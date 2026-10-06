class_name TrackProps
extends RefCounted
## Objetos ao redor da pista: postes de iluminação, painéis de anúncio, pórticos sobre a pista
## (anúncios e luzes de largada), placas de frenagem, setas nas curvas fechadas e placas dos boxes.
## Tudo vai para poucas malhas (estrutura, lâmpadas, anúncios) para gastar poucas draw calls.

const STEEL := Color(0.62, 0.65, 0.72)
const STEEL_DARK := Color(0.32, 0.34, 0.4)
const LAMP := Color(1.0, 0.97, 0.85)
## Curvas com raio menor que isso recebem setas (chevrons) do lado de fora.
const CHEVRON_MAX_RADIUS := 45.0


static func build(track: RaceTrack, parent: Node3D) -> void:
	var structure := MeshBuilder.new()
	var lamps := MeshBuilder.new()
	var ads := MeshBuilder.new()
	var cloth := MeshBuilder.new()
	for f in track.layout.features:
		if f == null:
			continue
		match f.kind:
			TrackFeature.Kind.LIGHTS:
				_lights(track, f, structure, lamps, cloth, parent)
			TrackFeature.Kind.BILLBOARD:
				_billboards(track, f, structure, ads)
			TrackFeature.Kind.AD_BRIDGE:
				_bridge(track, f, structure, ads, parent, false)
			TrackFeature.Kind.START_GANTRY:
				_bridge(track, f, structure, ads, parent, true)
			TrackFeature.Kind.BUNTING:
				_bunting(track, f, structure, cloth)
			TrackFeature.Kind.BRAKE_MARKERS:
				for side in f.sides():
					for k in 4:
						var dist: float = [200.0, 150.0, 100.0, 50.0][k]
						var sign_id: int = [TrackAds.Sign.BRAKE_200, TrackAds.Sign.BRAKE_150, TrackAds.Sign.BRAKE_100, TrackAds.Sign.BRAKE_50][k]
						_sign(track, f.s_start - dist, side, 2.2, sign_id, structure, ads)
	_chevrons(track, structure, ads)
	_pit_signs(track, structure, ads)

	var mi := MeshInstance3D.new()
	mi.name = "Props"
	var mesh := structure.commit(null, TrackMaterials.structure())
	lamps.commit(mesh, TrackMaterials.lamp(track.lamp_energy))
	ads.commit(mesh, TrackMaterials.ads())
	TrackFlags.commit_to(cloth, mesh)
	mi.mesh = mesh
	parent.add_child(mi)


## Refletor (SpotLight3D) do grupo "night_lights", apontado de `pos` para `target`.
static func night_light(parent: Node3D, pos: Vector3, target: Vector3, energy := 5.5, angle := 52.0) -> SpotLight3D:
	var holder := parent.get_node_or_null("NightLights") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "NightLights"
		parent.add_child(holder)
	var light := SpotLight3D.new()
	light.light_color = Color(1.0, 0.92, 0.78)
	light.light_energy = energy
	light.set_meta("base_energy", energy)
	light.spot_range = pos.distance_to(target) * 1.8 + 10.0
	light.spot_angle = angle
	light.spot_attenuation = 0.6
	light.shadow_enabled = false
	light.light_specular = 0.3
	light.visible = false
	light.add_to_group("night_lights")
	holder.add_child(light)
	light.global_transform = Transform3D(Basis.looking_at(target - pos), pos)
	return light


## Distância extra ocupada por arquibancadas naquele ponto/lado (para não plantar postes nelas).
static func _stand_clearance(track: RaceTrack, s: float, side: int) -> float:
	var extra := 0.0
	for f in track.layout.features:
		if f and (f.kind == TrackFeature.Kind.GRANDSTAND or f.kind == TrackFeature.Kind.SPECTATORS) \
				and side in f.sides() and track.in_span(s, f.s_start - 6.0, f.s_end + 6.0):
			var depth := Grandstands.ROW_DEPTH if f.kind == TrackFeature.Kind.GRANDSTAND else 1.0
			extra = maxf(extra, f.distance + f.rows * depth + 4.0)
	return extra


## Bandeirolas entre postes vizinhos quando estão a menos disso (m).
const BUNTING_MAX_SPAN := 75.0


