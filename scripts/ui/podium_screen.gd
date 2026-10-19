class_name PodiumScreen
extends CanvasLayer
## Tela de vitória no fim da corrida: os três primeiros carros (cópias, com as peças, cores e skin de
## cada um) parados na própria pista, logo depois da linha de chegada — o 1º no meio e mais à frente,
## o 2º à esquerda (de quem olha) um pouco atrás e o 3º à direita, mais atrás — com a câmera pela
## frente. Cada um tem a plaquinha com a posição no chão à frente e o nome em cima.
## Só nesta tela (cada jogador monta o seu pódio quando termina; quem ainda corre não vê nada): as
## cópias não têm colisão, e enquanto o pódio está aberto os carros da corrida, o HUD, o som dos
## carros e os sons do ambiente somem (a música continua). "VER RESULTADO" (ou Esc) fecha e devolve
## tudo.

signal closed

const CAR_SCENE := preload("res://scenes/car/f1_car.tscn")
## Por posição (1º, 2º, 3º): [lateral (m; + = esquerda do carro, à direita de quem olha de frente),
## distância depois da linha (m), cor da placa].
const SLOTS := [[0.0, 14.0, Color("e2b33c")], [-3.6, 11.5, Color("c9ced6")], [3.6, 9.0, Color("b87a46")]]
## Câmera: quanto à frente do 1º e altura.
const CAMERA_AHEAD := 9.5
const CAMERA_HEIGHT := 1.7
## Buses que silenciam no pódio (o ambiente no Master é pausado nó a nó).
const MUTED_BUSES := [&"Car", &"Rivals", &"Crowd"]

## Os três primeiros (até 3).
var entries: Array[RaceEntry] = []
var manager: RaceManager
var _root3d: Node3D
var _camera: Camera3D
var _prev_camera: Camera3D
var _t := 0.0
var _hidden: Array[Node] = []
var _paused: Array[Node] = []
var _muted: Array[int] = []
var _restored := false


func _ready() -> void:
	layer = 105
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_world()
	_silence(true)
	_build_overlay()


func _track() -> RaceTrack:
	return manager.track if manager else null


## Cena da corrida (onde ficam os carros, o HUD e os sons).
func _scene() -> Node:
	if manager == null:
		return null
	return manager.owner if manager.owner else manager.get_parent()


func _build_world() -> void:
	var track := _track()
	if track == null:
		return
	_root3d = Node3D.new()
	_root3d.name = "Podium"
	track.add_child(_root3d)
	var p := track.path
	for k in SLOTS.size():
		var s: float = SLOTS[k][1]
		var lat: float = SLOTS[k][0]
		var frame := p.frame_at(s, lat, 0.05)
		_plaque(k, p.frame_at(s + 3.5, lat, 0.0))
		if k < entries.size() and entries[k] != null:
			_spawn_car(entries[k], frame)
			_name_label(entries[k].name, frame.origin + frame.basis.y * 1.9, SLOTS[k][2])
	# Os carros da corrida, a linha ideal no chão (e o HUD) saem de cena enquanto o pódio está aberto
	if manager.line_guide and manager.line_guide.visible:
		manager.line_guide.visible = false
		_hidden.append(manager.line_guide)
	for e in manager.roster:
		if e.car and e.car.visible:
			e.car.visible = false
			_hidden.append(e.car)
	var scene := _scene()
	if scene:
		for n in scene.find_children("*", "CanvasLayer", true, false):
			var cl := n as CanvasLayer
			if cl.visible:
				cl.visible = false
				_hidden.append(cl)
	_prev_camera = manager.get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_camera.far = 4000.0
	_root3d.add_child(_camera)
	_camera.current = true
	_place_camera()


## Plaquinha no chão à frente do carro: um cavalete com a placa na cor da posição e o número.
func _plaque(k: int, at: Transform3D) -> void:
	var col: Color = SLOTS[k][2]
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.62, 0.42, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.6
	mat.roughness = 0.4
	bm.material = mat
	board.mesh = bm
	_root3d.add_child(board)
	# Virada para a frente (para a câmera), um pouco inclinada para trás
	var face := at.basis.rotated(at.basis.x, deg_to_rad(-12.0))
	board.global_transform = Transform3D(face, at.origin + at.basis.y * 0.3)
	var legs := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.5, 0.05, 0.28)
	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.15, 0.15, 0.17)
	lm.material = leg_mat
	legs.mesh = lm
	_root3d.add_child(legs)
	legs.global_transform = Transform3D(at.basis, at.origin + at.basis.y * 0.03)
	var num := Label3D.new()
	num.text = "%dº" % (k + 1)
	num.font = Retro.display(900)
	num.font_size = 128
	num.pixel_size = 0.0025
	num.modulate = Color("15121c")
	num.outline_size = 0
	num.shaded = true
	_root3d.add_child(num)
	num.global_transform = Transform3D(face, at.origin + at.basis.y * 0.3 + face.z * 0.025)


