class_name CarEffects
extends Node3D
## Efeitos visuais do carro ligados à pilotagem:
##  * Sombra de contato: um Decal escuro sob o carro (sempre visível, também à noite e com o sol
##    baixo; a sombra do sol continua por cima). O carro fica só na camada CAR_LAYER para o
##    decal não pintar a própria carroceria.
##  * Marcas de pneu: fitas escuras no chão enquanto o carro freia forte, trava ou derrapa.
##  * Boost da bateria (F1Car.boost_active): rodas brilhando forte na cor do boost
##    (CarConfig.boost_color), luz nas rodas, rastro de luz e partículas de pó mágico.
##  * Neon embaixo do carro (CarConfig.neon_enabled / neon_color): brilho no chão (Decal emissivo),
##    luzes sob o assoalho e tubos de neon nas laterais; bem mais forte à noite.
##  * Luz traseira de F1 (lanterna central + LEDs das placas da asa): pisca quando o carro freia
##    (recuperando energia para a bateria); apagada/fraca no resto do tempo.

## Marcas: velocidade mínima (m/s) e vida (s).
@export var skid_min_speed := 7.0
@export var skid_lifetime := 45.0
@export var skid_width := 0.3
@export var shadow_opacity := 0.6

var car: F1Car
var glow := 0.0
var _skids: Array[TrailRibbon] = []
var _trails: Array[TrailRibbon] = []
var _dust: Array[GPUParticles3D] = []
var _lights: Array[OmniLight3D] = []
var _decal: Decal
var _trail_material: StandardMaterial3D
var _dust_material: StandardMaterial3D
var _color := Color.WHITE
var _time := 0.0
var _neon_decal: Decal
var _neon_lights: Array[OmniLight3D] = []
var _neon_tubes: MeshInstance3D
var _neon_material: StandardMaterial3D
var _neon := 0.0
var _brake_material: StandardMaterial3D
var _brake_light: OmniLight3D
var _brake_glow := 0.0
var _brake_flares: Array[MeshInstance3D] = []
var _flare_material: StandardMaterial3D


var _ready_done := false
## Materiais das rodas ainda com o brilho do boost (para apagá-lo uma vez quando ele acaba).
var _glow_shown := true


func _ready() -> void:
	car = get_parent() as F1Car
	if car == null or Engine.is_editor_hint():
		return
	# Os filhos ficam prontos antes do F1Car: as rodas só existem depois do _ready dele.
	_setup.call_deferred()


func _setup() -> void:
	_build_shadow()
	var skid_mat := StandardMaterial3D.new()
	skid_mat.vertex_color_use_as_albedo = true
	skid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skid_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	skid_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	skid_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	skid_mat.roughness = 1.0
	skid_mat.render_priority = 1
	_trail_material = StandardMaterial3D.new()
	_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_material.vertex_color_use_as_albedo = true
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_material.albedo_texture = _soft_line_texture()
	for i in car.get_wheels().size():
		var skid := TrailRibbon.new()
		skid.name = "SkidMark%d" % i
		skid.mode = TrailRibbon.Mode.GROUND
		skid.width = skid_width
		skid.lifetime = skid_lifetime
		skid.max_points = 700
		skid.min_spacing = 0.3
		skid.fade_start = 0.7
		skid.color = Color(0.03, 0.03, 0.035, 0.55)
		skid.material_override = skid_mat
		add_child(skid)
		_skids.append(skid)
		var trail := TrailRibbon.new()
		trail.name = "BoostTrail%d" % i
		trail.mode = TrailRibbon.Mode.BILLBOARD
		trail.width = 0.16
		trail.lifetime = 0.9
		trail.max_points = 120
		trail.min_spacing = 0.2
		trail.fade_start = 0.0
		trail.taper = true
		trail.material_override = _trail_material
		add_child(trail)
		_trails.append(trail)
		_dust.append(_make_dust())
		var light := OmniLight3D.new()
		light.name = "BoostLight%d" % i
		light.omni_range = 2.4
		light.light_energy = 0.0
		light.shadow_enabled = false
		# Ilumina o chão em volta da roda, não a carroceria (a asa "estourava" no bloom)
		light.light_cull_mask = 0xFFFFF & ~CarAssembly.OWN_LAYERS
		light.visible = false
		add_child(light)
		_lights.append(light)
	_build_neon()
	_build_brake_light()
	car.parts_ready.connect(_on_parts_ready.call_deferred)
	_on_parts_ready.call_deferred()
	_ready_done = true


