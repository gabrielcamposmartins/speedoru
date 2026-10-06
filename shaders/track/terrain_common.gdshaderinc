// Funções compartilhadas pelo terreno, grama 3D e árvores (mesma cor de grama nos três).
// As cores vêm de uniforms globais (lineares) definidos pelo Daylight conforme o ambiente
// (verão, outono, sakura, fantasia): trocar de ambiente não precisa reconstruir nada.

global uniform vec3 grass_lush;
global uniform vec3 grass_warm;
global uniform vec3 grass_cool;
global uniform vec3 grass_deep;
global uniform vec3 leaf_a;
global uniform vec3 leaf_b;
global uniform vec3 leaf_c;
// 0 = folhas com a cor original do modelo (verão), 1 = paleta leaf_a/b/c.
global uniform float leaf_mix;
// Pinheiros/ciprestes também mudam de cor (fantasia) ou continuam verdes (outono, sakura).
global uniform float conifer_mix;
global uniform float night;

// Hash sem seno (estável com coordenadas de mundo grandes; sin() perde precisão na GPU).
float tc_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float tc_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(tc_hash(i), tc_hash(i + vec2(1.0, 0.0)), f.x),
		mix(tc_hash(i + vec2(0.0, 1.0)), tc_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float tc_fbm(vec2 p) {
	return tc_noise(p) * 0.55 + tc_noise(p * 2.13 + 7.1) * 0.3 + tc_noise(p * 4.37 + 3.7) * 0.15;
}

vec3 tc_srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

// Zonas de verde mais escuro (grama alta, sombra de bosque): 0 = normal, 1 = escura.
float tc_dark_zone(vec2 xz) {
	return smoothstep(0.5, 0.6, tc_fbm(xz / 240.0 + vec2(31.0, 7.0)));
}

// Cor da grama: manchas grandes (verde-amarelado / verde-azulado), tufos mais escuros e
// zonas de verde profundo alternando com as claras.
vec3 tc_grass_color(vec2 xz) {
	vec3 lush = grass_lush;
	vec3 warm = grass_warm;
	vec3 cool = grass_cool;
	float big = tc_fbm(xz / 85.0);
	float mid = tc_noise(xz / 17.0);
	vec3 c = mix(lush, warm, smoothstep(0.52, 0.75, big));
	c = mix(c, cool, smoothstep(0.42, 0.18, big) * 0.8);
	c *= 0.9 + 0.2 * mid;
	vec3 deep = grass_deep * (0.9 + 0.2 * mid);
	c = mix(c, deep, tc_dark_zone(xz) * 0.9);
	return c;
}

// Versão leve (menos oitavas) para a grama 3D, que avalia a cor em cada vértice.
vec3 tc_grass_color_lite(vec2 xz) {
	vec3 lush = grass_lush;
	vec3 warm = grass_warm;
	vec3 cool = grass_cool;
	vec2 p = xz / 85.0;
	float big = tc_noise(p) * 0.6 + tc_noise(p * 2.13 + 7.1) * 0.4;
	float mid = tc_noise(xz / 17.0);
	vec3 c = mix(lush, warm, smoothstep(0.52, 0.75, big));
	c = mix(c, cool, smoothstep(0.42, 0.18, big) * 0.8);
	c *= 0.9 + 0.2 * mid;
	vec2 q = xz / 240.0 + vec2(31.0, 7.0);
	float zone = smoothstep(0.5, 0.6, tc_noise(q) * 0.6 + tc_noise(q * 2.13 + 7.1) * 0.4);
	return mix(c, grass_deep * (0.9 + 0.2 * mid), zone * 0.9);
}

// Densidade de flores (campinas floridas em manchas).
float tc_meadow(vec2 xz) {
	return smoothstep(0.55, 0.75, tc_noise(xz / 38.0 + 11.0));
}

vec3 tc_flower_color(float h) {
	if (h < 0.25) return tc_srgb(vec3(1.0, 1.0, 0.96));
	if (h < 0.5) return tc_srgb(vec3(1.0, 0.86, 0.2));
	if (h < 0.75) return tc_srgb(vec3(1.0, 0.55, 0.75));
	return tc_srgb(vec3(0.55, 0.65, 1.0));
}

// Cor de folhagem pela paleta do ambiente. base = cor original (do modelo), pick = 0..1 escolhe
// o tom (cada árvore um), conifer = 1 para pinheiros/ciprestes.
vec3 tc_leaf_color(vec3 base, float pick, float conifer) {
	float lum = dot(base, vec3(0.3, 0.6, 0.1));
	vec3 pal = pick < 0.4 ? leaf_a : (pick < 0.75 ? leaf_b : leaf_c);
	// Mantém o brilho relativo do modelo (copas claras/escuras continuam diferentes)
	// (limitado para cores claras como o branco da sakura não estourarem no bloom)
	vec3 recolored = pal * clamp(lum / 0.22, 0.55, 1.4);
	recolored *= min(1.0, 0.8 / max(max(recolored.r, recolored.g), recolored.b));  // mantém o matiz
	float amount = leaf_mix * mix(1.0, conifer_mix, conifer);
	return mix(base, recolored, amount);
}
