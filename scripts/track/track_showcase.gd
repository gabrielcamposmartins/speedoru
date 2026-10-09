class_name TrackShowcase
extends Node3D
## Vitrine da pista: os balões de personagem (Psyduck e Hamtaro) bem à vista e as imagens de
## assets/outdoors espalhadas com discrição.
##
## * Balões de personagem (blender/build_balloons.py): presos sobre as duas retas mais longas, no fim
##   delas e afastados para o lado de fora, altos o bastante para passar por cima dos prédios e
##   baixos o bastante para ficarem no quadro de quem vem pela reta; virados para a pista, balançam
##   devagar (sobe e desce, giro de poucos graus).
## * Outdoors: algumas placas pequenas em dois postes atrás das barreiras, nas retas, viradas para a
##   pista (só onde há chão livre: fora de arquibancadas, boxes, prédios e escapes).
## * Murais: no alto das paredes de prédios de Mônaco que dão para a pista (a 50–230 m, sem prédio no
##   caminho) e nas paredes laterais das casas e campanários dos vilarejos de Monza.
## * Dirigíveis: um painel curvo com a imagem na traseira do casco (TrackScenery.blimp_mesh).
## As imagens são recortadas no centro para 3:2 (as mais largas perdem as pontas).

const IMAGE_DIR := "res://assets/outdoors/"
const IMAGE_ASPECT := 1.5
const BALLOONS := ["res://assets/track/balloons/psyduck.glb", "res://assets/track/balloons/hamtaro.glb"]
## Altura da base do cesto acima do chão/pista (m) — acima da linha das árvores — e folga sobre os
## prédios em volta.
const BALLOON_BASE := 34.0
## Escala dos balões no jogo (o modelo tem ~27 m; com 1,5 fica com ~40 m, como os balões de formato
## especial de verdade) e a altura do centro do personagem acima da base do cesto.
const BALLOON_SCALE := 1.5
const BALLOON_MID := 24.0
const BALLOON_OVER_ROOFS := 10.0
## Inclinação máxima (tangente) do centro do balão visto de onde o piloto vem.
const BALLOON_MAX_SLOPE := 0.30
## Giro das placas para quem vem pela reta (graus a partir de "de frente para a pista").
const BILLBOARD_TURN := 40.0
const BILLBOARD_SIZE := Vector2(6.0, 4.0)
const BILLBOARD_COUNT := 4
const MURAL_COUNT := 6

static var _images: Array[String] = []
static var _materials := {}

var _balloons: Array = []  # [nó, posição base, yaw base, fase]
## Pontos de vista para conferir (testes): [nome, olho, alvo].
var views: Array = []
var _t := 0.0


# ---------------------------------------------------------------------------
# Imagens
# ---------------------------------------------------------------------------
static func images() -> Array[String]:
	if _images.is_empty():
		var dir := DirAccess.open(IMAGE_DIR)
		if dir:
			for f in dir.get_files():
				var name := f.trim_suffix(".import").trim_suffix(".remap")
				if name.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"] and not _images.has(IMAGE_DIR + name):
					_images.append(IMAGE_DIR + name)
		_images.sort()
	return _images


static func image_count() -> int:
	return images().size()


## Material da imagem k (toon, como o resto do cenário).
static func image_material(k: int) -> Material:
	var list := images()
	if list.is_empty():
		return null
	k = posmod(k, list.size())
	if _materials.has(k):
		return _materials[k]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(list[k]) as Texture2D
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.roughness = 0.9
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[k] = mat
	return mat


## UV do recorte central 3:2 da imagem k.
static func image_uv(k: int) -> Rect2:
	var list := images()
	if list.is_empty():
		return Rect2(0, 0, 1, 1)
	var tex := load(list[posmod(k, list.size())]) as Texture2D
	var a := float(tex.get_width()) / maxf(tex.get_height(), 1.0)
	if a > IMAGE_ASPECT:
		var w := IMAGE_ASPECT / a
		return Rect2((1.0 - w) * 0.5, 0.0, w, 1.0)
	var h := a / IMAGE_ASPECT
	return Rect2(0.0, (1.0 - h) * 0.5, 1.0, h)


