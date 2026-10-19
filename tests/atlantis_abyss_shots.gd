extends SceneTree
## Capturas de tela da Atlantis Abyss para conferência visual (com janela, não entra na bateria de
## testes):
##   godot --path . -s res://tests/atlantis_abyss_shots.gd -- <pasta de saída> [horário] [prefixo] [só,estes] --offline
## Gera a pista e salva PNGs de vários pontos de vista: reta e anfiteatro, templo, avenida, túnel de
## cristal, subida do aqueduto, o Portão de Poseidon (fora d'água), a passagem pela linha d'água, o
## mergulho, a chicane, o abismo, as cachoeiras largas e os aquedutos sobre a pista, as pontes e
## fachadas nas paredes do cânion, as baleias de perto, a barreira de vidro de perto e vistas do alto.
## O 4º argumento (nomes separados por vírgula) captura só esses.

var scene: Node3D
var track: RaceTrack
var cam: Camera3D
var out_dir := ""
var prefix := "atl"
var only: PackedStringArray = []
const PROFILE := "user://test_atlantis_shots_profile.cfg"
const ACCOUNT := "user://test_atlantis_shots_account.cfg"


func _initialize() -> void:
	# Nem a conta do jogador nem o servidor de verdade: com janela o Net conectaria sozinho (rode com
	# --offline) e regravaria o account.cfg do jogador
	var net := root.get_node_or_null("Net")
	if net:
		net.account_file = ACCOUNT
		net.server_host = "127.0.0.1"
		net.server_port = 9
	var args := Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool: return not a.begins_with("--"))
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	RaceSettings.time_of_day = int(args[1]) if args.size() > 1 and args[1].is_valid_int() else 0
	prefix = args[2] if args.size() > 2 and not args[2].begins_with("--") else "atl"
	if args.size() > 3:
		only = args[3].split(",", false)
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = PROFILE
		profile.reset_profile()
	scene = (load("res://scenes/tracks/atlantis_abyss.tscn") as PackedScene).instantiate()
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
	if not only.is_empty() and not name in only:
		return
	cam.global_transform = xf
	cam.fov = fov
	# (o HUD do modo de jogo aparece depois da pista pronta)
	var hud := scene.get_node_or_null("RaceHud") as CanvasLayer
	if hud:
		hud.visible = false
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
	await _shot("reta_anfiteatro", _at_track(-250.0, -3.0, 3.0, 0.0, 120.0, 14.0, 4.0))
	await _shot("curva_templo", _at_track(360.0, 0.0, 2.4, 0.0, 110.0))
	await _shot("avenida", _at_track(560.0, 0.0, 2.4, 0.0, 150.0))
	await _shot("curva_polvo", _at_track(740.0, 0.0, 2.4, 0.0, 110.0))
	await _shot("tunel_entrada", _at_track(track.layout.tunnel.x - 90.0, 0.0, 3.0, 0.0, 90.0, 0.0, 4.0), 65.0)
	await _shot("tunel", _at_track((track.layout.tunnel.x + track.layout.tunnel.y) * 0.5, 0.0, 2.4, 0.0, 80.0), 75.0)
	await _shot("tunel_fora", _look(p.frame_at(1180.0, 45.0, 14.0).origin, p.frame_at(1200.0, 0.0, 3.0).origin), 65.0)
	await _shot("grampo", _at_track(1380.0, 0.0, 2.6, 0.0, 70.0))
	await _shot("subida", _at_track(1560.0, 0.0, 2.6, 0.0, 200.0, 0.0, 8.0))
	await _shot("linha_dagua", _at_track(1800.0, 0.0, 2.4, 0.0, 120.0, 0.0, 3.0))
	await _shot("portao", _at_track(1990.0, 0.0, 2.6, 0.0, 140.0))
	await _shot("ponte_cachoeiras", _at_track(2150.0, 0.0, 2.6, 0.0, 120.0))
	# Rosto de Poseidon com a cachoeira, visto da ponte
	var canyon := SeaCanyon.profile(track)
	var water := track.layout.water_level
	var face: Array = PoseidonGate.FACES[0]
	var fi := p.index_at(face[0])
	var fat := SeaCanyon.face_at(track, canyon, fi, face[1], water + 14.0)
	await _shot("cachoeira", _look(p.frame_at(face[0] - 70.0, 0.0, 4.0).origin, fat), 60.0)
	# A cadeia de montanhas com as cachoeiras, vista da ponte
	await _shot("montanhas_emerso", _look(p.frame_at(2080.0, 0.0, 6.0).origin, p.frame_at(2200.0, 70.0, 26.0).origin), 70.0)
	await _shot("cachoeiras", _look(p.frame_at(1990.0, -4.0, 7.0).origin, p.frame_at(2200.0, -60.0, 22.0).origin), 70.0)
	# As cachoeiras grandes e largas e os aquedutos por cima da pista
	for k in PoseidonGate.WIDE_FALLS.size():
		var wf: Array = PoseidonGate.WIDE_FALLS[k]
		await _shot("cachoeira_larga%d" % k, _look(p.frame_at(wf[0] - 95.0, -4.0 * wf[1], 5.0).origin,
			p.frame_at(wf[0], 45.0 * wf[1], 22.0).origin), 70.0)
	for k in PoseidonGate.AQUEDUCTS.size():
		var aq: float = PoseidonGate.AQUEDUCTS[k]
		await _shot("aqueduto_pista%d" % k, _at_track(aq - 70.0, 0.0, 2.6, 0.0, 70.0, 0.0, 12.0), 72.0)
	await _shot("aqueduto_pista_lado", _look(p.frame_at(PoseidonGate.AQUEDUCTS[0] - 60.0, -38.0, 4.0).origin,
		p.frame_at(PoseidonGate.AQUEDUCTS[0], 0.0, 14.0).origin), 70.0)
	# Cipós e árvores debruçadas sobre a pista (olhando para a frente e para cima)
	var gate := track.find_child("PoseidonGate", true, false)
	var liana_s: Array = gate.get_meta("liana_s", [])
	if not liana_s.is_empty():
		await _shot("cipos", _at_track(liana_s[liana_s.size() / 2] - 45.0, 0.0, 2.6, 0.0, 45.0, 0.0, 16.0), 75.0)
	var canopy_s: Array = gate.get_meta("canopy_s", [])
	for k in mini(canopy_s.size(), 2):
		var cs: float = canopy_s[k * maxi(canopy_s.size() / 2, 1) % canopy_s.size()]
		await _shot("copas%d" % k, _at_track(cs - 40.0, 0.0, 2.6, 0.0, 40.0, 0.0, 14.0), 75.0)
	# Saindo da água ao lado da ponte: gotas na tela (a câmera sobe devagar pela linha d'água)
	if only.is_empty() or "saida_agua" in only:
		var si := p.index_at(1960.0)
		var base := p.frame_at(1960.0, -(SeaTube.clearance(track, si, -1) + 9.0), 0.0).origin
		var look := p.frame_at(2070.0, 0.0, 8.0).origin
		var y := water - 2.5
		cam.fov = 70.0
		cam.global_transform = _look(Vector3(base.x, y, base.z), look)
		await create_timer(1.0).timeout
		while y < water + 1.6:
			y += 0.12
			cam.global_transform = _look(Vector3(base.x, y, base.z), look)
			await process_frame
		for k in 10:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_saida_agua.png" % prefix))
		print("captura: saida_agua")
		# (o efeito acaba antes das próximas capturas)
		await create_timer(SeaSplash.DURATION + 0.2).timeout
	await _shot("aqueduto_fora", _look(p.frame_at(1800.0, -70.0, -8.0).origin, p.frame_at(1840.0, 0.0, -2.0).origin), 65.0)
	await _shot("mergulho", _at_track(2330.0, 0.0, 2.6, 0.0, 160.0, 0.0, -6.0))
	await _shot("tartaruga", _at_track(2650.0, 0.0, 2.4, 0.0, 90.0))
	await _shot("chicane", _at_track(2790.0, 0.0, 2.4, 0.0, 80.0))
	await _shot("abismo", _at_track(3000.0, 0.0, 2.4, 0.0, 200.0))
	await _shot("abismo_lado", _look(p.frame_at(3350.0, -60.0, -25.0).origin, p.frame_at(3380.0, 0.0, -10.0).origin), 70.0)
	await _shot("baleia", _at_track(3600.0, 0.0, 2.4, 0.0, 150.0))
	await _shot("tritoes", _at_track(3950.0, 0.0, 2.4, 0.0, 180.0))
	await _shot("ultima_curva", _at_track(4110.0, 0.0, 2.4, 0.0, 100.0))
	# Tubo de vidro por dentro e por fora, a superfície vista de baixo, vulcões, recife e montanhas
	await _shot("tubo", _at_track(3150.0, 0.0, 3.0, 0.0, 160.0, 0.0, 6.0), 75.0)
	await _shot("tubo_fora", _look(p.frame_at(3260.0, -75.0, 6.0).origin, p.frame_at(3300.0, 0.0, 6.0).origin), 70.0)
	var up := p.frame_at(300.0, 0.0, 2.0)
	await _shot("superficie", _look(up.origin, up.origin + Vector3(30.0, 60.0, 10.0)), 80.0)
	await _shot("superficie_alto", _look(p.frame_at(3350.0, -90.0, 12.0).origin, p.frame_at(3420.0, -40.0, 40.0).origin), 80.0)
	var vents: Array = track.find_child("Vents", true, false).get_meta("vents", [])
	if not vents.is_empty():
		var v: Vector3 = vents[0]
		await _shot("vulcao", _look(v + Vector3(55.0, 6.0, 40.0), v + Vector3(0.0, 12.0, 0.0)), 70.0)
	await _shot("recife", _look(p.frame_at(2880.0, 40.0, -2.0).origin, p.frame_at(2920.0, 70.0, -8.0).origin), 70.0)
	await _shot("montanhas", _look(p.frame_at(4000.0, 0.0, 8.0).origin, p.frame_at(4000.0, -600.0, 10.0).origin), 75.0)
	# O cânion: de dentro do tubo, a parede de perto, de cima e o espelho d'água olhando para cima
	await _shot("canion", _at_track(3700.0, 0.0, 2.6, 0.0, 140.0, 0.0, 5.0), 75.0)
	var wi := p.index_at(3930.0)
	var wall := SeaCanyon.face_at(track, canyon, wi, 1, p.points[wi].y + 6.0)
	await _shot("canion_parede", _look(p.frame_at(3900.0, 0.0, 4.0).origin, wall), 65.0)
	await _shot("canion_alto", _look(p.frame_at(3860.0, 40.0, water - 2.0 - p.points[p.index_at(3860.0)].y).origin,
		p.frame_at(3960.0, 0.0, 4.0).origin), 70.0)
	await _shot("canion_tunel", _at_track(1100.0, 0.0, 2.4, 0.0, 120.0, 0.0, 4.0), 75.0)
	# Cavernas nas paredes do cânion, vistas de dentro do tubo
	var caves: Array = track.find_child("Canyon", true, false).get_meta("caves", [])
	for k in mini(caves.size(), 2):
		var cave: Vector3 = caves[k * 3 % caves.size()]
		var cpr := p.project(cave, true, false)
		await _shot("caverna%d" % k, _look(p.frame_at(cpr.x - 22.0, -signf(cpr.y) * 2.0, 3.0).origin, cave), 60.0)
	if not caves.is_empty():
		var cave0: Vector3 = caves[0]
		var cpr0 := p.project(cave0, true, false)
		var to_road := p.points[p.index_at(cpr0.x)] - cave0
		to_road.y = 0.0
		await _shot("caverna_perto", _look(cave0 + to_road.normalized() * 7.0 + Vector3.UP * 0.6, cave0), 65.0)
	# Ruínas no cânion: pontes de aqueduto por cima do tubo e fachadas de templo nas paredes
	var ruins := track.find_child("CanyonRuins", true, false)
	var bridge_s: Array = ruins.get_meta("bridge_s", [])
	for k in mini(bridge_s.size(), 2):
		await _shot("ponte_canion%d" % k, _at_track(bridge_s[k] - 55.0, 0.0, 2.6, 0.0, 55.0, 0.0, 9.0), 72.0)
	var aq_at: Array = ruins.get_meta("aqueduct_at", [])
	for k in mini(aq_at.size(), 2):
		var aq: Vector3 = aq_at[k]
		var pr := p.project(aq, true, false)
		await _shot("aqueduto_submerso%d" % k, _look(p.frame_at(pr.x - 50.0, signf(pr.y) * 2.0, 4.0).origin, aq + Vector3.UP * 8.0), 70.0)
	var facades: Array = ruins.get_meta("facade_at", [])
	for k in mini(facades.size(), 2):
		var fa: Vector2 = facades[k]
		var fi2 := p.index_at(fa.x)
		var foot: float = canyon.foot[0 if fa.y > 0.0 else 1][fi2]
		await _shot("fachada%d" % k, _look(p.frame_at(fa.x - 28.0, -fa.y * 2.0, 4.0).origin,
			p.frame_at(fa.x, fa.y * (foot - 1.3), 0.0).origin + Vector3.UP * (float(canyon.floor[fi2]) + 7.0 - p.points[fi2].y)), 70.0)
	await _shot("jardim_corais", _at_track(2760.0, 0.0, 2.4, 0.0, 70.0, 6.0, 3.0), 75.0)
	var eye := p.frame_at(3760.0, 0.0, 3.0).origin
	await _shot("espelho", _look(eye, eye + p.tangents[p.index_at(3760.0)] * 50.0 + Vector3.UP * 34.0), 80.0)
	# Bichos no trecho aberto (o abismo e o anfiteatro)
	await _shot("animais", _look(p.frame_at(3240.0, 0.0, 6.0).origin, p.frame_at(3300.0, -90.0, 10.0).origin), 75.0)
	await _shot("animais_anfiteatro", _look(p.frame_at(4380.0, 0.0, 8.0).origin, p.frame_at(4440.0, 90.0, 12.0).origin), 75.0)
	# Vulcões perto do tubo (de dentro dele e de perto) e as relíquias dos trechos abertos
	var craters: Array = track.find_child("Vents", true, false).get_meta("vents", [])
	craters.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return absf(p.project(a, true, false).y) < absf(p.project(b, true, false).y))
	for k in mini(craters.size(), 2):
		var cr: Vector3 = craters[k]
		var vpr := p.project(cr, true, false)
		await _shot("vulcao_pista%d" % k, _look(p.frame_at(vpr.x - 50.0, signf(vpr.y) * 3.0, 3.0).origin, cr + Vector3.UP * 4.0), 70.0)
	if not craters.is_empty():
		var cr0: Vector3 = craters[0]
		await _shot("vulcao_perto", _look(cr0 + Vector3(26.0, 4.0, 20.0), cr0 + Vector3.UP * 2.0), 70.0)
	var relic_spots: Dictionary = track.find_child("Relics", true, false).get_meta("spots", {})
	for kind: String in ["wreck", "plaza", "arch", "statue", "amphorae", "pinnacles"]:
		var list: Array = relic_spots.get(kind, [])
		for k in mini(list.size(), 2):
			var at: Vector3 = list[k]
			var rpr := p.project(at, true, false)
			await _shot("reliquia_%s%d" % [kind, k], _look(p.frame_at(rpr.x - 35.0, signf(rpr.y) * 3.0, 4.0).origin, at + Vector3.UP * 3.0), 70.0)
	await _shot("estandartes_tubo", _at_track(3700.0, 0.0, 2.6, 0.0, 60.0, 4.0, 5.0), 75.0)
	for k in mini((relic_spots.get("wreck", []) as Array).size(), 2):
		var wr: Vector3 = relic_spots["wreck"][k]
		var wpr := p.project(wr, true, false)
		var away := wr - p.points[p.index_at(wpr.x)]
		away.y = 0.0
		await _shot("naufragio_perto%d" % k, _look(wr + away.normalized() * 30.0 + Vector3.UP * 9.0, wr + Vector3.UP * 2.0), 65.0)
	await _shot("aqueduto_pista_baixo", _look(p.frame_at(3330.0, -40.0, -12.0).origin, p.frame_at(3360.0, -16.0, -6.0).origin), 70.0)
	# As baleias grandes passando junto do tubo, vistas de dentro dele
	var whales := track.find_child("SeaLife", true, false).find_children("Whale*", "Node3D", true, false)
	whales.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.get_child(0).scale.x > b.get_child(0).scale.x)
	for k in mini(whales.size(), 3):
		var wh := whales[k] as Node3D
		var pr := p.project(wh.global_position, true, false)
		await _shot("baleia_perto%d" % k, _look(p.frame_at(pr.x - 45.0, signf(pr.y) * 3.0, 4.0).origin, wh.global_position), 70.0)
	# Um barco visto de baixo
	var boats := track.find_child("Boats", true, false) as Node3D
	if boats and boats.get_child_count() > 0:
		var b := boats.get_child(boats.get_child_count() - 1) as Node3D
		var bp := b.global_position
		await _shot("barco", _look(Vector3(bp.x + 18.0, water - 16.0, bp.z + 12.0), bp), 75.0)
	# Barreira de vidro de perto
	var bi := p.index_at(3800.0)
	var bf := p.frame_at(3790.0, p.half_width(bi, 1) - 1.0, 1.1)
	await _shot("barreira_vidro", _look(bf.origin, p.frame_at(3810.0, p.half_width(bi, 1) + 3.0, 0.9).origin), 60.0)
	# Do alto
	var bounds := p.bounds()
	var c := Vector3(bounds.get_center().x, 10.0, bounds.get_center().y)
	await _shot("alto_geral", _look(c + Vector3(900, 650, 900), c), 55.0)
	await _shot("alto_portao", _look(p.frame_at(2000.0, -260.0, 120.0).origin, p.frame_at(2100.0, 0.0, 10.0).origin), 60.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ACCOUNT))
	quit()
