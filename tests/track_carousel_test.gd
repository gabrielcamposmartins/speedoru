extends SceneTree
## Carrossel de pistas, peças por categoria e Roleta Dragão (sem janela): traçado de cada pista
## (pontos e extensão), ←/→ no carrossel do Jogar solo trocam a pista (dando a volta dentro da
## categoria), as abas Reais/Fantasia trocam as pistas do anel, o só leitura
## não muda nada, a Galeria separa as peças por lugar do carro, a silhueta sem placa de vídeo não
## trava, nome da roleta e sons gerados. Usa um perfil de teste.
##   godot --headless --path . -s res://tests/track_carousel_test.gd

## Extensão oficial (m): a linha central do CSV tem de ficar perto.
## Sky Aerobase e Atlantis Abyss (fantasia): a do traçado gerado por tools/build_<pista>.py.
const OFFICIAL := {"monza": 5793.0, "monaco": 3337.0, "suzuka": 5807.0, "las_vegas": 6201.0, "sky_aerobase": 3810.0,
	"atlantis_abyss": 4732.0}

var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame
	await process_frame


func _run() -> void:
	var profile := root.get_node("Profile") as PlayerProfile
	PlayerProfile.save_path = "user://test_carousel.cfg"
	profile.reset_profile()
	var track_before := RaceSettings.track
	for t in RaceSettings.TRACKS:
		var id: String = t["id"]
		var o := TrackCarousel.outline(id)
		var inside := true
		for p in o:
			inside = inside and absf(p.x) <= 1.001 and absf(p.y) <= 1.001
		_check(o.size() >= 50 and inside, "%s: traçado com %d pontos, normalizado" % [id, o.size()])
		var length := TrackCarousel.outline_length(id)
		_check(absf(length - OFFICIAL[id]) / OFFICIAL[id] < 0.06, "%s: %.0f m (oficial %.0f)" % [id, length, OFFICIAL[id]])
	# Jogar solo
	var scene := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 10:
		await process_frame
	var ui: MenuUI = scene.ui
	RaceSettings.track = "monza"
	ui.show_screen("solo")
	for i in 5:
		await process_frame
	var carousel := scene.find_child("TrackCarousel", true, false) as TrackCarousel
	_check(carousel != null and carousel.is_visible_in_tree(), "Jogar solo tem o carrossel de pistas")
	if carousel:
		carousel.grab_focus()
		await process_frame
		await _key(KEY_RIGHT)
		_check(RaceSettings.track == RaceSettings.TRACKS[1]["id"], "→ escolhe a próxima pista (%s)" % RaceSettings.track)
		_check(root.get_viewport().gui_get_focus_owner() == carousel, "o foco fica no carrossel")
		await _key(KEY_LEFT)
		await _key(KEY_LEFT)
		var reais := RaceSettings.tracks_in("real")
		_check(RaceSettings.track == RaceSettings.TRACKS[reais[-1]]["id"], "← antes da primeira dá a volta nas reais (%s)" % RaceSettings.track)
		await create_timer(TrackCarousel.SPIN_TIME + 0.2).timeout
		_check(is_equal_approx(carousel.pos, float(carousel._slot(carousel.selected))), "o anel para na pista escolhida")
		# Abas: Fantasia mostra só as pistas fantasia; voltar a Reais volta na última escolhida
		var tabs := scene.find_child("TrackTabs", true, false) as HBoxContainer
		_check(tabs != null and tabs.get_child_count() == RaceSettings.CATEGORIES.size(), "abas das categorias acima do carrossel")
		if tabs:
			var last_real := RaceSettings.track
			(tabs.get_node("Tab_fantasy") as Button).pressed.emit()
			await process_frame
			_check(carousel.category == "fantasy" and RaceSettings.category_of(RaceSettings.track) == "fantasy"
				and carousel.count() == RaceSettings.tracks_in("fantasy").size(), "aba Fantasia: %s (%d pista)" % [RaceSettings.track, carousel.count()])
			_check((tabs.get_node("Tab_fantasy") as Button).theme_type_variation == "PrimaryButton", "aba ativa em destaque")
			await _key(KEY_RIGHT)
			_check(RaceSettings.category_of(RaceSettings.track) == "fantasy", "→ fica nas pistas fantasia")
			(tabs.get_node("Tab_real") as Button).pressed.emit()
			await process_frame
			_check(carousel.category == "real" and RaceSettings.track == last_real, "aba Reais volta na última pista real (%s)" % RaceSettings.track)
	# Só leitura (sala, quem não é o anfitrião)
	var ro := TrackCarousel.new()
	ro.editable = false
	ro.selected = 2
	var changed := [false]
	ro.track_changed.connect(func(_i: int) -> void: changed[0] = true)
	root.add_child(ro)
	await process_frame
	var right := InputEventAction.new()
	right.action = &"ui_right"
	right.pressed = true
	ro._gui_input(right)
	_check(ro.selected == 2 and not changed[0] and ro.focus_mode == Control.FOCUS_NONE, "só leitura não muda a pista")
	# Continua o giro do carrossel anterior
	var next := TrackCarousel.new()
	next.selected = 3
	next.start_pos = 2.4
	root.add_child(next)
	await process_frame
	_check(next.pos > 2.3 and next.pos < 3.0, "o carrossel refeito continua o giro (%.2f)" % next.pos)
	ro.queue_free()
	next.queue_free()
	# Galeria: peças por lugar do carro
	var gallery := GalleryPanel.new()
	root.add_child(gallery)
	gallery.setup()
	gallery.type = "part"
	gallery._rebuild()
	await process_frame
	var heads := []
	for c in gallery._grid.get_children():
		if c is Label and not c.is_queued_for_deletion():
			heads.append((c as Label).text)
	var slots := []
	for id in ShopCatalog.items_of_type("part"):
		var slot: String = ShopCatalog.item(id)["slot"]
		if not slot in slots:
			slots.append(slot)
	_check(heads.size() == slots.size() and heads.size() >= 6, "Galeria: %d categorias de peças (%s…)" % [heads.size(), ", ".join(heads.slice(0, 2))])
	var tiles := gallery._grid.get_children().filter(func(c: Node) -> bool:
		return c is StudioPanel.OptionTile and not c.is_queued_for_deletion())
	_check(tiles.all(func(t: StudioPanel.OptionTile) -> bool: return t.part_slot != "" and t.part_variant != ""),
		"Galeria: cartões de peça com a silhueta (%d)" % tiles.size())
	gallery.queue_free()
	# Sem placa de vídeo: sem silhueta e sem travar
	_check(PartSilhouette.texture("nose", "pointed") == null and PartSilhouette._pending.is_empty(), "headless: sem silhueta, nada na fila")
	# Roleta e sons
	_check(ShopCatalog.ROULETTES["inferno"]["name"] == "Roleta Dragão", "a roleta se chama Roleta Dragão (id inferno)")
	_check(UiSounds.tick().data.size() > 1000 and UiSounds.prize(4).get_length() > UiSounds.prize(0).get_length()
		and UiSounds.discovery().get_length() > 1.0,
		"sons do giro: clique, arpejo (maior no lendário) e brilho do prêmio novo")
	RaceSettings.track = track_before
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.save_path))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
