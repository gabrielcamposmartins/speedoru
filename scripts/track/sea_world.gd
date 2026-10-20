class_name SeaWorld
extends RefCounted
## A água em volta da pista no fundo do mar (Atlantis Abyss, TrackLayout.undersea):
##  * a superfície em layout.water_level: vista de cima, o mar (sea_surface.gdshader, no trecho
##    emerso), sem a água dentro do tubo de vidro onde ele atravessa a linha d'água; vista de baixo,
##    o espelho d'água (sea_ceiling.gdshader): pela janela de Snell o que está acima do mar — o céu de
##    verdade do período, as montanhas, as cachoeiras e os barcos, da câmera da janela do céu
##    (SkyWindow, só a camada WINDOW_LAYER) — refratado e distorcido pelas ondas, e fora dela o
##    reflexo do fundo; os barcos passando por cima (SeaBoats);
##  * SeaAtmosphere: troca névoa, céu e luz conforme a câmera está acima ou abaixo da linha d'água e,
##    quando ela sai da água, gotas na tela e o som (SeaSplash);
##  * raios de sol descendo pela água (sea_rays.gdshader), neve marinha e bolhas em volta da câmera
##    (sea_specks.gdshader, sem emissor; só do lado de fora do tubo de vidro) e a cáustica
##    sobre os pisos (sea_caustic_overlay.gdshader);
##  * SeaAudio: o som ambiente (zumbido, bolhas, baleias e as cachoeiras do Portão);
##  * apply_mood: o preset do período debaixo d'água (UNDER) e a cáustica em todos os materiais.
## Nada aqui tem colisão (o servidor pula a etapa "oceano").

const SURFACE_SIZE := 30000.0
## Camada de render do que fica acima do mar (montanhas, cachoeiras, barcos): a única que a câmera da
## janela do céu vê.
const WINDOW_LAYER := 1 << 15
## Janela do céu: tamanho da imagem e campo de visão da câmera na superfície olhando para cima.
const WINDOW_SIZE := 768
const WINDOW_FOV := 140.0
const RAY_COUNT := 150
## Distância máxima da pista dos raios de sol (m).
const RAY_REACH := 230.0

## Período (DaylightPresets.TimeOfDay) → ambiente debaixo d'água: névoa (cor, densidade, espalhamento
## da luz: quase nada, senão a névoa densa da água acende onde as luzes direcionais apontam; perspectiva
## aérea: zero, a névoa é só a cor da água), a água escurecendo com a profundidade (abaixo de
## deep_start m da linha d'água, densidade deep_density por metro: as fossas somem no escuro), luz
## ambiente, céu (topo, horizonte, chão: o que a água reflete), brilho, sol (cor, fração da energia),
## teto (janela, fundo), cáustica (força, cor), raios (força, cor) e partículas.
const UNDER := [
	{
		"fog_color": Color(0.012, 0.19, 0.32), "fog_density": 0.0034, "sun_scatter": 0.06, "aerial": 0.0,
		"deep_start": 36.0, "deep_density": 0.03,
		"ambient_color": Color(0.26, 0.56, 0.72), "ambient_energy": 0.58,
		"sky_top": Color(0.2, 0.62, 0.8), "sky_horizon": Color(0.02, 0.24, 0.38), "sky_ground": Color(0.005, 0.06, 0.12),
		"glow": 0.4, "sun_color": Color(0.74, 0.95, 1.0), "sun_energy": 0.9,
		"window": Color(0.7, 0.96, 1.0), "deep": Color(0.015, 0.2, 0.32), "mirror": Color(0.3, 0.6, 0.72), "ceiling": 1.0,
		"ceiling_sun": 8.0,
		"caustics": 0.75, "caustic_color": Color(0.7, 0.98, 1.0),
		"rays": 0.24, "ray_color": Color(0.72, 0.96, 1.0), "snow": 0.6, "bubbles": 0.85,
	},
	{
		"fog_color": Color(0.06, 0.17, 0.29), "fog_density": 0.0038, "sun_scatter": 0.05, "aerial": 0.0,
		"deep_start": 34.0, "deep_density": 0.034,
		"ambient_color": Color(0.4, 0.44, 0.66), "ambient_energy": 0.64,
		"sky_top": Color(0.62, 0.5, 0.58), "sky_horizon": Color(0.08, 0.2, 0.32), "sky_ground": Color(0.02, 0.06, 0.11),
		"glow": 0.45, "sun_color": Color(1.0, 0.76, 0.58), "sun_energy": 0.6,
		"window": Color(1.0, 0.78, 0.6), "deep": Color(0.05, 0.16, 0.27), "mirror": Color(0.36, 0.44, 0.6), "ceiling": 1.0,
		"ceiling_sun": 6.0,
		"caustics": 0.6, "caustic_color": Color(1.0, 0.82, 0.62),
		"rays": 0.22, "ray_color": Color(1.0, 0.8, 0.6), "snow": 0.55, "bubbles": 0.8,
	},
	{
		"fog_color": Color(0.014, 0.066, 0.14), "fog_density": 0.0045, "sun_scatter": 0.0, "aerial": 0.0,
		"deep_start": 30.0, "deep_density": 0.04,
		"ambient_color": Color(0.18, 0.34, 0.54), "ambient_energy": 0.62,
		"sky_top": Color(0.06, 0.14, 0.26), "sky_horizon": Color(0.01, 0.05, 0.1), "sky_ground": Color(0.0, 0.02, 0.05),
		"glow": 0.6, "sun_color": Color(0.55, 0.75, 1.0), "sun_energy": 0.8,
		"window": Color(0.12, 0.22, 0.38), "deep": Color(0.008, 0.035, 0.08), "mirror": Color(0.07, 0.13, 0.24), "ceiling": 1.0,
		"ceiling_sun": 2.0,
		"caustics": 0.18, "caustic_color": Color(0.55, 0.75, 1.0),
		"rays": 0.0, "ray_color": Color(0.5, 0.7, 1.0), "snow": 0.85, "bubbles": 0.6,
	},
]

