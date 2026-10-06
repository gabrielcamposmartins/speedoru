class_name MeshBuilder
extends RefCounted
## Acumulador de geometria para os geradores da pista (mais rápido que SurfaceTool para
## milhares de quads). Normais planas por face; cor de vértice; UV opcional.
## A orientação das faces é resolvida pela normal desejada (Godot usa ordem horária na frente).

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
## Geometria sem contorno anime (postes, pilares, mastros): vira uma superfície extra com
## TrackMaterials.plain() quando este builder é commitado.
var plain: MeshBuilder


func posts() -> MeshBuilder:
	if plain == null:
		plain = MeshBuilder.new()
	return plain


func is_empty() -> bool:
	return verts.is_empty()


func tri(a: Vector3, b: Vector3, c: Vector3, color: Color, normal_hint := Vector3.ZERO,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	if normal_hint != Vector3.ZERO and n.dot(normal_hint) > 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
	elif normal_hint == Vector3.ZERO and n.y > 0.0:
		var t2 := b
		b = c
		c = t2
		var tu2 := ub
		ub = uc
		uc = tu2
	n = -(b - a).cross(c - a).normalized()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	for i in 3:
		normals.append(n)
		colors.append(color)
	uvs.append(ua)
	uvs.append(ub)
	uvs.append(uc)


## Triângulo com normais por vértice (superfícies arredondadas: copas de árvore etc.).
func tri_smooth(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, color: Color,
		cb := Color(0, 0, 0, 0), cc := Color(0, 0, 0, 0)) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	var ca := color
	if cb.a == 0.0:
		cb = color
	if cc.a == 0.0:
		cc = color
	if n.dot(na + nb + nc) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
		var tc := cb
		cb = cc
		cc = tc
	verts.append(a)
	verts.append(b)
	verts.append(c)
	normals.append(na)
	normals.append(nb)
	normals.append(nc)
	colors.append(ca)
	colors.append(cb)
	colors.append(cc)
	for i in 3:
		uvs.append(Vector2.ZERO)


## Elipsoide com normais suaves (centro, raios). shade: escurece a parte de baixo (oclusão falsa).
func blob(center: Vector3, radii: Vector3, color: Color, segments := 8, rings := 5, shade := 0.0) -> void:
	var pts := []
	var nrm := []
	for r in rings + 1:
		var phi := PI * r / rings
		var row := []
		var nrow := []
		for k in segments:
			var th := TAU * k / segments + (0.5 if r % 2 == 1 else 0.0) * TAU / segments
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			row.append(center + d * radii)
			nrow.append((d / radii).normalized())
		pts.append(row)
		nrm.append(nrow)
	for r in rings:
		for k in segments:
			var k1 := (k + 1) % segments
			var a: Vector3 = pts[r][k]
			var b: Vector3 = pts[r][k1]
			var c: Vector3 = pts[r + 1][k1]
			var d: Vector3 = pts[r + 1][k]
			var col_a := _shaded(color, nrm[r][k], shade)
			var col_b := _shaded(color, nrm[r][k1], shade)
			var col_c := _shaded(color, nrm[r + 1][k1], shade)
			var col_d := _shaded(color, nrm[r + 1][k], shade)
			if r > 0:
				tri_smooth(a, b, c, nrm[r][k], nrm[r][k1], nrm[r + 1][k1], col_a, col_b, col_c)
			if r < rings - 1:
				tri_smooth(a, c, d, nrm[r][k], nrm[r + 1][k1], nrm[r + 1][k], col_a, col_c, col_d)


static func _shaded(color: Color, n: Vector3, shade: float) -> Color:
	if shade <= 0.0:
		return color
	var f := lerpf(1.0 - shade, 1.0 + shade * 0.25, n.y * 0.5 + 0.5)
	return Color(color.r * f, color.g * f, color.b * f, 1.0)


## Quad a-b-c-d (em sequência ao redor da borda) com a face voltada para `normal_hint`
## (ZERO = para cima).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, normal_hint := Vector3.ZERO,
		ua := Vector2(0, 0), ub := Vector2(1, 0), uc := Vector2(1, 1), ud := Vector2(0, 1)) -> void:
	tri(a, b, c, color, normal_hint, ua, ub, uc)
	tri(a, c, d, color, normal_hint, ua, uc, ud)


## Caixa orientada: `xf` posiciona o centro; `size` em metros.
func box(xf: Transform3D, size: Vector3, color: Color, top_color := Color(0, 0, 0, 0)) -> void:
	var h := size * 0.5
	var c := [
		xf * Vector3(-h.x, -h.y, -h.z), xf * Vector3(h.x, -h.y, -h.z),
		xf * Vector3(h.x, h.y, -h.z), xf * Vector3(-h.x, h.y, -h.z),
		xf * Vector3(-h.x, -h.y, h.z), xf * Vector3(h.x, -h.y, h.z),
		xf * Vector3(h.x, h.y, h.z), xf * Vector3(-h.x, h.y, h.z),
	]
	var b := xf.basis
	var top := top_color if top_color.a > 0.0 else color
	quad(c[0], c[1], c[2], c[3], color, -b.z)
	quad(c[5], c[4], c[7], c[6], color, b.z)
	quad(c[4], c[0], c[3], c[7], color, -b.x)
	quad(c[1], c[5], c[6], c[2], color, b.x)
	quad(c[3], c[2], c[6], c[7], top, b.y)
	quad(c[4], c[5], c[1], c[0], color, -b.y)


## Cilindro vertical (eixo Y local de `xf`), base em y = 0.
func cylinder(xf: Transform3D, radius_bottom: float, radius_top: float, height: float, color: Color,
		sides := 8, caps := true) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var p0 := xf * (d0 * radius_bottom)
		var p1 := xf * (d1 * radius_bottom)
		var p2 := xf * (d1 * radius_top + Vector3.UP * height)
		var p3 := xf * (d0 * radius_top + Vector3.UP * height)
		quad(p0, p1, p2, p3, color, xf.basis * (d0 + d1))
		if caps and radius_top > 0.0:
			tri(xf * (Vector3.UP * height), p3, p2, color, xf.basis.y)


## Acrescenta outro builder (ex.: peças montadas em espaço local).
func append(other: MeshBuilder, xf := Transform3D.IDENTITY) -> void:
	var nb := xf.basis.inverse().transposed()
	for i in other.verts.size():
		verts.append(xf * other.verts[i])
		normals.append((nb * other.normals[i]).normalized())
	colors.append_array(other.colors)
	uvs.append_array(other.uvs)


func commit(mesh: ArrayMesh = null, material: Material = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	if plain != null and not plain.is_empty():
		plain.commit(mesh, TrackMaterials.plain())
	return mesh


## Forma de colisão com os mesmos triângulos.
func collision_shape() -> ConcavePolygonShape3D:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(verts)
	return shape
