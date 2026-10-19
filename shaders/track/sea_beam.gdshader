// Facho das luzes coloridas submarinas (SeaCanyon): cone aberto e aditivo saindo dos cristais, na cor
// dos vértices; some ao longo (UV.y = 0 na fonte .. 1 na ponta) e nas bordas do cone (de lado ele
// não tem contorno), com um tremor lento como luz na água. Mais forte à noite (`intensity`, pelo
// período, e o global `night`).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float intensity = 0.5;
global uniform float night;

varying vec3 tint;
varying float k;

void vertex() {
	tint = COLOR.rgb;
	// (some com a distância: aditivo não pega a névoa)
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	k = exp(-length(w - CAMERA_POSITION_WORLD) / 180.0);
}

void fragment() {
	float along = pow(1.0 - clamp(UV.y, 0.0, 1.0), 1.6) * smoothstep(0.0, 0.06, UV.y);
	float edge = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.5);
	float flicker = 0.85 + 0.15 * sin(TIME * 1.7 + UV.x * 12.0 + UV.y * 5.0);
	ALBEDO = tint * along * edge * flicker * intensity * (0.55 + 0.45 * night) * k;
}
