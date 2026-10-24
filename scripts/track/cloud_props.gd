class_name CloudProps
extends RefCounted
## Enfeites da beira da pista fofa nas nuvens (Rainbow Raceway):
##   * placas de madeira-doce com coração no alto e tábuas em seta, com recados fofos (SIGNS);
##   * o letreiro "RAINBOW RACEWAY" numa nuvem perto da largada e placas de nome nas ilhas grandes;
##   * o Mirante na Reta do Mirante: varanda sobre as nuvens com binóculos de moeda, bancos, vasos e
##     um poste (de frente para a espiral e a Torre de Algodão-Doce);
##   * caixas de presente de vidro com um coração dentro flutuando e girando sobre a pista (GIFTS);
##   * cachos de balões de coração e de bolinha presos nas barreiras, balançando;
##   * estrelas grandes acesas girando no ar em volta da pista.
## Nada tem colisão.

const FONT := "res://assets/fonts/neon/Bungee-Regular.ttf"
const SCRIPT_FONT := "res://assets/fonts/neon/Pacifico-Regular.ttf"
const TEXT := Color(0.38, 0.2, 0.52)
## Placas: [s, lado (+1 esquerda, -1 direita), linhas]. Se o lugar estiver ocupado, vai para o outro lado
## ou um pouco para a frente.
const SIGNS := [
	[95.0, 1, ["BEM-VINDO À", "RAINBOW", "RACEWAY"]],
	[330.0, 1, ["CURVA DO", "URSINHO"]],
	[720.0, -1, ["GENTILEZA", "GERA", "GENTILEZA"]],
	[1120.0, -1, ["CASTELO DE", "ALGODÃO-DOCE"]],
	[1580.0, 1, ["TÚNEL DO", "ARCO-ÍRIS"]],
	[2140.0, -1, ["SORRIA!", "VOCÊ ESTÁ", "NAS NUVENS"]],
	[2560.0, -1, ["DEVAGAR", "NA ESPIRAL"]],
	[2920.0, 1, ["CUIDADO:", "FOFURA", "EXTREMA"]],
	[3100.0, -1, ["CACHOEIRAS", "ARCO-ÍRIS"]],
	[3390.0, 1, ["ABRACE", "UM URSINHO"]],
	[3800.0, 1, ["VOCÊ É", "INCRÍVEL!"]],
	[4020.0, 1, ["ÚLTIMA", "VOLTA?", "SÓ MAIS UMA!"]],
]
## Caixas de presente: s de cada fileira (quatro de lado a lado, no alto).
const GIFTS := [330.0, 1010.0, 1960.0, 3085.0, 3880.0]
const GIFT_HEIGHT := 6.8
## Balões: intervalo (m) entre os cachos (lados alternados).
const BALLOON_SPACING := 140.0
const MIRANTE_S := 2215.0


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "CloudProps"
	parent.add_child(root)
	var mb := MeshBuilder.new()
	var glow := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4321
	var signs := 0
	for sg: Array in SIGNS:
		if _signpost(track, root, mb, sg[0], sg[1], sg[2], rng):
			signs += 1
	_title(track, root, mb, glow, rng)
	_island_names(track, root, mb, rng)
	var mirante := _mirante(track, root, mb, glow, rng)
	CloudLook.add_mesh(root, "Props", mb.commit(null, CandyDecor.material()), null, 2500.0)
	if not glow.is_empty():
		CloudLook.add_mesh(root, "PropLights", glow.commit(null, CloudLook.glow(1.2, 2.8)))
	var gifts := _gifts(track, root, rng)
	var balloons := _balloons(track, root, rng)
	var stars := _stars(track, root, rng)
	root.set_meta("signs", signs)
	root.set_meta("mirante", mirante)
	root.set_meta("gifts", gifts)
	root.set_meta("balloons", balloons)
	root.set_meta("stars", stars)


static func _label(text: String, font_size: int, pixel: float, color := TEXT, font := FONT) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = load(font)
	label.font_size = font_size
	label.pixel_size = pixel
	label.outline_size = maxi(int(font_size * 0.12), 2)
	label.modulate = color
	label.outline_modulate = Color(1.0, 0.97, 1.0)
	label.shaded = false
	label.double_sided = false
	label.no_depth_test = false
	# Depois do contorno anime (prioridade 1, em tela cheia): senão as linhas do que está atrás passam por
	# cima das letras
	label.render_priority = 2
	label.visibility_range_end = 450.0
	return label


