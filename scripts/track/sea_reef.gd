class_name SeaReef
extends RefCounted
## Vida presa no fundo e nas construções da pista no fundo do mar (todas as peças com coral.gdshader:
## cor por instância, balanço da corrente e pólipos que brilham à noite):
##  * no leito, recifes em manchas sobre pedras cobertas de musgo (coral ramificado, de mesa, cérebro,
##    esponjas em tubo, leques e anêmonas, os de cima crescendo sobre as pedras), florestas de kelp e
##    capim do mar, mais densos perto da pista (fora do tubo) e mais nos trechos abertos (sem cânion;
##    nada dentro da rocha do cânion);
##  * nas paredes do cânion, o que a SeaCanyon registra com place();
##  * nas construções: algas penduradas na laje e nos arcos, colônias de coral e anêmonas na base dos
##    pilares, colunas e paredes e tufos de musgo no alto. Quem constrói (SeaCauseway, AtlantisRuins)
##    registra os pontos com hang/cluster/moss; build() junta tudo em MultiMesh por blocos;
##  * peças elaboradas (garden: jardins nos patamares do cânion e no leito; clam: marisco gigante;
##    worms: vermes tubulares dos vulcões): prateleiras de coral de placa, coral-pilar, esponja-barril,
##    coral mole com cachos de pólipos, chicotes-do-mar, leques em rede, estrelas-do-mar e ouriços.
## Nada tem colisão. Só abaixo da linha d'água.

const CORAL_PATCHES := 520
const KELP_FORESTS := 40
const GRASS := 6000
const CORAL_RANGE := 280.0
const ROCK_RANGE := 420.0
const KELP_RANGE := 480.0
const GRASS_RANGE := 170.0
const GROWTH_RANGE := 320.0

## (cores cheias e não claras demais: na luz azulada da água as claras viravam pastel de brinquedo)
const CORALS := [Color(0.86, 0.26, 0.46), Color(0.95, 0.45, 0.12), Color(0.5, 0.22, 0.78), Color(0.95, 0.74, 0.16),
	Color(0.78, 0.14, 0.2), Color(0.1, 0.62, 0.56), Color(0.86, 0.8, 0.7), Color(0.22, 0.4, 0.86)]
const ANEMONES := [Color(0.95, 0.32, 0.6), Color(0.98, 0.5, 0.14), Color(0.5, 0.86, 0.22), Color(0.62, 0.34, 0.95)]
const KELPS := [Color(0.36, 0.45, 0.16), Color(0.42, 0.38, 0.14), Color(0.22, 0.42, 0.18)]
const GREENS := [Color(0.24, 0.47, 0.2), Color(0.34, 0.52, 0.18), Color(0.18, 0.38, 0.22)]
const ROCKS := [Color(0.46, 0.43, 0.4), Color(0.52, 0.47, 0.41), Color(0.4, 0.42, 0.44)]

const PILLARS := [Color(0.78, 0.62, 0.4), Color(0.86, 0.76, 0.5), Color(0.6, 0.68, 0.42), Color(0.82, 0.54, 0.38)]
const SPONGES := [Color(0.92, 0.42, 0.12), Color(0.46, 0.22, 0.62), Color(0.58, 0.22, 0.18), Color(0.9, 0.7, 0.2),
	Color(0.76, 0.26, 0.42)]
const SOFTS := [Color(0.95, 0.22, 0.6), Color(0.98, 0.42, 0.1), Color(0.6, 0.28, 0.92), Color(0.9, 0.16, 0.24),
	Color(0.95, 0.76, 0.16), Color(0.16, 0.8, 0.74)]
const WHIPS := [Color(0.94, 0.66, 0.12), Color(0.86, 0.26, 0.16), Color(0.84, 0.8, 0.72), Color(0.52, 0.22, 0.76)]
const SHELLS := [Color(0.9, 0.87, 0.8), Color(0.82, 0.8, 0.72), Color(0.86, 0.8, 0.7)]
const MANTLES := [Color(0.15, 0.55, 1.0), Color(0.46, 0.26, 0.96), Color(0.1, 0.86, 0.76), Color(0.25, 0.9, 0.42),
	Color(0.95, 0.4, 0.8)]
const STARS := [Color(1.0, 0.46, 0.15), Color(0.95, 0.2, 0.26), Color(0.62, 0.3, 0.92), Color(0.2, 0.5, 1.0),
	Color(1.0, 0.76, 0.2)]
const URCHINS := [Color(0.26, 0.1, 0.32), Color(0.13, 0.11, 0.15), Color(0.56, 0.12, 0.22)]
const WORMS := [Color(0.93, 0.91, 0.87), Color(0.86, 0.84, 0.8)]
const PLUMES := [Color(0.96, 0.12, 0.16), Color(1.0, 0.28, 0.2)]

## As peças mais elaboradas (corais de placas em prateleiras, coral-pilar, esponja-barril, coral mole,
## chicote-do-mar, marisco gigante com o manto, estrela-do-mar, ouriço e os vermes tubulares dos
## vulcões) vêm depois das primeiras: os índices antigos não mudam.
enum Kind { BRANCH, TABLE, BRAIN, TUBES, FAN, ANEMONE, KELP, GRASS, STRAND, MOSS, ROCK, PLATE, PILLAR, BARREL, SOFT,
	WHIP, CLAM, MANTLE, STAR, URCHIN, WORM, PLUME }
## Peças pequenas (estrelas, ouriços, mariscos): aparecem só mais perto.
const SMALL_RANGE := 170.0

static var _water := 28.0
## Pontos registrados pelas construções: [tipo, Transform3D, cor]
static var _growth: Array = []
static var _meshes := {}
static var _material: ShaderMaterial


## Começo da geração da pista (o leito chama): esquece os pontos da pista anterior.
static func reset(track: RaceTrack) -> void:
	_water = track.layout.water_level
	_growth.clear()


## Alga pendurada em `pos`, descendo `length` m.
static func hang(pos: Vector3, length: float, rng: RandomNumberGenerator) -> void:
	if pos.y > _water - 1.0:
		return
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(0.8, 1.3), length, rng.randf_range(0.8, 1.3)))
	_growth.append([Kind.STRAND, Transform3D(basis, pos), _pick(GREENS, rng, 0.9)])


## Colônia de corais e anêmonas em volta de `pos` (raio `radius`), na altura de `pos`.
static func cluster(pos: Vector3, radius: float, rng: RandomNumberGenerator, count := 4) -> void:
	if pos.y > _water - 1.5:
		return
	for k in count:
		var a := rng.randf() * TAU
		var at := pos + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, radius)
		var kind: int = [Kind.BRANCH, Kind.BRAIN, Kind.ANEMONE, Kind.TUBES, Kind.FAN][rng.randi() % 5]
		var sc := rng.randf_range(0.4, 1.1)
		_growth.append([kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), at), _coral_color(kind, rng)])


