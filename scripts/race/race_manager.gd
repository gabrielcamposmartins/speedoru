class_name RaceManager
extends Node
## Modo de jogo: corrida (N voltas, pit obrigatório, bots) ou treino livre.
##
## * Grid e largada: carros no grid, luzes de largada; bots largam com tempo de reação da
##   dificuldade; o jogador que se mexer antes de as luzes apagarem leva penalidade.
## * Voltas: conta as passagens pela linha, tempos de volta, volta mais rápida, intervalos
##   (por marcas de progresso a cada CHECKPOINT m), posições e chegada.
## * Boxes: detecta a pista dos boxes, velocidade máxima de 80 km/h, pit stop no box da equipe
##   (pneus novos com o composto escolhido com 1/2/3), equipe de mecânicos em volta do carro.
## * Penalidades (todas registradas em RaceEntry.penalties e mostradas no HUD):
##   limites de pista (3 avisos, depois +5 s), cortar a pista e ganhar vantagem (+5 s),
##   colisão causada (+5/+10 s), largada queimada (+10 s), excesso de velocidade nos boxes
##   (+5 s), pit stop obrigatório não cumprido (desclassificação).
## O HUD da corrida (RaceModeHud) lê tudo daqui.
##
## Rede (servidor autoritativo): no servidor dedicado (net = SERVER) a corrida roda inteira aqui,
## com os carros dos humanos comandados pelas entradas que chegam pela rede (RaceSession); no
## cliente (net = CLIENT) nada é simulado: os carros são marionetes (NetRaceClient) e o estado da
## prova (voltas, posições, penalidades, bandeiras) vem do servidor.

signal infraction(entry: RaceEntry, title: String, detail: String, is_penalty: bool)
signal race_finished
signal state_changed(state: int)
## Rede (servidor): grid montado (o RaceSession manda a lista de carros e espera os clientes).
signal net_grid_ready
## Rede (servidor): acontecimento para mandar aos clientes (luzes, peça arrancada…).
signal net_event(data: Dictionary)

enum Net { OFF, SERVER, CLIENT }

enum State { MENU, PRACTICE, GRID, RACING, FINISHED, QUALIFYING }

const CHECKPOINT := 25.0
## Duração sorteada de cada pit stop (s), sem contar conserto.
const PIT_STOP_MIN := 2.0
const PIT_STOP_MAX := 4.0
const PIT_LIMIT := 80.0 / 3.6
const DRIVERS := [
	["Hikari Sato", "SAT"], ["Ren Kuroda", "KUR"], ["Mio Takahashi", "TAK"], ["Luna Rossi", "ROS"],
	["Theo Bianchi", "BIA"], ["Yuki Morita", "MOR"], ["Diego Alves", "ALV"], ["Emma Laurent", "LAU"],
	["Kai Müller", "MUL"], ["Aiko Fujimoto", "FUJ"], ["Nina Petrova", "PET"], ["Leo Costa", "COS"],
	["Hana Kimura", "KIM"], ["Max Weber", "WEB"], ["Rina Sasaki", "SAS"], ["Oscar Lind", "LIN"],
	["Yui Ogawa", "OGA"], ["Sora Ishikawa", "ISH"], ["Kenji Nakamura", "NAK"],
]

@export var car_scene: PackedScene = preload("res://scenes/car/f1_car.tscn")

var state := State.MENU
var track: RaceTrack
var player: F1Car
var entries: Array[RaceEntry] = []
var player_entry: RaceEntry
var line: RacingLine
var race_time := 0.0
var laps := 10
var fastest_lap := 0.0
var fastest_entry: RaceEntry
var leader_finished := false
## Composto escolhido para o próximo pit stop do jogador.
var pit_compound := CarConfig.TyreCompound.HARD
var player_pit_timer := 0.0
var hud: RaceModeHud

var _profiles := {}
var _grid_positions := {}
var _contact_cooldown := {}
var _crew: MultiMeshInstance3D
var _crew_cars := {}
var _wrong_way_cooldown := 0.0
var _box_marker: MeshInstance3D
## Pares de bots sem colisão entre si na largada (até a saída da 1ª chicane).
var _ghost_pairs: Array = []
const GHOST_UNTIL := 950.0
## Pares de bots sem colisão entre si nos boxes (chave "idA_idB" -> [a, b]).
var _pit_ghosts := {}
var _loading_base := -1.0
## Linha ideal (setas no chão) do jogador.
var line_guide: RacingLineGuide
## Bandeira amarela, safety car e regras sob amarela.
var control: RaceControl
## Créditos pagos ao jogador nesta corrida (-1 = ainda não pagou).
var player_reward := -1

## Rede: OFF (solo), SERVER (servidor dedicado) ou CLIENT (espelho do servidor).
var net := Net.OFF
## Regra do DRS: 0 = livre, 1 = só a até DRS_GAP s do carro da frente.
var drs_rule := 0
## Classificatória em andamento (ou a última que rodou).
var quali: Qualifying
## Rede (cliente): race_time em que o tempo da classificatória acaba (0 = sem limite).
var quali_end := 0.0
## Rede (cliente): votação para recomeçar ({yes, needed, until, voters}; vazio = nenhuma) e o meu voto.
var restart_vote := {}
var my_restart_vote := false
const DRS_GAP := 1.0
## Configuração da corrida em rede, definida antes de a cena entrar na árvore. Servidor:
## {laps, difficulty, bots, players: [{id, name, profile}]}; cliente: {me, roster, settings}.
var net_setup := {}
## Cliente: configuração da próxima corrida em rede (o Net guarda aqui antes de trocar de cena).
static var client_setup := {}
## Há uma corrida em rede aberta neste cliente (menus não pausam o jogo).
static var online_race := false
## Servidor: entries dos humanos por id de conta.
var humans := {}
## Todos os carros na ordem fixa (índice da rede), ao contrário de entries (ordenada por posição).
var roster: Array[RaceEntry] = []
var net_client: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var scene := get_parent()
	track = scene.get_node("Track") as RaceTrack
	player = scene.get_node("F1Car") as F1Car
	if not net_setup.is_empty():
		net = Net.SERVER
	elif not client_setup.is_empty():
		net = Net.CLIENT
		net_setup = client_setup
		client_setup = {}
	online_race = net == Net.CLIENT
	match net:
		Net.OFF:
			drs_rule = RaceSettings.drs_rule
		Net.SERVER:
			drs_rule = int(net_setup.get("drs", 0))
		Net.CLIENT:
			drs_rule = int((net_setup.get("settings", {}) as Dictionary).get("drs", 0))
	# O carro do jogador corre com o que está equipado na garagem (na rede, com o que o servidor manda)
	var profile := get_node_or_null("/root/Profile") as PlayerProfile
	if profile and player.config and net == Net.OFF:
		profile.apply_to_config(player.config)
		profile.apply_setup(player)
	# Horário e ambiente escolhidos antes da corrida
	var daylight := get_tree().get_first_node_in_group("daylight") as Daylight
	if daylight and net != Net.SERVER:
		daylight.time_of_day = RaceSettings.time_of_day as DaylightPresets.TimeOfDay
		daylight.biome = RaceSettings.biome as DaylightPresets.Biome
	if not track.is_built:
		await track.built
	if net == Net.SERVER:
		_build_net_grid.call_deferred()
		return
	hud = RaceModeHud.new()
	hud.name = "RaceHud"
	hud.manager = self
	scene.add_child.call_deferred(hud)
	# Vento do vácuo (pista visual) no carro seguido pela câmera
	var fx := SlipstreamFx.new()
	fx.name = "SlipstreamFx"
	fx.car = player
	scene.add_child.call_deferred(fx)
	if net == Net.CLIENT:
		_start_net_client.call_deferred()
		return
	if RaceSettings.skip_menu:
		RaceSettings.skip_menu = false
		_start.call_deferred()
	else:
		state = State.MENU
		get_tree().paused = true
		state_changed.emit.call_deferred(state)
		LoadingScreen.done()


func _exit_tree() -> void:
	if net == Net.CLIENT:
		online_race = false


## Chamado pelo menu (ou direto ao recomeçar).
func _start() -> void:
	get_tree().paused = false
	laps = RaceSettings.laps
	if RaceSettings.mode == RaceSettings.Mode.RACE:
		# Montar o grid (linha ideal, 9 carros) leva um tempo: mostra a tela de carregamento
		# (ou continua a da cena, se ainda estiver aberta), com a árvore pausada até o fim
		if not LoadingScreen.is_loading():
			LoadingScreen.start("Preparando a corrida")
		get_tree().paused = LoadingScreen.is_loading()
		await _loading_step(0.0, "Linha ideal e estratégia")
	line = RacingLine.build(track, track.layout.raceline)
	if RaceSettings.mode == RaceSettings.Mode.PRACTICE:
		_start_practice()
		LoadingScreen.done()
	else:
		await _start_race()


