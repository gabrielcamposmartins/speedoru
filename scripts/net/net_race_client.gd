class_name NetRaceClient
extends Node
## Corrida em rede, lado do cliente (filho do RaceManager em modo CLIENT).
##
## * Manda os comandos do jogador ao servidor a cada passo de física (pedais, direção, botões e
##   contadores das ações de toque — trocar marcha, limitador… —, que não se perdem se um pacote
##   não chegar, porque o servidor aplica a diferença).
## * Recebe os instantâneos (30/s) e desenha todos os carros um pouco no passado
##   (NetProtocol.INTERP_DELAY), interpolando entre dois instantâneos; se faltar um, estica a
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
## * Repassa o estado da prova (5/s) e os acontecimentos ao RaceManager.

const ACTIONS := ["shift_up", "shift_down", "toggle_gearbox", "pit_limiter", "toggle_tc", "brake_bias_forward",
	"brake_bias_rearward", "reset_car", "pass_signal"]
const MAX_EXTRAPOLATE := 0.25
## Janela (instantâneos, ~0,5 s) do relógio do servidor e quanto ele desce por instantâneo.
const OFFSET_WINDOW := 15
const OFFSET_DOWN := 0.18
## Diferença do relógio da interpolação que vale um salto em vez de correção suave (s).
const RENDER_SNAP := 0.5
## Passos de física para levar o carro da posição esticada até a interpolada.
const EXIT_BLEND_STEPS := 8
## Correção maior que isso (m) é um salto de verdade (carro levado de volta à pista): sem suavizar.
const EXIT_BLEND_MAX := 6.0

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
var _seq := 0
var _render_t := -1.0
## Contadores das ações de toque (um por item de ACTIONS; o servidor aplica a diferença).
var _counts := PackedFloat32Array()
var _net: Node


func _init() -> void:
	_counts.resize(ACTIONS.size())
	_counts.fill(0.0)


func setup(p_manager: RaceManager) -> void:
	manager = p_manager
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -10
	_net = get_node_or_null("/root/Net")
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
	var s := NetSnapshot.decode(data)
	_track_offset(float(s["t"]) - _now())
	if not _snaps.is_empty() and s["t"] <= _snaps[-1]["t"]:
		return
	_snaps.append(s)
	while _snaps.size() > 40:
		_snaps.pop_front()


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


func _on_state(d: Dictionary) -> void:
	if d.has("event"):
		manager.apply_net_event(d)
	else:
		manager.apply_net_state(d)


func _physics_process(delta: float) -> void:
	_send_input()
	if _snaps.is_empty():
		return
	var target := _now() + _offset - NetProtocol.INTERP_DELAY
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
	for e in manager.roster:
		var ca: Variant = a["cars"].get(e.index)
		if ca == null:
			continue
		var cb: Variant = b["cars"].get(e.index) if not b.is_empty() else null
		if cb != null:
			var span: float = maxf(b["t"] - a["t"], 0.001)
			var w := clampf((rt - a["t"]) / span, 0.0, 1.0)
			_apply(e.index, e.car, ca, cb, w, 0.0, delta)
		else:
			_apply(e.index, e.car, ca, ca, 0.0, clampf(rt - a["t"], 0.0, MAX_EXTRAPOLATE), delta)


func _apply(idx: int, car: F1Car, a: Dictionary, b: Dictionary, w: float, extra: float, delta: float) -> void:
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


## Comandos do jogador para o servidor. Com o menu de pausa aberto, solta os pedais.
func _send_input() -> void:
	if _net == null or not _net.online:
		return
	var blocked: bool = manager.hud != null and manager.hud.pause_menu != null
	for k in ACTIONS.size():
		if not blocked and Input.is_action_just_pressed(ACTIONS[k]):
			_counts[k] += 1.0
	_seq += 1
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
	_net.inp.rpc_id(1, d)
