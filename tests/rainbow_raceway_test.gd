extends SceneTree
## Teste da Rainbow Raceway, a pista fofa nas nuvens (sem janela):
##   godot --headless --path . -s res://tests/rainbow_raceway_test.gd
## Gera a pista e confere: comprimento e desnível, a espiral passando por baixo da Reta do Mirante
## (um cruzamento só, folga entre os níveis, projeção no nível certo, asfalto em cima e embaixo), pisos
## (raycast) nas retas, no túnel e na espiral, o grid e os 14 boxes (MAX_GRID), barreira dos dois lados
## em TODA a volta (ninguém cai: sem vigia de quedas), a laje de colisão, vão livre sobre a pista toda
## e nada acima do asfalto, o mundo das nuvens gerado (almofadas, Túnel do Arco-Íris, ilhas, castelo,
## arcos, pelúcias, enfeites e o céu), arcos, caixas de presente e o resto sempre altos sobre a pista,
## as nuvens da pista de cima sem descer sobre a de baixo, as ilhas longe da plataforma, as pelúcias
## atrás das barreiras, placas, cachoeiras e marcos, a noite (luzes acesas) e o ambiente de volta ao
## normal ao sair, e um carro parado (freado) no grampo, na espiral, em cima e embaixo da ponte e na
## chicane sem deslizar.

var scene: Node3D
var track: RaceTrack
var manager: RaceManager
var failures := 0
const PROFILE := "user://test_rainbow_profile.cfg"
const ACCOUNT := "user://test_rainbow_account.cfg"
## Altura mínima de tudo o que fica sobre o asfalto (arcos, faixa da largada, caixas), m.
const OVERHEAD := 5.5


