class_name PlayerProfile
extends Node
## Perfil do jogador (autoload "Profile"), salvo em user://profile.cfg: créditos, coleção (peças
## ganhas nas roletas), o que está equipado (e o cenário da garagem) e estatísticas.
##
## Regras (ver ShopCatalog):
## * spin(roleta): cobra o ticket (2.500 créditos ou um ticket ganho), sorteia com gerador
##   criptográfico e entrega na mesma operação; repetida devolve 30% do preço de tabela. As roletas
##   têm peças, decalques, boost, neon e rastros de partículas.
## * grant_item(id): prêmio (conquista, missão da semana, roleta do vencedor); repetida também vira
##   créditos. Os exclusivos (títulos, Sirene) não saem nas roletas da loja.
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
## Padrões de pintura do jogador (Estúdio → Pinturas): ficam no aparelho, fora do perfil, e valem
## offline e online. Cada um: {name, primary, secondary, accent, scheme, finish}.
static var paints_path := "user://paint_presets.cfg"
const MAX_CUSTOM_PAINTS := 24

var credits := ShopCatalog.START_CREDITS
## Tickets ganhos (roleta do vencedor): cada um paga um giro de roleta da loja.
var tickets := 0
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
## Origem dos itens (selos do Estúdio e da Galeria). A outra coleção desta conta, quando se sabe:
## * offline ("local"): a coleção da conta no servidor atual, guardada pelo Net na última conexão;
## * conectado ("remote"): a coleção deste aparelho (o Net preenche ao conectar).
## `other_known` falso = nunca conectou a este servidor: não dá para dizer de onde vem nada.
var other_owned := {}
var other_known := false


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
		# Rastro de partículas: id do item ("" = nenhum)
		"trail": "",
		# Luz de ultrapassagem: id do item ("" = âmbar padrão)
		"signal": "",
		"parts": {},
		"paint_finish": 0,
		"paint_scheme": 0,
		"rim_finish": 0,
		"setup": CarSetup.PLAYER_DEFAULTS.duplicate(),
		"decals": {},
		"skin": "",
		# Hora (unix, s) da última mudança feita pelo jogador: decide qual carro vale quando o do
		# aparelho e o do servidor são diferentes (o mais novo)
		"edited": 0.0,
	}


func reset_profile() -> void:
	credits = ShopCatalog.START_CREDITS
	tickets = 0
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
	tickets = maxi(int(cfg.get_value("wallet", "tickets", 0)), 0)
	_load_owned(cfg.get_value("collection", "owned", []))
	var eq: Variant = cfg.get_value("equipped", "data", {})
	if eq is Dictionary:
		for key in equipped:
			if eq.has(key):
				equipped[key] = eq[key]
		_keep_old_setup(eq)
	var st: Variant = cfg.get_value("stats", "data", {})
	if st is Dictionary:
		for key in stats:
			stats[key] = int(st.get(key, 0))
	clamp_equipped()


## Coleção a partir de uma lista de ids: só o que existe no catálogo. Itens aposentados
## (ShopCatalog.RETIRED) viram créditos na memória: carregar não grava nada (os testes carregam o
## perfil do aparelho ao abrir); a troca fica no arquivo na próxima gravação normal e, até lá,
## cada carga devolve o mesmo valor (uma vez só). Devolve se algum foi trocado.
func _load_owned(ids: Array) -> bool:
	owned = {}
	var retired := false
	for id in ids:
		if ShopCatalog.ITEMS.has(str(id)):
			owned[str(id)] = true
		elif ShopCatalog.RETIRED.has(str(id)) and mode != "remote":
			credits += int(ShopCatalog.RETIRED[str(id)])
			retired = true
	return retired


func save_profile() -> void:
	if mode != "local":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("wallet", "credits", credits)
	cfg.set_value("wallet", "tickets", tickets)
	cfg.set_value("collection", "owned", owned.keys())
	cfg.set_value("equipped", "data", equipped)
	cfg.set_value("stats", "data", stats)
	cfg.save(save_path)


## Estado completo da conta (servidor → cliente, e servidor → banco).
func to_dict() -> Dictionary:
	return {"credits": credits, "tickets": tickets, "owned": owned.keys(), "equipped": equipped.duplicate(true),
		"stats": stats.duplicate()}


