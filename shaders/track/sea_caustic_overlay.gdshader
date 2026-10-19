// Cáustica sobre a pista (pista no fundo do mar): uma camada aditiva logo acima do asfalto, das
// faixas e da área de escape, com a mesma rede de luz do leito e da pedra (caustics.gdshaderinc).
// Assim os pisos não precisam de um shader próprio. Some de longe e fora d'água.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

#include "res://shaders/track/caustics.gdshaderinc"

uniform float amount = 0.16;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	ALBEDO = sea_caustic_light(wpos, vec3(0.0, 1.0, 0.0), dist, TIME) * amount;
}
