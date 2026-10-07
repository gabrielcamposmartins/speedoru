class_name RaceHud
extends CanvasLayer
## HUD do carro (visual retrofuturista e minimalista, ver Retro): velocidade/marcha/giro/bateria no
## canto inferior direito (CarCluster), status do carro (pneus e dano num desenho compacto) na borda
## inferior esquerda (CarCluster.Status), nome do carro/câmera no canto superior direito, aviso de
## sub/sobreesterço, ajuda e garagem.

@export var car_path: NodePath
@export var camera_path: NodePath

var car: F1Car
var camera: RaceCamera
var cluster: CarCluster
var status: CarCluster.Status

@onready var camera_label: Label = %CameraLabel
@onready var car_name_label: Label = %CarNameLabel
@onready var speed_lines: ColorRect = %SpeedLines
@onready var garage: GaragePanel = %Garage
@onready var handling_label: Label = %HandlingLabel
@onready var help: PanelContainer = $Help


const MARGIN := 24.0


func _ready() -> void:
	car = get_node_or_null(car_path) as F1Car
	camera = get_node_or_null(camera_path) as RaceCamera
	_style()
	Retro.events.changed.connect(_style)
	if camera:
		camera.mode_changed.connect(_on_camera_mode_changed)
		_on_camera_mode_changed(camera.get_mode_name())
	# Recebe o Tab também com o jogo pausado (para fechar a garagem)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if car:
		garage.setup(car)
		# A garagem pausa o jogo e continua funcionando pausada
		garage.process_mode = Node.PROCESS_MODE_ALWAYS
		cluster = CarCluster.new()
		cluster.name = "CarCluster"
		add_child(cluster)
		cluster.setup(car)
		# Alinhado ao canto inferior direito
		var cluster_size := cluster.custom_minimum_size
		cluster.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		cluster.offset_right = -MARGIN
		cluster.offset_bottom = -MARGIN
		cluster.offset_left = -MARGIN - cluster_size.x
		cluster.offset_top = -MARGIN - cluster_size.y
		cluster.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		cluster.grow_vertical = Control.GROW_DIRECTION_BEGIN
		status = CarCluster.Status.new()
		status.name = "CarStatus"
		add_child(status)
		status.setup(car)
		var status_size := status.custom_minimum_size
		status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		# Folga embaixo para o monitor de desempenho (faixa fina na borda)
		status.offset_left = MARGIN * 0.5
		status.offset_right = MARGIN * 0.5 + status_size.x
		status.offset_bottom = -MARGIN - 48.0
		status.offset_top = status.offset_bottom - status_size.y
		status.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Aplica o tema retro nos Controls da cena (de novo quando a paleta muda).
func _style() -> void:
	var theme := Retro.theme()
	for node in [help, garage, $TopRight, handling_label]:
		(node as Control).theme = theme
	help.add_theme_stylebox_override("panel", Retro.panel_style(14.0, 0.82))
	var help_label := help.get_node("HelpLabel") as Label
	help_label.add_theme_color_override("font_color", Retro.c("text_2"))
	car_name_label.add_theme_font_override("font", Retro.display(800))
	car_name_label.add_theme_font_size_override("font_size", 18)
	car_name_label.add_theme_color_override("font_color", Retro.c("text"))
	car_name_label.add_theme_color_override("font_shadow_color", Color(Retro.c("accent"), 0.5))
	car_name_label.add_theme_constant_override("shadow_outline_size", 14)
	car_name_label.add_theme_constant_override("shadow_offset_x", 0)
	car_name_label.add_theme_constant_override("shadow_offset_y", 0)
	camera_label.add_theme_font_override("font", Retro.body(500))
	camera_label.add_theme_font_size_override("font_size", 12)
	camera_label.add_theme_color_override("font_color", Retro.c("text_2"))
	camera_label.add_theme_color_override("font_outline_color", Color(Retro.c("bg"), 0.85))
	camera_label.add_theme_constant_override("outline_size", 6)
	handling_label.add_theme_font_override("font", Retro.display(900))
	handling_label.add_theme_font_size_override("font_size", 38)
	handling_label.add_theme_color_override("font_outline_color", Color(Retro.c("bg"), 0.9))
	handling_label.add_theme_constant_override("outline_size", 10)
	handling_label.add_theme_constant_override("shadow_outline_size", 22)
	handling_label.add_theme_constant_override("shadow_offset_x", 0)
	handling_label.add_theme_constant_override("shadow_offset_y", 0)


func _process(_delta: float) -> void:
	if car == null:
		return
	# Sem aviso de sub/sobreesterço na tela
	handling_label.visible = false
	car_name_label.text = (car.config.car_name if car.config else "").to_upper()
	if camera:
		var cam_text := "Câmera: " + camera.get_mode_name()
		if camera.mode == RaceCamera.Mode.ORBIT:
			cam_text += "
arraste o mouse para girar · roda = zoom · O sai"
		elif camera.looking_back:
			cam_text += " · olhando para trás"
		var daylight := get_tree().get_first_node_in_group("daylight") as Daylight
		if daylight:
			cam_text += "
%s · %s" % [daylight.get_time_name(), daylight.get_biome_name()]
		camera_label.text = cam_text

	var lines := clampf((car.speed_kmh - 180.0) / 140.0, 0.0, 1.0)
	(speed_lines.material as ShaderMaterial).set_shader_parameter("intensity", lines)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_garage"):
		# Na corrida o carro não muda: a garagem (Tab) só existe no treino livre
		var rm := get_parent().get_node_or_null("RaceManager") as RaceManager
		if rm and rm.state != RaceManager.State.PRACTICE:
			return
		garage.visible = not garage.visible
		get_tree().paused = garage.visible
		if not garage.visible:
			get_viewport().gui_release_focus()
		get_viewport().set_input_as_handled()


func _on_camera_mode_changed(mode_name: String) -> void:
	camera_label.text = "Câmera: " + mode_name


