extends SceneTree
## Regra do DRS (sem janela):  godot --headless --path . -s res://tests/drs_rule_test.gd
## Livre: sempre permitido. "Até 1 s": só a até 1 s do carro da frente (o líder não tem); o carro
## só abre o DRS quando permitido.

var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.opponents = 1
	RaceSettings.laps = 3
	RaceSettings.drs_rule = 1
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_drs_profile.cfg"
		profile.reset_profile()
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_run.call_deferred(scene.get_node("RaceManager"))


## Dois carros: o de trás passou pela mesma marca de progresso [param gap] s depois.
func _gap_case(m: RaceManager, gap: float) -> bool:
	var front := m.entries[0]
	var back := m.entries[1]
	front.position = 1
	back.position = 2
	front.checkpoint_times = PackedFloat32Array([10.0, 12.0, 14.0])
	back.checkpoint_times = PackedFloat32Array([10.0 + gap, 12.0 + gap])
	return m.drs_gap_ok(back)


func _run(m: RaceManager) -> void:
	while m.state != RaceManager.State.RACING:
		await process_frame
	_check(m.drs_rule == 1, "corrida criada com DRS só a até 1 s")
	_check(_gap_case(m, 0.6), "a 0,6 s do carro da frente: DRS permitido")
	_check(not _gap_case(m, 1.5), "a 1,5 s: DRS não permitido")
	_check(not m.drs_gap_ok(m.entries[0]), "o líder não tem DRS")
	# O carro só abre a asa quando permitido
	var car := m.player_entry.car
	m.drs_rule = 0
	await physics_frame
	_check(car.drs_allowed, "DRS livre: sempre permitido")
	RaceSettings.drs_rule = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_drs_profile.cfg"))
	await _car_case()
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)


func _car_case() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	gs.shape = WorldBoundaryShape3D.new()
	ground.add_child(gs)
	world.add_child(ground)
	world.position = Vector3(0, -500, 0)
	var car := (load("res://scenes/car/f1_car.tscn") as PackedScene).instantiate() as F1Car
	car.player_controlled = false
	world.add_child(car)
	car.position = Vector3(0, 0.05, 0)
	for i in 30:
		await physics_frame
	car.linear_velocity = car.global_basis.z * 60.0
	car.throttle_input = 1.0
	car.drs_requested = true
	car.drs_allowed = false
	for i in 20:
		await physics_frame
	_check(not car.drs_open, "sem permissão o DRS não abre")
	car.drs_allowed = true
	for i in 20:
		await physics_frame
	_check(car.drs_open, "com permissão o DRS abre")
	world.queue_free()
