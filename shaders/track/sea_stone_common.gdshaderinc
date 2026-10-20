// Parte da pedra de Atlântida (sea_stone*.gdshader) incluída ANTES do building_common: as funções
// que o building_common chama no fim do fragment quando SEA_STONE está definido.

#include "res://shaders/track/caustics.gdshaderinc"

// Tom do mármore/calcário: as cores cinzentas (concreto) puxam para ele; cores fortes ficam.
uniform vec3 marble_tint : source_color = vec3(0.86, 0.84, 0.77);
uniform float marble_mix : hint_range(0.0, 1.0) = 0.75;
uniform vec3 moss_color : source_color = vec3(0.2, 0.42, 0.33);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.5;
uniform vec3 coral_color : source_color = vec3(0.92, 0.42, 0.5);
uniform float coral_amount : hint_range(0.0, 1.0) = 0.2;

// (hash sem seno: com coordenadas de mundo grandes o fract(sin(...)) perdia a precisão na placa de
// vídeo e as células vizinhas saíam quase iguais, em faixas retas)
float stone_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float stone_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// (interpolação quíntica: com a cúbica as manchas saíam quadradas, seguindo a grade)
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(stone_hash(i), stone_hash(i + vec2(1.0, 0.0)), u.x),
		mix(stone_hash(i + vec2(0.0, 1.0)), stone_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Oitavas giradas umas em relação às outras (as bordas das células não se alinham)
float stone_fbm(vec2 p) {
	const mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 p2 = rot * p * 2.13 + 4.7;
	return stone_noise(p) * 0.6 + stone_noise(p2) * 0.28 + stone_noise(rot * p2 * 2.05 + 1.3) * 0.12;
}

// Cor final da pedra no ponto `wp` (mundo) com normal de mundo `wn`: mármore, musgo em manchas com
// borda fofa e tufos finos por cima, fios de alga escorrendo pelas paredes, colônias de coral
// incrustado com borda e pólipos (algas e coral só debaixo d'água: fora dela, no trecho emerso, a
// pedra fica com o musgo), e as faces de baixo mais escuras.
vec3 sea_stone_albedo(vec3 c, vec3 wp, vec3 wn) {
	float wet = smoothstep(-1.0, 1.5, water_level - wp.y);
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	float sat = max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
	c = mix(c, marble_tint * (0.3 + lum * 0.85), marble_mix * (1.0 - smoothstep(0.08, 0.35, sat)));
	float up = smoothstep(0.25, 0.85, wn.y);
	float wall = 1.0 - abs(wn.y);
	float down = smoothstep(-0.3, -0.85, wn.y);
	// Coordenada na superfície: nas paredes, ao longo dela e a altura (só com x e z, numa parede
	// virada para x uma das coordenadas ficaria parada e o desenho viraria faixas); no chão, x e z
	vec2 tang = normalize(vec2(-wn.z, wn.x) + vec2(1e-4, 0.0));
	vec2 sp = abs(wn.y) > 0.7 ? wp.xz : vec2(dot(wp.xz, tang), wp.y);
	// Musgo: manchas grandes e, dentro delas, tufos (duas escalas finas)
	float big = stone_fbm(wp.xz * 0.22 + vec2(wp.y * 0.13));
	float fine = stone_noise(wp.xz * 3.1 + vec2(wp.y * 2.3)) * 0.6 + stone_noise(wp.xz * 7.7 - vec2(wp.y * 3.1)) * 0.4;
	// (menos musgo no que tem cor forte — o ouro das coroas, dos tridentes e do diadema —: a pátina fica,
	// mas o ouro não vira uma touca verde)
	float moss_mask = smoothstep(0.36, 0.58, big + (fine - 0.5) * 0.22) * up * (1.0 - 0.6 * smoothstep(0.25, 0.5, sat));
	vec3 moss = mix(moss_color * 0.55, mix(moss_color, vec3(0.55, 0.62, 0.22), 0.45), fine);
	c = mix(c, moss, clamp(moss_mask * moss_amount, 0.0, 1.0));
	// Algas escorrendo pelas paredes: fios finos (uns 20 cm) de comprimentos diferentes, descendo
	// de faixas onde a parede é mais úmida, verdes vivos (no azul da água o verde escuro vira mancha)
	float h_coord = sp.x * 4.2;
	float strand = stone_noise(vec2(h_coord, 0.0)) * 0.7 + stone_noise(vec2(h_coord * 2.3, 3.0)) * 0.3;
	float reach = stone_fbm(vec2(floor(h_coord) * 0.37, wp.y * 0.11));
	float algae = smoothstep(0.58, 0.7, strand) * smoothstep(0.45, 0.6, reach) * wall;
	vec3 alg = mix(vec3(0.16, 0.42, 0.2), vec3(0.42, 0.62, 0.22), fine) * (0.85 + 0.3 * strand);
	c = mix(c, alg, clamp(algae * moss_amount * 1.1, 0.0, 1.0) * wet);
	// Coral incrustado: colônias pequenas (grandes viravam manchas cor-de-rosa na pedra), em tons
	// quentes variados (aparecem no azul), com os pólipos em pontinhos claros e a borda mais escura
	float col_n = stone_fbm(sp * 0.95 + vec2(17.0, 3.0));
	float colony = smoothstep(0.67, 0.74, col_n);
	float rim = smoothstep(0.63, 0.68, col_n) * (1.0 - colony);
	// Pólipos: um por célula, cada um num lugar e num tamanho (sem formar uma grade)
	vec2 cid = floor(sp * 3.4);
	vec2 jit = vec2(stone_hash(cid), stone_hash(cid + 7.3)) - 0.5;
	float polyp = 1.0 - smoothstep(0.08, 0.2 + 0.08 * stone_hash(cid + 3.1), length(fract(sp * 3.4) - 0.5 - jit * 0.5));
	float hue = stone_noise(sp * 0.13 + 41.0);
	vec3 coral = hue < 0.4 ? coral_color : (hue < 0.78 ? vec3(1.0, 0.56, 0.2) : vec3(0.62, 0.34, 0.86));
	c = mix(c, c * 0.65, rim * coral_amount * 2.0 * (0.35 + 0.65 * wall) * wet);
	c = mix(c, coral * (0.75 + 0.5 * polyp), colony * clamp(coral_amount * 2.2, 0.0, 1.0) * (0.35 + 0.65 * wall) * wet);
	// Por baixo (beirais, arcos): sombra e crescimento escuro
	c *= 1.0 - 0.25 * down;
	return c;
}
