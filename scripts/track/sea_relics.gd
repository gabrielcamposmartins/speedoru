class_name SeaRelics
extends RefCounted
## O que enche o leito nos trechos abertos da pista no fundo do mar (sem cânion: SeaCanyon.open_spans),
## onde antes se via só areia e corais, dos dois lados do tubo:
##  * naufrágios de galés de Atlântida: casco de tábuas tombado e meio enterrado, com um rombo de
##    costelas à mostra, convés com tábuas faltando, aríete de bronze, popa enrolada, mastro (de pé com
##    a vela do tridente, ou quebrado com a verga caída na areia), remos e ânforas espalhadas;
##  * praças afundadas: piso de lajes (algumas faltando, a areia cobrindo as bordas), com um templo
##    redondo de cúpula meio desabada, uma fonte com estátua ou uma estátua grande no pedestal,
##    muretas de casas, escadaria, colunas caídas e lanternas ainda acesas;
##  * arcos de pedra naturais e pináculos de rocha com corais em cima;
##  * campos de ânforas com âncoras e, às vezes, um baú de moedas;
##  * estátuas gigantes tombadas ou meio enterradas (os .glb do blender/build_atlantis.py);
##  * junto do vidro, poças de vida: mariscos gigantes, estrelas-do-mar, ouriços e anêmonas.
## Perto do tubo na maioria (algumas mais longe), cada peça no seu lugar do leito (SeaFloor.claim) sem
## encostar no tubo, na laje, nos arcos nem nas outras. Em pedaços espaciais (BUCKET m) com
## visibility range. Nada tem colisão.

const BUCKET := 300.0
const VISIBILITY := 900.0
## Espaço entre as peças ao longo de cada lado dos trechos abertos e entre as poças de vida.
const STEP := Vector2(48.0, 78.0)
const POOL_STEP := Vector2(20.0, 34.0)
const WOOD := Color(0.36, 0.24, 0.15)
const WOOD_LIGHT := Color(0.47, 0.33, 0.2)
const WOOD_DARK := Color(0.2, 0.13, 0.08)
const BRONZE := Color(0.3, 0.5, 0.42)
const IRON := Color(0.24, 0.21, 0.2)
const TERRACOTTA := Color(0.68, 0.36, 0.2)
const GOLD := Color(1.0, 0.78, 0.28)
## Peças: [nome, peso no sorteio, raio ocupado (m), desnível máximo do chão embaixo (m), distância máxima
## além da borda do tubo quando é perto (m)]
const KINDS := [["wreck", 3.0, 23.0, 6.0, 12.0], ["plaza", 3.0, 21.0, 5.0, 16.0], ["arch", 1.4, 13.0, 8.0, 26.0],
	["pinnacles", 1.2, 10.0, 10.0, 26.0], ["statue", 1.2, 10.0, 8.0, 20.0], ["amphorae", 1.6, 8.0, 6.0, 20.0]]
## Estátuas: [modelo, altura total (m, mín e máx)]
const STATUES := [["goddess_head", Vector2(8.0, 12.0)], ["poseidon_face", Vector2(10.0, 15.0)],
	["poseidon_seated", Vector2(8.0, 11.0)], ["poseidon_standing", Vector2(9.0, 13.0)]]

static var _wood_mat: Material
static var _model_boxes := {}


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Relics"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3131
	var buckets := {}
	var statues: Array = []
	var counts := {}
	var spots := {}
	var points: Array = []
	for sp: Vector2 in SeaCanyon.open_spans(track):
		for side: int in [1, -1]:
			var s := sp.x + rng.randf_range(15.0, 45.0)
			while s < sp.x + sp.y - 15.0:
				var kind := _pick(rng)
				var at := _feature(track, kind, s, side, buckets, statues, rng)
				if at != Vector3.INF:
					var name: String = KINDS[kind][0]
					counts[name] = int(counts.get(name, 0)) + 1
					if not spots.has(name):
						spots[name] = []
					spots[name].append(at)
					points.append(at + Vector3.UP * 2.0)
				s += rng.randf_range(STEP.x, STEP.y)
			# Poças de vida junto do vidro
			s = sp.x + rng.randf_range(4.0, 16.0)
			while s < sp.x + sp.y:
				var pool := _pool(track, s, side, rng)
				if pool != Vector3.INF:
					counts["pool"] = int(counts.get("pool", 0)) + 1
					points.append(pool + Vector3.UP * 0.5)
				s += rng.randf_range(POOL_STEP.x, POOL_STEP.y)
	for key: Vector2i in buckets:
		_commit(root, key, buckets[key])
	AtlantisRuins.place_statues(root, statues)
	root.set_meta("counts", counts)
	root.set_meta("spots", spots)
	root.set_meta("points", PackedVector3Array(points))


