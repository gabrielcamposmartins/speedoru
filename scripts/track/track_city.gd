class_name TrackCity
extends RefCounted
## Cidade de um circuito de rua, lida dos dados gerados por tools/build_monaco.py (OpenStreetMap):
##
## * Terreno: grade de alturas (encosta, nível da pista, cais) em pedaços, com cor por uso do solo
##   (calçada, parques, encosta); colisão só perto da pista. Sobre o túnel o chão fica no teto dele.
## * Cais: muros de pedra no contorno do mar, com a faixa de calçada em cima.
## * Ruas da cidade (fitas de asfalto/pedra sobre o terreno) e piscinas.
## * Prédios: extrusão das plantas do OSM com fachadas coloridas, janelas (shader city_building),
##   mansardas, telhados de telha, equipamentos no telhado e acabamento dos marcos (Casino).
## * Árvores e palmeiras (MultiMesh).
##
## Coordenadas dos dados: x = leste, y = norte (m); no Godot (x, altura, -y), como no TrackPath.

const PAVEMENT := Color(0.71, 0.68, 0.62)
const SIDEWALK := Color(0.76, 0.74, 0.7)
const UNDER_ROAD := Color(0.2, 0.2, 0.22)
const GRASS := Color(0.36, 0.56, 0.24)
const GARDEN := Color(0.27, 0.47, 0.2)
const SLOPE := Color(0.62, 0.56, 0.46)
const QUAY_STONE := Color(0.66, 0.63, 0.57)
const QUAY_WET := Color(0.36, 0.36, 0.33)
const STREET := Color(0.25, 0.25, 0.28)
const PEDESTRIAN := Color(0.78, 0.74, 0.66)
const ROOF_FLAT := Color(0.6, 0.59, 0.57)
const ROOF_TILE := Color(0.72, 0.36, 0.24)
const ZINC := Color(0.36, 0.39, 0.45)
const COPPER := Color(0.42, 0.62, 0.53)
const SEA_FLOOR := -7.0
## Tamanho (em células da grade) de cada pedaço do terreno.
const CHUNK := 48
## Andar e vão das janelas (iguais aos do shader).
const FLOOR_H := 3.3
const BAY_W := 3.2

var area: Rect2
var cell := 4.0
var nx := 0
var ny := 0
var heights := PackedFloat32Array()
var cls := PackedByteArray()
var cover := PackedByteArray()
var tunnel := Vector2.ZERO
var tunnel_roof := 8.5
var data: Dictionary


static func load_city(path: String) -> TrackCity:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("TrackCity: não foi possível ler %s" % path)
		return null
	var c := TrackCity.new()
	c.data = parsed
	var a: Array = c.data["area"]
	c.area = Rect2(a[0], a[1], a[2] - a[0], a[3] - a[1])
	c.cell = c.data["cell"]
	c.nx = int(c.data["nx"])
	c.ny = int(c.data["ny"])
	var count := c.nx * c.ny
	var raw := _unpack(c.data["height_cm"], count * 2)
	c.heights.resize(count)
	for i in count:
		c.heights[i] = raw.decode_s16(i * 2) * 0.01
	c.cls = _unpack(c.data["cls"], count)
	c.cover = _unpack(c.data["cover"], count)
	var t: Array = c.data["tunnel"]
	c.tunnel = Vector2(t[0], t[1])
	c.tunnel_roof = c.data.get("tunnel_roof", 8.5)
	return c


static func _unpack(b64: String, size: int) -> PackedByteArray:
	return Marshalls.base64_to_raw(b64).decompress(size, FileAccess.COMPRESSION_DEFLATE)


## As cores da cidade são escritas em sRGB (como nos mapas); os shaders usam a cor de vértice
## como albedo linear.
static func lin(c: Color) -> Color:
	var l := c.srgb_to_linear()
	return Color(l.r, l.g, l.b, c.a)


static func to_world(x: float, y: float, h: float) -> Vector3:
	return Vector3(x, h, -y)


## Altura do chão em (x, z) do Godot (bilinear na grade).
func height_at(x: float, z: float) -> float:
	var fx := clampf((x - area.position.x) / cell, 0.0, nx - 1.001)
	var fy := clampf((-z - area.position.y) / cell, 0.0, ny - 1.001)
	var ix := int(fx)
	var iy := int(fy)
	var tx := fx - ix
	var ty := fy - iy
	var i := iy * nx + ix
	return lerpf(lerpf(heights[i], heights[i + 1], tx), lerpf(heights[i + nx], heights[i + nx + 1], tx), ty)


