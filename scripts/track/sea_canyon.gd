class_name SeaCanyon
extends RefCounted
## O cânion da pista no fundo do mar (Atlantis Abyss): na maior parte da volta o tubo de vidro corre
## entre duas paredes de rocha que sobem do leito até perto da superfície (layout.canyons: trechos e a
## folga de cada lado entre o tubo e o pé da parede). Onde a pista chega na superfície as paredes
## sobem acima do mar e viram uma cadeia de montanhas em volta dela (as cachoeiras: PoseidonGate).
## Atrás de cada parede uma serra (no leito, SeaFloor: crista e a descida até longe), então os
## cânions enchem o horizonte.
##  * profile(): por amostra da pista, presença do cânion (rampas nas pontas), pé, topo e chão;
##  * a face é uma malha própria (o leito tem células de 10 m): três patamares, a cornija no alto e o
##    ruído da rocha; material canyon_rock.gdshader (da cor da rocha do leito até bem mais escura por
##    textura de ruído, estratos, rachaduras, musgo e areia nos patamares, cáustica; acima do mar,
##    rocha seca com vegetação);
##  * nela crescem corais, leques, esponjas, anêmonas, kelp, capim, algas penduradas e musgo, com
##    pedras no pé e nos patamares (SeaReef); nas montanhas acima do mar, arbustos e árvores
##    (pinheiros-mansos, ciprestes, pinheiros) na crista e na serra; e as luzes coloridas submarinas
##    (cristais acesos, um facho e luz de verdade), também nos trechos abertos.
## Só visual: nada tem colisão (o servidor pula a etapa).

## Rampa (m de pista) em que as paredes sobem e descem nas pontas de cada trecho.
const RAMP := 80.0
## Avanço horizontal da face por metro de altura (~70°), patamares incluídos; varia ao longo do
## cânion entre SLOPE_RANGE (penhascos quase retos e encostas em terraços).
const SLOPE := 0.36
const SLOPE_RANGE := Vector2(0.24, 0.52)
## Parte do avanço que fica nos três patamares (o resto é a face inclinada entre eles).
const LEDGES := 0.42
## Meia altura (fração da parede) de cada patamar e quantos intervalos de anel entre eles.
const LEDGE_HALF := 0.008
const SEGMENTS := [5, 4, 4, 5]
## Quanto a cornija avança sobre o cânion no alto (m).
const CORNICE := 3.0
## Topo do cânion: tantos metros abaixo da linha d'água (pelo ruído, entre os dois).
const TOP_BELOW := Vector2(2.5, 8.0)
## Trecho emerso: folga até o pé das montanhas e altura delas acima do mar (pelo ruído, picos).
const MOUNTAIN_GAP := 24.0
const MOUNTAIN_TOP := Vector2(34.0, 112.0)
## Serra atrás da borda (m): crista e depois a descida até o leito longe.
const RIDGE := 200.0
const RIDGE_CREST := 34.0
const RIDGE_CELL := 8.0
## O leito atrás da face fica tantos metros para dentro da rocha (escondido pela malha).
const HIDDEN := 6.0
## Amostras de pista por pedaço da malha (recorte de visão).
const CHUNK := 70
const VISIBILITY := 1500.0
## Luzes coloridas: uma a cada LIGHT_SPACING m de cânion (lados alternados) e a cada OPEN_SPACING m
## nos trechos abertos.
const LIGHT_SPACING := 22.0
## Jardins de corais elaborados nos patamares e cavernas na face (espaço ao longo de cada parede, m).
const GARDEN_SPACING := 17.0
const CAVE_SPACING := 64.0
const OPEN_SPACING := 44.0
const LIGHT_COLORS := [Color(0.2, 0.95, 1.0), Color(1.0, 0.3, 0.75), Color(0.62, 0.36, 1.0), Color(1.0, 0.68, 0.22),
	Color(0.35, 1.0, 0.55), Color(1.0, 0.42, 0.38)]
## Energia das luzes por período (dia, entardecer, noite).
const LIGHT_ENERGY := [3.6, 5.0, 7.5]
const SHRUBS := [Color(0.27, 0.45, 0.18), Color(0.36, 0.5, 0.2), Color(0.22, 0.38, 0.2), Color(0.42, 0.46, 0.22)]
## Árvores das montanhas (TrackTrees.Species) e o peso de cada uma.
const TREES := [[TrackTrees.Species.STONE_PINE, 0.3], [TrackTrees.Species.CYPRESS, 0.25], [TrackTrees.Species.PINE, 0.2],
	[TrackTrees.Species.BUSH, 0.25]]

static var _cache := {}
static var _crag: FastNoiseLite
static var _along: FastNoiseLite
static var _hills: FastNoiseLite
static var _rock_mat: ShaderMaterial
static var _beam_mat: ShaderMaterial
static var _lights: Array[OmniLight3D] = []
## Bocas de caverna (cave_mouth.gdshader) e onde ficam.
static var _caves := MeshBuilder.new()
static var _cave_spots: Array[Vector3] = []
static var _cave_mat: ShaderMaterial
static var _rng := RandomNumberGenerator.new()


