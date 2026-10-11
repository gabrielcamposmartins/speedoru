class_name GameServer
extends Node
## Servidor dedicado (cena scenes/server/server.tscn; rodar com
## `godot --headless --path . -- --server`). Autoritativo em tudo que vale: contas, créditos,
## roletas, coleção, equipamento, engenharia, resultados, ranking e as corridas em rede.
##
## Banco: Turso / libSQL. Configuração (nessa ordem): argumentos --db-url= / --db-token=,
## variáveis de ambiente TURSO_DATABASE_URL / TURSO_AUTH_TOKEN, ou o arquivo server.cfg
## ([db] url, token) na pasta do projeto ou em user://. Porta: --port= (padrão 7350).
##
## Servidor aberto pelo próprio jogo (LocalHost, "Hospedar" na tela de multiplayer): --host-dir=
## troca o Turso por um arquivo nessa pasta (LocalStore) e liga o HostControl (estado e comandos
## por arquivos; --host-watch fecha junto com o jogo que o abriu).
##
## Regras de amigos, grupo, salas, ranking e perfil: documento "Pokeru — Regras de amigos, ranking
## e perfil", adaptadas para corridas (ver NetProtocol, Progression, Ranking).

var store: AccountStore
var db: TursoDB
var host_control: HostControl
var races: Node

## peer -> {account: Dictionary, profile: PlayerProfile, room: String, party: String}
var sessions := {}
## account_id -> Array[peer] (várias abas/instâncias da mesma conta)
var online := {}
## party_id -> {id, leader, members: Array[account_id], invited: {account_id: true}}
var parties := {}
## room_id -> ver _new_room()
var rooms := {}

var _ranking_cache := {}
var _ranking_time := -1000.0
var _rng := RandomNumberGenerator.new()
var _next_id := 1
var _ready_ok := false
## Peers saindo agora (não recebem mais nada).
var _gone := {}
## Skins (CarSkin): pasta das imagens, cache em memória (hash -> bytes) e quem espera cada uma.
var _skin_dir := ""
var _skin_cache := {}
var _skin_waiting := {}
const SKIN_CACHE_MAX := 64


func _ready() -> void:
	_rng.randomize()
	RaceTrack.server_mode = true
	var cfg := _config()
	races = Node.new()
	races.name = "Races"
	add_child(races)
	if cfg["host_dir"] != "":
		# Hospedado pelo jogo: banco num arquivo da pasta do host
		var local := LocalStore.new()
		local.name = "Store"
		local.setup_local(cfg["host_dir"])
		store = local
		add_child(store)
		print("Servidor: banco local %s" % local.path)
		if not await store.migrate():
			push_error("Servidor: banco local indisponível (%s)." % local.last_error)
			get_tree().quit(2)
			return
	else:
		db = TursoDB.new()
		db.name = "DB"
		add_child(db)
		db.configure(cfg["url"], cfg["token"])
		store = AccountStore.new()
		store.name = "Store"
		add_child(store)
		store.setup(db)
		print("Servidor: banco %s" % (db.url if db.url != "" else "(não configurado)"))
		if db.url == "" or not await store.migrate():
			push_error("Servidor: sem banco (%s). Configure TURSO_DATABASE_URL / TURSO_AUTH_TOKEN ou server.cfg." % db.last_error)
			get_tree().quit(2)
			return
	var err: Error = get_node("/root/Net").host(cfg["port"], self)
	if err != OK:
		push_error("Servidor: porta %d indisponível (%d)" % [cfg["port"], err])
		get_tree().quit(3)
		return
	_ready_ok = true
	print("Servidor: ouvindo na porta %d" % cfg["port"])
	_skin_dir = ProjectSettings.globalize_path(cfg["host_dir"].path_join("skins") if cfg["host_dir"] != "" else "user://server_skins")
	DirAccess.make_dir_recursive_absolute(_skin_dir)
	add_child(ServerStats.new())
	# Pistas do servidor geradas uma vez, em segundo plano (as salas que largarem antes esperam)
	var scenes := RaceSettings.TRACKS.map(func(t: Dictionary) -> String: return t["scene"])
	RaceTrack.prewarm_server(self, scenes)
	if cfg["host_dir"] != "":
		host_control = HostControl.new()
		host_control.name = "HostControl"
		host_control.setup(self, cfg["host_dir"], cfg["port"], cfg["watch"], cfg["session"])
		add_child(host_control)


func _config() -> Dictionary:
	var out := {"url": "", "token": "", "port": NetProtocol.DEFAULT_PORT, "host_dir": "", "watch": false, "session": ""}
	for path in ["res://server.cfg", "user://server.cfg"]:
		var c := ConfigFile.new()
		if c.load(path) == OK:
			out["url"] = str(c.get_value("db", "url", out["url"]))
			out["token"] = str(c.get_value("db", "token", out["token"]))
			out["port"] = int(c.get_value("server", "port", out["port"]))
	if OS.get_environment("TURSO_DATABASE_URL") != "":
		out["url"] = OS.get_environment("TURSO_DATABASE_URL")
	if OS.get_environment("TURSO_AUTH_TOKEN") != "":
		out["token"] = OS.get_environment("TURSO_AUTH_TOKEN")
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--db-url="):
			out["url"] = a.substr(9)
		elif a.begins_with("--db-token="):
			out["token"] = a.substr(11)
		elif a.begins_with("--port="):
			out["port"] = int(a.substr(7))
		elif a.begins_with("--host-dir="):
			out["host_dir"] = a.substr(11)
		elif a == "--host-watch":
			out["watch"] = true
		elif a.begins_with("--host-session="):
			out["session"] = a.substr(15)
	return out


# ---------------------------------------------------------------------------
# Skins (imagens pintadas pelos jogadores; CarSkin)
# ---------------------------------------------------------------------------
func _skin_path(h: String) -> String:
	return _skin_dir.path_join(h + ".webp")


func _skin_bytes(h: String) -> PackedByteArray:
	if _skin_cache.has(h):
		return _skin_cache[h]
	if not CarSkin.valid_hash(h) or not FileAccess.file_exists(_skin_path(h)):
		return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(_skin_path(h))
	_skin_remember(h, bytes)
	return bytes


