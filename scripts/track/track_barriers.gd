class_name TrackBarriers
extends RefCounted
## Barreiras (guard-rail ou muro de concreto), barreiras de proteção vermelhas/brancas na
## frente das caixas de brita, alambrado com postes, muro dos boxes e placas de anúncio
## presas na face da barreira (TrackFeature BARRIER_ADS).

const FENCE_HEIGHT := 3.2
const COLLISION_HEIGHT := 2.6
const COLLISION_THICKNESS := 1.2
const STEEL := Color(0.72, 0.75, 0.8)
const STEEL_DARK := Color(0.34, 0.36, 0.42)
const CONCRETE := Color(0.84, 0.84, 0.86)
const RED := Color(0.86, 0.12, 0.15)
const WHITE := Color(0.96, 0.96, 0.97)
const POST := Color(0.42, 0.45, 0.5)
## Brita mais larga que isso ganha barreira de proteção (Tecpro) na frente do guard-rail.
const PROTECTION_MIN_GRAVEL := 6.0


static func build(track: RaceTrack, parent: Node3D) -> void:
	var p := track.path
	var n := p.size()
	var walls := MeshBuilder.new()
	var fence := MeshBuilder.new()
	var collision: Array = []  # [Transform3D, tamanho]
	var ads := MeshBuilder.new()
	var ad_spans := []
	for f in track.layout.features:
		if f and f.kind == TrackFeature.Kind.BARRIER_ADS:
			ad_spans.append(f)

	for side in [1, -1]:
		var k := RaceTrack._si(side)
		for i in n:
			var j := (i + 1) % n
			var kind := track.barrier_kind[k][i]
			if kind == RaceTrack.Barrier.NONE or track.barrier_kind[k][j] == RaceTrack.Barrier.NONE:
				continue
			var d_i := track.barrier[k][i]
			var d_j := track.barrier[k][j]
			var protect := track.gravel[k][i] > PROTECTION_MIN_GRAVEL and kind == RaceTrack.Barrier.ARMCO
			var height := 1.25 if kind == RaceTrack.Barrier.CONCRETE else 0.95
			var thick := 0.6 if kind == RaceTrack.Barrier.CONCRETE else 0.35
			var front_i := d_i
			var front_j := d_j
			if protect:
				# Blocos de proteção alternando vermelho/branco
				var c := RED if (i / 2) % 2 == 0 else WHITE
				_wall(walls, track, i, j, side, d_i - 1.1, d_j - 1.1, 1.1, 1.05, [[0.0, 1.05, c]])
				front_i -= 1.1
				front_j -= 1.1
			if kind == RaceTrack.Barrier.CONCRETE:
				var top := RED if (i / 2) % 2 == 0 else WHITE
				_wall(walls, track, i, j, side, d_i, d_j, thick, height, [[0.0, 1.0, CONCRETE], [1.0, height, top]])
			else:
				_wall(walls, track, i, j, side, d_i, d_j, thick, height,
					[[0.0, 0.3, STEEL_DARK], [0.3, 0.58, STEEL], [0.58, 0.64, STEEL_DARK], [0.64, 0.92, STEEL], [0.92, height, STEEL_DARK]])
			# Alambrado sobre a barreira
			var fl_i := d_i + thick * 0.5
			var fl_j := d_j + thick * 0.5
			var s_i := p.s_at(i)
			var s_j := s_i + p.spacing
			fence.quad(track.edge_point(i, side, fl_i, height), track.edge_point(j, side, fl_j, height),
				track.edge_point(j, side, fl_j, height + FENCE_HEIGHT), track.edge_point(i, side, fl_i, height + FENCE_HEIGHT),
				Color.WHITE, -p.lefts[i] * side,
				Vector2(s_i, 0), Vector2(s_j, 0), Vector2(s_j, FENCE_HEIGHT), Vector2(s_i, FENCE_HEIGHT))
			if i % 2 == 0:
				var base := track.edge_point(i, side, fl_i, 0.0)
				var post_xf := Transform3D(Basis.looking_at(p.tangents[i]), base + Vector3.UP * (height + FENCE_HEIGHT) * 0.5)
				walls.posts().box(post_xf, Vector3(0.09, height + FENCE_HEIGHT, 0.09), POST)
			# Colisão: bloco sólido atrás da face (paredes finas deixam o carro atravessar em alta velocidade)
			collision.append(_wall_box(track.edge_point(i, side, front_i), track.edge_point(j, side, front_j),
				p.lefts[i] * side, COLLISION_THICKNESS))
			# Anúncios na face da barreira
			for f in ad_spans:
				if side in f.sides() and track.in_span(s_i, f.s_start, f.s_end):
					_ad_segment(ads, track, i, j, side, front_i - 0.03, front_j - 0.03, minf(height, 1.0), f)
					break

	_build_pit_wall(track, walls, fence, collision)

	var body := TrackSurface.make_body("Barriers", TrackSurface.Type.BARRIER)
	var wall_mi := MeshInstance3D.new()
	wall_mi.name = "Walls"
	wall_mi.mesh = walls.commit(null, TrackMaterials.barrier())
	body.add_child(wall_mi)
	var fence_mi := MeshInstance3D.new()
	fence_mi.name = "Fence"
	fence_mi.mesh = fence.commit(null, TrackMaterials.fence())
	fence_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(fence_mi)
	if not ads.is_empty():
		var ads_mi := MeshInstance3D.new()
		ads_mi.name = "BarrierAds"
		ads_mi.mesh = ads.commit(null, TrackMaterials.ads())
		ads_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(ads_mi)
	# Muro liso: o carro raspa e escorrega em vez de "agarrar" e capotar
	var mat := PhysicsMaterial.new()
	mat.friction = 0.25
	mat.bounce = 0.05
	body.physics_material_override = mat
	for box in collision:
		var shape := BoxShape3D.new()
		shape.size = box[1]
		var owner_id := body.create_shape_owner(body)
		body.shape_owner_add_shape(owner_id, shape)
		body.shape_owner_set_transform(owner_id, box[0])
	parent.add_child(body)


