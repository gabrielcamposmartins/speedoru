class_name RaceSession
extends Node
## Uma corrida em rede rodando no servidor dedicado (servidor autoritativo).
##
## A cena do circuito roda dentro de um SubViewport com mundo 3D próprio (cada sala tem a sua
## física, sem interferir nas outras). O RaceManager em modo SERVER monta o grid com os humanos
## (carros com o visual e a engenharia das contas) e bots; aqui chegam as entradas dos jogadores,
## saem os instantâneos (30/s), o estado da prova (5/s) e os acontecimentos; no fim, os resultados
## voltam ao GameServer, que paga e registra.

signal finished(results: Array)

const SCENE := "res://scenes/tracks/monza.tscn"
const LOAD_TIMEOUT := 45.0
## Depois que o primeiro humano termina, os outros têm esse tempo (s) para cruzar a linha.
const FINISH_TIMEOUT := 150.0
const END_DELAY := 5.0

var server: GameServer
var room_id := ""
var settings := {}
## [{id, name, peers, profile}]
var players: Array = []
var manager: RaceManager
var viewport: SubViewport

var _inputs := {}
var _last_counts := {}
var _loaded := {}
var _left := {}
var _phase := "loading"
var _wait := 0.0
var _t := 0.0
var _snap_acc := 0.0
var _state_acc := 0.0
var _first_finish := -1.0
var _end_timer := -1.0
var _net: Node


func start(p_server: GameServer, p_room: String, p_settings: Dictionary, p_players: Array) -> void:
	server = p_server
	_net = get_node("/root/Net")
	room_id = p_room
	settings = p_settings
	players = p_players
	viewport = SubViewport.new()
	viewport.name = "World"
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.size = Vector2i(2, 2)
	add_child(viewport)
	var scene := (load(SCENE) as PackedScene).instantiate()
	# Nada de câmera, HUD nem céu no servidor
	for n in ["HUD", "RaceCamera", "Daylight"]:
		var node := scene.get_node_or_null(n)
		if node:
			scene.remove_child(node)
			node.free()
	manager = scene.get_node("RaceManager") as RaceManager
	var list := []
	for p in players:
		list.append({"id": p["id"], "name": p["name"], "profile": p["profile"]})
	manager.net_setup = {"laps": settings.get("laps", 5), "difficulty": settings.get("difficulty", 1),
		"bots": settings.get("bots", true), "players": list}
	manager.net_grid_ready.connect(_on_grid_ready)
	manager.net_event.connect(_broadcast_event)
	manager.infraction.connect(_on_infraction)
	viewport.add_child(scene)


func _peers() -> Array:
	var out := []
	for p in players:
		if _left.has(p["id"]):
			continue
		for peer in server.online.get(p["id"], []):
			if not server._gone.has(peer):
				out.append(peer)
	return out


func _peers_of(acc_id: String) -> Array:
	return [] if _left.has(acc_id) else server.online.get(acc_id, [])


func _on_grid_ready() -> void:
	_phase = "waiting"
	_wait = 0.0
	var roster := manager.net_roster()
	var race_settings := {"laps": manager.laps, "time_of_day": settings.get("time_of_day", 0),
		"biome": settings.get("biome", 0), "difficulty": settings.get("difficulty", 1)}
	for p in players:
		for peer in _peers_of(p["id"]):
			server._send(peer, "race_start", {"room": room_id, "me": p["id"], "roster": roster, "settings": race_settings})


func _go() -> void:
	if _phase != "waiting":
		return
	_phase = "racing"
	manager.net_go()


func set_input(acc_id: String, data: PackedFloat32Array) -> void:
	if data.size() >= 14:
		_inputs[acc_id] = data


func command(acc_id: String, cmd: String, data: Dictionary) -> void:
	var e: RaceEntry = manager.humans.get(acc_id) if manager else null
	match cmd:
		"loaded":
			_loaded[acc_id] = true
			if _all_loaded():
				_go()
		"go_to_pit":
			if e and manager.control and manager.control.is_involved(e):
				manager.control.send_to_pit(e)
		"pit_compound":
			if e:
				e.pit_compound = clampi(int(data.get("value", 2)), 0, 2) as CarConfig.TyreCompound
		"quit":
			player_left(acc_id)


func _all_loaded() -> bool:
	for p in players:
		if not _loaded.has(p["id"]) and not _left.has(p["id"]):
			return false
	return true


## Saiu da sala ou da corrida: o carro abandona (DNF).
func player_left(acc_id: String) -> void:
	_left[acc_id] = true
	var e: RaceEntry = manager.humans.get(acc_id) if manager else null
	if e and not e.finished and not e.retired:
		manager.retire(e)
	if _phase == "waiting" and _all_loaded():
		_go()


func stop() -> void:
	_phase = "done"
	queue_free()


