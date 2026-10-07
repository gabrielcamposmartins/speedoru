class_name SafetyCar
extends Node3D
## Safety car: carro esportivo prateado com barra de luzes âmbar piscando no teto, que anda na linha
## ideal à frente do líder durante a bandeira amarela. É só visual (sem colisão): passar por ele é
## punido pelo RaceControl. Posição = `progress` (metros ao longo da pista, mesma conta do RaceEntry).

## Velocidade nas retas; nas curvas segue o perfil de velocidade da linha ideal (CORNER_FACTOR).
const SPEED := 180.0 / 3.6
const SLOW := 9.0
const CORNER_FACTOR := 0.8

var progress := 0.0
var speed := SPEED
var line: RacingLine
## Perfil de velocidade da linha ideal (m/s por trecho), para frear nas curvas. Vazio = só SPEED.
var profile := PackedFloat32Array()
var track: RaceTrack

var _lights: Array[MeshInstance3D] = []
var _amber: StandardMaterial3D
var _off: StandardMaterial3D
var _glow: OmniLight3D
var _t := 0.0


func setup(p_track: RaceTrack, p_line: RacingLine, start_progress: float) -> void:
	track = p_track
	line = p_line
	progress = start_progress
	_build()
	_place()


func _mat(c: Color, rough := 0.3, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _build() -> void:
	var body := _mat(Color("dfe3ea"), 0.25, 0.25)
	var dark := _mat(Color("16181d"), 0.4)
	var glass := _mat(Color("1c2a3c"), 0.05, 0.6)
	var stripe := _mat(Color("ffd21f"), 0.4)
	# Carroceria baixa, cabine recuada, faixas amarelas
	_box(Vector3(1.95, 0.55, 4.6), Vector3(0, 0.5, 0), body)
	_box(Vector3(1.7, 0.42, 2.1), Vector3(0, 0.96, -0.35), glass)
	_box(Vector3(1.6, 0.06, 1.9), Vector3(0, 1.18, -0.4), body)
	_box(Vector3(1.97, 0.12, 4.62), Vector3(0, 0.62, 0), stripe)
	_box(Vector3(1.9, 0.18, 0.2), Vector3(0, 0.36, 2.3), dark)
	_box(Vector3(1.9, 0.08, 0.35), Vector3(0, 0.82, -2.25), dark)
	for x in [-0.86, 0.86]:
		for z in [-1.45, 1.45]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.34
			cm.bottom_radius = 0.34
			cm.height = 0.26
			w.mesh = cm
			w.material_override = dark
			w.position = Vector3(x, 0.34, z)
			w.rotation.z = PI / 2.0
			add_child(w)
	# Faróis e lanternas
	var head := _mat(Color.WHITE)
	head.emission_enabled = true
	head.emission = Color("fff6e0")
	head.emission_energy_multiplier = 3.0
	var tail := _mat(Color("ff2020"))
	tail.emission_enabled = true
	tail.emission = Color("ff2020")
	tail.emission_energy_multiplier = 3.0
	for x in [-0.7, 0.7]:
		_box(Vector3(0.35, 0.1, 0.05), Vector3(x, 0.6, 2.31), head)
		_box(Vector3(0.4, 0.08, 0.05), Vector3(x, 0.66, -2.31), tail)
	# Barra de luzes no teto (âmbar, piscando alternado) + verde no meio
	_amber = _mat(Color("ffb000"))
	_amber.emission_enabled = true
	_amber.emission = Color("ffa000")
	_amber.emission_energy_multiplier = 8.0
	_amber.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_off = _mat(Color("4a3a10"))
	_box(Vector3(1.3, 0.1, 0.3), Vector3(0, 1.25, -0.4), dark)
	for x in [-0.45, 0.45]:
		_lights.append(_box(Vector3(0.36, 0.12, 0.26), Vector3(x, 1.33, -0.4), _amber))
	var green := _mat(Color("3dff6e"))
	green.emission_enabled = true
	green.emission = Color("3dff6e")
	green.emission_energy_multiplier = 4.0
	_box(Vector3(0.2, 0.1, 0.24), Vector3(0, 1.32, -0.4), green)
	_glow = OmniLight3D.new()
	_glow.light_color = Color("ffa000")
	_glow.omni_range = 9.0
	_glow.position = Vector3(0, 1.8, -0.4)
	add_child(_glow)
	for side in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = "SAFETY CAR"
		l.font = Retro.display(900)
		l.font_size = 60
		l.pixel_size = 0.006
		l.modulate = Color("16181d")
		l.position = Vector3(0.99 * side, 0.5, 0.2)
		l.rotation.y = PI / 2.0 * side
		add_child(l)


func _process(delta: float) -> void:
	_t += delta
	var phase := int(_t * 6.0) % 2
	for k in _lights.size():
		_lights[k].material_override = _amber if k % 2 == phase else _off
	_glow.light_energy = 2.5 if phase == 0 else 1.0


## Anda `delta` segundos a até 180 km/h (mais devagar nas curvas); espera o líder se ele ficar
## longe demais.
func advance(delta: float, leader_progress: float) -> void:
	var gap := progress - leader_progress
	var target := SPEED if gap < 110.0 else SLOW
	if not profile.is_empty():
		# Olha um pouco à frente para já chegar na curva devagar
		var ahead := fposmod(progress + 15.0 + speed * 1.2, track.path.length)
		target = minf(target, RacingLine.sample(profile, track.path, ahead) * CORNER_FACTOR)
	speed = move_toward(speed, target, (9.0 if target < speed else 5.0) * delta)
	progress += speed * delta
	_place()


func _place() -> void:
	var s := fposmod(progress, track.path.length)
	var p0 := line.position_at(s)
	var p1 := line.position_at(s + 2.0)
	var fwd := p1 - p0
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	var q := PhysicsRayQueryParameters3D.create(p0 + Vector3.UP * 4.0, p0 + Vector3.DOWN * 4.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q) if is_inside_tree() else {}
	var ground: Vector3 = hit["position"] if hit.has("position") else p0
	global_transform = Transform3D(Basis(Vector3.UP.cross(fwd).normalized(), Vector3.UP, fwd), ground)