func _name_label(text: String, at: Vector3, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Retro.display(800)
	l.font_size = 56
	l.pixel_size = 0.006
	l.modulate = Color.WHITE
	l.outline_modulate = Color(col.darkened(0.5), 0.9)
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_root3d.add_child(l)
	l.global_position = at


## Cópia parada do carro, sem colisão nem física (não atrapalha quem ainda corre).
func _spawn_car(e: RaceEntry, at: Transform3D) -> void:
	if e.car == null:
		return
	var car := CAR_SCENE.instantiate() as F1Car
	car.player_controlled = false
	car.hold = true
	for n in ["Audio", "Onboard"]:
		var child := car.get_node_or_null(n)
		if child:
			car.remove_child(child)
			child.free()
	if e.car.config:
		car.config = e.car.config.duplicate(true)
	car.collision_layer = 0
	car.collision_mask = 0
	car.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	car.freeze = true
	car.transform = _root3d.global_transform.affine_inverse() * at
	_root3d.add_child(car)
	# Como os carros dos outros online: sem isso o VehicleBody3D regrava as rodas a partir dos raios
	# da suspensão de antes e elas ficam na origem do mundo (pódio sem rodas)
	car.set_puppet(true)
	car.reset_physics_interpolation()


## Silencia (ou devolve) o som dos carros, do público e do ambiente; a música continua.
func _silence(on: bool) -> void:
	if on:
		for b in MUTED_BUSES:
			var idx := AudioServer.get_bus_index(b)
			if idx >= 0 and not AudioServer.is_bus_mute(idx):
				AudioServer.set_bus_mute(idx, true)
				_muted.append(idx)
		var scene := _scene()
		if scene:
			for n in scene.find_children("*", "", true, false):
				if (n is AudioStreamPlayer3D or n is AudioStreamPlayer or n is AudioStreamPlayer2D) \
						and str(n.get("bus")) != "Music" and not n.get("stream_paused"):
					n.set("stream_paused", true)
					_paused.append(n)
	else:
		for idx in _muted:
			AudioServer.set_bus_mute(idx, false)
		_muted.clear()
		for n in _paused:
			if is_instance_valid(n):
				n.set("stream_paused", false)
		_paused.clear()


func _place_camera() -> void:
	var track := _track()
	if track == null or _camera == null:
		return
	var p := track.path
	var first: float = SLOTS[0][1]
	var sway := sin(_t * 0.3) * 1.6
	var eye := p.frame_at(first + CAMERA_AHEAD, sway, CAMERA_HEIGHT + sin(_t * 0.45) * 0.15).origin
	var look := p.frame_at(first - 2.5, 0.0, 0.6).origin
	_camera.global_transform = Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)


func _process(delta: float) -> void:
	_t += delta
	_place_camera()


func _build_overlay() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = Retro.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var head := Label.new()
	head.text = "PÓDIO"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.set_anchors_preset(Control.PRESET_CENTER_TOP)
	head.position = Vector2(-300, 30)
	head.size = Vector2(600, 60)
	head.add_theme_font_override("font", Retro.display(900))
	head.add_theme_font_size_override("font_size", 46)
	head.add_theme_color_override("font_color", Color("ffcf4a"))
	head.add_theme_constant_override("outline_size", 10)
	head.add_theme_color_override("font_outline_color", Color(Retro.c("bg"), 0.85))
	root.add_child(head)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	center.position = Vector2(-150, -80)
	center.size = Vector2(300, 50)
	root.add_child(center)
	var b := Button.new()
	b.text = "VER RESULTADO"
	b.theme_type_variation = "PrimaryButton"
	b.custom_minimum_size = Vector2(260, 46)
	b.pressed.connect(_close)
	center.add_child(b)
	b.grab_focus.call_deferred()
	var confetti := Confetti.new()
	confetti.colors.append_array([SLOTS[0][2], SLOTS[1][2], SLOTS[2][2], Retro.c("accent")])
	add_child(confetti)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_restore()


## Devolve a cena da corrida (carros, HUD, câmera e sons); uma vez só.
func _restore() -> void:
	if _restored:
		return
	_restored = true
	_silence(false)
	for n in _hidden:
		if is_instance_valid(n):
			n.set("visible", true)
	_hidden.clear()
	if is_instance_valid(_prev_camera):
		_prev_camera.current = true
	if is_instance_valid(_root3d):
		_root3d.queue_free()


func _close() -> void:
	_restore()
	closed.emit()
	queue_free()
