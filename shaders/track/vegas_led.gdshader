shader_type spatial;
// Cobertura de LED à moda da Fremont Street (CityNeon): o teto em abóbada é uma tela que alterna
// shows procedurais a cada ~9 s — ondas de cor correndo pelo comprimento, céu estrelado com
// cometas, bandeira quadriculada tremulando e um arco-íris em faixas —, com a grade de pixels.
// UV.x = metros ao longo da cobertura, UV.y = 0..1 de um lado ao outro. De dia contida, à noite forte.
render_mode unshaded, cull_disabled;

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float day_level = 0.85;
uniform float night_level = 2.6;
uniform float pixel = 0.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

vec3 show(int k, vec2 p, float t) {
	if (k == 0) {
		float w = sin(p.x * 0.12 - t * 3.0 + sin(p.y * 6.0) * 0.8);
		return hue(fract(p.x * 0.01 - t * 0.15)) * (0.55 + 0.45 * w);
	} else if (k == 1) {
		vec2 cell = floor(p / pixel);
		float st = step(0.985, hash(cell)) * (0.5 + 0.5 * sin(t * 4.0 + hash(cell + 3.0) * 20.0));
		float comet = smoothstep(2.5, 0.0, abs(p.y * 20.0 - 10.0 - sin(p.x * 0.05) * 3.0))
			* smoothstep(0.0, 30.0, mod(t * 40.0 - p.x, 160.0)) * step(mod(t * 40.0 - p.x, 160.0), 30.0);
		return vec3(0.03, 0.02, 0.12) + vec3(st) + vec3(1.0, 0.6, 0.9) * comet;
	} else if (k == 2) {
		float wave = sin(p.x * 0.08 - t * 2.5) * 0.6;
		float c = mod(floor(p.x / 3.0 + wave) + floor((p.y + wave * 0.05) * 6.0), 2.0);
		return mix(vec3(0.05), vec3(1.0), c) * (0.75 + 0.25 * sin(p.x * 0.08 - t * 2.5));
	}
	float band = floor(fract(p.y + p.x * 0.004 - t * 0.12) * 7.0) / 7.0;
	return hue(band);
}

void fragment() {
	vec2 p = vec2(UV.x, UV.y);
	float t = TIME;
	float slot = t / 9.0;
	int k = int(mod(floor(slot), 4.0));
	vec3 c = show(k, p, t);
	// Troca de show com um fade
	float f = smoothstep(0.85, 1.0, fract(slot));
	c = mix(c, show(int(mod(floor(slot) + 1.0, 4.0)), p, t), f);
	// Grade de pixels
	vec2 g = fract(vec2(p.x / pixel, p.y * 24.0));
	c *= 0.55 + 0.45 * step(0.18, g.x) * step(0.18, g.y);
	ALBEDO = c * mix(day_level, night_level, night);
}
