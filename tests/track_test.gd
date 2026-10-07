extends SceneTree
## Teste do circuito (sem janela):
##   godot --headless --path . -s res://tests/track_test.gd
## Gera Monza, confere comprimento, elementos, pisos (raycast) e o efeito da brita e da
## barreira no carro.

var scene: Node3D
var track: RaceTrack
var car: F1Car
var failures := 0


func _initialize() -> void:
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	scene = (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	scene.set("start_light_sequence", false)
	root.add_child(scene)
	track = scene.get_node("Track")
	car = scene.get_node("F1Car")
	car.player_controlled = false
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _run() -> void:
	await _frames(5)
	var p := track.path
	print("Comprimento: %.0f m, %d amostras" % [p.length, p.size()])
	_check(absf(p.length - 5793.0) < 40.0, "comprimento perto dos 5.793 m reais")
	_report_nodes()
	_check(track.start_lights != null, "pórtico com luzes de largada")
	# Pisos sob pontos conhecidos
	_check(_surface_at(p.position_at(100.0)) == TrackSurface.Type.ASPHALT, "asfalto no meio da reta")
	_check(_surface_at(track.get_grid_transform(track.layout.grid_slots - 1).origin) == TrackSurface.Type.ASPHALT,
		"última posição do grid no asfalto")
	var boxes_ok := true
	for g in track.layout.garage_count:
		boxes_ok = boxes_ok and _surface_at(track.get_pit_box_transform(g).origin) == TrackSurface.Type.ASPHALT
	_check(boxes_ok, "vagas dos boxes na pista dos boxes")
	var kerb_found := false
	var gravel_found := false
	for i in p.size():
		if track.kerb[0][i] > 0.9 and not kerb_found:
			kerb_found = _surface_at(track.edge_point(i, 1, track.layout.kerb_width * 0.5)) == TrackSurface.Type.KERB
		if track.gravel[0][i] > 15.0 and not gravel_found:
			gravel_found = _surface_at(track.edge_point(i, 1, track.layout.kerb_width * track.kerb[0][i] + 6.0)) == TrackSurface.Type.GRAVEL
	_check(kerb_found, "zebra com colisão própria")
	_check(gravel_found, "brita com colisão própria")
	_check(_surface_at(track.edge_point(p.index_at(100.0), 1, 2.0) + Vector3(0, 0, 0)) == TrackSurface.Type.GRASS
		or track.barrier[0][p.index_at(100.0)] < 2.0, "grama fora da pista")

	_terrain_checks()
	await _launch_test()
	await _kerb_test()
	await _gravel_test()
	await _barrier_test()
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)


func _report_nodes() -> void:
	var crowd := 0
	var trees := 0
	var tris := 0
	for n in track.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (n as MultiMeshInstance3D).multimesh
		if n.name == "Crowd":
			crowd += mm.instance_count
		elif str(n.name).begins_with("Trees"):
			trees += mm.instance_count
	for n in track.find_children("*", "MeshInstance3D", true, false):
		var mesh := (n as MeshInstance3D).mesh
		if mesh is ArrayMesh:
			for s in mesh.get_surface_count():
				tris += (mesh as ArrayMesh).surface_get_array_len(s) / 3
	var stands := track.find_child("Grandstands", true, false)
	print("Arquibancadas: %d, público: %d, árvores: %d, triângulos estáticos: %d" % [
		stands.get_child_count() if stands else 0, crowd, trees, tris])
	_check(crowd > 10000, "público nas arquibancadas")
	_check(trees > 2000, "árvores")


func _surface_at(pos: Vector3) -> int:
	var space := track.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos - Vector3.UP * 3.0))
	if hit.is_empty():
		return -1
	return TrackSurface.of_body(hit.collider)


## Carro a 150 km/h em linha reta, sem acelerar: compara a desaceleração no asfalto e na brita.
func _gravel_test() -> void:
	var p := track.path
	var best := -1
	for i in p.size():
		if track.gravel[0][i] > 20.0 and absf(p.curvature[i]) < 0.004:
			best = i
			break
	if best < 0:
		_check(false, "achar trecho reto com brita")
		return
	var decel_asphalt := await _coast(p.frame_at(100.0, 0.0, 0.1))
	var lateral := p.width_left[best] + track.layout.kerb_width * track.kerb[0][best] + 1.0 + track.gravel[0][best] * 0.5
	var xf := p.frame_at(p.s_at(best) - 0.0, lateral, 0.1)
	var decel_gravel := await _coast(xf)
	print("Desaceleração rolando (150 km/h, 0,5 s): asfalto %.1f m/s², brita %.1f m/s²" % [decel_asphalt, decel_gravel])
	# Brita segura mais que o asfalto, mas sem "atolar" (resistência moderada, TrackSurface.DRAG)
	_check(decel_gravel > decel_asphalt + 1.5, "brita segura o carro")


