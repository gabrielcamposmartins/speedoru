// Pinheiro de preenchimento (modelo Tree_Pine_Light: agulhas em cards, dupla face). A cor vem da
// paleta do ambiente (tc_leaf_color, como as folhosas); o COLOR_0 do modelo só dá a variação de
// claro/escuro entre tufos. Balança com o vento. Rugosidade 0 = sem contorno anime (as agulhas
// virariam um borrão de linhas).
// INSTANCE_CUSTOM: r = tom, g = fase do vento, b = escolha na paleta, a = zona escura.
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

#include "res://shaders/track/terrain_common.gdshaderinc"

// Verde-azulado de pinheiro (sRGB) usado no verão (sem paleta).
uniform vec4 base_color : source_color = vec4(0.16, 0.36, 0.26, 1.0);
// Maior valor de COLOR.g no modelo (normaliza a variação).
uniform float color_scale = 0.0235;
uniform float sway = 0.1;

varying float tone;
varying float pick;
varying float dark;
varying float shade;

void vertex() {
	tone = INSTANCE_CUSTOM.r;
	pick = INSTANCE_CUSTOM.b;
	dark = INSTANCE_CUSTOM.a;
	shade = clamp(COLOR.g / color_scale, 0.35, 1.0);
	float h = max(VERTEX.y - 1.0, 0.0);
	float phase = INSTANCE_CUSTOM.g * 6.2831;
	VERTEX.x += sin(TIME * 0.9 + phase) * sway * h * 0.1;
	VERTEX.z += cos(TIME * 0.7 + phase * 1.3) * sway * h * 0.07;
	VERTEX += NORMAL * sin(TIME * 2.6 + phase + VERTEX.y * 3.0) * 0.02;
}

void fragment() {
	vec3 c = tc_leaf_color(base_color.rgb, pick, 0.0);
	c *= mix(0.8, 1.12, tone) * mix(0.55, 1.15, shade);
	c = mix(c, c * vec3(0.62, 0.74, 0.7), dark * 0.7);
	ALBEDO = c;
	ROUGHNESS = 0.0;
	BACKLIGHT = c * 0.35;
	RIM = 0.2;
	RIM_TINT = 0.6;
}
