class_name RaceCamera
extends Camera3D
## Câmera de corrida.
##  * C alterna: Perseguição, Perseguição (longe), T-Cam, Piloto (1ª pessoa) e Capô.
##  * Capô: lente no centro, acima do cockpit, mostrando só as rodas da frente, o bico e os
##    retrovisores (cabeça e corpo do piloto, volante e halo não são desenhados nela).
##  * V (segurar) olha para trás: nas câmeras externas a câmera gira até a frente do carro; na
##    1ª pessoa o piloto vira a cabeça e foca o retrovisor (esquerdo, ou direito se esterçando
##    para a direita); nas câmeras de bordo usa a lente traseira.
##  * O liga/desliga a órbita: arrastar com o mouse (ou analógico direito) gira, a roda do mouse
##    aproxima/afasta e, parada, ela gira sozinha. A órbita nunca entra no chão nem atravessa objetos.
##  * Perseguição com vida: afasta ao acelerar/no boost e aproxima na frenagem, desliza para fora e
##    inclina um pouco nas curvas olhando para dentro delas, acompanha a derrapagem, treme de leve
##    em alta velocidade, nas zebras/brita e forte nas batidas; FOV abre no boost.
## Segue a transformação interpolada do carro (physics interpolation ligada no projeto).

signal mode_changed(mode_name: String)

enum Mode { CHASE, CHASE_FAR, T_CAM, DRIVER, HOOD, ORBIT }

const MODE_NAMES := ["Perseguição", "Perseguição (longe)", "T-Cam", "Piloto (1ª pessoa)", "Capô", "Órbita"]
## Ordem do botão C (a órbita tem botão próprio).
const CYCLE := [Mode.CHASE, Mode.CHASE_FAR, Mode.T_CAM, Mode.DRIVER, Mode.HOOD]

## Câmeras de bordo fixas, no espaço do carro (frente = +Z). A câmera olha para -Z, por isso
## as voltadas para a frente giram 180°; as traseiras usam a base sem giro.
var onboard := {
	Mode.T_CAM: Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -0.06), Vector3(0, 1.13, -0.62)),
	Mode.HOOD: Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -0.05), Vector3(0, 1.0, -0.15)),
}
var onboard_rear := {
	Mode.T_CAM: Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 1.13, -0.70)),
	# Olhar para trás do capô: usa a lente traseira da T-Cam (do capô só se veria o cockpit)
	Mode.HOOD: Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 1.13, -0.70)),
}

@export var target_path: NodePath
@export var mode: Mode = Mode.CHASE

@export_group("Perseguição")
@export var chase_distance := 6.2
@export var chase_height := 1.9
@export var far_distance := 10.5
@export var far_height := 3.2
## Quão rápido a câmera alinha com a direção do carro (maior = mais rígida).
@export var direction_smoothing := 5.0
@export var base_fov := 68.0
## Aumento de FOV na velocidade máxima (sensação de velocidade).
@export var speed_fov_boost := 16.0
## Distância a mais por G longitudinal (acelerando afasta, freando aproxima), em m/G.
@export var chase_accel_pull := 0.28
## Deslize lateral para fora da curva (m/G) e inclinação (rad/G).
@export var chase_lateral_swing := 0.3
@export var chase_roll_per_g := 0.022
## Quanto o olhar entra na curva pela velocidade de giro do carro.
@export var chase_look_into_turn := 0.9
## Quanto a câmera acompanha a direção do movimento numa derrapagem (0..1).
@export var chase_slide_follow := 0.45
## Tremida: na velocidade máxima, em zebras/brita e em batidas (m).
@export var shake_speed := 0.018
@export var shake_surface := 0.045
## Tremor extra fora da pista (brita sacode mais que a grama).
@export var shake_offtrack := 0.14
@export var shake_impact := 0.22
## FOV a mais com o boost ligado.
@export var boost_fov := 6.0
## Toques pequenos no volante quase não mexem a câmera: desvios de direção menores que
## small_turn_deg são seguidos devagar (small_turn_smoothing); curvas de verdade, na velocidade
## normal. O olhar para dentro da curva e o deslize lateral só começam acima de uma zona morta.
@export var small_turn_deg := 8.0
@export var small_turn_smoothing := 0.6
@export var look_deadzone := 0.18
@export var swing_deadzone_g := 0.6

