class_name TrackLeaves
extends Node3D
## Árvores folhosas perto da pista e folhas soltas:
##  * árvores com copas de centenas de folhas individuais (dupla face, tremulando), plantadas logo
##    atrás das barreiras (mais perto da pista que o resto do parque);
##  * folhas caindo dessas árvores (GPUParticles3D com os pontos de emissão nas copas, vento e
##    turbulência) — pétalas no ambiente sakura;
##  * folhas espalhadas no chão em volta das árvores e na pista (MultiMesh), em quantidade que
##    depende do ambiente (outono: algumas na pista; sakura: algumas na pista e muitas no chão).
## A cor vem da paleta global do ambiente (shaders/track/leaf.gdshader). apply_mood() ajusta tudo.

const TRUNK := Color(0.45, 0.3, 0.2)
const LEAF := Color(0.3, 0.62, 0.27)
const LOD_DISTANCE := 260.0

## Densidade por ambiente: [folhas caindo, folhas na pista, folhas no chão]
const DENSITY := {
	DaylightPresets.Biome.SUMMER: [0.35, 0.0, 0.08],
	DaylightPresets.Biome.AUTUMN: [1.0, 0.45, 0.7],
	DaylightPresets.Biome.SAKURA: [1.0, 0.4, 1.0],
	DaylightPresets.Biome.FANTASY: [0.6, 0.12, 0.35],
}

var tree_positions := PackedVector3Array()
var _falling: GPUParticles3D
var _track_litter: MultiMeshInstance3D
var _ground_litter: MultiMeshInstance3D
var _litter_material_ground: ShaderMaterial


static func build(track: RaceTrack, terrain: TrackTerrain, parent: Node3D) -> TrackLeaves:
	var node := TrackLeaves.new()
	node.name = "Leaves"
	parent.add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = track.tree_seed + 4242
	node._place_trees(track, terrain, rng)
	node._build_falling(rng)
	node._build_litter(track, terrain, rng)
	return node


## Ajusta a quantidade de folhas para o ambiente.
func apply_mood(_time_of_day: int, biome: int) -> void:
	var d: Array = DENSITY.get(biome, DENSITY[DaylightPresets.Biome.SUMMER])
	if _falling:
		_falling.amount_ratio = d[0]
	if _track_litter:
		_track_litter.multimesh.visible_instance_count = int(_track_litter.multimesh.instance_count * float(d[1]))
	if _ground_litter:
		_ground_litter.multimesh.visible_instance_count = int(_ground_litter.multimesh.instance_count * float(d[2]))
	if _litter_material_ground:
		_litter_material_ground.set_shader_parameter("ground_darken", 0.5 if biome == DaylightPresets.Biome.AUTUMN else 0.15)


# ---------------------------------------------------------------------------
# Árvores
# ---------------------------------------------------------------------------
func _place_trees(track: RaceTrack, terrain: TrackTerrain, rng: RandomNumberGenerator) -> void:
	var p := track.path
	var lay := track.layout
	var chunks := {}  # Vector2i -> [transforms, dados] (blocos para o LOD funcionar por distância)
	for i in range(0, p.size(), 9):
		for side in [1, -1]:
			if rng.randf() < 0.4:
				continue
			if lay.has_pit and side == lay.pit_side and track.pit_width[i] > 0.0:
				continue
			var s := p.s_at(i)
			var d := track.outer_distance(i, side) + TrackProps._stand_clearance(track, s, side) + rng.randf_range(3.5, 6.0)
			var pos := track.edge_point(i, side, d)
			if terrain.height_at(pos.x, pos.z) > 0.3:
				continue
			var blocked := false
			for poly in track.footprints:
				if Geometry2D.is_point_in_polygon(Vector2(pos.x, pos.z), poly):
					blocked = true
					break
			if blocked:
				continue
			var scale := rng.randf_range(0.9, 1.3)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale * rng.randf_range(0.92, 1.1), scale))
			var key := Vector2i(floori(pos.x / TrackTrees.CHUNK), floori(pos.z / TrackTrees.CHUNK))
			if not chunks.has(key):
				chunks[key] = [[] as Array[Transform3D], [] as Array[Color]]
			chunks[key][0].append(Transform3D(basis, pos - Vector3.UP * 0.05))
			chunks[key][1].append(Color(rng.randf(), rng.randf(), rng.randf(), TrackTerrain.dark_zone(pos.x, pos.z) * 0.6))
			tree_positions.append(pos + Vector3.UP * 4.8 * scale)
	if chunks.is_empty():
		return
	var near_mat := ShaderMaterial.new()
	near_mat.shader = load("res://shaders/track/tree_leafy.gdshader")
	var meshes := [_leafy_mesh(true), _leafy_mesh(false)]
	for key in chunks:
		var transforms: Array[Transform3D] = chunks[key][0]
		var buffer := Grandstands.pack_buffer(transforms, chunks[key][1])
		for lod in 2:
			_add_lod(key, lod, transforms.size(), buffer, meshes[lod], near_mat)


