class_name CloudIslands
extends RefCounted
## Ilhas voadoras em volta da pista fofa nas nuvens (Rainbow Raceway): rocha em camadas pastel
## afinando para baixo (lilás, rosa, pêssego, creme), topo de grama menta ou rosa com contorno de
## nuvens fofas, e em cima árvores de pirulito e de algodão-doce, arbustos, flores, cogumelos, balas
## de goma, bengalas e casinhas de cupcake; algumas com cachoeira colorida caindo da beirada (com um
## riacho até ela e nuvem de névoa no pé) e um arco-íris pequeno.
##
## As ilhas grandes com nome (LANDMARKS) recebem os marcos: o Castelo de Algodão-Doce (CandyCastle),
## a Torre de Algodão-Doce no meio da espiral, a Ilha do Coração (arco de coração gigante), a Ilha das
## Cachoeiras (alta, com três cachoeiras e um arco-íris), a dos Ursinhos e a do Ursinho da curva 1
## (PlushFriends) e a dos Doces (cupcakes, rosquinhas e pirulitos gigantes). As outras são sorteadas
## longe da pista. Nada tem colisão.

## Marcos: [posição no mapa do traçado (x leste, y norte, m), raio (m), altura do topo (m)].
const LANDMARKS := {
	"castle": [Vector2(240.0, 320.0), 100.0, 24.0],
	"heart": [Vector2(-800.0, 225.0), 58.0, 2.0],
	"falls": [Vector2(-850.0, 560.0), 72.0, 54.0],
	"bears": [Vector2(-600.0, -75.0), 60.0, 6.0],
	"bear_corner": [Vector2(520.0, -60.0), 42.0, 10.0],
	"sweets": [Vector2(610.0, 360.0), 62.0, 14.0],
}
## Ilhotas sorteadas: quantas e a faixa de raio (m).
const SMALL_COUNT := 56
const SMALL_RADIUS := Vector2(9.0, 34.0)
## Folga (m) entre a beirada da ilha e a borda da plataforma da pista (mesma altura; bem abaixo ou
## acima da pista, a metade).
const TRACK_GAP := 26.0
## Lado das células que agrupam os enfeites (um MultiMesh por tipo por célula, para o recorte).
const CELL := 700.0
const DECOR_RANGE := 1300.0
const RIM_RANGE := 3200.0
const GRASS := [Color(0.3, 0.72, 0.38), Color(0.44, 0.78, 0.36), Color(1.0, 0.5, 0.74), Color(0.62, 0.5, 1.0)]
const STRATA := [Color(0.6, 0.46, 0.92), Color(0.98, 0.52, 0.72), Color(1.0, 0.68, 0.5), Color(0.98, 0.84, 0.68),
	Color(0.5, 0.7, 1.0), Color(0.78, 0.52, 0.98)]
const WATER := [Color(0.62, 0.9, 1.0), Color(1.0, 0.76, 0.9), Color(0.8, 0.74, 1.0)]

static var _cache := {}


## Marco `id` (ver LANDMARKS; "tower" = o meio da espiral): {pos (centro do topo, no mundo), radius}.
## A posição é afastada da pista se precisar (mesma conta que a geração usa).
static func landmark(track: RaceTrack, id: String) -> Dictionary:
	var key := "%s#%d#%s" % [track.layout.resource_path, track.path.size(), id]
	if _cache.has(key):
		return _cache[key]
	var out := {}
	if id == "tower":
		var c := spiral_center(track)
		out = {"pos": Vector3(c.x, 8.0, c.z), "radius": 30.0}
	else:
		var d: Array = LANDMARKS[id]
		var m: Vector2 = d[0]
		var r: float = d[1]
		var pos := _clear_spot(track, Vector3(m.x, d[2], -m.y), r)
		out = {"pos": pos, "radius": r}
	_cache[key] = out
	return out


## Centro da espiral (a curva de quase uma volta inteira): média dos pontos do trecho mais curvo
## que dá mais de 250°.
static func spiral_center(track: RaceTrack) -> Vector3:
	var p := track.path
	var n := p.size()
	var best_i := 0
	var best_turn := 0.0
	# Janela de ~400 m: onde o rumo gira mais
	var win := int(400.0 / p.spacing)
	for i in range(0, n, 4):
		var turn := 0.0
		for k in range(0, win, 2):
			turn += p.curvature[(i + k) % n] * p.spacing * 2.0
		if absf(turn) > absf(best_turn):
			best_turn = turn
			best_i = i
	# Círculo que melhor passa pelos pontos curvos do trecho (ajuste algébrico: x² + z² + D·x + E·z + F = 0)
	var m := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var v := Vector3.ZERO
	var y := 0.0
	var cnt := 0
	for k in range(0, win, 2):
		var i := (best_i + k) % n
		if absf(p.curvature[i]) > 1.0 / 120.0:
			var q := p.points[i]
			var row := Vector3(q.x, q.z, 1.0)
			var b := -(q.x * q.x + q.z * q.z)
			m.x += row * row.x
			m.y += row * row.y
			m.z += row * row.z
			v += row * b
			y += q.y
			cnt += 1
	var sol := m.inverse() * v
	return Vector3(-sol.x * 0.5, y / maxf(cnt, 1.0), -sol.y * 0.5)


