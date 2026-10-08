class_name MultiplayerPanel
extends VBoxContainer
## Tela de multiplayer do menu principal (regras do documento do Pokeru, adaptadas para corridas):
##
## * SALAS: corrida rápida (fila), criar sala Custom (nome, senha), lista de salas abertas; dentro da
##   sala: pilotos (pronto, anfitrião, nível, título, "+ amigo"), ajustes do anfitrião, convidar
##   amigo online, largar.
## * AMIGOS: seu código (ABC-234), adicionar por código, pedidos recebidos/enviados, lista com
##   presença (online / em corrida), perfil, chamar para o grupo ou para a sala, desfazer amizade.
## * GRUPO: até 4; só o líder convida e escolhe a partida (contra bots, fila ou Custom).
## * RANKING: Geral, Vitórias, Ganhos, Volta mais rápida (50 linhas + a sua).
## * PERFIL: nome, título, nível, "como você pilota", últimas corridas e conquistas.
## Sem conexão: mostra o endereço do servidor e o botão de conectar (o solo continua offline).

const TABS := [["rooms", "SALAS"], ["friends", "AMIGOS"], ["party", "GRUPO"], ["ranking", "RANKING"], ["profile", "PERFIL"]]
const DIFFICULTIES := ["Fácil", "Médio", "Difícil", "Mista"]

static var tab := "rooms"

var ui: MenuUI
var net: Node
var _header: VBoxContainer
var _tabs: HBoxContainer
var _content: VBoxContainer
var _scroll: ScrollContainer
var _friends := {}
var _rank_tab := "geral"
var _ranking := {}
var _profile_view := {}
var _confirm_remove := ""
var _rebuild_queued := false


func setup(p_ui: MenuUI) -> void:
	ui = p_ui
	net = get_node_or_null("/root/Net")
	add_theme_constant_override("separation", 10)
	_header = VBoxContainer.new()
	_header.add_theme_constant_override("separation", 4)
	add_child(_header)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)
	if net:
		net.message.connect(_on_message)
		net.connection_changed.connect(func(_o: bool) -> void: _queue_rebuild())
		net.account_changed.connect(_build_header)
	_rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	(func() -> void:
		_rebuild_queued = false
		if is_inside_tree():
			_rebuild()).call_deferred()


func _on_message(type: String, data: Dictionary) -> void:
	match type:
		"room", "party":
			if tab in ["rooms", "party", "friends"]:
				_queue_rebuild()
		"friends":
			_friends = data
			if tab in ["friends", "rooms", "party"]:
				_queue_rebuild()


func _rebuild() -> void:
	_build_header()
	for c in _tabs.get_children():
		c.queue_free()
	for c in _content.get_children():
		c.queue_free()
	if net == null or not net.online:
		_build_offline()
		return
	for t in TABS:
		var b := Button.new()
		b.text = t[1]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_font_override("font", Retro.display(700))
		b.add_theme_font_size_override("font_size", 12)
		if t[0] == "party" and not net.party.is_empty():
			b.text += " (%d)" % (net.party.get("members", []) as Array).size()
		if t[0] == "friends" and not (_friends.get("incoming", []) as Array).is_empty():
			b.text += " •"
		if t[0] == tab:
			b.theme_type_variation = "PrimaryButton"
		b.pressed.connect(func() -> void:
			tab = t[0]
			_profile_view = {}
			_rebuild())
		_tabs.add_child(b)
	var back := Button.new()
	back.text = "Voltar (Esc)"
	back.custom_minimum_size = Vector2(0, 36)
	back.pressed.connect(ui.show_screen.bind("home"))
	_tabs.add_child(back)
	match tab:
		"rooms":
			if net.room.is_empty():
				_build_lobby()
			else:
				_build_room()
		"friends":
			_build_friends()
		"party":
			_build_party()
		"ranking":
			_build_ranking()
		"profile":
			_build_profile()


# ---------------------------------------------------------------------------
# Peças
# ---------------------------------------------------------------------------
func _label(text: String, variation := "", size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	# Frases longas quebram linha (e ocupam a largura); rótulos curtos ficam numa linha só
	if text.length() > 48:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _button(text: String, action: Callable, primary := false, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 34)
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.pressed.connect(action)
	return b


func _row(parent: Container, sep := 10) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", sep)
	parent.add_child(r)
	return r


func _section(text: String) -> void:
	var l := _label(text, "RetroKicker")
	_content.add_child(l)


func _card() -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Retro.panel_style(10.0, 0.5))
	_content.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	return v


