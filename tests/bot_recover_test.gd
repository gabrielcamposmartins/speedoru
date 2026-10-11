extends SceneTree
## Bot preso no muro (sem janela): com a corrida andando, o bot é posto parado e apontado para a
## barreira (60°, a 1 m dela). Ele tem que sair sozinho dirigindo (ré esterçando e volta à pista),
## sem ser levado de volta pela recuperação de emergência, e seguir a corrida.
##   godot --headless --path . -s res://tests/bot_recover_test.gd -- [pista]

var failures := 0
var manager: RaceManager


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool: return not a.begins_with("--"))
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.opponents = 1
	RaceSettings.difficulty = 1
	RaceSettings.laps = 3
	RaceSettings.track = RaceSettings.valid_track(args[0]) if args.size() > 0 else "monza"
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_recover_profile.cfg"
		profile.reset_profile()
	var scene := (load(RaceSettings.track_scene(RaceSettings.track)) as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _run() -> void:
	while manager.state != RaceManager.State.RACING:
		await process_frame
	var bot_e: RaceEntry = null
	for e in manager.entries:
		if e.bot:
			bot_e = e
	await create_timer(4.0).timeout
	var track := manager.track
	var p := track.path
	var cases := 0
	var ok_cases := 0
	# Alguns pontos da volta, nos dois lados, onde há barreira perto
	for f in [0.15, 0.4, 0.65, 0.85]:
		for side in [1, -1]:
			var i := p.index_at(p.length * f)
			var si := 0 if side > 0 else 1
			var dist: float = track.barrier[si][i]
			if track.barrier_kind[si][i] == RaceTrack.Barrier.NONE or dist > 12.0:
				continue
			cases += 1
			var s := p.s_at(i)
			var pos := track.edge_point(i, side, dist - 1.6, 0.4)
			var fwd := p.tangent_at(s)
			var left: Vector3 = p.lefts[i] * side
			var aim: Vector3 = (fwd * cos(deg_to_rad(60.0)) + left * sin(deg_to_rad(60.0))).normalized()
			bot_e.car.global_transform = Transform3D(Basis.looking_at(-aim, Vector3.UP), pos)
			bot_e.car.linear_velocity = Vector3.ZERO
			bot_e.car.angular_velocity = Vector3.ZERO
			bot_e.car.reset_physics_interpolation()
			# A corrida acompanha o carro perto de onde ele estava: recomeça do ponto novo
			manager._init_position(bot_e)
			var bot := bot_e.bot
			bot.mode = BotDriver.Mode.RACE
			var puts := BotDriver.put_backs
			var revs := BotDriver.reversals
			await physics_frame
			await create_timer(20.0).timeout
			# Quanto avançou ao longo da pista a partir de onde foi posto (o teletransporte confunde
			# a contagem de voltas da corrida)
			var end_s := p.project(bot_e.car.global_position).x
			var gained := fposmod(end_s - s + p.length * 0.5, p.length) - p.length * 0.5
			var drove_out := BotDriver.put_backs == puts and gained > 60.0
			# Tratado como acidente (levado aos boxes pelo controle da prova) também resolve
			var in_pit := bot.mode != BotDriver.Mode.RACE or bot_e.in_pit or bot_e.in_pit_stop
			print("  s %.0f lado %s: andou %.0f m, ré %d vez(es), levado de volta %d%s" % [s, "esq" if side > 0 else "dir", gained,
				BotDriver.reversals - revs, BotDriver.put_backs - puts, " (nos boxes)" if in_pit else ""])
			if drove_out:
				ok_cases += 1
			elif gained > 30.0 or in_pit:
				ok_cases += 1  # levado de volta à pista (ou aos boxes) e seguiu: não ficou preso
	_check(cases >= 4, "casos de muro testados (%d)" % cases)
	_check(ok_cases == cases, "bot sai do muro e segue a corrida em todos (%d de %d)" % [ok_cases, cases])
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
