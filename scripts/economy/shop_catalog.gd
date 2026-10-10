class_name ShopCatalog
extends RefCounted
## Catálogo da economia (mesmo modelo de negócio do Pokeru, sem dinheiro real):
##
## * Moeda única: créditos, ganhos correndo (conta nova começa com 10.000).
## * Ticket = um giro numa roleta (2.500 créditos). Sem estoque, sem pacote, sem giro de 10, sem
##   desconto: cada giro é uma cobrança. Duas roletas temáticas, cada peça mora numa só.
## * As roletas sorteiam PEÇAS de desempenho, DECALQUES e as cores de luz: BRILHO DO BOOST e NEON.
##   As outras cores (carro, capacete, macacão, rodas) são livres no Estúdio; as pinturas prontas
##   (PAINTS) são atalhos grátis.
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
## 10 voltas = 2.000 / 3.000 / 4.000.
const REWARD_PER_LAP := [200, 300, 400, 300]

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
const RARITY_NAMES := ["Comum", "Incomum", "Raro", "Épico", "Lendário"]
## Fatia fixa de cada degrau (soma 100%).
const RARITY_WEIGHTS := [55.5, 26.0, 10.0, 6.0, 2.5]
const RARITY_COLORS := [Color("9aa4b2"), Color("3dfc9a"), Color("2f9bff"), Color("b14dff"), Color("ffb000")]
## Preço de tabela (base) por degrau; a devolução de repetida é 30% disso × multiplicador do tipo.
const RARITY_PRICE := [2000, 3000, 4500, 7000, 12000]

## Tipos colecionáveis (ordem da Galeria): [id, nome, multiplicador de preço].
const TYPES := [
	["part", "Peças", 1.2],
	["decal", "Decalques", 1.0],
	["boost", "Brilho do boost", 1.0],
	["neon", "Neon", 1.1],
]
## Campos de cor que só aceitam cores ganhas (itens desses tipos); os outros são livres.
const GACHA_COLORS := ["boost", "neon"]

const ROULETTES := {
	"neon": {"name": "Roleta Neon", "theme": "luz fria, sakura, cometa e peças leves", "color": Color("05d9e8")},
	"inferno": {"name": "Roleta Inferno", "theme": "fogo, chamas, garras, asas traseiras e rodas", "color": Color("ff4d2d")},
}

## Pinturas prontas (grátis): combinações de três cores aplicadas de uma vez. As cores do carro são
## livres; as pinturas são só atalhos.
const PAINTS := {
	"livery_akane": {"name": "Akane Racing", "colors": ["d81e2c", "f1f2f6", "12a4e8"]},
	"livery_aurora": {"name": "Aurora Boreal", "colors": ["00e5c0", "1a1446", "ff3dd8"]},
	"livery_yume": {"name": "Yume Sakura", "colors": ["ffb7d5", "ffffff", "ff4f9a"]},
	"livery_glacial": {"name": "Glacial", "colors": ["bfe9ff", "0b2a4a", "5ff3ff"]},
	"livery_tokyo": {"name": "Céu de Tóquio", "colors": ["2f7bff", "f5f7ff", "ff2a6d"]},
	"livery_jade": {"name": "Jade", "colors": ["00a86b", "f2fff8", "0b3d2e"]},
	"livery_daylight": {"name": "Luz do dia", "colors": ["fff4c2", "2b2b2b", "ffb000"]},
	"livery_lavender": {"name": "Lavanda", "colors": ["b9a3ff", "2a1f4f", "ffffff"]},
	"livery_mint": {"name": "Menta", "colors": ["98ffcf", "1b3b33", "0bd9a6"]},
	"livery_pool": {"name": "Azul piscina", "colors": ["1ec8ff", "ffffff", "0a3d62"]},
	"livery_ice_white": {"name": "Branco gelo", "colors": ["f4f8ff", "9fb3c8", "2f7bff"]},
	"livery_classic_blue": {"name": "Azul clássico", "colors": ["1e4fd8", "ffffff", "ffd21f"]},
	"livery_clear_sky": {"name": "Céu limpo", "colors": ["8fd3ff", "1b2a41", "ffffff"]},
	"livery_crimson_dragon": {"name": "Dragão Carmesim", "colors": ["8b0000", "111111", "ffb000"]},
	"livery_eclipse": {"name": "Eclipse", "colors": ["0b0b10", "3a0ca3", "ff2d55"]},
	"livery_ember": {"name": "Brasa", "colors": ["ff4500", "1a1a1a", "ffd166"]},
	"livery_midnight": {"name": "Meia-noite", "colors": ["0d1b2a", "e0e1dd", "c1121f"]},
	"livery_bordeaux": {"name": "Bordô", "colors": ["7a1023", "f3e9dc", "d4af37"]},
	"livery_titanium": {"name": "Titânio", "colors": ["8a8f98", "1c1c1c", "ff5a1f"]},
	"livery_graphite": {"name": "Grafite", "colors": ["2b2d33", "ff3b30", "f2f2f2"]},
	"livery_volcano": {"name": "Laranja vulcão", "colors": ["ff7a00", "202020", "ffffff"]},
	"livery_wine": {"name": "Vinho", "colors": ["5a0f2e", "f2d0a4", "ff6b6b"]},
	"livery_classic_red": {"name": "Vermelho clássico", "colors": ["c8102e", "ffffff", "1a1a1a"]},
	"livery_matte_black": {"name": "Preto fosco", "colors": ["1c1c1c", "8a8a8a", "e10600"]},
	"livery_steel": {"name": "Cinza aço", "colors": ["6b7280", "111827", "f97316"]},
}
const DEFAULT_PAINT := "livery_akane"