## Peça avulsa já posicionada e orientada por quem constrói (as paredes do cânion: leques colados na
## rocha, esponjas saindo dela, corais nos patamares...), com a cor do tipo.
static func place(kind: int, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	if xf.origin.y > _water - 1.0:
		return
	var color: Color
	match kind:
		Kind.KELP:
			var c := KELPS[rng.randi() % KELPS.size()] as Color
			var v := rng.randf_range(0.85, 1.12)
			color = Color(c.r * v, c.g * v, c.b * v, 1.0)
		Kind.GRASS:
			color = _pick(GREENS, rng, 1.0)
		Kind.STRAND:
			color = _pick(GREENS, rng, 0.9)
		Kind.MOSS:
			color = _pick(GREENS, rng, 0.05)
		Kind.ROCK:
			color = _pick(ROCKS, rng, 0.0)
		_:
			color = _coral_color(kind, rng)
	_growth.append([kind, xf, color])


## Tufo de musgo em `pos` (numa face de cima).
static func moss(pos: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	if pos.y > _water - 1.0:
		return
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * rng.randf_range(0.5, 0.9), size))
	_growth.append([Kind.MOSS, Transform3D(basis, pos), _pick(GREENS, rng, 0.05)])


static func _pick(list: Array, rng: RandomNumberGenerator, sway: float) -> Color:
	var c: Color = list[rng.randi() % list.size()]
	var v := rng.randf_range(0.85, 1.12)
	return Color(c.r * v, c.g * v, c.b * v, sway)


static func _coral_color(kind: int, rng: RandomNumberGenerator) -> Color:
	match kind:
		Kind.ANEMONE:
			return _pick(ANEMONES, rng, 1.0)
		Kind.FAN:
			return _pick(CORALS, rng, 0.6)
		Kind.PILLAR:
			return _pick(PILLARS, rng, 0.1)
		Kind.BARREL:
			return _pick(SPONGES, rng, 0.05)
		Kind.SOFT:
			return _pick(SOFTS, rng, 0.55)
		Kind.WHIP:
			return _pick(WHIPS, rng, 0.85)
		Kind.CLAM:
			return _pick(SHELLS, rng, 0.0)
		Kind.MANTLE:
			return _pick(MANTLES, rng, 0.0)
		Kind.STAR:
			return _pick(STARS, rng, 0.0)
		Kind.URCHIN:
			return _pick(URCHINS, rng, 0.2)
		Kind.WORM:
			return _pick(WORMS, rng, 0.3)
		Kind.PLUME:
			return _pick(PLUMES, rng, 0.7)
	return _pick(CORALS, rng, 0.12)


## Jardim de corais elaborado em volta de `pos` (raio em m, na altura de `pos`, ou na de `ground`
## (x, z) se vier): uma peça grande no meio (esponja-barril, prateleiras de placas, leque grande,
## coral mole ou coral-pilar) e em volta corais ramificados, pilares, corais moles, anêmonas,
## chicotes, um marisco gigante, estrelas e ouriços.
static func garden(pos: Vector3, radius: float, rng: RandomNumberGenerator, ground := Callable()) -> void:
	if pos.y > _water - 2.0:
		return
	var at_xz := func(x: float, z: float) -> Vector3:
		return Vector3(x, ground.call(x, z) if ground.is_valid() else pos.y, z)
	var centre: int = [Kind.BARREL, Kind.BARREL, Kind.PILLAR, Kind.SOFT, Kind.FAN, Kind.TABLE][rng.randi() % 6]
	var big := rng.randf_range(1.6, 2.6) * (1.6 if centre == Kind.FAN or centre == Kind.TABLE else 1.0)
	place(centre, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * big), at_xz.call(pos.x, pos.z)), rng)
	var mix := [Kind.BRANCH, Kind.PILLAR, Kind.SOFT, Kind.SOFT, Kind.ANEMONE, Kind.ANEMONE, Kind.WHIP, Kind.TUBES, Kind.BRAIN,
		Kind.BARREL]
	for k in rng.randi_range(7, 13):
		var a := rng.randf() * TAU
		var r := radius * sqrt(rng.randf_range(0.12, 1.0))
		var at: Vector3 = at_xz.call(pos.x + cos(a) * r, pos.z + sin(a) * r)
		var kind: int = mix[rng.randi() % mix.size()]
		var sc := rng.randf_range(0.7, 1.6)
		var tilt := Basis(Vector3(rng.randf() - 0.5, 0.0, rng.randf() - 0.5).normalized(), rng.randf_range(0.0, 0.15))
		place(kind, Transform3D(tilt * Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), at), rng)
	if rng.randf() < 0.7:
		var a := rng.randf() * TAU
		clam(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.5)),
			at_xz.call(pos.x + cos(a) * radius * 0.6, pos.z + sin(a) * radius * 0.6)), rng)
	for k in rng.randi_range(2, 5):
		var a := rng.randf() * TAU
		var r := radius * rng.randf_range(0.3, 1.1)
		var kind := Kind.STAR if k % 2 == 0 else Kind.URCHIN
		place(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.4)),
			at_xz.call(pos.x + cos(a) * r, pos.z + sin(a) * r)), rng)


## Marisco gigante (as duas conchas e o manto colorido entre elas) em `xf`.
static func clam(xf: Transform3D, rng: RandomNumberGenerator) -> void:
	place(Kind.CLAM, xf, rng)
	place(Kind.MANTLE, xf, rng)


## Colônia de vermes tubulares (tubos brancos com a pluma vermelha) em volta de `pos`.
static func worms(pos: Vector3, radius: float, rng: RandomNumberGenerator, count := 4) -> void:
	for k in count:
		var a := rng.randf() * TAU
		var at := pos + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, radius)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.8)), at)
		place(Kind.WORM, xf, rng)
		place(Kind.PLUME, xf, rng)


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/track/coral.gdshader")
	return _material


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Reef"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6612
	var items: Array = _growth.duplicate()
	var patches: Array[Vector3] = []
	var patch_rocks: Array = []
	var forests: Array[Vector3] = []
	_seabed(track, rng, items, patches, patch_rocks, forests)
	# (onde ficam os recifes — com as pedras de cada um: [x, z, raio] — e as florestas de kelp do leito,
	# para as capturas de conferência)
	root.set_meta("patches", PackedVector3Array(patches))
	root.set_meta("patch_rocks", patch_rocks)
	root.set_meta("kelp", PackedVector3Array(forests))
	# Por tipo: transformações e cores
	var groups := {}
	for it: Array in items:
		var kind: int = it[0]
		if not groups.has(kind):
			groups[kind] = [[], []]
		groups[kind][0].append(it[1])
		groups[kind][1].append(it[2])
	for kind: int in groups:
		var reach := CORAL_RANGE
		match kind:
			Kind.KELP:
				reach = KELP_RANGE
			Kind.GRASS:
				reach = GRASS_RANGE
			Kind.STRAND, Kind.MOSS:
				reach = GROWTH_RANGE
			Kind.ROCK:
				reach = ROCK_RANGE
			Kind.STAR, Kind.URCHIN, Kind.CLAM, Kind.MANTLE, Kind.WORM, Kind.PLUME:
				reach = SMALL_RANGE
		CityProps.add_chunked(root, Kind.keys()[kind].capitalize(), groups[kind][0], groups[kind][1],
			[[_mesh(kind), material(), 0.0, reach, false]])


