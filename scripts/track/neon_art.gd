class_name NeonArt
extends RefCounted
## Arte dos letreiros de Las Vegas (CityNeon) num atlas de textura (ATLAS_FILE). O atlas é gerado
## fora do jogo, pelo código deste arquivo: `godot --path . -s res://tools/build_neon_atlas.gd`
## desenha todas as células numa SubViewport 2D e salva o PNG (alfa pré-multiplicado); o Godot o
## importa comprimido (VRAM) e com mipmaps. Desenhar durante o jogo custaria ~1 s e deixaria
## centenas de MB de memória de vídeo presos (caches de glifos e reservas do driver). Os retângulos
## de UV (`uv`) vêm do mesmo arranjo (`_layout`), então mudar um desenho ou um tamanho de célula
## pede gerar o atlas de novo.
##
## O que há no atlas (cada célula = um desenho, com o halo de neon e fundo transparente):
## * nomes de hotel (`name:<i>`), cada um num estilo de letreiro: cursiva com sublinhado e estrela,
##   letras de marquise de cores alternadas, faroeste com estrelas, "Googie" com explosão atômica,
##   tubos múltiplos (Monoton), dólares de prata (uma letra por círculo), duas linhas em duas
##   fontes, texto dentro de seta;
## * palavras de cassino (`word:<i>`) e lâminas verticais (`blade:<i>`);
## * desenhos de neon sem texto (`icon:<nome>`): naipes, dados, cerejas, 777, martíni, coroa,
##   diamante, ferradura, fichas, roleta, palmeira, foguete, gato da sorte, carpa, dragão, planeta…;
## * as placas famosas (recriadas ou homenagens sem o nome de verdade): "Welcome to Fabulous Las
##   Vegas" (frente e verso; o desenho de Betty Willis é de domínio público), o caubói acenando (2
##   quadros, à moda do Vegas Vic), a vaqueira (Vegas Vickie), a guitarra gigante (Hard Rock), o
##   sapatinho (Silver Slipper), o pilar atômico (Stardust), o flamingo com plumas (Flamingo), a
##   ferradura (Binion's) e a lâmpada do gênio (Aladdin);
## * rolos de LED (`reel:<i>`): 4 quadros lado a lado que o shader alterna.

const ATLAS := Vector2i(4096, 3328)
const ATLAS_FILE := "res://assets/track/las_vegas/neon_atlas.png"
const PAD := 6
const FONT_DIR := "res://assets/fonts/neon/"

const PINK := Color("ff3fa4")
const CYAN := Color("3fe6ff")
const GOLD := Color("ffc93f")
const GREEN := Color("6dff6a")
const RED := Color("ff3b3b")
const PURPLE := Color("b26bff")
const ORANGE := Color("ff8a2a")
const BLUE := Color("4f8bff")
const WHITE := Color(1.0, 0.97, 0.92)
const COLORS := [PINK, CYAN, GOLD, GREEN, RED, PURPLE, ORANGE, BLUE]

const TOWER_NAMES := ["SAKURA PALACE", "NEON OASIS", "GOLDEN KOI", "LUCKY TANUKI", "ROYAL FLUSH", "THE ORBIT",
	"KITSUNE", "JACKPOT", "MOONLIGHT", "AURORA", "SILVER DRAGON", "FORTUNA", "MONARCH", "PHOENIX", "SAPPHIRE",
	"TOKYO NIGHTS", "SPEEDORU GRAND", "GACHA PALACE", "MOCHI BAY", "STARLIGHT", "LOTUS", "NEO VEGAS"]
const CASINO_WORDS := ["CASINO", "SLOTS", "POKER", "BLACKJACK", "LUCKY 7", "JACKPOT", "BINGO", "SHOWS", "BUFFET",
	"ROULETTE", "KENO", "GACHA x10", "WIN BIG", "OPEN 24H"]
const BLADE_WORDS := ["MOTEL", "BAR", "OPEN", "SLOTS", "CHAPEL", "PAWN", "LIQUOR", "DINER", "TACOS", "VACANCY",
	"GIFTS", "RAMEN", "KARAOKE", "ARCADE", "HOTEL", "CAFE", "SUSHI", "PIZZA"]
const STYLES := ["script", "marquee", "western", "googie", "tubes", "dollars", "stack", "arrow", "lobster"]
const ICONS := ["heart", "spade", "diamond", "club", "dice", "cherries", "seven", "martini", "crown", "gem",
	"horseshoe", "chips", "roulette", "palm", "rocket", "cat", "koi", "dragon", "planet", "star", "cards", "moon",
	"rings", "dollar"]
## Placas famosas: [id, tamanho da célula, quadros].
const FAMOUS := [["welcome", Vector2i(640, 640), 1], ["welcome_back", Vector2i(640, 640), 1],
	["cowboy", Vector2i(384, 608), 2], ["cowgirl", Vector2i(384, 608), 2], ["guitar", Vector2i(288, 832), 1],
	["slipper", Vector2i(512, 320), 1], ["atomic", Vector2i(288, 1024), 1], ["flamingo", Vector2i(512, 576), 1],
	["luckyshoe", Vector2i(512, 512), 1], ["genie", Vector2i(576, 384), 1]]
const REEL_FRAME := Vector2i(320, 160)
const REELS := 6

static var texture: Texture2D
static var _cells := {}
static var _mat: ShaderMaterial
static var _fonts := {}


## Material dos letreiros, com o atlas.
static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/track/vegas_sign.gdshader")
		if texture == null and ResourceLoader.exists(ATLAS_FILE):
			texture = load(ATLAS_FILE)
		_mat.set_shader_parameter("atlas", texture)
	return _mat


## Retângulo de UV da célula `id` (do 1º quadro, nas animadas). Vazio se não existir.
static func uv(id: String) -> Rect2:
	if _cells.is_empty():
		_layout()
	return _cells.get(id, [Rect2()])[0]


## Proporção largura/altura de um quadro da célula.
static func aspect(id: String) -> float:
	var r := uv(id)
	return (r.size.x * ATLAS.x) / maxf(r.size.y * ATLAS.y, 1.0)


## Deslocamento de UV entre quadros e número de quadros (animadas).
static func frames(id: String) -> Array:
	if _cells.is_empty():
		_layout()
	var c: Array = _cells.get(id, [Rect2(), 1])
	return [Vector2(c[0].size.x, 0.0), int(c[1])]


## Desenha o atlas inteiro (com janela; para tools/build_neon_atlas.gd): imagem RGBA com alfa
## pré-multiplicado, ou null sem placa de vídeo.
static func render(host: Node) -> Image:
	if _cells.is_empty():
		_layout()
	var vp := SubViewport.new()
	vp.size = ATLAS
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := Painter.new()
	painter.size = Vector2(ATLAS)
	vp.add_child(painter)
	host.add_child(vp)
	for k in 2:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


