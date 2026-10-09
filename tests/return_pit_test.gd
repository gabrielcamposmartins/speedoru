extends SceneTree
## Voltar aos boxes, dano replicado e contadores das ações da rede (sem janela):
##   godot --headless --path . -s res://tests/return_pit_test.gd
## * Select/K abre o popup de confirmação (o jogo pausa); cancelar não faz nada; confirmar leva o
##   carro ao box, recomeça a volta e faz o pit stop.
## * Batida do servidor aplicada num carro de outro jogador (remote_hit): amassado e resistência
##   das peças iguais às do carro que bateu; o sinal hit_applied sai em toda batida.
## * O cliente conta todas as ações de toque da rede (inclusive o pisca "pedir passagem").

var failures := 0
var manager: RaceManager


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_returnpit_profile.cfg"
		profile.reset_profile()
	RaceSettings.track = "monza"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 5
	RaceSettings.opponents = 2
	RaceSettings.quali_laps = 0
	RaceSettings.skip_menu = true
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func _run() -> void:
	while manager.state != RaceManager.State.RACING:
		await process_frame
	var pe := manager.player_entry
	var hud := manager.hud
	await create_timer(3.0, false).timeout

	# --- Voltar aos boxes ---
	_check(manager.can_return_to_pit(), "pode voltar aos boxes na corrida")
	await _press("go_to_pit")
	_check(hud.pit_confirm != null and paused, "Select/K abre a confirmação e pausa")
	await _press("ui_cancel")
	_check(hud.pit_confirm == null and not paused and not pe.in_pit_stop, "cancelar fecha sem ir ao box")
	var crossings := pe.crossings
	await _press("go_to_pit")
	await _press("go_to_pit")  # apertar de novo confirma
	await physics_frame
	var box := manager.track.get_pit_box_transform(pe.garage)
	_check(hud.pit_confirm == null and pe.in_pit_stop, "confirmar: pit stop em andamento")
	_check(pe.car.global_position.distance_to(box.origin) < 3.0, "carro no box (%.1f m)" % pe.car.global_position.distance_to(box.origin))
	_check(pe.crossings <= crossings, "volta em andamento recomeça (cruzamentos %d → %d)" % [crossings, pe.crossings])
	_check(not manager.can_return_to_pit(), "parado no box não pede de novo")
	var pits := pe.pit_count
	while pe.in_pit_stop:
		await physics_frame
	_check(pe.pit_count == pits + 1, "pit stop terminou")

	# --- Dano replicado ---
	var a := (manager.entries[1] as RaceEntry).car.get_node("Damage") as CarDamage
	var b := (manager.entries[2] as RaceEntry).car.get_node("Damage") as CarDamage
	var sent: Array = []
	a.hit_applied.connect(func(l: Vector3, d: Vector3, s: float) -> void: sent.append([l, d, s]))
	a._hit(Vector3(0.6, 0.2, 2.2), Vector3(-1, 0, 0), 0.5, a.car.global_transform * Vector3(0.6, 0.2, 2.2), a.car.global_basis.x)
	_check(sent.size() == 1, "batida emite hit_applied")
	var flashes := [0]
	b.part_damaged.connect(func(_p: String, _h: float) -> void: flashes[0] += 1)
	if sent.size() == 1:
		b.remote_hit(sent[0][0], sent[0][1], sent[0][2], a.health.duplicate())
	var same := true
	for piece in a.health:
		if absf(float(a.health[piece]) - float(b.health.get(piece, -1.0))) > 0.001:
			same = false
	_check(same and b.get_overall() < 0.999, "remote_hit copia a resistência (dano %d%%)" % roundi((1.0 - b.get_overall()) * 100.0))
	_check(flashes[0] > 0, "remote_hit avisa o HUD (part_damaged)")

	# --- Contadores da rede ---
	var client := NetRaceClient.new()
	_check(client._counts.size() == NetRaceClient.ACTIONS.size() and NetRaceClient.ACTIONS.has("pass_signal"),
		"um contador por ação (%d), inclusive pedir passagem" % client._counts.size())
	client.free()

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_returnpit_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