func _coast(xf: Transform3D) -> float:
	car.global_transform = xf
	car.reset_physics_interpolation()
	car.throttle_input = 0.0
	car.brake_input = 0.0
	car.steer_input = 0.0
	await physics_frame
	car.linear_velocity = xf.basis.z * (150.0 / 3.6)
	car.angular_velocity = Vector3.ZERO
	await _physics(30)
	var v0 := car.linear_velocity.length()
	await _physics(60)
	return (v0 - car.linear_velocity.length()) / 0.5


## Joga o carro contra a barreira e confere que ele não atravessa.
func _barrier_test() -> void:
	var p := track.path
	var i := p.index_at(3000.0)
	var side := 1
	var start := track.edge_point(i, side, -2.0, 0.1)
	var dir := (p.lefts[i] * 0.8 + p.tangents[i] * 0.6).normalized()
	car.global_transform = Transform3D(Basis.looking_at(-dir), start)
	car.reset_physics_interpolation()
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	await _physics(30)
	car.linear_velocity = dir * 30.0
	car.angular_velocity = Vector3.ZERO
	var max_lateral := -INF
	for k in 240:
		await physics_frame
		max_lateral = maxf(max_lateral, p.project(car.global_position).y)
	var limit := p.width_left[i] + track.barrier[0][i]
	print("Batida na barreira a 108 km/h: centro do carro chegou a %.1f m (face da barreira em %.1f m)" % [max_lateral, limit])
	# O centro do carro para a ~3 m da face (bico e roda batem antes)
	_check(max_lateral > limit - 4.0 and max_lateral < limit, "carro bate e não atravessa a barreira")


## O terreno tem que ser plano sob tudo o que foi construído e subir longe da pista.
func _terrain_checks() -> void:
	var t := track.terrain
	var p := track.path
	var worst := 0.0
	for i in range(0, p.size(), 3):
		for side in [1, -1]:
			var q := track.edge_point(i, side, track.structure_extent(i, side) - p.half_width(i, side) - 2.0)
			worst = maxf(worst, t.height_at(q.x, q.z))
	print("Terreno: %.0f..%.0f m na grade; maior altura sob estruturas %.2f m" % [t.min_height, t.max_height, worst])
	_check(worst < 0.05, "terreno plano sob pista, barreiras, arquibancadas e boxes")
	_check(t.max_height > 80.0, "relevo (colinas) ao redor do parque")
	# Ponto nas colinas, dentro da grade (entre amostras, para testar a interpolação)
	var probe := Vector2(t.origin.x + 203.0, t.center.y + 37.0)
	var hit := track.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(probe.x, 2000.0, probe.y), Vector3(probe.x, -10.0, probe.y)))
	var expected := t.height_at(probe.x, probe.y)
	_check(not hit.is_empty() and absf(hit.position.y - expected) < 1.0,
		"colisão do relevo acompanha a malha (%.1f m vs %.1f m)" % [hit.position.y if hit else -1.0, expected])


## Largada do grid: acelera 8 s na reta principal sem sair do asfalto.
func _launch_test() -> void:
	var p := track.path
	car.global_transform = track.get_grid_transform(0)
	car.reset_physics_interpolation()
	await physics_frame
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.throttle_input = 1.0
	var off := false
	for k in 960:
		await physics_frame
		for surf in car.tire_surface:
			off = off or surf != TrackSurface.Type.ASPHALT
	car.throttle_input = 0.0
	var pr := p.project(car.global_position)
	print("Largada: %.0f km/h após 8 s, %.0f m percorridos, lateral %.1f m" % [car.speed_kmh, pr.x + 6.0, pr.y])
	_check(car.speed_kmh > 250.0 and not off, "largada limpa na reta principal")


## Passa por cima da zebra na diagonal a 90 km/h: o carro não pode decolar nem capotar.
func _kerb_test() -> void:
	var p := track.path
	var best := -1
	for i in p.size():
		if track.kerb[0][i] > 0.99 and track.kerb[0][(i + 15) % p.size()] > 0.99 and absf(p.curvature[i]) < 0.02:
			best = i
			break
	var xf := p.frame_at(p.s_at(best), p.width_left[best] - 3.0, 0.1)
	var dir := (p.tangents[best] + p.lefts[best] * 0.25).normalized()
	car.global_transform = Transform3D(Basis.looking_at(-dir), xf.origin)
	car.reset_physics_interpolation()
	await physics_frame
	car.linear_velocity = dir * 25.0
	car.angular_velocity = Vector3.ZERO
	var max_up := 0.0
	var on_kerb := false
	for k in 120:
		await physics_frame
		max_up = maxf(max_up, car.linear_velocity.y)
		on_kerb = on_kerb or TrackSurface.Type.KERB in car.tire_surface
	var upright := car.global_basis.y.y
	print("Zebra a 90 km/h: velocidade vertical máx. %.2f m/s, inclinação final %.2f" % [max_up, upright])
	_check(on_kerb and max_up < 1.5 and upright > 0.95, "zebra chacoalha mas não lança o carro")


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _physics(n: int) -> void:
	for k in n:
		await physics_frame
