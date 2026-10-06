extends Node3D
## Cena de circuito: coloca o carro no grid (ou no box) e roda a sequência das luzes de
## largada ao começar. A pista inteira é gerada pelo RaceTrack ("Track").

## Posição no grid (0 = pole).
@export var grid_slot := 0
## Começa parado em frente ao box em vez do grid.
@export var start_in_pit := false
@export var pit_box := 0
@export var start_light_sequence := true

@onready var car: F1Car = $F1Car
@onready var track: RaceTrack = $Track


func _ready() -> void:
	# Com o RaceManager (modo de jogo) é ele quem posiciona os carros, roda as luzes e fecha a
	# tela de carregamento
	if has_node("RaceManager"):
		return
	if track.path == null:
		return
	if not track.is_built:
		await track.built
	place_car()
	LoadingScreen.done()
	if start_light_sequence and track.start_lights:
		track.start_lights.run_sequence.call_deferred()


func place_car() -> void:
	car.global_transform = track.get_pit_box_transform(pit_box) if start_in_pit else track.get_grid_transform(grid_slot)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_physics_interpolation()
