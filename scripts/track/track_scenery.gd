class_name TrackScenery
extends RefCounted
## Objetos ao redor do parque que dão escala e escondem o horizonte (ideia das pistas de
## Mario Kart): rochas nas colinas, vilarejos italianos com campanário, turbinas eólicas na
## serra, balões e um dirigível de anúncios dando voltas. Animação em SceneryAnimator.

const WALLS := [Color(0.96, 0.9, 0.78), Color(0.95, 0.78, 0.55), Color(0.93, 0.68, 0.58), Color(0.98, 0.96, 0.92),
	Color(0.88, 0.76, 0.62)]
const ROOF := Color(0.78, 0.36, 0.24)
const WINDOW := Color(0.25, 0.32, 0.45)
const ROCK := Color(0.66, 0.58, 0.52)


static func build(track: RaceTrack, terrain: TrackTerrain, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Scenery"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = track.tree_seed + 77
	_rocks(terrain, rng, root)
	_villages(terrain, rng, root)
	var animator := SceneryAnimator.new()
	animator.name = "Animator"
	animator.terrain = terrain
	root.add_child(animator)
	_turbines(terrain, rng, root, animator)
	_balloons(terrain, rng, root, animator)
	# Dirigíveis: [cor da faixa, anúncio, altura, raios (fração do raio da pista), velocidade, sentido]
	var blimps := [
		[Color(0.91, 0.15, 0.43), 0, 260.0, Vector2(0.75, 0.55), 14.0, 1.0],
		[Color(0.18, 0.5, 0.95), 4, 340.0, Vector2(0.5, 0.95), 11.0, -1.0],
		[Color(1.0, 0.78, 0.1), 3, 190.0, Vector2(0.18, 0.3), 8.0, 1.0],
		[Color(0.2, 0.75, 0.45), 10, 230.0, Vector2(0.95, 0.4), 12.0, 1.0],
		[Color(0.55, 0.3, 0.85), 5, 300.0, Vector2(0.35, 0.6), 10.0, -1.0],
		[Color(1.0, 0.5, 0.15), 13, 160.0, Vector2(0.25, 0.2), 7.0, -1.0],
	]
	for k in blimps.size():
		var b: Array = blimps[k]
		var height: float = b[2]
		var c3 := Vector3(terrain.center.x, height, terrain.center.y)
		if k == 2:
			# O terceiro fica sobre a reta principal (dirigível da TV)
			var start := track.path.position_at(0.0)
			c3 = Vector3(start.x, height, start.z)
		elif k == 5:
			# Outro baixinho sobre a Parabolica
			var para := track.path.position_at(4980.0)
			c3 = Vector3(para.x, height, para.z)
		elif k == 4:
			# Um sobre a região de Lesmo / Serraglio
			var lesmo := track.path.position_at(2600.0)
			c3 = Vector3(lesmo.x, height, lesmo.z)
		var radii: Vector2 = b[3]
		_blimp(root, animator, "Blimp%d" % k, b[0], b[1], c3, radii * terrain.track_radius, b[4], b[5])
	# Dirigíveis baixos: órbitas curtas sobre trechos da pista e passagens retas cruzando o circuito
	var low := [
		[Color(0.95, 0.25, 0.3), 6, 55.0, 1200.0, Vector2(160, 110), 9.0],
		[Color(0.2, 0.6, 0.95), 11, 70.0, 3600.0, Vector2(220, 140), -8.0],
		[Color(1.0, 0.85, 0.2), 2, 60.0, 4950.0, Vector2(140, 120), 7.0],
		[Color(0.6, 0.35, 0.9), 9, 50.0, 300.0, Vector2(120, 260), -6.0],
	]
	for k in low.size():
		var b: Array = low[k]
		var at := track.path.position_at(b[3])
		_blimp(root, animator, "LowBlimp%d" % k, b[0], b[1], Vector3(at.x, b[2], at.z), b[4], absf(b[5]), signf(b[5]))
	var passes := [
		[Color(0.15, 0.8, 0.6), 8, 45.0, 0.0, 0.3],
		[Color(0.9, 0.4, 0.9), 12, 65.0, 2400.0, 1.9],
		[Color(1.0, 0.6, 0.2), 14, 90.0, 4300.0, 3.1],
	]
	for k in passes.size():
		var b: Array = passes[k]
		var at := track.path.position_at(b[3])
		var heading: float = b[4]
		var dir := Vector3(cos(heading), 0.0, sin(heading))
		var reach := terrain.track_radius + 1400.0
		var center := Vector3(at.x, b[2], at.z)
		var node := _blimp(root, animator, "PassBlimp%d" % k, b[0], b[1], center, Vector2.ONE, 0.0, 1.0)
		animator.remove_blimp(node)
		animator.add_blimp_pass(node, center - dir * reach, center + dir * reach, 16.0, rng.randf() * 2.0)
	TrackLife.build(track, terrain, root, animator)
	_clouds(terrain, rng, root, animator)


# ---------------------------------------------------------------------------
# Rochas
# ---------------------------------------------------------------------------
static func _rocks(terrain: TrackTerrain, rng: RandomNumberGenerator, root: Node3D) -> void:
	var meshes: Array[ArrayMesh] = []
	for k in 3:
		meshes.append(_rock_mesh(rng))
	var transforms := [[] as Array[Transform3D], [] as Array[Transform3D], [] as Array[Transform3D]]
	var x0 := terrain.origin.x
	var z0 := terrain.origin.y
	var x1 := x0 + (terrain.size.x - 1) * TrackTerrain.CELL
	var z1 := z0 + (terrain.size.y - 1) * TrackTerrain.CELL
	var placed := 0
	var tries := 0
	while placed < 520 and tries < 20000:
		tries += 1
		var x := rng.randf_range(x0, x1)
		var z := rng.randf_range(z0, z1)
		var f := terrain.clearance(x, z)
		if f < 15.0:
			continue
		var slope := terrain.slope_at(x, z)
		# Mais pedras nas encostas e no pé dos penhascos
		if rng.randf() > 0.15 + slope * 1.6:
			continue
		var s := rng.randf_range(0.8, 3.0) * (2.5 if f > 300.0 and rng.randf() < 0.3 else 1.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.6, 1.1), s))
		var h := terrain.height_at(x, z)
		transforms[rng.randi() % 3].append(Transform3D(basis, Vector3(x, h - s * 0.25, z)))
		placed += 1
	for k in 3:
		var list: Array[Transform3D] = transforms[k]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[k]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Rocks%d" % k
		mmi.multimesh = mm
		mmi.material_override = TrackMaterials.rock()
		root.add_child(mmi)