func _spacer(parent: Container) -> void:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(s)


## Pedido ao servidor; erro vira aviso na tela.
func _ask(type: String, data := {}) -> Dictionary:
	var r: Dictionary = await net.request(type, data)
	if not r.get("ok", true) and r.has("error"):
		ui.toast(str(r["error"]))
	return r


func _status_dot(online: bool, racing: bool) -> Label:
	var l := Label.new()
	l.text = "●"
	l.add_theme_color_override("font_color", Retro.c("warn") if racing else (Retro.c("good") if online else Retro.c("muted")))
	l.tooltip_text = "Em corrida" if racing else ("Online" if online else "Offline")
	return l


func _level_badge(level: int) -> Label:
	var l := Label.new()
	l.text = "NV %d" % level
	l.add_theme_font_override("font", Retro.display(800))
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Progression.level_color(level))
	return l


# ---------------------------------------------------------------------------
# Cabeçalho e offline
# ---------------------------------------------------------------------------
func _build_header() -> void:
	if _header == null:
		return
	for c in _header.get_children():
		c.queue_free()
	var top := _row(_header)
	var title := _label("MULTIPLAYER", "RetroTitle")
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(title)
	_spacer(top)
	if net and net.online and not net.account.is_empty():
		var acc: Dictionary = net.account
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -2)
		top.add_child(v)
		var name_row := _row(v, 8)
		name_row.alignment = BoxContainer.ALIGNMENT_END
		name_row.add_child(_level_badge(int(acc.get("level", 1))))
		var n := _label(str(acc.get("name", "")), "", 18)
		n.autowrap_mode = TextServer.AUTOWRAP_OFF
		n.add_theme_font_override("font", Retro.display(800))
		name_row.add_child(n)
		var code := _label("%s · %s" % [acc.get("code", ""), acc.get("title", "") if acc.get("title", "") != "" else "sem título"], "RetroMuted", 12)
		code.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		code.autowrap_mode = TextServer.AUTOWRAP_OFF
		v.add_child(code)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(220, 6)
		bar.max_value = maxi(int(acc.get("xp_next", 1)), 1)
		bar.value = int(acc.get("xp", 0))
		bar.tooltip_text = "%d / %d xp para o próximo nível" % [int(acc.get("xp", 0)), int(acc.get("xp_next", 1))]
		v.add_child(bar)
	else:
		top.add_child(_status_dot(false, false))
		top.add_child(_label("offline", "RetroMuted"))


func _build_offline() -> void:
	var card := _card()
	var connecting: bool = net != null and net._connecting
	card.add_child(_label("Conectando ao servidor…" if connecting else "Sem conexão com o servidor", "", 18))
	if net and net.last_error != "":
		card.add_child(_label(net.last_error, "", 14, Retro.c("bad")))
	card.add_child(_label("Salas, amigos, grupo, ranking e perfil precisam do servidor dedicado. A corrida solo funciona offline (com o perfil deste aparelho).", "RetroMuted", 13))
	var row := _row(card)
	row.add_child(_label("SERVIDOR", "RetroKicker"))
	var host := LineEdit.new()
	host.placeholder_text = "endereço:porta"
	host.text = "%s:%d" % [net.server_host, net.server_port] if net else ""
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(host)
	var go := _button("CONECTAR", func() -> void:
		var parts := host.text.strip_edges().split(":")
		if parts.is_empty() or parts[0] == "":
			return
		net.set_server(parts[0], int(parts[1]) if parts.size() > 1 else NetProtocol.DEFAULT_PORT)
		net.disconnect_from_server()
		net.connect_to_server()
		_queue_rebuild.call_deferred(), true, 150)
	row.add_child(go)
	var back := _button("Voltar (Esc)", ui.show_screen.bind("home"))
	_content.add_child(back)


