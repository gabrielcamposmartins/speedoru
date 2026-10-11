extends SceneTree
## Desempenho das pistas (com janela, vsync desligado): corrida solo com 9 bots parados no grid; o
## carro do jogador é posto em alguns pontos da volta (a câmera da corrida segue) e mede FPS, tempo
## de CPU e de GPU, chamadas de desenho e triângulos. Com "grupos", desliga um grupo de nós da pista
## de cada vez e mede quanto cada um custa.
##   godot --path . -s res://tests/perf_probe.gd -- [pistas: monza,suzuka,monaco] [grupos]

const POINTS := [0.0, 0.25, 0.5, 0.75]
const SAMPLE_S := 2.5

var by_group := false
## Média da última amostra: [scripts (_process), física, render na CPU] em ms.
var _cpu := [0.0, 0.0, 0.0]
var pines := false


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Média de [fps, ms do quadro, ms da GPU, chamadas de desenho, triângulos (mil), objetos].
func _sample(seconds: float) -> Array:
	var vp := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _frames(10)
	var n := 0
	_cpu = [0.0, 0.0, 0.0]
	var acc := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < seconds * 1e6:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		acc[0] += 1000.0 / maxf(ms, 0.01)
		acc[1] += ms
		acc[2] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		acc[3] += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		acc[4] += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0
		acc[5] += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		_cpu[0] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_cpu[1] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_cpu[2] += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		n += 1
	_cpu = _cpu.map(func(x: float) -> float: return x / maxf(n, 1))
	return acc.map(func(x: float) -> float: return x / maxf(n, 1))


func _run() -> void:
	var tracks := ["monza", "suzuka"]
	for a in OS.get_cmdline_user_args():
		if a == "grupos":
			by_group = true
		elif a == "pinheiros":
			pines = true
		elif not a.begins_with("--"):
			tracks = a.split(",")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_perf_profile.cfg"
		profile.reset_profile()
	for id: String in tracks:
		RaceSettings.mode = RaceSettings.Mode.RACE
		RaceSettings.opponents = 9
		RaceSettings.laps = 3
		RaceSettings.track = id
		RaceSettings.skip_menu = true
		var scene := (load(RaceSettings.track_scene(id)) as PackedScene).instantiate()
		root.add_child(scene)
		current_scene = scene
		var manager := scene.get_node("RaceManager") as RaceManager
		while manager.state != RaceManager.State.GRID:
			await process_frame
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		await _frames(30)
		var car := manager.player
		car.freeze = true
		var path := manager.track.path
		var total := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		print("%s:" % id)
		for f: float in POINTS:
			var s := path.length * f + 30.0
			car.global_transform = path.frame_at(s, 0.0, 0.6)
			car.reset_physics_interpolation()
			await _frames(20)
			var r := await _sample(SAMPLE_S)
			print("  ponto %.2f: %4.0f fps · quadro %.1f ms · GPU %.1f ms · %4.0f desenhos · %5.0f mil triângulos · %4.0f objetos" % [
				f, r[0], r[1], r[2], r[3], r[4], r[5]])
			print("            CPU: scripts %.1f ms · física %.1f ms · render %.1f ms" % [_cpu[0], _cpu[1], _cpu[2]])
			for k in 6:
				total[k] += r[k] / POINTS.size()
		print("  média: %4.0f fps · quadro %.1f ms · GPU %.1f ms · %4.0f desenhos · %5.0f mil triângulos" % [total[0], total[1], total[2], total[3], total[4]])
		if by_group:
			await _groups(manager, path.length * 0.5 + 30.0)
		if pines:
			await _pines(manager, path.length * 0.75 + 30.0)
		scene.queue_free()
		await _frames(10)
	quit()


## Opções para os pinheiros (o grupo mais caro na GPU), no ponto dado.
func _pines(manager: RaceManager, s: float) -> void:
	var car := manager.player
	car.global_transform = manager.track.path.frame_at(s, 0.0, 0.6)
	car.reset_physics_interpolation()
	await _frames(20)
	var root := manager.track.get_node("Generated/Pines")
	var near: Array[GeometryInstance3D] = []
	var far: Array[GeometryInstance3D] = []
	for c in root.get_children():
		if str(c.name).ends_with("_shadow"):
			continue
		(far if str(c.name).ends_with("_far") else near).append(c)
	var base := await _sample(SAMPLE_S)
	print("  pinheiros (base %.1f ms GPU, %.0f mil triângulos):" % [base[2], base[4]])
	for n in near:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r := await _sample(SAMPLE_S)
	print("    sem sombra dos de perto → GPU %.1f ms, %.0f mil triângulos" % [r[2], r[4]])
	for n in near:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for d in [250.0, 150.0]:
		for n in near:
			n.visibility_range_end = d
		for f in far:
			f.visibility_range_begin = d
		r = await _sample(SAMPLE_S)
		print("    versão leve a partir de %.0f m → GPU %.1f ms, %.0f mil triângulos" % [d, r[2], r[4]])
	for n in near:
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r = await _sample(SAMPLE_S)
	print("    leve a partir de 150 m e sem sombra → GPU %.1f ms, %.0f mil triângulos" % [r[2], r[4]])


## Custo de cada grupo de nós da pista (desliga um de cada vez, no meio da volta).
func _groups(manager: RaceManager, s: float) -> void:
	var car := manager.player
	car.global_transform = manager.track.path.frame_at(s, 0.0, 0.6)
	car.reset_physics_interpolation()
	await _frames(20)
	var base := await _sample(SAMPLE_S)
	print("  grupos (base %.1f ms quadro, %.1f ms GPU, %d desenhos):" % [base[1], base[2], base[3]])
	var gen := manager.track.get_node("Generated")
	for child in gen.get_children():
		if not child is Node3D:
			continue
		var node := child as Node3D
		node.visible = false
		var r := await _sample(1.5)
		node.visible = true
		var saved_ms: float = base[1] - r[1]
		var saved_gpu: float = base[2] - r[2]
		if saved_ms > 0.3 or saved_gpu > 0.3 or base[3] - r[3] > 20:
			print("    sem %-24s → quadro -%.1f ms, GPU -%.1f ms, -%d desenhos, -%.0f mil triângulos" % [
				node.name, saved_ms, saved_gpu, base[3] - r[3], base[4] - r[4]])
