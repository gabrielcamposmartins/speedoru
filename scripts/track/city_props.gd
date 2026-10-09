class_name CityProps
extends RefCounted
## Detalhes da cidade junto à pista (circuito de rua, dados da TrackCity): mobiliário urbano nas
## calçadas e praças (bancos, floreiras, frades, lixeiras; na orla, mesas de café com guarda-sóis)
## e árvores nos jardins perto da pista. Só em lugares livres: chão de calçada/praça (ou jardim, para
## as árvores), fora dos prédios, das ruas, das arquibancadas e do mar, e além das barreiras.

## Faixa (m além da borda da pista) onde entram os objetos e as árvores.
const PROP_BAND := Vector2(4.0, 26.0)
const TREE_BAND := Vector2(7.0, 55.0)
## Passo ao longo da pista (m) entre tentativas.
const STEP := 4.0
const GRID := 20.0

enum Kind { BENCH, PLANTER, BOLLARDS, BIN, CAFE_RED, CAFE_GREEN, CAFE_BLUE }

var city: TrackCity
var track: RaceTrack
var _buildings := {}   # célula -> [polígono, retângulo]
var _streets := {}     # célula -> [a, b, meia-largura]
var _stands: Array = []  # contornos das arquibancadas/boxes (dados)
var _used := {}        # célula de 3 m já ocupada


static func build(p_track: RaceTrack, p_city: TrackCity, parent: Node3D) -> void:
	var cp := CityProps.new()
	cp.track = p_track
	cp.city = p_city
	cp._index()
	var root := Node3D.new()
	root.name = "CityProps"
	parent.add_child(root)
	cp._furniture(root)
	cp._trees(root)


# ---------------------------------------------------------------------------
# Lugares livres
# ---------------------------------------------------------------------------
func _index() -> void:
	for b in city.data["buildings"]:
		var pts: Array = b["p"]
		var poly := PackedVector2Array()
		for i in range(0, pts.size(), 2):
			poly.append(Vector2(pts[i], pts[i + 1]))
		var rect := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			rect = rect.expand(v)
		_add(_buildings, rect.grow(1.0), [poly, rect.grow(1.0)])
	for st in city.data["streets"]:
		var p: Array = st["p"]
		var half: float = float(st["w"]) * 0.5 + 0.8
		for i in range(0, p.size() / 3 - 1):
			var a := Vector2(p[i * 3], p[i * 3 + 1])
			var b := Vector2(p[i * 3 + 3], p[i * 3 + 4])
			# Trechos de rua por onde passa a própria pista não contam (a calçada ao lado é livre)
			var mid := (a + b) * 0.5
			var pr := track.path.project(Vector3(mid.x, 0.0, -mid.y), false)
			if pr.y != INF and absf(pr.y) < track.path.half_width(track.path.index_at(pr.x), 1 if pr.y >= 0.0 else -1) + 3.0:
				continue
			var rect := Rect2(a, Vector2.ZERO).expand(b).grow(half)
			_add(_streets, rect, [a, b, half])
	for fp in track.footprints:
		var poly := PackedVector2Array()
		for v in fp:
			poly.append(Vector2(v.x, -v.y))
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()
		_stands.append(poly)


## Lado (m) dos blocos de instâncias de add_chunked.
const CHUNK := 128.0
## Árvores da cidade: folhas soltas até esta distância (m), bolhas simples depois.
const TREE_LOD := 190.0