## Afasta `pos` (centro do topo) da pista até a beirada da ilha ficar a TRACK_GAP m da plataforma.
static func _clear_spot(track: RaceTrack, pos: Vector3, radius: float) -> Vector3:
	var p := track.path
	for it in 40:
		var pr := p.project(pos, true, false)
		var i := p.index_at(pr.x)
		var side := 1 if pr.y > 0.0 else -1
		var edge := track.deck_edge(i, side)
		var need := edge + radius + _gap(pos.y, p.points[i].y)
		if absf(pr.y) >= need:
			return pos
		var away := p.lefts[i] * side
		pos += Vector3(away.x, 0.0, away.z).normalized() * (need - absf(pr.y) + 2.0)
	return pos


static func _gap(y: float, track_y: float) -> float:
	return TRACK_GAP * (0.5 if absf(y - track_y) > 45.0 else 1.0)


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "CloudIslands"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var islands: Array = []  # [pos, radius, kind]
	for id: String in LANDMARKS:
		var lm := landmark(track, id)
		islands.append([lm.pos, lm.radius, id])
	var tower := landmark(track, "tower")
	islands.append([tower.pos, tower.radius, "tower"])
	_scatter(track, rng, islands)
	var decor := _Decor.new()
	var rocks := MeshBuilder.new()
	var falls: Array = [MeshBuilder.new(), MeshBuilder.new(), MeshBuilder.new()]
	var specials := MeshBuilder.new()
	var mist: Array[Transform3D] = []
	var rainbows: Array[Transform3D] = []
	var fall_count := 0
	for k in islands.size():
		var isl: Array = islands[k]
		var pos: Vector3 = isl[0]
		var r: float = isl[1]
		var kind: String = isl[2]
		var irng := RandomNumberGenerator.new()
		irng.seed = 5000 + k * 97
		var shape := _shape(irng, r)
		_rock(rocks, irng, pos, r, shape, kind)
		_rim(root, irng, pos, r, shape, k)
		# Cachoeiras: nas marcadas e em ~40% das ilhotas médias
		var n_falls := 0
		if kind == "falls":
			n_falls = 3
		elif kind in ["castle", "sweets", "heart"]:
			n_falls = 1
		elif kind == "small" and r > 16.0 and irng.randf() < 0.45:
			n_falls = 1
		var to_track := _to_track(track, pos)
		for f in n_falls:
			var ang := atan2(to_track.z, to_track.x) + (f - (n_falls - 1) * 0.5) * 0.7 + irng.randf_range(-0.25, 0.25)
			var drop := irng.randf_range(35.0, 70.0) if kind != "falls" else irng.randf_range(110.0, 150.0)
			var width := clampf(r * 0.16, 4.0, 11.0) * (1.6 if kind == "falls" else 1.0)
			var color := irng.randi() % WATER.size()
			_waterfall(falls[color], specials, mist, rainbows, pos, r, shape, ang, drop, width, irng)
			fall_count += 1
		match kind:
			"small":
				_decorate(decor, irng, pos, r, r * 0.85, 0.0)
			"castle":
				_decorate(decor, irng, pos, r, r * 0.93, r * 0.62)
			"tower":
				_decorate(decor, irng, pos, r, r * 0.9, r * 0.56)
			"sweets":
				_sweets(specials, decor, irng, pos, r)
			"heart":
				_heart_island(specials, decor, irng, pos, r, to_track)
			"falls":
				_decorate(decor, irng, pos, r, r * 0.85, r * 0.25)
			_:
				_decorate(decor, irng, pos, r, r * 0.85, r * 0.45)
	CloudLook.add_mesh(root, "Rocks", rocks.commit(null, TrackMaterials.candy_plastic("island", false, true, 0.0,
		{"rim_amount": 0.12, "sparkle": 0.0})))
	CloudLook.add_mesh(root, "Specials", specials.commit(null, CandyDecor.material()))
	for c in 3:
		if not (falls[c] as MeshBuilder).is_empty():
			CloudLook.add_mesh(root, "Waterfalls%d" % c, (falls[c] as MeshBuilder).commit(null, _fall_material(c)))
	CloudLook.add_multimesh(root, "FallMist", CloudLook.puff_mesh(3, 7, false, 1), mist, CloudLook.cloud_material(), 3000.0)
	_mini_rainbows(root, rainbows)
	decor.commit(root)
	root.set_meta("islands", islands.size())
	root.set_meta("waterfalls", fall_count)
	var spots: Array[Vector3] = []
	for isl: Array in islands:
		spots.append(isl[0])
	root.set_meta("points", spots)
	var radii: Array[float] = []
	for isl: Array in islands:
		radii.append(isl[1])
	root.set_meta("radii", radii)


