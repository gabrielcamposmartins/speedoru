extends SceneTree
## Bandeira amarela e safety car (sem janela):
##   godot --headless --path . -s res://tests/race_control_test.gd
## Batida de bot (amarela, safety car, limitador nos bots, bot levado ao box, fim da amarela),
## batida do jogador (instrução com a tecla, tempo esgotado → box, volta recomeça) e penalidades
## (limitador desligado, passar o safety car). Usa um perfil de teste.

var failures := 0
var manager: RaceManager


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_rc_profile.cfg"
		profile.reset_profile()
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 5
	RaceSettings.opponents = 5
	RaceSettings.difficulty = 1
	RaceSettings.grid = RaceSettings.Grid.MIDDLE
	RaceSettings.skip_menu = true
	Engine.max_physics_steps_per_frame = 200
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _seconds(t: float) -> void:
	var end := manager.race_time + t
	while manager.race_time < end:
		await physics_frame


func _run() -> void:
	while manager.state != RaceManager.State.RACING:
		await process_frame
	var pe := manager.player_entry
	pe.car.player_controlled = false
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 2.0
	await _seconds(25.0)
	var rc := manager.control
	_check(rc != null and not rc.yellow, "corrida começa em bandeira verde")
	# Ultrapassagens de bots sob amarela (não devem acontecer)
	var bot_passes := [0]
	manager.infraction.connect(func(e: RaceEntry, title: String, _d: String, pen: bool) -> void:
		if pen and e.bot and title.begins_with("ULTRAPASSAGEM"):
			bot_passes[0] += 1)
	# --- Batida de um bot
	var bot_e: RaceEntry = null
	for e in manager.entries:
		if not e.is_player and not e.retired:
			bot_e = e
			break
	var lap := bot_e.current_lap()
	var done := bot_e.laps_completed()
	var times := bot_e.lap_times.size()
	rc.report_crash(bot_e)
	_check(rc.yellow and rc.is_involved(bot_e), "batida de bot: bandeira amarela")
	_check(rc.safety_car != null, "safety car entra na pista")
	await _seconds(1.0)
	var fast := 0
	for e in manager.entries:
		if e.bot and not rc.is_involved(e) and not e.in_pit and e.bot.mode == BotDriver.Mode.RACE 				and e.car.speed_kmh > SafetyCar.SPEED * 3.6 * 1.25:
			fast += 1
	_check(fast == 0, "bots seguram a velocidade sob amarela (sem limitador obrigatório)")
	var info := rc.instruction_for(pe)
	_check(not info.is_empty() and "ultrapasse" in str(info[1]) and "safety car sai em" in str(info[1]), "jogador recebe a instrução da amarela: %s" % (info[1] if not info.is_empty() else ""))
	await _seconds(RaceControl.BOT_PIT_DELAY + 1.0)
	_check(bot_e.in_pit_stop, "bot batido é levado ao box")
	_check(bot_e.current_lap() == lap and bot_e.lap_restart, "a volta do bot recomeça (volta %d)" % bot_e.current_lap())
	# Limitador não é obrigatório sob amarela
	pe.car.limiter_on = false
	var pen_before := pe.penalty_seconds
	await _seconds(7.0)
	_check(is_equal_approx(pe.penalty_seconds, pen_before), "sem limitador sob amarela: sem penalidade")
	await _seconds(RaceControl.REPAIR_TIME)
	_check(not rc.is_involved(bot_e) and rc.yellow and rc.safety_car != null, "conserto terminado: a amarela continua até o safety car completar a volta")
	var sc_lap := rc.sc_end - rc.safety_car.progress
	_check(sc_lap > 0.0 and sc_lap < manager.track.path.length,
		"safety car dura uma volta a partir de onde entrou (faltam %.0f m de %.0f)" % [sc_lap, manager.track.path.length])
	rc.safety_car.progress = rc.sc_end - 1.0
	await _seconds(0.5)
	_check(not rc.yellow and rc.safety_car == null, "safety car completou a volta: bandeira verde")
	var damage := bot_e.car.get_node("Damage") as CarDamage
	_check(damage.get_overall() > 0.99, "carro do bot consertado")
	var t := 0.0
	while bot_e.lap_restart and t < 25.0:
		await _seconds(0.5)
		t += 0.5
	_check(not bot_e.lap_restart and bot_e.laps_completed() == done and bot_e.lap_times.size() == times and bot_e.current_lap() == lap,
		"saindo do box e cruzando a linha, a volta recomeça sem ser contada (%d completadas)" % bot_e.laps_completed())
	# --- Batida do jogador: tempo esgota → box
	pe.car.limiter_on = true
	var p_lap := pe.current_lap()
	rc.report_crash(pe)
	info = rc.instruction_for(pe)
	_check(not info.is_empty() and "boxes" in str(info[1]) and "[" in str(info[1]), "jogador batido: %s" % (info[1] if not info.is_empty() else ""))
	# Passar o safety car (jogador envolvido não é punido)
	pen_before = pe.penalty_seconds
	rc.safety_car.progress = pe.progress - 30.0
	await _seconds(0.5)
	_check(is_equal_approx(pe.penalty_seconds, pen_before), "envolvido pode passar o safety car")
	rc.involved[pe]["time_left"] = 0.2
	await _seconds(0.5)
	_check(pe.in_pit_stop and pe.current_lap() == p_lap and pe.lap_restart, "tempo esgotado: levado ao box, recomeça a mesma volta")
	await _seconds(RaceControl.REPAIR_TIME + 4.0)
	_check(not rc.is_involved(pe) and rc.yellow, "jogador consertado; amarela segue com o safety car")
	rc.safety_car.progress = rc.sc_end - 1.0
	await _seconds(0.5)
	# --- Safety car: quem não está envolvido e passa é punido
	for e in manager.entries:
		if e.bot and not e.in_pit and not e.in_pit_stop and not e.retired and not rc.is_involved(e):
			rc.report_crash(e)
			break
	_check(rc.yellow and rc.safety_car != null, "nova batida: nova amarela com safety car")
	await _seconds(0.2)
	var other: RaceEntry = null
	for e in manager.entries:
		if not rc.is_involved(e) and not e.in_pit and not e.in_pit_stop and e.bot:
			other = e
			break
	pen_before = other.penalty_seconds
	rc.safety_car.progress = other.progress - 50.0
	await _seconds(0.3)
	_check(other.penalty_seconds >= pen_before + 10.0, "passar o safety car: +10 s")
	_check(bot_passes[0] == 0, "bots não ultrapassam sob amarela (%d ultrapassagens)" % bot_passes[0])
	# Ultrapassagem sob amarela: a ordem do par inverte ao longo de vários passos → +5 s
	var subjects: Array[RaceEntry] = []
	for e in manager.entries:
		if rc._subject(e):
			subjects.append(e)
	if subjects.size() >= 2:
		var a := subjects[0]
		var b := subjects[1]
		var base := b.progress
		var pen_a := a.penalty_seconds
		a.progress = base - 12.0
		rc._check_rules(0.01)
		for k in 8:
			a.progress = base - 12.0 + k * 3.0
			rc._check_rules(0.01)
		_check(a.penalty_seconds >= pen_a + 5.0, "ultrapassagem lenta sob amarela: +5 s (%.0f → %.0f s)" % [pen_a, a.penalty_seconds])
	Engine.time_scale = 1.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_rc_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
