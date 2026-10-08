class_name Qualifying
extends Node
## Classificatória antes da corrida (escolhida no menu solo e na sala online).
##
## Os carros saem espalhados pela pista (antes da linha de chegada, longe uns dos outros), fazem a
## volta de saída e depois `laps` voltas cronometradas (ou voltas livres, `laps` < 0, até o tempo
## acabar). Vale a melhor volta VÁLIDA: com `strict`, sair da pista (as quatro rodas além da borda e
## da zebra) ou levar qualquer penalidade anula a volta em andamento (sem somar segundos na corrida);
## sem `strict` as infrações não têm efeito. Com `collisions` falso os carros se atravessam.
## Tempo limite (`time_limit`, s): quando acaba, ninguém começa volta nova, mas quem já está numa
## volta cronometrada pode terminá-la (como na F1). No fim, o grid é a ordem das melhores voltas
## (quem não marcou tempo larga atrás, na ordem original) e todos voltam para as posições de
## largada com o carro consertado.

signal finished

## Espaço (m) entre os carros na saída.
const SPACING := 150.0
## Quanto o centro do carro pode passar da borda (além da zebra) antes de a volta ser anulada:
## ~meia largura do carro, ou seja, as quatro rodas fora da pista (como na F1).
const OFF_TRACK_MARGIN := 1.05

var manager: RaceManager
## Voltas cronometradas (-1 = livres até o tempo acabar).
var laps := 1
var collisions := true
## Tempo limite da sessão (s; 0 = sem limite) e se infrações anulam a volta.
var time_limit := 0.0
var strict := true
## O tempo acabou (bandeira quadriculada da sessão).
var time_up := false
var active := false
## entry -> {best, laps, start, invalid, done}
var data := {}
var _added_exceptions: Array = []
var _removed_ghosts: Array = []
var _saved_pit_laps := {}
var _saved_profiles := {}


func setup(p_manager: RaceManager, p_laps: int, p_collisions: bool, p_time_limit := 0.0, p_strict := true) -> void:
	manager = p_manager
	laps = p_laps if p_laps > 0 else -1
	collisions = p_collisions
	time_limit = maxf(p_time_limit, 0.0)
	strict = p_strict
	if laps < 0 and time_limit <= 0.0:
		time_limit = RaceSettings.QUALI_FREE_MINUTES * 60.0


## Segundos que faltam da sessão (-1 = sem limite).
func time_left() -> float:
	return maxf(time_limit - manager.race_time, 0.0) if time_limit > 0.0 else -1.0


## Roda a sessão inteira (aguardar com await). Ao voltar, entries[].grid_slot já está na ordem nova.
func run() -> void:
	var m := manager
	var p := m.track.path
	active = true
	m.state = RaceManager.State.QUALIFYING
	m.race_time = 0.0
	_set_collisions()
	var order: Array = m.entries.duplicate()
	order.sort_custom(func(a: RaceEntry, b: RaceEntry) -> bool: return a.grid_slot < b.grid_slot)
	for k in order.size():
		var e: RaceEntry = order[k]
		var s := fposmod(-70.0 - k * SPACING, p.length)
		var lat := m.line.lateral_at(s) if m.line else 0.0
		e.car.global_transform = p.frame_at(s, lat, 0.3)
		e.car.linear_velocity = p.tangent_at(s) * 8.0
		e.car.angular_velocity = Vector3.ZERO
		e.car.reset_physics_interpolation()
		e.car.hold = false
		m._init_position(e)
		e.lap_start = 0.0
		e.last_lap = 0.0
		e.best_lap = 0.0
		data[e] = {"best": 0.0, "laps": 0, "start": -1.0, "invalid": false, "done": false}
		if e.bot:
			_saved_pit_laps[e] = e.bot.pit_lap
			_saved_profiles[e] = e.bot.profile
			e.bot.pit_lap = -1
			e.bot.released = true
	m.state_changed.emit(m.state)
	var what := "voltas livres" if laps < 0 else ("%d volta cronometrada" % laps if laps == 1 else "%d voltas cronometradas" % laps)
	var rules := "Sair da pista ou levar penalidade anula a volta" if strict else "Infrações não anulam a volta"
	var clock := " · %d min" % roundi(time_limit / 60.0) if time_limit > 0.0 else ""
	for e in m.entries:
		if e.is_player or e.is_human:
			m.notify_entry(e, "CLASSIFICATÓRIA", "Volta de saída + %s%s. %s%s" % [what, clock, rules, "" if collisions else " · sem colisão"], false)
	# Limite de segurança: com tempo, o tempo + uma volta lenta para terminar a que estava em andamento
	var lap_guess := p.length / 26.0
	var hard := time_limit + lap_guess + 30.0 if time_limit > 0.0 else (laps + 1) * lap_guess + 45.0
	while m.race_time < hard and not _all_done():
		if time_limit > 0.0 and not time_up and m.race_time >= time_limit:
			_on_time_up()
		await get_tree().physics_frame
	_finish()


