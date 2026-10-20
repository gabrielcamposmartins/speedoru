class_name AtlantisRuins
extends RefCounted
## As ruínas de Atlântida em volta da pista no fundo do mar, todas em pedra (sea_stone):
##  * o Templo de Poseidon por fora da Curva do Templo (escadaria, colunas, frontão e a estátua);
##  * colunatas dos dois lados da Avenida das Colunas (algumas quebradas, tambores caídos);
##  * o Portal de Atlântida, um arco gigante sobre a pista e o tubo de vidro;
##  * o Tridente do abismo: um tridente gigante de bronze e ouro fincado no fundo da fossa, por fora da
##    Chicane do Tridente (à esquerda de quem freia para ela), com as pontas logo abaixo da superfície;
##  * a muralha em arcos atrás das arquibancadas do anfiteatro (dois andares, como um coliseu);
##  * prédios em ruínas, torres e aquedutos (aqueduct: dois andares, contrafortes, o canal no alto,
##    pontas e vãos desabados) ao longe, sobre o leito (SeaFloor.ground), com lanternas quentes,
##    estandartes azuis com o tridente e as estátuas (.glb) onde houver.
## Os arcos (arcade) têm plinto e imposta nos pilares, aduelas salientes com a pedra de fecho, as
## faces de dentro dos vãos, cornija e as pontas fechadas. Cada peça ocupa o seu lugar do leito
## (SeaFloor.claim).
## Nada aqui tem colisão. Em pedaços espaciais (BUCKET m) com visibility range.

const STONE := Color(0.86, 0.83, 0.76)
const STONE_DARK := Color(0.66, 0.65, 0.62)
## Tijolo das aduelas dos arcos (alternado com a pedra clara).
const BRICK := Color(0.68, 0.4, 0.3)
const LANTERN := Color(1.0, 0.78, 0.42)
## Bronze das lanternas (cor forte: a pedra de Atlântida a mantém).
const LANTERN_BRONZE := Color(0.62, 0.43, 0.2)
const BUCKET := 300.0
const VISIBILITY := 1100.0
const PORTAL_S := 690.0
const PORTAL_CLEAR := 15.0
const AVENUE := Vector2(560.0, 760.0)
const TEMPLE_S := 487.0
## Caneluras do fuste das colunas.
const FLUTES := 12
## Tridente gigante: s (no miolo da Chicane do Tridente), lado (+1 esquerda) e distância além do tubo.
const TRIDENT := Vector3(3455.0, 1.0, 26.0)
## Estátuas (.glb gerados por blender/build_atlantis.py); as que não existirem são puladas.
const MODELS := "res://assets/track/atlantis_abyss/models/"

static var _banner_mat: ShaderMaterial
## Corais, musgo e algas presos nas ruínas (SeaReef).
static var _rng := RandomNumberGenerator.new()


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Ruins"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	_rng.seed = 7718
	var near := MeshBuilder.new()
	var lanterns := MeshBuilder.new()
	var banners := MeshBuilder.new()
	var statues: Array = []  # [modelo, Transform3D]
	_temple(track, near, banners, lanterns, statues)
	_avenue(track, near, banners, rng)
	_portal(track, near, banners, lanterns)
	_amphitheater_wall(track, near, banners, lanterns, statues)
	_commit(root, "Landmarks", near, lanterns, banners, true)
	_giant_trident(track, root)
	# Ao longe: por blocos espaciais
	var far := {}
	var spots := {}
	_background(track, far, rng, statues, spots)
	root.set_meta("background", spots)
	for key: Vector2i in far:
		var parts: Array = far[key]
		_commit(root, "Ruins_%d_%d" % [key.x, key.y], parts[0], parts[1], parts[2], false)
	place_statues(root, statues)


static func _commit(root: Node3D, node_name: String, mb: MeshBuilder, lanterns: MeshBuilder, banners: MeshBuilder,
		shadows: bool) -> void:
	if mb.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mb.commit(null, TrackMaterials.sea_stone("ruins", false, {"panel_size": 1.4, "grime_strength": 0.5,
		"moss_amount": 0.6, "coral_amount": 0.3, "no_outline": false}))
	if not lanterns.is_empty():
		lanterns.commit(mi.mesh as ArrayMesh, SkyDeck.glow(0.0, 1.4, 3.6))
	mi.visibility_range_end = VISIBILITY
	mi.visibility_range_end_margin = 80.0
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if not banners.is_empty():
		var bmi := MeshInstance3D.new()
		bmi.name = node_name + "Banners"
		bmi.mesh = banners.commit(null, banner_material())
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bmi.visibility_range_end = VISIBILITY
		root.add_child(bmi)


## O tridente gigante do abismo (TRIDENT), de bronze com pátina e as pontas de ouro
## (sea_bronze.gdshader): a haste com anéis saindo do fundo da fossa, a empunhadura, a travessa curva
## virada para a pista e as três pontas farpadas, a do meio mais alta, até 3 m da superfície; algas
## penduradas da travessa e musgo nas juntas. Ocupa o leito até o topo (os bichos não passam por ele).
static func _giant_trident(track: RaceTrack, root: Node3D) -> void:
	var p := track.path
	if TRIDENT.x > p.length:
		return
	var i := p.index_at(TRIDENT.x)
	var side := int(TRIDENT.y)
	var base := p.frame_at(TRIDENT.x, side * (SeaTube.clearance(track, i, side) + TRIDENT.z), 0.0).origin
	base.y = SeaFloor.ground(track, base.x, base.z) - 3.0
	var top := track.layout.water_level - 3.0
	if top - base.y < 30.0:
		return
	var mb := MeshBuilder.new()
	var bronze := SeaTube.METAL
	var gold := SeaTube.GOLD
	# (a travessa ao longo da pista: de quem chega o tridente aparece de frente)
	var along := p.tangents[i]
	along.y = 0.0
	along = along.normalized()
	var fork := top - 16.0
	var shaft := Vector3(base.x, base.y, base.z)
	mb.cylinder(Transform3D(Basis(), shaft), 1.6, 1.3, fork - base.y, bronze, 14)
	# Anéis a cada 12 m e a empunhadura (anéis juntos) logo abaixo da travessa
	var y := base.y + 10.0
	while y < fork - 4.0:
		mb.cylinder(Transform3D(Basis(), Vector3(shaft.x, y, shaft.z)), 1.95, 1.95, 0.9, gold if int(y) % 3 == 0 else bronze, 14)
		y += 12.0
	for k in 5:
		mb.cylinder(Transform3D(Basis(), Vector3(shaft.x, fork - 9.0 + k * 1.4, shaft.z)), 1.75, 1.75, 0.6, bronze * 0.85, 14)
	# Travessa curva (as pontas dos lados um pouco mais altas)
	var half := 8.5
	var prev := Vector3(shaft.x, fork, shaft.z) - along * half + Vector3.UP * 1.6
	for k in range(1, 9):
		var u := float(k) / 8.0
		var q := Vector3(shaft.x, fork, shaft.z) + along * lerpf(-half, half, u) + Vector3.UP * (1.6 * pow(2.0 * u - 1.0, 2.0))
		var dir := (q - prev).normalized()
		var x := dir.cross(Vector3.UP).normalized()
		mb.box(Transform3D(Basis(x, dir.cross(x).normalized(), dir), (prev + q) * 0.5), Vector3(1.9, 1.9, prev.distance_to(q) + 0.1), gold)
		prev = q
	mb.blob(Vector3(shaft.x, fork, shaft.z), Vector3(2.4, 1.6, 2.4), gold, 12, 6)
	# Três pontas farpadas
	for k in 3:
		var off := float(k - 1) * half
		var root_at := Vector3(shaft.x, fork + (1.6 if k != 1 else 0.0), shaft.z) + along * off
		var tip_y := top - (0.0 if k == 1 else 3.0)
		var length := tip_y - root_at.y - 4.0
		mb.cylinder(Transform3D(Basis(), root_at), 0.95, 0.75, length, gold, 10)
		var head := root_at + Vector3.UP * length
		mb.cylinder(Transform3D(Basis(), head), 1.3, 0.0, 4.0, gold, 10)
		# Farpas: duas lâminas abrindo para baixo nos lados da ponta (no plano do tridente)
		var n := along.cross(Vector3.UP).normalized()
		for s: float in [-1.0, 1.0]:
			mb.box(Transform3D(Basis().rotated(n, s * 0.55), head + along * s * 0.9 + Vector3.UP * 0.4), Vector3(0.45, 2.2, 0.35), gold)
	# Algas da travessa e musgo nas juntas (o SeaReef só aceita o que está debaixo d'água)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3455
	for k in 9:
		var at := Vector3(shaft.x, fork - 0.9, shaft.z) + along * rng.randf_range(-half, half)
		SeaReef.hang(at, rng.randf_range(2.0, 6.0), rng)
	SeaReef.moss(Vector3(shaft.x, fork + 1.4, shaft.z), 1.6, rng)
	for k in 4:
		SeaReef.moss(Vector3(shaft.x, base.y + 10.0 + k * 12.0 + 0.9, shaft.z) + Vector3(1.8, 0.0, 0.0).rotated(Vector3.UP, rng.randf() * TAU),
			0.9, rng)
	var mi := MeshInstance3D.new()
	mi.name = "GiantTrident"
	mi.mesh = mb.commit(null, TrackMaterials.sea_bronze("giant_trident", {"patina_amount": 0.5, "groove_spacing": 2.4}))
	mi.visibility_range_end = VISIBILITY
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	root.set_meta("trident", Vector3(shaft.x, fork, shaft.z))
	SeaFloor.claim(shaft, half + 3.0, top + 1.0)


