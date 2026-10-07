class_name PitComplex
extends RefCounted
## Prédio dos boxes (garagens por equipe com número, pneus e bancadas; escritórios nas pontas;
## andar envidraçado, marquise e faixa de anúncios no topo), cabines das equipes no muro,
## paddock com motorhomes. Os módulos seguem a curvatura da pista (um por garagem).

const DEPTH := 20.0
const GROUND_H := 5.5
const UPPER_H := 4.0
const CANOPY := 2.5
const WHITE := Color(0.94, 0.95, 0.97)
const GREY := Color(0.62, 0.64, 0.7)
const FLOOR := Color(0.78, 0.79, 0.82)
const GLASS := Color(0.45, 0.68, 0.9)
const TYRE := Color(0.1, 0.1, 0.12)


static func build(track: RaceTrack, parent: Node3D) -> void:
	var lay := track.layout
	if not lay.has_pit:
		return
	var p := track.path
	var side := lay.pit_side
	var front := RaceTrack.PIT_WALL_STRIP + lay.pit_lane_width
	var structure := MeshBuilder.new()
	var glass := MeshBuilder.new()
	var ads := MeshBuilder.new()
	var collision := MeshBuilder.new()
	var floor_mb := MeshBuilder.new()
	var cloth := MeshBuilder.new()
	var canopy_points := PackedVector3Array()
	var root := Node3D.new()
	root.name = "PitComplex"
	parent.add_child(root)

	# Módulos: garagens no centro, escritórios até completar o comprimento do prédio
	var module_w := lay.garage_width
	var modules := int(round(lay.pit_building_length / module_w))
	var first_garage := (modules - lay.garage_count) / 2
	for m in modules:
		var s := lay.garage_center_s + (m - (modules - 1) * 0.5) * module_w
		var xf := _module_frame(track, s, front)
		var g := m - first_garage
		var is_garage := g >= 0 and g < lay.garage_count
		var team := lay.team_colors[(g / 2) % lay.team_colors.size()] if is_garage else WHITE
		if is_garage:
			_garage(structure, collision, floor_mb, xf, module_w, team)
			# Luz da garagem à noite
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.95, 0.88)
			lamp.light_energy = 2.2
			lamp.set_meta("base_energy", 2.2)
			lamp.omni_range = 16.0
			lamp.visible = false
			lamp.add_to_group("night_lights")
			root.add_child(lamp)
			lamp.global_position = xf * Vector3(DEPTH * 0.45, GROUND_H - 0.8, 0.0)
			_garage_label(root, xf, module_w, g, team)
		else:
			_office(structure, glass, collision, xf, module_w)
		_upper_floor(structure, glass, ads, xf, module_w, m)
		# Bandeirolas sob a marquise e mastro com a bandeira da equipe no telhado
		canopy_points.append(xf * Vector3(-CANOPY + 0.2, GROUND_H + UPPER_H - 0.1, -module_w * 0.5))
		if is_garage and g % 2 == 0:
			TrackFlags.flagpole(structure, cloth, xf * Vector3(DEPTH * 0.6, GROUND_H + UPPER_H + 0.6, module_w * 0.5), 7.0,
				Vector2(2.6, 1.6), [team, Color.WHITE, team], 1)
		# Divisória/pilar no começo de cada módulo (e no fim do último)
		structure.box(xf * Transform3D(Basis(), Vector3(DEPTH * 0.5, GROUND_H * 0.5, -module_w * 0.5)),
			Vector3(DEPTH, GROUND_H, 0.6), WHITE)
		collision.box(xf * Transform3D(Basis(), Vector3(DEPTH * 0.5, GROUND_H * 0.5, -module_w * 0.5)),
			Vector3(DEPTH, GROUND_H, 0.6), WHITE)
		if m == modules - 1:
			structure.box(xf * Transform3D(Basis(), Vector3(DEPTH * 0.5, GROUND_H * 0.5, module_w * 0.5)),
				Vector3(DEPTH, GROUND_H, 0.6), WHITE)
			collision.box(xf * Transform3D(Basis(), Vector3(DEPTH * 0.5, GROUND_H * 0.5, module_w * 0.5)),
				Vector3(DEPTH, GROUND_H, 0.6), WHITE)

	for k in canopy_points.size() - 1:
		TrackFlags.bunting(cloth, canopy_points[k], canopy_points[k + 1], 0.5, 0.75, k * 2)
	_pit_wall_stands(track, structure)
	if lay.paddock_depth > 0.0:
		var footprint := _paddock(track, structure, glass, floor_mb, front)
		track.footprints.append(footprint)

	var mi := MeshInstance3D.new()
	mi.name = "Building"
	mi.mesh = structure.commit(null, TrackMaterials.pit())
	glass.commit(mi.mesh as ArrayMesh, TrackMaterials.glass(true))
	ads.commit(mi.mesh as ArrayMesh, TrackMaterials.ads(true))
	TrackFlags.commit_to(cloth, mi.mesh as ArrayMesh)
	root.add_child(mi)
	var body := TrackSurface.make_body("BuildingCollision", TrackSurface.Type.BARRIER)
	var col := CollisionShape3D.new()
	col.shape = collision.collision_shape()
	body.add_child(col)
	root.add_child(body)
	var floor_body := TrackSurface.make_body("Floor", TrackSurface.Type.ASPHALT)
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = floor_mb.commit(null, TrackMaterials.surface("paint"))
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floor_body.add_child(floor_mi)
	var floor_col := CollisionShape3D.new()
	floor_col.shape = floor_mb.collision_shape()
	floor_body.add_child(floor_col)
	root.add_child(floor_body)


