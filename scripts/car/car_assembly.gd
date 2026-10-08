@tool
class_name CarAssembly
extends Node3D
## Monta o visual do carro a partir de um CarConfig.
##
## Cada peça (.glb) vira um filho deste nó com o nome do slot. Pneus e rodas são instanciados
## dentro de cada VehicleWheel3D para girar/esterçar junto com a física. Ao sincronizar, só as
## peças cuja variante mudou são recriadas; cores são atualizadas direto nos materiais.

signal parts_rebuilt

## Camada de render da cabeça do piloto: a câmera de 1ª pessoa a remove do cull_mask.
const HEAD_LAYER := 1 << 9
## Camada extra das malhas do carro (a luz de contorno do Daylight só ilumina esta camada).
const CAR_LAYER := 1 << 10
## Camada do halo, do volante (com o painel) e do corpo do piloto: a câmera do capô a remove do
## cull_mask, para mostrar só o lado de fora do carro (rodas da frente, bico e retrovisores).
const INTERIOR_LAYER := 1 << 11
## Camadas que só o próprio carro usa (decals e luzes de efeito não devem pegar nelas).
const OWN_LAYERS := CAR_LAYER | HEAD_LAYER | INTERIOR_LAYER

var livery := CarLivery.new()

var _built := {}        # slot -> variante instanciada
var _decals_key := ""   # decalques montados (texto do dicionário)
var _decals_root: Node3D
var _nodes := {}        # slot -> Node3D (peças da carroceria)
var _wheel_nodes := {}  # "slot:NomeDaRoda" -> Node3D


func sync(config: CarConfig, wheels: Array) -> void:
	if config == null:
		return
	livery.update_from_config(config)
	var changed := false
	for slot in CarPartCatalog.SLOTS:
		var variant := config.get_part(slot)
		if _built.get(slot, "") == variant and is_instance_valid(_nodes.get(slot)):
			continue
		_replace_part(slot, variant)
		changed = true
	for slot in CarPartCatalog.WHEEL_SLOTS:
		var variant := config.get_part(slot)
		if _built.get(slot, "") == variant and _wheels_built(slot, wheels):
			continue
		for wheel in wheels:
			_replace_wheel_part(slot, variant, wheel)
		_built[slot] = variant
		changed = true
	_sync_decals(config)
	if changed:
		parts_rebuilt.emit()


## Remonta os decalques mesmo sem mudança (arquivos da pasta do jogador trocados).
func refresh_decals() -> void:
	_decals_key = ""
	var f1 := get_parent() as F1Car
	if f1 and f1.config:
		_sync_decals(f1.config)


## Decalques SVG projetados na carroceria (só remonta quando o dicionário muda).
func _sync_decals(config: CarConfig) -> void:
	var key := var_to_str(config.decals)
	if key == _decals_key and is_instance_valid(_decals_root):
		return
	_decals_key = key
	if not is_instance_valid(_decals_root):
		_decals_root = Node3D.new()
		_decals_root.name = "Decals"
		add_child(_decals_root)
	CarDecals.build(_decals_root, config.decals)


func get_part_node(slot: String) -> Node3D:
	var node: Node3D = _nodes.get(slot)
	return node if is_instance_valid(node) else null


## Procura um nó dentro de uma peça pelo prefixo do nome (ex.: "DRSFlap*").
func find_in_part(slot: String, pattern: String) -> Node3D:
	var part := get_part_node(slot)
	if part == null:
		return null
	return part.find_child(pattern, true, false) as Node3D


func clear() -> void:
	for node in _nodes.values() + _wheel_nodes.values():
		_discard(node)
	_nodes.clear()
	_wheel_nodes.clear()
	_built.clear()


static func _tag_car_layer(node: Node) -> void:
	for vi in node.find_children("*", "VisualInstance3D", true, false):
		(vi as VisualInstance3D).layers |= CAR_LAYER
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers |= CAR_LAYER


func _replace_part(slot: String, variant: String) -> void:
	_discard(_nodes.get(slot))
	_nodes.erase(slot)
	var node := _instantiate(CarPartCatalog.part_path(slot, variant))
	if node:
		node.name = slot
		add_child(node)
		_tag_car_layer(node)
		for head in node.find_children("DriverHelmet*", "VisualInstance3D", true, false):
			(head as VisualInstance3D).layers = HEAD_LAYER
		_tag_interior(slot, node)
		_nodes[slot] = node
	_built[slot] = variant


## Halo inteiro, volante e painel do cockpit, corpo do piloto (o capacete fica na HEAD_LAYER).
static func _tag_interior(slot: String, node: Node) -> void:
	var targets: Array[Node] = []
	match slot:
		"halo", "driver":
			targets.append(node)
		"cockpit":
			# (o painel "DisplayImage" é criado depois pelo CarOnboard e copia a camada do volante)
			targets.append_array(node.find_children("SteeringWheel*", "Node3D", true, false))
	for t in targets:
		var list: Array[Node] = t.find_children("*", "VisualInstance3D", true, false)
		if t is VisualInstance3D:
			list.append(t)
		for vi in list:
			if not (vi as VisualInstance3D).layers & HEAD_LAYER:
				(vi as VisualInstance3D).layers = INTERIOR_LAYER


func _replace_wheel_part(slot: String, variant: String, wheel: Node3D) -> void:
	var key := slot + ":" + wheel.name
	_discard(_wheel_nodes.get(key))
	_wheel_nodes.erase(key)
	var axle := "front" if wheel.position.z > 0.0 else "rear"
	var node := _instantiate(CarPartCatalog.wheel_part_path(slot, variant, axle))
	if node == null:
		return
	node.name = "Visual_" + slot
	_tag_car_layer(node)
	# Os modelos têm a face externa em +X (lado esquerdo); do lado direito giramos 180°.
	if wheel.position.x < 0.0:
		node.rotation.y = PI
	wheel.add_child(node)
	_wheel_nodes[key] = node


func _wheels_built(slot: String, wheels: Array) -> bool:
	for wheel in wheels:
		if not is_instance_valid(_wheel_nodes.get(slot + ":" + wheel.name)):
			return false
	return true


func _instantiate(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("Peça não encontrada: " + path)
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	livery.apply_to(node)
	return node


func _discard(node: Variant) -> void:
	if node is Node and is_instance_valid(node):
		var n := node as Node
		if n.get_parent():
			n.get_parent().remove_child(n)
		n.queue_free()
