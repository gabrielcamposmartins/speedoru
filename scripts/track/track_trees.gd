class_name TrackTrees
extends RefCounted
## Árvores estilizadas espalhadas pelo parque e pelas colinas, sobre o relevo do terreno.
##
## Espécies: carvalho (copa redonda), cipreste italiano, pinheiro, pinheiro-manso (copa em
## guarda-chuva), bétula e arbusto. Cada uma tem duas malhas: detalhada (perto) e simples (longe);
## o MultiMesh de cada bloco de CHUNK m troca de uma para outra pela distância (visibility range).
## Bosques e clareiras vêm de um ruído; penhascos e o alto das montanhas ficam sem árvores.

const CHUNK := 400.0
const LOD_DISTANCE := 380.0
const TRUNK := Color(0.5, 0.33, 0.22)

enum Species { OAK, CYPRESS, PINE, STONE_PINE, BIRCH, BUSH }

static var _near: Array[ArrayMesh] = []
static var _far: Array[ArrayMesh] = []


static func _in_footprint(track: RaceTrack, x: float, z: float) -> bool:
	for poly in track.footprints:
		if Geometry2D.is_point_in_polygon(Vector2(x, z), poly):
			return true
	return false


static func build(track: RaceTrack, terrain: TrackTerrain, parent: Node3D) -> void:
	if track.tree_count <= 0:
		return
	_make_meshes()
	var rng := RandomNumberGenerator.new()
	rng.seed = track.tree_seed
	var groves := FastNoiseLite.new()
	groves.seed = track.tree_seed
	groves.frequency = 1.0 / 260.0
	var x0 := terrain.origin.x
	var z0 := terrain.origin.y
	var x1 := x0 + (terrain.size.x - 1) * TrackTerrain.CELL
	var z1 := z0 + (terrain.size.y - 1) * TrackTerrain.CELL

	var chunks := {}  # Vector3i(cx, cz, espécie) -> [transforms, dados]
	var placed := 0
	var tries := 0
	while placed < track.tree_count and tries < track.tree_count * 8:
		tries += 1
		var x := rng.randf_range(x0, x1)
		var z := rng.randf_range(z0, z1)
		var f := terrain.clearance(x, z)
		if f < 4.0:
			continue
		if f < 30.0 and _in_footprint(track, x, z):
			continue
		var grove := groves.get_noise_2d(x, z)
		# Linha de árvores junto à pista, bosques e clareiras mais longe
		var density := 1.0 if f < 45.0 else (1.0 if grove > 0.0 else 0.04)
		if rng.randf() > density:
			continue
		var h := terrain.height_at(x, z)
		if h > 240.0 or terrain.slope_at(x, z) > 0.38:
			continue
		var species := _pick_species(rng, f, h)
		var scale := rng.randf_range(0.8, 1.3) * (1.15 if f > 120.0 else 1.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		# Inclinação leve (árvores nunca perfeitamente retas)
		basis = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.06)) * basis
		basis = basis.scaled(Vector3(scale, scale * rng.randf_range(0.9, 1.15), scale))
		var key := Vector3i(floori(x / CHUNK), floori(z / CHUNK), species)
		if not chunks.has(key):
			chunks[key] = [[] as Array[Transform3D], [] as Array[Color]]
		chunks[key][0].append(Transform3D(basis, Vector3(x, h - 0.1, z)))
		chunks[key][1].append(Color(rng.randf(), rng.randf(), rng.randf(), TrackTerrain.dark_zone(x, z)))
		placed += 1

	var root := Node3D.new()
	root.name = "Trees"
	parent.add_child(root)
	var mat := TrackMaterials.tree()
	for key in chunks:
		var transforms: Array[Transform3D] = chunks[key][0]
		var data: Array[Color] = chunks[key][1]
		var buffer := Grandstands.pack_buffer(transforms, data)
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = _near[key.z] if lod == 0 else _far[key.z]
			mm.instance_count = transforms.size()
			mm.buffer = buffer
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Trees_%d_%d_%d_%s" % [key.x, key.y, key.z, "near" if lod == 0 else "far"]
			mmi.multimesh = mm
			mmi.material_override = mat
			if lod == 0:
				mmi.visibility_range_end = LOD_DISTANCE
				mmi.visibility_range_end_margin = 30.0
			else:
				mmi.visibility_range_begin = LOD_DISTANCE
				mmi.visibility_range_begin_margin = 30.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)


