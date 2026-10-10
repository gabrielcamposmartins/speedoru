class_name TrackBridge
extends RefCounted
## Cruzamento em viaduto (Suzuka): o trecho de baixo passa num corte com muros de arrimo de
## concreto dos dois lados (logo atrás da barreira) e o de cima atravessa numa ponte.
##
## O terreno (TrackTerrain.ground_near) já fica no nível de cima em volta do cruzamento e no de
## baixo no corredor da pista de baixo; a rampa da grade entre os dois fica atrás do muro, coberta
## pelo topo dele (grama com o shader do terreno, na altura que o chão teria sem o corte). A ponte
## (laje, acostamento asfaltado e faixas de anúncio nas laterais) vai onde o chão sob a pista de
## cima fica abaixo dela.

const DECK := 1.4
const CONCRETE := Color(0.8, 0.8, 0.82)
const CONCRETE_DARK := Color(0.6, 0.6, 0.63)
const COPING := 0.45
## Pontos na lateral do topo do muro (seguem o chão).
const TOP_STEPS := 5


static func build(track: RaceTrack, terrain: TrackTerrain, parent: Node3D) -> void:
	var p := track.path
	if p.crossings.is_empty() or terrain == null:
		return
	for k in p.crossings.size():
		var root := Node3D.new()
		root.name = "Bridge%d" % k
		parent.add_child(root)
		_cutting(track, terrain, p.crossings[k], root)
		_deck(track, terrain, p.crossings[k], root)
		_footprints(track, terrain, p.crossings[k])


## Áreas sem árvores, arbustos e pinheiros: o corredor de baixo com o topo dos muros (uma árvore
## no fundo do corte atravessaria a ponte) e a faixa da ponte.
static func _footprints(track: RaceTrack, terrain: TrackTerrain, c: Vector3) -> void:
	var p := track.path
	var reach := TrackTerrain.CROSS_OUTER + 10.0
	var spans := [[c.x, reach, true], [c.y, 60.0, false]]
	for sp in spans:
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for i in track.span_indices(sp[0] - sp[1], sp[0] + sp[1], 2):
			var l: float
			var r: float
			if sp[2]:
				l = terrain.cut_reach(i, 1) + TrackTerrain.CELL * 1.5 + 4.0
				r = terrain.cut_reach(i, -1) + TrackTerrain.CELL * 1.5 + 4.0
			else:
				l = TrackTerrain.cut_wall(track, i, 1) + 6.0
				r = TrackTerrain.cut_wall(track, i, -1) + 6.0
			var a := _at(p, i, l)
			var b := _at(p, i, -r)
			left.append(Vector2(a.x, a.z))
			right.append(Vector2(b.x, b.z))
		right.reverse()
		left.append_array(right)
		track.footprints.append(left)


## Sob a ponte o muro e o topo dele param embaixo da laje (a ponte apoia neles): altura máxima
## em q (INF fora da faixa da ponte).
static func _under_deck(track: RaceTrack, c: Vector3, q: Vector3) -> float:
	var p := track.path
	var up := p.project_near(q, c.y, 50.0)
	var i := p.index_at(up.x)
	if absf(up.y) < TrackTerrain.cut_wall(track, i, 1 if up.y > 0.0 else -1) + 0.8:
		return p.height_at(up.x) - DECK - 0.05
	return INF


## Ponto a `lat` m do eixo (com sinal: + esquerda) na amostra i.
static func _at(p: TrackPath, i: int, lat: float) -> Vector3:
	return p.points[i] + p.lefts[i] * lat


