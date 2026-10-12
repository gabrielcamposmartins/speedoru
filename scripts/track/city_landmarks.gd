class_name CityLandmarks
extends Node3D
## Marcos de uma cidade (TrackCity, chave "landmarks" do JSON gerado por tools/build_las_vegas.py),
## desenhados à parte dos prédios comuns:
## * "sphere": a Sphere — tela de LED esférica (shader vegas_sphere: olho, planeta, ondas de néon)
##   sobre uma base escura; olha para o centro do circuito;
## * "eiffel": a Torre Eiffel do Paris Las Vegas — treliça de bronze (pernas curvas, travessas em X,
##   dois andares, mirante e antena) com lâmpadas douradas que acendem à noite;
## * "wheel": a roda-gigante High Roller (FerrisWheel em escala real, de frente para o plano mapeado);
## * "fountain": os jatos das fontes do Bellagio no lago (shader vegas_fountain, coreografia).
## Coordenadas dos dados: x leste, y norte (TrackCity.to_world).

## Tipos de prédio que viram marco (o TrackCity não desenha a caixa deles).
const KINDS := ["sphere", "eiffel"]
const BRONZE := Color(0.52, 0.36, 0.24)
const BRONZE_DARK := Color(0.36, 0.25, 0.17)
const GOLD := Color(1.0, 0.78, 0.35)

static var _night_mats: Array[ShaderMaterial] = []


static func build(track: RaceTrack, city: TrackCity, parent: Node3D) -> void:
	var list: Array = city.data.get("landmarks", [])
	if list.is_empty():
		return
	var root := CityLandmarks.new()
	root.name = "Landmarks"
	parent.add_child(root)
	_night_mats.clear()
	var center := Vector3.ZERO
	var n := 0
	var s := 0.0
	while s < track.path.length:
		center += track.path.position_at(s)
		n += 1
		s += 50.0
	center /= maxi(n, 1)
	for l: Dictionary in list:
		match str(l.get("kind", "")):
			"sphere":
				root._sphere(l, center)
			"eiffel":
				root._eiffel(l)
			"wheel":
				root._wheel(l, track)
			"fountain":
				root._fountain(l)


## Noite (0..1): telas e jatos mais fortes.
static func set_night(amount: float) -> void:
	for m in _night_mats:
		if is_instance_valid(m):
			m.set_shader_parameter("night", amount)


# ---------------------------------------------------------------------------
# Sphere
# ---------------------------------------------------------------------------
func _sphere(l: Dictionary, look_at_pt: Vector3) -> void:
	var h := float(l["h"])
	var radius := clampf(float(l["r"]) * 0.92, 55.0, 80.0)
	var ground := float(l["z"])
	var c := TrackCity.to_world(float(l["x"]), float(l["y"]), ground + h - radius)
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/vegas_sphere.gdshader")
	var to_track := look_at_pt - c
	to_track.y = 0.0
	mat.set_shader_parameter("look_dir", (to_track.normalized() + Vector3(0, 0.12, 0)).normalized())
	_night_mats.append(mat)
	var mi := MeshInstance3D.new()
	mi.name = "Sphere"
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = c
	add_child(mi)
	# Base escura onde a esfera encosta no chão
	var base_r := sqrt(maxf(radius * radius - (h - radius) * (h - radius), 1.0))
	var plinth := CylinderMesh.new()
	plinth.top_radius = base_r * 0.92
	plinth.bottom_radius = base_r * 1.05
	plinth.height = 6.0
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.12, 0.12, 0.14)
	plinth.material = pmat
	var pi := MeshInstance3D.new()
	pi.name = "SphereBase"
	pi.mesh = plinth
	pi.position = TrackCity.to_world(float(l["x"]), float(l["y"]), ground + 3.0)
	add_child(pi)


