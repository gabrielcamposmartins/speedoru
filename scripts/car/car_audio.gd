class_name CarAudio
extends CarAudioCore
## Sons do carro (gerados por tools/generate_car_sounds.py em assets/audio/car/).
##
##  * Motor: loops gravados em 7 giros, com e sem carga. Os dois loops vizinhos do giro atual são
##    misturados (equal power) e o pitch acompanha o rpm; o acelerador mistura carga/sem carga.
##    Corte de giro no limitador.
##  * Turbo, assobio das engrenagens (forte ao tirar o pé), vento, pneu cantando (deriva), pneu
##    arrastando (travado/patinando), brita, grama e zebra (batidas no ritmo da velocidade).
##  * Sons curtos: trocas de marcha, ronco do escapamento ao aliviar em giro alto, DRS e batidas.
## Tudo vai para o bus "Car" (compressor). Na câmera do piloto liga um passa-baixa (capacete).
##
## Carros dos outros (make_rival): bus "Rivals" separado (o compressor do seu motor não os abafa),
## som chegando de mais longe, estéreo mais marcado (dá para saber de que lado vem) e um reforço
## de volume quando o carro está perto da câmera — ao lado ou colado atrás.
##
## Desempenho: cada AudioStreamPlayer3D tocando (mesmo pausado) recalcula posição, doppler e áreas
## a cada passo de física. Os loops em silêncio ficam parados (stop, não pausa) e os rivais longe
## da câmera (RIVAL_CULL m) ficam mudos.
##
## A mistura a cada quadro, os sons curtos (play_shot) e as batidas rodam no código nativo
## (CarAudioCore, native/src/audio.rs, com as mesmas constantes); aqui os players são criados.
## Propriedades de lá: engine_db, effects_db, backfires, kerb_reference_speed, rival, engine_load,
## scrape_level.

const DIR := "res://assets/audio/car/"
const ENGINE_RPMS: Array[float] = [4000.0, 5500.0, 7000.0, 8500.0, 10000.0, 11500.0, 13000.0]
## A ordem importa: o CarAudioCore recebe os loops nesta ordem.
const LOOPS := ["turbo", "gear_whine", "wind", "tire_squeal", "tire_scrub", "gravel", "grass", "kerb", "scrape", "boost"]
const HELMET_EFFECT := 1

@export var bus := &"Car"
## Distância (m) em que o som começa a cair (atenuação 3D).
@export var unit_size := 14.0

const RIVAL_UNIT_SIZE := 24.0
const RIVAL_PANNING := 1.8

var car: F1Car
var _on: Array[AudioStreamPlayer3D] = []
var _off: Array[AudioStreamPlayer3D] = []
var _loops := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _shots := {}
var _prev_gear := 1


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
	_bus_index = AudioServer.get_bus_index(bus)
	_core_setup(car, _on, _off, LOOPS.map(func(n: String) -> AudioStreamPlayer3D: return _loops[n]), _pool, _shots)


## Som de um carro adversário (bots, outros jogadores): ver o comentário do topo.
func make_rival(p_engine_db := -1.0, p_effects_db := -4.0) -> void:
	rival = true
	engine_db = p_engine_db
	effects_db = p_effects_db
	if AudioServer.get_bus_index(&"Rivals") >= 0:
		bus = &"Rivals"
	_bus_index = AudioServer.get_bus_index(bus)
	for p in find_children("*", "AudioStreamPlayer3D", false, false):
		var player := p as AudioStreamPlayer3D
		player.bus = bus
		player.unit_size = RIVAL_UNIT_SIZE
		player.panning_strength = RIVAL_PANNING


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
	return p


func get_loop_level(loop_name: String) -> float:
	var p: AudioStreamPlayer3D = _loops[loop_name]
	return db_to_linear(p.volume_db - (effects_db + _near_db)) if p.playing else 0.0


## Pesos (0..1) das camadas do motor ligadas — para depuração/testes.
func get_engine_layers() -> Dictionary:
	var out := {}
	for i in ENGINE_RPMS.size():
		for pair in [[_on[i], "on"], [_off[i], "off"]]:
			var p: AudioStreamPlayer3D = pair[0]
			if p.playing:
				out["%s_%d" % [pair[1], int(ENGINE_RPMS[i])]] = [db_to_linear(p.volume_db - (engine_db + _near_db)), p.pitch_scale]
	return out


func _on_gear_changed(new_gear: int) -> void:
	var up := new_gear > _prev_gear and new_gear > 0
	_prev_gear = new_gear
	if new_gear == F1Car.GEAR_NEUTRAL:
		return
	play_shot("shift_up" if up else "shift_down", Vector3(0, 0.4, -1.4), -6.0 if up else -9.0, randf_range(0.95, 1.05))
	if up and backfires and car.rpm > 9000.0 and randf() < 0.15:
		play_shot("backfire_1", Vector3(0, 0.4, -2.6), -9.0, randf_range(0.95, 1.05))
