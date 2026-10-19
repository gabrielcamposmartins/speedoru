extends SceneTree
## Corrida online como o jogador vê (com janela): servidor local em outro processo (o mesmo do
## "Hospedar"), sala com bots do servidor e o carro do jogador pilotado por um bot daqui que só
## aperta os comandos (vai ao servidor como os de um humano, com predição e reconciliação).
## Mede por trecho e no fim:
## * quadros longos do jogo (> 25 ms e > 50 ms) e o pior;
## * buracos entre instantâneos que chegam (> 50 ms) e o pior;
## * tranco dos carros: passo de física em que o carro andou diferente da própria velocidade em
##   mais de 25% (carros dos outros, interpolados, e o do jogador, predito), e as correções da
##   predição;
## * salto visual: passo em que o carro andou diferente do passo anterior em mais de 25% (o que se
##   vê como tranco, independente da velocidade que o carro informa);
## * a linha de física do servidor (ServerStats) e os passos atrasados do servidor;
## * colisões só daqui: passos em que o meu carro encosta em outro carro na física do cliente;
## * distância do outro carro: para cada carro a menos de 30 m do meu, onde ele aparece aqui e
##   onde ele está de verdade no servidor no instante em que está o meu carro (o tempo do servidor
##   em que o comando atual do meu carro é aplicado). É o que faz "passar perto" virar batida.
## Com --server-trace o servidor sobe pelo tests/server_trace.gd (scripts cronometrados: mostra o que
## gastou o tempo nos passos lentos).
##   godot --path . -s res://tests/net_frame_probe.gd -- --offline [pista] [segundos] [carros] [--server-trace]
## Arquivos de teste: user://test_netframe_* (apagados no fim).

const PORT := 7369
const DIR := "user://test_netframe_host"

var track_id := "monza"
var seconds := 70.0
var cars := 8
var host: LocalHost
var trace_pid := -1
var manager: RaceManager
## --client-trace: scripts do jogo cronometrados; cada quadro longo (> SLOW_FRAME_MS) na corrida
## mostra as fases do quadro e os scripts que mais gastaram nele.
const SLOW_FRAME_MS := 25.0
var _phase_us := {"física": 0, "quadro": 0, "desenho": 0, "resto": 0}
var _phase := ""
var _phase_t := 0
var _frame_t := 0
var slow_frames: Array[String] = []


