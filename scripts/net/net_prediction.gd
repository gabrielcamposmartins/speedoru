class_name NetPrediction
extends RefCounted
## Predição no cliente, com reconciliação, para o carro do próprio jogador na corrida em rede
## (usada pelo NetRaceClient).
##
## O carro roda a física aqui, com o comando aplicado na hora (sem esperar a ida e volta ao
## servidor). Cada comando tem um número de sequência; o servidor aplica um por passo, na mesma
## ordem, e devolve no instantâneo o "ack" (o último comando aplicado) junto com o estado do carro
## dele. O estado que o cliente previu logo depois de cada comando fica guardado (history); quando o
## instantâneo chega, a diferença entre o estado do servidor e o previsto PARA O MESMO COMANDO é o
## erro da previsão:
## * pequeno (abaixo de DEAD_*): ignorado (física de cliente e servidor nunca bate ao milímetro);
## * médio: a velocidade é corrigida na hora e a posição/rotação aos poucos (BLEND por passo, para
##   não dar tranco na câmera); o histórico posterior ao ack é corrigido junto (ele foi previsto a
##   partir do estado errado) e o que ainda falta aplicar entra no estado guardado, para o mesmo
##   erro não ser contado duas vezes;
## * grande (> SNAP_POS: batida, carro levado aos boxes ou de volta à pista): o carro salta para o
##   estado do servidor (adiantado pelos comandos que ele ainda não aplicou).
## O que é decisão do servidor vem dele em todo instantâneo: largada/parada (hold), carro escondido,
## dano, pneus, rodas quebradas e bateria (se a diferença for grande). Limitador, controle de tração
## e câmbio automático seguem o servidor, menos logo depois de o jogador trocar aqui.
## Servidor antigo (instantâneo sem ack): a predição desliga e o carro volta a seguir o servidor.

const DEAD_POS := 0.05
const DEAD_VEL := 0.3
const DEAD_ROT := 0.0175
const SNAP_POS := 4.0
const BLEND := 0.25
const HISTORY := 360
## Instantâneos sem ack até concluir que o servidor não tem predição.
const NO_ACK_LIMIT := 20
## Depois de trocar limitador/TC/câmbio aqui, quanto tempo (ms) o valor do servidor é ignorado.
const TOGGLE_GRACE := 1500

var car: F1Car
var index := -1
var active := true
## Medidas (testes e diagnóstico): correções, saltos, último erro e maior erro (m).
var corrections := 0
var snaps := 0
var last_error := 0.0
var max_error := 0.0

## seq -> [posição, rotação, velocidade] previstos logo depois de aplicar o comando seq
var _history := {}
var _oldest := 0
var _pending_pos := Vector3.ZERO
var _pending_rot := Quaternion.IDENTITY
var _no_ack := 0
var _last_toggle := {}


func _init(p_car: F1Car, p_index: int) -> void:
	car = p_car
	index = p_index
	car.net_predicted = true
	car.player_controlled = false


## Antes do passo: guarda o estado que resultou do comando `seq` (aplicado no passo anterior),
## somando a correção que ainda não foi aplicada no carro.
func record(seq: int) -> void:
	if seq <= 0:
		return
	var xf := car.global_transform
	_history[seq] = [xf.origin + _pending_pos, (_pending_rot * xf.basis.get_rotation_quaternion()).normalized(), car.linear_velocity]
	if _oldest == 0:
		_oldest = seq
	while _history.size() > HISTORY:
		_history.erase(_oldest)
		_oldest += 1


## Aplica no carro o mesmo comando que vai para o servidor. `pressed`: ações de toque (NetRaceClient.ACTIONS).
func apply_input(d: PackedFloat32Array, pressed: Array) -> void:
	car.throttle_input = clampf(d[1], 0.0, 1.0)
	car.brake_input = clampf(d[2], 0.0, 1.0)
	car.reverse_input = clampf(d[3], 0.0, 1.0) if car.automatic else 0.0
	car.steer_input = clampf(d[4], -1.0, 1.0)
	var buttons := int(d[5])
	car.drs_requested = buttons & NetProtocol.BTN_DRS != 0
	car.boost_input = buttons & NetProtocol.BTN_BOOST != 0
	for k in pressed.size():
		if pressed[k]:
			_action(k)


## Mesmas ações do servidor (RaceSession._action), menos voltar à pista (o servidor leva o carro
## e o salto da reconciliação acompanha).
func _action(k: int) -> void:
	var now := Time.get_ticks_msec()
	match k:
		0:
			car.shift_up()
		1:
			car.shift_down()
		2:
			car.automatic = not car.automatic
			_last_toggle[NetSnapshot.F_AUTO] = now
		3:
			car.limiter_on = not car.limiter_on
			_last_toggle[NetSnapshot.F_LIMITER] = now
		4:
			car.traction_control = not car.traction_control
			_last_toggle[NetSnapshot.F_TC] = now
		5:
			car.adjust_brake_bias(0.005)
		6:
			car.adjust_brake_bias(-0.005)
		8:
			car.pass_signal()


