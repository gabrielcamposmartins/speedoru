class_name StudioPanel
extends HBoxContainer
## Estúdio: cores livres (seletor + sugestões) e o que a conta tem de peças e decalques. Usado na garagem do menu
## principal (painel à direita, carro em foco) e no painel da garagem durante a corrida (Tab).
##
## Layout compacto: uma coluna de abas só com ícones (o nome aparece no topo e no tooltip) e uma
## grade de 2 colunas em que toda opção tem o mesmo tamanho (TILE).
## * Pinturas prontas (grátis) aplicam as 3 cores de uma vez; cada cor (carro, capacete, macacão,
##   rodas) é livre: seletor de qualquer cor e sugestões. Boost e neon: as cores ganhas nas roletas.
## * Peças: as variantes ganhas (a padrão sempre), com o efeito na aerodinâmica no tooltip.
## * Engenharia: o comportamento do carro (aerodinâmica, freios, pneus, direção, câmbio,
##   suspensão, assistências), com slider, ajuste grosso/fino e explicação de cada parâmetro.
## * Decalques: SVG (padrão ganho ou da pasta do jogador) em cada lugar do carro, com cor livre
##   (seletor), e posição/tamanho/largura/giro numa prévia do lugar (arrastar e roda) ou nos sliders;
##   a câmera da garagem vai até o lugar (focus_request).
## * Skin: exporta o MOLDE (o carro planificado, CarSkinTemplate) para pintar num editor de imagem
##   e importa a pintura (CarSkin), que vale por cima das cores e aparece também online.
## Cada escolha vai para o Profile (que confere e salva) e para o carro na hora.

const TILE := Vector2(148, 92)
const CATEGORIES := [
	["engineering", "Engenharia"],
	["livery", "Pinturas"],
	["scheme", "Esquema de pintura"],
	["finish", "Acabamento"],
	["decals", "Decalques"],
	["skin", "Skin (pintura livre)"],
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
	"livery": "Pinturas prontas (grátis). Uma pintura aplica as 3 cores do carro de uma vez.",
	"scheme": "Como as 3 cores se dividem pelo carro: faixas, diagonal, metades, flechas, ondas, camuflagem… Todos vêm com o jogo.",
	"finish": "Acabamento da pintura (brilhante, metálico, perolado, acetinado, fosco, cromado) e das rodas. Todos vêm com o jogo.",
	"decals": "Adesivos SVG nas laterais, no bico, na entrada de ar e na asa traseira, na cor, posição e tamanho que você quiser. Ganhe mais nas roletas ou use os seus próprios SVGs.",
	"skin": "Pinte o carro inteiro num editor de imagem: exporte o molde, pinte por cima e importe. Aparece para todos online.",
	"primary": "Cor principal do carro: qualquer cor.",
	"secondary": "Cor secundária do carro: qualquer cor.",
	"accent": "Cor de destaque (detalhes e faixas): qualquer cor.",
	"helmet": "Cor do capacete do piloto.",
	"suit": "Cor do macacão do piloto.",
	"rim": "Cor das rodas.",
	"boost": "Cor do brilho das rodas, do rastro e das partículas quando o boost está ligado. Ganhe mais cores nas roletas.",
	"neon": "Luz de neon embaixo do carro (fica mais forte à noite). As cores saem nas roletas.",
	"parts": "Peças de desempenho que você ganhou: trocam aderência por velocidade.",
}

var car: F1Car
var category := "engineering"
## Lugar do carro escolhido na aba de decalques.
var decal_slot := "sidepods"

## Ajustes do decalque (sliders): [rótulo, chave, mín, máx, passo, formato, multiplicador, padrão].
const DECAL_SLIDERS := [
	["TAMANHO", "scale", 0.2, 2.5, 0.05, "%d%%", 100.0, 1.0],
	["LARGURA", "stretch", 0.4, 2.5, 0.05, "%d%%", 100.0, 1.0],
	["GIRO", "rot", -180.0, 180.0, 5.0, "%d°", 1.0, 0.0],
	["HORIZONTAL", "x", -1.0, 1.0, 0.02, "%d", 100.0, 0.0],
	["VERTICAL", "y", -1.0, 1.0, 0.02, "%d", 100.0, 0.0],
]
## Lugar do decalque → ponto da câmera da garagem (MainMenu.FOCUS).
const DECAL_FOCUS := {"sidepods": "sidepods", "nose": "nose", "airbox": "airbox", "wing": "rear_wing"}

