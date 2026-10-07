extends SceneTree
## Capturas de tela de Mônaco para conferência visual (com janela, não entra na bateria de testes):
##   godot --path . -s res://tests/monaco_shots.gd -- <pasta de saída>
## Gera a pista e salva PNGs de vários pontos de vista (grid, porto, Casino, túnel, grampo...).

var scene: Node3D
var track: RaceTrack
var cam: Camera3D
var out_dir := ""
var prefix := "monaco"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	# Opcional: horário e ambiente (índices de DaylightPresets) e um prefixo para os arquivos
	RaceSettings.time_of_day = int(args[1]) if args.size() > 1 else 0
	RaceSettings.biome = int(args[2]) if args.size() > 2 else 0
	prefix = args[3] if args.size() > 3 else "monaco"
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_shots_profile.cfg"
		profile.reset_profile()
	scene = (load("res://scenes/tracks/monaco.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	track = scene.get_node("Track")
	_run.call_deferred()


## Câmera em s (m) da pista, deslocada (lateral, altura, para trás) e olhando para um ponto.
func _at_track(s: float, lateral: float, height: float, back: float, look_ahead: float, look_lat := 0.0, look_h := 1.0) -> Transform3D:
	var p := track.path
	var f := p.frame_at(s - back, lateral, height)
	var target := p.frame_at(s + look_ahead, look_lat, look_h).origin
	return Transform3D(Basis.looking_at(target - f.origin), f.origin)


func _shot(name: String, xf: Transform3D, fov := 70.0) -> void:
	cam.global_transform = xf
	cam.fov = fov
	for k in 25:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("%s_%s.png" % [prefix, name]))
	print("captura: ", name)


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
	var p := track.path
	var c := track.city
	await _shot("grid", _at_track(-40.0, 0.0, 2.6, 0.0, 60.0))
	await _shot("porto_alto", Transform3D(Basis.looking_at(Vector3(250, 0, 0) - Vector3(-150, 220, 300)), Vector3(-150, 220, 300)), 60.0)
	await _shot("sainte_devote", _at_track(150.0, 0.0, 2.2, 0.0, 70.0))
	await _shot("beau_rivage", _at_track(430.0, -1.5, 2.0, 0.0, 90.0))
	await _shot("casino", _at_track(880.0, 0.0, 2.2, 0.0, 60.0))
	await _shot("casino_lado", _at_track(930.0, 12.0, 14.0, 0.0, 10.0, -20.0, 5.0))
	await _shot("grampo", _at_track(1200.0, 0.0, 3.0, 0.0, 55.0))
	await _shot("mirabeau_bas", _at_track(1300.0, 0.0, 2.2, 0.0, 40.0, 4.0, 3.0))
	await _shot("boxes", _at_track(-60.0, -10.0, 6.0, 30.0, 10.0, -18.0, 1.0))
	await _shot("portier", _at_track(1440.0, 0.0, 2.2, 0.0, 70.0))
	await _shot("tunel", _at_track((c.tunnel.x + c.tunnel.y) * 0.5, 0.0, 1.6, 0.0, 60.0))
	await _shot("saida_tunel", _at_track(c.tunnel.y - 20.0, 0.0, 1.8, 0.0, 80.0))
	await _shot("chicane", _at_track(2050.0, 0.0, 2.2, 0.0, 70.0))
	await _shot("piscine", _at_track(2420.0, 0.0, 2.4, 0.0, 70.0, 6.0))
	await _shot("rascasse", _at_track(2850.0, 0.0, 2.4, 0.0, 50.0))
	await _shot("iates", Transform3D(Basis.looking_at(Vector3(300, 0, -100) - Vector3(120, 18, -40)), Vector3(120, 18, -40)), 65.0)
	await _shot("cidade_alto", Transform3D(Basis.looking_at(Vector3(450, 30, -450) - Vector3(1100, 260, 400)), Vector3(1100, 260, 400)), 60.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_shots_profile.cfg"))
	quit(0)