# ---------------------------------------------------------------------------
# Corte: muros de arrimo ao longo do trecho de baixo
# ---------------------------------------------------------------------------
static func _cutting(track: RaceTrack, terrain: TrackTerrain, c: Vector3, root: Node3D) -> void:
	var p := track.path
	var walls := MeshBuilder.new()
	var tops := MeshBuilder.new()
	var boxes: Array = []
	var top_sum := 0.0
	var top_count := 0
	var reach := TrackTerrain.CROSS_OUTER + 10.0
	var cap := 0.18
	var cache := {}
	for i in track.span_indices(c.x - reach, c.x + reach):
		var j := p.wrap_index(i + 1)
		for side in [1, -1]:
			var a: Dictionary = _wall_profile(track, terrain, c, i, side, cap, cache)
			var b: Dictionary = _wall_profile(track, terrain, c, j, side, cap, cache)
			if not (a["wall"] or b["wall"]):
				continue
			var face_i: Vector3 = a["face"]
			var face_j: Vector3 = b["face"]
			var top_i: float = a["top"]
			var top_j: float = b["top"]
			var inward: Vector3 = -p.lefts[i] * side
			# Face do muro (até um pouco acima do chão de cima) e a capa de concreto
			walls.quad(Vector3(face_i.x, p.points[i].y - 0.3, face_i.z), Vector3(face_j.x, p.points[j].y - 0.3, face_j.z),
				Vector3(face_j.x, top_j + cap, face_j.z), Vector3(face_i.x, top_i + cap, face_i.z), CONCRETE, inward)
			var back_i: Vector3 = a["back"]
			var back_j: Vector3 = b["back"]
			walls.quad(Vector3(face_i.x, top_i + cap, face_i.z), Vector3(face_j.x, top_j + cap, face_j.z),
				Vector3(back_j.x, top_j + cap, back_j.z), Vector3(back_i.x, top_i + cap, back_i.z), CONCRETE_DARK, Vector3.UP)
			walls.quad(Vector3(back_i.x, top_i + cap, back_i.z), Vector3(back_j.x, top_j + cap, back_j.z),
				Vector3(back_j.x, top_j - 0.4, back_j.z), Vector3(back_i.x, top_i - 0.4, back_i.z), CONCRETE_DARK, -inward)
			boxes.append(TrackBarriers._wall_box(Vector3(face_i.x, p.points[i].y - 0.3, face_i.z),
				Vector3(face_j.x, p.points[j].y - 0.3, face_j.z), -inward, 1.0) + [maxf(top_i, top_j) - minf(p.points[i].y, p.points[j].y) + 0.3])
			# Topo: do fundo da capa até além da rampa
			var row_i: Array[Vector3] = a["row"]
			var row_j: Array[Vector3] = b["row"]
			for t in TOP_STEPS - 1:
				tops.quad(row_i[t], row_j[t], row_j[t + 1], row_i[t + 1], Color.WHITE, Vector3.UP)
			for v in row_i:
				top_sum += v.y
				top_count += 1
	if walls.is_empty():
		return
	var body := TrackSurface.make_body("CuttingWalls", TrackSurface.Type.BARRIER)
	var mi := MeshInstance3D.new()
	mi.name = "Walls"
	mi.mesh = walls.commit(null, TrackMaterials.structure())
	body.add_child(mi)
	for box in boxes:
		# Bloco do pé da face até o topo (a altura do bloco padrão da barreira não cobre o muro)
		var shape := BoxShape3D.new()
		var size: Vector3 = box[1]
		var h: float = box[2]
		shape.size = Vector3(size.x, h, size.z)
		var xf: Transform3D = box[0]
		xf.origin += xf.basis.y.normalized() * (h - size.y) * 0.5
		var owner_id := body.create_shape_owner(body)
		body.shape_owner_add_shape(owner_id, shape)
		body.shape_owner_set_transform(owner_id, xf)
	root.add_child(body)
	var ground := TrackSurface.make_body("CuttingTop", TrackSurface.Type.GRASS)
	var top_mi := MeshInstance3D.new()
	top_mi.name = "Top"
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/terrain.gdshader")
	mat.set_shader_parameter("use_heightmap", false)
	mat.set_shader_parameter("base_height", top_sum / maxf(top_count, 1))
	mat.set_shader_parameter("normal_tex", TrackMaterials.normal_texture("grass"))
	mat.set_shader_parameter("normal_strength", 0.9)
	top_mi.mesh = tops.commit(null, mat)
	ground.add_child(top_mi)
	var col := CollisionShape3D.new()
	col.shape = tops.collision_shape()
	ground.add_child(col)
	root.add_child(ground)


## Perfil do muro do corte na amostra i, lado `side` (calculado uma vez por amostra): face, fundo da
## capa, altura do topo e a fileira de pontos do topo (na altura do chão sem o corte; a última pega
## a altura do terreno de verdade, emendando sem degrau). wall = falso onde o corte é raso.
static func _wall_profile(track: RaceTrack, terrain: TrackTerrain, c: Vector3, i: int, side: int, cap: float,
		cache: Dictionary) -> Dictionary:
	var key := i * 2 + (1 if side > 0 else 0)
	if cache.has(key):
		return cache[key]
	var p := track.path
	var w := TrackTerrain.cut_wall(track, i, side)
	var o := terrain.cut_reach(i, side) + TrackTerrain.CELL * 1.5
	var face := _at(p, i, side * w)
	var top := terrain.uncut_height_at(face.x, face.z) + 0.05
	var out := {"face": face, "back": _at(p, i, side * (w + COPING)), "wall": top - p.points[i].y >= 0.5}
	top = minf(maxf(top, p.points[i].y + 0.3), _under_deck(track, c, face) - cap)
	out["top"] = top
	var row: Array[Vector3] = []
	for t in TOP_STEPS:
		var q := _at(p, i, side * lerpf(w + COPING, o, float(t) / (TOP_STEPS - 1)))
		if t == TOP_STEPS - 1:
			q.y = terrain.height_at(q.x, q.z)
		else:
			q.y = maxf(terrain.uncut_height_at(q.x, q.z), terrain.height_at(q.x, q.z)) + 0.04
			if t == 0:
				q.y = minf(q.y, top + cap - 0.02)
			q.y = minf(q.y, _under_deck(track, c, q) - 0.02)
		row.append(q)
	out["row"] = row
	cache[key] = out
	return out


