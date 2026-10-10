class_name CarSkinTemplate
extends RefCounted
## Gera o MOLDE da skin (CarSkin): o carro do jogador planificado nas vistas, do jeito que o shader
## lê a skin, numa imagem 2048×2048 para pintar por cima.
##
## Cada vista é renderizada numa SubViewport própria (mundo 3D isolado e compartilhado entre elas,
## sem luz e sem efeitos),
## com câmera ortográfica do tamanho exato do retângulo da vista (CarSkin.face_camera), e a pintura
## em modo molde (car_paint template_view): só as faces que pegam aquela vista, na cor pura (as
## cores, o esquema e a skin atual). O resto do carro (carbono, pneus, piloto, decalques) some.
## Depois, uma passada 2D desenha o contorno do carro (do lado de fora) e as legendas nas faixas
## entre as vistas, que não caem em nenhuma face.

const OUTLINE := Color(0.06, 0.07, 0.1)
const LABEL := Color(0.2, 0.22, 0.3)

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


## Renderiza o molde do carro com esta configuração. `host` é qualquer nó dentro da árvore (as
## viewports ficam penduradas nele durante a renderização).
static func render(host: Node, config: CarConfig) -> Image:
	var atlas := Image.create(CarSkin.SIZE, CarSkin.SIZE, false, Image.FORMAT_RGBA8)
	# Uma viewport por vista (tamanho e câmera fixos), todas olhando o mesmo mundo 3D
	var faces := [CarSkin.Face.LEFT, CarSkin.Face.RIGHT, CarSkin.Face.TOP, CarSkin.Face.FRONT, CarSkin.Face.BACK]
	var vps: Array[SubViewport] = []
	var world: World3D
	var env := _environment()
	for face: int in faces:
		var r: Rect2i = CarSkin.RECTS[face]
		var vp := SubViewport.new()
		vp.name = "SkinTemplate3D_%d" % face
		vp.size = r.size
		vp.transparent_bg = true
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = false
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if world == null:
			vp.own_world_3d = true
		host.add_child(vp)
		if world == null:
			world = vp.find_world_3d()
		else:
			vp.world_3d = world
		var c: Array = CarSkin.face_camera(face)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = c[3]
		cam.near = 0.1
		cam.far = 30.0
		cam.environment = env
		vp.add_child(cam)
		cam.look_at_from_position(c[0], c[1], c[2])
		cam.current = true
		vps.append(vp)
	var assembly := CarAssembly.new()
	vps[0].add_child(assembly)
	var cfg := config.duplicate() as CarConfig
	assembly.sync(cfg, [])
	var decals := assembly.get_node_or_null("Decals") as Node3D
	if decals:
		decals.visible = false
	_hide_unpainted(assembly)
	for k in faces.size():
		var face: int = faces[k]
		var r: Rect2i = CarSkin.RECTS[face]
		assembly.livery.set_template_view(face)
		vps[k].render_target_update_mode = SubViewport.UPDATE_ONCE
		for i in 3:
			await RenderingServer.frame_post_draw
		var img := vps[k].get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, r.size), r.position)
	for vp in vps:
		vp.queue_free()
	return await _decorate(host, atlas)


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


## Contorno do carro (do lado de fora) e legendas nas faixas entre as vistas.
static func _decorate(host: Node, atlas: Image) -> Image:
	var vp := SubViewport.new()
	vp.name = "SkinTemplate2D"
	vp.size = Vector2i(CarSkin.SIZE, CarSkin.SIZE)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(vp)
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
	var font := Retro.display(800)
	for face in [CarSkin.Face.LEFT, CarSkin.Face.RIGHT, CarSkin.Face.TOP, CarSkin.Face.FRONT, CarSkin.Face.BACK]:
		var r: Rect2i = CarSkin.RECTS[face]
		var arrow := ""
		match face:
			CarSkin.Face.LEFT:
				arrow = "◀ FRENTE"
			CarSkin.Face.RIGHT, CarSkin.Face.TOP:
				arrow = "FRENTE ▶"
		_label(vp, font, CarSkin.FACE_NAMES[face], Vector2(r.position.x, r.position.y - 32), 20)
		if arrow != "":
			_label(vp, font, arrow, Vector2(r.end.x - 160, r.position.y - 32), 20)
		var frame := ReferenceRect.new()
		frame.position = Vector2(r.position) - Vector2(4, 4)
		frame.size = Vector2(r.size) + Vector2(8, 8)
		frame.border_color = Color(LABEL, 0.5)
		frame.border_width = 1.0
		frame.editor_only = false
		vp.add_child(frame)
	var legend := "SPEEDORU · MOLDE DA SKIN\nPinte por cima e importe no Estúdio.\nTransparente = pintura normal do carro.\nFora dos quadros não aparece no carro."
	_label(vp, font, legend, Vector2(1500, 1560), 18)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out := vp.get_texture().get_image()
	out.convert(Image.FORMAT_RGBA8)
	vp.queue_free()
	return out


static func _label(parent: Node, font: Font, text: String, pos: Vector2, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", LABEL)
	parent.add_child(l)
