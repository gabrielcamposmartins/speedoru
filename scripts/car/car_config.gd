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

## Acabamento da pintura (ver PAINT_FINISHES) e das rodas (RIM_FINISHES).
@export var paint_finish := 0:
	set(value):
		paint_finish = value
		emit_changed()
@export var rim_finish := 0:
	set(value):
		rim_finish = value
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