# ---------------------------------------------------------------------------
# Ponte: laje sob o trecho de cima onde o chão fica abaixo da pista
# ---------------------------------------------------------------------------
static func _deck(track: RaceTrack, terrain: TrackTerrain, c: Vector3, root: Node3D) -> void:
	var p := track.path
	var idx := track.span_indices(c.y - 80.0, c.y + 80.0)
	var need := PackedByteArray()
	need.resize(idx.size())
	for k in idx.size():
		var i := idx[k]
		var l := TrackTerrain.cut_wall(track, i, 1)
		var r := TrackTerrain.cut_wall(track, i, -1)
		for t in 9:
			var pt := _at(p, i, lerpf(-r, l, t / 8.0))
			if terrain.height_at(pt.x, pt.z) < p.points[i].y - 0.35:
				need[k] = 1
				break
	# Apoio de alguns metros sobre o topo dos muros em cada ponta
	var span := PackedByteArray(need)
	for k in idx.size():
		if need[k]:
			for d in range(-4, 5):
				span[clampi(k + d, 0, idx.size() - 1)] = 1
	var slab := MeshBuilder.new()
	var verge := MeshBuilder.new()
	var ads := MeshBuilder.new()
	var first := -1
	var last := -1
	for k in idx.size() - 1:
		if not (span[k] and span[k + 1]):
			continue
		if first < 0:
			first = k
		last = k + 1
		var i := idx[k]
		var j := idx[k + 1]
		var y := TrackRoad.ROAD_Y - 0.004
		for side in [1, -1]:
			var hw_i := p.half_width(i, side)
			var hw_j := p.half_width(j, side)
			var e_i := TrackTerrain.cut_wall(track, i, side)
			var e_j := TrackTerrain.cut_wall(track, j, side)
			# Acostamento asfaltado da borda da pista até o parapeito
			TrackRoad._strip(verge, p, i, j, side * hw_i, side * hw_j, side * e_i, side * e_j, y, TrackRoad.VERGE)
			# Lateral da laje (face externa), com uma faixa de anúncio
			var a := _at(p, i, side * e_i)
			var b := _at(p, j, side * e_j)
			var out: Vector3 = p.lefts[i] * side
			slab.quad(a + Vector3.UP * 0.02, b + Vector3.UP * 0.02, b - Vector3.UP * DECK, a - Vector3.UP * DECK,
				CONCRETE, out)
			var seg := (p.s_at(i) - p.s_at(idx[0])) / 12.0
			var uv := TrackAds.ad_uv(int(seg) + (3 if side > 0 else 0))
			var u0 := uv.position.x + uv.size.x * fposmod(seg, 1.0)
			var u1 := u0 + uv.size.x * p.spacing / 12.0
			var lift: Vector3 = out * 0.03
			ads.quad(a + lift - Vector3.UP * 0.25, b + lift - Vector3.UP * 0.25, b + lift - Vector3.UP * 1.15,
				a + lift - Vector3.UP * 1.15, Color.WHITE, out,
				Vector2(u0, uv.position.y), Vector2(u1, uv.position.y), Vector2(u1, uv.end.y), Vector2(u0, uv.end.y))
		# Fundo da laje
		var l_i := _at(p, i, TrackTerrain.cut_wall(track, i, 1))
		var l_j := _at(p, j, TrackTerrain.cut_wall(track, j, 1))
		var r_i := _at(p, i, -TrackTerrain.cut_wall(track, i, -1))
		var r_j := _at(p, j, -TrackTerrain.cut_wall(track, j, -1))
		var down := Vector3.UP * DECK
		slab.quad(r_i - down, r_j - down, l_j - down, l_i - down, CONCRETE_DARK, Vector3.DOWN)
	if first < 0:
		return
	# Tampas nas pontas (ficam no topo dos muros)
	for k in [first, last]:
		var i := idx[k]
		var l := _at(p, i, TrackTerrain.cut_wall(track, i, 1))
		var r := _at(p, i, -TrackTerrain.cut_wall(track, i, -1))
		var back := -p.tangents[i] if k == first else p.tangents[i]
		slab.quad(l, r, r - Vector3.UP * DECK, l - Vector3.UP * DECK, CONCRETE, back)
	var mi := MeshInstance3D.new()
	mi.name = "Deck"
	mi.mesh = slab.commit(null, TrackMaterials.structure())
	root.add_child(mi)
	var ads_mi := MeshInstance3D.new()
	ads_mi.name = "DeckAds"
	ads_mi.mesh = ads.commit(null, TrackMaterials.ads())
	ads_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ads_mi)
	TrackRoad._add_surface(root, "DeckVerge", verge, TrackMaterials.surface("asphalt"), TrackSurface.Type.RUNOFF)