# ---------------------------------------------------------------------------
# Perfil
# ---------------------------------------------------------------------------
## Perfil do cânion (uma vez por traçado): w (presença 0..1), e (montanha 0..1), floor (chão), foot e
## top ([esquerda, direita]: distância do pé à linha central e altura do topo) e a grade da serra.
static func profile(track: RaceTrack) -> Dictionary:
	if _cache.get("path") == track.path:
		return _cache
	_init_noise()
	var p := track.path
	var n := p.size()
	var water := track.layout.water_level
	var tube := SeaTube.profile(track)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var gap_l := PackedFloat32Array()
	gap_l.resize(n)
	var gap_r := PackedFloat32Array()
	gap_r.resize(n)
	for i in n:
		var s := p.s_at(i)
		gap_l[i] = 12.0
		gap_r[i] = 12.0
		for c: Vector4 in track.layout.canyons:
			if fposmod(s - c.x, p.length) <= fposmod(c.y - c.x, p.length):
				raw[i] = 1.0
				gap_l[i] = c.z
				gap_r[i] = c.w
	# Rampas pela média móvel (trechos vizinhos se emendam sem as paredes baixarem entre eles)
	var w := _smooth(raw, int(RAMP * 0.5 / p.spacing))
	var e := PackedFloat32Array()
	e.resize(n)
	for i in n:
		# Montanhas: a pista chegando na superfície e acima dela
		e[i] = smoothstep(water - 20.0, water, p.points[i].y)
	e = _smooth(e, int(60.0 / p.spacing))
	gap_l = _smooth(gap_l, int(25.0 / p.spacing))
	gap_r = _smooth(gap_r, int(25.0 / p.spacing))
	var clear_l := PackedFloat32Array()
	clear_l.resize(n)
	var clear_r := PackedFloat32Array()
	clear_r.resize(n)
	for i in n:
		w[i] = maxf(smoothstep(0.0, 1.0, w[i]), e[i])
		clear_l[i] = SeaTube.clearance(track, i, 1)
		clear_r[i] = SeaTube.clearance(track, i, -1)
	# (o pé não acompanha cada degrau das arquibancadas e boxes)
	clear_l = _smooth(RaceTrack._dilate(clear_l, 8), 6)
	clear_r = _smooth(RaceTrack._dilate(clear_r, 8), 6)
	var floor_y := PackedFloat32Array()
	floor_y.resize(n)
	var foot := [PackedFloat32Array(), PackedFloat32Array()]
	var top := [PackedFloat32Array(), PackedFloat32Array()]
	var feet_l := PackedFloat32Array()
	feet_l.resize(n)
	var feet_r := PackedFloat32Array()
	feet_r.resize(n)
	var top_l := PackedFloat32Array()
	top_l.resize(n)
	var top_r := PackedFloat32Array()
	top_r.resize(n)
	for i in n:
		var s := p.s_at(i)
		floor_y[i] = SeaFloor.near_height(track, s)
		# Altura do tubo (ou do túnel) ali: a parede passa dele
		var th := 0.0
		if track.in_tunnel(i):
			th = GlassTunnel.HEIGHT
		elif tube.on[i] == 1:
			th = tube.height[i]
		for k in 2:
			var side := 1 if k == 0 else -1
			var gap: float = gap_l[i] if k == 0 else gap_r[i]
			var clear: float = clear_l[i] if k == 0 else clear_r[i]
			var meander := _along.get_noise_1d(s * 0.8 + 900.0 * side) * 3.5 * w[i]
			var f := clear + lerpf(gap, MOUNTAIN_GAP, e[i]) + meander
			var below := lerpf(TOP_BELOW.x, TOP_BELOW.y, 0.5 + 0.5 * _along.get_noise_1d(s * 1.3 + 2000.0 * side))
			var canyon_top := minf(maxf(water - below, p.points[i].y + th + 3.0), water - 1.2)
			var peak := pow(1.0 - absf(_along.get_noise_1d(s * 0.9 + 4000.0 + 700.0 * side)), 2.2)
			var mountain_top := water + lerpf(MOUNTAIN_TOP.x, MOUNTAIN_TOP.y, peak)
			var t := maxf(lerpf(canyon_top, mountain_top, e[i]), floor_y[i] + 6.0)
			if k == 0:
				feet_l[i] = f
				top_l[i] = t
			else:
				feet_r[i] = f
				top_r[i] = t
	foot = [feet_l, feet_r]
	top = [top_l, top_r]
	# Inclinação da face por trecho: penhascos quase retos e encostas mais deitadas (em terraços)
	var slope := PackedFloat32Array()
	slope.resize(n)
	for i in n:
		slope[i] = lerpf(SLOPE_RANGE.x, SLOPE_RANGE.y, 0.5 + 0.5 * _along.get_noise_1d(p.s_at(i) * 0.55 + 7300.0))
	slope = _smooth(slope, int(30.0 / p.spacing))
	var data := {"path": p, "w": w, "e": e, "floor": floor_y, "foot": foot, "top": top, "slope": slope}
	_ridge_grid(track, data)
	_cache = data
	return data