## Sugestões de cor por campo (nome, cor) — o seletor do Estúdio aceita qualquer cor (boost e neon
## não: só as cores ganhas).
const COLOR_SUGGESTIONS := {
	"helmet": [["Amarelo Akane", "ffd21f"], ["Cristal", "9ff0ff"], ["Flor de cerejeira", "ffc1e3"], ["Céu", "6ec6ff"], ["Lilás", "c8a2ff"], ["Branco", "f5f5f5"], ["Azul", "2f6bff"], ["Ouro", "d4af37"], ["Obsidiana", "1a1a1f"], ["Laranja", "ff8c1a"], ["Vermelho", "e01e37"], ["Preto", "101010"], ["Carmim", "c8102e"]],
	"suit": [["Vermelho Akane", "d81e2c"], ["Céu noturno", "1d2b64"], ["Gelo", "dff6ff"], ["Rosa", "ff8fc7"], ["Azul-marinho", "1b2a6b"], ["Branco", "f2f2f2"], ["Bordô", "6d0f1f"], ["Preto", "161616"], ["Laranja", "ff7a1a"], ["Cinza", "5b5f66"], ["Vermelho", "b5121b"]],
	"rim": [["Grafite escuro", "1b1c22"], ["Prata polida", "c9d2e0"], ["Branco perolado", "f4f1ea"], ["Azul elétrico", "1f6bff"], ["Rosa", "ff6fb5"], ["Grafite", "3a3d46"], ["Ouro", "c9a227"], ["Cobre", "b87333"], ["Vermelho", "c1121f"], ["Bronze", "8c6239"], ["Preto", "0e0e10"]],
}
## Cor padrão de cada campo (conta nova). Neon: nenhum (desligado até ganhar um).
const DEFAULT_COLORS := {"helmet": "ffd21f", "suit": "d81e2c", "rim": "1b1c22", "boost": "38f2ff", "neon": ""}

## Itens que vêm com a conta (fora do sorteio): os decalques básicos e o boost ciano.
const FREE := {
	"boost_akane": {"type": "boost", "name": "Ciano", "color": "38f2ff"},
	"decal_estrela": {"type": "decal", "name": "Estrela", "decal": "estrela"},
	"decal_alvo": {"type": "decal", "name": "Disco de número", "decal": "alvo"},
}

