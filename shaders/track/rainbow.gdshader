// Arco-íris sobre o Portão de Poseidon (trecho emerso): faixa em arco, aditiva, com as cores do
// espectro (vermelho por fora, violeta por dentro), sumindo nos pés e de perto; só de dia
// (intensity, do SeaWorld/PoseidonGate conforme o período). UV.x = 0..1 ao longo do arco,
// UV.y = 0 (borda de dentro) .. 1 (de fora).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float intensity = 0.3;

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	float v = UV.y;
	vec3 col = hue((1.0 - v) * 0.78);
	float band = sin(v * 3.14159);
	float feet = smoothstep(0.0, 0.18, UV.x) * (1.0 - smoothstep(0.82, 1.0, UV.x));
	ALBEDO = col * band * feet * intensity;
}
