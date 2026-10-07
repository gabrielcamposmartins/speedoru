class_name StudioPanel
extends HBoxContainer
## Estúdio: equipa e combina o que a conta tem (nunca libera nada novo). Usado na garagem do menu
## principal (painel à direita, carro em foco) e no painel da garagem durante a corrida (Tab).
##
## Layout compacto: uma coluna de abas só com ícones (o nome aparece no topo e no tooltip) e uma
## grade de 2 colunas em que toda opção tem o mesmo tamanho (TILE).
## * Pinturas aplicam as 3 cores de uma vez; as cores principal/secundária/destaque se misturam só
##   entre as cores das pinturas possuídas.
## * Capacete, macacão, cor das rodas, brilho do boost e neon: as cores das peças daquele tipo.
## * Peças: as variantes ganhas (a padrão sempre), com o efeito na aerodinâmica no tooltip.
## * Engenharia: o comportamento do carro (aerodinâmica, freios, pneus, direção, câmbio,
##   suspensão, assistências), com slider, ajuste grosso/fino e explicação de cada parâmetro.
## Cada escolha vai para o Profile (que confere e salva) e para o carro na hora.

const TILE := Vector2(148, 92)
const CATEGORIES := [
	["engineering", "Engenharia"],
	["livery", "Pinturas"],
	["finish", "Acabamento"],
	["primary", "Cor principal"],
	["secondary", "Cor secundária"],
	["accent", "Cor de destaque"],
	["helmet", "Capacete"],
	["suit", "Macacão"],
	["rim", "Cor das rodas"],
	["boost", "Brilho do boost"],
	["neon", "Neon embaixo do carro"],
	["parts", "Peças"],
]
## Explicação de cada aba (tooltip).
const CATEGORY_TIPS := {
	"engineering": "Comportamento do carro: aerodinâmica, freios, pneus, direção, câmbio, suspensão e assistências. Não muda a aparência.",
	"livery": "Pinturas que você tem. Uma pintura aplica as 3 cores do carro de uma vez.",
	"finish": "Acabamento da pintura (brilhante, metálico, perolado, acetinado, fosco, cromado) e das rodas. Todos vêm com o jogo.",
	"primary": "Cor principal do carro, escolhida entre as cores das suas pinturas.",
	"secondary": "Cor secundária do carro, escolhida entre as cores das suas pinturas.",
	"accent": "Cor de destaque (detalhes e faixas), escolhida entre as cores das suas pinturas.",
	"helmet": "Cor do capacete do piloto.",
	"suit": "Cor do macacão do piloto.",
	"rim": "Cor das rodas.",
	"boost": "Cor do brilho das rodas, do rastro e das partículas quando o boost está ligado.",
	"neon": "Luz de neon embaixo do carro (fica mais forte à noite).",
	"parts": "Peças de desempenho que você ganhou: trocam aderência por velocidade.",
}

var car: F1Car
var category := "engineering"

var _profile: PlayerProfile
var _tabs: VBoxContainer
var _title: Label
var _note: Label
var _grid: GridContainer


func setup(target: F1Car, _compact := false) -> void:
	car = target
	_profile = get_node("/root/Profile") as PlayerProfile
	add_theme_constant_override("separation", 10)
	_tabs = VBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	add_child(_tabs)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	_title = Label.new()
	_title.add_theme_font_override("font", Retro.display(800))
	_title.add_theme_font_size_override("font_size", 14)
	_title.add_theme_color_override("font_color", Retro.c("text"))
	right.add_child(_title)
	_note = Label.new()
	_note.theme_type_variation = "RetroMuted"
	_note.add_theme_font_size_override("font_size", 12)
	right.add_child(_note)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	right.add_child(_grid)
	if not _profile.changed.is_connected(_on_profile_changed):
		_profile.changed.connect(_on_profile_changed)
	_build()


func _on_profile_changed() -> void:
	if car and car.config:
		_profile.apply_to_config(car.config)
	_build.call_deferred()


