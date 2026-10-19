// Peixinhos dos cardumes (SeaLife): corpo em losango e cauda; a cauda abana (COLOR.r = peso) e cada
// peixe oscila um pouco em volta do lugar dele no cardume. INSTANCE_CUSTOM: x, y = fase; z = cor
// (0 amarelo, 0,33 azul com listra, 0,66 prateado, 1 laranja). Toon com ventre claro.
shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_disabled;

varying vec3 tint;
varying float belly;

void vertex() {
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float t = TIME * (7.0 + INSTANCE_CUSTOM.y * 4.0) + ph;
	VERTEX.x += sin(t) * 0.09 * COLOR.r;
	// Cada peixe vai e volta um pouco no cardume
	VERTEX += vec3(sin(TIME * 0.7 + ph) * 0.5, sin(TIME * 0.9 + ph * 1.3) * 0.3, cos(TIME * 0.6 + ph) * 0.5);
	float c = INSTANCE_CUSTOM.z;
	tint = c < 0.25 ? vec3(1.0, 0.82, 0.12) : (c < 0.5 ? vec3(0.15, 0.45, 0.95) : (c < 0.8 ? vec3(0.75, 0.82, 0.9) : vec3(1.0, 0.5, 0.15)));
	belly = COLOR.g;
}

void fragment() {
	vec3 col = mix(tint, vec3(0.95, 0.96, 0.98), belly * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.4;
	RIM = 0.4;
	RIM_TINT = 0.5;
}
