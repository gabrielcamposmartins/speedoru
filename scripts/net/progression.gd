class_name Progression
extends RefCounted
## Nível, conquistas, títulos e o "como você pilota" (regras do documento do Pokeru, adaptadas para
## corridas). Tudo é calculado dos contadores da conta, que só o servidor escreve.
##
## Contadores (account.counters): laps, races, wins, podiums, fastest_laps, clean_races,
## online_races, spins, earned. A coleção (items) vem do perfil.

## xp por ação. O nível não fica guardado: sai do xp, que sai dos contadores.
const XP := {"laps": 3, "races": 10, "podiums": 15, "wins": 25}

## Dificuldade dos bots liberada por nível (Fácil, Médio, Difícil, Mista). Conferido no servidor.
const TIER_LEVEL := [1, 3, 6, 3]

## [id, nome, contador, meta, título, grau 1–5]
const ACHIEVEMENTS := [
	["laps_1", "Primeira volta", "laps", 1, "Estreante", 1],
	["laps_100", "Rodagem", "laps", 100, "Piloto de testes", 2],
	["laps_1000", "Quilometragem", "laps", 1000, "Maratonista", 4],
	["races_1", "Bandeira quadriculada", "races", 1, "Finalista", 1],
	["races_25", "Regular", "races", 25, "Veterano", 3],
	["wins_1", "Primeira vitória", "wins", 1, "Vencedor", 2],
	["wins_10", "Dominante", "wins", 10, "Campeão", 4],
	["wins_50", "Lenda", "wins", 50, "Lenda de Monza", 5],
	["podiums_1", "Pódio", "podiums", 1, "Pódio", 1],
	["podiums_25", "Habitué do pódio", "podiums", 25, "Colecionador de troféus", 3],
	["fastest_1", "Relógio roxo", "fastest_laps", 1, "Relógio roxo", 2],
	["fastest_25", "Cronômetro", "fastest_laps", 25, "Rei do cronômetro", 4],
	["clean_1", "Corrida limpa", "clean_races", 1, "Cavalheiro", 1],
	["clean_10", "Fair play", "clean_races", 10, "Exemplo", 3],
	["online_1", "Online", "online_races", 1, "Rival online", 1],
	["online_25", "Rival", "online_races", 25, "Nêmesis", 3],
	["spins_1", "Primeiro giro", "spins", 1, "Apostador", 1],
	["spins_50", "Giro solto", "spins", 50, "Rei da roleta", 3],
	["items_10", "Colecionador", "items", 8, "Colecionador", 2],
	["items_50", "Garagem cheia", "items", 20, "Curador", 4],
	["earned_100k", "Magnata", "earned", 100000, "Magnata", 4],
]
const GRADE_COLORS := [Color("9aa4b2"), Color("3dfc9a"), Color("2f9bff"), Color("b14dff"), Color("ffb000")]
## Cor do nível por dezena.
const LEVEL_COLORS := [Color("9aa4b2"), Color("3dfc9a"), Color("2f9bff"), Color("b14dff"), Color("ffb000"), Color("ff3b5c")]

const TRAITS := ["Ritmo", "Ataque", "Limpeza", "Consistência", "Resistência", "Pódio"]


static func xp_of(counters: Dictionary) -> int:
	var xp := 0
	for key in XP:
		xp += int(counters.get(key, 0)) * int(XP[key])
	return xp


## nível = 1 + ⌊√(xp / 40)⌋
static func level_of_xp(xp: int) -> int:
	return 1 + int(floor(sqrt(maxf(xp, 0) / 40.0)))


## xp total para chegar ao nível n = 40·(n−1)²
static func xp_for_level(n: int) -> int:
	return 40 * (n - 1) * (n - 1)


static func level_of(counters: Dictionary) -> int:
	return level_of_xp(xp_of(counters))


## [xp no nível, xp do nível] (barra do perfil)
static func level_progress(counters: Dictionary) -> Vector2i:
	var xp := xp_of(counters)
	var lv := level_of_xp(xp)
	var base := xp_for_level(lv)
	return Vector2i(xp - base, xp_for_level(lv + 1) - base)


static func level_color(level: int) -> Color:
	return LEVEL_COLORS[clampi(level / 10, 0, LEVEL_COLORS.size() - 1)]


static func tier_unlocked(difficulty: int, level: int) -> bool:
	return level >= TIER_LEVEL[clampi(difficulty, 0, TIER_LEVEL.size() - 1)]


## Conquistas com progresso: [{id, name, value, goal, done, title, grade}]
static func achievements(counters: Dictionary) -> Array:
	var out := []
	for a in ACHIEVEMENTS:
		var v := int(counters.get(a[2], 0))
		out.append({"id": a[0], "name": a[1], "value": v, "goal": a[3], "done": v >= int(a[3]), "title": a[4], "grade": a[5]})
	return out


static func unlocked_titles(counters: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for a in ACHIEVEMENTS:
		if int(counters.get(a[2], 0)) >= int(a[3]):
			out.append(a[4])
	return out


static func title_grade(title: String) -> int:
	for a in ACHIEVEMENTS:
		if a[4] == title:
			return a[5]
	return 0


## Traços de 0 a 1 nas últimas corridas (registros do histórico). Sem histórico, todos 0,5.
## Registro: {pos, total, grid, finished, penalty, best_lap, consistency}
static func traits(records: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.5, 0.5, 0.5, 0.5, 0.5, 0.5])
	if records.is_empty():
		return out
	var pace := 0.0
	var pace_n := 0
	var attack := 0.0
	var clean := 0.0
	var consist := 0.0
	var finished := 0.0
	var podium := 0.0
	for r: Dictionary in records:
		var best := float(r.get("best_lap", 0.0))
		if best > 0.0:
			pace += clampf((110.0 - best) / (110.0 - 85.0), 0.0, 1.0)
			pace_n += 1
		var total := maxi(int(r.get("total", 1)), 1)
		var gained := int(r.get("grid", 0)) - int(r.get("pos", 0))
		attack += clampf(0.5 + gained / float(maxi(total - 1, 1)), 0.0, 1.0)
		clean += clampf(1.0 - float(r.get("penalty", 0.0)) / 30.0, 0.0, 1.0)
		consist += clampf(float(r.get("consistency", 0.5)), 0.0, 1.0)
		finished += 1.0 if r.get("finished", false) else 0.0
		podium += 1.0 if r.get("finished", false) and int(r.get("pos", 99)) <= 3 else 0.0
	var n := float(records.size())
	out[0] = pace / pace_n if pace_n > 0 else 0.5
	out[1] = attack / n
	out[2] = clean / n
	out[3] = consist / n
	out[4] = finished / n
	out[5] = podium / n
	return out


## Consistência das voltas (1 = todas iguais): 1 − desvio padrão relativo × 10.
static func consistency_of(lap_times: Array) -> float:
	var laps: Array[float] = []
	for t in lap_times:
		if float(t) > 0.0:
			laps.append(float(t))
	if laps.size() < 2:
		return 0.5
	var mean := 0.0
	for t in laps:
		mean += t
	mean /= laps.size()
	var var_sum := 0.0
	for t in laps:
		var_sum += (t - mean) * (t - mean)
	return clampf(1.0 - sqrt(var_sum / laps.size()) / mean * 10.0, 0.0, 1.0)
