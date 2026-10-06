@tool
class_name RaceTrack
extends Node3D
## Gera um circuito completo a partir de um TrackLayout: pista com zebras e faixas, caixas de
## brita, barreiras com alambrado, boxes, arquibancadas com público, anúncios, postes,
## pórticos, placas e árvores. Também cria o chão (grama) e as colisões com tipo de piso
## (TrackSurface), lidas pelo modelo de pneu do F1Car.
##
## Tudo é gerado em tempo de execução (e no editor, se build_in_editor) dentro do filho
## "Generated", que não é salvo na cena. Edite o layout (.tres) para mudar o circuito.

signal built
## Falso enquanto a pista está sendo gerada (a geração em etapas leva vários quadros).
var is_built := false

enum Barrier { ARMCO, CONCRETE, NONE }

@export var layout: TrackLayout:
	set(value):
		layout = value
		_queue_rebuild()
@export var build_in_editor := true:
	set(value):
		build_in_editor = value
		_queue_rebuild()
@export_tool_button("Reconstruir pista", "Reload") var rebuild_action := rebuild

@export_group("Cenário")
@export var tree_count := 24000
@export var tree_seed := 11
## Fração dos lugares ocupados nas arquibancadas.
@export_range(0.0, 1.0) var crowd_density := 0.97
## Distância máxima em que o público é desenhado (além disso só a cor das arquibancadas).
@export var crowd_visibility := 520.0
@export var lamp_energy := 2.5
@export var terrain_seed := 7
## Grama 3D em volta da câmera (raio em m; 0 desliga).
@export var grass_radius := 52.0
## Pinheiros de preenchimento (modelo de agulhas) em fileiras logo atrás das cercas.
@export var pines := true
## Rochas, vilarejos, turbinas, balões e dirigível.
@export var scenery := true

var path: TrackPath
## Perfil por amostra da pista; índice 0 = lado esquerdo, 1 = lado direito.
var kerb: Array[PackedFloat32Array] = []
var gravel: Array[PackedFloat32Array] = []
## Distância da borda da pista até a face da barreira.
var barrier: Array[PackedFloat32Array] = []
var barrier_kind: Array[PackedInt32Array] = []
## Largura da área dos boxes a partir da borda (só do lado dos boxes).
var pit_width := PackedFloat32Array()
## Áreas sem árvores (polígonos no plano XZ).
var footprints: Array[PackedVector2Array] = []
var start_lights: StartLights
## Servidor dedicado: só gera o que tem colisão (pista, barreiras, boxes, objetos, terreno),
## em etapas de um quadro cada (sem pausar as outras salas).
static var server_mode := false
const SERVER_SKIP := ["arquibancadas", "árvores", "folhas", "pinheiros", "cenário", "grama"]

var terrain: TrackTerrain
var leaves: TrackLeaves

var _root: Node3D
var _rebuild_queued := false

const PIT_WALL_STRIP := 3.0


func _ready() -> void:
	if Engine.is_editor_hint() and not build_in_editor:
		return
	# Com a tela de carregamento ativa gera em etapas, redesenhando a barra entre elas
	rebuild(not Engine.is_editor_hint() and LoadingScreen.is_loading())


func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	(func():
		_rebuild_queued = false
		if not Engine.is_editor_hint() or build_in_editor:
			rebuild()
		elif _root:
			_root.queue_free()
			_root = null).call_deferred()


