class_name TrackPath
extends RefCounted
## Linha central de um circuito fechado, reamostrada com espaçamento constante.
##
## Coordenadas: o CSV usa (x = leste, y = norte) em metros; no Godot vira (x, z, -y), então o
## mapa visto de cima com o norte para -Z fica igual ao original (mantém o sentido da pista).
## Uma 5ª coluna opcional é a elevação (m); sem ela a pista é plana (y = 0).
## `s` é a distância ao longo da pista a partir da linha de largada (0 .. length).
## Lateral positiva = esquerda de quem pilota.

var points := PackedVector3Array()
## Direção da pista (acompanha a rampa).
var tangents := PackedVector3Array()
## Normal horizontal para a esquerda.
var lefts := PackedVector3Array()
var width_left := PackedFloat32Array()
var width_right := PackedFloat32Array()
## Curvatura com sinal (1/m): + = curva para a esquerda.
var curvature := PackedFloat32Array()
var spacing := 2.0
var length := 0.0
## Pontos onde a pista passa por cima dela mesma (Suzuka): Vector3(s de baixo, s de cima, ângulo).
var crossings: Array[Vector3] = []
## Amostras perto de um cruzamento: lá a projeção também olha a altura (os dois níveis ficam no
## mesmo lugar do plano).
var _cross_zone := PackedByteArray()
const CROSS_ZONE := 90.0

var _grid := {}
const GRID_CELL := 40.0


## Lê um CSV "x_m,y_m,w_tr_right_m,w_tr_left_m[,z_m]" (formato do TUMFTM racetrack-database,
## com a elevação opcional). start_offset: distância (m) do 1º ponto do arquivo até a largada.
static func from_csv(path: String, sample_spacing := 2.0, width_scale := 1.0, min_half_width := 0.0,
		start_offset := 0.0) -> TrackPath:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TrackPath: não foi possível abrir %s" % path)
		return null
	var raw: Array[Vector4] = []
	var heights := PackedFloat32Array()
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var v := line.split_floats(",")
		if v.size() >= 4:
			raw.append(Vector4(v[0], -v[1], v[2], v[3]))
			heights.append(v[4] if v.size() >= 5 else 0.0)
	var path_obj := TrackPath.new()
	path_obj._build(raw, heights, sample_spacing, width_scale, min_half_width, start_offset)
	return path_obj


static func _catmull(p0: Variant, p1: Variant, p2: Variant, p3: Variant, t: float) -> Variant:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _build(raw: Array[Vector4], heights: PackedFloat32Array, sample_spacing: float, width_scale: float,
		min_half: float, start_offset: float) -> void:
	spacing = sample_spacing
	var n := raw.size()
	# Catmull-Rom denso entre os pontos originais
	var dense: Array[Vector4] = []
	var dense_h := PackedFloat32Array()
	for i in n:
		var p0 := raw[(i - 1 + n) % n]
		var p1 := raw[i]
		var p2 := raw[(i + 1) % n]
		var p3 := raw[(i + 2) % n]
		for k in 8:
			var t := k / 8.0
			dense.append(_catmull(p0, p1, p2, p3, t))
			dense_h.append(_catmull(heights[(i - 1 + n) % n], heights[i], heights[(i + 1) % n], heights[(i + 2) % n], t))
	# Comprimento acumulado
	var cum := PackedFloat32Array([0.0])
	for i in range(1, dense.size() + 1):
		var a := dense[i - 1]
		var b := dense[i % dense.size()]
		cum.append(cum[i - 1] + Vector2(b.x - a.x, b.y - a.y).length())
	var total := cum[cum.size() - 1]
	var count := int(round(total / sample_spacing))
	spacing = total / count
	length = total
	points.resize(count)
	width_left.resize(count)
	width_right.resize(count)
	var j := 0
	for i in count:
		var s := fposmod(start_offset + i * spacing, total)
		if s < cum[j]:
			j = 0
		while j < dense.size() - 1 and cum[j + 1] < s:
			j += 1
		var a := dense[j]
		var b := dense[(j + 1) % dense.size()]
		var t := (s - cum[j]) / maxf(cum[j + 1] - cum[j], 1e-6)
		var v := a.lerp(b, t)
		points[i] = Vector3(v.x, lerpf(dense_h[j], dense_h[(j + 1) % dense.size()], t), v.y)
		width_right[i] = maxf(v.z * width_scale, min_half)
		width_left[i] = maxf(v.w * width_scale, min_half)
	tangents.resize(count)
	lefts.resize(count)
	curvature.resize(count)
	for i in count:
		var t := (points[(i + 1) % count] - points[(i - 1 + count) % count]).normalized()
		tangents[i] = t
		lefts[i] = Vector3(t.z, 0.0, -t.x).normalized()
	# Curvatura suavizada (diferença de rumo, no plano, em ±3 amostras)
	for i in count:
		var ta := Vector2(tangents[(i - 3 + count) % count].x, tangents[(i - 3 + count) % count].z).normalized()
		var tb := Vector2(tangents[(i + 3) % count].x, tangents[(i + 3) % count].z).normalized()
		var ang := atan2(ta.x * tb.y - ta.y * tb.x, ta.dot(tb))
		curvature[i] = -ang / (6.0 * spacing)
	_build_grid()
	_find_crossings()


