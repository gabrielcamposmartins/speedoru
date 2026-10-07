extends SceneTree
## Configurações e músicas (sem janela):
##   godot --headless --path . -s res://tests/settings_test.gd
## Salva/recarrega (com backup do arquivo do jogador), remapeamento, conflitos, aplicação de
## gráficos e áudio, predefinições, e as 4 músicas (loop, playlist e faixa fixa).

var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var settings := root.get_node_or_null("Settings") as GameSettings
	var music := root.get_node_or_null("Music")
	_check(settings != null and music != null, "autoloads Settings e Music")
	if settings == null:
		quit(1)
		return
	# Backup das configurações reais do jogador
	var backup := ""
	if FileAccess.file_exists(GameSettings.PATH):
		backup = FileAccess.get_file_as_string(GameSettings.PATH)

	for extra in GameSettings.EXTRA_ACTIONS:
		_check(InputMap.has_action(extra[0]), "ação \"%s\" registrada" % extra[0])
	for a in GameSettings.ACTIONS:
		if not InputMap.has_action(a[0]):
			_check(false, "ação do menu existe: " + a[0])

	# Remapeamento + conflito + salvar/recarregar
	var k := InputEventKey.new()
	k.physical_keycode = KEY_J
	settings.set_binding("accelerate", false, k)
	_check(GameSettings.event_label(settings.get_binding("accelerate", false)) == "J", "remapear acelerar para J")
	settings.set_binding("drs", false, k.duplicate())
	_check(settings.conflicts("drs", settings.get_binding("drs", false)).has("Acelerar"), "conflito J em DRS e Acelerar")
	var pad := InputEventJoypadMotion.new()
	pad.axis = JOY_AXIS_TRIGGER_RIGHT
	pad.axis_value = 1.0
	settings.set_binding("brake", true, pad)
	settings.set_value("display", "fov", 80.0)
	settings.set_value("audio", "music", 0.5)
	settings.save_settings()
	# Volta tudo ao padrão só na memória e recarrega do arquivo
	for a in GameSettings.ACTIONS:
		InputMap.action_erase_events(a[0])
		for ev in settings._default_events[a[0]]:
			InputMap.action_add_event(a[0], ev)
	settings.values = GameSettings.DEFAULTS.duplicate(true)
	settings.load_settings()
	_check(GameSettings.event_label(settings.get_binding("accelerate", false)) == "J", "tecla salva e recarregada")
	_check(GameSettings.event_label(settings.get_binding("brake", true)) == "RT", "eixo do controle salvo e recarregado (RT)")
	_check(is_equal_approx(settings.get_value("display", "fov"), 80.0), "FOV salvo e recarregado")
	_check(is_equal_approx(settings.get_value("audio", "music"), 0.5), "volume da música salvo")
	# Som ambiente (torcida) no bus Crowd
	var crowd := AudioServer.get_bus_index("Crowd")
	var crowd_base := AudioServer.get_bus_volume_db(crowd)
	settings.set_value("audio", "ambient", 0.5)
	_check(absf(AudioServer.get_bus_volume_db(crowd) - (crowd_base + linear_to_db(0.5))) < 0.05,
		"som ambiente a 50%% baixa o bus da plateia (%.1f dB)" % AudioServer.get_bus_volume_db(crowd))
	settings.set_value("audio", "ambient", 0.0)
	_check(AudioServer.is_bus_mute(crowd), "som ambiente em 0: plateia muda")
	settings.set_value("audio", "ambient", 1.0)
	_check(not AudioServer.is_bus_mute(crowd), "som ambiente de volta")

	# Áudio aplicado no bus
	settings.apply_all()
	var bus := AudioServer.get_bus_index("Music")
	var base: float = settings._bus_base["Music"]
	_check(absf(AudioServer.get_bus_volume_db(bus) - (base + linear_to_db(0.5))) < 0.1, "volume da música aplicado no bus")

	# Gráficos: predefinição e personalizado
	settings.apply_preset(0)
	var vp := root.get_viewport()
	_check(vp.msaa_3d == Viewport.MSAA_DISABLED and is_equal_approx(vp.scaling_3d_scale, 0.75), "predefinição Baixo aplicada")
	settings.set_value("graphics", "msaa", 3)
	_check(vp.msaa_3d == Viewport.MSAA_8X and settings.get_value("graphics", "preset") == -1, "mudar MSAA vira Personalizado")
	settings.apply_preset(2)
	_check(settings.get_value("graphics", "preset") == 2 and vp.msaa_3d == Viewport.MSAA_4X, "predefinição Alto")

	# Músicas
	for t in music.TRACKS:
		var stream := load(t[0]) as AudioStreamWAV
		_check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.get_length() > 40.0,
			"música \"%s\" em loop (%.0f s)" % [t[1], stream.get_length() if stream else 0.0])
	settings.set_value("audio", "track", 3)
	_check(music.current == 2 and music.selection == 3, "faixa fixa: Slipstream")
	settings.set_value("audio", "music_on", false)
	_check(not music.is_enabled(), "música desligada")
	settings.set_value("audio", "music_on", true)
	settings.set_value("audio", "track", 0)
	_check(music.selection == 0, "volta para a playlist")

	# Menu abre e fecha (todas as abas montam sem erro)
	settings.open_menu()
	await process_frame
	var menu: SettingsMenu = settings._menu
	_check(menu != null and paused, "menu abre e pausa o jogo")
	for k2 in SettingsMenu.TABS.size():
		menu._show_tab(k2)
		await process_frame
		_check(menu._content.get_child_count() > 0, "aba %s montada" % SettingsMenu.TABS[k2])
	menu.close()
	await process_frame
	_check(not settings.is_menu_open() and not paused, "menu fecha e despausa")

	# Migração: arquivo antigo (sem versão) com a pausa só no Esc e a garagem no Start
	var old_cfg := ConfigFile.new()
	old_cfg.set_value("controls", "pause", [{"type": "key", "physical": KEY_ESCAPE, "keycode": 0, "location": 0}])
	old_cfg.set_value("controls", "toggle_garage", [{"type": "key", "physical": KEY_TAB, "keycode": 0, "location": 0},
		{"type": "joy_button", "button": JOY_BUTTON_START}])
	old_cfg.set_value("controls", "accelerate", [{"type": "key", "physical": KEY_J, "keycode": 0, "location": 0}])
	old_cfg.save(GameSettings.PATH)
	settings.load_settings()
	var pause_pad := settings.get_binding("pause", true)
	_check(pause_pad is InputEventJoypadButton and pause_pad.button_index == JOY_BUTTON_START, "migração: Start (botão 6) volta a pausar")
	_check(settings.get_binding("toggle_garage", true) == null or settings.get_binding("toggle_garage", true).button_index != JOY_BUTTON_START,
		"migração: Start não abre mais a garagem")
	_check(GameSettings.event_label(settings.get_binding("accelerate", false)) == "J", "migração mantém as teclas do teclado")
	settings.reset_section("controls")

	# Restaura o arquivo do jogador
	if backup != "":
		var f := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.PATH))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
