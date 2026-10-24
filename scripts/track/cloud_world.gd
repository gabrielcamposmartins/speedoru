class_name CloudWorld
extends RefCounted
## O céu em volta da pista fofa nas nuvens (Rainbow Raceway): um mar de nuvens de algodão-doce lá
## embaixo (layout.cloud_floor, com um fundo lilás por baixo dos furos), nuvens 3D em tons de rosa,
## lilás e branco em três camadas (abaixo, no nível da pista e altas), arco-íris gigantes saindo do mar
## de nuvens, brilhinhos piscando no ar perto da pista, pombinhas e as equipes nos boxes. O céu é
## pastel em todos os períodos (apply_mood troca as cores do Daylight). Nada aqui tem colisão.

const FLOOR_SIZE := 60000.0
## As nuvens no nível da pista ficam pelo menos a isso do traçado (e paradas: não cruzam a pista).
const TRACK_CLEARANCE := 120.0
## Fração da névoa normal do período (um véu pastel leve; longe some no rosa).
const FOG := 0.4
## Exposição e brilho (bloom) em relação aos do período: o céu e as cores claras lavavam a imagem.
const EXPOSURE := 0.84
const GLOW := 0.4
## Perspectiva aérea (o longe puxado para a cor do céu: as ilhas sumiam no lilás) e um pouco mais de
## saturação. O ambiente volta ao que era quando a pista sai da árvore (_EnvKeeper).
const AERIAL := 0.22
const SATURATION := 1.16
## Por período: [topo do céu, horizonte, abaixo do horizonte, névoa, nuvem iluminada, nuvem na sombra,
## luz ambiente, força do arco-íris].
const MOODS := {
	DaylightPresets.TimeOfDay.DAY: [Color(0.24, 0.48, 1.0), Color(1.0, 0.72, 0.88), Color(0.86, 0.66, 0.95), Color(0.98, 0.78, 0.92),
		Color(1.0, 0.98, 1.0), Color(0.74, 0.6, 0.95), Color(0.94, 0.82, 0.94), 0.6],
	DaylightPresets.TimeOfDay.SUNSET: [Color(0.4, 0.32, 0.78), Color(1.0, 0.6, 0.6), Color(0.75, 0.5, 0.75), Color(1.0, 0.68, 0.7),
		Color(1.0, 0.78, 0.72), Color(0.62, 0.46, 0.78), Color(0.95, 0.74, 0.8), 0.38],
	DaylightPresets.TimeOfDay.NIGHT: [Color(0.05, 0.03, 0.18), Color(0.3, 0.16, 0.44), Color(0.17, 0.1, 0.28), Color(0.2, 0.12, 0.32),
		Color(0.46, 0.38, 0.68), Color(0.17, 0.12, 0.32), Color(0.5, 0.44, 0.78), 0.12],
}

static var _floor: ShaderMaterial
static var _rainbows: Array[ShaderMaterial] = []
static var _clouds: Array[ShaderMaterial] = []


## Começo da geração da pista: esquece os materiais da geração anterior (arco-íris e nuvens que o
## apply_mood ajusta).
static func reset() -> void:
	_rainbows.clear()
	_clouds.clear()


## Arco-íris de outra parte do cenário (cachoeiras, arcos) que também segue o período do dia.
static func register_rainbow(mat: ShaderMaterial) -> void:
	_rainbows.append(mat)


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "CloudWorld"
	parent.add_child(root)
	var bounds := track.path.bounds()
	var center := Vector3(bounds.get_center().x, 0.0, bounds.get_center().y)
	var radius := bounds.size.length() * 0.5
	_cloud_sea(track, root, center)
	var animator := SceneryAnimator.new()
	animator.name = "Animator"
	root.add_child(animator)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5521
	_sky_clouds(track, root, animator, rng, center, radius)
	_sky_rainbows(track, root, rng, center, radius)
	_sparkles(track, root, rng)
	_hot_air_balloons(track, root, animator, rng, center, radius)
	TrackLife._birds(track, null, rng, root, animator)
	TrackLife._garage_crews(track, rng, root)
	var keeper := _EnvKeeper.new()
	keeper.name = "EnvKeeper"
	root.add_child(keeper)


