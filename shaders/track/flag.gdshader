// Bandeiras e bandeirolas tremulando. UV.x = 0 no mastro/corda e 1 na ponta solta:
// a onda empurra os vértices ao longo da normal, mais forte na ponta.
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

uniform float amplitude = 0.22;
uniform float speed = 6.0;
uniform float wavelength = 7.0;

varying float wave;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = UV.x;
	wave = sin(TIME * speed - t * wavelength + (w.x + w.z) * 0.21 + w.y * 0.5);
	float flutter = sin(TIME * speed * 2.3 + t * 13.0 + w.x * 0.7) * 0.25;
	VERTEX += NORMAL * (wave + flutter) * amplitude * t;
}

void fragment() {
	// Dobras: faixas mais claras/escuras acompanhando a onda
	ALBEDO = COLOR.rgb * (0.9 + 0.12 * wave * UV.x);
	// Rugosidade 0 = sem contorno anime (outline_post.gdshader)
	ROUGHNESS = 0.0;
	BACKLIGHT = COLOR.rgb * 0.25;
}
