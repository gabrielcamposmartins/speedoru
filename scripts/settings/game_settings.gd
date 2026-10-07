class_name GameSettings
extends Node
## Configurações do jogo (autoload "Settings"), salvas em user://settings.cfg e aplicadas ao abrir:
##
## * Controles: teclas/botões de cada ação do InputMap (uma de teclado/mouse e uma de controle).
## * Tela: modo da janela, resolução, VSync, limite de FPS, escala da interface, campo de visão.
## * Gráficos: predefinição, escala de renderização e upscaler, anti-aliasing, sombras, oclusão de
##   ambiente, brilho, neblina volumétrica e nível de detalhe.
## * Desempenho: monitor na tela (FPS / detalhado com CPU, GPU, RAM, VRAM, draw calls) e posição.
## * Áudio: volumes (geral, carro, música), música ligada, faixa/playlist, silenciar sem foco.
##
## O menu (SettingsMenu) só lê e escreve valores com get_value()/set_value(); quem usa um valor
## (câmera, música…) lê daqui ou ouve o sinal `changed`.

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"
## Versão dos controles salvos. Arquivos mais antigos mantêm as teclas do teclado, mas recebem os
## botões de controle atuais (ex.: o Start, botão 6, passou de Garagem para Pausa na versão 2).
const CONTROLS_VERSION := 2

## Ações remapeáveis, na ordem do menu: [ação, rótulo, grupo].
const ACTIONS := [
	["accelerate", "Acelerar", "Pilotagem"],
	["brake", "Frear", "Pilotagem"],
	["steer_left", "Esterçar à esquerda", "Pilotagem"],
	["steer_right", "Esterçar à direita", "Pilotagem"],
	["reverse", "Ré (câmbio automático)", "Pilotagem"],
	["boost", "Boost da bateria", "Pilotagem"],
	["drs", "DRS", "Pilotagem"],
	["shift_up", "Subir marcha (manual: R → N → 1…)", "Pilotagem"],
	["shift_down", "Descer marcha (manual: … 1 → N → R)", "Pilotagem"],
	["toggle_gearbox", "Câmbio auto/manual", "Carro"],
	["toggle_tc", "Controle de tração", "Carro"],
	["brake_bias_forward", "Balanço de freio para a frente", "Carro"],
	["brake_bias_rearward", "Balanço de freio para trás", "Carro"],
	["reset_car", "Recolocar o carro", "Carro"],
	["repair_car", "Reparar o carro", "Carro"],
	["pit_limiter", "Limitador de velocidade (boxes e bandeira amarela)", "Corrida"],
	["go_to_pit", "Ir aos boxes depois de uma batida", "Corrida"],
	["pit_soft", "Pneu do pit: macio", "Corrida"],
	["pit_medium", "Pneu do pit: médio", "Corrida"],
	["pit_hard", "Pneu do pit: duro", "Corrida"],
	["standings_next", "Classificação: próxima página", "Corrida"],
	["standings_prev", "Classificação: página anterior", "Corrida"],
	["camera_next", "Trocar câmera", "Câmera"],
	["look_back", "Olhar para trás", "Câmera"],
	["camera_orbit", "Câmera em órbita", "Câmera"],
	["pause", "Pausa", "Interface"],
	["open_settings", "Configurações", "Interface"],
	["toggle_help", "Mostrar/esconder ajuda", "Interface"],
	["toggle_garage", "Garagem", "Interface"],
	["toggle_music", "Música liga/desliga", "Interface"],
	["cycle_time", "Horário do dia", "Interface"],
	["cycle_biome", "Ambiente", "Interface"],
	["toggle_racing_line", "Linha ideal (desligada / frenagens / completa)", "Interface"],
]

## Ações que não estão no project.godot (antes eram teclas fixas no código): [ação, tecla].
const EXTRA_ACTIONS := [
	["pit_soft", KEY_1], ["pit_medium", KEY_2], ["pit_hard", KEY_3],
	["standings_next", KEY_PAGEDOWN], ["standings_prev", KEY_PAGEUP],
	["pause", KEY_ESCAPE], ["open_settings", KEY_F10], ["toggle_help", KEY_H], ["toggle_racing_line", KEY_L],
	["pit_limiter", KEY_P], ["go_to_pit", KEY_K],
]
## Botões do controle das ações acima (Start pausa; o resto fica pelos menus).
const EXTRA_PAD := {"pause": JOY_BUTTON_START, "pit_limiter": JOY_BUTTON_DPAD_LEFT, "go_to_pit": JOY_BUTTON_BACK}

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160)]
const FPS_LIMITS := [0, 30, 60, 120, 144, 165, 240]
## 0 = automática: escala pela janela (o HUD foi desenhado para 1600 × 900).
const UI_SCALES := [0.0, 0.75, 0.9, 1.0, 1.15, 1.25, 1.5]
const UI_BASE := Vector2(1600, 900)
const SHADOW_SIZES := [2048, 4096, 8192, 16384]
const SHADOW_FILTERS := [1, 2, 3, 4]
const LOD_THRESHOLDS := [4.0, 2.0, 1.0, 0.5]

