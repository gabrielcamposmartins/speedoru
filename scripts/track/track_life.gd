class_name TrackLife
extends RefCounted
## Vida em volta da pista: pedestres andando (corredores atrás das barreiras e arquibancadas,
## paddock) e grupos parados conversando; mecânicos das equipes nas garagens; bandos de pássaros
## sobrevoando o parque. Todo caminho de pedestre é conferido ponto a ponto para nunca cruzar a
## pista, a pista dos boxes ou as barreiras.
## Pedestres: um MultiMesh animado inteiramente no shader (shaders/track/walker.gdshader).
## Pássaros: um MultiMesh por bando, movido pelo SceneryAnimator.

const WALK_QUAD := Vector2(0.8, 1.9)


static func build(track: RaceTrack, terrain: TrackTerrain, parent: Node3D, animator: SceneryAnimator) -> void:
	var root := Node3D.new()
	root.name = "Life"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = track.tree_seed + 991
	_walkers(track, terrain, rng, root)
	_garage_crews(track, rng, root)
	_birds(track, terrain, rng, root, animator)


# ---------------------------------------------------------------------------
# Pedestres
# ---------------------------------------------------------------------------
static func _walkers(track: RaceTrack, terrain: TrackTerrain, rng: RandomNumberGenerator, root: Node3D) -> void:
	var p := track.path
	var transforms: Array[Transform3D] = []
	var data: Array[Color] = []
	var add := func(pos: Vector3, dir: Vector3, length: float, count: int) -> void:
		for k in count:
			var jitter := Vector3(cos(TAU * k / count), 0.0, sin(TAU * k / count)) * 0.7
			if length > 0.0:
				jitter = Vector3(rng.randf_range(-0.8, 0.8), 0.0, rng.randf_range(-0.8, 0.8))
			var s := rng.randf_range(0.9, 1.08)
			var basis := Basis.looking_at(-dir).scaled(Vector3(s, s, s))
			transforms.append(Transform3D(basis, pos + jitter))
			data.append(Color(rng.randf(), length / 100.0, rng.randf() if rng.randf() > 0.25 else 0.0, rng.randf()))

	var flat := func(pos: Vector3) -> bool:
		return terrain.rise_at(pos.x, pos.z) < 0.15

	# Corredores atrás das barreiras e das arquibancadas
	var lay := track.layout
	for i in range(0, p.size(), 7):
		for side in [1, -1]:
			if rng.randf() > 0.55:
				continue
			var s := p.s_at(i)
			if lay.has_pit and side == lay.pit_side and track.pit_width[i] > 0.0:
				continue
			var off := track.outer_distance(i, side) + TrackProps._stand_clearance(track, s, side) + rng.randf_range(2.5, 7.0)
			var pos := track.edge_point(i, side, off)
			var dir := p.tangents[i]
			var length := rng.randf_range(12.0, 45.0)
			var k := absf(p.curvature[i])
			if k > 0.002:
				length = minf(length, 0.35 / k)
			if not (flat.call(pos) and flat.call(pos + dir * length * 0.5) and flat.call(pos - dir * length * 0.5)):
				continue
			if not _clear_path(track, pos - dir * length * 0.5, pos + dir * length * 0.5):
				continue
			if rng.randf() < 0.2:
				add.call(pos, dir, 0.0, rng.randi_range(2, 4))  # grupinho conversando
			else:
				add.call(pos, dir * (1.0 if rng.randf() < 0.5 else -1.0), length, rng.randi_range(1, 3))

	# Paddock (entre o prédio dos boxes e os motorhomes, e atrás deles)
	if lay.has_pit:
		var front := RaceTrack.PIT_WALL_STRIP + lay.pit_lane_width
		for k in 140:
			var s := lay.garage_center_s + rng.randf_range(-0.5, 0.5) * lay.pit_building_length
			var depth := rng.randf_range(PitComplex.DEPTH + 47.0, PitComplex.DEPTH + 70.0)
			if rng.randf() < 0.65:
				depth = rng.randf_range(PitComplex.DEPTH + 4.0, PitComplex.DEPTH + 33.0)
			var xf := PitComplex._module_frame(track, s, front)
			var pos := xf * Vector3(depth, 0.0, 0.0)
			# Só ao longo do paddock (paralelo aos boxes): nunca em direção à pista dos boxes
			var along := xf.basis.z.normalized()
			var length := rng.randf_range(8.0, 40.0)
			if not _clear_path(track, pos - along * length * 0.5, pos + along * length * 0.5):
				continue
			if rng.randf() < 0.25:
				add.call(pos, along, 0.0, rng.randi_range(2, 5))
			else:
				add.call(pos, along, length, 1)

	if transforms.is_empty():
		return
	var quad := QuadMesh.new()
	quad.size = WALK_QUAD
	quad.center_offset = Vector3(0, WALK_QUAD.y * 0.5, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = transforms.size()
	mm.buffer = Grandstands.pack_buffer(transforms, data)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/walker.gdshader")
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Walkers"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# As instâncias andam até ~25 m da posição base: AABB folgada (sem alcance de visibilidade:
	# ele mede até o centro da AABB, que aqui fica no meio do circuito)
	mmi.custom_aabb = AABB(Vector3(-20000, -10, -20000), Vector3(40000, 60, 40000))
	root.add_child(mmi)


## Caminho de a até b longe da pista: cada ponto (a cada 2 m) fora da faixa da pista + barreira
## (que, do lado dos boxes, inclui a pista dos boxes).
static func _clear_path(track: RaceTrack, a: Vector3, b: Vector3) -> bool:
	var p := track.path
	var steps := maxi(int(a.distance_to(b) / 2.0), 1)
	for k in steps + 1:
		var pt := a.lerp(b, float(k) / steps)
		var pr := p.project(pt, false)
		if pr.x < 0.0:
			continue
		var i := p.index_at(pr.x)
		var side := 1 if pr.y > 0.0 else -1
		if absf(pr.y) < p.half_width(i, side) + track.outer_distance(i, side) + 1.0:
			return false
	return true


# ---------------------------------------------------------------------------
# Mecânicos
# ---------------------------------------------------------------------------
## Mecânicos (macacão e capacete na cor da equipe) dentro de cada garagem.
static func _garage_crews(track: RaceTrack, rng: RandomNumberGenerator, root: Node3D) -> void:
	var lay := track.layout
	if not lay.has_pit:
		return
	var front := RaceTrack.PIT_WALL_STRIP + lay.pit_lane_width
	var transforms: Array[Transform3D] = []
	var data: Array[Color] = []
	var colors: Array[Color] = []
	for g in lay.garage_count:
		var xf := PitComplex._module_frame(track, track.garage_s(g), front)
		var team := lay.team_colors[(g / 2) % lay.team_colors.size()]
		for k in rng.randi_range(4, 6):
			var depth := rng.randf_range(3.0, PitComplex.DEPTH - 3.5)
			var z := rng.randf_range(-0.38, 0.38) * lay.garage_width
			var pos := xf * Vector3(depth, 0.0, z)
			var face := xf.basis.x.normalized() * -1.0 if rng.randf() < 0.6 else xf.basis.z.normalized() * (1.0 if rng.randf() < 0.5 else -1.0)
			face.y = 0.0
			transforms.append(Transform3D(Basis.looking_at(-face.normalized()), pos))
			data.append(Color(rng.randf(), -2.0 if rng.randf() < 0.45 else -1.0, rng.randf(), rng.randf()))
			colors.append(team)
	var node := _crew_multimesh(transforms, data, colors)
	node.name = "GarageCrews"
	root.add_child(node)


## Equipe de pit stop (usada pelo RaceManager): todos com a mesma cor.
static func crew_node(transforms: Array[Transform3D], data: Array[Color], team: Color) -> MultiMeshInstance3D:
	var colors: Array[Color] = []
	for k in transforms.size():
		colors.append(team)
	return _crew_multimesh(transforms, data, colors)


static func _crew_multimesh(transforms: Array[Transform3D], data: Array[Color], colors: Array[Color]) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = WALK_QUAD
	quad.center_offset = Vector3(0, WALK_QUAD.y * 0.5, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = transforms.size()
	for k in transforms.size():
		mm.set_instance_transform(k, transforms[k])
		mm.set_instance_custom_data(k, data[k])
		mm.set_instance_color(k, colors[k])
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/walker.gdshader")
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-20000, -10, -20000), Vector3(40000, 60, 40000))
	return mmi


