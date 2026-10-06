class_name DaylightPresets
extends RefCounted
## Presets de período do dia e de ambiente usados pelo Daylight.
## Cores em sRGB (o Daylight converte para linear quando vão para uniforms globais).

enum TimeOfDay { DAY, SUNSET, NIGHT }
enum Biome { SUMMER, AUTUMN, SAKURA, FANTASY }

const TIME_NAMES := ["Dia", "Entardecer", "Noite"]
const BIOME_NAMES := ["Verão", "Outono", "Sakura", "Fantasia"]

## Por período: sol/lua, ambiente, neblina, céu, nuvens e luzes de três pontos.
const TIMES := {
	TimeOfDay.DAY: {
		"sun_elevation": 42.0, "sun_azimuth": 125.0, "sun_energy": 1.0, "sun_color": Color(1.0, 0.97, 0.92),
		"ambient_color": Color(0.82, 0.8, 0.8), "ambient_energy": 0.52, "exposure": 0.82,
		"fog_color": Color(0.78, 0.86, 0.97), "fog_density": 0.00075, "mist": Color(0.88, 0.92, 1.0), "mist_density": 0.012,
		"sky_top": Color(0.13, 0.36, 0.86), "sky_horizon": Color(0.62, 0.8, 0.98), "sky_ground": Color(0.24, 0.36, 0.25),
		"cloud_lit": Color(1.0, 1.0, 1.0), "cloud_shade": Color(0.68, 0.75, 0.93), "cloud_coverage": 0.42, "sky_energy": 1.05,
		"fill": 0.22, "rim": 0.65, "glow": 0.55,
	},
	TimeOfDay.SUNSET: {
		"sun_elevation": 6.0, "sun_azimuth": 245.0, "sun_energy": 1.05, "sun_color": Color(1.0, 0.62, 0.36),
		"ambient_color": Color(0.92, 0.72, 0.68), "ambient_energy": 0.42, "exposure": 0.92,
		"fog_color": Color(0.98, 0.7, 0.55), "fog_density": 0.0009, "mist": Color(1.0, 0.78, 0.65), "mist_density": 0.014,
		"sky_top": Color(0.22, 0.26, 0.58), "sky_horizon": Color(1.0, 0.6, 0.38), "sky_ground": Color(0.3, 0.22, 0.22),
		"cloud_lit": Color(1.0, 0.72, 0.5), "cloud_shade": Color(0.52, 0.42, 0.62), "cloud_coverage": 0.45, "sky_energy": 1.0,
		"fill": 0.2, "rim": 0.8, "glow": 0.7,
	},
	TimeOfDay.NIGHT: {
		"sun_elevation": 38.0, "sun_azimuth": 200.0, "sun_energy": 0.16, "sun_color": Color(0.6, 0.7, 1.0),
		"ambient_color": Color(0.4, 0.46, 0.7), "ambient_energy": 0.22, "exposure": 1.05,
		"fog_color": Color(0.08, 0.1, 0.18), "fog_density": 0.0009, "mist": Color(0.25, 0.3, 0.45), "mist_density": 0.01,
		"sky_top": Color(0.01, 0.02, 0.07), "sky_horizon": Color(0.06, 0.09, 0.2), "sky_ground": Color(0.03, 0.04, 0.06),
		"cloud_lit": Color(0.3, 0.33, 0.45), "cloud_shade": Color(0.09, 0.1, 0.17), "cloud_coverage": 0.3, "sky_energy": 1.0,
		"fill": 0.08, "rim": 0.25, "glow": 0.45,
	},
}

## Por ambiente: grama (lush, warm, cool, deep), folhas (a, b, c), quanto recolorir as árvores,
## pinheiros também, pétalas e, opcionalmente, céu próprio por período (fantasia) ou um toque no
## horizonte de dia.
const BIOMES := {
	Biome.SUMMER: {
		"grass": [Color(0.29, 0.53, 0.21), Color(0.4, 0.57, 0.22), Color(0.2, 0.44, 0.26), Color(0.12, 0.31, 0.15)],
		"leaves": [Color(0.3, 0.6, 0.25), Color(0.45, 0.7, 0.28), Color(0.25, 0.5, 0.22)],
		"leaf_mix": 0.0, "conifer_mix": 0.0, "petals": 0.0,
	},
	Biome.AUTUMN: {
		"grass": [Color(0.6, 0.42, 0.17), Color(0.74, 0.47, 0.15), Color(0.47, 0.38, 0.17), Color(0.46, 0.2, 0.1)],
		"leaves": [Color(0.95, 0.48, 0.1), Color(0.9, 0.33, 0.12), Color(0.98, 0.76, 0.2)],
		"leaf_mix": 1.0, "conifer_mix": 0.0, "petals": 0.0,
		"horizon_tint": Color(0.92, 0.84, 0.72),
	},
	Biome.SAKURA: {
		"grass": [Color(0.36, 0.6, 0.25), Color(0.5, 0.66, 0.3), Color(0.28, 0.52, 0.3), Color(0.18, 0.4, 0.2)],
		"leaves": [Color(1.0, 0.7, 0.82), Color(0.99, 0.95, 0.97), Color(0.42, 0.7, 0.3)],
		"leaf_mix": 1.0, "conifer_mix": 0.0, "petals": 1.0,
		"horizon_tint": Color(0.95, 0.86, 0.96),
	},
	Biome.FANTASY: {
		"grass": [Color(0.86, 0.48, 0.72), Color(0.95, 0.6, 0.8), Color(0.76, 0.42, 0.72), Color(0.56, 0.26, 0.52)],
		"leaves": [Color(0.62, 0.3, 0.88), Color(0.84, 0.46, 0.96), Color(0.42, 0.24, 0.78)],
		"leaf_mix": 1.0, "conifer_mix": 1.0, "petals": 0.0,
		"sky": {
			TimeOfDay.DAY: [Color(0.1, 0.62, 0.6), Color(0.62, 0.98, 0.9), Color(0.7, 0.98, 0.92)],
			TimeOfDay.SUNSET: [Color(0.16, 0.32, 0.5), Color(0.98, 0.62, 0.75), Color(0.9, 0.7, 0.8)],
			TimeOfDay.NIGHT: [Color(0.0, 0.07, 0.08), Color(0.03, 0.2, 0.2), Color(0.1, 0.25, 0.25)],
		},
	},
}


static func night_amount(time_of_day: int) -> float:
	match time_of_day:
		TimeOfDay.NIGHT:
			return 1.0
		TimeOfDay.SUNSET:
			return 0.35
	return 0.0
