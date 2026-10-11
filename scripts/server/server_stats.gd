class_name ServerStats
extends Node
## Medidor do servidor dedicado: a cada minuto escreve no log quantos passos de física passaram do
## orçamento de 8,3 ms (120 Hz), o pior passo e quantas salas estavam correndo. É o número para
## comparar o servidor antes e depois de mudanças (os "mini teleportes" vêm de passos atrasados).
##
## O passo é medido do primeiro ao último _physics_process do tick (este nó roda primeiro e o
## filho End por último: toda a lógica de corrida, bots e rede), mais o pior passo do quadro que o
## motor registra (inclui a simulação da física, Performance.TIME_PHYSICS_PROCESS).

const BUDGET_MS := 1000.0 / 120.0
const PERIOD := 60.0

var _start_us := 0
var _steps := 0
var _slow := 0
var _worst := 0.0
var _slow_frames := 0
var _worst_engine := 0.0
var _t := 0.0


func _ready() -> void:
	name = "ServerStats"
	process_physics_priority = -1000000
	var end := _End.new()
	end.name = "End"
	end.stats = self
	end.process_physics_priority = 1000000
	add_child(end)


func _physics_process(_delta: float) -> void:
	_start_us = Time.get_ticks_usec()


func _end_step() -> void:
	var ms := (Time.get_ticks_usec() - _start_us) / 1000.0
	_steps += 1
	_worst = maxf(_worst, ms)
	if ms > BUDGET_MS:
		_slow += 1


func _process(delta: float) -> void:
	var engine_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_worst_engine = maxf(_worst_engine, engine_ms)
	if engine_ms > BUDGET_MS:
		_slow_frames += 1
	_t += delta
	if _t < PERIOD:
		return
	_t = 0.0
	var server := get_parent() as GameServer
	var racing := server.room_counts().y if server else 0
	print("Servidor: física no último minuto: %d passos, %d acima de %.1f ms (pior %.1f ms); quadros com passo do motor acima: %d (pior %.1f ms); salas correndo: %d" % [
		_steps, _slow, BUDGET_MS, _worst, _slow_frames, _worst_engine, racing])
	_steps = 0
	_slow = 0
	_worst = 0.0
	_slow_frames = 0
	_worst_engine = 0.0


class _End extends Node:
	var stats: ServerStats

	func _physics_process(_delta: float) -> void:
		stats._end_step()