const MAIN_MENU := "res://scenes/menu/main_menu.tscn"


## skip_menu = true: corre de novo com as mesmas opções; false: volta ao menu principal (garagem).
func restart(skip_menu: bool) -> void:
	if net == Net.CLIENT:
		# Rede: sai da corrida (se ainda está correndo, abandona) e volta para a sala
		var n := get_node_or_null("/root/Net")
		if n and state != State.FINISHED:
			n.send_to_server("race_cmd", {"cmd": "quit"})
		online_race = false
		skip_menu = false
		RaceSettings.return_to = "multiplayer"
	RaceSettings.skip_menu = skip_menu
	get_tree().paused = false
	var path := get_tree().current_scene.scene_file_path if skip_menu else MAIN_MENU
	var loading := get_node_or_null("/root/Loading") as LoadingScreen
	if loading and not path.is_empty():
		loading.change_scene(path)
	elif skip_menu:
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(path)


## Avança a tela de carregamento (se aberta) até [param fraction] do que falta e espera um
## quadro ser desenhado, para o texto/porcentagem aparecerem antes do próximo passo pesado.
func _loading_step(fraction: float, text: String) -> void:
	if not LoadingScreen.is_loading():
		return
	var base := _loading_base if _loading_base >= 0.0 else LoadingScreen.instance.progress
	if _loading_base < 0.0:
		_loading_base = base
	LoadingScreen.report_progress(lerpf(base, 1.0, fraction), text)
	await RenderingServer.frame_post_draw


# ---------------------------------------------------------------------------
# Montagem
# ---------------------------------------------------------------------------
## Setas da linha ideal à frente do jogador (perfil de velocidade do bot difícil).
func _make_line_guide() -> void:
	if line_guide or line == null:
		return
	line_guide = RacingLineGuide.new()
	line_guide.name = "RacingLineGuide"
	get_parent().add_child(line_guide)
	line_guide.setup(player, line, _profile(BotDriver.Difficulty.HARD))
	var settings := get_node_or_null("/root/Settings") as GameSettings
	if settings:
		line_guide.mode = int(settings.get_value("gameplay", "racing_line"))
		settings.changed.connect(_on_settings_changed)


func _on_settings_changed(section: String, _key: String) -> void:
	if section == "gameplay" and line_guide:
		line_guide.mode = int((get_node("/root/Settings") as GameSettings).get_value("gameplay", "racing_line"))


func _start_practice() -> void:
	state = State.PRACTICE
	player_entry = _make_entry(player, true, 0, 0)
	_make_line_guide()
	_make_box_marker()
	player.global_transform = track.get_grid_transform(0)
	player.reset_physics_interpolation()
	player_entry.crossings = 0
	_init_position(player_entry)
	if track.start_lights:
		track.start_lights.run_sequence()
	state_changed.emit(state)


func _start_race() -> void:
	state = State.GRID
	# Corrida: horário/ambiente ficam como escolhidos (N/B só no treino)
	var daylight := get_tree().get_first_node_in_group("daylight") as Daylight
	if daylight:
		daylight.allow_cycle = false
	player.allow_quick_repair = false
	var count := RaceSettings.opponents + 1
	var player_slot := 0
	match RaceSettings.grid:
		RaceSettings.Grid.MIDDLE:
			player_slot = count / 2
		RaceSettings.Grid.BACK:
			player_slot = count - 1
	# Bots: mais rápidos na frente (dificuldade mista)
	var bot_levels: Array[int] = []
	for k in RaceSettings.opponents:
		var level := RaceSettings.difficulty
		if level == 3:
			level = [BotDriver.Difficulty.HARD, BotDriver.Difficulty.MEDIUM, BotDriver.Difficulty.EASY][k * 3 / maxi(RaceSettings.opponents, 1)]
		bot_levels.append(level)
	bot_levels.sort_custom(func(a: int, b: int) -> bool: return a > b)
	var names := DRIVERS.duplicate()
	names.shuffle()
	var bot_index := 0
	for slot in count:
		if slot == player_slot:
			player_entry = _make_entry(player, true, slot, 0)
			continue
		bot_index += 1
		await _loading_step(0.1 + 0.85 * bot_index / maxf(RaceSettings.opponents, 1.0), "Carros no grid %d/%d" % [bot_index, RaceSettings.opponents])
		var level: int = bot_levels[bot_index - 1]
		var car := _spawn_bot(bot_index, names[bot_index - 1], level)
		var entry := _make_entry(car, false, slot, bot_index)
		entry.name = names[bot_index - 1][0]
		entry.code = names[bot_index - 1][1]
		entry.difficulty = level
		var bot := BotDriver.new()
		bot.name = "Bot"
		car.add_child(bot)
		bot.setup(car, track, line, _profile(level), level, entry, self)
		bot.pit_lap = randi_range(maxi(laps / 3, 2), maxi(laps - 2, 2))
		bot.pit_compound = CarConfig.TyreCompound.HARD if randf() < 0.6 else CarConfig.TyreCompound.MEDIUM
		entry.bot = bot
	_make_box_marker()
	_make_line_guide()
	control = RaceControl.new()
	control.name = "RaceControl"
	add_child(control)
	control.setup(self)
	# Largada: bots atravessam uns aos outros até a saída da 1ª chicane (evita engavetamentos);
	# o jogador colide com todos normalmente.
	for a in entries:
		for b in entries:
			if a.is_player or b.is_player or a.get_instance_id() >= b.get_instance_id():
				continue
			a.car.add_collision_exception_with(b.car)
			_ghost_pairs.append([a, b])
	if RaceSettings.quali_laps > 0:
		if LoadingScreen.is_loading():
			await _loading_step(1.0, "Pronto")
			get_tree().paused = false
			LoadingScreen.done()
		await _run_qualifying(RaceSettings.quali_lap_count(RaceSettings.quali_laps), RaceSettings.quali_collisions,
			RaceSettings.quali_seconds(RaceSettings.quali_laps, RaceSettings.quali_time), RaceSettings.quali_strict)
	for entry in entries:
		entry.car.global_transform = track.get_grid_transform(entry.grid_slot)
		entry.car.linear_velocity = Vector3.ZERO
		entry.car.angular_velocity = Vector3.ZERO
		entry.car.reset_physics_interpolation()
		entry.car.hold = not entry.is_player
		_init_position(entry)
	if LoadingScreen.is_loading():
		await _loading_step(1.0, "Pronto")
		get_tree().paused = false
		LoadingScreen.done()
	state_changed.emit(state)
	# Apresentação dos carros e órbita no seu (o carro fica parado até ela acabar)
	if IntroDirector.enabled(get_tree()):
		player_entry.car.hold = true
		await _play_intro()
		player_entry.car.hold = false
		await get_tree().create_timer(1.0, false).timeout
	else:
		await get_tree().create_timer(2.5, false).timeout
	for entry in entries:
		_grid_positions[entry] = entry.car.global_position
	if track.start_lights:
		track.start_lights.lights_out.connect(_on_lights_out, CONNECT_ONE_SHOT)
		track.start_lights.run_sequence()
	else:
		_on_lights_out()


func _make_entry(car: F1Car, is_player: bool, slot: int, garage: int) -> RaceEntry:
	var e := RaceEntry.new()
	e.index = roster.size()
	roster.append(e)
	e.car = car
	e.is_player = is_player
	e.grid_slot = slot
	e.garage = garage
	if is_player:
		e.name = "Você"
		var n := car.config.car_name if car.config else "VOC"
		e.code = n.substr(0, 3).to_upper() if n.length() >= 3 else "VOC"
		e.color = car.config.primary_color if car.config else Color.RED
	else:
		e.color = track.layout.team_colors[(garage / 2) % track.layout.team_colors.size()]
	e.compounds_used.append(car.config.tyre_compound if car.config else 1)
	car.car_contact.connect(_on_car_contact.bind(e))
	entries.append(e)
	return e


func _spawn_bot(index: int, driver: Array, level: int) -> F1Car:
	var car := car_scene.instantiate() as F1Car
	car.name = "Bot%d" % index
	car.player_controlled = false
	# Bots não precisam dos retrovisores/display (SubViewports caros)
	var onboard := car.get_node_or_null("Onboard")
	if onboard:
		car.remove_child(onboard)
		onboard.free()
	var cfg := CarConfig.new()
	var team: Color = track.layout.team_colors[(index / 2) % track.layout.team_colors.size()]
	cfg.primary_color = team
	cfg.secondary_color = Color.WHITE if team.get_luminance() < 0.7 else Color(0.12, 0.12, 0.16)
	cfg.accent_color = Color.from_hsv(fposmod(team.h + 0.45, 1.0), 0.7, 0.95)
	cfg.helmet_color = Color.from_hsv(randf(), 0.7, 0.95)
	cfg.suit_color = team
	cfg.rim_color = Color(0.12, 0.12, 0.15)
	cfg.car_name = driver[0]
	cfg.tyre_compound = CarConfig.TyreCompound.MEDIUM if randf() < 0.7 else CarConfig.TyreCompound.SOFT
	car.config = cfg
	get_parent().add_child(car)
	var audio := car.get_node_or_null("Audio") as CarAudio
	if audio:
		audio.make_rival()
	return car


