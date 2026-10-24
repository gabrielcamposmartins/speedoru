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
## Pista no céu: placas metálicas da plataforma entre a borda e a barreira (ou a borda aberta) e a
## faixa de aviso amarela e preta antes do vazio.
const DECK_PLATE := Color(0.2, 0.21, 0.24)
## Pista no céu: asfalto bem mais escuro (contraste com as faixas, as zebras e o céu claro).
const SKY_ASPHALT := Color(0.085, 0.088, 0.1)
const SKY_PIT_ASPHALT := Color(0.13, 0.135, 0.15)
const HAZARD_YELLOW := Color(0.95, 0.72, 0.08)
const HAZARD_DARK := Color(0.1, 0.1, 0.12)
const HAZARD_WIDTH := 0.9
## Laje de colisão sob a pista no céu: topo abaixo do asfalto e espessura (m).
const DECK_FLOOR_TOP := 0.08
const DECK_FLOOR_THICK := 1.0
const LINE_WIDTH := 0.25
## Pista no fundo do mar: asfalto azul-ardósia escuro, zebras ciano e brancas, faixa de lajes de
## pedra até a barreira e um friso de LED ciano logo dentro de cada linha branca (com o pulso
## correndo, sky_glow.gdshader).
const SEA_ASPHALT := Color(0.1, 0.12, 0.15)
const SEA_PIT_ASPHALT := Color(0.15, 0.17, 0.2)
const SEA_KERB := Color(0.1, 0.78, 0.92)
const SEA_VERGE := Color(0.62, 0.62, 0.6)
const SEA_LED := Color(0.25, 0.95, 1.0)
const SEA_LED_WIDTH := 0.16
const SEA_LED_INSET := 0.2
## Pista fofa nas nuvens: asfalto rosa envernizado com corações brancos pintados, zebras de arco-íris,
## faixa creme até a barreira com as listras de arco-íris no pé dela e estrelas acesas no piso na
## saída das curvas lentas.
const CLOUD_ASPHALT := Color(0.84, 0.3, 0.54)
const CLOUD_PIT_ASPHALT := Color(0.88, 0.48, 0.68)
const CLOUD_VERGE := Color(1.0, 0.78, 0.88)
## Largura de cada listra de arco-íris no pé da barreira.
const CLOUD_BAND := 0.2
## Corações pintados no asfalto: intervalo (m) nas retas e curvas abertas.
const HEART_SPACING := 55.0
## Estrelas acesas no piso: quantos metros depois do fim das curvas lentas.
const STAR_AFTER := 28.0

## Cores das listras das zebras (a pista do fundo do mar troca o vermelho por ciano).
static var _kerb_colors := [KERB_RED, KERB_WHITE]


