class_name TrackTerrain
extends RefCounted
## Terreno com relevo ao redor do circuito (inspirado nas pistas de Mario Kart):
##  * a faixa da pista, arquibancadas e boxes fica plana (altura 0);
##  * fora dela: colinas arredondadas, terraços com penhascos e uma borda que sobe formando uma
##    "tigela" verde; ao longe, um anel de montanhas (com neve) esconde o horizonte.
##
## A altura vem de uma função analítica (ruídos + distância até a área ocupada). Ela é amostrada
## numa grade (CELL m) que vira textura (o shader desloca os vértices dos blocos de terreno),
## HeightMapShape3D (colisão) e consulta rápida para árvores e objetos (height_at).
##
## Pista com subidas (Suzuka): tudo isso soma sobre um relevo de base. Perto da pista ele é a altura
## dela (plana na lateral, um pouco abaixo do asfalto); longe, a superfície suave do layout
## (TrackLayout.relief). No cruzamento em viaduto o trecho de baixo passa num corte: em volta vale o
## nível de cima, menos no corredor da pista de baixo (os muros do corte são do TrackBridge).

const CELL := 8.0
const COARSE := 16.0
const CHUNK_CELLS := 32
## Margem da grade além do retângulo da pista (m).
const MARGIN := 760.0
## Distância (m) além da área ocupada em que o terreno começa a subir.
const FLAT_BLEND := 70.0

var origin := Vector2.ZERO
var size := Vector2i.ZERO
var heights := PackedFloat32Array()
var center := Vector2.ZERO
## Raio (m) do círculo que envolve a pista a partir do centro.
var track_radius := 0.0
var texture: ImageTexture
var min_height := 0.0
var max_height := 0.0
## Relevo de base por amostra da grade (0 sem relevo).
var bases := PackedFloat32Array()
var has_relief := false

var _track: RaceTrack
var _relief := PackedFloat32Array()
var _relief_origin := Vector2.ZERO
var _relief_cell := 16.0
var _relief_size := Vector2i.ZERO
## Raio (m) em volta de um cruzamento em que vale o nível de cima (com transição até CROSS_OUTER).
const CROSS_INNER := 45.0
const CROSS_OUTER := 90.0
## Quanto o terreno fica abaixo do asfalto (m), para nunca aparecer por cima dele.
const UNDER_ROAD := 0.06

var _clear_origin := Vector2.ZERO
var _clear_size := Vector2i.ZERO
var _clear := PackedFloat32Array()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _bowl := FastNoiseLite.new()
var _mesas := FastNoiseLite.new()


func _init(seed_value := 7) -> void:
	_hills.seed = seed_value
	_hills.frequency = 1.0 / 420.0
	_hills.fractal_octaves = 3
	_detail.seed = seed_value + 1
	_detail.frequency = 1.0 / 60.0
	_detail.fractal_octaves = 2
	_ridges.seed = seed_value + 2
	_ridges.frequency = 1.0 / 1400.0
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 4
	_bowl.seed = seed_value + 3
	_bowl.frequency = 1.0 / 900.0
	_mesas.seed = seed_value + 4
	_mesas.frequency = 1.0 / 330.0
	_mesas.fractal_octaves = 2


## Monta o campo de distância e a grade de alturas.
func setup(track: RaceTrack) -> void:
	var p := track.path
	_track = track
	has_relief = false
	for pt in p.points:
		if absf(pt.y) > 0.05:
			has_relief = true
			break
	if has_relief:
		_load_relief(track.layout.relief)
	var r := p.bounds()
	center = r.get_center()
	track_radius = 0.0
	for pt in p.points:
		track_radius = maxf(track_radius, Vector2(pt.x, pt.z).distance_to(center))
	var area := r.grow(MARGIN)
	origin = (area.position / CELL).floor() * CELL
	size = Vector2i(ceili(area.size.x / CELL) + 1, ceili(area.size.y / CELL) + 1)
	_build_clearance(track, area)
	heights.resize(size.x * size.y)
	bases.resize(size.x * size.y)
	bases.fill(0.0)
	if has_relief:
		_nearest_field()
	min_height = INF
	max_height = -INF
	for z in size.y:
		for x in size.x:
			var wx := origin.x + x * CELL
			var wz := origin.y + z * CELL
			var f := clearance(wx, wz)
			var h := raw_height(wx, wz, f)
			if has_relief:
				var b := base_height(wx, wz, f, true, _node_projection(z * size.x + x, wx, wz))
				bases[z * size.x + x] = b
				h += b
			heights[z * size.x + x] = h
			min_height = minf(min_height, h)
			max_height = maxf(max_height, h)
	# Textura: R = altura, G = relevo de base (o shader acha a parte plana pela diferença)
	var rg := PackedFloat32Array()
	rg.resize(heights.size() * 2)
	for k in heights.size():
		rg[k * 2] = heights[k]
		rg[k * 2 + 1] = bases[k]
	var img := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGF, rg.to_byte_array())
	texture = ImageTexture.create_from_image(img)


