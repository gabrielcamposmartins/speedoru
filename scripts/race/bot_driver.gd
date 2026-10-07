class_name BotDriver
extends Node
## Piloto controlado pelo computador. Filho do F1Car (que fica com player_controlled = false);
## roda antes dele em cada passo de física e escreve throttle/brake/steer.
##
## * Direção: "pure pursuit" num ponto à frente na linha de corrida (+ deslocamento lateral para
##   ultrapassar/desviar ou para entrar nos boxes).
## * Velocidade: perfil da linha (RacingLine.speed_profile) para a dificuldade; segue o carro da
##   frente quando não dá para passar.
## * Pit stop: na volta escolhida entra nos boxes, respeita 80 km/h, para no box da equipe, troca
##   os pneus e volta à pista.
## * Recupera sozinho se ficar parado/preso (volta para a pista).
## * Jogadores humanos: todos os bots deixam mais espaço (seguem com folga maior e enxergam uma faixa
##   mais larga em volta deles), sem frear nem desviar instantâneo — a batida continua possível.
##   Bots fácil e médio respeitam ataques: com um humano chegando por trás (até YIELD_RANGE m) ou
##   lado a lado, abrem para o outro lado e tiram um pouco o pé; o difícil defende a posição.
##   Sob bandeira amarela ninguém dá passagem (ultrapassar é proibido).

enum Difficulty { EASY, MEDIUM, HARD }
enum Mode { RACE, PIT_IN, PIT_STOP, PIT_OUT }

## [aderência, frenagem, aceleração, reação na largada (min, max), ruído lateral, tempo de pit]
const PRESETS := {
	Difficulty.EASY: [0.84, 0.74, 0.92, Vector2(0.45, 0.8), 0.7, 3.4],
	Difficulty.MEDIUM: [0.91, 0.84, 0.97, Vector2(0.28, 0.5), 0.35, 2.9],
	Difficulty.HARD: [0.96, 0.92, 1.0, Vector2(0.17, 0.3), 0.12, 2.5],
}
const NAMES := ["Fácil", "Médio", "Difícil"]
const WHEELBASE := 3.6
const PIT_SPEED := 21.5
## Desaceleração usada para calcular quando começar a frear atrás de outro carro.
const FOLLOW_DECEL := 9.0

const LANE_FAST := RaceTrack.PIT_WALL_STRIP + 3.4
## Distância (m) atrás em que um humano atacando faz o bot fácil/médio dar passagem.
const YIELD_RANGE := 25.0
## Quanto o bot tira o pé para deixar passar (fração da velocidade): fácil, médio.
const YIELD_LIFT := [0.9, 0.95]

var car: F1Car
var track: RaceTrack
var line: RacingLine
var profile := PackedFloat32Array()
var difficulty := Difficulty.MEDIUM
var entry: RaceEntry
var manager: RaceManager
var mode := Mode.RACE
## Volta (contagem de cruzamentos da linha) em que vai parar nos boxes; -1 = não para.
var pit_lap := -1
var pit_compound := CarConfig.TyreCompound.HARD
var released := false

var _offset := 0.0
var _offset_target := 0.0
var _side_by_side := false
var _rejoin := 0.0
var _stop_timer := 0.0
var _stuck_timer := 0.0
var _noise_phase := 0.0
var _pit_lateral := 0.0
var _passing: RaceEntry
var _pass_side := 1.0
## Faixa lateral do grid: mantida no começo da corrida para não fechar os vizinhos na largada.
var start_lateral := INF


func setup(p_car: F1Car, p_track: RaceTrack, p_line: RacingLine, p_profile: PackedFloat32Array,
		p_difficulty: Difficulty, p_entry: RaceEntry, p_manager: RaceManager) -> void:
	car = p_car
	track = p_track
	line = p_line
	profile = p_profile
	difficulty = p_difficulty
	entry = p_entry
	manager = p_manager
	_noise_phase = randf() * TAU
	process_physics_priority = -10


