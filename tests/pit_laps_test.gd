extends SceneTree
## Voltas e boxes (sem janela): o carro do jogador anda pela pista conduzido pelo teste (rápido, sem
## física) e vai aos boxes de todos os jeitos — "voltar aos boxes" no começo, no meio e no fim da
## volta, duas vezes seguidas, logo depois de cruzar a linha, e parando na vaga dirigindo. Confere:
## * cada volta contada foi percorrida de verdade (a volta em andamento recomeça no box);
## * termina com exatamente as voltas da corrida, e as voltas param de contar depois da bandeirada;
## * o limitador continua ligado depois do pit stop (só o jogador desliga);
## * classificação final e posições: quem levou volta e recebeu a bandeirada fica atrás de quem
##   completou mais voltas, mesmo que esse ainda não tenha cruzado a linha.
##   godot --headless --path . -s res://tests/pit_laps_test.gd -- [pistas: monza,monaco,suzuka]
## Perfil de teste: user://test_pitlaps_profile.cfg (apagado no fim).

const LAPS := 4
## Passo do carro conduzido (m por passo de física).
const STEP := 18.0
## Distância máxima entre o box e a linha de chegada (a volta recomeça no box).
const BOX_SLACK := 700.0

var failures := 0
var manager: RaceManager
var car: F1Car
var entry: RaceEntry
var path: TrackPath
var s := 0.0
var lateral := 0.0
## Distância percorrida desde a última volta contada (ou desde o box, onde a volta recomeça).
var since_count := 0.0
var last_laps := 0
var short_laps := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _run() -> void:
	PlayerProfile.save_path = "user://test_pitlaps_profile.cfg"
	(root.get_node("Profile") as PlayerProfile).reset_profile()
	var tracks := ["monza", "monaco", "suzuka"]
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			tracks = Array(a.split(","))
	for id: String in tracks:
		await _track(id)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_pitlaps_profile.cfg"))
	print("\npit_laps_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)


func _track(id: String) -> void:
	print("\n== %s" % id)
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = LAPS
	RaceSettings.opponents = 3
	RaceSettings.difficulty = 1
	RaceSettings.track = id
	RaceSettings.grid = RaceSettings.Grid.MIDDLE
	RaceSettings.mandatory_pits = 0
	RaceSettings.skip_menu = true
	var scene := (load(RaceSettings.track_scene(id)) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	manager = scene.get_node("RaceManager") as RaceManager
	while manager.state != RaceManager.State.RACING:
		await process_frame
	entry = manager.player_entry
	car = entry.car
	car.freeze = true
	path = manager.track.path
	s = entry.s if entry.crossings >= 1 else entry.s - path.length
	lateral = 0.0
	since_count = 0.0
	last_laps = 0
	short_laps = 0
	var length := path.length

	# Volta 1: "voltar aos boxes" a 30% da volta
	await _drive_to_fraction(0.3)
	await _return_to_pit("a 30% da volta")
	# Volta seguinte: no fim da volta (perto da linha)
	await _drive_to_fraction(0.93)
	await _return_to_pit("no fim da volta")
	# Duas vezes seguidas (logo ao sair do box)
	await _drive(60.0)
	await _return_to_pit("de novo ao sair do box")
	# Logo depois de cruzar a linha
	await _drive_to_fraction(0.02)
	await _return_to_pit("logo depois da linha")
	# Pit stop dirigindo até a vaga, com o limitador ligado
	await _drive_to_fraction(0.5)
	await _pit_stop_driving()
	# Até a bandeirada
	var guard := 0
	while not entry.finished and guard < 20000:
		await _drive(STEP)
		guard += 1
	_check(entry.finished, "recebeu a bandeirada")
	_check(entry.laps_completed() == LAPS, "terminou com %d voltas (corrida de %d)" % [entry.laps_completed(), LAPS])
	_check(short_laps == 0, "nenhuma volta contada sem ser percorrida (%d curtas)" % short_laps)
	# Volta de desaceleração: cruzar a linha de novo não conta mais
	await _drive(length + 200.0)
	_check(entry.laps_completed() == LAPS, "depois da bandeirada as voltas não aumentam (%d)" % entry.laps_completed())
	_classification()
	scene.queue_free()
	current_scene = null
	for i in 5:
		await process_frame


## Anda `dist` metros pela pista (STEP por passo de física), voltando à linha central aos poucos.
func _drive(dist: float) -> void:
	var left := dist
	while left > 0.0:
		var step := minf(STEP, left)
		left -= step
		s += step
		since_count += step
		lateral = move_toward(lateral, 0.0, 0.6)
		car.global_transform = path.frame_at(s, lateral, 0.6)
		await physics_frame
		_watch_laps()


## Anda até a fração `f` da volta (a partir da linha de chegada).
func _drive_to_fraction(f: float) -> void:
	var length := path.length
	var target := f * length
	var cur := fposmod(s, length)
	var dist := fposmod(target - cur, length)
	if dist < 1.0:
		dist += length
	await _drive(dist)


func _watch_laps() -> void:
	var done := entry.laps_completed()
	if done > last_laps:
		if since_count < path.length - BOX_SLACK:
			short_laps += 1
			print("    volta %d contada com só %.0f m percorridos" % [done, since_count])
		since_count = 0.0
		last_laps = done


## "Voltar aos boxes" (com a confirmação já aceita): o carro vai para a vaga, a volta recomeça.
func _return_to_pit(label: String) -> void:
	var before := entry.laps_completed()
	_check(manager.can_return_to_pit(), "pode voltar aos boxes %s" % label)
	manager.return_to_pit()
	await physics_frame
	await _wait_stop()
	_check(entry.laps_completed() == before, "voltar aos boxes %s não muda as voltas (%d → %d)" % [label, before, entry.laps_completed()])
	_from_box()


## Para na vaga dirigindo (entra pela faixa dos boxes) com o limitador ligado.
func _pit_stop_driving() -> void:
	var box := manager.track.get_pit_box_transform(entry.garage)
	var pr := path.project(box.origin)
	var length := path.length
	# Até 250 m antes da vaga pela pista, depois desvia para a faixa dos boxes
	var start := pr.x - 250.0
	await _drive(fposmod(start - fposmod(s, length), length))
	car.limiter_on = true
	var target_lat := pr.y
	var left := 250.0
	while left > 0.0:
		var step := minf(8.0, left)
		left -= step
		s += step
		since_count += step
		lateral = lerpf(lateral, target_lat, 0.15) if left > 40.0 else target_lat
		car.global_transform = path.frame_at(s, lateral, 0.6)
		await physics_frame
		_watch_laps()
	car.global_transform = box
	var t := 0
	while not entry.in_pit_stop and t < 240:
		await physics_frame
		t += 1
	_check(entry.in_pit_stop, "parou na vaga (pit stop começou)")
	await _wait_stop()
	_check(car.limiter_on, "limitador continua ligado depois do pit stop")
	car.limiter_on = false
	_from_box()


func _wait_stop() -> void:
	var t := 0
	while entry.in_pit_stop and t < 120 * 30:
		await physics_frame
		t += 1


## Continua da vaga (a volta em andamento recomeçou ali).
func _from_box() -> void:
	var pr := path.project(car.global_position)
	s = pr.x
	lateral = pr.y
	since_count = 0.0
	# Ao sair do box para trás da linha, a mesma volta recomeça ao cruzá-la
	last_laps = entry.laps_completed()


## Classificação com um carro que levou volta e já recebeu a bandeirada.
func _classification() -> void:
	var length := path.length
	var list: Array[RaceEntry] = []
	for e in manager.entries:
		if e != entry:
			list.append(e)
	var a := list[0]
	var b := list[1]
	var c := list[2]
	var p := entry
	# a: venceu (4 voltas); p: terminou depois, com as 4; b: levou volta e recebeu a bandeirada
	# (3 voltas) — e depois cruzou a linha de novo; c: 3 voltas completas, ainda na última
	for e in [a, b, c, p]:
		e.retired = false
		e.disqualified = false
		e.penalty_seconds = 0.0
	a.finished = true
	a.finish_laps = LAPS
	a.finish_time = 300.0
	a.crossings = LAPS + 2
	p.finished = true
	p.finish_laps = LAPS
	p.finish_time = 305.0
	p.crossings = LAPS + 1
	b.finished = true
	b.finish_laps = LAPS - 1
	b.finish_time = 302.0
	b.crossings = LAPS + 1
	b.progress = LAPS * length + 100.0
	c.finished = false
	c.crossings = LAPS
	c.progress = (LAPS - 1) * length + 1500.0
	var order := manager.final_classification()
	var names := order.map(func(e: RaceEntry) -> String: return e.code)
	_check(order[0] == a and order[1] == p and order[2] == c and order[3] == b,
		"classificação: vencedor, 2º, quem ainda corre com mais voltas e por fim quem levou volta (%s)" % ", ".join(names))
	_check(b.laps_completed() == LAPS - 1, "quem levou volta fica com as voltas da bandeirada (%d)" % b.laps_completed())
	manager._native_update_positions()
	_check(a.position == 1 and p.position == 2 and c.position == 3 and b.position == 4,
		"posições ao vivo na mesma ordem (%d, %d, %d, %d)" % [a.position, p.position, c.position, b.position])
	var text := manager.interval_text(b)
	_check(text.contains("VOLTA"), "intervalo de quem levou volta: %s" % text)
