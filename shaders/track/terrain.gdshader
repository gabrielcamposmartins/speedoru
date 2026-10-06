// Terreno estilizado: grama com manchas, faixas de corte perto da pista, flores, penhascos de rocha
// em camadas (estilo Mario Kart), floresta, rocha e neve nas montanhas.
// use_heightmap: os vértices (PlaneMesh) são deslocados pela textura de altura (TrackTerrain);
// sem ela (anel de montanhas) a altura já vem na malha.
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

#include "res://shaders/track/terrain_common.gdshaderinc"

uniform bool use_heightmap = true;
uniform sampler2D heightmap : filter_nearest, repeat_disable;
uniform vec2 hm_origin;
uniform float hm_cell = 8.0;
uniform ivec2 hm_size = ivec2(2, 2);
uniform float stripe_width = 9.0;
// Normal map do chão (projetado de cima): irregularidades da grama e da terra
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_strength = 0.0;
uniform float normal_scale = 0.35;

varying vec3 world_pos;
varying vec3 world_normal;

float hm(ivec2 c) {
	c = clamp(c, ivec2(0), hm_size - ivec2(1));
	return texelFetch(heightmap, c, 0).r;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (use_heightmap) {
		ivec2 c = ivec2(round((w.xz - hm_origin) / hm_cell));
		float h = hm(c);
		float hl = hm(c - ivec2(1, 0));
		float hr = hm(c + ivec2(1, 0));
		float hd = hm(c - ivec2(0, 1));
		float hu = hm(c + ivec2(0, 1));
		// Um pouco abaixo de zero na parte plana (asfalto e brita ficam milímetros acima)
		VERTEX.y = h - 0.03 * (1.0 - smoothstep(0.0, 0.5, h));
		NORMAL = normalize(vec3(hl - hr, 2.0 * hm_cell, hd - hu));
		w.y = VERTEX.y;
		world_normal = NORMAL;
	} else {
		world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	}
	world_pos = w;
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = normalize(cross(TANGENT, NORMAL));
}

void fragment() {
	vec2 xz = world_pos.xz;
	float y = world_pos.y;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec3 c = tc_grass_color(xz);

	// Faixas do cortador de grama só na área plana do parque
	float flat_area = 1.0 - smoothstep(0.05, 0.6, y);
	float stripe = mod(floor(xz.x / stripe_width), 2.0);
	c *= 1.0 - 0.07 * stripe * flat_area;

	// Florzinhas e trevos (somem com a distância)
	vec2 fp = xz * 1.4;
	vec2 cell = floor(fp);
	float near = 1.0 - smoothstep(25.0, 70.0, dist);
	float fh = tc_hash(cell);
	if (near > 0.0 && fh > 0.985 - 0.04 * tc_meadow(xz) && slope < 0.3) {
		vec2 o = vec2(tc_hash(cell + 3.1), tc_hash(cell + 9.7)) * 0.6 + 0.2;
		float spot = smoothstep(0.16, 0.1, length(fract(fp) - o));
		c = mix(c, tc_flower_color(tc_hash(cell + 5.3)), spot * near);
	}

	// Montanhas: faixa de floresta, rocha e neve (bordas irregulares)
	float n = tc_fbm(xz / 140.0);
	float forest = smoothstep(170.0, 215.0, y + n * 40.0) * (1.0 - smoothstep(300.0, 360.0, y + n * 60.0));
	if (forest > 0.0) {
		vec3 trees = tc_leaf_color(tc_srgb(vec3(0.16, 0.42, 0.28)), tc_noise(xz / 60.0), 0.0) * (0.75 + 0.5 * tc_noise(xz / 9.0));
		c = mix(c, trees, forest);
	}
	vec3 rock_a = tc_srgb(vec3(0.66, 0.54, 0.44));
	vec3 rock_b = tc_srgb(vec3(0.52, 0.43, 0.4));
	// Rocha/terra variando por ruído (sem listras)
	vec3 rock = mix(rock_a, rock_b, smoothstep(0.3, 0.7, tc_noise(xz / 23.0 + y / 17.0)));
	rock *= 0.9 + 0.2 * tc_noise(xz / 5.0 + y / 4.0);
	float high_rock = smoothstep(320.0, 380.0, y + n * 80.0);
	float cliff = smoothstep(0.42, 0.58, slope);
	c = mix(c, rock, max(cliff, high_rock));
	// Borda de grama mais clara no alto dos penhascos
	float lip = smoothstep(0.25, 0.4, slope) * (1.0 - cliff);
	c *= 1.0 + 0.12 * lip;
	float snow = smoothstep(430.0, 470.0, y + n * 90.0) * (1.0 - smoothstep(0.55, 0.75, slope));
	c = mix(c, tc_srgb(vec3(0.95, 0.97, 1.0)), snow);

	ALBEDO = c;
	ROUGHNESS = 1.0;
	RIM = 0.15 * snow;
	if (normal_strength > 0.0) {
		// Duas escalas misturadas (detalhe perto, ondulação mais larga) para não repetir
		vec3 a = texture(normal_tex, xz * normal_scale).rgb;
		vec3 b = texture(normal_tex, xz * normal_scale * 0.23 + 0.37).rgb;
		NORMAL_MAP = normalize(mix(a, b, 0.4) * 2.0 - 1.0) * 0.5 + 0.5;
		// Rocha com mais relevo que a grama; some ao longe para não cintilar
		float fade = 1.0 - smoothstep(60.0, 160.0, dist);
		NORMAL_MAP_DEPTH = normal_strength * mix(1.0, 1.8, cliff) * mix(0.25, 1.0, fade);
	}
}
