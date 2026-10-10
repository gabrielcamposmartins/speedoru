extends SceneTree
## Servidor hospedado pelo jogo e endereços (sem janela, sem banco externo):
## * NetProtocol.parse_address / format_address (IPv4, IPv6 com e sem colchetes, nomes, portas).
## * LocalStore: contas, amizades, histórico e persistência no arquivo.
## * LocalHost: abre o servidor num processo (--host-dir), dois clientes entram (um por IPv6 ::1),
##   status.json mostra os dois, "Tirar" derruba um (que não reconecta), fechar grava o banco e,
##   sem o batimento do jogo, o servidor fecha sozinho.
## * Net: servidores salvos com nome e histórico das conexões.
##
##   godot --headless --path . -s res://tests/host_test.gd [-- <Speedoru.exe exportado>]
## Com o executável, o servidor hospedado roda da build exportada (sem --path), como no jogo.
## Arquivos de teste: user://test_host/ e user://test_host_*.cfg (apagados no fim).

const PORT := 7361
const DIR := "user://test_host"

var failures := 0
var host: LocalHost
var a: Node
var b: Node


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await create_timer(0.05).timeout
		t += 0.05
	return cond.call()


func _client(tag: String) -> Node:
	var holder := Node.new()
	holder.name = "Client" + tag
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var n: Node = load("res://scripts/net/net.gd").new()
	n.name = "Net"
	n.account_file = "user://test_host_%s.cfg" % tag.to_lower()
	n.auto_profile = false
	n.auto_race = false
	holder.add_child(n)
	return n


