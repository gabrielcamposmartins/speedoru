// Jato dos motores verticais da Sky Aerobase: cone aberto apontando para baixo (UV.y = 0 no bocal,
// 1 na ponta), aditivo. Miolo branco-azulado, borda azul, anéis de choque (diamantes) perto do
// bocal e cintilação; some na ponta e nas bordas do cone (de lado ele parece cheio).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform vec4 outer_color : source_color = vec4(0.18, 0.5, 1.0, 1.0);
uniform float intensity = 1.0;
global uniform float night;

varying float seed;

void vertex() {
	seed = float(INSTANCE_ID) * 1.37;
}

void fragment() {
	float t = clamp(UV.y, 0.0, 1.0);
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float flicker = 0.85 + 0.15 * sin(TIME * 37.0 + seed * 5.0) * sin(TIME * 23.0 + seed);
	float diamonds = 0.75 + 0.25 * smoothstep(0.4, 1.0, sin(t * 42.0 - TIME * 3.0 + seed)) * (1.0 - smoothstep(0.0, 0.45, t));
	float body = pow(1.0 - t, 1.6) * smoothstep(0.0, 0.04, t + 0.02);
	float a = body * pow(facing, 1.3) * diamonds * flicker;
	vec3 c = mix(outer_color.rgb, core_color.rgb, clamp(facing * (1.0 - t * 1.4), 0.0, 1.0));
	ALBEDO = c * a * intensity * mix(1.0, 1.7, night);
}
