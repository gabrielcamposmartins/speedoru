extends Node
## Rede (autoload "Net"): o mesmo nó existe no cliente e no servidor dedicado, porque os RPCs do
## Godot precisam do mesmo caminho dos dois lados.
##
## Cliente: conecta ao servidor (ENet), entra com o token do aparelho (user://account.cfg, criado
## na primeira vez) e espelha a conta no Profile (modo "remote": créditos, coleção e giros só mudam
## pelo servidor). As telas usam request() e os sinais. Se o servidor não responde, o jogo segue
## offline (Profile local; sem loja, sem multiplayer).
## Servidor: o GameServer chama Net.host() e recebe as mensagens por handler.

signal connection_changed(online: bool)
signal message(type: String, data: Dictionary)
signal account_changed
signal race_snapshot(data: PackedByteArray)
signal race_state(data: Dictionary)

const ACCOUNT_FILE := "user://account.cfg"

var is_server := false
var online := false
var account := {}
## Sala e grupo atuais ({} = nenhum), como o servidor mandou por último.
var room := {}
var party := {}
## Último erro de conexão (versão diferente, banco fora do ar…), para a tela de multiplayer.
var last_error := ""
## Servidor: quem recebe as mensagens (GameServer).
var handler: Object
var server_host := NetProtocol.DEFAULT_HOST
var server_port := NetProtocol.DEFAULT_PORT
## Arquivo com o token da conta deste aparelho. --account=nome usa outro (dois jogos no mesmo PC).
var account_file := ACCOUNT_FILE
## Espelha a conta no autoload Profile (os testes com vários clientes no mesmo processo desligam).
var auto_profile := true
## Troca para a cena da corrida quando a sala larga (os testes desligam).
var auto_race := true

var _peer: ENetMultiplayerPeer
var _pending := {}
var _req_seq := 0
var _equip_timer := 0.0
var _equip_pending: Variant = null
var _retry := 0.0
var _connecting := false
var _local_owned := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	is_server = "--server" in args
	for a in args:
		if a.begins_with("--account="):
			account_file = "user://account_%s.cfg" % a.substr(10).validate_filename()
	var cfg := ConfigFile.new()
	if cfg.load(account_file) == OK:
		server_host = str(cfg.get_value("server", "host", server_host))
		server_port = int(cfg.get_value("server", "port", server_port))
	for a in args:
		if a.begins_with("--connect="):
			var hp := a.substr(10).split(":")
			server_host = hp[0]
			if hp.size() > 1:
				server_port = int(hp[1])
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_disconnected)
	if not is_server and DisplayServer.get_name() != "headless" and not "--offline" in args:
		connect_to_server.call_deferred()


