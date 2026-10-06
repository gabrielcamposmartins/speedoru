// Piso da pista (asfalto, zebras, cascalho, faixas pintadas): cor de vértice + granulação
// procedural em coordenadas de mundo (some com a distância para não serrilhar).
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

uniform float grain_scale = 6.0;
uniform float grain_strength : hint_range(0.0, 0.5) = 0.06;
uniform float patch_scale = 0.035;
uniform float patch_strength : hint_range(0.0, 0.5) = 0.05;
// Pedrinhas (cascalho): pontos claros e escuros maiores.
uniform float pebble_strength : hint_range(0.0, 1.0) = 0.0;
// Normal map projetado de cima (coordenadas de mundo); normal_scale = repetições por metro.
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_strength = 0.0;
uniform float normal_scale = 0.5;
uniform float normal_fade_distance = 60.0;

varying vec3 world_pos;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Base tangente alinhada ao mundo (u = X, v = Z) para o normal map projetado de cima
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = normalize(cross(TANGENT, NORMAL));
}

void fragment() {
	vec3 c = COLOR.rgb;
	vec2 gp = world_pos.xz * grain_scale;
	float fade = clamp(1.0 - length(fwidth(gp)) * 0.6, 0.0, 1.0);
	// Granulação suave (duas oitavas de ruído) em vez de blocos
	float grain = (value_noise(gp) * 0.6 + value_noise(gp * 2.7 + 13.0) * 0.4 - 0.5) * 2.0 * grain_strength * fade;
	float patches = (value_noise(world_pos.xz * patch_scale) - 0.5) * 2.0 * patch_strength;
	c *= 1.0 + grain + patches;
	if (pebble_strength > 0.0) {
		vec2 pp = world_pos.xz * 3.0;
		vec2 cell = floor(pp);
		vec2 f = fract(pp) - 0.5 - (vec2(hash(cell), hash(cell + 7.0)) - 0.5) * 0.5;
		float pebble = smoothstep(0.22, 0.12, length(f)) * clamp(1.0 - length(fwidth(pp)) * 0.8, 0.0, 1.0);
		c *= 1.0 + (hash(cell + 3.0) - 0.45) * pebble * pebble_strength;
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	if (normal_strength > 0.0) {
		NORMAL_MAP = texture(normal_tex, world_pos.xz * normal_scale).rgb;
		float dist = length(world_pos - CAMERA_POSITION_WORLD);
		NORMAL_MAP_DEPTH = normal_strength * (1.0 - smoothstep(normal_fade_distance * 0.5, normal_fade_distance, dist));
	}
}