@export_group("Piloto (1ª pessoa)")
## Posição dos olhos no espaço do carro.
@export var driver_eye := Vector3(0, 0.735, -0.04)
@export var driver_fov := 78.0
@export var driver_pitch_deg := -7.0
## Deslocamento da cabeça por G (m) e inclinação por G lateral (rad).
@export var head_shift_per_g := 0.012
@export var head_roll_per_g := 0.03
## Quanto a cabeça acompanha o esterço (olhar para dentro da curva).
@export var head_look_into_turn := 0.45
## FOV ao focar o retrovisor (zoom).
@export var mirror_zoom_fov := 24.0

@export_group("Olhar para trás")
@export var look_back_speed := 6.0

@export_group("Órbita")
@export var orbit_min_distance := 2.5
@export var orbit_max_distance := 20.0
@export var orbit_mouse_sensitivity := 0.006
@export var orbit_stick_speed := 2.2
## Velocidade do giro automático quando ninguém mexe (rad/s).
@export var orbit_auto_speed := 0.25
@export var orbit_auto_delay := 3.0
## Altura mínima acima do chão (m).
@export var orbit_ground_clearance := 0.3
## Semi-eixos (lateral, vertical, longitudinal) do envelope em volta do carro que a órbita não invade.
@export var orbit_car_envelope := Vector3(1.9, 1.5, 3.7)

var target: F1Car
var looking_back := false
## Câmera controlada por fora (apresentação antes da largada, IntroDirector).
var cinematic := false
var _onboard_gear: CarOnboard
var _direction := Vector3.BACK
var _height := 1.9
var _back_t := 0.0
var _head_g := Vector3.ZERO
## G local sem suavizar (para detectar batidas) e o "trauma" da tremida (0..1, decai).
var _raw_g := Vector3.ZERO
var _trauma := 0.0
var _shake_t := 0.0
var _chase_pull := 0.0
var _look_yaw := 0.0
var _cam_lat_g := 0.0
var _noise := FastNoiseLite.new()
var _prev_velocity := Vector3.ZERO
var _prev_pos := Vector3.ZERO
var _mirror_index := 0
var _mode_before_orbit: Mode = Mode.CHASE
var _orbit_yaw := 0.0
var _orbit_pitch := 0.3
var _orbit_distance := 7.0
var _orbit_idle := 0.0


func _ready() -> void:
	# Efeito Doppler nos sons 3D (carros passando pela câmera de órbita, etc.)
	doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	target = get_node_or_null(target_path) as F1Car
	if target:
		_direction = target.global_basis.z
		_onboard_gear = target.get_node_or_null("Onboard") as CarOnboard
	_apply_mode_settings()
	# Campo de visão das Configurações → Tela (o do piloto acompanha, 10° a mais)
	var settings := get_node_or_null("/root/Settings") as GameSettings
	if settings:
		_apply_fov_setting(settings)
		settings.changed.connect(_on_settings_changed)


func _on_settings_changed(section: String, key: String) -> void:
	if section == "display" and (key == "fov" or key == ""):
		_apply_fov_setting(get_node("/root/Settings") as GameSettings)


func _apply_fov_setting(settings: GameSettings) -> void:
	base_fov = float(settings.get_value("display", "fov"))
	driver_fov = base_fov + 10.0


## Depois de uma cena controlada por fora: a perseguição recomeça atrás do carro, sem salto.
func reset_after_cinematic() -> void:
	if target:
		var fwd := target.global_basis.z
		fwd.y = 0.0
		if fwd.length_squared() > 0.001:
			_direction = fwd.normalized()
		_height = far_height if mode == Mode.CHASE_FAR else chase_height
	_chase_pull = 0.0
	_look_yaw = 0.0
	_cam_lat_g = 0.0
	reset_physics_interpolation()


func get_mode_name() -> String:
	return MODE_NAMES[mode]