## Direção (no plano) da ilha para o ponto mais perto da pista.
static func _to_track(track: RaceTrack, pos: Vector3) -> Vector3:
	var pr := track.path.project(pos, true, false)
	var q := track.path.position_at(pr.x)
	var d := q - pos
	d.y = 0.0
	return d.normalized() if d.length() > 0.1 else Vector3.FORWARD


## Ilhotas sorteadas: em volta da pista e no miolo, longe dela e umas das outras.
static func _scatter(track: RaceTrack, rng: RandomNumberGenerator, islands: Array) -> void:
	var p := track.path
	var b := p.bounds().grow(650.0)
	var tries := 0
	var placed := 0
	while placed < SMALL_COUNT and tries < SMALL_COUNT * 60:
		tries += 1
		var r := lerpf(SMALL_RADIUS.x, SMALL_RADIUS.y, pow(rng.randf(), 1.6))
		var pos := Vector3(rng.randf_range(b.position.x, b.end.x), 0.0, rng.randf_range(b.position.y, b.end.y))
		# Altura: a maioria perto do nível da pista, algumas bem abaixo ou acima
		var roll := rng.randf()
		pos.y = rng.randf_range(-15.0, 50.0) if roll < 0.6 else (rng.randf_range(-110.0, -30.0) if roll < 0.85 else rng.randf_range(60.0, 130.0))
		var pr := p.project(pos, true, false)
		var i := p.index_at(pr.x)
		var side := 1 if pr.y > 0.0 else -1
		if absf(pr.y) < track.deck_edge(i, side) + r + _gap(pos.y, p.points[i].y):
			continue
		var ok := true
		for other: Array in islands:
			var op: Vector3 = other[0]
			if Vector2(pos.x - op.x, pos.z - op.z).length() < r + float(other[1]) + 18.0 and absf(pos.y - op.y) < 90.0:
				ok = false
				break
		if not ok:
			continue
		islands.append([pos, r, "small"])
		placed += 1


## Contorno irregular da ilha: fatores de raio por ângulo (ANGLES pontos).
const ANGLES := 40


