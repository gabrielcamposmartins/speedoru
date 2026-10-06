extends SceneTree
## Screenshots das câmeras (precisa de janela):
##   godot --path . -s res://tests/capture_cameras.gd -- <pasta>

var out_dir := "user://captures"
var car: F1Car
var cam: RaceCamera
var t := 0.0
var steps := [
	[2.5, "mode", RaceCamera.Mode.DRIVER],
	[4.0, "shot", "driver"],
	[4.1, "press", "look_back"],
	[4.9, "shot", "driver_mirror"],
	[5.0, "release", "look_back"],
	[5.1, "mode", RaceCamera.Mode.CHASE],
	[5.8, "press", "look_back"],
	[6.6, "shot", "chase_lookback"],
	[6.7, "release", "look_back"],
	[6.8, "mode", RaceCamera.Mode.T_CAM],
	[7.0, "press", "look_back"],
	[7.6, "shot", "tcam_lookback"],
	[7.7, "release", "look_back"],
	[7.8, "stop", null],
	[10.5, "mode", RaceCamera.Mode.ORBIT],
	[10.6, "orbit", Vector3(0.8, 0.5, 6.0)],
	[11.2, "shot", "orbit_high"],
	[11.3, "orbit", Vector3(2.4, -0.15, 4.0)],
	[11.9, "shot", "orbit_ground"],
	[12.0, "quit", null],
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


func _process(delta: float) -> bool:
	t += delta
	if index < 13:
		car.throttle_input = 1.0 if car.speed_kmh < 150.0 else 0.3
		car.steer_input = 0.04
	while index < steps.size() and t >= steps[index][0]:
		var step: Array = steps[index]
		index += 1
		match step[1]:
			"mode":
				cam.set_mode(step[2])
			"press":
				Input.action_press(step[2])
			"release":
				Input.action_release(step[2])
			"stop":
				car.throttle_input = 0.0
				car.brake_input = 1.0
				car.steer_input = 0.0
			"orbit":
				cam._orbit_yaw = step[2].x
				cam._orbit_pitch = step[2].y
				cam._orbit_distance = step[2].z
				cam._orbit_idle = 0.0
			"shot":
				var path := out_dir.path_join(step[2] + ".png")
				root.get_texture().get_image().save_png(path)
				print("salvo %s  câmera y=%.2f  vel=%.0f" % [step[2], cam.global_position.y, car.speed_kmh])
			"quit":
				return true
	return false