## Levado ao box depois de uma batida (RaceControl): parado na vaga, conserto de [param seconds].
func force_pit_stop(seconds: float) -> void:
	mode = Mode.PIT_STOP
	_stop_timer = seconds + randf_range(RaceManager.PIT_STOP_MIN, RaceManager.PIT_STOP_MAX)
	entry.pit_stop_start = manager.race_time
	_passing = null
	_offset = 0.0
	_stuck_timer = 0.0
	car.hold = true
	manager.begin_pit_stop(entry)


func reaction_time() -> float:
	var r: Vector2 = PRESETS[difficulty][3]
	return randf_range(r.x, r.y)


func _physics_process(delta: float) -> void:
	if car == null or entry.retired:
		return
	# Roda arrancada: batida forte (bandeira amarela; o RaceControl o leva ao box)
	if released and car.wheel_broken.has(true) and manager.control and mode != Mode.PIT_STOP:
		manager.control.report_crash(entry)
	if not released or entry.finished_and_parked:
		if car:
			car.throttle_input = 0.0
			car.steer_input = 0.0
			car.brake_input = 1.0 if entry and entry.finished_and_parked else 0.0
		return
	var s := entry.s
	var v := car.linear_velocity.length()
	var lay := track.layout
	# --- Pit: decide e acompanha a máquina de estados
	if mode == Mode.RACE and pit_lap >= 0 and entry.pit_count == 0 and entry.crossings >= pit_lap:
		var to_entry := _ahead(lay.pit_entry_s, s)
		if to_entry > 30.0 and to_entry < 260.0:
			mode = Mode.PIT_IN
	if start_lateral == INF:
		start_lateral = entry.lateral
	var yellow := manager.control != null and manager.control.yellow
	var crashed := manager.control != null and manager.control.is_involved(entry)
	# Limitador só nos boxes (sob amarela o bot acompanha o safety car pela velocidade)
	car.limiter_on = mode != Mode.RACE and mode != Mode.PIT_STOP
	var target_lateral := _planned_lateral(s, entry.progress)
	var speed_target := RacingLine.sample(profile, track.path, s + 4.0 + v * 0.15)
	# Primeira volta até depois da 1ª chicane: freia antes (o pelotão se espalha sem batidas)
	if entry.progress < 1100.0 and speed_target < 70.0:
		speed_target *= 0.86
	if yellow and not crashed and mode == Mode.RACE:
		# Sob amarela: no máximo um pouco acima do safety car (o pelotão se junta atrás dele)
		speed_target = minf(speed_target, SafetyCar.SPEED * 1.15)
		var sc := manager.control.safety_car
		if sc:
			var ds_sc := sc.progress - entry.progress
			if ds_sc > -1.0 and ds_sc < 160.0:
				speed_target = minf(speed_target, maxf(sc.speed + (ds_sc - 30.0) * 0.5, 2.0))
		if crashed:
			speed_target = minf(speed_target, 15.0)
	match mode:
		Mode.PIT_IN, Mode.PIT_OUT:
			var pit := _pit_plan(s, v)
			target_lateral = pit.x
			speed_target = minf(speed_target, pit.y)
			# Fila indiana só dentro da faixa dos boxes; antes da entrada desvia como na corrida
			if entry.in_pit or mode == Mode.PIT_OUT:
				speed_target = minf(speed_target, _pit_traffic(s, entry.lateral))
			if mode == Mode.PIT_IN and absf(_ahead(track.garage_s(entry.garage), s)) < 1.2 and v < 1.2:
				mode = Mode.PIT_STOP
				_stop_timer = randf_range(RaceManager.PIT_STOP_MIN, RaceManager.PIT_STOP_MAX)
				manager.begin_pit_stop(entry)
			if mode == Mode.PIT_OUT and _ahead(lay.pit_exit_s, s) < -5.0 and _ahead(lay.pit_exit_s, s) > -400.0:
				mode = Mode.RACE
				_rejoin = 1.0
		Mode.PIT_STOP:
			car.hold = true
			car.throttle_input = 0.0
			car.brake_input = 1.0
			car.steer_input = 0.0
			_stop_timer -= delta
			# Liberação segura: não sai do box na frente de quem vem pela pista dos boxes
			if _stop_timer <= 0.0 and _pit_release_clear(s):
				car.hold = false
				car.change_tyres(pit_compound)
				mode = Mode.PIT_OUT
				manager.end_pit_stop(entry)
			return
	# Volta à linha de corrida aos poucos depois dos boxes
	if mode == Mode.RACE and _rejoin > 0.0:
		_rejoin = maxf(_rejoin - delta * 0.6, 0.0)
		target_lateral = lerpf(target_lateral, _pit_lateral, _rejoin)
	# --- Tráfego: ultrapassar, seguir ou desviar (também indo para o box, antes da entrada)
	if mode == Mode.RACE or (mode == Mode.PIT_IN and not entry.in_pit):
		_offset_target = 0.0
		var traffic := _traffic(s, v, entry.lateral)
		_offset_target = traffic.x
		speed_target = minf(speed_target, traffic.y)
		# Desvia mais rápido com alguém lado a lado
		_offset = move_toward(_offset, _offset_target, delta * (3.0 if _side_by_side else 1.6))
		target_lateral += _offset
		# Pilotos fáceis "passeiam" um pouco pela pista
		target_lateral += sin(entry.race_time * 0.37 + _noise_phase) * float(PRESETS[difficulty][4])
	var i := track.path.index_at(s)
	if mode == Mode.RACE:
		target_lateral = clampf(target_lateral, -track.path.width_right[i] + 1.1, track.path.width_left[i] - 1.1)
	_steer(s, v, target_lateral)
	_speed(v, speed_target)
	_check_stuck(delta, v)