## Média móvel circular de raio `r` amostras.
static func _smooth(a: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var n := a.size()
	if r <= 0 or n == 0:
		return a
	var out := PackedFloat32Array()
	out.resize(n)
	var acc := 0.0
	for d in range(-r, r + 1):
		acc += a[posmod(d, n)]
	for i in n:
		out[i] = acc / (2 * r + 1)
		acc += a[(i + r + 1) % n] - a[posmod(i - r, n)]
	return out


static func _init_noise() -> void:
	if _crag != null:
		return
	_crag = FastNoiseLite.new()
	_crag.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_crag.frequency = 0.11
	_crag.fractal_octaves = 3
	_crag.seed = 6021
	_along = FastNoiseLite.new()
	_along.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_along.frequency = 0.012
	_along.fractal_octaves = 2
	_along.seed = 6022
	_hills = FastNoiseLite.new()
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.018
	_hills.fractal_octaves = 3
	_hills.seed = 6023


# ---------------------------------------------------------------------------
# A serra atrás das paredes (no leito)
# ---------------------------------------------------------------------------
## Altura da serra a `u2` m da borda da parede: a crista (com morros, picos nas montanhas) e a descida
## até o leito longe.
static func ridge_height(top: float, floor_y: float, u2: float, x: float, z: float, e: float) -> float:
	var bump := _hills.get_noise_2d(x, z) * lerpf(4.0, 16.0, e)
	if u2 <= RIDGE_CREST:
		return top + bump * smoothstep(0.0, 14.0, u2)
	var t := (u2 - RIDGE_CREST) / (RIDGE - RIDGE_CREST)
	return lerpf(top + bump, floor_y - 4.0, smoothstep(0.0, 1.0, t))


## Grade (vista de cima) com a altura da serra atrás de cada parede: o leito longe da pista usa o
## maior entre o relevo e ela.
static func _ridge_grid(track: RaceTrack, data: Dictionary) -> void:
	var p := track.path
	var n := p.size()
	var b := p.bounds().grow(RIDGE + 120.0)
	var nx := int(ceil(b.size.x / RIDGE_CELL)) + 1
	var nz := int(ceil(b.size.y / RIDGE_CELL)) + 1
	var grid := PackedFloat32Array()
	grid.resize(nx * nz)
	grid.fill(-1.0e9)
	var w: PackedFloat32Array = data.w
	var e: PackedFloat32Array = data.e
	var fl: PackedFloat32Array = data.floor
	for i in range(0, n, 2):
		if w[i] < 0.02:
			continue
		for k in 2:
			var side := 1 if k == 0 else -1
			var top: float = data.top[k][i]
			var run := maxf(top - fl[i], 1.0) * float(data.slope[i])
			var rim: float = float(data.foot[k][i]) + run + hidden(data, i)
			var u2 := 0.0
			while u2 <= RIDGE:
				var pos := p.points[i] + p.lefts[i] * side * (rim + u2)
				var h := lerpf(fl[i] - 20.0, ridge_height(top, fl[i], u2, pos.x, pos.z, e[i]), w[i])
				var cx := int(round((pos.x - b.position.x) / RIDGE_CELL))
				var cz := int(round((pos.z - b.position.y) / RIDGE_CELL))
				if cx >= 0 and cz >= 0 and cx < nx and cz < nz and h > grid[cz * nx + cx]:
					grid[cz * nx + cx] = h
				u2 += RIDGE_CELL * 0.5
	# Fecha os buracos entre os raios (por fora das curvas eles se abrem)
	for pass_k in 2:
		var out := grid.duplicate()
		for z in range(1, nz - 1):
			for x in range(1, nx - 1):
				var c := z * nx + x
				if grid[c] > -1.0e8:
					continue
				var best := -1.0e9
				var cnt := 0
				var acc := 0.0
				for o: int in [-1, 1, -nx, nx]:
					if grid[c + o] > -1.0e8:
						acc += grid[c + o]
						cnt += 1
				if cnt >= 2:
					best = acc / cnt
				out[c] = best
		grid = out
	data["ridge"] = grid
	data["ridge_origin"] = b.position
	data["ridge_n"] = Vector2i(nx, nz)


## Altura da serra em (x, z) (-1e9 onde não há serra).
static func ridge_at(data: Dictionary, x: float, z: float) -> float:
	var o: Vector2 = data.ridge_origin
	var nn: Vector2i = data.ridge_n
	var fx := (x - o.x) / RIDGE_CELL
	var fz := (z - o.y) / RIDGE_CELL
	var ix := floori(fx)
	var iz := floori(fz)
	if ix < 0 or iz < 0 or ix >= nn.x - 1 or iz >= nn.y - 1:
		return -1.0e9
	var g: PackedFloat32Array = data.ridge
	var c := iz * nn.x + ix
	var a := g[c]
	var b := g[c + 1]
	var d := g[c + nn.x]
	var f := g[c + nn.x + 1]
	var hi := maxf(maxf(a, b), maxf(d, f))
	if hi < -1.0e8:
		return -1.0e9
	# (célula na beira da serra: as que faltam descem, sem degrau)
	a = a if a > -1.0e8 else hi - 30.0
	b = b if b > -1.0e8 else hi - 30.0
	d = d if d > -1.0e8 else hi - 30.0
	f = f if f > -1.0e8 else hi - 30.0
	var tx := fx - ix
	return lerpf(lerpf(a, b, tx), lerpf(d, f, tx), fz - iz)


## Leito perto da pista (a `lat` m da linha central do lado `side`, na amostra i) com o cânion: o chão
## entre o tubo e a parede, a encosta escondida atrás da face (a face é a malha) e a crista.
static func carve(data: Dictionary, i: int, side: int, lat: float, base: float, ridge: float) -> float:
	var cw: float = data.w[i]
	if cw <= 0.001:
		return base
	var k := 0 if side > 0 else 1
	var fl: float = data.floor[i]
	var top: float = data.top[k][i]
	var u := lat - float(data.foot[k][i])
	var y := minf(base, fl)
	if u > 0.0:
		var run := maxf(top - fl, 1.0) * float(data.slope[i])
		var back := hidden(data, i)
		y = lerpf(fl, top, clampf((u - back) / run, 0.0, 1.0))
		if u > run + back:
			y = maxf(ridge, base)
	return lerpf(base, y, cw)


## O ponto está na rocha do cânion (atrás do pé de uma parede ou sob a serra): para quem espalha
## coisas no leito.
static func in_rock(track: RaceTrack, pos: Vector3, margin := 1.0) -> bool:
	var data := profile(track)
	var pr := track.path.project(pos, false, false)
	if pr.y == INF:
		return ridge_at(data, pos.x, pos.z) > pos.y - margin
	var i := track.path.index_at(pr.x)
	if float(data.w[i]) < 0.3:
		return ridge_at(data, pos.x, pos.z) > pos.y - margin
	var k := 0 if pr.y > 0.0 else 1
	return absf(pr.y) > float(data.foot[k][i]) - margin


## Trechos abertos (sem cânion) debaixo d'água: [s inicial, comprimento].
static func open_spans(track: RaceTrack) -> Array[Vector2]:
	var data := profile(track)
	if data.has("open"):
		return data.open
	var p := track.path
	var n := p.size()
	var water := track.layout.water_level
	var w: PackedFloat32Array = data.w
	var open := func(i: int) -> bool: return w[i] < 0.15 and p.points[i].y < water - 6.0
	# Começa num ponto fechado (os trechos não quebram na largada)
	var first := 0
	while first < n and open.call(first):
		first += 1
	var out: Array[Vector2] = []
	var start := -1
	for k in n + 1:
		var i := (first + k) % n
		var o: bool = open.call(i) and k < n
		if o and start < 0:
			start = i
		elif not o and start >= 0:
			out.append(Vector2(p.s_at(start), fposmod(p.s_at(i) - p.s_at(start), p.length)))
			start = -1
	data["open"] = out
	return out


## Um s ao acaso nos trechos abertos (proporcional ao comprimento).
static func random_open_s(track: RaceTrack, rng: RandomNumberGenerator) -> float:
	var spans := open_spans(track)
	var total := 0.0
	for sp in spans:
		total += sp.y
	if total <= 0.0:
		return rng.randf() * track.path.length
	var r := rng.randf() * total
	for sp in spans:
		if r <= sp.y:
			return fposmod(sp.x + r, track.path.length)
		r -= sp.y
	return spans[0].x


# ---------------------------------------------------------------------------
# A face da parede
# ---------------------------------------------------------------------------
## Fração da altura (0..1) de cada anel da face: intervalos iguais entre os patamares e um intervalo
## curtinho em cada patamar (o patamar fica plano: a face só avança ali).
static func _ring_t(s: float, side: int) -> PackedFloat32Array:
	var ledges := _ledge_t(s, side)
	var out := PackedFloat32Array()
	var a := 0.0
	for seg in SEGMENTS.size():
		var b: float = ledges[seg] - LEDGE_HALF if seg < 3 else 1.0
		var m: int = SEGMENTS[seg]
		for k in m:
			out.append(lerpf(a, b, float(k) / m))
		if seg < 3:
			# Embaixo do patamar; o trecho seguinte começa em cima dele
			out.append(b)
			a = ledges[seg] + LEDGE_HALF
	out.append(1.0)
	return out


## Altura (fração) dos três patamares, ondulando ao longo do cânion.
static func _ledge_t(s: float, side: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for j in 3:
		out.append(0.3 + 0.24 * j + 0.045 * _along.get_noise_1d(s * 0.7 + j * 333.0 + side * 91.0))
	return out


## Avanço da face (fração do avanço total) na fração de altura t: inclinada entre os patamares e
## avançando em cada um (`share`: a parte do avanço que fica nos patamares).
static func _shelf(t: float, ledges: PackedFloat32Array, share := LEDGES) -> float:
	var f := t * (1.0 - share)
	for tj in ledges:
		f += share / 3.0 * clampf((t - (tj - LEDGE_HALF)) / (2.0 * LEDGE_HALF), 0.0, 1.0)
	return f


## Quanto o leito fica escondido atrás da face na amostra i (mais nas montanhas, de rocha mais
## saliente).
static func hidden(data: Dictionary, i: int) -> float:
	return HIDDEN + 6.0 * float(data.e[i])


## Anéis (do pé à borda) da face do lado `side` na amostra i: a face com os patamares e a cornija e,
## por fim, a borda deitando sobre a crista.
static func column(track: RaceTrack, data: Dictionary, i: int, side: int) -> PackedVector3Array:
	var p := track.path
	var k := 0 if side > 0 else 1
	var s := p.s_at(i)
	var cw := float(data.w[i])
	var fl: float = data.floor[i]
	var top := lerpf(fl, float(data.top[k][i]), cw)
	var foot: float = data.foot[k][i]
	var height := maxf(top - fl, 0.5)
	var slope: float = data.slope[i]
	var run := height * slope
	var ts := _ring_t(s, side)
	var ledges := _ledge_t(s, side)
	var out := PackedVector3Array()
	var dir := p.lefts[i] * side
	# Montanhas (acima do mar): patamares bem menores e a rocha mais saliente
	var e: float = data.e[i]
	# (nas encostas mais deitadas os patamares são largos, em terraços; nos penhascos, estreitos)
	var share := LEDGES * (1.0 - 0.75 * e) * remap(slope, SLOPE_RANGE.x, SLOPE_RANGE.y, 0.55, 1.35)
	for t in ts:
		var y := fl - 2.5 + (height + 2.5) * t
		var lat := foot + run * _shelf(t, ledges, share) - CORNICE * smoothstep(0.86, 0.97, t) * cw
		var pos := p.points[i] + dir * lat
		pos.y = y
		# Rocha: saliências e reentrâncias, menos no pé e na borda
		var amp := (0.25 + 0.75 * sin(t * PI)) * (1.0 + 1.3 * e)
		pos += dir * ((_crag.get_noise_3dv(pos) * 2.2 + _crag.get_noise_3dv(pos * 3.1) * 0.7) * amp)
		out.append(pos)
	# Borda: deita sobre a crista e desce por trás dela até embaixo do leito (a serra)
	for lip: Vector2 in [Vector2(5.0, 0.6), Vector2(8.0 + hidden(data, i), -3.0), Vector2(20.0 + hidden(data, i), -14.0)]:
		var pos := p.points[i] + dir * (foot + run - CORNICE * cw + lip.x)
		pos.y = top + lip.y
		out.append(pos)
	return out


## Ponto da face do lado `side` na amostra i na altura y (interpolado entre os anéis).
static func face_at(track: RaceTrack, data: Dictionary, i: int, side: int, y: float) -> Vector3:
	var col := column(track, data, i, side)
	for r in range(1, top_ring() + 1):
		if col[r].y >= y:
			var a := col[r - 1]
			var b := col[r]
			return a.lerp(b, clampf((y - a.y) / maxf(b.y - a.y, 0.001), 0.0, 1.0))
	return col[top_ring()]


## Índices dos anéis de cada patamar (o intervalo plano: anel de baixo, anel de cima).
static func ledge_rings() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := 0
	for seg in 3:
		r += SEGMENTS[seg]
		out.append(Vector2i(r, r + 1))
		r += 1
	return out


## Anel do topo da face (antes da borda) e da ponta da cornija.
static func top_ring() -> int:
	var r := 3
	for m in SEGMENTS:
		r += m
	return r


static func material() -> ShaderMaterial:
	if _rock_mat == null:
		_rock_mat = ShaderMaterial.new()
		_rock_mat.shader = load("res://shaders/track/canyon_rock.gdshader")
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.02
		noise.fractal_octaves = 5
		noise.seed = 77
		var img := noise.get_seamless_image(256, 256)
		var bump := img.duplicate() as Image
		img.generate_mipmaps()
		_rock_mat.set_shader_parameter("noise_tex", ImageTexture.create_from_image(img))
		bump.bump_map_to_normal_map(6.0)
		bump.generate_mipmaps()
		_rock_mat.set_shader_parameter("normal_tex", ImageTexture.create_from_image(bump))
		var cells := FastNoiseLite.new()
		cells.noise_type = FastNoiseLite.TYPE_CELLULAR
		cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
		cells.frequency = 0.03
		cells.seed = 78
		var cimg := cells.get_seamless_image(256, 256)
		cimg.generate_mipmaps()
		_rock_mat.set_shader_parameter("crack_tex", ImageTexture.create_from_image(cimg))
		TrackMaterials.register_sea(_rock_mat)
		_rock_mat.set_shader_parameter("caustic_scale", 0.3)
	return _rock_mat


# ---------------------------------------------------------------------------
# Geração
# ---------------------------------------------------------------------------
static func build(track: RaceTrack, parent: Node3D) -> void:
	var data := profile(track)
	var p := track.path
	var n := p.size()
	var water := track.layout.water_level
	var root := Node3D.new()
	root.name = "Canyon"
	parent.add_child(root)
	_rng.seed = 9137
	_lights.clear()
	_caves = MeshBuilder.new()
	_cave_spots.clear()
	var w: PackedFloat32Array = data.w
	var points: Array = []
	var shrubs: Array = [[], []]
	var trees := {}
	var lamps := MeshBuilder.new()
	var beams := MeshBuilder.new()
	var light_spots: Array = []  # [posição, direção, cor]
	for k in 2:
		var side := 1 if k == 0 else -1
		var valid := PackedByteArray()
		valid.resize(n)
		for i in n:
			valid[i] = 1 if w[i] > 0.02 and _column_ok(track, data, i, side) else 0
		var i := 0
		while i < n - 1:
			if valid[i] == 0 or valid[i + 1] == 0:
				i += 1
				continue
			var j := i + 1
			while j + 1 < n and valid[j + 1] == 1 and j - i < CHUNK:
				j += 1
			# (a coluna da emenda é do pedaço seguinte, se a parede continua)
			var own_last := j + 1 >= n or valid[j + 1] == 0
			_chunk(track, data, root, side, i, j, own_last, points, shrubs, trees, light_spots)
			i = j
	_open_lights(track, data, light_spots)
	for spot: Array in light_spots:
		_light(root, lamps, beams, spot[0], spot[1], spot[2])
	if not lamps.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Crystals"
		mi.mesh = lamps.commit(null, SkyDeck.glow(0.0, 2.6, 4.4))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 700.0
		root.add_child(mi)
		var bi := MeshInstance3D.new()
		bi.name = "Beams"
		bi.mesh = beams.commit(null, beam_material())
		bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bi.visibility_range_end = 600.0
		root.add_child(bi)
	if not shrubs[0].is_empty():
		CityProps.add_chunked(root, "Shrubs", shrubs[0], shrubs[1],
			[[SeaReef._mesh(SeaReef.Kind.MOSS), SeaReef.material(), 0.0, 900.0, false]])
	if not trees.is_empty():
		CityProps.add_trees(root, "MountainTrees", trees)
	# (o que está acima do mar aparece na janela do céu vista de baixo d'água)
	for mmi: MultiMeshInstance3D in root.find_children("Shrubs*", "MultiMeshInstance3D", false, false) + \
			root.find_children("MountainTrees*", "MultiMeshInstance3D", false, false):
		mmi.layers |= SeaWorld.WINDOW_LAYER
	if not _caves.is_empty():
		var cmi := MeshInstance3D.new()
		cmi.name = "Caves"
		cmi.mesh = _caves.commit(null, _cave_material())
		cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cmi.visibility_range_end = 700.0
		root.add_child(cmi)
	root.set_meta("points", PackedVector3Array(points))
	root.set_meta("lights", _lights.size())
	root.set_meta("caves", _cave_spots.duplicate())
	# Ruínas e aquedutos perto da pista, nos cânions e nos trechos abertos
	CanyonRuins.build(track, parent)


## A parede da amostra i não invade o tubo (nem a laje e o aqueduto) de outro trecho da pista.
static func _column_ok(track: RaceTrack, data: Dictionary, i: int, side: int) -> bool:
	var col := column(track, data, i, side)
	for r: int in [0, 4, 9, 14, col.size() - 3, col.size() - 1]:
		if SeaTube.blocked(track, col[r], 1.5):
			return false
	return true


## Um pedaço da face (amostras i..j) com as normais suaves, mais o que cresce nela e os pontos das luzes.
static func _chunk(track: RaceTrack, data: Dictionary, root: Node3D, side: int, i0: int, i1: int, own_last: bool,
		points: Array, shrubs: Array, trees: Dictionary, light_spots: Array) -> void:
	var p := track.path
	var water := track.layout.water_level
	var cols := i1 - i0 + 1
	var grid: Array[PackedVector3Array] = []
	for c in cols:
		grid.append(column(track, data, i0 + c, side))
	var rings := grid[0].size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var top_y := -INF
	for c in cols:
		for r in rings:
			var v: Vector3 = grid[c][r]
			verts.append(v)
			top_y = maxf(top_y, v.y)
			var along: Vector3 = grid[mini(c + 1, cols - 1)][r] - grid[maxi(c - 1, 0)][r]
			var up: Vector3 = grid[c][mini(r + 1, rings - 1)] - grid[c][maxi(r - 1, 0)]
			var nrm := up.cross(along).normalized()
			# (para dentro do cânion, do lado da pista)
			if nrm.dot(-p.lefts[i0 + c] * side) < 0.0:
				nrm = -nrm
			normals.append(nrm)
	var indices := PackedInt32Array()
	# Ordem dos vértices pela normal (frente horária, como no MeshBuilder)
	var flip := (verts[rings] - verts[0]).cross(verts[1] - verts[0]).dot(normals[0]) > 0.0
	for c in cols - 1:
		for r in rings - 1:
			var a := c * rings + r
			if flip:
				indices.append_array([a, a + 1, a + rings, a + 1, a + rings + 1, a + rings])
			else:
				indices.append_array([a, a + rings, a + 1, a + 1, a + rings, a + rings + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	var mi := MeshInstance3D.new()
	mi.name = "Wall_%d_%d" % [side + 1, i0]
	mi.mesh = mesh
	mi.visibility_range_end = VISIBILITY
	mi.visibility_range_end_margin = 80.0
	# Sombra só nas montanhas (acima do mar a luz é forte); as que passam da superfície aparecem na
	# janela do céu vista de baixo (SeaWorld)
	var mountain := top_y > water + 4.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if mountain else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mountain:
		mi.layers |= SeaWorld.WINDOW_LAYER
	root.add_child(mi)
	for c in range(0, cols, 6):
		points.append(grid[c][rings / 2])
	# O que cresce na parede, as pedras e as luzes
	for c in cols:
		var i := i0 + c
		if c == cols - 1 and not own_last:
			continue
		_growth(track, data, i, side, grid[c], normals.slice(c * rings, (c + 1) * rings), shrubs, trees)
		var s := p.s_at(i)
		var period := LIGHT_SPACING * 2.0
		var phase := fposmod(s + (0.0 if side > 0 else LIGHT_SPACING), period)
		if phase < p.spacing and float(data.w[i]) > 0.6:
			var ledge := ledge_rings()[_rng.randi() % 3]
			var at: Vector3 = (grid[c][ledge.x] + grid[c][ledge.y]) * 0.5
			if at.y < water - 3.0:
				var out_dir := (-p.lefts[i] * side * 0.45 + Vector3.UP).normalized()
				light_spots.append([at, out_dir, LIGHT_COLORS[light_spots.size() % LIGHT_COLORS.size()]])


## O que cresce na coluna (anéis `ring`, normais `nrm`): corais e anêmonas nos patamares, leques,
## esponjas e anêmonas na face, kelp, capim e pedras no pé, algas penduradas na cornija, musgo na
## borda; acima do mar, arbustos nos patamares e na crista.
static func _growth(track: RaceTrack, data: Dictionary, i: int, side: int, ring: PackedVector3Array, nrm: PackedVector3Array,
		shrubs: Array, trees: Dictionary) -> void:
	var p := track.path
	var water := track.layout.water_level
	var rng := _rng
	var inward := -p.lefts[i] * side
	var tangent := p.tangents[i].normalized()
	# Patamares: um jardim de corais elaborado a cada GARDEN_SPACING m e, no resto, peças avulsas
	var s_here := p.s_at(i)
	var garden_at := fposmod(s_here + (0.0 if side > 0 else GARDEN_SPACING * 0.5), GARDEN_SPACING) < p.spacing
	var garden_ledge := rng.randi() % 3
	for li in ledge_rings().size():
		var lr: Vector2i = ledge_rings()[li]
		var a: Vector3 = ring[lr.x]
		var b: Vector3 = ring[lr.y]
		if garden_at and li == garden_ledge:
			var g := a.lerp(b, 0.5) + Vector3.UP * 0.05
			if g.y < water - 3.0:
				SeaReef.garden(g, minf(a.distance_to(b) * 0.6 + 1.0, 2.6), rng)
				continue
		if rng.randf() < 0.8:
			var at := a.lerp(b, rng.randf_range(0.2, 0.8)) + Vector3.UP * 0.05
			if at.y > water - 1.5:
				if rng.randf() < 0.45:
					_shrub(shrubs, at, rng.randf_range(1.4, 3.2), rng)
				continue
			var kind: int = [SeaReef.Kind.BRAIN, SeaReef.Kind.TABLE, SeaReef.Kind.BRANCH, SeaReef.Kind.PILLAR,
				SeaReef.Kind.ANEMONE, SeaReef.Kind.TUBES, SeaReef.Kind.GRASS, SeaReef.Kind.FAN, SeaReef.Kind.MOSS,
				SeaReef.Kind.ROCK, SeaReef.Kind.SOFT, SeaReef.Kind.BARREL, SeaReef.Kind.WHIP, SeaReef.Kind.URCHIN,
				SeaReef.Kind.STAR][rng.randi() % 15]
			var sc := rng.randf_range(0.9, 2.4) * (1.5 if kind == SeaReef.Kind.TABLE or kind == SeaReef.Kind.BRAIN else 1.0)
			if kind == SeaReef.Kind.ROCK:
				sc = rng.randf_range(0.6, 1.6)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc)
			if kind == SeaReef.Kind.ROCK:
				basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * 0.7, sc))
			SeaReef.place(kind, Transform3D(basis, at - Vector3.UP * (0.15 * sc if kind == SeaReef.Kind.ROCK else 0.0)), rng)
	# Face (entre os patamares): prateleiras de coral de placa, leques (alguns grandes) quase colados
	# na rocha, chicotes, esponjas e anêmonas saindo dela
	for _f in (2 if rng.randf() < 0.35 else 1 if rng.randf() < 0.75 else 0):
		var r := rng.randi_range(2, ring.size() - 6)
		var at: Vector3 = ring[r]
		var n: Vector3 = nrm[r]
		if at.y < water - 2.0 and rng.randf() < 0.3:
			# (as placas saem da parede para o lado da pista, na horizontal)
			var nh := Vector3(n.x, 0.0, n.z).normalized()
			var px := Vector3.UP.cross(nh).normalized()
			SeaReef.place(SeaReef.Kind.PLATE, Transform3D(Basis(px, Vector3.UP, nh).scaled(Vector3.ONE * rng.randf_range(1.3, 2.8)), at - nh * 0.1), rng)
			continue
		if at.y < water - 2.0:
			var kind: int = [SeaReef.Kind.FAN, SeaReef.Kind.FAN, SeaReef.Kind.TUBES, SeaReef.Kind.ANEMONE, SeaReef.Kind.BRANCH,
				SeaReef.Kind.WHIP, SeaReef.Kind.FAN][rng.randi() % 7]
			var sc := rng.randf_range(0.9, 2.2) * (rng.randf_range(1.3, 1.7) if kind == SeaReef.Kind.FAN and rng.randf() < 0.3 else 1.0)
			var up := (n * (0.35 if kind == SeaReef.Kind.FAN else 0.85) + Vector3.UP * (0.8 if kind == SeaReef.Kind.FAN else 0.3)).normalized()
			var x := tangent if absf(tangent.dot(up)) < 0.9 else n
			var z := x.cross(up).normalized()
			x = up.cross(z).normalized()
			SeaReef.place(kind, Transform3D(Basis(x, up, z).scaled(Vector3.ONE * sc), at + n * 0.25), rng)
	# Pé: kelp alto, capim e pedras grandes
	var foot: Vector3 = ring[1] + inward * rng.randf_range(0.5, 3.0)
	foot.y = float(data.floor[i])
	if foot.y < water - 4.0:
		var roll := rng.randf()
		if roll < 0.22:
			var h := minf(rng.randf_range(8.0, 18.0), water - 1.5 - foot.y)
			if h > 3.0:
				SeaReef.place(SeaReef.Kind.KELP, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.4, h, 1.4)), foot), rng)
		elif roll < 0.5:
			SeaReef.place(SeaReef.Kind.GRASS, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.6)), foot), rng)
		elif roll < 0.62:
			var size := rng.randf_range(1.5, 4.0)
			SeaReef.place(SeaReef.Kind.ROCK, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * 0.7, size)),
				foot - Vector3.UP * 0.4 + inward * 0.5), rng)
		elif roll < 0.72:
			SeaReef.place([SeaReef.Kind.BRAIN, SeaReef.Kind.BRANCH, SeaReef.Kind.ANEMONE][rng.randi() % 3],
				Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.2, 2.6)), foot), rng)
	# Cornija: algas penduradas da ponta (a face embaixo dela recua) e corais moles de cabeça para baixo
	var tip_r := top_ring() - 1
	if rng.randf() < 0.4 and ring[tip_r].y < water - 2.5:
		SeaReef.hang(ring[tip_r] + inward * 0.3, rng.randf_range(1.5, 4.0), rng)
	if rng.randf() < 0.12 and ring[tip_r].y < water - 3.0:
		var hx := tangent
		var down := Basis(hx, Vector3.DOWN, hx.cross(Vector3.DOWN)).scaled(Vector3.ONE * rng.randf_range(0.9, 1.6))
		SeaReef.place(SeaReef.Kind.SOFT, Transform3D(down, ring[tip_r] + inward * 0.2 + Vector3.DOWN * 0.1), rng)
	# Caverna na face, entre o primeiro e o segundo patamar (uma a cada CAVE_SPACING m de cada lado)
	if fposmod(s_here + (CAVE_SPACING * 0.37 if side > 0 else 0.0), CAVE_SPACING) < p.spacing and float(data.w[i]) > 0.9:
		var lr := ledge_rings()
		var r := (lr[0].y + lr[1].x) / 2
		if ring[r].y < water - 6.0 and ring[r].y > float(data.floor[i]) + 4.0:
			_cave(ring, nrm, r, tangent, rng)
	# Borda: musgo (debaixo d'água) ou arbustos e árvores (acima do mar, na crista e na serra atrás)
	var lip: Vector3 = ring[top_ring() + 1]
	if lip.y < water - 1.5:
		if rng.randf() < 0.35:
			SeaReef.moss(lip, rng.randf_range(1.0, 2.2), rng)
	elif lip.y > water + 4.0:
		if rng.randf() < 0.35:
			_shrub(shrubs, lip, rng.randf_range(1.8, 4.0), rng)
		if rng.randf() < 0.22:
			_tree(trees, lip + Vector3.DOWN * 0.3, rng)
		if rng.randf() < 0.3:
			var back := lip - inward * rng.randf_range(4.0, 34.0) + tangent * rng.randf_range(-1.0, 1.0)
			back.y = SeaFloor.ground(track, back.x, back.z) - 0.3
			if back.y > water + 3.0:
				_tree(trees, back, rng)


