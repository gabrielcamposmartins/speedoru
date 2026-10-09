class_name TrackTunnel
extends RefCounted
## Túnel de um circuito de rua (trecho [s0, s1] da pista, dado pela cidade): paredes de azulejo
## atrás das barreiras, teto com laje grossa (o terreno da cidade fica em cima dela), duas fileiras
## de luminárias, luzes alaranjadas e os portais nas duas bocas. Sondas de reflexo com ambiente
## escuro deixam o interior na penumbra mesmo de dia (o céu não ilumina lá dentro).

const HEIGHT := 7.0
const SLAB := 1.5
const WALL_THICK := 0.8
## A laje passa das paredes para cobrir o buraco que o terreno deixa sobre o túnel.
const SLAB_OVERHANG := 11.0
const TILE := Color(0.86, 0.83, 0.74)
const TILE_LOW := Color(0.32, 0.33, 0.36)
const CEILING := Color(0.24, 0.24, 0.27)
const PORTAL := Color(0.8, 0.78, 0.72)
const LAMP := Color(1.0, 0.84, 0.58)
const LIGHT_SPACING := 24.0


static func build(track: RaceTrack, s0: float, s1: float, parent: Node3D) -> void:
	var p := track.path
	var root := Node3D.new()
	root.name = "Tunnel"
	parent.add_child(root)
	var walls := MeshBuilder.new()
	var lamps := MeshBuilder.new()
	var idxs := track.span_indices(s0, s1)
	for k in idxs.size() - 1:
		var i := idxs[k]
		var j := idxs[k + 1]
		for side: int in [1, -1]:
			var si := RaceTrack._si(side)
			# Face interna logo atrás da barreira
			var d_i := track.barrier[si][i] + 0.6
			var d_j := track.barrier[si][j] + 0.6
			var inward := -p.lefts[i] * side
			var a0 := track.edge_point(i, side, d_i, 1.2)
			var b0 := track.edge_point(j, side, d_j, 1.2)
			var a1 := track.edge_point(i, side, d_i, 2.6)
			var b1 := track.edge_point(j, side, d_j, 2.6)
			var a2 := track.edge_point(i, side, d_i, HEIGHT)
			var b2 := track.edge_point(j, side, d_j, HEIGHT)
			walls.quad(a0, b0, b1, a1, TILE_LOW, inward)
			var tile := TILE if (i / 2) % 2 == 0 else TILE * 0.96
			walls.quad(a1, b1, b2, a2, tile, inward)
			# Parede por fora (vista de quem olha do mar ou do terreno ao lado)
			var o_i := d_i + WALL_THICK
			var o_j := d_j + WALL_THICK
			walls.quad(track.edge_point(i, side, o_i, -1.0), track.edge_point(j, side, o_j, -1.0),
				track.edge_point(j, side, o_j, HEIGHT), track.edge_point(i, side, o_i, HEIGHT), PORTAL * 0.9, -inward)
		# Teto (face de baixo) e laje (face de cima, com o mesmo piso da cidade)
		var li := track.barrier[0][i] + 0.6
		var lj := track.barrier[0][j] + 0.6
		var ri := track.barrier[1][i] + 0.6
		var rj := track.barrier[1][j] + 0.6
		walls.quad(track.edge_point(i, 1, li, HEIGHT), track.edge_point(j, 1, lj, HEIGHT),
			track.edge_point(j, -1, rj, HEIGHT), track.edge_point(i, -1, ri, HEIGHT), CEILING, Vector3.DOWN)
		var top := HEIGHT + SLAB
		walls.quad(track.edge_point(i, 1, li + SLAB_OVERHANG, top), track.edge_point(j, 1, lj + SLAB_OVERHANG, top),
			track.edge_point(j, -1, rj + SLAB_OVERHANG, top), track.edge_point(i, -1, ri + SLAB_OVERHANG, top),
			TrackCity.PAVEMENT, Vector3.UP)
		for side: int in [1, -1]:
			var si := RaceTrack._si(side)
			var d_i := track.barrier[si][i] + 0.6 + SLAB_OVERHANG
			var d_j := track.barrier[si][j] + 0.6 + SLAB_OVERHANG
			walls.quad(track.edge_point(i, side, d_i, top - 3.0), track.edge_point(j, side, d_j, top - 3.0),
				track.edge_point(j, side, d_j, top), track.edge_point(i, side, d_i, top), PORTAL * 0.85, p.lefts[i] * side)
		# Luminárias: duas fileiras no teto
		if k % 2 == 0:
			for lat: float in [2.6, -2.6]:
				var f := p.frame_at(p.s_at(i), lat, HEIGHT - 0.12)
				lamps.box(f, Vector3(0.5, 0.16, 2.4), LAMP)
	_portal(track, walls, s0, 1.0)
	_portal(track, walls, s1, -1.0)
	var mi := MeshInstance3D.new()
	mi.name = "Structure"
	mi.mesh = walls.commit(null, TrackMaterials.building("tunnel", false, {"panel_size": 0.6, "ground_dirt": 0.5}))
	lamps.commit(mi.mesh as ArrayMesh, TrackMaterials.lamp(2.5))
	root.add_child(mi)
	if track.city:
		# Muros de ala nas duas bocas (pedra com hera, o shader do chão da cidade)
		var wing := MeshBuilder.new()
		_wing_walls(track, wing, s0, 1.0)
		_wing_walls(track, wing, s1, -1.0)
		if not wing.is_empty():
			var wmi := MeshInstance3D.new()
			wmi.name = "WingWalls"
			wmi.mesh = wing.commit(null, TrackCity.ground_material())
			root.add_child(wmi)
	if RaceTrack.server_mode:
		return
	# Luzes de sódio (sem sombra) e penumbra
	var length := fposmod(s1 - s0, p.length)
	var count := int(length / LIGHT_SPACING)
	for n in count:
		var s := s0 + (n + 0.5) * length / count
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.78, 0.5)
		light.light_energy = 1.6
		light.omni_range = 20.0
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		root.add_child(light)
		light.global_position = p.frame_at(s, 0.0, HEIGHT - 1.2).origin
	var seg := 60.0
	var probes := maxi(int(ceil(length / seg)), 1)
	for n in probes:
		var s := s0 + (n + 0.5) * length / probes
		var f := p.frame_at(s)
		var probe := ReflectionProbe.new()
		probe.name = "Shade%d" % n
		probe.interior = true
		probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
		probe.ambient_color = Color(0.16, 0.14, 0.12)
		probe.ambient_color_energy = 1.0
		probe.intensity = 0.35
		probe.blend_distance = 6.0
		var half_w := maxf(p.width_left[p.index_at(s)], p.width_right[p.index_at(s)]) + 3.0
		probe.size = Vector3(half_w * 2.0, HEIGHT + 1.0, length / probes + 8.0)
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		root.add_child(probe)
		probe.global_transform = Transform3D(f.basis, f.origin + f.basis.y * (HEIGHT * 0.5))


