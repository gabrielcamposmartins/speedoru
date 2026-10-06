extends SceneTree
## Capturas do circuito (precisa de janela):
##   godot --path . -s res://tests/capture_track.gd -- <pasta de saída>
## Gera imagens de vários pontos: grid, boxes, chicane, Parabolica, arquibancadas e vista aérea.

var out_dir := "user://captures"
## Segundo argumento "quick": só as fotos principais (para ajustar iluminação).
var quick := false
var scene: Node3D
var track: RaceTrack
var cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	quick = args.size() > 1 and args[1] == "quick"
	DirAccess.make_dir_recursive_absolute(out_dir)
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	scene = (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	track = scene.get_node("Track")
	(scene.get_node("F1Car") as F1Car).player_controlled = false
	_run.call_deferred()


## Câmera livre: posição em (s, lateral, altura) olhando para (s, lateral, altura).
func _shot(file: String, s0: float, lat0: float, h0: float, s1: float, lat1: float, h1: float, fov := 60.0) -> void:
	var p := track.path
	var from := p.position_at(s0, lat0) + Vector3.UP * h0
	var to := p.position_at(s1, lat1) + Vector3.UP * h1
	cam.global_transform = Transform3D(Basis(), from).looking_at(to, Vector3.UP)
	cam.fov = fov
	await _frames(12)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(file))
	print("salvo ", file)


func _run() -> void:
	await _frames(20)
	var race_cam := scene.get_node("RaceCamera") as Camera3D
	scene.get_node("HUD").visible = false
	race_cam.get_node("Outline").reparent(root)
	cam = Camera3D.new()
	cam.far = 5000.0
	root.add_child(cam)
	var outline := root.get_node("Outline") as Node3D
	outline.reparent(cam, false)
	cam.current = true
	var p := track.path
	if quick:
		await _shot("02_pits.png", -60.0, -13.0, 7.0, 40.0, -18.0, 3.0, 65.0)
		await _shot("05_parabolica.png", 5000.0, -15.0, 25.0, 4900.0, 30.0, 0.0, 65.0)
		await _shot("06_lesmo.png", 2120.0, 0.0, 4.0, 2230.0, 5.0, 1.0, 60.0)
		outline.reparent(race_cam, false)
		race_cam.current = true
		await _frames(30)
		root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("10_chase.png"))
		quit()
		return
	await _shot("01_grid.png", -40.0, 0.0, 3.0, 40.0, 0.0, 1.0, 65.0)
	await _shot("02_pits.png", -60.0, -13.0, 7.0, 40.0, -18.0, 3.0, 65.0)
	await _shot("03_main_stand.png", 60.0, -2.0, 2.0, -20.0, 18.0, 6.0, 60.0)
	await _shot("04_chicane.png", 520.0, 0.0, 6.0, 640.0, 0.0, 0.0, 60.0)
	await _shot("05_parabolica.png", 5000.0, -15.0, 25.0, 4900.0, 30.0, 0.0, 65.0)
	await _shot("06_lesmo.png", 2120.0, 0.0, 4.0, 2230.0, 5.0, 1.0, 60.0)
	await _shot("07_ascari.png", 3560.0, 0.0, 3.0, 3680.0, 0.0, 1.0, 60.0)
	await _shot("08_crowd.png", -5.0, 1.0, 1.5, -5.0, 24.0, 5.0, 45.0)
	await _shot("12_grass.png", 3300.0, 12.0, 1.2, 3330.0, 30.0, 0.0, 70.0)
	await _shot("13_horizon.png", 2600.0, 0.0, 3.0, 2700.0, 0.0, 6.0, 70.0)
	await _shot("14_hills.png", 1500.0, -40.0, 60.0, 1500.0, -600.0, 40.0, 70.0)
	await _shot("15_flags.png", 40.0, 2.0, 4.0, -40.0, 22.0, 14.0, 70.0)
	await _shot("16_sky.png", 300.0, 0.0, 2.0, 700.0, 0.0, 120.0, 75.0)
	await _shot("17_gravel.png", 4950.0, 9.0, 1.6, 4975.0, 22.0, 0.0, 60.0)
	await _shot("18_paddock.png", -80.0, -45.0, 6.0, 40.0, -60.0, 1.0, 65.0)
	await _shot("19_behind_stand.png", 300.0, 40.0, 3.0, 400.0, 34.0, 1.0, 65.0)
	await _shot("20_low_blimp.png", 1150.0, 0.0, 3.0, 1250.0, 0.0, 60.0, 75.0)
	for target in ["Flock0", "LowBlimp0", "PassBlimp0"]:
		var node := scene.find_child(target, true, false) as Node3D
		if node:
			var at := node.global_position
			var from := at + Vector3(-30.0, -12.0, -30.0) * (1.0 if target == "Flock0" else 3.0)
			cam.global_transform = Transform3D(Basis(), from).looking_at(at, Vector3.UP)
			cam.fov = 60.0
			await _frames(6)
			root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("21_%s.png" % target))
	# Vista aérea do circuito inteiro (sem neblina para enxergar o traçado)
	(scene.find_child("WorldEnvironment", true, false) as WorldEnvironment).environment.fog_enabled = false
	var r := p.bounds()
	cam.global_transform = Transform3D(Basis(), Vector3(r.get_center().x + 600, 2600, r.get_center().y + 2600)).looking_at(
		Vector3(r.get_center().x, 0, r.get_center().y), Vector3.UP)
	cam.fov = 60.0
	await _frames(12)
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("09_aerial.png"))
	print("salvo 09_aerial.png")
	(scene.find_child("WorldEnvironment", true, false) as WorldEnvironment).environment.fog_enabled = true
	# Câmera do jogo atrás do carro no grid + medição de desempenho
	outline.reparent(race_cam, false)
	race_cam.current = true
	await _frames(30)
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("10_chase.png"))
	print("salvo 10_chase.png")
	await _measure("grid (câmera do jogo)")
	cam.current = true
	outline.reparent(cam, false)
	await _shot("11_far.png", 300.0, 8.0, 6.0, -300.0, 0.0, 2.0, 70.0)
	await _measure("reta olhando a tribuna")
	quit()


func _measure(label: String) -> void:
	await _frames(10)
	var t0 := Time.get_ticks_usec()
	await _frames(120)
	var ms := (Time.get_ticks_usec() - t0) / 120000.0
	print("Desempenho %s: %.2f ms/quadro (%.0f FPS), draw calls %d, primitivas %d" % [label, ms, 1000.0 / ms,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _frames(n: int) -> void:
	for i in n:
		await process_frame
