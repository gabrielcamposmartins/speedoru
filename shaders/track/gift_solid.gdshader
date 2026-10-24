// Miolo das caixas de presente e estrelas grandes no ar (ver gift_common.gdshaderinc): aceso.
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/track/gift_common.gdshaderinc"

void fragment() {
	ALBEDO = tint;
	EMISSION = tint * mix(day_energy, night_energy, night) * 0.55;
	// (sem o contorno anime: peça acesa)
	ROUGHNESS = 0.01;
}
