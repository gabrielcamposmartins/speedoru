class_name SlipstreamFx
extends MeshInstance3D
## Pista visual do vácuo do carro seguido pela câmera: filetes de vento que saem da frente do
## carro da frente, contornam a carroceria dele e correm até o bico do seu carro, mais fortes e
## numerosos quanto maior o vácuo (shaders/track/slipstream_wind.gdshader).

const STREAKS := 14
const SEGMENTS := 10
const WIDTH := 0.09

var car: F1Car
var _mesh := ImmediateMesh.new()
var _mat := ShaderMaterial.new()
var _offsets: Array[Vector2] = []
var _shown := 0.0


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


func _process(delta: float) -> void:
	_mesh.clear_surfaces()
	var target := car
	var cam := get_viewport().get_camera_3d()
	if cam is RaceCamera and (cam as RaceCamera).target:
		target = (cam as RaceCamera).target
	if target == null or not is_instance_valid(target):
		return
	var src := target.slipstream_source
	_shown = move_toward(_shown, clampf(target.slipstream, 0.0, 1.0) if src and is_instance_valid(src) else 0.0, delta * 3.0)
	_mat.set_shader_parameter("strength", _shown)
	if _shown <= 0.01 or src == null or not is_instance_valid(src):
		return
	var a_basis := src.global_basis
	var b_basis := target.global_basis
	var start := src.global_position + a_basis.z * 2.6
	var end := target.global_position + b_basis.z * 2.4
	var to_cam := (cam.global_position - (start + end) * 0.5).normalized() if cam else Vector3.UP
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := int(ceil(STREAKS * clampf(_shown * 1.3, 0.3, 1.0)))
	for k in count:
		var o := _offsets[k]
		var pts: Array[Vector3] = []
		for i in SEGMENTS + 1:
			var t := float(i) / SEGMENTS
			# Sai rente ao bico, abre em volta da carroceria do carro da frente e fecha de novo no seu
			var bulge := sin(clampf(t * 1.6, 0.0, 1.0) * PI) * 0.6 + 0.4
			var basis := a_basis.slerp(b_basis, t)
			var p := start.lerp(end, t) + basis.x * o.x * bulge + basis.y * o.y * (0.6 + 0.4 * bulge)
			pts.append(p)
		for i in SEGMENTS:
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var side := (p1 - p0).cross(to_cam).normalized() * WIDTH
			var u0 := float(i) / SEGMENTS
			var u1 := float(i + 1) / SEGMENTS
			var c := Color(float(k) / STREAKS, 0, 0, 1)
			_vert(p0 - side, Vector2(u0, 0), c)
			_vert(p1 - side, Vector2(u1, 0), c)
			_vert(p1 + side, Vector2(u1, 1), c)
			_vert(p0 - side, Vector2(u0, 0), c)
			_vert(p1 + side, Vector2(u1, 1), c)
			_vert(p0 + side, Vector2(u0, 1), c)
	_mesh.surface_end()


func _vert(p: Vector3, uv: Vector2, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_set_uv(uv)
	_mesh.surface_add_vertex(p)
