class_name UiSounds
extends RefCounted
## Sons curtos da interface, gerados por código (como os bipes da largada) e guardados depois do
## primeiro uso. Tocam no bus geral, baixinhos.

static var _cache := {}


## Clique do carrossel da roleta: a lingueta de plástico/madeira de uma roda da fortuna batendo
## num pino — um "toc" macio, sem metal nem chiado (ruído abafado por um passa-baixa de dois polos,
## ataque de ~1 ms e um corpo grave de 700 e 330 Hz).
static func tick() -> AudioStreamWAV:
	if not _cache.has("tick"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		var lp := [0.0, 0.0]
		_cache["tick"] = _synth(0.032, func(t: float) -> float:
			lp[0] += 0.11 * (rng.randf_range(-1.0, 1.0) - lp[0])
			lp[1] += 0.11 * (lp[0] - lp[1])
			var attack := minf(t / 0.0012, 1.0)
			var v: float = lp[1] * 4.5 * exp(-t * 500.0) + sin(TAU * 700.0 * t) * exp(-t * 320.0) * 0.35 \
				+ sin(TAU * 330.0 * t) * exp(-t * 220.0) * 0.25
			return v * attack * 2.0)
	return _cache["tick"]


## Prêmio escolhido: arpejo de sino (tríade maior subindo; uma nota a mais por degrau de raridade
## a partir do raro).
static func prize(rarity: int) -> AudioStreamWAV:
	var key := "prize%d" % rarity
	if not _cache.has(key):
		var notes := [523.25, 659.25, 783.99]
		if rarity >= 2:
			notes.append(1046.5)
		if rarity >= 4:
			notes.append(1318.5)
		var step := 0.075
		var length := step * (notes.size() - 1) + 0.9
		_cache[key] = _synth(length, func(t: float) -> float:
			var v := 0.0
			for i in notes.size():
				var nt := t - step * i
				if nt < 0.0:
					continue
				var f: float = notes[i]
				var env := minf(nt / 0.004, 1.0) * exp(-nt * 5.5)
				# Sino: fundamental, oitava e um parcial inarmônico que some rápido
				v += (sin(TAU * f * nt) + 0.35 * sin(TAU * f * 2.0 * nt) + 0.2 * sin(TAU * f * 2.76 * nt) * exp(-nt * 12.0)) * env
			return v * 0.2)
	return _cache[key]


## Prêmio novo (algo que o jogador ainda não tinha): um "brilho" macio por cima do arpejo — acorde
## de dó com sétima e nona (G-C-E-B-D) entrando nota a nota com ataque lento e um leve vibrato, e
## três pingos agudos bem baixinhos, como purpurina. Sem nada estalado ou agudo demais.
static func discovery() -> AudioStreamWAV:
	if not _cache.has("discovery"):
		var notes := [392.0, 523.25, 659.25, 987.77, 1174.66]
		var sparkles := [[0.42, 2093.0], [0.6, 2637.0], [0.8, 3136.0]]
		_cache["discovery"] = _synth(2.0, func(t: float) -> float:
			var v := 0.0
			for i in notes.size():
				var nt := t - 0.07 * i
				if nt < 0.0:
					continue
				var f: float = notes[i] * (1.0 + 0.003 * sin(TAU * 5.0 * nt))
				var env := minf(nt / 0.045, 1.0) * exp(-nt * 1.9)
				v += (sin(TAU * f * nt) + 0.12 * sin(TAU * f * 2.0 * nt)) * env
			for s: Array in sparkles:
				var st: float = t - float(s[0])
				if st >= 0.0:
					v += sin(TAU * float(s[1]) * st) * minf(st / 0.01, 1.0) * exp(-st * 9.0) * 0.35
			return v * 0.11)
	return _cache["discovery"]


## Toca `stream` num player temporário filho de `parent` (some quando acaba).
static func play(parent: Node, stream: AudioStream, db := -14.0, pitch := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.bus = &"Master"
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


static func _synth(seconds: float, wave: Callable) -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		# Sem estalo no fim
		var tail := clampf((seconds - t) / 0.01, 0.0, 1.0)
		data.encode_s16(i * 2, int(clampf(float(wave.call(t)) * tail, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
