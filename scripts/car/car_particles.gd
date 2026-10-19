class_name CarParticles
extends Node3D
## Rastro de partículas equipável (itens "trail" das roletas, CarConfig.trail): o carro solta
## bolhas, estrelinhas, fogo no chão, raios, pétalas, neve, brasas, moedas, fumaça ou um arco-íris.
## Além do rastro, todo carro solta faíscas do assoalho numa frenagem forte: começando a frear a
## 250 km/h ou mais e segurando o freio por mais de BRAKE_SPARK_HOLD s (não é item da loja).
## Filho do Effects do carro (o servidor nem cria: tira o Effects inteiro). As partículas nascem
## no mundo (ficam para trás formando o rastro), exceto os raios que estalam na carroceria.
## Parado, só na garagem (vitrine) o efeito aparece, fraco; cheio a partir de ~140 km/h. A velocidade
## vem do quanto o carro andou no quadro, então vale também para os carros dos outros jogadores.
## As formas são desenhadas no shader (shaders/car/car_particle.gdshader), sem textura.

## id do efeito -> nome (o mesmo dos itens da loja).
const EFFECTS := {
	"lightning": "Raios",
	"sakura": "Pétalas de sakura",
	"stars": "Estrelinhas",
	"bubbles": "Bolhas de sabão",
	"snow": "Flocos de neve",
	"fire": "Fogo no chão",
	"embers": "Brasas",
	"coins": "Chuva de moedas",
	"smoke": "Fumaça colorida",
	"rainbow": "Arco-íris",
}

enum Shape { BUBBLE, STAR, FLAME, BOLT, PETAL, SNOW, COIN, SPARK, SMOKE, EMBER }
enum Orient { BILLBOARD, VELOCITY, UPRIGHT }

## Vitrine: o carro da garagem do menu tem a meta "showcase" (MainMenu). Só ali, parado, o efeito
## fica fraco, de amostra; na pista (e em qualquer outro lugar) só sai com o carro andando.
## Velocidade (m/s) em que o efeito chega ao máximo.
const FULL_SPEED := 40.0
## Escala do tamanho de todas as partículas (e da faixa de fogo).
const SIZE := 0.6
## Faíscas de frenagem: velocidade mínima ao começar a frear (km/h), freio mínimo, quanto tempo
## freando até soltar faíscas (s) e até que velocidade continuam (km/h).
const BRAKE_SPARK_KMH := 250.0
const BRAKE_SPARK_INPUT := 0.3
const BRAKE_SPARK_HOLD := 1.0
const BRAKE_SPARK_MIN_KMH := 120.0
const BRAKE_SPARK_ARM := 0.25

var car: F1Car
var effect := ""
var _key := ""
var _emitters: Array[GPUParticles3D] = []
var _ribbons: Array[TrailRibbon] = []
var _wheels: Array[VehicleWheel3D] = []
var _light: OmniLight3D
var _light_energy := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _velocity := Vector3.ZERO
var _poll := 0.0
var _time := 0.0
var _brake_sparks: GPUParticles3D
## Freando há quanto tempo (s) e se a frenagem começou rápida o bastante para soltar faíscas.
var _brake_time := 0.0
var _brake_armed := false

static var _shader: Shader
static var _fire_shader: Shader
static var _rainbow_shader: Shader


func _enter_tree() -> void:
	RenderingServer.frame_pre_draw.connect(_push_velocity)


func _exit_tree() -> void:
	RenderingServer.frame_pre_draw.disconnect(_push_velocity)


## Velocidade herdada (inherit_velocity_ratio) dos emissores no mundo: o GPUParticles3D grava a
## dele a cada quadro (zero aqui), então a do carro vai logo antes de desenhar. Só vale para as
## partículas que nascem: emissor desligado não precisa (14 carros, todo quadro).
func _push_velocity() -> void:
	for e in _emitters:
		if is_instance_valid(e) and e.emitting and not e.local_coords:
			RenderingServer.particles_set_emitter_velocity(e.get_base(), _velocity)
	if is_instance_valid(_brake_sparks) and _brake_sparks.emitting:
		RenderingServer.particles_set_emitter_velocity(_brake_sparks.get_base(), _velocity)


func _ready() -> void:
	if car == null:
		car = get_parent().get_parent() as F1Car if get_parent() else null
	if car:
		_last_pos = car.global_position
		if not car.get_meta("showcase", false):
			_build_brake_sparks()
	_sync()


