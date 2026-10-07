class_name TrackRoad
extends RefCounted
## Asfalto (com faixas brancas), zebras vermelhas/brancas, caixas de brita,
## pista dos boxes e pinturas (largada, grid, boxes). Cada piso tem o próprio StaticBody3D
## com o metadado "surface" (TrackSurface.Type).

const ROAD_Y := 0.012
const PAINT_Y := 0.018
const KERB_Y := 0.045
const GRAVEL_Y := 0.006

const ASPHALT := Color(0.165, 0.17, 0.195)
const PIT_ASPHALT := Color(0.23, 0.235, 0.26)
const LINE := Color(0.95, 0.95, 0.97)
const KERB_RED := Color(0.86, 0.1, 0.13)
const KERB_WHITE := Color(0.97, 0.97, 0.98)
const GRAVEL := Color(0.52, 0.45, 0.36)
## Circuito de rua: faixa de asfalto mais clara entre a borda e a barreira (a calçada da cidade).
const VERGE := Color(0.3, 0.3, 0.33)
const LINE_WIDTH := 0.25


static func build(track: RaceTrack, parent: Node3D) -> void:
	var p := track.path
	var n := p.size()
	var road := MeshBuilder.new()
	var kerbs := MeshBuilder.new()
	var gravel := MeshBuilder.new()
	var runoff := MeshBuilder.new()
	var paint := MeshBuilder.new()
	for i in n:
		var j := (i + 1) % n
		var hl_i := p.width_left[i]
		var hl_j := p.width_left[j]
		var hr_i := p.width_right[i]
		var hr_j := p.width_right[j]
		# Asfalto + faixas de borda
		_strip(road, p, i, j, -hr_i, -hr_j, -hr_i + LINE_WIDTH, -hr_j + LINE_WIDTH, ROAD_Y, LINE)
		_strip(road, p, i, j, -hr_i + LINE_WIDTH, -hr_j + LINE_WIDTH, hl_i - LINE_WIDTH, hl_j - LINE_WIDTH, ROAD_Y, ASPHALT)
		_strip(road, p, i, j, hl_i - LINE_WIDTH, hl_j - LINE_WIDTH, hl_i, hl_j, ROAD_Y, LINE)
		for side in [1, -1]:
			var k := RaceTrack._si(side)
			var e_i := p.half_width(i, side)
			var e_j := p.half_width(j, side)
			var kw_i := track.layout.kerb_width * smoothstep(0.0, 1.0, track.kerb[k][i])
			var kw_j := track.layout.kerb_width * smoothstep(0.0, 1.0, track.kerb[k][j])
			if kw_i > 0.05 or kw_j > 0.05:
				_kerb(kerbs, p, i, j, side, e_i, e_j, kw_i, kw_j)
			if track.city:
				# Do fim da zebra (ou da faixa dos boxes, onde ela afunila) até a barreira
				var pit_side: bool = side == track.layout.pit_side
				var in_i := maxf(kw_i, track.pit_width[i] if pit_side else 0.0)
				var in_j := maxf(kw_j, track.pit_width[j] if pit_side else 0.0)
				var b_i := track.barrier[k][i]
				var b_j := track.barrier[k][j]
				if b_i > in_i + 0.05 or b_j > in_j + 0.05:
					_strip(runoff, p, i, j, side * (e_i + in_i), side * (e_j + in_j), side * (e_i + maxf(b_i, in_i) + 0.2),
						side * (e_j + maxf(b_j, in_j) + 0.2), ROAD_Y - 0.004, VERGE)
			var g_i := track.gravel[k][i]
			var g_j := track.gravel[k][j]
			if g_i > 0.3 or g_j > 0.3:
				var a_i := e_i + kw_i + 1.0
				var a_j := e_j + kw_j + 1.0
				_strip(gravel, p, i, j, side * a_i, side * a_j, side * (a_i + g_i), side * (a_j + g_j), GRAVEL_Y, GRAVEL)
		# Pista dos boxes (inclui a faixa do muro)
		if track.pit_width[i] > 0.05 or track.pit_width[j] > 0.05:
			var side := track.layout.pit_side
			var e_i := p.half_width(i, side)
			var e_j := p.half_width(j, side)
			_strip(road, p, i, j, side * e_i, side * e_j, side * (e_i + track.pit_width[i]), side * (e_j + track.pit_width[j]),
				ROAD_Y, PIT_ASPHALT)

	_paint_start(track, paint)
	_paint_pit(track, paint)

	_add_surface(parent, "Road", road, TrackMaterials.surface("asphalt"), TrackSurface.Type.ASPHALT)
	_add_surface(parent, "Kerbs", kerbs, TrackMaterials.surface("kerb"), TrackSurface.Type.KERB)
	_add_surface(parent, "Gravel", gravel, TrackMaterials.surface("gravel"), TrackSurface.Type.GRAVEL)
	_add_surface(parent, "Runoff", runoff, TrackMaterials.surface("asphalt"), TrackSurface.Type.RUNOFF)
	var mi := MeshInstance3D.new()
	mi.name = "Paint"
	mi.mesh = paint.commit(null, TrackMaterials.surface("paint"))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _add_surface(parent: Node3D, node_name: String, mb: MeshBuilder, mat: Material, type: int) -> void:
	if mb.is_empty():
		return
	var body := TrackSurface.make_body(node_name, type)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mb.commit(null, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var col := CollisionShape3D.new()
	col.shape = mb.collision_shape()
	body.add_child(col)
	parent.add_child(body)


## Faixa entre dois deslocamentos laterais (com sinal) de i até j.
static func _strip(mb: MeshBuilder, p: TrackPath, i: int, j: int, a_i: float, a_j: float, b_i: float, b_j: float,
		y: float, color: Color) -> void:
	var up := Vector3.UP * y
	mb.quad(p.points[i] + p.lefts[i] * a_i + up, p.points[i] + p.lefts[i] * b_i + up,
		p.points[j] + p.lefts[j] * b_j + up, p.points[j] + p.lefts[j] * a_j + up, color)


## Zebra elevada: sobe na borda da pista, plana e desce no fim. Listras de ~2 m.
static func _kerb(mb: MeshBuilder, p: TrackPath, i: int, j: int, side: int, e_i: float, e_j: float, w_i: float, w_j: float) -> void:
	var color := KERB_RED if i % 2 == 0 else KERB_WHITE
	# Perfil (fração da largura, altura)
	var profile := [Vector2(0.0, ROAD_Y), Vector2(0.18, KERB_Y), Vector2(0.85, KERB_Y), Vector2(1.0, ROAD_Y + 0.005)]
	for k in profile.size() - 1:
		var a: Vector2 = profile[k]
		var b: Vector2 = profile[k + 1]
		var pa_i := p.points[i] + p.lefts[i] * side * (e_i + w_i * a.x) + Vector3.UP * a.y
		var pb_i := p.points[i] + p.lefts[i] * side * (e_i + w_i * b.x) + Vector3.UP * b.y
		var pa_j := p.points[j] + p.lefts[j] * side * (e_j + w_j * a.x) + Vector3.UP * a.y
		var pb_j := p.points[j] + p.lefts[j] * side * (e_j + w_j * b.x) + Vector3.UP * b.y
		mb.quad(pa_i, pb_i, pb_j, pa_j, color)


## Retângulo pintado no chão: centro em (s, lateral), tamanho (comprimento, largura).
static func paint_rect(mb: MeshBuilder, p: TrackPath, s: float, lateral: float, length: float, width: float,
		color: Color, y := PAINT_Y) -> void:
	var f := p.frame_at(s, lateral, y)
	var hx := f.basis.x * width * 0.5
	var hz := f.basis.z * length * 0.5
	mb.quad(f.origin - hx - hz, f.origin + hx - hz, f.origin + hx + hz, f.origin - hx + hz, color)


## Linha de chegada quadriculada, linha de largada e marcas do grid.
static func _paint_start(track: RaceTrack, mb: MeshBuilder) -> void:
	var p := track.path
	var i0 := p.index_at(0.0)
	var left := p.width_left[i0]
	var right := p.width_right[i0]
	var cells := 16
	var cell := (left + right) / cells
	for row in 2:
		for c in cells:
			var color := Color.WHITE if (row + c) % 2 == 0 else Color(0.08, 0.08, 0.1)
			paint_rect(mb, p, 0.4 + row * 0.8, -right + (c + 0.5) * cell, 0.8, cell, color)
	# Grid: um "colchete" branco por posição
	for slot in track.layout.grid_slots:
		var xf := track.get_grid_transform(slot)
		var pr := p.project(xf.origin)
		var s := pr.x + 2.6  # frente do carro
		paint_rect(mb, p, s, pr.y, 0.2, 2.2, LINE)
		paint_rect(mb, p, s - 0.6, pr.y + 1.0, 1.2, 0.2, LINE)
		paint_rect(mb, p, s - 0.6, pr.y - 1.0, 1.2, 0.2, LINE)


## Faixas da pista dos boxes, linhas de limite de velocidade e vagas de cada equipe.
static func _paint_pit(track: RaceTrack, mb: MeshBuilder) -> void:
	if not track.layout.has_pit:
		return
	var p := track.path
	var side := track.layout.pit_side
	var lane := track.layout.pit_lane_width
	var full := RaceTrack.PIT_WALL_STRIP + lane
	for idx in track.span_indices(track.layout.pit_entry_s, track.layout.pit_exit_s):
		var w := track.pit_width[idx]
		if w < full * 0.98:
			continue
		var s := p.s_at(idx)
		# Linha junto ao muro, linha externa e tracejado entre pista rápida e área de trabalho
		paint_rect(mb, p, s, track.pit_lateral(idx, RaceTrack.PIT_WALL_STRIP + 0.2), p.spacing + 0.02, 0.2, LINE)
		paint_rect(mb, p, s, track.pit_lateral(idx, full - 0.2), p.spacing + 0.02, 0.2, LINE)
		if idx % 3 == 0:
			paint_rect(mb, p, s, track.pit_lateral(idx, RaceTrack.PIT_WALL_STRIP + lane * 0.45), p.spacing * 1.4, 0.15, LINE)
	# Limite de velocidade (entrada e saída)
	for s in [track.layout.pit_entry_s + track.layout.pit_taper, track.layout.pit_exit_s - track.layout.pit_taper]:
		var idx := p.index_at(s)
		for k in 6:
			paint_rect(mb, p, s, track.pit_lateral(idx, RaceTrack.PIT_WALL_STRIP + lane * (k + 0.5) / 6.0), 0.5, lane / 6.0,
				LINE if k % 2 == 0 else Color(0.1, 0.1, 0.12))
	# Vagas de cada box: retângulo com a cor da equipe
	for g in track.layout.garage_count:
		var s := track.garage_s(g)
		var idx := p.index_at(s)
		var color := track.layout.team_colors[(g / 2) % track.layout.team_colors.size()]
		var lat := track.pit_lateral(idx, RaceTrack.PIT_WALL_STRIP + lane * 0.72)
		paint_rect(mb, p, s, lat, 6.4, 3.4, LINE)
		paint_rect(mb, p, s, lat, 6.0, 3.0, color.darkened(0.15), PAINT_Y + 0.001)
