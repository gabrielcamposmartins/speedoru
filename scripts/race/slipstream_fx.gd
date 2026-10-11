class_name SlipstreamFx
extends SlipstreamFxCore
## Pista visual do vácuo do carro seguido pela câmera: filetes de vento que saem da frente do
## carro da frente, contornam a carroceria dele e correm até o bico do seu carro, mais fortes e
## numerosos quanto maior o vácuo (shaders/track/slipstream_wind.gdshader).
## A cada quadro roda no código nativo (SlipstreamFxCore, native/src/fx.rs, com as mesmas
## constantes); `car` (o carro do jogador) também é dele.

const STREAKS := 14

var _mesh := ImmediateMesh.new()
var _mat := ShaderMaterial.new()
var _offsets := PackedVector2Array()


func _ready() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat.shader = load("res://shaders/track/slipstream_wind.gdshader")
	material_override = _mat
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for k in STREAKS:
		# Posição no "túnel" de ar em volta do carro: lateral e altura
		_offsets.append(Vector2(rng.randf_range(-1.1, 1.1), rng.randf_range(0.25, 1.25)))
	top_level = true
	global_transform = Transform3D.IDENTITY
	_core_setup(_mesh, _mat, _offsets)
