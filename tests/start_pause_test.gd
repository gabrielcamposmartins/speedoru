extends SceneTree
## Pausa na largada (sem janela):  godot --headless --path . -s res://tests/start_pause_test.gd
## Pausar com o semáforo acendendo congela a sequência (luzes e largada); ao despausar ela segue.

var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.opponents = 1
	RaceSettings.laps = 3
	RaceSettings.skip_menu = true
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_pause_profile.cfg"
		profile.reset_profile()
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_run.call_deferred(scene.get_node("RaceManager"))


func _lit(lights: Node) -> int:
	var n := 0
	for lamp in lights._lamps:
		if lamp.material_override == lights._on:
			n += 1
	return n


func _run(manager: RaceManager) -> void:
	while manager.state != RaceManager.State.GRID:
		await process_frame
	var lights := manager.track.start_lights
	# Espera a primeira coluna acender
	while _lit(lights) == 0:
		await process_frame
	await create_timer(0.3).timeout
	var before := _lit(lights)
	paused = true
	# Timer que corre mesmo pausado (só para o teste esperar)
	await create_timer(6.0, true).timeout
	var during := _lit(lights)
	_check(manager.state == RaceManager.State.GRID and during == before,
		"pausado 6 s: o semáforo não avança (%d → %d lâmpadas acesas) e a largada não acontece" % [before, during])
	paused = false
	var t := 0.0
	while manager.state != RaceManager.State.RACING and t < 12.0:
		await create_timer(0.1).timeout
		t += 0.1
	_check(manager.state == RaceManager.State.RACING, "despausado: a sequência continua e a corrida larga")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_pause_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
