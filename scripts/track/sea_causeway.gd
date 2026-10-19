class_name SeaCauseway
extends RefCounted
## A pista no fundo do mar corre sobre uma laje de pedra (de uma borda da estrutura à outra, como a
## plataforma da Sky Aerobase: RaceTrack.deck_edge) com cornija e um friso de LED ciano nas
## laterais. Embaixo dela:
##  * onde o leito está perto (menos de PLINTH m), a parede desce cheia até o chão;
##  * no resto, arcos de aqueduto: pilares a cada PIER_SPACING m e arcos entre eles, em andares de
##    até TIER m (na fossa do abismo e na subida até o Portão de Poseidon ficam dois ou três), com
##    pilastras salientes nas faces dos pilares (impostas em cada andar), aduelas de pedra e tijolo
##    alternados em volta dos arcos com a pedra de fecho, cornijas entre os andares, lanternas quentes num pilar a cada LANTERN_EVERY e estandartes do
##    tridente num a cada BANNER_EVERY.
## Algas penduradas na cornija e no alto dos arcos e colônias de coral na base dos pilares (SeaReef).
## Só visual (a colisão é a DeckFloor do TrackRoad); em pedaços de CHUNK amostras para o recorte.

const TOP_Y := -0.04
const DEPTH := 1.5
const CORNICE := 0.35
const PIER_SPACING := 24.0
const PIER_WIDTH := 3.6
const TIER := 24.0
const PLINTH := 3.0
const ARC_STEPS := 10
const BAND := 0.9
const LANTERN_EVERY := 3
const BANNER_EVERY := 4
const CHUNK := 150
const STONE := Color(0.84, 0.81, 0.74)
const STONE_DARK := Color(0.64, 0.63, 0.6)
const LED := Color(0.25, 0.95, 1.0)
const VISIBILITY := 1500.0

## Algas e corais presos na laje e nos pilares (SeaReef).
static var _rng := RandomNumberGenerator.new()


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Causeway"
	parent.add_child(root)
	var p := track.path
	var n := p.size()
	var edges := [SkyDeck.edges(track, 1), SkyDeck.edges(track, -1)]
	# Onde há o tubo de vidro, a laje vai até a base dele (o tubo é mais largo onde a pista estreita,
	# para não acompanhar cada degrau)
	var tube := SeaTube.profile(track)
	for i in n:
		if tube.on[i] == 1:
			edges[0][i] = maxf(edges[0][i], float(tube.left[i]) + 0.6)
			edges[1][i] = maxf(edges[1][i], float(tube.right[i]) + 0.6)
	# Fundo sob cada amostra (o mais baixo entre as duas bordas e o meio)
	var ground := PackedFloat32Array()
	ground.resize(n)
	for i in n:
		var l := p.points[i] + p.lefts[i] * float(edges[0][i])
		var r := p.points[i] - p.lefts[i] * float(edges[1][i])
		ground[i] = minf(SeaFloor.ground(track, p.points[i].x, p.points[i].z),
			minf(SeaFloor.ground(track, l.x, l.z), SeaFloor.ground(track, r.x, r.z))) - 0.5
	var mat := TrackMaterials.sea_stone("causeway", false, {"panel_size": 1.2, "grime_strength": 0.4,
		"moss_amount": 0.55, "coral_amount": 0.25, "no_outline": true})
	_rng.seed = 5151
	var start := 0
	var chunk := 0
	while start < n:
		var stop := mini(start + CHUNK, n)
		var mb := MeshBuilder.new()
		var leds := MeshBuilder.new()
		var lamps := MeshBuilder.new()
		var banners := MeshBuilder.new()
		for i in range(start, stop):
			_slab(track, mb, leds, edges, ground, i, (i + 1) % n)
		_arcades(track, mb, lamps, banners, edges, ground, p.s_at(start), p.s_at(stop - 1) + p.spacing)
		var mi := MeshInstance3D.new()
		mi.name = "Causeway%d" % chunk
		mi.mesh = mb.commit(null, mat)
		if not leds.is_empty():
			leds.commit(mi.mesh as ArrayMesh, SkyDeck.glow(0.4, 1.5, 3.4))
		if not lamps.is_empty():
			lamps.commit(mi.mesh as ArrayMesh, SkyDeck.glow(0.0, 1.4, 3.6))
		if not banners.is_empty():
			var bmi := MeshInstance3D.new()
			bmi.name = "CausewayBanners%d" % chunk
			bmi.mesh = banners.commit(null, AtlantisRuins.banner_material())
			bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			bmi.visibility_range_end = VISIBILITY
			root.add_child(bmi)
		mi.visibility_range_end = VISIBILITY
		mi.visibility_range_end_margin = 80.0
		root.add_child(mi)
		start = stop
		chunk += 1