class Meter extends Node:
	var manager: RaceManager
	var frames := PackedFloat32Array()
	var _last := {}
	var remote_steps := 0
	var remote_jerks := 0
	var own_steps := 0
	var own_jerks := 0
	var snap_gaps := PackedFloat32Array()
	var _last_snap := 0
	var nc: NetRaceClient
	## Outros carros perto do meu: [tempo do servidor do meu carro, índice, posição mostrada aqui]
	var _samples: Array = []
	var gap_errors := PackedFloat32Array()
	var local_contacts := 0
	## Batidas do meu carro no servidor (evento "hit") e, nos trancos dos outros, a mudança de
	## velocidade do carro naquele passo (m/s: batida/freada forte ou o próprio esticar).
	var my_hits := 0
	var jerk_dv := PackedFloat32Array()
	var _last_vel := {}
	var _last_step := {}
	var remote_jumps := 0
	var own_jumps := 0
	## Diagnóstico: correções por segundo com o meu carro lento (preso?) — despeja o estado.
	var _diag_t := 0.0
	var _diag_c0 := 0
	var diag_dumps := 0

	func _diagnose() -> void:
		if nc == null or nc.prediction == null or diag_dumps >= 6:
			return
		var me := manager.player_entry
		var t := Time.get_ticks_msec() / 1000.0
		if t - _diag_t < 1.0:
			return
		var c := nc.prediction.corrections - _diag_c0
		_diag_t = t
		_diag_c0 = nc.prediction.corrections
		var srv: Variant = nc._snaps[-1]["cars"].get(me.index)
		var srv_kmh: float = (srv["vel"] as Vector3).length() * 3.6 if srv != null else 0.0
		if (c < 15 or me.car.speed_kmh > 30.0) and absf(srv_kmh - me.car.speed_kmh) < 60.0:
			return
		diag_dumps += 1
		var s: Dictionary = nc._snaps[-1]
		var mine: Variant = s["cars"].get(me.index)
		var lines := ["DIAG %.1f s: %d correções/s, %.0f km/h, erro %.2f m, hold %s, freeze %s, entradas acel %.2f freio %.2f ré %.2f dir %.2f, marcha %d" % [
			manager.race_time, c, me.car.speed_kmh, nc.prediction.last_error, me.car.hold, me.car.freeze, me.car.throttle_input,
			me.car.brake_input, me.car.reverse_input, me.car.steer_input, me.car.gear]]
		if mine != null:
			lines.append("  servidor: pos %s vel %.1f km/h | aqui: pos %s" % [mine["pos"], (mine["vel"] as Vector3).length() * 3.6, me.car.global_position])
		var pr := manager.track.path.project(me.car.global_position)
		lines.append("  na pista s %.0f lateral %.1f | encostado em: %s | destroços a menos de 10 m: %d | snaps %d" % [pr.x, pr.y,
			me.car.get_colliding_bodies().map(func(b: Node) -> String: return str(b.name)),
			manager.get_parent().get_children().filter(func(n: Node) -> bool: return n is RigidBody3D and str(n.name).begins_with("Debris") 				and (n as Node3D).global_position.distance_to(me.car.global_position) < 10.0).size(), nc.prediction.snaps])
		for w in me.car.get_wheels():
			lines.append("  roda %s contato %s em %s" % [w.name, w.is_in_contact(), w.get_contact_body().name if w.is_in_contact() and w.get_contact_body() else "-"])
		for e in manager.roster:
			if e != me and e.car and e.car.global_position.distance_to(me.car.global_position) < 15.0:
				lines.append("  perto: %s a %.1f m, %.0f km/h, camada %d" % [e.code, e.car.global_position.distance_to(me.car.global_position), e.car.linear_velocity.length() * 3.6, e.car.collision_layer])
		for l in lines:
			print(l)

	func on_state(d: Dictionary) -> void:
		if str(d.get("event", "")) == "hit" and manager.player_entry and int(d.get("idx", -1)) == manager.player_entry.index:
			my_hits += 1

	## Erro da posição mostrada de cada amostra que os instantâneos já cobrem.
	func _score_samples() -> void:
		var snaps: Array[Dictionary] = nc._snaps
		if snaps.size() < 2:
			return
		var newest: float = snaps[-1]["t"]
		var keep: Array = []
		for smp: Array in _samples:
			var t: float = smp[0]
			if t > newest:
				keep.append(smp)
				continue
			for k in snaps.size() - 1:
				var a: Dictionary = snaps[k]
				var b: Dictionary = snaps[k + 1]
				if a["t"] <= t and t <= b["t"]:
					var ca: Variant = a["cars"].get(smp[1])
					var cb: Variant = b["cars"].get(smp[1])
					if ca != null and cb != null:
						var w := clampf((t - a["t"]) / maxf(b["t"] - a["t"], 0.001), 0.0, 1.0)
						var truth: Vector3 = (ca["pos"] as Vector3).lerp(cb["pos"], w)
						gap_errors.append((smp[2] as Vector3).distance_to(truth))
					break
		_samples = keep

	func _ready() -> void:
		process_physics_priority = 1000
		process_mode = Node.PROCESS_MODE_ALWAYS

	func on_snap(_d: PackedByteArray) -> void:
		var now := Time.get_ticks_usec()
		if _last_snap > 0:
			var gap := (now - _last_snap) / 1000.0
			snap_gaps.append(gap)
			if gap > 200.0:
				print("buraco de %.0f ms nos instantâneos (%.1f s de jogo, corrida em %.1f s)" % [gap, Time.get_ticks_msec() / 1000.0,
					manager.race_time])
		_last_snap = now
		if nc:
			_score_samples.call_deferred()

	func _process(delta: float) -> void:
		frames.append(delta * 1000.0)

	func _physics_process(delta: float) -> void:
		if manager.state != RaceManager.State.RACING:
			_last.clear()
			return
		for e in manager.roster:
			if e.car == null or not e.car.visible:
				continue
			var p := e.car.global_position
			var v := e.car.linear_velocity
			if _last.has(e.index) and v.length() > 15.0:
				var step: Vector3 = p - _last[e.index]
				var expect := v * delta
				var dev := (step - expect).length() / expect.length()
				var mine := e == manager.player_entry
				if _last_step.has(e.index) and ((step - (_last_step[e.index] as Vector3)).length() > 0.25 * step.length()):
					if mine:
						own_jumps += 1
					else:
						remote_jumps += 1
				_last_step[e.index] = step
				if mine:
					own_steps += 1
					if dev > 0.25:
						own_jerks += 1
				else:
					remote_steps += 1
					if dev > 0.25:
						remote_jerks += 1
						jerk_dv.append((v - (_last_vel.get(e.index, v) as Vector3)).length())
			_last[e.index] = p
			_last_vel[e.index] = v
		var me := manager.player_entry
		if nc and nc.prediction and me and not nc._snaps.is_empty() and nc._snaps[-1].has("ack"):
			var last: Dictionary = nc._snaps[-1]
			# Meu carro agora = depois do comando _seq − 1; no relógio dos instantâneos (posições do passo
			# anterior ao tempo deles) isso é t + (_seq − ack) passos do servidor
			var t_own: float = float(last["t"]) + float(nc._seq - int(last["ack"])) / float(nc.get("_base_hz") if nc.get("_base_hz") != null else Engine.physics_ticks_per_second)
			for e in manager.roster:
				if e == me or e.car == null or not e.car.visible:
					continue
				if e.car.global_position.distance_to(me.car.global_position) < 30.0:
					_samples.append([t_own, e.index, e.car.global_position])
			for body in me.car.get_colliding_bodies():
				if body is F1Car:
					local_contacts += 1
					break
			_diagnose()


