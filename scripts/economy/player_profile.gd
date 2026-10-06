class_name PlayerProfile
extends Node
## Perfil do jogador (autoload "Profile"), salvo em user://profile.cfg: créditos, coleção (peças
## ganhas nas roletas), o que está equipado (e o cenário da garagem) e estatísticas.
##
## Regras (ver ShopCatalog):
## * spin(roleta): cobra o ticket, sorteia com gerador criptográfico e entrega na mesma operação;
##   repetida devolve 30% do preço de tabela.
## * O Estúdio só combina o que a conta tem: as cores da pintura saem das pinturas possuídas
##   (cada uma libera as 3 cores dela), capacete/macacão/rodas/boost/neon saem das peças daquele
##   tipo, e as peças de desempenho das variantes ganhas. Tudo é conferido de novo em
##   clamp_equipped() antes de ir para o carro: o que a conta não tem volta para o gratuito.

signal changed
## Engenharia mudou (separado de `changed` para não reconstruir as telas a cada clique de slider).
signal setup_changed
## Modo "remote": o jogador mudou o que está equipado; o cliente manda para o servidor validar.
signal equip_requested(equipped: Dictionary)

const PATH := "user://profile.cfg"
const COLOR_FIELDS := {"primary": "livery", "secondary": "livery", "accent": "livery", "helmet": "helmet",
	"suit": "suit", "rim": "rim", "boost": "boost", "neon": "neon"}

static var save_path := PATH

var credits := ShopCatalog.START_CREDITS
var owned := {}
var equipped := {}
var stats := {"spins": 0, "races": 0, "earned": 0, "duplicates": 0}

var _crypto := Crypto.new()

## Onde vive a verdade desta conta:
## * "local": arquivo user://profile.cfg (jogo offline, como antes);
## * "server": dentro do servidor dedicado (memória; o servidor grava no banco);
## * "remote": cliente conectado; espelha a conta do servidor (from_dict). Créditos, coleção e
##   giros só mudam pelo servidor; o equipamento muda aqui na hora e vai para o servidor, que
##   confere o que a conta tem e devolve a conta valendo.
var mode := "local"
## Conectado a um servidor que aceita o carro do aparelho: itens da coleção local também contam
## como "tem" (para montar o carro). PENDENTE (produção): o servidor validar a posse.
var extra_owned := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_profile()


# ---------------------------------------------------------------------------
# Persistência
# ---------------------------------------------------------------------------
static func default_equipped() -> Dictionary:
	var free := ShopCatalog.FREE
	return {
		"livery": "livery_akane",
		"primary": free["livery_akane"]["colors"][0], "secondary": free["livery_akane"]["colors"][1],
		"accent": free["livery_akane"]["colors"][2],
		"helmet": free["helmet_akane"]["color"], "suit": free["suit_akane"]["color"],
		"rim": free["rim_akane"]["color"], "boost": free["boost_akane"]["color"],
		"neon_on": false, "neon": "",
		"parts": {},
		"scene": "neon",
		"paint_finish": 0,
		"rim_finish": 0,
		"setup": {},
	}


func reset_profile() -> void:
	credits = ShopCatalog.START_CREDITS
	owned = {}
	equipped = default_equipped()
	stats = {"spins": 0, "races": 0, "earned": 0, "duplicates": 0}
	save_profile()
	changed.emit()


func load_profile() -> void:
	equipped = default_equipped()
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		# Conta nova: começa com os créditos iniciais
		save_profile()
		return
	credits = maxi(int(cfg.get_value("wallet", "credits", ShopCatalog.START_CREDITS)), 0)
	owned = {}
	for id in cfg.get_value("collection", "owned", []):
		if ShopCatalog.ITEMS.has(str(id)):
			owned[str(id)] = true
	var eq: Variant = cfg.get_value("equipped", "data", {})
	if eq is Dictionary:
		for key in equipped:
			if eq.has(key):
				equipped[key] = eq[key]
	var st: Variant = cfg.get_value("stats", "data", {})
	if st is Dictionary:
		for key in stats:
			stats[key] = int(st.get(key, 0))
	clamp_equipped()


