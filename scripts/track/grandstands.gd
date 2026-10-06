class_name Grandstands
extends RefCounted
## Arquibancadas (TrackFeature GRANDSTAND) e barrancos com público em pé (SPECTATORS).
## A estrutura acompanha a curva da pista; o público é um MultiMesh de quads animados por
## shader (shaders/track/crowd.gdshader), um por arquibancada.

const ROW_DEPTH := 0.85
const ROW_RISE := 0.45
const FRONT_HEIGHT := 2.4
const SEAT_SPACING := 0.48
const AISLE_EVERY := 11  # amostras (~22 m)
const CONCRETE := Color(0.66, 0.67, 0.71)
const GREY := Color(0.44, 0.46, 0.52)
const ROOF := Color(0.84, 0.85, 0.88)
const BANK := Color(0.38, 0.66, 0.3)
const SEATS := [
	[Color(0.7, 0.1, 0.13), Color(0.78, 0.78, 0.8)],
	[Color(0.15, 0.36, 0.72), Color(0.78, 0.78, 0.8)],
	[Color(0.1, 0.48, 0.28), Color(0.78, 0.78, 0.8)],
	[Color(0.78, 0.6, 0.12), Color(0.7, 0.1, 0.13)],
]

static var _quad: QuadMesh


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Grandstands"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	var count := 0
	for fi in track.layout.features.size():
		var f: TrackFeature = track.layout.features[fi]
		if f == null or (f.kind != TrackFeature.Kind.GRANDSTAND and f.kind != TrackFeature.Kind.SPECTATORS):
			continue
		rng.seed = hash(fi * 7919 + 13)
		for side in f.sides():
			var node := _build_one(track, f, side, rng)
			if node:
				node.name = (f.label if f.label != "" else "Stand%d" % fi).validate_node_name() + ("" if side > 0 else "_D")
				root.add_child(node)
				count += 1


