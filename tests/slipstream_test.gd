extends SceneTree
## Vácuo (sem janela):  godot --headless --path . -s res://tests/slipstream_test.gd
## A força do rastro (colado atrás, de lado, longe, devagar) e o efeito no carro: atrás de outro, em
## roda livre a 250 km/h, perde bem menos velocidade que sozinho.

var failures := 0
var world: Node3D


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _car(pos: Vector3) -> F1Car:
	var car := (load("res://scenes/car/f1_car.tscn") as PackedScene).instantiate() as F1Car
	car.player_controlled = false
	world.add_child(car)
	car.position = pos
	return car


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	gs.shape = WorldBoundaryShape3D.new()
	ground.add_child(gs)
	world.add_child(ground)
	var lead := _car(Vector3(0, 0.05, 10.0))
	var chaser := _car(Vector3(0, 0.05, 0.0))
	for i in 30:
		await physics_frame
	lead.linear_velocity = Vector3(0, 0, 60.0)
	chaser.linear_velocity = Vector3(0, 0, 60.0)
	var cars := [lead, chaser]
	_check(Slipstream.strength_for(chaser, cars) > 0.95, "colado atrás (10 m): vácuo total (%.2f)" % Slipstream.strength_for(chaser, cars))
	chaser.position = Vector3(3.5, 0.05, 0.0)
	_check(Slipstream.strength_for(chaser, cars) < 0.05, "3,5 m para o lado: sem vácuo")
	chaser.position = Vector3(0, 0.05, -45.0)
	_check(Slipstream.strength_for(chaser, cars) < 0.01, "55 m atrás: sem vácuo")
	chaser.position = Vector3(0, 0.05, -20.0)
	var mid := Slipstream.strength_for(chaser, cars)
	_check(mid > 0.2 and mid < 0.9, "30 m atrás: vácuo parcial (%.2f)" % mid)
	_check(Slipstream.strength_for(lead, cars) == 0.0, "o carro da frente não ganha nada")
	chaser.linear_velocity = Vector3(0, 0, 10.0)
	chaser.position = Vector3(0, 0.05, 0.0)
	_check(Slipstream.strength_for(chaser, cars) == 0.0, "devagar não há vácuo")
	# Roda livre: perda de velocidade em 1 s com e sem vácuo
	var alone := await _coast(0.0)
	var drafted := await _coast(1.0)
	print("  em 1 s de roda livre a 250 km/h: sozinho perde %.1f km/h, no vácuo %.1f km/h" % [alone, drafted])
	_check(alone > 5.0 and drafted < alone * 0.6, "no vácuo o carro perde bem menos velocidade")
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)


func _coast(slip: float) -> float:
	var car := _car(Vector3(40.0, 0.05, 0.0))
	for i in 30:
		await physics_frame
	car.linear_velocity = Vector3(0, 0, 250.0 / 3.6)
	car.throttle_input = 0.0
	car.brake_input = 0.0
	car.slipstream = slip
	await physics_frame
	var v0 := car.linear_velocity.length() * 3.6
	for i in 120:
		car.slipstream = slip
		await physics_frame
	var lost := v0 - car.linear_velocity.length() * 3.6
	car.queue_free()
	return lost
