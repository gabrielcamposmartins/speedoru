@tool
class_name F1Car
extends VehicleBody3D
## Carro de Fórmula 1 baseado em VehicleBody3D + 4 VehicleWheel3D.
##
## Origem do corpo = chão, no meio do entre-eixos (mesma origem dos modelos do Blender).
## Frente em +Z, esquerda em +X. O centro de massa é definido em `center_of_mass` (custom).
##
## Divisão de trabalho:
##  * VehicleBody3D/VehicleWheel3D: só a suspensão (raycast, mola, amortecedor) e o visual das rodas.
##    O atrito embutido do Godot é desligado (wheel_friction_slip = 0), porque ele dá aderência
##    "perfeita" até um limite e depois faz as 4 rodas escorregarem juntas.
##  * Modelo de pneu próprio (_update_tires), roda a roda:
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

signal gear_changed(gear: int)
signal drs_changed(open: bool)
## Emitido depois que as peças foram (re)montadas e as peças animadas foram localizadas.
signal parts_ready
## Encostou em outro carro (impulso estimado em N·s), para penalidades de colisão.
signal car_contact(other: F1Car, impulse: float)

enum TireState { AIR, GRIP, SLIDE, SPIN, LOCK }
enum Handling { NEUTRAL, UNDERSTEER, OVERSTEER }

const AIR_DENSITY := 1.225
const GEAR_REVERSE := -1
const GEAR_NEUTRAL := 0
## Abaixo desta velocidade o ângulo de deriva usa este denominador (evita divisão por ~0).
const LOW_SPEED_SLIP := 3.0

@export var config: CarConfig:
	set(value):
		if config and config.changed.is_connected(_on_config_changed):
			config.changed.disconnect(_on_config_changed)
		config = value
		if config and not config.changed.is_connected(_on_config_changed):
			config.changed.connect(_on_config_changed)
		_on_config_changed()

## Lê as entradas do jogador (InputMap). Desligue para IA/replays.
@export var player_controlled := true

@export_group("Motor e câmbio")
@export var max_power_kw := 760.0
@export var peak_torque_nm := 620.0
@export var idle_rpm := 4000.0
@export var launch_rpm := 9500.0
@export var max_rpm := 12500.0
## Relação total (câmbio × diferencial) de cada marcha, da 1ª à 8ª.
@export var gear_ratios := PackedFloat32Array([15.5, 12.4, 10.3, 8.8, 7.6, 6.6, 5.7, 4.85])
@export var reverse_ratio := 14.0
@export var max_reverse_kmh := 30.0
@export var automatic := true
@export var upshift_rpm := 11900.0
@export var downshift_rpm := 7600.0
@export var shift_time := 0.06
@export var engine_braking_force := 2400.0

@export_group("Assistências")
## Limita a força de tração ao que o pneu traseiro aguenta (sem patinar).
@export var traction_control := true
## Limita a força de frenagem ao que cada pneu aguenta (sem travar). F1 real não tem ABS.
@export var brake_assist := true
## Fração da aderência máxima usada pelas assistências.
@export_range(0.5, 1.0) var assist_threshold := 0.96

@export_group("Pneus")
## Aderência de pico (μ) com a carga nominal, antes do multiplicador do composto.
@export var front_grip := 1.75
@export var rear_grip := 1.8
## Ângulo de deriva (graus) em que o pneu atinge a força lateral máxima.
@export var peak_slip_angle_deg := 6.0
## Fator de forma "C" da curva de Pacejka: maior = cai mais depois do pico (1.2–1.6).
@export_range(1.05, 1.9) var tire_shape := 1.4
## Perda de μ por carga extra (0 = sem sensibilidade): μ = μ0·(1 − k·(Fz/Fz0 − 1)).
@export_range(0.0, 0.4) var load_sensitivity := 0.12
## Carga nominal por pneu Fz0 (N).
@export var nominal_load := 3000.0
## Aderência longitudinal com a roda travada/patinando (fração do pico).
@export_range(0.3, 1.0) var sliding_grip := 0.8
## Fração da aderência lateral que sobra com a roda travada/patinando.
@export_range(0.0, 1.0) var locked_lateral_grip := 0.15
## Comprimento de relaxação (m): o pneu leva essa distância para "construir" a força lateral.
@export var relaxation_length := 0.3

@export_group("Freios e direção")
## Força máxima de frenagem por roda (limite do sistema de freio).
@export var brake_force_per_wheel := 14000.0
@export_range(0.3, 0.8) var brake_bias_front := 0.57
@export var max_steer_angle := 0.36
## Esterço máximo em alta velocidade (acima disso a frente só satura e o carro sai de frente).
@export var high_speed_steer_angle := 0.12
## Velocidade (m/s) em que o esterço chega ao limite de alta velocidade.
@export var steer_speed_reference := 60.0
@export var steer_rate := 2.4
@export var steering_wheel_ratio := 3.2