## Referencial de um módulo: origem na fachada (lado da pista) no centro do módulo;
## +X = para longe da pista, +Y = cima, +Z = sentido da pista. (Pode ser espelhado.)
static func _module_frame(track: RaceTrack, s: float, front: float) -> Transform3D:
	var p := track.path
	var side := track.layout.pit_side
	var i := p.index_at(s)
	var f := p.frame_at(s, track.pit_lateral(i, front))
	return Transform3D(Basis(f.basis.x * side, Vector3.UP, f.basis.z), f.origin)


static func _at(xf: Transform3D, x: float, y: float, z: float) -> Transform3D:
	return xf * Transform3D(Basis(), Vector3(x, y, z))


static func _garage(mb: MeshBuilder, col: MeshBuilder, floor_mb: MeshBuilder, xf: Transform3D, w: float, team: Color) -> void:
	# Piso interno, parede do fundo na cor da equipe, teto e faixa da fachada
	floor_mb.quad(xf * Vector3(0, 0.014, -w * 0.5), xf * Vector3(DEPTH, 0.014, -w * 0.5),
		xf * Vector3(DEPTH, 0.014, w * 0.5), xf * Vector3(0, 0.014, w * 0.5), FLOOR, Vector3.UP)
	mb.box(_at(xf, DEPTH - 0.3, GROUND_H * 0.5, 0), Vector3(0.6, GROUND_H, w), team)
	col.box(_at(xf, DEPTH - 0.3, GROUND_H * 0.5, 0), Vector3(0.6, GROUND_H, w), team)
	mb.box(_at(xf, DEPTH * 0.5, GROUND_H - 0.2, 0), Vector3(DEPTH, 0.4, w), WHITE)
	mb.box(_at(xf, 0.0, GROUND_H - 0.5, 0), Vector3(0.5, 1.0, w), team, WHITE)
	mb.box(_at(xf, DEPTH - 0.65, 2.6, 0), Vector3(0.1, 0.5, w * 0.9), team.lightened(0.4))
	# Bancadas, pilhas de pneus e um macaco
	for k in 3:
		mb.box(_at(xf, DEPTH - 1.2, 0.5, (k - 1) * w * 0.28), Vector3(0.8, 1.0, 2.0), team.darkened(0.25), GREY)
	for z in [-w * 0.5 + 1.2, w * 0.5 - 1.2]:
		for row in 2:
			var base := _at(xf, DEPTH - 3.2 - row * 1.0, 0.0, z)
			for h in 4:
				mb.cylinder(base * Transform3D(Basis(), Vector3(0, h * 0.31, 0)), 0.34, 0.34, 0.3, TYRE, 10)
	mb.box(_at(xf, 4.0, 0.25, 0), Vector3(1.6, 0.18, 0.5), Color(0.9, 0.75, 0.1))


