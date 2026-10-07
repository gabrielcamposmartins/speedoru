class_name TrackHarbour
extends RefCounted
## Mar e porto de um circuito de rua (dados da TrackCity): o mar com o shader de água (plano
## subdividido perto da cidade e um anel liso até o horizonte), os pontões flutuantes, os barcos
## atracados e fundeados (iates, lanchas, veleiros e botes, MultiMesh com balanço no shader) e
## alguns barcos navegando ao largo com rastro de espuma (HarbourTraffic).

const NEAR_SIZE := 3200.0
const FAR_SIZE := 60000.0
const PONTOON := Color(0.58, 0.53, 0.46)
const PONTOON_SIDE := Color(0.3, 0.3, 0.32)
const WHITE := Color(0.96, 0.96, 0.95)
const DARK_GLASS := Color(0.1, 0.13, 0.18)
const TEAK := Color(0.62, 0.46, 0.3)
const BOTTOM := Color(0.42, 0.12, 0.12)
## Cores de casco (índice vindo dos dados).
const HULLS := [Color(0.97, 0.97, 0.96), Color(0.95, 0.95, 0.94), Color(0.1, 0.16, 0.3), Color(0.22, 0.24, 0.27),
	Color(0.06, 0.07, 0.09), Color(0.72, 0.74, 0.77)]
## Comprimentos de referência (m) dos modelos de cada tipo (super, lancha, veleiro, bote).
const VARIANTS := [[38.0, 58.0, 85.0], [12.0, 20.0], [10.0, 15.0], [7.0]]