@export_group("Desgaste dos pneus")
## Multiplica todo o desgaste (0 = pneus eternos).
@export_range(0.0, 5.0) var tyre_wear_rate := 1.0
## Desgaste por compostos (macio, médio, duro, intermediário, chuva): fração da vida por "unidade
## de esforço" (energia de deslizamento normalizada).
const COMPOUND_WEAR := [1.55, 1.0, 0.68, 1.2, 1.4]
## Perda máxima de aderência com o pneu acabado (fração).
@export_range(0.0, 0.8) var worn_grip_loss := 0.32

@export_group("Bateria e boost")
## Recarga (fração da bateria por segundo) freando forte acima de ~110 km/h.
@export var battery_regen_rate := 0.16
## Consumo por segundo com o boost ligado (bateria cheia dura 1/drain segundos).
@export var boost_drain_rate := 0.22
## Força extra (N) do motor elétrico durante o boost (soma à do motor a combustão).
@export var boost_force := 4200.0
## Bateria mínima para começar um boost (evita "piscar" com a bateria quase vazia).
@export_range(0.0, 0.5) var boost_min_start := 0.06

@export_group("Aerodinâmica")
## Coeficiente de sustentação negativa × área (m²).
@export var downforce_area := 4.2
## Coeficiente de arrasto × área (m²).
@export var drag_area := 1.4
## Fração da downforce no eixo dianteiro.
@export_range(0.2, 0.7) var aero_balance := 0.42
@export var rolling_resistance := 0.012
@export_range(0.0, 1.0) var drs_drag_reduction := 0.22
@export_range(0.0, 1.0) var drs_downforce_reduction := 0.12
@export var drs_min_speed_kmh := 80.0
@export var drs_flap_angle_deg := 28.0

# Entradas (0..1, direção -1..1 com + = esquerda)
var throttle_input := 0.0
var brake_input := 0.0
## Ré (0..1): com o carro parado engata a ré e acelera para trás; acelerar volta para a 1ª.
var reverse_input := 0.0
var boost_input := false
## Limitador de velocidade (botão): corta a tração acima de LIMITER_KMH (pit lane e bandeira amarela).
var limiter_on := false
const LIMITER_KMH := 80.0
## Bateria (0..1): sobe freando (regeneração), desce com o boost.
var battery := 0.35
var boost_active := false
var steer_input := 0.0
var drs_requested := false

# Estado (somente leitura para HUD/câmeras/telemetria)
var gear := 1
var rpm := 4000.0
var forward_speed := 0.0
var speed_kmh := 0.0
var drs_open := false
var tc_active := false
var abs_active := false
var effective_downforce_area := 0.0
var effective_drag_area := 0.0
var effective_balance := 0.42
## Ângulo entre a direção do carro e a direção do movimento (rad, + = carro de lado p/ esquerda).
var body_slip_angle := 0.0
var handling := Handling.NEUTRAL
## Por roda (mesma ordem de get_wheels()): carga (N), uso da aderência (0..1+), deriva (graus), estado.
var tire_load := PackedFloat32Array([0, 0, 0, 0])
var tire_usage := PackedFloat32Array([0, 0, 0, 0])
var tire_slip_deg := PackedFloat32Array([0, 0, 0, 0])
var tire_state: Array[TireState] = [TireState.AIR, TireState.AIR, TireState.AIR, TireState.AIR]
## Piso sob cada roda (TrackSurface.Type) — lido do metadado "surface" do corpo em contato.
var tire_surface := PackedInt32Array([0, 0, 0, 0])
## Desgaste de cada pneu (0 = novo, 1 = acabado). Sobe com o esforço: escorregar, travar,
## patinar, curvas no limite; mais rápido nos compostos macios.
var tire_wear := PackedFloat32Array([0, 0, 0, 0])
## Congela o carro (pit stop, antes da largada): sem tração, freio de mão total.
var hold := false
## Regra do DRS da corrida: com drs_rule_active, só abre se drs_allowed (a até 1 s do carro da
## frente; calculado pelo RaceManager). Sem regra (treino, "livre"), sempre permitido.
var drs_allowed := true
var drs_rule_active := false
## Rede (cliente): o carro não tem física própria, só mostra o estado que o servidor manda
## (corpo estático movido pelo NetRaceClient; velocidade, marcha, giro etc. vêm do snapshot).
## As rodas também são posicionadas aqui (suspensão do servidor, esterço e giro pela velocidade):
## a suspensão do VehicleBody3D, com o corpo movido por fora, faria as rodas tremerem.
var puppet := false
## Rede (cliente): quanto cada roda está abaixo do ponto de fixação (m), vindo do snapshot.
var puppet_wheel_drop := PackedFloat32Array([0.04, 0.04, 0.04, 0.04])
var _puppet_spin := PackedFloat32Array([0, 0, 0, 0])
## Reparo instantâneo (tecla F); desligado no modo corrida (lá o reparo é no pit stop).
var allow_quick_repair := true
## Efeitos do dano (escritos pelo CarDamage): multiplicadores de downforce, arrasto extra,
## potência e, por roda, aderência, convergência (rad) e roda quebrada (sem pneu no chão).
var damage_front_downforce := 1.0
var damage_rear_downforce := 1.0
var damage_drag := 0.0
var damage_power := 1.0
var wheel_grip := PackedFloat32Array([1, 1, 1, 1])
var wheel_toe := PackedFloat32Array([0, 0, 0, 0])
var wheel_broken: Array[bool] = [false, false, false, false]
## Quadro de física do último "recolocar o carro" (o som ignora a mudança brusca de velocidade).
var reset_frame := -100

