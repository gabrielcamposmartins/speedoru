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
## Pista no céu: muro de placas de metal escuro com o topo arredondado e a faixa de anúncios em
## holograma correndo (holo_ads.gdshader).
const SKY_METAL := Color(0.36, 0.38, 0.43)
const SKY_HEIGHT := 1.25
const SKY_THICK := 0.6
const HOLO_BOTTOM := 0.14
const HOLO_TOP := 0.68
## Pista no fundo do mar: mureta de pedra com o topo arredondado, painel de vidro em cima (com
## montantes a cada 8 m) e friso de LED ciano no alto do vidro. A colisão é a mesma das outras.
const SEA_STONE := Color(0.8, 0.79, 0.74)
const SEA_BASE := 0.62
const SEA_THICK := 0.55
const SEA_GLASS_TOP := 1.75
const SEA_MULLION := Color(0.32, 0.36, 0.4)
## Pista fofa nas nuvens: muro acolchoado cor-de-rosa com o topo arredondado, um rolo de almofada
## creme por cima e corações acesos na face a cada CLOUD_HEART_EVERY amostras.
const CLOUD_PINK := Color(1.0, 0.4, 0.64)
const CLOUD_ROLL := Color(1.0, 0.93, 0.96)
const CLOUD_HEIGHT := 1.2
const CLOUD_THICK := 0.7
const CLOUD_ROLL_RADIUS := 0.2
const CLOUD_HEART_EVERY := 5
const CLOUD_HEART := Color(1.0, 0.3, 0.62)



