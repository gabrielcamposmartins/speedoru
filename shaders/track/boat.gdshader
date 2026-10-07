// Barcos do porto (MultiMesh): balanço na água por instância e cor do casco por instância.
// INSTANCE_CUSTOM = (cor do casco rgb, amplitude do balanço). COLOR.a < 0.5 marca o casco;
// o resto usa a cor de vértice. O barco aponta para +X (proa) no espaço local.
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

varying vec3 hull_color;
varying float hull;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = dot(origin.xz, vec2(0.071, 0.113));
	float amp = INSTANCE_CUSTOM.a;
	float roll = sin(TIME * 0.83 + phase) * amp * 0.09;
	float pitch = sin(TIME * 0.61 + phase * 1.7) * amp * 0.035;
	// Rolagem em volta do eixo da proa (X) e arfagem em volta do eixo transversal (Z)
	vec3 v = VERTEX;
	v = vec3(v.x, v.y * cos(roll) - v.z * sin(roll), v.y * sin(roll) + v.z * cos(roll));
	v = vec3(v.x * cos(pitch) - v.y * sin(pitch), v.x * sin(pitch) + v.y * cos(pitch), v.z);
	v.y += sin(TIME * 1.1 + phase * 2.3) * amp * 0.12;
	VERTEX = v;
	vec3 n = NORMAL;
	n = vec3(n.x, n.y * cos(roll) - n.z * sin(roll), n.y * sin(roll) + n.z * cos(roll));
	NORMAL = n;
	hull_color = INSTANCE_CUSTOM.rgb;
	hull = 1.0 - step(0.5, COLOR.a);
}

void fragment() {
	ALBEDO = mix(COLOR.rgb, hull_color, hull);
	ROUGHNESS = 0.7;
	RIM = 0.2;
	RIM_TINT = 0.5;
}
