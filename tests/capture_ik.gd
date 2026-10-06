extends SceneTree
## Screenshots dos braços seguindo o volante (precisa de janela):
##   godot --path . -s res://tests/capture_ik.gd -- <pasta>

var out_dir := "user://captures"
var car: F1Car
var cam: RaceCamera
var t := 0.0
var steps := [
	[1.0, "steer", 0.0], [1.6, "shot", "ik_driver_center"],
	[1.7, "steer", 1.0], [2.6, "shot", "ik_driver_left"],
	[2.7, "steer", -1.0], [3.8, "shot", "ik_driver_right"],
	[3.9, "outside", null], [4.6, "shot", "ik_outside_right"],
	[4.7, "steer", 1.0], [5.8, "shot", "ik_outside_left"],
	[5.9, "quit", null],
]
var index := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene := (load("res://scenes/test/test_track.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	car = scene.get_node("F1Car")
	cam = scene.get_node("RaceCamera")
	car.player_controlled = false
	cam.set_mode(RaceCamera.Mode.DRIVER)


func _process(delta: float) -> bool:
	t += delta
	while index < steps.size() and t >= steps[index][0]:
		var step: Array = steps[index]
		index += 1
		match step[1]:
			"steer":
				car.steer_input = step[2]
			"outside":
				cam.set_mode(RaceCamera.Mode.ORBIT)
				cam.set_process(false)
				car.steer_input = -1.0
			"shot":
				if not cam.is_processing():
					var xf := car.global_transform
					cam.global_position = xf * Vector3(0.0, 1.25, 1.05)
					cam.look_at(xf * Vector3(0.0, 0.55, 0.15))
					cam.fov = 55.0
				var path := out_dir.path_join(step[2] + ".png")
				root.get_texture().get_image().save_png(path)
				print("salvo ", step[2], "  volante=%.0f°" % rad_to_deg(car.steering * car.steering_wheel_ratio))
			"quit":
				return true
	return false
