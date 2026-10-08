class_name CarDecals
extends RefCounted
## Decalques (adesivos SVG) do carro: projetados na carroceria com nós Decal e tingidos com a cor
## escolhida. O que está aplicado vive em CarConfig.decals / Profile.equipped["decals"]:
##   {lugar: {"id": "estrela" | "custom:arquivo.svg", "color": "rrggbb", "scale": 0.3..1.5, "rot": graus}}
##
## * Padrão: assets/decals/<id>.svg (brancos, gerados por tools/generate_decals.py).
## * Do jogador: qualquer .svg na pasta user://decals (botão "Abrir pasta" no Estúdio). Só aparecem
##   para quem tem o arquivo (os outros jogadores online não veem o decalque próprio).
## * Lugares com dois lados (laterais, entrada de ar, asa) recebem o mesmo decalque nos dois, cada
##   um legível de fora (sem espelhar).

const PRESET_DIR := "res://assets/decals/"
## Pasta dos SVGs do jogador (os testes usam outra).
static var user_dir := "user://decals"
const CUSTOM_PREFIX := "custom:"
## Tamanho máximo de um SVG do jogador (bytes) e lado da imagem gerada (px).
const MAX_SVG_BYTES := 512 * 1024
const RASTER := 512

## Decalques padrão: [id, nome].
const PRESETS := [
	["estrela", "Estrela"], ["raio", "Raio"], ["chamas", "Chamas"], ["xadrez", "Bandeira quadriculada"],
	["sakura", "Sakura"], ["coracao", "Coração"], ["asas", "Asas"], ["listras", "Listras de velocidade"],
	["garras", "Garras"], ["alvo", "Disco de número"], ["onda", "Onda"], ["logo_s", "Logo S"], ["cometa", "Cometa"],
]

## Lugares no carro (espaço local: +Z frente, +X esquerda, Y para cima). Cada posição:
## [centro, normal para fora, "direita" de quem olha de fora, largura, altura, profundidade].
const SLOTS := {
	"sidepods": {"label": "Laterais (dois lados)", "places": [
		[Vector3(0.70, 0.36, -0.30), Vector3(1, 0, 0), Vector3(0, 0, -1), 0.62, 0.32, 0.5],
		[Vector3(-0.70, 0.36, -0.30), Vector3(-1, 0, 0), Vector3(0, 0, 1), 0.62, 0.32, 0.5]]},
	"nose": {"label": "Bico", "places": [
		[Vector3(0.0, 0.43, 2.05), Vector3(0, 0.95, 0.31), Vector3(-1, 0, 0), 0.28, 0.55, 0.3]]},
	"airbox": {"label": "Entrada de ar (dois lados)", "places": [
		[Vector3(0.15, 0.79, -0.80), Vector3(1, 0, 0), Vector3(0, 0, -1), 0.55, 0.22, 0.24],
		[Vector3(-0.15, 0.79, -0.80), Vector3(-1, 0, 0), Vector3(0, 0, 1), 0.55, 0.22, 0.24]]},
	"wing": {"label": "Asa traseira (placas)", "places": [
		[Vector3(0.506, 0.80, -2.55), Vector3(1, 0, 0), Vector3(0, 0, -1), 0.5, 0.32, 0.1],
		[Vector3(-0.506, 0.80, -2.55), Vector3(-1, 0, 0), Vector3(0, 0, 1), 0.5, 0.32, 0.1]]},
}
const SLOT_ORDER := ["sidepods", "nose", "airbox", "wing"]

static var _textures := {}


static func slot_label(slot: String) -> String:
	return str((SLOTS.get(slot, {}) as Dictionary).get("label", slot))


static func preset_name(id: String) -> String:
	for p in PRESETS:
		if p[0] == id:
			return p[1]
	if id.begins_with(CUSTOM_PREFIX):
		return id.substr(CUSTOM_PREFIX.length()).get_basename()
	return id


static func is_preset(id: String) -> bool:
	for p in PRESETS:
		if p[0] == id:
			return true
	return false


## Nome de arquivo aceito para um SVG do jogador (sem pastas nem caracteres estranhos).
static func valid_custom_name(file: String) -> bool:
	if not file.to_lower().ends_with(".svg") or file.length() > 80:
		return false
	for ch in file:
		if not (ch.is_valid_identifier() or ch in " -_.0123456789" or ch.unicode_at(0) > 127):
			return false
	return not (".." in file or "/" in file or "\\" in file)


## Id aceito (padrão ou "custom:<arquivo>.svg"); o servidor usa isto para validar.
static func valid_id(id: String) -> bool:
	if id.begins_with(CUSTOM_PREFIX):
		return valid_custom_name(id.substr(CUSTOM_PREFIX.length()))
	return is_preset(id)


