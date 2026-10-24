class_name HeartArches
extends RefCounted
## Arcos sobre a pista fofa nas nuvens (Rainbow Raceway):
##   * o Arco do Coração na largada (TrackFeature START_GANTRY): arco fofo cor-de-rosa sobre a pista e
##     a pista dos boxes, com as faixas do arco-íris por dentro, o coração (moldura branca, miolo rosa
##     aceso) no topo, estrelas amarelas, colunas de nuvem nos pés e a faixa xadrez que segura as luzes
##     de largada (TrackProps só põe as luzes, na altura START_BEAM);
##   * arcos de arco-íris sólidos atravessando a pista (RAINBOWS), com os pés em nuvens fofas atrás
##     das barreiras;
##   * portais de pirulitos gigantes com bandeirolas pastel cruzando por cima da pista (GARLANDS).
## Nada tem colisão (o carro passa por baixo de tudo).

## s (m) dos arcos de arco-íris e dos portais de pirulito.
const RAINBOWS := [235.0, 650.0, 1080.0, 2010.0, 3450.0, 3585.0]
const GARLANDS := [150.0, 470.0, 880.0, 1460.0, 2235.0, 2885.0, 3215.0, 3940.0, 4090.0]
## Altura mínima (m) de qualquer parte de um arco sobre a pista (os carros passam bem por baixo).
const CLEARANCE := 6.0


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "HeartArches"
	parent.add_child(root)
	var mb := MeshBuilder.new()
	var glow := MeshBuilder.new()
	var cloth := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6060
	var count := 0
	for f in track.layout.features:
		if f and f.kind == TrackFeature.Kind.START_GANTRY:
			_start_arch(track, mb, glow, f.s_start, rng)
			count += 1
	var rainbows := 0
	for s: float in RAINBOWS:
		if _blocked(track, s):
			continue
		_rainbow(track, mb, s, rng)
		rainbows += 1
	var garlands := 0
	for s: float in GARLANDS:
		if _blocked(track, s):
			continue
		_garland(track, mb, cloth, s, rng)
		garlands += 1
	# Ponte do Arco-Íris: um arco-íris sobre a pista de baixo, logo debaixo da de cima
	var bridges := 0
	for c in track.path.crossings:
		_bridge_rainbow(track, mb, c, rng)
		bridges += 1
	var mesh := mb.commit(null, CandyDecor.material())
	TrackFlags.commit_to(cloth, mesh)
	CloudLook.add_mesh(root, "Arches", mesh)
	if not glow.is_empty():
		CloudLook.add_mesh(root, "ArchLights", glow.commit(null, CloudLook.glow(1.4, 3.0)))
	root.set_meta("start", count)
	root.set_meta("rainbows", rainbows)
	root.set_meta("garlands", garlands)
	root.set_meta("bridges", bridges)


## Trecho onde não cabe arco: túnel, perto de um cruzamento (a pista de cima passa ali) ou dos boxes.
static func _blocked(track: RaceTrack, s: float) -> bool:
	var p := track.path
	if track.in_tunnel(p.index_at(s)):
		return true
	for c in p.crossings:
		if track.in_span(s, c.x - 60.0, c.x + 60.0) or track.in_span(s, c.y - 60.0, c.y + 60.0):
			return true
	return false


## Pés de um arco em s: distância lateral (com sinal) até onde dá para apoiar, dos dois lados
## (atrás das barreiras, da pista dos boxes e das arquibancadas; no máximo a borda da plataforma).
static func _feet(track: RaceTrack, s: float) -> Vector2:
	var p := track.path
	var i := p.index_at(s)
	var out := Vector2.ZERO
	for side: int in [1, -1]:
		var k := RaceTrack._si(side)
		var d := p.half_width(i, side) + track.barrier[k][i] + TrackBarriers.CLOUD_THICK + 1.8
		d = minf(maxf(d, p.half_width(i, side) + 4.0), track.deck_edge(i, side) + 1.5)
		if side > 0:
			out.x = d
		else:
			out.y = -d
	return out