static func _pick(rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for k: Array in KINDS:
		total += float(k[1])
	var r := rng.randf() * total
	for i in KINDS.size():
		r -= float(KINDS[i][1])
		if r <= 0.0:
			return i
	return 0


static func _bucket(out: Dictionary, pos: Vector3) -> Array:
	var key := Vector2i(floori(pos.x / BUCKET), floori(pos.z / BUCKET))
	if not out.has(key):
		# pedra, madeira (e barro, bronze, ferro), brilho (lanternas, ouro), estandartes
		out[key] = [MeshBuilder.new(), MeshBuilder.new(), MeshBuilder.new(), MeshBuilder.new()]
	return out[key]


static func _commit(root: Node3D, key: Vector2i, parts: Array) -> void:
	var stone: MeshBuilder = parts[0]
	var wood: MeshBuilder = parts[1]
	var lamps: MeshBuilder = parts[2]
	var banners: MeshBuilder = parts[3]
	if not stone.is_empty() or not lamps.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Relics_%d_%d" % [key.x, key.y]
		mi.mesh = stone.commit(null, TrackMaterials.sea_stone("ruins", false, {}))
		if not lamps.is_empty():
			lamps.commit(mi.mesh as ArrayMesh, SkyDeck.glow(0.0, 1.4, 3.6))
		mi.visibility_range_end = VISIBILITY
		mi.visibility_range_end_margin = 60.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	if not wood.is_empty():
		if _wood_mat == null:
			_wood_mat = TrackMaterials.sea_stone("wreck", false, {"marble_mix": 0.0, "panel_size": 0.0, "moss_amount": 0.4,
				"coral_amount": 0.3, "grime_strength": 0.6, "detail_strength": 0.4})
		var wmi := MeshInstance3D.new()
		wmi.name = "Wrecks_%d_%d" % [key.x, key.y]
		wmi.mesh = wood.commit(null, _wood_mat)
		wmi.visibility_range_end = VISIBILITY
		wmi.visibility_range_end_margin = 60.0
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wmi)
	if not banners.is_empty():
		var bmi := MeshInstance3D.new()
		bmi.name = "Sails_%d_%d" % [key.x, key.y]
		bmi.mesh = banners.commit(null, AtlantisRuins.banner_material())
		bmi.visibility_range_end = VISIBILITY
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bmi)


## Uma peça em s, do lado `side`: o lugar (perto do tubo na maioria, às vezes mais longe; até 5
## tentativas, mudando um pouco o s e a distância), as conferências (chão sem muito desnível para o
## tipo, nem no fundo da fossa nem perto da superfície, fora da rocha, do tubo e do que já ocupa o
## leito) e a montagem. Devolve o centro (INF se não coube).
static func _feature(track: RaceTrack, kind: int, s: float, side: int, buckets: Dictionary, statues: Array,
		rng: RandomNumberGenerator) -> Vector3:
	var p := track.path
	var water := track.layout.water_level
	var radius: float = KINDS[kind][2]
	var tolerance: float = KINDS[kind][3]
	var far := rng.randf() < 0.25
	for attempt in 5:
		var st := s + rng.randf_range(-12.0, 12.0) * attempt
		var i := p.index_at(st)
		var extra := rng.randf_range(45.0, 140.0) if far or attempt >= 3 else rng.randf_range(2.0, float(KINDS[kind][4]))
		var pos := p.frame_at(st, side * (SeaTube.clearance(track, i, side) + radius + extra), 0.0).origin
		var ground := _flat_ground(track, pos, radius * 0.6, tolerance)
		if ground == INF or ground < p.points[i].y - 30.0 or ground > water - 9.0:
			continue
		pos.y = ground
		if SeaCanyon.in_rock(track, pos + Vector3.UP, 1.0) or SeaFloor.claimed(pos, radius) or not _clear(track, pos, radius, 16.0):
			continue
		var parts := _bucket(buckets, pos)
		match KINDS[kind][0]:
			"wreck":
				_wreck(parts, track, pos, rng)
			"plaza":
				_plaza(parts, track, pos, radius, rng, statues)
			"arch":
				SeaFloor.claim(pos, radius, _rock_arch(track, pos, rng))
			"pinnacles":
				SeaFloor.claim(pos, radius, _pinnacles(track, pos, rng))
			"statue":
				SeaFloor.claim(pos, radius, _statue(track, pos, rng, statues))
			"amphorae":
				SeaFloor.claim(pos, radius, _amphorae(parts, track, pos, rng))
		return pos
	return Vector3.INF


## Altura do leito no centro se o chão em volta (raio r) varia menos de `tolerance` m (o mais baixo
## dos pontos: a peça entra no morro em vez de flutuar); INF se não.
static func _flat_ground(track: RaceTrack, pos: Vector3, r: float, tolerance: float) -> float:
	var low := SeaFloor.ground(track, pos.x, pos.z)
	var high := low
	for k in 8:
		var a := TAU * k / 8.0
		var g := SeaFloor.ground(track, pos.x + cos(a) * r, pos.z + sin(a) * r)
		low = minf(low, g)
		high = maxf(high, g)
	return low if high - low <= tolerance else INF


## Nada da peça (raio, altura) encosta no tubo, na laje ou nos arcos embaixo dela.
static func _clear(track: RaceTrack, pos: Vector3, radius: float, height: float) -> bool:
	for k in 12:
		var dir := Vector3(cos(TAU * k / 12.0), 0.0, sin(TAU * k / 12.0))
		for f: float in [0.08, 0.5, 1.0]:
			if SeaTube.blocked(track, pos + dir * radius + Vector3.UP * (height * f), 1.0):
				return false
	return true


## Caixa de `a` até `b` (seção t × t).
static func _beam(mb: MeshBuilder, a: Vector3, b: Vector3, t: float, color: Color) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var y := d.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.FORWARD).normalized()
	mb.box(Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5), Vector3(t, d.length() + t * 0.5, t), color)


