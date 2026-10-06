@tool
class_name CarLivery
extends RefCounted
## Materiais toon (estilo anime) do carro.
##
## As malhas exportadas do Blender usam o nome do material como "slot" de pintura
## (Livery_Primary, Carbon, Rim...). Aqui cada slot vira um StandardMaterial3D em modo toon,
## compartilhado por todas as peças do mesmo carro: mudar uma cor atualiza o carro inteiro.

var materials: Dictionary = {}


func _init() -> void:
	materials = {
		"Livery_Primary": _toon(Color("d81e2c"), 0.22),
		"Livery_Secondary": _toon(Color("f1f2f6"), 0.22),
		"Livery_Accent": _toon(Color("12a4e8"), 0.22),
		"Carbon": _toon(Color("2b2d36"), 0.3, 0.0, 0.25),
		"Interior": _toon(Color("454957"), 0.8, 0.0, 0.15),
		"Tire": _toon(Color("2a2a2e"), 0.42, 0.0, 0.3),
		"Tire_Stripe": _toon(Color("f5c800"), 0.5),
		"Rim": _rim(Color("1b1c22")),
		"Metal": _toon(Color("b8bcc6"), 0.2, 0.8),
		"Helmet": _toon(Color("ffd21f"), 0.18),
		"Visor": _toon(Color("141a33"), 0.08, 0.5, 0.5),
		"Suit": _toon(Color("d81e2c"), 0.6),
		"Light_Red": _emissive(Color("ff2a2a"), 4.0),
		"Mirror": _toon(Color("a9c4dc"), 0.05, 0.8),
		"Screen": _emissive(Color("35f0d6"), 2.0),
	}


func update_from_config(config: CarConfig) -> void:
	if config == null:
		return
	_set_color("Livery_Primary", config.primary_color)
	_set_color("Livery_Secondary", config.secondary_color)
	_set_color("Livery_Accent", config.accent_color)
	_set_color("Rim", config.rim_color)
	_set_color("Helmet", config.helmet_color)
	_set_color("Suit", config.suit_color)
	_set_color("Tire_Stripe", config.compound_color())
	for slot in ["Livery_Primary", "Livery_Secondary", "Livery_Accent"]:
		apply_paint_finish(materials[slot], config.paint_finish)
	apply_rim_finish(materials["Rim"], config.rim_finish)


## Troca os materiais importados do .glb pelos materiais toon correspondentes.
func apply_to(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i)
				var key := src.resource_name if src else ""
				if materials.has(key):
					mi.set_surface_override_material(i, materials[key])
	for child in root.get_children():
		apply_to(child)


func _set_color(slot: String, color: Color) -> void:
	var mat = materials.get(slot)
	if mat is StandardMaterial3D:
		mat.albedo_color = color
	elif mat is ShaderMaterial:
		mat.set_shader_parameter("base_color", color)


static func _toon(color: Color, roughness := 0.3, metallic := 0.0, rim := 0.35) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mat.roughness = roughness
	mat.metallic = metallic
	mat.metallic_specular = 0.6
	if rim > 0.0:
		mat.rim_enabled = true
		mat.rim = rim
		mat.rim_tint = 0.5
	return mat


## Acabamento da pintura no material toon: brilhante (padrão), metálico (flocos + verniz),
## perolado (borda clara iridescente + verniz), acetinado, fosco (sem brilho) e cromado.
static func apply_paint_finish(mat: StandardMaterial3D, finish: int) -> void:
	mat.specular_mode = BaseMaterial3D.SPECULAR_TOON
	mat.clearcoat_enabled = false
	mat.normal_enabled = false
	mat.rim_enabled = true
	mat.rim_tint = 0.5
	match finish:
		1:  # Metálico
			mat.metallic = 0.65
			mat.roughness = 0.32
			mat.metallic_specular = 0.9
			mat.rim = 0.45
			mat.clearcoat_enabled = true
			mat.clearcoat = 0.7
			mat.clearcoat_roughness = 0.1
			mat.normal_enabled = true
			mat.normal_texture = _flakes()
			mat.normal_scale = 0.35
			mat.uv1_triplanar = true
			mat.uv1_scale = Vector3(24, 24, 24)
		2:  # Perolado
			mat.metallic = 0.3
			mat.roughness = 0.18
			mat.metallic_specular = 0.8
			mat.rim = 0.9
			mat.rim_tint = 0.0
			mat.clearcoat_enabled = true
			mat.clearcoat = 1.0
			mat.clearcoat_roughness = 0.05
		3:  # Acetinado
			mat.metallic = 0.1
			mat.roughness = 0.55
			mat.metallic_specular = 0.3
			mat.rim = 0.2
		4:  # Fosco
			mat.metallic = 0.0
			mat.roughness = 1.0
			mat.metallic_specular = 0.0
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			mat.rim = 0.08
		5:  # Cromado
			mat.metallic = 1.0
			mat.roughness = 0.06
			mat.metallic_specular = 1.0
			mat.rim = 0.6
			mat.clearcoat_enabled = true
			mat.clearcoat = 1.0
			mat.clearcoat_roughness = 0.0
		_:  # Brilhante
			mat.metallic = 0.0
			mat.roughness = 0.22
			mat.metallic_specular = 0.6
			mat.rim = 0.35


## Acabamento das rodas (shader car_rim): reflexo, brilho e rugosidade.
static func apply_rim_finish(mat: Material, finish: int) -> void:
	if not mat is ShaderMaterial:
		return
	var presets := [[0.55, 0.4, 0.2, 0.8], [0.95, 0.9, 0.05, 1.2], [0.25, 0.3, 0.5, 0.25], [0.05, 0.0, 0.9, 0.0]]
	var p: Array = presets[clampi(finish, 0, presets.size() - 1)]
	mat.set_shader_parameter("reflectivity", p[0])
	mat.set_shader_parameter("metal", p[1])
	mat.set_shader_parameter("rough", p[2])
	mat.set_shader_parameter("streak_strength", p[3])


static var _flake_tex: NoiseTexture2D


## Normal map de flocos (ruído celular fino) da pintura metálica.
static func _flakes() -> NoiseTexture2D:
	if _flake_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.frequency = 0.25
		_flake_tex = NoiseTexture2D.new()
		_flake_tex.width = 256
		_flake_tex.height = 256
		_flake_tex.seamless = true
		_flake_tex.as_normal_map = true
		_flake_tex.bump_strength = 4.0
		_flake_tex.noise = n
	return _flake_tex


## Aro da roda: metal polido com reflexo do ambiente estilo anime (shaders/car/car_rim.gdshader).
static func _rim(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/car/car_rim.gdshader")
	mat.set_shader_parameter("base_color", color)
	return mat


static func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat
