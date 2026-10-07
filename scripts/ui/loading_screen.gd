class_name LoadingScreen
extends CanvasLayer
## Tela de carregamento (autoload "Loading"): arte do jogo em tela cheia com uma barra de
## progresso com porcentagem embaixo. Aparece sempre que uma cena/corrida está carregando:
##
## * change_scene(path): carrega a cena numa thread (0–25 %), troca de cena e segue mostrando
##   a geração da pista (RaceTrack chama report() a cada etapa, 25–95 %) até finish().
## * begin()/report()/finish(): para quem carrega outra coisa (ex.: montar o grid da corrida).
##
## A geração da pista roda no thread principal em etapas; entre elas a tela é redesenhada, por
## isso a barra anda em degraus e a animação de fundo só se move entre as etapas.

const ART := preload("res://assets/ui/speedoru.png")
const FADE_TIME := 0.45
## Fatia da barra para carregar o arquivo da cena; o resto é a montagem (pista, grid).
const SCENE_SHARE := 0.25

static var instance: LoadingScreen

var active := false
var progress := 0.0
var stage := ""

var _shown := 0.0
var _root: Control
var _art: TextureRect
var _bar: LoadBar
var _percent: Label
var _stage_label: Label
var _tip: Label
var _time := 0.0
var _fade: Tween
var _loading_path := ""

const TIPS := [
	"Freie forte antes da curva e recarregue a bateria — Alt esquerdo solta o boost.",
	"Limite de 80 km/h na pista dos boxes: passar disso custa +5 s.",
	"Três saídas da pista geram aviso; a partir da quarta, +5 s de penalidade.",
	"Pneus macios são rápidos mas gastam cedo; duros aguentam a corrida inteira.",
	"Escolha o composto do pit com 1 / 2 / 3 antes de entrar nos boxes.",
	"Queimar a largada custa +10 s: espere as cinco luzes apagarem.",
	"DRS no Shift: use nas retas para ganhar velocidade final.",
	"Bater em quem está na frente gera penalidade de +5 ou +10 s.",
]