## Mar de nuvens: o tapete (cloud_deck.gdshader, bem fechado e em tons pastel) e um fundo lilás logo
## abaixo dele (aparece pelos furos).
static func _cloud_sea(track: RaceTrack, root: Node3D, center: Vector3) -> void:
	var y := track.layout.cloud_floor
	var h := FLOOR_SIZE * 0.5
	var mb := MeshBuilder.new()
	mb.quad(Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h), Color.WHITE, Vector3.UP)
	var plane := mb.commit()
	_floor = ShaderMaterial.new()
	_floor.shader = load("res://shaders/track/cloud_deck.gdshader")
	_floor.set_shader_parameter("center", center)
	_floor.set_shader_parameter("coverage", 0.8)
	_floor.set_shader_parameter("scale", 650.0)
	var sea := CloudLook.add_mesh(root, "CloudSea", plane, _floor)
	sea.position = center + Vector3.UP * y
	var under := StandardMaterial3D.new()
	under.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	under.albedo_color = Color(0.62, 0.56, 0.95)
	under.disable_fog = false
	var base := CloudLook.add_mesh(root, "CloudSeaBase", plane, under)
	base.position = center + Vector3.UP * (y - 60.0)
	base.set_meta("material", under)


## Nuvens 3D (as fofas do CloudLook) em três camadas: abaixo e no alto levadas pelo vento; no nível da
## pista, paradas e longe do traçado. Três tons: branco, rosa e lilás.
static func _sky_clouds(track: RaceTrack, root: Node3D, animator: SceneryAnimator, rng: RandomNumberGenerator,
		center: Vector3, radius: float) -> void:
	var tones := [[Color(1.0, 0.99, 1.0), Color(0.88, 0.78, 0.98)], [Color(1.0, 0.9, 0.95), Color(0.95, 0.68, 0.86)],
		[Color(0.96, 0.92, 1.0), Color(0.74, 0.66, 0.96)]]
	var mats: Array[ShaderMaterial] = []
	for tone in tones:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/cloud.gdshader")
		mat.set_shader_parameter("lit_color", tone[0])
		mat.set_shader_parameter("shade_color", tone[1])
		mat.set_shader_parameter("night_floor", CloudLook.NIGHT_FLOOR)
		mat.set_shader_parameter("night_glow", CloudLook.NIGHT_GLOW)
		mats.append(mat)
		_clouds.append(mat)
	var meshes: Array[ArrayMesh] = []
	for v in 3:
		meshes.append(CloudLook.puff_mesh(10 + v, 8 + v * 3, true, 1))
	var floor_y := track.layout.cloud_floor
	# [nome, quantidade, altura mín, máx, escala mín, máx, raio da área, animadas]
	var layers := [
		["Below", 160, floor_y + 20.0, floor_y + 160.0, 60.0, 170.0, radius + 4000.0, true],
		["Mid", 60, floor_y + 160.0, -90.0, 40.0, 110.0, radius + 3000.0, true],
		["Level", 46, -30.0, 90.0, 26.0, 70.0, radius + 1500.0, false],
		["High", 50, 380.0, 1100.0, 60.0, 160.0, radius + 5500.0, true],
	]
	for layer in layers:
		var area: float = layer[6]
		var lists: Array = []
		for t in 9:
			lists.append([] as Array[Transform3D])
		var placed := 0
		var tries := 0
		while placed < layer[1] and tries < layer[1] * 30:
			tries += 1
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf_range(0.02, 1.0)) * area
			var pos := Vector3(center.x + cos(a) * r, rng.randf_range(layer[2], layer[3]), center.z + sin(a) * r)
			var s := rng.randf_range(layer[4], layer[5])
			if not layer[7] and absf(track.path.project(pos, true, false).y) < TRACK_CLEARANCE + s:
				continue
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.55, 0.9), s))
			(lists[placed % 9] as Array[Transform3D]).append(Transform3D(basis, pos))
			placed += 1
		for t in 9:
			var list: Array[Transform3D] = lists[t]
			var mmi := CloudLook.add_multimesh(root, "Clouds%s%d" % [layer[0], t], meshes[t % 3], list, mats[t / 3])
			if mmi == null:
				continue
			if layer[7]:
				mmi.custom_aabb = AABB(Vector3(-30000, -3000, -30000), Vector3(60000, 6000, 60000))
				animator.add_clouds(mmi.multimesh, list, Vector2(center.x, center.z), area)


