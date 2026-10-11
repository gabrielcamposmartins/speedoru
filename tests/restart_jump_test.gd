extends SceneTree
## Recomeço da corrida online com o jogador acelerando (sem janela): depois de recomeçar, o carro
## do jogador (predição) não pode ficar voltando para trás aos saltos até a largada — o servidor
## segura os carros no grid até as luzes apagarem, e o jogo tem que segurar junto.
##   godot --headless --path . -s res://tests/restart_jump_test.gd -- --offline [--net-lag=ms]
## Arquivos de teste: user://test_rjump_* (apagados no fim).

const PORT := 7369
const DIR := "user://test_rjump_host"

var failures := 0
var host: LocalHost


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
	for d in [DIR.path_join("skins"), DIR]:
		var abs_dir := ProjectSettings.globalize_path(d)
		if DirAccess.dir_exists_absolute(abs_dir):
			for f in DirAccess.get_files_at(abs_dir):
				DirAccess.remove_absolute(abs_dir.path_join(f))
			DirAccess.remove_absolute(abs_dir)
	for f in ["user://test_rjump_account.cfg", "user://test_rjump_profile.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _rm() -> RaceManager:
	if current_scene == null or not current_scene.has_node("RaceManager"):
		return null
	return current_scene.get_node("RaceManager") as RaceManager


## Acompanha o carro do jogador até `seconds` depois da largada: saltos para trás (o carro voltando
## mais de 1,5 m ao longo da pista de um passo para o outro) e saltos da predição.
func _watch(rm: RaceManager, seconds: float) -> Dictionary:
	var car := rm.player
	var path := rm.track.path
	var last_s := path.project(car.global_position).x
	var back := 0
	var worst := 0.0
	var racing_t := -1.0
	var t := 0.0
	while t < 60.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if not is_instance_valid(car) or _rm() != rm:
			break
		var s := path.project(car.global_position).x
		var ds := fposmod(s - last_s + path.length * 0.5, path.length) - path.length * 0.5
		if ds < -1.5:
			back += 1
			worst = minf(worst, ds)
		last_s = s
		if rm.state == RaceManager.State.RACING and racing_t < 0.0:
			racing_t = t
		if racing_t >= 0.0 and t - racing_t > seconds:
			break
	var nc := rm.net_client
	return {"back": back, "worst": worst, "snaps": nc.prediction.snaps if nc and nc.prediction else -1, "raced": racing_t >= 0.0}


func _run() -> void:
	_clean()
	PlayerProfile.save_path = "user://test_rjump_profile.cfg"
	(root.get_node("Profile") as PlayerProfile).reset_profile()
	var net: Node = root.get_node("Net")
	net.account_file = "user://test_rjump_account.cfg"
	host = LocalHost.new()
	host.dir = DIR
	host.auto_join = false
	root.add_child(host)
	host.start(PORT)
	_check(await _wait_for(func() -> bool: return host.log_lines.any(func(l: String) -> bool: return l.contains("pistas do servidor prontas")), 120.0),
		"servidor no ar")
	net.connect_to_server("127.0.0.1", PORT)
	await _wait_for(func() -> bool: return net.online, 20.0)
	await net.request("room_create", {"kind": "custom", "name": "Recomeço"})
	await net.request("room_settings", {"track": "monza", "laps": 3, "bots": false, "cars": 2})
	await net.request("room_start")
	var ok := await _wait_for(func() -> bool:
		var rm := _rm()
		return rm != null and rm.state == RaceManager.State.RACING, 120.0)
	_check(ok, "primeira largada")
	if ok:
		Input.action_press("accelerate")
		await create_timer(4.0).timeout
		var first := _rm()
		# Recomeça acelerando (como quem vota no meio da corrida)
		print("  --- votação para recomeçar")
		net.send_to_server("race_cmd", {"cmd": "vote", "kind": "restart", "yes": true})
		var reloaded := await _wait_for(func() -> bool:
			var rm := _rm()
			return rm != null and rm != first and rm.net_client != null, 120.0)
		_check(reloaded, "corrida nova carregada")
		if reloaded:
			print("  --- corrida nova carregada")
			var r := await _watch(_rm(), 4.0)
			print("  depois do recomeço, acelerando: %d saltos para trás (pior %.1f m), %d saltos da predição, largou %s" % [
				r["back"], r["worst"], r["snaps"], r["raced"]])
			_check(r["raced"], "corrida nova largou")
			_check(r["back"] == 0, "o carro não volta aos saltos para trás (%d)" % r["back"])
		Input.action_release("accelerate")
	host.stop()
	await _wait_for(func() -> bool: return host.state == LocalHost.State.STOPPED, 15.0)
	_clean()
	print("\nrestart_jump_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)
