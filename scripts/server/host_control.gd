class_name HostControl
extends Node
## Controle do servidor aberto pelo próprio jogo (LocalHost no cliente; GameServer com --host-dir=).
## Fala com o jogo por arquivos na pasta do host, sem depender da rede:
##
## * status.json (o servidor grava a cada segundo): sessão, pid, porta, tempo no ar, jogadores,
##   salas e contas do banco.
## * cmd_<n>.json (o jogo cria; o servidor executa em ordem e apaga): {"cmd": "stop"} e
##   {"cmd": "kick", "id": conta}.
## * alive (o jogo grava a hora a cada 2 s; com --host-watch): se parar de bater por WATCH_TIMEOUT s,
##   o jogo que abriu o servidor fechou ou travou, e o servidor fecha sozinho gravando o banco.

const STATUS := "status.json"
const CMD_PREFIX := "cmd_"
const ALIVE := "alive"
const TICK := 0.5
## Sem batimento do jogo por este tempo: fecha (o jogo pode travar alguns segundos carregando pista).
const WATCH_TIMEOUT := 30

var server: GameServer
var dir := ""
var port := 0
var watch := false
var session := ""

var _t := 0.0
var _started := 0
var _ticks := 0


func setup(p_server: GameServer, p_dir: String, p_port: int, p_watch: bool, p_session: String) -> void:
	server = p_server
	dir = p_dir
	port = p_port
	watch = p_watch
	session = p_session
	_started = int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(dir)


func _ready() -> void:
	write_status()


func _process(delta: float) -> void:
	_t += delta
	if _t < TICK:
		return
	_t = 0.0
	_ticks += 1
	_read_commands()
	if _ticks % 2 == 0:
		write_status()
		if watch and _host_gone():
			print("Servidor: o jogo que abriu o servidor fechou")
			server.shutdown()


## O jogo parou de gravar o batimento (ou apagou o arquivo).
func _host_gone() -> bool:
	var path := dir.path_join(ALIVE)
	if not FileAccess.file_exists(path):
		return true
	var t := FileAccess.get_file_as_string(path).strip_edges().to_int()
	return t > 0 and int(Time.get_unix_time_from_system()) - t > WATCH_TIMEOUT


func write_status(state := "running") -> void:
	var counts := server.room_counts()
	var local := server.store as LocalStore
	var data := {
		"session": session, "pid": OS.get_process_id(), "port": port, "state": state,
		"started": _started, "uptime": int(Time.get_unix_time_from_system()) - _started,
		"players": server.players_online(), "rooms": counts.x, "racing": counts.y,
		"accounts": local.account_count() if local else -1, "version": NetProtocol.VERSION,
	}
	var tmp := dir.path_join(STATUS + ".tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	# Se o jogo estiver lendo o arquivo agora, a troca falha: tenta de novo no próximo segundo
	DirAccess.rename_absolute(tmp, dir.path_join(STATUS))


func _read_commands() -> void:
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool:
		return f.begins_with(CMD_PREFIX) and f.ends_with(".json"))
	# Em ordem: cmd_<n>.json com n crescente
	files.sort_custom(func(a: String, b: String) -> bool:
		return a.trim_prefix(CMD_PREFIX).to_int() < b.trim_prefix(CMD_PREFIX).to_int())
	for f: String in files:
		var full := dir.path_join(f)
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(full))
		DirAccess.remove_absolute(full)
		if data is Dictionary:
			_run(data)


func _run(cmd: Dictionary) -> void:
	match str(cmd.get("cmd", "")):
		"stop":
			write_status("stopped")
			server.shutdown()
		"kick":
			var id := str(cmd.get("id", ""))
			if await server.kick_account(id):
				print("Servidor: jogador %s removido pelo anfitrião" % id)
			write_status()
