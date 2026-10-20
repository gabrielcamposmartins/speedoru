class_name CanyonRuins
extends RefCounted
## Ruínas de Atlântida perto da pista (pista no fundo do mar), para dar variedade aos cânions:
##  * pontes de pedra atravessando o cânion com um arco grande por cima do túnel e do tubo (o arco
##    acompanha a seção dele, com os pés no fundo dos dois lados), onde há espaço até a superfície
##    (algumas com o tabuleiro desabado no meio), com algas, estandartes e lanternas;
##  * fachadas de templo esculpidas nas paredes do cânion (colunas na frente, entablamento e frontão
##    entrando na rocha, a porta escura e uma estátua ou estandartes);
##  * colunas quebradas e tambores caídos nos patamares das paredes;
##  * nos trechos abertos (sem cânion), aquedutos em ruínas ao lado do tubo (AtlantisRuins.aqueduct:
##    dois andares, contrafortes, o canal no alto, pontas e vãos desabados).
## Tudo em pedra (sea_stone), com corais, algas e musgo (SeaReef). Nada tem colisão nem invade o tubo.

const BRIDGES := 6
const BRIDGE_SPACING := 140.0
## Folga do intradorso das pontes até o tubo e a largura das aduelas (m).
const GAP := 2.5
const RING := 1.5
const FACADE_SPACING := 210.0
const LEDGE_SPACING := 46.0
const AQUEDUCT_SPACING := 150.0


static func build(track: RaceTrack, parent: Node3D) -> void:
	var data := SeaCanyon.profile(track)
	var root := Node3D.new()
	root.name = "CanyonRuins"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5511
	var stone := MeshBuilder.new()
	var banners := MeshBuilder.new()
	var lamps := MeshBuilder.new()
	var statues: Array = []
	var points: Array = []
	var bridges := _bridges(track, data, stone, banners, lamps, points, rng)
	var facades := _facades(track, data, stone, banners, lamps, statues, points, bridges, rng)
	_ledges(track, data, stone, points, bridges, rng)
	var aqueduct_at: Array[Vector3] = []
	var aqueducts := _open_aqueducts(track, stone, lamps, banners, points, aqueduct_at, rng)
	AtlantisRuins._commit(root, "Ruins", stone, lamps, banners, false)
	AtlantisRuins.place_statues(root, statues)
	root.set_meta("bridges", bridges.size())
	root.set_meta("bridge_s", bridges)
	root.set_meta("facades", facades.size())
	root.set_meta("facade_at", facades)
	root.set_meta("aqueducts", aqueducts)
	root.set_meta("aqueduct_at", aqueduct_at)
	root.set_meta("points", PackedVector3Array(points))


## s está a menos de `reach` m (ao longo da pista) de algum dos pontos da lista.
static func _near(track: RaceTrack, list: Array[float], s: float, reach: float) -> bool:
	var length := track.path.length
	for o in list:
		if absf(fposmod(s - o + length * 0.5, length) - length * 0.5) < reach:
			return true
	return false


## Altura do teto do tubo (ou do túnel de cristal) na amostra i.
static func _tube_top(track: RaceTrack, i: int) -> float:
	var tube := SeaTube.profile(track)
	var h := 0.0
	if track.in_tunnel(i):
		h = GlassTunnel.HEIGHT
	elif tube.on[i] == 1:
		h = tube.height[i]
	return track.path.points[i].y + h