# ---------------------------------------------------------------------------
# Peças
# ---------------------------------------------------------------------------
## Coluna jônica: base moldurada, fuste com êntase e caneluras (FLUTES sulcos, facetas lisas: o toon
## mostra as listras de luz e sombra), equino, as duas volutas enroladas e o ábaco; `broken` corta o
## fuste com o topo quebrado irregular; `top_moss` = musgo no alto (às vezes).
static func column(mb: MeshBuilder, base: Vector3, height: float, radius: float, broken := 0.0, color := STONE,
		top_moss := true) -> void:
	var shaft := height * (1.0 - broken) if broken > 0.0 else height - radius * 1.4
	# Base (toro e escócia) até o pé do fuste
	mb.lathe(Transform3D(Basis(), base), PackedVector2Array([Vector2(radius * 1.35, 0.0), Vector2(radius * 1.35, radius * 0.35),
		Vector2(radius * 1.15, radius * 0.55), Vector2(radius * 1.0, radius * 0.6), Vector2(0.0, radius * 0.6)]), color, 14)
	# Fuste canelado: anéis com o raio da êntase, a aresta e o fundo de cada canelura alternando
	const RINGS := 5
	var sides := FLUTES * 2
	var turn := _rng.randf() * TAU
	var rings: Array[PackedVector3Array] = []
	for k in RINGS + 1:
		var t := float(k) / RINGS
		var y := radius * 0.6 + t * (shaft - radius * 0.6)
		var r := radius * (1.0 - 0.14 * t + 0.05 * sin(t * PI))
		var ring := PackedVector3Array()
		for j in sides:
			var a := TAU * j / sides + turn
			var rr := r * (1.0 if j % 2 == 0 else 0.9)
			# (topo da coluna quebrada: a borda irregular)
			var yy := y - (_rng.randf_range(0.0, radius * 0.9) if broken > 0.0 and k == RINGS else 0.0)
			ring.append(base + Vector3(cos(a) * rr, yy, sin(a) * rr))
		rings.append(ring)
	for k in RINGS:
		for j in sides:
			var j1 := (j + 1) % sides
			var out := Vector3(cos(TAU * (j + 0.5) / sides + turn), 0.0, sin(TAU * (j + 0.5) / sides + turn))
			mb.quad(rings[k][j], rings[k][j1], rings[k + 1][j1], rings[k + 1][j], color, out)
	if broken > 0.0:
		var c := base + Vector3.UP * (shaft - radius * 0.5)
		for j in sides:
			mb.tri(rings[RINGS][j], rings[RINGS][(j + 1) % sides], c, color * 0.92, Vector3.UP)
	else:
		# Equino, as volutas (dois rolos de lado a lado sob o ábaco) e o ábaco
		mb.lathe(Transform3D(Basis(), base), PackedVector2Array([Vector2(radius * 0.9, shaft), Vector2(radius * 1.25, shaft + radius * 0.5),
			Vector2(radius * 1.2, shaft + radius * 0.75), Vector2(0.0, shaft + radius * 0.75)]), color, 14)
		var roll := Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, turn)
		var across := Vector3(cos(turn), 0.0, -sin(turn))
		for side: float in [-1.0, 1.0]:
			var at := base + across * side * radius * 1.3 + Vector3.UP * (shaft + radius * 0.55) - roll.y * radius * 1.25
			mb.cylinder(Transform3D(roll, at), radius * 0.36, radius * 0.36, radius * 2.5, color * 0.95, 10)
		mb.box(Transform3D(Basis(Vector3.UP, -turn), base + Vector3.UP * (shaft + radius * 1.05)), Vector3(radius * 2.9, radius * 0.6, radius * 2.9),
			color)
	# Corais no pé e musgo no alto (só debaixo d'água: o SeaReef ignora o resto)
	SeaReef.cluster(base, radius * 2.6, _rng, _rng.randi_range(2, 4))
	if broken <= 0.0 and _rng.randf() < 0.6 and top_moss:
		SeaReef.moss(base + Vector3.UP * (shaft + radius * 1.35), radius * 1.2, _rng)
	elif broken > 0.0:
		SeaReef.moss(base + Vector3.UP * shaft, radius * 1.1, _rng)