func _profile(level: int) -> PackedFloat32Array:
	if not _profiles.has(level):
		var preset: Array = BotDriver.PRESETS[level]
		var pace := track.layout.bot_pace
		_profiles[level] = line.speed_profile(preset[0] * pace, preset[1] * pace, preset[2])
	return _profiles[level]


func _init_position(entry: RaceEntry) -> void:
	var pr := track.path.project(entry.car.global_position)
	entry.s = pr.x
	entry.lateral = pr.y
	entry.crossings = 0 if pr.x > track.path.length * 0.5 else 1
	entry.progress = (entry.crossings - 1) * track.path.length + entry.s


## Plateia (CrowdAudio de todas as arquibancadas): "start" ou "finish".
func _crowd(kind: String) -> void:
	get_tree().call_group("crowd_audio", "on_race_event", kind)


func _on_lights_out() -> void:
	state = State.RACING
	race_time = 0.0
	_crowd("start")
	for entry in entries:
		entry.lap_start = 0.0
		if not entry.is_player:
			_release_bot.call_deferred(entry, entry.bot.reaction_time() + entry.grid_slot * 0.04)
		elif entry.car.global_position.distance_to(_grid_positions.get(entry, entry.car.global_position)) > 0.8:
			_penalize(entry, 10.0, "LARGADA QUEIMADA", "Se moveu antes de as luzes apagarem")
	state_changed.emit(state)


func _release_bot(entry: RaceEntry, delay: float) -> void:
	await get_tree().create_timer(delay, false).timeout
	entry.car.hold = false
	entry.bot.released = true


# ---------------------------------------------------------------------------
# A cada passo de física
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if state == State.MENU or entries.is_empty():
		return
	if net == Net.CLIENT:
		_client_physics(delta)
		return
	var racing := state == State.RACING or state == State.FINISHED or state == State.PRACTICE or state == State.QUALIFYING
	if racing:
		race_time += delta
	_wrong_way_cooldown -= delta
	for key in _contact_cooldown.keys():
		_contact_cooldown[key] -= delta
		if _contact_cooldown[key] <= 0.0:
			_contact_cooldown.erase(key)
	for entry in entries:
		_update_entry(entry, delta, racing)
	if state == State.GRID:
		_check_jump_start()
	if state == State.QUALIFYING:
		quali.physics_update(delta)
	else:
		_update_ghosts()
	_update_positions()
	_update_drs_rule()
	_update_give_backs()
	Slipstream.update_all(_cars(), delta)
	if control:
		control.physics_update(delta)
	_restored.clear()


func _update_entry(e: RaceEntry, delta: float, racing: bool) -> void:
	if e.retired:
		return
	var p := track.path
	var length := p.length
	var car := e.car
	var pr := p.project(car.global_position)
	var prev_s := e.s
	e.s = pr.x
	e.lateral = pr.y
	e.race_time = race_time
	# Linha de chegada
	if prev_s > length * 0.75 and e.s < length * 0.25:
		e.crossings += 1
		if racing:
			_on_line_crossed(e)
	elif prev_s < length * 0.25 and e.s > length * 0.75:
		e.crossings -= 1
	e.progress = (e.crossings - 1) * length + e.s
	if racing and not e.finished:
		var index := int(floor((e.progress + length) / CHECKPOINT))
		while e.checkpoint_times.size() <= index:
			e.checkpoint_times.append(race_time)
	if not racing:
		return
	_update_pit(e, delta)
	if state != State.FINISHED or not e.finished:
		_update_track_limits(e, delta)
	if e.is_player:
		_update_wrong_way(e, delta)


func _on_line_crossed(e: RaceEntry) -> void:
	if state == State.QUALIFYING:
		quali.on_cross(e)
		return
	if e.lap_restart:
		# Saindo do box depois da ida rápida: a mesma volta começa de novo aqui (não é completada)
		e.lap_restart = false
		e.lap_start = race_time
		e.lap_invalid = false
		return
	if e.crossings >= 2 and not e.finished:
		var lap := race_time - e.lap_start
		e.last_lap = lap
		e.lap_times.append(lap)
		if not e.lap_invalid:
			if e.best_lap <= 0.0 or lap < e.best_lap:
				e.best_lap = lap
			if fastest_lap <= 0.0 or lap < fastest_lap:
				fastest_lap = lap
				fastest_entry = e
	e.lap_invalid = false
	e.lap_start = race_time
	if state == State.PRACTICE:
		return
	if not e.finished and (e.laps_completed() >= laps or leader_finished):
		e.finished = true
		e.finish_time = race_time
		leader_finished = true
		if e.pit_count < RaceSettings.mandatory_pits:
			e.disqualified = true
			e.dsq_reason = "Pit stop obrigatório não cumprido"
			_notify(e, "DESCLASSIFICADO", e.dsq_reason, true)
		if e.bot:
			e.bot.profile = _slow_profile(e.bot.profile)
		if e.is_player and net == Net.OFF:
			_pay_player()
			_crowd("finish")
		if (e.is_player and net == Net.OFF) or _all_finished() or (net == Net.SERVER and _humans_done()):
			state = State.FINISHED
			state_changed.emit(state)
			race_finished.emit()


## Créditos da corrida (uma vez): por volta completada, pela dificuldade dos bots.
func _pay_player() -> void:
	var profile := get_node_or_null("/root/Profile") as PlayerProfile
	if net != Net.OFF or player_reward >= 0 or profile == null or player_entry == null or state == State.PRACTICE:
		return
	var e := player_entry
	if profile.mode == "remote":
		_report_solo_result(e)
		return
	player_reward = profile.award_race(e.laps_completed(), RaceSettings.difficulty, e.finished and not e.retired, e.disqualified)


## Conectado ao servidor: a economia é dele. Manda o resultado (ele confere e paga) e mostra o valor.
func _report_solo_result(e: RaceEntry) -> void:
	player_reward = 0
	var n := get_node_or_null("/root/Net")
	if n == null:
		return
	var res: Dictionary = await n.request("solo_result", {
		"laps": e.laps_completed(), "laps_total": laps, "difficulty": RaceSettings.difficulty,
		"race_time": e.finish_time if e.finished else race_time, "best_lap": e.best_lap, "finished": e.finished and not e.retired,
		"dsq": e.disqualified, "pos": final_classification().find(e) + 1, "total": entries.size(), "grid": e.grid_slot + 1,
		"penalty": e.penalty_seconds, "lap_times": Array(e.lap_times), "fastest": fastest_entry == e,
		"track": RaceSettings.track,
	})
	if res.get("ok", false):
		player_reward = int(res.get("reward", 0))
	else:
		notify_entry(e, "SERVIDOR", str(res.get("error", "Resultado não registrado")), false)


## Servidor: todos os humanos terminaram, abandonaram ou saíram.
func _humans_done() -> bool:
	for id in humans:
		var e: RaceEntry = humans[id]
		if not e.finished and not e.retired:
			return false
	return true


func _slow_profile(profile: PackedFloat32Array) -> PackedFloat32Array:
	var out := profile.duplicate()
	for i in out.size():
		out[i] = minf(out[i] * 0.7, 45.0)
	return out


func _all_finished() -> bool:
	for e in entries:
		if not e.finished and not e.retired:
			return false
	return true


func _update_positions() -> void:
	var length := track.path.length
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a: RaceEntry, b: RaceEntry) -> bool:
		return _rank_key(a, length) > _rank_key(b, length))
	for k in sorted.size():
		(sorted[k] as RaceEntry).position = k + 1
	entries.assign(sorted)


## DRS por regra: a até DRS_GAP s do carro da frente (tempo nas marcas de progresso, as mesmas
## dos intervalos); o líder e quem está nos boxes não têm. Livre / treino: sempre permitido.
func _update_drs_rule() -> void:
	var active := drs_rule == 1 and state != State.PRACTICE and state != State.QUALIFYING
	for e in entries:
		e.car.drs_rule_active = active
		e.car.drs_allowed = not active or drs_gap_ok(e)


func drs_gap_ok(e: RaceEntry) -> bool:
	if e.position <= 1 or e.in_pit or e.retired or e.position - 2 >= entries.size():
		return false
	var ahead := entries[e.position - 2]
	if ahead.retired:
		return false
	var index := mini(e.checkpoint_times.size(), ahead.checkpoint_times.size()) - 1
	if index < 0:
		return false
	var gap := e.checkpoint_times[index] - ahead.checkpoint_times[index]
	return gap >= 0.0 and gap <= DRS_GAP