# ---------------------------------------------------------------------------
# Salas
# ---------------------------------------------------------------------------
func _build_lobby() -> void:
	var quick := _card()
	var qr := _row(quick)
	var qv := VBoxContainer.new()
	qv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qr.add_child(qv)
	qv.add_child(_label("CORRIDA RÁPIDA", "", 18))
	qv.add_child(_label("Entra numa sala aberta (ou abre uma). Larga quando todos marcam pronto.", "RetroMuted", 13))
	qr.add_child(_button("ENTRAR NA FILA", func() -> void: _ask("room_quick"), true, 180))
	var create := _card()
	create.add_child(_label("CRIAR SALA CUSTOM", "", 18))
	var cr := _row(create)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Nome da sala"
	name_edit.max_length = 24
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cr.add_child(name_edit)
	var pass_edit := LineEdit.new()
	pass_edit.placeholder_text = "Senha (opcional)"
	pass_edit.secret = true
	pass_edit.max_length = 24
	pass_edit.custom_minimum_size = Vector2(170, 0)
	cr.add_child(pass_edit)
	cr.add_child(_button("CRIAR", func() -> void:
		var d := {"kind": "custom", "password": pass_edit.text}
		if name_edit.text.strip_edges() != "":
			d["name"] = name_edit.text
		_ask("room_create", d), true, 110))
	var head := _row(_content)
	head.add_child(_label("SALAS ABERTAS", "RetroKicker"))
	_spacer(head)
	head.add_child(_button("Atualizar", _queue_rebuild))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	_content.add_child(list)
	var r: Dictionary = await net.request("rooms")
	if not is_instance_valid(list):
		return
	var rooms: Array = r.get("rooms", [])
	if rooms.is_empty():
		list.add_child(_label("Nenhuma sala aberta. Crie uma ou entre na fila.", "RetroMuted"))
	for room: Dictionary in rooms:
		var row := _row(list)
		var st: Dictionary = room["settings"]
		var info := _label("%s%s  ·  %d/%d  ·  %d voltas  ·  %s" % ["🔒 " if room["locked"] else "", room["name"],
			(room["members"] as Array).size(), int(st["max"]), int(st["laps"]),
			("bots " + DIFFICULTIES[int(st["difficulty"])].to_lower()) if st["bots"] else "sem bots"])
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var pw := LineEdit.new()
		if room["locked"]:
			pw.placeholder_text = "senha"
			pw.secret = true
			pw.custom_minimum_size = Vector2(110, 0)
			row.add_child(pw)
		row.add_child(_button("ENTRAR", func() -> void: _ask("room_join", {"id": room["id"], "password": pw.text}), false, 100))


