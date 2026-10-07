class_name StartLights
extends Node3D
## Luzes de largada (5 colunas de 2 lâmpadas vermelhas). Montado pelo TrackProps no pórtico.
## run_sequence(): acende uma coluna por segundo e apaga todas após um intervalo aleatório.
## Som: um bipe grave a cada coluna acesa e um tom agudo e mais longo quando as luzes apagam
## (gerados em código, sem arquivos de áudio).

signal lights_out

var _lamps: Array[MeshInstance3D] = []
var _on: StandardMaterial3D
var _off: StandardMaterial3D
var _running := false
var _beep: AudioStreamPlayer
var _go: AudioStreamPlayer


func setup(pod_spacing := 0.9) -> void:
	_beep = _player(_tone(620.0, 0.22), -6.0)
	_go = _player(_tone(1240.0, 0.75), -4.0)
	_on = StandardMaterial3D.new()
	_on.albedo_color = Color(1.0, 0.1, 0.08)
	_on.emission_enabled = true
	_on.emission = Color(1.0, 0.08, 0.05)
	_on.emission_energy_multiplier = 6.0
	_on.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_off = StandardMaterial3D.new()
	_off.albedo_color = Color(0.18, 0.04, 0.05)
	_off.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var lamp := SphereMesh.new()
	lamp.radius = 0.13
	lamp.height = 0.26
	lamp.radial_segments = 12
	lamp.rings = 6
	var pod := BoxMesh.new()
	pod.size = Vector3(0.55, 1.5, 0.35)
	var pod_mat := StandardMaterial3D.new()
	pod_mat.albedo_color = Color(0.08, 0.08, 0.1)
	pod_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	for c in 5:
		var x := (c - 2) * pod_spacing
		var body := MeshInstance3D.new()
		body.mesh = pod
		body.material_override = pod_mat
		body.position = Vector3(x, 0, 0)
		add_child(body)
		for r in 2:
			# Lâmpadas nas duas faces (quem larga olha para -Z do pórtico)
			for face in [-1.0, 1.0]:
				var mi := MeshInstance3D.new()
				mi.mesh = lamp
				mi.material_override = _off
				mi.position = Vector3(x, 0.35 - r * 0.38, 0.17 * face)
				mi.scale = Vector3(1, 1, 0.5)
				mi.set_meta("column", c)
				add_child(mi)
				_lamps.append(mi)


## Acende as `count` primeiras colunas (0 = todas apagadas).
func set_lit(count: int) -> void:
	for lamp in _lamps:
		lamp.material_override = _on if int(lamp.get_meta("column")) < count else _off


## [param hold_time]: espera depois da 5ª luz (sorteada se < 0; na rede o servidor manda a mesma
## para todos).
func run_sequence(hold_time := -1.0) -> void:
	if _running:
		return
	_running = true
	for c in range(1, 6):
		set_lit(c)
		_beep.play()
		# Timers que param na pausa (o padrão do create_timer corre mesmo com o jogo pausado)
		await get_tree().create_timer(1.0, false).timeout
	await get_tree().create_timer(hold_time if hold_time >= 0.0 else randf_range(0.2, 3.0), false).timeout
	set_lit(0)
	_go.play()
	_running = false
	lights_out.emit()


func _player(stream: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.bus = &"Car" if AudioServer.get_bus_index(&"Car") >= 0 else &"Master"
	add_child(p)
	return p


## Bipe eletrônico: onda quase quadrada (fundamental + 3º e 5º harmônicos) com ataque e queda curtos.
static func _tone(freq: float, seconds: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := minf(t / 0.008, 1.0) * clampf((seconds - t) / 0.05, 0.0, 1.0)
		var w := TAU * freq * t
		var v := (sin(w) + sin(3.0 * w) / 3.0 + sin(5.0 * w) / 5.0) * 0.55 * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