func _update_ghosts() -> void:
	_update_pit_ghosts()
	if _ghost_pairs.is_empty():
		return
	var keep: Array = []
	for pair in _ghost_pairs:
		var a: RaceEntry = pair[0]
		var b: RaceEntry = pair[1]
		var done := (a.progress > GHOST_UNTIL or a.retired) and (b.progress > GHOST_UNTIL or b.retired)
		if done and a.car.global_position.distance_to(b.car.global_position) > 6.0:
			a.car.remove_collision_exception_with(b.car)
		else:
			keep.append(pair)
	_ghost_pairs = keep


## Pista dos boxes: as vagas ficam a ~12 m uma da outra e um bot entrando na dele cruza a frente
## de quem está parado na vaga vizinha. Como na maioria dos jogos de corrida, bots não colidem entre
## si enquanto um deles está nos boxes (seguem fazendo fila e liberação segura); o jogador colide
## com todos normalmente.
func _update_pit_ghosts() -> void:
	for i in entries.size():
		var a := entries[i]
		if a.is_player or a.car == null:
			continue
		for j in range(i + 1, entries.size()):
			var b := entries[j]
			if b.is_player or b.car == null:
				continue
			var key := "%d_%d" % [a.get_instance_id(), b.get_instance_id()]
			var in_pit := _in_pit_area(a) or _in_pit_area(b)
			var dist := a.car.global_position.distance_to(b.car.global_position)
			if in_pit and dist < 40.0:
				if not _pit_ghosts.has(key):
					a.car.add_collision_exception_with(b.car)
					_pit_ghosts[key] = [a, b]
			elif _pit_ghosts.has(key) and not in_pit and dist > 8.0:
				if not _is_start_ghost(a, b):
					a.car.remove_collision_exception_with(b.car)
				_pit_ghosts.erase(key)


func _in_pit_area(e: RaceEntry) -> bool:
	return e.in_pit or e.in_pit_stop or (e.bot != null and e.bot.mode != BotDriver.Mode.RACE)


func _is_start_ghost(a: RaceEntry, b: RaceEntry) -> bool:
	for pair in _ghost_pairs:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


func _rank_key(e: RaceEntry, length: float) -> float:
	if e.retired:
		return -1e6 + e.progress
	if e.finished:
		return (laps + 2) * length + 1e5 - e.finish_time
	return e.progress


## Intervalo (texto) para o carro da frente.
func interval_text(e: RaceEntry) -> String:
	if net == Net.CLIENT:
		return e.net_interval
	if e.retired:
		return "DNF"
	if e.position <= 1:
		return "LÍDER" if state != State.FINISHED or not e.finished else "VENCEDOR"
	var ahead: RaceEntry = entries[e.position - 2]
	var length := track.path.length
	if e.finished and ahead.finished:
		return "+%.3f" % (e.finish_time - ahead.finish_time)
	var lap_diff := int(floor((ahead.progress - e.progress) / length))
	if lap_diff >= 1 and not ahead.finished:
		return "+%d VOLTA%s" % [lap_diff, "S" if lap_diff > 1 else ""]
	var index := mini(e.checkpoint_times.size() - 1, ahead.checkpoint_times.size() - 1)
	if index < 0:
		return "--"
	var gap := e.time_at_checkpoint(index) - ahead.time_at_checkpoint(index)
	return "+%.3f" % maxf(gap, 0.0)


# ---------------------------------------------------------------------------
# Boxes
# ---------------------------------------------------------------------------
func _update_pit(e: RaceEntry, delta: float) -> void:
	# Pit stop do jogador em andamento (conta mesmo se a vaga ficar fora da detecção da pista dos boxes)
	if e.is_player and e.in_pit_stop:
		e.pit_timer -= delta
		player_pit_timer = e.pit_timer
		if e.pit_timer <= 0.0:
			_end_player_pit(e)
	var lay := track.layout
	var p := track.path
	var i := p.index_at(e.s)
	var side := lay.pit_side
	var beyond := e.lateral * side - p.half_width(i, side)
	var was_in := e.in_pit
	# Dentro da pista dos boxes de verdade (além do muro onde ele existe)
	e.in_pit = lay.has_pit and track.pit_width[i] > 2.0 and beyond > minf(2.2, track.pit_width[i] * 0.3)
	if not e.in_pit:
		if was_in:
			e.pit_speeding_flagged = false
			e.pit_served = false
		if e.is_player and _box_marker:
			_box_marker.visible = false
		return
	# Limite de velocidade entre as linhas pintadas
	var after_entry := _ahead(lay.pit_entry_s + lay.pit_taper, e.s) < 0.0
	var before_exit := _ahead(lay.pit_exit_s - lay.pit_taper, e.s) > 0.0
	var speed := e.car.linear_velocity.length()
	var full := track.pit_width[i] >= (RaceTrack.PIT_WALL_STRIP + lay.pit_lane_width) * 0.95
	if after_entry and before_exit and full and speed > PIT_LIMIT + 0.8 and not e.pit_speeding_flagged:
		e.pit_speeding_flagged = true
		_penalize(e, 5.0, "VELOCIDADE NOS BOXES", "%d km/h no limite de 80 km/h" % roundi(speed * 3.6))
	# Pit stop do jogador: parar no box da equipe
	if e.is_player and _box_marker:
		_box_marker.visible = not e.in_pit_stop
	# Uma parada por passagem: parado na vaga depois do pit stop não começa outro
	if e.is_player and not e.in_pit_stop and not e.pit_served:
		var box := track.get_pit_box_transform(e.garage)
		if e.car.global_position.distance_to(box.origin) < 3.0 and speed < 1.5:
			_begin_player_pit(e)


## Coluna de luz sobre o box do jogador (aparece na pista dos boxes).
## Vaga do jogador nos boxes: o retângulo pintado ganha uma borda luminosa discreta (linha no chão e
## um véu baixo de luz, pulsando), visível ao entrar nos boxes.
func _make_box_marker() -> void:
	const LENGTH := 6.7
	const WIDTH := 3.7
	const VEIL := 0.45
	const LINE := 0.14
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector3(-WIDTH, 0, -LENGTH), Vector3(WIDTH, 0, -LENGTH), Vector3(WIDTH, 0, LENGTH), Vector3(-WIDTH, 0, LENGTH)]
	for k in 4:
		var a: Vector3 = corners[k] * 0.5
		var b: Vector3 = corners[(k + 1) % 4] * 0.5
		var inward := -(a + b).normalized() * Vector3(1, 0, 1)
		# Véu vertical
		for v in [[a, 0.0], [b, 0.0], [b + Vector3.UP * VEIL, 1.0], [a, 0.0], [b + Vector3.UP * VEIL, 1.0], [a + Vector3.UP * VEIL, 1.0]]:
			st.set_uv(Vector2(0.0, v[1]))
			st.add_vertex(v[0] + Vector3.UP * 0.03)
		# Linha no chão (por dentro da borda)
		var ai: Vector3 = a + inward.normalized() * LINE
		var bi: Vector3 = b + inward.normalized() * LINE
		for v in [a, b, bi, a, bi, ai]:
			st.set_uv(Vector2(0.0, 0.0))
			st.add_vertex(v + Vector3.UP * 0.03)
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/pit_box_glow.gdshader")
	mesh.surface_set_material(0, mat)
	_box_marker = MeshInstance3D.new()
	_box_marker.name = "PlayerBoxMarker"
	_box_marker.mesh = mesh
	_box_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box_marker.visible = false
	get_parent().add_child(_box_marker)
	var xf := track.get_pit_box_transform(player_entry.garage if player_entry else 0)
	_box_marker.global_transform = Transform3D(xf.basis, xf.origin - xf.basis.y * 0.05)


func _begin_player_pit(e: RaceEntry) -> void:
	begin_player_pit(e, 0.0)


## Pit stop do jogador; [param repair_time] > 0 força o conserto com esse tempo (levado ao box).
func begin_player_pit(e: RaceEntry, repair_time: float) -> void:
	e.in_pit_stop = true
	e.car.hold = true
	e.car.limiter_on = false
	var damage := e.car.get_node_or_null("Damage") as CarDamage
	var repair := repair_time > 0.0 or (damage != null and damage.get_overall() < 0.97)
	# Parada sorteada entre 2 e 4 s (o conserto soma o tempo dele)
	e.pit_timer = randf_range(PIT_STOP_MIN, PIT_STOP_MAX) + (maxf(repair_time, 5.0) if repair else 0.0)
	e.pit_stop_start = race_time
	player_pit_timer = e.pit_timer
	_show_crew(e, true)
	_notify(e, "PIT STOP", "Pneus %s%s" % [CarConfig.COMPOUND_NAMES[e.pit_compound], " + reparo" if repair else ""], false)


