class_name ShopCatalog
extends RefCounted
## Catálogo da economia (mesmo modelo de negócio do Pokeru, sem dinheiro real):
##
## * Moeda única: créditos, ganhos correndo (conta nova começa com 10.000).
## * Ticket = um giro numa roleta (2.500 créditos). Sem estoque, sem pacote, sem giro de 10, sem
##   desconto: cada giro é uma cobrança. Duas roletas temáticas, cada peça mora numa só.
## * Cada giro sorteia um DEGRAU de raridade com fatia fixa (RARITIES) e, dentro dele, uma peça
##   com chance igual. Sem pity, sem garantia: cada giro é independente.
## * Repetida vira créditos: 30% do preço de tabela (DUP_FRACTION). O giro nunca sai vazio.
## * O que vem com a conta (FREE) fica fora do sorteio. As paletas da interface vêm todas com o
##   jogo (só se troca, em Configurações).
## * A loja vende só tickets. Nenhum cosmético se compra diretamente.
## A Galeria e a Loja mostram as chances lidas daqui, as mesmas que o sorteio usa.

const CURRENCY := "créditos"
const START_CREDITS := 10000
const TICKET_PRICE := 2500
const DUP_FRACTION := 0.3

## Recompensa por volta completada, por dificuldade dos bots (fácil, médio, difícil, mista):
## 10 voltas = 200 / 300 / 400.
const REWARD_PER_LAP := [20, 30, 40, 30]

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
const RARITY_NAMES := ["Comum", "Incomum", "Raro", "Épico", "Lendário"]
## Fatia fixa de cada degrau (soma 100%).
const RARITY_WEIGHTS := [55.5, 26.0, 10.0, 6.0, 2.5]
const RARITY_COLORS := [Color("9aa4b2"), Color("3dfc9a"), Color("2f9bff"), Color("b14dff"), Color("ffb000")]
## Preço de tabela (base) por degrau; a devolução de repetida é 30% disso × multiplicador do tipo.
const RARITY_PRICE := [2000, 3000, 4500, 7000, 12000]

## Tipos colecionáveis (ordem da Galeria): [id, nome, multiplicador de preço].
const TYPES := [
	["livery", "Pinturas", 1.25],
	["helmet", "Capacetes", 1.0],
	["suit", "Macacões", 1.0],
	["rim", "Cor das rodas", 1.0],
	["boost", "Brilho do boost", 1.0],
	["neon", "Neon", 1.1],
	["part", "Peças", 1.2],
]

const ROULETTES := {
	"neon": {"name": "Roleta Neon", "theme": "luz, céu, gelo, neon, sakura", "color": Color("05d9e8")},
	"inferno": {"name": "Roleta Inferno", "theme": "fogo, sombra, noite, metal, bordô", "color": Color("ff4d2d")},
}

## Itens que vêm com a conta (fora do sorteio).
const FREE := {
	"livery_akane": {"type": "livery", "name": "Akane Racing", "colors": ["d81e2c", "f1f2f6", "12a4e8"]},
	"helmet_akane": {"type": "helmet", "name": "Amarelo Akane", "color": "ffd21f"},
	"suit_akane": {"type": "suit", "name": "Vermelho Akane", "color": "d81e2c"},
	"rim_akane": {"type": "rim", "name": "Grafite escuro", "color": "1b1c22"},
	"boost_akane": {"type": "boost", "name": "Ciano", "color": "38f2ff"},
}