func _skin_remember(h: String, bytes: PackedByteArray) -> void:
	if _skin_cache.size() >= SKIN_CACHE_MAX:
		_skin_cache.erase(_skin_cache.keys()[0])
	_skin_cache[h] = bytes


## A conta equipou uma skin que o servidor ainda não tem: pede a imagem ao jogo dela.
func _ask_skin(peer: int) -> void:
	var s := _session(peer)
	if s.is_empty():
		return
	var h := str(s["profile"].equipped.get("skin", ""))
	if CarSkin.valid_hash(h) and _skin_bytes(h).is_empty():
		print("Servidor: pedindo a skin %s… a %s" % [h.substr(0, 8), s["account"]["name"]])
		_send(peer, "skin_need", {"hash": h})


func _skin_get(peer: int, h: String) -> void:
	if not CarSkin.valid_hash(h):
		return
	var bytes := _skin_bytes(h)
	if not bytes.is_empty():
		_send(peer, "skin", {"hash": h, "data": bytes})
		return
	# Ainda não tem: guarda o pedido e chama quem está com ela equipada
	if not _skin_waiting.has(h):
		_skin_waiting[h] = []
	if not peer in _skin_waiting[h]:
		_skin_waiting[h].append(peer)
	for p: int in sessions:
		if str(sessions[p]["profile"].equipped.get("skin", "")) == h:
			_send(p, "skin_need", {"hash": h})
			break


## Imagem mandada pelo dono: só a skin equipada da conta, conferida (hash, tamanho, WebP).
func _skin_upload(peer: int, data: Dictionary) -> void:
	var h := str(data.get("hash", ""))
	var bytes: Variant = data.get("data")
	var s := _session(peer)
	if not bytes is PackedByteArray or str(s["profile"].equipped.get("skin", "")) != h:
		return
	if not CarSkin.check_net_bytes(h, bytes):
		_error(peer, data, "Skin inválida (imagem corrompida ou grande demais).")
		return
	if _skin_bytes(h).is_empty():
		var f := FileAccess.open(_skin_path(h), FileAccess.WRITE)
		if f:
			f.store_buffer(bytes)
			f.close()
		_skin_remember(h, bytes)
		print("Servidor: skin %s… recebida de %s (%d KB)" % [h.substr(0, 8), s["account"]["name"], bytes.size() / 1024])
	for p: int in _skin_waiting.get(h, []):
		if sessions.has(p):
			_send(p, "skin", {"hash": h, "data": bytes})
	_skin_waiting.erase(h)


# ---------------------------------------------------------------------------
# Controle do host (HostControl)
# ---------------------------------------------------------------------------
## Quem está no servidor agora: [{id, name, room, racing}].
func players_online() -> Array:
	var out := []
	for acc_id: String in online:
		var peers: Array = online[acc_id]
		if peers.is_empty() or not sessions.has(peers[0]):
			continue
		var s: Dictionary = sessions[peers[0]]
		var room: Dictionary = rooms.get(s["room"], {})
		out.append({"id": acc_id, "name": s["account"]["name"], "room": str(room.get("name", "")),
			"racing": not room.is_empty() and room.get("state", "lobby") != "lobby"})
	return out


func room_counts() -> Vector2i:
	var racing := 0
	for r: Dictionary in rooms.values():
		if r.get("state", "lobby") != "lobby":
			racing += 1
	return Vector2i(rooms.size(), racing)


## Tira a conta do servidor (todas as abas). O jogo dela não reconecta sozinho.
func kick_account(account_id: String) -> bool:
	var peers: Array = online.get(account_id, []).duplicate()
	for p in peers:
		_send(p, "kicked", {"error": "O anfitrião tirou você do servidor."})
	if peers.is_empty():
		return false
	await get_tree().create_timer(0.3).timeout
	for p in peers:
		get_node("/root/Net").kick(p)
	return true


func _exit_tree() -> void:
	RaceTrack.clear_server_cache()


## Fecha o servidor gravando tudo (comando "stop" do host ou o jogo que o abriu fechou).
func shutdown(code := 0) -> void:
	print("Servidor: fechando")
	_ready_ok = false
	var local := store as LocalStore
	if local:
		local.flush()
	var net := get_node("/root/Net")
	if net.multiplayer.multiplayer_peer:
		net.multiplayer.multiplayer_peer.close()
	get_tree().quit(code)


func _id(prefix: String) -> String:
	_next_id += 1
	return "%s%d%04d" % [prefix, _next_id, _rng.randi_range(0, 9999)]


func _send(peer: int, type: String, data: Dictionary = {}) -> void:
	if not _gone.has(peer):
		get_node("/root/Net").send(peer, type, data)


## Manda para todas as abas de uma conta.
func _send_account(account_id: String, type: String, data: Dictionary = {}) -> void:
	for p in online.get(account_id, []):
		_send(p, type, data)


func _reply(peer: int, data: Dictionary, type: String, payload: Dictionary) -> void:
	if data.has("req"):
		payload["req"] = data["req"]
	_send(peer, type, payload)


func _error(peer: int, data: Dictionary, text: String) -> void:
	_reply(peer, data, "error", {"ok": false, "error": text})


func _ok(peer: int, data: Dictionary, extra := {}) -> void:
	var payload := {"ok": true}
	payload.merge(extra)
	_reply(peer, data, "ok", payload)


# ---------------------------------------------------------------------------
# Conexões
# ---------------------------------------------------------------------------
func on_peer_connected(_peer: int) -> void:
	pass


func on_peer_disconnected(peer: int) -> void:
	if not sessions.has(peer):
		return
	var s: Dictionary = sessions[peer]
	var acc_id: String = s["account"]["id"]
	_gone[peer] = true
	_leave_room(peer)
	sessions.erase(peer)
	var peers: Array = online.get(acc_id, [])
	peers.erase(peer)
	if peers.is_empty():
		online.erase(acc_id)
		# Saiu de vez: deixa o grupo (o grupo se desfaz se era o líder ou se sobra um)
		_party_remove(acc_id)
		await _broadcast_presence(acc_id)
	if is_instance_valid(s["profile"]):
		s["profile"].free()
	_gone.erase(peer)


func is_online(acc_id: String) -> bool:
	return online.has(acc_id)