## Pedra facetada: esfera grosseira deformada, faces planas; topo com musgo.
static func _rock_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var seg := 7
	var rings := 5
	var pts := []
	for r in rings + 1:
		var row := []
		var phi := PI * r / rings
		for k in seg:
			var th := TAU * k / seg + r * 0.4
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			row.append(d * rng.randf_range(0.75, 1.15) * Vector3(1.0, 0.75, 1.0))
		pts.append(row)
	for r in rings:
		for k in seg:
			var k1 := (k + 1) % seg
			var quad := [pts[r][k], pts[r][k1], pts[r + 1][k1], pts[r + 1][k]]
			var center: Vector3 = (quad[0] + quad[1] + quad[2] + quad[3]) * 0.25
			var top := center.y > 0.35
			var col := Color(0.42, 0.62, 0.3) if top and rng.randf() < 0.6 else ROCK.darkened(rng.randf_range(0.0, 0.15))
			if r > 0:
				mb.tri(quad[0], quad[1], quad[2], col, center)
			if r < rings - 1:
				mb.tri(quad[0], quad[2], quad[3], col, center)
	return mb.commit()


# ---------------------------------------------------------------------------
# Vilarejos
# ---------------------------------------------------------------------------
static func _villages(terrain: TrackTerrain, rng: RandomNumberGenerator, root: Node3D) -> void:
	var centers: Array[Vector2] = []
	var tries := 0
	while centers.size() < 4 and tries < 4000:
		tries += 1
		var a := rng.randf() * TAU
		var r := terrain.track_radius + rng.randf_range(250.0, 650.0)
		var c := terrain.center + Vector2(cos(a), sin(a)) * r
		if not terrain.in_grid(c.x, c.y) or terrain.clearance(c.x, c.y) < 220.0:
			continue
		if terrain.slope_at(c.x, c.y) > 0.12:
			continue
		var far_enough := true
		for o in centers:
			far_enough = far_enough and o.distance_to(c) > 900.0
		if far_enough:
			centers.append(c)
	var mb := MeshBuilder.new()
	var glass := MeshBuilder.new()
	for c in centers:
		var houses := rng.randi_range(14, 24)
		for k in houses:
			var p := c + Vector2(rng.randf_range(-70, 70), rng.randf_range(-70, 70))
			if terrain.slope_at(p.x, p.y) > 0.25:
				continue
			_house(mb, glass, terrain, p, rng)
		_bell_tower(mb, glass, terrain, c + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)))
	if mb.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "Villages"
	mi.mesh = mb.commit(null, TrackMaterials.structure())
	glass.commit(mi.mesh as ArrayMesh, TrackMaterials.glass())
	root.add_child(mi)