func _process(delta: float) -> void:
	if car == null:
		return
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.25
		_sync()
	if _brake_sparks:
		var state := brake_spark_state(_brake_time, _brake_armed, car.speed_kmh, car.brake_input, delta)
		_brake_time = state[0]
		_brake_armed = state[1]
		var sparks: bool = state[2]
		if _brake_sparks.emitting != sparks:
			_brake_sparks.emitting = sparks
	if effect == "" and _brake_sparks == null:
		return
	_time += delta
	var pos := car.global_position
	var vel := (pos - _last_pos) / maxf(delta, 1e-4)
	_last_pos = pos
	if vel.length() > 200.0:
		vel = _velocity  # teleporte (largada, boxes, replay)
	_velocity = _velocity.lerp(vel, clampf(delta * 8.0, 0.0, 1.0))
	_speed = _velocity.length()
	if effect == "":
		return
	var f := clampf((_speed - 1.0) / (FULL_SPEED - 1.0), 0.0, 1.0)
	var showcase: bool = car.get_meta("showcase", false)
	for e in _emitters:
		var idle: float = e.get_meta("idle", 0.3) if showcase else 0.0
		var ratio := lerpf(idle, 1.0, f)
		if absf(e.amount_ratio - ratio) > 0.002:
			e.amount_ratio = ratio
		var on := ratio > 0.005
		if e.emitting != on:
			e.emitting = on
		var drag: float = e.get_meta("drag", 0.0)
		if drag > 0.0:
			var damp: float = float(e.get_meta("damp", 0.0)) + drag * f
			var pm := e.process_material as ParticleProcessMaterial
			if absf(pm.damping_min - damp) > 0.2:
				pm.damping_min = damp
				pm.damping_max = damp * 1.6
		# A turbulência puxa a velocidade para a do ruído (apagaria a herdada): só com o carro devagar
		if e.has_meta("turb"):
			var tb: Vector2 = e.get_meta("turb")
			var k := (1.0 - f) * (1.0 - f)
			var pt := e.process_material as ParticleProcessMaterial
			if absf(pt.turbulence_influence_max - tb.y * k) > 0.004:
				pt.turbulence_influence_min = tb.x * k
				pt.turbulence_influence_max = tb.y * k
	_update_ribbons()
	_update_light(f, 1.0 if showcase else clampf(f * 6.0, 0.0, 1.0), delta)


## Faíscas de frenagem: [tempo freando, armado, soltando faíscas] depois de [param delta] s.
## Arma se estiver a BRAKE_SPARK_KMH ou mais logo no começo da frenagem (BRAKE_SPARK_ARM s);
## solta faíscas depois de BRAKE_SPARK_HOLD s com o freio apertado e para ao soltar o freio ou
## abaixo de BRAKE_SPARK_MIN_KMH.
static func brake_spark_state(time: float, armed: bool, kmh: float, brake: float, delta: float) -> Array:
	if brake < BRAKE_SPARK_INPUT:
		return [0.0, false, false]
	if time < BRAKE_SPARK_ARM and kmh >= BRAKE_SPARK_KMH:
		armed = true
	time += delta
	return [time, armed, armed and time > BRAKE_SPARK_HOLD and kmh >= BRAKE_SPARK_MIN_KMH]


## Confere o efeito do carro (e as cores, que a fumaça usa) e remonta se mudou.
func _sync() -> void:
	var want := car.config.trail if car and car.config and EFFECTS.has(car.config.trail) else ""
	var key := want
	if want == "smoke":
		key += car.config.primary_color.to_html() + car.config.secondary_color.to_html() + car.config.accent_color.to_html()
	if key == _key:
		return
	_key = key
	_build(want)


func _clear() -> void:
	for c in get_children():
		if c == _brake_sparks:
			continue
		remove_child(c)
		c.queue_free()
	_emitters.clear()
	_ribbons.clear()
	_light = null