func _steer(s: float, v: float, target_lateral: float) -> void:
	var look := clampf(6.0 + v * 0.42, 8.0, 42.0)
	var lat_ahead := target_lateral
	if mode == Mode.RACE:
		lat_ahead = line.lateral_at(s + look) + (target_lateral - line.lateral_at(s))
	var target := track.path.position_at(s + look, lat_ahead)
	var local := car.global_transform.affine_inverse() * target
	var alpha := atan2(local.x, local.z)
	var delta_angle := atan(2.0 * WHEELBASE * sin(alpha) / look)
	# Amortece a guinada (evita "serpentear" em alta)
	var yaw_rate := car.angular_velocity.dot(car.global_basis.y)
	var expected := v * sin(alpha) * 2.0 / look
	delta_angle -= (yaw_rate - expected) * 0.02
	var t := clampf(absf(car.forward_speed) / car.steer_speed_reference, 0.0, 1.0)
	var limit := lerpf(car.max_steer_angle, car.high_speed_steer_angle, sqrt(t))
	car.steer_input = clampf(delta_angle / maxf(limit, 0.001), -1.0, 1.0)


func _speed(v: float, target: float) -> void:
	var err := target - v
	if err > 0.4:
		car.throttle_input = clampf(0.45 + err * 0.25, 0.0, 1.0)
		car.brake_input = 0.0
	elif err > -1.2:
		car.throttle_input = 0.3
		car.brake_input = 0.0
	else:
		car.throttle_input = 0.0
		car.brake_input = clampf(-err * 0.12, 0.1, 1.0)


## Distância à frente (com sinal, entre -L/2 e L/2) de `target_s` a partir de `s`.
func _ahead(target_s: float, s: float) -> float:
	var length := track.path.length
	return fposmod(target_s - s + length * 0.5, length) - length * 0.5