func _build() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	for cat in CATEGORIES:
		var t := IconTab.new()
		t.icon_kind = cat[0]
		t.tooltip_text = cat[1]
		t.tip_text = CATEGORY_TIPS.get(cat[0], "")
		t.selected = cat[0] == category
		t.tint = _tab_tint(cat[0])
		t.pressed.connect(func() -> void:
			category = cat[0]
			_build())
		_tabs.add_child(t)
	for c in _grid.get_children():
		c.queue_free()
	_grid.columns = 1 if category == "engineering" else 2
	var eq := _profile.equipped
	for cat in CATEGORIES:
		if cat[0] == category:
			_title.text = str(cat[1]).to_upper()
	match category:
		"livery":
			var owned := _profile.owned_of_type("livery")
			_note.text = "%d de %d pinturas · aplica as 3 cores" % [owned.size(), ShopCatalog.items_of_type("livery").size()]
			for id in owned:
				_tile(id, ShopCatalog.item(id)["name"], eq["livery"] == id, _profile.equip_livery.bind(id))
		"primary", "secondary", "accent", "helmet", "suit", "rim", "boost":
			_note.text = "cores das %s que você tem" % ("pinturas" if category in ["primary", "secondary", "accent"] else "peças deste tipo")
			_color_tiles(category)
		"neon":
			if not _profile.has_neon():
				_note.text = "ganhe um neon nas roletas da loja"
			else:
				_note.text = "fica mais forte à noite"
			var off := OptionTile.new()
			off.title = "Desligado"
			off.art_kind = "off"
			off.selected = not eq["neon_on"]
			off.pressed.connect(_profile.set_neon.bind(false))
			_add(off)
			if _profile.has_neon():
				for c in _profile.unlocked_colors("neon"):
					var t := OptionTile.new()
					t.title = _color_source_name("neon", c)
					t.art_kind = "glow"
					t.color = c
					t.selected = eq["neon_on"] and str(eq["neon"]) == c.to_html(false)
					t.pressed.connect(func() -> void:
						_profile.equip_color("neon", c)
						_profile.set_neon(true))
					_add(t)
		"engineering":
			_build_engineering()
		"finish":
			_note.text = "como a luz reflete na pintura e nas rodas"
			_build_finishes()
		"parts":
			_note.text = "trocam aderência por velocidade"
			for slot in CarPartCatalog.all_slots():
				if CarPartCatalog.variants(slot).size() < 2:
					continue
				var current: String = eq["parts"].get(slot, CarPartCatalog.default_variant(slot))
				for variant in _profile.owned_variants(slot):
					var t := OptionTile.new()
					t.title = CarPartCatalog.variant_label(slot, variant)
					t.subtitle = CarPartCatalog.slot_label(slot)
					t.art_kind = "part"
					t.selected = variant == current
					t.tip_text = "%s: %s." % [CarPartCatalog.slot_label(slot), CarPartCatalog.variant_label(slot, variant)]
					t.tip_rows = _stats_rows(slot, variant)
					t.pressed.connect(_profile.equip_part.bind(slot, variant))
					_add(t)


const PAINT_TIPS := ["Verniz liso e brilhante (padrão).", "Flocos metálicos sob o verniz: brilha e cintila.",
	"Verniz espesso com borda clara iridescente.", "Brilho suave, meio fosco.", "Sem reflexo: cor sólida e chapada.",
	"Espelhado: reflete tudo ao redor."]
const RIM_TIPS := ["Metal polido com faixa de reflexo.", "Espelhado, reflexo forte.", "Metal escovado, reflexo suave.",
	"Pintura fosca, sem reflexo."]


