extends SceneTree
## Diagnóstico de som (precisa de janela/áudio): grava a saída no menu e no grid, silenciando um
## bus de cada vez, para achar de onde vem um zumbido constante.
##   godot --path . -s res://tests/audio_hum_probe.gd -- <pasta> [pista]

var out_dir := ""
var rec: AudioEffectRecord


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	RaceSettings.track = RaceSettings.valid_track(args[1]) if args.size() > 1 else "monaco"
	rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	_run.call_deferred()


func _record(name: String, seconds: float) -> void:
	rec.set_recording_active(true)
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < seconds * 1000.0:
		await process_frame
	rec.set_recording_active(false)
	rec.get_recording().save_to_wav(out_dir.path_join("hum_%s.wav" % name))
	print("gravado ", name)


func _mute_only(bus: String) -> void:
	for b in ["Car", "Rivals", "Music", "Crowd"]:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_mute(i, b == bus or bus == "tudo" or (bus == "motores" and (b == "Car" or b == "Rivals")))


func _run() -> void:
	# Menu principal (garagem)
	var menu := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	for k in 120:
		await process_frame
	await _record("menu", 4.0)
	_mute_only("Music")
	await _record("menu_sem_musica", 4.0)
	_mute_only("Car")
	await _record("menu_sem_carro", 4.0)
	_mute_only("")
	menu.queue_free()
	await process_frame
	# Corrida, no grid antes da largada
	RaceSettings.mode = RaceSettings.Mode.RACE
	RaceSettings.skip_menu = true
	var scene := (load(RaceSettings.track_scene(RaceSettings.track)) as PackedScene).instantiate()
	root.add_child(scene)
	var manager: RaceManager = scene.get_node("RaceManager")
	while manager.state != RaceManager.State.GRID:
		await process_frame
	for k in 60:
		await process_frame
	await _record("grid", 4.0)
	for b in ["Car", "Rivals", "Music", "Crowd", "motores", "tudo"]:
		_mute_only(b)
		await _record("grid_sem_" + b.to_lower(), 4.0)
	_mute_only("")
	# Pausado
	paused = true
	for k in 30:
		await process_frame
	await _record("pausado", 4.0)
	quit()
