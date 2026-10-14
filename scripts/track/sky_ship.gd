class_name SkyShip
extends RefCounted
## O túnel da pista no céu (Sky Aerobase) é uma nave pousada sobre a pista, em placas de metal
## escuro: casco arredondado por cima, parede cheia (com janelas acesas por fora) do lado de dentro
## do circuito e o lado de fora vazado, só com pilares, para quem passa ver o céu. Espinha com friso
## de luz e duas barbatanas em cima, dois núcleos do reator, a proa afinando na saída e dois
## propulsores na entrada, com os bocais acesos virados para quem chega.
## Nada aqui tem colisão (as barreiras do túnel seguram o carro).

const HEIGHT := 7.0
## Quanto o casco sobe no meio, acima de HEIGHT, e a espessura dele.
const BULGE := 4.5
const SHELL := 1.0
const WALL := 1.0
## Beiral do casco além das paredes (m).
const EAVE := 1.6
const ARC := 10
const PILLAR_EVERY := 4
const PROW := 16.0
const LIGHT_SPACING := 24.0
## Refletores da noite no forro: intervalo (m) e força.
const NIGHT_LIGHT_SPACING := 10.0
const NIGHT_LIGHT_ENERGY := 5.0
const HULL := Color(0.4, 0.42, 0.48)
const HULL_DARK := Color(0.24, 0.25, 0.3)
const CEILING := Color(0.2, 0.21, 0.25)
const WINDOW := Color(0.55, 0.85, 1.0)


static func build(track: RaceTrack, s0: float, s1: float, parent: Node3D) -> void:
	var p := track.path
	var root := Node3D.new()
	root.name = "Tunnel"
	parent.add_child(root)
	var mb := MeshBuilder.new()
	var glow := MeshBuilder.new()
	var outer := outer_side(track, s0, s1)
	var inner := -outer
	var idxs := track.span_indices(s0, s1)
	for k in idxs.size() - 1:
		var i := idxs[k]
		var j := idxs[k + 1]
		_slice(track, mb, glow, i, j, inner, outer, k)
	_portal(track, mb, glow, s0, inner, outer, 1.0)
	_portal(track, mb, glow, s1, inner, outer, -1.0)
	_prow(track, mb, glow, s1, inner, outer)
	_thrusters(track, mb, glow, s0, inner, outer)
	var length := fposmod(s1 - s0, p.length)
	for n in 2:
		var f := p.frame_at(s0 + length * (0.35 + n * 0.3), 0.0, 0.0)
		var top := f.origin + Vector3.UP * (HEIGHT + BULGE + SHELL)
		mb.cylinder(Transform3D(Basis(), top - Vector3.UP * 0.5), 6.0, 5.4, 2.0, HULL_DARK, 20)
		glow.cylinder(Transform3D(Basis(), top + Vector3.UP * 1.5), 4.6, 3.6, 7.0, WINDOW, 20)
		mb.cylinder(Transform3D(Basis(), top + Vector3.UP * 8.5), 5.2, 1.6, 2.5, HULL, 20)
	var mi := MeshInstance3D.new()
	mi.name = "Ship"
	mi.mesh = mb.commit(null, TrackMaterials.building("ship", true, {"no_outline": true}))
	glow.commit(mi.mesh as ArrayMesh, SkyDeck.glow(0.0, 1.6, 3.6))
	root.add_child(mi)
	if RaceTrack.server_mode:
		return
	# Luz azulada lá dentro (o lado aberto deixa o dia entrar; sem penumbra forçada) e, à noite,
	# refletores brancos do forro para a pista (grupo "night_lights": o RaceTrack acende e dosa)
	var count := maxi(int(length / LIGHT_SPACING), 1)
	for n in count:
		var light := OmniLight3D.new()
		light.light_color = Color(0.62, 0.82, 1.0)
		light.light_energy = 1.2
		light.omni_range = 18.0
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		root.add_child(light)
		light.global_position = p.frame_at(s0 + (n + 0.5) * length / count, 0.0, HEIGHT - 1.0).origin
	var night := maxi(int(length / NIGHT_LIGHT_SPACING), 1)
	for n in night:
		var s := s0 + (n + 0.5) * length / night
		var spot := SpotLight3D.new()
		spot.light_color = Color(0.92, 0.96, 1.0)
		spot.light_energy = NIGHT_LIGHT_ENERGY
		spot.set_meta("base_energy", NIGHT_LIGHT_ENERGY)
		spot.spot_range = 16.0
		spot.spot_angle = 70.0
		spot.spot_attenuation = 0.6
		spot.shadow_enabled = false
		spot.visible = false
		spot.add_to_group("night_lights")
		root.add_child(spot)
		var at := p.frame_at(s, (n % 2 - 0.5) * 4.0, HEIGHT + BULGE * 0.5).origin
		spot.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, p.tangents[p.index_at(s)]), at)


