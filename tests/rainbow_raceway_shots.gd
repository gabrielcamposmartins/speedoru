extends SceneTree
## Capturas de tela da Rainbow Raceway para conferência visual (com janela, não entra na bateria de
## testes):
##   godot --path . -s res://tests/rainbow_raceway_shots.gd -- <pasta de saída> [horário] [prefixo] [só,estes] --offline
## Gera a pista e salva PNGs de vários pontos de vista: o grid e o Arco do Coração, a reta, as curvas,
## a subida, o castelo, o grampo, o Túnel do Arco-Íris, o Mirante e a Ponte do Arco-Íris (o
## cruzamento visto de cima e de baixo), a espiral em volta da Torre de Algodão-Doce, as cachoeiras,
## a chicane, os ursinhos, a barreira, o chão e a base de nuvem de perto, o letreiro, cada ilha com
## nome, o mirante, as caixas de presente, um grupinho de pelúcias, um balão de ar quente e vistas do
## alto.
## O 4º argumento (nomes separados por vírgula) captura só esses.

var scene: Node3D
var track: RaceTrack
var cam: Camera3D
var out_dir := ""
var prefix := "rr"
var only: PackedStringArray = []
const PROFILE := "user://test_rainbow_shots_profile.cfg"
const ACCOUNT := "user://test_rainbow_shots_account.cfg"


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
	prefix = args[2] if args.size() > 2 and not args[2].begins_with("--") else "rr"
	if args.size() > 3:
		only = args[3].split(",", false)
	RaceSettings.track = "rainbow_raceway"
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = PROFILE
		profile.reset_profile()
	scene = (load("res://scenes/tracks/rainbow_raceway.tscn") as PackedScene).instantiate()
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