## Cria os MultiMesh de uma lista de instâncias divididos em blocos de CHUNK m, um por bloco e por
## LOD. O Godot mede o visibility range até o centro de cada MultiMesh e recorta (câmera e cascatas
## de sombra) pela caixa dele inteira: um MultiMesh só para a cidade toda nunca trocaria de LOD e
## iria inteiro para cada cascata de sombra. `lods` = lista de [malha, material, início, fim,
## sombra] (início/fim do visibility range; 0 = sem limite). `data` = INSTANCE_CUSTOM (ou vazio).
## Devolve os MultiMeshInstance3D criados.
static func add_chunked(root: Node3D, prefix: String, xfs: Array, data: Array, lods: Array) -> Array[MultiMeshInstance3D]:
	var chunks := {}
	for i in xfs.size():
		var o: Vector3 = (xfs[i] as Transform3D).origin
		var key := Vector2i(floori(o.x / CHUNK), floori(o.z / CHUNK))
		if not chunks.has(key):
			chunks[key] = [[] as Array[Transform3D], [] as Array[Color]]
		chunks[key][0].append(xfs[i])
		chunks[key][1].append(data[i] if not data.is_empty() else Color())
	var out: Array[MultiMeshInstance3D] = []
	for key: Vector2i in chunks:
		var part: Array[Transform3D] = chunks[key][0]
		var buffer := PackedFloat32Array()
		if not data.is_empty():
			buffer = Grandstands.pack_buffer(part, chunks[key][1])
		for l in lods.size():
			var lod: Array = lods[l]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = not data.is_empty()
			mm.mesh = lod[0]
			mm.instance_count = part.size()
			if data.is_empty():
				for i in part.size():
					mm.set_instance_transform(i, part[i])
			else:
				mm.buffer = buffer
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d%s" % [prefix, key.x, key.y, "" if l == 0 else "_lod%d" % l]
			mmi.multimesh = mm
			if lod[1] != null:
				mmi.material_override = lod[1]
			# Só o primeiro LOD guarda as posições (os testes contam cada instância uma vez)
			if l == 0:
				mmi.set_meta("points", origins(part))
			if float(lod[2]) > 0.0:
				mmi.visibility_range_begin = lod[2]
				mmi.visibility_range_begin_margin = 25.0
			if float(lod[3]) > 0.0:
				mmi.visibility_range_end = lod[3]
				mmi.visibility_range_end_margin = 25.0
			if not lod[4]:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
			out.append(mmi)
	return out


