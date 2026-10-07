class_name CarCluster
extends Control
## Painel do carro em corrida, minimalista e no canto inferior direito: velocidade, marcha, uma
## barra fina de giro, uma de bateria e indicadores DRS/câmbio/TC/ABS só em texto. Fundo quase
## transparente (degradê para o canto), sem caixas. O status do carro (pneus e dano) fica num
## desenho compacto à parte (CarCluster.Status, na borda inferior esquerda).

const W := 300.0
const H := 128.0

var car: F1Car

var _battery_shown := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, H)
	size = custom_minimum_size
	Retro.events.changed.connect(queue_redraw)


func setup(target: F1Car) -> void:
	car = target


func _process(delta: float) -> void:
	if car == null:
		return
	_battery_shown = lerpf(_battery_shown, car.battery, 1.0 - exp(-12.0 * delta))
	queue_redraw()


func _draw() -> void:
	if car == null:
		return
	# Fundo: degradê suave para o canto (lê sobre o asfalto sem esconder a pista)
	var bg := Color(Retro.c("bg"), 0.0)
	var bg2 := Color(Retro.c("bg"), 0.48)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(36, 0), Vector2(36, H), Vector2(0, H)]),
		PackedColorArray([bg, bg2, bg2, bg]))
	draw_rect(Rect2(36, 0, W - 36, H), bg2)
	Retro.draw_corners(self, Rect2(Vector2.ZERO, Vector2(W, H)).grow(1.0), Color(Retro.c("accent"), 0.6), 10.0, 2.0)
	var disp := Retro.display(800)
	var muted := Retro.c("muted")
	# Marcha (caixa à direita) e velocidade
	var gear_box := Rect2(W - 62, 8, 54, 54)
	draw_rect(gear_box, Color(Retro.c("accent"), 0.14))
	draw_rect(gear_box, Retro.line(3), false, 1.0)
	var gear := "R" if car.gear == F1Car.GEAR_REVERSE else ("N" if car.gear == F1Car.GEAR_NEUTRAL else str(car.gear))
	Retro.draw_glow_text(self, disp, Vector2(gear_box.position.x, gear_box.position.y + 44), gear, HORIZONTAL_ALIGNMENT_CENTER,
		gear_box.size.x, 40, Retro.c("warn") if car.gear <= 0 else Retro.c("text"))
	Retro.draw_glow_text(self, disp, Vector2(0, 58), "%d" % roundi(car.speed_kmh), HORIZONTAL_ALIGNMENT_RIGHT,
		gear_box.position.x - 50, 50, Retro.c("text"))
	Retro.draw_label(self, Retro.display(700), Vector2(gear_box.position.x - 44, 58), "KM/H", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Retro.c("accent_2"))
	# Giro: uma barra fina segmentada (ciano → amarelo → vermelho piscando)
	var rpm_t := clampf((car.rpm - car.idle_rpm) / (car.max_rpm - car.idle_rpm), 0.0, 1.0)
	var flash := rpm_t > 0.93 and int(Time.get_ticks_msec() / 70) % 2 == 0
	var rpm_color := func(t: float) -> Color:
		if t > 0.93:
			return Color.WHITE if flash else Retro.c("bad")
		if t > 0.8:
			return Retro.c("warn")
		return Retro.c("accent_2")
	Retro.draw_segments(self, Rect2(10, 74, W - 20, 7), rpm_t, 28, rpm_color, 2.0)
	# Bateria: barra mais fina, na cor do boost
	var boost: Color = car.config.boost_color if car.config else Retro.c("accent_2")
	var t := Time.get_ticks_msec() / 1000.0
	var bcol := boost.lightened(0.25 + 0.2 * sin(t * 20.0)) if car.boost_active else boost
	Retro.draw_label(self, Retro.display(700), Vector2(10, 98), "⚡", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, bcol)
	Retro.draw_segments(self, Rect2(26, 90, W - 86, 4), _battery_shown, 20, bcol, 1.0, car.boost_active)
	Retro.draw_label(self, Retro.display(700), Vector2(0, 98), "%d%%" % roundi(car.battery * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, W - 10, 10,
		bcol if car.boost_active else Retro.c("text_2"))
	# Indicadores só em texto (acesos quando ativos)
	# DRS: aceso aberto; com a regra de 1 s, destacado quando disponível e apagado quando não
	var drs_off := car.drs_rule_active and not car.drs_allowed and not car.drs_open
	var flags := [
		["DRS", car.drs_open, Retro.c("good"), drs_off],
		# No vácuo, o lugar do câmbio mostra "VÁCUO" aceso
		["VÁCUO", true, Retro.c("accent_2")] if car.slipstream > 0.2 else ["AUTO" if car.automatic else "MANUAL", false, Retro.c("text_2")],
		["TC", car.tc_active, Retro.c("warn"), not car.traction_control],
		["ABS", car.abs_active, Retro.c("warn")],
		["LIM", car.limiter_on, Color("ffc400")],
	]
	var x := 10.0
	var f := Retro.display(700)
	for fl in flags:
		var lit: bool = fl[1]
		var off: bool = fl.size() > 3 and fl[3]
		var col: Color = fl[2] if lit else (Color(Retro.c("text_2"), 0.45) if off else Retro.c("text_2"))
		var label: String = fl[0] + (" OFF" if off and fl[0] != "DRS" else "")
		if fl[0] == "DRS" and not lit and car.drs_rule_active and car.drs_allowed:
			col = Retro.c("accent_2")
		Retro.draw_label(self, f, Vector2(x, H - 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		if lit:
			draw_rect(Rect2(x, H - 7, f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, 2), col)
		x += f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 16.0


## Status do carro compacto (borda inferior esquerda): o carro visto de cima; cada pneu é uma mini
## barra (preenchimento = quanto resta, contorno = aderência em uso, pisca patinando/travando) com o
## % ao lado; as peças mostram o dano por cor; uma linha de texto com composto e dano.
class Status extends Control:
	const DAMAGE_LAYOUT := {
		"front_wing_L": Rect2(2, 2, 27, 10), "front_wing_R": Rect2(31, 2, 27, 10),
		"nose": Rect2(24, 12, 12, 26),
		"suspension_FL": Rect2(0, 26, 14, 24), "suspension_FR": Rect2(46, 26, 14, 24),
		"mirror_L": Rect2(12, 56, 8, 5), "mirror_R": Rect2(40, 56, 8, 5),
		"chassis": Rect2(21, 38, 18, 40),
		"sidepod_L": Rect2(8, 66, 13, 38), "sidepod_R": Rect2(39, 66, 13, 38),
		"floor": Rect2(14, 104, 32, 8),
		"engine_cover": Rect2(22, 78, 16, 36), "engine": Rect2(25, 92, 10, 14),
		"suspension_RL": Rect2(0, 106, 15, 26), "suspension_RR": Rect2(45, 106, 15, 26),
		"rear_wing": Rect2(10, 134, 40, 12),
	}
	## Pneus (relativos à origem do carro de 60 x 150 px): DE, DD, TE, TD
	const TYRES := [Rect2(-15, 24, 10, 28), Rect2(65, 24, 10, 28), Rect2(-17, 104, 12, 30), Rect2(65, 104, 12, 30)]

	var car: F1Car
	var damage: CarDamage
	var _flash := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(150, 196)
		size = custom_minimum_size

	func setup(target: F1Car) -> void:
		car = target
		damage = car.get_node_or_null("Damage") as CarDamage
		if damage:
			damage.part_detached.connect(func(_p): _flash = 1.5)
			damage.part_damaged.connect(func(_p, _h): _flash = maxf(_flash, 0.6))

	func _process(delta: float) -> void:
		_flash = maxf(_flash - delta, 0.0)
		queue_redraw()

	func _draw() -> void:
		if car == null:
			return
		var origin := Vector2(45, 22)
		var bg := Color(Retro.c("bg"), 0.32)
		draw_rect(Rect2(origin - Vector2(26, 10), Vector2(112, 168)), bg)
		Retro.draw_corners(self, Rect2(origin - Vector2(26, 10), Vector2(112, 168)), Color(Retro.c("accent"), 0.5), 8.0, 2.0)
		# Peças (dano)
		var blink := _flash > 0.0 and int(Time.get_ticks_msec() / 80) % 2 == 0
		if damage:
			for piece in DAMAGE_LAYOUT:
				if not damage.health.has(piece):
					continue
				var pr: Rect2 = DAMAGE_LAYOUT[piece]
				pr.position += origin
				if damage.detached.has(piece):
					draw_rect(pr, Color(Retro.c("bad"), 0.55), false, 1.0)
					draw_line(pr.position, pr.end, Color(Retro.c("bad"), 0.8), 1.0)
					continue
				var h := float(damage.health[piece])
				var col := _health_color(h)
				if h < 0.4 and blink:
					col = Color.WHITE
				draw_rect(pr, Color(col, 0.16 if h >= 0.999 else 0.4))
				draw_rect(pr, Color(col, 0.55 if h >= 0.999 else 0.9), false, 1.0)
		# Pneus: preenchimento = vida restante, contorno = aderência em uso
		var tblink := int(Time.get_ticks_msec() / 90) % 2 == 0
		var font := Retro.display(700)
		for i in mini(4, car.tire_usage.size()):
			var tr: Rect2 = TYRES[i]
			tr.position += origin
			var left := 1.0 - car.tire_wear[i]
			var wear_col := Retro.c("good") if left > 0.6 else (Retro.c("warn") if left > 0.3 else Retro.c("bad"))
			draw_rect(tr, Color(0, 0, 0, 0.55))
			var fill_h := tr.size.y * left
			draw_rect(Rect2(tr.position.x, tr.end.y - fill_h, tr.size.x, fill_h), Color(wear_col, 0.85))
			draw_rect(tr.grow(1.5), _grip_color(i, tblink), false, 2.0)
			var right_side := i % 2 == 1
			var tx := tr.end.x + 3 if right_side else tr.position.x - 25
			Retro.draw_label(self, font, Vector2(tx, tr.get_center().y + 4), "%d" % roundi(left * 100.0), HORIZONTAL_ALIGNMENT_RIGHT if not right_side else HORIZONTAL_ALIGNMENT_LEFT,
				22, 9, Retro.c("text_2"))
		# Linha de texto: composto e dano
		var compound: int = car.config.tyre_compound if car.config else 1
		var ccol: Color = Retro.ctx(CarConfig.COMPOUND_COLORS[compound])
		var y := origin.y + 162
		draw_circle(Vector2(origin.x - 18, y - 4), 5.0, ccol)
		draw_circle(Vector2(origin.x - 18, y - 4), 2.2, Retro.c("bg"))
		Retro.draw_label(self, font, Vector2(origin.x - 9, y), CarConfig.COMPOUND_NAMES[compound].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Retro.c("text_2"))
		var overall := damage.get_overall() if damage else 1.0
		if overall < 0.999:
			Retro.draw_label(self, font, Vector2(origin.x - 26, y), "DANO %d%%" % roundi((1.0 - overall) * 100.0), HORIZONTAL_ALIGNMENT_RIGHT,
				112, 10, _health_color(overall))

	func _health_color(h: float) -> Color:
		if h < 0.4:
			return Retro.c("bad")
		if h < 0.75:
			return Retro.c("warn")
		if h < 0.999:
			return Retro.c("good").lerp(Retro.c("warn"), (1.0 - h) / 0.25)
		return Retro.c("good")

	func _grip_color(i: int, blink: bool) -> Color:
		match car.tire_state[i]:
			F1Car.TireState.AIR:
				return Color(Retro.c("text"), 0.25)
			F1Car.TireState.SPIN, F1Car.TireState.LOCK, F1Car.TireState.SLIDE:
				return Retro.c("bad") if blink else Color.WHITE
		var usage := car.tire_usage[i]
		if usage < 0.7:
			return Color(Retro.c("accent_2"), 0.5 + usage * 0.5)
		return Retro.c("good").lerp(Retro.c("warn"), clampf((usage - 0.7) / 0.3, 0.0, 1.0))
