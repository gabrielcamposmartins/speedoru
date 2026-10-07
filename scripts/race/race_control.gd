class_name RaceControl
extends Node
## Direção de prova: bandeira amarela, safety car e as regras sob amarela (filho do RaceManager).
##
## * Batida que arranca peça (ou quebra roda) → o carro fica "envolvido" e a bandeira amarela entra
##   (se ainda não estava). O safety car aparece à frente do líder.
## * Envolvido: aperta o botão de ir aos boxes (go_to_pit) → teletransporte para o box e conserto;
##   ou vai sozinho até o box; se não chegar em uma volta (tempo da melhor volta, ou 110 s), é
##   levado ao box automaticamente. Bots vão ao box sozinhos depois de alguns segundos. Quem é
##   levado ao box (botão, tempo esgotado ou bot) recomeça a volta em andamento: ao sair do box e
##   cruzar a linha ela começa de novo, sem contar como completada (quem vai dirigindo até o box
##   segue a volta normalmente).
## * O safety car (e a bandeira amarela) dura uma volta inteira a partir de onde entrou na pista;
##   uma batida nova durante a amarela não a prolonga. Os consertos seguem independentes dela.
## * Sob amarela, para quem não está envolvido (fica a cargo do jogador; quem não segue é punido):
##   - não ultrapassar (a não ser quem está nos boxes ou envolvido) → +5 s por ultrapassagem;
##   - não passar o safety car → +10 s.
##   O limitador não é obrigatório (é só um jeito fácil de andar devagar atrás do safety car).
##   Quem não bateu pode aproveitar para trocar pneus; isso não muda o estado da bandeira.

signal flag_changed(yellow: bool)

const BOT_PIT_DELAY := 3.5
const DEFAULT_LAP := 110.0
const REPAIR_TIME := 6.0

var manager: RaceManager
var yellow := false
var safety_car: SafetyCar
## Envolvidos: RaceEntry -> {"time_left": s, "bot_delay": s, "in_box": bool}
var involved := {}

## Rede (cliente): só espelha o estado que vem do servidor (sem regras nem punições aqui).
var mirror := false

var _yellow_time := 0.0
var _sc_target := 0.0
## Progresso em que o safety car termina a volta (onde entrou + uma volta).
var sc_end := 0.0
var _flagged := {}
var _prev_progress := {}


func setup(p_manager: RaceManager) -> void:
	manager = p_manager
	if mirror:
		return
	for e in manager.entries:
		_watch(e)


func _watch(e: RaceEntry) -> void:
	var damage := e.car.get_node_or_null("Damage") as CarDamage
	if damage and not damage.part_detached.is_connected(_on_part_detached):
		damage.part_detached.connect(_on_part_detached.bind(e))


func _on_part_detached(_piece: String, e: RaceEntry) -> void:
	report_crash(e)


func is_involved(e: RaceEntry) -> bool:
	return involved.has(e)


## Batida forte (peça arrancada / roda quebrada): entra a amarela.
func report_crash(e: RaceEntry) -> void:
	if manager.state != RaceManager.State.RACING or e.finished or e.retired or involved.has(e) or e.in_pit_stop:
		return
	var lap := e.best_lap if e.best_lap > 0.0 else DEFAULT_LAP
	involved[e] = {"time_left": lap, "bot_delay": BOT_PIT_DELAY, "in_box": false}
	manager.notify_entry(e, "BATIDA", "Vá aos boxes para consertar o carro", false)
	if not yellow:
		_start_yellow()


func _start_yellow() -> void:
	yellow = true
	_yellow_time = 0.0
	_flagged.clear()
	_prev_progress.clear()
	var leader := _leader()
	if leader and manager.line:
		safety_car = SafetyCar.new()
		safety_car.name = "SafetyCar"
		manager.get_parent().add_child(safety_car)
		safety_car.profile = manager._profile(BotDriver.Difficulty.EASY)
		safety_car.setup(manager.track, manager.line, leader.progress + 60.0)
		sc_end = safety_car.progress + manager.track.path.length
	for e in manager.entries:
		if e.is_player and not involved.has(e):
			manager.notify_entry(e, "BANDEIRA AMARELA", "Safety car por uma volta: não ultrapasse e não passe o safety car", false)
	flag_changed.emit(true)