static func build(track: RaceTrack, parent: Node3D) -> void:
	var p := track.path
	var n := p.size()
	var road := MeshBuilder.new()
	var kerbs := MeshBuilder.new()
	var gravel := MeshBuilder.new()
	var runoff := MeshBuilder.new()
	var paint := MeshBuilder.new()
	var sea := track.layout.undersea
	var clouds := track.layout.clouds
	var leds := MeshBuilder.new()
	var asphalt := SKY_ASPHALT if track.layout.sky else (SEA_ASPHALT if sea else ASPHALT)
	var pit_asphalt := SKY_PIT_ASPHALT if track.layout.sky else (SEA_PIT_ASPHALT if sea else PIT_ASPHALT)
	_kerb_colors = [SEA_KERB, KERB_WHITE] if sea else [KERB_RED, KERB_WHITE]
	if clouds:
		asphalt = CLOUD_ASPHALT
		pit_asphalt = CLOUD_PIT_ASPHALT
		_kerb_colors = CloudLook.RAINBOW
	for i in n:
		var j := (i + 1) % n
		var hl_i := p.width_left[i]
		var hl_j := p.width_left[j]
		var hr_i := p.width_right[i]
		var hr_j := p.width_right[j]
		# Asfalto + faixas de borda
		_strip(road, p, i, j, -hr_i, -hr_j, -hr_i + LINE_WIDTH, -hr_j + LINE_WIDTH, ROAD_Y, LINE)
		_strip(road, p, i, j, -hr_i + LINE_WIDTH, -hr_j + LINE_WIDTH, hl_i - LINE_WIDTH, hl_j - LINE_WIDTH, ROAD_Y, asphalt)
		_strip(road, p, i, j, hl_i - LINE_WIDTH, hl_j - LINE_WIDTH, hl_i, hl_j, ROAD_Y, LINE)
		if sea:
			_led_strip(leds, p, i, j, hl_i - LINE_WIDTH - SEA_LED_INSET, hl_j - LINE_WIDTH - SEA_LED_INSET)
			_led_strip(leds, p, i, j, -hr_i + LINE_WIDTH + SEA_LED_INSET + SEA_LED_WIDTH,
				-hr_j + LINE_WIDTH + SEA_LED_INSET + SEA_LED_WIDTH)
		for side in [1, -1]:
			var k := RaceTrack._si(side)
			var e_i := p.half_width(i, side)
			var e_j := p.half_width(j, side)
			var kw_i := track.layout.kerb_width * smoothstep(0.0, 1.0, track.kerb[k][i])
			var kw_j := track.layout.kerb_width * smoothstep(0.0, 1.0, track.kerb[k][j])
			if kw_i > 0.05 or kw_j > 0.05:
				_kerb(kerbs, p, i, j, side, e_i, e_j, kw_i, kw_j)
			if track.city or track.layout.sky or sea or clouds:
				# Do fim da zebra (ou da faixa dos boxes, onde ela afunila) até a barreira
				var pit_side: bool = side == track.layout.pit_side
				var in_i := maxf(kw_i, track.pit_width[i] if pit_side else 0.0)
				var in_j := maxf(kw_j, track.pit_width[j] if pit_side else 0.0)
				var b_i := track.barrier[k][i]
				var b_j := track.barrier[k][j]
				var verge := DECK_PLATE if track.layout.sky else (SEA_VERGE if sea else VERGE)
				if track.layout.sky and track.open_edge(i, side) and track.open_edge(j, side):
					# Borda aberta: área de escape até a faixa de aviso, e depois dela o vazio
					var h_i := maxf(b_i - HAZARD_WIDTH, in_i)
					var h_j := maxf(b_j - HAZARD_WIDTH, in_j)
					_strip(runoff, p, i, j, side * (e_i + in_i), side * (e_j + in_j), side * (e_i + h_i), side * (e_j + h_j),
						ROAD_Y - 0.004, verge)
					_strip(runoff, p, i, j, side * (e_i + h_i), side * (e_j + h_j), side * (e_i + b_i), side * (e_j + b_j),
						ROAD_Y - 0.002, HAZARD_YELLOW if i % 2 == 0 else HAZARD_DARK)
				elif clouds and (b_i > in_i + 0.05 or b_j > in_j + 0.05):
					_cloud_verge(runoff, p, i, j, side, e_i, e_j, in_i, in_j, maxf(b_i, in_i), maxf(b_j, in_j))
				elif b_i > in_i + 0.05 or b_j > in_j + 0.05:
					_strip(runoff, p, i, j, side * (e_i + in_i), side * (e_j + in_j), side * (e_i + maxf(b_i, in_i) + 0.2),
						side * (e_j + maxf(b_j, in_j) + 0.2), ROAD_Y - 0.004, verge)
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
				ROAD_Y, pit_asphalt)

	_paint_start(track, paint)
	_paint_pit(track, paint)
	var stars := MeshBuilder.new()
	if clouds:
		_paint_hearts(track, paint)
		_paint_stars(track, paint, stars)

	_add_surface(parent, "Road", road, TrackMaterials.surface("asphalt"), TrackSurface.Type.ASPHALT)
	_add_surface(parent, "Kerbs", kerbs, TrackMaterials.surface("kerb"), TrackSurface.Type.KERB)
	_add_surface(parent, "Gravel", gravel, TrackMaterials.surface("gravel"), TrackSurface.Type.GRAVEL)
	# Pista no céu: a faixa entre a pista e a barreira (e a área de escape) é chão de placas de metal
	var runoff_mat := TrackMaterials.surface("asphalt")
	if track.layout.sky:
		runoff_mat = TrackMaterials.metal_plate("runoff", false, true)
	elif sea:
		# Fundo do mar: lajes de pedra (juntas a cada 1,5 m)
		runoff_mat = TrackMaterials.sea_stone("runoff", false, {"no_outline": true, "panel_size": 1.5,
			"grime_strength": 0.3, "moss_amount": 0.25, "coral_amount": 0.03})
	_add_surface(parent, "Runoff", runoff, runoff_mat, TrackSurface.Type.RUNOFF)
	# Pista no céu, no fundo do mar e nas nuvens: não há chão de colisão embaixo dos pisos
	if track.layout.sky or sea or clouds:
		_deck_floor(track, parent)
	if not leds.is_empty():
		var led_mi := MeshInstance3D.new()
		led_mi.name = "EdgeLights"
		led_mi.mesh = leds.commit(null, SkyDeck.glow(0.45, 1.5, 3.2))
		led_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(led_mi)
	var mi := MeshInstance3D.new()
	mi.name = "Paint"
	mi.mesh = paint.commit(null, TrackMaterials.surface("paint"))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if not stars.is_empty():
		var star_mi := MeshInstance3D.new()
		star_mi.name = "StarPads"
		star_mi.mesh = stars.commit(null, CloudLook.glow(1.3, 2.6, 0.5))
		star_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(star_mi)


