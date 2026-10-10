extends SceneTree
## Diagnóstico (sem janela): um bot sozinho dá voltas e registra onde perde velocidade, sai da
## linha ou bate.  godot --headless --path . -s res://tests/track_bot_probe.gd -- [pista] [voltas] [dificuldade]

var scene: Node3D
var manager: RaceManager


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	RaceSettings.track = RaceSettings.valid_track(args[0]) if args.size() > 0 else "monaco"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = int(args[1]) if args.size() > 1 else 2
	RaceSettings.opponents = int(args[3]) if args.size() > 3 else 0
	RaceSettings.skip_menu = true
	var difficulty := int(args[2]) if args.size() > 2 else 2
	set_meta("pit", args.size() > 4 and args[4] == "pit")
	set_meta("difficulty", difficulty)
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_probe_profile.cfg"
		profile.reset_profile()
	scene = (load(RaceSettings.track_scene(RaceSettings.track)) as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _run() -> void:
	while manager.state != RaceManager.State.GRID:
		await process_frame
	var pe := manager.player_entry
	var args_pit: bool = get_meta("pit")
	var bot := BotDriver.new()
	pe.car.player_controlled = false
	pe.car.add_child(bot)
	var diff: int = get_meta("difficulty")
	bot.setup(pe.car, manager.track, manager.line, manager._profile(diff), diff, pe, manager)
	bot.pit_lap = 1 if args_pit else 99
	pe.bot = bot
	# Com adversários: todos param na mesma volta (engarrafamento nos boxes)
	for e in manager.entries:
		if e.bot and e != pe:
			e.bot.pit_lap = 1
	manager.infraction.connect(func(e: RaceEntry, t: String, d: String, pen: bool) -> void:
		if e != pe:
			print("  [%6.1f s] %s %s: %s" % [manager.race_time, e.code, t, d]))
	manager.infraction.connect(func(e: RaceEntry, t: String, d: String, pen: bool) -> void:
		print("  [%6.1f s] s=%.0f lat=%.1f %.0f km/h  %s: %s" % [manager.race_time, e.s, e.lateral, e.car.speed_kmh, t, d]))
	while manager.state != RaceManager.State.RACING:
		await process_frame
	bot.released = true
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 2.0
	var last := -10.0
	var lap := 0
	var prev_v := 0.0
	var reported := -10.0
	var path := manager.track.path
	# 6º argumento opcional "inicio-fim": trecho (s, m) com registro a cada 0,1 s
	var detail_range := Vector2(INF, -INF)
	var args := OS.get_cmdline_user_args()
	if args.size() > 5 and "-" in args[5]:
		detail_range = Vector2(float(args[5].get_slice("-", 0)), float(args[5].get_slice("-", 1)))
	while not manager._all_finished() and manager.race_time < RaceSettings.laps * 200.0:
		await physics_frame
		# Saída dos boxes: o que há logo à frente do carro
		if bot.mode == BotDriver.Mode.PIT_OUT and pe.s > 120.0 and pe.s < 200.0:
			var space := pe.car.get_world_3d().direct_space_state
			for h: float in [0.25, 0.6]:
				for side_off: float in [-0.9, 0.0, 0.9]:
					var from := pe.car.global_position + pe.car.global_basis.y * h + pe.car.global_basis.x * side_off
					var q := PhysicsRayQueryParameters3D.create(from, from + pe.car.global_basis.z * 5.0)
					q.exclude = [pe.car.get_rid()]
					var hit := space.intersect_ray(q)
					if not hit.is_empty() and Engine.get_physics_frames() % 6 == 0:
						var pr := manager.track.path.project(hit.position)
						print("    à frente (h %.2f lado %.1f): %s em s=%.0f lat=%.1f y=%.2f" % [h, side_off,
							str((hit.collider as Node).name), pr.x, pr.y, hit.position.y - manager.track.path.position_at(pr.x).y])
		# Freada brusca (batida): o que está encostado no carro
		var v := pe.car.speed_kmh
		if prev_v - v > 6.0 and manager.race_time - reported > 3.0:
			reported = manager.race_time
			_contacts(pe)
		prev_v = v
		if pe.crossings != lap:
			lap = pe.crossings
			print("volta %d em %.1f s (melhor %s)" % [lap, manager.race_time, RaceManager.format_time(pe.best_lap)])
		var detail := pe.s >= detail_range.x and pe.s <= detail_range.y
		if manager.race_time - last >= (0.1 if detail else 0.5 if bot.mode != BotDriver.Mode.RACE or (pe.s > 3100 or pe.s < 260) else 2.0) and RaceSettings.opponents == 0:
			last = manager.race_time
			var target := RacingLine.sample(bot.profile, path, pe.s)
			var line_lat := bot.line.lateral_at(pe.s)
			print("  t=%5.1f s=%6.0f lat %5.1f (linha %5.1f) %3.0f km/h (alvo %3.0f) y %.1f modo %s" % [manager.race_time, pe.s, pe.lateral,
				line_lat, pe.car.speed_kmh, target * 3.6, pe.car.global_position.y - path.position_at(pe.s).y, BotDriver.Mode.keys()[bot.mode]])
	print("Fim: %d voltas, melhor %s" % [pe.laps_completed(), RaceManager.format_time(pe.best_lap)])
	for e in manager.entries:
		print("  %s: %d voltas, %d pits, %s | modo %s s=%.0f lat=%.1f %.0f km/h hold %s in_pit %s parado %s" % [e.code, e.laps_completed(), e.pit_count,
			"terminou" if e.finished else "NÃO terminou", BotDriver.Mode.keys()[e.bot.mode] if e.bot else "-", e.s, e.lateral,
			e.car.speed_kmh, e.car.hold, e.in_pit, e.in_pit_stop])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_probe_profile.cfg"))
	quit(0)


func _contacts(pe: RaceEntry) -> void:
	var car := pe.car
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 1.6, 6.2)
	q.shape = box
	q.transform = Transform3D(car.global_basis, car.global_position + car.global_basis.y * 0.6)
	q.exclude = [car.get_rid()]
	var hits := car.get_world_3d().direct_space_state.intersect_shape(q, 8)
	var names := []
	for h in hits:
		names.append(str((h.collider as Node).get_path()).replace("/root/Monaco/Track/Generated/", ""))
	print("    batida em s=%.0f lat=%.1f y=%.2f (pista %.2f): %s" % [pe.s, pe.lateral, car.global_position.y,
		manager.track.path.position_at(pe.s).y, ", ".join(names)])
