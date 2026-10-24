class_name PlushFriends
extends RefCounted
## Bichos de pelúcia da Rainbow Raceway (modelos de blender/cloud_plush.py, plush.gdshader):
##   * na beira da pista, sentados em almofadas de nuvem atrás das barreiras e virados para quem vem,
##     acenando (ursinhos e coelhinhos) ou abraçando um coração, em grupinhos de um a três;
##   * o Ursinho gigante na ilha da Curva do Ursinho, acenando para a pista;
##   * o piquenique na Ilha dos Ursinhos: toalha xadrez, um bolo de cupcake no meio e a turma em volta;
##   * um ou dois nas ilhotas maiores (as do CloudIslands).
## Pelos em tons pastel sorteados; laço e coração numa cor de destaque. Nada tem colisão.

const MODELS := "res://assets/track/rainbow_raceway/models/"
const KINDS := ["bear_wave", "bear_hug", "bunny_wave"]
## Ombro do braço que acena de cada modelo (espaço do modelo no Godot; impresso por build_clouds.py).
const PIVOTS := {"bear_wave": Vector3(-0.215, 0.49, 0.02), "bear_hug": Vector3(0.0, 0.47, 0.05), "bunny_wave": Vector3(-0.19, 0.446, 0.02)}
const FURS := [Color(1.0, 0.62, 0.76), Color(0.74, 0.62, 1.0), Color(1.0, 0.86, 0.42), Color(0.58, 0.78, 1.0), Color(0.58, 0.92, 0.74),
	Color(1.0, 0.74, 0.56), Color(0.98, 0.96, 0.94), Color(0.78, 0.56, 0.44)]
## Beira da pista: intervalo (m) entre os grupinhos e a altura de cada bicho (m).
const TRACKSIDE_SPACING := 85.0
const TRACKSIDE_SIZE := Vector2(2.1, 2.8)
## Altura da almofada de nuvem em que eles sentam (aparecem inteiros por cima da barreira).
const CUSHION := 1.05
const TRACKSIDE_RANGE := 420.0
## Pedaços da pista (m) com um MultiMesh por modelo (recorte).
const CHUNK := 600.0
const GIANT_SIZE := 22.0

static var _materials := {}


static func material(multi: bool) -> ShaderMaterial:
	if not _materials.has(multi):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/plush.gdshader")
		mat.set_shader_parameter("use_custom", multi)
		_materials[multi] = mat
	return _materials[multi]


## Malha do modelo `kind` (a primeira do .glb), ou nulo se não existir.
static func mesh(kind: String) -> Mesh:
	var path := MODELS + kind + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene := (load(path) as PackedScene).instantiate()
	var found: Mesh = null
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		found = mi.mesh
		break
	scene.free()
	return found


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "PlushFriends"
	parent.add_child(root)
	var meshes := {}
	for kind: String in KINDS:
		var m := mesh(kind)
		if m:
			meshes[kind] = m
	if meshes.size() < KINDS.size():
		push_warning("PlushFriends: modelos faltando em %s" % MODELS)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 8086
	var placed := _trackside(track, root, meshes, rng)
	var cushions: Array[Transform3D] = placed[1]
	var count: int = placed[0]
	count += _giant(track, root, meshes)
	count += _picnic(track, root, meshes, rng)
	count += _islands(parent, root, meshes, rng, cushions)
	CloudLook.add_multimesh(root, "Cushions", CloudLook.puff_mesh(4, 6, true, 1), cushions, CloudLook.cloud_material(), 900.0)
	root.set_meta("count", count)


## Grupinhos na beira da pista: [quantos, almofadas].
static func _trackside(track: RaceTrack, root: Node3D, meshes: Dictionary, rng: RandomNumberGenerator) -> Array:
	var p := track.path
	var chunks := {}
	var cushions: Array[Transform3D] = []
	var count := 0
	var n := int(p.length / TRACKSIDE_SPACING)
	for k in n:
		var s := (k + 0.3) * p.length / n + rng.randf_range(-12.0, 12.0)
		var side := 1 if k % 2 == 0 else -1
		var i := p.index_at(s)
		if not _free_spot(track, s, side):
			side = -side
			if not _free_spot(track, s, side):
				continue
		var kidx := RaceTrack._si(side)
		var back := p.half_width(i, side) + track.barrier[kidx][i] + TrackBarriers.CLOUD_THICK
		var room := track.deck_edge(i, side) - back
		var group := rng.randi_range(1, 3)
		for g in group:
			var size := rng.randf_range(TRACKSIDE_SIZE.x, TRACKSIDE_SIZE.y)
			var lat := side * (back + clampf(room * 0.5, 1.0, 2.2) + rng.randf_range(-0.3, 0.5))
			var at := p.frame_at(s + (g - (group - 1) * 0.5) * 2.4, lat, 0.0).origin
			# Virado para a pista, um pouco para quem vem
			var to_road := -p.lefts[i] * side
			var face := (to_road * 0.8 - p.tangents[i] * 0.5)
			face.y = 0.0
			face = face.normalized()
			var kind: String = KINDS[rng.randi() % KINDS.size()] if g > 0 else ("bear_wave" if rng.randf() < 0.65 else "bunny_wave")
			var xf := Transform3D(_facing(face).scaled(Vector3.ONE * size), at + Vector3.UP * CUSHION)
			_add(chunks, int(s / CHUNK), kind, xf, rng)
			cushions.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size * 0.8, CUSHION * 1.35, size * 0.7)), at + Vector3.DOWN * 0.25))
			count += 1
	_commit(root, "Trackside", chunks, meshes, TRACKSIDE_RANGE)
	return [count, cushions]


