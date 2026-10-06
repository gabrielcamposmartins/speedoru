class_name CarAudio
extends Node3D
## Sons do carro (gerados por tools/generate_car_sounds.py em assets/audio/car/).
##
##  * Motor: loops gravados em 7 giros, com e sem carga. Os dois loops vizinhos do giro atual são
##    misturados (equal power) e o pitch acompanha o rpm; o acelerador mistura carga/sem carga.
##    Corte de giro no limitador.
##  * Turbo, assobio das engrenagens (forte ao tirar o pé), vento, pneu cantando (deriva), pneu
##    arrastando (travado/patinando), brita, grama e zebra (batidas no ritmo da velocidade).
##  * Sons curtos: trocas de marcha, estouros do escapamento ao aliviar em giro alto, DRS e batidas.
## Tudo vai para o bus "Car" (compressor). Na câmera do piloto liga um passa-baixa (capacete).

const DIR := "res://assets/audio/car/"
const ENGINE_RPMS: Array[float] = [4000.0, 5500.0, 7000.0, 8500.0, 10000.0, 11500.0, 13000.0]
const LOOPS := ["turbo", "gear_whine", "wind", "tire_squeal", "tire_scrub", "gravel", "grass", "kerb", "scrape", "boost"]
const HELMET_EFFECT := 1

@export var bus := &"Car"
@export_range(-30.0, 12.0) var engine_db := 0.0
@export_range(-30.0, 12.0) var effects_db := -2.0
## Distância (m) em que o som começa a cair (atenuação 3D).
@export var unit_size := 14.0
@export var backfires := true
## Velocidade (m/s) em que as batidas da zebra soam no pitch original (20 batidas/s, listras de 2 m).
@export var kerb_reference_speed := 40.0

var car: F1Car
var engine_load := 0.0
## Raspando no muro/chão (0..1), escrito pelo CarDamage.
var scrape_level := 0.0
var _boost_level := 0.0
var _on: Array[AudioStreamPlayer3D] = []
var _off: Array[AudioStreamPlayer3D] = []
var _loops := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _shots := {}
var _time := 0.0
var _prev_throttle := 0.0
var _prev_gear := 1
var _pops_left := 0
var _pop_timer := 0.0
var _prev_velocity := Vector3.ZERO
var _prev_position := Vector3.ZERO
var _impact_cooldown := 0.0
var _bus_index := -1


func _ready() -> void:
	car = get_parent() as F1Car
	if car == null:
		return
	var engine_pos := Vector3(0, 0.55, -1.1)
	for rpm in ENGINE_RPMS:
		_on.append(_make_player("engine_on_%d.wav" % int(rpm), engine_pos, true))
		_off.append(_make_player("engine_off_%d.wav" % int(rpm), engine_pos, true))
	for loop_name in LOOPS:
		var pos := engine_pos if loop_name == "turbo" or loop_name == "gear_whine" else Vector3(0, 0.3, 0)
		_loops[loop_name] = _make_player(loop_name + ".wav", pos, true)
	for i in 6:
		_pool.append(_make_player("", Vector3.ZERO, false))
	for shot in ["shift_up", "shift_down", "backfire_1", "backfire_2", "backfire_3", "impact_1", "impact_2", "drs",
			"crack_1", "crack_2"]:
		_shots[shot] = load(DIR + shot + ".wav")
	car.gear_changed.connect(_on_gear_changed)
	car.drs_changed.connect(func(_open: bool): play_shot("drs", Vector3(0, 0.9, -2.4), -8.0))
	_prev_gear = car.gear
	_prev_position = car.global_position
	_bus_index = AudioServer.get_bus_index(bus)


func _make_player(file: String, pos: Vector3, loop: bool) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	if file != "":
		p.stream = load(DIR + file)
	p.bus = bus
	p.unit_size = unit_size
	p.max_db = 6.0
	p.position = pos
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	p.attenuation_filter_cutoff_hz = 9000.0
	p.volume_db = -80.0
	add_child(p)
	if loop:
		p.play()
		p.stream_paused = true
	return p


## Toca um som curto (posição local no carro).
func play_shot(shot: String, pos: Vector3, db := 0.0, pitch := 1.0) -> void:
	var player: AudioStreamPlayer3D = null
	for p in _pool:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _pool[0]
		_pool.push_back(_pool.pop_front())
	player.stream = _shots[shot]
	player.position = pos
	player.volume_db = db + effects_db
	player.pitch_scale = pitch
	player.play()


