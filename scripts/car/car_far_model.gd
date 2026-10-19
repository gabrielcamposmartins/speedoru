class_name CarFarModel
extends MeshInstance3D
## Modelo do carro para quando ele está longe da câmera: todas as peças visíveis do Visual
## (carroceria, asas, bico, sidepods, suspensão, retrovisores, capacete…) juntas numa malha só, uma
## superfície por material (os mesmos materiais do carro: cores, brilho do boost e luz de freio
## continuam valendo), com níveis de detalhe (LOD) gerados para ela. Perto, cada peça era um objeto
## para o renderizador cortar, ordenar e desenhar — também nas cascatas da sombra (~40 por carro).
##
## A troca é do próprio Godot, pelas faixas de visibilidade: as peças somem a partir de FAR + OVERLAP
## e o modelo aparece a partir de FAR (as duas faixas se cruzam um pouco, sem buraco). Vale para a
## câmera de cada viewport (retrovisores inclusive) e para as sombras, sem conferência por quadro e
## sem mexer no `visible` das peças (o dano e o pisca mexem nele). As rodas (giram e esterçam) e o
## corpo do piloto (com esqueleto) ficam de fora.
##
## Montagem: os vértices das peças são lidos na thread principal (eles vêm da placa de vídeo) e
## guardados por malha (os carros dividem as mesmas peças); a junção e os LODs rodam numa thread
## (WorkerThreadPool) e a malha nova entra na thread principal. Refeito quando as peças mudam
## (parts_ready) ou o carro sofre dano. Só com janela (servidor e testes sem janela não montam).

const FAR := 85.0
const OVERLAP := 3.0
const MARGIN := 2.0
## LODs: ângulos (graus) de junção e de separação das normais (ImporterMesh.generate_lods).
const LOD_MERGE_ANGLE := 25.0
const LOD_SPLIT_ANGLE := 60.0

var car: F1Car
var _dirty := true
var _task := -1
var _built: ImporterMesh
var _parts: Array[GeometryInstance3D] = []
var _pending_parts: Array[GeometryInstance3D] = []
## Arrays de cada malha já lida (id da malha → [WeakRef, superfícies]).
static var _cache := {}
## Último quadro em que um modelo começou a ser montado (no máximo um por quadro).
static var _started_frame := -1


## Põe o modelo de longe no carro (nada sem janela ou se já tem).
static func attach(p_car: F1Car) -> void:
	if p_car == null or DisplayServer.get_name() == "headless" or p_car.has_node("FarModel"):
		return
	var fm := CarFarModel.new()
	fm.name = "FarModel"
	fm.car = p_car
	p_car.add_child(fm)


func _ready() -> void:
	visibility_range_begin = FAR
	visibility_range_begin_margin = MARGIN
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	car.parts_ready.connect(_mark_dirty)
	var damage := car.get_node_or_null("Damage")
	if damage:
		damage.part_detached.connect(func(_p: String) -> void: _mark_dirty())
		damage.hit_applied.connect(func(_l: Vector3, _d: Vector3, _s: float) -> void: _mark_dirty())


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _task >= 0:
		if WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			_finish()
		return
	if _dirty and Engine.get_process_frames() != _started_frame:
		_started_frame = Engine.get_process_frames()
		_start()


## Junta as peças visíveis agora (thread principal: lê os vértices) e manda montar numa thread.
func _start() -> void:
	_dirty = false
	var assembly := car.assembly
	if assembly == null:
		return
	var inv := car.global_transform.affine_inverse()
	var items: Array = []
	_pending_parts.clear()
	for node in assembly.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.skin != null or not _shown(mi, assembly):
			continue
		# As cópias amassadas pelo dano mudam a cada batida: lidas de novo, sem cache
		var surfaces := _arrays_of(mi.mesh, str(mi.name).begins_with("Damaged"))
		if surfaces.is_empty():
			continue
		var xf := inv * mi.global_transform
		for s in surfaces.size():
			items.append([surfaces[s], xf, mi.get_active_material(s)])
		_pending_parts.append(mi)
	if items.is_empty():
		return
	_task = WorkerThreadPool.add_task(_merge.bind(items), false, "CarFarModel")


## A peça aparece (ela e os pais até o Visual; o próprio Visual não conta).
static func _shown(node: Node3D, top: Node3D) -> bool:
	var n: Node = node
	while n != null and n != top:
		if n is Node3D and not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