static var _ceiling: ShaderMaterial
static var _rays: ShaderMaterial
static var _snow: ShaderMaterial
static var _bubbles: ShaderMaterial


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "SeaWorld"
	parent.add_child(root)
	var bounds := track.path.bounds()
	var center := Vector3(bounds.get_center().x, 0.0, bounds.get_center().y)
	var window := _surface(track, root, center)
	var atmosphere := SeaAtmosphere.new()
	atmosphere.name = "Atmosphere"
	atmosphere.track = track
	atmosphere.window = window
	root.add_child(atmosphere)
	# Saindo da água: gotas na tela e o som
	var splash := SeaSplash.new()
	splash.name = "Splash"
	root.add_child(splash)
	atmosphere.splash = splash
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	_sun_rays(track, root, rng)
	_specks(track, root, rng)
	atmosphere.specks.append_array([_snow, _bubbles])
	_caustic_overlay(track, root)
	SeaBoats.build(track, root)
	# Som ambiente (debaixo d'água e as cachoeiras do Portão, se houver)
	var audio := SeaAudio.new()
	audio.name = "Audio"
	audio.atmosphere = atmosphere
	var gate := parent.get_node_or_null("PoseidonGate")
	if gate and gate.has_meta("waterfalls"):
		audio.waterfalls.assign(gate.get_meta("waterfalls"))
	var vents := parent.get_node_or_null("Vents")
	if vents and vents.has_meta("vents"):
		audio.vents.assign(vents.get_meta("vents"))
	root.add_child(audio)