func _build_finishes() -> void:
	var eq := _profile.equipped
	var paint := Color(str(eq["primary"]))
	var rim := Color(str(eq["rim"]))
	for group in [["PINTURA", "paint_finish", CarConfig.PAINT_FINISHES, PAINT_TIPS, paint],
			["RODAS", "rim_finish", CarConfig.RIM_FINISHES, RIM_TIPS, rim]]:
		var head := Label.new()
		head.text = group[0]
		head.theme_type_variation = "RetroKicker"
		head.add_theme_font_size_override("font_size", 11)
		_grid.add_child(head)
		_grid.add_child(Control.new())
		var names: Array = group[2]
		for k in names.size():
			var t := OptionTile.new()
			t.title = names[k]
			t.art_kind = "finish"
			t.finish = k if group[1] == "paint_finish" else [0, 5, 3, 4][k]
			t.color = group[4]
			t.selected = int(eq[group[1]]) == k
			t.tip_text = group[3][k]
			t.pressed.connect(_profile.set_finish.bind(group[1], k))
			_add(t)
		if names.size() % 2 == 1:
			_grid.add_child(Control.new())


func _build_engineering() -> void:
	_note.text = "só o comportamento do carro · passe o mouse para a explicação"
	var reset_all := Button.new()
	reset_all.text = "Restaurar tudo de fábrica"
	reset_all.add_theme_font_size_override("font_size", 12)
	reset_all.pressed.connect(func() -> void:
		_profile.reset_setup()
		_profile.apply_setup(car)
		_build())
	_grid.add_child(reset_all)
	for group in CarSetup.GROUPS:
		var head := Label.new()
		head.text = str(group).to_upper()
		head.theme_type_variation = "RetroKicker"
		head.add_theme_font_size_override("font_size", 11)
		_grid.add_child(head)
		for p in CarSetup.PARAMS:
			if p[1] == group:
				var row := SetupRow.new()
				row.param = p
				row.studio = self
				_grid.add_child(row)


func _tab_tint(kind: String) -> Color:
	var eq := _profile.equipped
	match kind:
		"primary", "secondary", "accent", "helmet", "suit", "rim", "boost":
			return Color(str(eq[kind]))
		"neon":
			return Color(str(eq["neon"])) if eq["neon_on"] else Retro.c("muted")
	return Retro.c("text_2")


func _add(tile: OptionTile) -> void:
	_grid.add_child(tile)


func _tile(id: String, title: String, selected: bool, on_press: Callable) -> void:
	var t := OptionTile.new()
	t.item_id = id
	t.title = title
	t.art_kind = "livery"
	t.selected = selected
	t.pressed.connect(on_press)
	_add(t)


func _color_tiles(field: String) -> void:
	var current := str(_profile.equipped.get(field, ""))
	for c in _profile.unlocked_colors(field):
		var t := OptionTile.new()
		t.title = _color_source_name(field, c)
		t.art_kind = "glow" if field == "boost" else "color"
		t.color = c
		t.selected = c.to_html(false) == current
		t.pressed.connect(_profile.equip_color.bind(field, c))
		_add(t)


## Nome da peça de onde a cor veio (a primeira que a tem).
func _color_source_name(field: String, c: Color) -> String:
	var key := c.to_html(false)
	for id in _profile.owned_of_type(PlayerProfile.COLOR_FIELDS[field]):
		for cc in ShopCatalog.colors_of(id):
			if cc.to_html(false) == key:
				return ShopCatalog.item(id)["name"]
	return "#" + key


func _stats_rows(slot: String, variant: String) -> Array:
	var st := CarPartCatalog.variant_stats(slot, variant)
	if st.is_empty():
		return [["Efeito", "peça de referência"]]
	var rows := []
	if st.has("downforce"):
		rows.append(["Carga", "%+.2f m²" % st["downforce"], Retro.c("good") if st["downforce"] > 0 else Retro.c("warn")])
	if st.has("drag"):
		rows.append(["Arrasto", "%+.2f m²" % st["drag"], Retro.c("good") if st["drag"] < 0 else Retro.c("warn")])
	if st.has("balance"):
		rows.append(["Balanço", "%+d%% frente" % roundi(st["balance"] * 100.0)])
	return rows