## Superfícies (arrays) de uma malha, lidas uma vez por malha (`fresh`: lê de novo).
static func _arrays_of(mesh: Mesh, fresh := false) -> Array:
	var id := mesh.get_instance_id()
	var hit: Variant = _cache.get(id)
	if not fresh and hit != null and (hit[0] as WeakRef).get_ref() == mesh:
		return hit[1]
	var surfaces: Array = []
	for s in mesh.get_surface_count():
		# Malhas prontas (QuadMesh, BoxMesh…) são sempre triângulos
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			surfaces.append([])
			continue
		var arr := mesh.surface_get_arrays(s)
		var verts: Variant = arr[Mesh.ARRAY_VERTEX] if arr.size() > Mesh.ARRAY_VERTEX else null
		surfaces.append(arr if verts != null and (verts as PackedVector3Array).size() > 0 else [])
	_cache[id] = [weakref(mesh), surfaces]
	return surfaces


## Superfícies de um mesmo material (e com os mesmos atributos) juntas.
class Group:
	var mat: Material
	var has: Array
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	## Acrescenta uma superfície já no espaço do carro. Normais pela inversa transposta (peça
	## espelhada ou com escala) e, numa peça espelhada, o sentido dos triângulos invertido (senão ela
	## fica "do avesso").
	func add(arr: Array, xf: Transform3D) -> void:
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var base := v.size()
		v.append_array(xf * verts)
		var nb := xf.basis.inverse().transposed()
		var mirrored := xf.basis.determinant() < 0.0
		if has[0]:
			var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var out := PackedVector3Array()
			out.resize(normals.size())
			for k in normals.size():
				out[k] = (nb * normals[k]).normalized()
			n.append_array(out)
		if has[1]:
			var tan: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			var out := PackedFloat32Array()
			out.resize(tan.size())
			for k in tan.size() / 4:
				var d := (xf.basis * Vector3(tan[k * 4], tan[k * 4 + 1], tan[k * 4 + 2])).normalized()
				out[k * 4] = d.x
				out[k * 4 + 1] = d.y
				out[k * 4 + 2] = d.z
				out[k * 4 + 3] = -tan[k * 4 + 3] if mirrored else tan[k * 4 + 3]
			t.append_array(out)
		if has[2]:
			uv.append_array(arr[Mesh.ARRAY_TEX_UV])
		if has[3]:
			uv2.append_array(arr[Mesh.ARRAY_TEX_UV2])
		if has[4]:
			c.append_array(arr[Mesh.ARRAY_COLOR])
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for k in verts.size():
				idx[k] = k
		var out_i := PackedInt32Array()
		out_i.resize(idx.size())
		for k in idx.size() / 3:
			var a := idx[k * 3] + base
			var b := idx[k * 3 + 1] + base
			var e := idx[k * 3 + 2] + base
			out_i[k * 3] = a
			out_i[k * 3 + 1] = e if mirrored else b
			out_i[k * 3 + 2] = b if mirrored else e
		i.append_array(out_i)

	func arrays() -> Array:
		var out: Array = []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = v
		if has[0]:
			out[Mesh.ARRAY_NORMAL] = n
		if has[1]:
			out[Mesh.ARRAY_TANGENT] = t
		if has[2]:
			out[Mesh.ARRAY_TEX_UV] = uv
		if has[3]:
			out[Mesh.ARRAY_TEX_UV2] = uv2
		if has[4]:
			out[Mesh.ARRAY_COLOR] = c
		out[Mesh.ARRAY_INDEX] = i
		return out


## Na thread: junta as superfícies por material (e pelos atributos que têm), já transformadas para o
## espaço do carro, e gera os LODs.
func _merge(items: Array) -> void:
	var groups := {}
	for it: Array in items:
		var arr: Array = it[0]
		if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
			continue
		var mat: Material = it[2]
		var has := [arr[Mesh.ARRAY_NORMAL] != null, arr[Mesh.ARRAY_TANGENT] != null, arr[Mesh.ARRAY_TEX_UV] != null,
			arr[Mesh.ARRAY_TEX_UV2] != null, arr[Mesh.ARRAY_COLOR] != null]
		var key := "%d:%s" % [mat.get_instance_id() if mat else 0, str(has)]
		var g: Group = groups.get(key)
		if g == null:
			g = Group.new()
			g.mat = mat
			g.has = has
			groups[key] = g
		g.add(arr, it[1])
	var im := ImporterMesh.new()
	for key in groups:
		var g: Group = groups[key]
		if g.v.is_empty():
			continue
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, g.arrays(), [], {}, g.mat)
	if im.get_surface_count() > 0:
		im.generate_lods(LOD_MERGE_ANGLE, LOD_SPLIT_ANGLE, [])
	_built = im


## Na thread principal: a malha nova entra e as peças juntadas ganham a faixa de visibilidade.
func _finish() -> void:
	if _built == null or _built.get_surface_count() == 0:
		return
	mesh = _built.get_mesh()
	_built = null
	for p in _parts:
		if is_instance_valid(p) and not _pending_parts.has(p):
			p.visibility_range_end = 0.0
	_parts = _pending_parts.duplicate()
	for p in _parts:
		if is_instance_valid(p):
			p.visibility_range_end = FAR + OVERLAP
			p.visibility_range_end_margin = MARGIN
