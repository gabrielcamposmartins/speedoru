class_name SeaFloor
extends RefCounted
## Leito do mar da pista no fundo do mar (Atlantis Abyss): uma grade de alturas sob a pista e em
## volta dela (CELL m, em blocos de CHUNK m com visibility range, para o recorte de visão), com
## areia em ondinhas, rocha nas encostas, manchas de algas e a cáustica da água (seabed.gdshader).
## Embaixo da pista o fundo fica layout.seabed_depth m abaixo dela (a laje e os arcos do aqueduto,
## SeaCauseway, preenchem o vão); na reta do anfiteatro (PLAZA) quase rente; nas fossas
## (layout.trenches) despenca até TRENCH_DEPTH formando um cânion; longe da pista, dunas e cadeias
## de montanhas (ruído em cristas, mais um anel de serras em volta da área da pista) e montanhas
## avulsas pontudas à vista da pista (uma a cada ~PEAK_SPACING m), que sobem até perto da superfície
## (MOUNTAIN_BELOW_WATER). Nos trechos em cânion (SeaCanyon) o chão fica baixo entre o tubo e a
## parede (a face é uma malha própria; o leito passa escondido atrás dela) e sobe na serra atrás.
## Sem colisão: as barreiras seguram o carro e a laje DeckFloor fica sob os pisos.

const CELL := 10.0
const CHUNK := 250.0
## Quanto o leito se estende além da pista (m).
const MARGIN := 1100.0
## Trecho (s) da reta do anfiteatro, onde o fundo fica logo abaixo da laje (praça das arquibancadas).
const PLAZA := Vector2(-520.0, 500.0)
const PLAZA_DEPTH := 1.3
const TRENCH_DEPTH := 80.0
## Distância (além da borda da pista) em que o fundo passa da altura junto à pista para as dunas.
const NEAR := 30.0
const FAR := 100.0
## Até onde o leito é desenhado (a névoa da água esconde antes).
const VISIBILITY := 1400.0
## Altura máxima das montanhas: tantos metros abaixo da linha d'água.
const MOUNTAIN_BELOW_WATER := 3.0

static var _noise: FastNoiseLite
static var _ridge: FastNoiseLite
static var _mask: FastNoiseLite
static var _material: ShaderMaterial
## Área da pista (para o anel de montanhas em volta dela).
static var _bounds := Rect2()
static var _bounds_path: TrackPath
## Montanhas avulsas à vista da pista: [x, z, raio, altura, ângulo, alongamento], sorteadas por pista.
static var _peaks: Array = []
static var _peaks_path: TrackPath

## Uma montanha avulsa a cada ~PEAK_SPACING m de pista (lados alternados), a PEAK_OFFSET m da borda.
const PEAK_SPACING := 300.0
const PEAK_OFFSET := Vector2(115.0, 230.0)
## Distância mínima do pico a qualquer trecho da pista (o traçado passa perto de si mesmo).
const PEAK_CLEAR := 105.0

## Lugares do leito já ocupados por construções, vulcões e destroços: (x, z, raio, altura do topo).
## Quem constrói depois não se sobrepõe (claimed), os recifes não nascem dentro e os bichos grandes
## passam por cima (claim_top). Zerado a cada geração (build); numa grade de CLAIM_CELL m para as
## consultas (o capim pergunta milhares de vezes).
static var _claims: Array[Vector4] = []
static var _claim_grid := {}
const CLAIM_CELL := 50.0


## Ocupa o círculo em volta de `pos` (raio em m) até a altura `top`.
static func claim(pos: Vector3, radius: float, top: float) -> void:
	var idx := _claims.size()
	_claims.append(Vector4(pos.x, pos.z, radius, top))
	for cx in range(floori((pos.x - radius) / CLAIM_CELL), floori((pos.x + radius) / CLAIM_CELL) + 1):
		for cz in range(floori((pos.z - radius) / CLAIM_CELL), floori((pos.z + radius) / CLAIM_CELL) + 1):
			var key := Vector2i(cx, cz)
			if not _claim_grid.has(key):
				_claim_grid[key] = PackedInt32Array()
			_claim_grid[key].append(idx)


