@tool
class_name Daylight
extends Node3D
## Iluminação de dia em três pontos, compartilhada pelas cenas:
##  * principal (Sun): o sol, com sombras em cascata;
##  * preenchimento (Fill): luz fria e suave vinda do lado da câmera oposto ao sol, clareia o que
##    está na sombra sem criar sombras novas;
##  * contorno (Rim): luz quente vinda de trás do que a câmera olha, contra ela, desenha a
##    silhueta do carro e dos objetos.
## Fill e Rim acompanham a câmera ativa durante o jogo (no editor ficam paradas), não aparecem
## no céu e não projetam sombra. O WorldEnvironment cuida do céu, ambiente, tonemapping, SSAO,
## bloom e neblina.
##
## Período do dia (dia, entardecer, noite) e ambiente (verão, outono, sakura, fantasia) aplicam os
## presets de DaylightPresets: sol/lua, céu (estrelas à noite), neblina, ambiente e as paletas
## globais de grama/folhas. Quem precisa reagir (pista: refletores, folhas) entra no grupo
## "mood_aware" e recebe apply_mood(time_of_day, biome). N e B alternam durante o jogo.

signal mood_changed(time_of_day: int, biome: int)

## Quanto é noite agora (0 = dia, 0.35 = entardecer, 1 = noite), para scripts (luzes do carro).
static var current_night := 0.0

@export var time_of_day: DaylightPresets.TimeOfDay = DaylightPresets.TimeOfDay.DAY:
	set(value):
		time_of_day = value
		_apply_mood()
@export var biome: DaylightPresets.Biome = DaylightPresets.Biome.SUMMER:
	set(value):
		biome = value
		_apply_mood()

## Altura do sol acima do horizonte (graus).
@export_range(2.0, 90.0) var sun_elevation := 42.0:
	set(value):
		sun_elevation = value
		_apply()
## Direção do sol (graus, 0 = vindo do norte/-Z, 90 = do leste/+X).
@export_range(-180.0, 180.0) var sun_azimuth := 125.0:
	set(value):
		sun_azimuth = value
		_apply()
@export var sun_energy := 1.0:
	set(value):
		sun_energy = value
		_apply()
## Cor do sol ao meio-dia e perto do horizonte (mistura pela elevação).
@export var noon_color := Color(1.0, 0.97, 0.92)
@export var low_sun_color := Color(1.0, 0.72, 0.48)

@export_group("Três pontos")
## Fill e Rim seguem a câmera ativa.
@export var follow_camera := true
@export var fill_energy := 0.22
@export var fill_color := Color(0.72, 0.82, 1.0)
## Desvio lateral (graus) do preenchimento em relação à direção da câmera.
@export var fill_angle := 40.0
@export var fill_elevation := 22.0
## Só ilumina a camada do carro (CarAssembly.CAR_LAYER): o foco dos três pontos é o carro.
@export var rim_energy := 0.65
@export var rim_color := Color(1.0, 0.92, 0.8)
@export var rim_elevation := 14.0


func _ready() -> void:
	add_to_group("daylight")
	_apply_mood()


## N/B trocam horário e ambiente na pista (o modo corrida desliga: lá eles são escolhidos antes).
var allow_cycle := true


func _unhandled_input(event: InputEvent) -> void:
	if not allow_cycle:
		return
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed("cycle_time"):
		time_of_day = ((int(time_of_day) + 1) % DaylightPresets.TIME_NAMES.size()) as DaylightPresets.TimeOfDay
	elif event.is_action_pressed("cycle_biome"):
		biome = ((int(biome) + 1) % DaylightPresets.BIOME_NAMES.size()) as DaylightPresets.Biome


