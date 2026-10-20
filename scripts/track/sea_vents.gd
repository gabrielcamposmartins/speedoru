class_name SeaVents
extends RefCounted
## Vulcões de bolhas no fundo do mar (Atlantis Abyss), logo ao lado do tubo nos trechos sem cânion:
##  * o monte de rocha vulcânica irregular (anéis com ruído e lava escorrida em sulcos), com crostas
##    minerais coloridas perto da boca e das chaminés (enxofre amarelo, ferrugem, esteiras brancas de
##    bactérias), almofadas de lava nas encostas e pedras em volta;
##  * a cratera com o fundo de lava, rachaduras acesas descendo as encostas, um halo de luz sobre a
##    boca (vent_glow.gdshader) e uma luz de verdade (mais forte à noite);
##  * chaminés em volta da cratera (fumarolas negras: tortas, encaroçadas, largas no pé e finas no alto,
##    com crostas de enxofre e ferrugem em manchas perto da boca e esteiras brancas no pé) soltando
##    fumaça escura e bolhas, com colônias de vermes tubulares no pé (SeaReef.worms);
##  * a coluna de bolhas subindo até a superfície e filetes saindo das rachaduras
##    (vent_bubbles.gdshader, sem emissor), a água tremendo de calor sobre a boca
##    (vent_shimmer.gdshader) e a espuma onde a coluna chega.
## Ficam a GAP m da borda do tubo (sem encostar nele, na laje ou nos arcos), longe uns dos outros e
## do que já ocupa o leito (SeaFloor.claim). Nada tem colisão.

const COUNT := 10
const BUBBLES := 720
const SIDES := 28
const RINGS := 10
const BASALT := Color(0.14, 0.12, 0.13)
const GLOW := Color(1.0, 0.42, 0.12)
## Lava nas rachaduras (mais vermelha que a da boca).
const CRACK := Color(1.0, 0.3, 0.06)
## Crostas minerais: enxofre, ferrugem, esteira de bactérias, ocre.
const CRUSTS := [Color(0.88, 0.74, 0.18), Color(0.8, 0.4, 0.12), Color(0.9, 0.88, 0.8), Color(0.66, 0.56, 0.2)]
const MIN_SPACING := 140.0
const CRATER := 4.4
## Distância (m) da borda do monte até a borda do tubo.
const GAP := Vector2(3.0, 22.0)