# ---------------------------------------------------------------------------
# Placas
# ---------------------------------------------------------------------------
## Placa em s, do lado `side` (ou do outro, ou alguns metros adiante, se ali estiver ocupado).
static func _signpost(track: RaceTrack, root: Node3D, mb: MeshBuilder, s: float, side: int, lines: Array, rng: RandomNumberGenerator) -> bool:
	var p := track.path
	var spot := Vector2.INF
	for tries in 8:
		var ss := s + tries * 9.0
		for sd: int in [side, -side]:
			if PlushFriends._free_spot(track, ss, sd):
				spot = Vector2(ss, sd)
				break
		if spot != Vector2.INF:
			break
	if spot == Vector2.INF:
		return false
	s = spot.x
	side = int(spot.y)
	var i := p.index_at(s)
	var back := p.half_width(i, side) + track.barrier[RaceTrack._si(side)][i] + TrackBarriers.CLOUD_THICK
	var at := p.frame_at(s, side * (back + 1.6)).origin
	var to_road := -p.lefts[i] * side
	var face := (to_road * 0.75 - p.tangents[i] * 0.66)
	face.y = 0.0
	face = face.normalized()
	var basis := Basis(Vector3.UP.cross(face).normalized(), Vector3.UP, face)
	var height := 2.2 + lines.size() * 0.75
	# Poste e coração no alto
	mb.cylinder(Transform3D(Basis(), at), 0.16, 0.13, height + 0.4, CloudLook.CREAM, 10)
	mb.blob(at + Vector3.UP * 0.15, Vector3(0.6, 0.3, 0.6), Color(1.0, 0.95, 0.99), 10, 5)
	CloudLook.slab(mb, CloudLook.heart(0.9), Transform3D(basis, at + Vector3.UP * (height + 0.75)), 0.22, CloudLook.HOT_PINK, Color.WHITE)
	# Tábuas em seta, alternando a ponta para um lado e para o outro
	for k in lines.size():
		var y := height - 0.2 - k * 0.75
		var width := 0.45 + 0.24 * (lines[k] as String).length()
		var dir := 1.0 if k % 2 == 0 else -1.0
		var poly := PackedVector2Array([Vector2(-width * 0.5, -0.29), Vector2(width * 0.5, -0.29), Vector2(width * 0.5 + 0.3, 0.0),
			Vector2(width * 0.5, 0.29), Vector2(-width * 0.5, 0.29)])
		if dir < 0.0:
			for q in poly.size():
				poly[q] = Vector2(-poly[q].x, poly[q].y)
		var col: Color = [CloudLook.PINK, CloudLook.LILAC, CloudLook.MINT, CloudLook.BABY_BLUE, CloudLook.BUTTER][(k + int(s)) % 5]
		var center := at + Vector3.UP * y + basis.x * dir * width * 0.12
		CloudLook.slab(mb, poly, Transform3D(basis, center), 0.1, col, Color.WHITE)
		var label := _label(lines[k], 44, 0.0075)
		root.add_child(label)
		label.global_transform = Transform3D(basis, center + face * 0.07)
	return true