static func _shape(rng: RandomNumberGenerator, _r: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var f1 := rng.randf() * TAU
	var f2 := rng.randf() * TAU
	var f3 := rng.randf() * TAU
	for k in ANGLES:
		var a := TAU * k / ANGLES
		out.append(1.0 + 0.1 * sin(3.0 * a + f1) + 0.06 * sin(5.0 * a + f2) + 0.04 * sin(9.0 * a + f3))
	return out


static func _edge_at(shape: PackedFloat32Array, ang: float) -> float:
	var f := fposmod(ang, TAU) / TAU * ANGLES
	var k := int(floor(f))
	return lerpf(shape[k % ANGLES], shape[(k + 1) % ANGLES], f - k)


## Rocha (cone irregular em camadas, com normais suaves: pedra de bala, sem arestas marcadas) e o
## topo de grama levemente abaulado com a beirada mais escura.
static func _rock(mb: MeshBuilder, rng: RandomNumberGenerator, pos: Vector3, r: float, shape: PackedFloat32Array, kind: String) -> void:
	var grass: Color = GRASS[rng.randi() % GRASS.size()]
	if kind in ["castle", "tower", "bears", "bear_corner", "falls"]:
		grass = GRASS[0]
	elif kind == "heart":
		grass = GRASS[2]
	var base := rng.randi() % STRATA.size()
	# Anéis de baixo: [fração do raio, profundidade (em raios)]
	var rings := [[1.0, 0.0], [1.02, 0.06], [0.97, 0.14], [0.92, 0.25], [0.84, 0.38], [0.75, 0.5], [0.64, 0.64], [0.52, 0.8], [0.39, 0.95],
		[0.26, 1.1], [0.14, 1.24], [0.05, 1.33], [0.0, 1.37]]
	var depth_scale := clampf(r * 0.9, 6.0, 70.0) / r
	# Pontos de todos os anéis primeiro (as normais de cada um olham os vizinhos)
	var grid: Array = []
	var cols: Array[Color] = []
	for q in rings.size():
		var ring: Array = rings[q]
		var row: Array[Vector3] = []
		for k in ANGLES:
			var a := TAU * k / ANGLES
			var jitter := 1.0 if q < 2 else rng.randf_range(0.93, 1.07)
			var rad: float = r * float(ring[0]) * shape[k] * jitter
			var y: float = -float(ring[1]) * r * depth_scale + (rng.randf_range(-0.03, 0.03) * r if q > 1 else 0.0)
			row.append(pos + Vector3(cos(a) * rad, y, sin(a) * rad))
		grid.append(row)
		cols.append(grass.darkened(0.18) if q <= 1 else STRATA[(base + q / 2) % STRATA.size()])
	var last := rings.size() - 1
	var normals: Array = []
	for q in rings.size():
		var nrow: Array[Vector3] = []
		var up: Array[Vector3] = grid[maxi(q - 1, 0)]
		var down: Array[Vector3] = grid[mini(q + 1, last)]
		var row: Array[Vector3] = grid[q]
		for k in ANGLES:
			var tk: Vector3 = row[(k + 1) % ANGLES] - row[(k + ANGLES - 1) % ANGLES]
			var tq: Vector3 = down[k] - up[k]
			var n := tk.cross(tq)
			var out := Vector3(cos(TAU * k / ANGLES), -0.4, sin(TAU * k / ANGLES))
			if n.length_squared() < 1e-8:
				n = Vector3.DOWN
			elif n.dot(out) < 0.0:
				n = -n
			nrow.append(n.normalized())
		normals.append(nrow)
	for q in range(1, rings.size()):
		var r0: Array[Vector3] = grid[q - 1]
		var r1: Array[Vector3] = grid[q]
		var n0: Array[Vector3] = normals[q - 1]
		var n1: Array[Vector3] = normals[q]
		for k in ANGLES:
			var k1 := (k + 1) % ANGLES
			mb.tri_smooth(r0[k], r0[k1], r1[k1], n0[k], n0[k1], n1[k1], cols[q - 1], cols[q - 1], cols[q])
			mb.tri_smooth(r0[k], r1[k1], r1[k], n0[k], n1[k1], n1[k], cols[q - 1], cols[q], cols[q])
	# Topo: anéis concêntricos abaulados (normal da cúpula)
	var dome := minf(r * 0.06, 3.0)
	var tops := [1.0, 0.75, 0.45, 0.0]
	var last_row: Array[Vector3] = []
	var last_n: Array[Vector3] = []
	for q in tops.size():
		var row: Array[Vector3] = []
		var nrow: Array[Vector3] = []
		for k in ANGLES:
			var a := TAU * k / ANGLES
			var f: float = tops[q]
			var rad := r * f * shape[k]
			var dir := Vector3(cos(a), 0.0, sin(a))
			row.append(pos + dir * rad + Vector3.UP * dome * (1.0 - f * f))
			nrow.append((dir * (2.0 * dome * f / maxf(r * shape[k], 0.1)) + Vector3.UP).normalized())
		if q > 0:
			var c0 := grass * (0.97 + 0.06 * ((q - 1) % 2))
			var c1 := grass * (0.97 + 0.06 * (q % 2))
			for k in ANGLES:
				var k1 := (k + 1) % ANGLES
				mb.tri_smooth(last_row[k], last_row[k1], row[k1], last_n[k], last_n[k1], nrow[k1], c0, c0, c1)
				mb.tri_smooth(last_row[k], row[k1], row[k], last_n[k], nrow[k1], nrow[k], c0, c1, c1)
		last_row = row
		last_n = nrow


## Altura do topo de grama (y) a `rel` do centro (fração do raio).
static func top_y(pos: Vector3, r: float, rel: float) -> float:
	var dome := minf(r * 0.06, 3.0)
	return pos.y + dome * (1.0 - rel * rel)


## Contorno de nuvens fofas na beirada do topo (um MultiMesh por ilha, médio de perto e simples longe).
static func _rim(root: Node3D, rng: RandomNumberGenerator, pos: Vector3, r: float, shape: PackedFloat32Array, k: int) -> void:
	var xfs: Array[Transform3D] = []
	var circ := TAU * r
	var count := maxi(int(circ / 7.0), 6)
	for q in count:
		var a := TAU * (q + rng.randf_range(-0.3, 0.3)) / count
		var rad := r * _edge_at(shape, a) * rng.randf_range(0.98, 1.08)
		var s := clampf(r * 0.16, 2.4, 7.5) * rng.randf_range(0.8, 1.25)
		var at := pos + Vector3(cos(a) * rad, -s * rng.randf_range(0.35, 0.6), sin(a) * rad)
		xfs.append(Transform3D(Basis(Vector3.UP, -a).scaled(Vector3(s * 1.2, s * rng.randf_range(0.55, 0.75), s)), at))
		# Um pouco embaixo também (nuvem pendurada na rocha)
		if rng.randf() < 0.3:
			var under := pos + Vector3(cos(a) * rad * 0.8, -r * rng.randf_range(0.25, 0.5), sin(a) * rad * 0.8)
			xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s * 1.3), under))
	var mat := CloudLook.cloud_material()
	var near := CloudLook.add_multimesh(root, "Rim%d" % k, CloudLook.puff_mesh(k % 3, 7, true, 2), xfs, mat, 700.0)
	var far := CloudLook.add_multimesh(root, "RimFar%d" % k, CloudLook.puff_mesh(k % 3, 7, true, 3), xfs, mat, RIM_RANGE)
	if far:
		far.visibility_range_begin = 700.0