## Pede à garagem para levar a câmera até um ponto do carro ("" = volta à órbita).
signal focus_request(key: String)

var _profile: PlayerProfile
var _tabs: VBoxContainer
var _title: Label
var _note: Label
var _grid: GridContainer
## Aba de decalques: prévia do lugar e sliders (atualizados juntos sem reconstruir a tela).
var _pad: PositionPad
var _decal_sliders := {}


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
	if not _profile.decals_changed.is_connected(_on_decals_changed):
		_profile.decals_changed.connect(_on_decals_changed)
	_build()


## Cor/tamanho/giro de decalque (sliders): só o carro, sem reconstruir a tela.
func _on_decals_changed() -> void:
	if car and car.config:
		_profile.apply_to_config(car.config)
	_sync_decal_controls()


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
			var was_decals := category == "decals"
			category = cat[0]
			if category == "decals" and not was_decals:
				focus_request.emit(DECAL_FOCUS.get(decal_slot, ""))
			elif was_decals:
				focus_request.emit("")
			_build())
		_tabs.add_child(t)
	for c in _grid.get_children():
		c.queue_free()
	_pad = null
	_decal_sliders.clear()
	_grid.columns = 1 if category in ["engineering", "decals", "skin"] else 2
	var eq := _profile.equipped
	for cat in CATEGORIES:
		if cat[0] == category:
			_title.text = str(cat[1]).to_upper()
	match category:
		"livery":
			_note.text = "%d pinturas prontas · grátis · aplica as 3 cores" % ShopCatalog.PAINTS.size()
			for id in ShopCatalog.PAINTS:
				_tile(id, ShopCatalog.PAINTS[id]["name"], eq["livery"] == id, _profile.equip_livery.bind(id))
		"primary", "secondary", "accent", "helmet", "suit", "rim":
			_note.text = "qualquer cor · seletor ou sugestões"
			_color_tiles(category)
		"boost":
			var have := _profile.collection_count("boost")
			_note.text = "%d de %d cores ganhas · mais nas roletas" % [have.x, have.y]
			for c in _profile.owned_colors("boost"):
				var t := OptionTile.new()
				t.item_id = c[0]
				t.title = c[1]
				t.art_kind = "glow"
				t.color = c[2]
				t.selected = str(eq["boost"]) == (c[2] as Color).to_html(false)
				t.pressed.connect(_profile.equip_color.bind("boost", c[2]))
				_add(t)
		"neon":
			var have := _profile.collection_count("neon")
			_note.text = ("%d de %d cores ganhas · fica mais forte à noite" % [have.x, have.y]) if have.x > 0 \
				else "nenhum neon ainda · ganhe nas roletas Neon e Inferno"
			var off := OptionTile.new()
			off.title = "Desligado"
			off.art_kind = "off"
			off.selected = not eq["neon_on"]
			off.pressed.connect(_profile.set_neon.bind(false))
			_add(off)
			for c in _profile.owned_colors("neon"):
				var col: Color = c[2]
				var t := OptionTile.new()
				t.item_id = c[0]
				t.title = c[1]
				t.art_kind = "glow"
				t.color = col
				t.selected = eq["neon_on"] and str(eq["neon"]) == col.to_html(false)
				t.pressed.connect(func() -> void:
					_profile.equip_color("neon", col)
					_profile.set_neon(true))
				_add(t)
		"scheme":
			_note.text = "como as 3 cores se dividem · todos grátis"
			var cols := [Color(str(eq["primary"])), Color(str(eq["secondary"])), Color(str(eq["accent"]))]
			for k in CarConfig.PAINT_SCHEMES.size():
				var t := OptionTile.new()
				t.title = CarConfig.PAINT_SCHEMES[k][0]
				t.art_kind = "scheme"
				t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				t.scheme = k
				t.scheme_cols = cols
				t.tip_text = CarConfig.PAINT_SCHEMES[k][1]
				t.selected = int(eq.get("paint_scheme", 0)) == k
				t.pressed.connect(_profile.set_finish.bind("paint_scheme", k))
				_add(t)
		"engineering":
			_build_engineering()
		"finish":
			_note.text = "como a luz reflete na pintura e nas rodas"
			_build_finishes()
		"skin":
			_note.text = "pinte o carro inteiro numa imagem · aparece online"
			_build_skin()
		"decals":
			_note.text = "%d de %d decalques · ganhe mais nas roletas · seus SVGs são livres" % [
				_profile.owned_decals().size(), CarDecals.PRESETS.size()]
			_build_decals()
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


