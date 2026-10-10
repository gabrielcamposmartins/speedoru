extends SceneTree
## Teste do circuito de Suzuka (sem janela):
##   godot --headless --path . -s res://tests/suzuka_test.gd
## Gera a pista e confere: comprimento e desnível, o cruzamento em viaduto (folga entre os níveis,
## projeção na pista certa em cima e embaixo, nada com colisão sobre a pista de baixo além da ponte),
## pisos (raycast) no grid, nos boxes e nos dois níveis do cruzamento, o terreno abaixo do asfalto e
## um carro parado em cima da ponte e embaixo dela (sem afundar nem escorregar).

var scene: Node3D
var track: RaceTrack
var car: F1Car
var failures := 0


func _initialize() -> void:
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_suzuka_profile.cfg"
		profile.reset_profile()
	scene = (load("res://scenes/tracks/suzuka.tscn") as PackedScene).instantiate()
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


## Primeiro piso de cima para baixo a partir de `from` (até 4 m abaixo de pos): tipo, altura e nome.
func _hit_below(pos: Vector3, from := 3.0) -> Dictionary:
	var space := track.get_world_3d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * from, pos - Vector3.UP * 4.0))


func _surface_at(pos: Vector3, from := 3.0) -> int:
	var hit := _hit_below(pos, from)
	if hit.is_empty():
		return -1
	return TrackSurface.of_body(hit.collider)


func _run() -> void:
	while not track.is_built:
		await process_frame
	await _frames(3)
	var p := track.path
	print("Comprimento: %.0f m, %d amostras" % [p.length, p.size()])
	_check(absf(p.length - 5807.0) < 30.0, "comprimento perto dos 5.807 m reais")
	var lo := INF
	var hi := -INF
	for v in p.points:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	print("Elevação: %.1f a %.1f m" % [lo, hi])
	_check(hi - lo > 28.0 and hi - lo < 45.0, "desnível de ~34 m (curva 2 à Degner)")
	# Cruzamento
	_check(p.crossings.size() == 1, "um cruzamento (%d)" % p.crossings.size())
	if p.crossings.is_empty():
		_finish()
		return
	var c := p.crossings[0]
	var low := p.position_at(c.x)
	var up := p.position_at(c.y)
	print("  cruzamento: s=%.0f (%.1f m) sob s=%.0f (%.1f m), %.0f°" % [c.x, low.y, c.y, up.y, rad_to_deg(c.z)])
	_check(up.y - low.y > 9.5, "folga de %.1f m entre os níveis" % (up.y - low.y))
	var pr_low := p.project(low + Vector3.UP * 0.4)
	var pr_up := p.project(up + Vector3.UP * 0.4)
	_check(absf(pr_low.x - c.x) < 3.0, "projeção embaixo da ponte fica no trecho de baixo (s=%.0f)" % pr_low.x)
	_check(absf(pr_up.x - c.y) < 3.0, "projeção em cima da ponte fica no trecho de cima (s=%.0f)" % pr_up.x)
	# Os dois níveis: asfalto em cima; embaixo, raio de dentro do vão também acha asfalto
	_check(_surface_at(up) == TrackSurface.Type.ASPHALT, "asfalto em cima da ponte")
	var under := _hit_below(low, 3.0)
	_check(not under.is_empty() and TrackSurface.of_body(under.collider) == TrackSurface.Type.ASPHALT
		and absf(under.position.y - low.y) < 0.2, "asfalto embaixo da ponte")
	# Nada com colisão sobre a pista de baixo fora da ponte; sob a ponte, o vão livre
	var space := track.get_world_3d().direct_space_state
	var blocked := 0
	for s in range(0, int(p.length), 6):
		for lat: float in [-4.0, 0.0, 4.0]:
			var pos := p.position_at(s, lat)
			var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.UP * 6.0)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				blocked += 1
				if blocked <= 6:
					print("    s=%d lat %.0f: %s a %.1f m acima" % [s, lat, hit.collider.get_path(), hit.position.y - pos.y])
	_check(blocked == 0, "vão livre de 6 m sobre a pista toda (%d pontos)" % blocked)
	# Nada acima do asfalto (muro do corte, topo, laje): de 1,2 m acima, o primeiro piso é a pista
	var bumps := 0
	for s in range(0, int(p.length), 2):
		for lat: float in [-0.85, 0.0, 0.85]:
			var i := p.index_at(s)
			var pos := p.position_at(s, lat * p.half_width(i, 1 if lat > 0.0 else -1))
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.2, pos - Vector3.UP * 0.5))
			if hit.is_empty() or hit.collider is RigidBody3D:
				continue
			var type := TrackSurface.of_body(hit.collider)
			if not type in [TrackSurface.Type.ASPHALT, TrackSurface.Type.KERB] or hit.position.y > pos.y + 0.08:
				bumps += 1
				if bumps <= 6:
					print("    s=%d lat %.2f: %s a %.2f m" % [s, lat, (hit.collider as Node).name, hit.position.y - pos.y])
	_check(bumps == 0, "nada acima do asfalto na pista toda (%d pontos)" % bumps)
	# Terreno nunca acima do asfalto
	var poking := 0
	var worst := 0.0
	for i in range(0, p.size(), 2):
		for lat: float in [-0.9, -0.5, 0.0, 0.5, 0.9]:
			var side := 1 if lat > 0.0 else -1
			var pos: Vector3 = p.points[i] + p.lefts[i] * lat * p.half_width(i, side)
			var g := track.terrain.height_at(pos.x, pos.z)
			if g > pos.y + TrackRoad.ROAD_Y - 0.01:
				poking += 1
				worst = maxf(worst, g - pos.y)
	_check(poking == 0, "terreno abaixo do asfalto (%d pontos, pior %.2f m)" % [poking, worst])
	# Grid e boxes
	var grid_ok := true
	for slot in 20:
		grid_ok = grid_ok and _surface_at(track.get_grid_transform(slot).origin) == TrackSurface.Type.ASPHALT
	_check(grid_ok, "posições do grid no asfalto")
	var boxes_ok := true
	for g in track.layout.garage_count:
		boxes_ok = boxes_ok and _surface_at(track.get_pit_box_transform(g).origin) == TrackSurface.Type.ASPHALT
	_check(boxes_ok, "vagas dos boxes na pista dos boxes")
	var gen := track.get_node("Generated")
	_check(gen.find_child("Bridge*", true, false) != null, "estrutura da ponte")
	await _parked_test(c.y, "em cima da ponte")
	await _parked_test(c.x, "embaixo da ponte")
	await _parked_test(2200.0, "na subida da Degner")
	_finish()


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_suzuka_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)


## Carro parado (freio de mão) em s: assenta na pista certa (sem afundar) e não desliza.
func _parked_test(s: float, label: String) -> void:
	car.global_transform = track.path.frame_at(s, 0.0, 0.3)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.throttle_input = 0.0
	car.brake_input = 1.0
	car.reset_physics_interpolation()
	await _physics(240)
	var pr := track.path.project(car.global_position)
	var height := car.global_position.y - track.path.position_at(pr.x, pr.y).y
	var moved := fposmod(pr.x - s + track.path.length * 0.5, track.path.length) - track.path.length * 0.5
	print("  %s: altura %.2f m, andou %.2f m" % [label, height, moved])
	_check(height > -0.2 and height < 1.0, "carro apoiado na pista %s" % label)
	_check(absf(moved) < 1.5, "carro freado não desliza %s" % label)


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _physics(n: int) -> void:
	for k in n:
		await physics_frame