## Cachoeira: riacho no topo até a beirada no ângulo `ang`, lâmina caindo `drop` m (abrindo um
## pouco para fora), nuvens de névoa no pé e, nas maiores, um arco-íris pequeno.
static func _waterfall(mb: MeshBuilder, specials: MeshBuilder, mist: Array[Transform3D], rainbows: Array[Transform3D], pos: Vector3,
		r: float, shape: PackedFloat32Array, ang: float, drop: float, width: float, rng: RandomNumberGenerator) -> void:
	var out := Vector3(cos(ang), 0.0, sin(ang))
	var side := Vector3.UP.cross(out).normalized()
	var edge := r * _edge_at(shape, ang)
	var lip := pos + out * (edge + 0.4) + Vector3.UP * (top_y(pos, r, 1.0) - pos.y + 0.15)
	# Riacho no topo (do miolo até a beirada), azul claro, um pouco acima da grama
	var steps := 8
	for k in steps:
		var t0 := float(k) / steps
		var t1 := float(k + 1) / steps
		var a := pos + out * (edge * lerpf(0.35, 1.0, t0))
		var b := pos + out * (edge * lerpf(0.35, 1.0, t1))
		var w0 := width * lerpf(0.5, 0.75, t0) * 0.5
		var w1 := width * lerpf(0.5, 0.75, t1) * 0.5
		var ya := top_y(pos, r, lerpf(0.35, 1.0, t0)) + 0.12
		var yb := top_y(pos, r, lerpf(0.35, 1.0, t1)) + 0.12
		specials.quad(Vector3(a.x, ya, a.z) - side * w0, Vector3(b.x, yb, b.z) - side * w1, Vector3(b.x, yb, b.z) + side * w1,
			Vector3(a.x, ya, a.z) + side * w0, Color(0.6, 0.86, 1.0), Vector3.UP)
	# Lâmina: UV.x 0..1 na largura, UV.y 0 no alto .. 1 embaixo
	var segs := 12
	for k in segs:
		var t0 := float(k) / segs
		var t1 := float(k + 1) / segs
		var c0 := lip + out * (sqrt(t0) * drop * 0.08) + Vector3.DOWN * drop * t0
		var c1 := lip + out * (sqrt(t1) * drop * 0.08) + Vector3.DOWN * drop * t1
		var h0 := width * 0.5 * (1.0 + t0 * t0 * 1.6)
		var h1 := width * 0.5 * (1.0 + t1 * t1 * 1.6)
		mb.quad(c0 - side * h0, c0 + side * h0, c1 + side * h1, c1 - side * h1, Color.WHITE, out,
			Vector2(0, t0), Vector2(1, t0), Vector2(1, t1), Vector2(0, t1))
	# Névoa: nuvens no meio e no fim da queda (onde a lâmina some)
	var foot := lip + out * (drop * 0.08) + Vector3.DOWN * drop * 0.8
	for k in 4:
		var s := width * rng.randf_range(1.3, 2.1)
		var off := side * rng.randf_range(-width, width) + out * rng.randf_range(-1.0, 4.0) + Vector3.UP * rng.randf_range(-drop * 0.15, drop * 0.1)
		mist.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.8, s)), foot + off))
	if drop > 100.0 or rng.randf() < 0.35:
		var rr := clampf(width * 3.5, 14.0, 40.0)
		rainbows.append(Transform3D(Basis(side, Vector3.UP, out).scaled(Vector3.ONE * rr), foot + Vector3.UP * 4.0 + out * 6.0))


static var _fall_mats := {}


static func _fall_material(c: int) -> ShaderMaterial:
	if not _fall_mats.has(c):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/candy_fall.gdshader")
		mat.set_shader_parameter("water_color", WATER[c])
		mat.set_shader_parameter("rainbow", 0.45 if c == 0 else 0.25)
		_fall_mats[c] = mat
	return _fall_mats[c]


