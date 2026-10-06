extends SceneTree
## Navegação dos menus pelo controle (sem janela): foco inicial, D-pad, A confirma, LB/RB trocam
## abas da garagem e das configurações, B volta. Usa um perfil de teste.
##   godot --headless --path . -s res://tests/ui_nav_test.gd

var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame
	await process_frame


func _focused() -> Control:
	return root.get_viewport().gui_get_focus_owner()


func _run() -> void:
	var profile := root.get_node("Profile") as PlayerProfile
	PlayerProfile.save_path = "user://test_nav.cfg"
	profile.reset_profile()
	var scene := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 10:
		await process_frame
	var ui: MenuUI = scene.ui
	# Sem nada focado, o primeiro toque no D-pad foca o primeiro botão
	await _pad(JOY_BUTTON_DPAD_DOWN)
	var f := _focused()
	_check(f is MenuUI.BigButton and f.title == "JOGAR SOLO", "D-pad foca o primeiro botão do menu")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	f = _focused()
	_check(f is MenuUI.BigButton and f.title == "GARAGEM", "D-pad ↓ desce até Garagem")
	await _pad(JOY_BUTTON_A)
	for i in 5:
		await process_frame
	_check(ui.screen == "garage" and ui.garage_tab == 0, "A abre a garagem (Estúdio)")
	_check(_focused() != null and _focused().is_visible_in_tree(), "a garagem já abre com algo em foco")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	_check(ui.garage_tab == 1, "RB vai para a Galeria")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	_check(ui.garage_tab == 2, "RB vai para a Loja")
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	_check(ui.garage_tab == 1, "LB volta para a Galeria")
	await _pad(JOY_BUTTON_B)
	_check(ui.screen == "home", "B volta para o início")
	# Configurações: LB/RB trocam abas, B fecha
	var settings := root.get_node("Settings") as GameSettings
	settings.open_menu()
	await process_frame
	var menu: SettingsMenu = settings._menu
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	_check(menu.tab == 1, "configurações: RB vai para a próxima aba")
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	_check(menu.tab == SettingsMenu.TABS.size() - 1, "configurações: LB dá a volta para a última aba")
	await _pad(JOY_BUTTON_B)
	await process_frame
	_check(not settings.is_menu_open(), "configurações: B fecha")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.save_path))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