func _build(id: String) -> void:
	_clear()
	effect = id
	if id == "" or car == null:
		return
	_wheels.clear()
	for w in car.get_wheels():
		if w.position.z < 0.0:
			_wheels.append(w)
	var rear_z := _wheels[0].position.z if not _wheels.is_empty() else -1.6
	match id:
		"bubbles":
			var e := _emitter(Shape.BUBBLE, Orient.BILLBOARD, Vector2(0.62, 0.62), 220, 2.6, 0.35)
			e.position = Vector3(0, 0.8, -2.5)
			var pm := _box(e, Vector3(0.8, 0.3, 0.6), Vector3(0, 0.5, -1), 45.0, 1.0, 3.5, Vector3(0, 0.45, 0))
			_motion(e, 0.85, 1.2, 14.0)
			_turbulence(e, 1.2, 3.0, 0.06, 0.12)
			_scale(pm, 0.45, 1.25, [Vector2(0, 0.3), Vector2(0.12, 1.0), Vector2(1, 1.0)])
			pm.color_initial_ramp = _palette([Color("ffffff"), Color("e3f6ff"), Color("fff0fb"), Color("f0fff4")])
			pm.color_ramp = _alpha_ramp([[0.0, 0.0], [0.08, 1.0], [1.0, 1.0]])
		"stars":
			var e := _emitter(Shape.STAR, Orient.BILLBOARD, Vector2(0.44, 0.44), 180, 1.4, 0.45)
			e.position = Vector3(0, 0.85, -2.3)
			var pm := _box(e, Vector3(1.0, 0.4, 0.7), Vector3(0, 1, -0.3), 180.0, 0.6, 2.4, Vector3(0, -0.35, 0))
			_motion(e, 0.85, 1.6, 16.0)
			_spin(pm, 120.0)
			_scale(pm, 0.5, 1.3, [Vector2(0, 0.0), Vector2(0.12, 1.0), Vector2(0.7, 0.85), Vector2(1, 0.0)])
			pm.color_initial_ramp = _palette([Color("ffd84d"), Color("ff6fd8"), Color("5ff3ff"), Color("ffffff"), Color("b48cff"), Color("7dff9a")])
			pm.color_ramp = _alpha_ramp([[0.0, 1.0], [0.7, 1.0], [1.0, 0.0]])
		"fire":
			# Por roda traseira: uma faixa de fogo contínua (fita virada para a câmera, presa ao
			# chão: de trás deita, de lado vira parede), o brilho no asfalto e chamas curtas por cima
			for w in _wheels:
				var e := _emitter(Shape.FLAME, Orient.UPRIGHT, Vector2(0.5, 0.8), 320, 0.45, 0.35)
				# Base da chama rente ao chão (metade da altura do quad)
				e.position = Vector3(w.position.x, 0.8 * SIZE * 0.45, rear_z - 0.2)
				var pm := _box(e, Vector3(0.1, 0.02, 0.5), Vector3.UP, 8.0, 0.2, 0.8, Vector3(0, 0.6, 0))
				_motion(e, 0.0, 0.5, 0.0)
				_scale(pm, 0.6, 1.2, [Vector2(0, 0.5), Vector2(0.25, 1.0), Vector2(1, 0.3)])
				pm.color_ramp = _ramp([[0.0, Color(1, 1, 1, 0)], [0.1, Color(1, 1, 1, 1)], [0.6, Color(1, 0.85, 0.8, 0.85)], [1.0, Color(1, 0.6, 0.5, 0)]])
				var band_width := 0.7 * SIZE
				_fire_ribbon("FireTrail", TrailRibbon.Mode.BILLBOARD, band_width, 0.6, w, band_width * 0.5, true)
				_fire_ribbon("FireGlow", TrailRibbon.Mode.GROUND, 0.9 * SIZE, 1.0, w, 0.03, false)
			var embers := _emitter(Shape.EMBER, Orient.BILLBOARD, Vector2(0.16, 0.16), 70, 1.4, 0.35)
			embers.position = Vector3(0, 0.3, rear_z - 0.4)
			var pe := _box(embers, Vector3(0.9, 0.1, 0.5), Vector3.UP, 30.0, 1.0, 3.0, Vector3(0, 1.0, 0))
			_motion(embers, 0.5, 0.0, 8.0)
			_turbulence(embers, 2.0, 1.5, 0.1, 0.25)
			pe.color_initial_ramp = _palette([Color("ffb347"), Color("ff7a1a"), Color("ffd27a")])
			pe.color_ramp = _alpha_ramp([[0.0, 1.0], [0.6, 0.9], [1.0, 0.0]])
			_add_light(Color(1.0, 0.45, 0.1), Vector3(0, 0.5, rear_z - 0.8), 7.0)
		"lightning":
			# Arcos estalando na carroceria e raios caindo no chão: presos ao carro
			var arcs := _emitter(Shape.BOLT, Orient.BILLBOARD, Vector2(0.45, 1.35), 30, 0.16, 0.55, true)
			arcs.position = Vector3(0, 0.55, -0.3)
			var pa := _box(arcs, Vector3(0.9, 0.3, 2.2), Vector3.UP, 0.0, 0.0, 0.0, Vector3.ZERO)
			_spin(pa, 0.0)
			pa.scale_min = 0.6
			pa.scale_max = 1.3
			pa.color_initial_ramp = _palette([Color("9fe6ff"), Color("d0b3ff"), Color("ffffff")])
			var strikes := _emitter(Shape.BOLT, Orient.UPRIGHT, Vector2(0.8, 2.0), 14, 0.2, 0.12, true)
			# O raio vai do chão até ~2 × SIZE de altura
			strikes.position = Vector3(0, 1.0 * SIZE, -1.6)
			var ps := _box(strikes, Vector3(1.1, 0.1, 1.4), Vector3.UP, 0.0, 0.0, 0.0, Vector3.ZERO)
			ps.color_initial_ramp = _palette([Color("8fd8ff"), Color("b48cff")])
			var sparks := _emitter(Shape.SPARK, Orient.VELOCITY, Vector2(0.05, 0.45), 90, 0.4, 0.2)
			sparks.position = Vector3(0, 0.1, -1.6)
			var pk := _box(sparks, Vector3(0.9, 0.05, 1.0), Vector3.UP, 70.0, 2.0, 5.0, Vector3(0, -9.8, 0))
			_motion(sparks, 0.8, 0.0, 10.0)
			pk.particle_flag_align_y = true
			pk.color_initial_ramp = _palette([Color("9fe6ff"), Color("ffffff")])
			pk.color_ramp = _alpha_ramp([[0.0, 1.0], [1.0, 0.0]])
			_add_light(Color(0.55, 0.75, 1.0), Vector3(0, 0.9, -0.6), 8.0)
		"sakura":
			var e := _emitter(Shape.PETAL, Orient.BILLBOARD, Vector2(0.32, 0.32), 200, 2.8, 0.35)
			e.position = Vector3(0, 0.9, -2.2)
			var pm := _box(e, Vector3(0.9, 0.35, 0.8), Vector3(0, 0.6, -1), 60.0, 0.8, 2.6, Vector3(0, -0.6, 0))
			_motion(e, 0.85, 1.0, 14.0)
			_spin(pm, 150.0)
			_turbulence(e, 1.5, 2.5, 0.05, 0.1)
			_scale(pm, 0.7, 1.3, [])
			pm.color_initial_ramp = _palette([Color("ffb7d5"), Color("ff8fc7"), Color("ffd6e8"), Color("ff6fae")])
			pm.color_ramp = _alpha_ramp([[0.0, 0.0], [0.05, 1.0], [0.8, 1.0], [1.0, 0.0]])
		"snow":
			var e := _emitter(Shape.SNOW, Orient.BILLBOARD, Vector2(0.38, 0.38), 180, 2.2, 0.4)
			e.position = Vector3(0, 0.95, -2.0)
			var pm := _box(e, Vector3(1.0, 0.45, 0.9), Vector3.UP, 180.0, 0.3, 1.5, Vector3(0, -0.45, 0))
			_motion(e, 0.85, 1.2, 14.0)
			_spin(pm, 60.0)
			_turbulence(e, 1.0, 2.0, 0.04, 0.08)
			_scale(pm, 0.5, 1.2, [Vector2(0, 0.2), Vector2(0.1, 1.0), Vector2(1, 0.8)])
			pm.color_initial_ramp = _palette([Color("ffffff"), Color("e0f7ff"), Color("9ff0ff"), Color("c7d8ff")])
			pm.color_ramp = _alpha_ramp([[0.0, 1.0], [0.75, 1.0], [1.0, 0.0]])
		"embers":
			var e := _emitter(Shape.EMBER, Orient.BILLBOARD, Vector2(0.22, 0.22), 240, 1.8, 0.45)
			e.position = Vector3(0, 0.4, -2.4)
			var pm := _box(e, Vector3(0.75, 0.25, 0.5), Vector3(0, 1, -0.5), 50.0, 1.5, 4.5, Vector3(0, 1.3, 0))
			_motion(e, 0.8, 0.6, 12.0)
			_turbulence(e, 2.5, 1.5, 0.15, 0.3)
			_scale(pm, 0.5, 1.4, [])
			pm.color_ramp = _ramp([[0.0, Color("ffd27a")], [0.35, Color("ff7a1a")], [0.8, Color(0.78, 0.12, 0.04, 0.8)], [1.0, Color(0.5, 0.05, 0.02, 0.0)]])
			var smoke := _emitter(Shape.SMOKE, Orient.BILLBOARD, Vector2(0.9, 0.9), 30, 1.8, 0.35)
			smoke.position = e.position
			var ps := _box(smoke, Vector3(0.6, 0.15, 0.4), Vector3.UP, 25.0, 0.6, 1.6, Vector3(0, 0.8, 0))
			_motion(smoke, 0.75, 0.0, 12.0)
			_spin(ps, 40.0)
			_scale(ps, 0.7, 1.0, [Vector2(0, 0.4), Vector2(1, 2.2)])
			ps.color_ramp = _ramp([[0.0, Color(0.12, 0.1, 0.1, 0.0)], [0.15, Color(0.12, 0.1, 0.1, 0.55)], [1.0, Color(0.2, 0.18, 0.18, 0.0)]])
		"coins":
			var e := _emitter(Shape.COIN, Orient.BILLBOARD, Vector2(0.4, 0.4), 80, 1.2, 0.3)
			e.position = Vector3(0, 0.9, -2.1)
			var pm := _box(e, Vector3(0.5, 0.15, 0.3), Vector3(0, 1, -0.55), 35.0, 3.0, 6.5, Vector3(0, -9.8, 0))
			_motion(e, 0.85, 0.0, 8.0)
			pm.angle_min = -20.0
			pm.angle_max = 20.0
			_scale(pm, 0.8, 1.1, [])
			pm.color_initial_ramp = _palette([Color("ffc93c"), Color("ffd966"), Color("f2b632")])
			pm.color_ramp = _alpha_ramp([[0.0, 1.0], [0.85, 1.0], [1.0, 0.0]])
			var glints := _emitter(Shape.STAR, Orient.BILLBOARD, Vector2(0.22, 0.22), 60, 0.8, 0.3)
			glints.position = e.position
			var pg := _box(glints, Vector3(0.6, 0.3, 0.5), Vector3(0, 1, -0.5), 60.0, 1.0, 3.0, Vector3(0, -2.0, 0))
			_motion(glints, 0.85, 0.0, 12.0)
			_scale(pg, 0.6, 1.2, [Vector2(0, 0.0), Vector2(0.2, 1.0), Vector2(1, 0.0)])
			pg.color_initial_ramp = _palette([Color("fff3b0"), Color("ffd84d")])
		"smoke":
			var e := _emitter(Shape.SMOKE, Orient.BILLBOARD, Vector2(1.0, 1.0), 90, 2.0, 0.3)
			e.position = Vector3(0, 0.35, -2.5)
			var pm := _box(e, Vector3(0.55, 0.12, 0.25), Vector3(0, 0.35, -1), 25.0, 1.0, 3.0, Vector3(0, 0.3, 0))
			_motion(e, 0.85, 1.0, 9.0)
			_spin(pm, 40.0)
			_scale(pm, 0.6, 1.0, [Vector2(0, 0.35), Vector2(1, 2.6)])
			var cfg := car.config
			pm.color_initial_ramp = _palette([cfg.primary_color, cfg.secondary_color, cfg.accent_color])
			pm.color_ramp = _alpha_ramp([[0.0, 0.0], [0.1, 1.0], [1.0, 0.0]])
		"rainbow":
			# Faixa de arco-íris saindo da traseira (fita virada para a câmera) e estrelinhas
			var ribbon := TrailRibbon.new()
			ribbon.name = "RainbowTrail"
			ribbon.mode = TrailRibbon.Mode.BILLBOARD
			ribbon.width = 1.5 * SIZE
			ribbon.lifetime = 0.9
			ribbon.max_points = 240
			ribbon.min_spacing = 0.3
			ribbon.fade_start = 0.0
			ribbon.taper = false
			ribbon.color = Color.WHITE
			if _rainbow_shader == null:
				_rainbow_shader = load("res://shaders/car/car_rainbow_trail.gdshader")
			var mat := ShaderMaterial.new()
			mat.shader = _rainbow_shader
			ribbon.material_override = mat
			add_child(ribbon)
			ribbon.global_transform = Transform3D.IDENTITY
			ribbon.set_meta("anchor", Vector3(0, 0.55, rear_z - 0.5))
			_ribbons.append(ribbon)
			var glints := _emitter(Shape.STAR, Orient.BILLBOARD, Vector2(0.3, 0.3), 90, 1.0, 0.4)
			glints.position = Vector3(0, 0.6, rear_z - 0.8)
			var pg := _box(glints, Vector3(0.6, 0.35, 0.4), Vector3(0, 0.3, -1), 70.0, 0.5, 1.8, Vector3.ZERO)
			_motion(glints, 0.85, 1.0, 12.0)
			_spin(pg, 90.0)
			_scale(pg, 0.5, 1.2, [Vector2(0, 0.0), Vector2(0.2, 1.0), Vector2(1, 0.0)])
			pg.color_initial_ramp = _palette([Color("ffffff"), Color("fff3b0"), Color("bff6ff"), Color("ffd1f5")])


