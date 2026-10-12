@tool
class_name F1Car
extends F1CarCore
## Carro de Fórmula 1 baseado em VehicleBody3D + 4 VehicleWheel3D.
##
## Origem do corpo = chão, no meio do entre-eixos (mesma origem dos modelos do Blender).
## Frente em +Z, esquerda em +X. O centro de massa é definido em `center_of_mass` (custom).
##
## A física roda no código nativo (F1CarCore, native/src/car.rs), a cada passo de física; este
## script monta as peças (CarAssembly), conserta, cria os efeitos e as luzes do pisca.
##
## Divisão de trabalho:
##  * VehicleBody3D/VehicleWheel3D: só a suspensão (raycast, mola, amortecedor) e o visual das rodas.
##    O atrito embutido do Godot é desligado (wheel_friction_slip = 0), porque ele dá aderência
##    "perfeita" até um limite e depois faz as 4 rodas escorregarem juntas.
##  * Modelo de pneu próprio (F1CarCore), roda a roda:
##      - carga vertical de cada pneu: a compressão das molas define a distribuição entre as
##        rodas e o total vem do equilíbrio (peso + downforce + aceleração vertical) → a
##        transferência de peso em curva, frenagem e aceleração acontece naturalmente;
##      - força lateral pela curva "Magic Formula" (Pacejka simplificada) em função do ângulo de
##        deriva, com pico e queda depois do pico (é isso que faz o carro rodar);
##      - μ cai com a carga (sensibilidade à carga): o eixo que recebe mais carga lateral perde
##        eficiência → equilíbrio sub/sobreesterço depende de peso, aerodinâmica e acerto;
##      - elipse de atrito: frear/acelerar consome aderência lateral; acima do limite a roda
##        trava ou patina e quase não segura de lado (subesterço travando a frente,
##        sobreesterço de potência na saída de curva).
##  * Motor, câmbio, freios, aerodinâmica e DRS geram os pedidos de força para os pneus.
##  * Entradas: throttle_input / brake_input / steer_input. Com `player_controlled` elas vêm do
##    InputMap; caso contrário podem ser preenchidas por uma IA ou script de teste.
##
## Sinais do F1CarCore: gear_changed(gear), drs_changed(open), car_contact(other, impulse).
## Propriedades (exportadas e de estado) também ficam lá: tire_state é um F1Car.TireState por roda.

## Emitido depois que as peças foram (re)montadas e as peças animadas foram localizadas.
signal parts_ready

enum TireState { AIR, GRIP, SLIDE, SPIN, LOCK }
enum Handling { NEUTRAL, UNDERSTEER, OVERSTEER }

const AIR_DENSITY := 1.225
const GEAR_REVERSE := -1
const GEAR_NEUTRAL := 0
## Abaixo desta velocidade o ângulo de deriva usa este denominador (evita divisão por ~0).
const LOW_SPEED_SLIP := 3.0
## Desgaste por compostos (macio, médio, duro, intermediário, chuva): fração da vida por "unidade
## de esforço" (energia de deslizamento normalizada).
const COMPOUND_WEAR := [1.55, 1.0, 0.68, 1.2, 1.4]
## Limitador de velocidade (botão): corta a tração acima disto (pit lane e bandeira amarela).
const LIMITER_KMH := 80.0

@export var config: CarConfig:
	set(value):
		if config and config.changed.is_connected(_on_config_changed):
			config.changed.disconnect(_on_config_changed)
		config = value
		_core_set_config(config)
		if config and not config.changed.is_connected(_on_config_changed):
			config.changed.connect(_on_config_changed)
		_on_config_changed()

## Carro cujo rastro dá o vácuo (para o efeito visual).
var slipstream_source: F1Car

var _smoke: Array[CPUParticles3D] = []
var _dust: Array[CPUParticles3D] = []
var _drs_flap: Node3D
var _drs_flap_rest := Transform3D.IDENTITY
var _steering_wheel: Node3D
var _steering_wheel_rest := Transform3D.IDENTITY

@onready var assembly: CarAssembly = $Visual


