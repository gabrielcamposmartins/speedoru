class_name PlayerProfile
extends Node
## Perfil do jogador (autoload "Profile"), salvo em user://profile.cfg: créditos, coleção (peças
## ganhas nas roletas), o que está equipado (e o cenário da garagem) e estatísticas.
##
## Regras (ver ShopCatalog):
## * spin(roleta): cobra o ticket, sorteia com gerador criptográfico e entrega na mesma operação;
##   repetida devolve 30% do preço de tabela. As roletas têm peças, decalques, boost e neon.
## * Cores livres: carro (3 cores), capacete, macacão e rodas aceitam qualquer cor; as pinturas
##   prontas (ShopCatalog.PAINTS) são atalhos grátis. Brilho do boost e neon: só as cores ganhas.
## * Peças de desempenho: só as variantes ganhas; decalques padrão: só os ganhos (ou grátis); os
##   SVGs do próprio jogador são livres. Tudo é conferido de novo em clamp_equipped() antes de ir
##   para o carro: o que a conta não tem volta para o padrão.

signal changed
## Engenharia mudou (separado de `changed` para não reconstruir as telas a cada clique de slider).
signal setup_changed
## Cor, tamanho ou giro de um decalque mudou (idem: sliders do Estúdio).
signal decals_changed
## Modo "remote": o jogador mudou o que está equipado; o cliente manda para o servidor validar.
signal equip_requested(equipped: Dictionary)

const PATH := "user://profile.cfg"
## Campos de cor (boost e neon só com cores ganhas: ShopCatalog.GACHA_COLORS).
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
	if NetProtocol.is_server_process():
		# Servidor: o perfil deste aparelho não é dele (nunca lê nem grava o arquivo)
		mode = "server"
		equipped = default_equipped()
		return
	load_profile()


