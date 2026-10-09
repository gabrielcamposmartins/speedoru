extends SceneTree
## Vitrine da pista (com janela):  godot --path . -s res://tests/capture_showcase.gd -- <pasta> [monza|monaco]
## Fotografa os balões de personagem do começo das retas (como o piloto os vê), os outdoors e os
## murais (TrackShowcase.views) e um dirigível com imagem de perto. Confere que os dois balões e as
## imagens foram postos.

var out_dir := ""
var track_id := "monza"
var scene: Node3D
var track: RaceTrack
var cam: Camera3D
var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	track_id = args[1] if args.size() > 1 else "monza"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_capshow_profile.cfg"
		profile.reset_profile()
	RaceSettings.track = track_id
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	scene = (load(RaceSettings.track_scene(track_id)) as PackedScene).instantiate()
	root.add_child(scene)
	track = scene.get_node("Track")
	_run.call_deferred()


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _shot(file: String, from: Vector3, to: Vector3, fov := 55.0) -> void:
	cam.global_transform = Transform3D(Basis(), from).looking_at(to, Vector3.UP)
	cam.fov = fov
	await _frames(14)
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [track_id, file]))
	print("captura ", file)


func _run() -> void:
	while not track.is_built:
		await process_frame
	await _frames(30)
	var hud := scene.get_node_or_null("HUD") as CanvasItem
	if hud:
		hud.visible = false
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	cam = Camera3D.new()
	cam.far = 6000.0
	root.add_child(cam)
	cam.current = true
	var show := track.find_child("Showcase", true, false) as TrackShowcase
	_check(show != null, "vitrine montada")
	if show == null:
		quit(1)
		return
	var balloons := show.views.filter(func(v: Array) -> bool: return str(v[0]).ends_with("Balloon"))
	_check(balloons.size() == 2, "os dois balões de personagem (%d)" % balloons.size())
	_check(TrackShowcase.image_count() >= 1, "imagens de assets/outdoors (%d)" % TrackShowcase.image_count())
	var others := show.views.size() - balloons.size()
	_check(others >= 3, "outdoors e murais com imagens (%d)" % others)
	for v in show.views:
		print("  ", v[0], " olho ", (v[1] as Vector3).round(), " alvo ", (v[2] as Vector3).round())
		await _shot(str(v[0]), v[1], v[2], 55.0 if str(v[0]).ends_with("Balloon") else 40.0)
	# Balão de perto (para ver o modelo)
	for node in show.get_children():
		if node.name.ends_with("Balloon"):
			var at := (node as Node3D).global_position + Vector3.UP * TrackShowcase.BALLOON_MID
			var face := (node as Node3D).global_basis.z.normalized()
			await _shot("perto_" + str(node.name), at + face * 80.0 + Vector3.UP * 5.0, at, 50.0)
	# Um dirigível com imagem, de perto
	for mi: MeshInstance3D in track.find_children("*Blimp*", "MeshInstance3D", true, false):
		if mi.mesh and mi.mesh.get_surface_count() >= 3:
			var c := mi.global_position
			var side := mi.global_basis.x
			var back := mi.global_basis.z
			await _shot("dirigivel", c + side * 45.0 - back * 22.0 + Vector3.UP * 4.0, c - back * 14.0, 45.0)
			break
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_capshow_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