# ---------------------------------------------------------------------------
# Naufrágio
# ---------------------------------------------------------------------------
## Galé afundada (montada no espaço dela: x = boca, y = altura, z = comprimento, proa em +z) tombada e
## meio enterrada em `pos`. Devolve a altura do topo.
static func _wreck(parts: Array, track: RaceTrack, pos: Vector3, rng: RandomNumberGenerator) -> float:
	var stone: MeshBuilder = parts[0]
	var wood: MeshBuilder = parts[1]
	var banners: MeshBuilder = parts[3]
	var hull := MeshBuilder.new()
	var length := rng.randf_range(32.0, 42.0)
	var beam := length * rng.randf_range(0.18, 0.22)
	var depth := rng.randf_range(3.4, 4.2)
	var n := 16
	var breach := 1.0 if rng.randf() < 0.5 else -1.0
	var gap_a := int(n * rng.randf_range(0.3, 0.45))
	var gap_b := gap_a + rng.randi_range(3, 5)
	# Seções ao longo do comprimento: [z, meia boca, quilha, borda]; a popa sobe mais (enrolada)
	var secs: Array = []
	for k in n:
		var t := float(k) / (n - 1)
		var w := beam * 0.5 * maxf(pow(sin(PI * t), 0.55), 0.08)
		var keel := 0.7 * pow(absf(2.0 * t - 1.0), 4.0)
		var sheer := depth + 1.5 * pow(absf(2.0 * t - 1.0), 3.0) + (1.6 * (0.15 - t) / 0.15 if t < 0.15 else 0.0)
		secs.append([(t - 0.5) * length, w, keel, sheer])
	# Perfil da seção (fração da meia boca, fração da altura), da quilha até a borda
	var prof: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.45, 0.12), Vector2(0.8, 0.35), Vector2(0.97, 0.62),
		Vector2(1.0, 0.85), Vector2(0.96, 1.0)]
	var pt := func(sec: Array, r: int, side: float) -> Vector3:
		var f: Vector2 = prof[r]
		return Vector3(side * float(sec[1]) * f.x, lerpf(sec[2], sec[3], f.y), float(sec[0]))
	# Casco: tábuas (fiadas de tons alternados, a cinta escura) por fora e por dentro; o rombo
	for k in n - 1:
		for side: float in [1.0, -1.0]:
			for r in prof.size() - 1:
				if side == breach and k >= gap_a and k < gap_b and r >= 2:
					continue
				var p00: Vector3 = pt.call(secs[k], r, side)
				var p01: Vector3 = pt.call(secs[k], r + 1, side)
				var p10: Vector3 = pt.call(secs[k + 1], r, side)
				var p11: Vector3 = pt.call(secs[k + 1], r + 1, side)
				var c := WOOD_DARK if r == 3 else (WOOD_LIGHT if r % 2 == 0 else WOOD)
				var out := Vector3(side, -0.6 + 0.35 * r, 0.0)
				hull.quad(p00, p10, p11, p01, c * rng.randf_range(0.9, 1.08), out)
				hull.quad(p00, p01, p11, p10, WOOD_DARK, -out)
	# Costelas à mostra no rombo
	for k in range(gap_a, gap_b + 1):
		for r in range(1, prof.size() - 1):
			_beam(hull, pt.call(secs[k], r, breach), pt.call(secs[k], r + 1, breach), 0.24, WOOD_DARK)
	# Quilha, convés (tábuas faltando e o buraco sobre o rombo), aríete e a popa enrolada
	_beam(hull, Vector3(0, -0.1, -length * 0.36), Vector3(0, -0.1, length * 0.36), 0.4, WOOD_DARK)
	for k in n - 1:
		if (k >= gap_a - 1 and k < gap_b + 1) or rng.randf() < 0.15:
			continue
		var a: Array = secs[k]
		var b: Array = secs[k + 1]
		var ya: float = a[3] - 0.55
		var yb: float = b[3] - 0.55
		var wa: float = a[1] * 0.93
		var wb: float = b[1] * 0.93
		hull.quad(Vector3(-wa, ya, a[0]), Vector3(wa, ya, a[0]), Vector3(wb, yb, b[0]), Vector3(-wb, yb, b[0]), WOOD_LIGHT, Vector3.UP)
		hull.quad(Vector3(-wa, ya - 0.12, a[0]), Vector3(wa, ya - 0.12, a[0]), Vector3(wb, yb - 0.12, b[0]), Vector3(-wb, yb - 0.12, b[0]),
			WOOD_DARK, Vector3.DOWN)
	var bow: Array = secs[n - 1]
	hull.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, float(bow[2]) + 0.35, float(bow[0]) - 0.4)), 0.5, 0.06, 2.4,
		BRONZE, 8)
	var stern: Array = secs[0]
	var curl := 1.3
	var c0 := Vector3(0, float(stern[3]), float(stern[0]))
	var prev := c0
	for k in range(1, 8):
		var th := -PI * 0.5 + PI * 1.5 * k / 7.0
		var q := c0 + Vector3(0, curl * sin(th) + curl, -curl * cos(th))
		_beam(hull, prev, q, 0.32, WOOD)
		prev = q
	# Remos saindo do lado de cima (o casco tomba para o rombo) e afundando na areia
	for k in range(3, n - 4, 2):
		var root: Vector3 = pt.call(secs[k], 4, -breach)
		var dir := Vector3(-breach * 0.75, -0.55, rng.randf_range(-0.25, 0.25)).normalized()
		var reach := rng.randf_range(2.0, 6.5)
		_beam(hull, root, root + dir * reach, 0.13, WOOD)
		if reach > 4.0:
			hull.box(Transform3D(Basis(Vector3.UP, rng.randf() * 0.3), root + dir * reach), Vector3(0.25, 0.08, 1.1), WOOD)
	# Mastro: de pé (com a verga e a vela do tridente) ou quebrado
	var mast_z := length * -0.05
	var standing := rng.randf() < 0.45
	var mast_h := rng.randf_range(8.5, 11.0) if standing else rng.randf_range(2.5, 4.5)
	hull.cylinder(Transform3D(Basis(), Vector3(0, 0.3, mast_z)), 0.24, 0.18, mast_h, WOOD_DARK, 8)
	if standing:
		hull.box(Transform3D(Basis(), Vector3(0, 0.3 + mast_h * 0.86, mast_z)), Vector3(beam * 1.7, 0.22, 0.22), WOOD_DARK)
	else:
		hull.cylinder(Transform3D(Basis(), Vector3(0, 0.3 + mast_h, mast_z)), 0.18, 0.02, 0.6, WOOD_DARK, 6)
	# No leito: tombado para o lado do rombo, de bico um pouco para baixo, a quilha enterrada
	var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.BACK, breach * rng.randf_range(0.12, 0.3)) \
		* Basis(Vector3.RIGHT, rng.randf_range(-0.1, 0.05))
	var xf := Transform3D(basis, pos + Vector3.DOWN * rng.randf_range(0.5, 1.1))
	wood.append(hull, xf)
	if standing:
		var yard := xf * Vector3(0, 0.3 + mast_h * 0.86, mast_z)
		AtlantisRuins.add_banner(banners, yard + Vector3.DOWN * 0.2, basis.x, basis.z, beam * 1.45, mast_h * 0.42)
	else:
		# A verga caída na areia ao lado
		var at := pos + basis.x * (-breach * rng.randf_range(4.0, 7.0)) + basis.z * rng.randf_range(-4.0, 4.0)
		at.y = SeaFloor.ground(track, at.x, at.z) + 0.15
		var along := Basis(Vector3.UP, rng.randf() * TAU) * Vector3.RIGHT
		_beam(wood, at - along * beam * 0.85, at + along * beam * 0.85, 0.24, WOOD_DARK)
	# Ânforas espalhadas, corais no convés e algas penduradas da borda, um jardim na proa
	for k in rng.randi_range(4, 8):
		var at := pos + basis.x * rng.randf_range(-beam, beam) * 1.4 + basis.z * rng.randf_range(-length, length) * 0.5
		at.y = SeaFloor.ground(track, at.x, at.z)
		_amphora_at(wood, at, rng)
	for k in 6:
		var sec: Array = secs[rng.randi_range(2, n - 3)]
		SeaReef.cluster(xf * Vector3(0, float(sec[3]) - 0.4, float(sec[0])), 1.4, rng, 2)
		SeaReef.hang(xf * pt.call(sec, prof.size() - 1, breach), rng.randf_range(1.0, 2.8), rng)
		SeaReef.moss(xf * (pt.call(sec, prof.size() - 1, -breach) + Vector3.UP * 0.05), rng.randf_range(0.6, 1.2), rng)
	var ground := func(x: float, z: float) -> float: return SeaFloor.ground(track, x, z)
	SeaReef.garden(pos + basis.z * (length * 0.62), 3.5, rng, ground)
	# Ocupa o leito: o casco (largo e baixo) e o mastro de pé (fino e alto)
	SeaFloor.claim(pos, length * 0.55 + 2.0, pos.y + depth + 3.0)
	if standing:
		SeaFloor.claim(xf * Vector3(0, 0.3, mast_z), 4.0, pos.y + mast_h + 1.0)
	return pos.y + (mast_h + 1.0 if standing else depth + 3.0)


