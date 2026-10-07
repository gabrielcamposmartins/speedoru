extends SceneTree
## Classificatória (sem janela):  godot --headless --path . -s res://tests/qualifying_test.gd
## Mônaco, 1 volta cronometrada, sem colisão, 3 bots + o jogador pilotado por bot: a sessão acaba,
## penalidade só anula a volta (sem segundos), o grid sai na ordem das melhores voltas, os carros
## voltam a colidir e a corrida larga do zero.

var failures := 0
var manager: RaceManager


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	RaceSettings.track = "monaco"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 3
	RaceSettings.opponents = 3
	RaceSettings.difficulty = 2
	RaceSettings.quali_laps = 1
	RaceSettings.quali_collisions = false
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_quali_profile.cfg"
		profile.reset_profile()
	var scene := (load(RaceSettings.track_scene("monaco")) as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _run() -> void:
	while manager.state != RaceManager.State.QUALIFYING:
		await process_frame
	# Jogador pilotado por um bot
	var pe := manager.player_entry
	var bot := BotDriver.new()
	pe.car.player_controlled = false
	pe.car.add_child(bot)
	bot.setup(pe.car, manager.track, manager.line, manager._profile(BotDriver.Difficulty.HARD), BotDriver.Difficulty.HARD, pe, manager)
	bot.pit_lap = -1
	bot.released = true
	pe.bot = bot
	manager.infraction.connect(func(e: RaceEntry, t: String, d: String, _pen: bool) -> void:
		print("  [%6.1f s] %s %s — %s (s=%.0f lat=%.1f)" % [manager.race_time, e.code, t, d, e.s, e.lateral]))
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 2.0
	var a := manager.entries[1].car
	var b := manager.entries[2].car
	_check(a.get_collision_exceptions().has(b), "sem colisão na classificatória (exceção entre os carros)")
	# Penalidade no meio da volta cronometrada: só anula a volta
	while manager.quali.data[pe]["start"] < 0.0:
		await physics_frame
	await create_timer(3.0, false).timeout
	manager.penalize_entry(pe, 5.0, "TESTE", "penalidade de teste")
	_check(pe.penalty_seconds == 0.0 and manager.quali.data[pe]["invalid"], "penalidade na classificatória anula a volta, sem somar segundos")
	while manager.state == RaceManager.State.QUALIFYING:
		await physics_frame
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 120
	var q := manager.quali
	print("  fim da classificatória em %.1f s" % manager.race_time)
	for e in q.data:
		print("   ", e.code, " ", q.data[e])
	var times := []
	for e in manager.entries:
		times.append([e.grid_slot, q.best_of(e), e.code])
	times.sort()
	print("  grid: ", times)
	_check(q.best_of(pe) == 0.0, "volta anulada não conta (jogador sem tempo)")
	_check(manager.entries.size() == 4 and _sorted(times), "grid na ordem das melhores voltas, sem tempo atrás")
	var on_grid := true
	for e in manager.entries:
		on_grid = on_grid and e.car.global_position.distance_to(manager.track.get_grid_transform(e.grid_slot).origin) < 1.0
	_check(on_grid, "todos no grid na posição da classificatória")
	_check(pe.car.get_collision_exceptions().is_empty(), "o jogador volta a colidir")
	_check(pe.penalty_seconds == 0.0 and pe.best_lap == 0.0, "corrida começa sem tempos nem penalidades")
	while manager.state != RaceManager.State.RACING:
		await process_frame
	_check(pe.laps_completed() == 0, "largada com zero voltas completadas")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_quali_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)


func _sorted(rows: Array) -> bool:
	var last := 0.0
	var no_time := false
	for r in rows:
		var t: float = r[1]
		if t <= 0.0:
			no_time = true
		elif no_time or t < last:
			return false
		else:
			last = t
	return true