func _add_lod(key: Vector2i, lod: int, count: int, buffer: PackedFloat32Array, mesh: ArrayMesh, near_mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.buffer = buffer
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LeafyTrees_%d_%d%s" % [key.x, key.y, "" if lod == 0 else "_far"]
	mmi.multimesh = mm
	mmi.material_override = near_mat if lod == 0 else TrackMaterials.tree()
	if lod == 0:
		mmi.visibility_range_end = LOD_DISTANCE
		mmi.visibility_range_end_margin = 20.0
	else:
		mmi.visibility_range_begin = LOD_DISTANCE
		mmi.visibility_range_begin_margin = 20.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Tufo de folhas: miolo escuro (a copa não fica transparente entre as folhas) e folhas em losango
## deitadas na superfície de um elipsoide (como escamas, levemente erguidas), com caimento aleatório.
## `leaf_len` = comprimento da folha; `density` = folhas por m² de superfície.
static func leaf_clump(mb: MeshBuilder, center: Vector3, radii: Vector3, color: Color, rng: RandomNumberGenerator,
		leaf_len := 0.34, density := 6.0) -> void:
	mb.blob(center, radii * 0.84, color.darkened(0.3), 7, 5)
	# Área aproximada do elipsoide
	var area := 4.0 * PI * pow((pow(radii.x * radii.y, 1.6) + pow(radii.x * radii.z, 1.6) + pow(radii.y * radii.z, 1.6)) / 3.0, 1.0 / 1.6)
	var count := int(area * density)
	for n in count:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var pos := center + d * radii * rng.randf_range(0.86, 1.04)
		var outward := (d / radii).normalized()
		var normal := (outward + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.1, 0.4), rng.randf_range(-0.3, 0.3))).normalized()
		var t := normal.cross(Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT).normalized()
		t = t.rotated(normal, rng.randf() * TAU)
		var b := normal.cross(t)
		var length := leaf_len * rng.randf_range(0.82, 1.18)
		var width := length * 0.55
		var tip := pos + t * length * 0.5
		var back := pos - t * length * 0.5
		var l := pos + b * width * 0.5
		var rr := pos - b * width * 0.5
		var col := color.lightened(rng.randf_range(-0.12, 0.15))
		mb.tri_smooth(back, l, tip, outward, outward, outward, col)
		mb.tri_smooth(back, tip, rr, outward, outward, outward, col)


static var _city := {}