func in_tunnel(s: float, margin := 0.0) -> bool:
	return s >= tunnel.x - margin and s <= tunnel.y + margin


func _vertex(ix: int, iy: int) -> Vector3:
	return to_world(area.position.x + ix * cell, area.position.y + iy * cell, heights[iy * nx + ix])


# ---------------------------------------------------------------------------
# Terreno, cais, ruas e piscinas
# ---------------------------------------------------------------------------
static func build_ground(track: RaceTrack, city: TrackCity, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "City"
	parent.add_child(root)
	city._terrain(root, not RaceTrack.server_mode)
	if RaceTrack.server_mode:
		return
	city._quays(root)
	city._streets(root)
	city._pools(root)


func _ground_color(i: int, n: Vector3, rng: RandomNumberGenerator) -> Color:
	var c := PAVEMENT
	match cls[i]:
		1:
			return lin(UNDER_ROAD)
		4:
			return lin(SIDEWALK)
		2, 3:
			c = GARDEN
	if cover[i] == 1:
		c = GRASS.lerp(GARDEN, rng.randf())
	elif heights[i] > 30.0 and cls[i] == 0:
		# Encosta alta: jardins e terraços misturados com a calçada
		c = PAVEMENT.lerp(GARDEN, clampf((heights[i] - 30.0) / 60.0, 0.0, 0.55) * rng.randf_range(0.6, 1.0))
	if n.y < 0.75:
		c = c.lerp(SLOPE, clampf((0.75 - n.y) / 0.35, 0.0, 0.8))
	return lin(c * rng.randf_range(0.96, 1.04))


func _terrain(root: Node3D, visual: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var normals := PackedVector3Array()
	normals.resize(nx * ny)
	for iy in ny:
		for ix in nx:
			var hl := heights[iy * nx + maxi(ix - 1, 0)]
			var hr := heights[iy * nx + mini(ix + 1, nx - 1)]
			var hd := heights[maxi(iy - 1, 0) * nx + ix]
			var hu := heights[mini(iy + 1, ny - 1) * nx + ix]
			# y do dado = -z do Godot
			normals[iy * nx + ix] = Vector3(hl - hr, 2.0 * cell, hu - hd).normalized()
	var col_faces := PackedVector3Array()
	var mat := TrackMaterials.building("city_ground", false, {"ground_dirt": 0.0, "grime_strength": 0.25})
	for cy in range(0, ny - 1, CHUNK):
		for cx in range(0, nx - 1, CHUNK):
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var colors := PackedColorArray()
			var index := PackedInt32Array()
			var remap := {}
			var x1 := mini(cx + CHUNK, nx - 1)
			var y1 := mini(cy + CHUNK, ny - 1)
			for iy in range(cy, y1):
				for ix in range(cx, x1):
					var q := [iy * nx + ix, iy * nx + ix + 1, (iy + 1) * nx + ix + 1, (iy + 1) * nx + ix]
					var skip := false
					var wet := 0
					var near := false
					for v in q:
						if cls[v] == 2:
							skip = true
						if heights[v] < -0.3:
							wet += 1
						if cls[v] != 0:
							near = true
					if skip or wet == 4:
						continue
					# Colisão perto da pista (o carro só chega lá se passar pela barreira)
					if near:
						var a := _vertex(ix, iy)
						var b := _vertex(ix + 1, iy)
						var c := _vertex(ix + 1, iy + 1)
						var d := _vertex(ix, iy + 1)
						col_faces.append_array([a, c, b, a, d, c])
					if not visual:
						continue
					for v in q:
						if not remap.has(v):
							remap[v] = verts.size()
							verts.append(_vertex(v % nx, v / nx))
							norms.append(normals[v])
							colors.append(_ground_color(v, normals[v], rng))
					# Com a frente para cima (y do dado cresce para -z)
					index.append_array([remap[q[0]], remap[q[2]], remap[q[1]], remap[q[0]], remap[q[3]], remap[q[2]]])
			if verts.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = colors
			arrays[Mesh.ARRAY_INDEX] = index
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, mat)
			var mi := MeshInstance3D.new()
			mi.name = "Ground_%d_%d" % [cx, cy]
			mi.mesh = mesh
			root.add_child(mi)
	if not col_faces.is_empty():
		var body := TrackSurface.make_body("GroundCollision", TrackSurface.Type.ASPHALT)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(col_faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)


func _quays(root: Node3D) -> void:
	var q: Array = data["quays"]
	var mb := MeshBuilder.new()
	for k in range(0, q.size(), 7):
		var a := Vector2(q[k], q[k + 1])
		var b := Vector2(q[k + 2], q[k + 3])
		var n := Vector2(q[k + 4], q[k + 5])  # para a terra
		var top: float = q[k + 6]
		var out := to_world(-n.x, 0.0, -n.y)  # normal do muro: para o mar
		var a0 := to_world(a.x, a.y, SEA_FLOOR)
		var b0 := to_world(b.x, b.y, SEA_FLOOR)
		var aw := to_world(a.x, a.y, 0.5)
		var bw := to_world(b.x, b.y, 0.5)
		var at := to_world(a.x, a.y, top)
		var bt := to_world(b.x, b.y, top)
		mb.quad(a0, b0, bw, aw, lin(QUAY_WET), out)
		mb.quad(aw, bw, bt, at, lin(QUAY_STONE), out)
		# Calçada do cais
		var ai := to_world(a.x + n.x * 7.0, a.y + n.y * 7.0, top)
		var bi := to_world(b.x + n.x * 7.0, b.y + n.y * 7.0, top)
		mb.quad(at, bt, bi, ai, lin(SIDEWALK))
	var mi := MeshInstance3D.new()
	mi.name = "Quays"
	mi.mesh = mb.commit(null, TrackMaterials.building("city_quay", false, {"panel_size": 1.2, "ground_dirt": 0.0}))
	root.add_child(mi)


func _streets(root: Node3D) -> void:
	var mb := MeshBuilder.new()
	for st in data["streets"]:
		var p: Array = st["p"]
		var w: float = st["w"] * 0.5
		var color := lin(PEDESTRIAN if int(st["k"]) == 1 else STREET)
		var count := p.size() / 3
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for i in count:
			var c := to_world(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
			var j0 := maxi(i - 1, 0)
			var j1 := mini(i + 1, count - 1)
			var dir := to_world(p[j1 * 3], p[j1 * 3 + 1], 0.0) - to_world(p[j0 * 3], p[j0 * 3 + 1], 0.0)
			var left := Vector3(dir.z, 0.0, -dir.x).normalized()
			var l := c + left * w
			var r := c - left * w
			if i > 0:
				mb.quad(prev_r, r, l, prev_l, color)
			prev_l = l
			prev_r = r
	var mi := MeshInstance3D.new()
	mi.name = "Streets"
	mi.mesh = mb.commit(null, TrackMaterials.surface("asphalt"))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _pools(root: Node3D) -> void:
	var water := MeshBuilder.new()
	var rim := MeshBuilder.new()
	for pool in data["pools"]:
		var p: Array = pool["p"]
		var z: float = pool["z"]
		var poly := PackedVector2Array()
		for i in range(0, p.size(), 2):
			poly.append(Vector2(p[i], p[i + 1]))
		var tris := Geometry2D.triangulate_polygon(poly)
		for t in range(0, tris.size(), 3):
			water.tri(to_world(poly[tris[t]].x, poly[tris[t]].y, z - 0.25), to_world(poly[tris[t + 1]].x, poly[tris[t + 1]].y, z - 0.25),
				to_world(poly[tris[t + 2]].x, poly[tris[t + 2]].y, z - 0.25), Color.WHITE)
		# Borda de pedra clara e parede interna
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var e := (b - a).normalized()
			var out := Vector2(e.y, -e.x)  # anti-horário: lado de fora à direita
			rim.quad(to_world(a.x, a.y, z + 0.05), to_world(b.x, b.y, z + 0.05),
				to_world(b.x + out.x * 0.8, b.y + out.y * 0.8, z + 0.05), to_world(a.x + out.x * 0.8, a.y + out.y * 0.8, z + 0.05),
				Color(0.92, 0.92, 0.9))
			rim.quad(to_world(a.x, a.y, z - 0.25), to_world(b.x, b.y, z - 0.25), to_world(b.x, b.y, z + 0.05),
				to_world(a.x, a.y, z + 0.05), Color(0.85, 0.9, 0.92), to_world(-out.x, -out.y, 0.0))
	var mi := MeshInstance3D.new()
	mi.name = "Pools"
	mi.mesh = water.commit(null, _pool_material())
	rim.commit(mi.mesh as ArrayMesh, TrackMaterials.structure())
	root.add_child(mi)


static func _pool_material() -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.72, 0.85)
	mat.roughness = 0.0  # sem contorno anime
	mat.metallic_specular = 0.8
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.25, 0.3)
	return mat