## Letreiro "RAINBOW RACEWAY" numa nuvem grande perto da largada, do lado das arquibancadas, com um
## arco-íris atrás e corações dos lados.
static func _title(track: RaceTrack, root: Node3D, mb: MeshBuilder, glow: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var p := track.path
	# Depois da largada, do lado de fora dos boxes: quem está no grid vê lá na frente
	var s := 165.0
	var i := p.index_at(s)
	var side := -track.layout.pit_side
	var lat := side * (track.structure_extent(i, side) + 16.0)
	var at := p.frame_at(s, lat, 21.0).origin
	var face := p.position_at(-140.0) - at
	face.y = 0.0
	face = face.normalized()
	var basis := Basis(Vector3.UP.cross(face).normalized(), Vector3.UP, face)
	var xf := Transform3D(basis, at)
	CandyDecor.rainbow_arch(mb, xf * Transform3D(Basis(), Vector3(0, -6.0, -3.0)), 21.0, 1.4, 1.6, 36)
	for k in 26:
		var x := rng.randf_range(-17.0, 17.0)
		var y := rng.randf_range(-3.5, 3.5) * (1.0 - absf(x) / 22.0)
		var r := rng.randf_range(2.6, 4.4) * (1.0 - absf(x) / 34.0)
		# (atrás das letras: a nuvem é o fundo da placa)
		mb.blob(xf * Vector3(x, y, rng.randf_range(-4.5, -3.0)), Vector3(r * 1.2, r, r * 0.8), Color(1.0, 0.97, 1.0), 12, 8, 0.2)
	for sx: float in [-1.0, 1.0]:
		CloudLook.slab(mb, CloudLook.heart(4.0), xf * Transform3D(Basis(Vector3.FORWARD, sx * 0.25), Vector3(sx * 18.5, 3.0, 1.2)), 1.0,
			CloudLook.HOT_PINK, Color.WHITE)
		CloudLook.slab(glow, CloudLook.star(1.4, 0.48), xf * Transform3D(Basis(), Vector3(sx * 13.0, 6.2, 1.6)), 0.3, CloudLook.BUTTER)
	for line: Array in [["RAINBOW", 3.4], ["RACEWAY", -3.0]]:
		var label := _label(line[0], 220, 0.028, CloudLook.HOT_PINK)
		label.outline_size = 40
		label.visibility_range_end = 2500.0
		root.add_child(label)
		label.global_transform = Transform3D(basis, xf * Vector3(0, float(line[1]), 1.2))
	root.set_meta("title", at)


## Placas de nome nas ilhas grandes (nuvem com o nome escrito), na beirada virada para a pista.
static func _island_names(track: RaceTrack, root: Node3D, mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var names := {"castle": "CASTELO DE ALGODÃO-DOCE", "heart": "ILHA DO CORAÇÃO", "falls": "CACHOEIRAS ARCO-ÍRIS",
		"bears": "PIQUENIQUE DOS URSINHOS", "sweets": "ILHA DOS DOCES"}
	for id: String in names:
		var lm := CloudIslands.landmark(track, id)
		var pos: Vector3 = lm.pos
		var r: float = lm.radius
		var pr := track.path.project(pos, true, false)
		var q := track.path.position_at(pr.x)
		var face := q - pos
		face.y = 0.0
		face = face.normalized()
		var at := pos + face * (r * 0.92) + Vector3.UP * (CloudIslands.top_y(pos, r, 0.92) - pos.y + 3.6)
		var basis := Basis(Vector3.UP.cross(face).normalized(), Vector3.UP, face)
		var text: String = names[id]
		var w := text.length() * 0.95 + 2.0
		for k in int(w / 1.6):
			var x := -w * 0.5 + (k + 0.5) * 1.6
			mb.blob(at + basis.x * x + basis.z * -0.6 + Vector3.UP * rng.randf_range(-0.3, 0.3), Vector3(1.4, 1.3, 1.0) * rng.randf_range(0.9, 1.2),
				Color(1.0, 0.97, 1.0), 10, 6, 0.2)
		var label := _label(text, 96, 0.012, CloudLook.HOT_PINK)
		label.visibility_range_end = 1500.0
		root.add_child(label)
		label.global_transform = Transform3D(basis, at + face * 0.9)


# ---------------------------------------------------------------------------
# Mirante
# ---------------------------------------------------------------------------
## Varanda redonda sobre as nuvens, saindo de trás da barreira do lado da espiral: piso de glacê,
## grade cor-de-rosa na metade de fora, dois binóculos de moeda virados para a Torre de Algodão-Doce,
## dois bancos, vasos de flor, um poste e a placa com o nome virada para a pista.
static func _mirante(track: RaceTrack, root: Node3D, mb: MeshBuilder, glow: MeshBuilder, rng: RandomNumberGenerator) -> Vector3:
	var p := track.path
	var s := MIRANTE_S
	var tower := CloudIslands.landmark(track, "tower")
	var tpos: Vector3 = tower.pos
	var pr := p.project(tpos, true, false)
	var side := 1 if pr.y > 0.0 else -1
	var i := p.index_at(s)
	var back := p.half_width(i, side) + track.barrier[RaceTrack._si(side)][i] + TrackBarriers.CLOUD_THICK
	var radius := 6.5
	var center := p.frame_at(s, side * (back + radius + 0.6), -0.15).origin
	var out := p.lefts[i] * side
	out.y = 0.0
	out = out.normalized()
	var along := Vector3.UP.cross(out).normalized()
	var face := tpos - center
	face.y = 0.0
	face = face.normalized()
	var look := Basis(Vector3.UP.cross(face).normalized(), Vector3.UP, face)
	var obasis := Basis(along, Vector3.UP, out)
	# Piso e beirada de glacê
	mb.lathe(Transform3D(Basis(), center), PackedVector2Array([Vector2(radius * 0.7, -1.6), Vector2(radius, -0.6), Vector2(radius + 0.2, -0.2),
		Vector2(radius, 0.12), Vector2(0.0, 0.14)]), Color(1.0, 0.86, 0.93), 32)
	for k in 14:
		var a := TAU * k / 14.0
		mb.blob(center + Vector3(cos(a) * radius, -0.7, sin(a) * radius), Vector3(0.5, 0.9, 0.5), Color.WHITE, 8, 5)
	# Grade na metade de fora
	var base_a := atan2(out.z, out.x)
	var posts := 18
	for k in posts + 1:
		var a := base_a + PI * (float(k) / posts - 0.5) * 1.3
		var at := center + Vector3(cos(a), 0.0, sin(a)) * (radius - 0.3)
		mb.cylinder(Transform3D(Basis(), at + Vector3.UP * 0.12), 0.06, 0.06, 1.0, Color.WHITE, 6, false)
		mb.blob(at + Vector3.UP * 1.18, Vector3.ONE * 0.1, CloudLook.HOT_PINK, 6, 4)
		if k < posts:
			var a1 := base_a + PI * (float(k + 1) / posts - 0.5) * 1.3
			var b := center + Vector3(cos(a1), 0.0, sin(a1)) * (radius - 0.3)
			var dir := (b - at)
			var x := dir.normalized()
			mb.box(Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)).orthonormalized(), (at + b) * 0.5 + Vector3.UP * 1.1), Vector3(dir.length() + 0.05, 0.12, 0.12),
				CloudLook.HOT_PINK)
	# Binóculos de moeda (rosa), na beirada de fora, virados para a torre
	for sx: float in [-1.6, 1.6]:
		var at := center + along * sx + out * (radius * 0.6)
		var b := Transform3D(look, at)
		mb.cylinder(Transform3D(Basis(), at + Vector3.UP * 0.12), 0.32, 0.26, 0.15, CloudLook.HOT_PINK, 12)
		mb.cylinder(Transform3D(Basis(), at + Vector3.UP * 0.12), 0.09, 0.09, 1.05, Color(1.0, 0.75, 0.86), 8)
		mb.box(b * Transform3D(Basis(), Vector3(0, 1.28, 0)), Vector3(0.34, 0.42, 0.38), CloudLook.HOT_PINK)
		for ex: float in [-0.12, 0.12]:
			mb.cylinder(b * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(ex, 1.42, 0.12)), 0.1, 0.12, 0.35, Color(1.0, 0.55, 0.75), 12)
			glow.blob(b * Vector3(ex, 1.42, 0.48), Vector3.ONE * 0.08, Color(0.75, 0.9, 1.0), 8, 4)
		mb.blob(b * Vector3(0, 1.62, 0.0), Vector3(0.12, 0.08, 0.12), CloudLook.BUTTER, 8, 4)
	# Bancos (de frente para fora, encosto do lado da pista)
	for sx: float in [-3.3, 3.3]:
		var at := center + along * sx + out * 0.8
		for k in 3:
			mb.box(Transform3D(obasis, at + Vector3.UP * 0.5 + out * (k - 1) * 0.16), Vector3(1.8, 0.07, 0.14), CloudLook.PINK)
		for k in 3:
			mb.box(Transform3D(obasis * Basis(Vector3.RIGHT, 0.15), at + Vector3.UP * (0.75 + k * 0.17) - out * 0.27), Vector3(1.8, 0.12, 0.05),
				CloudLook.PINK)
		for lx: float in [-0.8, 0.8]:
			mb.box(Transform3D(obasis, at + along * lx + Vector3.UP * 0.25), Vector3(0.08, 0.5, 0.4), Color.WHITE)
	# Vasos de flor junto da grade e o poste com coração
	for k in 4:
		var a := base_a + PI * (k / 3.0 - 0.5) * 1.1
		var at := center + Vector3(cos(a), 0.0, sin(a)) * (radius - 1.1)
		mb.cylinder(Transform3D(Basis(), at + Vector3.UP * 0.12), 0.32, 0.38, 0.5, CloudLook.LILAC, 10)
		mb.blob(at + Vector3.UP * 0.75, Vector3(0.45, 0.35, 0.45), CloudLook.pick(rng, [CloudLook.HOT_PINK, CloudLook.BUTTER, Color.WHITE]), 8, 5)
	var lamp_at := center + along * 4.8 + out * 1.6
	mb.cylinder(Transform3D(Basis(), lamp_at), 0.08, 0.07, 3.2, Color.WHITE, 8)
	CloudLook.slab(glow, CloudLook.heart(0.7), Transform3D(look, lamp_at + Vector3.UP * 3.55), 0.3, Color(1.0, 0.7, 0.86))
	# Placa com o nome, na beirada do lado da pista, virada para quem passa
	var sign_at := center - out * (radius - 1.2)
	for sx: float in [-3.6, 3.6]:
		mb.cylinder(Transform3D(Basis(), sign_at + along * sx), 0.1, 0.1, 3.2, Color.WHITE, 8)
	mb.box(Transform3D(Basis(along, Vector3.UP, -out), sign_at + Vector3.UP * 2.75), Vector3(7.8, 0.9, 0.12), CloudLook.PINK)
	var label := _label("MIRANTE DAS NUVENS", 56, 0.0085)
	root.add_child(label)
	label.global_transform = Transform3D(Basis(-along, Vector3.UP, -out), sign_at + Vector3.UP * 2.75 - out * 0.08)
	return center


