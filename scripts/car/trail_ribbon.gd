class_name TrailRibbon
extends MeshInstance3D
## Fita que segue um ponto (rastro). Dois modos:
##  * GROUND: faixa deitada no chão (marca de pneu), alinhada à normal do piso; os pontos ficam
##    até sumir por idade (`lifetime`) ou excesso (`max_points`). A malha só é refeita quando muda.
##  * BILLBOARD: fita virada para a câmera (rastro de luz), refeita todo quadro.
## Cada `stop()` encerra o traço atual; o próximo `add_point()` começa outro (sem ligar os dois).
## Fica em coordenadas de mundo (top_level).

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
var _mesh := ImmediateMesh.new()
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
	var removed := false
	while not _points.is_empty() and _time - float(_points[0][3]) > lifetime:
		_points.pop_front()
		removed = true
	# Marcas no chão: só refaz quando muda ou de tempos em tempos para o desbotamento
	if mode == Mode.BILLBOARD or _dirty or removed or (Engine.get_process_frames() % 20 == 0 and not _points.is_empty()):
		_rebuild()
		_dirty = false


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _points.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	var verts: Array = []
	var n := _points.size()
	for k in range(1, n):
		var b: Array = _points[k]
		if b[4]:
			continue  # começo de um traço novo: não liga ao anterior
		var a: Array = _points[k - 1]
		var pa: Vector3 = a[0]
		var pb: Vector3 = b[0]
		var sa: Vector3 = a[2]
		var sb: Vector3 = b[2]
		if mode == Mode.BILLBOARD:
			var dir := (pb - pa).normalized()
			sa = dir.cross(cam_pos - pa).normalized()
			sb = dir.cross(cam_pos - pb).normalized()
		var ca := _color_at(float(a[3]), k - 1)
		var cb := _color_at(float(b[3]), k)
		var wa := width * ((0.25 + 0.75 * float(k - 1) / n) if taper else 1.0)
		var wb := width * ((0.25 + 0.75 * float(k) / n) if taper else 1.0)
		var a0 := pa - sa * wa * 0.5
		var a1 := pa + sa * wa * 0.5
		var b0 := pb - sb * wb * 0.5
		var b1 := pb + sb * wb * 0.5
		verts.append_array([[a0, ca, 0.0, a[1]], [b0, cb, 0.0, b[1]], [b1, cb, 1.0, b[1]],
			[a0, ca, 0.0, a[1]], [b1, cb, 1.0, b[1]], [a1, ca, 1.0, a[1]]])
	if verts.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in verts:
		_mesh.surface_set_color(v[1])
		_mesh.surface_set_uv(Vector2(v[2], 0.0))
		_mesh.surface_set_normal(v[3])
		_mesh.surface_add_vertex(v[0])
	_mesh.surface_end()


func _color_at(born: float, index: int) -> Color:
	var age := (_time - born) / lifetime
	var alpha := 1.0 - smoothstep(fade_start, 1.0, age)
	# Pontas do traço suaves (não começa nem termina em degrau)
	alpha *= smoothstep(0.0, 3.0, float(index)) if mode == Mode.GROUND else 1.0
	return Color(color.r, color.g, color.b, color.a * alpha)