func _end_yellow() -> void:
	yellow = false
	if safety_car:
		safety_car.queue_free()
		safety_car = null
	for e in manager.entries:
		if e.is_player:
			manager.notify_entry(e, "BANDEIRA VERDE", "Safety car saiu: pista liberada", false)
	flag_changed.emit(false)


## Líder entre os carros que não estão envolvidos (o safety car fica à frente dele).
func _leader() -> RaceEntry:
	var best: RaceEntry = null
	for e in manager.entries:
		if e.retired or e.finished or involved.has(e) or e.in_pit_stop:
			continue
		if best == null or e.progress > best.progress:
			best = e
	return best


## Teletransporte para o box da equipe e conserto (botão, tempo esgotado ou bot).
func send_to_pit(e: RaceEntry) -> void:
	if not involved.has(e) or involved[e]["in_box"]:
		return
	involved[e]["in_box"] = true
	var car := e.car
	var box := manager.track.get_pit_box_transform(e.garage)
	car.global_transform = box
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_physics_interpolation()
	# Recomeça a volta em andamento. O box fica antes da linha: volta um cruzamento, e o próximo
	# (saindo do box) só marca o novo início da mesma volta. Se ficasse depois, recomeçaria já.
	var length := manager.track.path.length
	var pr := manager.track.path.project(car.global_position)
	e.s = pr.x
	e.lateral = pr.y
	if e.s > length * 0.5:
		e.crossings -= 1
		e.lap_restart = true
	e.progress = (e.crossings - 1) * length + e.s
	e.lap_start = manager.race_time
	e.lap_invalid = false
	# Marcas de progresso (intervalos) da parte que vai ser refeita são apagadas
	var index := int(floor((e.progress + length) / RaceManager.CHECKPOINT))
	if index < e.checkpoint_times.size():
		e.checkpoint_times.resize(maxi(index + 1, 0))
	if e.bot:
		e.bot.force_pit_stop(REPAIR_TIME)
	else:
		manager.begin_player_pit(e, REPAIR_TIME)


## Fim de um pit stop (chamado pelo RaceManager): se era um envolvido, sai da lista.
func on_pit_done(e: RaceEntry) -> void:
	if not involved.has(e):
		return
	involved.erase(e)
	_flagged.erase(e)
	# Sem safety car (não havia líder/linha ideal): a amarela acaba com o último conserto
	if involved.is_empty() and yellow and safety_car == null:
		_end_yellow()


func physics_update(delta: float) -> void:
	if manager.state != RaceManager.State.RACING:
		return
	# Envolvidos: bots vão ao box sozinhos; jogador tem uma volta, depois vai à força
	for e in involved.keys():
		var info: Dictionary = involved[e]
		if e.retired or e.finished:
			involved.erase(e)
			continue
		if info["in_box"] or e.in_pit_stop:
			continue
		if e.bot:
			info["bot_delay"] -= delta
			if info["bot_delay"] <= 0.0:
				send_to_pit(e)
		else:
			info["time_left"] -= delta
			if info["time_left"] <= 0.0:
				manager.notify_entry(e, "BOXES", "Tempo esgotado: levado aos boxes", false)
				send_to_pit(e)
	if not yellow:
		return
	_yellow_time += delta
	var leader := _leader()
	if safety_car and leader:
		safety_car.advance(delta, leader.progress)
	# O safety car fica uma volta inteira a partir de onde entrou
	if (safety_car and safety_car.progress >= sc_end) or (safety_car == null and involved.is_empty()):
		_end_yellow()
		return
	_check_rules(delta)


func _subject(e: RaceEntry) -> bool:
	return not (e.retired or e.finished or involved.has(e) or e.in_pit or e.in_pit_stop)