static func build(track: RaceTrack, parent: Node3D) -> void:
	var p := track.path
	var n := p.size()
	var walls := MeshBuilder.new()
	var fence := MeshBuilder.new()
	# Pista no céu: sem alambrado (a vista é o céu); friso de LED azul no alto do muro
	var sky := track.layout.sky
	var sea := track.layout.undersea
	var clouds := track.layout.clouds
	var hearts := MeshBuilder.new()
	var glass := MeshBuilder.new()
	var leds := MeshBuilder.new()
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
			if sky:
				height = SKY_HEIGHT
				thick = SKY_THICK
				protect = false
			elif sea:
				height = SEA_BASE
				thick = SEA_THICK
				protect = false
			elif clouds:
				height = CLOUD_HEIGHT
				thick = CLOUD_THICK
				protect = false
			var front_i := d_i
			var front_j := d_j
			if protect:
				# Blocos de proteção alternando vermelho/branco
				var c := RED if (i / 2) % 2 == 0 else WHITE
				_wall(walls, track, i, j, side, d_i - 1.1, d_j - 1.1, 1.1, 1.05, [[0.0, 1.05, c]])
				front_i -= 1.1
				front_j -= 1.1
			if sky:
				_round_wall(walls, track, i, j, side, d_i, d_j, thick, height, SKY_METAL)
			elif sea:
				_round_wall(walls, track, i, j, side, d_i, d_j, thick, height, SEA_STONE)
				_glass_panel(glass, walls, leds, track, i, j, side, d_i + thick * 0.5, d_j + thick * 0.5)
			elif clouds:
				_cloud_wall(walls, hearts, track, i, j, side, d_i, d_j)
			elif kind == RaceTrack.Barrier.CONCRETE:
				var top := RED if (i / 2) % 2 == 0 else WHITE
				_wall(walls, track, i, j, side, d_i, d_j, thick, height, [[0.0, 1.0, CONCRETE], [1.0, height, top]])
			else:
				_wall(walls, track, i, j, side, d_i, d_j, thick, height,
					[[0.0, 0.3, STEEL_DARK], [0.3, 0.58, STEEL], [0.58, 0.64, STEEL_DARK], [0.64, 0.92, STEEL], [0.92, height, STEEL_DARK]])
			# Circuito de rua: muro de contenção sob a barreira (onde a pista passa acima do chão
			# ao lado, ex. Mirabeau sobre o Mirabeau Bas)
			if track.city:
				var back_i := d_i + thick
				var back_j := d_j + thick
				walls.quad(track.edge_point(i, side, back_i, -12.0), track.edge_point(j, side, back_j, -12.0),
					track.edge_point(j, side, back_j, 0.05), track.edge_point(i, side, back_i, 0.05),
					CONCRETE * 0.85, p.lefts[i] * side)
			# Alambrado sobre a barreira (no túnel e no céu não há)
			var fl_i := d_i + thick * 0.5
			var fl_j := d_j + thick * 0.5
			var s_i := p.s_at(i)
			var s_j := s_i + p.spacing
			if sky:
				leds.quad(track.edge_point(i, side, d_i - 0.02, 0.76), track.edge_point(j, side, d_j - 0.02, 0.76),
					track.edge_point(j, side, d_j - 0.02, 0.86), track.edge_point(i, side, d_i - 0.02, 0.86),
					SkyDeck.LED, -p.lefts[i] * side, Vector2(s_i, 0), Vector2(s_j, 0), Vector2(s_j, 1), Vector2(s_i, 1))
			elif sea or clouds:
				pass  # o vidro (no mar) e o rolo de almofada (nas nuvens) fazem o papel do alambrado
			elif not track.in_tunnel(i):
				fence.quad(track.edge_point(i, side, fl_i, height), track.edge_point(j, side, fl_j, height),
					track.edge_point(j, side, fl_j, height + FENCE_HEIGHT), track.edge_point(i, side, fl_i, height + FENCE_HEIGHT),
					Color.WHITE, -p.lefts[i] * side,
					Vector2(s_i, 0), Vector2(s_j, 0), Vector2(s_j, FENCE_HEIGHT), Vector2(s_i, FENCE_HEIGHT))
				if i % 2 == 0:
					var base := track.edge_point(i, side, fl_i, 0.0)
					var flat := Vector3(p.tangents[i].x, 0.0, p.tangents[i].z)
					var post_xf := Transform3D(Basis.looking_at(flat), base + Vector3.UP * (height + FENCE_HEIGHT) * 0.5)
					walls.posts().box(post_xf, Vector3(0.09, height + FENCE_HEIGHT, 0.09), POST)
			# Colisão: bloco sólido atrás da face (paredes finas deixam o carro atravessar em alta velocidade)
			collision.append(_wall_box(track.edge_point(i, side, front_i), track.edge_point(j, side, front_j),
				p.lefts[i] * side, COLLISION_THICKNESS))
			# Anúncios na face da barreira
			for f in ad_spans:
				if side in f.sides() and track.in_span(s_i, f.s_start, f.s_end):
					if sky:
						_holo_segment(ads, track, i, j, side, front_i - 0.06, front_j - 0.06, f)
					else:
						_ad_segment(ads, track, i, j, side, front_i - 0.03, front_j - 0.03, minf(height, 1.0), f)
					break

	_build_pit_wall(track, walls, fence, collision, glass, leds, hearts)

	var body := TrackSurface.make_body("Barriers", TrackSurface.Type.BARRIER)
	var wall_mi := MeshInstance3D.new()
	wall_mi.name = "Walls"
	wall_mi.mesh = walls.commit(null, TrackMaterials.barrier())
	body.add_child(wall_mi)
	if not leds.is_empty():
		# Céu: na cor dos LEDs da pista (SkyLights); fundo do mar: ciano da cor de vértice
		leds.commit(wall_mi.mesh as ArrayMesh, SkyDeck.glow(0.5, 1.5, 3.4, not sea))
	if not hearts.is_empty():
		var hearts_mi := MeshInstance3D.new()
		hearts_mi.name = "Hearts"
		hearts_mi.mesh = hearts.commit(null, CloudLook.glow(1.6, 3.2))
		hearts_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(hearts_mi)
	if not glass.is_empty():
		var glass_mi := MeshInstance3D.new()
		glass_mi.name = "Glass"
		glass_mi.mesh = glass.commit(null, TrackMaterials.sea_glass())
		glass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(glass_mi)
	var fence_mi := MeshInstance3D.new()
	fence_mi.name = "Fence"
	fence_mi.mesh = fence.commit(null, TrackMaterials.fence())
	fence_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(fence_mi)
	if not ads.is_empty():
		var ads_mi := MeshInstance3D.new()
		ads_mi.name = "BarrierAds"
		ads_mi.mesh = ads.commit(null, TrackAds.holo_material(true) if sky else TrackMaterials.ads())
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