## Altura (m) do fundo da laje acima do leito na amostra i.
static func _clearance(track: RaceTrack, ground: PackedFloat32Array, i: int) -> float:
	return track.path.points[i].y + TOP_Y - DEPTH - ground[i]


## Uma fatia (i → j) da laje: topo, laterais com cornija e friso de LED, fundo e, onde o leito está
## perto, a parede cheia até o chão.
static func _slab(track: RaceTrack, mb: MeshBuilder, leds: MeshBuilder, edges: Array, ground: PackedFloat32Array,
		i: int, j: int) -> void:
	var p := track.path
	var el_i: float = edges[0][i]
	var el_j: float = edges[0][j]
	var er_i: float = edges[1][i]
	var er_j: float = edges[1][j]
	var s_i := p.s_at(i)
	var s_j := s_i + p.spacing
	mb.quad(_at(p, i, el_i, TOP_Y), _at(p, j, el_j, TOP_Y), _at(p, j, -er_j, TOP_Y), _at(p, i, -er_i, TOP_Y), STONE * 0.95, Vector3.UP)
	var solid := _clearance(track, ground, i) < PLINTH or _clearance(track, ground, j) < PLINTH
	for side: int in [1, -1]:
		var e_i: float = el_i if side > 0 else er_i
		var e_j: float = el_j if side > 0 else er_j
		var out := p.lefts[i] * side
		# Cornija (um pouco para fora), face da laje e friso de LED logo abaixo da cornija
		var c_i := e_i + 0.3
		var c_j := e_j + 0.3
		_face(mb, p, i, j, side, c_i, c_j, TOP_Y - CORNICE, TOP_Y, STONE, out)
		mb.quad(_at(p, i, side * e_i, TOP_Y - CORNICE), _at(p, j, side * e_j, TOP_Y - CORNICE),
			_at(p, j, side * c_j, TOP_Y - CORNICE), _at(p, i, side * c_i, TOP_Y - CORNICE), STONE_DARK, Vector3.DOWN)
		var bottom_i := TOP_Y - DEPTH
		var bottom_j := TOP_Y - DEPTH
		if solid:
			bottom_i = ground[i] - p.points[i].y
			bottom_j = ground[j] - p.points[j].y
		_face(mb, p, i, j, side, e_i, e_j, minf(bottom_i, TOP_Y - DEPTH), TOP_Y - CORNICE, STONE_DARK * 1.15, out,
			minf(bottom_j, TOP_Y - DEPTH))
		if not solid and _rng.randf() < 0.32:
			SeaReef.hang(_at(p, i, side * (c_i - 0.1), TOP_Y - CORNICE - 0.02), _rng.randf_range(1.2, 4.5), _rng)
		var y0 := TOP_Y - CORNICE - 0.12
		var y1 := TOP_Y - CORNICE - 0.32
		var l_i := e_i + 0.03
		var l_j := e_j + 0.03
		if side > 0:
			leds.quad(_at(p, i, l_i, y1), _at(p, j, l_j, y1), _at(p, j, l_j, y0), _at(p, i, l_i, y0), LED, out,
				Vector2(s_i, 1), Vector2(s_j, 1), Vector2(s_j, 0), Vector2(s_i, 0))
		else:
			leds.quad(_at(p, i, -l_i, y0), _at(p, j, -l_j, y0), _at(p, j, -l_j, y1), _at(p, i, -l_i, y1), LED, out,
				Vector2(s_i, 0), Vector2(s_j, 0), Vector2(s_j, 1), Vector2(s_i, 1))
	if not solid:
		mb.quad(_at(p, i, -er_i, TOP_Y - DEPTH), _at(p, j, -er_j, TOP_Y - DEPTH),
			_at(p, j, el_j, TOP_Y - DEPTH), _at(p, i, el_i, TOP_Y - DEPTH), STONE_DARK, Vector3.DOWN)


