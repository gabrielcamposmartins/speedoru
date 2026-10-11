class_name CarSkin
extends RefCounted
## Skin do carro: uma imagem pintada pelo jogador por cima do MOLDE (o carro planificado).
##
## Planificação por projeção nas vistas do carro, no espaço do carro (+Z frente, +X esquerda, Y para
## cima; todas as peças da carroceria ficam nesse espaço). Cada face da pintura pega a vista para a
## qual mais aponta (a maior componente da normal): lado esquerdo, lado direito, cima, baixo, frente
## e trás. Assim o molde vale para qualquer combinação de peças.
##
## Duas camadas por vista, para nenhuma superfície dividir a pintura com outra:
## * VISÍVEL (RECTS, 250 px/m): a superfície mais perto de quem olha daquele lado — o carro como se
##   vê. É onde vai o desenho principal.
## * ESCONDIDA (RECTS_HIDDEN, 120 px/m): o que fica atrás de outra superfície virada para o mesmo
##   lado (o monocoque atrás do sidepod, a face de dentro do sidepod do outro lado, os elementos de
##   baixo da asa). A parte de baixo do carro inteira também fica aqui (BOTTOM).
## Quem é escondido sai do MAPA DE PROFUNDIDADE do carro (CarSkinTemplate.depth_texture: em cada
## vista, a profundidade da superfície visível, renderizada para a combinação de peças): o shader
## car_paint compara a profundidade do ponto com a do mapa (folga DEPTH_EPS). O molde é renderizado
## com o mesmo mapa, então o que se pinta cai exatamente onde aparece.
##
## * Molde (CarSkinTemplate): o carro como está (cores, esquema, skin atual) em cada quadro, sem
##   luz, só as superfícies pintáveis, e a camada de linhas (peças, saltos de profundidade, áreas
##   muito inclinadas, nomes) à parte. Pintar por cima e importar: o que ficar transparente mostra a
##   pintura normal (cores e esquema).
## * Arquivos (user://skins/): <hash>.webp = versão da rede (1024 px, o hash é dela) e
##   <hash>.hd.webp = versão cheia (2048 px) de quem importou. Skins de outros jogadores, baixadas
##   do servidor, ficam no mesmo lugar (só a versão da rede).
## * Equipado: Profile.equipped["skin"] = hash ("" = sem skin). Online o servidor guarda as imagens
##   (pede a quem tem com "skin_need") e entrega a quem precisa ("skin_get").

signal skin_ready(hash: String)
## Mapa de profundidade pronto para uma combinação de peças (CarSkinTemplate.depth_texture).
signal depth_ready(key: String)

## Lado do molde (px) e da versão da rede.
const SIZE := 2048
const NET_SIZE := 1024
## Mapa de profundidade: metade da resolução do molde (mesmo layout, retângulos visíveis / 2).
const DEPTH_SIZE := 1024
## Escalas (px por metro) das camadas visível e escondida, e caixa do carro (m) que cabe em todas
## as peças.
const SCALE := 250.0
const SCALE_HIDDEN := 120.0
const BOX_MIN := Vector3(-1.1, 0.0, -3.2)
const BOX_MAX := Vector3(1.1, 1.2, 3.2)
## Uma superfície atrás da visível por mais que isso (m) é escondida.
const DEPTH_EPS := 0.02
## Faces (vistas): índice usado no shader.
enum Face { LEFT, RIGHT, TOP, BOTTOM, FRONT, BACK }
const FACE_NAMES := ["LADO ESQUERDO", "LADO DIREITO", "CIMA", "BAIXO", "FRENTE", "TRÁS"]
const HIDDEN_NAMES := ["ESCONDIDO · LADO ESQ.", "ESCONDIDO · LADO DIR.", "ESCONDIDO · CIMA", "BAIXO (EMBAIXO DO CARRO)",
	"ESCONDIDO · FRENTE", "ESCONDIDO · TRÁS"]