static func _build_one(track: RaceTrack, f: TrackFeature, side: int, rng: RandomNumberGenerator) -> Node3D:
	var p := track.path
	var idxs := track.span_indices(f.s_start, f.s_end)
	if idxs.size() < 2:
		return null
	var standing := f.kind == TrackFeature.Kind.SPECTATORS
	# Afastamento da frente, suavizado para não acompanhar cada ondulação da barreira
	var dist := PackedFloat32Array()
	for i in idxs:
		dist.append(track.outer_distance(i, side) + f.distance)
	var smooth := dist.duplicate()
	for k in dist.size():
		var m := 0.0
		for d in range(-8, 9):
			m = maxf(m, dist[clampi(k + d, 0, dist.size() - 1)])
		smooth[k] = m
	dist = smooth

	var rows := maxi(f.rows, 1)
	var rise := 0.35 if standing else ROW_RISE
	var depth := 1.0 if standing else ROW_DEPTH
	var base_h := 0.3 if standing else FRONT_HEIGHT
	var back := rows * depth
	var top := base_h + rows * rise
	var palette: Array = SEATS[f.variant % SEATS.size()]

	var mb := MeshBuilder.new()
	var ads := MeshBuilder.new()
	var cloth := MeshBuilder.new()
	var glass := MeshBuilder.new()
	var rail_points := PackedVector3Array()
	var pole_points := PackedVector3Array()
	var crowd: Array[Transform3D] = []
	var crowd_data: Array[Color] = []
	var front_poly := PackedVector2Array()
	var back_poly := PackedVector2Array()
	var carry := 0.0
	for k in idxs.size():
		var i := idxs[k]
		var u := func(off: float, y: float) -> Vector3:
			return track.edge_point(i, side, dist[k] + off, y)
		var fp: Vector3 = u.call(-1.0, 0.0)
		var bp: Vector3 = u.call(back + 2.0, 0.0)
		front_poly.append(Vector2(fp.x, fp.z))
		back_poly.append(Vector2(bp.x, bp.z))
		if k == idxs.size() - 1:
			break
		var j := idxs[k + 1]
		var v := func(off: float, y: float) -> Vector3:
			return track.edge_point(j, side, dist[k + 1] + off, y)
		var to_track := -p.lefts[i] * side
		var aisle := not standing and k % AISLE_EVERY == 0
		# Pontos de amarração das bandeirolas (a cada ~12 m) e mastros (a cada ~24 m)
		if not standing and k % 6 == 0:
			var tie: Vector3 = u.call(-1.4, top + 4.3) if f.roof else u.call(back + 0.15, top + 2.6)
			rail_points.append(tie)
			if not f.roof:
				mb.posts().box(Transform3D(Basis(), tie - Vector3.UP * 0.75), Vector3(0.08, 1.6, 0.08), GREY)
			if k % 12 == 0:
				pole_points.append(u.call(-0.9, top + 4.6) if f.roof else u.call(back + 0.15, top + 1.1))
		# Mureta da frente
		if not standing:
			mb.quad(u.call(0.0, 0.0), v.call(0.0, 0.0), v.call(0.0, base_h), u.call(0.0, base_h), CONCRETE, to_track)
			var uv := TrackAds.ad_uv((k / 6) * 3 + f.variant)
			var a := float(k % 6) / 6.0
			var b := float(k % 6 + 1) / 6.0
			if side < 0:
				a = 1.0 - a
				b = 1.0 - b
			ads.quad(u.call(-0.02, 0.5), v.call(-0.02, 0.5), v.call(-0.02, 1.9), u.call(-0.02, 1.9), Color.WHITE, to_track,
				Vector2(uv.position.x + uv.size.x * a, uv.end.y), Vector2(uv.position.x + uv.size.x * b, uv.end.y),
				Vector2(uv.position.x + uv.size.x * b, uv.position.y), Vector2(uv.position.x + uv.size.x * a, uv.position.y))
		else:
			mb.quad(u.call(0.0, 0.0), v.call(0.0, 0.0), v.call(0.0, base_h), u.call(0.0, base_h), BANK.darkened(0.15), to_track)
		# Degraus: espelho + piso de cada fileira
		for r in rows:
			var y0 := base_h + r * rise
			var y1 := y0 + rise
			var u0 := r * depth
			var u1 := u0 + depth
			var seat: Color = BANK if standing else (GREY if aisle else palette[(r / 3 + k / 9) % 2])
			mb.quad(u.call(u0, y0), v.call(u0, y0), v.call(u1, y0), u.call(u1, y0), seat, Vector3.UP)
			mb.quad(u.call(u1, y0), v.call(u1, y0), v.call(u1, y1), u.call(u1, y1),
				BANK.darkened(0.1) if standing else CONCRETE.darkened(0.08), to_track)
		mb.quad(u.call(back, top), v.call(back, top), v.call(back + 0.3, top), u.call(back + 0.3, top), CONCRETE, Vector3.UP)
		# Fundo fechado
		mb.quad(u.call(back + 0.3, 0.0), v.call(back + 0.3, 0.0), v.call(back + 0.3, top + 1.1), u.call(back + 0.3, top + 1.1),
			GREY, -to_track)
		mb.quad(u.call(back, top), v.call(back, top), v.call(back, top + 1.1), u.call(back, top + 1.1), GREY.lightened(0.2), to_track)
		# Cobertura com camarotes envidraçados no alto (entre a última fileira e o telhado)
		if f.roof:
			var g0 := top + 1.25
			var g1 := top + 3.45
			glass.quad(u.call(back - 0.05, g0), v.call(back - 0.05, g0), v.call(back - 0.05, g1), u.call(back - 0.05, g1),
				Color.WHITE, to_track)
			mb.quad(u.call(back - 0.6, g0 - 0.15), v.call(back - 0.6, g0 - 0.15), v.call(back - 0.6, g0), u.call(back - 0.6, g0),
				GREY, to_track)
			if k % 2 == 0:
				mb.posts().box(Transform3D(Basis(), (u.call(back - 0.12, (g0 + g1) * 0.5) as Vector3)), Vector3(0.12, g1 - g0, 0.12), GREY)
			var r0 := top + 4.6
			var r1 := top + 3.8
			mb.quad(u.call(-1.5, r0), v.call(-1.5, r0), v.call(back + 0.6, r1), u.call(back + 0.6, r1), ROOF, Vector3.UP)
			mb.quad(u.call(-1.5, r0 - 0.25), v.call(-1.5, r0 - 0.25), v.call(back + 0.6, r1 - 0.25), u.call(back + 0.6, r1 - 0.25),
				GREY, Vector3.DOWN)
			mb.quad(u.call(-1.5, r0 - 0.25), v.call(-1.5, r0 - 0.25), v.call(-1.5, r0), u.call(-1.5, r0), palette[0], to_track)
			if k % 4 == 0:
				var col_pos: Vector3 = u.call(back + 0.15, 0.0)
				mb.posts().box(Transform3D(Basis(), col_pos + Vector3.UP * (r1 * 0.5)), Vector3(0.35, r1, 0.35), GREY)
		# Público
		var seg := p.points[i].distance_to(p.points[j]) * (1.0 + side * p.curvature[i] * (dist[k] + back * 0.5))
		if aisle:
			carry = 0.0
			continue
		var t := carry
		while t < seg:
			var frac := t / maxf(seg, 0.01)
			for r in rows:
				if rng.randf() > track.crowd_density * (0.75 if standing else 1.0):
					continue
				var off := r * depth + depth * (0.5 if standing else 0.42) + rng.randf_range(-0.08, 0.08)
				var y := base_h + r * rise
				var pos: Vector3 = (u.call(off, y) as Vector3).lerp(v.call(off, y), frac)
				pos += p.tangents[i] * rng.randf_range(-0.08, 0.08)
				var z := to_track.normalized()
				var basis := Basis(Vector3.UP.cross(z), Vector3.UP, z)
				var scale := rng.randf_range(0.9, 1.08) * (1.05 if standing else 1.0)
				crowd.append(Transform3D(basis.scaled(Vector3.ONE * scale), pos))
				crowd_data.append(_random_fan(rng))
			t += SEAT_SPACING * (1.3 if standing else 1.0)
		carry = t - seg

	# Tampas laterais nas pontas
	for end in [0, idxs.size() - 1]:
		var i := idxs[end]
		var pts := PackedVector3Array([track.edge_point(i, side, dist[end], 0.0)])
		for r in rows + 1:
			pts.append(track.edge_point(i, side, dist[end] + r * depth, base_h + r * rise))
		pts.append(track.edge_point(i, side, dist[end] + back + 0.3, top))
		pts.append(track.edge_point(i, side, dist[end] + back + 0.3, 0.0))
		var normal := p.tangents[i] * (-1.0 if end == 0 else 1.0)
		for q in range(1, pts.size() - 1):
			mb.tri(pts[0], pts[q], pts[q + 1], CONCRETE.darkened(0.05), normal)

	for k in rail_points.size() - 1:
		TrackFlags.bunting(cloth, rail_points[k], rail_points[k + 1], 0.7, 0.8, k * 3)
	for k in pole_points.size():
		var colors: Array = TrackFlags.ITALY if k % 2 == 0 else [palette[0], Color.WHITE, palette[0]]
		TrackFlags.flagpole(mb, cloth, pole_points[k], 6.0, Vector2(2.4, 1.5), colors, 0 if k % 2 == 0 else 1)

	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Structure"
	mi.mesh = mb.commit(null, TrackMaterials.stand(f.roof))
	glass.commit(mi.mesh as ArrayMesh, TrackMaterials.glass())
	if not ads.is_empty():
		ads.commit(mi.mesh as ArrayMesh, TrackMaterials.ads())
	TrackFlags.commit_to(cloth, mi.mesh as ArrayMesh)
	node.add_child(mi)
	if not crowd.is_empty():
		node.add_child(make_crowd(crowd, crowd_data, track.crowd_visibility))
	back_poly.reverse()
	front_poly.append_array(back_poly)
	track.footprints.append(front_poly)
	return node