class Bridge extends Node:
	## Lê o que o bot escreveu no carro e aperta os comandos (antes do NetRaceClient mandar).
	var car: F1Car

	func _ready() -> void:
		process_physics_priority = -20

	func _physics_process(_delta: float) -> void:
		if car == null:
			return
		_press("accelerate", car.throttle_input)
		_press("brake", car.brake_input)
		var s := car.steer_input
		_press("steer_left", maxf(s, 0.0))
		_press("steer_right", maxf(-s, 0.0))

	func _press(a: String, v: float) -> void:
		if v > 0.001:
			Input.action_press(a, clampf(v, 0.0, 1.0))
		else:
			Input.action_release(a)


func _initialize() -> void:
	_run.call_deferred()


func _mark(next: String) -> void:
	var now := Time.get_ticks_usec()
	if _phase != "":
		_phase_us[_phase] += now - _phase_t
	_phase = next
	_phase_t = now


func _on_physics_frame() -> void:
	if _phase != "física":
		_mark("física")


## Fim do quadro: se foi longo, guarda as fases e os scripts que mais gastaram.
func _on_post_draw() -> void:
	_mark("resto")
	var now := Time.get_ticks_usec()
	var ms := (now - _frame_t) / 1000.0
	_frame_t = now
	var d: Dictionary = Engine.get_meta(&"prof")
	if ms > SLOW_FRAME_MS and manager and manager.state == RaceManager.State.RACING:
		var keys := d.keys()
		keys.sort_custom(func(a, b) -> bool: return d[a] > d[b])
		var parts := []
		for k in keys.slice(0, 6):
			parts.append("%s %.1f" % [k, d[k] / 1000.0])
		slow_frames.append("%.0f ms (física %.1f, quadro %.1f, desenho %.1f, resto %.1f): %s" % [ms,
			_phase_us["física"] / 1000.0, _phase_us["quadro"] / 1000.0, _phase_us["desenho"] / 1000.0,
			_phase_us["resto"] / 1000.0, ", ".join(parts)])
	d.clear()
	for k in _phase_us:
		_phase_us[k] = 0


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
	for f in ["user://test_netframe_account.cfg", "user://test_netframe_profile.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## Mediana, percentil 95 e maior valor (m) de uma lista de distâncias.
static func _dist(a: PackedFloat32Array) -> String:
	if a.is_empty():
		return "sem amostras"
	var v := Array(a)
	v.sort()
	return "%d amostras, mediana %.2f m, p95 %.2f m, máx %.2f m" % [v.size(), v[v.size() / 2], v[mini(int(v.size() * 0.95), v.size() - 1)], v[-1]]


static func _stats(a: PackedFloat32Array, over: Array) -> String:
	if a.is_empty():
		return "-"
	var worst := 0.0
	var counts := []
	for o in over:
		counts.append(0)
	for x in a:
		worst = maxf(worst, x)
		for k in over.size():
			if x > over[k]:
				counts[k] += 1
	var parts := []
	for k in over.size():
		parts.append("> %d ms: %d" % [over[k], counts[k]])
	return "%d, %s, pior %.0f ms" % [a.size(), ", ".join(parts), worst]


func _run() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool: return not a.begins_with("--"))
	if args.size() > 0:
		track_id = args[0]
	if args.size() > 1:
		seconds = float(args[1])
	if args.size() > 2:
		cars = int(args[2])
	_clean()
	Engine.set_meta(&"prof", {})
	if "--client-trace" in OS.get_cmdline_user_args():
		var tracer := load("res://tests/server_trace.gd")
		var paths: Array = []
		tracer._scripts("res://scripts", paths, ["res://scripts/server", "res://scripts/menu", "res://scripts/economy", "res://scripts/update"])
		var n := 0
		for p: String in paths:
			n += tracer._instrument(p)
		print("cliente: %d callbacks cronometrados" % n)
		physics_frame.connect(_on_physics_frame)
		process_frame.connect(_mark.bind("quadro"))
		RenderingServer.frame_pre_draw.connect(_mark.bind("desenho"))
		RenderingServer.frame_post_draw.connect(_on_post_draw)
	PlayerProfile.save_path = "user://test_netframe_profile.cfg"
	(root.get_node("Profile") as PlayerProfile).reset_profile()
	var net: Node = root.get_node("Net")
	net.account_file = "user://test_netframe_account.cfg"
	var trace := "--server-trace" in OS.get_cmdline_user_args()
	var log_path := ProjectSettings.globalize_path(DIR).path_join("server.log")
	if trace:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		trace_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--log-file", log_path, "-s", "res://tests/server_trace.gd", "--", "--server", "--port=%d" % PORT,
			"--host-dir=" + ProjectSettings.globalize_path(DIR)] + Array(OS.get_cmdline_user_args()).filter(
				func(a: String) -> bool: return a.begins_with("--trace-deep=")))
	else:
		host = LocalHost.new()
		host.dir = DIR
		host.auto_join = false
		root.add_child(host)
		host.start(PORT)
	var ready := func() -> bool:
		if trace:
			return FileAccess.file_exists(log_path) and FileAccess.get_file_as_string(log_path).contains("pistas do servidor prontas")
		return host.log_lines.any(func(l: String) -> bool: return l.contains("pistas do servidor prontas"))
	if not await _wait_for(ready, 180.0):
		print("servidor não subiu")
		quit(1)
		return
	net.connect_to_server("127.0.0.1", PORT)
	await _wait_for(func() -> bool: return net.online, 20.0)
	print("sala: ", await net.request("room_create", {"kind": "custom", "name": "Medida"}))
	print("ajustes: ", await net.request("room_settings", {"track": track_id, "laps": 10, "bots": true, "cars": cars, "difficulty": 2}))
	print("largar: ", await net.request("room_start"))
	var ok := await _wait_for(func() -> bool:
		return current_scene != null and current_scene.has_node("RaceManager") \
			and (current_scene.get_node("RaceManager") as RaceManager).player_entry != null, 120.0)
	if not ok:
		print("corrida não começou")
		quit(1)
		return
	manager = current_scene.get_node("RaceManager")
	var pe := manager.player_entry
	var bot := BotDriver.new()
	pe.car.add_child(bot)
	bot.setup(pe.car, manager.track, manager.line, manager._profile(BotDriver.Difficulty.HARD), BotDriver.Difficulty.HARD, pe, manager)
	bot.process_physics_priority = -30
	pe.bot = bot
	var bridge := Bridge.new()
	bridge.car = pe.car
	manager.add_child(bridge)
	var meter := Meter.new()
	meter.manager = manager
	manager.add_child(meter)
	net.race_snapshot.connect(meter.on_snap)
	net.race_state.connect(meter.on_state)
	await _wait_for(func() -> bool: return manager.state == RaceManager.State.RACING, 120.0)
	bot.released = true
	var nc: NetRaceClient = manager.net_client
	meter.nc = nc
	await create_timer(3.0).timeout
	print("pista %s, %d carros, %.0f s; janela %s, vsync %s, max_fps %d" % [track_id, manager.roster.size(), seconds,
		root.get_viewport().get_visible_rect().size, DisplayServer.window_get_vsync_mode(), Engine.max_fps])
	var t := 0.0
	var chunk := 10.0
	var e0 := nc.extrapolated_steps
	var s0 := nc.interp_steps
	var tot := {"f25": 0, "f50": 0, "worst": 0.0, "g50": 0, "gworst": 0.0, "own": 0, "remote": 0, "corr": 0, "back": 0, "contacts": 0,
		"rjump": 0, "ojump": 0, "hits": 0}
	var all_gaps := PackedFloat32Array()
	while t < seconds:
		meter.frames.clear()
		meter.snap_gaps.clear()
		meter.remote_steps = 0
		meter.remote_jerks = 0
		meter.own_steps = 0
		meter.own_jerks = 0
		meter.gap_errors.clear()
		meter.local_contacts = 0
		meter.my_hits = 0
		meter.jerk_dv.clear()
		meter.remote_jumps = 0
		meter.own_jumps = 0
		var sn0: int = nc.prediction.snaps if nc.prediction else 0
		var c0: int = nc.prediction.corrections if nc.prediction else 0
		var b0: int = nc.prediction.pullbacks if nc.prediction else 0
		var x0 := nc.extrapolated_steps
		var i0 := nc.interp_steps
		await create_timer(chunk).timeout
		t += chunk
		var c1: int = nc.prediction.corrections if nc.prediction else 0
		var b1: int = nc.prediction.pullbacks if nc.prediction else 0
		tot["back"] += b1 - b0
		for x in meter.frames:
			tot["f25"] += 1 if x > 25.0 else 0
			tot["f50"] += 1 if x > 50.0 else 0
			tot["worst"] = maxf(tot["worst"], x)
		for x in meter.snap_gaps:
			tot["g50"] += 1 if x > 50.0 else 0
			tot["gworst"] = maxf(tot["gworst"], x)
		tot["own"] += meter.own_jerks
		tot["remote"] += meter.remote_jerks
		tot["corr"] += c1 - c0
		tot["contacts"] += meter.local_contacts
		all_gaps.append_array(meter.gap_errors)
		print("[%3.0f s] quadros %s | instantâneos %s | folga %.0f ms, esticado %.1f%% | tranco outros %.2f%% (%d), meu %.2f%% (%d), correções %d (para trás %d), erro máx %.2f m | volta %d, %.0f km/h" % [
			t, _stats(meter.frames, [25, 50]), _stats(meter.snap_gaps, [50, 100]), nc.interp_delay * 1000.0,
			100.0 * (nc.extrapolated_steps - x0) / maxf(nc.interp_steps - i0, 1),
			100.0 * meter.remote_jerks / maxf(meter.remote_steps, 1), meter.remote_jerks,
			100.0 * meter.own_jerks / maxf(meter.own_steps, 1), meter.own_jerks, c1 - c0, b1 - b0,
			nc.prediction.max_error if nc.prediction else 0.0, pe.laps_completed(), pe.car.speed_kmh])
		tot["rjump"] += meter.remote_jumps
		tot["ojump"] += meter.own_jumps
		tot["hits"] += meter.my_hits
		print("        outro carro perto: %s | colisões só daqui %d | batidas minhas no servidor %d, saltos %d | salto visual outros %d, meu %d" % [
			_dist(meter.gap_errors), meter.local_contacts, meter.my_hits, (nc.prediction.snaps if nc.prediction else 0) - sn0,
			meter.remote_jumps, meter.own_jumps])
	for l in slow_frames:
		print("quadro longo: ", l)
	print("esticado no total: %.1f%%" % (100.0 * (nc.extrapolated_steps - e0) / maxf(nc.interp_steps - s0, 1)))
	print("TOTAL: quadros > 25 ms %d, > 50 ms %d, pior %.0f | instantâneos > 50 ms %d, pior %.0f | tranco meu %d, outros %d | correções %d (para trás %d), erro máx %.2f m" % [
		tot["f25"], tot["f50"], tot["worst"], tot["g50"], tot["gworst"], tot["own"], tot["remote"], tot["corr"], tot["back"],
		nc.prediction.max_error if nc.prediction else 0.0])
	print("TOTAL outro carro perto (onde aparece × onde está no servidor no tempo do meu carro): %s | colisões só daqui (passos) %d" % [
		_dist(all_gaps), tot["contacts"]])
	print("TOTAL salto visual: outros %d, meu %d | batidas do meu carro no servidor %d" % [tot["rjump"], tot["ojump"], tot["hits"]])
	var lines: Array = host.log_lines if host else Array(FileAccess.get_file_as_string(log_path).split(char(10)))
	for l: String in lines:
		if l.contains("física no último minuto") or l.contains("ERROR") or l.contains("server_trace"):
			print("servidor: ", l.left(600))
	if host:
		host.stop()
		await _wait_for(func() -> bool: return host.state == LocalHost.State.STOPPED, 15.0)
	else:
		OS.kill(trace_pid)
		await create_timer(1.0).timeout
	_clean()
	quit()
