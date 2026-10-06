class_name TrackPines
extends RefCounted
## Pinheiros de preenchimento (modelo Tree_Pine_Light, de edit-assets-workspace/tree/tree_pine):
## uma faixa densa logo atrás das cercas e mais fileiras atrás dela, para fechar a vista do
## horizonte e encher os arredores da pista. Cor do ambiente (shaders/track/pine_fill.gdshader).
## Perto: o modelo de agulhas (~46 mil triângulos); longe: uma versão estilizada com a mesma
## silhueta (~130 triângulos), na mesma cor. MultiMesh por bloco para o LOD e o culling funcionarem.

const MODEL := "res://assets/track/trees/tree_pine_light.glb"
const CHUNK := 160.0
const LOD_DISTANCE := 400.0

## Fileiras: [afastamento mínimo e máximo depois da cerca/arquibancada (m), espaçamento ao longo
## da pista (m), chance de existir].
const ROWS := [[1.0, 3.5, 7.0, 0.85], [7.0, 14.0, 9.0, 0.8], [16.0, 30.0, 11.0, 0.7], [32.0, 60.0, 14.0, 0.6]]

static var _far_mesh: ArrayMesh


static func build(track: RaceTrack, terrain: TrackTerrain, parent: Node3D) -> void:
	var source := _load_model()
	if source == null:
		return
	var p := track.path
	var lay := track.layout
	var rng := RandomNumberGenerator.new()
	rng.seed = track.tree_seed + 5150
	var chunks := {}
	var leaf_positions: Array[Vector2] = []
	if track.leaves:
		for c in track.leaves.tree_positions:
			leaf_positions.append(Vector2(c.x, c.z))
	for r in ROWS.size():
		var row: Array = ROWS[r]
		var spacing: float = row[2]
		var step := maxi(int(spacing / p.spacing), 1)
		for side in [1, -1]:
			for i in range(0, p.size(), step):
				if rng.randf() > float(row[3]):
					continue
				if lay.has_pit and side == lay.pit_side and track.pit_width[i] > 0.0:
					continue
				var j := p.index_at(p.s_at(i) + rng.randf_range(-0.4, 0.4) * spacing)
				var d := track.outer_distance(j, side) + TrackProps._stand_clearance(track, p.s_at(j), side)
				d += rng.randf_range(float(row[0]), float(row[1]))
				var pos := track.edge_point(j, side, d)
				if not _free_spot(track, pos, leaf_positions):
					continue
				if terrain.slope_at(pos.x, pos.z) > 0.35:
					continue
				pos.y = terrain.height_at(pos.x, pos.z) - 0.05
				var scale := rng.randf_range(1.2, 2.0) * (1.0 + 0.25 * r)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale * rng.randf_range(0.9, 1.15), scale))
				var key := Vector2i(floori(pos.x / CHUNK), floori(pos.z / CHUNK))
				if not chunks.has(key):
					chunks[key] = [[] as Array[Transform3D], [] as Array[Color]]
				chunks[key][0].append(Transform3D(basis, pos))
				chunks[key][1].append(Color(rng.randf(), rng.randf(), rng.randf(), TrackTerrain.dark_zone(pos.x, pos.z) * 0.6))

	var root := Node3D.new()
	root.name = "Pines"
	parent.add_child(root)
	var leaf_mat := ShaderMaterial.new()
	leaf_mat.shader = load("res://shaders/track/pine_fill.gdshader")
	var near := _near_mesh(source, leaf_mat)
	var far := _far()
	var count := 0
	for key in chunks:
		var transforms: Array[Transform3D] = chunks[key][0]
		var buffer := Grandstands.pack_buffer(transforms, chunks[key][1])
		count += transforms.size()
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = near if lod == 0 else far
			mm.instance_count = transforms.size()
			mm.buffer = buffer
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Pines_%d_%d%s" % [key.x, key.y, "" if lod == 0 else "_far"]
			mmi.multimesh = mm
			if lod == 0:
				mmi.visibility_range_end = LOD_DISTANCE
				mmi.visibility_range_end_margin = 15.0
			else:
				mmi.material_override = leaf_mat
				mmi.visibility_range_begin = LOD_DISTANCE
				mmi.visibility_range_begin_margin = 15.0
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
	root.set_meta("count", count)


## Ponto livre: longe de qualquer trecho da pista (curvas fechadas), fora de prédios e
## arquibancadas e sem encostar nas árvores folhosas.
static func _free_spot(track: RaceTrack, pos: Vector3, leaf_positions: Array[Vector2]) -> bool:
	var p := track.path
	var pr := p.project(pos, false)
	if pr.x >= 0.0:
		var k := p.index_at(pr.x)
		var side := 1 if pr.y > 0.0 else -1
		if absf(pr.y) < p.half_width(k, side) + track.outer_distance(k, side):
			return false
	var p2 := Vector2(pos.x, pos.z)
	for poly in track.footprints:
		if Geometry2D.is_point_in_polygon(p2, poly):
			return false
	for lp in leaf_positions:
		if lp.distance_squared_to(p2) < 9.0:
			return false
	return true


static func _load_model() -> ArrayMesh:
	if not ResourceLoader.exists(MODEL):
		push_warning("TrackPines: modelo %s não encontrado." % MODEL)
		return null
	var scene := (load(MODEL) as PackedScene).instantiate()
	var mi := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mesh := mi.mesh as ArrayMesh
	scene.free()
	return mesh


## Malha de perto: tronco com o material original (toon) e agulhas com o shader do ambiente.
static func _near_mesh(source: ArrayMesh, leaf_mat: Material) -> ArrayMesh:
	var mesh := source.duplicate() as ArrayMesh
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		if mat and mat.resource_name == "Pine_Leaf":
			mesh.surface_set_material(s, leaf_mat)
		elif mat is StandardMaterial3D:
			var trunk := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			trunk.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			trunk.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			trunk.roughness = 0.0  # sem contorno anime
			mesh.surface_set_material(s, trunk)
	return mesh


## Versão distante: tronco + 7 camadas de "saias" irregulares, mesma silhueta larga embaixo.
## COLOR.g guarda a variação claro/escuro (mesma escala do modelo) para o shader.
static func _far() -> ArrayMesh:
	if _far_mesh:
		return _far_mesh
	var mb := MeshBuilder.new()
	mb.cylinder(Transform3D(), 0.14, 0.05, 4.8, Color(0.0, 0.02, 0.0), 5, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for k in 7:
		var y := 0.7 + k * 0.62
		var radius := lerpf(2.05, 0.35, float(k) / 6.0)
		var sides := 9
		for n in sides:
			var a0 := TAU * n / sides + k * 0.4
			var a1 := TAU * (n + 1) / sides + k * 0.4
			var r0 := radius * rng.randf_range(0.8, 1.1)
			var r1 := radius * rng.randf_range(0.8, 1.1)
			var top := Vector3(0, y + 0.75, 0)
			var p0 := Vector3(cos(a0) * r0, y - 0.15 * r0, sin(a0) * r0)
			var p1 := Vector3(cos(a1) * r1, y - 0.15 * r1, sin(a1) * r1)
			var shade := Color(0, 0.0235 * rng.randf_range(0.55, 1.0), 0)
			var nrm := (((p0 + p1) * 0.5 - top).normalized() + Vector3.UP * 0.8).normalized()
			mb.tri_smooth(top, p0, p1, Vector3.UP, nrm, nrm, shade)
	_far_mesh = mb.commit()
	return _far_mesh
