@tool
class_name TestCircuit
extends Node3D
## Circuito de teste gerado proceduralmente a partir de pontos de controle (spline fechada).
## Gera asfalto, linhas brancas, zebras nas curvas, linha de largada e árvores estilizadas.
## É só visual: a física usa o plano do chão (StaticBody3D "Ground" da cena).

@export var control_points := PackedVector2Array([
	Vector2(0, -100), Vector2(0, 100), Vector2(0, 300), Vector2(0, 450),
	Vector2(25, 540), Vector2(100, 580), Vector2(180, 560),
	Vector2(220, 480), Vector2(210, 380), Vector2(240, 300), Vector2(320, 270),
	Vector2(420, 280), Vector2(500, 240), Vector2(520, 140),
	Vector2(480, 40), Vector2(400, 0), Vector2(380, -80), Vector2(420, -180),
	Vector2(400, -300), Vector2(320, -360), Vector2(200, -350),
	Vector2(120, -300), Vector2(60, -260), Vector2(15, -200),
]):
	set(value):
		control_points = value
		_queue_rebuild()
@export var track_width := 14.0:
	set(value):
		track_width = value
		_queue_rebuild()
@export var sample_spacing := 2.0
## Curvatura (1/raio) a partir da qual aparecem zebras.
@export var kerb_curvature := 0.007
@export var tree_count := 260
@export var tree_seed := 7
## Retângulos (x0, z0, x1, z1) onde não nascem árvores (área de testes).
@export var keep_clear: Array[Rect2] = [Rect2(-140, -160, 130, 420)]

const ASPHALT := Color(0.25, 0.26, 0.31)
const LINE := Color(0.95, 0.95, 0.97)
const KERB_RED := Color(0.86, 0.12, 0.16)
const KERB_WHITE := Color(0.96, 0.96, 0.98)

var points: PackedVector3Array = []
var tangents: PackedVector3Array = []
var _rebuild_queued := false


func _ready() -> void:
	rebuild()


func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func rebuild() -> void:
	_rebuild_queued = false
	for child in get_children():
		child.queue_free()
	if control_points.size() < 4:
		return
	_sample_spline()
	_build_road()
	_build_trees()


## Transformação de largada (sobre o ponto de controle 0 → 1, olhando no sentido da pista).
func get_start_transform(offset_back := 0.0) -> Transform3D:
	var p := points[0] - tangents[0] * offset_back
	return Transform3D(Basis.looking_at(-tangents[0]), p)


func distance_to_track(p: Vector3) -> float:
	var best := INF
	for i in range(0, points.size(), 4):
		best = minf(best, Vector2(points[i].x - p.x, points[i].z - p.z).length())
	return best - track_width * 0.5


func _sample_spline() -> void:
	var dense: Array[Vector3] = []
	var n := control_points.size()
	for i in n:
		var p0 := control_points[(i - 1 + n) % n]
		var p1 := control_points[i]
		var p2 := control_points[(i + 1) % n]
		var p3 := control_points[(i + 2) % n]
		for k in 24:
			var c := _catmull(p0, p1, p2, p3, k / 24.0)
			dense.append(Vector3(c.x, 0.0, c.y))
	# Reamostragem com espaçamento constante ao longo da curva
	points = PackedVector3Array([dense[0]])
	var carry := 0.0
	for i in range(1, dense.size() + 1):
		var a := dense[i - 1]
		var b := dense[i % dense.size()]
		var seg := a.distance_to(b)
		var d := sample_spacing - carry
		while d <= seg:
			points.append(a.lerp(b, d / seg))
			d += sample_spacing
		carry = seg - (d - sample_spacing)
	if points[points.size() - 1].distance_to(points[0]) < sample_spacing * 0.5:
		points.remove_at(points.size() - 1)
	tangents.resize(points.size())
	for i in points.size():
		var prev := points[(i - 1 + points.size()) % points.size()]
		var next := points[(i + 1) % points.size()]
		tangents[i] = (next - prev).normalized()


