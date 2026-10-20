class_name SeaLife
extends RefCounted
## A vida marinha da pista no fundo do mar (Atlantis Abyss), toda animada pela GPU ou pelo
## SceneryAnimator (Rust), sem _process por bicho:
##  * cardumes de peixinhos coloridos (MultiMesh, como os bandos de pássaros: add_flock);
##  * raias-manta, tubarões e tartarugas dando voltas (add_blimp), baleias grandes (34 a 39 m) indo e
##    voltando junto do tubo, do lado sem arquibancadas nem boxes (um grupo com filhote ao lado da
##    Ponte do Abismo e mais quatro nos trechos abertos: add_blimp_pass) e grupos de golfinhos
##    (add_flock);
## quase todos nos trechos abertos (sem cânion: SeaCanyon.open_spans), onde há espaço para nadar;
##  * o polvo gigante enroscado numa coluna por fora da Curva do Polvo;
##  * grupos de águas-vivas brilhantes (mais fortes à noite).
## Os bichos grandes vêm de blender/atlantis_creatures.py (sea_creature.gdshader: dorso, ventre e
## destaque por instância, as máscaras e o peso do nado pintados no modelo). Cada rota é conferida
## (_route_ok): fora do tubo de vidro (SeaTube.inside), abaixo da linha d'água e acima do leito e das
## montanhas. Nada tem colisão.

const MODELS := "res://assets/track/atlantis_abyss/models/"
## Distância máxima em que os bichos aparecem (a névoa da água esconde antes).
const VISIBILITY := 700.0
## Meia-altura da baleia na escala 1 (com folga), para as rotas.
const WHALE_SIZE := 2.6
## Bicho: [cor do dorso, cor do ventre, manchas, modo do nado, amplitude, frequência, onda, cor de destaque]
## (o desenho de cada um — ventre, destaque, olhos, guelras, placas — vem pintado no modelo: as manchas
## de ruído ficam desligadas)
const LOOK := {
	"whale": [Color(0.13, 0.16, 0.21), Color(0.86, 0.88, 0.9), 0.0, 1, 0.9, 0.9, 0.18, Color(0.8, 0.83, 0.84)],
	"manta": [Color(0.06, 0.08, 0.12), Color(0.93, 0.94, 0.95), 0.0, 2, 1.1, 1.4, 0.9, Color(0.84, 0.86, 0.88)],
	"shark": [Color(0.42, 0.47, 0.52), Color(0.94, 0.95, 0.96), 0.0, 0, 0.35, 2.4, 1.1, Color(0.88, 0.9, 0.92)],
	"turtle": [Color(0.3, 0.32, 0.27), Color(0.9, 0.85, 0.66), 0.0, 3, 0.25, 1.6, 0.0, Color(0.5, 0.4, 0.22)],
	"dolphin": [Color(0.47, 0.52, 0.58), Color(0.93, 0.92, 0.93), 0.0, 1, 0.22, 3.0, 1.6, Color(0.27, 0.31, 0.37)],
	"octopus": [Color(0.66, 0.24, 0.17), Color(0.96, 0.7, 0.58), 0.0, 4, 0.55, 0.7, 0.0, Color(0.98, 0.86, 0.78)],
}

static var _creature_mat: ShaderMaterial
static var _fish_mat: ShaderMaterial
static var _jelly_mat: ShaderMaterial


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "SeaLife"
	parent.add_child(root)
	var animator := SceneryAnimator.new()
	animator.name = "Animator"
	root.add_child(animator)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	_schools(track, root, animator, rng)
	_big(track, root, animator, rng)
	_octopus(track, root)
	_jellyfish(track, root, rng)


static func creature_material() -> ShaderMaterial:
	if _creature_mat == null:
		_creature_mat = ShaderMaterial.new()
		_creature_mat.shader = load("res://shaders/track/sea_creature.gdshader")
	return _creature_mat


