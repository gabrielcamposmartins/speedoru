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
	await _frames(90)
	await _snap("online_home")
	var ui: MenuUI = scene.ui
	MultiplayerPanel.tab = "friends"
	ui.show_screen("multiplayer")
	await create_timer(2.5).timeout
	await _snap("online_friends")
	MultiplayerPanel.tab = "profile"
	ui.show_screen("multiplayer")
	await create_timer(2.5).timeout
	await _snap("online_profile")
	MultiplayerPanel.tab = "ranking"
	ui.show_screen("multiplayer")
	await create_timer(2.5).timeout
	await _snap("online_ranking")
	# Sala com o amigo
	MultiplayerPanel.tab = "rooms"
	ui.show_screen("multiplayer")
	await create_timer(2.5).timeout
	await _snap("online_lobby")
	var r: Dictionary = await net.request("room_create", {"kind": "custom", "name": "Noite em Monza"})
	await net.request("room_settings", {"laps": 3, "difficulty": 0, "time_of_day": 2})
	await bot.request("room_join", {"id": r["room"]})
	await bot.request("room_ready", {"ready": true})
	await _frames(40)
	await _snap("online_room")
	# Convite de grupo vindo do amigo (cartão no canto)
	await bot.request("party_invite", {"id": net.account["id"]})
	await _frames(30)
	await _snap("online_invite")
	# Larga: o amigo (sem cena) só confirma que carregou; o jogo troca para a pista
	await net.request("room_start")
	await _until(func() -> bool: return current_scene != null and current_scene.has_node("RaceManager"), 60.0)
	bot.send_to_server("race_cmd", {"cmd": "loaded"})
	var rm := current_scene.get_node("RaceManager") as RaceManager
	await _until(func() -> bool: return rm.state == RaceManager.State.GRID and rm.net_client != null, 60.0)
	await _frames(60)
	await _snap("online_grid")
	var racing := await _until(func() -> bool: return rm.state == RaceManager.State.RACING, 40.0)
	print("largada: ", racing, " estado ", rm.state)
	Input.action_press("accelerate")
	await create_timer(6.0).timeout
	await _snap("online_racing")
	print("posição do jogador: ", rm.player_entry.position, " velocidade ", rm.player.speed_kmh, " km/h")
	await create_timer(4.0).timeout
	Input.action_release("accelerate")
	await _snap("online_racing2")
	for f in ["user://test_capture_main.cfg", "user://test_capture_friend.cfg", "user://test_capture_profile.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	quit()
