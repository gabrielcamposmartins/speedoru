class_name IntroDirector
extends CanvasLayer
## Apresentação antes da largada (filho do RaceManager): com os carros no grid, a câmera passa por
## cada um, do pole para trás (SHOT s cada, aproximando devagar pela frente, alternando o lado),
## com uma legenda "P3 · nome"; termina com uma órbita no carro do jogador (ORBIT s) que entrega
## para a câmera de perseguição. O HUD some durante a apresentação. Enter / A pula (só a câmera:
## no online o servidor espera a duração de length() antes do semáforo, para todos juntos).
## Desliga em Configurações → Jogo.

signal finished

const SHOT := 0.85
const ORBIT := 3.4

var manager: RaceManager
var camera: RaceCamera
var _caption: Label
var _sub: Label
var _hidden: Array[CanvasLayer] = []
var _skip := false


## Duração da apresentação com n carros (o servidor usa para esperar os clientes).
static func length(cars: int) -> float:
	return maxi(cars - 1, 0) * SHOT + ORBIT


## Liga nas configurações e só com janela (sem janela — testes, servidor — não há o que mostrar).
static func enabled(tree: SceneTree) -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var settings := tree.root.get_node_or_null("Settings") as GameSettings
	return settings == null or bool(settings.get_value("gameplay", "race_intro"))


func play(p_manager: RaceManager) -> void:
	manager = p_manager
	layer = 6
	process_mode = Node.PROCESS_MODE_PAUSABLE
	camera = manager.get_viewport().get_camera_3d() as RaceCamera
	if camera == null or manager.player_entry == null:
		finished.emit()
		return
	_build_ui()
	for layer_node in [manager.hud, manager.get_parent().get_node_or_null("HUD")]:
		if layer_node is CanvasLayer and layer_node.visible:
			layer_node.visible = false
			_hidden.append(layer_node)
	camera.cinematic = true
	if manager.line_guide:
		manager.line_guide.suppressed = true
	# Começa só depois que a tela de carregamento sumiu de todo
	while LoadingScreen.is_shown():
		await get_tree().process_frame
	var cars: Array[RaceEntry] = manager.roster.duplicate()
	cars.sort_custom(func(a: RaceEntry, b: RaceEntry) -> bool: return a.grid_slot < b.grid_slot)
	var side := 1.0
	for e in cars:
		if _skip:
			break
		if e == manager.player_entry or e.car == null:
			continue
		await _shot(e, side)
		side = -side
	if not _skip:
		await _orbit(manager.player_entry)
	_end()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		_skip = true
		get_viewport().set_input_as_handled()


func _caption_for(e: RaceEntry) -> void:
	_caption.text = "P%d  ·  %s" % [e.grid_slot + 1, e.name.to_upper()]
	_caption.add_theme_color_override("font_color", e.color.lightened(0.25))
	_sub.text = e.code + ("  ·  " + ["FÁCIL", "MÉDIO", "DIFÍCIL"][e.difficulty] if e.difficulty >= 0 and e.difficulty < 3 else "")


## Close de um carro: pela frente, de um lado, aproximando devagar.
func _shot(e: RaceEntry, side: float) -> void:
	_caption_for(e)
	var t := 0.0
	while t < SHOT and not _skip:
		var xf := e.car.get_global_transform_interpolated()
		var k := smoothstep(0.0, 1.0, t / SHOT)
		var local := Vector3(side * 2.5, 0.8, 4.8).lerp(Vector3(side * 1.9, 0.65, 3.7), k)
		var at := xf.origin + xf.basis.y * 0.5 + xf.basis.z * 0.6
		camera.global_transform = Transform3D(Basis(), xf * local).looking_at(at, Vector3.UP)
		camera.fov = 52.0
		t += await _tick()


## Órbita no carro do jogador: começa pela frente-direita e gira até ficar atrás (a câmera de
## perseguição continua dali sem salto).
func _orbit(e: RaceEntry) -> void:
	_caption_for(e)
	_caption.text = "P%d  ·  VOCÊ" % (e.grid_slot + 1)
	var t := 0.0
	while t < ORBIT and not _skip:
		var xf := e.car.get_global_transform_interpolated()
		var k := smoothstep(0.0, 1.0, t / ORBIT)
		var ang := lerpf(deg_to_rad(40.0), deg_to_rad(180.0 + 1.0), k)
		var radius := lerpf(5.6, camera.chase_distance, k)
		var height := lerpf(1.3, camera.chase_height, k)
		var offset := (xf.basis.z * cos(ang) + xf.basis.x * sin(ang)) * radius
		var pos := xf.origin + offset + Vector3.UP * height
		camera.global_transform = Transform3D(Basis(), pos).looking_at(xf.origin + Vector3.UP * 0.55, Vector3.UP)
		camera.fov = lerpf(55.0, camera.base_fov, k)
		t += await _tick()


## Um quadro; devolve quanto a apresentação andou (nada com o jogo pausado — aí o HUD volta, para
## o menu de pausa aparecer).
func _tick() -> float:
	await get_tree().process_frame
	var paused := get_tree().paused
	for layer_node in _hidden:
		if is_instance_valid(layer_node):
			layer_node.visible = paused
	return 0.0 if paused else get_process_delta_time()


## Encerra já (no online, quando o semáforo do servidor começa).
func skip() -> void:
	_skip = true


func _end() -> void:
	if manager.line_guide:
		manager.line_guide.suppressed = false
	camera.cinematic = false
	camera.reset_after_cinematic()
	for layer_node in _hidden:
		if is_instance_valid(layer_node):
			layer_node.visible = true
	finished.emit()
	queue_free()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Retro.theme()
	add_child(root)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(64, -170)
	box.add_theme_constant_override("separation", 0)
	root.add_child(box)
	_caption = Label.new()
	_caption.add_theme_font_override("font", Retro.display(900))
	_caption.add_theme_font_size_override("font_size", 40)
	_caption.add_theme_constant_override("outline_size", 10)
	_caption.add_theme_color_override("font_outline_color", Color(Retro.c("bg"), 0.85))
	box.add_child(_caption)
	_sub = Label.new()
	_sub.add_theme_font_override("font", Retro.display(700))
	_sub.add_theme_font_size_override("font_size", 16)
	_sub.add_theme_color_override("font_color", Retro.c("text_2"))
	_sub.add_theme_constant_override("outline_size", 6)
	_sub.add_theme_color_override("font_outline_color", Color(Retro.c("bg"), 0.85))
	box.add_child(_sub)
	var hint := Label.new()
	hint.text = "Enter / A: pular"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.position = Vector2(-230, -60)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(Retro.c("muted"), 0.9))
	root.add_child(hint)