func set_mode(new_mode: Mode) -> void:
	if new_mode == Mode.ORBIT and mode != Mode.ORBIT:
		_mode_before_orbit = mode
		_enter_orbit()
	mode = new_mode
	_apply_mode_settings()
	mode_changed.emit(MODE_NAMES[mode])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_next"):
		var current: Mode = _mode_before_orbit if mode == Mode.ORBIT else mode
		set_mode(CYCLE[(CYCLE.find(current) + 1) % CYCLE.size()])
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_orbit"):
		set_mode(_mode_before_orbit if mode == Mode.ORBIT else Mode.ORBIT)
		get_viewport().set_input_as_handled()
	elif mode == Mode.ORBIT:
		_orbit_input(event)


func _process(delta: float) -> void:
	if target == null or cinematic:
		return
	var xf := target.get_global_transform_interpolated()
	looking_back = mode != Mode.ORBIT and Input.is_action_pressed("look_back")
	_back_t = move_toward(_back_t, 1.0 if looking_back else 0.0, look_back_speed * delta)
	var back := smoothstep(0.0, 1.0, _back_t)
	var speed_t := clampf(target.speed_kmh / 330.0, 0.0, 1.0)
	var target_fov := base_fov + speed_fov_boost * speed_t * speed_t

	match mode:
		Mode.ORBIT:
			_update_orbit(xf, delta)
			target_fov = base_fov
		Mode.CHASE, Mode.CHASE_FAR:
			_update_chase(xf, delta, back)
			if target.boost_active:
				target_fov += boost_fov * (1.0 - back)
		Mode.DRIVER:
			var head := xf * _driver_head()
			if target.steer_input < -0.2:
				_mirror_index = 1
			elif target.steer_input > 0.2 or _back_t <= 0.0:
				_mirror_index = 0
			var mirror := _onboard_gear.get_mirror_position(_mirror_index) if _onboard_gear else head.origin
			var at_mirror := Transform3D(Basis(), head.origin).looking_at(mirror, xf.basis.y)
			global_transform = head.interpolate_with(at_mirror, back)
			target_fov = lerpf(driver_fov + speed_fov_boost * 0.4 * speed_t, mirror_zoom_fov, back)
		_:
			global_transform = (xf * onboard[mode]).interpolate_with(xf * onboard_rear[mode], back)

	fov = lerpf(fov, target_fov, 1.0 - exp(-(12.0 if looking_back else 3.0) * delta))
	if _onboard_gear:
		_onboard_gear.mirrors_active = mode in [Mode.DRIVER, Mode.T_CAM, Mode.HOOD]


# --- Perseguição ---------------------------------------------------------------
func _update_chase(xf: Transform3D, delta: float, back: float) -> void:
	var far := mode == Mode.CHASE_FAR
	var distance := far_distance if far else chase_distance
	var height := far_height if far else chase_height
	# Na câmera longe os efeitos são mais discretos; olhando para trás, nenhum
	var life := (0.65 if far else 1.0) * (1.0 - back)
	var forward := xf.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = _direction
	forward = forward.normalized()
	# Derrapagem: a câmera puxa para a direção em que o carro está indo de verdade
	var vel := target.linear_velocity
	vel.y = 0.0
	if vel.length() > 8.0:
		var slide := clampf(absf(target.body_slip_angle) / 0.5, 0.0, 1.0) * chase_slide_follow
		forward = forward.slerp(vel.normalized(), slide).normalized()
	# Desvio pequeno (toque no volante): a câmera segue devagar; curva de verdade: rápido
	var diff := rad_to_deg(_direction.angle_to(forward))
	var follow := lerpf(small_turn_smoothing, direction_smoothing, smoothstep(small_turn_deg * 0.4, small_turn_deg * 1.6, diff))
	_direction = _direction.slerp(forward, 1.0 - exp(-follow * delta)).normalized()
	_height = lerpf(_height, height, 1.0 - exp(-4.0 * delta))
	# Inércia: afasta acelerando, aproxima freando (G longitudinal suavizado)
	var pull := clampf(_head_g.z * chase_accel_pull, -1.1, 0.9) * life
	_chase_pull = lerpf(_chase_pull, pull, 1.0 - exp(-3.0 * delta))
	var left := Vector3.UP.cross(_direction).normalized()
	# G lateral com zona morta e resposta mais lenta (toques curtos não balançam a câmera)
	var g_in := clampf(_head_g.x, -4.0, 4.0)
	g_in = signf(g_in) * maxf(absf(g_in) - swing_deadzone_g, 0.0)
	_cam_lat_g = lerpf(_cam_lat_g, g_in, 1.0 - exp(-2.5 * delta))
	var lat_g := _cam_lat_g
	# Olhar para trás: a câmera dá a volta por cima/lado do carro (sem atravessá-lo).
	var dir := _direction.rotated(Vector3.UP, PI * back)
	var focus := xf.origin + Vector3.UP * 0.55
	var pos := focus - dir * (lerpf(distance, distance * 0.85, back) + _chase_pull) 		+ Vector3.UP * (_height + sin(PI * back) * 0.8 - clampf(_head_g.y, -2.0, 2.0) * 0.05 * life) 		- left * lat_g * chase_lateral_swing * life
	# Olha para dentro da curva (velocidade de giro do carro)
	var yaw_in := clampf(target.angular_velocity.y, -1.5, 1.5)
	yaw_in = signf(yaw_in) * maxf(absf(yaw_in) - look_deadzone, 0.0)
	_look_yaw = lerpf(_look_yaw, yaw_in, 1.0 - exp(-2.5 * delta))
	var look := focus + dir * 4.0 + left * _look_yaw * chase_look_into_turn * life
	pos += _shake(delta, life)
	var up := Vector3.UP.rotated(dir, -lat_g * chase_roll_per_g * life)
	global_transform = Transform3D(Basis(), pos).looking_at(look, up)