## Parede reta de `a` até `b` (no chão, horizontal), da altura `y0` a `y1` (em relação a a.y), com
## `count` arcos vazados (nascendo em y0 + spring) e espessura `thick`: pilares com plinto e imposta,
## as faces de dentro dos vãos, aduelas salientes em volta de cada arco com a pedra de fecho, a
## cornija no alto e as pontas fechadas; algas penduradas no alto dos arcos, corais nos pés dos
## pilares e musgo em cima (SeaReef).
static func arcade(mb: MeshBuilder, a: Vector3, b: Vector3, y0: float, y1: float, count: int, spring: float,
		thick: float, color := STONE) -> void:
	var along := b - a
	along.y = 0.0
	var length := along.length()
	var x := along / length
	var z := x.cross(Vector3.UP).normalized()
	var flat := Basis(x, Vector3.UP, z)
	var bay := length / count
	var pier := bay * 0.28
	var r := (bay - pier) * 0.5
	var steps := 8
	var dark := color * 0.8
	dark.a = 1.0
	var band := clampf(r * 0.2, 0.3, 1.1)
	for side: float in [1.0, -1.0]:
		var off := z * side * thick * 0.5
		var n := z * side
		var out := z * side * (thick * 0.5 + 0.14)
		for c in count:
			var x0 := c * bay
			# Pilar (do chão à nascença) dos dois lados do vão
			for px: float in [x0, x0 + bay - pier * 0.5]:
				var w := pier * 0.5
				var p0 := a + x * px + off
				mb.quad(p0 + Vector3.UP * y0, p0 + x * w + Vector3.UP * y0, p0 + x * w + Vector3.UP * (y0 + spring),
					p0 + Vector3.UP * (y0 + spring), color, n)
			# Tímpano: do intradorso até o topo; aduelas salientes em volta do arco
			var cx := x0 + pier * 0.5 + r
			for k in steps:
				var ang0 := PI * (1.0 - float(k) / steps)
				var ang1 := PI * (1.0 - float(k + 1) / steps)
				var q0 := a + x * (cx + cos(ang0) * r) + off + Vector3.UP * (y0 + spring + sin(ang0) * r)
				var q1 := a + x * (cx + cos(ang1) * r) + off + Vector3.UP * (y0 + spring + sin(ang1) * r)
				var t0 := Vector3(q0.x, a.y + y1, q0.z)
				var t1 := Vector3(q1.x, a.y + y1, q1.z)
				mb.quad(q0, q1, t1, t0, color, n)
				var i0 := a + x * (cx + cos(ang0) * r) + out + Vector3.UP * (y0 + spring + sin(ang0) * r)
				var i1 := a + x * (cx + cos(ang1) * r) + out + Vector3.UP * (y0 + spring + sin(ang1) * r)
				var o0 := a + x * (cx + cos(ang0) * (r + band)) + out + Vector3.UP * (y0 + spring + sin(ang0) * (r + band))
				var o1 := a + x * (cx + cos(ang1) * (r + band)) + out + Vector3.UP * (y0 + spring + sin(ang1) * (r + band))
				mb.quad(i0, i1, o1, o0, BRICK if k % 2 == 0 else color, n)
			# Faixa do pilar acima da nascença até o topo
			var p1 := a + x * x0 + off
			mb.quad(p1 + Vector3.UP * (y0 + spring), p1 + x * pier * 0.5 + Vector3.UP * (y0 + spring),
				p1 + x * pier * 0.5 + Vector3.UP * y1, p1 + Vector3.UP * y1, color, n)
			var p2 := a + x * (x0 + bay - pier * 0.5) + off
			mb.quad(p2 + Vector3.UP * (y0 + spring), p2 + x * pier * 0.5 + Vector3.UP * (y0 + spring),
				p2 + x * pier * 0.5 + Vector3.UP * y1, p2 + Vector3.UP * y1, color, n)
	for c in count:
		var x_l := c * bay + pier * 0.5
		var x_r := (c + 1) * bay - pier * 0.5
		# Faces de dentro do vão (do chão à nascença) e a pedra de fecho
		for jamb: Vector2 in [Vector2(x_l, 1.0), Vector2(x_r, -1.0)]:
			var p0 := a + x * jamb.x + Vector3.UP * y0
			mb.quad(p0 - z * thick * 0.5, p0 + z * thick * 0.5, p0 + z * thick * 0.5 + Vector3.UP * spring,
				p0 - z * thick * 0.5 + Vector3.UP * spring, color * 0.9, x * jamb.y)
		mb.box(Transform3D(flat, a + x * (x_l + r) + Vector3.UP * (y0 + spring + r + band * 0.45)),
			Vector3(band * 0.85, band * 1.35, thick + 0.5), dark)
	# Plinto e imposta de cada pilar (nas pontas, meio pilar)
	for c in count + 1:
		var w := pier * (0.5 if c == 0 or c == count else 1.0)
		var px := c * bay + (pier * 0.25 if c == 0 else (-pier * 0.25 if c == count else 0.0))
		mb.box(Transform3D(flat, a + x * px + Vector3.UP * (y0 + 0.45)), Vector3(w + 0.35, 0.9, thick + 0.4), dark)
		mb.box(Transform3D(flat, a + x * px + Vector3.UP * (y0 + spring + 0.18)), Vector3(w + 0.3, 0.36, thick + 0.3), dark)
	# Pontas fechadas e a cornija
	for e: Vector2 in [Vector2(0.0, -1.0), Vector2(length, 1.0)]:
		var p0 := a + x * e.x
		mb.quad(p0 - z * thick * 0.5 + Vector3.UP * y0, p0 + z * thick * 0.5 + Vector3.UP * y0, p0 + z * thick * 0.5 + Vector3.UP * y1,
			p0 - z * thick * 0.5 + Vector3.UP * y1, color, x * e.y)
	mb.box(Transform3D(flat, a + x * length * 0.5 + Vector3.UP * (y1 - 0.22)), Vector3(length + 0.4, 0.44, thick + 0.5), dark)
	# Algas penduradas no alto dos arcos, corais nos pés dos pilares e musgo em cima
	for c in count:
		var cx := c * bay + pier * 0.5 + r
		if _rng.randf() < 0.75:
			SeaReef.hang(a + x * (cx + _rng.randf_range(-r, r) * 0.4) + z * _rng.randf_range(-thick, thick) * 0.4 + Vector3.UP * (y0 + spring + r * 0.95),
				_rng.randf_range(1.2, r * 0.9 + 1.0), _rng)
		if y0 < 0.5 and _rng.randf() < 0.6:
			SeaReef.cluster(a + x * (c * bay) + z * (thick * 0.5 + 0.8), 2.0, _rng, 3)
		if _rng.randf() < 0.4:
			SeaReef.moss(a + x * (cx + _rng.randf_range(-r, r)) + Vector3.UP * (y1 + 0.05), 1.0, _rng)
	# Intradorsos e topo
	for c in count:
		var cx := c * bay + pier * 0.5 + r
		for k in steps:
			var ang0 := PI * float(k) / steps
			var ang1 := PI * float(k + 1) / steps
			var q0 := a + x * (cx + cos(ang0) * r) + Vector3.UP * (y0 + spring + sin(ang0) * r)
			var q1 := a + x * (cx + cos(ang1) * r) + Vector3.UP * (y0 + spring + sin(ang1) * r)
			var c0 := a + x * cx + Vector3.UP * (y0 + spring)
			mb.quad(q0 + z * thick * 0.5, q1 + z * thick * 0.5, q1 - z * thick * 0.5, q0 - z * thick * 0.5, color * 0.8,
				(c0 - (q0 + q1) * 0.5).normalized())
	mb.quad(a + Vector3.UP * y1 + z * thick * 0.5, b + Vector3.UP * y1 + z * thick * 0.5, b + Vector3.UP * y1 - z * thick * 0.5,
		a + Vector3.UP * y1 - z * thick * 0.5, color, Vector3.UP)