## Recifes, kelp e capim no leito, mais perto da pista (fora do tubo) e alguns longe.
static func _seabed(track: RaceTrack, rng: RandomNumberGenerator, items: Array, patches: Array[Vector3], patch_rocks: Array,
		forests: Array[Vector3]) -> void:
	var p := track.path
	var mix := [Kind.BRANCH, Kind.BRANCH, Kind.BRANCH, Kind.TABLE, Kind.BRAIN, Kind.BRAIN, Kind.TUBES, Kind.FAN, Kind.FAN,
		Kind.ANEMONE, Kind.ANEMONE]
	for k in CORAL_PATCHES:
		var c := _spot(track, rng, 4.0, 150.0 if k % 4 != 0 else 420.0, 0.6)
		if c == Vector3.INF:
			continue
		var radius := rng.randf_range(8.0, 20.0)
		# (nada nasce dentro de naufrágios, praças, vulcões e ruínas: SeaFloor.claim)
		if SeaFloor.claimed(c, radius * 0.6):
			continue
		# Pedras do recife (uma grande de vez em quando): (x, z, raio, altura, base)
		var rocks: Array = []
		for n in rng.randi_range(1, 4):
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * radius * 0.6
			var pos := c + Vector3(cos(a) * r, 0.0, sin(a) * r)
			var size := rng.randf_range(5.0, 8.0) if n == 0 and k % 6 == 0 else rng.randf_range(1.6, 4.2)
			var hgt := size * rng.randf_range(0.5, 0.85)
			pos.y = SeaFloor.ground(track, pos.x, pos.z) - 0.15 * hgt
			if pos.y + hgt > _water - 3.0 or SeaTube.inside(track, pos, size + 1.0) or SeaCanyon.in_rock(track, pos, 0.5):
				continue
			rocks.append([pos.x, pos.z, size, hgt, pos.y])
			items.append([Kind.ROCK, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, hgt, size)), pos),
				_pick(ROCKS, rng, 0.0)])
		patches.append(c)
		patch_rocks.append(rocks.map(func(rk: Array) -> Vector3: return Vector3(rk[0], rk[1], rk[2])))
		for n in rng.randi_range(18, 42):
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * radius
			var pos := c + Vector3(cos(a) * r, 0.0, sin(a) * r)
			pos.y = SeaFloor.ground(track, pos.x, pos.z)
			# Sobre a pedra (o topo dela, um pouco enterrado para não flutuar)
			for rk: Array in rocks:
				var d: float = Vector2(pos.x - rk[0], pos.z - rk[1]).length() / rk[2]
				if d < 0.75:
					pos.y = maxf(pos.y, rk[4] + rk[3] * (0.42 + 0.5 * sqrt(1.0 - d * d)))
			if pos.y > _water - 3.0 or SeaTube.inside(track, pos, 1.0) or SeaCanyon.in_rock(track, pos, 0.5):
				continue
			var kind: int = mix[rng.randi() % mix.size()]
			var sc := rng.randf_range(1.2, 3.4) * (1.6 if kind == Kind.TABLE or kind == Kind.FAN or kind == Kind.BRAIN else 1.0)
			if rng.randf() < 0.08:
				sc *= 1.7
			var tilt := Basis(Vector3(rng.randf() - 0.5, 0.0, rng.randf() - 0.5).normalized(), rng.randf_range(0.0, 0.18))
			items.append([kind, Transform3D(tilt * Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), pos), _coral_color(kind, rng)])
	# Florestas de kelp (talos altos, sem passar da superfície)
	for f in KELP_FORESTS:
		var c := _spot(track, rng, 12.0, 220.0, 0.7)
		if c == Vector3.INF or SeaFloor.claimed(c, 6.0):
			continue
		forests.append(c)
		var color := KELPS[rng.randi() % KELPS.size()] as Color
		var radius := rng.randf_range(12.0, 28.0)
		for n in rng.randi_range(20, 44):
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * radius
			var pos := c + Vector3(cos(a) * r, 0.0, sin(a) * r)
			pos.y = SeaFloor.ground(track, pos.x, pos.z) - 0.3
			var h := minf(rng.randf_range(8.0, 20.0), _water - 1.5 - pos.y)
			if h < 3.0 or SeaTube.inside(track, pos + Vector3.UP * h * 0.5, 2.0) or SeaCanyon.in_rock(track, pos, 0.5):
				continue
			var w := rng.randf_range(1.0, 1.8)
			var v := rng.randf_range(0.85, 1.12)
			items.append([Kind.KELP, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, h, w)), pos),
				Color(color.r * v, color.g * v, color.b * v, 1.0)])
	# Capim do mar perto da pista
	for k in GRASS:
		var pos := _spot(track, rng, 1.0, 90.0)
		if pos == Vector3.INF or SeaFloor.claimed(pos, 0.5):
			continue
		var sc := rng.randf_range(0.6, 1.5)
		items.append([Kind.GRASS, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), pos), _pick(GREENS, rng, 1.0)])


## Ponto no leito a `near`..`far` m além da borda do tubo, de um lado da pista (INF se não serve):
## fora da rocha do cânion e, com a chance `open_bias`, num trecho aberto.
static func _spot(track: RaceTrack, rng: RandomNumberGenerator, near: float, far: float, open_bias := 0.0) -> Vector3:
	var p := track.path
	var tube := SeaTube.profile(track)
	for t in 6:
		var s := SeaCanyon.random_open_s(track, rng) if rng.randf() < open_bias else rng.randf() * p.length
		var i := p.index_at(s)
		var side := 1 if rng.randf() < 0.5 else -1
		var edge: float = tube.left[i] if side > 0 else tube.right[i]
		var pos := p.frame_at(s, side * (edge + rng.randf_range(near, far)), 0.0).origin
		pos.y = SeaFloor.ground(track, pos.x, pos.z)
		if pos.y < _water - 3.0 and not SeaTube.inside(track, pos, 1.0) and not SeaCanyon.in_rock(track, pos, 0.5):
			return pos
	return Vector3.INF


