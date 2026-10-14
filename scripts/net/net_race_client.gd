class_name NetRaceClient
extends Node
## Corrida em rede, lado do cliente (filho do RaceManager em modo CLIENT).
##
## * Manda os comandos do jogador ao servidor a cada passo de física (pedais, direção, botões e
##   contadores das ações de toque — trocar marcha, limitador… —, que não se perdem se um pacote
##   não chegar, porque o servidor aplica a diferença).
## * Recebe os instantâneos (30/s) e desenha todos os carros um pouco no passado (a FOLGA de
##   interpolação, interp_delay), interpolando entre dois instantâneos; se faltar um, estica a
##   última posição pela velocidade por até 0,25 s e, quando os instantâneos voltam, leva o carro
##   até a posição interpolada em alguns passos (EXIT_BLEND_STEPS), sem salto. O relógio da
##   interpolação anda um passo de física por vez (corrigindo devagar para o relógio do servidor):
##   com a hora real, dois passos no mesmo quadro teriam o mesmo instante e o carro andaria aos
##   trancos.
## * Relógio do servidor (_offset): o maior "tempo do instantâneo − hora local" dos últimos
##   OFFSET_WINDOW instantâneos (o atraso de rede só diminui a conta, então o maior é o mais
##   confiável). Sobe na hora; desce aos poucos (OFFSET_DOWN por instantâneo, ~0,5 s), assim um
##   passo atrasado no servidor (o tempo da simulação fica para trás) não deixa o cliente adiante
##   dos instantâneos.
## * Folga adaptativa: para cada instantâneo, o quanto ele chegou atrasado em relação ao mais
##   rápido da janela (variação da rede e passos atrasados no servidor). A folga é um intervalo
##   entre instantâneos + o percentil 95 desses atrasos + uma margem (entre INTERP_MIN e
##   INTERP_MAX): a menor que ainda deixa um instantâneo à frente quase sempre. Sobe rápido quando a
##   rede piora e desce devagar quando melhora (sem ficar oscilando).
## * Repassa o estado da prova (5/s) e os acontecimentos ao RaceManager.
## * O carro do próprio jogador não segue os instantâneos: roda a física aqui com o comando na hora
##   (predição, NetPrediction) e é corrigido pelo estado do servidor para o mesmo comando
##   (reconciliação). Com servidor antigo (sem ack), depois da bandeirada ou se o carro abandonar,
##   volta a seguir o servidor como os outros.

const ACTIONS := ["shift_up", "shift_down", "toggle_gearbox", "pit_limiter", "toggle_tc", "brake_bias_forward",
	"brake_bias_rearward", "reset_car", "pass_signal"]
const MAX_EXTRAPOLATE := 0.25
## Folga de interpolação adaptativa: limites (s), margem (s), janela de medida (instantâneos, ~3 s),
## percentil dos atrasos e quanto a folga anda por instantâneo subindo e descendo.
const INTERP_MIN := 0.04
const INTERP_MAX := 0.25
const INTERP_MARGIN := 0.01
const JITTER_WINDOW := 90
const JITTER_PERCENTILE := 0.95
const INTERP_UP := 0.3
const INTERP_DOWN := 0.03
## Janela (instantâneos, ~0,5 s) do relógio do servidor e quanto ele desce por instantâneo.
const OFFSET_WINDOW := 15
const OFFSET_DOWN := 0.18
## Diferença do relógio da interpolação que vale um salto em vez de correção suave (s).
const RENDER_SNAP := 0.5
## Passos de física para levar o carro da posição esticada até a interpolada.
const EXIT_BLEND_STEPS := 8
## Correção maior que isso (m) é um salto de verdade (carro levado de volta à pista): sem suavizar.
const EXIT_BLEND_MAX := 6.0
## Distância (m) entre dois retratos seguidos que só um teletransporte explica (nem a 350 km/h com
## alguns retratos perdidos o carro anda isso).
const TELEPORT_JUMP := 40.0

