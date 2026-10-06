class_name Retro
extends RefCounted
## Tema retrofuturista da interface (synthwave + monitor CRT + HUD de ficção científica).
##
## Tudo sai de tokens de cor de uma paleta (c("accent"), c("surface")…); as bordas são o acento
## com transparência (line(1..3)), o brilho é acento e nunca massa. Fontes: Orbitron (display:
## títulos, números, rótulos curtos em caixa alta) e Chakra Petch (corpo). Geometria reta: raio
## de 0 a 3 px, cantoneiras em "L" nos painéis principais, etiquetas chanfradas.
##
## * theme(): Theme para os Controls (botões, seletores, sliders, painéis, popups). É um objeto
##   só, atualizado no lugar quando a paleta muda, então os Controls mudam juntos.
## * draw_*(): peças desenhadas à mão pelos HUDs (painel, cantoneiras, etiqueta, barra segmentada,
##   texto com halo).
## * A paleta escolhida fica em user://interface.cfg (as que não são grátis se compram na loja).

const SETTINGS_PATH := "user://interface.cfg"

const PALETTE_ORDER := ["synthwave", "tron", "vaporwave", "fosforo", "ambar"]
const PALETTES := {
	"synthwave": {"name": "Synthwave", "bg": "0d0221", "bg_2": "13042e", "surface": "170935", "surface_2": "1f0d45",
		"surface_3": "2a1458", "text": "fbeaff", "text_2": "d6c2f0", "muted": "9a84bd", "accent": "ff2a6d",
		"accent_2": "05d9e8", "accent_3": "d300c5", "good": "3dfc9a", "bad": "ff4d6d", "warn": "ffd319",
		"on_accent": "12021f", "horizon": "ff2a6d"},
	"tron": {"name": "Tron", "bg": "000b13", "bg_2": "00111d", "surface": "031927", "surface_2": "062334",
		"surface_3": "0a3147", "text": "e0fbff", "text_2": "a3d9e8", "muted": "5f93a5", "accent": "00e5ff",
		"accent_2": "2f7bff", "accent_3": "7df9ff", "good": "3dfc9a", "bad": "ff5470", "warn": "ffc640",
		"on_accent": "00121c", "horizon": "00e5ff"},
	"vaporwave": {"name": "Vaporwave", "bg": "1a0b2e", "bg_2": "200e3a", "surface": "261146", "surface_2": "2e1554",
		"surface_3": "3b1c68", "text": "fff0fb", "text_2": "e4c8f2", "muted": "a98cc6", "accent": "ff71ce",
		"accent_2": "01cdfe", "accent_3": "b967ff", "good": "05ffa1", "bad": "ff5c8a", "warn": "fffb96",
		"on_accent": "1a0b2e", "horizon": "ff71ce"},
	"fosforo": {"name": "Fósforo verde", "bg": "010a03", "bg_2": "021006", "surface": "04170a", "surface_2": "07200f",
		"surface_3": "0b2d16", "text": "c8ffd4", "text_2": "8fe2a5", "muted": "52925f", "accent": "33ff66",
		"accent_2": "a6ff4d", "accent_3": "00ff9c", "good": "33ff66", "bad": "ff5a4d", "warn": "e8ff4d",
		"on_accent": "011204", "horizon": "33ff66", "mono": true},
	"ambar": {"name": "Âmbar", "bg": "0c0600", "bg_2": "120900", "surface": "1a0e02", "surface_2": "231404",
		"surface_3": "301c07", "text": "ffe4b5", "text_2": "e9c182", "muted": "a27b46", "accent": "ffb000",
		"accent_2": "ff7a00", "accent_3": "ffd166", "good": "b6ff4d", "bad": "ff5a3c", "warn": "ffd166",
		"on_accent": "1a0d00", "horizon": "ff9500", "mono": true},
}
## Roxo da volta mais rápida: é convenção da F1, fica igual em todas as paletas.
const FASTEST := Color("b14dff")

