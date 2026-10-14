class_name SkyDeck
extends RefCounted
## Plataforma da pista no céu (Sky Aerobase): laje metálica sob a pista, de uma borda à outra
## (RaceTrack.deck_edge: atrás das barreiras, arquibancadas e boxes; na borda aberta, no fim da
## área de escape), com friso de LED azul nas laterais, vigas por baixo e propulsores verticais
## presos nas beiradas, alternando os lados: a ponta (como a de um foguete, em metal escuro) aparece
## acima da plataforma, o corpo desce ao lado da laje e o jato azul sai por baixo.
## A laje não tem colisão: o carro anda nos pisos do TrackRoad (asfalto, zebras, escape).

const DEPTH := 2.6
## Recuo da face de baixo (o casco afina para baixo).
const UNDER_INSET := 1.1
const TOP_Y := -0.04
const HULL := Color(0.5, 0.53, 0.6)
const HULL_DARK := Color(0.22, 0.24, 0.29)
const LED := Color(0.3, 0.72, 1.0)
const ENGINE_SPACING := 46.0
## Motores: nacela (raio, altura) e o jato.
const NACELLE_RADIUS := 1.75
const NACELLE_HEIGHT := 4.6
## Propulsor da beirada: altura da ponta acima da plataforma e do corpo abaixo dela (antes da escala).
const NOSE_HEIGHT := 2.13
const EDGE_BODY := 6.0
## Raio dos propulsores da beirada em relação ao dos outros (a altura não muda).
const EDGE_RADIUS_SCALE := 1.6
## Cores das faixas dos propulsores da beirada (uma por propulsor, em sequência).
const BAND_COLORS := [Color(1.0, 0.18, 0.15), Color(1.0, 0.8, 0.1), Color(0.2, 0.55, 1.0), Color(0.2, 1.0, 0.4)]
const PLUME_LENGTH := 22.0
## Escala dos motores sob a pista.
const ENGINE_SCALE := 1.5
## Amostras por pedaço de malha (~300 m), para o recorte de visão.
const CHUNK := 150

static var _materials := {}


## Material dos frisos e luzes (sky_glow.gdshader). chase: pulso correndo pelo friso. led: na cor dos
## LEDs da pista, que troca entre azul, verde e roxo (SkyLights).
static func glow(chase := 0.0, day := 1.4, night := 3.2, led := false) -> ShaderMaterial:
	var key := "%.2f_%.2f_%.2f_%s" % [chase, day, night, led]
	if not _materials.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/sky_glow.gdshader")
		mat.set_shader_parameter("chase", chase)
		mat.set_shader_parameter("day_energy", day)
		mat.set_shader_parameter("night_energy", night)
		if led:
			SkyLights.register(mat)
		_materials[key] = mat
	return _materials[key]


## Casco metálico (painéis de 2 m, pouca sujeira).
static func hull() -> Material:
	return TrackMaterials.building("sky_hull", false, {"panel_size": 2.0, "grime_strength": 0.18, "ground_dirt": 0.0,
		"detail_strength": 0.12, "no_outline": true})


static func plume_material(core := Color(0.85, 0.95, 1.0), outer := Color(0.18, 0.5, 1.0), intensity := 1.0) -> ShaderMaterial:
	var key := "plume_%s_%s_%.2f" % [core.to_html(), outer.to_html(), intensity]
	if not _materials.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/jet_plume.gdshader")
		mat.set_shader_parameter("core_color", core)
		mat.set_shader_parameter("outer_color", outer)
		mat.set_shader_parameter("intensity", intensity)
		_materials[key] = mat
	return _materials[key]


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "SkyDeck"
	parent.add_child(root)
	var p := track.path
	var n := p.size()
	var edges := [edges(track, 1), edges(track, -1)]
	var start := 0
	var chunk := 0
	while start < n:
		var stop := mini(start + CHUNK, n)
		var mb := MeshBuilder.new()
		var leds := MeshBuilder.new()
		for i in range(start, stop):
			_segment(track, mb, leds, edges, i, (i + 1) % n)
		var mi := MeshInstance3D.new()
		mi.name = "Deck%d" % chunk
		mi.mesh = mb.commit(null, hull())
		leds.commit(mi.mesh as ArrayMesh, glow(0.6, 1.6, 3.6, true))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		start = stop
		chunk += 1
	# Propulsores nas beiradas: um de cada lado a cada ENGINE_SPACING, alternados; o +X local aponta
	# para a laje (o suporte fica desse lado)
	var xfs: Array[Transform3D] = []
	var count := int(p.length / ENGINE_SPACING)
	var r := NACELLE_RADIUS * ENGINE_SCALE * EDGE_RADIUS_SCALE
	for k in count:
		for side: int in [1, -1]:
			var s := (k + (0.25 if side > 0 else 0.75)) * p.length / count
			var i := p.index_at(s)
			var e: float = edges[RaceTrack._si(side)][i]
			var f := p.frame_at(s, side * (e + r + 0.35), TOP_Y)
			var to_deck := -p.lefts[i] * side
			to_deck.y = 0.0
			to_deck = to_deck.normalized()
			# Mais largo que alto: só o raio cresce (colunas X e Z da base)
			var side_axis := to_deck.cross(Vector3.UP)
			xfs.append(Transform3D(Basis(to_deck * EDGE_RADIUS_SCALE, Vector3.UP, side_axis * EDGE_RADIUS_SCALE), f.origin))
	add_engines(root, xfs, "Engines", ENGINE_SCALE, true)
	SkyLights.build(track, root)


