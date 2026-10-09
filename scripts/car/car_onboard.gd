class_name CarOnboard
extends Node3D
## Equipamentos de bordo visíveis da câmera do piloto:
##  * Retrovisores funcionais: cada "MirrorGlassL/R" do modelo recebe a imagem (espelhada) de uma
##    câmera traseira renderizada num SubViewport.
##  * Display do volante: SteeringDisplay desenhado num SubViewport e aplicado sobre a face do
##    "SteeringWheel" (gira junto com o volante).
## Reconecta tudo sozinho quando as peças do carro são trocadas (CarAssembly.parts_rebuilt).

## Tamanho da textura de cada retrovisor (proporção do vidro ≈ 2,7:1).
@export var mirror_resolution := Vector2i(432, 160)
@export var mirror_fov := 24.0
## Giro das câmeras dos retrovisores para fora (graus), para enxergar as laterais traseiras.
@export var mirror_outward_deg := 13.0
@export var display_resolution := Vector2i(512, 256)
## Retrovisores atualizam todo quadro só quando `mirrors_active` (câmeras de bordo).
## Fora disso atualizam a cada N quadros (um espelho de cada vez), para economizar; o display do
## volante também.
@export var idle_mirror_interval := 30
## Abaixo deste FPS, nas câmeras de bordo, os dois espelhos se revezam (cada um a meio FPS): cada
## espelho é a cidade inteira renderizada de novo.
@export var mirror_alternate_below_fps := 90
## Taxa máxima de redesenho do display do volante (Hz).
const DISPLAY_HZ := 30.0

var mirrors_active := false

var car: F1Car
var _mirror_views: Array[SubViewport] = []
var _mirror_cameras: Array[Camera3D] = []
var _mirror_locals: Array[Transform3D] = []
var _mirror_glass: Array[Node3D] = []
var _display_view: SubViewport
var _display: SteeringDisplay
var _frame := 0
var _display_wait := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	car = get_parent() as F1Car
	for i in 2:
		var view := SubViewport.new()
		view.name = "MirrorView%d" % i
		view.size = mirror_resolution
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cam := Camera3D.new()
		cam.fov = mirror_fov
		cam.near = 0.05
		cam.far = 400.0
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		view.add_child(cam)
		add_child(view)
		_mirror_views.append(view)
		_mirror_cameras.append(cam)
		_mirror_locals.append(Transform3D.IDENTITY)
		_mirror_glass.append(null)

	_display_view = SubViewport.new()
	_display_view.name = "SteeringDisplayView"
	_display_view.size = display_resolution
	_display_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_display = SteeringDisplay.new()
	_display.car = car
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display_view.add_child(_display)
	add_child(_display_view)

	# Os filhos ficam prontos antes do pai: o F1Car ainda não montou as peças. A montagem
	# emite parts_rebuilt quando terminar (e a cada troca de peça).
	(car.get_node("Visual") as CarAssembly).parts_rebuilt.connect(_attach)


## Posição global do vidro de um retrovisor (0 = esquerdo, 1 = direito), para a câmera do piloto mirar.
func get_mirror_position(index: int) -> Vector3:
	var glass := _mirror_glass[index]
	if is_instance_valid(glass):
		return glass.global_position
	return car.global_transform * Vector3(0.5 if index == 0 else -0.5, 0.75, 0.42)


func _attach() -> void:
	if car == null or car.assembly == null:
		return
	var mirrors := car.assembly.get_part_node("mirrors")
	for i in 2:
		var suffix := "L" if i == 0 else "R"
		var glass := (mirrors.find_child("MirrorGlass" + suffix + "*", true, false) as MeshInstance3D) if mirrors else null
		_mirror_glass[i] = glass
		if glass == null:
			continue
		var aabb := glass.get_aabb()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = _mirror_views[i].get_texture()
		# Espelho: imagem invertida na horizontal
		mat.uv1_scale = Vector3(-1, 1, 1)
		mat.uv1_offset = Vector3(1, 0, 0)
		_add_screen(glass, "MirrorImage", Vector2(aabb.size.x, aabb.size.y),
			aabb.get_center() + Vector3(0, 0, aabb.position.z - aabb.get_center().z - 0.0005), mat)
		# Câmera no vidro olhando para trás (câmera olha para -Z, que é a traseira do carro)
		var outward := deg_to_rad(mirror_outward_deg) * (-1.0 if i == 0 else 1.0)
		var to_car := car.global_transform.affine_inverse() * glass.global_transform
		_mirror_locals[i] = Transform3D(Basis(Vector3.UP, outward), to_car.origin + Vector3(0, 0.01, -0.02))

	var wheel := car.assembly.find_in_part("cockpit", "SteeringWheel*")
	if wheel:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = _display_view.get_texture()
		# Face do volante voltada para o piloto (-Z local), logo à frente do corpo do volante.
		_add_screen(wheel, "DisplayImage", Vector2(0.222, 0.111), Vector3(0, 0, -0.0245), mat)


func _add_screen(parent: Node3D, node_name: String, quad_size: Vector2, pos: Vector3, mat: Material) -> void:
	var old := parent.get_node_or_null(node_name)
	if old:
		old.free()
	var quad := QuadMesh.new()
	quad.size = quad_size
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation.y = PI  # o QuadMesh olha para +Z; aqui precisa olhar para trás (-Z, piloto)
	# Mesma camada da peça (o painel do volante some junto com ele na câmera do capô)
	if parent is VisualInstance3D:
		mi.layers = (parent as VisualInstance3D).layers
	parent.add_child(mi)


func _process(delta: float) -> void:
	if car == null:
		return
	_frame += 1
	var xf := car.get_global_transform_interpolated()
	var alternate := Engine.get_frames_per_second() < mirror_alternate_below_fps
	for i in 2:
		var update: bool
		if mirrors_active:
			update = not alternate or (_frame + i) % 2 == 0
		else:
			update = (_frame + i * idle_mirror_interval / 2) % idle_mirror_interval == 0
		_mirror_views[i].render_target_update_mode = SubViewport.UPDATE_ONCE if update else SubViewport.UPDATE_DISABLED
		if update:
			_mirror_cameras[i].global_transform = xf * _mirror_locals[i]
	# Display do volante: a 30 Hz nas câmeras de bordo; fora delas, de vez em quando
	_display_wait -= delta
	if (mirrors_active and _display_wait <= 0.0) or (not mirrors_active and _frame % idle_mirror_interval == 0):
		_display_wait = 1.0 / DISPLAY_HZ
		_display.queue_redraw()
		_display_view.render_target_update_mode = SubViewport.UPDATE_ONCE
