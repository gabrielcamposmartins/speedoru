extends SceneTree
## Captura (com janela) dos selos de origem no Estúdio e na Galeria: offline com a coleção da conta
## guardada (APARELHO e SÓ ONLINE) e "conectado" (CONTA e APARELHO; só o perfil, sem rede).
##   godot --path . -s res://tests/capture_origin.gd -- --offline <pasta de saída>
## Arquivos de teste: user://test_capture_origin_* (apagados no fim).

var out_dir := "user://captures"
var _settings_backup := PackedByteArray()


func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool: return not a.begins_with("--"))
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
	if FileAccess.file_exists("user://settings.cfg"):
		_settings_backup = FileAccess.get_file_as_bytes("user://settings.cfg")
	(root.get_node("Net") as Node).account_file = "user://test_capture_origin_account.cfg"
	var profile := root.get_node("Profile") as PlayerProfile
	PlayerProfile.save_path = "user://test_capture_origin_profile.cfg"
	profile.reset_profile()
	# Aparelho: asas e rastros; conta no servidor: parte igual, parte diferente
	for id in ["part_rear_wing_lowdf", "part_nose_pointed", "part_rim_spoked", "trail_fire", "trail_bubbles", "trail_stars"]:
		profile.owned[id] = true
	profile.other_owned = {}
	for id in ["part_rear_wing_lowdf", "part_rear_wing_dragon", "part_rim_star", "trail_fire", "trail_rainbow", "trail_lightning"]:
		profile.other_owned[id] = true
	profile.other_known = true
	var scene := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(90)
	var ui: MenuUI = scene.ui
	for pass_name in ["offline", "online"]:
		if pass_name == "online":
			# Como o Net deixa o perfil conectado: conta = owned, aparelho = other_owned/extra_owned
			var device := profile.owned.duplicate()
			profile.mode = "remote"
			profile.owned = profile.other_owned.duplicate()
			profile.other_owned = device
			profile.extra_owned = device.duplicate()
		ui.garage_tab = 0
		ui.show_screen("garage")
		await _frames(20)
		var studio := _find(scene, "StudioPanel") as StudioPanel
		for cat in ["parts", "trail"]:
			studio.category = cat
			studio._build()
			await _frames(40)
			await _snap("origem_%s_estudio_%s" % [pass_name, cat])
		ui.garage_tab = 1
		ui.show_screen("garage")
		await _frames(20)
		var gallery := _find(scene, "GalleryPanel") as GalleryPanel
		gallery.type = "trail"
		gallery.selected_id = "trail_rainbow"
		gallery._rebuild()
		await _frames(30)
		await _snap("origem_%s_galeria_trail" % pass_name)
	profile.mode = "local"
	profile.extra_owned = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_capture_origin_account.cfg"))
	if not _settings_backup.is_empty():
		var f := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		f.store_buffer(_settings_backup)
		f.close()
	quit()


func _find(node: Node, cls: String) -> Node:
	if node.get_script() and node.get_script().get_global_name() == cls:
		return node
	for c in node.get_children():
		var f := _find(c, cls)
		if f:
			return f
	return null