## Tremida da câmera: alta velocidade, piso (zebra, brita, grama) e batidas (trauma que decai).
func _shake(delta: float, life: float) -> Vector3:
	_shake_t += delta
	_trauma = maxf(_trauma - delta * 1.4, 0.0)
	var kmh := target.speed_kmh
	var amount := shake_speed * smoothstep(200.0, 340.0, kmh)
	var rough := 0.0
	var off := 0.0
	for k in target.tire_surface.size():
		if target.tire_state[k] == F1Car.TireState.AIR:
			continue
		match target.tire_surface[k]:
			TrackSurface.Type.KERB:
				rough += 0.25
			TrackSurface.Type.GRAVEL:
				off += 0.25
			TrackSurface.Type.GRASS:
				off += 0.13
	amount += shake_surface * minf(rough, 1.0) * clampf(kmh / 120.0, 0.0, 1.0)
	amount += shake_offtrack * minf(off, 1.0) * clampf(kmh / 70.0, 0.15, 1.0)
	amount += shake_impact * _trauma * _trauma
	if amount <= 0.0005:
		return Vector3.ZERO
	var f := 18.0 + 30.0 * _trauma + 10.0 * minf(off, 1.0)
	return Vector3(_noise.get_noise_2d(_shake_t * f, 0.0), _noise.get_noise_2d(_shake_t * f, 50.0),
		_noise.get_noise_2d(_shake_t * f, 100.0)) * amount * life


# --- Piloto ----------------------------------------------------------------------
## G do carro medido no passo de física (intervalo fixo): por quadro, com FPS diferente da física,
## a velocidade muda aos saltos e a leitura sairia cheia de picos.
func _physics_process(delta: float) -> void:
	if target:
		_update_head_g(target.global_transform, delta)


func _update_head_g(xf: Transform3D, delta: float) -> void:
	var velocity := target.linear_velocity
	var accel := (velocity - _prev_velocity) / maxf(delta, 0.0001)
	_prev_velocity = velocity
	# Teletransporte (recolocar o carro, ida ao box): salto de posição maior que a velocidade explica
	var jump := xf.origin.distance_to(_prev_pos)
	_prev_pos = xf.origin
	if jump > (velocity.length() + 10.0) * delta * 3.0:
		_raw_g = Vector3.ZERO
		return
	var local := xf.basis.inverse() * accel / 9.8
	# Batida: pico de desaceleração muito acima do que pneus e freios fazem (> 7 G)
	if local.length() > 7.0 and _raw_g.length() < 7.0:
		_trauma = minf(_trauma + (local.length() - 7.0) / 12.0, 1.0)
	_raw_g = local
	_head_g = _head_g.lerp(local.clamp(Vector3(-5, -5, -6), Vector3(5, 5, 6)), 1.0 - exp(-5.0 * delta))