static func _circle(r: float, n := 12) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n:
		out.append(Vector2(cos(TAU * k / n), sin(TAU * k / n)) * r)
	return out


# ---------------------------------------------------------------------------
# Caixas de presente, balões e estrelas
# ---------------------------------------------------------------------------
static func _gifts(track: RaceTrack, root: Node3D, rng: RandomNumberGenerator) -> int:
	var p := track.path
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	for s: float in GIFTS:
		if HeartArches._blocked(track, s):
			continue
		var i := p.index_at(s)
		var w := p.width_left[i] + p.width_right[i]
		for k in 4:
			var lat := -p.width_right[i] + w * (k + 0.5) / 4.0
			var at := p.frame_at(s, lat, GIFT_HEIGHT).origin
			xfs.append(Transform3D(Basis().scaled(Vector3.ONE * 2.2), at))
			cols.append(CloudLook.RAINBOW[(k + int(s)) % CloudLook.RAINBOW.size()])
	if xfs.is_empty():
		return 0
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var glass := ShaderMaterial.new()
	glass.shader = load("res://shaders/track/gift_box.gdshader")
	var solid := ShaderMaterial.new()
	solid.shader = load("res://shaders/track/gift_solid.gdshader")
	var heart := MeshBuilder.new()
	CloudLook.slab(heart, CloudLook.heart(0.55), Transform3D(Basis(), Vector3(0, -0.02, 0)), 0.22, Color(1.0, 0.42, 0.7))
	var ribbon := MeshBuilder.new()
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		var side := axis.cross(Vector3.UP)
		ribbon.box(Transform3D(Basis(side, Vector3.UP, axis), Vector3.ZERO), Vector3(0.12, 1.02, 1.02), Color.WHITE)
	ribbon.blob(Vector3(0, 0.55, 0), Vector3(0.18, 0.1, 0.18), Color.WHITE, 8, 4)
	var white: Array[Color] = []
	for c in cols:
		white.append(Color.WHITE)
	CloudLook.add_multimesh(root, "GiftBoxes", box, xfs, glass, 900.0, cols)
	CloudLook.add_multimesh(root, "GiftHearts", heart.commit(), xfs, solid, 900.0, white)
	CloudLook.add_multimesh(root, "GiftRibbons", ribbon.commit(), xfs, solid, 900.0, cols)
	return xfs.size()