## Nível linear (0..1) e pitch de um loop; pausa os que estão em silêncio.
func _set_loop(p: AudioStreamPlayer3D, level: float, pitch := 1.0, offset_db := 0.0) -> void:
	if level < 0.003:
		if not p.stream_paused:
			p.stream_paused = true
		return
	if p.stream_paused:
		p.stream_paused = false
	p.volume_db = linear_to_db(level) + offset_db
	p.pitch_scale = clampf(pitch, 0.3, 3.5)


func get_loop_level(loop_name: String) -> float:
	var p: AudioStreamPlayer3D = _loops[loop_name]
	return 0.0 if p.stream_paused else db_to_linear(p.volume_db - effects_db)


## Pesos (0..1) das camadas do motor ligadas — para depuração/testes.
func get_engine_layers() -> Dictionary:
	var out := {}
	for i in ENGINE_RPMS.size():
		for pair in [[_on[i], "on"], [_off[i], "off"]]:
			var p: AudioStreamPlayer3D = pair[0]
			if not p.stream_paused:
				out["%s_%d" % [pair[1], int(ENGINE_RPMS[i])]] = [db_to_linear(p.volume_db - engine_db), p.pitch_scale]
	return out


func _process(delta: float) -> void:
	if car == null:
		return
	_time += delta
	var rpm := car.rpm
	var reversing := car.gear == F1Car.GEAR_REVERSE
	var pedal := car.reverse_input if reversing else car.throttle_input
	var target := pedal
	if car.is_shifting():
		target *= 0.3
	if car.tc_active:
		target *= 0.8
	engine_load = move_toward(engine_load, target, delta * (12.0 if target > engine_load else 7.0))
	_update_engine(rpm, delta)
	_update_effects(rpm)
	_update_backfire(rpm, pedal, delta)
	_update_helmet()


func _update_engine(rpm: float, _delta: float) -> void:
	var r := clampf(rpm, ENGINE_RPMS[0], ENGINE_RPMS[ENGINE_RPMS.size() - 1] - 1.0)
	var lo := 0
	while lo < ENGINE_RPMS.size() - 2 and r >= ENGINE_RPMS[lo + 1]:
		lo += 1
	var t := (r - ENGINE_RPMS[lo]) / (ENGINE_RPMS[lo + 1] - ENGINE_RPMS[lo])
	var loudness := lerpf(0.55, 1.0, clampf((rpm - 4000.0) / 9000.0, 0.0, 1.0))
	# Corte de ignição no limitador: o som "pipoca"
	var limiter := 1.0
	if rpm > car.max_rpm - 120.0 and engine_load > 0.5:
		limiter = 0.5 + 0.5 * smoothstep(-0.4, 0.4, sin(_time * TAU * 18.0))
	var on_gain := engine_load * limiter
	var off_gain := (1.0 - engine_load) * 0.9
	for i in ENGINE_RPMS.size():
		var w := 0.0
		if i == lo:
			w = cos(t * PI * 0.5)
		elif i == lo + 1:
			w = sin(t * PI * 0.5)
		var pitch := rpm / ENGINE_RPMS[i]
		_set_loop(_on[i], w * on_gain * loudness, pitch, engine_db)
		_set_loop(_off[i], w * off_gain * loudness, pitch, engine_db)


