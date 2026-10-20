extends SceneTree
## Safety car (com janela): põe o safety car na reta à frente do grid e captura de vários ângulos
## (3/4 de frente, lado, 3/4 de trás, de cima, de frente, a barra de luzes de perto, atrás dele
## como o jogador o vê e de longe), com a barra de luzes nas duas fases do pisca.
##   godot --path . -s res://tests/capture_safety_car.gd -- <pasta> [pista] [day|sunset|night]

## Vistas: nome → [posição da câmera, ponto olhado] no espaço do safety car (+Z = frente,
## +X = esquerda), e o campo de visão.
const VIEWS := {
	"front34": [Vector3(3.4, 1.25, 5.6), Vector3(0.0, 0.55, 0.2), 40.0],
	"side": [Vector3(-6.0, 0.9, 0.0), Vector3(0.0, 0.6, 0.0), 40.0],
	"rear34": [Vector3(-3.6, 1.5, -5.8), Vector3(0.0, 0.6, -0.3), 40.0],
	"front": [Vector3(0.0, 0.85, 7.5), Vector3(0.0, 0.6, 0.0), 32.0],
	"rear": [Vector3(0.0, 1.1, -7.5), Vector3(0.0, 0.7, 0.0), 32.0],
	"top": [Vector3(2.2, 6.5, 1.0), Vector3(0.0, 0.4, 0.0), 45.0],
	"roof": [Vector3(1.4, 2.3, 1.2), Vector3(0.0, 1.2, -0.3), 40.0],
	"chase": [Vector3(0.0, 1.6, -16.0), Vector3(0.0, 0.9, 0.0), 60.0],
	"follow": [Vector3(0.0, 1.9, -9.0), Vector3(0.0, 0.8, 0.0), 55.0],
	"far": [Vector3(9.0, 3.0, 32.0), Vector3(0.0, 0.6, 0.0), 40.0],
	# Ângulos das fotos de referência (para comparar lado a lado): lateral baixa, 3/4 de frente do
	# alto e traseira do alto
	"ref_side": [Vector3(9.0, 1.0, 0.1), Vector3(0.0, 0.65, 0.1), 32.0],
	"ref_front": [Vector3(1.9, 3.4, 5.7), Vector3(0.0, 0.55, 0.15), 32.0],
	"ref_rear": [Vector3(-0.5, 2.6, -6.0), Vector3(0.0, 0.62, -0.4), 30.0],
}

var out_dir := ""


func _initialize() -> void:
	# Com janela e sem --offline o Net conecta sozinho com a conta real e regrava o account.cfg do
	# jogador: desconecta e passa a gravar num arquivo de teste
	var net := root.get_node_or_null("Net")
	if net and not "--offline" in OS.get_cmdline_user_args():
		net.account_file = "user://test_sc_account.cfg"
		net.disconnect_from_server()
		net._retry = 0.0
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool: return not a.begins_with("--"))
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("safety_car")
	var track_id: String = args[1] if args.size() > 1 else "monza"
	var period: String = args[2] if args.size() > 2 else ""
	DirAccess.make_dir_recursive_absolute(out_dir)
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_sc_profile.cfg"
		profile.reset_profile()
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.opponents = 3
	RaceSettings.laps = 3
	RaceSettings.track = track_id
	RaceSettings.grid = RaceSettings.Grid.POLE
	RaceSettings.skip_menu = true
	var scene := (load(RaceSettings.track_scene(track_id)) as PackedScene).instantiate()
	scene.set("start_light_sequence", false)
	root.add_child(scene)
	current_scene = scene
	var manager := scene.get_node("RaceManager") as RaceManager
	while manager.player_entry == null or manager.entries.size() < 4 or LoadingScreen.is_loading():
		await process_frame
	# Pula a apresentação dos carros (ela pega a câmera), que começa logo depois do carregamento
	for i in 60:
		var intro := manager.get_node_or_null("Intro") as IntroDirector
		if intro:
			intro.skip()
			break
		await process_frame
	while manager.has_node("Intro"):
		await process_frame
	await _frames(30)
	var daylight := scene.get_tree().get_first_node_in_group("daylight") as Daylight
	if daylight and period != "":
		daylight.time_of_day = {"day": DaylightPresets.TimeOfDay.DAY, "sunset": DaylightPresets.TimeOfDay.SUNSET,
			"night": DaylightPresets.TimeOfDay.NIGHT}.get(period, DaylightPresets.TimeOfDay.DAY)
	# Safety car na reta, uns 150 m à frente do pole, no meio da pista (espaço dos dois lados)
	var path := manager.track.path
	var grid_s: float = path.project(manager.entries[0].car.global_position).x
	var sc := SafetyCar.new()
	sc.name = "SafetyCarCapture"
	scene.add_child(sc)
	sc.setup(manager.track, manager.line, grid_s + 150.0)
	sc.set_process(false)
	var xf := path.frame_at(fposmod(grid_s + 150.0, path.length))
	var ray := PhysicsRayQueryParameters3D.create(xf.origin + Vector3.UP * 4.0, xf.origin + Vector3.DOWN * 4.0)
	var hit := sc.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.has("position"):
		xf.origin = hit["position"]
	sc.global_transform = xf
	# Sem HUD (as imagens servem para comparar o carro com fotos)
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.make_current()
	for view: String in VIEWS:
		var v: Array = VIEWS[view]
		cam.fov = v[2]
		cam.global_position = sc.global_transform * (v[0] as Vector3)
		cam.look_at(sc.global_transform * (v[1] as Vector3))
		for phase in 2:
			sc._t = phase / 6.0 + 0.01
			sc._process(0.0)
			await _frames(8)
			var file := "%s%s_%s%s.png" % [track_id, "" if period == "" else "_" + period, view, "" if phase == 0 else "_b"]
			root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
			# Só a barra de luzes muda entre as fases: a segunda vista só onde ela aparece de perto
			if view not in ["roof", "front34", "chase", "follow"]:
				break
	print("capturas em ", out_dir)
	quit()
