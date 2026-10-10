extends SceneTree
## Multiplayer de ponta a ponta (sem janela): sobe o servidor dedicado, conecta dois clientes no
## mesmo processo (cada um com a própria MultiplayerAPI) e passa por conta, amigos, grupo, sala,
## corrida no servidor (entradas → carro anda nos instantâneos), resultado solo e ranking.
##
## Precisa de um libSQL local (Docker):
##   docker run -d -p 18080:8080 ghcr.io/tursodatabase/libsql-server
##   godot --headless --path . -s res://tests/net_test.gd
## Outra URL: variável SPEEDORU_TEST_DB. SPEEDORU_TEST_DB=local usa o banco em arquivo do servidor
## hospedado pelo jogo (LocalStore, em user://test_net_host/), sem Docker.
## Contas de teste ficam em user://test_net_*.cfg (apagadas no fim).

const PORT := 7360
const GODOT_ARGS := ["--headless", "--path", ".", "--", "--server", "--port=7360"]
const LOCAL_DIR := "user://test_net_host"

var failures := 0
var server_pid := -1
var a: Node
var b: Node
var inbox := {"A": [], "B": []}
var snaps := {"A": [], "B": []}
var states := {"A": [], "B": []}


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await process_frame
		t += 1.0 / 60.0
		await create_timer(1.0 / 60.0).timeout
	return cond.call()


func _client(tag: String) -> Node:
	var holder := Node.new()
	holder.name = "Client" + tag
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var n: Node = load("res://scripts/net/net.gd").new()
	n.name = "Net"
	n.account_file = "user://test_net_%s.cfg" % tag.to_lower()
	n.auto_profile = false
	n.auto_race = false
	holder.add_child(n)
	n.message.connect(func(type: String, data: Dictionary) -> void: inbox[tag].append([type, data]))
	n.race_snapshot.connect(func(data: PackedByteArray) -> void: snaps[tag].append(NetSnapshot.decode(data)))
	n.race_state.connect(func(data: Dictionary) -> void: states[tag].append(data))
	return n


func _got(tag: String, type: String) -> Variant:
	for m in inbox[tag]:
		if m[0] == type:
			return m[1]
	return null


