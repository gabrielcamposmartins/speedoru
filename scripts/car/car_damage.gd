class_name CarDamage
extends Node
## Dano e destruição do carro.
##
## Peças com resistência própria (asa dianteira esquerda/direita, bico, asa traseira, sidepods,
## retrovisores, cobertura do motor, assoalho, suspensão de cada canto e o motor). As malhas que
## formam cada peça são copiadas (e as de dois lados divididas ao meio) para poderem ser amassadas
## sem afetar os outros carros.
##
## Cada batida (impulso de contato do corpo, lido em F1Car._integrate_forces):
##  * tira resistência das peças perto do ponto de impacto (ponderado pela distância e fragilidade);
##  * amassa a malha em volta do ponto (vértices empurrados na direção do impacto);
##  * peças muito danificadas ficam soltas (caídas e balançando com o vento);
##  * com resistência zero a peça se solta e vira um RigidBody3D na pista (o bico leva a asa junto;
##    a suspensão quebrada solta a roda e o canto do carro arrasta no chão);
##  * faíscas, fragmentos de fibra de carbono e, com o motor ferido, fumaça.
## Os efeitos na física vão para o F1Car: downforce dianteira/traseira, arrasto, potência e, por
## roda, aderência, convergência (carro puxando para um lado) e roda quebrada.
## F1Car.repair() reconstrói o carro e zera tudo.
## No servidor dedicado (que não desenha) as malhas não são copiadas: a zona de cada peça sai da
## caixa da malha original (metade dela nas peças de dois lados) e a resistência funciona igual;
## o amassado e os destroços com a malha são coisa dos clientes. Copiar as malhas triângulo a
## triângulo custava ~60 ms por carro na largada, com a thread das outras salas parada.

signal part_damaged(piece: String, health: float)
signal part_detached(piece: String)
## Uma batida aplicada (servidor → clientes: amassado, faíscas e a resistência de cada peça).
signal hit_applied(local: Vector3, dir: Vector3, severity: float)

## Impulso (N·s) abaixo do qual o contato não causa dano (toques, raspadas leves).
@export var impulse_threshold := 550.0
## Impulso que tira 100% de uma peça de fragilidade 1 no ponto de impacto.
@export var impulse_full_damage := 7500.0
## Multiplicador geral (0 = indestrutível).
@export_range(0.0, 3.0) var damage_scale := 1.0
## Máximo de destroços na pista (os mais antigos somem).
@export var max_debris := 40

## nome -> [slot, lado (+1 esq., -1 dir., 0 inteiro), fragilidade, massa (kg), solta?]
const PIECES := {
	"front_wing_L": ["front_wing", 1, 1.4, 3.5, true],
	"front_wing_R": ["front_wing", -1, 1.4, 3.5, true],
	"nose": ["nose", 0, 0.9, 5.0, true],
	"rear_wing": ["rear_wing", 0, 0.9, 6.0, true],
	"sidepod_L": ["sidepods", 1, 0.6, 6.0, true],
	"sidepod_R": ["sidepods", -1, 0.6, 6.0, true],
	"mirror_L": ["mirrors", 1, 1.6, 1.0, true],
	"mirror_R": ["mirrors", -1, 1.6, 1.0, true],
	"engine_cover": ["engine_cover", 0, 0.45, 5.0, true],
	"floor": ["floor", 0, 0.35, 0.0, false],
	"chassis": ["chassis", 0, 0.0, 0.0, false],
	"suspension_FL": ["suspension_front", 1, 0.8, 3.0, true],
	"suspension_FR": ["suspension_front", -1, 0.8, 3.0, true],
	"suspension_RL": ["suspension_rear", 1, 0.8, 3.0, true],
	"suspension_RR": ["suspension_rear", -1, 0.8, 3.0, true],
}
## Zona do motor (sem malha própria): centro e tamanho no espaço do carro.
const ENGINE_ZONE := AABB(Vector3(-0.32, 0.25, -2.0), Vector3(0.64, 0.6, 1.3))
const DEBRIS_LAYER := 1 << 3
const WHEEL_DEBRIS_MASS := 12.0

var car: F1Car
## Resistência por peça (1 = intacta, 0 = destruída); "engine" incluído.
var health := {}
var detached := {}
var scrape_level := 0.0

static var _debris: Array[Node3D] = []