## Distância da linha central até a borda da plataforma em cada amostra (alargada um pouco para não
## ter dentes nas trocas; na borda aberta é exata, porque o vazio começa ali).
static func edges(track: RaceTrack, side: int) -> PackedFloat32Array:
	var n := track.path.size()
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = track.deck_edge(i, side)
	var out := RaceTrack._dilate(raw, 3)
	for i in n:
		if track.open_edge(i, side):
			out[i] = raw[i]
	return out


static func _segment(track: RaceTrack, mb: MeshBuilder, leds: MeshBuilder, edges: Array, i: int, j: int) -> void:
	var p := track.path
	var el_i: float = edges[0][i]
	var el_j: float = edges[0][j]
	var er_i: float = edges[1][i]
	var er_j: float = edges[1][j]
	var s_i := p.s_at(i)
	var s_j := s_i + p.spacing
	# Topo (só aparece fora do asfalto/escape: atrás das barreiras, sob arquibancadas e boxes)
	mb.quad(_at(p, i, el_i, TOP_Y), _at(p, j, el_j, TOP_Y), _at(p, j, -er_j, TOP_Y), _at(p, i, -er_i, TOP_Y), HULL * 0.9, Vector3.UP)
	# Laterais (com chanfro para dentro embaixo) e friso de LED
	for side: int in [1, -1]:
		var e_i: float = el_i if side > 0 else er_i
		var e_j: float = el_j if side > 0 else er_j
		var out := p.lefts[i] * side
		var a0 := _at(p, i, side * e_i, TOP_Y)
		var b0 := _at(p, j, side * e_j, TOP_Y)
		var a1 := _at(p, i, side * e_i, TOP_Y - DEPTH * 0.45)
		var b1 := _at(p, j, side * e_j, TOP_Y - DEPTH * 0.45)
		var a2 := _at(p, i, side * (e_i - UNDER_INSET), TOP_Y - DEPTH)
		var b2 := _at(p, j, side * (e_j - UNDER_INSET), TOP_Y - DEPTH)
		if side > 0:
			mb.quad(a1, b1, b0, a0, HULL, out)
			mb.quad(a2, b2, b1, a1, HULL_DARK * 1.4, out + Vector3.DOWN)
		else:
			mb.quad(a0, b0, b1, a1, HULL, out)
			mb.quad(a1, b1, b2, a2, HULL_DARK * 1.4, out + Vector3.DOWN)
		var l0 := _at(p, i, side * (e_i + 0.03), TOP_Y - 0.28)
		var l1 := _at(p, j, side * (e_j + 0.03), TOP_Y - 0.28)
		var l2 := _at(p, j, side * (e_j + 0.03), TOP_Y - 0.5)
		var l3 := _at(p, i, side * (e_i + 0.03), TOP_Y - 0.5)
		if side > 0:
			leds.quad(l3, l2, l1, l0, LED, out, Vector2(s_i, 1), Vector2(s_j, 1), Vector2(s_j, 0), Vector2(s_i, 0))
		else:
			leds.quad(l0, l1, l2, l3, LED, out, Vector2(s_i, 0), Vector2(s_j, 0), Vector2(s_j, 1), Vector2(s_i, 1))
	# Fundo
	mb.quad(_at(p, i, -(er_i - UNDER_INSET), TOP_Y - DEPTH), _at(p, j, -(er_j - UNDER_INSET), TOP_Y - DEPTH),
		_at(p, j, el_j - UNDER_INSET, TOP_Y - DEPTH), _at(p, i, el_i - UNDER_INSET, TOP_Y - DEPTH), HULL_DARK, Vector3.DOWN)
	# Vigas transversais a cada 12 m
	if i % 6 == 0:
		var f := p.frame_at(s_i, (el_i - er_i) * 0.5, TOP_Y - DEPTH - 0.35)
		mb.box(f, Vector3(el_i + er_i - UNDER_INSET * 2.0, 0.7, 0.9), HULL_DARK)


