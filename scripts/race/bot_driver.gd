class_name BotDriver
extends Node
## Piloto controlado pelo computador. Filho do F1Car (que fica com player_controlled = false);
## roda antes dele em cada passo de física e escreve throttle/brake/steer.
##
## * Direção: "pure pursuit" num ponto à frente na linha de corrida (+ deslocamento lateral para
##   ultrapassar/desviar ou para entrar nos boxes).
## * Velocidade: perfil da linha (RacingLine.speed_profile) para a dificuldade; segue o carro da
##   frente quando não dá para passar.
## * Ultrapassagem sem medo: começa com reta suficiente (PASS_STRAIGHT) e um pouco mais rápido que o
##   da frente, segue perto (pega o vácuo) e não desiste já lado a lado na entrada da curva; evita a
##   batida abrindo espaço lado a lado, tirando o pé se sobrepõe e só voltando para a linha 10 m à
##   frente de quem passou.
## * Pit stop: na volta escolhida entra nos boxes, respeita 80 km/h, para no box da equipe, troca
##   os pneus e volta à pista. Só vai para a faixa da vaga nos últimos BOX_APPROACH m (não passa por
##   cima das vagas vizinhas) e, na pista dos boxes, espera qualquer carro que esteja no caminho
##   que vai fazer — inclusive parado na vaga e humanos.
## * Preso (encostado no muro, rodado, parado sem avançar): dá ré esterçando para apontar de volta
##   para a pista (até RECOVER_TRIES vezes); se não sair, é levado de volta à pista num vão do
##   tráfego.
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
## Ultrapassagem: reta à frente (m) para começar, quanto mais rápido que o da frente (m/s, por
## dificuldade) e até que distância (m) começa.
const PASS_STRAIGHT := 90.0
const PASS_MARGIN := [2.0, 0.4, 0.2]
const PASS_RANGE := 60.0
## Boxes: distância (m) antes/depois da vaga em que o carro passa entre a faixa rápida e a da vaga.
const BOX_APPROACH := 18.0
## Preso: avanço mínimo (m) por segundo querendo andar, ré (s) e tentativas antes de voltar à pista.
const STUCK_PROGRESS := 2.5
const RECOVER_TIME := 1.6
## A cada nova tentativa a ré dura mais isso (s): o carro precisa recuar mais para girar.
const RECOVER_TIME_STEP := 0.8
const RECOVER_TRIES := 3
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
## Contadores (testes/diagnóstico): ré para sair do muro e volta à pista.
static var reversals := 0
static var put_backs := 0
## Preso: progresso de referência, tempo da janela, ré em andamento (s), tentativas e tempo total.
var _prog_ref := 0.0
var _prog_t := 0.0
var _recover := 0.0
var _recover_tries := 0
var _stuck_total := 0.0
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