## Arco-íris pequenos (aditivos) no pé das cachoeiras.
static func _mini_rainbows(root: Node3D, xfs: Array[Transform3D]) -> void:
	if xfs.is_empty():
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/rainbow.gdshader")
	mat.set_shader_parameter("intensity", 0.5)
	CloudWorld.register_rainbow(mat)
	CloudLook.add_multimesh(root, "FallRainbows", CloudWorld.arc_mesh(1.0, 0.16, 32, 0.98), xfs, mat, 2500.0)


# ---------------------------------------------------------------------------
# Enfeites no topo
# ---------------------------------------------------------------------------
## Espalha árvores, arbustos, flores, cogumelos, balas, bengalas e casinhas no topo da ilha, no anel
## entre `inner` e `outer` m do centro.
static func _decorate(decor: _Decor, rng: RandomNumberGenerator, pos: Vector3, r: float, outer: float, inner: float) -> void:
	var area := PI * (outer * outer - inner * inner)
	var count := clampi(int(area / 22.0), 4, 420)
	for k in count:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf_range(inner * inner / maxf(outer * outer, 1.0), 1.0)) * outer
		var at := pos + Vector3(cos(a) * d, 0.0, sin(a) * d)
		at.y = top_y(pos, r, d / r) - 0.05
		var roll := rng.randf()
		var yaw := Basis(Vector3.UP, rng.randf() * TAU)
		if roll < 0.2:
			decor.add("cotton", at, yaw, rng.randf_range(1.3, 2.4), CloudLook.pick(rng, [CloudLook.PINK, CloudLook.LILAC, CloudLook.MINT,
				CloudLook.BABY_BLUE, CloudLook.PEACH]), rng.randi() % 3)
		elif roll < 0.36:
			decor.add("lollipop", at, yaw, rng.randf_range(1.2, 2.2), CloudLook.pick(rng, CloudLook.RAINBOW))
		elif roll < 0.55:
			decor.add("bush", at, yaw, rng.randf_range(0.9, 1.8), CloudLook.pick(rng, [CloudLook.MINT, Color(0.55, 0.85, 0.6),
				CloudLook.PINK, CloudLook.LILAC]), rng.randi() % 3)
		elif roll < 0.82:
			# Canteiro: várias flores juntas da mesma cor
			var col := CloudLook.pick(rng, [CloudLook.HOT_PINK, CloudLook.BUTTER, CloudLook.LILAC, Color.WHITE, CloudLook.PEACH, CloudLook.BABY_BLUE])
			for f in rng.randi_range(3, 7):
				var off := Vector3(rng.randf_range(-1.6, 1.6), 0.0, rng.randf_range(-1.6, 1.6))
				var fat := at + off
				fat.y = top_y(pos, r, clampf((Vector2(fat.x - pos.x, fat.z - pos.z).length()) / r, 0.0, 1.0)) - 0.03
				decor.add("flower", fat, Basis(Vector3.UP, rng.randf() * TAU), rng.randf_range(0.8, 1.4), col)
		elif roll < 0.9:
			decor.add("mushroom", at, yaw, rng.randf_range(0.8, 2.2), CloudLook.pick(rng, [Color(1.0, 0.35, 0.45), CloudLook.HOT_PINK,
				CloudLook.LILAC, CloudLook.PEACH]))
		elif roll < 0.96:
			decor.add("gumdrop", at, yaw, rng.randf_range(0.8, 1.8), CloudLook.pick(rng, CloudLook.RAINBOW))
		else:
			decor.add("cane", at, yaw, rng.randf_range(1.0, 2.0), Color.WHITE)
	# Casinhas de cupcake nas ilhas maiores
	var houses := 0 if r < 18.0 else clampi(int(r / 22.0), 1, 4)
	for h in houses:
		var a := rng.randf() * TAU
		var d := lerpf(maxf(inner, r * 0.15), outer * 0.8, rng.randf())
		var at := pos + Vector3(cos(a) * d, 0.0, sin(a) * d)
		at.y = top_y(pos, r, d / r) - 0.1
		decor.houses.append([at, rng.randf() * TAU, rng.randf_range(2.6, 4.2), CloudLook.pick(rng), CloudLook.pick(rng, [CloudLook.CREAM,
			CloudLook.PINK, Color(0.62, 0.42, 0.34), CloudLook.MINT, CloudLook.LILAC])])