# ---------------------------------------------------------------------------
# Praça afundada
# ---------------------------------------------------------------------------
static func _plaza(parts: Array, track: RaceTrack, center: Vector3, radius: float, rng: RandomNumberGenerator,
		statues: Array) -> float:
	var stone: MeshBuilder = parts[0]
	var lamps: MeshBuilder = parts[2]
	var r_pave := radius * rng.randf_range(0.6, 0.72)
	var tile := 1.8
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	var bury := FastNoiseLite.new()
	bury.seed = rng.randi()
	bury.frequency = 0.09
	# Lajes (algumas faltando; a areia cobre as bordas em manchas)
	var n := int(r_pave / tile)
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var local := Vector3(ix * tile, 0.0, iz * tile)
			var d := local.length()
			if d > r_pave or rng.randf() < 0.12:
				continue
			var at := center + basis * local
			if bury.get_noise_2d(at.x, at.z) * 0.5 + 0.5 < smoothstep(r_pave * 0.5, r_pave, d) * 0.95:
				continue
			at.y = SeaFloor.ground(track, at.x, at.z) + 0.06 + rng.randf_range(-0.05, 0.05)
			var c := AtlantisRuins.STONE if (ix + iz) % 2 == 0 else AtlantisRuins.STONE_DARK
			stone.box(Transform3D(basis * Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)), at), Vector3(tile - 0.14, 0.3, tile - 0.14),
				c * rng.randf_range(0.9, 1.05))
	# O que fica no meio
	var top := center.y + 6.0
	var roll := rng.randf()
	if roll < 0.45:
		top = _tholos(stone, lamps, center + Vector3.UP * 0.2, rng)
	elif roll < 0.75:
		top = _fountain(stone, center + Vector3.UP * 0.2, rng, statues)
	else:
		var ped := center + Vector3.UP * 0.2
		stone.box(Transform3D(basis, ped + Vector3.UP * 1.5), Vector3(5.5, 3.0, 5.5), AtlantisRuins.STONE_DARK)
		stone.box(Transform3D(basis, ped + Vector3.UP * 3.2), Vector3(6.2, 0.5, 6.2), AtlantisRuins.STONE)
		top = ped.y + 3.4 + _place_statue(statues, "poseidon_seated", rng.randf_range(8.0, 10.0),
			Transform3D(basis, ped + Vector3.UP * 3.45))
	# Muretas de casas em volta, a escadaria, colunas caídas e lanternas
	for h in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var at := center + Vector3(cos(a), 0, sin(a)) * r_pave * rng.randf_range(0.85, 1.15)
		_house(stone, track, at, Basis(Vector3.UP, a + PI * 0.5), rng)
	var sa := rng.randf() * TAU
	var sdir := Vector3(cos(sa), 0, sin(sa))
	for k in 4:
		var at := center + sdir * (r_pave + 0.6 + k * 0.9)
		at.y = SeaFloor.ground(track, at.x, at.z) - k * 0.3 + 0.1
		stone.box(Transform3D(Basis(Vector3.UP, -sa), at), Vector3(1.0, 0.35, 7.0), AtlantisRuins.STONE_DARK if k % 2 else AtlantisRuins.STONE)
	for k in rng.randi_range(1, 3):
		var a := rng.randf() * TAU
		var at := center + Vector3(cos(a), 0, sin(a)) * r_pave * rng.randf_range(0.3, 0.8)
		at.y = SeaFloor.ground(track, at.x, at.z) + 0.65
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5)
		stone.cylinder(Transform3D(b, at), 0.6, 0.55, rng.randf_range(2.5, 5.0), AtlantisRuins.STONE, 12)
	for k in rng.randi_range(2, 3):
		var a := TAU * k / 3.0 + rng.randf()
		var at := center + Vector3(cos(a), 0, sin(a)) * r_pave * 0.92
		at.y = SeaFloor.ground(track, at.x, at.z)
		stone.cylinder(Transform3D(Basis(), at), 0.22, 0.16, 3.6, AtlantisRuins.STONE_DARK, 8)
		AtlantisRuins.lantern(stone, lamps, at + Vector3.UP * 4.0)
	var ground := func(x: float, z: float) -> float: return SeaFloor.ground(track, x, z)
	for k in 2:
		var a := rng.randf() * TAU
		SeaReef.garden(center + Vector3(cos(a), 0, sin(a)) * r_pave * 1.05, 3.0, rng, ground)
	# Ocupa o leito: a praça (larga e baixa) e o que fica no meio (estreito e alto)
	SeaFloor.claim(center, radius, center.y + 3.5)
	SeaFloor.claim(center, 8.5, top)
	return top