## Superfície: o mar visto de cima e o teto visto de baixo, no mesmo plano.
static func _surface(track: RaceTrack, root: Node3D, center: Vector3) -> SubViewport:
	var water := track.layout.water_level
	var h := SURFACE_SIZE * 0.5
	var top_mat := ShaderMaterial.new()
	top_mat.shader = load("res://shaders/track/sea_surface.gdshader")
	top_mat.set_shader_parameter("normal_a", TrackHarbour._wave_normal(0.018, 7))
	top_mat.set_shader_parameter("normal_b", TrackHarbour._wave_normal(0.05, 13))
	top_mat.set_shader_parameter("shallow_color", Color(0.1, 0.62, 0.66))
	var mb := MeshBuilder.new()
	mb.quad(Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h), Color.WHITE, Vector3.UP)
	var top := MeshInstance3D.new()
	top.name = "SeaSurface"
	top.mesh = mb.commit(null, top_mat)
	top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top.position = center + Vector3.UP * water
	root.add_child(top)
	if _ceiling == null:
		_ceiling = ShaderMaterial.new()
		_ceiling.shader = load("res://shaders/track/sea_ceiling.gdshader")
		_ceiling.set_shader_parameter("normal_a", TrackHarbour._wave_normal(0.018, 7))
		_ceiling.set_shader_parameter("normal_b", TrackHarbour._wave_normal(0.05, 13))
	# Sem água dentro do tubo de vidro onde ele atravessa a linha d'água (nos dois lados da superfície)
	var carve := SeaTube.surface_carve(track)
	for mat: ShaderMaterial in [top_mat, _ceiling]:
		mat.set_shader_parameter("carve_tex", carve[0] if not carve.is_empty() else null)
		mat.set_shader_parameter("carve_area", carve[1] if not carve.is_empty() else Vector4.ZERO)
	var under := MeshBuilder.new()
	under.quad(Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h), Color.WHITE, Vector3.DOWN)
	var ceiling := MeshInstance3D.new()
	ceiling.name = "SeaCeiling"
	ceiling.mesh = under.commit(null, _ceiling)
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ceiling.position = center + Vector3.UP * (water - 0.05)
	root.add_child(ceiling)
	# Janela do céu: câmera na superfície olhando para cima, só com o que está acima do mar (o
	# ambiente de fora d'água é dela: SeaAtmosphere); o espelho d'água procura nela o que se vê pela
	# janela de Snell. Atualizada só com a câmera debaixo d'água.
	var window := SubViewport.new()
	window.name = "SkyWindow"
	window.size = Vector2i(WINDOW_SIZE, WINDOW_SIZE)
	window.render_target_update_mode = SubViewport.UPDATE_DISABLED
	window.msaa_3d = Viewport.MSAA_DISABLED
	window.positional_shadow_atlas_size = 0
	window.mesh_lod_threshold = 4.0
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = WINDOW_FOV
	cam.near = 0.5
	cam.far = 5000.0
	cam.cull_mask = WINDOW_LAYER
	cam.attributes = CameraAttributesPractical.new()
	# (olhando para +Y; +Z do mundo para baixo na imagem)
	cam.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), center + Vector3.UP * (water + 0.3))
	window.add_child(cam)
	root.add_child(window)
	cam.current = true
	_ceiling.render_priority = -120
	_ceiling.set_shader_parameter("window_tex", window.get_texture())
	_ceiling.set_shader_parameter("window_tan", tan(deg_to_rad(WINDOW_FOV * 0.5)))
	return window


## Raios de sol: folhas cruzadas presas na superfície, descendo até o leito, perto da pista.
static func _sun_rays(track: RaceTrack, root: Node3D, rng: RandomNumberGenerator) -> void:
	if _rays == null:
		_rays = ShaderMaterial.new()
		_rays.shader = load("res://shaders/track/sea_rays.gdshader")
	_rays.set_shader_parameter("water_level", track.layout.water_level)
	var mb := MeshBuilder.new()
	for k in 2:
		var a := PI * 0.5 * k
		var x := Vector3(cos(a), 0, sin(a)) * 0.5
		mb.quad(-x, x, x + Vector3.DOWN, -x + Vector3.DOWN, Color.WHITE, Vector3(-sin(a), 0, cos(a)),
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	var p := track.path
	var water := track.layout.water_level
	var xfs: Array[Transform3D] = []
	var seeds: Array[float] = []
	var tries := 0
	while xfs.size() < RAY_COUNT and tries < RAY_COUNT * 10:
		tries += 1
		var s := rng.randf() * p.length
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var pos := p.frame_at(s, side * rng.randf_range(0.0, RAY_REACH), 0.0).origin
		# Só onde a pista está debaixo d'água (no trecho emerso não há raios dentro da água)
		if p.height_at(s) > water - 4.0:
			continue
		var bottom := SeaFloor.ground(track, pos.x, pos.z)
		var height := water - bottom
		if height < 6.0:
			continue
		var width := rng.randf_range(5.0, 16.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(width, height, width))
		xfs.append(Transform3D(basis, Vector3(pos.x, water, pos.z)))
		seeds.append(rng.randf())
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mb.commit(null, null)
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_custom_data(i, Color(seeds[i], 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "SunRays"
	mmi.multimesh = mm
	mmi.material_override = _rays
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Os raios se inclinam no shader: a caixa precisa cobrir o deslocamento
	mmi.custom_aabb = AABB(Vector3(-30000, -2000, -30000), Vector3(60000, 4000, 60000))
	root.add_child(mmi)


## Neve marinha e bolhas: um MultiMesh cada, com as posições numa caixa que o shader repete em
## volta da câmera.
static func _specks(track: RaceTrack, root: Node3D, rng: RandomNumberGenerator) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	if _snow == null:
		_snow = ShaderMaterial.new()
		_snow.shader = load("res://shaders/track/sea_specks.gdshader")
		_snow.set_shader_parameter("shape", 0)
		_snow.set_shader_parameter("box", 100.0)
		_snow.set_shader_parameter("size", 0.12)
	if _bubbles == null:
		_bubbles = ShaderMaterial.new()
		_bubbles.shader = load("res://shaders/track/sea_specks.gdshader")
		_bubbles.set_shader_parameter("shape", 1)
		_bubbles.set_shader_parameter("box", 100.0)
		_bubbles.set_shader_parameter("size", 0.28)
		_bubbles.set_shader_parameter("rise", 1.4)
		_bubbles.set_shader_parameter("color", Color(0.86, 0.97, 1.0))
	for spec: Array in [["MarineSnow", 14000, _snow], ["Bubbles", 1300, _bubbles]]:
		var mat: ShaderMaterial = spec[2]
		mat.set_shader_parameter("water_level", track.layout.water_level)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		mm.instance_count = spec[1]
		var box: float = mat.get_shader_parameter("box")
		for i in mm.instance_count:
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(rng.randf(), rng.randf(), rng.randf()) * box))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = spec[0]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-30000, -3000, -30000), Vector3(60000, 6000, 60000))
		root.add_child(mmi)