func from_dict(d: Dictionary) -> void:
	credits = maxi(int(d.get("credits", ShopCatalog.START_CREDITS)), 0)
	tickets = maxi(int(d.get("tickets", 0)), 0)
	_load_owned(d.get("owned", []))
	var eq: Variant = d.get("equipped", {})
	# Conectado: uma resposta do servidor mais velha que a última mudança feita aqui (ainda indo
	# para ele) não desfaz a mudança
	var keep_local := mode == "remote" and eq is Dictionary \
		and float(eq.get("edited", 0.0)) < float(equipped.get("edited", 0.0))
	if not keep_local:
		equipped = default_equipped()
		if eq is Dictionary:
			for key in equipped:
				if eq.has(key):
					equipped[key] = eq[key]
			_keep_old_setup(eq)
	var st: Variant = d.get("stats", {})
	if st is Dictionary:
		for key in stats:
			stats[key] = int(st.get(key, 0))
	clamp_equipped()
	changed.emit()
	setup_changed.emit()


## Títulos que a coleção dá (itens do tipo "title").
func owned_titles() -> Array[String]:
	var out: Array[String] = []
	for id in owned:
		var t := ShopCatalog.title_of(str(id))
		if t != "":
			out.append(t)
	return out


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


## Peças que a conta tem de um tipo (gratuitas incluídas). `with_other`: também as que só a outra
## coleção tem (o Estúdio mostra apagadas as que não dá para usar agora, ver known()).
func owned_of_type(type: String, with_other := false) -> Array[String]:
	var out: Array[String] = []
	for id in ShopCatalog.items_of_type(type):
		if known(id) if with_other else owns(id):
			out.append(id)
	return out


## Pode usar agora ou a outra coleção desta conta tem (conta no servidor ou este aparelho).
func known(id: String) -> bool:
	return owns(id) or other_owned.has(id)


## De onde vem um item: "free" (grátis), "both" (conta e aparelho, ou origem desconhecida),
## "account" (só na conta do servidor), "device" (só neste aparelho) ou "" (não tem).
func origin(id: String) -> String:
	if ShopCatalog.is_free(id):
		return "free"
	var here := owned.has(id)
	var other := other_owned.has(id)
	if mode == "remote" and extra_owned.has(id):
		other = true
	if not here and not other:
		return ""
	if not other_known or (here and other):
		return "both"
	if mode == "remote":
		return "account" if here else "device"
	return "device" if here else "account"


## Selo de origem: [texto, cor do tema (Retro.c), pode usar agora]; texto "" = sem selo (nos dois
## lados, grátis ou origem desconhecida).
func badge_of(id: String) -> Array:
	match origin(id):
		"account":
			return ["CONTA", "accent_2", true] if owns(id) else ["SÓ ONLINE", "muted", false]
		"device":
			return ["APARELHO", "warn", true] if owns(id) else ["SÓ OFFLINE", "muted", false]
	return ["", "", owns(id)]


## Item da loja de uma variante de peça ("" = a padrão ou sem item).
static func part_item(slot: String, variant: String) -> String:
	for id in ShopCatalog.items_of_type("part"):
		var it := ShopCatalog.item(id)
		if it["slot"] == slot and it["variant"] == variant:
			return id
	return ""


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
func owned_colors(type: String, with_other := false) -> Array:
	var out := []
	for id in owned_of_type(type, with_other):
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
func owned_decals(with_other := false) -> Array[String]:
	var out: Array[String] = []
	for p in CarDecals.PRESETS:
		var item := ShopCatalog.decal_item(p[0])
		if item != "" and (known(item) if with_other else owns(item)):
			out.append(p[0])
	return out


## Um decalque pode ser usado: SVG do jogador (livre) ou padrão que a conta tem.
func can_use_decal(id: String) -> bool:
	if id.begins_with(CarDecals.CUSTOM_PREFIX):
		return CarDecals.valid_id(id)
	return id in owned_decals()


## Variantes de uma peça que a conta pode montar (a padrão sempre).
func owned_variants(slot: String, with_other := false) -> Array[String]:
	var out: Array[String] = [CarPartCatalog.default_variant(slot)]
	for id in owned_of_type("part", with_other):
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
## Compra e gira um ticket (com [param use_ticket], gasta um ticket ganho em vez dos créditos).
## Devolve {ok, error?, item, dup, refund, rarity, ticket}.
func spin(roulette: String, use_ticket := false) -> Dictionary:
	if not ShopCatalog.ROULETTES.has(roulette) or ShopCatalog.is_hidden(roulette):
		return {"ok": false, "error": "Roleta desconhecida."}
	if use_ticket:
		if tickets <= 0:
			return {"ok": false, "error": "Você não tem tickets."}
		tickets -= 1
	else:
		if credits < ShopCatalog.TICKET_PRICE:
			return {"ok": false, "error": "Créditos insuficientes: o ticket custa %s." % format_credits(ShopCatalog.TICKET_PRICE)}
		credits -= ShopCatalog.TICKET_PRICE
	var id := ShopCatalog.draw(roulette, _secure_roll())
	var res := _give(id)
	stats["spins"] += 1
	save_profile()
	changed.emit()
	res["ticket"] = use_ticket
	return res


