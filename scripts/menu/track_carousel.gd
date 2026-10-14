class_name TrackCarousel
extends Control
## Escolha da pista em carrossel: o traçado de cada pista (linha central do CSV, norte para cima)
## num anel que gira; a da frente fica grande, com o nome, a extensão, a largada e um ponto de luz
## correndo a volta; as de trás ficam menores e apagadas. Trocar gira o anel (animado).
##
## Setas ‹ › nas laterais, clique nas pistas de trás, ←/→ (teclado e controle) com o foco. Só
## leitura (`editable = false`): mostra a pista escolhida, sem setas nem foco.
## Com `category` (RaceSettings.CATEGORIES) o anel só tem as pistas daquela categoria; as abas
## de category_tabs() trocam a categoria.

signal track_changed(index: int)

const SPIN_TIME := 0.5
## Fração da volta por segundo do ponto de luz na pista da frente.
const RUNNER_SPEED := 0.09

## Índice (em RaceSettings.TRACKS) da pista escolhida.
var selected := 0
var editable := true
## Categoria mostrada no anel; vazio = todas as pistas.
var category := ""
## Posição inicial do anel (a do carrossel anterior, quando a tela se refaz): gira dela até a
## escolhida. < 0 = começa parado na escolhida.
var start_pos := -1.0
## Posição atual do anel (em pistas; fracionária durante a animação).
var pos := 0.0

static var _outlines := {}
## Última pista escolhida em cada categoria (volta nela ao trocar de aba).
static var _last_in := {}

var _tween: Tween
var _runner := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(custom_minimum_size.x, maxf(custom_minimum_size.y, 200.0))
	focus_mode = Control.FOCUS_ALL if editable else Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_PASS
	tooltip_text = "Pista: ← → ou clique nas setas" if editable else ""
	if category != "" and not members().has(selected):
		category = RaceSettings.category_of(RaceSettings.TRACKS[selected]["id"])
	pos = float(_slot(selected))
	if start_pos >= 0.0 and start_pos < count() and not is_equal_approx(start_pos, pos):
		pos = start_pos
		_spin_to(_slot(selected))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	Retro.events.changed.connect(queue_redraw)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_runner = fmod(_runner + delta * RUNNER_SPEED, 1.0)
		queue_redraw()


## Pistas no anel (índices em RaceSettings.TRACKS).
func members() -> Array[int]:
	if category != "":
		return RaceSettings.tracks_in(category)
	var all: Array[int] = []
	for i in RaceSettings.TRACKS.size():
		all.append(i)
	return all


func count() -> int:
	return members().size()


## Posição da pista `index` no anel.
func _slot(index: int) -> int:
	return maxi(members().find(index), 0)


## Escolhe a pista `index` (de RaceSettings.TRACKS; gira o anel pelo caminho mais curto) e avisa.
func select(index: int) -> void:
	var m := members()
	if m.is_empty():
		return
	if not m.has(index):
		index = m[posmod(index, m.size())]
	if index == selected:
		return
	selected = index
	if category != "":
		_last_in[category] = index
	_spin_to(_slot(index))
	track_changed.emit(index)


## Pista seguinte (+1) ou anterior (-1) no anel.
func step(dir: int) -> void:
	var m := members()
	if not m.is_empty():
		select(m[posmod(_slot(selected) + dir, m.size())])


## Mostra outra categoria: volta na última pista escolhida nela (ou na primeira) e avisa.
func show_category(cat: String) -> void:
	if cat == category:
		return
	category = cat
	var m := members()
	if m.is_empty():
		return
	var index: int = _last_in.get(cat, m[0])
	if not m.has(index):
		index = m[0]
	if _tween:
		_tween.kill()
	pos = float(_slot(index))
	var changed := index != selected
	selected = index
	_last_in[cat] = index
	queue_redraw()
	if changed:
		track_changed.emit(index)