## Aqueduto em ruínas de `a` até `b` (no chão, horizontal): o andar de baixo com arcos altos (`h1` m)
## e contrafortes nos pilares, o andar de cima com arcos pequenos (às vezes com dois vãos desabados) e
## o canal no alto com as lajes da cobertura (algumas faltando). Às vezes a ponta de `b` caiu: o
## último vão some, o pilar fica pela metade e as pedras ficam no chão. Estandartes e lanternas em
## alguns pilares. Devolve a altura do topo.
static func aqueduct(mb: MeshBuilder, lamps: MeshBuilder, banners: MeshBuilder, a: Vector3, b: Vector3, h1: float,
		rng: RandomNumberGenerator) -> float:
	var along := b - a
	along.y = 0.0
	var length := along.length()
	var x := along / length
	var z := x.cross(Vector3.UP).normalized()
	var flat := Basis(x, Vector3.UP, z)
	var bays := maxi(int(length / 12.0), 3)
	var bay := length / bays
	var thick := 3.2
	var broken := rng.randf() < 0.45
	var keep := bays - (1 if broken else 0)
	var end := a + x * (bay * keep)
	arcade(mb, a, end, 0.0, h1, keep, h1 * 0.45, thick)
	# Contrafortes nos pilares, das duas faces, em dois degraus
	for c in keep + 1:
		for side: float in [1.0, -1.0]:
			var base := a + x * (c * bay) + z * side * (thick * 0.5 + 0.45)
			mb.box(Transform3D(flat, base + Vector3.UP * h1 * 0.22), Vector3(bay * 0.16, h1 * 0.44, 0.9), STONE_DARK)
			mb.box(Transform3D(flat, base + Vector3.UP * h1 * 0.52 - z * side * 0.2), Vector3(bay * 0.12, h1 * 0.18, 0.5), STONE_DARK)
	if broken:
		var stub := a + x * (bay * bays)
		mb.box(Transform3D(flat, stub + Vector3.UP * h1 * 0.2 - x * bay * 0.07), Vector3(bay * 0.14, h1 * 0.4, thick), STONE)
		for k in rng.randi_range(5, 9):
			var at := a + x * (bay * (keep + rng.randf())) + z * rng.randf_range(-4.0, 4.0)
			var sz := rng.randf_range(0.7, 1.6)
			mb.box(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4)),
				at + Vector3.UP * sz * 0.3), Vector3(sz * 1.6, sz, sz * 1.1), STONE * rng.randf_range(0.85, 1.0))
	# Andar de cima (com um trecho desabado às vezes) e o canal sobre ele
	var h2 := h1 * rng.randf_range(0.5, 0.62)
	var up := Vector3.UP * h1
	var bays2 := keep * 2
	var bay2 := bay * 0.5
	var gap := rng.randi_range(1, bays2 - 3) if bays2 > 4 and rng.randf() < 0.4 else -1
	var runs: Array[Vector2i] = [Vector2i(0, bays2)]
	if gap >= 0:
		runs = [Vector2i(0, gap), Vector2i(gap + 2, bays2)]
	for run in runs:
		if run.y <= run.x:
			continue
		var ra := a + up + x * (bay2 * run.x)
		var rb := a + up + x * (bay2 * run.y)
		arcade(mb, ra, rb, 0.0, h2, run.y - run.x, h2 * 0.35, thick * 0.8)
		_channel(mb, ra + Vector3.UP * h2, rb + Vector3.UP * h2, thick * 0.8, rng)
	# Estandartes e lanternas em alguns pilares
	for c in range(1, keep):
		if rng.randf() < 0.35:
			for side: float in [1.0, -1.0]:
				add_banner(banners, a + x * (c * bay) + z * side * (thick * 0.5 + 0.95) + Vector3.UP * (h1 - 0.6), x, z * side, 1.8, 5.0)
		elif rng.randf() < 0.3:
			lantern(mb, lamps, a + x * (c * bay) + z * (thick * 0.5 + 1.0) + Vector3.UP * (h1 * 0.62))
	return a.y + h1 + h2 + 1.7


## Canal no alto do aqueduto (de `a` até `b`): as duas paredes e as lajes da cobertura, algumas
## faltando.
static func _channel(mb: MeshBuilder, a: Vector3, b: Vector3, width: float, rng: RandomNumberGenerator) -> void:
	var along := b - a
	var length := along.length()
	var x := along / length
	var z := x.cross(Vector3.UP).normalized()
	var flat := Basis(x, Vector3.UP, z)
	for side: float in [1.0, -1.0]:
		mb.box(Transform3D(flat, (a + b) * 0.5 + z * side * (width * 0.5 - 0.3) + Vector3.UP * 0.7), Vector3(length, 1.4, 0.6), STONE)
	var slabs := maxi(int(length / 1.6), 1)
	for k in slabs:
		if rng.randf() < 0.3:
			continue
		var at := a + x * (length * (k + 0.5) / slabs) + Vector3.UP * 1.55
		mb.box(Transform3D(flat * Basis(Vector3.UP, rng.randf_range(-0.06, 0.06)), at), Vector3(length / slabs - 0.12, 0.3, width + 0.25),
			STONE_DARK)


## Estandarte (pano com o tridente) preso em `top` (centro da borda de cima), largura ao longo de
## `right`, virado para `facing`; subdividido na altura para balançar (banner_trident.gdshader).
static func add_banner(mb: MeshBuilder, top: Vector3, right: Vector3, facing: Vector3, width: float, height: float) -> void:
	var r := right.normalized() * width * 0.5
	var rows := 8
	for k in rows:
		var v0 := float(k) / rows
		var v1 := float(k + 1) / rows
		var y0 := Vector3.DOWN * height * v0
		var y1 := Vector3.DOWN * height * v1
		mb.quad(top - r + y0, top + r + y0, top + r + y1, top - r + y1, Color.WHITE, facing,
			Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1))


static func banner_material() -> ShaderMaterial:
	if _banner_mat == null:
		_banner_mat = ShaderMaterial.new()
		_banner_mat.shader = load("res://shaders/track/banner_trident.gdshader")
	return _banner_mat


## Lanterna (globo quente) num suporte.
## Lanterna: a haste, o anel de bronze embaixo, o globo aceso e a tampa de bronze em cúpula com o
## botão no alto.
static func lantern(mb: MeshBuilder, lamps: MeshBuilder, at: Vector3) -> void:
	mb.cylinder(Transform3D(Basis(), at + Vector3.DOWN * 0.9), 0.08, 0.08, 0.5, STONE_DARK, 6, false)
	mb.cylinder(Transform3D(Basis(), at + Vector3.DOWN * 0.46), 0.2, 0.26, 0.12, LANTERN_BRONZE, 10)
	lamps.blob(at, Vector3(0.38, 0.42, 0.38), LANTERN, 8, 5)
	mb.lathe(Transform3D(Basis(), at + Vector3.UP * 0.3), PackedVector2Array([Vector2(0.44, 0.0), Vector2(0.4, 0.1), Vector2(0.24, 0.26),
		Vector2(0.06, 0.34), Vector2(0.09, 0.42), Vector2(0.0, 0.48)]), LANTERN_BRONZE, 10)