static func _lights(track: RaceTrack, f: TrackFeature, mb: MeshBuilder, lamps: MeshBuilder, cloth: MeshBuilder,
		parent: Node3D) -> void:
	var p := track.path
	var step := maxi(int(f.spacing / p.spacing), 1)
	for side in f.sides():
		var prev := Vector3.INF
		for i in track.span_indices(f.s_start, f.s_end, step):
			var s := p.s_at(i)
			var d := track.outer_distance(i, side) + 1.5 + f.distance + _stand_clearance(track, s, side)
			var base := track.edge_point(i, side, d)
			var to_track := -p.lefts[i] * side
			var height := 18.0
			if prev != Vector3.INF and prev.distance_to(base) < BUNTING_MAX_SPAN:
				TrackFlags.bunting(cloth, prev + Vector3.UP * 12.0, base + Vector3.UP * 12.0, 2.2, 0.9, i)
			prev = base
			mb.posts().cylinder(Transform3D(Basis(), base), 0.32, 0.18, height, STEEL, 8)
			mb.posts().box(Transform3D(Basis(), base + Vector3.UP * 0.4), Vector3(0.9, 0.8, 0.9), STEEL_DARK)
			# Braço com 4 refletores inclinados para a pista
			var head := base + Vector3.UP * height + to_track * 0.6
			var basis := Basis(p.tangents[i], Vector3.UP, to_track)
			mb.box(Transform3D(basis, head), Vector3(4.2, 0.25, 0.3), STEEL_DARK)
			var tilt := basis * Basis(Vector3.RIGHT, deg_to_rad(35.0))
			for k in 4:
				var c := head + p.tangents[i] * (k - 1.5) * 1.0 + to_track * 0.35 + Vector3.UP * 0.35
				mb.box(Transform3D(tilt, c), Vector3(0.8, 0.6, 0.25), STEEL_DARK)
				lamps.box(Transform3D(tilt, c + tilt.z * 0.13), Vector3(0.68, 0.48, 0.02), LAMP)
			# Luz de verdade para a noite (desligada de dia; RaceTrack.apply_mood liga)
			night_light(parent, head + to_track * 0.6, p.points[i] + to_track * 0.0 - p.lefts[i] * side * 2.0)


static func _billboards(track: RaceTrack, f: TrackFeature, mb: MeshBuilder, ads: MeshBuilder) -> void:
	var p := track.path
	var step := maxi(int(f.spacing / p.spacing), 1)
	var n := 0
	for side in f.sides():
		for i in track.span_indices(f.s_start, f.s_end, step):
			var d := track.outer_distance(i, side) + 2.0 + f.distance
			var base := track.edge_point(i, side, d)
			var to_track := -p.lefts[i] * side
			# Virado para quem se aproxima, levemente para a pista
			var normal := (-p.tangents[i] * 0.75 + to_track * 0.66).normalized()
			_panel(base, normal, Vector2(10.0, 2.6), 2.2, f.variant + n * 5, mb, ads)
			n += 1


## Painel de anúncio sobre duas pernas: base no chão, normal = face com o anúncio.
static func _panel(base: Vector3, normal: Vector3, size: Vector2, lift: float, brand: int,
		mb: MeshBuilder, ads: MeshBuilder) -> void:
	var right := Vector3.UP.cross(normal).normalized()
	var center := base + Vector3.UP * (lift + size.y * 0.5)
	var basis := Basis(right, Vector3.UP, normal)
	mb.box(Transform3D(basis, center - normal * 0.12), Vector3(size.x + 0.3, size.y + 0.3, 0.2), STEEL_DARK)
	for x: float in [-0.32, 0.32]:
		mb.posts().box(Transform3D(basis, base + right * size.x * x + Vector3.UP * (lift * 0.5 + 0.3) - normal * 0.25),
			Vector3(0.25, lift + 0.6, 0.25), STEEL)
	var uv := TrackAds.ad_uv(brand)
	var hx := right * size.x * 0.5
	var hy := Vector3.UP * size.y * 0.5
	var c := center + normal * 0.0
	ads.quad(c - hx - hy, c + hx - hy, c + hx + hy, c - hx + hy, Color.WHITE, normal,
		Vector2(uv.position.x, uv.end.y), Vector2(uv.end.x, uv.end.y), Vector2(uv.end.x, uv.position.y), uv.position)