var _wheels: Array[VehicleWheel3D] = []
var _mounts: Array[Vector3] = []
var _alpha := PackedFloat32Array([0, 0, 0, 0])
var _max_force := PackedFloat32Array([0, 0, 0, 0])
var _lat_usage := PackedFloat32Array([0, 0, 0, 0])
var _vertical_accel := 0.0
var _prev_up_speed := 0.0
var _drive_request := PackedFloat32Array([0, 0, 0, 0])
var _brake_request := PackedFloat32Array([0, 0, 0, 0])
var _smoke: Array[CPUParticles3D] = []
var _dust: Array[CPUParticles3D] = []
var _shift_timer := 0.0
var _reverse_timer := 0.0
var _drs_amount := 0.0
var _downforce := 0.0
var _reset_pending := false
var _drs_flap: Node3D
var _drs_flap_rest := Transform3D.IDENTITY
var _steering_wheel: Node3D
var _steering_wheel_rest := Transform3D.IDENTITY

@onready var assembly: CarAssembly = $Visual
@onready var _damage: CarDamage = get_node_or_null("Damage")


func _ready() -> void:
	# Sem a detecção contínua de colisão (CCD) do Godot: em alta velocidade ela lança um raio à
	# frente de cada forma e, se ele tocar qualquer coisa (a rampa de uma zebra, um muro de raspão),
	# troca a velocidade inteira pela distância até o toque — o carro "para do nada" (320 → 5 km/h
	# num passo). A 120 Hz o carro anda < 1 m por passo e os muros têm 1,2 m: não atravessa.
	# (tests/ccd_probe.gd)
	continuous_cd = false
	for child in get_children():
		if child is VehicleWheel3D:
			var wheel := child as VehicleWheel3D
			_wheels.append(wheel)
			_mounts.append(wheel.position)
			# O atrito do Godot fica desligado; o modelo de pneu abaixo aplica as forças.
			wheel.wheel_friction_slip = 0.0
			wheel.engine_force = 0.0
			wheel.brake = 0.0
	if not Engine.is_editor_hint():
		_create_tire_smoke()
		_create_dust()
	if config == null:
		config = CarConfig.new()
	else:
		_on_config_changed()


func _on_config_changed() -> void:
	if not is_node_ready() or config == null:
		return
	assembly.sync(config, _wheels)
	_cache_animated_parts()
	_update_stats()
	parts_ready.emit()


# ---------------------------------------------------------------------------
# API pública
# ---------------------------------------------------------------------------
## Câmbio manual: R ↔ N ↔ 1 ↔ 2 … (a ré só engata com o carro quase parado). No automático a
## redução da 1ª vai direto para a ré (como antes) e não há neutro.
func shift_up() -> void:
	if gear == GEAR_REVERSE:
		_set_gear(1 if automatic else GEAR_NEUTRAL)
	elif gear == GEAR_NEUTRAL:
		_set_gear(1)
	elif gear < gear_ratios.size():
		_set_gear(gear + 1)


func shift_down() -> void:
	if gear > 1:
		_set_gear(gear - 1)
	elif gear == 1:
		if not automatic:
			_set_gear(GEAR_NEUTRAL)
		elif forward_speed < 1.0:
			_set_gear(GEAR_REVERSE)
	elif gear == GEAR_NEUTRAL and forward_speed < 1.0:
		_set_gear(GEAR_REVERSE)


## Ajuste de balanço de freio (botões do volante): + = mais freio na dianteira.
func adjust_brake_bias(delta_bias: float) -> void:
	brake_bias_front = clampf(snappedf(brake_bias_front + delta_bias, 0.005), 0.45, 0.70)


## Recoloca o carro em pé, alguns centímetros acima do ponto atual, mantendo a direção.
func reset_car() -> void:
	_reset_pending = true


## Pneus novos (pit stop); muda o composto se `compound` >= 0.
func change_tyres(compound := -1) -> void:
	tire_wear.fill(0.0)
	if compound >= 0 and config:
		config.tyre_compound = compound as CarConfig.TyreCompound