func in_race(acc_id: String) -> bool:
	for p in online.get(acc_id, []):
		var room_id: String = sessions[p]["room"]
		if room_id != "" and rooms.has(room_id) and rooms[room_id]["state"] == "racing":
			return true
	return false


func _session(peer: int) -> Dictionary:
	return sessions.get(peer, {})


# ---------------------------------------------------------------------------
# Mensagens
# ---------------------------------------------------------------------------
func on_message(peer: int, type: String, data: Dictionary) -> void:
	if not _ready_ok:
		return
	if type == "hello":
		await _hello(peer, data)
		return
	if not sessions.has(peer):
		_error(peer, data, "Faça login primeiro.")
		return
	match type:
		"set_name":
			await _set_name(peer, data)
		"set_title":
			await _set_title(peer, data)
		"spin":
			await _spin(peer, data)
		"equip":
			await _equip(peer, data)
		"solo_result":
			await _solo_result(peer, data)
		"friends":
			await _send_friends(peer, data)
		"friend_add":
			await _friend_add(peer, data, NetProtocol.normalize_code(str(data.get("code", ""))), "")
		"friend_add_player":
			await _friend_add(peer, data, "", str(data.get("id", "")))
		"friend_accept":
			await _friend_accept(peer, data)
		"friend_decline":
			await _friend_decline(peer, data)
		"friend_remove":
			await _friend_remove(peer, data)
		"party_invite":
			_party_invite(peer, data)
		"party_accept":
			_party_accept(peer, data)
		"party_decline":
			_party_decline(peer, data)
		"party_leave":
			_party_remove(_session(peer)["account"]["id"])
			_ok(peer, data)
		"party_start":
			_party_start(peer, data)
		"rooms":
			_reply(peer, data, "rooms", {"rooms": _room_list()})
		"room_create":
			_room_create(peer, data)
		"room_join":
			_room_join(peer, data, str(data.get("id", "")), str(data.get("password", "")), false)
		"room_quick":
			_room_quick(peer, data)
		"room_leave":
			_leave_room(peer)
			_ok(peer, data)
		"room_ready":
			_room_ready(peer, data)
		"room_settings":
			_room_settings(peer, data)
		"room_start":
			_room_start(peer, data)
		"room_invite":
			_room_invite(peer, data)
		"profile_of":
			await _profile_of(peer, data)
		"ranking":
			await _ranking(peer, data)
		"race_cmd":
			_race_cmd(peer, data)
		"skin_get":
			_skin_get(peer, str(data.get("hash", "")))
		"skin_upload":
			_skin_upload(peer, data)
		_:
			_error(peer, data, "Mensagem desconhecida: %s" % type)


func on_input(peer: int, data: PackedFloat32Array) -> void:
	var s := _session(peer)
	if s.is_empty() or s["room"] == "" or not rooms.has(s["room"]):
		return
	var session: Variant = rooms[s["room"]].get("session")
	if session:
		session.set_input(s["account"]["id"], data)


func _race_cmd(peer: int, data: Dictionary) -> void:
	var s := _session(peer)
	if s["room"] == "" or not rooms.has(s["room"]):
		return
	var session: Variant = rooms[s["room"]].get("session")
	if session:
		session.command(s["account"]["id"], str(data.get("cmd", "")), data)


# ---------------------------------------------------------------------------
# Conta
# ---------------------------------------------------------------------------
func _hello(peer: int, data: Dictionary) -> void:
	if int(data.get("version", 0)) != NetProtocol.VERSION:
		_send(peer, "error", {"ok": false, "error": "Versão do jogo diferente da do servidor. Atualize o jogo."})
		return
	var token := str(data.get("token", ""))
	if token.length() < 16:
		_send(peer, "error", {"ok": false, "error": "Token inválido."})
		return
	var acc: Variant = await store.login(token, str(data.get("name", "Jogador")))
	if acc == null:
		_send(peer, "error", {"ok": false, "error": "Banco indisponível, tente de novo."})
		return
	var profile := PlayerProfile.new()
	profile.mode = "server"
	profile.from_dict(acc["profile"])
	# O carro do aparelho (skins, peças, engenharia) vale neste servidor.
	# PENDENTE (produção): validar que a conta tem as skins e peças (TRUST_CLIENT_CAR = false).
	var car: Variant = data.get("car")
	if NetProtocol.TRUST_CLIENT_CAR and car is Dictionary:
		profile.equipped = PlayerProfile.sanitize_equipped(car)
		acc["profile"] = profile.to_dict()
		await store.save_account(acc)
	sessions[peer] = {"account": acc, "profile": profile, "room": "", "party": ""}
	var was_online := online.has(acc["id"])
	if not was_online:
		online[acc["id"]] = []
	online[acc["id"]].append(peer)
	_send(peer, "welcome", {"account": _account_payload(sessions[peer])})
	_ask_skin(peer)
	if not was_online:
		await _broadcast_presence(acc["id"], true)


## Tudo que o próprio dono vê da conta.
func _account_payload(s: Dictionary) -> Dictionary:
	var acc: Dictionary = s["account"]
	var counters: Dictionary = acc["counters"].duplicate()
	counters["items"] = ShopCatalog.count_collectible(s["profile"].owned.keys())
	var prog := Progression.level_progress(counters)
	return {
		"id": acc["id"], "name": acc["name"], "code": NetProtocol.format_code(acc["friend_code"]),
		"title": acc["title"], "titles": Progression.unlocked_titles(counters),
		"level": Progression.level_of(counters), "xp": prog.x, "xp_next": prog.y,
		"counters": counters, "best_lap": acc["best_lap"], "profile": s["profile"].to_dict(),
		"trust_car": NetProtocol.TRUST_CLIENT_CAR,
	}


## Salva a conta e manda o estado novo para todas as abas dela.
func _commit_account(peer: int) -> void:
	var s := _session(peer)
	var acc: Dictionary = s["account"]
	acc["profile"] = s["profile"].to_dict()
	await store.save_account(acc)
	# Abas da mesma conta compartilham os dados: atualiza todas
	for p in online.get(acc["id"], []):
		if p != peer and sessions.has(p):
			sessions[p]["account"] = acc
			sessions[p]["profile"].from_dict(acc["profile"])
		_send(p, "account", {"account": _account_payload(sessions[p])})


