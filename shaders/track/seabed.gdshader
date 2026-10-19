// Leito do mar (pista no fundo do mar, SeaFloor): areia clara com ondinhas e manchas, rocha nas
// encostas (o cânion da fossa), tufos de algas e a cáustica da água (caustics.gdshaderinc),
// escurecendo com a profundidade; acima do mar (a serra das montanhas do trecho emerso), rocha seca
// e vegetação. A malha está em coordenadas do mundo.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://shaders/track/caustics.gdshaderinc"

uniform vec3 sand_color : source_color = vec3(0.86, 0.8, 0.64);
uniform vec3 sand_dark : source_color = vec3(0.62, 0.6, 0.5);
uniform vec3 rock_color : source_color = vec3(0.36, 0.4, 0.42);
uniform vec3 weed_color : source_color = vec3(0.2, 0.42, 0.32);
// Profundidade (m abaixo da linha d'água) em que o fundo fica bem mais escuro.
uniform float dark_depth = 90.0;

varying vec3 wpos;
varying vec3 wnormal;
// Rocha pela inclinação, calculada no vértice e interpolada (com o limiar no fragment as bordas
// seguiam os triângulos da grade de 10 m)
varying float rock_w;

float bed_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float bed_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(bed_hash(i), bed_hash(i + vec2(1.0, 0.0)), u.x),
		mix(bed_hash(i + vec2(0.0, 1.0)), bed_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float bed_fbm(vec2 p) {
	return bed_noise(p) * 0.55 + bed_noise(p * 2.07 + 5.1) * 0.3 + bed_noise(p * 4.3 + 1.7) * 0.15;
}

void vertex() {
	wpos = VERTEX;
	wnormal = NORMAL;
	// (de ~30° a ~45° vira rocha: as encostas das montanhas ficam de pedra, as dunas de areia)
	rock_w = smoothstep(0.06, 0.3, 1.0 - clamp(NORMAL.y, 0.0, 1.0));
}

void fragment() {
	vec2 p = wpos.xz;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(30.0, 120.0, dist);
	// Areia: ondinhas (cristas paralelas, tortas pelo ruído) e manchas claras/escuras
	float warp = bed_fbm(p * 0.03) * 6.0;
	float ripple = sin(dot(p, vec2(0.86, 0.5)) * 1.7 + warp) * 0.5 + 0.5;
	float patches = bed_fbm(p * 0.012);
	vec3 col = mix(sand_dark, sand_color, smoothstep(0.3, 0.75, patches));
	col *= 1.0 - 0.08 * ripple * near;
	// Tufos de algas e cascalho escuro
	float weed = smoothstep(0.55, 0.8, bed_fbm(p * 0.05 + 3.3));
	col = mix(col, weed_color, weed * 0.55);
	// Rocha nas encostas
	float rock = clamp(rock_w + (bed_fbm(p * 0.06 + vec2(wpos.y * 0.05)) - 0.5) * 0.35, 0.0, 1.0);
	vec3 rk = rock_color * (0.75 + 0.5 * bed_fbm(vec2(p.x + p.y, wpos.y) * 0.15));
	col = mix(col, rk, rock);
	// Mais fundo, mais escuro
	float depth = water_level - wpos.y;
	col *= mix(1.0, 0.45, smoothstep(10.0, dark_depth, depth));
	if (depth < 0.0) {
		// Acima do mar (a serra das montanhas do trecho emerso): rocha seca, vegetação nos planos e a
		// faixa molhada perto da linha d'água
		// (as mesmas faixas de cor das montanhas: creme, ocre, terracota e tijolo pela altura)
		float sy = wpos.y * 0.082 + bed_fbm(p * 0.006) * 1.6;
		float k = fract(sy) * 4.0;
		vec3 bands = k < 1.0 ? vec3(0.88, 0.8, 0.64) : (k < 2.0 ? vec3(0.82, 0.59, 0.34) : (k < 3.0 ? vec3(0.74, 0.43, 0.28) : vec3(0.62, 0.3, 0.22)));
		vec3 dry = bands * (0.55 + 0.5 * bed_fbm(p * 0.07));
		float veg = smoothstep(0.72, 0.9, normalize(wnormal).y) * smoothstep(0.3, 0.55, bed_fbm(p * 0.04 + 3.0));
		col = mix(dry, vec3(0.3, 0.48, 0.2) * (0.8 + 0.4 * bed_fbm(p * 0.3)), veg);
		col *= mix(0.6, 1.0, smoothstep(0.0, 5.0, -depth));
	}
	ALBEDO = col;
	// Rugosidade 0: o contorno anime (outline_post) não desenha as cristas das dunas e montanhas
	// (linhas pretas que não somem na névoa da água); sem especular, não muda a luz
	ROUGHNESS = 0.0;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Cáustica discreta no fundo e mais apagada quanto mais funda a água (não parece piscina)
	EMISSION = sea_caustic_light(wpos, n, dist, TIME) * col * 0.5 * mix(1.0, 0.4, smoothstep(12.0, 45.0, depth));
}
