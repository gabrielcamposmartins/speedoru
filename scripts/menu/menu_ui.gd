class_name MenuUI
extends CanvasLayer
## Interface do menu principal (visual retrofuturista): logo, saldo de créditos, botões grandes à
## esquerda e as telas Jogar solo (configurar a corrida) e Garagem (Estúdio, Galeria, Loja).
## No Estúdio o painel é compacto e fica à direita (o carro vem para o centro-esquerda); Galeria e
## Loja usam o painel largo à esquerda. Esc volta ao início.
## Multiplayer (MultiplayerPanel): salas, amigos, grupo, ranking e perfil; convites e avisos do
## servidor aparecem em qualquer tela.

const LEFT := 56.0

var menu: Node3D
var screen := "home"
var garage_tab := 0

var _root: Control
var _body: Control
var _shade: TextureRect
var _wallet: Label
var _logo_node: Control
var _wallet_node: Control
var _toast: Label
var _profile: PlayerProfile
var _net: Node
var _invites: VBoxContainer
## Sala em que o jogador está ("" = nenhuma): só entrar numa sala nova abre a tela dela.
var _room_id := ""
## Cartão das missões na tela inicial (só conectado ao servidor).
var _missions_card: Control


func _ready() -> void:
	layer = 4
	_profile = get_node("/root/Profile") as PlayerProfile
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = Retro.theme()
	add_child(_root)
	# Sombra à esquerda para o menu ler bem sobre a garagem
	_shade = TextureRect.new()
	var shade := _shade
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(Retro.c("bg"), 0.92), Color(Retro.c("bg"), 0.7), Color(Retro.c("bg"), 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 128
	gt.height = 4
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_bottom = 1.0
	shade.anchor_right = 0.62
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	_logo_node = _logo()
	_root.add_child(_logo_node)
	_wallet_node = _wallet_panel()
	_root.add_child(_wallet_node)
	_body = Control.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_body)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(-300, -110)
	_toast.size = Vector2(600, 40)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_override("font", Retro.display(800))
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", Retro.c("warn"))
	_toast.modulate.a = 0.0
	_root.add_child(_toast)
	_invites = VBoxContainer.new()
	_invites.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_invites.position = Vector2(-390, 120)
	_invites.custom_minimum_size = Vector2(350, 0)
	_invites.add_theme_constant_override("separation", 8)
	_root.add_child(_invites)
	_profile.changed.connect(_update_wallet)
	_update_wallet()
	_net = get_node_or_null("/root/Net")
	if _net:
		_room_id = str((_net.room as Dictionary).get("id", ""))
		_net.message.connect(_on_net_message)
		_net.connection_changed.connect(func(_o: bool) -> void:
			if screen == "home":
				show_screen("home"))
		# A conta mudou (corrida terminada, missão completa, giro): atualiza o cartão das missões
		_net.account_changed.connect(func() -> void:
			if screen == "home" and is_instance_valid(_missions_card):
				_build_missions_card())
	var back_to := RaceSettings.return_to
	RaceSettings.return_to = ""
	show_screen("multiplayer" if back_to == "multiplayer" and _net and _net.online else "home")
	Retro.events.changed.connect(_restyle)


## Estilo ou paleta da interface trocados (nas configurações): refaz o que guardou cores e
## fontes do estilo anterior e remonta a tela atual.
func _restyle() -> void:
	var g := (_shade.texture as GradientTexture2D).gradient
	g.colors = PackedColorArray([Color(Retro.c("bg"), 0.92), Color(Retro.c("bg"), 0.7), Color(Retro.c("bg"), 0.0)])
	for old in [_logo_node, _wallet_node]:
		old.queue_free()
	_logo_node = _logo()
	_root.add_child(_logo_node)
	_root.move_child(_logo_node, _shade.get_index() + 1)
	_wallet_node = _wallet_panel()
	_root.add_child(_wallet_node)
	_root.move_child(_wallet_node, _logo_node.get_index() + 1)
	_update_wallet()
	_toast.add_theme_font_override("font", Retro.display(800))
	_toast.add_theme_color_override("font_color", Retro.c("warn"))
	show_screen(screen)