func _set_name(peer: int, data: Dictionary) -> void:
	var s := _session(peer)
	s["account"]["name"] = NetProtocol.clean_name(str(data.get("name", "")))
	await _commit_account(peer)
	_ok(peer, data, {"name": s["account"]["name"]})


func _set_title(peer: int, data: Dictionary) -> void:
	var s := _session(peer)
	var title := str(data.get("title", ""))
	var counters: Dictionary = s["account"]["counters"].duplicate()
	counters["items"] = ShopCatalog.count_collectible(s["profile"].owned.keys())
	# O servidor recusa um título que as conquistas da conta não sustentam
	if title != "" and not title in Progression.unlocked_titles(counters):
		_error(peer, data, "Você ainda não conquistou esse título.")
		return
	s["account"]["title"] = title
	await _commit_account(peer)
	_ok(peer, data)


func _spin(peer: int, data: Dictionary) -> void:
	var s := _session(peer)
	var res: Dictionary = s["profile"].spin(str(data.get("roulette", "")))
	if res["ok"]:
		s["account"]["counters"]["spins"] = int(s["account"]["counters"].get("spins", 0)) + 1
		if res["refund"] > 0:
			s["account"]["counters"]["earned"] = int(s["account"]["counters"].get("earned", 0)) + int(res["refund"])
		await _commit_account(peer)
	_reply(peer, data, "spun", res)


func _equip(peer: int, data: Dictionary) -> void:
	var s := _session(peer)
	var eq: Variant = data.get("equipped")
	if not eq is Dictionary:
		return
	if NetProtocol.TRUST_CLIENT_CAR:
		# PENDENTE (produção): validar a posse em vez de aceitar o carro do aparelho
		s["profile"].equipped = PlayerProfile.sanitize_equipped(eq)
	else:
		# Só o que a conta tem (clamp_equipped volta o resto para o gratuito)
		s["profile"].apply_requested_equipped(eq)
	_ask_skin(peer)
	await _commit_account(peer)


## Resultado de corrida solo contra bots (simulada no cliente): o servidor confere se é plausível
## e calcula os créditos e contadores ele mesmo.
func _solo_result(peer: int, data: Dictionary) -> void:
	var s := _session(peer)
	var laps := clampi(int(data.get("laps", 0)), 0, 20)
	var laps_total := clampi(int(data.get("laps_total", 0)), 1, 20)
	var difficulty := clampi(int(data.get("difficulty", 1)), 0, 3)
	var race_time := float(data.get("race_time", 0.0))
	var best := float(data.get("best_lap", 0.0))
	var finished := bool(data.get("finished", false))
	var track := RaceSettings.valid_track(str(data.get("track", "monza")))
	var min_lap := NetProtocol.min_lap(track)
	var counters: Dictionary = s["account"]["counters"]
	var problems := []
	if laps > laps_total:
		problems.append("voltas demais")
	if laps > 0 and race_time < laps * min_lap:
		problems.append("tempo de corrida impossível")
	if best > 0.0 and best < min_lap:
		problems.append("volta impossível")
	var cc := counters.duplicate()
	cc["items"] = ShopCatalog.count_collectible(s["profile"].owned.keys())
	if not Progression.tier_unlocked(difficulty, Progression.level_of(cc)):
		problems.append("dificuldade bloqueada para o seu nível")
	if not problems.is_empty():
		_error(peer, data, "Resultado recusado: " + ", ".join(problems))
		return
	var record := {
		"pos": int(data.get("pos", 0)), "total": int(data.get("total", 1)), "grid": int(data.get("grid", 0)),
		"finished": finished, "penalty": float(data.get("penalty", 0.0)), "best_lap": best,
		"consistency": Progression.consistency_of(data.get("lap_times", [])), "laps": laps, "track": track,
	}
	var reward := await _apply_result(peer, record, difficulty, bool(data.get("dsq", false)), bool(data.get("fastest", false)), "solo")
	_ok(peer, data, {"reward": reward})


## Contadores, créditos, histórico e recorde de uma corrida terminada (solo ou online).
func _apply_result(peer: int, record: Dictionary, difficulty: int, dsq: bool, fastest: bool, kind: String) -> int:
	var s := _session(peer)
	var acc: Dictionary = s["account"]
	var c: Dictionary = acc["counters"]
	var level_before := Progression.level_of(c)
	var laps := int(record.get("laps", 0))
	var reward: int = s["profile"].award_race(laps, difficulty, record["finished"], dsq)
	c["laps"] = int(c.get("laps", 0)) + laps
	c["earned"] = int(c.get("earned", 0)) + reward
	if record["finished"] and not dsq:
		c["races"] = int(c.get("races", 0)) + 1
		if int(record["pos"]) == 1:
			c["wins"] = int(c.get("wins", 0)) + 1
		if int(record["pos"]) <= 3:
			c["podiums"] = int(c.get("podiums", 0)) + 1
		if float(record["penalty"]) <= 0.0:
			c["clean_races"] = int(c.get("clean_races", 0)) + 1
	if fastest:
		c["fastest_laps"] = int(c.get("fastest_laps", 0)) + 1
	if kind == "online":
		c["online_races"] = int(c.get("online_races", 0)) + 1
	var best := float(record.get("best_lap", 0.0))
	var track := RaceSettings.valid_track(str(record.get("track", "monza")))
	if track == "monza":
		# O recorde da conta (ranking) é o de Monza
		if best >= NetProtocol.MIN_PLAUSIBLE_LAP and (acc["best_lap"] <= 0.0 or best < acc["best_lap"]):
			acc["best_lap"] = best
			_ranking_time = -1000.0  # recorde novo derruba o cache do ranking
	elif best >= NetProtocol.min_lap(track):
		var key := "best_lap_" + track
		if float(c.get(key, 0.0)) <= 0.0 or best < float(c.get(key, 0.0)):
			c[key] = best
	record["credits"] = reward
	await store.add_match(acc["id"], kind, record)
	await _commit_account(peer)
	var level_after := Progression.level_of(c)
	if level_after > level_before:
		var unlocked := []
		for d in 4:
			if not Progression.tier_unlocked(d, level_before) and Progression.tier_unlocked(d, level_after):
				unlocked.append(["Fácil", "Médio", "Difícil", "Mista"][d])
		_send(peer, "level_up", {"level": level_after, "unlocked": unlocked})
	return reward