## Tráfego recalculado a cada TRAFFIC_EVERY passos de física (a 120 Hz, 60 vezes por segundo),
## intercalado entre os bots; nos outros passos vale o último resultado.
const TRAFFIC_EVERY := 2
var _traffic_cache := Vector2(0.0, INF)
var _traffic_phase := randi() % TRAFFIC_EVERY


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
		# Sob amarela, a cada passo (a regra de não ultrapassar é justa)
		if (Engine.get_physics_frames() + _traffic_phase) % TRAFFIC_EVERY == 0 or _traffic_cache.y == INF or yellow:
			_offset_target = 0.0
			_traffic_cache = _traffic(s, v, entry.lateral)
		var traffic := _traffic_cache
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
	if _recover > 0.0:
		_reverse_out(delta, s, v, target_lateral)
		return
	car.reverse_input = 0.0
	_steer(s, v, target_lateral)
	_speed(v, speed_target)
	_check_stuck(delta, v, speed_target)


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
## Pessoa (o jogador local ou um humano na corrida online): mais espaço e passagem.
static func _person(e: RaceEntry) -> bool:
	return e.is_player or e.is_human


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
	var straight := _straight_ahead(s, PASS_STRAIGHT)
	# Continua (ou desiste de) uma ultrapassagem em andamento
	if _passing and manager.control and manager.control.yellow and not manager.control.is_involved(_passing) \
			and not manager.control.is_involved(entry):
		_passing = null
	if _passing:
		var ds_pass := _ahead(_passing.s, s)
		# Desiste se ainda não chegou ao lado dele e a curva está perto, ou se está POR FORA da curva
		# que chega sem já estar à frente (por fora, lado a lado, sai da pista); por dentro, segue
		var corner_near := not _straight_ahead(s, 40.0)
		if ds_pass < -10.0 or ds_pass > PASS_RANGE + 10.0 or _passing.in_pit \
				or (corner_near and ds_pass > 6.0) \
				or (corner_near and ds_pass > -3.0 and _pass_side != _corner_inside(s, 60.0)):
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
		if yields and _person(other) and ds < -1.0 and ds > -YIELD_RANGE and ds > attacker_ds 				and (other.car.linear_velocity.length() > v - 0.5 or ds > -8.0):
			attacker = other
			attacker_ds = ds
		if ds < -8.0 or ds > 90.0:
			continue
		# Onde eu vou estar quando chegar lá (inclui a faixa do grid no começo); de perto vale
		# também onde eu estou agora (o plano pode não bater com a posição real no meio do pelotão)
		var my_there := _planned_lateral(other.s, entry.progress + ds) + _offset
		var dlat := other.lateral - my_there
		# Em volta de um humano a faixa "ocupada" é um pouco mais larga (mais respeito, menos batida)
		var width := 2.9 if _person(other) else 2.5
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
			if yields and _person(other):
				max_speed = minf(max_speed, _yield_speed(s))
			# Colado atrás e sobrepondo (carros têm 2 m de largura): tira o pé antes de tocar
			if ds > 0.5 and absf(other.lateral - my_lateral) < 2.1:
				max_speed = minf(max_speed, other.car.linear_velocity.length() - 2.0)
	if follow:
		var other_v := follow.car.linear_velocity.length()
		var quicker := v > other_v + float(PASS_MARGIN[difficulty])
		var side_choice := 0.0
		var yellow_ok := manager.control == null or not manager.control.yellow or manager.control.is_involved(follow) \
				or manager.control.is_involved(entry)
		if _passing == null and straight and quicker and follow_ds < PASS_RANGE and entry.progress > 1100.0 and yellow_ok:
			var room_left := track.path.width_left[i] - follow.lateral
			var room_right := follow.lateral + track.path.width_right[i]
			# Prefere o lado de dentro da próxima curva (chega nela por dentro); sem curva perto, o
			# lado com mais espaço
			var inside := _corner_inside(s, 160.0)
			var first := inside if inside != 0.0 else (1.0 if room_left > room_right else -1.0)
			for side: float in [first, -first]:
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
			# Perto o bastante para pegar o vácuo; a velocidade de frenagem segura a batida
			var gap := 6.0 + v * 0.17 + (3.0 if _person(follow) else 0.0)
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


## Lado de dentro (+1 esquerda, -1 direita) da curva mais forte nos próximos `distance` m; 0 se
## não há curva (pela direção da pista: para que lado a tangente gira).
func _corner_inside(s: float, distance: float) -> float:
	var p := track.path
	var best := 0.0
	var at := -1.0
	for n in int(distance / 10.0):
		var k := absf(RacingLine.sample(line.curvature, p, s + n * 10.0))
		if k > best:
			best = k
			at = s + n * 10.0
	if best < 1.0 / 450.0:
		return 0.0
	var turn := p.tangent_at(at + 15.0).dot(p.lefts[p.index_at(at - 15.0)])
	return 1.0 if turn > 0.0 else -1.0


func _straight_ahead(s: float, distance: float) -> bool:
	var k := 0.0
	var steps := int(distance / 10.0)
	for n in steps:
		k = maxf(k, absf(RacingLine.sample(line.curvature, track.path, s + n * 10.0)))
	return k < 1.0 / 450.0


## Retorna Vector2(lateral alvo, velocidade máxima) na entrada/saída dos boxes.
func _pit_plan(s: float, v: float) -> Vector2:
	var lay := track.layout
	var lateral := _pit_lane_lateral(s + (clampf(v * 0.6, 3.0, 25.0) if mode == Mode.PIT_OUT else 0.0), s)
	var box_s := track.garage_s(entry.garage)
	var to_box := _ahead(box_s, s)
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


