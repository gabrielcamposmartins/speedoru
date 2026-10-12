extends SceneTree
## Capturas de tela de Las Vegas para conferência visual (com janela, não entra na bateria de testes):
##   godot --path . -s res://tests/las_vegas_shots.gd -- <pasta de saída> [horário] [ambiente] [prefixo]
## Gera a pista e salva PNGs de vários pontos de vista (grid, Sphere, Strip com a Torre Eiffel e as
## fontes do Bellagio, High Roller, as placas famosas, um dirigível, a cobertura de LED e vistas
## do alto).

var scene: Node3D
var track: RaceTrack
var cam: Camera3D
var out_dir := ""
var prefix := "vegas"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	RaceSettings.time_of_day = int(args[1]) if args.size() > 1 and args[1].is_valid_int() else 0
	RaceSettings.biome = int(args[2]) if args.size() > 2 and args[2].is_valid_int() else 0
	prefix = args[3] if args.size() > 3 and not args[3].begins_with("--") else "vegas"
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_vegas_shots_profile.cfg"
		profile.reset_profile()
	scene = (load("res://scenes/tracks/las_vegas.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	track = scene.get_node("Track")
	_run.call_deferred()


## Câmera em s (m) da pista, deslocada (lateral, altura, para trás) e olhando para um ponto.
func _at_track(s: float, lateral: float, height: float, back: float, look_ahead: float, look_lat := 0.0, look_h := 1.0) -> Transform3D:
	var p := track.path
	var f := p.frame_at(s - back, lateral, height)
	var target := p.frame_at(s + look_ahead, look_lat, look_h).origin
	return Transform3D(Basis.looking_at(target - f.origin), f.origin)


func _look(eye: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(at - eye), eye)


func _shot(name: String, xf: Transform3D, fov := 70.0) -> void:
	cam.global_transform = xf
	cam.fov = fov
	for k in 25:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("%s_%s.png" % [prefix, name]))
	print("captura: ", name)


func _landmark(n: String) -> Node3D:
	return track.find_child(n, true, false) as Node3D


func _run() -> void:
	while not track.is_built:
		await process_frame
	for n in ["HUD"]:
		var node := scene.get_node_or_null(n)
		if node:
			node.queue_free()
	cam = Camera3D.new()
	cam.far = 12000.0
	scene.add_child(cam)
	cam.current = true
	var outline := scene.get_node_or_null("RaceCamera/Outline")
	if outline:
		outline.reparent(cam, false)
	for k in 60:
		await process_frame
	await _shot("grid", _at_track(-40.0, 0.0, 2.6, 0.0, 60.0))
	await _shot("curva1", _at_track(150.0, 0.0, 2.4, 0.0, 70.0))
	await _shot("koval", _at_track(800.0, 0.0, 2.4, 0.0, 120.0))
	await _shot("sands", _at_track(1700.0, 0.0, 2.4, 0.0, 90.0))
	await _shot("sphere_chegada", _at_track(2300.0, 0.0, 2.4, 0.0, 120.0))
	await _shot("sphere_chicane", _at_track(2470.0, 0.0, 2.6, 0.0, 60.0))
	await _shot("strip_entrada", _at_track(3160.0, 0.0, 2.4, 0.0, 150.0))
	await _shot("strip", _at_track(3800.0, 0.0, 2.4, 0.0, 150.0))
	await _shot("strip_bellagio", _at_track(4300.0, 0.0, 2.4, 0.0, 150.0))
	await _shot("harmon", _at_track(5300.0, 0.0, 2.4, 0.0, 120.0))
	var sphere := _landmark("Sphere")
	var eiffel := _landmark("EiffelTower") as MeshInstance3D
	var wheel := _landmark("HighRoller")
	var fountain := _landmark("BellagioFountains") as MultiMeshInstance3D
	if sphere:
		var c := sphere.global_position
		await _shot("sphere_perto", _look(c + Vector3(260, 40, 160), c + Vector3(0, 10, 0)), 55.0)
	if wheel:
		var c := wheel.global_position
		await _shot("high_roller", _look(c + wheel.global_basis.x * 320.0 + Vector3(0, 60, 0), c + Vector3(0, 80, 0)), 55.0)
	if eiffel:
		var b := eiffel.get_aabb().get_center()
		await _shot("eiffel", _look(b + Vector3(220, 30, -160), b + Vector3(0, 40, 0)), 55.0)
	if fountain:
		await _shot("fontes", _look(Vector3(-430, 40, 600), Vector3(-640, 10, 760)), 60.0)
	# Placas famosas, vistas da pista mais perto de cada uma
	for n in CityNeon.FAMOUS:
		var node := track.find_child((n as String).capitalize().replace(" ", ""), true, false) as Node3D
		if node == null:
			continue
		var at := node.global_position
		var eye := at + node.global_basis.z * 38.0 + node.global_basis.x * 8.0 + Vector3.UP * 5.0
		await _shot("famosa_" + n, _look(eye, at + Vector3.UP * 11.0), 55.0)
	var blimp := track.find_child("Blimp0", true, false) as Node3D
	if blimp:
		var bp := blimp.global_position
		await _shot("dirigivel", _look(bp + blimp.global_basis.x * 90.0 + Vector3(0, -25, 0), bp), 50.0)
	var canopy := track.find_child("LedCanopy", true, false) as MeshInstance3D
	if canopy:
		var cc := canopy.get_aabb().get_center()
		await _shot("cobertura_led", _look(cc + Vector3(0, -14, 0) + canopy.get_aabb().size.normalized() * Vector3(1, 0, 1) * 60.0, cc), 70.0)
	await _shot("alto_strip", _look(Vector3(-200, 650, 1700), Vector3(-200, 0, 0)), 60.0)
	await _shot("alto_geral", _look(Vector3(1600, 1400, 1600), Vector3(0, 0, 0)), 55.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_vegas_shots_profile.cfg"))
	quit()