## Um bicho grande: nó (o que anda) com o modelo escalado dentro, material toon animado com a cor e o
## nado dele. Nulo se o modelo não existir.
static func creature(root: Node3D, kind: String, scale: float, phase: float, shadows := false) -> Node3D:
	var path := MODELS + kind + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var holder := Node3D.new()
	# (nome único e legível: nomes repetidos viram "@Node3D@…")
	holder.name = "%s%d" % [kind.capitalize().replace(" ", ""), root.get_child_count()]
	root.add_child(holder)
	var model := (load(path) as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * scale
	holder.add_child(model)
	var look: Array = LOOK[kind]
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = creature_material()
		mi.set_instance_shader_parameter("top_color", look[0])
		mi.set_instance_shader_parameter("belly_color", look[1])
		mi.set_instance_shader_parameter("accent_color", look[7])
		mi.set_instance_shader_parameter("spots", look[2])
		mi.set_instance_shader_parameter("mode", float(look[3]))
		mi.set_instance_shader_parameter("amp", float(look[4]) / scale)
		mi.set_instance_shader_parameter("freq", look[5])
		mi.set_instance_shader_parameter("wave", float(look[6]) * scale)
		mi.set_instance_shader_parameter("phase", phase)
		mi.visibility_range_end = VISIBILITY
		mi.visibility_range_end_margin = 60.0
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return holder


# ---------------------------------------------------------------------------
# Rotas fora do tubo
# ---------------------------------------------------------------------------
## Pontos de uma elipse (órbita do add_blimp).
static func _ellipse(center: Vector3, radii: Vector2, n := 20) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in n:
		var a := TAU * k / n
		out.append(center + Vector3(cos(a) * radii.x, 0.0, sin(a) * radii.y))
	return out


## Pontos do desenho que um bando faz (o mesmo do add_flock: x = cos a, z = sen(0,8 a + 1,3)).
static func _lissajous(center: Vector3, radii: Vector2, n := 40) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in n:
		var a := 5.0 * TAU * k / n
		out.append(center + Vector3(cos(a) * radii.x, 0.0, sin(a * 0.8 + 1.3) * radii.y))
	return out


static func _line(a: Vector3, b: Vector3, n := 20) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in n + 1:
		out.append(a.lerp(b, float(k) / n))
	return out


## A rota (pontos, oscilando ±swing m na altura) não entra no tubo, não passa da superfície e não
## atravessa o leito nem as montanhas, para um bicho (ou bando) de meia-altura `size` e meia-largura
## `width` (a mesma se negativa: os bandos são bem mais largos que altos).
static func _route_ok(track: RaceTrack, pts: Array[Vector3], swing: float, size: float, width := -1.0) -> bool:
	var water := track.layout.water_level
	var w := size if width < 0.0 else width
	for pt in pts:
		if pt.y + swing + size > water - 1.0:
			return false
		if pt.y - swing - size < SeaFloor.ground(track, pt.x, pt.z) + 1.0:
			return false
		# (por cima dos vulcões, naufrágios e ruínas do leito)
		if pt.y - swing - size < SeaFloor.claim_top(pt.x, pt.z, w) + 1.0:
			return false
		for dy: float in [-swing, 0.0, swing]:
			if SeaTube.blocked(track, pt + Vector3.UP * dy, w + 2.0):
				return false
	return true


## Rota de ida e volta em linha reta ao lado da pista: começa entre s_range.x e s_range.y, com
## `length` m, a lat m da borda do tubo (dos dois lados) e above m acima da pista, para um bicho de
## meia-altura `size`. [a, b, para fora da pista] ou [] se não achar.
static func _pass_route(track: RaceTrack, rng: RandomNumberGenerator, s_range: Vector2, length: Vector2, lat: Vector2,
		above: Vector2, size: float, tries: int) -> Array:
	var p := track.path
	var water := track.layout.water_level
	for t in tries:
		var s0 := rng.randf_range(s_range.x, s_range.y)
		var s1 := s0 + rng.randf_range(length.x, length.y)
		var i0 := p.index_at(s0)
		# Do lado livre: arquibancadas e boxes (dentro do tubo) esconderiam o bicho de quem passa; com os
		# dois lados ocupados, outra rota
		var room := Vector2.ZERO
		var busy := Vector2.ZERO
		for u in 9:
			var j := p.index_at(lerpf(s0, s1, u / 8.0))
			room = Vector2(maxf(room.x, SeaTube.clearance(track, j, 1)), maxf(room.y, SeaTube.clearance(track, j, -1)))
			busy = Vector2(maxf(busy.x, _occupied(track, j, 1)), maxf(busy.y, _occupied(track, j, -1)))
		if busy.x > 6.0 and busy.y > 6.0:
			continue
		var side := 1 if rng.randf() < 0.5 else -1
		if (busy.x > 6.0) != (busy.y > 6.0):
			side = 1 if busy.x <= 6.0 else -1
		var off := (room.x if side > 0 else room.y) + rng.randf_range(lat.x, lat.y)
		var a := p.frame_at(s0, side * off, 0.0).origin
		var b := p.frame_at(s1, side * off, 0.0).origin
		a.y = minf(p.height_at(s0) + rng.randf_range(above.x, above.y), water - size - 6.0)
		b.y = a.y
		# (só trechos quase retos: numa curva a reta se afasta do tubo ou corta para perto dele)
		var straight := true
		for u: float in [0.2, 0.4, 0.5, 0.6, 0.8]:
			var d := absf(p.project(a.lerp(b, u), true, false).y)
			if d < off - 3.0 or d > off + 10.0:
				straight = false
				break
		if not straight:
			continue
		if _route_ok(track, _line(a, b, 30), 4.0, size):
			return [a, b, p.lefts[i0] * side]
	return []


## Quanto as construções do lado `side` (arquibancadas, boxes) passam da faixa comum ao lado da pista.
static func _occupied(track: RaceTrack, i: int, side: int) -> float:
	var plain := track.path.half_width(i, side) + track.barrier[RaceTrack._si(side)][i] + 7.0
	return track.structure_extent(i, side) - plain


## Procura uma órbita perto de s0 (±reach): centro a lat.x..lat.y m da pista (dos dois lados), a
## above.x..above.y m acima dela, raios entre r_min e r_max, para um bicho (ou bando) de meia-altura
## `size` e meia-largura `width` (_route_ok). [centro, raios] ou [] se não achar.
static func _find_orbit(track: RaceTrack, rng: RandomNumberGenerator, s0: float, reach: float, lat: Vector2, above: Vector2,
		r_min: Vector2, r_max: Vector2, swing: float, size: float, flock := false, tries := 30, width := -1.0) -> Array:
	var p := track.path
	for t in tries:
		var s := s0 + rng.randf_range(-reach, reach)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var center := p.frame_at(s, side * rng.randf_range(lat.x, lat.y), 0.0).origin
		center.y = minf(p.height_at(s) + rng.randf_range(above.x, above.y), track.layout.water_level - swing - size - 2.0)
		var radii := Vector2(rng.randf_range(r_min.x, r_max.x), rng.randf_range(r_min.y, r_max.y))
		var pts := _lissajous(center, radii) if flock else _ellipse(center, radii)
		# Por cima das ruínas, naufrágios e vulcões do leito (SeaFloor.claim): sobe o que precisar, até
		# perto da superfície (senão quase nenhum bando grande achava lugar nos trechos abertos)
		var floor_top := -INF
		for pt in pts:
			floor_top = maxf(floor_top, SeaFloor.claim_top(pt.x, pt.z, size if width < 0.0 else width))
		if floor_top + swing + size + 1.5 > center.y:
			center.y = minf(floor_top + swing + size + 1.5, track.layout.water_level - swing - size - 2.0)
			pts = _lissajous(center, radii) if flock else _ellipse(center, radii)
		if _route_ok(track, pts, swing, size, width):
			return [center, radii]
	return []


static func _big(track: RaceTrack, root: Node3D, animator: SceneryAnimator, rng: RandomNumberGenerator) -> void:
	var p := track.path
	var water := track.layout.water_level
	# (um s ao acaso nos trechos abertos)
	var open := func() -> float: return SeaCanyon.random_open_s(track, rng)
	# Raias-manta: dando voltas ao lado do tubo (vistas através do vidro)
	for k in 7:
		var o := _find_orbit(track, rng, open.call(), 120.0, Vector2(50, 160), Vector2(8, 18), Vector2(40, 30), Vector2(90, 70), 6.0, 0.6,
			false, 40)
		var m := creature(root, "manta", 1.0 + rng.randf() * 0.5, rng.randf() * TAU, true) if not o.is_empty() else null
		if m:
			animator.add_blimp(m, o[0], o[1], rng.randf_range(5.0, 7.0) * (1.0 if rng.randf() < 0.5 else -1.0))
			m.set_meta("at", o[0])
	# Baleias grandes (34 a 39 m) passando junto do tubo. Um grupo (mãe, outra adulta e o filhote) indo e
	# voltando ao lado da Ponte do Abismo
	var whales := _pass_route(track, rng, Vector2(2950.0, 3450.0), Vector2(110.0, 170.0), Vector2(8.0, 16.0), Vector2(5.0, 11.0),
		WHALE_SIZE * 2.0, 120)
	if whales.is_empty():
		push_warning("SeaLife: sem lugar para o grupo de baleias do abismo")
	else:
		var along: Vector3 = (whales[1] - whales[0]).normalized()
		var out: Vector3 = whales[2]
		# (a outra adulta atrás e mais por fora; o filhote colado na mãe, um pouco abaixo)
		var offsets := [Vector3.ZERO, -along * 48.0 + out * 12.0 + Vector3.DOWN * 2.0, -along * 14.0 + out * 7.0 + Vector3.DOWN * 4.0]
		var scales := [2.0, 1.7, 0.9]
		for k in offsets.size():
			if k > 0 and not _route_ok(track, _line(whales[0] + offsets[k], whales[1] + offsets[k]), 4.0, WHALE_SIZE * scales[k]):
				continue
			var w := creature(root, "whale", scales[k], k * 0.7, true)
			if w:
				animator.add_blimp_pass(w, whales[0] + offsets[k], whales[1] + offsets[k], 4.0, 0.2)
				w.set_meta("at", (whales[0] + whales[1]) * 0.5 + offsets[k])
	# A maior e mais três nos outros trechos abertos, também junto do tubo
	var near_whales := 0
	for t in 30:
		if near_whales >= 4:
			break
		var s0 := SeaCanyon.random_open_s(track, rng)
		var sc := 2.3 if near_whales == 0 else rng.randf_range(1.8, 2.2)
		var route := _pass_route(track, rng, Vector2(s0, s0), Vector2(120.0, 240.0), Vector2(8.0, 26.0), Vector2(4.0, 13.0),
			WHALE_SIZE * sc, 16)
		var w := creature(root, "whale", sc, rng.randf() * TAU, true) if not route.is_empty() else null
		if w:
			animator.add_blimp_pass(w, route[0], route[1], rng.randf_range(3.5, 5.0), rng.randf())
			w.set_meta("at", (route[0] + route[1]) * 0.5)
			near_whales += 1
	# Tubarões
	for k in 7:
		var o := _find_orbit(track, rng, open.call(), 150.0, Vector2(40, 140), Vector2(4, 14), Vector2(30, 25), Vector2(70, 55), 6.0, 0.8,
			false, 40)
		var sh := creature(root, "shark", rng.randf_range(0.9, 1.3), rng.randf() * TAU) if not o.is_empty() else null
		if sh:
			animator.add_blimp(sh, o[0], o[1], rng.randf_range(7.0, 9.0))
			sh.set_meta("at", o[0])
	# Tartarugas
	for k in 7:
		var o := _find_orbit(track, rng, open.call(), 150.0, Vector2(30, 110), Vector2(3, 10), Vector2(15, 12), Vector2(35, 28), 6.0, 0.6,
			false, 40)
		var tt := creature(root, "turtle", rng.randf_range(1.2, 1.6), rng.randf() * TAU) if not o.is_empty() else null
		if tt:
			animator.add_blimp(tt, o[0], o[1], rng.randf_range(2.0, 3.0))
			tt.set_meta("at", o[0])
	# Golfinhos: dois grupos de seis andando juntos (como um bando)
	for g in 2:
		# (o grupo: ±2 m de altura e ±8 m de largura, mais o tamanho de um golfinho)
		var o2 := _find_orbit(track, rng, open.call(), 250.0, Vector2(80, 240), Vector2(8, 16), Vector2(40, 30), Vector2(90, 70), 6.0, 3.5,
			true, 80, 10.0)
		if o2.is_empty():
			continue
		var pod := Node3D.new()
		pod.name = "Dolphins%d" % g
		root.add_child(pod)
		pod.set_meta("at", o2[0])
		for k in 6:
			var d := creature(pod, "dolphin", rng.randf_range(0.9, 1.1), k * 1.1)
			if d:
				d.position = Vector3(rng.randf_range(-6, 6), rng.randf_range(-2, 2), rng.randf_range(-8, 8))
		animator.add_flock(pod, o2[0], o2[1], 11.0, 0.5)


## Polvo gigante enroscado numa coluna quebrada, por fora da Curva do Polvo.
static func _octopus(track: RaceTrack, root: Node3D) -> void:
	var p := track.path
	var s := 835.0
	var i := p.index_at(s)
	var side := 1
	var d := SeaTube.clearance(track, i, side) + 16.0
	var base := p.frame_at(s, side * d, 0.0).origin
	base.y = SeaFloor.ground(track, base.x, base.z)
	var mb := MeshBuilder.new()
	var top := p.points[i].y + 6.0 - base.y
	# (sem o musgo no alto da coluna do polvo: atravessaria a membrana dele)
	AtlantisRuins.column(mb, base, top, 1.4, 0.0, AtlantisRuins.STONE, false)
	AtlantisRuins.column(mb, base + p.tangents[i] * 9.0 + Vector3.DOWN * 0.5, top * 0.6, 1.2, 0.4)
	var mi := MeshInstance3D.new()
	mi.name = "OctopusColumn"
	mi.mesh = mb.commit(null, TrackMaterials.sea_stone("ruins", false, {}))
	root.add_child(mi)
	var octo := creature(root, "octopus", 2.4, 0.0, true)
	if octo:
		var to_track := p.points[i] - base
		to_track.y = 0.0
		octo.global_transform = Transform3D(Basis.looking_at(-to_track.normalized()), base + Vector3.UP * (top - 2.0))


# ---------------------------------------------------------------------------
# Cardumes
# ---------------------------------------------------------------------------
static func _schools(track: RaceTrack, root: Node3D, animator: SceneryAnimator, rng: RandomNumberGenerator) -> void:
	if _fish_mat == null:
		_fish_mat = ShaderMaterial.new()
		_fish_mat.shader = load("res://shaders/track/fish.gdshader")
	var mesh := _fish_mesh()
	var p := track.path
	for f in 24:
		var count := rng.randi_range(30, 70)
		var spread := rng.randf_range(5.0, 11.0)
		var color := float(rng.randi() % 4) / 3.0
		var transforms: Array[Transform3D] = []
		var data: Array[Color] = []
		for k in count:
			var offset := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5), rng.randf_range(-1, 1)) * spread
			var s := rng.randf_range(0.7, 1.3)
			transforms.append(Transform3D(Basis().scaled(Vector3(s, s, s)), offset))
			data.append(Color(rng.randf(), rng.randf(), color, 0.0))
		var s0 := SeaCanyon.random_open_s(track, rng) if f % 5 != 0 else rng.randf() * p.length
		# (o cardume: ±0,5 spread de altura e ±spread de largura, mais o vaivém dos peixes)
		var o := _find_orbit(track, rng, s0, 100.0, Vector2(35, 200), Vector2(4, 18), Vector2(18, 14),
			Vector2(55, 42), 6.0, spread * 0.5 + 1.5, true, 60, spread + 2.0)
		if o.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = count
		mm.buffer = Grandstands.pack_buffer(transforms, data)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "School%d" % f
		mmi.multimesh = mm
		mmi.material_override = _fish_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = VISIBILITY
		mmi.custom_aabb = AABB(Vector3.ONE * -(spread + 4.0), Vector3.ONE * (spread + 4.0) * 2.0)
		root.add_child(mmi)
		animator.add_flock(mmi, o[0], o[1], rng.randf_range(5.0, 9.0), rng.randf() * TAU)