## Boca de caverna na face (anel r da coluna, normal nrm[r]): o disco escuro rente à rocha
## (cave_mouth.gdshader: bioluminescência e, às vezes, os olhos de uma moreia), pedras em volta da
## boca, algas penduradas em cima e corais no pé.
static func _cave(ring: PackedVector3Array, nrm: PackedVector3Array, r: int, tangent: Vector3, rng: RandomNumberGenerator) -> void:
	var at: Vector3 = ring[r]
	var n: Vector3 = nrm[r]
	var nh := Vector3(n.x, 0.0, n.z).normalized()
	var ux := Vector3.UP.cross(nh).normalized()
	var uy := nh.cross(ux).normalized()
	var w := rng.randf_range(2.8, 4.4)
	var h := rng.randf_range(2.1, 3.3)
	var c := at + nh * 0.45 + Vector3.UP * 0.3
	var eel := Color(1.0 if rng.randf() < 0.45 else 0.0, rng.randf(), 0.0, 1.0)
	var steps := 18
	for k in steps:
		var a0 := TAU * k / steps
		var a1 := TAU * (k + 1) / steps
		var q0 := c + ux * cos(a0) * w + uy * sin(a0) * h
		var q1 := c + ux * cos(a1) * w + uy * sin(a1) * h
		_caves.tri(c, q0, q1, eel, nh, Vector2.ZERO, Vector2(cos(a0), -sin(a0)), Vector2(cos(a1), -sin(a1)))
	# Pedras em volta da boca (a borda some entre elas)
	for k in rng.randi_range(7, 10):
		var a := TAU * k / 9.0 + rng.randf_range(-0.2, 0.2)
		var sz := rng.randf_range(0.8, 1.6)
		var q := c + ux * cos(a) * w * 1.08 + uy * sin(a) * h * 1.08 - nh * 0.25
		SeaReef.place(SeaReef.Kind.ROCK, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sz, sz * 0.8, sz)), q - Vector3.UP * sz * 0.4), rng)
	for k in rng.randi_range(2, 4):
		SeaReef.hang(c + ux * rng.randf_range(-w, w) * 0.7 + uy * h * 1.05 + nh * 0.2, rng.randf_range(0.8, 2.2), rng)
	SeaReef.cluster(c - uy * h * 1.15 + nh * 0.6, 1.2, rng, 3)
	_cave_spots.append(c)