## Acabou o tempo: quem não está numa volta cronometrada válida encerra; os outros terminam a volta.
func _on_time_up() -> void:
	time_up = true
	for e: RaceEntry in data:
		var d: Dictionary = data[e]
		if d["done"]:
			continue
		var running: bool = d["start"] >= 0.0 and not d["invalid"]
		if not running:
			d["done"] = true
		if e.is_player or e.is_human:
			if running:
				manager.notify_entry(e, "TEMPO ESGOTADO", "Termine a volta em andamento: ela ainda vale", false)
			else:
				manager.notify_entry(e, "TEMPO ESGOTADO", "Classificatória encerrada · aguarde os outros pilotos", false)


func _all_done() -> bool:
	for e in data:
		var d: Dictionary = data[e]
		if not d["done"] and not (e as RaceEntry).retired:
			return false
	return true


## A cada passo de física (RaceManager): volta anulada ao sair da pista ou ao ir rápido para o box.
func physics_update(_delta: float) -> void:
	var p := manager.track.path
	for e: RaceEntry in data:
		var d: Dictionary = data[e]
		if d["done"]:
			continue
		if e.lap_restart:
			# Ida rápida aos boxes: a volta recomeça como volta de saída
			e.lap_restart = false
			d["start"] = -1.0
			d["invalid"] = false
			continue
		if not strict or d["start"] < 0.0 or d["invalid"] or e.in_pit:
			continue
		var i := p.index_at(e.s)
		var side := 1 if e.lateral >= 0.0 else -1
		var kerb := manager.track.layout.kerb_width * manager.track.kerb[RaceTrack._si(side)][i]
		if absf(e.lateral) > p.half_width(i, side) + kerb + OFF_TRACK_MARGIN:
			invalidate(e, "SAIU DA PISTA")


## Anula a volta cronometrada em andamento (sair da pista, penalidade). Sem `strict`, não faz nada.
func invalidate(e: RaceEntry, reason: String) -> void:
	if not data.has(e) or not strict:
		return
	var d: Dictionary = data[e]
	if d["done"] or d["start"] < 0.0 or d["invalid"]:
		return
	d["invalid"] = true
	e.lap_invalid = true
	manager.notify_entry(e, "VOLTA ANULADA", reason, true)


## Passou pela linha de chegada.
func on_cross(e: RaceEntry) -> void:
	if not data.has(e):
		return
	var d: Dictionary = data[e]
	var now := manager.race_time
	e.lap_start = now
	if d["done"]:
		return
	if d["start"] < 0.0:
		if time_up:
			d["done"] = true
			return
		# Fim da volta de saída: começa a primeira cronometrada
		d["start"] = now
		d["invalid"] = false
		e.lap_invalid = false
		return
	var lap: float = now - d["start"]
	d["laps"] += 1
	e.last_lap = lap
	if not d["invalid"]:
		if d["best"] <= 0.0 or lap < d["best"]:
			d["best"] = lap
			e.best_lap = lap
		manager.notify_entry(e, "VOLTA %s  %s" % [_lap_label(d["laps"]), RaceManager.format_time(lap)],
			"Melhor: %s" % RaceManager.format_time(d["best"]), false)
	else:
		manager.notify_entry(e, "VOLTA %s ANULADA" % _lap_label(d["laps"]), "Não conta para o grid", true)
	d["start"] = now
	d["invalid"] = false
	e.lap_invalid = false
	if time_up or (laps > 0 and d["laps"] >= laps):
		d["done"] = true
		if e.bot:
			e.bot.profile = manager._slow_profile(e.bot.profile)
		if e.is_player or e.is_human:
			manager.notify_entry(e, "CLASSIFICATÓRIA CONCLUÍDA", "Aguarde os outros pilotos", false)