func _stats_text(slot: String, variant: String) -> String:
	var st := CarPartCatalog.variant_stats(slot, variant)
	if st.is_empty():
		return "Referência"
	var parts := PackedStringArray()
	if st.has("downforce"):
		parts.append("downforce %+.2f m²" % st["downforce"])
	if st.has("drag"):
		parts.append("arrasto %+.2f m²" % st["drag"])
	if st.has("balance"):
		parts.append("balanço %+d%%" % roundi(st["balance"] * 100.0))
	return ", ".join(parts)


## Esfera ilustrando um acabamento: sombra, brilho especular (tamanho/força pelo acabamento),
## flocos (metálico), borda clara (perolado) e reflexo de céu/chão (cromado).
static func draw_finish_ball(ci: CanvasItem, c: Vector2, r: float, base: Color, finish: int) -> void:
	var steps := 10
	for k in steps:
		var f := float(k) / steps
		var col := base.darkened(0.45 * (1.0 - f))
		if finish == 5:
			col = Color(0.25, 0.3, 0.36).lerp(Color(0.85, 0.92, 1.0), f).lerp(base, 0.35)
		ci.draw_circle(c + Vector2(r, r) * 0.18 * f, r * (1.0 - f * 0.55), col)
	if finish == 1:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for k in 26:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * r * 0.9
			ci.draw_circle(c + Vector2(cos(a), sin(a)) * d, 1.0, Color(1, 1, 1, rng.randf_range(0.3, 0.8)))
	if finish == 2:
		ci.draw_arc(c, r * 0.95, 0, TAU, 40, Color(0.85, 0.95, 1.0, 0.7), r * 0.12)
	var spec: float = [0.9, 1.0, 1.0, 0.45, 0.0, 1.0][clampi(finish, 0, 5)]
	var size: float = [0.22, 0.16, 0.18, 0.4, 0.0, 0.12][clampi(finish, 0, 5)]
	if spec > 0.0:
		ci.draw_circle(c - Vector2(r, r) * 0.35, r * size, Color(1, 1, 1, spec))
	if finish == 5:
		ci.draw_line(c + Vector2(-r * 0.8, r * 0.1), c + Vector2(r * 0.8, r * 0.1), Color(1, 1, 1, 0.8), 2.0)
	ci.draw_arc(c, r, 0, TAU, 40, Color(0, 0, 0, 0.45), 1.5)


