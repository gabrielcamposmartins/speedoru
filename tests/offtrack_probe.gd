extends SceneTree
## Fora da pista (sem janela):  godot --headless --path . -s res://tests/offtrack_probe.gd
## Carro a 200 km/h entrando em grama e cascalho: velocidade perdida em 2 s (sem acelerar e
## acelerando) e aderência lateral máxima numa curva a 120 km/h.

func _initialize() -> void:
	_run.call_deferred()


func _world(surface: int) -> Array:
	var world := Node3D.new()
	root.add_child(world)
	var ground := TrackSurface.make_body("Chao", surface)
	var gs := CollisionShape3D.new()
	gs.shape = WorldBoundaryShape3D.new()
	ground.add_child(gs)
	world.add_child(ground)
	var car := (load("res://scenes/car/f1_car.tscn") as PackedScene).instantiate() as F1Car
	car.player_controlled = false
	world.add_child(car)
	car.position = Vector3(0, 0.05, 0)
	return [world, car]


func _steps(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await physics_frame


func _run() -> void:
	for surface in [TrackSurface.Type.ASPHALT, TrackSurface.Type.GRASS, TrackSurface.Type.GRAVEL]:
		var name: String = TrackSurface.NAMES[surface]
		var loss := []
		for throttle in [0.0, 1.0]:
			var w: Array = _world(surface)
			var car: F1Car = w[1]
			await _steps(0.8)
			car.linear_velocity = car.global_basis.z * (200.0 / 3.6)
			car.gear = 6
			car.throttle_input = throttle
			await _steps(2.0)
			loss.append(200.0 - car.speed_kmh)
			(w[0] as Node).queue_free()
			await process_frame
		# Aderência lateral: 120 km/h, esterço máximo por 3 s, maior aceleração lateral
		var w2: Array = _world(surface)
		var c2: F1Car = w2[1]
		await _steps(0.8)
		c2.linear_velocity = c2.global_basis.z * (120.0 / 3.6)
		c2.gear = 4
		c2.throttle_input = 0.35
		c2.steer_input = 1.0
		var lat := 0.0
		var prev := c2.linear_velocity
		for i in int(3.0 * Engine.physics_ticks_per_second):
			await physics_frame
			var acc := (c2.linear_velocity - prev) * Engine.physics_ticks_per_second
			prev = c2.linear_velocity
			lat = maxf(lat, absf(acc.dot(c2.global_basis.x)) / 9.8)
		(w2[0] as Node).queue_free()
		await process_frame
		print("%-9s perde em 2 s: %3.0f km/h sem acelerar, %3.0f km/h acelerando | lateral máx %.2f g" % [name, loss[0], loss[1], lat])
	quit()