# ---------------------------------------------------------------------------
# Lista e arranjo das células
# ---------------------------------------------------------------------------
## [id, tamanho, quadros, desenho(ci, tamanho do quadro, quadro)]
static func _jobs() -> Array:
	var out := []
	for i in TOWER_NAMES.size():
		var style: String = STYLES[i % STYLES.size()]
		var name: String = TOWER_NAMES[i]
		out.append(["name:%d" % i, Vector2i(640, 160), 1, func(ci: CanvasItem, s: Vector2, _f: int) -> void:
			_text_style(ci, s, name, style, i)])
	for i in CASINO_WORDS.size():
		var style: String = ["marquee", "script", "tubes", "googie", "western", "lobster", "dollars"][i % 7]
		var word: String = CASINO_WORDS[i]
		out.append(["word:%d" % i, Vector2i(448, 160), 1, func(ci: CanvasItem, s: Vector2, _f: int) -> void:
			_text_style(ci, s, word, style, i + 3)])
	for i in BLADE_WORDS.size():
		var word: String = BLADE_WORDS[i]
		out.append(["blade:%d" % i, Vector2i(112, 448), 1, func(ci: CanvasItem, s: Vector2, _f: int) -> void:
			_blade(ci, s, word, i)])
	for name: String in ICONS:
		out.append(["icon:" + name, Vector2i(224, 224), 1, func(ci: CanvasItem, s: Vector2, _f: int) -> void:
			_icon(ci, s, name)])
	for f: Array in FAMOUS:
		var id: String = f[0]
		out.append(["famous:" + id, f[1], f[2], func(ci: CanvasItem, s: Vector2, frame: int) -> void:
			_famous(ci, s, id, frame)])
	for i in REELS:
		out.append(["reel:%d" % i, REEL_FRAME, 4, func(ci: CanvasItem, s: Vector2, frame: int) -> void:
			_reel(ci, s, i, frame)])
	return out


## Arranjo em prateleiras (as mais altas primeiro).
static func _layout() -> void:
	_cells.clear()
	var jobs := _jobs()
	jobs.sort_custom(func(a: Array, b: Array) -> bool: return (a[1] as Vector2i).y > (b[1] as Vector2i).y)
	var x := 0
	var y := 0
	var shelf := 0
	for j in jobs:
		var size: Vector2i = j[1]
		var w: int = size.x * int(j[2]) + PAD * 2
		var h: int = size.y + PAD * 2
		if x + w > ATLAS.x:
			x = 0
			y += shelf
			shelf = 0
		if y + h > ATLAS.y:
			push_warning("NeonArt: atlas cheio, %s ficou de fora" % j[0])
			continue
		var r := Rect2(Vector2(x + PAD, y + PAD) / Vector2(ATLAS), Vector2(size) / Vector2(ATLAS))
		_cells[j[0]] = [r, j[2], Vector2i(x + PAD, y + PAD), j[3], size]
		x += w
		shelf = maxi(shelf, h)


## Desenha todas as células na SubViewport.
class Painter extends Control:
	## Origem da célula sendo desenhada.
	var origin := Vector2.ZERO

	func _draw() -> void:
		for id in NeonArt._cells:
			var c: Array = NeonArt._cells[id]
			var size: Vector2i = c[4]
			for f in int(c[1]):
				origin = Vector2(c[2] + Vector2i(size.x * f, 0))
				draw_set_transform(origin)
				(c[3] as Callable).call(self, Vector2(size), f)
		draw_set_transform(Vector2.ZERO)


# ---------------------------------------------------------------------------
# Ferramentas de desenho: tubos de neon e texto com halo
# ---------------------------------------------------------------------------
static func font(name: String) -> Font:
	if not _fonts.has(name):
		_fonts[name] = load(FONT_DIR + name + "-Regular.ttf")
	return _fonts[name]


## Tubo de neon: halo largo e fraco, tubo colorido e o miolo quase branco.
static func tube(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, closed := false) -> void:
	if pts.size() < 2:
		return
	if closed:
		pts.append(pts[0])
	ci.draw_polyline(pts, Color(col, 0.09), w * 5.0, true)
	ci.draw_polyline(pts, Color(col, 0.22), w * 2.6, true)
	ci.draw_polyline(pts, col, w, true)
	ci.draw_polyline(pts, col.lerp(Color.WHITE, 0.65), w * 0.35, true)


## Forma cheia com contorno de neon (painel pintado e iluminado).
static func fill(ci: CanvasItem, pts: PackedVector2Array, body: Color, edge: Color, w: float) -> void:
	ci.draw_colored_polygon(pts, body)
	tube(ci, pts, edge, w, true)