## Altura analítica. f = distância (m) até a borda da área ocupada (negativo = dentro dela).
func raw_height(x: float, z: float, f: float) -> float:
	var ramp := smoothstep(0.0, FLAT_BLEND, f)
	if ramp <= 0.0:
		return 0.0
	var hn := _hills.get_noise_2d(x, z) * 0.5 + 0.5
	var hills := hn * hn * 46.0
	var bumps := _detail.get_noise_2d(x, z) * 2.2
	# A borda da "tigela" sobe com a distância da pista (mais alta em alguns lados)
	var rim := smoothstep(90.0, 560.0, f) * (40.0 + 50.0 * (_bowl.get_noise_2d(x, z) * 0.5 + 0.5))
	# Mesas: morros de topo plano com paredões (estilo Mario Kart)
	var mesa := smoothstep(0.28, 0.36, _mesas.get_noise_2d(x, z)) * 32.0 * smoothstep(70.0, 160.0, f)
	var h := hills + rim + mesa
	# Terraços com penhascos nas colinas
	var step := 8.0
	var t := h / step
	var terrace := (floorf(t) + smoothstep(0.3, 0.7, t - floorf(t))) * step
	h = lerpf(h, terrace, 0.8 * smoothstep(40.0, 180.0, f)) + bumps
	# Montanhas: começam fora do parque e passam de 500 m
	var r := Vector2(x, z).distance_to(center)
	var m := smoothstep(track_radius + 650.0, track_radius + 2900.0, r)
	if m > 0.0:
		var ridge := _ridges.get_noise_2d(x, z) * 0.5 + 0.5
		h += m * (180.0 + 520.0 * ridge * ridge)
	return maxf(h * ramp, 0.0)


## Relevo de base: perto da pista, a altura dela; além, mistura com o relevo do layout.
## cut = false ignora o corte do cruzamento (a altura que o chão teria ali: topo dos muros).
## pr: projeção na pista já conhecida (Vector2(s, lateral); s < 0 = calcular).
func base_height(x: float, z: float, f: float, cut := true, pr := Vector2(-1.0, 0.0)) -> float:
	var far := relief_at(x, z)
	if f >= FLAT_BLEND:
		return far
	return lerpf(ground_near(x, z, cut, pr), far, smoothstep(0.0, FLAT_BLEND, f))


## Altura do chão junto da pista: a do ponto mais próximo (a pista não tem inclinação lateral),
## um pouco abaixo do asfalto. Nos cruzamentos vale o nível de cima, menos no corredor de baixo.
func ground_near(x: float, z: float, cut := true, pr := Vector2(-1.0, 0.0)) -> float:
	var p := _track.path
	var pos := Vector3(x, 0.0, z)
	if pr.x < 0.0:
		pr = p.project(pos, true, false)
	var h := _flat_height(pr)
	for k in p.crossings.size():
		var cp := _cross_points[k]
		var c := p.crossings[k]
		var r := Vector2(x - cp.x, z - cp.z).length()
		if r > CROSS_OUTER:
			continue
		var lo := p.project_near(pos, c.x, CROSS_OUTER + 40.0)
		if cut and absf(lo.y) < cut_reach(p.index_at(lo.x), 1 if lo.y > 0.0 else -1):
			return _flat_height(lo)
		var up := _flat_height(p.project_near(pos, c.y, CROSS_OUTER + 40.0))
		h = lerpf(h, up, 1.0 - smoothstep(CROSS_INNER, CROSS_OUTER, r))
	return h