## Conserta o carro: remonta todas as peças e zera o dano (o CarDamage se refaz em parts_ready).
func repair() -> void:
	damage_front_downforce = 1.0
	damage_rear_downforce = 1.0
	damage_drag = 0.0
	damage_power = 1.0
	wheel_grip.fill(1.0)
	wheel_toe.fill(0.0)
	wheel_broken = [false, false, false, false]
	assembly.clear()
	_on_config_changed()


## Transformação local do volante com a direção reta (usada pelo IK do piloto).
func get_steering_wheel_rest() -> Transform3D:
	return _steering_wheel_rest


## Embreagem aberta durante a troca de marcha (sem torque).
func is_shifting() -> bool:
	return _shift_timer > 0.0


func get_wheels() -> Array[VehicleWheel3D]:
	return _wheels


func is_front_wheel(index: int) -> bool:
	return _wheels[index].use_as_steering


# ---------------------------------------------------------------------------
# Física
# ---------------------------------------------------------------------------
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
			for w in _wheels:
				var xf := w.transform
				remove_child(w)
				holder.add_child(w)
				w.transform = xf


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if puppet:
		forward_speed = linear_velocity.dot(global_basis.z)
		speed_kmh = absf(forward_speed) * 3.6
		_drs_amount = move_toward(_drs_amount, 1.0 if drs_open else 0.0, delta * 5.0)
		_animate_puppet_wheels(delta)
		_animate_parts()
		return
	if player_controlled:
		_read_player_input()
	forward_speed = linear_velocity.dot(global_basis.z)
	speed_kmh = absf(forward_speed) * 3.6
	_update_gearbox(delta)
	_update_drive_and_brakes()
	_update_steering(delta)
	_update_drs(delta)
	_apply_aero()
	_update_tires(delta)
	_update_handling()
	_animate_parts()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Contatos do corpo (batidas, raspadas) para o sistema de dano
	if _damage and state.get_contact_count() > 0:
		for i in state.get_contact_count():
			var pos := state.get_contact_local_position(i)
			var rel := state.get_contact_local_velocity_at_position(i) - state.get_contact_collider_velocity_at_position(i)
			var normal := state.get_contact_local_normal(i)
			var slide := (rel - normal * rel.dot(normal)).length()
			var collider := state.get_contact_collider_object(i)
			_damage.add_contact(pos, state.get_contact_impulse(i), normal, collider, slide)
			if collider is F1Car:
				var closing := absf(rel.dot(normal))
				car_contact.emit(collider, maxf(state.get_contact_impulse(i).length(), closing * mass * 0.5))
	if not _reset_pending:
		return
	_reset_pending = false
	var forward := global_basis.z
	var yaw := atan2(forward.x, forward.z)
	state.transform = Transform3D(Basis(Vector3.UP, yaw), state.transform.origin + Vector3.UP * 0.6)
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO
	reset_frame = Engine.get_physics_frames()
	_alpha.fill(0.0)
	_set_gear(1)
	reset_physics_interpolation()


func _animate_puppet_wheels(delta: float) -> void:
	for i in _wheels.size():
		var w := _wheels[i]
		_puppet_spin[i] = fposmod(_puppet_spin[i] + forward_speed * delta / maxf(w.wheel_radius, 0.1), TAU)
		var steer := steering if w.use_as_steering else 0.0
		var drop := puppet_wheel_drop[i] if i < puppet_wheel_drop.size() else 0.04
		w.transform = Transform3D(Basis(Vector3.UP, steer) * Basis(Vector3.RIGHT, _puppet_spin[i]), _mounts[i] + Vector3.DOWN * drop)


func _read_player_input() -> void:
	throttle_input = Input.get_action_strength("accelerate")
	brake_input = Input.get_action_strength("brake")
	# No manual a ré é uma marcha (engata com Q e acelera com W): a tecla de ré não faz nada
	reverse_input = Input.get_action_strength("reverse") if automatic else 0.0
	boost_input = Input.is_action_pressed("boost")
	steer_input = Input.get_axis("steer_right", "steer_left")
	drs_requested = Input.is_action_pressed("drs")
	if Input.is_action_just_pressed("shift_up"):
		shift_up()
	if Input.is_action_just_pressed("shift_down"):
		shift_down()
	if Input.is_action_just_pressed("toggle_gearbox"):
		automatic = not automatic
	if Input.is_action_just_pressed("pit_limiter"):
		limiter_on = not limiter_on
	if Input.is_action_just_pressed("toggle_tc"):
		traction_control = not traction_control
	if Input.is_action_just_pressed("brake_bias_forward"):
		adjust_brake_bias(0.005)
	if Input.is_action_just_pressed("brake_bias_rearward"):
		adjust_brake_bias(-0.005)
	if Input.is_action_just_pressed("reset_car"):
		reset_car()
	if Input.is_action_just_pressed("repair_car") and allow_quick_repair:
		repair()


