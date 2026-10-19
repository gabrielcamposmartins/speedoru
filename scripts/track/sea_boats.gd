class_name SeaBoats
extends Node3D
## Barcos na superfície da pista no fundo do mar, perto dela: lanchas e veleiros
## (TrackHarbour.boat_mesh) indo e voltando em linha reta bem por cima da pista, ao longo dela, e
## navios (TrackOffshore.ship_mesh) ao lado, nos trechos abertos (fundos: o casco desce ~8 m), cada
## um com a esteira de espuma atrás. As rotas não passam por cima de rocha, do tubo perto da
## superfície nem da ponte do trecho emerso. De baixo d'água aparecem como silhuetas (o casco está
## na água) e pela janela do céu (SeaWorld.WINDOW_LAYER); do trecho emerso, como barcos. Um _process
## só, para todos (poucos nós).

const SHIPS := [[TrackOffshore.Ship.CRUISE, 210.0, 6.5], [TrackOffshore.Ship.CONTAINER, 180.0, 7.5], [TrackOffshore.Ship.FERRY, 110.0, 9.0]]
## [tipo, comprimento, velocidade]
const SMALL := [[1, 20.0, 7.0], [2, 15.0, 4.5], [3, 7.0, 6.0], [1, 12.0, 8.5], [2, 10.0, 4.0], [1, 20.0, 6.0], [3, 7.0, 5.0],
	[2, 15.0, 5.0], [1, 12.0, 9.0], [2, 12.0, 4.5], [1, 15.0, 7.5], [3, 7.0, 5.5], [2, 20.0, 4.0], [1, 10.0, 8.0]]
## Quanto o casco desce na água (m): navios e barcos pequenos.
const SHIP_DRAFT := 9.0
const BOAT_DRAFT := 1.4

## [nó, ponto a, ponto b, velocidade, fase (0..2), comprimento da rota]
var _boats: Array = []
static var _ship_mat: StandardMaterial3D


static func build(track: RaceTrack, parent: Node3D) -> void:
	var node := SeaBoats.new()
	node.name = "Boats"
	parent.add_child(node)
	node._setup(track)


func _setup(track: RaceTrack) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	if _ship_mat == null:
		_ship_mat = StandardMaterial3D.new()
		_ship_mat.vertex_color_use_as_albedo = true
		_ship_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		_ship_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Navios: ao lado da pista, nos trechos abertos (fundos)
	for spec: Array in SHIPS:
		var route := _near_route(track, rng, SHIP_DRAFT, Vector2(45.0, 150.0), Vector2(700.0, 1100.0), true)
		if route.is_empty():
			continue
		var ship := MeshInstance3D.new()
		ship.name = "Ship"
		ship.mesh = TrackOffshore.ship_mesh(int(spec[0]), float(spec[1]), rng)
		ship.material_override = _ship_mat
		add_child(ship)
		_wake(ship, float(spec[1]))
		_boats.append([ship, route[0], route[1], float(spec[2]), rng.randf() * 2.0, route[0].distance_to(route[1])])
	# Lanchas e veleiros: bem por cima da pista, ao longo dela
	var hull_mat := TrackHarbour._boat_material()
	for spec: Array in SMALL:
		var route := _near_route(track, rng, BOAT_DRAFT, Vector2(-22.0, 22.0), Vector2(260.0, 520.0), false)
		if route.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = TrackHarbour.boat_mesh(int(spec[0]), float(spec[1]))
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D())
		var hull: Color = TrackHarbour.HULLS[rng.randi() % TrackHarbour.HULLS.size()]
		mm.set_instance_custom_data(0, Color(hull, clampf(10.0 / float(spec[1]), 0.12, 1.0)))
		var boat := MultiMeshInstance3D.new()
		boat.name = "Boat"
		boat.multimesh = mm
		boat.material_override = hull_mat
		add_child(boat)
		_wake(boat, float(spec[1]))
		_boats.append([boat, route[0], route[1], float(spec[2]), rng.randf() * 2.0, route[0].distance_to(route[1])])
	# Na janela do céu vista de baixo d'água
	for vi: VisualInstance3D in find_children("*", "VisualInstance3D", true, false):
		vi.layers |= SeaWorld.WINDOW_LAYER


