// Vidro estilo anime: azul com reflexo do céu (fresnel), duas faixas diagonais de brilho e um
// pouco de sujeira. Opaco (os interiores não são modelados). A cor de vértice tinge o vidro.
shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform vec4 tint : source_color = vec4(0.42, 0.62, 0.86, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.82, 0.92, 1.0, 1.0);
uniform sampler2D grime_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float streak_size = 3.5;
uniform bool no_outline = false;
// Janelas acesas à noite (luz quente vinda de dentro)
uniform float night_glow = 1.0;
global uniform float night;

varying vec3 local_pos;
varying vec3 world_normal;

void vertex() {
	local_pos = VERTEX;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float fresnel = pow(1.0 - clamp(dot(world_normal, view_dir), 0.0, 1.0), 3.0);
	vec3 c = COLOR.rgb * tint.rgb;
	c = mix(c, sky_tint.rgb, 0.25 + 0.6 * fresnel);
	// Faixas diagonais de reflexo (clássico do anime)
	float diag = (local_pos.x + local_pos.z) * 0.7 + local_pos.y;
	float f = fract(diag / streak_size);
	float streak = smoothstep(0.0, 0.03, f) * (1.0 - smoothstep(0.09, 0.12, f));
	streak += (smoothstep(0.17, 0.19, f) * (1.0 - smoothstep(0.21, 0.23, f))) * 0.6;
	c = mix(c, vec3(1.0), streak * 0.55);
	vec2 uv = abs(world_normal.x) > abs(world_normal.z) ? local_pos.zy : local_pos.xy;
	c *= mix(1.0, texture(grime_tex, uv * 0.09).r, 0.35);
	ALBEDO = c;
	float lit = step(0.35, fract(sin(dot(floor(local_pos.xz * 0.3 + local_pos.y * 0.5), vec2(12.9, 78.2))) * 43758.5));
	EMISSION = vec3(1.0, 0.78, 0.45) * night * night_glow * (0.6 + 1.4 * lit);
	METALLIC = 0.35;
	ROUGHNESS = no_outline ? 0.0 : 0.12;
	SPECULAR = 0.8;
	RIM = 0.4;
}