func _build_room() -> void:
	var room: Dictionary = net.room
	var me: String = net.account.get("id", "")
	var host: bool = room.get("host", "") == me
	var st: Dictionary = room.get("settings", {})
	var lobby: bool = room.get("state", "lobby") == "lobby"
	var card := _card()
	var top := _row(card)
	var kind_name: String = {"custom": "CUSTOM", "queue": "FILA", "bots": "CONTRA BOTS"}.get(room.get("kind", "custom"), "SALA")
	var tag := Retro.tag_label(kind_name, 11)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tag)
	var title := _label(("🔒 " if room.get("locked", false) else "") + str(room.get("name", "")), "", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_label("Em corrida" if not lobby else "Aguardando", "RetroMuted"))
	# Ajustes: anfitrião muda (menos na fila); os outros só veem
	var editable: bool = host and lobby and room.get("kind", "") != "queue"
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	card.add_child(grid)
	_setting(grid, "Pista", RaceSettings.TRACKS.map(func(t: Dictionary) -> String: return t["name"]),
		RaceSettings.track_index(str(st.get("track", "monza"))), editable,
		func(i: int) -> void: _ask("room_settings", {"track": RaceSettings.TRACKS[i]["id"]}))
	_setting(grid, "Voltas", NetProtocol.ROOM_LAPS.map(func(x: int) -> String: return str(x)), NetProtocol.ROOM_LAPS.find(int(st.get("laps", 5))), editable,
		func(i: int) -> void: _ask("room_settings", {"laps": NetProtocol.ROOM_LAPS[i]}))
	_setting(grid, "Bots", ["Com bots", "Sem bots"], 0 if st.get("bots", true) else 1, editable and room.get("kind", "") == "custom",
		func(i: int) -> void: _ask("room_settings", {"bots": i == 0}))
	_setting(grid, "Corredores", NetProtocol.ROOM_CARS.map(func(x: int) -> String: return "%d no grid" % x),
		maxi(NetProtocol.ROOM_CARS.find(int(st.get("cars", NetProtocol.MAX_ROOM_PLAYERS))), 0), editable and room.get("kind", "") == "custom",
		func(i: int) -> void: _ask("room_settings", {"cars": NetProtocol.ROOM_CARS[i]}))
	_setting(grid, "Dificuldade", DIFFICULTIES, int(st.get("difficulty", 1)), editable,
		func(i: int) -> void: _ask("room_settings", {"difficulty": i}))
	_setting(grid, "Classificatória", RaceSettings.QUALI_LAP_NAMES, int(st.get("quali_laps", 0)), editable,
		func(i: int) -> void: _ask("room_settings", {"quali_laps": i}))
	_setting(grid, "Tempo da classif.", RaceSettings.QUALI_TIME_NAMES, int(st.get("quali_time", 0)), editable,
		func(i: int) -> void: _ask("room_settings", {"quali_time": i}))
	_check(grid, "Colisão na classif.", bool(st.get("quali_collisions", true)), editable,
		func(on: bool) -> void: _ask("room_settings", {"quali_collisions": on}))
	_check(grid, "Infração anula volta", bool(st.get("quali_strict", true)), editable,
		func(on: bool) -> void: _ask("room_settings", {"quali_strict": on}))
	_setting(grid, "DRS", ["Livre", "Até 1 s do carro da frente"], int(st.get("drs", 0)), editable,
		func(i: int) -> void: _ask("room_settings", {"drs": i}))
	_setting(grid, "Horário", Array(DaylightPresets.TIME_NAMES), int(st.get("time_of_day", 0)), editable,
		func(i: int) -> void: _ask("room_settings", {"time_of_day": i}))
	_setting(grid, "Ambiente", Array(DaylightPresets.BIOME_NAMES), int(st.get("biome", 0)), editable,
		func(i: int) -> void: _ask("room_settings", {"biome": i}))
	if editable and room.get("kind", "") == "custom":
		var pw := LineEdit.new()
		pw.placeholder_text = "nova senha (vazio = aberta)"
		pw.secret = true
		pw.max_length = 24
		pw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(_label("SENHA", "RetroKicker"))
		grid.add_child(pw)
		grid.add_child(_button("Salvar senha", func() -> void: _ask("room_settings", {"password": pw.text})))
	# Pilotos
	var friend_ids := (_friends.get("friends", []) as Array).map(func(f: Dictionary) -> String: return f["id"])
	var outgoing := (_friends.get("outgoing", []) as Array).map(func(f: Dictionary) -> String: return f["id"])
	_section("PILOTOS (%d/%d)" % [(room.get("members", []) as Array).size(), int(st.get("max", NetProtocol.MAX_ROOM_PLAYERS))])
	for m: Dictionary in room.get("members", []):
		var row := _row(_content)
		var ready := _label("✔" if m["ready"] else "…", "", 16, Retro.c("good") if m["ready"] else Retro.c("muted"))
		ready.custom_minimum_size = Vector2(22, 0)
		row.add_child(ready)
		row.add_child(_level_badge(int(m["level"])))
		var n := _label(("★ " if m["host"] else "") + str(m["name"]) + ("  (você)" if m["id"] == me else ""), "", 16)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		if str(m.get("title", "")) != "":
			row.add_child(_label(str(m["title"]), "RetroMuted", 12, Progression.GRADE_COLORS[clampi(Progression.title_grade(m["title"]) - 1, 0, 4)]))
		# Pedir amizade na mesa
		if m["id"] != me and not m["id"] in friend_ids:
			if m["id"] in outgoing:
				row.add_child(_label("pedido enviado", "RetroMuted", 12))
			else:
				row.add_child(_button("+ amigo", func() -> void:
					var r := await _ask("friend_add_player", {"id": m["id"]})
					if r.get("ok", false):
						ui.toast("Vocês agora são amigos!" if r.get("friends_now", false) else "Pedido de amizade enviado")
						net.send_to_server("friends")))
	# Convidar amigo online (Custom)
	if room.get("kind", "") == "custom" and lobby:
		var online_friends := (_friends.get("friends", []) as Array).filter(func(f: Dictionary) -> bool:
			return f["online"] and not f["in_race"] and not (room.get("members", []) as Array).any(func(m: Dictionary) -> bool: return m["id"] == f["id"]))
		if not online_friends.is_empty():
			var inv := _row(_content)
			inv.add_child(_label("CONVIDAR", "RetroKicker"))
			var o := OptionButton.new()
			o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for f: Dictionary in online_friends:
				o.add_item(str(f["name"]))
			inv.add_child(o)
			inv.add_child(_button("Chamar", func() -> void:
				var r := await _ask("room_invite", {"id": online_friends[o.selected]["id"]})
				if r.get("ok", false):
					ui.toast("Convite enviado")))
	var actions := _row(_content, 12)
	var my_ready := false
	for m: Dictionary in room.get("members", []):
		if m["id"] == me:
			my_ready = m["ready"]
	if lobby:
		var rb := _button("✔ PRONTO" if my_ready else "MARCAR PRONTO", func() -> void: _ask("room_ready", {"ready": not my_ready}), not my_ready, 180)
		actions.add_child(rb)
		if host and room.get("kind", "") != "queue":
			actions.add_child(_button("LARGAR", func() -> void: _ask("room_start"), true, 160))
	else:
		actions.add_child(_label("A corrida desta sala está acontecendo.", "RetroMuted"))
	_spacer(actions)
	actions.add_child(_button("Sair da sala", func() -> void: _ask("room_leave")))
	if _friends.is_empty():
		net.send_to_server("friends")


