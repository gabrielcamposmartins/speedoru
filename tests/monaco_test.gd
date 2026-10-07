extends SceneTree
## Teste do circuito de Mônaco (sem janela):
##   godot --headless --path . -s res://tests/monaco_test.gd
## Gera a pista e a cidade e confere: comprimento e desnível do traçado real, pisos (raycast) no
## grid, nos boxes, na subida e no túnel, o túnel coberto, a cidade (prédios, cais, mar e barcos)
## e um carro parado na rampa do Beau Rivage e no grampo (sem afundar nem escorregar).

var scene: Node3D
var track: RaceTrack
var car: F1Car
var failures := 0


func _initialize() -> void:
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_monaco_profile.cfg"
		profile.reset_profile()
	scene = (load("res://scenes/tracks/monaco.tscn") as PackedScene).instantiate()
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


func _surface_at(pos: Vector3) -> int:
	var space := track.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos - Vector3.UP * 3.0))
	if hit.is_empty():
		return -1
	return TrackSurface.of_body(hit.collider)


func _run() -> void:
	while not track.is_built:
		await process_frame
	await _frames(3)
	var p := track.path
	print("Comprimento: %.0f m, %d amostras" % [p.length, p.size()])
	_check(absf(p.length - 3300.0) < 40.0, "comprimento perto dos 3.337 m reais (linha central do OSM)")
	var lo := INF
	var hi := -INF
	for v in p.points:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	print("Elevação: %.1f a %.1f m" % [lo, hi])
	_check(hi - lo > 38.0 and hi - lo < 46.0, "desnível de ~42 m (porto ao Casino)")
	_check(p.height_at(900.0) > 40.0, "Casino lá em cima (%.1f m)" % p.height_at(900.0))
	_check(p.height_at(2640.0) < 4.0, "Piscine junto ao mar (%.1f m)" % p.height_at(2640.0))
	# Pisos
	_check(_surface_at(p.position_at(60.0)) == TrackSurface.Type.ASPHALT, "asfalto na reta dos boxes")
	_check(_surface_at(p.position_at(500.0)) == TrackSurface.Type.ASPHALT, "asfalto na subida do Beau Rivage")
	_check(_surface_at(p.position_at(1700.0)) == TrackSurface.Type.ASPHALT, "asfalto dentro do túnel")
	var vi := p.index_at(500.0)
	while track.kerb[0][vi] > 0.01 or track.barrier[0][vi] < 1.2:
		vi += 3
	_check(_surface_at(track.edge_point(vi, 1, track.barrier[0][vi] * 0.6)) == TrackSurface.Type.RUNOFF,
		"faixa asfaltada até a barreira é área de escape (fora da pista para os limites)")
	var grid_ok := true
	for slot in 12:
		grid_ok = grid_ok and _surface_at(track.get_grid_transform(slot).origin) == TrackSurface.Type.ASPHALT
	_check(grid_ok, "posições do grid no asfalto")
	var boxes_ok := true
	for g in track.layout.garage_count:
		boxes_ok = boxes_ok and _surface_at(track.get_pit_box_transform(g).origin) == TrackSurface.Type.ASPHALT
	_check(boxes_ok, "vagas dos boxes na pista dos boxes")
	# Túnel coberto: o terreno/laje fica acima do teto
	var city := track.city
	_check(city != null and city.tunnel.y - city.tunnel.x > 300.0, "túnel de %.0f m" % (city.tunnel.y - city.tunnel.x))
	var mid := (city.tunnel.x + city.tunnel.y) * 0.5
	var above := p.position_at(mid)
	var over := city.height_at(above.x, above.z)
	print("  túnel: pista a %.1f m, chão por cima a %.1f m" % [above.y, over])
	_check(over > above.y + 7.0, "terreno passa por cima do túnel")
	var gen := track.get_node("Generated")
	_check(gen.find_child("Tunnel", true, false) != null, "estrutura do túnel")
	var blocks := gen.find_child("Buildings", true, false)
	_check(blocks != null and blocks.get_child_count() > 8, "prédios em blocos (%d)" % (blocks.get_child_count() if blocks else 0))
	_check(gen.find_child("Quays", true, false) != null, "muros do cais")
	var boats := 0
	var harbour := gen.find_child("Harbour", true, false)
	if harbour:
		for mmi in harbour.find_children("Boats_*", "MultiMeshInstance3D", true, false):
			boats += (mmi as MultiMeshInstance3D).multimesh.instance_count
	_check(boats > 150, "barcos no porto e fundeados (%d)" % boats)
	_check(harbour != null and harbour.find_child("Sea", true, false) != null, "mar com shader de água")
	# Nenhum prédio sobre a pista: raycast de cima não acha prédio no meio da pista (só fora do túnel)
	var blocked := 0
	var space := track.get_world_3d().direct_space_state
	for s in range(0, int(p.length), 10):
		if city.in_tunnel(s, 10.0):
			continue
		var pos := p.position_at(s)
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 60.0, pos + Vector3.UP * 0.5)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			blocked += 1
			print("    s=%d: %s a %.1f m acima" % [s, hit.collider.get_path(), hit.position.y - pos.y])
	_check(blocked == 0, "nada com colisão sobre a pista fora do túnel (%d pontos)" % blocked)
	# Nenhuma planta de prédio cobre a pista (fora do túnel, onde eles ficam em cima da laje)
	var covering := 0
	for bld in city.data["buildings"]:
		var pts: Array = bld["p"]
		var poly := PackedVector2Array()
		for k in range(0, pts.size(), 2):
			poly.append(Vector2(pts[k], pts[k + 1]))
		for i in range(0, p.size(), 2):
			if city.in_tunnel(p.s_at(i), 1.0):
				continue
			var q := Vector2(p.points[i].x, -p.points[i].z)
			if Geometry2D.is_point_in_polygon(q, poly):
				covering += 1
				print("    prédio sobre a pista em s=%.0f: %s" % [p.s_at(i), bld.get("n", "")])
				break
	_check(covering == 0, "nenhum prédio sobre a pista fora do túnel")
	await _parked_test(500.0, "rampa do Beau Rivage")
	await _parked_test(1253.0, "grampo do Grand Hotel")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_monaco_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)


## Carro parado (freio de mão) numa rampa: não afunda nem desliza.
func _parked_test(s: float, label: String) -> void:
	var xf := track.path.frame_at(s, 0.0, 0.3)
	car.global_transform = xf
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.throttle_input = 0.0
	car.brake_input = 1.0
	await _physics(240)
	var pr := track.path.project(car.global_position)
	var height := car.global_position.y - track.path.position_at(pr.x).y
	var moved := fposmod(pr.x - s + track.path.length * 0.5, track.path.length) - track.path.length * 0.5
	print("  %s: altura %.2f m, andou %.2f m" % [label, height, moved])
	_check(height > -0.2 and height < 1.0, "carro apoiado na pista na %s" % label)
	_check(absf(moved) < 1.5, "carro freado não desliza na %s" % label)


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _physics(n: int) -> void:
	for k in n:
		await physics_frame
