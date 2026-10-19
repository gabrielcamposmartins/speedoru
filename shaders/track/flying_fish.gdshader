// Peixes-voadores do Portão de Poseidon: cada um salta da água num arco ao longo do +Z dele (o
// começo e o fim ficam embaixo d'água, escondidos pelo mar), com as nadadeiras-asas abertas
// tremendo (COLOR.r = peso). INSTANCE_CUSTOM.x = fase, .y = duração do salto.
shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_disabled;

uniform float jump_length = 26.0;
uniform float jump_height = 3.2;
uniform vec3 back_color : source_color = vec3(0.18, 0.36, 0.7);
uniform vec3 belly_color : source_color = vec3(0.9, 0.94, 1.0);

varying float belly;

void vertex() {
	float period = 2.4 + INSTANCE_CUSTOM.y * 2.0;
	float u = fract(TIME / period + INSTANCE_CUSTOM.x);
	// Asas tremendo
	VERTEX.y += sin(TIME * 40.0 + INSTANCE_CUSTOM.x * 30.0) * 0.06 * COLOR.r;
	// Inclina acompanhando o arco (sobe e desce)
	float slope = cos(u * 3.14159) * jump_height * 3.14159 / jump_length;
	float c = cos(slope);
	float s = sin(slope);
	VERTEX = vec3(VERTEX.x, VERTEX.y * c + VERTEX.z * s, -VERTEX.y * s + VERTEX.z * c);
	VERTEX.z += (u - 0.5) * jump_length;
	VERTEX.y += sin(u * 3.14159) * jump_height - 0.8;
	belly = COLOR.g;
}

void fragment() {
	ALBEDO = mix(back_color, belly_color, belly);
	ROUGHNESS = 0.3;
	RIM = 0.5;
	RIM_TINT = 0.5;
}
