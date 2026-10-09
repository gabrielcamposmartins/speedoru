extends SceneTree
## Captura o menu principal (com janela): início, Jogar solo, garagem (Estúdio nos 3 cenários,
## Galeria, Loja) e o resultado de um giro. Usa um perfil de teste com algumas peças.
##   godot --path . -s res://tests/capture_menu.gd -- <pasta de saída>

var out_dir := "user://captures"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("salvo ", name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var profile := root.get_node("Profile") as PlayerProfile
	PlayerProfile.save_path = "user://test_capture_profile.cfg"
	profile.reset_profile()
	profile.credits = 48750
	for id in ["part_rear_wing_lowdf", "part_nose_pointed", "decal_cometa", "decal_raio", "decal_chamas", "neon_cyan", "boost_ruby"]:
		profile.owned[id] = true
	profile.equip_livery("livery_aurora")
	profile.equip_color("helmet", Color("ffd23f"))
	var scene := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(90)
	await _snap("menu_home")
	var ui: MenuUI = scene.ui
	ui.show_screen("solo")
	await _frames(30)
	await _snap("menu_solo")
	ui.garage_tab = 0
	ui.show_screen("garage")
	await _frames(40)
	await _snap("menu_studio")
	profile.set_neon(true)
	profile.equip_part("rear_wing", "lowdf")
	await _frames(20)
	await _snap("menu_studio_neon")
	var studio := _find(scene, "StudioPanel") as StudioPanel
	studio.category = "engineering"
	studio._build()
	profile.set_setup_value("downforce_area", 4.6)
	profile.set_setup_value("brake_bias_front", 0.6)
	await _frames(20)
	await _snap("menu_studio_engineering")
	profile.reset_setup()
	studio.category = "finish"
	profile.set_finish("paint_finish", 1)
	profile.set_finish("rim_finish", 1)
	studio._build()
	await _frames(20)
	await _snap("menu_studio_finish")
	profile.set_finish("paint_finish", 4)
	await _frames(20)
	await _snap("menu_studio_finish_matte")
	profile.set_finish("paint_finish", 0)
	profile.set_finish("rim_finish", 0)
	studio.category = "livery"
	studio._build()
	for kind in ["sun", "box"]:
		scene.set_scene(kind)
		await _frames(30)
		await _snap("menu_studio_" + kind)
	scene.set_scene("neon")
	ui.garage_tab = 1
	ui.show_screen("garage")
	await _frames(20)
	await _snap("menu_gallery")
	# Prévia: peça que falta (asa traseira de alta carga) e capacete; a câmera vai até cada uma
	var gallery := _find(scene, "GalleryPanel") as GalleryPanel
	gallery.type = "part"
	gallery._select("part_rear_wing_highdf")
	await create_timer(1.6).timeout
	await _snap("menu_gallery_part")
	gallery.type = "decal"
	gallery._select("decal_sakura")
	await create_timer(1.6).timeout
	await _snap("menu_gallery_decal")
	ui.garage_tab = 2
	ui.show_screen("garage")
	await _frames(20)
	await _snap("menu_shop")
	# Giro
	var shop := _find(scene, "ShopPanel") as ShopPanel
	shop._spin("neon")
	await _frames(40)
	await _snap("menu_spin")
	await create_timer(2.6).timeout
	await _frames(30)
	await _snap("menu_spin_result")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.save_path))
	quit()


func _find(node: Node, cls: String) -> Node:
	if node.get_script() and node.get_script().get_global_name() == cls:
		return node
	for c in node.get_children():
		var f := _find(c, cls)
		if f:
			return f
	return null
