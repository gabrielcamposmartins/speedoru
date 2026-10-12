class_name Confetti
extends Control
## Chuva de confetes por cima da tela (prêmio novo na roleta): dois canhões nos cantos de baixo
## atiram papéis coloridos para o alto; eles giram, balançam ao cair e somem aos poucos. Some
## sozinho quando o último papel sai. Não pega o mouse.

const COUNT := 150
const GRAVITY := 900.0
const LIFE := 3.6

## Cores dos papéis (a da raridade entra com mais peso).
var colors: Array[Color] = [Color("ff4fa3"), Color("4fd8ff"), Color("ffd84f"), Color("7dff8a"), Color("b48cff"), Color.WHITE]

var _bits := []
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var vp := size if size.x > 0.0 else get_viewport_rect().size
	for i in COUNT:
		var left := i % 2 == 0
		var origin := Vector2(vp.x * (0.04 if left else 0.96), vp.y * 1.02)
		# Para cima e para dentro da tela
		var ang := deg_to_rad(randf_range(-80.0, -52.0) if left else randf_range(-128.0, -100.0))
		var speed := randf_range(0.8, 1.2) * vp.y * 2.4
		_bits.append({
			"p": origin, "v": Vector2(cos(ang), sin(ang)) * speed,
			"r": randf() * TAU, "w": randf_range(-9.0, 9.0),
			"s": Vector2(randf_range(10.0, 18.0), randf_range(6.0, 10.0)),
			"c": colors[randi() % colors.size()], "ph": randf() * TAU, "delay": randf() * 0.25,
			"round": randf() < 0.25,
		})


func _process(delta: float) -> void:
	_t += delta
	for b in _bits:
		if _t < b["delay"]:
			continue
		var v: Vector2 = b["v"]
		v.y += GRAVITY * delta
		# Resistência do ar: papel cai devagar e balança de um lado para o outro
		v *= pow(0.3, delta)
		v.y = minf(v.y, 260.0)
		b["v"] = v
		b["p"] += (v + Vector2(sin(_t * 5.0 + b["ph"]) * 60.0, 0.0)) * delta
		b["r"] += b["w"] * delta
	queue_redraw()
	if _t > LIFE + 0.3:
		queue_free()


func _draw() -> void:
	var fade := clampf((LIFE - _t) / 0.9, 0.0, 1.0)
	for b in _bits:
		if _t < b["delay"]:
			continue
		var c: Color = b["c"]
		# O "giro" do papel no ar: a largura aparente pulsa
		var flip := absf(cos(_t * 7.0 + b["ph"]))
		var s: Vector2 = b["s"]
		draw_set_transform(b["p"], b["r"], Vector2(maxf(flip, 0.15), 1.0))
		if b["round"]:
			draw_circle(Vector2.ZERO, s.y * 0.6, Color(c, fade))
		else:
			draw_rect(Rect2(-s * 0.5, s), Color(c.darkened(0.25 * (1.0 - flip)), fade))
	draw_set_transform(Vector2.ZERO)