## Templo redondo (tholos): base em degraus, anel de colunas (algumas quebradas), arquitrave sobre as
## inteiras e a cúpula meio desabada, com a lanterna acesa no meio. Devolve o topo.
static func _tholos(stone: MeshBuilder, lamps: MeshBuilder, at: Vector3, rng: RandomNumberGenerator) -> float:
	var r := rng.randf_range(5.0, 6.4)
	for k in 3:
		stone.cylinder(Transform3D(Basis(), at + Vector3.UP * (k * 0.45 - 0.3)), r + 1.6 - k * 0.55, r + 1.6 - k * 0.55, 0.45,
			AtlantisRuins.STONE_DARK if k == 1 else AtlantisRuins.STONE, 24)
	var floor_y := 1.05
	var cols := 10
	var h := rng.randf_range(6.5, 8.0)
	var standing: Array[bool] = []
	for k in cols:
		var a := TAU * k / cols
		var broken := rng.randf_range(0.3, 0.7) if rng.randf() < 0.3 else 0.0
		AtlantisRuins.column(stone, at + Vector3(cos(a) * r, floor_y, sin(a) * r), h, 0.45, broken)
		standing.append(broken == 0.0)
	for k in cols:
		if not standing[k] or not standing[(k + 1) % cols]:
			continue
		var a0 := TAU * k / cols
		var a1 := TAU * (k + 1) / cols
		var p0 := at + Vector3(cos(a0) * r, floor_y + h + 0.3, sin(a0) * r)
		var p1 := at + Vector3(cos(a1) * r, floor_y + h + 0.3, sin(a1) * r)
		var d := (p1 - p0).normalized()
		stone.box(Transform3D(Basis(d, Vector3.UP, d.cross(Vector3.UP)), (p0 + p1) * 0.5 + Vector3.UP * 0.4),
			Vector3(p0.distance_to(p1) + 0.5, 0.8, 1.1), AtlantisRuins.STONE)
	var top := at.y + floor_y + h + 1.2
	if standing.count(true) >= 7:
		_dome(stone, at + Vector3.UP * (floor_y + h + 1.1), r + 0.5, rng.randf() * TAU, PI * rng.randf_range(1.0, 1.4), rng)
		top += r * 0.9
	stone.cylinder(Transform3D(Basis(), at + Vector3.UP * floor_y), 0.5, 0.4, 2.2, AtlantisRuins.STONE_DARK, 10)
	AtlantisRuins.lantern(stone, lamps, at + Vector3.UP * (floor_y + 3.1))
	return top


## Cúpula meio desabada: um pedaço (sweep rad, a partir de start) da meia esfera, com a borda
## quebrada em degraus, vista por fora e por dentro.
static func _dome(stone: MeshBuilder, center: Vector3, r: float, start: float, sweep: float, rng: RandomNumberGenerator) -> void:
	var rings := 6
	var segs := 16
	for ring in rings:
		var phi0 := PI * 0.5 * ring / rings
		var phi1 := PI * 0.5 * (ring + 1) / rings
		# (a borda quebrada recua um pouco a cada anel)
		var reach := sweep * (1.0 - 0.1 * rng.randf() - 0.06 * ring)
		for k in segs:
			var a0 := start + reach * k / segs
			var a1 := start + reach * (k + 1) / segs
			var q00 := center + Vector3(cos(a0) * cos(phi0), sin(phi0), sin(a0) * cos(phi0)) * r
			var q10 := center + Vector3(cos(a1) * cos(phi0), sin(phi0), sin(a1) * cos(phi0)) * r
			var q01 := center + Vector3(cos(a0) * cos(phi1), sin(phi1), sin(a0) * cos(phi1)) * r
			var q11 := center + Vector3(cos(a1) * cos(phi1), sin(phi1), sin(a1) * cos(phi1)) * r
			var out := (q00 + q11) * 0.5 - center
			stone.quad(q00, q10, q11, q01, AtlantisRuins.STONE, out)
			stone.quad(q00, q01, q11, q10, AtlantisRuins.STONE_DARK, -out)


