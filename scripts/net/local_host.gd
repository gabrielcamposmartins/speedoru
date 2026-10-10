class_name LocalHost
extends Node
## Servidor aberto pelo próprio jogo ("Hospedar" na tela de multiplayer; filho do autoload Net no
## cliente). Sobe o servidor dedicado num processo à parte (o mesmo executável, sem janela, com
## --server --host-dir=…): banco num arquivo da pasta do host (LocalStore), sem Turso.
##
## * Controle por arquivos (HostControl): status.json a cada segundo, cmd_<n>.json para fechar
##   e tirar jogadores. O jogo grava a hora em "alive" a cada 2 s; se parar (jogo fechou ou
##   travou), o servidor fecha sozinho gravando o banco (--host-watch).
## * Log: a saída do processo (pipe) e o arquivo server.log na pasta do host.
## * Endereços para passar aos amigos: rede local (IPv4/IPv6), IPv6 público e, se pedido, a porta
##   aberta no roteador por UPnP (com o IP externo).

signal changed
signal log_added(line: String)

enum State { STOPPED, STARTING, RUNNING, STOPPING }
const STATE_NAMES := ["Parado", "Abrindo…", "No ar", "Fechando…"]
const LOG_MAX := 200
## Tempo para o servidor ficar pronto (carrega o jogo sem janela) e para fechar sozinho.
const START_TIMEOUT := 40.0
const STOP_TIMEOUT := 6.0
const HOST_DIR := "user://host"

var state := State.STOPPED
## Pasta do host (banco, estado, comandos, log). Os testes usam outra.
var dir := HOST_DIR
var port := NetProtocol.DEFAULT_PORT
## Entrar no próprio servidor quando ele ficar no ar.
var auto_join := true
## Outro executável do jogo exportado para o servidor ("" = este mesmo; os testes usam para conferir
## uma build exportada).
var executable := ""
## Último status.json do servidor ({} parado).
var status := {}
var log_lines: Array[String] = []
## Último erro (porta ocupada, processo caiu…), para a tela.
var last_error := ""
## UPnP: "" (não pedido), "abrindo", "aberta", "falhou"; texto e IP externo.
var upnp_state := ""
var upnp_text := ""
var external_ip := ""

var _pid := -1
var _stdio: FileAccess
var _stderr: FileAccess
var _bytes := PackedByteArray()
var _session := ""
var _timer := 0.0
var _poll := 0.0
var _cmd_seq := 0
var _beat := 0
var _joined := false
var _upnp: UPNP
var _upnp_thread: Thread


func is_running() -> bool:
	return state == State.RUNNING


func is_active() -> bool:
	return state != State.STOPPED


func state_name() -> String:
	return STATE_NAMES[state]


func host_dir_abs() -> String:
	return ProjectSettings.globalize_path(dir)


## Linha de comando do servidor: o mesmo executável; fora do jogo exportado, com o projeto.
func command(p_port: int) -> PackedStringArray:
	var abs_dir := host_dir_abs()
	var args := PackedStringArray()
	if not OS.has_feature("template") and executable == "":
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--headless", "--log-file", abs_dir.path_join("server.log"), "--",
		"--server", "--port=%d" % p_port, "--host-dir=" + abs_dir, "--host-watch",
		"--host-session=" + _session])
	return args


## Abre o servidor nesta porta. Devolve se o processo subiu (fica "Abrindo…" até responder).
func start(p_port: int, open_router := false) -> bool:
	if is_active():
		return false
	port = p_port if p_port > 0 and p_port < 65536 else NetProtocol.DEFAULT_PORT
	last_error = ""
	status = {}
	_joined = false
	_session = Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(host_dir_abs())
	# Restos de uma sessão anterior
	for f in DirAccess.get_files_at(host_dir_abs()):
		if f == HostControl.STATUS or f.begins_with(HostControl.CMD_PREFIX):
			DirAccess.remove_absolute(host_dir_abs().path_join(f))
	_heartbeat()
	var proc := OS.execute_with_pipe(executable if executable != "" else OS.get_executable_path(), command(port), false)
	if proc.is_empty() or int(proc.get("pid", -1)) <= 0:
		last_error = "Não deu para abrir o processo do servidor."
		changed.emit()
		return false
	_pid = int(proc["pid"])
	_stdio = proc.get("stdio")
	_stderr = proc.get("stderr")
	_bytes = PackedByteArray()
	_add_log("— abrindo o servidor na porta %d (processo %d)" % [port, _pid])
	_set_state(State.STARTING)
	_timer = START_TIMEOUT
	if open_router:
		open_upnp()
	return true


