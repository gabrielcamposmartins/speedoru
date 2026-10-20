// Leito do mar (pista no fundo do mar, SeaFloor): areia bege-acinzentada com ondinhas de crista
// clara e vale escuro, manchas de areia mais clara e mais escura, cascalho, conchas e pedrinhas de
// perto, rocha nas encostas (o cânion da fossa), tufos de algas e a cáustica da água
// (caustics.gdshaderinc), escurecendo com a profundidade; acima do mar (a serra das montanhas do
// trecho emerso), rocha seca e vegetação. A malha está em coordenadas do mundo.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://shaders/track/caustics.gdshaderinc"

// (areia mais escura e quente que o branco: na luz azulada da água a clara virava verde-menta)
uniform vec3 sand_color : source_color = vec3(0.66, 0.6, 0.47);
uniform vec3 sand_dark : source_color = vec3(0.44, 0.43, 0.38);
uniform vec3 rock_color : source_color = vec3(0.3, 0.33, 0.36);
uniform vec3 weed_color : source_color = vec3(0.16, 0.34, 0.24);
// Profundidade (m abaixo da linha d'água) em que o fundo fica bem mais escuro.
uniform float dark_depth = 90.0;

varying vec3 wpos;
varying vec3 wnormal;
// Inclinação (1 − normal.y) no vértice, interpolada crua: o limiar da rocha fica no fragment, com
// ruído (pesada no vértice, uma encosta média acendia um vértice sim e outro não e a rocha virava
// triângulos de 10 m)
varying float slope;

// (hash sem seno: com coordenadas de mundo grandes o fract(sin(...)) perdia a precisão na placa de
// vídeo e as células vizinhas saíam quase iguais, em faixas retas)
float bed_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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
	slope = 1.0 - clamp(NORMAL.y, 0.0, 1.0);
}

void fragment() {
	vec2 p = wpos.xz;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(30.0, 120.0, dist);
	// Areia: manchas grandes claras/escuras e ondinhas (cristas paralelas tortas pelo ruído, com a
	// encosta suave clara e o vale escuro), mais fortes de perto (de longe virariam chiado)
	float patches = bed_fbm(p * 0.012);
	vec3 col = mix(sand_dark, sand_color, smoothstep(0.25, 0.8, patches));
	float warp = bed_fbm(p * 0.03) * 6.0 + bed_fbm(p * 0.11) * 1.4;
	float phase = fract(dot(p, vec2(0.86, 0.5)) * 0.27 + warp * 0.16);
	float crest = smoothstep(0.0, 0.7, phase) * (1.0 - smoothstep(0.78, 1.0, phase));
	float ripples = mix(0.35, 1.0, near) * smoothstep(0.25, 0.6, bed_fbm(p * 0.02 + 8.0));
	col *= 1.0 + (crest - 0.55) * 0.22 * ripples;
	// Cascalho, conchas e pedrinhas (só de perto, pequenas e espalhadas)
	float grit = bed_noise(p * 6.1);
	float pebble = smoothstep(0.9, 0.95, bed_noise(p * 5.3 + 11.0)) * smoothstep(0.45, 0.7, bed_fbm(p * 0.08 + 2.0)) * near;
	col *= 1.0 - 0.07 * smoothstep(0.55, 0.85, grit) * near;
	col = mix(col, vec3(0.86, 0.82, 0.74), smoothstep(0.95, 0.98, bed_noise(p * 6.7 + 4.0)) * near * 0.5);
	col = mix(col, rock_color * 0.9, pebble * 0.55);
	// Tufos de algas e cascalho escuro
	float weed = smoothstep(0.55, 0.8, bed_fbm(p * 0.05 + 3.3));
	col = mix(col, weed_color * (0.8 + 0.4 * grit), weed * 0.6);
	// Rocha nas encostas íngremes (de ~35° a ~55°: as dunas ficam de areia, as paredes da fossa e as
	// montanhas de pedra), com a borda quebrada pelo ruído
	float rock = smoothstep(0.17, 0.42, slope + (bed_fbm(p * 0.06 + vec2(wpos.y * 0.05)) - 0.5) * 0.14);
	vec3 rk = rock_color * (0.75 + 0.5 * bed_fbm(vec2(p.x + p.y, wpos.y) * 0.15));
	col = mix(col, rk, rock);
	// Mais fundo, mais escuro (a névoa de altura da água escurece o resto)
	float depth = water_level - wpos.y;
	col *= mix(1.0, 0.6, smoothstep(10.0, dark_depth, depth));
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
	// (sem reflexo do céu: com rugosidade 0 a superfície virava um espelho e a linha do horizonte
	// refletida desenhava polígonos nas normais interpoladas dos triângulos)
	SPECULAR = 0.0;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Cáustica discreta no fundo e mais apagada quanto mais funda a água (não parece piscina)
	EMISSION = sea_caustic_light(wpos, n, dist, TIME) * col * 0.5 * mix(1.0, 0.4, smoothstep(12.0, 45.0, depth));
}
