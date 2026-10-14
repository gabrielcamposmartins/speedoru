extends SceneTree
## Teste da Sky Aerobase, a pista no céu (sem janela):
##   godot --headless --path . -s res://tests/sky_aerobase_test.gd
## Gera a pista e confere: comprimento e desnível, sem cruzamentos, pisos (raycast) no grid, nos
## boxes e nas retas, trechos sem barreira (esses, chicane, curva do céu) com área de escape e nada
## embaixo (nem chão: quem passa da borda cai), nada com colisão sobre a pista, plataforma, túnel,
## mar, nuvens e base aérea gerados, e um carro parado em duas curvas.
## Depois, numa corrida com bots: o jogador e um bot que caem da chicane voltam pelo box em pit stop
## (2 s de queda depois de passar da borda), um carro parado na área de escape não cai, e no treino
## (sem RaceControl) a queda também leva ao box.

var scene: Node3D
var track: RaceTrack
var manager: RaceManager
var failures := 0


func _initialize() -> void:
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = "user://test_sky_profile.cfg"
		profile.reset_profile()
	RaceSettings.track = "sky_aerobase"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 5
	RaceSettings.opponents = 2
	RaceSettings.quali_laps = 0
	RaceSettings.skip_menu = true
	_load()
	_run.call_deferred()


func _load() -> void:
	scene = (load("res://scenes/tracks/sky_aerobase.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	track = scene.get_node("Track")
	manager = scene.get_node("RaceManager")


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _hit(from: Vector3, to: Vector3) -> Dictionary:
	return track.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))


func _surface_at(pos: Vector3) -> int:
	var hit := _hit(pos + Vector3.UP * 3.0, pos - Vector3.UP * 3.0)
	return -1 if hit.is_empty() else TrackSurface.of_body(hit.collider)


