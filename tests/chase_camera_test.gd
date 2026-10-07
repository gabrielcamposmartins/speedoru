extends SceneTree
## Câmera de perseguição com vida (sem janela):
##   godot --headless --path . -s res://tests/chase_camera_test.gd
## Acelerando a câmera se afasta, freando se aproxima; numa curva para a esquerda ela desliza
## para fora (direita) e olha para dentro; numa batida treme.

var failures := 0
var car: F1Car
var cam: RaceCamera


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _setup() -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	gs.shape = WorldBoundaryShape3D.new()
	ground.add_child(gs)
	root3d.add_child(ground)
	car = (load("res://scenes/car/f1_car.tscn") as PackedScene).instantiate()
	car.player_controlled = false
	root3d.add_child(car)
	car.position = Vector3(0, 0.05, 0)
	cam = RaceCamera.new()
	cam.target_path = car.get_path()
	root3d.add_child(cam)
	cam.current = true


## Espera n/60 s de jogo (passos de física; sem janela os quadros não seguem o relógio).
func _frames(n: int) -> void:
	for i in n * 2:
		await physics_frame


## Distância horizontal câmera→carro e deslocamento lateral (positivo = à esquerda do carro).
func _offset() -> Vector2:
	var xf := car.get_global_transform_interpolated()
	var rel := cam.global_position - xf.origin
	var fwd := xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var left := Vector3.UP.cross(fwd).normalized()
	return Vector2(-rel.dot(fwd), rel.dot(left))


func _run() -> void:
	_setup()
	await _frames(60)
	var rest := cam._chase_pull
	car.throttle_input = 1.0
	await _frames(70)
	_check(cam._chase_pull > rest + 0.15, "acelerando a câmera se afasta (+%.2f m)" % cam._chase_pull)
	while car.speed_kmh < 200.0:
		await physics_frame
	car.throttle_input = 0.0
	car.brake_input = 1.0
	await _frames(45)
	_check(cam._chase_pull < -0.4, "freando a câmera se aproxima (%.2f m, %.1f G)" % [cam._chase_pull, cam._head_g.z])
	car.brake_input = 0.0
	car.throttle_input = 0.5
	while car.speed_kmh > 130.0:
		await physics_frame
	# Toque curto no volante (0,15 s): a câmera quase não deve se mexer
	var cam_fwd := -cam.global_basis.z
	var car_fwd := car.global_basis.z
	var early := 0.0
	car.steer_input = 0.35
	for i in 120:
		if i == 18:
			car.steer_input = 0.0
		await physics_frame
		if i < 42:
			early = maxf(early, rad_to_deg((-cam.global_basis.z).angle_to(cam_fwd)))
	var car_turn := rad_to_deg(car.global_basis.z.angle_to(car_fwd))
	print("    toque no volante: carro virou %.2f°, câmera %.2f° nos primeiros 0,35 s" % [car_turn, early])
	_check(early < 1.2, "toque curto no volante: a câmera quase não reage na hora (%.2f°)" % early)
	car.throttle_input = 0.0
	while car.speed_kmh > 130.0:
		await physics_frame
	car.throttle_input = 0.5
	car.steer_input = 0.6
	await _frames(90)
	var xf := car.get_global_transform_interpolated()
	_check(cam._head_g.x > 1.0, "curva para a esquerda: G lateral para dentro (%.1f G) desliza a câmera para fora" % cam._head_g.x)
	_check(cam.global_basis.y.dot(xf.basis.x) > 0.02, "curva: a câmera inclina para dentro da curva")
	_check(cam.global_basis.z.dot(-xf.basis.x) < 0.0, "curva: olha para dentro da curva")
	car.steer_input = 0.0
	await _frames(30)
	cam._trauma = 0.0
	# Batida: desaceleração brusca (~200 km/h → 80 km/h num passo)
	car.linear_velocity = car.linear_velocity * 0.4
	await _frames(2)
	_check(cam._trauma > 0.3, "batida faz a câmera tremer (trauma %.2f)" % cam._trauma)
	cam._trauma = 0.0
	var p := car.global_position
	car.global_position = p + Vector3(0, 0, 200)
	car.linear_velocity = Vector3.ZERO
	await _frames(2)
	_check(cam._trauma < 0.05, "teletransporte não conta como batida")
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