# ---------------------------------------------------------------------------
# Pontes de aqueduto sobre o cânion
# ---------------------------------------------------------------------------
static func _bridges(track: RaceTrack, data: Dictionary, stone: MeshBuilder, banners: MeshBuilder, lamps: MeshBuilder,
		points: Array, rng: RandomNumberGenerator) -> Array[float]:
	var p := track.path
	var water := track.layout.water_level
	var w: PackedFloat32Array = data.w
	var e: PackedFloat32Array = data.e
	# Onde cabe: o arco passa por cima do tubo e o tabuleiro fica abaixo da superfície
	var cands: Array[int] = []
	for i in range(0, p.size(), 6):
		# (longe do Portal de Atlântida, que já passa por cima da pista)
		var portal := absf(p.s_at(i) - AtlantisRuins.PORTAL_S) < 45.0
		var covered: bool = track.in_tunnel(i) or SeaTube.profile(track).on[i] == 1
		if w[i] > 0.95 and e[i] < 0.05 and covered and not portal and _tube_top(track, i) + 8.5 < water - 2.0:
			cands.append(i)
	for k in range(cands.size() - 1, 0, -1):
		var j := rng.randi() % (k + 1)
		var t := cands[k]
		cands[k] = cands[j]
		cands[j] = t
	var chosen: Array[float] = []
	for i in cands:
		if chosen.size() >= BRIDGES:
			break
		var s := p.s_at(i)
		var far := true
		for o in chosen:
			if absf(fposmod(s - o + p.length * 0.5, p.length) - p.length * 0.5) < BRIDGE_SPACING:
				far = false
		if far and _bridge(track, data, i, stone, banners, lamps, points, rng):
			chosen.append(s)
	return chosen