## Ajuste liga/desliga da sala: caixa de marcar para o anfitrião, texto para os outros.
func _check(grid: GridContainer, label: String, value: bool, editable: bool, action: Callable) -> void:
	grid.add_child(_label(label.to_upper(), "RetroKicker"))
	if editable:
		var cb := CheckBox.new()
		cb.text = "Sim" if value else "Não"
		cb.button_pressed = value
		cb.toggled.connect(action)
		grid.add_child(cb)
	else:
		grid.add_child(_label("Sim" if value else "Não"))


func _setting(grid: GridContainer, label: String, items: Array, selected: int, editable: bool, action: Callable) -> void:
	grid.add_child(_label(label.to_upper(), "RetroKicker"))
	if editable:
		var o := OptionButton.new()
		for it in items:
			o.add_item(str(it))
		o.selected = maxi(selected, 0)
		o.item_selected.connect(action)
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(o)
	else:
		grid.add_child(_label(str(items[clampi(selected, 0, items.size() - 1)]) if not items.is_empty() else "-"))


# ---------------------------------------------------------------------------
# Amigos
# ---------------------------------------------------------------------------
func _build_friends() -> void:
	var mine := _card()
	var r1 := _row(mine)
	r1.add_child(_label("SEU CÓDIGO", "RetroKicker"))
	var code := _label(str(net.account.get("code", "")), "", 26)
	code.add_theme_font_override("font", Retro.display(900))
	code.add_theme_color_override("font_color", Retro.c("accent_2"))
	r1.add_child(code)
	_spacer(r1)
	r1.add_child(_button("Copiar", func() -> void:
		DisplayServer.clipboard_set(str(net.account.get("code", "")))
		ui.toast("Código copiado")))
	var r2 := _row(mine)
	var edit := LineEdit.new()
	edit.placeholder_text = "Código do amigo (ABC-234)"
	edit.max_length = 9
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(edit)
	r2.add_child(_button("ADICIONAR", func() -> void:
		var r := await _ask("friend_add", {"code": edit.text})
		if r.get("ok", false):
			ui.toast("Vocês agora são amigos!" if r.get("friends_now", false) else "Pedido enviado")
			edit.text = "", true, 140))
	mine.add_child(_label("Até %d amigos. Pedido cruzado vira amizade na hora." % NetProtocol.MAX_FRIENDS, "RetroMuted", 12))
	if _friends.is_empty():
		var r: Dictionary = await net.request("friends")
		if not is_inside_tree():
			return
		_friends = r
	var incoming: Array = _friends.get("incoming", [])
	if not incoming.is_empty():
		_section("PEDIDOS RECEBIDOS")
		for f: Dictionary in incoming:
			var row := _row(_content)
			row.add_child(_level_badge(int(f["level"])))
			var n := _label(str(f["name"]), "", 16)
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(n)
			row.add_child(_button("Aceitar", func() -> void: _ask("friend_accept", {"id": f["id"]}), true))
			row.add_child(_button("Recusar", func() -> void: _ask("friend_decline", {"id": f["id"]})))
	var outgoing: Array = _friends.get("outgoing", [])
	if not outgoing.is_empty():
		_section("PEDIDOS ENVIADOS")
		for f: Dictionary in outgoing:
			var row := _row(_content)
			var n := _label("%s  ·  %s" % [f["name"], f["code"]], "RetroMuted")
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(n)
			row.add_child(_button("Cancelar", func() -> void: _ask("friend_decline", {"id": f["id"]})))
	var friends: Array = _friends.get("friends", []).duplicate()
	# Online primeiro, depois por nome
	friends.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["online"] != b["online"]:
			return a["online"]
		return str(a["name"]) < str(b["name"]))
	_section("AMIGOS (%d/%d)" % [friends.size(), NetProtocol.MAX_FRIENDS])
	if friends.is_empty():
		_content.add_child(_label("Passe seu código para os amigos ou adicione alguém que correu com você na sala.", "RetroMuted"))
	var me: String = net.account.get("id", "")
	var party: Dictionary = net.party
	var leader: bool = party.is_empty() or party.get("leader", "") == me
	var in_custom: bool = not net.room.is_empty() and net.room.get("kind", "") == "custom" and net.room.get("state", "") == "lobby"
	for f: Dictionary in friends:
		var row := _row(_content)
		row.add_child(_status_dot(f["online"], f["in_race"]))
		row.add_child(_level_badge(int(f["level"])))
		var n := _label(str(f["name"]) + ("  ·  " + str(f["title"]) if str(f.get("title", "")) != "" else ""), "", 15)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		row.add_child(_button("Perfil", func() -> void: _open_profile(f["id"])))
		var in_party: bool = (party.get("members", []) as Array).any(func(m: Dictionary) -> bool: return m["id"] == f["id"])
		if f["online"] and leader and not in_party:
			row.add_child(_button("Grupo", func() -> void:
				var r := await _ask("party_invite", {"id": f["id"]})
				if r.get("ok", false):
					ui.toast("Convite para o grupo enviado")))
		if f["online"] and in_custom:
			row.add_child(_button("Sala", func() -> void:
				var r := await _ask("room_invite", {"id": f["id"]})
				if r.get("ok", false):
					ui.toast("Convite para a sala enviado")))
		var rm := _button("Confirmar?" if _confirm_remove == f["id"] else "✕", func() -> void:
			if _confirm_remove == f["id"]:
				_confirm_remove = ""
				_ask("friend_remove", {"id": f["id"]})
			else:
				_confirm_remove = f["id"]
				_queue_rebuild())
		rm.tooltip_text = "Desfazer amizade"
		row.add_child(rm)


