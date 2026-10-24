class_name CandyDecor
extends RefCounted
## Enfeites de doce da pista fofa nas nuvens (Rainbow Raceway), em unidades de metro com a base em
## y = 0: árvores de pirulito e de algodão-doce, arbustos, flores, cogumelos, balas de goma, bengalas,
## casinhas de cupcake, corações de pedestal e arco-íris sólidos.
##
## Os que se repetem muito (árvores, flores, cogumelos...) vêm em partes: a parte que muda de cor por
## instância (MultiMesh com cores: a cor da instância multiplica a do vértice, branca) separada da que
## não muda (cabos, troncos, bolinhas do cogumelo). As peças únicas (casinhas, corações, arco-íris)
## são montadas direto num MeshBuilder com as cores de vértice. Tudo com o material de plástico pastel.

const STICK := Color(1.0, 0.96, 0.9)
const TRUNK := Color(0.94, 0.78, 0.66)
const LEAF_WHITE := Color(1.0, 1.0, 1.0)

static var _meshes := {}


static func material() -> Material:
	return TrackMaterials.candy_plastic("candy_decor", false, true)


static func _cached(key: String, maker: Callable) -> ArrayMesh:
	if not _meshes.has(key):
		var mb := MeshBuilder.new()
		maker.call(mb)
		_meshes[key] = mb.commit()
	return _meshes[key]


# ---------------------------------------------------------------------------
# Árvore de pirulito: cabo (fixo) e disco espiral (pela instância)
# ---------------------------------------------------------------------------
static func lollipop_stick() -> ArrayMesh:
	return _cached("lolli_stick", func(mb: MeshBuilder) -> void:
		mb.cylinder(Transform3D(), 0.07, 0.06, 2.3, STICK, 8))


## Disco de pirulito em pé (plano XY, centro a 2,3 m), espiral branca e cinza-clara (a instância pinta).
static func lollipop_disc() -> ArrayMesh:
	return _cached("lolli_disc", func(mb: MeshBuilder) -> void:
		lollipop_swirl(mb, Transform3D(Basis(), Vector3(0, 2.3, 0)), 0.75, 0.2, LEAF_WHITE, Color(0.72, 0.72, 0.74), 18, 4))


## Disco de pirulito (plano XY de `xf`, centrado), raio `r`, espessura `depth`, espiral de duas cores.
static func lollipop_swirl(mb: MeshBuilder, xf: Transform3D, r: float, depth: float, col_a: Color, col_b: Color, seg := 28,
		rings := 5) -> void:
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		for q in rings:
			var r0 := r * q / rings
			var r1 := r * (q + 1) / rings
			# Espiral: a faixa muda de cor com o ângulo + o raio
			var band := int(floor((a0 / TAU) * 2.0 + float(q) * 0.5)) % 2
			var col := col_a if band == 0 else col_b
			for face: float in [1.0, -1.0]:
				var z := Vector3(0, 0, depth * 0.5 * face)
				var p00 := Vector3(cos(a0) * r0, sin(a0) * r0, 0) + z
				var p01 := Vector3(cos(a1) * r0, sin(a1) * r0, 0) + z
				var p10 := Vector3(cos(a0) * r1, sin(a0) * r1, 0) + z
				var p11 := Vector3(cos(a1) * r1, sin(a1) * r1, 0) + z
				mb.quad(xf * p00, xf * p10, xf * p11, xf * p01, col, xf.basis * Vector3(0, 0, face))
		# Borda
		var e0 := Vector3(cos(a0) * r, sin(a0) * r, 0)
		var e1 := Vector3(cos(a1) * r, sin(a1) * r, 0)
		var zz := Vector3(0, 0, depth * 0.5)
		mb.quad(xf * (e0 + zz), xf * (e1 + zz), xf * (e1 - zz), xf * (e0 - zz), col_b.lerp(col_a, 0.5),
			xf.basis * Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0))


# ---------------------------------------------------------------------------
# Árvore de algodão-doce: tronco curvinho (fixo) e copa de bolinhas (pela instância)
# ---------------------------------------------------------------------------
static func cotton_trunk() -> ArrayMesh:
	return _cached("cotton_trunk", func(mb: MeshBuilder) -> void:
		var prev := Vector3.ZERO
		for k in range(1, 6):
			var t := k / 5.0
			var q := Vector3(sin(t * 2.2) * 0.25, t * 2.6, 0.0)
			var dir := (q - prev).normalized()
			var x := dir.cross(Vector3.FORWARD).normalized()
			mb.cylinder(Transform3D(Basis(x, dir, x.cross(dir)).orthonormalized(), prev), lerpf(0.2, 0.12, t - 0.2), lerpf(0.2, 0.12, t),
				prev.distance_to(q) + 0.03, TRUNK, 8, false)
			prev = q)