static var _mound_mat: Material
static var _halo_mat: ShaderMaterial
static var _shimmer_mat: ShaderMaterial


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Vents"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var p := track.path
	var water := track.layout.water_level
	var spots: Array[Vector3] = []
	var sizes: Array[Vector2] = []
	var tries := 0
	while spots.size() < COUNT and tries < COUNT * 80:
		tries += 1
		# (nos trechos abertos: nos cânions a rocha toma o lugar)
		var s := SeaCanyon.random_open_s(track, rng)
		var i := p.index_at(s)
		var side := 1 if rng.randf() < 0.5 else -1
		var radius := rng.randf_range(15.0, 23.0)
		var h := rng.randf_range(11.0, 17.0)
		var lat := SeaTube.clearance(track, i, side) + radius + rng.randf_range(GAP.x, GAP.y)
		var pos := p.frame_at(s, side * lat, 0.0).origin
		pos.y = SeaFloor.ground(track, pos.x, pos.z)
		# Chão quase plano sob o monte (nas encostas ele ficaria flutuando de um lado) e não no fundo da
		# fossa (lá ninguém vê)
		var low := pos.y
		var high := pos.y
		for k in 8:
			var a := TAU * k / 8.0
			var g := SeaFloor.ground(track, pos.x + cos(a) * radius * 0.8, pos.z + sin(a) * radius * 0.8)
			low = minf(low, g)
			high = maxf(high, g)
		if high - low > h * 0.5 or low < p.points[i].y - 30.0:
			continue
		pos.y = low
		if pos.y + h + 9.0 > water - 4.0 or not _clear(track, pos, radius, h) or SeaFloor.claimed(pos, radius * 0.9):
			continue
		var far := true
		for o in spots:
			if Vector2(o.x - pos.x, o.z - pos.z).length() < MIN_SPACING:
				far = false
				break
		if far:
			spots.append(pos)
			sizes.append(Vector2(radius, h))
			# (a base larga e baixa; o cone e as chaminés, estreitos e altos)
			SeaFloor.claim(pos, radius * 1.05, pos.y + h * 0.45)
			SeaFloor.claim(pos, radius * 0.45, pos.y + h + 9.0)
	var mb := MeshBuilder.new()
	var glow := MeshBuilder.new()
	var craters: Array[Vector3] = []
	var chimney_count := 0
	for v in spots.size():
		var pos := spots[v]
		var radius := sizes[v].x
		var h := sizes[v].y
		var tops := _mound(mb, glow, pos + Vector3.DOWN * 0.8, radius, h, rng)
		var crater := pos + Vector3.UP * (h - 3.2)
		craters.append(crater)
		_column(track, root, crater, water - crater.y, BUBBLES, CRATER * 0.4, rng.randf_range(2.2, 3.2), rng)
		root.add_child(_shimmer(crater + Vector3.UP * 0.5, 16.0))
		# Fumaça escura e bolhas das chaminés; vermes tubulares no pé delas
		for top: Vector3 in tops:
			_smoke(root, top, rng)
			_column(track, root, top, water - top.y, 70, 0.35, rng.randf_range(1.8, 2.6), rng, false)
			chimney_count += 1
		# Corais em volta (de longe da boca quente)
		for k in 3:
			var a := rng.randf() * TAU
			SeaReef.cluster(pos + Vector3(cos(a), 0.0, sin(a)) * radius * rng.randf_range(0.85, 1.05), radius * 0.4, rng, 7)
		if not RaceTrack.server_mode:
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.55, 0.25)
			light.light_energy = 4.5
			light.omni_range = 46.0
			light.omni_attenuation = 1.2
			light.shadow_enabled = false
			root.add_child(light)
			light.global_position = crater + Vector3.UP * 3.0
			root.add_child(_halo(crater + Vector3.UP * 3.5, CRATER * 3.4))
	if _mound_mat == null:
		_mound_mat = TrackMaterials.sea_stone("vent", false, {"marble_mix": 0.0, "moss_amount": 0.12, "coral_amount": 0.06,
			"detail_scale": 0.4, "detail_strength": 0.35, "normal_strength": 1.0})
	var mi := MeshInstance3D.new()
	mi.name = "Mounds"
	mi.mesh = mb.commit(null, _mound_mat)
	glow.commit(mi.mesh as ArrayMesh, SkyDeck.glow(0.0, 2.4, 5.0))
	mi.visibility_range_end = 900.0
	root.add_child(mi)
	root.set_meta("vents", craters)
	root.set_meta("chimneys", chimney_count)


## O monte (raio, altura) em `pos` não encosta no tubo, na laje nem nos arcos embaixo dela (pontos
## da encosta em volta, em várias alturas).
static func _clear(track: RaceTrack, pos: Vector3, radius: float, h: float) -> bool:
	for k in 12:
		var dir := Vector3(cos(TAU * k / 12.0), 0.0, sin(TAU * k / 12.0))
		for f: float in [0.05, 0.35, 0.7, 1.0]:
			var r := lerpf(radius, CRATER + 1.0, pow(f, 0.7)) * 1.12
			if SeaTube.blocked(track, pos + dir * r + Vector3.UP * (h * f), 1.5):
				return false
	return not SeaTube.blocked(track, pos + Vector3.UP * (h + 6.0), 3.0)