static func _pick_species(rng: RandomNumberGenerator, f: float, h: float) -> int:
	var r := rng.randf()
	if h > 90.0:
		return Species.PINE if r < 0.75 else Species.OAK
	if f < 45.0:
		# Perto da pista: mistura italiana, com arbustos e ciprestes
		if r < 0.3:
			return Species.OAK
		if r < 0.48:
			return Species.STONE_PINE
		if r < 0.62:
			return Species.CYPRESS
		if r < 0.8:
			return Species.BUSH
		if r < 0.9:
			return Species.BIRCH
		return Species.PINE
	if r < 0.42:
		return Species.OAK
	if r < 0.6:
		return Species.PINE
	if r < 0.72:
		return Species.STONE_PINE
	if r < 0.82:
		return Species.BIRCH
	if r < 0.9:
		return Species.CYPRESS
	return Species.BUSH


## Malhas prontas (para outros cenários, como a cidade de Mônaco).
static func ensure_meshes() -> void:
	_make_meshes()


## Malha de uma espécie: detalhada (perto) ou simples (longe).
static func mesh(species: int, near: bool) -> ArrayMesh:
	_make_meshes()
	return _near[species] if near else _far[species]


static func _make_meshes() -> void:
	if not _near.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for species in Species.size():
		var near := MeshBuilder.new()
		var far := MeshBuilder.new()
		match species:
			Species.OAK:
				var leaf := Color(0.29, 0.62, 0.27)
				near.cylinder(Transform3D(), 0.34, 0.22, 3.6, TRUNK, 7, false)
				for k in 2:
					var dir := Vector3(cos(k * 2.6 + 0.4), 0.0, sin(k * 2.6 + 0.4))
					var xf := Transform3D(Basis(dir.cross(Vector3.UP).normalized(), deg_to_rad(40.0)), Vector3.UP * 2.6)
					near.cylinder(xf, 0.14, 0.07, 1.8, TRUNK, 5, false)
				var blobs := [[Vector3(0, 5.4, 0), Vector3(2.6, 2.2, 2.6)], [Vector3(1.6, 4.6, 0.6), Vector3(1.8, 1.6, 1.8)],
					[Vector3(-1.4, 4.8, -0.7), Vector3(1.9, 1.7, 1.9)], [Vector3(0.4, 7.0, -0.2), Vector3(1.7, 1.4, 1.7)],
					[Vector3(-0.5, 4.4, 1.6), Vector3(1.6, 1.4, 1.6)], [Vector3(0.9, 6.2, -1.4), Vector3(1.5, 1.3, 1.5)],
					[Vector3(-1.5, 6.3, 0.8), Vector3(1.3, 1.2, 1.3)]]
				for b in blobs:
					near.blob(b[0], b[1], leaf.lightened(rng.randf_range(-0.04, 0.08)), 8, 5, 0.3)
				far.cylinder(Transform3D(), 0.34, 0.22, 3.6, TRUNK, 4, false)
				far.blob(Vector3(0, 5.5, 0), Vector3(3.0, 2.7, 3.0), leaf, 6, 4, 0.3)
			Species.CYPRESS:
				var dark := Color(0.17, 0.42, 0.25)
				near.cylinder(Transform3D(), 0.22, 0.16, 1.4, TRUNK, 6, false)
				near.blob(Vector3(0, 3.4, 0), Vector3(1.25, 2.6, 1.25), dark, 8, 5, 0.3)
				near.blob(Vector3(0.1, 6.2, 0.05), Vector3(1.0, 2.6, 1.0), dark.lightened(0.04), 8, 5, 0.25)
				near.blob(Vector3(0.0, 8.7, 0.1), Vector3(0.6, 1.9, 0.6), dark.lightened(0.08), 8, 5, 0.2)
				far.blob(Vector3(0, 5.2, 0), Vector3(1.2, 5.0, 1.2), dark, 6, 4, 0.3)
			Species.PINE:
				var pine := Color(0.15, 0.45, 0.33)
				near.cylinder(Transform3D(), 0.3, 0.18, 2.4, TRUNK, 6, false)
				for k in 4:
					var r := 2.7 - k * 0.6
					near.cylinder(Transform3D(Basis(), Vector3.UP * (1.9 + k * 1.75)), r, 0.0, 2.8 - k * 0.25,
						pine.lightened(k * 0.05), 10)
					# Saia levemente caída sob cada camada
					near.cylinder(Transform3D(Basis(), Vector3.UP * (1.9 + k * 1.75 - 0.3)), r * 0.75, r, 0.3,
						pine.darkened(0.15), 10, false)
				far.cylinder(Transform3D(), 0.3, 0.18, 2.4, TRUNK, 4, false)
				far.cylinder(Transform3D(Basis(), Vector3.UP * 1.9), 2.7, 0.0, 7.4, pine, 6)
			Species.STONE_PINE:
				var canopy := Color(0.24, 0.5, 0.25)
				near.cylinder(Transform3D(), 0.32, 0.24, 4.0, TRUNK, 7, false)
				near.cylinder(Transform3D(Basis(Vector3.FORWARD, 0.18), Vector3.UP * 3.9), 0.24, 0.18, 3.6, TRUNK, 6, false)
				for k in 6:
					var a := TAU * k / 6.0
					var c := Vector3(cos(a) * 2.3, 8.0 + rng.randf_range(-0.3, 0.3), sin(a) * 2.3) + Vector3(-0.6, 0, 0)
					near.blob(c, Vector3(2.4, 1.0, 2.4), canopy.lightened(rng.randf_range(-0.03, 0.07)), 8, 5, 0.35)
				near.blob(Vector3(-0.6, 8.5, 0), Vector3(2.6, 1.1, 2.6), canopy.lightened(0.06), 8, 5, 0.35)
				far.cylinder(Transform3D(), 0.32, 0.24, 7.6, TRUNK, 4, false)
				far.blob(Vector3(-0.6, 8.2, 0), Vector3(4.6, 1.4, 4.6), canopy, 7, 4, 0.35)
			Species.BIRCH:
				var light := Color(0.5, 0.74, 0.3)
				var y := 0.0
				for k in 6:
					var mark := Color(0.95, 0.94, 0.9) if k % 2 == 0 else Color(0.25, 0.24, 0.24)
					var hgt := 1.1 if k % 2 == 0 else 0.18
					near.cylinder(Transform3D(Basis(), Vector3.UP * y), 0.17 - y * 0.012, 0.17 - (y + hgt) * 0.012, hgt, mark, 7, false)
					y += hgt
				near.blob(Vector3(0.2, 5.4, 0.1), Vector3(1.7, 2.1, 1.7), light, 8, 5, 0.25)
				near.blob(Vector3(-0.8, 4.4, -0.4), Vector3(1.2, 1.3, 1.2), light.lightened(0.06), 8, 5, 0.25)
				near.blob(Vector3(0.7, 4.0, 0.7), Vector3(1.1, 1.2, 1.1), light.darkened(0.04), 8, 5, 0.25)
				far.cylinder(Transform3D(), 0.17, 0.1, 4.0, Color(0.92, 0.91, 0.88), 4, false)
				far.blob(Vector3(0, 5.0, 0), Vector3(2.0, 2.3, 2.0), light, 6, 4, 0.25)
			Species.BUSH:
				var bush := Color(0.33, 0.6, 0.28)
				for k in 4:
					var a := TAU * k / 4.0 + 0.3
					near.blob(Vector3(cos(a) * 0.7, 0.75, sin(a) * 0.7), Vector3(1.0, 0.85, 1.0),
						bush.lightened(rng.randf_range(-0.04, 0.06)), 8, 5, 0.3)
				near.blob(Vector3(0, 1.2, 0), Vector3(0.9, 0.8, 0.9), bush.lightened(0.06), 8, 5, 0.3)
				far.blob(Vector3(0, 0.9, 0), Vector3(1.6, 1.0, 1.6), bush, 6, 4, 0.3)
		_near.append(near.commit())
		_far.append(far.commit())