## Arco-íris gigantes saindo do mar de nuvens, longe da pista e virados para o meio dela.
static func _sky_rainbows(track: RaceTrack, root: Node3D, rng: RandomNumberGenerator, center: Vector3, radius: float) -> void:
	var shader := load("res://shaders/track/rainbow.gdshader")
	var floor_y := track.layout.cloud_floor
	var count := 5
	for k in count:
		var a := TAU * (k + rng.randf_range(0.1, 0.6)) / count
		var dist := radius + rng.randf_range(900.0, 2600.0)
		var r := rng.randf_range(520.0, 950.0)
		var width := r * rng.randf_range(0.09, 0.13)
		var base := center + Vector3(cos(a), 0.0, sin(a)) * dist + Vector3.UP * (floor_y + 40.0)
		var to_center := (center - base)
		to_center.y = 0.0
		var face := to_center.normalized()
		var right := Vector3.UP.cross(face).normalized()
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("intensity", 0.55)
		_rainbows.append(mat)
		var mesh := arc_mesh(r, width, 48, 0.96)
		var mi := CloudLook.add_mesh(root, "SkyRainbow%d" % k, mesh, mat)
		mi.global_transform = Transform3D(Basis(right, Vector3.UP, face), base)
		mi.extra_cull_margin = r


## Faixa em arco num plano vertical (x para o lado, y para cima), do pé esquerdo ao direito: raio
## externo `r`, largura `width`; `span` = fração da meia-volta (1 = semicírculo). UV.x 0..1 ao longo do
## arco, UV.y 0 (borda de dentro) .. 1 (de fora), como o rainbow.gdshader espera.
static func arc_mesh(r: float, width: float, segments := 48, span := 1.0) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var a0 := PI * 0.5 * (1.0 - span)
	for k in segments:
		var t0 := float(k) / segments
		var t1 := float(k + 1) / segments
		var b0 := PI - a0 - (PI - 2.0 * a0) * t0
		var b1 := PI - a0 - (PI - 2.0 * a0) * t1
		var o0 := Vector3(cos(b0), sin(b0), 0.0)
		var o1 := Vector3(cos(b1), sin(b1), 0.0)
		mb.quad(o0 * (r - width), o1 * (r - width), o1 * r, o0 * r, Color.WHITE, Vector3.BACK,
			Vector2(t0, 0), Vector2(t1, 0), Vector2(t1, 1), Vector2(t0, 1))
	return mb.commit()


## Brilhinhos piscando no ar em volta da pista (sparkle.gdshader), em pedaços para o recorte.
static func _sparkles(track: RaceTrack, root: Node3D, rng: RandomNumberGenerator) -> void:
	var p := track.path
	var mat := sparkle_material()
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var colors := [Color(1.0, 0.95, 0.75), Color(1.0, 0.75, 0.9), Color(0.8, 0.85, 1.0), Color(1.0, 1.0, 1.0)]
	var per := 400.0
	var chunks := int(ceil(p.length / per))
	for c in chunks:
		var xfs: Array[Transform3D] = []
		var cols: Array[Color] = []
		for k in 70:
			var s := (c + rng.randf()) * per
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var lat := side * rng.randf_range(16.0, 70.0)
			var pos := p.frame_at(s, lat, rng.randf_range(3.0, 30.0)).origin
			xfs.append(Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.7, 2.2)), pos))
			cols.append(colors[rng.randi() % colors.size()])
		CloudLook.add_multimesh(root, "Sparkles%d" % c, quad, xfs, mat, 700.0, cols)


## Balões de ar quente em volta da pista (longe dela, passeando devagar com o SceneryAnimator):
## bolha de gomos em duas cores pastel ou em forma de coração, cesto de vime, cordas e a chama acesa.
const HOT_AIR := 14