## Pista no céu: laje de colisão de 1 m logo abaixo dos pisos, de uma borda da plataforma à outra.
## Os pisos são superfícies sem espessura e embaixo não há chão: sem ela, um carro empurrado por
## outro (no box, numa batida) atravessaria o asfalto e cairia. Nas bordas abertas acaba junto com
## a área de escape (dali para fora é o vazio).
static func _deck_floor(track: RaceTrack, parent: Node3D) -> void:
	var p := track.path
	var n := p.size()
	var left := SkyDeck.edges(track, 1)
	var right := SkyDeck.edges(track, -1)
	var body := TrackSurface.make_body("DeckFloor", TrackSurface.Type.RUNOFF)
	for i in n:
		var j := (i + 1) % n
		var fwd := p.points[j] - p.points[i]
		var length := fwd.length()
		if length < 0.01:
			continue
		var z := fwd / length
		var x := p.lefts[i]
		var y := z.cross(x).normalized()
		var lat := (left[i] - right[i]) * 0.5
		var center := (p.points[i] + p.points[j]) * 0.5 + x * lat - y * (DECK_FLOOR_TOP + DECK_FLOOR_THICK * 0.5)
		var shape := BoxShape3D.new()
		shape.size = Vector3(left[i] + right[i], DECK_FLOOR_THICK, length + 0.3)
		var owner_id := body.create_shape_owner(body)
		body.shape_owner_add_shape(owner_id, shape)
		body.shape_owner_set_transform(owner_id, Transform3D(Basis(x, y, z).orthonormalized(), center))
	parent.add_child(body)


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


## Torção máxima (m) de cada pedaço de faixa: acima disso a faixa é dividida na largura.
const MAX_TWIST := 0.0007


## Faixa entre dois deslocamentos laterais (com sinal) de i até j. Numa curva fechada com subida
## ou descida o quadrilátero torce (as duas bordas são retas horizontais em alturas diferentes e
## não paralelas) e os dois triângulos formam um vinco que tira a aderência de um pneu (Curva do
## Portal da Sky Aerobase): onde torce, a faixa vira vários pedaços estreitos.
static func _strip(mb: MeshBuilder, p: TrackPath, i: int, j: int, a_i: float, a_j: float, b_i: float, b_j: float,
		y: float, color: Color) -> void:
	var up := Vector3.UP * y
	var a0 := p.points[i] + p.lefts[i] * a_i + up
	var b0 := p.points[i] + p.lefts[i] * b_i + up
	var b1 := p.points[j] + p.lefts[j] * b_j + up
	var a1 := p.points[j] + p.lefts[j] * a_j + up
	var normal := (b0 - a0).cross(b1 - a0)
	var twist := absf((a1 - a0).dot(normal.normalized())) if normal.length_squared() > 1e-8 else 0.0
	var pieces := clampi(ceili(twist / MAX_TWIST), 1, 12)
	for k in pieces:
		var t0 := float(k) / pieces
		var t1 := float(k + 1) / pieces
		mb.quad(a0.lerp(b0, t0), a0.lerp(b0, t1), a1.lerp(b1, t1), a1.lerp(b1, t0), color)


## Zebra elevada: sobe na borda da pista, plana e desce no fim. Listras de ~2 m (nas nuvens, as seis
## cores do arco-íris em sequência).
static func _kerb(mb: MeshBuilder, p: TrackPath, i: int, j: int, side: int, e_i: float, e_j: float, w_i: float, w_j: float) -> void:
	var color: Color = _kerb_colors[i % _kerb_colors.size()]
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


## Pista fofa nas nuvens: faixa creme do fim da zebra (ou da borda) até a barreira, com as seis
## listras do arco-íris correndo junto ao pé dela (a última passa um pouco por baixo do muro).
static func _cloud_verge(mb: MeshBuilder, p: TrackPath, i: int, j: int, side: int, e_i: float, e_j: float,
		in_i: float, in_j: float, b_i: float, b_j: float) -> void:
	var bands: int = CloudLook.RAINBOW.size()
	var w_i := minf(CLOUD_BAND * bands, maxf(b_i - in_i, 0.0))
	var w_j := minf(CLOUD_BAND * bands, maxf(b_j - in_j, 0.0))
	var r_i := b_i - w_i
	var r_j := b_j - w_j
	if r_i > in_i + 0.02 or r_j > in_j + 0.02:
		_strip(mb, p, i, j, side * (e_i + in_i), side * (e_j + in_j), side * (e_i + r_i), side * (e_j + r_j), ROAD_Y - 0.004, CLOUD_VERGE)
	for k in bands:
		var a_i := r_i + w_i * k / bands
		var a_j := r_j + w_j * k / bands
		var c_i := r_i + w_i * (k + 1) / bands + (0.2 if k == bands - 1 else 0.0)
		var c_j := r_j + w_j * (k + 1) / bands + (0.2 if k == bands - 1 else 0.0)
		_strip(mb, p, i, j, side * (e_i + a_i), side * (e_j + a_j), side * (e_i + c_i), side * (e_j + c_j), ROAD_Y - 0.003,
			CloudLook.RAINBOW[bands - 1 - k])


