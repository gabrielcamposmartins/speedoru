extends SceneTree
## Diagnóstico: o que acontece com os pneus em alta velocidade em linha reta (sem janela).
##   godot --headless --path . -s res://tests/highspeed_probe.gd
## Cenário 1: plano perfeito (22 s de acelerador). Cenário 2: reta principal de Monza, do grid
## até antes da 1ª chicane. Acima de 200 km/h registra carga, aderência, estado e contato de cada
## pneu, aceleração vertical e deriva/guinada da carroceria.

var car: F1Car
var rows := []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# --- Plano
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
	await _wait(1.5)
	await _drive(22.0, -1.0)
	_report("PLANO")
	await _scenarios(root3d)
	root3d.queue_free()
	await process_frame
	# --- Monza
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	var rm := scene.get_node_or_null("RaceManager")
	if rm:
		scene.remove_child(rm)
		rm.free()
	scene.set("start_light_sequence", false)
	root.add_child(scene)
	var track := scene.get_node("Track") as RaceTrack
	if not track.is_built:
		await track.built
	car = scene.get_node("F1Car") as F1Car
	car.player_controlled = false
	await _wait(1.0)
	rows.clear()
	await _drive(30.0, 1000.0, track)
	_report("MONZA (reta principal)")
	quit()


func _wait(s: float) -> void:
	var t := 0.0
	while t < s:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second


func _drive(seconds: float, max_s: float, track: RaceTrack = null) -> void:
	car.throttle_input = 1.0
	car.brake_input = 0.0
	car.steer_input = 0.0
	var t := 0.0
	var start := car.global_position
	while t < seconds:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		if max_s > 0.0 and car.global_position.distance_to(start) > max_s:
			break
		# Mantém a direção reta (sem piloto corrigindo)
		if car.speed_kmh < 200.0:
			continue
		var r := {"v": car.speed_kmh, "va": car._vertical_accel, "slip": rad_to_deg(car.body_slip_angle),
			"yaw": rad_to_deg(car.angular_velocity.y), "df": car._downforce}
		var air := 0
		var nongrip := 0
		var fz := []
		var use := []
		for i in 4:
			if car.tire_state[i] == F1Car.TireState.AIR:
				air += 1
			elif car.tire_state[i] != F1Car.TireState.GRIP:
				nongrip += 1
			fz.append(car.tire_load[i])
			use.append(car.tire_usage[i])
		r["air"] = air
		r["nongrip"] = nongrip
		r["fz"] = fz
		r["use"] = use
		rows.append(r)


func _report(title: String) -> void:
	print("== ", title, ": ", rows.size(), " passos acima de 200 km/h")
	if rows.is_empty():
		return
	var vmax := 0.0
	var air_frames := 0
	var nongrip_frames := 0
	var va_min := 1e9
	var va_max := -1e9
	var fz_min := 1e9
	var fz_max := 0.0
	var use_max := 0.0
	var slip_max := 0.0
	var yaw_max := 0.0
	var df_max := 0.0
	for r in rows:
		vmax = maxf(vmax, r["v"])
		air_frames += int(r["air"] > 0)
		nongrip_frames += int(r["nongrip"] > 0)
		va_min = minf(va_min, r["va"])
		va_max = maxf(va_max, r["va"])
		for f in r["fz"]:
			fz_min = minf(fz_min, f)
			fz_max = maxf(fz_max, f)
		for u in r["use"]:
			use_max = maxf(use_max, u)
		slip_max = maxf(slip_max, absf(r["slip"]))
		yaw_max = maxf(yaw_max, absf(r["yaw"]))
		df_max = maxf(df_max, r["df"])
	print("  vel. máx %.0f km/h | downforce máx %.0f N" % [vmax, df_max])
	print("  passos com roda no ar: %d | com pneu fora do GRIP: %d" % [air_frames, nongrip_frames])
	print("  carga por pneu: %.0f .. %.0f N | uso máx da aderência: %.2f" % [fz_min, fz_max, use_max])
	print("  aceleração vertical usada na carga: %.1f .. %.1f m/s²" % [va_min, va_max])
	print("  deriva máx da carroceria %.2f° | guinada máx %.2f°/s" % [slip_max, yaw_max])
	# Amostra a cada ~0,5 s
	var step := maxi(rows.size() / 12, 1)
	for k in range(0, rows.size(), step):
		var r: Dictionary = rows[k]
		print("  %3.0f km/h  va %6.1f  fz %s  uso %s  ar %d  slip %.2f°" % [r["v"], r["va"],
			(r["fz"] as Array).map(func(x): return roundi(x)), (r["use"] as Array).map(func(x): return snappedf(x, 0.01)), r["air"], r["slip"]])