## Até onde (lateral, m) o chão fica no nível do trecho de baixo de um cruzamento: além da face
## do muro do corte (cut_wall) por mais de uma célula na diagonal, para a rampa da grade entre os
## dois níveis ficar inteira atrás do muro.
func cut_reach(i: int, side: int) -> float:
	return cut_wall(_track, i, side) + CELL * 1.45


## Face do muro do corte do cruzamento (lateral a partir do eixo, m): logo atrás da barreira.
static func cut_wall(track: RaceTrack, i: int, side: int) -> float:
	return track.path.half_width(i, side) + track.barrier[RaceTrack._si(side)][i] + 0.6


## Ponto mais próximo da pista para cada amostra da grade, de uma vez: cada amostra da pista (a cada
## NEAR_STEP) "pinta" os nós ao longo da sua normal até NEAR_REACH m, guardando o mais perto.
## Bem mais rápido que projetar nó a nó (a projeção completa fica para os que sobrarem).
const NEAR_STEP := 4
const NEAR_REACH := 170.0
var _near_i := PackedInt32Array()
var _near_d := PackedFloat32Array()
var _cross_points: Array[Vector3] = []


func _nearest_field() -> void:
	var p := _track.path
	_cross_points.clear()
	for c in p.crossings:
		_cross_points.append(p.position_at(c.x))
	var count := size.x * size.y
	_near_i.resize(count)
	_near_i.fill(-1)
	_near_d.resize(count)
	_near_d.fill(INF)
	var steps := int(NEAR_REACH / (CELL * 0.5))
	for i in range(0, p.size(), NEAR_STEP):
		var pt := p.points[i]
		var left := p.lefts[i]
		for k in range(-steps, steps + 1):
			var q := pt + left * (k * CELL * 0.5)
			var gx := floori((q.x - origin.x) / CELL)
			var gz := floori((q.z - origin.y) / CELL)
			for dz in 2:
				for dx in 2:
					var nx := gx + dx
					var nz := gz + dz
					if nx < 0 or nz < 0 or nx >= size.x or nz >= size.y:
						continue
					var idx := nz * size.x + nx
					var ex := origin.x + nx * CELL - pt.x
					var ez := origin.y + nz * CELL - pt.z
					var d := ex * ex + ez * ez
					if d < _near_d[idx]:
						_near_d[idx] = d
						_near_i[idx] = i


## Projeção do nó idx da grade pela amostra mais próxima já achada (como TrackPath.project).
func _node_projection(idx: int, x: float, z: float) -> Vector2:
	var i := _near_i[idx]
	if i < 0:
		return Vector2(-1.0, 0.0)
	var p := _track.path
	# Refina entre as amostras vizinhas (a busca usou uma a cada NEAR_STEP)
	var best := i
	var best_d := INF
	for d in range(-NEAR_STEP, NEAR_STEP + 1):
		var j := p.wrap_index(i + d)
		var ex := p.points[j].x - x
		var ez := p.points[j].z - z
		var dd := ex * ex + ez * ez
		if dd < best_d:
			best_d = dd
			best = j
	var rel := Vector3(x, p.points[best].y, z) - p.points[best]
	return Vector2(fposmod(best * p.spacing + rel.dot(p.tangents[best]), p.length), rel.dot(p.lefts[best]))


func _flat_height(pr: Vector2) -> float:
	var p := _track.path
	var i := p.index_at(pr.x)
	var hw := p.half_width(i, 1 if pr.y > 0.0 else -1)
	return p.height_at(pr.x) - UNDER_ROAD * (1.0 - smoothstep(hw, hw + 2.0, absf(pr.y)))