# ---------------------------------------------------------------------------
# Amigos
# ---------------------------------------------------------------------------
func _friend_entry(info: Dictionary) -> Dictionary:
	var e := info.duplicate()
	e["online"] = is_online(info["id"])
	e["in_race"] = in_race(info["id"])
	return e


func _send_friends(peer: int, data := {}) -> void:
	var me: String = _session(peer)["account"]["id"]
	var friends: Array = await store.friends_of(me)
	var incoming: Array = await store.requests_to(me)
	var outgoing: Array = await store.requests_from(me)
	var info: Dictionary = await store.summaries(friends + incoming + outgoing)
	var payload := {
		"friends": friends.filter(func(i): return info.has(i)).map(func(i): return _friend_entry(info[i])),
		"incoming": incoming.filter(func(i): return info.has(i)).map(func(i): return info[i]),
		"outgoing": outgoing.filter(func(i): return info.has(i)).map(func(i): return info[i]),
	}
	_reply(peer, data, "friends", payload)


## Pedido de amizade por código (ou pelo jogador na mesma sala).
func _friend_add(peer: int, data: Dictionary, code: String, target_id: String) -> void:
	var me: Dictionary = _session(peer)["account"]
	var target: Variant = null
	if target_id != "":
		# Pedir na mesa: só quem está na mesma sala
		var room_id: String = _session(peer)["room"]
		if room_id == "" or not rooms.has(room_id) or not target_id in rooms[room_id]["members"]:
			_error(peer, data, "Esse jogador não está na sua sala.")
			return
		target = await store.get_account(target_id)
	elif code == "":
		_error(peer, data, "Código inválido.")
		return
	else:
		target = await store.find_by_code(code)
	if target == null:
		_error(peer, data, "Nenhum jogador com esse código.")
		return
	var other: String = target["id"]
	if other == me["id"]:
		_error(peer, data, "Esse código é o seu.")
		return
	if await store.are_friends(me["id"], other):
		_error(peer, data, "Vocês já são amigos.")
		return
	if await store.has_request(me["id"], other):
		_error(peer, data, "O pedido já está esperando.")
		return
	if await store.count_friends(me["id"]) >= NetProtocol.MAX_FRIENDS or await store.count_friends(other) >= NetProtocol.MAX_FRIENDS:
		_error(peer, data, "Limite de %d amigos atingido." % NetProtocol.MAX_FRIENDS)
		return
	# Pedido cruzado: viram amigos na hora
	if await store.has_request(other, me["id"]):
		await store.make_friends(me["id"], other)
		_ok(peer, data, {"friends_now": true})
		await _refresh_friends(me["id"])
		await _refresh_friends(other)
		return
	if await store.count_requests_to(other) >= NetProtocol.MAX_REQUESTS:
		_error(peer, data, "A caixa de pedidos está cheia.")
		return
	await store.add_request(me["id"], other)
	_ok(peer, data)
	_send_account(other, "friend_request", {"id": me["id"], "name": me["name"]})
	await _refresh_friends(me["id"])
	await _refresh_friends(other)


func _friend_accept(peer: int, data: Dictionary) -> void:
	var me: String = _session(peer)["account"]["id"]
	var other := str(data.get("id", ""))
	if not await store.has_request(other, me):
		_error(peer, data, "Esse pedido não existe mais.")
		return
	if await store.count_friends(me) >= NetProtocol.MAX_FRIENDS or await store.count_friends(other) >= NetProtocol.MAX_FRIENDS:
		_error(peer, data, "Limite de %d amigos atingido." % NetProtocol.MAX_FRIENDS)
		return
	await store.make_friends(me, other)
	_ok(peer, data)
	await _refresh_friends(me)
	await _refresh_friends(other)


func _friend_decline(peer: int, data: Dictionary) -> void:
	var me: String = _session(peer)["account"]["id"]
	var other := str(data.get("id", ""))
	await store.clear_requests(me, other)
	_ok(peer, data)
	await _refresh_friends(me)
	await _refresh_friends(other)


## Desfazer amizade: remove dos dois lados, sem aviso ao outro (a lista dele só se atualiza).
func _friend_remove(peer: int, data: Dictionary) -> void:
	var me: String = _session(peer)["account"]["id"]
	var other := str(data.get("id", ""))
	await store.remove_friend(me, other)
	_ok(peer, data)
	await _refresh_friends(me)
	await _refresh_friends(other)


func _refresh_friends(acc_id: String) -> void:
	for p in online.get(acc_id, []):
		await _send_friends(p)


## Presença: avisa os amigos (friend_online ao entrar) e atualiza as listas.
func _broadcast_presence(acc_id: String, came_online := false) -> void:
	var friends: Array = await store.friends_of(acc_id)
	var name := ""
	if came_online and online.has(acc_id):
		name = sessions[online[acc_id][0]]["account"]["name"]
	for f in friends:
		if not online.has(f):
			continue
		if came_online:
			_send_account(f, "friend_online", {"id": acc_id, "name": name})
		await _refresh_friends(f)


# ---------------------------------------------------------------------------
# Grupo (até 4; só o líder convida; só amigos online que não estão em outro grupo)
# ---------------------------------------------------------------------------
func _party_of(acc_id: String) -> String:
	for pid in parties:
		if acc_id in parties[pid]["members"]:
			return pid
	return ""


func _party_payload(pid: String) -> Dictionary:
	if not parties.has(pid):
		return {}
	var p: Dictionary = parties[pid]
	var members := []
	for m in p["members"]:
		var s: Dictionary = sessions[online[m][0]] if online.has(m) else {}
		var counters: Dictionary = s["account"]["counters"] if not s.is_empty() else {}
		members.append({"id": m, "name": s["account"]["name"] if not s.is_empty() else "?", "level": Progression.level_of(counters),
			"leader": m == p["leader"]})
	return {"id": pid, "leader": p["leader"], "members": members}


func _push_party(pid: String) -> void:
	if not parties.has(pid):
		return
	var payload := _party_payload(pid)
	for m in parties[pid]["members"]:
		_send_account(m, "party", {"party": payload})