## Bandeirolas: cordões sobre o alambrado dos dois lados (a cada ~16 m) e, a cada `spacing`,
## mastros altos dos dois lados com cordões atravessando por cima da pista.
static func _bunting(track: RaceTrack, f: TrackFeature, mb: MeshBuilder, cloth: MeshBuilder) -> void:
	var p := track.path
	for side in [1, -1]:
		var k := RaceTrack._si(side)
		var prev := Vector3.INF
		for i in track.span_indices(f.s_start, f.s_end, 8):
			if track.barrier_kind[k][i] == RaceTrack.Barrier.NONE:
				prev = Vector3.INF
				continue
			var height := 1.25 if track.barrier_kind[k][i] == RaceTrack.Barrier.CONCRETE else 0.95
			var tie := track.edge_point(i, side, track.barrier[k][i] + 0.2, height + TrackBarriers.FENCE_HEIGHT + 0.1)
			if prev != Vector3.INF:
				TrackFlags.bunting(cloth, prev, tie, 0.6, 0.8, i)
			prev = tie
	var step := maxi(int(f.spacing / p.spacing), 1)
	for i in track.span_indices(f.s_start, f.s_end, step):
		if track.barrier_kind[0][i] == RaceTrack.Barrier.NONE or track.barrier_kind[1][i] == RaceTrack.Barrier.NONE:
			continue
		var tops: Array[Vector3] = []
		for side in [1, -1]:
			var base := track.edge_point(i, side, track.outer_distance(i, side) + 0.4)
			mb.posts().cylinder(Transform3D(Basis(), base), 0.14, 0.1, 11.0, TrackFlags.POLE, 6)
			tops.append(base + Vector3.UP * 10.8)
		# Dois cordões cruzando a pista, um pouco defasados
		TrackFlags.bunting(cloth, tops[0], tops[1], 1.6, 0.85, i)
		TrackFlags.bunting(cloth, tops[0] - Vector3.UP * 1.2, tops[1] - Vector3.UP * 1.2, 1.3, 0.85, i + 3)


## Pórtico sobre a pista (torres fora das barreiras). Com `start`, ganha as luzes de largada.
static func _bridge(track: RaceTrack, f: TrackFeature, mb: MeshBuilder, ads: MeshBuilder, parent: Node3D, start: bool) -> void:
	var p := track.path
	var s := f.s_start
	var i := p.index_at(s)
	var fwd := p.tangents[i]
	var left := p.lefts[i]
	var dl := p.width_left[i] + track.outer_distance(i, 1) + 1.0
	var dr := p.width_right[i] + track.outer_distance(i, -1) + 1.0
	if track.layout.has_pit and track.layout.pit_side < 0 and track.pit_width[i] > 0.0:
		dr = minf(dr, p.width_right[i] + 1.5)  # sobre o muro dos boxes
	elif track.layout.has_pit and track.layout.pit_side > 0 and track.pit_width[i] > 0.0:
		dl = minf(dl, p.width_left[i] + 1.5)
	var center := p.position_at(s)
	var height := 7.5 if not start else 6.8
	var beam_h := 2.8
	for lat: float in [dl, -dr]:
		var base := center + left * lat
		mb.posts().box(Transform3D(Basis.looking_at(fwd), base + Vector3.UP * (height + beam_h) * 0.5),
			Vector3(1.0, height + beam_h, 1.0), STEEL)
		mb.posts().box(Transform3D(Basis.looking_at(fwd), base + Vector3.UP * 0.6), Vector3(1.6, 1.2, 1.6), STEEL_DARK)
	var mid := center + left * (dl - dr) * 0.5
	var span := dl + dr
	var basis := Basis(left, Vector3.UP, fwd)
	mb.box(Transform3D(basis, mid + Vector3.UP * (height + beam_h * 0.5)), Vector3(span, beam_h, 0.8), STEEL_DARK)
	# Dois anúncios por face (cada um ~4:1)
	for face: float in [-1.0, 1.0]:
		var normal := fwd * face
		var right := Vector3.UP.cross(normal).normalized()
		for k in 2:
			var w := span * 0.5 - 0.4
			var c := mid + right * (k - 0.5) * (span * 0.5) + Vector3.UP * (height + beam_h * 0.5) + normal * 0.42
			var uv := TrackAds.ad_uv(f.variant + k * 3 + (1 if face > 0 else 0) * 6)
			var hx := right * w * 0.5
			var hy := Vector3.UP * (beam_h - 0.3) * 0.5
			ads.quad(c - hx - hy, c + hx - hy, c + hx + hy, c - hx + hy, Color.WHITE, normal,
				Vector2(uv.position.x, uv.end.y), Vector2(uv.end.x, uv.end.y), Vector2(uv.end.x, uv.position.y), uv.position)
	if start:
		var lights := StartLights.new()
		lights.name = "StartLights"
		parent.add_child(lights)
		lights.setup()
		# As lâmpadas ficam abaixo da viga, no centro da pista
		lights.global_transform = Transform3D(Basis(left, Vector3.UP, fwd), center + Vector3.UP * (height - 1.0))
		track.start_lights = lights