## Ponte de parede a parede com um arco grande por cima do tubo: o intradorso acompanha a seção do tubo
## (ou do túnel de cristal) GAP m por fora, com os pés no fundo dos dois lados dele; aduelas e fecho
## marcados, tímpanos, cornija e tabuleiro com mureta abaixo da superfície. Às vezes o tabuleiro
## desabou no meio (sobra o arco). Falso se não cabe (paredes mais baixas que o tabuleiro).
static func _bridge(track: RaceTrack, data: Dictionary, i: int, stone: MeshBuilder, banners: MeshBuilder, lamps: MeshBuilder,
		points: Array, rng: RandomNumberGenerator) -> bool:
	var p := track.path
	var water := track.layout.water_level
	var tube := SeaTube.profile(track)
	var tunnel := track.in_tunnel(i)
	var ring := func(t: float, out: float) -> Vector3:
		return GlassTunnel._arc(track, i, t, -out) if tunnel else SeaTube.point(track, tube, i, t, -out)
	var tube_top: Vector3 = ring.call(0.5, 0.0)
	var crown: Vector3 = ring.call(0.5, GAP + RING)
	var y_deck := minf(water - 2.0, crown.y + rng.randf_range(2.5, 4.0))
	if float(data.top[0][i]) < y_deck + 1.0 or float(data.top[1][i]) < y_deck + 1.0:
		return false
	var c := p.points[i]
	var lv := p.lefts[i]
	var fwd := p.tangents[i]
	fwd.y = 0.0
	fwd = fwd.normalized()
	var lat_of := func(q: Vector3) -> float: return (q - c).dot(lv)
	var at := func(lat: float, y: float) -> Vector3:
		var b := c + lv * lat
		return Vector3(b.x, y, b.z)
	# Pontas: 2 m para dentro da rocha de cada parede, na altura do tabuleiro
	var lat_l: float = lat_of.call(SeaCanyon.face_at(track, data, i, 1, y_deck)) + 2.0
	var lat_r: float = lat_of.call(SeaCanyon.face_at(track, data, i, -1, y_deck)) - 2.0
	var floor_y := float(data.floor[i]) - 1.0
	var half := rng.randf_range(2.2, 3.0)
	var segs := 28
	var intra: Array[Vector3] = []
	var extra: Array[Vector3] = []
	for k in segs + 1:
		intra.append(ring.call(float(k) / segs, GAP))
		extra.append(ring.call(float(k) / segs, GAP + RING))
	var jamb_r: float = lat_of.call(intra[0])
	var jamb_l: float = lat_of.call(intra[segs])
	var mid_lat: float = lat_of.call(crown)
	# (desabada: sem tabuleiro, tímpano e cornija entre as aduelas k_a e k_b, perto do fecho)
	var k_a := segs + 1
	var k_b := -1
	if rng.randf() < 0.3:
		for k in segs + 1:
			if absf(float(lat_of.call(intra[k])) - mid_lat) < (jamb_l - jamb_r) * 0.11:
				k_a = mini(k_a, k)
				k_b = maxi(k_b, k)
	var broken := k_b > k_a
	var center: Vector3 = at.call(mid_lat, c.y + (tube_top.y - c.y) * 0.4)
	for sgn: float in [1.0, -1.0]:
		var o := fwd * half * sgn
		var n := fwd * sgn
		# Faces: de parede a pé do arco (do fundo ao tabuleiro), sobre o arco (do intradorso ao
		# tabuleiro) e as aduelas um pouco salientes
		for part: Vector2 in [Vector2(lat_r, jamb_r), Vector2(jamb_l, lat_l)]:
			stone.quad(at.call(part.x, floor_y) + o, at.call(part.y, floor_y) + o, at.call(part.y, y_deck) + o, at.call(part.x, y_deck) + o,
				AtlantisRuins.STONE, n)
		for k in segs:
			var q0 := intra[k]
			var q1 := intra[k + 1]
			var lat0: float = lat_of.call(q0)
			var lat1: float = lat_of.call(q1)
			var cut := k >= k_a and k + 1 <= k_b
			var y_top0 := extra[k].y if cut else y_deck
			var y_top1 := extra[k + 1].y if cut else y_deck
			stone.quad(q0 + o, q1 + o, at.call(lat1, y_top1) + o, at.call(lat0, y_top0) + o, AtlantisRuins.STONE, n)
			# (aduelas alternando pedra escura e tijolo, de duas em duas, como nos aquedutos)
			var out := fwd * (half + 0.18) * sgn
			stone.quad(q0 + out, q1 + out, extra[k + 1] + out, extra[k] + out,
				AtlantisRuins.STONE_DARK if (k / 2) % 2 == 0 else AtlantisRuins.BRICK, n)
	# Intradorso (por baixo do arco) e as faces de dentro dos pés, do fundo até a pista
	for k in segs:
		var q0 := intra[k]
		var q1 := intra[k + 1]
		var nrm := (q1 - q0).cross(fwd).normalized()
		if nrm.dot(center - (q0 + q1) * 0.5) < 0.0:
			nrm = -nrm
		stone.quad(q0 - fwd * half, q1 - fwd * half, q1 + fwd * half, q0 + fwd * half, AtlantisRuins.STONE_DARK, nrm)
		if k % 2 == 0:
			points.append((q0 + q1) * 0.5)
	for jamb: Vector2 in [Vector2(jamb_r, 1.0), Vector2(jamb_l, -1.0)]:
		var base_y: float = c.y
		stone.quad(at.call(jamb.x, floor_y) - fwd * half, at.call(jamb.x, floor_y) + fwd * half,
			at.call(jamb.x, base_y) + fwd * half, at.call(jamb.x, base_y) - fwd * half, AtlantisRuins.STONE, lv * jamb.y)
		points.append(at.call(jamb.x - jamb.y * 1.0, (floor_y + base_y) * 0.5))
	# Fecho saliente
	var key := (intra[segs / 2] + extra[segs / 2]) * 0.5 + Vector3.UP * 0.3
	stone.box(Transform3D(Basis(lv, Vector3.UP, fwd), key), Vector3(1.8, RING + 0.9, half * 2.0 + 0.5), AtlantisRuins.STONE_DARK)
	# Medalhão dourado com o tridente nas duas faces do fecho
	for sgn: float in [1.0, -1.0]:
		var face := key + fwd * (half + 0.3) * sgn
		var disc := Basis(lv, fwd * sgn, lv.cross(fwd * sgn)).orthonormalized()
		stone.cylinder(Transform3D(disc, face - fwd * 0.05 * sgn), 0.7, 0.7, 0.12, SeaTube.GOLD, 12)
		var flat := Basis(lv, Vector3.UP, fwd * sgn).orthonormalized()
		var relief := face + fwd * 0.08 * sgn
		stone.box(Transform3D(flat, relief + Vector3.DOWN * 0.1), Vector3(0.09, 0.8, 0.06), AtlantisRuins.STONE_DARK)
		stone.box(Transform3D(flat, relief + Vector3.UP * 0.14), Vector3(0.48, 0.08, 0.06), AtlantisRuins.STONE_DARK)
		for tx: float in [-0.2, 0.0, 0.2]:
			stone.box(Transform3D(flat, relief + lv * tx + Vector3.UP * 0.3), Vector3(0.07, 0.3, 0.06), AtlantisRuins.STONE_DARK)
	# Tabuleiro, cornija e mureta (interrompidos na parte desabada)
	var spans: Array[Vector2] = [Vector2(lat_r, lat_l)]
	if broken:
		spans = [Vector2(lat_r, lat_of.call(intra[k_a])), Vector2(lat_of.call(intra[k_b]), lat_l)]
	for sp in spans:
		var length := sp.y - sp.x
		var mid := (sp.x + sp.y) * 0.5
		stone.quad(at.call(sp.x, y_deck) - fwd * half, at.call(sp.y, y_deck) - fwd * half, at.call(sp.y, y_deck) + fwd * half,
			at.call(sp.x, y_deck) + fwd * half, AtlantisRuins.STONE, Vector3.UP)
		stone.box(Transform3D(Basis(lv, Vector3.UP, fwd), at.call(mid, y_deck - 0.45)), Vector3(length, 0.6, half * 2.0 + 0.5),
			AtlantisRuins.STONE_DARK)
		for sgn: float in [1.0, -1.0]:
			stone.box(Transform3D(Basis(lv, Vector3.UP, fwd), at.call(mid, y_deck + 0.5) + fwd * (half - 0.3) * sgn),
				Vector3(length, 1.0, 0.5), AtlantisRuins.STONE_DARK)
		points.append(at.call(mid, y_deck))
	if broken:
		# Pontas da quebra: o corte do tímpano, o topo do arco à mostra e pedras caídas
		for edge: Vector2i in [Vector2i(k_a, 1), Vector2i(k_b, -1)]:
			var lat: float = lat_of.call(intra[edge.x])
			var y0: float = extra[edge.x].y
			stone.quad(at.call(lat, y0) - fwd * half, at.call(lat, y0) + fwd * half, at.call(lat, y_deck) + fwd * half,
				at.call(lat, y_deck) - fwd * half, AtlantisRuins.STONE_DARK, lv * edge.y)
			stone.blob(at.call(lat, y_deck), Vector3(1.3, 0.9, half), AtlantisRuins.STONE_DARK, 7, 4, 0.2)
		for k in range(k_a, k_b):
			var a0: Vector3 = at.call(lat_of.call(intra[k]), extra[k].y)
			var a1: Vector3 = at.call(lat_of.call(intra[k + 1]), extra[k + 1].y)
			stone.quad(a0 - fwd * half, a1 - fwd * half, a1 + fwd * half, a0 + fwd * half, AtlantisRuins.STONE, Vector3.UP)
	# Estandartes nas duas faces (sobre os pés; no meio só se o tabuleiro está inteiro) e lanternas
	var hang := clampf(y_deck - 0.9 - tube_top.y - 0.8, 1.5, 4.2)
	for sgn: float in [1.0, -1.0]:
		for lat: float in [jamb_r - 1.6, jamb_l + 1.6]:
			AtlantisRuins.add_banner(banners, at.call(lat, y_deck - 0.9) + fwd * (half + 0.3) * sgn, lv, fwd * sgn, 2.4, 5.4)
		if not broken:
			AtlantisRuins.add_banner(banners, at.call(mid_lat, y_deck - 0.9) + fwd * (half + 0.3) * sgn, lv, fwd * sgn, 2.6, hang)
	for u: float in [0.1, 0.9]:
		AtlantisRuins.lantern(stone, lamps, at.call(lerpf(lat_r, lat_l, u), y_deck + 1.9) + fwd * (half - 0.3))
	# Algas curtas penduradas perto do fecho (sem encostar no tubo) e corais em cima
	for k in range(segs / 3, segs * 2 / 3):
		if rng.randf() < 0.5:
			SeaReef.hang((intra[k] + intra[k + 1]) * 0.5 + fwd * rng.randf_range(-half, half) * 0.8, rng.randf_range(0.6, GAP - 0.7), rng)
	for k in 6:
		var lat := lerpf(lat_r + 2.0, lat_l - 2.0, rng.randf())
		if not broken or lat < float(lat_of.call(intra[k_a])) or lat > float(lat_of.call(intra[k_b])):
			SeaReef.cluster(at.call(lat, y_deck), 1.4, rng, 2)
	return true


