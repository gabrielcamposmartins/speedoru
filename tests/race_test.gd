extends SceneTree
## Corrida de teste (sem janela), com o carro do jogador também pilotado por um bot:
##   godot --headless --path . -s res://tests/race_test.gd -- [voltas] [adversários] [dificuldade 0-3]
## Confere que todos completam as voltas, fazem o pit obrigatório e quase não levam penalidades.

var scene: Node3D
var manager: RaceManager
var failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = int(args[0]) if args.size() > 0 else 3
	RaceSettings.opponents = int(args[1]) if args.size() > 1 else 9
	RaceSettings.difficulty = int(args[2]) if args.size() > 2 else 3
	RaceSettings.grid = RaceSettings.Grid.MIDDLE
	RaceSettings.skip_menu = true
	Engine.max_physics_steps_per_frame = 200
	# Perfil de teste (não mexe nos créditos/coleção do jogador)
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_profile.cfg"
		profile.reset_profile()
	scene = (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _run() -> void:
	while manager.state != RaceManager.State.GRID:
		await process_frame
	# Jogador pilotado por um bot difícil
	var pe := manager.player_entry
	var bot := BotDriver.new()
	pe.car.player_controlled = false
	pe.car.add_child(bot)
	bot.setup(pe.car, manager.track, manager.line, manager._profile(BotDriver.Difficulty.HARD), BotDriver.Difficulty.HARD, pe, manager)
	bot.pit_lap = 2
	pe.bot = bot
	manager.infraction.connect(func(e: RaceEntry, t: String, d: String, pen: bool) -> void:
		print("  [%6.1f s] %s %s: %s — %s" % [manager.race_time, e.code, "PENALIDADE" if pen else "aviso", t, d]))
	while manager.state != RaceManager.State.RACING:
		await process_frame
	bot.released = true
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 2.0
	var t0 := Time.get_ticks_msec()
	var last_report := 0.0
	var limit := RaceSettings.laps * 140.0 + 120.0
	while not manager._all_finished() and manager.race_time < limit:
		await process_frame
		if manager.race_time - last_report > 30.0:
			last_report = manager.race_time
			var line := "t=%5.0f s:" % manager.race_time
			for e in manager.entries:
				line += " %s(v%d %.0fkm/h%s)" % [e.code, e.crossings, e.car.speed_kmh, " BOX" if e.in_pit else ""]
			print(line)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 120
	print("Tempo real: %.1f s para %.1f s de corrida" % [(Time.get_ticks_msec() - t0) / 1000.0, manager.race_time])
	print("POS PILOTO          DIF  VOLTAS  TEMPO       MELHOR     PITS PENAL")
	var all_pitted := true
	var penalties := 0
	for e in manager.final_classification():
		print("%2d  %-15s %-4s %3d   %-10s  %-9s  %d    %ds %s" % [e.position, e.name, ("JOG" if e.is_player else ["F", "M", "D"][e.difficulty]),
			e.laps_completed(), RaceManager.format_time(e.total_time()), RaceManager.format_time(e.best_lap), e.pit_count,
			roundi(e.penalty_seconds), ("DSQ " + e.dsq_reason) if e.disqualified else ""])
		all_pitted = all_pitted and e.pit_count >= 1
		penalties += e.penalties.size()
	_check(manager._all_finished(), "todos terminaram a corrida")
	_check(all_pitted, "todos fizeram o pit stop obrigatório")
	_check(penalties <= manager.entries.size(), "poucas penalidades entre os bots (%d)" % penalties)
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