# ---------------------------------------------------------------------------
# Arco do Coração (largada)
# ---------------------------------------------------------------------------
static func _start_arch(track: RaceTrack, mb: MeshBuilder, glow: MeshBuilder, s: float, rng: RandomNumberGenerator) -> void:
	var p := track.path
	var feet := _feet(track, s)
	var f := p.frame_at(s)
	var left := f.basis.x
	var center := f.origin + left * (feet.x + feet.y) * 0.5
	var a := (feet.x - feet.y) * 0.5 + 1.5
	var height := 19.0
	# Plano do arco: X = esquerda da pista, Y = cima, Z = sentido da pista (horizontal)
	var fwd := Vector3(f.basis.z.x, 0.0, f.basis.z.z).normalized()
	var xf := Transform3D(Basis(left, Vector3.UP, fwd), center)
	# Arco fofo: bolinhas cor-de-rosa grandes ao longo da meia-elipse (algumas mais claras)
	var n := 46
	for k in n + 1:
		var t := PI * k / n
		var pos := Vector3(cos(t) * a, sin(t) * height, 0.0)
		var rr := rng.randf_range(2.0, 2.6)
		var col := CloudLook.PINK if k % 3 != 0 else Color(1.0, 0.78, 0.9)
		mb.blob(xf * pos, Vector3(rr, rr * 0.92, rr * 1.15), col, 12, 8, 0.2)
		if k % 2 == 0:
			var off := Vector3(cos(t), sin(t), 0.0) * rng.randf_range(0.8, 1.6) + Vector3(0, 0, rng.randf_range(-1.0, 1.0))
			mb.blob(xf * (pos + off), Vector3.ONE * rr * 0.65, Color(1.0, 0.86, 0.94), 10, 6, 0.2)
	# Arco-íris por dentro (as faixas na face de baixo do arco), esticado na mesma elipse
	CandyDecor.rainbow_arch(mb, xf * Transform3D(Basis(), Vector3(0, 0, 0)), a - 1.6, 0.42, 3.4, 40, height / a)
	# Colunas de nuvem nos pés
	for side: float in [-1.0, 1.0]:
		for q in 4:
			var pos := Vector3(side * a, -1.0 + q * 1.4, 0.0) + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
			mb.blob(xf * pos, Vector3.ONE * (3.2 - q * 0.35), Color(1.0, 0.92, 0.97), 12, 8, 0.25)
	# Coração no topo: moldura branca, miolo rosa e o brilho dentro
	var heart_xf := xf * Transform3D(Basis(), Vector3(0, height + 1.4, 0))
	CloudIslands.heart_frame(mb, heart_xf, 9.0, 1.4, 3.0, Color.WHITE, Color(1.0, 0.9, 0.96))
	CloudLook.slab(mb, CloudLook.heart(6.4), heart_xf, 2.4, CloudLook.HOT_PINK)
	for face: float in [1.0, -1.0]:
		CloudLook.slab(glow, CloudLook.heart(3.6), heart_xf * Transform3D(Basis(Vector3.UP, 0.0 if face > 0 else PI), Vector3(0, 0, face * 1.25)), 0.1,
			Color(1.0, 0.72, 0.88))
	# Estrelas amarelas nos dois lados do arco
	for side: float in [-1.0, 1.0]:
		var t := PI * (0.5 - side * 0.27)
		var at := Vector3(cos(t) * a * 0.98, sin(t) * height * 0.98, 0.0)
		for face: float in [1.0, -1.0]:
			CloudLook.slab(mb, CloudLook.star(2.2, 0.48), xf * Transform3D(Basis(Vector3.FORWARD, side * 0.2), at + Vector3(0, 0, face * 2.0)), 0.7,
				CloudLook.BUTTER)
	# Faixa xadrez (lilás e branca) na altura das luzes, de uma perna à outra
	var beam_y := TrackProps.START_BEAM
	var half := a * sqrt(maxf(1.0 - pow((beam_y + 0.9) / height, 2.0), 0.0))
	var cells := 22
	var cell := half * 2.0 / cells
	for c in cells:
		for row in 2:
			var col := Color.WHITE if (c + row) % 2 == 0 else CloudLook.LILAC
			var cx := -half + (c + 0.5) * cell
			mb.box(xf * Transform3D(Basis(), Vector3(cx, beam_y + 0.45 + row * 0.9, 0.0)), Vector3(cell, 0.9, 0.5), col)
	mb.box(xf * Transform3D(Basis(), Vector3(0, beam_y + 0.05, 0)), Vector3(half * 2.0, 0.2, 0.7), CloudLook.CREAM)
	mb.box(xf * Transform3D(Basis(), Vector3(0, beam_y + 1.9, 0)), Vector3(half * 2.0, 0.2, 0.7), CloudLook.CREAM)


# ---------------------------------------------------------------------------
# Arcos de arco-íris e portais de pirulito
# ---------------------------------------------------------------------------
static func _rainbow(track: RaceTrack, mb: MeshBuilder, s: float, rng: RandomNumberGenerator) -> void:
	var p := track.path
	var feet := _feet(track, s)
	var f := p.frame_at(s)
	var fwd := Vector3(f.basis.z.x, 0.0, f.basis.z.z).normalized()
	var center := f.origin + f.basis.x * (feet.x + feet.y) * 0.5
	var band := 0.95
	# (as seis faixas apoiam do pé para fora: a de dentro fica atrás da barreira)
	var r := (feet.x - feet.y) * 0.5 + band * 6.0
	# Esticado para passar alto sobre a pista
	var stretch := 1.25
	var xf := Transform3D(Basis(f.basis.x, Vector3.UP, fwd), center + Vector3.DOWN * 1.0)
	CandyDecor.rainbow_arch(mb, xf, r, band, 1.4, 36, stretch)
	for side: float in [-1.0, 1.0]:
		for q in 3:
			var pos := Vector3(side * (r - band * 3.0) + rng.randf_range(-1.5, 1.5), -0.5 + q * 0.9, rng.randf_range(-1.2, 1.2))
			mb.blob(xf * pos, Vector3.ONE * rng.randf_range(2.2, 3.2), Color(1.0, 0.95, 0.99), 12, 8, 0.25)


