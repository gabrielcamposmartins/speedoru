@tool
class_name CarConfig
extends Resource
## Configuração de um carro: qual variante de cada peça e as cores da pintura.
## Emite `changed` a cada alteração; o F1Car escuta e reconstrói só o que mudou.

enum TyreCompound { SOFT, MEDIUM, HARD, INTERMEDIATE, WET }

const COMPOUND_NAMES := ["Macio", "Médio", "Duro", "Intermediário", "Chuva"]
const COMPOUND_COLORS := [
	Color("e8202a"), Color("f5c800"), Color("f2f2f2"), Color("2fb44a"), Color("1f6fe0"),
]
## Multiplicador do atrito dos pneus (wheel_friction_slip) por composto.
const COMPOUND_GRIP := [1.06, 1.0, 0.95, 0.85, 0.78]
const PAINT_FINISHES := ["Brilhante", "Metálico", "Perolado", "Acetinado", "Fosco", "Cromado"]
## Esquemas de pintura: como as 3 cores se dividem pela carroceria (shader car_paint). [nome, explicação]
const PAINT_SCHEMES := [
	["Clássico", "As cores nas peças como o carro foi desenhado."],
	["Dois tons", "Cor 1 em cima, cor 2 embaixo e um filete da cor 3 na divisão."],
	["Faixas de corrida", "Duas faixas largas da cor 2 de ponta a ponta, contornadas na cor 3."],
	["Diagonal", "Frente na cor 1 e traseira na cor 2, cortadas na diagonal por uma faixa da cor 3."],
	["Flechas", "Chevrons da cor 2 apontando para a frente, com borda da cor 3."],
	["Degradê", "A cor 1 vira a cor 2 da frente para trás; a base do carro na cor 3."],
	["Metades", "Lado esquerdo na cor 1, direito na cor 2 e uma faixa central da cor 3."],
	["Relâmpago", "Divisão em zigue-zague pela lateral, com filete da cor 3."],
	["Ondas", "A cor 2 sobe em onda pela lateral, com uma segunda onda fina da cor 3."],
	["Camuflagem", "Manchas nas três cores pelo carro inteiro."],
	["Pontas", "Corpo na cor 1; bico, asa dianteira e asa traseira na cor 2, divididos pela cor 3."],
	["Faixa lateral", "Uma faixa larga da cor 2 nas laterais, com filetes da cor 3."],
]
const RIM_FINISHES := ["Polido", "Cromado", "Acetinado", "Fosco"]

@export var car_name := "Protótipo":
	set(value):
		car_name = value
		emit_changed()

## slot -> variante (ver CarPartCatalog). Slots ausentes usam a variante padrão.
@export var parts: Dictionary = {}:
	set(value):
		parts = value
		emit_changed()

@export_group("Pintura")
@export var primary_color := Color("d81e2c"):
	set(value):
		primary_color = value
		emit_changed()
@export var secondary_color := Color("f1f2f6"):
	set(value):
		secondary_color = value
		emit_changed()
@export var accent_color := Color("12a4e8"):
	set(value):
		accent_color = value
		emit_changed()
@export var rim_color := Color("1b1c22"):
	set(value):
		rim_color = value
		emit_changed()
@export var helmet_color := Color("ffd21f"):
	set(value):
		helmet_color = value
		emit_changed()
@export var suit_color := Color("d81e2c"):
	set(value):
		suit_color = value
		emit_changed()
## Neon embaixo do carro (aparece principalmente à noite).
@export var neon_enabled := false:
	set(value):
		neon_enabled = value
		emit_changed()
@export var neon_color := Color("ff3dd8"):
	set(value):
		neon_color = value
		emit_changed()
## Brilho das rodas, rastro e partículas do boost da bateria.
@export var boost_color := Color("38f2ff"):
	set(value):
		boost_color = value
		emit_changed()

## Esquema de divisão das 3 cores (ver PAINT_SCHEMES).
@export var paint_scheme := 0:
	set(value):
		paint_scheme = value
		emit_changed()

## Acabamento da pintura (ver PAINT_FINISHES) e das rodas (RIM_FINISHES).
@export var paint_finish := 0:
	set(value):
		paint_finish = value
		emit_changed()
@export var rim_finish := 0:
	set(value):
		rim_finish = value
		emit_changed()

## Decalques SVG por lugar do carro (ver CarDecals).
@export var decals: Dictionary = {}:
	set(value):
		decals = value
		emit_changed()

@export_group("Pneus")
@export var tyre_compound: TyreCompound = TyreCompound.MEDIUM:
	set(value):
		tyre_compound = value
		emit_changed()


func get_part(slot: String) -> String:
	var variant: String = parts.get(slot, "")
	if variant.is_empty() or not CarPartCatalog.has_variant(slot, variant):
		return CarPartCatalog.default_variant(slot)
	return variant


func set_part(slot: String, variant: String) -> void:
	if not CarPartCatalog.has_variant(slot, variant):
		push_warning("Variante desconhecida: %s/%s" % [slot, variant])
		return
	var copy := parts.duplicate()
	copy[slot] = variant
	parts = copy


func compound_color() -> Color:
	return COMPOUND_COLORS[tyre_compound]


func compound_grip() -> float:
	return COMPOUND_GRIP[tyre_compound]
