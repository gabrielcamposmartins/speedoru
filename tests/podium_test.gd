extends SceneTree
## Pódio (sem janela):
##   godot --headless --path . -s res://tests/podium_test.gd -- --offline
## Abre a tela de pódio com os três primeiros e confere que as cópias dos carros ficam com as quatro
## rodas no lugar (o VehicleBody3D as regravava na origem do mundo) e que fechar devolve os carros.

var scene: Node3D
var manager: RaceManager
var failures := 0


func _initialize() -> void:
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_podium_profile.cfg"
		profile.reset_profile()
	RaceSettings.track = "monza"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 1
	RaceSettings.opponents = 3
	RaceSettings.quali_laps = 0
	RaceSettings.skip_menu = true
	scene = (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	scene.set("start_light_sequence", false)
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	while not manager.track.is_built:
		await process_frame
	await _physics(20)
	var podium := PodiumScreen.new()
	podium.manager = manager
	for e in manager.entries.slice(0, 3):
		podium.entries.append(e)
	root.add_child(podium)
	await _physics(30)
	var cars := podium._root3d.find_children("*", "F1Car", true, false)
	_check(cars.size() == 3, "três carros no pódio (%d)" % cars.size())
	for c in cars:
		var car := c as F1Car
		var wheels := car.get_wheels()
		var ok := wheels.size() == 4
		var worst := 0.0
		for w in wheels:
			var local := car.global_transform.affine_inverse() * w.global_position
			worst = maxf(worst, local.length())
			ok = ok and local.length() < 3.0 and w.is_visible_in_tree()
		_check(ok, "%s: quatro rodas presas ao carro (mais longe %.2f m do centro)" % [car.name, worst])
	podium._close()
	await _physics(5)
	print("podium_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)
