// Balões de festa da Rainbow Raceway (cachos de corações e bolinhas presos nas barreiras): cor da
// instância com brilho de látex (reflexo e borda), balançando com o vento — o nó do cordão (y = 0 da
// malha) fica parado e o balanço cresce com a altura (`height` = altura do cacho na malha).
shader_type spatial;
render_mode diffuse_toon, specular_toon, cull_disabled;

uniform float height = 5.0;
uniform float sway = 0.5;
global uniform float night;

varying vec3 tint;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float h = fract(sin(dot(center, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float w = clamp(VERTEX.y / height, 0.0, 1.0);
	w *= w;
	float t = TIME * (0.9 + 0.4 * h) + h * 6.2831;
	VERTEX.x += sin(t) * sway * w;
	VERTEX.z += cos(t * 0.8) * sway * 0.6 * w;
	VERTEX.y += sin(t * 1.7) * 0.12 * w;
	tint = COLOR.rgb;
}

void fragment() {
	ALBEDO = tint;
	SPECULAR = 0.7;
	ROUGHNESS = 0.18;
	RIM = 0.5;
	RIM_TINT = 0.6;
	EMISSION = tint * (0.06 + 0.2 * night);
}
