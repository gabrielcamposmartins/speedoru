class_name SkyBase
extends RefCounted
## A base aérea em volta da Sky Aerobase: torres de controle em plataformas flutuantes (com motores
## a jato por baixo), um porta-aviões voador com caças estacionados, anéis metálicos gigantes sobre
## a pista (girando), letreiros ("SKY AEROBASE"), caças passando em formação, dirigíveis-nave
## dando voltas e holofotes riscando o céu (SkyBeams). Tudo é visual (sem colisão) e fica longe do traçado, exceto os anéis, que passam por
## cima e por baixo da plataforma sem tocar a pista.

const HULL := Color(0.7, 0.73, 0.8)
const HULL_DARK := Color(0.3, 0.32, 0.38)
const DECK := Color(0.2, 0.21, 0.25)
const GLASS := Color(0.45, 0.8, 1.0)
const LINE := Color(0.95, 0.85, 0.3)
const BEACON := Color(1.0, 0.25, 0.2)
const JET_GREY := Color(0.56, 0.6, 0.66)
const SIGN_BLUE := Color(0.55, 0.85, 1.0)
## Raio dos aros sobre a pista (em meias-larguras da plataforma no ponto).
const RING_SCALE := 1.7
## Folga mínima entre a borda da pista (meia-largura + barreira + plataforma) e as estruturas (m).
const CLEARANCE := 70.0


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "SkyBase"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var mb := MeshBuilder.new()
	var glow := MeshBuilder.new()
	var big_engines: Array[Transform3D] = []
	var spots := _spots(track, rng)
	var mean_y := 0.0
	for pt in track.path.points:
		mean_y += pt.y
	mean_y /= track.path.size()
	# O maior espaço livre leva o porta-aviões; os outros, as torres
	var used := 0
	if spots.size() > 0:
		_carrier(track, root, mb, glow, big_engines, spots[0], mean_y - 22.0, rng)
		used = 1
	for k in range(used, mini(spots.size(), used + 5)):
		var y := mean_y + rng.randf_range(-25.0, 15.0)
		_tower(mb, glow, big_engines, spots[k], y, k, rng)
	_rings(track, root)
	var mi := MeshInstance3D.new()
	mi.name = "Structures"
	mi.mesh = mb.commit(null, SkyDeck.hull())
	glow.commit(mi.mesh as ArrayMesh, SkyDeck.glow(0.0, 1.8, 4.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	SkyDeck.add_engines(root, big_engines, "BaseEngines", 2.4)
	_signs(track, root)
	if not RaceTrack.server_mode:
		_fighters(track, root, rng, mean_y)
		_airships(track, root, rng, mean_y, spots)
		SkyBeams.build(track, root)


## Lugares livres para as estruturas: [centro (x, z), raio livre], do maior para o menor, a pelo
## menos CLEARANCE da plataforma e a no máximo ~450 m dela (ficam no quadro de quem pilota).
static func _spots(track: RaceTrack, rng: RandomNumberGenerator) -> Array:
	var p := track.path
	var bounds := p.bounds().grow(450.0)
	var step := 40.0
	var cands := []
	var x := bounds.position.x
	while x < bounds.end.x:
		var z := bounds.position.y
		while z < bounds.end.y:
			var pr := p.project(Vector3(x, 0, z))
			var i := p.index_at(pr.x)
			var side := 1 if pr.y > 0.0 else -1
			var free := absf(pr.y) - track.deck_edge(i, side) - CLEARANCE
			if free > 30.0 and free < 420.0:
				cands.append([Vector2(x, z), minf(free, 160.0), free])
			z += step
		x += step
	# Gulosa: o maior raio livre primeiro, sem sobrepor os já escolhidos
	cands.shuffle()
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var out := []
	for c in cands:
		var ok := true
		for o in out:
			if (c[0] as Vector2).distance_to(o[0]) < float(c[1]) + float(o[1]) + 120.0:
				ok = false
				break
		if ok:
			out.append(c)
		if out.size() >= 7:
			break
	return out


# ---------------------------------------------------------------------------
# Torre de controle numa plataforma flutuante
# ---------------------------------------------------------------------------
static func _tower(mb: MeshBuilder, glow: MeshBuilder, engines: Array[Transform3D], spot: Array, y: float, k: int,
		rng: RandomNumberGenerator) -> void:
	var c := Vector3(spot[0].x, y, spot[0].y)
	var r := clampf(float(spot[1]) * 0.5, 26.0, 42.0)
	var base := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), c)
	# Plataforma: disco grosso com friso de luz e motores por baixo
	mb.cylinder(base.translated_local(Vector3(0, -6.0, 0)), r * 0.82, r, 6.0, HULL, 28)
	glow.cylinder(base.translated_local(Vector3(0, -1.2, 0)), r + 0.05, r + 0.05, 0.5, GLASS, 28, false)
	for e in 6:
		var a := TAU * e / 6.0
		engines.append(Transform3D(Basis(), base * Vector3(cos(a) * r * 0.55, -6.0, sin(a) * r * 0.55)))
	# Fuste com casulos laterais
	var height := rng.randf_range(80.0, 125.0)
	mb.cylinder(base, 7.5, 5.0, height, HULL, 16)
	for side: float in [-1.0, 1.0]:
		var pod := base.translated_local(Vector3(side * 10.0, 0, 0))
		mb.cylinder(pod, 3.6, 2.6, height * 0.45, HULL_DARK * 1.6, 12)
		glow.cylinder(pod.translated_local(Vector3(0, height * 0.45 - 2.0, 0)), 2.7, 2.7, 1.0, GLASS, 12, false)
	# Anéis no meio e o "disco" no alto (janelas acesas em volta)
	mb.cylinder(base.translated_local(Vector3(0, height * 0.42, 0)), 15.0, 15.0, 2.0, HULL_DARK * 1.4, 24)
	glow.cylinder(base.translated_local(Vector3(0, height * 0.42 + 0.6, 0)), 15.06, 15.06, 0.6, GLASS, 24, false)
	var top := height * 0.8
	mb.cylinder(base.translated_local(Vector3(0, top, 0)), 7.0, 24.0, 5.0, HULL, 28)
	glow.cylinder(base.translated_local(Vector3(0, top + 5.0, 0)), 24.0, 20.0, 5.0, GLASS * 0.9, 28, false)
	mb.cylinder(base.translated_local(Vector3(0, top + 10.0, 0)), 20.0, 8.0, 5.0, HULL, 28)
	# Antena com farol vermelho
	var spire := base.translated_local(Vector3(0, top + 15.0, 0))
	mb.cylinder(spire, 1.3, 0.25, height * 0.35, HULL_DARK, 8)
	glow.blob(spire * Vector3(0, height * 0.35 + 0.6, 0), Vector3.ONE * 1.1, BEACON, 8, 5)
	if k % 2 == 0:
		# Plataforma de pouso em balanço com um caça
		var pad := base.translated_local(Vector3(0, height * 0.42 + 2.0, -26.0))
		mb.box(pad.translated_local(Vector3(0, -0.6, 0)), Vector3(22.0, 1.2, 22.0), DECK)
		mb.box(base.translated_local(Vector3(0, height * 0.42 + 1.4, -13.0)), Vector3(3.0, 1.0, 12.0), HULL_DARK)
		glow.box(pad.translated_local(Vector3(0, 0.02, 0)), Vector3(22.2, 0.06, 0.4), LINE)
		_fighter(mb, glow, pad.translated_local(Vector3(0, 1.3, 0)) * Transform3D(Basis(Vector3.UP, 0.6), Vector3.ZERO))