## Rastro visto da câmera de perseguição: a partícula herda parte da velocidade do carro e um
## arrasto que cresce com a velocidade a faz ficar para trás aos poucos (parado, só [param damp]).
func _motion(e: GPUParticles3D, inherit: float, damp: float, drag: float) -> void:
	var pm := e.process_material as ParticleProcessMaterial
	pm.inherit_velocity_ratio = inherit
	pm.damping_min = damp
	pm.damping_max = damp * 1.6
	e.set_meta("damp", damp)
	e.set_meta("drag", drag)


## Faíscas de frenagem (todo carro): saem do assoalho raspando no chão, fora da lista do rastro.
func _build_brake_sparks() -> void:
	var e := _emitter(Shape.SPARK, Orient.VELOCITY, Vector2(0.1, 1.1), 480, 0.5, 0.0)
	_emitters.erase(e)
	e.name = "BrakeSparks"
	e.position = Vector3(0, 0.06, -0.3)
	var pm := _box(e, Vector3(0.55, 0.01, 1.3), Vector3(0, 0.3, -1), 24.0, 6.0, 15.0, Vector3(0, -9.8, 0))
	pm.inherit_velocity_ratio = 0.6
	pm.particle_flag_align_y = true
	_scale(pm, 0.8, 1.5, [])
	# Cores acima de 1: brilham (glow) mesmo de dia
	pm.color_ramp = _ramp([[0.0, Color(3.0, 2.8, 2.2)], [0.25, Color(2.6, 1.7, 0.6)], [0.6, Color(1.8, 0.7, 0.15)], [1.0, Color(1.0, 0.16, 0.0, 0.0)]])
	e.emitting = false
	_brake_sparks = e