## Arco-íris sobre a pista de baixo de um cruzamento (c = s de baixo, s de cima), com o topo 3 m abaixo
## da pista de cima (a laje e as nuvens dela ficam por cima).
static func _bridge_rainbow(track: RaceTrack, mb: MeshBuilder, c: Vector3, rng: RandomNumberGenerator) -> void:
	var p := track.path
	var gap := p.height_at(c.y) - p.height_at(c.x)
	var feet := _feet(track, c.x)
	var f := p.frame_at(c.x)
	var fwd := Vector3(f.basis.z.x, 0.0, f.basis.z.z).normalized()
	var band := 0.95
	var r := (feet.x - feet.y) * 0.5 + band * 6.0
	var top := maxf(gap - CloudDeck.DEPTH - 3.0, CLEARANCE + band * 6.0)
	var xf := Transform3D(Basis(f.basis.x, Vector3.UP, fwd), f.origin + f.basis.x * (feet.x + feet.y) * 0.5 + Vector3.DOWN * 1.0)
	CandyDecor.rainbow_arch(mb, xf, r, band, 1.6, 40, (top + 1.0) / r)
	for side: float in [-1.0, 1.0]:
		for q in 3:
			var pos := Vector3(side * (r - band * 3.0) + rng.randf_range(-1.5, 1.5), -0.5 + q * 0.9, rng.randf_range(-1.2, 1.2))
			mb.blob(xf * pos, Vector3.ONE * rng.randf_range(2.2, 3.2), Color(1.0, 0.95, 0.99), 12, 8, 0.25)


static func _garland(track: RaceTrack, mb: MeshBuilder, cloth: MeshBuilder, s: float, rng: RandomNumberGenerator) -> void:
	var p := track.path
	var feet := _feet(track, s)
	var f := p.frame_at(s)
	var fwd := Vector3(f.basis.z.x, 0.0, f.basis.z.z).normalized()
	var tops: Array[Vector3] = []
	for d: float in [feet.x, feet.y]:
		var base := f.origin + f.basis.x * d
		var height := 9.5
		mb.posts().cylinder(Transform3D(Basis(), base), 0.22, 0.18, height, CloudLook.CREAM, 10)
		var col := CloudLook.pick(rng, CloudLook.RAINBOW)
		var face := Basis(f.basis.x, Vector3.UP, fwd)
		CandyDecor.lollipop_swirl(mb, Transform3D(face, base + Vector3.UP * (height + 2.2)), 2.4, 0.5, col, Color.WHITE)
		mb.blob(base + Vector3.UP * 0.2, Vector3(1.6, 0.9, 1.6), Color(1.0, 0.95, 0.99), 10, 6, 0.25)
		tops.append(base + Vector3.UP * (height - 0.3))
	pennants(cloth, tops[0], tops[1], 1.4, 0.9, int(s))
	pennants(cloth, tops[0] + Vector3.DOWN * 1.1, tops[1] + Vector3.DOWN * 1.1, 1.1, 0.9, int(s) + 3)


## Cordão de bandeirinhas em tons pastel do arco-íris (igual ao TrackFlags.bunting, outras cores).
static func pennants(cloth: MeshBuilder, a: Vector3, b: Vector3, sag := 0.6, spacing := 0.8, offset := 0) -> void:
	var length := a.distance_to(b)
	if length < 1.0:
		return
	var dir := (b - a) / length
	var side := dir.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.5:
		side = Vector3.RIGHT
	var point := func(t: float) -> Vector3:
		return a.lerp(b, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)
	var segs := maxi(int(length / 2.0), 2)
	for k in segs:
		var p0: Vector3 = point.call(float(k) / segs)
		var p1: Vector3 = point.call(float(k + 1) / segs)
		cloth.quad(p0, p1, p1 - Vector3.UP * 0.04, p0 - Vector3.UP * 0.04, Color(1.0, 0.95, 0.98), side,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	var n := int(length / spacing)
	var size := minf(spacing * 0.75, 0.6)
	var colors: Array = CloudLook.RAINBOW + [Color.WHITE, CloudLook.PINK]
	for k in n:
		var top0: Vector3 = point.call((k + 0.12) / n)
		var top1: Vector3 = point.call((k + 0.88) / n)
		var tip := (top0 + top1) * 0.5 - Vector3.UP * size * 1.2
		var color: Color = colors[(k + offset) % colors.size()]
		cloth.tri(top0, top1, tip, color, side, Vector2(0, 0), Vector2(0, 0), Vector2(1, 0))