## Posições das instâncias (metadado "points" dos MultiMesh, para os testes: sem janela o
## renderizador é vazio e não devolve as transformações).
static func origins(xfs: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for xf: Transform3D in xfs:
		out.append(xf.origin)
	return out


static func _add(grid: Dictionary, rect: Rect2, item: Array) -> void:
	for gx in range(floori(rect.position.x / GRID), floori(rect.end.x / GRID) + 1):
		for gy in range(floori(rect.position.y / GRID), floori(rect.end.y / GRID) + 1):
			var key := Vector2i(gx, gy)
			if not grid.has(key):
				grid[key] = []
			grid[key].append(item)


## Tipo de chão (classe e cobertura da grade) no ponto, ou -1 fora da área / no mar.
func _ground(d: Vector2) -> int:
	if not city.area.has_point(d):
		return -1
	var ix := clampi(roundi((d.x - city.area.position.x) / city.cell), 0, city.nx - 1)
	var iy := clampi(roundi((d.y - city.area.position.y) / city.cell), 0, city.ny - 1)
	var i := iy * city.nx + ix
	if city.heights[i] < 0.6:
		return -1
	if city.cover[i] == 1:
		return 10  # jardim
	return city.cls[i]


## O ponto (mundo) fica fora da pista e de tudo o que é dela, em qualquer trecho do circuito (em
## Mônaco vários trechos correm lado a lado): atrás da barreira, além da faixa dos boxes e longe
## das garagens. `margin` = folga extra (m), por exemplo o raio da copa.
static func clear_of_track(track: RaceTrack, pos: Vector3, margin: float) -> bool:
	var p := track.path
	var pr := p.project(pos, false)
	if pr.y == INF:
		return true  # longe de qualquer trecho
	var i := p.index_at(pr.x)
	var side := 1 if pr.y >= 0.0 else -1
	var need := p.half_width(i, side) + track.outer_distance(i, side) + 0.5
	var lay := track.layout
	if lay.has_pit and side == lay.pit_side:
		if track.pit_width[i] > 0.0:
			need = maxf(need, p.half_width(i, side) + track.pit_width[i] + 3.0)
		var ds := fposmod(pr.x - lay.garage_center_s + p.length * 0.5, p.length) - p.length * 0.5
		if absf(ds) < lay.pit_building_length * 0.5 + 20.0:
			need = maxf(need, p.half_width(i, side) + RaceTrack.PIT_WALL_STRIP + lay.pit_lane_width + PitComplex.DEPTH + 4.0)
	return absf(pr.y) > need + margin


## Raio de cima para baixo no ponto: o primeiro piso tem de ser o chão da cidade (não pista, escape,
## faixa ou chão dos boxes, barreira, muro, arquibancada). Sem nada embaixo também vale.
func _on_city_ground(d: Vector2) -> bool:
	var space := track.get_world_3d().direct_space_state if track.is_inside_tree() else null
	if space == null:
		return true
	var h := city.height_at(d.x, -d.y)
	var q := PhysicsRayQueryParameters3D.create(Vector3(d.x, h + 8.0, -d.y), Vector3(d.x, h - 4.0, -d.y))
	var hit := space.intersect_ray(q)
	return hit.is_empty() or String((hit["collider"] as Node).name) == "GroundCollision"


func _free(d: Vector2, radius: float) -> bool:
	if not clear_of_track(track, Vector3(d.x, 0.0, -d.y), radius) or not _on_city_ground(d):
		return false
	var key := Vector2i(floori(d.x / GRID), floori(d.y / GRID))
	for item in _buildings.get(key, []):
		if (item[1] as Rect2).has_point(d) and (Geometry2D.is_point_in_polygon(d, item[0]) or _near_poly(d, item[0], radius + 0.8)):
			return false
	for item in _streets.get(key, []):
		if d.distance_to(Geometry2D.get_closest_point_to_segment(d, item[0], item[1])) < float(item[2]) + radius:
			return false
	for poly in _stands:
		if Geometry2D.is_point_in_polygon(d, poly):
			return false
	var cell := Vector2i(floori(d.x / 3.0), floori(d.y / 3.0))
	if _used.has(cell):
		return false
	return true


static func _near_poly(d: Vector2, poly: PackedVector2Array, dist: float) -> bool:
	for k in poly.size():
		if d.distance_to(Geometry2D.get_closest_point_to_segment(d, poly[k], poly[(k + 1) % poly.size()])) < dist:
			return true
	return false


func _mark(d: Vector2) -> void:
	_used[Vector2i(floori(d.x / 3.0), floori(d.y / 3.0))] = true


## Pontos candidatos dos dois lados da pista: [posição (mundo), virado para a pista (base), s, distância].
func _candidates(band: Vector2, rng: RandomNumberGenerator, chance: float) -> Array:
	var out := []
	var p := track.path
	var s := 0.0
	while s < p.length:
		s += STEP * rng.randf_range(0.7, 1.3)
		if city.in_tunnel(s, 30.0):
			continue
		var i := p.index_at(s)
		for side: int in [1, -1]:
			if rng.randf() > chance:
				continue
			var edge := p.half_width(i, side)
			var dist := rng.randf_range(band.x, band.y)
			var pos := p.frame_at(s, side * (edge + dist), 0.0).origin
			var toward := p.frame_at(s, 0.0, 0.0).origin - pos
			out.append([pos, Basis(Vector3.UP, atan2(-toward.x, -toward.z) + rng.randf_range(-0.15, 0.15)), s, dist])
	return out


# ---------------------------------------------------------------------------
# Mobiliário
# ---------------------------------------------------------------------------
func _furniture(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var lists := {}
	for k in Kind.size():
		lists[k] = [] as Array[Transform3D]
	for cand in _candidates(PROP_BAND, rng, 0.8):
		var pos: Vector3 = cand[0]
		var d := Vector2(pos.x, -pos.z)
		var ground := _ground(d)
		if not ground in [0, 1, 4]:
			continue  # só calçada e praça (a faixa "sob a pista" além da borda é calçada)
		if not _free(d, 1.2):
			continue
		var h := city.height_at(pos.x, pos.z)
		var kind: int
		var r := rng.randf()
		if h < 4.5 and r < 0.45:
			kind = [Kind.CAFE_RED, Kind.CAFE_GREEN, Kind.CAFE_BLUE][rng.randi() % 3]  # orla do porto
		elif r < 0.5:
			kind = Kind.BENCH
		elif r < 0.72:
			kind = Kind.PLANTER
		elif r < 0.88:
			kind = Kind.BOLLARDS
		else:
			kind = Kind.BIN
		lists[kind].append(Transform3D(cand[1], Vector3(pos.x, h, pos.z)))
		_mark(d)
	var mat := TrackMaterials.structure()
	for k in lists:
		var xfs: Array[Transform3D] = lists[k]
		if xfs.is_empty():
			continue
		# Coisas pequenas: só até 220 m, e só os guarda-sóis fazem sombra que se nota
		var shadow: bool = k in [Kind.CAFE_RED, Kind.CAFE_GREEN, Kind.CAFE_BLUE, Kind.PLANTER]
		add_chunked(root, "Props_%s" % Kind.keys()[k], xfs, [], [[_mesh(k), mat, 0.0, 220.0, shadow]])


## Modelos (frente para -Z, que fica virada para a pista).
static func _mesh(kind: int) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var iron := Color(0.16, 0.2, 0.18)
	var wood := Color(0.55, 0.36, 0.2)
	var stone := Color(0.82, 0.79, 0.72)
	match kind:
		Kind.BENCH:
			for k in 3:
				mb.box(Transform3D(Basis(), Vector3(0, 0.45, -0.18 + k * 0.14)), Vector3(1.8, 0.05, 0.11), wood)
			for k in 2:
				mb.box(Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 0.75 + k * 0.14, 0.27 + k * 0.03)), Vector3(1.8, 0.1, 0.04), wood)
			for x: float in [-0.75, 0.75]:
				mb.box(Transform3D(Basis(), Vector3(x, 0.22, 0.0)), Vector3(0.06, 0.44, 0.5), iron)
				mb.box(Transform3D(Basis(), Vector3(x, 0.62, 0.3)), Vector3(0.05, 0.5, 0.05), iron)
		Kind.PLANTER:
			mb.box(Transform3D(Basis(), Vector3(0, 0.3, 0)), Vector3(1.4, 0.6, 1.4), stone)
			mb.box(Transform3D(Basis(), Vector3(0, 0.62, 0)), Vector3(1.5, 0.06, 1.5), stone.lightened(0.08))
			mb.blob(Vector3(0, 0.95, 0), Vector3(0.62, 0.45, 0.62), Color(0.2, 0.42, 0.16), 8, 5, 0.3)
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for f in 9:
				var a := rng.randf() * TAU
				var r := rng.randf_range(0.2, 0.55)
				var col: Color = [Color(0.9, 0.15, 0.25), Color(1.0, 0.75, 0.2), Color(0.95, 0.5, 0.75), Color(1, 1, 1)][f % 4]
				mb.blob(Vector3(cos(a) * r, 1.15 + rng.randf() * 0.2, sin(a) * r), Vector3(0.1, 0.08, 0.1), col, 5, 3)
		Kind.BOLLARDS:
			for x: float in [-1.2, 0.0, 1.2]:
				mb.cylinder(Transform3D(Basis(), Vector3(x, 0, 0)), 0.1, 0.09, 0.85, iron, 8)
				mb.blob(Vector3(x, 0.88, 0), Vector3(0.1, 0.07, 0.1), Color(0.75, 0.6, 0.2), 6, 3)
		Kind.BIN:
			mb.cylinder(Transform3D(), 0.26, 0.28, 0.9, Color(0.12, 0.3, 0.2), 10)
			mb.cylinder(Transform3D(Basis(), Vector3(0, 0.9, 0)), 0.3, 0.27, 0.08, Color(0.2, 0.22, 0.22), 10)
		Kind.CAFE_RED, Kind.CAFE_GREEN, Kind.CAFE_BLUE:
			var shade: Color = {Kind.CAFE_RED: Color(0.82, 0.16, 0.16), Kind.CAFE_GREEN: Color(0.16, 0.5, 0.3),
				Kind.CAFE_BLUE: Color(0.18, 0.35, 0.7)}[kind]
			# Guarda-sol de gomos (duas cores), mastro, mesa redonda e duas cadeiras
			mb.cylinder(Transform3D(), 0.04, 0.04, 2.3, Color(0.85, 0.85, 0.82), 6)
			for g in 8:
				var a0 := TAU * g / 8.0
				var a1 := TAU * (g + 1) / 8.0
				var top := Vector3(0, 2.55, 0)
				var c: Color = shade if g % 2 == 0 else Color(0.96, 0.95, 0.9)
				mb.tri(top, Vector3(cos(a1) * 1.4, 2.1, sin(a1) * 1.4), Vector3(cos(a0) * 1.4, 2.1, sin(a0) * 1.4), c)
				mb.tri(top, Vector3(cos(a0) * 1.4, 2.1, sin(a0) * 1.4), Vector3(cos(a1) * 1.4, 2.1, sin(a1) * 1.4), c.darkened(0.25))
			mb.cylinder(Transform3D(Basis(), Vector3(0, 0.72, 0)), 0.42, 0.42, 0.04, Color(0.92, 0.92, 0.9), 12)
			mb.cylinder(Transform3D(), 0.05, 0.05, 0.72, iron, 6)
			for side: float in [-1.0, 1.0]:
				var cx := side * 0.72
				mb.box(Transform3D(Basis(), Vector3(cx, 0.45, 0)), Vector3(0.42, 0.04, 0.42), iron)
				mb.box(Transform3D(Basis(), Vector3(cx + side * 0.2, 0.7, 0)), Vector3(0.04, 0.5, 0.42), iron)
				for lx: float in [-0.18, 0.18]:
					for lz: float in [-0.18, 0.18]:
						mb.box(Transform3D(Basis(), Vector3(cx + lx, 0.22, lz)), Vector3(0.03, 0.45, 0.03), iron)
	return mb.commit()