static func _house(mb: MeshBuilder, glass: MeshBuilder, terrain: TrackTerrain, p: Vector2, rng: RandomNumberGenerator) -> void:
	var w := rng.randf_range(6.0, 10.0)
	var d := rng.randf_range(6.0, 9.0)
	var h := rng.randf_range(5.0, 9.0)
	var ground := minf(terrain.height_at(p.x - w * 0.5, p.y), terrain.height_at(p.x + w * 0.5, p.y))
	ground = minf(ground, minf(terrain.height_at(p.x, p.y - d * 0.5), terrain.height_at(p.x, p.y + d * 0.5)))
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	var base := Vector3(p.x, ground - 3.0, p.y)
	var wall: Color = WALLS[rng.randi() % WALLS.size()]
	var total := h + 3.0
	mb.box(Transform3D(basis, base + Vector3.UP * total * 0.5), Vector3(w, total, d), wall)
	# Janelas nas fachadas maiores
	for side in [-1.0, 1.0]:
		for k in 2:
			for j in int(h / 3.2):
				var off := basis * Vector3((k - 0.5) * w * 0.45, 3.0 + 1.6 + j * 3.0, side * (d * 0.5 + 0.03))
				glass.box(Transform3D(basis, base + off), Vector3(0.9, 1.3, 0.08), Color.WHITE)
				# Persianas verdes ao lado (casas italianas)
				mb.box(Transform3D(basis, base + off + basis * Vector3(0.62, 0, 0)), Vector3(0.3, 1.4, 0.1), Color(0.25, 0.48, 0.3))
				mb.box(Transform3D(basis, base + off - basis * Vector3(0.62, 0, 0)), Vector3(0.3, 1.4, 0.1), Color(0.25, 0.48, 0.3))
	# Telhado de duas águas
	var top := base + Vector3.UP * total
	var rh := w * 0.28
	var a := basis * Vector3(-w * 0.55, 0, -d * 0.55)
	var b := basis * Vector3(w * 0.55, 0, -d * 0.55)
	var c := basis * Vector3(w * 0.55, 0, d * 0.55)
	var e := basis * Vector3(-w * 0.55, 0, d * 0.55)
	var r0 := basis * Vector3(0, rh, -d * 0.55)
	var r1 := basis * Vector3(0, rh, d * 0.55)
	var roof := ROOF.lightened(rng.randf_range(-0.05, 0.08))
	mb.quad(top + a, top + r0, top + r1, top + e, roof, (basis * Vector3(-1, 1.5, 0)).normalized())
	mb.quad(top + b, top + c, top + r1, top + r0, roof.darkened(0.08), (basis * Vector3(1, 1.5, 0)).normalized())
	mb.tri(top + a, top + b, top + r0, wall, basis * Vector3(0, 0, -1))
	mb.tri(top + e, top + c, top + r1, wall, basis * Vector3(0, 0, 1))


static func _bell_tower(mb: MeshBuilder, glass: MeshBuilder, terrain: TrackTerrain, p: Vector2) -> void:
	var ground := terrain.height_at(p.x, p.y) - 3.0
	var base := Vector3(p.x, ground, p.y)
	mb.box(Transform3D(Basis(), base + Vector3.UP * 14.0), Vector3(5.0, 28.0, 5.0), Color(0.93, 0.85, 0.72))
	mb.box(Transform3D(Basis(), base + Vector3.UP * 26.5), Vector3(5.4, 3.0, 5.4), Color(0.85, 0.7, 0.55))
	for side in 4:
		var dir := Basis(Vector3.UP, side * PI * 0.5) * Vector3(0, 0, 2.72)
		glass.box(Transform3D(Basis(Vector3.UP, side * PI * 0.5), base + Vector3.UP * 26.3 + dir), Vector3(1.4, 2.0, 0.06), Color.WHITE)
	mb.cylinder(Transform3D(Basis(), base + Vector3.UP * 28.0), 3.6, 0.0, 6.0, ROOF, 4)


