class_name PoseidonGate
extends RefCounted
## O trecho emerso da pista no fundo do mar (Atlantis Abyss): onde a pista passa acima de
## layout.water_level ela sai da água entre montanhas, o Portão de Poseidon:
##  * a cadeia de montanhas em volta da pista são as paredes do cânion subindo acima do mar
##    (SeaCanyon), com três cachoeiras grandes e largas (cortinas de 80 a 100 m saltando do alto da
##    montanha em arco, com espuma e névoa no pé);
##  * dois aquedutos de pedra em dois andares atravessando por cima da pista, de montanha a montanha
##    (o arco grande sobre a ponte, arcos pequenos em cima e o canal com água despejando no mar), com
##    estandartes, trepadeiras penduradas, tufos de plantas nas bordas, arbustos e árvores;
##  * cipós pendendo de uma montanha à outra por cima da pista, com folhas e gavinhas, e árvores
##    gigantes saindo da face das montanhas, debruçadas sobre a pista: em vários trechos as copas dos
##    dois lados se encontram e fecham o céu (tudo a CLEARANCE m ou mais do asfalto);
##  * mastros com estandartes a cada POLE_SPACING m dos dois lados da ponte e bandeiras grandes nas
##    cristas;
##  * dois rostos gigantes de Poseidon esculpidos na face das montanhas, com cachoeiras saindo da
##    boca, Poseidon com o tridente no pico mais alto e ruínas nas cristas;
##  * o arco-íris na frente de quem passa pela ponte (só de dia), peixes-voadores e gaivotas;
##  * estandartes de Atlântida em mastros ao longo da ponte.
## Tudo aparece também na janela do céu vista de baixo d'água (SeaWorld.WINDOW_LAYER). Nada aqui tem
## colisão (as barreiras seguram o carro).

const MODELS := "res://assets/track/atlantis_abyss/models/"
## Rostos: s e lado (+1 esquerda); ficam na face da montanha.
const FACES := [[2075.0, 1], [2185.0, -1]]
## Altura (m acima da base do modelo) e avanço (+Z) da boca do rosto (blender/build_atlantis.py).
const FACE_MOUTH := Vector2(12.4, 7.2)
## Arco-íris: s do centro, distância à frente e raio.
const RAINBOW := Vector3(2140.0, 260.0, 210.0)
## Cachoeiras grandes e largas nas montanhas: [s do meio, lado (+1 esquerda), largura].
const WIDE_FALLS := [[1955.0, 1, 92.0], [2112.0, -1, 80.0], [2335.0, 1, 100.0]]
## Aquedutos atravessando por cima da pista (s) e a altura do segundo andar deles.
const AQUEDUCTS := [2030.0, 2248.0]
const AQUEDUCT_TIER := 6.5
## Cipós atravessando de uma montanha à outra por cima da pista (grupos) e árvores debruçadas sobre
## ela saindo da face das montanhas (lugares; quase sempre dos dois lados, as copas fechando o céu).
const LIANAS := 16
const CANOPIES := 10
## Trechos (s inicial, s final) em que as árvores dos dois lados fecham o céu sobre a pista (longe dos
## aquedutos, dos rostos e das cachoeiras largas).
const CANOPY_ZONES := [Vector2(1850.0, 1905.0), Vector2(2203.0, 2228.0), Vector2(2392.0, 2452.0)]
## Nada passa a menos disto acima do asfalto (carros, mastros de 11 m).
const CLEARANCE := 14.0
## Mastros de estandartes ao longo da ponte (espaço, m) e bandeiras grandes nas cristas.
const POLE_SPACING := 24.0
const CREST_FLAGS := 7
const BARK := Color(0.3, 0.22, 0.14)
const LIANA := Color(0.26, 0.24, 0.13)
const CROWNS := [Color(0.19, 0.33, 0.15), Color(0.25, 0.4, 0.17), Color(0.3, 0.44, 0.2), Color(0.22, 0.36, 0.2)]

static var _water_mats := {}
static var _rainbow: ShaderMaterial


## Trechos (s inicial, s final) em que a pista passa acima da linha d'água.
static func emerged_spans(track: RaceTrack) -> Array[Vector2]:
	var p := track.path
	var out: Array[Vector2] = []
	var water := track.layout.water_level
	var start := -1.0
	for i in p.size() + 1:
		var above := p.points[i % p.size()].y > water
		if above and start < 0.0:
			start = p.s_at(i % p.size())
		elif not above and start >= 0.0:
			out.append(Vector2(start, p.s_at(i % p.size())))
			start = -1.0
	return out