var _pieces := {}  # nome -> Piece
var _contacts: Array = []
var _sparks: GPUParticles3D
var _smoke: CPUParticles3D
var _wheel_defaults: Array = []
var _signature := []
var _time := 0.0
var _prev_velocity := Vector3.ZERO
var _prev_position := Vector3.ZERO


class Piece:
	var name: String
	var side := 0
	var fragility := 1.0
	var mass := 1.0
	var detachable := true
	## Cópias editáveis das malhas: [MeshInstance3D, rest Transform3D, Array de PackedVector3Array por superfície]
	var copies: Array = []
	## Nós originais carregados junto ao soltar (duplicados): DRS, vidros dos retrovisores, rodas.
	var extras: Array[Node3D] = []
	var zone := AABB()
	var pivot := Vector3.ZERO
	var axis := Vector3.RIGHT
	var phase := 0.0
	var wheel := -1


func _ready() -> void:
	car = get_parent() as F1Car
	if car == null or Engine.is_editor_hint():
		return
	car.parts_ready.connect(_setup)
	_create_effects()


# ---------------------------------------------------------------------------
# Montagem
# ---------------------------------------------------------------------------
func _setup() -> void:
	# parts_ready também dispara quando só a pintura muda: se as peças são as mesmas instâncias,
	# o dano (e as malhas amassadas) continua como está.
	var signature := []
	for slot in CarPartCatalog.SLOTS:
		var part := car.assembly.get_part_node(slot)
		signature.append(part.get_instance_id() if part else 0)
	if signature == _signature and not _pieces.is_empty():
		return
	_signature = signature
	_discard_copies()
	_pieces.clear()
	health.clear()
	detached.clear()
	var inv := car.global_transform.affine_inverse()
	var wheels := car.get_wheels()
	if _wheel_defaults.is_empty():
		for w in wheels:
			_wheel_defaults.append([w.wheel_radius, w.suspension_stiffness])
	for i in wheels.size():
		wheels[i].wheel_radius = _wheel_defaults[i][0]
		wheels[i].suspension_stiffness = _wheel_defaults[i][1]
	for piece_name: String in PIECES:
		var info: Array = PIECES[piece_name]
		var part := car.assembly.get_part_node(info[0])
		if part == null:
			continue
		var p := Piece.new()
		p.name = piece_name
		p.side = info[1]
		p.fragility = info[2]
		p.mass = info[3]
		p.detachable = info[4]
		p.phase = randf() * TAU
		var first := true
		var lite := NetProtocol.is_server_process()
		for node in part.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if not (mi.mesh is ArrayMesh) or mi.name.begins_with("Damaged_"):
				continue
			if mi.name.begins_with("DRSFlap") or mi.name.begins_with("MirrorGlass"):
				# Animados/usados por outros sistemas: só vão junto quando a peça solta
				if p.side == 0 or (mi.name.ends_with("L") == (p.side > 0)):
					p.extras.append(mi)
				continue
			if lite:
				var box := _half_aabb(inv * mi.global_transform * mi.get_aabb(), p.side)
				if box.size != Vector3.ZERO:
					p.zone = box if first else p.zone.merge(box)
					first = false
				continue
			var copy := _copy_mesh(mi, p.side, inv)
			if copy.is_empty():
				continue
			p.copies.append(copy)
			var ab: AABB = inv * copy[0].global_transform * (copy[0] as MeshInstance3D).get_aabb()
			p.zone = ab if first else p.zone.merge(ab)
			first = false
		if first:
			continue
		# Suspensão: a zona inclui a roda daquele canto (é ela que bate primeiro)
		if piece_name.begins_with("suspension"):
			var front: bool = String(piece_name)[-2] == "F"
			for wi in wheels.size():
				var w := wheels[wi]
				if w.use_as_steering == front and signf(w.position.x) == p.side:
					p.wheel = wi
					p.zone = p.zone.merge(AABB(w.position - Vector3(0.2, 0.36, 0.36), Vector3(0.4, 0.72, 0.72)))
					for child in w.get_children():
						if child is Node3D and child.name.begins_with("Visual"):
							p.extras.append(child)
		# Articulação: ponto da zona mais perto do centro do carro (onde a peça está presa)
		var c := p.zone.get_center()
		p.pivot = Vector3(clampf(0.0, p.zone.position.x, p.zone.end.x), c.y, clampf(0.0, p.zone.position.z, p.zone.end.z))
		p.axis = Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized()
		_pieces[piece_name] = p
		health[piece_name] = 1.0
	health["engine"] = 1.0
	_apply_to_car()