static func cotton_canopy(v: int) -> ArrayMesh:
	return _cached("cotton_canopy_%d" % v, func(mb: MeshBuilder) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 700 + v
		var top := Vector3(sin(2.2) * 0.25, 2.6, 0.0)
		mb.blob(top + Vector3(0, 0.75, 0), Vector3(1.15, 0.95, 1.15), LEAF_WHITE, 10, 6, 0.25)
		for k in 5 + v:
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.5, 0.95)
			var off := Vector3(cos(a) * r, rng.randf_range(0.1, 1.1), sin(a) * r)
			mb.blob(top + off, Vector3.ONE * rng.randf_range(0.5, 0.75), LEAF_WHITE, 7, 5, 0.25))


# ---------------------------------------------------------------------------
# Arbusto, flor, cogumelo, bala de goma, bengala
# ---------------------------------------------------------------------------
static func bush(v: int) -> ArrayMesh:
	return _cached("bush_%d" % v, func(mb: MeshBuilder) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 800 + v
		for k in 4:
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.0, 0.5)
			var rad := rng.randf_range(0.45, 0.7)
			mb.blob(Vector3(cos(a) * r, rad * 0.75, sin(a) * r), Vector3(rad, rad * 0.85, rad), LEAF_WHITE, 7, 5, 0.3))


## Flor: caule e folhinha (verdes) e as pétalas em volta do miolo (a instância pinta; o miolo fica
## mais escuro que as pétalas).
static func flower_stem() -> ArrayMesh:
	return _cached("flower_stem", func(mb: MeshBuilder) -> void:
		mb.cylinder(Transform3D(), 0.03, 0.025, 0.55, Color(0.38, 0.78, 0.42), 5, false)
		mb.blob(Vector3(0.08, 0.22, 0), Vector3(0.12, 0.04, 0.06), Color(0.42, 0.84, 0.46), 6, 3))


static func flower_head() -> ArrayMesh:
	return _cached("flower_head", func(mb: MeshBuilder) -> void:
		var c := Vector3(0, 0.58, 0)
		for k in 5:
			var a := TAU * k / 5
			mb.blob(c + Vector3(cos(a), 0.0, sin(a)) * 0.13, Vector3(0.12, 0.04, 0.12), LEAF_WHITE, 5, 3)
		mb.blob(c + Vector3(0, 0.03, 0), Vector3(0.08, 0.05, 0.08), Color(1.0, 0.86, 0.3), 5, 3))


static func mushroom_stem() -> ArrayMesh:
	return _cached("mush_stem", func(mb: MeshBuilder) -> void:
		mb.lathe(Transform3D(), PackedVector2Array([Vector2(0.28, 0.0), Vector2(0.24, 0.3), Vector2(0.2, 0.7), Vector2(0.22, 0.95),
			Vector2(0.0, 0.96)]), STICK, 12))


## Chapéu do cogumelo (a instância pinta) e as bolinhas brancas dele (fixas).
static func mushroom_cap() -> ArrayMesh:
	return _cached("mush_cap", func(mb: MeshBuilder) -> void:
		var prof := PackedVector2Array()
		for k in 9:
			var t := k / 8.0
			prof.append(Vector2(0.75 * cos(t * PI * 0.5) + 0.02, 0.9 + 0.55 * sin(t * PI * 0.5)))
		prof.insert(0, Vector2(0.18, 0.92))
		mb.lathe(Transform3D(), prof, LEAF_WHITE, 16))


static func mushroom_dots() -> ArrayMesh:
	return _cached("mush_dots", func(mb: MeshBuilder) -> void:
		for k in 7:
			var a := TAU * k / 7.0 + 0.3
			var el := 0.55 if k % 2 == 0 else 0.95
			var n := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el))
			var pos := Vector3(n.x * 0.75, 0.9 + n.y * 0.55, n.z * 0.75)
			mb.blob(pos, Vector3.ONE * 0.1, Color(1.0, 1.0, 1.0), 6, 4)
		mb.blob(Vector3(0, 1.46, 0), Vector3(0.14, 0.04, 0.14), Color(1.0, 1.0, 1.0), 6, 3))


static func gumdrop() -> ArrayMesh:
	return _cached("gumdrop", func(mb: MeshBuilder) -> void:
		var prof := PackedVector2Array()
		for k in 9:
			var t := k / 8.0
			prof.append(Vector2(0.5 * (1.0 - t * t * 0.95) * (1.0 - t * 0.1), t * 0.85))
		prof.append(Vector2(0.0, 0.88))
		mb.lathe(Transform3D(), prof, LEAF_WHITE, 14))