## Aplica período + ambiente: luz, céu, neblina, paletas globais e avisa o grupo "mood_aware".
func _apply_mood() -> void:
	if not is_inside_tree():
		return
	var t: Dictionary = DaylightPresets.TIMES[time_of_day]
	var b: Dictionary = DaylightPresets.BIOMES[biome]
	sun_elevation = t.sun_elevation
	sun_azimuth = t.sun_azimuth
	noon_color = t.sun_color
	low_sun_color = t.sun_color if time_of_day != DaylightPresets.TimeOfDay.DAY else Color(1.0, 0.72, 0.48)
	sun_energy = t.sun_energy
	fill_energy = t.fill
	rim_energy = t.rim
	var night := DaylightPresets.night_amount(time_of_day)
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		var env := we.environment
		env.ambient_light_color = t.ambient_color
		env.ambient_light_energy = t.ambient_energy
		env.tonemap_exposure = t.exposure
		env.fog_light_color = t.fog_color
		env.fog_density = t.fog_density
		env.glow_intensity = t.glow
		var sky := env.sky.sky_material as ShaderMaterial if env.sky else null
		if sky:
			var top: Color = t.sky_top
			var horizon: Color = t.sky_horizon
			var fog: Color = t.fog_color
			if b.has("sky"):
				var custom: Array = b.sky[time_of_day]
				top = custom[0]
				horizon = custom[1]
				fog = fog.lerp(custom[2], 0.7)
				env.fog_light_color = fog
			elif b.has("horizon_tint") and time_of_day == DaylightPresets.TimeOfDay.DAY:
				horizon = horizon.lerp(b.horizon_tint, 0.5)
				env.fog_light_color = fog.lerp(b.horizon_tint, 0.4)
			sky.set_shader_parameter("top_color", top)
			sky.set_shader_parameter("horizon_color", horizon)
			sky.set_shader_parameter("ground_color", t.sky_ground)
			sky.set_shader_parameter("cloud_lit", t.cloud_lit)
			sky.set_shader_parameter("cloud_shade", t.cloud_shade)
			sky.set_shader_parameter("cloud_coverage", t.cloud_coverage)
			sky.set_shader_parameter("energy", t.sky_energy)
	var mist := get_node_or_null("GroundMist") as FogVolume
	if mist and mist.material is FogMaterial:
		(mist.material as FogMaterial).albedo = t.mist
		(mist.material as FogMaterial).density = t.mist_density
	var names := ["grass_lush", "grass_warm", "grass_cool", "grass_deep"]
	for k in 4:
		_global_color(names[k], b.grass[k])
	var leaf_names := ["leaf_a", "leaf_b", "leaf_c"]
	for k in 3:
		_global_color(leaf_names[k], b.leaves[k])
	RenderingServer.global_shader_parameter_set(&"leaf_mix", b.leaf_mix)
	RenderingServer.global_shader_parameter_set(&"conifer_mix", b.conifer_mix)
	RenderingServer.global_shader_parameter_set(&"petals", b.petals)
	RenderingServer.global_shader_parameter_set(&"night", night)
	current_night = night
	_apply()
	if not Engine.is_editor_hint():
		get_tree().call_group("mood_aware", "apply_mood", time_of_day, biome)
	mood_changed.emit(time_of_day, biome)


static func _global_color(param: String, srgb: Color) -> void:
	var c := srgb.srgb_to_linear()
	RenderingServer.global_shader_parameter_set(StringName(param), Vector3(c.r, c.g, c.b))


func get_time_name() -> String:
	return DaylightPresets.TIME_NAMES[time_of_day]


func get_biome_name() -> String:
	return DaylightPresets.BIOME_NAMES[biome]


func _process(_delta: float) -> void:
	if follow_camera and not Engine.is_editor_hint():
		var cam := get_viewport().get_camera_3d()
		if cam:
			aim_camera_lights(-cam.global_basis.z)


func _apply() -> void:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return
	var el := deg_to_rad(sun_elevation)
	var az := deg_to_rad(sun_azimuth)
	# Direção de onde a luz vem (do chão para o sol); a luz aponta para -Z local
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)
	var low := 1.0 - smoothstep(5.0, 35.0, sun_elevation)
	sun.light_color = noon_color.lerp(low_sun_color, low)
	sun.light_energy = sun_energy * lerpf(1.0, 0.75, low)
	# Usado pelos shaders das construções (building_common.gdshaderinc)
	RenderingServer.global_shader_parameter_set(&"sun_dir_world", to_sun)
	for node_name in ["Fill", "Rim"]:
		var light := get_node_or_null(node_name) as DirectionalLight3D
		if light:
			light.light_color = fill_color if node_name == "Fill" else rim_color
			light.light_energy = fill_energy if node_name == "Fill" else rim_energy
	# Posição inicial (editor): como se a câmera olhasse para o norte
	aim_camera_lights(Vector3.FORWARD)


## Orienta preenchimento e contorno a partir da direção em que a câmera olha.
func aim_camera_lights(camera_forward: Vector3) -> void:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	var fill := get_node_or_null("Fill") as DirectionalLight3D
	var rim := get_node_or_null("Rim") as DirectionalLight3D
	if sun == null or fill == null or rim == null:
		return
	var f := Vector3(camera_forward.x, 0.0, camera_forward.z)
	if f.length_squared() < 1e-4:
		f = Vector3.FORWARD
	f = f.normalized()
	var right := f.cross(Vector3.UP)
	# Lado para onde o sol empurra a luz (visto da câmera): o preenchimento vem do outro lado
	var key_travel := -sun.basis.z
	var key_side := signf(key_travel.dot(right))
	if key_side == 0.0:
		key_side = 1.0
	var fill_h := (f - right * key_side * tan(deg_to_rad(fill_angle))).normalized()
	fill.basis = Basis.looking_at(_tilt_down(fill_h, fill_elevation))
	# Contorno: de trás do assunto em direção à câmera, um pouco deslocado para o lado do sol
	var rim_h := (-f + right * key_side * 0.35).normalized()
	rim.basis = Basis.looking_at(_tilt_down(rim_h, rim_elevation))


static func _tilt_down(horizontal: Vector3, elevation_deg: float) -> Vector3:
	var e := deg_to_rad(elevation_deg)
	return (horizontal * cos(e) + Vector3.DOWN * sin(e)).normalized()