func _shot(shot_name: String, xf: Transform3D, fov := 70.0) -> void:
	if not only.is_empty() and not shot_name in only:
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
	img.save_png(out_dir.path_join("%s_%s.png" % [prefix, shot_name]))
	print("captura: ", shot_name)


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
	var mid := p.bounds().get_center()
	var center := Vector3(mid.x, 0.0, mid.y)
	await _shot("grid", _at_track(-60.0, 0.0, 2.6, 0.0, 60.0))
	await _shot("arco", _at_track(-45.0, 2.0, 2.4, 0.0, 57.0, 0.0, 7.0), 72.0)
	await _shot("reta", _at_track(140.0, 0.0, 2.6, 0.0, 160.0))
	await _shot("reta_lado", _look(p.frame_at(-120.0, -30.0, 9.0).origin, p.frame_at(-40.0, 12.0, 4.0).origin), 70.0)
	await _shot("curva_ursinho", _at_track(330.0, 0.0, 2.6, 0.0, 90.0))
	await _shot("subida", _at_track(500.0, 0.0, 2.6, 0.0, 180.0, 0.0, 6.0))
	await _shot("esse", _at_track(760.0, 0.0, 2.6, 0.0, 150.0))
	await _shot("reta_castelo", _at_track(1000.0, 0.0, 2.6, 0.0, 170.0, 0.0, 6.0))
	await _shot("grampo", _at_track(1150.0, 0.0, 2.6, 0.0, 60.0))
	await _shot("ponte_levadica", _at_track(1290.0, 0.0, 2.6, 0.0, 120.0))
	await _shot("curva_torre", _at_track(1400.0, 0.0, 2.6, 0.0, 110.0))
	await _shot("tunel_entrada", _at_track(track.layout.tunnel.x - 80.0, 0.0, 3.0, 0.0, 80.0, 0.0, 4.0), 65.0)
	await _shot("tunel", _at_track((track.layout.tunnel.x + track.layout.tunnel.y) * 0.5, 0.0, 2.4, 0.0, 70.0), 75.0)
	await _shot("esse_bolhas", _at_track(1990.0, 0.0, 2.6, 0.0, 160.0))
	if not p.crossings.is_empty():
		var c := p.crossings[0]
		await _shot("mirante", _at_track(c.y - 120.0, 0.0, 2.6, 0.0, 160.0))
		await _shot("ponte", _at_track(c.x - 90.0, 0.0, 2.4, 0.0, 90.0, 0.0, 10.0), 72.0)
		await _shot("ponte_lado", _look(p.position_at(c.x) + Vector3(70.0, 12.0, 60.0), p.position_at(c.x) + Vector3.UP * 10.0), 70.0)
	await _shot("espiral", _at_track(2420.0, 0.0, 2.6, 0.0, 110.0))
	await _shot("espiral_alto", _look(p.position_at(2530.0) + Vector3(0.0, 160.0, 0.0) + (p.position_at(2530.0) - center).normalized() * 160.0,
		p.position_at(2530.0)), 70.0)
	await _shot("pirulito", _at_track(2940.0, 0.0, 2.6, 0.0, 90.0))
	await _shot("cachoeiras", _at_track(3080.0, 0.0, 2.6, 0.0, 120.0))
	await _shot("chicane", _at_track(3120.0, 0.0, 2.6, 0.0, 70.0))
	await _shot("coracao", _at_track(3420.0, 0.0, 2.6, 0.0, 160.0))
	await _shot("ursinhos", _at_track(3600.0, 0.0, 2.6, 0.0, 140.0))
	await _shot("chao", _look(p.frame_at(190.0, 0.0, 9.0).origin, p.frame_at(196.0, 0.0, 0.0).origin), 60.0)
	await _shot("barreira_perto", _look(p.frame_at(200.0, -3.0, 1.4).origin, p.frame_at(212.0, -9.5, 0.8).origin), 60.0)
	await _shot("base_nuvem", _look(p.frame_at(600.0, 45.0, -4.0).origin, p.frame_at(640.0, 0.0, 0.0).origin), 65.0)
	var gen := track.get_node("Generated")
	var props := gen.get_node_or_null("CloudProps")
	if props and props.has_meta("title"):
		var t: Vector3 = props.get_meta("title")
		await _shot("titulo", _look(p.frame_at(-60.0, 0.0, 2.6).origin, t), 60.0)
		await _shot("titulo_perto", _look(p.frame_at(100.0, 0.0, 6.0).origin, t), 60.0)
	for id: String in ["castle", "bear_corner", "bears", "falls", "heart", "sweets", "tower"]:
		var lm := CloudIslands.landmark(track, id)
		var pos: Vector3 = lm.pos
		var r: float = lm.radius
		var pr := p.project(pos, true, false)
		var q := p.position_at(pr.x)
		var dir := (pos - q)
		dir.y = 0.0
		dir = dir.normalized()
		var eye := q + Vector3.UP * (12.0 + r * 0.25) - dir * 10.0
		await _shot("ilha_" + id, _look(eye, pos + Vector3.UP * r * 0.3), 60.0)
	if props:
		var m: Vector3 = props.get_meta("mirante", Vector3.ZERO)
		await _shot("mirante_perto", _look(m + (m - p.position_at(CloudProps.MIRANTE_S)).normalized() * -14.0 + Vector3.UP * 3.0,
			m + Vector3.UP * 1.0), 65.0)
	await _shot("presentes", _at_track(CloudProps.GIFTS[0] - 40.0, 0.0, 2.6, 0.0, 40.0, 0.0, 5.0), 70.0)
	var plush := gen.get_node_or_null("PlushFriends")
	if plush:
		for mmi: MultiMeshInstance3D in plush.find_children("Trackside_*", "MultiMeshInstance3D", false, false):
			if mmi.multimesh.instance_count > 0:
				var at := mmi.multimesh.get_instance_transform(0).origin
				var pr2 := p.project(at, true, false)
				await _shot("pelucias", _look(p.frame_at(pr2.x - 12.0, 0.0, 2.2).origin, at + Vector3.UP * 1.0), 55.0)
				break
	var balloons := gen.get_node_or_null("CloudWorld/HotAirBalloons")
	if balloons and balloons.get_child_count() > 0:
		var bpos := (balloons.get_child(0) as Node3D).global_position
		var pr3 := p.project(bpos, true, false)
		await _shot("balao", _look(p.frame_at(pr3.x, 0.0, 4.0).origin, bpos + Vector3.UP * 12.0), 50.0)
	await _shot("alto", _look(center + Vector3(-300.0, 900.0, 1100.0), center), 65.0)
	await _shot("alto2", _look(center + Vector3(900.0, 380.0, -700.0), center + Vector3(-200.0, 0.0, 100.0)), 70.0)
	print("capturas prontas")
	for f in [PROFILE, ACCOUNT]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	quit(0)