## Retorna Vector2(deslocamento lateral desejado em relação à linha, velocidade máxima).
## Ultrapassagem com memória: escolhe um lado e mantém até ficar 10 m à frente; só começa em
## reta (curvatura baixa nos próximos 150 m). Nas curvas segue o carro da frente com folga.
func _traffic(s: float, v: float, my_lateral: float) -> Vector2:
	var max_speed := INF
	var line_lat := line.lateral_at(s)
	_side_by_side = false
	var i := track.path.index_at(s)
	var straight := _straight_ahead(s, 150.0)
	# Continua (ou desiste de) uma ultrapassagem em andamento
	if _passing and manager.control and manager.control.yellow and not manager.control.is_involved(_passing) \
			and not manager.control.is_involved(entry):
		_passing = null
	if _passing:
		var ds_pass := _ahead(_passing.s, s)
		if ds_pass < -10.0 or ds_pass > 60.0 or _passing.in_pit or (not straight and ds_pass > 4.0):
			_passing = null
	var follow: RaceEntry = null
	var follow_ds := INF
	var yellow := manager.control != null and manager.control.yellow
	var yields := difficulty != Difficulty.HARD and not yellow and mode == Mode.RACE
	# Sob amarela ninguém ultrapassa: qualquer carro à frente (que não esteja nos boxes nem
	# envolvido na batida) vira o carro a seguir, mesmo em outra linha da pista
	var no_pass := yellow and not manager.control.is_involved(entry)
	var attacker: RaceEntry = null
	var attacker_ds := -INF
	for other: RaceEntry in manager.entries:
		if other == entry or other.car == null or other.in_pit or other.retired:
			continue
		var ds := _ahead(other.s, s)
		# Humano atacando por trás (mais rápido, ou já colado): o bot fácil/médio dá passagem
		if yields and other.is_player and ds < -1.0 and ds > -YIELD_RANGE and ds > attacker_ds 				and (other.car.linear_velocity.length() > v - 0.5 or ds > -8.0):
			attacker = other
			attacker_ds = ds
		if ds < -8.0 or ds > 90.0:
			continue
		# Onde eu vou estar quando chegar lá (inclui a faixa do grid no começo); de perto vale
		# também onde eu estou agora (o plano pode não bater com a posição real no meio do pelotão)
		var my_there := _planned_lateral(other.s, entry.progress + ds) + _offset
		var dlat := other.lateral - my_there
		# Em volta de um humano a faixa "ocupada" é um pouco mais larga (mais respeito, menos batida)
		var width := 2.9 if other.is_player else 2.5
		var in_my_way := absf(dlat) < width or (ds < 35.0 and absf(other.lateral - my_lateral) < width - 0.2)
		if no_pass and not manager.control.is_involved(other):
			in_my_way = true
			# Lado a lado e ele um pouco à frente: fica atrás
			if ds > 0.0 and ds <= 4.5:
				max_speed = minf(max_speed, other.car.linear_velocity.length() - 1.0)
		if ds > 4.5 and in_my_way and other != _passing:
			if ds < follow_ds:
				follow = other
				follow_ds = ds
		elif absf(ds) <= 8.0 and absf(other.lateral - my_lateral) < 3.2 and other != _passing:
			# Lado a lado: abre espaço (largura do carro + folga)
			_offset_target = (my_lateral - line_lat) - signf(other.lateral - my_lateral) * (3.2 - absf(other.lateral - my_lateral))
			_side_by_side = true
			# Lado a lado com um humano: o fácil/médio não briga pela posição (alivia um pouco)
			if yields and other.is_player:
				max_speed = minf(max_speed, _yield_speed(s))
			# Colado atrás e sobrepondo (carros têm 2 m de largura): tira o pé antes de tocar
			if ds > 0.5 and absf(other.lateral - my_lateral) < 2.1:
				max_speed = minf(max_speed, other.car.linear_velocity.length() - 2.0)
	if follow:
		var other_v := follow.car.linear_velocity.length()
		var quicker := v > other_v + (0.5 if difficulty != Difficulty.EASY else 2.5)
		var side_choice := 0.0
		var yellow_ok := manager.control == null or not manager.control.yellow or manager.control.is_involved(follow) \
				or manager.control.is_involved(entry)
		if _passing == null and straight and quicker and follow_ds < 45.0 and entry.progress > 1100.0 and yellow_ok:
			var room_left := track.path.width_left[i] - follow.lateral
			var room_right := follow.lateral + track.path.width_right[i]
			for side: float in ([1.0, -1.0] if room_left > room_right else [-1.0, 1.0]):
				var room := room_left if side > 0.0 else room_right
				if room > 4.2 and _lane_clear(s, follow.lateral + side * 3.0):
					side_choice = side
					break
		if side_choice != 0.0:
			_passing = follow
			_pass_side = side_choice
		else:
			# Distância de segurança proporcional à velocidade; de longe, a velocidade que ainda dá
			# para frear (FOLLOW_DECEL) até a distância de segurança atrás dele
			var gap := 8.0 + v * 0.22 + (4.0 if follow.is_player else 0.0)
			if follow != _passing:
				var room := follow_ds - gap
				var limit := other_v + room * 0.6 if room < 0.0 else sqrt(other_v * other_v + 2.0 * FOLLOW_DECEL * room)
				max_speed = minf(max_speed, limit)
	# Dando passagem: abre para o lado oposto ao do atacante e tira um pouco o pé
	if attacker and _passing == null and not _side_by_side:
		var dl := attacker.lateral - my_lateral
		var away := -signf(dl)
		if absf(dl) < 0.4:
			away = 1.0 if track.path.width_left[i] - my_lateral > my_lateral + track.path.width_right[i] else -1.0
		_offset_target = (my_lateral - line_lat) + away * clampf(3.2 - absf(dl), 0.0, 3.2)
		_side_by_side = true
		if attacker_ds > -15.0:
			max_speed = minf(max_speed, _yield_speed(s))
	var offset := 0.0
	if _passing:
		offset = (_passing.lateral + _pass_side * 3.0) - line_lat
		# Ainda colado atrás: não acelera para dentro dele
		var ds_pass := _ahead(_passing.s, s)
		if ds_pass > 0.0 and absf(_passing.lateral - my_lateral) < 2.2:
			max_speed = minf(max_speed, _passing.car.linear_velocity.length() + (ds_pass - 6.0) * 0.8)
	elif _offset_target != 0.0 and absf(_offset_target) > 0.01:
		offset = _offset_target
	return Vector2(offset, maxf(max_speed, 3.0))