## Lugar livre para um grupinho em s, do lado `side`: atrás da barreira cabe (a plataforma vai além),
## sem arquibancada, prédio dos boxes, túnel, cruzamento nem pé de arco por perto.
static func _free_spot(track: RaceTrack, s: float, side: int) -> bool:
	var p := track.path
	var i := p.index_at(s)
	if track.in_tunnel(i) or track.open_edge(i, side):
		return false
	if track.layout.has_pit and side == track.layout.pit_side and track.pit_width[i] > 0.0:
		return false
	if TrackProps._stand_clearance(track, s, side) > 0.0:
		return false
	for c in p.crossings:
		if track.in_span(s, c.x - 70.0, c.x + 70.0) or track.in_span(s, c.y - 70.0, c.y + 70.0):
			return false
	for a: float in HeartArches.RAINBOWS + HeartArches.GARLANDS:
		if absf(fposmod(s - a + p.length * 0.5, p.length) - p.length * 0.5) < 8.0:
			return false
	var back := p.half_width(i, side) + track.barrier[RaceTrack._si(side)][i] + TrackBarriers.CLOUD_THICK
	return track.deck_edge(i, side) - back > 2.6


static func _facing(face: Vector3) -> Basis:
	return Basis(Vector3.UP.cross(face).normalized(), Vector3.UP, face)