static func build(track: RaceTrack, parent: Node3D) -> void:
	var spans := emerged_spans(track)
	if spans.is_empty():
		return
	var root := Node3D.new()
	root.name = "PoseidonGate"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2828
	var p := track.path
	var water := track.layout.water_level
	var canyon := SeaCanyon.profile(track)
	var span: Vector2 = spans[0]
	var stone := MeshBuilder.new()
	var banners := MeshBuilder.new()
	var falls := MeshBuilder.new()
	var foam := MeshBuilder.new()
	var strips := MeshBuilder.new()
	var statues: Array = []
	var feet: Array[Vector3] = []
	var length := fposmod(span.y - span.x, p.length)
	# Rostos de Poseidon esculpidos na face das montanhas, com a cachoeira saindo da boca
	for f: Array in FACES:
		var s: float = f[0]
		var side: int = f[1]
		var i := p.index_at(s)
		# (encaixado na rocha: a face da montanha na altura do meio da cabeça; o queixo entra nela)
		var at := SeaCanyon.face_at(track, canyon, i, side, water + 18.0)
		var to_track := p.points[i] - at
		to_track.y = 0.0
		to_track = to_track.normalized()
		var base := Vector3(at.x, water + 5.5, at.z) + to_track * 1.0
		statues.append(["poseidon_face", Transform3D(Basis.looking_at(-to_track), base)])
		var mouth := base + to_track * FACE_MOUTH.y + Vector3.UP * FACE_MOUTH.x
		_waterfall(falls, foam, mouth, to_track, 7.0, water, feet)
	# Cachoeiras grandes e largas saltando das montanhas
	var curtains := MeshBuilder.new()
	var mist := MeshBuilder.new()
	var widths: Array[float] = []
	for wf: Array in WIDE_FALLS:
		var made := _wide_fall(track, canyon, curtains, mist, foam, feet, wf[0], wf[1], wf[2])
		if made > 0.0:
			widths.append(made)
	# Aquedutos por cima da pista, com plantas
	var channel := MeshBuilder.new()
	var vines: Array = [[], []]
	var bushes: Array = [[], []]
	var trees := {}
	var bridges := 0
	var lowest := INF
	for aq: float in AQUEDUCTS:
		var low := _aqueduct_over(track, canyon, stone, banners, falls, foam, channel, feet, vines, bushes, trees, aq, rng)
		if low < INF:
			bridges += 1
			lowest = minf(lowest, low)
	# Poseidon com o tridente no pico mais alto e ruínas nas cristas
	var best := Vector3(0, -INF, 0)
	var best_i := -1
	var best_side := 1
	for k in range(-130, int(length / p.spacing) + 130, 3):
		var i := posmod(p.index_at(span.x) + k, p.size())
		for side: int in [1, -1]:
			var col := SeaCanyon.column(track, canyon, i, side)
			var crest: Vector3 = col[SeaCanyon.top_ring() + 1]
			if crest.y > best.y:
				best = crest
				best_i = i
				best_side = side
			if crest.y > water + 20.0 and k % 51 == 0:
				for n in rng.randi_range(2, 4):
					var a := rng.randf() * TAU
					AtlantisRuins.column(stone, crest + p.lefts[i] * side * 6.0 + Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.5, 5.0)
						+ Vector3.DOWN * 1.0, rng.randf_range(7.0, 12.0), 0.8, rng.randf_range(0.2, 0.6) if rng.randf() < 0.5 else 0.0)
	if best_i >= 0:
		var to_track := p.points[best_i] - best
		to_track.y = 0.0
		statues.append(["poseidon_standing", Transform3D(Basis.looking_at(-to_track.normalized()).scaled(Vector3.ONE * 3.2),
			best + p.lefts[best_i] * best_side * 8.0 + Vector3.DOWN * 1.0)])
	# Mastros com estandartes ao longo da ponte
	var poles := int(length / POLE_SPACING)
	for k in poles:
		var s := span.x + (k + 0.5) * length / poles
		var i := p.index_at(s)
		# (só fora do tubo: dentro dele o mastro furaria o vidro)
		if p.points[i].y < water + 1.0 or SeaTube.covers(track, i):
			continue
		for side: int in [1, -1]:
			var lat := side * (track.structure_extent(i, side) - 1.0)
			var foot := p.frame_at(s, lat, 0.0).origin
			stone.cylinder(Transform3D(Basis(), foot), 0.22, 0.16, 11.0, AtlantisRuins.STONE_DARK, 8)
			stone.box(Transform3D(Basis(p.tangents[i].normalized(), Vector3.UP, p.lefts[i]).orthonormalized(), foot + Vector3.UP * 10.6),
				Vector3(2.4, 0.15, 0.15), AtlantisRuins.STONE_DARK)
			AtlantisRuins.add_banner(banners, foot + Vector3.UP * 10.5, p.tangents[i], -p.lefts[i] * side, 2.0, 5.2)
	# Cipós e árvores debruçadas sobre a pista; bandeiras nas cristas
	var bark := MeshBuilder.new()
	var crowns: Array = [[], []]
	var lianas: Array[float] = _lianas(track, canyon, bark, vines, bushes, span, rng)
	var canopies: Array[float] = _canopy_trees(track, canyon, bark, crowns, span, rng)
	var flags := _crest_flags(track, canyon, stone, banners, span, rng)
	# Espuma onde a pista entra e sai da água
	for crossing: float in [span.x, span.y]:
		_waterline_foam(track, strips, crossing)
	_commit(root, stone, banners, falls, foam, strips)
	for part: Array in [[curtains, 3, "WideFalls"], [mist, 4, "FallMist"], [channel, 0, "AqueductWater"]]:
		var mb: MeshBuilder = part[0]
		if mb.is_empty():
			continue
		var w := MeshInstance3D.new()
		w.name = part[2]
		w.mesh = mb.commit(null, water_material(part[1]))
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(w)
	if not vines[0].is_empty():
		CityProps.add_chunked(root, "Vines", vines[0], vines[1], [[SeaReef._mesh(SeaReef.Kind.STRAND), SeaReef.material(), 0.0, 900.0, false]])
	if not bushes[0].is_empty():
		CityProps.add_chunked(root, "Bushes", bushes[0], bushes[1], [[SeaReef._mesh(SeaReef.Kind.MOSS), SeaReef.material(), 0.0, 900.0, false]])
	if not trees.is_empty():
		CityProps.add_trees(root, "BridgeTrees", trees)
	if not bark.is_empty():
		var bmi := MeshInstance3D.new()
		bmi.name = "Lianas"
		bmi.mesh = bark.commit(null, TrackMaterials.sea_stone("bark", false, {"marble_mix": 0.0, "panel_size": 0.0,
			"moss_amount": 0.35, "coral_amount": 0.0, "detail_strength": 0.45}))
		bmi.visibility_range_end = 900.0
		root.add_child(bmi)
	if not crowns[0].is_empty():
		CityProps.add_chunked(root, "Canopy", crowns[0], crowns[1], [[SeaReef._mesh(SeaReef.Kind.MOSS), SeaReef.material(), 0.0, 1100.0, true]])
	root.set_meta("lianas", lianas.size())
	root.set_meta("liana_s", lianas)
	root.set_meta("canopies", canopies.size())
	root.set_meta("canopy_s", canopies)
	root.set_meta("crest_flags", flags)
	root.set_meta("waterfalls", feet)
	root.set_meta("wide_falls", widths)
	root.set_meta("falls", widths.size())
	root.set_meta("bridges", bridges)
	root.set_meta("vine_clearance", lowest)
	_rainbow_arc(track, root)
	_flying_fish(track, root, rng, span)
	_gulls(track, root, rng, span)
	AtlantisRuins.place_statues(root, statues)
	# Tudo acima do mar: aparece na janela do céu vista de baixo d'água
	for vi: VisualInstance3D in root.find_children("*", "VisualInstance3D", true, false):
		vi.layers |= SeaWorld.WINDOW_LAYER