const ORBITRON := preload("res://assets/fonts/orbitron/Orbitron-Variable.ttf")
const CHAKRA := {
	400: preload("res://assets/fonts/chakra_petch/ChakraPetch-Regular.ttf"),
	500: preload("res://assets/fonts/chakra_petch/ChakraPetch-Medium.ttf"),
	600: preload("res://assets/fonts/chakra_petch/ChakraPetch-SemiBold.ttf"),
	700: preload("res://assets/fonts/chakra_petch/ChakraPetch-Bold.ttf"),
}

static var palette_id := "synthwave"
static var events := Events.new()
## O jogador está usando controle/teclado nos menus (último evento foi de navegação, não do mouse).
static var using_pad := false

static var _colors := {}
static var _display := {}
static var _theme: Theme
static var _scan_tex: ImageTexture
static var _loaded := false


class Events extends RefCounted:
	signal changed


# ---------------------------------------------------------------------------
# Tokens
# ---------------------------------------------------------------------------
static func c(token: String) -> Color:
	_ensure()
	return _colors.get(token, Color.MAGENTA)


## Bordas: acento com 14 / 24 / 42 % (fraca, média, forte).
static func line(level := 2) -> Color:
	return Color(c("accent"), [0.0, 0.14, 0.24, 0.42][clampi(level, 1, 3)])


## Cor de contexto (equipe, composto…): nas paletas monocromáticas vira o acento.
static func ctx(color: Color) -> Color:
	return c("accent") if is_mono() else color


static func is_mono() -> bool:
	return PALETTES[palette_id].get("mono", false)


static func palette_names() -> PackedStringArray:
	var out := PackedStringArray()
	for id in PALETTE_ORDER:
		out.append(PALETTES[id]["name"])
	return out


static func set_palette(id: String) -> void:
	if not PALETTES.has(id):
		return
	palette_id = id
	_apply()
	save_settings()


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var id := str(cfg.get_value("ui", "palette", "synthwave"))
		palette_id = id if PALETTES.has(id) else "synthwave"
	_loaded = true
	_apply()


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "palette", palette_id)
	cfg.save(SETTINGS_PATH)


static func _ensure() -> void:
	if not _loaded:
		load_settings()
	elif _colors.is_empty():
		_apply()


static func _apply() -> void:
	var p: Dictionary = PALETTES[palette_id]
	_colors.clear()
	for key in p:
		if p[key] is String and key != "name":
			_colors[key] = Color(p[key])
	if _theme:
		_fill_theme(_theme)
	events.changed.emit()


# ---------------------------------------------------------------------------
# Fontes
# ---------------------------------------------------------------------------
## Orbitron (variável) no peso pedido.
static func display(weight := 700) -> Font:
	if not _display.has(weight):
		var f := FontVariation.new()
		f.base_font = ORBITRON
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_display[weight] = f
	return _display[weight]


## Chakra Petch (400, 500, 600 ou 700).
static func body(weight := 500) -> Font:
	return CHAKRA.get(weight, CHAKRA[500])


# ---------------------------------------------------------------------------
# Theme para Controls
# ---------------------------------------------------------------------------
static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_fill_theme(_theme)
	return _theme


