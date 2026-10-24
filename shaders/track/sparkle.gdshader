// Brilhinhos no ar da Rainbow Raceway (e nas pontas das estrelas e dos enfeites): quadrado sempre
// virado para a câmera com uma estrela de quatro pontas de luz, piscando cada um no seu ritmo
// (fase tirada da posição). A cor vem da instância (MultiMesh com cores); aditivo, mais forte à noite.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float day_energy = 0.9;
uniform float night_energy = 2.2;
uniform float twinkle = 1.0;
global uniform float night;

varying float glow;
varying vec3 tint;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float h = fract(sin(dot(center, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float t = 0.5 + 0.5 * sin(TIME * (1.2 + h * 2.4) + h * 40.0);
	glow = mix(1.0, pow(t, 4.0), twinkle);
	float scale = length(MODEL_MATRIX[0].xyz) * (0.55 + 0.45 * glow);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= scale;
	tint = COLOR.rgb;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float core = exp(-length(q) * 5.0);
	float rays = exp(-abs(q.x) * 28.0) * exp(-abs(q.y) * 2.6) + exp(-abs(q.y) * 28.0) * exp(-abs(q.x) * 2.6);
	float edge = 1.0 - smoothstep(0.8, 1.0, max(abs(q.x), abs(q.y)));
	ALBEDO = tint * (core * 1.6 + rays) * edge * glow * mix(day_energy, night_energy, night);
}
