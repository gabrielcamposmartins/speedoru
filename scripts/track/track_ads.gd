class_name TrackAds
extends RefCounted
## Atlas de anúncios (marcas fictícias) e placas da pista.
## Layout da textura (2048 x 1024):
##  * linhas 0..3: 16 anúncios de 512 x 128 (proporção 4:1);
##  * linhas 4..7 (y >= 512): quadrados de 128 x 128 (placas de frenagem, setas, PIT...).
## A textura é gerada por tools/bake_ad_atlas.gd e salva em ATLAS_PATH.

const ATLAS_PATH := "res://assets/track/ads/ad_atlas.png"
const ATLAS_SIZE := Vector2i(2048, 1024)
const AD_SIZE := Vector2i(512, 128)
const SQUARE := 128

## [texto, fundo, texto, faixa de destaque]
const BRANDS := [
	["F1 GATCHA", Color("e8256f"), Color("ffffff"), Color("ffd23f")],
	["SAKURA OIL", Color("fff4f8"), Color("e8467c"), Color("e8467c")],
	["NEKO ENERGY", Color("16161d"), Color("ffe14d"), Color("ffe14d")],
	["TURBO RAMEN", Color("ffd23f"), Color("d7263d"), Color("d7263d")],
	["KAZE TELECOM", Color("1f5fd6"), Color("ffffff"), Color("7fd1ff")],
	["HOSHI TYRES", Color("3d1f73"), Color("ffd23f"), Color("ffd23f")],
	["MOCHI COLA", Color("d7263d"), Color("ffffff"), Color("ffffff")],
	["RYU BANK", Color("114b3a"), Color("f2c14e"), Color("f2c14e")],
	["PIXEL AIR", Color("0c1a3d"), Color("4ce0ff"), Color("ff4fa3")],
	["KITSUNE WATCHES", Color("ffffff"), Color("f26b1d"), Color("16161d")],
	["ORBIT FUEL", Color("b8f14a"), Color("101010"), Color("101010")],
	["SORA AIRLINES", Color("f4fbff"), Color("2a8be8"), Color("2a8be8")],
	["GACHA x10", Color("7a2cf0"), Color("ffffff"), Color("ffcc00")],
	["YUZU SODA", Color("fffbe0"), Color("2f9e44"), Color("ffcc00")],
	["TANUKI LOGISTICS", Color("6b4226"), Color("ffffff"), Color("f2c14e")],
	["GRAN PREMIO", Color("ffffff"), Color("16161d"), Color("d7263d")],
]

enum Sign { BRAKE_100, BRAKE_150, BRAKE_200, BRAKE_50, PIT, SPEED_80, CHEVRON_RIGHT, CHEVRON_LEFT, STOP }
const SIGN_TEXT := ["100", "150", "200", "50", "PIT", "80", ">", "<", "STOP"]


static func ad_count() -> int:
	return BRANDS.size()


## Retângulo UV (0..1) do anúncio i.
static func ad_uv(i: int) -> Rect2:
	i = posmod(i, BRANDS.size())
	var px := Vector2((i % 4) * AD_SIZE.x, (i / 4) * AD_SIZE.y)
	return Rect2(px / Vector2(ATLAS_SIZE), Vector2(AD_SIZE) / Vector2(ATLAS_SIZE))


## Retângulo UV de uma placa quadrada.
static func sign_uv(i: int) -> Rect2:
	var px := Vector2((i % 16) * SQUARE, 512 + (i / 16) * SQUARE)
	return Rect2(px / Vector2(ATLAS_SIZE), Vector2(SQUARE, SQUARE) / Vector2(ATLAS_SIZE))


static func load_atlas() -> Texture2D:
	if ResourceLoader.exists(ATLAS_PATH):
		return load(ATLAS_PATH) as Texture2D
	push_warning("TrackAds: atlas %s não encontrado (rode tools/bake_ad_atlas.gd)." % ATLAS_PATH)
	return null


## Desenha o atlas inteiro num CanvasItem (usado pelo baker).
static func draw_atlas(ci: CanvasItem, font: Font) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, ATLAS_SIZE), Color(0.5, 0.5, 0.5))
	for i in BRANDS.size():
		var b: Array = BRANDS[i]
		var r := Rect2(Vector2((i % 4) * AD_SIZE.x, (i / 4) * AD_SIZE.y), AD_SIZE)
		ci.draw_rect(r, b[1])
		# Faixas diagonais de destaque nas pontas
		for k in 3:
			var x0 := r.position.x + 14 + k * 22
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(x0, r.end.y), Vector2(x0 + 12, r.end.y), Vector2(x0 + 44, r.position.y), Vector2(x0 + 32, r.position.y)]), b[3])
			var x1 := r.end.x - 14 - k * 22
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(x1, r.position.y), Vector2(x1 - 12, r.position.y), Vector2(x1 - 44, r.end.y), Vector2(x1 - 32, r.end.y)]), b[3])
		ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 10), Vector2(r.size.x, 10)), b[3])
		_draw_text_fit(ci, font, b[0], Rect2(r.position + Vector2(96, 10), r.size - Vector2(192, 30)), b[2])
	for i in SIGN_TEXT.size():
		var r := Rect2(Vector2((i % 16) * SQUARE, 512 + (i / 16) * SQUARE), Vector2(SQUARE, SQUARE))
		var bg := Color("f4f4f4")
		var fg := Color("16161d")
		if i == Sign.PIT or i == Sign.STOP:
			bg = Color("1f5fd6")
			fg = Color.WHITE
		elif i == Sign.SPEED_80:
			bg = Color.WHITE
		elif i == Sign.CHEVRON_LEFT or i == Sign.CHEVRON_RIGHT:
			bg = Color("d7263d")
			fg = Color.WHITE
		ci.draw_rect(r, bg)
		ci.draw_rect(r.grow(-4), fg, false, 4.0)
		if i == Sign.SPEED_80:
			ci.draw_circle(r.get_center(), 56, Color("d7263d"))
			ci.draw_circle(r.get_center(), 44, Color.WHITE)
		if i == Sign.CHEVRON_LEFT or i == Sign.CHEVRON_RIGHT:
			var dir := 1.0 if i == Sign.CHEVRON_RIGHT else -1.0
			var c := r.get_center()
			for k in 2:
				var off := (k - 0.5) * 34.0 * dir
				ci.draw_colored_polygon(PackedVector2Array([
					c + Vector2(off - 18 * dir, -40), c + Vector2(off + 2 * dir, -40),
					c + Vector2(off + 26 * dir, 0), c + Vector2(off + 2 * dir, 40),
					c + Vector2(off - 18 * dir, 40), c + Vector2(off + 6 * dir, 0)]), fg)
		else:
			_draw_text_fit(ci, font, SIGN_TEXT[i], r.grow(-20), fg)


static func _draw_text_fit(ci: CanvasItem, font: Font, text: String, r: Rect2, color: Color) -> void:
	var size := 120
	while size > 8:
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		if ts.x <= r.size.x and font.get_height(size) * 0.8 <= r.size.y:
			break
		size -= 2
	var ts2 := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var baseline := r.position.y + (r.size.y + font.get_ascent(size) * 0.72) * 0.5
	ci.draw_string(font, Vector2(r.position.x + (r.size.x - ts2.x) * 0.5, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