func _unhandled_input(event: InputEvent) -> void:
	if (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")) and screen != "home":
		show_screen("home")
		get_viewport().set_input_as_handled()
	elif screen == "garage" and event is InputEventJoypadButton and event.pressed \
			and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		# LB/RB: aba anterior/próxima (Estúdio, Galeria, Loja)
		garage_tab = posmod(garage_tab + (1 if event.button_index == JOY_BUTTON_RIGHT_SHOULDER else -1), 3)
		show_screen("garage")
		get_viewport().set_input_as_handled()


## O nó (ou um ancestral) está marcado para ser apagado (tela que acabou de ser trocada).
func _dying(node: Node) -> bool:
	while node:
		if node.is_queued_for_deletion():
			return true
		node = node.get_parent()
	return false


## Com controle (ou navegando pelo teclado), a tela nova já abre com o primeiro item em foco.
func _focus_screen() -> void:
	# Espera a tela assentar (painéis como o Estúdio se reconstroem no quadro seguinte)
	for i in 2:
		await get_tree().process_frame
	if not Retro.using_pad or not is_inside_tree():
		return
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and owner.is_visible_in_tree() and not _dying(owner):
		return
	var first := Retro.first_focusable(_body)
	if first:
		first.grab_focus()


# ---------------------------------------------------------------------------
func _logo() -> Control:
	var logo := LogoText.new()
	logo.position = Vector2(LEFT, 34)
	logo.size = Vector2(620, 120)
	return logo


func _wallet_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Retro.panel_style(14.0, 0.85))
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-330, 32)
	panel.custom_minimum_size = Vector2(290, 0)
	Retro.add_corners(panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var icon := Label.new()
	icon.text = "◆"
	icon.add_theme_font_size_override("font_size", 24)
	icon.add_theme_color_override("font_color", Retro.c("warn"))
	box.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	box.add_child(v)
	_wallet = Label.new()
	_wallet.add_theme_font_override("font", Retro.display(800))
	_wallet.add_theme_font_size_override("font_size", 24)
	v.add_child(_wallet)
	var unit := Label.new()
	unit.text = ShopCatalog.CURRENCY.to_upper()
	unit.theme_type_variation = "RetroKicker"
	v.add_child(unit)
	return panel


func _update_wallet() -> void:
	_wallet.text = PlayerProfile.format_credits(_profile.credits)


func toast(text: String) -> void:
	_toast.text = text
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.8)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


# ---------------------------------------------------------------------------
# Telas
# ---------------------------------------------------------------------------
func show_screen(name: String) -> void:
	screen = name
	# Saindo da Galeria: o carro volta para o que está equipado e a câmera para a órbita normal
	if menu and menu.has_method("clear_preview"):
		menu.clear_preview()
	for c in _body.get_children():
		c.queue_free()
	match name:
		"home":
			_build_home()
		"solo":
			_build_solo()
		"garage":
			_build_garage()
		"multiplayer":
			_build_multiplayer()
	var studio := name == "garage" and garage_tab in [0, 1]
	# Degradê de leitura do lado do painel (mais leve no Estúdio, para o carro aparecer)
	_shade.flip_h = studio
	_shade.anchor_left = 0.55 if studio else 0.0
	_shade.anchor_right = 1.0 if studio else 0.62
	_shade.modulate.a = 0.6 if studio else 1.0
	if menu:
		menu.set("car_shift", -0.11 if studio else (0.34 if name == "garage" else 0.26))
	_focus_screen.call_deferred()


func _build_home() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(LEFT, 210)
	box.add_theme_constant_override("separation", 14)
	_body.add_child(box)
	var entries := [
		["JOGAR SOLO", "Corrida contra bots em pistas reais, no céu ou no fundo do mar · pit obrigatório", func() -> void: show_screen("solo"), false],
		["MULTIPLAYER", _multiplayer_subtitle(), func() -> void: show_screen("multiplayer"), false],
		["GARAGEM", "Estúdio, galeria e loja", func() -> void: show_screen("garage"), false],
		["CONFIGURAÇÕES", "Controles, tela, gráficos, desempenho e áudio", func() -> void: menu.open_settings(), false],
		["SAIR", "Fechar o jogo", func() -> void: get_tree().quit(), false],
	]
	for k in entries.size():
		var e: Array = entries[k]
		var b := BigButton.new()
		b.title = e[0]
		b.subtitle = e[1]
		b.soon = e[3]
		b.primary = k == 0
		b.pressed.connect(e[2])
		box.add_child(b)
		# Entrada escalonada
		b.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.05 * k)
		tw.tween_property(b, "modulate:a", 1.0, 0.25)
	if _net and _net.online:
		_build_missions_card()
		_refresh_missions()


## Pede as missões de novo (o dia pode ter virado com o jogo aberto).
func _refresh_missions() -> void:
	var r: Dictionary = await _net.request("missions", {})
	if r.has("missions") and _net.online:
		_net.account["missions"] = r
		if screen == "home" and is_instance_valid(_missions_card):
			_build_missions_card()


