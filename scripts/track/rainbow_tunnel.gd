class_name RainbowTunnel
extends RefCounted
## Túnel do Arco-Íris da Rainbow Raceway (layout.tunnel): abóbada elíptica sobre a pista, das
## barreiras do túnel para cima, pintada por dentro com as seis faixas do arco-íris correndo ao longo
## do túnel (dos dois lados, subindo do chão para o teto lilás-escuro), estrelas acesas no teto, anéis
## de luz a cada RIB_EVERY amostras com um pulso correndo no sentido da pista, portais de arco-íris
## sólido nas duas bocas e, por fora, a casca rosa coberta de nuvens fofas. Nada tem colisão (as
## barreiras do túnel são do TrackBarriers).

const HEIGHT := 8.6
## Folga da abóbada além da face da barreira (m).
const SIDE_GAP := 0.9
const THICK := 0.8
const SEGMENTS := 18
const RIB_EVERY := 6
const CEILING := Color(0.42, 0.3, 0.72)
const SHELL := Color(1.0, 0.7, 0.86)


static func build(track: RaceTrack, s0: float, s1: float, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "RainbowTunnel"
	parent.add_child(root)
	var p := track.path
	var inner := MeshBuilder.new()
	var outer := MeshBuilder.new()
	var glow := MeshBuilder.new()
	var stars := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1885
	var idx := track.span_indices(s0, s1)
	var puffs: Array[Transform3D] = []
	for k in idx.size() - 1:
		var i := idx[k]
		var j := idx[k + 1]
		var ring_i := _ring(track, i)
		var ring_j := _ring(track, j)
		var s_i := p.s_at(i)
		for q in SEGMENTS:
			var c := _band_color(q)
			var n_i := (ring_i[q] + ring_i[q + 1]) * 0.5 - (p.points[i] + Vector3.UP * HEIGHT * 0.35)
			inner.quad(ring_i[q], ring_i[q + 1], ring_j[q + 1], ring_j[q], c, -n_i)
			# Casca por fora
			var o0 := _outward(track, i, ring_i[q])
			var o1 := _outward(track, i, ring_i[q + 1])
			var o2 := _outward(track, j, ring_j[q + 1])
			var o3 := _outward(track, j, ring_j[q])
			outer.quad(o0, o1, o2, o3, SHELL, n_i)
		# Anel de luz (faixa fina por dentro) e estrelas no teto
		if k % RIB_EVERY == 0:
			var col: Color = CloudLook.RAINBOW[(k / RIB_EVERY) % CloudLook.RAINBOW.size()]
			var ring_a := _ring(track, i, 0.12)
			var f := p.frame_at(s_i + 0.6)
			var ring_b: Array[Vector3] = []
			for v in ring_a:
				ring_b.append(v + f.basis.z * 0.7)
			for q in SEGMENTS:
				var n := (ring_a[q] + ring_a[q + 1]) * 0.5 - (p.points[i] + Vector3.UP * HEIGHT * 0.35)
				glow.quad(ring_a[q], ring_a[q + 1], ring_b[q + 1], ring_b[q], col * 1.4, -n,
					Vector2(s_i, 0), Vector2(s_i, 0), Vector2(s_i + 0.7, 1), Vector2(s_i + 0.7, 1))
		if k % 2 == 0:
			for n_star in 4:
				var q := rng.randi_range(5, SEGMENTS - 6)
				var t := rng.randf()
				var at := ring_i[q].lerp(ring_i[q + 1], t).lerp(ring_j[q].lerp(ring_j[q + 1], t), rng.randf())
				var to_axis := (p.points[i] + Vector3.UP * HEIGHT * 0.3 - at).normalized()
				var x := to_axis.cross(p.tangents[i]).normalized()
				var basis := Basis(x, p.tangents[i], to_axis).orthonormalized()
				var size := rng.randf_range(0.25, 0.6)
				CloudLook.slab(stars, CloudLook.star(size, 0.45), Transform3D(basis, at + to_axis * 0.06), 0.04,
					CloudLook.BUTTER if rng.randf() < 0.6 else Color(1.0, 0.85, 0.95))
		# Nuvens por fora da casca: uma no alto (a base plana logo acima do topo: a casca desce dos
		# lados, então nada dela entra no túnel) e uma de cada lado, encostada por fora
		if k % 3 == 0:
			var sc := rng.randf_range(3.0, 4.2)
			var top := p.frame_at(s_i, rng.randf_range(-2.0, 2.0), HEIGHT + THICK + 0.15).origin
			puffs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc * 1.2, sc * 0.7, sc)), top))
			for side: int in [1, -1]:
				var sc2 := rng.randf_range(2.6, 3.8)
				var at := p.frame_at(s_i, side * (_half(track, i, side) + THICK + sc2 * 0.8), rng.randf_range(0.5, 3.0)).origin
				puffs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc2 * 1.1, sc2 * 0.75, sc2)), at))
	# Por dentro, as faixas acesas (o sol não entra: no toon ficariam apagadas)
	CloudLook.add_mesh(root, "Inside", inner.commit(null, CloudLook.glow(0.82, 1.0)))
	CloudLook.add_mesh(root, "Shell", outer.commit(null, TrackMaterials.candy_plastic("tunnel_shell", false, true)))
	CloudLook.add_mesh(root, "Rings", glow.commit(null, CloudLook.glow(1.1, 2.6, 0.75)))
	CloudLook.add_mesh(root, "Stars", stars.commit(null, CloudLook.glow(1.6, 3.0)))
	CloudLook.add_multimesh(root, "Clouds", CloudLook.puff_mesh(1, 7, true, 1), puffs, CloudLook.cloud_material(), 1500.0)
	# Portais: arco-íris sólido em volta das duas bocas, com nuvens nos pés
	var portal := MeshBuilder.new()
	for end: Array in [[s0, 1.0], [s1, -1.0]]:
		var s: float = end[0]
		var f := p.frame_at(s)
		var fwd := Vector3(f.basis.z.x, 0.0, f.basis.z.z).normalized()
		var i := p.index_at(s)
		var w := _half(track, i, 1) + _half(track, i, -1)
		var center := f.origin + f.basis.x * (_half(track, i, 1) - _half(track, i, -1)) * 0.5
		var r := w * 0.5 + THICK + 3.3
		CandyDecor.rainbow_arch(portal, Transform3D(Basis(f.basis.x, Vector3.UP, fwd), center + fwd * float(end[1]) * -0.6), r, 0.55, 1.6, 36,
			(HEIGHT + THICK + 3.3) / r)
		for side: float in [-1.0, 1.0]:
			for q in 3:
				var at := center + f.basis.x * side * (r - 1.6) + Vector3.UP * (q * 1.2 - 0.5) + fwd * rng.randf_range(-1.5, 1.5)
				portal.blob(at, Vector3.ONE * rng.randf_range(2.0, 2.8), Color(1.0, 0.95, 0.99), 12, 8, 0.25)
		# Estrela grande no alto do portal
		CloudLook.slab(portal, CloudLook.star(2.0, 0.48), Transform3D(Basis(f.basis.x, Vector3.UP, fwd), center + Vector3.UP * (HEIGHT + THICK + 3.6)), 0.6,
			CloudLook.BUTTER)
	CloudLook.add_mesh(root, "Portals", portal.commit(null, CandyDecor.material()))
	root.set_meta("span", Vector2(s0, s1))


