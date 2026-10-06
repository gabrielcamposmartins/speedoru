extends SceneTree
## Captura (com janela) a bandeira amarela: instrução do jogador, safety car e minimapa.
##   godot --path . -s res://tests/capture_yellow.gd -- <pasta de saída>

var out_dir := "user://captures"
var manager: RaceManager


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_yellow_profile.cfg"
		profile.reset_profile()
		profile.set_finish("paint_finish", 1)
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.opponents = 9
	RaceSettings.skip_menu = true
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("salvo ", name)


func _run() -> void:
	while manager.state != RaceManager.State.RACING:
		await process_frame
	var car := manager.player
	car.player_controlled = false
	var t := 0.0
	while t < 14.0:
		car.throttle_input = 1.0
		car.steer_input = 0.0
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	# Um bot à frente bate: amarela; o jogador ainda sem limitador
	var bot: RaceEntry = null
	for e in manager.entries:
		if not e.is_player:
			bot = e
			break
	manager.control.report_crash(bot)
	for i in 30:
		await process_frame
	await _snap("yellow_limiter")
	car.limiter_on = true
	for i in 20:
		await process_frame
	await _snap("yellow_following")
	# Câmera atrás do safety car
	var cam := Camera3D.new()
	root.add_child(cam)
	var sc := manager.control.safety_car
	cam.global_position = sc.global_transform * Vector3(-3.0, 2.2, -8.0)
	cam.look_at(sc.global_position + Vector3.UP * 0.8)
	cam.current = true
	for i in 5:
		await process_frame
	await _snap("yellow_safety_car")
	cam.current = false
	manager.control.report_crash(manager.player_entry)
	for i in 20:
		await process_frame
	await _snap("yellow_crash")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_yellow_profile.cfg"))
	quit()