# ---------------------------------------------------------------------------
# Porta-aviões voador
# ---------------------------------------------------------------------------
static func _carrier(track: RaceTrack, root: Node3D, mb: MeshBuilder, glow: MeshBuilder, engines: Array[Transform3D],
		spot: Array, y: float, rng: RandomNumberGenerator) -> void:
	var c := Vector3(spot[0].x, y, spot[0].y)
	# Comprido paralelo ao trecho de pista mais próximo (fica de lado para quem passa)
	var s := track.path.project(c).x
	var t := track.path.tangent_at(s)
	var yaw := atan2(t.x, t.z)
	var free: float = spot[1]
	var length := clampf(free * 1.5, 140.0, 230.0)
	var width := length * 0.34
	var xf := Transform3D(Basis(Vector3.UP, yaw), c)
	# Casco: deque reto em cima, quilha afinando embaixo
	mb.box(xf.translated_local(Vector3(0, -3.0, 0)), Vector3(width, 6.0, length), HULL, DECK)
	mb.box(xf.translated_local(Vector3(0, -9.0, 0)), Vector3(width * 0.7, 6.0, length * 0.85), HULL_DARK * 1.5)
	# Pista de pouso: faixa central tracejada, bordas amarelas e luzes nas bordas
	for k in int(length / 14.0):
		var z := -length * 0.5 + 7.0 + k * 14.0
		mb.box(xf.translated_local(Vector3(0, 0.03, z)), Vector3(0.8, 0.06, 7.0), Color(0.92, 0.93, 0.95))
		for side: float in [-1.0, 1.0]:
			glow.box(xf.translated_local(Vector3(side * (width * 0.5 - 0.6), 0.15, z)), Vector3(0.5, 0.3, 0.5), GLASS)
	for side: float in [-1.0, 1.0]:
		mb.box(xf.translated_local(Vector3(side * (width * 0.5 - 3.0), 0.03, 0)), Vector3(0.4, 0.06, length - 8.0), LINE)
		glow.box(xf.translated_local(Vector3(side * (width * 0.5 + 0.02), -1.6, 0)), Vector3(0.1, 0.5, length), GLASS)
	# Ilha (torre de comando) num dos lados
	var island := xf.translated_local(Vector3(width * 0.36, 0, length * 0.12))
	mb.box(island.translated_local(Vector3(0, 9.0, 0)), Vector3(8.0, 18.0, 26.0), HULL)
	glow.box(island.translated_local(Vector3(0, 14.0, 0)), Vector3(8.1, 2.2, 26.1), GLASS)
	mb.cylinder(island.translated_local(Vector3(0, 18.0, 0)), 1.0, 0.3, 14.0, HULL_DARK, 8)
	glow.blob(island * Vector3(0, 32.6, 0), Vector3.ONE * 0.9, BEACON, 8, 5)
	# Caças estacionados em diagonal
	var jets := int(length / 40.0)
	for k in jets:
		var z := -length * 0.38 + k * (length * 0.62 / maxf(jets - 1, 1))
		var jet := xf.translated_local(Vector3(-width * 0.2, 1.3, z)) * Transform3D(Basis(Vector3.UP, 0.7), Vector3.ZERO)
		_fighter(mb, glow, jet)
	# Motores: duas fileiras por baixo
	for k in 4:
		for side: float in [-1.0, 1.0]:
			engines.append(Transform3D(Basis(), xf * Vector3(side * width * 0.25, -12.0, -length * 0.36 + k * length * 0.24)))
	# Nome na lateral virada para a pista
	var to_track := (track.path.position_at(s) - c)
	to_track.y = 0.0
	var side_sign := signf(xf.basis.x.dot(to_track))
	var label := _label("SKY AEROBASE", 1600, 0.014)
	root.add_child(label)
	label.global_transform = Transform3D(Basis(Vector3.UP, yaw + (PI * 0.5 if side_sign > 0 else -PI * 0.5)),
		xf * Vector3(side_sign * (width * 0.5 + 0.3), -4.5, 0))