var manager: RaceManager
var _snaps: Array[Dictionary] = []
var _offset := 0.0
var _has_offset := false
## Últimas estimativas do relógio do servidor (ver OFFSET_WINDOW).
var _estimates := PackedFloat64Array()
## Por carro (índice): se o último passo foi esticado, a última pose mostrada e a correção em
## andamento ao sair da extrapolação [erro de posição, erro de rotação, passos restantes].
var _extrapolated := {}
var _last_pose := {}
var _blend := {}
## Último comando mandado (número de sequência; vem do Net, contínuo entre corridas).
var _seq := 0
var _render_t := -1.0
## Contadores das ações de toque (um por item de ACTIONS; o servidor aplica a diferença). São os
## do Net (contínuos entre corridas, como a sequência).
var _counts := PackedFloat32Array()
var _net: Node
## Folga de interpolação atual (s) e a que a variação medida permite (s).
var interp_delay := NetProtocol.INTERP_DELAY
var interp_target := NetProtocol.INTERP_DELAY
## Passos em que algum carro dos outros foi esticado (faltou instantâneo) e passos no total.
var extrapolated_steps := 0
var interp_steps := 0
## Atrasos de chegada dos últimos instantâneos (s, em relação ao mais rápido).
var _late := PackedFloat32Array()
## Predição do carro do jogador (null = segue o servidor como os outros).
var prediction: NetPrediction
## Predição ligada (-- --no-prediction desliga, para comparar).
static var prediction_enabled := true
## Atraso de rede simulado (ms, ida e volta; -- --net-lag=ms), só para testes: segura os comandos
## na ida e os instantâneos na volta por metade disso cada; -- --net-jitter=ms soma um atraso
## aleatório de 0 a isso a cada instantâneo e a cada comando (os que chegam fora de ordem são
## descartados pelo servidor, como no canal "unreliable_ordered").
static var lag_ms := 0
static var jitter_ms := 0
var _out_lag: Array = []
var _in_lag: Array = []


func _init() -> void:
	_counts.resize(ACTIONS.size())
	_counts.fill(0.0)


func setup(p_manager: RaceManager) -> void:
	manager = p_manager
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -10
	_net = get_node_or_null("/root/Net")
	if _net:
		if (_net.input_counts as PackedFloat32Array).size() != ACTIONS.size():
			_net.input_counts.resize(ACTIONS.size())
			_net.input_counts.fill(0.0)
		_counts = _net.input_counts
		_seq = _net.input_seq
	for a in OS.get_cmdline_user_args():
		if a == "--no-prediction":
			prediction_enabled = false
		elif a.begins_with("--net-lag="):
			lag_ms = maxi(int(a.substr(10)), 0)
		elif a.begins_with("--net-jitter="):
			jitter_ms = maxi(int(a.substr(13)), 0)
	var me := manager.player_entry
	if me and me.car and not me.car.puppet:
		if prediction_enabled:
			prediction = NetPrediction.new(me.car, me.index)
		else:
			me.car.set_puppet(true)
	if _net:
		_net.race_snapshot.connect(_on_snapshot)
		_net.race_state.connect(_on_state)
		_net.connection_changed.connect(_on_connection)


func _exit_tree() -> void:
	if _net and _net.race_snapshot.is_connected(_on_snapshot):
		_net.race_snapshot.disconnect(_on_snapshot)
		_net.race_state.disconnect(_on_state)
		_net.connection_changed.disconnect(_on_connection)


## Caiu a conexão: avisa e volta ao menu (a corrida é do servidor, não dá para continuar).
func _on_connection(is_online: bool) -> void:
	if is_online or manager == null:
		return
	if manager.player_entry:
		manager.notify_entry(manager.player_entry, "CONEXÃO PERDIDA", "Voltando ao menu…", true)
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(manager):
		manager.restart(false)


static func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func _on_snapshot(data: PackedByteArray) -> void:
	if lag_ms > 0 or jitter_ms > 0:
		_in_lag.append([Time.get_ticks_msec() + lag_ms / 2 + randi_range(0, jitter_ms), data])
		_in_lag.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		return
	_handle_snapshot(data)


func _handle_snapshot(data: PackedByteArray) -> void:
	var s := NetSnapshot.decode(data)
	var est := float(s["t"]) - _now()
	_track_offset(est)
	_adapt_delay(est)
	if not _snaps.is_empty() and s["t"] <= _snaps[-1]["t"]:
		return
	_snaps.append(s)
	while _snaps.size() > 40:
		_snaps.pop_front()
	if prediction:
		prediction.reconcile(s, _seq)
		if not prediction.active:
			_stop_prediction()


## Relógio do servidor nos dois sentidos: o maior valor da janela, subindo na hora e descendo aos
## poucos (sem pular de uma vez).
func _track_offset(est: float) -> void:
	_estimates.append(est)
	if _estimates.size() > OFFSET_WINDOW:
		_estimates = _estimates.slice(_estimates.size() - OFFSET_WINDOW)
	var best := est
	for v in _estimates:
		best = maxf(best, v)
	if not _has_offset or best > _offset:
		_offset = best
		_has_offset = true
	else:
		_offset = lerpf(_offset, best, OFFSET_DOWN)