## Fecha o servidor (grava o banco antes). Se não fechar sozinho em alguns segundos, mata o processo.
func stop() -> void:
	if state == State.STOPPED or state == State.STOPPING:
		return
	_send_command({"cmd": "stop"})
	_set_state(State.STOPPING)
	_timer = STOP_TIMEOUT
	close_upnp()


## Tira um jogador (todas as abas da conta) do servidor.
func kick(account_id: String) -> void:
	if is_running():
		_send_command({"cmd": "kick", "id": account_id})


func _send_command(cmd: Dictionary) -> void:
	_cmd_seq += 1
	var base := host_dir_abs().path_join("%s%d" % [HostControl.CMD_PREFIX, _cmd_seq])
	var f := FileAccess.open(base + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(cmd))
	f.close()
	DirAccess.rename_absolute(base + ".tmp", base + ".json")


func _set_state(s: State) -> void:
	state = s
	changed.emit()


func _process(delta: float) -> void:
	if state == State.STOPPED:
		return
	_read_output()
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.5
	_timer -= 0.5
	_beat += 1
	if _beat % 4 == 0:
		_heartbeat()
	if not OS.is_process_running(_pid):
		_on_exited()
		return
	_read_status()
	match state:
		State.STARTING:
			if _timer <= 0.0:
				last_error = "O servidor não respondeu a tempo."
				_kill()
		State.STOPPING:
			if _timer <= 0.0:
				_kill()


func _heartbeat() -> void:
	var f := FileAccess.open(host_dir_abs().path_join(HostControl.ALIVE), FileAccess.WRITE)
	if f:
		f.store_string(str(int(Time.get_unix_time_from_system())))
		f.close()


func _read_status() -> void:
	var path := host_dir_abs().path_join(HostControl.STATUS)
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or str(data.get("session", "")) != _session:
		return
	# Só avisa a tela quando muda algo além do tempo no ar (a tela conta o tempo sozinha)
	var before := status.duplicate()
	before.erase("uptime")
	status = data
	var after := status.duplicate()
	after.erase("uptime")
	if state == State.STARTING and str(data.get("state", "")) == "running":
		_add_log("— servidor no ar")
		_set_state(State.RUNNING)
		if auto_join:
			_join()
	elif JSON.stringify(before) != JSON.stringify(after):
		changed.emit()


## Entra no próprio servidor (sem trocar o servidor padrão salvo).
func _join() -> void:
	var net := get_parent()
	if net and net.has_method("switch_server"):
		_joined = true
		net.switch_server("127.0.0.1", port, false)


func _on_exited() -> void:
	_read_output()
	var code := OS.get_process_exit_code(_pid)
	if state == State.STARTING and last_error == "":
		last_error = "Porta %d ocupada (outro servidor aberto?)." % port if code == 3 else "O servidor fechou ao abrir (código %d). Veja o log." % code
	elif state == State.RUNNING:
		last_error = "O servidor caiu (código %d). Veja o log." % code
	_add_log("— servidor fechado (código %d)" % code)
	_pid = -1
	_stdio = null
	_stderr = null
	status = {}
	close_upnp()
	_set_state(State.STOPPED)
	# Estava jogando no próprio servidor: volta para o servidor padrão
	var net := get_parent()
	if _joined and net and net.has_method("set_server"):
		_joined = false
		if net.server_host == "127.0.0.1" and net.server_port == port:
			var cfg := ConfigFile.new()
			cfg.load(net.account_file)
			net.switch_server(str(cfg.get_value("server", "host", NetProtocol.DEFAULT_HOST)),
				int(cfg.get_value("server", "port", NetProtocol.DEFAULT_PORT)), false)


func _kill() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)


func _read_output() -> void:
	for pipe: FileAccess in [_stdio, _stderr]:
		if pipe == null:
			continue
		for i in 16:
			var chunk := pipe.get_buffer(4096)
			if chunk.is_empty():
				break
			_bytes.append_array(chunk)
	var nl := _bytes.find(10)
	while nl >= 0:
		var line := _bytes.slice(0, nl).get_string_from_utf8().strip_edges()
		_bytes = _bytes.slice(nl + 1)
		if line != "":
			_add_log(line)
		nl = _bytes.find(10)