# ---------------------------------------------------------------------------
# Montagem
# ---------------------------------------------------------------------------
func _emitter(shape: Shape, orient: Orient, size: Vector2, amount: int, life: float, idle: float, local := false) -> GPUParticles3D:
	if _shader == null:
		_shader = load("res://shaders/car/car_particle.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("orient", orient)
	var quad := QuadMesh.new()
	quad.size = size * SIZE
	quad.material = mat
	var e := GPUParticles3D.new()
	e.name = "Trail%s" % Shape.keys()[shape].capitalize()
	e.process_material = ParticleProcessMaterial.new()
	e.draw_pass_1 = quad
	e.amount = amount
	e.lifetime = life
	e.local_coords = local
	# Emite a cada quadro (a 30 Hz o rastro abre buracos com o carro rápido)
	e.fixed_fps = 0
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.visibility_aabb = AABB(Vector3(-120, -20, -120), Vector3(240, 60, 240))
	e.set_meta("idle", idle)
	add_child(e)
	_emitters.append(e)
	return e


func _box(e: GPUParticles3D, extents: Vector3, dir: Vector3, spread: float, vmin: float, vmax: float,
		gravity: Vector3) -> ParticleProcessMaterial:
	var pm := e.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = dir.normalized()
	pm.spread = spread
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = gravity
	return pm


func _spin(pm: ParticleProcessMaterial, speed: float) -> void:
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -speed
	pm.angular_velocity_max = speed


func _turbulence(e: GPUParticles3D, strength: float, noise_scale: float, imin: float, imax: float) -> void:
	var pm := e.process_material as ParticleProcessMaterial
	e.set_meta("turb", Vector2(imin, imax))
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = strength
	pm.turbulence_noise_scale = noise_scale
	pm.turbulence_influence_min = imin
	pm.turbulence_influence_max = imax


func _scale(pm: ParticleProcessMaterial, smin: float, smax: float, curve: Array) -> void:
	pm.scale_min = smin
	pm.scale_max = smax
	if curve.is_empty():
		return
	var c := Curve.new()
	c.max_value = 3.0
	for pt: Vector2 in curve:
		c.add_point(pt)
	var tex := CurveTexture.new()
	tex.curve = c
	pm.scale_curve = tex


## Paleta: cada partícula nasce com uma destas cores (sorteada).
static func _palette(cols: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for k in cols.size():
		offsets.append(float(k) / cols.size())
		colors.append(cols[k])
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


## Rampa ao longo da vida: [[offset, cor], ...].
static func _ramp(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s in stops:
		offsets.append(s[0])
		colors.append(s[1])
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


## Só o alfa ao longo da vida: [[offset, alfa], ...].
static func _alpha_ramp(stops: Array) -> GradientTexture1D:
	var out := []
	for s in stops:
		out.append([s[0], Color(1, 1, 1, s[1])])
	return _ramp(out)


func _fire_material(band: bool) -> ShaderMaterial:
	if _fire_shader == null:
		_fire_shader = load("res://shaders/car/car_fire_trail.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = _fire_shader
	mat.set_shader_parameter("band", band)
	return mat


## Fita de fogo que segue o contato de uma roda, [param lift] metros acima do chão.
func _fire_ribbon(ribbon_name: String, mode: TrailRibbon.Mode, width: float, life: float, wheel: VehicleWheel3D,
		lift: float, band: bool) -> void:
	var ribbon := TrailRibbon.new()
	ribbon.name = ribbon_name
	ribbon.mode = mode
	ribbon.width = width
	ribbon.lifetime = life
	ribbon.max_points = 220
	ribbon.min_spacing = 0.3
	ribbon.fade_start = 0.0
	ribbon.taper = band
	ribbon.color = Color.WHITE
	ribbon.material_override = _fire_material(band)
	add_child(ribbon)
	# Os pontos já são de mundo (top_level): sem isto a fita herda onde o carro estava ao criá-la
	ribbon.global_transform = Transform3D.IDENTITY
	ribbon.set_meta("wheel", wheel)
	ribbon.set_meta("lift", lift)
	_ribbons.append(ribbon)


func _add_light(color: Color, pos: Vector3, reach: float) -> void:
	_light = OmniLight3D.new()
	_light.name = "TrailLight"
	_light.light_color = color
	_light.position = pos
	_light.omni_range = reach
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	add_child(_light)


# ---------------------------------------------------------------------------
# A cada quadro
# ---------------------------------------------------------------------------
## Fogo no chão: a fita segue o ponto de contato de cada roda traseira enquanto o carro anda.
func _update_ribbons() -> void:
	if _ribbons.is_empty():
		return
	var up := car.global_basis.y
	var fwd := car.global_basis.z
	for r in _ribbons:
		if r.has_meta("anchor"):
			if _speed < 2.0:
				r.stop()
			else:
				r.add_point(car.to_global(r.get_meta("anchor")), up, fwd)
			continue
		var w := r.get_meta("wheel") as VehicleWheel3D
		if w == null or _speed < 2.0:
			r.stop()
			continue
		var lift: float = r.get_meta("lift", 0.03)
		if w.is_in_contact():
			var n := w.get_contact_normal()
			r.add_point(w.get_contact_point() + n * lift, n, fwd)
		else:
			r.add_point(w.global_position - up * (w.wheel_radius - lift), up, fwd)


## [param lit]: 0 apagada (parado fora da garagem) a 1.
func _update_light(f: float, lit: float, delta: float) -> void:
	if _light == null:
		return
	if effect == "lightning":
		# Clarões curtos e aleatórios
		if randf() < delta * (3.0 + 9.0 * f) * lit:
			_light_energy = randf_range(3.0, 6.0)
		_light_energy = maxf(_light_energy - delta * 40.0, 0.0)
	else:
		_light_energy = (1.0 + 2.2 * f) * lit * (0.75 + 0.25 * sin(_time * 23.0) * sin(_time * 7.3 + 1.0))
	_light.light_energy = _light_energy
	_light.visible = _light_energy > 0.01


# ---------------------------------------------------------------------------
# Ícone (Estúdio, Galeria, roleta)
# ---------------------------------------------------------------------------
## Desenha o ícone de um efeito num retângulo (2D, à mão).
static func draw_icon(ci: CanvasItem, id: String, r: Rect2, alpha := 1.0) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) / 46.0
	var a := alpha
	match id:
		"bubbles":
			for b in [[Vector2(-10, 6), 13.0, Color("8fe9ff")], [Vector2(12, -8), 9.0, Color("ffb3ec")], [Vector2(14, 12), 6.0, Color("c6ffb3")]]:
				var p: Vector2 = c + (b[0] as Vector2) * s
				var rad: float = b[1] * s
				ci.draw_circle(p, rad, Color(b[2], 0.12 * a))
				ci.draw_arc(p, rad, 0, TAU, 32, Color(b[2], 0.9 * a), 1.6 * s, true)
				ci.draw_circle(p + Vector2(-0.35, -0.4) * rad, rad * 0.22, Color(1, 1, 1, 0.9 * a))
		"stars":
			for st in [[Vector2(-9, 4), 13.0, Color("ffd84d")], [Vector2(12, -10), 8.0, Color("ff6fd8")], [Vector2(13, 12), 6.0, Color("5ff3ff")]]:
				var p: Vector2 = c + (st[0] as Vector2) * s
				ci.draw_circle(p, st[1] * s * 1.2, Color(st[2], 0.12 * a))
				ci.draw_colored_polygon(_star_points(p, st[1] * s, st[1] * s * 0.45, 5, -PI / 2.0), Color(st[2], a))
		"fire":
			ci.draw_rect(Rect2(c + Vector2(-26, 16) * s, Vector2(52, 3) * s), Color(1.0, 0.4, 0.05, 0.5 * a))
			for fl in [[-12.0, 1.0], [2.0, 1.3], [15.0, 0.9]]:
				var x: float = fl[0]
				var h: float = fl[1]
				for layer in [[Color("e8360a"), 1.0], [Color("ff8a1a"), 0.7], [Color("ffe08a"), 0.4]]:
					var k: float = layer[1]
					var base := c + Vector2(x, 17) * s
					var pts := PackedVector2Array([base + Vector2(-8 * k, 0) * s, base + Vector2(-7 * k, -10 * h * k) * s,
						base + Vector2(-1, -30 * h * k) * s, base + Vector2(3 * k, -16 * h * k) * s, base + Vector2(8 * k, -8 * h * k) * s,
						base + Vector2(7 * k, 0) * s])
					ci.draw_colored_polygon(pts, Color(layer[0], a))
		"lightning":
			var bolt := PackedVector2Array([Vector2(4, -26), Vector2(-8, -2), Vector2(2, -2), Vector2(-6, 26), Vector2(12, -6),
				Vector2(1, -6), Vector2(10, -26)])
			for i in bolt.size():
				bolt[i] = c + bolt[i] * s
			ci.draw_circle(c, 24 * s, Color("8fd8ff", 0.12 * a))
			ci.draw_colored_polygon(bolt, Color("bfeaff", a))
			ci.draw_polyline(bolt + PackedVector2Array([bolt[0]]), Color("ffffff", a), 1.5 * s, true)
			ci.draw_line(c + Vector2(-16, 10) * s, c + Vector2(-24, 18) * s, Color("b48cff", a), 2.0 * s)
			ci.draw_line(c + Vector2(18, 4) * s, c + Vector2(25, -4) * s, Color("b48cff", a), 2.0 * s)
		"sakura":
			for pt in [[Vector2(-8, 2), 0.4, 1.0], [Vector2(12, -10), -0.7, 0.7], [Vector2(10, 14), 1.4, 0.6]]:
				var p: Vector2 = c + (pt[0] as Vector2) * s
				var k: float = pt[2]
				for petal in 5:
					var ang: float = pt[1] + TAU * petal / 5.0
					var q := p + Vector2(cos(ang), sin(ang)) * 6.0 * s * k
					ci.draw_set_transform(q, ang + PI / 2.0, Vector2(0.62, 1.0))
					ci.draw_circle(Vector2.ZERO, 6.0 * s * k, Color("ffb7d5", a))
					ci.draw_set_transform_matrix(Transform2D.IDENTITY)
				ci.draw_circle(p, 2.2 * s * k, Color("ff6fae", a))
		"snow":
			for fl in [[Vector2(-6, 0), 16.0], [Vector2(15, -13), 7.0], [Vector2(15, 14), 6.0]]:
				var p: Vector2 = c + (fl[0] as Vector2) * s
				var rad: float = fl[1] * s
				for k in 6:
					var d := Vector2.from_angle(TAU * k / 6.0)
					ci.draw_line(p, p + d * rad, Color("e0f7ff", a), maxf(1.0, 2.0 * s))
					var m := p + d * rad * 0.55
					ci.draw_line(m, m + d.rotated(0.9) * rad * 0.3, Color("9ff0ff", a), maxf(1.0, 1.4 * s))
					ci.draw_line(m, m + d.rotated(-0.9) * rad * 0.3, Color("9ff0ff", a), maxf(1.0, 1.4 * s))
		"embers":
			for e in [[Vector2(-10, 10), 5.0], [Vector2(4, -4), 4.0], [Vector2(14, 8), 3.0], [Vector2(-4, -16), 3.0], [Vector2(16, -18), 2.0], [Vector2(-18, -4), 2.5]]:
				var p: Vector2 = c + (e[0] as Vector2) * s
				ci.draw_circle(p, e[1] * s * 2.2, Color("ff7a1a", 0.18 * a))
				ci.draw_circle(p, e[1] * s, Color("ffd27a", a))
		"coins":
			for co in [[Vector2(-10, 6), 12.0, 1.0], [Vector2(11, -9), 9.0, 0.45], [Vector2(13, 13), 7.0, 0.8]]:
				var p: Vector2 = c + (co[0] as Vector2) * s
				var rad: float = co[1] * s
				ci.draw_set_transform(p, 0.0, Vector2(co[2], 1.0))
				ci.draw_circle(Vector2.ZERO, rad, Color("c9901e", a))
				ci.draw_circle(Vector2.ZERO, rad * 0.8, Color("ffc93c", a))
				ci.draw_colored_polygon(_star_points(Vector2.ZERO, rad * 0.5, rad * 0.22, 5, -PI / 2.0), Color("ffe48a", a))
				ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		"smoke":
			for pf in [[Vector2(-12, 8), 11.0, Retro.c("accent")], [Vector2(4, 0), 13.0, Retro.c("accent_2")], [Vector2(15, -10), 9.0, Color("ff3dd8")]]:
				ci.draw_circle(c + (pf[0] as Vector2) * s, pf[1] * s, Color(pf[2], 0.75 * a))
		"rainbow":
			var cols := [Color("ff3b3b"), Color("ff9a1f"), Color("ffe03a"), Color("3ddc6b"), Color("2f9bff"), Color("6a5cff"), Color("c04dff")]
			for k in cols.size():
				var rad := (22.0 - k * 2.6) * s
				var arc := PackedVector2Array()
				for q in 17:
					arc.append(c + Vector2(0, 10 * s) + Vector2.from_angle(PI + PI * q / 16.0) * rad)
				ci.draw_polyline(arc, Color(cols[k], a), 2.8 * s)
			for st: Vector2 in [Vector2(-18, 14), Vector2(19, 12)]:
				ci.draw_colored_polygon(_star_points(c + st * s, 5.0 * s, 2.2 * s, 4, 0.0), Color(1, 1, 1, a))


static func _star_points(c: Vector2, outer: float, inner: float, n: int, start: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n * 2:
		var ang := start + PI * k / n
		pts.append(c + Vector2(cos(ang), sin(ang)) * (outer if k % 2 == 0 else inner))
	return pts
