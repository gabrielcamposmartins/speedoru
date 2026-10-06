// Folhas soltas (caindo nas partículas e espalhadas no chão/pista num MultiMesh) e pétalas de
// sakura. Forma recortada no fragment (alpha scissor), cor da paleta do ambiente.
// Partículas: COLOR.r = tom (aleatório por folha). MultiMesh: INSTANCE_CUSTOM.r = tom.
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

#include "res://shaders/track/terrain_common.gdshaderinc"

uniform bool use_instance_custom = false;
// Folhas no chão ficam um pouco mais escuras/secas.
uniform float ground_darken = 0.0;
global uniform float petals;

varying float pick;

void vertex() {
	pick = use_instance_custom ? INSTANCE_CUSTOM.r : COLOR.r;
	// Partículas: a folha "tremula" girando um pouco em torno do próprio eixo
	if (!use_instance_custom) {
		VERTEX.y += sin(TIME * 7.0 + pick * 40.0) * 0.03 * VERTEX.x * 6.0;
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float inside;
	if (petals > 0.5) {
		// Pétala: oval com um entalhe na ponta
		float oval = length(vec2(p.x * 1.25, p.y));
		float notch = length(vec2(p.x, p.y - 1.0)) < 0.28 ? 1.0 : 0.0;
		inside = (oval < 0.92 ? 1.0 : 0.0) * (1.0 - notch);
	} else {
		// Folha: elipse pontuda (losango arredondado) com cabinho
		float leaf = abs(p.x) * 1.7 + pow(abs(p.y), 1.6) * 0.95;
		float stem = (abs(p.x) < 0.05 && p.y < -0.8) ? 1.0 : 0.0;
		inside = max(leaf < 1.0 ? 1.0 : 0.0, stem);
	}
	// Pétalas só nos tons a/b (rosa e branco), sem o verde das folhas novas
	vec3 base = tc_leaf_color(vec3(0.07, 0.3, 0.05), petals > 0.5 ? pick * 0.74 : pick, 0.0);
	// Sem paleta (verão): folhas verdes com variação
	base = mix(base, base * (0.8 + 0.4 * pick), 0.5);
	// Nervura central
	float vein = (petals < 0.5 && abs(p.x) < 0.04) ? 0.75 : 1.0;
	ALBEDO = base * vein * (1.0 - ground_darken * (0.3 + 0.3 * pick));
	ALPHA = inside;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.0;
	BACKLIGHT = base * 0.4;
}