## Cartão à direita da tela inicial, logo abaixo dos créditos e da mesma largura (o carro continua
## à vista): as três missões do dia com o progresso e o prêmio, a semana, a roleta do vencedor para
## girar e os tickets. A aba MISSÕES do multiplayer tem os detalhes.
func _build_missions_card() -> void:
	if is_instance_valid(_missions_card):
		_missions_card.queue_free()
	var acc: Dictionary = _net.account
	var ms: Dictionary = acc.get("missions", {})
	var panel := PanelContainer.new()
	panel.name = "MissionsCard"
	panel.add_theme_stylebox_override("panel", Retro.panel_style(16.0, 0.88))
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.custom_minimum_size = Vector2(_wallet_node.custom_minimum_size.x, 0)
	panel.position = Vector2(_wallet_node.position.x, _wallet_node.position.y + 80)
	Retro.add_corners(panel)
	_body.add_child(panel)
	_missions_card = panel
	# Encosta embaixo dos créditos (a altura deles só se sabe depois do layout)
	(func() -> void:
		if is_instance_valid(panel) and is_instance_valid(_wallet_node):
			panel.custom_minimum_size.x = _wallet_node.size.x
			# Altura volta ao mínimo (os textos com quebra de linha medem errado no primeiro layout)
			panel.size = Vector2(_wallet_node.size.x, 0)
			panel.position = Vector2(_wallet_node.position.x, _wallet_node.position.y + _wallet_node.size.y + 10)).call_deferred()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "MISSÕES DE HOJE"
	title.theme_type_variation = "RetroKicker"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var left := int(ms.get("reset_in", 0))
	if left > 0:
		var reset := Label.new()
		reset.text = "renova em %dh%02d" % [left / 3600, (left % 3600) / 60]
		reset.theme_type_variation = "RetroMuted"
		reset.add_theme_font_size_override("font_size", 11)
		head.add_child(reset)
	var list: Array = ms.get("missions", [])
	if list.is_empty():
		var wait := Label.new()
		wait.text = "Carregando missões…"
		wait.theme_type_variation = "RetroMuted"
		box.add_child(wait)
	for m: Dictionary in list:
		var done: bool = m.get("done", false)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var name_l := Label.new()
		name_l.text = ("✓ " if done else "") + str(m.get("text", ""))
		name_l.tooltip_text = str(m.get("text", ""))
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		name_l.clip_text = true
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.add_theme_font_size_override("font_size", 14)
		name_l.add_theme_color_override("font_color", Retro.c("good") if done else Retro.c("text"))
		row.add_child(name_l)
		var prize := Label.new()
		prize.text = "+%s" % PlayerProfile.format_credits(int(m.get("credits", 0)))
		prize.add_theme_font_override("font", Retro.display(800))
		prize.add_theme_font_size_override("font_size", 13)
		prize.add_theme_color_override("font_color", Retro.c("muted") if done else Retro.c("warn"))
		row.add_child(prize)
		if not done:
			var bar_row := HBoxContainer.new()
			bar_row.add_theme_constant_override("separation", 8)
			box.add_child(bar_row)
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, 6)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.max_value = maxi(int(m.get("goal", 1)), 1)
			bar.value = int(m.get("progress", 0))
			bar_row.add_child(bar)
			var count := Label.new()
			count.text = "%d/%d" % [int(m.get("progress", 0)), int(m.get("goal", 1))]
			count.theme_type_variation = "RetroMuted"
			count.add_theme_font_size_override("font_size", 11)
			bar_row.add_child(count)
	box.add_child(HSeparator.new())
	var week_done := int(ms.get("week_done", 0))
	var week_goal := maxi(int(ms.get("week_goal", Missions.WEEK_GOAL)), 1)
	var week := Label.new()
	week.add_theme_font_size_override("font_size", 12)
	if ms.get("week_paid", false):
		week.text = "Semana completa: prêmio recebido ✓"
		week.add_theme_color_override("font_color", Retro.c("good"))
	else:
		week.text = "SEMANA %d/%d" % [week_done, week_goal]
		week.add_theme_color_override("font_color", Retro.c("text_2"))
	box.add_child(week)
	var wbar := ProgressBar.new()
	wbar.show_percentage = false
	wbar.custom_minimum_size = Vector2(0, 6)
	wbar.max_value = week_goal
	wbar.value = week_done
	box.add_child(wbar)
	var spins := int(acc.get("race_spins", 0))
	if spins > 0:
		var spin := Button.new()
		spin.text = "ROLETA DO VENCEDOR (%d)" % spins
		spin.theme_type_variation = "PrimaryButton"
		spin.custom_minimum_size = Vector2(0, 36)
		spin.add_theme_font_size_override("font_size", 13)
		spin.clip_text = true
		spin.pressed.connect(func() -> void:
			var wheel := PrizeWheel.new()
			get_tree().root.add_child(wheel))
		box.add_child(spin)
	var tickets := int((acc.get("profile", {}) as Dictionary).get("tickets", 0))
	if tickets > 0:
		var tk := Label.new()
		tk.text = "Tickets da loja: %d" % tickets
		tk.theme_type_variation = "RetroMuted"
		tk.add_theme_font_size_override("font_size", 12)
		box.add_child(tk)


