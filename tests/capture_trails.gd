extends SceneTree
## Capturas dos rastros de partículas (CarParticles), andando, parado na pista (nada) e parado na
## vitrine da garagem (precisa de janela):
##   godot --path . -s res://tests/capture_trails.gd -- <pasta> [efeito ...]

var out_dir := "user://captures"
var only: Array[String] = []
var scene: Node3D
var car: F1Car
var track: RaceTrack
var cam: RaceCamera


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	for k in range(1, args.size()):
		only.append(args[k])
	DirAccess.make_dir_recursive_absolute(out_dir)
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_trails_profile.cfg"
		profile.reset_profile()
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
	print("salvo ", file, " | %.0f km/h" % car.speed_kmh)


func _physics(n: int) -> void:
	for k in n:
		await physics_frame


func _place(speed: float) -> void:
	car.global_transform = track.get_grid_transform(0)
	car.reset_physics_interpolation()
	car.linear_velocity = car.global_basis.z * speed
	car.angular_velocity = Vector3.ZERO


func _use_camera(c: Camera3D) -> void:
	var outline := cam.get_node_or_null("Outline")
	if outline == null:
		for n in scene.find_children("Outline", "", true, false):
			outline = n
	if outline and outline.get_parent() != c:
		outline.reparent(c, false)
	c.current = true


func _run() -> void:
	await _physics(30)
	track = scene.get_node("Track")
	cam = scene.get_node("RaceCamera")
	var free := Camera3D.new()
	scene.add_child(free)
	var daylight := scene.find_child("Daylight", true, false) as Daylight
	var effects: Array = CarParticles.EFFECTS.keys() if only.is_empty() else only
	for id: String in effects:
		car.config.trail = id
		# Andando: câmera de perseguição
		_use_camera(cam)
		_place(55.0)
		car.throttle_input = 1.0
		car.brake_input = 0.0
		await _physics(150)
		await _shot("trail_%s_chase.png" % id)
		# Andando, vista de lado (um pouco à frente, olhando o rastro): câmera presa ao carro
		var side := Camera3D.new()
		car.add_child(side)
		side.transform = Transform3D(Basis(), Vector3(5.5, 2.0, 3.0)).looking_at(Vector3(0, 0.3, -7.0), Vector3.UP)
		_use_camera(side)
		await _physics(2)
		await _shot("trail_%s_side.png" % id)
		_use_camera(free)
		side.queue_free()
		# Parado (como na garagem)
		car.throttle_input = 0.0
		car.brake_input = 1.0
		_place(0.0)
		await _physics(200)
		var c := car.global_position
		free.global_transform = Transform3D(Basis(), c - car.global_basis.z * 6.5 + car.global_basis.x * 3.5 + Vector3.UP * 1.8) \
			.looking_at(c + Vector3.UP * 0.5 - car.global_basis.z * 1.5, Vector3.UP)
		await _physics(2)
		# Parado na pista: nada; parado na vitrine (garagem): fraco, de amostra
		await _shot("trail_%s_parked_pista.png" % id)
		car.set_meta("showcase", true)
		await _physics(120)
		await _shot("trail_%s_parked.png" % id)
		car.remove_meta("showcase")
		if id in ["fire", "lightning", "stars", "embers"]:
			daylight.time_of_day = DaylightPresets.TimeOfDay.NIGHT
			_use_camera(cam)
			_place(55.0)
			car.throttle_input = 1.0
			car.brake_input = 0.0
			await _physics(150)
			await _shot("trail_%s_night.png" % id)
			daylight.time_of_day = DaylightPresets.TimeOfDay.DAY
	car.config.trail = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_trails_profile.cfg"))
	quit()
