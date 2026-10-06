extends SceneTree
## Teste do mixer de som do carro (sem janela):
##   godot --headless --path . -s res://tests/audio_test.gd
## Confere as camadas do motor (2 giros vizinhos, equal power, pitch = rpm/giro do loop), trocas
## de marcha, estouros ao aliviar, pneu cantando, brita, zebra e batida.

var scene: Node3D
var track: RaceTrack
var car: F1Car
var audio: CarAudio
var failures := 0
var shots: Array[String] = []


func _initialize() -> void:
	RaceSettings.mode = RaceSettings.Mode.PRACTICE
	RaceSettings.skip_menu = true
	scene = (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	scene.set("start_light_sequence", false)
	root.add_child(scene)
	track = scene.get_node("Track")
	car = scene.get_node("F1Car")
	car.player_controlled = false
	audio = car.get_node("Audio")
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _run() -> void:
	await _physics(30)
	_watch_shots()
	await _engine_sweep()
	await _slide()
	await _surfaces()
	await _crash()
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)


## Registra os sons curtos tocados (embrulha play_shot olhando os players do pool).
func _watch_shots() -> void:
	for p in audio._pool:
		p.finished.connect(func(): pass)


func _played_shots() -> Array[String]:
	var out: Array[String] = []
	for p in audio._pool:
		if p.playing and p.stream:
			out.append(p.stream.resource_path.get_file().get_basename())
	return out


func _engine_sweep() -> void:
	car.global_transform = track.get_grid_transform(0)
	car.reset_physics_interpolation()
	await _physics(10)
	car.throttle_input = 1.0
	var ok_layers := true
	var shift_heard := false
	var max_rpm := 0.0
	for k in 16:
		await _physics(60)
		var layers := audio.get_engine_layers()
		var on_sum := 0.0
		var pitch_ok := true
		var desc := []
		for key in layers:
			var w: float = layers[key][0]
			var pitch: float = layers[key][1]
			if key.begins_with("on"):
				on_sum += w * w
			pitch_ok = pitch_ok and pitch > 0.7 and pitch < 1.45
			desc.append("%s %.2f×%.2f" % [key, w, pitch])
		var loud := lerpf(0.55, 1.0, clampf((car.rpm - 4000.0) / 9000.0, 0.0, 1.0)) * audio.engine_load
		# Equal power: soma dos quadrados = ganho² (fora do corte de giro / troca)
		var power_ok := absf(sqrt(on_sum) - loud) < 0.08 or car.is_shifting() or car.rpm > car.max_rpm - 150.0
		ok_layers = ok_layers and pitch_ok and layers.size() <= 4 and power_ok
		max_rpm = maxf(max_rpm, car.rpm)
		for s in _played_shots():
			shift_heard = shift_heard or s.begins_with("shift")
		if k % 3 == 0:
			print("  %3.0f km/h marcha %d %5.0f rpm carga %.2f | %s" % [car.speed_kmh, car.gear, car.rpm, audio.engine_load, ", ".join(desc)])
	_check(ok_layers, "motor: 2 camadas vizinhas, equal power, pitch entre 0,7 e 1,45")
	_check(shift_heard, "som de troca de marcha")
	# Alivia em giro alto: estouros
	car.throttle_input = 0.0
	var pops := false
	for k in 60:
		await physics_frame
		for s in _played_shots():
			pops = pops or s.begins_with("backfire")
	_check(pops, "estouros no escapamento ao aliviar")
	await _physics(30)
	var off_layers := audio.get_engine_layers().keys().filter(func(key): return key.begins_with("off"))
	_check(not off_layers.is_empty(), "sem acelerar usa os loops sem carga")
	_check(audio.get_loop_level("gear_whine") > 0.1, "assobio das engrenagens ao aliviar")
	_check(audio.get_loop_level("wind") > 0.1, "vento em alta velocidade")


func _slide() -> void:
	# Freia forte esterçando: pneus no limite (cantando) ou travando (arrastando)
	car.brake_input = 1.0
	car.steer_input = 1.0
	var squeal := 0.0
	for k in 60:
		await physics_frame
		squeal = maxf(squeal, audio.get_loop_level("tire_squeal") + audio.get_loop_level("tire_scrub"))
	car.brake_input = 0.0
	car.steer_input = 0.0
	print("  pneus no limite: nível %.2f" % squeal)
	_check(squeal > 0.1, "pneu cantando/arrastando no limite")


func _surfaces() -> void:
	var p := track.path
	# Brita
	var best := -1
	for i in p.size():
		if track.gravel[0][i] > 20.0 and absf(p.curvature[i]) < 0.004:
			best = i
			break
	var lateral := p.width_left[best] + track.layout.kerb_width * track.kerb[0][best] + 1.0 + track.gravel[0][best] * 0.5
	await _launch(p.frame_at(p.s_at(best), lateral, 0.1), 30.0)
	var gravel := 0.0
	for k in 30:
		await physics_frame
		gravel = maxf(gravel, audio.get_loop_level("gravel"))
	_check(gravel > 0.2, "som de brita (%.2f)" % gravel)
	# Zebra na diagonal
	best = -1
	for i in p.size():
		if track.kerb[0][i] > 0.99 and track.kerb[0][(i + 15) % p.size()] > 0.99 and absf(p.curvature[i]) < 0.02:
			best = i
			break
	var xf := p.frame_at(p.s_at(best), p.width_left[best] - 3.0, 0.1)
	var dir := (p.tangents[best] + p.lefts[best] * 0.25).normalized()
	await _launch(Transform3D(Basis.looking_at(-dir), xf.origin), 25.0)
	var kerb := 0.0
	var pitch := 0.0
	for k in 90:
		await physics_frame
		var level := audio.get_loop_level("kerb")
		if level > kerb:
			kerb = level
			pitch = (audio._loops["kerb"] as AudioStreamPlayer3D).pitch_scale
	print("  zebra: nível %.2f, pitch %.2f (esperado ~%.2f)" % [kerb, pitch, 25.0 / audio.kerb_reference_speed])
	_check(kerb > 0.1 and absf(pitch - 25.0 / audio.kerb_reference_speed) < 0.15, "batidas da zebra no ritmo da velocidade")


func _crash() -> void:
	var p := track.path
	var i := p.index_at(3000.0)
	var dir := (p.lefts[i] * 0.8 + p.tangents[i] * 0.6).normalized()
	await _launch(Transform3D(Basis.looking_at(-dir), track.edge_point(i, 1, -2.0, 0.1)), 30.0)
	var heard := false
	for k in 180:
		await physics_frame
		for s in _played_shots():
			heard = heard or s.begins_with("impact")
	_check(heard, "som de batida na barreira")


func _launch(xf: Transform3D, speed: float) -> void:
	car.global_transform = xf
	car.reset_physics_interpolation()
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	await _physics(20)
	car.linear_velocity = xf.basis.z * speed
	audio._prev_velocity = car.linear_velocity
	audio._prev_position = car.global_position


func _physics(n: int) -> void:
	for k in n:
		await physics_frame