## Vistas com camada visível (a de baixo só tem a escondida).
const VISIBLE_FACES := [Face.LEFT, Face.RIGHT, Face.TOP, Face.FRONT, Face.BACK]
const ALL_FACES := [Face.LEFT, Face.RIGHT, Face.TOP, Face.BOTTOM, Face.FRONT, Face.BACK]
## Retângulos (px) da camada visível. Lado esquerdo: frente à esquerda; lado direito e cima: frente
## à direita (em cima, o lado esquerdo do carro fica no alto). A de baixo aponta para a escondida.
const RECTS := [
	Rect2i(40, 40, 1600, 300),
	Rect2i(40, 376, 1600, 300),
	Rect2i(40, 712, 1600, 550),
	Rect2i(1220, 1298, 768, 264),
	Rect2i(40, 1298, 550, 300),
	Rect2i(630, 1298, 550, 300),
]
## Retângulos (px) da camada escondida (e da parte de baixo).
const RECTS_HIDDEN := [
	Rect2i(40, 1634, 768, 144),
	Rect2i(40, 1814, 768, 144),
	Rect2i(848, 1634, 768, 264),
	Rect2i(1220, 1298, 768, 264),
	Rect2i(1680, 40, 264, 144),
	Rect2i(1680, 220, 264, 144),
]
## Tamanho máximo dos arquivos aceitos (bytes): importado e recebido pela rede.
const MAX_IMPORT_BYTES := 32 * 1024 * 1024
const MAX_NET_BYTES := 1024 * 1024
const DIR := "user://skins"
## Pasta das skins (os testes usam outra).
static var dir := DIR

static var _instance: CarSkin
## hash -> ImageTexture (versão cheia quando existe)
static var _textures := {}
## Pedidos ao servidor em andamento: hash -> tempo do pedido (ms)
static var _pending := {}


## Emissor dos avisos (skin baixada): CarSkin.events().skin_ready.
static func events() -> CarSkin:
	if _instance == null:
		_instance = CarSkin.new()
	return _instance


static func valid_hash(h: String) -> bool:
	if h.length() != 64:
		return false
	for ch in h:
		if not ch in "0123456789abcdef":
			return false
	return true


# ---------------------------------------------------------------------------
# Planificação (mesmas contas do shader car_paint)
# ---------------------------------------------------------------------------
static func face_of(n: Vector3) -> int:
	var a := n.abs()
	if a.x >= a.y and a.x >= a.z:
		return Face.LEFT if n.x >= 0.0 else Face.RIGHT
	if a.y >= a.z:
		return Face.TOP if n.y >= 0.0 else Face.BOTTOM
	return Face.FRONT if n.z >= 0.0 else Face.BACK


## Coordenada (0..1) dentro do retângulo da face, para o ponto p do carro.
static func face_uv(face: int, p: Vector3) -> Vector2:
	var size := BOX_MAX - BOX_MIN
	match face:
		Face.LEFT:
			return Vector2((BOX_MAX.z - p.z) / size.z, (BOX_MAX.y - p.y) / size.y)
		Face.RIGHT:
			return Vector2((p.z - BOX_MIN.z) / size.z, (BOX_MAX.y - p.y) / size.y)
		Face.TOP:
			return Vector2((p.z - BOX_MIN.z) / size.z, (BOX_MAX.x - p.x) / size.x)
		Face.BOTTOM:
			return Vector2((p.z - BOX_MIN.z) / size.z, (p.x - BOX_MIN.x) / size.x)
		Face.FRONT:
			return Vector2((p.x - BOX_MIN.x) / size.x, (BOX_MAX.y - p.y) / size.y)
	return Vector2((BOX_MAX.x - p.x) / size.x, (BOX_MAX.y - p.y) / size.y)


## Retângulo da face numa camada (0 visível, 1 escondida; a de baixo é sempre a escondida).
static func rect_of(face: int, layer := 0) -> Rect2i:
	return RECTS_HIDDEN[face] if layer == 1 or face == Face.BOTTOM else RECTS[face]


## Pixel do molde para o ponto p com normal n, na camada dada.
static func pixel_of(p: Vector3, n: Vector3, layer := 0) -> Vector2:
	var f := face_of(n)
	var r := rect_of(f, layer)
	return Vector2(r.position) + face_uv(f, p) * Vector2(r.size)


## Retângulos normalizados (x, y, largura, altura) para o shader: os 6 visíveis e os 6 escondidos.
static func rects_uniform() -> PackedVector4Array:
	var out := PackedVector4Array()
	for layer in 2:
		for f in 6:
			var r := rect_of(f, layer)
			out.append(Vector4(r.position.x, r.position.y, r.size.x, r.size.y) / float(SIZE))
	return out