# ---------------------------------------------------------------------------
# Grupo
# ---------------------------------------------------------------------------
func _build_party() -> void:
	var party: Dictionary = net.party
	var me: String = net.account.get("id", "")
	if party.is_empty():
		var card := _card()
		card.add_child(_label("Sem grupo", "", 18))
		card.add_child(_label("Chame amigos online pela aba AMIGOS (botão Grupo). Até %d pessoas; quem chama é o líder e escolhe a partida." % NetProtocol.MAX_PARTY, "RetroMuted"))
		return
	var leader: bool = party.get("leader", "") == me
	_section("GRUPO (%d/%d)" % [(party.get("members", []) as Array).size(), NetProtocol.MAX_PARTY])
	for m: Dictionary in party.get("members", []):
		var row := _row(_content)
		row.add_child(_level_badge(int(m["level"])))
		var n := _label(("★ " if m["leader"] else "") + str(m["name"]) + ("  (você)" if m["id"] == me else ""), "", 16)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
	if leader:
		_section("JOGAR COM O GRUPO")
		var modes := [
			["bots", "CONTRA BOTS", "Uma sala só do grupo, com bots completando o grid."],
			["queue", "FILA", "O grupo entra junto numa corrida rápida."],
			["custom", "CUSTOM", "O grupo vai para a sua sala Custom (ou uma nova)."],
		]
		for md in modes:
			var row := _row(_content)
			var v := VBoxContainer.new()
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(v)
			v.add_child(_label(md[1], "", 16))
			v.add_child(_label(md[2], "RetroMuted", 12))
			row.add_child(_button("Ir", func() -> void:
				var r := await _ask("party_start", {"kind": md[0]})
				if r.get("ok", false):
					tab = "rooms"
					_queue_rebuild(), true, 90))
	else:
		_content.add_child(_label("O líder escolhe a partida; você entra junto.", "RetroMuted"))
	var leave := _row(_content)
	_spacer(leave)
	leave.add_child(_button("Sair do grupo", func() -> void: _ask("party_leave")))


