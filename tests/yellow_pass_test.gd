extends SceneTree
## Ultrapassagem do jogador sob bandeira amarela (sem janela):
##   godot --headless --path . -s res://tests/yellow_pass_test.gd
## Com a amarela de uma batida de bot, o jogador passa outro bot (carros posicionados de verdade):
## aparece o aviso para devolver a posição, e sem devolver leva a penalidade no fim do prazo.

var failures := 0
var manager: RaceManager
var notices: Array = []


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_yellowpass_profile.cfg"
		profile.reset_profile()
	RaceSettings.track = "monza"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 5
	RaceSettings.opponents = 2
	RaceSettings.quali_laps = 0
	RaceSettings.skip_menu = true
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _place(e: RaceEntry, s: float, lateral: float) -> void:
	e.car.global_transform = manager.track.path.frame_at(s, lateral, 0.3)
	e.car.linear_velocity = manager.track.path.tangent_at(s) * 5.0
	e.car.angular_velocity = Vector3.ZERO
	e.car.reset_physics_interpolation()


func _run() -> void:
	while manager.state != RaceManager.State.RACING:
		await process_frame
	manager.infraction.connect(func(e: RaceEntry, title: String, _d: String, _pen: bool) -> void:
		if e.is_player:
			notices.append(title))
	var pe := manager.player_entry
	pe.car.player_controlled = false
	var bots: Array[RaceEntry] = []
	for e in manager.entries:
		if e != pe:
			bots.append(e)
	for b in bots:
		b.bot.released = false
		b.car.hold = true
	pe.car.hold = true
	await create_timer(1.0, false).timeout
	# Amarela: batida do segundo bot
	manager.control.report_crash(bots[1])
	_check(manager.control.yellow, "amarela com a batida do bot")
	var other := bots[0]
	_place(other, 900.0, -2.0)
	other.car.linear_velocity = Vector3.ZERO
	_place(pe, 880.0, 2.0)
	for k in 30:
		await physics_frame
	# O jogador passa o bot devagar
	for k in 50:
		_place(pe, 880.0 + k * 1.0, 2.0)
		await physics_frame
	await physics_frame
	print("  avisos: ", notices)
	_check(manager.give_backs.has(pe), "aviso para devolver a posição (pendente)")
	_check(notices.has("DEVOLVA A POSIÇÃO"), "banner DEVOLVA A POSIÇÃO")
	var pen := pe.penalty_seconds
	var t0 := manager.race_time
	while manager.race_time - t0 < RaceManager.GIVE_BACK_TIME + 1.0:
		await physics_frame

	_check(pe.penalty_seconds >= pen + 10.0, "sem devolver: +10 s (%.0f → %.0f)" % [pen, pe.penalty_seconds])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_yellowpass_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