## Face lateral vertical (do lado `side`) entre as alturas y0 e y1 (relativas à pista), a `e` m do centro.
static func _face(mb: MeshBuilder, p: TrackPath, i: int, j: int, side: int, e_i: float, e_j: float, y0: float, y1: float,
		color: Color, out: Vector3, y0_j := INF) -> void:
	var b_j := y0 if y0_j == INF else y0_j
	mb.quad(_at(p, i, side * e_i, y0), _at(p, j, side * e_j, b_j), _at(p, j, side * e_j, y1), _at(p, i, side * e_i, y1), color, out)


## Pilares e arcos entre s0 e s1: um pilar a cada PIER_SPACING m (no s múltiplo, para os pedaços
## vizinhos não repetirem) e os arcos entre dois pilares, em andares.
static func _arcades(track: RaceTrack, mb: MeshBuilder, lamps: MeshBuilder, banners: MeshBuilder, edges: Array,
		ground: PackedFloat32Array, s0: float, s1: float) -> void:
	var p := track.path
	var k0 := int(ceil(s0 / PIER_SPACING))
	var k1 := int(floor((s1 - 0.001) / PIER_SPACING))
	for k in range(k0, k1 + 1):
		var s := k * PIER_SPACING
		if s >= p.length - PIER_SPACING * 0.5:
			continue
		var i := p.index_at(s)
		var h := _clearance(track, ground, i)
		if h < PLINTH:
			continue
		_pier(track, mb, lamps, banners, edges, ground, s, k)
		var s_next := minf((k + 1) * PIER_SPACING, p.length)
		var j := p.index_at(fposmod(s_next, p.length))
		if _clearance(track, ground, j) >= PLINTH:
			_arch_span(track, mb, edges, ground, s, s_next)