## Gera a pista inteira. Com [param staged] cada etapa espera um quadro ser desenhado antes
## (a tela de carregamento mostra a etapa e a porcentagem) e a árvore fica pausada até o fim
## para os carros não caírem antes de o chão existir.
func rebuild(staged := false) -> void:
	is_built = false
	if _root:
		remove_child(_root)
		_root.queue_free()
		_root = null
	if layout == null or layout.centerline.is_empty():
		return
	var t0 := Time.get_ticks_msec()
	path = TrackPath.from_csv(layout.centerline, 2.0, layout.width_scale, layout.min_half_width, layout.start_offset)
	if path == null:
		return
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)
	footprints.clear()
	_compute_profile()
	# [nome no log, texto na tela de carregamento, peso (≈ ms), etapa]
	var steps := [
		["chão e pista", "Asfalto e zebras", 90, func(): TrackRoad.build(self, _root)],
		["barreiras", "Barreiras e cercas", 380, func(): TrackBarriers.build(self, _root)],
		["boxes", "Boxes", 30, func(): PitComplex.build(self, _root)],
		["arquibancadas", "Arquibancadas e público", 700, func(): Grandstands.build(self, _root)],
		["objetos", "Placas, postes e bandeirolas", 90, func(): TrackProps.build(self, _root)],
		["terreno", "Terreno e montanhas", 550, func(): terrain = TrackTerrain.build(self, _root)],
		["árvores", "Árvores", 420, func(): TrackTrees.build(self, terrain, _root)],
		["folhas", "Folhagem", 700, func(): leaves = TrackLeaves.build(self, terrain, _root)],
		["pinheiros", "Pinheiros", 400, func(): _build_pines()],
		["cenário", "Cenário e céu", 200, func(): _build_scenery()],
		["grama", "Grama", 30, func(): _build_grass()],
	]
	var tree := get_tree()
	var was_paused := false
	if staged:
		was_paused = tree.paused
		tree.paused = true
	var total := 0.0
	for st in steps:
		total += st[2]
	var done := 0.0
	var timings := []
	for st in steps:
		if server_mode:
			if st[0] in SERVER_SKIP:
				continue
			await tree.process_frame
		elif staged:
			LoadingScreen.report_progress(lerpf(LoadingScreen.SCENE_SHARE, 0.95, done / total), st[1])
			await RenderingServer.frame_post_draw
		var ts := Time.get_ticks_msec()
		st[3].call()
		timings.append("%s %d ms" % [st[0], Time.get_ticks_msec() - ts])
		done += st[2]
	print("RaceTrack: %.0f m gerados em %d ms (%s)" % [path.length, Time.get_ticks_msec() - t0, ", ".join(timings)])
	if staged:
		LoadingScreen.report_progress(0.95, "Preparando")
		tree.paused = was_paused
	is_built = true
	built.emit()
	_apply_current_mood()


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------
## Posição de largada (0 = pole). O carro olha no sentido da pista.
func get_grid_transform(slot: int) -> Transform3D:
	var s := -6.0 - slot * layout.grid_spacing
	var lateral := layout.grid_lateral * (1.0 if slot % 2 == 0 else -1.0)
	return path.frame_at(s, lateral, 0.05)


## Vaga do carro em frente ao box `index` (0 .. garage_count-1).
func get_pit_box_transform(index: int) -> Transform3D:
	var s := garage_s(index)
	var lateral := pit_lateral(path.index_at(s), PIT_WALL_STRIP + layout.pit_lane_width * 0.72)
	return path.frame_at(s, lateral, 0.05)


## Centro (s) do box `index`.
func garage_s(index: int) -> float:
	return layout.garage_center_s + (index - (layout.garage_count - 1) * 0.5) * layout.garage_width


## Lateral (com sinal) de um ponto a `d` metros além da borda do lado dos boxes.
func pit_lateral(i: int, d: float) -> float:
	var side := layout.pit_side
	return side * (path.half_width(i, side) + d)


## Ponto a `d` metros além da borda da pista, do lado `side` (+1 esquerda, -1 direita).
func edge_point(i: int, side: int, d: float, y := 0.0) -> Vector3:
	return path.points[i] + path.lefts[i] * (side * (path.half_width(i, side) + d)) + Vector3.UP * y


## Distância (m) da linha central até onde termina tudo o que foi construído daquele lado
## (barreira, arquibancadas, postes, boxes e paddock). Além disso o terreno pode subir.
func structure_extent(i: int, side: int) -> float:
	var hw := path.half_width(i, side)
	var e := hw + barrier[_si(side)][i] + 3.0
	var s := path.s_at(i)
	e = maxf(e, hw + outer_distance(i, side) + TrackProps._stand_clearance(self, s, side) + 3.0)
	if layout.has_pit and side == layout.pit_side:
		var ds := fposmod(s - layout.garage_center_s + path.length * 0.5, path.length) - path.length * 0.5
		if absf(ds) < layout.pit_building_length * 0.5 + 40.0:
			e = maxf(e, hw + PIT_WALL_STRIP + layout.pit_lane_width + PitComplex.DEPTH + 75.0 + 8.0)
		elif pit_width[i] > 0.0:
			e = maxf(e, hw + pit_width[i] + 4.0)
	return e + 4.0