## Árvores da cidade de Mônaco (perto), com copas de folhas soltas como as folhosas de Monza, por
## espécie de TrackTrees: carvalho e bétula (copa redonda), arbusto (sem tronco), cipreste italiano
## (coluna fina em chama), pinheiro (camadas em cone) e pinheiro-manso (copa em guarda-chuva sobre
## o tronco inclinado). As coníferas usam verde-azulado (o shader as reconhece pela cor).
static func city_tree_mesh(species: int) -> ArrayMesh:
	if _city.has(species):
		return _city[species]
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + species
	var mb := MeshBuilder.new()
	var conifer := Color(0.1, 0.27, 0.2)
	match species:
		TrackTrees.Species.CYPRESS:
			# Coluna em chama: tufos altos bem sobrepostos (silhueta contínua) afinando até a ponta
			mb.cylinder(Transform3D(), 0.2, 0.14, 1.6, TRUNK, 6, false)
			for k in 6:
				var t := float(k) / 5.0
				var r := lerpf(1.05, 0.34, pow(t, 1.4))
				leaf_clump(mb, Vector3(rng.randf_range(-0.04, 0.04), 2.6 + t * 7.2, rng.randf_range(-0.04, 0.04)),
					Vector3(r, 1.9 - t * 0.5, r), conifer.lightened(t * 0.05), rng, 0.3, 10.0)
		TrackTrees.Species.PINE:
			mb.cylinder(Transform3D(), 0.3, 0.16, 3.2, TRUNK, 6, false)
			for k in 5:
				var t := float(k) / 4.0
				var r := lerpf(2.6, 0.7, t)
				leaf_clump(mb, Vector3(0, 2.4 + t * 6.4, 0), Vector3(r, lerpf(0.9, 0.8, t), r), conifer.lightened(t * 0.05), rng, 0.26, 6.5)
		TrackTrees.Species.STONE_PINE:
			# Tronco inclinado que se abre em três galhos; copa larga e chata (guarda-chuva)
			mb.cylinder(Transform3D(Basis(Vector3.FORWARD, 0.12)), 0.34, 0.24, 5.0, TRUNK, 7, false)
			var top := Vector3(-0.6, 4.95, 0.0)
			for k in 3:
				var dir := Vector3(cos(k * 2.1 + 0.5), 0.0, sin(k * 2.1 + 0.5))
				mb.cylinder(Transform3D(Basis(dir.cross(Vector3.UP).normalized(), deg_to_rad(38.0)), top), 0.16, 0.08, 2.8, TRUNK, 5, false)
			var canopy := Color(0.2, 0.42, 0.32)
			for k in 6:
				var a := TAU * k / 6.0 + 0.3
				leaf_clump(mb, top + Vector3(cos(a) * 2.2, 2.6 + rng.randf_range(-0.2, 0.3), sin(a) * 2.2),
					Vector3(2.0, 0.85, 2.0), canopy.lightened(rng.randf_range(-0.03, 0.05)), rng, 0.3, 4.5)
			leaf_clump(mb, top + Vector3(0, 3.1, 0), Vector3(2.3, 0.9, 2.3), canopy.lightened(0.05), rng, 0.3, 4.5)
		TrackTrees.Species.BUSH:
			var bush := Color(0.3, 0.56, 0.26)
			for k in 4:
				var a := TAU * k / 4.0 + 0.3
				leaf_clump(mb, Vector3(cos(a) * 0.65, 0.75, sin(a) * 0.65), Vector3(0.9, 0.75, 0.9),
					bush.lightened(rng.randf_range(-0.04, 0.06)), rng, 0.24, 8.0)
			leaf_clump(mb, Vector3(0, 1.2, 0), Vector3(0.85, 0.75, 0.85), bush.lightened(0.06), rng, 0.24, 8.0)
		TrackTrees.Species.BIRCH:
			var y := 0.0
			for k in 6:
				var mark := Color(0.95, 0.94, 0.9) if k % 2 == 0 else Color(0.25, 0.24, 0.24)
				var hgt := 1.1 if k % 2 == 0 else 0.18
				mb.cylinder(Transform3D(Basis(), Vector3.UP * y), 0.17 - y * 0.012, 0.17 - (y + hgt) * 0.012, hgt, mark, 7, false)
				y += hgt
			var light := Color(0.42, 0.66, 0.28)
			for c in [[Vector3(0.2, 5.4, 0.1), Vector3(1.6, 1.9, 1.6)], [Vector3(-0.8, 4.4, -0.4), Vector3(1.1, 1.2, 1.1)],
					[Vector3(0.7, 4.0, 0.7), Vector3(1.0, 1.1, 1.0)]]:
				leaf_clump(mb, c[0], c[1], light, rng, 0.3, 7.0)
		_:
			_city[species] = _leafy_mesh(true)
			return _city[species]
	_city[species] = mb.commit()
	return _city[species]


static var _leafy_material: ShaderMaterial