## Relevo do layout (bilinear; fora da grade, a borda). 0 sem relevo.
func relief_at(x: float, z: float) -> float:
	if _relief.is_empty():
		return 0.0
	var fx := clampf((x - _relief_origin.x) / _relief_cell, 0.0, _relief_size.x - 1.001)
	var fz := clampf((z - _relief_origin.y) / _relief_cell, 0.0, _relief_size.y - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var k := iz * _relief_size.x + ix
	var a := lerpf(_relief[k], _relief[k + 1], fx - ix)
	var b := lerpf(_relief[k + _relief_size.x], _relief[k + _relief_size.x + 1], fx - ix)
	return lerpf(a, b, fz - iz)


func _load_relief(file_path: String) -> void:
	_relief = PackedFloat32Array()
	if file_path.is_empty():
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if not data is Dictionary:
		push_error("TrackTerrain: relevo inválido em %s" % file_path)
		return
	_relief_origin = Vector2(data["origin"][0], data["origin"][1])
	_relief_cell = float(data["cell"])
	_relief_size = Vector2i(int(data["size"][0]), int(data["size"][1]))
	_relief = Marshalls.base64_to_raw(str(data["h"])).to_float32_array()


## Altura acima do relevo de base (morros, terraços): 0 na área plana em volta da pista.
func rise_at(x: float, z: float) -> float:
	return height_at(x, z) - _bilinear(bases, x, z)


## Altura que o terreno teria sem o corte do cruzamento (topo dos muros do corte).
func uncut_height_at(x: float, z: float) -> float:
	var f := clearance(x, z)
	return raw_height(x, z, f) + (base_height(x, z, f, false) if has_relief else 0.0)


func _bilinear(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x - origin.x) / CELL, 0.0, size.x - 1.001)
	var fz := clampf((z - origin.y) / CELL, 0.0, size.y - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var k := iz * size.x + ix
	var a := lerpf(arr[k], arr[k + 1], fx - ix)
	var b := lerpf(arr[k + size.x], arr[k + size.x + 1], fx - ix)
	return lerpf(a, b, fz - iz)


## Distância até a área ocupada (bilinear no campo grosso; longe da grade = muito grande).
func clearance(x: float, z: float) -> float:
	var fx := (x - _clear_origin.x) / COARSE
	var fz := (z - _clear_origin.y) / COARSE
	if fx < 0.0 or fz < 0.0 or fx >= _clear_size.x - 1 or fz >= _clear_size.y - 1:
		return 1e5
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var k := iz * _clear_size.x + ix
	var a := lerpf(_clear[k], _clear[k + 1], tx)
	var b := lerpf(_clear[k + _clear_size.x], _clear[k + _clear_size.x + 1], tx)
	return lerpf(a, b, tz)


## Altura do terreno (bilinear na grade; fora dela usa a função analítica).
func height_at(x: float, z: float) -> float:
	var fx := (x - origin.x) / CELL
	var fz := (z - origin.y) / CELL
	if fx < 0.0 or fz < 0.0 or fx >= size.x - 1 or fz >= size.y - 1:
		return raw_height(x, z, 1e5) + relief_at(x, z)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var k := iz * size.x + ix
	var a := lerpf(heights[k], heights[k + 1], tx)
	var b := lerpf(heights[k + size.x], heights[k + size.x + 1], tx)
	return lerpf(a, b, tz)


## Mesmas contas de tc_dark_zone() (terrain_common.gdshaderinc): 0 = verde normal, 1 = escuro.
static func dark_zone(x: float, z: float) -> float:
	var p := Vector2(x, z) / 240.0 + Vector2(31.0, 7.0)
	var v := _tc_noise(p) * 0.55 + _tc_noise(p * 2.13 + Vector2(7.1, 7.1)) * 0.3 + _tc_noise(p * 4.37 + Vector2(3.7, 3.7)) * 0.15
	return smoothstep(0.5, 0.6, v)


static func _tc_hash(p: Vector2) -> float:
	var p3 := Vector3(p.x, p.y, p.x) * 0.1031
	p3 = Vector3(p3.x - floorf(p3.x), p3.y - floorf(p3.y), p3.z - floorf(p3.z))
	var d := p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3(33.33, 33.33, 33.33))
	p3 += Vector3(d, d, d)
	var r := (p3.x + p3.y) * p3.z
	return r - floorf(r)


