// Árvores estilizadas (MultiMesh): sombreamento toon, copas com tufos de folhas mais claros e
// escuros (ruído em espaço de mundo), borda iluminada e balanço com o vento.
// INSTANCE_CUSTOM: r = tom da copa, g = fase do vento, b = variação de matiz (outono/primavera),
//                  a = zona de verde escuro (TrackTerrain.dark_zone).
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

#include "res://shaders/track/terrain_common.gdshaderinc"

uniform vec4 tint_dark : source_color = vec4(0.8, 0.9, 0.86, 1.0);
uniform vec4 tint_light : source_color = vec4(1.1, 1.08, 0.84, 1.0);
uniform vec4 tint_warm : source_color = vec4(1.25, 1.0, 0.6, 1.0);
uniform float sway = 0.12;

varying float tone;
varying float hue;
varying float dark;
varying vec3 world_pos;
varying vec3 local_pos;

void vertex() {
	tone = INSTANCE_CUSTOM.r;
	hue = INSTANCE_CUSTOM.b;
	local_pos = VERTEX;
	// Árvores nas zonas de grama escura também ficam mais escuras (calculado por árvore na CPU)
	dark = INSTANCE_CUSTOM.a;
	float h = max(VERTEX.y - 1.5, 0.0);
	float phase = INSTANCE_CUSTOM.g * 6.2831;
	VERTEX.x += sin(TIME * 1.1 + phase) * sway * h * 0.12;
	VERTEX.z += cos(TIME * 0.8 + phase * 1.3) * sway * h * 0.08;
	// Folhagem tremulando
	VERTEX += NORMAL * sin(TIME * 3.0 + phase + VERTEX.y * 2.0) * 0.03 * step(1.5, VERTEX.y);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = COLOR.rgb;
	float leaf = COLOR.g > COLOR.r * 1.05 ? 1.0 : 0.0;
	if (leaf > 0.5) {
		// Pinheiros/ciprestes (verde-azulado) x folhosas: paleta do ambiente
		float conifer = step(1.3, COLOR.b / max(COLOR.r, 0.01));
		c = tc_leaf_color(c, fract(hue * 3.7 + tone * 0.31), conifer);
		c *= mix(tint_dark.rgb, tint_light.rgb, tone);
		// Algumas árvores um pouco mais amareladas
		c *= mix(vec3(1.0), tint_warm.rgb, smoothstep(0.82, 1.0, hue) * 0.6 * (1.0 - leaf_mix));
		// Tufos de folhas: manchas claras/escuras com borda definida (estilo cel)
		float n = tc_noise(world_pos.xz * 1.1 + world_pos.y * 1.3 + tone * 10.0);
		c *= mix(0.86, 1.1, smoothstep(0.45, 0.55, n));
		c = mix(c, c * vec3(0.6, 0.74, 0.7), dark * 0.85);
	} else {
		// Casca: listras verticais sutis
		c *= 0.9 + 0.1 * step(0.5, fract(atan(local_pos.z, local_pos.x) * 2.0));
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	RIM = 0.3 * leaf;
	RIM_TINT = 0.6;
	BACKLIGHT = vec3(0.12, 0.18, 0.05) * leaf;
}
