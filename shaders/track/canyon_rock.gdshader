// Rocha das paredes do cânion e das montanhas do trecho emerso (SeaCanyon), com muita variação de cor:
//  * estratos: faixas quase horizontais (~12 m, tortas pelo ruído) numa sequência de cores — debaixo
//    d'água ardósia azulada, ocre, ferrugem, roxo acinzentado e verde mineral; acima do mar creme,
//    ocre, terracota, tijolo e cinza —, com a sequência deslocada por regiões grandes e listras finas
//    dentro de cada faixa;
//  * do tom da faixa até bem escuro pela textura de ruído (noise_tex, projetada nos três eixos do
//    mundo: manchas grandes, médias e o grão);
//  * escorridos de ferrugem descendo pelas paredes, veios claros de quartzo, rachaduras (crack_tex);
//  * debaixo d'água: musgo e algas nas faces de cima, areia nos planos, colônias de líquen e
//    esponjas em pontinhos de cores vivas, incrustações de coral, a cáustica e mais escuro quanto
//    mais fundo; acima do mar: vegetação nas faces de cima, líquen alaranjado e a faixa molhada
//    perto da linha d'água.
// Sem contorno anime (rugosidade 0).
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

#include "res://shaders/track/caustics.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D crack_tex : filter_linear_mipmap, repeat_enable;
// Estratos debaixo d'água
uniform vec3 wet_a : source_color = vec3(0.34, 0.41, 0.48);
uniform vec3 wet_b : source_color = vec3(0.62, 0.52, 0.36);
uniform vec3 wet_c : source_color = vec3(0.58, 0.34, 0.27);
uniform vec3 wet_d : source_color = vec3(0.46, 0.38, 0.53);
uniform vec3 wet_e : source_color = vec3(0.3, 0.47, 0.43);
// Estratos acima do mar
uniform vec3 dry_a : source_color = vec3(0.88, 0.8, 0.64);
uniform vec3 dry_b : source_color = vec3(0.82, 0.59, 0.34);
uniform vec3 dry_c : source_color = vec3(0.74, 0.43, 0.28);
uniform vec3 dry_d : source_color = vec3(0.62, 0.3, 0.22);
uniform vec3 dry_e : source_color = vec3(0.6, 0.58, 0.53);
uniform vec3 rock_dark : source_color = vec3(0.08, 0.1, 0.13);
uniform vec3 rust_color : source_color = vec3(0.52, 0.25, 0.13);
uniform vec3 vein_color : source_color = vec3(0.9, 0.88, 0.8);
uniform vec3 sand_color : source_color = vec3(0.78, 0.74, 0.6);
uniform vec3 moss_color : source_color = vec3(0.17, 0.4, 0.22);
uniform vec3 coral_a : source_color = vec3(1.0, 0.45, 0.4);
uniform vec3 coral_b : source_color = vec3(0.95, 0.62, 0.22);
uniform vec3 lichen_a : source_color = vec3(1.0, 0.8, 0.22);
uniform vec3 lichen_b : source_color = vec3(1.0, 0.45, 0.36);
uniform vec3 lichen_c : source_color = vec3(0.76, 0.42, 0.96);
uniform vec3 lichen_d : source_color = vec3(0.36, 0.92, 0.76);
uniform vec3 grass_color : source_color = vec3(0.3, 0.5, 0.18);
// Profundidade (m abaixo da linha d'água) em que a rocha fica bem mais escura.
uniform float dark_depth = 70.0;
uniform float normal_strength = 0.9;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tri_weights(vec3 n) {
	vec3 b = pow(abs(n), vec3(4.0));
	return b / (b.x + b.y + b.z);
}

float tri(sampler2D t, vec3 p, vec3 b, float scale) {
	return texture(t, p.zy * scale).r * b.x + texture(t, p.xz * scale).r * b.y + texture(t, p.xy * scale).r * b.z;
}

