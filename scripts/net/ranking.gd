class_name Ranking
extends RefCounted
## Ranking (regras do documento do Pokeru, adaptadas para corridas), montado pelo servidor a partir
## de todas as contas salvas:
##
## * Abas: Vitórias (1º lugar em qualquer corrida), Ganhos (créditos ganhos desde sempre), Volta
##   mais rápida (recorde em Monza, menor é melhor) e Geral.
## * Geral: cada aba vale até 1.000 pontos; a conta recebe a fração do líder daquela aba
##   (round(valor / líder × 1000); na volta, round(líder / valor × 1000)).
## * Entra quem tem valor acima de zero; ordem pelo valor, empates pelo nome e depois pelo id;
##   empatados dividem a posição (1, 2, 2, 4); até 50 linhas, e quem fica de fora vê a própria
##   posição numa linha "você". Sem temporadas.

## [id, nome, unidade, menor é melhor]
const TABS := [
	["geral", "Geral", "pontos", false],
	["wins", "Vitórias", "vitórias", false],
	["earned", "Ganhos", "créditos", false],
	["best_lap", "Volta mais rápida", "", true],
]


static func value_of(tab: String, row: Dictionary) -> float:
	match tab:
		"wins":
			return float(row["counters"].get("wins", 0))
		"earned":
			return float(row["counters"].get("earned", 0))
		"best_lap":
			return float(row.get("best_lap", 0.0))
	return 0.0


## Monta todas as abas. rows = [{id, name, counters, best_lap}]
## Devolve {tab: [{pos, id, name, value, detail}]} ordenado e sem corte.
static func build(rows: Array) -> Dictionary:
	var out := {}
	var leaders := {}
	for t in TABS:
		if t[0] == "geral":
			continue
		var lower: bool = t[3]
		var best := 0.0
		for r in rows:
			var v := value_of(t[0], r)
			if v > 0.0 and (best == 0.0 or (v < best if lower else v > best)):
				best = v
		leaders[t[0]] = best
	for t in TABS:
		var list := []
		for r in rows:
			var v := 0.0
			var detail := {}
			if t[0] == "geral":
				for t2 in TABS:
					if t2[0] == "geral":
						continue
					var x := value_of(t2[0], r)
					var lead: float = leaders[t2[0]]
					var pts := 0
					if x > 0.0 and lead > 0.0:
						pts = roundi((lead / x if t2[3] else x / lead) * NetProtocol.RANKING_TAB_POINTS)
					detail[t2[0]] = pts
					v += pts
			else:
				v = value_of(t[0], r)
				if t[0] == "wins":
					detail["races"] = int(r["counters"].get("races", 0))
			if v > 0.0:
				list.append({"id": r["id"], "name": r["name"], "value": v, "detail": detail})
		var lower: bool = t[3]
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["value"] != b["value"]:
				return a["value"] < b["value"] if lower else a["value"] > b["value"]
			if a["name"] != b["name"]:
				return a["name"] < b["name"]
			return a["id"] < b["id"])
		# Empatados dividem a posição (1, 2, 2, 4)
		for k in list.size():
			list[k]["pos"] = k + 1 if k == 0 or list[k]["value"] != list[k - 1]["value"] else list[k - 1]["pos"]
		out[t[0]] = list
	return out


## Visão de uma conta: até 50 linhas por aba + a própria linha ("you") se ficou de fora.
static func view_for(full: Dictionary, account_id: String) -> Dictionary:
	var out := {}
	for tab in full:
		var list: Array = full[tab]
		var top := list.slice(0, NetProtocol.RANKING_ROWS)
		var you: Variant = null
		for k in list.size():
			if list[k]["id"] == account_id:
				if k >= NetProtocol.RANKING_ROWS:
					you = list[k]
				break
		out[tab] = {"rows": top, "you": you}
	return out