## Material das árvores folhosas (folhas soltas dupla face, vento, cor do ambiente).
static func leafy_material() -> ShaderMaterial:
	if _leafy_material == null:
		_leafy_material = ShaderMaterial.new()
		_leafy_material.shader = load("res://shaders/track/tree_leafy.gdshader")
	return _leafy_material


## Copa de folhas soltas (perto) ou bolhas simples (longe).
static func _leafy_mesh(detailed: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var mb := MeshBuilder.new()
	mb.cylinder(Transform3D(), 0.3, 0.2, 3.4, TRUNK, 7 if detailed else 4, false)
	var clumps := [[Vector3(0, 4.7, 0), 2.1], [Vector3(1.4, 4.1, 0.5), 1.5], [Vector3(-1.3, 4.3, -0.6), 1.55],
		[Vector3(0.2, 5.9, 0.1), 1.4], [Vector3(-0.4, 3.9, 1.3), 1.3], [Vector3(0.6, 4.2, -1.3), 1.25]]
	if not detailed:
		mb.blob(Vector3(0, 4.8, 0), Vector3(2.8, 2.4, 2.8), LEAF, 6, 4, 0.3)
		return mb.commit()
	for k in 3:
		var dir := Vector3(cos(k * 2.1 + 0.3), 0.0, sin(k * 2.1 + 0.3))
		var xf := Transform3D(Basis(dir.cross(Vector3.UP).normalized(), deg_to_rad(45.0)), Vector3.UP * 2.8)
		mb.cylinder(xf, 0.12, 0.05, 2.0, TRUNK, 5, false)
	for clump in clumps:
		var center: Vector3 = clump[0]
		var r: float = clump[1]
		# Miolo escuro (a copa não fica transparente entre as folhas)
		mb.blob(center, Vector3.ONE * r * 0.72, LEAF.darkened(0.35), 7, 5)
		var count := int(85.0 * r)
		for n in count:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
			var pos := center + d * r * rng.randf_range(0.72, 1.05)
			# Folha: losango 0.34 x 0.2 m virado mais ou menos para fora, com caimento aleatório
			var normal := (d + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.3, 0.6), rng.randf_range(-0.5, 0.5))).normalized()
			var t := normal.cross(Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT).normalized()
			t = t.rotated(normal, rng.randf() * TAU)
			var b := normal.cross(t)
			var length := rng.randf_range(0.28, 0.4)
			var width := length * 0.55
			var tip := pos + t * length * 0.5
			var back := pos - t * length * 0.5
			var l := pos + b * width * 0.5
			var rr := pos - b * width * 0.5
			var col := LEAF.lightened(rng.randf_range(-0.12, 0.15))
			mb.tri_smooth(back, l, tip, d, d, d, col)
			mb.tri_smooth(back, tip, rr, d, d, d, col)
	return mb.commit()


# ---------------------------------------------------------------------------
# Folhas caindo
# ---------------------------------------------------------------------------
func _build_falling(rng: RandomNumberGenerator) -> void:
	if tree_positions.is_empty():
		return
	var count := tree_positions.size() * 6
	var img := Image.create(count, 1, false, Image.FORMAT_RGBF)
	for k in count:
		var c := tree_positions[k % tree_positions.size()]
		var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.8), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.5, 2.2)
		var p := c + off
		img.set_pixel(k, 0, Color(p.x, p.y, p.z))
	var points := ImageTexture.create_from_image(img)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	process.emission_point_texture = points
	process.emission_point_count = count
	process.direction = Vector3(0, -1, 0)
	process.spread = 70.0
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.7
	process.gravity = Vector3(0.7, -0.75, 0.5)
	process.damping_min = 0.2
	process.damping_max = 0.6
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.4
	process.turbulence_noise_scale = 3.5
	process.turbulence_influence_min = 0.08
	process.turbulence_influence_max = 0.18
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -220.0
	process.angular_velocity_max = 220.0
	process.particle_flag_rotate_y = true
	process.scale_min = 0.8
	process.scale_max = 1.35
	var ramp := Gradient.new()
	ramp.set_color(0, Color.BLACK)
	ramp.set_color(1, Color.WHITE)
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	process.color_initial_ramp = ramp_tex
	_falling = GPUParticles3D.new()
	_falling.name = "FallingLeaves"
	_falling.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.22)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/leaf.gdshader")
	quad.material = mat
	_falling.draw_pass_1 = quad
	_falling.amount = clampi(tree_positions.size() * 5, 200, 3000)
	_falling.lifetime = 7.0
	_falling.preprocess = 7.0
	_falling.randomness = 0.5
	_falling.local_coords = false
	_falling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_falling.visibility_aabb = AABB(Vector3(-20000, -50, -20000), Vector3(40000, 200, 40000))
	add_child(_falling)