func _ready() -> void:
	instance = self
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------
## Carrega uma cena com a tela de carregamento por cima do começo ao fim.
func change_scene(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().change_scene_to_file(path)
		return
	begin("Carregando")
	_loading_path = path
	var err := ResourceLoader.load_threaded_request(path, "", true)
	if err != OK:
		_loading_path = ""
		get_tree().change_scene_to_file(path)
		return
	set_process(true)


## Mostra a tela (sem animação de entrada: ela cobre a troca imediatamente).
func begin(text := "Carregando") -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _fade:
		_fade.kill()
	active = true
	progress = 0.0
	_shown = 0.0
	stage = text
	_root.visible = true
	_root.modulate.a = 1.0
	_tip.text = TIPS[randi() % TIPS.size()]
	_time = 0.0
	_layout_art()
	_update_labels()
	set_process(true)


## Progresso absoluto (0–1) e a etapa atual. O valor mostrado nunca volta para trás.
func report(value: float, text := "") -> void:
	if not active:
		return
	progress = maxf(progress, clampf(value, 0.0, 1.0))
	if text != "":
		stage = text
	# A etapa seguinte costuma travar o thread principal: mostra já o valor real
	_shown = progress
	_update_labels()


## Completa a barra e some com um fade.
func finish() -> void:
	if not active:
		return
	active = false
	progress = 1.0
	stage = "Pronto"
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_method(func(v: float):
		_shown = v
		_update_labels(), _shown, 1.0, 0.25)
	_fade.tween_interval(0.15)
	_fade.tween_property(_root, "modulate:a", 0.0, FADE_TIME)
	_fade.tween_callback(func(): _root.visible = false)


## Atalhos estáticos (não fazem nada sem o autoload, ex.: no editor ou em testes).
static func report_progress(value: float, text := "") -> void:
	if instance:
		instance.report(value, text)


static func start(text := "Carregando") -> void:
	if instance:
		instance.begin(text)


static func done() -> void:
	if instance:
		instance.finish()


## Ainda na tela (carregando ou no fade de saída).
static func is_shown() -> bool:
	return instance != null and instance._root != null and instance._root.visible


static func is_loading() -> bool:
	return instance != null and instance.active


# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _root.visible:
		set_process(false)
		return
	_time += delta
	if _loading_path != "":
		var p := []
		var status := ResourceLoader.load_threaded_get_status(_loading_path, p)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				report(SCENE_SHARE * float(p[0]) if p.size() > 0 else 0.0, "Carregando a cena")
			ResourceLoader.THREAD_LOAD_LOADED:
				var packed := ResourceLoader.load_threaded_get(_loading_path) as PackedScene
				_loading_path = ""
				report(SCENE_SHARE, "Montando o circuito")
				get_tree().change_scene_to_packed(packed)
			_:
				push_error("Falha ao carregar %s" % _loading_path)
				var path := _loading_path
				_loading_path = ""
				get_tree().change_scene_to_file(path)
	if active:
		_shown = move_toward(_shown, progress, delta * 0.8)
		_update_labels()
	# Zoom lento na arte (Ken Burns), a partir do topo para o logo continuar inteiro
	var z := 1.0 + 0.035 * (1.0 - exp(-_time * 0.12))
	_art.scale = Vector2(z, z)
	_art.pivot_offset = _art.size * Vector2(0.5, 0.0)
	_bar.time = _time
	_bar.queue_redraw()


func _layout_art() -> void:
	var view := _root.size
	var aspect := float(ART.get_width()) / ART.get_height()
	if view.x / maxf(view.y, 1.0) >= aspect:
		# Tela mais larga que a arte: ocupa a largura, corta embaixo
		_art.size = Vector2(view.x, view.x / aspect)
		_art.position = Vector2.ZERO
	else:
		# Tela mais estreita: ocupa a altura, corta dos lados
		_art.size = Vector2(view.y * aspect, view.y)
		_art.position = Vector2((view.x - _art.size.x) * 0.5, 0.0)


func _update_labels() -> void:
	_bar.value = _shown
	_percent.text = "%d%%" % roundi(_shown * 100.0)
	_stage_label.text = stage.to_upper() + ("" if not active else ".".repeat(1 + int(_time * 2.5) % 3))
	_bar.queue_redraw()


func _build() -> void:
	var bold := Retro.display(800)
	var italic := Retro.body(500)

	_root = Control.new()
	_root.name = "Loading"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	# Enquadrada pelo topo (o logo nunca é cortado; sobra corta embaixo, no asfalto) — igual ao
	# splash do Godot (speedoru_splash.png é o mesmo recorte 16:9), então a troca não dá pulo
	_art = TextureRect.new()
	_art.texture = ART
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_art)
	_root.resized.connect(_layout_art)

	# Faixa escura embaixo para a barra
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([Color(0.01, 0.02, 0.07, 0.0), Color(0.01, 0.02, 0.07, 0.72), Color(0.01, 0.02, 0.07, 0.94)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	gtex.width = 8
	gtex.height = 128
	shade.texture = gtex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 0.68
	shade.anchor_bottom = 1.0
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	var bottom := Control.new()
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 64
	bottom.offset_right = -64
	bottom.offset_top = -150
	bottom.offset_bottom = -40
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bottom)

	_stage_label = Label.new()
	_stage_label.add_theme_font_override("font", bold)
	_stage_label.add_theme_font_size_override("font_size", 22)
	_stage_label.add_theme_color_override("font_color", Retro.c("text"))
	_stage_label.add_theme_color_override("font_shadow_color", Color(Retro.c("accent"), 0.6))
	_stage_label.add_theme_constant_override("shadow_offset_x", 0)
	_stage_label.add_theme_constant_override("shadow_offset_y", 0)
	_stage_label.add_theme_constant_override("shadow_outline_size", 10)
	_stage_label.position = Vector2(4, 0)
	bottom.add_child(_stage_label)

	_percent = Label.new()
	_percent.add_theme_font_override("font", bold)
	_percent.add_theme_font_size_override("font_size", 52)
	_percent.add_theme_color_override("font_color", Retro.c("text"))
	_percent.add_theme_color_override("font_outline_color", Retro.c("bg"))
	_percent.add_theme_constant_override("outline_size", 10)
	_percent.add_theme_color_override("font_shadow_color", Color(Retro.c("accent"), 0.75))
	_percent.add_theme_constant_override("shadow_offset_x", 0)
	_percent.add_theme_constant_override("shadow_offset_y", 0)
	_percent.add_theme_constant_override("shadow_outline_size", 22)
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_percent.anchor_left = 1.0
	_percent.anchor_right = 1.0
	_percent.offset_left = -240
	_percent.offset_right = 0
	_percent.offset_top = -30
	bottom.add_child(_percent)

	_bar = LoadBar.new()
	_bar.anchor_left = 0.0
	_bar.anchor_right = 1.0
	_bar.offset_top = 46
	_bar.offset_bottom = 74
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_bar)

	_tip = Label.new()
	_tip.add_theme_font_override("font", italic)
	_tip.add_theme_font_size_override("font_size", 17)
	_tip.add_theme_color_override("font_color", Retro.c("text_2"))
	_tip.position = Vector2(6, 86)
	bottom.add_child(_tip)


