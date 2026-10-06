class_name ShopPanel
extends VBoxContainer
## Loja: vende só tickets (um giro numa roleta, 2.500 créditos). Nenhum cosmético se compra
## diretamente: o que equipa o carro sai das roletas; as paletas da interface vêm com o jogo.
##
## As duas roletas lado a lado com a tabela de chances lida do mesmo catálogo do sorteio. O giro cobra e sorteia na hora; a animação dura no mínimo 2,2 s e mostra
## o resultado (nova ou repetida, com a devolução).

const MIN_SPIN_TIME := 2.2

var _profile: PlayerProfile
var _content: VBoxContainer
var _overlay: CanvasLayer
var _waiting := false
var _message: Label


func setup() -> void:
	_profile = get_node("/root/Profile") as PlayerProfile
	add_theme_constant_override("separation", 12)
	_message = Label.new()
	_message.add_theme_color_override("font_color", Retro.c("bad"))
	_message.visible = false
	add_child(_message)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_content)
	_build()


func _set_message(text: String) -> void:
	_message.text = text
	_message.visible = text != ""


func _build() -> void:
	for c in _content.get_children():
		c.queue_free()
	_build_tickets()


func _build_tickets() -> void:
	var intro := Label.new()
	intro.text = "Cada ticket é um giro: sorteia um degrau de raridade (fatia fixa) e, dentro dele, uma peça com chance igual. Repetida devolve 30% do preço de tabela. Sem pacotes e sem garantia: cada giro é independente."
	intro.theme_type_variation = "RetroMuted"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(intro)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_content.add_child(row)
	for rid in ShopCatalog.ROULETTES:
		row.add_child(_roulette_card(rid))


func _roulette_card(rid: String) -> Control:
	var info: Dictionary = ShopCatalog.ROULETTES[rid]
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := Retro.panel_style(16.0, 0.9)
	style.border_color = Color(info["color"], 0.55)
	style.shadow_color = Color(info["color"], 0.2)
	panel.add_theme_stylebox_override("panel", style)
	Retro.add_corners(panel, info["color"])
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := Label.new()
	title.text = str(info["name"]).to_upper()
	title.add_theme_font_override("font", Retro.display(800))
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", info["color"])
	box.add_child(title)
	var theme_l := Label.new()
	theme_l.text = "Tema: " + info["theme"]
	theme_l.theme_type_variation = "RetroMuted"
	box.add_child(theme_l)
	var have := 0
	var items := ShopCatalog.roulette_items(rid)
	for id in items:
		if _profile.owns(id):
			have += 1
	var col := Label.new()
	col.text = "Sua coleção nesta roleta: %d de %d" % [have, items.size()]
	col.add_theme_color_override("font_color", Retro.c("text_2"))
	box.add_child(col)
	# Tabela de chances (a mesma do sorteio)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	for h in ["RARIDADE", "FATIA", "PEÇAS", "CADA"]:
		var l := Label.new()
		l.text = h
		l.theme_type_variation = "RetroKicker"
		l.add_theme_font_size_override("font_size", 10)
		grid.add_child(l)
	for rarity in range(ShopCatalog.RARITY_WEIGHTS.size() - 1, -1, -1):
		var n := ShopCatalog.drops(rid, rarity).size()
		var cells := [ShopCatalog.RARITY_NAMES[rarity], _pct(ShopCatalog.RARITY_WEIGHTS[rarity] / 100.0),
			str(n), _pct(ShopCatalog.RARITY_WEIGHTS[rarity] / 100.0 / maxf(n, 1))]
		for i in cells.size():
			var l := Label.new()
			l.text = cells[i]
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_color_override("font_color", ShopCatalog.RARITY_COLORS[rarity] if i == 0 else Retro.c("text_2"))
			grid.add_child(l)
	box.add_child(grid)
	var b := Button.new()
	b.text = "GIRAR · %s" % PlayerProfile.format_credits(ShopCatalog.TICKET_PRICE)
	b.theme_type_variation = "PrimaryButton"
	b.custom_minimum_size = Vector2(0, 46)
	b.disabled = _profile.credits < ShopCatalog.TICKET_PRICE
	if b.disabled:
		b.tooltip_text = "Créditos insuficientes"
	b.pressed.connect(_spin.bind(rid))
	box.add_child(b)
	return panel


