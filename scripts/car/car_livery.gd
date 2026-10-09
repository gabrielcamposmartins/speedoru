@tool
class_name CarLivery
extends RefCounted
## Materiais toon (estilo anime) do carro.
##
## As malhas exportadas do Blender usam o nome do material como "slot" de pintura
## (Livery_Primary, Carbon, Rim...). Aqui cada slot vira um StandardMaterial3D em modo toon,
## compartilhado por todas as peças do mesmo carro: mudar uma cor atualiza o carro inteiro.
##
## A pintura (Livery_*) usa o shader car_paint: as 3 cores e o ESQUEMA (CarConfig.PAINT_SCHEMES)
## que divide as cores pela carroceria. Peças que se mexem usam a variante "#plain" (cor do slot).

## Slots de pintura do modelo (cor 1, 2 e 3).
const LIVERY_SLOTS := ["Livery_Primary", "Livery_Secondary", "Livery_Accent"]
## Malhas que se mexem em relação ao carro (o esquema "andaria" nelas): sempre a cor do slot.
const PLAIN_PREFIXES := ["Rim", "Driver", "Steering", "DRSFlap"]
const PAINT_SHADER := preload("res://shaders/car/car_paint.gdshader")

var materials: Dictionary = {}


func _init() -> void:
	materials = {
		"Livery_Primary": _paint(0, false),
		"Livery_Secondary": _paint(1, false),
		"Livery_Accent": _paint(2, false),
		"Livery_Primary#plain": _paint(0, true),
		"Livery_Secondary#plain": _paint(1, true),
		"Livery_Accent#plain": _paint(2, true),
		"Carbon": _toon(Color("2b2d36"), 0.3, 0.0, 0.25),
		"Interior": _toon(Color("454957"), 0.8, 0.0, 0.15),
		"Tire": _tire(),
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
	for slot in LIVERY_SLOTS:
		for key in [slot, slot + "#plain"]:
			var mat: ShaderMaterial = materials[key]
			mat.set_shader_parameter("color_primary", config.primary_color)
			mat.set_shader_parameter("color_secondary", config.secondary_color)
			mat.set_shader_parameter("color_accent", config.accent_color)
			mat.set_shader_parameter("scheme", clampi(config.paint_scheme, 0, CarConfig.PAINT_SCHEMES.size() - 1))
			apply_paint_finish(mat, config.paint_finish)
	_set_color("Rim", config.rim_color)
	_set_color("Helmet", config.helmet_color)
	_set_color("Suit", config.suit_color)
	_set_color("Tire_Stripe", config.compound_color())
	apply_rim_finish(materials["Rim"], config.rim_finish)


## Troca os materiais importados do .glb pelos materiais toon correspondentes.
func apply_to(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i)
				var key := src.resource_name if src else ""
				if key in LIVERY_SLOTS and _moving(mi):
					key += "#plain"
				if materials.has(key):
					mi.set_surface_override_material(i, materials[key])
	for child in root.get_children():
		apply_to(child)


## Malha que gira/se move dentro do carro (roda, volante, piloto, flap do DRS)?
static func _moving(mi: Node) -> bool:
	for prefix in PLAIN_PREFIXES:
		if str(mi.name).begins_with(prefix):
			return true
	return false


static func _paint(slot: int, plain: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PAINT_SHADER
	mat.set_shader_parameter("slot", slot)
	mat.set_shader_parameter("plain", plain)
	mat.set_shader_parameter("flake_tex", _flakes())
	apply_paint_finish(mat, 0)
	return mat


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


## Borracha dos pneus: preta e lustrosa (faixa de brilho toon mais forte e verniz fino por cima,
## como pneu novo), com borda de luz para o contorno da banda não sumir no asfalto escuro.
static func _tire() -> StandardMaterial3D:
	var mat := _toon(Color("2c2c31"), 0.2, 0.0, 0.45)
	mat.metallic_specular = 0.9
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.55
	mat.clearcoat_roughness = 0.22
	return mat


## Acabamento da pintura (shader car_paint): brilhante (padrão), metálico (flocos + verniz),
## perolado (borda clara iridescente + verniz), acetinado, fosco (sem brilho) e cromado.
## [rugosidade, metal, brilho, borda, tom da borda, verniz, rugosidade do verniz, flocos]
const PAINT_FINISH_PARAMS := [
	[0.22, 0.0, 0.6, 0.35, 0.5, 0.0, 0.1, 0.0],  # Brilhante
	[0.32, 0.65, 0.9, 0.45, 0.5, 0.7, 0.1, 0.35],  # Metálico
	[0.18, 0.3, 0.8, 0.9, 0.0, 1.0, 0.05, 0.0],  # Perolado
	[0.55, 0.1, 0.3, 0.2, 0.5, 0.0, 0.1, 0.0],  # Acetinado
	[1.0, 0.0, 0.0, 0.08, 0.5, 0.0, 0.1, 0.0],  # Fosco
	[0.06, 1.0, 1.0, 0.6, 0.5, 1.0, 0.0, 0.0],  # Cromado
]


static func apply_paint_finish(mat: ShaderMaterial, finish: int) -> void:
	var p: Array = PAINT_FINISH_PARAMS[clampi(finish, 0, PAINT_FINISH_PARAMS.size() - 1)]
	for k in 8:
		mat.set_shader_parameter(["rough", "metal", "spec", "rim_amount", "rim_tint_amount", "coat", "coat_rough",
			"flakes"][k], p[k])


# ---------------------------------------------------------------------------
# Esquemas de pintura: as mesmas contas do shader car_paint (sem suavizar a borda), para as
# prévias do Estúdio.
# ---------------------------------------------------------------------------
## Peso da cor 2 (x) e da cor 3 (y) por cima da cor 1 no ponto p do carro (espaço do carro).
static func scheme_weights(scheme: int, p: Vector3) -> Vector2:
	var on := func(d: float) -> float: return 1.0 if d > 0.0 else 0.0
	var band := func(d: float, half_w: float) -> float: return 1.0 if absf(d) < half_w else 0.0
	match scheme:
		1:
			var d := p.y - 0.40
			return Vector2(1.0 - on.call(d), band.call(d, 0.034))
		2:
			var d := absf(p.x) - 0.115
			return Vector2(band.call(d, 0.05), band.call(d, 0.07) * (1.0 - band.call(d, 0.05)))
		3:
			var d := p.z + 1.4 * (p.y - 0.35) - 0.15
			return Vector2(1.0 - on.call(d), band.call(d, 0.05))
		4:
			var d := p.z - 0.85 * absf(p.x)
			var t := (d / 1.1 - floorf(d / 1.1 + 0.5)) * 1.1
			return Vector2(band.call(t, 0.17), band.call(t, 0.21) * (1.0 - band.call(t, 0.17)))
		5:
			return Vector2(smoothstep(1.8, -2.2, p.z), 1.0 - on.call(p.y - 0.13))
		6:
			return Vector2(1.0 - on.call(p.x), band.call(p.x, 0.035))
		7:
			var tri := absf(fposmod(p.z * 0.8, 1.0) - 0.5) * 2.0
			var d := p.y - (0.30 + 0.16 * tri)
			return Vector2(1.0 - on.call(d), band.call(d, 0.034))
		8:
			var d := p.y - (0.40 + 0.06 * sin(p.z * 4.5))
			var d2 := p.y - (0.27 + 0.05 * sin(p.z * 4.5 + 1.6))
			return Vector2(1.0 - on.call(d), band.call(d2, 0.034))
		9:
			var n := 0.65 * _vnoise(p * 2.2) + 0.35 * _vnoise(p * 5.0 + Vector3.ONE * 7.3)
			return Vector2(on.call(n - 0.48) * (1.0 - on.call(n - 0.62)), on.call(n - 0.62))
		10:
			var d1 := p.z - 1.55
			var d2 := -2.2 - p.z
			return Vector2(maxf(on.call(d1), on.call(d2)), maxf(band.call(d1, 0.03), band.call(d2, 0.03)))
		11:
			var d := p.y - 0.36
			return Vector2(band.call(d, 0.075), band.call(absf(d) - 0.105, 0.022))
	return Vector2.ZERO


static func _hash3(q: Vector3) -> float:
	var v := sin(q.dot(Vector3(127.1, 311.7, 74.7))) * 43758.5453
	return v - floorf(v)


static func _vnoise(x: Vector3) -> float:
	var i := x.floor()
	var f := x - i
	f = f * f * (Vector3.ONE * 3.0 - 2.0 * f)
	var a := lerpf(lerpf(_hash3(i), _hash3(i + Vector3(1, 0, 0)), f.x), lerpf(_hash3(i + Vector3(0, 1, 0)), _hash3(i + Vector3(1, 1, 0)), f.x), f.y)
	var b := lerpf(lerpf(_hash3(i + Vector3(0, 0, 1)), _hash3(i + Vector3(1, 0, 1)), f.x), lerpf(_hash3(i + Vector3(0, 1, 1)), _hash3(i + Vector3(1, 1, 1)), f.x), f.y)
	return lerpf(a, b, f.z)


## Perfil lateral simplificado do carro: [baixo, cima] (m) na posição z, ou vazio fora do carro.
static func _side(z: float) -> Vector2:
	if z > 2.86 or z < -2.86:
		return Vector2.ZERO
	if z > 2.18:
		return Vector2(0.05, 0.30)  # asa dianteira
	if z > 1.58:
		return Vector2(0.10, lerpf(0.52, 0.30, (z - 1.58) / 0.6))  # bico
	if z > -0.6:
		return Vector2(0.08, 0.86 if absf(z + 0.05) < 0.42 else 0.62)  # monocoque e sidepods (halo)
	if z > -2.5:
		return Vector2(0.10, 1.0 if z > -1.0 else lerpf(0.55, 1.0, (z + 2.5) / 1.5))  # cobertura do motor
	return Vector2(0.27, 0.99)  # asa traseira


## Meia largura do carro visto de cima na posição z (0 = fora).
static func _half_width(z: float) -> float:
	if z > 2.86 or z < -2.86:
		return 0.0
	if z > 2.18:
		return 0.98
	if z > 1.58:
		return 0.2
	if z > 0.34:
		return 0.4
	if z > -1.6:
		return 0.76
	if z > -2.5:
		return lerpf(0.2, 0.37, (z + 2.5) / 0.9)
	return 0.5


static var _previews := {}


## Prévia de um esquema (pixel art): o carro de lado em cima e visto de cima embaixo, com a frente
## para a direita, nas três cores. Fica em cache por esquema + cores.
static func scheme_preview(scheme: int, cols: Array) -> ImageTexture:
	var key := "%d:%s:%s:%s" % [scheme, (cols[0] as Color).to_html(false), (cols[1] as Color).to_html(false),
		(cols[2] as Color).to_html(false)]
	if _previews.has(key):
		return _previews[key]
	var w := 116
	var h := 28
	var img := Image.create(w, h * 2 + 4, false, Image.FORMAT_RGBA8)
	var tire := Color(0.08, 0.08, 0.1)
	for px in w:
		var z := lerpf(-2.9, 2.9, (px + 0.5) / w)
		var prof := _side(z)
		for py in h:
			# De lado (lado esquerdo do carro, x = +0,6)
			var y := lerpf(1.0, 0.0, (py + 0.5) / h)
			var c := Color(0, 0, 0, 0)
			for wz: float in [1.72, -2.2]:
				if Vector2(z - wz, y - 0.34).length() < 0.34:
					c = tire
			if c.a == 0.0 and prof != Vector2.ZERO and y >= prof.x and y <= prof.y:
				c = _scheme_color(scheme, Vector3(0.6, y, z), cols)
			img.set_pixel(px, py, c)
			# De cima (esquerda do carro em cima), na altura do topo da carroceria
			var x := lerpf(1.0, -1.0, (py + 0.5) / h)
			var c2 := Color(0, 0, 0, 0)
			if absf(x) <= _half_width(z):
				c2 = _scheme_color(scheme, Vector3(x, prof.y, z), cols)
			img.set_pixel(px, h + 4 + py, c2)
	var tex := ImageTexture.create_from_image(img)
	if _previews.size() > 200:
		_previews.clear()
	_previews[key] = tex
	return tex


static func _scheme_color(scheme: int, p: Vector3, cols: Array) -> Color:
	if scheme == 0:
		# Clássico: aproximação das cores do modelo (corpo 1, laterais baixas 2, asas 3)
		if absf(p.z) > 2.18:
			return cols[2]
		return cols[1] if p.y < 0.3 else cols[0]
	var wv := scheme_weights(scheme, p)
	return (cols[0] as Color).lerp(cols[1], wv.x).lerp(cols[2], wv.y)


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