## Cáustica sobre os pisos: faixas aditivas logo acima do asfalto, de barreira a barreira, onde a
## pista está debaixo d'água.
static func _caustic_overlay(track: RaceTrack, root: Node3D) -> void:
	var p := track.path
	var mb := MeshBuilder.new()
	var water := track.layout.water_level
	var y := Vector3.UP * 0.03
	for i in p.size():
		var j := (i + 1) % p.size()
		if p.points[i].y > water - 0.5 and p.points[j].y > water - 0.5:
			continue
		var l_i := p.half_width(i, 1) + track.barrier[0][i]
		var l_j := p.half_width(j, 1) + track.barrier[0][j]
		var r_i := p.half_width(i, -1) + track.barrier[1][i] + (track.pit_width[i] if track.layout.pit_side < 0 else 0.0)
		var r_j := p.half_width(j, -1) + track.barrier[1][j] + (track.pit_width[j] if track.layout.pit_side < 0 else 0.0)
		if track.layout.pit_side > 0:
			l_i += track.pit_width[i]
			l_j += track.pit_width[j]
		mb.quad(p.points[i] - p.lefts[i] * r_i + y, p.points[i] + p.lefts[i] * l_i + y,
			p.points[j] + p.lefts[j] * l_j + y, p.points[j] - p.lefts[j] * r_j + y, Color.WHITE, Vector3.UP)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/sea_caustic_overlay.gdshader")
	TrackMaterials.register_sea(mat)
	# Na pista a rede é mais fina (o asfalto é visto de perto; com células grandes ela virava um
	# desenho de teia por cima da pista)
	mat.set_shader_parameter("caustic_scale", 0.46)
	var mi := MeshInstance3D.new()
	mi.name = "RoadCaustics"
	mi.mesh = mb.commit(null, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Período do dia: preset debaixo d'água na atmosfera, no teto, nos raios, nas partículas e na
## cáustica de todos os materiais da água.
static func apply_mood(track: RaceTrack, time_of_day: int) -> void:
	var u: Dictionary = UNDER[clampi(time_of_day, 0, UNDER.size() - 1)]
	TrackMaterials.set_sea("water_level", track.layout.water_level)
	TrackMaterials.set_sea("caustic_strength", u.caustics)
	TrackMaterials.set_sea("caustic_color", u.caustic_color)
	if _ceiling:
		# O horizonte (borda da janela de Snell) e o brilho do sol do período; o céu vem da janela
		var t: Dictionary = DaylightPresets.TIMES[clampi(time_of_day, 0, 2)]
		_ceiling.set_shader_parameter("sky_horizon", (t.sky_horizon as Color).lerp(u.window, 0.25))
		_ceiling.set_shader_parameter("sun_color", t.sun_color)
		_ceiling.set_shader_parameter("sun_strength", u.ceiling_sun)
		_ceiling.set_shader_parameter("deep_color", u.deep)
		_ceiling.set_shader_parameter("mirror_tint", u.mirror)
		_ceiling.set_shader_parameter("brightness", u.ceiling)
	if _rays:
		_rays.set_shader_parameter("intensity", u.rays)
		_rays.set_shader_parameter("ray_color", u.ray_color)
		_rays.set_shader_parameter("fade_distance", 1.0 / maxf(u.fog_density, 0.0005))
	if _snow:
		_snow.set_shader_parameter("intensity", u.snow)
	if _bubbles:
		_bubbles.set_shader_parameter("intensity", u.bubbles)
	PoseidonGate.apply_mood(time_of_day)
	SeaCanyon.apply_mood(time_of_day)
	var root := track.get_node_or_null("Generated/SeaWorld")
	var atmosphere := root.get_node_or_null("Atmosphere") as SeaAtmosphere if root else null
	if atmosphere:
		atmosphere.under = u
		atmosphere.capture()
