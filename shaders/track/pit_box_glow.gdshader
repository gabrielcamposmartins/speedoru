// Contorno do box do jogador: borda luminosa discreta no chão e um véu baixo que some para cima
// (UV.y: 0 no chão, 1 no topo do véu). Pulsa devagar.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 glow_color : source_color = vec4(0.21, 0.94, 0.84, 0.85);

void fragment() {
	float pulse = 0.72 + 0.28 * sin(TIME * 3.2);
	float fade = pow(1.0 - clamp(UV.y, 0.0, 1.0), 2.2);
	ALBEDO = glow_color.rgb;
	ALPHA = glow_color.a * fade * pulse;
}
