// Aro da roda polido, estilo anime: cor da pintura + reflexo do ambiente (céu claro em cima,
// chão escuro embaixo), faixa de brilho nítida e borda (fresnel). O reflexo vai na emissão, então
// aparece mesmo com aro preto e na sombra.
shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform vec4 base_color : source_color = vec4(0.1, 0.1, 0.13, 1.0);
uniform vec4 sky_color : source_color = vec4(0.78, 0.88, 1.0, 1.0);
uniform vec4 ground_color : source_color = vec4(0.16, 0.2, 0.14, 1.0);
uniform float reflectivity : hint_range(0.0, 1.0) = 0.55;
// Acabamento (CarLivery.apply_rim_finish)
uniform float metal : hint_range(0.0, 1.0) = 0.4;
uniform float rough : hint_range(0.0, 1.0) = 0.2;
uniform float streak_strength = 0.8;
// Brilho do boost (CarEffects)
uniform vec4 glow_color : source_color = vec4(0.2, 0.95, 1.0, 1.0);
uniform float glow = 0.0;

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	float horizon = smoothstep(-0.05, 0.25, r.y);
	vec3 env = mix(ground_color.rgb, sky_color.rgb, horizon);
	// Faixa de brilho (horizonte refletido) e borda clara
	float streak = smoothstep(0.02, 0.06, r.y) * (1.0 - smoothstep(0.1, 0.16, r.y));
	float fresnel = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0);
	vec3 refl = env * (0.35 + 0.65 * fresnel) + vec3(1.0) * streak * streak_strength;
	ALBEDO = base_color.rgb * (1.0 - reflectivity * 0.5);
	EMISSION = refl * reflectivity * 0.55 + glow_color.rgb * glow * 2.5;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = 0.8;
	RIM = 0.4;
	RIM_TINT = 0.8;
}