## Ilha dos Doces: cupcakes, rosquinhas e pirulitos gigantes no meio dos enfeites.
static func _sweets(specials: MeshBuilder, decor: _Decor, rng: RandomNumberGenerator, pos: Vector3, r: float) -> void:
	_decorate(decor, rng, pos, r, r * 0.85, r * 0.5)
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		var at := pos + Vector3(cos(a), 0.0, sin(a)) * r * 0.28
		at.y = top_y(pos, r, 0.28)
		CandyDecor.cupcake_house(specials, Transform3D(Basis(Vector3.UP, -a + PI * 0.5), at), rng.randf_range(6.0, 8.5),
			CloudLook.pick(rng), CloudLook.pick(rng, [CloudLook.CREAM, CloudLook.PINK, CloudLook.MINT]), rng)
	# Rosquinhas gigantes de pé (toro com cobertura e granulado)
	for k in 2:
		var a := TAU * (k + 0.5) / 3.0 + 0.4
		var at := pos + Vector3(cos(a), 0.0, sin(a)) * r * 0.45
		at.y = top_y(pos, r, 0.45)
		_donut(specials, Transform3D(Basis(Vector3.UP, a), at + Vector3.UP * 7.5), 7.0, 2.6, rng)
	for k in 5:
		var a := rng.randf() * TAU
		var at := pos + Vector3(cos(a), 0.0, sin(a)) * r * rng.randf_range(0.55, 0.75)
		at.y = top_y(pos, r, 0.65)
		decor.add("lollipop", at, Basis(Vector3.UP, rng.randf() * TAU), rng.randf_range(4.0, 6.5), CloudLook.pick(rng, CloudLook.RAINBOW))


## Rosquinha de pé (no plano XY local): massa cor de biscoito, cobertura rosa na frente e granulado.
static func _donut(mb: MeshBuilder, xf: Transform3D, big: float, small: float, rng: RandomNumberGenerator) -> void:
	var seg := 28
	var ring := 12
	var icing := CloudLook.pick(rng, [CloudLook.HOT_PINK, CloudLook.LILAC, CloudLook.MINT, Color(0.5, 0.3, 0.25)])
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		for q in ring:
			var b0 := TAU * q / ring
			var b1 := TAU * (q + 1) / ring
			var p00 := _torus(a0, b0, big, small)
			var p10 := _torus(a1, b0, big, small)
			var p11 := _torus(a1, b1, big, small)
			var p01 := _torus(a0, b1, big, small)
			var front := sin((b0 + b1) * 0.5)
			var col := icing if front > -0.15 else Color(0.95, 0.74, 0.5)
			var n := _torus(a0, b0, big, small) - Vector3(cos(a0), sin(a0), 0) * big
			mb.quad(xf * p00, xf * p10, xf * p11, xf * p01, col, xf.basis * n)
	for k in 40:
		var a := rng.randf() * TAU
		var b := rng.randf_range(0.2, PI - 0.2)
		var at := _torus(a, b, big, small * 1.03)
		mb.box(Transform3D(xf.basis * Basis(Vector3.FORWARD, rng.randf() * TAU), xf * at), Vector3(0.15, 0.6, 0.15), CloudLook.pick(rng, CloudLook.RAINBOW))


static func _torus(a: float, b: float, big: float, small: float) -> Vector3:
	var c := Vector3(cos(a), sin(a), 0.0)
	return c * (big + small * cos(b)) + Vector3(0, 0, small * sin(b))


## Ilha do Coração: o arco em forma de coração gigante (contorno grosso, rosa com friso branco) de
## frente para a pista, canteiros de flores e corações de pedestal.
static func _heart_island(specials: MeshBuilder, decor: _Decor, rng: RandomNumberGenerator, pos: Vector3, r: float, to_track: Vector3) -> void:
	_decorate(decor, rng, pos, r, r * 0.88, r * 0.42)
	var face := to_track
	var right := Vector3.UP.cross(face).normalized()
	var size := r * 0.75
	var at := pos + Vector3.UP * (top_y(pos, r, 0.0) - pos.y + size * 0.48)
	var xf := Transform3D(Basis(right, Vector3.UP, face), at)
	heart_frame(specials, xf, size, size * 0.14, 2.6, CloudLook.HOT_PINK, Color.WHITE)
	for k in 6:
		var a := TAU * k / 6.0
		var sp := pos + Vector3(cos(a), 0.0, sin(a)) * r * 0.62
		sp.y = top_y(pos, r, 0.62)
		CandyDecor.heart_statue(specials, Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), sp), rng.randf_range(2.5, 3.6),
			CloudLook.pick(rng, [CloudLook.HOT_PINK, CloudLook.PINK, CloudLook.LILAC]))