## Dados de um torcedor: (fase, tipo de animação, camisa, aparência).
static func _random_fan(rng: RandomNumberGenerator) -> Color:
	var r := rng.randf()
	var type := 0.1
	if r > 0.95:
		type = 0.95
	elif r > 0.8:
		type = 0.7
	elif r > 0.55:
		type = 0.4
	# Muita camisa vermelha (torcida da casa)
	var shirt := 0.0 if rng.randf() < 0.3 else rng.randf()
	return Color(rng.randf(), type, shirt, rng.randf())


static func make_crowd(transforms: Array[Transform3D], data: Array[Color], visibility: float) -> MultiMeshInstance3D:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(0.8, 1.4)
		_quad.center_offset = Vector3(0, 0.7, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _quad
	mm.instance_count = transforms.size()
	mm.buffer = pack_buffer(transforms, data)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Crowd"
	mmi.multimesh = mm
	mmi.material_override = TrackMaterials.crowd()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = visibility
	return mmi


## Buffer do MultiMesh (transformação 3x4 por linha + custom data), bem mais rápido que
## set_instance_transform() para dezenas de milhares de instâncias.
static func pack_buffer(transforms: Array[Transform3D], data: Array[Color]) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(transforms.size() * 16)
	var o := 0
	for i in transforms.size():
		var t := transforms[i]
		var b := t.basis
		var c := data[i]
		buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = t.origin.x
		buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = t.origin.y
		buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = t.origin.z
		buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a
		o += 16
	return buf