## Quadro com a imagem: centro, normal (para onde olha), direção "para cima" e tamanho.
static func add_picture(mb: MeshBuilder, center: Vector3, normal: Vector3, up: Vector3, size: Vector2, k: int) -> void:
	var right := up.cross(normal).normalized()
	var hx := right * size.x * 0.5
	var hy := up.normalized() * size.y * 0.5
	var uv := image_uv(k)
	mb.quad(center - hx - hy, center + hx - hy, center + hx + hy, center - hx + hy, Color.WHITE, normal,
		Vector2(uv.position.x, uv.end.y), Vector2(uv.end.x, uv.end.y), Vector2(uv.end.x, uv.position.y), uv.position)


# ---------------------------------------------------------------------------
# Montagem
# ---------------------------------------------------------------------------
static func build(track: RaceTrack, parent: Node3D) -> void:
	var node := TrackShowcase.new()
	node.name = "Showcase"
	parent.add_child(node)
	var runs := straights(track)
	node._character_balloons(track, runs)
	if image_count() == 0:
		return
	node._billboards(track, runs)
	if track.city:
		node._city_murals(track)
	else:
		node._village_murals()


## Retas da pista (trechos em que a direção muda pouco): [[s inicial, comprimento]], da maior para a menor.
static func straights(track: RaceTrack) -> Array:
	var p := track.path
	var step := 20.0
	var n := int(p.length / step)
	var flat: Array[bool] = []
	for k in n:
		var s := k * step
		var a := p.tangent_at(s - 60.0)
		var b := p.tangent_at(s + 60.0)
		flat.append(absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z))) < deg_to_rad(9.0))
	# Começa num ponto que não é reta (para não partir uma reta que cruza o zero)
	var start := flat.find(false)
	if start < 0:
		return [[0.0, p.length]]
	var runs := []
	var k := 0
	while k < n:
		var i := (start + k) % n
		if flat[i]:
			var len := 0
			while k < n and flat[(start + k) % n]:
				len += 1
				k += 1
			runs.append([i * step, len * step])
		else:
			k += 1
	runs.sort_custom(func(x: Array, y: Array) -> bool: return x[1] > y[1])
	return runs


## A reta de `a` até `b` (mundo) passa por dentro de algum prédio (TrackOffshore._building_blocks)
## mais alto que ela? Só testa os prédios cujo retângulo cruza o da reta.
static func blocked(blocks: Array, a: Vector3, b: Vector3) -> bool:
	var a2 := Vector2(a.x, -a.z)
	var b2 := Vector2(b.x, -b.z)
	var box := Rect2(a2, Vector2.ZERO).expand(b2)
	var hits := []
	for blk in blocks:
		if (blk[1] as Rect2).intersects(box) and float(blk[2]) > minf(a.y, b.y):
			hits.append(blk)
	if hits.is_empty():
		return false
	var steps := maxi(int(a2.distance_to(b2) / 3.0), 1)
	for k in range(1, steps):
		var t := float(k) / steps
		var q := a2.lerp(b2, t)
		var h := lerpf(a.y, b.y, t)
		for blk in hits:
			if float(blk[2]) > h and (blk[1] as Rect2).has_point(q) and Geometry2D.is_point_in_polygon(q, blk[0]):
				return true
	return false


## Obstáculos para a visada: prédios da cidade e as arquibancadas/boxes (pegadas da pista, ~18 m
## acima da pista). Mesmo formato de TrackOffshore._building_blocks: [polígono, retângulo, topo, centro].
static func obstacles(track: RaceTrack) -> Array:
	var out := TrackOffshore._building_blocks(track.city) if track.city else []
	for fp in track.footprints:
		if fp.size() < 3:
			continue
		var poly := PackedVector2Array()
		for v in fp:
			poly.append(Vector2(v.x, -v.y))
		var rect := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			rect = rect.expand(v)
		var c := rect.get_center()
		var y := track.path.frame_at(track.path.project(Vector3(c.x, 0.0, -c.y)).x, 0.0, 0.0).origin.y
		out.append([poly, rect, y + 18.0, c])
	return out


static func ground_y(track: RaceTrack, pos: Vector3) -> float:
	if track.city:
		return track.city.height_at(pos.x, pos.z)
	if track.terrain:
		return track.terrain.height_at(pos.x, pos.z)
	return pos.y