## Monte de rocha irregular com a cratera: anéis com ruído (o raio e a altura variam com o ângulo),
## sulcos de lava escorrida, crostas minerais perto da boca, a parede de dentro e o fundo aceso,
## rachaduras com lava, almofadas de lava, pedras em volta e as chaminés. Devolve o topo de cada
## chaminé.
static func _mound(mb: MeshBuilder, glow: MeshBuilder, base: Vector3, radius: float, h: float,
		rng: RandomNumberGenerator) -> Array[Vector3]:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.9
	var rot := rng.randf() * TAU
	# Sulcos de lava escorrida: ângulos em que a encosta afunda um pouco, da boca até embaixo
	var flows: Array[float] = []
	for f in rng.randi_range(4, 7):
		flows.append(rng.randf() * TAU)
	var grid: Array[PackedVector3Array] = []
	var tees := PackedFloat32Array()
	for k in RINGS + 1:
		var t := float(k) / RINGS
		var row := PackedVector3Array()
		for j in SIDES:
			var th := TAU * j / SIDES + rot
			var n := noise.get_noise_2d(cos(th) * 1.4 + t * 2.2, sin(th) * 1.4 + t * 1.3)
			var groove := 0.0
			for fa in flows:
				groove = maxf(groove, 1.0 - smoothstep(0.0, 0.22, absf(angle_difference(th, fa))))
			var r := lerpf(radius, CRATER + 0.9, pow(t, 0.7)) * (1.0 + 0.16 * n * (1.0 - t * 0.5)) - groove * 0.9 * sin(t * PI)
			var y := h * t * t * (3.0 - 2.0 * t) + (0.9 * n if k == RINGS else 0.7 * n * sin(t * PI))
			row.append(base + Vector3(cos(th), 0.0, sin(th)) * r + Vector3.UP * y)
		grid.append(row)
		tees.append(t)
	# Parede de dentro da cratera e o fundo
	for inner: Vector2 in [Vector2(CRATER, -1.1), Vector2(CRATER * 0.72, -2.1), Vector2(0.0, -2.5)]:
		var row := PackedVector3Array()
		for j in SIDES:
			var th := TAU * j / SIDES + rot
			row.append(base + Vector3(cos(th), 0.0, sin(th)) * inner.x + Vector3.UP * (h + inner.y))
		grid.append(row)
		tees.append(1.2)
	var rows := grid.size()
	# Normais suaves pela grade (para fora na encosta; seguem a superfície para dentro da cratera)
	var normals: Array[PackedVector3Array] = []
	for k in rows:
		var nrow := PackedVector3Array()
		for j in SIDES:
			var dk := grid[mini(k + 1, rows - 1)][j] - grid[maxi(k - 1, 0)][j]
			var dj := grid[k][(j + 1) % SIDES] - grid[k][(j + SIDES - 1) % SIDES]
			nrow.append(dj.cross(dk).normalized())
		normals.append(nrow)
	var out0 := grid[0][0] - base
	out0.y = 0.0
	if normals[1][0].dot(out0) < 0.0:
		for k in rows:
			for j in SIDES:
				normals[k][j] = -normals[k][j]
	# Cores: basalto variando, crostas em manchas perto da boca, a parede de dentro avermelhada
	var colors: Array[PackedColorArray] = []
	for k in rows:
		var crow := PackedColorArray()
		for j in SIDES:
			var q := grid[k][j]
			var t := tees[k]
			var n := noise.get_noise_2d(q.x * 0.35 + 50.0, q.z * 0.35)
			var c := BASALT * (0.85 + 0.35 * (n * 0.5 + 0.5))
			c.a = 1.0
			if t > 1.0:
				c = c.lerp(Color(0.42, 0.14, 0.08), 0.6)
			else:
				var crust := smoothstep(0.6, 0.92, t) * smoothstep(-0.05, 0.25, n)
				var pick: Color = CRUSTS[int(absf(noise.get_noise_2d(q.x * 0.11, q.z * 0.11 + 9.0)) * 37.0) % CRUSTS.size()]
				c = c.lerp(pick, crust * 0.85)
				# Esteiras de bactérias (brancas) em volta da base
				c = c.lerp(CRUSTS[2], (1.0 - smoothstep(0.0, 0.12, t)) * smoothstep(0.3, 0.6, n) * 0.6)
			crow.append(c)
		colors.append(crow)
	for k in rows - 1:
		for j in SIDES:
			var j1 := (j + 1) % SIDES
			mb.tri_smooth(grid[k][j], grid[k][j1], grid[k + 1][j1], normals[k][j], normals[k][j1], normals[k + 1][j1],
				colors[k][j], colors[k][j1], colors[k + 1][j1])
			mb.tri_smooth(grid[k][j], grid[k + 1][j1], grid[k + 1][j], normals[k][j], normals[k + 1][j1], normals[k + 1][j],
				colors[k][j], colors[k + 1][j1], colors[k + 1][j])
	# Lava no fundo da cratera e o anel aceso na boca
	glow.blob(base + Vector3.UP * (h - 2.35), Vector3(CRATER * 0.7, 0.45, CRATER * 0.7), GLOW, 14, 4)
	for j in SIDES:
		var a := grid[RINGS + 1][j]
		var b := grid[RINGS + 1][(j + 1) % SIDES]
		var c := grid[RINGS + 2][(j + 1) % SIDES]
		var d := grid[RINGS + 2][j]
		glow.quad(a.lerp(d, 0.35), b.lerp(c, 0.35), c, d, GLOW * 0.8, Vector3.UP)
	# Rachaduras acesas descendo pelos sulcos: finas, em zigue-zague (cada ponto puxado para um lado
	# entre as colunas da grade), mais largas perto da boca e com falhas no caminho
	for fa in flows:
		var j := int(round(fposmod(fa - rot, TAU) / TAU * SIDES)) % SIDES
		var prev := grid[RINGS - 1][j] + normals[RINGS - 1][j] * 0.12
		for k in range(RINGS - 2, rng.randi_range(0, 3) - 1, -1):
			var nb := (j + (1 if rng.randf() < 0.5 else SIDES - 1)) % SIDES
			var at := grid[k][j].lerp(grid[k][nb], rng.randf_range(0.0, 0.3)) + normals[k][j] * 0.12
			if rng.randf() < 0.2:
				prev = at
				continue
			var side := normals[k][j].cross(at - prev).normalized()
			var w := lerpf(0.6, 0.14, 1.0 - float(k) / RINGS) * rng.randf_range(0.7, 1.3)
			var mid := prev.lerp(at, 0.5) + side * rng.randf_range(-0.5, 0.5)
			glow.quad(prev - side * w * 0.5, prev + side * w * 0.5, mid + side * w * 0.6, mid - side * w * 0.6, CRACK, normals[k][j])
			glow.quad(mid - side * w * 0.6, mid + side * w * 0.6, at + side * w * 0.4, at - side * w * 0.4, CRACK, normals[k][j])
			prev = at
	# Almofadas de lava nas encostas e pedras em volta
	for k in rng.randi_range(10, 16):
		var ring := rng.randi_range(0, RINGS - 3)
		var j := rng.randi() % SIDES
		var sz := rng.randf_range(1.0, 2.6)
		mb.blob(grid[ring][j] + normals[ring][j] * sz * 0.35, Vector3(sz, sz * 0.6, sz * 1.2), BASALT * 1.15, 8, 5, 0.3)
	for k in rng.randi_range(8, 13):
		var a := rng.randf() * TAU
		var d := radius * rng.randf_range(0.85, 1.35)
		var sz := rng.randf_range(1.0, 3.2)
		mb.blob(base + Vector3(cos(a) * d, sz * 0.3, sin(a) * d), Vector3(sz, sz * 0.7, sz * 1.1), BASALT * 1.1, 7, 5, 0.3)
	# Chaminés na parte de cima da encosta (lados diferentes)
	var tops: Array[Vector3] = []
	var start := rng.randi() % SIDES
	for c in rng.randi_range(2, 4):
		var j := (start + c * SIDES / 3 + rng.randi_range(-2, 2) + SIDES) % SIDES
		var ring := rng.randi_range(RINGS - 5, RINGS - 3)
		var at := grid[ring][j] - normals[ring][j] * 0.3
		tops.append(_chimney(mb, glow, at, rng.randf_range(4.5, 9.0), rng.randf_range(0.9, 1.5), rng))
		# Vermes tubulares em volta do pé (na encosta, crescendo para cima)
		for spot: Vector2i in [Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(0, -2), Vector2i(0, 2), Vector2i(1, 0)]:
			var rk := clampi(ring + spot.x, 0, RINGS)
			var jj := (j + spot.y + SIDES) % SIDES
			var up := (normals[rk][jj] + Vector3.UP).normalized()
			var x := up.cross(Vector3.FORWARD).normalized()
			var xf := Transform3D(Basis(x, up, x.cross(up)).orthonormalized().scaled(Vector3.ONE * rng.randf_range(1.0, 1.8)),
				grid[rk][jj] - normals[rk][jj] * 0.1)
			SeaReef.place(SeaReef.Kind.WORM, xf, rng)
			SeaReef.place(SeaReef.Kind.PLUME, xf, rng)
	return tops


