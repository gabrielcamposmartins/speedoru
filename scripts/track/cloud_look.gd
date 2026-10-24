class_name CloudLook
extends RefCounted
## Paleta, formas e materiais compartilhados da pista fofa nas nuvens (Rainbow Raceway): as cores do
## arco-íris pastel, o contorno de coração e de estrela (para pinturas no chão, luzes, placas e
## enfeites), as nuvens fofas (cloud.gdshader em tons de algodão-doce) e o brilho das luzes.

## Arco-íris pastel (de fora para dentro): vermelho-morango, laranja, amarelo, menta, azul-céu, lilás.
const RAINBOW := [Color(1.0, 0.38, 0.5), Color(1.0, 0.64, 0.32), Color(1.0, 0.89, 0.36), Color(0.46, 0.9, 0.58),
	Color(0.42, 0.72, 1.0), Color(0.7, 0.52, 0.98)]
const PINK := Color(1.0, 0.62, 0.8)
const HOT_PINK := Color(1.0, 0.36, 0.64)
const CREAM := Color(1.0, 0.95, 0.97)
const LILAC := Color(0.76, 0.64, 1.0)
const MINT := Color(0.6, 0.95, 0.8)
const BABY_BLUE := Color(0.62, 0.82, 1.0)
const BUTTER := Color(1.0, 0.92, 0.55)
const PEACH := Color(1.0, 0.76, 0.62)
## Cores das coisas (casinhas, doces, flores, balões) sorteadas com `pick`.
const CANDY := [PINK, HOT_PINK, LILAC, MINT, BABY_BLUE, BUTTER, PEACH, CREAM]
## Nuvens à noite: até quanto a cor cai (cloud.gdshader) e o brilho lilás próprio.
const NIGHT_FLOOR := 0.5
const NIGHT_GLOW := 0.12

static var _materials := {}
static var _meshes := {}


static func pick(rng: RandomNumberGenerator, list: Array = CANDY) -> Color:
	return list[rng.randi() % list.size()]


## Contorno de coração no plano (x para a direita, y para a frente: os dois lóbulos em +y, a ponta
## em -y), com largura total `width`, centrado. `points` pontos em volta.
static func heart(width: float, points := 40) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in points:
		var t := TAU * k / points
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		# (centraliza: a curva vai de -17 a +12 em y)
		out.append(Vector2(x, y + 2.5) * (width / 32.0))
	return out


## Estrela de `tips` pontas (contorno alternando raio externo e interno), primeira ponta em +y.
static func star(outer: float, inner_ratio := 0.45, tips := 5) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in tips * 2:
		var a := PI * 0.5 + PI * k / tips
		var r := outer if k % 2 == 0 else outer * inner_ratio
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


## Polígono cheio (em leque a partir do centro) num plano dado por `xf` (X e Z do plano: x → X,
## y → -Z, normal +Y), com a cor `color`.
static func fill(mb: MeshBuilder, poly: PackedVector2Array, xf: Transform3D, color: Color, normal := Vector3.ZERO) -> void:
	var center := Vector2.ZERO
	for q in poly:
		center += q
	center /= poly.size()
	var c3 := xf * Vector3(center.x, 0.0, -center.y)
	var nrm := normal if normal != Vector3.ZERO else xf.basis.y.normalized()
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		mb.tri(c3, xf * Vector3(a.x, 0.0, -a.y), xf * Vector3(b.x, 0.0, -b.y), color, nrm)


## Contorno (faixa de largura `line`) de um polígono no plano de `xf`, para dentro.
static func outline(mb: MeshBuilder, poly: PackedVector2Array, xf: Transform3D, line: float, color: Color, normal := Vector3.ZERO) -> void:
	var center := Vector2.ZERO
	for q in poly:
		center += q
	center /= poly.size()
	var nrm := normal if normal != Vector3.ZERO else xf.basis.y.normalized()
	var n := poly.size()
	for k in n:
		var a := poly[k]
		var b := poly[(k + 1) % n]
		var ia := a + (center - a).normalized() * line
		var ib := b + (center - b).normalized() * line
		mb.quad(xf * Vector3(a.x, 0.0, -a.y), xf * Vector3(b.x, 0.0, -b.y), xf * Vector3(ib.x, 0.0, -ib.y),
			xf * Vector3(ia.x, 0.0, -ia.y), color, nrm)


