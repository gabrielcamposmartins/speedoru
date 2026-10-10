extends SceneTree
## Captura a skin do carro (com janela): aba Skin do Estúdio, o molde exportado, uma pintura
## simulada por cima (como faria um editor de imagem), importada e equipada, e o carro na garagem.
##   godot --path . -s res://tests/capture_skin.gd -- <pasta de saída> --offline
## Perfil e skins de teste: user://test_capture_profile.cfg e user://test_capture_skins/.

const SKIN_DIR := "user://test_capture_skins"

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
	CarSkin.dir = SKIN_DIR
	var profile := root.get_node("Profile") as PlayerProfile
	PlayerProfile.save_path = "user://test_capture_profile.cfg"
	profile.reset_profile()
	profile.equip_livery("livery_tokyo")
	var scene := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await _frames(60)
	var ui: MenuUI = scene.ui
	ui.garage_tab = 0
	ui.show_screen("garage")
	await _frames(20)
	var studio := _find(scene, "StudioPanel") as StudioPanel
	studio.category = "skin"
	studio._build()
	await _frames(20)
	await _snap("skin_aba_vazia")
	# Exporta o molde pelo mesmo caminho do botão
	var tpl_path := out_dir.path_join("molde.png")
	await studio.export_template_to(tpl_path, false)
	var img := Image.load_from_file(tpl_path)
	# "Pinta" por cima: chamas nos lados, faixas em cima, número na lateral
	_paint(img)
	var painted := out_dir.path_join("pintado.png")
	img.save_png(painted)
	var res: Dictionary = await studio.import_skin_from(painted)
	print("importou: ", res)
	await _frames(30)
	await _snap("skin_aba_equipada")
	studio.focus_request.emit("sidepods")
	await create_timer(2.0).timeout
	await _snap("skin_lateral")
	studio.focus_request.emit("")
	await create_timer(3.0).timeout
	await _snap("skin_garagem")
	await create_timer(4.0).timeout
	await _snap("skin_garagem2")
	for f in DirAccess.get_files_at(ProjectSettings.globalize_path(SKIN_DIR)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SKIN_DIR).path_join(f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SKIN_DIR))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.save_path))
	quit()


func _paint(img: Image) -> void:
	var flame_a := Color("ff2d6f")
	var flame_b := Color("ffb000")
	for face in [CarSkin.Face.LEFT, CarSkin.Face.RIGHT]:
		var r: Rect2i = CarSkin.RECTS[face]
		for y in range(r.position.y, r.end.y):
			var fy := float(y - r.position.y) / r.size.y
			for x in range(r.position.x, r.end.x):
				if img.get_pixel(x, y).a < 0.5:
					continue
				# frente = 0..1 ao longo do carro
				var fx := float(x - r.position.x) / r.size.x
				var front := 1.0 - fx if face == CarSkin.Face.LEFT else fx
				var wave := 0.55 + 0.12 * sin(front * 38.0) + 0.25 * front
				if fy > wave:
					img.set_pixel(x, y, flame_a.lerp(flame_b, clampf((fy - wave) * 4.0, 0.0, 1.0)))
		# Disco de número na lateral (sidepod)
		var cz := -0.6
		var c := CarSkin.pixel_of(Vector3(0.0, 0.45, cz), Vector3.RIGHT if face == CarSkin.Face.LEFT else Vector3.LEFT)
		for y in range(int(c.y) - 60, int(c.y) + 60):
			for x in range(int(c.x) - 60, int(c.x) + 60):
				var d := Vector2(x, y).distance_to(c)
				if d < 52 and img.get_pixel(x, y).a > 0.5:
					img.set_pixel(x, y, Color.WHITE if d < 46 else Color("111111"))
	var top: Rect2i = CarSkin.RECTS[CarSkin.Face.TOP]
	for y in range(top.position.y, top.end.y):
		for x in range(top.position.x, top.end.x):
			if img.get_pixel(x, y).a < 0.5:
				continue
			if int((x + y) / 40.0) % 3 == 0:
				img.set_pixel(x, y, Color("ff2d6f"))


func _find(node: Node, cls: String) -> Node:
	if node.get_script() and node.get_script().get_global_name() == cls:
		return node
	for c in node.get_children():
		var f := _find(c, cls)
		if f:
			return f
	return null