# ---------------------------------------------------------------------------
# Prédios
# ---------------------------------------------------------------------------
class Arrays:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()

	## Quad a-b-c-d (anti-horário visto de fora), uv em metros e uv2 = (vão útil, altura da parede).
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color: Color,
			ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, u2: Vector2) -> void:
		color = TrackCity.lin(color)
		verts.append_array([a, c, b, a, d, c])
		for i in 6:
			normals.append(n)
			colors.append(color)
			uv2.append(u2)
		uv.append_array([ua, uc, ub, ua, ud, uc])

	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color) -> void:
		color = TrackCity.lin(color)
		# Ordem horária vista de fora (frente no Godot)
		if (b - a).cross(c - a).dot(n) > 0.0:
			verts.append_array([a, c, b])
		else:
			verts.append_array([a, b, c])
		for i in 3:
			normals.append(n)
			colors.append(color)
			uv.append(Vector2.ZERO)
			uv2.append(Vector2.ZERO)

	func commit(material: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		return mesh


## Estilos de fachada (alfa da cor de vértice, lido pelo shader).
const STYLE_CLASSIC := 0.1   # janelas com venezianas
const STYLE_MODERN := 0.45   # faixas de varandas e vidro
const STYLE_PLAIN := 0.75    # janelas simples
const STYLE_NONE := 1.0      # telhados, sem janelas


static func build_buildings(track: RaceTrack, city: TrackCity, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Buildings"
	parent.add_child(root)
	var palette: Array = city.data["facades"]
	var chunks := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for b in city.data["buildings"]:
		var p: Array = b["p"]
		var poly := PackedVector2Array()
		for i in range(0, p.size(), 2):
			poly.append(Vector2(p[i], p[i + 1]))
		var center := Vector2.ZERO
		for v in poly:
			center += v
		center /= poly.size()
		var key := Vector2i(floori(center.x / 300.0), floori(center.y / 300.0))
		if not chunks.has(key):
			chunks[key] = Arrays.new()
		var color := Color(String(palette[int(b["c"]) % palette.size()]))
		var top: float = b["t"]
		var base: float = b["b"]
		var height := top - base
		var style := STYLE_CLASSIC if height < 26.0 and rng.randf() < 0.6 else (STYLE_MODERN if height > 18.0 else STYLE_PLAIN)
		if rng.randf() < 0.12:
			style = STYLE_PLAIN
		var lm: String = b.get("lm", "")
		if lm != "":
			style = STYLE_CLASSIC
			color = Color("f2e2bf") if lm == "casino" else Color("efe3cc")
		var mansard := lm != "" or (style == STYLE_CLASSIC and height > 13.0 and rng.randf() < 0.55)
		_building(chunks[key], poly, base, top, color, style, int(b["r"]), mansard, lm, rng, track)
	var mat := _building_material()
	for key in chunks:
		var arr: Arrays = chunks[key]
		if arr.verts.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Block_%d_%d" % [key.x, key.y]
		mi.mesh = arr.commit(mat)
		root.add_child(mi)


static var _bmat: ShaderMaterial


## Noite (0..1): acende parte das janelas.
static func set_night(amount: float) -> void:
	if _bmat:
		_bmat.set_shader_parameter("night", amount)


static func _building_material() -> Material:
	if _bmat:
		return _bmat
	var mat := ShaderMaterial.new()
	_bmat = mat
	mat.shader = load("res://shaders/track/city_building.gdshader")
	mat.set_shader_parameter("detail_tex", load(TrackMaterials.TEXTURE_DIR + "material_detail.png"))
	mat.set_shader_parameter("grime_tex", load(TrackMaterials.TEXTURE_DIR + "grime.png"))
	mat.set_shader_parameter("normal_tex", load(TrackMaterials.TEXTURE_DIR + "deform_normal.png"))
	return mat


## Paredes de um prisma (polígono anti-horário) de y0 a y1, com UV de janelas.
static func _walls(arr: Arrays, poly: PackedVector2Array, y0: float, y1: float, color: Color, style: float, wall_base := -1e9) -> void:
	var n := poly.size()
	var base_ref := y0 if wall_base < -1e8 else wall_base
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var length := a.distance_to(b)
		if length < 0.05:
			continue
		var e := (b - a) / length
		var out := to_world(e.y, -e.x, 0.0)  # anti-horário: fora à direita
		# Janelas centradas na parede: u vai de -folga até o vão útil
		var bays := floorf(length / BAY_W)
		var usable := bays * BAY_W
		var u0 := -(length - usable) * 0.5
		var u2 := Vector2(usable, y1 - base_ref)
		arr.quad(to_world(a.x, a.y, y0), to_world(b.x, b.y, y0), to_world(b.x, b.y, y1), to_world(a.x, a.y, y1), out,
			Color(color, style), Vector2(u0, y0 - base_ref), Vector2(u0 + length, y0 - base_ref),
			Vector2(u0 + length, y1 - base_ref), Vector2(u0, y1 - base_ref), u2)


static func _roof(arr: Arrays, poly: PackedVector2Array, y: float, color: Color) -> bool:
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		return false
	for t in range(0, tris.size(), 3):
		arr.tri(to_world(poly[tris[t]].x, poly[tris[t]].y, y), to_world(poly[tris[t + 1]].x, poly[tris[t + 1]].y, y),
			to_world(poly[tris[t + 2]].x, poly[tris[t + 2]].y, y), Vector3.UP, Color(color, STYLE_NONE))
	return true


static func _is_convex(poly: PackedVector2Array) -> bool:
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var c := poly[(i + 2) % n]
		if (b - a).cross(c - b) < -1e-4:
			return false
	return true


static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		s += poly[i].cross(poly[(i + 1) % poly.size()])
	return s * 0.5


static func _building(arr: Arrays, poly: PackedVector2Array, base: float, top: float, color: Color, style: float,
		roof_kind: int, mansard: bool, lm: String, rng: RandomNumberGenerator, track: RaceTrack) -> void:
	var area := _area(poly)
	var wall_top := top
	var inner: Array = []
	if mansard:
		inner = Geometry2D.offset_polygon(poly, -1.6, Geometry2D.JOIN_MITER)
		if inner.is_empty():
			mansard = false
		else:
			wall_top = top - 3.6
	_walls(arr, poly, base, wall_top, color, style)
	if mansard:
		var roof_color := COPPER if lm == "casino" else ZINC
		_roof(arr, poly, wall_top, ROOF_FLAT)
		for ip in inner:
			var ipoly: PackedVector2Array = ip
			if Geometry2D.is_polygon_clockwise(ipoly):
				ipoly.reverse()
			# Mansarda: parede mais escura com lucarnas (estilo "simples" mais estreito)
			_walls(arr, ipoly, wall_top, top, roof_color, STYLE_PLAIN, wall_top - 1.0)
			_roof(arr, ipoly, top, roof_color.darkened(0.15))
	elif roof_kind == 1 and _is_convex(poly) and area < 900.0:
		# Telhado de telha em pirâmide baixa
		var c := Vector2.ZERO
		for v in poly:
			c += v
		c /= poly.size()
		var peak := to_world(c.x, c.y, top + clampf(sqrt(area) * 0.18, 1.0, 3.5))
		for i in poly.size():
			var a := to_world(poly[i].x, poly[i].y, top)
			var b := to_world(poly[(i + 1) % poly.size()].x, poly[(i + 1) % poly.size()].y, top)
			var nrm := (b - a).cross(peak - a).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			arr.tri(a, b, peak, nrm, Color(ROOF_TILE * rng.randf_range(0.9, 1.08), STYLE_NONE))
	else:
		_roof(arr, poly, top, ROOF_FLAT * rng.randf_range(0.92, 1.06))
		# Equipamentos no telhado (casa de máquinas, ar-condicionado)
		if area > 250.0:
			for k in rng.randi_range(1, 3):
				var c := poly[rng.randi() % poly.size()].lerp(_centroid(poly), rng.randf_range(0.45, 0.8))
				if Geometry2D.is_point_in_polygon(c, poly):
					var size := Vector2(rng.randf_range(2.0, 5.0), rng.randf_range(2.0, 4.0))
					var h := rng.randf_range(1.2, 3.0)
					var box := PackedVector2Array([c + Vector2(-size.x, -size.y) * 0.5, c + Vector2(size.x, -size.y) * 0.5,
						c + Vector2(size.x, size.y) * 0.5, c + Vector2(-size.x, size.y) * 0.5])
					_walls(arr, box, top, top + h, Color(0.78, 0.78, 0.76), STYLE_NONE)
					_roof(arr, box, top + h, Color(0.7, 0.7, 0.68))
	if lm == "casino":
		_casino(arr, poly, base, top, color, track)


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for v in poly:
		c += v
	return c / poly.size()


## Casino de Monte-Carlo: duas torres com cúpulas de cobre do lado da praça e uma cúpula central.
static func _casino(arr: Arrays, poly: PackedVector2Array, base: float, top: float, color: Color, track: RaceTrack) -> void:
	# Os dois vértices mais próximos da pista (fachada da praça)
	var best: Array = []
	for v in poly:
		var pr := track.path.project(to_world(v.x, v.y, top))
		best.append([absf(pr.y), v])
	best.sort_custom(func(a, b): return a[0] < b[0])
	var used: Array[Vector2] = []
	for item in best:
		var v: Vector2 = item[1]
		var far := true
		for u in used:
			if u.distance_to(v) < 25.0:
				far = false
		if far:
			used.append(v)
		if used.size() == 2:
			break
	var c := _centroid(poly)
	for v in used:
		var t := v.lerp(c, 0.12)
		var sq := PackedVector2Array([t + Vector2(-3.5, -3.5), t + Vector2(3.5, -3.5), t + Vector2(3.5, 3.5), t + Vector2(-3.5, 3.5)])
		_walls(arr, sq, base, top + 7.0, color, STYLE_CLASSIC)
		_dome(arr, to_world(t.x, t.y, top + 7.0), 3.8, 6.0, COPPER)
	_dome(arr, to_world(c.x, c.y, top - 1.0), 7.0, 6.5, COPPER)


static func _dome(arr: Arrays, center: Vector3, radius: float, height: float, color: Color) -> void:
	var seg := 12
	var rings := 4
	for r in rings:
		var a0 := PI * 0.5 * r / rings
		var a1 := PI * 0.5 * (r + 1) / rings
		for k in seg:
			var t0 := TAU * k / seg
			var t1 := TAU * (k + 1) / seg
			var p := [
				center + Vector3(cos(t0) * cos(a0) * radius, sin(a0) * height, sin(t0) * cos(a0) * radius),
				center + Vector3(cos(t1) * cos(a0) * radius, sin(a0) * height, sin(t1) * cos(a0) * radius),
				center + Vector3(cos(t1) * cos(a1) * radius, sin(a1) * height, sin(t1) * cos(a1) * radius),
				center + Vector3(cos(t0) * cos(a1) * radius, sin(a1) * height, sin(t0) * cos(a1) * radius),
			]
			var n: Vector3 = ((p[0] + p[2]) * 0.5 - center).normalized()
			arr.tri(p[0], p[1], p[2], n, Color(color, STYLE_NONE))
			if r < rings - 1:
				arr.tri(p[0], p[2], p[3], n, Color(color, STYLE_NONE))


# ---------------------------------------------------------------------------
# Árvores e palmeiras
# ---------------------------------------------------------------------------
static func build_trees(track: RaceTrack, city: TrackCity, parent: Node3D) -> void:
	var t: Array = city.data["trees"]
	var xfs: Array = [[], []]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for k in range(0, t.size(), 4):
		var kind := int(t[k + 3])
		var s := rng.randf_range(0.8, 1.25)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
		xfs[kind].append(Transform3D(basis, to_world(t[k], t[k + 1], t[k + 2] - 0.2)))
	var meshes := [_round_tree_mesh(DaylightPresets.Biome.SUMMER), _palm_mesh(DaylightPresets.Biome.SUMMER)]
	var names := ["Trees", "Palms"]
	for kind in 2:
		if xfs[kind].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[kind]
		mm.instance_count = xfs[kind].size()
		for i in xfs[kind].size():
			mm.set_instance_transform(i, xfs[kind][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = names[kind]
		mmi.multimesh = mm
		mmi.add_to_group("city_trees")
		mmi.set_meta("kind", kind)
		parent.add_child(mmi)


## Copas no tema do ambiente (outono laranja, sakura rosa, fantasia roxa); chamado pelo RaceTrack
## quando o ambiente muda. As palmeiras só puxam um pouco para a cor do tema.
static func apply_biome(root: Node, biome: int) -> void:
	for mmi in root.get_tree().get_nodes_in_group("city_trees"):
		if not root.is_ancestor_of(mmi):
			continue
		var kind := int(mmi.get_meta("kind", 0))
		(mmi as MultiMeshInstance3D).multimesh.mesh = _round_tree_mesh(biome) if kind == 0 else _palm_mesh(biome)


static func _leaf_colors(biome: int) -> Array:
	var b: Dictionary = DaylightPresets.BIOMES.get(biome, DaylightPresets.BIOMES[DaylightPresets.Biome.SUMMER])
	return b["leaves"]


static func _round_tree_mesh(biome: int) -> ArrayMesh:
	var leaves := _leaf_colors(biome)
	var summer := biome == DaylightPresets.Biome.SUMMER
	var a: Color = Color(0.26, 0.48, 0.2) if summer else leaves[0]
	var b: Color = Color(0.3, 0.54, 0.23) if summer else leaves[1]
	var mb := MeshBuilder.new()
	mb.posts().cylinder(Transform3D.IDENTITY, 0.28, 0.2, 3.2, Color(0.4, 0.3, 0.22), 6, false)
	mb.blob(Vector3(0, 4.6, 0), Vector3(2.6, 2.2, 2.6), a, 9, 5, 0.35)
	mb.blob(Vector3(0.9, 5.6, 0.4), Vector3(1.6, 1.4, 1.6), b, 7, 4, 0.3)
	return mb.commit(null, TrackMaterials.structure())


static func _palm_mesh(biome := 0) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var trunk := Color(0.55, 0.45, 0.33)
	# Tronco levemente curvo, em anéis
	var segs := 7
	var height := 8.5
	var prev := Vector3.ZERO
	for k in segs:
		var t := float(k + 1) / segs
		var p := Vector3(0.9 * t * t, height * t, 0.0)
		var xf := Transform3D(Basis(Vector3.FORWARD, atan2(p.x - prev.x, p.y - prev.y)), prev)
		mb.posts().cylinder(xf, lerpf(0.32, 0.2, t - 1.0 / segs), lerpf(0.32, 0.2, t), prev.distance_to(p) + 0.05,
			trunk.darkened(0.1 if k % 2 == 0 else 0.0), 6, false)
		prev = p
	var crown := prev
	# Folhas: tiras arqueadas caindo para fora
	var leaf := Color(0.3, 0.55, 0.22)
	if biome != DaylightPresets.Biome.SUMMER:
		var tint: Color = _leaf_colors(biome)[0]
		leaf = leaf.lerp(tint, 0.45 if biome != DaylightPresets.Biome.SAKURA else 0.25)
	for f in 9:
		var ang := TAU * f / 9.0 + (0.2 if f % 2 == 0 else 0.0)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var length := 4.2 if f % 2 == 0 else 3.6
		var a := crown
		for k in 4:
			var t0 := float(k) / 4.0
			var t1 := float(k + 1) / 4.0
			var p0 := crown + dir * length * t0 + Vector3.UP * (1.2 * t0 - 2.6 * t0 * t0)
			var p1 := crown + dir * length * t1 + Vector3.UP * (1.2 * t1 - 2.6 * t1 * t1)
			var w0 := 0.75 * sin(PI * (t0 * 0.85 + 0.1))
			var w1 := 0.75 * sin(PI * (t1 * 0.85 + 0.1))
			var c := leaf.darkened(0.12 * k)
			mb.quad(p0 - side * w0, p1 - side * w1, p1 + side * w1, p0 + side * w0, c)
			mb.quad(p0 + side * w0, p1 + side * w1, p1 - side * w1, p0 - side * w0, c.darkened(0.2))
			a = p1
	mb.blob(crown + Vector3(0, -0.2, 0), Vector3(0.45, 0.5, 0.45), Color(0.45, 0.36, 0.22), 6, 3)
	return mb.commit(null, TrackMaterials.structure())


# ---------------------------------------------------------------------------
# Entorno: morros e casario além da área dos dados
# ---------------------------------------------------------------------------
## Anéis em volta do retângulo da cidade (raios a partir do centro). O anel 0 coincide com a borda
## do terreno da cidade (mesmas alturas); do lado da terra o relevo sobe até ~650 m (Alpes
## Marítimos) e despenca no mar seguindo a linha da costa fora da área; do lado do mar fica no fundo.
const RINGS := [0.0, 10.0, 28.0, 60.0, 110.0, 180.0, 280.0, 420.0, 620.0, 900.0, 1300.0, 1900.0, 2700.0, 3800.0, 5200.0]


static func build_backdrop(track: RaceTrack, city: TrackCity, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Backdrop"
	parent.add_child(root)
	var exits: Array = city.data.get("coast_exits", [])
	var p1 := Vector2.ZERO
	var p2 := Vector2(1, 1)
	if exits.size() >= 2:
		p1 = Vector2(exits[0][0], exits[0][1])
		p2 = Vector2(exits[1][0], exits[1][1])
	var center := city.area.get_center()
	var land_sign := signf((p2 - p1).cross(Vector2(city.area.position.x, city.area.end.y) - p1))
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.0012
	noise.fractal_octaves = 4
	# Borda do retângulo nos vértices da grade (anti-horário visto de cima, x leste / y norte)
	var border: Array[Vector2i] = []
	for ix in range(0, city.nx - 1):
		border.append(Vector2i(ix, 0))
	for iy in range(0, city.ny - 1):
		border.append(Vector2i(city.nx - 1, iy))
	for ix in range(city.nx - 1, 0, -1):
		border.append(Vector2i(ix, city.ny - 1))
	for iy in range(city.ny - 1, 0, -1):
		border.append(Vector2i(0, iy))
	var n := border.size()
	var rows: Array[PackedVector3Array] = []
	var land_rows: Array[PackedByteArray] = []
	for r in RINGS.size():
		var row := PackedVector3Array()
		var lands := PackedByteArray()
		for k in n:
			var g := border[k]
			var b := Vector2(city.area.position.x + g.x * city.cell, city.area.position.y + g.y * city.cell)
			var h0 := city.heights[g.y * city.nx + g.x]
			var dir := (b - center).normalized()
			var d: float = RINGS[r]
			var p := b + dir * d
			var h := h0
			var is_land := 0
			if r > 0:
				var dc := land_sign * (p2 - p1).normalized().cross(p - p1)
				if dc > 0.0 and h0 > -1.0:
					is_land = 1
					var mountain := 90.0 + clampf(dc * 0.28, 0.0, 560.0) + noise.get_noise_2d(p.x, p.y) * 120.0
					h = lerpf(h0, maxf(mountain, h0), smoothstep(0.0, 1400.0, d))
					h *= smoothstep(0.0, 140.0, dc)
					h = maxf(h, -6.0)
				else:
					h = minf(h0, -4.0) if d > 30.0 else h0
			row.append(to_world(p.x, p.y, h))
			lands.append(is_land)
		rows.append(row)
		land_rows.append(lands)
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var index := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for r in RINGS.size():
		for k in n:
			var v := rows[r][k]
			verts.append(v)
			var c := PAVEMENT
			if r > 0:
				var town := clampf(noise.get_noise_2d(v.x * 3.1, v.z * 3.1) * 2.0 + 0.4 - float(RINGS[r]) / 2500.0, 0.0, 1.0)
				c = GARDEN.lerp(Color(0.5, 0.5, 0.36), clampf(v.y / 700.0, 0.0, 0.6)).lerp(PAVEMENT, town * 0.7)
				if v.y < 1.0:
					c = SLOPE
			colors.append(lin(c * rng.randf_range(0.95, 1.05)))
	for r in RINGS.size() - 1:
		for k in n:
			var k1 := (k + 1) % n
			var a := r * n + k
			var b := r * n + k1
			var c := (r + 1) * n + k1
			var d := (r + 1) * n + k
			# Só desenha o que está acima do fundo do mar perto da costa
			if verts[a].y < -3.0 and verts[b].y < -3.0 and verts[c].y < -3.0 and verts[d].y < -3.0:
				continue
			index.append_array([a, b, c, a, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = index
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, TrackMaterials.building("city_ground", false, {"ground_dirt": 0.0, "grime_strength": 0.25}))
	var mi := MeshInstance3D.new()
	mi.name = "Hills"
	mi.mesh = mesh
	root.add_child(mi)
	_backdrop_town(city, rows, land_rows, root)


## Casario nas encostas logo além da área dos dados (Beausoleil, Cap d'Ail): blocos simples com o
## mesmo shader de fachada.
static func _backdrop_town(city: TrackCity, rows: Array[PackedVector3Array], land_rows: Array[PackedByteArray], root: Node3D) -> void:
	var arr := Arrays.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var palette: Array = city.data["facades"]
	var n := rows[0].size()
	for r in range(1, 9):
		for k in range(0, n, 3):
			if land_rows[r][k] == 0 or land_rows[r + 1][k] == 0 or rng.randf() < 0.35:
				continue
			var a := rows[r][k]
			var b := rows[r + 1][k]
			var p := a.lerp(b, rng.randf())
			var slope := absf(b.y - a.y) / maxf(Vector2(b.x - a.x, b.z - a.z).length(), 1.0)
			if slope > 0.9 or p.y < 2.0:
				continue
			var size := Vector2(rng.randf_range(10.0, 24.0), rng.randf_range(9.0, 18.0))
			var ang := rng.randf() * TAU
			var c := Vector2(p.x, -p.z)
			var poly := PackedVector2Array()
			for v in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				poly.append(c + (v * size * 0.5).rotated(ang))
			var h := rng.randf_range(9.0, 30.0)
			var color := Color(String(palette[rng.randi() % palette.size()]))
			_walls(arr, poly, p.y - 6.0, p.y + h, color, STYLE_PLAIN if rng.randf() < 0.5 else STYLE_CLASSIC, p.y)
			_roof(arr, poly, p.y + h, ROOF_TILE if rng.randf() < 0.4 else ROOF_FLAT)
	if arr.verts.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "Town"
	mi.mesh = arr.commit(_building_material())
	root.add_child(mi)
