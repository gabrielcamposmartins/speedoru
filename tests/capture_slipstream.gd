extends SceneTree
## Capturas do vácuo e do pisca dos retrovisores (com janela):
##   godot --path . -s res://tests/capture_slipstream.gd -- <pasta>
## Treino em Monza: um bot à frente na reta, o jogador colado atrás no rastro dele.

var out_dir := ""
var manager: RaceManager


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_capslip_profile.cfg"
		profile.reset_profile()
	RaceSettings.track = "monza"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.opponents = 1
	RaceSettings.quali_laps = 0
	RaceSettings.skip_menu = true
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _shot(name: String) -> void:
	for k in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(name))
	print("captura: ", name)


func _run() -> void:
	while manager.state != RaceManager.State.RACING:
		await process_frame
	var pe := manager.player_entry
	var other: RaceEntry = manager.entries[0] if manager.entries[0] != pe else manager.entries[1]
	other.bot.released = false
	pe.car.player_controlled = false
	var p := manager.track.path
	var s := 900.0
	# Os dois andando juntos a 250 km/h, o jogador 9 m atrás
	for k in 150:
		s += 70.0 / 60.0
		other.car.global_transform = p.frame_at(s, 0.0, 0.3)
		pe.car.global_transform = p.frame_at(s - 9.0, 0.2, 0.3)
		other.car.linear_velocity = p.tangent_at(s) * 70.0
		pe.car.linear_velocity = p.tangent_at(s) * 70.0
		if k == 100:
			other.car.pass_signal()
		await process_frame
		if k == 90:
			await _shot("slipstream.png")
		if k == 104:
			print("  leds: %d, signal_on %s, tempo %.2f" % [other.car._signal_leds.size(), other.car.signal_on, other.car.signal_time])
			for led in other.car._signal_leds:
				print("    led ", led.global_position - other.car.global_position, " visível ", led.is_visible_in_tree())
			await _shot("pass_signal.png")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_capslip_profile.cfg"))
	quit()
