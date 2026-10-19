extends SceneTree
## Sair depois do pódio (sem janela):
##   godot --headless --path . -s res://tests/leave_after_podium_test.gd -- --offline
## Online, quando os três primeiros recebem a bandeirada o RaceManager avisa (may_leave e
## "podium_done" no estado da rede). Quem sai da corrida antes disso abandona (metade dos créditos);
## depois, conta como chegada com as voltas que tinha (créditos inteiros) e o carro sai da pista;
## sem o pit stop obrigatório continua desclassificado.

var scene: Node3D
var manager: RaceManager
var failures := 0


func _initialize() -> void:
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_leave_podium_profile.cfg"
		profile.reset_profile()
	RaceSettings.track = "monza"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 3
	RaceSettings.opponents = 5
	RaceSettings.quali_laps = 0
	RaceSettings.skip_menu = true
	scene = (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	scene.set("start_light_sequence", false)
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


## Faz o carro cruzar a linha completando a volta `lap`.
func _cross(e: RaceEntry, lap: int) -> void:
	e.crossings = lap + 1
	e.pit_count = 1
	manager._on_line_crossed(e)


func _run() -> void:
	while manager.state != RaceManager.State.RACING:
		await physics_frame
	await _physics(5)
	var me := manager.player_entry
	var bots: Array = manager.entries.filter(func(e: RaceEntry) -> bool: return not e.is_player)
	var warned := [0]
	manager.may_leave.connect(func() -> void: warned[0] += 1)
	me.crossings = 3  # 2 voltas completas
	me.pit_count = 1
	for k in 2:
		_cross(bots[k], RaceSettings.laps)
	_check(not manager.podium_done and warned[0] == 0, "dois na bandeirada: ainda não avisa")
	_check(not bool(manager.net_state().get("podium_done", true)), "estado da rede sem o aviso")
	_cross(bots[2], RaceSettings.laps)
	_check(manager.podium_done and warned[0] == 1, "três na bandeirada: avisa uma vez")
	_check(bool(manager.net_state().get("podium_done", false)), "estado da rede leva o aviso")
	_cross(bots[3], RaceSettings.laps)
	_check(warned[0] == 1, "o quarto não avisa de novo")

	# Sessão do servidor: o jogador sai da corrida
	var session := RaceSession.new()
	session.manager = manager
	session._phase = "racing"
	manager.humans = {"acc_me": me}
	session.player_left("acc_me")
	_check(me.finished and not me.retired and not me.disqualified, "saiu depois do pódio: conta como chegada (não abandono)")
	_check(me.laps_completed() == 2, "com as voltas que tinha (%d)" % me.laps_completed())
	var profile := PlayerProfile.new()
	var full := profile.award_race(2, 1, true, false)
	var got := profile.award_race(me.laps_completed(), 1, me.finished and not me.retired, me.disqualified)
	_check(got == full and got > 0, "créditos inteiros das voltas (%d)" % got)
	await _physics(2)
	_check(not me.car.visible and me.car.collision_layer == 0, "carro sai da pista")
	var order := manager.final_classification()
	_check(order.find(me) > order.find(bots[3]), "classificado atrás de quem completou mais voltas")

	# Sem o pit stop obrigatório: desclassificado
	var other: RaceEntry = bots[4]
	other.crossings = 3
	other.pit_count = 0
	manager.leave_after_podium(other)
	_check(other.finished and other.disqualified, "sem pit stop obrigatório: desclassificado (%d paradas exigidas)" % RaceSettings.mandatory_pits)

	session.free()
	profile.free()
	print("leave_after_podium_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)