## Placa quadrada (atlas) num poste, virada para quem se aproxima.
static func _sign(track: RaceTrack, s: float, side: int, d: float, sign_id: int, mb: MeshBuilder, ads: MeshBuilder,
		size := 1.3, lift := 0.5) -> void:
	var p := track.path
	var i := p.index_at(s)
	var base := track.edge_point(i, side, d)
	var normal := -p.tangents[i]
	var right := Vector3.UP.cross(normal).normalized()
	var c := base + Vector3.UP * (lift + size * 0.5)
	mb.posts().box(Transform3D(Basis(right, Vector3.UP, normal), base + Vector3.UP * (lift + size) * 0.5 - normal * 0.08),
		Vector3(0.12, lift + size, 0.12), STEEL)
	mb.box(Transform3D(Basis(right, Vector3.UP, normal), c - normal * 0.04), Vector3(size + 0.08, size + 0.08, 0.06), STEEL_DARK)
	var uv := TrackAds.sign_uv(sign_id)
	var hx := right * size * 0.5
	var hy := Vector3.UP * size * 0.5
	ads.quad(c - hx - hy, c + hx - hy, c + hx + hy, c - hx + hy, Color.WHITE, normal,
		Vector2(uv.position.x, uv.end.y), Vector2(uv.end.x, uv.end.y), Vector2(uv.end.x, uv.position.y), uv.position)


## Setas do lado de fora das curvas fechadas, presas à barreira.
static func _chevrons(track: RaceTrack, mb: MeshBuilder, ads: MeshBuilder) -> void:
	var p := track.path
	var n := p.size()
	var limit := 1.0 / CHEVRON_MAX_RADIUS
	var i := 0
	while i < n:
		if absf(p.curvature[i]) < limit:
			i += 1
			continue
		var best := i
		while i < n and absf(p.curvature[i]) >= limit:
			if absf(p.curvature[i]) > absf(p.curvature[best]):
				best = i
			i += 1
		var turn_left := p.curvature[best] > 0.0
		var outside := -1 if turn_left else 1
		var sign_id := TrackAds.Sign.CHEVRON_LEFT if turn_left else TrackAds.Sign.CHEVRON_RIGHT
		for k in 3:
			var idx := p.wrap_index(best - 6 + k * 4)
			var d := track.barrier[RaceTrack._si(outside)][idx] - 0.6
			var base := track.edge_point(idx, outside, d)
			var normal := (-p.tangents[idx] * 0.6 + p.lefts[idx] * -outside * 0.8).normalized()
			var right := Vector3.UP.cross(normal).normalized()
			var c := base + Vector3.UP * 1.9
			mb.posts().box(Transform3D(Basis(right, Vector3.UP, normal), base + Vector3.UP * 1.25 - normal * 0.06), Vector3(0.1, 2.5, 0.1), STEEL)
			var uv := TrackAds.sign_uv(sign_id)
			var hx := right * 0.6
			var hy := Vector3.UP * 0.6
			ads.quad(c - hx - hy, c + hx - hy, c + hx + hy, c - hx + hy, Color.WHITE, normal,
				Vector2(uv.position.x, uv.end.y), Vector2(uv.end.x, uv.end.y), Vector2(uv.end.x, uv.position.y), uv.position)


static func _pit_signs(track: RaceTrack, mb: MeshBuilder, ads: MeshBuilder) -> void:
	var lay := track.layout
	if not lay.has_pit:
		return
	var side := lay.pit_side
	var i := track.path.index_at(lay.pit_entry_s - 40.0)
	_sign(track, lay.pit_entry_s - 40.0, side, track.barrier[RaceTrack._si(side)][i] - 0.8, TrackAds.Sign.PIT, mb, ads, 1.6, 1.0)
	var s_limit := lay.pit_entry_s + lay.pit_taper - 10.0
	i = track.path.index_at(s_limit)
	_sign(track, s_limit, side, track.pit_width[i] + 0.2, TrackAds.Sign.SPEED_80, mb, ads, 1.2, 1.2)
