class_name TrackFlags
extends RefCounted
## Bandeirolas (cordões de bandeirinhas triangulares) e mastros com bandeiras.
## O pano vai para um MeshBuilder com o material de bandeira (shaders/track/flag.gdshader, que faz
## tremular usando UV.x = 0 na corda/mastro e 1 na ponta); cordas e mastros vão para a estrutura.
## Todas as bandeiras apontam para o mesmo lado (WIND).

const WIND := Vector3(0.8, 0.0, 0.6)
const PENNANTS := [Color(0.95, 0.2, 0.25), Color(1.0, 0.82, 0.15), Color(0.2, 0.55, 0.95), Color(0.15, 0.75, 0.45),
	Color(0.98, 0.98, 0.98), Color(1.0, 0.45, 0.7), Color(1.0, 0.55, 0.15)]
const ITALY := [Color(0.1, 0.6, 0.3), Color(0.97, 0.97, 0.97), Color(0.86, 0.12, 0.17)]
const ROPE := Color(0.3, 0.3, 0.34)
const POLE := Color(0.85, 0.87, 0.9)

static var _material: ShaderMaterial


static func material() -> Material:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/track/flag.gdshader")
	return _material


## Cordão de bandeirinhas de a até b, com barriga (sag) no meio.
static func bunting(cloth: MeshBuilder, a: Vector3, b: Vector3, sag := 0.6, spacing := 0.8, offset := 0) -> void:
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var dir := (b - a) / length
	var side := dir.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.5:
		side = Vector3.RIGHT
	var point := func(t: float) -> Vector3:
		return a.lerp(b, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)
	# Corda: fita fina
	var segs := maxi(int(length / 2.0), 2)
	for k in segs:
		var p0: Vector3 = point.call(float(k) / segs)
		var p1: Vector3 = point.call(float(k + 1) / segs)
		cloth.quad(p0, p1, p1 - Vector3.UP * 0.04, p0 - Vector3.UP * 0.04, ROPE, side,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	# Bandeirinhas
	var n := int(length / spacing)
	var size := minf(spacing * 0.75, 0.6)
	for k in n:
		var top0: Vector3 = point.call((k + 0.12) / n)
		var top1: Vector3 = point.call((k + 0.88) / n)
		var tip := (top0 + top1) * 0.5 - Vector3.UP * size * 1.2
		var color: Color = PENNANTS[(k + offset) % PENNANTS.size()]
		cloth.tri(top0, top1, tip, color, side, Vector2(0, 0), Vector2(0, 0), Vector2(1, 0))


## Mastro com bandeira. style: 0 = listras verticais (ex.: Itália), 1 = faixas horizontais.
static func flagpole(structure: MeshBuilder, cloth: MeshBuilder, base: Vector3, height: float, size: Vector2,
		colors: Array, style := 0) -> void:
	structure.posts().cylinder(Transform3D(Basis(), base), 0.09, 0.06, height, POLE, 6)
	structure.posts().box(Transform3D(Basis(), base + Vector3.UP * (height + 0.08)), Vector3(0.18, 0.16, 0.18), Color(0.95, 0.8, 0.25))
	var along := WIND.normalized()
	var side := along.cross(Vector3.UP).normalized()
	var top := base + Vector3.UP * (height - 0.15)
	var nx := 8
	var ny := 4
	for i in nx:
		for j in ny:
			var u0 := float(i) / nx
			var u1 := float(i + 1) / nx
			var v0 := float(j) / ny
			var v1 := float(j + 1) / ny
			var idx := int(u0 * colors.size()) if style == 0 else int(v0 * colors.size())
			var color: Color = colors[clampi(idx, 0, colors.size() - 1)]
			var p00 := top + along * size.x * u0 - Vector3.UP * size.y * v0
			var p10 := top + along * size.x * u1 - Vector3.UP * size.y * v0
			var p11 := top + along * size.x * u1 - Vector3.UP * size.y * v1
			var p01 := top + along * size.x * u0 - Vector3.UP * size.y * v1
			cloth.quad(p00, p10, p11, p01, color, side, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 0), Vector2(u0, 0))


## Junta o pano a uma malha existente (superfície extra com o material de bandeira).
static func commit_to(cloth: MeshBuilder, mesh: ArrayMesh) -> void:
	if not cloth.is_empty():
		cloth.commit(mesh, material())