## Peixinho de ~0,56 m (frente em +Z): corpo fusiforme alto e achatado dos lados (anéis elípticos),
## cauda em forquilha, nadadeira dorsal e as peitorais. COLOR.r = peso da cauda; COLOR.g = ventre.
static func _fish_mesh() -> ArrayMesh:
	return fish_builder().commit()


## As peças do peixinho (escala `k`), para quem quiser acrescentar (os peixes-voadores ganham asas).
static func fish_builder(k := 1.0) -> MeshBuilder:
	var mb := MeshBuilder.new()
	const SIDES := 7
	# Anéis ao longo do corpo: z, meia-largura, meia-altura, centro em y (do focinho ao pedúnculo)
	var rings := [[0.2, 0.024, 0.04, -0.005], [0.12, 0.04, 0.082, 0.0], [0.03, 0.045, 0.098, 0.004],
		[-0.06, 0.035, 0.074, 0.004], [-0.13, 0.017, 0.034, 0.002], [-0.165, 0.009, 0.022, 0.0]]
	var nose := Vector3(0, -0.008, 0.265) * k
	var ring_pts: Array[PackedVector3Array] = []
	for r: Array in rings:
		var row := PackedVector3Array()
		for j in SIDES:
			var a := TAU * j / SIDES
			row.append(Vector3(cos(a) * float(r[1]), float(r[3]) + sin(a) * float(r[2]), float(r[0])) * k)
		ring_pts.append(row)
	var white := Color.WHITE
	for j in SIDES:
		var j1 := (j + 1) % SIDES
		var a0 := ring_pts[0][j]
		var a1 := ring_pts[0][j1]
		mb.tri(nose, a1, a0, white, (a0 + a1) * 0.5 - nose * 0.5)
		for r in rings.size() - 1:
			var p00 := ring_pts[r][j]
			var p01 := ring_pts[r][j1]
			var p10 := ring_pts[r + 1][j]
			var p11 := ring_pts[r + 1][j1]
			var out := (p00 + p01 + p10 + p11) * 0.25
			out = Vector3(out.x, out.y, 0.0)
			mb.quad(p00, p01, p11, p10, white, out)
	# Cauda em forquilha (dois lobos e o entalhe no meio)
	var base := Vector3(0, 0, -0.165) * k
	var top := Vector3(0, 0.1, -0.31) * k
	var bottom := Vector3(0, -0.095, -0.3) * k
	var notch := Vector3(0, 0.0, -0.25) * k
	mb.tri(base, top, notch, white, Vector3.RIGHT)
	mb.tri(base, notch, bottom, white, Vector3.RIGHT)
	# Dorsal e peitorais
	mb.tri(Vector3(0, 0.09, 0.09) * k, Vector3(0, 0.155, -0.02) * k, Vector3(0, 0.07, -0.08) * k, white, Vector3.RIGHT)
	for side: float in [1.0, -1.0]:
		mb.tri(Vector3(side * 0.04, -0.02, 0.1) * k, Vector3(side * 0.09, -0.05, 0.02) * k, Vector3(side * 0.035, -0.04, 0.05) * k,
			white, Vector3(side, -0.3, 0.0))
	# Peso da cauda pela posição (de 0 na frente a 1 na ponta da cauda) e o ventre (embaixo da linha do
	# meio do corpo)
	for v in mb.verts.size():
		var q := mb.verts[v] / k
		var w := clampf((0.05 - q.z) / 0.35, 0.0, 1.0)
		var belly := smoothstep(0.0, -0.05, q.y) if absf(q.x) > 0.001 or q.z > -0.17 else 0.0
		mb.colors[v] = Color(w, belly, 1.0)
	return mb


