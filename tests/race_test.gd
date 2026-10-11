extends SceneTree
## Corrida de teste (sem janela), com o carro do jogador também pilotado por um bot:
##   godot --headless --path . -s res://tests/race_test.gd -- [voltas] [adversários] [dificuldade 0-3] [pista: monza|monaco]
## Confere que todos completam as voltas, fazem o pit obrigatório e quase não levam penalidades.
## Mede também: toques nos boxes (dois carros se sobrepondo na área dos boxes), ultrapassagens na
## pista (troca de ordem entre dois carros perto, nenhum nos boxes), colisões punidas e, nos bots,
## quantas vezes deram ré para sair do muro e foram levados de volta à pista.

var scene: Node3D
var manager: RaceManager
var failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = int(args[0]) if args.size() > 0 else 3
	RaceSettings.opponents = int(args[1]) if args.size() > 1 else 9
	RaceSettings.difficulty = int(args[2]) if args.size() > 2 else 3
	RaceSettings.track = RaceSettings.valid_track(args[3]) if args.size() > 3 else "monza"
	RaceSettings.grid = RaceSettings.Grid.MIDDLE
	RaceSettings.skip_menu = true
	Engine.max_physics_steps_per_frame = 200
	# Perfil de teste (não mexe nos créditos/coleção do jogador)
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_profile.cfg"
		profile.reset_profile()
	scene = (load(RaceSettings.track_scene(RaceSettings.track)) as PackedScene).instantiate()
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
		if pen and (t + d).to_lower().contains("colis"):
			collisions += 1
		if t.contains("BATIDA") and e.bot:
			var near := ""
			for o in manager.entries:
				var ds: float = e.bot._ahead(o.s, e.s)
				if o != e and absf(ds) < 25.0:
					near += " %s(ds %.1f lat %.1f v %.0f%s)" % [o.code, ds, o.lateral, o.car.speed_kmh, " BOX" if manager._in_pit_area(o) else ""]
			print("    batida de %s: modo %s, s %.0f lat %.1f, %.0f km/h, nos boxes %s, rodas quebradas %s | perto:%s" % [e.code,
				BotDriver.Mode.keys()[e.bot.mode], e.s, e.lateral, e.car.speed_kmh, manager._in_pit_area(e), e.car.wheel_broken, near])
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
		_watch_stuck()
		_watch_metrics()
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
	print("Toques nos boxes: %d · ultrapassagens na pista: %d · colisões punidas: %d · ré para sair do muro: %d · levados de volta à pista: %d" % [
		pit_touches, overtakes, collisions, _static_count("reversals"), _static_count("put_backs")])
	_check(manager._all_finished(), "todos terminaram a corrida")
	_check(all_pitted, "todos fizeram o pit stop obrigatório")
	_check(penalties <= manager.entries.size(), "poucas penalidades entre os bots (%d)" % penalties)
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)


var _still := {}
var _reported := {}
var pit_touches := 0
var overtakes := 0
var collisions := 0
var _touching := {}
var _order := {}
var _dbg := 0


## Contador estático do BotDriver (-1 numa versão sem ele).
func _static_count(name: String) -> int:
	var v: Variant = (BotDriver as Script).get(name)
	return int(v) if v != null else -1


## Toques nos boxes e ultrapassagens na pista (pares de carros).
func _watch_metrics() -> void:
	if manager.state != RaceManager.State.RACING:
		return
	var list := manager.entries
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: RaceEntry = list[i]
			var b: RaceEntry = list[j]
			if a.car == null or b.car == null or a.retired or b.retired:
				continue
			var key := "%d_%d" % [mini(a.get_instance_id(), b.get_instance_id()), maxi(a.get_instance_id(), b.get_instance_id())]
			var pit := manager._in_pit_area(a) or manager._in_pit_area(b)
			if pit:
				var local := a.car.global_transform.affine_inverse() * b.car.global_position
				var touch := absf(local.x) < 1.9 and absf(local.z) < 4.6
				if touch and not _touching.get(key, false):
					pit_touches += 1
				_touching[key] = touch
			else:
				_touching[key] = false
			var diff := a.progress - b.progress
			var sign := diff > 0.0
			if _order.has(key) and _order[key] != sign and OS.get_environment("RACE_DEBUG") != "" and _dbg < 8:
				_dbg += 1
				print("  [troca] %s x %s diff %.1f pit %s fim %s %s" % [a.code, b.code, diff, pit, a.finished, b.finished])
			if _order.has(key) and _order[key] != sign and absf(diff) < 40.0 and not pit and not a.finished and not b.finished:
				overtakes += 1
			_order[key] = sign


## Diagnóstico: bot parado (< 1 km/h, sem terminar) por mais de 15 s imprime o estado completo uma vez.
func _watch_stuck() -> void:
	for e in manager.entries:
		if e.finished or e.retired or e.bot == null or manager.state != RaceManager.State.RACING:
			_still.erase(e)
			continue
		# Parado no box além da conta (o pit dura 2–4 s)
		if e.in_pit_stop:
			if not _still.has(e):
				_still[e] = manager.race_time
			elif manager.race_time - _still[e] > 25.0 and not _reported.has(e):
				_reported[e] = true
				var who := ""
				for o in manager.entries:
					var ds: float = e.bot._ahead(o.s, e.s)
					if o != e and o.in_pit and ds > -40.0 and ds < 10.0:
						who += " %s(ds %.1f lat %.1f v %.1f modo %s%s)" % [o.code, ds, o.lateral, o.car.linear_velocity.length(),
							BotDriver.Mode.keys()[o.bot.mode] if o.bot else "-", " PARADO" if o.in_pit_stop else ""]
				print("  PRESO NO BOX %s a %.0f s: modo %s timer %.1f liberado %s | s %.0f lat %.1f | box s %.0f | perto:%s" % [e.code,
					manager.race_time, BotDriver.Mode.keys()[e.bot.mode], e.bot._stop_timer, e.bot._pit_release_clear(e.s), e.s, e.lateral,
					manager.track.garage_s(e.garage), who])
			continue
		if e.car.speed_kmh > 1.0:
			_still.erase(e)
			continue
		if not _still.has(e):
			_still[e] = manager.race_time
		elif manager.race_time - _still[e] > 15.0 and not _reported.has(e):
			_reported[e] = true
			var b := e.bot
			var damage := e.car.get_node_or_null("Damage") as CarDamage
			var ahead := ""
			for o in manager.entries:
				var ds := b._ahead(o.s, e.s)
				if o != e and ds > -5.0 and ds < 40.0:
					ahead += " %s(ds %.1f lat %.1f v %.0f%s%s)" % [o.code, ds, o.lateral, o.car.speed_kmh, " PARADO-BOX" if o.in_pit_stop else "", " BOX" if o.in_pit else ""]
			print("  PRESO %s a %.0f s: modo %s in_pit %s hold %s rodas quebradas %s dano %.2f | gas %.2f freio %.2f dir %.2f | s %.0f lat %.1f | envolvido %s | perto:%s" % [
				e.code, manager.race_time, BotDriver.Mode.keys()[b.mode], e.in_pit, e.car.hold, e.car.wheel_broken,
				damage.get_overall() if damage else -1.0, e.car.throttle_input, e.car.brake_input, e.car.steer_input,
				e.s, e.lateral, manager.control.is_involved(e) if manager.control else false, ahead])
