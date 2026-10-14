extends SceneTree
## Capturas de tela da Sky Aerobase para conferência visual (com janela, não entra na bateria de testes):
##   godot --path . -s res://tests/sky_aerobase_shots.gd -- <pasta de saída> [horário] [prefixo]
## Gera a pista e salva PNGs de vários pontos de vista: reta e boxes, curvas, descida, túnel, chicane
## sem barreira (olhando o vazio), a plataforma de lado e por baixo (motores), a base aérea e vistas
## do alto.

var scene: Node3D
var track: RaceTrack
var cam: Camera3D
var out_dir := ""
var prefix := "sky"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	RaceSettings.time_of_day = int(args[1]) if args.size() > 1 and args[1].is_valid_int() else 0
	prefix = args[2] if args.size() > 2 and not args[2].begins_with("--") else "sky"
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_sky_shots_profile.cfg"
		profile.reset_profile()
	scene = (load("res://scenes/tracks/sky_aerobase.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	track = scene.get_node("Track")
	_run.call_deferred()


## Câmera em s (m) da pista, deslocada (lateral, altura, para trás) e olhando para um ponto.
func _at_track(s: float, lateral: float, height: float, back: float, look_ahead: float, look_lat := 0.0, look_h := 1.0) -> Transform3D:
	var p := track.path
	var f := p.frame_at(s - back, lateral, height)
	var target := p.frame_at(s + look_ahead, look_lat, look_h).origin
	return Transform3D(Basis.looking_at(target - f.origin), f.origin)


func _look(eye: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(at - eye), eye)


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
	await _shot("grid", _at_track(-60.0, 0.0, 2.6, 0.0, 60.0))
	await _shot("reta_boxes", _at_track(-250.0, 3.0, 3.0, 0.0, 120.0, -14.0, 4.0))
	await _shot("curva_torre", _at_track(330.0, 0.0, 2.4, 0.0, 110.0))
	await _shot("esses", _at_track(900.0, 0.0, 2.4, 0.0, 130.0))
	await _shot("grampo", _at_track(1380.0, 0.0, 2.6, 0.0, 70.0))
	await _shot("descida", _at_track(1600.0, 0.0, 2.6, 0.0, 140.0))
	await _shot("curva_portal", _at_track(1850.0, 0.0, 2.6, 0.0, 70.0))
	await _shot("tunel_entrada", _at_track(1975.0, 0.0, 2.4, 0.0, 100.0))
	await _shot("tunel", _at_track(2150.0, 0.0, 2.4, 0.0, 80.0))
	await _shot("chicane", _at_track(2385.0, 0.0, 2.4, 0.0, 70.0))
	await _shot("reta_oposta", _at_track(2530.0, 0.0, 2.4, 0.0, 150.0))
	await _shot("curva_ceu", _at_track(2700.0, 0.0, 2.4, 0.0, 120.0))
	await _shot("ultima_curva", _at_track(3140.0, 0.0, 2.4, 0.0, 100.0))
	# Barreira de metal com a faixa em holograma, de perto, e a nave do túnel por fora
	var bi := p.index_at(2600.0)
	var bf := p.frame_at(2590.0, p.half_width(bi, 1) - 1.0, 1.0)
	await _shot("barreira_holo", _look(bf.origin, p.frame_at(2610.0, p.half_width(bi, 1) + 2.0, 0.6).origin), 60.0)
	var ts := (track.layout.tunnel.x + track.layout.tunnel.y) * 0.5
	var ti := p.index_at(ts)
	var out := SkyShip.outer_side(track, track.layout.tunnel.x, track.layout.tunnel.y)
	await _shot("nave_fora", _look(p.frame_at(ts - 60.0, out * 70.0, 25.0).origin, p.frame_at(ts, 0.0, 6.0).origin), 60.0)
	await _shot("nave_dentro", _at_track(ts - 40.0, 0.0, 2.4, 0.0, 60.0), 75.0)
	await _shot("nave_entrada", _at_track(track.layout.tunnel.x - 90.0, 0.0, 3.0, 0.0, 90.0, 0.0, 8.0), 65.0)
	await _shot("propulsores", _at_track(700.0, -4.0, 3.0, 0.0, 60.0, -14.0, 2.0), 70.0)
	# Céu: holofotes, balões e dirigíveis
	await _shot("ceu", _at_track(2560.0, 0.0, 2.0, 0.0, 400.0, 0.0, 260.0), 80.0)
	await _shot("ceu_boxes", _at_track(-300.0, 0.0, 2.0, 0.0, 500.0, 0.0, 240.0), 80.0)
	var ship := track.find_child("Airship3", true, false) as Node3D
	if ship:
		await _shot("dirigivel", _look(ship.global_position + ship.global_basis.x * 70.0 + Vector3(0, 12, 0) - ship.global_basis.z * 25.0,
			ship.global_position), 60.0)
		await _shot("dirigivel_baixo", _look(ship.global_position + ship.global_basis.x * 45.0 + Vector3(0, -30, 0) + ship.global_basis.z * 30.0,
			ship.global_position), 60.0)
	# A nave rente à pista e a que passa abaixo dela, vistas da pista
	for pair: Array in [["Airship0", "nave_rente"], ["Airship1", "nave_abaixo"]]:
		var a := track.find_child(pair[0], true, false) as Node3D
		if a:
			var sa := p.project(a.global_position).x
			await _shot(pair[1], _look(p.frame_at(sa - 60.0, 0.0, 2.4).origin, a.global_position), 70.0)
	# Na borda aberta da chicane, olhando o vazio e o mar
	var i := p.index_at(2460.0)
	var edge := track.deck_edge(i, -1)
	var f := p.frame_at(2460.0, -edge + 1.5, 1.6)
	await _shot("borda_abismo", _look(f.origin, f.origin - p.lefts[i] * 40.0 + Vector3.DOWN * 60.0 + p.tangents[i] * 20.0), 75.0)
	# A plataforma de lado e por baixo (motores e jatos)
	var s := 600.0
	var g := p.frame_at(s, -80.0, -6.0)
	await _shot("plataforma_lado", _look(g.origin, p.frame_at(s + 40.0, 0.0, -4.0).origin), 60.0)
	var u := p.frame_at(s, -30.0, -40.0)
	await _shot("plataforma_baixo", _look(u.origin, p.frame_at(s + 60.0, 0.0, -3.0).origin), 70.0)
	# Base aérea: porta-aviões e torres
	var bounds := p.bounds()
	var c := Vector3(bounds.get_center().x, 40.0, bounds.get_center().y)
	await _shot("alto_geral", _look(c + Vector3(900, 650, 900), c), 55.0)
	await _shot("alto_mar", _look(c + Vector3(-300, 260, 1100), c + Vector3(0, -300, 0)), 70.0)
	var base := track.find_child("SkyBase", true, false) as Node3D
	var label := base.find_children("*", "Label3D", true, false)
	if label.size() > 0:
		var lb := label[0] as Label3D
		await _shot("porta_avioes", _look(lb.global_position + lb.global_basis.z * 160.0 + Vector3.UP * 40.0, lb.global_position), 60.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_sky_shots_profile.cfg"))
	quit()

