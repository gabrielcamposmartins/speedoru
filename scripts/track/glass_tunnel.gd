class_name GlassTunnel
extends RefCounted
## O túnel da pista no fundo do mar (layout.tunnel): um tubo de vidro sobre a pista, de barreira a
## barreira, com nervuras de bronze com pátina (o mesmo do tubo grande, sea_bronze.gdshader) a cada
## RIB_SPACING m (luzes amarelas embaixo e um friso ciano por dentro), uma viga no topo, estandartes de
## Atlântida entre as nervuras e portais de pedra nas duas pontas. Visto de dentro, o mar, as ruínas e os bichos passam por cima.
## Nada aqui tem colisão (as barreiras do túnel seguram o carro).

const HEIGHT := 8.8
const RIB_SPACING := 8.0
const ARC := 16
const RIB := 0.45
const RIB_DEPTH := 0.4
## Folga além da face de fora da barreira até a base do tubo (m).
const BASE_GAP := 0.8
const METAL := SeaTube.METAL
const STONE := Color(0.84, 0.81, 0.74)
const LAMP := Color(1.0, 0.82, 0.42)
const LED := Color(0.25, 0.95, 1.0)
const BANNER_EVERY := 4
const LIGHT_SPACING := 30.0
const NIGHT_LIGHT_ENERGY := 4.5


static func build(track: RaceTrack, s0: float, s1: float, parent: Node3D) -> void:
	var p := track.path
	var root := Node3D.new()
	root.name = "Tunnel"
	parent.add_child(root)
	var glass := MeshBuilder.new()
	var metal := MeshBuilder.new()
	var stone := MeshBuilder.new()
	var lamps := MeshBuilder.new()
	var leds := MeshBuilder.new()
	var banners := MeshBuilder.new()
	var idxs := track.span_indices(s0, s1)
	for k in idxs.size() - 1:
		var i := idxs[k]
		var j := idxs[k + 1]
		var s_i := p.s_at(i)
		var s_j := s_i + p.spacing
		for n in ARC:
			var t0 := float(n) / ARC
			var t1 := float(n + 1) / ARC
			glass.quad(_arc(track, i, t0), _arc(track, j, t0), _arc(track, j, t1), _arc(track, i, t1), Color.WHITE,
				_arc_normal(track, i, (t0 + t1) * 0.5), Vector2(s_i, t0), Vector2(s_j, t0), Vector2(s_j, t1), Vector2(s_i, t1))
		# Viga no topo e friso ciano ao pé do vidro, dos dois lados
		var top_i := _arc(track, i, 0.5, 0.25)
		var top_j := _arc(track, j, 0.5, 0.25)
		metal.box(Transform3D(_along(top_i, top_j), (top_i + top_j) * 0.5), Vector3(0.5, 0.35, top_i.distance_to(top_j) + 0.02), METAL * 0.8)
		for t: float in [0.0, 1.0]:
			var a := _arc(track, i, t, 0.12)
			var b := _arc(track, j, t, 0.12)
			leds.quad(a, b, b + Vector3.UP * 0.12, a + Vector3.UP * 0.12, LED, -p.lefts[i] * (1.0 if t > 0.5 else -1.0),
				Vector2(s_i, 0), Vector2(s_j, 0), Vector2(s_j, 1), Vector2(s_i, 1))
	var length := fposmod(s1 - s0, p.length)
	var ribs := int(length / RIB_SPACING)
	for r in ribs + 1:
		var s := s0 + r * length / ribs
		var portal := r == 0 or r == ribs
		_rib(track, stone if portal else metal, lamps, leds, s, 2.2 if portal else RIB, 1.4 if portal else RIB_DEPTH, portal)
		if not portal and r % BANNER_EVERY == 2:
			var side := 1 if (r / BANNER_EVERY) % 2 == 0 else -1
			var i := p.index_at(s + RIB_SPACING * 0.5)
			var lat := side * (_edge(track, i, side) - 0.5)
			var top := p.frame_at(s + RIB_SPACING * 0.5, lat, 5.4).origin
			AtlantisRuins.add_banner(banners, top, p.tangents[i], -p.lefts[i] * side, 1.5, 3.8)
	var glass_mi := MeshInstance3D.new()
	glass_mi.name = "Glass"
	glass_mi.mesh = glass.commit(null, TrackMaterials.sea_glass(RIB_SPACING))
	glass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glass_mi)
	var mi := MeshInstance3D.new()
	mi.name = "Frame"
	mi.mesh = metal.commit(null, TrackMaterials.sea_bronze("glass_tunnel"))
	stone.commit(mi.mesh as ArrayMesh, TrackMaterials.sea_stone("tunnel_portal", false, {"no_outline": true, "panel_size": 1.0}))
	lamps.commit(mi.mesh as ArrayMesh, SkyDeck.glow(0.0, 1.8, 3.4))
	leds.commit(mi.mesh as ArrayMesh, SkyDeck.glow(0.35, 1.6, 3.4))
	root.add_child(mi)
	if not banners.is_empty():
		var bmi := MeshInstance3D.new()
		bmi.name = "Banners"
		bmi.mesh = banners.commit(null, AtlantisRuins.banner_material())
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bmi)
	if RaceTrack.server_mode:
		return
	# Luz ciano fraca lá dentro e, à noite, refletores na viga (grupo "night_lights")
	var count := maxi(int(length / LIGHT_SPACING), 1)
	for n in count:
		var light := OmniLight3D.new()
		light.light_color = Color(0.55, 0.9, 1.0)
		light.light_energy = 0.9
		light.omni_range = 16.0
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		root.add_child(light)
		light.global_position = p.frame_at(s0 + (n + 0.5) * length / count, 0.0, HEIGHT - 1.5).origin
	var night := maxi(int(length / 12.0), 1)
	for n in night:
		var s := s0 + (n + 0.5) * length / night
		var spot := SpotLight3D.new()
		spot.light_color = Color(0.85, 0.96, 1.0)
		spot.light_energy = NIGHT_LIGHT_ENERGY
		spot.set_meta("base_energy", NIGHT_LIGHT_ENERGY)
		spot.spot_range = 16.0
		spot.spot_angle = 70.0
		spot.spot_attenuation = 0.6
		spot.shadow_enabled = false
		spot.visible = false
		spot.add_to_group("night_lights")
		root.add_child(spot)
		spot.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, p.tangents[p.index_at(s)]),
			p.frame_at(s, 0.0, HEIGHT - 0.6).origin)