func _party_invite(peer: int, data: Dictionary) -> void:
	var me: String = _session(peer)["account"]["id"]
	var other := str(data.get("id", ""))
	var pid := _party_of(me)
	if pid != "" and parties[pid]["leader"] != me:
		_error(peer, data, "Só o líder convida para o grupo.")
		return
	if not is_online(other):
		_error(peer, data, "Só dá para chamar amigos online.")
		return
	if not await store.are_friends(me, other):
		_error(peer, data, "Só dá para chamar amigos.")
		return
	if _party_of(other) != "":
		_error(peer, data, "Esse amigo já está em outro grupo.")
		return
	if pid == "":
		pid = _id("p")
		parties[pid] = {"id": pid, "leader": me, "members": [me], "invited": {}}
		_push_party(pid)
	if parties[pid]["members"].size() + parties[pid]["invited"].size() >= NetProtocol.MAX_PARTY:
		_error(peer, data, "O grupo já tem %d pessoas." % NetProtocol.MAX_PARTY)
		return
	parties[pid]["invited"][other] = true
	_send_account(other, "party_ask", {"party": pid, "from": me, "name": _session(peer)["account"]["name"]})
	_ok(peer, data)


func _party_accept(peer: int, data: Dictionary) -> void:
	var me: String = _session(peer)["account"]["id"]
	var pid := str(data.get("party", ""))
	if not parties.has(pid) or not parties[pid]["invited"].has(me):
		_error(peer, data, "Esse convite não vale mais.")
		return
	if _party_of(me) != "":
		_error(peer, data, "Saia do seu grupo antes.")
		return
	parties[pid]["invited"].erase(me)
	parties[pid]["members"].append(me)
	_ok(peer, data)
	_push_party(pid)


func _party_decline(peer: int, data: Dictionary) -> void:
	var me: String = _session(peer)["account"]["id"]
	var pid := str(data.get("party", ""))
	if parties.has(pid):
		parties[pid]["invited"].erase(me)
		_dissolve_if_alone(pid)
	_ok(peer, data)


## Sai do grupo. Se o líder sai, o grupo se desfaz; se sobra só uma pessoa, também.
func _party_remove(acc_id: String) -> void:
	var pid := _party_of(acc_id)
	if pid == "":
		return
	var p: Dictionary = parties[pid]
	p["members"].erase(acc_id)
	_send_account(acc_id, "party", {"party": {}})
	if p["leader"] == acc_id or p["members"].size() <= 1:
		for m in p["members"]:
			_send_account(m, "party", {"party": {}})
			_send_account(m, "notice", {"text": "O grupo se desfez."})
		parties.erase(pid)
	else:
		_push_party(pid)


func _dissolve_if_alone(pid: String) -> void:
	if parties.has(pid) and parties[pid]["members"].size() <= 1 and parties[pid]["invited"].is_empty():
		for m in parties[pid]["members"]:
			_send_account(m, "party", {"party": {}})
		parties.erase(pid)


## O líder escolhe como jogar: contra bots (o grupo e bots), fila (o grupo entra junto numa sala
## aberta) ou Custom (a sala criada pelo líder puxa o grupo).
func _party_start(peer: int, data: Dictionary) -> void:
	var me: String = _session(peer)["account"]["id"]
	var pid := _party_of(me)
	if pid == "" or parties[pid]["leader"] != me:
		_error(peer, data, "Só o líder do grupo escolhe a partida.")
		return
	var kind := str(data.get("kind", "bots"))
	var room_id := ""
	match kind:
		"bots":
			room_id = _room_create(peer, {"kind": "bots", "name": "Grupo de %s" % _session(peer)["account"]["name"]}, true)
		"queue":
			room_id = _find_queue_room(parties[pid]["members"].size())
			if room_id == "":
				room_id = _room_create(peer, {"kind": "queue", "name": "Corrida rápida"}, true)
			else:
				_room_join(peer, {}, room_id, "", true)
		_:
			room_id = _session(peer)["room"]
			if room_id == "":
				room_id = _room_create(peer, {"kind": "custom", "name": "Sala de %s" % _session(peer)["account"]["name"]}, true)
	if room_id == "":
		_error(peer, data, "Não foi possível criar a sala.")
		return
	# Puxa o grupo (quem já está numa corrida fica de fora)
	for m in parties[pid]["members"]:
		if m == me or in_race(m) or not online.has(m):
			continue
		_room_join(online[m][0], {}, room_id, "", true)
	_ok(peer, data, {"room": room_id})


# ---------------------------------------------------------------------------
# Salas
# ---------------------------------------------------------------------------
func _new_room(kind: String, name: String, host_id: String) -> Dictionary:
	return {
		"id": _id("r"), "kind": kind, "name": name.substr(0, 24), "host": host_id, "password": "",
		"members": [], "ready": {}, "state": "lobby", "session": null, "invited": {},
		"settings": {"track": "monza", "laps": 5, "difficulty": 1, "bots": true, "cars": NetProtocol.MAX_ROOM_PLAYERS, "quali_laps": 0, "quali_collisions": true, "quali_time": 0, "quali_strict": true, "drs": 0, "time_of_day": 0, "biome": 0, "max": NetProtocol.MAX_ROOM_PLAYERS},
	}


func _room_payload(room: Dictionary) -> Dictionary:
	var members := []
	for m in room["members"]:
		var s: Dictionary = sessions[online[m][0]] if online.has(m) else {}
		if s.is_empty():
			continue
		members.append({"id": m, "name": s["account"]["name"], "title": s["account"]["title"],
			"level": Progression.level_of(s["account"]["counters"]), "ready": room["ready"].get(m, false), "host": m == room["host"]})
	return {"id": room["id"], "kind": room["kind"], "name": room["name"], "host": room["host"],
		"locked": room["password"] != "", "state": room["state"], "settings": room["settings"], "members": members}


func _push_room(room_id: String) -> void:
	if not rooms.has(room_id):
		return
	var payload := _room_payload(rooms[room_id])
	for m in rooms[room_id]["members"]:
		_send_account(m, "room", {"room": payload})


func _room_list() -> Array:
	var out := []
	for id in rooms:
		var r: Dictionary = rooms[id]
		if r["kind"] == "custom" and r["state"] == "lobby":
			out.append(_room_payload(r))
	return out