func _multiplayer_subtitle() -> String:
	if _net == null or not _net.online:
		return "Offline · conectar ao servidor"
	var room: Dictionary = _net.room
	if not room.is_empty():
		return "Na sala %s" % room.get("name", "")
	return "Salas, amigos, grupo, ranking e perfil"


func _build_multiplayer() -> void:
	var box := _panel("MULTIPLAYER", 0.62)
	var mp := MultiplayerPanel.new()
	mp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(mp)
	mp.setup(self)


## Avisos do servidor em qualquer tela do menu.
func _on_net_message(type: String, data: Dictionary) -> void:
	match type:
		"friend_online":
			toast("%s está online" % data.get("name", ""))
		"friend_request":
			toast("%s quer ser seu amigo" % data.get("name", ""))
		"notice":
			toast(str(data.get("text", "")))
		"level_up":
			var unlocked: Array = data.get("unlocked", [])
			toast("Nível %d!%s" % [int(data.get("level", 1)), (" Bots liberados: " + ", ".join(unlocked)) if not unlocked.is_empty() else ""])
		"rewards":
			# Conquistas pagas ao entrar (feitas antes de as conquistas pagarem)
			var total := 0
			for a: Dictionary in data.get("achievements", []):
				total += int(a.get("credits", 0))
			var n := (data.get("achievements", []) as Array).size()
			if n > 0:
				toast("Recompensas de %d conquista%s: +%s %s" % [n, "s" if n > 1 else "", PlayerProfile.format_credits(total), ShopCatalog.CURRENCY])
		"party_ask":
			_invite("%s chamou você para o grupo" % data.get("name", ""),
				func() -> void: _net.request("party_accept", {"party": data["party"]}),
				func() -> void: _net.request("party_decline", {"party": data["party"]}))
		"room_ask":
			_invite("%s chamou você para a sala %s" % [data.get("name", ""), data.get("room_name", "")],
				func() -> void:
					var r: Dictionary = await _net.request("room_join", {"id": data["room"]})
					if not r.get("ok", false):
						toast(str(r.get("error", ""))),
				Callable())
		"room":
			# Puxado para uma sala (grupo, convite, fila): abre a tela da sala. Só ao entrar nela: as
			# atualizações da sala em que já está (ajustes do anfitrião, alguém pronto) não tiram o
			# jogador do que está fazendo (garagem, loja…)
			var id := str((data.get("room", {}) as Dictionary).get("id", ""))
			if id != "" and id != _room_id and screen != "multiplayer":
				MultiplayerPanel.tab = "rooms"
				show_screen("multiplayer")
			_room_id = id


## Cartão de convite (Aceitar / Recusar), some sozinho em 20 s.
func _invite(text: String, accept: Callable, decline: Callable) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Retro.panel_style(12.0, 0.92))
	Retro.add_corners(panel)
	_invites.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var yes := Button.new()
	yes.text = "Aceitar"
	yes.theme_type_variation = "PrimaryButton"
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.pressed.connect(func() -> void:
		accept.call()
		panel.queue_free())
	row.add_child(yes)
	var no := Button.new()
	no.text = "Recusar"
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(func() -> void:
		if decline.is_valid():
			decline.call()
		panel.queue_free())
	row.add_child(no)
	get_tree().create_timer(20.0).timeout.connect(func() -> void:
		if is_instance_valid(panel):
			if decline.is_valid():
				decline.call()
			panel.queue_free())


func _panel(kicker: String, width_ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Retro.panel_style(22.0, 0.9))
	panel.anchor_left = 0.0
	panel.anchor_right = width_ratio
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = LEFT
	panel.offset_top = 196
	panel.offset_bottom = -34
	Retro.add_corners(panel)
	_body.add_child(panel)
	var tag := Retro.tag_label(kicker, 13)
	tag.position = Vector2(LEFT + 18, 184)
	_body.add_child(tag)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return box


