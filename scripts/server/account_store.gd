class_name AccountStore
extends Node
## Dados persistentes do servidor no Turso (tabelas próprias com prefixo sp_, para conviver com as
## que já existem no banco): contas, amizades, pedidos de amizade e histórico de corridas.
##
## A conta guarda o perfil econômico (PlayerProfile.to_dict: créditos, coleção, equipamento,
## engenharia), os contadores (que dão nível, conquistas e ranking), o título e a melhor volta.
## O token do jogador nunca é guardado: só o hash SHA-256 dele.

const SCHEMA_VERSION := 1
const SCHEMA := [
	"""CREATE TABLE IF NOT EXISTS sp_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)""",
	"""CREATE TABLE IF NOT EXISTS sp_accounts (
		id TEXT PRIMARY KEY,
		token_hash TEXT NOT NULL UNIQUE,
		name TEXT NOT NULL,
		friend_code TEXT NOT NULL UNIQUE,
		title TEXT NOT NULL DEFAULT '',
		profile TEXT NOT NULL DEFAULT '{}',
		counters TEXT NOT NULL DEFAULT '{}',
		best_lap REAL NOT NULL DEFAULT 0,
		created_at INTEGER NOT NULL,
		updated_at INTEGER NOT NULL)""",
	"""CREATE TABLE IF NOT EXISTS sp_friends (
		account_id TEXT NOT NULL,
		friend_id TEXT NOT NULL,
		since INTEGER NOT NULL,
		PRIMARY KEY (account_id, friend_id))""",
	"""CREATE TABLE IF NOT EXISTS sp_friend_requests (
		from_id TEXT NOT NULL,
		to_id TEXT NOT NULL,
		created_at INTEGER NOT NULL,
		PRIMARY KEY (from_id, to_id))""",
	"""CREATE INDEX IF NOT EXISTS sp_friend_requests_to ON sp_friend_requests (to_id)""",
	"""CREATE TABLE IF NOT EXISTS sp_matches (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		account_id TEXT NOT NULL,
		finished_at INTEGER NOT NULL,
		kind TEXT NOT NULL,
		record TEXT NOT NULL)""",
	"""CREATE INDEX IF NOT EXISTS sp_matches_account ON sp_matches (account_id, finished_at)""",
]

var db: TursoDB
var _rng := RandomNumberGenerator.new()


func setup(p_db: TursoDB) -> void:
	db = p_db
	_rng.randomize()


## Cria as tabelas (idempotente). Devolve se o banco respondeu.
func migrate() -> bool:
	var statements := []
	for sql in SCHEMA:
		statements.append([sql, []])
	statements.append(["INSERT INTO sp_meta (key, value) VALUES ('schema', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
		[str(SCHEMA_VERSION)]])
	return await db.batch(statements)


static func now() -> int:
	return int(Time.get_unix_time_from_system())


static func hash_token(token: String) -> String:
	return token.sha256_text()


# ---------------------------------------------------------------------------
# Contas
# ---------------------------------------------------------------------------
## Conta pelo token do aparelho; cria uma nova se não existir. null se o banco falhar.
func login(token: String, name: String) -> Variant:
	var h := hash_token(token)
	var rows: Variant = await db.query("SELECT * FROM sp_accounts WHERE token_hash = ?", [h])
	if rows == null:
		return null
	if not rows.is_empty():
		return _row_to_account(rows[0])
	# Conta nova: id fixo e código de amigo único
	var profile := PlayerProfile.new()
	profile.mode = "server"
	profile.equipped = PlayerProfile.default_equipped()
	var acc := {
		"id": _uuid(), "name": NetProtocol.clean_name(name), "friend_code": "", "title": "",
		"profile": profile.to_dict(), "counters": {}, "best_lap": 0.0,
	}
	profile.free()
	for attempt in 8:
		acc["friend_code"] = NetProtocol.random_code(_rng)
		var ok: bool = await db.exec("""INSERT INTO sp_accounts (id, token_hash, name, friend_code, title, profile, counters,
			best_lap, created_at, updated_at) VALUES (?, ?, ?, ?, '', ?, '{}', 0, ?, ?)""",
			[acc["id"], h, acc["name"], acc["friend_code"], JSON.stringify(acc["profile"]), now(), now()])
		if ok:
			return acc
		if not db.last_error.to_lower().contains("unique"):
			return null
	return null


func get_account(id: String) -> Variant:
	var rows: Variant = await db.query("SELECT * FROM sp_accounts WHERE id = ?", [id])
	if rows == null or rows.is_empty():
		return null
	return _row_to_account(rows[0])


func find_by_code(code: String) -> Variant:
	var rows: Variant = await db.query("SELECT * FROM sp_accounts WHERE friend_code = ?", [code])
	if rows == null or rows.is_empty():
		return null
	return _row_to_account(rows[0])


## Grava os campos mutáveis da conta.
func save_account(acc: Dictionary) -> bool:
	return await db.exec("""UPDATE sp_accounts SET name = ?, title = ?, profile = ?, counters = ?, best_lap = ?, updated_at = ?
		WHERE id = ?""", [acc["name"], acc["title"], JSON.stringify(acc["profile"]), JSON.stringify(acc["counters"]),
		float(acc["best_lap"]), now(), acc["id"]])


