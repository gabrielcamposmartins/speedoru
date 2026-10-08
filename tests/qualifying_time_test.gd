extends SceneTree
## Classificatória com tempo limite e sem anular volta por infração (sem janela):
##   godot --headless --path . -s res://tests/qualifying_time_test.gd
## Monza, voltas livres, 2 bots + o jogador pilotado por bot. Infrações não anulam a volta; quando o
## tempo acaba (encurtado no meio da volta cronometrada do jogador), ninguém começa volta nova, mas
## a volta em andamento termina e vale para o grid.

var failures := 0
var manager: RaceManager


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	RaceSettings.track = "monza"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 3
	RaceSettings.opponents = 2
	RaceSettings.difficulty = 2
	RaceSettings.quali_laps = RaceSettings.QUALI_FREE
	RaceSettings.quali_time = 1
	RaceSettings.quali_strict = false
	RaceSettings.quali_collisions = false
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_qualitime_profile.cfg"
		profile.reset_profile()
	var scene := (load(RaceSettings.track_scene("monza")) as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _run() -> void:
	while manager.state != RaceManager.State.QUALIFYING:
		await process_frame
	var q := manager.quali
	_check(q.laps < 0 and is_equal_approx(q.time_limit, 180.0) and not q.strict,
		"voltas livres, 3 min, infração não anula (laps %d, %.0f s, strict %s)" % [q.laps, q.time_limit, q.strict])
	_check(manager.quali_time_left() > 170.0, "relógio da sessão correndo (%.0f s)" % manager.quali_time_left())
	var pe := manager.player_entry
	var bot := BotDriver.new()
	pe.car.player_controlled = false
	pe.car.add_child(bot)
	bot.setup(pe.car, manager.track, manager.line, manager._profile(BotDriver.Difficulty.HARD), BotDriver.Difficulty.HARD, pe, manager)
	bot.pit_lap = -1
	bot.released = true
	pe.bot = bot
	manager.infraction.connect(func(e: RaceEntry, t: String, d: String, _pen: bool) -> void:
		if e == pe:
			print("  [%6.1f s] %s — %s" % [manager.race_time, t, d]))
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 2.0
	while q.data[pe]["start"] < 0.0:
		await physics_frame
	await create_timer(3.0, false).timeout
	manager.penalize_entry(pe, 5.0, "TESTE", "penalidade de teste")
	q.invalidate(pe, "SAIU DA PISTA")
	_check(not q.data[pe]["invalid"] and pe.penalty_seconds == 0.0, "infração não anula a volta nem soma segundos")
	# O tempo acaba agora, no meio da volta cronometrada do jogador
	q.time_limit = manager.race_time + 0.5
	await create_timer(1.0, false).timeout
	_check(q.time_up, "tempo esgotado")
	_check(not q.data[pe]["done"], "volta em andamento continua valendo")
	var others_done := true
	for e: RaceEntry in q.data:
		var d: Dictionary = q.data[e]
		if e != pe and d["start"] < 0.0:
			others_done = others_done and d["done"]
	_check(others_done, "quem ainda estava na volta de saída encerrou")
	while manager.state == RaceManager.State.QUALIFYING:
		await physics_frame
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 120
	print("  jogador: ", q.data[pe])
	_check(int(q.data[pe]["laps"]) == 1 and q.best_of(pe) > 0.0,
		"a volta terminou depois do tempo e conta para o grid (%s)" % RaceManager.format_time(q.best_of(pe)))
	_check(pe.grid_slot == 0 or q.classification().find(pe) == pe.grid_slot, "grid montado pela classificatória")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_qualitime_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