## Cachoeira grande e larga (largura `width` m em s, no lado `side`): a água sai da borda da montanha
## (a mesma altura em toda a largura) com força, cai em arco por cima da encosta (a velocidade de cada
## coluna faz o arco passar na frente da rocha) e chega no mar com espuma e névoa no pé. Devolve a
## largura feita (0 se a montanha ali é baixa demais).
static func _wide_fall(track: RaceTrack, canyon: Dictionary, curtains: MeshBuilder, mist: MeshBuilder, foam: MeshBuilder,
		feet: Array[Vector3], s: float, side: int, width: float) -> float:
	var p := track.path
	var water := track.layout.water_level
	var n := p.size()
	var i0 := p.index_at(s)
	var half := int(width * 0.5 / p.spacing)
	var columns: Array = []
	var lip := water + 72.0
	for k in range(-half, half + 1):
		var i := posmod(i0 + k, n)
		var col := SeaCanyon.column(track, canyon, i, side)
		columns.append([i, col])
		lip = minf(lip, col[SeaCanyon.top_ring()].y - 3.0)
	if lip < water + 22.0:
		return 0.0
	var drop := lip - water + 1.5
	var rows := 18
	var speeds := PackedFloat32Array()
	for entry: Array in columns:
		var i: int = entry[0]
		var col: PackedVector3Array = entry[1]
		var inward := -p.lefts[i] * side
		var start := _face_y(col, lip)
		var need := 3.0
		for r in range(1, rows + 1):
			var d := drop * float(r) / rows
			var ahead := (_face_y(col, lip - d) - start).dot(inward)
			need = maxf(need, (ahead + 3.0) / sqrt(2.0 * d / 9.8))
		speeds.append(need)
	# (a cortina inteira com a velocidade das colunas vizinhas: sem dentes)
	var smooth := PackedFloat32Array()
	for c in speeds.size():
		var m := 0.0
		for k in range(maxi(c - 5, 0), mini(c + 6, speeds.size())):
			m = maxf(m, speeds[k])
		smooth.append(m)
	var grid: Array[PackedVector3Array] = []
	for c in columns.size():
		var i: int = columns[c][0]
		var col: PackedVector3Array = columns[c][1]
		var inward := -p.lefts[i] * side
		var start := _face_y(col, lip) + inward * 0.8
		var pts := PackedVector3Array()
		for r in rows + 1:
			var d := drop * float(r) / rows
			pts.append(start + inward * (smooth[c] * sqrt(2.0 * d / 9.8)) + Vector3.DOWN * d)
		grid.append(pts)
	var total := float(columns.size() - 1) * p.spacing
	var fade := func(x: float) -> float: return smoothstep(0.0, 7.0, x) * smoothstep(0.0, 7.0, total - x)
	for c in columns.size() - 1:
		var x0 := c * p.spacing
		var x1 := (c + 1) * p.spacing
		var f0: float = fade.call(x0)
		var f1: float = fade.call(x1)
		for r in rows:
			var v0 := float(r) / rows
			var v1 := float(r + 1) / rows
			_vquad(curtains, grid[c][r], grid[c + 1][r], grid[c + 1][r + 1], grid[c][r + 1], Color(f0, 0, 0, 1), Color(f1, 0, 0, 1),
				Vector2(x0, v0), Vector2(x1, v0), Vector2(x1, v1), Vector2(x0, v1))
	# Pé: espuma ao longo, névoa subindo (duas camadas) e o som em três pontos
	for c in range(0, columns.size(), 4):
		var q := grid[c][rows]
		var i: int = columns[c][0]
		var inward := -p.lefts[i] * side
		var fc := Vector3(q.x, water + 0.06, q.z) + inward * 1.5
		var rf := 9.0
		foam.quad(fc + Vector3(-rf, 0, -rf), fc + Vector3(rf, 0, -rf), fc + Vector3(rf, 0, rf), fc + Vector3(-rf, 0, rf), Color.WHITE, Vector3.UP,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	for layer in 2:
		var push := 2.0 + layer * 5.0
		var tall := 24.0 + layer * 10.0
		for c in columns.size() - 1:
			var ia: int = columns[c][0]
			var ib: int = columns[c + 1][0]
			var qa := grid[c][rows] - p.lefts[ia] * side * push
			var qb := grid[c + 1][rows] - p.lefts[ib] * side * push
			qa.y = water - 0.5
			qb.y = water - 0.5
			var u0 := float(c) / (columns.size() - 1)
			var u1 := float(c + 1) / (columns.size() - 1)
			_vquad(mist, qa, qb, qb + Vector3.UP * tall, qa + Vector3.UP * tall, Color(1, 1, 1, 0.9 - layer * 0.35),
				Color(1, 1, 1, 0.9 - layer * 0.35), Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1))
	for u: float in [0.15, 0.5, 0.85]:
		var q := grid[int(u * (columns.size() - 1))][rows]
		feet.append(Vector3(q.x, water + 0.06, q.z))
	return total


## Ponto da face (anéis de uma coluna da parede) na altura y.
static func _face_y(col: PackedVector3Array, y: float) -> Vector3:
	for r in range(1, SeaCanyon.top_ring() + 1):
		if col[r].y >= y:
			return col[r - 1].lerp(col[r], clampf((y - col[r - 1].y) / maxf(col[r].y - col[r - 1].y, 0.001), 0.0, 1.0))
	return col[SeaCanyon.top_ring()]


## Quadrilátero com cor e UV por vértice (o MeshBuilder só tem uma cor por face); face dupla no shader.
static func _vquad(mb: MeshBuilder, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, ua: Vector2, ub: Vector2,
		uc: Vector2, ud: Vector2) -> void:
	var nrm := (b - a).cross(d - a).normalized()
	for v: Array in [[a, ca, ua], [b, cb, ub], [c, cb, uc], [a, ca, ua], [c, cb, uc], [d, ca, ud]]:
		mb.verts.append(v[0])
		mb.normals.append(nrm)
		mb.colors.append(v[1])
		mb.uvs.append(v[2])