static func _pct(p: float) -> String:
	var v := p * 100.0
	return (("%.1f" if v >= 10.0 or is_equal_approx(v, roundf(v * 10.0) / 10.0) else "%.2f") % v).replace(".", ",") + "%"


# ---------------------------------------------------------------------------
# Giro
# ---------------------------------------------------------------------------
func _spin(rid: String) -> void:
	if _overlay or _waiting:
		return
	var res: Dictionary
	if _profile.mode == "remote":
		# Conectado: o giro é do servidor (créditos, sorteio e coleção ficam lá)
		_waiting = true
		_set_message("Girando…")
		res = await get_node("/root/Net").request("spin", {"roulette": rid})
		_waiting = false
		if not is_inside_tree():
			return
	else:
		res = _profile.spin(rid)
	if not res["ok"]:
		_set_message(res["error"])
		return
	_set_message("")
	var overlay := SpinOverlay.new()
	overlay.roulette = rid
	overlay.result = res
	overlay.panel = self
	_overlay = overlay
	get_tree().root.add_child(overlay)


func _on_overlay_closed(again: String) -> void:
	_overlay = null
	_build()
	if again != "":
		_spin(again)


## Cena do giro: carrossel que desacelera por no mínimo 2,2 s e para no prêmio; depois o cartão
## grande com "NOVA!" ou "REPETIDA · +créditos" e os botões.
class SpinOverlay extends CanvasLayer:
	var roulette := ""
	var result := {}
	var panel: ShopPanel
	var _t := 0.0
	var _done := false
	var _pool: Array[String] = []
	var _strip: Control
	var _reveal: Control

	func _ready() -> void:
		layer = 110
		process_mode = Node.PROCESS_MODE_ALWAYS
		var bg := Retro.backdrop(0.92)
		bg.theme = Retro.theme()
		add_child(bg)
		_pool = ShopCatalog.roulette_items(roulette)
		_strip = Control.new()
		_strip.set_anchors_preset(Control.PRESET_FULL_RECT)
		_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_strip.draw.connect(_draw_strip)
		bg.add_child(_strip)

	func _process(delta: float) -> void:
		_t += delta
		_strip.queue_redraw()
		if not _done and _t >= ShopPanel.MIN_SPIN_TIME:
			_done = true
			_show_result()

	## Posição do carrossel: desacelera (ease out) e para exatamente no prêmio.
	func _draw_strip() -> void:
		var vp := _strip.size
		var info: Dictionary = ShopCatalog.ROULETTES[roulette]
		Retro.draw_glow_text(_strip, Retro.display(900), Vector2(0, vp.y * 0.2), str(info["name"]).to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 34, Retro.c("text"), info["color"])
		if _done:
			return
		var card_w := 190.0
		var gap := 16.0
		var spins := 34.0
		var t := clampf(_t / ShopPanel.MIN_SPIN_TIME, 0.0, 1.0)
		var pos := spins * (1.0 - pow(1.0 - t, 3.0))
		var center := Vector2(vp.x * 0.5, vp.y * 0.5)
		var target_index := _pool.find(result["item"])
		for k in range(-4, 5):
			var slot := int(floor(pos)) + k
			var frac: float = pos - floor(pos)
			var x: float = center.x + (k - frac) * (card_w + gap)
			# Os últimos cartões param no prêmio: o índice final cai no item sorteado
			var idx := posmod(target_index - int(spins) + slot, _pool.size())
			var r := Rect2(x - card_w * 0.5, center.y - 90, card_w, 180)
			var it := ShopCatalog.item(_pool[idx])
			var rc: Color = ShopCatalog.RARITY_COLORS[it["rarity"]]
			Retro.draw_panel(_strip, r, 0.92, false)
			_strip.draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), rc)
			GalleryPanel.ItemCard.draw_art(_strip, _pool[idx], Rect2(r.position + Vector2(12, 18), Vector2(r.size.x - 24, 80)), true)
			_strip.draw_string(Retro.body(700), r.position + Vector2(12, 124), it["name"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24, 14,
				Retro.c("text"))
			_strip.draw_string(Retro.display(700), r.position + Vector2(12, 146), str(ShopCatalog.RARITY_NAMES[it["rarity"]]).to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, rc)
		# Marcador central
		_strip.draw_rect(Rect2(center.x - 2, center.y - 112, 4, 224), Retro.c("accent"))
		_strip.draw_colored_polygon(PackedVector2Array([center + Vector2(-12, -122), center + Vector2(12, -122), center + Vector2(0, -104)]),
			Retro.c("accent"))

	func _show_result() -> void:
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		get_child(0).add_child(center)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 14)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		center.add_child(box)
		var dup: bool = result["dup"]
		var rarity: int = result["rarity"]
		var head := Label.new()
		head.text = "REPETIDA · +%s %s" % [PlayerProfile.format_credits(result["refund"]), ShopCatalog.CURRENCY] if dup else "NOVA PEÇA!"
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_font_override("font", Retro.display(900))
		head.add_theme_font_size_override("font_size", 30)
		head.add_theme_color_override("font_color", Retro.c("warn") if dup else ShopCatalog.RARITY_COLORS[rarity])
		head.add_theme_color_override("font_shadow_color", Color(ShopCatalog.RARITY_COLORS[rarity], 0.5))
		head.add_theme_constant_override("shadow_outline_size", 18)
		head.add_theme_constant_override("shadow_offset_x", 0)
		head.add_theme_constant_override("shadow_offset_y", 0)
		box.add_child(head)
		var card := GalleryPanel.ItemCard.new()
		card.item_id = result["item"]
		card.owned = true
		card.big = true
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(card)
		var buttons := HBoxContainer.new()
		buttons.alignment = BoxContainer.ALIGNMENT_CENTER
		buttons.add_theme_constant_override("separation", 12)
		box.add_child(buttons)
		var profile := panel._profile
		var again := Button.new()
		again.text = "GIRAR DE NOVO · %s" % PlayerProfile.format_credits(ShopCatalog.TICKET_PRICE)
		again.theme_type_variation = "PrimaryButton"
		again.custom_minimum_size = Vector2(260, 46)
		again.disabled = profile.credits < ShopCatalog.TICKET_PRICE
		again.pressed.connect(_close.bind(roulette))
		buttons.add_child(again)
		again.grab_focus.call_deferred()
		var ok := Button.new()
		ok.text = "Fechar"
		ok.custom_minimum_size = Vector2(160, 46)
		ok.pressed.connect(_close.bind(""))
		buttons.add_child(ok)
		var wallet := Label.new()
		wallet.text = "Saldo: %s %s" % [PlayerProfile.format_credits(profile.credits), ShopCatalog.CURRENCY]
		wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wallet.theme_type_variation = "RetroMuted"
		box.add_child(wallet)
		# Cartão entra com um "pop"
		card.pivot_offset = card.custom_minimum_size * 0.5
		card.scale = Vector2(0.6, 0.6)
		create_tween().tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _unhandled_input(event: InputEvent) -> void:
		if _done and event.is_action_pressed("ui_cancel"):
			_close("")
			get_viewport().set_input_as_handled()

	func _close(again: String) -> void:
		queue_free()
		if is_instance_valid(panel):
			panel._on_overlay_closed(again)