## Metade de uma caixa (espaço do carro) do lado `side` (+1 esquerda, -1 direita, 0 inteira).
static func _half_aabb(box: AABB, side: int) -> AABB:
	if side == 0:
		return box
	var lo := box.position
	var hi := box.end
	if side > 0:
		lo.x = maxf(lo.x, 0.0)
	else:
		hi.x = minf(hi.x, 0.0)
	if hi.x <= lo.x:
		return AABB()
	return AABB(lo, hi - lo)


## Desfaz as cópias de uma montagem anterior (troca de peça na garagem): as originais voltam a
## aparecer e as novas cópias são criadas a partir delas.
func _discard_copies() -> void:
	for piece_name in _pieces:
		var p: Piece = _pieces[piece_name]
		if detached.has(piece_name):
			continue
		for copy in p.copies:
			var mi: MeshInstance3D = copy[0]
			if is_instance_valid(mi):
				mi.queue_free()
				mi.get_parent().remove_child(mi)
	for slot in CarPartCatalog.SLOTS:
		var part := car.assembly.get_part_node(slot)
		if part == null:
			continue
		for node in part.find_children("*", "MeshInstance3D", true, false):
			if not node.name.begins_with("Damaged_"):
				(node as MeshInstance3D).visible = true


## Copia (e, com side != 0, corta ao meio) a malha de `mi` numa MeshInstance3D irmã; esconde a original.
func _copy_mesh(mi: MeshInstance3D, side: int, inv: Transform3D) -> Array:
	var src := mi.mesh as ArrayMesh
	var to_car := inv * mi.global_transform
	var mesh := ArrayMesh.new()
	var verts_per_surface: Array = []
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv = arrays[Mesh.ARRAY_TEX_UV]
		var idx = arrays[Mesh.ARRAY_INDEX]
		var out_v := PackedVector3Array()
		var out_n := PackedVector3Array()
		var out_uv := PackedVector2Array()
		var tri_count: int = (idx.size() if idx != null else v.size()) / 3
		for t in tri_count:
			var ids := [t * 3, t * 3 + 1, t * 3 + 2]
			if idx != null:
				ids = [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]]
			if side != 0:
				var cx: float = (to_car * ((v[ids[0]] + v[ids[1]] + v[ids[2]]) / 3.0)).x
				if cx * side < 0.0:
					continue
			for k in ids:
				out_v.append(v[k])
				out_n.append(n[k])
				if uv != null:
					out_uv.append(uv[k])
		if out_v.is_empty():
			continue
		var new_arrays := []
		new_arrays.resize(Mesh.ARRAY_MAX)
		new_arrays[Mesh.ARRAY_VERTEX] = out_v
		new_arrays[Mesh.ARRAY_NORMAL] = out_n
		if not out_uv.is_empty():
			new_arrays[Mesh.ARRAY_TEX_UV] = out_uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mi.get_active_material(s))
		verts_per_surface.append(out_v)
	if mesh.get_surface_count() == 0:
		return []
	var copy := MeshInstance3D.new()
	copy.name = "Damaged_" + mi.name + ("" if side == 0 else ("_L" if side > 0 else "_R"))
	copy.mesh = mesh
	copy.layers = mi.layers
	mi.get_parent().add_child(copy)
	copy.transform = mi.transform
	# A original fica escondida (as metades de peças divididas leem dela)
	mi.visible = false
	return [copy, copy.transform, verts_per_surface]


# ---------------------------------------------------------------------------
# Contatos e dano
# ---------------------------------------------------------------------------
## Chamado por F1Car._integrate_forces para cada contato do corpo do carro.
func add_contact(world_pos: Vector3, impulse: Vector3, normal: Vector3, collider: Object, rel_speed: float) -> void:
	_contacts.append([world_pos, impulse, normal, collider, rel_speed])