## Lateral (com sinal) da faixa dos boxes que este carro segue no ponto `at_s` (a faixa rápida e,
## nos últimos BOX_APPROACH m antes da vaga / depois dela, a faixa da vaga). `now_s`: onde o carro
## está (decide se ele ainda vai para a vaga ou já saiu dela).
func _pit_lane_lateral(at_s: float, now_s: float) -> float:
	var lay := track.layout
	var p := track.path
	var side := lay.pit_side
	var i := p.index_at(at_s)
	var hw := p.half_width(i, side)
	var w := track.pit_width[i]
	var d := minf(w * 0.55, LANE_FAST)
	var box_d := RaceTrack.PIT_WALL_STRIP + lay.pit_lane_width * 0.72
	var to_box := _ahead(track.garage_s(entry.garage), at_s)
	var going_in := mode == Mode.PIT_IN and _ahead(track.garage_s(entry.garage), now_s) > -3.0
	if going_in and to_box < BOX_APPROACH and to_box > -3.0:
		d = lerpf(d, box_d, smoothstep(BOX_APPROACH, 4.0, to_box))
	if mode == Mode.PIT_OUT and to_box < 0.0 and to_box > -BOX_APPROACH:
		d = lerpf(box_d, d, smoothstep(-1.0, -BOX_APPROACH + 2.0, to_box))
	return side * (hw + d) if w > 0.5 else side * (hw - 1.6)


## Na pista dos boxes: fila indiana. Espera quem estiver no caminho que este carro vai fazer (na
## faixa rápida, entrando ou saindo de uma vaga, ou parado na vaga perto da sua), com folga de 7 m.
func _pit_traffic(s: float, my_lateral: float) -> float:
	var max_speed := INF
	for other: RaceEntry in manager.entries:
		if other == entry or other.car == null or other.retired:
			continue
		var ds := _ahead(other.s, s)
		if ds < 0.5 or ds > 45.0:
			continue
		# No caminho: perto de onde eu vou passar quando chegar lá (ou de onde estou, se colado)
		var my_there := _pit_lane_lateral(other.s, s)
		if absf(other.lateral - my_there) > 2.4 and (ds > 6.0 or absf(other.lateral - my_lateral) > 2.4):
			continue
		var other_v := other.car.linear_velocity.length()
		# A velocidade que ainda dá para frear (6 m/s²) até 7 m atrás dele
		var room := ds - 7.0
		max_speed = minf(max_speed, other_v + room * 0.7 if room < 0.0 else sqrt(other_v * other_v + 2.0 * 6.0 * room))
	return max_speed


## Ninguém chegando pela faixa rápida dos boxes nos 35 m de trás (ou logo ao lado).
func _pit_release_clear(s: float) -> bool:
	for other: RaceEntry in manager.entries:
		if other == entry or other.car == null or other.retired or not other.in_pit or other.in_pit_stop:
			continue
		# Bot parado na faixa (fila ou enroscado) não segura a saída: entre bots não há colisão nos
		# boxes, e esperar por ele travaria os dois
		if not _person(other) and other.car.linear_velocity.length() < 1.0:
			continue
		# Quem não está avançando pela pista dos boxes (enroscado, girando as rodas) também não
		if other.car.linear_velocity.dot(track.path.tangent_at(other.s)) < 1.0:
			continue
		var ds := _ahead(other.s, s)
		# Quem vem mais rápido precisa de mais distância (2 s dele, no mínimo 35 m)
		var reach := maxf(35.0, other.car.linear_velocity.length() * 2.0)
		if ds > -reach and ds < 6.0:
			return false
	return true


## Ré para sair do muro: esterça ao contrário (de ré, o volante gira o carro para o outro lado),
## apontando o bico de volta para a pista; no fim volta a andar para a frente.
func _reverse_out(delta: float, s: float, v: float, target_lateral: float) -> void:
	_recover -= delta
	_steer(s, v, target_lateral)
	car.steer_input = -car.steer_input
	car.throttle_input = 0.0
	car.brake_input = 0.0
	car.reverse_input = 1.0 if _recover > 0.15 else 0.0
	if _recover <= 0.0:
		car.reverse_input = 0.0
		_prog_ref = entry.progress
		_prog_t = 0.0


## Leva o carro de volta à linha de corrida (na mesma posição da pista).
func _put_back(s: float) -> void:
	put_backs += 1
	_stuck_timer = 0.0
	_stuck_total = 0.0
	_recover_tries = 0
	car.global_transform = track.path.frame_at(s, line.lateral_at(s), 0.3)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_physics_interpolation()
	car.reset_frame = Engine.get_physics_frames()


