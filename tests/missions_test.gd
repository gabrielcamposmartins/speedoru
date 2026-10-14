extends SceneTree
## Missões diárias, prêmio da semana, conquistas pagas e roleta do vencedor (sem rede: só as regras).
##   godot --headless --path . -s res://tests/missions_test.gd
## Perfil de teste: user://test_missions_profile.cfg (apagado no fim).

var failures := 0


func _check(cond: bool, label: String) -> void:
	print(("  OK   " if cond else "  FALHA ") + label)
	if not cond:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var profile := root.get_node("Profile") as PlayerProfile
	PlayerProfile.save_path = "user://test_missions_profile.cfg"
	profile.reset_profile()

	# --- Dia e semana (Brasília): 13/10/2026 é uma terça
	var tue := 1791900000  # 2026-10-13 ~15:00 (UTC−3)
	var day := Missions.day_of(tue)
	_check(Missions.day_of(tue + 86400) == day + 1, "dia seguinte")
	var monday := day - 1
	_check(Missions.week_of(monday) == Missions.week_of(day) and Missions.week_of(monday - 1) == Missions.week_of(day) - 1,
		"semana começa na segunda")
	_check(Missions.next_reset(tue) > tue and Missions.next_reset(tue) - tue <= 86400, "próxima troca em menos de um dia")

	# --- Sorteio do dia: sempre o mesmo, 3 diferentes, e muda de um dia para outro
	var m1 := Missions.daily(day)
	var m2 := Missions.daily(day)
	_check(m1.size() == Missions.MISSIONS_PER_DAY and str(m1) == str(m2), "as 3 missões do dia são sempre as mesmas")
	var ids := {}
	for m: Dictionary in m1:
		ids[m["id"]] = true
	_check(ids.size() == 3, "três missões diferentes")
	var differs := false
	for k in range(1, 8):
		differs = differs or str(Missions.daily(day + k)) != str(m1)
	_check(differs, "outros dias têm outras missões")

	# --- Progresso: uma corrida que cumpre tudo completa as três
	var counters := {}
	var record := {"finished": true, "dsq": false, "pos": 1, "grid": 10, "laps": 20, "penalty": 0.0, "fastest": true,
		"time_of_day": 2}
	for m: Dictionary in m1:
		if m["id"] == "track":
			record["track"] = m["track"]
	var res := Missions.on_result(counters, record, "online", tue)
	var st: Dictionary = counters["missions"]
	_check((res["completed"] as Array).size() >= 2, "corrida perfeita completa as missões (%d de 3)" % (res["completed"] as Array).size())
	var res2 := Missions.on_result(counters, record, "online", tue)
	var all_done: bool = st["done"].all(func(x: bool) -> bool: return x)
	_check(all_done and (res2["completed"] as Array).size() == 3 - (res["completed"] as Array).size(),
		"com mais corridas as três fecham, e cada missão paga uma vez")
	_check((Missions.on_result(counters, record, "online", tue)["completed"] as Array).is_empty(), "missão completa não paga de novo")
	# DSQ não conta
	var dsq := Missions.gain_of({"id": "win"}, {"finished": true, "dsq": true, "pos": 1}, "online")
	_check(dsq == 0 and Missions.gain_of({"id": "online"}, {"finished": true, "pos": 5}, "solo") == 0,
		"desclassificado não conta; corrida solo não conta como online")

	# --- Troca de dia zera; a semana acumula até 21 e paga o prêmio uma vez
	var week_paid := 0
	var week_counters := {}
	var t := tue - (day - monday) * 86400  # segunda
	for d in 7:
		var list := Missions.daily(Missions.day_of(t))
		var rec := record.duplicate()
		for m: Dictionary in list:
			if m["id"] == "track":
				rec["track"] = m["track"]
		for k in 4:
			if Missions.on_result(week_counters, rec, "online", t)["week"]:
				week_paid += 1
		_check(int(week_counters["missions"]["week_done"]) == (d + 1) * 3, "dia %d: %d missões da semana" % [d + 1, (d + 1) * 3])
		t += 86400
	_check(week_paid == 1, "prêmio da semana pago uma vez ao completar as 21")
	Missions.on_result(week_counters, record, "online", t)
	_check(int(week_counters["missions"]["week_done"]) <= 3 and not bool(week_counters["missions"]["week_paid"]),
		"semana nova começa do zero")
	var pl := Missions.payload(week_counters, t)
	_check((pl["missions"] as Array).size() == 3 and int(pl["week_goal"]) == 21, "o que o jogador vê: 3 missões e a meta da semana")

	# --- Conquistas: créditos pelo grau, Sirene na Interceptor, títulos especiais
	var ach := Progression.achievements({"positions_gained": 300, "nightmares": 1})
	var inter: Dictionary = ach.filter(func(a: Dictionary) -> bool: return a["id"] == "positions_300")[0]
	var night: Dictionary = ach.filter(func(a: Dictionary) -> bool: return a["id"] == "nightmare_1")[0]
	_check(inter["done"] and inter["item"] == "signal_police" and int(inter["credits"]) == 5000, "Interceptor: 5.000 créditos e a Sirene")
	_check(night["done"] and night["title"] == "Nightmare" and int(night["credits"]) == 12000, "Nightmare: título especial, 12.000 créditos")
	var titles := Progression.unlocked_titles({"nightmares": 1}, ["Tempestade"])
	_check("Nightmare" in titles and "Tempestade" in titles and Progression.title_grade("Tempestade") == 5, "títulos de conquista e da coleção")
	for tt in ["Midnight", "Winged Death", "Nightmare"]:
		_check(TitleLabel.is_special(tt) and TitleLabel.font_of(tt) != null, "título especial com fonte própria: %s" % tt)

	# --- Roleta do vencedor: fatias 5 / 50 / 30 / 15
	var counts := [0, 0, 0, 0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 100000:
		counts[ShopCatalog.winner_slice(rng.randf())] += 1
	var want := [5.0, 50.0, 30.0, 15.0]
	var dist_ok := true
	for k in 4:
		dist_ok = dist_ok and absf(counts[k] / 1000.0 - want[k]) < 0.6
	_check(dist_ok, "roleta do vencedor: 5%% exclusivo, 50%% 500, 30%% 1000, 15%% ticket (%s)" % str(counts))
	profile.credits = 0
	var r := GameServer.resolve_race_spin(profile, 0.01, 0.0)
	_check(r["kind"] == "exclusive" and r["item"] in ShopCatalog.EXCLUSIVE_POOL and profile.owns(r["item"]), "exclusivo entra na coleção")
	r = GameServer.resolve_race_spin(profile, 0.30, 0.0)
	_check(r["kind"] == "credits" and int(r["credits"]) == 500 and profile.credits == 500, "500 créditos")
	r = GameServer.resolve_race_spin(profile, 0.70, 0.0)
	_check(int(r["credits"]) == 1000 and profile.credits == 1500, "1.000 créditos")
	r = GameServer.resolve_race_spin(profile, 0.95, 0.0)
	_check(r["kind"] == "ticket" and profile.tickets == 1, "ticket da roleta da loja")
	for id in ShopCatalog.EXCLUSIVE_POOL:
		profile.owned[id] = true
	r = GameServer.resolve_race_spin(profile, 0.01, 0.0)
	_check(r["item"] == "" and int(r["credits"]) == ShopCatalog.WINNER_ALL_OWNED, "com todos os exclusivos: créditos no lugar")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_missions_profile.cfg"))
	print("missions_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)
