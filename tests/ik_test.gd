extends SceneTree
## Teste do IK dos braços (sem janela):
##   godot --headless --path . -s res://tests/ik_test.gd
## Gira o volante e mede a distância entre cada pulso e o alvo preso à manopla, o desvio de
## rotação da mão e a posição dos cotovelos (devem ficar dentro do cockpit).

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
	await _frames(30)
	var rig := car.get_node("DriverRig") as DriverRig
	if rig.ik == null:
		print("FALHA: IK não foi criado")
		quit(1)
		return
	var skeleton := rig.ik.get_skeleton()
	print("Esqueleto: %d ossos, modificadores: %s" % [skeleton.get_bone_count(),
		skeleton.get_children().filter(func(n): return n is SkeletonModifier3D).map(func(n): return str(n.name))])
	var worst := 0.0
	var worst_rot := 0.0
	for steer in [0.0, 1.0, -1.0, 0.5]:
		car.steer_input = steer
		await _frames(90)
		var errors := rig.get_hand_errors()
		var line := "volante %+4.0f°: pulso→alvo E %.1f mm, D %.1f mm" % [
			rad_to_deg(car.steering * car.steering_wheel_ratio), errors[0] * 1000.0, errors[1] * 1000.0]
		for i in 2:
			worst = maxf(worst, errors[i])
			var rot_err := rad_to_deg(rig.hand_poses[i].basis.get_rotation_quaternion().angle_to(
				rig.get_target(i).global_basis.get_rotation_quaternion()))
			worst_rot = maxf(worst_rot, rot_err)
			var elbow := car.global_transform.affine_inverse() * rig.elbow_positions[i]
			line += " | %s: rot. %.1f°, cotovelo (%.2f, %.2f, %.2f)" % [
				rig.ik.get_end_bone_name(i), rot_err, elbow.x, elbow.y, elbow.z]
		print(line)
	var ok := worst < 0.01 and worst_rot < 2.0
	print("Pior erro: %.1f mm, %.1f° → %s" % [worst * 1000.0, worst_rot, "OK" if ok else "FALHA"])
	quit(0 if ok else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