## Lado de fora do circuito no meio do túnel (+1 esquerda, -1 direita): o que se afasta do centro.
static func outer_side(track: RaceTrack, s0: float, s1: float) -> int:
	var p := track.path
	var b := p.bounds()
	var center := Vector3(b.get_center().x, 0.0, b.get_center().y)
	var mid := p.index_at(s0 + fposmod(s1 - s0, p.length) * 0.5)
	var away := p.points[mid] - center
	away.y = 0.0
	return 1 if p.lefts[mid].dot(away) > 0.0 else -1


## Lateral (com sinal) da face de dentro da parede/pilares de um lado.
static func _inner_face(track: RaceTrack, i: int, side: int) -> float:
	return side * (track.path.half_width(i, side) + track.barrier[RaceTrack._si(side)][i] + 0.6)


## Ponto do arco do casco no índice i: t = 0 no beiral de dentro, 1 no de fora; lift = espessura.
static func _arc(track: RaceTrack, i: int, inner: int, outer: int, t: float, lift := 0.0) -> Vector3:
	var p := track.path
	var a := _inner_face(track, i, inner) + inner * (WALL + EAVE)
	var b := _inner_face(track, i, outer) + outer * (WALL + EAVE)
	var lat := lerpf(a, b, t)
	var y := HEIGHT - 0.6 + (BULGE + 0.6) * pow(sin(PI * t), 0.6) + lift
	return p.points[i] + p.lefts[i] * lat + Vector3.UP * y


