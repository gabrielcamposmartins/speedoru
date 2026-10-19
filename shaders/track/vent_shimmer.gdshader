// Água tremendo de calor sobre a boca dos vulcões de bolhas (SeaVents): um cilindro aberto (UV.y = 0
// embaixo, 1 em cima) que mostra a imagem de trás deslocada por um ruído que sobe, mais forte perto
// da boca, com um calor alaranjado bem de leve; some nas bordas do cilindro (de lado), em cima e com
// a distância. Desenhado antes das bolhas (render_priority -1 no material).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.014;
uniform float fade_distance = 150.0;
uniform vec3 tint : source_color = vec3(1.0, 0.55, 0.25);

varying float k;

float shimmer_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float shimmer_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(shimmer_hash(i), shimmer_hash(i + vec2(1.0, 0.0)), u.x),
		mix(shimmer_hash(i + vec2(0.0, 1.0)), shimmer_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	k = exp(-length((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD) / fade_distance);
}

void fragment() {
	float h = UV.y;
	vec2 p = vec2(UV.x * 9.0, h * 5.0 - TIME * 1.7);
	vec2 off = vec2(shimmer_noise(p) - 0.5, shimmer_noise(p * 1.7 + 13.0) - 0.5);
	float power = (1.0 - h * 0.7) * k;
	vec3 bg = textureLod(screen_tex, SCREEN_UV + off * strength * power, 0.0).rgb;
	float side = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.2);
	ALBEDO = bg + tint * 0.035 * (1.0 - h);
	ALPHA = side * smoothstep(0.0, 0.08, h) * (1.0 - smoothstep(0.55, 1.0, h)) * k;
}