# ---------------------------------------------------------------------------
# Marcos perto da pista
# ---------------------------------------------------------------------------
## Templo de Poseidon por fora da Curva do Templo, de frente para quem chega.
static func _temple(track: RaceTrack, mb: MeshBuilder, banners: MeshBuilder, lamps: MeshBuilder, statues: Array) -> void:
	var p := track.path
	var i := p.index_at(TEMPLE_S)
	var side := -1  # curva à esquerda: o templo fica por fora (à direita)
	var d := SeaTube.clearance(track, i, side) + 34.0
	var center := p.frame_at(TEMPLE_S, side * d, 0.0).origin
	var ground := SeaFloor.ground(track, center.x, center.z)
	var to_track := (p.points[i] - center)
	to_track.y = 0.0
	to_track = to_track.normalized()
	var x := to_track.cross(Vector3.UP).normalized()
	var basis := Basis(x, Vector3.UP, to_track)
	var base := Vector3(center.x, ground, center.z)
	var width := 44.0
	var depth := 30.0
	SeaFloor.claim(base, 32.0, base.y + 32.0)
	# Escadaria (três degraus largos) e o piso
	var y := 0.0
	for k in 4:
		var h := 1.2 if k < 3 else 1.6
		mb.box(Transform3D(basis, base + basis.y * (y + h * 0.5)), Vector3(width + 8.0 - k * 2.6, h, depth + 8.0 - k * 2.6), STONE_DARK if k == 3 else STONE)
		y += h
	var floor_y := y
	# Colunas da frente e das laterais
	var col_h := 15.0
	var col_r := 0.95
	for c in 8:
		var cx := -width * 0.5 + 2.5 + c * (width - 5.0) / 7.0
		var broken := 0.35 if c == 6 else 0.0
		column(mb, base + basis * Vector3(cx, floor_y, depth * 0.5 - 2.0), col_h, col_r, broken)
		column(mb, base + basis * Vector3(cx, floor_y, -depth * 0.5 + 2.0), col_h, col_r)
	for c in range(1, 4):
		var cz := -depth * 0.5 + 2.0 + c * (depth - 4.0) / 4.0
		for sx: float in [-1.0, 1.0]:
			column(mb, base + basis * Vector3(sx * (width * 0.5 - 2.5), floor_y, cz), col_h, col_r)
	# Cela (parede interna) com a porta
	mb.box(Transform3D(basis, base + basis * Vector3(0, floor_y + 6.0, -2.0)), Vector3(width - 12.0, 12.0, depth - 10.0), STONE_DARK)
	# Entablamento, frontão (com o tridente) e telhado (quebrado num canto)
	var top := floor_y + col_h + 0.6
	mb.box(Transform3D(basis, base + basis * Vector3(0, top + 1.0, 0)), Vector3(width, 2.0, depth), STONE)
	var ped_h := 6.5
	var front := depth * 0.5
	var l := base + basis * Vector3(-width * 0.5, top + 2.0, front)
	var r := base + basis * Vector3(width * 0.5, top + 2.0, front)
	var apex := base + basis * Vector3(0, top + 2.0 + ped_h, front)
	var lb := base + basis * Vector3(-width * 0.5, top + 2.0, -front)
	var rb := base + basis * Vector3(width * 0.5, top + 2.0, -front)
	var apex_b := base + basis * Vector3(0, top + 2.0 + ped_h, -front)
	mb.tri(l, r, apex, STONE, to_track)
	mb.tri(lb, rb, apex_b, STONE, -to_track)
	mb.quad(l, apex, apex_b, lb, STONE_DARK, (basis.y - basis.x).normalized())
	mb.quad(apex, r, rb, apex_b, STONE_DARK, (basis.y + basis.x).normalized())
	# Frontão: a moldura saliente nos três lados, o tímpano recuado e escuro, o tridente dourado em
	# relevo no meio, os acrotérios (palmetas) no alto e nas pontas e o friso de tríglifos embaixo
	var out := to_track * 0.6
	for pair: Array in [[l, apex], [apex, r], [l, r]]:
		var a: Vector3 = pair[0]
		var b: Vector3 = pair[1]
		var along := (b - a).normalized()
		var up := along.cross(to_track).normalized()
		if up.y < 0.0:
			up = -up
		mb.box(Transform3D(Basis(along, up, along.cross(up)).orthonormalized(), (a + b) * 0.5 + out + up * 0.35),
			Vector3(a.distance_to(b) + 1.4, 0.8, 1.6), STONE)
	mb.tri(l + out * 0.2 + basis.x * 1.6 + Vector3.UP * 0.9, r + out * 0.2 - basis.x * 1.6 + Vector3.UP * 0.9,
		apex + out * 0.2 + Vector3.DOWN * 0.9, STONE_DARK, to_track)
	var gold := Color(1.0, 0.78, 0.3)
	var tri_at := base + basis * Vector3(0, top + 2.0 + 1.0, front + 0.75)
	mb.box(Transform3D(basis, tri_at + Vector3.UP * 1.9), Vector3(0.45, 3.8, 0.3), gold)
	mb.box(Transform3D(basis, tri_at + Vector3.UP * 3.2), Vector3(3.2, 0.4, 0.3), gold)
	for tx: float in [-1.4, 0.0, 1.4]:
		var tip := tri_at + basis.x * tx + Vector3.UP * (4.5 if tx == 0.0 else 4.1)
		mb.box(Transform3D(basis, tip + Vector3.DOWN * 0.55), Vector3(0.35, 1.3, 0.3), gold)
		mb.box(Transform3D(basis.rotated(to_track, PI * 0.25), tip + Vector3.UP * 0.2), Vector3(0.6, 0.6, 0.3), gold)
	for at: Vector3 in [apex + Vector3.UP * 0.9, l + Vector3.UP * 0.9, r + Vector3.UP * 0.9]:
		mb.box(Transform3D(basis.rotated(to_track, PI * 0.25), at + out), Vector3(1.6, 1.6, 0.5), STONE)
		mb.box(Transform3D(basis, at + out + Vector3.UP * 1.1), Vector3(0.5, 1.6, 0.5), gold)
	for t in 16:
		var tx := -width * 0.5 + 1.4 + t * (width - 2.8) / 15.0
		mb.box(Transform3D(basis, base + basis * Vector3(tx, top + 1.0, front + 0.15)), Vector3(0.9, 1.6, 0.3),
			STONE_DARK if t % 2 == 0 else STONE)
	# Estandartes nas colunas da frente
	add_banner(banners, base + basis * Vector3(-width * 0.5 + 6.0, floor_y + col_h - 1.0, depth * 0.5 - 0.6), basis.x, to_track, 2.4, 7.0)
	add_banner(banners, base + basis * Vector3(width * 0.5 - 6.0, floor_y + col_h - 1.0, depth * 0.5 - 0.6), basis.x, to_track, 2.4, 7.0)
	# Lanternas na escadaria
	for sx: float in [-1.0, 1.0]:
		var at := base + basis * Vector3(sx * (width * 0.5 + 2.0), floor_y + 4.2, depth * 0.5 + 3.0)
		mb.cylinder(Transform3D(Basis(), at + Vector3.DOWN * 4.2), 0.5, 0.4, 3.4, STONE_DARK, 10)
		lantern(mb, lamps, at)
	# Estátua de Poseidon na frente do templo (pedestal)
	var ped := base + basis * Vector3(0, 0, depth * 0.5 + 10.0)
	mb.box(Transform3D(basis, ped + Vector3.UP * 1.5), Vector3(6.0, 3.0, 6.0), STONE_DARK)
	statues.append(["poseidon_standing", Transform3D(basis.scaled(Vector3.ONE * 1.0), ped + Vector3.UP * 3.0)])