## Comprimento dos muros de ala na aproximação de cada boca (m).
const WING_LENGTH := 60.0


## Muros de ala na aproximação de uma boca (dir = +1 na entrada, -1 na saída): muro de arrimo logo
## atrás da barreira, dos dois lados, da altura do barranco atrás dele (até o topo do portal), com
## capa. Seguram o terreno que sobe da pista até a laje (sem rampas pontudas ao lado do portal).
static func _wing_walls(track: RaceTrack, mb: MeshBuilder, s_portal: float, dir: float) -> void:
	var p := track.path
	var city := track.city
	var wall := Color(TrackCity.lin(TrackCity.RETAINING), TrackCity.FLOOR_WALL)
	var cap := Color(TrackCity.lin(Color(0.8, 0.76, 0.68)), TrackCity.FLOOR_SIDEWALK)
	var step := 3.0
	var n := int(WING_LENGTH / step)
	for side: int in [1, -1]:
		var si := RaceTrack._si(side)
		var prev_base := Vector3.INF
		var prev_top := Vector3.INF
		for k in n + 1:
			# Da boca para fora (k = 0 na boca)
			var s := s_portal - dir * k * step
			var i := p.index_at(s)
			var lat: float = side * (p.half_width(i, side) + track.barrier[si][i] + 0.4)
			var road := p.frame_at(s, 0.0, 0.0).origin
			# O barranco mais alto numa faixa de 1 a 12 m atrás do muro (do lado do mar ele é uma
			# crista estreita: logo atrás o chão cai)
			var ground := -INF
			for extra: float in [1.0, 3.0, 5.0, 8.0, 12.0]:
				var q := p.frame_at(s, lat + side * extra, 0.0).origin
				ground = maxf(ground, city.height_at(q.x, q.z))
			var hgt := clampf(ground - road.y + 0.4, 0.0, HEIGHT + SLAB + 2.5)
			var base := p.frame_at(s, lat, -0.5).origin
			var top := Vector3(base.x, road.y + hgt, base.z)
			if prev_base != Vector3.INF and (hgt > 0.6 or prev_top.y - prev_base.y > 1.1):
				var out := -p.lefts[i] * side
				mb.quad(prev_base, base, top, prev_top, wall, out)
				# Capa do muro (0,7 m para trás)
				var back := p.lefts[i] * side * 0.7
				mb.quad(prev_top, top, top + back, prev_top + back, cap, Vector3.UP)
			prev_base = base
			prev_top = top


