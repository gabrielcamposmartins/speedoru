extends SceneTree
## Onde vai o tempo de cada quadro numa corrida de verdade (com janela, vsync desligado): corrida
## solo com 9 bots e o carro do jogador também pilotado por um bot, câmera da corrida seguindo.
## Mede por segundo de jogo: GDScript (cada _process, _physics_process e _integrate_forces dos
## scripts, cronometrado), física do motor (fase de física menos os scripts dela), render na CPU,
## GPU e o quadro inteiro.
## Os scripts são cronometrados trocando o código só na memória (os arquivos não mudam): cada
## callback vira um invólucro que mede e chama o original.
##   godot --path . -s res://tests/frame_probe.gd -- [pistas: monza,monaco] [segundos] [puro] [--deep=race_manager,bot_driver]
## Usa as configurações gráficas do jogador (só lê) e um perfil de teste (user://test_frame_profile.cfg).

const CALLBACKS := ["_process", "_physics_process", "_integrate_forces"]
## Scripts que não são cronometrados: o menu e o que não roda na corrida offline.
const SKIP_DIRS := ["res://scripts/menu", "res://scripts/economy", "res://scripts/server", "res://scripts/update"]

var seconds := 25.0
## Sem cronometrar os scripts (para ver quanto a medição pesa)
var plain := false
## Scripts (nome do arquivo sem .gd) com todas as funções cronometradas (--deep=a,b), não só os callbacks.
var deep := PackedStringArray()
## Fases do quadro no thread principal (µs somados): física, quadro (_process e interface),
## desenho (RenderingServer.draw, inclui esperar a GPU) e o resto (apresentar, entrada, áudio).
var _phase_us := {"física": 0, "quadro": 0, "desenho": 0, "resto": 0}
var _phase := ""
var _phase_t := 0


func _initialize() -> void:
	_run.call_deferred()


func _scripts(dir: String, out: Array) -> void:
	if dir in SKIP_DIRS:
		return
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scripts(dir.path_join(d), out)


