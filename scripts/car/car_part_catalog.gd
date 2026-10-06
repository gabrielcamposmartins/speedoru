@tool
class_name CarPartCatalog
extends RefCounted
## Catálogo das peças intercambiáveis do carro.
##
## Cada peça fica em res://assets/car/parts/<slot>/<variante>.glb (gerado por
## blender/build_f1_car.py). Todas compartilham a origem do carro, então montar é só instanciar.
## Pneus e rodas ficam em <slot>/<variante>_<front|rear>.glb, com origem no cubo da roda.
##
## "stats" são deltas aplicados à aerodinâmica do F1Car:
##   downforce -> ClA (m²), drag -> CdA (m²), balance -> fração de downforce no eixo dianteiro.

const PARTS_DIR := "res://assets/car/parts/"

const SLOTS := {
	"chassis": {"label": "Monocoque", "variants": {
		"standard": {"label": "Padrão"},
	}},
	"nose": {"label": "Bico", "variants": {
		"standard": {"label": "Padrão"},
		"pointed": {"label": "Pontudo", "stats": {"drag": -0.02, "downforce": -0.10, "balance": -0.01}},
	}},
	"front_wing": {"label": "Asa dianteira", "variants": {
		"standard": {"label": "Alta carga (4 elementos)"},
		"lowdf": {"label": "Baixa carga (3 elementos)", "stats": {"drag": -0.04, "downforce": -0.35, "balance": -0.03}},
	}},
	"rear_wing": {"label": "Asa traseira", "variants": {
		"standard": {"label": "Média carga"},
		"lowdf": {"label": "Baixa carga (Monza)", "stats": {"drag": -0.12, "downforce": -0.60, "balance": 0.03}},
		"highdf": {"label": "Alta carga (Mônaco)", "stats": {"drag": 0.10, "downforce": 0.50, "balance": -0.03}},
	}},
	"sidepods": {"label": "Sidepods", "variants": {
		"downwash": {"label": "Downwash"},
		"slim": {"label": "Zeropod", "stats": {"drag": -0.03, "downforce": -0.10}},
	}},
	"engine_cover": {"label": "Cobertura do motor", "variants": {
		"standard": {"label": "Padrão"},
		"sharkfin": {"label": "Barbatana", "stats": {"drag": 0.01, "balance": -0.01}},
	}},
	"floor": {"label": "Assoalho", "variants": {"standard": {"label": "Efeito solo"}}},
	"halo": {"label": "Halo", "variants": {"standard": {"label": "Padrão"}}},
	"mirrors": {"label": "Retrovisores", "variants": {"standard": {"label": "Padrão"}}},
	"suspension_front": {"label": "Suspensão dianteira", "variants": {"standard": {"label": "Pushrod"}}},
	"suspension_rear": {"label": "Suspensão traseira", "variants": {"standard": {"label": "Pullrod"}}},
	"cockpit": {"label": "Cockpit", "variants": {"standard": {"label": "Padrão"}}},
	"driver": {"label": "Piloto", "variants": {"standard": {"label": "Padrão"}}},
}

const WHEEL_SLOTS := {
	"tyre": {"label": "Pneu", "variants": {
		"slick": {"label": "Slick"},
	}},
	"rim": {"label": "Roda", "variants": {
		"covered": {"label": "Com calota"},
		"spoked": {"label": "Raiada"},
	}},
}


static func all_slots() -> Array:
	return SLOTS.keys() + WHEEL_SLOTS.keys()


static func is_wheel_slot(slot: String) -> bool:
	return WHEEL_SLOTS.has(slot)


static func slot_info(slot: String) -> Dictionary:
	if SLOTS.has(slot):
		return SLOTS[slot]
	return WHEEL_SLOTS.get(slot, {})


static func slot_label(slot: String) -> String:
	return slot_info(slot).get("label", slot)


static func variants(slot: String) -> Array:
	return slot_info(slot).get("variants", {}).keys()


static func has_variant(slot: String, variant: String) -> bool:
	return slot_info(slot).get("variants", {}).has(variant)


static func default_variant(slot: String) -> String:
	var list := variants(slot)
	return list[0] if not list.is_empty() else ""


static func variant_label(slot: String, variant: String) -> String:
	return slot_info(slot).get("variants", {}).get(variant, {}).get("label", variant)


static func variant_stats(slot: String, variant: String) -> Dictionary:
	return slot_info(slot).get("variants", {}).get(variant, {}).get("stats", {})


static func part_path(slot: String, variant: String) -> String:
	return PARTS_DIR + slot + "/" + variant + ".glb"


static func wheel_part_path(slot: String, variant: String, axle: String) -> String:
	return PARTS_DIR + slot + "/" + variant + "_" + axle + ".glb"
