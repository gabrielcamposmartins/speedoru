extends SceneTree
## Colisões no box (sem janela):
##   godot --headless --path . -s res://tests/pit_collisions_test.gd -- --offline
## Com a opção ligada (padrão) o jogador colide com um bot nos boxes; desligada, os dois se
## atravessam enquanto um deles está nos boxes e voltam a colidir depois que saem e se afastam.

var scene: Node3D
var manager: RaceManager
var failures := 0


func _initialize() -> void:
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_pit_collisions_profile.cfg"
		profile.reset_profile()
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _load(pit_collisions: bool) -> void:
	if scene:
		scene.queue_free()
		await process_frame
	RaceSettings.track = "monza"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 3
	RaceSettings.opponents = 3
	RaceSettings.quali_laps = 0
	RaceSettings.skip_menu = true
	RaceSettings.pit_collisions = pit_collisions
	scene = (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	scene.set("start_light_sequence", false)
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	while not manager.track.is_built:
		await process_frame
	# Os boxes só são detectados com a corrida andando (depois da largada)
	var t := 0
	while manager.state != RaceManager.State.RACING and t < 60 * 60:
		await physics_frame
		t += 1
	await _physics(10)


## Põe o jogador na vaga dos boxes e um bot 12 m atrás (sem encostar); devolve se há exceção de colisão.
func _pit_pair() -> bool:
	var me := manager.player_entry
	var bot: RaceEntry = manager.entries.filter(func(e: RaceEntry) -> bool: return not e.is_player)[0]
	var box := manager.track.get_pit_box_transform(me.garage)
	for e in [me, bot]:
		e.car.hold = true
		e.car.linear_velocity = Vector3.ZERO
		e.car.angular_velocity = Vector3.ZERO
	# Como o pit stop: reposiciona e recalcula a posição na pista (s), senão os boxes não são detectados
	manager.teleport_to_box(me, box)
	manager.teleport_to_box(bot, box.translated(-box.basis.z * 12.0))
	await _physics(10)
	return me.car.get_collision_exceptions().has(bot.car) or bot.car.get_collision_exceptions().has(me.car)


func _run() -> void:
	await _load(true)
	_check(manager.pit_collisions, "padrão: colisões no box ligadas")
	var ghost := await _pit_pair()
	_check(manager._in_pit_area(manager.player_entry), "jogador na área dos boxes")
	_check(not ghost, "ligadas: jogador e bot colidem nos boxes")

	await _load(false)
	_check(not manager.pit_collisions, "opção desligada chega ao RaceManager")
	ghost = await _pit_pair()
	_check(ghost, "desligadas: jogador e bot se atravessam nos boxes")
	# Fora dos boxes e longe: volta a colisão
	var me := manager.player_entry
	var bot: RaceEntry = manager.entries.filter(func(e: RaceEntry) -> bool: return not e.is_player)[0]
	me.car.global_transform = manager.track.get_grid_transform(0)
	bot.car.global_transform = manager.track.get_grid_transform(6)
	me.car.reset_physics_interpolation()
	bot.car.reset_physics_interpolation()
	await _physics(10)
	_check(not me.car.get_collision_exceptions().has(bot.car) and not bot.car.get_collision_exceptions().has(me.car)
		or manager._is_start_ghost(me, bot), "fora dos boxes e afastados voltam a colidir")
	RaceSettings.pit_collisions = true
	print("pit_collisions_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)