func save_profile() -> void:
	if mode != "local":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("wallet", "credits", credits)
	cfg.set_value("collection", "owned", owned.keys())
	cfg.set_value("equipped", "data", equipped)
	cfg.set_value("stats", "data", stats)
	cfg.save(save_path)


## Estado completo da conta (servidor → cliente, e servidor → banco).
func to_dict() -> Dictionary:
	return {"credits": credits, "owned": owned.keys(), "equipped": equipped.duplicate(true), "stats": stats.duplicate()}


func from_dict(d: Dictionary) -> void:
	credits = maxi(int(d.get("credits", ShopCatalog.START_CREDITS)), 0)
	owned = {}
	for id in d.get("owned", []):
		if ShopCatalog.ITEMS.has(str(id)):
			owned[str(id)] = true
	equipped = default_equipped()
	var eq: Variant = d.get("equipped", {})
	if eq is Dictionary:
		for key in equipped:
			if eq.has(key):
				equipped[key] = eq[key]
	var st: Variant = d.get("stats", {})
	if st is Dictionary:
		for key in stats:
			stats[key] = int(st.get(key, 0))
	clamp_equipped()
	changed.emit()
	setup_changed.emit()


## Equipamento pedido pelo cliente (servidor): aceita só o que a conta tem.
func apply_requested_equipped(eq: Dictionary) -> void:
	for key in equipped:
		if eq.has(key):
			equipped[key] = eq[key]
	clamp_equipped()


# ---------------------------------------------------------------------------
# Coleção
# ---------------------------------------------------------------------------
func owns(id: String) -> bool:
	return ShopCatalog.is_free(id) or owned.has(id) or extra_owned.has(id)


## Equipamento só com estrutura válida (cores, peças e engenharia que existem, nos limites), sem
## conferir se a conta tem os itens. Usado pelo servidor enquanto aceita o carro do aparelho
## (NetProtocol.TRUST_CLIENT_CAR).
static func sanitize_equipped(eq: Dictionary) -> Dictionary:
	var tmp := PlayerProfile.new()
	tmp.mode = "server"
	for id in ShopCatalog.ITEMS:
		tmp.owned[id] = true
	tmp.equipped = default_equipped()
	tmp.apply_requested_equipped(eq)
	var out := tmp.equipped.duplicate(true)
	tmp.free()
	return out


## Peças que a conta tem de um tipo (gratuitas incluídas).
func owned_of_type(type: String) -> Array[String]:
	var out: Array[String] = []
	for id in ShopCatalog.items_of_type(type):
		if owns(id):
			out.append(id)
	return out


## Cores liberadas para um campo do Estúdio (sem repetir), na ordem das peças.
func unlocked_colors(field: String) -> Array[Color]:
	var out: Array[Color] = []
	var seen := {}
	for id in owned_of_type(COLOR_FIELDS[field]):
		for c in ShopCatalog.colors_of(id):
			var key := c.to_html(false)
			if not seen.has(key):
				seen[key] = true
				out.append(c)
	return out


func is_color_unlocked(field: String, color: Color) -> bool:
	var key := color.to_html(false)
	for c in unlocked_colors(field):
		if c.to_html(false) == key:
			return true
	return false


## Variantes de uma peça que a conta pode montar (a padrão sempre).
func owned_variants(slot: String) -> Array[String]:
	var out: Array[String] = [CarPartCatalog.default_variant(slot)]
	for id in owned_of_type("part"):
		var it := ShopCatalog.item(id)
		if it["slot"] == slot and not it["variant"] in out:
			out.append(it["variant"])
	return out


func collection_count(type: String) -> Vector2i:
	var have := 0
	var total := 0
	for id in ShopCatalog.items_of_type(type):
		if ShopCatalog.is_free(id):
			continue
		total += 1
		if owned.has(id):
			have += 1
	return Vector2i(have, total)


