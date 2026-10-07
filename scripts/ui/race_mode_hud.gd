class_name RaceModeHud
extends CanvasLayer
## HUD do modo de jogo (visual retrofuturista, ver Retro): menu inicial, classificação paginada
## (superior esquerdo), minimapa (superior direito), voltas/tempos (centro superior), avisos de
## infração (banner grande na lateral direita), informações dos boxes, pausa (Esc) e resultado.

const PAGE_SIZE := 5
const MARGIN := 24.0
const MINIMAP := 210.0

var manager: RaceManager
var standings: Standings
var minimap: Minimap
var banner: Banner
var flag_panel: FlagPanel
var info: RaceInfo
var menu: Control
var results: Control
var pause_menu: Control


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	standings = Standings.new()
	standings.hud = self
	standings.position = Vector2(MARGIN, MARGIN)
	add_child(standings)
	minimap = Minimap.new()
	minimap.hud = self
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-MARGIN - MINIMAP, MARGIN)
	minimap.size = Vector2(MINIMAP, MINIMAP)
	add_child(minimap)
	info = RaceInfo.new()
	info.hud = self
	info.set_anchors_preset(Control.PRESET_CENTER_TOP)
	info.position = Vector2(-230, 16)
	info.size = Vector2(460, 250)
	add_child(info)
	flag_panel = FlagPanel.new()
	flag_panel.hud = self
	flag_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	flag_panel.position = Vector2(-320, 262)
	flag_panel.size = Vector2(640, 64)
	add_child(flag_panel)
	banner = Banner.new()
	banner.hud = self
	banner.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	banner.position = Vector2(-640, -170)
	banner.size = Vector2(640, 150)
	add_child(banner)
	manager.infraction.connect(_on_infraction)
	manager.state_changed.connect(_on_state)
	_on_state(manager.state)
	_move_base_hud()


## Abre espaço no HUD do carro: ajuda vai para baixo à esquerda (H mostra/esconde) e o nome do
## carro/câmera desce para baixo do minimapa.
func _move_base_hud() -> void:
	var base := get_parent().get_node_or_null("HUD")
	if base == null:
		return
	var help := base.get_node_or_null("Help") as Control
	if help:
		help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		help.offset_top = -150
		help.offset_bottom = -MARGIN
		help.offset_left = MARGIN
		help.grow_vertical = Control.GROW_DIRECTION_BEGIN
		help.visible = false
	var top_right := base.get_node_or_null("TopRight") as Control
	if top_right:
		top_right.offset_top = MARGIN + MINIMAP + 8
	# Garagem (Tab) abre embaixo da classificação
	var garage := base.get_node_or_null("Garage") as Control
	if garage:
		garage.offset_left = MARGIN
		garage.offset_top = MARGIN + 250
		garage.offset_bottom = -MARGIN


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("toggle_help"):
		var help := get_parent().get_node_or_null("HUD/Help") as Control
		if help:
			help.visible = not help.visible
	elif event.is_action_pressed("standings_next"):
		standings.page += 1
	elif event.is_action_pressed("standings_prev"):
		standings.page = maxi(standings.page - 1, 0)
	elif event.is_action_pressed("pause") and manager.state != RaceManager.State.MENU:
		_toggle_pause()
	elif event.is_action_pressed("ui_cancel") and pause_menu:
		_toggle_pause()
	else:
		return
	get_viewport().set_input_as_handled()


## Fecha a pausa e abre a garagem do carro (pelo controle, que não tem Tab).
func _open_garage() -> void:
	_toggle_pause()
	var garage := get_parent().get_node_or_null("HUD/Garage") as Control
	if garage:
		garage.visible = true
		get_tree().paused = true
		var first := Retro.first_focusable(garage)
		if first:
			first.grab_focus.call_deferred()


func _open_settings() -> void:
	var settings := get_node_or_null("/root/Settings") as GameSettings
	if settings:
		settings.open_menu()


func _on_state(state: int) -> void:
	var show_race := state != RaceManager.State.MENU
	standings.visible = show_race and state != RaceManager.State.PRACTICE and state != RaceManager.State.QUALIFYING
	minimap.visible = show_race
	flag_panel.visible = show_race
	info.visible = show_race
	if state == RaceManager.State.MENU:
		_show_menu()
	elif menu:
		menu.queue_free()
		menu = null
	if state == RaceManager.State.FINISHED and manager.player_entry and (manager.player_entry.finished or manager.net == RaceManager.Net.CLIENT):
		get_tree().create_timer(2.5).timeout.connect(_show_results)


func _on_infraction(entry: RaceEntry, title: String, detail: String, is_penalty: bool) -> void:
	if entry.is_player:
		banner.push(title, detail, is_penalty)