# ---------------------------------------------------------------------------
# Ranking
# ---------------------------------------------------------------------------
func _build_ranking() -> void:
	var sub := _row(_content, 6)
	for t in Ranking.TABS:
		var b := _button(t[1], func() -> void:
			_rank_tab = t[0]
			_queue_rebuild())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if t[0] == _rank_tab:
			b.theme_type_variation = "PrimaryButton"
		sub.add_child(b)
	var hint := {"geral": "Cada aba vale até 1.000 pontos: a fração do líder da aba.", "wins": "Vitórias em qualquer corrida.",
		"earned": "Créditos ganhos desde sempre.", "best_lap": "Recorde em Monza (menor é melhor)."}
	_content.add_child(_label(hint.get(_rank_tab, ""), "RetroMuted", 12))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	_content.add_child(list)
	if _ranking.is_empty():
		var r: Dictionary = await net.request("ranking")
		if not is_instance_valid(list):
			return
		_ranking = r
		# O servidor guarda por 15 s; pede de novo da próxima vez que abrir a aba
		get_tree().create_timer(NetProtocol.RANKING_CACHE_S).timeout.connect(func() -> void: _ranking = {})
	var view: Dictionary = _ranking.get("tabs", {}).get(_rank_tab, {})
	var rows: Array = view.get("rows", [])
	var me: String = net.account.get("id", "")
	if rows.is_empty():
		list.add_child(_label("Ninguém pontuou ainda nesta aba.", "RetroMuted"))
	for row: Dictionary in rows:
		_rank_row(list, row, row["id"] == me)
	if view.get("you") != null:
		list.add_child(_label("···", "RetroMuted"))
		_rank_row(list, view["you"], true)


func _rank_row(list: VBoxContainer, row: Dictionary, mine: bool) -> void:
	var r := _row(list)
	var pos := _label("%d" % int(row["pos"]), "", 16)
	pos.custom_minimum_size = Vector2(44, 0)
	pos.add_theme_font_override("font", Retro.display(800))
	if int(row["pos"]) <= 3:
		pos.add_theme_color_override("font_color", [Color("ffd319"), Color("d6dbe4"), Color("e08a4a")][int(row["pos"]) - 1])
	r.add_child(pos)
	var n := _label(str(row["name"]) + ("  (você)" if mine else ""), "", 15, Retro.c("accent_2") if mine else Color(0, 0, 0, 0))
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(n)
	var v := float(row["value"])
	var text := ""
	match _rank_tab:
		"best_lap":
			text = RaceManager.format_time(v)
		"earned":
			text = "%s %s" % [PlayerProfile.format_credits(int(v)), ShopCatalog.CURRENCY]
		"wins":
			text = "%d (%d corridas)" % [int(v), int(row.get("detail", {}).get("races", 0))]
		_:
			text = "%d pts" % int(v)
	var val := _label(text, "", 15)
	val.add_theme_font_override("font", Retro.display(700))
	r.add_child(val)


# ---------------------------------------------------------------------------
# Perfil
# ---------------------------------------------------------------------------
func _open_profile(id: String) -> void:
	var r := await _ask("profile_of", {"id": id})
	if r.get("ok", true) == false:
		return
	_profile_view = r
	tab = "profile"
	_rebuild()


