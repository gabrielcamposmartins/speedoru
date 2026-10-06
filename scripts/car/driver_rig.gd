class_name DriverRig
extends Node
## IK dos braços do piloto: mantém as mãos nas manoplas enquanto o volante gira.
##
## Monta, em tempo de execução, dentro do Skeleton3D da peça "driver":
##  * TwoBoneIK3D (2 configurações): braço → antebraço → mão até um alvo preso ao volante, com o
##    cotovelo puxado na direção de um polo (calculado a partir da pose de repouso do modelo).
##  * CopyTransformModifier3D: copia a rotação do alvo para a mão (o punho gira com o volante).
##
## Não depende da geometria do modelo atual: basta um esqueleto com os nomes de ossos abaixo
## (padrão SkeletonProfileHumanoid do Godot). Se as mãos do novo modelo não estiverem nas manoplas
## na pose de repouso, o IK as leva até `left_grip` / `right_grip` (espaço do volante).

@export_group("Ossos")
@export var left_upper_arm := "LeftUpperArm"
@export var left_lower_arm := "LeftLowerArm"
@export var left_hand := "LeftHand"
@export var right_upper_arm := "RightUpperArm"
@export var right_lower_arm := "RightLowerArm"
@export var right_hand := "RightHand"

@export_group("Pegada no volante")
## Leva o centro da palma até as manoplas (desligue para usar a posição de repouso do modelo).
@export var snap_to_grips := true
## Centro das manoplas no espaço do nó do volante (frente do volante = -Z, para o piloto).
@export var left_grip := Vector3(0.128, -0.01, -0.012)
@export var right_grip := Vector3(-0.128, -0.01, -0.012)
## Distância do pulso (início do osso da mão) ao centro da palma, ao longo do osso da mão (+Y).
@export var palm_distance := 0.05
## Distância do polo do cotovelo, a partir do cotovelo de repouso.
@export var pole_distance := 0.4
## O punho acompanha a rotação do volante (CopyTransformModifier3D).
@export var rotate_hands := true

var car: F1Car
var ik: TwoBoneIK3D
var hand_copy: CopyTransformModifier3D
var _created: Array[Node] = []
var _driver_part: Node3D
var _wheel_node: Node3D
## Poses finais (depois do IK) das mãos e cotovelos, no espaço global. Os SkeletonModifier3D
## só valem durante a atualização do esqueleto; fora dela get_bone_global_pose() volta ao FK.
var hand_poses: Array[Transform3D] = [Transform3D(), Transform3D()]
var elbow_positions: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	car = get_parent() as F1Car
	# Os filhos ficam prontos antes do pai: espera a montagem das peças.
	car.parts_ready.connect(_setup)


## Distância (m) entre cada pulso e o alvo dele na manopla (depuração/testes).
func get_hand_errors() -> PackedFloat32Array:
	var errors := PackedFloat32Array()
	if ik == null or not is_instance_valid(ik):
		return errors
	for i in ik.setting_count:
		errors.append(hand_poses[i].origin.distance_to(get_target(i).global_position))
	return errors


func get_target(index: int) -> Node3D:
	return ik.get_node(ik.get_target_node(index)) as Node3D


func _on_skeleton_updated() -> void:
	if ik == null or not is_instance_valid(ik):
		return
	var skeleton := ik.get_skeleton()
	for i in ik.setting_count:
		hand_poses[i] = skeleton.global_transform * skeleton.get_bone_global_pose(
			skeleton.find_bone(ik.get_end_bone_name(i)))
		elbow_positions[i] = (skeleton.global_transform * skeleton.get_bone_global_pose(
			skeleton.find_bone(ik.get_middle_bone_name(i)))).origin