static func _box(bg: Color, border: Color, border_w := 1, radius := 3, shadow := Color(0, 0, 0, 0), shadow_size := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.shadow_color = shadow
	s.shadow_size = shadow_size
	s.anti_aliasing = false
	return s


static func _gradient_tex(from: Color, to: Color, angle := 0.0) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([from, to])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 16
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(cos(angle), sin(angle)) if angle != 0.0 else Vector2(1, 0)
	return t


## Painel padrão (cartão): superfície quase opaca, borda média, brilho difuso de acento.
static func panel_style(margin := 16.0, alpha := 0.92) -> StyleBoxFlat:
	var s := _box(Color(c("surface"), alpha), line(2), 1, 3, Color(c("accent"), 0.16), 10)
	s.set_content_margin_all(margin)
	return s


static func _fill_theme(t: Theme) -> void:
	var text := c("text")
	var accent := c("accent")
	t.default_font = body(500)
	t.default_font_size = 16

	t.set_color("font_color", "Label", text)

	# Botões comuns: superfície translúcida, borda média; hover com brilho
	var normal := _box(Color(c("surface_2"), 0.85), line(2))
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = c("surface_3")
	hover.border_color = line(3)
	hover.shadow_color = Color(accent, 0.4)
	hover.shadow_size = 7
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent, 0.22)
	pressed.border_color = accent
	var focus := _box(Color(0, 0, 0, 0), c("accent_2"))
	focus.draw_center = false
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(c("surface"), 0.6)
	disabled.border_color = line(1)
	for type in ["Button", "OptionButton", "ColorPickerButton", "MenuButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("disabled", type, disabled)
		t.set_color("font_color", type, text)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, text)
		t.set_color("font_disabled_color", type, c("muted"))
		t.set_color("icon_normal_color", type, c("text_2"))
		t.set_color("icon_hover_color", type, accent)
	t.set_font("font", "Button", body(600))

	# Botão principal: degradê neon, texto escuro, Orbitron em caixa alta
	t.set_type_variation("PrimaryButton", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var tex := StyleBoxTexture.new()
		var a := accent if state == "normal" or state == "focus" else accent.lightened(0.15)
		tex.texture = _gradient_tex(a, c("accent_3"))
		tex.content_margin_left = 22
		tex.content_margin_right = 22
		tex.content_margin_top = 10
		tex.content_margin_bottom = 10
		if state == "focus":
			tex.draw_center = false
			tex.texture = null
		t.set_stylebox(state, "PrimaryButton", tex)
	for col in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(col, "PrimaryButton", c("on_accent"))
	t.set_font("font", "PrimaryButton", display(800))
	t.set_font_size("font_size", "PrimaryButton", 15)

	# Botão de perigo
	t.set_type_variation("DangerButton", "Button")
	var danger := normal.duplicate() as StyleBoxFlat
	danger.border_color = Color(c("bad"), 0.45)
	t.set_stylebox("normal", "DangerButton", danger)
	t.set_color("font_color", "DangerButton", c("bad"))

	# Popups (lista do OptionButton)
	var popup := _box(Color(c("surface"), 0.97), line(3), 1, 3, Color(accent, 0.3), 12)
	popup.set_content_margin_all(6)
	t.set_stylebox("panel", "PopupMenu", popup)
	var popup_hover := _box(Color(accent, 0.16), line(3), 1, 2)
	t.set_stylebox("hover", "PopupMenu", popup_hover)
	t.set_color("font_color", "PopupMenu", c("text_2"))
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_accelerator_color", "PopupMenu", c("muted"))
	t.set_font("font", "PopupMenu", body(500))
	t.set_font_size("font_size", "PopupMenu", 15)

	# Painéis
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_stylebox("panel", "PopupPanel", popup)

	# Check
	for type in ["CheckButton", "CheckBox"]:
		t.set_color("font_color", type, c("text_2"))
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, text)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, text)
		var empty := StyleBoxEmpty.new()
		empty.content_margin_top = 4
		empty.content_margin_bottom = 4
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			t.set_stylebox(state, type, empty)

	# Slider: trilho no acento a 13 %, parte preenchida no acento com brilho
	var track := _box(Color(accent, 0.13), Color(0, 0, 0, 0), 0, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := _box(accent, Color(0, 0, 0, 0), 0, 0, Color(accent, 0.6), 4)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)

	# Barras de rolagem: acento a 28 %, cantos de 2 px
	var grab := _box(Color(accent, 0.28), Color(0, 0, 0, 0), 0, 2)
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	var grab_hi := grab.duplicate() as StyleBoxFlat
	grab_hi.bg_color = Color(accent, 0.5)
	var scroll_bg := _box(Color(accent, 0.06), Color(0, 0, 0, 0), 0, 0)
	scroll_bg.content_margin_left = 3
	scroll_bg.content_margin_right = 3
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)
	t.set_stylebox("scroll", "VScrollBar", scroll_bg)

	# Tooltips padrão (os de texto simples): cartão do tema, texto legível
	var tip := _box(Color(c("surface"), 0.97), line(3), 1, 3, Color(0, 0, 0, 0.45), 10)
	tip.content_margin_left = 12
	tip.content_margin_right = 12
	tip.content_margin_top = 8
	tip.content_margin_bottom = 8
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_font("font", "TooltipLabel", body(500))
	t.set_font_size("font_size", "TooltipLabel", 14)
	t.set_color("font_color", "TooltipLabel", c("text"))
	t.set_constant("line_spacing", "TooltipLabel", 3)

	# Rótulos de seção (variação de Label)
	t.set_type_variation("RetroKicker", "Label")
	t.set_font("font", "RetroKicker", display(700))
	t.set_font_size("font_size", "RetroKicker", 12)
	t.set_color("font_color", "RetroKicker", c("accent_2"))
	t.set_type_variation("RetroTitle", "Label")
	t.set_font("font", "RetroTitle", display(800))
	t.set_font_size("font_size", "RetroTitle", 30)
	t.set_color("font_color", "RetroTitle", text)
	t.set_color("font_shadow_color", "RetroTitle", Color(accent, 0.45))
	t.set_constant("shadow_outline_size", "RetroTitle", 14)
	t.set_constant("shadow_offset_x", "RetroTitle", 0)
	t.set_constant("shadow_offset_y", "RetroTitle", 0)
	t.set_type_variation("RetroMuted", "Label")
	t.set_color("font_color", "RetroMuted", c("muted"))
	t.set_font_size("font_size", "RetroMuted", 14)