func _update_gearbox(delta: float) -> void:
	_shift_timer = maxf(_shift_timer - delta, 0.0)

	# Automático: segurar a ré com o carro (quase) parado engata a ré; acelerar volta para a 1ª
	# (e sai do neutro, se o jogador trocou de manual para automático em N).
	if automatic:
		if gear >= 1 and forward_speed < 0.5 and reverse_input > 0.3 and throttle_input < 0.05:
			_reverse_timer += delta
			if _reverse_timer > 0.2:
				_set_gear(GEAR_REVERSE)
		elif (gear == GEAR_REVERSE and forward_speed > -0.5 and throttle_input > 0.05) 				or (gear == GEAR_NEUTRAL and throttle_input > 0.05):
			_set_gear(1)
		else:
			_reverse_timer = 0.0

	var target_rpm := _rpm_for_gear(gear)
	# Embreagem patinando na largada: o giro sobe com o acelerador.
	if gear == 1 or gear == GEAR_REVERSE:
		var pedal := reverse_input if gear == GEAR_REVERSE and automatic else throttle_input
		target_rpm = maxf(target_rpm, lerpf(idle_rpm, launch_rpm, pedal))
	# Neutro: o motor gira solto com o acelerador
	if gear == GEAR_NEUTRAL:
		target_rpm = lerpf(idle_rpm, max_rpm * 0.97, throttle_input)
	# Roda traseira patinando: o motor "solta" o giro.
	if _rear_spinning():
		target_rpm = maxf(target_rpm, lerpf(target_rpm, max_rpm, 0.6))
	rpm = lerpf(rpm, minf(target_rpm, max_rpm + 150.0), 1.0 - exp(-18.0 * delta))

	if automatic and gear >= 1 and _shift_timer <= 0.0:
		if _rpm_for_gear(gear) > upshift_rpm and gear < gear_ratios.size():
			shift_up()
		elif gear > 1 and _rpm_for_gear(gear) < downshift_rpm and _rpm_for_gear(gear - 1) < upshift_rpm - 600.0:
			shift_down()


## Calcula, por roda, a força de tração pedida ao pneu e a força de frenagem.
func _update_drive_and_brakes() -> void:
	var reversing := gear == GEAR_REVERSE
	# Automático: a ré anda com a tecla de ré e o acelerador freia; manual: o acelerador anda para trás
	var drive_pedal := reverse_input if reversing and automatic else throttle_input
	var brake_pedal := maxf(brake_input, throttle_input) if reversing and automatic else brake_input
	var speed := absf(forward_speed)

	var drive_force := 0.0
	if gear != GEAR_NEUTRAL and _shift_timer <= 0.0 and drive_pedal > 0.0 and brake_pedal < 0.05:
		var torque_force := _torque_at(rpm) * _ratio(gear) / _wheel_radius()
		var power_force := max_power_kw * 1000.0 / maxf(speed, 1.0)
		drive_force = minf(torque_force, power_force) * drive_pedal * damage_power
		if _rpm_for_gear(gear) >= max_rpm:
			drive_force = 0.0
		if reversing:
			drive_force = minf(drive_force, 6000.0) * clampf((max_reverse_kmh - speed_kmh) / 5.0, 0.0, 1.0)
		# Limitador: some a tração perto do limite (o carro mantém ~80 km/h e não passa disso acelerando)
		if limiter_on and not reversing:
			drive_force *= clampf((LIMITER_KMH - 0.5 - speed_kmh) / 2.0, 0.0, 1.0)

	# Bateria: frear regenera (mais em alta velocidade); o boost gasta e empurra com o motor
	# elétrico mesmo durante a troca de marcha ou no limitador.
	var dt := get_physics_process_delta_time()
	if brake_pedal > 0.05 and speed > 3.0:
		battery = minf(battery + battery_regen_rate * brake_pedal * clampf(speed / 30.0, 0.0, 1.0) * dt, 1.0)
	var wants_boost := boost_input and not reversing and gear != GEAR_NEUTRAL and not limiter_on
	if wants_boost and (boost_active or battery > boost_min_start) and battery > 0.0:
		boost_active = true
		battery = maxf(battery - boost_drain_rate * dt, 0.0)
		drive_force += boost_force * damage_power
	else:
		boost_active = false

	# Diferencial: mesmo torque nas duas rodas traseiras (a roda aliviada patina primeiro).
	var rear_count := 0
	for wheel in _wheels:
		if wheel.use_as_traction:
			rear_count += 1
	var per_wheel := drive_force / maxf(rear_count, 1)
	tc_active = false
	if traction_control and per_wheel > 0.0:
		var limit := INF
		for i in _wheels.size():
			if _wheels[i].use_as_traction and _max_force[i] > 0.0:
				# Como a assistência de freio: deixa aderência lateral para a traseira segurar a curva.
				var lat := clampf(_lat_usage[i], 0.0, 0.95)
				limit = minf(limit, _max_force[i] * assist_threshold * maxf(sqrt(1.0 - lat * lat), 0.3))
		if per_wheel > limit:
			per_wheel = limit
			tc_active = true
	if reversing:
		per_wheel = -per_wheel

	var engine_brake := 0.0
	if drive_pedal < 0.02 and gear != GEAR_NEUTRAL:
		engine_brake = engine_braking_force * clampf(speed / 25.0, 0.0, 1.0)
	var holding := speed < 0.5 and drive_pedal < 0.02

	abs_active = false
	for i in _wheels.size():
		var wheel := _wheels[i]
		var brake := brake_force_per_wheel * brake_pedal
		brake *= 2.0 * (brake_bias_front if wheel.use_as_steering else 1.0 - brake_bias_front)
		if not wheel.use_as_steering:
			brake += engine_brake * 0.5
		if brake_assist and speed > 2.0 and _max_force[i] > 0.0:
			# Reserva aderência para a curva: usa só o que sobra da elipse de atrito.
			var lat := clampf(_lat_usage[i], 0.0, 0.95)
			var cap := _max_force[i] * assist_threshold * maxf(sqrt(1.0 - lat * lat), 0.35)
			if brake > cap:
				brake = cap
				abs_active = brake_pedal > 0.05
		if holding:
			brake = maxf(brake, 3000.0)
		if hold:
			brake = maxf(brake, 20000.0)
		_brake_request[i] = brake
		_drive_request[i] = per_wheel if wheel.use_as_traction and not hold else 0.0