func _build_decals() -> void:
	var decals: Dictionary = _profile.equipped["decals"]
	var row := row_box()
	row.add_child(_kicker("LUGAR"))
	var place := OptionButton.new()
	place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place.clip_text = true
	for k in CarDecals.SLOT_ORDER.size():
		var s: String = CarDecals.SLOT_ORDER[k]
		place.add_item(CarDecals.slot_label(s) + ("  ●" if decals.has(s) else ""))
		if s == decal_slot:
			place.selected = k
	place.item_selected.connect(func(i: int) -> void:
		decal_slot = CarDecals.SLOT_ORDER[i]
		focus_request.emit(DECAL_FOCUS.get(decal_slot, ""))
		_build())
	row.add_child(place)
	_grid.add_child(row)
	var cur: Dictionary = decals.get(decal_slot, {})
	if not cur.is_empty():
		_decal_controls(cur)
	_grid.add_child(_kicker("DESENHO"))
	var tiles := GridContainer.new()
	tiles.columns = 2
	tiles.add_theme_constant_override("h_separation", 8)
	tiles.add_theme_constant_override("v_separation", 8)
	_grid.add_child(tiles)
	var none := OptionTile.new()
	none.title = "Nenhum"
	none.art_kind = "off"
	none.selected = cur.is_empty()
	none.pressed.connect(_profile.set_decal.bind(decal_slot, ""))
	tiles.add_child(none)
	var tint := Color(str(cur.get("color", "ffffff")))
	var ids: Array = _profile.owned_decals()
	ids.append_array(CarDecals.custom_ids())
	for id: String in ids:
		var t := OptionTile.new()
		t.title = CarDecals.preset_name(id)
		t.subtitle = "seu SVG" if id.begins_with(CarDecals.CUSTOM_PREFIX) else ""
		t.art_kind = "decal"
		t.decal = CarDecals.texture(id)
		t.color = tint
		t.selected = str(cur.get("id", "")) == id
		t.tip_text = "Seu arquivo em decals/%s (só você vê online)." % id.substr(CarDecals.CUSTOM_PREFIX.length()) \
			if id.begins_with(CarDecals.CUSTOM_PREFIX) else "Decalque padrão."
		t.pressed.connect(_profile.set_decal.bind(decal_slot, id))
		tiles.add_child(t)
	var files := HBoxContainer.new()
	files.add_theme_constant_override("separation", 8)
	var open := Button.new()
	open.text = "Pasta dos meus SVG"
	open.add_theme_font_size_override("font_size", 12)
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.tooltip_text = "Coloque arquivos .svg (desenho branco, fundo transparente) nesta pasta e clique em Recarregar."
	open.pressed.connect(func() -> void: OS.shell_open(CarDecals.ensure_user_dir()))
	files.add_child(open)
	var reload := Button.new()
	reload.text = "Recarregar"
	reload.add_theme_font_size_override("font_size", 12)
	reload.pressed.connect(func() -> void:
		CarDecals.clear_cache()
		if car and car.assembly:
			car.assembly.refresh_decals()
		_build())
	files.add_child(reload)
	_grid.add_child(files)