## "2/3" (voltas contadas) ou só "2" (voltas livres).
func _lap_label(n: int) -> String:
	return str(n) if laps < 0 else "%d/%d" % [n, laps]


## Melhor volta válida de cada carro (0 = sem tempo).
func best_of(e: RaceEntry) -> float:
	return float((data.get(e, {}) as Dictionary).get("best", 0.0))


## Ordem do grid: melhores voltas primeiro; sem tempo, na ordem original.
func classification() -> Array:
	var out: Array = manager.entries.duplicate()
	out.sort_custom(func(a: RaceEntry, b: RaceEntry) -> bool:
		var ta := best_of(a)
		var tb := best_of(b)
		if (ta > 0.0) != (tb > 0.0):
			return ta > 0.0
		if ta > 0.0 and ta != tb:
			return ta < tb
		return a.grid_slot < b.grid_slot)
	return out


func _finish() -> void:
	var m := manager
	var order := classification()
	for k in order.size():
		var e: RaceEntry = order[k]
		e.grid_slot = k
		if e.is_player or e.is_human:
			var t := best_of(e)
			m.notify_entry(e, "VOCÊ LARGA EM P%d" % (k + 1), "Melhor volta: %s" % (RaceManager.format_time(t) if t > 0.0 else "sem tempo"), false)
	_restore_collisions()
	for e: RaceEntry in m.entries:
		if e.bot:
			e.bot.pit_lap = _saved_pit_laps.get(e, e.bot.pit_lap)
			e.bot.released = false
			e.bot.profile = _saved_profiles.get(e, e.bot.profile)
			e.bot.mode = BotDriver.Mode.RACE
		# Corrida começa do zero: voltas, tempos, penalidades, pneus e dano
		e.lap_times.clear()
		e.best_lap = 0.0
		e.last_lap = 0.0
		e.lap_invalid = false
		e.lap_restart = false
		e.penalty_seconds = 0.0
		e.penalties.clear()
		e.penalty_log.clear()
		e.track_limit_warnings = 0
		e.checkpoint_times.clear()
		e.pit_count = 0
		e.compounds_used.clear()
		e.pit_served = false
		e.off_time = 0.0
		e.off_distance = 0.0
		m._repair(e)
	m.fastest_lap = 0.0
	m.fastest_entry = null
	active = false
	finished.emit()


func _set_collisions() -> void:
	var m := manager
	for a: RaceEntry in m.entries:
		for b: RaceEntry in m.entries:
			if a.get_instance_id() >= b.get_instance_id():
				continue
			if collisions:
				# Com colisão: tira os "fantasmas" da largada entre bots (voltam depois)
				for pair in m._ghost_pairs:
					if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
						a.car.remove_collision_exception_with(b.car)
						_removed_ghosts.append([a, b])
			else:
				a.car.add_collision_exception_with(b.car)
				_added_exceptions.append([a, b])


func _restore_collisions() -> void:
	for pair in _added_exceptions:
		var a: RaceEntry = pair[0]
		var b: RaceEntry = pair[1]
		var ghost := false
		for g in manager._ghost_pairs:
			if (g[0] == a and g[1] == b) or (g[0] == b and g[1] == a):
				ghost = true
		if not ghost:
			a.car.remove_collision_exception_with(b.car)
	for pair in _removed_ghosts:
		(pair[0] as RaceEntry).car.add_collision_exception_with((pair[1] as RaceEntry).car)
	_added_exceptions.clear()
	_removed_ghosts.clear()