## Muro com o topo arredondado (pista no céu): face reta até `height - thick/2`, meia-cana em cima
## e a face de trás.
static func _round_wall(mb: MeshBuilder, track: RaceTrack, i: int, j: int, side: int, d_i: float, d_j: float,
		thick: float, height: float, color: Color) -> void:
	var to_track := -track.path.lefts[i] * side
	var r := thick * 0.5
	var straight := height - r
	mb.quad(track.edge_point(i, side, d_i, 0.0), track.edge_point(j, side, d_j, 0.0),
		track.edge_point(j, side, d_j, straight), track.edge_point(i, side, d_i, straight), color, to_track)
	mb.quad(track.edge_point(i, side, d_i + thick, 0.0), track.edge_point(j, side, d_j + thick, 0.0),
		track.edge_point(j, side, d_j + thick, straight), track.edge_point(i, side, d_i + thick, straight),
		color.darkened(0.15), -to_track)
	var segs := 6
	for k in segs:
		var a0 := PI * k / segs
		var a1 := PI * (k + 1) / segs
		var am := (a0 + a1) * 0.5
		mb.quad(track.edge_point(i, side, d_i + r - r * cos(a0), straight + r * sin(a0)),
			track.edge_point(j, side, d_j + r - r * cos(a0), straight + r * sin(a0)),
			track.edge_point(j, side, d_j + r - r * cos(a1), straight + r * sin(a1)),
			track.edge_point(i, side, d_i + r - r * cos(a1), straight + r * sin(a1)),
			color * 1.12, to_track * cos(am) + Vector3.UP * sin(am))


## Pista fofa nas nuvens: muro acolchoado (i → j) com o topo arredondado, o rolo de almofada creme em
## cima (tubo de 8 lados) e, a cada CLOUD_HEART_EVERY amostras, um coração aceso na face (um menor
## e mais claro na frente dele).
static func _cloud_wall(mb: MeshBuilder, hearts: MeshBuilder, track: RaceTrack, i: int, j: int, side: int,
		d_i: float, d_j: float, height := CLOUD_HEIGHT) -> void:
	var p := track.path
	var to_track := -p.lefts[i] * side
	_round_wall(mb, track, i, j, side, d_i, d_j, CLOUD_THICK, height, CLOUD_PINK)
	var r := CLOUD_ROLL_RADIUS
	var c_i := track.edge_point(i, side, d_i + CLOUD_THICK * 0.5, height + r * 0.55)
	var c_j := track.edge_point(j, side, d_j + CLOUD_THICK * 0.5, height + r * 0.55)
	var segs := 8
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var o0 := to_track * cos(a0) + Vector3.UP * sin(a0)
		var o1 := to_track * cos(a1) + Vector3.UP * sin(a1)
		var shade := 0.9 + 0.1 * sin((a0 + a1) * 0.5)
		mb.quad(c_i + o0 * r, c_j + o0 * r, c_j + o1 * r, c_i + o1 * r, CLOUD_ROLL * shade, o0 + o1)
	if i % CLOUD_HEART_EVERY == 0:
		var face := track.edge_point(i, side, d_i - 0.03, height * 0.5)
		var basis := Basis(Vector3.UP.cross(to_track).normalized(), Vector3.UP, to_track)
		CloudLook.slab(hearts, CloudLook.heart(0.82, 22), Transform3D(basis, face), 0.06, CLOUD_HEART)
		CloudLook.slab(hearts, CloudLook.heart(0.42, 16), Transform3D(basis, face + to_track * 0.035), 0.02, Color(1.0, 0.86, 0.95))


## Fundo do mar: painel de vidro (i → j) no meio da mureta de pedra, de SEA_BASE a SEA_GLASS_TOP, com
## friso de LED ciano no alto (UV.x = s, para o pulso) e um montante de metal a cada 4 amostras.
static func _glass_panel(glass: MeshBuilder, walls: MeshBuilder, leds: MeshBuilder, track: RaceTrack, i: int, j: int,
		side: int, g_i: float, g_j: float, base := SEA_BASE) -> void:
	var p := track.path
	var to_track := -p.lefts[i] * side
	var s_i := p.s_at(i)
	var s_j := s_i + p.spacing
	glass.quad(track.edge_point(i, side, g_i, base), track.edge_point(j, side, g_j, base),
		track.edge_point(j, side, g_j, SEA_GLASS_TOP), track.edge_point(i, side, g_i, SEA_GLASS_TOP),
		Color.WHITE, to_track, Vector2(s_i, 0), Vector2(s_j, 0), Vector2(s_j, 1), Vector2(s_i, 1))
	leds.quad(track.edge_point(i, side, g_i - 0.03, SEA_GLASS_TOP - 0.06), track.edge_point(j, side, g_j - 0.03, SEA_GLASS_TOP - 0.06),
		track.edge_point(j, side, g_j - 0.03, SEA_GLASS_TOP + 0.04), track.edge_point(i, side, g_i - 0.03, SEA_GLASS_TOP + 0.04),
		TrackRoad.SEA_LED, to_track, Vector2(s_i, 0), Vector2(s_j, 0), Vector2(s_j, 1), Vector2(s_i, 1))
	if i % 4 == 0:
		var flat := Vector3(p.tangents[i].x, 0.0, p.tangents[i].z)
		var mid := track.edge_point(i, side, g_i, (base + SEA_GLASS_TOP) * 0.5)
		walls.posts().box(Transform3D(Basis.looking_at(flat), mid), Vector3(0.07, SEA_GLASS_TOP - base, 0.09), SEA_MULLION)