func _update_effects(rpm: float) -> void:
	var speed := car.linear_velocity.length()
	var kmh := speed * 3.6
	# Turbo/MGU-H: assobio que sobe com o giro, com carga
	_set_loop(_loops["turbo"], engine_load * smoothstep(5000.0, 12000.0, rpm) * 0.32, 0.55 + 0.6 * rpm / 12000.0, effects_db)
	# Engrenagens retas: aparecem ao aliviar o acelerador em velocidade
	var whine := ((1.0 - engine_load) * 0.3 + 0.05) * smoothstep(15.0, 120.0, kmh)
	_set_loop(_loops["gear_whine"], whine, 0.35 + kmh / 260.0, effects_db)
	# Vento
	_set_loop(_loops["wind"], pow(clampf(speed / 90.0, 0.0, 1.0), 2.0) * 0.45, 0.75 + kmh / 450.0, effects_db)

	# Pneus e pisos
	var squeal := 0.0
	var scrub := 0.0
	var on := {TrackSurface.Type.GRAVEL: 0, TrackSurface.Type.GRASS: 0, TrackSurface.Type.KERB: 0}
	var wheels := car.tire_state.size()
	for i in wheels:
		var state := car.tire_state[i]
		if state == F1Car.TireState.AIR:
			continue
		var surface := car.tire_surface[i]
		if on.has(surface):
			on[surface] += 1
		if surface == TrackSurface.Type.GRASS or surface == TrackSurface.Type.GRAVEL:
			continue  # piso solto não canta
		if state == F1Car.TireState.LOCK or state == F1Car.TireState.SPIN:
			scrub += 1.0
		else:
			squeal = maxf(squeal, clampf((car.tire_usage[i] - 0.9) / 0.35, 0.0, 1.0))
	var moving := clampf(speed / 8.0, 0.0, 1.0)
	_set_loop(_loops["tire_squeal"], squeal * moving * 0.55, 0.9 + 0.25 * squeal + kmh / 1500.0, effects_db)
	_set_loop(_loops["tire_scrub"], clampf(scrub / 2.0, 0.0, 1.0) * moving * 0.6, 0.7 + kmh / 220.0, effects_db)
	var loose := clampf(speed / 15.0, 0.0, 1.0)
	_set_loop(_loops["gravel"], float(on[TrackSurface.Type.GRAVEL]) / wheels * loose * 0.8, 0.8 + kmh / 400.0, effects_db)
	_set_loop(_loops["grass"], float(on[TrackSurface.Type.GRASS]) / wheels * loose * 0.6, 0.8 + kmh / 400.0, effects_db)
	_set_loop(_loops["scrape"], scrape_level * 0.9, 0.8 + kmh / 400.0, effects_db)
	_boost_level = move_toward(_boost_level, 1.0 if car.boost_active else 0.0, get_process_delta_time() * 5.0)
	_set_loop(_loops["boost"], _boost_level * 0.55, 0.9 + kmh / 900.0, effects_db)
	_set_loop(_loops["kerb"], float(on[TrackSurface.Type.KERB]) / wheels * clampf(speed / 5.0, 0.0, 1.0) * 0.8,
		speed / kerb_reference_speed, effects_db)


## Estouros no escapamento ao tirar o pé em giro alto.
func _update_backfire(rpm: float, pedal: float, delta: float) -> void:
	if backfires and _prev_throttle > 0.7 and pedal < 0.2 and rpm > 8500.0:
		_pops_left = randi_range(1, 3)
		_pop_timer = randf_range(0.04, 0.15)
	_prev_throttle = pedal
	if _pops_left > 0:
		_pop_timer -= delta
		if _pop_timer <= 0.0:
			play_shot("backfire_%d" % randi_range(1, 3), Vector3(0, 0.4, -2.6), randf_range(-8.0, -3.0), randf_range(0.9, 1.15))
			_pops_left -= 1
			_pop_timer = randf_range(0.08, 0.3)


func _on_gear_changed(new_gear: int) -> void:
	var up := new_gear > _prev_gear and new_gear > 0
	_prev_gear = new_gear
	if new_gear == F1Car.GEAR_NEUTRAL:
		return
	play_shot("shift_up" if up else "shift_down", Vector3(0, 0.4, -1.4), -6.0 if up else -9.0, randf_range(0.95, 1.05))
	if up and backfires and car.rpm > 9000.0 and randf() < 0.25:
		_pops_left = 1
		_pop_timer = 0.03


func _physics_process(delta: float) -> void:
	if car == null:
		return
	# Batida: mudança brusca de velocidade num único passo (> ~30 G), ignorando teleportes
	_impact_cooldown -= delta
	var v := car.linear_velocity
	var jump := car.global_position.distance_to(_prev_position)
	var dv := (v - _prev_velocity).length()
	var was_reset := Engine.get_physics_frames() - car.reset_frame < 3
	if _impact_cooldown <= 0.0 and jump < 5.0 and dv > 2.5 and not was_reset:
		var strength := clampf((dv - 2.5) / 12.0, 0.0, 1.0)
		play_shot("impact_1" if strength > 0.5 else "impact_2", Vector3(0, 0.4, 0), lerpf(-10.0, 2.0, strength),
			randf_range(0.9, 1.1))
		_impact_cooldown = 0.25
	_prev_velocity = v
	_prev_position = car.global_position


## Na câmera do piloto o som passa por um passa-baixa (capacete).
func _update_helmet() -> void:
	if _bus_index < 0 or AudioServer.get_bus_effect_count(_bus_index) <= HELMET_EFFECT:
		return
	var cam := get_viewport().get_camera_3d()
	var inside := cam is RaceCamera and (cam as RaceCamera).mode == RaceCamera.Mode.DRIVER
	if AudioServer.is_bus_effect_enabled(_bus_index, HELMET_EFFECT) != inside:
		AudioServer.set_bus_effect_enabled(_bus_index, HELMET_EFFECT, inside)
