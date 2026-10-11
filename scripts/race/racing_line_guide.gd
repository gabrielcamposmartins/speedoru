class_name RacingLineGuide
extends RacingLineGuideCore
## Linha ideal no chão: setas em "V" ao longo da trajetória à frente do carro do jogador, coloridas
## pela velocidade atual comparada à ideal em cada trecho (perfil do bot difícil):
##   verde = abaixo do ideal (pode acelerar) · amarelo = no limite · vermelho = acima (frear).
## Modo (Configurações → Jogo, ou L na pista): 0 desligada, 1 só nas frenagens e curvas, 2 completa.
## A cada quadro roda no código nativo (RacingLineGuideCore, native/src/guide.rs, com as mesmas
## constantes): `mode` e `suppressed` (escondida por fora) também são de lá.

const COUNT := 48
const SPACING := 7.0
const START := 9.0
const LIFT := 0.025
## Inclinação das setas (subida por metro para trás).
const TILT := 0.1
## Intensidade da cor (HDR).
const GLOW := 2.4

var car: F1Car
var line: RacingLine
var profile: PackedFloat32Array


func setup(p_car: F1Car, p_line: RacingLine, p_profile: PackedFloat32Array) -> void:
	car = p_car
	line = p_line
	profile = p_profile
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _chevron_mesh()
	mm.instance_count = COUNT
	multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 2
	mat.disable_fog = true
	material_override = mat
	_core_setup(car, line.native, profile)


## "V" apontando para a frente (+Z): 2,2 m de largura, braços de 42 cm, quase deitado no asfalto
## (parte de trás levantada só ~6° para não sumir na câmera de perseguição).
static func _chevron_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0, 0, 0.8)
	var w := 0.42
	for side in [-1.0, 1.0]:
		var back := Vector3(1.1 * side, 0, -0.6)
		var dir := (back - tip).normalized()
		var n := Vector3(-dir.z, 0, dir.x) * w * 0.5
		var quad := [tip + n, tip - n, back - n, back + n]
		for q in 4:
			quad[q].y = (0.8 - quad[q].z) * TILT
		st.set_color(Color.WHITE)
		st.add_vertex(quad[0])
		st.add_vertex(quad[1])
		st.add_vertex(quad[2])
		st.add_vertex(quad[0])
		st.add_vertex(quad[2])
		st.add_vertex(quad[3])
	return st.commit()