## Opção do Estúdio: todas do mesmo tamanho (arte em cima, nome embaixo).
class OptionTile extends Button:
	var item_id := ""
	var title := ""
	var subtitle := ""
	var art_kind := "color"
	var color := Color.WHITE
	## Acabamento (arte "finish"): mesmo índice de CarConfig.PAINT_FINISHES.
	var finish := 0
	var selected := false
	## Tooltip em cartão: título (padrão = nome), texto e linhas de valores.
	var tip_title := ""
	var tip_text := ""
	var tip_rows: Array = []
	## Galeria: selo de estado ("✓", "FALTA", "GRÁTIS") e peça que falta apagada.
	var badge := ""
	var badge_color := Color.WHITE
	var dim := false

	func _ready() -> void:
		custom_minimum_size = StudioPanel.TILE
		flat = true
		if tooltip_text == "":
			tooltip_text = title
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _make_custom_tooltip(_for_text: String) -> Object:
		return Retro.make_tooltip(tip_title if tip_title != "" else title, tip_text, tip_rows)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(Retro.c("surface_2"), 0.55))
		var art := Rect2(6, 6, size.x - 12, size.y - 36)
		draw_rect(art, Color(Retro.c("bg"), 0.55))
		var a_mul := 0.5 if dim else 1.0
		match art_kind:
			"livery":
				var cols := ShopCatalog.colors_of(item_id)
				var w := art.size.x
				var k := art.size.y * 0.35
				var xs := [0.0, w * 0.45, w * 0.72, w]
				for i in 3:
					var a: float = xs[i]
					var b: float = xs[i + 1]
					draw_colored_polygon(PackedVector2Array([art.position + Vector2(a + (k if i > 0 else 0.0), 0),
						art.position + Vector2(b + (k if i < 2 else 0.0), 0), art.position + Vector2(b, art.size.y),
						art.position + Vector2(a, art.size.y)]), Color(cols[i], a_mul))
				if not ShopCatalog.is_free(item_id):
					var rc: Color = ShopCatalog.RARITY_COLORS[ShopCatalog.item(item_id)["rarity"]]
					draw_rect(Rect2(art.position.x, art.end.y - 3, art.size.x, 3), rc)
			"color":
				draw_circle(art.get_center(), art.size.y * 0.36, Color(color, a_mul))
				draw_arc(art.get_center(), art.size.y * 0.36, 0, TAU, 32, Color(0, 0, 0, 0.45), 1.5)
			"glow":
				for g in 4:
					draw_circle(art.get_center(), art.size.y * (0.55 - g * 0.07), Color(color, 0.1))
				draw_circle(art.get_center(), art.size.y * 0.26, Color(color, a_mul))
			"finish":
				StudioPanel.draw_finish_ball(self, art.get_center(), art.size.y * 0.4, color, finish)
			"off":
				draw_arc(art.get_center(), art.size.y * 0.3, 0, TAU, 32, Retro.c("muted"), 2.0)
				draw_line(art.get_center() + Vector2(-12, 12), art.get_center() + Vector2(12, -12), Retro.c("muted"), 2.0)
			"part":
				draw_string(Retro.display(800), Vector2(art.position.x, art.get_center().y + 5), subtitle.to_upper(),
					HORIZONTAL_ALIGNMENT_CENTER, art.size.x, 11, Retro.c("accent_2"))
		draw_string(Retro.body(600), Vector2(8, size.y - 11), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 13,
			Retro.c("text") if selected else Retro.c("text_2"))
		if badge != "":
			var f := Retro.display(800)
			var bw := f.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 10
			var br := Rect2(size.x - bw - 8, 9, bw, 15)
			draw_rect(br, Color(Retro.c("bg"), 0.85))
			draw_rect(br, badge_color, false, 1.0)
			draw_string(f, br.position + Vector2(5, 11), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, badge_color)
		if selected:
			draw_rect(r.grow(1.0), Color(Retro.c("accent"), 0.3))
			draw_rect(r, Retro.c("accent"), false, 2.0)
		elif is_hovered():
			draw_rect(r, Retro.line(3), false, 1.0)
		else:
			draw_rect(r, Retro.line(1), false, 1.0)
		if has_focus():
			draw_rect(r.grow(3.0), Retro.c("accent_2"), false, 2.0)