## Skin: molde para pintar, importar, tirar e as skins já importadas neste aparelho.
func _build_skin() -> void:
	var current := str(_profile.equipped.get("skin", ""))
	var help := Label.new()
	help.text = "1. Exporte o molde: o seu carro planificado (lados, cima, frente e trás).\n2. Pinte por cima num editor de imagem (Krita, Photoshop, GIMP…), em camadas se quiser.\n3. Importe a imagem (PNG). O que ficar transparente mostra as cores e o esquema."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(TILE.x * 2 + 8, 0)
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Retro.c("text_2"))
	_grid.add_child(help)
	var row := row_box()
	var export := Button.new()
	export.text = "Exportar molde…"
	export.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export.tooltip_text = "Salva um PNG 2048×2048 com o carro como está agora (cores, esquema e skin atual)."
	export.pressed.connect(_export_template)
	row.add_child(export)
	var import := Button.new()
	import.text = "Importar skin…"
	import.theme_type_variation = "PrimaryButton"
	import.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import.tooltip_text = "PNG, JPG ou WebP pintado sobre o molde (o ideal é 2048×2048)."
	import.pressed.connect(_import_skin)
	row.add_child(import)
	_grid.add_child(row)
	if current != "":
		var off := Button.new()
		off.text = "Tirar a skin (volta às cores)"
		off.pressed.connect(_profile.set_skin.bind(""))
		_grid.add_child(off)
	var own := CarSkin.own_skins()
	if current != "" and not current in own:
		own.push_front(current)
	if own.is_empty():
		return
	_grid.add_child(_kicker("SUAS SKINS"))
	var tiles := GridContainer.new()
	tiles.columns = 2
	tiles.add_theme_constant_override("h_separation", 8)
	tiles.add_theme_constant_override("v_separation", 8)
	_grid.add_child(tiles)
	for h: String in own.slice(0, 8):
		var tex := CarSkin.texture(h)
		var b := Button.new()
		b.custom_minimum_size = TILE
		b.toggle_mode = true
		b.button_pressed = h == current
		b.tooltip_text = "Skin em uso" if h == current else "Usar esta skin (botão direito: apagar)"
		if tex:
			# Miniatura: lado direito e vista de cima (o resto do molde é quase vazio)
			var full := tex.get_image()
			full.clear_mipmaps()
			var k := float(full.get_width()) / CarSkin.SIZE
			var side: Rect2i = CarSkin.RECTS[CarSkin.Face.RIGHT]
			var top: Rect2i = CarSkin.RECTS[CarSkin.Face.TOP]
			var crop := Rect2i(Vector2i(Vector2(side.position) * k), Vector2i(Vector2(side.size.x, top.end.y - side.position.y) * k))
			var thumb := full.get_region(crop)
			thumb.resize(int(TILE.x) - 16, int((TILE.x - 16) * crop.size.y / crop.size.x), Image.INTERPOLATE_BILINEAR)
			b.icon = ImageTexture.create_from_image(thumb)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			b.text = "baixando…"
		b.pressed.connect(_profile.set_skin.bind(h))
		b.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT and h != current:
				CarSkin.delete(h)
				_build())
		tiles.add_child(b)


## Pasta inicial dos diálogos de arquivo: Documentos/Speedoru.
static func _docs_dir() -> String:
	var d := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("Speedoru")
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _file_dialog(mode: FileDialog.FileMode, title: String, file_name: String, filters: PackedStringArray, on_file: Callable) -> void:
	var fd := FileDialog.new()
	fd.file_mode = mode
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.title = title
	fd.filters = filters
	fd.current_dir = _docs_dir()
	if file_name != "":
		fd.current_file = file_name
	fd.file_selected.connect(func(path: String) -> void:
		fd.queue_free()
		on_file.call(path))
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.6)


func _export_template() -> void:
	_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Salvar o molde da skin", "speedoru_molde.png",
		PackedStringArray(["*.png ; Imagem PNG"]), func(path: String) -> void: export_template_to(path))


## Gera o molde do carro e salva em `path` (PNG). Devolve o erro (OK se salvou).
func export_template_to(path: String, show := true) -> Error:
	if car == null or car.config == null:
		return ERR_UNCONFIGURED
	_note.text = "gerando o molde…"
	var img := await CarSkinTemplate.render(self, car.config)
	if path.get_extension().to_lower() != "png":
		path += ".png"
	var err := img.save_png(path)
	_note.text = ("molde salvo em %s" % path) if err == OK else "não deu para salvar o molde (%d)" % err
	if err == OK and show:
		OS.shell_show_in_file_manager(path)
	return err


func _import_skin() -> void:
	_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Importar a skin pintada", "",
		PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Imagens"]), func(path: String) -> void: import_skin_from(path))


