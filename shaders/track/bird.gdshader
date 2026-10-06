// Pássaros (MultiMesh por bando): asas batendo (COLOR.r = quanto o vértice é ponta de asa),
// planando às vezes, e cada pássaro oscilando em volta do lugar no bando.
// INSTANCE_CUSTOM: r = fase, g = frequência das batidas, b = tom (0 escuro, 1 claro/gaivota).
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

uniform vec4 dark_color : source_color = vec4(0.16, 0.15, 0.2, 1.0);
uniform vec4 light_color : source_color = vec4(0.95, 0.95, 0.98, 1.0);

varying float tone;

void vertex() {
	float ph = INSTANCE_CUSTOM.r * 6.2831;
	float freq = 6.0 + INSTANCE_CUSTOM.g * 6.0;
	// Planar: alguns segundos sem bater as asas
	float glide = smoothstep(0.55, 0.75, sin(TIME * 0.4 + ph * 3.0));
	float flap = sin(TIME * freq + ph) * (1.0 - glide) + 0.15 * glide;
	VERTEX.y += flap * COLOR.r * 0.45;
	// Pequeno deslocamento em volta da posição no bando
	VERTEX += vec3(sin(TIME * 0.7 + ph), sin(TIME * 0.9 + ph * 1.7) * 0.5, cos(TIME * 0.6 + ph * 0.8)) * 1.6
		/ max(length(MODEL_MATRIX[0].xyz), 0.01);
	tone = INSTANCE_CUSTOM.b;
}

void fragment() {
	vec3 c = mix(dark_color.rgb, light_color.rgb, tone);
	// Pontas das asas mais escuras
	c *= mix(1.0, 0.55, COLOR.r * tone);
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
