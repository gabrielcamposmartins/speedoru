class_name NightLightBalance
extends RefCounted
## À noite a reta dos boxes junta postes, luzes das garagens, mastros da chegada e refletores das
## arquibancadas, e o brilho estoura. Aqui se estima a luz que chega ao chão em pontos perto da
## linha (até REACH m antes e depois, no meio da pista e dos dois lados) e em pontos espalhados
## pelo resto da pista; as luzes que iluminam um ponto da largada acima do LIMIT_PERCENTILE dos
## pontos iluminados do resto (com mais que LIT) são dosadas (fração no meta "dim", lida pelo
## RaceTrack.apply_mood) até ficar no nível das partes iluminadas do circuito (com uma folga,
## HEADROOM: a largada continua um pouco mais clara).

const REACH := 200.0
## Pontos da largada: a cada STEP m, no meio da pista e a LATERAL m de cada lado.
const STEP := 10.0
const LATERAL := 22.0
## Pontos de referência no resto da pista.
const REST_SAMPLES := 120
const LIMIT_PERCENTILE := 0.5
const LIT := 0.15
const HEADROOM := 1.25
## Luz que só contribui com menos disso num ponto não é dosada por ele.
const MIN_SHARE := 0.03
const MIN_DIM := 0.3

## Último resultado (para testes): {limit, start_before, start_after, rest, dimmed, ms}.
static var last := {}


static func apply(track: RaceTrack, lights: Array) -> void:
	last = {}
	var t0 := Time.get_ticks_usec()
	var p := track.path
	if p == null or lights.is_empty():
		return
	var start: Array[Vector3] = []
	var s := -REACH
	while s <= REACH:
		for lat in [-LATERAL, 0.0, LATERAL]:
			start.append(p.frame_at(s, lat, 0.0).origin)
		s += STEP
	var rest: Array[float] = []
	var span := p.length - 2.0 * REACH
	if span <= 0.0:
		return
	for k in REST_SAMPLES:
		var at := p.frame_at(REACH + span * (k + 0.5) / REST_SAMPLES, [-LATERAL, 0.0, LATERAL][k % 3], 0.0).origin
		var e := _total(at, lights)
		if e > LIT:
			rest.append(e)
	if rest.size() < 5:
		return
	rest.sort()
	var limit := rest[int((rest.size() - 1) * LIMIT_PERCENTILE)] * HEADROOM
	var dims := {}
	var before := 0.0
	for at in start:
		var parts := {}
		var total := 0.0
		for l: Light3D in lights:
			var e := _irradiance(l, at)
			if e > 0.0:
				parts[l] = e
				total += e
		before = maxf(before, total)
		if total <= limit:
			continue
		var f := maxf(limit / total, MIN_DIM)
		for l: Light3D in parts:
			if parts[l] >= total * MIN_SHARE:
				dims[l] = minf(dims.get(l, 1.0), f)
	for l: Light3D in dims:
		l.set_meta("dim", dims[l])
	var after := 0.0
	for at in start:
		after = maxf(after, _total(at, lights))
	last = {"limit": limit, "start_before": before, "start_after": after, "rest": rest, "dimmed": dims.size(),
		"ms": (Time.get_ticks_usec() - t0) / 1000.0}


static func _total(at: Vector3, lights: Array) -> float:
	var sum := 0.0
	for l: Light3D in lights:
		sum += _irradiance(l, at)
	return sum


## Luz de `l` chegando ao chão em `at` (mesma atenuação que o Godot usa, mais o cosseno com o chão),
## já com a dosagem atual.
static func _irradiance(l: Light3D, at: Vector3) -> float:
	var pos := l.global_position
	var to := pos - at
	var d := to.length()
	var reach := 0.0
	var decay := 1.0
	if l is SpotLight3D:
		reach = (l as SpotLight3D).spot_range
		decay = (l as SpotLight3D).spot_attenuation
	elif l is OmniLight3D:
		reach = (l as OmniLight3D).omni_range
		decay = (l as OmniLight3D).omni_attenuation
	else:
		return 0.0
	if d >= reach or d < 0.01 or to.y <= 0.0:
		return 0.0
	var dir := to / d
	if l is SpotLight3D:
		var axis := -l.global_transform.basis.z.normalized()
		var ang := rad_to_deg(acos(clampf(axis.dot(-dir), -1.0, 1.0)))
		var cone := (l as SpotLight3D).spot_angle
		if ang >= cone:
			return 0.0
	var nd := d / reach
	nd = nd * nd
	nd = nd * nd
	var window := maxf(1.0 - nd, 0.0)
	var energy := float(l.get_meta("base_energy", l.light_energy)) * float(l.get_meta("dim", 1.0))
	return energy * window * window * pow(maxf(d, 0.0001), -decay) * dir.y