# ---------------------------------------------------------------------------
# Peças (altura ~1, base em y = 0). Cor de vértice: R = balanço, G = pólipo, B = claro nas pontas
# ---------------------------------------------------------------------------
static func _mesh(kind: int) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + kind
	var height := 1.0
	match kind:
		Kind.BRANCH:
			_branch(mb, Vector3.ZERO, Vector3.UP, 0.085, 0.34, 0, rng)
		Kind.TABLE:
			# Coral de mesa: pé torto e o tampo em dois andares, com a borda recortada em lóbulos e
			# levemente inclinado (lathe e depois o raio da borda variando com o ângulo)
			var prof := PackedVector2Array([Vector2(0.07, 0.0), Vector2(0.05, 0.3), Vector2(0.14, 0.4), Vector2(0.55, 0.48),
				Vector2(0.62, 0.52), Vector2(0.5, 0.56), Vector2(0.0, 0.58)])
			mb.lathe(Transform3D(), prof, Color.WHITE, 22)
			var top := MeshBuilder.new()
			var prof2 := PackedVector2Array([Vector2(0.04, 0.5), Vector2(0.1, 0.6), Vector2(0.34, 0.66), Vector2(0.38, 0.69),
				Vector2(0.3, 0.72), Vector2(0.0, 0.73)])
			top.lathe(Transform3D(Basis(), Vector3(0.12, 0.0, -0.06)), prof2, Color.WHITE, 16)
			mb.append(top)
			for v in mb.verts.size():
				var q := mb.verts[v]
				var r := Vector2(q.x, q.z).length()
				if r > 0.2:
					var a := atan2(q.z, q.x)
					var lobe := 1.0 + 0.09 * sin(a * 7.0 + 1.3) + 0.05 * sin(a * 13.0)
					mb.verts[v] = Vector3(q.x * lobe, q.y + q.x * 0.08, q.z * lobe)
			height = 0.73
		Kind.BRAIN:
			mb.blob(Vector3(0, 0.22, 0), Vector3(0.5, 0.34, 0.46), Color.WHITE, 18, 9, 0.35)
			# (caroços largos: nenhum coral-cérebro é uma meia esfera perfeita)
			var lump := FastNoiseLite.new()
			lump.seed = 31
			lump.frequency = 2.2
			for v in mb.verts.size():
				if mb.verts[v].y > 0.02:
					mb.verts[v] += mb.normals[v] * lump.get_noise_3dv(mb.verts[v]) * 0.06
			height = 0.56
		Kind.TUBES:
			for t in 5:
				var a := TAU * t / 5.0
				var h := rng.randf_range(0.5, 1.0)
				var base := Vector3(cos(a), 0, sin(a)) * (0.13 if t > 0 else 0.0)
				var prof := PackedVector2Array([Vector2(0.07, 0.0), Vector2(0.09, h * 0.5), Vector2(0.11, h), Vector2(0.08, h * 0.97)])
				mb.lathe(Transform3D(Basis(), base), prof, Color.WHITE, 10)
				# (o miolo: escuro, Color.BLACK marca para o _weights)
				mb.lathe(Transform3D(Basis(), base), PackedVector2Array([Vector2(0.08, h * 0.97), Vector2(0.06, h * 0.82),
					Vector2(0.0, h * 0.8)]), Color.BLACK, 10)
		Kind.FAN:
			# Gorgônia: tronco curto, galhos num plano (XY) e as pontes entre galhos vizinhos (a rede)
			mb.quad(Vector3(-0.03, 0, 0), Vector3(0.03, 0, 0), Vector3(0.022, 0.16, 0), Vector3(-0.022, 0.16, 0), Color.WHITE,
				Vector3.BACK)
			var tips: Array = []
			_fan(mb, Vector3(0, 0.16, 0), Vector3.UP, 0.32, 0, rng, tips)
			_lattice(mb, tips, rng)
			# (o leque curvo, como uma concha aberta para a corrente)
			for v in mb.verts.size():
				var q := mb.verts[v]
				mb.verts[v] = Vector3(q.x, q.y, q.z + 0.3 * q.x * q.x)
			height = 1.15
		Kind.PLATE:
			# Prateleiras de coral saindo de uma parede (o plano z = 0), em degraus para cima
			for k in 4:
				var y := 0.1 + k * 0.27
				var x := rng.randf_range(-0.14, 0.14)
				_shelf(mb, Vector3(x, y, 0.0), 0.56 - k * 0.07, rng)
			height = 1.0
		Kind.PILLAR:
			for t in 8:
				var a := TAU * t / 8.0 + rng.randf() * 0.5
				var base := Vector3(cos(a), 0, sin(a)) * (0.0 if t == 0 else rng.randf_range(0.12, 0.3))
				var h := rng.randf_range(0.45, 1.0) if t > 0 else 1.0
				var r := rng.randf_range(0.055, 0.09)
				mb.cylinder(Transform3D(Basis(), base), r * 1.1, r, h, Color.WHITE, 9, false)
				mb.blob(base + Vector3.UP * h, Vector3(r, r * 0.8, r), Color.WHITE, 7, 4)
				# Caroços (as colônias de pólipos fazendo volume) ao longo do pilar
				for n in rng.randi_range(2, 4):
					var ka := rng.randf() * TAU
					mb.blob(base + Vector3(cos(ka) * r * 0.9, rng.randf_range(0.15, 0.9) * h, sin(ka) * r * 0.9),
						Vector3.ONE * r * rng.randf_range(0.45, 0.65), Color.WHITE, 6, 4)
		Kind.BARREL:
			# Esponja-barril: o vaso por fora (com os gomos verticais), a borda de cima ondulada e o miolo
			# escuro por dentro (preto: vira cavidade no _weights)
			mb.lathe(Transform3D(), PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.3, 0.12), Vector2(0.38, 0.45), Vector2(0.42, 0.8),
				Vector2(0.41, 1.0), Vector2(0.37, 1.03)]), Color.WHITE, 22)
			mb.lathe(Transform3D(), PackedVector2Array([Vector2(0.37, 1.03), Vector2(0.33, 0.98), Vector2(0.29, 0.6), Vector2(0.19, 0.32),
				Vector2(0.0, 0.3)]), Color.BLACK, 22)
			for v in mb.verts.size():
				var q := mb.verts[v]
				var ang := atan2(q.z, q.x)
				var ring := Vector2(q.x, q.z)
				# (gomos só por fora e sumindo na borda, onde o miolo encosta)
				if ring.length() > 0.15 and q.y > 0.05 and mb.colors[v].r > 0.5:
					mb.verts[v] += Vector3(q.x, 0, q.z).normalized() * 0.03 * sin(ang * 9.0) * smoothstep(0.05, 0.4, q.y) * (1.0 - smoothstep(0.95, 1.03, q.y))
				if q.y > 0.97:
					mb.verts[v].y += 0.04 * sin(ang * 5.0 + 1.0)
			height = 1.07
		Kind.SOFT:
			# Coral mole (como uma couve-flor): tronco grosso, galhos que se dividem uma vez, cachos de
			# pólipos (bolinhas) nas pontas e mais alguns ao longo dos galhos
			mb.cylinder(Transform3D(), 0.08, 0.06, 0.3, Color.WHITE, 8, false)
			for b in 5:
				var a := TAU * b / 5.0 + rng.randf() * 0.6
				var dir := Vector3(cos(a) * 0.7, 1.0, sin(a) * 0.7).normalized()
				var base := Vector3(0, rng.randf_range(0.2, 0.3), 0)
				var x := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
				var length := rng.randf_range(0.16, 0.24)
				mb.cylinder(Transform3D(Basis(x, dir, x.cross(dir)).orthonormalized(), base), 0.04, 0.028, length, Color.WHITE, 6, false)
				var fork := base + dir * length
				for sub in 2:
					var sa := a + (float(sub) - 0.5) * 1.6
					var sd := (dir + Vector3(cos(sa), 0.3, sin(sa)) * 0.6).normalized()
					var sx := sd.cross(Vector3.FORWARD if absf(sd.z) < 0.9 else Vector3.RIGHT).normalized()
					var sl := rng.randf_range(0.1, 0.16)
					mb.cylinder(Transform3D(Basis(sx, sd, sx.cross(sd)).orthonormalized(), fork), 0.026, 0.018, sl, Color.WHITE, 5, false)
					var tip := fork + sd * sl
					for c in 6:
						var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.02, 0.07)
						var sz := rng.randf_range(0.035, 0.06)
						mb.blob(tip + off, Vector3(sz, sz, sz), Color.WHITE, 6, 4)
				for c in 3:
					var on := base + dir * length * rng.randf_range(0.3, 0.9) + x * rng.randf_range(-0.03, 0.03)
					mb.blob(on, Vector3.ONE * rng.randf_range(0.028, 0.04), Color.WHITE, 5, 3)
			height = 0.7
		Kind.WHIP:
			for t in 7:
				var a := TAU * t / 7.0 + rng.randf() * 0.5
				var dir := Vector3(cos(a) * rng.randf_range(0.1, 0.45), 1.0, sin(a) * rng.randf_range(0.1, 0.45)).normalized()
				var bend := Vector3(cos(a + 1.3), 0.0, sin(a + 1.3)) * rng.randf_range(0.05, 0.2)
				var at := Vector3(cos(a), 0, sin(a)) * 0.04
				var length := rng.randf_range(0.75, 1.15)
				for seg in 6:
					var u := float(seg) / 6.0
					var d := (dir + bend * u).normalized()
					var x := d.cross(Vector3.FORWARD if absf(d.z) < 0.9 else Vector3.RIGHT).normalized()
					var r0 := lerpf(0.022, 0.006, u)
					mb.cylinder(Transform3D(Basis(x, d, x.cross(d)).orthonormalized(), at), r0, r0 * 0.85, length / 6.0, Color.WHITE, 5, false)
					at += d * length / 6.0
				# (a ponta arredondada)
				mb.blob(at, Vector3.ONE * 0.011, Color.WHITE, 4, 3)
			height = 1.1
		Kind.CLAM:
			_clam(mb, null)
			height = 0.55
		Kind.MANTLE:
			_clam(null, mb)
			height = 0.6
		Kind.STAR:
			_star(mb, rng)
			height = 0.08
		Kind.URCHIN:
			mb.blob(Vector3(0, 0.13, 0), Vector3(0.18, 0.14, 0.18), Color.WHITE, 9, 5)
			for t in 64:
				var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.15, 1), rng.randf_range(-1, 1)).normalized()
				var x := d.cross(Vector3.FORWARD if absf(d.z) < 0.9 else Vector3.RIGHT).normalized()
				var root_at := Vector3(0, 0.13, 0) + Vector3(d.x * 0.17, d.y * 0.13, d.z * 0.17)
				mb.cylinder(Transform3D(Basis(x, d, x.cross(d)).orthonormalized(), root_at), 0.012, 0.002, rng.randf_range(0.14, 0.4),
					Color.WHITE, 3, false)
			height = 0.5
		Kind.WORM, Kind.PLUME:
			var tubes := MeshBuilder.new()
			var plumes := MeshBuilder.new()
			_worms(tubes, plumes)
			_weights(tubes, Kind.WORM, 1.3)
			_weights(plumes, Kind.PLUME, 1.3)
			_meshes[Kind.WORM] = tubes.commit()
			_meshes[Kind.PLUME] = plumes.commit()
			return _meshes[kind]
		Kind.ANEMONE:
			# Anêmona: a coluna (pé alargado), o disco oral com a boca escura no meio e três voltas de
			# tentáculos que sobem e se curvam para fora (os de fora mais deitados), com a ponta em bolinha
			mb.lathe(Transform3D(), PackedVector2Array([Vector2(0.17, 0.0), Vector2(0.13, 0.06), Vector2(0.12, 0.16),
				Vector2(0.15, 0.2), Vector2(0.0, 0.21)]), Color.WHITE, 14)
			mb.lathe(Transform3D(), PackedVector2Array([Vector2(0.05, 0.205), Vector2(0.0, 0.2)]), Color.BLACK, 10)
			for t in 36:
				var lap := t % 3
				var a := TAU * t / 36.0 + rng.randf() * 0.15
				var out := Vector3(cos(a), 0.0, sin(a))
				var r := 0.07 + 0.035 * lap
				var at := Vector3(cos(a) * r, 0.2, sin(a) * r)
				var length := rng.randf_range(0.2, 0.3) * (1.0 - 0.12 * lap)
				var dir := (Vector3.UP * (1.6 - 0.45 * lap) + out).normalized()
				for seg in 3:
					var d := (dir + out * 0.35 * seg).normalized()
					var x := d.cross(out.cross(Vector3.UP)).normalized()
					var r0 := lerpf(0.016, 0.009, seg / 3.0)
					mb.cylinder(Transform3D(Basis(x, d, x.cross(d)).orthonormalized(), at), r0, r0 * 0.8, length / 3.0, Color.WHITE, 4, false)
					at += d * length / 3.0
				mb.blob(at, Vector3.ONE * 0.016, Color.WHITE, 4, 3)
			height = 0.5
		Kind.KELP:
			# Kelp gigante (altura 1 = a do talo; a instância estica em y): o talo e lâminas compridas
			# saindo em espiral, subindo e depois caindo um pouco (meio e ponta), mais cheias no alto
			mb.cylinder(Transform3D(), 0.018, 0.01, 1.0, Color.WHITE, 5, false)
			for t in 26:
				var u := float(t) / 25.0
				var y := 0.05 + 0.93 * pow(u, 0.85)
				var a := t * 2.39996
				var out := Vector3(cos(a), 0.0, sin(a))
				var side := out.cross(Vector3.UP).normalized()
				var reach := lerpf(0.32, 0.5, u) * rng.randf_range(0.8, 1.15)
				var base := Vector3(0, y, 0)
				var mid := base + out * reach * 0.5 + Vector3.UP * 0.03
				var tip := base + out * reach + Vector3.UP * 0.012
				var w0 := 0.025
				var w1 := 0.06 * rng.randf_range(0.85, 1.2)
				mb.quad(base - side * w0, base + side * w0, mid + side * w1, mid - side * w1, Color.WHITE, out + Vector3.UP)
				mb.quad(mid - side * w1, mid + side * w1, tip + side * w1 * 0.3, tip - side * w1 * 0.3, Color.WHITE, out + Vector3.UP)
		Kind.GRASS:
			# Capim do mar: onze folhas em fita, de alturas diferentes, curvando para fora e torcendo um
			# pouco, afinando até a ponta
			for t in 11:
				var a := TAU * t / 11.0 + rng.randf() * 0.4
				var out := Vector3(cos(a), 0.0, sin(a))
				var h := rng.randf_range(0.3, 0.62)
				var lean := rng.randf_range(0.08, 0.2)
				var twist := rng.randf_range(-0.6, 0.6)
				var prev := out * 0.02
				var prev_w := out.cross(Vector3.UP).normalized() * 0.024
				for seg in 4:
					var u := float(seg + 1) / 4.0
					var q := out * (0.02 + lean * u * u) + Vector3.UP * h * u
					var w := out.cross(Vector3.UP).normalized().rotated(Vector3.UP, twist * u) * 0.024 * (1.0 - u * 0.85)
					mb.quad(prev - prev_w, prev + prev_w, q + w, q - w, Color.WHITE, out)
					prev = q
					prev_w = w
			height = 0.62
		Kind.STRAND:
			# Fita de alga pendurada: do ponto (y = 0) para baixo, com folhas alternadas
			var prev := Vector3.ZERO
			for seg in 9:
				var u := float(seg + 1) / 9.0
				var q := Vector3(sin(u * 5.0) * 0.06, -u, cos(u * 4.0) * 0.04)
				var side := Vector3(0.045 * (1.0 - u * 0.4), 0, 0.0)
				mb.quad(prev - side, prev + side, q + side * 0.85, q - side * 0.85, Color.WHITE, Vector3.FORWARD)
				# (folha de um lado e do outro, alternando)
				var s := 1.0 if seg % 2 == 0 else -1.0
				var leaf := prev.lerp(q, 0.3)
				mb.tri(leaf + side * s, leaf + side * s * 4.0 + Vector3.DOWN * 0.07, leaf + side * s + Vector3.DOWN * 0.1, Color.WHITE,
					Vector3.FORWARD)
				prev = q
			height = -1.0
		Kind.MOSS:
			for t in 4:
				var a := TAU * t / 4.0 + rng.randf()
				mb.blob(Vector3(cos(a) * 0.25, 0.05, sin(a) * 0.25), Vector3(0.3, 0.18, 0.28) * rng.randf_range(0.7, 1.2), Color.WHITE, 7, 4)
			mb.blob(Vector3(0, 0.08, 0), Vector3(0.36, 0.22, 0.36), Color.WHITE, 8, 4)
			# (tufos pequenos na borda: o musgo fofo)
			for t in 9:
				var a := TAU * t / 9.0 + rng.randf() * 0.4
				mb.blob(Vector3(cos(a) * 0.42, 0.04, sin(a) * 0.42), Vector3.ONE * rng.randf_range(0.07, 0.12), Color.WHITE, 5, 3)
			height = 0.3
		Kind.ROCK:
			# Pedra encaroçada (raio ~1, altura ~1, base em y = 0)
			mb.blob(Vector3(0, 0.42, 0), Vector3(1.0, 0.58, 0.92), Color.WHITE, 14, 8, 0.2)
			for t in 5:
				var a := TAU * t / 5.0 + rng.randf() * 0.6
				var r := rng.randf_range(0.55, 0.8)
				var sz := rng.randf_range(0.3, 0.5)
				mb.blob(Vector3(cos(a) * r, sz * 0.5, sin(a) * r), Vector3(sz, sz * 0.8, sz), Color.WHITE, 8, 5, 0.2)
			# Caroços: empurra cada vértice pela normal com um ruído da posição (mesmo ponto, mesmo empurrão)
			var lump := FastNoiseLite.new()
			lump.seed = 77
			lump.frequency = 1.6
			for v in mb.verts.size():
				mb.verts[v] += mb.normals[v] * lump.get_noise_3dv(mb.verts[v]) * 0.14
			# Camadas (degraus de estrato) e o topo achatado: pedra, não caroço (só pela posição: as cópias
			# do mesmo vértice andam juntas)
			for v in mb.verts.size():
				var q := mb.verts[v]
				var band := 1.0 + 0.05 * signf(sin(q.y * 13.0 + 1.3))
				var y := q.y if q.y < 0.8 else 0.8 + (q.y - 0.8) * 0.35
				mb.verts[v] = Vector3(q.x * band, y, q.z * band)
	_weights(mb, kind, height)
	var mesh := mb.commit()
	_meshes[kind] = mesh
	return mesh