# ---------------------------------------------------------------------------
# Desenho
# ---------------------------------------------------------------------------
## Cartão: degradê vertical surface_2 → surface, borda média, filete de luz no topo, brilho difuso
## só perto da borda e uma trama de varredura bem fraca por dentro.
static func draw_panel(ci: CanvasItem, r: Rect2, alpha := 0.9, glow := true, border_level := 2) -> void:
	var accent := c("accent")
	if glow:
		for k in 3:
			var g := r.grow(2.0 + k * 3.0)
			ci.draw_rect(g, Color(accent, 0.07 - k * 0.02), false, 3.0)
	var top := Color(c("surface_2"), alpha)
	var bottom := Color(c("surface"), minf(alpha + 0.04, 1.0))
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))
	ci.draw_texture_rect(scan_texture(), r, true, Color(accent, 0.05))
	ci.draw_line(r.position + Vector2(1, 1.5), Vector2(r.end.x - 1, r.position.y + 1.5), Color(accent, 0.18), 1.0)
	ci.draw_rect(r, line(border_level), false, 1.0)


## Cantoneiras em "L" (superior esquerda e inferior direita) com brilho.
static func draw_corners(ci: CanvasItem, r: Rect2, color := Color(0, 0, 0, 0), length := 14.0, width := 2.0, all_four := false) -> void:
	if color.a == 0.0:
		color = c("accent")
	var corners := [[r.position, Vector2(1, 1)], [r.end, Vector2(-1, -1)]]
	if all_four:
		corners += [[Vector2(r.end.x, r.position.y), Vector2(-1, 1)], [Vector2(r.position.x, r.end.y), Vector2(1, -1)]]
	for corner in corners:
		var p: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		var legs := [Rect2(p, Vector2(length * d.x, width * d.y)).abs(), Rect2(p, Vector2(width * d.x, length * d.y)).abs()]
		for leg: Rect2 in legs:
			ci.draw_rect(leg.grow(2.0), Color(color, 0.22))
		for leg: Rect2 in legs:
			ci.draw_rect(leg, color)