## Abas das categorias (RaceSettings.CATEGORIES) que trocam a categoria do carrossel; a ativa fica
## em destaque. Só para carrossel editável.
static func category_tabs(carousel: TrackCarousel) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "TrackTabs"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	var buttons: Array[Button] = []
	for cat: Array in RaceSettings.CATEGORIES:
		var b := Button.new()
		b.name = "Tab_%s" % cat[0]
		b.text = str(cat[1]).to_upper()
		b.custom_minimum_size = Vector2(150, 34)
		b.add_theme_font_override("font", Retro.display(700))
		b.add_theme_font_size_override("font_size", 12)
		b.set_meta("category", cat[0])
		row.add_child(b)
		buttons.append(b)
	var restyle := func() -> void:
		for b in buttons:
			b.theme_type_variation = "PrimaryButton" if b.get_meta("category") == carousel.category else ""
	for b in buttons:
		b.pressed.connect(func() -> void:
			carousel.show_category(b.get_meta("category"))
			restyle.call())
	restyle.call()
	return row


func _spin_to(index: int) -> void:
	var n := count()
	# Caminho mais curto no anel
	var target := float(index)
	var d := fposmod(target - pos + n * 0.5, float(n)) - n * 0.5
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "pos", pos + d, SPIN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void: pos = fposmod(pos, float(n)))


func _gui_input(event: InputEvent) -> void:
	if not editable:
		return
	if event.is_action_pressed("ui_left", true):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		step(1)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var x: float = (event as InputEventMouseButton).position.x
		if x < size.x * 0.3:
			step(-1)
		elif x > size.x * 0.7:
			step(1)
		grab_focus()
		accept_event()


func _draw() -> void:
	var m := members()
	var n := m.size()
	if n == 0:
		return
	var c := Vector2(size.x * 0.5, size.y * 0.4)
	var radius_x := minf(size.x * 0.34, 330.0)
	var front := minf(size.y * 0.56, size.x * 0.32)
	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size).grow(-1.0), Retro.c("accent_2"), false, 2.0)
	# Anel: de trás para a frente
	var items := []
	for i in n:
		var d := fposmod(i - pos + n * 0.5, float(n)) - n * 0.5
		var ang := d * TAU / n
		items.append([cos(ang), m[i], sin(ang)])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for it in items:
		var depth: float = (it[0] + 1.0) * 0.5
		var i: int = it[1]
		var p := c + Vector2(it[2] * radius_x, -(1.0 - depth) * size.y * 0.1)
		var k := lerpf(0.42, 1.0, depth * depth) + (0.08 if absf(it[2]) > 0.7 else 0.0)
		var front_most := depth > 0.98
		var col := Color(Retro.c("text"), lerpf(0.18, 1.0, depth * depth))
		_draw_track(RaceSettings.TRACKS[i]["id"], p, front * k, col, lerpf(1.2, 2.6, depth), front_most)
	# Nome e extensão da pista da frente
	var cur: Dictionary = RaceSettings.TRACKS[m[posmod(roundi(pos), n)]]
	var font := Retro.display(900)
	var y := size.y - 34.0
	draw_string(font, Vector2(0, y), str(cur["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Retro.c("text"))
	var km := outline_length(cur["id"]) / 1000.0
	if km > 0.0:
		draw_string(Retro.body(600), Vector2(0, y + 18), ("%.2f km" % km).replace(".", ","), HORIZONTAL_ALIGNMENT_CENTER, size.x, 12,
			Retro.c("muted"))
	# Pontos (qual das N)
	var dot_y := size.y - 6.0
	for i in n:
		var dx := (i - (n - 1) * 0.5) * 12.0
		draw_circle(Vector2(size.x * 0.5 + dx, dot_y), 3.0 if m[i] == selected else 2.0,
			Retro.c("accent") if m[i] == selected else Color(Retro.c("muted"), 0.6))
	if editable:
		var hover := get_local_mouse_position()
		for side in [-1, 1]:
			var ax := 18.0 if side < 0 else size.x - 18.0
			var on := Rect2(Vector2(0 if side < 0 else size.x * 0.7, 0), Vector2(size.x * 0.3, size.y)).has_point(hover) \
				and Rect2(Vector2.ZERO, size).has_point(hover)
			var arrow_col := Retro.c("accent") if on else Retro.c("text_2")
			var h := 14.0
			draw_polyline(PackedVector2Array([Vector2(ax - side * 7.0, c.y - h), Vector2(ax + side * 7.0, c.y),
				Vector2(ax - side * 7.0, c.y + h)]), arrow_col, 3.0, true)


## Traçado centrado em `center`, cabendo num quadrado de lado `box`. A da frente ganha a largada
## (traço xadrez e seta no sentido da corrida) e o ponto de luz correndo.
func _draw_track(id: String, center: Vector2, box: float, col: Color, width: float, front_most: bool) -> void:
	var o := outline(id)
	if o.size() < 3:
		return
	var pts := PackedVector2Array()
	pts.resize(o.size() + 1)
	for i in o.size():
		pts[i] = center + o[i] * box * 0.5
	pts[o.size()] = pts[0]
	if front_most:
		draw_polyline(pts, Color(Retro.c("accent"), 0.25), width + 5.0, true)
	draw_polyline(pts, col, width, true)
	if not front_most:
		return
	# Largada: traço perpendicular e seta para onde a corrida vai
	var a := pts[0]
	var b := pts[mini(3, pts.size() - 1)]
	var dir := (b - a).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	draw_line(a - nrm * 8.0, a + nrm * 8.0, Retro.c("text"), 3.0)
	draw_line(a - nrm * 8.0, a + nrm * 8.0, Color.BLACK, 1.0)
	var tip := a + dir * 16.0
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 7.0 + nrm * 4.0, tip - dir * 7.0 - nrm * 4.0]), Retro.c("accent"))
	# Ponto de luz dando a volta
	var lp := _point_at(pts, _runner)
	for g in 3:
		draw_circle(lp, 7.0 - g * 2.0, Color(Retro.c("accent_2"), 0.18 + g * 0.3))


