extends SceneTree
## Captura o menu de configurações (cada aba) e o monitor de desempenho (com janela).
##   godot --path . -s res://tests/capture_settings.gd -- <pasta de saída>
## As configurações do jogador são restauradas no fim.

var out_dir := "user://captures"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	_run.call_deferred()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("salvo ", name)


func _run() -> void:
	var settings := root.get_node("Settings") as GameSettings
	var backup := FileAccess.get_file_as_string(GameSettings.PATH) if FileAccess.file_exists(GameSettings.PATH) else ""
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var car := scene.get_node("F1Car") as F1Car
	for i in 90:
		await process_frame
	settings.open_menu()
	for k in SettingsMenu.TABS.size():
		settings._menu._show_tab(k)
		for i in 3:
			await process_frame
		await _snap("settings_%d_%s" % [k, SettingsMenu.TABS[k].to_lower()])
	# Captura de tecla em andamento
	settings._menu._show_tab(0)
	await process_frame
	await process_frame
	settings._menu.close()
	settings.set_value("performance", "overlay", 2)
	settings.set_value("performance", "corner", 2)
	car.player_controlled = false
	var t := 0.0
	while t < 4.0:
		car.throttle_input = 1.0
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	await _snap("perf_overlay")
	if backup != "":
		var f := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.PATH))
	quit()
