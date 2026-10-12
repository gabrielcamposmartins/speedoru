extends SceneTree
## Observador na sala online (sem janela): sobe o servidor hospedado, o jogo e um segundo jogador
## (no mesmo processo) entram numa sala; o jogo vira observador e o outro larga.
## * a sala marca o observador, ele não precisa marcar pronto e não entra no grid;
## * todos como observadores: a sala não larga;
## * o observador recebe a largada, abre a corrida sem carro, com o modo espectador travado, e os
##   carros andam (instantâneos chegando);
## * sair e entrar de novo com a corrida em andamento, só para assistir, abre a corrida de novo.
##   godot --headless --path . -s res://tests/spectator_test.gd
## Com janela (o HUD desenha): godot --path . -s res://tests/spectator_test.gd -- --offline
## Arquivos de teste: user://test_watch_* (apagados no fim).

const PORT := 7366
const DIR := "user://test_watch_host"

var failures := 0
var host: LocalHost
var net: Node
var friend: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await create_timer(0.05).timeout
		t += 0.05
	return cond.call()


func _clean() -> void:
	for d in [DIR.path_join("skins"), DIR]:
		var abs_dir := ProjectSettings.globalize_path(d)
		if DirAccess.dir_exists_absolute(abs_dir):
			for f in DirAccess.get_files_at(abs_dir):
				DirAccess.remove_absolute(abs_dir.path_join(f))
			DirAccess.remove_absolute(abs_dir)
	for f in ["user://test_watch_a.cfg", "user://test_watch_b.cfg", "user://test_watch_profile.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _rm() -> RaceManager:
	if current_scene == null or not current_scene.has_node("RaceManager"):
		return null
	return current_scene.get_node("RaceManager") as RaceManager


func _me_in_room() -> Dictionary:
	var me: String = net.account.get("id", "")
	for m: Dictionary in (net.room as Dictionary).get("members", []):
		if m["id"] == me:
			return m
	return {}


func _run() -> void:
	_clean()
	PlayerProfile.save_path = "user://test_watch_profile.cfg"
	(root.get_node("Profile") as PlayerProfile).reset_profile()
	net = root.get_node("Net")
	net.account_file = "user://test_watch_a.cfg"
	host = LocalHost.new()
	host.dir = DIR
	host.auto_join = false
	root.add_child(host)
	host.start(PORT)
	_check(await _wait_for(func() -> bool: return host.log_lines.any(func(l: String) -> bool: return l.contains("pistas do servidor prontas")), 120.0),
		"servidor no ar")
	net.connect_to_server("127.0.0.1", PORT)
	var holder := Node.new()
	holder.name = "Friend"
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	friend = load("res://scripts/net/net.gd").new()
	friend.name = "Net"
	friend.account_file = "user://test_watch_b.cfg"
	friend.auto_profile = false
	friend.auto_race = false
	holder.add_child(friend)
	friend.connect_to_server("127.0.0.1", PORT)
	_check(await _wait_for(func() -> bool: return net.online and friend.online, 20.0), "os dois conectados")
	friend.message.connect(func(type: String, _d: Dictionary) -> void:
		if type == "race_start":
			friend.send_to_server("race_cmd", {"cmd": "loaded"}))
	var r: Dictionary = await friend.request("room_create", {"kind": "custom", "name": "Assistir"})
	var room_id := str(r.get("room", ""))
	await friend.request("room_settings", {"track": "monaco", "laps": 3, "bots": true, "cars": 4, "difficulty": 1})
	await net.request("room_join", {"id": room_id})
	r = await net.request("room_spectate", {"on": true})
	_check(r.get("ok", false), "virar observador na sala")
	_check(await _wait_for(func() -> bool: return _me_in_room().get("spectator", false), 5.0), "a sala mostra o observador")
	# Todos observadores: não larga
	await friend.request("room_spectate", {"on": true})
	r = await friend.request("room_start")
	_check(not r.get("ok", false), "sem ninguém para correr a sala não larga (%s)" % r.get("error", ""))
	await friend.request("room_spectate", {"on": false})
	r = await friend.request("room_start")
	_check(r.get("ok", false), "o anfitrião larga com o observador sem marcar pronto")
	var loaded := await _wait_for(func() -> bool:
		var rm := _rm()
		return rm != null and rm.net_client != null and rm.state != RaceManager.State.MENU, 120.0)
	_check(loaded, "o observador abriu a corrida")
	if loaded:
		await _watch("largada")
	# Sai da corrida e da sala e entra de novo, com a corrida andando, só para assistir
	var rm := _rm()
	if rm:
		rm.restart(false)
	_check(await _wait_for(func() -> bool: return _rm() == null, 60.0), "voltou ao menu")
	await net.request("room_leave")
	r = await net.request("room_join", {"id": room_id, "password": "", "spectate": true})
	_check(r.get("ok", false), "entrar como observador com a corrida em andamento (%s)" % r.get("error", "ok"))
	loaded = await _wait_for(func() -> bool:
		var m := _rm()
		return m != null and m.net_client != null and m.state != RaceManager.State.MENU, 120.0)
	_check(loaded, "a corrida em andamento abriu para o observador")
	if loaded:
		await _watch("corrida em andamento")
	if failures > 0:
		print("--- log do servidor
" + "
".join(host.log_lines.slice(maxi(host.log_lines.size() - 40, 0))))
	host.stop()
	await _wait_for(func() -> bool: return host.state == LocalHost.State.STOPPED, 15.0)
	_clean()
	print("\nspectator_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)


## Confere a corrida do observador: sem carro próprio, espectador travado, carros andando.
func _watch(label: String) -> void:
	var rm := _rm()
	_check(rm.observer and rm.player_entry == null, "%s: observador sem carro próprio" % label)
	_check(rm.roster.size() == 4 and rm.roster.all(func(e: RaceEntry) -> bool: return e.net_id != net.account.get("id", "")),
		"%s: grid sem o observador (%d carros)" % [label, rm.roster.size()])
	_check(await _wait_for(func() -> bool: return rm.hud != null and rm.hud.spectator != null and rm.hud.spectator.active, 10.0),
		"%s: modo espectador ligado" % label)
	rm.hud.spectator.exit()
	_check(rm.hud.spectator.active, "%s: o observador não sai do modo espectador" % label)
	_check(await _wait_for(func() -> bool: return rm.state == RaceManager.State.RACING, 90.0), "%s: corrida andando" % label)
	var before := 0.0
	for e in rm.roster:
		before += e.car.global_position.length()
	await create_timer(3.0).timeout
	var moved := 0.0
	for e in rm.roster:
		moved += e.car.global_position.length()
	_check(absf(moved - before) > 5.0, "%s: os carros andam na tela do observador" % label)