static func build(track: RaceTrack, city: TrackCity, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Harbour"
	parent.add_child(root)
	_sea(city, root)
	_pontoons(city, root)
	_boats(city, root)
	var traffic := HarbourTraffic.new()
	traffic.name = "Traffic"
	root.add_child(traffic)
	traffic.setup(city, _boat_material())


static func _water_material(city: TrackCity, far: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/water.gdshader")
	var a: Array = city.data["area"]
	mat.set_shader_parameter("shore_tex", load("res://assets/track/monaco/monaco_shore.png"))
	mat.set_shader_parameter("shore_area", Vector4(a[0], a[1], a[2], a[3]))
	mat.set_shader_parameter("normal_a", _wave_normal(0.018, 7))
	mat.set_shader_parameter("normal_b", _wave_normal(0.05, 13))
	mat.set_shader_parameter("far_plane", far)
	return mat


static var _normals := {}


static func _wave_normal(freq: float, seed: int) -> Texture2D:
	var key := "%f_%d" % [freq, seed]
	if _normals.has(key):
		return _normals[key]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = freq
	noise.fractal_octaves = 3
	noise.seed = seed
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 4.0
	tex.generate_mipmaps = true
	tex.noise = noise
	_normals[key] = tex
	return tex


static func _sea(city: TrackCity, root: Node3D) -> void:
	var center := Vector3(city.area.get_center().x, 0.0, -city.area.get_center().y)
	var plane := PlaneMesh.new()
	plane.size = Vector2(NEAR_SIZE, NEAR_SIZE)
	plane.subdivide_width = 320
	plane.subdivide_depth = 320
	plane.material = _water_material(city, false)
	var near := MeshInstance3D.new()
	near.name = "Sea"
	near.mesh = plane
	near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	near.position = center
	root.add_child(near)
	# Anel até o horizonte (quatro retângulos em volta, sem sobrepor o plano de perto)
	var mb := MeshBuilder.new()
	var h := NEAR_SIZE * 0.5
	var f := FAR_SIZE * 0.5
	var rects := [Rect2(-f, -f, FAR_SIZE, f - h), Rect2(-f, h, FAR_SIZE, f - h), Rect2(-f, -h, f - h, NEAR_SIZE), Rect2(h, -h, f - h, NEAR_SIZE)]
	for r in rects:
		var rr: Rect2 = r
		mb.quad(Vector3(rr.position.x, 0, rr.position.y), Vector3(rr.end.x, 0, rr.position.y),
			Vector3(rr.end.x, 0, rr.end.y), Vector3(rr.position.x, 0, rr.end.y), Color.WHITE)
	var far := MeshInstance3D.new()
	far.name = "SeaFar"
	far.mesh = mb.commit(null, _water_material(city, true))
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.position = center
	root.add_child(far)


static func _pontoons(city: TrackCity, root: Node3D) -> void:
	var mb := MeshBuilder.new()
	for pr in city.data["piers"]:
		var poly := PackedVector2Array()
		if pr.has("poly"):
			var p: Array = pr["poly"]
			for i in range(0, p.size(), 2):
				poly.append(Vector2(p[i], p[i + 1]))
			_slab(mb, poly)
		else:
			var p: Array = pr["line"]
			var w: float = pr["w"] * 0.5
			for i in range(0, p.size() - 2, 2):
				var a := Vector2(p[i], p[i + 1])
				var b := Vector2(p[i + 2], p[i + 3])
				var e := (b - a).normalized()
				var n := Vector2(-e.y, e.x) * w
				_slab(mb, PackedVector2Array([a - n, b - n, b + n, a + n]))
	var mi := MeshInstance3D.new()
	mi.name = "Pontoons"
	mi.mesh = mb.commit(null, TrackMaterials.structure())
	root.add_child(mi)


## Plataforma flutuante: tampo a 0,55 m e lateral escura até a água.
static func _slab(mb: MeshBuilder, poly: PackedVector2Array) -> void:
	if Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	var tris := Geometry2D.triangulate_polygon(poly)
	for t in range(0, tris.size(), 3):
		mb.tri(TrackCity.to_world(poly[tris[t]].x, poly[tris[t]].y, 0.55), TrackCity.to_world(poly[tris[t + 1]].x, poly[tris[t + 1]].y, 0.55),
			TrackCity.to_world(poly[tris[t + 2]].x, poly[tris[t + 2]].y, 0.55), PONTOON)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := (b - a).normalized()
		mb.quad(TrackCity.to_world(a.x, a.y, -0.3), TrackCity.to_world(b.x, b.y, -0.3), TrackCity.to_world(b.x, b.y, 0.55),
			TrackCity.to_world(a.x, a.y, 0.55), PONTOON_SIDE, TrackCity.to_world(e.y, -e.x, 0.0))


static var _boat_mat: ShaderMaterial


static func _boat_material() -> ShaderMaterial:
	if _boat_mat == null:
		_boat_mat = ShaderMaterial.new()
		_boat_mat.shader = load("res://shaders/track/boat.gdshader")
	return _boat_mat


static func _boats(city: TrackCity, root: Node3D) -> void:
	var b: Array = city.data["boats"]
	# [tipo][variante] -> lista de [transform, cor]
	var groups := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	for k in range(0, b.size(), 6):
		var kind := int(b[k + 4])
		var length: float = b[k + 3]
		var variants: Array = VARIANTS[kind]
		var vi := 0
		for v in variants.size():
			if absf(variants[v] - length) < absf(variants[vi] - length):
				vi = v
		var s := length / float(variants[vi])
		var xf := Transform3D(Basis(Vector3.UP, b[k + 2]).scaled(Vector3(s, s, s)), TrackCity.to_world(b[k], b[k + 1], 0.0))
		var color: Color = HULLS[int(b[k + 5]) % HULLS.size()]
		if kind == 0 and rng.randf() < 0.6:
			color = HULLS[0]
		var amp := clampf(10.0 / length, 0.12, 1.0)
		var key := Vector2i(kind, vi)
		if not groups.has(key):
			groups[key] = []
		groups[key].append([xf, Color(color, amp)])
	for key in groups:
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = boat_mesh(key.x, VARIANTS[key.x][key.y])
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_custom_data(i, list[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Boats_%d_%d" % [key.x, key.y]
		mmi.multimesh = mm
		root.add_child(mmi)


static var _meshes := {}


## Modelo de barco (proa para +X) do tipo `kind` com comprimento `length`.
static func boat_mesh(kind: int, length: float) -> ArrayMesh:
	var key := "%d_%.0f" % [kind, length]
	if _meshes.has(key):
		return _meshes[key]
	var mb := MeshBuilder.new()
	var beam := length * (0.3 if kind == 2 else 0.19) + 1.0
	var freeboard := 0.9 + length * 0.035
	var draft := 0.5 + length * 0.02
	_hull(mb, length, beam, freeboard, draft, TEAK if kind != 0 else Color(0.9, 0.9, 0.88))
	var deck := freeboard
	match kind:
		0:
			# Superiate: três ou quatro conveses escalonados com faixas de vidro escuro
			var tiers := 3 if length < 50.0 else 4
			var tier_h := 2.8
			for t in tiers:
				var x0 := -length * (0.42 - 0.04 * t)
				var x1 := length * (0.22 - 0.08 * t)
				var w := beam * (0.86 - 0.08 * t)
				var y := deck + t * tier_h
				_tier(mb, x0, x1, w, y, tier_h)
			# Arco do radar e antenas
			var y_top := deck + tiers * tier_h
			var xr := length * (0.1 - 0.08 * tiers)
			mb.box(Transform3D(Basis(), Vector3(xr, y_top + 0.9, 0)), Vector3(1.6, 1.8, beam * 0.5), WHITE)
			mb.posts().cylinder(Transform3D(Basis(), Vector3(xr, y_top + 1.8, 0)), 0.08, 0.05, 2.6, WHITE, 5)
			mb.box(Transform3D(Basis(), Vector3(xr, y_top + 2.2, 0)), Vector3(0.4, 0.15, 2.6), Color(0.85, 0.85, 0.85))
		1:
			# Lancha: cabine com para-brisa escuro e capota
			_tier(mb, -length * 0.25, length * 0.12, beam * 0.78, deck, 1.9)
			mb.box(Transform3D(Basis(), Vector3(-length * 0.1, deck + 2.0, 0)), Vector3(length * 0.32, 0.12, beam * 0.7), WHITE)
		2:
			# Veleiro: cabine baixa, mastro alto, retranca e vela enrolada
			_tier(mb, -length * 0.15, length * 0.12, beam * 0.55, deck, 0.9)
			var mast_h := length * 1.25
			mb.posts().cylinder(Transform3D(Basis(), Vector3(length * 0.1, deck, 0)), 0.1, 0.07, mast_h, Color(0.85, 0.86, 0.88), 6)
			mb.posts().cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(length * 0.1, deck + 1.6, 0)), 0.07, 0.07,
				length * 0.42, Color(0.75, 0.76, 0.78), 5, false)
			mb.posts().cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(length * 0.08, deck + 1.85, 0)), 0.26, 0.2,
				length * 0.4, Color(0.2, 0.3, 0.55), 6, false)
			# Estai: da proa ao topo do mastro
			var stay := Vector2(length * 0.1 - length * 0.48, mast_h)
			mb.posts().cylinder(Transform3D(Basis(Vector3.BACK, atan2(-stay.x, stay.y)), Vector3(length * 0.48, deck, 0)), 0.03, 0.03,
				stay.length(), Color(0.6, 0.6, 0.6), 3, false)
		3:
			# Bote: console e motor de popa
			mb.box(Transform3D(Basis(), Vector3(0.0, deck + 0.5, 0)), Vector3(0.9, 1.0, 0.8), WHITE)
			mb.box(Transform3D(Basis(), Vector3(-length * 0.5 - 0.2, deck * 0.6, 0)), Vector3(0.5, 1.0, 0.45), Color(0.15, 0.15, 0.17))
	var mesh := mb.commit(null, _boat_material())
	_meshes[key] = mesh
	return mesh