func _end_player_pit(e: RaceEntry) -> void:
	e.pit_served = true
	var damage := e.car.get_node_or_null("Damage") as CarDamage
	if (damage != null and damage.get_overall() < 0.97) or (control and control.is_involved(e)):
		_repair(e)
	e.car.change_tyres(e.pit_compound)
	e.car.hold = false
	e.in_pit_stop = false
	e.pit_count += 1
	e.compounds_used.append(e.pit_compound)
	_pit_time_notice(e)
	_show_crew(e, false)
	if control:
		control.on_pit_done(e)


## Conserto no box. Na rede os clientes reconstroem o carro também (peças arrancadas voltam).
func _repair(e: RaceEntry) -> void:
	e.car.repair()
	net_event.emit({"event": "repair", "idx": e.index})


## Carro destruído: sai da corrida (DNF) e é tirado da pista depois de alguns segundos.
func retire(e: RaceEntry) -> void:
	if e.retired:
		return
	e.retired = true
	e.car.hold = true
	if e.is_player and net == Net.OFF:
		_pay_player()
	_notify(e, "ABANDONO", "%s está fora da corrida" % e.name, false)
	await get_tree().create_timer(4.0, false).timeout
	if is_instance_valid(e.car):
		e.car.visible = false
		e.car.process_mode = Node.PROCESS_MODE_DISABLED
		e.car.collision_layer = 0
		e.car.collision_mask = 0
		e.car.freeze = true


## Chamados pelo BotDriver.
func begin_pit_stop(e: RaceEntry) -> void:
	e.in_pit_stop = true
	e.pit_stop_start = race_time
	_show_crew(e, true)


## Tempo parado no box (da parada até a liberação), mostrado ao sair.
func _pit_time_notice(e: RaceEntry) -> void:
	e.last_pit_time = race_time - e.pit_stop_start
	_notify(e, "PIT STOP  %s s" % ("%.1f" % e.last_pit_time).replace(".", ","),
		"Tempo parado no box · pneus %s" % CarConfig.COMPOUND_NAMES[e.pit_compound if e.is_player else e.car.config.tyre_compound], false)


func end_pit_stop(e: RaceEntry) -> void:
	e.in_pit_stop = false
	var damage := e.car.get_node_or_null("Damage") as CarDamage
	if (damage != null and damage.get_overall() < 0.97) or (control and control.is_involved(e)):
		_repair(e)
	e.pit_count += 1
	e.compounds_used.append(e.car.config.tyre_compound)
	_pit_time_notice(e)
	_show_crew(e, false)
	if control:
		control.on_pit_done(e)


func _ahead(target_s: float, s: float) -> float:
	var length := track.path.length
	return fposmod(target_s - s + length * 0.5, length) - length * 0.5


## Mecânicos (8, com as cores da equipe) em volta do carro durante o pit stop.
func _show_crew(e: RaceEntry, show: bool) -> void:
	if _crew_cars.has(e):
		(_crew_cars[e] as Node).queue_free()
		_crew_cars.erase(e)
	if not show:
		return
	var xf := e.car.global_transform
	var spots := [Vector3(1.4, 0, 1.8), Vector3(-1.4, 0, 1.8), Vector3(1.4, 0, -1.8), Vector3(-1.4, 0, -1.8),
		Vector3(0, 0, 3.3), Vector3(1.9, 0, 0.2), Vector3(-1.9, 0, 0.2), Vector3(0, 0, -3.2)]
	var transforms: Array[Transform3D] = []
	var data: Array[Color] = []
	for k in spots.size():
		var pos: Vector3 = xf * spots[k]
		pos.y = xf.origin.y - 0.05
		var face := (xf.origin - pos)
		face.y = 0.0
		transforms.append(Transform3D(Basis.looking_at(-face.normalized()), pos))
		data.append(Color(randf(), -2.0, randf(), randf()))
	var node := TrackLife.crew_node(transforms, data, e.color)
	node.name = "PitCrew"
	get_parent().add_child(node)
	_crew_cars[e] = node


# ---------------------------------------------------------------------------
# Penalidades
# ---------------------------------------------------------------------------
func _update_track_limits(e: RaceEntry, delta: float) -> void:
	if e.in_pit or e.car.hold:
		e.off_time = 0.0
		return
	if e.off_time <= 0.0:
		e.off_ahead = []
	var on_track := 0
	var in_contact := 0
	for k in e.car.tire_surface.size():
		if e.car.tire_state[k] == F1Car.TireState.AIR:
			continue
		in_contact += 1
		var surf := e.car.tire_surface[k]
		if surf == TrackSurface.Type.ASPHALT or surf == TrackSurface.Type.KERB:
			on_track += 1
	var speed := e.car.linear_velocity.length()
	if in_contact >= 2 and on_track == 0:
		if e.off_time <= 0.0:
			e.off_start_progress = e.progress
			e.off_distance = 0.0
			# Quem estava logo à frente ao sair da pista (para saber quem ele passou por fora)
			e.off_ahead = []
			for o in entries:
				if o != e and not o.retired and o.progress > e.progress and o.progress - e.progress < 80.0:
					e.off_ahead.append(o)
		e.off_time += delta
		e.off_distance += speed * delta
	elif on_track >= 2 and e.off_time > 0.0:
		var gained := (e.progress - e.off_start_progress) - e.off_distance
		if e.off_time > 0.25 and speed > 5.0:
			var passed: RaceEntry = null
			for o: RaceEntry in e.off_ahead:
				if o.progress < e.progress and not o.in_pit and not o.retired:
					passed = o
			if passed and (e.is_player or e.is_human) and state == State.RACING:
				# Passou alguém por fora da pista: dá para devolver a posição antes da penalidade
				request_give_back(e, passed, 5.0, "VANTAGEM INDEVIDA", "Passou %s por fora da pista" % passed.code)
			elif gained > 10.0:
				_penalize(e, 5.0, "VANTAGEM INDEVIDA", "Cortou a pista e ganhou %.0f m" % gained)
			else:
				e.track_limit_warnings += 1
				if e.track_limit_warnings > 3:
					_penalize(e, 5.0, "LIMITES DE PISTA", "Infração %d — penalidade" % e.track_limit_warnings)
				else:
					_notify(e, "LIMITES DE PISTA", "Aviso %d/3" % e.track_limit_warnings, false)
		e.off_time = 0.0


func _update_wrong_way(e: RaceEntry, delta: float) -> void:
	var tangent := track.path.tangent_at(e.s)
	var v := e.car.linear_velocity
	if v.length() > 5.0 and v.normalized().dot(tangent) < -0.4 and not e.in_pit:
		e.wrong_way_time += delta
		if e.wrong_way_time > 1.5 and _wrong_way_cooldown <= 0.0:
			_wrong_way_cooldown = 5.0
			_notify(e, "CONTRAMÃO", "Vire o carro no sentido da pista", false)
	else:
		e.wrong_way_time = 0.0


func _check_jump_start() -> void:
	for e in entries:
		if e.is_player and _grid_positions.has(e) and not e.penalties.has("LARGADA QUEIMADA"):
			if e.car.global_position.distance_to(_grid_positions[e]) > 0.8:
				_penalize(e, 10.0, "LARGADA QUEIMADA", "Se moveu antes de as luzes apagarem")


func _on_car_contact(other: F1Car, impulse: float, e: RaceEntry) -> void:
	if state != State.RACING:
		return
	var o := _entry_of(other)
	if o == null or o.retired or e.retired:
		return
	var key := "%d-%d" % [mini(e.get_instance_id(), o.get_instance_id()), maxi(e.get_instance_id(), o.get_instance_id())]
	if _contact_cooldown.has(key) or impulse < 2600.0:
		return
	_contact_cooldown[key] = 4.0
	# Culpado: quem está atrás e chegou mais rápido
	var behind := e if e.progress < o.progress else o
	var front := o if behind == e else e
	var dir := (front.car.global_position - behind.car.global_position).normalized()
	var closing := behind.car.linear_velocity.dot(dir) - front.car.linear_velocity.dot(dir)
	if closing > 2.5 and front.progress - behind.progress > 0.8:
		var seconds := 10.0 if impulse > 7000.0 else 5.0
		_penalize(behind, seconds, "COLISÃO", "Causou um acidente com %s" % front.code)


func _entry_of(car: F1Car) -> RaceEntry:
	for e in entries:
		if e.car == car:
			return e
	return null


func _penalize(e: RaceEntry, seconds: float, title: String, detail: String) -> void:
	if state == State.QUALIFYING:
		# Na classificatória a penalidade só anula a volta
		quali.invalidate(e, title)
		return
	if state == State.PRACTICE:
		_notify(e, title, detail + " (treino: sem penalidade)", false)
		return
	e.penalty_seconds += seconds
	e.penalties.append(title)
	e.penalty_log.append([title, seconds, detail, e.laps_completed() + 1])
	_notify(e, "%s  +%ds" % [title, roundi(seconds)], detail, true)


