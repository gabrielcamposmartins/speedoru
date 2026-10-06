extends SceneTree
## Teste automático da física do carro (sem janela):
##   godot --headless --path . -s res://tests/drive_test.gd
## Mede carga nos pneus, aceleração, frenagem, curva em regime permanente, sobreesterço de
## potência (com/sem controle de tração) e travamento das rodas dianteiras (com/sem assistência).

var car: F1Car


func _initialize() -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	root3d.add_child(ground)
	car = (load("res://scenes/car/f1_car.tscn") as PackedScene).instantiate()
	car.player_controlled = false
	root3d.add_child(car)
	car.position = Vector3(0, 0.05, 0)
	_run.call_deferred()


func _run() -> void:
	await _wait(1.5)
	_report_loads()
	await _straight_line()
	await _skidpad(120.0, [0.25, 0.5, 0.75, 1.0])
	await _skidpad(220.0, [0.5, 1.0])
	await _power_oversteer(true)
	await _power_oversteer(false)
	await _lockup(true)
	await _lockup(false)
	quit()


func _report_loads() -> void:
	var total := 0.0
	var front := 0.0
	for i in 4:
		total += car.tire_load[i]
		if car.is_front_wheel(i):
			front += car.tire_load[i]
	print("Carga em repouso: %.0f N (peso = %.0f N), dianteira %.0f%%, por roda %s" % [
		total, car.mass * 9.8, front / total * 100.0, Array(car.tire_load).map(func(v): return roundi(v))])


func _straight_line() -> void:
	var marks := {}
	var t := 0.0
	_inputs(1.0, 0.0, 0.0)
	while t < 22.0:
		await physics_frame
		t += _dt()
		for target in [100, 200, 300]:
			if car.speed_kmh >= target and not marks.has(target):
				marks[target] = t
	print("0-100: %.2fs  0-200: %.2fs  0-300: %s  após 22s: %.0f km/h" % [
		marks.get(100, -1.0), marks.get(200, -1.0),
		("%.2fs" % marks[300]) if marks.has(300) else "—", car.speed_kmh])
	var v0 := car.speed_kmh
	var p0 := car.global_position
	t = 0.0
	var locks := 0
	_inputs(0.0, 1.0, 0.0)
	while car.speed_kmh > 1.0 and t < 15.0:
		await physics_frame
		t += _dt()
		locks += int(car.tire_state.has(F1Car.TireState.LOCK))
	print("Frenagem %.0f→0 km/h: %.2fs em %.0f m (quadros com roda travada: %d)" % [
		v0, t, car.global_position.distance_to(p0), locks])


## Curva em regime permanente: velocidade constante, esterço fixo.
func _skidpad(speed: float, steers: Array) -> void:
	for s in steers:
		await _reset_and_reach(speed)
		var stats := await _measure(4.0, speed, s, 0.0, false)
		print("Curva %3.0f km/h, esterço %.2f: lateral %.2f g | deriva diant. %.1f° tras. %.1f° | %s" % [
			speed, s, stats.lat_g, stats.front_slip, stats.rear_slip, stats.summary])


## Saída de curva lenta acelerando tudo: sem TC a traseira deve escapar.
func _power_oversteer(tc: bool) -> void:
	car.traction_control = tc
	await _reset_and_reach(70.0)
	await _measure(1.0, 70.0, 0.6, 0.0, false)
	var stats := await _measure(2.0, -1.0, 0.6, 0.0, true)
	print("Acelerando em curva a 70 km/h, TC %s: deriva do carro máx. %.1f°, guinada máx. %.0f°/s | %s" % [
		"ligado" if tc else "desligado", stats.max_body_slip, stats.max_yaw, stats.summary])
	car.traction_control = true


## Frear forte já esterçando: sem assistência a frente trava e o carro sai de frente.
func _lockup(assist: bool) -> void:
	car.brake_assist = assist
	await _reset_and_reach(180.0)
	var h0 := car.global_basis.z
	_inputs(0.0, 1.0, 0.5)
	var stats := await _measure(1.5, -1.0, 0.5, 1.0, false)
	var turned := rad_to_deg(h0.signed_angle_to(car.global_basis.z, Vector3.UP))
	print("Freando de 180 km/h esterçando, assistência %s: virou %.1f° | %s" % [
		"ligada" if assist else "desligada", turned, stats.summary])
	car.brake_assist = true


## Roda por `seconds` com esterço fixo. speed > 0 mantém a velocidade; caso contrário usa throttle/brake.
func _measure(seconds: float, speed: float, steer: float, brake: float, full_throttle: bool) -> Dictionary:
	var t := 0.0
	var counts := {}
	var lat := 0.0
	var fs := 0.0
	var rs := 0.0
	var samples := 0
	var max_body := 0.0
	var max_yaw := 0.0
	while t < seconds:
		var throttle := 1.0 if full_throttle else 0.0
		if speed > 0.0:
			throttle = clampf((speed - car.speed_kmh) * 0.15 + 0.35, 0.0, 1.0)
		_inputs(throttle, brake, steer)
		await physics_frame
		t += _dt()
		var key: String = ["NEUTRO", "SUBESTERÇO", "SOBREESTERÇO"][car.handling]
		for i in 4:
			if car.tire_state[i] in [F1Car.TireState.SPIN, F1Car.TireState.LOCK]:
				key += "+" + ["", "", "", "PATINA", "TRAVA"][car.tire_state[i]]
				break
		counts[key] = counts.get(key, 0) + 1
		max_body = maxf(max_body, absf(rad_to_deg(car.body_slip_angle)))
		max_yaw = maxf(max_yaw, absf(rad_to_deg(car.angular_velocity.y)))
		if t > seconds * 0.5:
			samples += 1
			lat += absf(car.angular_velocity.y) * car.linear_velocity.length() / 9.8
			fs += (absf(car.tire_slip_deg[0]) + absf(car.tire_slip_deg[1])) * 0.5
			rs += (absf(car.tire_slip_deg[2]) + absf(car.tire_slip_deg[3])) * 0.5
	var total := 0
	for k in counts:
		total += counts[k]
	var parts := []
	for k in counts:
		parts.append("%s %d%%" % [k, roundi(100.0 * counts[k] / total)])
	samples = maxi(samples, 1)
	return {"lat_g": lat / samples, "front_slip": fs / samples, "rear_slip": rs / samples,
		"max_body_slip": max_body, "max_yaw": max_yaw, "summary": ", ".join(parts)}


func _reset_and_reach(speed: float) -> void:
	_inputs(0.0, 0.0, 0.0)
	car.reset_car()
	await _wait(0.6)
	while car.speed_kmh < speed:
		_inputs(1.0, 0.0, 0.0)
		await physics_frame
	_inputs(0.3, 0.0, 0.0)


func _inputs(throttle: float, brake: float, steer: float) -> void:
	car.throttle_input = throttle
	car.brake_input = brake
	car.steer_input = steer


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await physics_frame
		t += _dt()


func _dt() -> float:
	return 1.0 / Engine.physics_ticks_per_second