static func _hot_air_balloons(track: RaceTrack, root: Node3D, animator: SceneryAnimator, rng: RandomNumberGenerator,
		center: Vector3, radius: float) -> void:
	var holder := Node3D.new()
	holder.name = "HotAirBalloons"
	root.add_child(holder)
	var mat := TrackMaterials.candy_plastic("hot_air", false, true, 0.0, {"sparkle": 0.0})
	var flame := CloudLook.glow(1.6, 3.2)
	var placed := 0
	var tries := 0
	while placed < HOT_AIR and tries < 300:
		tries += 1
		var a := rng.randf() * TAU
		var r := radius * rng.randf_range(0.2, 1.4)
		var pos := Vector3(center.x + cos(a) * r, rng.randf_range(45.0, 140.0), center.z + sin(a) * r)
		# (passeiam 60 m para cada lado: ficam longe da pista e das ilhas grandes)
		if absf(track.path.project(pos, true, false).y) < 190.0:
			continue
		var scale := rng.randf_range(0.8, 1.3)
		var mb := MeshBuilder.new()
		var glow := MeshBuilder.new()
		var col_a := CloudLook.pick(rng, CloudLook.RAINBOW)
		var col_b := CloudLook.pick(rng, [Color.WHITE, CloudLook.CREAM, CloudLook.PINK, CloudLook.BUTTER])
		if placed % 4 == 3:
			# Coração estufado
			CloudProps._puffy_heart(mb, Transform3D(Basis(), Vector3(0, 14.0, 0)), 18.0, CloudLook.HOT_PINK)
		else:
			_envelope(mb, col_a, col_b)
		# Cordas, cesto e chama
		for k in 4:
			var ang := TAU * (k + 0.5) / 4.0
			var top := Vector3(cos(ang) * 3.2, 5.2, sin(ang) * 3.2)
			var low := Vector3(cos(ang) * 0.9, 0.4, sin(ang) * 0.9)
			var dir := (top - low).normalized()
			var x := dir.cross(Vector3.FORWARD).normalized()
			mb.cylinder(Transform3D(Basis(x, dir, x.cross(dir)).orthonormalized(), low), 0.04, 0.04, top.distance_to(low), Color(0.9, 0.85, 0.8), 4, false)
		mb.box(Transform3D(Basis(), Vector3(0, -0.3, 0)), Vector3(1.9, 1.4, 1.9), Color(0.82, 0.6, 0.42), Color(0.7, 0.5, 0.36))
		mb.box(Transform3D(Basis(), Vector3(0, 0.45, 0)), Vector3(2.0, 0.18, 2.0), CloudLook.pick(rng, CloudLook.RAINBOW))
		glow.blob(Vector3(0, 1.6, 0), Vector3(0.35, 0.7, 0.35), Color(1.0, 0.7, 0.3), 8, 5)
		var node := Node3D.new()
		node.name = "Balloon%d" % placed
		holder.add_child(node)
		node.position = pos
		node.scale = Vector3.ONE * scale
		var mesh := mb.commit(null, mat)
		glow.commit(mesh, flame)
		CloudLook.add_mesh(node, "Mesh", mesh, null, 4000.0)
		animator.add_balloon(node, pos, rng.randf() * TAU)
		placed += 1
	holder.set_meta("count", placed)


## Bolha do balão de ar quente (gota de ponta para baixo) em 16 gomos alternando duas cores, com a
## boca aberta embaixo (y = 5,2) e o topo a ~24 m.
static func _envelope(mb: MeshBuilder, col_a: Color, col_b: Color) -> void:
	var gores := 16
	var prof := PackedVector2Array()
	for k in 15:
		var t := k / 14.0
		var y := lerpf(5.2, 24.0, t)
		var r := 9.5 * sin(PI * pow(t, 0.72)) * (1.0 - 0.15 * t) + 1.3 * (1.0 - t)
		prof.append(Vector2(r, y))
	prof.append(Vector2(0.0, 24.2))
	for g in gores:
		var a0 := TAU * g / gores
		var a1 := TAU * (g + 1) / gores
		var col := col_a if g % 2 == 0 else col_b
		for k in prof.size() - 1:
			var p0 := prof[k]
			var p1 := prof[k + 1]
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v10 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v01 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			var mid := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
			var nrm := mid * (p1.y - p0.y) + Vector3.UP * (p0.x - p1.x)
			mb.quad(v00, v10, v11, v01, col, nrm)


