extends SceneTree
## Capturas do boost, marcas de pneu e sombra (precisa de janela):
##   godot --path . -s res://tests/capture_boost.gd -- <pasta>

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
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
	print("salvo ", file, " | bateria %.0f%% boost %s %.0f km/h" % [car.battery * 100.0, car.boost_active, car.speed_kmh])


func _physics(n: int) -> void:
	for k in n:
		await physics_frame


func _run() -> void:
	await _physics(30)
	var track: RaceTrack = scene.get_node("Track")
	var cam: RaceCamera = scene.get_node("RaceCamera")
	car.global_transform = track.get_grid_transform(0)
	car.reset_physics_interpolation()
	car.battery = 0.0
	car.throttle_input = 1.0
	await _physics(120 * 7)
	# Freada forte: marcas de pneu + recarga
	car.throttle_input = 0.0
	car.brake_input = 1.0
	await _physics(120 * 2)
	car.brake_input = 0.0
	print("depois da freada: bateria %.0f%%" % (car.battery * 100.0))
	await _shot("brake_marks_chase.png")
	# Câmera livre olhando as marcas no asfalto
	var free := Camera3D.new()
	scene.add_child(free)
	var c := car.global_position
	free.global_transform = Transform3D(Basis(), c + car.global_basis.z * 8.0 + Vector3.UP * 3.0 + car.global_basis.x * 3.0).looking_at(c - car.global_basis.z * 25.0, Vector3.UP)
	cam.get_node("Outline").reparent(free, false)
	free.current = true
	await _physics(10)
	await _shot("skid_marks.png")
	free.get_node("Outline").reparent(cam, false)
	cam.current = true
	# Boost
	car.battery = 1.0
	car.throttle_input = 1.0
	car.boost_input = true
	await _physics(120 * 1)
	await _shot("boost_chase.png")
	cam.set("mode", RaceCamera.Mode.ORBIT)
	cam.call("_apply_mode_settings")
	await _physics(60)
	await _shot("boost_orbit.png")
	car.boost_input = false
	car.throttle_input = 0.0
	car.brake_input = 1.0
	await _physics(120 * 3)
	car.brake_input = 0.0
	# Sombra de contato à noite e grama rosa na fantasia
	var daylight := scene.find_child("Daylight", true, false) as Daylight
	daylight.time_of_day = DaylightPresets.TimeOfDay.NIGHT
	await _physics(30)
	await _shot("shadow_night.png")
	# Neon à noite (vista de lado/de cima) e luz de freio piscando
	car.config.neon_enabled = true
	await _physics(60)
	await _shot("neon_night.png")
	var side := Camera3D.new()
	scene.add_child(side)
	var cp := car.global_position
	side.global_transform = Transform3D(Basis(), cp + car.global_basis.x * 6.0 + Vector3.UP * 1.2 - car.global_basis.z * 2.0).looking_at(cp + Vector3.UP * 0.3, Vector3.UP)
	cam.get_node("Outline").reparent(side, false)
	side.current = true
	await _physics(10)
	await _shot("neon_side.png")
	# Luz de freio: atrás do carro freando (sem neon, para ver bem)
	car.config.neon_enabled = false
	side.global_transform = Transform3D(Basis(), cp - car.global_basis.z * 5.0 + Vector3.UP * 1.1 + car.global_basis.x * 1.5).looking_at(cp + Vector3.UP * 0.5, Vector3.UP)
	car.global_transform = car.global_transform
	car.linear_velocity = car.global_basis.z * 20.0
	car.brake_input = 1.0
	for k in 3:
		await _physics(9)
		side.global_transform = Transform3D(Basis(), car.global_position - car.global_basis.z * 5.0 + Vector3.UP * 1.1 + car.global_basis.x * 1.5).looking_at(car.global_position + Vector3.UP * 0.5, Vector3.UP)
		await _shot("brake_light_%d.png" % k)
	car.brake_input = 0.0
	# Boost à noite, de lado
	car.battery = 1.0
	car.boost_input = true
	car.throttle_input = 0.3
	await _physics(40)
	await _shot("boost_night_side.png")
	car.boost_input = false
	car.throttle_input = 0.0
	side.get_node("Outline").reparent(cam, false)
	cam.current = true
	car.config.neon_enabled = false
	daylight.time_of_day = DaylightPresets.TimeOfDay.DAY
	daylight.biome = DaylightPresets.Biome.FANTASY
	await _physics(30)
	await _shot("fantasy_pink.png")
	quit()