static func _at(p: TrackPath, i: int, lateral: float, y: float) -> Vector3:
	return p.points[i] + p.lefts[i] * lateral + Vector3.UP * y


# ---------------------------------------------------------------------------
# Motores a jato verticais (também usados pela base aérea)
# ---------------------------------------------------------------------------
## Motores em `xfs`: nacela, anel brilhando no bocal e o jato. Normal (edge = false): origem no
## topo da nacela, presa por baixo de alguma coisa. Na beirada (edge = true): origem na altura do
## topo da plataforma, com a ponta de foguete para cima e o suporte para o +X local.
static func add_engines(root: Node3D, xfs: Array[Transform3D], node_name: String, scale := 1.0, edge := false) -> void:
	if xfs.is_empty():
		return
	var scaled: Array[Transform3D] = []
	for xf in xfs:
		scaled.append(Transform3D(xf.basis.scaled(Vector3.ONE * scale), xf.origin))
	var bottom := -EDGE_BODY if edge else -NACELLE_HEIGHT
	var parts := [
		[edge_engine_mesh() if edge else engine_mesh(), hull(), 2600.0, "Nacelles"],
		[_ring_mesh(bottom), glow(0.0, 1.3, 3.0), 1800.0, "Rings"],
		[plume_mesh(PLUME_LENGTH, NACELLE_RADIUS * 0.72, NACELLE_RADIUS * 1.35, 14, bottom - 0.1), plume_material(), 1600.0, "Plumes"],
	]
	if edge:
		parts.append([_band_mesh(), glow(0.0, 1.6, 3.4), 1800.0, "Bands"])
	for part in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		# Faixa na base da ponta: cada propulsor com uma cor fixa, alternando de um para o outro
		mm.use_colors = part[3] == "Bands"
		mm.mesh = part[0]
		mm.instance_count = scaled.size()
		for k in scaled.size():
			mm.set_instance_transform(k, scaled[k])
			if mm.use_colors:
				mm.set_instance_color(k, BAND_COLORS[k % BAND_COLORS.size()])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s%s" % [node_name, part[3]]
		mmi.multimesh = mm
		mmi.material_override = part[1]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = part[2] * scale
		root.add_child(mmi)


static var _meshes := {}


## Nacela vertical (topo em y = 0): suporte, corpo com reforços, saia e bocal escuro.
static func engine_mesh() -> ArrayMesh:
	if _meshes.has("engine"):
		return _meshes["engine"]
	var mb := MeshBuilder.new()
	var r := NACELLE_RADIUS
	var h := NACELLE_HEIGHT
	# Suporte (pilone) até a laje
	mb.box(Transform3D(Basis(), Vector3(0, -0.45, 0)), Vector3(r * 0.9, 0.9, r * 1.6), HULL_DARK)
	# Corpo: entrada larga em cima, cintura e bocal mais estreito
	mb.cylinder(Transform3D(Basis(), Vector3(0, -h * 0.35, 0)), r, r * 0.92, h * 0.35 - 0.6, HULL, 16)
	mb.cylinder(Transform3D(Basis(), Vector3(0, -h * 0.8, 0)), r * 0.82, r, h * 0.45, HULL * 0.92, 16, false)
	mb.cylinder(Transform3D(Basis(), Vector3(0, -h, 0)), r * 0.72, r * 0.82, h * 0.2, HULL_DARK, 16, false)
	# Anéis de reforço
	for y: float in [-h * 0.36, -h * 0.62]:
		mb.cylinder(Transform3D(Basis(), Vector3(0, y - 0.12, 0)), r * 1.04, r * 1.04, 0.24, HULL_DARK * 1.3, 16, false)
	# Fundo do bocal (escuro, visto de baixo em volta do jato)
	mb.cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -h + 0.02, 0)), r * 0.72, 0.0, 0.01, HULL_DARK * 0.5, 16)
	_meshes["engine"] = mb.commit()
	return _meshes["engine"]