## Modelo de pneu: calcula e aplica as forças de contato de cada roda.
func _update_tires(delta: float) -> void:
	var body := global_basis
	var up := body.y
	var com := global_transform * center_of_mass
	var compound := config.compound_grip() if config else 1.0
	var peak := deg_to_rad(peak_slip_angle_deg)
	# B da Magic Formula escolhido para o pico cair exatamente em peak_slip_angle.
	var stiffness_b := tan(PI / (2.0 * tire_shape)) / peak

	# Força vertical total que os pneus precisam suportar (peso + downforce + aceleração vertical).
	var up_speed := linear_velocity.dot(up)
	_vertical_accel = lerpf(_vertical_accel, (up_speed - _prev_up_speed) / delta, 0.2)
	_prev_up_speed = up_speed
	var support := maxf(mass * (9.8 * maxf(up.y, 0.0) + clampf(_vertical_accel, -20.0, 20.0)) + _downforce, 0.0)
	# A compressão de cada mola define como essa força se divide entre as rodas.
	var springs := PackedFloat32Array([0, 0, 0, 0])
	var spring_sum := 0.0
	for i in _wheels.size():
		var wheel := _wheels[i]
		if wheel.is_in_contact():
			var mount := global_transform * _mounts[i]
			var length := (mount - wheel.get_contact_point()).dot(up) - wheel.wheel_radius
			var compression := clampf(wheel.wheel_rest_length - length, 0.0, wheel.suspension_travel)
			springs[i] = wheel.suspension_stiffness * compression
			spring_sum += springs[i]

	for i in _wheels.size():
		var wheel := _wheels[i]
		if not wheel.is_in_contact() or wheel_broken[i]:
			_set_tire(i, 0.0, 0.0, 0.0, TireState.AIR)
			_max_force[i] = 0.0
			_alpha[i] = 0.0
			continue

		var contact := wheel.get_contact_point()
		var normal := wheel.get_contact_normal()

		var fz := support * springs[i] / spring_sum if spring_sum > 0.0 else 0.0

		# Referencial do pneu sobre o chão
		var heading := body.z
		var wheel_angle := wheel_toe[i] + (steering if wheel.use_as_steering else 0.0)
		if wheel_angle != 0.0:
			heading = body * Vector3(sin(wheel_angle), 0.0, cos(wheel_angle))
		var fwd := (heading - normal * heading.dot(normal)).normalized()
		var side := normal.cross(fwd)  # esquerda do pneu

		var vel := linear_velocity + angular_velocity.cross(contact - com)
		var vx := vel.dot(fwd)
		var vy := vel.dot(side)

		# Ângulo de deriva com relaxação (o pneu precisa rolar um pouco para gerar força).
		var target_alpha := atan2(vy, maxf(absf(vx), LOW_SPEED_SLIP))
		var relax := clampf((absf(vx) + 1.0) * delta / relaxation_length, 0.0, 1.0)
		_alpha[i] = lerpf(_alpha[i], target_alpha, relax)

		# Piso: grama e brita têm menos aderência e freiam o carro
		var surface := TrackSurface.of_body(wheel.get_contact_body())
		tire_surface[i] = surface
		var base_mu := front_grip if wheel.use_as_steering else rear_grip
		var surface_grip: float = TrackSurface.GRIP[surface]
		var wear_grip := 1.0 - worn_grip_loss * pow(tire_wear[i], 1.6)
		var mu := base_mu * compound * surface_grip * wheel_grip[i] * wear_grip * maxf(1.0 - load_sensitivity * (fz / nominal_load - 1.0), 0.5)
		var max_force := mu * fz
		_max_force[i] = max_force

		# Força lateral pura (Magic Formula, E = 0)
		var fy := -max_force * sin(tire_shape * atan(stiffness_b * _alpha[i])) * float(TrackSurface.SIDE_GRIP[surface])
		_lat_usage[i] = absf(fy) / maxf(max_force, 1.0)

		# Força longitudinal pedida (motor + freio)
		var fx := _drive_request[i]
		var braking := _brake_request[i] > 0.0 and absf(fx) < 1.0
		if braking:
			fx = -signf(vx) * _brake_request[i] * clampf(absf(vx) / 0.3, 0.0, 1.0)

		# Elipse de atrito
		var state := TireState.GRIP
		var long_usage := absf(fx) / maxf(max_force, 1.0)
		if long_usage > 1.0:
			state = TireState.LOCK if braking else TireState.SPIN
			fx = signf(fx) * max_force * sliding_grip
			fy *= locked_lateral_grip
		else:
			fy *= maxf(sqrt(1.0 - long_usage * long_usage), locked_lateral_grip)
			if absf(_alpha[i]) > peak * 1.2:
				state = TireState.SLIDE

		# Desgaste: potência dissipada no contato (força × velocidade de deslizamento)
		var slide_speed := absf(vy) + (absf(vx) if state == TireState.LOCK or state == TireState.SPIN else 0.0)
		var effort := Vector2(fx, fy).length() / maxf(max_force, 1.0)
		var wear_power := (slide_speed * 0.6 + effort * effort * absf(vx) * 0.012) * fz / nominal_load
		var compound_wear: float = COMPOUND_WEAR[config.tyre_compound] if config else 1.0
		tire_wear[i] = minf(tire_wear[i] + wear_power * compound_wear * tyre_wear_rate * 0.0009 * delta, 1.0)
		var force := fwd * fx + side * fy
		var drag: float = TrackSurface.DRAG[surface] * fz
		if drag > 0.0:
			# Resistência do piso solto (afunda o pneu): contra o movimento nos dois eixos
			force -= fwd * signf(vx) * drag * clampf(absf(vx) / 2.0, 0.0, 1.0)
			force -= side * signf(vy) * drag * 0.5 * clampf(absf(vy) / 2.0, 0.0, 1.0)
		var rumble: float = TrackSurface.RUMBLE[surface]
		if rumble > 0.0 and absf(vx) > 4.0:
			force += normal * randf_range(-1.0, 1.0) * rumble * mass * 0.25 * minf(absf(vx) / 30.0, 1.0)
		apply_force(force, contact - global_position)
		var usage := Vector2(fx, fy).length() / maxf(max_force, 1.0)
		if state != TireState.GRIP:
			usage = maxf(usage, 1.05)
		_set_tire(i, fz, usage, rad_to_deg(_alpha[i]), state)

	_update_smoke()