func _run() -> void:
	while not track.is_built:
		await process_frame
	await _frames(3)
	var p := track.path
	print("Comprimento: %.0f m, %d amostras" % [p.length, p.size()])
	_check(absf(p.length - 3810.0) < 40.0, "comprimento perto dos 3.810 m do traçado")
	var lo := INF
	var hi := -INF
	for v in p.points:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	_check(hi - lo > 30.0 and lo > 0.0, "descida e subida (%.0f a %.0f m)" % [lo, hi])
	_check(p.crossings.is_empty(), "traçado sem cruzamentos")
	# Pisos
	for s in [100.0, 700.0, 1250.0, 1750.0, 2150.0, 2600.0, 3500.0]:
		_check(_surface_at(p.position_at(s)) == TrackSurface.Type.ASPHALT, "asfalto em s=%.0f" % s)
	var grid_ok := true
	for slot in 20:
		grid_ok = grid_ok and _surface_at(track.get_grid_transform(slot).origin) == TrackSurface.Type.ASPHALT
	_check(grid_ok, "posições do grid no asfalto")
	var boxes_ok := true
	for g in track.layout.garage_count:
		boxes_ok = boxes_ok and _surface_at(track.get_pit_box_transform(g).origin) == TrackSurface.Type.ASPHALT
	_check(boxes_ok, "vagas dos boxes na pista dos boxes")
	# Bordas abertas: área de escape, faixa de aviso e o vazio (nada embaixo até o mar)
	for spot: Array in [[455.0, -1, "curva da torre"], [1030.0, -1, "esses"], [1447.0, -1, "grampo"], [1922.0, 1, "curva do portal"], [2460.0, 1, "chicane (esq.)"], [2460.0, -1, "chicane (dir.)"], [2815.0, -1, "curva do céu"]]:
		var s: float = spot[0]
		var side: int = spot[1]
		var i := p.index_at(s)
		_check(track.open_edge(i, side), "%s sem barreira" % spot[2])
		var escape := p.frame_at(s, side * (p.half_width(i, side) + track.barrier[RaceTrack._si(side)][i] - 2.0), 0.0).origin
		_check(_surface_at(escape) == TrackSurface.Type.RUNOFF, "%s: área de escape antes da borda" % spot[2])
		var beyond := p.frame_at(s, side * (track.deck_edge(i, side) + 2.0), 0.0).origin
		_check(_hit(beyond + Vector3.UP * 2.0, beyond + Vector3.DOWN * 2000.0).is_empty(), "%s: nada embaixo além da borda" % spot[2])
	var barrier_at := p.index_at(2600.0)
	_check(not track.open_edge(barrier_at, 1) and not track.open_edge(barrier_at, -1), "reta oposta com barreiras")
	# Nada com colisão sobre a pista (anéis, pórticos, túnel e base aérea são só visuais)
	var blocked := 0
	for s in range(0, int(p.length), 10):
		var pos := p.position_at(s)
		var hit := _hit(pos + Vector3.UP * 60.0, pos + Vector3.UP * 0.5)
		if not hit.is_empty():
			blocked += 1
			print("    s=%d: %s a %.1f m acima" % [s, hit.collider.get_path(), hit.position.y - pos.y])
	_check(blocked == 0, "nada com colisão sobre a pista (%d pontos)" % blocked)
	var gen := track.get_node("Generated")
	_check(gen.find_child("Ground", false, false) == null and gen.find_child("City", false, false) == null, "sem chão nem cidade")
	for n in ["SkyDeck", "Tunnel", "SkyWorld", "SkyBase"]:
		_check(gen.find_child(n, false, false) != null, "gerado: %s" % n)
	var ship := gen.find_child("Tunnel", false, false)
	_check(ship != null and ship.find_child("Ship", false, false) != null, "túnel em forma de nave")
	var engines := gen.find_child("EnginesNacelles", true, false) as MultiMeshInstance3D
	_check(engines != null and engines.multimesh.instance_count > 150, "motores a jato sob a pista (%d)" %
		(engines.multimesh.instance_count if engines else 0))
	# (sem placa de vídeo a MultiMesh não guarda a cor por instância: confere a montagem)
	var bands := gen.find_child("EnginesBands", true, false) as MultiMeshInstance3D
	_check(bands != null and bands.multimesh.use_colors and bands.multimesh.instance_count == engines.multimesh.instance_count
		and SkyDeck.BAND_COLORS.size() == 4, "faixa colorida em cada propulsor (4 cores alternando)")
	var airships := gen.find_children("Airship*", "Node3D", true, false)
	_check(airships.size() >= 10, "dirigíveis-nave (%d)" % airships.size())
	var lowest := INF
	for a: Node3D in airships:
		var pr := p.project(a.global_position)
		var i := p.index_at(pr.x)
		var over := a.global_position.y - p.height_at(pr.x)
		var edge := track.deck_edge(i, 1 if pr.y > 0.0 else -1)
		_check(absf(pr.y) < 700.0, "%s perto da pista (%.0f m)" % [a.name, absf(pr.y)])
		# (a projeção pode cair num trecho mais baixo ao lado: mede até o ponto mais próximo em 3D)
		var near := INF
		var near_y := 0.0
		for v in p.points:
			if v.distance_to(a.global_position) < near:
				near = v.distance_to(a.global_position)
				near_y = v.y
		var rise := a.global_position.y - near_y
		if a.name == "Airship0":
			_check(absf(pr.y) - edge > 15.0 and near < 170.0 and rise > 12.0 and rise < 45.0,
				"dirigível rente à pista (%.0f m da pista, %.0f m acima dela)" % [near, rise])
		elif a.name == "Airship1":
			var open := track.open_edge(i, 1 if pr.y > 0.0 else -1)
			_check(absf(pr.y) - edge > 25.0 and near < 400.0 and rise < -12.0,
				"dirigível abaixo da pista (%.0f m dela, %.0f m abaixo, lado %s)" % [near, -rise, "aberto" if open else "com barreira"])
		else:
			lowest = minf(lowest, over)
	_check(lowest > 30.0, "outros dirigíveis acima dos aros e prédios (o mais baixo a %.0f m)" % lowest)
	_check(gen.find_child("SkyBeams", true, false) != null, "holofotes")
	_check(gen.find_child("Sea", true, false) != null and gen.find_child("CloudDeck", true, false) != null, "mar e tapete de nuvens")
	_check(track.in_tunnel(p.index_at(2150.0)) and not track.in_tunnel(p.index_at(2500.0)), "túnel do reator no lugar")

	# --- Corrida: quedas ---
	while manager.state != RaceManager.State.RACING:
		await process_frame
	await create_timer(2.0, false).timeout
	_check(manager.fall_watch != null, "vigia de quedas ativo na pista no céu")
	var pe := manager.player_entry
	await _parked_test(pe, 453.0, "curva da torre")
	await _parked_test(pe, 1447.0, "grampo")
	# Parado na área de escape da chicane: não cai
	var i_esc := p.index_at(2460.0)
	var esc_lat := -(p.half_width(i_esc, -1) + track.barrier[1][i_esc] - 2.5)
	_place(pe, p.frame_at(2460.0, esc_lat, 0.3), Vector3.ZERO, true)
	await _physics(240)
	_check(not pe.in_pit_stop and FallWatch.grounded(pe.car), "parado na área de escape não cai")
	pe.car.hold = false
	await _fall_test(pe, 2460.0, -1, "jogador")
	await _fall_test(manager.entries[1] as RaceEntry, 2470.0, 1, "bot")
	# LEDs da pista: a cor muda a cada volta de quem lidera
	var lights := track.find_child("SkyLights", true, false) as SkyLights
	var lap := lights.current_lap()
	var leader: RaceEntry = manager.entries[0]
	for e2: RaceEntry in manager.entries:
		if e2.laps_completed() >= leader.laps_completed():
			leader = e2
	var before := leader.crossings
	leader.crossings = maxi(before, 1) + 1
	await create_timer(2.0, false).timeout
	_check(lights.current_lap() == lap + 1 and lights._color == SkyLights.color_for_lap(lap + 1)
		and lights._color != SkyLights.color_for_lap(lap), "LEDs mudam de cor na volta seguinte (%d → %d)" % [lap, lap + 1])
	leader.crossings = before

	# --- Treino (sem RaceControl): a queda também leva ao box ---
	scene.queue_free()
	await _frames(3)
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	_load()
	while manager.state != RaceManager.State.PRACTICE:
		await process_frame
	await create_timer(1.0, false).timeout
	_check(manager.control == null, "treino sem controle de prova")
	await _fall_test(manager.player_entry, 2460.0, -1, "jogador no treino")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_sky_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)