func _reset(root3d: Node3D) -> void:
	if car:
		car.queue_free()
	await physics_frame
	car = (load("res://scenes/car/f1_car.tscn") as PackedScene).instantiate()
	car.player_controlled = false
	root3d.add_child(car)
	car.position = Vector3(0, 0.05, 0)
	await _wait(1.0)


func _until_speed(kmh: float) -> void:
	car.throttle_input = 1.0
	var t := 0.0
	while car.speed_kmh < kmh and t < 25.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second


## Conta passos com pneu em cada estado durante [param seconds].
func _watch(seconds: float, step_fn: Callable) -> Dictionary:
	var out := {"spin": 0, "slide": 0, "lock": 0, "air": 0, "bottom": 0, "body": 0, "slip": 0.0, "yaw": 0.0, "front_alpha": 0.0}
	var t := 0.0
	while t < seconds:
		step_fn.call(t)
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var st := car.tire_state
		out["spin"] += int(st.has(F1Car.TireState.SPIN))
		out["slide"] += int(st.has(F1Car.TireState.SLIDE))
		out["lock"] += int(st.has(F1Car.TireState.LOCK))
		out["air"] += int(st.has(F1Car.TireState.AIR))
		var bottomed := false
		for w in car.get_wheels():
			if w.is_in_contact():
				var mount: Vector3 = car.global_transform * w.position
				var length := (mount - w.get_contact_point()).dot(car.global_basis.y) - w.wheel_radius
				if w.wheel_rest_length - length >= w.suspension_travel - 0.002:
					bottomed = true
		out["bottom"] += int(bottomed)
		var ds := PhysicsServer3D.body_get_direct_state(car.get_rid())
		if ds and ds.get_contact_count() > 0:
			out["body"] += 1
		out["slip"] = maxf(out["slip"], absf(rad_to_deg(car.body_slip_angle)))
		out["yaw"] = maxf(out["yaw"], absf(rad_to_deg(car.angular_velocity.y)))
		for i in 4:
			if car.is_front_wheel(i):
				out["front_alpha"] = maxf(out["front_alpha"], absf(car.tire_slip_deg[i]))
	return out


func _scenarios(root3d: Node3D) -> void:
	# Boost a 180-260 km/h, com e sem controle de tração
	for tc in [true, false]:
		await _reset(root3d)
		car.traction_control = tc
		car.battery = 1.0
		await _until_speed(170.0)
		var r := await _watch(3.0, func(_t: float) -> void:
			car.throttle_input = 1.0
			car.boost_input = true)
		car.boost_input = false
		print("== BOOST em reta (TC %s): passos com patinagem %d, deriva máx %.2f°, guinada máx %.1f°/s, vel %.0f km/h" % [
			"ligado" if tc else "desligado", r["spin"], r["slip"], r["yaw"], car.speed_kmh])
	# Toque de teclado na direção a 300 km/h (0,15 s esterçando tudo)
	await _reset(root3d)
	await _until_speed(300.0)
	var r2 := await _watch(2.0, func(t: float) -> void:
		car.throttle_input = 1.0
		car.steer_input = 1.0 if t < 0.15 else 0.0)
	print("== TOQUE NA DIREÇÃO a 300 km/h (0,15 s): limite de esterço %.1f°, deriva do pneu diant. máx %.1f° (pico %.1f°), passos SLIDE %d, deriva carroceria %.2f°, guinada %.1f°/s" % [
		rad_to_deg(car.high_speed_steer_angle), r2["front_alpha"], car.peak_slip_angle_deg, r2["slide"], r2["slip"], r2["yaw"]])
	# Acerto extremo: mola mais mole e carga aerodinâmica máxima
	await _reset(root3d)
	car.downforce_area = 5.4
	for w in car.get_wheels():
		w.suspension_stiffness = 100.0
	await _until_speed(250.0)
	var r3 := await _watch(6.0, func(_t: float) -> void: car.throttle_input = 1.0)
	print("== ACERTO EXTREMO (mola 100, carga 5,4 m²): passos com suspensão no batente %d, carroceria tocando o chão %d, roda no ar %d, vel %.0f km/h" % [
		r3["bottom"], r3["body"], r3["air"], car.speed_kmh])
	await _reset(root3d)
	await _until_speed(250.0)
	var r4 := await _watch(6.0, func(_t: float) -> void: car.throttle_input = 1.0)
	print("== ACERTO PADRÃO: passos com suspensão no batente %d, carroceria tocando o chão %d, vel %.0f km/h" % [r4["bottom"], r4["body"], car.speed_kmh])
