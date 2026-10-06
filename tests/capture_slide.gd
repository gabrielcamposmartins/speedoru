extends SceneTree
## Screenshots de perda de aderência (precisa de janela):
##   godot --path . -s res://tests/capture_slide.gd -- <pasta>

var out_dir := "user://captures"
var car: F1Car
var t := 0.0
var phase := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene := (load("res://scenes/test/test_track.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	car = scene.get_node("F1Car")
	car.player_controlled = false
	car.traction_control = false
	# Vira para a área livre (sem árvores) à esquerda da reta.
	car.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-40, 0.05, 100))


func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:  # ganha velocidade
			car.throttle_input = 1.0 if car.speed_kmh < 80.0 else 0.2
			if t > 4.0:
				phase = 1
				t = 0.0
		1:  # esterça e acelera tudo sem TC
			car.steer_input = 0.7
			car.throttle_input = 1.0
			if t > 0.45 and t - delta <= 0.45:
				_shot("oversteer")
			if t > 0.9 and t - delta <= 0.9:
				_shot("oversteer2")
			if t > 1.6:
				car.reset_car()
				car.traction_control = true
				phase = 2
				t = 0.0
		2:  # entra rápido demais esterçando tudo: subesterço
			car.steer_input = 0.0
			car.throttle_input = 1.0 if car.speed_kmh < 200.0 else 0.4
			if car.speed_kmh >= 200.0:
				phase = 3
				t = 0.0
		3:
			car.steer_input = 1.0
			car.brake_input = 0.6
			car.throttle_input = 0.0
			if t > 0.5 and t - delta <= 0.5:
				_shot("understeer")
			if t > 1.0:
				return true
	return false


func _shot(name: String) -> void:
	var path := out_dir.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("salvo %s  vel=%.0f  deriva=%.1f°  estado=%s  pneus=%s" % [name, car.speed_kmh,
		rad_to_deg(car.body_slip_angle), car.handling, car.tire_state])
