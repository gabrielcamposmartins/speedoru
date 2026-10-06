extends SceneTree
## Captura a interface retrofuturista (com janela): garagem aberta e o HUD em corrida em cada
## paleta. godot --path . -s res://tests/capture_ui.gd -- <pasta de saída>

var out_dir := "user://captures"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 10
	RaceSettings.opponents = 9
	RaceSettings.skip_menu = true
	_run.call_deferred()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("salvo ", name)


func _run() -> void:
	var previous := Retro.palette_id
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var manager := scene.get_node("RaceManager") as RaceManager
	while manager.state != RaceManager.State.RACING:
		await process_frame
	var car := scene.get_node("F1Car") as F1Car
	car.player_controlled = false
	var t := 0.0
	while t < 5.0:
		car.throttle_input = 1.0
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	for id in Retro.PALETTE_ORDER:
		Retro.set_palette(id)
		for i in 3:
			await process_frame
		await _snap("ui_" + id)
	Retro.set_palette(previous)
	var hud := scene.get_node("HUD") as RaceHud
	hud.garage.visible = true
	for i in 3:
		await process_frame
	await _snap("ui_garage")
	quit()