## Aba da coluna: só o ícone (desenhado à mão), nome no tooltip.
class IconTab extends Button:
	var icon_kind := "livery"
	var selected := false
	var tint := Color.WHITE
	var tip_text := ""
	var tip_rows: Array = []

	func _ready() -> void:
		custom_minimum_size = Vector2(48, 48)
		flat = true
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _make_custom_tooltip(for_text: String) -> Object:
		return Retro.make_tooltip(for_text, tip_text, tip_rows)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if selected:
			draw_rect(r, Color(Retro.c("accent"), 0.28))
			draw_rect(Rect2(0, 0, 3, size.y), Retro.c("accent"))
		elif is_hovered():
			draw_rect(r, Color(Retro.c("accent"), 0.12))
		draw_rect(r, Retro.line(2 if selected else 1), false, 1.0)
		if has_focus():
			draw_rect(r.grow(2.0), Retro.c("accent_2"), false, 2.0)
		var c := size * 0.5
		var ink := Retro.c("text") if selected or is_hovered() else Retro.c("text_2")
		match icon_kind:
			"livery":
				var cols := [Retro.c("accent"), Color.WHITE, Retro.c("accent_2")]
				for i in 3:
					var x := c.x - 13 + i * 9
					draw_colored_polygon(PackedVector2Array([Vector2(x + 4, c.y - 11), Vector2(x + 11, c.y - 11), Vector2(x + 7, c.y + 11),
						Vector2(x, c.y + 11)]), cols[i])
			"primary", "secondary", "accent":
				# Gota de tinta na cor equipada + número do campo
				draw_circle(c + Vector2(0, 4), 8, tint)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-7, 1), c + Vector2(0, -12), c + Vector2(7, 1)]), tint)
				draw_arc(c + Vector2(0, 4), 8, 0.0, PI, 16, Color(0, 0, 0, 0.4), 1.0)
				var n: String = {"primary": "1", "secondary": "2", "accent": "3"}[icon_kind]
				draw_string(Retro.display(900), Vector2(size.x - 14, size.y - 6), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
			"helmet":
				draw_circle(c + Vector2(0, 1), 11, tint)
				draw_rect(Rect2(c + Vector2(-2, -3), Vector2(13, 6)), Retro.c("bg"))
				draw_rect(Rect2(c + Vector2(-11, 9), Vector2(22, 3)), tint.darkened(0.3))
			"suit":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-12, -8), c + Vector2(-4, -11), c + Vector2(4, -11), c + Vector2(12, -8),
					c + Vector2(9, -1), c + Vector2(6, -3), c + Vector2(6, 12), c + Vector2(-6, 12), c + Vector2(-6, -3), c + Vector2(-9, -1)]), tint)
			"rim":
				draw_circle(c, 12, Color(0.08, 0.08, 0.1))
				draw_arc(c, 8, 0, TAU, 24, tint, 3.0)
				for k in 5:
					var a := TAU * k / 5.0
					draw_line(c, c + Vector2(cos(a), sin(a)) * 8.0, tint, 2.0)
			"boost":
				draw_colored_polygon(PackedVector2Array([c + Vector2(3, -13), c + Vector2(-8, 2), c + Vector2(-1, 2), c + Vector2(-4, 13),
					c + Vector2(8, -3), c + Vector2(1, -3)]), tint)
			"neon":
				draw_rect(Rect2(c + Vector2(-13, -6), Vector2(26, 7)), ink)
				for g in 3:
					draw_line(c + Vector2(-12 + g * 2, 5 + g * 3), c + Vector2(12 - g * 2, 5 + g * 3), Color(tint, 0.9 - g * 0.25), 2.0)
			"finish":
				StudioPanel.draw_finish_ball(self, c, 12.0, Retro.c("accent"), 1)
			"engineering":
				# Chave inglesa
				draw_line(c + Vector2(-10, 10), c + Vector2(5, -5), ink, 4.0)
				draw_arc(c + Vector2(7, -7), 6.0, deg_to_rad(-200), deg_to_rad(70), 12, ink, 3.0)
			"parts":
				# Asa traseira: plano + placas laterais
				draw_rect(Rect2(c + Vector2(-13, -6), Vector2(26, 5)), ink)
				draw_rect(Rect2(c + Vector2(-14, -10), Vector2(3, 16)), ink)
				draw_rect(Rect2(c + Vector2(11, -10), Vector2(3, 16)), ink)
				draw_rect(Rect2(c + Vector2(-2, -1), Vector2(4, 11)), ink)