## Importa a imagem pintada e já equipa. Devolve o resultado de CarSkin.import_file.
func import_skin_from(path: String) -> Dictionary:
	_note.text = "importando…"
	var res := await CarSkin.import_file_async(path)
	if res.get("ok", false):
		_profile.set_skin(res["hash"])
		_note.text = "skin importada e equipada"
	else:
		_note.text = str(res.get("error", "não deu para importar"))
	return res


## Cor (seletor livre), prévia do lugar (arrastar = mover) e os ajustes do decalque escolhido.
func _decal_controls(cur: Dictionary) -> void:
	var colors := row_box()
	colors.add_child(_kicker("COR"))
	var picker := ColorPickerButton.new()
	picker.color = Color(str(cur.get("color", "ffffff")))
	picker.edit_alpha = false
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.custom_minimum_size = Vector2(0, 28)
	picker.tooltip_text = "Qualquer cor"
	var hex := Label.new()
	hex.text = "#" + picker.color.to_html(false)
	hex.custom_minimum_size = Vector2(64, 0)
	hex.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hex.add_theme_font_size_override("font_size", 12)
	picker.color_changed.connect(func(c: Color) -> void:
		hex.text = "#" + c.to_html(false)
		_profile.set_decal_value(decal_slot, "color", c.to_html(false)))
	colors.add_child(picker)
	colors.add_child(hex)
	_grid.add_child(colors)
	_pad = PositionPad.new()
	_pad.studio = self
	_pad.slot = decal_slot
	_grid.add_child(_pad)
	# Lugares de dois lados: o esquerdo espelha o direito (desligar para textos)
	if (CarDecals.SLOTS[decal_slot]["places"] as Array).size() > 1:
		var mirror := CheckButton.new()
		mirror.text = "Espelhar no lado esquerdo"
		mirror.add_theme_font_size_override("font_size", 12)
		mirror.button_pressed = bool(cur.get("mirror", CarDecals.default_mirror(str(cur.get("id", "")))))
		mirror.tooltip_text = "Ligado: o lado esquerdo é o reflexo do direito (chamas e setas apontam para o mesmo lado do carro).\nDesligado: os dois lados leem o desenho normalmente (bom para textos)."
		mirror.toggled.connect(func(on: bool) -> void: _profile.set_decal_value(decal_slot, "mirror", on))
		_grid.add_child(mirror)
	var hint := Label.new()
	hint.text = "arraste para mover · roda: tamanho · Shift+roda: giro · duplo clique: centraliza"
	hint.theme_type_variation = "RetroMuted"
	hint.add_theme_font_size_override("font_size", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(200, 0)
	_grid.add_child(hint)
	for spec in DECAL_SLIDERS:
		var r := row_box()
		r.add_child(_kicker(spec[0], 84))
		var sl := HSlider.new()
		sl.min_value = spec[2]
		sl.max_value = spec[3]
		sl.step = spec[4]
		sl.value = float(cur.get(spec[1], spec[7]))
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.custom_minimum_size = Vector2(60, 20)
		StudioPanel.style_slider(sl)
		var value := Label.new()
		value.custom_minimum_size = Vector2(44, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 12)
		value.text = spec[5] % roundi(sl.value * spec[6])
		sl.value_changed.connect(func(v: float) -> void: _profile.set_decal_value(decal_slot, spec[1], v))
		r.add_child(sl)
		r.add_child(value)
		_grid.add_child(r)
		_decal_sliders[spec[1]] = [sl, value, spec]
	var reset := Button.new()
	reset.text = "Centralizar e tamanho padrão"
	reset.add_theme_font_size_override("font_size", 12)
	reset.pressed.connect(func() -> void:
		for spec in DECAL_SLIDERS:
			_profile.set_decal_value(decal_slot, spec[1], spec[7]))
	_grid.add_child(reset)


## Valor de um ajuste do decalque atual (o padrão se ainda não mudou).
func decal_value(key: String) -> float:
	var cur: Dictionary = (_profile.equipped["decals"] as Dictionary).get(decal_slot, {})
	for spec in DECAL_SLIDERS:
		if spec[1] == key:
			return float(cur.get(key, spec[7]))
	return 0.0


## Mudança vinda da prévia (arrastar/roda): dentro dos limites, vai para o perfil.
func set_decal_from_pad(key: String, value: float) -> void:
	for spec in DECAL_SLIDERS:
		if spec[1] == key:
			value = clampf(value, spec[2], spec[3])
	_profile.set_decal_value(decal_slot, key, value)


## Sliders e prévia acompanham o perfil (sem reconstruir a tela).
func _sync_decal_controls() -> void:
	if _pad and is_instance_valid(_pad):
		_pad.queue_redraw()
	for key in _decal_sliders:
		var e: Array = _decal_sliders[key]
		var sl: HSlider = e[0]
		if not is_instance_valid(sl):
			continue
		var v := decal_value(key)
		if absf(sl.value - v) > 0.0001:
			sl.set_value_no_signal(v)
		(e[1] as Label).text = e[2][5] % roundi(v * e[2][6])


func row_box() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	return r


func _kicker(text: String, width := 64.0) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "RetroKicker"
	l.add_theme_font_size_override("font_size", 11)
	l.custom_minimum_size = Vector2(width, 0)
	return l


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
			return Color(str(eq["neon"])) if eq["neon_on"] and str(eq["neon"]) != "" else Retro.c("muted")
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
	_color_picker_tile(field)
	for sug in _profile.color_suggestions(field):
		var c: Color = sug[1]
		var t := OptionTile.new()
		t.title = sug[0]
		t.art_kind = "color"
		t.color = c
		t.selected = c.to_html(false) == current
		t.pressed.connect(_profile.equip_color.bind(field, c))
		_add(t)


## Primeira opção da grade: a cor atual com o seletor livre (qualquer cor).
func _color_picker_tile(field: String) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size = TILE
	box.add_theme_constant_override("separation", 4)
	var picker := ColorPickerButton.new()
	picker.color = Color(str(_profile.equipped.get(field, "ffffff")))
	picker.edit_alpha = false
	picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker.tooltip_text = "Escolher qualquer cor"
	# Ao arrastar no seletor só o carro muda; a tela é refeita quando ele fecha
	picker.color_changed.connect(func(c: Color) -> void:
		_profile.equipped[field] = c.to_html(false)
		if car and car.config:
			_profile.apply_to_config(car.config))
	picker.popup_closed.connect(func() -> void: _profile.equip_color(field, picker.color))
	box.add_child(picker)
	var l := Label.new()
	l.text = "Qualquer cor · #%s" % picker.color.to_html(false)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Retro.c("text"))
	box.add_child(l)
	_grid.add_child(box)


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
	## Esquema de pintura (art_kind "scheme") e as 3 cores da prévia.
	var scheme := 0
	var scheme_cols: Array = []
	var selected := false
	## Tooltip em cartão: título (padrão = nome), texto e linhas de valores.
	var tip_title := ""
	var tip_text := ""
	var tip_rows: Array = []
	## Decalque (art_kind "decal"): o desenho, tingido com `color`.
	var decal: Texture2D
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
				if ShopCatalog.ITEMS.has(item_id):
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
			"scheme":
				# O carro de lado (em cima) e de cima (embaixo), frente para a direita
				var tex := CarLivery.scheme_preview(scheme, scheme_cols)
				var box := art.grow(-3.0)
				var k := minf(box.size.x / tex.get_width(), box.size.y / tex.get_height())
				var sz := Vector2(tex.get_width(), tex.get_height()) * k
				draw_texture_rect(tex, Rect2(box.get_center() - sz * 0.5, sz), false, Color(1, 1, 1, a_mul))
			"off":
				draw_arc(art.get_center(), art.size.y * 0.3, 0, TAU, 32, Retro.c("muted"), 2.0)
				draw_line(art.get_center() + Vector2(-12, 12), art.get_center() + Vector2(12, -12), Retro.c("muted"), 2.0)
			"part":
				draw_string(Retro.display(800), Vector2(art.position.x, art.get_center().y + 5), subtitle.to_upper(),
					HORIZONTAL_ALIGNMENT_CENTER, art.size.x, 11, Retro.c("accent_2"))
			"decal":
				# Fundo cinza-escuro (decalques claros e escuros aparecem) e o desenho na proporção
				draw_rect(art, Color(0.24, 0.25, 0.3, 0.9))
				if decal:
					var aspect := float(decal.get_width()) / maxf(decal.get_height(), 1.0)
					var box := art.grow(-6.0)
					var w := minf(box.size.x, box.size.y * aspect)
					var dr := Rect2(box.get_center() - Vector2(w, w / aspect) * 0.5, Vector2(w, w / aspect))
					draw_texture_rect(decal, dr, false, Color(color, a_mul))
				else:
					draw_string(Retro.body(600), Vector2(art.position.x, art.get_center().y + 5), "SVG inválido",
						HORIZONTAL_ALIGNMENT_CENTER, art.size.x, 11, Retro.c("bad"))
				if subtitle != "":
					draw_string(Retro.display(700), Vector2(art.position.x + 4, art.position.y + 12), subtitle.to_upper(),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Retro.c("accent_2"))
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
			"scheme":
				# Carroceria dividida na diagonal em três faixas
				var body := Rect2(c + Vector2(-13, -7), Vector2(26, 14))
				var cols := [Retro.c("accent"), Color.WHITE, Retro.c("accent_2")]
				var xs := [-13.0, -2.0, 3.0, 13.0]
				for i in 3:
					var a: float = xs[i]
					var b: float = xs[i + 1]
					var pts := PackedVector2Array()
					for q in [Vector2(a + 3.0, -7), Vector2(b + 3.0, -7), Vector2(b - 3.0, 7), Vector2(a - 3.0, 7)]:
						pts.append(c + Vector2(clampf(q.x, -13.0, 13.0), q.y))
					draw_colored_polygon(pts, cols[i])
				draw_rect(body, ink, false, 1.0)
			"skin":
				# Rolo de pintura: rolo, cabo e um rastro de tinta colorida
				draw_rect(Rect2(c + Vector2(-12, 5), Vector2(24, 6)), Retro.c("accent"))
				draw_rect(Rect2(c + Vector2(-12, 5), Vector2(12, 6)), Retro.c("accent_2"))
				draw_rect(Rect2(c + Vector2(-9, -12), Vector2(18, 8)), ink)
				draw_line(c + Vector2(9, -8), c + Vector2(13, -8), ink, 2.0)
				draw_line(c + Vector2(13, -8), c + Vector2(13, -1), ink, 2.0)
				draw_line(c + Vector2(13, -1), c + Vector2(1, -1), ink, 2.0)
				draw_line(c + Vector2(1, -1), c + Vector2(1, 4), ink, 3.0)
			"decals":
				# Estrela (adesivo) com a ponta descolando
				var pts := PackedVector2Array()
				for k in 10:
					var rad := 12.0 if k % 2 == 0 else 5.0
					var ang := -PI * 0.5 + k * PI / 5.0
					pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
				draw_colored_polygon(pts, ink)
				draw_colored_polygon(PackedVector2Array([c + Vector2(6, 6), c + Vector2(12, 6), c + Vector2(6, 12)]), Retro.c("accent"))
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


