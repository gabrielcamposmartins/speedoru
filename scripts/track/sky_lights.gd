class_name SkyLights
extends Node3D
## LEDs da Sky Aerobase: a cor de todos (frisos da plataforma e das barreiras, aros sobre a pista)
## muda a cada volta, entre azul, verde e roxo, com uma transição suave. A volta é a de quem lidera a
## corrida (no treino, a do jogador); sem corrida, fica na primeira cor. À noite, luzes de verdade
## ao longo das barreiras na mesma cor (grupo "night_lights": o RaceTrack liga, desliga e dosa com o
## horário) iluminam a pista onde a luz dos postes não chega.

const PALETTE := [Color(0.25, 0.62, 1.0), Color(0.2, 1.0, 0.5), Color(0.72, 0.32, 1.0)]
## Segundos da transição de uma cor para a outra.
const FADE := 1.5
## Luzes ao longo das barreiras (alternando os lados): intervalo (m), alcance e força.
const LIGHT_SPACING := 18.0
const LIGHT_RANGE := 24.0
const LIGHT_ENERGY := 3.6

static var _materials: Array[ShaderMaterial] = []

var _lights: Array[OmniLight3D] = []
var _track: RaceTrack
var _manager: Node
var _color: Color = PALETTE[0]
## Transição em andamento: da cor `_from` para `_to`, `_t` de 0 a 1.
var _from: Color = PALETTE[0]
var _to: Color = PALETTE[0]
var _t := 1.0


## Cor dos LEDs na volta `lap` (0 = antes da primeira volta completa).
static func color_for_lap(lap: int) -> Color:
	return PALETTE[posmod(lap, PALETTE.size())]


## Material de LED que troca de cor com os outros (sky_glow.gdshader com use_led_color).
static func register(mat: ShaderMaterial) -> ShaderMaterial:
	mat.set_shader_parameter("use_led_color", true)
	mat.set_shader_parameter("led_color", PALETTE[0])
	if not _materials.has(mat):
		_materials.append(mat)
	return mat


static func build(track: RaceTrack, parent: Node3D) -> SkyLights:
	var node := SkyLights.new()
	node.name = "SkyLights"
	node._track = track
	parent.add_child(node)
	if RaceTrack.server_mode:
		return node
	var p := track.path
	var count := int(p.length / LIGHT_SPACING)
	for k in count:
		var side := 1 if k % 2 == 0 else -1
		var s := (k + 0.5) * p.length / count
		var i := p.index_at(s)
		if track.in_tunnel(i):
			continue
		var d := track.barrier[RaceTrack._si(side)][i]
		var light := OmniLight3D.new()
		light.omni_range = LIGHT_RANGE
		light.omni_attenuation = 0.9
		light.shadow_enabled = false
		light.light_specular = 0.2
		light.light_color = PALETTE[0]
		light.set_meta("base_energy", LIGHT_ENERGY)
		light.visible = false
		light.add_to_group("night_lights")
		node.add_child(light)
		light.global_position = track.edge_point(i, side, d - 0.4, 1.6)
		node._lights.append(light)
	return node


## Volta atual de quem lidera (no treino, do jogador); 0 sem corrida.
func current_lap() -> int:
	if _manager == null or not is_instance_valid(_manager):
		_manager = _track.get_parent().get_node_or_null("RaceManager") if _track and _track.get_parent() else null
		if _manager == null:
			return 0
	var best := 0
	for e: RaceEntry in _manager.entries:
		best = maxi(best, e.laps_completed())
	return best


func _process(delta: float) -> void:
	var target := color_for_lap(current_lap())
	if target != _to:
		_from = _color
		_to = target
		_t = 0.0
	if _t >= 1.0:
		return
	_t = minf(_t + delta / FADE, 1.0)
	_color = _from.lerp(_to, smoothstep(0.0, 1.0, _t))
	for mat in _materials:
		mat.set_shader_parameter("led_color", _color)
	for light in _lights:
		light.light_color = _color