static func _garage_label(root: Node3D, xf: Transform3D, w: float, index: int, team: Color) -> void:
	var label := Label3D.new()
	label.text = "%02d" % (index + 1)
	label.font_size = 160
	label.outline_size = 24
	label.pixel_size = 0.004
	label.modulate = Color.WHITE
	label.outline_modulate = team.darkened(0.5)
	var pos := xf * Vector3(-0.28, GROUND_H - 0.5, -w * 0.32)
	var out := xf.basis.x.normalized()
	label.transform = Transform3D(Basis.looking_at(out), pos)
	root.add_child(label)


static func _office(mb: MeshBuilder, glass: MeshBuilder, col: MeshBuilder, xf: Transform3D, w: float) -> void:
	mb.box(_at(xf, DEPTH * 0.5 + 0.3, GROUND_H * 0.5, 0), Vector3(DEPTH - 0.6, GROUND_H, w), WHITE)
	col.box(_at(xf, DEPTH * 0.5 + 0.3, GROUND_H * 0.5, 0), Vector3(DEPTH - 0.6, GROUND_H, w), WHITE)
	glass.quad(xf * Vector3(0.28, 1.2, -w * 0.45), xf * Vector3(0.28, 1.2, w * 0.45),
		xf * Vector3(0.28, 4.3, w * 0.45), xf * Vector3(0.28, 4.3, -w * 0.45), GLASS, -xf.basis.x)


static func _upper_floor(mb: MeshBuilder, glass: MeshBuilder, ads: MeshBuilder, xf: Transform3D, w: float, m: int) -> void:
	var top := GROUND_H + UPPER_H
	# Volume do andar de cima com fachada de vidro recuada
	mb.box(_at(xf, DEPTH * 0.5 + 0.8, GROUND_H + UPPER_H * 0.5, 0), Vector3(DEPTH - 1.6, UPPER_H, w), WHITE)
	glass.quad(xf * Vector3(0.78, GROUND_H + 0.3, -w * 0.5), xf * Vector3(0.78, GROUND_H + 0.3, w * 0.5),
		xf * Vector3(0.78, top - 0.3, w * 0.5), xf * Vector3(0.78, top - 0.3, -w * 0.5), GLASS, -xf.basis.x)
	# Laje/marquise avançando sobre a pista dos boxes
	mb.box(_at(xf, DEPTH * 0.5 - CANOPY * 0.5, top + 0.3, 0), Vector3(DEPTH + CANOPY, 0.6, w + 0.02), WHITE, GREY)
	# Faixa de anúncio no alto, voltada para a pista (texto legível de quem passa)
	var uv := TrackAds.ad_uv(m * 7 + 3)
	var z0 := -w * 0.5
	var z1 := w * 0.5
	var mirrored := xf.basis.determinant() < 0.0
	var u_start := uv.end.x if mirrored else uv.position.x
	var u_end := uv.position.x if mirrored else uv.end.x
	var y0 := top + 0.6
	var y1 := top + 3.6
	ads.quad(xf * Vector3(-CANOPY + 0.3, y0, z0), xf * Vector3(-CANOPY + 0.3, y0, z1),
		xf * Vector3(-CANOPY + 0.3, y1, z1), xf * Vector3(-CANOPY + 0.3, y1, z0), Color.WHITE, -xf.basis.x,
		Vector2(u_start, uv.end.y), Vector2(u_end, uv.end.y), Vector2(u_end, uv.position.y), Vector2(u_start, uv.position.y))
	mb.box(_at(xf, -CANOPY + 0.6, (y0 + y1) * 0.5, 0), Vector3(0.5, y1 - y0, w), GREY)