## Propulsor da beirada (topo da plataforma em y = 0): ponta de foguete em três trechos acima, corpo
## com reforços descendo ao lado da laje, quatro aletas embaixo, bocal e o suporte até a laje (+X).
static func edge_engine_mesh() -> ArrayMesh:
	if _meshes.has("edge_engine"):
		return _meshes["edge_engine"]
	var mb := MeshBuilder.new()
	var r := NACELLE_RADIUS
	var h := EDGE_BODY
	# Corpo e ponta numa peça só, de normais suaves: bocal, corpo e a ponta acima da plataforma
	# (meio cúpula, meio cone: raio r·√(1 − t²)·(1 − 0,35·t), com t = y / NOSE_HEIGHT)
	var profile := PackedVector2Array([Vector2(r * 0.72, -h), Vector2(r * 0.78, -h * 0.93), Vector2(r * 0.86, -h * 0.82),
		Vector2(r * 0.97, -h * 0.66), Vector2(r, -h * 0.5), Vector2(r, -h * 0.2)])
	var tips := 12
	for k in tips + 1:
		var t := float(k) / tips
		profile.append(Vector2(r * sqrt(maxf(1.0 - t * t, 0.0)) * (1.0 - 0.35 * t), NOSE_HEIGHT * t))
	mb.lathe(Transform3D(), profile, HULL * 0.92, 24)
	for y: float in [-0.4, -h * 0.3, -h * 0.55]:
		mb.cylinder(Transform3D(Basis(), Vector3(0, y - 0.14, 0)), r * 1.05, r * 1.05, 0.28, HULL_DARK * 1.3, 16, false)
	mb.cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -h + 0.02, 0)), r * 0.72, 0.0, 0.01, HULL_DARK * 0.5, 16)
	# Aletas
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var dir := Vector3(cos(a), 0, sin(a))
		mb.box(Transform3D(Basis(Vector3.UP, -a), dir * (r + 0.45) + Vector3.UP * (-h * 0.82)), Vector3(0.9, h * 0.32, 0.12),
			HULL_DARK * 1.4)
	# Suporte até a laje
	mb.box(Transform3D(Basis(), Vector3(r + 0.15, -DEPTH * 0.5, 0)), Vector3(0.8, DEPTH * 0.7, r * 1.2), HULL_DARK * 1.3)
	_meshes["edge_engine"] = mb.commit()
	return _meshes["edge_engine"]


## Anel brilhando na boca do bocal (em y = bottom); nos da beirada, também o friso na base da ponta.
static func _ring_mesh(bottom := -NACELLE_HEIGHT) -> ArrayMesh:
	var key := "ring_%.2f" % bottom
	if _meshes.has(key):
		return _meshes[key]
	var mb := MeshBuilder.new()
	var r := NACELLE_RADIUS
	mb.cylinder(Transform3D(Basis(), Vector3(0, bottom - 0.05, 0)), r * 0.74, r * 0.74, 0.35, LED, 16, false)
	mb.cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, bottom + 0.01, 0)), r * 0.6, 0.0, 0.01, Color(0.75, 0.9, 1.0), 16)
	_meshes[key] = mb.commit()
	return _meshes[key]


## Faixa acesa na base da ponta dos propulsores da beirada (branca: a cor vem de cada instância).
static func _band_mesh() -> ArrayMesh:
	if _meshes.has("band"):
		return _meshes["band"]
	var mb := MeshBuilder.new()
	mb.cylinder(Transform3D(Basis(), Vector3(0, 0.12, 0)), NACELLE_RADIUS * 1.01, NACELLE_RADIUS * 1.0, 0.3, Color.WHITE, 20, false)
	_meshes["band"] = mb.commit()
	return _meshes["band"]


## Cone aberto do jato, do bocal (y = y0) para baixo: UV.y 0 no bocal e 1 na ponta.
static func plume_mesh(length: float, r0: float, r1: float, sides := 14, y0 := -NACELLE_HEIGHT - 0.1) -> ArrayMesh:
	var key := "plume_%.1f_%.2f_%.2f_%.2f" % [length, r0, r1, y0]
	if _meshes.has(key):
		return _meshes[key]
	var mb := MeshBuilder.new()
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		mb.quad(d0 * r0 + Vector3.UP * y0, d1 * r0 + Vector3.UP * y0, d1 * r1 + Vector3.UP * (y0 - length),
			d0 * r1 + Vector3.UP * (y0 - length), Color.WHITE, d0 + d1,
			Vector2(float(k) / sides, 0), Vector2(float(k + 1) / sides, 0), Vector2(float(k + 1) / sides, 1), Vector2(float(k) / sides, 1))
	_meshes[key] = mb.commit()
	return _meshes[key]