## Peça com volume (prisma) de um polígono: frente e verso no plano XY de `xf` (o polígono em x, y),
## espessura `depth` em Z. Para corações e estrelas de pé (placas, luzes, enfeites).
static func slab(mb: MeshBuilder, poly: PackedVector2Array, xf: Transform3D, depth: float, color: Color, side_color := Color(0, 0, 0, 0)) -> void:
	var side := side_color if side_color.a > 0.0 else color.darkened(0.12)
	var h := depth * 0.5
	var center := Vector2.ZERO
	for q in poly:
		center += q
	center /= poly.size()
	var n := poly.size()
	for k in n:
		var a := poly[k]
		var b := poly[(k + 1) % n]
		var fa := xf * Vector3(a.x, a.y, h)
		var fb := xf * Vector3(b.x, b.y, h)
		var ba := xf * Vector3(a.x, a.y, -h)
		var bb := xf * Vector3(b.x, b.y, -h)
		mb.tri(xf * Vector3(center.x, center.y, h), fa, fb, color, xf.basis.z)
		mb.tri(xf * Vector3(center.x, center.y, -h), ba, bb, color, -xf.basis.z)
		var out := xf.basis * Vector3(b.y - a.y, a.x - b.x, 0.0)
		mb.quad(fa, fb, bb, ba, side, out)


## Material das nuvens fofas (cloud.gdshader) em tom de algodão-doce: lado iluminado e sombra.
static func cloud_material(lit := Color(1.0, 0.97, 0.99), shade := Color(0.78, 0.64, 0.95)) -> ShaderMaterial:
	var key := "cloud_%s_%s" % [lit.to_html(), shade.to_html()]
	if not _materials.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/cloud.gdshader")
		mat.set_shader_parameter("lit_color", lit)
		mat.set_shader_parameter("shade_color", shade)
		mat.set_shader_parameter("night_floor", NIGHT_FLOOR)
		mat.set_shader_parameter("night_glow", NIGHT_GLOW)
		_materials[key] = mat
	return _materials[key]


## Malha de nuvem fofa (bolinhas juntas, base achatada) com `puffs` bolinhas; variante `v`.
## detail: 0 = de perto (12×8 faces por bolinha), 1 = médio (9×6), 2 = longe (7×4), 3 = bem longe (5×3).
static func puff_mesh(v: int, puffs := 7, flat := true, detail := 0) -> ArrayMesh:
	var key := "puff_%d_%d_%s_%d" % [v, puffs, flat, detail]
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + v * 31 + puffs
	var seg: int = [12, 9, 7, 5][detail]
	var rings: int = [8, 6, 4, 3][detail]
	var mb := MeshBuilder.new()
	for k in puffs:
		var x := rng.randf_range(-1.0, 1.0)
		var z := rng.randf_range(-0.5, 0.5)
		var r := rng.randf_range(0.38, 0.62) * (1.25 - absf(x) * 0.5)
		var y := r * 0.3 + rng.randf_range(0.0, 0.22) if flat else rng.randf_range(-0.25, 0.25)
		mb.blob(Vector3(x, y, z), Vector3(r, r * 0.86, r), Color.WHITE, seg, rings)
	if flat:
		for i in mb.verts.size():
			if mb.verts[i].y < 0.0:
				mb.verts[i] = Vector3(mb.verts[i].x, 0.0, mb.verts[i].z)
				mb.normals[i] = Vector3.DOWN
	_meshes[key] = mb.commit()
	return _meshes[key]


## Luz acesa (cor de vértice brilhando, mais forte à noite): sky_glow.gdshader via SkyDeck.glow.
static func glow(day := 1.5, night := 3.0, chase := 0.0) -> ShaderMaterial:
	return SkyDeck.glow(chase, day, night)


## MultiMesh com as transformações (e cores, se houver) dadas.
static func multimesh(mesh: Mesh, xfs: Array[Transform3D], colors: Array[Color] = []) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
		if mm.use_colors:
			mm.set_instance_color(k, colors[k])
	return mm


## Nó com um MultiMesh (sem sombra), visível até `range_end` m (0 = sempre). As posições das instâncias
## ficam também no metadado "points" (o servidor sem placa de vídeo não guarda as do MultiMesh).
static func add_multimesh(parent: Node3D, node_name: String, mesh: Mesh, xfs: Array[Transform3D], material: Material,
		range_end := 0.0, colors: Array[Color] = []) -> MultiMeshInstance3D:
	if xfs.is_empty():
		return null
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = multimesh(mesh, xfs, colors)
	var pts := PackedVector3Array()
	for xf in xfs:
		pts.append(xf.origin)
	mmi.set_meta("points", pts)
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if range_end > 0.0:
		mmi.visibility_range_end = range_end
		mmi.visibility_range_end_margin = range_end * 0.1
	parent.add_child(mmi)
	return mmi


## Nó com uma malha (sem sombra).
static func add_mesh(parent: Node3D, node_name: String, mesh: Mesh, material: Material = null, range_end := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	if material:
		mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if range_end > 0.0:
		mi.visibility_range_end = range_end
		mi.visibility_range_end_margin = range_end * 0.1
	parent.add_child(mi)
	return mi
