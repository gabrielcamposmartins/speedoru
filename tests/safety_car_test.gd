extends SceneTree
## Modelo do safety car: todo slot de material do .glb tem material nas duas pinturas, as quatro
## rodas existem no lugar certo (com a origem no cubo, para girar) e a barra de luzes tem as lentes
## que piscam.
##   godot --headless --path . -s res://tests/safety_car_test.gd

var failures := 0


func _check(ok: bool, msg: String) -> void:
	print("  %s %s" % ["OK   " if ok else "FALHA", msg])
	if not ok:
		failures += 1


func _initialize() -> void:
	var model := SafetyCar.MODEL.instantiate() as Node3D
	var slots := {}
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			slots[m.resource_name if m else ""] = true
	var sc := SafetyCar.new()
	for k in SafetyCar.LIVERIES.size():
		var mats := sc._materials(SafetyCar.LIVERIES[k])
		var missing := slots.keys().filter(func(s: String) -> bool: return not mats.has(s))
		_check(missing.is_empty(), "pintura %d: todos os %d slots do modelo têm material %s" % [k, slots.size(),
			"" if missing.is_empty() else "(faltam %s)" % [missing]])
	for slot in ["SC_BarAmberL", "SC_BarAmberR", "SC_BarGreen", "SC_Plate", "SC_Paint", "SC_Lettering"]:
		_check(slots.has(slot), "o modelo tem o slot %s" % slot)
	# Rodas: FL na frente à esquerda (+Z, +X), RR atrás à direita; malha centrada no cubo
	var signs := {"Wheel_FL": Vector2(1, 1), "Wheel_FR": Vector2(-1, 1), "Wheel_RL": Vector2(1, -1), "Wheel_RR": Vector2(-1, -1)}
	for w: String in signs:
		var n := model.find_child(w, true, false) as MeshInstance3D
		_check(n != null, "roda %s existe" % w)
		if n == null:
			continue
		var p := n.position
		var sg: Vector2 = signs[w]
		_check(signf(p.x) == sg.x and signf(p.z) == sg.y and absf(p.y - SafetyCar.WHEEL_RADIUS) < 0.01,
			"%s no lugar (%.2f, %.2f, %.2f)" % [w, p.x, p.y, p.z])
		var c := n.mesh.get_aabb().get_center()
		_check(absf(c.y) < 0.01 and absf(c.z) < 0.01, "%s gira em volta do cubo (centro da malha %s)" % [w, c])
	# Entre-eixos do modelo = o usado no esterço
	var fl := model.find_child("Wheel_FL", true, false) as Node3D
	var rl := model.find_child("Wheel_RL", true, false) as Node3D
	if fl and rl:
		_check(absf((fl.position.z - rl.position.z) - SafetyCar.WHEELBASE) < 0.01, "entre-eixos %.2f m" % (fl.position.z - rl.position.z))
	sc.free()
	model.free()
	print("safety_car_test: %d falhas" % failures)
	quit(1 if failures else 0)
