class_name PrizeWheel
extends CanvasLayer
## Roleta do vencedor (tela final de corrida online, 1º lugar): uma roda com as fatias de
## ShopCatalog.WINNER_WHEEL no tamanho das chances (5% exclusivo, 50% 500 créditos, 30% 1.000
## créditos, 15% ticket). Pede o sorteio ao servidor ("race_spin") girando rápido; quando a resposta
## chega, desacelera e para dentro da fatia sorteada, e mostra o prêmio (o item exclusivo no cartão
## da Galeria, com confetes).

signal closed

const SPIN_TIME := 3.6
const SLICE_COLORS := [Color("ffd84d"), Color("2f9bff"), Color("b14dff"), Color("3dfc9a")]

## Testes/offline: resultado já sorteado (pula o pedido ao servidor).
var preset := {}
var result := {}
var _angle := 0.0
var _speed := 9.0
var _t := 0.0
var _start_angle := 0.0
var _target := 0.0
var _landing := false
var _done := false
var _last_slice := -1
var _wheel: Control
var _status: Label


func _ready() -> void:
	layer = 115
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := Retro.backdrop(0.9)
	bg.theme = Retro.theme()
	add_child(bg)
	_wheel = Control.new()
	_wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel.draw.connect(_draw_wheel)
	bg.add_child(_wheel)
	_status = Label.new()
	_status.text = "Girando…"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.position.y -= 90
	_status.theme_type_variation = "RetroMuted"
	bg.add_child(_status)
	if preset.is_empty():
		_ask.call_deferred()
	else:
		_land(preset)


func _ask() -> void:
	var net := get_node_or_null("/root/Net")
	if net == null:
		_fail("Sem conexão com o servidor.")
		return
	var res: Dictionary = await net.request("race_spin", {})
	if not is_inside_tree():
		return
	if not res.get("ok", false):
		_fail(str(res.get("error", "A roleta não respondeu.")))
		return
	_land(res)


func _fail(msg: String) -> void:
	_done = true
	_speed = 0.0
	_status.text = msg
	_add_close()


## Começa a desacelerar até o meio (com folga) da fatia sorteada, debaixo do ponteiro (em cima).
func _land(res: Dictionary) -> void:
	result = res
	var k := int(res.get("slice", 0))
	var a0 := 0.0
	for j in k:
		a0 += float(ShopCatalog.WINNER_WHEEL[j][1]) / 100.0 * TAU
	var w := float(ShopCatalog.WINNER_WHEEL[k][1]) / 100.0 * TAU
	var inside := a0 + w * randf_range(0.2, 0.8)
	# O ponteiro fica em −π/2; a roda girou _angle: a fatia sob o ponteiro é −π/2 − _angle
	var want := -PI * 0.5 - inside
	var turns := 4.0 * TAU
	_start_angle = _angle
	_target = _angle + turns + fposmod(want - _angle, TAU)
	_t = 0.0
	_landing = true


func _process(delta: float) -> void:
	if _done and not _landing:
		_wheel.queue_redraw()
		return
	if _landing:
		_t += delta
		var u := clampf(_t / SPIN_TIME, 0.0, 1.0)
		_angle = lerpf(_start_angle, _target, 1.0 - pow(1.0 - u, 3.0))
		if u >= 1.0:
			_landing = false
			_done = true
			_reveal()
	else:
		_angle += _speed * delta
	var under := _slice_under()
	if under != _last_slice:
		_last_slice = under
		UiSounds.play(self, UiSounds.tick(), -18.0, randf_range(0.96, 1.04))
	_wheel.queue_redraw()


func _slice_under() -> int:
	var a := fposmod(-PI * 0.5 - _angle, TAU)
	var acc := 0.0
	for k in ShopCatalog.WINNER_WHEEL.size():
		acc += float(ShopCatalog.WINNER_WHEEL[k][1]) / 100.0 * TAU
		if a < acc:
			return k
	return ShopCatalog.WINNER_WHEEL.size() - 1


static func slice_label(k: int) -> String:
	var s: Array = ShopCatalog.WINNER_WHEEL[k]
	match str(s[0]):
		"exclusive":
			return "EXCLUSIVO"
		"credits":
			return "%s" % PlayerProfile.format_credits(int(s[2]))
		"ticket":
			return "TICKET"
	return ""