func _physics_process(delta: float) -> void:
	if car == null:
		return
	var scrape := 0.0
	var inv := car.global_transform.affine_inverse()
	# O impulso reportado pela física às vezes vem zerado no passo da batida: estima também pela
	# variação de velocidade do carro na direção da normal do contato (Δv · n × massa).
	var dv := car.linear_velocity - _prev_velocity
	var teleported := car.global_position.distance_to(_prev_position) > 5.0 		or Engine.get_physics_frames() - car.reset_frame < 3
	_prev_velocity = car.linear_velocity
	_prev_position = car.global_position
	var hits := {}  # agrupa contatos próximos (uma batida = um golpe)
	for c in _contacts:
		var pos: Vector3 = c[0]
		var impulse: Vector3 = c[1]
		var normal: Vector3 = c[2]
		var surface := TrackSurface.of_body(c[3])
		var ground := normal.y > 0.6 and surface != TrackSurface.Type.BARRIER
		var slide: float = c[4]
		# Raspando (barreira ou assoalho no chão) em velocidade: faíscas e som
		if slide > 4.0:
			scrape = maxf(scrape, clampf(slide / 30.0, 0.15, 1.0) * (0.5 if ground else 1.0))
			if randf() < 0.5:
				_spark_burst(pos, normal, 2 if ground else 4, slide)
		if teleported:
			continue
		var j := maxf(impulse.length(), car.mass * maxf(dv.dot(normal), 0.0))
		var threshold := impulse_threshold * (5.0 if ground else 1.0)
		if j > threshold and damage_scale > 0.0:
			var key := Vector3i((inv * pos / 0.5).round())
			if not hits.has(key) or hits[key][2] < j:
				hits[key] = [pos, normal, j, threshold]
	# Contatos do mesmo golpe dividem o impulso
	for key in hits:
		var h: Array = hits[key]
		var severity: float = (float(h[2]) - float(h[3])) / impulse_full_damage * damage_scale / sqrt(float(hits.size()))
		_hit(inv * (h[0] as Vector3), inv.basis * (-(h[1] as Vector3)), severity, h[0], h[1])
	_contacts.clear()
	scrape_level = move_toward(scrape_level, scrape, delta * 6.0)
	var audio := car.get_node_or_null("Audio") as CarAudio
	if audio:
		audio.scrape_level = scrape_level


## Batida vinda do servidor (multiplayer): amassa e solta faíscas como a original e copia a
## resistência das peças calculada lá (as peças arrancadas chegam pelo evento "detach").
func remote_hit(local: Vector3, dir: Vector3, severity: float, new_health: Dictionary) -> void:
	if car == null:
		return
	_hit(local, dir, severity, car.global_transform * local, car.global_basis * -dir, true)
	for piece_name in new_health:
		if health.has(piece_name) and not detached.has(piece_name):
			health[piece_name] = clampf(float(new_health[piece_name]), 0.0, 1.0)
			part_damaged.emit(piece_name, health[piece_name])
	_apply_to_car()


## Impacto no ponto `local` (espaço do carro) empurrando na direção `dir` (para dentro do carro).
## `remote`: só o visual (a resistência vem do servidor).
func _hit(local: Vector3, dir: Vector3, severity: float, world_pos: Vector3, normal: Vector3, remote := false) -> void:
	_spark_burst(world_pos, normal, int(6 + severity * 40), 12.0 + severity * 20.0)
	if severity > 0.25:
		_shard_burst(world_pos, normal, int(4 + severity * 20))
	var audio := car.get_node_or_null("Audio") as CarAudio
	var any_detached := false
	for piece_name in _pieces.keys():
		var p: Piece = _pieces[piece_name]
		if detached.has(piece_name):
			continue
		var d := _distance_to_aabb(local, p.zone.grow(0.05))
		var w := clampf(1.0 - d / 1.0, 0.0, 1.0)
		# Batidas fortes propagam o choque pela estrutura (peças vizinhas também sofrem)
		if severity > 0.8:
			w += clampf(1.0 - d / 2.2, 0.0, 1.0) * 0.3
		if w <= 0.0:
			continue
		var dmg := severity * w * p.fragility
		if p.copies.size() > 0 and severity * w > 0.02:
			_dent(p, local, dir, clampf(0.025 + severity * 0.09, 0.0, 0.2) * w, 0.22 + 0.3 * minf(severity, 1.0))
		if dmg <= 0.0 or remote:
			continue
		health[piece_name] = maxf(float(health[piece_name]) - dmg, 0.0)
		part_damaged.emit(piece_name, health[piece_name])
		if health[piece_name] <= 0.0 and p.detachable:
			_detach(piece_name, dir * -1.0, severity)
			any_detached = true
	if remote:
		return
	var dw := clampf(1.0 - _distance_to_aabb(local, ENGINE_ZONE) / 0.8, 0.0, 1.0)
	if dw > 0.0:
		health["engine"] = maxf(float(health["engine"]) - severity * dw * 0.35, 0.0)
	if any_detached and audio:
		audio.play_shot("crack_%d" % randi_range(1, 2), local, 2.0, randf_range(0.9, 1.1))
	_apply_to_car()
	hit_applied.emit(local, dir, severity)