## Velocidade ao dar passagem: uma fração do ritmo normal daquele trecho (e não da velocidade
## atual, senão o bot iria desacelerando sem parar enquanto alguém o segue sem ultrapassar).
func _yield_speed(s: float) -> float:
	return RacingLine.sample(profile, track.path, s + 4.0) * float(YIELD_LIFT[difficulty])


## Lateral planejada (sem tráfego) num ponto: a linha de corrida; na largada, a linha deslocada
## pela faixa do grid (duas filas lado a lado) até a frenagem da 1ª chicane.
func _planned_lateral(at_s: float, at_progress: float) -> float:
	var lat := line.lateral_at(at_s)
	if start_lateral != INF and at_progress < 520.0:
		# Mesma distância da linha que tinha no grid; converge antes da frenagem da 1ª chicane
		var keep := start_lateral - line.lateral_at(0.0)
		lat = lat + keep * (1.0 - smoothstep(280.0, 520.0, at_progress))
	return lat


## Ninguém perto (de 15 m atrás a 40 m à frente) na faixa `lateral`.
func _lane_clear(s: float, lateral: float) -> bool:
	for other: RaceEntry in manager.entries:
		if other == entry or other.car == null or other.retired:
			continue
		var ds := _ahead(other.s, s)
		if ds > -15.0 and ds < 40.0 and absf(other.lateral - lateral) < 2.6:
			return false
	return true


func _straight_ahead(s: float, distance: float) -> bool:
	var k := 0.0
	var steps := int(distance / 10.0)
	for n in steps:
		k = maxf(k, absf(RacingLine.sample(line.curvature, track.path, s + n * 10.0)))
	return k < 1.0 / 450.0