## Cor de vértice pela altura: R = balanço (mais na ponta), G = pólipo (pontas dos corais), B = claro
## nas pontas. Nas algas penduradas a "altura" é para baixo. O que veio preto do construtor (o miolo
## dos tubos) vira cavidade escura.
static func _weights(mb: MeshBuilder, kind: int, height: float) -> void:
	for v in mb.verts.size():
		var y := mb.verts[v].y
		var u := clampf(y / height, 0.0, 1.0)
		var polyp := 0.0
		# Desenho no shader (alfa): 0 = sulcos de coral-cérebro, 0,25 = pedra com musgo, 0,5 = pólipos,
		# 0,85 = cavidade escura, 1 = liso
		var pattern := 1.0
		if mb.colors[v].r < 0.5:
			mb.colors[v] = Color(0.0, 0.0, 0.0, 0.85)
			continue
		match kind:
			Kind.BRAIN:
				pattern = 0.0
			Kind.ROCK:
				pattern = 0.25
			Kind.BRANCH, Kind.TABLE, Kind.TUBES, Kind.PLATE, Kind.PILLAR, Kind.BARREL, Kind.MANTLE, Kind.STAR, Kind.WHIP:
				pattern = 0.5
		match kind:
			Kind.BRANCH, Kind.TUBES, Kind.ANEMONE:
				polyp = smoothstep(0.7, 1.0, u)
			Kind.BRAIN, Kind.TABLE:
				polyp = 0.35 * smoothstep(0.5, 1.0, u)
			Kind.FAN, Kind.PLATE:
				polyp = 0.25 * u
			Kind.PILLAR:
				polyp = 0.8 * smoothstep(0.45, 1.0, u)
			Kind.BARREL:
				polyp = 0.2 * u
			Kind.SOFT:
				polyp = smoothstep(0.4, 0.7, u)
			Kind.WHIP, Kind.STAR:
				polyp = 0.3 * u
			Kind.MANTLE:
				polyp = 0.85
			Kind.PLUME:
				polyp = 1.0
		var sway := 0.0 if kind == Kind.ROCK else pow(u, 1.3)
		mb.colors[v] = Color(sway, polyp, 0.35 + 0.65 * u, pattern)