# ---------------------------------------------------------------------------
# Turbinas eólicas, balões e dirigível
# ---------------------------------------------------------------------------
static func _turbines(terrain: TrackTerrain, rng: RandomNumberGenerator, root: Node3D, animator: SceneryAnimator) -> void:
	var base_angle := rng.randf() * TAU
	var blade := MeshBuilder.new()
	for k in 3:
		var b := Basis(Vector3.FORWARD, TAU * k / 3.0)
		blade.box(Transform3D(b, b * Vector3(0, 15.0, 0)), Vector3(1.6, 30.0, 0.4), Color(0.96, 0.97, 0.98))
	blade.box(Transform3D(), Vector3(2.2, 2.2, 1.6), Color(0.9, 0.92, 0.95))
	var blade_mesh := blade.commit(null, TrackMaterials.structure())
	for k in 8:
		var a := base_angle + k * 0.07
		var r := terrain.track_radius + 1500.0 + k % 2 * 120.0
		var p := terrain.center + Vector2(cos(a), sin(a)) * r
		var h := terrain.height_at(p.x, p.y)
		var tower := MeshBuilder.new()
		tower.cylinder(Transform3D(), 2.2, 1.2, 70.0, Color(0.95, 0.96, 0.97), 10)
		tower.box(Transform3D(Basis(), Vector3(0, 71.0, -1.0)), Vector3(3.0, 3.0, 7.0), Color(0.92, 0.93, 0.95))
		var node := MeshInstance3D.new()
		node.name = "Turbine%d" % k
		node.mesh = tower.commit(null, TrackMaterials.structure())
		# Rotor virado para o centro do circuito
		var to_center := Vector3(terrain.center.x - p.x, 0.0, terrain.center.y - p.y).normalized()
		node.transform = Transform3D(Basis.looking_at(-to_center), Vector3(p.x, h - 2.0, p.y))
		root.add_child(node)
		var rotor := MeshInstance3D.new()
		rotor.name = "Rotor"
		rotor.mesh = blade_mesh
		rotor.position = Vector3(0, 71.0, 2.9)
		node.add_child(rotor)
		animator.add_rotor(rotor, rng.randf_range(0.8, 1.3))


static func _balloons(terrain: TrackTerrain, rng: RandomNumberGenerator, root: Node3D, animator: SceneryAnimator) -> void:
	var palettes := [[Color(0.95, 0.25, 0.3), Color(1.0, 0.85, 0.2)], [Color(0.2, 0.55, 0.95), Color(1, 1, 1)],
		[Color(0.55, 0.3, 0.85), Color(0.3, 0.9, 0.7)], [Color(1.0, 0.55, 0.15), Color(0.95, 0.2, 0.5)]]
	for k in palettes.size():
		var mb := MeshBuilder.new()
		var pal: Array = palettes[k]
		var gores := 16
		var rows := 10
		for r in rows:
			for g in gores:
				var col: Color = pal[g % 2]
				var p := []
				var n := []
				for corner in [[r, g], [r, g + 1], [r + 1, g + 1], [r + 1, g]]:
					var t: float = float(corner[0]) / rows
					var ang: float = TAU * float(corner[1]) / gores
					# Perfil de gota: largo em cima, fino embaixo
					var radius := sin(PI * (0.08 + 0.92 * t)) * (0.6 + 0.4 * t) * 9.0 + 1.0
					var y := -cos(PI * t) * 10.0
					p.append(Vector3(cos(ang) * radius, y, sin(ang) * radius))
					n.append(Vector3(cos(ang), 0.3 - 0.6 * (1.0 - t), sin(ang)).normalized())
				mb.tri_smooth(p[0], p[1], p[2], n[0], n[1], n[2], col)
				mb.tri_smooth(p[0], p[2], p[3], n[0], n[2], n[3], col)
		mb.box(Transform3D(Basis(), Vector3(0, -15.0, 0)), Vector3(2.0, 1.5, 2.0), Color(0.55, 0.38, 0.22))
		for c in 4:
			var ang := TAU * c / 4.0 + PI * 0.25
			var top := Vector3(cos(ang) * 1.8, -10.5, sin(ang) * 1.8)
			var bottom := Vector3(cos(ang) * 0.9, -14.3, sin(ang) * 0.9)
			mb.box(Transform3D(Basis.looking_at(top - bottom), (top + bottom) * 0.5), Vector3(0.08, 0.08, (top - bottom).length()),
				Color(0.3, 0.25, 0.2))
		var node := MeshInstance3D.new()
		node.name = "Balloon%d" % k
		node.mesh = mb.commit(null, TrackMaterials.structure())
		var a := rng.randf() * TAU
		var r := terrain.track_radius * rng.randf_range(0.5, 1.1)
		var p2 := terrain.center + Vector2(cos(a), sin(a)) * r
		var pos := Vector3(p2.x, terrain.height_at(p2.x, p2.y) + rng.randf_range(160.0, 300.0), p2.y)
		node.position = pos
		root.add_child(node)
		animator.add_balloon(node, pos, rng.randf() * TAU)