## Distância da linha central até a base do tubo do lado `side` (fora da barreira).
static func _edge(track: RaceTrack, i: int, side: int) -> float:
	return track.path.half_width(i, side) + track.barrier[RaceTrack._si(side)][i] + TrackBarriers.SEA_THICK + BASE_GAP


## Ponto do arco no índice i: t = 0 na base direita, 1 na esquerda; `inset` para dentro do tubo.
static func _arc(track: RaceTrack, i: int, t: float, inset := 0.0) -> Vector3:
	var p := track.path
	var a := -_edge(track, i, -1)
	var b := _edge(track, i, 1)
	var half := (b - a) * 0.5
	var mid := (a + b) * 0.5
	var ang := PI * t
	var lat := mid - cos(ang) * (half - inset)
	var y := sin(ang) * (HEIGHT - inset)
	return p.points[i] + p.lefts[i] * lat + Vector3.UP * y


## Normal para dentro do tubo (o vidro é visto dos dois lados; a do arco serve de referência).
static func _arc_normal(track: RaceTrack, i: int, t: float) -> Vector3:
	var ang := PI * t
	return (track.path.lefts[i] * cos(ang) - Vector3.UP * sin(ang)).normalized()


static func _along(a: Vector3, b: Vector3) -> Basis:
	var z := (b - a).normalized()
	var x := Vector3.UP.cross(z).normalized()
	return Basis(x, z.cross(x), z)


## Uma nervura (ou o portal, mais grosso, de pedra) em s: caixas ao longo do arco, luzes amarelas
## na parte de baixo e um friso ciano na face de dentro.
static func _rib(track: RaceTrack, mb: MeshBuilder, lamps: MeshBuilder, leds: MeshBuilder, s: float, thick: float,
		depth: float, portal: bool) -> void:
	var p := track.path
	var i := p.index_at(s)
	var tangent := p.tangents[i]
	var prev := _arc(track, i, 0.0, -depth * 0.5)
	for n in ARC:
		var t1 := float(n + 1) / ARC
		var q := _arc(track, i, t1, -depth * 0.5)
		var y := (q - prev).normalized()
		var x := tangent.normalized()
		var z := x.cross(y).normalized()
		mb.box(Transform3D(Basis(x, y, z).orthonormalized(), (prev + q) * 0.5), Vector3(thick, prev.distance_to(q) + 0.04, depth),
			STONE if portal else METAL)
		prev = q
	if portal:
		# Base do portal (sapatas dos dois lados)
		for t: float in [0.0, 1.0]:
			var b := _arc(track, i, t, -depth * 0.5)
			mb.box(Transform3D(Basis(tangent, Vector3.UP, tangent.cross(Vector3.UP)), b + Vector3.UP * 0.6), Vector3(thick + 0.8, 1.2, depth + 0.8), STONE)
		return
	for t: float in [0.18, 0.82]:
		var c := _arc(track, i, t, 0.06)
		var y := (_arc(track, i, t + 0.01) - _arc(track, i, t - 0.01)).normalized()
		lamps.box(Transform3D(Basis(tangent, y, tangent.cross(y)), c), Vector3(thick * 0.6, 0.5, 0.06), LAMP)
	var a := _arc(track, i, 0.25, 0.04)
	for n in range(4, ARC - 3):
		var t1 := float(n + 1) / ARC
		var b := _arc(track, i, t1, 0.04)
		var y2 := (b - a).normalized()
		leds.box(Transform3D(Basis(tangent, y2, tangent.cross(y2)), (a + b) * 0.5), Vector3(0.08, a.distance_to(b), 0.03), LED)
		a = b
