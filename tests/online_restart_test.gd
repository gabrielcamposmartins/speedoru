extends SceneTree
## Largada e recomeço da corrida online COM JANELA (o render entra: skins, mapa de profundidade,
## carros dos outros), como no jogo: servidor hospedado, o jogo entra numa sala com bots e um
## segundo jogador (no mesmo processo), os dois com skin; larga, anda, vota para recomeçar e larga
## de novo, algumas vezes. O processo tem que sobreviver a tudo.
##   godot --path . -s res://tests/online_restart_test.gd -- --offline [vezes]
## Arquivos de teste: user://test_restart_* (apagados no fim).

const PORT := 7367
const DIR := "user://test_restart_host"
const SKINS := "user://test_restart_skins"

var failures := 0
var host: LocalHost
var net: Node
var friend: Node


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await create_timer(0.05).timeout
		t += 0.05
	return cond.call()


func _clean() -> void:
	for d in [DIR.path_join("skins"), DIR, SKINS]:
		var abs_dir := ProjectSettings.globalize_path(d)
		if DirAccess.dir_exists_absolute(abs_dir):
			for f in DirAccess.get_files_at(abs_dir):
				DirAccess.remove_absolute(abs_dir.path_join(f))
			DirAccess.remove_absolute(abs_dir)
	for f in ["user://test_restart_a.cfg", "user://test_restart_b.cfg", "user://test_restart_profile.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _rm() -> RaceManager:
	if current_scene == null or not current_scene.has_node("RaceManager"):
		return null
	return current_scene.get_node("RaceManager") as RaceManager


func _run() -> void:
	_clean()
	var times := 2
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			times = int(a)
	CarSkin.dir = SKINS
	PlayerProfile.save_path = "user://test_restart_profile.cfg"
	var profile := root.get_node("Profile") as PlayerProfile
	profile.reset_profile()
	var img := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.4, 0.1))
	var skin: String = CarSkin.import_image(img)["hash"]
	profile.set_skin(skin)
	profile.set_decal("sidepods", "estrela")
	net = root.get_node("Net")
	net.account_file = "user://test_restart_a.cfg"
	host = LocalHost.new()
	host.dir = DIR
	host.auto_join = false
	root.add_child(host)
	host.start(PORT)
	_check(await _wait_for(func() -> bool: return host.log_lines.any(func(l: String) -> bool: return l.contains("pistas do servidor prontas")), 120.0),
		"servidor no ar")
	net.connect_to_server("127.0.0.1", PORT)
	# Segundo jogador no mesmo processo, também com skin (carro remoto pintado na tela)
	var holder := Node.new()
	holder.name = "Friend"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	friend = load("res://scripts/net/net.gd").new()
	friend.name = "Net"
	friend.account_file = "user://test_restart_b.cfg"
	friend.auto_profile = false
	friend.auto_race = false
	holder.add_child(friend)
	friend.connect_to_server("127.0.0.1", PORT)
	_check(await _wait_for(func() -> bool: return net.online and friend.online, 20.0), "os dois conectados")
	var eq := PlayerProfile.default_equipped()
	eq["skin"] = skin
	eq["primary"] = "22cc88"
	friend.send_to_server("equip", {"equipped": eq})
	friend.message.connect(func(type: String, _d: Dictionary) -> void:
		if type == "race_start":
			# O amigo não carrega cena: confirma na hora
			friend.send_to_server("race_cmd", {"cmd": "loaded"}))
	var r: Dictionary = await net.request("room_create", {"kind": "custom", "name": "Recomeço"})
	await net.request("room_settings", {"track": "monaco", "laps": 3, "bots": true, "cars": 6, "difficulty": 1})
	await friend.request("room_join", {"id": r.get("room", "")})
	await friend.request("room_ready", {"ready": true})
	await net.request("room_start")
	for k in times + 1:
		var label := "largada" if k == 0 else "largada depois do recomeço %d" % k
		var loaded := await _wait_for(func() -> bool:
			var rm := _rm()
			return rm != null and rm.net_client != null, 120.0)
		_check(loaded, "corrida carregada (%s)" % label)
		var racing := await _wait_for(func() -> bool:
			var rm := _rm()
			return rm != null and rm.state == RaceManager.State.RACING, 60.0)
		_check(racing, label)
		if not racing:
			break
		Input.action_press("accelerate")
		await create_timer(3.0).timeout
		Input.action_release("accelerate")
		var rm := _rm()
		_check(rm != null and rm.player.speed_kmh >= 0.0, "andando depois da %s (%.0f km/h)" % [label, rm.player.speed_kmh if rm else -1.0])
		if k == times:
			break
		# Vota para recomeçar (os dois)
		var old := rm
		net.send_to_server("race_cmd", {"cmd": "vote", "kind": "restart", "yes": true})
		await create_timer(0.3).timeout
		friend.send_to_server("race_cmd", {"cmd": "vote", "kind": "restart", "yes": true})
		_check(await _wait_for(func() -> bool: return _rm() != old, 30.0), "recomeço %d: corrida nova carregando" % (k + 1))
	print("  o processo sobreviveu a %d largada(s)" % (times + 1))
	host.stop()
	await _wait_for(func() -> bool: return host.state == LocalHost.State.STOPPED, 15.0)
	_clean()
	print("\nonline_restart_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)
