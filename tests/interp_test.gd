extends SceneTree
## Folga de interpolação adaptativa (sem janela): corrida com bots num servidor hospedado; o jogo
## não dirige, só desenha os carros dos outros. Mede a folga escolhida e em quantos passos faltou
## instantâneo (carro esticado). Sem variação de rede a folga tem que ficar perto do mínimo; com
## variação (-- --net-jitter=ms) ela sobe só o necessário e quase nunca falta instantâneo.
##   godot --headless --path . -s res://tests/interp_test.gd -- --offline [--net-lag=ms] [--net-jitter=ms]
## Arquivos de teste: user://test_interp_* (apagados no fim).

const PORT := 7368
const DIR := "user://test_interp_host"

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
	for f in ["user://test_interp_account.cfg", "user://test_interp_profile.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _run() -> void:
	_clean()
	var jitter := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net-jitter="):
			jitter = int(a.substr(13))
	PlayerProfile.save_path = "user://test_interp_profile.cfg"
	(root.get_node("Profile") as PlayerProfile).reset_profile()
	var net: Node = root.get_node("Net")
	net.account_file = "user://test_interp_account.cfg"
	host = LocalHost.new()
	host.dir = DIR
	host.auto_join = false
	root.add_child(host)
	host.start(PORT)
	_check(await _wait_for(func() -> bool: return host.log_lines.any(func(l: String) -> bool: return l.contains("pistas do servidor prontas")), 120.0),
		"servidor no ar")
	net.connect_to_server("127.0.0.1", PORT)
	await _wait_for(func() -> bool: return net.online, 20.0)
	await net.request("room_create", {"kind": "custom", "name": "Folga"})
	await net.request("room_settings", {"track": "monza", "laps": 3, "bots": true, "cars": 5, "difficulty": 1})
	await net.request("room_start")
	var ok := await _wait_for(func() -> bool:
		return current_scene != null and current_scene.has_node("RaceManager") \
			and (current_scene.get_node("RaceManager") as RaceManager).state == RaceManager.State.RACING, 120.0)
	_check(ok, "corrida com bots largou")
	if ok:
		var nc: NetRaceClient = (current_scene.get_node("RaceManager") as RaceManager).net_client
		# Deixa a folga se acomodar e mede
		await create_timer(4.0).timeout
		var e0 := nc.extrapolated_steps
		var s0 := nc.interp_steps
		var delays := PackedFloat32Array()
		for i in 80:
			await create_timer(0.1).timeout
			delays.append(nc.interp_delay)
		var frac := float(nc.extrapolated_steps - e0) / maxf(nc.interp_steps - s0, 1)
		var avg := 0.0
		for d in delays:
			avg += d
		avg /= delays.size()
		print("  variação simulada %d ms: folga média %.0f ms (alvo %.0f ms), carro esticado em %.1f%% dos passos" % [
			jitter, avg * 1000.0, nc.interp_target * 1000.0, frac * 100.0])
		if jitter == 0:
			_check(avg < 0.08, "sem variação, folga pequena (%.0f ms; era 150 fixa)" % (avg * 1000.0))
		else:
			_check(avg > 0.04 + jitter / 2000.0 and avg < 0.04 + jitter / 1000.0 + 0.05,
				"com variação de %d ms, a folga sobe só o necessário (%.0f ms)" % [jitter, avg * 1000.0])
		_check(frac < 0.05, "quase nunca falta instantâneo (%.1f%% dos passos)" % (frac * 100.0))
	host.stop()
	await _wait_for(func() -> bool: return host.state == LocalHost.State.STOPPED, 15.0)
	_clean()
	print("\ninterp_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)