## Câmera ortográfica que vê a face como o molde a mostra: [posição, alvo, cima, altura (m)].
static func face_camera(face: int) -> Array:
	var c := (BOX_MIN + BOX_MAX) * 0.5
	var size := BOX_MAX - BOX_MIN
	match face:
		Face.LEFT:
			return [Vector3(BOX_MAX.x + 5.0, c.y, c.z), c, Vector3.UP, size.y]
		Face.RIGHT:
			return [Vector3(BOX_MIN.x - 5.0, c.y, c.z), c, Vector3.UP, size.y]
		Face.TOP:
			return [Vector3(c.x, BOX_MAX.y + 5.0, c.z), c, Vector3(1, 0, 0), size.x]
		Face.BOTTOM:
			return [Vector3(c.x, BOX_MIN.y - 5.0, c.z), c, Vector3(-1, 0, 0), size.x]
		Face.FRONT:
			return [Vector3(c.x, c.y, BOX_MAX.z + 5.0), c, Vector3.UP, size.y]
	return [Vector3(c.x, c.y, BOX_MIN.z - 5.0), c, Vector3.UP, size.y]


## Chave da combinação de peças de um carro (o mapa de profundidade é um por combinação).
static func parts_key(config: CarConfig) -> String:
	var parts := []
	for slot in CarPartCatalog.SLOTS:
		parts.append(config.get_part(slot))
	return ",".join(parts)


# ---------------------------------------------------------------------------
# Arquivos
# ---------------------------------------------------------------------------
static func ensure_dir() -> String:
	var abs_dir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	return abs_dir


static func net_path(h: String) -> String:
	return ProjectSettings.globalize_path(dir).path_join(h + ".webp")


static func hd_path(h: String) -> String:
	return ProjectSettings.globalize_path(dir).path_join(h + ".hd.webp")


static func has_local(h: String) -> bool:
	return valid_hash(h) and FileAccess.file_exists(net_path(h))


