extends SceneTree
## Decalques no carro e a aba do Estúdio (com janela):
##   godot --path . -s res://tests/capture_decals.gd -- <pasta>
## Perfil de teste (user://test_capdecals_profile.cfg): coloca um decalque em cada lugar, fotografa
## o carro de vários ângulos e a aba "Decalques" do Estúdio. Confere também um SVG "do jogador"
## criado numa pasta de teste (user://test_capdecals) apagada no fim.

var out_dir := ""
var car: F1Car
var cam: RaceCamera
var profile: PlayerProfile
var failures := 0
const TEST_SVG := "teste_capdecals.svg"


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else OS.get_user_data_dir()
	profile = root.get_node_or_null("Profile") as PlayerProfile
	PlayerProfile.save_path = "user://test_capdecals_profile.cfg"
	profile.reset_profile()
	var scene := (load("res://scenes/test/test_track.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	car = scene.get_node("F1Car")
	cam = scene.get_node("RaceCamera")
	car.player_controlled = false
	_run.call_deferred()


func _shot(name: String, eye: Vector3, target: Vector3, fov := 40.0) -> void:
	cam.set_mode(RaceCamera.Mode.ORBIT)
	cam.set_process(false)
	var xf := car.global_transform
	cam.global_position = xf * eye
	cam.look_at(xf * target)
	cam.fov = fov
	for k in 6:
		await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("captura: ", name)


func _run() -> void:
	for k in 20:
		await physics_frame
	# SVG "do jogador" numa pasta de teste (apagada no fim; a pasta real do jogador não é tocada)
	CarDecals.user_dir = "user://test_capdecals"
	CarDecals.ensure_user_dir()
	var f := FileAccess.open(CarDecals.user_dir.path_join(TEST_SVG), FileAccess.WRITE)
	f.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="400" height="200"><rect x="10" y="10" width="380" height="180" rx="40" fill="#fff"/></svg>')
	f.close()
	CarDecals.clear_cache()
	_check(CarDecals.custom_ids().has(CarDecals.CUSTOM_PREFIX + TEST_SVG), "SVG do jogador listado")
	_check(CarDecals.texture(CarDecals.CUSTOM_PREFIX + TEST_SVG) != null, "SVG do jogador vira imagem")
	_check(not CarDecals.valid_id("custom:../x.svg") and not CarDecals.valid_id("nada"), "ids inválidos recusados")
	profile.set_decal("sidepods", "chamas")
	profile.set_decal_value("sidepods", "color", "ffd21f")
	profile.set_decal("nose", "estrela")
	profile.set_decal_value("nose", "color", "1fd6e8")
	profile.set_decal("airbox", "alvo")
	profile.set_decal("wing", "logo_s")
	profile.set_decal_value("wing", "color", "15161a")
	profile.set_decal_value("wing", "rot", 15.0)
	profile.apply_to_config(car.config)
	for k in 6:
		await process_frame
	var decals := car.find_children("Decal_*", "Decal", true, false)
	_check(decals.size() == 7, "7 decalques no carro (2 laterais, bico, 2 na entrada de ar, 2 na asa): %d" % decals.size())
	var saved := PlayerProfile.sanitize_equipped(profile.equipped.duplicate(true))
	_check((saved["decals"] as Dictionary).size() == 4 and saved["decals"]["sidepods"]["color"] == "ffd21f",
		"decalques passam pela validação do servidor")
	await _shot("decal_lado", Vector3(3.2, 1.0, -0.2), Vector3(0, 0.45, -0.3), 45.0)
	await _shot("decal_frente34", Vector3(2.2, 1.8, 3.0), Vector3(0, 0.45, 0.6), 45.0)
	await _shot("decal_tras34", Vector3(-2.4, 1.6, -3.6), Vector3(0, 0.6, -1.4), 45.0)
	await _shot("decal_lado_direito", Vector3(-3.2, 1.0, -0.2), Vector3(0, 0.45, -0.3), 45.0)
	# Estúdio, aba Decalques (lugar: laterais)
	var layer := CanvasLayer.new()
	layer.layer = 20
	root.add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(980, 20)
	panel.size = Vector2(600, 860)
	layer.add_child(panel)
	var studio := StudioPanel.new()
	studio.category = "decals"
	panel.add_child(studio)
	studio.setup(car)
	await _shot("decal_estudio", Vector3(3.2, 1.2, 1.5), Vector3(0, 0.45, -0.3), 45.0)
	for file in ["LEIA-ME.txt", TEST_SVG]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CarDecals.user_dir.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CarDecals.user_dir))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_capdecals_profile.cfg"))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
