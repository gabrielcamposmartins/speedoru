class_name TrackMaterials
extends RefCounted
## Materiais compartilhados do cenário (criados uma vez e reaproveitados).
## Quase toda a geometria usa cor de vértice, então poucos materiais cobrem o circuito inteiro.

static var _cache := {}
static var _textures := {}
## Pista no céu (Sky Aerobase): as construções (building() e tudo o que passa por ele: barreiras,
## boxes, arquibancadas, estruturas, túnel) viram placas de metal escuro com parafusos. O RaceTrack
## liga/desliga ao gerar cada pista.
static var metal := false
## Pista no fundo do mar (Atlantis Abyss): as construções viram pedra de Atlântida (mármore com
## musgo, coral e a cáustica da água, sea_stone.gdshader). O RaceTrack liga/desliga ao gerar.
static var marble := false
## Materiais com a cáustica da água (pedra, leito, pista): o SeaWorld troca os parâmetros conforme
## o período do dia (set_sea) em todos de uma vez.
static var _sea: Array[ShaderMaterial] = []
static var _sea_params := {}


static func _cached(key: String, maker: Callable) -> Material:
	if not _cache.has(key) or _cache[key] == null:
		_cache[key] = maker.call()
	return _cache[key]


## Piso (asfalto, zebra, cascalho, pintura): cor de vértice + granulação.
## Na pista no céu (metal) sem o sombreamento toon.
static func surface(kind: String) -> Material:
	var smooth := metal
	return _cached("surface_%s_%s" % [kind, smooth], func() -> Material:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/track_surface_smooth.gdshader" if smooth else "res://shaders/track/track_surface.gdshader")
		match kind:
			"asphalt":
				mat.set_shader_parameter("grain_strength", 0.07)
				mat.set_shader_parameter("patch_strength", 0.06)
			"kerb":
				mat.set_shader_parameter("grain_strength", 0.03)
				mat.set_shader_parameter("patch_strength", 0.02)
			"gravel":
				mat.set_shader_parameter("grain_scale", 9.0)
				mat.set_shader_parameter("grain_strength", 0.12)
				mat.set_shader_parameter("patch_strength", 0.08)
				mat.set_shader_parameter("pebble_strength", 0.6)
				mat.set_shader_parameter("normal_tex", normal_texture("gravel"))
				mat.set_shader_parameter("normal_strength", 1.4)
				mat.set_shader_parameter("normal_scale", 0.5)
			"paint":
				mat.set_shader_parameter("grain_strength", 0.03)
				mat.set_shader_parameter("patch_strength", 0.0)
				mat.render_priority = 1
		return mat)


## Normal maps procedurais (NoiseTexture2D, sem emenda):
##  "gravel" = pedrinhas (ruído celular), "grass" = chão de grama irregular (fractal).
static func normal_texture(kind: String) -> Texture2D:
	if _textures.has(kind):
		return _textures[kind]
	var noise := FastNoiseLite.new()
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.as_normal_map = true
	tex.generate_mipmaps = true
	match kind:
		"gravel":
			noise.noise_type = FastNoiseLite.TYPE_CELLULAR
			noise.frequency = 0.045
			noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_ADD
			noise.cellular_jitter = 1.0
			tex.bump_strength = 10.0
		_:
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			noise.frequency = 0.02
			noise.fractal_octaves = 4
			noise.fractal_gain = 0.6
			tex.bump_strength = 6.0
	tex.noise = noise
	_textures[kind] = tex
	return tex


const TEXTURE_DIR := "res://assets/track/textures/"