# ---------------------------------------------------------------------------
# Loja
# ---------------------------------------------------------------------------
## Compra e gira um ticket. Devolve {ok, error?, item, dup, refund, rarity}.
func spin(roulette: String) -> Dictionary:
	if not ShopCatalog.ROULETTES.has(roulette):
		return {"ok": false, "error": "Roleta desconhecida."}
	if credits < ShopCatalog.TICKET_PRICE:
		return {"ok": false, "error": "Créditos insuficientes: o ticket custa %s." % format_credits(ShopCatalog.TICKET_PRICE)}
	credits -= ShopCatalog.TICKET_PRICE
	var id := ShopCatalog.draw(roulette, _secure_roll())
	var dup := owned.has(id)
	var refund := 0
	if dup:
		refund = ShopCatalog.refund_of(id)
		credits += refund
		stats["duplicates"] += 1
	else:
		owned[id] = true
	stats["spins"] += 1
	save_profile()
	changed.emit()
	return {"ok": true, "item": id, "dup": dup, "refund": refund, "rarity": ShopCatalog.item(id)["rarity"]}


## Créditos da corrida: por volta completada, pela dificuldade dos bots. Devolve o valor pago.
func award_race(laps_completed: int, difficulty: int, finished: bool, disqualified: bool) -> int:
	if disqualified or laps_completed <= 0:
		return 0
	var amount: int = ShopCatalog.REWARD_PER_LAP[clampi(difficulty, 0, 3)] * laps_completed
	if not finished:
		amount = amount / 2  # abandono: metade do que andou, como consolação
	credits += amount
	stats["races"] += 1
	stats["earned"] += amount
	save_profile()
	changed.emit()
	return amount


## Número uniforme em [0, 1) de um gerador criptográfico (o sorteio não depende de randi()).
func _secure_roll() -> float:
	var bytes := _crypto.generate_random_bytes(4)
	var n := bytes.decode_u32(0)
	return float(n) / 4294967296.0


static func format_credits(amount: int) -> String:
	var s := str(absi(amount))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if amount < 0 else "") + s + out


# ---------------------------------------------------------------------------
# Estúdio (equipar)
# ---------------------------------------------------------------------------
func equip_livery(id: String) -> void:
	if not owns(id) or ShopCatalog.item(id).get("type", "") != "livery":
		return
	var cols := ShopCatalog.colors_of(id)
	equipped["livery"] = id
	equipped["primary"] = cols[0].to_html(false)
	equipped["secondary"] = cols[1].to_html(false)
	equipped["accent"] = cols[2].to_html(false)
	_commit()


## Troca uma cor (primary/secondary/accent/helmet/suit/rim/boost/neon) — só cores liberadas.
func equip_color(field: String, color: Color) -> void:
	if not COLOR_FIELDS.has(field) or not is_color_unlocked(field, color):
		return
	equipped[field] = color.to_html(false)
	if field in ["primary", "secondary", "accent"]:
		equipped["livery"] = _matching_livery()
	_commit()


func equip_part(slot: String, variant: String) -> void:
	if not variant in owned_variants(slot):
		return
	var parts: Dictionary = equipped["parts"]
	parts[slot] = variant
	_commit()


func set_neon(on: bool) -> void:
	equipped["neon_on"] = on and not owned_of_type("neon").is_empty()
	if equipped["neon_on"] and equipped["neon"] == "":
		equipped["neon"] = ShopCatalog.colors_of(owned_of_type("neon")[0])[0].to_html(false)
	_commit()


## Acabamento da pintura ("paint_finish") ou das rodas ("rim_finish"): todos vêm com o jogo.
func set_finish(kind: String, index: int) -> void:
	if kind in ["paint_finish", "rim_finish"]:
		equipped[kind] = index
		_commit()


func has_neon() -> bool:
	return not owned_of_type("neon").is_empty()


func _matching_livery() -> String:
	for id in owned_of_type("livery"):
		var cols := ShopCatalog.colors_of(id)
		if cols[0].to_html(false) == equipped["primary"] and cols[1].to_html(false) == equipped["secondary"] \
				and cols[2].to_html(false) == equipped["accent"]:
			return id
	return ""  # combinação própria