## Aqueduto de pedra atravessando por cima da pista em s, de montanha a montanha, em dois andares: o
## arco grande sobre a ponte com os pilares na água e arcos menores até as montanhas; em cima, uma
## fileira de arcos pequenos com o canal no alto, a água correndo e despejando no mar dos dois lados.
## Estandartes nas faces, trepadeiras penduradas (sem chegar perto dos carros), tufos de plantas
## debruçados nas bordas, arbustos e árvores em cima. Devolve a altura mais baixa das trepadeiras
## sobre a pista (INF se não fez).
static func _aqueduct_over(track: RaceTrack, canyon: Dictionary, stone: MeshBuilder, banners: MeshBuilder, falls: MeshBuilder,
		foam: MeshBuilder, channel: MeshBuilder, feet: Array[Vector3], vines: Array, bushes: Array, trees: Dictionary, s: float,
		rng: RandomNumberGenerator) -> float:
	var p := track.path
	var water := track.layout.water_level
	var i := p.index_at(s)
	var road := p.points[i].y
	if road < water + 2.0:
		return INF
	var c := p.points[i]
	var lv := p.lefts[i]
	var fwd := p.tangents[i]
	fwd.y = 0.0
	fwd = fwd.normalized()
	var base_y := water - 3.0
	var top := road + 27.0
	var crown := top + AQUEDUCT_TIER
	# Face de dentro dos pilares (na água, por fora da laje) e as pontas na rocha das montanhas
	var pier := maxf(track.deck_edge(i, 1), track.deck_edge(i, -1)) + 4.0
	var lat_l := (SeaCanyon.face_at(track, canyon, i, 1, top - 2.0) - c).dot(lv) + 3.0
	var lat_r := (SeaCanyon.face_at(track, canyon, i, -1, top - 2.0) - c).dot(lv) - 3.0
	if lat_l < pier + 14.0 or -lat_r < pier + 14.0:
		return INF
	var at := func(lat: float, y: float) -> Vector3:
		var b := c + lv * lat
		return Vector3(b.x, y, b.z)
	var flat := Basis(lv, Vector3.UP, fwd)
	var thick := 7.0
	var thin := thick * 0.78
	var length := lat_l - lat_r
	var middle := (lat_l + lat_r) * 0.5
	# Arco grande: o vão de pilar a pilar por cima da pista (arcade: os pilares são 28% do vão)
	var span := 2.0 * (pier + 6.0)
	var r := span * 0.72 * 0.5
	var apex := road + 22.5
	AtlantisRuins.arcade(stone, at.call(-(pier + 6.0), base_y), at.call(pier + 6.0, base_y), 0.0, top - base_y, 1,
		apex - r - base_y, thick)
	# Arcos menores dos pilares até as montanhas
	for side: int in [1, -1]:
		var far: float = lat_l if side > 0 else lat_r
		var near := side * (pier + 6.0)
		var bays := maxi(int(absf(far - near) / 13.0), 1)
		AtlantisRuins.arcade(stone, at.call(near, base_y), at.call(far, base_y), 0.0, top - base_y, bays, (top - base_y) * 0.42, thick)
	# Cornija entre os andares e o segundo andar (arcos pequenos, um pouco recuados)
	stone.box(Transform3D(flat, at.call(middle, top + 0.25)), Vector3(length, 0.7, thick + 0.6), AtlantisRuins.STONE_DARK)
	AtlantisRuins.arcade(stone, at.call(lat_r, top + 0.6), at.call(lat_l, top + 0.6), 0.0, crown - top - 0.6,
		maxi(int(length / 6.5), 3), (crown - top) * 0.36, thin)
	# Mureta e o canal com água no alto (correndo do meio para as pontas)
	for sgn: float in [1.0, -1.0]:
		stone.box(Transform3D(flat, at.call(middle, crown + 0.6) + fwd * (thin * 0.5 - 0.35) * sgn), Vector3(length, 1.2, 0.7),
			AtlantisRuins.STONE_DARK)
	var cw := thin * 0.5 - 1.0
	for side: int in [1, -1]:
		var far: float = (lat_l if side > 0 else lat_r) - side * 3.0
		var steps := 10
		for k in steps:
			var u0 := float(k) / steps
			var u1 := float(k + 1) / steps
			var a0: Vector3 = at.call(lerpf(0.0, far, u0), crown + 0.2)
			var a1: Vector3 = at.call(lerpf(0.0, far, u1), crown + 0.2)
			channel.quad(a0 - fwd * cw, a0 + fwd * cw, a1 + fwd * cw, a1 - fwd * cw, Color.WHITE, Vector3.UP,
				Vector2(0, u0), Vector2(1, u0), Vector2(1, u1), Vector2(0, u1))
		# Bica despejando no mar, entre os pilares e a montanha
		var spout := side * (pier + 12.0)
		_waterfall(falls, foam, at.call(spout, crown - 1.2) + fwd * (thin * 0.5 + 0.2), fwd, 3.0, water, feet)
	# Estandartes pendurados da cornija, sobre os pilares do arco grande
	for sgn: float in [1.0, -1.0]:
		for lat: float in [-(pier + 3.0), pier + 3.0]:
			AtlantisRuins.add_banner(banners, at.call(lat, top - 0.2) + fwd * (thick * 0.5 + 0.12) * sgn, lv, fwd * sgn, 2.8, 7.5)
	# Trepadeiras: do intradorso do arco grande (por cima da pista) e da cornija pelas faces; sobre o
	# vão só até a folga dos carros
	var clear := road + 14.0
	var lowest := INF
	for k in 30:
		var lat := lerpf(-(pier + 5.0), pier + 5.0, (k + rng.randf()) / 30.0)
		var y_in := apex - r + sqrt(maxf(r * r - lat * lat, 0.0))
		var face := fwd * (thick * 0.5 - rng.randf_range(0.2, 1.2)) * (1.0 if rng.randf() < 0.5 else -1.0)
		var length_v := minf(rng.randf_range(2.0, 6.5), y_in - clear)
		if length_v < 1.0:
			continue
		lowest = minf(lowest, y_in - length_v - road)
		vines[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(2.6, 4.2), length_v, 2.0)),
			at.call(lat, y_in) + face))
		vines[1].append(_green(rng, 0.9))
	for sgn: float in [1.0, -1.0]:
		for k in 36:
			var lat := lerpf(lat_r + 3.0, lat_l - 3.0, (k + rng.randf()) / 36.0)
			var length_v := rng.randf_range(3.0, 11.0)
			if absf(lat) < pier + 6.0:
				length_v = minf(length_v, top - 0.1 - clear)
				lowest = minf(lowest, top - 0.1 - length_v - road)
			vines[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(2.6, 4.4), length_v, 2.0)),
				at.call(lat, top - 0.1) + fwd * (thick * 0.5 + 0.15) * sgn))
			vines[1].append(_green(rng, 0.8))
		# Tufos debruçados nas bordas da cornija e do alto (vistos de baixo, da pista)
		for edge: Vector2 in [Vector2(top + 0.6, thick * 0.5 + 0.25), Vector2(crown + 1.2, thin * 0.5 + 0.05)]:
			var lat := lat_r + 2.0 + rng.randf()
			while lat < lat_l - 2.0:
				var size := rng.randf_range(1.3, 2.3)
				bushes[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * 0.7, size)),
					at.call(lat, edge.x) + fwd * edge.y * sgn))
				bushes[1].append(_green(rng, 0.05))
				lat += rng.randf_range(1.8, 3.2)
	# Arbustos ao longo da mureta e árvores nas pontas (junto das montanhas)
	for k in 22:
		var lat := lerpf(lat_r + 2.0, lat_l - 2.0, rng.randf())
		var sgn := 1.0 if rng.randf() < 0.5 else -1.0
		var size := rng.randf_range(1.2, 2.4)
		bushes[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * 0.8, size)),
			at.call(lat, crown + 1.1) + fwd * (thin * 0.5 - 0.9) * sgn))
		bushes[1].append(_green(rng, 0.05))
	for side: int in [1, -1]:
		var far: float = lat_l if side > 0 else lat_r
		for k in 2:
			SeaCanyon._tree(trees, at.call(far - side * rng.randf_range(3.0, 7.0), crown + 0.1) + fwd * rng.randf_range(-2.0, 2.0), rng)
	return lowest