## Fonte: bacia redonda com o pedestal e uma estátua no meio. Devolve o topo.
static func _fountain(stone: MeshBuilder, at: Vector3, rng: RandomNumberGenerator, statues: Array) -> float:
	var prof := PackedVector2Array([Vector2(3.4, 0.0), Vector2(3.6, 0.9), Vector2(3.3, 1.05), Vector2(3.05, 0.45), Vector2(0.0, 0.35)])
	stone.lathe(Transform3D(Basis(), at), prof, AtlantisRuins.STONE, 28)
	stone.cylinder(Transform3D(Basis(), at), 0.9, 0.75, 2.4, AtlantisRuins.STONE_DARK, 12)
	var model: String = "poseidon_standing" if rng.randf() < 0.6 else "goddess_head"
	var h := _place_statue(statues, model, rng.randf_range(4.5, 6.0), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at + Vector3.UP * 2.4))
	SeaReef.cluster(at + Vector3.UP * 0.45, 2.2, rng, 5)
	return at.y + 2.4 + h


## Mureta de casa (retângulo com paredes de alturas quebradas e a porta) com a frente em `basis`.
static func _house(stone: MeshBuilder, track: RaceTrack, at: Vector3, basis: Basis, rng: RandomNumberGenerator) -> void:
	var w := rng.randf_range(6.0, 10.0)
	var d := rng.randf_range(5.0, 8.0)
	var corners := [Vector3(-w, 0, -d) * 0.5, Vector3(w, 0, -d) * 0.5, Vector3(w, 0, d) * 0.5, Vector3(-w, 0, d) * 0.5]
	for e in 4:
		var a: Vector3 = at + basis * corners[e]
		var b: Vector3 = at + basis * corners[(e + 1) % 4]
		var pieces := 4
		for k in pieces:
			# (a porta: o meio da parede da frente fica aberto)
			if e == 2 and (k == 1 or k == 2) and rng.randf() < 0.85:
				continue
			var p0 := a.lerp(b, float(k) / pieces)
			var p1 := a.lerp(b, float(k + 1) / pieces)
			var mid := (p0 + p1) * 0.5
			var h := rng.randf_range(0.6, 2.8)
			mid.y = SeaFloor.ground(track, mid.x, mid.z) + h * 0.5 - 0.3
			var dir := (p1 - p0).normalized()
			stone.box(Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), mid), Vector3(p0.distance_to(p1) + 0.3, h, 0.6),
				AtlantisRuins.STONE if k % 2 == 0 else AtlantisRuins.STONE * 0.94)
			if rng.randf() < 0.3:
				SeaReef.moss(mid + Vector3.UP * (h * 0.5), 0.7, rng)


# ---------------------------------------------------------------------------
# Rocha
# ---------------------------------------------------------------------------
## Arco de pedra natural: pedras encaroçadas encostadas umas nas outras num meio arco, as do pé
## maiores, corais em cima, um jardim embaixo e kelp em volta. Devolve o topo.
static func _rock_arch(track: RaceTrack, center: Vector3, rng: RandomNumberGenerator) -> float:
	var span := rng.randf_range(13.0, 20.0)
	var rise := rng.randf_range(8.0, 13.0)
	var yaw := rng.randf() * TAU
	var x := Vector3(cos(yaw), 0, sin(yaw))
	var count := rng.randi_range(12, 16)
	for k in count + 1:
		var a := PI * float(k) / count
		var q := center + x * (-cos(a) * span * 0.5) + Vector3.UP * (sin(a) * rise)
		var size := lerpf(3.6, 2.1, sin(a)) * rng.randf_range(0.85, 1.15)
		var b := Basis(Vector3.UP, rng.randf() * TAU).rotated(x, rng.randf_range(-0.35, 0.35))
		SeaReef.place(SeaReef.Kind.ROCK, Transform3D(b.scaled(Vector3(size, size * 0.85, size)), q - Vector3.UP * size * 0.4), rng)
	for side: float in [-1.0, 1.0]:
		var foot := center + x * side * span * 0.55
		foot.y = SeaFloor.ground(track, foot.x, foot.z)
		var size := rng.randf_range(4.0, 5.2)
		SeaReef.place(SeaReef.Kind.ROCK, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * 0.8, size)),
			foot - Vector3.UP * size * 0.3), rng)
		for k in rng.randi_range(2, 4):
			var h := minf(rng.randf_range(8.0, 15.0), track.layout.water_level - 2.0 - foot.y)
			if h > 3.0:
				var at := foot + Vector3(rng.randf_range(-4, 4), -0.3, rng.randf_range(-4, 4))
				SeaReef.place(SeaReef.Kind.KELP, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.4, h, 1.4)), at), rng)
	SeaReef.cluster(center + Vector3.UP * (rise + 1.6), 2.4, rng, 6)
	SeaReef.place(SeaReef.Kind.FAN, Transform3D(Basis(Vector3.UP, yaw + PI * 0.5).scaled(Vector3.ONE * rng.randf_range(2.4, 3.4)),
		center + Vector3.UP * (rise + 1.2)), rng)
	var ground := func(gx: float, gz: float) -> float: return SeaFloor.ground(track, gx, gz)
	SeaReef.garden(center, 4.0, rng, ground)
	return center.y + rise + 5.0


