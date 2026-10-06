extends SceneTree
## Teste de dano/destruição (sem janela):
##   godot --headless --path . -s res://tests/damage_test.gd
## Em Monza: volta normal sem dano, raspada leve, batida lateral, batida de frente a 200 km/h
## (peças soltas viram destroços, downforce cai) e reparo.

var scene: Node3D
var track: RaceTrack
var car: F1Car
var damage: CarDamage
var failures := 0


func _initialize() -> void:
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	scene = (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	scene.set("start_light_sequence", false)
	root.add_child(scene)
	track = scene.get_node("Track")
	car = scene.get_node("F1Car")
	car.player_controlled = false
	damage = car.get_node("Damage")
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _summary() -> String:
	var parts := []
	for k in damage.health:
		var h := float(damage.health[k])
		if h < 0.999:
			parts.append("%s %.0f%%%s" % [k, h * 100.0, " (solta)" if damage.detached.has(k) else ""])
	return ", ".join(parts) if not parts.is_empty() else "intacto"


func _run() -> void:
	await _physics(30)
	_check(damage.health.size() >= 14, "peças registradas: %d" % damage.health.size())
	# 1) Largada e reta sem dano (pisos, zebras e lombadas não podem quebrar nada)
	car.global_transform = track.get_grid_transform(0)
	car.reset_physics_interpolation()
	await _physics(10)
	car.throttle_input = 1.0
	await _physics(840)
	car.throttle_input = 0.0
	print("Após 7 s acelerando: %s" % _summary())
	_check(damage.get_overall() > 0.999, "dirigir normalmente não causa dano")

	# 2) Raspada leve na barreira (ângulo raso, 80 km/h)
	await _crash(3000.0, 10.0, 80.0)
	print("Raspada a 80 km/h, 10°: %s" % _summary())
	_check(damage.detached.is_empty(), "raspada leve não solta peças")

	# 3) Batida lateral moderada
	car.repair()
	await _physics(5)
	await _crash(3000.0, 35.0, 110.0)
	var side_report := _summary()
	print("Batida a 110 km/h, 35°: %s" % side_report)
	var worst := 1.0
	for k in damage.health:
		worst = minf(worst, float(damage.health[k]))
	_check(worst < 0.85, "batida lateral causa dano")

	# 4) Batida de frente a 200 km/h
	car.repair()
	await _physics(5)
	var before := _count_debris()
	var dents = _mesh_snapshot("front_wing_L")
	await _crash(3000.0, 80.0, 200.0)
	print("Batida a 200 km/h, 80°: %s" % _summary())
	print("  downforce dianteira x%.2f, traseira x%.2f, potência x%.2f, destroços na pista: %d" % [
		car.damage_front_downforce, car.damage_rear_downforce, car.damage_power, _count_debris() - before])
	_check(not damage.detached.is_empty(), "peças se soltam na batida forte")
	_check(_count_debris() > before, "destroços viram corpos físicos na pista")
	_check(car.damage_front_downforce < 0.95, "perda de downforce dianteira")
	_check(dents == null or _mesh_snapshot("front_wing_L") != dents or damage.detached.has("front_wing_L"), "malha amassada/solta")

	# 5) Trocar a pintura não pode zerar o dano nem duplicar as peças
	var hurt := float(damage.health["nose"])
	var copies := car.find_children("Damaged_*", "MeshInstance3D", true, false).size()
	car.config.primary_color = Color(0.2, 0.4, 0.9)
	car.config.rim_color = Color(0.9, 0.8, 0.2)
	await _physics(3)
	_check(is_equal_approx(float(damage.health["nose"]), hurt)
		and car.find_children("Damaged_*", "MeshInstance3D", true, false).size() == copies, "trocar a cor mantém o dano")

	# 6) Reparo
	car.repair()
	await _physics(5)
	_check(damage.get_overall() > 0.999 and damage.detached.is_empty() and car.damage_front_downforce == 1.0
		and not car.wheel_broken.has(true), "reparo zera o dano")
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)


func _crash(s: float, angle_deg: float, kmh: float) -> void:
	var p := track.path
	var i := p.index_at(s)
	var a := deg_to_rad(angle_deg)
	var dir := (p.tangents[i] * cos(a) + p.lefts[i] * sin(a)).normalized()
	# Começa perto da barreira esquerda para bater logo
	var dist := track.barrier[0][i] + p.width_left[i]
	var start := p.points[i] + p.lefts[i] * (dist - 3.0) - dir * 6.0 + Vector3.UP * 0.1
	car.global_transform = Transform3D(Basis.looking_at(-dir), start)
	car.reset_physics_interpolation()
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	await _physics(20)
	car.linear_velocity = dir * kmh / 3.6
	await _physics(180)


func _count_debris() -> int:
	return scene.get_children().filter(func(n): return n is RigidBody3D and str(n.name).begins_with("Debris")).size()


func _mesh_snapshot(piece: String):
	var p = damage._pieces.get(piece)
	if p == null or p.copies.is_empty():
		return null
	return (p.copies[0][2][0] as PackedVector3Array).duplicate()


func _physics(n: int) -> void:
	for k in n:
		await physics_frame
