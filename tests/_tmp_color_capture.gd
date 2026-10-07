extends SceneTree
## Captura o multiplayer (com janela) contra um servidor dedicado local:
##   godot --path . -s res://tests/capture_online.gd -- <pasta de saída> [porta] --offline
## (servidor: godot --headless --path . -- --server --db-url=http://127.0.0.1:18080 --port=<porta>)
## O jogo entra com uma conta de teste (user://test_capture_*.cfg); um segundo cliente no mesmo
## processo ("Bruno") vira amigo e entra na sala. Depois larga uma corrida online com bots e
## captura a pista com os carros vindos do servidor.

var out_dir := "user://captures"
var port := 7362
var bot: Node


func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool: return not a.begins_with("--"))
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		port = int(args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("salvo ", name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await create_timer(0.1).timeout
		t += 0.1
	return cond.call()


func _run() -> void:
	PlayerProfile.save_path = "user://test_capture_profile.cfg"
	var net: Node = root.get_node("Net")
	net.account_file = "user://test_capture_main.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(net.account_file))
	var cfg := ConfigFile.new()
	cfg.set_value("account", "name", "Gabi")
	cfg.save(net.account_file)
	# Você com boost rosa (só na memória: nada é salvo no seu perfil)
	var prof := root.get_node("Profile") as PlayerProfile
	prof.owned["boost_hot_pink"] = true
	prof.equipped["boost"] = "ff3d9a"
	net.connect_to_server("127.0.0.1", port)
	# Segundo cliente (amigo) no mesmo processo
	var holder := Node.new()
	holder.name = "Friend"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	bot = load("res://scripts/net/net.gd").new()
	bot.name = "Net"
	bot.account_file = "user://test_capture_friend.cfg"
	bot.auto_profile = false
	bot.auto_race = false
	holder.add_child(bot)
	bot.connect_to_server("127.0.0.1", port)
	var ok := await _until(func() -> bool: return net.online and bot.online, 20.0)
	print("conectado: ", ok)
	await bot.request("set_name", {"name": "Bruno"})
	await bot.request("friend_add", {"code": net.account["code"]})
	var fr: Dictionary = await net.request("friends")
	for f: Dictionary in fr.get("incoming", []):
		await net.request("friend_accept", {"id": f["id"]})
	# Algumas corridas solo para o perfil ter histórico e nível
	for k in 4:
		await net.request("solo_result", {"laps": 5, "laps_total": 5, "difficulty": 0, "race_time": 520.0 + k,
			"best_lap": 97.5 - k, "finished": true, "pos": [1, 3, 2, 1][k], "total": 10, "grid": 5,
			"lap_times": [105.0, 101.0, 99.0, 98.0, 97.5 - k], "fastest": k == 3})
	await bot.request("solo_result", {"laps": 5, "laps_total": 5, "difficulty": 0, "race_time": 530.0, "best_lap": 96.1,
		"finished": true, "pos": 1, "total": 10, "lap_times": [104.0, 99.0, 98.0, 97.0, 96.1]})

	var scene := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(30)
	print("PERFIS: eu=", net.account["profile"]["equipped"]["boost"], " outro=", bot.account["profile"]["equipped"]["boost"])
	var r: Dictionary = await net.request("room_create", {"kind": "custom", "name": "Cor", "bots": false})
	await net.request("room_settings", {"laps": 3, "bots": false})
	await bot.request("room_join", {"id": r["room"]})
	await net.request("room_start")
	await _until(func() -> bool: return current_scene != null and current_scene.has_node("RaceManager"), 60.0)
	bot.send_to_server("race_cmd", {"cmd": "loaded"})
	var rm := current_scene.get_node("RaceManager") as RaceManager
	await _until(func() -> bool: return rm.state == RaceManager.State.GRID and rm.roster.size() == 2, 60.0)
	await _frames(20)
	await _until(func() -> bool: return rm.state == RaceManager.State.RACING, 60.0)
	var cam := current_scene.get_node("RaceCamera") as RaceCamera
	cam.set_mode(RaceCamera.Mode.ORBIT)
	Input.action_press("accelerate")
	for i in 600:
		var other_boost := i > 40 and i < 160
		if i == 200:
			Input.action_press("boost")
		var d := PackedFloat32Array([i, 0.6, 0.0, 0.0, 0.0, NetProtocol.BTN_BOOST if other_boost else 0, 0, 0, 0, 0, 0, 0, 0, 0])
		bot.inp.rpc_id(1, d)
		# Câmera de lado, olhando os dois carros
		var bru: RaceEntry = rm.roster[0] if not rm.roster[0].is_player else rm.roster[1]
		var me := rm.player_entry
		var mid := (bru.car.global_position + me.car.global_position) * 0.5
		cam.cinematic = true
		cam.global_transform = Transform3D(Basis(), mid + me.car.global_basis.x * 9.0 + Vector3.UP * 2.0).looking_at(mid, Vector3.UP)
		await create_timer(1.0 / 60.0).timeout
		if i == 80:
			_print_colors(rm, "so_ele")
			await _snap("so_ele_boost")
		if i == 230:
			_print_colors(rm, "so_eu")
			await _snap("so_eu_boost")
			break
	Input.action_release("accelerate")
	Input.action_release("boost")
	quit()


func _print_colors(rm: RaceManager, when: String) -> void:
	for e in rm.roster:
		var fx := e.car.get_node_or_null("Effects")
		var light := ""
		if fx and fx.get("_lights") and not (fx.get("_lights") as Array).is_empty():
			light = ((fx.get("_lights") as Array)[0] as OmniLight3D).light_color.to_html(false)
		var lit := 0
		var total := 0
		var names := []
		for vi in e.car.find_children("*", "GeometryInstance3D", true, false):
			if not (vi as VisualInstance3D).visible:
				continue
			total += 1
			if (vi as VisualInstance3D).layers & ~CarAssembly.OWN_LAYERS:
				lit += 1
				if names.size() < 6:
					names.append("%s[%d]" % [vi.name, (vi as VisualInstance3D).layers])
		print("CAMADAS %-8s %s: %d de %d peças iluminadas pelas luzes dos outros %s" % [when, e.code, lit, total, names])
