extends SceneTree
## Conferência visual das silhuetas das peças (com janela): salva uma folha com todas em <pasta>.
##   godot --path . -s res://tests/part_silhouette_probe.gd -- <pasta>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else OS.get_user_data_dir()
	var keys := []
	for slot in PartSilhouette.VIEWS:
		for v in CarPartCatalog.variants(slot):
			keys.append([slot, v])
			PartSilhouette.texture(slot, v)
	var t0 := Time.get_ticks_msec()
	for k in 600:
		await process_frame
		if PartSilhouette._pending.is_empty() and k > 3:
			break
	print("silhuetas prontas em %d ms" % (Time.get_ticks_msec() - t0))
	var cell := Vector2i(PartSilhouette.SIZE.x / 2, PartSilhouette.SIZE.y / 2)
	var cols := 8
	var sheet := Image.create_empty(cell.x * cols, cell.y * ((keys.size() + cols - 1) / cols), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.11, 0.14))
	var fringe := 0
	for i in keys.size():
		var tex := PartSilhouette.texture(keys[i][0], keys[i][1])
		if tex == null:
			print("sem silhueta: ", keys[i])
			continue
		var img := tex.get_image()
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.05 and c.r < 0.9:
					fringe += 1
		var k := minf(float(cell.x - 8) / img.get_width(), float(cell.y - 8) / img.get_height())
		img.resize(maxi(int(img.get_width() * k), 1), maxi(int(img.get_height() * k), 1))
		var at := Vector2i((i % cols) * cell.x, (i / cols) * cell.y) + (cell - img.get_size()) / 2
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
	print("pixels de borda escura: ", fringe)
	sheet.save_png(out.path_join("silhuetas.png"))
	quit()