func _run() -> void:
	var db := OS.get_environment("SPEEDORU_TEST_DB")
	if db == "":
		db = "http://127.0.0.1:18080"
	print("Banco de teste: ", db)
	var args := GODOT_ARGS.duplicate()
	if db == "local":
		_clean_local()
		args.append("--host-dir=" + ProjectSettings.globalize_path(LOCAL_DIR))
	else:
		args.append("--db-url=" + db)
	server_pid = OS.create_process(OS.get_executable_path(), args)
	_check(server_pid > 0, "servidor dedicado iniciado")
	await _wait(6.0)
	for f in ["user://test_net_a.cfg", "user://test_net_b.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	a = _client("A")
	b = _client("B")
	a.connect_to_server("127.0.0.1", PORT)
	b.connect_to_server("127.0.0.1", PORT)
	var ok := await _wait_for(func() -> bool: return a.online and b.online, 20.0)
	_check(ok, "os dois clientes entraram (welcome)")
	if not ok:
		_finish()
		return
	var code_a: String = a.account["code"]
	_check(code_a.length() == 7 and code_a[3] == "-", "código de amigo no formato ABC-234 (%s)" % code_a)
	_check(int(a.account["level"]) == 1, "conta nova começa no nível 1")

	# --- Perfil: nome
	var r: Dictionary = await a.request("set_name", {"name": "  Alice Teste Muito Comprida  "})
	_check(r.get("ok", false) and str(r.get("name")).length() <= 16, "nome limpo e com até 16 letras (%s)" % r.get("name"))
	await b.request("set_name", {"name": "Bruno"})
	r = await a.request("set_name", {"name": "Alice"})

	# --- Amigos
	r = await b.request("friend_add", {"code": code_a.to_lower().replace("-", " ")})
	_check(r.get("ok", false), "pedido de amizade pelo código (minúsculas/espaço aceitos)")
	r = await b.request("friend_add", {"code": code_a})
	_check(not r.get("ok", true), "pedido repetido recusado: %s" % r.get("error", ""))
	r = await a.request("friend_add", {"code": a.account["code"]})
	_check(not r.get("ok", true), "pedido para si mesmo recusado: %s" % r.get("error", ""))
	await _wait(0.5)
	_check(_got("A", "friend_request") != null, "A recebeu o aviso do pedido")
	r = await a.request("friends")
	_check((r.get("incoming", []) as Array).size() == 1, "A vê 1 pedido recebido")
	var b_id: String = b.account["id"]
	var a_id: String = a.account["id"]
	r = await a.request("friend_accept", {"id": b_id})
	_check(r.get("ok", false), "A aceitou")
	r = await b.request("friends")
	var fl: Array = r.get("friends", [])
	_check(fl.size() == 1 and fl[0]["online"] == true, "B vê A como amigo online")
	r = await a.request("profile_of", {"id": b_id})
	_check(r.get("ok", true) != false and r.get("name") == "Bruno" and not r.has("earned"), "perfil de amigo visível, sem ganhos privados")

	# --- Grupo
	r = await a.request("party_invite", {"id": b_id})
	_check(r.get("ok", false), "A convidou B para o grupo")
	await _wait(0.4)
	var ask: Variant = _got("B", "party_ask")
	_check(ask != null, "B recebeu o convite do grupo")
	if ask:
		r = await b.request("party_accept", {"party": ask["party"]})
		_check(r.get("ok", false), "B entrou no grupo")
	await _wait(0.4)
	var party_msgs: Array = inbox["A"].filter(func(m: Array) -> bool: return m[0] == "party")
	_check(not party_msgs.is_empty() and (party_msgs[-1][1]["party"]["members"] as Array).size() == 2, "grupo com 2 pessoas")
	r = await b.request("party_invite", {"id": a_id})
	_check(not r.get("ok", true), "só o líder convida: %s" % r.get("error", ""))

	# --- Sala
	r = await a.request("room_create", {"kind": "custom", "name": "Sala teste", "password": "x"})
	_check(r.get("ok", false), "sala criada")
	var room_id: String = r.get("room", "")
	r = await b.request("room_join", {"id": room_id, "password": "errada"})
	_check(not r.get("ok", true), "senha errada recusada")
	r = await b.request("room_join", {"id": room_id, "password": "x"})
	_check(r.get("ok", false), "B entrou com a senha")
	r = await b.request("room_settings", {"laps": 3})
	_check(not r.get("ok", true), "só o anfitrião muda a sala")
	r = await a.request("room_settings", {"laps": 3, "bots": false, "difficulty": 0, "drs": 1, "track": "monaco"})
	_check(r.get("ok", false), "anfitrião ajustou: 3 voltas, sem bots")
	r = await a.request("rooms")
	_check((r.get("rooms", []) as Array).any(func(x: Dictionary) -> bool: return x["id"] == room_id and x["locked"]), "sala aparece na lista com cadeado")

	# --- Carro do aparelho: o servidor aceita até item que a conta não tem (PENDENTE: validar posse)
	var eq: Dictionary = (a.account["profile"]["equipped"] as Dictionary).duplicate(true)
	eq["primary"] = "123456"
	eq["decals"] = {"sidepods": {"id": "sakura", "color": "ff0000", "scale": 1.2, "rot": 0.0, "x": 0.3, "y": 0.0}}
	eq["setup"] = {"downforce_area": 4.6}
	a.send_to_server("equip", {"equipped": eq})
	ok = await _wait_for(func() -> bool:
		return str((a.account["profile"]["equipped"].get("decals", {}) as Dictionary).get("sidepods", {}).get("id", "")) == "sakura", 5.0)
	_check(ok and float(a.account["profile"]["equipped"]["setup"].get("downforce_area", 0.0)) == 4.6
		and str(a.account["profile"]["equipped"]["primary"]) == "123456",
		"servidor aceita o carro do aparelho (cor livre, decalque não ganho e engenharia)")

	# --- Corrida no servidor
	r = await a.request("room_start")
	_check(r.get("ok", false), "anfitrião largou a corrida")
	ok = await _wait_for(func() -> bool: return _got("A", "race_start") != null and _got("B", "race_start") != null, 60.0)
	_check(ok, "os dois receberam race_start (servidor montou o grid)")
	if ok:
		var rs: Dictionary = _got("A", "race_start")
		var roster: Array = rs["roster"]
		_check(roster.size() == 2, "grid só com os 2 humanos")
		_check(int(rs["settings"].get("drs", 0)) == 1, "regra do DRS da sala (até 1 s) chega à corrida")
		_check(str(rs["settings"].get("track", "")) == "monaco", "pista da sala (Mônaco) chega à corrida")
		var mine: Array = roster.filter(func(d: Dictionary) -> bool: return d["id"] == a_id)
		_check(not mine.is_empty() and str(mine[0]["profile"]["equipped"]["primary"]) == "123456"
			and str(mine[0]["profile"]["equipped"]["decals"]["sidepods"]["id"]) == "sakura",
			"o carro do grid usa o visual do jogador (cor e decalque)")
		var my_idx := -1
		for d in roster:
			if d["id"] == a_id:
				my_idx = int(d["idx"])
		a.send_to_server("race_cmd", {"cmd": "loaded"})
		b.send_to_server("race_cmd", {"cmd": "loaded"})
		ok = await _wait_for(func() -> bool:
			return states["A"].any(func(s: Dictionary) -> bool: return int(s.get("state", 0)) == RaceManager.State.RACING), 40.0)
		_check(ok, "luzes apagaram no servidor (estado RACING chegou)")
		_check(states["A"].any(func(s: Dictionary) -> bool: return s.get("event", "") == "lights"), "evento das luzes chegou")
		var start_pos: Vector3 = snaps["A"][-1]["cars"][my_idx]["pos"] if not snaps["A"].is_empty() else Vector3.ZERO
		# Acelera 4 s (entradas a 60/s, como o jogo)
		var counts := [0, 0, 0, 0, 0, 0, 0, 0]
		var b_idx := -1
		for d2 in roster:
			if d2["id"] == b.account["id"]:
				b_idx = int(d2["idx"])
		var boost_a := 0
		var boost_b := 0
		for i in 240:
			var d := PackedFloat32Array([i, 1.0, 0.0, 0.0, 0.0, NetProtocol.BTN_BOOST if i > 120 else 0])
			d.append_array(PackedFloat32Array(counts))
			a.inp.rpc_id(1, d)
			await create_timer(1.0 / 60.0).timeout
		for snap: Dictionary in snaps["A"].slice(-60):
			boost_a += int(int(snap["cars"][my_idx]["flags"]) & NetSnapshot.F_BOOST != 0)
			boost_b += int(int(snap["cars"][b_idx]["flags"]) & NetSnapshot.F_BOOST != 0)
		_check(boost_a > 0 and boost_b == 0, "boost só no carro de quem apertou (A %d, B %d instantâneos com boost)" % [boost_a, boost_b])
		var end_snap: Dictionary = snaps["A"][-1]["cars"][my_idx]
		var moved := (end_snap["pos"] as Vector3).distance_to(start_pos)
		_check(moved > 15.0, "o carro de A andou com as entradas pela rede (%.0f m, %.0f km/h)" % [moved, (end_snap["vel"] as Vector3).length() * 3.6])
		_check(snaps["B"].size() > 50, "B recebe os instantâneos (%d)" % snaps["B"].size())

		# --- Votação para pausar: os dois votam, os carros congelam; votação para retomar com contagem
		a.send_to_server("race_cmd", {"cmd": "vote", "kind": "pause", "yes": true})
		b.send_to_server("race_cmd", {"cmd": "vote", "kind": "pause", "yes": true})
		ok = await _wait_for(func() -> bool:
			return states["A"].any(func(s: Dictionary) -> bool: return s.get("event", "") == "paused" and bool(s.get("paused", false))), 5.0)
		_check(ok, "votação aprovada: corrida pausada")
		await _wait(0.5)
		var p0: Vector3 = snaps["A"][-1]["cars"][my_idx]["pos"]
		for i in 60:
			var d := PackedFloat32Array([i, 1.0, 0.0, 0.0, 0.0, 0])
			d.append_array(PackedFloat32Array(counts))
			a.inp.rpc_id(1, d)
			await create_timer(1.0 / 60.0).timeout
		var p1: Vector3 = snaps["A"][-1]["cars"][my_idx]["pos"]
		_check(p0.distance_to(p1) < 0.05, "pausado: o carro não anda mesmo acelerando (%.3f m)" % p0.distance_to(p1))
		states["A"].clear()
		a.send_to_server("race_cmd", {"cmd": "vote", "kind": "resume", "yes": true})
		b.send_to_server("race_cmd", {"cmd": "vote", "kind": "resume", "yes": true})
		ok = await _wait_for(func() -> bool:
			return states["A"].any(func(s: Dictionary) -> bool: return s.get("event", "") == "resuming"), 5.0)
		_check(ok, "votação para retomar aprovada: contagem")
		ok = await _wait_for(func() -> bool:
			return states["A"].any(func(s: Dictionary) -> bool: return s.get("event", "") == "paused" and not bool(s.get("paused", true))), 8.0)
		_check(ok, "corrida retomada depois da contagem")

		# --- Votação para recomeçar: A abre (1/2), B vota e a corrida recomeça do grid
		states["B"].clear()
		a.send_to_server("race_cmd", {"cmd": "vote", "kind": "restart", "yes": true})
		ok = await _wait_for(func() -> bool:
			return states["B"].any(func(s: Dictionary) -> bool: return s.get("event", "") == "vote" and int(s.get("yes", 0)) == 1), 5.0)
		_check(ok, "votação aberta chega a B (1/2)")
		var vote_ev: Array = states["B"].filter(func(s: Dictionary) -> bool: return s.get("event", "") == "vote")
		_check(not vote_ev.is_empty() and int(vote_ev[-1]["needed"]) == 2 and a_id in (vote_ev[-1]["ids"] as Array),
			"maioria de 2 humanos = 2 votos; A conta como sim")
		var starts_before: int = inbox["A"].filter(func(m: Array) -> bool: return m[0] == "race_start").size()
		b.send_to_server("race_cmd", {"cmd": "vote", "kind": "restart", "yes": true})
		ok = await _wait_for(func() -> bool:
			return states["A"].any(func(s: Dictionary) -> bool: return s.get("event", "") == "restarting"), 5.0)
		_check(ok, "votação aprovada: aviso de recomeço")
		ok = await _wait_for(func() -> bool:
			return inbox["A"].filter(func(m: Array) -> bool: return m[0] == "race_start").size() > starts_before \
				and inbox["B"].filter(func(m: Array) -> bool: return m[0] == "race_start").size() > starts_before, 60.0)
		_check(ok, "novo race_start para os dois (corrida recomeçou)")
		states["A"].clear()
		a.send_to_server("race_cmd", {"cmd": "loaded"})
		b.send_to_server("race_cmd", {"cmd": "loaded"})
		ok = await _wait_for(func() -> bool:
			return states["A"].any(func(s: Dictionary) -> bool: return int(s.get("state", 0)) == RaceManager.State.RACING), 40.0)
		_check(ok, "corrida nova largou")
		a.send_to_server("race_cmd", {"cmd": "quit"})
		b.send_to_server("race_cmd", {"cmd": "quit"})
		ok = await _wait_for(func() -> bool:
			var rooms: Array = inbox["A"].filter(func(m: Array) -> bool: return m[0] == "room" and not m[1]["room"].is_empty())
			return not rooms.is_empty() and rooms[-1][1]["room"]["state"] == "lobby", 15.0)
		_check(ok, "todos saíram: corrida encerrada e sala de volta ao lobby")

	# --- Resultado solo (conferido pelo servidor)
	r = await a.request("solo_result", {"laps": 3, "laps_total": 3, "difficulty": 0, "race_time": 300.0, "best_lap": 9.0, "finished": true, "pos": 1, "total": 10})
	_check(not r.get("ok", true), "volta impossível recusada: %s" % r.get("error", ""))
	r = await a.request("solo_result", {"laps": 3, "laps_total": 3, "difficulty": 2, "race_time": 300.0, "best_lap": 95.0, "finished": true, "pos": 1, "total": 10})
	_check(not r.get("ok", true), "dificuldade bloqueada no nível 1: %s" % r.get("error", ""))
	r = await a.request("solo_result", {"laps": 3, "laps_total": 3, "difficulty": 0, "race_time": 300.0, "best_lap": 95.0, "finished": true,
		"pos": 1, "total": 10, "grid": 5, "lap_times": [101.0, 99.0, 95.0], "fastest": true})
	_check(r.get("ok", false) and int(r.get("reward", 0)) > 0, "vitória solo paga pelo servidor (%s)" % r.get("reward"))
	await _wait(0.3)
	_check(int(a.account["counters"].get("wins", 0)) == 1 and int(a.account["counters"].get("laps", 0)) == 3, "contadores atualizados na conta")
	r = await a.request("profile_of")
	_check((r.get("history", []) as Array).size() == 1 and r.has("earned"), "histórico com a corrida e ganhos visíveis para o dono")
	_check((r.get("achievements", []) as Array).size() == 21, "21 conquistas no perfil")
	r = await a.request("ranking")
	var tabs: Dictionary = r.get("tabs", {})
	_check(tabs.has("geral") and tabs.has("wins") and tabs.has("best_lap"), "ranking com as abas")
	var wins_rows: Array = tabs.get("wins", {}).get("rows", [])
	_check(wins_rows.any(func(x: Dictionary) -> bool: return x["id"] == a_id), "A aparece no ranking de vitórias")
	r = await a.request("set_title", {"title": "Lenda das pistas"})
	_check(not r.get("ok", true), "título não conquistado recusado")

	# --- Desfazer amizade e saída do líder
	r = await b.request("friend_remove", {"id": a_id})
	_check(r.get("ok", false), "B desfez a amizade")
	r = await a.request("friends")
	_check((r.get("friends", []) as Array).is_empty(), "removida dos dois lados")
	inbox["B"].clear()
	a.disconnect_from_server()
	await _wait(1.5)
	var pb: Array = inbox["B"].filter(func(m: Array) -> bool: return m[0] == "party")
	_check(not pb.is_empty() and pb[-1][1]["party"].is_empty(), "líder saiu: grupo desfeito")
	_finish()


func _clean_local() -> void:
	for d in [LOCAL_DIR.path_join("skins"), LOCAL_DIR]:
		var dir := ProjectSettings.globalize_path(d)
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir.path_join(f))
			DirAccess.remove_absolute(dir)


func _finish() -> void:
	for f in ["user://test_net_a.cfg", "user://test_net_b.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	if server_pid > 0:
		OS.kill(server_pid)
	await _wait(0.5)
	_clean_local()
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
