extends SceneTree
## Desempenho de CPU numa corrida (com janela): corrida solo com bots correndo de verdade e o carro do
## jogador pilotado por um bot (a câmera segue no meio do pelotão). A imagem 3D vai a 50% numa janela
## pequena e sem vsync, para a placa de vídeo não ser o limite. Mede por quadro, na thread
## principal: física (os passos do quadro: scripts, carros e bots nativos e o motor de física),
## lógica (_process), desenho (envio ao render) e o resto; e, com --trace, quanto cada script gasta.
## Depois liga e desliga, durante a mesma corrida, coisas de cada carro para medir o custo de cada uma.
##   godot --path . -s res://tests/cpu_probe.gd -- [pistas] [segundos] [adversários] [--trace] [--experimentos]

const SLICE_S := 6.0

var tracks := PackedStringArray(["monza"])
var seconds := 30.0
var opponents := 13
var trace := false
var experiments := false

## Fase atual e quando começou (µs); totais por fase no trecho medido.
var _phase := ""
var _phase_t := 0
var _acc := {}
var _frames := 0
var _ticks := 0
var _frame_ms := PackedFloat32Array()
var _last_frame := 0
var _measuring := false


func _initialize() -> void:
	# Com janela e sem --offline o Net conecta sozinho com a conta real e regrava o account.cfg do
	# jogador: desconecta e passa a gravar num arquivo de teste
	var net := root.get_node_or_null("Net")
	if net and not "--offline" in OS.get_cmdline_user_args():
		net.account_file = "user://test_cpu_account.cfg"
		net.disconnect_from_server()
		net._retry = 0.0
	_run.call_deferred()


func _mark(next: String) -> void:
	var now := Time.get_ticks_usec()
	if _measuring and _phase != "":
		_acc[_phase] = int(_acc.get(_phase, 0)) + now - _phase_t
	_phase = next
	_phase_t = now


func _on_physics() -> void:
	if _measuring:
		_ticks += 1
	if _phase != "física":
		_mark("física")


func _on_process() -> void:
	_mark("lógica")


func _on_pre_draw() -> void:
	_mark("desenho")


func _on_post_draw() -> void:
	_mark("resto")
	var now := Time.get_ticks_usec()
	if _measuring:
		_frames += 1
		if _last_frame > 0:
			_frame_ms.append((now - _last_frame) / 1000.0)
	_last_frame = now


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _begin() -> void:
	_acc.clear()
	_frames = 0
	_ticks = 0
	_frame_ms.clear()
	(Engine.get_meta(&"prof") as Dictionary).clear()
	_script_acc.clear()
	_measuring = true


var _script_acc := {}


func _collect_scripts() -> void:
	var d: Dictionary = Engine.get_meta(&"prof")
	for k in d:
		_script_acc[k] = int(_script_acc.get(k, 0)) + int(d[k])
	d.clear()


func _end(label: String) -> Dictionary:
	_measuring = false
	var n := maxi(_frames, 1)
	var sorted := Array(_frame_ms)
	sorted.sort()
	var p95: float = sorted[mini(int(sorted.size() * 0.95), sorted.size() - 1)] if not sorted.is_empty() else 0.0
	var vp := root.get_viewport().get_viewport_rid()
	var r := {"fps": _frames / maxf(_frame_sum(), 0.001), "física": _acc.get("física", 0) / 1000.0 / n,
		"lógica": _acc.get("lógica", 0) / 1000.0 / n, "desenho": _acc.get("desenho", 0) / 1000.0 / n,
		"resto": _acc.get("resto", 0) / 1000.0 / n, "ticks": float(_ticks) / n, "p95": p95,
		"gpu": RenderingServer.viewport_get_measured_render_time_gpu(vp)}
	print("  %-26s %4.0f fps · quadro p95 %5.1f ms · física %5.2f ms (%.1f passos) · lógica %5.2f · desenho %5.2f · resto %5.2f · GPU %4.1f" % [
		label, r["fps"], r["p95"], r["física"], r["ticks"], r["lógica"], r["desenho"], r["resto"], r["gpu"]])
	return r


func _frame_sum() -> float:
	var s := 0.0
	for x in _frame_ms:
		s += x
	return s / 1000.0


