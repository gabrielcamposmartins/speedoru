class_name CarSkinTemplate
extends RefCounted
## Gera o MOLDE da skin (CarSkin), o MAPA DE PROFUNDIDADE que separa o visível do escondido e a
## camada de LINHAS (guia).
##
## * Mapa de profundidade (depth_texture): em cada vista, a profundidade (16 bits) da superfície
##   pintável mais perto de quem olha, só das faces que pegam aquela vista, na metade da resolução do
##   molde. Um por combinação de peças (CarSkin.parts_key), feito uma vez e guardado; os carros com
##   skin o usam no shader (car_paint skin_depth) para saber o que é escondido.
## * Molde (2048×2048): o carro do jogador em cada quadro — os VISÍVEIS (250 px/m) e os ESCONDIDOS e
##   a parte de baixo (120 px/m) —, na cor pura (as cores, o esquema e a skin atual), sem luz, com
##   contorno e legendas fora do carro.
## * Linhas (mesmo tamanho, à parte, para usar como camada de cima e esconder ao exportar): o
##   contorno de cada peça, os saltos de profundidade (uma superfície por cima de outra), hachura
##   nas áreas muito inclinadas (onde o desenho estica) e o nome das peças em cada região.
##
## Cada quadro é renderizado numa SubViewport própria, com câmera ortográfica do tamanho exato do
## retângulo (CarSkin.face_camera), todas olhando o mesmo mundo 3D isolado, sem luz e sem efeitos; a
## pintura em modo molde (car_paint template_view / template_layer / template_out) mostra só as
## faces daquele quadro. O resto do carro (carbono, pneus, piloto, decalques) some.

const OUTLINE := Color(0.06, 0.07, 0.1)
const LABEL := Color(0.2, 0.22, 0.3)
const LINE := Color(0.03, 0.04, 0.08, 0.92)
const HALO := Color(1.0, 1.0, 1.0, 0.85)
const HATCH := Color(0.95, 0.1, 0.3, 0.6)
## Salto de profundidade (níveis de 8 bits da vista) que vira linha.
const DEPTH_STEP := 3.0
## Inclinação (maior componente da normal) abaixo da qual a área ganha hachura: o desenho estica
## mais de ~25% ali.
const TILT_HATCH := 0.8
## Rótulos das peças: grade da busca por regiões (px) e tamanho mínimo da região (células).
const LABEL_STEP := 6
const LABEL_MIN_CELLS := 60
const LABEL_MIN_CELLS_HIDDEN := 14

const _HIDE_SHADER := "shader_type spatial;\nrender_mode unshaded;\nvoid fragment() { discard; }\n"
const _OUTLINE_SHADER := """shader_type canvas_item;
uniform vec4 outline_color : source_color;
uniform float px = 1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.01) {
		float near = 0.0;
		for (int i = -2; i <= 2; i++) {
			for (int j = -2; j <= 2; j++) {
				near = max(near, texture(TEXTURE, UV + vec2(float(i), float(j)) * px).a);
			}
		}
		c = near > 0.01 ? outline_color : vec4(0.0);
	}
	COLOR = c;
}
"""
## Linhas: muda a peça (R) ou a profundidade salta (G), ou é a borda do carro — preta, com um
## contorno branco em volta (aparece sobre qualquer cor e fundo); hachura onde a superfície é muito
## inclinada para a vista (B).
const _EDGE_SHADER = """shader_type canvas_item;
uniform vec4 line_color : source_color;
uniform vec4 halo_color : source_color;
uniform vec4 hatch_color : source_color;
uniform float px = 1.0;
uniform float depth_step = 3.0;
uniform float tilt_hatch = 0.8;

float is_edge(sampler2D tex, vec2 uv) {
	vec4 c = texture(tex, uv);
	vec2 offs[4] = vec2[](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0));
	for (int k = 0; k < 4; k++) {
		vec4 n = texture(tex, uv + offs[k] * px);
		if ((n.a > 0.5) != (c.a > 0.5)) {
			return c.a > 0.5 ? 1.0 : 0.0;
		}
		if (c.a > 0.5) {
			vec3 d = abs(n.rgb - c.rgb) * 255.0;
			if (d.r > 0.5 || d.g > depth_step) {
				return 1.0;
			}
		}
	}
	return 0.0;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (is_edge(TEXTURE, UV) > 0.0) {
		COLOR = line_color;
	} else {
		float near = 0.0;
		for (int i = -2; i <= 2; i++) {
			for (int j = -2; j <= 2; j++) {
				if (i != 0 || j != 0) {
					near = max(near, is_edge(TEXTURE, UV + vec2(float(i), float(j)) * px));
				}
			}
		}
		if (near > 0.0) {
			COLOR = halo_color;
		} else if (c.a > 0.5 && c.b < tilt_hatch && mod(FRAGCOORD.x + FRAGCOORD.y, 9.0) < 1.5) {
			COLOR = hatch_color;
		} else {
			COLOR = vec4(0.0);
		}
	}
}
"""

