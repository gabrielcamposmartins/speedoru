extends SceneTree
## Peças do carro (sem janela):  godot --headless --path . -s res://tests/parts_test.gd
## Monta cada variante de cada peça num carro e confere: o modelo aparece, o dano encontra as malhas
## (peças que se soltam), a asa traseira tem o flap do DRS e os retrovisores têm os dois vidros. Toda
## variante que não é a padrão cai em alguma roleta.

var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var car := (load("res://scenes/car/f1_car.tscn") as PackedScene).instantiate() as F1Car
	car.player_controlled = false
	root.add_child(car)
	for k in 5:
		await physics_frame
	var damage := car.get_node("Damage") as CarDamage
	for slot in CarPartCatalog.all_slots():
		var variants := CarPartCatalog.variants(slot)
		if variants.size() < 2:
			continue
		for v in variants:
			var cfg: CarConfig = car.config.duplicate(true)
			cfg.set_part(slot, v)
			car.config = cfg
			for k in 3:
				await physics_frame
			var label := "%s/%s" % [slot, v]
			if CarPartCatalog.is_wheel_slot(slot):
				var meshes := 0
				for w in car.get_wheels():
					meshes += w.find_children("*", "MeshInstance3D", true, false).size()
				_check(meshes > 0, label + ": rodas montadas")
				continue
			var node := car.assembly.get_part_node(slot)
			var meshes := node.find_children("*", "MeshInstance3D", true, false).size() if node else 0
			_check(meshes > 0, label + ": modelo montado (%d malhas)" % meshes)
			match slot:
				"rear_wing":
					_check(car.assembly.find_in_part("rear_wing", "DRSFlap*") != null, label + ": flap do DRS")
					_check(damage.health.has("rear_wing"), label + ": dano encontra a asa")
				"mirrors":
					for suffix in ["L", "R"]:
						_check(node.find_child("MirrorGlass" + suffix + "*", true, false) != null, label + ": vidro " + suffix)
				"front_wing":
					_check(damage.health.has("front_wing_L") and damage.health.has("front_wing_R"), label + ": dano nos dois lados")
				"nose", "sidepods", "engine_cover":
					var piece: String = {"nose": "nose", "sidepods": "sidepod_L", "engine_cover": "engine_cover"}[slot]
					_check(damage.health.has(piece), label + ": dano encontra a peça")
			if v != CarPartCatalog.default_variant(slot):
				_check(ShopCatalog.ITEMS.has("part_%s_%s" % [slot, v]), label + ": está numa roleta")
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