## Chaminé (fumarola negra): um tronco torto e encaroçado, largo no pé e fino no alto (anéis com o
## raio variando pelo ruído e saliências de depósito), basalto escuro com manchas de crosta de enxofre
## e ferrugem perto da boca e esteira branca no pé, uns caroços avulsos e a boca alargada com o brilho
## de lava por dentro. Devolve a boca.
static func _chimney(mb: MeshBuilder, glow: MeshBuilder, at: Vector3, height: float, radius: float,
		rng: RandomNumberGenerator) -> Vector3:
	const RINGS_C := 10
	const SIDES_C := 11
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.55
	var dir := Vector3.UP
	var center := at
	var grid: Array[PackedVector3Array] = []
	var tees := PackedFloat32Array()
	var bend := Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.04, 0.1)
	for k in RINGS_C + 1:
		var t := float(k) / RINGS_C
		if k > 0:
			dir = (dir + bend + Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.06, 0.06))).normalized()
			center += dir * height / RINGS_C
		var x := dir.cross(Vector3.FORWARD).normalized()
		var z := x.cross(dir).normalized()
		# (largo no pé, afinando; saliências de depósito em alturas ao acaso)
		var r := radius * lerpf(1.35, 0.62, pow(t, 0.8)) * (1.0 + 0.22 * maxf(sin(t * 19.0 + radius * 7.0), 0.0))
		var row := PackedVector3Array()
		for j in SIDES_C:
			var a := TAU * j / SIDES_C
			var n := noise.get_noise_3d(cos(a) * 1.6, t * height * 0.5, sin(a) * 1.6)
			row.append(center + (x * cos(a) + z * sin(a)) * r * (1.0 + 0.3 * n))
		grid.append(row)
		tees.append(t)
	var rows := grid.size()
	for k in rows - 1:
		for j in SIDES_C:
			var j1 := (j + 1) % SIDES_C
			var pts: Array[Vector3] = [grid[k][j], grid[k][j1], grid[k + 1][j1], grid[k + 1][j]]
			var cs: Array[Color] = []
			var ns: Array[Vector3] = []
			for q in 4:
				var kk := k + (1 if q >= 2 else 0)
				var jj := j1 if q == 1 or q == 2 else j
				var dk := grid[mini(kk + 1, rows - 1)][jj] - grid[maxi(kk - 1, 0)][jj]
				var dj := grid[kk][(jj + 1) % SIDES_C] - grid[kk][(jj + SIDES_C - 1) % SIDES_C]
				ns.append(dj.cross(dk).normalized())
				var p3 := pts[q]
				var t := tees[kk]
				var n := noise.get_noise_3d(p3.x * 0.9 + 30.0, p3.y * 0.9, p3.z * 0.9)
				var c := BASALT * (0.8 + 0.45 * (n * 0.5 + 0.5))
				var pick: Color = CRUSTS[0] if n > 0.25 else CRUSTS[1]
				c = c.lerp(pick, smoothstep(0.45, 0.85, t) * smoothstep(0.0, 0.35, absf(n)) * 0.8)
				c = c.lerp(CRUSTS[2], (1.0 - smoothstep(0.0, 0.18, t)) * smoothstep(0.1, 0.5, n) * 0.7)
				c.a = 1.0
				cs.append(c)
			# (normais para fora: a ordem dos anéis pode virar a conta)
			var out := (pts[0] - grid[k][(j + SIDES_C / 2) % SIDES_C]).normalized()
			for q in 4:
				if ns[q].dot(out) < 0.0:
					ns[q] = -ns[q]
			mb.tri_smooth(pts[0], pts[1], pts[2], ns[0], ns[1], ns[2], cs[0], cs[1], cs[2])
			mb.tri_smooth(pts[0], pts[2], pts[3], ns[0], ns[2], ns[3], cs[0], cs[2], cs[3])
	# Caroços de depósito colados no tronco
	for b in rng.randi_range(3, 6):
		var k := rng.randi_range(1, RINGS_C - 2)
		var j := rng.randi() % SIDES_C
		var sz := radius * rng.randf_range(0.35, 0.6)
		mb.blob(grid[k][j], Vector3(sz, sz * 1.3, sz), BASALT * 1.1, 7, 4, 0.3)
	# Boca alargada e o brilho dentro dela
	var top := grid[RINGS_C][0].lerp(grid[RINGS_C][SIDES_C / 2], 0.5)
	var r_top := grid[RINGS_C][0].distance_to(top)
	mb.cylinder(Transform3D(Basis(), top), r_top, r_top * 1.3, 0.45, BASALT * 1.3, 11, false)
	glow.blob(top + Vector3.UP * 0.28, Vector3(r_top * 0.85, 0.2, r_top * 0.85), GLOW, 8, 3)
	return top + Vector3.UP * 0.45


