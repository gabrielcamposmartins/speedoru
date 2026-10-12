class_name GalleryPanel
extends HBoxContainer
## Galeria: a coleção do jogador (não vende nada), no mesmo layout do Estúdio: coluna de abas só
## com ícones (um por tipo colecionável) e grade de 2 colunas com opções do mesmo tamanho.
##
## Responde "o que me falta e onde consigo": cada peça mostra a arte, a raridade e o estado
## ("✓" sua, "FALTA", "GRÁTIS"). Clicar numa peça mostra no carro como ficaria (sem equipar; a
## câmera vai até a peça) e o cartão de detalhes: raridade, roleta onde cai, chance exata, quanto
## devolve se sair repetida e o botão Equipar (se for sua) ou Ir à loja (se faltar).

const TYPE_ICONS := {"part": "parts", "decal": "decals", "boost": "boost", "neon": "neon", "trail": "trail"}

var type := "part"
var selected_id := ""
## Menu principal (prévia no carro); pode ser null.
var menu: Node
## Chamado com o id da roleta quando o jogador quer ir à loja girar.
var on_go_shop: Callable

var _profile: PlayerProfile
var _tabs: VBoxContainer
var _title: Label
var _note: Label
var _details: VBoxContainer
var _grid: GridContainer


func setup(p_menu: Node = null) -> void:
	menu = p_menu
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
	right.add_child(_title)
	_note = Label.new()
	_note.theme_type_variation = "RetroMuted"
	_note.add_theme_font_size_override("font_size", 12)
	right.add_child(_note)
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 4)
	_details.custom_minimum_size = Vector2(StudioPanel.TILE.x * 2 + 8, 0)
	right.add_child(_details)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	right.add_child(_grid)
	if not _profile.changed.is_connected(_rebuild_deferred):
		_profile.changed.connect(_rebuild_deferred)
	_rebuild()


func _rebuild_deferred() -> void:
	_rebuild.call_deferred()


func _rebuild() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	for t in ShopCatalog.TYPES:
		var tab := StudioPanel.IconTab.new()
		tab.icon_kind = TYPE_ICONS[t[0]]
		var count := _profile.collection_count(t[0])
		tab.tooltip_text = t[1]
		tab.tip_text = "%d de %d na sua coleção (as que vêm com o jogo não contam)." % [count.x, count.y]
		tab.selected = t[0] == type
		tab.tint = Retro.c("text_2")
		tab.pressed.connect(func() -> void:
			type = t[0]
			selected_id = ""
			_rebuild())
		_tabs.add_child(tab)
	var count := _profile.collection_count(type)
	_title.text = str(ShopCatalog.type_info(type)[1]).to_upper()
	_note.text = "%d de %d · as que vêm com o jogo não contam" % [count.x, count.y]
	_build_details()
	for c in _grid.get_children():
		c.queue_free()
	var ids := ShopCatalog.items_of_type(type)
	if type == "part":
		_build_parts(ids)
		return
	for id in ids:
		_grid.add_child(_tile(id))


## Peças separadas por categoria (como no Estúdio): título do lugar do carro com quantas a conta
## tem (as que vêm com o jogo não contam) e as peças dele.
func _build_parts(ids: Array[String]) -> void:
	for slot in CarPartCatalog.all_slots():
		var of_slot := ids.filter(func(id: String) -> bool: return ShopCatalog.item(id).get("slot", "") == slot)
		if of_slot.is_empty():
			continue
		var have := 0
		var total := 0
		for id: String in of_slot:
			if not ShopCatalog.is_free(id):
				total += 1
				have += 1 if _profile.owns(id) else 0
		var head := Label.new()
		head.text = "%s · %d de %d" % [CarPartCatalog.slot_label(slot).to_upper(), have, total]
		head.theme_type_variation = "RetroKicker"
		head.add_theme_font_size_override("font_size", 11)
		_grid.add_child(head)
		_grid.add_child(Control.new())
		for id: String in of_slot:
			_grid.add_child(_tile(id))
		if of_slot.size() % 2 == 1:
			_grid.add_child(Control.new())