# ---------------------------------------------------------------------------
# Servidor
# ---------------------------------------------------------------------------
func host(port: int, p_handler: Object) -> Error:
	handler = p_handler
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, NetProtocol.MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = _peer
	multiplayer.peer_connected.connect(func(id: int) -> void: handler.on_peer_connected(id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void: handler.on_peer_disconnected(id))
	return OK


func send(peer: int, type: String, data: Dictionary = {}) -> void:
	if multiplayer.multiplayer_peer and peer in multiplayer.get_peers():
		msg.rpc_id(peer, type, data)


# ---------------------------------------------------------------------------
# Cliente
# ---------------------------------------------------------------------------
func connect_to_server(host_name := "", port := 0) -> void:
	if is_server or _connecting or online:
		return
	if host_name != "":
		server_host = host_name
	if port > 0:
		server_port = port
	_connecting = true
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_client(server_host, server_port) != OK:
		_connecting = false
		_retry = 10.0
		return
	multiplayer.multiplayer_peer = _peer


## Endereço do servidor escolhido na tela de multiplayer (fica salvo neste aparelho).
func set_server(host_name: String, port: int) -> void:
	server_host = host_name.strip_edges()
	server_port = port if port > 0 else NetProtocol.DEFAULT_PORT
	var cfg := ConfigFile.new()
	cfg.load(account_file)
	cfg.set_value("server", "host", server_host)
	cfg.set_value("server", "port", server_port)
	cfg.save(account_file)


func disconnect_from_server() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_set_online(false)


func _on_connected() -> void:
	_connecting = false
	var cfg := ConfigFile.new()
	cfg.load(account_file)
	var token := str(cfg.get_value("account", "token", ""))
	if token == "":
		token = Crypto.new().generate_random_bytes(24).hex_encode()
		cfg.set_value("account", "token", token)
		cfg.save(account_file)
	var name := str(cfg.get_value("account", "name", "Jogador"))
	var hello := {"version": NetProtocol.VERSION, "token": token, "name": name}
	# O carro deste aparelho (visual e engenharia) vai junto: o servidor o usa nas corridas
	var profile := get_node_or_null("/root/Profile") as PlayerProfile if auto_profile else null
	if profile and profile.mode == "local":
		hello["car"] = profile.equipped.duplicate(true)
		_local_owned = profile.owned.duplicate()
	msg.rpc_id(1, "hello", hello)


func _on_failed() -> void:
	_connecting = false
	multiplayer.multiplayer_peer = null
	_retry = 15.0


func _on_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	_set_online(false)
	_retry = 5.0


func _set_online(value: bool) -> void:
	if online == value:
		return
	online = value
	if online:
		last_error = ""
	else:
		room = {}
		party = {}
	var profile := get_node_or_null("/root/Profile") as PlayerProfile if auto_profile else null
	if profile:
		if online:
			profile.mode = "remote"
			# Servidor que aceita o carro do aparelho: a coleção local também vale para montar o carro
			profile.extra_owned = _local_owned.duplicate() if bool(account.get("trust_car", false)) else {}
			if not profile.equip_requested.is_connected(_on_equip_requested):
				profile.equip_requested.connect(_on_equip_requested)
		else:
			# Offline: volta ao perfil local do aparelho
			profile.mode = "local"
			profile.extra_owned = {}
			profile.load_profile()
			profile.changed.emit()
	connection_changed.emit(online)


func _process(delta: float) -> void:
	if is_server:
		return
	if not online and not _connecting and _retry > 0.0:
		_retry -= delta
		if _retry <= 0.0:
			connect_to_server()
	# Equipamento: junta os cliques (sliders da engenharia) e manda no máximo 3 vezes por segundo
	if _equip_pending != null:
		_equip_timer -= delta
		if _equip_timer <= 0.0:
			send_to_server("equip", {"equipped": _equip_pending})
			_equip_pending = null


func _on_equip_requested(equipped: Dictionary) -> void:
	_equip_pending = equipped
	if _equip_timer <= 0.0:
		_equip_timer = 0.33


## Latência (ida e volta até o servidor, ms, média do ENet); -1 sem conexão.
func ping_ms() -> int:
	if is_server or not online or _peer == null:
		return -1
	var server := _peer.get_peer(1)
	if server == null:
		return -1
	return int(server.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


func send_to_server(type: String, data: Dictionary = {}) -> void:
	if online or type == "hello":
		msg.rpc_id(1, type, data)


## Pedido com resposta: manda type com um id e espera a mensagem de resposta com o mesmo id.
## Devolve o data da resposta ({"ok": false, "error": ...} se cair a conexão ou demorar 10 s).
func request(type: String, data: Dictionary = {}) -> Dictionary:
	if not online:
		return {"ok": false, "error": "Sem conexão com o servidor."}
	_req_seq += 1
	var id := _req_seq
	data = data.duplicate()
	data["req"] = id
	_pending[id] = null
	send_to_server(type, data)
	var waited := 0.0
	while _pending.get(id) == null and waited < 10.0 and online:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var reply: Variant = _pending.get(id)
	_pending.erase(id)
	if reply == null:
		return {"ok": false, "error": "O servidor não respondeu."}
	return reply


## Nome guardado no aparelho (também mandado ao servidor no próximo login).
func set_local_name(name: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(account_file)
	cfg.set_value("account", "name", NetProtocol.clean_name(name))
	cfg.save(account_file)


# ---------------------------------------------------------------------------
# RPCs (mesmos nos dois lados)
# ---------------------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func msg(type: String, data: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if is_server:
		if handler:
			handler.on_message(sender, type, data)
		return
	if sender != 1:
		return
	match type:
		"welcome", "account":
			account = data.get("account", {})
			var profile := get_node_or_null("/root/Profile") as PlayerProfile if auto_profile else null
			if type == "welcome":
				_set_online(true)
			if profile and account.has("profile"):
				profile.from_dict(account["profile"])
			account_changed.emit()
		"room":
			room = data.get("room", {})
		"party":
			party = data.get("party", {})
		"error":
			if not data.has("req"):
				last_error = str(data.get("error", ""))
		"race_start":
			if auto_race:
				_enter_race(data)
	if data.has("req") and _pending.has(int(data["req"])):
		_pending[int(data["req"])] = data
	message.emit(type, data)


## A sala largou: monta a corrida em rede (mesma pista, mesmos carros) e troca de cena.
func _enter_race(data: Dictionary) -> void:
	var st: Dictionary = data.get("settings", {})
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = int(st.get("laps", 5))
	RaceSettings.time_of_day = int(st.get("time_of_day", 0))
	RaceSettings.biome = int(st.get("biome", 0))
	RaceSettings.skip_menu = false
	RaceSettings.track = RaceSettings.valid_track(str(st.get("track", "monza")))
	RaceManager.client_setup = data
	var scene := RaceSettings.track_scene(RaceSettings.track)
	var loading := get_node_or_null("/root/Loading") as LoadingScreen
	if loading:
		loading.change_scene(scene)
	else:
		get_tree().change_scene_to_file(scene)


## Comandos do carro (cliente → servidor), contínuos.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func inp(data: PackedFloat32Array) -> void:
	if is_server and handler:
		handler.on_input(multiplayer.get_remote_sender_id(), data)


## Instantâneo de todos os carros (servidor → cliente).
@rpc("authority", "call_remote", "unreliable")
func snap(data: PackedByteArray) -> void:
	race_snapshot.emit(data)


## Estado da prova (posições, voltas, bandeira…), servidor → cliente.
@rpc("authority", "call_remote", "reliable")
func race(data: Dictionary) -> void:
	race_state.emit(data)