# ---------------------------------------------------------------------------
# Painéis modais (céu synthwave + cartão com cantoneiras)
# ---------------------------------------------------------------------------
func _panel(kicker: String, title: String, width: float, backdrop_alpha := 0.86) -> VBoxContainer:
	var root := Retro.backdrop(backdrop_alpha)
	root.theme = Retro.theme()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", -12)
	center.add_child(holder)
	var tag := Retro.tag_label(kicker, 13)
	tag.z_index = 1
	var tag_row := MarginContainer.new()
	tag_row.add_theme_constant_override("margin_left", 22)
	tag_row.add_child(tag)
	holder.add_child(tag_row)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Retro.panel_style(30.0, 0.94))
	panel.custom_minimum_size = Vector2(width, 0)
	holder.add_child(panel)
	Retro.add_corners(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	box.add_child(spacer)
	var label := Label.new()
	label.text = title
	label.theme_type_variation = "RetroTitle"
	box.add_child(label)
	add_child(root)
	box.set_meta("root", root)
	return box


func _option(box: VBoxContainer, label_text: String, items: Array, selected: int, on_select: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = label_text.to_upper()
	label.theme_type_variation = "RetroKicker"
	label.custom_minimum_size = Vector2(220, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		option.add_item(item)
	option.selected = selected
	option.item_selected.connect(on_select)
	row.add_child(option)
	box.add_child(row)


func _button(box: Container, text: String, on_press: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text.to_upper() if primary else text
	b.custom_minimum_size = Vector2(0, 46)
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.pressed.connect(on_press)
	box.add_child(b)
	return b


func _show_menu() -> void:
	if menu:
		return
	var box := _panel("SPEEDORU", _track_name(), 600, 0.88)
	menu = box.get_meta("root")
	var sub := Label.new()
	sub.text = "Escolha o modo de jogo"
	sub.theme_type_variation = "RetroMuted"
	box.add_child(sub)
	_option(box, "Modo", ["Corrida (pit obrigatório)", "Treino livre"], RaceSettings.mode,
		func(i: int) -> void: RaceSettings.mode = i as RaceSettings.Mode)
	var lap_options := [3, 5, 10, 15, 20]
	_option(box, "Voltas", lap_options.map(func(v): return str(v)), lap_options.find(RaceSettings.laps),
		func(i: int) -> void: RaceSettings.laps = lap_options[i])
	var opp := [3, 5, 9, 13]
	_option(box, "Adversários", opp.map(func(v): return str(v)), maxi(opp.find(RaceSettings.opponents), 0),
		func(i: int) -> void: RaceSettings.opponents = opp[i])
	_option(box, "Dificuldade dos bots", ["Fácil", "Médio", "Difícil", "Mista"], RaceSettings.difficulty,
		func(i: int) -> void: RaceSettings.difficulty = i)
	_option(box, "Largada", ["Pole position", "Meio do grid", "Última fila"], RaceSettings.grid,
		func(i: int) -> void: RaceSettings.grid = i as RaceSettings.Grid)
	_option(box, "DRS", ["Livre", "Só a até 1 s do carro da frente"], RaceSettings.drs_rule,
		func(i: int) -> void: RaceSettings.drs_rule = i)
	_option(box, "Classificatória", ["Sem", "1 volta", "2 voltas", "3 voltas"], RaceSettings.quali_laps,
		func(i: int) -> void: RaceSettings.quali_laps = i)
	var quali_row: Control = box.get_child(box.get_child_count() - 1)
	var cb := CheckBox.new()
	cb.text = "Colisão"
	cb.button_pressed = RaceSettings.quali_collisions
	cb.toggled.connect(func(on: bool) -> void: RaceSettings.quali_collisions = on)
	quali_row.add_child(cb)
	_option(box, "Horário", Array(DaylightPresets.TIME_NAMES), RaceSettings.time_of_day,
		func(i: int) -> void: RaceSettings.time_of_day = i)
	_option(box, "Ambiente", Array(DaylightPresets.BIOME_NAMES), RaceSettings.biome,
		func(i: int) -> void: RaceSettings.biome = i)
	var rules := Label.new()
	rules.text = "Regras: limites de pista (3 avisos, depois +5 s), cortar a pista +5 s, colisão +5/+10 s,\nlargada queimada +10 s, mais de 80 km/h nos boxes +5 s, sem pit stop = desclassificado.\nBoxes: entre logo depois da Parabolica, pare na sua vaga; 1/2/3 escolhem o pneu."
	rules.theme_type_variation = "RetroMuted"
	rules.add_theme_font_size_override("font_size", 13)
	box.add_child(rules)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var start := _button(buttons, "Iniciar", func() -> void: manager._start(), true)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cfg := _button(buttons, "Configurações", _open_settings)
	cfg.custom_minimum_size.x = 190


func _show_results() -> void:
	if results:
		return
	var box := _panel("BANDEIRA QUADRICULADA", "RESULTADO", 800)
	results = box.get_meta("root")
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for h in ["POS", "PILOTO", "VOLTAS", "TEMPO", "PENAL.", "MELHOR VOLTA"]:
		var l := Label.new()
		l.text = h
		l.theme_type_variation = "RetroKicker"
		grid.add_child(l)
	var rows := manager.final_classification()
	var winner_time := 0.0
	for k in rows.size():
		var e: RaceEntry = rows[k]
		if k == 0 and e.finished and not e.disqualified:
			winner_time = e.total_time()
		var cells := [
			"DSQ" if e.disqualified else ("DNF" if e.retired else str(k + 1)),
			("► " if e.is_player else "") + e.name,
			str(e.laps_completed()),
			"Desclassificado" if e.disqualified else "Abandonou" if e.retired else (RaceManager.format_time(e.total_time()) if k == 0 or winner_time <= 0.0
				else ("+%.3f" % (e.total_time() - winner_time) if e.finished else "em pista")),
			("+%ds" % roundi(e.penalty_seconds)) if e.penalty_seconds > 0.0 else "-",
			RaceManager.format_time(e.best_lap) + (" ⏱" if e == manager.fastest_entry else ""),
		]
		for c in cells.size():
			var l := Label.new()
			l.text = cells[c]
			if c == 0:
				l.add_theme_font_override("font", Retro.display(800))
			if e.is_player:
				l.add_theme_color_override("font_color", Retro.c("accent_2"))
			if e.disqualified or e.retired:
				l.add_theme_color_override("font_color", Retro.c("muted"))
			if c == 4 and e.penalty_seconds > 0.0:
				l.add_theme_color_override("font_color", Retro.c("bad"))
			if c == 5 and e == manager.fastest_entry:
				l.add_theme_color_override("font_color", Retro.FASTEST)
			grid.add_child(l)
	if manager.player_reward > 0:
		var reward := Label.new()
		reward.text = "+%s %s" % [PlayerProfile.format_credits(manager.player_reward), ShopCatalog.CURRENCY]
		reward.add_theme_font_override("font", Retro.display(800))
		reward.add_theme_font_size_override("font_size", 22)
		reward.add_theme_color_override("font_color", Retro.c("good"))
		box.add_child(reward)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	if manager.net == RaceManager.Net.CLIENT:
		_button(buttons, "Voltar à sala", func() -> void: manager.restart(false), true)
	else:
		_button(buttons, "Correr de novo", func() -> void: manager.restart(true), true)
		_button(buttons, "Menu", func() -> void: manager.restart(false))
	_button(buttons, "Continuar dirigindo", func() -> void:
		results.queue_free()
		results = null)


func _toggle_pause() -> void:
	if pause_menu:
		pause_menu.queue_free()
		pause_menu = null
		get_tree().paused = false
		return
	var online := manager.net == RaceManager.Net.CLIENT
	# Corrida em rede não pausa: o servidor segue correndo (o carro fica sem comandos)
	get_tree().paused = not online
	var box := _panel("SPEEDORU", "CORRIDA ONLINE" if online else "PAUSA", 440, 0.7)
	pause_menu = box.get_meta("root")
	_button(box, "Continuar", _toggle_pause, true)
	if online:
		_button(box, "Configurações", _open_settings)
		_button(box, "Sair da corrida", func() -> void: manager.restart(false))
		return
	if manager.state == RaceManager.State.PRACTICE:
		_button(box, "Garagem (Tab)", _open_garage)
	_button(box, "Configurações", _open_settings)
	_button(box, "Reiniciar", func() -> void: manager.restart(true))
	_button(box, "Menu principal", func() -> void: manager.restart(false))


## Relógio roxo (volta mais rápida), com halo.
static func draw_stopwatch(ci: CanvasItem, c: Vector2) -> void:
	ci.draw_circle(c, 12, Color(Retro.FASTEST, 0.22))
	ci.draw_circle(c, 9, Retro.FASTEST)
	ci.draw_circle(c, 6.5, Color(0.12, 0.04, 0.2))
	ci.draw_rect(Rect2(c.x - 2, c.y - 13, 4, 4), Retro.FASTEST)
	ci.draw_line(c, c + Vector2(0, -5), Color.WHITE, 2.0)
	ci.draw_line(c, c + Vector2(3.5, 1.5), Color.WHITE, 2.0)


# ---------------------------------------------------------------------------
# Classificação (superior esquerdo), páginas de 5
# ---------------------------------------------------------------------------
class Standings extends Control:
	var hud: RaceModeHud
	var page := 0
	const W := 340.0
	const ROW := 36.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(W, 240)

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var m := hud.manager
		var entries := m.entries
		if entries.is_empty():
			return
		var disp := Retro.display(800)
		var body := Retro.body(600)
		var pages := maxi(ceili(float(entries.size()) / PAGE_SIZE), 1)
		page = clampi(page, 0, pages - 1)
		var first := page * PAGE_SIZE
		var rows: Array[RaceEntry] = []
		for k in range(first, mini(first + PAGE_SIZE, entries.size())):
			rows.append(entries[k])
		var player := m.player_entry
		if player and not rows.has(player):
			rows[rows.size() - 1] = player
		var top := 12.0
		var panel := Rect2(0, top, W, rows.size() * ROW + 34)
		Retro.draw_panel(self, panel, 0.42, false)
		Retro.draw_corners(self, panel.grow(1.0))
		# Cabeçalho: etiqueta da volta + página
		var lap := clampi(player.current_lap() if player else 1, 1, m.laps)
		Retro.draw_tag(self, Vector2(14, 0), "VOLTA %d/%d" % [lap, m.laps], 13, 24.0)
		Retro.draw_label(self, Retro.display(600), Vector2(0, top + 26), "PÁG %d/%d · PgUp/PgDn" % [page + 1, pages],
			HORIZONTAL_ALIGNMENT_RIGHT, W - 14, 10, Retro.c("muted"))
		var y := top + 30.0
		for e in rows:
			var me := e == player
			var row := Rect2(8, y, W - 16, ROW - 4)
			if me:
				draw_rect(row, Color(Retro.c("accent"), 0.16))
				draw_rect(Rect2(row.position, Vector2(3, row.size.y)).grow(2.0), Color(Retro.c("accent"), 0.3))
				draw_rect(Rect2(row.position, Vector2(3, row.size.y)), Retro.c("accent"))
			else:
				draw_line(Vector2(row.position.x, row.end.y + 2), Vector2(row.end.x, row.end.y + 2), Retro.line(1), 1.0)
			# Posição: pódio aceso, demais com borda
			var pos_box := Rect2(row.position.x + 10, y + 4, 30, row.size.y - 8)
			if e.position <= 3:
				draw_rect(pos_box, Retro.c("text") if e.position > 1 else Retro.c("accent"))
			else:
				draw_rect(pos_box, Retro.line(3), false, 1.0)
			draw_string(disp, Vector2(pos_box.position.x, y + 22), str(e.position), HORIZONTAL_ALIGNMENT_CENTER,
				pos_box.size.x, 15, Retro.c("on_accent") if e.position <= 3 else Retro.c("text"))
			# Equipe e sigla
			var team := Retro.ctx(e.color)
			draw_rect(Rect2(row.position.x + 48, y + 6, 4, row.size.y - 12), team)
			draw_string(disp, Vector2(row.position.x + 60, y + 22), e.code, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Retro.c("accent_2") if me else Retro.c("text"))
			# Pneu (composto) e marcadores
			var x := row.position.x + 118.0
			var compound: int = e.car.config.tyre_compound if e.car and e.car.config else 1
			draw_circle(Vector2(x + 8, y + 16), 8, Retro.ctx(CarConfig.COMPOUND_COLORS[compound]))
			draw_circle(Vector2(x + 8, y + 16), 3.6, Retro.c("surface"))
			x += 24.0
			if e == m.fastest_entry:
				RaceModeHud.draw_stopwatch(self, Vector2(x + 9, y + 17))
				x += 24.0
			if e.in_pit:
				draw_string(Retro.display(800), Vector2(x, y + 21), "BOX", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Retro.c("warn"))
				x += 34.0
			if e.penalty_seconds > 0.0:
				draw_string(Retro.display(700), Vector2(x, y + 21), "+%ds" % roundi(e.penalty_seconds), HORIZONTAL_ALIGNMENT_LEFT,
					-1, 11, Retro.c("bad"))
			var gap := "DSQ" if e.disqualified else ("ABANDONOU" if e.retired else m.interval_text(e))
			draw_string(body, Vector2(row.position.x, y + 22), gap, HORIZONTAL_ALIGNMENT_RIGHT, row.size.x - 10, 14,
				Retro.c("bad") if e.disqualified else (Retro.c("muted") if e.retired else Retro.c("text_2")))
			y += ROW


# ---------------------------------------------------------------------------
# Minimapa (superior direito)
# ---------------------------------------------------------------------------
class Minimap extends Control:
	var hud: RaceModeHud
	var _poly := PackedVector2Array()
	var _pit := PackedVector2Array()
	var _xform := Transform2D.IDENTITY

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		if _poly.is_empty() and hud.manager.track and hud.manager.track.is_built:
			_build()
		queue_redraw()

	func _build() -> void:
		var track := hud.manager.track
		var p := track.path
		var r := p.bounds()
		var scale := minf((size.x - 40.0) / r.size.x, (size.y - 50.0) / r.size.y)
		var offset := size * 0.5 - r.get_center() * scale + Vector2(0, -6)
		_xform = Transform2D(Vector2(scale, 0), Vector2(0, scale), offset)
		for i in range(0, p.size(), 4):
			_poly.append(_xform * Vector2(p.points[i].x, p.points[i].z))
		_poly.append(_poly[0])
		var lay := track.layout
		if lay.has_pit:
			for idx in track.span_indices(lay.pit_entry_s, lay.pit_exit_s, 4):
				if track.pit_width[idx] > 2.0:
					var pt := track.edge_point(idx, lay.pit_side, RaceTrack.PIT_WALL_STRIP + 6.0)
					_pit.append(_xform * Vector2(pt.x, pt.z))

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(Retro.c("bg"), 0.3))
		Retro.draw_corners(self, r.grow(1.0), Color(Retro.c("accent"), 0.6), 10.0, 2.0)
		if _poly.size() < 2:
			return
		var accent := Retro.c("accent")
		# Traçado em neon: halo largo + linha clara
		draw_polyline(_poly, Color(accent, 0.18), 10.0, true)
		draw_polyline(_poly, Color(accent, 0.45), 5.0, true)
		draw_polyline(_poly, Retro.c("text"), 2.0, true)
		if _pit.size() > 1:
			draw_polyline(_pit, Color(Retro.c("warn"), 0.75), 1.5, true)
		var track := hud.manager.track
		var start := track.path.position_at(0.0)
		var s2 := _xform * Vector2(start.x, start.z)
		var t := track.path.tangent_at(0.0)
		var n := Vector2(-t.z, t.x) * 9.0
		draw_line(s2 - n, s2 + n, Retro.c("bad"), 3.0)
		var control := hud.manager.control
		if control and control.safety_car:
			var sc := control.safety_car.global_position
			var sp := _xform * Vector2(sc.x, sc.z)
			draw_rect(Rect2(sp - Vector2(6, 6), Vector2(12, 12)), Color("ffb000"))
			draw_string(Retro.display(800), sp + Vector2(8, 4), "SC", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("ffb000"))
		var player := hud.manager.player_entry
		for e: RaceEntry in hud.manager.entries:
			if e == player or e.car == null or e.retired:
				continue
			var pos := _xform * Vector2(e.car.global_position.x, e.car.global_position.z)
			draw_circle(pos, 6.0, Color(Retro.c("bg"), 0.85))
			draw_circle(pos, 4.5, Retro.ctx(e.color))
		if player:
			var pos := _xform * Vector2(player.car.global_position.x, player.car.global_position.z)
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
			draw_circle(pos, 12.0 + pulse * 3.0, Color(Retro.c("accent_2"), 0.18))
			draw_circle(pos, 8.0, Retro.c("bg"))
			draw_circle(pos, 6.0, Retro.c("accent_2"))
		Retro.draw_label(self, Retro.display(800), Vector2(14, size.y - 14), track.layout.display_name.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Retro.c("accent_2"))
		var km := ("%.2f km" % (track.path.length / 1000.0)).replace(".", ",") if track and track.path else ""
		Retro.draw_label(self, Retro.body(500), Vector2(0, size.y - 14), km, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14, 12,
			Retro.c("muted"))


# ---------------------------------------------------------------------------
# Banner de infrações (lateral direita)
# ---------------------------------------------------------------------------
class Banner extends Control:
	var hud: RaceModeHud
	var _queue: Array = []
	var _current: Array = []
	var _t := 0.0
	const DURATION := 3.6

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func push(title: String, detail: String, is_penalty: bool) -> void:
		_queue.append([title, detail, is_penalty])

	func _process(delta: float) -> void:
		if _current.is_empty() and not _queue.is_empty():
			_current = _queue.pop_front()
			_t = 0.0
		if not _current.is_empty():
			_t += delta
			if _t > DURATION:
				_current = []
		queue_redraw()

	func _draw() -> void:
		if _current.is_empty():
			return
		var appear := clampf(_t / 0.25, 0.0, 1.0)
		var fade := 1.0 - clampf((_t - DURATION + 0.4) / 0.4, 0.0, 1.0)
		var slide := (1.0 - ease(appear, 0.3)) * 660.0
		var penalty: bool = _current[2]
		var main := Retro.c("bad") if penalty else Retro.c("warn")
		var x0 := 40.0 + slide
		var top := 16.0
		var k := 30.0
		var h := size.y - top
		var shape := PackedVector2Array([Vector2(x0 + k, top), Vector2(size.x + 40, top),
			Vector2(size.x + 40, top + h), Vector2(x0, top + h)])
		# Brilho externo na cor da infração (só perto da borda)
		for g in 3:
			var off := 3.0 + g * 4.0
			draw_polyline(PackedVector2Array([Vector2(x0, top + h + off * 0.3), Vector2(x0 + k + off * 0.3, top - off),
				Vector2(size.x + 40, top - off)]), Color(main, (0.16 - g * 0.05) * fade), 3.0)
		var top_c := Color(Retro.c("surface_2"), 0.95 * fade)
		var bot_c := Color(Retro.c("bg"), 0.96 * fade)
		draw_polygon(shape, PackedColorArray([top_c, top_c, bot_c, bot_c]))
		# Trama de varredura por dentro
		draw_texture_rect(Retro.scan_texture(), Rect2(x0 + k, top, size.x + 40 - x0 - k, h), true, Color(main, 0.07 * fade))
		# Faixa inclinada na cor da infração + borda
		draw_colored_polygon(PackedVector2Array([Vector2(x0 + k, top), Vector2(x0 + k + 14, top),
			Vector2(x0 + 14, top + h), Vector2(x0, top + h)]), Color(main, fade))
		draw_polyline(PackedVector2Array([Vector2(x0, top + h), Vector2(x0 + k, top), Vector2(size.x + 40, top)]),
			Color(main, 0.8 * fade), 1.5)
		draw_line(Vector2(x0, top + h), Vector2(size.x + 40, top + h), Color(main, 0.35 * fade), 1.0)
		# Etiqueta chanfrada (pisca no começo)
		var label := "PENALIDADE" if penalty else "AVISO"
		if not (_t < 1.0 and int(_t * 8.0) % 2 == 0):
			Retro.draw_tag(self, Vector2(x0 + k + 20, 0), label, 14, 30.0, Color(main, fade), Color(main.lerp(Color.WHITE, 0.25), fade),
				Color(Retro.c("on_accent"), fade))
		Retro.draw_glow_text(self, Retro.display(900), Vector2(x0 + 52, top + 74), _current[0], HORIZONTAL_ALIGNMENT_LEFT,
			-1, 34, Color(Retro.c("text"), fade), main, fade)
		draw_string(Retro.body(600), Vector2(x0 + 52, top + 108), _current[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
			Color(Retro.c("text_2"), fade))


# ---------------------------------------------------------------------------
# Voltas e tempos (centro superior), largada e boxes
# ---------------------------------------------------------------------------
class RaceInfo extends Control:
	## Painel do centro: posição, tempo da volta (grande), última/melhor volta e a volta mais rápida
	## da corrida. Ao fechar uma volta, o tempo dela fica em destaque por FLASH s: roxo se é a mais
	## rápida da corrida, verde se é o seu recorde, amarelo nos outros casos, com a diferença para o
	## seu melhor. Quando alguém bate a volta mais rápida, a linha dela pisca em roxo.
	const FLASH := 5.0

	var hud: RaceModeHud
	var _laps_seen := -1
	var _prev_best := 0.0
	var _lap_flash := 0.0
	var _flash_lap := 0.0
	var _flash_delta := 0.0
	var _flash_color := Color.WHITE
	var _fastest_seen := 0.0
	var _fastest_flash := 0.0
	## DRS liberado pela regra de 1 s (aviso curto quando passa a valer)
	var _drs_flash := 0.0
	var _drs_was := true

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		var m := hud.manager
		var e := m.player_entry
		if e:
			if _laps_seen < 0:
				_laps_seen = e.lap_times.size()
				_prev_best = e.best_lap
			elif e.lap_times.size() > _laps_seen:
				_laps_seen = e.lap_times.size()
				_on_lap(e, e.lap_times[_laps_seen - 1])
		if m.fastest_lap > 0.0 and absf(m.fastest_lap - _fastest_seen) > 0.0005:
			_fastest_seen = m.fastest_lap
			_fastest_flash = FLASH
		if e and e.car:
			var allowed := e.car.drs_rule_active and e.car.drs_allowed and m.state == RaceManager.State.RACING
			if allowed and not _drs_was and e.car.speed_kmh > 80.0:
				_drs_flash = 2.5
			_drs_was = allowed
		_lap_flash = maxf(_lap_flash - d, 0.0)
		_fastest_flash = maxf(_fastest_flash - d, 0.0)
		_drs_flash = maxf(_drs_flash - d, 0.0)
		queue_redraw()

	func _on_lap(e: RaceEntry, lap: float) -> void:
		var m := hud.manager
		if lap <= 0.0:
			return
		_flash_lap = lap
		_flash_delta = lap - _prev_best if _prev_best > 0.0 else 0.0
		if m.fastest_entry == e and absf(m.fastest_lap - lap) < 0.001:
			_flash_color = Retro.FASTEST
		elif absf(e.best_lap - lap) < 0.001:
			_flash_color = Retro.c("good")
		else:
			_flash_color = Retro.c("warn")
		_prev_best = e.best_lap
		_lap_flash = FLASH

	func _draw() -> void:
		var m := hud.manager
		var e := m.player_entry
		if e == null:
			return
		var disp := Retro.display(800)
		var body := Retro.body(600)
		var cx := size.x * 0.5
		var practice := m.state == RaceManager.State.PRACTICE
		var quali := m.state == RaceManager.State.QUALIFYING
		var current := m.race_time - e.lap_start if e.crossings >= 1 else 0.0
		var top := "TREINO LIVRE" if practice else "P%d/%d" % [e.position, m.entries.size()]
		if quali:
			top = "CLASSIFICATÓRIA"
			if m.quali and m.quali.data.has(e):
				var qd: Dictionary = m.quali.data[e]
				if qd["done"]:
					top += " · CONCLUÍDA"
				elif qd["start"] < 0.0:
					top += " · VOLTA DE SAÍDA"
				else:
					top += " · %d/%d%s" % [int(qd["laps"]) + 1, m.quali.laps, " ANULADA" if qd["invalid"] else ""]
		var back := Rect2(cx - 175, 0, 350, 128 if practice else 156)
		draw_rect(back, Color(Retro.c("bg"), 0.36))
		Retro.draw_corners(self, back.grow(1.0), Color(Retro.c("accent"), 0.6), 10.0, 2.0)
		Retro.draw_glow_text(self, disp, Vector2(0, 32), top, HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Retro.c("text"))
		# Tempo da volta: grande; logo depois de fechar uma volta, o tempo dela com a cor do resultado
		if _lap_flash > 0.0:
			var a := clampf(_lap_flash / 0.6, 0.0, 1.0)
			var col := Color(_flash_color, a)
			Retro.draw_glow_text(self, Retro.display(900), Vector2(0, 66), RaceManager.format_time(_flash_lap),
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, col, _flash_color)
			var tag := "VOLTA MAIS RÁPIDA" if _flash_color == Retro.FASTEST else ("RECORDE PESSOAL" if _flash_color == Retro.c("good") else "VOLTA")
			if absf(_flash_delta) > 0.0005:
				tag += "   %s%.3f" % ["+" if _flash_delta > 0.0 else "−", absf(_flash_delta)]
			Retro.draw_label(self, Retro.display(700), Vector2(0, 84), tag, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, col)
		else:
			Retro.draw_glow_text(self, Retro.display(800), Vector2(0, 66), RaceManager.format_time(current),
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 28, Retro.c("accent_2"))
		# Última e melhor volta (a melhor em roxo, com o relógio, se é a mais rápida da corrida)
		var mine_fastest := e == m.fastest_entry and m.fastest_lap > 0.0
		var best_color := Retro.FASTEST if mine_fastest else Retro.c("text")
		Retro.draw_label(self, body, Vector2(cx - 215, 106), "ÚLTIMA " + RaceManager.format_time(e.last_lap), HORIZONTAL_ALIGNMENT_RIGHT,
			200, 16, Retro.c("text_2"))
		Retro.draw_label(self, Retro.body(700), Vector2(cx + 15, 106), "MELHOR " + RaceManager.format_time(e.best_lap), HORIZONTAL_ALIGNMENT_LEFT,
			200, 16, best_color)
		if mine_fastest:
			RaceModeHud.draw_stopwatch(self, Vector2(cx + 4, 100))
		# Volta mais rápida da corrida (pisca quando alguém bate o recorde)
		if m.fastest_entry and m.fastest_lap > 0.0:
			var who := "VOCÊ" if m.fastest_entry == e else m.fastest_entry.code
			var line := "VOLTA MAIS RÁPIDA  ·  %s  %s" % [who, RaceManager.format_time(m.fastest_lap)]
			var glow := _fastest_flash > 0.0 and fmod(_fastest_flash, 0.5) > 0.2
			if glow:
				Retro.draw_glow_text(self, Retro.display(800), Vector2(0, 126), line, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13,
					Retro.FASTEST, Retro.FASTEST)
			else:
				Retro.draw_label(self, Retro.display(700), Vector2(0, 126), line, HORIZONTAL_ALIGNMENT_CENTER, size.x, 12,
					Color(Retro.FASTEST, 0.95))
		if not practice and not quali:
			var done := e.pit_count >= RaceSettings.mandatory_pits
			var pit_text := "PIT OBRIGATÓRIO: FEITO" if done else "PIT OBRIGATÓRIO: PENDENTE"
			var font := Retro.display(700)
			var w := font.get_string_size(pit_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 20
			var chip := Rect2(cx - w * 0.5, 132, w, 20)
			var col := Retro.c("good") if done else Retro.c("warn")
			draw_rect(chip, Color(col, 0.12))
			draw_rect(chip, Color(col, 0.6), false, 1.0)
			draw_string(font, Vector2(chip.position.x, chip.position.y + 14), pit_text, HORIZONTAL_ALIGNMENT_CENTER, w, 10, col)
		if m.give_backs.has(e):
			# Posição ganha de forma irregular: devolver antes do prazo
			var gb: Dictionary = m.give_backs[e]
			var left := maxf(float(gb["until"]) - m.race_time, 0.0)
			var blink := fmod(m.race_time, 0.8) < 0.55
			Retro.draw_glow_text(self, disp, Vector2(0, 192), "DEVOLVA A POSIÇÃO PARA %s" % (gb["target"] as RaceEntry).code,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Retro.c("warn") if blink else Retro.c("text"), Retro.c("warn"))
			Retro.draw_label(self, Retro.display(700), Vector2(0, 214), "%s · %d s para deixar passar ou +%ds" % [gb["title"], ceili(left),
				roundi(float(gb["seconds"]))], HORIZONTAL_ALIGNMENT_CENTER, size.x, 12, Retro.c("warn"))
		elif _drs_flash > 0.0:
			var a := clampf(_drs_flash / 0.5, 0.0, 1.0)
			Retro.draw_glow_text(self, disp, Vector2(0, 192), "DRS LIBERADO", HORIZONTAL_ALIGNMENT_CENTER, size.x, 22,
				Color(Retro.c("good"), a), Retro.c("good"))
			Retro.draw_label(self, Retro.display(700), Vector2(0, 212), "a menos de 1 s do carro da frente · aperte o DRS",
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(Retro.c("good"), a))
		if m.state == RaceManager.State.GRID:
			Retro.draw_glow_text(self, disp, Vector2(0, 192), "AGUARDE AS LUZES APAGAREM", HORIZONTAL_ALIGNMENT_CENTER, size.x,
				22, Retro.c("bad"), Retro.c("bad"))
		elif e.in_pit:
			_pit_panel(e)
		elif m.state == RaceManager.State.FINISHED and e.finished:
			Retro.draw_glow_text(self, disp, Vector2(0, 192), "BANDEIRA QUADRICULADA!", HORIZONTAL_ALIGNMENT_CENTER, size.x,
				24, Retro.c("text"))

	func _pit_panel(e: RaceEntry) -> void:
		var m := hud.manager
		var r := Rect2(0, 166, size.x, 74)
		draw_rect(r, Color(Retro.c("bg"), 0.5))
		Retro.draw_corners(self, r.grow(1.0), Retro.c("warn"), 10.0, 2.0)
		var title := "PIT STOP..." if e.in_pit_stop else "BOXES · LIMITE 80 KM/H"
		draw_string(Retro.display(800), Vector2(0, r.position.y + 22), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 14,
			Retro.c("warn"))
		var labels := ["1 MACIO", "2 MÉDIO", "3 DURO"]
		var font := Retro.display(700)
		var x := 34.0
		for k in 3:
			var sel := k == m.pit_compound
			var c: Color = Retro.ctx(CarConfig.COMPOUND_COLORS[k])
			var chip := Rect2(x, r.position.y + 32, 120, 24)
			if sel:
				draw_rect(chip.grow(2.0), Color(c, 0.2))
				draw_rect(chip, Color(c, 0.22))
				draw_rect(chip, c, false, 1.0)
			draw_circle(Vector2(x + 14, chip.position.y + 12), 6, c)
			draw_string(font, Vector2(x + 28, chip.position.y + 17), labels[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Retro.c("text") if sel else Retro.c("muted"))
			x += 132.0
		if not e.in_pit_stop:
			var box := m.track.get_pit_box_transform(e.garage)
			var d := e.car.global_position.distance_to(box.origin)
			draw_string(Retro.body(600), Vector2(0, r.end.y - 4), "Seu box: %d m — pare na vaga" % roundi(d),
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Retro.c("text_2"))


# ---------------------------------------------------------------------------
# Bandeira e instruções (centro, abaixo dos tempos)
# ---------------------------------------------------------------------------
## Mostra a bandeira amarela e a instrução da situação do jogador, com a tecla/botão certo:
## batida ("pressione [K] para ir aos boxes ou vá sozinho 1:23"), amarela sem limitador
## ("pressione [P] para ativar o limitador"), ou só o lembrete das regras.
class FlagPanel extends Control:
	var hud: RaceModeHud
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var m := hud.manager
		if m.control == null or m.player_entry == null:
			return
		var info := m.control.instruction_for(m.player_entry)
		if info.is_empty():
			return
		var yellow := m.control.yellow
		var urgent: bool = info[2]
		var col := Color("ffc400") if yellow else Retro.c("warn")
		var blink := urgent and int(_t * 3.0) % 2 == 0
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(Retro.c("bg"), 0.62))
		draw_rect(Rect2(0, 0, 8, size.y), col if not blink else col.lightened(0.5))
		if yellow:
			# Bandeirinha amarela
			draw_rect(Rect2(20, 12, 3, 40), Color(0.85, 0.85, 0.9))
			draw_colored_polygon(PackedVector2Array([Vector2(23, 12), Vector2(52, 16), Vector2(48, 30), Vector2(23, 30)]), col)
		var x := 64.0 if yellow else 22.0
		Retro.draw_label(self, Retro.display(800), Vector2(x, 24), str(info[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		Retro.draw_label(self, Retro.body(600), Vector2(x, 48), str(info[1]), HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 12, 16,
			Color.WHITE if urgent else Retro.c("text_2"))
		Retro.draw_corners(self, r.grow(1.0), Color(col, 0.8), 10.0, 2.0)


## Nome da pista em jogo (do layout; antes de a pista existir, o escolhido no menu).
func _track_name() -> String:
	if manager and manager.track and manager.track.layout and manager.track.layout.display_name != "":
		return manager.track.layout.display_name.to_upper()
	return RaceSettings.track_name(RaceSettings.track).to_upper()
