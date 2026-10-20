// Bronze de Atlântida (nervuras do tubo de vidro da pista no fundo do mar, medalhões, anéis): a cor
// do vértice é o metal (bronze, ouro), com a pátina verde-azulada do mar em manchas (mais nas faces
// de cima e nos cantos, menos no ouro), frisos gravados ao longo da peça, brilho de metal na borda
// (rim e um reflexo na direção do olhar, sem especular: o toon dava degraus) e a cáustica da água
// (caustics.gdshaderinc). Rugosidade 0: sem o contorno anime.
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

#include "res://shaders/track/caustics.gdshaderinc"

uniform vec3 patina_color : source_color = vec3(0.2, 0.5, 0.43);
uniform float patina_amount : hint_range(0.0, 1.0) = 0.38;
// Frisos gravados: a cada tantos metros na coordenada local y (0 = sem)
uniform float groove_spacing = 0.9;
uniform float shine = 0.5;

varying vec3 wpos;
varying vec3 lpos;

// (hash sem seno: com coordenadas de mundo grandes o fract(sin(...)) perdia a precisão na placa de
// vídeo e as células vizinhas saíam quase iguais, em faixas retas)
float bronze_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float bronze_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(bronze_hash(i), bronze_hash(i + vec3(1.0, 0.0, 0.0)), u.x);
	float b = mix(bronze_hash(i + vec3(0.0, 1.0, 0.0)), bronze_hash(i + vec3(1.0, 1.0, 0.0)), u.x);
	float c = mix(bronze_hash(i + vec3(0.0, 0.0, 1.0)), bronze_hash(i + vec3(1.0, 0.0, 1.0)), u.x);
	float d = mix(bronze_hash(i + vec3(0.0, 1.0, 1.0)), bronze_hash(i + vec3(1.0, 1.0, 1.0)), u.x);
	return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lpos = VERTEX;
}

void fragment() {
	vec3 metal = COLOR.rgb;
	// Ouro (amarelo saturado) quase sem pátina
	float gold = smoothstep(0.55, 0.75, metal.r) * smoothstep(0.45, 0.6, metal.g);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float n = bronze_noise(wpos * 0.7) * 0.6 + bronze_noise(wpos * 2.3 + 3.1) * 0.3 + bronze_noise(wpos * 7.1) * 0.1;
	float up = smoothstep(0.1, 0.8, wn.y);
	float pat = smoothstep(0.42, 0.72, n + up * 0.25) * patina_amount * (1.0 - gold * 0.85);
	vec3 col = mix(metal * (0.85 + 0.3 * bronze_noise(wpos * 4.0)), patina_color * (0.8 + 0.4 * n), pat);
	// Frisos gravados (só de perto)
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	if (groove_spacing > 0.0) {
		float g = abs(fract(wpos.y / groove_spacing) - 0.5);
		float aa = fwidth(wpos.y / groove_spacing) * 1.5;
		col *= 1.0 - 0.25 * (1.0 - smoothstep(0.03, 0.06 + aa, g)) * (1.0 - smoothstep(30.0, 70.0, dist));
	}
	ALBEDO = col;
	// Brilho de metal: borda e um reflexo largo olhando de frente (menos onde há pátina)
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 gleam = metal * (pow(1.0 - facing, 3.0) * 0.6 + pow(facing, 6.0) * 0.25) * shine * (1.0 - pat);
	EMISSION = gleam + sea_caustic_light(wpos, wn, dist, TIME) * col;
	ROUGHNESS = 0.0;
	// (sem reflexo do céu: com rugosidade 0 ele virava um espelho)
	SPECULAR = 0.0;
	RIM = 0.4 * (1.0 - pat);
	RIM_TINT = 0.8;
}