## Põe o carro em xf com velocidade; hold = freado (como no box), para os testes de carro parado.
func _place(e: RaceEntry, xf: Transform3D, velocity: Vector3, hold := false) -> void:
	e.car.hold = hold
	e.car.global_transform = xf
	e.car.linear_velocity = velocity
	e.car.angular_velocity = Vector3.ZERO
	e.car.reset_physics_interpolation()
	e.car.throttle_input = 0.0
	e.car.brake_input = 1.0


## O carro sai pela borda aberta (de lado, a 15 m/s): 2 s depois de começar a cair está no box em
## pit stop, que depois termina contando uma parada.
func _fall_test(e: RaceEntry, s: float, side: int, label: String) -> void:
	var p := track.path
	var i := p.index_at(s)
	var edge := track.deck_edge(i, side)
	var xf := p.frame_at(s, side * (edge - 1.0), 0.4)
	var pits := e.pit_count
	_place(e, xf, p.lefts[i] * side * 15.0 + p.tangents[i] * 10.0)
	var steps := 0
	var fall_step := -1
	while not e.in_pit_stop and steps < 120 * 6:
		await physics_frame
		steps += 1
		if fall_step < 0 and manager.fall_watch.is_falling(e):
			fall_step = steps
			if e == manager.player_entry:
				var cam := scene.get_node("RaceCamera") as RaceCamera
				_check(cam.is_target_falling(), "%s: a câmera de corrida também vê a queda" % label)
	var hz := float(Engine.physics_ticks_per_second)
	var elapsed := steps / hz
	var falling := (steps - fall_step) / hz if fall_step >= 0 else INF
	var box := track.get_pit_box_transform(e.garage)
	print("  %s: no box %.2f s depois de sair pela borda (%.2f s caindo)" % [label, elapsed, falling])
	_check(e.in_pit_stop and falling <= FallWatch.FALL_TIME + 0.1 and elapsed <= 4.0, "%s caiu e voltou pelo box (2 s de queda)" % label)
	_check(e.car.global_position.distance_to(box.origin) < 4.0, "%s parado na vaga do box (%.1f m)" % [label,
		e.car.global_position.distance_to(box.origin)])
	var waited := 0
	while e.in_pit_stop and waited < 120 * 20:
		await physics_frame
		waited += 1
	_check(not e.in_pit_stop and e.pit_count == pits + 1, "%s: a queda contou como pit stop" % label)


## Carro parado (freado) numa curva: não afunda nem desliza.
func _parked_test(e: RaceEntry, s: float, label: String) -> void:
	_place(e, track.path.frame_at(s, 0.0, 0.3), Vector3.ZERO, true)
	await _physics(240)
	var car := e.car
	var pr := track.path.project(car.global_position)
	var height := car.global_position.y - track.path.position_at(pr.x).y
	var moved := fposmod(pr.x - s + track.path.length * 0.5, track.path.length) - track.path.length * 0.5
	print("  %s: altura %.2f m, andou %.2f m" % [label, height, moved])
	_check(height > -0.2 and height < 1.0, "carro apoiado na pista na %s" % label)
	_check(absf(moved) < 1.5, "carro freado não desliza na %s" % label)
	car.hold = false


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _physics(n: int) -> void:
	for k in n:
		await physics_frame
