class_name GrassField
extends MultiMeshInstance3D
## Campo de grama 3D que acompanha a câmera ativa (raio `radius`). Os tufos ficam numa grade
## fixa no mundo (o nó anda em passos de `spacing`); o shader lê a altura do terreno e uma
## máscara (pista, zebras, brita, boxes) renderizada uma vez de cima, num mundo 3D separado.

@export var radius := 52.0
@export var spacing := 0.4

var _material: ShaderMaterial
var _mask_view: SubViewport

const MASK_RESOLUTION := 0.5  # m por pixel
const MASK_MARGIN := 40.0


func setup(track: RaceTrack, terrain: TrackTerrain, surfaces: Array[MeshInstance3D]) -> void:
	name = "GrassField"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/track/grass.gdshader")
	terrain.apply_heightmap(_material)
	_material.set_shader_parameter("spacing", spacing)
	_material.set_shader_parameter("radius", radius)
	material_override = _material

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _tuft_mesh()
	var cells := int(ceil(radius / spacing))
	var transforms: Array[Transform3D] = []
	for z in range(-cells, cells + 1):
		for x in range(-cells, cells + 1):
			var p := Vector3(x * spacing, 0.0, z * spacing)
			if p.length() <= radius:
				transforms.append(Transform3D(Basis(), p))
	mm.instance_count = transforms.size()
	var buf := PackedFloat32Array()
	buf.resize(transforms.size() * 12)
	for i in transforms.size():
		var o := transforms[i].origin
		buf[i * 12] = 1.0
		buf[i * 12 + 3] = o.x
		buf[i * 12 + 5] = 1.0
		buf[i * 12 + 7] = 0.0
		buf[i * 12 + 10] = 1.0
		buf[i * 12 + 11] = o.z
	mm.buffer = buf
	multimesh = mm
	custom_aabb = AABB(Vector3(-radius - 2.0, -5.0, -radius - 2.0), Vector3(radius * 2.0 + 4.0, 200.0, radius * 2.0 + 4.0))
	_build_mask(track, surfaces)


## Máscara: as malhas de piso desenhadas em branco, vistas de cima por uma câmera ortogonal.
func _build_mask(track: RaceTrack, surfaces: Array[MeshInstance3D]) -> void:
	var r := track.path.bounds().grow(MASK_MARGIN)
	_mask_view = SubViewport.new()
	_mask_view.name = "GrassMask"
	_mask_view.own_world_3d = true
	_mask_view.world_3d = World3D.new()
	_mask_view.size = Vector2i(ceili(r.size.x / MASK_RESOLUTION), ceili(r.size.y / MASK_RESOLUTION))
	_mask_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_mask_view.msaa_3d = Viewport.MSAA_DISABLED
	_mask_view.transparent_bg = false
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	var we := WorldEnvironment.new()
	we.environment = env
	_mask_view.add_child(we)
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color.WHITE
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	for s in surfaces:
		if s == null or s.mesh == null:
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = s.mesh
		copy.material_override = white
		copy.transform = s.global_transform
		_mask_view.add_child(copy)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = r.size.y
	cam.near = 1.0
	cam.far = 400.0
	# Olhando para baixo com o "topo" da imagem para -Z: u = x, v = z
	cam.transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(r.get_center().x, 200.0, r.get_center().y))
	_mask_view.add_child(cam)
	add_child(_mask_view)
	_material.set_shader_parameter("surface_mask", _mask_view.get_texture())
	_material.set_shader_parameter("mask_origin", r.position)
	_material.set_shader_parameter("mask_size", r.size)
	_material.set_shader_parameter("has_mask", true)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	global_position = Vector3(snappedf(p.x, spacing), 0.0, snappedf(p.z, spacing))
	_material.set_shader_parameter("field_center", p)


## Tufo: 9 lâminas finas abertas em leque, bem separadas (base num anel, pontas para fora), com
## alturas um pouco diferentes + uma "flor" no centro (escondida pelo shader quando não é flor).
## COLOR.r = altura ao longo da lâmina (0 base, 1 ponta); COLOR.g = 1 na flor; COLOR.b = 1 na haste;
## COLOR.a = valor aleatório da lâmina (o shader varia o tamanho de cada uma por tufo).
static func _tuft_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var blades := 9
	for b in blades:
		var a := TAU * (b + rng.randf_range(-0.2, 0.2)) / blades
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-dir.z, 0.0, dir.x)
		# Base num anel (lâminas separadas) e ponta inclinada para fora
		var base := dir * rng.randf_range(0.05, 0.13)
		var h := rng.randf_range(0.1, 0.19)
		var w := rng.randf_range(0.014, 0.022)
		var lean := dir * rng.randf_range(0.05, 0.1) + side * rng.randf_range(-0.03, 0.03)
		var tip := base + Vector3.UP * h + lean
		var n := (dir + Vector3.UP * 0.8).normalized()
		var id := rng.randf()
		for v in [base - side * w, base + side * w, tip]:
			verts.append(v)
			normals.append(n)
			colors.append(Color(clampf((v as Vector3).y / h, 0.0, 1.0), 0.0, 0.0, id))
	# Flor: duas pétalas cruzadas no alto
	var fh := 0.2
	for k in 2:
		var d := Vector3(1, 0, 0) if k == 0 else Vector3(0, 0, 1)
		var c := Vector3.UP * fh
		for v in [c - d * 0.05, c + d * 0.05, c + Vector3.UP * 0.06, c - d * 0.05, c - Vector3.UP * 0.04, c + d * 0.05]:
			verts.append(v)
			normals.append(Vector3.UP)
			colors.append(Color(1.0, 1.0, 0.0, 0.5))
	# Haste até a flor
	for v in [Vector3(-0.008, 0, 0), Vector3(0.008, 0, 0), Vector3(0, fh, 0)]:
		verts.append(v)
		normals.append(Vector3.UP)
		colors.append(Color(v.y / fh, 1.0, 1.0, 0.5))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
