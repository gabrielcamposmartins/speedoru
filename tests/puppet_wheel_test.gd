extends SceneTree
## Rodas dos carros da rede (marionetes) sem tremedeira (sem janela):
##   godot --headless --path . -s res://tests/puppet_wheel_test.gd
## Move um carro marionete em linha reta a 250 km/h por fora (como o NetRaceClient faz) e confere
## que o motor de física não mexe nas rodas: cada roda fica exatamente na altura mandada pelo
## servidor, esterça junto com o carro e gira para frente na velocidade certa.

var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	gs.shape = WorldBoundaryShape3D.new()
	ground.add_child(gs)
	world.add_child(ground)
	var car := (load("res://scenes/car/f1_car.tscn") as PackedScene).instantiate() as F1Car
	world.add_child(car)
	car.set_puppet(true)
	for i in 10:
		await physics_frame
	var speed := 250.0 / 3.6
	var dt := 1.0 / Engine.physics_ticks_per_second
	var pos := Vector3(0, 0.0, 0)
	var drops := PackedFloat32Array([0.05, 0.05, 0.07, 0.07])
	var max_err := 0.0
	var spin_before := 0.0
	var front := car.get_wheels()[0]
	for i in 240:
		pos.z += speed * dt
		car.global_transform = Transform3D(Basis(), pos)
		car.linear_velocity = Vector3(0, 0, speed)
		car.puppet_wheel_drop = drops
		car.steering = 0.1 if i > 120 else 0.0
		await physics_frame
		for k in 4:
			var w := car.get_wheels()[k]
			var want: float = car._mounts[k].y - drops[k]
			var err := absf(w.position.y - want)
			if err > 0.001:
				print("    passo %d roda %d: y %.3f esperado %.3f" % [i, k, w.position.y, want])
			max_err = maxf(max_err, err)
		if i == 100:
			spin_before = car._puppet_spin[0]
	_check(max_err < 0.0005, "rodas na altura do servidor, sem a suspensão local mexendo (erro máx %.4f m)" % max_err)
	# Esterço pelo eixo da roda (a frente dela gira junto com o pneu)
	var axle := front.transform.basis.x
	var steer := atan2(-axle.z, axle.x)
	_check(absf(steer - 0.1) < 0.01, "roda dianteira esterça com o carro (%.3f rad)" % steer)
	var spun := fposmod(car._puppet_spin[0] - spin_before, TAU)
	var expected := fposmod(speed * dt * 139.0 / front.wheel_radius, TAU)
	_check(absf(spun - expected) < 0.05 or absf(absf(spun - expected) - TAU) < 0.05, "roda gira na velocidade do carro")
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