## Itens das roletas: id -> {type, name, rarity, roulette, (slot+variant | decal | color)}.
## Peças de desempenho trocam uma coisa por outra (nunca são melhores em tudo).
const ITEMS := {
	# --- Roleta Neon -------------------------------------------------------------
	"part_front_wing_lowdf": {"type": "part", "name": "Asa dianteira de baixa carga", "rarity": 3, "roulette": "neon", "slot": "front_wing", "variant": "lowdf"},
	"part_nose_pointed": {"type": "part", "name": "Bico pontudo", "rarity": 3, "roulette": "neon", "slot": "nose", "variant": "pointed"},
	"part_sidepods_slim": {"type": "part", "name": "Sidepods Zeropod", "rarity": 2, "roulette": "neon", "slot": "sidepods", "variant": "slim"},
	"decal_sakura": {"type": "decal", "name": "Sakura", "rarity": 4, "roulette": "neon", "decal": "sakura"},
	"decal_asas": {"type": "decal", "name": "Asas", "rarity": 3, "roulette": "neon", "decal": "asas"},
	"decal_cometa": {"type": "decal", "name": "Cometa", "rarity": 2, "roulette": "neon", "decal": "cometa"},
	"decal_coracao": {"type": "decal", "name": "Coração", "rarity": 1, "roulette": "neon", "decal": "coracao"},
	"decal_onda": {"type": "decal", "name": "Onda", "rarity": 1, "roulette": "neon", "decal": "onda"},
	"decal_listras": {"type": "decal", "name": "Listras de velocidade", "rarity": 0, "roulette": "neon", "decal": "listras"},
	"decal_raio": {"type": "decal", "name": "Raio", "rarity": 0, "roulette": "neon", "decal": "raio"},
	"boost_hyperlight": {"type": "boost", "name": "Hiperluz", "rarity": 4, "roulette": "neon", "color": "f0f8ff"},
	"neon_aurora": {"type": "neon", "name": "Aurora", "rarity": 4, "roulette": "neon", "color": "3dffb5"},
	"boost_ice": {"type": "boost", "name": "Gelo", "rarity": 2, "roulette": "neon", "color": "7df9ff"},
	"neon_cyan": {"type": "neon", "name": "Ciano", "rarity": 2, "roulette": "neon", "color": "00e5ff"},
	"boost_hot_pink": {"type": "boost", "name": "Rosa choque", "rarity": 1, "roulette": "neon", "color": "ff3d9a"},
	"neon_sakura": {"type": "neon", "name": "Sakura", "rarity": 1, "roulette": "neon", "color": "ff3dd8"},
	"boost_violet": {"type": "boost", "name": "Violeta", "rarity": 0, "roulette": "neon", "color": "b14dff"},
	"part_sidepods_jet": {"type": "part", "name": "Sidepods Turbina", "rarity": 4, "roulette": "neon", "slot": "sidepods", "variant": "jet"},
	"part_front_wing_gull": {"type": "part", "name": "Asa dianteira Gaivota", "rarity": 3, "roulette": "neon", "slot": "front_wing", "variant": "gull"},
	"part_rim_turbine": {"type": "part", "name": "Rodas Turbina", "rarity": 2, "roulette": "neon", "slot": "rim", "variant": "turbine"},
	"part_halo_winged": {"type": "part", "name": "Halo com aletas", "rarity": 2, "roulette": "neon", "slot": "halo", "variant": "winged"},
	"part_nose_duckbill": {"type": "part", "name": "Bico de pato", "rarity": 1, "roulette": "neon", "slot": "nose", "variant": "duckbill"},
	"part_engine_cover_twing": {"type": "part", "name": "Cobertura com asa em T", "rarity": 1, "roulette": "neon", "slot": "engine_cover", "variant": "twing"},
	"part_mirrors_bullet": {"type": "part", "name": "Retrovisores Bala", "rarity": 0, "roulette": "neon", "slot": "mirrors", "variant": "bullet"},
	"part_rear_wing_butterfly": {"type": "part", "name": "Asa traseira Borboleta", "rarity": 4, "roulette": "neon", "slot": "rear_wing", "variant": "butterfly"},
	"part_front_wing_ring": {"type": "part", "name": "Asa dianteira Anel", "rarity": 3, "roulette": "neon", "slot": "front_wing", "variant": "ring"},
	"part_rear_wing_omega": {"type": "part", "name": "Asa traseira Ômega", "rarity": 3, "roulette": "neon", "slot": "rear_wing", "variant": "omega"},
	"part_nose_hammer": {"type": "part", "name": "Bico Tubarão-martelo", "rarity": 2, "roulette": "neon", "slot": "nose", "variant": "hammer"},
	"part_front_wing_delta": {"type": "part", "name": "Asa dianteira Delta", "rarity": 2, "roulette": "neon", "slot": "front_wing", "variant": "delta"},
	"part_sidepods_periscope": {"type": "part", "name": "Sidepods Periscópio", "rarity": 2, "roulette": "neon", "slot": "sidepods", "variant": "periscope"},
	"part_engine_cover_twin_airbox": {"type": "part", "name": "Cobertura com entrada dupla", "rarity": 2, "roulette": "neon", "slot": "engine_cover", "variant": "twin_airbox"},
	"part_nose_drill": {"type": "part", "name": "Bico Broca", "rarity": 1, "roulette": "neon", "slot": "nose", "variant": "drill"},
	"part_sidepods_vents": {"type": "part", "name": "Sidepods Persianas", "rarity": 1, "roulette": "neon", "slot": "sidepods", "variant": "vents"},
	"part_engine_cover_exhaust": {"type": "part", "name": "Cobertura com escapamentos", "rarity": 1, "roulette": "neon", "slot": "engine_cover", "variant": "exhaust"},
	"part_halo_airfoil": {"type": "part", "name": "Halo com asa", "rarity": 1, "roulette": "neon", "slot": "halo", "variant": "airfoil"},
	"part_mirrors_fin": {"type": "part", "name": "Retrovisores com aleta", "rarity": 1, "roulette": "neon", "slot": "mirrors", "variant": "fin"},
	"part_rim_mesh": {"type": "part", "name": "Rodas Colmeia", "rarity": 1, "roulette": "neon", "slot": "rim", "variant": "mesh"},
	"part_halo_ribbed": {"type": "part", "name": "Halo com costelas", "rarity": 0, "roulette": "neon", "slot": "halo", "variant": "ribbed"},
	"part_mirrors_eye": {"type": "part", "name": "Retrovisores Olho", "rarity": 0, "roulette": "neon", "slot": "mirrors", "variant": "eye"},
	"part_rim_disc": {"type": "part", "name": "Rodas Disco", "rarity": 0, "roulette": "neon", "slot": "rim", "variant": "disc"},
	# --- Roleta Inferno ----------------------------------------------------------
	"part_rear_wing_lowdf": {"type": "part", "name": "Asa traseira de baixa carga", "rarity": 3, "roulette": "inferno", "slot": "rear_wing", "variant": "lowdf"},
	"part_rear_wing_highdf": {"type": "part", "name": "Asa traseira de alta carga", "rarity": 3, "roulette": "inferno", "slot": "rear_wing", "variant": "highdf"},
	"part_engine_cover_sharkfin": {"type": "part", "name": "Cobertura com barbatana", "rarity": 2, "roulette": "inferno", "slot": "engine_cover", "variant": "sharkfin"},
	"part_rim_spoked": {"type": "part", "name": "Rodas raiadas", "rarity": 1, "roulette": "inferno", "slot": "rim", "variant": "spoked"},
	"decal_chamas": {"type": "decal", "name": "Chamas", "rarity": 4, "roulette": "inferno", "decal": "chamas"},
	"decal_garras": {"type": "decal", "name": "Garras", "rarity": 3, "roulette": "inferno", "decal": "garras"},
	"decal_logo_s": {"type": "decal", "name": "Logo S", "rarity": 2, "roulette": "inferno", "decal": "logo_s"},
	"decal_xadrez": {"type": "decal", "name": "Bandeira quadriculada", "rarity": 1, "roulette": "inferno", "decal": "xadrez"},
	"decal_shuriken": {"type": "decal", "name": "Shuriken", "rarity": 0, "roulette": "inferno", "decal": "shuriken"},
	"decal_faixa_dupla": {"type": "decal", "name": "Faixas duplas", "rarity": 0, "roulette": "inferno", "decal": "faixa_dupla"},
	"boost_solar_flame": {"type": "boost", "name": "Chama solar", "rarity": 4, "roulette": "inferno", "color": "ff6a00"},
	"neon_lava": {"type": "neon", "name": "Lava", "rarity": 4, "roulette": "inferno", "color": "ff3300"},
	"boost_ruby": {"type": "boost", "name": "Rubi", "rarity": 2, "roulette": "inferno", "color": "ff1744"},
	"neon_amber": {"type": "neon", "name": "Âmbar", "rarity": 2, "roulette": "inferno", "color": "ffb000"},
	"boost_gold": {"type": "boost", "name": "Ouro", "rarity": 1, "roulette": "inferno", "color": "ffd166"},
	"neon_crimson": {"type": "neon", "name": "Carmesim", "rarity": 1, "roulette": "inferno", "color": "c1121f"},
	"neon_violet": {"type": "neon", "name": "Violeta", "rarity": 0, "roulette": "inferno", "color": "8a3df0"},
	"part_rear_wing_dragon": {"type": "part", "name": "Asa traseira Dragão", "rarity": 4, "roulette": "inferno", "slot": "rear_wing", "variant": "dragon"},
	"part_nose_shark": {"type": "part", "name": "Bico Tubarão", "rarity": 3, "roulette": "inferno", "slot": "nose", "variant": "shark"},
	"part_rear_wing_twin": {"type": "part", "name": "Asa traseira Dupla", "rarity": 3, "roulette": "inferno", "slot": "rear_wing", "variant": "twin"},
	"part_front_wing_biplane": {"type": "part", "name": "Asa dianteira Biplano", "rarity": 2, "roulette": "inferno", "slot": "front_wing", "variant": "biplane"},
	"part_engine_cover_spine": {"type": "part", "name": "Cobertura Espinha de dragão", "rarity": 2, "roulette": "inferno", "slot": "engine_cover", "variant": "spine"},
	"part_sidepods_gills": {"type": "part", "name": "Sidepods Guelras", "rarity": 1, "roulette": "inferno", "slot": "sidepods", "variant": "gills"},
	"part_rim_star": {"type": "part", "name": "Rodas Estrela", "rarity": 0, "roulette": "inferno", "slot": "rim", "variant": "star"},
	"part_rear_wing_phoenix": {"type": "part", "name": "Asa traseira Fênix", "rarity": 4, "roulette": "inferno", "slot": "rear_wing", "variant": "phoenix"},
	"part_nose_dragon_snout": {"type": "part", "name": "Bico Focinho de dragão", "rarity": 3, "roulette": "inferno", "slot": "nose", "variant": "dragon_snout"},
	"part_front_wing_bat": {"type": "part", "name": "Asa dianteira Morcego", "rarity": 3, "roulette": "inferno", "slot": "front_wing", "variant": "bat"},
	"part_sidepods_scales": {"type": "part", "name": "Sidepods Escamas de dragão", "rarity": 3, "roulette": "inferno", "slot": "sidepods", "variant": "scales"},
	"part_engine_cover_horns": {"type": "part", "name": "Cobertura com chifres", "rarity": 3, "roulette": "inferno", "slot": "engine_cover", "variant": "horns"},
	"part_rear_wing_blade": {"type": "part", "name": "Asa traseira Lâmina", "rarity": 2, "roulette": "inferno", "slot": "rear_wing", "variant": "blade"},
	"part_engine_cover_scales": {"type": "part", "name": "Cobertura com escamas", "rarity": 2, "roulette": "inferno", "slot": "engine_cover", "variant": "scales"},
	"part_halo_crown": {"type": "part", "name": "Halo Coroa", "rarity": 2, "roulette": "inferno", "slot": "halo", "variant": "crown"},
	"part_rim_shuriken": {"type": "part", "name": "Rodas Shuriken", "rarity": 2, "roulette": "inferno", "slot": "rim", "variant": "shuriken"},
	"part_nose_tusks": {"type": "part", "name": "Bico com presas", "rarity": 1, "roulette": "inferno", "slot": "nose", "variant": "tusks"},
	"part_front_wing_scales": {"type": "part", "name": "Asa dianteira Escamas", "rarity": 1, "roulette": "inferno", "slot": "front_wing", "variant": "scales"},
	"part_halo_horned": {"type": "part", "name": "Halo com chifres", "rarity": 1, "roulette": "inferno", "slot": "halo", "variant": "horned"},
	"part_mirrors_winglet": {"type": "part", "name": "Retrovisores com asinha", "rarity": 1, "roulette": "inferno", "slot": "mirrors", "variant": "winglet"},
	"part_sidepods_bulge": {"type": "part", "name": "Sidepods Musculoso", "rarity": 0, "roulette": "inferno", "slot": "sidepods", "variant": "bulge"},
	"part_mirrors_spiked": {"type": "part", "name": "Retrovisores com espinhos", "rarity": 0, "roulette": "inferno", "slot": "mirrors", "variant": "spiked"},
	"part_rim_yspoke": {"type": "part", "name": "Rodas Raios em Y", "rarity": 0, "roulette": "inferno", "slot": "rim", "variant": "yspoke"},
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


## Cores de uma pintura pronta (3) ou de um item com cor.
static func colors_of(id: String) -> Array[Color]:
	var it: Dictionary = PAINTS.get(id, item(id))
	var out: Array[Color] = []
	if it.has("colors"):
		for c in it["colors"]:
			out.append(Color(c))
	elif it.has("color"):
		out.append(Color(it["color"]))
	return out


## Decalque (id do CarDecals) de um item do tipo "decal".
static func decal_of(id: String) -> String:
	return str(item(id).get("decal", ""))


## Id do item de um decalque padrão ("" se não existe).
static func decal_item(decal: String) -> String:
	var id := "decal_" + decal
	return id if ITEMS.has(id) or FREE.has(id) else ""


## Quantos itens das roletas (do catálogo atual) estão na lista: a coleção para as conquistas.
## Itens de versões antigas (pinturas, capacetes, macacões e rodas, que agora são livres) não contam.
static func count_collectible(ids: Array) -> int:
	var n := 0
	for id in ids:
		if ITEMS.has(str(id)):
			n += 1
	return n


static func roulette_items(roulette: String) -> Array[String]:
	var out: Array[String] = []
	for rarity in range(RARITY_WEIGHTS.size() - 1, -1, -1):
		out.append_array(drops(roulette, rarity))
	return out