## Cachos de balões (corações e bolinhas em cordões) presos no alto das barreiras.
static func _balloons(track: RaceTrack, root: Node3D, rng: RandomNumberGenerator) -> int:
	var p := track.path
	var mesh := _balloon_bunch()
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var n := int(p.length / BALLOON_SPACING)
	for k in n:
		var s := (k + 0.6) * p.length / n
		var side := 1 if k % 2 == 1 else -1
		if not PlushFriends._free_spot(track, s, side):
			side = -side
			if not PlushFriends._free_spot(track, s, side):
				continue
		var i := p.index_at(s)
		var d := track.barrier[RaceTrack._si(side)][i] + TrackBarriers.CLOUD_THICK * 0.5
		var at := track.edge_point(i, side, d, TrackBarriers.CLOUD_HEIGHT + 0.3)
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.2)), at))
		cols.append(Color.WHITE)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/balloon.gdshader")
	mat.set_shader_parameter("height", 5.0)
	CloudLook.add_multimesh(root, "Balloons", mesh, xfs, mat, 700.0, cols)
	return xfs.size()


## Cacho de balões: sete balões (corações e bolinhas, cores do arco-íris) em cordões finos saindo de
## um laço em y = 0.
static func _balloon_bunch() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	mb.blob(Vector3.ZERO, Vector3(0.12, 0.08, 0.12), Color.WHITE, 8, 4)
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf_range(-0.2, 0.2)
		var spread := rng.randf_range(0.6, 1.3)
		var top := Vector3(cos(a) * spread, rng.randf_range(3.4, 4.8), sin(a) * spread)
		var col: Color = CloudLook.RAINBOW[k % CloudLook.RAINBOW.size()]
		# Cordão
		var dir := top.normalized()
		var x := dir.cross(Vector3.FORWARD).normalized()
		mb.cylinder(Transform3D(Basis(x, dir, x.cross(dir)).orthonormalized(), Vector3.ZERO), 0.012, 0.012, top.length() - 0.4, Color(1.0, 0.95, 0.98), 4, false)
		if k % 2 == 0:
			var face := Vector3(top.x, 0.0, top.z).normalized()
			var basis := Basis(Vector3.UP.cross(face).normalized(), Vector3.UP, face)
			_puffy_heart(mb, Transform3D(basis, top + Vector3.UP * 0.25), 0.95, col)
		else:
			mb.blob(top + Vector3.UP * 0.35, Vector3(0.42, 0.52, 0.42), col, 12, 8)
			mb.cylinder(Transform3D(Basis(), top - Vector3.UP * 0.2), 0.03, 0.07, 0.12, col, 6)
	return mb.commit()