## Portal numa boca do túnel: pilares dos dois lados e a viga sobre a abertura, até o terreno.
## dir = +1 na entrada (a fachada olha para trás), -1 na saída.
static func _portal(track: RaceTrack, mb: MeshBuilder, s: float, dir: float) -> void:
	var p := track.path
	var i := p.index_at(s)
	var f := p.frame_at(s)
	f.basis = Basis(f.basis.x, Vector3.UP, f.basis.x.cross(Vector3.UP).normalized())
	var inner_l := p.width_left[i] + track.barrier[0][i] + 0.6
	var inner_r := p.width_right[i] + track.barrier[1][i] + 0.6
	var outer := 16.0
	var depth := 1.2
	var top := HEIGHT + SLAB + 2.5
	# Em circuito de rua o chão sobre a laje pode ficar mais alto que o portal: pilares e viga sobem
	# até ele (a boca vira uma frente contínua, sem o barranco aparecendo por cima)
	var pillar := HEIGHT + 1.0
	if track.city:
		var behind := 0.0
		for ds: float in [1.0, 4.0, 8.0, 12.0, 16.0]:
			for side: int in [1, -1]:
				var inner0: float = inner_l if side > 0 else inner_r
				for extra: float in [0.0, 4.0, 8.0, 12.0, outer]:
					var q := p.frame_at(s + dir * ds, side * (inner0 + extra), 0.0).origin
					behind = maxf(behind, track.city.height_at(q.x, q.z) - f.origin.y)
		top = clampf(maxf(top, behind + 0.4), top, 18.0)
		pillar = maxf(pillar, minf(behind + 0.4, 18.0))
	var back := f.basis.z * (-dir * depth * 0.5)
	# Viga (com friso) e pilares
	var lintel_w := inner_l + inner_r + 2.0 * outer
	var center_lat := (inner_l - inner_r) * 0.5
	mb.box(Transform3D(f.basis, f.origin + f.basis.x * center_lat + Vector3.UP * (HEIGHT + (top - HEIGHT) * 0.5) + back),
		Vector3(lintel_w, top - HEIGHT, depth), PORTAL)
	# Friso escuro no alto da viga (dá escala à frente alta)
	mb.box(Transform3D(f.basis, f.origin + f.basis.x * center_lat + Vector3.UP * (top - 0.3) + back - f.basis.z * dir * 0.1),
		Vector3(lintel_w, 0.6, depth + 0.2), TILE_LOW)
	mb.box(Transform3D(f.basis, f.origin + f.basis.x * center_lat + Vector3.UP * (HEIGHT + 0.25) + back - f.basis.z * dir * 0.35),
		Vector3(inner_l + inner_r, 0.5, 0.3), TILE_LOW)
	for side: int in [1, -1]:
		var inner := inner_l if side > 0 else inner_r
		var lat := side * (inner + outer * 0.5)
		mb.box(Transform3D(f.basis, f.origin + f.basis.x * lat + Vector3.UP * (pillar * 0.5 - 1.0) + back),
			Vector3(outer, pillar + 1.0, depth), PORTAL)