## Folga adaptativa: um intervalo entre instantâneos + o percentil dos atrasos de chegada.
func _adapt_delay(est: float) -> void:
	_late.append(maxf(_offset - est, 0.0))
	if _late.size() > JITTER_WINDOW:
		_late = _late.slice(_late.size() - JITTER_WINDOW)
	if _late.size() < 10:
		return
	var sorted := Array(_late)
	sorted.sort()
	var p: float = sorted[mini(int(sorted.size() * JITTER_PERCENTILE), sorted.size() - 1)]
	interp_target = clampf(1.0 / NetProtocol.SNAPSHOT_HZ + p + INTERP_MARGIN, INTERP_MIN, INTERP_MAX)
	interp_delay = lerpf(interp_delay, interp_target, INTERP_UP if interp_target > interp_delay else INTERP_DOWN)


func _on_state(d: Dictionary) -> void:
	if d.has("event"):
		manager.apply_net_event(d)
	else:
		manager.apply_net_state(d)


## O carro do jogador volta a seguir o servidor (marionete, interpolado como os outros).
func _stop_prediction() -> void:
	if prediction == null:
		return
	prediction.car.net_predicted = false
	prediction.car.set_puppet(true)
	prediction = null


func _physics_process(delta: float) -> void:
	if lag_ms > 0 or jitter_ms > 0:
		var now := Time.get_ticks_msec()
		while not _in_lag.is_empty() and int(_in_lag[0][0]) <= now:
			_handle_snapshot(_in_lag.pop_front()[1])
		while not _out_lag.is_empty() and int(_out_lag[0][0]) <= now:
			_net.inp.rpc_id(1, _out_lag.pop_front()[1])
	if prediction:
		var me := manager.player_entry
		if me == null or me.finished or me.retired or manager.state == RaceManager.State.FINISHED:
			_stop_prediction()
	if prediction:
		# Pausa da sala: o carro para junto com o servidor
		if prediction.car.freeze != manager.net_paused:
			prediction.car.freeze = manager.net_paused
		if not manager.net_paused:
			prediction.record(_seq)
			prediction.step()
	# Observador (sem carro): não manda comandos
	var sent := [] if manager.observer else _send_input()
	if prediction and not manager.net_paused and not sent.is_empty():
		prediction.apply_input(sent[0], sent[1])
	if _snaps.is_empty():
		return
	var target := _now() + _offset - interp_delay
	if _render_t < 0.0 or absf(target - _render_t) > RENDER_SNAP:
		_render_t = target
	else:
		_render_t += delta + (target - _render_t) * 0.05
	var rt := _render_t
	var a: Dictionary = _snaps[0]
	var b: Dictionary = {}
	for k in _snaps.size():
		if _snaps[k]["t"] <= rt:
			a = _snaps[k]
			b = _snaps[k + 1] if k + 1 < _snaps.size() else {}
		else:
			if k == 0:
				b = {}
			break
	var stretched := false
	for e in manager.roster:
		if prediction and e.index == prediction.index:
			continue
		var ca: Variant = a["cars"].get(e.index)
		if ca == null:
			continue
		var cb: Variant = b["cars"].get(e.index) if not b.is_empty() else null
		if cb != null:
			var span: float = maxf(b["t"] - a["t"], 0.001)
			var w := clampf((rt - a["t"]) / span, 0.0, 1.0)
			_apply(e.index, e.car, ca, cb, w, 0.0, delta)
		else:
			stretched = true
			_apply(e.index, e.car, ca, ca, 0.0, clampf(rt - a["t"], 0.0, MAX_EXTRAPOLATE), delta)
	interp_steps += 1
	if stretched:
		extrapolated_steps += 1