## Valores padrão (e tipos) de tudo que é salvo.
const DEFAULTS := {
	"display": {"window_mode": 0, "resolution": 2, "vsync": 1, "max_fps": 0, "ui_scale": 0, "fov": 68.0},
	"graphics": {"preset": 2, "render_scale": 1.0, "upscaler": 0, "msaa": 2, "screen_aa": 1, "taa": false,
		"shadows": 2, "ssao": true, "ssil": false, "glow": true, "volumetric_fog": true, "lod": 2},
	"performance": {"overlay": 0, "corner": 2, "online": 1},
	"gameplay": {"racing_line": 2, "auto_update": true},
	"audio": {"master": 1.0, "car": 1.0, "music": 1.0, "music_on": true, "track": 0, "mute_unfocused": true},
}

## Predefinições gráficas: chaves de "graphics" aplicadas juntas (Baixo, Médio, Alto, Ultra).
const PRESETS := [
	{"render_scale": 0.75, "upscaler": 1, "msaa": 0, "screen_aa": 1, "taa": false, "shadows": 0, "ssao": false,
		"ssil": false, "glow": true, "volumetric_fog": false, "lod": 0},
	{"render_scale": 0.9, "upscaler": 1, "msaa": 1, "screen_aa": 1, "taa": false, "shadows": 1, "ssao": true,
		"ssil": false, "glow": true, "volumetric_fog": false, "lod": 1},
	{"render_scale": 1.0, "upscaler": 0, "msaa": 2, "screen_aa": 1, "taa": false, "shadows": 2, "ssao": true,
		"ssil": false, "glow": true, "volumetric_fog": true, "lod": 2},
	{"render_scale": 1.0, "upscaler": 0, "msaa": 3, "screen_aa": 2, "taa": false, "shadows": 3, "ssao": true,
		"ssil": true, "glow": true, "volumetric_fog": true, "lod": 3},
]

var values := {}
var _default_events := {}
var _bus_base := {}
var _overlay: PerfOverlay
var _menu: SettingsMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_extra_actions()
	for a in ACTIONS:
		_default_events[a[0]] = InputMap.action_get_events(a[0]).duplicate()
	for bus in ["Master", "Car", "Rivals", "Music"]:
		var i := AudioServer.get_bus_index(bus)
		_bus_base[bus] = AudioServer.get_bus_volume_db(i) if i >= 0 else 0.0
	_overlay = PerfOverlay.new()
	add_child(_overlay)
	load_settings()
	apply_all()
	# O mundo 3D muda a cada cena carregada: reaplica os gráficos quando o ambiente aparece
	get_tree().node_added.connect(_on_node_added)
	# Escala automática acompanha o tamanho da janela
	get_tree().root.size_changed.connect(_apply_ui_scale)


func _register_extra_actions() -> void:
	# Menus pelo controle: A confirma (e Start), B volta
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B]]:
		var has := false
		for ev in InputMap.action_get_events(pair[0]):
			if ev is InputEventJoypadButton and ev.button_index == pair[1]:
				has = true
		if not has:
			var jb := InputEventJoypadButton.new()
			jb.button_index = pair[1]
			InputMap.action_add_event(pair[0], jb)
	for extra in EXTRA_ACTIONS:
		if InputMap.has_action(extra[0]):
			continue
		InputMap.add_action(extra[0])
		var ev := InputEventKey.new()
		ev.physical_keycode = extra[1]
		InputMap.action_add_event(extra[0], ev)
		if EXTRA_PAD.has(extra[0]):
			var pad := InputEventJoypadButton.new()
			pad.button_index = EXTRA_PAD[extra[0]]
			InputMap.action_add_event(extra[0], pad)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion or Retro.is_nav_event(event):
		Retro.using_pad = true
	elif event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length() > 4.0):
		Retro.using_pad = false
	# Navegação por controle/teclado sem nada focado: foca o primeiro item do menu de cima
	if Retro.is_nav_event(event) and get_viewport().gui_get_focus_owner() == null:
		if Retro.grab_any_focus(get_tree()):
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_settings") and not event.is_echo():
		toggle_menu()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Valores