# ---------------------------------------------------------------------------
# Pássaros
# ---------------------------------------------------------------------------
static func _birds(track: RaceTrack, terrain: TrackTerrain, rng: RandomNumberGenerator, root: Node3D,
		animator: SceneryAnimator) -> void:
	var mesh := _bird_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/bird.gdshader")
	var p := track.path
	for f in 10:
		var count := rng.randi_range(6, 26)
		var gulls := rng.randf() < 0.35
		var v_shape := rng.randf() < 0.4
		var transforms: Array[Transform3D] = []
		var data: Array[Color] = []
		for k in count:
			var offset := Vector3.ZERO
			if v_shape:
				var row := (k + 1) / 2
				var side := 1.0 if k % 2 == 0 else -1.0
				offset = Vector3(side * row * 2.2, rng.randf_range(-0.3, 0.3), -row * 1.8)
			else:
				offset = Vector3(rng.randf_range(-9, 9), rng.randf_range(-3, 3), rng.randf_range(-9, 9))
			var s := rng.randf_range(0.8, 1.2) * (1.6 if gulls else 1.0)
			transforms.append(Transform3D(Basis().scaled(Vector3(s, s, s)), offset))
			data.append(Color(rng.randf(), rng.randf(), 0.9 if gulls else rng.randf_range(0.0, 0.25), 0.0))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = count
		mm.buffer = Grandstands.pack_buffer(transforms, data)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Flock%d" % f
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		# Cada bando dá voltas em volta de um trecho da pista, alguns bem baixos
		var anchor := p.position_at(rng.randf() * p.length)
		var height := rng.randf_range(14.0, 30.0) if f < 5 else rng.randf_range(35.0, 90.0)
		var radii := Vector2(rng.randf_range(80.0, 320.0), rng.randf_range(60.0, 260.0))
		animator.add_flock(mmi, Vector3(anchor.x, height, anchor.z), radii, rng.randf_range(9.0, 15.0), rng.randf() * TAU)


