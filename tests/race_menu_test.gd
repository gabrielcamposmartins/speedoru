extends SceneTree
## Menus da corrida e música (sem janela):
##   godot --headless --path . -s res://tests/race_menu_test.gd
## Na corrida o Tab não abre a garagem e N/B não mudam horário/ambiente (escolhidos antes);
## no treino o Tab abre a garagem e pausa. A música troca entre o tema do menu e a da pista.

var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _key(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await process_frame


func _load(path: String) -> Node:
	change_scene_to_file(path)
	for i in 20:
		await process_frame
	return current_scene


func _run() -> void:
	var profile := root.get_node("Profile") as PlayerProfile
	PlayerProfile.save_path = "user://test_rm.cfg"
	profile.reset_profile()
	var music := root.get_node("Music")
	await _load("res://scenes/menu/main_menu.tscn")
	_check(music.context == "menu" and music.current == music.MENU_TRACK, "menu principal toca o tema do menu")
	# --- Corrida: noite + outono
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.opponents = 3
	RaceSettings.time_of_day = 2
	RaceSettings.biome = 1
	RaceSettings.skip_menu = true
	var scene: Node = await _load("res://scenes/tracks/monza.tscn")
	var rm := scene.get_node("RaceManager") as RaceManager
	while rm.state != RaceManager.State.GRID and rm.state != RaceManager.State.RACING:
		await process_frame
	_check(music.context == "race" and music.current != music.MENU_TRACK, "na pista a música troca (faixa %d)" % music.current)
	var daylight := get_first_node_in_group("daylight") as Daylight
	_check(daylight.time_of_day == 2 and daylight.biome == 1, "horário e ambiente escolhidos antes da corrida")
	await _key("cycle_time")
	_check(daylight.time_of_day == 2, "na corrida N não muda o horário")
	await _key("toggle_garage")
	var garage := scene.get_node("HUD/Garage") as Control
	_check(not garage.visible and not paused, "na corrida o Tab não abre a garagem")
	# --- Treino: Tab abre a garagem e pausa
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	scene = await _load("res://scenes/tracks/monza.tscn")
	rm = scene.get_node("RaceManager") as RaceManager
	while rm.state != RaceManager.State.PRACTICE:
		await process_frame
	await _key("toggle_garage")
	garage = scene.get_node("HUD/Garage") as Control
	_check(garage.visible and paused, "no treino o Tab abre a garagem e pausa")
	await _key("toggle_garage")
	_check(not garage.visible and not paused, "Tab de novo fecha e despausa")
	await _load("res://scenes/menu/main_menu.tscn")
	_check(music.context == "menu" and music.current == music.MENU_TRACK, "voltando ao menu, volta o tema do menu")
	RaceSettings.time_of_day = 0
	RaceSettings.biome = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.save_path))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