## Jogar solo: a pista num carrossel em cima e duas colunas (corrida | classificatória e
## ambiente), cada opção com o nome em cima; a área das opções rola se a janela for baixa e os
## botões ficam sempre embaixo.
func _build_solo() -> void:
	var box := _panel("JOGAR SOLO", 0.64)
	var race_rows := [
		["Modo", ["Corrida (pit obrigatório)", "Treino livre"], RaceSettings.mode, func(i: int) -> void: RaceSettings.mode = i as RaceSettings.Mode],
		["Voltas", ["3", "5", "10", "15", "20"], [3, 5, 10, 15, 20].find(RaceSettings.laps), func(i: int) -> void: RaceSettings.laps = [3, 5, 10, 15, 20][i]],
		["Adversários", ["3", "5", "9", "13"], maxi([3, 5, 9, 13].find(RaceSettings.opponents), 0), func(i: int) -> void: RaceSettings.opponents = [3, 5, 9, 13][i]],
		["Dificuldade dos bots", ["Fácil", "Médio", "Difícil", "Mista"], RaceSettings.difficulty, func(i: int) -> void: RaceSettings.difficulty = i],
		["Largada", ["Pole position", "Meio do grid", "Última fila"], RaceSettings.grid, func(i: int) -> void: RaceSettings.grid = i as RaceSettings.Grid],
		["DRS", ["Livre", "Só a até 1 s do carro da frente"], RaceSettings.drs_rule, func(i: int) -> void: RaceSettings.drs_rule = i,
			["Colisões no box", RaceSettings.pit_collisions, func(on: bool) -> void: RaceSettings.pit_collisions = on]],
	]
	var more_rows := [
		["Classificatória", RaceSettings.QUALI_LAP_NAMES, RaceSettings.quali_laps,
			func(i: int) -> void: RaceSettings.quali_laps = i,
			["Colisão entre os carros", RaceSettings.quali_collisions, func(on: bool) -> void: RaceSettings.quali_collisions = on]],
		["Tempo da classificatória", RaceSettings.QUALI_TIME_NAMES, RaceSettings.quali_time,
			func(i: int) -> void: RaceSettings.quali_time = i,
			["Infração anula a volta", RaceSettings.quali_strict, func(on: bool) -> void: RaceSettings.quali_strict = on]],
		["Horário", Array(DaylightPresets.TIME_NAMES), RaceSettings.time_of_day, func(i: int) -> void: RaceSettings.time_of_day = i],
		["Ambiente", Array(DaylightPresets.BIOME_NAMES), RaceSettings.biome, func(i: int) -> void: RaceSettings.biome = i],
	]
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 14)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	# Pista: abas Reais/Fantasia e o carrossel com as pistas da categoria
	var carousel := TrackCarousel.new()
	carousel.name = "TrackCarousel"
	carousel.selected = RaceSettings.track_index(RaceSettings.track)
	carousel.category = RaceSettings.category_of(RaceSettings.track)
	carousel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carousel.track_changed.connect(func(i: int) -> void: RaceSettings.track = RaceSettings.TRACKS[i]["id"])
	inner.add_child(TrackCarousel.category_tabs(carousel))
	inner.add_child(carousel)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(cols)
	var left := _solo_column(cols, "CORRIDA")
	var right := _solo_column(cols, "CLASSIFICATÓRIA E AMBIENTE")
	for r in race_rows:
		_solo_option(left, r)
	for r in more_rows:
		_solo_option(right, r)
	var per_lap: int = ShopCatalog.REWARD_PER_LAP[clampi(RaceSettings.difficulty, 0, 3)]
	for text in ["Prêmio: %d %s por volta completada (fácil %d · médio %d · difícil %d · mista %d). Treino livre não paga." % (
				[per_lap, ShopCatalog.CURRENCY] + ShopCatalog.REWARD_PER_LAP),
			"Regras: limites de pista (3 avisos, depois +5 s), cortar a pista +5 s, colisão +5/+10 s, largada queimada +10 s, mais de 80 km/h nos boxes +5 s, sem pit stop = desclassificado."]:
		var note := Label.new()
		note.text = text
		note.theme_type_variation = "RetroMuted"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 13)
		right.add_child(note)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var go := Button.new()
	go.text = "CORRER"
	go.theme_type_variation = "PrimaryButton"
	go.custom_minimum_size = Vector2(0, 52)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(menu.start_race)
	buttons.add_child(go)
	var back := Button.new()
	back.text = "Voltar"
	back.custom_minimum_size = Vector2(150, 52)
	back.pressed.connect(show_screen.bind("home"))
	buttons.add_child(back)