## Rota reta [a, b] na superfície ao longo da pista (a `lateral` m da linha central, de `length` m),
## num trecho aberto ou em qualquer lugar; [] se não achar uma em que o casco (`draft` m) passe livre.
func _near_route(track: RaceTrack, rng: RandomNumberGenerator, draft: float, lateral: Vector2, length: Vector2, open_only: bool) -> Array:
	var p := track.path
	var water := track.layout.water_level
	for t in 40:
		var s := SeaCanyon.random_open_s(track, rng) if open_only else rng.randf() * p.length
		var i := p.index_at(s)
		var lat := rng.randf_range(lateral.x, lateral.y)
		if open_only and rng.randf() < 0.5:
			lat = -lat
		var c := p.frame_at(s, lat, 0.0).origin
		c.y = water
		var dir := p.tangents[i].rotated(Vector3.UP, rng.randf_range(-0.25, 0.25))
		dir.y = 0.0
		dir = dir.normalized()
		var half := rng.randf_range(length.x, length.y) * 0.5
		var a := c - dir * half
		var b := c + dir * half
		if _clear(track, a, b, draft):
			return [a, b]
	return []


## O casco passa livre de a até b: água funda o bastante (sem rocha, cânion ou montanha embaixo), sem o
## tubo perto da superfície e longe da ponte do trecho emerso.
func _clear(track: RaceTrack, a: Vector3, b: Vector3, draft: float) -> bool:
	var p := track.path
	var water := track.layout.water_level
	for k in 17:
		var q := a.lerp(b, k / 16.0)
		if SeaFloor.ground(track, q.x, q.z) > water - draft - 1.5:
			return false
		var keel := Vector3(q.x, water - draft, q.z)
		if SeaTube.blocked(track, keel, 1.5) or SeaCanyon.in_rock(track, keel, 1.0):
			return false
		var pr := p.project(q, false, false)
		if pr.y != INF:
			var i := p.index_at(pr.x)
			var side := 1 if pr.y > 0.0 else -1
			if p.points[i].y > water - 3.0 and absf(pr.y) < SeaTube.clearance(track, i, side) + 6.0:
				return false
	return true


## Esteira atrás da popa (o barco aponta para +X): faixa do meio e os dois braços em V, sumindo.
func _wake(boat: Node3D, length: float) -> void:
	var mb := MeshBuilder.new()
	var stern := -length * 0.5
	var long := length * 4.0
	var segs := 10
	for arm: float in [0.0, 1.0, -1.0]:
		for k in segs:
			var u0 := float(k) / segs
			var u1 := float(k + 1) / segs
			var w0 := length * (0.08 + u0 * (0.25 if arm == 0.0 else 0.12))
			var w1 := length * (0.08 + u1 * (0.25 if arm == 0.0 else 0.12))
			var spread := 0.3 * arm
			var a := Vector3(stern - u0 * long, 0.06, u0 * long * spread)
			var b := Vector3(stern - u1 * long, 0.06, u1 * long * spread)
			var alpha := Color(1, 1, 1, (1.0 - u0) * (0.9 if arm == 0.0 else 0.6))
			mb.quad(a + Vector3(0, 0, -w0 * 0.5), b + Vector3(0, 0, -w1 * 0.5), b + Vector3(0, 0, w1 * 0.5), a + Vector3(0, 0, w0 * 0.5),
				alpha, Vector3.UP, Vector2(-u0 * long, 0), Vector2(-u1 * long, 0), Vector2(-u1 * long, 1), Vector2(-u0 * long, 1))
	var wake := MeshInstance3D.new()
	wake.name = "Wake"
	wake.mesh = mb.commit(null, PoseidonGate.water_material(2))
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	boat.add_child(wake)


func _process(delta: float) -> void:
	for b: Array in _boats:
		b[4] = fposmod(float(b[4]) + delta * float(b[3]) / float(b[5]), 2.0)
		var t: float = b[4]
		var forward := t < 1.0
		var u := t if forward else 2.0 - t
		var a: Vector3 = b[1]
		var c: Vector3 = b[2]
		var dir := (c - a).normalized() * (1.0 if forward else -1.0)
		var node: Node3D = b[0]
		node.global_transform = Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), a.lerp(c, u))
