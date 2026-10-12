shader_type spatial;
// Arte dos letreiros de Las Vegas (atlas desenhado por NeonArt): sem luz, com o halo de neon do
// próprio desenho (alfa pré-multiplicado). De dia acesa e contida; à noite passa de 1 e o glow do
// ambiente espalha. Animação por quadros (letreiros de LED, o caubói acenando): `frames` quadros
// lado a lado no atlas, `frame_step` = deslocamento de UV de um para o outro. Alfa da cor de
// vértice: 1 = neon; 0 = painel pintado iluminado por dentro (a placa "Welcome"), que à noite
// clareia bem menos.
render_mode unshaded, cull_back, blend_premul_alpha, depth_prepass_alpha;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float day_level = 1.0;
uniform float night_level = 3.0;
uniform float lit_night_level = 1.15;
instance uniform vec2 frame_step = vec2(0.0);
instance uniform float frames = 1.0;
instance uniform float fps = 1.0;

void fragment() {
	vec2 uv = UV;
	if (frames > 1.5) {
		uv += frame_step * floor(mod(TIME * fps, frames));
	}
	vec4 t = texture(atlas, uv);
	float lvl = mix(day_level, mix(lit_night_level, night_level, COLOR.a), night);
	ALBEDO = t.rgb * COLOR.rgb * lvl;
	ALPHA = t.a;
}
