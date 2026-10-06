extends SceneTree
## Câmbio (sem janela): manual com neutro e ré no acelerador; automático como antes.
##   godot --headless --path . -s res://tests/gearbox_test.gd

var failures := 0
var car: F1Car


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	root.add_child(ground)
	car = (load("res://scenes/car/f1_car.tscn") as PackedScene).instantiate() as F1Car
	car.position = Vector3(0, 0.6, 0)
	root.add_child(car)
	_run.call_deferred()


func _physics(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second


func _run() -> void:
	await _physics(1.0)
	# --- Manual
	car.automatic = false
	car.shift_down()
	_check(car.gear == F1Car.GEAR_NEUTRAL, "manual: da 1ª desce para o neutro")
	Input.action_press("accelerate")
	await _physics(1.5)
	_check(absf(car.forward_speed) < 0.3 and car.rpm > 8000.0, "neutro: acelerar só sobe o giro (%.0f rpm, %.2f m/s)" % [car.rpm, car.forward_speed])
	Input.action_release("accelerate")
	await _physics(0.5)
	car.shift_down()
	_check(car.gear == F1Car.GEAR_REVERSE, "manual: do neutro (parado) desce para a ré")
	Input.action_press("accelerate")
	await _physics(2.0)
	Input.action_release("accelerate")
	_check(car.forward_speed < -2.0, "ré manual anda para trás com o acelerador (%.1f m/s)" % car.forward_speed)
	await _physics(2.0)
	car.shift_up()
	_check(car.gear == F1Car.GEAR_NEUTRAL, "manual: da ré sobe para o neutro")
	car.shift_up()
	_check(car.gear == 1, "manual: do neutro sobe para a 1ª")
	Input.action_press("brake")
	await _physics(2.0)
	Input.action_release("brake")
	Input.action_press("reverse")
	await _physics(1.0)
	Input.action_release("reverse")
	_check(car.gear == 1 and absf(car.forward_speed) < 0.5, "manual: a tecla de ré não faz nada (marcha %d, %.2f m/s)" % [car.gear, car.forward_speed])
	Input.action_press("accelerate")
	await _physics(2.0)
	Input.action_release("accelerate")
	car.shift_down()
	_check(car.gear == F1Car.GEAR_NEUTRAL, "manual: em movimento, da 1ª vai para o neutro")
	car.shift_down()
	_check(car.gear == F1Car.GEAR_NEUTRAL, "manual: em movimento não engata a ré")
	Input.action_press("brake")
	await _physics(3.0)
	Input.action_release("brake")
	# --- Automático
	car.automatic = true
	Input.action_press("accelerate")
	await _physics(0.3)
	Input.action_release("accelerate")
	_check(car.gear >= 1, "automático: acelerar em neutro engata a 1ª")
	Input.action_press("brake")
	await _physics(3.0)
	Input.action_release("brake")
	Input.action_press("reverse")
	await _physics(2.0)
	Input.action_release("reverse")
	_check(car.gear == F1Car.GEAR_REVERSE and car.forward_speed < -1.0, "automático: segurar a ré engata e anda para trás")
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