# ---------------------------------------------------------------------------
# Torre Eiffel (réplica do Paris Las Vegas)
# ---------------------------------------------------------------------------
func _eiffel(l: Dictionary) -> void:
	var height := float(l["h"])
	var base := TrackCity.to_world(float(l["x"]), float(l["y"]), float(l["z"]))
	var mb := MeshBuilder.new()
	var bulbs := MeshBuilder.new()
	var levels := 26
	var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	var prev: Array[Vector3] = []
	for k in levels + 1:
		var t := float(k) / levels
		var y := t * height * 0.9
		var w := _eiffel_half(t, height)
		var ring: Array[Vector3] = []
		for c: Vector2 in corners:
			ring.append(base + Vector3(c.x * w, y, c.y * w))
		if not prev.is_empty():
			var thick := lerpf(2.2, 0.6, t)
			for i in 4:
				_beam(mb, prev[i], ring[i], thick, BRONZE)
				var j := (i + 1) % 4
				# Travessas em X nas faces (menos no alto, onde a torre já é fina)
				if t < 0.85:
					_beam(mb, prev[i], ring[j], thick * 0.35, BRONZE_DARK)
					_beam(mb, prev[j], ring[i], thick * 0.35, BRONZE_DARK)
				_beam(mb, ring[i], ring[j], thick * 0.4, BRONZE_DARK)
				if k % 2 == 0:
					bulbs.box(Transform3D(Basis(), ring[i]), Vector3.ONE * thick * 0.6, GOLD)
		prev = ring
	# Andares e mirante
	for f: Array in [[0.19, 3.0], [0.38, 2.4], [0.86, 1.6]]:
		var t: float = f[0]
		var w := _eiffel_half(t, height) * 1.12
		var y := t * height * 0.9
		mb.box(Transform3D(Basis(), base + Vector3(0, y, 0)), Vector3(w * 2.0, float(f[1]), w * 2.0), BRONZE_DARK)
		for c: Vector2 in corners:
			bulbs.box(Transform3D(Basis(), base + Vector3(c.x * w, y + 1.4, c.y * w)), Vector3(1.2, 1.2, 1.2), GOLD)
	# Arcos na base (entre as pernas)
	var w0 := _eiffel_half(0.0, height)
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var last := Vector3.ZERO
		for k in 9:
			var u := float(k) / 8.0
			var p := a.lerp(b, u) * w0 * 0.82
			var y := sin(u * PI) * height * 0.14 + height * 0.02
			var q := base + Vector3(p.x, y, p.y)
			if k > 0:
				_beam(mb, last, q, 1.3, BRONZE)
			last = q
	# Antena
	var top := base + Vector3(0, height * 0.9, 0)
	_beam(mb, top, base + Vector3(0, height, 0), 0.8, BRONZE_DARK)
	bulbs.box(Transform3D(Basis(), base + Vector3(0, height, 0)), Vector3(1.6, 1.6, 1.6), Color(1.0, 0.2, 0.15))
	var mi := MeshInstance3D.new()
	mi.name = "EiffelTower"
	mi.mesh = mb.commit(null, TrackMaterials.structure())
	add_child(mi)
	var lights := MeshInstance3D.new()
	lights.name = "EiffelLights"
	lights.mesh = bulbs.commit(null, TrackMaterials.lamp(2.0))
	lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lights)


## Meia-largura da torre na altura relativa t (curva das pernas: larga embaixo, fina em cima).
static func _eiffel_half(t: float, height: float) -> float:
	return height * (0.19 * pow(1.0 - t, 2.4) + 0.012)


static func _beam(mb: MeshBuilder, a: Vector3, b: Vector3, thick: float, color: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var y := d / length
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	mb.box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(thick, length, thick), color)


# ---------------------------------------------------------------------------
# High Roller
# ---------------------------------------------------------------------------
func _wheel(l: Dictionary, track: RaceTrack) -> void:
	var wheel := FerrisWheel.create(float(l["d"]))
	wheel.name = "HighRoller"
	# Plano da roda na direção mapeada (dx, dy): o eixo local Z da roda; o eixo de giro em X
	var plane := Vector3(float(l["dx"]), 0.0, -float(l["dy"])).normalized()
	var axis := plane.cross(Vector3.UP).normalized()
	var c := TrackCity.to_world(float(l["x"]), float(l["y"]), float(l["z"]) - 0.2)
	wheel.transform = Transform3D(Basis(axis, Vector3.UP, plane), c)
	wheel.speed = 0.012  # uma volta a cada ~9 min, como a de verdade (30 min) mas visível
	add_child(wheel)
	var poly := PackedVector2Array()
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var q: Vector3 = c + axis * d.x * 18.0 + plane * d.y * float(l["d"]) * 0.42
		poly.append(Vector2(q.x, q.z))
	track.footprints.append(poly)


# ---------------------------------------------------------------------------
# Fontes do Bellagio
# ---------------------------------------------------------------------------
func _fountain(l: Dictionary) -> void:
	var p: Array = l["p"]
	var poly := PackedVector2Array()
	for i in range(0, p.size(), 2):
		poly.append(Vector2(p[i], p[i + 1]))
	var center := TrackCity._centroid(poly)
	# Fileira de jatos: a borda do lago que dá para a Strip (leste), 22 m para dentro
	var pts: Array[Vector2] = []
	var east := -INF
	for v in poly:
		east = maxf(east, v.x)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var steps := maxi(int(a.distance_to(b) / 7.0), 1)
		for k in steps:
			var q := a.lerp(b, float(k) / steps)
			if q.x < east - 140.0:
				continue
			var inner := q + (center - q).normalized() * 22.0
			if Geometry2D.is_point_in_polygon(inner, poly):
				pts.append(inner)
	if pts.is_empty():
		return
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var jet := CylinderMesh.new()
	jet.top_radius = 0.35
	jet.bottom_radius = 0.9
	jet.height = 1.0
	jet.radial_segments = 8
	jet.rings = 6
	# Base em y = 0 (o shader estica para cima)
	var arrays := jet.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += 0.5
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mm.mesh = mesh
	mm.instance_count = pts.size()
	var z := float(l["z"])
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis(), TrackCity.to_world(pts[i].x, pts[i].y, z)))
		mm.set_instance_custom_data(i, Color(float(i) / maxf(pts.size() - 1, 1.0), 0, 0, 0))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/vegas_fountain.gdshader")
	_night_mats.append(mat)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BellagioFountains"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-2000, -10, -2000), Vector3(4000, 200, 4000))
	add_child(mmi)