# ---------------------------------------------------------------------------
# Persistência
# ---------------------------------------------------------------------------
static func default_equipped() -> Dictionary:
	var paint: Array = ShopCatalog.PAINTS[ShopCatalog.DEFAULT_PAINT]["colors"]
	var def := ShopCatalog.DEFAULT_COLORS
	return {
		"livery": ShopCatalog.DEFAULT_PAINT,
		"primary": paint[0], "secondary": paint[1], "accent": paint[2],
		"helmet": def["helmet"], "suit": def["suit"], "rim": def["rim"], "boost": def["boost"],
		"neon_on": false, "neon": def["neon"],
		"parts": {},
		"scene": "neon",
		"paint_finish": 0,
		"paint_scheme": 0,
		"rim_finish": 0,
		"setup": {},
		"decals": {},
		"skin": "",
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


## Sugestões de cor para um campo do Estúdio (sem repetir): [nome, cor]. As cores do carro saem
## das pinturas prontas; as outras de ShopCatalog.COLOR_SUGGESTIONS. Qualquer cor é aceita.
func color_suggestions(field: String) -> Array:
	var out := []
	var seen := {}
	if field in ["primary", "secondary", "accent"]:
		var k := ["primary", "secondary", "accent"].find(field)
		for id in ShopCatalog.PAINTS:
			var c := Color(str(ShopCatalog.PAINTS[id]["colors"][k]))
			if not seen.has(c.to_html(false)):
				seen[c.to_html(false)] = true
				out.append([ShopCatalog.PAINTS[id]["name"], c])
	else:
		for item in ShopCatalog.COLOR_SUGGESTIONS.get(field, []):
			out.append([item[0], Color(str(item[1]))])
	return out


## Cores ganhas de um tipo ("boost"/"neon"): [id, nome, cor], grátis primeiro.
func owned_colors(type: String) -> Array:
	var out := []
	for id in owned_of_type(type):
		var it := ShopCatalog.item(id)
		out.append([id, it["name"], Color(str(it["color"]))])
	return out


## A conta tem um item de boost/neon com essa cor?
func owns_color(type: String, html: String) -> bool:
	if not Color.html_is_valid(html):
		return false
	var want := Color(html).to_html(false)
	for c in owned_colors(type):
		if (c[2] as Color).to_html(false) == want:
			return true
	return false


## Decalques padrão (ids do CarDecals) que a conta pode usar: grátis e ganhos nas roletas.
func owned_decals() -> Array[String]:
	var out: Array[String] = []
	for p in CarDecals.PRESETS:
		var item := ShopCatalog.decal_item(p[0])
		if item != "" and owns(item):
			out.append(p[0])
	return out


## Um decalque pode ser usado: SVG do jogador (livre) ou padrão que a conta tem.
func can_use_decal(id: String) -> bool:
	if id.begins_with(CarDecals.CUSTOM_PREFIX):
		return CarDecals.valid_id(id)
	return id in owned_decals()


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
## Aplica uma pintura pronta (grátis): as três cores do carro.
func equip_livery(id: String) -> void:
	if not ShopCatalog.PAINTS.has(id):
		return
	var cols := ShopCatalog.colors_of(id)
	equipped["livery"] = id
	equipped["primary"] = cols[0].to_html(false)
	equipped["secondary"] = cols[1].to_html(false)
	equipped["accent"] = cols[2].to_html(false)
	_commit()


## Troca uma cor (primary/secondary/accent/helmet/suit/rim: qualquer cor; boost/neon: só as ganhas).
func equip_color(field: String, color: Color) -> void:
	if not COLOR_FIELDS.has(field):
		return
	if field in ShopCatalog.GACHA_COLORS and not owns_color(field, color.to_html(false)):
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


## Coloca (ou tira, com id vazio) um decalque num lugar do carro; mantém cor/tamanho/giro.
func set_decal(slot: String, id: String) -> void:
	if not CarDecals.SLOTS.has(slot):
		return
	var decals: Dictionary = equipped["decals"]
	if id == "":
		decals.erase(slot)
	elif can_use_decal(id):
		var cur: Dictionary = decals.get(slot, {"color": "ffffff", "scale": 1.0, "rot": 0.0})
		if str(cur.get("id", "")) != id:
			cur["mirror"] = CarDecals.default_mirror(id)
		cur["id"] = id
		decals[slot] = cur
	_commit()


## Cor ("rrggbb"), tamanho ("scale"), largura ("stretch"), giro ("rot", graus) ou posição ("x"/"y",
## -1..1) de um decalque já colocado. Não reconstrói as telas (sliders, arrastar): avisa por
## decals_changed; grava e manda ao servidor quando os valores param de mudar.
func set_decal_value(slot: String, key: String, value: Variant) -> void:
	var decals: Dictionary = equipped["decals"]
	if not decals.has(slot) or not key in ["color", "scale", "stretch", "rot", "x", "y", "mirror"]:
		return
	decals[slot][key] = value
	equipped["decals"] = CarDecals.sanitize(decals)
	decals_changed.emit()
	_save_soon()



## Grava (e, conectado, manda o equipamento) 0,35 s depois da última mudança seguida.
func _save_soon() -> void:
	if not is_inside_tree():
		save_profile()
		return
	_save_tick += 1
	var tick := _save_tick
	await get_tree().create_timer(0.35, true).timeout
	if tick != _save_tick:
		return
	save_profile()
	if mode == "remote":
		equip_requested.emit(equipped.duplicate(true))


var _save_tick := 0


## Liga/desliga o neon (precisa de uma cor de neon ganha; sem cor escolhida, usa a primeira).
func set_neon(on: bool) -> void:
	if on and not owns_color("neon", str(equipped["neon"])):
		var mine := owned_colors("neon")
		if mine.is_empty():
			return
		equipped["neon"] = (mine[0][2] as Color).to_html(false)
	equipped["neon_on"] = on
	_commit()


## Acabamento da pintura ("paint_finish"), das rodas ("rim_finish") ou esquema de pintura
## ("paint_scheme"): todos vêm com o jogo.
func set_finish(kind: String, index: int) -> void:
	if kind in ["paint_finish", "rim_finish", "paint_scheme"]:
		equipped[kind] = index
		_commit()


## Equipa uma skin (hash do CarSkin; "" tira). Online, o servidor pede a imagem se não tiver.
func set_skin(h: String) -> void:
	equipped["skin"] = h if CarSkin.valid_hash(h) else ""
	_commit()


func has_neon() -> bool:
	return not owned_of_type("neon").is_empty()


## Pintura pronta com exatamente as três cores atuais ("" = combinação própria).
func _matching_livery() -> String:
	for id in ShopCatalog.PAINTS:
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


## Trava: o que a conta não tem volta para o padrão (cores livres só precisam ser válidas; boost e
## neon precisam ser cores ganhas).
func clamp_equipped() -> void:
	var defaults := default_equipped()
	for field in COLOR_FIELDS:
		var value := str(equipped.get(field, ""))
		if field in ShopCatalog.GACHA_COLORS:
			if owns_color(field, value):
				equipped[field] = Color(value).to_html(false)
			elif field == "neon":
				var mine := owned_colors("neon")
				equipped["neon"] = (mine[0][2] as Color).to_html(false) if not mine.is_empty() else ""
			else:
				equipped[field] = defaults[field]
			continue
		if value == "" or not Color.html_is_valid(value):
			equipped[field] = defaults[field]
		else:
			equipped[field] = Color(value).to_html(false)
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
	equipped["neon_on"] = bool(equipped.get("neon_on", false)) and str(equipped["neon"]) != ""
	# Decalques: só lugares/ids válidos, valores nos limites, e padrão só se a conta tiver
	var decals := CarDecals.sanitize(equipped.get("decals", {}))
	for slot in decals.keys():
		if not can_use_decal(str(decals[slot]["id"])):
			decals.erase(slot)
	equipped["decals"] = decals
	equipped["paint_finish"] = clampi(int(equipped.get("paint_finish", 0)), 0, CarConfig.PAINT_FINISHES.size() - 1)
	equipped["paint_scheme"] = clampi(int(equipped.get("paint_scheme", 0)), 0, CarConfig.PAINT_SCHEMES.size() - 1)
	equipped["rim_finish"] = clampi(int(equipped.get("rim_finish", 0)), 0, CarConfig.RIM_FINISHES.size() - 1)
	# Skin: hash válido; no aparelho, só se o arquivo ainda existe (no servidor ele chega depois)
	var skin := str(equipped.get("skin", ""))
	if not CarSkin.valid_hash(skin) or (mode == "local" and not CarSkin.has_local(skin)):
		skin = ""
	equipped["skin"] = skin
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
	config.paint_scheme = equipped["paint_scheme"]
	if var_to_str(config.decals) != var_to_str(equipped["decals"]):
		config.decals = (equipped["decals"] as Dictionary).duplicate(true)
	config.rim_finish = equipped["rim_finish"]
	if config.skin != str(equipped["skin"]):
		config.skin = str(equipped["skin"])
	if equipped["neon"] != "":
		config.neon_color = Color(equipped["neon"])
