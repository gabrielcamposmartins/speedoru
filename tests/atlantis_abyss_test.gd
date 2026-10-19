extends SceneTree
## Teste da Atlantis Abyss, a pista no fundo do mar (sem janela):
##   godot --headless --path . -s res://tests/atlantis_abyss_test.gd
## Gera a pista e confere: comprimento, que ela desce abaixo e sobe acima da linha d'água (Portão de
## Poseidon), sem cruzamentos, pisos (raycast) nas retas, no túnel, na subida, no trecho emerso, no
## grid e nos 14 boxes (MAX_GRID), barreira dos dois lados em TODA a volta (ninguém cai: sem vigia de
## quedas), laje de colisão sob os pisos, nada com colisão sobre a pista, túnel de cristal no lugar,
## o mundo do mar gerado (leito, aqueduto, ruínas, Portão com cachoeiras, água e bichos), o cânion na
## maior parte da pista submersa (paredes fora do tubo com a inclinação variando, luzes coloridas,
## ruínas e pontes de aqueduto fora do tubo) virando montanhas acima do mar no trecho emerso (com as
## cachoeiras grandes e largas fora da laje, os aquedutos, os cipós e as árvores debruçadas por cima
## da pista e as bandeiras nas cristas), os vulcões perto do tubo, as relíquias dos trechos abertos
## (naufrágios, praças, arcos de pedra, poças de vida) fora do tubo, os corais elaborados, as
## cavernas, os estandartes no tubo e no aqueduto, os bichos grandes nos trechos abertos, as baleias
## grandes perto do tubo, os barcos perto da pista e a janela do céu do espelho d'água, a troca de ambiente na linha d'água (e o Environment de
## volta ao normal ao sair da pista), as gotas na tela e o som saindo da água e um carro parado
## (freado) nas curvas e nas rampas sem deslizar.

