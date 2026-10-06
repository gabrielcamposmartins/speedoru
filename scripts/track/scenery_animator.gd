class_name SceneryAnimator
extends Node3D
## Anima os objetos do cenário: rotores das turbinas, balões flutuando, dirigíveis em órbita e
## nuvens levadas pelo vento (voltam do outro lado ao sair da área).

## Vento das nuvens (m/s, no plano XZ).
@export var cloud_wind := Vector2(7.0, 4.5)

var _rotors: Array = []    # [nó, velocidade (rad/s)]
var _balloons: Array = []  # [nó, posição base, fase]
var _blimps: Array = []    # [nó, centro, raios, velocidade (m/s, sinal = sentido), ângulo]
var _clouds: Array = []    # [MultiMesh, transforms, centro, raio]
var _flocks: Array = []    # [nó, centro, raios, velocidade, fase]
var _passes: Array = []    # [nó, a, b, velocidade, t (0..2)]
var _time := 0.0
## Terreno (opcional): dirigíveis e pássaros mantêm altura mínima sobre o relevo.
var terrain: TrackTerrain
var _lift := {}  # nó -> subida extra atual (m), suavizada


func add_rotor(node: Node3D, speed: float) -> void:
	_rotors.append([node, speed])


func add_balloon(node: Node3D, base: Vector3, phase: float) -> void:
	_balloons.append([node, base, phase])


func add_blimp(node: Node3D, center: Vector3, radii: Vector2, speed: float) -> void:
	_blimps.append([node, center, radii, speed, randf() * TAU])
	_update_blimp(_blimps[_blimps.size() - 1], 0.0)


## Bando de pássaros dando voltas (curva de Lissajous) em volta de `center`.
func add_flock(node: Node3D, center: Vector3, radii: Vector2, speed: float, phase: float) -> void:
	_flocks.append([node, center, radii, speed, phase])


## Dirigível passando em linha reta de `a` até `b` e voltando (vira longe da pista).
func add_blimp_pass(node: Node3D, a: Vector3, b: Vector3, speed: float, start: float) -> void:
	_passes.append([node, a, b, speed, start])


func remove_blimp(node: Node3D) -> void:
	_blimps = _blimps.filter(func(b): return b[0] != node)


func add_clouds(mm: MultiMesh, transforms: Array[Transform3D], center: Vector2, radius: float) -> void:
	_clouds.append([mm, transforms.duplicate(), center, radius])


func _process(delta: float) -> void:
	_time += delta
	for r in _rotors:
		(r[0] as Node3D).rotate_object_local(Vector3.BACK, r[1] * delta)
	for b in _balloons:
		var node: Node3D = b[0]
		var base: Vector3 = b[1]
		var ph: float = b[2]
		node.position = base + Vector3(sin(_time * 0.05 + ph) * 60.0, sin(_time * 0.3 + ph) * 4.0, cos(_time * 0.04 + ph) * 60.0)
		node.rotation.y = _time * 0.05 + ph
	for b in _blimps:
		_update_blimp(b, delta)
	for f in _flocks:
		var node: Node3D = f[0]
		var center: Vector3 = f[1]
		var radii: Vector2 = f[2]
		var speed: float = f[3]
		var ph: float = f[4]
		var w := speed / ((radii.x + radii.y) * 0.5)
		var pos := _flock_pos(center, radii, _time * w + ph)
		var ahead := _flock_pos(center, radii, _time * w + ph + 0.02)
		var vel := ahead - pos
		var bank := clampf(vel.normalized().cross(Vector3.UP).dot((ahead - pos).normalized()), -0.4, 0.4)
		pos.y += _clearance(node, pos, vel.normalized(), 14.0, delta)
		node.global_transform = Transform3D(Basis.looking_at(-vel.normalized()) * Basis(Vector3.BACK, bank), pos)
	for pa in _passes:
		var node: Node3D = pa[0]
		var a: Vector3 = pa[1]
		var b: Vector3 = pa[2]
		var length := a.distance_to(b)
		pa[4] = fposmod(float(pa[4]) + delta * float(pa[3]) / length, 2.0)
		var t: float = pa[4]
		var forward := t < 1.0
		var u := t if forward else 2.0 - t
		var dir := (b - a).normalized() * (1.0 if forward else -1.0)
		var pos := a.lerp(b, u) + Vector3.UP * sin(_time * 0.15 + length) * 4.0
		pos.y += _clearance(node, pos, dir, 40.0, delta)
		node.global_transform = Transform3D(Basis.looking_at(-dir), pos)
	var drift := Vector3(cloud_wind.x, 0.0, cloud_wind.y) * delta
	for c in _clouds:
		var mm: MultiMesh = c[0]
		var list: Array = c[1]
		var center: Vector2 = c[2]
		var radius: float = c[3]
		for i in list.size():
			var t: Transform3D = list[i]
			t.origin += drift
			var rel := Vector2(t.origin.x - center.x, t.origin.z - center.y)
			if rel.length() > radius:
				# Reaparece do lado de onde o vento vem
				rel = -rel.normalized() * radius * 0.98
				t.origin = Vector3(center.x + rel.x, t.origin.y, center.y + rel.y)
			list[i] = t
			mm.set_instance_transform(i, t)


## Quanto subir para ficar `margin` m acima do terreno (olhando 80 m à frente), suavizado.
func _clearance(node: Node3D, pos: Vector3, dir: Vector3, margin: float, delta: float) -> float:
	if terrain == null:
		return 0.0
	var ground := maxf(terrain.height_at(pos.x, pos.z), terrain.height_at(pos.x + dir.x * 80.0, pos.z + dir.z * 80.0))
	var need := maxf(ground + margin - pos.y, 0.0)
	var current: float = _lift.get(node, need)
	current = move_toward(current, need, delta * (6.0 if need > current else 2.0))
	_lift[node] = current
	return current


static func _flock_pos(center: Vector3, radii: Vector2, a: float) -> Vector3:
	return center + Vector3(cos(a) * radii.x, sin(a * 2.0) * 6.0, sin(a * 0.8 + 1.3) * radii.y)


func _update_blimp(b: Array, delta: float) -> void:
	var node: Node3D = b[0]
	var center: Vector3 = b[1]
	var radii: Vector2 = b[2]
	var speed: float = b[3]
	# Velocidade aproximadamente constante ao longo da elipse (raio médio)
	b[4] = float(b[4]) + delta * speed / ((radii.x + radii.y) * 0.5)
	var ang: float = b[4]
	var p := center + Vector3(cos(ang) * radii.x, sin(_time * 0.2 + ang) * 6.0, sin(ang) * radii.y)
	var d := signf(speed) * 0.01
	var ahead := center + Vector3(cos(ang + d) * radii.x, 0.0, sin(ang + d) * radii.y)
	var dir := Vector3(ahead.x - p.x, 0.0, ahead.z - p.z)
	if dir.length_squared() < 1e-8:
		return
	p.y += _clearance(node, p, dir.normalized(), 40.0, delta)
	node.global_transform = Transform3D(Basis.looking_at(-dir.normalized()), p)
