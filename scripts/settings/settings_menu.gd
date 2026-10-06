class_name SettingsMenu
extends CanvasLayer
## Menu de configurações (F10, ou pelo menu inicial, pausa e garagem), no visual retro. Abas:
## Controles, Tela, Gráficos, Desempenho e Áudio. Tudo é aplicado e salvo na hora (GameSettings).
##
## Controles: clique no botão da tecla (ou do controle) e aperte a nova; Esc cancela, Backspace
## apaga. Conflitos com outras ações aparecem em amarelo ao lado.

const TABS := ["JOGO", "CONTROLES", "TELA", "GRÁFICOS", "DESEMPENHO", "ÁUDIO"]
const SECTION_OF_TAB := ["gameplay", "controls", "display", "graphics", "performance", "audio"]

var was_paused := false
var tab := 0

var _settings: GameSettings
var _content: VBoxContainer
var _scroll: ScrollContainer
var _tab_buttons: Array[Button] = []
## Captura de tecla em andamento: [ação, é controle, botão].
var _capture: Array = []


func _ready() -> void:
	layer = 115
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings = get_parent() as GameSettings
	var root := Retro.backdrop(0.9)
	root.theme = Retro.theme()
	add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", -12)
	center.add_child(holder)
	var tag_row := MarginContainer.new()
	tag_row.add_theme_constant_override("margin_left", 22)
	var tag := Retro.tag_label("SPEEDORU", 13)
	tag.z_index = 1
	tag_row.add_child(tag)
	holder.add_child(tag_row)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Retro.panel_style(28.0, 0.95))
	var vp_size := get_viewport().get_visible_rect().size
	panel.custom_minimum_size = Vector2(minf(1040, vp_size.x - 60), minf(700, vp_size.y - 80))
	holder.add_child(panel)
	Retro.add_corners(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "CONFIGURAÇÕES"
	title.theme_type_variation = "RetroTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var hint := Label.new()
	hint.text = "Esc / F10 fecha · tudo é salvo na hora"
	hint.theme_type_variation = "RetroMuted"
	hint.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(hint)
	box.add_child(head)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for k in TABS.size():
		var b := Button.new()
		b.text = TABS[k]
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_override("font", Retro.display(700))
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(150, 38)
		b.pressed.connect(_show_tab.bind(k))
		tabs.add_child(b)
		_tab_buttons.append(b)
	box.add_child(tabs)

	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	var reset := Button.new()
	reset.text = "Restaurar padrões desta aba"
	reset.theme_type_variation = "DangerButton"
	reset.pressed.connect(func() -> void:
		_settings.reset_section(SECTION_OF_TAB[tab])
		_show_tab.call_deferred(tab))
	foot.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	var close_b := Button.new()
	close_b.text = "FECHAR"
	close_b.theme_type_variation = "PrimaryButton"
	close_b.custom_minimum_size = Vector2(200, 44)
	close_b.pressed.connect(close)
	foot.add_child(close_b)
	box.add_child(foot)
	_show_tab(0)


func close() -> void:
	_settings.save_settings()
	get_tree().paused = was_paused
	queue_free()


func _input(event: InputEvent) -> void:
	if not _capture.is_empty():
		_handle_capture(event)
		get_viewport().set_input_as_handled()
		return
	if event.is_echo():
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("open_settings") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		# LB/RB: aba anterior/próxima
		_show_tab(posmod(tab + (1 if event.button_index == JOY_BUTTON_RIGHT_SHOULDER else -1), TABS.size()))
		_focus_first.call_deferred()
		get_viewport().set_input_as_handled()


func _focus_first() -> void:
	var first := Retro.first_focusable(_content)
	if first:
		first.grab_focus()


# ---------------------------------------------------------------------------
# Abas
# ---------------------------------------------------------------------------
func _show_tab(index: int) -> void:
	tab = index
	_capture = []
	for k in _tab_buttons.size():
		_tab_buttons[k].set_pressed_no_signal(k == index)
		_tab_buttons[k].theme_type_variation = "PrimaryButton" if k == index else ""
	for c in _content.get_children():
		c.queue_free()
	match index:
		0:
			_build_gameplay()
		1:
			_build_controls()
		2:
			_build_display()
		3:
			_build_graphics()
		4:
			_build_performance()
		5:
			_build_audio()
	_scroll.scroll_vertical = 0


func _header(text: String) -> void:
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_top", 10)
	var t := Retro.tag_label(text.to_upper(), 12)
	t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.add_child(t)
	_content.add_child(holder)


func _row(label_text: String, control: Control, note := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(330, 0)
	label.add_theme_color_override("font_color", Retro.c("text_2"))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	if note != "":
		var n := Label.new()
		n.text = note
		n.theme_type_variation = "RetroMuted"
		n.custom_minimum_size = Vector2(220, 0)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(n)
	_content.add_child(row)
	return row


func _option(section: String, key: String, label: String, items: Array, note := "") -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = clampi(int(_settings.get_value(section, key)), 0, items.size() - 1)
	o.item_selected.connect(func(i: int) -> void: _settings.set_value(section, key, i))
	_row(label, o, note)
	return o


func _toggle(section: String, key: String, label: String, note := "") -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = bool(_settings.get_value(section, key))
	c.text = "Ligado" if c.button_pressed else "Desligado"
	c.toggled.connect(func(on: bool) -> void:
		c.text = "Ligado" if on else "Desligado"
		_settings.set_value(section, key, on))
	_row(label, c, note)
	return c


func _slider(section: String, key: String, label: String, lo: float, hi: float, step: float, fmt: Callable) -> HSlider:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(_settings.get_value(section, key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(s)
	var v := Label.new()
	v.text = fmt.call(s.value)
	v.custom_minimum_size = Vector2(70, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_override("font", Retro.display(700))
	v.add_theme_font_size_override("font_size", 13)
	box.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt.call(x)
		_settings.set_value(section, key, x))
	_row(label, box)
	return s


static func _pct(x: float) -> String:
	return "%d%%" % roundi(x * 100.0)


# ---------------------------------------------------------------------------
func _build_gameplay() -> void:
	_header("Pista")
	_option("gameplay", "racing_line", "Linha ideal (L na pista)", ["Desligada", "Só nas frenagens e curvas", "Completa"],
		"setas no chão: verde acelera, amarelo no limite, vermelho freie")
	_header("Jogo")
	_toggle("gameplay", "auto_update", "Atualizar o jogo sozinho ao abrir",
		"baixa e instala a versão nova do GitHub em silêncio; o jogo reabre sozinho")


func _build_controls() -> void:
	var info := Label.new()
	info.text = "Clique numa tecla para trocar e aperte a nova (Esc cancela, Backspace apaga). Coluna da esquerda: teclado; da direita: controle."
	info.theme_type_variation = "RetroMuted"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(info)
	var group := ""
	for a in GameSettings.ACTIONS:
		if a[2] != group:
			group = a[2]
			_header(group)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.text = a[1]
		label.custom_minimum_size = Vector2(300, 0)
		label.add_theme_color_override("font_color", Retro.c("text_2"))
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		var warn := Label.new()
		warn.add_theme_color_override("font_color", Retro.c("warn"))
		warn.add_theme_font_size_override("font_size", 13)
		warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		warn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		for pad in [false, true]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(190, 34)
			b.clip_text = true
			b.text = GameSettings.event_label(_settings.get_binding(a[0], pad))
			b.pressed.connect(func() -> void:
				_capture = [a[0], pad, b, warn]
				b.text = "Aperte um botão do controle…" if pad else "Aperte uma tecla…")
			row.add_child(b)
		row.add_child(warn)
		_update_conflict(a[0], warn)
		_content.add_child(row)


func _update_conflict(action: String, warn: Label) -> void:
	var names := PackedStringArray()
	for pad in [false, true]:
		names.append_array(_settings.conflicts(action, _settings.get_binding(action, pad)))
	warn.text = ("também em: " + ", ".join(names)) if not names.is_empty() else ""


func _handle_capture(event: InputEvent) -> void:
	var action: String = _capture[0]
	var pad: bool = _capture[1]
	var button: Button = _capture[2]
	var warn: Label = _capture[3]
	var chosen: InputEvent = null
	var done := false
	if event is InputEventKey and event.pressed and not event.echo:
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if code == KEY_ESCAPE:
			done = true
		elif code == KEY_BACKSPACE or code == KEY_DELETE:
			_settings.set_binding(action, pad, null)
			done = true
		elif not pad:
			var k := InputEventKey.new()
			k.physical_keycode = code
			k.location = event.location
			chosen = k
	elif event is InputEventMouseButton and event.pressed:
		done = true  # clique fora cancela
	elif pad and event is InputEventJoypadButton and event.pressed:
		var jb := InputEventJoypadButton.new()
		jb.button_index = event.button_index
		chosen = jb
	elif pad and event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		var jm := InputEventJoypadMotion.new()
		jm.axis = event.axis
		jm.axis_value = signf(event.axis_value)
		chosen = jm
	if chosen:
		_settings.set_binding(action, pad, chosen)
		done = true
	if done:
		_capture = []
		button.text = GameSettings.event_label(_settings.get_binding(action, pad))
		_update_conflict(action, warn)


func _build_display() -> void:
	_header("Janela")
	var mode := _option("display", "window_mode", "Modo", ["Janela", "Tela cheia (sem bordas)", "Tela cheia exclusiva"])
	var res_items := []
	for r in GameSettings.RESOLUTIONS:
		res_items.append("%d × %d" % [r.x, r.y])
	var res := _option("display", "resolution", "Resolução da janela", res_items, "em tela cheia usa a do monitor")
	res.disabled = int(_settings.get_value("display", "window_mode")) != 0
	mode.item_selected.connect(func(i: int) -> void: res.disabled = i != 0)
	_option("display", "vsync", "Sincronia vertical (VSync)", ["Desligada", "Ligada", "Adaptativa", "Mailbox"],
		"ligada evita cortes na imagem")
	var fps_items := ["Sem limite"]
	for f in GameSettings.FPS_LIMITS.slice(1):
		fps_items.append("%d FPS" % f)
	_option("display", "max_fps", "Limite de FPS", fps_items)
	_header("Interface e câmera")
	var ui_items := []
	for sc in GameSettings.UI_SCALES:
		ui_items.append("Automática (pela janela)" if sc <= 0.0 else "%d%%" % roundi(sc * 100.0))
	_option("display", "ui_scale", "Escala da interface", ui_items, "valores altos em janela pequena sobrepõem o HUD")
	_slider("display", "fov", "Campo de visão (câmera de perseguição)", 55.0, 95.0, 1.0,
		func(x: float) -> String: return "%d°" % roundi(x))
	var palette := OptionButton.new()
	for name in Retro.palette_names():
		palette.add_item(name)
	palette.selected = Retro.PALETTE_ORDER.find(Retro.palette_id)
	palette.item_selected.connect(func(i: int) -> void: Retro.set_palette(Retro.PALETTE_ORDER[i]))
	_row("Paleta da interface", palette)


func _build_graphics() -> void:
	_header("Qualidade")
	var preset_items := ["Baixo", "Médio", "Alto", "Ultra", "Personalizado"]
	var p := OptionButton.new()
	for it in preset_items:
		p.add_item(it)
	p.set_item_disabled(4, true)
	var cur := int(_settings.get_value("graphics", "preset"))
	p.selected = cur if cur >= 0 else 4
	p.item_selected.connect(func(i: int) -> void:
		if i < 4:
			_settings.apply_preset(i)
			_show_tab.call_deferred(2))
	_row("Predefinição", p, "ajusta tudo abaixo de uma vez")
	_slider("graphics", "render_scale", "Escala de renderização 3D", 0.5, 1.0, 0.05, _pct)
	_option("graphics", "upscaler", "Ampliação (upscaler)", ["Bilinear", "AMD FSR 1.0", "AMD FSR 2.2"],
		"FSR fica mais nítido abaixo de 100%")
	_header("Serrilhado")
	_option("graphics", "msaa", "MSAA (bordas 3D)", ["Desligado", "2×", "4×", "8×"])
	_option("graphics", "screen_aa", "Anti-aliasing de tela", ["Desligado", "FXAA", "SMAA"])
	_toggle("graphics", "taa", "TAA (temporal)", "suaviza mais, pode borrar em movimento")
	_header("Luz e efeitos")
	_option("graphics", "shadows", "Sombras", ["Baixa", "Média", "Alta", "Ultra"])
	_toggle("graphics", "ssao", "Oclusão de ambiente (SSAO)")
	_toggle("graphics", "ssil", "Iluminação indireta (SSIL)")
	_toggle("graphics", "glow", "Brilho (glow/bloom)")
	_toggle("graphics", "volumetric_fog", "Neblina volumétrica")
	_option("graphics", "lod", "Nível de detalhe dos modelos", ["Baixo", "Médio", "Alto", "Ultra"])


func _build_performance() -> void:
	_header("Monitor na tela")
	_option("performance", "overlay", "Mostrar", ["Desligado", "Só FPS", "Detalhado (FPS, CPU, GPU, RAM)"])
	_option("performance", "corner", "Posição", ["Superior esquerdo", "Superior direito", "Inferior esquerdo",
		"Inferior direito", "Topo, no centro"])
	_option("performance", "online", "Em corridas online", ["Como acima", "FPS e latência", "Detalhado (com latência)"])
	var info := Label.new()
	info.text = "Faixa fina na borda escolhida. Detalhado: FPS (média e mínimo), mini gráfico do tempo de quadro, CPU = tempo do processador na lógica do jogo + na física, por quadro, GPU = tempo de renderização medido, RAM usada pelo jogo, memória de vídeo e draw calls. Conectado ao servidor, mostra também a latência (ida e volta até o servidor, em ms); nas corridas online o monitor liga sozinho (FPS e latência), a não ser que você escolha \"Como acima\"."
	info.theme_type_variation = "RetroMuted"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(info)


func _build_audio() -> void:
	_header("Volume")
	_slider("audio", "master", "Volume geral", 0.0, 1.5, 0.05, _pct)
	_slider("audio", "car", "Carro (motor, pneus, batidas)", 0.0, 1.5, 0.05, _pct)
	_slider("audio", "music", "Música", 0.0, 1.5, 0.05, _pct)
	_toggle("audio", "mute_unfocused", "Silenciar com a janela em segundo plano")
	_header("Música")
	_toggle("audio", "music_on", "Música de fundo (M)")
	var tracks := ["Playlist (todas, com transição)"]
	var music := get_node_or_null("/root/Music")
	if music:
		tracks.append_array(music.track_names())
	_option("audio", "track", "Faixa", tracks)