func notify_entry(e: RaceEntry, title: String, detail: String, is_penalty: bool) -> void:
	_notify(e, title, detail, is_penalty)


func penalize_entry(e: RaceEntry, seconds: float, title: String, detail: String) -> void:
	_penalize(e, seconds, title, detail)


func _notify(e: RaceEntry, title: String, detail: String, is_penalty: bool) -> void:
	infraction.emit(e, title, detail, is_penalty)


# ---------------------------------------------------------------------------
# Resultado
# ---------------------------------------------------------------------------
## Classificação final: terminaram (por voltas e tempo + penalidades), não terminaram, desclassificados.
func final_classification() -> Array[RaceEntry]:
	var out: Array[RaceEntry] = entries.duplicate()
	out.sort_custom(func(a: RaceEntry, b: RaceEntry) -> bool:
		if a.disqualified != b.disqualified:
			return b.disqualified
		if a.retired != b.retired:
			return b.retired
		if a.finished != b.finished:
			return a.finished
		if a.finished:
			if a.laps_completed() != b.laps_completed():
				return a.laps_completed() > b.laps_completed()
			return a.total_time() < b.total_time()
		return a.progress > b.progress)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if net == Net.SERVER:
		return
	if event.is_action_pressed("go_to_pit") and control and player_entry and control.is_involved(player_entry):
		if net == Net.CLIENT:
			_net_cmd({"cmd": "go_to_pit"})
		else:
			control.send_to_pit(player_entry)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_racing_line"):
		var settings := get_node_or_null("/root/Settings") as GameSettings
		if settings:
			settings.set_value("gameplay", "racing_line", (int(settings.get_value("gameplay", "racing_line")) + 1) % 3)
			var names := ["Linha ideal desligada", "Linha ideal: frenagens e curvas", "Linha ideal completa"]
			if player_entry:
				_notify(player_entry, "LINHA IDEAL", names[int(settings.get_value("gameplay", "racing_line"))], false)
	var chosen := -1
	if event.is_action_pressed("pit_soft"):
		chosen = CarConfig.TyreCompound.SOFT
	elif event.is_action_pressed("pit_medium"):
		chosen = CarConfig.TyreCompound.MEDIUM
	elif event.is_action_pressed("pit_hard"):
		chosen = CarConfig.TyreCompound.HARD
	if chosen >= 0:
		pit_compound = chosen as CarConfig.TyreCompound
		if player_entry:
			player_entry.pit_compound = pit_compound
		if net == Net.CLIENT:
			_net_cmd({"cmd": "pit_compound", "value": chosen})


## Rede (cliente): vota para recomeçar a corrida (ou retira o voto).
func vote_restart(yes: bool) -> void:
	if net != Net.CLIENT:
		return
	my_restart_vote = yes
	_net_cmd({"cmd": "restart_vote", "yes": yes})


## Votação aberta para recomeçar: segundos que faltam (0 = nenhuma).
func restart_vote_left() -> float:
	return maxf(float(restart_vote.get("until", 0.0)) - race_time, 0.0) if not restart_vote.is_empty() else 0.0


func _net_cmd(data: Dictionary) -> void:
	var n := get_node_or_null("/root/Net")
	if n:
		n.send_to_server("race_cmd", data)


static func format_time(t: float) -> String:
	if t <= 0.0:
		return "--:--.---"
	var m := int(t / 60.0)
	return "%d:%06.3f" % [m, t - m * 60.0]


## Apresentação dos carros (IntroDirector); termina quando ela acaba (ou é pulada).
func _play_intro() -> void:
	var intro := IntroDirector.new()
	intro.name = "Intro"
	add_child(intro)
	intro.play.call_deferred(self)
	await intro.finished


# ---------------------------------------------------------------------------
# Rede: servidor
# ---------------------------------------------------------------------------
## Monta o grid da corrida em rede: humanos na frente (ordem sorteada), bots completando até 10
## (se a sala usa bots). Os carros dos humanos usam o perfil da conta (visual e engenharia), que só o
## servidor conhece de verdade. Depois espera o RaceSession chamar net_go().
func _build_net_grid() -> void:
	laps = int(net_setup.get("laps", 5))
	line = RacingLine.build(track, track.layout.raceline)
	state = State.GRID
	player.allow_quick_repair = false
	var players: Array = net_setup.get("players", []).duplicate()
	players.shuffle()
	var count := players.size()
	if bool(net_setup.get("bots", true)):
		count = maxi(count, clampi(int(net_setup.get("cars", NetProtocol.MAX_ROOM_PLAYERS)), 2, NetProtocol.MAX_GRID))
	var difficulty := clampi(int(net_setup.get("difficulty", 1)), 0, 3)
	var bot_count := count - players.size()
	var bot_levels: Array[int] = []
	for k in bot_count:
		var level := difficulty
		if level == 3:
			level = [BotDriver.Difficulty.HARD, BotDriver.Difficulty.MEDIUM, BotDriver.Difficulty.EASY][k * 3 / maxi(bot_count, 1)]
		bot_levels.append(level)
	bot_levels.sort_custom(func(a: int, b: int) -> bool: return a > b)
	var names := DRIVERS.duplicate()
	names.shuffle()
	for slot in count:
		if slot < players.size():
			var p: Dictionary = players[slot]
			var car := player if slot == 0 else _spawn_net_car("Human%d" % slot)
			car.player_controlled = false
			_apply_profile(car, p.get("profile", {}), true)
			var entry := _make_entry(car, true, slot, slot)
			entry.is_human = true
			entry.net_id = str(p["id"])
			entry.name = str(p.get("name", "Jogador"))
			entry.code = _code_of(entry.name)
			humans[entry.net_id] = entry
			continue
		var k := slot - players.size()
		var level: int = bot_levels[k]
		var car := _spawn_bot(slot, names[k], level)
		var entry := _make_entry(car, false, slot, slot)
		entry.name = names[k][0]
		entry.code = names[k][1]
		entry.difficulty = level
		var bot := BotDriver.new()
		bot.name = "Bot"
		car.add_child(bot)
		bot.setup(car, track, line, _profile(level), level, entry, self)
		bot.pit_lap = randi_range(maxi(laps / 3, 2), maxi(laps - 2, 2))
		bot.pit_compound = CarConfig.TyreCompound.HARD if randf() < 0.6 else CarConfig.TyreCompound.MEDIUM
		entry.bot = bot
	# Servidor não desenha nem toca nada: tira o que só serve para isso
	for e in entries:
		for n in ["Audio", "Onboard"]:
			var node := e.car.get_node_or_null(n)
			if node:
				node.queue_free()
	control = RaceControl.new()
	control.name = "RaceControl"
	add_child(control)
	control.setup(self)
	for e in entries:
		var damage := e.car.get_node_or_null("Damage") as CarDamage
		if damage:
			damage.part_detached.connect(func(piece: String) -> void:
				net_event.emit({"event": "detach", "idx": e.index, "piece": piece}))
	for a in entries:
		for b in entries:
			if a.is_player or b.is_player or a.get_instance_id() >= b.get_instance_id():
				continue
			a.car.add_collision_exception_with(b.car)
			_ghost_pairs.append([a, b])
	for entry in entries:
		entry.car.global_transform = track.get_grid_transform(entry.grid_slot)
		entry.car.linear_velocity = Vector3.ZERO
		entry.car.angular_velocity = Vector3.ZERO
		entry.car.reset_physics_interpolation()
		entry.car.hold = not entry.is_player
		_init_position(entry)
	net_grid_ready.emit()


## Largada da corrida em rede (todos carregaram ou o tempo de espera acabou).
func net_go() -> void:
	var q_laps := int(net_setup.get("quali_laps", 0))
	if q_laps > 0:
		var q_time := RaceSettings.quali_seconds(q_laps, int(net_setup.get("quali_time", 0)))
		net_event.emit({"event": "quali", "end": q_time})
		await _run_qualifying(RaceSettings.quali_lap_count(q_laps), bool(net_setup.get("quali_collisions", true)),
			q_time, bool(net_setup.get("quali_strict", true)))
		for entry in entries:
			entry.car.global_transform = track.get_grid_transform(entry.grid_slot)
			entry.car.linear_velocity = Vector3.ZERO
			entry.car.angular_velocity = Vector3.ZERO
			entry.car.reset_physics_interpolation()
			entry.car.hold = not entry.is_player
			_init_position(entry)
	state_changed.emit(state)
	net_event.emit({"event": "grid"})
	# Tempo da apresentação dos clientes (todos largam juntos); os humanos ficam parados
	for id in humans:
		humans[id].car.hold = true
	await get_tree().create_timer(IntroDirector.length(roster.size()) + 1.0, false).timeout
	for id in humans:
		humans[id].car.hold = false
	for entry in entries:
		_grid_positions[entry] = entry.car.global_position
	var hold_time := randf_range(0.2, 3.0)
	net_event.emit({"event": "lights", "hold": hold_time})
	if track.start_lights:
		track.start_lights.lights_out.connect(_on_lights_out, CONNECT_ONE_SHOT)
		track.start_lights.run_sequence(hold_time)
	else:
		_on_lights_out()