## Cabines das equipes sobre o muro dos boxes (uma por equipe).
static func _pit_wall_stands(track: RaceTrack, mb: MeshBuilder) -> void:
	var lay := track.layout
	var p := track.path
	var side := lay.pit_side
	for t in lay.garage_count / 2:
		var s := (track.garage_s(t * 2) + track.garage_s(t * 2 + 1)) * 0.5
		var i := p.index_at(s)
		var f := p.frame_at(s, track.pit_lateral(i, 2.4))
		var xf := Transform3D(Basis(f.basis.x * side, Vector3.UP, f.basis.z), f.origin)
		var team := lay.team_colors[t % lay.team_colors.size()]
		mb.box(_at(xf, 0, 0.5, 0), Vector3(1.1, 1.0, 7.0), GREY, team)
		for k in 4:
			mb.box(_at(xf, -0.1, 1.45, (k - 1.5) * 1.6), Vector3(0.2, 0.7, 1.2), Color(0.12, 0.13, 0.18))
		for z in [-3.3, 3.3]:
			mb.posts().box(_at(xf, 0.3, 1.6, z), Vector3(0.12, 3.2, 0.12), GREY)
		mb.box(_at(xf, -0.6, 3.25, 0), Vector3(3.6, 0.15, 7.4), team, team.lightened(0.2))


## Paddock atrás dos boxes: piso e motorhomes das equipes. Retorna a área (sem árvores).
static func _paddock(track: RaceTrack, mb: MeshBuilder, glass: MeshBuilder, floor_mb: MeshBuilder, front: float) -> PackedVector2Array:
	var lay := track.layout
	var p := track.path
	var half := lay.pit_building_length * 0.5 + 30.0
	var s0 := lay.garage_center_s - half
	var s1 := lay.garage_center_s + half
	var depth := DEPTH + lay.paddock_depth
	var outer := PackedVector2Array()
	var s := s0
	while s <= s1 + 0.01:
		var a := _module_frame(track, s, front) * Vector3(DEPTH, 0.0, 0.0)
		var b := _module_frame(track, s, front) * Vector3(depth, 0.0, 0.0)
		outer.append(Vector2(b.x, b.z))
		if s + 10.0 <= s1 + 0.01:
			var c := _module_frame(track, s + 10.0, front) * Vector3(DEPTH, 0.0, 0.0)
			var d := _module_frame(track, s + 10.0, front) * Vector3(depth, 0.0, 0.0)
			floor_mb.quad(a + Vector3.UP * 0.01, b + Vector3.UP * 0.01, d + Vector3.UP * 0.01, c + Vector3.UP * 0.01,
				Color(0.4, 0.41, 0.45), Vector3.UP)
		s += 10.0
	# Motorhomes (só se o paddock tiver espaço)
	var teams := lay.team_colors.size() if lay.paddock_depth >= 30.0 else 0
	var mx := DEPTH + lay.paddock_depth * 0.533
	for t in teams:
		var st := lay.garage_center_s + (t - (teams - 1) * 0.5) * (lay.pit_building_length / teams)
		var xf := _module_frame(track, st, front)
		var color := lay.team_colors[t]
		mb.box(_at(xf, mx, 1.6, 0), Vector3(6.0, 3.2, 16.0), color, WHITE)
		mb.box(_at(xf, mx, 4.4, 0), Vector3(6.0, 2.4, 16.0), WHITE, GREY)
		glass.quad(xf * Vector3(mx - 3.02, 3.6, -7.5), xf * Vector3(mx - 3.02, 3.6, 7.5),
			xf * Vector3(mx - 3.02, 5.2, 7.5), xf * Vector3(mx - 3.02, 5.2, -7.5), GLASS, -xf.basis.x)
		# Toldo
		mb.box(_at(xf, mx - 5.5, 3.0, 0), Vector3(5.0, 0.12, 14.0), color.lightened(0.3))
	# Área sem árvores: da fachada até o fundo do paddock
	var a0 := _module_frame(track, s0, front) * Vector3(-2.0, 0, 0)
	var a1 := _module_frame(track, s1, front) * Vector3(-2.0, 0, 0)
	var poly := PackedVector2Array([Vector2(a0.x, a0.z)])
	poly.append_array(outer)
	poly.append(Vector2(a1.x, a1.z))
	return poly