// Sequência de cinco faixas (t em faixas de 1/5), bordas suaves.
vec3 strata(float t, vec3 a, vec3 b, vec3 c, vec3 d, vec3 e) {
	float x = fract(t) * 5.0;
	float i = floor(x);
	float f = smoothstep(0.78, 1.0, fract(x));
	vec3 c0 = i < 0.5 ? a : (i < 1.5 ? b : (i < 2.5 ? c : (i < 3.5 ? d : e)));
	vec3 c1 = i < 0.5 ? b : (i < 1.5 ? c : (i < 2.5 ? d : (i < 3.5 ? e : a)));
	return mix(c0, c1, f);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 b = tri_weights(n);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(60.0, 200.0, dist);
	float depth = water_level - wpos.y;
	bool wet = depth > 0.0;
	// Manchas grandes, médias, o grão e as regiões (outra sequência de faixas)
	float big = tri(noise_tex, wpos, b, 0.006);
	float mid = tri(noise_tex, wpos + vec3(31.0, 7.0, 13.0), b, 0.03);
	float fine = mix(0.5, tri(noise_tex, wpos + vec3(77.0, 51.0, 3.0), b, 0.21), near);
	float region = tri(noise_tex, wpos + vec3(-57.0, 19.0, 211.0), b, 0.0025);
	// Estratos
	float sy = wpos.y * 0.082 + big * 1.6 + mid * 0.4 + floor(region * 3.0) * 0.37;
	vec3 band = wet ? strata(sy, wet_a, wet_b, wet_c, wet_d, wet_e) : strata(sy, dry_a, dry_b, dry_c, dry_d, dry_e);
	// (um pouco puxado para o tom médio: faixas marcadas sem virar listras de bandeira)
	band = mix(band, wet ? wet_a : dry_e, 0.18) * (0.88 + 0.12 * sin(wpos.y * 2.4 + mid * 6.0));
	// Do tom da faixa até bem escuro (textura de ruído)
	float tone = clamp(0.5 + (big - 0.5) * 1.3 + (mid - 0.5) * 0.7 + (fine - 0.5) * 0.4, 0.0, 1.0);
	vec3 col = mix(rock_dark, band, 0.32 + 0.68 * tone);
	// Coordenada na superfície: nas paredes, ao longo dela e a altura; no chão, x e z
	vec2 tang = normalize(vec2(-n.z, n.x) + vec2(1e-4, 0.0));
	float along = dot(wpos.xz, tang);
	vec2 sp = abs(n.y) > 0.7 ? wpos.xz : vec2(along, wpos.y);
	// Escorridos de ferrugem descendo pelas paredes
	float streak = texture(noise_tex, vec2(along * 0.07, wpos.y * 0.009)).r;
	float rust = smoothstep(0.62, 0.78, streak) * (1.0 - abs(n.y)) * smoothstep(0.35, 0.6, mid);
	col = mix(col, rust_color * (0.7 + 0.5 * fine), rust * 0.55);
	// Rachaduras escuras e veios claros de quartzo (só em algumas regiões)
	float cell = tri(crack_tex, wpos, b, 0.05);
	col *= mix(1.0, 0.42, (1.0 - smoothstep(0.02, 0.09, cell)) * mix(0.5, 1.0, near));
	float vein = (1.0 - smoothstep(0.0, 0.035, tri(crack_tex, wpos * 0.6 + vec3(13.0), b, 0.02))) * smoothstep(0.55, 0.75, region);
	col = mix(col, vein_color * (0.8 + 0.3 * fine), vein * 0.5 * mix(0.4, 1.0, near));
	// Pontinhos (líquen e esponjas) em colônias: cor viva por célula
	vec2 cid = floor(sp * 2.2);
	float hsh = fract(sin(dot(cid, vec2(12.9898, 78.233))) * 43758.5453);
	float speck = (1.0 - smoothstep(0.14, 0.3, length(fract(sp * 2.2) - 0.5 - (vec2(hsh, fract(hsh * 7.3)) - 0.5) * 0.4)))
		* step(0.42, hsh) * near;
	float colony = smoothstep(0.55, 0.7, tri(noise_tex, wpos + vec3(5.0, 91.0, 47.0), b, 0.035));
	float up = smoothstep(0.45, 0.85, n.y);
	if (wet) {
		// Musgo e algas nas faces de cima, areia nos planos
		float moss = up * smoothstep(0.4, 0.62, mid + (fine - 0.5) * 0.5);
		col = mix(col, moss_color * (0.65 + 0.7 * fine), moss * 0.8);
		float sand = smoothstep(0.9, 0.98, n.y) * smoothstep(0.45, 0.7, big + (fine - 0.5) * 0.3);
		col = mix(col, sand_color * (0.8 + 0.3 * fine), sand * 0.7);
		// Líquen e esponjas incrustadas, em quatro cores
		vec3 lc = hsh < 0.62 ? lichen_a : (hsh < 0.75 ? lichen_b : (hsh < 0.88 ? lichen_c : lichen_d));
		col = mix(col, lc, speck * colony * 0.85);
		// Incrustações de coral (manchas maiores, quentes)
		float crust = smoothstep(0.6, 0.7, tri(noise_tex, wpos + vec3(5.0, 91.0, 47.0), b, 0.035)) * smoothstep(0.5, 0.7, big)
			* (1.0 - up) * near;
		col = mix(col, mix(coral_a, coral_b, step(0.5, mid)) * (0.7 + 0.5 * fine), crust * 0.45);
		// Mais fundo, mais escuro
		col *= mix(1.0, 0.45, smoothstep(10.0, dark_depth, depth));
	} else {
		// Acima do mar: vegetação nas faces de cima, líquen alaranjado e a faixa molhada
		float veg = up * smoothstep(0.3, 0.55, mid + (fine - 0.5) * 0.6);
		col = mix(col, grass_color * (0.7 + 0.6 * fine), veg);
		col = mix(col, mix(lichen_a, lichen_b, hsh), speck * colony * (1.0 - veg) * 0.6);
		col *= mix(0.55, 1.0, smoothstep(0.0, 5.0, -depth));
	}
	ALBEDO = col;
	// Relevo: normal map do ruído no eixo dominante (projeção como a do building_common)
	vec2 uv = b.y > max(b.x, b.z) ? wpos.xz : (b.x > b.z ? vec2(wpos.z, -wpos.y) : vec2(wpos.x, -wpos.y));
	NORMAL_MAP = texture(normal_tex, uv * 0.11).rgb;
	NORMAL_MAP_DEPTH = normal_strength * mix(0.35, 1.0, near);
	ROUGHNESS = 0.0;
	if (wet) {
		EMISSION = sea_caustic_light(wpos, n, dist, TIME) * col * 0.6 * mix(1.0, 0.4, smoothstep(12.0, 45.0, depth));
	}
}
