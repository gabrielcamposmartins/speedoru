// Nuvens 3D fofas (estilo Mario Kart): toon com lado iluminado branco, sombra azulada e
// borda clara. Base achatada vem da malha (SceneryAnimator move as nuvens com o vento).
shader_type spatial;
render_mode diffuse_toon, specular_disabled, shadows_disabled;

uniform vec4 lit_color : source_color = vec4(0.9, 0.91, 0.93, 1.0);
uniform vec4 shade_color : source_color = vec4(0.72, 0.78, 0.96, 1.0);

varying float up;
global uniform float night;

void vertex() {
	up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

void fragment() {
	// Embaixo levemente azulada mesmo no sol; o toon cuida da sombra do lado oposto ao sol
	ALBEDO = mix(shade_color.rgb, lit_color.rgb, smoothstep(-0.6, 0.3, up));
	ALBEDO *= mix(1.0, 0.18, night);
	EMISSION = shade_color.rgb * 0.08 * (1.0 - night);
	ROUGHNESS = 1.0;
	RIM = 0.4;
	RIM_TINT = 1.0;
}