## Coração estufado (balão): camadas do contorno encolhendo para a frente e para trás.
static func _puffy_heart(mb: MeshBuilder, xf: Transform3D, size: float, color: Color) -> void:
	var outline := CloudLook.heart(size, 32)
	var layers := 5
	var rows: Array = []
	for l in layers + 1:
		var a := PI * l / layers - PI * 0.5
		var z := sin(a) * size * 0.22
		var k := 0.35 + 0.65 * cos(a)
		var row: Array[Vector3] = []
		for q in outline:
			row.append(xf * Vector3(q.x * k, q.y * k, z))
		rows.append(row)
	var n := outline.size()
	var center := xf.origin
	for l in layers:
		var r0: Array[Vector3] = rows[l]
		var r1: Array[Vector3] = rows[l + 1]
		for q in n:
			var q1 := (q + 1) % n
			var nrm := (r0[q] + r0[q1] + r1[q] + r1[q1]) * 0.25 - center
			mb.quad(r0[q], r0[q1], r1[q1], r1[q], color, nrm)


## Estrelas grandes acesas girando no ar em volta da pista.
static func _stars(track: RaceTrack, root: Node3D, rng: RandomNumberGenerator) -> int:
	var p := track.path
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var n := 34
	for k in n:
		var s := (k + rng.randf()) * p.length / n
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var at := p.frame_at(s, side * rng.randf_range(28.0, 60.0), rng.randf_range(14.0, 34.0)).origin
		xfs.append(Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(1.6, 3.2)), at))
		cols.append(Color(1.0, 0.8, 0.22) if rng.randf() < 0.7 else Color(1.0, 0.55, 0.78))
	var mb := MeshBuilder.new()
	CloudLook.slab(mb, CloudLook.star(1.0, 0.48), Transform3D(), 0.35, Color.WHITE)
	var solid := ShaderMaterial.new()
	solid.shader = load("res://shaders/track/gift_solid.gdshader")
	solid.set_shader_parameter("spin", 0.5)
	solid.set_shader_parameter("bob", 0.8)
	CloudLook.add_multimesh(root, "FloatingStars", mb.commit(), xfs, solid, 2200.0, cols)
	return xfs.size()