## s longe dos aquedutos e dos rostos (o que atravessa a pista passaria por dentro deles). Na frente
## das cachoeiras largas pode: o cipó ou a árvore fica na frente da cortina.
static func _clear_of_landmarks(s: float) -> bool:
	for aq: float in AQUEDUCTS:
		if absf(s - aq) < 22.0:
			return false
	for f: Array in FACES:
		if absf(s - float(f[0])) < 18.0:
			return false
	return true


## Corda (cilindro de 6 lados) de `a` até `b`.
static func _rope(mb: MeshBuilder, a: Vector3, b: Vector3, r0: float, r1: float, color: Color) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var y := d.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.FORWARD).normalized()
	mb.cylinder(Transform3D(Basis(x, y, x.cross(y)), a), r0, r1, d.length(), color, 6, false)


## Cipós de uma montanha à outra por cima da pista (grupos de 1 a 3, em parábola, a ponta mais baixa
## a CLEARANCE m ou mais do asfalto), com tufos de folhas ao longo e gavinhas penduradas. Devolve o s
## de cada um.
static func _lianas(track: RaceTrack, canyon: Dictionary, bark: MeshBuilder, vines: Array, bushes: Array, span: Vector2,
		rng: RandomNumberGenerator) -> Array[float]:
	var p := track.path
	var water := track.layout.water_level
	var length := fposmod(span.y - span.x, p.length)
	var made: Array[float] = []
	for k in LIANAS:
		var s := span.x + length * (k + rng.randf_range(0.2, 0.8)) / LIANAS
		if not _clear_of_landmarks(s):
			continue
		var i := p.index_at(s)
		var road := p.points[i].y
		if road < water + 1.0:
			continue
		for b in rng.randi_range(1, 3):
			var ia := p.index_at(s + rng.randf_range(-7.0, 7.0))
			var ib := p.index_at(s + rng.randf_range(-7.0, 7.0))
			var ya := road + rng.randf_range(19.0, 34.0)
			var yb := road + rng.randf_range(19.0, 34.0)
			# (as pontas entram 1 m na rocha das duas paredes)
			var a := SeaCanyon.face_at(track, canyon, ia, 1, ya) + p.lefts[ia] * 1.0
			var e := SeaCanyon.face_at(track, canyon, ib, -1, yb) - p.lefts[ib] * 1.0
			var sag := minf(rng.randf_range(5.0, 13.0), (ya + yb) * 0.5 - (road + CLEARANCE + 1.0))
			if sag < 1.5:
				continue
			var pts: Array[Vector3] = []
			var steps := 16
			for u in steps + 1:
				var t := float(u) / steps
				pts.append(a.lerp(e, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))
			var r := rng.randf_range(0.17, 0.28)
			for u in steps:
				_rope(bark, pts[u], pts[u + 1], r, r, LIANA * rng.randf_range(0.85, 1.15))
			# Um segundo cipó mais fino enrolado no primeiro
			var perp := (e - a).cross(Vector3.UP).normalized()
			var turns := rng.randf_range(3.0, 6.0)
			var prev2 := pts[0]
			for u in range(1, steps + 1):
				var ph := float(u) / steps * TAU * turns
				var q2 := pts[u] + (perp * cos(ph) + Vector3.UP * sin(ph)) * r * 1.7
				_rope(bark, prev2, q2, r * 0.55, r * 0.55, LIANA * 0.8)
				prev2 = q2
			# Folhas e gavinhas (as de cima da pista sem passar da folga)
			for u in range(1, steps * 2):
				var q := pts[u / 2].lerp(pts[mini(u / 2 + 1, steps)], 0.5 * (u % 2)) + Vector3(rng.randf_range(-0.35, 0.35), -0.1, rng.randf_range(-0.35, 0.35))
				var sz := rng.randf_range(0.6, 1.3)
				bushes[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sz, sz * 0.7, sz)), q))
				bushes[1].append(_green(rng, 0.25))
				if rng.randf() < 0.55:
					var hang := minf(rng.randf_range(1.0, 4.0), q.y - (road + CLEARANCE - 1.0))
					if hang > 0.6:
						vines[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(2.0, 3.2), hang, 1.6)), q))
						vines[1].append(_green(rng, 0.9))
			made.append(s)
	return made