## Mapas de profundidade prontos (chave das peças -> textura) e os que estão sendo feitos.
static var _depth := {}
static var _depth_pending := {}


# ---------------------------------------------------------------------------
# Mapa de profundidade (também usado pelos carros no jogo)
# ---------------------------------------------------------------------------
## Mapa de profundidade desta combinação de peças; null se ainda não existe (começa a fazer e avisa
## por CarSkin.events().depth_ready). Sem tela (servidor, testes sem janela) não há mapa.
static func depth_texture(config: CarConfig) -> Texture2D:
	var key := CarSkin.parts_key(config)
	if _depth.has(key):
		return _depth[key]
	if DisplayServer.get_name() == "headless" or NetProtocol.is_server_process():
		return null
	if not _depth_pending.has(key):
		_depth_pending[key] = true
		_bake_later(key, config.duplicate() as CarConfig)
	return null


static func _bake_later(key: String, cfg: CarConfig) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var tex := await bake_depth(tree.root, cfg)
	_depth[key] = tex
	_depth_pending.erase(key)
	CarSkin.events().depth_ready.emit(key)


## Renderiza o mapa de profundidade das peças desta configuração (a skin e as cores não importam).
static func bake_depth(host: Node, config: CarConfig) -> ImageTexture:
	var cfg := config.duplicate() as CarConfig
	cfg.skin = ""
	var scene := _scene(host, cfg)
	var img := Image.create(CarSkin.DEPTH_SIZE, CarSkin.DEPTH_SIZE, false, Image.FORMAT_RGBA8)
	for face: int in CarSkin.VISIBLE_FACES:
		var r: Rect2i = CarSkin.RECTS[face]
		var dr := Rect2i(r.position / 2, r.size / 2)
		_params(scene["materials"], {"template_view": face, "template_layer": 0, "template_out": 2, "use_skin_depth": false})
		var shot := await _shoot(host, scene["world"], face, dr.size)
		img.blit_rect(shot, Rect2i(Vector2i.ZERO, dr.size), dr.position)
	(scene["holder"] as Node).queue_free()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------------------
# Molde e linhas
# ---------------------------------------------------------------------------
## Renderiza o molde do carro com esta configuração. `host` é qualquer nó dentro da árvore (as
## viewports ficam penduradas nele durante a renderização).
static func render(host: Node, config: CarConfig) -> Image:
	var layers := await render_layers(host, config)
	return layers["template"]