func _add_log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > LOG_MAX:
		log_lines = log_lines.slice(log_lines.size() - LOG_MAX)
	log_added.emit(line)


func _exit_tree() -> void:
	# O jogo está fechando: o servidor grava e fecha (também fecharia sozinho, sem o batimento)
	if state != State.STOPPED:
		_send_command({"cmd": "stop"})
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp and upnp_state == "aberta":
		_upnp.delete_port_mapping(port, "UDP")
		_upnp = null


# ---------------------------------------------------------------------------
# Endereços para os amigos
# ---------------------------------------------------------------------------
## [{label, address}]: rede local (IPv4 privado, IPv6 local) e internet (IPv6 público, IP externo
## do UPnP). Os IPv6 temporários de privacidade aparecem também; qualquer um serve.
func addresses() -> Array:
	var out := []
	var v6 := 0
	for ip: String in IP.get_local_addresses():
		if ip.contains(":"):
			ip = NetProtocol.compact_ipv6(ip)
			var low := ip.to_lower()
			if low == "::1" or low.begins_with("fe80") or low.contains("%"):
				continue
			if low.begins_with("fc") or low.begins_with("fd"):
				out.append({"label": "Rede local (IPv6)", "address": NetProtocol.format_address(ip, port)})
			elif (low.begins_with("2") or low.begins_with("3")) and v6 < 3:
				v6 += 1
				out.append({"label": "Internet (IPv6)", "address": NetProtocol.format_address(ip, port)})
		elif not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append({"label": "Rede local" if _private_v4(ip) else "Internet", "address": NetProtocol.format_address(ip, port)})
	if external_ip != "":
		out.append({"label": "Internet (roteador, UPnP)", "address": NetProtocol.format_address(external_ip, port)})
	return out


static func _private_v4(ip: String) -> bool:
	var p := ip.split(".")
	if p.size() != 4:
		return false
	var a := p[0].to_int()
	var b := p[1].to_int()
	return a == 10 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31) or (a == 100 and b >= 64 and b <= 127)


# ---------------------------------------------------------------------------
# UPnP (abre a porta UDP no roteador; numa thread, a busca leva uns segundos)
# ---------------------------------------------------------------------------
func open_upnp() -> void:
	if _upnp_thread or upnp_state == "aberta":
		return
	upnp_state = "abrindo"
	upnp_text = "Procurando o roteador…"
	changed.emit()
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_open.bind(port))


func close_upnp() -> void:
	# Ainda procurando: _upnp_done fecha a porta se o servidor já tiver parado
	if upnp_state == "abrindo":
		return
	var u := _upnp
	var was_open := upnp_state == "aberta"
	_upnp = null
	upnp_state = ""
	upnp_text = ""
	external_ip = ""
	if was_open and u and _upnp_thread == null:
		_upnp_thread = Thread.new()
		_upnp_thread.start(_upnp_close.bind(u, port))


func _upnp_open(p: int) -> void:
	var u := UPNP.new()
	var err := u.discover(2000, 2, "InternetGatewayDevice")
	var result := {"ok": false, "upnp": u}
	if err != UPNP.UPNP_RESULT_SUCCESS or u.get_gateway() == null or not u.get_gateway().is_valid_gateway():
		result["text"] = "Roteador sem UPnP (ou desligado). Abra a porta UDP %d à mão ou use IPv6." % p
	else:
		var r := u.add_port_mapping(p, p, "Speedoru", "UDP", 0)
		if r != UPNP.UPNP_RESULT_SUCCESS:
			result["text"] = "O roteador recusou abrir a porta %d (erro %d)." % [p, r]
		else:
			result["ok"] = true
			result["ip"] = u.query_external_address()
			result["text"] = "Porta UDP %d aberta no roteador." % p
	_upnp_done.call_deferred(result)


func _upnp_done(result: Dictionary) -> void:
	_upnp_thread.wait_to_finish()
	_upnp_thread = null
	if result["ok"]:
		_upnp = result["upnp"]
		external_ip = str(result.get("ip", ""))
		upnp_state = "aberta"
		# O servidor fechou enquanto procurava: fecha a porta de novo
		if state == State.STOPPED or state == State.STOPPING:
			close_upnp()
	else:
		upnp_state = "falhou"
	upnp_text = str(result["text"])
	_add_log("— UPnP: " + upnp_text)
	changed.emit()


func _upnp_close(u: UPNP, p: int) -> void:
	u.delete_port_mapping(p, "UDP")
	(func() -> void:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null).call_deferred()
