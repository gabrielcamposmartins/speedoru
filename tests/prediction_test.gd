extends SceneTree
## Predição no cliente com reconciliação (sem janela): sobe um servidor (LocalHost), entra numa
## corrida de verdade em Monza (cena do cliente, como o jogo) e, depois da largada:
## * mede em quantos passos o carro responde ao acelerador (com predição: na hora; sem: depois da
##   ida e volta ao servidor e do atraso de interpolação);
## * acelera, vira e freia por alguns segundos medindo o erro entre o previsto e o servidor (para o
##   mesmo comando), quantas correções e quantos saltos houve.
##   godot --headless --path . -s res://tests/prediction_test.gd -- --offline [--net-lag=120] [--no-prediction]
## Arquivos de teste: user://test_pred_* (apagados no fim).

const PORT := 7365
const DIR := "user://test_pred_host"

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
	for f in ["user://test_pred_account.cfg", "user://test_pred_profile.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _run() -> void:
	_clean()
	PlayerProfile.save_path = "user://test_pred_profile.cfg"
	(root.get_node("Profile") as PlayerProfile).reset_profile()
	var net: Node = root.get_node("Net")
	net.account_file = "user://test_pred_account.cfg"
	var lag := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net-lag="):
			lag = int(a.substr(10))
	var predicting := not "--no-prediction" in OS.get_cmdline_user_args()
	print("Atraso simulado: %d ms (ida e volta); predição %s" % [lag, "ligada" if predicting else "desligada"])
	host = LocalHost.new()
	host.dir = DIR
	host.auto_join = false
	root.add_child(host)
	host.start(PORT)
	var ready := await _wait_for(func() -> bool: return host.log_lines.any(func(l: String) -> bool: return l.contains("pistas do servidor prontas")), 120.0)
	_check(ready, "servidor no ar")
	if not ready:
		await _finish()
		return
	net.connect_to_server("127.0.0.1", PORT)
	if not await _wait_for(func() -> bool: return net.online, 20.0):
		_check(false, "conectado")
		await _finish()
		return
	await net.request("room_create", {"kind": "custom", "name": "Predição"})
	await net.request("room_settings", {"track": "monza", "laps": 3, "bots": false, "cars": 2})
	await net.request("room_start")
	var in_race := await _wait_for(func() -> bool:
		return current_scene != null and current_scene.has_node("RaceManager") \
			and (current_scene.get_node("RaceManager") as RaceManager).net_client != null, 90.0)
	_check(in_race, "corrida carregada no cliente")
	if not in_race:
		await _finish()
		return
	var rm := current_scene.get_node("RaceManager") as RaceManager
	var nc: NetRaceClient = rm.net_client
	_check((nc.prediction != null) == predicting, "predição no carro do jogador: %s" % ("sim" if nc.prediction else "não"))
	var racing := await _wait_for(func() -> bool: return rm.state == RaceManager.State.RACING, 60.0)
	_check(racing, "largada")
	await create_timer(1.5).timeout
	var car := rm.player
	# Resposta ao acelerador
	var v0 := car.speed_kmh
	Input.action_press("accelerate")
	var steps := 0
	while car.speed_kmh < v0 + 1.0 and steps < 240:
		await physics_frame
		steps += 1
	var ms := steps * 1000.0 / Engine.physics_ticks_per_second
	print("  carro na tela responde ao acelerador em %d passos (%.0f ms)" % [steps, ms])
	if predicting:
		_check(steps <= 8, "com predição, resposta imediata (%d passos)" % steps)
	# Anda, vira e freia medindo o erro da previsão
	var errs := PackedFloat32Array()
	for phase in [["accelerate", 4.0], ["steer_left", 0.6], ["steer_right", 0.6], ["brake", 1.5]]:
		if phase[0] != "accelerate":
			Input.action_press(phase[0], 0.6 if phase[0].begins_with("steer") else 1.0)
		var t := 0.0
		while t < float(phase[1]):
			await physics_frame
			t += 1.0 / Engine.physics_ticks_per_second
			if nc.prediction:
				errs.append(nc.prediction.last_error)
		if phase[0] != "accelerate":
			Input.action_release(phase[0])
	Input.action_release("accelerate")
	print("  velocidade máxima %.0f km/h" % car.speed_kmh)
	if nc.prediction:
		var p := nc.prediction
		var sum := 0.0
		for e in errs:
			sum += e
		print("  erro previsto x servidor: médio %.3f m, maior %.3f m; correções %d, saltos %d" % [
			sum / maxf(errs.size(), 1), p.max_error, p.corrections, p.snaps])
		var sorted := Array(errs)
		sorted.sort()
		var p95: float = sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0
		_check(p.snaps == 0, "nenhum salto andando normalmente (%d)" % p.snaps)
		# Numa raspada no muro a física de cliente e servidor diverge um pouco (corrigido aos poucos)
		_check(sum / maxf(errs.size(), 1) < 0.15 and p95 < 0.5, "erro da previsão pequeno (médio %.3f m, 95%% abaixo de %.2f m)" % [
			sum / maxf(errs.size(), 1), p95])
		# O carro na tela e o do servidor estão no mesmo lugar (descontando o atraso)
		var last: Dictionary = nc._snaps[-1]
		var server_pos: Vector3 = last["cars"][rm.player_entry.index]["pos"]
		var gap := car.global_position.distance_to(server_pos)
		var allowed := 2.0 + car.linear_velocity.length() * (lag / 1000.0 + 0.1)
		_check(gap < allowed, "carro na tela perto do carro do servidor (%.1f m; até %.1f m pelo atraso)" % [gap, allowed])
	await _finish()


func _finish() -> void:
	if host and host.is_active():
		host.stop()
		await _wait_for(func() -> bool: return host.state == LocalHost.State.STOPPED, 15.0)
	_clean()
	print("\nprediction_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)