## Distância da borda até o lado de fora da barreira (onde começam as estruturas).
func outer_distance(i: int, side: int) -> float:
	return barrier[_si(side)][i] + 1.0


## Índices das amostras entre s0 e s1 (considera a volta).
func span_indices(s0: float, s1: float, step := 1) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := path.size()
	var i0 := path.index_at(s0)
	var count := int(round(fposmod(s1 - s0, path.length) / path.spacing))
	for k in range(0, count + 1, step):
		out.append((i0 + k) % n)
	return out


func in_span(s: float, s0: float, s1: float) -> bool:
	return fposmod(s - s0, path.length) <= fposmod(s1 - s0, path.length)


## Período do dia / ambiente (chamado pelo Daylight via grupo "mood_aware"): refletores dos
## postes e luzes dos boxes à noite (fracos no entardecer), lâmpadas mais fortes e folhas soltas.
func apply_mood(time_of_day: int, biome: int) -> void:
	var night := DaylightPresets.night_amount(time_of_day)
	for light in get_tree().get_nodes_in_group("night_lights"):
		if not is_ancestor_of(light):
			continue
		light.visible = night > 0.05
		light.light_energy = float(light.get_meta("base_energy", 8.0)) * night
	var lamp := TrackMaterials.lamp(lamp_energy) as StandardMaterial3D
	lamp.emission_energy_multiplier = lamp_energy * (1.0 + 5.0 * night)
	if leaves:
		leaves.apply_mood(time_of_day, biome)


func _apply_current_mood() -> void:
	if not is_inside_tree():
		return
	if not is_in_group("mood_aware"):
		add_to_group("mood_aware")
	var daylight := get_tree().get_first_node_in_group("daylight") as Daylight
	if daylight:
		apply_mood(daylight.time_of_day, daylight.biome)
	else:
		apply_mood(DaylightPresets.TimeOfDay.DAY, DaylightPresets.Biome.SUMMER)


func _build_pines() -> void:
	if pines and terrain:
		TrackPines.build(self, terrain, _root)


func _build_scenery() -> void:
	if scenery and terrain:
		TrackScenery.build(self, terrain, _root)


## Grama 3D: máscara feita com as malhas de piso (asfalto, zebras, brita, boxes).
func _build_grass() -> void:
	if grass_radius <= 0.0 or terrain == null:
		return
	var surfaces: Array[MeshInstance3D] = []
	for body in _root.find_children("*", "StaticBody3D", true, false):
		var type := TrackSurface.of_body(body)
		if body.has_meta("surface") and type in [TrackSurface.Type.ASPHALT, TrackSurface.Type.KERB, TrackSurface.Type.GRAVEL]:
			for mi in body.find_children("*", "MeshInstance3D", false, false):
				surfaces.append(mi)
	var grass := GrassField.new()
	grass.radius = grass_radius
	_root.add_child(grass)
	grass.setup(self, terrain, surfaces)


static func _si(side: int) -> int:
	return 0 if side > 0 else 1