## Colunatas dos dois lados da Avenida das Colunas: colunas a cada 16 m atrás da barreira, arquitraves
## ligando os pares (algumas faltando), colunas quebradas com tambores caídos e estandartes.
static func _avenue(track: RaceTrack, mb: MeshBuilder, banners: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var p := track.path
	var spacing := 16.0
	var count := int((AVENUE.y - AVENUE.x) / spacing)
	for side: int in [1, -1]:
		var prev := Vector3.INF
		var prev_ok := false
		for k in count + 1:
			var s := AVENUE.x + k * spacing
			var i := p.index_at(s)
			var d := SeaTube.clearance(track, i, side) + 2.5
			var base := p.frame_at(s, side * d, 0.0).origin
			base.y = maxf(SeaFloor.ground(track, base.x, base.z), p.points[i].y - 2.0)
			var broken := rng.randf_range(0.3, 0.7) if rng.randf() < 0.22 else 0.0
			# Plinto até a altura da pista (o leito fica abaixo da laje)
			var plinth := p.points[i].y - base.y
			if plinth > 0.2:
				mb.box(Transform3D(Basis(), base + Vector3.UP * plinth * 0.5), Vector3(2.8, plinth, 2.8), STONE_DARK)
			var foot := Vector3(base.x, p.points[i].y, base.z)
			column(mb, foot, 12.0, 0.75, broken)
			if broken > 0.0:
				# Tambores caídos ao lado
				for n in 2:
					var drum := foot + p.tangents[i] * rng.randf_range(-4.0, 4.0) + p.lefts[i] * side * rng.randf_range(2.0, 5.0)
					var b := Basis(p.tangents[i].normalized(), rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5)
					mb.cylinder(Transform3D(b, drum + Vector3.UP * 0.7), 0.72, 0.72, 1.6, STONE, 12)
			var ok := broken == 0.0
			if ok and prev_ok and rng.randf() < 0.75:
				var top_a := prev + Vector3.UP * 12.2
				var top_b := foot + Vector3.UP * 12.2
				var along := top_b - top_a
				mb.box(Transform3D(Basis(along.normalized().cross(Vector3.UP).normalized(), Vector3.UP, along.normalized()),
					(top_a + top_b) * 0.5 + Vector3.UP * 0.6), Vector3(1.8, 1.2, along.length() + 1.0), STONE)
				if k % 3 == 1:
					add_banner(banners, (top_a + top_b) * 0.5 + Vector3.DOWN * 0.1, along, -p.lefts[i] * side, 2.0, 6.0)
			prev = foot
			prev_ok = ok


## Portal de Atlântida: dois pilares maciços atrás das barreiras (com a base em degrau, pilastras e o
## capitel), um arco sobre a pista (vão livre de PORTAL_CLEAR m) de aduelas alternando pedra e tijolo,
## a pedra de fecho com o tridente dourado em relevo, a cornija no alto, estandartes e lanternas.
static func _portal(track: RaceTrack, mb: MeshBuilder, banners: MeshBuilder, lamps: MeshBuilder) -> void:
	var p := track.path
	var i := p.index_at(PORTAL_S)
	var dl := SeaTube.clearance(track, i, 1) + 1.5
	var dr := SeaTube.clearance(track, i, -1) + 1.5
	var f := p.frame_at(PORTAL_S, 0.0, 0.0)
	var x := p.lefts[i]
	var z := p.tangents[i].normalized()
	var basis := Basis(x, Vector3.UP, z).orthonormalized()
	var pillar := Vector3(5.0, 0.0, 6.0)
	# O arco passa por cima do tubo de vidro
	var top := maxf(PORTAL_CLEAR, float(SeaTube.profile(track).height[i]) + 4.5)
	for side: int in [1, -1]:
		var d := dl if side > 0 else dr
		var c := f.origin + x * side * (d + pillar.x * 0.5)
		var ground := minf(SeaFloor.ground(track, c.x, c.z), f.origin.y - 1.0)
		var h := f.origin.y + top + 4.0 - ground
		mb.box(Transform3D(basis, Vector3(c.x, ground + h * 0.5, c.z)), Vector3(pillar.x, h, pillar.z), STONE)
		mb.box(Transform3D(basis, Vector3(c.x, f.origin.y + top + 4.6, c.z)), Vector3(pillar.x + 1.2, 1.2, pillar.z + 1.2), STONE_DARK)
		# Base em degrau e pilastras nas faces da frente e de trás, com o capitel
		mb.box(Transform3D(basis, Vector3(c.x, f.origin.y + 1.0, c.z)), Vector3(pillar.x + 1.4, 2.0, pillar.z + 1.4), STONE_DARK)
		for fz: float in [-1.0, 1.0]:
			var face := Vector3(c.x, 0.0, c.z) + z * fz * (pillar.z * 0.5 + 0.2)
			var ph := f.origin.y + top + 3.4
			mb.box(Transform3D(basis, Vector3(face.x, (f.origin.y + 2.0 + ph) * 0.5, face.z)), Vector3(2.2, ph - f.origin.y - 2.0, 0.5), STONE)
			mb.box(Transform3D(basis, Vector3(face.x, ph + 0.3, face.z) + z * fz * 0.15), Vector3(3.0, 0.6, 0.8), STONE_DARK)
		add_banner(banners, c - x * side * (pillar.x * 0.5 + 0.08) + Vector3.UP * (top - 1.0), z, -x * side, 2.6, 9.0)
		lantern(mb, lamps, c - x * side * (pillar.x * 0.5 + 0.6) + z * 2.2 + Vector3.UP * 5.0)
	# Arco: anel de pedra entre os pilares
	var span := dl + dr
	var mid := f.origin + x * (dl - dr) * 0.5
	var r_in := span * 0.5
	var spring := top - r_in * 0.42
	var steps := 18
	for k in steps:
		var a0 := PI * float(k) / steps
		var a1 := PI * float(k + 1) / steps
		var p0 := mid + x * (cos(a0) * r_in) + Vector3.UP * (spring + sin(a0) * r_in * 0.42)
		var p1 := mid + x * (cos(a1) * r_in) + Vector3.UP * (spring + sin(a1) * r_in * 0.42)
		var seg := p1 - p0
		var b := Basis(seg.normalized(), seg.normalized().cross(z).normalized() * -1.0, z).orthonormalized()
		# (aduelas alternando pedra clara e tijolo, como nos aquedutos)
		mb.box(Transform3D(b, (p0 + p1) * 0.5 + b.y * 1.6), Vector3(seg.length() + 0.3, 3.2, pillar.z - 0.6), STONE if k % 2 == 0 else BRICK)
	# Pedra de fecho saliente com o tridente dourado em relevo nas duas faces, cornija por cima
	var key := mid + Vector3.UP * (spring + r_in * 0.42 + 1.6)
	mb.box(Transform3D(basis, key), Vector3(2.6, 4.4, pillar.z + 0.4), STONE)
	var gold := Color(1.0, 0.78, 0.3)
	for fz: float in [-1.0, 1.0]:
		var face := key + z * fz * (pillar.z * 0.5 + 0.3)
		mb.box(Transform3D(basis, face + Vector3.DOWN * 0.4), Vector3(0.22, 2.6, 0.2), gold)
		mb.box(Transform3D(basis, face + Vector3.UP * 0.55), Vector3(1.5, 0.22, 0.2), gold)
		for tx: float in [-0.65, 0.0, 0.65]:
			mb.box(Transform3D(basis, face + x * tx + Vector3.UP * (1.05 if tx == 0.0 else 0.95)), Vector3(0.18, 0.8 if tx == 0.0 else 0.6, 0.2), gold)
			mb.box(Transform3D(basis.rotated(z, PI * 0.25), face + x * tx + Vector3.UP * (1.55 if tx == 0.0 else 1.35)), Vector3(0.32, 0.32, 0.2), gold)
	mb.box(Transform3D(basis, mid + Vector3.UP * (spring + r_in * 0.42 + 4.1)), Vector3(span + pillar.x * 2.0 + 2.0, 0.9, pillar.z + 1.0), STONE_DARK)
	# Estandarte do tridente no meio, virado para quem chega
	add_banner(banners, mid + Vector3.UP * (spring + r_in * 0.42 - 0.2) - z * 2.9, x, -z, 3.0, 5.0)


## Muralha do anfiteatro: atrás das arquibancadas do lado de dentro da reta, dois andares de arcos, com
## estátuas (Poseidon e a deusa, alternando) em pedestais no alto, uma a cada dois trechos.
static func _amphitheater_wall(track: RaceTrack, mb: MeshBuilder, banners: MeshBuilder, lamps: MeshBuilder, statues: Array) -> void:
	var p := track.path
	for f in track.layout.features:
		if f == null or f.kind != TrackFeature.Kind.GRANDSTAND or not (f.s_start < 100.0 and f.s_start > -400.0):
			continue
		for side in f.sides():
			var segs := maxi(int(fposmod(f.s_end - f.s_start, p.length) / 40.0), 1)
			for k in segs:
				var sa := f.s_start + k * fposmod(f.s_end - f.s_start, p.length) / segs
				var sb := f.s_start + (k + 1) * fposmod(f.s_end - f.s_start, p.length) / segs
				var ia := p.index_at(sa)
				var ib := p.index_at(sb)
				var da := SeaTube.clearance(track, ia, side) + 1.0
				var db := SeaTube.clearance(track, ib, side) + 1.0
				var a := p.frame_at(sa, side * da, 0.0).origin
				var b := p.frame_at(sb, side * db, 0.0).origin
				var ground := minf(SeaFloor.ground(track, a.x, a.z), SeaFloor.ground(track, b.x, b.z))
				var lift := a.y - ground
				a.y = ground
				b.y = ground
				arcade(mb, a, b, 0.0, lift + 11.0, 4, lift + 3.0, 2.2)
				arcade(mb, a + Vector3.UP * (lift + 11.0), b + Vector3.UP * (lift + 11.0), 0.0, 10.0, 4, 3.0, 1.8)
				for u in 9:
					SeaFloor.claim(a.lerp(b, u / 8.0), 3.0, ground + lift + 22.0)
				if k % 2 == 0:
					var c := (a + b) * 0.5 + Vector3.UP * (lift + 20.0) - p.lefts[ia] * side * 1.0
					add_banner(banners, c, b - a, -p.lefts[ia] * side, 2.6, 8.0)
					lantern(mb, lamps, c + (b - a).normalized() * 6.0 - p.lefts[ia] * side * 0.8 + Vector3.DOWN * 9.0)
				else:
					# Estátua no alto, num pedestal sobre a cornija, virada para a pista
					var ped := (a + b) * 0.5 + Vector3.UP * (lift + 21.0)
					mb.box(Transform3D(Basis(), ped + Vector3.UP * 0.6), Vector3(2.4, 1.2, 2.4), STONE_DARK)
					var face := -p.lefts[ia] * side
					var model: String = "poseidon_standing" if (k / 2) % 2 == 0 else "goddess_head"
					var sc := 0.42 if model == "poseidon_standing" else 0.55
					statues.append([model, Transform3D(Basis.looking_at(-face).scaled(Vector3.ONE * sc), ped + Vector3.UP * 1.2)])


# ---------------------------------------------------------------------------
# Ao longe
# ---------------------------------------------------------------------------
static func _bucket(out: Dictionary, pos: Vector3) -> Array:
	var key := Vector2i(floori(pos.x / BUCKET), floori(pos.z / BUCKET))
	if not out.has(key):
		out[key] = [MeshBuilder.new(), MeshBuilder.new(), MeshBuilder.new()]
	return out[key]


## Lugar livre ao longe: a `min_gap` m além de tudo o que foi construído junto à pista.
static func _free_spot(track: RaceTrack, rng: RandomNumberGenerator, reach: float, min_gap: float) -> Vector3:
	var p := track.path
	var b := p.bounds().grow(reach)
	for t in 30:
		var pos := Vector3(rng.randf_range(b.position.x, b.end.x), 0.0, rng.randf_range(b.position.y, b.end.y))
		var pr := p.project(pos, false, false)
		if pr.y != INF:
			var i := p.index_at(pr.x)
			var side := 1 if pr.y > 0.0 else -1
			if absf(pr.y) < SeaTube.clearance(track, i, side) + min_gap:
				continue
		pos.y = SeaFloor.ground(track, pos.x, pos.z)
		# Na encosta, a base vai na parte mais baixa (o prédio entra no morro em vez de flutuar)
		for o: Vector2 in [Vector2(10, 0), Vector2(-10, 0), Vector2(0, 10), Vector2(0, -10)]:
			pos.y = minf(pos.y, SeaFloor.ground(track, pos.x + o.x, pos.z + o.y))
		# Longe do trecho emerso (lá ficam as falésias do Portão) e do que já ocupa o leito
		if pos.y > track.layout.water_level - 30.0 or SeaFloor.claimed(pos, 20.0):
			continue
		return pos
	return Vector3.INF


static func _background(track: RaceTrack, out: Dictionary, rng: RandomNumberGenerator, statues: Array, spots: Dictionary) -> void:
	# Prédios em ruínas (blocos com arcos), torres, grupos de colunas e aquedutos
	for n in 70:
		var pos := _free_spot(track, rng, 520.0, 40.0)
		if pos == Vector3.INF:
			continue
		var parts := _bucket(out, pos)
		var kind := rng.randi() % 4
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		match kind:
			0:
				_ruined_building(parts[0], parts[1], parts[2], pos, basis, rng)
				SeaFloor.claim(pos, 24.0, pos.y + 26.0)
				spots.get_or_add("building", []).append(pos)
			1:
				_tower(parts[0], parts[1], pos, rng)
				SeaFloor.claim(pos, 11.0, pos.y + 40.0)
				spots.get_or_add("tower", []).append(pos)
			2:
				for c in rng.randi_range(4, 9):
					var at := pos + basis * Vector3(rng.randf_range(-14, 14), 0.0, rng.randf_range(-14, 14))
					# (cada coluna no chão do seu lugar, um pouco enterrada: nas dunas elas flutuavam)
					at.y = SeaFloor.ground(track, at.x, at.z) - 0.3
					column(parts[0], at, rng.randf_range(9.0, 16.0), rng.randf_range(0.7, 1.1), rng.randf_range(0.2, 0.8) if rng.randf() < 0.5 else 0.0)
				SeaFloor.claim(pos, 18.0, pos.y + 17.0)
			3:
				var len := rng.randf_range(70.0, 160.0)
				var a := pos - basis.x * len * 0.5
				var b := pos + basis.x * len * 0.5
				a.y = pos.y - 2.0
				b.y = pos.y - 2.0
				var top := aqueduct(parts[0], parts[1], parts[2], a, b, rng.randf_range(14.0, 22.0), rng)
				for u in int(len / 14.0) + 1:
					SeaFloor.claim(a.lerp(b, u * 14.0 / len), 9.0, top)
	# Estátuas espalhadas (cabeça da deusa, Poseidon sentado)
	for model: String in ["goddess_head", "poseidon_seated", "goddess_head", "poseidon_standing"]:
		var pos := _free_spot(track, rng, 260.0, 30.0)
		if pos != Vector3.INF:
			statues.append([model, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.2, 1.8)), pos)])
			SeaFloor.claim(pos, 10.0, pos.y + 20.0)


