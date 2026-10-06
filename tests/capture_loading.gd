extends SceneTree
## Captura a tela de carregamento (com janela): abertura do circuito e montagem do grid.
## godot --path . -s res://tests/capture_loading.gd -- <pasta de saída>

var out_dir := "user://captures"
var shots := 0
var log_lines: PackedStringArray = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 10
	RaceSettings.opponents = 9
	RaceSettings.skip_menu = false
	_run.call_deferred()


func _snap(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	shots += 1
	var loading := root.get_node("Loading") as LoadingScreen
	var path := "%s/loading_%02d_%s.png" % [out_dir, shots, tag]
	img.save_png(path)
	print("%s  %.0f%%  %s" % [path.get_file(), loading.progress * 100.0, loading.stage])


func _run() -> void:
	var loading := root.get_node_or_null("Loading") as LoadingScreen
	if loading == null:
		print("ERRO: autoload Loading ausente")
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	loading.change_scene("res://scenes/tracks/monza.tscn")
	var last := -1.0
	while loading.active:
		await process_frame
		if loading.progress - last >= 0.12 or (last < 0.0):
			last = loading.progress
			await _snap("cena")
	print("Cena carregada em %d ms" % (Time.get_ticks_msec() - t0))
	for i in 20:
		await process_frame
	await _snap("menu")
	var manager := current_scene.get_node("RaceManager") as RaceManager
	t0 = Time.get_ticks_msec()
	manager._start()
	last = -1.0
	while loading.active:
		await process_frame
		if loading.progress - last >= 0.3 or last < 0.0:
			last = loading.progress
			await _snap("grid")
	print("Grid montado em %d ms" % (Time.get_ticks_msec() - t0))
	for i in 40:
		await process_frame
	await _snap("largada")
	quit()
