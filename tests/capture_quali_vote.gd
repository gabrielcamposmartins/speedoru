extends SceneTree
## Screenshots das telas novas (com janela):
##   godot --path . -s res://tests/capture_quali_vote.gd -- <pasta>
## Menu da corrida com as opções da classificatória, relógio da classificatória no HUD e a faixa
## da votação para recomeçar (simulada, como chega do servidor).

var out_dir := ""
var manager: RaceManager


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_capqv_profile.cfg"
		profile.reset_profile()
	RaceSettings.track = "monza"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.opponents = 3
	RaceSettings.quali_laps = RaceSettings.QUALI_FREE
	RaceSettings.quali_time = 2
	RaceSettings.quali_strict = false
	RaceSettings.skip_menu = false
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _shot(name: String) -> void:
	for k in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(name))
	print("captura: ", name)


func _run() -> void:
	while manager.state != RaceManager.State.MENU:
		await process_frame
	await create_timer(1.5).timeout
	await _shot("menu_corrida.png")
	manager._start()
	while manager.state != RaceManager.State.QUALIFYING:
		await process_frame
	manager.player_entry.car.player_controlled = false
	await create_timer(4.0).timeout
	await _shot("quali_relogio.png")
	# Votação como o cliente recebe do servidor
	manager.vote_state = {"kind": "pause", "yes": 1, "needed": 2, "until": manager.race_time + 24.0, "voters": ["Alice"]}
	await _shot("votacao.png")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_capqv_profile.cfg"))
	quit()