## Convés escalonado: base branca, faixa de vidro escuro e laje com beiral.
static func _tier(mb: MeshBuilder, x0: float, x1: float, w: float, y: float, h: float) -> void:
	var seg_len := x1 - x0
	var cx := (x0 + x1) * 0.5
	mb.box(Transform3D(Basis(), Vector3(cx, y + h * 0.15, 0)), Vector3(seg_len, h * 0.3, w), WHITE)
	mb.box(Transform3D(Basis(), Vector3(cx - 0.05, y + h * 0.55, 0)), Vector3(seg_len - 0.3, h * 0.5, w - 0.2), DARK_GLASS)
	mb.box(Transform3D(Basis(), Vector3(cx + 0.3, y + h * 0.9, 0)), Vector3(seg_len + 1.0, h * 0.2, w + 0.3), WHITE)
	# Frente inclinada (para-brisa)
	var fx := x1
	mb.quad(Vector3(fx, y + h * 0.3, -w * 0.5 + 0.1), Vector3(fx, y + h * 0.3, w * 0.5 - 0.1),
		Vector3(fx - h * 0.45, y + h * 0.8, w * 0.5 - 0.1), Vector3(fx - h * 0.45, y + h * 0.8, -w * 0.5 + 0.1), DARK_GLASS, Vector3(1, 0.7, 0))