## Lista de carros para os clientes montarem a mesma corrida.
func net_roster() -> Array:
	var out := []
	for e in roster:
		var cfg := e.car.config
		var d := {"idx": e.index, "id": e.net_id, "name": e.name, "code": e.code, "slot": e.grid_slot, "garage": e.garage,
			"color": e.color.to_html(), "difficulty": e.difficulty}
		if e.is_human:
			d["profile"] = _profile_for(e)
		elif cfg:
			d["colors"] = [cfg.primary_color.to_html(), cfg.secondary_color.to_html(), cfg.accent_color.to_html(),
				cfg.helmet_color.to_html(), cfg.suit_color.to_html(), cfg.rim_color.to_html()]
			d["compound"] = cfg.tyre_compound
		out.append(d)
	return out


func _profile_for(e: RaceEntry) -> Dictionary:
	for p in net_setup.get("players", []):
		if str(p["id"]) == e.net_id:
			return p.get("profile", {})
	return {}


static func _code_of(text: String) -> String:
	var letters := ""
	for ch in text.to_upper():
		if ch >= "A" and ch <= "Z":
			letters += ch
	return (letters + "XXX").substr(0, 3)


## Carro extra (outro humano na rede): sem retrovisores; no cliente, sem som de motor alto.
func _spawn_net_car(node_name: String) -> F1Car:
	var car := car_scene.instantiate() as F1Car
	car.name = node_name
	car.player_controlled = false
	var onboard := car.get_node_or_null("Onboard")
	if onboard:
		car.remove_child(onboard)
		onboard.free()
	car.config = CarConfig.new()
	get_parent().add_child(car)
	var audio := car.get_node_or_null("Audio") as CarAudio
	if audio:
		audio.make_rival()
	return car


## Visual (e, no servidor, a engenharia) de um carro a partir do perfil da conta.
func _apply_profile(car: F1Car, profile_dict: Dictionary, with_setup: bool) -> void:
	if car.config == null:
		car.config = CarConfig.new()
	var p := PlayerProfile.new()
	p.mode = "server"
	p.from_dict(profile_dict)
	p.apply_to_config(car.config)
	if with_setup:
		p.apply_setup(car)
	car.config.changed.emit()
	p.free()


## Estado da prova para os clientes (5 vezes por segundo).
func net_state() -> Dictionary:
	var list := []
	for e in roster:
		list.append([e.position, e.crossings, e.progress, e.last_lap, e.best_lap, e.finished, e.finish_time,
			e.penalty_seconds, e.penalty_log.map(func(x: Array) -> String: return "%s|%s|%s|%d" % [x[0], x[1], x[2], x[3]]), e.retired, e.disqualified, e.pit_count, e.in_pit, e.in_pit_stop,
			interval_text(e), e.lap_start, e.track_limit_warnings, e.pit_timer, e.lap_invalid, e.lap_restart, e.car.drs_allowed])
	var inv := {}
	if control:
		for e: RaceEntry in control.involved:
			inv[e.index] = [control.involved[e]["time_left"], control.involved[e]["in_box"]]
	return {
		"state": state, "race_time": race_time, "laps": laps, "entries": list,
		"fastest": fastest_entry.index if fastest_entry else -1, "fastest_lap": fastest_lap, "leader_finished": leader_finished,
		"yellow": control.yellow if control else false, "involved": inv,
		"sc": [control.safety_car.progress, control.safety_car.speed, control.yellow_min_left()] if control and control.safety_car else [],
	}


# ---------------------------------------------------------------------------
# Rede: cliente
# ---------------------------------------------------------------------------
## Monta a mesma corrida que o servidor: todos os carros são marionetes (sem física própria).
func _start_net_client() -> void:
	get_tree().paused = false
	var settings: Dictionary = net_setup.get("settings", {})
	laps = int(settings.get("laps", 5))
	if not LoadingScreen.is_loading():
		LoadingScreen.start("Preparando a corrida")
	await _loading_step(0.0, "Linha ideal")
	line = RacingLine.build(track, track.layout.raceline)
	state = State.GRID
	player.allow_quick_repair = false
	var daylight := get_tree().get_first_node_in_group("daylight") as Daylight
	if daylight:
		daylight.allow_cycle = false
	var me := str(net_setup.get("me", ""))
	var list: Array = net_setup.get("roster", [])
	var own_used := false
	for k in list.size():
		var d: Dictionary = list[k]
		await _loading_step(0.1 + 0.85 * (k + 1) / maxf(list.size(), 1.0), "Carros no grid %d/%d" % [k + 1, list.size()])
		var mine := str(d.get("id", "")) == me and me != "" and not own_used
		var car: F1Car
		if mine:
			car = player
			own_used = true
		else:
			car = _spawn_net_car("Car%d" % int(d["idx"]))
		if d.has("profile"):
			_apply_profile(car, d["profile"], false)
		elif d.has("colors"):
			var c: Array = d["colors"]
			var cfg := car.config
			cfg.primary_color = Color.html(c[0])
			cfg.secondary_color = Color.html(c[1])
			cfg.accent_color = Color.html(c[2])
			cfg.helmet_color = Color.html(c[3])
			cfg.suit_color = Color.html(c[4])
			cfg.rim_color = Color.html(c[5])
			cfg.car_name = str(d["name"])
			cfg.tyre_compound = int(d.get("compound", 1)) as CarConfig.TyreCompound
			cfg.changed.emit()
		car.set_puppet(true)
		var entry := _make_entry(car, mine, int(d["slot"]), int(d["garage"]))
		entry.is_human = str(d.get("id", "")) != ""
		entry.net_id = str(d.get("id", ""))
		entry.name = "Você" if mine else str(d["name"])
		entry.code = str(d["code"])
		entry.color = Color.html(str(d["color"]))
		entry.difficulty = int(d.get("difficulty", -1))
		if mine:
			player_entry = entry
		car.global_transform = track.get_grid_transform(entry.grid_slot)
		car.reset_physics_interpolation()
		_init_position(entry)
	if player_entry == null:
		# Sem carro próprio (não deveria acontecer): esconde o carro da cena
		player.visible = false
		player.set_puppet(true)
	control = RaceControl.new()
	control.name = "RaceControl"
	control.mirror = true
	add_child(control)
	control.setup(self)
	_make_box_marker()
	_make_line_guide()
	net_client = NetRaceClient.new()
	net_client.name = "NetRaceClient"
	add_child(net_client)
	net_client.setup(self)
	if LoadingScreen.is_loading():
		await _loading_step(1.0, "Esperando os outros pilotos")
		LoadingScreen.done()
	state_changed.emit(state)
	_net_cmd({"cmd": "loaded"})


func _client_physics(delta: float) -> void:
	if state == State.RACING or state == State.FINISHED:
		race_time += delta
	# Vácuo só para o visual (a física é do servidor)
	Slipstream.update_all(_cars(), delta)
	var p := track.path
	for e in roster:
		var pr := p.project(e.car.global_position)
		e.s = pr.x
		e.lateral = pr.y
		e.race_time = race_time
	if control:
		control.mirror_update(delta)
	if _box_marker and player_entry:
		_box_marker.visible = player_entry.in_pit and not player_entry.in_pit_stop