## Halo de luz laranja sobre a boca da cratera (billboard aditivo, mais forte à noite).
static func _halo(pos: Vector3, size: float) -> MeshInstance3D:
	if _halo_mat == null:
		_halo_mat = ShaderMaterial.new()
		_halo_mat.shader = load("res://shaders/track/vent_glow.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	var mi := MeshInstance3D.new()
	mi.name = "VentGlow"
	mi.mesh = quad
	mi.material_override = _halo_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
	mi.visibility_range_end = 700.0
	mi.position = pos
	mi.scale = Vector3.ONE * size
	return mi


## A água tremendo de calor sobre a boca: um cilindro aberto (raio 2,5 → 6 m, `height` m) que
## distorce o que está atrás (vent_shimmer.gdshader); desenhado antes das bolhas.
static func _shimmer(pos: Vector3, height: float) -> MeshInstance3D:
	if _shimmer_mat == null:
		_shimmer_mat = ShaderMaterial.new()
		_shimmer_mat.shader = load("res://shaders/track/vent_shimmer.gdshader")
		_shimmer_mat.render_priority = -1
	var mb := MeshBuilder.new()
	var sides := 16
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		mb.quad(d0 * 2.5, d1 * 2.5, d1 * 6.0 + Vector3.UP * height, d0 * 6.0 + Vector3.UP * height, Color.WHITE, d0 + d1,
			Vector2(float(k) / sides, 0), Vector2(float(k + 1) / sides, 0), Vector2(float(k + 1) / sides, 1), Vector2(float(k) / sides, 1))
	var mi := MeshInstance3D.new()
	mi.name = "VentShimmer"
	mi.mesh = mb.commit(null, _shimmer_mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 260.0
	mi.position = pos
	return mi


## Coluna de bolhas de `base` até a superfície (`height` m acima), com `count` bolhas; a principal
## (foam) deixa a espuma onde chega.
static func _column(track: RaceTrack, root: Node3D, base: Vector3, height: float, count: int, base_radius: float, speed: float,
		rng: RandomNumberGenerator, foam := true) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/vent_bubbles.gdshader")
	mat.set_shader_parameter("height", height)
	mat.set_shader_parameter("speed", speed)
	mat.set_shader_parameter("base_radius", base_radius)
	mat.set_shader_parameter("spread", 3.6 if foam else 1.6)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = count
	for k in count:
		mm.set_instance_transform(k, Transform3D())
		mm.set_instance_custom_data(k, Color(rng.randf(), rng.randf(), rng.randf_range(0.2, 1.0), rng.randf()))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "VentBubbles"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-10, -1, -10), Vector3(20, height + 2.0, 20))
	mmi.visibility_range_end = 700.0
	root.add_child(mmi)
	mmi.global_position = base
	if not foam:
		return
	# Espuma onde a coluna chega na superfície (vista de cima e, de baixo, como uma mancha clara)
	var mb := MeshBuilder.new()
	var c := Vector3(base.x, track.layout.water_level + 0.05, base.z)
	var r := 9.0
	mb.quad(c + Vector3(-r, 0, -r), c + Vector3(r, 0, -r), c + Vector3(r, 0, r), c + Vector3(-r, 0, r), Color.WHITE, Vector3.UP,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	var foam_mi := MeshInstance3D.new()
	foam_mi.name = "VentFoam"
	foam_mi.mesh = mb.commit(null, PoseidonGate.water_material(1))
	foam_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(foam_mi)


## Fumaça escura de minerais saindo da boca de uma chaminé: nuvens macias que sobem devagar abrindo
## e somem uns 30 m acima (vent_bubbles.gdshader no modo fumaça).
static func _smoke(root: Node3D, top: Vector3, rng: RandomNumberGenerator) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/vent_bubbles.gdshader")
	mat.set_shader_parameter("height", 30.0)
	mat.set_shader_parameter("speed", rng.randf_range(1.3, 1.8))
	mat.set_shader_parameter("base_radius", 0.4)
	mat.set_shader_parameter("spread", 5.0)
	mat.set_shader_parameter("puff", true)
	mat.set_shader_parameter("color", Color(0.17, 0.15, 0.16))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = 46
	for k in 46:
		mm.set_instance_transform(k, Transform3D())
		mm.set_instance_custom_data(k, Color(float(k) / 46.0 + rng.randf() * 0.02, rng.randf(), rng.randf_range(0.2, 1.0), rng.randf()))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "VentSmoke"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-14, -1, -14), Vector3(28, 34, 28))
	mmi.visibility_range_end = 500.0
	root.add_child(mmi)
	mmi.global_position = top