func _apply(idx: int, car: F1Car, a: Dictionary, b: Dictionary, w: float, extra: float, delta: float) -> void:
	# Teletransporte entre os dois retratos (voltou ao box, caiu da pista no céu): sem interpolar,
	# senão o carro desliza pelo meio do caminho
	if (a["pos"] as Vector3).distance_to(b["pos"]) > TELEPORT_JUMP:
		a = b
		w = 1.0
		_blend.erase(idx)
		_extrapolated.erase(idx)
		_last_pose.erase(idx)
	var vel: Vector3 = (a["vel"] as Vector3).lerp(b["vel"], w)
	var pos: Vector3 = (a["pos"] as Vector3).lerp(b["pos"], w) + vel * extra
	var rot: Quaternion = (a["rot"] as Quaternion).slerp(b["rot"], w)
	# Saindo de uma extrapolação: a posição esticada e a interpolada não batem; em vez de saltar,
	# leva o carro até a interpolada em alguns passos
	if extra <= 0.0 and _extrapolated.get(idx, false) and _last_pose.has(idx):
		var last: Transform3D = _last_pose[idx]
		var expected: Vector3 = last.origin + vel * delta
		var err := expected - pos
		if err.length() > 0.01 and err.length() < EXIT_BLEND_MAX:
			_blend[idx] = [err, last.basis.get_rotation_quaternion() * rot.inverse(), EXIT_BLEND_STEPS]
	_extrapolated[idx] = extra > 0.0
	if _blend.has(idx):
		var bl: Array = _blend[idx]
		var f := float(bl[2]) / (EXIT_BLEND_STEPS + 1)
		pos += (bl[0] as Vector3) * f
		rot = Quaternion.IDENTITY.slerp(bl[1], f) * rot
		bl[2] -= 1
		if bl[2] <= 0:
			_blend.erase(idx)
	var xf := Transform3D(Basis(rot.normalized()), pos)
	_last_pose[idx] = xf
	car.global_transform = xf
	car.linear_velocity = vel
	var s: Dictionary = b if w >= 0.5 else a
	car.rpm = lerpf(a["rpm"], b["rpm"], w)
	var gear: int = s["gear"]
	if gear != car.gear:
		car.gear = gear
		car.gear_changed.emit(gear)
	car.throttle_input = s["throttle"]
	car.brake_input = s["brake"]
	car.steering = lerpf(a["steer"], b["steer"], w)
	var flags: int = s["flags"]
	var drs := flags & NetSnapshot.F_DRS != 0
	if drs != car.drs_open:
		car.drs_open = drs
		car.drs_changed.emit(drs)
	car.boost_active = flags & NetSnapshot.F_BOOST != 0
	car.limiter_on = flags & NetSnapshot.F_LIMITER != 0
	car.hold = flags & NetSnapshot.F_HOLD != 0
	car.visible = flags & NetSnapshot.F_HIDDEN == 0
	car.traction_control = flags & NetSnapshot.F_TC != 0
	car.abs_active = flags & NetSnapshot.F_ABS != 0
	car.automatic = flags & NetSnapshot.F_AUTO != 0
	car.battery = s["battery"]
	var compound: int = s["compound"]
	if car.config and compound != car.config.tyre_compound:
		car.change_tyres(compound)
	car.tire_wear = s["wear"]
	var dmg: PackedFloat32Array = s["damage"]
	car.damage_front_downforce = dmg[0]
	car.damage_rear_downforce = dmg[1]
	car.damage_drag = dmg[2]
	car.damage_power = dmg[3]
	var broken: int = s["broken"]
	car.signal_on = broken & 16 != 0
	for k in mini(car.wheel_broken.size(), 4):
		car.wheel_broken[k] = broken & (1 << k) != 0
	car.tire_usage = s["usage"]
	car.brake_bias_front = s["bias"]
	var da: PackedFloat32Array = a["drop"]
	var db: PackedFloat32Array = b["drop"]
	for k in 4:
		car.puppet_wheel_drop[k] = lerpf(da[k], db[k], w)


## Comandos do jogador para o servidor. Com o menu de pausa aberto, solta os pedais. Devolve
## [comando, ações apertadas agora] (o mesmo comando vai para a predição) ou [] sem conexão.
func _send_input() -> Array:
	if _net == null or not _net.online:
		return []
	var blocked: bool = manager.hud != null and manager.hud.pause_menu != null
	var pressed := []
	for k in ACTIONS.size():
		var hit := not blocked and Input.is_action_just_pressed(ACTIONS[k])
		pressed.append(hit)
		if hit:
			_counts[k] += 1.0
	_seq += 1
	_net.input_seq = _seq
	_net.input_counts = _counts
	var buttons := 0
	if not blocked and Input.is_action_pressed("drs"):
		buttons |= NetProtocol.BTN_DRS
	if not blocked and Input.is_action_pressed("boost"):
		buttons |= NetProtocol.BTN_BOOST
	var d := PackedFloat32Array([
		_seq,
		0.0 if blocked else Input.get_action_strength("accelerate"),
		0.0 if blocked else Input.get_action_strength("brake"),
		0.0 if blocked else Input.get_action_strength("reverse"),
		0.0 if blocked else Input.get_axis("steer_right", "steer_left"),
		buttons,
	])
	d.append_array(_counts)
	if lag_ms > 0 or jitter_ms > 0:
		_out_lag.append([Time.get_ticks_msec() + lag_ms / 2 + randi_range(0, jitter_ms), d])
		_out_lag.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	else:
		_net.inp.rpc_id(1, d)
	return [d, pressed]
