// Vidro transparente da pista no fundo do mar (barreiras e o túnel de cristal): quase invisível de
// frente e mais opaco e brilhante de lado (fresnel ciano), com faixas de reflexo diagonais que
// andam devagar e as bordas de cada painel um pouco mais visíveis. UV.x = metros ao longo da peça,
// UV.y = 0..1 na altura (bordas do painel). Não grava profundidade (o contorno anime não o vê).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.55, 0.92, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.07;
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.42;
uniform float rim_power = 2.6;
uniform float glow = 0.35;
// Comprimento (m) de cada painel ao longo da peça (bordas mais visíveis); 0 = sem painéis.
uniform float panel_length = 8.0;
uniform float streak_strength : hint_range(0.0, 1.0) = 0.12;
global uniform float night;

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	float f = pow(1.0 - facing, rim_power);
	// Faixas de reflexo diagonais (anime)
	float diag = UV.x * 0.35 + UV.y * 1.6 - TIME * 0.05;
	float streak = smoothstep(0.82, 0.9, fract(diag)) * (1.0 - smoothstep(0.93, 1.0, fract(diag)));
	float edge = 0.0;
	if (panel_length > 0.0) {
		float u = fract(UV.x / panel_length);
		edge = 1.0 - smoothstep(0.0, 0.015, min(u, 1.0 - u));
	}
	edge = max(edge, 1.0 - smoothstep(0.0, 0.035, min(UV.y, 1.0 - UV.y)));
	ALBEDO = tint * 0.55;
	ALPHA = clamp(base_alpha + rim_alpha * f + streak * streak_strength + edge * 0.25, 0.0, 0.8);
	EMISSION = tint * (glow * (f + edge * 0.6) * mix(1.0, 2.2, night) + streak * streak_strength);
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
}