# ---------------------------------------------------------------------------
# Caça (malha procedural low-poly, nariz para +Z, ~15 m)
# ---------------------------------------------------------------------------
static func _fighter(mb: MeshBuilder, glow: MeshBuilder, xf: Transform3D, color := JET_GREY) -> void:
	var dark := color * 0.55
	var along := Basis(Vector3.RIGHT, PI * 0.5)  # eixo Y do cilindro vira +Z
	# Fuselagem, nariz e bocais
	mb.cylinder(xf * Transform3D(along, Vector3(0, 0, -6.5)), 1.05, 0.95, 10.5, color, 10)
	mb.cylinder(xf * Transform3D(along, Vector3(0, 0, 4.0)), 0.95, 0.0, 4.0, color, 10)
	for side: float in [-0.55, 0.55]:
		mb.cylinder(xf * Transform3D(along, Vector3(side, -0.1, -7.6)), 0.55, 0.6, 1.4, dark, 8, false)
		glow.cylinder(xf * Transform3D(along, Vector3(side, -0.1, -7.65)), 0.45, 0.45, 0.06, Color(1.0, 0.55, 0.25), 8)
	# Cabine
	mb.blob(xf * Vector3(0, 0.75, 2.4), Vector3(0.55, 0.45, 1.6), Color(0.12, 0.16, 0.24), 8, 5)
	# Asas em delta e estabilizadores (dos dois lados)
	for side: float in [-1.0, 1.0]:
		var a := xf * Vector3(side * 0.9, 0, 2.0)
		var b := xf * Vector3(side * 6.2, -0.1, -4.6)
		var d := xf * Vector3(side * 0.9, 0, -5.4)
		mb.tri(a, b, d, color, xf.basis.y)
		mb.tri(a, d, b, dark, -xf.basis.y)
		var e := xf * Vector3(side * 0.9, 0, -5.4)
		var f := xf * Vector3(side * 3.4, 0, -7.4)
		var g := xf * Vector3(side * 0.9, 0, -7.2)
		mb.tri(e, f, g, color, xf.basis.y)
		mb.tri(e, g, f, dark, -xf.basis.y)
		# Derivas inclinadas para fora
		var h0 := xf * Vector3(side * 0.7, 0.6, -4.2)
		var h1 := xf * Vector3(side * 1.8, 3.2, -6.6)
		var h2 := xf * Vector3(side * 0.7, 0.6, -7.0)
		mb.tri(h0, h1, h2, color, xf.basis.x * side)
		mb.tri(h0, h2, h1, dark, -xf.basis.x * side)