func _tile(id: String) -> StudioPanel.OptionTile:
	var it := ShopCatalog.item(id)
	var owned := _profile.owns(id)
	var t := StudioPanel.OptionTile.new()
	t.item_id = id
	t.title = it["name"]
	match it["type"]:
		"livery":
			t.art_kind = "livery"
		"boost", "neon":
			t.art_kind = "glow"
		"trail":
			t.art_kind = "trail"
		"part":
			t.art_kind = "part"
			t.part_slot = it["slot"]
			t.part_variant = it["variant"]
		"decal":
			t.art_kind = "decal"
			t.decal = CarDecals.texture(ShopCatalog.decal_of(id))
			t.color = Color.WHITE
		_:
			t.art_kind = "color"
	var cols := ShopCatalog.colors_of(id)
	if not cols.is_empty() and it["type"] != "decal":
		t.color = cols[0]
	t.selected = id == selected_id
	t.dim = not owned
	if ShopCatalog.is_free(id):
		t.badge = "GRÁTIS"
		t.badge_color = Retro.c("muted")
	elif owned:
		t.badge = "✓"
		t.badge_color = Retro.c("good")
	else:
		t.badge = "FALTA"
		t.badge_color = ShopCatalog.RARITY_COLORS[it["rarity"]]
	t.tip_text = "Clique para ver no carro."
	t.tip_rows = _tip_rows(id, owned)
	t.pressed.connect(_select.bind(id))
	return t


func _tip_rows(id: String, owned: bool) -> Array:
	if ShopCatalog.is_free(id):
		return [["Estado", "já vem com o jogo", Retro.c("muted")]]
	var it := ShopCatalog.item(id)
	return [
		["Raridade", ShopCatalog.RARITY_NAMES[it["rarity"]], ShopCatalog.RARITY_COLORS[it["rarity"]]],
		["Estado", "sua" if owned else "falta", Retro.c("good") if owned else Retro.c("warn")],
		["Roleta", ShopCatalog.ROULETTES[it["roulette"]]["name"]],
		["Chance", ShopPanel._pct(ShopCatalog.chance_of(id)) + " por giro"],
		["Repetida", "devolve %s" % PlayerProfile.format_credits(ShopCatalog.refund_of(id))],
	]


func _select(id: String) -> void:
	selected_id = id
	if menu and menu.has_method("preview_item"):
		menu.preview_item(id)
	_rebuild()


## Cartão de detalhes da peça selecionada.
func _build_details() -> void:
	for c in _details.get_children():
		c.queue_free()
	if selected_id == "":
		var hint := Label.new()
		hint.text = "Clique numa peça para ver no carro."
		hint.theme_type_variation = "RetroMuted"
		_details.add_child(hint)
		return
	var it := ShopCatalog.item(selected_id)
	var free := ShopCatalog.is_free(selected_id)
	var owned := _profile.owns(selected_id)
	var name_l := Label.new()
	name_l.text = it["name"]
	name_l.add_theme_font_override("font", Retro.body(700))
	name_l.add_theme_font_size_override("font_size", 17)
	_details.add_child(name_l)
	var rarity_l := Label.new()
	rarity_l.add_theme_font_override("font", Retro.display(700))
	rarity_l.add_theme_font_size_override("font_size", 11)
	if free:
		rarity_l.text = "GRÁTIS · JÁ VEM COM O JOGO"
		rarity_l.add_theme_color_override("font_color", Retro.c("muted"))
	else:
		rarity_l.text = "%s · %s" % [str(ShopCatalog.RARITY_NAMES[it["rarity"]]).to_upper(), str(ShopCatalog.ROULETTES[it["roulette"]]["name"]).to_upper()]
		rarity_l.add_theme_color_override("font_color", ShopCatalog.RARITY_COLORS[it["rarity"]])
	_details.add_child(rarity_l)
	if not free:
		var info := Label.new()
		info.text = "%s · chance %s por giro · repetida devolve %s" % ["✓ Sua" if owned else "Falta",
			ShopPanel._pct(ShopCatalog.chance_of(selected_id)), PlayerProfile.format_credits(ShopCatalog.refund_of(selected_id))]
		info.add_theme_font_size_override("font_size", 12)
		info.add_theme_color_override("font_color", Retro.c("good") if owned else Retro.c("text_2"))
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_details.add_child(info)
	if it["type"] == "part":
		var st := Label.new()
		st.text = _stats_text(it["slot"], it["variant"])
		st.theme_type_variation = "RetroMuted"
		st.add_theme_font_size_override("font_size", 12)
		_details.add_child(st)
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 34)
	if owned:
		b.text = "EQUIPAR"
		b.theme_type_variation = "PrimaryButton"
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_equip.bind(selected_id))
	else:
		b.text = "Girar na %s" % ShopCatalog.ROULETTES[it["roulette"]]["name"]
		b.pressed.connect(func() -> void:
			if on_go_shop.is_valid():
				on_go_shop.call(it["roulette"]))
	_details.add_child(b)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 10)
	_details.add_child(sep)