func _clean() -> void:
	var abs_dir := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		for f in DirAccess.get_files_at(abs_dir):
			DirAccess.remove_absolute(abs_dir.path_join(f))
		DirAccess.remove_absolute(abs_dir)
	for f in ["user://test_host_a.cfg", "user://test_host_b.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _run() -> void:
	_clean()
	_addresses()
	await _store()
	await _hosting()
	_finish()


func _addresses() -> void:
	print("Endereços")
	var cases := [
		["192.168.0.10", "192.168.0.10", 7350], ["192.168.0.10:7400", "192.168.0.10", 7400],
		["meuservidor.com", "meuservidor.com", 7350], ["meuservidor.com:9000", "meuservidor.com", 9000],
		["2001:db8::1", "2001:db8::1", 7350], ["[2001:db8::1]:7400", "2001:db8::1", 7400],
		["[::1]", "::1", 7350], ["  ::1  ", "::1", 7350],
	]
	for c in cases:
		var r := NetProtocol.parse_address(c[0])
		_check(r["host"] == c[1] and r["port"] == c[2], "%s -> %s porta %d" % [c[0], r["host"], r["port"]])
	for bad in ["", "host:abc", "host:70000", "[2001:db8::1", "[::1]x", "a b:7350"]:
		_check(NetProtocol.parse_address(bad)["host"] == "", "inválido recusado: '%s'" % bad)
	_check(NetProtocol.format_address("2001:db8::1", 7350) == "[2001:db8::1]:7350", "IPv6 mostrado entre colchetes")
	_check(NetProtocol.format_address("10.0.0.2", 7350) == "10.0.0.2:7350", "IPv4 mostrado sem colchetes")
	_check(NetProtocol.compact_ipv6("2804:014c:0:0:0:0:0:11a8") == "2804:14c::11a8", "IPv6 compactado (%s)" % NetProtocol.compact_ipv6("2804:014c:0:0:0:0:0:11a8"))
	_check(NetProtocol.compact_ipv6("2001:db8:0:1:0:0:0:1") == "2001:db8:0:1::1", "compacta a maior sequência de zeros")
	_check(NetProtocol.compact_ipv6("0:0:0:0:0:0:0:1") == "::1", "::1")
	_check(NetProtocol.compact_ipv6("2001:db8:1:2:3:4:5:6") == "2001:db8:1:2:3:4:5:6" and NetProtocol.compact_ipv6("10.0.0.1") == "10.0.0.1",
		"sem zeros e IPv4 ficam iguais")
	var round_trip := NetProtocol.parse_address(NetProtocol.format_address("fe80::1", 7401))
	_check(round_trip["host"] == "fe80::1" and round_trip["port"] == 7401, "formatar e ler de volta dá o mesmo endereço")


func _store() -> void:
	print("Banco local")
	var s := LocalStore.new()
	root.add_child(s)
	s.setup_local(ProjectSettings.globalize_path(DIR))
	_check(await s.migrate(), "banco novo criado")
	var acc_a: Variant = await s.login("token-a-0123456789abcdef", "Alice")
	var acc_b: Variant = await s.login("token-b-0123456789abcdef", "Bruno")
	_check(acc_a is Dictionary and acc_b is Dictionary and acc_a["id"] != acc_b["id"], "duas contas")
	_check(not acc_a.has("token_hash"), "o hash do token não sai do banco")
	var again: Variant = await s.login("token-a-0123456789abcdef", "Outro")
	_check(again["id"] == acc_a["id"] and again["name"] == "Alice", "mesmo token entra na mesma conta")
	_check((await s.find_by_code(acc_b["friend_code"]))["id"] == acc_b["id"], "acha pelo código de amigo")
	await s.add_request(acc_a["id"], acc_b["id"])
	_check(await s.has_request(acc_a["id"], acc_b["id"]) and (await s.requests_to(acc_b["id"])) == [acc_a["id"]], "pedido de amizade")
	await s.make_friends(acc_a["id"], acc_b["id"])
	_check(await s.are_friends(acc_b["id"], acc_a["id"]) and await s.count_friends(acc_a["id"]) == 1 and not await s.has_request(acc_a["id"], acc_b["id"]),
		"amizade mútua e pedido limpo")
	acc_a["counters"] = {"wins": 2, "earned": 5000}
	acc_a["best_lap"] = 81.5
	await s.save_account(acc_a)
	for i in 3:
		await s.add_match(acc_a["id"], "solo", {"pos": i + 1})
	var recent: Array = await s.recent_matches(acc_a["id"], 2)
	_check(recent.size() == 2 and int(recent[0]["pos"]) == 3 and recent[0]["kind"] == "solo", "últimas corridas, a mais nova primeiro")
	_check(s.flush(), "gravou o arquivo")
	s.queue_free()
	# Relê do arquivo
	var s2 := LocalStore.new()
	root.add_child(s2)
	s2.setup_local(ProjectSettings.globalize_path(DIR))
	_check(await s2.migrate(), "banco relido")
	var back: Variant = await s2.get_account(acc_a["id"])
	_check(back != null and int(back["counters"]["wins"]) == 2 and is_equal_approx(back["best_lap"], 81.5), "conta voltou igual do arquivo")
	_check(await s2.are_friends(acc_a["id"], acc_b["id"]) and (await s2.recent_matches(acc_a["id"], 5)).size() == 3, "amizades e histórico voltaram")
	var rows: Array = await s2.ranking_rows()
	_check(rows.size() == 2, "ranking vê as duas contas")
	s2.queue_free()
	await process_frame
	_clean()


func _hosting() -> void:
	print("Hospedar")
	host = LocalHost.new()
	host.dir = DIR
	host.auto_join = false
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		host.executable = user_args[0]
		print("Servidor da build exportada: ", host.executable)
	root.add_child(host)
	_check(host.start(PORT), "processo do servidor aberto")
	var up := await _wait_for(func() -> bool: return host.is_running(), 60.0)
	_check(up, "servidor no ar (status.json da mesma sessão)")
	if not up:
		print("\n".join(host.log_lines))
		host.stop()
		return
	_check(host.log_lines.any(func(l: String) -> bool: return l.contains("ouvindo na porta %d" % PORT)), "log do processo chega ao jogo")
	_check(host.log_lines.any(func(l: String) -> bool: return l.contains("banco local")), "servidor usa o banco local")
	a = _client("A")
	b = _client("B")
	a.connect_to_server("127.0.0.1", PORT)
	# IPv6: o servidor escuta nos dois
	b.connect_to_server("::1", PORT)
	var ok := await _wait_for(func() -> bool: return a.online and b.online, 20.0)
	_check(a.online, "cliente A entrou por IPv4 (127.0.0.1)")
	_check(b.online, "cliente B entrou por IPv6 (::1)")
	if ok:
		var seen := await _wait_for(func() -> bool: return (host.status.get("players", []) as Array).size() == 2, 5.0)
		_check(seen, "status mostra os dois jogadores")
		_check(int(host.status.get("accounts", 0)) == 2, "status conta as contas do banco")
		# Histórico e salvos
		var hist: Array = a.server_history()
		_check(hist.size() == 1 and hist[0]["host"] == "127.0.0.1" and int(hist[0]["port"]) == PORT, "conexão entrou no histórico")
		_check(b.server_history()[0]["host"] == "::1", "histórico guarda o IPv6")
		a.save_server("Casa do Teste", "2001:db8::5", 7400)
		a.save_server("Casa do Teste (novo nome)", "2001:db8::5", 7400)
		a.save_server("", "10.0.0.9", 7350)
		var saved: Array = a.saved_servers()
		_check(saved.size() == 2 and a.server_name("2001:db8::5", 7400) == "Casa do Teste (novo nome)", "salvar de novo renomeia em vez de duplicar")
		_check(a.server_name("10.0.0.9", 7350) == "10.0.0.9:7350", "sem nome, usa o endereço")
		a.forget_server("10.0.0.9", 7350)
		_check(a.saved_servers().size() == 1, "remover servidor salvo")
		# Tirar o B
		var b_id: String = b.account["id"]
		host.kick(b_id)
		var gone := await _wait_for(func() -> bool: return not b.online, 8.0)
		_check(gone, "B foi tirado do servidor")
		_check(str(b.last_error).contains("anfitrião"), "B vê o motivo (%s)" % b.last_error)
		await create_timer(6.0).timeout
		_check(not b.online and not b._connecting, "B não reconecta sozinho")
		_check(a.online, "A continua no servidor")
	# Fechar
	host.stop()
	var down := await _wait_for(func() -> bool: return host.state == LocalHost.State.STOPPED, 15.0)
	_check(down, "servidor fechou")
	_check(host.log_lines.any(func(l: String) -> bool: return l.contains("fechando")), "fechou pelo comando (gravando o banco)")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(DIR).path_join(LocalStore.FILE)))
	_check(data is Dictionary and (data["accounts"] as Array).size() == 2, "banco do host gravado com as duas contas")
	await create_timer(1.0).timeout
	_check(a == null or not a.online, "A caiu junto com o servidor")
	# O jogo some (para de bater e o arquivo alive some): o servidor fecha sozinho
	_check(host.start(PORT + 1), "abriu de novo (outra porta)")
	if await _wait_for(func() -> bool: return host.is_running(), 60.0):
		host.process_mode = Node.PROCESS_MODE_DISABLED
		DirAccess.remove_absolute(host.host_dir_abs().path_join(HostControl.ALIVE))
		await create_timer(3.0).timeout
		host.process_mode = Node.PROCESS_MODE_INHERIT
		var closed := await _wait_for(func() -> bool: return host.state == LocalHost.State.STOPPED, 8.0)
		_check(closed and host.log_lines.any(func(l: String) -> bool: return l.contains("o jogo que abriu o servidor fechou")),
			"sem o batimento do jogo, o servidor fecha sozinho")
	if failures > 0:
		print("--- log do servidor
" + "
".join(host.log_lines))


func _finish() -> void:
	if host and host.is_active():
		host.stop()
		await _wait_for(func() -> bool: return host.state == LocalHost.State.STOPPED, 10.0)
	_clean()
	print("\nhost_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)