## Meia-largura do túnel por dentro no índice i, de um lado: borda da pista + barreira + muro + folga.
static func _half(track: RaceTrack, i: int, side: int) -> float:
	return track.path.half_width(i, side) + track.barrier[RaceTrack._si(side)][i] + TrackBarriers.CLOUD_THICK + SIDE_GAP


## Pontos da abóbada por dentro no índice i (SEGMENTS + 1, da direita para a esquerda, passando pelo
## teto), `inset` m para dentro.
static func _ring(track: RaceTrack, i: int, inset := 0.0) -> Array[Vector3]:
	var p := track.path
	var out: Array[Vector3] = []
	var wl := _half(track, i, 1) - inset
	var wr := _half(track, i, -1) - inset
	var h := HEIGHT - inset
	for q in SEGMENTS + 1:
		var a := PI * q / SEGMENTS
		var w := wr if a < PI * 0.5 else wl
		var lat := -cos(a) * w
		out.append(p.points[i] + p.lefts[i] * lat + Vector3.UP * (sin(a) * h - 0.05))
	return out


## Ponto da casca por fora correspondente a `v` (THICK m para fora, a partir do eixo do túnel).
static func _outward(track: RaceTrack, i: int, v: Vector3) -> Vector3:
	var d := v - track.path.points[i]
	d.y = maxf(d.y, 0.0)
	return v + d.normalized() * THICK


## Cor da faixa q da abóbada: as seis do arco-íris de baixo para cima nos dois lados e o teto lilás.
static func _band_color(q: int) -> Color:
	var from_floor := mini(q, SEGMENTS - 1 - q)
	var bands: int = CloudLook.RAINBOW.size()
	if from_floor < bands:
		return CloudLook.RAINBOW[from_floor]
	return CEILING
