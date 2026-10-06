extends SceneTree
## Capturas de todos os horários × ambientes (precisa de janela):
##   godot --path . -s res://tests/capture_moods.gd -- <pasta> [rápido]
## Mesmo ponto de vista (reta principal com árvores e arquibancada) em cada combinação, mais
## algumas vistas extras (árvores folhosas, folhas na pista, refletores à noite).

var out_dir := "user://captures"
var scene: Node3D
var cam: Camera3D


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
	(scene.get_node("F1Car") as F1Car).player_controlled = false
	_run.call_deferred()


func _view(s0: float, lat0: float, h0: float, s1: float, lat1: float, h1: float) -> void:
	var p := (scene.get_node("Track") as RaceTrack).path
	cam.global_transform = Transform3D(Basis(), p.position_at(s0, lat0) + Vector3.UP * h0).looking_at(
		p.position_at(s1, lat1) + Vector3.UP * h1, Vector3.UP)


func _save(file: String) -> void:
	for k in 25:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
	print("salvo ", file)


func _run() -> void:
	for k in 20:
		await process_frame
	scene.get_node("HUD").visible = false
	var race_cam := scene.get_node("RaceCamera") as Camera3D
	cam = Camera3D.new()
	cam.far = 12000.0
	cam.fov = 65.0
	root.add_child(cam)
	race_cam.get_node("Outline").reparent(cam, false)
	cam.current = true
	var daylight := scene.find_child("Daylight", true, false) as Daylight
	var leaves := (scene.get_node("Track") as RaceTrack).leaves
	# Vista com árvores folhosas perto da pista
	var tree := leaves.tree_positions[leaves.tree_positions.size() / 3]
	var p := (scene.get_node("Track") as RaceTrack).path
	var pr := p.project(tree)
	for b in DaylightPresets.Biome.values():
		for t in DaylightPresets.TimeOfDay.values():
			daylight.biome = b
			daylight.time_of_day = t
			_view(pr.x - 45.0, 0.0, 2.5, pr.x + 10.0, pr.y * 0.7, 3.0)
			await _save("mood_%s_%s.png" % [DaylightPresets.BIOME_NAMES[b], DaylightPresets.TIME_NAMES[t]])
	# Noite na reta principal (refletores) e outono/sakura com folhas na pista
	daylight.biome = DaylightPresets.Biome.SUMMER
	daylight.time_of_day = DaylightPresets.TimeOfDay.NIGHT
	_view(-60.0, 0.0, 4.0, 60.0, 0.0, 1.0)
	await _save("night_straight.png")
	daylight.time_of_day = DaylightPresets.TimeOfDay.DAY
	for b in [DaylightPresets.Biome.AUTUMN, DaylightPresets.Biome.SAKURA]:
		daylight.biome = b
		_view(pr.x - 8.0, 0.0, 1.4, pr.x + 6.0, pr.y * 0.5, 0.0)
		await _save("ground_%s.png" % DaylightPresets.BIOME_NAMES[b])
	# Pinheiros de preenchimento na beira da pista (verão e outono)
	daylight.time_of_day = DaylightPresets.TimeOfDay.DAY
	for b in [DaylightPresets.Biome.SUMMER, DaylightPresets.Biome.AUTUMN, DaylightPresets.Biome.SAKURA]:
		daylight.biome = b
		_view(2380.0, 0.0, 2.0, 2470.0, 3.0, 2.0)
		await _save("pines_%s.png" % DaylightPresets.BIOME_NAMES[b])
	# Árvore folhosa de perto (folhas individuais e caindo), outono e verão
	var c := tree
	var away := Vector3(p.lefts[p.index_at(pr.x)].x, 0, p.lefts[p.index_at(pr.x)].z) * -signf(pr.y)
	for b in [DaylightPresets.Biome.SUMMER, DaylightPresets.Biome.AUTUMN]:
		daylight.biome = b
		cam.global_transform = Transform3D(Basis(), Vector3(c.x, 2.0, c.z) + away * 11.0 + Vector3(3, 0, 3)).looking_at(c + Vector3.UP * 0.5, Vector3.UP)
		await _save("leafy_%s.png" % DaylightPresets.BIOME_NAMES[b])
	quit()
