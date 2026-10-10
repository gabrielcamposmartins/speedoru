class_name LocalStore
extends AccountStore
## Banco do servidor hospedado pelo próprio jogo (LocalHost; `--host-dir=`): as mesmas operações do
## AccountStore, guardadas num arquivo JSON na pasta do host em vez do Turso. Quem abre um servidor
## para os amigos não precisa de banco nenhum.
##
## Tudo fica na memória. Grava no máximo uma vez por segundo e ao fechar (flush), num arquivo
## temporário que substitui o anterior de uma vez (não corrompe se o processo morrer no meio).

const FILE := "server_db.json"
const SAVE_DELAY := 1.0
const MAX_MATCHES := 5000

var path := ""
var last_error := ""
## id -> conta (campos de _row_to_account + token_hash)
var _accounts := {}
## id -> {friend_id: since}
var _friends := {}
## "from|to" -> {from, to, t}
var _requests := {}
## [{id, account, t, kind, record}], mais antiga primeiro
var _matches := []
var _next_match := 1
var _dirty := false
var _save_timer := 0.0


func setup_local(dir: String) -> void:
	path = dir.path_join(FILE)
	_rng.randomize()


## Lê o arquivo (se existe). Recusa um arquivo estragado em vez de começar outro por cima.
func migrate() -> bool:
	if not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		_dirty = true
		return flush()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		last_error = "arquivo do banco ilegível: %s" % path
		return false
	for a: Dictionary in data.get("accounts", []):
		var acc := {
			"id": str(a["id"]), "token_hash": str(a["token_hash"]), "name": str(a["name"]),
			"friend_code": str(a["friend_code"]), "title": str(a.get("title", "")),
			"profile": a.get("profile", {}), "counters": a.get("counters", {}), "best_lap": float(a.get("best_lap", 0.0)),
		}
		_accounts[acc["id"]] = acc
	for f: Array in data.get("friends", []):
		_link(str(f[0]), str(f[1]), int(f[2]))
	for r: Array in data.get("requests", []):
		_requests["%s|%s" % [r[0], r[1]]] = {"from": str(r[0]), "to": str(r[1]), "t": int(r[2])}
	for m: Dictionary in data.get("matches", []):
		_matches.append({"id": int(m["id"]), "account": str(m["account"]), "t": int(m["t"]), "kind": str(m["kind"]),
			"record": m.get("record", {})})
		_next_match = maxi(_next_match, int(m["id"]) + 1)
	return true


## Grava agora (se mudou algo). Devolve se deu certo.
func flush() -> bool:
	if not _dirty:
		return true
	var friends := []
	for a: String in _friends:
		for b: String in _friends[a]:
			friends.append([a, b, _friends[a][b]])
	var requests := []
	for r: Dictionary in _requests.values():
		requests.append([r["from"], r["to"], r["t"]])
	var data := {"version": SCHEMA_VERSION, "accounts": _accounts.values(), "friends": friends, "requests": requests,
		"matches": _matches}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "não deu para gravar %s (%d)" % [tmp, FileAccess.get_open_error()]
		push_warning("LocalStore: " + last_error)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		last_error = "não deu para trocar %s" % path
		return false
	_dirty = false
	return true


func _touch() -> void:
	if not _dirty:
		_save_timer = SAVE_DELAY
	_dirty = true


func _process(delta: float) -> void:
	if _dirty:
		_save_timer -= delta
		if _save_timer <= 0.0:
			flush()


func _exit_tree() -> void:
	flush()


func _public(acc: Dictionary) -> Dictionary:
	var out := acc.duplicate(true)
	out.erase("token_hash")
	return out


# ---------------------------------------------------------------------------
# Contas
# ---------------------------------------------------------------------------
func login(token: String, name: String) -> Variant:
	var h := hash_token(token)
	for acc: Dictionary in _accounts.values():
		if acc["token_hash"] == h:
			return _public(acc)
	var profile := PlayerProfile.new()
	profile.mode = "server"
	profile.equipped = PlayerProfile.default_equipped()
	var acc := {
		"id": _uuid(), "token_hash": h, "name": NetProtocol.clean_name(name), "friend_code": "", "title": "",
		"profile": JSON.parse_string(JSON.stringify(profile.to_dict())), "counters": {}, "best_lap": 0.0,
	}
	profile.free()
	var used := {}
	for a: Dictionary in _accounts.values():
		used[a["friend_code"]] = true
	for attempt in 64:
		acc["friend_code"] = NetProtocol.random_code(_rng)
		if not used.has(acc["friend_code"]):
			_accounts[acc["id"]] = acc
			_touch()
			return _public(acc)
	return null