## O molde e a camada de linhas: {"template": Image, "lines": Image}.
static func render_layers(host: Node, config: CarConfig) -> Dictionary:
	var key := CarSkin.parts_key(config)
	var depth: Texture2D = _depth.get(key)
	if depth == null:
		depth = await bake_depth(host, config)
		_depth[key] = depth
	var scene := _scene(host, config.duplicate() as CarConfig)
	var mats: Array = scene["materials"]
	_params(mats, {"use_skin_depth": true, "skin_depth": depth})
	var atlas := Image.create(CarSkin.SIZE, CarSkin.SIZE, false, Image.FORMAT_RGBA8)
	var ids := Image.create(CarSkin.SIZE, CarSkin.SIZE, false, Image.FORMAT_RGBA8)
	for layer in 2:
		for face: int in (CarSkin.VISIBLE_FACES if layer == 0 else CarSkin.ALL_FACES):
			var r := CarSkin.rect_of(face, layer)
			for out in [0, 1]:
				_params(mats, {"template_view": face, "template_layer": layer, "template_out": out})
				var shot := await _shoot(host, scene["world"], face, r.size)
				(atlas if out == 0 else ids).blit_rect(shot, Rect2i(Vector2i.ZERO, r.size), r.position)
	(scene["holder"] as Node).queue_free()
	return {
		"template": await _decorate(host, atlas),
		"lines": await _lines(host, ids, scene["names"]),
	}


## Mundo 3D só com a pintura da carroceria: {holder, world, materials (um por malha), names}.
static func _scene(host: Node, cfg: CarConfig) -> Dictionary:
	var holder := SubViewport.new()
	holder.name = "SkinTemplateWorld"
	holder.own_world_3d = true
	holder.size = Vector2i(2, 2)
	holder.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(holder)
	var assembly := CarAssembly.new()
	holder.add_child(assembly)
	assembly.sync(cfg, [])
	var decals := assembly.get_node_or_null("Decals") as Node3D
	if decals:
		decals.visible = false
	_hide_unpainted(assembly)
	var info := _tag_parts(assembly)
	info["holder"] = holder
	info["world"] = holder.find_world_3d()
	return info


static func _params(mats: Array, values: Dictionary) -> void:
	for m: ShaderMaterial in mats:
		for k: String in values:
			m.set_shader_parameter(k, values[k])


## Uma foto ortográfica da vista `face` (viewport própria, do tamanho exato do retângulo).
static func _shoot(host: Node, world: World3D, face: int, size: Vector2i) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.world_3d = world
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(vp)
	var c: Array = CarSkin.face_camera(face)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = c[3]
	cam.near = 0.1
	cam.far = 30.0
	cam.environment = _environment()
	vp.add_child(cam)
	cam.look_at_from_position(c[0], c[1], c[2])
	cam.current = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	vp.queue_free()
	return img


## Esconde o que não recebe skin: tudo que não é pintura da carroceria.
static func _hide_unpainted(assembly: CarAssembly) -> void:
	var hide := ShaderMaterial.new()
	hide.shader = Shader.new()
	hide.shader.code = _HIDE_SHADER
	var paint := []
	for slot in CarLivery.LIVERY_SLOTS:
		paint.append(assembly.livery.materials[slot])
	for mi: MeshInstance3D in assembly.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			if not mi.get_surface_override_material(i) in paint:
				mi.set_surface_override_material(i, hide)
	for gi: GeometryInstance3D in assembly.find_children("*", "GeometryInstance3D", true, false):
		if not gi is MeshInstance3D:
			gi.visible = false


## Cada malha pintável ganha a própria cópia do material, com o código da peça (para a passada de
## identificação). Devolve {materials, names: código da peça -> nome}.
static func _tag_parts(assembly: CarAssembly) -> Dictionary:
	var paint := {}
	for slot in CarLivery.LIVERY_SLOTS:
		paint[assembly.livery.materials[slot]] = true
	var mats := []
	var names := {}
	var slots: Array = CarPartCatalog.SLOTS.keys()
	for k in slots.size():
		var part := assembly.get_part_node(slots[k])
		if part == null:
			continue
		var part_code := k + 1
		names[part_code] = CarPartCatalog.slot_label(slots[k]).to_upper()
		for mi: MeshInstance3D in part.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var src := mi.get_surface_override_material(i)
				if not paint.has(src):
					continue
				var m := (src as ShaderMaterial).duplicate() as ShaderMaterial
				m.set_shader_parameter("part_id", part_code / 255.0)
				mi.set_surface_override_material(i, m)
				mats.append(m)
	return {"materials": mats, "names": names}