## Um parâmetro de engenharia, em duas linhas alinhadas com as outras:
##   nome ......................... valor  ↺   (↺ só aparece quando mudou do de fábrica)
##   (−) ━━━━━━━━━━●━━━━━|━━━━━━━━━ (+)        (a marca | é o valor de fábrica)
## Clique em −/+ = passo fino; com Shift = passo grosso. Todos os controles mostram o mesmo
## tooltip em cartão (explicação, valor atual, fábrica, limites e passos).
class SetupRow extends VBoxContainer:
	var param: Array
	var studio: StudioPanel
	var _slider: TipSlider
	var _value: Label
	var _reset: TipButton
	var _syncing := false

	func _ready() -> void:
		custom_minimum_size = Vector2(StudioPanel.TILE.x * 2 + 8, 52)
		add_theme_constant_override("separation", 4)
		var car := studio.car
		var d := float(CarSetup.defaults(car)[param[0]])
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		add_child(top)
		var name_l := TipLabel.new()
		name_l.text = param[2]
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.add_theme_font_size_override("font_size", 13)
		name_l.add_theme_color_override("font_color", Retro.c("text_2"))
		name_l.mouse_filter = Control.MOUSE_FILTER_STOP
		name_l.tooltip_text = param[2]
		name_l.make_tip = make_tip.bind("")
		top.add_child(name_l)
		_value = Label.new()
		_value.add_theme_font_override("font", Retro.display(700))
		_value.add_theme_font_size_override("font_size", 12)
		_value.custom_minimum_size = Vector2(78, 0)
		_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		top.add_child(_value)
		_reset = TipButton.new()
		_reset.text = "↺"
		_reset.flat = true
		_reset.focus_mode = Control.FOCUS_NONE
		_reset.tooltip_text = param[2]
		_reset.make_tip = make_tip.bind("volta ao de fábrica (%s)" % CarSetup.format(param, d))
		_reset.custom_minimum_size = Vector2(20, 18)
		_reset.add_theme_font_size_override("font_size", 13)
		_reset.add_theme_color_override("font_color", Retro.c("accent_2"))
		_reset.pressed.connect(func() -> void:
			studio._profile.reset_setup(param[0])
			studio._profile.apply_setup(car)
			_sync())
		top.add_child(_reset)
		var bottom := HBoxContainer.new()
		bottom.add_theme_constant_override("separation", 8)
		add_child(bottom)
		bottom.add_child(_step_button(-1.0))
		_slider = TipSlider.new()
		_slider.min_value = param[5]
		_slider.max_value = param[6]
		_slider.step = param[7]
		_slider.factory = d
		_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_slider.custom_minimum_size = Vector2(0, 20)
		_slider.tooltip_text = param[2]
		_slider.make_tip = make_tip.bind("arraste para ajustar · a marca é o valor de fábrica")
		_slider.value_changed.connect(_on_value)
		StudioPanel.style_slider(_slider)
		bottom.add_child(_slider)
		bottom.add_child(_step_button(1.0))
		studio._profile.setup_changed.connect(_sync)
		_sync()

	## Cartão do tooltip: explicação + valores (o atual em destaque se mudou do de fábrica).
	func make_tip(action: String) -> Control:
		var v := studio._profile.setup_value(studio.car, param[0])
		var d := float(CarSetup.defaults(studio.car)[param[0]])
		var changed := not is_equal_approx(v, d)
		var rows := [
			["Atual", CarSetup.format(param, v), Retro.c("accent_2") if changed else Retro.c("text")],
			["Fábrica", CarSetup.format(param, d)],
			["Limites", "%s  a  %s" % [CarSetup.format(param, param[5]), CarSetup.format(param, param[6])]],
			["Passo", "fino %s · grosso %s" % [CarSetup.format(param, param[7]), CarSetup.format(param, param[8])]],
		]
		if action != "":
			rows.append(["Este botão", action, Retro.c("warn")])
		return Retro.make_tooltip("%s · %s" % [param[1], param[2]], param[12], rows)

	## Botão redondo − / +: passo fino; com Shift, passo grosso.
	func _step_button(sign: float) -> TipButton:
		var b := TipButton.new()
		b.text = "+" if sign > 0.0 else "−"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(24, 24)
		b.add_theme_font_size_override("font_size", 14)
		StudioPanel.style_round_button(b)
		b.tooltip_text = param[2]
		b.make_tip = make_tip.bind("%s%s (Shift: %s%s)" % ["+" if sign > 0.0 else "−", CarSetup.format(param, float(param[7])),
			"+" if sign > 0.0 else "−", CarSetup.format(param, float(param[8]))])
		b.pressed.connect(func() -> void:
			var step: float = float(param[8]) if Input.is_key_pressed(KEY_SHIFT) else float(param[7])
			_slider.value = clampf(_slider.value + sign * step, param[5], param[6]))
		return b

	func _on_value(v: float) -> void:
		if _syncing:
			return
		studio._profile.set_setup_value(param[0], v)
		studio._profile.apply_setup(studio.car)
		_sync()

	func _sync() -> void:
		var v := studio._profile.setup_value(studio.car, param[0])
		var d := float(CarSetup.defaults(studio.car)[param[0]])
		_syncing = true
		_slider.value = v
		_syncing = false
		var changed := not is_equal_approx(v, d)
		_value.text = CarSetup.format(param, v)
		_value.add_theme_color_override("font_color", Retro.c("accent_2") if changed else Retro.c("text"))
		_reset.disabled = not changed
		_reset.modulate.a = 1.0 if changed else 0.0