## Empurra os vértices perto do impacto (amassado com queda suave).
func _dent(p: Piece, local: Vector3, dir: Vector3, depth: float, radius: float) -> void:
	var to_world := car.global_transform
	for copy in p.copies:
		var mi: MeshInstance3D = copy[0]
		var to_mesh := (to_world.affine_inverse() * mi.global_transform).affine_inverse()
		var center := to_mesh * local
		var push := (to_mesh.basis * dir).normalized() * depth
		var mesh := mi.mesh as ArrayMesh
		var surfaces: Array = copy[2]
		var changed := false
		for s in surfaces.size():
			var v: PackedVector3Array = surfaces[s]
			for k in v.size():
				var dist := v[k].distance_to(center)
				if dist < radius:
					var f := 1.0 - dist / radius
					v[k] += push * f * f * randf_range(0.7, 1.15)
					changed = true
			surfaces[s] = v
		if changed:
			_rebuild_mesh(mesh, surfaces)


static func _rebuild_mesh(mesh: ArrayMesh, surfaces: Array) -> void:
	var data := []
	for s in mesh.get_surface_count():
		data.append([mesh.surface_get_arrays(s), mesh.surface_get_material(s)])
	mesh.clear_surfaces()
	for s in data.size():
		var arrays: Array = data[s][0]
		arrays[Mesh.ARRAY_VERTEX] = surfaces[s]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(s, data[s][1])


static func _distance_to_aabb(p: Vector3, box: AABB) -> float:
	var q := p.clamp(box.position, box.end)
	return p.distance_to(q)


# ---------------------------------------------------------------------------
# Peças se soltando
# ---------------------------------------------------------------------------
## Rede (cliente): arranca a peça que o servidor mandou (só visual).
func detach_piece(piece_name: String) -> void:
	if piece_name != "" and car:
		_detach(piece_name, car.global_basis.x * (1.0 if randf() < 0.5 else -1.0) + Vector3.UP * 0.5, 0.6)


func _detach(piece_name: String, outward: Vector3, severity: float) -> void:
	var p: Piece = _pieces.get(piece_name)
	if p == null or detached.has(piece_name):
		return
	detached[piece_name] = true
	health[piece_name] = 0.0
	# O bico leva a asa dianteira junto
	if piece_name == "nose":
		for wing in ["front_wing_L", "front_wing_R"]:
			_detach(wing, outward, severity)
	var scene := car.get_parent()
	var body := RigidBody3D.new()
	body.name = "Debris_" + piece_name
	body.collision_layer = DEBRIS_LAYER
	body.collision_mask = 1 | 2 | DEBRIS_LAYER
	var mat := PhysicsMaterial.new()
	mat.friction = 0.7
	mat.bounce = 0.25
	body.physics_material_override = mat
	body.mass = maxf(p.mass, 0.5)
	scene.add_child(body)
	body.global_transform = car.global_transform * Transform3D(Basis(), p.zone.get_center())
	var points := PackedVector3Array()
	for copy in p.copies:
		var mi: MeshInstance3D = copy[0]
		var xf := mi.global_transform
		mi.get_parent().remove_child(mi)
		body.add_child(mi)
		mi.global_transform = xf
		var local_xf := body.global_transform.affine_inverse() * xf
		for s in (copy[2] as Array):
			for v in (s as PackedVector3Array):
				points.append(local_xf * v)
	if p.copies.is_empty():
		# Servidor (sem cópias das malhas): o casco do destroço é a caixa da peça
		var half := p.zone.size * 0.5
		for k in 8:
			points.append(Vector3(half.x * (1 if k & 1 else -1), half.y * (1 if k & 2 else -1), half.z * (1 if k & 4 else -1)))
	for extra in p.extras:
		if not is_instance_valid(extra):
			continue
		var dup := extra.duplicate() as Node3D
		body.add_child(dup)
		dup.global_transform = extra.global_transform
		extra.visible = false
		if p.wheel >= 0 and extra.name.begins_with("Visual"):
			body.mass += WHEEL_DEBRIS_MASS * 0.5
			var wheel_xf := body.global_transform.affine_inverse() * extra.global_transform
			for k in 12:
				var a := TAU * k / 12.0
				for side in [-0.18, 0.18]:
					points.append(wheel_xf * Vector3(side, sin(a) * 0.36, cos(a) * 0.36))
	var shape := ConvexPolygonShape3D.new()
	shape.points = _hull_sample(points)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var r := car.global_transform.basis * (p.zone.get_center())
	body.linear_velocity = car.linear_velocity + car.angular_velocity.cross(r) \
		+ (car.global_transform.basis * outward).normalized() * randf_range(2.0, 5.0) * clampf(severity, 0.5, 2.0) \
		+ Vector3.UP * randf_range(1.0, 4.0)
	body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * randf_range(4.0, 14.0)
	_debris.append(body)
	while _debris.size() > max_debris:
		var old: Node3D = _debris.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	if p.wheel >= 0:
		var w := car.get_wheels()[p.wheel]
		w.wheel_radius = 0.12
		w.suspension_stiffness = 20.0
	part_detached.emit(piece_name)