## A cada passo: aplica uma parte da correção de posição/rotação que falta.
func step() -> void:
	if _pending_pos.length_squared() < 1e-6 and _pending_rot.get_angle() < 1e-4:
		return
	var dp := _pending_pos * BLEND
	var dr := Quaternion.IDENTITY.slerp(_pending_rot, BLEND)
	var xf := car.global_transform
	car.global_transform = Transform3D(Basis((dr * xf.basis.get_rotation_quaternion()).normalized()), xf.origin + dp)
	_pending_pos -= dp
	_pending_rot = (dr.inverse() * _pending_rot).normalized()


## Instantâneo do servidor: aplica o que é dele e compara o estado com o previsto para o ack.
## `latest_seq`: o último comando mandado (para adiantar o estado num salto).
func reconcile(s: Dictionary, latest_seq: int) -> void:
	var c: Variant = (s["cars"] as Dictionary).get(index)
	if c == null:
		return
	_apply_authority(c)
	if not s.has("ack"):
		_no_ack += 1
		if _no_ack > NO_ACK_LIMIT:
			active = false
		return
	var ack: int = s["ack"]
	var pred: Variant = _history.get(ack)
	while _oldest > 0 and _oldest <= ack and _oldest <= latest_seq:
		_history.erase(_oldest)
		_oldest += 1
	if c["flags"] & NetSnapshot.F_HIDDEN:
		return
	if pred == null:
		# Nada previsto para esse comando (início, pausa): só um salto se estiver muito longe
		if (car.global_position - (c["pos"] as Vector3)).length() > SNAP_POS * 2.0:
			_snap(c, latest_seq - ack)
		return
	var err_pos: Vector3 = (c["pos"] as Vector3) - (pred[0] as Vector3)
	var err_rot: Quaternion = ((c["rot"] as Quaternion) * (pred[1] as Quaternion).inverse()).normalized()
	var err_vel: Vector3 = (c["vel"] as Vector3) - (pred[2] as Vector3)
	last_error = err_pos.length()
	max_error = maxf(max_error, last_error)
	if last_error > SNAP_POS:
		_snap(c, latest_seq - ack)
		return
	if last_error < DEAD_POS and err_vel.length() < DEAD_VEL and err_rot.get_angle() < DEAD_ROT:
		return
	corrections += 1
	_pending_pos += err_pos
	_pending_rot = (err_rot * _pending_rot).normalized()
	car.linear_velocity += err_vel
	# O que foi previsto depois do ack partiu do estado errado: corrige junto
	for k: int in _history:
		var e: Array = _history[k]
		e[0] = (e[0] as Vector3) + err_pos
		e[1] = (err_rot * (e[1] as Quaternion)).normalized()
		e[2] = (e[2] as Vector3) + err_vel


## Salto para o estado do servidor, adiantado pelos `ahead` comandos que ele ainda não aplicou.
func _snap(c: Dictionary, ahead: int) -> void:
	snaps += 1
	var dt := 1.0 / Engine.physics_ticks_per_second
	var vel: Vector3 = c["vel"]
	car.global_transform = Transform3D(Basis(c["rot"] as Quaternion), (c["pos"] as Vector3) + vel * maxi(ahead, 0) * dt)
	car.linear_velocity = vel
	car.angular_velocity = Vector3.ZERO
	car.reset_physics_interpolation()
	_pending_pos = Vector3.ZERO
	_pending_rot = Quaternion.IDENTITY
	_history.clear()
	_oldest = 0


## O que só o servidor decide (vale do jeito que ele mandou).
func _apply_authority(c: Dictionary) -> void:
	var flags: int = c["flags"]
	car.hold = flags & NetSnapshot.F_HOLD != 0
	car.visible = flags & NetSnapshot.F_HIDDEN == 0
	var now := Time.get_ticks_msec()
	for f in [NetSnapshot.F_LIMITER, NetSnapshot.F_TC, NetSnapshot.F_AUTO]:
		if now - int(_last_toggle.get(f, -100000)) < TOGGLE_GRACE:
			continue
		var on: bool = flags & f != 0
		match f:
			NetSnapshot.F_LIMITER:
				car.limiter_on = on
			NetSnapshot.F_TC:
				car.traction_control = on
			NetSnapshot.F_AUTO:
				car.automatic = on
	if absf(car.battery - float(c["battery"])) > 0.05:
		car.battery = c["battery"]
	var compound: int = c["compound"]
	if car.config and compound != car.config.tyre_compound:
		car.change_tyres(compound)
	car.tire_wear = c["wear"]
	car.tire_usage = c["usage"]
	var dmg: PackedFloat32Array = c["damage"]
	car.damage_front_downforce = dmg[0]
	car.damage_rear_downforce = dmg[1]
	car.damage_drag = dmg[2]
	car.damage_power = dmg[3]
	var broken: int = c["broken"]
	for k in mini(car.wheel_broken.size(), 4):
		car.wheel_broken[k] = broken & (1 << k) != 0