func _build_road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := track_width * 0.5
	var count := points.size()
	for i in count:
		var j := (i + 1) % count
		# Asfalto
		_quad(st, i, j, -half, half, 0.012, ASPHALT)
		# Linhas brancas de borda
		_quad(st, i, j, half - 0.75, half - 0.5, 0.018, LINE)
		_quad(st, i, j, -half + 0.5, -half + 0.75, 0.018, LINE)
		# Zebras nas curvas
		if _curvature(i) > kerb_curvature:
			var color := KERB_RED if i % 2 == 0 else KERB_WHITE
			_quad(st, i, j, half, half + 1.5, 0.022, color)
			_quad(st, i, j, -half - 1.5, -half, 0.022, color)
	# Linha de largada quadriculada
	var cells := 14
	for row in 2:
		for col in cells:
			var color := Color.WHITE if (row + col) % 2 == 0 else Color(0.08, 0.08, 0.1)
			var a := -half + track_width * col / cells
			var b := -half + track_width * (col + 1) / cells
			_rect(st, points[0] + tangents[0] * (row * 0.9 - 0.9), tangents[0], a, b, 0.9, 0.024, color)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.name = "Road"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	lo -= Vector2(150, 150)
	hi += Vector2(150, 150)
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < tree_count and tries < tree_count * 20:
		tries += 1
		var pos := Vector3(rng.randf_range(lo.x, hi.x), 0.0, rng.randf_range(lo.y, hi.y))
		if distance_to_track(pos) < 14.0:
			continue
		var blocked := false
		for r in keep_clear:
			if r.has_point(Vector2(pos.x, pos.z)):
				blocked = true
		if blocked:
			continue
		var s := rng.randf_range(0.8, 1.6)
		transforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), pos))

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.35
	trunk.height = 2.0
	trunk.radial_segments = 6
	var crown := CylinderMesh.new()
	crown.top_radius = 0.0
	crown.bottom_radius = 2.4
	crown.height = 6.0
	crown.radial_segments = 7
	crown.rings = 1
	_add_multimesh("TreeTrunks", trunk, CarLivery._toon(Color("8a5a3c"), 0.8, 0.0, 0.0), transforms, 1.0)
	_add_multimesh("TreeCrowns", crown, CarLivery._toon(Color("2f9e5b"), 0.6, 0.0, 0.25), transforms, 4.5)


func _add_multimesh(node_name: String, mesh: Mesh, mat: Material, transforms: Array[Transform3D], lift: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		var t := transforms[i]
		mm.set_instance_transform(i, Transform3D(t.basis, t.origin + Vector3.UP * lift * t.basis.get_scale().y))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


func _curvature(i: int) -> float:
	var count := points.size()
	var a := tangents[(i - 2 + count) % count]
	var b := tangents[(i + 2) % count]
	return a.angle_to(b) / (4.0 * sample_spacing)


func _side(i: int) -> Vector3:
	var t := tangents[i]
	return Vector3(t.z, 0.0, -t.x)  # esquerda da pista


func _quad(st: SurfaceTool, i: int, j: int, a: float, b: float, y: float, color: Color) -> void:
	var up := Vector3.UP * y
	var pa := points[i] + _side(i) * a + up
	var pb := points[i] + _side(i) * b + up
	var qa := points[j] + _side(j) * a + up
	var qb := points[j] + _side(j) * b + up
	_tri(st, pa, qa, pb, color)
	_tri(st, pb, qa, qb, color)


func _rect(st: SurfaceTool, origin: Vector3, forward: Vector3, a: float, b: float, length: float, y: float, color: Color) -> void:
	var side := Vector3(forward.z, 0.0, -forward.x)
	var up := Vector3.UP * y
	var pa := origin + side * a + up
	var pb := origin + side * b + up
	var qa := pa + forward * length
	var qb := pb + forward * length
	_tri(st, pa, qa, pb, color)
	_tri(st, pb, qa, qb, color)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	# Godot usa ordem horária para a face da frente: garante a face voltada para cima
	if (b - a).cross(c - a).y > 0.0:
		var tmp := b
		b = c
		c = tmp
	for v in [a, b, c]:
		st.set_color(color)
		st.add_vertex(v)


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