# ---------------------------------------------------------------------------
# Fachadas esculpidas nas paredes
# ---------------------------------------------------------------------------
static func _facades(track: RaceTrack, data: Dictionary, stone: MeshBuilder, banners: MeshBuilder, lamps: MeshBuilder,
		statues: Array, points: Array, bridges: Array[float], rng: RandomNumberGenerator) -> Array[Vector2]:
	var p := track.path
	var water := track.layout.water_level
	var w: PackedFloat32Array = data.w
	var e: PackedFloat32Array = data.e
	var made: Array[Vector2] = []
	var side := 1
	var s := 60.0
	while s < p.length:
		var i := p.index_at(s)
		var k := 0 if side > 0 else 1
		var gap: float = float(data.foot[k][i]) - SeaTube.clearance(track, i, side)
		var height: float = float(data.top[k][i]) - float(data.floor[i])
		if w[i] > 0.97 and e[i] < 0.05 and gap > 3.5 and height > 22.0 and float(data.top[k][i]) < water - 1.0 				and not _near(track, bridges, s, 24.0):
			if _facade(track, data, s, side, stone, banners, lamps, statues, points, rng):
				made.append(Vector2(s, side))
				side = -side
				s += FACADE_SPACING
				continue
		s += 20.0
	return made


## Fachada de templo na parede do lado `side` em s: colunas no pé da parede, entablamento e frontão
## entrando na rocha, degraus, a porta escura e uma estátua (ou estandartes) no meio.
static func _facade(track: RaceTrack, data: Dictionary, s: float, side: int, stone: MeshBuilder, banners: MeshBuilder,
		lamps: MeshBuilder, statues: Array, points: Array, rng: RandomNumberGenerator) -> bool:
	var p := track.path
	var i := p.index_at(s)
	var k := 0 if side > 0 else 1
	var foot: float = data.foot[k][i]
	var fl: float = data.floor[i]
	# (par: a estátua fica no vão do meio)
	var cols := 4 if rng.randf() < 0.5 else 6
	var step := 4.4
	var width := (cols - 1) * step
	var h := rng.randf_range(10.0, 13.0)
	var r := 0.72
	var out := -p.lefts[i] * side
	var fwd := p.tangents[i]
	fwd.y = 0.0
	fwd = fwd.normalized()
	# A rocha tem que estar atrás (as pontas da fachada também dentro do cânion)
	for d: float in [-width * 0.5 - 3.0, width * 0.5 + 3.0]:
		var j := p.index_at(s + d)
		if float(data.w[j]) < 0.95 or SeaTube.blocked(track, p.frame_at(s + d, side * (foot - 1.0), 0.0).origin + Vector3.UP * 4.0, 1.0):
			return false
	var lat := foot - 1.3
	var center := p.frame_at(s, side * lat, 0.0).origin
	center.y = fl
	var basis := Basis(fwd, Vector3.UP, out).orthonormalized()
	# Degraus e piso
	for st in 2:
		stone.box(Transform3D(basis, center + out * (0.8 - st * 0.9) + Vector3.UP * (0.3 + st * 0.6) - out * 0.0),
			Vector3(width + 5.0 - st * 1.6, 0.6, 4.0 - st * 1.0), AtlantisRuins.STONE_DARK)
	var base_y := fl + 1.2
	# Colunas
	for c in cols:
		var at := center + fwd * (c * step - width * 0.5)
		at.y = base_y
		var broken := rng.randf_range(0.3, 0.6) if rng.randf() < 0.18 else 0.0
		AtlantisRuins.column(stone, at, h, r, broken)
		points.append(at + Vector3.UP * h * 0.5)
	# Porta escura atrás das colunas do meio (um vão na rocha)
	stone.box(Transform3D(basis, center - out * 2.4 + Vector3.UP * (base_y - fl + 4.0)), Vector3(step * 1.6, 8.0, 3.0),
		AtlantisRuins.STONE_DARK * 0.28)
	# Entablamento e frontão entrando na rocha
	var top_y := base_y + h + 0.6
	var depth := 9.0
	stone.box(Transform3D(basis, center - out * (depth * 0.5 - 1.6) + Vector3.UP * (top_y - fl + 0.8)),
		Vector3(width + 3.0, 1.6, depth), AtlantisRuins.STONE)
	var ped_h := 3.2
	var front := center + out * 1.6
	var l := front - fwd * (width * 0.5 + 1.5) + Vector3.UP * (top_y + 1.6 - fl)
	var rr := front + fwd * (width * 0.5 + 1.5) + Vector3.UP * (top_y + 1.6 - fl)
	var apex := front + Vector3.UP * (top_y + 1.6 + ped_h - fl)
	stone.tri(l, rr, apex, AtlantisRuins.STONE, out)
	var back := -out * (depth - 1.6)
	stone.quad(l, apex, apex + back, l + back, AtlantisRuins.STONE_DARK, (Vector3.UP - fwd).normalized())
	stone.quad(apex, rr, rr + back, apex + back, AtlantisRuins.STONE_DARK, (Vector3.UP + fwd).normalized())
	# No meio: estátua ou estandartes; lanternas nas pontas
	if rng.randf() < 0.55:
		var model := "poseidon_standing" if rng.randf() < 0.6 else "poseidon_seated"
		# (os modelos têm a frente em +Z)
		statues.append([model, Transform3D(Basis.looking_at(-out).scaled(Vector3.ONE * 0.75), center - out * 0.6 + Vector3.UP * (base_y - fl))])
	else:
		for d: float in [-step * 0.5, step * 0.5]:
			AtlantisRuins.add_banner(banners, center + fwd * d + out * 1.0 + Vector3.UP * (top_y - fl - 0.2), fwd, out, 2.0, 6.5)
	for d: float in [-width * 0.5 - 1.6, width * 0.5 + 1.6]:
		AtlantisRuins.lantern(stone, lamps, center + fwd * d + out * 0.6 + Vector3.UP * (base_y - fl + 3.0))
	# Corais nos degraus, algas no entablamento, musgo no frontão
	SeaReef.cluster(center + out * 1.2 + Vector3.UP * (base_y - fl - 0.5), width * 0.5, rng, 6)
	for n in 4:
		SeaReef.hang(front - fwd * rng.randf_range(-width * 0.5, width * 0.5) + Vector3.UP * (top_y - fl), rng.randf_range(1.5, 3.5), rng)
	SeaReef.moss(apex - out * 1.5, 1.6, rng)
	return true