func _ready() -> void:
	_core_ready()
	if not Engine.is_editor_hint():
		_create_tire_smoke()
		_create_dust()
		_core_set_fx(_smoke, _dust)
	if config == null:
		config = CarConfig.new()
	else:
		_on_config_changed()


func _on_config_changed() -> void:
	if not is_node_ready() or config == null:
		return
	assembly.sync(config, get_wheels())
	_cache_animated_parts()
	_update_stats()
	parts_ready.emit()


# ---------------------------------------------------------------------------
# API pública (o resto — câmbio, pneus, reset — é do F1CarCore)
# ---------------------------------------------------------------------------
## Conserta o carro: remonta todas as peças e zera o dano (o CarDamage se refaz em parts_ready).
func repair() -> void:
	_reset_damage()
	assembly.clear()
	_on_config_changed()


## Transformação local do volante com a direção reta (usada pelo IK do piloto).
func get_steering_wheel_rest() -> Transform3D:
	return _steering_wheel_rest


# ---------------------------------------------------------------------------
# Pedir passagem: pisca a luz dos retrovisores (como a seta dos carros de rua). O tempo do pisca
# corre no F1CarCore (signal_time / signal_on); aqui ficam as luzes.
# ---------------------------------------------------------------------------
const SIGNAL_COLOR := Color(1.0, 0.62, 0.08)
var _signal_leds: Array[MeshInstance3D] = []


## Chamado pelo F1CarCore quando o pisca acende ou apaga.
func _show_signal_leds(on: bool) -> void:
	if on and _signal_leds.is_empty():
		_build_signal_leds()
	for led in _signal_leds:
		if is_instance_valid(led):
			led.visible = on


## Faixa de LED âmbar na borda de fora de cada retrovisor (presa ao vidro: some se ele quebrar).
func _build_signal_leds() -> void:
	if assembly == null:
		return
	var mirrors := assembly.get_part_node("mirrors")
	if mirrors == null:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = SIGNAL_COLOR
	mat.emission_enabled = true
	mat.emission = SIGNAL_COLOR
	mat.emission_energy_multiplier = 6.0
	for suffix in ["L", "R"]:
		var glass := mirrors.find_child("MirrorGlass" + suffix + "*", true, false) as MeshInstance3D
		if glass == null:
			continue
		var aabb := glass.get_aabb()
		var center := glass.global_transform * aabb.get_center()
		var outward := global_basis.x * (1.0 if suffix == "L" else -1.0)
		var half_w := (glass.global_basis * Vector3(aabb.size.x, 0, 0)).length() * 0.5
		var height := maxf((glass.global_basis * Vector3(0, aabb.size.y, 0)).length() * 0.75, 0.03)
		var box := BoxMesh.new()
		box.size = Vector3(0.05, height * 1.2, 0.22)
		box.material = mat
		var led := MeshInstance3D.new()
		led.name = "SignalLED"
		led.mesh = box
		led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		led.visible = false
		glass.add_child(led)
		led.global_transform = Transform3D(global_basis, center + outward * (half_w + 0.02))
		# Halo (visível de longe, nos retrovisores dos outros) e uma luz âmbar pequena
		var halo := MeshInstance3D.new()
		halo.mesh = _signal_halo_mesh()
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		led.add_child(halo)
		var light := OmniLight3D.new()
		light.light_color = SIGNAL_COLOR
		light.light_energy = 2.5
		light.omni_range = 2.2
		light.shadow_enabled = false
		led.add_child(light)
		_signal_leds.append(led)


static var _halo_mesh: QuadMesh


static func _signal_halo_mesh() -> QuadMesh:
	if _halo_mesh:
		return _halo_mesh
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = tex
	mat.albedo_color = Color(SIGNAL_COLOR, 0.9)
	mat.no_depth_test = false
	_halo_mesh = QuadMesh.new()
	_halo_mesh.size = Vector2(0.75, 0.75)
	_halo_mesh.material = mat
	return _halo_mesh