static func arc(c: Vector2, r: Vector2, a0: float, a1: float, n := 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n + 1:
		var a := lerpf(a0, a1, float(k) / n)
		out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return out


static func circle(c: Vector2, r: float, n := 32) -> PackedVector2Array:
	var p := arc(c, Vector2(r, r), 0.0, TAU, n)
	p.remove_at(p.size() - 1)
	return p


static func star(c: Vector2, r_out: float, r_in: float, points := 5, rot := -PI * 0.5) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in points * 2:
		var a := rot + PI * k / points
		out.append(c + Vector2(cos(a), sin(a)) * (r_out if k % 2 == 0 else r_in))
	return out


## Curva de Bézier quadrática.
static func bez(a: Vector2, b: Vector2, c: Vector2, n := 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n + 1:
		var t := float(k) / n
		out.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return out


## Tamanho de fonte para `text` caber em `max_w` x `max_h`.
static func fit(f: Font, text: String, max_w: float, max_h: float) -> int:
	var fs := int(max_h)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if w > max_w:
		fs = int(fs * max_w / w)
	return maxi(fs, 8)


## Texto de neon centrado em `c` (cores por letra, em ciclo), com halo.
static func glow_text(ci: CanvasItem, f: Font, text: String, c: Vector2, fs: int, cols: Array, core := 0.55,
		tube_w := 0.06) -> void:
	var size := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var base := Vector2(c.x - size.x * 0.5, c.y + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5)
	for pass_i in 4:
		var x := base.x
		var k := 0
		for ch in text:
			var col: Color = cols[k % cols.size()]
			var code := ch.unicode_at(0)
			var p := Vector2(x, base.y)
			match pass_i:
				0:
					ci.draw_char_outline(f, p, ch, fs, int(fs * 0.3), Color(col, 0.1))
				1:
					ci.draw_char_outline(f, p, ch, fs, int(fs * 0.14), Color(col, 0.28))
				2:
					ci.draw_char_outline(f, p, ch, fs, maxi(int(fs * tube_w), 2), col)
				3:
					ci.draw_char(f, p, ch, fs, col.lerp(Color.WHITE, core))
			x += f.get_char_size(code, fs).x
			if ch != " ":
				k += 1


# ---------------------------------------------------------------------------
# Estilos de texto
# ---------------------------------------------------------------------------
static func _pal(seed: int) -> Array:
	return [COLORS[seed % COLORS.size()], COLORS[(seed * 3 + 2) % COLORS.size()], COLORS[(seed * 5 + 4) % COLORS.size()]]


static func _text_style(ci: CanvasItem, s: Vector2, text: String, style: String, seed: int) -> void:
	var p := _pal(seed)
	var c1: Color = p[0]
	var c2: Color = p[1] if p[1] != c1 else p[2]
	var mid := s * 0.5
	match style:
		"script", "lobster":
			var f := font("Pacifico" if style == "script" else "Lobster")
			var t := text.capitalize() if style == "script" else text.to_lower().capitalize()
			var fs := fit(f, t, s.x * 0.86, s.y * 0.62)
			glow_text(ci, f, t, mid + Vector2(0, -s.y * 0.08), fs, [c1] if style == "script" else [c2, c1, c1, c1, c1, c1, c1, c1, c1, c1, c1, c1, c1, c1])
			# Sublinhado em curva terminando numa estrela
			var y := s.y * 0.8
			tube(ci, bez(Vector2(s.x * 0.12, y), Vector2(s.x * 0.5, y + s.y * 0.14), Vector2(s.x * 0.84, y - s.y * 0.04)), c2, s.y * 0.03)
			tube(ci, star(Vector2(s.x * 0.89, y - s.y * 0.06), s.y * 0.1, s.y * 0.04), GOLD, s.y * 0.02, true)
		"marquee":
			var f := font("Bungee")
			glow_text(ci, f, text, mid, fit(f, text, s.x * 0.9, s.y * 0.6), [c1, c2, GOLD, CYAN], 0.45)
		"western":
			var f := font("Rye")
			glow_text(ci, f, text, mid, fit(f, text, s.x * 0.72, s.y * 0.58), [c1], 0.5)
			for side in [-1.0, 1.0]:
				var sc := Vector2(mid.x + side * s.x * 0.44, mid.y)
				tube(ci, star(sc, s.y * 0.2, s.y * 0.08), c2, s.y * 0.025, true)
		"googie":
			# Explosão atômica atrás (raios de tamanhos diferentes) e bumerangues
			var sc := Vector2(s.x * 0.12, s.y * 0.3)
			for k in 12:
				var a := TAU * k / 12.0
				var r := s.y * (0.28 if k % 2 == 0 else 0.16)
				tube(ci, PackedVector2Array([sc, sc + Vector2(cos(a), sin(a)) * r]), c2, s.y * 0.015)
			tube(ci, bez(Vector2(s.x * 0.62, s.y * 0.9), Vector2(s.x * 0.8, s.y * 0.7), Vector2(s.x * 0.97, s.y * 0.92)), CYAN, s.y * 0.025)
			var f := font("Righteous")
			glow_text(ci, f, text, mid + Vector2(s.x * 0.05, -s.y * 0.04), fit(f, text, s.x * 0.78, s.y * 0.6), [c1, c1, c2], 0.5)
		"tubes":
			var f := font("Monoton")
			glow_text(ci, f, text, mid, fit(f, text, s.x * 0.92, s.y * 0.66), [c1], 0.35, 0.03)
		"dollars":
			# Uma letra por círculo de "dólar de prata" (como o WELCOME da placa famosa)
			var letters := text.replace(" ", "")
			var n := letters.length()
			var r := minf(s.x / (n * 2.2), s.y * 0.4)
			var f := font("Bungee")
			for k in n:
				var cc := Vector2(mid.x + (k - (n - 1) * 0.5) * r * 2.15, mid.y)
				fill(ci, circle(cc, r), Color(0.92, 0.92, 0.95), WHITE, r * 0.08)
				glow_text(ci, f, letters[k], cc, int(r * 1.2), [RED], 0.1, 0.02)
		"stack":
			var words := text.split(" ")
			var top := words[0] if words.size() > 1 else "THE"
			var big := " ".join(words.slice(1)) if words.size() > 1 else text
			var f1 := font("Righteous")
			var f2 := font("Bungee")
			glow_text(ci, f1, top, Vector2(mid.x, s.y * 0.22), fit(f1, top, s.x * 0.5, s.y * 0.28), [c2], 0.5)
			glow_text(ci, f2, big, Vector2(mid.x, s.y * 0.64), fit(f2, big, s.x * 0.92, s.y * 0.52), [c1, c1.lightened(0.35)], 0.45)
		"arrow":
			# Seta de lâmpadas apontando para o nome
			var body := PackedVector2Array([Vector2(s.x * 0.04, s.y * 0.2), Vector2(s.x * 0.82, s.y * 0.2),
				Vector2(s.x * 0.97, s.y * 0.5), Vector2(s.x * 0.82, s.y * 0.8), Vector2(s.x * 0.04, s.y * 0.8), Vector2(s.x * 0.12, s.y * 0.5)])
			fill(ci, body, Color(0.05, 0.03, 0.09, 0.92), c2, s.y * 0.03)
			var k := 0.0
			while k < 1.0:
				ci.draw_circle(Vector2(lerpf(s.x * 0.08, s.x * 0.8, k), s.y * 0.11), s.y * 0.025, Color(1, 0.86, 0.5))
				k += 0.035
			var f := font("Bungee")
			glow_text(ci, f, text, Vector2(s.x * 0.47, mid.y), fit(f, text, s.x * 0.66, s.y * 0.44), [c1], 0.5)


## Lâmina vertical: letras empilhadas, duas cores alternadas, estrela no alto.
static func _blade(ci: CanvasItem, s: Vector2, word: String, seed: int) -> void:
	var p := _pal(seed + 1)
	var f := font(["Bungee", "Rye", "Righteous", "Monoton", "Lobster"][seed % 5])
	var n := word.length()
	var step := minf((s.y - s.x * 0.9) / n, s.x * 0.95)
	var fs := int(step * 0.92)
	var y0 := s.x * 0.8 + step * 0.5
	tube(ci, star(Vector2(s.x * 0.5, s.x * 0.42), s.x * 0.3, s.x * 0.12), GOLD, s.x * 0.04, true)
	for k in n:
		glow_text(ci, f, word[k], Vector2(s.x * 0.5, y0 + k * step), fs, [p[k % 2]], 0.5)


# ---------------------------------------------------------------------------
# Desenhos (ícones de neon)
# ---------------------------------------------------------------------------
static func _icon(ci: CanvasItem, s: Vector2, name: String) -> void:
	var c := s * 0.5
	var u := s.x / 256.0
	var w := 7.0 * u
	match name:
		"heart":
			tube(ci, _heart(c, 90 * u), RED, w, true)
			tube(ci, _heart(c, 62 * u), PINK, w * 0.7, true)
		"spade":
			var h := _heart(c + Vector2(0, -6 * u), 82 * u)
			for i in h.size():
				h[i] = c * 2.0 - h[i] + Vector2(0, -12 * u)
			tube(ci, h, CYAN, w, true)
			tube(ci, PackedVector2Array([c + Vector2(0, 30 * u), c + Vector2(-26 * u, 100 * u), c + Vector2(26 * u, 100 * u)]), CYAN, w, true)
		"diamond":
			tube(ci, PackedVector2Array([c + Vector2(0, -100 * u), c + Vector2(70 * u, 0), c + Vector2(0, 100 * u), c + Vector2(-70 * u, 0)]), RED, w, true)
			tube(ci, PackedVector2Array([c + Vector2(0, -60 * u), c + Vector2(40 * u, 0), c + Vector2(0, 60 * u), c + Vector2(-40 * u, 0)]), GOLD, w * 0.6, true)
		"club":
			for o in [Vector2(0, -42), Vector2(-42, 8), Vector2(42, 8)]:
				tube(ci, circle(c + o * u, 36 * u), GREEN, w, true)
			tube(ci, PackedVector2Array([c + Vector2(0, 20 * u), c + Vector2(-24 * u, 100 * u), c + Vector2(24 * u, 100 * u)]), GREEN, w, true)
		"dice":
			for d: Array in [[Vector2(-40, -10), -0.25, 5], [Vector2(48, 20), 0.3, 3]]:
				var dc: Vector2 = c + (d[0] as Vector2) * u
				var rot: float = d[1]
				var sq := PackedVector2Array()
				for k in 4:
					sq.append(dc + Vector2(cos(rot + PI * 0.25 + k * PI * 0.5), sin(rot + PI * 0.25 + k * PI * 0.5)) * 62 * u)
				fill(ci, sq, Color(0.95, 0.95, 0.95, 0.95), RED, w * 0.8)
				var pips := [[0, 0], [-1, -1], [1, 1], [-1, 1], [1, -1]] if int(d[2]) == 5 else [[0, 0], [-1, -1], [1, 1]]
				for pp: Array in pips:
					var o := Vector2(pp[0], pp[1]).rotated(rot) * 24 * u
					ci.draw_circle(dc + o, 8 * u, RED)
		"cherries":
			tube(ci, bez(c + Vector2(-40 * u, 40 * u), c + Vector2(-20 * u, -60 * u), c + Vector2(30 * u, -90 * u)), GREEN, w * 0.8)
			tube(ci, bez(c + Vector2(45 * u, 50 * u), c + Vector2(40 * u, -40 * u), c + Vector2(30 * u, -90 * u)), GREEN, w * 0.8)
			tube(ci, PackedVector2Array([c + Vector2(30 * u, -90 * u), c + Vector2(80 * u, -100 * u), c + Vector2(60 * u, -70 * u)]), GREEN, w * 0.7, true)
			fill(ci, circle(c + Vector2(-40 * u, 62 * u), 34 * u), Color(0.6, 0.02, 0.08, 0.9), RED, w)
			fill(ci, circle(c + Vector2(48 * u, 70 * u), 34 * u), Color(0.6, 0.02, 0.08, 0.9), RED, w)
		"seven":
			glow_text(ci, font("Bungee"), "777", c, int(120 * u), [RED, GOLD, RED], 0.45)
		"martini":
			tube(ci, PackedVector2Array([c + Vector2(-80 * u, -80 * u), c + Vector2(80 * u, -80 * u), c + Vector2(0, 10 * u)]), CYAN, w, true)
			tube(ci, PackedVector2Array([c + Vector2(0, 10 * u), c + Vector2(0, 90 * u)]), CYAN, w)
			tube(ci, PackedVector2Array([c + Vector2(-46 * u, 92 * u), c + Vector2(46 * u, 92 * u)]), CYAN, w)
			fill(ci, circle(c + Vector2(-12 * u, -46 * u), 16 * u), Color(0.2, 0.5, 0.1, 0.9), GREEN, w * 0.6)
			tube(ci, PackedVector2Array([c + Vector2(-12 * u, -46 * u), c + Vector2(40 * u, -110 * u)]), PINK, w * 0.5)
		"crown":
			tube(ci, PackedVector2Array([c + Vector2(-90 * u, 60 * u), c + Vector2(-100 * u, -50 * u), c + Vector2(-48 * u, 0),
				c + Vector2(0, -80 * u), c + Vector2(48 * u, 0), c + Vector2(100 * u, -50 * u), c + Vector2(90 * u, 60 * u)]), GOLD, w, true)
			for k in 3:
				ci.draw_circle(c + Vector2((k - 1) * 50 * u, 30 * u), 10 * u, [RED, CYAN, GREEN][k])
		"gem":
			var g := PackedVector2Array([c + Vector2(-90 * u, -30 * u), c + Vector2(-50 * u, -80 * u), c + Vector2(50 * u, -80 * u),
				c + Vector2(90 * u, -30 * u), c + Vector2(0, 95 * u)])
			fill(ci, g, Color(0.1, 0.5, 0.75, 0.55), CYAN, w)
			tube(ci, PackedVector2Array([c + Vector2(-90 * u, -30 * u), c + Vector2(90 * u, -30 * u)]), CYAN, w * 0.6)
			tube(ci, PackedVector2Array([c + Vector2(-40 * u, -30 * u), c + Vector2(0, 95 * u), c + Vector2(40 * u, -30 * u)]), WHITE, w * 0.4)
		"horseshoe":
			tube(ci, arc(c + Vector2(0, 10 * u), Vector2(80, 90) * u, PI * 0.82, PI * 2.18, 30), GOLD, w * 2.2)
			for k in 7:
				var a := lerpf(PI * 0.9, PI * 2.1, k / 6.0)
				ci.draw_circle(c + Vector2(0, 10 * u) + Vector2(cos(a) * 80, sin(a) * 90) * u, 7 * u, Color(0.35, 0.2, 0.05))
		"chips":
			for k in 3:
				var cc := c + Vector2((k - 1) * 46 * u, (k % 2) * 30 * u - 15 * u)
				var col: Color = [RED, BLUE, GREEN][k]
				fill(ci, circle(cc, 52 * u), Color(col.darkened(0.5), 0.9), col, w * 0.8)
				tube(ci, circle(cc, 30 * u), WHITE, w * 0.4, true)
		"roulette":
			tube(ci, circle(c, 100 * u), GOLD, w, true)
			for k in 16:
				var a := TAU * k / 16.0
				var wedge := PackedVector2Array([c + Vector2(cos(a), sin(a)) * 40 * u, c + Vector2(cos(a), sin(a)) * 90 * u,
					c + Vector2(cos(a + TAU / 16.0), sin(a + TAU / 16.0)) * 90 * u, c + Vector2(cos(a + TAU / 16.0), sin(a + TAU / 16.0)) * 40 * u])
				ci.draw_colored_polygon(wedge, Color(0.8, 0.05, 0.05, 0.9) if k % 2 == 0 else Color(0.05, 0.05, 0.06, 0.9))
			tube(ci, circle(c, 40 * u), GOLD, w * 0.7, true)
			ci.draw_circle(c + Vector2(0, -66 * u), 9 * u, WHITE)
		"palm":
			tube(ci, bez(c + Vector2(10 * u, 110 * u), c + Vector2(-10 * u, 20 * u), c + Vector2(10 * u, -50 * u)), ORANGE, w * 1.2)
			for k in 6:
				var a := -PI * 0.95 + k * PI * 0.38
				var tip := c + Vector2(10 * u, -50 * u) + Vector2(cos(a), sin(a) * 0.6 + 0.4) * 95 * u
				tube(ci, bez(c + Vector2(10 * u, -50 * u), c + Vector2(10 * u, -50 * u) + Vector2(cos(a), -0.6) * 60 * u, tip), GREEN, w * 0.8)
		"rocket":
			var body := PackedVector2Array([c + Vector2(0, -110 * u), c + Vector2(30 * u, -50 * u), c + Vector2(30 * u, 50 * u),
				c + Vector2(-30 * u, 50 * u), c + Vector2(-30 * u, -50 * u)])
			fill(ci, body, Color(0.85, 0.85, 0.9, 0.85), RED, w * 0.8)
			fill(ci, circle(c + Vector2(0, -30 * u), 14 * u), Color(0.2, 0.6, 0.9), CYAN, w * 0.4)
			for side in [-1.0, 1.0]:
				tube(ci, PackedVector2Array([c + Vector2(side * 30 * u, 10 * u), c + Vector2(side * 60 * u, 70 * u), c + Vector2(side * 30 * u, 50 * u)]), RED, w * 0.8, true)
			tube(ci, PackedVector2Array([c + Vector2(-18 * u, 58 * u), c + Vector2(0, 115 * u), c + Vector2(18 * u, 58 * u)]), ORANGE, w, true)
		"cat":
			# Gato da sorte (maneki-neko) acenando
			fill(ci, circle(c + Vector2(0, 40 * u), 62 * u), Color(0.95, 0.95, 0.92, 0.9), GOLD, w * 0.7)
			fill(ci, circle(c + Vector2(0, -40 * u), 50 * u), Color(0.95, 0.95, 0.92, 0.9), GOLD, w * 0.7)
			for side in [-1.0, 1.0]:
				tube(ci, PackedVector2Array([c + Vector2(side * 18 * u, -82 * u), c + Vector2(side * 42 * u, -108 * u), c + Vector2(side * 46 * u, -66 * u)]), GOLD, w * 0.6, true)
				ci.draw_circle(c + Vector2(side * 18 * u, -44 * u), 6 * u, Color(0.1, 0.1, 0.1))
			tube(ci, PackedVector2Array([c + Vector2(50 * u, 0), c + Vector2(80 * u, -60 * u)]), GOLD, w * 1.4)
			ci.draw_circle(c + Vector2(0, 0), 10 * u, RED)
			glow_text(ci, font("Bungee"), "$", c + Vector2(0, 50 * u), int(56 * u), [GOLD], 0.4)
		"koi":
			var body := PackedVector2Array()
			for k in 25:
				var t := k / 24.0
				body.append(c + Vector2(lerpf(-90, 70, t), sin(t * PI) * -38 + sin(t * TAU) * 6) * u)
			for k in range(24, -1, -1):
				var t := k / 24.0
				body.append(c + Vector2(lerpf(-90, 70, t), sin(t * PI) * 38 + sin(t * TAU) * 6) * u)
			fill(ci, body, Color(0.95, 0.4, 0.1, 0.85), ORANGE, w * 0.7)
			tube(ci, PackedVector2Array([c + Vector2(70 * u, 0), c + Vector2(110 * u, -40 * u), c + Vector2(100 * u, 0), c + Vector2(110 * u, 40 * u)]), ORANGE, w * 0.7, true)
			ci.draw_circle(c + Vector2(-62 * u, -8 * u), 6 * u, Color(0.05, 0.05, 0.05))
			ci.draw_circle(c + Vector2(-5 * u, -10 * u), 14 * u, WHITE)
		"dragon":
			var pts := PackedVector2Array()
			for k in 40:
				var t := k / 39.0
				pts.append(c + Vector2(lerpf(-100, 100, t), sin(t * TAU * 1.5) * 50) * u)
			tube(ci, pts, GREEN, w * 1.6)
			for k in range(2, 38, 4):
				tube(ci, PackedVector2Array([pts[k], pts[k] + Vector2(0, -16 * u)]), GOLD, w * 0.5)
			var head := pts[pts.size() - 1]
			tube(ci, PackedVector2Array([head + Vector2(-10, -20) * u, head + Vector2(26, -6) * u, head + Vector2(-6, 14) * u]), GREEN, w, true)
			tube(ci, bez(head + Vector2(-6, -18) * u, head + Vector2(-20, -50) * u, head + Vector2(-40, -40) * u), GOLD, w * 0.5)
			tube(ci, bez(head + Vector2(20, 4) * u, head + Vector2(50, 10) * u, head + Vector2(60, -12) * u), RED, w * 0.6)
		"planet":
			fill(ci, circle(c, 62 * u), Color(0.45, 0.2, 0.7, 0.85), PURPLE, w)
			tube(ci, arc(c, Vector2(115, 30) * u, -0.3, PI + 0.3, 24), CYAN, w * 0.8)
			tube(ci, star(c + Vector2(80, -80) * u, 16 * u, 6 * u, 4), GOLD, w * 0.4, true)
		"star":
			tube(ci, star(c, 108 * u, 44 * u), GOLD, w, true)
			tube(ci, star(c, 66 * u, 27 * u), PINK, w * 0.7, true)
		"cards":
			for k in 3:
				var rot := (k - 1) * 0.35
				var cc := c + Vector2((k - 1) * 30 * u, 10 * u)
				var sq := PackedVector2Array()
				for v in [Vector2(-42, -62), Vector2(42, -62), Vector2(42, 62), Vector2(-42, 62)]:
					sq.append(cc + (v * u).rotated(rot))
				fill(ci, sq, Color(0.97, 0.97, 0.97, 0.95), [RED, BLUE, RED][k], w * 0.6)
			glow_text(ci, font("Bungee"), "A", c + Vector2(30 * u, 10 * u), int(60 * u), [RED], 0.1, 0.02)
		"moon":
			var outer := arc(c, Vector2(95, 95) * u, PI * 0.35, PI * 1.65, 26)
			var inner := arc(c + Vector2(-35, 0) * u, Vector2(72, 80) * u, PI * 1.5, PI * 0.5, 26)
			outer.append_array(inner)
			tube(ci, outer, GOLD, w, true)
			tube(ci, star(c + Vector2(70, -40) * u, 18 * u, 7 * u), CYAN, w * 0.5, true)
		"rings":
			tube(ci, circle(c + Vector2(-30, 10) * u, 52 * u), GOLD, w, true)
			tube(ci, circle(c + Vector2(30, 10) * u, 52 * u), GOLD, w, true)
			tube(ci, _heart(c + Vector2(0, -78) * u, 22 * u), PINK, w * 0.6, true)
		"dollar":
			glow_text(ci, font("Rye"), "$", c, int(200 * u), [GREEN], 0.5)


static func _heart(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 40:
		var t := TAU * k / 40.0
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		out.append(c + Vector2(x, y) * r / 16.0)
	return out


# ---------------------------------------------------------------------------
# Placas famosas
# ---------------------------------------------------------------------------
static func _famous(ci: CanvasItem, s: Vector2, id: String, frame: int) -> void:
	var u := s.x / 512.0
	match id:
		"welcome", "welcome_back":
			_welcome(ci, s, id == "welcome")
		"cowboy", "cowgirl":
			_cowboy(ci, s, frame, id == "cowgirl")
		"guitar":
			var c := Vector2(s.x * 0.5, s.y * 0.72)
			var body := PackedVector2Array()
			for k in 48:
				var a := TAU * k / 48.0
				var r := 1.0 + 0.16 * cos(a * 2.0 + PI) - (0.12 if (a > PI * 1.2 and a < PI * 1.5) else 0.0)
				body.append(c + Vector2(cos(a) * s.x * 0.42, sin(a) * s.x * 0.52) * r)
			# Sunburst: vermelho na borda, dourado no meio
			ci.draw_colored_polygon(body, Color(0.55, 0.05, 0.05, 0.95))
			ci.draw_colored_polygon(circle(c, s.x * 0.28, 32), Color(0.95, 0.6, 0.12, 0.95))
			tube(ci, body, GOLD, 6 * u, true)
			ci.draw_rect(Rect2(c + Vector2(-s.x * 0.06, -s.y * 0.66), Vector2(s.x * 0.12, s.y * 0.62)), Color(0.3, 0.16, 0.06))
			tube(ci, PackedVector2Array([c + Vector2(-s.x * 0.06, -s.y * 0.66), c + Vector2(-s.x * 0.06, -s.y * 0.05)]), WHITE, 3 * u)
			tube(ci, PackedVector2Array([c + Vector2(s.x * 0.06, -s.y * 0.66), c + Vector2(s.x * 0.06, -s.y * 0.05)]), WHITE, 3 * u)
			var hs := PackedVector2Array([c + Vector2(-s.x * 0.1, -s.y * 0.66), c + Vector2(s.x * 0.1, -s.y * 0.66),
				c + Vector2(s.x * 0.14, -s.y * 0.71), c + Vector2(-s.x * 0.12, -s.y * 0.71)])
			fill(ci, hs, Color(0.12, 0.08, 0.06), GOLD, 4 * u)
			for k in 3:
				ci.draw_rect(Rect2(c + Vector2(-s.x * 0.2, -s.y * 0.04 + k * s.y * 0.05), Vector2(s.x * 0.4, s.y * 0.012)), WHITE)
			tube(ci, circle(c + Vector2(s.x * 0.2, s.y * 0.08), s.x * 0.04), WHITE, 3 * u, true)
		"slipper":
			var pts := PackedVector2Array([Vector2(0.06, 0.62), Vector2(0.2, 0.5), Vector2(0.45, 0.48), Vector2(0.62, 0.3),
				Vector2(0.86, 0.12), Vector2(0.95, 0.2), Vector2(0.9, 0.86), Vector2(0.84, 0.86), Vector2(0.8, 0.5),
				Vector2(0.55, 0.76), Vector2(0.1, 0.78)])
			for i in pts.size():
				pts[i] *= s
			fill(ci, pts, Color(0.75, 0.8, 0.9, 0.85), WHITE, 6 * u)
			var rng := RandomNumberGenerator.new()
			rng.seed = 11
			for k in 18:
				var p := Vector2(rng.randf_range(0.12, 0.85), rng.randf_range(0.5, 0.72)) * s
				tube(ci, star(p, 9 * u, 3 * u, 4), CYAN, 2 * u, true)
		"atomic":
			# Pilar estelar: explosão no alto, letras empilhadas, bumerangues
			var top := Vector2(s.x * 0.5, s.x * 0.5)
			for k in 16:
				var a := TAU * k / 16.0
				tube(ci, PackedVector2Array([top, top + Vector2(cos(a), sin(a)) * s.x * (0.45 if k % 2 == 0 else 0.25)]), [GOLD, PINK][k % 2], 4 * u)
			ci.draw_circle(top, s.x * 0.06, WHITE)
			var f := font("Righteous")
			var word := "ATOMIC"
			var step := (s.y - s.x * 1.1) / word.length()
			for k in word.length():
				glow_text(ci, f, word[k], Vector2(s.x * 0.5, s.x * 1.05 + (k + 0.5) * step), int(step * 0.8),
					[[CYAN, PINK, GOLD][k % 3]], 0.5)
		"flamingo":
			var c := s * 0.5
			# Plumas em leque atrás
			for k in 7:
				var a := -PI * 0.92 + k * PI * 0.14
				var tip := c + Vector2(cos(a), sin(a)) * s.x * 0.5
				tube(ci, bez(c + Vector2(0, s.y * 0.05), c + Vector2(cos(a), sin(a)) * s.x * 0.3 + Vector2(0, -20 * u), tip), [PINK, ORANGE][k % 2], 9 * u)
			# Pássaro: corpo, pescoço em S, cabeça, bico e uma perna
			fill(ci, arc(c + Vector2(30, 60) * u, Vector2(110, 60) * u, 0.0, TAU, 28), Color(0.95, 0.35, 0.6, 0.9), PINK, 6 * u)
			tube(ci, bez(c + Vector2(-60, 40) * u, c + Vector2(-150, -40) * u, c + Vector2(-70, -150) * u), PINK, 14 * u)
			fill(ci, circle(c + Vector2(-60, -160) * u, 24 * u), Color(0.95, 0.35, 0.6, 0.9), PINK, 5 * u)
			tube(ci, PackedVector2Array([c + Vector2(-40, -165) * u, c + Vector2(-5, -140) * u, c + Vector2(-30, -150) * u]), GOLD, 5 * u)
			tube(ci, PackedVector2Array([c + Vector2(40, 115) * u, c + Vector2(40, 240) * u]), PINK, 6 * u)
			tube(ci, PackedVector2Array([c + Vector2(40, 175) * u, c + Vector2(80, 150) * u, c + Vector2(50, 130) * u]), PINK, 5 * u)
		"luckyshoe":
			var c := Vector2(s.x * 0.5, s.y * 0.44)
			tube(ci, arc(c, Vector2(160, 170) * u, PI * 0.78, PI * 2.22, 34), GOLD, 26 * u)
			for k in 8:
				var a := lerpf(PI * 0.85, PI * 2.15, k / 7.0)
				ci.draw_circle(c + Vector2(cos(a) * 160, sin(a) * 170) * u, 9 * u, WHITE)
			glow_text(ci, font("Rye"), "LUCKY", Vector2(s.x * 0.5, s.y * 0.86), int(86 * u), [RED], 0.5)
		"genie":
			var c := Vector2(s.x * 0.45, s.y * 0.66)
			var lamp := PackedVector2Array()
			lamp.append_array(arc(c, Vector2(150, 62) * u, 0.0, PI, 20))
			lamp.append_array(PackedVector2Array([c + Vector2(-235, -55) * u, c + Vector2(-130, -30) * u,
				c + Vector2(-60, -60) * u, c + Vector2(60, -60) * u]))
			fill(ci, lamp, Color(0.85, 0.6, 0.15, 0.9), GOLD, 6 * u)
			tube(ci, arc(c + Vector2(190, -10) * u, Vector2(45, 45) * u, -PI * 0.5, PI * 0.5, 14), GOLD, 7 * u)
			fill(ci, circle(c + Vector2(0, -80) * u, 22 * u), Color(0.85, 0.6, 0.15, 0.9), GOLD, 4 * u)
			# Fumaça em espiral subindo do bico
			var smoke := PackedVector2Array()
			for k in 40:
				var t := k / 39.0
				smoke.append(c + Vector2(-225, -70) * u + Vector2(sin(t * TAU * 1.6) * 40 * t, -t * 200) * u)
			tube(ci, smoke, PURPLE, 8 * u)
			tube(ci, star(c + Vector2(-190, -290) * u, 26 * u, 10 * u), CYAN, 4 * u, true)


## "Welcome to Fabulous Las Vegas Nevada": losango esticado de lados arredondados, branco,
## borda de lâmpadas; WELCOME em sete "dólares de prata"; verso "Drive Carefully / Come Back Soon".
static func _welcome(ci: CanvasItem, s: Vector2, front: bool) -> void:
	var c := Vector2(s.x * 0.5, s.y * 0.58)
	var hw := s.x * 0.48
	var hh := s.y * 0.38
	var shape := PackedVector2Array()
	for k in 64:
		var a := TAU * k / 64.0
		var x := cos(a)
		var y := sin(a)
		# Pontudo em cima e embaixo, arredondado dos lados
		var px := signf(x) * pow(absf(x), 0.75)
		var py := signf(y) * pow(absf(y), 1.6)
		shape.append(c + Vector2(px * hw, py * hh))
	ci.draw_colored_polygon(shape, Color(0.97, 0.97, 0.95))
	tube(ci, shape, GOLD, s.x * 0.008, true)
	for k in 64:
		ci.draw_circle(c.lerp(shape[k], 0.96), s.x * 0.008, Color(1.0, 0.85, 0.35))
	var red := Color(0.86, 0.1, 0.12)
	var blue := Color(0.12, 0.3, 0.75)
	var f := font("Bungee")
	if front:
		var word := "WELCOME"
		for k in word.length():
			var cc := Vector2(s.x * 0.5 + (k - 3) * s.x * 0.105, s.y * 0.38 - absf(k - 3) * -s.y * 0.012)
			ci.draw_circle(cc, s.x * 0.048, Color(0.85, 0.86, 0.9))
			tube(ci, circle(cc, s.x * 0.048), WHITE, s.x * 0.005, true)
			glow_text(ci, f, word[k], cc, int(s.x * 0.06), [red], 0.0, 0.01)
		glow_text(ci, font("Pacifico"), "to Fabulous", Vector2(s.x * 0.5, s.y * 0.5), int(s.x * 0.06), [blue], 0.0, 0.01)
		glow_text(ci, f, "LAS VEGAS", Vector2(s.x * 0.5, s.y * 0.62), fit(f, "LAS VEGAS", s.x * 0.72, s.y * 0.13), [red], 0.0, 0.01)
		glow_text(ci, f, "NEVADA", Vector2(s.x * 0.5, s.y * 0.75), int(s.x * 0.05), [blue], 0.0, 0.01)
	else:
		glow_text(ci, f, "DRIVE", Vector2(s.x * 0.5, s.y * 0.4), int(s.x * 0.08), [red], 0.0, 0.01)
		glow_text(ci, f, "CAREFULLY", Vector2(s.x * 0.5, s.y * 0.5), fit(f, "CAREFULLY", s.x * 0.66, s.y * 0.1), [red], 0.0, 0.01)
		glow_text(ci, font("Pacifico"), "Come Back", Vector2(s.x * 0.5, s.y * 0.63), int(s.x * 0.07), [blue], 0.0, 0.01)
		glow_text(ci, f, "SOON", Vector2(s.x * 0.5, s.y * 0.75), int(s.x * 0.06), [blue], 0.0, 0.01)
	# Estrela de oito pontas acima do painel
	var st := Vector2(s.x * 0.5, s.y * 0.12)
	fill(ci, star(st, s.x * 0.11, s.x * 0.045, 8, 0.0), Color(0.85, 0.1, 0.12), GOLD, s.x * 0.007)


## Caubói (ou vaqueira) de neon acenando: quadro 0 braço em cima, quadro 1 mais baixo; a vaqueira
## chuta a perna no quadro 1.
static func _cowboy(ci: CanvasItem, s: Vector2, frame: int, girl: bool) -> void:
	var u := s.x / 448.0
	var c := Vector2(s.x * 0.5, s.y * 0.42)
	var skin := Color(1.0, 0.75, 0.55)
	var hat := GOLD if not girl else PINK
	var shirt := RED if not girl else CYAN
	# Chapéu
	fill(ci, PackedVector2Array([c + Vector2(-120, -150) * u, c + Vector2(120, -150) * u, c + Vector2(90, -165) * u,
		c + Vector2(60, -230) * u, c + Vector2(-60, -230) * u, c + Vector2(-90, -165) * u]), Color(hat.darkened(0.4), 0.9), hat, 5 * u)
	# Rosto
	fill(ci, circle(c + Vector2(0, -105) * u, 48 * u), Color(skin, 0.95), ORANGE, 4 * u)
	ci.draw_circle(c + Vector2(-16, -115) * u, 5 * u, Color(0.1, 0.1, 0.1))
	ci.draw_circle(c + Vector2(16, -115) * u, 5 * u, Color(0.1, 0.1, 0.1))
	tube(ci, arc(c + Vector2(0, -98) * u, Vector2(20, 14) * u, 0.2, PI - 0.2, 10), RED, 3 * u)
	if girl:
		tube(ci, bez(c + Vector2(-46, -130) * u, c + Vector2(-80, -60) * u, c + Vector2(-50, -20) * u), GOLD, 8 * u)
		tube(ci, bez(c + Vector2(46, -130) * u, c + Vector2(80, -60) * u, c + Vector2(50, -20) * u), GOLD, 8 * u)
	# Tronco (camisa xadrez nas linhas)
	var torso := PackedVector2Array([c + Vector2(-60, -55) * u, c + Vector2(60, -55) * u, c + Vector2(50, 80) * u, c + Vector2(-50, 80) * u])
	fill(ci, torso, Color(shirt.darkened(0.45), 0.9), shirt, 5 * u)
	for k in 3:
		tube(ci, PackedVector2Array([c + Vector2(-52, -20 + k * 32) * u, c + Vector2(52, -20 + k * 32) * u]), WHITE, 2 * u)
	# Braço esquerdo na cintura; o direito acena
	tube(ci, PackedVector2Array([c + Vector2(-60, -45) * u, c + Vector2(-100, 10) * u, c + Vector2(-50, 40) * u]), shirt, 12 * u)
	var hand := c + (Vector2(150, -170) if frame == 0 else Vector2(170, -70)) * u
	tube(ci, PackedVector2Array([c + Vector2(60, -45) * u, c + Vector2(115, -60) * u + (Vector2(0, -40) if frame == 0 else Vector2(10, 10)) * u, hand]), shirt, 12 * u)
	fill(ci, circle(hand, 16 * u), Color(skin, 0.95), ORANGE, 3 * u)
	# Pernas e botas (a vaqueira chuta no quadro 1)
	var legs := [[Vector2(-30, 80), Vector2(-40, 230)], [Vector2(30, 80), Vector2(40, 230) if (frame == 0 or not girl) else Vector2(170, 120)]]
	for l: Array in legs:
		tube(ci, PackedVector2Array([c + (l[0] as Vector2) * u, c + (l[1] as Vector2) * u]), BLUE if not girl else WHITE, 16 * u)
		fill(ci, circle(c + (l[1] as Vector2) * u, 18 * u), Color(0.4, 0.2, 0.08, 0.95), ORANGE, 3 * u)
	glow_text(ci, font("Rye"), "YEEHAW!" if girl else "HOWDY!", Vector2(s.x * 0.5, s.y * 0.94), int(64 * u), [GOLD, RED], 0.5)


# ---------------------------------------------------------------------------
# Rolos de LED (4 quadros)
# ---------------------------------------------------------------------------
static func _reel(ci: CanvasItem, s: Vector2, reel: int, frame: int) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.02, 0.05))
	var k := (reel * 4 + frame) % 12
	var c := s * 0.5
	var f := font("Bungee")
	match k:
		0:
			glow_text(ci, f, "JACKPOT", c + Vector2(0, -s.y * 0.12), fit(f, "JACKPOT", s.x * 0.85, s.y * 0.42), [GOLD, ORANGE], 0.4)
			glow_text(ci, font("Righteous"), "$1,000,000", c + Vector2(0, s.y * 0.26), int(s.y * 0.2), [GREEN], 0.5)
		1:
			for i in 3:
				var dc := Vector2(s.x * (0.22 + i * 0.28), c.y)
				ci.draw_rect(Rect2(dc - Vector2(s.y * 0.32, s.y * 0.36), Vector2(s.y * 0.64, s.y * 0.72)), Color(0.95, 0.95, 0.92))
				glow_text(ci, f, "7", dc, int(s.y * 0.6), [RED], 0.2, 0.02)
		2:
			for i in 8:
				for j in 4:
					if (i + j) % 2 == 0:
						ci.draw_rect(Rect2(Vector2(i, j) * s.y * 0.07 + Vector2(s.x * 0.03, s.y * 0.36), Vector2.ONE * s.y * 0.07), WHITE)
			glow_text(ci, f, "SPEEDORU GP", Vector2(s.x * 0.66, c.y), fit(f, "SPEEDORU GP", s.x * 0.56, s.y * 0.3), [PINK, CYAN], 0.45)
		3:
			glow_text(ci, font("Pacifico"), "Tonight", c + Vector2(0, -s.y * 0.15), int(s.y * 0.34), [PINK], 0.5)
			glow_text(ci, f, "LIVE SHOW", c + Vector2(0, s.y * 0.25), int(s.y * 0.22), [CYAN], 0.5)
		4:
			_icon_in(ci, Rect2(Vector2(s.x * 0.04, 0), Vector2(s.y, s.y)), "cherries")
			glow_text(ci, f, "SLOTS", Vector2(s.x * 0.66, c.y), fit(f, "SLOTS", s.x * 0.55, s.y * 0.5), [RED, GOLD], 0.45)
		5:
			glow_text(ci, font("Monoton"), "WIN", c, int(s.y * 0.7), [GREEN], 0.35, 0.03)
		6:
			_icon_in(ci, Rect2(Vector2(s.x * 0.04, 0), Vector2(s.y, s.y)), "martini")
			glow_text(ci, font("Lobster"), "Happy Hour", Vector2(s.x * 0.64, c.y), int(s.y * 0.3), [CYAN], 0.5)
		7:
			glow_text(ci, font("Rye"), "BUFFET", c + Vector2(0, -s.y * 0.1), fit(font("Rye"), "BUFFET", s.x * 0.8, s.y * 0.42), [ORANGE], 0.5)
			glow_text(ci, f, "ALL YOU CAN EAT", c + Vector2(0, s.y * 0.3), int(s.y * 0.13), [WHITE], 0.5)
		8:
			var cell := PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)])
			for i in 6:
				var a := TAU * i / 6.0
				var ray := PackedVector2Array([c, c + Vector2(cos(a), sin(a)) * s.x, c + Vector2(cos(a + 0.5), sin(a + 0.5)) * s.x])
				for part in Geometry2D.intersect_polygons(ray, cell):
					ci.draw_colored_polygon(part, Color(COLORS[i], 0.6))
			glow_text(ci, f, "MEGA BONUS", c, fit(f, "MEGA BONUS", s.x * 0.85, s.y * 0.38), [WHITE], 0.6)
		9:
			_icon_in(ci, Rect2(Vector2(s.x * 0.04, 0), Vector2(s.y, s.y)), "dragon")
			glow_text(ci, f, "DRAGÃO", Vector2(s.x * 0.66, c.y), fit(f, "DRAGÃO", s.x * 0.55, s.y * 0.4), [GREEN, GOLD], 0.45)
		10:
			glow_text(ci, font("Righteous"), "GACHA x10", c, fit(font("Righteous"), "GACHA x10", s.x * 0.85, s.y * 0.5), [PURPLE, PINK], 0.5)
		11:
			_icon_in(ci, Rect2(Vector2(s.x * 0.04, 0), Vector2(s.y, s.y)), "cards")
			glow_text(ci, f, "POKER", Vector2(s.x * 0.66, c.y), fit(f, "POKER", s.x * 0.55, s.y * 0.5), [BLUE, CYAN], 0.45)
	# Grade de pixels do painel de LED
	var step := 6.0
	var x := 0.0
	while x < s.x:
		ci.draw_line(Vector2(x, 0), Vector2(x, s.y), Color(0, 0, 0, 0.35), 1.5)
		x += step
	var y := 0.0
	while y < s.y:
		ci.draw_line(Vector2(0, y), Vector2(s.x, y), Color(0, 0, 0, 0.35), 1.5)
		y += step


## Ícone desenhado dentro de `r` (coordenadas da célula atual).
static func _icon_in(ci: CanvasItem, r: Rect2, name: String) -> void:
	var origin: Vector2 = (ci as Painter).origin
	ci.draw_set_transform(origin + r.position, 0.0, Vector2.ONE * (r.size.x / 256.0))
	_icon(ci, Vector2(256, 256), name)
	ci.draw_set_transform(origin)
