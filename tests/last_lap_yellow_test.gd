extends SceneTree
## Amarela na última volta (sem janela):  godot --headless --path . -s res://tests/last_lap_yellow_test.gd
## Fora da última volta a amarela dura no mínimo 30 s e espera o carro batido ir ao box; na última
## volta do líder ela dura só 10 s, mesmo com o batido ainda na pista.

var failures := 0
var manager: RaceManager


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_lastlap_profile.cfg"
		profile.reset_profile()
	RaceSettings.track = "monza"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 5
	RaceSettings.opponents = 3
	RaceSettings.quali_laps = 0
	RaceSettings.skip_menu = true
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _seconds(t: float) -> void:
	var t0 := manager.race_time
	while manager.race_time - t0 < t:
		await physics_frame


func _run() -> void:
	while manager.state != RaceManager.State.RACING:
		await process_frame
	Engine.time_scale = 4.0
	var control := manager.control
	var pe := manager.player_entry
	pe.car.player_controlled = false
	pe.car.hold = true
	var wreck: RaceEntry = null
	for e in manager.entries:
		if e != pe:
			wreck = e
			break
	# O batido fica parado na pista (o bot não vai sozinho ao box)
	wreck.bot.released = false
	wreck.car.hold = true
	control.report_crash(wreck)
	control.involved[wreck]["bot_delay"] = 1e9
	_check(control.yellow and not control.last_lap(), "amarela na 1ª volta (não é a última)")
	await _seconds(12.0)
	_check(control.yellow, "fora da última volta: ainda amarela depois de 12 s")
	# Agora a corrida está na última volta (o líder já completou laps - 1)
	manager.laps = 1
	_check(control.last_lap(), "última volta")
	_check(control.yellow_min_left() > 9.0 and control.sc_left_text().contains("sai em"), "contagem de 10 s na última volta")
	await _seconds(5.0)
	_check(control.yellow, "ainda amarela aos 5 s da última volta")
	await _seconds(6.0)
	_check(not control.yellow, "última volta: amarela termina em 10 s mesmo com o batido na pista")
	Engine.time_scale = 1.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_lastlap_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