func _setup() -> void:
	var driver_now := car.assembly.get_part_node("driver")
	var wheel_now := car.assembly.find_in_part("cockpit", "SteeringWheel*")
	if driver_now == _driver_part and wheel_now == _wheel_node and is_instance_valid(ik):
		return  # só cores mudaram
	_driver_part = driver_now
	_wheel_node = wheel_now
	for node in _created:
		if is_instance_valid(node):
			node.queue_free()
	_created.clear()
	ik = null
	hand_copy = null

	var driver := car.assembly.get_part_node("driver")
	var wheel := car.assembly.find_in_part("cockpit", "SteeringWheel*")
	if driver == null or wheel == null:
		return
	var skeletons := driver.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_warning("DriverRig: o modelo do piloto não tem Skeleton3D.")
		return
	var skeleton := skeletons[0] as Skeleton3D
	var arms := [
		[left_upper_arm, left_lower_arm, left_hand, left_grip, "L"],
		[right_upper_arm, right_lower_arm, right_hand, right_grip, "R"],
	]
	for arm in arms:
		for bone_name in arm.slice(0, 3):
			if skeleton.find_bone(bone_name) < 0:
				push_warning("DriverRig: osso '%s' não encontrado." % bone_name)
				return

	# Volante na posição reta (o carro pode estar esterçando quando a peça é trocada).
	var wheel_rest: Transform3D = (wheel.get_parent() as Node3D).global_transform * car.get_steering_wheel_rest()
	var to_wheel: Transform3D = wheel_rest.affine_inverse()

	ik = TwoBoneIK3D.new()
	ik.name = "ArmIK"
	ik.setting_count = arms.size()
	hand_copy = CopyTransformModifier3D.new()
	hand_copy.name = "HandRotation"
	hand_copy.setting_count = arms.size()
	skeleton.add_child(ik)
	skeleton.add_child(hand_copy)
	if not skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_created.append_array([ik, hand_copy])

	for i in arms.size():
		var arm: Array = arms[i]
		var upper := skeleton.find_bone(arm[0])
		var lower := skeleton.find_bone(arm[1])
		var hand := skeleton.find_bone(arm[2])
		var shoulder_rest := skeleton.global_transform * skeleton.get_bone_global_rest(upper)
		var elbow_rest := skeleton.global_transform * skeleton.get_bone_global_rest(lower)
		var hand_rest := skeleton.global_transform * skeleton.get_bone_global_rest(hand)

		# Alvo do pulso, preso ao volante: rotação de repouso da mão; posição de repouso do pulso
		# ou corrigida para a palma cair na manopla.
		var target_local: Transform3D = to_wheel * hand_rest
		if snap_to_grips:
			# Ossos vindos do Blender/glTF apontam para +Y local.
			var hand_axis := hand_rest.basis.y.normalized()
			var palm_local: Vector3 = target_local.origin + to_wheel.basis * (hand_axis * palm_distance)
			target_local.origin += arm[3] - palm_local
		var target := Node3D.new()
		target.name = "GripTarget" + arm[4]
		target.transform = target_local
		wheel.add_child(target)

		# Polo do cotovelo: mesmo lado para onde o cotovelo aponta na pose de repouso.
		var mid := shoulder_rest.origin.lerp(hand_rest.origin, 0.5)
		var bend := (elbow_rest.origin - mid).normalized()
		var pole := Node3D.new()
		pole.name = "ElbowPole" + arm[4]
		driver.add_child(pole)
		pole.global_position = elbow_rest.origin + bend * pole_distance
		_created.append_array([target, pole])

		ik.set_root_bone_name(i, arm[0])
		ik.set_middle_bone_name(i, arm[1])
		ik.set_end_bone_name(i, arm[2])
		ik.set_target_node(i, ik.get_path_to(target))
		ik.set_pole_node(i, ik.get_path_to(pole))

		hand_copy.set_apply_bone_name(i, arm[2])
		hand_copy.set_reference_type(i, 1)  # referência = nó
		hand_copy.set_reference_node(i, hand_copy.get_path_to(target))
		hand_copy.set_copy_position(i, false)
		hand_copy.set_copy_scale(i, false)
		hand_copy.set_copy_rotation(i, true)
		hand_copy.set_relative(i, false)
	hand_copy.active = rotate_hands