static func _cave_material() -> ShaderMaterial:
	if _cave_mat == null:
		_cave_mat = ShaderMaterial.new()
		_cave_mat.shader = load("res://shaders/track/cave_mouth.gdshader")
	return _cave_mat


static func _tree(trees: Dictionary, at: Vector3, rng: RandomNumberGenerator) -> void:
	var r := rng.randf()
	var species: int = TREES[0][0]
	for tw: Array in TREES:
		r -= float(tw[1])
		if r <= 0.0:
			species = tw[0]
			break
	if not trees.has(species):
		trees[species] = [[], []]
	var sc := rng.randf_range(0.8, 1.5)
	trees[species][0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), at))
	trees[species][1].append(Color(rng.randf(), rng.randf(), rng.randf(), 0.0))


static func _shrub(shrubs: Array, at: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var c: Color = SHRUBS[rng.randi() % SHRUBS.size()]
	var v := rng.randf_range(0.85, 1.15)
	shrubs[0].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * rng.randf_range(0.6, 1.0), size)), at))
	shrubs[1].append(Color(c.r * v, c.g * v, c.b * v, 0.05))


## Luzes nos trechos abertos: no leito, ao lado do tubo, lados alternados.
static func _open_lights(track: RaceTrack, data: Dictionary, light_spots: Array) -> void:
	var p := track.path
	var water := track.layout.water_level
	var side := 1
	for sp in open_spans(track):
		var s := sp.x + OPEN_SPACING * 0.5
		while s < sp.x + sp.y:
			var i := p.index_at(s)
			var at := p.frame_at(s, side * (SeaTube.clearance(track, i, side) + _rng.randf_range(5.0, 16.0)), 0.0).origin
			at.y = SeaFloor.ground(track, at.x, at.z) + 0.3
			if at.y < water - 6.0 and not SeaTube.blocked(track, at + Vector3.UP * 2.0, 1.0):
				light_spots.append([at, Vector3.UP, LIGHT_COLORS[light_spots.size() % LIGHT_COLORS.size()]])
			s += OPEN_SPACING
			side = -side