## Pássaro de ~1 m de envergadura: corpo em losango e duas asas (COLOR.r = 1 nas pontas).
static func _bird_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var body := Color(0, 1, 1)
	mb.tri(Vector3(0, 0, 0.35), Vector3(0.07, 0, 0), Vector3(0, 0.05, -0.3), body, Vector3.UP)
	mb.tri(Vector3(0, 0, 0.35), Vector3(-0.07, 0, 0), Vector3(0, 0.05, -0.3), body, Vector3.UP)
	mb.tri(Vector3(0, 0, -0.3), Vector3(0.12, 0, -0.42), Vector3(-0.12, 0, -0.42), body, Vector3.UP)
	for side in [1.0, -1.0]:
		var root_f := Vector3(side * 0.05, 0, 0.12)
		var root_b := Vector3(side * 0.05, 0, -0.08)
		var mid := Vector3(side * 0.28, 0.03, 0.02)
		var tip := Vector3(side * 0.55, 0, -0.12)
		var inner := Color(0.0, 1, 1)
		var outer := Color(1.0, 1, 1)
		var mid_c := Color(0.5, 1, 1)
		var start := mb.verts.size()
		mb.tri(root_f, mid, root_b, inner, Vector3.UP)
		mb.tri(mid, tip, root_b, mid_c, Vector3.UP)
		# Cor por vértice: quanto mais longe do corpo, mais a ponta mexe
		for v in range(start, mb.verts.size()):
			var t := clampf(absf(mb.verts[v].x) / 0.55, 0.0, 1.0)
			mb.colors[v] = Color(t, 1, 1)
	return mb.commit()
