extends SceneTree
## Diagnóstico: a detecção contínua de colisão (CCD) do Godot para o carro em alta velocidade?
##   godot --headless --path . -s res://tests/ccd_probe.gd
## (Bug corrigido: com CCD o carro "parava do nada" a mais de 300 km/h ao pegar uma zebra de lado.)
## A 320 km/h, com CCD ligado e desligado: subir numa zebra em ângulo raso, raspar num muro e
## passar por cima de um detrito pequeno. Mede a menor velocidade logo depois. Também confere que,
## sem CCD, o carro não atravessa um muro de Monza (1,2 m) numa batida a 340 km/h.

const KERB_Y := 0.045
const ROAD_Y := 0.012


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for case in ["zebra", "muro", "detrito"]:
		for ccd in [true, false]:
			var r: Array = await _case(case, ccd)
			print("%-8s CCD %-10s → menor velocidade %3.0f km/h, maior queda num passo %3.0f km/h" % [case, "ligado" if ccd else "desligado", r[0], r[1]])
	for angle in [90.0, 30.0, 10.0]:
		var through: bool = await _crash(angle)
		_check(not through, "batida a %2.0f° a 340 km/h: o carro do jogo para no muro (não atravessa)" % angle)
	# Regressão: o carro como o jogo usa não perde velocidade na zebra nem no raspão
	for case in ["zebra", "muro"]:
		var r: Array = await _case(case, null)
		_check(r[0] > 280.0, "%s a 320 km/h com o carro do jogo: menor velocidade %.0f km/h" % [case, r[0]])
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)


var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


## Muro de 1,2 m (como os de Monza) a 60 m, batendo a [param angle] graus. Devolve se atravessou.
func _crash(angle: float) -> bool:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	gs.shape = WorldBoundaryShape3D.new()
	ground.add_child(gs)
	world.add_child(ground)
	var wall := StaticBody3D.new()
	var ws := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 2.6, 1.2)
	ws.shape = box
	wall.add_child(ws)
	# Face da frente do muro passa por (0, 0, 60); o muro fica do lado de lá
	var basis := Basis(Vector3.UP, deg_to_rad(90.0 - angle))
	wall.transform = Transform3D(basis, Vector3(0, 1.3, 60.0) + basis.z * 0.6)
	world.add_child(wall)
	var car := (load("res://scenes/car/f1_car.tscn") as PackedScene).instantiate() as F1Car
	car.player_controlled = false
	world.add_child(car)
	car.position = Vector3(0, 0.05, 0)
	for i in 60:
		await physics_frame
	car.linear_velocity = car.global_basis.z * (340.0 / 3.6)
	car.throttle_input = 1.0
	for i in int(Engine.physics_ticks_per_second * 2.0):
		await physics_frame
	# Lado de lá do muro = além da face de trás na direção da normal
	var depth := (car.global_position - (Vector3(0, 0, 60.0))).dot(basis.z)
	world.queue_free()
	await process_frame
	return depth > 1.2


func _case(kind: String, ccd: Variant) -> Array:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	gs.shape = WorldBoundaryShape3D.new()
	ground.add_child(gs)
	world.add_child(ground)
	match kind:
		"zebra":
			# Zebra de Monza (sobe 3,3 cm em 29 cm, 1,6 m de largura), 3° em relação ao carro, 120 m à frente
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var tri := ConcavePolygonShape3D.new()
			var prof := [Vector2(0.0, ROAD_Y), Vector2(0.29, KERB_Y), Vector2(1.36, KERB_Y), Vector2(1.6, ROAD_Y)]
			var faces := PackedVector3Array()
			for k in 3:
				var a: Vector2 = prof[k]
				var b: Vector2 = prof[k + 1]
				var a0 := Vector3(-a.x, a.y, 0.0)
				var b0 := Vector3(-b.x, b.y, 0.0)
				var a1 := Vector3(-a.x, a.y, 400.0)
				var b1 := Vector3(-b.x, b.y, 400.0)
				faces.append_array([a0, b0, b1, a0, b1, a1])
			tri.set_faces(faces)
			shape.shape = tri
			body.add_child(shape)
			body.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-3.0)), Vector3(1.0, 0.0, 120.0))
			world.add_child(body)
		"muro":
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.5, 1.0, 400.0)
			shape.shape = box
			body.add_child(shape)
			# Paralelo ao carro, encostando de leve (1°) a partir de 120 m
			body.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-1.0)), Vector3(-1.25, 0.5, 320.0))
			world.add_child(body)
		"detrito":
			var debris := RigidBody3D.new()
			debris.collision_layer = CarDamage.DEBRIS_LAYER
			debris.collision_mask = 1 | 2 | CarDamage.DEBRIS_LAYER
			debris.mass = 3.0
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.4, 0.08, 0.3)
			shape.shape = box
			debris.add_child(shape)
			debris.position = Vector3(0.0, 0.05, 120.0)
			world.add_child(debris)
	var car := (load("res://scenes/car/f1_car.tscn") as PackedScene).instantiate() as F1Car
	car.player_controlled = false
	world.add_child(car)
	# null = como o jogo usa o carro (o F1Car desliga o CCD sozinho)
	if ccd != null:
		car.continuous_cd = ccd
	car.position = Vector3(0, 0.05, 0)
	for i in 60:
		await physics_frame
	car.linear_velocity = car.global_basis.z * (320.0 / 3.6)
	car.throttle_input = 1.0
	var vmin := 1000.0
	var drop := 0.0
	var prev := 320.0
	for i in int(Engine.physics_ticks_per_second * 3.5):
		await physics_frame
		car.steer_input = 0.0
		var v := car.speed_kmh
		if i > 5:
			vmin = minf(vmin, v)
			drop = maxf(drop, prev - v)
		prev = v
	world.queue_free()
	await process_frame
	return [vmin, drop]