## Trilho fino e escuro, parte preenchida na cor de destaque (sliders da engenharia).
static func style_slider(sl: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(Retro.c("bg"), 0.9)
	track.border_color = Color(Retro.c("muted"), 0.6)
	track.set_border_width_all(1)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	sl.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(Retro.c("accent"), 0.85)
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	sl.add_theme_stylebox_override("grabber_area", fill)
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = Retro.c("accent_2")
	sl.add_theme_stylebox_override("grabber_area_highlight", fill_hi)


## Botão redondo discreto (contorno fino; destaca no hover).
static func style_round_button(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(1)
		match state:
			"normal":
				sb.bg_color = Color(Retro.c("bg"), 0.6)
				sb.border_color = Color(Retro.c("muted"), 0.8)
			"hover":
				sb.bg_color = Color(Retro.c("accent"), 0.18)
				sb.border_color = Retro.c("accent_2")
			"pressed":
				sb.bg_color = Color(Retro.c("accent"), 0.4)
				sb.border_color = Retro.c("accent_2")
			"disabled":
				sb.bg_color = Color(Retro.c("bg"), 0.3)
				sb.border_color = Color(Retro.c("muted"), 0.3)
			"focus":
				sb.bg_color = Color(0, 0, 0, 0)
				sb.border_color = Color(0, 0, 0, 0)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Retro.c("text"))
	b.add_theme_color_override("font_hover_color", Retro.c("accent_2"))


## Controles com tooltip em cartão (o conteúdo vem de make_tip, montado na hora do hover).
class TipButton extends Button:
	var make_tip: Callable

	func _make_custom_tooltip(_for_text: String) -> Object:
		return make_tip.call() if make_tip.is_valid() else null


class TipSlider extends HSlider:
	var make_tip: Callable
	## Valor de fábrica: marca fina sobre o trilho.
	var factory := NAN

	func _make_custom_tooltip(_for_text: String) -> Object:
		return make_tip.call() if make_tip.is_valid() else null

	func _draw() -> void:
		if is_nan(factory) or max_value <= min_value:
			return
		var grab: float = float(get_theme_icon("grabber").get_width()) if has_theme_icon("grabber") else 12.0
		var t: float = (factory - min_value) / (max_value - min_value)
		var x: float = grab * 0.5 + t * (size.x - grab)
		draw_rect(Rect2(x - 1.0, size.y * 0.5 - 7.0, 2.0, 14.0), Color(Retro.c("text"), 0.55))


class TipLabel extends Label:
	var make_tip: Callable

	func _make_custom_tooltip(_for_text: String) -> Object:
		return make_tip.call() if make_tip.is_valid() else null