## Etiqueta chanfrada (canto inferior direito cortado) em degradê do acento, texto escuro.
## Devolve a largura usada.
static func draw_tag(ci: CanvasItem, pos: Vector2, text: String, font_size := 13, height := 24.0,
		from := Color(0, 0, 0, 0), to := Color(0, 0, 0, 0), text_color := Color(0, 0, 0, 0)) -> float:
	if from.a == 0.0:
		from = c("accent")
	if to.a == 0.0:
		to = c("accent_3")
	if text_color.a == 0.0:
		text_color = c("on_accent")
	var font := display(800)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 32.0
	var cut := 10.0
	ci.draw_polygon(PackedVector2Array([pos, pos + Vector2(w, 0), pos + Vector2(w - cut, height), pos + Vector2(0, height)]),
		PackedColorArray([from, to, to, from]))
	ci.draw_string(font, pos + Vector2(14, height * 0.5 + font_size * 0.38), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	return w


## Barra segmentada (cantos retos); segmentos acesos com brilho. [param colors] pode ser uma
## Callable(t) -> Color para colorir por posição.
static func draw_segments(ci: CanvasItem, r: Rect2, value: float, count: int, color: Variant, gap := 3.0, glow := true) -> void:
	var w := (r.size.x - gap * (count - 1)) / count
	var lit := value * count
	var trackc := Color(c("accent"), 0.13)
	for k in count:
		var seg := Rect2(r.position.x + k * (w + gap), r.position.y, w, r.size.y)
		var col: Color = color.call((k + 0.5) / count) if color is Callable else color
		var amount := clampf(lit - k, 0.0, 1.0)
		ci.draw_rect(seg, trackc)
		if amount > 0.0:
			var part := Rect2(seg.position, Vector2(seg.size.x * amount, seg.size.y))
			if glow:
				ci.draw_rect(part.grow(2.0), Color(col, 0.22))
			ci.draw_rect(part, col)


## Texto com halo de neon (só para títulos e números grandes).
static func draw_glow_text(ci: CanvasItem, font: Font, pos: Vector2, text: String, align: HorizontalAlignment,
		width: float, size: int, color: Color, glow := Color(0, 0, 0, 0), glow_strength := 1.0) -> void:
	if glow.a == 0.0:
		glow = c("accent")
	ci.draw_string_outline(font, pos, text, align, width, size, 14, Color(glow, 0.10 * glow_strength))
	ci.draw_string_outline(font, pos, text, align, width, size, 7, Color(glow, 0.22 * glow_strength))
	# Contorno escuro fino: legível também sobre o céu claro do jogo
	ci.draw_string_outline(font, pos, text, align, width, size, 3, Color(c("bg"), 0.75 * color.a))
	ci.draw_string(font, pos, text, align, width, size, color)


# ---------------------------------------------------------------------------
# Navegação por controle
# ---------------------------------------------------------------------------
## Evento de navegação de menu (D-pad/analógico/A do controle, setas/Enter do teclado).
static func is_nav_event(event: InputEvent) -> bool:
	if event is InputEventJoypadMotion:
		return absf(event.axis_value) > 0.6 and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT,
			JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_A]
	if event is InputEventKey and event.pressed and not event.echo:
		return event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER]
	return false


## Foca o primeiro controle focável visível da camada de interface mais alta que tenha algum.
## Devolve se focou.
static func grab_any_focus(tree: SceneTree) -> bool:
	var layers := tree.root.find_children("*", "CanvasLayer", true, false)
	layers.sort_custom(func(a: CanvasLayer, b: CanvasLayer) -> bool: return a.layer > b.layer)
	for l in layers:
		if not (l as CanvasLayer).visible:
			continue
		var c := first_focusable(l)
		if c:
			c.grab_focus()
			return true
	return false


static func first_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			if not c.is_visible_in_tree():
				continue
			if c.focus_mode == Control.FOCUS_ALL and (c is BaseButton or c is Range) and not (c is BaseButton and c.disabled):
				return c
		var deeper := first_focusable(child)
		if deeper:
			return deeper
	return null


## Texto pequeno do HUD sobre a pista: contorno escuro fino para ler sobre fundo claro (céu, grama).
static func draw_label(ci: CanvasItem, font: Font, pos: Vector2, text: String, align: HorizontalAlignment,
		width: float, size: int, color: Color) -> void:
	ci.draw_string_outline(font, pos, text, align, width, size, 4, Color(c("bg"), 0.85 * color.a))
	ci.draw_string(font, pos, text, align, width, size, color)


## Trama de varredura (1 linha a cada 4 px), para desenhar em mosaico com uma cor.
static func scan_texture() -> ImageTexture:
	if _scan_tex == null:
		var img := Image.create(1, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0))
		img.set_pixel(0, 0, Color.WHITE)
		_scan_tex = ImageTexture.create_from_image(img)
	return _scan_tex