## Uma fatia (i → j) da faixa de anúncios em holograma (pista no céu): UV.x = metros ao longo da
## faixa (do lado direito ao contrário, para o texto ler certo); a marca e o movimento são do shader.
static func _holo_segment(mb: MeshBuilder, track: RaceTrack, i: int, j: int, side: int, d_i: float, d_j: float,
		f: TrackFeature) -> void:
	var s_i := track.path.s_at(i) + f.variant * 37.0
	var s_j := s_i + track.path.spacing
	var u_i := s_i if side > 0 else -s_i
	var u_j := s_j if side > 0 else -s_j
	mb.quad(track.edge_point(i, side, d_i, HOLO_BOTTOM), track.edge_point(j, side, d_j, HOLO_BOTTOM),
		track.edge_point(j, side, d_j, HOLO_TOP), track.edge_point(i, side, d_i, HOLO_TOP), Color.WHITE,
		-track.path.lefts[i] * side, Vector2(u_i, 0), Vector2(u_j, 0), Vector2(u_j, 1), Vector2(u_i, 1))


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
static func _build_pit_wall(track: RaceTrack, walls: MeshBuilder, fence: MeshBuilder, collision: Array,
		glass: MeshBuilder = null, leds: MeshBuilder = null, hearts: MeshBuilder = null) -> void:
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
		if track.layout.sky:
			_round_wall(walls, track, i, j, side, 1.2, 1.2, 0.6, 1.1, SKY_METAL)
		elif track.layout.undersea and glass:
			# Fundo do mar: mureta de pedra com vidro, como as barreiras (sem tela)
			_round_wall(walls, track, i, j, side, 1.2, 1.2, 0.6, SEA_BASE, SEA_STONE)
			_glass_panel(glass, walls, leds, track, i, j, side, 1.5, 1.5)
			collision.append(_wall_box(track.edge_point(i, side, 1.2), track.edge_point(j, side, 1.2), p.lefts[i] * side, 0.6))
			continue
		elif track.layout.clouds and hearts:
			# Nuvens: o mesmo muro acolchoado das barreiras (sem tela)
			_cloud_wall(walls, hearts, track, i, j, side, 1.2, 1.2, 1.1)
			collision.append(_wall_box(track.edge_point(i, side, 1.2), track.edge_point(j, side, 1.2), p.lefts[i] * side, 0.6))
			continue
		else:
			_wall(walls, track, i, j, side, 1.2, 1.2, 0.6, 1.1, [[0.0, 0.95, CONCRETE], [0.95, 1.1, top]])
		var s_i := p.s_at(i)
		fence.quad(track.edge_point(i, side, 1.5, 1.1), track.edge_point(j, side, 1.5, 1.1),
			track.edge_point(j, side, 1.5, 3.4), track.edge_point(i, side, 1.5, 3.4), Color.WHITE, -p.lefts[i] * side,
			Vector2(s_i, 0), Vector2(s_i + p.spacing, 0), Vector2(s_i + p.spacing, 2.3), Vector2(s_i, 2.3))
		if i % 2 == 0:
			walls.posts().box(Transform3D(Basis.looking_at(p.tangents[i]), track.edge_point(i, side, 1.5, 1.7)),
				Vector3(0.08, 3.4, 0.08), POST)
		collision.append(_wall_box(track.edge_point(i, side, 1.2), track.edge_point(j, side, 1.2), p.lefts[i] * side, 0.6))