static func _point_at(pts: PackedVector2Array, f: float) -> Vector2:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var want := f * total
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if want <= seg:
			return pts[i].lerp(pts[i + 1], want / maxf(seg, 0.001))
		want -= seg
	return pts[0]


## Traçado normalizado (centro em 0, maior lado = 2, norte para cima), começando na largada.
static func outline(id: String) -> PackedVector2Array:
	if not _outlines.has(id):
		_outlines[id] = _load(id)
	return _outlines[id][0]


## Extensão da linha central (m).
static func outline_length(id: String) -> float:
	if not _outlines.has(id):
		_outlines[id] = _load(id)
	return _outlines[id][1]


static func _load(id: String) -> Array:
	var layout_path := "res://resources/tracks/%s_layout.tres" % id
	if not ResourceLoader.exists(layout_path):
		return [PackedVector2Array(), 0.0]
	var layout := load(layout_path) as TrackLayout
	var file := FileAccess.open(layout.centerline, FileAccess.READ) if layout else null
	if file == null:
		return [PackedVector2Array(), 0.0]
	var raw := PackedVector2Array()
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var v := line.split_floats(",")
		if v.size() >= 2:
			raw.append(Vector2(v[0], -v[1]))
	if raw.size() < 3:
		return [PackedVector2Array(), 0.0]
	var length := 0.0
	for i in raw.size():
		length += raw[i].distance_to(raw[(i + 1) % raw.size()])
	# Começa na largada (start_offset metros depois do 1º ponto)
	var want := fposmod(layout.start_offset, length)
	var start := 0
	while want > 0.0 and start < raw.size():
		want -= raw[start].distance_to(raw[(start + 1) % raw.size()])
		start += 1
	var pts := PackedVector2Array()
	for i in raw.size():
		pts.append(raw[(start + i) % raw.size()])
	# Menos pontos (o desenho não precisa de todos) e normalizado
	var step := maxi(1, pts.size() / 400)
	var thin := PackedVector2Array()
	for i in range(0, pts.size(), step):
		thin.append(pts[i])
	var lo := thin[0]
	var hi := thin[0]
	for p in thin:
		lo = lo.min(p)
		hi = hi.max(p)
	var mid := (lo + hi) * 0.5
	var half := maxf(hi.x - lo.x, hi.y - lo.y) * 0.5
	for i in thin.size():
		thin[i] = (thin[i] - mid) / maxf(half, 1.0)
	return [thin, length]
