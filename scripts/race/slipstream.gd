class_name Slipstream
extends RefCounted
## Vácuo: atrás de um carro há uma faixa (o rastro) onde o ar já vem "arrastado" e o arrasto
## aerodinâmico some. Fica estreita colada no carro da frente e abre um pouco com a distância;
## a força é total entre 3 e 14 m e some até 42 m e para os lados. Só vale andando rápido.
## Calculado pelas posições dos carros (o mesmo no servidor, offline e — só para o visual — no
## cliente), sem depender da pista.

const NEAR := 3.0
const FULL := 14.0
const FAR := 42.0
## Meia-largura (m) do núcleo do rastro colado no carro e o quanto ela abre por metro.
const CORE := 0.9
const SPREAD := 0.025
## Borda suave além do núcleo.
const EDGE := 1.1
const MIN_SPEED := 22.0  # m/s (~80 km/h)
## Velocidade com que o efeito entra/sai (por segundo).
const RATE := 2.5


## Força (0..1) do vácuo que o carro `me` recebe dos outros.
static func strength_for(me: F1Car, cars: Array) -> float:
	return source_for(me, cars)[0]


## [força, carro que dá o vácuo (ou null)].
static func source_for(me: F1Car, cars: Array) -> Array:
	if me.linear_velocity.length() < MIN_SPEED:
		return [0.0, null]
	var best := 0.0
	var src: F1Car = null
	for o in cars:
		var other := o as F1Car
		if other == null or other == me or other.linear_velocity.length() < MIN_SPEED * 0.8:
			continue
		var b := other.global_basis
		var rel := me.global_position - other.global_position
		var behind := -rel.dot(b.z)
		if behind < NEAR or behind > FAR:
			continue
		# Mesmo sentido (não vale para quem vem na contramão)
		if me.global_basis.z.dot(b.z) < 0.7:
			continue
		var lateral := absf(rel.dot(b.x))
		var width := CORE + SPREAD * behind
		var side := 1.0 - smoothstep(width, width + EDGE, lateral)
		var along := smoothstep(NEAR, NEAR + 1.5, behind) * (1.0 - smoothstep(FULL, FAR, behind))
		if side * along > best:
			best = side * along
			src = other
	return [best, src]


## Atualiza o vácuo de todos os carros (com suavização).
static func update_all(cars: Array, delta: float) -> void:
	for o in cars:
		var car := o as F1Car
		if car == null:
			continue
		var r := source_for(car, cars)
		car.slipstream = move_toward(car.slipstream, float(r[0]), delta * RATE)
		if r[1] != null:
			car.slipstream_source = r[1]
		elif car.slipstream <= 0.0:
			car.slipstream_source = null