static func _ruined_building(mb: MeshBuilder, lamps: MeshBuilder, banners: MeshBuilder, pos: Vector3, basis: Basis,
		rng: RandomNumberGenerator) -> void:
	var w := rng.randf_range(18.0, 34.0)
	var d := rng.randf_range(14.0, 26.0)
	var h := rng.randf_range(10.0, 24.0)
	mb.box(Transform3D(basis, pos + Vector3.UP * 0.8), Vector3(w + 4.0, 1.6, d + 4.0), STONE_DARK)
	# Quatro paredes com arcos (uma mais baixa, quebrada)
	var corners := [Vector3(-w, 0, -d), Vector3(w, 0, -d), Vector3(w, 0, d), Vector3(-w, 0, d)]
	for k in 4:
		var a: Vector3 = pos + basis * (corners[k] * 0.5) + Vector3.UP * 1.6
		var b: Vector3 = pos + basis * (corners[(k + 1) % 4] * 0.5) + Vector3.UP * 1.6
		var top := h * (0.55 if k == 2 else 1.0)
		arcade(mb, a, b, 0.0, top, maxi(int(a.distance_to(b) / 7.0), 2), top * 0.3, 1.4)
	# Pedaços do telhado caído dentro, blocos soltos no chão em volta e, às vezes, a escadaria e um
	# frontão quebrado na frente
	for k in rng.randi_range(3, 6):
		var at := pos + basis * Vector3(rng.randf_range(-w, w) * 0.4, 0.0, rng.randf_range(-d, d) * 0.4)
		var tilt := Basis(Vector3(rng.randf() - 0.5, 0.0, rng.randf() - 0.5).normalized(), rng.randf_range(0.2, 0.7))
		mb.box(Transform3D(basis * tilt, at + Vector3.UP * 2.2), Vector3(rng.randf_range(3.0, 6.0), 0.8, rng.randf_range(2.0, 4.0)), STONE)
	for k in rng.randi_range(4, 8):
		var a := rng.randf() * TAU
		var at := pos + Vector3(cos(a) * (w * 0.6 + rng.randf_range(1.0, 5.0)), 0.0, sin(a) * (d * 0.6 + rng.randf_range(1.0, 5.0)))
		var sz := rng.randf_range(0.8, 1.8)
		mb.box(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)), at + Vector3.UP * sz * 0.4),
			Vector3(sz * 1.6, sz, sz), STONE_DARK if k % 2 == 0 else STONE)
	if rng.randf() < 0.55:
		var front := pos + basis * Vector3(0, 0, d * 0.5)
		for k in 3:
			mb.box(Transform3D(basis, front + basis * Vector3(0, 0.3 + k * 0.6, 1.6 - k * 0.8)), Vector3(w * 0.5 - k * 1.2, 0.6, 1.6), STONE_DARK)
		# Frontão quebrado: metade do triângulo sobre a parede da frente
		var apex := pos + basis * Vector3(0, h + 1.6 + w * 0.12, d * 0.5)
		var l := pos + basis * Vector3(-w * 0.5, h + 1.6, d * 0.5)
		var m := pos + basis * Vector3(0, h + 1.6, d * 0.5)
		mb.tri(l, m, apex, STONE, basis.z)
		mb.tri(l, apex, m, STONE_DARK, -basis.z)
	if rng.randf() < 0.6:
		var c := pos + basis * Vector3(0, 0, d * 0.5 + 0.8) + Vector3.UP * (h - 0.5)
		add_banner(banners, c, basis.x, basis.z, 2.4, 6.5)
	if rng.randf() < 0.7:
		lantern(mb, lamps, pos + basis * Vector3(w * 0.5 + 0.9, 0, d * 0.5 + 0.9) + Vector3.UP * (h * 0.5))


