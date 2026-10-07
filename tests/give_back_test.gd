extends SceneTree
## Devolver a posição (sem janela):  godot --headless --path . -s res://tests/give_back_test.gd
## O jogador ganha uma posição de forma irregular: aviso com prazo; deixando passar, sem penalidade;
## sem devolver, +5 s no fim do prazo.

var failures := 0
var manager: RaceManager


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	RaceSettings.track = "monza"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.opponents = 1
	RaceSettings.laps = 3
	RaceSettings.quali_laps = 0
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_giveback_profile.cfg"
		profile.reset_profile()
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _place(e: RaceEntry, s: float) -> void:
	e.car.global_transform = manager.track.path.frame_at(s, 0.0 if e.is_player else 3.0, 0.3)
	e.car.linear_velocity = Vector3.ZERO
	e.car.reset_physics_interpolation()


func _run() -> void:
	while manager.state != RaceManager.State.RACING:
		await process_frame
	var pe := manager.player_entry
	var bot_e: RaceEntry = manager.entries[0] if manager.entries[0] != pe else manager.entries[1]
	bot_e.bot.released = false
	bot_e.car.hold = true
	pe.car.hold = true
	_place(bot_e, 600.0)
	_place(pe, 620.0)
	for k in 10:
		await physics_frame
	manager.request_give_back(pe, bot_e, 5.0, "TESTE", "passou por fora")
	_check(manager.give_backs.has(pe), "aviso para devolver a posição")
	_place(pe, 580.0)
	for k in 10:
		await physics_frame
	_check(not manager.give_backs.has(pe) and pe.penalty_seconds == 0.0, "deixou passar: resolvido sem penalidade")
	_place(pe, 620.0)
	for k in 10:
		await physics_frame
	manager.request_give_back(pe, bot_e, 5.0, "TESTE", "passou por fora")
	var t0 := manager.race_time
	while manager.race_time - t0 < RaceManager.GIVE_BACK_TIME + 0.5:
		await physics_frame
	_check(not manager.give_backs.has(pe) and pe.penalty_seconds == 5.0, "não devolveu: +5 s no fim do prazo")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_giveback_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
