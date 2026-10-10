class_name FerrisWheel
extends Node3D
## Roda-gigante (a do parque de diversões ao lado de Suzuka): pernas em A, dois aros com raios e
## lâmpadas (acendem mais à noite, material TrackMaterials.lamp) e gôndolas coloridas que ficam
## sempre em pé enquanto a roda gira devagar.
##
## Espaço local: eixo da roda em X, a roda no plano YZ, base no chão em y = 0.

const STEEL := Color(0.95, 0.95, 0.97)
const STEEL_DARK := Color(0.55, 0.58, 0.64)
const GONDOLA_COLORS := [Color(0.95, 0.25, 0.35), Color(1.0, 0.75, 0.15), Color(0.2, 0.6, 0.98), Color(0.2, 0.8, 0.5),
	Color(0.75, 0.4, 0.95), Color(1.0, 0.5, 0.2)]

## Velocidade (rad/s): uma volta a cada ~2 min.
@export var speed := 0.05
var radius := 24.0
var hub_height := 28.0
var count := 24

var _wheel: Node3D
var _gondolas: Array[Node3D] = []
var _angle := 0.0
const HANG := 2.4


## Monta a roda com `diameter` m de diâmetro.
static func create(diameter: float) -> FerrisWheel:
	var fw := FerrisWheel.new()
	fw.name = "FerrisWheel"
	fw.radius = diameter * 0.5
	fw.hub_height = fw.radius + 4.5
	fw._build()
	return fw


func _build() -> void:
	var r := radius
	var hub := Vector3(0.0, hub_height, 0.0)
	var axle := 3.4
	var frame := MeshBuilder.new()
	# Base, pernas em A dos dois lados e o eixo
	frame.box(Transform3D(Basis(), Vector3(0.0, 0.4, 0.0)), Vector3(axle * 2.0 + 6.0, 0.8, r * 0.75), Color(0.75, 0.74, 0.72))
	for sx in [-1.0, 1.0]:
		var top := hub + Vector3(sx * axle, 0.0, 0.0)
		for sz in [-1.0, 1.0]:
			_beam(frame, Vector3(sx * (axle + 1.2), 0.8, sz * r * 0.33), top, 0.75, STEEL)
		_beam(frame, Vector3(sx * (axle + 1.2), hub_height * 0.45, -r * 0.18), Vector3(sx * (axle + 1.2), hub_height * 0.45, r * 0.18), 0.4, STEEL)
	_beam(frame, hub - Vector3(axle + 0.6, 0, 0), hub + Vector3(axle + 0.6, 0, 0), 1.3, STEEL_DARK)
	# Bilheteria na base
	frame.box(Transform3D(Basis(), Vector3(axle + 6.0, 1.9, r * 0.25)), Vector3(4.0, 2.2, 3.0), Color(0.95, 0.35, 0.45), Color(1.0, 0.85, 0.3))
	var mi := MeshInstance3D.new()
	mi.name = "Frame"
	mi.mesh = frame.commit(null, TrackMaterials.structure())
	add_child(mi)

	# Parte que gira: aros, raios, travessas e lâmpadas
	_wheel = Node3D.new()
	_wheel.name = "Wheel"
	_wheel.position = hub
	add_child(_wheel)
	var wheel := MeshBuilder.new()
	var bulbs := MeshBuilder.new()
	var segs := count * 2
	var rim := 1.8
	for sx in [-rim, rim]:
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var p0 := Vector3(sx, sin(a0) * r, cos(a0) * r)
			var p1 := Vector3(sx, sin(a1) * r, cos(a1) * r)
			_beam(wheel, p0, p1, 0.45, STEEL)
			var q0 := Vector3(sx, sin(a0) * r * 0.62, cos(a0) * r * 0.62)
			var q1 := Vector3(sx, sin(a1) * r * 0.62, cos(a1) * r * 0.62)
			_beam(wheel, q0, q1, 0.3, STEEL)
			bulbs.box(Transform3D(Basis(), p0 * Vector3(1.0, 1.0, 1.0) + Vector3(signf(sx) * 0.3, 0, 0)), Vector3(0.35, 0.35, 0.35),
				Color(1.0, 0.9, 0.6) if k % 2 == 0 else Color(1.0, 0.55, 0.75))
		for k in count:
			var a := TAU * k / count
			var tip := Vector3(sx, sin(a) * r, cos(a) * r)
			_beam(wheel, Vector3(sx * 0.5, 0, 0), tip, 0.22, STEEL)
			# Diagonal entre os aros (treliça)
			var b := TAU * (k + 0.5) / count
			_beam(wheel, Vector3(sx, sin(a) * r * 0.62, cos(a) * r * 0.62), Vector3(sx, sin(b) * r, cos(b) * r), 0.18, STEEL)
	for k in count:
		var a := TAU * k / count
		_beam(wheel, Vector3(-rim, sin(a) * r, cos(a) * r), Vector3(rim, sin(a) * r, cos(a) * r), 0.3, STEEL_DARK)
	var wmi := MeshInstance3D.new()
	wmi.name = "Rim"
	wmi.mesh = wheel.commit(null, TrackMaterials.plain())
	_wheel.add_child(wmi)
	var bmi := MeshInstance3D.new()
	bmi.name = "Bulbs"
	bmi.mesh = bulbs.commit(null, TrackMaterials.lamp(2.5))
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wheel.add_child(bmi)

	# Gôndolas: uma malha por cor, penduradas no eixo entre os aros
	var meshes: Array[ArrayMesh] = []
	for c in GONDOLA_COLORS:
		meshes.append(_gondola_mesh(c))
	for k in count:
		var g := MeshInstance3D.new()
		g.name = "Gondola%d" % k
		g.mesh = meshes[k % meshes.size()]
		add_child(g)
		_gondolas.append(g)
	_update()


## Gôndola: cabine hexagonal com janelas, teto em cúpula e a haste até o eixo (origem no eixo).
static func _gondola_mesh(color: Color) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var glass := Color(0.55, 0.8, 0.95)
	var xf := Transform3D(Basis(), Vector3(0.0, -HANG - 1.1, 0.0))
	mb.cylinder(xf, 1.25, 1.25, 0.55, color, 6)
	mb.cylinder(xf.translated(Vector3(0, 0.55, 0)), 1.25, 1.25, 1.1, glass, 6, false)
	mb.cylinder(xf.translated(Vector3(0, 1.65, 0)), 1.3, 0.25, 0.6, color, 6)
	mb.box(Transform3D(Basis(), Vector3(0.0, -HANG * 0.5 + 0.2, 0.0)), Vector3(0.12, HANG - 0.2, 0.12), STEEL_DARK)
	return mb.commit(null, TrackMaterials.structure())


## Viga de seção quadrada entre a e b.
static func _beam(mb: MeshBuilder, a: Vector3, b: Vector3, thick: float, color: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var y := d / length
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	mb.box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(thick, length, thick), color)


func _process(delta: float) -> void:
	_angle = fposmod(_angle + speed * delta, TAU)
	_update()


func _update() -> void:
	_wheel.rotation = Vector3(_angle, 0.0, 0.0)
	var hub := Vector3(0.0, hub_height, 0.0)
	for k in _gondolas.size():
		var a := TAU * k / count - _angle
		_gondolas[k].position = hub + Vector3(0.0, sin(a) * radius, cos(a) * radius)
