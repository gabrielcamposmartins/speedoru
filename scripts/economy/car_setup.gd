class_name CarSetup
extends RefCounted
## Engenharia: parâmetros de comportamento do carro (nunca de aparência) que o jogador ajusta na
## garagem (Estúdio → Engenharia), com nomes amigáveis, limites que fazem sentido e uma explicação.
## O ajuste fica no perfil (Profile.equipped["setup"], só o que mudou) e vai para o carro do
## jogador na garagem e na corrida. Potência, desgaste e regras não entram: são iguais para todos.
##
## Cada parâmetro: [chave, grupo, nome, alvo, propriedade, mínimo, máximo, passo fino, passo grosso,
## unidade, escala de exibição, casas, explicação]. Alvo: "car" (F1Car), "front"/"rear" (rodas do
## eixo), "gears" (multiplica as relações de marcha).

const PARAMS := [
	# --- Aerodinâmica
	["downforce_area", "Aerodinâmica", "Carga aerodinâmica", "car", "downforce_area", 3.2, 5.4, 0.02, 0.2, "m²", 1.0, 2,
		"Quanto o carro é empurrado contra o chão em velocidade (ClA). Mais carga = mais aderência nas curvas rápidas, porém mais arrasto e menos velocidade final."],
	["drag_area", "Aerodinâmica", "Arrasto", "car", "drag_area", 1.05, 1.85, 0.01, 0.1, "m²", 1.0, 2,
		"Resistência do ar (CdA). Menos arrasto = mais velocidade nas retas; na prática anda junto com a carga (asas maiores têm mais arrasto)."],
	["aero_balance", "Aerodinâmica", "Balanço aerodinâmico", "car", "aero_balance", 0.36, 0.5, 0.005, 0.02, "% frente", 100.0, 1,
		"Quanto da carga fica no eixo dianteiro. Mais na frente = carro mais ágil na entrada da curva (pode sair de traseira); menos = mais estável (pode sair de frente)."],
	# --- Freios
	["brake_force_per_wheel", "Freios", "Força dos freios", "car", "brake_force_per_wheel", 9000.0, 18000.0, 100.0, 1000.0, "N/roda", 1.0, 0,
		"Força máxima de cada freio. Mais força = frenagens mais curtas, mas trava as rodas com mais facilidade (principalmente sem a assistência de freio)."],
	["brake_bias_front", "Freios", "Balanço de freio", "car", "brake_bias_front", 0.5, 0.66, 0.005, 0.02, "% frente", 100.0, 1,
		"Divisão da frenagem entre frente e trás. Mais na frente = estável, mas trava a dianteira e sai de frente; mais atrás = gira melhor na entrada, mas pode rodar. Também muda com [ e ] na pista."],
	# --- Pneus
	["front_grip", "Pneus", "Aderência dianteira", "car", "front_grip", 1.5, 2.0, 0.01, 0.05, "μ", 1.0, 2,
		"Atrito de pico dos pneus da frente. Mais aderência na frente que atrás deixa o carro mais 'nervoso' (tende a sair de traseira)."],
	["rear_grip", "Pneus", "Aderência traseira", "car", "rear_grip", 1.5, 2.0, 0.01, 0.05, "μ", 1.0, 2,
		"Atrito de pico dos pneus de trás. Mais aderência atrás = carro estável e tração melhor na saída de curva (tende a sair de frente)."],
	["peak_slip_angle_deg", "Pneus", "Ângulo de pico", "car", "peak_slip_angle_deg", 4.0, 9.0, 0.1, 0.5, "°", 1.0, 1,
		"Deriva em que o pneu dá a força lateral máxima. Menor = resposta rápida e limite 'afiado'; maior = pneu mais progressivo, que avisa antes de escorregar."],
	["tire_shape", "Pneus", "Queda depois do limite", "car", "tire_shape", 1.2, 1.7, 0.01, 0.05, "", 1.0, 2,
		"Quanto a aderência cai depois do pico (fator de forma da curva do pneu). Maior = passou do limite, escorrega de vez; menor = deslizes mais fáceis de controlar."],
	["load_sensitivity", "Pneus", "Sensibilidade à carga", "car", "load_sensitivity", 0.04, 0.24, 0.005, 0.02, "", 1.0, 3,
		"Quanto o pneu perde de atrito quando recebe mais peso. Maior = o eixo carregado (lado de fora, frente na frenagem) satura antes; menor = mais aderência total."],
	# --- Direção
	["max_steer_angle", "Direção", "Esterço em baixa", "car", "max_steer_angle", 0.0, 0.45, 0.005, 0.02, "°", 57.2958, 1,
		"Ângulo máximo das rodas em baixa velocidade (grampos e chicanes). Mais esterço = vira mais fechado, mas fica mais sensível."],
	["high_speed_steer_angle", "Direção", "Esterço em alta", "car", "high_speed_steer_angle", 0.0, 0.18, 0.002, 0.01, "°", 57.2958, 1,
		"Ângulo máximo das rodas em alta velocidade. Menor = mais estável nas retas e curvas rápidas; maior = mais resposta, com risco de rodar em correções bruscas."],
	["steer_rate", "Direção", "Velocidade do volante", "car", "steer_rate", 0.0, 4.0, 0.05, 0.25, "", 1.0, 2,
		"Quão rápido o volante chega ao ângulo pedido. Mais rápido = reações imediatas; mais lento = movimentos suaves (bom no teclado)."],
	# --- Motor e câmbio
	["final_drive", "Motor e câmbio", "Relação final", "gears", "", 0.9, 1.1, 0.005, 0.02, "×", 1.0, 3,
		"Multiplica todas as marchas. Maior = acelera mais forte e chega antes no limitador (velocidade final menor); menor = mais velocidade final, saídas mais lentas."],
	["upshift_rpm", "Motor e câmbio", "Troca para cima (auto)", "car", "upshift_rpm", 10500.0, 12300.0, 50.0, 250.0, "rpm", 1.0, 0,
		"Giro em que o câmbio automático sobe a marcha. Mais alto = usa o motor até o fim (a potência máxima fica perto do limite)."],
	["downshift_rpm", "Motor e câmbio", "Redução (auto)", "car", "downshift_rpm", 6500.0, 9000.0, 50.0, 250.0, "rpm", 1.0, 0,
		"Giro em que o câmbio automático reduz. Mais alto = sai das curvas com mais giro (mais força), mas mais freio-motor na entrada."],
	["engine_braking_force", "Motor e câmbio", "Freio-motor", "car", "engine_braking_force", 1200.0, 3600.0, 50.0, 300.0, "N", 1.0, 0,
		"Quanto o motor segura o carro ao soltar o acelerador. Mais = ajuda a frear e a 'virar' a traseira na entrada; menos = carro mais solto e estável ao aliviar."],
	# --- Suspensão
	["front_spring", "Suspensão", "Mola dianteira", "front", "suspension_stiffness", 100.0, 220.0, 1.0, 10.0, "", 1.0, 0,
		"Rigidez das molas da frente. Mais dura = resposta rápida e menos rolagem, mas pula nas zebras; mais macia = absorve ondulações e transfere peso para a frente."],
	["rear_spring", "Suspensão", "Mola traseira", "rear", "suspension_stiffness", 100.0, 230.0, 1.0, 10.0, "", 1.0, 0,
		"Rigidez das molas de trás. Traseira mais dura que a frente deixa o carro mais solto de traseira; mais macia = mais tração na saída."],
	["front_damper", "Suspensão", "Amortecedor dianteiro", "front", "damping_compression", 2.5, 7.5, 0.05, 0.5, "", 1.0, 2,
		"Controla a velocidade com que a frente sobe e desce. Mais = carro firme e preciso; menos = mais macio nas zebras, mas oscila mais."],
	["rear_damper", "Suspensão", "Amortecedor traseiro", "rear", "damping_compression", 2.5, 7.5, 0.05, 0.5, "", 1.0, 2,
		"Controla a velocidade com que a traseira sobe e desce. Mais = traseira firme; menos = mais tração em piso irregular."],
	["front_height", "Suspensão", "Altura dianteira", "front", "wheel_rest_length", 0.08, 0.16, 0.002, 0.01, "mm", 1000.0, 0,
		"Altura da frente. Mais baixa = centro de gravidade mais baixo e mais preciso, mas o assoalho raspa nas zebras."],
	["rear_height", "Suspensão", "Altura traseira", "rear", "wheel_rest_length", 0.08, 0.16, 0.002, 0.01, "mm", 1000.0, 0,
		"Altura da traseira. Traseira mais alta que a frente (rake) desloca o equilíbrio para a frente: carro mais ágil; mais baixa = mais estável."],
	["front_roll", "Suspensão", "Barra estabilizadora dianteira", "front", "wheel_roll_influence", 0.0, 0.15, 0.002, 0.01, "", 1.0, 3,
		"Quanto a frente deixa o carro inclinar nas curvas. Mais rígida (menor) = menos rolagem e frente mais 'firme'; mais solta = mais aderência dianteira em curvas lentas."],
	["rear_roll", "Suspensão", "Barra estabilizadora traseira", "rear", "wheel_roll_influence", 0.0, 0.15, 0.002, 0.01, "", 1.0, 3,
		"Quanto a traseira deixa o carro inclinar. Mais rígida (menor) = traseira mais viva na entrada; mais solta = mais tração na saída das curvas."],
	# --- Assistências
	["assist_threshold", "Assistências", "Margem das assistências", "car", "assist_threshold", 0.85, 1.0, 0.005, 0.02, "%", 100.0, 1,
		"Até quanto da aderência o controle de tração e a assistência de freio deixam usar. Mais alto = mais rápido, mais perto do limite; mais baixo = mais seguro."],
]