## Barra inclinada com preenchimento em degradê nas cores da paleta (Synthwave: ciano → magenta →
## rosa, as mesmas do logo), brilho correndo por dentro, marcas a cada 10 %, cantoneiras e uma
## bandeira quadriculada na ponta.
class LoadBar extends Control:
	var value := 0.0
	var time := 0.0
	const SKEW := 14.0

	func _para(x0: float, x1: float, y0: float, y1: float) -> PackedVector2Array:
		return PackedVector2Array([Vector2(x0 + SKEW, y0), Vector2(x1 + SKEW, y0), Vector2(x1, y1), Vector2(x0, y1)])

	func _draw() -> void:
		var w := size.x - SKEW
		var h := size.y
		# Moldura, fundo e cantoneiras
		draw_colored_polygon(_para(-4, w + 4, -4, h + 4), Retro.line(3))
		draw_colored_polygon(_para(-2, w + 2, -2, h + 2), Color(Retro.c("bg"), 0.95))
		Retro.draw_corners(self, Rect2(-10, -10, size.x + 20, h + 20), Color(0, 0, 0, 0), 16.0, 2.0)
		var fill := w * clampf(value, 0.0, 1.0)
		if fill > 1.0:
			# Degradê em fatias (polígonos coloridos por vértice)
			var steps := 24
			for k in steps:
				var a := fill * k / steps
				var b := fill * (k + 1) / steps
				var ca := _grad(a / w)
				var cb := _grad(b / w)
				var pts := _para(a, b, 0, h)
				draw_polygon(pts, PackedColorArray([ca, cb, cb, ca]))
			# Reflexo na metade de cima
			draw_colored_polygon(_para(0, fill, 0, h * 0.42), Color(1, 1, 1, 0.18))
			# Brilho correndo
			var sweep := fmod(time * 380.0, fill + 160.0) - 80.0
			var g0 := clampf(sweep - 50.0, 0.0, fill)
			var g1 := clampf(sweep + 50.0, 0.0, fill)
			if g1 > g0:
				var clear := Color(1, 1, 1, 0.0)
				var mid := (g0 + g1) * 0.5
				draw_polygon(_para(g0, mid, 0, h), PackedColorArray([clear, Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.45), clear]))
				draw_polygon(_para(mid, g1, 0, h), PackedColorArray([Color(1, 1, 1, 0.45), clear, clear, Color(1, 1, 1, 0.45)]))
			# Ponta brilhante
			draw_colored_polygon(_para(fill - 3, fill, -3, h + 3), Color(1, 1, 1, 0.95))
		# Marcas a cada 10 %
		for k in range(1, 10):
			var x := w * k / 10.0
			draw_line(Vector2(x + SKEW * 0.75, h * 0.25), Vector2(x + SKEW * 0.25, h * 0.75), Color(1, 1, 1, 0.22 if x > fill else 0.4), 2.0)
		# Bandeira quadriculada no fim da barra
		var cell := h / 4.0
		var fx := w + 12.0
		for row in 4:
			for col in 3:
				var dark := (row + col) % 2 == 0
				var y0 := row * cell
				var off := SKEW * (1.0 - (y0 + cell * 0.5) / h)
				var r := Rect2(fx + col * cell + off, y0, cell, cell)
				draw_rect(r, Color(0.05, 0.05, 0.08) if dark else Color(0.95, 0.96, 1.0))

	func _grad(t: float) -> Color:
		var c0 := Retro.c("accent_2")
		var c1 := Retro.c("accent_3")
		var c2 := Retro.c("accent")
		return c0.lerp(c1, t * 2.0) if t < 0.5 else c1.lerp(c2, (t - 0.5) * 2.0)