# ---------------------------------------------------------------------------
# Balões de personagem
# ---------------------------------------------------------------------------
func _character_balloons(track: RaceTrack, runs: Array) -> void:
	var spots := _city_balloon_spots(track) if track.city else _field_balloon_spots(track, runs)
	for k in mini(spots.size(), BALLOONS.size()):
		var scene := load(BALLOONS[k]) as PackedScene
		if scene == null:
			continue
		var eye: Vector3 = spots[k][0]
		var pos: Vector3 = spots[k][1]
		var node := scene.instantiate() as Node3D
		node.name = BALLOONS[k].get_file().get_basename().capitalize() + "Balloon"
		add_child(node)
		node.scale = Vector3.ONE * BALLOON_SCALE
		_toon(node)
		var to_eye := Vector3(eye.x - pos.x, 0.0, eye.z - pos.z).normalized()
		# O modelo olha para +Z: gira para encarar quem vem
		var yaw := atan2(to_eye.x, to_eye.z)
		_balloons.append([node, pos, yaw, k * 2.1])
		views.append([node.name, eye, pos + Vector3.UP * BALLOON_MID])
	_update_balloons()


## Circuito no campo: nas duas retas mais longas (afastadas), perto do fim delas e pouco para o
## lado (no cone de visão de quem vem pela reta), alto o bastante para passar por cima das árvores;
## sem arquibancada ou boxes entre a reta e o balão.
func _field_balloon_spots(track: RaceTrack, runs: Array) -> Array:
	var p := track.path
	var occ := obstacles(track)
	var out := []
	var used: Array[float] = []
	for run in runs:
		if out.size() >= BALLOONS.size():
			break
		var s0: float = run[0]
		var length: float = run[1]
		var far := true
		for u in used:
			far = far and absf(fposmod(s0 - u + p.length * 0.5, p.length) - p.length * 0.5) > 600.0
		if not far or length < 140.0:
			continue
		var eye := p.frame_at(s0 + 10.0, 0.0, 3.0).origin
		var found := false
		for frac: float in [0.55, 0.42, 0.7, 0.3]:
			if found:
				break
			var ahead := clampf(length * frac, 150.0, 320.0)
			var first := _open_side(track, s0 + ahead)
			for side: int in [first, -first]:
				if found:
					break
				for extra: float in [25.0, 55.0]:
					var i := p.index_at(s0 + ahead)
					var lat: float = side * (p.half_width(i, side) + track.outer_distance(i, side) + extra)
					var at := p.frame_at(s0 + ahead, lat, 0.0).origin
					var base := maxf(ground_y(track, at), p.frame_at(s0 + ahead, 0.0, 0.0).origin.y) + BALLOON_BASE
					var mid := Vector3(at.x, base + BALLOON_MID, at.z)
					var dist := Vector2(at.x - eye.x, at.z - eye.z).length()
					if (mid.y - eye.y) / maxf(dist, 1.0) > BALLOON_MAX_SLOPE or blocked(occ, mid, eye):
						continue
					out.append([eye, Vector3(at.x, base, at.z)])
					used.append(s0)
					found = true
					break
	return out


## Circuito de rua: procura, ao longo da volta, lugares de céu aberto a 180–260 m à frente e para o
## lado, por cima dos telhados, que se vejam da pista sem prédio no caminho; prefere os que ficam
## sobre o mar (o porto). Os dois melhores, longe um do outro na volta.
func _city_balloon_spots(track: RaceTrack) -> Array:
	var p := track.path
	var blocks := TrackOffshore._building_blocks(track.city)
	var occ := obstacles(track)
	var cands := []
	var s := 0.0
	while s < p.length:
		var eye := p.frame_at(s, 0.0, 3.0).origin
		for ahead: float in [180.0, 240.0]:
			for side: int in [1, -1]:
				for lat_m: float in [90.0, 150.0]:
					var at := p.frame_at(s + ahead, side * lat_m, 0.0).origin
					var ground := track.city.height_at(at.x, at.z)
					var road_y := p.frame_at(s + ahead, 0.0, 0.0).origin.y
					var base := maxf(maxf(ground, road_y) + 30.0,
						TrackOffshore._top_near(blocks, Vector2(at.x, -at.z), 65.0) + BALLOON_OVER_ROOFS)
					var center := Vector3(at.x, base + BALLOON_MID, at.z)
					var dist := Vector2(at.x - eye.x, at.z - eye.z).length()
					var slope := (center.y - eye.y) / maxf(dist, 1.0)
					if slope > BALLOON_MAX_SLOPE + 0.05:
						continue
					if blocked(occ, center, eye):
						continue
					var score := (2.0 if ground < 1.0 else 0.0) - slope * 2.0 - absf(lat_m - 120.0) * 0.002
					cands.append([score, s, eye, Vector3(at.x, base, at.z)])
		s += 40.0
	cands.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	var out := []
	var used: Array[float] = []
	for c in cands:
		if out.size() >= BALLOONS.size():
			break
		var far := true
		for u in used:
			far = far and absf(fposmod(float(c[1]) - u + p.length * 0.5, p.length) - p.length * 0.5) > 900.0
		var spaced := true
		for o in out:
			spaced = spaced and (o[1] as Vector3).distance_to(c[3]) > 300.0
		if far and spaced:
			out.append([c[2], c[3]])
			used.append(float(c[1]))
	return out