## Casco: seções da popa (x = -L/2) à proa (x = +L/2); borda livre sobe para a proa.
## COLOR.a = 0 nas laterais (cor do casco por instância).
static func _hull(mb: MeshBuilder, length: float, beam: float, freeboard: float, draft: float, deck_color: Color) -> void:
	var stations := 12
	var top := []
	var chine := []
	var keel := []
	for k in stations + 1:
		var u := float(k) / stations
		var x := -length * 0.5 + u * length
		var w := beam * 0.5 * (0.9 + 0.1 * u / 0.6 if u < 0.6 else sqrt(maxf(1.0 - pow((u - 0.6) / 0.4, 2.0), 0.0)))
		var y_top := freeboard * (1.0 + 0.3 * u * u)
		var y_keel := -draft * (1.0 - 0.75 * pow(u, 3.0))
		top.append(Vector3(x, y_top, w))
		chine.append(Vector3(x, -draft * 0.25, w * 0.82))
		keel.append(Vector3(x, y_keel, 0.0))
	var hull_mark := Color(1, 1, 1, 0)
	for k in stations:
		for side: float in [1.0, -1.0]:
			var m := Vector3(1, 1, side)
			var t0: Vector3 = top[k] * m
			var t1: Vector3 = top[k + 1] * m
			var c0: Vector3 = chine[k] * m
			var c1: Vector3 = chine[k + 1] * m
			var k0: Vector3 = keel[k]
			var k1: Vector3 = keel[k + 1]
			var out := Vector3(0, 0, side)
			mb.quad(c0, c1, t1, t0, hull_mark, out)
			mb.quad(k0, k1, c1, c0, BOTTOM, out + Vector3.DOWN)
		# Convés
		mb.quad(top[k] * Vector3(1, 1, -1), top[k + 1] * Vector3(1, 1, -1), top[k + 1], top[k], deck_color)
	# Espelho de popa
	var t0: Vector3 = top[0]
	var c0: Vector3 = chine[0]
	var k0: Vector3 = keel[0]
	var back := Vector3.LEFT
	mb.quad(c0 * Vector3(1, 1, -1), c0, t0, t0 * Vector3(1, 1, -1), hull_mark, back)
	mb.tri(k0, c0, c0 * Vector3(1, 1, -1), BOTTOM, back)
	# Faixa escura na linha d'água e frisos
	for k in stations:
		for side: float in [1.0, -1.0]:
			var m := Vector3(1, 1, side)
			var a: Vector3 = top[k] * m
			var b: Vector3 = top[k + 1] * m
			mb.quad(a + Vector3(0, -0.35, 0.01 * side), b + Vector3(0, -0.35, 0.01 * side), b + Vector3(0, -0.2, 0.01 * side),
				a + Vector3(0, -0.2, 0.01 * side), Color(0.12, 0.13, 0.16), Vector3(0, 0, side))