## Entrega um prêmio (conquista, missão, roleta do vencedor): repetida vira créditos.
## Devolve {ok, item, dup, refund, rarity}.
func grant_item(id: String) -> Dictionary:
	if ShopCatalog.item(id).is_empty() or ShopCatalog.is_free(id):
		return {"ok": false, "error": "Item desconhecido."}
	var res := _give(id)
	save_profile()
	changed.emit()
	return res


func _give(id: String) -> Dictionary:
	var dup := owned.has(id)
	var refund := 0
	if dup:
		refund = ShopCatalog.refund_of(id)
		credits += refund
		stats["duplicates"] += 1
	else:
		owned[id] = true
	return {"ok": true, "item": id, "dup": dup, "refund": refund, "rarity": ShopCatalog.item(id)["rarity"]}


## Créditos de prêmio (missões, conquistas, roleta do vencedor): entram em "earned".
func add_credits(amount: int) -> void:
	credits += maxi(amount, 0)
	stats["earned"] += maxi(amount, 0)
	save_profile()
	changed.emit()


## Exclusivo sorteado entre os que a conta ainda não tem ("" se já tem todos).
func pick_exclusive(roll: float) -> String:
	var left: Array = ShopCatalog.EXCLUSIVE_POOL.filter(func(id: String) -> bool: return not owned.has(id))
	if left.is_empty():
		return ""
	return str(left[mini(int(roll * left.size()), left.size() - 1)])


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



## Marca a hora da mudança do equipamento (feita pelo jogador).
func _touch() -> void:
	equipped["edited"] = Time.get_unix_time_from_system()


## Conectado: guarda no aparelho o equipamento que vale no servidor (só ele; créditos e coleção
## do perfil local ficam como estão). Assim o carro offline é o mesmo, e a próxima conexão não
## manda um carro mais velho que o do servidor.
func store_equipped_locally() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	cfg.set_value("equipped", "data", equipped.duplicate(true))
	cfg.save(save_path)


## Grava (e, conectado, manda o equipamento) 0,35 s depois da última mudança seguida.
func _save_soon() -> void:
	_touch()
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


## Equipa um rastro de partículas (id do item; "" tira).
func equip_trail(id: String) -> void:
	if id != "" and (ShopCatalog.item(id).get("type", "") != "trail" or not owns(id)):
		return
	equipped["trail"] = id
	_commit()


## Equipa uma luz de ultrapassagem (id do item; "" volta ao âmbar).
func equip_signal(id: String) -> void:
	if id != "" and (ShopCatalog.item(id).get("type", "") != "signal" or not owns(id)):
		return
	equipped["signal"] = id
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


# ---------------------------------------------------------------------------
# Padrões de pintura do jogador
# ---------------------------------------------------------------------------
func custom_paints() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(paints_path) != OK:
		return []
	var out := []
	for p in cfg.get_value("paints", "list", []):
		if p is Dictionary and _valid_paint(p):
			out.append(p)
	return out.slice(0, MAX_CUSTOM_PAINTS)


static func _valid_paint(p: Dictionary) -> bool:
	for f in ["primary", "secondary", "accent"]:
		if not Color.html_is_valid(str(p.get(f, ""))):
			return false
	return true