## Lado da pista (+1/-1) com mais espaço livre: sem boxes, arquibancadas e prédios altos.
static func _open_side(track: RaceTrack, s: float) -> int:
	var p := track.path
	var best := 1
	var best_score := -INF
	for side in [1, -1]:
		var score := 0.0
		if track.layout.has_pit and side == track.layout.pit_side:
			score -= 50.0
		var q := p.frame_at(s, side * 80.0, 0.0).origin
		var q2 := Vector2(q.x, q.z)
		for fp in track.footprints:
			if Geometry2D.is_point_in_polygon(q2, fp):
				score -= 30.0
		if track.city:
			score -= TrackOffshore._top_near(TrackOffshore._building_blocks(track.city), Vector2(q.x, -q.z), 60.0)
		if score > best_score:
			best_score = score
			best = side
	return best


## Materiais importados do .glb -> toon (como os carros e o cenário).
static func _toon(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if src == null:
				continue
			var mat := StandardMaterial3D.new()
			mat.albedo_color = src.albedo_color
			mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
			mat.roughness = 0.35
			mat.metallic_specular = 0.45
			mat.rim_enabled = true
			mat.rim = 0.3
			mat.rim_tint = 0.6
			mi.set_surface_override_material(s, mat)


func _process(delta: float) -> void:
	_t += delta
	_update_balloons()


## Sobe e desce devagar e gira poucos graus para os lados, sempre de frente para a pista.
func _update_balloons() -> void:
	for b in _balloons:
		var node: Node3D = b[0]
		var pos: Vector3 = b[1]
		var ph: float = b[3]
		node.position = pos + Vector3(sin(_t * 0.11 + ph) * 2.0, sin(_t * 0.35 + ph) * 1.4, cos(_t * 0.09 + ph) * 2.0)
		node.rotation = Vector3(sin(_t * 0.4 + ph) * 0.02, float(b[2]) + sin(_t * 0.16 + ph) * 0.14, cos(_t * 0.33 + ph) * 0.02)
		node.scale = Vector3.ONE * BALLOON_SCALE


# ---------------------------------------------------------------------------
# Outdoors
# ---------------------------------------------------------------------------
func _billboards(track: RaceTrack, runs: Array) -> void:
	var p := track.path
	var mb_posts := MeshBuilder.new()
	var placed: Array[Vector3] = []
	var pictures := {}  # imagem -> MeshBuilder
	var img := 0
	# Trechos quase retos (de onde a placa se vê de longe), dos mais longos aos mais curtos
	var spots := []
	for run in runs:
		var length: float = run[1]
		if length >= 60.0:
			spots.append(float(run[0]) + length * 0.6)
	for s: float in spots:
		if placed.size() >= BILLBOARD_COUNT:
			break
		var first := _open_side(track, s)
		for side: int in [first, -first]:
			var i := p.index_at(s)
			var lat: float = side * (p.half_width(i, side) + track.outer_distance(i, side) + 4.0)
			var frame := p.frame_at(s, lat, 0.0)
			var at := frame.origin
			if not _free_ground(track, at, 4.0):
				continue
			var near := false
			for q in placed:
				near = near or q.distance_to(at) < 300.0
			if near:
				continue
			var g := ground_y(track, at)
			# De frente para a pista e girada para quem vem pela reta
			var inward: Vector3 = -frame.basis.x * side
			var back: Vector3 = -frame.basis.z
			var normal: Vector3 = (inward * cos(deg_to_rad(BILLBOARD_TURN)) + back * sin(deg_to_rad(BILLBOARD_TURN)))
			normal = Vector3(normal.x, 0.0, normal.z).normalized()
			var right := Vector3.UP.cross(normal).normalized()
			# Por cima da tela de proteção
			var bottom := maxf(g, frame.origin.y) + 3.6
			var c := Vector3(at.x, bottom + BILLBOARD_SIZE.y * 0.5, at.z)
			var look := Basis.looking_at(-normal)
			for sx: float in [-1.0, 1.0]:
				var post: Vector3 = Vector3(at.x, g, at.z) + right * sx * BILLBOARD_SIZE.x * 0.38 - normal * 0.12
				var hgt := bottom + BILLBOARD_SIZE.y * 0.4 - g
				mb_posts.box(Transform3D(look, post + Vector3.UP * hgt * 0.5), Vector3(0.2, hgt, 0.2), Color(0.3, 0.31, 0.34))
			mb_posts.box(Transform3D(look, c - normal * 0.08), Vector3(BILLBOARD_SIZE.x + 0.3, BILLBOARD_SIZE.y + 0.3, 0.12),
				Color(0.16, 0.17, 0.2))
			if not pictures.has(img):
				pictures[img] = MeshBuilder.new()
			add_picture(pictures[img], c, normal, Vector3.UP, BILLBOARD_SIZE, img)
			placed.append(at)
			views.append(["Outdoor%d" % placed.size(), p.frame_at(s - 90.0, 0.0, 2.5).origin, c])
			img = (img + 1) % image_count()
			break
	_commit("Billboards", mb_posts, pictures)


## Chão livre para uma placa: fora da pista e dos escapes, de arquibancadas/boxes e de prédios.
static func _free_ground(track: RaceTrack, at: Vector3, radius: float) -> bool:
	if not CityProps.clear_of_track(track, at, radius * 0.5):
		return false
	var a := Vector2(at.x, at.z)
	for fp in track.footprints:
		if Geometry2D.is_point_in_polygon(a, fp):
			return false
		for e in fp.size():
			if Geometry2D.get_closest_point_to_segment(a, fp[e], fp[(e + 1) % fp.size()]).distance_to(a) < radius:
				return false
	if track.city:
		var d := Vector2(at.x, -at.z)
		for blk in TrackOffshore._building_blocks(track.city):
			if (blk[1] as Rect2).grow(radius).has_point(d) and Geometry2D.is_point_in_polygon(d, blk[0]):
				return false
		# Chão da cidade perto do nível da pista (não no mar nem num morro)
		var g := track.city.height_at(at.x, at.z)
		if g < 0.5 or absf(g - track.path.frame_at(track.path.project(at, false).x, 0, 0).origin.y) > 4.0:
			return false
	return true


func _commit(name: String, structure: MeshBuilder, pictures: Dictionary) -> void:
	if structure.is_empty() and pictures.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = name
	var mesh := structure.commit(null, TrackMaterials.structure())
	for k in pictures:
		(pictures[k] as MeshBuilder).commit(mesh, image_material(k))
	mi.mesh = mesh
	add_child(mi)


# ---------------------------------------------------------------------------
# Murais
# ---------------------------------------------------------------------------
## Mônaco: no alto de paredes viradas para a pista, a 50–230 m dela, sem prédio no caminho.
func _city_murals(track: RaceTrack) -> void:
	var p := track.path
	var blocks := TrackOffshore._building_blocks(track.city)
	# Pontos da pista a cada 12 m (x, -z dos dados) para achar o trecho mais perto de cada parede
	var samples: Array[Vector2] = []
	var step := 12.0
	var n_samples := int(p.length / step)
	for k in n_samples:
		var q := p.position_at(k * step)
		samples.append(Vector2(q.x, -q.z))
	var candidates := []
	for b in track.city.data["buildings"]:
		var base: float = b["b"]
		var top: float = b["t"]
		if top - base < 18.0:
			continue
		var pts: Array = b["p"]
		var poly := PackedVector2Array()
		for i in range(0, pts.size(), 2):
			poly.append(Vector2(pts[i], pts[i + 1]))
		var centroid := Vector2.ZERO
		for v in poly:
			centroid += v
		centroid /= poly.size()
		var near_k := -1
		var near_d := INF
		for k in n_samples:
			var d := samples[k].distance_squared_to(centroid)
			if d < near_d:
				near_d = d
				near_k = k
		if sqrt(near_d) > 260.0:
			continue
		for e in poly.size():
			var a := poly[e]
			var c := poly[(e + 1) % poly.size()]
			var edge := c - a
			if edge.length() < 12.0:
				continue
			var mid := (a + c) * 0.5
			var n := Vector2(edge.y, -edge.x).normalized()
			if n.dot(mid - centroid) < 0.0:
				n = -n
			# Trecho da pista mais perto da parede (perto do mais próximo do prédio)
			var best_k := near_k
			var best_d := INF
			for dk in range(-12, 13):
				var kk := posmod(near_k + dk, n_samples)
				var d := samples[kk].distance_squared_to(mid)
				if d < best_d:
					best_d = d
					best_k = kk
			var road := p.position_at(best_k * step)
			var to_road := Vector2(road.x - mid.x, -road.z - mid.y)
			var dist := to_road.length()
			if dist < 50.0 or dist > 230.0 or n.dot(to_road / dist) < 0.8:
				continue
			var w := minf(edge.length() * 0.6, 13.0)
			var h := minf(w / IMAGE_ASPECT, (top - base) * 0.35)
			w = h * IMAGE_ASPECT
			var cy := top - 2.0 - h * 0.5
			var center := TrackCity.to_world(mid.x, mid.y, cy) + TrackCity.to_world(n.x, n.y, 0.0) * 0.12
			# Visto da pista (por cima dos outros prédios), sem contar o próprio
			var eye := road + Vector3.UP * 3.0
			var probe := center + TrackCity.to_world(n.x, n.y, 0.0) * 1.5
			if blocked(blocks, probe, eye):
				continue
			candidates.append([absf(dist - 120.0), best_k * step, center, TrackCity.to_world(n.x, n.y, 0.0), Vector2(w, h), eye])
	candidates.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	_place_murals(candidates, p.length, 350.0, "CityMurals")


## Monza: paredes laterais (sem janelas) das casas e dos campanários dos vilarejos, viradas para o
## circuito (TrackScenery.mural_walls).
func _village_murals() -> void:
	var candidates := []
	for k in TrackScenery.mural_walls.size():
		var w: Array = TrackScenery.mural_walls[k]
		candidates.append([float(k), float(k) * 1000.0, w[0], w[1], w[2]])
	_place_murals(candidates, 1e9, 0.0, "VillageMurals")


## Escolhe até MURAL_COUNT murais (afastados `spacing` m ao longo da pista) com imagens diferentes.
func _place_murals(candidates: Array, length: float, spacing: float, name: String) -> void:
	var chosen: Array[float] = []
	var pictures := {}
	var frames := MeshBuilder.new()
	var img := 3
	for c in candidates:
		if chosen.size() >= MURAL_COUNT:
			break
		var s: float = c[1]
		var ok := true
		for u in chosen:
			ok = ok and absf(fposmod(s - u + length * 0.5, length) - length * 0.5) >= spacing
		if not ok:
			continue
		var center: Vector3 = c[2]
		var normal: Vector3 = c[3]
		var size: Vector2 = c[4]
		frames.box(Transform3D(Basis.looking_at(-normal), center - normal * 0.05), Vector3(size.x + 0.5, size.y + 0.5, 0.1),
			Color(0.2, 0.18, 0.17))
		if not pictures.has(img):
			pictures[img] = MeshBuilder.new()
		add_picture(pictures[img], center + normal * 0.02, normal, Vector3.UP, size, img)
		chosen.append(s)
		var eye: Vector3 = c[5] if c.size() > 5 else center + normal * maxf(size.x * 4.0, 30.0) + Vector3.DOWN * size.y
		views.append(["%s%d" % [name, chosen.size()], eye, center])
		img = (img + 1) % image_count()
	_commit(name, frames, pictures)