## Torre redonda em ruínas: base em talude, o corpo com faixas de pedra (cornijas) a cada andar,
## janelas em arco escuras em volta, as ameias com algumas faltando, blocos caídos no pé e a lanterna.
static func _tower(mb: MeshBuilder, lamps: MeshBuilder, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var r := rng.randf_range(5.0, 9.0)
	var h := rng.randf_range(22.0, 38.0)
	mb.cylinder(Transform3D(Basis(), pos + Vector3.DOWN * 2.0), r * 1.15, r, h * 0.3, STONE_DARK, 16)
	mb.cylinder(Transform3D(Basis(), pos + Vector3.UP * (h * 0.3 - 2.0)), r, r * 0.9, h * 0.7, STONE, 16)
	# Cornijas a cada andar e as janelas em arco (a abertura escura rente à parede, com o arco por cima)
	var floors := int(h / 8.0)
	for f in range(1, floors):
		var y := h * 0.3 - 2.0 + f * (h * 0.7) / floors
		var rr := lerpf(r, r * 0.9, float(f) / floors)
		mb.cylinder(Transform3D(Basis(), pos + Vector3.UP * (y - 0.3)), rr + 0.45, rr + 0.45, 0.6, STONE_DARK, 16)
		for k in 4:
			var a := TAU * (k + 0.5 * (f % 2)) / 4.0
			var out := Vector3(cos(a), 0.0, sin(a))
			var at := pos + out * (rr + 0.05) + Vector3.UP * (y + 2.6)
			var b := Basis.looking_at(out)
			mb.box(Transform3D(b, at), Vector3(1.4, 2.6, 0.2), Color(0.05, 0.1, 0.14))
			mb.box(Transform3D(b, at + Vector3.UP * 1.55 + out * 0.1), Vector3(2.0, 0.4, 0.4), STONE_DARK)
	# Ameias (algumas faltando) e blocos caídos no pé
	for k in 10:
		if rng.randf() < 0.25:
			continue
		var a := TAU * k / 10.0
		mb.box(Transform3D(Basis(Vector3.UP, -a), pos + Vector3(cos(a) * r * 0.85, h - 1.2, sin(a) * r * 0.85)), Vector3(1.4, 2.0, 1.0), STONE)
	for k in rng.randi_range(3, 6):
		var a := rng.randf() * TAU
		var at := pos + Vector3(cos(a), 0.0, sin(a)) * (r * 1.3 + rng.randf_range(0.5, 4.0))
		mb.box(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, rng.randf_range(-0.4, 0.4)), at + Vector3.UP * 0.5),
			Vector3(1.4, 1.0, 1.0), STONE)
	lantern(mb, lamps, pos + Vector3(r * 0.95, h * 0.62, 0.0))


## Estátuas (.glb, materiais trocados pela pedra); as que ainda não existem são puladas.
static func place_statues(root: Node3D, statues: Array) -> void:
	var mat := TrackMaterials.sea_stone("statue", false, {"moss_amount": 0.45, "coral_amount": 0.2, "panel_size": 0.0})
	for st: Array in statues:
		var path: String = MODELS + st[0] + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var scene := (load(path) as PackedScene).instantiate() as Node3D
		scene.name = "Statue_" + st[0]
		root.add_child(scene)
		scene.global_transform = st[1]
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = mat
			mi.visibility_range_end = VISIBILITY