## Bengala de doce de pé (listras brancas e cor-de-rosa), gancho no alto.
static func candy_cane() -> ArrayMesh:
	return _cached("cane", func(mb: MeshBuilder) -> void:
		var r := 0.09
		var h := 2.0
		var stripe := 0.22
		var y := 0.0
		var k := 0
		while y < h:
			var seg := minf(stripe, h - y)
			mb.cylinder(Transform3D(Basis(), Vector3(0, y, 0)), r, r, seg, CloudLook.HOT_PINK if k % 2 == 0 else Color.WHITE, 8, false)
			y += seg
			k += 1
		var hook := 0.32
		var center := Vector3(hook, h, 0)
		var prev := Vector3(0, h, 0)
		for n in range(1, 9):
			var a := PI * n / 8.0
			var q := center + Vector3(-hook * cos(a), hook * sin(a), 0)
			var dir := (q - prev).normalized()
			var x := dir.cross(Vector3.FORWARD).normalized()
			mb.cylinder(Transform3D(Basis(x, dir, x.cross(dir)).orthonormalized(), prev), r, r, prev.distance_to(q) + 0.01,
				CloudLook.HOT_PINK if n % 2 == 0 else Color.WHITE, 8, false)
			prev = q)


# ---------------------------------------------------------------------------
# Peças únicas (montadas com as cores no vértice)
# ---------------------------------------------------------------------------
## Casinha de cupcake: forminha listrada com porta e janelas, cobertura de glacê em gomos, granulado,
## cereja e uma chaminé de bengala. `size` = raio da forminha (m).
static func cupcake_house(mb: MeshBuilder, xf: Transform3D, size: float, wrapper: Color, frosting: Color, rng: RandomNumberGenerator) -> void:
	var r := size
	var h := size * 1.25
	var sides := 16
	# Forminha (abre para cima), listras verticais alternando
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var col := wrapper if k % 2 == 0 else wrapper.lerp(Color.WHITE, 0.45)
		mb.quad(xf * (d0 * r * 0.82), xf * (d1 * r * 0.82), xf * (d1 * r + Vector3.UP * h), xf * (d0 * r + Vector3.UP * h), col,
			xf.basis * (d0 + d1))
	# Cobertura: anel gordo saindo da borda e domo de glacê em camadas
	var top := Vector3.UP * h
	mb.lathe(Transform3D(xf.basis, xf * top), PackedVector2Array([Vector2(r * 1.08, -0.1 * r), Vector2(r * 1.15, 0.12 * r),
		Vector2(r * 1.0, 0.32 * r), Vector2(r * 0.86, 0.42 * r), Vector2(r * 0.8, 0.55 * r), Vector2(r * 0.62, 0.72 * r),
		Vector2(r * 0.5, 0.8 * r), Vector2(r * 0.3, 0.98 * r), Vector2(r * 0.12, 1.12 * r), Vector2(0.0, 1.18 * r)]), frosting, 20)
	# Granulado colorido
	for k in int(18 * size):
		var a := rng.randf() * TAU
		var el := rng.randf_range(0.15, 1.2)
		var rr := r * (1.05 - el * 0.55)
		var pos := top + Vector3(cos(a) * rr, r * (0.2 + el * 0.62), sin(a) * rr)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)).normalized()
		mb.box(Transform3D(Basis.looking_at(dir), xf * pos), Vector3(0.05, 0.05, 0.22) * size, CloudLook.pick(rng, CloudLook.RAINBOW))
	# Cereja
	mb.blob(xf * (top + Vector3.UP * r * 1.32), Vector3.ONE * r * 0.2, Color(0.95, 0.12, 0.3), 10, 7)
	mb.cylinder(Transform3D(xf.basis * Basis(Vector3.FORWARD, 0.3), xf * (top + Vector3.UP * r * 1.45)), 0.03 * size, 0.02 * size,
		r * 0.3, Color(0.3, 0.6, 0.3), 5, false)
	# Porta (arco) e janelas redondas, viradas para +Z local
	var door_h := h * 0.62
	var door_w := r * 0.42
	var front := Vector3(0, 0, 1)
	# (a forminha afina para baixo: a porta acompanha a inclinação)
	var tilt := atan2(r * 0.18, h)
	var door_basis := xf.basis * Basis(Vector3.RIGHT, tilt)
	var door_poly := PackedVector2Array()
	for k in 9:
		var a := PI * k / 8.0
		door_poly.append(Vector2(cos(a) * door_w * 0.5, door_h * 0.5 + sin(a) * door_w * 0.5))
	door_poly.append(Vector2(-door_w * 0.5, -door_h * 0.42))
	door_poly.append(Vector2(door_w * 0.5, -door_h * 0.42))
	var door_xf := Transform3D(door_basis, xf * (front * (r * 0.93) + Vector3.UP * door_h * 0.45))
	CloudLook.slab(mb, door_poly, door_xf, 0.14, Color(0.62, 0.38, 0.32))
	mb.blob(door_xf * Vector3(door_w * 0.28, 0.0, 0.09), Vector3.ONE * 0.06 * size, CloudLook.BUTTER, 6, 4)
	var circle := PackedVector2Array()
	for k in 12:
		circle.append(Vector2(cos(TAU * k / 12.0), sin(TAU * k / 12.0)))
	for side: float in [-1.0, 1.0]:
		var a := side * 0.85
		var dir := Vector3(sin(a), 0, cos(a))
		var wb := xf.basis * Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, tilt)
		var wpos := xf * (dir * (r * 0.97) + Vector3.UP * h * 0.6)
		var rim := PackedVector2Array()
		var glass := PackedVector2Array()
		for q in circle:
			rim.append(q * r * 0.22)
			glass.append(q * r * 0.16)
		CloudLook.slab(mb, rim, Transform3D(wb, wpos), 0.1, Color.WHITE)
		CloudLook.slab(mb, glass, Transform3D(wb, wpos + wb.z * 0.04), 0.06, Color(1.0, 0.9, 0.55))
	# Chaminé de bengala
	var cane := candy_cane()
	var cxf := xf * Transform3D(Basis().scaled(Vector3.ONE * size * 0.5), Vector3(-r * 0.4, h + r * 0.4, -r * 0.25))
	append_mesh(mb, cane, cxf)