func get_account(id: String) -> Variant:
	return _public(_accounts[id]) if _accounts.has(id) else null


func find_by_code(code: String) -> Variant:
	for acc: Dictionary in _accounts.values():
		if acc["friend_code"] == code:
			return _public(acc)
	return null


func save_account(acc: Dictionary) -> bool:
	if not _accounts.has(acc["id"]):
		return false
	var cur: Dictionary = _accounts[acc["id"]]
	cur["name"] = acc["name"]
	cur["title"] = acc["title"]
	# Mesma ida e volta por JSON do banco de verdade (números viram float)
	cur["profile"] = JSON.parse_string(JSON.stringify(acc["profile"]))
	cur["counters"] = JSON.parse_string(JSON.stringify(acc["counters"]))
	cur["best_lap"] = float(acc["best_lap"])
	_touch()
	return true


func summaries(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		if _accounts.has(id):
			var r: Dictionary = _accounts[id]
			out[id] = {"id": id, "name": r["name"], "code": NetProtocol.format_code(r["friend_code"]),
				"title": r["title"], "level": Progression.level_of(r["counters"])}
	return out


func ranking_rows() -> Array:
	var out := []
	for r: Dictionary in _accounts.values():
		out.append({"id": r["id"], "name": r["name"], "counters": r["counters"].duplicate(true), "best_lap": float(r["best_lap"])})
	return out


## Quantas contas o banco tem (painel do host).
func account_count() -> int:
	return _accounts.size()


# ---------------------------------------------------------------------------
# Amizades
# ---------------------------------------------------------------------------
func _link(a: String, b: String, since: int) -> void:
	if not _friends.has(a):
		_friends[a] = {}
	if not _friends[a].has(b):
		_friends[a][b] = since


func friends_of(id: String) -> Array:
	return (_friends.get(id, {}) as Dictionary).keys()


func requests_to(id: String) -> Array:
	return _requests.values().filter(func(r: Dictionary) -> bool: return r["to"] == id).map(func(r: Dictionary) -> String: return r["from"])


func requests_from(id: String) -> Array:
	return _requests.values().filter(func(r: Dictionary) -> bool: return r["from"] == id).map(func(r: Dictionary) -> String: return r["to"])


func count_friends(id: String) -> int:
	return (_friends.get(id, {}) as Dictionary).size()


func count_requests_to(id: String) -> int:
	return requests_to(id).size()


func are_friends(a: String, b: String) -> bool:
	return (_friends.get(a, {}) as Dictionary).has(b)


func has_request(from_id: String, to_id: String) -> bool:
	return _requests.has("%s|%s" % [from_id, to_id])


func add_request(from_id: String, to_id: String) -> bool:
	var key := "%s|%s" % [from_id, to_id]
	if not _requests.has(key):
		_requests[key] = {"from": from_id, "to": to_id, "t": now()}
		_touch()
	return true


func clear_requests(a: String, b: String) -> bool:
	_requests.erase("%s|%s" % [a, b])
	_requests.erase("%s|%s" % [b, a])
	_touch()
	return true


func make_friends(a: String, b: String) -> bool:
	_link(a, b, now())
	_link(b, a, now())
	return clear_requests(a, b)


func remove_friend(a: String, b: String) -> bool:
	(_friends.get(a, {}) as Dictionary).erase(b)
	(_friends.get(b, {}) as Dictionary).erase(a)
	_touch()
	return true


# ---------------------------------------------------------------------------
# Histórico
# ---------------------------------------------------------------------------
func add_match(id: String, kind: String, record: Dictionary) -> bool:
	_matches.append({"id": _next_match, "account": id, "t": now(), "kind": kind,
		"record": JSON.parse_string(JSON.stringify(record))})
	_next_match += 1
	# O perfil só olha as últimas corridas: o arquivo não cresce sem fim
	if _matches.size() > MAX_MATCHES:
		_matches = _matches.slice(_matches.size() - MAX_MATCHES)
	_touch()
	return true


func recent_matches(id: String, n: int) -> Array:
	var out := []
	# Mais nova primeiro (mesma ordem do SQL: finished_at e id decrescentes)
	for k in range(_matches.size() - 1, -1, -1):
		var m: Dictionary = _matches[k]
		if m["account"] != id:
			continue
		var rec: Dictionary = (m["record"] as Dictionary).duplicate(true)
		rec["t"] = int(m["t"])
		rec["kind"] = m["kind"]
		out.append(rec)
		if out.size() >= n:
			break
	return out