## Itens das roletas: id -> {type, name, rarity, roulette, (colors | color | slot+variant)}.
## Peças de desempenho trocam uma coisa por outra (nunca são melhores em tudo).
const ITEMS := {
	# --- Roleta Neon -------------------------------------------------------------
	"livery_aurora": {"type": "livery", "name": "Aurora Boreal", "rarity": 4, "roulette": "neon", "colors": ["00e5c0", "1a1446", "ff3dd8"]},
	"livery_yume": {"type": "livery", "name": "Yume Sakura", "rarity": 4, "roulette": "neon", "colors": ["ffb7d5", "ffffff", "ff4f9a"]},
	"boost_hyperlight": {"type": "boost", "name": "Hiperluz", "rarity": 4, "roulette": "neon", "color": "f0f8ff"},
	"neon_aurora": {"type": "neon", "name": "Aurora", "rarity": 4, "roulette": "neon", "color": "3dffb5"},
	"livery_glacial": {"type": "livery", "name": "Glacial", "rarity": 3, "roulette": "neon", "colors": ["bfe9ff", "0b2a4a", "5ff3ff"]},
	"livery_tokyo": {"type": "livery", "name": "Céu de Tóquio", "rarity": 3, "roulette": "neon", "colors": ["2f7bff", "f5f7ff", "ff2a6d"]},
	"helmet_crystal": {"type": "helmet", "name": "Cristal", "rarity": 3, "roulette": "neon", "color": "9ff0ff"},
	"helmet_cherry": {"type": "helmet", "name": "Flor de cerejeira", "rarity": 3, "roulette": "neon", "color": "ffc1e3"},
	"suit_night_sky": {"type": "suit", "name": "Céu noturno", "rarity": 3, "roulette": "neon", "color": "1d2b64"},
	"rim_silver": {"type": "rim", "name": "Prata polida", "rarity": 3, "roulette": "neon", "color": "c9d2e0"},
	"part_front_wing_lowdf": {"type": "part", "name": "Asa dianteira de baixa carga", "rarity": 3, "roulette": "neon", "slot": "front_wing", "variant": "lowdf"},
	"part_nose_pointed": {"type": "part", "name": "Bico pontudo", "rarity": 3, "roulette": "neon", "slot": "nose", "variant": "pointed"},
	"livery_jade": {"type": "livery", "name": "Jade", "rarity": 2, "roulette": "neon", "colors": ["00a86b", "f2fff8", "0b3d2e"]},
	"livery_daylight": {"type": "livery", "name": "Luz do dia", "rarity": 2, "roulette": "neon", "colors": ["fff4c2", "2b2b2b", "ffb000"]},
	"boost_ice": {"type": "boost", "name": "Gelo", "rarity": 2, "roulette": "neon", "color": "7df9ff"},
	"neon_cyan": {"type": "neon", "name": "Ciano", "rarity": 2, "roulette": "neon", "color": "00e5ff"},
	"rim_pearl": {"type": "rim", "name": "Branco perolado", "rarity": 2, "roulette": "neon", "color": "f4f1ea"},
	"part_sidepods_slim": {"type": "part", "name": "Sidepods Zeropod", "rarity": 2, "roulette": "neon", "slot": "sidepods", "variant": "slim"},
	"livery_lavender": {"type": "livery", "name": "Lavanda", "rarity": 1, "roulette": "neon", "colors": ["b9a3ff", "2a1f4f", "ffffff"]},
	"livery_mint": {"type": "livery", "name": "Menta", "rarity": 1, "roulette": "neon", "colors": ["98ffcf", "1b3b33", "0bd9a6"]},
	"livery_pool": {"type": "livery", "name": "Azul piscina", "rarity": 1, "roulette": "neon", "colors": ["1ec8ff", "ffffff", "0a3d62"]},
	"helmet_sky": {"type": "helmet", "name": "Céu", "rarity": 1, "roulette": "neon", "color": "6ec6ff"},
	"helmet_lilac": {"type": "helmet", "name": "Lilás", "rarity": 1, "roulette": "neon", "color": "c8a2ff"},
	"suit_ice": {"type": "suit", "name": "Gelo", "rarity": 1, "roulette": "neon", "color": "dff6ff"},
	"suit_pink": {"type": "suit", "name": "Rosa", "rarity": 1, "roulette": "neon", "color": "ff8fc7"},
	"rim_electric": {"type": "rim", "name": "Azul elétrico", "rarity": 1, "roulette": "neon", "color": "1f6bff"},
	"rim_pink": {"type": "rim", "name": "Rosa", "rarity": 1, "roulette": "neon", "color": "ff6fb5"},
	"boost_hot_pink": {"type": "boost", "name": "Rosa choque", "rarity": 1, "roulette": "neon", "color": "ff3d9a"},
	"livery_ice_white": {"type": "livery", "name": "Branco gelo", "rarity": 0, "roulette": "neon", "colors": ["f4f8ff", "9fb3c8", "2f7bff"]},
	"livery_classic_blue": {"type": "livery", "name": "Azul clássico", "rarity": 0, "roulette": "neon", "colors": ["1e4fd8", "ffffff", "ffd21f"]},
	"livery_clear_sky": {"type": "livery", "name": "Céu limpo", "rarity": 0, "roulette": "neon", "colors": ["8fd3ff", "1b2a41", "ffffff"]},
	"helmet_white": {"type": "helmet", "name": "Branco", "rarity": 0, "roulette": "neon", "color": "f5f5f5"},
	"helmet_blue": {"type": "helmet", "name": "Azul", "rarity": 0, "roulette": "neon", "color": "2f6bff"},
	"suit_navy": {"type": "suit", "name": "Azul-marinho", "rarity": 0, "roulette": "neon", "color": "1b2a6b"},
	"suit_white": {"type": "suit", "name": "Branco", "rarity": 0, "roulette": "neon", "color": "f2f2f2"},
	"rim_graphite": {"type": "rim", "name": "Grafite", "rarity": 0, "roulette": "neon", "color": "3a3d46"},
	# --- Roleta Inferno ----------------------------------------------------------
	"livery_crimson_dragon": {"type": "livery", "name": "Dragão Carmesim", "rarity": 4, "roulette": "inferno", "colors": ["8b0000", "111111", "ffb000"]},
	"livery_eclipse": {"type": "livery", "name": "Eclipse", "rarity": 4, "roulette": "inferno", "colors": ["0b0b10", "3a0ca3", "ff2d55"]},
	"boost_solar_flame": {"type": "boost", "name": "Chama solar", "rarity": 4, "roulette": "inferno", "color": "ff6a00"},
	"neon_lava": {"type": "neon", "name": "Lava", "rarity": 4, "roulette": "inferno", "color": "ff3300"},
	"livery_ember": {"type": "livery", "name": "Brasa", "rarity": 3, "roulette": "inferno", "colors": ["ff4500", "1a1a1a", "ffd166"]},
	"livery_midnight": {"type": "livery", "name": "Meia-noite", "rarity": 3, "roulette": "inferno", "colors": ["0d1b2a", "e0e1dd", "c1121f"]},
	"helmet_gold": {"type": "helmet", "name": "Ouro", "rarity": 3, "roulette": "inferno", "color": "d4af37"},
	"helmet_obsidian": {"type": "helmet", "name": "Obsidiana", "rarity": 3, "roulette": "inferno", "color": "1a1a1f"},
	"suit_burgundy": {"type": "suit", "name": "Bordô", "rarity": 3, "roulette": "inferno", "color": "6d0f1f"},
	"rim_gold": {"type": "rim", "name": "Ouro", "rarity": 3, "roulette": "inferno", "color": "c9a227"},
	"part_rear_wing_lowdf": {"type": "part", "name": "Asa traseira de baixa carga", "rarity": 3, "roulette": "inferno", "slot": "rear_wing", "variant": "lowdf"},
	"part_rear_wing_highdf": {"type": "part", "name": "Asa traseira de alta carga", "rarity": 3, "roulette": "inferno", "slot": "rear_wing", "variant": "highdf"},
	"livery_bordeaux": {"type": "livery", "name": "Bordô", "rarity": 2, "roulette": "inferno", "colors": ["7a1023", "f3e9dc", "d4af37"]},
	"livery_titanium": {"type": "livery", "name": "Titânio", "rarity": 2, "roulette": "inferno", "colors": ["8a8f98", "1c1c1c", "ff5a1f"]},
	"boost_ruby": {"type": "boost", "name": "Rubi", "rarity": 2, "roulette": "inferno", "color": "ff1744"},
	"neon_amber": {"type": "neon", "name": "Âmbar", "rarity": 2, "roulette": "inferno", "color": "ffb000"},
	"rim_copper": {"type": "rim", "name": "Cobre", "rarity": 2, "roulette": "inferno", "color": "b87333"},
	"part_engine_cover_sharkfin": {"type": "part", "name": "Cobertura com barbatana", "rarity": 2, "roulette": "inferno", "slot": "engine_cover", "variant": "sharkfin"},
	"livery_graphite": {"type": "livery", "name": "Grafite", "rarity": 1, "roulette": "inferno", "colors": ["2b2d33", "ff3b30", "f2f2f2"]},
	"livery_volcano": {"type": "livery", "name": "Laranja vulcão", "rarity": 1, "roulette": "inferno", "colors": ["ff7a00", "202020", "ffffff"]},
	"livery_wine": {"type": "livery", "name": "Vinho", "rarity": 1, "roulette": "inferno", "colors": ["5a0f2e", "f2d0a4", "ff6b6b"]},
	"helmet_orange": {"type": "helmet", "name": "Laranja", "rarity": 1, "roulette": "inferno", "color": "ff8c1a"},
	"helmet_red": {"type": "helmet", "name": "Vermelho", "rarity": 1, "roulette": "inferno", "color": "e01e37"},
	"suit_black": {"type": "suit", "name": "Preto", "rarity": 1, "roulette": "inferno", "color": "161616"},
	"suit_orange": {"type": "suit", "name": "Laranja", "rarity": 1, "roulette": "inferno", "color": "ff7a1a"},
	"rim_red": {"type": "rim", "name": "Vermelho", "rarity": 1, "roulette": "inferno", "color": "c1121f"},
	"rim_bronze": {"type": "rim", "name": "Bronze", "rarity": 1, "roulette": "inferno", "color": "8c6239"},
	"part_rim_spoked": {"type": "part", "name": "Rodas raiadas", "rarity": 1, "roulette": "inferno", "slot": "rim", "variant": "spoked"},
	"livery_classic_red": {"type": "livery", "name": "Vermelho clássico", "rarity": 0, "roulette": "inferno", "colors": ["c8102e", "ffffff", "1a1a1a"]},
	"livery_matte_black": {"type": "livery", "name": "Preto fosco", "rarity": 0, "roulette": "inferno", "colors": ["1c1c1c", "8a8a8a", "e10600"]},
	"livery_steel": {"type": "livery", "name": "Cinza aço", "rarity": 0, "roulette": "inferno", "colors": ["6b7280", "111827", "f97316"]},
	"helmet_black": {"type": "helmet", "name": "Preto", "rarity": 0, "roulette": "inferno", "color": "101010"},
	"helmet_crimson": {"type": "helmet", "name": "Carmim", "rarity": 0, "roulette": "inferno", "color": "c8102e"},
	"suit_grey": {"type": "suit", "name": "Cinza", "rarity": 0, "roulette": "inferno", "color": "5b5f66"},
	"suit_red": {"type": "suit", "name": "Vermelho", "rarity": 0, "roulette": "inferno", "color": "b5121b"},
	"rim_black": {"type": "rim", "name": "Preto", "rarity": 0, "roulette": "inferno", "color": "0e0e10"},
}


