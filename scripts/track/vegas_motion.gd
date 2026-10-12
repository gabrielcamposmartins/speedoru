class_name VegasMotion
extends Node3D
## Movimento simples do cenário de Las Vegas: gira em torno do Y local (`spin`, rad/s) — o sapatinho
## girando no alto do poste e o pivô que leva os dirigíveis em volta do circuito — e balança de leve
## para cima e para baixo (`bob`, m), como um dirigível no ar.

@export var spin := 0.0
@export var bob := 0.0

var _t := 0.0
var _base_y := 0.0


func _ready() -> void:
	_base_y = position.y
	_t = randf() * 10.0


func _process(delta: float) -> void:
	_t += delta
	if spin != 0.0:
		rotate_y(spin * delta)
	if bob != 0.0:
		position.y = _base_y + sin(_t * 0.35) * bob