## Aplica o estado da prova que veio do servidor.
func apply_net_state(d: Dictionary) -> void:
	var new_state := int(d.get("state", state))
	race_time = float(d.get("race_time", race_time))
	laps = int(d.get("laps", laps))
	var list: Array = d.get("entries", [])
	for k in mini(list.size(), roster.size()):
		var e := roster[k]
		var v: Array = list[k]
		e.position = int(v[0])
		var crossings := int(v[1])
		if crossings != e.crossings and int(v[1]) >= 2 and v[3] > 0.0 and e.lap_times.size() < crossings - 1:
			e.lap_times.append(float(v[3]))
		e.crossings = crossings
		e.progress = float(v[2])
		e.last_lap = float(v[3])
		e.best_lap = float(v[4])
		e.finished = bool(v[5])
		e.finish_time = float(v[6])
		e.penalty_seconds = float(v[7])
		e.penalties.clear()
		e.penalty_log.clear()
		for item in v[8]:
			var parts := str(item).split("|")
			e.penalties.append(parts[0])
			e.penalty_log.append([parts[0], float(parts[1]) if parts.size() > 1 else 0.0, parts[2] if parts.size() > 2 else "",
				int(parts[3]) if parts.size() > 3 else 0])
		e.retired = bool(v[9])
		e.disqualified = bool(v[10])
		e.pit_count = int(v[11])
		e.in_pit = bool(v[12])
		var was_stop := e.in_pit_stop
		e.in_pit_stop = bool(v[13])
		if was_stop != e.in_pit_stop:
			_show_crew(e, e.in_pit_stop)
		e.net_interval = str(v[14])
		e.lap_start = float(v[15])
		e.track_limit_warnings = int(v[16])
		e.pit_timer = float(v[17])
		e.lap_invalid = bool(v[18])
		e.lap_restart = bool(v[19]) if v.size() > 19 else false
		e.car.drs_rule_active = drs_rule == 1 and state != State.PRACTICE
		e.car.drs_allowed = bool(v[20]) if v.size() > 20 else true
		if e.is_player:
			player_pit_timer = e.pit_timer
	var fi := int(d.get("fastest", -1))
	fastest_entry = roster[fi] if fi >= 0 and fi < roster.size() else null
	fastest_lap = float(d.get("fastest_lap", 0.0))
	leader_finished = bool(d.get("leader_finished", false))
	var sorted := roster.duplicate()
	sorted.sort_custom(func(a: RaceEntry, b: RaceEntry) -> bool: return a.position < b.position)
	entries.assign(sorted)
	if control:
		control.apply_mirror(d, roster)
	# Quem já terminou vê a corrida como encerrada (resultado) mesmo com outros ainda correndo
	if player_entry and player_entry.finished and new_state == State.RACING:
		new_state = State.FINISHED
	if new_state != state:
		if new_state == State.RACING:
			_crowd("start")
		elif new_state == State.FINISHED and player_entry and player_entry.finished:
			_crowd("finish")
		state = new_state as State
		state_changed.emit(state)
		if state == State.FINISHED:
			race_finished.emit()


## Acontecimentos que o servidor manda na hora (luzes, peça arrancada, aviso para este jogador).
func apply_net_event(d: Dictionary) -> void:
	match str(d.get("event", "")):
		"quali":
			# Classificatória antes do grid: sem apresentação agora (ela vem no "grid")
			quali_end = float(d.get("end", 0.0))
			state = State.QUALIFYING
			state_changed.emit(state)
		"grid":
			if IntroDirector.enabled(get_tree()) and player_entry:
				_play_intro()
		"lights":
			var intro := get_node_or_null("Intro") as IntroDirector
			if intro:
				intro.skip()
			if track.start_lights:
				track.start_lights.run_sequence(float(d.get("hold", 1.0)))
		"detach":
			var idx := int(d.get("idx", -1))
			if idx >= 0 and idx < roster.size():
				var damage := roster[idx].car.get_node_or_null("Damage") as CarDamage
				if damage:
					damage.detach_piece(str(d.get("piece", "")))
		"repair":
			var ri := int(d.get("idx", -1))
			if ri >= 0 and ri < roster.size():
				roster[ri].car.repair()
		"notice":
			if player_entry:
				_notify(player_entry, str(d.get("title", "")), str(d.get("detail", "")), bool(d.get("penalty", false)))
		"reward":
			player_reward = int(d.get("reward", 0))
		"give_back":
			if player_entry and int(d.get("idx", -1)) == player_entry.index:
				_client_give_back = {"target": str(d.get("target", "")), "until": race_time + float(d.get("left", GIVE_BACK_TIME)),
					"seconds": float(d.get("seconds", 10.0))}
		"vote":
			if bool(d.get("closed", false)):
				restart_vote = {}
				my_restart_vote = false
			else:
				restart_vote = {"yes": int(d.get("yes", 0)), "needed": int(d.get("needed", 1)),
					"until": race_time + float(d.get("left", 0.0)), "voters": d.get("voters", [])}
				var n := get_node_or_null("/root/Net")
				if n:
					my_restart_vote = str(n.account.get("id", "")) in (d.get("ids", []) as Array)
				if not my_restart_vote and player_entry:
					_notify(player_entry, "VOTAÇÃO: RECOMEÇAR A CORRIDA", "%d/%d votos · abra o menu (Esc) para votar" % [
						restart_vote["yes"], restart_vote["needed"]], false)
		"restarting":
			restart_vote = {}
			my_restart_vote = false
			if player_entry:
				_notify(player_entry, "RECOMEÇANDO A CORRIDA", "Votação aprovada · carregando o grid de novo", false)
		"give_back_end":
			if player_entry and int(d.get("idx", -1)) == player_entry.index:
				_client_give_back = {}
		"closed":
			# O servidor encerrou a corrida: quem ainda corria vê o resultado
			if state != State.FINISHED:
				state = State.FINISHED
				state_changed.emit(state)
				race_finished.emit()


# ---------------------------------------------------------------------------
# Devolver a posição
# ---------------------------------------------------------------------------
## Prazo (s) para devolver uma posição ganha de forma irregular.
const GIVE_BACK_TIME := 12.0
## entry -> {target, until, seconds, title, detail}
var give_backs := {}
var _restored := {}
## Cliente: o "devolva a posição" do jogador espelhado do servidor.
var _client_give_back := {}


## Posição que o jogador deve devolver agora: {target (código), left (s), seconds} ou vazio.
func player_give_back() -> Dictionary:
	if player_entry == null:
		return {}
	if net == Net.CLIENT:
		if _client_give_back.is_empty():
			return {}
		return {"target": _client_give_back["target"], "left": maxf(float(_client_give_back["until"]) - race_time, 0.0),
			"seconds": _client_give_back["seconds"]}
	if not give_backs.has(player_entry):
		return {}
	var d: Dictionary = give_backs[player_entry]
	return {"target": (d["target"] as RaceEntry).code, "left": maxf(float(d["until"]) - race_time, 0.0), "seconds": d["seconds"]}


## O jogador ganhou a posição de `target` de forma irregular: aviso para devolvê-la; se não devolver
## no prazo, leva a penalidade.
func request_give_back(e: RaceEntry, target: RaceEntry, seconds: float, title: String, detail: String) -> void:
	if state == State.QUALIFYING:
		quali.invalidate(e, title)
		return
	if give_backs.has(e):
		# Já devendo uma posição: a nova infração vale direto
		_penalize(e, seconds, title, detail)
		return
	give_backs[e] = {"target": target, "until": race_time + GIVE_BACK_TIME, "seconds": seconds, "title": title, "detail": detail}
	_notify(e, "DEVOLVA A POSIÇÃO", "%s · deixe %s passar em %d s ou leve +%ds" % [detail, target.code, int(GIVE_BACK_TIME), roundi(seconds)], true)
	net_event.emit({"event": "give_back", "idx": e.index, "target": target.code, "left": GIVE_BACK_TIME, "seconds": seconds})


## `passer` voltou à frente de `e`: se era a posição que `e` devia, está resolvido (true).
func give_back_restored(e: RaceEntry, passer: RaceEntry) -> bool:
	if give_backs.has(e) and give_backs[e]["target"] == passer:
		give_backs.erase(e)
		net_event.emit({"event": "give_back_end", "idx": e.index})
		_restored[e] = passer
		_notify(e, "POSIÇÃO DEVOLVIDA", "Sem penalidade", false)
		if passer.is_player or passer.is_human:
			_notify(passer, "POSIÇÃO DEVOLVIDA", "%s devolveu a sua posição" % e.code, false)
		return true
	# Já resolvido neste passo (a troca de volta não é uma ultrapassagem irregular de quem recebeu)
	if _restored.get(e) == passer:
		_restored.erase(e)
		return true
	return false


func _update_give_backs() -> void:
	for e: RaceEntry in give_backs.keys():
		var d: Dictionary = give_backs[e]
		var target: RaceEntry = d["target"]
		if target.retired or target.in_pit or e.retired or e.finished:
			give_backs.erase(e)
			net_event.emit({"event": "give_back_end", "idx": e.index})
		elif target.progress > e.progress + 2.0:
			give_back_restored(e, target)
		elif race_time > float(d["until"]):
			give_backs.erase(e)
			net_event.emit({"event": "give_back_end", "idx": e.index})
			_penalize(e, d["seconds"], d["title"], d["detail"] + " (não devolveu a posição)")


## Classificatória (solo ou servidor): ao voltar, entries[].grid_slot é o grid novo e o estado volta a GRID.
func _run_qualifying(q_laps: int, collisions: bool, time_limit := 0.0, strict := true) -> void:
	quali = Qualifying.new()
	quali.name = "Qualifying"
	add_child(quali)
	quali.setup(self, q_laps, collisions, time_limit, strict)
	await quali.run()
	state = State.GRID
	race_time = 0.0
	leader_finished = false


## Segundos que faltam da classificatória (-1 = sem limite ou fora dela).
func quali_time_left() -> float:
	if state != State.QUALIFYING:
		return -1.0
	if quali:
		return quali.time_left()
	return maxf(quali_end - race_time, 0.0) if quali_end > 0.0 else -1.0


## Carros na pista (para o vácuo).
func _cars() -> Array:
	var out := []
	for e in entries:
		if e.car and not e.retired:
			out.append(e.car)
	return out
