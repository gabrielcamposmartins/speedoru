class_name SeaSplash
extends CanvasLayer
## Saída da água na pista no fundo do mar: quando a câmera passa da água para o ar (a SeaAtmosphere
## avisa com surfaced()), gotas escorrendo na tela com a imagem distorcida por elas e a película
## d'água descendo no começo (water_lens.gdshader), mais o som da água escorrendo
## (water_exit.wav, bus Crowd: o volume de "ambiente"). Fica embaixo da interface da corrida.

const DURATION := 2.8
const SOUND := "res://assets/audio/ambient/water_exit.wav"
const VOLUME_DB := -3.0

var _rect: ColorRect
var _mat: ShaderMaterial
var _player: AudioStreamPlayer
var _t := -1.0


func _ready() -> void:
	# (por cima da imagem 3D, embaixo do HUD)
	layer = -1
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/track/water_lens.gdshader")
	_rect = ColorRect.new()
	_rect.name = "Lens"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)
	_player = AudioStreamPlayer.new()
	_player.stream = load(SOUND)
	_player.bus = &"Crowd" if AudioServer.get_bus_index(&"Crowd") >= 0 else &"Master"
	_player.volume_db = VOLUME_DB
	add_child(_player)


## A câmera acabou de sair da água.
func surfaced() -> void:
	_t = 0.0
	_mat.set_shader_parameter("seed", randf() * 100.0)
	_mat.set_shader_parameter("elapsed", 0.0)
	_mat.set_shader_parameter("strength", 1.0)
	_rect.visible = true
	_player.play()


## O efeito está na tela.
func active() -> bool:
	return _t >= 0.0


## A câmera voltou para dentro da água: as gotas somem na hora.
func cancel() -> void:
	_t = -1.0
	if _rect:
		_rect.visible = false


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var k := 1.0 - _t / DURATION
	if k <= 0.0:
		_t = -1.0
		_rect.visible = false
		return
	_mat.set_shader_parameter("elapsed", _t)
	_mat.set_shader_parameter("strength", k)