## Pose da cabeça no espaço do carro: inércia joga a cabeça para fora da curva e para frente
## na frenagem; o olhar acompanha o esterço.
func _driver_head() -> Transform3D:
	var yaw := target.steering * head_look_into_turn
	var roll := -_head_g.x * head_roll_per_g
	var offset := Vector3(-_head_g.x * head_shift_per_g, 0.0, -_head_g.z * head_shift_per_g * 0.7)
	var basis := Basis(Vector3.UP, PI + yaw) * Basis(Vector3.RIGHT, deg_to_rad(driver_pitch_deg)) \
		* Basis(Vector3.BACK, roll)
	return Transform3D(basis, driver_eye + offset)


# --- Órbita ----------------------------------------------------------------------
func _enter_orbit() -> void:
	if target == null:
		return
	var xf := target.global_transform
	var pivot := xf.origin + Vector3.UP * 0.45
	var rel := global_position - pivot
	var dist := maxf(rel.length(), 0.1)
	_orbit_distance = clampf(dist, orbit_min_distance, orbit_max_distance)
	_orbit_pitch = clampf(asin(clampf(rel.y / dist, -1.0, 1.0)), -0.15, 1.45)
	_orbit_yaw = atan2(rel.x, rel.z) - _heading(xf)
	_orbit_idle = 0.0


func _orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
			_orbit_yaw -= motion.relative.x * orbit_mouse_sensitivity
			_orbit_pitch += motion.relative.y * orbit_mouse_sensitivity
			_orbit_idle = 0.0
	elif event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance *= 0.9
			_orbit_idle = 0.0
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance *= 1.1
			_orbit_idle = 0.0


func _update_orbit(xf: Transform3D, delta: float) -> void:
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > 0.15:
		_orbit_yaw -= stick.x * orbit_stick_speed * delta
		_orbit_pitch += stick.y * orbit_stick_speed * 0.7 * delta
		_orbit_idle = 0.0
	_orbit_idle += delta
	if _orbit_idle > orbit_auto_delay:
		_orbit_yaw += orbit_auto_speed * delta
	_orbit_pitch = clampf(_orbit_pitch, -0.15, 1.45)
	_orbit_distance = clampf(_orbit_distance, orbit_min_distance, orbit_max_distance)

	var yaw := _heading(xf) + _orbit_yaw
	var dir := Vector3(sin(yaw) * cos(_orbit_pitch), sin(_orbit_pitch), cos(yaw) * cos(_orbit_pitch))
	var pivot := xf.origin + Vector3.UP * 0.45
	# Distância mínima na direção atual = borda de um elipsoide em volta do carro (não entra nele).
	var local := xf.basis.inverse() * dir
	var e := orbit_car_envelope
	var min_distance := 1.0 / sqrt(pow(local.x / e.x, 2) + pow(local.y / e.y, 2) + pow(local.z / e.z, 2))
	_orbit_distance = maxf(_orbit_distance, min_distance)
	var pos := pivot + dir * _orbit_distance

	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [target.get_rid()]
	# Não atravessa objetos entre o carro e a câmera
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pivot, pos, 1, exclude))
	if hit:
		pos = hit.position - dir * 0.2
	# Nunca abaixo do chão: mede a altura do solo embaixo da câmera
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		pos + Vector3.UP * 50.0, pos - Vector3.UP * 50.0, 1, exclude))
	if ground:
		pos.y = maxf(pos.y, ground.position.y + orbit_ground_clearance)
	else:
		pos.y = maxf(pos.y, orbit_ground_clearance)
	global_transform = Transform3D(Basis(), pos).looking_at(pivot, Vector3.UP)


static func _heading(xf: Transform3D) -> float:
	return atan2(xf.basis.z.x, xf.basis.z.z)


func _apply_mode_settings() -> void:
	near = 0.02 if mode == Mode.DRIVER else (0.03 if onboard.has(mode) else 0.08)
	# Na 1ª pessoa a cabeça do piloto fica invisível (estaríamos dentro do capacete).
	cull_mask = 0xFFFFF
	if mode == Mode.DRIVER:
		cull_mask &= ~CarAssembly.HEAD_LAYER
	elif mode == Mode.HOOD:
		cull_mask &= ~(CarAssembly.HEAD_LAYER | CarAssembly.INTERIOR_LAYER)
	_back_t = 0.0
	reset_physics_interpolation()