## Até ~64 pontos espalhados (o casco convexo fica leve para a física).
static func _hull_sample(points: PackedVector3Array) -> PackedVector3Array:
	if points.size() <= 64:
		return points
	var out := PackedVector3Array()
	var step := float(points.size()) / 64.0
	for k in 64:
		out.append(points[int(k * step)])
	# Garante os extremos
	var box := AABB(points[0], Vector3.ZERO)
	for v in points:
		box = box.expand(v)
	for k in 8:
		out.append(box.get_endpoint(k).lerp(box.get_center(), 0.15))
	return out


# ---------------------------------------------------------------------------
# Efeitos na física e no visual
# ---------------------------------------------------------------------------
func _apply_to_car() -> void:
	var eff := func(piece_name: String) -> float:
		if detached.has(piece_name) or not health.has(piece_name):
			return 0.0 if detached.has(piece_name) else 1.0
		return 0.55 + 0.45 * float(health[piece_name])
	var front_wing: float = (eff.call("front_wing_L") + eff.call("front_wing_R")) * 0.5
	var rear_wing: float = eff.call("rear_wing")
	var floor_h: float = eff.call("floor")
	car.damage_front_downforce = (0.4 + 0.6 * front_wing) * (0.85 + 0.15 * floor_h)
	car.damage_rear_downforce = (0.35 + 0.65 * rear_wing) * (0.85 + 0.15 * floor_h)
	var drag := 0.0
	for piece_name in ["sidepod_L", "sidepod_R", "engine_cover", "nose", "front_wing_L", "front_wing_R"]:
		if health.has(piece_name) and not detached.has(piece_name):
			drag += (1.0 - float(health[piece_name])) * 0.06
	if detached.has("rear_wing"):
		drag -= 0.35
	car.damage_drag = drag
	car.damage_power = 0.4 + 0.6 * float(health.get("engine", 1.0))
	for piece_name in ["suspension_FL", "suspension_FR", "suspension_RL", "suspension_RR"]:
		var p: Piece = _pieces.get(piece_name)
		if p == null or p.wheel < 0:
			continue
		var h := float(health.get(piece_name, 1.0))
		car.wheel_broken[p.wheel] = detached.has(piece_name)
		car.wheel_grip[p.wheel] = 0.8 + 0.2 * h
		# Braço torto: a roda aponta para um lado (o carro puxa)
		car.wheel_toe[p.wheel] = (1.0 - h) * 0.05 * signf(p.axis.x)
	_smoke.emitting = float(health.get("engine", 1.0)) < 0.6


func _process(delta: float) -> void:
	if car == null:
		return
	_time += delta
	var speed := car.linear_velocity.length()
	# Peças soltas caem e balançam com o vento
	for piece_name in _pieces:
		if detached.has(piece_name):
			continue
		var h := float(health[piece_name])
		if h > 0.6:
			continue
		var p: Piece = _pieces[piece_name]
		var loose := (0.6 - h) / 0.6
		var droop := loose * 0.18 + sin(_time * (18.0 + p.phase) + p.phase) * loose * minf(speed / 60.0, 1.0) * 0.04
		var rot := Transform3D(Basis(p.axis, droop), Vector3.ZERO)
		for copy in p.copies:
			var mi: MeshInstance3D = copy[0]
			var rest: Transform3D = copy[1]
			var parent_inv := (car.global_transform.affine_inverse() * (mi.get_parent() as Node3D).global_transform).affine_inverse()
			# Gira em volta do ponto de fixação (espaço do carro) e volta para o espaço do pai
			var around := Transform3D(Basis(), p.pivot) * rot * Transform3D(Basis(), -p.pivot)
			mi.transform = parent_inv * around * parent_inv.affine_inverse() * rest