## Bytes da versão da rede (para mandar ao servidor); vazio se não tem.
static func net_bytes(h: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(net_path(h)) if has_local(h) else PackedByteArray()


## Importa numa thread (sem travar o jogo: uma imagem grande leva alguns segundos, e o servidor
## derruba quem fica 5 s sem responder). Mesmos resultados de import_file / import_image.
static func import_file_async(path: String) -> Dictionary:
	return await _in_thread(_read_and_import.bind(path))


static func import_image_async(img: Image) -> Dictionary:
	return await _in_thread(_import.bind(img))


static func _in_thread(job: Callable) -> Dictionary:
	var t := Thread.new()
	t.start(job)
	var tree := Engine.get_main_loop() as SceneTree
	while t.is_alive():
		await tree.process_frame
	var res: Dictionary = t.wait_to_finish()
	if res.get("ok", false):
		_textures.erase(res["hash"])
	return res


## Importa uma imagem pintada sobre o molde (PNG, JPG ou WebP). Devolve {ok, hash} ou {ok: false,
## error}. Imagem de outro tamanho é redimensionada para o molde (o ideal é a mesma proporção).
static func import_file(path: String) -> Dictionary:
	var res := _read_and_import(path)
	if res.get("ok", false):
		_textures.erase(res["hash"])
	return res


static func _read_and_import(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Arquivo não encontrado."}
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > MAX_IMPORT_BYTES:
		return {"ok": false, "error": "Arquivo grande demais (máximo 32 MB)."}
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match path.get_extension().to_lower():
		"png":
			err = img.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			err = img.load_jpg_from_buffer(bytes)
		"webp":
			err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return {"ok": false, "error": "Não deu para ler a imagem (use PNG, JPG ou WebP)."}
	return _import(img)


static func import_image(src: Image) -> Dictionary:
	var res := _import(src)
	if res.get("ok", false):
		_textures.erase(res["hash"])
	return res


## O trabalho da importação (pode rodar numa thread: não mexe no cache de texturas).
static func _import(src: Image) -> Dictionary:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != SIZE or img.get_height() != SIZE:
		img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	# Cor das bordas transparentes = cor vizinha (sem halo escuro no filtro)
	img.fix_alpha_edges()
	# Versão da rede: 1024 px; se uma pintura muito detalhada não couber em 1 MB, menor
	var net_bytes_ := PackedByteArray()
	for side: int in [NET_SIZE, 768, 512]:
		var net := img.duplicate() as Image
		net.resize(side, side, Image.INTERPOLATE_LANCZOS)
		for q: float in [0.85, 0.6]:
			net_bytes_ = net.save_webp_to_buffer(true, q)
			if net_bytes_.size() <= MAX_NET_BYTES:
				break
		if net_bytes_.size() <= MAX_NET_BYTES:
			break
	if net_bytes_.size() > MAX_NET_BYTES:
		return {"ok": false, "error": "A imagem ficou grande demais para a rede."}
	var h := hash_bytes(net_bytes_)
	ensure_dir()
	var f := FileAccess.open(net_path(h), FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Não deu para gravar a skin (%d)." % FileAccess.get_open_error()}
	f.store_buffer(net_bytes_)
	f.close()
	var hd := FileAccess.open(hd_path(h), FileAccess.WRITE)
	if hd:
		hd.store_buffer(img.save_webp_to_buffer(true, 0.92))
		hd.close()
	return {"ok": true, "hash": h}


static func hash_bytes(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## Confere bytes da rede: hash certo, tamanho e WebP quadrado de até NET_SIZE.
static func check_net_bytes(h: String, bytes: PackedByteArray) -> bool:
	if not valid_hash(h) or bytes.is_empty() or bytes.size() > MAX_NET_BYTES or hash_bytes(bytes) != h:
		return false
	var img := Image.new()
	if img.load_webp_from_buffer(bytes) != OK:
		return false
	return img.get_width() == img.get_height() and img.get_width() <= NET_SIZE and img.get_width() >= 64


## Skin recebida do servidor: confere, grava e avisa quem esperava.
static func receive(h: String, bytes: PackedByteArray) -> bool:
	_pending.erase(h)
	if not check_net_bytes(h, bytes):
		return false
	ensure_dir()
	var f := FileAccess.open(net_path(h), FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	_textures.erase(h)
	events().skin_ready.emit(h)
	return true


## Skins importadas neste aparelho (as que têm a versão cheia), da mais nova para a mais velha.
static func own_skins() -> Array[String]:
	var abs_dir := ProjectSettings.globalize_path(dir)
	var list := []
	if not DirAccess.dir_exists_absolute(abs_dir):
		return []
	for f in DirAccess.get_files_at(abs_dir):
		if f.ends_with(".hd.webp"):
			var h := f.trim_suffix(".hd.webp")
			if valid_hash(h):
				list.append([FileAccess.get_modified_time(abs_dir.path_join(f)), h])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out: Array[String] = []
	for e in list:
		out.append(e[1])
	return out


static func delete(h: String) -> void:
	if not valid_hash(h):
		return
	DirAccess.remove_absolute(net_path(h))
	DirAccess.remove_absolute(hd_path(h))
	_textures.erase(h)


# ---------------------------------------------------------------------------
# Texturas
# ---------------------------------------------------------------------------
## Textura da skin (com mipmaps); null se ainda não tem o arquivo (pede ao servidor quando online).
static func texture(h: String) -> Texture2D:
	if not valid_hash(h):
		return null
	if _textures.has(h):
		return _textures[h]
	var img := Image.new()
	var path := hd_path(h) if FileAccess.file_exists(hd_path(h)) else net_path(h)
	if not FileAccess.file_exists(path) or img.load_webp_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		fetch(h)
		return null
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	if _textures.size() > 32:
		_textures.clear()
	_textures[h] = tex
	return tex


## Pede a skin ao servidor (uma vez a cada 20 s por hash), se este processo é um jogo conectado.
static func fetch(h: String) -> void:
	if NetProtocol.is_server_process() or not valid_hash(h):
		return
	var now := Time.get_ticks_msec()
	if _pending.has(h) and now - int(_pending[h]) < 20000:
		return
	var tree := Engine.get_main_loop() as SceneTree
	var net := tree.root.get_node_or_null("Net") if tree else null
	if net == null or not net.online:
		return
	_pending[h] = now
	net.send_to_server("skin_get", {"hash": h})


static func clear_cache() -> void:
	_textures.clear()
