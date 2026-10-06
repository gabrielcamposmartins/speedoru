extends Node3D
## Cenário de teste: coloca o carro na largada e cria obstáculos simples
## (slalom de cones e uma rampa) na área livre à esquerda da reta principal.

@export var cone_count := 12
@export var cone_spacing := 18.0

@onready var car: F1Car = $F1Car
@onready var circuit: TestCircuit = $Circuit


func _ready() -> void:
	car.global_transform = circuit.get_start_transform(30.0).translated(Vector3.UP * 0.05)
	car.reset_physics_interpolation()
	_spawn_cones()
	_spawn_ramp()


func _spawn_cones() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.2
	mesh.height = 0.6
	mesh.radial_segments = 10
	var mat := CarLivery._toon(Color("ff7a1a"), 0.3)
	var shape := CylinderShape3D.new()
	shape.radius = 0.16
	shape.height = 0.6
	for i in cone_count:
		var cone := RigidBody3D.new()
		cone.name = "Cone%d" % i
		cone.mass = 3.0
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		cone.add_child(mi)
		var col := CollisionShape3D.new()
		col.shape = shape
		cone.add_child(col)
		add_child(cone)
		var x := -45.0 + (3.0 if i % 2 == 0 else -3.0)
		cone.global_position = Vector3(x, 0.3, -60.0 + i * cone_spacing)


func _spawn_ramp() -> void:
	var ramp := StaticBody3D.new()
	ramp.name = "Ramp"
	var box := BoxMesh.new()
	box.size = Vector3(8.0, 0.4, 16.0)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = CarLivery._toon(Color("f1f2f6"), 0.4)
	ramp.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	ramp.add_child(col)
	add_child(ramp)
	ramp.global_transform = Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(9.0)), Vector3(-45.0, 1.05, 220.0))
