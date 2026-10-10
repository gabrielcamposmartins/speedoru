extends SceneTree
## Economia (sem janela): catálogo, chances, sorteio, giro, repetidas, loja, Estúdio, recompensas
## e persistência. Usa um perfil de teste (não toca no do jogador).
##   godot --headless --path . -s res://tests/economy_test.gd

var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var profile := root.get_node("Profile") as PlayerProfile
	PlayerProfile.save_path = "user://test_economy.cfg"
	profile.reset_profile()

	# --- Catálogo
	var total := 0.0
	for w in ShopCatalog.RARITY_WEIGHTS:
		total += w
	_check(is_equal_approx(total, 100.0), "fatias dos degraus somam 100%")
	for rid in ShopCatalog.ROULETTES:
		var sum := 0.0
		for id in ShopCatalog.roulette_items(rid):
			sum += ShopCatalog.chance_of(id)
		_check(absf(sum - 1.0) < 1e-6, "%s: chances das peças somam 100%%" % rid)
		for rarity in ShopCatalog.RARITY_WEIGHTS.size():
			_check(ShopCatalog.drops(rid, rarity).size() > 0, "%s: degrau %s tem peças" % [rid, ShopCatalog.RARITY_NAMES[rarity]])
	var parts_ok := true
	for id in ShopCatalog.ITEMS:
		var it: Dictionary = ShopCatalog.ITEMS[id]
		if it["type"] == "part" and not CarPartCatalog.has_variant(it["slot"], it["variant"]):
			parts_ok = false
			print("    peça inexistente: ", id)
	_check(parts_ok, "toda peça de desempenho existe no catálogo do carro")
	var all_variants := true
	for slot in CarPartCatalog.all_slots():
		for v in CarPartCatalog.variants(slot):
			if v == CarPartCatalog.default_variant(slot):
				continue
			var found := false
			for id in ShopCatalog.ITEMS:
				if ShopCatalog.ITEMS[id]["type"] == "part" and ShopCatalog.ITEMS[id]["slot"] == slot and ShopCatalog.ITEMS[id]["variant"] == v:
					found = true
			if not found:
				all_variants = false
				print("    variante sem roleta: ", slot, "/", v)
	_check(all_variants, "toda variante não padrão cai em alguma roleta")
	var only_parts_decals := true
	for id in ShopCatalog.ITEMS:
		if not ShopCatalog.ITEMS[id]["type"] in ["part", "decal", "boost", "neon"]:
			only_parts_decals = false
		if ShopCatalog.ITEMS[id]["type"] in ["boost", "neon"] and not Color.html_is_valid(str(ShopCatalog.ITEMS[id].get("color", ""))):
			only_parts_decals = false
		if ShopCatalog.ITEMS[id]["type"] == "decal" and not CarDecals.is_preset(ShopCatalog.decal_of(id)):
			only_parts_decals = false
			print("    decalque inexistente: ", id)
	_check(only_parts_decals, "roletas só com peças, decalques, boost e neon (que existem)")
	var legendaries := ShopCatalog.drops("neon", ShopCatalog.Rarity.LEGENDARY).size()
	_check(is_equal_approx(1.0 / ShopCatalog.chance_of("decal_sakura"), 40.0 * legendaries),
		"um lendário da roleta Neon: %d giros em média" % (40 * legendaries))
	# Toda peça do catálogo tem o modelo exportado (peças e rodas)
	var models_ok := true
	for slot in CarPartCatalog.all_slots():
		for v in CarPartCatalog.variants(slot):
			var path := CarPartCatalog.wheel_part_path(slot, v, "front") if CarPartCatalog.is_wheel_slot(slot) 				else CarPartCatalog.part_path(slot, v)
			if not ResourceLoader.exists(path):
				models_ok = false
				print("    sem modelo: ", path)
	_check(models_ok, "toda variante do catálogo tem modelo")
	_check(ShopCatalog.refund_of("decal_sakura") == roundi(ShopCatalog.table_price("decal_sakura") * 0.3), "repetida devolve 30% do preço de tabela")

	# --- Sorteio: distribuição dos degraus com números uniformes
	var counts := [0, 0, 0, 0, 0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := 200000
	for k in n:
		var id := ShopCatalog.draw("neon", rng.randf())
		counts[ShopCatalog.item(id)["rarity"]] += 1
	var dist_ok := true
	for r in 5:
		var got: float = 100.0 * counts[r] / n
		if absf(got - ShopCatalog.RARITY_WEIGHTS[r]) > 0.35:
			dist_ok = false
		print("    %s: %.2f%% (esperado %.1f%%)" % [ShopCatalog.RARITY_NAMES[r], got, ShopCatalog.RARITY_WEIGHTS[r]])
	_check(dist_ok, "sorteio respeita as fatias (200 mil giros)")
	_check(ShopCatalog.draw("neon", 0.0) != "" and ShopCatalog.draw("neon", 0.9999999) != "", "extremos do sorteio")

	# --- Giro
	_check(profile.credits == ShopCatalog.START_CREDITS, "conta nova começa com %d" % ShopCatalog.START_CREDITS)
	var res := profile.spin("neon")
	_check(res["ok"] and profile.credits == ShopCatalog.START_CREDITS - ShopCatalog.TICKET_PRICE + res["refund"], "giro cobra o ticket")
	_check(profile.owns(res["item"]) and not res["dup"], "primeira peça é nova e entra na coleção")
	# Repetida: já possui a peça sorteada
	var before := profile.credits
	profile.owned["decal_asas"] = true
	var dup_seen := false
	for k in 400:
		if profile.credits < ShopCatalog.TICKET_PRICE:
			profile.credits += 100000
		var r2 := profile.spin("neon")
		if r2["dup"]:
			dup_seen = true
			_check(r2["refund"] == ShopCatalog.refund_of(r2["item"]), "repetida devolve %d" % r2["refund"])
			break
	_check(dup_seen, "repetidas acontecem e devolvem créditos")
	profile.credits = 100
	var fail := profile.spin("inferno")
	_check(not fail["ok"] and profile.credits == 100, "sem créditos: recusa e não cobra")

	# --- Estúdio
	profile.reset_profile()
	profile.equip_color("primary", Color("123456"))
	_check(profile.equipped["primary"] == "123456", "cor livre: qualquer cor no carro")
	profile.equip_color("helmet", Color("abcdef"))
	_check(profile.equipped["helmet"] == "abcdef", "cor livre: qualquer cor no capacete")
	_check(profile.equipped["livery"] == "", "cores próprias = combinação própria")
	profile.equip_livery("livery_aurora")
	_check(profile.equipped["primary"] == "00e5c0" and profile.equipped["livery"] == "livery_aurora", "pintura pronta grátis aplica as 3 cores")
	profile.set_decal("sidepods", "sakura")
	_check(not profile.equipped["decals"].has("sidepods"), "decalque não possuído é recusado")
	profile.set_decal("sidepods", "estrela")
	_check(profile.equipped["decals"].get("sidepods", {}).get("id", "") == "estrela", "decalque grátis é aceito")
	profile.owned["decal_sakura"] = true
	profile.set_decal("nose", "sakura")
	_check(profile.equipped["decals"].get("nose", {}).get("id", "") == "sakura", "decalque ganho é aceito")
	profile.owned.erase("decal_sakura")
	profile.clamp_equipped()
	_check(not profile.equipped["decals"].has("nose"), "trava: decalque perdido sai do carro")
	profile.equip_part("rear_wing", "lowdf")
	_check(not profile.equipped["parts"].has("rear_wing"), "peça não possuída é recusada")
	profile.owned["part_rear_wing_lowdf"] = true
	profile.equip_part("rear_wing", "lowdf")
	_check(profile.equipped["parts"].get("rear_wing", "") == "lowdf", "peça possuída é montada")
	# Boost e neon: só as cores ganhas
	_check(not profile.has_neon() and profile.equipped["neon"] == "" and not profile.equipped["neon_on"], "conta nova sem neon")
	profile.set_neon(true)
	_check(not profile.equipped["neon_on"], "sem cor de neon ganha o neon não liga")
	profile.equip_color("boost", Color("123456"))
	_check(profile.equipped["boost"] == "38f2ff", "boost: cor não ganha é recusada (fica o ciano grátis)")
	profile.owned["boost_ruby"] = true
	profile.equip_color("boost", Color("ff1744"))
	_check(profile.equipped["boost"] == "ff1744", "boost: cor ganha é aceita")
	profile.owned["neon_cyan"] = true
	profile.equip_color("neon", Color("abcdef"))
	_check(profile.equipped["neon"] != "abcdef", "neon: cor não ganha é recusada")
	profile.equip_color("neon", Color("00e5ff"))
	profile.set_neon(true)
	_check(profile.equipped["neon_on"] and profile.equipped["neon"] == "00e5ff", "neon ganho liga na cor dele")
	profile.owned.erase("boost_ruby")
	profile.clamp_equipped()
	_check(profile.equipped["boost"] == "38f2ff", "trava: boost perdido volta para o grátis")
	# Esquema de pintura: grátis, qualquer um da lista; fora da lista volta para o clássico
	profile.set_finish("paint_scheme", 4)
	_check(profile.equipped["paint_scheme"] == 4, "esquema de pintura escolhido")
	profile.equipped["paint_scheme"] = 99
	profile.clamp_equipped()
	_check(profile.equipped["paint_scheme"] == CarConfig.PAINT_SCHEMES.size() - 1, "trava: esquema fora da lista")
	profile.set_finish("paint_scheme", 4)
	var w_side := CarLivery.scheme_weights(1, Vector3(0.6, 0.2, 0.0))
	var w_top := CarLivery.scheme_weights(1, Vector3(0.6, 0.6, 0.0))
	_check(w_side.x == 1.0 and w_top.x == 0.0, "dois tons: cor 2 embaixo, cor 1 em cima")
	profile.equipped["primary"] = "não é cor"
	profile.clamp_equipped()
	_check(profile.equipped["primary"] == "d81e2c", "trava: cor inválida volta para a padrão")
	var cfg := CarConfig.new()
	profile.apply_to_config(cfg)
	_check(cfg.get_part("rear_wing") == "lowdf" and cfg.neon_enabled and cfg.neon_color.to_html(false) == "00e5ff",
		"aplica peças, neon e cores na configuração do carro")
	_check(cfg.paint_scheme == 4, "aplica o esquema de pintura na configuração do carro")
	var saved := PlayerProfile.sanitize_equipped({"paint_scheme": 7})
	_check(saved["paint_scheme"] == 7, "esquema passa pela validação do servidor")

	# --- Engenharia (comportamento do carro)
	var car := (load("res://scenes/car/f1_car.tscn") as PackedScene).instantiate() as F1Car
	car.player_controlled = false
	root.add_child(car)
	await process_frame
	var base_df := car.downforce_area
	var base_gear := car.gear_ratios[0]
	var color_before := car.config.primary_color
	profile.set_setup_value("downforce_area", 4.8)
	profile.set_setup_value("final_drive", 1.05)
	profile.set_setup_value("front_spring", 999.0)
	profile.apply_setup(car)
	_check(is_equal_approx(car.downforce_area, 4.8), "engenharia: carga aerodinâmica aplicada no carro")
	_check(is_equal_approx(car.gear_ratios[0], base_gear * 1.05), "engenharia: relação final multiplica as marchas")
	var springs := []
	for w in car.get_wheels():
		if w.use_as_steering:
			springs.append(w.suspension_stiffness)
	print("    rodas: %d, molas dianteiras %s" % [car.get_wheels().size(), springs])
	_check(springs.size() == 2 and is_equal_approx(springs[0], 220.0), "engenharia: mola limitada ao máximo (220)")
	_check(car.config.primary_color == color_before, "engenharia não mexe na aparência")
	profile.reset_setup()
	profile.apply_setup(car)
	_check(is_equal_approx(car.downforce_area, base_df) and is_equal_approx(car.gear_ratios[0], base_gear), "engenharia: restaurar de fábrica")
	car.queue_free()

	# --- Recompensas
	profile.credits = 0
	_check(profile.award_race(10, 0, true, false) == 2000 and profile.award_race(10, 1, true, false) == 3000 \
		and profile.award_race(10, 2, true, false) == 4000, "10 voltas pagam 2.000 / 3.000 / 4.000")
	_check(profile.award_race(10, 2, true, true) == 0, "desclassificado não recebe")
	_check(profile.award_race(6, 2, false, false) == 1200, "abandono recebe metade do que andou")

	# --- Persistência
	var credits := profile.credits
	profile.save_profile()
	profile.credits = 0
	profile.owned = {}
	profile.load_profile()
	_check(profile.credits == credits and profile.owns("part_rear_wing_lowdf"),
		"salva e recarrega créditos e coleção")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_economy.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