func _store_custom_paints(list: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("paints", "list", list)
	cfg.save(paints_path)


## Salva as cores, o esquema e o acabamento atuais como um padrão novo (ou atualiza o de mesmo
## nome). Devolve o índice dele (-1 se a lista está cheia).
func save_custom_paint(paint_name: String) -> int:
	var list := custom_paints()
	paint_name = paint_name.strip_edges().left(24)
	if paint_name == "":
		paint_name = "Pintura %d" % (list.size() + 1)
	var p := {"name": paint_name, "primary": str(equipped["primary"]), "secondary": str(equipped["secondary"]),
		"accent": str(equipped["accent"]), "scheme": int(equipped.get("paint_scheme", 0)), "finish": int(equipped.get("paint_finish", 0))}
	var index := -1
	for k in list.size():
		if str(list[k]["name"]) == paint_name:
			index = k
	if index >= 0:
		list[index] = p
	elif list.size() >= MAX_CUSTOM_PAINTS:
		return -1
	else:
		list.append(p)
		index = list.size() - 1
	_store_custom_paints(list)
	changed.emit()
	return index


func delete_custom_paint(index: int) -> void:
	var list := custom_paints()
	if index < 0 or index >= list.size():
		return
	list.remove_at(index)
	_store_custom_paints(list)
	changed.emit()


## Aplica um padrão salvo (as 3 cores, o esquema e o acabamento).
func apply_custom_paint(index: int) -> void:
	var list := custom_paints()
	if index < 0 or index >= list.size():
		return
	var p: Dictionary = list[index]
	for f in ["primary", "secondary", "accent"]:
		equipped[f] = Color(str(p[f])).to_html(false)
	equipped["paint_scheme"] = int(p.get("scheme", 0))
	equipped["paint_finish"] = int(p.get("finish", 0))
	equipped["livery"] = _matching_livery()
	_commit()


## O carro está agora com este padrão salvo?
func is_custom_paint_on(p: Dictionary) -> bool:
	for f in ["primary", "secondary", "accent"]:
		if Color(str(p[f])).to_html(false) != str(equipped[f]):
			return false
	return int(p.get("scheme", 0)) == int(equipped.get("paint_scheme", 0)) 		and int(p.get("finish", 0)) == int(equipped.get("paint_finish", 0))


func _commit() -> void:
	_touch()
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
	var trail := str(equipped.get("trail", ""))
	equipped["trail"] = trail if ShopCatalog.item(trail).get("type", "") == "trail" and owns(trail) else ""
	var sig := str(equipped.get("signal", ""))
	equipped["signal"] = sig if ShopCatalog.item(sig).get("type", "") == "signal" and owns(sig) else ""
	# Decalques: só lugares/ids válidos, valores nos limites, e padrão só se a conta tiver
	var decals := CarDecals.sanitize(equipped.get("decals", {}))
	for slot in decals.keys():
		if not can_use_decal(str(decals[slot]["id"])):
			decals.erase(slot)
	equipped["decals"] = decals
	equipped["paint_finish"] = clampi(int(equipped.get("paint_finish", 0)), 0, CarConfig.PAINT_FINISHES.size() - 1)
	equipped["paint_scheme"] = clampi(int(equipped.get("paint_scheme", 0)), 0, CarConfig.PAINT_SCHEMES.size() - 1)
	equipped["rim_finish"] = clampi(int(equipped.get("rim_finish", 0)), 0, CarConfig.RIM_FINISHES.size() - 1)
	equipped["edited"] = maxf(float(equipped.get("edited", 0.0)), 0.0)
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
	_touch()
	save_profile()
	setup_changed.emit()
	if mode == "remote":
		equip_requested.emit(equipped.duplicate(true))


## Conta que já existia, salva antes do ajuste de engenharia: continua com o de fábrica (o padrão
## novo do jogador, CarSetup.PLAYER_DEFAULTS, é só para contas novas).
func _keep_old_setup(eq: Dictionary) -> void:
	if not eq.has("setup"):
		equipped["setup"] = {}


## Volta um parâmetro (ou todos, com key vazia) ao padrão (CarSetup.standard: o de fábrica, com o
## padrão do jogador na direção).
func reset_setup(key := "") -> void:
	var setup: Dictionary = equipped["setup"]
	if key == "":
		setup.clear()
		setup.merge(CarSetup.PLAYER_DEFAULTS)
	elif CarSetup.PLAYER_DEFAULTS.has(key):
		setup[key] = CarSetup.PLAYER_DEFAULTS[key]
	else:
		setup.erase(key)
	_touch()
	save_profile()
	setup_changed.emit()
	if mode == "remote":
		equip_requested.emit(equipped.duplicate(true))


func apply_setup(car: F1Car) -> void:
	if car:
		CarSetup.apply(car, equipped["setup"])


## Aplica o que está equipado na configuração de um carro (peças, cores, neon, boost, partículas).
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
	var trail := ShopCatalog.effect_of(str(equipped["trail"]))
	if config.trail != trail:
		config.trail = trail
	var sig := ShopCatalog.signal_of(str(equipped["signal"]))
	if config.pass_light != sig:
		config.pass_light = sig
	config.paint_finish = equipped["paint_finish"]
	config.paint_scheme = equipped["paint_scheme"]
	if var_to_str(config.decals) != var_to_str(equipped["decals"]):
		config.decals = (equipped["decals"] as Dictionary).duplicate(true)
	config.rim_finish = equipped["rim_finish"]
	if config.skin != str(equipped["skin"]):
		config.skin = str(equipped["skin"])
	if equipped["neon"] != "":
		config.neon_color = Color(equipped["neon"])