## Coração de pedestal (rosa com contorno branco), olhando para +Z local, de altura `size`.
static func heart_statue(mb: MeshBuilder, xf: Transform3D, size: float, color: Color) -> void:
	mb.cylinder(xf * Transform3D(Basis(), Vector3.ZERO), size * 0.3, size * 0.25, size * 0.18, CloudLook.CREAM, 12)
	mb.cylinder(xf * Transform3D(Basis(), Vector3.UP * size * 0.18), size * 0.08, size * 0.06, size * 0.3, CloudLook.CREAM, 8)
	var hxf := xf * Transform3D(Basis(), Vector3.UP * (size * 0.48 + size * 0.42))
	CloudLook.slab(mb, CloudLook.heart(size * 0.95), hxf, size * 0.24, Color.WHITE)
	CloudLook.slab(mb, CloudLook.heart(size * 0.8), Transform3D(hxf.basis, hxf.origin), size * 0.34, color)


## Arco-íris sólido (seis faixas em arco, de pé no plano XY local, pés em x = ±r), espessura `depth`;
## `stretch` estica na vertical (arco mais alto que largo).
static func rainbow_arch(mb: MeshBuilder, xf: Transform3D, r: float, band: float, depth: float, segments := 28, stretch := 1.0) -> void:
	var bands: int = CloudLook.RAINBOW.size()
	var sy := Vector3(1.0, stretch, 1.0)
	for b in bands:
		var r1 := r - b * band
		var r0 := r1 - band
		var col: Color = CloudLook.RAINBOW[b]
		for k in segments:
			var a0 := PI * k / segments
			var a1 := PI * (k + 1) / segments
			var o0 := Vector3(cos(a0), sin(a0), 0)
			var o1 := Vector3(cos(a1), sin(a1), 0)
			var zf := Vector3(0, 0, depth * 0.5)
			mb.quad(xf * (o0 * r0 * sy + zf), xf * (o1 * r0 * sy + zf), xf * (o1 * r1 * sy + zf), xf * (o0 * r1 * sy + zf), col, xf.basis.z)
			mb.quad(xf * (o0 * r0 * sy - zf), xf * (o1 * r0 * sy - zf), xf * (o1 * r1 * sy - zf), xf * (o0 * r1 * sy - zf), col, -xf.basis.z)
			if b == 0:
				mb.quad(xf * (o0 * r1 * sy + zf), xf * (o1 * r1 * sy + zf), xf * (o1 * r1 * sy - zf), xf * (o0 * r1 * sy - zf), col.darkened(0.08),
					xf.basis * (o0 + o1))
			if b == bands - 1:
				mb.quad(xf * (o0 * r0 * sy + zf), xf * (o1 * r0 * sy + zf), xf * (o1 * r0 * sy - zf), xf * (o0 * r0 * sy - zf), col.darkened(0.08),
					-(xf.basis * (o0 + o1)))


## Copia os triângulos de uma malha (com as cores do vértice) para o builder, transformados.
static func append_mesh(mb: MeshBuilder, mesh: ArrayMesh, xf: Transform3D) -> void:
	for surf in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surf)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var nb := xf.basis.inverse().transposed()
		for i in verts.size():
			mb.verts.append(xf * verts[i])
			mb.normals.append((nb * normals[i]).normalized())
			mb.colors.append(colors[i] if i < colors.size() else Color.WHITE)
			mb.uvs.append(Vector2.ZERO)
