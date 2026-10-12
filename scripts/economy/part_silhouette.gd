class_name PartSilhouette
extends Node
## Silhueta branca de cada peça do carro (arte dos cartões no Estúdio, na Galeria e no giro da
## loja): a peça é desenhada uma vez numa SubViewport de fundo transparente, toda branca e sem luz,
## em vista ortográfica escolhida por lugar do carro (o que mais diferencia as variantes), e vira
## uma textura recortada na forma. Fica em cache pelo resto do jogo.
##
## Os pedidos do mesmo quadro saem juntos (uma SubViewport por peça, todas no mesmo quadro). Sem
## placa de vídeo (headless) a imagem volta vazia: `texture` devolve null e o cartão fica sem arte.

## Emitido quando uma leva de silhuetas fica pronta (os cartões se redesenham).
signal rendered

## Resolução de cada silhueta (2x o cartão, para ficar nítida).
const SIZE := Vector2i(288, 168)
## Vista por lugar: [de onde a câmera olha, para cima na tela, (fração da profundidade desenhada,
## a partir da frente)]. O carro anda para +Z; +X é a esquerda. Rodas: só a face de fora (senão o
## aro de trás tapa os vãos entre os raios).
const VIEWS := {
	"nose": [Vector3.UP, Vector3.LEFT],
	"front_wing": [Vector3(0.0, 1.0, 0.8), Vector3.UP],
	"rear_wing": [Vector3(0.0, 0.35, -1.0), Vector3.UP],
	"sidepods": [Vector3.RIGHT, Vector3.UP],
	"engine_cover": [Vector3.RIGHT, Vector3.UP],
	"halo": [Vector3(0.0, 0.25, 1.0), Vector3.UP],
	"mirrors": [Vector3.RIGHT, Vector3.UP],
	"rim": [Vector3.RIGHT, Vector3.UP, 0.3],
}
## Leva máxima por quadro.
const BATCH := 24

static var _instance: PartSilhouette
static var _cache := {}
static var _pending: Array[String] = []
static var _material: StandardMaterial3D

var _busy := false


## Textura da silhueta (null enquanto não fica pronta ou sem placa de vídeo). O primeiro pedido
## agenda o desenho; conecte em `notifier().rendered` para redesenhar quando sair.
static func texture(slot: String, variant: String) -> Texture2D:
	var key := slot + "/" + variant
	if _cache.has(key):
		return _cache[key]
	if not key in _pending and DisplayServer.get_name() != "headless":
		_pending.append(key)
		notifier()
	return null


## O nó que desenha e avisa (criado sob a raiz na primeira vez).
static func notifier() -> PartSilhouette:
	if not is_instance_valid(_instance):
		var tree := Engine.get_main_loop() as SceneTree
		_instance = PartSilhouette.new()
		_instance.name = "PartSilhouette"
		tree.root.add_child.call_deferred(_instance)
	return _instance


func _process(_delta: float) -> void:
	if not _busy and not _pending.is_empty():
		_render_batch()


func _render_batch() -> void:
	_busy = true
	var keys := _pending.slice(0, BATCH)
	var jobs := []
	for key in keys:
		var vp := _make_viewport(key.get_slice("/", 0), key.get_slice("/", 1))
		jobs.append([key, vp])
	# A SubViewport nova desenha no fim deste quadro; o resultado está pronto depois do próximo
	for k in 2:
		await RenderingServer.frame_post_draw
	for job in jobs:
		var key: String = job[0]
		var vp: SubViewport = job[1]
		_cache[key] = _to_texture(vp.get_texture().get_image()) if vp else null
		_pending.erase(key)
		if vp:
			vp.queue_free()
	_busy = false
	rendered.emit()


func _make_viewport(slot: String, variant: String) -> SubViewport:
	var path := CarPartCatalog.wheel_part_path(slot, variant, "front") if CarPartCatalog.is_wheel_slot(slot) \
		else CarPartCatalog.part_path(slot, variant)
	var scene := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if scene == null:
		return null
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(1, 1, 1, 0)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	vp.add_child(env)
	var part := scene.instantiate() as Node3D
	vp.add_child(part)
	var aabb := _whiten(part, part.global_transform.affine_inverse())
	if aabb.size == Vector3.ZERO:
		vp.queue_free()
		return null
	var view: Array = VIEWS.get(slot, [Vector3.RIGHT, Vector3.UP])
	var eye_dir: Vector3 = (view[0] as Vector3).normalized()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var center := aabb.get_center()
	var radius := aabb.size.length()
	vp.add_child(cam)
	cam.look_at_from_position(center + eye_dir * radius * 2.0, center, view[1])
	# Enquadra: maior extensão dos cantos da caixa nos eixos da tela
	var right := cam.global_basis.x
	var up := cam.global_basis.y
	var half := Vector3.ZERO
	for i in 8:
		var d := aabb.get_endpoint(i) - center
		half = Vector3(maxf(half.x, absf(d.dot(right))), maxf(half.y, absf(d.dot(up))), maxf(half.z, absf(d.dot(eye_dir))))
	var aspect := float(SIZE.x) / SIZE.y
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = maxf(half.y, half.x / aspect) * 2.0 * 1.08
	cam.near = radius * 0.5
	cam.far = radius * 4.0
	if view.size() > 2:
		cam.near = radius * 2.0 - half.z - 0.01
		cam.far = cam.near + half.z * 2.0 * float(view[2])
	return vp


## Toda a peça em branco sem luz (e só malhas: sem decalques, luzes nem partículas); devolve a
## caixa das malhas no espaço da peça.
static func _whiten(node: Node, to_local: Transform3D) -> AABB:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.albedo_color = Color.WHITE
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var box := AABB()
	var first := true
	for child in node.find_children("*", "VisualInstance3D", true, false):
		var vi := child as VisualInstance3D
		if vi is MeshInstance3D and (vi as MeshInstance3D).mesh:
			(vi as MeshInstance3D).material_override = _material
			var b := (to_local * vi.global_transform) * vi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		else:
			vi.visible = false
	return box


## A forma recortada na área usada (o fundo branco transparente do mundo deixa a borda suavizada
## branca também).
static func _to_texture(img: Image) -> Texture2D:
	if img == null or img.is_empty():
		return null
	var used := img.get_used_rect()
	if used.size.x < 2 or used.size.y < 2:
		return null
	return ImageTexture.create_from_image(img.get_region(used.grow(2).intersection(Rect2i(Vector2i.ZERO, img.get_size()))))


## Desenha a silhueta centralizada em `box` (mantendo a proporção). Devolve false se ainda não há.
static func draw(ci: CanvasItem, slot: String, variant: String, box: Rect2, color := Color.WHITE) -> bool:
	var tex := texture(slot, variant)
	if tex == null:
		return false
	var k := minf(box.size.x / tex.get_width(), box.size.y / tex.get_height())
	var sz := Vector2(tex.get_width(), tex.get_height()) * k
	ci.draw_texture_rect(tex, Rect2(box.get_center() - sz * 0.5, sz), false, color)
	return true
