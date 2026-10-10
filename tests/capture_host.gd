extends SceneTree
## Captura a aba SERVIDOR do multiplayer (com janela): offline com servidores salvos e histórico,
## depois abrindo o próprio servidor (LocalHost), com um amigo conectado e o log.
##   godot --path . -s res://tests/capture_host.gd -- <pasta de saída> [porta] --offline
## Conta e pasta do host de teste: user://test_capture_host*.cfg e user://test_capture_host/
## (apagados no fim).

const HOST_DIR := "user://test_capture_host"

var out_dir := "user://captures"
var port := 7363


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


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await create_timer(0.1).timeout
		t += 0.1
	return cond.call()


func _run() -> void:
	PlayerProfile.save_path = "user://test_capture_host_profile.cfg"
	var net: Node = root.get_node("Net")
	net.account_file = "user://test_capture_host.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(net.account_file))
	var cfg := ConfigFile.new()
	cfg.set_value("account", "name", "Gabi")
	cfg.set_value("server", "host", "2001:db8::42")
	cfg.set_value("server", "port", 7350)
	cfg.save(net.account_file)
	net.server_host = "2001:db8::42"
	net.save_server("Servidor oficial", "speedoru.exemplo.com", 7350)
	net.save_server("Casa do Léo", "2001:db8::42", 7350)
	net.save_server("LAN da faculdade", "192.168.0.15", 7400)
	net._cfg_store("history", [
		{"host": "192.168.0.15", "port": 7400, "t": int(Time.get_unix_time_from_system()) - 7200},
		{"host": "2804:14c:5b80::1a2b", "port": 7350, "t": int(Time.get_unix_time_from_system()) - 90000},
	])
	net.last_error = ""
	var lh: LocalHost = net.local_host
	lh.dir = HOST_DIR
	lh.port = port

	var scene := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.5).timeout
	var ui: MenuUI = scene.ui
	MultiplayerPanel.tab = "server"
	ui.show_screen("multiplayer")
	await create_timer(1.5).timeout
	await _snap("host_offline")

	# Abre o servidor: o jogo entra nele sozinho
	lh.start(port)
	await create_timer(0.5).timeout
	await _snap("host_abrindo")
	var ok := await _until(func() -> bool: return net.online, 60.0)
	print("no próprio servidor: ", ok)
	# Um amigo entra (segundo cliente no mesmo processo, por IPv6)
	var holder := Node.new()
	holder.name = "Friend"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var friend: Node = load("res://scripts/net/net.gd").new()
	friend.name = "Net"
	friend.account_file = "user://test_capture_host_friend.cfg"
	friend.auto_profile = false
	friend.auto_race = false
	holder.add_child(friend)
	friend.connect_to_server("::1", port)
	await _until(func() -> bool: return friend.online, 20.0)
	await friend.request("set_name", {"name": "Bruno"})
	await _until(func() -> bool: return (lh.status.get("players", []) as Array).size() == 2, 10.0)
	MultiplayerPanel.tab = "server"
	ui.show_screen("multiplayer")
	await create_timer(2.0).timeout
	await _snap("host_no_ar")
	var panel := _find_panel(scene)
	if panel:
		panel._scroll.scroll_vertical = 100000
		await create_timer(0.5).timeout
		await _snap("host_no_ar_baixo")
	lh.stop()
	await _until(func() -> bool: return lh.state == LocalHost.State.STOPPED, 15.0)
	await create_timer(1.0).timeout
	await _snap("host_fechado")
	for f in ["user://test_capture_host.cfg", "user://test_capture_host_friend.cfg", "user://test_capture_host_profile.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var abs_dir := ProjectSettings.globalize_path(HOST_DIR)
	for f in DirAccess.get_files_at(abs_dir):
		DirAccess.remove_absolute(abs_dir.path_join(f))
	DirAccess.remove_absolute(abs_dir)
	quit()


func _find_panel(n: Node) -> MultiplayerPanel:
	if n is MultiplayerPanel:
		return n
	for c in n.get_children():
		var p := _find_panel(c)
		if p:
			return p
	return null