## Sem luz nenhuma: a cor sai só pela emissão do modo molde, sem curva de tom.
static func _environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false
	return env


## Contorno do carro (do lado de fora) e legendas nas faixas entre os quadros.
static func _decorate(host: Node, atlas: Image) -> Image:
	var vp := _canvas(host, "SkinTemplate2D")
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(atlas)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.size = Vector2(CarSkin.SIZE, CarSkin.SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = _OUTLINE_SHADER
	mat.set_shader_parameter("outline_color", OUTLINE)
	mat.set_shader_parameter("px", 1.0 / CarSkin.SIZE)
	rect.material = mat
	vp.add_child(rect)
	_frames_and_titles(vp)
	_label(vp, Retro.display(800), "SPEEDORU\nMOLDE DA SKIN\n\nPinte por cima e importe\nno Estúdio.\n\nTransparente = pintura\nnormal do carro.\n\nQuadros grandes: o que\nse vê de cada lado.\n\nQuadros ESCONDIDO: o que\nfica atrás de outra parte\n(lado de dentro, elementos\nde baixo da asa…).\n\nBAIXO: embaixo do carro.\n\nFora dos quadros não\naparece no carro.\n\nGuia das peças e áreas\nque esticam (hachura):\no arquivo _linhas.png\n(camada de cima;\nesconda ao exportar).", Vector2(1680, 400), 15)
	return await _grab(vp)


## Camada de linhas: contorno das peças, saltos de profundidade, hachura nas áreas inclinadas e os
## nomes das peças.
static func _lines(host: Node, ids: Image, names: Dictionary) -> Image:
	var vp := _canvas(host, "SkinTemplateLines")
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(ids)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.size = Vector2(CarSkin.SIZE, CarSkin.SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = _EDGE_SHADER
	mat.set_shader_parameter("line_color", LINE)
	mat.set_shader_parameter("halo_color", HALO)
	mat.set_shader_parameter("hatch_color", HATCH)
	mat.set_shader_parameter("px", 1.0 / CarSkin.SIZE)
	mat.set_shader_parameter("depth_step", DEPTH_STEP)
	mat.set_shader_parameter("tilt_hatch", TILT_HATCH)
	rect.material = mat
	vp.add_child(rect)
	_frames_and_titles(vp)
	# Nome de cada peça em cada região contínua dela (as de dois lados ganham um em cada lado), num
	# ponto dentro da região e sem cobrir outro nome
	var font := Retro.display(800)
	for layer in 2:
		for face: int in (CarSkin.VISIBLE_FACES if layer == 0 else CarSkin.ALL_FACES):
			var placed: Array[Rect2] = []
			var min_cells := LABEL_MIN_CELLS if layer == 0 else LABEL_MIN_CELLS_HIDDEN
			for comp: Array in _components(ids, CarSkin.rect_of(face, layer), LABEL_STEP):
				var code: int = comp[0]
				if comp[1] < min_cells or not names.has(code):
					continue
				var size_px := 11 if layer == 1 else (14 if comp[1] < LABEL_MIN_CELLS * 3 else 16)
				var l := _label(vp, font, names[code], Vector2.ZERO, size_px)
				l.add_theme_color_override("font_color", Color(0.05, 0.06, 0.12))
				l.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
				l.add_theme_constant_override("outline_size", 5)
				var size := l.get_minimum_size()
				var box := Rect2((comp[2] as Vector2) - size * 0.5, size)
				if placed.any(func(o: Rect2) -> bool: return o.grow(4.0).intersects(box)):
					l.free()
					continue
				l.position = box.position
				placed.append(box)
	_label(vp, font, "SPEEDORU\nLINHAS DO MOLDE (GUIA)\n\nCamada de cima, por cima\ndo molde. Esconda antes\nde exportar a sua skin:\nas linhas não fazem\nparte da pintura.\n\nLinha: borda de peça ou\numa superfície por cima\nde outra.\n\nHachura vermelha: área\nmuito inclinada para\naquela vista — o desenho\nestica ali; evite detalhes\nfinos (rostos, textos).", Vector2(1680, 400), 15)
	return await _grab(vp)


## Regiões contínuas de cada peça num quadro (grade de `step` px na imagem de identificação), da
## maior para a menor: [código da peça, células, ponto da região mais perto do centro dela].
static func _components(ids: Image, r: Rect2i, step: int) -> Array:
	var w := r.size.x / step
	var h := r.size.y / step
	var codes := PackedInt32Array()
	codes.resize(w * h)
	for gy in h:
		for gx in w:
			var c := ids.get_pixel(r.position.x + gx * step, r.position.y + gy * step)
			codes[gy * w + gx] = int(round(c.r * 255.0)) if c.a > 0.5 else 0
	var seen := PackedByteArray()
	seen.resize(w * h)
	var out := []
	for start in w * h:
		if codes[start] == 0 or seen[start] == 1:
			continue
		var code := codes[start]
		var cells := PackedInt32Array([start])
		seen[start] = 1
		var k := 0
		while k < cells.size():
			var cur := cells[k]
			k += 1
			var cx := cur % w
			var cy := cur / w
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := cx + d.x
				var ny := cy + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni := ny * w + nx
				if seen[ni] == 0 and codes[ni] == code:
					seen[ni] = 1
					cells.append(ni)
		var sum := Vector2.ZERO
		for cell in cells:
			sum += Vector2(cell % w, cell / w)
		var center := sum / cells.size()
		var best := cells[0]
		var best_d := INF
		for cell in cells:
			var dd := Vector2(cell % w, cell / w).distance_squared_to(center)
			if dd < best_d:
				best_d = dd
				best = cell
		out.append([code, cells.size(), Vector2(r.position) + Vector2(best % w, best / w) * step])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return out


static func _canvas(host: Node, node_name: String) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = node_name
	vp.size = Vector2i(CarSkin.SIZE, CarSkin.SIZE)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(vp)
	return vp


static func _frames_and_titles(vp: SubViewport) -> void:
	var font := Retro.display(800)
	for layer in 2:
		for face: int in (CarSkin.VISIBLE_FACES if layer == 0 else CarSkin.ALL_FACES):
			var r := CarSkin.rect_of(face, layer)
			var title: String = CarSkin.FACE_NAMES[face] if layer == 0 else CarSkin.HIDDEN_NAMES[face]
			var size := 18 if layer == 0 else 13
			_label(vp, font, title, Vector2(r.position.x, r.position.y - 28), size)
			if layer == 0 and face in [CarSkin.Face.LEFT, CarSkin.Face.RIGHT, CarSkin.Face.TOP]:
				var arrow := "◀ FRENTE" if face == CarSkin.Face.LEFT else "FRENTE ▶"
				_label(vp, font, arrow, Vector2(r.end.x - 140, r.position.y - 28), 18)
			var frame := ReferenceRect.new()
			frame.position = Vector2(r.position) - Vector2(3, 3)
			frame.size = Vector2(r.size) + Vector2(6, 6)
			frame.border_color = Color(LABEL, 0.5)
			frame.border_width = 1.0
			frame.editor_only = false
			vp.add_child(frame)


static func _grab(vp: SubViewport) -> Image:
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out := vp.get_texture().get_image()
	out.convert(Image.FORMAT_RGBA8)
	vp.queue_free()
	return out


static func _label(parent: Node, font: Font, text: String, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", LABEL)
	parent.add_child(l)
	return l
