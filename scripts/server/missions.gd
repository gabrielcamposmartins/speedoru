class_name Missions
extends RefCounted
## Missões diárias (servidor): MISSIONS_PER_DAY por dia, iguais para todos, sorteadas pela data
## (horário de Brasília) num conjunto fixo (POOL). Cada corrida validada pelo servidor (online ou
## solo com a conta conectada) avança as missões; cada missão completa paga créditos na hora.
## Completar todas as missões da semana (segunda a domingo) dá o prêmio semanal: WEEK_CREDITS e um
## item exclusivo (ShopCatalog.EXCLUSIVE_POOL).
##
## O estado fica nos contadores da conta (account.counters["missions"]), sem tabela nova:
## {day, progress[], done[], week, week_done, week_paid}. A troca de dia e de semana é preguiçosa:
## o estado guardado de outro dia é zerado na próxima leitura.

const MISSIONS_PER_DAY := 3
const DAYS_PER_WEEK := 7
const WEEK_GOAL := MISSIONS_PER_DAY * DAYS_PER_WEEK
const WEEK_CREDITS := 3000
## Fuso das missões (Brasília, UTC−3): o dia vira à meia-noite daqui.
const TZ_OFFSET := -3 * 3600
## Posições a ganhar na missão "gain".
const GAIN_POSITIONS := 4

## [id, texto, meta, créditos]. %d = meta; %s = pista do dia.
const POOL := [
	["races", "Complete %d corridas", 3, 600],
	["podium", "Termine uma corrida no pódio", 1, 700],
	["win", "Vença uma corrida", 1, 1000],
	["laps", "Complete %d voltas", 15, 500],
	["clean", "Termine uma corrida sem penalidades", 1, 500],
	["fastest", "Faça a volta mais rápida de uma corrida", 1, 800],
	["track", "Termine uma corrida em %s", 1, 400],
	["night", "Termine uma corrida à noite", 1, 400],
	["gain", "Ganhe %d posições numa corrida", 1, 600],
	["online", "Complete %d corridas online", 2, 600],
]

## Testes: relógio simulado (unix, s); 0 = relógio de verdade.
static var now_override := 0


static func now() -> int:
	return now_override if now_override > 0 else int(Time.get_unix_time_from_system())


static func day_of(unix: int) -> int:
	return floori((unix + TZ_OFFSET) / 86400.0)


## Semana de segunda a domingo (o dia 0, 1/1/1970, foi uma quinta).
static func week_of(day: int) -> int:
	return floori((day + 3) / 7.0)


## Quando vira o dia (unix, s).
static func next_reset(unix: int) -> int:
	return (day_of(unix) + 1) * 86400 - TZ_OFFSET


## Missões de um dia: [{id, text, goal, credits, track?}], sempre as mesmas para o mesmo dia.
static func daily(day: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(day * 7919 + 17)
	var idx := range(POOL.size())
	# Embaralha (Fisher–Yates com o gerador do dia: o shuffle() usa o global)
	for k in range(idx.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp: int = idx[k]
		idx[k] = idx[j]
		idx[j] = tmp
	var out := []
	for k in MISSIONS_PER_DAY:
		var m: Array = POOL[idx[k]]
		var d := {"id": m[0], "goal": int(m[2]), "credits": int(m[3])}
		match str(m[0]):
			"track":
				var t: Dictionary = RaceSettings.TRACKS[rng.randi_range(0, RaceSettings.TRACKS.size() - 1)]
				d["track"] = t["id"]
				d["text"] = str(m[1]) % t["name"]
			"gain":
				d["text"] = str(m[1]) % GAIN_POSITIONS
			_:
				d["text"] = (str(m[1]) % int(m[2])) if "%d" in str(m[1]) else str(m[1])
		out.append(d)
	return out


## Estado das missões nos contadores, já no dia e na semana de hoje.
static func state(counters: Dictionary, unix := 0) -> Dictionary:
	var day := day_of(unix if unix > 0 else now())
	var week := week_of(day)
	var st: Variant = counters.get("missions")
	if not st is Dictionary:
		st = {}
	if int(st.get("week", -1)) != week:
		st["week"] = week
		st["week_done"] = 0
		st["week_paid"] = false
	if int(st.get("day", -1)) != day:
		st["day"] = day
		st["progress"] = []
		st["done"] = []
	var progress: Array = st.get("progress", [])
	var done: Array = st.get("done", [])
	while progress.size() < MISSIONS_PER_DAY:
		progress.append(0)
	while done.size() < MISSIONS_PER_DAY:
		done.append(false)
	st["progress"] = progress
	st["done"] = done
	counters["missions"] = st
	return st


## Quanto uma corrida avança uma missão. [param record]: {finished, dsq, pos, grid, laps, penalty,
## fastest, track, time_of_day}; [param kind] "online" ou "solo".
static func gain_of(mission: Dictionary, record: Dictionary, kind: String) -> int:
	var finished := bool(record.get("finished", false)) and not bool(record.get("dsq", false))
	var pos := int(record.get("pos", 99))
	match str(mission["id"]):
		"races":
			return 1 if finished else 0
		"podium":
			return 1 if finished and pos <= 3 else 0
		"win":
			return 1 if finished and pos == 1 else 0
		"laps":
			return int(record.get("laps", 0)) if not bool(record.get("dsq", false)) else 0
		"clean":
			return 1 if finished and float(record.get("penalty", 0.0)) <= 0.0 else 0
		"fastest":
			return 1 if bool(record.get("fastest", false)) and not bool(record.get("dsq", false)) else 0
		"track":
			return 1 if finished and str(record.get("track", "")) == str(mission.get("track", "")) else 0
		"night":
			return 1 if finished and int(record.get("time_of_day", 0)) == DaylightPresets.TimeOfDay.NIGHT else 0
		"gain":
			return 1 if finished and int(record.get("grid", 0)) - pos >= GAIN_POSITIONS else 0
		"online":
			return 1 if finished and kind == "online" else 0
	return 0


## Avança as missões com uma corrida. Devolve {completed: [{text, credits}], week: bool} — quem
## chama paga os créditos e, com week, o prêmio da semana.
static func on_result(counters: Dictionary, record: Dictionary, kind: String, unix := 0) -> Dictionary:
	var st := state(counters, unix)
	var list := daily(int(st["day"]))
	var completed := []
	for k in list.size():
		if bool(st["done"][k]):
			continue
		var m: Dictionary = list[k]
		var p := mini(int(st["progress"][k]) + gain_of(m, record, kind), int(m["goal"]))
		st["progress"][k] = p
		if p >= int(m["goal"]):
			st["done"][k] = true
			st["week_done"] = int(st["week_done"]) + 1
			completed.append({"text": m["text"], "credits": m["credits"]})
	var week := int(st["week_done"]) >= WEEK_GOAL and not bool(st["week_paid"])
	if week:
		st["week_paid"] = true
	return {"completed": completed, "week": week}


## O que o jogador vê (aba Missões).
static func payload(counters: Dictionary, unix := 0) -> Dictionary:
	var t := unix if unix > 0 else now()
	var st := state(counters, t)
	var list := daily(int(st["day"]))
	var missions := []
	for k in list.size():
		var m: Dictionary = list[k]
		missions.append({"text": m["text"], "goal": m["goal"], "progress": int(st["progress"][k]), "done": bool(st["done"][k]),
			"credits": m["credits"]})
	return {"missions": missions, "week_done": int(st["week_done"]), "week_goal": WEEK_GOAL, "week_paid": bool(st["week_paid"]),
		"week_credits": WEEK_CREDITS, "reset_in": next_reset(t) - t}