func _draw_wheel() -> void:
	var vp := _wheel.size
	var c := Vector2(vp.x * 0.5, vp.y * 0.42)
	var r := minf(vp.x, vp.y) * 0.26
	Retro.draw_glow_text(_wheel, Retro.display(900), Vector2(0, c.y - r - 60), "ROLETA DO VENCEDOR", HORIZONTAL_ALIGNMENT_CENTER,
		vp.x, 34, Retro.c("text"), Retro.c("accent"))
	_wheel.draw_circle(c, r + 10, Color(Retro.c("bg"), 0.95))
	var a := _angle
	for k in ShopCatalog.WINNER_WHEEL.size():
		var w := float(ShopCatalog.WINNER_WHEEL[k][1]) / 100.0 * TAU
		var pts := PackedVector2Array([c])
		var steps := maxi(int(w / 0.05), 2)
		for q in steps + 1:
			pts.append(c + Vector2.from_angle(a + w * q / steps) * r)
		var col: Color = SLICE_COLORS[k]
		_wheel.draw_colored_polygon(pts, col.darkened(0.15 if k % 2 == 0 else 0.3))
		_wheel.draw_polyline(pts, Color(Retro.c("bg"), 0.8), 2.0)
		# Texto no meio da fatia, girando junto
		var mid := a + w * 0.5
		var label := slice_label(k)
		var fs := 15 if w > 0.6 else 11
		var tp := c + Vector2.from_angle(mid) * r * 0.62
		# Texto ao longo da borda, sempre de pé (vira 180° na metade de baixo)
		var rot := mid + PI * 0.5
		if cos(rot) < 0.0:
			rot += PI
		_wheel.draw_set_transform(tp, rot, Vector2.ONE)
		_wheel.draw_string(Retro.display(900), Vector2(-60, fs * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, 120, fs, Color(0.05, 0.05, 0.1))
		_wheel.draw_set_transform_matrix(Transform2D.IDENTITY)
		a += w
	_wheel.draw_arc(c, r + 4, 0, TAU, 96, Retro.c("accent"), 4.0)
	_wheel.draw_circle(c, r * 0.12, Retro.c("surface_2"))
	_wheel.draw_arc(c, r * 0.12, 0, TAU, 32, Retro.c("accent"), 3.0)
	# Ponteiro em cima
	var top := c + Vector2(0, -r - 6)
	_wheel.draw_colored_polygon(PackedVector2Array([top + Vector2(-16, -22), top + Vector2(16, -22), top + Vector2(0, 8)]), Retro.c("accent_2"))


func _reveal() -> void:
	var kind := str(result.get("kind", ""))
	var credits := int(result.get("credits", 0))
	var item := str(result.get("item", ""))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_child(0).add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_END
	box.custom_minimum_size = Vector2(0, get_viewport().get_visible_rect().size.y * 0.92)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var head := Label.new()
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_override("font", Retro.display(900))
	head.add_theme_font_size_override("font_size", 28)
	head.add_theme_color_override("font_color", Retro.c("good"))
	match kind:
		"exclusive":
			if item != "":
				head.text = "PRÊMIO EXCLUSIVO!" if not bool(result.get("dup", false)) else "EXCLUSIVO REPETIDO · +%s %s" % [
					PlayerProfile.format_credits(int(result.get("refund", 0))), ShopCatalog.CURRENCY]
				head.add_theme_color_override("font_color", ShopCatalog.RARITY_COLORS[4])
			else:
				head.text = "VOCÊ JÁ TEM TODOS OS EXCLUSIVOS · +%s %s" % [PlayerProfile.format_credits(credits), ShopCatalog.CURRENCY]
		"credits":
			head.text = "+%s %s" % [PlayerProfile.format_credits(credits), ShopCatalog.CURRENCY]
		"ticket":
			head.text = "+1 TICKET DA ROLETA DA LOJA"
			head.add_theme_color_override("font_color", SLICE_COLORS[3])
	box.add_child(head)
	_status.text = ""
	if item != "":
		var card := GalleryPanel.ItemCard.new()
		card.item_id = item
		card.owned = true
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(card)
	UiSounds.play(self, UiSounds.prize(4 if kind == "exclusive" else 2), -11.0)
	var confetti := Confetti.new()
	confetti.colors.append_array([SLICE_COLORS[int(result.get("slice", 0))], Retro.c("accent"), Color.WHITE])
	add_child(confetti)
	_add_close(box)


func _add_close(parent: Control = null) -> void:
	var ok := Button.new()
	ok.text = "Fechar"
	ok.custom_minimum_size = Vector2(180, 44)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(_close)
	if parent:
		parent.add_child(ok)
	else:
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		center.position.y -= 50
		get_child(0).add_child(center)
		center.add_child(ok)
	ok.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if _done and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()