## Contorno de coração com espessura (moldura): a faixa entre o coração de largura `size` e o de dentro
## (`line` m para dentro), com `depth` m de espessura, numa cor e com o friso de outra na frente.
static func heart_frame(mb: MeshBuilder, xf: Transform3D, size: float, line: float, depth: float, color: Color, trim: Color) -> void:
	var outer := CloudLook.heart(size, 64)
	var center := Vector2.ZERO
	for q in outer:
		center += q
	center /= outer.size()
	var n := outer.size()
	var inner := PackedVector2Array()
	for q in outer:
		inner.append(q + (center - q).normalized() * line)
	var h := depth * 0.5
	for k in n:
		var k1 := (k + 1) % n
		var o0 := outer[k]
		var o1 := outer[k1]
		var i0 := inner[k]
		var i1 := inner[k1]
		for z: float in [h, -h]:
			mb.quad(xf * Vector3(o0.x, o0.y, z), xf * Vector3(o1.x, o1.y, z), xf * Vector3(i1.x, i1.y, z), xf * Vector3(i0.x, i0.y, z),
				color, xf.basis.z * signf(z))
		var on := xf.basis * Vector3(o1.y - o0.y, o0.x - o1.x, 0.0)
		mb.quad(xf * Vector3(o0.x, o0.y, h), xf * Vector3(o1.x, o1.y, h), xf * Vector3(o1.x, o1.y, -h), xf * Vector3(o0.x, o0.y, -h), color.darkened(0.1), on)
		mb.quad(xf * Vector3(i0.x, i0.y, h), xf * Vector3(i1.x, i1.y, h), xf * Vector3(i1.x, i1.y, -h), xf * Vector3(i0.x, i0.y, -h), color.darkened(0.15), -on)
		# Friso branco na frente (um pouco saliente), no meio da faixa
		var m0 := o0.lerp(i0, 0.4)
		var m1 := o1.lerp(i1, 0.4)
		var t0 := o0.lerp(i0, 0.6)
		var t1 := o1.lerp(i1, 0.6)
		for z: float in [h + 0.05, -h - 0.05]:
			mb.quad(xf * Vector3(m0.x, m0.y, z), xf * Vector3(m1.x, m1.y, z), xf * Vector3(t1.x, t1.y, z), xf * Vector3(t0.x, t0.y, z),
				trim, xf.basis.z * signf(z))


## Enfeites agrupados por célula do mapa: [tipo] -> [transformações, cores]; casinhas montadas no fim.
class _Decor:
	var cells := {}
	var houses: Array = []

	func add(kind: String, at: Vector3, yaw: Basis, scale: float, color: Color, variant := 0) -> void:
		var cell := Vector2i(floori(at.x / CELL), floori(at.z / CELL))
		if not cells.has(cell):
			cells[cell] = {}
		var key := "%s_%d" % [kind, variant]
		var groups: Dictionary = cells[cell]
		if not groups.has(key):
			groups[key] = [[] as Array[Transform3D], [] as Array[Color]]
		var g: Array = groups[key]
		(g[0] as Array[Transform3D]).append(Transform3D(yaw.scaled(Vector3.ONE * scale), at))
		(g[1] as Array[Color]).append(color)

	func commit(root: Node3D) -> void:
		var mat := CandyDecor.material()
		var holder := Node3D.new()
		holder.name = "Decor"
		root.add_child(holder)
		var n := 0
		for cell: Vector2i in cells:
			var groups: Dictionary = cells[cell]
			for key: String in groups:
				var g: Array = groups[key]
				var xfs: Array[Transform3D] = g[0]
				var cols: Array[Color] = g[1]
				var kind := key.get_slice("_", 0)
				var v := int(key.get_slice("_", 1))
				# [malha pintada pela instância, malha fixa (mesma transformação)]
				var parts: Array = []
				match kind:
					"cotton":
						parts = [CandyDecor.cotton_canopy(v), CandyDecor.cotton_trunk()]
					"lollipop":
						parts = [CandyDecor.lollipop_disc(), CandyDecor.lollipop_stick()]
					"bush":
						parts = [CandyDecor.bush(v), null]
					"flower":
						parts = [CandyDecor.flower_head(), CandyDecor.flower_stem()]
					"mushroom":
						parts = [CandyDecor.mushroom_cap(), CandyDecor.mushroom_stem(), CandyDecor.mushroom_dots()]
					"gumdrop":
						parts = [CandyDecor.gumdrop(), null]
					"cane":
						parts = [null, CandyDecor.candy_cane()]
				for q in parts.size():
					if parts[q] == null:
						continue
					var node_name := "%s%d_%d_%d_%d" % [kind.capitalize(), cell.x, cell.y, v, q]
					var tint: Array[Color] = cols if q == 0 else ([] as Array[Color])
					CloudLook.add_multimesh(holder, node_name, parts[q], xfs, mat, DECOR_RANGE, tint)
					n += xfs.size() if q == 0 else 0
		var mb := MeshBuilder.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for h: Array in houses:
			CandyDecor.cupcake_house(mb, Transform3D(Basis(Vector3.UP, h[1]), h[0]), h[2], h[3], h[4], rng)
		if not mb.is_empty():
			CloudLook.add_mesh(holder, "CupcakeHouses", mb.commit(null, mat), null, DECOR_RANGE * 1.4)
		holder.set_meta("count", n)
		holder.set_meta("houses", houses.size())