# ---------------------------------------------------------------------------
# Colunas nos patamares
# ---------------------------------------------------------------------------
static func _ledges(track: RaceTrack, data: Dictionary, stone: MeshBuilder, points: Array, bridges: Array[float],
		rng: RandomNumberGenerator) -> void:
	var p := track.path
	var water := track.layout.water_level
	var w: PackedFloat32Array = data.w
	var e: PackedFloat32Array = data.e
	var s := 30.0
	var side := 1
	while s < p.length:
		var i := p.index_at(s)
		if w[i] > 0.95 and e[i] < 0.2 and not _near(track, bridges, s, 10.0):
			var col := SeaCanyon.column(track, data, i, side)
			var lr: Vector2i = SeaCanyon.ledge_rings()[rng.randi() % 2]
			var at: Vector3 = (col[lr.x] + col[lr.y]) * 0.5
			if at.y < water - 8.0:
				for n in rng.randi_range(1, 3):
					var off := p.tangents[i].normalized() * rng.randf_range(-3.0, 3.0)
					AtlantisRuins.column(stone, at + off + Vector3.DOWN * 0.2, rng.randf_range(4.0, 8.0), 0.55, rng.randf_range(0.25, 0.65))
				# Tambor caído
				var b := Basis(p.tangents[i].normalized(), rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5)
				stone.cylinder(Transform3D(b, at + p.tangents[i].normalized() * 4.0 + Vector3.UP * 0.4), 0.55, 0.55, 1.4,
					AtlantisRuins.STONE, 10)
				points.append(at + Vector3.UP * 2.0)
		s += LEDGE_SPACING * rng.randf_range(0.7, 1.3)
		side = -side


