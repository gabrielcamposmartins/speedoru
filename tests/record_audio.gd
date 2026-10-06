extends SceneTree
## Grava o som de uma largada em Monza (precisa de janela/áudio):
##   godot --path . -s res://tests/record_audio.gd -- <pasta>
## Salva largada.wav e largada_rpm.csv (tempo, rpm, marcha, velocidade) para análise.

var out_dir := "user://audio"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene := (load("res://scenes/tracks/monza.tscn") as PackedScene).instantiate()
	scene.set("start_light_sequence", false)
	root.add_child(scene)
	_run.call_deferred(scene)


func _run(scene: Node3D) -> void:
	var car := scene.get_node("F1Car") as F1Car
	car.player_controlled = false
	await _physics(60)
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	rec.set_recording_active(true)
	var t0 := Time.get_ticks_msec()
	var log := "t,rpm,gear,kmh\n"
	car.throttle_input = 1.0
	for k in 1200:  # 10 s
		await physics_frame
		if k == 960:
			car.throttle_input = 0.0
			car.brake_input = 0.6
		if k % 6 == 0:
			log += "%.3f,%.0f,%d,%.1f\n" % [(Time.get_ticks_msec() - t0) / 1000.0, car.rpm, car.gear, car.speed_kmh]
	rec.set_recording_active(false)
	var wav := rec.get_recording()
	wav.save_to_wav(out_dir.path_join("largada.wav"))
	var f := FileAccess.open(out_dir.path_join("largada_rpm.csv"), FileAccess.WRITE)
	f.store_string(log)
	f.close()
	print("Gravado: %.1f s" % wav.get_length())
	quit()


func _physics(n: int) -> void:
	for k in n:
		await physics_frame
