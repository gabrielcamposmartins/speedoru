extends SceneTree
## Seta (pisca dos retrovisores) depois do reparo (sem janela):
##   godot --headless --path . -s res://tests/signal_repair_test.gd -- --offline
## O reparo (pit stop, queda da pista na Sky Aerobase) remonta as peças: os LEDs presos ao vidro
## antigo somem e a seta precisa voltar a acender nos retrovisores novos.

var car: F1Car
var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	scene.set("start_light_sequence", false)
	root.add_child(scene)
	car = scene.get_node("F1Car")
	car.player_controlled = false
	_run.call_deferred()


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


## Pisca e devolve quantos LEDs válidos acenderam em algum momento (dentro dos retrovisores atuais).
func _blink() -> int:
	car.pass_signal()
	var lit := {}
	for i in 90:
		await physics_frame
		for k in car._signal_leds.size():
			var led: Variant = car._signal_leds[k]
			if is_instance_valid(led) and (led as Node3D).is_visible_in_tree():
				lit[k] = true
	return lit.size()


func _run() -> void:
	await _physics(30)
	var mirrors := car.assembly.get_part_node("mirrors")
	_check(mirrors != null, "carro com retrovisores")
	_check(await _blink() == 2, "seta acende os dois LEDs")
	car.repair()
	await _physics(10)
	_check(car.assembly.get_part_node("mirrors") != mirrors, "reparo remonta os retrovisores")
	_check(await _blink() == 2, "seta acende os dois LEDs depois do reparo")
	var leds_ok := true
	for k in car._signal_leds.size():
		var led: Variant = car._signal_leds[k]
		leds_ok = leds_ok and is_instance_valid(led) and car.assembly.get_part_node("mirrors").is_ancestor_of(led)
	_check(leds_ok, "LEDs presos aos retrovisores novos")
	print("signal_repair_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)