# ---------------------------------------------------------------------------
func get_value(section: String, key: String) -> Variant:
	return values.get(section, {}).get(key, DEFAULTS[section][key])


func set_value(section: String, key: String, value: Variant, save := true) -> void:
	values[section][key] = value
	if section == "graphics" and key != "preset":
		values["graphics"]["preset"] = _matching_preset()
	_apply(section, key)
	changed.emit(section, key)
	if save:
		save_settings()


func apply_preset(index: int) -> void:
	values["graphics"]["preset"] = index
	for key in PRESETS[index]:
		values["graphics"][key] = PRESETS[index][key]
	_apply_graphics()
	changed.emit("graphics", "preset")
	save_settings()


## Índice da predefinição igual aos valores atuais, ou -1 (personalizado).
func _matching_preset() -> int:
	for k in PRESETS.size():
		var same := true
		for key in PRESETS[k]:
			if values["graphics"][key] != PRESETS[k][key]:
				same = false
				break
		if same:
			return k
	return -1


func reset_section(section: String) -> void:
	if section == "controls":
		for a in ACTIONS:
			InputMap.action_erase_events(a[0])
			for ev in _default_events[a[0]]:
				InputMap.action_add_event(a[0], ev)
	else:
		values[section] = DEFAULTS[section].duplicate(true)
	apply_all()
	changed.emit(section, "")
	save_settings()


func load_settings() -> void:
	values = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			var v: Variant = cfg.get_value(section, key, DEFAULTS[section][key])
			# Mantém o tipo do padrão (um arquivo editado à mão não quebra o jogo)
			if typeof(v) == typeof(DEFAULTS[section][key]) or (DEFAULTS[section][key] is float and v is int):
				values[section][key] = float(v) if DEFAULTS[section][key] is float else v
	if cfg.has_section("controls"):
		var old_pad := int(cfg.get_value("meta", "controls_version", 1)) < CONTROLS_VERSION
		for a in ACTIONS:
			if not cfg.has_section_key("controls", a[0]):
				continue
			var saved: Variant = cfg.get_value("controls", a[0])
			if not saved is Array:
				continue
			InputMap.action_erase_events(a[0])
			for d in saved:
				var ev := event_from_dict(d)
				if ev and not (old_pad and is_pad_event(ev)):
					InputMap.action_add_event(a[0], ev)
			if old_pad:
				for ev in _default_events[a[0]]:
					if is_pad_event(ev):
						InputMap.action_add_event(a[0], ev)
		if old_pad:
			save_settings.call_deferred()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for section in values:
		for key in values[section]:
			cfg.set_value(section, key, values[section][key])
	cfg.set_value("meta", "controls_version", CONTROLS_VERSION)
	for a in ACTIONS:
		var list := []
		for ev in InputMap.action_get_events(a[0]):
			var d := event_to_dict(ev)
			if not d.is_empty():
				list.append(d)
		cfg.set_value("controls", a[0], list)
	cfg.save(PATH)