func _on_parts_ready() -> void:
	_retag_layers()
	_assign_brake_material()


func _process(delta: float) -> void:
	if car == null or not _ready_done:
		return
	_time += delta
	var target := 1.0 if car.boost_active else 0.0
	glow = move_toward(glow, target, delta * (6.0 if target > glow else 2.5))
	var c: Color = car.config.boost_color if car.config else Color.CYAN
	if c != _color and _dust_material:
		_color = c
		_dust_material.albedo_color = c
	if glow > 0.0 or _glow_shown:
		_update_wheel_materials(c)
		_glow_shown = glow > 0.0
	_update_neon(delta)
	_update_brake_light(delta)
	var wheels := car.get_wheels()
	var speed := car.linear_velocity.length()
	var forward := car.global_basis.z
	for i in wheels.size():
		var wheel := wheels[i]
		var hub := wheel.global_position
		# Boost: luz, rastro e pó mágico (apagados não são mexidos)
		_lights[i].visible = glow > 0.01
		if glow > 0.01:
			_lights[i].global_position = hub
			_lights[i].light_color = c
			_lights[i].light_energy = glow * (1.6 + 0.4 * sin(_time * 18.0 + i))
		var dusting := car.boost_active and speed > 2.0
		if dusting or _dust[i].emitting:
			_dust[i].global_position = hub
			_dust[i].emitting = dusting
		if car.boost_active and speed > 1.0:
			_trails[i].color = Color(c.r, c.g, c.b, 0.9)
			_trails[i].add_point(hub - car.global_basis.y * 0.1, car.global_basis.y, forward)
		else:
			_trails[i].stop()
		# Marcas de pneu
		if _skidding(i, wheel, speed):
			var n := wheel.get_contact_normal()
			_skids[i].add_point(wheel.get_contact_point() + n * 0.012, n, forward)
		else:
			_skids[i].stop()


func _skidding(i: int, wheel: VehicleWheel3D, speed: float) -> bool:
	if not wheel.is_in_contact() or speed < skid_min_speed or car.wheel_broken[i]:
		return false
	var surface := car.tire_surface[i]
	if surface != TrackSurface.Type.ASPHALT and surface != TrackSurface.Type.KERB:
		return false
	var state := car.tire_state[i]
	if state == F1Car.TireState.LOCK or state == F1Car.TireState.SPIN:
		return true
	if state == F1Car.TireState.SLIDE and absf(car.tire_slip_deg[i]) > car.peak_slip_angle_deg * 1.5:
		return true
	return car.brake_input > 0.6 and car.tire_usage[i] > 0.93


## Brilho das rodas: emissão no pneu e no aro (materiais compartilhados do carro).
func _update_wheel_materials(c: Color) -> void:
	var mats: Dictionary = car.assembly.livery.materials
	var pulse := glow * (0.85 + 0.15 * sin(_time * 14.0))
	var tyre := mats.get("Tire") as StandardMaterial3D
	if tyre:
		tyre.emission_enabled = pulse > 0.001
		tyre.emission = c
		tyre.emission_energy_multiplier = pulse * 1.1
	var stripe := mats.get("Tire_Stripe") as StandardMaterial3D
	if stripe:
		stripe.emission_enabled = pulse > 0.001
		stripe.emission = c
		stripe.emission_energy_multiplier = pulse * 9.0
	var rim := mats.get("Rim") as ShaderMaterial
	if rim:
		rim.set_shader_parameter("glow_color", c)
		rim.set_shader_parameter("glow", pulse * 4.0)