## Árvores gigantes saindo da face das montanhas e se debruçando sobre a pista: nos CANOPY_ZONES, uma
## a cada 6 a 9 m dos dois lados, com as copas largas se encontrando por cima (o céu fica fechado); no
## resto, algumas avulsas. Nada abaixo de CLEARANCE m do asfalto. Devolve o s de cada uma.
static func _canopy_trees(track: RaceTrack, canyon: Dictionary, bark: MeshBuilder, crowns: Array, span: Vector2,
		rng: RandomNumberGenerator) -> Array[float]:
	var p := track.path
	var length := fposmod(span.y - span.x, p.length)
	var spots: Array = []  # [s, lado, fechando o céu]
	for zone: Vector2 in CANOPY_ZONES:
		var s := zone.x
		var side := 1
		while s <= zone.y:
			spots.append([s, side, true])
			spots.append([s + rng.randf_range(2.0, 4.5), -side, true])
			side = -side
			s += rng.randf_range(6.0, 9.0)
	for k in CANOPIES:
		var s := span.x + length * (k + rng.randf_range(0.15, 0.85)) / CANOPIES
		var in_zone := false
		for zone: Vector2 in CANOPY_ZONES:
			if s > zone.x - 12.0 and s < zone.y + 12.0:
				in_zone = true
		if in_zone or not _clear_of_landmarks(s):
			continue
		spots.append([s, 1 if rng.randf() < 0.5 else -1, false])
	var made: Array[float] = []
	for sp: Array in spots:
		if _canopy_tree(track, canyon, bark, crowns, sp[0], sp[1], sp[2], rng):
			made.append(sp[0])
	# O miolo da copa por cima do meio da pista nos trechos fechados (as copas dos dois lados se juntam)
	for zone: Vector2 in CANOPY_ZONES:
		var s := zone.x
		while s <= zone.y:
			var i := p.index_at(s)
			var road := p.points[i].y
			for k in 3:
				var at := p.frame_at(s + rng.randf_range(-1.5, 1.5), rng.randf_range(-7.0, 7.0), 0.0).origin
				at.y = road + rng.randf_range(19.0, 23.0)
				var sz := rng.randf_range(4.0, 6.0)
				crowns[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sz, sz * 0.4, sz)), at))
				var col: Color = CROWNS[rng.randi() % CROWNS.size()]
				var v := rng.randf_range(0.85, 1.15)
				crowns[1].append(Color(col.r * v, col.g * v, col.b * v, 0.12))
			s += 3.0
	return made


## Uma árvore saindo da face do lado `side` em s: o tronco grosso sai da rocha quase na horizontal,
## avança por cima da pista e sobe (curva de Bézier, afinando, com nós), galhos para cima e para os
## lados e a copa de tufos achatados nas pontas. `closing`: a ponta passa do meio da pista e a copa é
## mais cheia (com as do outro lado, fecha o céu). Falso se não coube.
static func _canopy_tree(track: RaceTrack, canyon: Dictionary, bark: MeshBuilder, crowns: Array, s: float, side: int,
		closing: bool, rng: RandomNumberGenerator) -> bool:
	var p := track.path
	var water := track.layout.water_level
	var i := p.index_at(s)
	var road := p.points[i].y
	if road < water + 1.0:
		return false
	var inward := -p.lefts[i] * side
	var tangent := p.tangents[i].normalized()
	var y0 := road + rng.randf_range(5.0, 9.0)
	var anchor := SeaCanyon.face_at(track, canyon, i, side, y0) - inward * 1.2
	# (a ponta: do próprio lado da pista ou, fechando o céu, passando do meio)
	var reach := rng.randf_range(-4.0, 3.0) if closing else rng.randf_range(3.0, 9.0)
	var tip := p.frame_at(s, side * reach, 0.0).origin + tangent * rng.randf_range(-3.0, 3.0)
	tip.y = road + rng.randf_range(19.0, 24.0)
	var flat := tip - anchor
	flat.y = 0.0
	var dist := flat.length()
	# (sobe quase reto junto da rocha e se debruça no alto: o trecho por cima da laje fica lá em cima)
	var c1 := anchor + Vector3.UP * (tip.y - anchor.y) * 0.85 + inward * dist * 0.12
	var c2 := tip - inward * dist * 0.5 + Vector3.UP * rng.randf_range(0.5, 2.0)
	var steps := 14
	var pts: Array[Vector3] = []
	for u in steps + 1:
		var t := float(u) / steps
		var q := anchor * pow(1.0 - t, 3) + c1 * 3.0 * t * pow(1.0 - t, 2) + c2 * 3.0 * t * t * (1.0 - t) + tip * pow(t, 3)
		pts.append(q)
		var lat := absf((q - p.points[i]).dot(p.lefts[i]))
		if lat < track.deck_edge(i, side) + 2.0 and q.y - 1.3 < road + CLEARANCE:
			return false
	for u in steps:
		var r0 := lerpf(1.3, 0.45, pow(float(u) / steps, 0.8))
		var r1 := lerpf(1.3, 0.45, pow(float(u + 1) / steps, 0.8))
		_rope(bark, pts[u], pts[u + 1], r0, r1, BARK * rng.randf_range(0.9, 1.1))
		# Nós no tronco
		if u > 0 and rng.randf() < 0.3:
			bark.blob(pts[u], Vector3.ONE * r0 * 1.25, BARK * 0.9, 7, 4)
	# Raízes agarradas na rocha em volta da saída do tronco
	for k in rng.randi_range(3, 5):
		var dir := (Vector3.DOWN * rng.randf_range(0.5, 1.2) + tangent * rng.randf_range(-1.2, 1.2) - inward * 0.25).normalized()
		_rope(bark, anchor + inward * 0.8, anchor + inward * 0.4 + dir * rng.randf_range(2.5, 5.0), 0.45, 0.12, BARK * 0.85)
	# Galhos da parte de cima e a copa (tufos achatados em volta da ponta e das pontas dos galhos)
	var heads: Array[Vector3] = [tip]
	for g in rng.randi_range(4, 6):
		var from := pts[rng.randi_range(8, steps - 1)]
		var dir := (Vector3.UP * 0.6 + tangent * rng.randf_range(-1.1, 1.1) + inward * rng.randf_range(-0.4, 0.7)).normalized()
		var end := from + dir * rng.randf_range(4.5, 8.0)
		if end.y < road + CLEARANCE + 2.5:
			continue
		_rope(bark, from, end, 0.36, 0.14, BARK)
		heads.append(end)
	var tufts := Vector2i(10, 14) if closing else Vector2i(6, 9)
	for h in heads:
		for c in rng.randi_range(tufts.x, tufts.y):
			var off := Vector3(rng.randf_range(-5.0, 5.0), rng.randf_range(-1.4, 1.2), rng.randf_range(-5.0, 5.0))
			var sz := rng.randf_range(4.0, 6.5) if closing else rng.randf_range(3.4, 5.4)
			var at := h + off
			at.y = maxf(at.y, road + CLEARANCE + 1.8)
			crowns[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sz, sz * 0.4, sz)), at))
			var col: Color = CROWNS[rng.randi() % CROWNS.size()]
			var v := rng.randf_range(0.85, 1.15)
			crowns[1].append(Color(col.r * v, col.g * v, col.b * v, 0.12))
	return true