## Material texturizado das construções (shaders/track/building*.gdshader): cor de vértice +
## grão do material, manchas/escorridos e normal map de deformidades. `params` ajusta o shader.
static func building(key: String, two_sided := false, params := {}) -> Material:
	if metal:
		return metal_plate(key, two_sided, params.get("no_outline", false))
	if marble:
		return sea_stone(key, two_sided, params)
	return _cached("building_" + key, func() -> Material:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/building_two_sided.gdshader" if two_sided else "res://shaders/track/building.gdshader")
		mat.set_shader_parameter("detail_tex", load(TEXTURE_DIR + "material_detail.png"))
		mat.set_shader_parameter("grime_tex", load(TEXTURE_DIR + "grime.png"))
		mat.set_shader_parameter("normal_tex", load(TEXTURE_DIR + "deform_normal.png"))
		for k in params:
			mat.set_shader_parameter(k, params[k])
		return mat)


## Pedra de Atlântida (shaders/track/sea_stone*.gdshader): as texturas e `params` do building() mais
## o mármore, o musgo, o coral e a cáustica. A cor de vértice cinza vira mármore; cores fortes ficam.
static func sea_stone(key: String, two_sided := false, params := {}) -> Material:
	return _cached("sea_stone_%s_%s" % [key, two_sided], func() -> Material:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/sea_stone_two_sided.gdshader" if two_sided else "res://shaders/track/sea_stone.gdshader")
		mat.set_shader_parameter("detail_tex", load(TEXTURE_DIR + "material_detail.png"))
		mat.set_shader_parameter("grime_tex", load(TEXTURE_DIR + "grime.png"))
		mat.set_shader_parameter("normal_tex", load(TEXTURE_DIR + "deform_normal.png"))
		mat.set_shader_parameter("ground_dirt", 0.0)
		for k in params:
			mat.set_shader_parameter(k, params[k])
		# Sem o contorno anime nas construções do fundo do mar (pedra, ruínas, falésias, estátuas)
		mat.set_shader_parameter("no_outline", true)
		register_sea(mat)
		return mat)


## Bronze de Atlântida (shaders/track/sea_bronze.gdshader): a cor de vértice é o metal (bronze, ouro),
## com pátina, frisos gravados, brilho de borda e a cáustica da água.
static func sea_bronze(key: String, params := {}) -> Material:
	return _cached("sea_bronze_%s" % key, func() -> Material:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/sea_bronze.gdshader")
		for k in params:
			mat.set_shader_parameter(k, params[k])
		register_sea(mat)
		return mat)


## Inclui um material com a cáustica (caustics.gdshaderinc) nos ajustes do SeaWorld, já com os
## valores atuais.
static func register_sea(mat: ShaderMaterial) -> void:
	if mat in _sea:
		return
	_sea.append(mat)
	for k in _sea_params:
		mat.set_shader_parameter(k, _sea_params[k])


## Troca um parâmetro da água (caustic_strength, caustic_color, water_level...) em todos os materiais
## registrados (e nos que forem criados depois).
static func set_sea(param: String, value: Variant) -> void:
	_sea_params[param] = value
	for mat in _sea:
		if mat:
			mat.set_shader_parameter(param, value)


## Placas de metal escuro com parafusos (shaders/track/metal_plate*.gdshader). A cor de vértice
## cinza/branca vira metal; cores fortes ficam (escurecidas).
static func metal_plate(key: String, two_sided := false, no_outline := false) -> Material:
	return _cached("metal_%s_%s_%s" % [key, two_sided, no_outline], func() -> Material:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/metal_plate_two_sided.gdshader" if two_sided else "res://shaders/track/metal_plate.gdshader")
		mat.set_shader_parameter("grime_tex", load(TEXTURE_DIR + "grime.png"))
		mat.set_shader_parameter("no_outline", no_outline)
		return mat)


## Estruturas em geral (barreiras, objetos, casas): concreto/pintura com juntas a cada 4 m.
static func structure() -> Material:
	return building("structure", false, {"panel_size": 4.0})


## Igual a structure(), mas visível dos dois lados (telhados finos, bandeiras, placas).
static func structure_two_sided() -> Material:
	return building("structure2", true, {"panel_size": 4.0})