# ---------------------------------------------------------------------------
static func item(id: String) -> Dictionary:
	if ITEMS.has(id):
		return ITEMS[id]
	return FREE.get(id, {})


static func is_free(id: String) -> bool:
	return FREE.has(id)


static func type_info(type: String) -> Array:
	for t in TYPES:
		if t[0] == type:
			return t
	return ["", type, 1.0]


## Preço de tabela de uma peça (base da devolução de repetidas).
static func table_price(id: String) -> int:
	var it := item(id)
	if it.is_empty() or is_free(id):
		return 0
	return int(round(RARITY_PRICE[it["rarity"]] * float(type_info(it["type"])[2]) / 50.0) * 50)


static func refund_of(id: String) -> int:
	return int(round(table_price(id) * DUP_FRACTION))


## Peças de uma roleta num degrau.
static func drops(roulette: String, rarity: int) -> Array[String]:
	var out: Array[String] = []
	for id in ITEMS:
		if ITEMS[id]["roulette"] == roulette and ITEMS[id]["rarity"] == rarity:
			out.append(id)
	return out


## Chance exata (0–1) de uma peça sair num giro da roleta dela.
static func chance_of(id: String) -> float:
	var it := item(id)
	if it.is_empty() or is_free(id):
		return 0.0
	var n := drops(it["roulette"], it["rarity"]).size()
	return RARITY_WEIGHTS[it["rarity"]] / 100.0 / maxf(n, 1)