# ---------------------------------------------------------------------------
# Águas-vivas
# ---------------------------------------------------------------------------
static func _jellyfish(track: RaceTrack, root: Node3D, rng: RandomNumberGenerator) -> void:
	if _jelly_mat == null:
		_jelly_mat = ShaderMaterial.new()
		_jelly_mat.shader = load("res://shaders/track/jellyfish.gdshader")
	var mesh := _jelly_mesh()
	var p := track.path
	var water := track.layout.water_level
	var xfs: Array[Transform3D] = []
	var data: Array[Color] = []
	for cluster: Array in [[3000.0, -1], [3200.0, 1], [3420.0, -1], [4450.0, 1], [180.0, -1], [1620.0, -1], [2880.0, 1],
			[3980.0, -1], [900.0, 1]]:
		var hue := rng.randf()
		for k in 34:
			var s: float = cluster[0] + rng.randf_range(-70.0, 70.0)
			var i := p.index_at(s)
			var side: int = cluster[1]
			var lat := side * (p.half_width(i, side) + rng.randf_range(10.0, 110.0))
			var pos := p.frame_at(s, lat, 0.0).origin
			var bed := SeaFloor.ground(track, pos.x, pos.z)
			if bed + 5.0 > water - 4.0:
				continue
			pos.y = rng.randf_range(bed + 5.0, water - 4.0)
			# Fora do tubo (os carros correm no seco), da estrutura embaixo dele e da rocha do cânion
			if SeaTube.blocked(track, pos, 4.0) or SeaCanyon.in_rock(track, pos, 2.0):
				continue
			var sc := rng.randf_range(0.8, 2.2)
			xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), pos))
			data.append(Color(rng.randf(), fposmod(hue + rng.randf_range(-0.15, 0.15), 1.0), 0.0, 0.0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	mm.buffer = Grandstands.pack_buffer(xfs, data)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Jellyfish"
	mmi.multimesh = mm
	# (as posições também em metadado: sem placa de vídeo a MultiMesh não as guarda)
	mmi.set_meta("points", CityProps.origins(xfs))
	mmi.material_override = _jelly_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


## Água-viva de ~1,2 m: sino em domo com a borda levemente aberta e recortada em lóbulos, quatro
## braços orais largos e franzidos no meio e dezesseis tentáculos finos saindo da borda. COLOR.r = 0
## no sino e até 1 na ponta dos braços e tentáculos; COLOR.g = 1 na borda do sino.
static func _jelly_mesh() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var prof := PackedVector2Array()
	for k in 10:
		var t := k / 9.0
		var a := t * PI * 0.5
		# (a borda abre um pouco para fora, como uma saia)
		prof.append(Vector2(cos(a) * 0.6 + 0.05 * pow(1.0 - t, 3.0), sin(a) * 0.45 - 0.04 * pow(1.0 - t, 2.0)))
	mb.lathe(Transform3D(Basis(), Vector3.ZERO), prof, Color(0, 0, 1), 20)
	# Borda em lóbulos e mais clara
	for v in mb.verts.size():
		var q := mb.verts[v]
		var y := q.y
		if y < 0.03:
			var a := atan2(q.z, q.x)
			var lobe := 1.0 + 0.05 * absf(sin(a * 8.0))
			mb.verts[v] = Vector3(q.x * lobe, y, q.z * lobe)
		mb.colors[v] = Color(0.0, 1.0 - smoothstep(-0.05, 0.12, y), 1.0)
	# Braços orais: fitas largas franzidas (ondulando de lado) descendo do meio
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		var out := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-sin(a), 0.0, cos(a))
		var rows := 9
		for r in rows:
			var t0 := float(r) / rows
			var t1 := float(r + 1) / rows
			var c0 := out * (0.06 + 0.08 * t0) + Vector3.DOWN * (0.05 + t0 * 1.7) + side * sin(t0 * 9.0) * 0.06
			var c1 := out * (0.06 + 0.08 * t1) + Vector3.DOWN * (0.05 + t1 * 1.7) + side * sin(t1 * 9.0) * 0.06
			var w0 := lerpf(0.13, 0.05, t0)
			var w1 := lerpf(0.13, 0.05, t1)
			var start := mb.verts.size()
			mb.quad(c0 - side * w0, c0 + side * w0, c1 + side * w1, c1 - side * w1, Color(t0, 0, 1), out)
			for v in range(start, mb.verts.size()):
				mb.colors[v] = Color(clampf(-mb.verts[v].y / 1.75, 0.0, 1.0) * 0.8, 0.15, 1.0)
	# Tentáculos finos saindo da borda, de comprimentos diferentes
	for k in 16:
		var a := TAU * k / 16.0
		var base := Vector3(cos(a), 0.0, sin(a)) * 0.6
		var side := Vector3(-sin(a), 0.0, cos(a)) * 0.022
		var length := 2.4 + 0.8 * absf(sin(k * 2.3))
		var rows := 6
		for r in rows:
			var t0 := float(r) / rows
			var t1 := float(r + 1) / rows
			var y0 := Vector3.DOWN * (t0 * length) - base * 0.12 * t0
			var y1 := Vector3.DOWN * (t1 * length) - base * 0.12 * t1
			var start := mb.verts.size()
			mb.quad(base + y0 - side, base + y0 + side, base + y1 + side, base + y1 - side, Color(t0, 0, 1), Vector3(cos(a), 0, sin(a)))
			for v in range(start, mb.verts.size()):
				mb.colors[v] = Color(clampf(-mb.verts[v].y / length, 0.0, 1.0), 0.0, 1.0)
	return mb.commit()