func size() -> int:
	return points.size()


func wrap_index(i: int) -> int:
	return posmod(i, points.size())


func index_at(s: float) -> int:
	return posmod(int(round(s / spacing)), points.size())


func wrap_s(s: float) -> float:
	return fposmod(s, length)


func s_at(i: int) -> float:
	return i * spacing


## Ponto sobre a pista (interpolado) com deslocamento lateral (+ = esquerda).
func position_at(s: float, lateral := 0.0) -> Vector3:
	var f := fposmod(s, length) / spacing
	var i := int(floor(f))
	var t := f - i
	var a := points[i % points.size()] + lefts[i % points.size()] * lateral
	var b := points[(i + 1) % points.size()] + lefts[(i + 1) % points.size()] * lateral
	return a.lerp(b, t)


func tangent_at(s: float) -> Vector3:
	var f := fposmod(s, length) / spacing
	var i := int(floor(f))
	return tangents[i % points.size()].slerp(tangents[(i + 1) % points.size()], f - i).normalized()


## Referencial sobre a pista, igual ao do carro: +Z = sentido da pista (inclinado com a rampa),
## +X = esquerda (sempre horizontal: a pista não tem inclinação lateral), +Y = cima.
func frame_at(s: float, lateral := 0.0, height := 0.0) -> Transform3D:
	var fwd := tangent_at(s)
	var left := Vector3(fwd.z, 0.0, -fwd.x).normalized()
	var up := fwd.cross(left)
	return Transform3D(Basis(left, up, fwd), position_at(s, lateral) + up * height)


## Altura (y) da pista em s.
func height_at(s: float) -> float:
	return position_at(s).y


## Meia-largura de um lado (side = +1 esquerda, -1 direita) no índice i.
func half_width(i: int, side: int) -> float:
	return width_left[i] if side > 0 else width_right[i]


## Ponto mais próximo da linha central: Vector2(s, lateral).
## Com exhaustive = false, pontos a mais de ~120 m da pista retornam Vector2(-1, INF) (rápido).
## Perto de um cruzamento a altura de `pos` escolhe o nível (use_height = false: só o plano).
func project(pos: Vector3, exhaustive := true, use_height := true) -> Vector2:
	var height := use_height and not crossings.is_empty()
	var key := Vector2i(floori(pos.x / GRID_CELL), floori(pos.z / GRID_CELL))
	var best := -1
	var best_d := INF
	for r in 3:
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var cell: PackedInt32Array = _grid.get(key + Vector2i(dx, dz), PackedInt32Array())
				for i in cell:
					var d := Vector2(points[i].x - pos.x, points[i].z - pos.z).length_squared()
					if height and _cross_zone[i]:
						d += _height_penalty(pos.y - points[i].y)
					if d < best_d:
						best_d = d
						best = i
		if best >= 0 and sqrt(best_d) < GRID_CELL * r:
			break
	if best < 0 and not exhaustive:
		return Vector2(-1.0, INF)
	if best < 0:
		# Longe da pista: busca completa
		for i in points.size():
			var d := Vector2(points[i].x - pos.x, points[i].z - pos.z).length_squared()
			if height and _cross_zone[i]:
				d += _height_penalty(pos.y - points[i].y)
			if d < best_d:
				best_d = d
				best = i
	var rel := pos - points[best]
	var along := rel.dot(tangents[best])
	return Vector2(fposmod(best * spacing + along, length), rel.dot(lefts[best]))