static func _slice(track: RaceTrack, mb: MeshBuilder, glow: MeshBuilder, i: int, j: int, inner: int, outer: int, k: int) -> void:
	var p := track.path
	var to_in := -p.lefts[i] * inner
	# Parede de dentro: face interna, face de fora (janelas acesas) e topo
	var w_i := _inner_face(track, i, inner)
	var w_j := _inner_face(track, j, inner)
	var at := func(idx: int, lat: float, y: float) -> Vector3:
		return p.points[idx] + p.lefts[idx] * lat + Vector3.UP * y
	mb.quad(at.call(i, w_i, 0.0), at.call(j, w_j, 0.0), at.call(j, w_j, HEIGHT), at.call(i, w_i, HEIGHT), HULL, to_in)
	var o_i := w_i + inner * WALL
	var o_j := w_j + inner * WALL
	mb.quad(at.call(i, o_i, -0.5), at.call(j, o_j, -0.5), at.call(j, o_j, HEIGHT), at.call(i, o_i, HEIGHT), HULL_DARK * 1.3, -to_in)
	if k % 3 != 2:
		glow.quad(at.call(i, o_i + inner * 0.03, 4.0), at.call(j, o_j + inner * 0.03, 4.0),
			at.call(j, o_j + inner * 0.03, 5.0), at.call(i, o_i + inner * 0.03, 5.0), WINDOW, -to_in)
	# Casco: forro (embaixo), casco (em cima) e as faces dos beirais
	for n in ARC:
		var t0 := float(n) / ARC
		var t1 := float(n + 1) / ARC
		var a0 := _arc(track, i, inner, outer, t0)
		var a1 := _arc(track, i, inner, outer, t1)
		var b0 := _arc(track, j, inner, outer, t0)
		var b1 := _arc(track, j, inner, outer, t1)
		mb.quad(a0, b0, b1, a1, CEILING, Vector3.DOWN)
		var c0 := _arc(track, i, inner, outer, t0, SHELL)
		var c1 := _arc(track, i, inner, outer, t1, SHELL)
		var d0 := _arc(track, j, inner, outer, t0, SHELL)
		var d1 := _arc(track, j, inner, outer, t1, SHELL)
		var up := (c1 - c0).cross(p.tangents[i]).normalized()
		if up.y < 0.0:
			up = -up
		mb.quad(c0, d0, d1, c1, HULL, up)
	# Luminárias: duas fileiras no forro
	if k % 2 == 0:
		for t: float in [0.32, 0.68]:
			var c := (_arc(track, i, inner, outer, t) + _arc(track, j, inner, outer, t)) * 0.5 + Vector3.DOWN * 0.1
			glow.box(Transform3D(Basis(p.lefts[i], Vector3.UP, p.lefts[i].cross(Vector3.UP)).orthonormalized(), c), Vector3(0.6, 0.12, 1.8), WINDOW)
	for t: float in [0.0, 1.0]:
		var side := inner if t == 0.0 else outer
		mb.quad(_arc(track, i, inner, outer, t), _arc(track, j, inner, outer, t), _arc(track, j, inner, outer, t, SHELL),
			_arc(track, i, inner, outer, t, SHELL), HULL_DARK * 1.4, p.lefts[i] * side)
	# Espinha com friso de luz
	var top_i := _arc(track, i, inner, outer, 0.5, SHELL)
	var top_j := _arc(track, j, inner, outer, 0.5, SHELL)
	var spine := Transform3D(Basis(p.lefts[i], Vector3.UP, p.lefts[i].cross(Vector3.UP)).orthonormalized(), (top_i + top_j) * 0.5 + Vector3.UP * 0.4)
	mb.box(spine, Vector3(1.6, 0.8, top_i.distance_to(top_j) + 0.05), HULL_DARK * 1.5)
	glow.box(spine.translated_local(Vector3(0, 0.42, 0)), Vector3(0.5, 0.06, top_i.distance_to(top_j) + 0.05), WINDOW)
	# Lado de fora: pilares (o resto é vão aberto)
	if k % PILLAR_EVERY == 0:
		var face := _inner_face(track, i, outer)
		var lat := face + outer * WALL * 0.5
		var base := p.points[i] + p.lefts[i] * lat
		var t_pillar := 1.0 - (WALL * 0.5 + EAVE) / maxf(_span(track, i, inner, outer), 1.0)
		var top_y := _arc(track, i, inner, outer, t_pillar).y
		var hgt := top_y - p.points[i].y
		var xf := Transform3D(Basis(p.lefts[i], Vector3.UP, p.lefts[i].cross(Vector3.UP)).orthonormalized(), base + Vector3.UP * hgt * 0.5)
		mb.box(xf, Vector3(WALL, hgt, 1.3), HULL_DARK * 1.5)
		glow.box(xf.translated_local(Vector3(-outer * (WALL * 0.5 + 0.02), 0, 0)), Vector3(0.04, hgt * 0.8, 0.2), WINDOW)


## Largura do arco do casco (de beiral a beiral) no índice i.
static func _span(track: RaceTrack, i: int, inner: int, outer: int) -> float:
	return absf(_inner_face(track, i, outer) + outer * (WALL + EAVE) - (_inner_face(track, i, inner) + inner * (WALL + EAVE)))