func _update_steering(delta: float) -> void:
	var vel := linear_velocity
	var speed := vel.length()
	body_slip_angle = 0.0
	if speed > 5.0:
		body_slip_angle = atan2(vel.dot(global_basis.x), absf(vel.dot(global_basis.z)))
	var t := clampf(absf(forward_speed) / steer_speed_reference, 0.0, 1.0)
	var limit := lerpf(max_steer_angle, high_speed_steer_angle, sqrt(t))
	# Permite contraesterçar quando a traseira escapa, mesmo em alta velocidade.
	limit = clampf(maxf(limit, absf(body_slip_angle) + 0.05), 0.0, max_steer_angle)
	var target := steer_input * limit
	var rate := steer_rate * (1.6 if absf(target) < absf(steering) else 1.0)
	steering = move_toward(steering, target, rate * delta)


func _update_handling() -> void:
	handling = Handling.NEUTRAL
	if speed_kmh < 30.0:
		return
	var front := 0.0
	var rear := 0.0
	var rear_spin := false
	for i in _wheels.size():
		var slip := absf(tire_slip_deg[i])
		if _wheels[i].use_as_steering:
			front = maxf(front, slip)
		else:
			rear = maxf(rear, slip)
			rear_spin = rear_spin or tire_state[i] == TireState.SPIN
	var limit := peak_slip_angle_deg
	if (rear > limit and rear - front > 1.5) or (rear_spin and absf(body_slip_angle) > 0.06):
		handling = Handling.OVERSTEER
	elif front > limit and front - rear > 1.5:
		handling = Handling.UNDERSTEER


func _update_drs(delta: float) -> void:
	var allowed := drs_requested and drs_allowed and speed_kmh >= drs_min_speed_kmh and brake_input < 0.05
	if allowed != drs_open:
		drs_open = allowed
		drs_changed.emit(drs_open)
	_drs_amount = move_toward(_drs_amount, 1.0 if drs_open else 0.0, delta * 5.0)