## Coral ramificado (chifre-de-veado): galhos que se curvam para cima e se dividem até o terceiro nível,
## às vezes com um galho curto saindo do meio, e a ponta arredondada (os pólipos).
static func _branch(mb: MeshBuilder, base: Vector3, dir: Vector3, radius: float, length: float, depth: int,
		rng: RandomNumberGenerator) -> void:
	# Dois segmentos por galho, o segundo virando para cima (o galho se curva)
	var bent := (dir + Vector3.UP * 0.2).normalized()
	var mid := base + dir * length * 0.5
	for seg in 2:
		var d := dir if seg == 0 else bent
		var from := base if seg == 0 else mid
		var ref := Vector3.FORWARD if absf(d.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var x := d.cross(ref).normalized()
		var r0 := radius * (1.0 if seg == 0 else 0.86)
		mb.cylinder(Transform3D(Basis(x, d, x.cross(d)).orthonormalized(), from), r0, r0 * 0.86, length * 0.5 + radius * 0.3, Color.WHITE, 6,
			false)
	var tip := mid + bent * length * 0.5
	if depth >= 3:
		mb.blob(tip, Vector3.ONE * radius * 1.15, Color.WHITE, 6, 3)
		return
	# (os filhos abrem em volta: ângulos espaçados no plano, mais um pouco para cima)
	var count := 3 if depth == 0 else 2
	var a0 := rng.randf() * TAU
	for k in count:
		var a := a0 + TAU * k / count + rng.randf_range(-0.4, 0.4)
		var spread := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.7, 1.1)
		var nd := (bent * 0.7 + spread + Vector3.UP * rng.randf_range(0.2, 0.5)).normalized()
		_branch(mb, tip, nd, radius * 0.74, length * 0.76, depth + 1, rng)
	# Galho curto saindo do meio
	if depth >= 1 and rng.randf() < 0.5:
		var sd := (dir + Vector3(rng.randf_range(-1, 1), 0.4, rng.randf_range(-1, 1))).normalized()
		_branch(mb, mid, sd, radius * 0.6, length * 0.45, 3, rng)