# ---------------------------------------------------------------------------
# Texturas
# ---------------------------------------------------------------------------
static func _glow_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var r := Vector2((x + 0.5) / s * 2.0 - 1.0, (y + 0.5) / s * 2.0 - 1.0).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(pow(1.0 - r, 2.2), 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Neon embaixo do carro
# ---------------------------------------------------------------------------
func _build_neon() -> void:
	_neon_decal = Decal.new()
	_neon_decal.name = "NeonGlow"
	_neon_decal.size = Vector3(3.6, 1.2, 6.6)
	_neon_decal.position = Vector3(0, 0.35, -0.15)
	var tex := _neon_texture()
	_neon_decal.texture_albedo = tex
	_neon_decal.texture_emission = tex
	_neon_decal.albedo_mix = 0.25
	_neon_decal.emission_energy = 0.0
	_neon_decal.normal_fade = 0.2
	_neon_decal.upper_fade = 0.3
	_neon_decal.lower_fade = 0.3
	_neon_decal.cull_mask = 0xFFFFF & ~CarAssembly.OWN_LAYERS
	_neon_decal.visible = false
	add_child(_neon_decal)
	for z: float in [1.2, -0.3, -1.7]:
		var light := OmniLight3D.new()
		light.name = "NeonLight"
		light.position = Vector3(0, 0.08, z)
		light.omni_range = 3.2
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		light.light_cull_mask = 0xFFFFF & ~CarAssembly.OWN_LAYERS
		light.visible = false
		add_child(light)
		_neon_lights.append(light)
	# Tubos de neon nas bordas do assoalho (vistos de lado)
	_neon_material = StandardMaterial3D.new()
	_neon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_neon_material.emission_enabled = true
	_neon_material.emission_energy_multiplier = 3.0
	var mb := MeshBuilder.new()
	for x: float in [-0.8, 0.8]:
		mb.box(Transform3D(Basis(), Vector3(x, 0.075, -0.4)), Vector3(0.035, 0.035, 2.9), Color.WHITE)
	mb.box(Transform3D(Basis(), Vector3(0, 0.075, 1.6)), Vector3(0.5, 0.03, 0.03), Color.WHITE)
	_neon_tubes = MeshInstance3D.new()
	_neon_tubes.name = "NeonTubes"
	_neon_tubes.mesh = mb.commit()
	_neon_tubes.material_override = _neon_material
	_neon_tubes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_neon_tubes.visible = false
	add_child(_neon_tubes)


func _update_neon(delta: float) -> void:
	var enabled: bool = car.config != null and car.config.neon_enabled
	_neon = move_toward(_neon, 1.0 if enabled else 0.0, delta * 3.0)
	var on := _neon > 0.001
	_neon_decal.visible = on
	_neon_tubes.visible = on
	for light in _neon_lights:
		light.visible = on
	if not on:
		return
	var c: Color = car.config.neon_color
	var night: float = Daylight.current_night
	var flicker := 0.95 + 0.05 * sin(_time * 50.0) * sin(_time * 7.3)
	var level := _neon * flicker
	_neon_decal.modulate = c
	_neon_decal.emission_energy = level * lerpf(0.9, 4.0, night)
	for light in _neon_lights:
		light.light_color = c
		light.light_energy = level * lerpf(0.5, 2.6, night)
	_neon_material.albedo_color = c
	_neon_material.emission = c
	_neon_material.emission_energy_multiplier = level * lerpf(1.5, 4.0, night)


## Brilho oval e suave (mais largo que o carro).
static func _neon_texture() -> ImageTexture:
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var p := Vector2((x + 0.5) / w * 2.0 - 1.0, (y + 0.5) / h * 2.0 - 1.0)
			var d := Vector2(p.x / 0.85, p.y / 0.92).length()
			var a := clampf(1.0 - smoothstep(0.35, 1.0, d), 0.0, 1.0)
			# Degradê também na cor: a emissão do decal não usa o alfa da textura
			img.set_pixel(x, y, Color(a * a, a * a, a * a, a * a))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Luz traseira de F1
# ---------------------------------------------------------------------------
func _build_brake_light() -> void:
	_brake_material = StandardMaterial3D.new()
	_brake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_brake_material.albedo_color = Color(0.25, 0.02, 0.02)
	_brake_material.emission_enabled = true
	_brake_material.emission = Color(1.0, 0.05, 0.04)
	_brake_material.emission_energy_multiplier = 0.0
	_brake_light = OmniLight3D.new()
	_brake_light.name = "BrakeLight"
	_brake_light.position = Vector3(0, 0.4, -2.8)
	_brake_light.light_color = Color(1.0, 0.08, 0.05)
	_brake_light.omni_range = 4.5
	_brake_light.shadow_enabled = false
	_brake_light.light_cull_mask = 0xFFFFF & ~CarAssembly.OWN_LAYERS
	_brake_light.visible = false
	add_child(_brake_light)
	# Clarões (billboard) na lanterna central e nos LEDs das placas da asa traseira
	_flare_material = StandardMaterial3D.new()
	_flare_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flare_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flare_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flare_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flare_material.albedo_texture = _glow_texture()
	_flare_material.albedo_color = Color(1.0, 0.1, 0.06, 0.0)
	for spot in [[Vector3(0, 0.255, -2.62), 0.9], [Vector3(0.5, 0.8, -2.93), 0.6], [Vector3(-0.5, 0.8, -2.93), 0.6]]:
		var flare := MeshInstance3D.new()
		flare.name = "BrakeFlare"
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * float(spot[1])
		flare.mesh = quad
		flare.material_override = _flare_material
		flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flare.position = spot[0]
		flare.visible = false
		add_child(flare)
		_brake_flares.append(flare)


## As lanternas traseiras (material Light_Red na asa traseira e na cobertura do motor, incluindo
## as cópias do sistema de dano) ganham um material próprio; os LEDs do volante continuam iguais.
func _assign_brake_material() -> void:
	var livery_red: Material = car.assembly.livery.materials.get("Light_Red")
	var inv := car.global_transform.affine_inverse()
	for node in car.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not (mi.mesh is ArrayMesh):
			continue
		if (inv * mi.global_transform * mi.get_aabb()).get_center().z > -1.4:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var active := mi.get_active_material(s)
			if (src and src.resource_name == "Light_Red") or active == livery_red or active == _brake_material:
				mi.set_surface_override_material(s, _brake_material)


func _update_brake_light(delta: float) -> void:
	var night: float = Daylight.current_night
	var braking := car.brake_input > 0.1 and car.linear_velocity.length() > 2.0
	# Pisca como na F1 (recuperação de energia): ~4 Hz, pulsos curtos
	var target := 0.0
	if braking:
		target = 1.0 if fmod(_time * 4.0, 1.0) < 0.55 else 0.08
	_brake_glow = target if target > _brake_glow else move_toward(_brake_glow, target, delta * 25.0)
	_brake_material.emission_energy_multiplier = 0.15 + _brake_glow * lerpf(12.0, 16.0, night)
	_brake_light.visible = _brake_glow > 0.05 and night > 0.05
	_brake_light.light_energy = _brake_glow * night * 2.0
	_flare_material.albedo_color = Color(1.0, 0.12, 0.08, _brake_glow)
	for flare in _brake_flares:
		flare.visible = _brake_glow > 0.02 and not car.get_node("Damage").detached.has("rear_wing")
	if _brake_flares.size() > 0:
		_brake_flares[0].visible = _brake_glow > 0.02


# ---------------------------------------------------------------------------
# Sombra de contato
# ---------------------------------------------------------------------------
func _build_shadow() -> void:
	_decal = Decal.new()
	_decal.name = "ContactShadow"
	_decal.size = Vector3(2.3, 0.8, 5.9)
	_decal.position = Vector3(0, 0.3, -0.15)
	_decal.texture_albedo = _shadow_texture()
	_decal.modulate = Color(0.02, 0.02, 0.05, shadow_opacity)
	_decal.albedo_mix = 1.0
	_decal.normal_fade = 0.3
	_decal.upper_fade = 0.2
	_decal.lower_fade = 0.3
	_decal.cull_mask = 0xFFFFF & ~CarAssembly.OWN_LAYERS
	add_child(_decal)


## Retângulo de cantos arredondados com borda bem suave (largura x comprimento do carro).
static func _shadow_texture() -> ImageTexture:
	var w := 64
	var h := 160
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var p := Vector2((x + 0.5) / w * 2.0 - 1.0, (y + 0.5) / h * 2.0 - 1.0)
			# Mais estreito no bico e na traseira (formato de F1 visto de cima)
			var width := lerpf(0.55, 0.95, smoothstep(0.95, 0.2, absf(p.y + 0.1)))
			var q := Vector2(absf(p.x) / width, absf(p.y))
			var d := maxf(q.x, q.y)
			var a := 1.0 - smoothstep(0.55, 1.0, d)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Tudo do carro só na camada CAR_LAYER (a sombra de contato e a luz de contorno usam isso);
## a cabeça do piloto continua na HEAD_LAYER e halo, volante e corpo do piloto na INTERIOR_LAYER.
func _retag_layers() -> void:
	for vi in car.find_children("*", "VisualInstance3D", true, false):
		if vi is Light3D or vi is Decal:
			continue
		var v := vi as VisualInstance3D
		if v.layers & (CarAssembly.HEAD_LAYER | CarAssembly.INTERIOR_LAYER):
			continue
		v.layers = CarAssembly.CAR_LAYER


# ---------------------------------------------------------------------------
# Pó mágico
# ---------------------------------------------------------------------------
func _make_dust() -> GPUParticles3D:
	if _dust_material == null:
		_dust_material = StandardMaterial3D.new()
		_dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_dust_material.vertex_color_use_as_albedo = true
		_dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_dust_material.albedo_texture = _sparkle_texture()
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.3
	process.direction = Vector3(0, 1, 0)
	process.spread = 180.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0, -0.6, 0)
	process.damping_min = 1.0
	process.damping_max = 2.0
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.scale_min = 0.5
	process.scale_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.2))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(1, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = curve
	process.scale_curve = scale_tex
	# Brilho piscando (cintila) e sumindo
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.35, 0.5, 0.65, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.4), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	process.color_ramp = ramp_tex
	# Algumas partículas brancas misturadas com as da cor do boost
	var tint := Gradient.new()
	tint.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
	tint.colors = PackedColorArray([Color(1, 1, 1), Color(1, 1, 1), Color(1.6, 1.6, 1.6)])
	var tint_tex := GradientTexture1D.new()
	tint_tex.gradient = tint
	process.color_initial_ramp = tint_tex
	var dust := GPUParticles3D.new()
	dust.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	quad.material = _dust_material
	dust.draw_pass_1 = quad
	dust.amount = 70
	dust.lifetime = 1.1
	dust.local_coords = false
	dust.emitting = false
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 30, 80))
	dust.top_level = true
	add_child(dust)
	return dust


## Estrelinha de 4 pontas com centro brilhante.
static func _sparkle_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var p := Vector2((x + 0.5) / s * 2.0 - 1.0, (y + 0.5) / s * 2.0 - 1.0)
			var core := exp(-p.length_squared() * 18.0)
			var rays := exp(-absf(p.x) * 22.0) * (1.0 - absf(p.y)) + exp(-absf(p.y) * 22.0) * (1.0 - absf(p.x))
			var a := clampf(core + rays * 0.9, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Gradiente transversal da fita (bordas suaves, miolo claro).
static func _soft_line_texture() -> ImageTexture:
	var img := Image.create(32, 1, false, Image.FORMAT_RGBA8)
	for x in 32:
		var u := (x + 0.5) / 32.0 * 2.0 - 1.0
		var a := clampf(1.0 - absf(u), 0.0, 1.0)
		var core := clampf(1.0 - absf(u) * 3.0, 0.0, 1.0)
		img.set_pixel(x, 0, Color(1.0, 1.0, 1.0, a * a).lerp(Color(1, 1, 1, 1), core))
	return ImageTexture.create_from_image(img)
