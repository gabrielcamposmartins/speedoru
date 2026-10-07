class_name CrowdAudio
extends Node3D
## Som da plateia de uma arquibancada (criado pelo Grandstands, um por arquibancada/barranco):
##
## * Murmúrio contínuo e baixo em alguns pontos ao longo dela (AudioStreamPlayer3D, bus "Crowd"),
##   começando em pontos diferentes do loop. Longe da câmera os players ficam pausados.
## * De vez em quando palmas, torcida ou buzinas de ar espontâneas, e com mais chance quando o
##   carro da câmera passa rápido perto; na largada e na chegada (call_group "crowd_audio") todas
##   reagem (gritos, buzinas e palmas).
## Tudo discreto: a plateia é ambiente, não pode cobrir os carros.

const DIR := "res://assets/audio/crowd/"
## Volumes medidos contra o motor na reta dos boxes: a plateia fica audível, uns 5 dB abaixo dos
## carros (antes ficava 13 dB abaixo e o motor a cobria).
const MURMUR_DB := -8.0
const CHEER_DB := -5.0
const APPLAUSE_DB := -7.0
const HORN_DB := -9.0
const UNIT_SIZE := 24.0
const MAX_DISTANCE := 260.0
## Distância da câmera (m) a partir da qual os players ficam pausados.
const ACTIVE_RANGE := 320.0

var _murmurs: Array[AudioStreamPlayer3D] = []
var _shots: Array[AudioStreamPlayer3D] = []
var _points: Array[Vector3] = []
var _check := 0.0
var _next_spontaneous := 0.0
var _pass_cooldown := 0.0
var _rng := RandomNumberGenerator.new()

static var _murmur_stream: AudioStream
static var _cheers: Array[AudioStream] = []
static var _applause: Array[AudioStream] = []
static var _horns: Array[AudioStream] = []


## Posições (globais) dos alto-falantes ao longo da arquibancada; definidas antes de entrar na cena.
var points: Array[Vector3] = []


func _ready() -> void:
	add_to_group("crowd_audio")
	_rng.randomize()
	_load_streams()
	_points = points
	for p in points:
		var m := _player(p, _murmur_stream, MURMUR_DB)
		_murmurs.append(m)
	for k in 3:
		_shots.append(_player(points[0] if not points.is_empty() else Vector3.ZERO, null, CHEER_DB))
	_next_spontaneous = _rng.randf_range(6.0, 16.0)


static func _load_streams() -> void:
	if _murmur_stream:
		return
	_murmur_stream = load(DIR + "crowd_murmur.wav")
	for v in [1, 2]:
		_cheers.append(load(DIR + "crowd_cheer_%d.wav" % v))
		_applause.append(load(DIR + "applause_%d.wav" % v))
		_horns.append(load(DIR + "air_horn_%d.wav" % v))


func _player(pos: Vector3, stream: AudioStream, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = &"Crowd" if AudioServer.get_bus_index(&"Crowd") >= 0 else &"Master"
	p.volume_db = db
	p.unit_size = UNIT_SIZE
	p.max_distance = MAX_DISTANCE
	p.attenuation_filter_cutoff_hz = 6000.0
	add_child(p)
	p.global_position = pos
	return p


func _process(delta: float) -> void:
	_check -= delta
	_pass_cooldown -= delta
	if _check > 0.0:
		return
	_check = 0.5
	var cam := get_viewport().get_camera_3d()
	var near := INF
	var near_point := Vector3.ZERO
	if cam:
		for p in _points:
			var d := cam.global_position.distance_to(p)
			if d < near:
				near = d
				near_point = p
	var active := near < ACTIVE_RANGE
	for m in _murmurs:
		if active and not m.playing:
			m.play(_rng.randf() * 9.0)
		elif not active and m.playing:
			m.stop()
	if not active:
		return
	# Palmas/torcida espontâneas de vez em quando
	_next_spontaneous -= 0.5
	if _next_spontaneous <= 0.0:
		_next_spontaneous = _rng.randf_range(8.0, 20.0)
		var roll := _rng.randf()
		if roll < 0.35:
			_play_shot(_applause, APPLAUSE_DB - 4.0, near_point)
		elif roll < 0.7:
			_play_shot(_horns, HORN_DB - 3.0, _points[_rng.randi_range(0, _points.size() - 1)])
		else:
			_play_shot(_cheers, CHEER_DB - 5.0, near_point)
	# Carro da câmera passando rápido perto: a arquibancada vibra
	var car := (cam as RaceCamera).target if cam is RaceCamera else null
	if car and _pass_cooldown <= 0.0 and car.speed_kmh > 120.0:
		for p in _points:
			if car.global_position.distance_to(p) < 45.0:
				_pass_cooldown = _rng.randf_range(10.0, 22.0)
				if _rng.randf() < 0.6:
					_play_shot(_cheers, CHEER_DB - 2.0, p)
				if _rng.randf() < 0.5:
					_play_shot(_horns, HORN_DB, p)
				break


## Largada ("start") e chegada ("finish"): todas as arquibancadas reagem.
func on_race_event(kind: String) -> void:
	if _points.is_empty():
		return
	var p: Vector3 = _points[_rng.randi_range(0, _points.size() - 1)]
	match kind:
		"start":
			_play_shot(_cheers, CHEER_DB, p)
			_play_shot(_horns, HORN_DB, _points[_rng.randi_range(0, _points.size() - 1)])
		"finish":
			_play_shot(_applause, APPLAUSE_DB + 1.0, p)
			_play_shot(_cheers, CHEER_DB - 1.0, p)
			_play_shot(_horns, HORN_DB + 1.0, _points[_rng.randi_range(0, _points.size() - 1)])


func _play_shot(pool: Array[AudioStream], db: float, at: Vector3) -> void:
	var player: AudioStreamPlayer3D = null
	for s in _shots:
		if not s.playing:
			player = s
			break
	if player == null:
		return
	player.stream = pool[_rng.randi_range(0, pool.size() - 1)]
	player.global_position = at
	player.volume_db = db + _rng.randf_range(-2.0, 1.0)
	player.pitch_scale = _rng.randf_range(0.94, 1.06)
	player.play()