## Bloco de colisão com a face da frente entre a e b (no chão) e `thick` m para fora (`out`).
static func _wall_box(a: Vector3, b: Vector3, out: Vector3, thick: float) -> Array:
	var along := b - a
	var length := along.length() + 0.15
	var x := along.normalized()
	var z := (out - x * out.dot(x)).normalized()
	var basis := Basis(x, Vector3.UP, x.cross(Vector3.UP).normalized() * signf(x.cross(Vector3.UP).dot(z)))
	var center := (a + b) * 0.5 + z * thick * 0.5 + Vector3.UP * COLLISION_HEIGHT * 0.5
	return [Transform3D(basis, center), Vector3(length, COLLISION_HEIGHT, thick)]


## Parede com seção retangular entre os afastamentos d (face) e d + thick.
## bands: [[y0, y1, cor], ...] para a face voltada para a pista.
static func _wall(mb: MeshBuilder, track: RaceTrack, i: int, j: int, side: int, d_i: float, d_j: float,
		thick: float, height: float, bands: Array) -> void:
	var p := track.path
	var to_track := -p.lefts[i] * side
	for band in bands:
		var y0: float = band[0]
		var y1: float = band[1]
		mb.quad(track.edge_point(i, side, d_i, y0), track.edge_point(j, side, d_j, y0),
			track.edge_point(j, side, d_j, y1), track.edge_point(i, side, d_i, y1), band[2], to_track)
	var top_color: Color = bands[bands.size() - 1][2]
	mb.quad(track.edge_point(i, side, d_i, height), track.edge_point(j, side, d_j, height),
		track.edge_point(j, side, d_j + thick, height), track.edge_point(i, side, d_i + thick, height), top_color, Vector3.UP)
	mb.quad(track.edge_point(i, side, d_i + thick, 0.0), track.edge_point(j, side, d_j + thick, 0.0),
		track.edge_point(j, side, d_j + thick, height), track.edge_point(i, side, d_i + thick, height),
		bands[0][2].darkened(0.1), -to_track)


## Uma fatia (i → j) de uma faixa contínua de anúncios; cada marca ocupa 6 amostras (~12 m).
static func _ad_segment(mb: MeshBuilder, track: RaceTrack, i: int, j: int, side: int, d_i: float, d_j: float,
		height: float, f: TrackFeature) -> void:
	var per := 6
	var panel := i / per
	var brand := (panel * 5 + f.variant + (0 if side > 0 else 3)) % TrackAds.ad_count()
	var uv := TrackAds.ad_uv(brand)
	var u0 := uv.position.x + uv.size.x * float(i % per) / per
	var u1 := uv.position.x + uv.size.x * float(i % per + 1) / per
	# A face olha para a pista; do lado direito o texto precisa ser espelhado para ler certo.
	if side < 0:
		var t := u0
		u0 = uv.position.x + uv.size.x - (u1 - uv.position.x)
		u1 = uv.position.x + uv.size.x - (t - uv.position.x)
		var tmp := u0
		u0 = u1
		u1 = tmp
	var y0 := 0.08
	var top := uv.position.y
	var bottom := uv.position.y + uv.size.y
	mb.quad(track.edge_point(i, side, d_i, y0), track.edge_point(j, side, d_j, y0),
		track.edge_point(j, side, d_j, height), track.edge_point(i, side, d_i, height), Color.WHITE,
		-track.path.lefts[i] * side,
		Vector2(u0, bottom), Vector2(u1, bottom), Vector2(u1, top), Vector2(u0, top))


## Muro entre a pista e os boxes (concreto + tela), só onde a pista dos boxes já está aberta.
static func _build_pit_wall(track: RaceTrack, walls: MeshBuilder, fence: MeshBuilder, collision: Array) -> void:
	if not track.layout.has_pit:
		return
	var p := track.path
	var side := track.layout.pit_side
	var full := RaceTrack.PIT_WALL_STRIP + track.layout.pit_lane_width
	var idxs := track.span_indices(track.layout.pit_entry_s, track.layout.pit_exit_s)
	for k in idxs.size() - 1:
		var i := idxs[k]
		var j := idxs[k + 1]
		if track.pit_width[i] < full * 0.9 or track.pit_width[j] < full * 0.9:
			continue
		var top := RED if (i / 2) % 2 == 0 else WHITE
		_wall(walls, track, i, j, side, 1.2, 1.2, 0.6, 1.1, [[0.0, 0.95, CONCRETE], [0.95, 1.1, top]])
		var s_i := p.s_at(i)
		fence.quad(track.edge_point(i, side, 1.5, 1.1), track.edge_point(j, side, 1.5, 1.1),
			track.edge_point(j, side, 1.5, 3.4), track.edge_point(i, side, 1.5, 3.4), Color.WHITE, -p.lefts[i] * side,
			Vector2(s_i, 0), Vector2(s_i + p.spacing, 0), Vector2(s_i + p.spacing, 2.3), Vector2(s_i, 2.3))
		if i % 2 == 0:
			walls.posts().box(Transform3D(Basis.looking_at(p.tangents[i]), track.edge_point(i, side, 1.5, 1.7)),
				Vector3(0.08, 3.4, 0.08), POST)
		collision.append(_wall_box(track.edge_point(i, side, 1.2), track.edge_point(j, side, 1.2), p.lefts[i] * side, 0.6))