# ---------------------------------------------------------------------------
# Controles
# ---------------------------------------------------------------------------
static func is_pad_event(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton or ev is InputEventJoypadMotion


## Evento de teclado/mouse (pad = false) ou de controle (pad = true) de uma ação, ou null.
func get_binding(action: String, pad: bool) -> InputEvent:
	for ev in InputMap.action_get_events(action):
		if is_pad_event(ev) == pad:
			return ev
	return null


## Troca o evento do tipo (teclado/controle) de uma ação; null apaga.
func set_binding(action: String, pad: bool, event: InputEvent) -> void:
	for ev in InputMap.action_get_events(action):
		if is_pad_event(ev) == pad:
			InputMap.action_erase_event(action, ev)
	if event:
		InputMap.action_add_event(action, event)
	changed.emit("controls", action)
	save_settings()


## Outras ações que usam o mesmo evento (para avisar conflitos).
func conflicts(action: String, event: InputEvent) -> PackedStringArray:
	var out := PackedStringArray()
	if event == null:
		return out
	for a in ACTIONS:
		if a[0] == action:
			continue
		for ev in InputMap.action_get_events(a[0]):
			if _same_input(ev, event):
				out.append(a[1])
	return out


static func _same_input(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return _key_code(a) == _key_code(b)
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return a.button_index == b.button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		return a.axis == b.axis and signf(a.axis_value) == signf(b.axis_value)
	return false


static func _key_code(ev: InputEventKey) -> Key:
	return ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode


## Nome legível de um evento ("W", "Espaço", "Botão A", "Gatilho direito"…).
static func event_label(ev: InputEvent) -> String:
	if ev == null:
		return "—"
	if ev is InputEventKey:
		var code := _key_code(ev)
		var names := {KEY_SPACE: "Espaço", KEY_ESCAPE: "Esc", KEY_ENTER: "Enter", KEY_TAB: "Tab",
			KEY_SHIFT: "Shift", KEY_CTRL: "Ctrl", KEY_ALT: "Alt", KEY_BACKSPACE: "Backspace",
			KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→", KEY_PAGEUP: "Page Up",
			KEY_PAGEDOWN: "Page Down", KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]"}
		var text: String = names.get(code, OS.get_keycode_string(code))
		if ev is InputEventKey and ev.location == KEY_LOCATION_LEFT and code in [KEY_ALT, KEY_SHIFT, KEY_CTRL]:
			text += " esq."
		return text
	if ev is InputEventMouseButton:
		return {MOUSE_BUTTON_LEFT: "Mouse esq.", MOUSE_BUTTON_RIGHT: "Mouse dir.", MOUSE_BUTTON_MIDDLE: "Mouse meio"}.get(
			ev.button_index, "Mouse %d" % ev.button_index)
	if ev is InputEventJoypadButton:
		var pad := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
			JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_BACK: "Back",
			JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
			JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓", JOY_BUTTON_DPAD_LEFT: "D-pad ←",
			JOY_BUTTON_DPAD_RIGHT: "D-pad →"}
		return "Botão " + pad.get(ev.button_index, str(ev.button_index))
	if ev is InputEventJoypadMotion:
		var plus: bool = ev.axis_value > 0.0
		match ev.axis:
			JOY_AXIS_LEFT_X:
				return "Analógico esq. " + ("→" if plus else "←")
			JOY_AXIS_LEFT_Y:
				return "Analógico esq. " + ("↓" if plus else "↑")
			JOY_AXIS_RIGHT_X:
				return "Analógico dir. " + ("→" if plus else "←")
			JOY_AXIS_RIGHT_Y:
				return "Analógico dir. " + ("↓" if plus else "↑")
			JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
		return "Eixo %d%s" % [ev.axis, "+" if plus else "−"]
	return ev.as_text()


static func event_to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"type": "key", "physical": int(ev.physical_keycode), "keycode": int(ev.keycode), "location": int(ev.location)}
	if ev is InputEventMouseButton:
		return {"type": "mouse", "button": int(ev.button_index)}
	if ev is InputEventJoypadButton:
		return {"type": "joy_button", "button": int(ev.button_index)}
	if ev is InputEventJoypadMotion:
		return {"type": "joy_axis", "axis": int(ev.axis), "value": float(ev.axis_value)}
	return {}


static func event_from_dict(d: Variant) -> InputEvent:
	if not d is Dictionary:
		return null
	match d.get("type", ""):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("physical", 0)) as Key
			k.keycode = int(d.get("keycode", 0)) as Key
			k.location = int(d.get("location", 0)) as KeyLocation
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(d.get("button", 1)) as MouseButton
			return m
		"joy_button":
			var b := InputEventJoypadButton.new()
			b.button_index = int(d.get("button", 0)) as JoyButton
			return b
		"joy_axis":
			var a := InputEventJoypadMotion.new()
			a.axis = int(d.get("axis", 0)) as JoyAxis
			a.axis_value = float(d.get("value", 1.0))
			return a
	return null


# ---------------------------------------------------------------------------
# Aplicação
# ---------------------------------------------------------------------------
func apply_all() -> void:
	_apply_display()
	_apply_graphics()
	_apply_audio()
	_configure_overlay()


func _apply(section: String, key: String) -> void:
	match section:
		"display":
			_apply_display(key)
		"graphics":
			_apply_graphics()
		"audio":
			_apply_audio()
		"performance":
			_configure_overlay()


func _configure_overlay() -> void:
	_overlay.online_mode = int(get_value("performance", "online"))
	_overlay.configure(get_value("performance", "overlay"), get_value("performance", "corner"))