## Pilar: do leito até o fundo da laje, com base mais larga e impostas na linha de cada andar; nas
## duas faces de fora, a pilastra saliente (com o capitel em cada andar), a lanterna e o estandarte
## (nos pilares de número k múltiplo de LANTERN_EVERY e BANNER_EVERY).
static func _pier(track: RaceTrack, mb: MeshBuilder, lamps: MeshBuilder, banners: MeshBuilder, edges: Array,
		ground: PackedFloat32Array, s: float, k: int) -> void:
	var p := track.path
	var i := p.index_at(s)
	var el: float = edges[0][i]
	var er: float = edges[1][i]
	var width := el + er
	var top := TOP_Y - DEPTH
	var bottom := ground[i] - p.points[i].y
	var f := p.frame_at(s, (el - er) * 0.5, 0.0)
	var basis := f.basis
	var height := top - bottom
	mb.box(Transform3D(basis, f.origin + basis.y * (bottom + height * 0.5)), Vector3(width - 0.2, height, PIER_WIDTH), STONE_DARK * 1.1)
	mb.box(Transform3D(basis, f.origin + basis.y * (bottom + 0.8)), Vector3(width + 1.0, 1.6, PIER_WIDTH + 1.2), STONE_DARK)
	var tiers := _tiers(height)
	for t in range(1, tiers):
		var y := top - height * t / tiers
		mb.box(Transform3D(basis, f.origin + basis.y * y), Vector3(width + 0.4, 0.6, PIER_WIDTH + 0.6), STONE)
	for side: float in [1.0, -1.0]:
		var foot := f.origin + basis.y * (bottom + 0.2) + basis.x * side * (width * 0.5 + 1.2)
		SeaReef.cluster(foot, 3.0, _rng, _rng.randi_range(3, 7))
		if _rng.randf() < 0.5:
			SeaReef.moss(f.origin + basis.y * (bottom + 1.65) + basis.x * side * (width * 0.5 + 0.2), 0.9, _rng)
	# Pilastras nas faces de fora (pela borda de cada lado), com um capitel em cada andar
	var tangent := p.tangents[i].normalized()
	var flat := Basis(p.lefts[i], Vector3.UP, tangent).orthonormalized()
	for side: int in [1, -1]:
		var e: float = (el if side > 0 else er)
		var face := p.points[i] + p.lefts[i] * side * (e + 0.55)
		mb.box(Transform3D(flat, face + Vector3.UP * (bottom + height * 0.5)), Vector3(1.3, height, 3.0), STONE)
		# (base em degrau e um capitel escuro em cada andar)
		mb.box(Transform3D(flat, face + Vector3.UP * (bottom + 1.0) + p.lefts[i] * side * 0.2), Vector3(1.9, 2.0, 3.8), STONE_DARK)
		for t in range(1, tiers + 1):
			var y := top - height * t / tiers
			mb.box(Transform3D(flat, face + Vector3.UP * (y + 0.4) + p.lefts[i] * side * 0.15), Vector3(1.8, 0.7, 3.6), STONE_DARK)
		mb.box(Transform3D(flat, face + Vector3.UP * (top - 0.35) + p.lefts[i] * side * 0.15), Vector3(1.8, 0.7, 3.7), STONE_DARK)
		var out := p.lefts[i] * side
		if k % LANTERN_EVERY == 0:
			AtlantisRuins.lantern(mb, lamps, face + out * 1.05 + Vector3.UP * (top - minf(height * 0.35, 6.0)))
		if k % BANNER_EVERY == 2:
			AtlantisRuins.add_banner(banners, face + out * 0.5 + Vector3.UP * (top - 0.7), tangent, out, 2.0, minf(6.5, height * 0.6))


static func _tiers(height: float) -> int:
	return maxi(int(ceil(height / TIER)), 1)


