class_name GaragePanel
extends PanelContainer
## Painel da garagem durante a corrida (Tab): o Estúdio (pintura e peças, só o que a conta tem),
## composto dos pneus, assistências, reparo, horário/ambiente da pista e desempenho do carro.

var car: F1Car
var _stats_label: Label

var _mood_connections: Array = []  # [Daylight, Callable]


func setup(target: F1Car) -> void:
	car = target
	_build()
	# Reconstrói ao abrir, para refletir mudanças feitas fora do painel.
	visibility_changed.connect(func() -> void:
		if visible:
			_build())
	Retro.events.changed.connect(_on_theme_changed)
	Retro.add_corners(self)
	var profile := get_node_or_null("/root/Profile") as PlayerProfile
	if profile:
		profile.changed.connect(_refresh_stats)


## Paleta trocada (na própria garagem): reconstrói depois do sinal do seletor terminar.
func _on_theme_changed() -> void:
	if visible:
		_build.call_deferred()


func _build() -> void:
	for c in _mood_connections:
		if is_instance_valid(c[0]) and (c[0] as Daylight).mood_changed.is_connected(c[1]):
			(c[0] as Daylight).mood_changed.disconnect(c[1])
	_mood_connections.clear()
	for child in get_children():
		child.queue_free()
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(340, 0)
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "GARAGEM"
	title.theme_type_variation = "RetroTitle"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Tab fecha · as mudanças valem na hora e ficam salvas"
	hint.theme_type_variation = "RetroMuted"
	box.add_child(hint)

	box.add_child(_section("Pneus"))
	var compound := OptionButton.new()
	for i in CarConfig.COMPOUND_NAMES.size():
		compound.add_item(CarConfig.COMPOUND_NAMES[i], i)
	compound.selected = car.config.tyre_compound
	compound.item_selected.connect(func(index: int) -> void:
		car.config.tyre_compound = index as CarConfig.TyreCompound
		_refresh_stats())
	box.add_child(_row("Composto", compound))

	box.add_child(_section("Assistências"))
	for assist in [["traction_control", "Controle de tração (T)"], ["brake_assist", "Assistência de freio"]]:
		var check := CheckButton.new()
		check.text = assist[1]
		check.button_pressed = car.get(assist[0])
		var property: String = assist[0]
		check.toggled.connect(func(on: bool) -> void: car.set(property, on))
		box.add_child(check)

	var repair := Button.new()
	repair.text = "Reparar carro (F)"
	repair.pressed.connect(car.repair)
	repair.disabled = not car.allow_quick_repair
	box.add_child(repair)

	var daylight := get_tree().get_first_node_in_group("daylight") as Daylight
	if daylight:
		box.add_child(_section("Pista"))
		for setting in [["time_of_day", "Horário (N)", DaylightPresets.TIME_NAMES], ["biome", "Ambiente (B)", DaylightPresets.BIOME_NAMES]]:
			var option := OptionButton.new()
			for name in setting[2]:
				option.add_item(name)
			var property: String = setting[0]
			option.selected = int(daylight.get(property))
			option.item_selected.connect(func(index: int) -> void: daylight.set(property, index))
			# O painel é reconstruído ao trocar peças/cores: guarda a conexão para desfazê-la (senão o
			# Daylight continuaria chamando um seletor já apagado).
			var sync := func(_t: int, _b: int) -> void:
				if is_instance_valid(option):
					option.selected = int(daylight.get(property))
			daylight.mood_changed.connect(sync)
			_mood_connections.append([daylight, sync])
			box.add_child(_row(setting[1], option))

	# Volumes, música, controles, tela e gráficos ficam nas Configurações
	var settings_button := Button.new()
	settings_button.text = "Configurações (F10): controles, tela, gráficos, áudio"
	settings_button.pressed.connect(func() -> void:
		var settings := get_node_or_null("/root/Settings") as GameSettings
		if settings:
			settings.open_menu())
	box.add_child(settings_button)

	# Pintura e peças: o Estúdio (só o que a conta tem; ganhe mais nas roletas da loja)
	var studio := StudioPanel.new()
	studio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(studio)
	studio.setup(car, true)

	box.add_child(_section("Desempenho"))
	_stats_label = Label.new()
	box.add_child(_stats_label)
	_refresh_stats()


func _refresh_stats() -> void:
	if _stats_label == null:
		return
	# Velocidade máxima teórica limitada pela potência: P = ½ ρ CdA v³
	var v := pow(car.max_power_kw * 1000.0 / (0.5 * F1Car.AIR_DENSITY * car.effective_drag_area), 1.0 / 3.0)
	var df_250 := 0.5 * F1Car.AIR_DENSITY * car.effective_downforce_area * pow(250.0 / 3.6, 2) / 9.8
	_stats_label.text = "Downforce (ClA): %.2f m²\nArrasto (CdA): %.2f m²\nBalanço dianteiro: %d%%\nDownforce a 250 km/h: %d kg\nVel. máx. teórica: %d km/h\nAderência do pneu: ×%.2f" % [
		car.effective_downforce_area, car.effective_drag_area, roundi(car.effective_balance * 100.0),
		roundi(df_250), roundi(v * 3.6), car.config.compound_grip()]


func _section(text: String) -> Control:
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_top", 10)
	holder.add_theme_constant_override("margin_bottom", 2)
	var tag := Retro.tag_label(text.to_upper(), 12)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.add_child(tag)
	return holder


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Retro.c("text_2"))
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row