## Troca cada callback do script (ou, com `all`, cada função) por um invólucro que mede e chama a
## original (na memória). Funções com await ficam de fora. Devolve quantas trocou.
func _instrument(path: String, all := false) -> int:
	var script := load(path) as GDScript
	if script == null:
		return 0
	var lines := script.source_code.split("
")
	var out := PackedStringArray()
	var n := 0
	var rx := RegEx.create_from_string("^(\\s*)(static )?func (\\w+)\\(([^)]*)\\)(\\s*->\\s*([\\w\\[\\]\\.]+))?\\s*:\\s*$")
	for i in lines.size():
		var m := rx.search(lines[i])
		if m == null or not (all or m.get_string(3) in CALLBACKS) or _has_await(lines, i, m.get_string(1)):
			out.append(lines[i])
			continue
		var ind := m.get_string(1)
		var fn := m.get_string(3)
		var ret := m.get_string(6)
		var args := PackedStringArray()
		for a in m.get_string(4).split(",", false):
			args.append(a.split(":")[0].split("=")[0].strip_edges())
		var key := "%s:%s" % [path.get_file().get_basename(), fn]
		var head := "%s%sfunc %s(%s)%s:" % [ind, m.get_string(2), fn, m.get_string(4), (" -> " + ret) if ret != "" else ""]
		out.append(head)
		out.append("%s	var __t := Time.get_ticks_usec()" % ind)
		if ret == "void":
			out.append("%s	%s__p(%s)" % [ind, fn, ", ".join(args)])
		else:
			out.append("%s	var __r = %s__p(%s)" % [ind, fn, ", ".join(args)])
		out.append("%s	var __d: Dictionary = Engine.get_meta(&\"prof\")" % ind)
		out.append("%s	__d[\"%s\"] = int(__d.get(\"%s\", 0)) + Time.get_ticks_usec() - __t" % [ind, key, key])
		if ret != "void":
			out.append("%s	return __r" % ind)
		out.append("")
		out.append(head.replace("func %s(" % fn, "func %s__p(" % fn))
		n += 1
	if n == 0:
		return 0
	script.source_code = "
".join(out)
	var err := script.reload(true)
	if err != OK:
		print("  (não deu para cronometrar %s: erro %d)" % [path, err])
		return 0
	return n


## A função que começa na linha `at` (indentação `ind`) usa await.
func _has_await(lines: PackedStringArray, at: int, ind: String) -> bool:
	for j in range(at + 1, lines.size()):
		var l := lines[j]
		if l.strip_edges() != "" and not l.begins_with(ind + "	") and not l.begins_with(ind + " "):
			return false
		if l.contains("await "):
			return true
	return false


## Fecha a fase atual e abre a próxima.
func _mark(next: String) -> void:
	var now := Time.get_ticks_usec()
	if _phase != "":
		_phase_us[_phase] += now - _phase_t
	_phase = next
	_phase_t = now


func _on_physics_frame() -> void:
	if _phase != "física":
		_mark("física")


func _run() -> void:
	var tracks := ["monza", "monaco"]
	for a in OS.get_cmdline_user_args():
		if a.is_valid_float():
			seconds = float(a)
		elif a == "puro":
			plain = true
		elif a.begins_with("--deep="):
			deep = a.trim_prefix("--deep=").split(",")
		elif not a.begins_with("--"):
			tracks = a.split(",")
	Engine.set_meta(&"prof", {})
	var paths: Array = []
	_scripts("res://scripts", paths)
	var wrapped := 0
	if not plain:
		for p: String in paths:
			wrapped += _instrument(p, p.get_file().get_basename() in deep)
	print("callbacks cronometrados: %d" % wrapped)
	physics_frame.connect(_on_physics_frame)
	process_frame.connect(_mark.bind("quadro"))
	RenderingServer.frame_pre_draw.connect(_mark.bind("desenho"))
	RenderingServer.frame_post_draw.connect(_mark.bind("resto"))
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_frame_profile.cfg"
		profile.reset_profile()
	print("GPU: %s · %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	print("CPU: %s (%d núcleos)" % [OS.get_processor_name(), OS.get_processor_count()])
	print("janela: %s" % str(DisplayServer.window_get_size()))
	for id: String in tracks:
		await _race(id)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_frame_profile.cfg"))
	quit()


func _race(id: String) -> void:
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.opponents = 9
	RaceSettings.laps = 3
	RaceSettings.difficulty = 3
	RaceSettings.track = id
	RaceSettings.grid = RaceSettings.Grid.MIDDLE
	RaceSettings.skip_menu = true
	var scene := (load(RaceSettings.track_scene(id)) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	var manager := scene.get_node("RaceManager") as RaceManager
	while manager.state != RaceManager.State.GRID or manager.player_entry == null:
		await process_frame
	var pe := manager.player_entry
	var bot := BotDriver.new()
	pe.car.player_controlled = false
	pe.car.add_child(bot)
	bot.setup(pe.car, manager.track, manager.line, manager._profile(BotDriver.Difficulty.HARD), BotDriver.Difficulty.HARD, pe, manager)
	pe.bot = bot
	while manager.state != RaceManager.State.RACING:
		await process_frame
	bot.released = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# Deixa a largada assentar e mede
	await create_timer(5.0).timeout
	var vp := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 10:
		await process_frame
	var prof: Dictionary = Engine.get_meta(&"prof")
	prof.clear()
	for k in _phase_us:
		_phase_us[k] = 0
	var gpu := 0.0
	var rcpu := 0.0
	var draws := 0.0
	var frame_ms: Array[float] = []
	var steps0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < seconds * 1e6:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		rcpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var wall_s := (Time.get_ticks_usec() - t0) / 1e6
	var n := frame_ms.size()
	var steps := Engine.get_physics_frames() - steps0
	frame_ms.sort()
	var script_phys := 0
	var script_proc := 0
	for k: String in prof:
		if k.ends_with(":_process"):
			script_proc += prof[k]
		else:
			script_phys += prof[k]
	# Tudo em ms por segundo de jogo (1000 = um núcleo inteiro) e em ms por quadro
	var per_s := func(us: float) -> float: return us / 1000.0 / wall_s
	var avg := wall_s * 1000.0 / n
	print("\n%s: %.0f s, %d quadros, %d passos de física, %d carros" % [id, wall_s, n, steps, manager.entries.size()])
	print("  FPS médio %.0f · quadro médio %.2f ms · 1%% piores %.2f ms · pior %.2f ms" % [
		n / wall_s, avg, frame_ms[int(n * 0.99)], frame_ms[-1]])
	print("  GPU %.2f ms/quadro · render na CPU %.2f ms/quadro · %.0f desenhos" % [gpu / n, rcpu / n, draws / n])
	print("  por segundo de jogo (ms de CPU/s):")
	print("    GDScript na física   %6.1f" % per_s.call(script_phys))
	print("    GDScript no quadro   %6.1f" % per_s.call(script_proc))
	if not plain:
		print("    física do motor      %6.1f   (fase de física menos o GDScript dela)" % per_s.call(_phase_us["física"] - script_phys))
	print("    render na CPU        %6.1f" % (rcpu / wall_s))
	print("    GPU                  %6.1f" % (gpu / wall_s))
	print("  fases do thread principal (ms/s, somam ~1000):")
	for k: String in _phase_us:
		print("    %-20s %6.1f" % [k, per_s.call(_phase_us[k])])
	print("  GDScript mais caro (ms/s):")
	var keys := prof.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return prof[a] > prof[b])
	for k: String in keys.slice(0, 40 if not deep.is_empty() else 30):
		print("    %-36s %6.2f" % [k, per_s.call(prof[k])])
	scene.queue_free()
	current_scene = null
	for i in 10:
		await process_frame
