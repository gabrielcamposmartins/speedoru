class_name RacingLineGuide
extends MultiMeshInstance3D
## Linha ideal no chão: setas em "V" ao longo da trajetória à frente do carro do jogador, coloridas
## pela velocidade atual comparada à ideal em cada trecho (perfil do bot difícil):
##   verde = abaixo do ideal (pode acelerar) · amarelo = no limite · vermelho = acima (frear).
## Modo (Configurações → Jogo, ou L na pista): 0 desligada, 1 só nas frenagens e curvas, 2 completa.

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
var mode := 2

var _path: TrackPath
var _s := 0.0


func setup(p_car: F1Car, p_line: RacingLine, p_profile: PackedFloat32Array) -> void:
	car = p_car
	line = p_line
	profile = p_profile
	_path = line.path
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
	_s = _path.project(car.global_position).x


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


## Escondida por fora (apresentação antes da largada).
var suppressed := false


func _process(_delta: float) -> void:
	if car == null or multimesh == null:
		return
	visible = mode > 0 and not suppressed
	if not visible:
		return
	# Posição do carro ao longo da pista; as setas começam alguns metros à frente
	var proj := _path.project(car.global_position)
	_s = proj.x
	var v := car.linear_velocity.length()
	for k in COUNT:
		var s := _s + START + k * SPACING
		var ideal := RacingLine.sample(profile, _path, s)
		var p0 := line.position_at(s)
		var p1 := line.position_at(s + 1.0)
		var fwd := (p1 - p0)
		fwd.y = 0.0
		if fwd.length_squared() < 1e-6:
			fwd = Vector3.FORWARD
		fwd = fwd.normalized()
		var basis := Basis(Vector3.UP.cross(fwd).normalized(), Vector3.UP, fwd)
		var xf := Transform3D(basis, _ground(p0) + Vector3.UP * LIFT)
		var col := _speed_color(v, ideal)
		# Some suave perto do carro e no fim da linha
		var fade := clampf(float(k) / 3.0, 0.0, 1.0) * clampf(float(COUNT - k) / 12.0, 0.0, 1.0)
		if mode == 1 and not _matters(s, ideal):
			fade = 0.0
		col.a *= fade
		# Cor em HDR (acima de 1) para atravessar o tonemap sem ficar pálida
		col = Color(col.r * GLOW, col.g * GLOW, col.b * GLOW, col.a)
		multimesh.set_instance_transform(k, xf)
		multimesh.set_instance_color(k, col)


## Altura do asfalto naquele ponto (a linha central do traçado não acompanha o relevo da pista).
func _ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 4.0)
	q.exclude = [car.get_rid()]
	var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if hit.has("position") else p


## Cor pela diferença entre a velocidade atual e a ideal naquele ponto.
static func _speed_color(v: float, ideal: float) -> Color:
	var diff := v - ideal
	var green := Color(0.1, 1.0, 0.35, 0.92)
	var yellow := Color(1.0, 0.8, 0.0, 0.95)
	var red := Color(1.0, 0.08, 0.1, 0.95)
	if diff < -6.0:
		return green
	if diff < 0.0:
		return green.lerp(yellow, (diff + 6.0) / 6.0)
	if diff < 5.0:
		return yellow.lerp(red, diff / 5.0)
	return red


## Modo "só nas frenagens e curvas": onde a velocidade ideal cai ou a curvatura é alta.
func _matters(s: float, ideal: float) -> bool:
	var before := RacingLine.sample(profile, _path, s - 60.0)
	if before - ideal > 4.0:
		return true
	return absf(RacingLine.sample(line.curvature, _path, s)) > 1.0 / 450.0