## Bandeiras grandes em mastros nas cristas mais altas das montanhas, viradas para a pista.
static func _crest_flags(track: RaceTrack, canyon: Dictionary, stone: MeshBuilder, banners: MeshBuilder, span: Vector2,
		rng: RandomNumberGenerator) -> int:
	var p := track.path
	var water := track.layout.water_level
	var length := fposmod(span.y - span.x, p.length)
	var made := 0
	for k in CREST_FLAGS:
		var s := span.x + length * (k + rng.randf_range(0.25, 0.75)) / CREST_FLAGS
		var side := 1 if k % 2 == 0 else -1
		var i := p.index_at(s)
		var col := SeaCanyon.column(track, canyon, i, side)
		var crest: Vector3 = col[SeaCanyon.top_ring() + 1]
		if crest.y < water + 30.0:
			continue
		var foot := crest - p.lefts[i] * side * 2.0 + Vector3.DOWN * 0.5
		stone.cylinder(Transform3D(Basis(), foot), 0.4, 0.28, 16.0, AtlantisRuins.STONE_DARK, 8)
		var to_track := -p.lefts[i] * side
		stone.box(Transform3D(Basis(p.tangents[i].normalized(), Vector3.UP, p.lefts[i]).orthonormalized(), foot + Vector3.UP * 15.4),
			Vector3(4.6, 0.25, 0.25), AtlantisRuins.STONE_DARK)
		AtlantisRuins.add_banner(banners, foot + Vector3.UP * 15.3, p.tangents[i], to_track, 4.0, 10.0)
		made += 1
	return made


static func _green(rng: RandomNumberGenerator, sway: float) -> Color:
	var c: Color = SeaCanyon.SHRUBS[rng.randi() % SeaCanyon.SHRUBS.size()]
	var v := rng.randf_range(0.8, 1.2)
	return Color(c.r * v, c.g * v, c.b * v, sway)


static func _commit(root: Node3D, stone: MeshBuilder, banners: MeshBuilder, falls: MeshBuilder, foam: MeshBuilder,
		strips: MeshBuilder) -> void:
	if not stone.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Ruins"
		mi.mesh = stone.commit(null, TrackMaterials.sea_stone("ruins", false, {}))
		root.add_child(mi)
	if not banners.is_empty():
		var bmi := MeshInstance3D.new()
		bmi.name = "Banners"
		bmi.mesh = banners.commit(null, AtlantisRuins.banner_material())
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bmi)
	for part: Array in [[falls, 0, "Waterfalls"], [foam, 1, "WaterfallFoam"], [strips, 2, "WaterlineFoam"]]:
		var mb: MeshBuilder = part[0]
		if mb.is_empty():
			continue
		var w := MeshInstance3D.new()
		w.name = part[2]
		w.mesh = mb.commit(null, water_material(part[1]))
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(w)


static func water_material(mode: int) -> ShaderMaterial:
	if not _water_mats.has(mode):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/waterfall.gdshader")
		mat.set_shader_parameter("mode", mode)
		_water_mats[mode] = mat
	return _water_mats[mode]


## Cachoeira saindo de `lip` para a frente (`forward`) e caindo até o mar, com `width` m de largura e
## um disco de espuma no pé (guardado em `feet`, para o som).
static func _waterfall(falls: MeshBuilder, foam: MeshBuilder, lip: Vector3, forward: Vector3, width: float, water: float,
		feet: Array[Vector3]) -> void:
	var right := forward.cross(Vector3.UP).normalized() * width * 0.5
	var drop := lip.y - water
	if drop < 2.0:
		return
	var rows := 14
	var prev := lip
	for r in rows:
		var t1 := float(r + 1) / rows
		# Sai para a frente e cai em parábola (mais rápido embaixo)
		var q := lip + forward * (2.5 * sqrt(t1) + 2.0 * t1) + Vector3.DOWN * (drop * t1 * t1)
		var w0 := 1.0 + 0.25 * float(r) / rows
		var w1 := 1.0 + 0.25 * t1
		falls.quad(prev - right * w0, prev + right * w0, q + right * w1, q - right * w1, Color.WHITE, forward,
			Vector2(0, float(r) / rows), Vector2(1, float(r) / rows), Vector2(1, t1), Vector2(0, t1))
		prev = q
	var c := Vector3(prev.x, water + 0.06, prev.z)
	feet.append(c)
	var r := width * 1.4
	foam.quad(c + Vector3(-r, 0, -r), c + Vector3(r, 0, -r), c + Vector3(r, 0, r), c + Vector3(-r, 0, r), Color.WHITE, Vector3.UP,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))


## Faixa de espuma na linha d'água em volta da laje, onde a pista cruza a superfície (em s).
static func _waterline_foam(track: RaceTrack, mb: MeshBuilder, s: float) -> void:
	var p := track.path
	var water := track.layout.water_level
	for side: int in [1, -1]:
		var idxs := track.span_indices(s - 40.0, s + 40.0)
		for k in idxs.size() - 1:
			var i := idxs[k]
			var j := idxs[k + 1]
			var e_i := track.deck_edge(i, side)
			var e_j := track.deck_edge(j, side)
			var a := p.points[i] + p.lefts[i] * side * e_i
			var b := p.points[j] + p.lefts[j] * side * e_j
			a.y = water + 0.05
			b.y = water + 0.05
			var o_i := p.lefts[i] * side * 3.5
			var o_j := p.lefts[j] * side * 3.5
			var u_i := p.s_at(i)
			var u_j := u_i + p.spacing
			mb.quad(a - o_i * 0.3, b - o_j * 0.3, b + o_j, a + o_i, Color.WHITE, Vector3.UP,
				Vector2(u_i, 0), Vector2(u_j, 0), Vector2(u_j, 1), Vector2(u_i, 1))
	# Através da pista, onde o asfalto encontra a água
	var i0 := p.index_at(s)
	var hw := p.half_width(i0, 1) + track.barrier[0][i0] + 1.0
	var hr := p.half_width(i0, -1) + track.barrier[1][i0] + 1.0
	var f := p.frame_at(s, 0.0, 0.0)
	var c := Vector3(f.origin.x, water + 0.05, f.origin.z)
	var along := p.tangents[i0] * 2.0
	mb.quad(c - p.lefts[i0] * hr - along, c + p.lefts[i0] * hw - along, c + p.lefts[i0] * hw + along, c - p.lefts[i0] * hr + along,
		Color.WHITE, Vector3.UP, Vector2(0, 0), Vector2(hw + hr, 0), Vector2(hw + hr, 1), Vector2(0, 1))


