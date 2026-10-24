class_name CloudDeck
extends RefCounted
## A base da pista fofa nas nuvens (Rainbow Raceway): uma laje de glacê sob a pista, de uma borda à
## outra (RaceTrack.deck_edge: atrás das barreiras, arquibancadas e boxes), com a beirada branca de
## glacê e as seis listras do arco-íris correndo pela lateral, o fundo lilás, e as nuvens fofas
## embaixo dela: almofadas nas duas beiradas (aparecendo um pouco para fora) e no meio, mais umas
## pendentes maiores de vez em quando. Perto de um cruzamento as nuvens da pista de cima não descem
## sobre a de baixo. A laje não tem colisão: o carro anda nos pisos do TrackRoad (e a laje de
## colisão dele fica logo abaixo).

const TOP_Y := -0.04
## Espessura da laje (m): a beirada de glacê, as listras e o fundo.
const DEPTH := 1.7
const ICING := 0.32
const BAND := 0.2
const UNDER_INSET := 0.5
const ICING_COLOR := Color(1.0, 0.97, 0.99)
const UNDER_COLOR := Color(0.78, 0.64, 0.95)
const TOP_COLOR := Color(1.0, 0.9, 0.95)
## Amostras por pedaço de malha (~300 m), para o recorte de visão.
const CHUNK := 150
## Nuvens: intervalo (m) nas beiradas e no meio, e o alcance do modelo detalhado e do simples.
const PUFF_SPACING := 7.0
const NEAR_RANGE := 420.0
const FAR_RANGE := 2600.0
## Folga (m) que as nuvens da pista de cima deixam sobre a pista de baixo num cruzamento.
const CROSS_CLEARANCE := 6.5


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "CloudDeck"
	parent.add_child(root)
	var p := track.path
	var n := p.size()
	var edges := [SkyDeck.edges(track, 1), SkyDeck.edges(track, -1)]
	var mat := TrackMaterials.candy_plastic("cloud_deck", false, true)
	var start := 0
	var chunk := 0
	while start < n:
		var stop := mini(start + CHUNK, n)
		var mb := MeshBuilder.new()
		for i in range(start, stop):
			_segment(track, mb, edges, i, (i + 1) % n)
		var mi := MeshInstance3D.new()
		mi.name = "Slab%d" % chunk
		mi.mesh = mb.commit(null, mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		start = stop
		chunk += 1
	_puffs(track, root, edges)


static func _segment(track: RaceTrack, mb: MeshBuilder, edges: Array, i: int, j: int) -> void:
	var p := track.path
	var el_i: float = edges[0][i]
	var el_j: float = edges[0][j]
	var er_i: float = edges[1][i]
	var er_j: float = edges[1][j]
	# Topo (aparece atrás das barreiras, sob as arquibancadas e os boxes)
	mb.quad(_at(p, i, el_i, TOP_Y), _at(p, j, el_j, TOP_Y), _at(p, j, -er_j, TOP_Y), _at(p, i, -er_i, TOP_Y), TOP_COLOR, Vector3.UP)
	for side: int in [1, -1]:
		var e_i: float = el_i if side > 0 else er_i
		var e_j: float = el_j if side > 0 else er_j
		var out := p.lefts[i] * side
		# Beirada de glacê (um pouco saliente e arredondada) e as listras do arco-íris
		var y := TOP_Y
		var rows := [[ICING, ICING_COLOR, 0.12]]
		for k in CloudLook.RAINBOW.size():
			rows.append([BAND, CloudLook.RAINBOW[k], 0.0])
		rows.append([DEPTH - ICING - BAND * CloudLook.RAINBOW.size(), UNDER_COLOR, -UNDER_INSET])
		var bulge := 0.12
		for row: Array in rows:
			var h: float = row[0]
			var next_bulge: float = row[2]
			var a0 := _at(p, i, side * (e_i + bulge), y)
			var b0 := _at(p, j, side * (e_j + bulge), y)
			var a1 := _at(p, i, side * (e_i + next_bulge), y - h)
			var b1 := _at(p, j, side * (e_j + next_bulge), y - h)
			mb.quad(a0, b0, b1, a1, row[1], out)
			bulge = next_bulge
			y -= h
	# Fundo
	mb.quad(_at(p, i, -(er_i - UNDER_INSET), TOP_Y - DEPTH), _at(p, j, -(er_j - UNDER_INSET), TOP_Y - DEPTH),
		_at(p, j, el_j - UNDER_INSET, TOP_Y - DEPTH), _at(p, i, el_i - UNDER_INSET, TOP_Y - DEPTH), UNDER_COLOR * 0.9, Vector3.DOWN)


static func _at(p: TrackPath, i: int, lateral: float, y: float) -> Vector3:
	return p.points[i] + p.lefts[i] * lateral + Vector3.UP * y


## Nuvens em volta e embaixo da laje, em pedaços de ~300 m com o modelo detalhado perto e um
## simples longe:
##   * na beirada (de pé, com o topo redondo aparecendo ~0,6 a 1,2 m acima da laje, quase toda
##     para fora dela: o contorno de algodão da pista);
##   * embaixo (de cabeça para baixo: o lado achatado encosta no fundo da laje), com uma pendente
##     maior de vez em quando.
static func _puffs(track: RaceTrack, root: Node3D, edges: Array) -> void:
	var p := track.path
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var per_chunk := int(300.0 / PUFF_SPACING)
	var count := int(p.length / PUFF_SPACING)
	var mat := CloudLook.cloud_material()
	var chunks: Array = []
	var cur: Array[Transform3D] = []
	var placed := 0
	var flip := Basis(Vector3.RIGHT, PI)
	for k in count:
		var s := k * PUFF_SPACING + rng.randf_range(-2.0, 2.0)
		var i := p.index_at(s)
		var yaw := Basis(Vector3.UP, rng.randf() * TAU)
		var xfs: Array[Transform3D] = []
		# Beiradas
		for side: int in [1, -1]:
			var e: float = edges[RaceTrack._si(side)][i]
			var scale := rng.randf_range(3.6, 5.6)
			var sy := scale * rng.randf_range(0.5, 0.7)
			var lateral := side * (e + scale * rng.randf_range(0.2, 0.45))
			var top := rng.randf_range(0.5, 1.1)
			var f := p.frame_at(s, lateral, top - sy * 0.95)
			xfs.append(Transform3D((yaw * Basis(Vector3.UP, side)).scaled(Vector3(scale * 1.15, sy, scale)), f.origin))
		# Embaixo, no meio
		if k % 2 == 0:
			var scale := rng.randf_range(6.0, 9.5)
			var drop := 0.0
			if rng.randf() < 0.2:
				scale *= 1.5
				drop = rng.randf_range(1.0, 4.0)
			var lateral: float = (float(edges[0][i]) - float(edges[1][i])) * 0.5 + rng.randf_range(-2.0, 2.0)
			var f := p.frame_at(s, lateral, TOP_Y - DEPTH + 0.25 - drop)
			xfs.append(Transform3D((yaw * flip).scaled(Vector3(scale * 1.2, scale * rng.randf_range(0.5, 0.7), scale)), f.origin))
		for xf in xfs:
			if _over_lower(track, xf):
				continue
			cur.append(xf)
			placed += 1
		if k % per_chunk == per_chunk - 1:
			chunks.append(cur)
			cur = []
	if not cur.is_empty():
		chunks.append(cur)
	var near_meshes: Array[ArrayMesh] = []
	var far_meshes: Array[ArrayMesh] = []
	for v in 3:
		near_meshes.append(CloudLook.puff_mesh(v, 7, true, 1))
		far_meshes.append(CloudLook.puff_mesh(v, 7, true, 3))
	for c in chunks.size():
		var list: Array[Transform3D] = chunks[c]
		var groups := [[] as Array[Transform3D], [] as Array[Transform3D], [] as Array[Transform3D]]
		for k in list.size():
			groups[k % 3].append(list[k])
		for v in 3:
			var near := CloudLook.add_multimesh(root, "Puffs%d_%d" % [c, v], near_meshes[v], groups[v], mat, NEAR_RANGE)
			if near:
				# Ponto mais baixo de cada nuvem (as de cima são de pé, as de baixo de cabeça para baixo)
				var bottoms := PackedFloat32Array()
				for xf: Transform3D in groups[v]:
					bottoms.append(minf(xf.origin.y, (xf * Vector3(0, 0.95, 0)).y))
				near.set_meta("bottoms", bottoms)
			var far := CloudLook.add_multimesh(root, "PuffsFar%d_%d" % [c, v], far_meshes[v], groups[v], mat, FAR_RANGE)
			if far:
				far.visibility_range_begin = NEAR_RANGE
				far.visibility_range_begin_margin = NEAR_RANGE * 0.1
	root.set_meta("puffs", placed)


## Uma nuvem (malha de base em y = 0 e topo em ~0,95, transformada por `xf`) que desceria sobre a
## pista de baixo num cruzamento: a menos de CROSS_CLEARANCE m acima do asfalto de baixo, na largura
## dela até atrás das barreiras.
static func _over_lower(track: RaceTrack, xf: Transform3D) -> bool:
	var p := track.path
	var pos := xf.origin
	var reach_xz := maxf(xf.basis.x.length(), xf.basis.z.length()) * 1.3
	var low := minf(pos.y, (xf * Vector3(0, 0.95, 0)).y)
	for c in p.crossings:
		var lower := p.position_at(c.x)
		if Vector2(pos.x - lower.x, pos.z - lower.z).length() > 160.0:
			continue
		# Ponto mais perto na pista de baixo (só o plano), olhando em volta do cruzamento
		var best := INF
		var best_s := c.x
		var s := c.x - 140.0
		while s < c.x + 140.0:
			var q := p.position_at(s)
			var d := Vector2(pos.x - q.x, pos.z - q.z).length()
			if d < best:
				best = d
				best_s = s
			s += 2.0
		var i := p.index_at(best_s)
		var reach := maxf(p.width_left[i], p.width_right[i]) + maxf(track.barrier[0][i], track.barrier[1][i]) + 4.0 + reach_xz
		if best < reach and low < p.height_at(best_s) + CROSS_CLEARANCE and pos.y > p.height_at(best_s) + 2.0:
			return true
	return false