## Índices dos lugares ocupados perto do círculo (x, z, raio).
static func _near_claims(x: float, z: float, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for cx in range(floori((x - radius) / CLAIM_CELL), floori((x + radius) / CLAIM_CELL) + 1):
		for cz in range(floori((z - radius) / CLAIM_CELL), floori((z + radius) / CLAIM_CELL) + 1):
			var key := Vector2i(cx, cz)
			if _claim_grid.has(key):
				out.append_array(_claim_grid[key])
	return out


## O círculo (pos, raio) encosta em algum lugar ocupado.
static func claimed(pos: Vector3, radius: float) -> bool:
	if _claims.is_empty():
		return false
	for k in _near_claims(pos.x, pos.z, radius + 30.0):
		var c := _claims[k]
		if Vector2(pos.x - c.x, pos.z - c.y).length() < radius + c.z:
			return true
	return false


## Topo do que ocupa (x, z), com `margin` m de folga em volta (−INF se nada).
static func claim_top(x: float, z: float, margin := 0.0) -> float:
	var top := -INF
	if _claims.is_empty():
		return top
	for k in _near_claims(x, z, margin + 30.0):
		var c := _claims[k]
		if Vector2(x - c.x, z - c.y).length() < c.z + margin:
			top = maxf(top, c.w)
	return top


## Sorteia as montanhas avulsas da pista (uma vez por traçado).
static func _ensure_peaks(track: RaceTrack) -> void:
	if _peaks_path == track.path:
		return
	_peaks_path = track.path
	_peaks.clear()
	var p := track.path
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var s := rng.randf() * PEAK_SPACING
	var side := 1
	while s < p.length:
		var i := p.index_at(s)
		var c := p.frame_at(s, side * (p.half_width(i, side) + rng.randf_range(PEAK_OFFSET.x, PEAK_OFFSET.y)), 0.0).origin
		var pr := p.project(Vector3(c.x, 0.0, c.z), true, false)
		if absf(pr.y) > PEAK_CLEAR:
			_peaks.append([c.x, c.z, rng.randf_range(85.0, 140.0), rng.randf_range(58.0, 78.0), rng.randf() * PI,
				rng.randf_range(1.2, 2.0)])
		s += PEAK_SPACING * rng.randf_range(0.75, 1.25)
		if rng.randf() < 0.7:
			side = -side


## Altura somada pelas montanhas avulsas em (x, z): cristas alongadas, encosta côncava e pontuda,
## com penhascos (ruído em cristas por cima).
static func _peak_height(x: float, z: float) -> float:
	_init_noise()
	var h := 0.0
	for pk: Array in _peaks:
		var dx: float = x - pk[0]
		var dz: float = z - pk[1]
		var r: float = pk[2]
		if dx * dx + dz * dz > r * r * 4.5:
			continue
		var ca := cos(pk[4])
		var sa := sin(pk[4])
		# (no eixo da crista a montanha vai mais longe: distância "esticada")
		var u: float = (dx * ca + dz * sa) / pk[5]
		var v := -dx * sa + dz * ca
		var d := sqrt(u * u + v * v) / r
		if d < 1.0:
			var crag := 1.0 - absf(_ridge.get_noise_2d(x * 2.4 + 300.0, z * 2.4))
			h = maxf(h, pk[3] * pow(1.0 - d, 2.1) * (0.7 + 0.6 * crag * crag))
	return h


## Peso (0..1) do anel de montanhas: cresce com a distância além da área da pista.
static func _ring(x: float, z: float) -> float:
	var dx := maxf(maxf(_bounds.position.x - x, x - _bounds.end.x), 0.0)
	var dz := maxf(maxf(_bounds.position.y - z, z - _bounds.end.y), 0.0)
	return smoothstep(120.0, 520.0, sqrt(dx * dx + dz * dz))


## Altura do leito no ponto (x, z) do mundo.
static func ground(track: RaceTrack, x: float, z: float) -> float:
	if _bounds_path != track.path:
		_bounds_path = track.path
		_bounds = track.path.bounds()
	_ensure_peaks(track)
	# A serra atrás das paredes do cânion (SeaCanyon) entra no relevo de longe
	var canyon := SeaCanyon.profile(track)
	var ridge := SeaCanyon.ridge_at(canyon, x, z)
	var far := maxf(_dunes(x, z, track.layout.water_level, _ring(x, z), _peak_height(x, z)), ridge)
	var pr := track.path.project(Vector3(x, 0.0, z), false, false)
	if pr.y == INF:
		return far
	var p := track.path
	var s := pr.x
	var i := p.index_at(s)
	var side := 1 if pr.y > 0.0 else -1
	var edge := p.half_width(i, side) + 3.0
	var d := absf(pr.y) - edge
	var ht := p.height_at(s)
	var plaza := _span_weight(track, s, PLAZA.x, PLAZA.y, 70.0)
	var trench := _trench(track, s)
	var depth := _depth(track, s)
	var near := ht - depth
	# Cânion da fossa: paredes mais longe e mais altas que as encostas comuns
	var w := smoothstep(NEAR + trench * 25.0, FAR, d)
	var y := lerpf(near, maxf(far, near) if trench > 0.5 else far, w)
	# Junto à pista nunca acima dela (laje, barreiras e boxes)
	if d < 25.0:
		y = minf(y, ht - lerpf(1.0, depth, clampf(1.0 - plaza, 0.0, 1.0)))
	# Nos trechos em cânion: o chão entre o tubo e a parede, a encosta atrás da face e a crista
	return SeaCanyon.carve(canyon, i, side, absf(pr.y), y, ridge)


## Altura do leito junto à pista em s, sem o cânion: layout.seabed_depth abaixo da pista, quase rente
## na praça do anfiteatro e TRENCH_DEPTH nas fossas.
static func near_height(track: RaceTrack, s: float) -> float:
	return track.path.height_at(s) - _depth(track, s)


static func _depth(track: RaceTrack, s: float) -> float:
	var depth := lerpf(track.layout.seabed_depth, PLAZA_DEPTH, _span_weight(track, s, PLAZA.x, PLAZA.y, 70.0))
	return lerpf(depth, TRENCH_DEPTH, _trench(track, s))


static func _trench(track: RaceTrack, s: float) -> float:
	var trench := 0.0
	for t: Vector2 in _trenches(track):
		trench = maxf(trench, _span_weight(track, s, t.x, t.y, 90.0))
	return trench


## Peso (0..1) de s estar dentro do trecho [s0, s1], com rampas de `ramp` m nas pontas.
static func _span_weight(track: RaceTrack, s: float, s0: float, s1: float, ramp: float) -> float:
	var length := track.path.length
	var into := fposmod(s - s0, length)
	var span := fposmod(s1 - s0, length)
	if into <= span:
		return minf(smoothstep(0.0, ramp, into), smoothstep(0.0, ramp, span - into))
	return 0.0


static func _trenches(track: RaceTrack) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for t in track.layout.trenches:
		out.append(t)
	return out


## Ruídos do relevo (criados na primeira consulta).
static func _init_noise() -> void:
	if _noise != null:
		return
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0035
	_noise.fractal_octaves = 4
	_noise.seed = 4471
	_ridge = FastNoiseLite.new()
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.frequency = 0.0024
	_ridge.fractal_octaves = 3
	_ridge.seed = 913
	_mask = FastNoiseLite.new()
	_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mask.frequency = 0.0011
	_mask.seed = 5150


## Dunas e morros suaves longe da pista e as cadeias de montanhas (cristas afiadas, em grupos).
static func _dunes(x: float, z: float, water: float, ring := 0.0, peak := 0.0) -> float:
	_init_noise()
	var base := -17.0 + _noise.get_noise_2d(x, z) * 11.0 + _noise.get_noise_2d(x * 3.1 + 900.0, z * 3.1) * 2.0
	var ridge := pow(1.0 - absf(_ridge.get_noise_2d(x, z)), 3.0)
	var group := maxf(smoothstep(-0.3, 0.25, _mask.get_noise_2d(x, z)), ring)
	var mountain := (ridge * (50.0 + ring * 12.0) + absf(_noise.get_noise_2d(x * 5.0, z * 5.0)) * 5.0) * group + ring * 10.0
	# Picos arredondados abaixo da superfície (comprimidos perto do teto, sem platôs cortados)
	var h := base + maxf(mountain, peak)
	var knee := water - MOUNTAIN_BELOW_WATER - 12.0
	if h > knee:
		h = knee + 12.0 * (1.0 - exp((knee - h) / 12.0))
	return h


static func build(track: RaceTrack, parent: Node3D) -> void:
	# Primeira etapa do fundo do mar: zera os corais e algas registrados pela pista anterior e os
	# lugares ocupados
	SeaReef.reset(track)
	_claims.clear()
	_claim_grid.clear()
	var root := Node3D.new()
	root.name = "SeaFloor"
	parent.add_child(root)
	var b := track.path.bounds().grow(MARGIN)
	var nx := int(ceil(b.size.x / CELL)) + 1
	var nz := int(ceil(b.size.y / CELL)) + 1
	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			heights[iz * nx + ix] = ground(track, b.position.x + ix * CELL, b.position.y + iz * CELL)
	var per := int(CHUNK / CELL)
	var mat := material()
	for cz in range(0, nz - 1, per):
		for cx in range(0, nx - 1, per):
			var mi := MeshInstance3D.new()
			mi.name = "Seabed_%d_%d" % [cx / per, cz / per]
			mi.mesh = _chunk(heights, nx, nz, cx, cz, mini(per, nx - 1 - cx), mini(per, nz - 1 - cz), b.position, mat)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = VISIBILITY
			mi.visibility_range_end_margin = 60.0
			# (a serra que passa do mar aparece na janela do céu vista de baixo d'água)
			if (mi.mesh as ArrayMesh).get_aabb().end.y > track.layout.water_level:
				mi.layers |= SeaWorld.WINDOW_LAYER
			root.add_child(mi)


## Malha indexada de um bloco da grade (normais pelas diferenças centrais).
static func _chunk(heights: PackedFloat32Array, nx: int, nz: int, cx: int, cz: int, w: int, h: int, origin: Vector2,
		mat: Material) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for iz in range(cz, cz + h + 1):
		for ix in range(cx, cx + w + 1):
			var y := heights[iz * nx + ix]
			verts.append(Vector3(origin.x + ix * CELL, y, origin.y + iz * CELL))
			var hl := heights[iz * nx + maxi(ix - 1, 0)]
			var hr := heights[iz * nx + mini(ix + 1, nx - 1)]
			var hd := heights[maxi(iz - 1, 0) * nx + ix]
			var hu := heights[mini(iz + 1, nz - 1) * nx + ix]
			normals.append(Vector3(hl - hr, 2.0 * CELL, hd - hu).normalized())
	var row := w + 1
	for iz in h:
		for ix in w:
			var a := iz * row + ix
			# (sentido horário visto de cima = face para cima, como no MeshBuilder)
			indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/track/seabed.gdshader")
		TrackMaterials.register_sea(_material)
		# Rede de luz mais fina no fundo (células de ~3 m)
		_material.set_shader_parameter("caustic_scale", 0.32)
	return _material