## Postes, pilares e mastros: sem contorno anime (rugosidade 0, ver outline_post.gdshader).
static func plain() -> Material:
	return building("plain", false, {"no_outline": true, "detail_strength": 0.15, "grime_strength": 0.3})


## Barreiras e muretas (guard-rail, muro, blocos de proteção, muro dos boxes): sem contorno anime.
static func barrier() -> Material:
	return building("barrier", false, {"no_outline": true, "panel_size": 4.0})


## Prédio dos boxes: sem contorno, painéis de fachada de 3 m.
static func pit() -> Material:
	return building("pit", false, {"no_outline": true, "panel_size": 3.0, "grime_strength": 0.35})


## Arquibancadas: concreto mais sujo, grão mais fino, sem contorno anime.
static func stand(two_sided: bool) -> Material:
	return building("stand2" if two_sided else "stand", two_sided,
		{"detail_scale": 0.9, "grime_strength": 0.55, "panel_size": 6.0, "detail_strength": 0.26, "no_outline": true})


## Rochas: mais relevo e grão, sem sujeira de chão.
static func rock() -> Material:
	return building("rock", false, {"detail_scale": 1.2, "detail_strength": 0.35, "normal_strength": 1.1,
		"normal_scale": 0.6, "ground_dirt": 0.0, "rim_amount": 0.1, "grime_scale": 0.2})


## Vidro estilo anime (reflexo, faixas diagonais). no_outline: sem contorno (boxes).
static func glass(no_outline := false) -> Material:
	return _cached("glass_%s" % no_outline, func() -> Material:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/glass.gdshader")
		mat.set_shader_parameter("grime_tex", load(TEXTURE_DIR + "grime.png"))
		mat.set_shader_parameter("no_outline", no_outline)
		return mat)


## Vidro transparente da pista no fundo do mar (barreiras, túnel de cristal, tubo): sea_glass.gdshader.
## panel_length: comprimento de cada painel ao longo de UV.x (bordas mais visíveis).
## `params` ajusta o shader (base_alpha, rim_alpha, glow...).
static func sea_glass(panel_length := 8.0, params := {}) -> Material:
	return _cached("sea_glass_%.1f_%s" % [panel_length, str(params)], func() -> Material:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/sea_glass.gdshader")
		mat.set_shader_parameter("panel_length", panel_length)
		for k in params:
			mat.set_shader_parameter(k, params[k])
		return mat)


## Lâmpadas: emissivo com a cor de vértice.
static func lamp(energy: float) -> Material:
	return _cached("lamp_%.2f" % energy, func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.95, 0.8)
		mat.emission_energy_multiplier = energy
		return mat)


static func fence() -> Material:
	return _cached("fence", func() -> Material:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/fence.gdshader")
		return mat)


static func crowd() -> Material:
	return _cached("crowd", func() -> Material:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/crowd.gdshader")
		return mat)


static func tree() -> Material:
	return _cached("tree", func() -> Material:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/track/tree.gdshader")
		return mat)


## Anúncios: textura do atlas (UV) multiplicada pela cor de vértice.
## no_outline: rugosidade 0 (sem contorno anime, usado no prédio dos boxes).
static func ads(no_outline := false) -> Material:
	# Pista no céu: todos os anúncios em holograma (fundo transparente, letras flutuando)
	if metal:
		return TrackAds.holo_material(false)
	return _cached("ads_%s" % no_outline, func() -> Material:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = TrackAds.load_atlas()
		mat.vertex_color_use_as_albedo = true
		mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.emission_enabled = true
		mat.emission_texture = mat.albedo_texture
		mat.emission_energy_multiplier = 0.25
		mat.roughness = 0.0 if no_outline else 0.8
		return mat)

static func grass() -> Material:
	return _cached("grass", func() -> Material:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/ground_grass.gdshader")
		mat.set_shader_parameter("grid_color", Color(0.46, 0.75, 0.37))
		mat.set_shader_parameter("stripe_width", 9.0)
		return mat)