# ---------------------------------------------------------------------------
# Folhas no chão e na pista
# ---------------------------------------------------------------------------
func _build_litter(track: RaceTrack, terrain: TrackTerrain, rng: RandomNumberGenerator) -> void:
	var p := track.path
	# Pista: espalhadas no asfalto, mais perto das bordas (o vento e os carros empurram)
	var on_track: Array[Transform3D] = []
	for k in 14000:
		var s := rng.randf() * p.length
		var i := p.index_at(s)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var hw := p.half_width(i, int(side))
		var lateral := side * hw * (1.0 - pow(rng.randf(), 1.8))
		var pos := p.position_at(s, lateral) + Vector3.UP * 0.024
		on_track.append(_lying(pos, rng))
	# Chão: em volta das árvores folhosas (a favor do vento) e espalhadas pelo parque plano
	var on_ground: Array[Transform3D] = []
	var wind := Vector3(0.8, 0.0, 0.6)
	for c in tree_positions:
		for k in 90:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * 9.0
			var pos := Vector3(c.x, 0.0, c.z) + Vector3(cos(a), 0, sin(a)) * r + wind * rng.randf_range(0.0, 4.0)
			var h := terrain.height_at(pos.x, pos.z)
			if h > 0.4:
				continue
			pos.y = maxf(h, 0.0) + 0.03
			on_ground.append(_lying(pos, rng))
	var area := p.bounds().grow(120.0)
	var tries := 0
	var extra := 0
	while extra < 22000 and tries < 80000:
		tries += 1
		var pos := Vector3(rng.randf_range(area.position.x, area.end.x), 0.0, rng.randf_range(area.position.y, area.end.y))
		if terrain.clearance(pos.x, pos.z) > 40.0:
			continue
		var pr := p.project(pos, false)
		if pr.x < 0.0:
			continue
		var i := p.index_at(pr.x)
		var side := 1 if pr.y > 0.0 else -1
		var off := absf(pr.y) - p.half_width(i, side)
		if off < 0.5:
			continue
		var h := terrain.height_at(pos.x, pos.z)
		if h > 0.4:
			continue
		pos.y = maxf(h, 0.0) + 0.03
		on_ground.append(_lying(pos, rng))
		extra += 1
	on_track.shuffle()
	on_ground.shuffle()
	_track_litter = _litter_node("TrackLeafLitter", on_track, rng, false)
	_ground_litter = _litter_node("GroundLeafLitter", on_ground, rng, true)


func _lying(pos: Vector3, rng: RandomNumberGenerator) -> Transform3D:
	var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.25))
	var s := rng.randf_range(0.8, 1.3)
	return Transform3D(basis.scaled(Vector3(s, s, s)), pos)


func _litter_node(node_name: String, transforms: Array[Transform3D], rng: RandomNumberGenerator, ground: bool) -> MultiMeshInstance3D:
	var data: Array[Color] = []
	for k in transforms.size():
		data.append(Color(rng.randf(), 0, 0, 0))
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.2, 0.28)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = plane
	mm.instance_count = transforms.size()
	mm.buffer = Grandstands.pack_buffer(transforms, data)
	mm.visible_instance_count = 0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/leaf.gdshader")
	mat.set_shader_parameter("use_instance_custom", true)
	mat.set_shader_parameter("ground_darken", 0.15)
	if ground:
		_litter_material_ground = mat
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-20000, -10, -20000), Vector3(40000, 400, 40000))
	add_child(mmi)
	return mmi
