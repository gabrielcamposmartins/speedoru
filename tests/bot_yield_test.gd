extends SceneTree
## Bots e o jogador (sem janela):  godot --headless --path . -s res://tests/bot_yield_test.gd
## Chama a lógica de tráfego do bot (BotDriver._traffic) com o jogador posicionado em volta:
## bot fácil dá passagem a um ataque por trás (abre para o outro lado e tira o pé), o difícil
## defende, sob amarela ninguém dá passagem, e atrás do jogador o bot deixa mais espaço.

var failures := 0
var manager: RaceManager


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.opponents = 1
	RaceSettings.difficulty = 0
	RaceSettings.laps = 3
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_yield_profile.cfg"
		profile.reset_profile()
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


## Coloca os dois na reta principal: bot em s=500, jogador a ds metros (negativo = atrás).
func _place(bot_e: RaceEntry, pe: RaceEntry, ds: float, player_lat: float, player_speed: float) -> void:
	bot_e.s = 500.0
	bot_e.lateral = 0.0
	pe.s = 500.0 + ds
	pe.lateral = player_lat
	pe.car.linear_velocity = pe.car.global_basis.z * player_speed


func _run() -> void:
	while manager.state != RaceManager.State.GRID:
		await process_frame
	var pe := manager.player_entry
	var bot_e: RaceEntry = null
	for e in manager.entries:
		if e.bot:
			bot_e = e
	var bot := bot_e.bot
	# Ritmo normal do bot naquele trecho (a passagem é uma fração dele)
	var v: float = RacingLine.sample(bot.profile, bot.track.path, 504.0)
	# 1) Fácil, jogador 12 m atrás e 0,6 m à esquerda, mais rápido
	bot.difficulty = BotDriver.Difficulty.EASY
	bot._passing = null
	_place(bot_e, pe, -12.0, 0.6, 70.0)
	var r: Vector2 = bot._traffic(500.0, v, 0.0)
	var line_lat := bot.line.lateral_at(500.0)
	var move := (r.x + line_lat) - 0.0
	_check(move < -1.0, "bot fácil abre para o lado oposto ao ataque (%.1f m)" % move)
	_check(r.y < v * 0.95 and r.y > v * 0.8, "bot fácil tira o pé para deixar passar, sem parar (%.1f → %.1f m/s)" % [v, r.y])
	# Seguido de perto sem ultrapassar, não vai freando até parar: mesmo partindo devagar, a meta
	# é uma fração do ritmo do trecho
	bot._offset_target = 0.0
	_place(bot_e, pe, -10.0, 0.6, 30.0)
	var slow: Vector2 = bot._traffic(500.0, 30.0, 0.0)
	_check(slow.y > v * 0.8, "seguido de perto, não desacelera sem parar (meta %.1f m/s andando a 30)" % slow.y)
	# 2) Difícil: defende
	bot.difficulty = BotDriver.Difficulty.HARD
	bot._offset_target = 0.0
	_place(bot_e, pe, -12.0, 0.6, 70.0)
	r = bot._traffic(500.0, v, 0.0)
	_check(absf(r.x) < 0.01 and r.y >= v, "bot difícil não dá passagem")
	# 3) Amarela: ninguém dá passagem
	bot.difficulty = BotDriver.Difficulty.EASY
	bot._offset_target = 0.0
	manager.control.yellow = true
	_place(bot_e, pe, -12.0, 0.6, 70.0)
	r = bot._traffic(500.0, v, 0.0)
	manager.control.yellow = false
	_check(absf(r.x) < 0.01, "sob bandeira amarela o bot não abre passagem")
	# 4) Atrás do jogador (mais lento, 30 m à frente): folga maior que atrás de um bot
	bot._offset_target = 0.0
	_place(bot_e, pe, 30.0, 0.0, 40.0)
	var behind_player: float = bot._traffic(500.0, v, 0.0).y
	pe.is_player = false
	bot._offset_target = 0.0
	var behind_bot: float = bot._traffic(500.0, v, 0.0).y
	pe.is_player = true
	_check(behind_player < behind_bot - 0.5, "atrás do jogador o bot freia antes (%.1f m/s contra %.1f atrás de um bot)" % [behind_player, behind_bot])
	# 5) Ultrapassagem sem medo: 90 m de reta bastam (antes eram 150) com o da frente mais lento
	var path := bot.track.path
	var s_pass := -1.0
	var s_corner := -1.0
	for k in range(200, int(path.length) - 200, 10):
		if s_pass < 0.0 and bot._straight_ahead(k, 90.0) and not bot._straight_ahead(k, 150.0):
			s_pass = k
		if s_corner < 0.0 and k > s_pass and s_pass > 0.0 and not bot._straight_ahead(k, 40.0):
			s_corner = k
	bot.difficulty = BotDriver.Difficulty.MEDIUM
	bot._passing = null
	bot._offset_target = 0.0
	bot_e.progress = 5000.0
	bot_e.s = s_pass
	bot_e.lateral = bot.line.lateral_at(s_pass)
	pe.s = s_pass + 25.0
	pe.lateral = bot_e.lateral
	pe.car.linear_velocity = pe.car.global_basis.z * 56.0
	bot._traffic(s_pass, 60.0, bot_e.lateral)
	_check(bot._passing == pe, "começa a ultrapassar com 90 m de reta e 4 m/s a mais (s %.0f)" % s_pass)
	# 6) Já lado a lado chegando na curva: não desiste da ultrapassagem
	bot_e.s = s_corner
	bot_e.lateral = bot.line.lateral_at(s_corner) + 3.0
	pe.s = s_corner + 2.0
	pe.lateral = bot.line.lateral_at(s_corner)
	bot._traffic(s_corner, 50.0, bot_e.lateral)
	_check(bot._passing == pe, "lado a lado na entrada da curva, segue a ultrapassagem (s %.0f)" % s_corner)
	var inside: float = bot._corner_inside(s_corner, 60.0)
	_check(bot._pass_side == inside, "ultrapassagem pelo lado de dentro da curva (%+.0f)" % bot._pass_side)
	# 6b) Lado a lado POR FORA da curva que chega: desiste (por fora, sairia da pista)
	bot._passing = pe
	bot._pass_side = -inside
	bot_e.lateral = bot.line.lateral_at(s_corner) - inside * 3.0
	bot._traffic(s_corner, 50.0, bot_e.lateral)
	_check(bot._passing == null, "lado a lado por fora da curva, desiste e encaixa atrás")
	bot._passing = pe
	bot._pass_side = inside
	# 7) Ainda longe (ainda não chegou ao lado) com a curva perto: desiste e segue atrás
	pe.s = s_corner + 20.0
	bot._traffic(s_corner, 50.0, bot_e.lateral)
	_check(bot._passing == null, "longe dele com a curva perto, desiste e segue atrás")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_yield_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