func _apply_aero() -> void:
	var v2 := forward_speed * forward_speed
	var df_area := effective_downforce_area * (1.0 - drs_downforce_reduction * _drs_amount)
	var drag_a := maxf(effective_drag_area * (1.0 - drs_drag_reduction * _drs_amount) + damage_drag, 0.3)
	var downforce := 0.5 * AIR_DENSITY * df_area * v2
	_downforce = downforce
	var down := -global_basis.y
	var front_point := global_basis * Vector3(0.0, 0.25, 1.8)
	var rear_point := global_basis * Vector3(0.0, 0.25, -1.8)
	var front_df := downforce * effective_balance * damage_front_downforce
	var rear_df := downforce * (1.0 - effective_balance) * damage_rear_downforce
	_downforce = front_df + rear_df
	apply_force(down * front_df, front_point)
	apply_force(down * rear_df, rear_point)

	var vel := linear_velocity
	var speed := vel.length()
	if speed > 0.1:
		var drag := 0.5 * AIR_DENSITY * drag_a * speed * speed + rolling_resistance * mass * 9.8
		apply_central_force(-vel / speed * drag)


# ---------------------------------------------------------------------------
# Auxiliares
# ---------------------------------------------------------------------------
func _set_tire(i: int, fz: float, usage: float, slip_deg: float, state: TireState) -> void:
	tire_load[i] = fz
	tire_usage[i] = usage
	tire_slip_deg[i] = slip_deg
	tire_state[i] = state


func _rear_spinning() -> bool:
	for i in _wheels.size():
		if not _wheels[i].use_as_steering and tire_state[i] == TireState.SPIN:
			return true
	return false


func _set_gear(new_gear: int) -> void:
	if new_gear == gear:
		return
	gear = new_gear
	_shift_timer = shift_time
	_reverse_timer = 0.0
	gear_changed.emit(gear)


func _ratio(g: int) -> float:
	if g == GEAR_REVERSE:
		return reverse_ratio
	if g < 1:
		return 0.0
	return gear_ratios[clampi(g - 1, 0, gear_ratios.size() - 1)]


func _rpm_for_gear(g: int) -> float:
	var wheel_rpm := absf(forward_speed) / _wheel_radius() * 60.0 / TAU
	return maxf(idle_rpm, wheel_rpm * _ratio(g))


## Curva de torque simplificada (fração do pico) de um V6 turbo híbrido.
func _torque_at(engine_rpm: float) -> float:
	var x := clampf((engine_rpm - idle_rpm) / (max_rpm - idle_rpm), 0.0, 1.0)
	var curve := 0.72 + 0.28 * sin(x * PI * 0.85)
	return peak_torque_nm * curve


func _wheel_radius() -> float:
	return _wheels[0].wheel_radius if not _wheels.is_empty() else 0.36


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


func _animate_parts() -> void:
	if _drs_flap:
		var open := Basis(Vector3.RIGHT, -deg_to_rad(drs_flap_angle_deg) * _drs_amount)
		_drs_flap.transform = Transform3D(_drs_flap_rest.basis * open, _drs_flap_rest.origin)
	if _steering_wheel:
		var turn := Basis(Vector3.BACK, -steering * steering_wheel_ratio)
		_steering_wheel.transform = Transform3D(_steering_wheel_rest.basis * turn, _steering_wheel_rest.origin)


# ---------------------------------------------------------------------------
# Fumaça dos pneus (feedback visual de perda de aderência)
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
	for i in _wheels.size():
		var smoke := CPUParticles3D.new()
		smoke.name = "TireSmoke%d" % i
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
	for i in _wheels.size():
		var dust := CPUParticles3D.new()
		dust.name = "Dust%d" % i
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


func _update_smoke() -> void:
	var speed := linear_velocity.length()
	for i in _dust.size():
		var loose := tire_surface[i] == TrackSurface.Type.GRAVEL or tire_surface[i] == TrackSurface.Type.GRASS
		_dust[i].emitting = loose and tire_state[i] != TireState.AIR and speed > 4.0
		if _dust[i].emitting:
			var gravel := tire_surface[i] == TrackSurface.Type.GRAVEL
			var tint := Color(0.85, 0.74, 0.55, 0.55) if gravel else Color(0.45, 0.62, 0.3, 0.35)
			if _dust[i].color != tint:
				var fade := Gradient.new()
				fade.set_color(0, tint)
				fade.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
				_dust[i].color = tint
				_dust[i].color_ramp = fade
	for i in _smoke.size():
		var state := tire_state[i]
		var sliding := state == TireState.SPIN or state == TireState.LOCK \
			or (state == TireState.SLIDE and absf(tire_slip_deg[i]) > peak_slip_angle_deg * 1.8)
		_smoke[i].emitting = sliding and linear_velocity.length() > 3.0 or (state == TireState.SPIN and throttle_input > 0.5)
