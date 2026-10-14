class_name CarSignalSounds
extends RefCounted
## Sons do pisca dos retrovisores (pedir passagem), gerados por código e guardados depois do primeiro
## uso:
## * relay(on): o relé do pisca âmbar — um "tic" seco ao acender e um "tac" mais grave ao apagar;
## * siren(): a sirene da luz Sirene, em loop — "yelp" de viatura, subindo de ~650 a ~1.450 Hz
##   quase três vezes por segundo, com harmônicos de corneta.

const RATE := 44100
## Varreduras por segundo e faixa de frequência da sirene.
const SIREN_SWEEPS := 2.8
const SIREN_LOW := 650.0
const SIREN_HIGH := 1450.0

static var _cache := {}


static func relay(on: bool) -> AudioStreamWAV:
	var key := "relay_on" if on else "relay_off"
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 7 if on else 8
		var body := 2600.0 if on else 1500.0
		var lp := [0.0]
		_cache[key] = UiSounds._synth(0.03, func(t: float) -> float:
			lp[0] += 0.35 * (rng.randf_range(-1.0, 1.0) - lp[0])
			var attack := minf(t / 0.0006, 1.0)
			return (lp[0] * 2.2 * exp(-t * 700.0) + sin(TAU * body * t) * exp(-t * 450.0) * 0.5) * attack)
	return _cache[key]


## Loop da sirene: começa e termina num cruzamento do zero subindo (sem estalo ao repetir).
static func siren() -> AudioStreamWAV:
	if _cache.has("siren"):
		return _cache["siren"]
	var period := 1.0 / SIREN_SWEEPS
	var cycles := 3
	var n := int(RATE * period * cycles)
	var samples := PackedFloat32Array()
	samples.resize(n + RATE / 50)
	var phase := 0.0
	var end := samples.size()
	for i in samples.size():
		var t := float(i) / RATE
		samples[i] = 0.55 * sin(phase) + 0.25 * sin(2.0 * phase) + 0.12 * sin(3.0 * phase) + 0.06 * sin(5.0 * phase)
		# Sobe devagar e cai rápido (yelp): dente de serra suavizado
		var u := fmod(t / period, 1.0)
		var shape := u / 0.85 if u < 0.85 else 1.0 - (u - 0.85) / 0.15
		var f := lerpf(SIREN_LOW, SIREN_HIGH, smoothstep(0.0, 1.0, shape))
		var next := phase + TAU * f / RATE
		# Depois das varreduras inteiras, corta quando a fase completa uma volta: a amostra seguinte
		# seria a fase 0 de novo, igual ao começo do loop
		if i >= n and floorf(next / TAU) > floorf(phase / TAU):
			end = i + 1
			break
		phase = next
	var data := PackedByteArray()
	data.resize(end * 2)
	for i in end:
		data.encode_s16(i * 2, int(clampf(samples[i] * 0.8, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = end
	_cache["siren"] = wav
	return wav