# ---------------------------------------------------------------------------
# Aros gigantes sobre a pista
# ---------------------------------------------------------------------------
## Aros gigantes sobre as retas (passam por baixo da plataforma), girando devagar no próprio plano:
## cada um é um nó com a malha em volta da origem (eixo = Z local, que o SceneryAnimator gira), com
## LEDs na cor da pista: faixa contínua por dentro, uma faixa em cada face (com placas em relevo e
## pinos em volta) e pontos por fora.
static func _rings(track: RaceTrack, root: Node3D) -> void:
	var p := track.path
	var runs := TrackShowcase.straights(track)
	var placed: Array[float] = []
	var animator: SceneryAnimator = null
	if not RaceTrack.server_mode:
		animator = SceneryAnimator.new()
		animator.name = "RingSpin"
		root.add_child(animator)
	var led := SkyDeck.glow(0.0, 1.8, 4.0, true)
	for run in runs:
		if placed.size() >= 3:
			break
		var s: float = run[0] + run[1] * 0.55
		if run[1] < 160.0 or track.in_tunnel(p.index_at(s)) or _near_pit(track, s):
			continue
		var close := false
		for q in placed:
			if absf(fposmod(s - q + p.length * 0.5, p.length) - p.length * 0.5) < 300.0:
				close = true
		if close:
			continue
		placed.append(s)
		var i := p.index_at(s)
		var half := maxf(track.deck_edge(i, 1), track.deck_edge(i, -1)) + 6.0
		var f := p.frame_at(s, 0.0, 0.0)
		var flat := Basis(f.basis.x, Vector3.UP, f.basis.x.cross(Vector3.UP).normalized())
		var radius := half * RING_SCALE
		var mb := MeshBuilder.new()
		var glow := MeshBuilder.new()
		var segs := 64
		var depth := 5.0
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var p0 := Vector3(cos(a0), sin(a0), 0.0) * radius
			var p1 := Vector3(cos(a1), sin(a1), 0.0) * radius
			var mid := (p0 + p1) * 0.5
			var dir := (p1 - p0).normalized()
			var out := mid.normalized()
			var basis := Basis(dir, out, dir.cross(out)).orthonormalized()
			var seg := p0.distance_to(p1) + 0.3
			mb.box(Transform3D(basis, mid), Vector3(seg, 3.2, depth), HULL)
			# Por dentro: faixa contínua; nas duas faces: duas faixas; por fora: um ponto por segmento
			glow.box(Transform3D(basis, mid - out * 1.62), Vector3(seg, 0.08, 1.4), GLASS)
			# Em cada face: uma faixa de LED no meio, placas em relevo acima e abaixo dela e pinos na borda
			for z: float in [-1.0, 1.0]:
				var face := basis.z * z * (depth * 0.5)
				glow.box(Transform3D(basis, mid + face * 1.004), Vector3(seg, 0.3, 0.04), GLASS)
				for h: float in [-1.0, 1.0]:
					mb.box(Transform3D(basis, mid + out * h * 0.85 + face + basis.z * z * 0.06), Vector3(seg * 0.82, 0.8, 0.12), HULL_DARK * 1.6)
					if k % 2 == 1:
						mb.box(Transform3D(basis, mid + out * h * 1.42 + face + basis.z * z * 0.1), Vector3(0.35, 0.22, 0.2), HULL_DARK)
			glow.box(Transform3D(basis, mid + out * 1.62), Vector3(0.9, 0.08, 0.9), GLASS)
			if k % 4 == 0:
				mb.box(Transform3D(basis, mid), Vector3(1.4, 4.4, depth + 1.4), HULL_DARK * 1.4)
		var ring := MeshInstance3D.new()
		ring.name = "Ring%d" % placed.size()
		ring.mesh = mb.commit(null, SkyDeck.hull())
		glow.commit(ring.mesh as ArrayMesh, led)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		ring.global_transform = Transform3D(flat, f.origin)
		if animator:
			animator.add_rotor(ring, 0.12 if placed.size() % 2 == 0 else -0.12)


static func _near_pit(track: RaceTrack, s: float) -> bool:
	return track.layout.has_pit and track.in_span(s, track.layout.pit_entry_s - 60.0, track.layout.pit_exit_s + 60.0)


