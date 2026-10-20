extends SceneTree
## Galeria dos modelos e das peças do fundo do mar da Atlantis Abyss, para conferência visual (com
## janela, não entra na bateria de testes):
##   godot --path . -s res://tests/atlantis_models_gallery.gd -- <pasta de saída> [só,estas] --offline
## Gera a pista, esconde o cenário (ficam só o leito e a água) e, num lugar plano do leito longe do
## tubo, monta cada peça sozinha, com os materiais e a luz do jogo, e tira uma captura dela:
##  * os bichos (baleia, raia, tubarão, golfinho, tartaruga) e o polvo na coluna;
##  * os peixinhos das quatro espécies, os peixes-voadores e as águas-vivas;
##  * as estátuas (rosto das cachoeiras, Poseidon em pé e sentado, busto da deusa);
##  * cada tipo de coral e de vida presa do SeaReef;
##  * as relíquias (naufrágio, praça com o mosaico, templo redondo, fonte, estátua no pedestal, arco de
##    pedra, pináculos, estátuas tombadas e enterradas, campo de ânforas, âncora, baú, poça de vida);
##  * o vulcão de bolhas (o monte com as chaminés, as bolhas, a fumaça e o halo);
##  * as ruínas (coluna inteira e quebrada, lanterna, torre, prédio em ruínas, aqueduto).
## O 2º argumento (nomes separados por vírgula) captura só esses. As peças presas à pista (tubo, túnel,
## laje e arcos, cânion, pontes, fachadas, cavernas, portal, templo, tridente gigante) estão nas
## capturas da pista (atlantis_abyss_shots.gd).

var scene: Node3D
var track: RaceTrack
var cam: Camera3D
var out_dir := ""
var only: PackedStringArray = []
var stage: Node3D
## Lugar plano do leito (no chão), a direção em que a câmera olha e o lado.
var spot := Vector3.ZERO
var dir := Vector3(1.0, 0.0, 0.35).normalized()
var side := Vector3.ZERO
const PROFILE := "user://test_atlantis_gallery_profile.cfg"
const ACCOUNT := "user://test_atlantis_gallery_account.cfg"


func _initialize() -> void:
	var net := root.get_node_or_null("Net")
	if net:
		net.account_file = ACCOUNT
		net.server_host = "127.0.0.1"
		net.server_port = 9
	var args := Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool: return not a.begins_with("--"))
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	if args.size() > 1:
		only = String(args[1]).split(",", false)
	RaceSettings.time_of_day = 0
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


func _want(name: String) -> bool:
	return only.is_empty() or name in only


func _look(eye: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(at - eye), eye)


func _save(name: String) -> void:
	# (o HUD do modo de jogo aparece depois da pista pronta)
	var hud := scene.get_node_or_null("RaceHud") as CanvasLayer
	if hud:
		hud.visible = false
	for k in 25:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("galeria_%s.png" % name))
	print("captura: ", name)


## Captura olhando para `at` de `dist` m de distância (de 3/4: girada `turn` rad e um pouco de cima).
func _shot(name: String, at: Vector3, dist: float, rise := 0.3, fov := 50.0, turn := 0.35) -> void:
	var view := dir.rotated(Vector3.UP, turn)
	cam.global_transform = _look(at - view * dist + Vector3.UP * dist * rise, at)
	cam.fov = fov
	await _save(name)


## Esvazia o palco e os pontos do SeaReef registrados desde `mark`.
func _clear(mark := -1) -> void:
	for c in stage.get_children():
		c.queue_free()
	if mark >= 0:
		SeaReef._growth.resize(mark)
	await process_frame


## Desenha o que o SeaReef registrou desde `mark` (corais, algas e musgo presos às peças), como no jogo.
func _flush_growth(mark: int) -> void:
	var groups := {}
	for it: Array in SeaReef._growth.slice(mark):
		groups.get_or_add(it[0], []).append(it)
	for kind: int in groups:
		var list: Array = groups[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = SeaReef._mesh(kind)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][1])
			mm.set_instance_custom_data(i, list[i][2])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = SeaReef.material()
		stage.add_child(mmi)


