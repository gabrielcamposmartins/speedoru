extends SceneTree
## Gera o atlas dos letreiros de Las Vegas (NeonArt.ATLAS_FILE) a partir dos desenhos de
## scripts/track/neon_art.gd. Precisa de janela (placa de vídeo):
##   godot --path . -s res://tools/build_neon_atlas.gd
## Depois, o Godot reimporta o PNG (comprimido, com mipmaps, sem mexer no alfa: ver o .import).


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var img: Image = await NeonArt.render(root)
	if img == null or img.is_empty():
		print("sem placa de vídeo: rode com janela")
		quit(1)
		return
	var path := ProjectSettings.globalize_path(NeonArt.ATLAS_FILE)
	img.save_png(path)
	print("atlas: %s (%dx%d, %d células, %d ms)" % [path, img.get_width(), img.get_height(), NeonArt._cells.size(),
		Time.get_ticks_msec() - t0])
	quit()