## Lateral (com sinal) da faixa rápida dos boxes no ponto `at_s`.
func _fast_lane_lateral(at_s: float) -> float:
	var side := track.layout.pit_side
	var i := track.path.index_at(at_s)
	var w := track.pit_width[i]
	return side * (track.path.half_width(i, side) + minf(w * 0.55, LANE_FAST)) if w > 0.5 else side * (track.path.half_width(i, side) - 1.6)


## Ninguém de 2 m atrás a 25 m à frente do ponto, perto da lateral dada.
func _spot_clear(at_s: float, lateral: float) -> bool:
	for other: RaceEntry in manager.entries:
		if other == entry or other.car == null or other.retired:
			continue
		var ds := _ahead(other.s, at_s)
		if ds > -2.0 and ds < 25.0 and absf(other.lateral - lateral) < 2.6:
			return false
	return true


## Algum carro logo à frente (até 14 m) perto da minha faixa: parado por tráfego, não preso.
func _blocked_ahead() -> bool:
	for other: RaceEntry in manager.entries:
		if other == entry or other.car == null or other.retired:
			continue
		var ds := _ahead(other.s, entry.s)
		if ds > -2.0 and ds < 14.0 and absf(other.lateral - entry.lateral) < 3.5:
			return true
	return false


## Ninguém chegando (de `behind` m atrás a 15 m à frente).
func _gap_clear(s: float, behind: float) -> bool:
	for other: RaceEntry in manager.entries:
		if other != entry and other.car and not other.retired:
			var ds := _ahead(other.s, s)
			if ds > -behind and ds < 15.0:
				return false
	return true


## Preso: querendo andar (meta de velocidade razoável) mas quase sem avançar ao longo da pista
## (encostado no muro, de lado, rodado). Primeiro dá ré esterçando (RECOVER_TRIES vezes); se não
## sair, volta à pista num vão do tráfego (de 60 m; depois de mais 6 s, de 25 m).
func _check_stuck(delta: float, v: float, speed_target := INF) -> void:
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
	# Enroscado saindo do box (no carro da vaga vizinha ou no muro): vai para a faixa rápida logo à
	# frente, se ela estiver livre
	if mode == Mode.PIT_OUT and speed_target > 3.0 and not car.hold:
		_prog_t += delta
		if _prog_t >= 1.0:
			_stuck_timer = _stuck_timer + 1.0 if entry.progress - _prog_ref < 1.0 else 0.0
			_prog_ref = entry.progress
			_prog_t = 0.0
		if _stuck_timer >= 4.0:
			# Só a faixa à frente importa (quem está atrás espera por mim e não pode travar a saída)
			var ahead_s := entry.s + 8.0
			var fast := _fast_lane_lateral(ahead_s)
			if _spot_clear(ahead_s, fast):
				_stuck_timer = 0.0
				put_backs += 1
				car.global_transform = track.path.frame_at(ahead_s, fast, 0.3)
				car.linear_velocity = Vector3.ZERO
				car.angular_velocity = Vector3.ZERO
				car.reset_physics_interpolation()
				car.reset_frame = Engine.get_physics_frames()
		return
	if mode != Mode.RACE or speed_target < 6.0 or car.hold:
		_stuck_timer = 0.0
		_stuck_total = 0.0
		_prog_ref = entry.progress
		_prog_t = 0.0
		return
	_prog_t += delta
	if _prog_t >= 1.0:
		var gained := entry.progress - _prog_ref
		_prog_ref = entry.progress
		_prog_t = 0.0
		# Preso de verdade: quase parado e sem ninguém logo à frente (no pelotão, atrás de um carro
		# lento, não é muro)
		if gained < STUCK_PROGRESS and v < 3.0 and not _blocked_ahead():
			_stuck_timer += 1.0
		else:
			_stuck_timer = 0.0
			_stuck_total = 0.0
			_recover_tries = 0
	if _stuck_timer < 2.0:
		return
	_stuck_total += delta
	var s := entry.s
	if _recover_tries < RECOVER_TRIES:
		_recover = RECOVER_TIME + RECOVER_TIME_STEP * _recover_tries
		_recover_tries += 1
		reversals += 1
		_stuck_timer = 0.0
		return
	if _gap_clear(s, 60.0) or (_stuck_total > 6.0 and _gap_clear(s, 25.0)):
		_put_back(s)