## Esconde o cenário da pista (fica o leito e a água).
func _hide_scenery() -> void:
	var gen := track.get_node("Generated")
	for n: Node in track.get_children() + gen.get_children():
		if n is Node3D and not String(n.name) in ["Generated", "SeaFloor", "SeaWorld"]:
			(n as Node3D).visible = false


## Um lugar plano do leito, a 16–40 m de profundidade e longe da pista.
func _find_spot() -> Vector3:
	var p := track.path
	var water := track.layout.water_level
	var b := p.bounds().grow(500.0)
	var best := Vector3.INF
	var best_score := INF
	var x := b.position.x
	while x < b.end.x:
		var z := b.position.y
		while z < b.end.y:
			var g0 := SeaFloor.ground(track, x, z)
			var depth := water - g0
			var pr := p.project(Vector3(x, g0, z), false, false)
			if depth > 16.0 and depth < 40.0 and (pr.y == INF or absf(pr.y) > 160.0):
				var spread := 0.0
				for k in 12:
					var a := TAU * k / 12.0
					for r: float in [15.0, 35.0]:
						spread = maxf(spread, absf(SeaFloor.ground(track, x + cos(a) * r, z + sin(a) * r) - g0))
				var score := spread * 4.0 + absf(depth - 24.0)
				if spread < 2.0 and score < best_score:
					best_score = score
					best = Vector3(x, g0, z)
			z += 50.0
		x += 50.0
	return best


## Semente do rng em que o primeiro sorteio de SeaRelics._statue cai no modelo k.
func _statue_seed(k: int) -> int:
	for s in 500:
		var r := RandomNumberGenerator.new()
		r.seed = s
		if r.randi() % SeaRelics.STATUES.size() == k:
			return s
	return 0


## As partes de um pedaço das relíquias: pedra, madeira, brilho, estandartes, rocha.
func _parts() -> Array:
	return [MeshBuilder.new(), MeshBuilder.new(), MeshBuilder.new(), MeshBuilder.new(), MeshBuilder.new()]