static var _sparkle: ShaderMaterial


static func sparkle_material() -> ShaderMaterial:
	if _sparkle == null:
		_sparkle = ShaderMaterial.new()
		_sparkle.shader = load("res://shaders/track/sparkle.gdshader")
	return _sparkle


## Período do dia: céu pastel (topo, horizonte e abaixo dele), névoa rosada, luz ambiente puxada para o
## rosa, cores das nuvens (do céu, do mar de nuvens e das 3D) e a força dos arco-íris.
static func apply_mood(track: RaceTrack, time_of_day: int) -> void:
	var m: Array = MOODS[time_of_day]
	var t: Dictionary = DaylightPresets.TIMES[time_of_day]
	if _floor:
		_floor.set_shader_parameter("lit_color", (m[4] as Color))
		_floor.set_shader_parameter("shade_color", (m[5] as Color))
	for mat in _rainbows:
		if mat:
			mat.set_shader_parameter("intensity", m[7])
	var dim := 1.0 if time_of_day == DaylightPresets.TimeOfDay.DAY else (0.85 if time_of_day == DaylightPresets.TimeOfDay.SUNSET else 0.8)
	for k in _clouds.size():
		if _clouds[k]:
			var lit: Color = _clouds[k].get_shader_parameter("lit_color")
			_clouds[k].set_meta("lit0", _clouds[k].get_meta("lit0", lit))
			_clouds[k].set_shader_parameter("lit_color", (_clouds[k].get_meta("lit0") as Color).lerp(m[4], 0.5) * dim)
	var base := track.find_child("CloudSeaBase", true, false) as MeshInstance3D
	if base and base.has_meta("material"):
		(base.get_meta("material") as StandardMaterial3D).albedo_color = (m[0] as Color).lerp(m[5], 0.45)
	if not track.is_inside_tree():
		return
	var daylight := track.get_tree().get_first_node_in_group("daylight") as Node3D
	if daylight == null:
		return
	var we := daylight.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		var env := we.environment
		env.fog_density = t.fog_density * Daylight.FOG_SCALE * FOG
		env.fog_light_color = m[3]
		var keeper := track.find_child("EnvKeeper", true, false) as _EnvKeeper
		if keeper:
			keeper.save(env)
		env.tonemap_exposure = t.exposure * EXPOSURE
		env.glow_intensity = t.glow * GLOW
		env.fog_aerial_perspective = AERIAL
		env.adjustment_enabled = true
		env.adjustment_saturation = SATURATION
		env.ambient_light_color = m[6]
		if env.sky:
			var sky := env.sky.sky_material as ShaderMaterial
			if sky:
				sky.set_shader_parameter("top_color", m[0])
				sky.set_shader_parameter("horizon_color", m[1])
				sky.set_shader_parameter("ground_color", m[2])
				sky.set_shader_parameter("cloud_lit", m[4])
				sky.set_shader_parameter("cloud_shade", m[5])
	var mist := daylight.get_node_or_null("GroundMist") as Node3D
	if mist:
		mist.position.y = track.layout.cloud_floor


## Guarda o que a pista muda no Environment do Daylight (que pode ser o mesmo recurso nas outras
## pistas) e devolve ao sair da árvore.
class _EnvKeeper extends Node:
	var _env: Environment
	var _saved := {}
	const KEYS := ["fog_aerial_perspective", "adjustment_enabled", "adjustment_saturation"]

	func save(env: Environment) -> void:
		if _env != null:
			return
		_env = env
		for k: String in KEYS:
			_saved[k] = env.get(k)

	func _ready() -> void:
		tree_exiting.connect(func() -> void:
			if _env:
				for k: String in _saved:
					_env.set(k, _saved[k]))