func _commit() -> void:
	clamp_equipped()
	save_profile()
	changed.emit()
	if mode == "remote":
		equip_requested.emit(equipped.duplicate(true))


## Trava: o que a conta não tem volta para o gratuito.
func clamp_equipped() -> void:
	var defaults := default_equipped()
	for field in COLOR_FIELDS:
		var value := str(equipped.get(field, ""))
		if field == "neon":
			if value != "" and not is_color_unlocked("neon", Color(value)):
				equipped["neon"] = ""
			continue
		if value == "" or not Color.html_is_valid(value) or not is_color_unlocked(field, Color(value)):
			equipped[field] = defaults[field]
	if not equipped.get("parts") is Dictionary:
		equipped["parts"] = {}
	# Engenharia: só chaves conhecidas, dentro dos limites
	if not equipped.get("setup") is Dictionary:
		equipped["setup"] = {}
	var setup: Dictionary = equipped["setup"]
	for key in setup.keys():
		var p := CarSetup.param(str(key))
		if p.is_empty() or not (setup[key] is float or setup[key] is int):
			setup.erase(key)
		else:
			setup[key] = clampf(float(setup[key]), p[5], p[6])
	var parts: Dictionary = equipped["parts"]
	for slot in parts.keys():
		if not CarPartCatalog.has_variant(slot, str(parts[slot])) or not str(parts[slot]) in owned_variants(slot):
			parts.erase(slot)
	equipped["neon_on"] = bool(equipped.get("neon_on", false)) and has_neon() and equipped["neon"] != ""
	equipped["paint_finish"] = clampi(int(equipped.get("paint_finish", 0)), 0, CarConfig.PAINT_FINISHES.size() - 1)
	equipped["rim_finish"] = clampi(int(equipped.get("rim_finish", 0)), 0, CarConfig.RIM_FINISHES.size() - 1)
	if not owns(str(equipped.get("livery", ""))):
		equipped["livery"] = _matching_livery()


# ---------------------------------------------------------------------------
# Engenharia (comportamento do carro)
# ---------------------------------------------------------------------------
func setup_value(car: F1Car, key: String) -> float:
	var setup: Dictionary = equipped["setup"]
	return float(setup[key]) if setup.has(key) else float(CarSetup.defaults(car)[key])


func set_setup_value(key: String, value: float) -> void:
	var p := CarSetup.param(key)
	if p.is_empty():
		return
	var setup: Dictionary = equipped["setup"]
	setup[key] = clampf(value, p[5], p[6])
	save_profile()
	setup_changed.emit()
	if mode == "remote":
		equip_requested.emit(equipped.duplicate(true))


## Volta um parâmetro (ou todos, com key vazia) ao de fábrica.
func reset_setup(key := "") -> void:
	var setup: Dictionary = equipped["setup"]
	if key == "":
		setup.clear()
	else:
		setup.erase(key)
	save_profile()
	setup_changed.emit()
	if mode == "remote":
		equip_requested.emit(equipped.duplicate(true))


func apply_setup(car: F1Car) -> void:
	if car:
		CarSetup.apply(car, equipped["setup"])


## Aplica o que está equipado na configuração de um carro (peças, cores, neon, boost).
func apply_to_config(config: CarConfig) -> void:
	if config == null:
		return
	clamp_equipped()
	for slot in CarPartCatalog.all_slots():
		var want: String = equipped["parts"].get(slot, CarPartCatalog.default_variant(slot))
		if config.get_part(slot) != want:
			config.set_part(slot, want)
	config.primary_color = Color(equipped["primary"])
	config.secondary_color = Color(equipped["secondary"])
	config.accent_color = Color(equipped["accent"])
	config.helmet_color = Color(equipped["helmet"])
	config.suit_color = Color(equipped["suit"])
	config.rim_color = Color(equipped["rim"])
	config.boost_color = Color(equipped["boost"])
	config.neon_enabled = equipped["neon_on"]
	config.paint_finish = equipped["paint_finish"]
	config.rim_finish = equipped["rim_finish"]
	if equipped["neon"] != "":
		config.neon_color = Color(equipped["neon"])
