class_name TrailRibbon
extends MeshInstance3D
## Fita que segue um ponto (rastro). Dois modos:
##  * GROUND: faixa deitada no chão (marca de pneu), alinhada à normal do piso; os pontos ficam
##    até sumir por idade (`lifetime`) ou excesso (`max_points`). A malha só é refeita quando muda.
##  * BILLBOARD: fita virada para a câmera (rastro de luz), refeita todo quadro.
## Cada `stop()` encerra o traço atual; o próximo `add_point()` começa outro (sem ligar os dois).
## Fica em coordenadas de mundo (top_level). A malha é um ArrayMesh montado de uma vez com arrays
## compactos (dois vértices por ponto); sem pontos, não faz nada.

enum Mode { GROUND, BILLBOARD }

var mode := Mode.GROUND
var width := 0.3
var lifetime := 20.0
var max_points := 500
var min_spacing := 0.25
## Cor; o alfa some ao longo da idade (fade_start = fração da vida em que começa a sumir).
var color := Color(0.05, 0.05, 0.06, 0.6)
var fade_start := 0.6
## Alfa extra perto da ponta nova (BILLBOARD: a fita "nasce" brilhante e afina).
var taper := false

var _points: Array = []  # [posição, normal, lateral, tempo, novo traço?]
var _time := 0.0
var _dirty := false
var _mesh := ArrayMesh.new()
## Marcas no chão: refaz para o desbotamento a cada tantos quadros.
const FADE_FRAMES := 45
var _break := true


func _init() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0


func add_point(pos: Vector3, normal: Vector3, forward: Vector3) -> void:
	if not _points.is_empty() and not _break:
		var last: Array = _points[_points.size() - 1]
		if (last[0] as Vector3).distance_to(pos) < min_spacing:
			return
	var side := normal.cross(forward).normalized()
	_points.append([pos, normal, side, _time, _break])
	_break = false
	while _points.size() > max_points:
		_points.pop_front()
	_dirty = true


func stop() -> void:
	_break = true


func clear() -> void:
	_points.clear()
	_dirty = true


func _process(delta: float) -> void:
	_time += delta
	if _points.is_empty():
		if _dirty:
			_mesh.clear_surfaces()
			_dirty = false
		return
	var removed := false
	while not _points.is_empty() and _time - float(_points[0][3]) > lifetime:
		_points.pop_front()
		removed = true
	# Marcas no chão: só refaz quando muda ou de tempos em tempos para o desbotamento
	if mode == Mode.BILLBOARD or _dirty or removed or (Engine.get_process_frames() + get_instance_id()) % FADE_FRAMES == 0:
		_rebuild()
		_dirty = false


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var n := _points.size()
	if n < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	verts.resize(n * 2)
	normals.resize(n * 2)
	colors.resize(n * 2)
	uvs.resize(n * 2)
	for k in n:
		var p: Array = _points[k]
		var pos: Vector3 = p[0]
		var side: Vector3 = p[2]
		if mode == Mode.BILLBOARD:
			# Fita virada para a câmera, na direção do traço naquele ponto
			var dir := ((_points[mini(k + 1, n - 1)][0] as Vector3) - (_points[maxi(k - 1, 0)][0] as Vector3)).normalized()
			side = dir.cross(cam_pos - pos).normalized()
		var w := width * ((0.25 + 0.75 * float(k) / n) if taper else 1.0) * 0.5
		var c := _color_at(float(p[3]), k)
		verts[k * 2] = pos - side * w
		verts[k * 2 + 1] = pos + side * w
		normals[k * 2] = p[1]
		normals[k * 2 + 1] = p[1]
		colors[k * 2] = c
		colors[k * 2 + 1] = c
		uvs[k * 2] = Vector2(0.0, 0.0)
		uvs[k * 2 + 1] = Vector2(1.0, 0.0)
		# Liga ao ponto anterior, a não ser no começo de um traço novo
		if k > 0 and not p[4]:
			var a := (k - 1) * 2
			index.append_array([a, a + 2, a + 3, a, a + 3, a + 1])
	if index.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _color_at(born: float, index: int) -> Color:
	var age := (_time - born) / lifetime
	var alpha := 1.0 - smoothstep(fade_start, 1.0, age)
	# Pontas do traço suaves (não começa nem termina em degrau)
	alpha *= smoothstep(0.0, 3.0, float(index)) if mode == Mode.GROUND else 1.0
	return Color(color.r, color.g, color.b, color.a * alpha)