var scene: Node3D
var track: RaceTrack
var manager: RaceManager
var failures := 0
## Névoa fora d'água (medida no trecho emerso).
var above_fog := 0.0
const PROFILE := "user://test_atlantis_profile.cfg"
const ACCOUNT := "user://test_atlantis_account.cfg"


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
	RaceSettings.track = "atlantis_abyss"
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.laps = 5
	RaceSettings.opponents = 2
	RaceSettings.quali_laps = 0
	RaceSettings.skip_menu = true
	scene = (load("res://scenes/tracks/atlantis_abyss.tscn") as PackedScene).instantiate()
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
	var water := track.layout.water_level
	print("Comprimento: %.0f m, %d amostras" % [p.length, p.size()])
	_check(absf(p.length - 4732.0) < 40.0, "comprimento perto dos 4.732 m do traçado")
	var lo := INF
	var hi := -INF
	var above := 0.0
	for v in p.points:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
		if v.y > water:
			above += p.spacing
	_check(lo < water - 20.0 and hi > water + 3.0, "abaixo e acima da linha d'água (%.0f a %.0f m; água a %.0f m)" % [lo, hi, water])
	_check(above > 400.0 and above < 900.0, "trecho emerso de %.0f m" % above)
	_check(p.crossings.is_empty(), "traçado sem cruzamentos")
	# Pisos
	for s in [100.0, 700.0, 1200.0, 1750.0, 2150.0, 2500.0, 2870.0, 3300.0, 4000.0]:
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
	# Vaga perto da linha: o carro passa um pouco dela ao parar e a volta conta duas vezes
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
	# Nada com colisão sobre a pista (túnel, arcos e estátuas são só visuais)
	var blocked := 0
	for s in range(0, int(p.length), 10):
		var pos := p.position_at(s)
		var hit := _hit(pos + Vector3.UP * 60.0, pos + Vector3.UP * 0.5)
		if not hit.is_empty():
			blocked += 1
			print("    s=%d: %s a %.1f m acima" % [s, hit.collider.get_path(), hit.position.y - pos.y])
	_check(blocked == 0, "nada com colisão sobre a pista (%d pontos)" % blocked)
	var gen := track.get_node("Generated")
	_check(gen.find_child("Ground", false, false) == null and gen.find_child("City", false, false) == null, "sem campo nem cidade")
	for n in ["SeaFloor", "Causeway", "SeaTube", "Tunnel", "Canyon", "Ruins", "Vents", "PoseidonGate", "SeaLife", "Reef", "SeaWorld"]:
		_check(gen.find_child(n, false, false) != null, "gerado: %s" % n)
	_check(track.in_tunnel(p.index_at(1200.0)) and not track.in_tunnel(p.index_at(1500.0)), "túnel de cristal no lugar")
	# Tubo de vidro: toda a pista debaixo d'água fica dentro dele ou do túnel (os carros no seco)
	var wet := 0
	var uncovered := 0
	for i in p.size():
		if p.points[i].y < water - 0.5:
			wet += 1
			if not SeaTube.covers(track, i) and not track.in_tunnel(i):
				uncovered += 1
	_check(wet > 0 and uncovered == 0, "pista debaixo d'água toda dentro do tubo ou do túnel (%d de %d fora)" % [uncovered, wet])
	var tube := SeaTube.profile(track)
	var low := INF
	var high := 0.0
	for i in p.size():
		if tube.on[i] == 1:
			low = minf(low, tube.height[i])
			high = maxf(high, tube.height[i])
	_check(low >= SeaTube.TUBE_MIN and low > GlassTunnel.HEIGHT, "tubo bem maior que o túnel (%.0f a %.0f m de altura)" % [low, high])
	# Corais, kelp e águas-vivas fora do tubo
	var wrong := 0
	var checked := 0
	for mmi: MultiMeshInstance3D in gen.get_node("Reef").find_children("*", "MultiMeshInstance3D", false, false):
		var pts: PackedVector3Array = mmi.get_meta("points", PackedVector3Array())
		for k in range(0, pts.size(), 7):
			checked += 1
			if SeaTube.inside(track, pts[k], -0.5):
				wrong += 1
	_check(checked > 300 and wrong == 0, "corais e algas fora do tubo (%d de %d conferidos dentro)" % [wrong, checked])
	var jelly := gen.find_child("Jellyfish", true, false) as MultiMeshInstance3D
	var jelly_pts: PackedVector3Array = jelly.get_meta("points", PackedVector3Array())
	var jelly_in := 0
	for q in jelly_pts:
		if SeaTube.inside(track, q, 0.0):
			jelly_in += 1
	_check(jelly_pts.size() > 50 and jelly_in == 0, "águas-vivas fora do tubo (%d de %d dentro)" % [jelly_in, jelly_pts.size()])
	_check(gen.get_node("Vents").get_meta("vents", []).size() >= 5, "vulcões de bolhas (%d)" % gen.get_node("Vents").get_meta("vents", []).size())
	_check(gen.find_child("Boats", true, false) != null and gen.find_child("Boats", true, false).get_child_count() >= 10, "barcos na superfície")
	var whales := gen.get_node("SeaLife").find_children("Whale*", "Node3D", true, false)
	_check(whales.size() >= 5, "baleias (%d)" % whales.size())
	# (grandes e perto do tubo)
	var big_whales := 0
	var whale_lat := 0.0
	for wh: Node3D in whales:
		if (wh.get_child(0) as Node3D).scale.x >= 1.6:
			big_whales += 1
			whale_lat += absf(p.project(wh.get_meta("at", wh.global_position), true, false).y)
	whale_lat /= maxf(big_whales, 1.0)
	_check(big_whales >= 4 and whale_lat < 48.0, "baleias grandes perto da pista (%d, %.0f m em média)" % [big_whales, whale_lat])
	_check(gen.find_child("RoadCaustics", true, false) != null and gen.find_child("SeaCeiling", true, false) != null
		and gen.find_child("Rainbow", true, false) != null, "cáustica na pista, teto da água e arco-íris")
	_check(gen.get_node("PoseidonGate").get_meta("waterfalls", []).size() >= 4, "cachoeiras no Portão de Poseidon")
	# Cânion: na maior parte da pista debaixo d'água, paredes fora do tubo, montanhas acima do mar no
	# trecho emerso com cachoeiras por quase toda a extensão, luzes coloridas
	var canyon := SeaCanyon.profile(track)
	var w: PackedFloat32Array = canyon.w
	var in_canyon := 0
	var submerged := 0
	var mountain_top := -INF
	for i in p.size():
		if p.points[i].y < water - 0.5:
			submerged += 1
			if w[i] > 0.5:
				in_canyon += 1
		elif p.points[i].y > water + 1.0:
			mountain_top = maxf(mountain_top, maxf(canyon.top[0][i], canyon.top[1][i]))
	_check(in_canyon > submerged * 0.5, "cânion na maior parte da pista debaixo d'água (%d de %d amostras)" % [in_canyon, submerged])
	var wall_pts: PackedVector3Array = gen.get_node("Canyon").get_meta("points", PackedVector3Array())
	var wall_in := 0
	for q in wall_pts:
		if SeaTube.inside(track, q, -0.5):
			wall_in += 1
	_check(wall_pts.size() > 300 and wall_in == 0, "paredes do cânion fora do tubo (%d de %d dentro)" % [wall_in, wall_pts.size()])
	_check(mountain_top > water + 60.0, "montanhas em volta do trecho emerso (até %.0f m acima do mar)" % (mountain_top - water))
	# Trecho emerso: cachoeiras grandes e largas (a cortina e a névoa fora da laje) e aquedutos por cima
	# da pista, com as trepadeiras longe dos carros
	var gate := gen.get_node("PoseidonGate")
	var wide: Array = gate.get_meta("wide_falls", [])
	_check(wide.size() >= 2 and float(wide.min()) >= 60.0, "cachoeiras grandes e largas nas montanhas (%s m)" % str(wide))
	var over_deck := 0
	var curtain_n := 0
	for part: String in ["WideFalls", "FallMist"]:
		var mi := gate.get_node(part) as MeshInstance3D
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for k in range(0, verts.size(), 3):
			curtain_n += 1
			var pr := p.project(verts[k], true, false)
			var vi := p.index_at(pr.x)
			var side := 1 if pr.y > 0.0 else -1
			if absf(pr.y) < track.deck_edge(vi, side) + 1.0 and verts[k].y > water - 1.0:
				over_deck += 1
	_check(curtain_n > 500 and over_deck == 0, "cortinas e névoa das cachoeiras fora da laje (%d de %d)" % [over_deck, curtain_n])
	var vines: float = gate.get_meta("vine_clearance", 0.0)
	_check(int(gate.get_meta("bridges", 0)) >= 2 and vines >= 12.0,
		"aquedutos por cima da pista (%d, trepadeiras a %.1f m do asfalto)" % [gate.get_meta("bridges", 0), vines])
	# Ruínas nos cânions (pontes por cima do tubo, fachadas nas paredes, aquedutos nos trechos abertos)
	# e a inclinação das paredes variando
	var ruins := gen.get_node("CanyonRuins")
	var ruin_pts: PackedVector3Array = ruins.get_meta("points", PackedVector3Array())
	var ruin_in := 0
	for q in ruin_pts:
		# (a forma de verdade do tubo: o arco das pontes o contorna 2,5 m por fora)
		if SeaTube.in_section(track, q, 0.5):
			ruin_in += 1
	_check(int(ruins.get_meta("bridges", 0)) >= 3 and int(ruins.get_meta("facades", 0)) >= 4 and int(ruins.get_meta("aqueducts", 0)) >= 1,
		"ruínas nos cânions (pontes %d, fachadas %d, aquedutos %d)" % [ruins.get_meta("bridges", 0), ruins.get_meta("facades", 0),
		ruins.get_meta("aqueducts", 0)])
	_check(ruin_pts.size() > 40 and ruin_in == 0, "ruínas fora do tubo (%d de %d dentro)" % [ruin_in, ruin_pts.size()])
	# Vulcões perto do tubo (sem encostar), chaminés; relíquias nos trechos abertos fora do tubo;
	# corais elaborados; cavernas nas paredes; estandartes no tubo e no aqueduto
	var crater_pts: Array = gen.get_node("Vents").get_meta("vents", [])
	var vent_lat := 0.0
	for q: Vector3 in crater_pts:
		vent_lat += absf(p.project(q, true, false).y)
	vent_lat /= maxf(crater_pts.size(), 1.0)
	_check(crater_pts.size() >= 8 and vent_lat < 70.0 and int(gen.get_node("Vents").get_meta("chimneys", 0)) >= 16,
		"vulcões perto do tubo (%d, %.0f m em média, %d chaminés)" % [crater_pts.size(), vent_lat, gen.get_node("Vents").get_meta("chimneys", 0)])
	var relics := gen.get_node("Relics")
	var counts: Dictionary = relics.get_meta("counts", {})
	_check(int(counts.get("wreck", 0)) >= 3 and int(counts.get("plaza", 0)) >= 3
		and int(counts.get("arch", 0)) + int(counts.get("pinnacles", 0)) >= 2 and int(counts.get("pool", 0)) >= 25,
		"relíquias nos trechos abertos (%s)" % str(counts))
	var relic_pts: PackedVector3Array = relics.get_meta("points", PackedVector3Array())
	var relic_in := 0
	for q in relic_pts:
		if SeaTube.in_section(track, q, 0.5) or SeaTube.inside(track, q, -1.0):
			relic_in += 1
	_check(relic_pts.size() > 60 and relic_in == 0, "relíquias fora do tubo (%d de %d dentro)" % [relic_in, relic_pts.size()])
	var reef_names := PackedStringArray()
	for child: Node in gen.get_node("Reef").get_children():
		reef_names.append(String(child.name).get_slice("_", 0))
	var missing := PackedStringArray()
	for kind: String in ["Plate", "Pillar", "Barrel", "Soft", "Whip", "Clam", "Mantle", "Star", "Urchin", "Worm", "Plume"]:
		if not kind in reef_names:
			missing.append(kind)
	_check(missing.is_empty(), "corais elaborados no recife (faltando: %s)" % ", ".join(missing))
	var caves: Array = gen.get_node("Canyon").get_meta("caves", [])
	_check(caves.size() >= 10, "cavernas nas paredes do cânion (%d)" % caves.size())
	_check(gen.get_node("SeaTube").find_children("Banners*", "MeshInstance3D", false, false).size() >= 3
		and gen.get_node("Causeway").find_children("CausewayBanners*", "MeshInstance3D", false, false).size() >= 3,
		"estandartes nas nervuras do tubo e nos pilares do aqueduto")
	# Trecho emerso: cipós e árvores debruçadas sobre a pista, nunca baixos sobre a laje; bandeiras
	var over := 0
	var checked_over := 0
	var lianas_mi := gate.get_node_or_null("Lianas") as MeshInstance3D
	var low_pts: Array[Vector3] = []
	if lianas_mi:
		var lv: PackedVector3Array = lianas_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for k in range(0, lv.size(), 5):
			low_pts.append(lv[k])
	for mmi: MultiMeshInstance3D in gate.find_children("Canopy*", "MultiMeshInstance3D", false, false):
		for k in mmi.multimesh.instance_count:
			var cx := mmi.multimesh.get_instance_transform(k)
			low_pts.append(cx.origin - Vector3.UP * cx.basis.y.length() * 0.1)
	for q in low_pts:
		var pr := p.project(q, true, false)
		var vi := p.index_at(pr.x)
		var side := 1 if pr.y > 0.0 else -1
		if absf(pr.y) < track.deck_edge(vi, side) and p.points[vi].y > water:
			checked_over += 1
			if q.y < p.points[vi].y + 12.5:
				over += 1
	_check(int(gate.get_meta("lianas", 0)) >= 6 and int(gate.get_meta("canopies", 0)) >= 8 and checked_over > 100 and over == 0,
		"cipós (%d) e árvores debruçadas (%d) sobre a pista, nada baixo sobre a laje (%d de %d)" % [gate.get_meta("lianas", 0),
		gate.get_meta("canopies", 0), over, checked_over])
	_check(int(gate.get_meta("crest_flags", 0)) >= 4, "bandeiras nas cristas (%d)" % gate.get_meta("crest_flags", 0))
	var slope: PackedFloat32Array = canyon.slope
	var slope_min := INF
	var slope_max := -INF
	for v in slope:
		slope_min = minf(slope_min, v)
		slope_max = maxf(slope_max, v)
	_check(slope_max - slope_min > 0.12, "paredes com inclinação variando (%.2f a %.2f)" % [slope_min, slope_max])
	var lights: int = gen.get_node("Canyon").get_meta("lights", 0)
	_check(lights >= 40, "luzes coloridas submarinas (%d)" % lights)
	# Paredes perto da pista (fora dos trechos com marcos: polvo, portal) e árvores nas montanhas
	var gap_sum := 0.0
	var gap_n := 0
	for i in range(0, p.size(), 5):
		if w[i] > 0.95 and float(canyon.e[i]) < 0.05 and p.points[i].y < water - 5.0:
			gap_sum += float(canyon.foot[0][i]) - SeaTube.clearance(track, i, 1)
			gap_n += 1
	_check(gap_n > 50 and gap_sum / gap_n < 9.0, "paredes do cânion perto do tubo (%.1f m em média)" % (gap_sum / maxf(gap_n, 1.0)))
	var tree_count := 0
	for mmi: MultiMeshInstance3D in gen.get_node("Canyon").find_children("MountainTrees*", "MultiMeshInstance3D", false, false):
		if not mmi.name.contains("_lod"):
			tree_count += mmi.multimesh.instance_count
	_check(tree_count >= 40, "árvores nas montanhas acima do mar (%d)" % tree_count)
	# Os bichos grandes nos trechos abertos (sem cânion)
	var open_n := 0
	var big := 0
	for holder: Node in gen.get_node("SeaLife").get_children():
		if not holder.has_meta("at"):
			continue
		big += 1
		var at: Vector3 = holder.get_meta("at")
		var pr := p.project(at, true, false)
		if float(w[p.index_at(pr.x)]) < 0.5:
			open_n += 1
	_check(big >= 15 and open_n >= big * 0.7, "bichos grandes nos trechos abertos (%d de %d)" % [open_n, big])
	# Barcos perto da pista e a janela do céu do espelho d'água
	var boats := gen.find_child("Boats", true, false) as SeaBoats
	var lat_sum := 0.0
	for b: Array in boats._boats:
		var mid: Vector3 = ((b[1] as Vector3) + (b[2] as Vector3)) * 0.5
		lat_sum += absf(p.project(mid, true, false).y)
	var lat_avg := lat_sum / maxf(boats._boats.size(), 1.0)
	_check(boats._boats.size() >= 10 and lat_avg < 90.0, "barcos perto da pista (%d, %.0f m em média)" % [boats._boats.size(), lat_avg])
	_check(gen.find_child("SkyWindow", true, false) is SubViewport, "janela do céu do espelho d'água")
	# Linha d'água: debaixo d'água a névoa é a densa da água; no trecho emerso, a do período
	var atm := track.find_child("Atmosphere", true, false) as SeaAtmosphere
	var env := (scene.get_node("Daylight/WorldEnvironment") as WorldEnvironment).environment
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true
	cam.global_position = p.position_at(100.0) + Vector3.UP * 3.0
	await _frames(3)
	var under_fog := env.fog_density
	_check(atm != null and atm.factor > 0.99 and under_fog > 0.003, "câmera debaixo d'água: névoa da água (%.4f)" % under_fog)
	cam.global_position = p.position_at(2150.0) + Vector3.UP * 4.0
	await _frames(3)
	above_fog = env.fog_density
	_check(atm.factor < 0.01 and above_fog < 0.002, "câmera no trecho emerso: névoa do período (%.4f)" % above_fog)
	cam.global_position = p.position_at(100.0) + Vector3.UP * 3.0
	await _frames(3)
	# Saindo da água devagar (a câmera andando, depois de um tempo debaixo d'água): gotas na tela e o
	# som; um corte de câmera para fora d'água (o de cima) não conta
	var splash := track.find_child("Splash", true, false) as SeaSplash
	_check(splash != null and not splash.active(), "corte de câmera para fora d'água não mostra as gotas")
	var rise := p.position_at(100.0)
	rise.y = water - 3.0
	cam.global_position = rise
	await create_timer(0.9).timeout
	for k in 30:
		rise.y += 0.25
		cam.global_position = rise
		await _frames(1)
	_check(splash != null and splash.active() and ResourceLoader.exists(SeaSplash.SOUND),
		"saindo da água: gotas na tela e o som")
	cam.current = false
	cam.queue_free()

	# --- Corrida: sem quedas; carro parado nas curvas e nas rampas ---
	while manager.state != RaceManager.State.RACING:
		await process_frame
	await create_timer(1.0, false).timeout
	_check(manager.fall_watch == null, "sem vigia de quedas (barreiras em toda a volta)")
	var pe := manager.player_entry
	await _parked_test(pe, 480.0, "na Curva do Templo")
	await _parked_test(pe, 1455.0, "no Grampo da Âncora")
	await _parked_test(pe, 1750.0, "na Subida do Aqueduto")
	await _parked_test(pe, 2500.0, "no Mergulho")
	await _parked_test(pe, 2737.0, "na Curva da Tartaruga")
	# Saindo da pista, o Environment (compartilhado com a próxima) volta ao de fora d'água
	var env_out := (scene.get_node("Daylight/WorldEnvironment") as WorldEnvironment).environment
	scene.queue_free()
	await _frames(3)
	_check(absf(env_out.fog_density - above_fog) < 0.0001, "ao sair, a névoa volta à do período (%.5f)" % env_out.fog_density)
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
	car.hold = false


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _physics(n: int) -> void:
	for k in n:
		await physics_frame
