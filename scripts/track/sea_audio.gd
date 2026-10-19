class_name SeaAudio
extends Node
## Som ambiente da pista no fundo do mar (sons de tools/generate_sea_sounds.py, bus "Crowd", o
## volume de "ambiente" das configurações):
##  * debaixo d'água, o zumbido grave e as bolhas (sem posição), entrando e saindo com a mistura da
##    SeaAtmosphere (a câmera atravessando a linha d'água) e, de vez em quando, um canto de baleia;
##  * no Portão de Poseidon, o rugido de cada cachoeira, e o borbulhar de cada vulcão de bolhas
##    (AudioStreamPlayer3D), parados longe da câmera.
## Tudo discreto: é ambiente, não pode cobrir os carros.

const DIR := "res://assets/audio/ambient/"
const HUM_DB := -14.0
const BUBBLES_DB := -21.0
const WHALE_DB := -17.0
const FALL_DB := -3.0
const VENT_DB := -4.0
const SILENT_DB := -60.0
const FALL_UNIT := 30.0
const FALL_RANGE := 320.0

var atmosphere: SeaAtmosphere
## Pé de cada cachoeira e cratera de cada vulcão de bolhas (globais), definidos antes de entrar na cena.
var waterfalls: Array[Vector3] = []
var vents: Array[Vector3] = []
var _hum: AudioStreamPlayer
var _bubbles: AudioStreamPlayer
var _whale: AudioStreamPlayer
var _whales: Array[AudioStream] = []
var _falls: Array[AudioStreamPlayer3D] = []
var _next_whale := 0.0
var _check := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_hum = _player(load(DIR + "underwater_hum.wav"))
	_bubbles = _player(load(DIR + "bubbles.wav"))
	_whale = _player(null)
	_whale.volume_db = WHALE_DB
	for v in [1, 2]:
		_whales.append(load(DIR + "whale_call_%d.wav" % v))
	var fall := load(DIR + "waterfall.wav") as AudioStream
	var boil := load(DIR + "bubbles.wav") as AudioStream
	for spot: Array in [[waterfalls, fall, FALL_DB], [vents, boil, VENT_DB]]:
		for pos: Vector3 in spot[0]:
			var p := AudioStreamPlayer3D.new()
			p.stream = spot[1]
			p.bus = _bus()
			p.volume_db = spot[2]
			p.unit_size = FALL_UNIT
			p.max_distance = FALL_RANGE
			p.attenuation_filter_cutoff_hz = 9000.0
			add_child(p)
			p.global_position = pos
			_falls.append(p)
	_next_whale = _rng.randf_range(12.0, 25.0)


func _bus() -> StringName:
	return &"Crowd" if AudioServer.get_bus_index(&"Crowd") >= 0 else &"Master"


func _player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = _bus()
	p.volume_db = SILENT_DB
	add_child(p)
	return p


func _process(delta: float) -> void:
	var f := atmosphere.factor if atmosphere else 1.0
	_level(_hum, HUM_DB, f)
	_level(_bubbles, BUBBLES_DB, f)
	_next_whale -= delta
	if _next_whale <= 0.0:
		_next_whale = _rng.randf_range(28.0, 60.0)
		if f > 0.5 and not _whales.is_empty():
			_whale.stream = _whales[_rng.randi() % _whales.size()]
			_whale.pitch_scale = _rng.randf_range(0.85, 1.1)
			_whale.play()
	# Cachoeiras: tocam só perto da câmera (verificado a cada 0,5 s)
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		var cam := get_viewport().get_camera_3d()
		for p in _falls:
			var near := cam != null and cam.global_position.distance_to(p.global_position) < FALL_RANGE + 40.0
			if near and not p.playing:
				p.play(_rng.randf() * 6.0)
			elif not near and p.playing:
				p.stop()


## Volume pela mistura (0 = fora d'água): toca só quando dá para ouvir.
func _level(p: AudioStreamPlayer, db: float, f: float) -> void:
	if f < 0.01:
		if p.playing:
			p.stop()
		return
	p.volume_db = lerpf(SILENT_DB, db, sqrt(f))
	if not p.playing:
		p.play(_rng.randf() * 4.0)