static func _tc_noise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	var a := lerpf(_tc_hash(i), _tc_hash(i + Vector2(1, 0)), f.x)
	var b := lerpf(_tc_hash(i + Vector2(0, 1)), _tc_hash(i + Vector2(1, 1)), f.x)
	return lerpf(a, b, f.y)


## Inclinação (0 = plano, 1 = vertical).
func slope_at(x: float, z: float) -> float:
	var dx := height_at(x + CELL, z) - height_at(x - CELL, z)
	var dz := height_at(x, z + CELL) - height_at(x, z - CELL)
	var n := Vector3(-dx, 2.0 * CELL, -dz).normalized()
	return 1.0 - n.y


func in_grid(x: float, z: float) -> bool:
	return x > origin.x and z > origin.y and x < origin.x + (size.x - 1) * CELL and z < origin.y + (size.y - 1) * CELL


## Campo de distância grosso: semeia perto da pista (distância - área ocupada daquele ponto)
## e propaga com distância chanfrada (duas passadas).
func _build_clearance(track: RaceTrack, area: Rect2) -> void:
	var p := track.path
	_clear_origin = (area.position / COARSE).floor() * COARSE
	_clear_size = Vector2i(ceili(area.size.x / COARSE) + 2, ceili(area.size.y / COARSE) + 2)
	var w := _clear_size.x
	var hgt := _clear_size.y
	_clear.resize(w * hgt)
	_clear.fill(1e5)
	for i in p.size():
		var extent := maxf(track.structure_extent(i, 1), track.structure_extent(i, -1)) + 12.0
		var pt := Vector2(p.points[i].x, p.points[i].z)
		var cx := int(round((pt.x - _clear_origin.x) / COARSE))
		var cz := int(round((pt.y - _clear_origin.y) / COARSE))
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var x := cx + dx
				var z := cz + dz
				if x < 0 or z < 0 or x >= w or z >= hgt:
					continue
				var c := _clear_origin + Vector2(x, z) * COARSE
				var k := z * w + x
				_clear[k] = minf(_clear[k], c.distance_to(pt) - extent)
	var d1 := COARSE
	var d2 := COARSE * 1.4142
	for z in hgt:
		for x in w:
			var k := z * w + x
			var v := _clear[k]
			if x > 0:
				v = minf(v, _clear[k - 1] + d1)
			if z > 0:
				v = minf(v, _clear[k - w] + d1)
				if x > 0:
					v = minf(v, _clear[k - w - 1] + d2)
				if x < w - 1:
					v = minf(v, _clear[k - w + 1] + d2)
			_clear[k] = v
	for z in range(hgt - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var k := z * w + x
			var v := _clear[k]
			if x < w - 1:
				v = minf(v, _clear[k + 1] + d1)
			if z < hgt - 1:
				v = minf(v, _clear[k + w] + d1)
				if x < w - 1:
					v = minf(v, _clear[k + w + 1] + d2)
				if x > 0:
					v = minf(v, _clear[k + w - 1] + d2)
			_clear[k] = v


# ---------------------------------------------------------------------------
# Construção dos nós
# ---------------------------------------------------------------------------
static func build(track: RaceTrack, parent: Node3D) -> TrackTerrain:
	var terrain := TrackTerrain.new(track.terrain_seed)
	terrain.setup(track)
	var root := Node3D.new()
	root.name = "Terrain"
	parent.add_child(root)

	# Colisão: HeightMapShape3D (1 unidade por amostra, escalado para CELL)
	var body := TrackSurface.make_body("Ground", TrackSurface.Type.GRASS)
	var shape := HeightMapShape3D.new()
	shape.map_width = terrain.size.x
	shape.map_depth = terrain.size.y
	shape.map_data = terrain.heights
	var col := CollisionShape3D.new()
	col.shape = shape
	var extent := Vector2(terrain.size - Vector2i.ONE) * CELL
	col.transform = Transform3D(Basis.from_scale(Vector3(CELL, 1.0, CELL)),
		Vector3(terrain.origin.x + extent.x * 0.5, 0.0, terrain.origin.y + extent.y * 0.5))
	body.add_child(col)
	root.add_child(body)

	# Blocos visuais: um PlaneMesh compartilhado, deslocado pelo shader com a textura de altura
	var mat := terrain.make_material()
	var plane := PlaneMesh.new()
	var chunk_size := CHUNK_CELLS * CELL
	plane.size = Vector2(chunk_size, chunk_size)
	plane.subdivide_width = CHUNK_CELLS - 1
	plane.subdivide_depth = CHUNK_CELLS - 1
	plane.material = mat
	var chunks := Vector2i(ceili(float(terrain.size.x - 1) / CHUNK_CELLS), ceili(float(terrain.size.y - 1) / CHUNK_CELLS))
	for cz in chunks.y:
		for cx in chunks.x:
			var lo := Vector2i(cx * CHUNK_CELLS, cz * CHUNK_CELLS)
			var hmin := INF
			var hmax := -INF
			for z in range(lo.y, mini(lo.y + CHUNK_CELLS + 1, terrain.size.y)):
				for x in range(lo.x, mini(lo.x + CHUNK_CELLS + 1, terrain.size.x)):
					var h := terrain.heights[z * terrain.size.x + x]
					hmin = minf(hmin, h)
					hmax = maxf(hmax, h)
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.mesh = plane
			mi.position = Vector3(terrain.origin.x + (lo.x + CHUNK_CELLS * 0.5) * CELL, 0.0,
				terrain.origin.y + (lo.y + CHUNK_CELLS * 0.5) * CELL)
			mi.custom_aabb = AABB(Vector3(-chunk_size * 0.5, hmin - 1.0, -chunk_size * 0.5),
				Vector3(chunk_size, hmax - hmin + 2.0, chunk_size))
			# Blocos totalmente planos não precisam projetar sombra
			if hmax < 0.5:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
	root.add_child(terrain._build_far_ring())
	return terrain


func make_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/terrain.gdshader")
	mat.set_shader_parameter("use_heightmap", true)
	mat.set_shader_parameter("normal_tex", TrackMaterials.normal_texture("grass"))
	mat.set_shader_parameter("normal_strength", 0.9)
	apply_heightmap(mat)
	return mat


## Passa a textura de altura e a geometria da grade para um material (terreno, grama).
func apply_heightmap(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("heightmap", texture)
	mat.set_shader_parameter("hm_origin", origin)
	mat.set_shader_parameter("hm_cell", CELL)
	mat.set_shader_parameter("hm_size", size)


## Anel de montanhas além da grade (malha polar mais grossa, mesma função de altura).
## Onde ele se sobrepõe à grade fica alguns metros abaixo, escondido.
func _build_far_ring() -> MeshInstance3D:
	var r_in := minf(size.x, size.y) * CELL * 0.5 - 80.0
	var r_out := track_radius + 7000.0
	var segments := 288
	var rings := 64
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var radii := PackedFloat32Array()
	for k in rings + 1:
		radii.append(r_in * pow(r_out / r_in, float(k) / rings))
	for k in rings + 1:
		for s in segments:
			var a := TAU * s / segments
			var x := center.x + cos(a) * radii[k]
			var z := center.y + sin(a) * radii[k]
			# Dentro da grade fica escondido sob o terreno de verdade
			var h := height_at(x, z) - 6.0 if in_grid(x, z) else raw_height(x, z, 1e5) + relief_at(x, z)
			verts.append(Vector3(x, h, z))
	for k in rings + 1:
		for s in segments:
			var i := k * segments + s
			var left := verts[k * segments + (s + segments - 1) % segments]
			var right := verts[k * segments + (s + 1) % segments]
			var inner := verts[maxi(k - 1, 0) * segments + s]
			var outer := verts[mini(k + 1, rings) * segments + s]
			var n := (outer - inner).cross(right - left).normalized()
			normals.append(n if n.y > 0.0 else -n)
			if k < rings:
				var j := i + segments
				var i2 := k * segments + (s + 1) % segments
				var j2 := i2 + segments
				indices.append_array([i, j, i2, i2, j, j2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/terrain.gdshader")
	mat.set_shader_parameter("use_heightmap", false)
	mat.set_shader_parameter("normal_tex", TrackMaterials.normal_texture("grass"))
	mat.set_shader_parameter("normal_strength", 0.6)
	mat.set_shader_parameter("normal_scale", 0.05)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Mountains"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
