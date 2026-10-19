extends SceneTree
## Modelo de longe dos carros (com janela): grid de Monza com a câmera atrás dele (a maioria dos
## carros a mais de CarFarModel.FAR); captura com o modelo de longe e com as peças originais, e
## mede quantos objetos e desenhos o quadro tem em cada caso.
##   godot --path . -s res://tests/capture_far_model.gd -- <pasta>

var out_dir := ""


func _initialize() -> void:
	# Com janela e sem --offline o Net conecta sozinho com a conta real e regrava o account.cfg do
	# jogador: desconecta e passa a gravar num arquivo de teste
	var net := root.get_node_or_null("Net")
	if net and not "--offline" in OS.get_cmdline_user_args():
		net.account_file = "user://test_far_account.cfg"
		net.disconnect_from_server()
		net._retry = 0.0
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _stats() -> String:
	await _frames(30)
	return "%d objetos, %d desenhos, %d mil triângulos" % [Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000]


func _run() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool: return not a.begins_with("--"))
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("far_model")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_far_profile.cfg"
		profile.reset_profile()
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.opponents = 13
	RaceSettings.laps = 3
	RaceSettings.track = "monza"
	RaceSettings.grid = RaceSettings.Grid.POLE
	RaceSettings.skip_menu = true
	var scene := (load(RaceSettings.track_scene("monza")) as PackedScene).instantiate()
	scene.set("start_light_sequence", false)
	root.add_child(scene)
	current_scene = scene
	var manager := scene.get_node("RaceManager") as RaceManager
	while manager.player_entry == null or manager.entries.size() < 14:
		await process_frame
	await _frames(60)
	# O jogador vai para longe à frente do grid, virado para ele (a câmera de perseguição olha o grid)
	var path := manager.track.path
	var s := path.length - 40.0
	var grid_s: float = path.project(manager.entries[1].car.global_position).x
	var far_xf := path.frame_at(fposmod(grid_s + 110.0, path.length), 0.0, 0.6)
	far_xf.basis = far_xf.basis.rotated(far_xf.basis.y, PI)
	manager.player.freeze = true
	manager.player.global_transform = far_xf
	manager.player.reset_physics_interpolation()
	# Pula a apresentação dos carros (ela pega a câmera) e espera a câmera da corrida voltar
	var intro := manager.get_node_or_null("Intro") as IntroDirector
	if intro:
		intro._skip = true
	while manager.has_node("Intro"):
		await process_frame
	await _frames(10)
	# Câmera fixa a ~100 m do grid, olhando para ele (sem a apresentação nem a câmera de perseguição)
	var cam := Camera3D.new()
	cam.fov = 40.0
	scene.add_child(cam)
	var grid_pos := manager.entries[1].car.global_position
	cam.global_position = far_xf.origin + Vector3.UP * 3.0
	cam.look_at(grid_pos + Vector3.UP * 0.5)
	cam.make_current()
	await _frames(120)
	var models := scene.find_children("FarModel", "MeshInstance3D", true, false)
	var built := models.filter(func(m: MeshInstance3D) -> bool: return m.mesh != null).size()
	print("modelos de longe: %d, montados %d" % [models.size(), built])
	print("com o modelo de longe: ", await _stats())
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("far_on.png"))
	# Desliga: modelo escondido e as peças sem faixa de visibilidade
	for m: CarFarModel in models:
		m.visible = false
		for p in m._parts:
			if is_instance_valid(p):
				p.visibility_range_end = 0.0
	print("só com as peças: ", await _stats())
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("far_off.png"))
	quit()