# ---------------------------------------------------------------------------
# Controls auxiliares
# ---------------------------------------------------------------------------
## Cantoneiras num Control (painel de conteúdo principal). Desenhadas pelo sinal draw do próprio
## Control (por cima do fundo, abaixo dos filhos), então funcionam também em Containers.
static func add_corners(target: Control, color := Color(0, 0, 0, 0)) -> void:
	target.draw.connect(func() -> void:
		draw_corners(target, Rect2(Vector2(-1, -1), target.size + Vector2(2, 2)), color))
	events.changed.connect(target.queue_redraw)


## Tooltip bonito (para _make_custom_tooltip): cartão do tema com título, texto com quebra de linha
## (largura máxima) e linhas de valores "Nome · valor" opcionais (ex.: atual, fábrica, limites).
static func make_tooltip(title: String, text: String, rows: Array = [], accent := Color(0, 0, 0, 0)) -> Control:
	if accent.a == 0.0:
		accent = c("accent_2")
	var panel := PanelContainer.new()
	var st := _box(Color(c("surface"), 0.97), Color(accent, 0.7), 1, 3, Color(0, 0, 0, 0.5), 12)
	st.border_width_left = 3
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", st)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	if title != "":
		var head := Label.new()
		head.text = title.to_upper()
		head.add_theme_font_override("font", display(800))
		head.add_theme_font_size_override("font_size", 12)
		head.add_theme_color_override("font_color", accent)
		box.add_child(head)
	if text != "":
		var body_l := Label.new()
		body_l.text = text
		body_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_l.custom_minimum_size = Vector2(320, 0)
		body_l.add_theme_font_override("font", body(500))
		body_l.add_theme_font_size_override("font_size", 14)
		body_l.add_theme_color_override("font_color", c("text"))
		body_l.add_theme_constant_override("line_spacing", 3)
		box.add_child(body_l)
	if not rows.is_empty():
		var sep := ColorRect.new()
		sep.color = line(2)
		sep.custom_minimum_size = Vector2(0, 1)
		box.add_child(sep)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 2)
		for r in rows:
			var k := Label.new()
			k.text = str(r[0]).to_upper()
			k.add_theme_font_override("font", display(700))
			k.add_theme_font_size_override("font_size", 10)
			k.add_theme_color_override("font_color", c("muted"))
			grid.add_child(k)
			var v := Label.new()
			v.text = str(r[1])
			v.add_theme_font_override("font", body(600))
			v.add_theme_font_size_override("font_size", 13)
			v.add_theme_color_override("font_color", r[2] if r.size() > 2 else c("text_2"))
			grid.add_child(v)
		box.add_child(grid)
	return panel


## Etiqueta chanfrada como Control (título de seção em menus e na garagem).
static func tag_label(text: String, font_size := 13) -> Control:
	var t := TagLabel.new()
	t.text = text
	t.font_size = font_size
	return t


class TagLabel extends Control:
	var text := ""
	var font_size := 13

	func _ready() -> void:
		var w := Retro.display(800).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 32.0
		custom_minimum_size = Vector2(w, font_size + 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		Retro.events.changed.connect(queue_redraw)

	func _draw() -> void:
		Retro.draw_tag(self, Vector2.ZERO, text, font_size, size.y)


## Fundo synthwave (céu + sol no horizonte + grade em perspectiva) para menus.
static func backdrop(alpha := 0.82) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ui/retro_backdrop.gdshader")
	rect.material = mat
	var update := func() -> void:
		mat.set_shader_parameter("bg", c("bg"))
		mat.set_shader_parameter("bg_2", c("bg_2"))
		mat.set_shader_parameter("horizon", c("horizon"))
		mat.set_shader_parameter("accent", c("accent"))
		mat.set_shader_parameter("accent_3", c("accent_3"))
		mat.set_shader_parameter("alpha", alpha)
	update.call()
	events.changed.connect(update)
	rect.tree_exiting.connect(func() -> void:
		if events.changed.is_connected(update):
			events.changed.disconnect(update))
	return rect
