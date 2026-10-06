extends SceneTree
## Capturas de uma batida (precisa de janela):
##   godot --path . -s res://tests/capture_crash.gd -- <pasta>

var out_dir := "user://captures"
var scene: Node3D
var car: F1Car


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	scene = (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	scene.set("start_light_sequence", false)
	root.add_child(scene)
	car = scene.get_node("F1Car")
	car.player_controlled = false
	_run.call_deferred()


func _shot(file: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
	print("salvo ", file)


func _run() -> void:
	await _physics(30)
	var track: RaceTrack = scene.get_node("Track")
	var cam: RaceCamera = scene.get_node("RaceCamera")
	var p := track.path
	var i := p.index_at(3000.0)
	var a := deg_to_rad(45.0)
	var dir := (p.tangents[i] * cos(a) + p.lefts[i] * sin(a)).normalized()
	var dist := track.barrier[0][i] + p.width_left[i]
	var start := p.points[i] + p.lefts[i] * (dist - 2.5) - dir * 30.0 + Vector3.UP * 0.1
	car.global_transform = Transform3D(Basis.looking_at(-dir), start)
	car.reset_physics_interpolation()
	cam.reset_physics_interpolation()
	await _physics(20)
	car.linear_velocity = dir * 160.0 / 3.6
	var shot := 0
	for k in 160:
		await physics_frame
		if car.get_node("Damage").get_overall() < 0.999 and shot < 3 and k % 4 == 0:
			await process_frame
			_shot("crash_%d.png" % shot)
			shot += 1
	await _physics(120)
	var dmg: CarDamage = car.get_node("Damage")
	print("Depois: em pé %.2f, velocidade %.1f km/h, peças soltas %s" % [car.global_basis.y.y, car.speed_kmh, dmg.detached.keys()])
	# Câmera livre olhando o carro de cima/lado
	var free := Camera3D.new()
	scene.add_child(free)
	var c := car.global_position
	free.global_transform = Transform3D(Basis(), c + p.lefts[i] * -7.0 + p.tangents[i] * -5.0 + Vector3.UP * 4.0).looking_at(c, Vector3.UP)
	cam.get_node("Outline").reparent(free, false)
	free.current = true
	await _frames(30)
	_shot("crash_after.png")
	quit()


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _physics(n: int) -> void:
	for k in n:
		await physics_frame
