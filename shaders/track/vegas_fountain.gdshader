shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
// Jatos das fontes do Bellagio: cada instância é um jato (cilindro de 1 m com a base em y = 0).
// INSTANCE_CUSTOM.r = posição ao longo da fila (0..1); a altura segue uma coreografia que se repete
// a cada `cycle` s: ondas correndo pela fila, todos juntos e o "estouro" final; entre os shows os
// jatos ficam baixos. A névoa abre perto do topo. À noite brilha mais (night).

uniform float cycle = 36.0;
uniform float max_height = 70.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;

varying float v_up;
varying float v_alpha;

float show_height(float x, float t) {
	float c = fract(t / cycle) * cycle;
	if (c > 24.0) {
		return 0.06;
	}
	float wave = 0.5 + 0.5 * sin(x * 18.0 - c * 2.4);
	float sweep = smoothstep(0.0, 0.15, (c / 8.0) - x) * step(c, 8.0);
	float together = (0.55 + 0.45 * sin(c * 1.8)) * step(8.0, c) * step(c, 16.0);
	float finale = smoothstep(16.0, 19.0, c) * (1.0 - smoothstep(22.0, 24.0, c)) * (0.8 + 0.2 * sin(x * 40.0 + c * 9.0));
	float h = max(max(wave * sweep, together * (0.4 + 0.6 * wave)), finale * 1.25);
	return max(h, 0.06);
}

void vertex() {
	float x = INSTANCE_CUSTOM.r;
	float h = show_height(x, TIME) * max_height;
	v_up = clamp(VERTEX.y, 0.0, 1.0);
	// Névoa: o jato abre e afina em cima
	float spread = 1.0 + v_up * v_up * (1.0 + h * 0.025);
	VERTEX.xz *= spread;
	VERTEX.y *= h;
	v_alpha = smoothstep(0.0, 0.08, v_up) * (1.0 - smoothstep(0.55, 1.0, v_up));
}

void fragment() {
	vec3 col = vec3(0.85, 0.92, 1.0);
	float a = v_alpha * mix(0.18, 0.7, night);
	ALBEDO = col * a;
	EMISSION = col * a * mix(0.4, 2.2, night);
}