func _check_rules(_delta: float) -> void:
	var subjects: Array[RaceEntry] = []
	for e in manager.entries:
		if _subject(e):
			subjects.append(e)
	for e in subjects:
		# Safety car
		if safety_car and e.progress > safety_car.progress + 2.0 and not _flagged.has([e, "sc"]):
			_flagged[[e, "sc"]] = true
			manager.penalize_entry(e, 10.0, "SAFETY CAR", "Ultrapassou o safety car")
	# Ultrapassagens entre quem está sujeito às regras (quem está nos boxes ou envolvido pode ser passado)
	for a in subjects:
		for b in subjects:
			if a == b or not _prev_progress.has(a) or not _prev_progress.has(b):
				continue
			var was_behind: bool = _prev_progress[a] < _prev_progress[b] - 0.5
			var now_ahead := a.progress > b.progress + 1.5
			if was_behind and now_ahead and not _flagged.has([a, b]):
				_flagged[[a, b]] = true
				manager.penalize_entry(a, 5.0, "ULTRAPASSAGEM", "Passou %s sob bandeira amarela" % b.code)
	_prev_progress.clear()
	for e in subjects:
		_prev_progress[e] = e.progress


## Texto de instrução para o jogador (HUD), com a tecla da ação: [título, instrução, urgente].
func instruction_for(e: RaceEntry) -> Array:
	if e == null:
		return []
	if involved.has(e) and not involved[e]["in_box"] and not e.in_pit_stop:
		var t: float = involved[e]["time_left"]
		return ["BATIDA", "Pressione %s para ir aos boxes ou vá sozinho %d:%02d" % [
			key_label("go_to_pit"), int(t) / 60, int(t) % 60], true]
	if involved.has(e):
		return ["BOXES", "Consertando o carro…", false]
	if yellow:
		if e.in_pit_stop:
			return ["BANDEIRA AMARELA", "Pit stop durante a amarela", false]
		return ["BANDEIRA AMARELA", "Não ultrapasse · não passe o safety car%s" % sc_left_text(), false]
	if e.in_pit and not e.in_pit_stop and not e.car.limiter_on:
		return ["BOXES", "Pressione %s para ativar o limitador (80 km/h)" % key_label("pit_limiter"), true]
	return []


## Quanto falta da volta do safety car (" · safety car sai em 2,3 km").
func sc_left_text() -> String:
	if safety_car == null:
		return ""
	var left := maxf(sc_end - safety_car.progress, 0.0)
	return " · safety car sai em %s" % ("%.1f km" % (left / 1000.0)).replace(".", ",")


## Nome da tecla (ou botão do controle, se o jogador está usando controle) de uma ação.
static func key_label(action: String) -> String:
	var settings := Engine.get_main_loop().root.get_node_or_null("Settings") as GameSettings if Engine.get_main_loop() else null
	if settings == null:
		return action
	var ev := settings.get_binding(action, Retro.using_pad)
	if ev == null:
		ev = settings.get_binding(action, not Retro.using_pad)
	return "[%s]" % GameSettings.event_label(ev)


# ---------------------------------------------------------------------------
# Rede (cliente)
# ---------------------------------------------------------------------------
func apply_mirror(d: Dictionary, roster: Array[RaceEntry]) -> void:
	var was := yellow
	yellow = bool(d.get("yellow", false))
	involved.clear()
	var inv: Dictionary = d.get("involved", {})
	for idx in inv:
		if int(idx) < roster.size():
			involved[roster[int(idx)]] = {"time_left": float(inv[idx][0]), "in_box": bool(inv[idx][1]), "bot_delay": 0.0}
	var sc: Array = d.get("sc", [])
	if sc.size() >= 2 and manager.line:
		if safety_car == null:
			safety_car = SafetyCar.new()
			safety_car.name = "SafetyCar"
			manager.get_parent().add_child(safety_car)
			safety_car.setup(manager.track, manager.line, float(sc[0]))
		_sc_target = float(sc[0])
		safety_car.speed = float(sc[1])
		if sc.size() >= 3:
			sc_end = float(sc[2])
	elif safety_car:
		safety_car.queue_free()
		safety_car = null
	if yellow != was:
		flag_changed.emit(yellow)


## Entre um estado e outro: anda o safety car e conta o tempo dos envolvidos.
func mirror_update(delta: float) -> void:
	for e in involved:
		involved[e]["time_left"] = maxf(float(involved[e]["time_left"]) - delta, 0.0)
	if safety_car:
		_sc_target += safety_car.speed * delta
		safety_car.progress = lerpf(safety_car.progress + safety_car.speed * delta, _sc_target, minf(delta * 3.0, 1.0))
		safety_car._place()