func _apply_room_settings(room: Dictionary, data: Dictionary) -> void:
	var st: Dictionary = room["settings"]
	if data.has("laps"):
		st["laps"] = int(data["laps"]) if int(data["laps"]) in NetProtocol.ROOM_LAPS else st["laps"]
	if data.has("difficulty"):
		st["difficulty"] = clampi(int(data["difficulty"]), 0, 3)
	if data.has("bots"):
		st["bots"] = bool(data["bots"])
	if data.has("drs"):
		st["drs"] = clampi(int(data["drs"]), 0, 1)
	if data.has("track"):
		st["track"] = RaceSettings.valid_track(str(data["track"]))
	if data.has("quali_laps"):
		st["quali_laps"] = clampi(int(data["quali_laps"]), 0, RaceSettings.QUALI_FREE)
	if data.has("quali_collisions"):
		st["quali_collisions"] = bool(data["quali_collisions"])
	if data.has("quali_time"):
		st["quali_time"] = clampi(int(data["quali_time"]), 0, RaceSettings.QUALI_TIMES.size() - 1)
	if data.has("quali_strict"):
		st["quali_strict"] = bool(data["quali_strict"])
	if data.has("cars") and room["kind"] == "custom":
		# Total do grid; a sala aceita até esse número de jogadores (nunca menos que os que já estão)
		var members: int = (room["members"] as Array).size()
		st["cars"] = clampi(int(data["cars"]), maxi(2, members), NetProtocol.MAX_GRID)
		st["max"] = clampi(int(st["cars"]), members, NetProtocol.MAX_ROOM_PLAYERS)
	if data.has("time_of_day"):
		st["time_of_day"] = clampi(int(data["time_of_day"]), 0, 2)
	if data.has("biome"):
		st["biome"] = clampi(int(data["biome"]), 0, 3)
	if data.has("name"):
		room["name"] = str(data["name"]).strip_edges().substr(0, 24)
	if data.has("password"):
		room["password"] = str(data["password"]).substr(0, 24)


## Cria a sala e coloca quem criou dentro. Devolve o id ("" se falhou).
func _room_create(peer: int, data: Dictionary, quiet := false) -> String:
	var s := _session(peer)
	_leave_room(peer)
	var kind := str(data.get("kind", "custom"))
	if not kind in ["custom", "queue", "bots"]:
		kind = "custom"
	var room := _new_room(kind, str(data.get("name", "Sala de %s" % s["account"]["name"])), s["account"]["id"])
	_apply_room_settings(room, data)
	if kind == "bots":
		room["settings"]["bots"] = true
	rooms[room["id"]] = room
	room["members"].append(s["account"]["id"])
	s["room"] = room["id"]
	_push_room(room["id"])
	if not quiet:
		_ok(peer, data, {"room": room["id"]})
	return room["id"]


func _room_join(peer: int, data: Dictionary, room_id: String, password: String, forced: bool) -> void:
	var s := _session(peer)
	if not rooms.has(room_id):
		if not forced:
			_error(peer, data, "Essa sala não existe mais.")
		return
	var room: Dictionary = rooms[room_id]
	var me: String = s["account"]["id"]
	if room["state"] != "lobby":
		if not forced:
			_error(peer, data, "A corrida dessa sala já começou.")
		return
	if room["members"].size() >= int(room["settings"]["max"]):
		if not forced:
			_error(peer, data, "A sala está cheia.")
		return
	# Convidado entra mesmo que a sala tenha senha
	if not forced and room["password"] != "" and password != room["password"] and not room["invited"].has(me):
		_error(peer, data, "Senha errada.")
		return
	if s["room"] == room_id:
		if not forced:
			_ok(peer, data, {"room": room_id})
		return
	_leave_room(peer)
	room["members"].append(me)
	room["invited"].erase(me)
	s["room"] = room_id
	_push_room(room_id)
	if not forced:
		_ok(peer, data, {"room": room_id})


## Fila: entra numa sala de corrida rápida aberta com lugar; senão cria uma.
func _room_quick(peer: int, data: Dictionary) -> void:
	var room_id := _find_queue_room(1)
	if room_id == "":
		room_id = _room_create(peer, {"kind": "queue", "name": "Corrida rápida"}, true)
		_ok(peer, data, {"room": room_id})
	else:
		_room_join(peer, data, room_id, "", false)


func _find_queue_room(seats: int) -> String:
	for id in rooms:
		var r: Dictionary = rooms[id]
		if r["kind"] == "queue" and r["state"] == "lobby" and r["members"].size() + seats <= int(r["settings"]["max"]):
			return id
	return ""


func _leave_room(peer: int) -> void:
	var s := _session(peer)
	if s.is_empty() or s["room"] == "" or not rooms.has(s["room"]):
		if not s.is_empty():
			s["room"] = ""
		return
	var room: Dictionary = rooms[s["room"]]
	var me: String = s["account"]["id"]
	s["room"] = ""
	# Outras abas da mesma conta continuam na sala; só sai quando nenhuma está
	for p in online.get(me, []):
		if p != peer and sessions[p]["room"] == room["id"]:
			return
	room["members"].erase(me)
	room["ready"].erase(me)
	if room["session"]:
		room["session"].player_left(me)
	_send(peer, "room", {"room": {}})
	if room["members"].is_empty():
		if room["session"]:
			room["session"].stop()
		rooms.erase(room["id"])
		return
	if room["host"] == me:
		room["host"] = room["members"][0]
	_push_room(room["id"])


func _room_ready(peer: int, data: Dictionary) -> void:
	var s := _session(peer)
	if s["room"] == "" or not rooms.has(s["room"]):
		return
	rooms[s["room"]]["ready"][s["account"]["id"]] = bool(data.get("ready", true))
	_push_room(s["room"])
	_maybe_autostart(s["room"])


func _room_settings(peer: int, data: Dictionary) -> void:
	var s := _session(peer)
	if s["room"] == "" or not rooms.has(s["room"]):
		return
	var room: Dictionary = rooms[s["room"]]
	if room["host"] != s["account"]["id"] or room["kind"] == "queue" or room["state"] != "lobby":
		_error(peer, data, "Só o anfitrião muda a sala.")
		return
	_apply_room_settings(room, data)
	_push_room(room["id"])
	_ok(peer, data)


