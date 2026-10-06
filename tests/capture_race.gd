extends SceneTree
## Capturas do modo corrida (precisa de janela):
##   godot --path . -s res://tests/capture_race.gd -- <pasta>
## Menu, grid com as luzes, largada, HUD durante a corrida (classificação, minimapa, banner),
## jogador nos boxes com a equipe trocando pneus, mecânicos nas garagens e público.

var out_dir := "user://captures"
var scene: Node3D
var manager: RaceManager


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 10
	RaceSettings.opponents = 9
	RaceSettings.difficulty = 3
	RaceSettings.grid = RaceSettings.Grid.MIDDLE
	RaceSettings.skip_menu = false
	scene = (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _shot(file: String) -> void:
	for k in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(file))
	print("salvo ", file)


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _run() -> void:
	await _frames(40)
	await _shot("race_menu.png")
	manager._start()
	while manager.state != RaceManager.State.GRID:
		await process_frame
	await _frames(240)
	await _shot("race_grid.png")
	while manager.state != RaceManager.State.RACING:
		await process_frame
	# Jogador pilotado por um bot (para a captura)
	var pe := manager.player_entry
	pe.car.player_controlled = false
	var bot := BotDriver.new()
	pe.car.add_child(bot)
	bot.setup(pe.car, manager.track, manager.line, manager._profile(BotDriver.Difficulty.MEDIUM), BotDriver.Difficulty.MEDIUM, pe, manager)
	pe.bot = bot
	bot.released = true
	await _frames(90)
	await _shot("race_start.png")
	manager.infraction.emit(pe, "LIMITES DE PISTA", "Aviso 1/3", false)
	await _frames(60)
	await _shot("race_banner_warning.png")
	manager.infraction.emit(pe, "COLISÃO  +5s", "Causou um acidente com SAT", true)
	await _frames(200)
	await _shot("race_banner_penalty.png")
	await _frames(1500)
	await _shot("race_running.png")
	# Página 2 da classificação
	manager.hud.standings.page = 1
	await _shot("race_page2.png")
	manager.hud.standings.page = 0
	# Boxes: leva o jogador ao box e faz o pit stop
	bot.mode = BotDriver.Mode.PIT_IN
	pe.car.global_transform = manager.track.path.frame_at(manager.track.layout.pit_entry_s + 100.0,
		-(manager.track.path.width_right[manager.track.path.index_at(manager.track.layout.pit_entry_s + 100.0)] + 9.0), 0.2)
	pe.car.linear_velocity = pe.car.global_basis.z * 20.0
	pe.car.reset_physics_interpolation()
	await _frames(60)
	await _shot("race_pitlane.png")
	while not pe.in_pit_stop and manager.race_time < 400.0:
		await process_frame
	await _frames(30)
	var cam := Camera3D.new()
	scene.add_child(cam)
	var c := pe.car.global_position
	cam.global_transform = Transform3D(Basis(), c + pe.car.global_basis.x * 7.0 + Vector3.UP * 3.5 + pe.car.global_basis.z * 3.0).looking_at(c, Vector3.UP)
	(scene.get_node("RaceCamera/Outline") as Node3D).reparent(cam, false)
	cam.current = true
	await _shot("race_pitstop.png")
	# Garagens com mecânicos
	var g := manager.track.get_pit_box_transform(4)
	cam.global_transform = Transform3D(Basis(), g.origin + g.basis.x * 3.0 + Vector3.UP * 2.2 - g.basis.z * 6.0).looking_at(g.origin - g.basis.x * 12.0, Vector3.UP)
	await _shot("race_garages.png")
	# Público de perto
	var p := manager.track.path
	cam.global_transform = Transform3D(Basis(), p.position_at(-5.0, 1.0) + Vector3.UP * 1.5).looking_at(p.position_at(-5.0, 24.0) + Vector3.UP * 5.0, Vector3.UP)
	cam.fov = 40.0
	await _shot("race_crowd.png")
	quit()
