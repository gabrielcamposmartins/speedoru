class_name TrackPath
extends RefCounted
## Linha central de um circuito fechado, reamostrada com espaçamento constante.
##
## Coordenadas: o CSV usa (x = leste, y = norte) em metros; no Godot vira (x, 0, -y), então o
## mapa visto de cima com o norte para -Z fica igual ao original (mantém o sentido da pista).
## `s` é a distância ao longo da pista a partir da linha de largada (0 .. length).
## Lateral positiva = esquerda de quem pilota.

var points := PackedVector3Array()
var tangents := PackedVector3Array()
## Normal horizontal para a esquerda.
var lefts := PackedVector3Array()
var width_left := PackedFloat32Array()
var width_right := PackedFloat32Array()
## Curvatura com sinal (1/m): + = curva para a esquerda.
var curvature := PackedFloat32Array()
var spacing := 2.0
var length := 0.0

var _grid := {}
const GRID_CELL := 40.0


## Lê um CSV "x_m,y_m,w_tr_right_m,w_tr_left_m" (formato do TUMFTM racetrack-database).
## start_offset: distância (m) do 1º ponto do arquivo até a linha de largada.
static func from_csv(path: String, sample_spacing := 2.0, width_scale := 1.0, min_half_width := 0.0,
		start_offset := 0.0) -> TrackPath:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TrackPath: não foi possível abrir %s" % path)
		return null
	var raw: Array[Vector4] = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var v := line.split_floats(",")
		if v.size() >= 4:
			raw.append(Vector4(v[0], -v[1], v[2], v[3]))
	var path_obj := TrackPath.new()
	path_obj._build(raw, sample_spacing, width_scale, min_half_width, start_offset)
	return path_obj


func _build(raw: Array[Vector4], sample_spacing: float, width_scale: float, min_half: float,
		start_offset: float) -> void:
	spacing = sample_spacing
	var n := raw.size()
	# Catmull-Rom denso entre os pontos originais
	var dense: Array[Vector4] = []
	for i in n:
		var p0 := raw[(i - 1 + n) % n]
		var p1 := raw[i]
		var p2 := raw[(i + 1) % n]
		var p3 := raw[(i + 2) % n]
		for k in 8:
			var t := k / 8.0
			var t2 := t * t
			var t3 := t2 * t
			dense.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
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
		points[i] = Vector3(v.x, 0.0, v.y)
		width_right[i] = maxf(v.z * width_scale, min_half)
		width_left[i] = maxf(v.w * width_scale, min_half)
	tangents.resize(count)
	lefts.resize(count)
	curvature.resize(count)
	for i in count:
		var t := (points[(i + 1) % count] - points[(i - 1 + count) % count]).normalized()
		tangents[i] = t
		lefts[i] = Vector3(t.z, 0.0, -t.x)
	# Curvatura suavizada (diferença de rumo em ±3 amostras)
	for i in count:
		var ta := tangents[(i - 3 + count) % count]
		var tb := tangents[(i + 3) % count]
		var ang := atan2(ta.x * tb.z - ta.z * tb.x, ta.dot(tb))
		curvature[i] = -ang / (6.0 * spacing)
	_build_grid()


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


## Referencial sobre a pista, igual ao do carro: +Z = sentido da pista, +X = esquerda, +Y = cima.
func frame_at(s: float, lateral := 0.0, height := 0.0) -> Transform3D:
	var fwd := tangent_at(s)
	var left := Vector3(fwd.z, 0.0, -fwd.x)
	return Transform3D(Basis(left, Vector3.UP, fwd), position_at(s, lateral) + Vector3.UP * height)


## Meia-largura de um lado (side = +1 esquerda, -1 direita) no índice i.
func half_width(i: int, side: int) -> float:
	return width_left[i] if side > 0 else width_right[i]


## Ponto mais próximo da linha central: Vector2(s, lateral).
## Com exhaustive = false, pontos a mais de ~120 m da pista retornam Vector2(-1, INF) (rápido).
func project(pos: Vector3, exhaustive := true) -> Vector2:
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
			if d < best_d:
				best_d = d
				best = i
	var rel := pos - points[best]
	var along := rel.dot(tangents[best])
	return Vector2(fposmod(best * spacing + along, length), rel.dot(lefts[best]))


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