func _apply_display(only := "") -> void:
	var headless := DisplayServer.get_name() == "headless"
	if not headless and (only == "" or only in ["window_mode", "resolution"]):
		var mode: int = get_value("display", "window_mode")
		var target: DisplayServer.WindowMode = [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN,
			DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN][clampi(mode, 0, 2)]
		if DisplayServer.window_get_mode() != target:
			DisplayServer.window_set_mode(target)
		if target == DisplayServer.WINDOW_MODE_WINDOWED and only != "":
			var size: Vector2i = RESOLUTIONS[clampi(get_value("display", "resolution"), 0, RESOLUTIONS.size() - 1)]
			var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			size = size.min(screen.size)
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
	if not headless and (only == "" or only == "vsync"):
		DisplayServer.window_set_vsync_mode([DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED,
			DisplayServer.VSYNC_ADAPTIVE, DisplayServer.VSYNC_MAILBOX][clampi(get_value("display", "vsync"), 0, 3)])
	if only == "" or only == "max_fps":
		Engine.max_fps = FPS_LIMITS[clampi(get_value("display", "max_fps"), 0, FPS_LIMITS.size() - 1)]
	if only == "" or only == "ui_scale":
		_apply_ui_scale()
	# fov é lido pela RaceCamera (sinal changed)


func _apply_ui_scale() -> void:
	var chosen: float = UI_SCALES[clampi(get_value("display", "ui_scale"), 0, UI_SCALES.size() - 1)]
	if chosen <= 0.0:
		var win := Vector2(DisplayServer.window_get_size()) if DisplayServer.get_name() != "headless" else UI_BASE
		chosen = clampf(minf(win.x / UI_BASE.x, win.y / UI_BASE.y), 0.75, 2.0)
	if not is_equal_approx(get_tree().root.content_scale_factor, chosen):
		get_tree().root.content_scale_factor = chosen


func _apply_graphics() -> void:
	var vp := get_viewport()
	var g: Dictionary = values["graphics"]
	vp.scaling_3d_scale = clampf(g["render_scale"], 0.5, 1.0)
	vp.scaling_3d_mode = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR,
		Viewport.SCALING_3D_MODE_FSR2][clampi(g["upscaler"], 0, 2)]
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][clampi(g["msaa"], 0, 3)]
	vp.screen_space_aa = [Viewport.SCREEN_SPACE_AA_DISABLED, Viewport.SCREEN_SPACE_AA_FXAA,
		Viewport.SCREEN_SPACE_AA_SMAA][clampi(g["screen_aa"], 0, 2)]
	vp.use_taa = g["taa"] or g["upscaler"] == 2
	vp.mesh_lod_threshold = LOD_THRESHOLDS[clampi(g["lod"], 0, 3)]
	var shadows := clampi(g["shadows"], 0, 3)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_SIZES[shadows], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_FILTERS[shadows] as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality(SHADOW_FILTERS[shadows] as RenderingServer.ShadowQuality)
	vp.positional_shadow_atlas_size = SHADOW_SIZES[shadows] / 2
	var world := vp.find_world_3d()
	var env := world.environment if world else null
	if env:
		env.ssao_enabled = g["ssao"]
		env.ssil_enabled = g["ssil"]
		env.glow_enabled = g["glow"]
		env.volumetric_fog_enabled = g["volumetric_fog"]


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		_apply_graphics.call_deferred()


func _apply_audio() -> void:
	var a: Dictionary = values["audio"]
	# O volume "Carro" vale para o seu carro e para os rivais (canais separados: o compressor do
	# seu motor não abafa os outros)
	for bus_key in [["Master", "master"], ["Car", "car"], ["Rivals", "car"], ["Music", "music"]]:
		var i := AudioServer.get_bus_index(bus_key[0])
		if i < 0:
			continue
		var v: float = a[bus_key[1]]
		AudioServer.set_bus_mute(i, v <= 0.001)
		AudioServer.set_bus_volume_db(i, _bus_base[bus_key[0]] + linear_to_db(maxf(v, 0.001)))
	var music := get_node_or_null("/root/Music")
	if music and music.has_method("configure"):
		music.configure(a["music_on"], a["track"])


## Foco da aplicação inteira (abrir a lista de um select é outra janela, mas não tira o foco do jogo).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_on_focus(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_on_focus(false)


func _on_focus(focused: bool) -> void:
	var i := AudioServer.get_bus_index("Master")
	if i < 0:
		return
	var v: float = values["audio"]["master"]
	AudioServer.set_bus_mute(i, v <= 0.001 or (not focused and values["audio"]["mute_unfocused"]))


# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------
func is_menu_open() -> bool:
	return _menu != null and is_instance_valid(_menu)


## Abre (ou fecha) o menu de configurações por cima de tudo; pausa o jogo enquanto aberto.
func toggle_menu() -> void:
	if is_menu_open():
		_menu.close()
	else:
		open_menu()


func open_menu() -> void:
	if is_menu_open() or LoadingScreen.is_loading():
		return
	_menu = SettingsMenu.new()
	_menu.was_paused = get_tree().paused
	# Corrida em rede não pausa (o servidor segue correndo)
	get_tree().paused = not RaceManager.online_race
	add_child(_menu)
