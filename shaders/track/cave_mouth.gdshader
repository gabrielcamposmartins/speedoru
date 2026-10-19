// Boca de caverna nas paredes do cânion (SeaCanyon): um disco elíptico rente à rocha (UV de -1 a 1 do
// centro à borda) escuro no meio e sumindo na borda, com pontinhos de bioluminescência piscando lá
// dentro (mais fortes à noite) e, onde COLOR.r > 0,5, os olhos amarelos de uma moreia que pisca
// (COLOR.g = fase). A névoa da água continua valendo (some ao longe como a rocha).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 deep : source_color = vec3(0.01, 0.022, 0.045);
uniform vec3 glow_a : source_color = vec3(0.2, 0.9, 1.0);
uniform vec3 glow_b : source_color = vec3(0.9, 0.35, 1.0);
global uniform float night;

float cave_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 q = UV;
	float r = length(q);
	vec3 col = deep * (0.7 + 0.6 * smoothstep(0.2, 1.0, r));
	// Pontinhos de bioluminescência (um por célula, alguns acesos, cada um no seu ritmo)
	vec2 g = q * 6.0 + 6.0;
	vec2 cell = floor(g);
	float h = cave_hash(cell);
	vec2 jit = vec2(cave_hash(cell + 3.7), cave_hash(cell + 9.1)) - 0.5;
	float speck = step(0.78, h) * (1.0 - smoothstep(0.04, 0.14, length(fract(g) - 0.5 - jit * 0.5)));
	speck *= 0.55 + 0.45 * sin(TIME * (0.8 + h * 2.5) + h * 40.0);
	col += mix(glow_a, glow_b, fract(h * 7.3)) * speck * (0.5 + 1.3 * night) * (1.0 - smoothstep(0.35, 0.85, r));
	// Olhos da moreia, piscando de vez em quando
	if (COLOR.r > 0.5) {
		float open = step(0.05, fract(TIME * 0.11 + COLOR.g));
		float eyes = (1.0 - smoothstep(0.025, 0.055, length(q - vec2(-0.1, -0.12))))
			+ (1.0 - smoothstep(0.025, 0.055, length(q - vec2(0.1, -0.12))));
		col += vec3(1.0, 0.86, 0.3) * eyes * open * 1.8;
	}
	ALBEDO = col;
	ALPHA = 1.0 - smoothstep(0.62, 1.0, r);
}
