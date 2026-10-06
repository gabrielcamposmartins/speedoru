extends SceneTree
## Gera o atlas de anúncios (precisa de janela/renderização, não use --headless):
##   godot --path . -s res://tools/bake_ad_atlas.gd
## Salva em TrackAds.ATLAS_PATH. Edite TrackAds.BRANDS para mudar as marcas.


class AtlasCanvas extends Control:
	var font: Font

	func _draw() -> void:
		TrackAds.draw_atlas(self, font)


func _initialize() -> void:
	var view := SubViewport.new()
	view.size = TrackAds.ATLAS_SIZE
	view.transparent_bg = false
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := AtlasCanvas.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial Black", "Impact", "Segoe UI Black", "Arial"])
	font.font_weight = 900
	canvas.font = font
	canvas.size = TrackAds.ATLAS_SIZE
	view.add_child(canvas)
	root.add_child(view)
	_save.call_deferred(view)


func _save(view: SubViewport) -> void:
	for i in 4:
		await process_frame
	var image := view.get_texture().get_image()
	var path := ProjectSettings.globalize_path(TrackAds.ATLAS_PATH)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := image.save_png(path)
	print("Atlas salvo em %s (%s)" % [path, error_string(err)])
	quit()