## Nomes, níveis e títulos de várias contas (lista de amigos, salas).
func summaries(ids: Array) -> Dictionary:
	var out := {}
	if ids.is_empty():
		return out
	var marks := ",".join(ids.map(func(_x): return "?"))
	var rows: Variant = await db.query("SELECT id, name, friend_code, title, counters FROM sp_accounts WHERE id IN (%s)" % marks, ids)
	if rows == null:
		return out
	for r in rows:
		var counters: Dictionary = _json(r["counters"])
		out[r["id"]] = {"id": r["id"], "name": r["name"], "code": NetProtocol.format_code(r["friend_code"]),
			"title": r["title"], "level": Progression.level_of(counters)}
	return out


## Todas as contas com o mínimo para o ranking.
func ranking_rows() -> Array:
	var rows: Variant = await db.query("SELECT id, name, counters, best_lap FROM sp_accounts")
	if rows == null:
		return []
	var out := []
	for r in rows:
		out.append({"id": r["id"], "name": r["name"], "counters": _json(r["counters"]), "best_lap": float(r["best_lap"])})
	return out


func _row_to_account(r: Dictionary) -> Dictionary:
	return {
		"id": r["id"], "name": r["name"], "friend_code": r["friend_code"], "title": r["title"],
		"profile": _json(r["profile"]), "counters": _json(r["counters"]), "best_lap": float(r["best_lap"]),
	}


static func _json(text: Variant) -> Dictionary:
	var v: Variant = JSON.parse_string(str(text)) if text != null else null
	return v if v is Dictionary else {}


func _uuid() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	return b.hex_encode()


# ---------------------------------------------------------------------------
# Amizades (sempre mútuas: uma linha em cada sentido)
# ---------------------------------------------------------------------------
func friends_of(id: String) -> Array:
	var rows: Variant = await db.query("SELECT friend_id FROM sp_friends WHERE account_id = ?", [id])
	return [] if rows == null else rows.map(func(r): return r["friend_id"])


func requests_to(id: String) -> Array:
	var rows: Variant = await db.query("SELECT from_id FROM sp_friend_requests WHERE to_id = ?", [id])
	return [] if rows == null else rows.map(func(r): return r["from_id"])


func requests_from(id: String) -> Array:
	var rows: Variant = await db.query("SELECT to_id FROM sp_friend_requests WHERE from_id = ?", [id])
	return [] if rows == null else rows.map(func(r): return r["to_id"])


func count_friends(id: String) -> int:
	var rows: Variant = await db.query("SELECT COUNT(*) AS n FROM sp_friends WHERE account_id = ?", [id])
	return 0 if rows == null or rows.is_empty() else int(rows[0]["n"])


func count_requests_to(id: String) -> int:
	var rows: Variant = await db.query("SELECT COUNT(*) AS n FROM sp_friend_requests WHERE to_id = ?", [id])
	return 0 if rows == null or rows.is_empty() else int(rows[0]["n"])


func are_friends(a: String, b: String) -> bool:
	var rows: Variant = await db.query("SELECT 1 AS x FROM sp_friends WHERE account_id = ? AND friend_id = ?", [a, b])
	return rows != null and not rows.is_empty()


func has_request(from_id: String, to_id: String) -> bool:
	var rows: Variant = await db.query("SELECT 1 AS x FROM sp_friend_requests WHERE from_id = ? AND to_id = ?", [from_id, to_id])
	return rows != null and not rows.is_empty()


func add_request(from_id: String, to_id: String) -> bool:
	return await db.exec("INSERT OR IGNORE INTO sp_friend_requests (from_id, to_id, created_at) VALUES (?, ?, ?)",
		[from_id, to_id, now()])


## Recusar e cancelar: a mesma ação limpa o pedido dos dois lados.
func clear_requests(a: String, b: String) -> bool:
	return await db.exec("DELETE FROM sp_friend_requests WHERE (from_id = ? AND to_id = ?) OR (from_id = ? AND to_id = ?)",
		[a, b, b, a])


func make_friends(a: String, b: String) -> bool:
	return await db.batch([
		["INSERT OR IGNORE INTO sp_friends (account_id, friend_id, since) VALUES (?, ?, ?)", [a, b, now()]],
		["INSERT OR IGNORE INTO sp_friends (account_id, friend_id, since) VALUES (?, ?, ?)", [b, a, now()]],
		["DELETE FROM sp_friend_requests WHERE (from_id = ? AND to_id = ?) OR (from_id = ? AND to_id = ?)", [a, b, b, a]],
	])


func remove_friend(a: String, b: String) -> bool:
	return await db.exec("DELETE FROM sp_friends WHERE (account_id = ? AND friend_id = ?) OR (account_id = ? AND friend_id = ?)",
		[a, b, b, a])


# ---------------------------------------------------------------------------
# Histórico
# ---------------------------------------------------------------------------
func add_match(id: String, kind: String, record: Dictionary) -> bool:
	return await db.exec("INSERT INTO sp_matches (account_id, finished_at, kind, record) VALUES (?, ?, ?, ?)",
		[id, now(), kind, JSON.stringify(record)])


## Últimas n corridas (mais nova primeiro), com finished_at.
func recent_matches(id: String, n: int) -> Array:
	var rows: Variant = await db.query("SELECT finished_at, kind, record FROM sp_matches WHERE account_id = ? ORDER BY finished_at DESC, id DESC LIMIT ?",
		[id, n])
	if rows == null:
		return []
	var out := []
	for r in rows:
		var rec := _json(r["record"])
		rec["t"] = int(r["finished_at"])
		rec["kind"] = r["kind"]
		out.append(rec)
	return out