## Leque (gorgônia): galhos num plano (XY), fininhos, dos dois lados; guarda o meio de cada galho
## (por nível) em `tips` para as pontes da rede.
static func _fan(mb: MeshBuilder, base: Vector3, dir: Vector3, length: float, depth: int, rng: RandomNumberGenerator,
		tips: Array) -> void:
	var tip := base + dir * length
	var side := Vector3(-dir.y, dir.x, 0.0).normalized() * maxf(0.02 - depth * 0.003, 0.006)
	mb.quad(base - side, base + side, tip + side * 0.8, tip - side * 0.8, Color.WHITE, Vector3.BACK)
	while tips.size() <= depth:
		tips.append([])
	tips[depth].append((base + tip) * 0.5)
	if depth >= 5:
		return
	for k in 2:
		var ang := (0.42 if k == 0 else -0.42) + rng.randf_range(-0.14, 0.14)
		var nd := Vector3(dir.x * cos(ang) - dir.y * sin(ang), dir.x * sin(ang) + dir.y * cos(ang), 0.0).normalized()
		_fan(mb, tip, nd, length * 0.74, depth + 1, rng, tips)


## As pontes finas entre galhos vizinhos do mesmo nível do leque (a rede da gorgônia).
static func _lattice(mb: MeshBuilder, tips: Array, rng: RandomNumberGenerator) -> void:
	for depth in range(2, tips.size()):
		var row: Array = tips[depth]
		row.sort_custom(func(a: Vector3, b: Vector3) -> bool: return atan2(a.x, a.y) < atan2(b.x, b.y))
		for k in row.size() - 1:
			var a: Vector3 = row[k]
			var b: Vector3 = row[k + 1]
			if a.distance_to(b) > 0.3 or rng.randf() < 0.25:
				continue
			var d := (b - a).normalized()
			var side := Vector3(-d.y, d.x, 0.0) * 0.006
			mb.quad(a - side, a + side, b + side, b - side, Color.WHITE, Vector3.BACK)