func _solo_column(parent: Container, heading: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.0
	parent.add_child(col)
	var h := Label.new()
	h.text = heading
	h.theme_type_variation = "RetroKicker"
	h.add_theme_color_override("font_color", Retro.c("accent_2"))
	col.add_child(h)
	return col


## Uma opção: nome em cima, a lista embaixo e, se houver, a caixa de marcar logo abaixo.
## r = [nome, itens, selecionado, ao escolher, (caixa: [texto, marcada, ao mudar])]
func _solo_option(col: VBoxContainer, r: Array) -> void:
	var item := VBoxContainer.new()
	item.add_theme_constant_override("separation", 4)
	col.add_child(item)
	var l := Label.new()
	l.text = str(r[0]).to_upper()
	l.theme_type_variation = "RetroKicker"
	l.add_theme_font_size_override("font_size", 12)
	item.add_child(l)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.clip_text = true
	for text in r[1]:
		o.add_item(text)
	# Online: a dificuldade dos bots é liberada por nível (o servidor confere)
	if r[0] == "Dificuldade dos bots" and _net and _net.online:
		var level := int(_net.account.get("level", 1))
		for k in o.item_count:
			if not Progression.tier_unlocked(k, level):
				o.set_item_disabled(k, true)
				o.set_item_text(k, "%s (nível %d)" % [o.get_item_text(k), Progression.TIER_LEVEL[k]])
		if not Progression.tier_unlocked(RaceSettings.difficulty, level):
			RaceSettings.difficulty = 0
			r[2] = 0
	o.selected = maxi(int(r[2]), 0)
	o.item_selected.connect(r[3])
	item.add_child(o)
	if r.size() > 4:
		var chk: Array = r[4]
		var cb := CheckBox.new()
		cb.text = chk[0]
		cb.button_pressed = chk[1]
		cb.toggled.connect(chk[2])
		item.add_child(cb)


func _garage_tabs(box: Container, compact: bool) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)
	for k in 3:
		var b := Button.new()
		b.text = ["ESTÚDIO", "GALERIA", "LOJA"][k]
		b.custom_minimum_size = Vector2(0 if compact else 150, 36)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL
		b.add_theme_font_override("font", Retro.display(700))
		b.add_theme_font_size_override("font_size", 11 if compact else 13)
		if k == garage_tab:
			b.theme_type_variation = "PrimaryButton"
			b.add_theme_font_size_override("font_size", 10 if compact else 12)
		b.pressed.connect(func() -> void:
			garage_tab = k
			show_screen("garage"))
		head.add_child(b)
	if not compact:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(spacer)
	var back := Button.new()
	back.text = "←" if compact else "Voltar (Esc)"
	back.tooltip_text = "Voltar (Esc)"
	back.custom_minimum_size = Vector2(40 if compact else 0, 36)
	back.pressed.connect(show_screen.bind("home"))
	head.add_child(back)


func _build_garage() -> void:
	if garage_tab in [0, 1]:
		_build_side_panel()
	else:
		var box := _panel("GARAGEM", 0.6)
		_garage_tabs(box, false)
		var scroll := ScrollContainer.new()
		scroll.follow_focus = true
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.add_child(scroll)
		var shop := ShopPanel.new()
		shop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(shop)
		shop.setup()


## Estúdio e Galeria: painel compacto à direita (abas de ícones + 2 colunas), fundo mais
## transparente; o carro fica em foco no centro-esquerda.
func _build_side_panel() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Retro.panel_style(16.0, 0.55))
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -LEFT - 400
	panel.offset_right = -LEFT * 0.5
	panel.offset_top = 132
	panel.offset_bottom = -34
	Retro.add_corners(panel)
	_body.add_child(panel)
	var tag := Retro.tag_label("ESTÚDIO" if garage_tab == 0 else "GALERIA", 13)
	tag.anchor_left = 1.0
	tag.anchor_right = 1.0
	tag.offset_left = -LEFT - 382
	tag.offset_top = 120
	_body.add_child(tag)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	box.add_child(spacer)
	_garage_tabs(box, true)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	if garage_tab == 0:
		var studio := StudioPanel.new()
		scroll.add_child(studio)
		studio.setup(menu.car)
		if studio.category in StudioPanel.LIGHT_PREVIEW:
			menu.set_light_preview(studio.category)
			menu.focus_on("mirrors" if studio.category == "signal" else studio.category)
		# Decalques: a câmera vai até o lugar escolhido (e volta à órbita ao sair da aba)
		studio.focus_request.connect(func(key: String) -> void:
			# Boost e luz de ultrapassagem: além do foco, a luz acende no carro parado
			menu.set_light_preview(key if key in StudioPanel.LIGHT_PREVIEW else "")
			if key == "":
				menu.clear_focus()
			else:
				menu.focus_on("mirrors" if key == "signal" else key))
	else:
		var gallery := GalleryPanel.new()
		gallery.on_go_shop = func(_roulette: String) -> void:
			garage_tab = 2
			show_screen("garage")
		scroll.add_child(gallery)
		gallery.setup(menu)


