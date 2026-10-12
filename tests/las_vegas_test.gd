extends SceneTree
## Teste do circuito de Las Vegas (sem janela):
##   godot --headless --path . -s res://tests/las_vegas_test.gd
## Gera a pista e a cidade e confere: comprimento do traçado real, pista plana, pisos (raycast) no
## grid, nos boxes e nas retas, a cidade (prédios, ruas, piscinas, palmeiras) sem mar, cais nem túnel,
## os marcos (Sphere, Torre Eiffel, High Roller, fontes do Bellagio), os terrenos preenchidos, os
## letreiros de neon e os postes, nada sobre a pista e um carro
## parado em duas curvas (sem afundar nem escorregar).

var scene: Node3D
var track: RaceTrack
var car: F1Car
var failures := 0


func _initialize() -> void:
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_vegas_profile.cfg"
		profile.reset_profile()
	scene = (load("res://scenes/tracks/las_vegas.tscn") as PackedScene).instantiate()
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
	_check(absf(p.length - 6200.0) < 80.0, "comprimento perto dos 6.201 m reais (linha central do OSM)")
	var lo := INF
	var hi := -INF
	for v in p.points:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	_check(hi - lo < 0.5, "pista plana no deserto (%.2f m de desnível)" % (hi - lo))
	# Pisos
	for s in [60.0, 1000.0, 2200.0, 4000.0, 5500.0]:
		_check(_surface_at(p.position_at(s)) == TrackSurface.Type.ASPHALT, "asfalto em s=%.0f" % s)
	var grid_ok := true
	for slot in 20:
		grid_ok = grid_ok and _surface_at(track.get_grid_transform(slot).origin) == TrackSurface.Type.ASPHALT
	_check(grid_ok, "posições do grid no asfalto")
	var boxes_ok := true
	for g in track.layout.garage_count:
		boxes_ok = boxes_ok and _surface_at(track.get_pit_box_transform(g).origin) == TrackSurface.Type.ASPHALT
	_check(boxes_ok, "vagas dos boxes na pista dos boxes")
	# Cidade sem mar nem túnel; marcos
	var city := track.city
	_check(city != null and not city.has_sea() and not city.has_tunnel() and city.modern(), "cidade no deserto (sem mar nem túnel, prédios modernos)")
	var gen := track.get_node("Generated")
	var blocks := gen.find_child("Buildings", true, false)
	_check(blocks != null and blocks.get_child_count() > 8, "prédios em blocos (%d)" % (blocks.get_child_count() if blocks else 0))
	_check(gen.find_child("Harbour", true, false) == null and gen.find_child("Tunnel", true, false) == null
		and gen.find_child("Offshore", true, false) == null, "sem porto, túnel nem navios")
	var marks := gen.find_child("Landmarks", true, false)
	_check(marks != null, "marcos da cidade")
	if marks:
		for n in ["Sphere", "EiffelTower", "HighRoller", "BellagioFountains"]:
			_check(marks.find_child(n, true, false) != null, "marco: %s" % n)
		var sphere := marks.find_child("Sphere", true, false) as MeshInstance3D
		if sphere:
			var c := sphere.global_position
			var nearest := INF
			for i in range(0, p.size(), 2):
				nearest = minf(nearest, Vector2(p.points[i].x - c.x, p.points[i].z - c.z).length())
			var radius := (sphere.mesh as SphereMesh).radius
			print("  Sphere: centro a %.0f m do eixo da pista, raio %.0f m" % [nearest, radius])
			_check(nearest - radius > 15.0 and nearest < 250.0, "a Sphere fica ao lado da pista, sem invadir")
	# Nada com colisão sobre a pista
	var blocked := 0
	var space := track.get_world_3d().direct_space_state
	for s in range(0, int(p.length), 10):
		var pos := p.position_at(s)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 60.0, pos + Vector3.UP * 0.5))
		if not hit.is_empty():
			blocked += 1
			print("    s=%d: %s a %.1f m acima" % [s, hit.collider.get_path(), hit.position.y - pos.y])
	_check(blocked == 0, "nada com colisão sobre a pista (%d pontos)" % blocked)
	var covering := 0
	for bld in city.data["buildings"]:
		var pts: Array = bld["p"]
		var poly := PackedVector2Array()
		for k in range(0, pts.size(), 2):
			poly.append(Vector2(pts[k], pts[k + 1]))
		for i in range(0, p.size(), 2):
			if Geometry2D.is_point_in_polygon(Vector2(p.points[i].x, -p.points[i].z), poly):
				covering += 1
				print("    prédio sobre a pista em s=%.0f: %s" % [p.s_at(i), bld.get("n", "")])
				break
	_check(covering == 0, "nenhum prédio sobre a pista")
	# Terrenos vazios preenchidos e as luzes da cidade (letreiros de neon e postes)
	var filled := 0
	var signed := 0
	for bld in city.data["buildings"]:
		filled += 1 if bld.get("f", 0) else 0
		signed += 1 if int(bld.get("v", 0)) > 0 else 0
	_check(filled > 300 and signed > 300, "prédios de preenchimento (%d) e com letreiro (%d)" % [filled, signed])
	var neon := gen.find_child("Neon", false, false)
	var signs := neon.find_child("SignArt", false, false) if neon else null
	var points: PackedVector3Array = signs.get_meta("points", PackedVector3Array()) if signs else PackedVector3Array()
	_check(neon != null and neon.find_child("NeonSigns", false, false) != null and points.size() > 300,
		"letreiros de neon (%d artes)" % points.size())
	_check(neon != null and neon.find_children("StreetPosts_*", "MultiMeshInstance3D", false, false).size() > 4, "postes nas ruas")
	var famous := 0
	for n in CityNeon.FAMOUS:
		famous += 1 if neon and neon.find_child((n as String).capitalize().replace(" ", ""), false, false) else 0
	_check(famous == CityNeon.FAMOUS.size(), "placas famosas (%d de %d)" % [famous, CityNeon.FAMOUS.size()])
	_check(neon != null and neon.find_children("Blimp*", "", true, false).size() >= 3 and neon.find_child("LedCanopy", false, false) != null,
		"dirigíveis e cobertura de LED")
	var reels := 0
	if neon:
		for mi in neon.find_children("*", "MeshInstance3D", true, false):
			reels += 1 if str(mi.get_meta("anim", "")).begins_with("reel:") else 0
	_check(reels > 10, "telões de LED animados (%d)" % reels)
	var over := 0
	for pt in points:
		var pr := p.project(pt, false)
		if pr.y != INF and absf(pr.y) < p.half_width(p.index_at(pr.x), 1 if pr.y >= 0.0 else -1) + 2.0:
			over += 1
			print("    letreiro sobre a pista em s=%.0f" % pr.x)
	_check(over == 0, "nenhum letreiro sobre a pista")
	await physics_frame
	var ray_space := track.get_world_3d().direct_space_state
	var on_track := 0
	var total := 0
	for mmi in gen.find_children("*", "MultiMeshInstance3D", true, false):
		if not mmi.has_meta("points"):
			continue
		for pos: Vector3 in (mmi.get_meta("points") as PackedVector3Array):
			total += 1
			var hit := ray_space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3(0, 6, 0), pos + Vector3(0, -4, 0)))
			if hit.is_empty() or String((hit["collider"] as Node).name) in ["GroundCollision", "Ground"]:
				continue
			on_track += 1
			if on_track <= 5:
				var pr := p.project(pos, false)
				print("    %s sobre %s em s=%.0f (lateral %.1f)" % [mmi.name, (hit["collider"] as Node).name, pr.x, pr.y])
	_check(total > 500 and on_track == 0, "nenhuma árvore nem objeto sobre a pista, escapes, boxes ou barreiras (%d de %d)" % [on_track, total])
	await _parked_test(225.0, "curva 1")
	await _parked_test(3135.0, "entrada da Strip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_vegas_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)


## Carro parado (freio de mão) numa curva: não afunda nem desliza.
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