## Prévia do lugar do decalque, na proporção real: a área do lugar na cor da pintura, o limite até
## onde ele pode ir e o desenho na posição, tamanho, largura e giro atuais (as mesmas contas de
## CarDecals.build). Arrastar move; roda = tamanho; Shift+roda = giro; Ctrl+roda = largura; duplo
## clique centraliza.
class PositionPad extends Control:
	var studio: StudioPanel
	var slot := "sidepods"
	var _drag := false

	func _ready() -> void:
		custom_minimum_size = Vector2(0, 150)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_MOVE
		tooltip_text = "Arraste o desenho para mover"

	## [centro (px), px por metro, largura e altura do lugar (m)].
	func _frame() -> Array:
		var place: Array = CarDecals.SLOTS[slot]["places"][0]
		var w: float = place[3]
		var h: float = place[4]
		# Espaço para o centro andar ±MOVE do lugar e o desenho ainda caber
		var span := Vector2(w * (2.0 * CarDecals.MOVE + 1.0), h * (2.0 * CarDecals.MOVE + 1.0))
		var area := Rect2(Vector2.ZERO, size).grow(-10.0)
		var k := minf(area.size.x / span.x, area.size.y / span.y)
		return [area.get_center(), k, w, h]

	func _draw() -> void:
		var f := _frame()
		var c: Vector2 = f[0]
		var k: float = f[1]
		var w: float = f[2]
		var h: float = f[3]
		draw_rect(Rect2(Vector2.ZERO, size), Color(Retro.c("bg"), 0.85))
		Retro.draw_corners(self, Rect2(Vector2.ZERO, size), Color(Retro.c("accent"), 0.5), 8.0, 2.0)
		var eq: Dictionary = studio._profile.equipped
		# Lugar (na cor da pintura) e até onde o centro pode ir
		var body := Rect2(c - Vector2(w, h) * k * 0.5, Vector2(w, h) * k)
		draw_rect(body, Color(Color(str(eq["primary"])), 0.9))
		draw_rect(body, Color(Retro.c("text"), 0.35), false, 1.0)
		var travel := Rect2(c - Vector2(w, h) * k * CarDecals.MOVE, Vector2(w, h) * k * 2.0 * CarDecals.MOVE)
		draw_rect(travel, Color(Retro.c("accent_2"), 0.35), false, 1.0)
		draw_line(Vector2(c.x, travel.position.y), Vector2(c.x, travel.end.y), Color(Retro.c("text"), 0.12), 1.0)
		draw_line(Vector2(travel.position.x, c.y), Vector2(travel.end.x, c.y), Color(Retro.c("text"), 0.12), 1.0)
		var cur: Dictionary = (eq["decals"] as Dictionary).get(slot, {})
		var tex := CarDecals.texture(str(cur.get("id", "")))
		if tex:
			var aspect := float(tex.get_width()) / maxf(tex.get_height(), 1.0)
			var scale := studio.decal_value("scale")
			var dw := w * scale
			var dh := dw / aspect
			if dh > h * scale:
				dh = h * scale
				dw = dh * aspect
			dw *= studio.decal_value("stretch")
			var at := c + Vector2(studio.decal_value("x") * w, -studio.decal_value("y") * h) * CarDecals.MOVE * k
			# Giro: o Decal gira em volta da normal (anti-horário visto de fora); na tela o ângulo cresce no horário
			draw_set_transform(at, -deg_to_rad(studio.decal_value("rot")), Vector2.ONE)
			var r := Rect2(-Vector2(dw, dh) * k * 0.5, Vector2(dw, dh) * k)
			draw_texture_rect(tex, r, false, Color(str(cur.get("color", "ffffff"))))
			draw_rect(r, Color(Retro.c("accent_2"), 0.8 if _drag else 0.45), false, 1.0)
			draw_set_transform(Vector2.ZERO)
		var label := CarDecals.slot_label(slot)
		if (CarDecals.SLOTS[slot]["places"] as Array).size() > 1:
			label += " · visto pelo lado direito"
		Retro.draw_label(self, Retro.body(600), Vector2(10, size.y - 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(Retro.c("text_2"), 0.8))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.double_click:
					studio.set_decal_from_pad("x", 0.0)
					studio.set_decal_from_pad("y", 0.0)
				_drag = mb.pressed
				if _drag:
					_move_to(mb.position)
				queue_redraw()
				accept_event()
			elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var dir := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				if mb.shift_pressed:
					studio.set_decal_from_pad("rot", wrapf(studio.decal_value("rot") + dir * 5.0, -180.0, 180.0))
				elif mb.ctrl_pressed:
					studio.set_decal_from_pad("stretch", studio.decal_value("stretch") + dir * 0.05)
				else:
					studio.set_decal_from_pad("scale", studio.decal_value("scale") + dir * 0.05)
				accept_event()
		elif event is InputEventMouseMotion and _drag:
			_move_to((event as InputEventMouseMotion).position)
			accept_event()

	func _move_to(pos: Vector2) -> void:
		var f := _frame()
		var d: Vector2 = (pos - (f[0] as Vector2)) / (f[1] as float) / CarDecals.MOVE
		studio.set_decal_from_pad("x", clampf(d.x / float(f[2]), -1.0, 1.0))
		studio.set_decal_from_pad("y", clampf(-d.y / float(f[3]), -1.0, 1.0))


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