## Projeção só entre as amostras a até `reach` m de s0 (um trecho, num cruzamento): Vector2(s, lateral).
func project_near(pos: Vector3, s0: float, reach: float) -> Vector2:
	var i0 := index_at(s0)
	var k := int(reach / spacing)
	var best := i0
	var best_d := INF
	for d in range(-k, k + 1):
		var i := wrap_index(i0 + d)
		var dd := Vector2(points[i].x - pos.x, points[i].z - pos.z).length_squared()
		if dd < best_d:
			best_d = dd
			best = i
	var rel := pos - points[best]
	return Vector2(fposmod(best * spacing + rel.dot(tangents[best]), length), rel.dot(lefts[best]))


## Diferença de altura vira distância: a até ~3 m (carro em cima da pista, lombadas) quase não
## conta; o outro nível (~10 m) fica bem mais longe que qualquer ponto do próprio trecho.
static func _height_penalty(dy: float) -> float:
	var e := maxf(absf(dy) - 2.5, 0.0) * 6.0
	return e * e


## Acha os cruzamentos (segmentos que se cortam no plano com alturas diferentes) e marca as
## amostras a até CROSS_ZONE m deles.
func _find_crossings() -> void:
	crossings.clear()
	var n := points.size()
	_cross_zone.resize(n)
	_cross_zone.fill(0)
	var min_gap := int(200.0 / spacing)
	for i in n:
		var a := Vector2(points[i].x, points[i].z)
		var b := Vector2(points[(i + 1) % n].x, points[(i + 1) % n].z)
		var key := Vector2i(floori(a.x / GRID_CELL), floori(a.y / GRID_CELL))
		var seen := {}
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for j: int in _grid.get(key + Vector2i(dx, dz), PackedInt32Array()):
					if j <= i or seen.has(j):
						continue
					seen[j] = true
					if mini(j - i, n - (j - i)) < min_gap:
						continue
					var c := Vector2(points[j].x, points[j].z)
					var d := Vector2(points[(j + 1) % n].x, points[(j + 1) % n].z)
					var hit: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
					if hit == null:
						continue
					var ti := (hit as Vector2).distance_to(a) / maxf(a.distance_to(b), 1e-6)
					var tj := (hit as Vector2).distance_to(c) / maxf(c.distance_to(d), 1e-6)
					var si := (i + ti) * spacing
					var sj := (j + tj) * spacing
					var ang := acos(clampf(absf((b - a).normalized().dot((d - c).normalized())), 0.0, 1.0))
					var dup := false
					for o in crossings:
						dup = dup or absf(o.x - si) < 20.0 or absf(o.y - si) < 20.0
					if dup:
						continue
					if height_at(si) < height_at(sj):
						crossings.append(Vector3(si, sj, ang))
					else:
						crossings.append(Vector3(sj, si, ang))
	for c in crossings:
		for s0 in [c.x, c.y]:
			var k := int(CROSS_ZONE / spacing)
			for d in range(-k, k + 1):
				_cross_zone[wrap_index(index_at(s0) + d)] = 1


func _build_grid() -> void:
	_grid.clear()
	for i in points.size():
		var key := Vector2i(floori(points[i].x / GRID_CELL), floori(points[i].z / GRID_CELL))
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		var cell: PackedInt32Array = _grid[key]
		cell.append(i)
		_grid[key] = cell


## Retângulo que envolve a pista (x, z).
func bounds() -> Rect2:
	var r := Rect2(points[0].x, points[0].z, 0, 0)
	for p in points:
		r = r.expand(Vector2(p.x, p.z))
	return r