# ---------------------------------------------------------------------------
# Letreiros
# ---------------------------------------------------------------------------
static func _label(text: String, font_size: int, pixel: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel
	label.outline_size = int(font_size * 0.08)
	label.modulate = SIGN_BLUE
	label.outline_modulate = Color(0.05, 0.1, 0.25)
	label.shaded = false
	label.double_sided = false
	label.no_depth_test = false
	return label


## Nome da base no prédio dos boxes, voltado para a reta, e o lema embaixo.
static func _signs(track: RaceTrack, root: Node3D) -> void:
	if not track.layout.has_pit:
		return
	var p := track.path
	var s := track.layout.garage_center_s
	var i := p.index_at(s)
	var lat := track.pit_lateral(i, RaceTrack.PIT_WALL_STRIP + track.layout.pit_lane_width + PitComplex.DEPTH * 0.5)
	var f := p.frame_at(s, lat, PitComplex.GROUND_H + PitComplex.UPPER_H + 9.0)
	var face := -p.lefts[i] * track.layout.pit_side
	var title := _label("SKY AEROBASE", 1400, 0.012)
	root.add_child(title)
	title.global_transform = Transform3D(Basis.looking_at(-face), f.origin)
	var motto := _label("HIGHER  ·  FASTER  ·  FURTHER", 700, 0.012)
	motto.modulate = Color(0.9, 0.95, 1.0)
	root.add_child(motto)
	motto.global_transform = Transform3D(Basis.looking_at(-face), f.origin + Vector3.DOWN * 7.5)


# ---------------------------------------------------------------------------
# Caças em formação passando sobre a pista (ida e volta, viram longe)
# ---------------------------------------------------------------------------
static func _fighters(track: RaceTrack, root: Node3D, rng: RandomNumberGenerator, mean_y: float) -> void:
	var animator := SceneryAnimator.new()
	animator.name = "Flyby"
	root.add_child(animator)
	var bounds := track.path.bounds()
	var center := Vector3(bounds.get_center().x, 0.0, bounds.get_center().y)
	var reach := bounds.size.length() * 0.5 + 2500.0
	var contrail := SkyDeck.plume_material(Color(1, 1, 1), Color(0.8, 0.88, 1.0), 0.55)
	for k in 3:
		var a := rng.randf() * PI
		var dir := Vector3(cos(a), 0.0, sin(a))
		var height := mean_y + rng.randf_range(120.0, 320.0)
		var mid := center + Vector3(rng.randf_range(-200.0, 200.0), height, rng.randf_range(-200.0, 200.0))
		var group := Node3D.new()
		group.name = "Flight%d" % k
		root.add_child(group)
		var mb := MeshBuilder.new()
		var glow := MeshBuilder.new()
		var trails := MeshBuilder.new()
		for w in 3:
			var off := Vector3((w - 1) * 16.0, (absf(w - 1)) * -2.0, -absf(w - 1) * 14.0)
			_fighter(mb, glow, Transform3D(Basis(), off))
			for side: float in [-0.55, 0.55]:
				_trail(trails, off + Vector3(side, -0.1, -8.4), 260.0)
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit(null, SkyDeck.hull())
		glow.commit(mi.mesh as ArrayMesh, SkyDeck.glow(0.0, 2.0, 3.0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(mi)
		var tmi := MeshInstance3D.new()
		tmi.mesh = trails.commit(null, contrail)
		tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(tmi)
		animator.add_blimp_pass(group, mid - dir * reach, mid + dir * reach, rng.randf_range(110.0, 150.0), rng.randf() * 2.0)


## Rastro de condensação: cone fino e comprido para trás (-Z), UV.y 0 no bocal e 1 na ponta.
static func _trail(mb: MeshBuilder, at: Vector3, length: float) -> void:
	var sides := 6
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var d0 := Vector3(cos(a0), sin(a0), 0)
		var d1 := Vector3(cos(a1), sin(a1), 0)
		mb.quad(at + d0 * 0.25, at + d1 * 0.25, at + d1 * 2.2 + Vector3(0, 0, -length), at + d0 * 2.2 + Vector3(0, 0, -length),
			Color.WHITE, d0 + d1, Vector2(float(k) / sides, 0), Vector2(float(k + 1) / sides, 0),
			Vector2(float(k + 1) / sides, 1), Vector2(float(k) / sides, 1))


# ---------------------------------------------------------------------------
# Dirigíveis-nave
# ---------------------------------------------------------------------------
## Dirigíveis com cara de nave dando voltas sobre trechos diferentes da pista, em alturas variadas
## (sempre perto o bastante para aparecerem de quem pilota). Mais largos que altos: casco achatado,
## convés de cima, ponte de comando, nariz, dois flutuadores laterais presos por asas e cauda dupla;
## janelas acesas no corpo, anúncio em holograma dos dois lados, seis propulsores (quatro para baixo
## sob os flutuadores, dois para trás) e um farol vermelho piscando embaixo (SkyBlink). À noite, luzes
## de verdade nos propulsores e nas janelas iluminam o casco.
static func _airships(track: RaceTrack, root: Node3D, rng: RandomNumberGenerator, mean_y: float, spots: Array) -> void:
	var animator := SceneryAnimator.new()
	animator.name = "ShipRoutes"
	root.add_child(animator)
	var blink := SkyBlink.new()
	blink.name = "ShipBeacons"
	root.add_child(blink)
	var beacon_mat := SkyDeck.glow(0.0, 2.0, 3.6).duplicate() as ShaderMaterial
	blink.materials.append(beacon_mat)
	var p := track.path
	var hull_mesh := _airship_mesh()
	var beacon_mesh := _airship_beacon()
	var plume_down := SkyDeck.plume_mesh(AIRSHIP_DOWN_PLUME, 1.0, 1.8, 14, -AIRSHIP_DOWN_LENGTH - 0.1)
	var plume_back := SkyDeck.plume_mesh(22.0, 1.3, 2.8, 14, 0.0)
	var plume_mat := SkyDeck.plume_material()
	for k in AIRSHIPS:
		var ship := Node3D.new()
		ship.name = "Airship%d" % k
		root.add_child(ship)
		var body := Node3D.new()
		body.name = "Body"
		body.scale = Vector3.ONE * rng.randf_range(0.8, 1.25)
		ship.add_child(body)
		var hull := MeshInstance3D.new()
		hull.mesh = hull_mesh
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(hull)
		var beacon := MeshInstance3D.new()
		beacon.mesh = beacon_mesh
		beacon.material_override = beacon_mat
		beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(beacon)
		# Anúncio em holograma nos dois lados do convés
		var ads := MeshBuilder.new()
		var uv := TrackAds.ad_uv(k * 3 % TrackAds.ad_count())
		for side: float in [-1.0, 1.0]:
			var c := Vector3(side * 6.4, 2.8, -2.0)
			var hz := Vector3(0, 0, -side * 9.0)
			var hy := Vector3(0, 2.0, 0)
			ads.quad(c - hz - hy, c + hz - hy, c + hz + hy, c - hz + hy, Color.WHITE, Vector3(side, 0, 0),
				Vector2(uv.position.x, uv.end.y), Vector2(uv.end.x, uv.end.y), Vector2(uv.end.x, uv.position.y), uv.position)
		var ad := MeshInstance3D.new()
		ad.mesh = ads.commit(null, TrackAds.holo_material(false))
		ad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(ad)
		# Jatos: quatro para baixo e dois para trás (o do plume_mesh desce: girado 90° no X sai para -Z)
		for at: Vector3 in AIRSHIP_DOWN:
			_ship_part(body, plume_down, plume_mat, Transform3D(Basis(), at))
		for at: Vector3 in AIRSHIP_BACK:
			_ship_part(body, plume_back, plume_mat, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at))
		# Luzes que mostram o casco à noite: azul sob os propulsores e atrás, morna nas janelas
		var blue := Color(0.45, 0.7, 1.0)
		var warm := Color(1.0, 0.82, 0.55)
		for l: Array in [[Vector3(-11.0, -7.0, -3.0), blue, 20.0, 12.0], [Vector3(11.0, -7.0, -3.0), blue, 20.0, 12.0],
				[Vector3(0, 0.0, -28.0), blue, 24.0, 9.0], [Vector3(14.0, 2.5, 2.0), warm, 18.0, 6.0], [Vector3(-14.0, 2.5, 2.0), warm, 18.0, 6.0]]:
			body.add_child(_ship_light(l[0], l[1], l[2], l[3], true))
		var red := _ship_light(Vector3(0, -5.5, 2.0), Color(1.0, 0.2, 0.15), 22.0, 6.0, false)
		body.add_child(red)
		blink.lights.append(red)
		# Órbita: sobre um trecho da pista (espalhados pela volta), mais alto ou mais baixo. A primeira
		# dá voltas rente à pista, logo além da borda; a segunda, abaixo da plataforma (vista dos
		# trechos altos e das bordas abertas)
		var speed := rng.randf_range(9.0, 18.0) * (1.0 if k % 2 == 0 else -1.0)
		if k < 2:
			var orbit := _orbit_beside(track, spots, k == 1)
			if not orbit.is_empty():
				var radius: float = orbit[1]
				animator.add_blimp(ship, orbit[0], Vector2(radius, radius), speed * 0.8)
				continue
		var s := (k + rng.randf_range(0.0, 0.6)) * p.length / AIRSHIPS
		var pos := p.position_at(s)
		var height := mean_y + 55.0 + (k % 4) * 60.0 + rng.randf_range(0.0, 30.0)
		var radii := Vector2(rng.randf_range(160.0, 420.0), rng.randf_range(140.0, 380.0))
		animator.add_blimp(ship, Vector3(pos.x, height, pos.z), radii, speed)


## Órbita circular de um dirigível ao lado da pista: [centro, raio], ou [] se não couber. A nave
## passa a CLOSE_GAP m da borda da plataforma (sem cruzar outro trecho nem as torres), CLOSE_HEIGHT m
## acima de uma reta. Com `below`, fica BELOW_DEPTH m abaixo da pista, do lado de uma borda aberta
## (sem barreira no caminho, quem pilota a vê lá embaixo).
static func _orbit_beside(track: RaceTrack, spots: Array, below: bool) -> Array:
	var p := track.path
	var radius := BELOW_RADIUS if below else CLOSE_RADIUS
	var gap := BELOW_GAP if below else CLOSE_GAP
	# Candidatos [s, lados]: retas, as mais longas primeiro (a nave fica no quadro por mais tempo);
	# no de baixo, as bordas abertas, as mais longas primeiro
	var cands := []
	if below:
		for f in track.layout.features:
			if f.kind == TrackFeature.Kind.BARRIER and f.variant == 2:
				cands.append([f.s_start + f.span_length(p.length) * 0.5, f.sides(), f.span_length(p.length)])
	else:
		for run: Array in TrackShowcase.straights(track):
			cands.append([run[0] + run[1] * 0.5, [1, -1], run[1]])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[2] > b[2])
	for cand: Array in cands:
		var s: float = cand[0]
		var i := p.index_at(s)
		if _near_pit(track, s) or track.in_tunnel(i):
			continue
		for side: int in cand[1]:
			if _stands_at(track, s, side):
				continue  # a arquibancada esconderia a nave de quem pilota
			var c := p.frame_at(s, side * (track.deck_edge(i, side) + gap + radius), 0.0).origin
			if _orbit_clear(track, spots, Vector2(c.x, c.z), radius + gap):
				var y := p.position_at(s).y + (-BELOW_DEPTH if below else CLOSE_HEIGHT)
				return [Vector3(c.x, y, c.z), radius]
	return []


## Há arquibancada desse lado (1 esquerda, -1 direita) perto de s.
static func _stands_at(track: RaceTrack, s: float, side: int) -> bool:
	for f in track.layout.features:
		if f.kind == TrackFeature.Kind.GRANDSTAND and side in f.sides() and track.in_span(s, f.s_start - 100.0, f.s_end + 100.0):
			return true
	return false


## O círculo (x, z) de raio `reach` não encosta em nenhum trecho da plataforma nem nas torres.
static func _orbit_clear(track: RaceTrack, spots: Array, c: Vector2, reach: float) -> bool:
	var p := track.path
	for i in range(0, p.size(), 2):
		var q := p.points[i]
		if Vector2(q.x, q.z).distance_to(c) < reach + maxf(track.deck_edge(i, 1), track.deck_edge(i, -1)) - 1.0:
			return false
	for spot: Array in spots:
		if (spot[0] as Vector2).distance_to(c) < reach - CLOSE_GAP + 60.0:
			return false
	return true


static func _ship_part(parent: Node3D, mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = xf
	parent.add_child(mi)


## Luz de um dirigível (sem sombra, some de longe). night = acende com o horário ("night_lights").
static func _ship_light(at: Vector3, color: Color, reach: float, energy: float, night: bool) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = color
	light.omni_range = reach
	light.omni_attenuation = 1.2
	light.light_energy = energy
	light.set_meta("base_energy", energy)
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 500.0
	light.distance_fade_length = 120.0
	light.visible = false
	if night:
		light.add_to_group("night_lights")
	return light


const AIRSHIPS := 12
## Propulsores do dirigível (espaço da nave, antes da escala): para baixo, sob os flutuadores (topo da
## nacela) e para trás, no fim dos flutuadores (boca do bocal).
const AIRSHIP_DOWN := [Vector3(-11.0, -2.6, 5.0), Vector3(11.0, -2.6, 5.0), Vector3(-11.0, -2.6, -11.0), Vector3(11.0, -2.6, -11.0)]
const AIRSHIP_BACK := [Vector3(-11.0, -0.8, -21.5), Vector3(11.0, -0.8, -21.5)]
const AIRSHIP_DOWN_LENGTH := 3.6
## Comprimento do jato dos propulsores de baixo (m, antes da escala).
const AIRSHIP_DOWN_PLUME := 8.0
## Dirigível rente à pista: raio da órbita, folga até a borda da plataforma e altura sobre a pista.
const CLOSE_RADIUS := 60.0
const CLOSE_GAP := 30.0
const CLOSE_HEIGHT := 26.0
## Dirigível abaixo da pista: raio, folga até a borda aberta e profundidade abaixo dela.
const BELOW_RADIUS := 110.0
const BELOW_GAP := 80.0
const BELOW_DEPTH := 20.0


## Malha do dirigível-nave (nariz para +Z, ~56 m de comprimento e ~30 de largura, ~10 de altura).
static func _airship_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var glow := MeshBuilder.new()
	var hull := Color(0.5, 0.53, 0.6)
	var dark := Color(0.28, 0.3, 0.35)
	var warm := Color(1.0, 0.84, 0.52)
	var cyan := Color(0.55, 0.86, 1.0)
	# Casco achatado, convés de cima, ponte de comando e nariz
	mb.blob(Vector3.ZERO, Vector3(9.0, 3.6, 22.0), hull, 22, 10)
	mb.blob(Vector3(0, 2.5, -2.0), Vector3(5.6, 2.4, 13.0), hull * 1.05, 18, 8)
	mb.blob(Vector3(0, 4.0, 7.5), Vector3(3.2, 1.7, 4.2), dark * 1.3, 14, 7)
	mb.blob(Vector3(0, -0.4, 19.0), Vector3(4.5, 2.2, 7.5), hull, 16, 8)
	mb.blob(Vector3(0, -3.3, 0.0), Vector3(4.0, 1.2, 14.0), dark, 14, 6)
	# Flutuadores laterais, asas que os prendem e a cauda dupla
	for side: float in [-1.0, 1.0]:
		var fx := side * 11.0
		mb.lathe(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(fx, -0.8, -20.0)),
			PackedVector2Array([Vector2(1.6, 0.0), Vector2(2.3, 2.5), Vector2(2.5, 9.0), Vector2(2.5, 26.0), Vector2(2.0, 31.0),
				Vector2(1.0, 33.5), Vector2(0.0, 34.5)]), hull * 0.95, 18)
		var w0 := Vector3(side * 6.5, -0.3, 8.0)
		var w1 := Vector3(side * 11.0, -0.4, 3.0)
		var w2 := Vector3(side * 11.0, -0.6, -12.0)
		var w3 := Vector3(side * 6.5, -0.4, -14.0)
		for dy: float in [0.45, -0.45]:
			mb.quad(w0 + Vector3.UP * dy, w1 + Vector3.UP * dy, w2 + Vector3.UP * dy, w3 + Vector3.UP * dy, dark * 1.5, Vector3.UP * signf(dy))
		mb.quad(w1 + Vector3.UP * 0.45, w1 - Vector3.UP * 0.45, w2 - Vector3.UP * 0.45, w2 + Vector3.UP * 0.45, dark, Vector3(side, 0, 0))
		mb.quad(w0 + Vector3.UP * 0.45, w0 - Vector3.UP * 0.45, w1 - Vector3.UP * 0.45, w1 + Vector3.UP * 0.45, dark, Vector3(0, 0, 1))
		# Deriva da cauda (dois lados da chapa)
		var t0 := Vector3(side * 3.6, 3.0, -14.0)
		var t1 := Vector3(side * 5.2, 9.5, -22.0)
		var t2 := Vector3(side * 4.0, 2.4, -22.5)
		mb.tri(t0, t1, t2, dark * 1.4, Vector3(side, 0, 0))
		mb.tri(t0, t2, t1, dark * 1.4, Vector3(-side, 0, 0))
		glow.blob(t1 + Vector3(0, 0.2, 0), Vector3.ONE * 0.45, Color(1.0, 0.25, 0.2), 8, 5)
		# Janelas: duas fileiras no casco, uma no convés, escotilhas nos flutuadores
		for row: Array in [[0.4, 8.6, 9, 3.0, warm], [-1.4, 8.2, 8, 3.0, warm], [3.2, 5.3, 6, 3.2, cyan]]:
			var y: float = row[0]
			var half: float = row[1]
			for w in int(row[2]):
				var z := 10.0 - w * float(row[3])
				var x := half * sqrt(maxf(1.0 - pow(z / 22.0, 2.0), 0.1))
				glow.box(Transform3D(Basis(Vector3.UP, atan2(z * 0.4, 22.0) * side), Vector3(side * x, y, z)), Vector3(0.12, 0.7, 1.5), row[4])
		for w in 5:
			glow.blob(Vector3(fx + side * 2.45, -0.5, 6.0 - w * 4.0), Vector3(0.1, 0.45, 0.45), warm, 6, 4)
		# Propulsores para baixo (sob os flutuadores) e para trás (no fim deles)
		for at: Vector3 in [Vector3(fx, -2.6, 5.0), Vector3(fx, -2.6, -11.0)]:
			mb.lathe(Transform3D(Basis(), at - Vector3.UP * AIRSHIP_DOWN_LENGTH), PackedVector2Array([Vector2(1.05, 0.0), Vector2(1.3, 0.6),
				Vector2(1.45, 2.0), Vector2(1.35, AIRSHIP_DOWN_LENGTH)]), dark * 1.2, 16)
			glow.cylinder(Transform3D(Basis(), at - Vector3.UP * (AIRSHIP_DOWN_LENGTH + 0.05)), 1.1, 1.1, 0.25, cyan, 16, false)
			glow.cylinder(Transform3D(Basis(Vector3.RIGHT, PI), at - Vector3.UP * (AIRSHIP_DOWN_LENGTH - 0.02)), 0.95, 0.0, 0.01, cyan, 16)
		var back := Vector3(fx, -0.8, -21.5)
		var axis := Basis(Vector3.RIGHT, -PI * 0.5)  # eixo Y do torno → -Z
		mb.lathe(Transform3D(axis, back + Vector3(0, 0, 4.0)), PackedVector2Array([Vector2(2.2, 0.0), Vector2(1.9, 3.2), Vector2(1.6, 4.0)]),
			dark * 1.2, 16)
		glow.cylinder(Transform3D(axis, back + Vector3(0, 0, 0.05)), 1.45, 0.0, 0.05, cyan, 16)
	# Janelas da ponte de comando (faixa na frente)
	glow.blob(Vector3(0, 4.4, 10.6), Vector3(2.6, 0.6, 1.2), cyan, 12, 6)
	var mesh := mb.commit(null, SkyDeck.hull())
	glow.commit(mesh, SkyDeck.glow(0.0, 1.8, 3.6))
	return mesh


## Farol embaixo do casco (a cor pisca pelo material do SkyBlink).
static func _airship_beacon() -> ArrayMesh:
	var mb := MeshBuilder.new()
	mb.blob(Vector3(0, -4.6, 2.0), Vector3.ONE * 0.7, Color(1.0, 0.18, 0.12), 10, 6)
	return mb.commit()