const GROUPS := ["Aerodinâmica", "Freios", "Pneus", "Direção", "Motor e câmbio", "Suspensão", "Assistências"]


static func param(key: String) -> Array:
	for p in PARAMS:
		if p[0] == key:
			return p
	return []


## Valores de fábrica do carro (lidos uma vez, antes de qualquer ajuste).
static func defaults(car: F1Car) -> Dictionary:
	if car.has_meta("_setup_defaults"):
		return car.get_meta("_setup_defaults")
	var d := {}
	for p in PARAMS:
		d[p[0]] = _read(car, p)
	car.set_meta("_setup_defaults", d)
	car.set_meta("_base_gears", car.gear_ratios.duplicate())
	return d


static func _wheels(car: F1Car, axle: String) -> Array:
	var out := []
	for w in car.get_wheels():
		var front: bool = (w as VehicleWheel3D).use_as_steering
		if (axle == "front") == front:
			out.append(w)
	return out


static func _read(car: F1Car, p: Array) -> float:
	match p[3]:
		"car":
			return float(car.get(p[4]))
		"gears":
			return 1.0
		_:
			var ws := _wheels(car, p[3])
			return float(ws[0].get(p[4])) if not ws.is_empty() else float(p[5])


## Aplica um ajuste (só as chaves presentes; o resto volta ao de fábrica).
static func apply(car: F1Car, setup: Dictionary) -> void:
	if car == null:
		return
	var d := defaults(car)
	for p in PARAMS:
		var v: float = clampf(float(setup.get(p[0], d[p[0]])), p[5], p[6]) if setup.has(p[0]) else float(d[p[0]])
		match p[3]:
			"car":
				car.set(p[4], v)
			"gears":
				var base: PackedFloat32Array = car.get_meta("_base_gears")
				var g := PackedFloat32Array()
				for r in base:
					g.append(r * v)
				car.gear_ratios = g
			_:
				for w in _wheels(car, p[3]):
					w.set(p[4], v)
					# Amortecedor: a extensão acompanha a compressão (proporção do carro original)
					if p[4] == "damping_compression":
						w.set("damping_relaxation", v * 1.25)
	# Aerodinâmica efetiva = base + peças
	car._update_stats()


static func format(p: Array, v: float) -> String:
	var shown: float = v * float(p[10])
	var txt := ("%." + str(p[11]) + "f") % shown
	txt = txt.replace(".", ",")
	return (txt + " " + str(p[9])).strip_edges()