## Barcos navegando ao largo, com rastro de espuma. As rotas são elipses no mar aberto, longe
## da costa (conferidas na textura da costa).
class HarbourTraffic:
	extends Node3D

	var _routes: Array = []  # [centro (x, z), raios, velocidade angular, fase]
	var _mm: MultiMesh
	var _wake_mm: MultiMesh
	var _t := 0.0

	func setup(city: TrackCity, material: Material) -> void:
		var img: Image = (load("res://assets/track/monaco/monaco_shore.png") as Texture2D).get_image()
		var a: Array = city.data["area"]
		var rng := RandomNumberGenerator.new()
		rng.seed = 2718
		var tries := 0
		while _routes.size() < 4 and tries < 400:
			tries += 1
			var c := Vector2(rng.randf_range(a[0], a[2]), rng.randf_range(a[1], a[3]))
			var r := Vector2(rng.randf_range(70.0, 220.0), rng.randf_range(60.0, 160.0))
			if _route_ok(img, a, c, r):
				var speed := rng.randf_range(7.0, 13.0)
				_routes.append([c, r, speed / ((r.x + r.y) * 0.5) * (1.0 if rng.randf() < 0.5 else -1.0), rng.randf() * TAU])
		_mm = MultiMesh.new()
		_mm.transform_format = MultiMesh.TRANSFORM_3D
		_mm.use_custom_data = true
		_mm.mesh = TrackHarbour.boat_mesh(1, 12.0)
		_mm.instance_count = _routes.size()
		for i in _routes.size():
			_mm.set_instance_custom_data(i, Color(HULLS[i % 2], 0.25))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = _mm
		add_child(mmi)
		_wake_mm = MultiMesh.new()
		_wake_mm.transform_format = MultiMesh.TRANSFORM_3D
		_wake_mm.mesh = _wake_mesh()
		_wake_mm.instance_count = _routes.size()
		var wake := MultiMeshInstance3D.new()
		wake.multimesh = _wake_mm
		wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wake)
		_update()

	static func _route_ok(img: Image, a: Array, c: Vector2, r: Vector2) -> bool:
		for k in 24:
			var ang := TAU * k / 24.0
			var p := c + Vector2(cos(ang) * r.x, sin(ang) * r.y)
			var px := int((p.x - float(a[0])) / 2.0)
			var py := int((float(a[3]) - p.y) / 2.0)
			if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
				return false
			var pix := img.get_pixel(px, py)
			if pix.r < 0.99 or pix.g > 0.05:
				return false  # perto da costa ou dentro do porto
		return true

	func _process(delta: float) -> void:
		_t += delta
		_update()

	func _update() -> void:
		for i in _routes.size():
			var rt: Array = _routes[i]
			var c: Vector2 = rt[0]
			var r: Vector2 = rt[1]
			var ang: float = rt[3] + _t * rt[2]
			var p := c + Vector2(cos(ang) * r.x, sin(ang) * r.y)
			var v := Vector2(-sin(ang) * r.x, cos(ang) * r.y) * signf(rt[2])
			var heading := atan2(v.y, v.x)
			var xf := Transform3D(Basis(Vector3.UP, heading), TrackCity.to_world(p.x, p.y, 0.15))
			_mm.set_instance_transform(i, xf)
			_wake_mm.set_instance_transform(i, xf)

	static func _wake_mesh() -> ArrayMesh:
		# Dois braços em V atrás da popa (-X) e a esteira central, esmaecendo
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segs := 10
		for side: float in [1.0, -1.0, 0.0]:
			for k in segs:
				var u0 := float(k) / segs
				var u1 := float(k + 1) / segs
				var seg_len := 70.0
				var spread := 0.32 if side != 0.0 else 0.0
				var w0 := 0.8 + u0 * (3.5 if side == 0.0 else 2.0)
				var w1 := 0.8 + u1 * (3.5 if side == 0.0 else 2.0)
				var p0 := Vector3(-6.0 - u0 * seg_len, 0.0, side * u0 * seg_len * spread)
				var p1 := Vector3(-6.0 - u1 * seg_len, 0.0, side * u1 * seg_len * spread)
				var a0 := Color(1, 1, 1, (1.0 - u0) * 0.75)
				var a1 := Color(1, 1, 1, (1.0 - u1) * 0.75)
				var n0 := Vector3(0, 0, w0 * 0.5)
				var n1 := Vector3(0, 0, w1 * 0.5)
				for v in [[p0 - n0, a0], [p1 - n1, a1], [p1 + n1, a1], [p0 - n0, a0], [p1 + n1, a1], [p0 + n0, a0]]:
					st.set_color(v[1])
					st.set_normal(Vector3.UP)
					st.add_vertex(v[0])
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mesh := st.commit()
		mesh.surface_set_material(0, mat)
		return mesh
