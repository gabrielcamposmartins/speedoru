extends SceneTree
## Capturas de tela de Suzuka para conferência visual (com janela, não entra na bateria de testes):
##   godot --path . -s res://tests/suzuka_shots.gd -- <pasta de saída>
## Gera a pista e salva PNGs de vários pontos de vista (grid, S, Degner, ponte, grampo, Spoon, 130R...).

var scene: Node3D
var track: RaceTrack
var cam: Camera3D
var out_dir := ""
var prefix := "suzuka"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	# Opcional: horário e ambiente (índices de DaylightPresets) e um prefixo para os arquivos
	RaceSettings.time_of_day = int(args[1]) if args.size() > 1 else 0
	RaceSettings.biome = int(args[2]) if args.size() > 2 else 0
	prefix = args[3] if args.size() > 3 else "suzuka"
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_shots_profile.cfg"
		profile.reset_profile()
	scene = (load("res://scenes/tracks/suzuka.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	track = scene.get_node("Track")
	_run.call_deferred()


## Câmera em s (m) da pista, deslocada (lateral, altura, para trás) e olhando para um ponto.
func _at_track(s: float, lateral: float, height: float, back: float, look_ahead: float, look_lat := 0.0, look_h := 1.0) -> Transform3D:
	var p := track.path
	var f := p.frame_at(s - back, lateral, height)
	var target := p.frame_at(s + look_ahead, look_lat, look_h).origin
	return Transform3D(Basis.looking_at(target - f.origin), f.origin)


func _shot(name: String, xf: Transform3D, fov := 70.0) -> void:
	cam.global_transform = xf
	cam.fov = fov
	for k in 25:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("%s_%s.png" % [prefix, name]))
	print("captura: ", name)


func _run() -> void:
	while not track.is_built:
		await process_frame
	for n in ["HUD"]:
		var node := scene.get_node_or_null(n)
		if node:
			node.queue_free()
	cam = Camera3D.new()
	cam.far = 12000.0
	scene.add_child(cam)
	cam.current = true
	var outline := scene.get_node_or_null("RaceCamera/Outline")
	if outline:
		outline.reparent(cam, false)
	for k in 60:
		await process_frame
	var p := track.path
	var only := OS.get_cmdline_user_args().slice(4)
	var shots := [
		["grid", _at_track(-40.0, 0.0, 2.6, 0.0, 60.0)],
		["boxes", _at_track(-60.0, -10.0, 6.0, 30.0, 10.0, -18.0, 1.0)],
		["curva1", _at_track(470.0, 0.0, 2.2, 0.0, 80.0)],
		["curva2", _at_track(700.0, 0.0, 2.2, 0.0, 60.0)],
		["s1", _at_track(950.0, 0.0, 2.2, 0.0, 70.0)],
		["s2", _at_track(1250.0, 0.0, 2.2, 0.0, 70.0)],
		["dunlop", _at_track(1650.0, 0.0, 2.2, 0.0, 80.0)],
		["degner1", _at_track(2120.0, 0.0, 2.2, 0.0, 60.0)],
		["degner2", _at_track(2290.0, 0.0, 2.2, 0.0, 60.0)],
		["sob_ponte", _at_track(p.crossings[0].x - 70.0, 0.0, 2.0, 0.0, 70.0)],
		["sob_ponte_perto", _at_track(p.crossings[0].x - 25.0, 0.0, 1.6, 0.0, 30.0, 0.0, 4.0)],
		["grampo", _at_track(2700.0, 0.0, 2.4, 0.0, 70.0)],
		["200r", _at_track(2980.0, 0.0, 2.2, 0.0, 80.0)],
		["spoon", _at_track(3640.0, 0.0, 2.2, 0.0, 80.0)],
		["reta_oposta", _at_track(4400.0, 0.0, 2.2, 0.0, 120.0)],
		["sobre_ponte", _at_track(p.crossings[0].y - 90.0, 0.0, 2.2, 0.0, 90.0)],
		["130r", _at_track(4840.0, 0.0, 2.2, 0.0, 70.0)],
		["chicane", _at_track(-640.0, 0.0, 2.2, 0.0, 70.0)],
		["ultima_curva", _at_track(-330.0, 0.0, 2.2, 0.0, 80.0)],
	]
	var cp := p.position_at(p.crossings[0].x)
	var up_dir := p.tangent_at(p.crossings[0].y)
	var side := Vector3(up_dir.z, 0.0, -up_dir.x)
	var eye := cp + side * 110.0 - up_dir * 40.0 + Vector3(0, 55, 0)
	shots.append(["ponte_aerea", Transform3D(Basis.looking_at(cp + Vector3(0, 4, 0) - eye), eye)])
	shots.append(["ponte_volta", _at_track(p.crossings[0].x + 45.0, 0.0, 3.0, 0.0, -45.0, 0.0, 6.0)])
	var wheel := scene.find_child("FerrisWheel", true, false) as Node3D
	if wheel:
		shots.append(["roda_gigante", _at_track(150.0, 2.0, 2.0, 0.0, 10.0)])
		var w := wheel.global_position + Vector3(0, 25, 0)
		eye = w + wheel.global_basis.x * 120.0 + Vector3(0, -10, 40)
		shots.append(["roda_perto", Transform3D(Basis.looking_at(w - eye), eye)])
	var b := p.bounds()
	var center := Vector3(b.get_center().x, 0.0, b.get_center().y)
	eye = center + Vector3(300, 700, 900)
	shots.append(["vista_geral", Transform3D(Basis.looking_at(center - eye), eye)])
	for sh in shots:
		if only.is_empty() or sh[0] in only:
			await _shot(sh[0], sh[1])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_shots_profile.cfg"))
	quit(0)