## Uma luz colorida: cristais acesos, o facho saindo deles e a luz de verdade.
static func _light(root: Node3D, lamps: MeshBuilder, beams: MeshBuilder, at: Vector3, dir: Vector3, color: Color) -> void:
	var rng := _rng
	var x := dir.cross(Vector3.FORWARD if absf(dir.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(dir).normalized()
	# Cristais: prismas pontudos abrindo em leque
	for c in rng.randi_range(6, 10):
		var d := (dir + x * rng.randf_range(-0.7, 0.7) + z * rng.randf_range(-0.7, 0.7)).normalized()
		var length := rng.randf_range(1.0, 3.2)
		var radius := length * rng.randf_range(0.14, 0.22)
		var base := at + x * rng.randf_range(-0.6, 0.6) + z * rng.randf_range(-0.6, 0.6)
		_crystal(lamps, base, d, length, radius, color)
	# Facho: cone aberto e aditivo (cor nos vértices, UV.y = 0 na fonte .. 1 na ponta)
	var length := rng.randf_range(12.0, 20.0)
	var sides := 10
	var bx := dir.cross(Vector3.FORWARD if absf(dir.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var bz := bx.cross(dir).normalized()
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var r0 := 0.5
		var r1 := length * 0.24
		var p0 := at + (bx * cos(a0) + bz * sin(a0)) * r0
		var p1 := at + (bx * cos(a1) + bz * sin(a1)) * r0
		var q0 := at + dir * length + (bx * cos(a0) + bz * sin(a0)) * r1
		var q1 := at + dir * length + (bx * cos(a1) + bz * sin(a1)) * r1
		beams.quad(p0, p1, q1, q0, color, (bx * cos((a0 + a1) * 0.5) + bz * sin((a0 + a1) * 0.5)),
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	if RaceTrack.server_mode:
		return
	var light := OmniLight3D.new()
	light.name = "SeaLight%d" % _lights.size()
	light.light_color = color
	light.light_energy = LIGHT_ENERGY[0]
	light.omni_range = 26.0
	light.omni_attenuation = 1.1
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 260.0
	light.distance_fade_length = 60.0
	root.add_child(light)
	light.global_position = at + dir * 2.0
	_lights.append(light)


## Cristal: prisma de seis faces com ponta, de `base` na direção `d`.
static func _crystal(mb: MeshBuilder, base: Vector3, d: Vector3, length: float, radius: float, color: Color) -> void:
	var x := d.cross(Vector3.FORWARD if absf(d.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(d).normalized()
	var tip := base + d * length
	var shoulder := base + d * length * 0.72
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		var o0 := (x * cos(a0) + z * sin(a0)) * radius
		var o1 := (x * cos(a1) + z * sin(a1)) * radius
		var out := (x * cos((a0 + a1) * 0.5) + z * sin((a0 + a1) * 0.5))
		mb.quad(base + o0, base + o1, shoulder + o1, shoulder + o0, color * 0.85, out)
		mb.tri(shoulder + o0, shoulder + o1, tip, color, (out + d * 0.6).normalized())


static func beam_material() -> ShaderMaterial:
	if _beam_mat == null:
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = load("res://shaders/track/sea_beam.gdshader")
	return _beam_mat


## Período do dia: luzes mais fortes no entardecer e à noite.
static func apply_mood(time_of_day: int) -> void:
	var t := clampi(time_of_day, 0, 2)
	for light in _lights:
		if is_instance_valid(light):
			light.light_energy = LIGHT_ENERGY[t]
	if _beam_mat:
		_beam_mat.set_shader_parameter("intensity", [0.85, 1.2, 1.7][t])
