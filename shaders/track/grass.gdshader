// Grama 3D em volta da câmera (GrassField): cada instância é um tufo de lâminas.
// Posição, giro, tamanho e flores vêm do hash da célula no mundo, então nada "pula" quando o
// campo acompanha a câmera. Não nasce onde a máscara marca pista/brita/boxes, em penhascos nem
// no alto das montanhas.
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

#include "res://shaders/track/terrain_common.gdshaderinc"

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform vec2 hm_origin;
uniform float hm_cell = 8.0;
uniform ivec2 hm_size = ivec2(2, 2);
uniform sampler2D surface_mask : filter_linear, repeat_disable;
uniform bool has_mask = false;
uniform vec2 mask_origin;
uniform vec2 mask_size = vec2(1.0);
uniform float spacing = 0.55;
uniform float radius = 60.0;
uniform vec3 field_center;
uniform vec2 wind_dir = vec2(0.8, 0.6);

varying float tip;
varying vec3 base_color;
varying float is_flower;
varying vec3 flower_color;

float height_at(vec2 xz) {
	vec2 uv = ((xz - hm_origin) / hm_cell + 0.5) / vec2(hm_size);
	return texture(heightmap, uv).r;
}

void vertex() {
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 cell = round(base.xz / spacing);
	float h1 = tc_hash(cell);
	float h2 = tc_hash(cell + 17.3);
	float h3 = tc_hash(cell + 41.7);
	float h4 = tc_hash(cell + 89.1);
	vec2 jitter = (vec2(h1, h2) - 0.5) * spacing * 0.9;
	vec2 xz = base.xz + jitter;

	float d = distance(xz, field_center.xz);
	// Variações pequenas de tamanho entre tufos e manchas levemente mais altas
	float s = mix(0.85, 1.15, h3) * (0.9 + 0.2 * tc_noise(xz / 9.0));
	s *= 1.0 - smoothstep(radius * 0.6, radius, d);
	if (has_mask) {
		vec2 muv = (xz - mask_origin) / mask_size;
		if (muv.x > 0.0 && muv.y > 0.0 && muv.x < 1.0 && muv.y < 1.0) {
			s *= 1.0 - smoothstep(0.15, 0.4, texture(surface_mask, muv).r);
		}
	}
	float h = height_at(xz);
	float hx = height_at(xz + vec2(2.0, 0.0)) - h;
	float hz = height_at(xz + vec2(0.0, 2.0)) - h;
	float steep = length(vec2(hx, hz)) / 2.0;
	s *= 1.0 - smoothstep(0.55, 0.8, steep);
	s *= 1.0 - smoothstep(100.0, 130.0, h);

	// Flor no topo de alguns tufos (mais nas campinas)
	is_flower = COLOR.g * step(0.965 - 0.12 * tc_meadow(xz), h4);
	flower_color = tc_flower_color(tc_hash(cell + 5.3));
	vec3 v = VERTEX;
	if (COLOR.g > 0.5 && is_flower < 0.5) {
		v = vec3(0.0);
	}
	// Cada lâmina com altura própria (varia de tufo para tufo)
	if (COLOR.g < 0.5) {
		v.y *= 0.8 + 0.4 * fract(COLOR.a * 13.7 + h4 * 5.3);
	}
	float a = h1 * 6.2831;
	v.xz = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * v.xz;
	v *= s;
	// Vento: ondas que atravessam o campo
	float gust = sin(TIME * 1.7 + dot(xz, wind_dir) * 0.18) * 0.5 + 0.5;
	v.xz += wind_dir * (0.04 + 0.1 * gust) * COLOR.r * s;
	VERTEX = v + vec3(jitter.x, h, jitter.y);
	tip = COLOR.r;
	base_color = tc_grass_color_lite(xz);
}

void fragment() {
	vec3 c = mix(base_color * 0.55, base_color * 1.08 + vec3(0.006, 0.008, 0.0), tip);
	if (is_flower > 0.5 && COLOR.g > 0.5 && COLOR.b < 0.5) {
		c = flower_color;
	}
	ALBEDO = c;
	// Rugosidade 0 = sem contorno anime (outline_post.gdshader)
	ROUGHNESS = 0.0;
	BACKLIGHT = vec3(0.25, 0.3, 0.1) * tip;
}