## Moldura grossa na boca (dir = +1 na entrada, -1 na saída), acompanhando paredes e casco, com um
## anel de luz por dentro.
static func _portal(track: RaceTrack, mb: MeshBuilder, glow: MeshBuilder, s: float, inner: int, outer: int, dir: float) -> void:
	var p := track.path
	var i := p.index_at(s)
	var back := p.tangents[i] * dir
	var pts: Array[Vector3] = []
	pts.append(p.points[i] + p.lefts[i] * (_inner_face(track, i, inner) + inner * WALL))
	for n in ARC + 1:
		pts.append(_arc(track, i, inner, outer, float(n) / ARC, SHELL * 0.5))
	pts.append(p.points[i] + p.lefts[i] * (_inner_face(track, i, outer) + outer * WALL))
	for n in pts.size() - 1:
		var a := pts[n]
		var b := pts[n + 1]
		var mid := (a + b) * 0.5
		var along := (b - a).normalized()
		var out := along.cross(back).normalized()
		var xf := Transform3D(Basis(along, out, along.cross(out)).orthonormalized(), mid + back * 1.0)
		mb.box(xf, Vector3(a.distance_to(b) + 0.4, SHELL + 1.4, 2.4), HULL_DARK * 1.5)
		glow.box(xf.translated_local(Vector3(0, -(SHELL + 1.4) * 0.5 - 0.02, 0)), Vector3(a.distance_to(b) + 0.4, 0.06, 0.5), WINDOW)


## Proa na saída: o casco continua além da boca afinando e descendo até uma ponta.
static func _prow(track: RaceTrack, mb: MeshBuilder, glow: MeshBuilder, s: float, inner: int, outer: int) -> void:
	var p := track.path
	var i := p.index_at(s)
	var fwd := p.tangents[i]
	var steps := 6
	for n in steps:
		var f0 := float(n) / steps
		var f1 := float(n + 1) / steps
		for m in ARC:
			var t0 := float(m) / ARC
			var t1 := float(m + 1) / ARC
			var a0 := _prow_point(track, i, inner, outer, t0, f0, fwd)
			var a1 := _prow_point(track, i, inner, outer, t1, f0, fwd)
			var b0 := _prow_point(track, i, inner, outer, t0, f1, fwd)
			var b1 := _prow_point(track, i, inner, outer, t1, f1, fwd)
			mb.quad(a0, b0, b1, a1, HULL, Vector3.UP + fwd * 0.5)
			mb.quad(a0 + Vector3.DOWN * 0.6, b0 + Vector3.DOWN * 0.6, b1 + Vector3.DOWN * 0.6, a1 + Vector3.DOWN * 0.6, CEILING, Vector3.DOWN)
	var tip := _prow_point(track, i, inner, outer, 0.5, 1.0, fwd)
	glow.blob(tip, Vector3.ONE * 0.6, Color(1.0, 0.3, 0.25), 8, 5)


## Ponto da proa: f = 0 na boca, 1 na ponta (estreita para o meio, desce e avança PROW m).
static func _prow_point(track: RaceTrack, i: int, inner: int, outer: int, t: float, f: float, fwd: Vector3) -> Vector3:
	var base := _arc(track, i, inner, outer, t, SHELL)
	var mid := _arc(track, i, inner, outer, 0.5, SHELL)
	var q := base.lerp(mid, pow(f, 0.8))
	return q + fwd * (PROW * f) + Vector3.DOWN * (BULGE * 0.6 * f * f)


## Dois propulsores horizontais sobre a entrada, com o bocal aceso virado para quem chega.
static func _thrusters(track: RaceTrack, mb: MeshBuilder, glow: MeshBuilder, s: float, inner: int, outer: int) -> void:
	var p := track.path
	var i := p.index_at(s)
	var back := -p.tangents[i]
	# Cilindro com o eixo Y local apontando para trás (para quem chega)
	var axis := Basis(p.lefts[i], back, p.lefts[i].cross(back)).orthonormalized()
	for t: float in [0.3, 0.7]:
		var c := _arc(track, i, inner, outer, t, SHELL + 2.6) + p.tangents[i] * 4.0
		mb.cylinder(Transform3D(axis, c), 2.8, 2.6, 9.0, HULL, 18)
		mb.cylinder(Transform3D(axis, c + back * 9.0), 2.6, 2.1, 1.6, HULL_DARK * 1.4, 18, false)
		glow.cylinder(Transform3D(axis, c + back * 10.55), 2.0, 0.0, 0.05, Color(0.6, 0.88, 1.0), 18)
		mb.box(Transform3D(Basis(p.lefts[i], Vector3.UP, p.lefts[i].cross(Vector3.UP)).orthonormalized(), c + back * 3.0 + Vector3.DOWN * 2.4),
			Vector3(1.2, 2.4, 5.0), HULL_DARK * 1.4)