## Arco-íris num plano vertical à frente de quem passa pela ponte.
static func _rainbow_arc(track: RaceTrack, root: Node3D) -> void:
	var p := track.path
	var i := p.index_at(RAINBOW.x)
	var fwd := p.tangents[i]
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var center := p.position_at(RAINBOW.x) + fwd * RAINBOW.y
	center.y = track.layout.water_level - RAINBOW.z * 0.25
	var mb := MeshBuilder.new()
	var steps := 48
	var inner := RAINBOW.z
	var outer := RAINBOW.z * 1.09
	for k in steps:
		var a0 := PI * float(k) / steps
		var a1 := PI * float(k + 1) / steps
		var d0 := right * cos(a0) + Vector3.UP * sin(a0)
		var d1 := right * cos(a1) + Vector3.UP * sin(a1)
		mb.quad(center + d0 * inner, center + d1 * inner, center + d1 * outer, center + d0 * outer, Color.WHITE, -fwd,
			Vector2(float(k) / steps, 0), Vector2(float(k + 1) / steps, 0), Vector2(float(k + 1) / steps, 1), Vector2(float(k) / steps, 1))
	if _rainbow == null:
		_rainbow = ShaderMaterial.new()
		_rainbow.shader = load("res://shaders/track/rainbow.gdshader")
	var mi := MeshInstance3D.new()
	mi.name = "Rainbow"
	mi.mesh = mb.commit(null, _rainbow)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Período do dia: o arco-íris só de dia (fraco no entardecer).
static func apply_mood(time_of_day: int) -> void:
	if _rainbow:
		_rainbow.set_shader_parameter("intensity", [0.32, 0.12, 0.0][clampi(time_of_day, 0, 2)])


## Peixes-voadores saltando perto da ponte, dos dois lados.
static func _flying_fish(track: RaceTrack, root: Node3D, rng: RandomNumberGenerator, span: Vector2) -> void:
	var p := track.path
	var water := track.layout.water_level
	# Corpo (o do cardume, maior, sem abanar a cauda) e as nadadeiras-asas (COLOR.r = 1 nas pontas)
	var mb := SeaLife.fish_builder(1.6)
	for v in mb.verts.size():
		mb.colors[v] = Color(0.0, mb.colors[v].g, 1.0)
	for side: float in [1.0, -1.0]:
		var root_f := Vector3(side * 0.06, 0.05, 0.28)
		var root_b := Vector3(side * 0.06, 0.05, -0.03)
		var tip := Vector3(side * 0.66, 0.1, -0.12)
		var start := mb.verts.size()
		mb.tri(root_f, tip, root_b, Color(0.0, 0.0, 1.0), Vector3.UP)
		for v in range(start, mb.verts.size()):
			mb.colors[v] = Color(clampf(absf(mb.verts[v].x) / 0.66, 0.0, 1.0), 0.0, 1.0)
	var mesh := mb.commit()
	var xfs: Array[Transform3D] = []
	var data: Array[Color] = []
	var length := fposmod(span.y - span.x, p.length)
	for k in 22:
		var s := span.x + rng.randf() * length
		var i := p.index_at(s)
		var side := 1 if rng.randf() < 0.5 else -1
		var pos := p.frame_at(s, side * (track.deck_edge(i, side) + rng.randf_range(6.0, 18.0)), 0.0).origin
		pos.y = water
		var dir := p.tangents[i] * (1.0 if rng.randf() < 0.6 else -1.0) + p.lefts[i] * rng.randf_range(-0.5, 0.5)
		dir.y = 0.0
		xfs.append(Transform3D(Basis.looking_at(-dir.normalized()), pos))
		data.append(Color(rng.randf(), rng.randf(), 0.0, 0.0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	mm.buffer = Grandstands.pack_buffer(xfs, data)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/flying_fish.gdshader")
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "FlyingFish"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-20000, -100, -20000), Vector3(40000, 200, 40000))
	root.add_child(mmi)


## Duas revoadas de gaivotas sobre o cânion (o modelo e o shader dos pássaros do campo).
static func _gulls(track: RaceTrack, root: Node3D, rng: RandomNumberGenerator, span: Vector2) -> void:
	var animator := SceneryAnimator.new()
	animator.name = "GullAnimator"
	root.add_child(animator)
	var mesh := TrackLife._bird_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/bird.gdshader")
	var p := track.path
	for f in 2:
		var count := rng.randi_range(8, 14)
		var transforms: Array[Transform3D] = []
		var data: Array[Color] = []
		for k in count:
			var s := rng.randf_range(1.4, 1.8)
			transforms.append(Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(rng.randf_range(-12, 12), rng.randf_range(-3, 3), rng.randf_range(-12, 12))))
			data.append(Color(rng.randf(), rng.randf(), 0.9, 0.0))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = count
		mm.buffer = Grandstands.pack_buffer(transforms, data)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Gulls%d" % f
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		var anchor := p.position_at(span.x + fposmod(span.y - span.x, p.length) * (0.3 + 0.4 * f))
		animator.add_flock(mmi, Vector3(anchor.x, track.layout.water_level + rng.randf_range(30.0, 55.0), anchor.z),
			Vector2(rng.randf_range(90.0, 160.0), rng.randf_range(70.0, 130.0)), rng.randf_range(9.0, 13.0), rng.randf() * TAU)