## Sorteio: um degrau pela fatia fixa e, dentro dele, uma peça com chance igual. [param roll]
## é um número uniforme em [0, 1) (o Profile usa um gerador criptográfico).
static func draw(roulette: String, roll: float) -> String:
	var total := 0.0
	for w in RARITY_WEIGHTS:
		total += w
	var x := roll * total
	var rarity := RARITY_WEIGHTS.size() - 1
	var acc := 0.0
	for k in RARITY_WEIGHTS.size():
		acc += RARITY_WEIGHTS[k]
		if x < acc:
			rarity = k
			break
	var pool := drops(roulette, rarity)
	# Posição dentro do degrau: a parte fracionária do mesmo número (uniforme dentro da fatia)
	var within: float = (x - (acc - RARITY_WEIGHTS[rarity])) / RARITY_WEIGHTS[rarity]
	return pool[mini(int(within * pool.size()), pool.size() - 1)]


## Todas as peças de um tipo (gratuitas primeiro, depois das roletas por raridade decrescente).
static func items_of_type(type: String) -> Array[String]:
	var out: Array[String] = []
	for id in FREE:
		if FREE[id]["type"] == type:
			out.append(id)
	var rest: Array[String] = []
	for id in ITEMS:
		if ITEMS[id]["type"] == type:
			rest.append(id)
	rest.sort_custom(func(a: String, b: String) -> bool:
		return ITEMS[a]["rarity"] > ITEMS[b]["rarity"] if ITEMS[a]["rarity"] != ITEMS[b]["rarity"] else ITEMS[a]["name"] < ITEMS[b]["name"])
	out.append_array(rest)
	return out


## Cores de uma peça (pinturas têm 3; capacete/macacão/roda/boost/neon têm 1).
static func colors_of(id: String) -> Array[Color]:
	var it := item(id)
	var out: Array[Color] = []
	if it.has("colors"):
		for c in it["colors"]:
			out.append(Color(c))
	elif it.has("color"):
		out.append(Color(it["color"]))
	return out


static func roulette_items(roulette: String) -> Array[String]:
	var out: Array[String] = []
	for rarity in range(RARITY_WEIGHTS.size() - 1, -1, -1):
		out.append_array(drops(roulette, rarity))
	return out