## Uma prateleira de coral de placa: meio disco (raio r) saindo da parede (z = 0) para +z em `at`,
## inclinada um pouco para cima, com a borda ondulada e 4 cm de espessura.
static func _shelf(mb: MeshBuilder, at: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	# Meio disco em anéis saindo da parede: a borda ondulada subindo um pouco, as linhas de crescimento
	# (anéis em relevo) e a espessura na borda
	const STEPS := 14
	const RINGS := 4
	var wave := rng.randf() * TAU
	var down := Vector3.DOWN * 0.035
	var grid: Array[PackedVector3Array] = []
	for ring in RINGS + 1:
		var u := float(ring) / RINGS
		var row := PackedVector3Array()
		for k in STEPS + 1:
			var th := PI * float(k) / STEPS
			var rr := r * u * (1.0 + 0.1 * sin(th * 6.0 + wave) * u)
			var z := sin(th) * rr
			row.append(at + Vector3(cos(th) * rr, 0.14 * z + 0.06 * u * u + 0.012 * sin(u * PI * 5.0), z + 0.02))
		grid.append(row)
	for ring in RINGS:
		for k in STEPS:
			var a := grid[ring][k]
			var b := grid[ring][k + 1]
			var c := grid[ring + 1][k + 1]
			var d := grid[ring + 1][k]
			mb.quad(a, b, c, d, Color.WHITE, Vector3.UP)
			mb.quad(a + down, d + down, c + down, b + down, Color.WHITE, Vector3.DOWN)
	var rim := grid[RINGS]
	for k in STEPS:
		var out := (rim[k] + rim[k + 1]) * 0.5 - at
		out.y = 0.0
		mb.quad(rim[k], rim[k + 1], rim[k + 1] + down, rim[k] + down, Color.WHITE, out)


## Marisco gigante: as duas conchas com gomos (meia casca alongada de cada lado, a borda de cima em
## zigue-zague) em `shells` e o manto colorido saindo entre elas em `mantle` (qualquer um pode ser nulo).
static func _clam(shells: MeshBuilder, mantle: MeshBuilder) -> void:
	var length := 1.0
	var width := 0.34
	var h := 0.5
	var gap := 0.07
	var nu := 8
	var nv := 14
	for side: float in [1.0, -1.0]:
		var grid: Array[PackedVector3Array] = []
		for iv in nv + 1:
			var v := float(iv) / nv
			var z := (v - 0.5) * length
			var taper := sqrt(maxf(1.0 - pow(v * 2.0 - 1.0, 2.0), 0.0))
			# (gomos: o raio ondula ao longo do comprimento, mais forte em cima)
			var rib := 1.0 + 0.2 * sin(v * PI * 9.0)
			var row := PackedVector3Array()
			for iu in nu + 1:
				var u := float(iu) / nu
				var phi := lerpf(-PI * 0.5, PI * 0.42, u)
				var r := width * taper * lerpf(1.0, rib, u)
				row.append(Vector3(side * (gap + r * cos(phi)), (h * 0.5 + h * 0.5 * sin(phi)) * lerpf(0.4, 1.0, taper), z))
			grid.append(row)
		if shells != null:
			for iv in nv:
				for iu in nu:
					var a := grid[iv][iu]
					var b := grid[iv + 1][iu]
					var c := grid[iv + 1][iu + 1]
					var d := grid[iv][iu + 1]
					var out := Vector3(side, 0.2, 0.0)
					shells.quad(a, b, c, d, Color.WHITE, out)
					shells.quad(a, d, c, b, Color.WHITE, -out)
		if mantle != null and side > 0.0:
			# Manto: a faixa entre as bordas de cima das duas conchas, estufada e ondulada
			for iv in nv:
				var l0 := grid[iv][nu]
				var l1 := grid[iv + 1][nu]
				var r0 := Vector3(-l0.x, l0.y, l0.z)
				var r1 := Vector3(-l1.x, l1.y, l1.z)
				var lift0 := Vector3.UP * (0.05 + 0.03 * sin(float(iv) * 1.9))
				var lift1 := Vector3.UP * (0.05 + 0.03 * sin(float(iv + 1) * 1.9))
				var m0 := (l0 + r0) * 0.5 + lift0
				var m1 := (l1 + r1) * 0.5 + lift1
				for pair: Array in [[l0 * Vector3(1.15, 1, 1), l1 * Vector3(1.15, 1, 1), m1, m0], [m0, m1, r1 * Vector3(1.15, 1, 1), r0 * Vector3(1.15, 1, 1)]]:
					mantle.quad(pair[0], pair[1], pair[2], pair[3], Color.WHITE, Vector3.UP)


## Estrela-do-mar: o disco abaulado no meio e cinco braços roliços afinando (seções em meia elipse ao
## longo de cada braço), cada um num comprimento e com a ponta um pouco erguida e torta.
static func _star(mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	mb.blob(Vector3(0, 0.025, 0), Vector3(0.13, 0.06, 0.13), Color.WHITE, 10, 4)
	const SEGS := 6
	const SIDES := 6
	for arm in 5:
		var a := TAU * arm / 5.0 + rng.randf_range(-0.08, 0.08)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := dir.cross(Vector3.UP).normalized()
		var reach := rng.randf_range(0.4, 0.5)
		var bend := rng.randf_range(-0.12, 0.12)
		var rings: Array[PackedVector3Array] = []
		for k in SEGS + 1:
			var t := float(k) / SEGS
			# (o braço afina, a ponta sobe e entorta um pouco para o lado)
			var c := dir * (0.05 + t * reach) + side * bend * t * t + Vector3.UP * (0.015 + 0.06 * t * t * t)
			var w := lerpf(0.085, 0.018, t)
			var h := lerpf(0.055, 0.014, t)
			var ring := PackedVector3Array()
			for j in SIDES + 1:
				var u := PI * float(j) / SIDES
				ring.append(c + side * cos(u) * w + Vector3.UP * sin(u) * h)
			rings.append(ring)
		for k in SEGS:
			for j in SIDES:
				var mid := (rings[k][j] + rings[k + 1][j + 1]) * 0.5
				var axis_pt := dir * (0.05 + (k + 0.5) / SEGS * reach)
				mb.quad(rings[k][j], rings[k + 1][j], rings[k + 1][j + 1], rings[k][j + 1], Color.WHITE, mid - axis_pt)
		# (a ponta fechada)
		var tip := rings[SEGS]
		var tip_c := dir * (0.05 + reach * 1.04) + side * bend + Vector3.UP * 0.075
		for j in SIDES:
			mb.tri(tip[j], tip[j + 1], tip_c, Color.WHITE, dir)


## Vermes tubulares: tubos brancos, um pouco tortos, em `tubes` e a pluma vermelha na ponta de cada um
## em `plumes` (os dois com a mesma semente: as plumas ficam nas pontas).
static func _worms(tubes: MeshBuilder, plumes: MeshBuilder) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4041
	for t in 18:
		var a := rng.randf() * TAU
		var at := Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * 0.32
		var dir := Vector3(rng.randf_range(-0.25, 0.25), 1.0, rng.randf_range(-0.25, 0.25)).normalized()
		var r := rng.randf_range(0.03, 0.05)
		var length := rng.randf_range(0.6, 1.3)
		for seg in 3:
			var d := (dir + Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12))).normalized()
			var x := d.cross(Vector3.FORWARD if absf(d.z) < 0.9 else Vector3.RIGHT).normalized()
			tubes.cylinder(Transform3D(Basis(x, d, x.cross(d)).orthonormalized(), at), r, r * 0.95, length / 3.0, Color.WHITE, 6, false)
			# (anel de crescimento na junta)
			tubes.cylinder(Transform3D(Basis(x, d, x.cross(d)).orthonormalized(), at + d * (length / 3.0 - 0.025)), r * 1.25, r * 1.2, 0.03,
				Color.WHITE, 6, false)
			at += d * length / 3.0
			dir = d
		plumes.blob(at + dir * 0.06, Vector3(r * 1.9, 0.09, r * 1.9), Color.WHITE, 7, 4)
		for f in 8:
			var fa := TAU * f / 8.0 + rng.randf() * 0.3
			var fd := (dir + Vector3(cos(fa), 0.25, sin(fa)) * 0.9).normalized()
			plumes.quad(at + Vector3(-0.012, 0, 0), at + Vector3(0.012, 0, 0), at + fd * 0.13 + Vector3(0.008, 0, 0),
				at + fd * 0.13 - Vector3(0.008, 0, 0), Color.WHITE, Vector3(fd.x, 0.0, fd.z))