func _run() -> void:
	while not track.is_built:
		await process_frame
	for n in ["HUD"]:
		var node := scene.get_node_or_null(n)
		if node:
			node.queue_free()
	var hud := scene.get_node_or_null("RaceHud") as CanvasLayer
	if hud:
		hud.visible = false
	cam = Camera3D.new()
	cam.far = 4000.0
	scene.add_child(cam)
	cam.current = true
	_hide_scenery()
	spot = _find_spot()
	print("palco: %s, %.0f m de profundidade" % [spot, track.layout.water_level - spot.y])
	side = dir.cross(Vector3.UP).normalized()
	stage = Node3D.new()
	stage.name = "Gallery"
	scene.add_child(stage)
	for k in 30:
		await process_frame
	var rng := RandomNumberGenerator.new()
	var mark := SeaReef._growth.size()
	# --- Bichos (na escala de jogo) ---------------------------------------------------------------
	for spec: Array in [["whale", 2.0, 8.0, 34.0], ["manta", 1.2, 3.0, 11.0], ["shark", 1.2, 2.5, 7.5], ["dolphin", 1.0, 2.0, 4.5],
			["turtle", 1.4, 1.5, 4.5]]:
		var name := "bicho_%s" % spec[0]
		if not _want(name):
			continue
		var holder := SeaLife.creature(stage, spec[0], spec[1], 0.0, true)
		var lift: float = spec[2]
		var at := spot + Vector3.UP * lift
		holder.global_transform = Transform3D(Basis.looking_at(side), at)
		await _shot(name, at, spec[3], 0.25, 50.0, 0.55)
		await _clear()
	if _want("polvo") or _want("polvo_cima"):
		# (como no jogo: a coluna de 1,4 m de raio e o polvo em escala 2,4 com o corpo 2 m acima do topo)
		var mb := MeshBuilder.new()
		AtlantisRuins.column(mb, spot, 14.0, 1.4, 0.0, AtlantisRuins.STONE, false)
		var col := MeshInstance3D.new()
		col.mesh = mb.commit(null, TrackMaterials.sea_stone("ruins", false, {}))
		stage.add_child(col)
		var octo := SeaLife.creature(stage, "octopus", 2.4, 0.0, true)
		octo.global_transform = Transform3D(Basis.looking_at(dir), spot + Vector3.UP * 12.0)
		if _want("polvo"):
			await _shot("polvo", spot + Vector3.UP * 10.0, 24.0, 0.15, 55.0, 0.2)
		if _want("polvo_cima"):
			await _shot("polvo_cima", spot + Vector3.UP * 11.0, 11.0, 0.9, 60.0, 0.2)
		await _clear(mark)
	# --- Peixes e águas-vivas ------------------------------------------------------------------------
	if _want("peixes"):
		var fish := MultiMesh.new()
		fish.transform_format = MultiMesh.TRANSFORM_3D
		fish.use_custom_data = true
		fish.mesh = SeaLife._fish_mesh()
		fish.instance_count = 4
		for k in 4:
			fish.set_instance_transform(k, Transform3D(Basis.looking_at(side).scaled(Vector3.ONE * 4.0), spot + Vector3.UP * (3.0 + k * 1.6)))
			fish.set_instance_custom_data(k, Color(0.0, 0.0, float(k) / 3.0, 0.0))
		var fmi := MultiMeshInstance3D.new()
		fmi.multimesh = fish
		fmi.material_override = SeaLife._fish_mat
		# (a caixa em volta do palco: os peixes se mexem no shader)
		fmi.custom_aabb = AABB(spot - Vector3.ONE * 50.0, Vector3.ONE * 100.0)
		stage.add_child(fmi)
		await _shot("peixes", spot + Vector3.UP * 5.4, 10.0, 0.05, 55.0, 0.0)
		await _clear()
	if _want("peixes_voadores"):
		# (parados: o salto do shader desligado)
		var ff := MultiMesh.new()
		ff.transform_format = MultiMesh.TRANSFORM_3D
		ff.use_custom_data = true
		ff.mesh = PoseidonGate.flying_fish_mesh()
		ff.instance_count = 3
		for k in 3:
			ff.set_instance_transform(k, Transform3D(Basis.looking_at(side).scaled(Vector3.ONE * 3.0), spot + Vector3.UP * (5.5 + k * 2.2)))
			ff.set_instance_custom_data(k, Color(0.2 * k, 0.5, 0.0, 0.0))
		var ffm := ShaderMaterial.new()
		ffm.shader = load("res://shaders/track/flying_fish.gdshader")
		# (comprimento quase zero, não zero: o shader divide por ele na inclinação do salto)
		ffm.set_shader_parameter("jump_length", 0.001)
		ffm.set_shader_parameter("jump_height", 0.0)
		var ffi := MultiMeshInstance3D.new()
		ffi.multimesh = ff
		ffi.material_override = ffm
		ffi.custom_aabb = AABB(spot - Vector3.ONE * 50.0, Vector3.ONE * 100.0)
		stage.add_child(ffi)
		await _shot("peixes_voadores", spot + Vector3.UP * 6.6, 9.0, 0.25, 55.0, 0.0)
		await _clear()
	if _want("aguas_vivas"):
		var jelly := MultiMesh.new()
		jelly.transform_format = MultiMesh.TRANSFORM_3D
		jelly.use_custom_data = true
		jelly.mesh = SeaLife._jelly_mesh()
		jelly.instance_count = 3
		for k in 3:
			jelly.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * 1.6), spot + Vector3.UP * 7.0 + side * (k - 1) * 3.4))
			jelly.set_instance_custom_data(k, Color(0.2 * k, k * 0.45, 0.0, 0.0))
		var jmi := MultiMeshInstance3D.new()
		jmi.multimesh = jelly
		jmi.material_override = SeaLife._jelly_mat
		jmi.custom_aabb = AABB(spot - Vector3.ONE * 50.0, Vector3.ONE * 100.0)
		stage.add_child(jmi)
		await _shot("aguas_vivas", spot + Vector3.UP * 6.0, 11.0, 0.05, 55.0, 0.0)
		await _clear()
	# --- Estátuas ------------------------------------------------------------------------------------
	for spec: Array in [["poseidon_face", 28.0], ["poseidon_standing", 15.0], ["poseidon_seated", 11.0], ["goddess_head", 7.8]]:
		var name := "estatua_%s" % spec[0]
		if not _want(name):
			continue
		var h: float = spec[1]
		AtlantisRuins.place_statues(stage, [[spec[0], Transform3D(Basis.looking_at(dir), spot)]])
		await _shot(name, spot + Vector3.UP * h * 0.5, h * 1.25, 0.12, 55.0, 0.25)
		await _clear()
	# --- Corais e vida presa: um tipo por vez --------------------------------------------------------
	for kind: int in SeaReef.Kind.values():
		var name := "coral_%s" % String(SeaReef.Kind.keys()[kind]).to_lower()
		if not _want(name):
			continue
		var basis := Basis.looking_at(dir)
		var xf := Transform3D(basis.scaled(Vector3.ONE * 2.0), spot)
		var focus := 0.8
		var dist := 4.5
		match kind:
			SeaReef.Kind.ROCK:
				xf = Transform3D(basis.scaled(Vector3(3.0, 2.2, 3.0)), spot)
				focus = 1.1
				dist = 9.0
			SeaReef.Kind.KELP:
				xf = Transform3D(basis.scaled(Vector3(1.6, 10.0, 1.6)), spot)
				focus = 5.0
				dist = 13.0
			SeaReef.Kind.STRAND:
				xf = Transform3D(basis.scaled(Vector3(1.4, 3.0, 1.4)), spot + Vector3.UP * 4.0)
				focus = 2.6
				dist = 5.0
			SeaReef.Kind.STAR, SeaReef.Kind.URCHIN:
				xf = Transform3D(basis.scaled(Vector3.ONE * 2.5), spot)
				focus = 0.25
				dist = 2.6
			SeaReef.Kind.GRASS, SeaReef.Kind.MOSS:
				focus = 0.4
				dist = 3.0
			SeaReef.Kind.CLAM, SeaReef.Kind.MANTLE, SeaReef.Kind.WORM, SeaReef.Kind.PLUME:
				focus = 0.7
				dist = 4.0
			SeaReef.Kind.FAN, SeaReef.Kind.WHIP, SeaReef.Kind.PILLAR, SeaReef.Kind.PLATE:
				focus = 1.1
				dist = 5.5
		# (pelo SeaReef.place: a cor de cada tipo como no jogo — verdes do kelp, do capim, do musgo e das
		# algas, cinzas das pedras; o marisco com o manto e o verme com a pluma)
		SeaReef.place(kind, xf, rng)
		var pair := -1
		match kind:
			SeaReef.Kind.CLAM:
				pair = SeaReef.Kind.MANTLE
			SeaReef.Kind.MANTLE:
				pair = SeaReef.Kind.CLAM
			SeaReef.Kind.WORM:
				pair = SeaReef.Kind.PLUME
			SeaReef.Kind.PLUME:
				pair = SeaReef.Kind.WORM
		if pair >= 0:
			SeaReef.place(pair, xf, rng)
		_flush_growth(mark)
		await _shot(name, spot + Vector3.UP * focus, dist, 0.3, 50.0, 0.3)
		await _clear(mark)
	# --- Relíquias -----------------------------------------------------------------------------------
	var statues: Array = []
	if _want("naufragio"):
		rng.seed = 11
		var parts := _parts()
		SeaRelics._wreck(parts, track, spot, rng)
		SeaRelics._commit(stage, Vector2i(9000, 0), parts)
		_flush_growth(mark)
		await _shot("naufragio", spot + Vector3.UP * 3.0, 40.0, 0.35, 55.0, 0.5)
		await _clear(mark)
	if _want("praca"):
		rng.seed = 21
		var parts := _parts()
		statues = []
		SeaRelics._plaza(parts, track, spot, 21.0, rng, statues)
		SeaRelics._commit(stage, Vector2i(9001, 0), parts)
		AtlantisRuins.place_statues(stage, statues)
		_flush_growth(mark)
		await _shot("praca", spot + Vector3.UP * 2.0, 34.0, 0.6, 55.0, 0.3)
		await _clear(mark)
	if _want("templo_redondo"):
		rng.seed = 3
		var parts := _parts()
		SeaRelics._tholos(parts[0], parts[2], spot + Vector3.UP * 0.2, rng)
		SeaRelics._commit(stage, Vector2i(9002, 0), parts)
		_flush_growth(mark)
		await _shot("templo_redondo", spot + Vector3.UP * 6.0, 24.0, 0.25, 55.0, 0.3)
		await _clear(mark)
	if _want("fonte"):
		rng.seed = 4
		var parts := _parts()
		statues = []
		SeaRelics._fountain(parts[0], spot + Vector3.UP * 0.2, rng, statues)
		SeaRelics._commit(stage, Vector2i(9003, 0), parts)
		AtlantisRuins.place_statues(stage, statues)
		_flush_growth(mark)
		await _shot("fonte", spot + Vector3.UP * 3.5, 13.0, 0.3, 55.0, 0.3)
		await _clear(mark)
	if _want("estatua_pedestal"):
		var parts := _parts()
		statues = []
		var basis := Basis.looking_at(dir)
		parts[0].box(Transform3D(basis, spot + Vector3.UP * 1.5), Vector3(5.5, 3.0, 5.5), AtlantisRuins.STONE_DARK)
		parts[0].box(Transform3D(basis, spot + Vector3.UP * 3.2), Vector3(6.2, 0.5, 6.2), AtlantisRuins.STONE)
		SeaRelics._place_statue(statues, "poseidon_seated", 9.0, Transform3D(basis, spot + Vector3.UP * 3.45))
		SeaRelics._commit(stage, Vector2i(9004, 0), parts)
		AtlantisRuins.place_statues(stage, statues)
		await _shot("estatua_pedestal", spot + Vector3.UP * 6.5, 18.0, 0.15, 55.0, 0.2)
		await _clear(mark)
	if _want("arco_pedra"):
		rng.seed = 5
		var parts := _parts()
		SeaRelics._rock_arch(parts[4], track, spot, rng)
		SeaRelics._commit(stage, Vector2i(9005, 0), parts)
		_flush_growth(mark)
		# (de dois lados a 90°: o vão segue a pista mais perto, então de um lado ele aparece de ponta)
		await _shot("arco_pedra", spot + Vector3.UP * 8.0, 34.0, 0.2, 55.0, 0.6)
		await _shot("arco_pedra_lado", spot + Vector3.UP * 8.0, 34.0, 0.2, 55.0, 0.6 + PI * 0.5)
		await _clear(mark)
	if _want("pinaculos"):
		rng.seed = 6
		var parts := _parts()
		SeaRelics._pinnacles(parts[4], track, spot, rng)
		SeaRelics._commit(stage, Vector2i(9006, 0), parts)
		_flush_growth(mark)
		await _shot("pinaculos", spot + Vector3.UP * 9.0, 30.0, 0.2, 55.0, 0.3)
		await _clear(mark)
	for spec: Array in [["estatua_tombada", 3], ["busto_enterrado", 0], ["rosto_enterrado", 1], ["sentado_enterrado", 2]]:
		if not _want(spec[0]):
			continue
		rng.seed = _statue_seed(spec[1])
		statues = []
		SeaRelics._statue(track, spot, rng, statues)
		AtlantisRuins.place_statues(stage, statues)
		_flush_growth(mark)
		await _shot(spec[0], spot + Vector3.UP * 3.0, 18.0, 0.3, 55.0, 0.3)
		await _clear(mark)
	if _want("anforas"):
		rng.seed = 8
		var parts := _parts()
		SeaRelics._amphorae(parts, track, spot, rng)
		SeaRelics._commit(stage, Vector2i(9008, 0), parts)
		_flush_growth(mark)
		await _shot("anforas", spot + Vector3.UP * 0.8, 13.0, 0.45, 55.0, 0.3)
		await _clear(mark)
	if _want("ancora"):
		rng.seed = 9
		var parts := _parts()
		SeaRelics._anchor(parts[1], spot, rng)
		SeaRelics._commit(stage, Vector2i(9009, 0), parts)
		await _shot("ancora", spot + Vector3.UP * 0.4, 5.5, 0.5, 55.0, 0.3)
		await _clear(mark)
	if _want("bau"):
		rng.seed = 10
		var parts := _parts()
		SeaRelics._chest(parts, spot, rng)
		SeaRelics._commit(stage, Vector2i(9010, 0), parts)
		await _shot("bau", spot + Vector3.UP * 0.5, 3.6, 0.45, 55.0, 0.3)
		await _clear(mark)
	if _want("poca_vida"):
		# (como a poça de vida junto do vidro: o marisco gigante, estrelas, ouriços e anêmonas)
		rng.seed = 12
		SeaReef.clam(Transform3D(Basis.looking_at(dir).scaled(Vector3.ONE * 1.5), spot), rng)
		for k in 6:
			var a := TAU * k / 6.0
			var at := spot + Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.2, 2.6)
			var kind := SeaReef.Kind.STAR if k % 2 == 0 else SeaReef.Kind.URCHIN
			SeaReef.place(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 1.3), at), rng)
		for k in 3:
			var a := TAU * k / 3.0 + 0.5
			var at := spot + Vector3(cos(a), 0, sin(a)) * 2.2
			var kind: int = [SeaReef.Kind.ANEMONE, SeaReef.Kind.PILLAR, SeaReef.Kind.SOFT][k]
			SeaReef.place(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 1.3), at), rng)
		_flush_growth(mark)
		await _shot("poca_vida", spot + Vector3.UP * 0.5, 6.5, 0.6, 55.0, 0.3)
		await _clear(mark)
	# --- Vulcão de bolhas ----------------------------------------------------------------------------
	if _want("vulcao") or _want("vulcao_chamine"):
		rng.seed = 13
		var mb := MeshBuilder.new()
		var glow := MeshBuilder.new()
		var tops := SeaVents._mound(mb, glow, spot + Vector3.DOWN * 0.8, 19.0, 14.0, rng)
		var crater := spot + Vector3.UP * (14.0 - 3.2)
		var water := track.layout.water_level
		SeaVents._column(track, stage, crater, water - crater.y, SeaVents.BUBBLES, SeaVents.CRATER * 0.4, 2.6, rng)
		stage.add_child(SeaVents._shimmer(crater + Vector3.UP * 0.5, 16.0))
		for top: Vector3 in tops:
			SeaVents._smoke(stage, top, rng)
			SeaVents._column(track, stage, top, water - top.y, 70, 0.35, 2.2, rng, false)
		stage.add_child(SeaVents._halo(crater + Vector3.UP * 3.5, SeaVents.CRATER * 3.4))
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.25)
		light.light_energy = 4.5
		light.omni_range = 46.0
		stage.add_child(light)
		light.global_position = crater + Vector3.UP * 3.0
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit(null, SeaVents._mound_mat)
		glow.commit(mi.mesh as ArrayMesh, SkyDeck.glow(0.0, 2.4, 5.0))
		stage.add_child(mi)
		_flush_growth(mark)
		if _want("vulcao"):
			await _shot("vulcao", spot + Vector3.UP * 8.0, 50.0, 0.2, 55.0, 0.3)
		if _want("vulcao_chamine") and not tops.is_empty():
			var out := tops[0] - spot
			out.y = 0.0
			cam.global_transform = _look(tops[0] + out.normalized() * 9.0 + Vector3.UP * 3.0, tops[0] + Vector3.DOWN * 2.0)
			cam.fov = 55.0
			await _save("vulcao_chamine")
		await _clear(mark)
	# --- Ruínas --------------------------------------------------------------------------------------
	if _want("colunas"):
		var mb := MeshBuilder.new()
		AtlantisRuins.column(mb, spot - side * 2.5, 12.0, 0.8, 0.0)
		AtlantisRuins.column(mb, spot + side * 2.5, 12.0, 0.8, 0.45)
		AtlantisRuins._commit(stage, "Columns", mb, MeshBuilder.new(), MeshBuilder.new(), true)
		_flush_growth(mark)
		await _shot("colunas", spot + Vector3.UP * 6.0, 16.0, 0.15, 55.0, 0.2)
		await _clear(mark)
	if _want("lanterna"):
		var mb := MeshBuilder.new()
		var lamps := MeshBuilder.new()
		mb.cylinder(Transform3D(Basis(), spot), 0.22, 0.16, 3.6, AtlantisRuins.STONE_DARK, 8)
		AtlantisRuins.lantern(mb, lamps, spot + Vector3.UP * 4.5)
		AtlantisRuins._commit(stage, "Lantern", mb, lamps, MeshBuilder.new(), true)
		await _shot("lanterna", spot + Vector3.UP * 4.3, 3.0, 0.15, 55.0, 0.3)
		await _clear(mark)
	if _want("torre"):
		rng.seed = 14
		var mb := MeshBuilder.new()
		var lamps := MeshBuilder.new()
		AtlantisRuins._tower(mb, lamps, spot, rng)
		AtlantisRuins._commit(stage, "Tower", mb, lamps, MeshBuilder.new(), true)
		_flush_growth(mark)
		await _shot("torre", spot + Vector3.UP * 14.0, 46.0, 0.15, 55.0, 0.3)
		await _clear(mark)
	if _want("predio"):
		rng.seed = 15
		var mb := MeshBuilder.new()
		var lamps := MeshBuilder.new()
		var banners := MeshBuilder.new()
		AtlantisRuins._ruined_building(mb, lamps, banners, spot, Basis.looking_at(dir), rng)
		AtlantisRuins._commit(stage, "Building", mb, lamps, banners, true)
		_flush_growth(mark)
		await _shot("predio", spot + Vector3.UP * 8.0, 46.0, 0.35, 55.0, 0.5)
		await _clear(mark)
	if _want("aqueduto"):
		rng.seed = 16
		var mb := MeshBuilder.new()
		var lamps := MeshBuilder.new()
		var banners := MeshBuilder.new()
		AtlantisRuins.aqueduct(mb, lamps, banners, spot - side * 45.0 + Vector3.DOWN * 2.0, spot + side * 45.0 + Vector3.DOWN * 2.0, 16.0, rng)
		AtlantisRuins._commit(stage, "Aqueduct", mb, lamps, banners, true)
		_flush_growth(mark)
		await _shot("aqueduto", spot + Vector3.UP * 12.0, 70.0, 0.15, 55.0, 0.15)
		await _clear(mark)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ACCOUNT))
	quit()