func _equip(id: String) -> void:
	var it := ShopCatalog.item(id)
	var cols := ShopCatalog.colors_of(id)
	match it["type"]:
		"livery":
			_profile.equip_livery(id)
		"neon":
			_profile.equip_color("neon", cols[0])
			_profile.set_neon(true)
		"part":
			_profile.equip_part(it["slot"], it["variant"])
		"decal":
			# Nas laterais (o lugar mais visível); o Estúdio troca de lugar, cor, posição e tamanho
			_profile.set_decal("sidepods", ShopCatalog.decal_of(id))
		_:
			_profile.equip_color(it["type"], cols[0])


func _stats_text(slot: String, variant: String) -> String:
	var st := CarPartCatalog.variant_stats(slot, variant)
	if st.is_empty():
		return "Peça de referência"
	var parts := PackedStringArray()
	if st.has("downforce"):
		parts.append("downforce %+.2f m²" % st["downforce"])
	if st.has("drag"):
		parts.append("arrasto %+.2f m²" % st["drag"])
	if st.has("balance"):
		parts.append("balanço %+d%%" % roundi(st["balance"] * 100.0))
	return ", ".join(parts)


## Cartão de uma peça (usado no resultado do giro da loja, grande).
class ItemCard extends Control:
	var item_id := ""
	var owned := false
	var big := false

	func _ready() -> void:
		custom_minimum_size = Vector2(300, 260) if big else Vector2(176, 168)
		mouse_filter = Control.MOUSE_FILTER_PASS
		Retro.events.changed.connect(queue_redraw)
		PartSilhouette.notifier().rendered.connect(queue_redraw)

	func _draw() -> void:
		var it := ShopCatalog.item(item_id)
		var free := ShopCatalog.is_free(item_id)
		var rarity := -1 if free else int(it["rarity"])
		var rc: Color = Retro.c("muted") if rarity < 0 else ShopCatalog.RARITY_COLORS[rarity]
		var r := Rect2(Vector2.ZERO, size)
		Retro.draw_panel(self, r, 0.9, owned and rarity >= 3)
		draw_rect(Rect2(0, 0, size.x, 3), rc)
		var s := 1.7 if big else 1.0
		var art := Rect2(10 * s, 12 * s, size.x - 20 * s, 66 * s)
		ItemCard.draw_art(self, item_id, art, owned)
		var stamp := "GRÁTIS" if free else str(ShopCatalog.RARITY_NAMES[rarity]).to_upper()
		var font := Retro.display(800)
		var fs := int(10 * s)
		var w := font.get_string_size(stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14
		var st := Rect2(art.position + Vector2(4, 4), Vector2(w, 16 * s))
		draw_rect(st, Color(Retro.c("bg"), 0.85))
		draw_rect(st, rc, false, 1.0)
		draw_string(font, st.position + Vector2(7, 12 * s), stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, rc)
		var y := art.end.y + 18 * s
		draw_string(Retro.body(700), Vector2(10 * s, y), it.get("name", item_id), HORIZONTAL_ALIGNMENT_LEFT, size.x - 20 * s,
			int(14 * s), Retro.c("text"))
		y += 15 * s
		var type_name: String = ShopCatalog.type_info(it.get("type", ""))[1]
		draw_string(Retro.body(500), Vector2(10 * s, y), type_name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), Retro.c("muted"))
		y += 18 * s
		var body := Retro.body(600)
		if free:
			draw_string(body, Vector2(10 * s, y), "Já vem com o jogo", HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s), Retro.c("text_2"))
		elif owned:
			draw_string(body, Vector2(10 * s, y), "✓ Sua", HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s), Retro.c("good"))
			draw_string(body, Vector2(10 * s, y + 15 * s), "repetida devolve %s" % PlayerProfile.format_credits(ShopCatalog.refund_of(item_id)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * s), Retro.c("muted"))

	## Arte de uma peça: pintura = faixas diagonais; cor = disco com brilho; peça = silhueta branca
	## (o nome do lugar enquanto ela não fica pronta).
	static func draw_art(ci: CanvasItem, id: String, art: Rect2, owned: bool) -> void:
		var it := ShopCatalog.item(id)
		ci.draw_rect(art, Color(Retro.c("bg"), 0.7))
		var dim := 1.0 if owned or ShopCatalog.is_free(id) else 0.55
		var cols := ShopCatalog.colors_of(id)
		match it.get("type", ""):
			"livery":
				var w := art.size.x
				var k := art.size.y * 0.35
				var xs := [0.0, w * 0.45, w * 0.72, w]
				for i in 3:
					var a: float = xs[i]
					var b: float = xs[i + 1]
					ci.draw_colored_polygon(PackedVector2Array([art.position + Vector2(a + (k if i > 0 else 0.0), 0),
						art.position + Vector2(b + (k if i < 2 else 0.0), 0), art.position + Vector2(b, art.size.y),
						art.position + Vector2(a, art.size.y)]), Color(cols[i], dim))
			"decal":
				var tex := CarDecals.texture(ShopCatalog.decal_of(id))
				if tex:
					var aspect := float(tex.get_width()) / maxf(tex.get_height(), 1.0)
					var box := art.grow(-8.0)
					var w := minf(box.size.x, box.size.y * aspect)
					ci.draw_texture_rect(tex, Rect2(box.get_center() - Vector2(w, w / aspect) * 0.5, Vector2(w, w / aspect)), false,
						Color(1, 1, 1, dim))
			"trail":
				# Abaixo do selo de raridade
				CarParticles.draw_icon(ci, ShopCatalog.effect_of(id), Rect2(art.position.x, art.position.y + art.size.y * 0.22,
					art.size.x, art.size.y * 0.78), dim)
			"part":
				# Abaixo do selo de raridade
				var box := Rect2(art.position.x + 8.0, art.position.y + art.size.y * 0.32, art.size.x - 16.0, art.size.y * 0.6)
				if not PartSilhouette.draw(ci, it["slot"], it["variant"], box, Color(1, 1, 1, dim)):
					ci.draw_string(Retro.display(800), art.position + Vector2(0, art.size.y * 0.62),
						CarPartCatalog.slot_label(it["slot"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, art.size.x,
						int(art.size.y * 0.2), Color(Retro.c("accent_2"), dim))
			_:
				var c := art.get_center()
				var rad := art.size.y * 0.36
				if it["type"] in ["boost", "neon"]:
					for g in 4:
						ci.draw_circle(c, rad * (1.6 - g * 0.15), Color(cols[0], 0.08 * dim))
				ci.draw_circle(c, rad, Color(cols[0], dim))
				ci.draw_arc(c, rad, 0, TAU, 40, Color(0, 0, 0, 0.4), 2.0)
