extends SceneTree
## Atlas da sombra do sol (com janela, vsync desligado): em pontos da volta de cada pista, alterna os
## tamanhos dados várias vezes medindo o tempo de GPU (média por tamanho, mais robusta com outro
## programa usando a placa) e salva capturas para comparar a imagem: duas seguidas com o primeiro
## tamanho (o que muda sozinho: vento, grama, partículas) e uma com cada outro tamanho.
##   godot --path . -s res://tests/shadow_atlas_probe.gd -- <pasta> [pistas] [tamanhos: 16384,8192]

const POINTS := [0.25, 0.5, 0.75]
const REPEATS := 3
const SAMPLE_S := 1.2

var out_dir := ""


func _initialize() -> void:
	# Com janela e sem --offline o Net conecta sozinho com a conta real e regrava o account.cfg do
	# jogador: desconecta e passa a gravar num arquivo de teste
	var net := root.get_node_or_null("Net")
	if net and not "--offline" in OS.get_cmdline_user_args():
		net.account_file = "user://test_atlas_account.cfg"
		net.disconnect_from_server()
		net._retry = 0.0
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _gpu(seconds: float) -> float:
	var vp := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _frames(8)
	var acc := 0.0
	var n := 0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < seconds * 1e6:
		await process_frame
		acc += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		n += 1
	return acc / maxf(n, 1)


func _shot(file: String) -> void:
	await _frames(12)
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))


func _run() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool: return not a.begins_with("--"))
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir().path_join("shadow_atlas")
	var tracks: PackedStringArray = (args[1] as String).split(",") if args.size() > 1 else PackedStringArray(["suzuka", "monza", "las_vegas"])
	var sizes: Array = Array((args[2] as String).split(",")).map(func(x: String) -> int: return int(x)) if args.size() > 2 else [16384, 8192]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_perf_profile.cfg"
		profile.reset_profile()
	for id in tracks:
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
		for f: float in POINTS:
			car.global_transform = path.frame_at(path.length * f + 30.0, 0.0, 0.6)
			car.reset_physics_interpolation()
			await _frames(20)
			var acc := {}
			for rep in REPEATS:
				for size: int in sizes:
					RenderingServer.directional_shadow_atlas_set_size(size, true)
					acc[size] = float(acc.get(size, 0.0)) + await _gpu(SAMPLE_S) / REPEATS
			var line := "%s %.2f: " % [id, f]
			for size: int in sizes:
				line += "atlas %d → GPU %.2f ms  " % [size, acc[size]]
			print(line)
			RenderingServer.directional_shadow_atlas_set_size(sizes[0], true)
			await _shot("%s_%.2f_a.png" % [id, f])
			await _shot("%s_%.2f_b.png" % [id, f])
			for k in range(1, sizes.size()):
				RenderingServer.directional_shadow_atlas_set_size(sizes[k], true)
				await _shot("%s_%.2f_%d.png" % [id, f, sizes[k]])
			RenderingServer.directional_shadow_atlas_set_size(sizes[0], true)
		scene.queue_free()
		await _frames(10)
	quit()
