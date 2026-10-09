extends SceneTree
## Modo espectador (com janela):  godot --path . -s res://tests/capture_spectator.gd -- <pasta> [monza|monaco]
## Corrida solo com 3 bots: entra no espectador (piloto automático assume o carro do jogador),
## fotografa a TV automática, câmeras fixas, a câmera livre e a perseguição de outro carro, e sai
## (o controle volta ao jogador).

var out_dir := ""
var track_id := "monaco"
var manager: RaceManager
var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	track_id = args[1] if args.size() > 1 else "monaco"
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_capspec_profile.cfg"
		profile.reset_profile()
	RaceSettings.track = track_id
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 3
	RaceSettings.opponents = 3
	RaceSettings.quali_laps = 0
	RaceSettings.skip_menu = true
	var scene := (load(RaceSettings.track_scene(track_id)) as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _shot(name: String) -> void:
	for k in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [track_id, name]))
	print("captura: ", name)


func _run() -> void:
	while manager.state != RaceManager.State.RACING:
		await process_frame
	var intro := manager.get_node_or_null("Intro")
	if intro:
		intro.skip()
	await create_timer(4.0).timeout
	var hud := manager.get_parent().find_child("RaceModeHud", true, false) as RaceModeHud
	if hud == null:
		for n in manager.get_parent().get_children():
			if n is RaceModeHud:
				hud = n
	var spec := hud.spectator
	spec.enter()
	_check(spec.active, "modo espectador ativo")
	var pe := manager.player_entry
	_check(pe.bot != null and not pe.car.player_controlled, "piloto automático dirige o carro do jogador")
	print("  câmeras fixas: ", spec.spot_list.map(func(sp: Array) -> String: return "%s %s" % [sp[1], sp[0]]))
	_check(spec.spot_list.size() >= 4, "câmeras fixas da pista (%d)" % spec.spot_list.size())
	await create_timer(2.0).timeout
	await _shot("tv_auto")
	for k in mini(3, spec.spot_list.size()):
		spec.spot = k
		spec._set_view(Spectator.View.TV_FIXED)
		await create_timer(0.5).timeout
		await _shot("fixa_%d" % (k + 1))
	spec._set_view(Spectator.View.FREE)
	var cam := spec._cam
	var p0 := cam.global_position
	spec._free_xf = Transform3D(Basis(Vector3.RIGHT, -0.5), p0 + Vector3(0, 40, 0))
	spec._free_pitch = -0.5
	await create_timer(0.5).timeout
	_check(cam.global_position.distance_to(p0) > 20.0, "câmera livre se move (pausa %s, vista %d, ativo %s)" % [
		paused, spec.view, spec.active])
	await _shot("livre")
	spec._change_car(1)
	spec._set_view(Spectator.View.FOLLOW)
	await create_timer(1.5).timeout
	_check(cam.target != pe.car, "perseguição de outro carro")
	await _shot("perseguicao")
	spec.exit()
	await create_timer(0.3).timeout
	_check(not spec.active and pe.bot == null and pe.car.player_controlled and cam.target == pe.car, "saiu: controle volta ao jogador")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_capspec_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
