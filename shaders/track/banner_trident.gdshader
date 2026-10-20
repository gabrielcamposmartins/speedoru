// Estandarte de Atlântida (pista no fundo do mar): pano azul-marinho com borda dourada, ponta em V
// embaixo e o tridente de Poseidon dourado no meio (desenhado aqui, sem textura), balançando devagar
// com a corrente. UV.x = 0..1 na largura, UV.y = 0 (em cima, preso) .. 1 (ponta). `aspect` =
// altura / largura do pano (para o tridente não esticar).
shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_disabled;

uniform vec3 cloth : source_color = vec3(0.07, 0.13, 0.38);
uniform vec3 gold : source_color = vec3(0.98, 0.78, 0.26);
uniform float aspect = 2.6;
uniform float sway = 0.22;
global uniform float night;

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Ponta de lança (triângulo para cima) com a base em y = 0
float sd_tip(vec2 p, float w, float h) {
	p.x = abs(p.x);
	float edge = (p.x * h + p.y * w - w * h) / length(vec2(h, w));
	return max(max(edge, -p.y), -10.0);
}

void vertex() {
	float w = UV.y;
	VERTEX += NORMAL * sin(TIME * 1.1 + VERTEX.x * 0.7 + VERTEX.z * 0.7 + UV.y * 2.6) * sway * w;
}

void fragment() {
	// Ponta em V embaixo
	float v = 0.84 + 0.16 * (1.0 - abs(UV.x * 2.0 - 1.0));
	if (UV.y > v) {
		discard;
	}
	// Coordenadas em "larguras" (x: -0,5..0,5; y: para cima)
	vec2 q = vec2(UV.x - 0.5, (0.42 - UV.y) * aspect);
	float d = sd_box(q - vec2(0.0, -0.35), vec2(0.03, 0.55));
	d = min(d, sd_box(q - vec2(0.0, 0.22), vec2(0.2, 0.03)));
	for (int k = -1; k <= 1; k++) {
		float x = float(k) * 0.19;
		d = min(d, sd_box(q - vec2(x, 0.4), vec2(0.028, 0.18)));
		d = min(d, sd_tip(q - vec2(x, 0.56), 0.065, 0.16));
	}
	float aa = fwidth(q.x) * 1.5;
	float trident = 1.0 - smoothstep(0.0, aa, d);
	float border = 1.0 - smoothstep(0.0, fwidth(UV.x) * 1.5, min(min(UV.x, 1.0 - UV.x) - 0.06, UV.y - 0.035));
	border = max(border, 1.0 - smoothstep(0.0, 0.012, v - UV.y - 0.035));
	vec3 col = mix(cloth, gold, max(trident, border));
	ALBEDO = col;
	EMISSION = gold * max(trident, border) * (0.15 + 0.6 * night);
	ROUGHNESS = 0.0;
	// (sem reflexo do céu: com rugosidade 0 ele virava um espelho)
	SPECULAR = 0.0;
}