func _create_effects() -> void:
	_sparks = GPUParticles3D.new()
	_sparks.name = "Sparks"
	var spark := BoxMesh.new()
	spark.size = Vector3(0.018, 0.14, 0.018)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.15)
	mat.emission_energy_multiplier = 6.0
	spark.material = mat
	_sparks.draw_pass_1 = spark
	var process := ParticleProcessMaterial.new()
	process.gravity = Vector3(0, -9.8, 0)
	process.particle_flag_align_y = true
	process.damping_min = 2.0
	process.damping_max = 4.0
	var shrink := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	shrink.curve = curve
	process.scale_curve = shrink
	_sparks.process_material = process
	_sparks.amount = 400
	_sparks.lifetime = 0.5
	_sparks.local_coords = false
	_sparks.amount_ratio = 0.0
	_sparks.emitting = true
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sparks.visibility_aabb = AABB(Vector3(-5000, -100, -5000), Vector3(10000, 400, 10000))
	add_child(_sparks)
	_smoke = CPUParticles3D.new()
	_smoke.name = "EngineSmoke"
	var puff := SphereMesh.new()
	puff.radius = 0.3
	puff.height = 0.6
	puff.radial_segments = 8
	puff.rings = 4
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	puff.material = smat
	_smoke.mesh = puff
	_smoke.amount = 50
	_smoke.lifetime = 1.6
	_smoke.local_coords = false
	_smoke.direction = Vector3.UP
	_smoke.spread = 25.0
	_smoke.initial_velocity_min = 1.0
	_smoke.initial_velocity_max = 2.5
	_smoke.gravity = Vector3(0, 1.2, 0)
	_smoke.damping_min = 0.8
	_smoke.damping_max = 1.5
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 3.5))
	_smoke.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.25, 0.25, 0.27, 0.65))
	fade.set_color(1, Color(0.5, 0.5, 0.52, 0.0))
	_smoke.color_ramp = fade
	_smoke.emitting = false
	_smoke.position = Vector3(0, 0.95, -1.5)
	car.add_child.call_deferred(_smoke)


## Faíscas (emitidas uma a uma, com velocidade espalhada em volta da normal + arrasto do carro).
func _spark_burst(pos: Vector3, normal: Vector3, count: int, speed: float) -> void:
	var base := car.linear_velocity * 0.6
	for k in count:
		var dir := (normal + Vector3(randf_range(-1, 1), randf_range(-0.2, 1.0), randf_range(-1, 1))).normalized()
		var v := base + dir * randf_range(2.0, 4.0 + speed * 0.25)
		_sparks.emit_particle(Transform3D(Basis(), pos), v, Color.WHITE, Color.WHITE,
			GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY)


## Lascas de fibra de carbono (pedacinhos pretos que voam e caem).
func _shard_burst(pos: Vector3, normal: Vector3, count: int) -> void:
	var shards := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 0.008, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.14)
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mesh.material = mat
	shards.mesh = mesh
	shards.amount = maxi(count, 2)
	shards.lifetime = 1.4
	shards.one_shot = true
	shards.explosiveness = 0.95
	shards.local_coords = false
	shards.direction = normal + Vector3.UP * 0.6
	shards.spread = 70.0
	shards.initial_velocity_min = 3.0
	shards.initial_velocity_max = 9.0
	shards.angular_velocity_min = -720.0
	shards.angular_velocity_max = 720.0
	shards.gravity = Vector3(0, -9.8, 0)
	shards.scale_amount_min = 0.6
	shards.scale_amount_max = 2.0
	car.get_parent().add_child(shards)
	shards.global_position = pos
	shards.emitting = true
	shards.finished.connect(shards.queue_free)


## Soma de tudo (0 = destruído, 1 = intacto) — para o HUD/telemetria.
func get_overall() -> float:
	if health.is_empty():
		return 1.0
	var total := 0.0
	for k in health:
		total += float(health[k])
	return total / health.size()