## Retorna Vector2(lateral alvo, velocidade máxima) na entrada/saída dos boxes.
func _pit_plan(s: float, v: float) -> Vector2:
	var lay := track.layout
	var p := track.path
	var side := lay.pit_side
	# Saindo, mira a faixa um pouco à frente (onde ela afunila para a pista o carro já vem junto)
	var i := p.index_at(s + (clampf(v * 0.6, 3.0, 25.0) if mode == Mode.PIT_OUT else 0.0))
	var hw := p.half_width(i, side)
	var w := track.pit_width[i]
	var d := minf(w * 0.55, LANE_FAST)
	var box_s := track.garage_s(entry.garage)
	var box_d := RaceTrack.PIT_WALL_STRIP + lay.pit_lane_width * 0.72
	var to_box := _ahead(box_s, s)
	if mode == Mode.PIT_IN and to_box < 45.0 and to_box > -3.0:
		d = lerpf(d, box_d, smoothstep(45.0, 12.0, to_box))
	if mode == Mode.PIT_OUT and to_box < 0.0 and to_box > -30.0:
		d = lerpf(box_d, d, smoothstep(0.0, -25.0, to_box))
	var lateral := side * (hw + d) if w > 0.5 else side * (hw - 1.6)
	_pit_lateral = lateral - line.lateral_at(s)
	# Velocidade: 80 km/h entre as linhas, parando no box
	var max_speed := INF
	var to_line := _ahead(lay.pit_entry_s + lay.pit_taper, s)
	if mode == Mode.PIT_IN:
		max_speed = sqrt(PIT_SPEED * PIT_SPEED + 2.0 * 14.0 * maxf(to_line - 6.0, 0.0)) if to_line > 0.0 else PIT_SPEED
		if to_box > -2.0 and to_box < 120.0:
			max_speed = minf(max_speed, sqrt(2.0 * 5.0 * maxf(to_box - 0.3, 0.0)))
	else:
		var to_exit_line := _ahead(lay.pit_exit_s - lay.pit_taper, s)
		max_speed = PIT_SPEED if to_exit_line > 0.0 else INF
	return Vector2(lateral, max_speed)


## Na pista dos boxes: fila indiana. Segue quem está na frente na mesma faixa (entrando ou saindo
## do box) com folga de 7 m, sem ultrapassar. Bots parados na vaga não contam: entre bots não há
## colisão nos boxes (RaceManager), e esperar por eles travaria quem sai da vaga de trás.
func _pit_traffic(s: float, my_lateral: float) -> float:
	var max_speed := INF
	for other: RaceEntry in manager.entries:
		if other == entry or other.car == null or other.retired or (other.in_pit_stop and not other.is_player):
			continue
		var ds := _ahead(other.s, s)
		if ds < 0.5 or ds > 45.0 or absf(other.lateral - my_lateral) > 2.6:
			continue
		var other_v := other.car.linear_velocity.length()
		max_speed = minf(max_speed, other_v + maxf(ds - 7.0, 0.0) * 0.7)
	return max_speed


## Ninguém chegando pela faixa rápida dos boxes nos 35 m de trás (ou logo ao lado).
func _pit_release_clear(s: float) -> bool:
	for other: RaceEntry in manager.entries:
		if other == entry or other.car == null or other.retired or not other.in_pit or other.in_pit_stop:
			continue
		# Bot parado na faixa (fila ou enroscado) não segura a saída: entre bots não há colisão nos
		# boxes, e esperar por ele travaria os dois
		if not other.is_player and other.car.linear_velocity.length() < 1.0:
			continue
		var ds := _ahead(other.s, s)
		if ds > -35.0 and ds < 6.0:
			return false
	return true


## Preso (parado fora dos boxes) por alguns segundos: volta para a linha de corrida.
func _check_stuck(delta: float, v: float) -> void:
	# Enroscado na entrada da vaga (pit lane estreita): depois de alguns segundos, vai direto para ela
	if mode == Mode.PIT_IN and v < 1.0 and absf(_ahead(track.garage_s(entry.garage), entry.s)) < 30.0:
		_stuck_timer += delta
		if _stuck_timer > 5.0:
			_stuck_timer = 0.0
			car.global_transform = track.get_pit_box_transform(entry.garage)
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			car.reset_physics_interpolation()
			car.reset_frame = Engine.get_physics_frames()
		return
	if mode != Mode.RACE or v > 2.0:
		_stuck_timer = 0.0
		return
	_stuck_timer += delta
	if _stuck_timer > 4.0:
		var s := entry.s
		# Só volta para a pista com um vão no tráfego (ninguém chegando nos próximos 150 m)
		for other: RaceEntry in manager.entries:
			if other != entry and other.car and not other.retired:
				var ds := _ahead(other.s, s)
				if ds > -150.0 and ds < 15.0:
					return
		_stuck_timer = 0.0
		car.global_transform = track.path.frame_at(s, line.lateral_at(s), 0.3)
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.reset_physics_interpolation()
		car.reset_frame = Engine.get_physics_frames()