func _build_profile() -> void:
	var p := _profile_view
	if p.is_empty():
		var r: Dictionary = await net.request("profile_of")
		if not is_inside_tree():
			return
		if r.get("ok", true) == false:
			_content.add_child(_label(str(r.get("error", "")), "", 14, Retro.c("bad")))
			return
		p = r
	var own: bool = p.get("own", false)
	if not own:
		_content.add_child(_button("← Meu perfil", func() -> void:
			_profile_view = {}
			_rebuild()))
	var card := _card()
	var top := _row(card)
	top.add_child(_level_badge(int(p.get("level", 1))))
	var n := _label(str(p.get("name", "")), "", 22)
	n.add_theme_font_override("font", Retro.display(800))
	top.add_child(n)
	top.add_child(_status_dot(p.get("online", false), p.get("in_race", false)))
	_spacer(top)
	top.add_child(_label(str(p.get("code", "")), "RetroMuted"))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.max_value = maxi(int(p.get("xp_next", 1)), 1)
	bar.value = int(p.get("xp", 0))
	card.add_child(bar)
	var facts := "Melhor volta: %s" % RaceManager.format_time(float(p.get("best_lap", 0.0)))
	if p.has("earned"):
		facts += "  ·  Ganhos: %s %s (só você vê)" % [PlayerProfile.format_credits(int(p["earned"])), ShopCatalog.CURRENCY]
	card.add_child(_label(facts, "RetroMuted", 13))
	if own:
		var edit_row := _row(card)
		edit_row.add_child(_label("NOME", "RetroKicker"))
		var name_edit := LineEdit.new()
		name_edit.text = str(p.get("name", ""))
		name_edit.max_length = NetProtocol.NAME_MAX
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit_row.add_child(name_edit)
		edit_row.add_child(_button("Salvar", func() -> void:
			var r := await _ask("set_name", {"name": name_edit.text})
			if r.get("ok", false):
				net.set_local_name(str(r["name"]))
				ui.toast("Nome salvo")
				_queue_rebuild()))
		var title_row := _row(card)
		title_row.add_child(_label("TÍTULO", "RetroKicker"))
		var o := OptionButton.new()
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		o.add_item("(nenhum)")
		var titles: Array = Array(net.account.get("titles", PackedStringArray()))
		for t in titles:
			o.add_item(str(t))
			if str(t) == str(p.get("title", "")):
				o.selected = o.item_count - 1
		o.item_selected.connect(func(i: int) -> void:
			_ask("set_title", {"title": "" if i == 0 else str(titles[i - 1])}))
		title_row.add_child(o)
	elif str(p.get("title", "")) != "":
		card.add_child(_label(str(p["title"]), "", 14, Progression.GRADE_COLORS[clampi(Progression.title_grade(p["title"]) - 1, 0, 4)]))
	# Como você pilota (últimas 10 corridas; 0,5 sem histórico)
	_section("COMO %s PILOTA" % ("VOCÊ" if own else str(p.get("name", "")).to_upper()))
	var traits: Array = p.get("traits", [])
	var tg := GridContainer.new()
	tg.columns = 2
	tg.add_theme_constant_override("h_separation", 12)
	_content.add_child(tg)
	for k in mini(traits.size(), Progression.TRAITS.size()):
		tg.add_child(_label(Progression.TRAITS[k], "", 13))
		var tb := ProgressBar.new()
		tb.show_percentage = false
		tb.max_value = 1.0
		tb.step = 0.01
		tb.value = float(traits[k])
		tb.custom_minimum_size = Vector2(0, 10)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tg.add_child(tb)
	# Últimas corridas
	_section("ÚLTIMAS CORRIDAS")
	var history: Array = p.get("history", [])
	if history.is_empty():
		_content.add_child(_label("Nenhuma corrida ainda.", "RetroMuted"))
	for h: Dictionary in history:
		var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		var when := Time.get_datetime_string_from_unix_time(int(h.get("t", 0)) + bias).replace("T", " ").substr(0, 16)
		var result := "%dº de %d" % [int(h.get("pos", 0)), int(h.get("total", 0))] if h.get("finished", false) else "não terminou"
		var line := "%s  ·  %s  ·  %s  ·  %d voltas  ·  melhor %s%s" % [when, "online" if h.get("kind", "") == "online" else "solo", result,
			int(h.get("laps", 0)), RaceManager.format_time(float(h.get("best_lap", 0.0))),
			("  ·  +%s" % PlayerProfile.format_credits(int(h["credits"]))) if own and h.has("credits") else ""]
		_content.add_child(_label(line, "", 13))
	# Conquistas
	var ach: Array = p.get("achievements", [])
	_section("CONQUISTAS (%d/%d)" % [ach.filter(func(a: Dictionary) -> bool: return a["done"]).size(), ach.size()])
	var ag := GridContainer.new()
	ag.columns = 3
	ag.add_theme_constant_override("h_separation", 8)
	ag.add_theme_constant_override("v_separation", 8)
	_content.add_child(ag)
	for a: Dictionary in ach:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", Retro.panel_style(8.0, 0.35 if not a["done"] else 0.7))
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ag.add_child(panel)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		panel.add_child(v)
		var color: Color = Progression.GRADE_COLORS[clampi(int(a["grade"]) - 1, 0, 4)]
		v.add_child(_label(str(a["name"]), "", 13, color if a["done"] else Retro.c("muted")))
		v.add_child(_label("%s / %s" % [_short(int(a["value"])), _short(int(a["goal"]))] if not a["done"] else "Título: " + str(a["title"]), "RetroMuted", 11))
		panel.tooltip_text = "%s — meta %d. Libera o título \"%s\"." % [a["name"], int(a["goal"]), a["title"]]


static func _short(n: int) -> String:
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)