# ---------------------------------------------------------------------------
# Perfil lateral: zebras, brita, barreiras e boxes ao longo da pista
# ---------------------------------------------------------------------------
func _compute_profile() -> void:
	var n := path.size()
	kerb = [PackedFloat32Array(), PackedFloat32Array()]
	gravel = [PackedFloat32Array(), PackedFloat32Array()]
	barrier = [PackedFloat32Array(), PackedFloat32Array()]
	barrier_kind = [PackedInt32Array(), PackedInt32Array()]
	for k in 2:
		kerb[k].resize(n)
		gravel[k].resize(n)
		barrier[k].resize(n)
		barrier_kind[k].resize(n)
		barrier[k].fill(layout.barrier_distance)
		barrier_kind[k].fill(Barrier.ARMCO)
	pit_width.resize(n)
	pit_width.fill(0.0)

	# Zebras: curvas com raio menor que kerb_max_radius (dos dois lados), estendidas ±10 m.
	if layout.auto_kerbs:
		for i in n:
			if absf(path.curvature[i]) > 1.0 / layout.kerb_max_radius:
				for k in 2:
					kerb[k][i] = 1.0
		for k in 2:
			kerb[k] = _smooth(_dilate(kerb[k], 5), 2)

	# Brita automática do lado de fora das curvas.
	if layout.auto_gravel:
		var limit := 1.0 / layout.gravel_max_radius
		var i := 0
		while i < n:
			if absf(path.curvature[i]) > limit:
				var start := i
				var peak := 0.0
				while i < n and absf(path.curvature[i]) > limit * 0.7:
					if absf(path.curvature[i]) > absf(peak):
						peak = path.curvature[i]
					i += 1
				var outside := -1 if peak > 0.0 else 1
				for idx in span_indices(path.s_at(start) - 40.0, path.s_at(i) + 50.0):
					gravel[_si(outside)][idx] = maxf(gravel[_si(outside)][idx], layout.gravel_width)
			i += 1

	# Elementos do layout que mudam o perfil
	for f in layout.features:
		if f == null:
			continue
		for side in f.sides():
			var k := _si(side)
			match f.kind:
				TrackFeature.Kind.GRAVEL:
					for idx in span_indices(f.s_start, f.s_end):
						gravel[k][idx] = maxf(gravel[k][idx], f.distance)
				TrackFeature.Kind.BARRIER:
					for idx in span_indices(f.s_start, f.s_end):
						barrier[k][idx] = f.distance
						barrier_kind[k][idx] = Barrier.CONCRETE if f.variant == 1 else Barrier.ARMCO
				TrackFeature.Kind.GRANDSTAND:
					for idx in span_indices(f.s_start - 10.0, f.s_end + 10.0):
						barrier_kind[k][idx] = Barrier.CONCRETE

	for k in 2:
		gravel[k] = _smooth(gravel[k], 8)

	# Barreira: atrás da zebra + brita
	for k in 2:
		for i in n:
			if gravel[k][i] > 0.5:
				var need := layout.kerb_width * kerb[k][i] + 1.0 + gravel[k][i] + 2.0
				barrier[k][i] = maxf(barrier[k][i], need)

	# Boxes: a pista dos boxes ocupa a faixa entre a borda e a barreira daquele lado
	if layout.has_pit:
		var k := _si(layout.pit_side)
		var full := PIT_WALL_STRIP + layout.pit_lane_width
		var span := fposmod(layout.pit_exit_s - layout.pit_entry_s, path.length)
		var building_half := layout.pit_building_length * 0.5
		for idx in span_indices(layout.pit_entry_s, layout.pit_exit_s):
			var rel := fposmod(path.s_at(idx) - layout.pit_entry_s, path.length)
			var w := smoothstep(0.0, layout.pit_taper, rel) * (1.0 - smoothstep(span - layout.pit_taper, span, rel))
			pit_width[idx] = w * full
			gravel[k][idx] = 0.0
			kerb[k][idx] = 0.0
			barrier[k][idx] = maxf(barrier[k][idx], pit_width[idx] + 1.0)
			var ds := fposmod(path.s_at(idx) - layout.garage_center_s + path.length * 0.5, path.length) - path.length * 0.5
			if absf(ds) < building_half:
				barrier_kind[k][idx] = Barrier.NONE

	# Suaviza a barreira e impede que ela cruze o centro de curvas fechadas
	for k in 2:
		var side := 1 if k == 0 else -1
		var b := _smooth(_dilate(barrier[k], 5), 5)
		for pass_i in 2:
			for i in n:
				var c := path.curvature[i] * side
				if c > 1e-4:
					var limit := 0.85 / c - path.half_width(i, side)
					b[i] = clampf(b[i], 1.2, maxf(limit, 1.2))
			if pass_i == 0:
				b = _smooth(b, 2)
		barrier[k] = b
		for i in n:
			if pit_width[i] > 0.0 and k == _si(layout.pit_side):
				b[i] = maxf(b[i], pit_width[i] + 1.0)
			gravel[k][i] = minf(gravel[k][i], maxf(b[i] - layout.kerb_width * kerb[k][i] - 3.0, 0.0))
		barrier[k] = b


static func _dilate(a: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var m := a[i]
		for d in range(-radius, radius + 1):
			m = maxf(m, a[(i + d + n) % n])
		out[i] = m
	return out


static func _smooth(a: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	# Média móvel com soma deslizante
	var sum := 0.0
	for d in range(-radius, radius + 1):
		sum += a[(d + n) % n]
	var w := 2 * radius + 1
	for i in n:
		out[i] = sum / w
		sum += a[(i + radius + 1) % n] - a[(i - radius + n) % n]
	return out
