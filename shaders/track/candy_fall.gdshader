// Cachoeiras das ilhas voadoras da Rainbow Raceway: lâmina com filetes descendo, na cor da água
// (water_color) passando pelo arco-íris pastel no meio da queda (rainbow), bordas transparentes,
// espuma onde a água sai e sumindo em névoa embaixo (não chega a lugar nenhum: some no ar).
// UV.x = 0..1 na largura, UV.y = 0 no alto .. 1 embaixo.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;

uniform vec3 water_color : source_color = vec3(0.62, 0.9, 1.0);
uniform vec3 foam_color : source_color = vec3(1.0, 0.98, 1.0);
uniform float rainbow = 0.35;
uniform float speed = 0.8;
global uniform float night;

float cf_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float cf_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(cf_hash(i), cf_hash(i + vec2(1.0, 0.0)), u.x), mix(cf_hash(i + vec2(0.0, 1.0)), cf_hash(i + vec2(1.0)), u.x), u.y);
}

vec3 cf_hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	float t = TIME * speed;
	float x = UV.x;
	float y = UV.y;
	float edge = smoothstep(0.0, 0.18, x) * (1.0 - smoothstep(0.82, 1.0, x));
	float streak = cf_noise(vec2(x * 14.0, y * 6.0 - t * 2.2));
	float fine = cf_noise(vec2(x * 40.0, y * 18.0 - t * 3.6));
	float foam = 1.0 - smoothstep(0.0, 0.08, y);
	// Arco-íris pastel atravessando a queda (faixas horizontais suaves no meio)
	vec3 bow = mix(vec3(1.0), cf_hue(fract(y * 1.6 + 0.1)), 0.55);
	vec3 col = mix(water_color, water_color * bow, rainbow * smoothstep(0.15, 0.4, y));
	col = mix(col, foam_color, clamp(streak * 0.45 + fine * 0.2 + foam * 0.8, 0.0, 1.0));
	// Some em névoa: cada vez mais transparente e mais larga (as bordas abrem) até sumir
	float fade = 1.0 - smoothstep(0.45, 1.0, y);
	ALBEDO = col;
	EMISSION = col * (0.15 + 0.5 * night);
	ALPHA = edge * fade * clamp(0.55 + streak * 0.3 + fine * 0.2 + foam * 0.3, 0.0, 0.95);
}