# ---------------------------------------------------------------------------
# Árvores junto à pista (jardins e praças)
# ---------------------------------------------------------------------------
func _trees(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2626
	var by_species := {}
	for cand in _candidates(TREE_BAND, rng, 0.85):
		var pos: Vector3 = cand[0]
		var d := Vector2(pos.x, -pos.z)
		var ground := _ground(d)
		# Jardins; nas praças e calçadas, árvores de rua de vez em quando
		if ground != 10 and not (ground in [0, 1, 4] and rng.randf() < 0.3):
			continue
		if not _free(d, 2.5):
			continue
		var q := rng.randf()
		var species: int = TrackTrees.Species.STONE_PINE if q < 0.3 else (TrackTrees.Species.OAK if q < 0.6 else
			(TrackTrees.Species.CYPRESS if q < 0.8 else TrackTrees.Species.BUSH))
		var s := rng.randf_range(0.6, 0.9)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.12), s))
		if not by_species.has(species):
			by_species[species] = [[] as Array[Transform3D], [] as Array[Color]]
		by_species[species][0].append(Transform3D(basis, Vector3(pos.x, city.height_at(pos.x, pos.z) - 0.2, pos.z)))
		by_species[species][1].append(Color(rng.randf(), rng.randf(), rng.randf(), 0.0))
		_mark(d)
	add_trees(root, "TracksideTrees", by_species)


## Árvores da cidade por espécie (espécie -> [transformações, INSTANCE_CUSTOM]): folhas soltas
## (TrackLeaves.city_tree_mesh) até TREE_LOD m, bolhas simples sem sombra depois.
static func add_trees(root: Node3D, prefix: String, by_species: Dictionary) -> void:
	TrackTrees.ensure_meshes()
	for species: int in by_species:
		add_chunked(root, "%s_%d" % [prefix, species], by_species[species][0], by_species[species][1], [
			[TrackLeaves.city_tree_mesh(species), TrackLeaves.leafy_material(), 0.0, TREE_LOD, true],
			[TrackTrees.mesh(species, false), TrackMaterials.tree(), TREE_LOD, 0.0, false]])