## Convite para sala Custom: qualquer pessoa sentada pode chamar um amigo online.
func _room_invite(peer: int, data: Dictionary) -> void:
	var s := _session(peer)
	var other := str(data.get("id", ""))
	if s["room"] == "" or not rooms.has(s["room"]):
		_error(peer, data, "Você não está numa sala.")
		return
	var room: Dictionary = rooms[s["room"]]
	if room["kind"] != "custom" or room["state"] != "lobby":
		_error(peer, data, "Só dá para convidar para salas Custom antes da largada.")
		return
	if not is_online(other) or not await store.are_friends(s["account"]["id"], other):
		_error(peer, data, "Só dá para chamar amigos online.")
		return
	room["invited"][other] = true
	_send_account(other, "room_ask", {"room": room["id"], "from": s["account"]["id"], "name": s["account"]["name"], "room_name": room["name"]})
	_ok(peer, data)


## Fila: começa sozinha quando todos marcam "pronto" (mínimo 1).
func _maybe_autostart(room_id: String) -> void:
	var room: Dictionary = rooms[room_id]
	if room["kind"] != "queue" or room["state"] != "lobby":
		return
	for m in room["members"]:
		if not room["ready"].get(m, false):
			return
	_start_race(room_id)


func _room_start(peer: int, data: Dictionary) -> void:
	var s := _session(peer)
	if s["room"] == "" or not rooms.has(s["room"]):
		return
	var room: Dictionary = rooms[s["room"]]
	if room["host"] != s["account"]["id"]:
		_error(peer, data, "Só o anfitrião larga a corrida.")
		return
	if room["state"] != "lobby":
		return
	_ok(peer, data)
	_start_race(room["id"])


func _start_race(room_id: String) -> void:
	var room: Dictionary = rooms[room_id]
	room["state"] = "racing"
	var players := []
	for m in room["members"]:
		if not online.has(m):
			continue
		var s: Dictionary = sessions[online[m][0]]
		var pd: Dictionary = s["profile"].to_dict()
		if NetProtocol.TRUST_CLIENT_CAR:
			# Carro aceito do aparelho: na pista todos os itens valem (senão o perfil os trocaria
			# pelos gratuitos ao montar o carro). PENDENTE (produção): validar a posse.
			pd["owned"] = ShopCatalog.ITEMS.keys()
		players.append({"id": m, "name": s["account"]["name"], "peers": online[m].duplicate(), "profile": pd})
	var session := RaceSession.new()
	session.name = "Race_" + room_id
	races.add_child(session)
	room["session"] = session
	session.finished.connect(_on_race_finished.bind(room_id))
	session.restart_requested.connect(_restart_race.bind(room_id), CONNECT_DEFERRED)
	session.start(self, room_id, room["settings"].duplicate(), players)
	_push_room(room_id)
	for m in room["members"]:
		await _broadcast_presence(m)


## Votação aprovada: descarta a corrida (sem resultado nem prêmio) e larga outra com a mesma sala.
## Os clientes recebem um novo race_start e recarregam a pista.
func _restart_race(room_id: String) -> void:
	if not rooms.has(room_id):
		return
	var room: Dictionary = rooms[room_id]
	var old: Variant = room["session"]
	room["session"] = null
	if old:
		old.stop()
	_start_race(room_id)


## Fim da corrida: aplica resultados (créditos, contadores, histórico) e volta a sala para o lobby.
func _on_race_finished(results: Array, room_id: String) -> void:
	for r: Dictionary in results:
		var acc_id: String = r["id"]
		if not online.has(acc_id):
			continue
		var peer: int = online[acc_id][0]
		var reward := await _apply_result(peer, r["record"], int(r["difficulty"]), bool(r["dsq"]), bool(r["fastest"]), "online")
		for p in online.get(acc_id, []):
			get_node("/root/Net").race.rpc_id(p, {"event": "reward", "reward": reward})
	if rooms.has(room_id):
		var room: Dictionary = rooms[room_id]
		room["state"] = "lobby"
		room["ready"] = {}
		if room["session"]:
			room["session"].queue_free()
		room["session"] = null
		_push_room(room_id)
		for m in room["members"]:
			await _broadcast_presence(m)


# ---------------------------------------------------------------------------
# Perfil (só amigos e o dono) e ranking
# ---------------------------------------------------------------------------
func _profile_of(peer: int, data: Dictionary) -> void:
	var me: String = _session(peer)["account"]["id"]
	var id := str(data.get("id", me))
	if id != me and not await store.are_friends(me, id):
		_error(peer, data, "Só dá para ver o perfil de amigos.")
		return
	var acc: Variant = await store.get_account(id)
	if acc == null:
		_error(peer, data, "Perfil não encontrado.")
		return
	var counters: Dictionary = acc["counters"].duplicate()
	counters["items"] = ShopCatalog.count_collectible(acc["profile"].get("owned", []) as Array)
	var history: Array = await store.recent_matches(id, NetProtocol.TRAITS_WINDOW)
	var prog := Progression.level_progress(counters)
	var payload := {
		"id": id, "name": acc["name"], "code": NetProtocol.format_code(acc["friend_code"]), "title": acc["title"],
		"level": Progression.level_of(counters), "xp": prog.x, "xp_next": prog.y,
		"history": history.slice(0, NetProtocol.HISTORY_SIZE), "achievements": Progression.achievements(counters),
		"traits": Array(Progression.traits(history)), "online": is_online(id), "in_race": in_race(id),
		"best_lap": acc["best_lap"], "own": id == me,
	}
	# Ganhos totais e saldo são privados (só o dono vê)
	if id == me:
		payload["earned"] = int(counters.get("earned", 0))
	_reply(peer, data, "profile", payload)


func _ranking(peer: int, data: Dictionary) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _ranking_time > NetProtocol.RANKING_CACHE_S:
		_ranking_cache = Ranking.build(await store.ranking_rows())
		_ranking_time = now
	var me: String = _session(peer)["account"]["id"]
	_reply(peer, data, "ranking", {"tabs": Ranking.view_for(_ranking_cache, me), "me": me})