func _initialize() -> void:
	# (a conta do jogador e o servidor de verdade ficam de fora)
	var net := root.get_node_or_null("Net")
	if net:
		net.account_file = ACCOUNT
		net.server_host = "127.0.0.1"
		net.server_port = 9
	var profile := root.get_node_or_null("Profile") as PlayerProfile
	if profile:
		PlayerProfile.save_path = PROFILE
		profile.reset_profile()
	RaceSettings.track = "rainbow_raceway"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 5
	RaceSettings.opponents = 2
	RaceSettings.quali_laps = 0
	RaceSettings.skip_menu = true
	scene = (load("res://scenes/tracks/rainbow_raceway.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	track = scene.get_node("Track")
	manager = scene.get_node("RaceManager")
	_run.call_deferred()


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
	_check(absf(p.length - 4226.0) < 40.0, "comprimento perto dos 4.226 m do traçado")
	var lo := INF
	var hi := -INF
	for v in p.points:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	_check(hi - lo > 25.0 and hi - lo < 40.0, "desnível de %.0f m (%.0f a %.0f m)" % [hi - lo, lo, hi])
	# Cruzamento: a espiral passa por baixo da Reta do Mirante
	_check(p.crossings.size() == 1, "um cruzamento (%d)" % p.crossings.size())
	if p.crossings.is_empty():
		_finish()
		return
	var c := p.crossings[0]
	var low := p.position_at(c.x)
	var up := p.position_at(c.y)
	print("  cruzamento: s=%.0f (%.1f m) sob s=%.0f (%.1f m), %.0f°" % [c.x, low.y, c.y, up.y, rad_to_deg(c.z)])
	_check(up.y - low.y > 15.0, "folga de %.1f m entre os níveis" % (up.y - low.y))
	_check(c.y > 2190.0 and c.y < 2360.0 and c.x > 2705.0 and c.x < 2980.0, "a Reta do Mirante por cima da Passagem do Arco-Íris")
	var pr_low := p.project(low + Vector3.UP * 0.4)
	var pr_up := p.project(up + Vector3.UP * 0.4)
	_check(absf(pr_low.x - c.x) < 3.0, "projeção embaixo da ponte fica no trecho de baixo (s=%.0f)" % pr_low.x)
	_check(absf(pr_up.x - c.y) < 3.0, "projeção em cima da ponte fica no trecho de cima (s=%.0f)" % pr_up.x)
	_check(_surface_at(up) == TrackSurface.Type.ASPHALT, "asfalto em cima da ponte")
	_check(_surface_at(low) == TrackSurface.Type.ASPHALT, "asfalto embaixo da ponte")
	# Pisos
	for s in [100.0, 600.0, 1100.0, 1750.0, 2250.0, 2500.0, 2650.0, 3100.0, 3500.0, 4000.0]:
		_check(_surface_at(p.position_at(s)) == TrackSurface.Type.ASPHALT, "asfalto em s=%.0f" % s)
	var grid_ok := true
	for slot in 20:
		grid_ok = grid_ok and _surface_at(track.get_grid_transform(slot).origin) == TrackSurface.Type.ASPHALT
	_check(grid_ok, "posições do grid no asfalto")
	_check(track.layout.garage_count >= NetProtocol.MAX_GRID, "boxes para o grid inteiro (%d)" % track.layout.garage_count)
	var boxes_ok := true
	for g in track.layout.garage_count:
		boxes_ok = boxes_ok and _surface_at(track.get_pit_box_transform(g).origin) == TrackSurface.Type.ASPHALT
	_check(boxes_ok, "vagas dos boxes na pista dos boxes")
	_check(track.garage_s(track.layout.garage_count - 1) < -30.0, "boxes antes da linha de chegada (a última vaga em s=%.0f)" %
		track.garage_s(track.layout.garage_count - 1))
	# Barreiras em toda a volta: nenhuma borda aberta e um raio de dentro da pista bate nelas
	var open := 0
	var missed := 0
	for i in range(0, p.size(), 2):
		for side in [1, -1]:
			if track.open_edge(i, side):
				open += 1
				continue
			var k := RaceTrack._si(side)
			var from := p.points[i] + Vector3.UP * 1.0
			var reach := p.half_width(i, side) + track.barrier[k][i] + 1.5
			if track.layout.has_pit and side == track.layout.pit_side and track.pit_width[i] > 0.0:
				reach += track.pit_width[i] + 1.5
			var hit := _hit(from, from + p.lefts[i] * side * reach)
			if hit.is_empty() or TrackSurface.of_body(hit.collider) != TrackSurface.Type.BARRIER:
				missed += 1
				if missed <= 5:
					print("    sem barreira em s=%.0f lado %d" % [p.s_at(i), side])
	_check(open == 0, "nenhuma borda aberta (%d)" % open)
	_check(missed == 0, "barreira dos dois lados em toda a volta (%d pontos sem)" % missed)
	_check(track.find_child("DeckFloor", true, false) != null, "laje de colisão sob os pisos")
	# Vão livre sobre a pista toda (o que fica no alto não tem colisão; a ponte fica 19 m acima)
	var blocked := 0
	for s in range(0, int(p.length), 6):
		for lat: float in [-4.0, 0.0, 4.0]:
			var pos := p.position_at(s, lat)
			var hit := _hit(pos + Vector3.UP * 0.5, pos + Vector3.UP * 8.0)
			if not hit.is_empty():
				blocked += 1
				if blocked <= 6:
					print("    s=%d lat %.0f: %s a %.1f m acima" % [s, lat, hit.collider.get_path(), hit.position.y - pos.y])
	_check(blocked == 0, "vão livre de 8 m sobre a pista toda (%d pontos)" % blocked)
	# Nada acima do asfalto: de 1,2 m acima, o primeiro piso é a pista. (Fora das amostras de 2 m: um
	# raio que passa exatamente num vértice da malha de colisão pode atravessar)
	var bumps := 0
	for s0 in range(0, int(p.length), 2):
		var s := s0 + 0.37
		for lat: float in [-0.85, 0.0, 0.85]:
			var i := p.index_at(s)
			var pos := p.position_at(s, lat * p.half_width(i, 1 if lat > 0.0 else -1))
			var hit := _hit(pos + Vector3.UP * 1.2, pos - Vector3.UP * 0.5)
			if hit.is_empty() or hit.collider is RigidBody3D:
				continue
			var type := TrackSurface.of_body(hit.collider)
			if not type in [TrackSurface.Type.ASPHALT, TrackSurface.Type.KERB] or hit.position.y > pos.y + 0.08:
				bumps += 1
				if bumps <= 6:
					print("    s=%d lat %.2f: %s a %.2f m" % [s, lat, (hit.collider as Node).name, hit.position.y - pos.y])
	_check(bumps == 0, "nada acima do asfalto na pista toda (%d pontos)" % bumps)
	# O mundo das nuvens
	var gen := track.get_node("Generated")
	for n in ["CloudDeck", "RainbowTunnel", "CloudIslands", "CandyCastle", "HeartArches", "PlushFriends", "CloudProps", "CloudWorld"]:
		_check(gen.get_node_or_null(n) != null, "gerado: %s" % n)
	_check(track.start_lights != null, "luzes de largada")
	_check(track.in_tunnel(p.index_at(1750.0)) and not track.in_tunnel(p.index_at(1950.0)), "Túnel do Arco-Íris no lugar")
	# Tudo o que passa por cima do asfalto fica alto (malhas dos arcos, da faixa da largada, das bengalas
	# e das caixas de presente)
	var low_over := 0
	var checked := 0
	var meshes: Array[MeshInstance3D] = []
	for name: String in ["HeartArches/Arches", "CloudProps/Props"]:
		var mi := gen.get_node_or_null(name) as MeshInstance3D
		if mi:
			meshes.append(mi)
	for mi in meshes:
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for k in range(0, verts.size(), 3):
			var v := mi.global_transform * verts[k]
			var pr := p.project(v, true, true)
			var i := p.index_at(pr.x)
			var side := 1 if pr.y > 0.0 else -1
			# (o que fica embaixo da pista de cima do cruzamento não está sobre ela)
			if absf(pr.y) > p.half_width(i, side) + 0.3 or v.y < p.position_at(pr.x).y - 1.0 or v.y - p.points[i].y > 40.0:
				continue
			checked += 1
			if v.y - p.position_at(pr.x).y < OVERHEAD:
				low_over += 1
				if low_over <= 5:
					print("    %s: vértice a %.1f m sobre a pista em s=%.0f" % [mi.name, v.y - p.position_at(pr.x).y, pr.x])
	_check(checked > 500 and low_over == 0, "arcos e enfeites a mais de %.1f m sobre o asfalto (%d de %d)" % [OVERHEAD, low_over, checked])
	var gifts := gen.get_node_or_null("CloudProps/GiftBoxes") as MultiMeshInstance3D
	var gifts_low := 0
	if gifts:
		for at: Vector3 in gifts.get_meta("points", PackedVector3Array()):
			if at.y - p.position_at(p.project(at).x).y < CloudProps.GIFT_HEIGHT - 1.6:
				gifts_low += 1
	_check(gifts != null and gifts.multimesh.instance_count >= 12 and gifts_low == 0, "caixas de presente no alto (%d)" %
		(gifts.multimesh.instance_count if gifts else 0))
	# As nuvens sob a pista de cima não descem sobre a de baixo
	var deck := gen.get_node("CloudDeck")
	var over_lower := 0
	var near_cross := 0
	for mmi: MultiMeshInstance3D in deck.find_children("Puffs*", "MultiMeshInstance3D", false, false):
		if mmi.name.begins_with("PuffsFar"):
			continue
		var origins: PackedVector3Array = mmi.get_meta("points", PackedVector3Array())
		var bottoms: PackedFloat32Array = mmi.get_meta("bottoms", PackedFloat32Array())
		for k in origins.size():
			var o := origins[k]
			if Vector2(o.x - low.x, o.z - low.z).length() > 80.0 or o.y < low.y + 4.0:
				continue
			near_cross += 1
			var bottom := bottoms[k]
			var pr := p.project(Vector3(o.x, low.y + 1.0, o.z), true, true)
			var i := p.index_at(pr.x)
			var reach := p.half_width(i, 1 if pr.y > 0.0 else -1) + 3.0
			if absf(pr.y) < reach and bottom < low.y + CloudDeck.CROSS_CLEARANCE - 0.5:
				over_lower += 1
	_check(near_cross > 10 and over_lower == 0, "nuvens da ponte acima da pista de baixo (%d de %d)" % [over_lower, near_cross])
	# Ilhas longe da plataforma da pista
	var islands := gen.get_node("CloudIslands")
	var pts: Array = islands.get_meta("points", [])
	var radii: Array = islands.get_meta("radii", [])
	var too_close := 0
	for k in pts.size():
		var q: Vector3 = pts[k]
		var pr := p.project(q, true, false)
		var i := p.index_at(pr.x)
		var side := 1 if pr.y > 0.0 else -1
		var gap := absf(pr.y) - track.deck_edge(i, side) - float(radii[k])
		if gap < CloudIslands.TRACK_GAP * 0.5 - 1.0:
			too_close += 1
			print("    ilha %d (r %.0f) a %.1f m da plataforma" % [k, radii[k], gap])
	_check(pts.size() >= 50 and too_close == 0, "ilhas voadoras longe da plataforma (%d, %d perto demais)" % [pts.size(), too_close])
	_check(int(islands.get_meta("waterfalls", 0)) >= 12, "cachoeiras (%d)" % islands.get_meta("waterfalls", 0))
	var decor := islands.get_node("Decor")
	_check(int(decor.get_meta("count", 0)) > 1500 and int(decor.get_meta("houses", 0)) >= 15,
		"enfeites nas ilhas (%d, %d casinhas de cupcake)" % [decor.get_meta("count", 0), decor.get_meta("houses", 0)])
	# Marcos: castelo, torre no meio da espiral, arco da largada, arco-íris, portais, ponte
	var tower := CloudIslands.landmark(track, "tower")
	var tc: Vector3 = tower.pos
	var spiral_gap := INF
	for s in range(2370, 2700, 4):
		spiral_gap = minf(spiral_gap, Vector2(p.position_at(s).x - tc.x, p.position_at(s).z - tc.z).length())
	_check(spiral_gap > 40.0 and spiral_gap < 75.0, "Torre de Algodão-Doce no meio da espiral (pista a %.0f m)" % spiral_gap)
	var arches := gen.get_node("HeartArches")
	_check(int(arches.get_meta("start", 0)) == 1 and int(arches.get_meta("rainbows", 0)) >= 5 and int(arches.get_meta("garlands", 0)) >= 7
		and int(arches.get_meta("bridges", 0)) == 1, "arco da largada, arco-íris, portais de pirulito e a ponte do arco-íris")
	# Pelúcias atrás das barreiras, o gigante e o piquenique
	var plush := gen.get_node("PlushFriends")
	var in_front := 0
	var trackside := 0
	for mmi: MultiMeshInstance3D in plush.find_children("Trackside_*", "MultiMeshInstance3D", false, false):
		for at: Vector3 in mmi.get_meta("points", PackedVector3Array()):
			trackside += 1
			var pr := p.project(at, true, true)
			var i := p.index_at(pr.x)
			var side := 1 if pr.y > 0.0 else -1
			if absf(pr.y) < p.half_width(i, side) + track.barrier[RaceTrack._si(side)][i] + TrackBarriers.CLOUD_THICK:
				in_front += 1
	_check(trackside >= 40 and in_front == 0, "pelúcias na beira da pista atrás das barreiras (%d, %d na frente)" % [trackside, in_front])
	_check(plush.get_node_or_null("GiantBear") != null and int(plush.get_meta("count", 0)) >= 60,
		"ursinho gigante e a turma toda (%d)" % plush.get_meta("count", 0))
	var props := gen.get_node("CloudProps")
	_check(int(props.get_meta("signs", 0)) >= 10 and props.has_meta("title") and int(props.get_meta("balloons", 0)) >= 15
		and int(props.get_meta("stars", 0)) >= 20, "placas (%d), letreiro, balões (%d) e estrelas" % [props.get_meta("signs", 0),
		props.get_meta("balloons", 0)])
	var labels := props.find_children("*", "Label3D", false, false)
	_check(labels.size() >= 25, "textos das placas (%d)" % labels.size())
	# Noite: as luzes dos postes acendem; o ambiente que a pista mexe volta ao sair
	var daylight := scene.get_node("Daylight") as Daylight
	var env := (scene.get_node("Daylight/WorldEnvironment") as WorldEnvironment).environment
	var aerial_before: float = env.fog_aerial_perspective
	daylight.time_of_day = DaylightPresets.TimeOfDay.NIGHT
	await _frames(3)
	var lit := 0
	for l in get_nodes_in_group("night_lights"):
		if (l as Light3D).visible and track.is_ancestor_of(l):
			lit += 1
	_check(lit > 40, "noite: luzes dos postes acesas (%d)" % lit)
	daylight.time_of_day = DaylightPresets.TimeOfDay.DAY
	await _frames(3)

	# --- Corrida: sem quedas; carro parado nas curvas, em cima e embaixo da ponte ---
	while manager.state != RaceManager.State.RACING:
		await process_frame
	await create_timer(1.0, false).timeout
	_check(manager.fall_watch == null, "sem vigia de quedas (barreiras em toda a volta)")
	# A linha de corrida dos bots não mistura os dois níveis no cruzamento (a altura vai no CSV): na
	# Reta do Mirante e na Passagem do Arco-Íris, perto do cruzamento, o alvo é de reta
	var bot_entry: RaceEntry = null
	for e in manager.entries:
		if e.bot:
			bot_entry = e
			break
	if bot_entry:
		var up_kmh := RacingLine.sample(bot_entry.bot.profile, p, c.y - 25.0) * 3.6
		var low_kmh := RacingLine.sample(bot_entry.bot.profile, p, c.x + 25.0) * 3.6
		_check(up_kmh > 200.0 and low_kmh > 150.0, "bots em velocidade de reta no cruzamento (em cima %.0f km/h, embaixo %.0f km/h)" %
			[up_kmh, low_kmh])
	else:
		_check(false, "um bot na corrida")
	var pe := manager.player_entry
	await _parked_test(pe, 1222.0, "no Grampo do Castelo")
	await _parked_test(pe, 2500.0, "na Espiral do Algodão-Doce")
	await _parked_test(pe, c.y, "em cima da ponte")
	await _parked_test(pe, c.x, "embaixo da ponte")
	await _parked_test(pe, 3205.0, "na Chicane da Estrela")
	# Saindo da pista, o ambiente (compartilhado com as outras) volta ao que era
	var env_out := env
	scene.queue_free()
	await _frames(3)
	_check(absf(env_out.fog_aerial_perspective - 0.6) < 0.01 and absf(env_out.adjustment_saturation - 1.08) < 0.001,
		"ao sair, perspectiva aérea e saturação voltam (%.2f e %.2f; com a pista: %.2f)" % [env_out.fog_aerial_perspective,
		env_out.adjustment_saturation, aerial_before])
	_finish()


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ACCOUNT))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)


## Põe o carro em xf, freado (como no box), sem velocidade.
func _place(e: RaceEntry, xf: Transform3D) -> void:
	e.car.hold = true
	e.car.global_transform = xf
	e.car.linear_velocity = Vector3.ZERO
	e.car.angular_velocity = Vector3.ZERO
	e.car.reset_physics_interpolation()
	e.car.throttle_input = 0.0
	e.car.brake_input = 1.0


## Carro parado (freado) numa curva ou rampa: não afunda nem desliza.
func _parked_test(e: RaceEntry, s: float, label: String) -> void:
	_place(e, track.path.frame_at(s, 0.0, 0.3))
	await _physics(240)
	var car := e.car
	var pr := track.path.project(car.global_position)
	var height := car.global_position.y - track.path.position_at(pr.x).y
	var moved := fposmod(pr.x - s + track.path.length * 0.5, track.path.length) - track.path.length * 0.5
	print("  %s: altura %.2f m, andou %.2f m" % [label, height, moved])
	_check(height > -0.2 and height < 1.0, "carro apoiado na pista %s" % label)
	_check(absf(moved) < 1.5, "carro freado não desliza %s" % label)


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _physics(n: int) -> void:
	for k in n:
		await physics_frame