## Arcos entre os pilares em s_a e s_b: em cada andar, o tímpano (das duas faces) entre o
## intradorso do arco e o topo do andar, e o intradorso por baixo; entre os andares, uma faixa.
static func _arch_span(track: RaceTrack, mb: MeshBuilder, edges: Array, ground: PackedFloat32Array, s_a: float, s_b: float) -> void:
	var p := track.path
	var ia := p.index_at(s_a)
	var ib := p.index_at(fposmod(s_b, p.length))
	var height := minf(_clearance(track, ground, ia), _clearance(track, ground, ib))
	var tiers := _tiers(height)
	var tier_h := height / tiers
	var span := s_b - s_a
	var open := span - PIER_WIDTH
	var top := TOP_Y - DEPTH
	for t in tiers:
		var tier_top := top - tier_h * t
		var rise := minf(open * 0.5, tier_h * 0.45)
		var spring := tier_top - maxf(rise + 0.8, tier_h * 0.35)
		for u in ARC_STEPS:
			var u0 := float(u) / ARC_STEPS
			var u1 := float(u + 1) / ARC_STEPS
			var sa := s_a + PIER_WIDTH * 0.5 + open * u0
			var sb := s_a + PIER_WIDTH * 0.5 + open * u1
			var ya := spring + rise * sqrt(maxf(1.0 - pow(u0 * 2.0 - 1.0, 2.0), 0.0))
			var yb := spring + rise * sqrt(maxf(1.0 - pow(u1 * 2.0 - 1.0, 2.0), 0.0))
			var i0 := p.index_at(sa)
			var i1 := p.index_at(sb)
			for side: int in [1, -1]:
				var e0: float = (edges[0][i0] if side > 0 else edges[1][i0]) - 0.1
				var e1: float = (edges[0][i1] if side > 0 else edges[1][i1]) - 0.1
				var out := p.lefts[i0] * side
				var a0 := p.frame_at(sa, side * e0, ya).origin
				var b0 := p.frame_at(sb, side * e1, yb).origin
				var a1 := p.frame_at(sa, side * e0, tier_top).origin
				var b1 := p.frame_at(sb, side * e1, tier_top).origin
				mb.quad(a0, b0, b1, a1, STONE * 0.98, out)
			# Intradorso (a face de baixo do arco, de uma face à outra)
			var l0 := p.frame_at(sa, float(edges[0][i0]) - 0.1, ya).origin
			var l1 := p.frame_at(sb, float(edges[0][i1]) - 0.1, yb).origin
			var r0 := p.frame_at(sa, -float(edges[1][i0]) + 0.1, ya).origin
			var r1 := p.frame_at(sb, -float(edges[1][i1]) + 0.1, yb).origin
			# (a face olha para o centro do arco, na linha de nascença)
			var center := p.frame_at(s_a + span * 0.5, 0.0, spring - 0.5).origin
			mb.quad(l0, l1, r1, r0, STONE_DARK, (center - (l0 + l1 + r0 + r1) * 0.25).normalized())
		# Aduelas (o anel saliente em volta do arco, nas duas faces) e a pedra de fecho
		var mid_s := s_a + span * 0.5
		for side: int in [1, -1]:
			var e_c: float = edges[0][ia] if side > 0 else edges[1][ia]
			# (aduelas de verdade: caixas saindo 0,6 m da face, pedra clara e tijolo alternados)
			var lat := side * (e_c + 0.2)
			for u in ARC_STEPS:
				var mids: Array[Vector3] = []
				for uu: float in [float(u) / ARC_STEPS, float(u + 1) / ARC_STEPS]:
					var c := uu * 2.0 - 1.0
					var h := sqrt(maxf(1.0 - c * c, 0.0))
					mids.append(p.frame_at(mid_s + c * (open * 0.5 + BAND * 0.5), lat, spring + (rise + BAND * 0.5) * h).origin)
				var along := mids[1] - mids[0]
				var ax := along.normalized()
				var az := p.lefts[ia] * side
				var ay := az.cross(ax).normalized()
				if ay.y < 0.0:
					ay = -ay
				mb.box(Transform3D(Basis(ax, ay, ax.cross(ay)).orthonormalized(), (mids[0] + mids[1]) * 0.5),
					Vector3(along.length() + 0.06, BAND, 0.7), STONE if u % 2 == 0 else AtlantisRuins.BRICK)
			var key := p.frame_at(mid_s, side * (e_c + 0.35), spring + rise + BAND * 0.55)
			mb.box(Transform3D(key.basis, key.origin), Vector3(1.0, BAND * 1.7, 1.3), STONE)
		for k in 2:
			if _rng.randf() < 0.7:
				var lat := lerpf(-float(edges[1][ia]), float(edges[0][ia]), _rng.randf_range(0.1, 0.9))
				SeaReef.hang(p.frame_at(s_a + span * 0.5 + _rng.randf_range(-2.0, 2.0), lat, spring + rise - 0.05).origin,
					_rng.randf_range(1.5, minf(5.0, rise + 1.0)), _rng)
		if t > 0:
			# Cornija entre os andares (saliente, com a faixa escura embaixo)
			var f := p.frame_at((s_a + s_b) * 0.5, (float(edges[0][ia]) - float(edges[1][ia])) * 0.5, tier_top)
			mb.box(Transform3D(f.basis, f.origin + f.basis.y * 0.15), Vector3(float(edges[0][ia]) + float(edges[1][ia]) + 2.4, 0.6, span),
				STONE)
			mb.box(Transform3D(f.basis, f.origin - f.basis.y * 0.35), Vector3(float(edges[0][ia]) + float(edges[1][ia]) + 1.4, 0.4, span),
				STONE_DARK)


static func _at(p: TrackPath, i: int, lateral: float, y: float) -> Vector3:
	return p.points[i] + p.lefts[i] * lateral + Vector3.UP * y