## Dois a quatro pináculos de pedras empilhadas, com um coral de mesa, leque ou esponja no topo.
static func _pinnacles(track: RaceTrack, center: Vector3, rng: RandomNumberGenerator) -> float:
	var top := center.y
	for n in rng.randi_range(2, 4):
		var a := rng.randf() * TAU
		var base := center + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 6.0)
		base.y = SeaFloor.ground(track, base.x, base.z) - 0.5
		var size := rng.randf_range(3.0, 4.2)
		var drift := Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))
		var at := base
		var stack := rng.randi_range(4, 6)
		for k in stack:
			var sz := size * (1.0 - 0.11 * k)
			SeaReef.place(SeaReef.Kind.ROCK, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sz, sz * 1.05, sz)), at), rng)
			at += Vector3.UP * sz * 0.85 + drift
		var crown: int = [SeaReef.Kind.TABLE, SeaReef.Kind.FAN, SeaReef.Kind.BARREL, SeaReef.Kind.SOFT][rng.randi() % 4]
		SeaReef.place(crown, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(2.2, 3.2)), at), rng)
		SeaReef.cluster(at - Vector3.UP * size * 0.6, size * 0.5, rng, 3)
		top = maxf(top, at.y + 3.0)
	return top


# ---------------------------------------------------------------------------
# Estátuas, ânforas, âncoras e o baú
# ---------------------------------------------------------------------------
## Estátua gigante tombada (Poseidon em pé, deitado) ou meio enterrada e inclinada.
static func _statue(track: RaceTrack, center: Vector3, rng: RandomNumberGenerator, statues: Array) -> float:
	var pick: Array = STATUES[rng.randi() % STATUES.size()]
	var model: String = pick[0]
	var size: Vector2 = pick[1]
	var target := rng.randf_range(size.x, size.y)
	var lying := model == "poseidon_standing"
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	var sink := target * rng.randf_range(0.28, 0.42)
	if lying:
		basis = basis * Basis(Vector3.RIGHT, PI * 0.5 * rng.randf_range(0.86, 0.95))
		sink = 0.6
	else:
		basis = basis * Basis(Vector3(rng.randf() - 0.5, 0.0, rng.randf() - 0.5).normalized(), rng.randf_range(0.12, 0.38))
	var h := _place_statue(statues, model, target, Transform3D(basis, center + Vector3.DOWN * sink))
	SeaReef.cluster(center, 4.5, rng, 6)
	var ground := func(gx: float, gz: float) -> float: return SeaFloor.ground(track, gx, gz)
	SeaReef.garden(center + basis.x * 6.0, 2.5, rng, ground)
	return center.y + (target * 0.45 if lying else maxf(h - sink, 2.0))


## Põe a estátua `model` com `height` m de altura total em `xf` (a escala vem da caixa do modelo).
## Devolve a altura (0 se o modelo não existe).
static func _place_statue(statues: Array, model: String, height: float, xf: Transform3D) -> float:
	var box := _model_box(model)
	if box.size.y <= 0.0:
		return 0.0
	var sc := height / box.size.y
	statues.append([model, Transform3D(xf.basis.scaled(Vector3.ONE * sc), xf.origin)])
	return height


## Caixa do modelo .glb (na escala 1), medida uma vez instanciando a cena.
static func _model_box(model: String) -> AABB:
	if _model_boxes.has(model):
		return _model_boxes[model]
	var path: String = AtlantisRuins.MODELS + model + ".glb"
	var box := AABB()
	if ResourceLoader.exists(path):
		var scene := (load(path) as PackedScene).instantiate() as Node3D
		var first := true
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			var t := Transform3D()
			var node: Node = mi
			while node != scene and node is Node3D:
				t = (node as Node3D).transform * t
				node = node.get_parent()
			var b := t * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		scene.free()
	_model_boxes[model] = box
	return box


## Campo de ânforas (deitadas e em pé, meio enterradas), uma âncora e, às vezes, um baú de moedas.
static func _amphorae(parts: Array, track: RaceTrack, center: Vector3, rng: RandomNumberGenerator) -> float:
	var wood: MeshBuilder = parts[1]
	for k in rng.randi_range(8, 15):
		var a := rng.randf() * TAU
		var at := center + Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * 6.5
		at.y = SeaFloor.ground(track, at.x, at.z)
		_amphora_at(wood, at, rng)
	var a := rng.randf() * TAU
	var anchor_at := center + Vector3(cos(a), 0, sin(a)) * rng.randf_range(2.0, 5.0)
	anchor_at.y = SeaFloor.ground(track, anchor_at.x, anchor_at.z)
	_anchor(wood, anchor_at, rng)
	if rng.randf() < 0.45:
		var chest_at := center + Vector3(cos(a + 2.0), 0, sin(a + 2.0)) * rng.randf_range(2.0, 4.5)
		chest_at.y = SeaFloor.ground(track, chest_at.x, chest_at.z)
		_chest(parts, chest_at, rng)
	SeaReef.cluster(center, 5.5, rng, 5)
	return center.y + 3.0


## Ânfora de barro em `at` (no chão): deitada e meio enterrada ou em pé, inclinada.
static func _amphora_at(mb: MeshBuilder, at: Vector3, rng: RandomNumberGenerator) -> void:
	var size := rng.randf_range(1.0, 1.5)
	var basis := Basis(Vector3.UP, rng.randf() * TAU)
	if rng.randf() < 0.65:
		basis = basis * Basis(Vector3.RIGHT, rng.randf_range(1.35, 1.75))
		at.y += size * 0.06
	else:
		basis = basis * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
		at.y -= size * rng.randf_range(0.1, 0.3)
	var c := TERRACOTTA * rng.randf_range(0.8, 1.1)
	c.a = 1.0
	var prof := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.09, 0.08), Vector2(0.24, 0.3),
		Vector2(0.3, 0.5), Vector2(0.27, 0.68), Vector2(0.14, 0.8), Vector2(0.1, 0.84), Vector2(0.1, 0.97), Vector2(0.13, 1.0),
		Vector2(0.08, 1.0), Vector2(0.0, 0.92)])
	var xf := Transform3D(basis.scaled(Vector3.ONE * size), at)
	mb.lathe(xf, prof, c, 12)
	# Alças: do gargalo ao ombro
	for side: float in [1.0, -1.0]:
		_beam(mb, xf * Vector3(side * 0.1, 0.9, 0), xf * Vector3(side * 0.25, 0.86, 0), 0.05 * size, c)
		_beam(mb, xf * Vector3(side * 0.25, 0.86, 0), xf * Vector3(side * 0.24, 0.68, 0), 0.05 * size, c)