## Guarda um bicho no pedaço `chunk`: [transformações, dados (pelo, destaque + fase)].
static func _add(chunks: Dictionary, chunk: int, kind: String, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var key := "%s#%d" % [kind, chunk]
	if not chunks.has(key):
		chunks[key] = [[] as Array[Transform3D], [] as Array[Color]]
	var c: Array = chunks[key]
	(c[0] as Array[Transform3D]).append(xf)
	var fur: Color = FURS[rng.randi() % FURS.size()]
	(c[1] as Array[Color]).append(Color(fur.r, fur.g, fur.b, float(rng.randi() % 5) + rng.randf() * 0.99))


static func _commit(root: Node3D, prefix: String, chunks: Dictionary, meshes: Dictionary, range_end: float) -> void:
	for key: String in chunks:
		var kind := key.get_slice("#", 0)
		var c: Array = chunks[key]
		var xfs: Array[Transform3D] = c[0]
		var data: Array[Color] = c[1]
		var pts := PackedVector3Array()
		for xf in xfs:
			pts.append(xf.origin)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[kind]
		mm.instance_count = xfs.size()
		for k in xfs.size():
			mm.set_instance_transform(k, xfs[k])
			mm.set_instance_custom_data(k, data[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%s_%s" % [prefix, kind, key.get_slice("#", 1)]
		mmi.multimesh = mm
		mmi.set_meta("points", pts)
		mmi.material_override = material(true)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if range_end > 0.0:
			mmi.visibility_range_end = range_end
			mmi.visibility_range_end_margin = range_end * 0.1
		root.add_child(mmi)
		_set_motion(mmi, kind)


static func _set_motion(node: GeometryInstance3D, kind: String) -> void:
	node.set_instance_shader_parameter("pivot", PIVOTS[kind])
	node.set_instance_shader_parameter("mode", 1 if kind == "bear_hug" else 0)
	node.set_instance_shader_parameter("amp", 0.5 if kind == "bear_wave" else 0.42)
	node.set_instance_shader_parameter("freq", 3.2 if kind != "bear_hug" else 2.0)


## Um bicho solto (nó com as cores nos instance uniforms).
static func single(root: Node3D, meshes: Dictionary, kind: String, xf: Transform3D, fur: Color, accent: Color, phase: float,
		node_name: String, range_end := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = meshes[kind]
	mi.material_override = material(false)
	mi.transform = xf
	root.add_child(mi)
	_set_motion(mi, kind)
	mi.set_instance_shader_parameter("fur_color", fur)
	mi.set_instance_shader_parameter("accent_color", accent)
	mi.set_instance_shader_parameter("phase", phase)
	if range_end > 0.0:
		mi.visibility_range_end = range_end
	return mi


## O Ursinho gigante da Curva do Ursinho (sentado na ilha, acenando para a pista).
static func _giant(track: RaceTrack, root: Node3D, meshes: Dictionary) -> int:
	var lm := CloudIslands.landmark(track, "bear_corner")
	var pos: Vector3 = lm.pos
	pos.y = CloudIslands.top_y(lm.pos, lm.radius, 0.0) - 0.3
	var target := track.path.position_at(420.0)
	var face := target - pos
	face.y = 0.0
	var xf := Transform3D(_facing(face.normalized()).scaled(Vector3.ONE * GIANT_SIZE), pos)
	var mi := single(root, meshes, "bear_wave", xf, Color(1.0, 0.6, 0.76), Color(0.6, 0.42, 1.0), 0.0, "GiantBear")
	mi.set_instance_shader_parameter("freq", 1.6)
	mi.set_meta("at", pos)
	return 1


## Piquenique na Ilha dos Ursinhos: toalha xadrez, o bolo no meio e a turma em roda.
static func _picnic(track: RaceTrack, root: Node3D, meshes: Dictionary, rng: RandomNumberGenerator) -> int:
	var lm := CloudIslands.landmark(track, "bears")
	var r: float = lm.radius
	var center: Vector3 = lm.pos
	center.y = CloudIslands.top_y(lm.pos, r, 0.0)
	var mb := MeshBuilder.new()
	var blanket := r * 0.42
	var cells := 8
	var cell := blanket * 2.0 / cells
	for x in cells:
		for z in cells:
			var col := Color(1.0, 0.45, 0.62) if (x + z) % 2 == 0 else Color.WHITE
			var c := center + Vector3(-blanket + (x + 0.5) * cell, 0.06, -blanket + (z + 0.5) * cell)
			mb.quad(c + Vector3(-cell, 0, -cell) * 0.5, c + Vector3(cell, 0, -cell) * 0.5, c + Vector3(cell, 0, cell) * 0.5,
				c + Vector3(-cell, 0, cell) * 0.5, col, Vector3.UP)
	CandyDecor.cupcake_house(mb, Transform3D(Basis(), center), 3.2, CloudLook.LILAC, CloudLook.PINK, rng)
	CloudLook.add_mesh(root, "Picnic", mb.commit(null, CandyDecor.material()))
	var n := 7
	var to_track := track.path.position_at(track.path.project(center, true, false).x) - center
	to_track.y = 0.0
	var count := 0
	for k in n:
		var a := TAU * k / n + 0.3
		var at := center + Vector3(cos(a), 0.0, sin(a)) * blanket * 0.85
		var face := (center - at).normalized()
		var kind: String = KINDS[k % KINDS.size()]
		# Um de costas para a roda, acenando para a pista
		if k == 0:
			face = to_track.normalized()
			kind = "bear_wave"
		var size := rng.randf_range(5.5, 7.5)
		var fur: Color = FURS[k % FURS.size()]
		single(root, meshes, kind, Transform3D(_facing(face).scaled(Vector3.ONE * size), at + Vector3.UP * 0.05), fur,
			CloudLook.pick(rng, [CloudLook.HOT_PINK, CloudLook.LILAC, CloudLook.BABY_BLUE]), rng.randf() * TAU, "Picnic%d" % k, 2500.0)
		count += 1
	return count


## Um ou dois bichos nas ilhotas maiores, sentados numa almofada perto da beirada.
static func _islands(parent: Node3D, root: Node3D, meshes: Dictionary, rng: RandomNumberGenerator, cushions: Array[Transform3D]) -> int:
	var islands := parent.get_node_or_null("CloudIslands")
	if islands == null:
		return 0
	var pts: Array = islands.get_meta("points", [])
	var radii: Array = islands.get_meta("radii", [])
	var chunks := {}
	var count := 0
	for k in pts.size():
		var r: float = radii[k]
		if r < 16.0 or r > 40.0 or rng.randf() < 0.45:
			continue
		var pos: Vector3 = pts[k]
		for g in rng.randi_range(1, 2):
			var a := rng.randf() * TAU
			var at := pos + Vector3(cos(a), 0.0, sin(a)) * r * 0.6
			at.y = CloudIslands.top_y(pos, r, 0.6) + 0.2
			var size := rng.randf_range(3.0, 4.6)
			var face := Vector3(cos(a), 0.0, sin(a))
			_add(chunks, k, KINDS[rng.randi() % KINDS.size()], Transform3D(_facing(face).scaled(Vector3.ONE * size), at), rng)
			cushions.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size * 0.75, size * 0.3, size * 0.65)), at + Vector3.DOWN * 0.3))
			count += 1
	_commit(root, "Islands", chunks, meshes, 1600.0)
	return count