func _run() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var plain := args.filter(func(a: String) -> bool: return not a.begins_with("--"))
	if plain.size() > 0:
		tracks = (plain[0] as String).split(",")
	if plain.size() > 1:
		seconds = float(plain[1])
	if plain.size() > 2:
		opponents = int(plain[2])
	trace = "--trace" in args
	experiments = "--experimentos" in args
	Engine.set_meta(&"prof", {})
	if trace:
		var tracer := load("res://tests/server_trace.gd")
		var paths: Array = []
		tracer._scripts("res://scripts", paths, ["res://scripts/server", "res://scripts/menu", "res://scripts/economy", "res://scripts/update"])
		var n := 0
		for p: String in paths:
			n += tracer._instrument(p)
		print("cpu_probe: %d callbacks cronometrados" % n)
	physics_frame.connect(_on_physics)
	process_frame.connect(_on_process)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_cpu_profile.cfg"
		profile.reset_profile()
	print("cpu_probe: física %s, thread própria %s, %d passos/s; desenho em thread %s" % [
		ProjectSettings.get_setting("physics/3d/physics_engine"), ProjectSettings.get_setting("physics/3d/run_on_separate_thread"),
		Engine.physics_ticks_per_second, ProjectSettings.get_setting("rendering/driver/threads/thread_model")])
	for id in tracks:
		RaceSettings.mode = RaceSettings.Mode.RACE
		RaceSettings.opponents = opponents
		RaceSettings.laps = 5
		RaceSettings.difficulty = 2
		RaceSettings.quali_laps = 0
		RaceSettings.grid = RaceSettings.Grid.MIDDLE
		RaceSettings.track = id
		RaceSettings.skip_menu = true
		var scene := (load(RaceSettings.track_scene(id)) as PackedScene).instantiate()
		root.add_child(scene)
		current_scene = scene
		var manager := scene.get_node("RaceManager") as RaceManager
		# O estado vira GRID antes de os carros entrarem (um por vez): espera o grid completo
		var t0 := Time.get_ticks_msec()
		while manager.player_entry == null or manager.entries.size() < opponents + 1:
			await process_frame
			if Time.get_ticks_msec() - t0 > 120000:
				print("cpu_probe: o grid não ficou pronto")
				quit(1)
				return
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		DisplayServer.window_set_size(Vector2i(1280, 720))
		root.scaling_3d_scale = 0.5
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		# O carro do jogador pilotado por um bot (a câmera segue no pelotão)
		var pe := manager.player_entry
		var bot := BotDriver.new()
		pe.car.add_child(bot)
		bot.setup(pe.car, manager.track, manager.line, manager._profile(BotDriver.Difficulty.HARD), BotDriver.Difficulty.HARD, pe, manager)
		pe.bot = bot
		pe.car.player_controlled = false
		while manager.state != RaceManager.State.RACING:
			await process_frame
		bot.released = true
		await _wait(4.0)
		print("%s (%d carros):" % [id, manager.entries.size()])
		_begin()
		await _wait(seconds)
		_collect_scripts()
		_end("corrida")
		if trace:
			var keys := _script_acc.keys()
			keys.sort_custom(func(a, b) -> bool: return _script_acc[a] > _script_acc[b])
			var n := maxi(_frames, 1)
			var total := 0.0
			for k in keys:
				total += _script_acc[k] / 1000.0 / n
			print("    scripts (ms por quadro, total %.2f): " % total + ", ".join(keys.slice(0, 14).map(func(k: String) -> String:
				return "%s %.3f" % [k, _script_acc[k] / 1000.0 / n])))
		if experiments:
			await _experiments(manager)
		scene.queue_free()
		await _wait(0.5)
	quit()


## Liga/desliga coisas de cada carro (menos o do jogador) em fatias alternadas: base, sem cada uma.
func _experiments(manager: RaceManager) -> void:
	var others: Array[F1Car] = []
	for e in manager.entries:
		if e != manager.player_entry and e.car:
			others.append(e.car)
	var toggles := {
		"sem IK dos pilotos": func(on: bool) -> void:
			for car in others:
				for m in car.find_children("*", "SkeletonModifier3D", true, false):
					(m as SkeletonModifier3D).active = on,
		"sem efeitos (Effects)": func(on: bool) -> void:
			for car in others:
				var fx := car.get_node_or_null("Effects")
				if fx:
					fx.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED,
		"sem som dos rivais": func(on: bool) -> void:
			for car in others:
				var au := car.get_node_or_null("Audio")
				if au:
					au.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED,
		"sem dano (Damage)": func(on: bool) -> void:
			for car in others:
				var dm := car.get_node_or_null("Damage")
				if dm:
					dm.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED,
	}
	for label: String in toggles:
		var base_acc := {}
		var off_acc := {}
		for rep in 2:
			_begin()
			await _wait(SLICE_S)
			var b := _end("  base")
			(toggles[label] as Callable).call(false)
			await _wait(0.5)
			_begin()
			await _wait(SLICE_S)
			var o := _end("  " + label)
			(toggles[label] as Callable).call(true)
			await _wait(0.5)
			for k in b:
				base_acc[k] = float(base_acc.get(k, 0.0)) + float(b[k]) / 2.0
				off_acc[k] = float(off_acc.get(k, 0.0)) + float(o[k]) / 2.0
		print("  → %s: física %+.2f ms, lógica %+.2f ms, desenho %+.2f ms por quadro" % [label,
			off_acc["física"] - base_acc["física"], off_acc["lógica"] - base_acc["lógica"], off_acc["desenho"] - base_acc["desenho"]])