## Corações brancos pintados no asfalto rosa (pista fofa nas nuvens): um grande vazado no meio da
## pista a cada HEART_SPACING m nas retas e curvas abertas, e um par de pequenos cheios nas faixas a
## cada dois. Fora do grid e dos trechos com zebra.
static func _paint_hearts(track: RaceTrack, mb: MeshBuilder) -> void:
	var p := track.path
	var big := CloudLook.heart(3.4)
	var small := CloudLook.heart(1.3)
	var count := int(p.length / HEART_SPACING)
	for k in count:
		var s := (k + 0.5) * p.length / count
		if track.in_span(s, -track.layout.grid_slots * track.layout.grid_spacing - 20.0, 20.0):
			continue
		var i := p.index_at(s)
		if absf(p.curvature[i]) > 1.0 / 250.0 or track.kerb[0][i] > 0.05 or track.kerb[1][i] > 0.05:
			continue
		# (x para a direita, y para a frente: os lóbulos para a frente, a ponta para quem vem)
		var f := p.frame_at(s, 0.0, PAINT_Y + 0.002)
		var xf := Transform3D(Basis(-f.basis.x, f.basis.y, -f.basis.z), f.origin)
		CloudLook.outline(mb, big, xf, 0.32, LINE, Vector3.UP)
		if k % 2 == 0:
			for lat: float in [-3.6, 3.6]:
				var g := p.frame_at(s + 9.0, lat, PAINT_Y + 0.002)
				CloudLook.fill(mb, small, Transform3D(Basis(-g.basis.x, g.basis.y, -g.basis.z), g.origin), Color(1.0, 0.86, 0.93), Vector3.UP)


## Estrelas acesas no piso (pista fofa nas nuvens): três em fila na saída de cada curva lenta (raio
## menor que 60 m), com o contorno branco pintado em volta.
static func _paint_stars(track: RaceTrack, paint: MeshBuilder, glow: MeshBuilder) -> void:
	var p := track.path
	var n := p.size()
	var shape := CloudLook.star(1.25, 0.5)
	var rim := CloudLook.star(1.55, 0.5)
	var i := 0
	while i < n:
		if absf(p.curvature[i]) > 1.0 / 60.0:
			while i < n and absf(p.curvature[i]) > 1.0 / 90.0:
				i += 1
			var s0 := p.s_at(i) + STAR_AFTER
			var grid := track.layout.grid_slots * track.layout.grid_spacing
			if not track.in_tunnel(p.index_at(s0)) and not track.in_span(s0, -grid - 30.0, 30.0):
				for k in 3:
					var f := p.frame_at(s0 + k * 6.0, 0.0, PAINT_Y + 0.004)
					var xf := Transform3D(Basis(-f.basis.x, f.basis.y, -f.basis.z), f.origin)
					CloudLook.fill(paint, rim, xf, LINE, Vector3.UP)
					CloudLook.fill(glow, shape, Transform3D(xf.basis, xf.origin + Vector3.UP * 0.003), CloudLook.BUTTER * 1.3, Vector3.UP)
		i += 1


## Friso de LED (fundo do mar) de i até j, entre os deslocamentos laterais a - SEA_LED_WIDTH e a;
## UV.x = s (o pulso do sky_glow corre ao longo da pista).
static func _led_strip(mb: MeshBuilder, p: TrackPath, i: int, j: int, a_i: float, a_j: float) -> void:
	var up := Vector3.UP * PAINT_Y
	var s_i := p.s_at(i)
	var s_j := s_i + p.spacing
	mb.quad(p.points[i] + p.lefts[i] * (a_i - SEA_LED_WIDTH) + up, p.points[i] + p.lefts[i] * a_i + up,
		p.points[j] + p.lefts[j] * a_j + up, p.points[j] + p.lefts[j] * (a_j - SEA_LED_WIDTH) + up,
		SEA_LED, Vector3.UP, Vector2(s_i, 0), Vector2(s_i, 1), Vector2(s_j, 1), Vector2(s_j, 0))


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
