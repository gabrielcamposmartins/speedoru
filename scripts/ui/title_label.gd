class_name TitleLabel
extends Control
## Título do jogador (conquistas e itens exclusivos). Os comuns são texto na cor do grau; os
## especiais (STYLES) têm fonte própria (assets/fonts/neon) e animação:
## * pulse: brilho que pulsa (Midnight);
## * shake: tremor curto de vez em quando, brilho vermelho (Winged Death);
## * glitch: cópias vermelha e ciano deslocadas em rajadas (Nightmare);
## * spark: um clarão que percorre as letras (Tempestade);
## * ghost: some e volta, flutuando (Fantasma);
## * sweep: dourado com um brilho deslizando (Soberano do Céu).
## draw_title() é estático: a Galeria e a roleta desenham o mesmo título nos cartões.

const FONTS := "res://assets/fonts/neon/"
## título -> {font, color, glow, anim}
const STYLES := {
	"Midnight": {"font": "Monoton-Regular.ttf", "color": Color("8fb8ff"), "glow": Color("2a4dff"), "anim": "pulse"},
	"Winged Death": {"font": "Rye-Regular.ttf", "color": Color("ff2a3d"), "glow": Color("7a0010"), "anim": "shake"},
	"Nightmare": {"font": "Bungee-Regular.ttf", "color": Color("c77dff"), "glow": Color("5a189a"), "anim": "glitch"},
	"Tempestade": {"font": "Righteous-Regular.ttf", "color": Color("7df9ff"), "glow": Color("1f6bff"), "anim": "spark"},
	"Fantasma": {"font": "Pacifico-Regular.ttf", "color": Color("e8f4ff"), "glow": Color("9fb3c8"), "anim": "ghost"},
	"Soberano do Céu": {"font": "Righteous-Regular.ttf", "color": Color("ffcf4a"), "glow": Color("b8860b"), "anim": "sweep"},
}

## Texto do título ("" = nenhum).
@export var text := "":
	set(value):
		text = value
		_resize()
		queue_redraw()
## Grau (1–5) para a cor dos títulos comuns (Progression.GRADE_COLORS).
@export var grade := 1:
	set(value):
		grade = value
		queue_redraw()
@export var font_size := 13:
	set(value):
		font_size = value
		_resize()
		queue_redraw()
## Cor dos títulos comuns quando não há grau (lista de amigos etc.).
var plain_color := Color(0, 0, 0, 0)

static var _fonts := {}


static func is_special(title: String) -> bool:
	return STYLES.has(title)


static func font_of(title: String) -> Font:
	if not STYLES.has(title):
		return Retro.body(700)
	var file: String = STYLES[title]["font"]
	if not _fonts.has(file):
		_fonts[file] = load(FONTS + file)
	return _fonts[file]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_resize()


func _process(_delta: float) -> void:
	if is_special(text) and is_visible_in_tree():
		queue_redraw()


func _resize() -> void:
	if text == "":
		custom_minimum_size = Vector2.ZERO
		return
	var fs := _size_for(text, font_size)
	var w := font_of(text).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	custom_minimum_size = Vector2(w + 8.0, fs * 1.45)


## Fontes decorativas são mais largas: um pouco menores para caber no mesmo lugar.
static func _size_for(title: String, fs: int) -> int:
	if title == "Midnight" or title == "Nightmare":
		return int(fs * 0.9)
	return fs


func _draw() -> void:
	if text == "":
		return
	var col: Color = plain_color if plain_color.a > 0.0 else Progression.GRADE_COLORS[clampi(grade, 1, 5) - 1]
	var fs := _size_for(text, font_size)
	draw_title(self, Vector2(4.0, size.y * 0.5 + fs * 0.36), text, fs, Time.get_ticks_msec() / 1000.0, col)


## Desenha [param title] com a linha de base em [param pos] (canto esquerdo).
static func draw_title(ci: CanvasItem, pos: Vector2, title: String, fs: int, t: float, color: Color, alpha := 1.0) -> void:
	if not STYLES.has(title):
		# Contorno escuro fino: legível também sobre a pista (apresentação dos carros)
		ci.draw_string_outline(Retro.body(700), pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(Retro.c("bg"), 0.7 * alpha))
		ci.draw_string(Retro.body(700), pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(color, color.a * alpha))
		return
	var st: Dictionary = STYLES[title]
	var font := font_of(title)
	var base: Color = st["color"]
	var glow: Color = st["glow"]
	match str(st["anim"]):
		"pulse":
			var k := 0.5 + 0.5 * sin(t * 2.4)
			ci.draw_string_outline(font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color(glow, (0.15 + 0.3 * k) * alpha))
			ci.draw_string_outline(font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(glow, (0.3 + 0.4 * k) * alpha))
			ci.draw_string(font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(base.lerp(Color.WHITE, 0.35 * k), alpha))
		"shake":
			# Tremor de 0,25 s a cada 2 s
			var phase := fmod(t, 2.0)
			var off := Vector2.ZERO
			if phase < 0.25:
				off = Vector2(sin(t * 90.0), cos(t * 77.0)) * 1.6
			ci.draw_string_outline(font, pos + off, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(glow, 0.6 * alpha))
			ci.draw_string_outline(font, pos + off, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, Color(0, 0, 0, 0.9 * alpha))
			ci.draw_string(font, pos + off, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(base, alpha))
		"glitch":
			var burst := fmod(t, 1.7) < 0.3
			var jx := (sin(t * 53.0) * 2.5) if burst else 0.0
			ci.draw_string_outline(font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(glow, 0.45 * alpha))
			if burst:
				ci.draw_string(font, pos + Vector2(jx, 0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.1, 0.3, 0.7 * alpha))
				ci.draw_string(font, pos - Vector2(jx, -1), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 1, 1, 0.7 * alpha))
			ci.draw_string(font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(base, alpha))
		"spark", "sweep":
			# Letra a letra: um clarão percorre o texto
			ci.draw_string_outline(font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(glow, 0.4 * alpha))
			var n := title.length()
			var head := fmod(t * (9.0 if st["anim"] == "spark" else 5.0), n + 6.0) - 3.0
			var x := pos.x
			for k in n:
				var ch := title[k]
				var d := absf(k - head)
				var lit := clampf(1.0 - d / 2.5, 0.0, 1.0)
				var c := base.lerp(Color.WHITE, lit * 0.85)
				if st["anim"] == "sweep":
					c = base.darkened(0.2).lerp(Color("fff6c8"), lit)
				ci.draw_char(font, Vector2(x, pos.y), ch, fs, Color(c, alpha))
				x += font.get_char_size(ch.unicode_at(0), fs).x
		"ghost":
			var k := 0.55 + 0.45 * sin(t * 1.6)
			var lift := sin(t * 1.1) * 1.5
			var p := pos + Vector2(0, lift)
			ci.draw_string_outline(font, p, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(glow, 0.25 * k * alpha))
			ci.draw_string(font, p, title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(base, (0.35 + 0.65 * k) * alpha))