## Âncora de ferro deitada na areia: haste, os dois braços curvos com as patas, o cepo e a argola.
static func _anchor(mb: MeshBuilder, at: Vector3, rng: RandomNumberGenerator) -> void:
	var local := MeshBuilder.new()
	local.cylinder(Transform3D(), 0.12, 0.1, 3.0, IRON, 8)
	for side: float in [-1.0, 1.0]:
		var prev := Vector3(0, 0.2, 0)
		for k in 4:
			var ang := (k + 1) / 4.0 * PI * 0.45
			var q := Vector3(side * sin(ang) * 1.1, 0.2 + (1.0 - cos(ang)) * 1.1, 0)
			_beam(local, prev, q, 0.18, IRON)
			prev = q
		local.box(Transform3D(Basis(), prev + Vector3(side * 0.1, 0.15, 0)), Vector3(0.36, 0.46, 0.12), IRON)
	local.box(Transform3D(Basis(), Vector3(0, 2.75, 0)), Vector3(0.2, 0.2, 2.1), IRON)
	var prev := Vector3(0, 3.0, 0)
	for k in range(1, 9):
		var a := TAU * k / 8.0
		var q := Vector3(sin(a) * 0.26, 3.26 - cos(a) * 0.26, 0)
		_beam(local, prev, q, 0.07, IRON)
		prev = q
	var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.BACK, PI * 0.5 * rng.randf_range(0.88, 0.96))
	mb.append(local, Transform3D(basis, at + Vector3.UP * 0.18))


## Baú de madeira com cintas de bronze, a tampa aberta e moedas de ouro brilhando dentro e em volta.
static func _chest(parts: Array, at: Vector3, rng: RandomNumberGenerator) -> void:
	var wood: MeshBuilder = parts[1]
	var lamps: MeshBuilder = parts[2]
	var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.BACK, rng.randf_range(-0.15, 0.15))
	at.y -= 0.15
	wood.box(Transform3D(basis, at + basis.y * 0.35), Vector3(1.3, 0.7, 0.8), WOOD)
	for side: float in [-1.0, 1.0]:
		wood.box(Transform3D(basis, at + basis.y * 0.35 + basis.x * side * 0.42), Vector3(0.1, 0.74, 0.84), BRONZE)
	# Tampa aberta (girada pela dobradiça de trás)
	var hinge := at + basis.y * 0.7 - basis.z * 0.4
	var lid := basis * Basis(Vector3.RIGHT, -1.9)
	wood.box(Transform3D(lid, hinge + lid * Vector3(0, 0.0, 0.4)), Vector3(1.3, 0.14, 0.8), WOOD_LIGHT)
	lamps.blob(at + basis.y * 0.72, Vector3(0.56, 0.16, 0.32), GOLD, 8, 4)
	for k in rng.randi_range(6, 11):
		var a := rng.randf() * TAU
		var c := at + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.7, 1.8) + Vector3.UP * 0.18
		lamps.cylinder(Transform3D(Basis(Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5).normalized(), rng.randf_range(0.0, 0.5)), c),
			0.09, 0.09, 0.03, GOLD, 8)


# ---------------------------------------------------------------------------
# Poças de vida junto do vidro
# ---------------------------------------------------------------------------
## Marisco gigante, estrelas-do-mar, ouriços e anêmonas a poucos metros do tubo em s. Devolve o lugar
## (INF se não coube).
static func _pool(track: RaceTrack, s: float, side: int, rng: RandomNumberGenerator) -> Vector3:
	var p := track.path
	var i := p.index_at(s)
	var pos := p.frame_at(s, side * (SeaTube.clearance(track, i, side) + rng.randf_range(2.5, 10.0)), 0.0).origin
	pos.y = SeaFloor.ground(track, pos.x, pos.z)
	if pos.y > track.layout.water_level - 3.0 or pos.y < p.points[i].y - 22.0:
		return Vector3.INF
	if SeaCanyon.in_rock(track, pos + Vector3.UP, 0.5) or SeaFloor.claimed(pos, 2.5) or SeaTube.blocked(track, pos + Vector3.UP, 1.0):
		return Vector3.INF
	SeaReef.clam(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.7)), pos), rng)
	for k in rng.randi_range(3, 7):
		var a := rng.randf() * TAU
		var at := pos + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.8, 3.2)
		at.y = SeaFloor.ground(track, at.x, at.z)
		var kind := SeaReef.Kind.STAR if rng.randf() < 0.45 else SeaReef.Kind.URCHIN
		SeaReef.place(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.5)), at), rng)
	for k in rng.randi_range(1, 3):
		var a := rng.randf() * TAU
		var at := pos + Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.0, 2.8)
		at.y = SeaFloor.ground(track, at.x, at.z)
		var kind: int = [SeaReef.Kind.ANEMONE, SeaReef.Kind.PILLAR, SeaReef.Kind.SOFT, SeaReef.Kind.ANEMONE][rng.randi() % 4]
		SeaReef.place(kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.6)), at), rng)
	SeaFloor.claim(pos, 2.2, pos.y + 1.5)
	return pos