static func _blimp(root: Node3D, animator: SceneryAnimator, node_name: String, band: Color,
		ad: int, center: Vector3, radii: Vector2, speed: float, direction: float) -> Node3D:
	var mb := MeshBuilder.new()
	mb.blob(Vector3.ZERO, Vector3(8.0, 8.0, 32.0), Color(0.94, 0.95, 0.98), 16, 10, 0.25)
	mb.blob(Vector3(0, 0, 0), Vector3(8.1, 1.4, 22.0), band, 16, 6)
	mb.box(Transform3D(Basis(), Vector3(0, -8.6, 2.0)), Vector3(2.8, 2.4, 9.0), Color(0.3, 0.32, 0.4))
	for k in 4:
		var b := Basis(Vector3.BACK, k * PI * 0.5)
		mb.box(Transform3D(b, Vector3(0, 0, -27.0) + b * Vector3(0, 6.5, 0)), Vector3(0.5, 7.0, 7.0), band)
	var ads := MeshBuilder.new()
	for side: float in [-1.0, 1.0]:
		var uv := TrackAds.ad_uv(ad)
		var n := Vector3(side, 0, 0)
		var c := Vector3(side * 8.25, 2.6, 0)
		var right := Vector3.UP.cross(n).normalized()
		var hx := right * 14.0
		var hy := Vector3.UP * 3.5
		ads.quad(c - hx - hy, c + hx - hy, c + hx + hy, c - hx + hy, Color.WHITE, n,
			Vector2(uv.position.x, uv.end.y), Vector2(uv.end.x, uv.end.y), Vector2(uv.end.x, uv.position.y), uv.position)
	var mesh := mb.commit(null, TrackMaterials.structure())
	ads.commit(mesh, TrackMaterials.ads())
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	root.add_child(node)
	animator.add_blimp(node, center, radii, speed * direction)
	return node


# ---------------------------------------------------------------------------
# Nuvens 3D
# ---------------------------------------------------------------------------
static func _clouds(terrain: TrackTerrain, rng: RandomNumberGenerator, root: Node3D, animator: SceneryAnimator) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/cloud.gdshader")
	var meshes: Array[ArrayMesh] = []
	for v in 3:
		meshes.append(_cloud_mesh(rng, 6 + v * 3))
	var transforms := [[] as Array[Transform3D], [] as Array[Transform3D], [] as Array[Transform3D]]
	var area := terrain.track_radius + 6500.0
	for k in 56:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf_range(0.04, 1.0)) * area
		var pos := Vector3(terrain.center.x + cos(a) * r, rng.randf_range(650.0, 1500.0), terrain.center.y + sin(a) * r)
		var s := rng.randf_range(60.0, 170.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.0), s))
		transforms[k % 3].append(Transform3D(basis, pos))
	for v in 3:
		var list: Array[Transform3D] = transforms[v]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[v]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Clouds%d" % v
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-20000, 0, -20000), Vector3(40000, 3000, 40000))
		root.add_child(mmi)
		animator.add_clouds(mm, list, Vector2(terrain.center.x, terrain.center.y), area)


## Nuvem fofa: bolhas agrupadas com a base achatada (malha unitária, ~2 de largura).
static func _cloud_mesh(rng: RandomNumberGenerator, puffs: int) -> ArrayMesh:
	var mb := MeshBuilder.new()
	for k in puffs:
		var x := rng.randf_range(-1.0, 1.0)
		var z := rng.randf_range(-0.45, 0.45)
		var r := rng.randf_range(0.35, 0.6) * (1.25 - absf(x) * 0.5)
		mb.blob(Vector3(x, r * 0.35 + rng.randf_range(0.0, 0.2), z), Vector3(r, r * 0.85, r), Color.WHITE, 10, 7)
	# Base achatada
	for i in mb.verts.size():
		if mb.verts[i].y < 0.0:
			mb.verts[i] = Vector3(mb.verts[i].x, 0.0, mb.verts[i].z)
			mb.normals[i] = Vector3.DOWN
	return mb.commit()
