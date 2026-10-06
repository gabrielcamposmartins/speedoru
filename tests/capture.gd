extends SceneTree
## Captura screenshots do cenário de teste (precisa de janela, não use --headless):
##   godot --path . -s res://tests/capture.gd -- <pasta_de_saída>
## Dirige o carro automaticamente e salva imagens em vários modos de câmera.

var out_dir := "user://captures"
var scene: Node
var car: F1Car
var camera: RaceCamera
var hud: RaceHud
var frame := 0
var t := 0.0
var shots := [
	# tempo (s), nome, ação
	[1.2, "start_chase", ""],
	[1.3, "", "cam_far"],
	[2.0, "start_far", ""],
	[2.1, "", "drive"],
	[6.5, "speed_chase", "cam_chase"],
	[7.0, "", "cam_tcam"],
	[7.6, "speed_tcam", ""],
	[7.7, "", "cam_cockpit"],
	[8.3, "speed_cockpit", ""],
	[8.4, "", "stop_and_garage"],
	[11.0, "garage_variants", ""],
	[11.1, "", "orbit"],
	[11.8, "variants_front", ""],
	[12.0, "", "quit"],
]
var shot_index := 0
var orbit := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	scene = (load("res://scenes/test/test_track.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	car = scene.get_node("F1Car")
	camera = scene.get_node("RaceCamera")
	hud = scene.get_node("HUD")
	car.player_controlled = false


func _process(delta: float) -> bool:
	t += delta
	frame += 1
	if orbit:
		var xf := car.global_transform
		camera.set_process(false)
		camera.global_position = xf.origin + xf.basis * Vector3(3.2, 1.6, 4.8)
		camera.look_at(xf.origin + Vector3.UP * 0.5)
	while shot_index < shots.size() and t >= shots[shot_index][0]:
		var shot: Array = shots[shot_index]
		shot_index += 1
		if shot[1] != "":
			var img := root.get_texture().get_image()
			var path: String = out_dir.path_join(shot[1] + ".png")
			img.save_png(path)
			print("salvo: ", path, "  vel=%.0f km/h marcha=%d" % [car.speed_kmh, car.gear])
		match shot[2]:
			"cam_far":
				camera.mode = RaceCamera.Mode.CHASE_FAR
			"cam_chase":
				camera.mode = RaceCamera.Mode.CHASE
			"cam_tcam":
				camera.mode = RaceCamera.Mode.T_CAM
			"cam_cockpit":
				camera.mode = RaceCamera.Mode.COCKPIT
			"drive":
				car.throttle_input = 1.0
				car.drs_requested = true
			"stop_and_garage":
				car.throttle_input = 0.0
				car.brake_input = 1.0
				car.drs_requested = false
				camera.mode = RaceCamera.Mode.CHASE
				car.config.set_part("rear_wing", "highdf")
				car.config.set_part("front_wing", "lowdf")
				car.config.set_part("sidepods", "slim")
				car.config.set_part("engine_cover", "sharkfin")
				car.config.set_part("nose", "pointed")
				car.config.set_part("rim", "spoked")
				car.config.primary_color = Color("1d3fd8")
				car.config.accent_color = Color("ffd21f")
				car.config.suit_color = Color("1d3fd8")
				car.config.tyre_compound = CarConfig.TyreCompound.SOFT
				hud.garage.visible = true
			"orbit":
				hud.garage.visible = false
				orbit = true
			"quit":
				return true
	return false