func set_puppet(on: bool) -> void:
	puppet = on
	if on:
		player_controlled = false
		# Estático e sem o retorno de estado da física: o VehicleBody3D regravaria as rodas a cada
		# passo (raios da suspensão a partir da posição anterior) — era a tremedeira dos pneus
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = on
	if on:
		PhysicsServer3D.body_set_state_sync_callback(get_rid(), Callable())
		# As rodas saem de baixo do VehicleBody3D (num nó no mesmo lugar): só se registra nele a roda
		# que é filha direta, então o motor deixa de regravar a posição delas
		if not has_node("PuppetWheels"):
			var holder := Node3D.new()
			holder.name = "PuppetWheels"
			add_child(holder)
			for w in get_wheels():
				var xf := w.transform
				remove_child(w)
				holder.add_child(w)
				w.transform = xf


# ---------------------------------------------------------------------------
# Auxiliares
# ---------------------------------------------------------------------------
func _update_stats() -> void:
	effective_downforce_area = downforce_area
	effective_drag_area = drag_area
	effective_balance = aero_balance
	for slot in CarPartCatalog.all_slots():
		var stats := CarPartCatalog.variant_stats(slot, config.get_part(slot))
		effective_downforce_area += stats.get("downforce", 0.0)
		effective_drag_area += stats.get("drag", 0.0)
		effective_balance += stats.get("balance", 0.0)


func _cache_animated_parts() -> void:
	# Só lê a pose de repouso quando a peça é nova (a atual pode estar girada/aberta).
	var flap := assembly.find_in_part("rear_wing", "DRSFlap*")
	if flap != _drs_flap:
		_drs_flap = flap
		if flap:
			_drs_flap_rest = flap.transform
	var wheel := assembly.find_in_part("cockpit", "SteeringWheel*")
	if wheel != _steering_wheel:
		_steering_wheel = wheel
		if wheel:
			_steering_wheel_rest = wheel.transform
	_core_set_parts(_drs_flap, _drs_flap_rest, _steering_wheel, _steering_wheel_rest)


# ---------------------------------------------------------------------------
# Fumaça dos pneus (feedback visual de perda de aderência); o F1CarCore liga e desliga
# ---------------------------------------------------------------------------
func _create_tire_smoke() -> void:
	var puff := SphereMesh.new()
	puff.radius = 0.22
	puff.height = 0.44
	puff.radial_segments = 8
	puff.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	puff.material = mat
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.45))
	fade.set_color(1, Color(0.9, 0.92, 1.0, 0.0))
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 3.0))
	for i in get_wheels().size():
		var smoke := CPUParticles3D.new()
		smoke.name = "TireSmoke%d" % i
		smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		smoke.mesh = puff
		smoke.amount = 40
		smoke.lifetime = 0.9
		smoke.emitting = false
		smoke.local_coords = false
		smoke.direction = Vector3.UP
		smoke.spread = 60.0
		smoke.initial_velocity_min = 0.5
		smoke.initial_velocity_max = 2.0
		smoke.gravity = Vector3(0, 0.8, 0)
		smoke.damping_min = 1.0
		smoke.damping_max = 2.0
		smoke.scale_amount_curve = grow
		smoke.color_ramp = fade
		smoke.position = Vector3(_mounts[i].x, 0.15, _mounts[i].z)
		add_child(smoke)
		_smoke.append(smoke)


## Poeira marrom/verde quando a roda passa pela brita ou grama.
func _create_dust() -> void:
	var puff := SphereMesh.new()
	puff.radius = 0.25
	puff.height = 0.5
	puff.radial_segments = 6
	puff.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	puff.material = mat
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 3.5))
	for i in get_wheels().size():
		var dust := CPUParticles3D.new()
		dust.name = "Dust%d" % i
		dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dust.mesh = puff
		dust.amount = 30
		dust.lifetime = 1.2
		dust.emitting = false
		dust.local_coords = false
		dust.direction = Vector3.UP
		dust.spread = 50.0
		dust.initial_velocity_min = 1.0
		dust.initial_velocity_max = 3.0
		dust.gravity = Vector3(0, -1.5, 0)
		dust.damping_min = 1.5
		dust.damping_max = 2.5
		dust.scale_amount_curve = grow
		dust.position = Vector3(_mounts[i].x, 0.1, _mounts[i].z)
		add_child(dust)
		_dust.append(dust)
