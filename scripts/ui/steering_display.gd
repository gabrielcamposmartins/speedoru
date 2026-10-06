class_name SteeringDisplay
extends Control
## Face do volante (desenhada num SubViewport e aplicada sobre o volante 3D):
## luzes de troca de marcha, marcha, velocidade, balanço de freio, DRS, TC, composto e botões.

const LED_COUNT := 15
const GREEN := Color("3dff6e")
const RED := Color("ff2e45")
const BLUE := Color("3d8bff")
const CYAN := Color("35f0d6")
const YELLOW := Color("ffd21f")
const DIM := Color(1, 1, 1, 0.12)

var car: F1Car


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color("0c0c14"))
	draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color("2a2a38"), false, 3.0)
	if car == null:
		return

	# Luzes de troca de marcha (verde → vermelho → azul; piscam azul no limite)
	var rpm_t := clampf((car.rpm - 8000.0) / (car.upshift_rpm - 8000.0), 0.0, 1.0)
	var lit := roundi(rpm_t * LED_COUNT)
	var limiter := car.rpm >= car.upshift_rpm - 50.0
	var flash := int(Time.get_ticks_msec() / 80) % 2 == 0
	for i in LED_COUNT:
		var x := w * 0.5 + (i - (LED_COUNT - 1) * 0.5) * 22.0
		var color := GREEN if i < 5 else (RED if i < 10 else BLUE)
		if limiter:
			color = BLUE if flash else DIM
		elif i >= lit:
			color = DIM
		draw_circle(Vector2(x, 20), 8.0, color)

	# Tela central
	var screen := Rect2(150, 40, w - 300, 150)
	draw_rect(screen, Color("05070b"))
	draw_rect(screen, CYAN.darkened(0.4), false, 2.0)
	var gear_text := "R" if car.gear == F1Car.GEAR_REVERSE else ("N" if car.gear == 0 else str(car.gear))
	draw_string(font, Vector2(screen.position.x, screen.position.y + 118), gear_text,
		HORIZONTAL_ALIGNMENT_CENTER, screen.size.x, 110, YELLOW)
	draw_string(font, screen.position + Vector2(10, 28), "%d" % roundi(car.speed_kmh),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	draw_string(font, screen.position + Vector2(10, 46), "KM/H", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM * 4.0)
	draw_string(font, screen.position + Vector2(0, 28), "%d" % roundi(car.rpm),
		HORIZONTAL_ALIGNMENT_RIGHT, screen.size.x - 10, 22, CYAN)
	draw_string(font, screen.position + Vector2(0, 46), "RPM", HORIZONTAL_ALIGNMENT_RIGHT, screen.size.x - 10, 12, DIM * 4.0)
	var bb := "BB %.1f" % (car.brake_bias_front * 100.0)
	draw_string(font, screen.position + Vector2(10, 140), bb, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	var tc := "TC ON" if car.traction_control else "TC OFF"
	draw_string(font, screen.position + Vector2(0, 140), tc, HORIZONTAL_ALIGNMENT_RIGHT, screen.size.x - 10, 20,
		YELLOW if car.tc_active else (Color.WHITE if car.traction_control else RED))
	if car.config:
		draw_circle(screen.position + Vector2(screen.size.x * 0.5, 134), 9.0, car.config.compound_color())

	# Botões laterais
	_button(Vector2(70, 75), "DRS", GREEN, car.drs_open)
	_button(Vector2(70, 145), "TC", YELLOW, car.traction_control)
	_button(Vector2(70, 212), "N", Color.WHITE, car.gear == 0)
	_button(Vector2(w - 70, 75), "BB+", CYAN, Input.is_action_pressed("brake_bias_forward"))
	_button(Vector2(w - 70, 145), "BB-", CYAN, Input.is_action_pressed("brake_bias_rearward"))
	_button(Vector2(w - 70, 212), "PIT", Color("ff9a3d"), false)
	# Seletores rotativos (só visuais)
	_rotary(Vector2(200, 222), "MODE", 0.6)
	_rotary(Vector2(w - 200, 222), "DIFF", -0.4)
	if car.handling == F1Car.Handling.OVERSTEER:
		draw_string(font, Vector2(0, 236), "OVERSTEER", HORIZONTAL_ALIGNMENT_CENTER, w, 16, RED)
	elif car.handling == F1Car.Handling.UNDERSTEER:
		draw_string(font, Vector2(0, 236), "UNDERSTEER", HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color("ffa62b"))


func _button(center: Vector2, label: String, color: Color, active: bool) -> void:
	draw_circle(center, 26.0, color if active else color.darkened(0.75))
	draw_arc(center, 26.0, 0.0, TAU, 32, color, 2.0)
	draw_string(ThemeDB.fallback_font, center + Vector2(-26, 6), label, HORIZONTAL_ALIGNMENT_CENTER, 52, 16,
		Color.BLACK if active else Color.WHITE)


func _rotary(center: Vector2, label: String, angle: float) -> void:
	draw_circle(center, 18.0, Color("3a3a48"))
	draw_line(center, center + Vector2(sin(angle), -cos(angle)) * 16.0, YELLOW, 3.0)
	draw_string(ThemeDB.fallback_font, center + Vector2(-40, 34), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 12, DIM * 5.0)
