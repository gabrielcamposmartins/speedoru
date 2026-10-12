extends SceneTree
## Captura (com janela) das prévias novas: carrossel de pistas (Jogar solo, parado e girando),
## peças e partículas do Estúdio e da Galeria (silhuetas e ícones, por categoria) e o giro da Roleta
## Dragão.
##   godot --path . -s res://tests/capture_cards.gd -- <pasta de saída>

var out_dir := "user://captures"
var _settings_backup := PackedByteArray()


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
	if FileAccess.file_exists("user://settings.cfg"):
		_settings_backup = FileAccess.get_file_as_bytes("user://settings.cfg")
	var profile := root.get_node("Profile") as PlayerProfile
	PlayerProfile.save_path = "user://test_capture_cards_profile.cfg"
	profile.reset_profile()
	profile.credits = 48750
	for id in ["part_rear_wing_lowdf", "part_nose_pointed", "part_rear_wing_dragon", "part_rim_spoked", "part_rim_star",
			"part_front_wing_bat", "part_sidepods_gills", "part_halo_crown", "part_mirrors_winglet", "part_engine_cover_horns"]:
		profile.owned[id] = true
	for id in ["trail_fire", "trail_lightning", "trail_stars", "trail_bubbles", "trail_sakura", "trail_coins"]:
		profile.owned[id] = true
	profile.equip_trail("trail_fire")
	var scene := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(90)
	var ui: MenuUI = scene.ui
	ui.show_screen("solo")
	await _frames(30)
	await _snap("solo")
	var carousel := scene.find_child("TrackCarousel", true, false) as TrackCarousel
	carousel.select(carousel.selected + 1)
	await create_timer(0.18).timeout
	await _snap("solo_girando")
	await create_timer(0.6).timeout
	carousel.select(carousel.selected + 1)
	await create_timer(0.8).timeout
	await _snap("solo_outra")
	ui.garage_tab = 0
	ui.show_screen("garage")
	await _frames(20)
	var studio := _find(scene, "StudioPanel") as StudioPanel
	studio.category = "parts"
	studio._build()
	await _frames(30)
	await _snap("estudio_pecas")
	studio.category = "trail"
	studio._build()
	await _frames(60)
	await _snap("estudio_particulas")
	ui.garage_tab = 1
	ui.show_screen("garage")
	await _frames(20)
	var gallery := _find(scene, "GalleryPanel") as GalleryPanel
	gallery.type = "part"
	gallery._rebuild()
	await _frames(30)
	await _snap("galeria_pecas")
	gallery.type = "trail"
	gallery._rebuild()
	await _frames(30)
	await _snap("galeria_particulas")
	ui.garage_tab = 2
	ui.show_screen("garage")
	await _frames(20)
	await _snap("loja")
	var shop := _find(scene, "ShopPanel") as ShopPanel
	var overlay := ShopPanel.SpinOverlay.new()
	overlay.roulette = "inferno"
	overlay.result = {"ok": true, "item": "part_rear_wing_dragon", "dup": false, "rarity": 4, "refund": 0}
	overlay.panel = shop
	shop._overlay = overlay
	root.add_child(overlay)
	await create_timer(0.8).timeout
	await _snap("giro")
	await create_timer(2.2).timeout
	await _snap("giro_resultado")
	await create_timer(1.0).timeout
	await _snap("giro_confete")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.save_path))
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
