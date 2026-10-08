extends SceneTree
## Prévia de um modelo de piloto no carro, sem trocar o asset (precisa de janela):
##   godot --path . -s res://tests/capture_driver.gd -- <piloto.glb> <pasta>
## Carrega o .glb em tempo de execução no lugar da peça "driver", remonta o IK dos braços e tira
## fotos de fora (vários ângulos) e da câmera do piloto (volante reto e esterçado).

var out_dir := ""
var car: F1Car
var cam: RaceCamera


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[1] if args.size() > 1 else OS.get_user_data_dir()
	var scene := (load("res://scenes/test/test_track.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	car = scene.get_node("F1Car")
	cam = scene.get_node("RaceCamera")
	car.player_controlled = false
	_run.call_deferred(args[0] if args.size() > 0 else "")


func _swap_driver(path: String) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("não carregou " + path)
		return
	var node := doc.generate_scene(state) as Node3D
	var asm := car.assembly
	asm._discard(asm._nodes.get("driver"))
	node.name = "driver"
	asm.livery.apply_to(node)
	asm.add_child(node)
	CarAssembly._tag_car_layer(node)
	for head in node.find_children("DriverHelmet*", "VisualInstance3D", true, false):
		(head as VisualInstance3D).layers = CarAssembly.HEAD_LAYER
	CarAssembly._tag_interior("driver", node)
	asm._nodes["driver"] = node
	(car.get_node("DriverRig") as DriverRig)._setup()


func _shot(name: String) -> void:
	for k in 6:
		await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("captura: ", name)


func _outside(eye: Vector3, target: Vector3, fov: float) -> void:
	cam.set_mode(RaceCamera.Mode.ORBIT)
	cam.set_process(false)
	var xf := car.global_transform
	cam.global_position = xf * eye
	cam.look_at(xf * target)
	cam.fov = fov


func _run(path: String) -> void:
	for k in 30:
		await process_frame
	if not path.is_empty():
		_swap_driver(path)
	for k in 10:
		await physics_frame
	_outside(Vector3(0.9, 1.35, 0.9), Vector3(0.0, 0.6, -0.05), 40.0)
	await _shot("jogo_frente34")
	_outside(Vector3(-0.8, 1.3, -1.2), Vector3(0.0, 0.62, -0.1), 40.0)
	await _shot("jogo_tras34")
	_outside(Vector3(1.9, 0.85, -0.1), Vector3(0.0, 0.6, -0.05), 35.0)
	await _shot("jogo_lado")
	_outside(Vector3(0.0, 1.05, 2.2), Vector3(0.0, 0.65, 0.0), 30.0)
	await _shot("jogo_frente")
	cam.set_process(true)
	cam.set_mode(RaceCamera.Mode.DRIVER)
	await _shot("jogo_camera_piloto")
	car.steer_input = 1.0
	for k in 40:
		await physics_frame
	await _shot("jogo_camera_piloto_esterco")
	_outside(Vector3(0.9, 1.35, 0.9), Vector3(0.0, 0.6, -0.05), 40.0)
	await _shot("jogo_frente34_esterco")
	var rig := car.get_node("DriverRig") as DriverRig
	print("erro das mãos (m): ", rig.get_hand_errors())
	quit()