## SVGs do jogador em user://decals (ids "custom:...").
static func custom_ids() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(user_dir)
	if dir == null:
		return out
	for f in dir.get_files():
		if valid_custom_name(f):
			out.append(CUSTOM_PREFIX + f)
	out.sort()
	return out


## Cria a pasta dos SVGs do jogador (com um arquivo de instruções) e devolve o caminho no disco.
static func ensure_user_dir() -> String:
	DirAccess.make_dir_recursive_absolute(user_dir)
	var readme := user_dir.path_join("LEIA-ME.txt")
	if not FileAccess.file_exists(readme):
		var f := FileAccess.open(readme, FileAccess.WRITE)
		if f:
			f.store_string("Coloque aqui arquivos .svg (até 512 KB) para usar como decalques no Estúdio do Speedoru.\n" +
				"Use desenhos brancos com fundo transparente: no jogo eles são pintados com a cor escolhida.\n" +
				"Depois clique em \"Recarregar\" no Estúdio. Decalques próprios só aparecem para você.\n")
	return ProjectSettings.globalize_path(user_dir)


## Esquece as imagens já geradas (depois de trocar arquivos na pasta).
static func clear_cache() -> void:
	_textures.clear()


## Imagem do decalque (nula se o arquivo não existe ou não é um SVG válido).
static func texture(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var tex: Texture2D = null
	if id.begins_with(CUSTOM_PREFIX):
		var file := id.substr(CUSTOM_PREFIX.length())
		if valid_custom_name(file):
			tex = _raster_file(user_dir.path_join(file))
	elif is_preset(id):
		tex = load(PRESET_DIR + id + ".svg") as Texture2D
	_textures[id] = tex
	return tex


static func _raster_file(path: String) -> Texture2D:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_SVG_BYTES:
		return null
	var text := f.get_as_text()
	var probe := Image.new()
	if probe.load_svg_from_string(text, 1.0) != OK or probe.get_width() <= 0:
		return null
	var scale := clampf(float(RASTER) / maxf(probe.get_width(), probe.get_height()), 0.05, 16.0)
	var img := Image.new()
	if img.load_svg_from_string(text, scale) != OK:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Monta os nós Decal de `decals` dentro de `parent` (apaga os anteriores).
static func build(parent: Node3D, decals: Dictionary) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()
	for slot in decals:
		if not SLOTS.has(slot) or not decals[slot] is Dictionary:
			continue
		var d: Dictionary = decals[slot]
		var tex := texture(str(d.get("id", "")))
		if tex == null:
			continue
		var color_html := str(d.get("color", "ffffff"))
		var color := Color(color_html) if Color.html_is_valid(color_html) else Color.WHITE
		var scale := clampf(float(d.get("scale", 1.0)), 0.3, 1.5)
		var rot := deg_to_rad(clampf(float(d.get("rot", 0.0)), -180.0, 180.0))
		var aspect := float(tex.get_width()) / maxf(tex.get_height(), 1.0)
		var places: Array = SLOTS[slot]["places"]
		for k in places.size():
			var place: Array = places[k]
			var w: float = place[3]
			var h: float = place[4]
			# Cabe no retângulo do lugar mantendo a proporção do desenho
			var dw := w * scale
			var dh := dw / aspect
			if dh > h * scale:
				dh = h * scale
				dw = dh * aspect
			var normal: Vector3 = (place[1] as Vector3).normalized()
			var right: Vector3 = place[2]
			right = (right - normal * right.dot(normal)).normalized()
			# Decal: projeta ao longo de -Y local; a imagem vai em X (largura) e Z (altura, para baixo)
			var basis := Basis(right, normal, right.cross(normal)) * Basis(Vector3.UP, rot)
			var dec := Decal.new()
			dec.name = "Decal_%s_%d" % [slot, k]
			dec.transform = Transform3D(basis, place[0])
			dec.size = Vector3(dw, place[5], dh)
			dec.texture_albedo = tex
			dec.modulate = color
			dec.cull_mask = CarAssembly.CAR_LAYER
			dec.normal_fade = 0.45
			dec.upper_fade = 0.15
			dec.lower_fade = 0.15
			parent.add_child(dec)


## Copia limpa de um dicionário de decalques (lugares e ids válidos, valores nos limites).
static func sanitize(src: Variant) -> Dictionary:
	var out := {}
	if not src is Dictionary:
		return out
	for slot in (src as Dictionary):
		var v: Variant = src[slot]
		if not SLOTS.has(str(slot)) or not v is Dictionary:
			continue
		var id := str((v as Dictionary).get("id", ""))
		if not valid_id(id):
			continue
		var color := str((v as Dictionary).get("color", "ffffff"))
		out[str(slot)] = {
			"id": id,
			"color": color if Color.html_is_valid(color) else "ffffff",
			"scale": clampf(float((v as Dictionary).get("scale", 1.0)), 0.3, 1.5),
			"rot": clampf(float((v as Dictionary).get("rot", 0.0)), -180.0, 180.0),
		}
	return out