func _physics_process(delta: float) -> void:
	if manager == null or _phase == "done":
		return
	_t += delta
	if _phase == "waiting":
		_wait += delta
		if _wait > LOAD_TIMEOUT:
			_go()
	_apply_inputs()
	_snap_acc += delta
	if _snap_acc >= 1.0 / NetProtocol.SNAPSHOT_HZ and not manager.roster.is_empty():
		_snap_acc = 0.0
		var bytes := NetSnapshot.encode(_t, manager.roster)
		for peer in _peers():
			_net.snap.rpc_id(peer, bytes)
	_state_acc += delta
	if _state_acc >= 1.0 / NetProtocol.RACE_STATE_HZ and _phase != "loading":
		_state_acc = 0.0
		var st := manager.net_state()
		for peer in _peers():
			_net.race.rpc_id(peer, st)
	if _phase == "racing":
		_check_end(delta)


func _apply_inputs() -> void:
	for acc_id in manager.humans:
		var e: RaceEntry = manager.humans[acc_id]
		var car := e.car
		if e.retired or _left.has(acc_id):
			car.throttle_input = 0.0
			car.brake_input = 1.0
			car.steer_input = 0.0
			continue
		var d: Variant = _inputs.get(acc_id)
		if d == null:
			continue
		var inp: PackedFloat32Array = d
		car.throttle_input = clampf(inp[1], 0.0, 1.0)
		car.brake_input = clampf(inp[2], 0.0, 1.0)
		# No manual a ré é uma marcha (a tecla de ré não faz nada)
		car.reverse_input = clampf(inp[3], 0.0, 1.0) if car.automatic else 0.0
		car.steer_input = clampf(inp[4], -1.0, 1.0)
		var buttons := int(inp[5])
		car.drs_requested = buttons & NetProtocol.BTN_DRS != 0
		car.boost_input = buttons & NetProtocol.BTN_BOOST != 0
		var counts := inp.slice(6, 14)
		var last: Variant = _last_counts.get(acc_id)
		_last_counts[acc_id] = counts
		if last == null:
			continue
		for k in 8:
			var times := clampi(int(counts[k] - last[k]), 0, 3)
			for _i in times:
				_action(car, k)


func _action(car: F1Car, k: int) -> void:
	match k:
		0:
			car.shift_up()
		1:
			car.shift_down()
		2:
			car.automatic = not car.automatic
		3:
			car.limiter_on = not car.limiter_on
		4:
			car.traction_control = not car.traction_control
		5:
			car.adjust_brake_bias(0.005)
		6:
			car.adjust_brake_bias(-0.005)
		7:
			car.reset_car()


func _on_infraction(entry: RaceEntry, title: String, detail: String, is_penalty: bool) -> void:
	if not entry.is_human:
		return
	var ev := {"event": "notice", "title": title, "detail": detail, "penalty": is_penalty}
	for peer in _peers_of(entry.net_id):
		_net.race.rpc_id(peer, ev)


func _broadcast_event(data: Dictionary) -> void:
	for peer in _peers():
		_net.race.rpc_id(peer, data)


## Fim: todos os humanos terminaram/abandonaram (ou saíram), ou acabou o tempo depois do 1º.
func _check_end(delta: float) -> void:
	if _end_timer >= 0.0:
		_end_timer -= delta
		if _end_timer <= 0.0:
			_finish()
		return
	var any_active := false
	var all_done := true
	for acc_id in manager.humans:
		var e: RaceEntry = manager.humans[acc_id]
		if _left.has(acc_id):
			continue
		any_active = true
		if e.finished and _first_finish < 0.0:
			_first_finish = _t
		if not e.finished and not e.retired:
			all_done = false
	if not any_active:
		_finish()
	elif all_done:
		_end_timer = END_DELAY
	elif _first_finish >= 0.0 and _t - _first_finish > FINISH_TIMEOUT:
		_finish()


func _finish() -> void:
	if _phase == "done":
		return
	_phase = "done"
	var st := manager.net_state()
	var classification := manager.final_classification()
	var results := []
	for acc_id in manager.humans:
		var e: RaceEntry = manager.humans[acc_id]
		if _left.has(acc_id) and e.laps_completed() <= 0:
			continue
		var pos := classification.find(e) + 1
		results.append({
			"id": acc_id, "difficulty": int(settings.get("difficulty", 1)) if bool(settings.get("bots", true)) else 1,
			"dsq": e.disqualified, "fastest": manager.fastest_entry == e,
			"record": {"pos": pos, "total": classification.size(), "grid": e.grid_slot + 1, "finished": e.finished and not e.retired,
				"penalty": e.penalty_seconds, "best_lap": e.best_lap, "laps": e.laps_completed(),
				"consistency": Progression.consistency_of(Array(e.lap_times)), "online": true},
		})
	for peer in _peers():
		_net.race.rpc_id(peer, st)
		_net.race.rpc_id(peer, {"event": "closed"})
	finished.emit(results)