# ---------------------------------------------------------------------------
## Logo em texto. Retrô: SPEEDORU em Orbitron com halo + subtítulo. Speedoru: Exo 2 itálica com
## sombras magenta/ciano deslocadas, bandeira quadriculada e a faixa "AM I RIGHT? ///".
class LogoText extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if Retro.is_pop():
			_draw_pop()
			return
		var f := Retro.display(900)
		Retro.draw_glow_text(self, f, Vector2(0, 70), "SPEEDORU", HORIZONTAL_ALIGNMENT_LEFT, -1, 72, Retro.c("text"),
			Retro.c("accent"), 1.4)
		draw_rect(Rect2(4, 86, 300, 3), Retro.c("accent"))
		draw_rect(Rect2(310, 86, 80, 3), Retro.c("accent_2"))
		draw_string(Retro.display(700), Vector2(4, 112), "FASTER  /  FURTHER  /  BEYOND", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Retro.c("accent_2"))

	func _draw_pop() -> void:
		var f := Retro.display(900)
		var ink := Retro.c("ink")
		var size_px := 82
		var base := Vector2(2, 76)
		var tw := f.get_string_size("SPEEDORU", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		# Bandeira quadriculada atrás do fim da palavra, com rastro amarelo/magenta
		var flag := Rect2(tw + 8, 16, 110, 40)
		draw_colored_polygon(PackedVector2Array([flag.position + Vector2(30, 34), flag.end + Vector2(20, -10),
			flag.end + Vector2(10, 4), flag.position + Vector2(18, 48)]), Retro.c("warn"))
		Retro.draw_checker(self, flag, 7, Color.WHITE, Retro.c("accent"))
		# Palavra: sombra dura escura, magenta e ciano deslocados (aberração), branco por cima
		draw_string_outline(f, base + Vector2(6, 6), "SPEEDORU", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 12, ink)
		draw_string(f, base + Vector2(5, 4), "SPEEDORU", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Retro.c("accent"))
		draw_string(f, base + Vector2(-3, -2), "SPEEDORU", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Retro.c("accent_2"))
		draw_string_outline(f, base, "SPEEDORU", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 6, ink)
		draw_string(f, base, "SPEEDORU", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color.WHITE)
		# Faixa inclinada "AM I RIGHT? ///"
		var sub := Retro.display(800)
		var text := "AM I RIGHT?"
		var sw := sub.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var x0 := 150.0
		var h := 28.0
		var w := sw + 92.0
		var band := PackedVector2Array([Vector2(x0 + 10, 88), Vector2(x0 + w + 10, 88), Vector2(x0 + w, 88 + h), Vector2(x0, 88 + h)])
		var shadow := PackedVector2Array()
		for v in band:
			shadow.append(v + Vector2(5, 4))
		draw_colored_polygon(shadow, Retro.c("accent"))
		draw_colored_polygon(band, ink)
		draw_string(sub, Vector2(x0 + 22, 108), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		Retro.draw_slashes(self, Vector2(x0 + 32 + sw, 94), 16.0, Retro.c("accent"))
		draw_rect(Rect2(4, 100, x0 - 14, 4), Retro.c("accent_2"))


## Botão grande do menu: painel chanfrado, título em Orbitron e uma linha de descrição; no hover
## acende (degradê do acento) e desliza para a direita.
class BigButton extends Button:
	var title := ""
	var subtitle := ""
	var soon := false
	var primary := false
	var _hover := 0.0

	func _ready() -> void:
		custom_minimum_size = Vector2(500, 82)
		flat = true
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _process(delta: float) -> void:
		var target := 1.0 if is_hovered() or has_focus() else 0.0
		if not is_equal_approx(_hover, target):
			_hover = move_toward(_hover, target, delta * 6.0)
			queue_redraw()

	func _draw() -> void:
		if Retro.is_pop():
			_draw_pop()
			return
		var x := _hover * 14.0
		var w := size.x - 40.0
		var h := size.y
		var cut := 22.0
		var pts := PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w - cut, h), Vector2(x, h)])
		var accent := Retro.c("accent")
		var lit := primary or _hover > 0.0
		if lit:
			var a := accent if primary else accent.lerp(Retro.c("surface_3"), 1.0 - _hover)
			var b := Retro.c("accent_3") if primary else Retro.c("accent_3").lerp(Retro.c("surface_2"), 1.0 - _hover)
			draw_polygon(pts, PackedColorArray([a, b, b, a]))
			for g in 3:
				draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(accent, 0.12 - g * 0.035), 4.0 + g * 4.0)
		else:
			var top := Color(Retro.c("surface_2"), 0.88)
			var bot := Color(Retro.c("surface"), 0.92)
			draw_polygon(pts, PackedColorArray([top, top, bot, bot]))
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Retro.line(2), 1.0)
		draw_rect(Rect2(x, 0, 5, h), Retro.c("accent_2") if not lit else Color.WHITE)
		var dark := lit and (primary or _hover > 0.5)
		var title_col := Retro.c("on_accent") if dark else Retro.c("text")
		var sub_col := Color(Retro.c("on_accent"), 0.75) if dark else Retro.c("muted")
		if soon:
			title_col = Color(title_col, 0.6)
		draw_string(Retro.display(900), Vector2(x + 26, 42), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, title_col)
		draw_string(Retro.body(600), Vector2(x + 28, 66), subtitle, HORIZONTAL_ALIGNMENT_LEFT, w - 60, 14, sub_col)
		if soon:
			var f := Retro.display(800)
			var tw := f.get_string_size("EM BREVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 16
			var chip := Rect2(x + w - cut - tw - 16, 14, tw, 22)
			draw_rect(chip, Color(Retro.c("warn"), 0.18))
			draw_rect(chip, Retro.c("warn"), false, 1.0)
			draw_string(f, chip.position + Vector2(8, 15), "EM BREVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Retro.c("warn"))

	## Speedoru: paralelogramo com sombra dura; aceso (principal ou hover) fica magenta chapado
	## com sombra ciano (amarela no hover) e "///" no fim.
	func _draw_pop() -> void:
		var x := _hover * 14.0
		var w := size.x - 40.0
		var h := size.y
		var lean := 20.0
		var pts := PackedVector2Array([Vector2(x + lean, 0), Vector2(x + w, 0), Vector2(x + w - lean, h), Vector2(x, h)])
		var accent := Retro.c("accent")
		var lit := primary or _hover > 0.0
		var amount := 1.0 if primary else _hover
		var shadow_col := Retro.c("accent_2") if primary else Retro.c("warn")
		var off := Vector2(7, 6) * (amount if lit else 0.0) + Vector2(5, 5) * (1.0 - (amount if lit else 0.0))
		var shadow := PackedVector2Array()
		for v in pts:
			shadow.append(v + off)
		draw_colored_polygon(shadow, Color(Retro.c("ink"), 0.6).lerp(shadow_col, amount if lit else 0.0))
		var top := Color(Retro.c("surface_2"), 0.94).lerp(accent, amount if lit else 0.0)
		var bot := Color(Retro.c("surface"), 0.94).lerp(accent.darkened(0.12), amount if lit else 0.0)
		draw_polygon(pts, PackedColorArray([top, top, bot, bot]))
		var border := Color(Retro.c("accent_3"), 0.7).lerp(Color.WHITE, amount if lit else 0.0)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), border, 2.0)
		# Faixa inclinada à esquerda (ciano; branca quando aceso)
		draw_colored_polygon(PackedVector2Array([pts[0], pts[0] + Vector2(8, 0), pts[3] + Vector2(8, 0), pts[3]]),
			Retro.c("accent_2").lerp(Color.WHITE, amount if lit else 0.0))
		var ink := Retro.c("ink")
		var title_col := Color.WHITE
		if soon:
			title_col = Color(title_col, 0.6)
		var font := Retro.display(900)
		draw_string_outline(font, Vector2(x + 36, 46), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 31, 5, Color(ink, 0.85))
		draw_string(font, Vector2(x + 36, 46), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 31, title_col)
		var sub_col := Color(1, 1, 1, 0.88) if lit and amount > 0.5 else Retro.c("muted")
		draw_string(Retro.body(600), Vector2(x + 34, 68), subtitle, HORIZONTAL_ALIGNMENT_LEFT, w - 80, 14, sub_col)
		if lit:
			Retro.draw_slashes(self, Vector2(x + w - lean - 58, h * 0.3), h * 0.4, Color(1, 1, 1, amount), 3, 5.0)
		if soon:
			var f := Retro.display(800)
			var tw := f.get_string_size("EM BREVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 16
			var chip := Rect2(x + w - lean - tw - 70, 14, tw, 22)
			draw_rect(chip, Retro.c("warn"))
			draw_string(f, chip.position + Vector2(8, 15), "EM BREVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