# ---------------------------------------------------------------------------
# Aquedutos ao lado do tubo nos trechos abertos
# ---------------------------------------------------------------------------
static func _open_aqueducts(track: RaceTrack, stone: MeshBuilder, lamps: MeshBuilder, banners: MeshBuilder, points: Array,
		spots: Array[Vector3], rng: RandomNumberGenerator) -> int:
	var p := track.path
	var water := track.layout.water_level
	var count := 0
	var side := 1
	for sp in SeaCanyon.open_spans(track):
		var s := sp.x + 70.0
		while s < sp.x + sp.y - 70.0:
			var length := rng.randf_range(50.0, 90.0)
			var i := p.index_at(s)
			var lat := side * (SeaTube.clearance(track, i, side) + rng.randf_range(9.0, 18.0))
			var a := p.frame_at(s - length * 0.5, lat, 0.0).origin
			var b := p.frame_at(s + length * 0.5, lat, 0.0).origin
			var ok := true
			var ground := INF
			for u: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var q := a.lerp(b, u)
				var g := SeaFloor.ground(track, q.x, q.z)
				ground = minf(ground, g)
				# (o leito perto da pista: nem a fossa nem a rocha; longe dos outros trechos do tubo)
				if g < p.points[i].y - 18.0 or SeaCanyon.in_rock(track, Vector3(q.x, g + 1.0, q.z)):
					ok = false
				for hy: float in [2.0, 10.0, 18.0]:
					if SeaTube.blocked(track, Vector3(q.x, g + hy, q.z), 3.5):
						ok = false
			var h1 := rng.randf_range(10.0, 13.0)
			if ok and ground + h1 * 1.62 + 1.8 < water - 3.0:
				a.y = ground - 0.5
				b.y = ground - 0.5
				var top := AtlantisRuins.aqueduct(stone, lamps, banners, a, b, h1, rng)
				for u in int(length / 12.0) + 1:
					SeaFloor.claim(a.lerp(b, u * 12.0 / length), 6.0, top)
				points.append((a + b) * 0.5 + Vector3.UP * (h1 * 0.5))
				spots.append((a + b) * 0.5)
				count += 1
				side = -side
			s += AQUEDUCT_SPACING * rng.randf_range(0.8, 1.2)
	return count
