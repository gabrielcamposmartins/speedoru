class_name TursoDB
extends Node
## Cliente do Turso / libSQL pela API HTTP (pipeline Hrana v2: POST {url}/v2/pipeline), em GDScript.
## Funciona com o Turso na nuvem (libsql://… vira https://…) e com o servidor sqld local (Docker).
##
## query(sql, args) → Array de linhas (Dictionary coluna → valor) ou null em caso de erro; exec()
## para comandos; batch() manda vários comandos numa só ida (dentro de BEGIN/COMMIT).
## Os pedidos vão em fila, um de cada vez (a ordem das escritas é a ordem das chamadas).

var url := ""
var token := ""
var last_error := ""

var _http: HTTPRequest
var _busy := false
var _queue: Array = []


func configure(p_url: String, p_token: String) -> void:
	url = p_url.strip_edges()
	if url.begins_with("libsql://"):
		url = "https://" + url.substr(9)
	url = url.trim_suffix("/")
	token = p_token.strip_edges()


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)


## Executa uma consulta e devolve as linhas (ou null se deu erro; ver last_error).
func query(sql: String, args: Array = []) -> Variant:
	var res: Variant = await _pipeline([[sql, args]])
	if res == null:
		return null
	return res[0]


## Executa um comando (INSERT/UPDATE/DELETE/DDL). Devolve se deu certo.
func exec(sql: String, args: Array = []) -> bool:
	return await query(sql, args) != null


## Vários comandos numa transação. statements = [[sql, args], ...]
func batch(statements: Array) -> bool:
	var all := [["BEGIN", []]]
	all.append_array(statements)
	all.append(["COMMIT", []])
	return await _pipeline(all) != null


func _pipeline(statements: Array) -> Variant:
	# Fila: um pedido HTTP de cada vez
	while _busy:
		await get_tree().process_frame
	_busy = true
	var requests := []
	for st in statements:
		requests.append({"type": "execute", "stmt": {"sql": st[0], "args": _encode_args(st[1])}})
	requests.append({"type": "close"})
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var err := _http.request(url + "/v2/pipeline", headers, HTTPClient.METHOD_POST, JSON.stringify({"requests": requests}))
	if err != OK:
		last_error = "falha ao enviar (%d)" % err
		_busy = false
		return null
	var reply: Array = await _http.request_completed
	_busy = false
	var result: int = reply[0]
	var code: int = reply[1]
	var body: PackedByteArray = reply[3]
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		last_error = "HTTP %d (resultado %d): %s" % [code, result, body.get_string_from_utf8().substr(0, 300)]
		push_warning("TursoDB: " + last_error)
		return null
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		last_error = "resposta inválida"
		return null
	var out := []
	var results: Array = parsed.get("results", [])
	for k in statements.size():
		var r: Dictionary = results[k] if k < results.size() else {}
		if r.get("type", "") != "ok":
			last_error = str(r.get("error", {}).get("message", "erro desconhecido"))
			push_warning("TursoDB: %s — %s" % [last_error, statements[k][0].substr(0, 120)])
			return null
		out.append(_decode_rows(r["response"].get("result", {})))
	return out


static func _encode_args(args: Array) -> Array:
	var out := []
	for v in args:
		match typeof(v):
			TYPE_NIL:
				out.append({"type": "null"})
			TYPE_BOOL:
				out.append({"type": "integer", "value": "1" if v else "0"})
			TYPE_INT:
				out.append({"type": "integer", "value": str(v)})
			TYPE_FLOAT:
				out.append({"type": "float", "value": v})
			_:
				out.append({"type": "text", "value": str(v)})
	return out


static func _decode_rows(result: Dictionary) -> Array:
	var cols: Array = result.get("cols", [])
	var rows := []
	for raw in result.get("rows", []):
		var row := {}
		for c in cols.size():
			var cell: Dictionary = raw[c]
			var v: Variant = cell.get("value")
			match cell.get("type", "null"):
				"integer":
					v = int(v)
				"float":
					v = float(v)
				"null":
					v = null
			row[cols[c].get("name", str(c))] = v
		rows.append(row)
	return rows
