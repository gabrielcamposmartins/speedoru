// Público de placeholder: cada instância do MultiMesh é um quad com uma silhueta desenhada no
// fragment (cabeça, tronco, braços e às vezes bandeira). A animação é toda na GPU.
// INSTANCE_CUSTOM: r = fase (0..1), g = tipo (0 sentado, ~0.4 acenando, ~0.7 pulando, 1 bandeira),
//                  b = cor da camisa (índice na paleta), a = tom de pele + cabelo/boné.
// Quad: QuadMesh 0.8 x 1.4 com a base na origem (center_offset y = 0.7).
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

uniform float width = 0.8;
uniform float height = 1.4;
uniform float excitement : hint_range(0.0, 2.0) = 1.0;

const vec3 SHIRTS[12] = vec3[](
	vec3(0.86, 0.10, 0.14), vec3(0.95, 0.95, 0.97), vec3(0.98, 0.78, 0.12), vec3(0.16, 0.42, 0.88),
	vec3(0.12, 0.62, 0.36), vec3(0.95, 0.42, 0.62), vec3(0.20, 0.20, 0.26), vec3(0.96, 0.52, 0.12),
	vec3(0.55, 0.30, 0.82), vec3(0.18, 0.78, 0.86), vec3(0.86, 0.10, 0.14), vec3(0.98, 0.92, 0.80)
);
const vec3 SKINS[4] = vec3[](
	vec3(0.98, 0.84, 0.72), vec3(0.90, 0.70, 0.54), vec3(0.70, 0.48, 0.34), vec3(0.46, 0.30, 0.22)
);
const vec3 HAIRS[4] = vec3[](
	vec3(0.12, 0.10, 0.12), vec3(0.45, 0.28, 0.14), vec3(0.95, 0.80, 0.40), vec3(0.86, 0.10, 0.14)
);

varying flat vec4 data;
varying float lift;

float sd_capsule(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

float sd_round_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void vertex() {
	data = INSTANCE_CUSTOM;
	float speed = 2.0 + data.r * 2.5;
	float t = TIME * speed + data.r * 40.0;
	lift = 0.0;
	if (data.g > 0.55 && data.g < 0.85) {
		lift = max(sin(t * 1.4), 0.0) * 0.16 * excitement;
	} else {
		lift = sin(t * 0.6) * 0.012;
	}
	VERTEX.y += lift;
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * width, (1.0 - UV.y) * height);
	float t = TIME * (2.0 + data.r * 2.5) + data.r * 40.0;
	vec3 shirt = SHIRTS[int(data.b * 11.99)];
	int look = int(data.a * 15.99);
	vec3 skin = SKINS[look % 4];
	vec3 hair = HAIRS[look / 4];

	float sway = sin(t * 0.5) * 0.02;
	vec2 head_c = vec2(sway, 0.80);
	float head = length(p - head_c) - 0.115;
	float body = sd_round_box(p - vec2(sway * 0.5, 0.42), vec2(0.17, 0.25), 0.08);

	// Braços: parados ao lado do corpo, acenando ou segurando bandeira
	float arms = 1e3;
	float flag = 1e3;
	vec2 flag_uv = vec2(0.0);
	vec2 sl = vec2(-0.15 + sway, 0.6);
	vec2 sr = vec2(0.15 + sway, 0.6);
	if (data.g > 0.25 && data.g < 0.55) {
		float a = 0.35 + sin(t * 2.2) * 0.45 * excitement;
		arms = min(sd_capsule(p, sr, sr + vec2(sin(a), cos(a)) * 0.34, 0.045),
			sd_capsule(p, sl, sl + vec2(-sin(a * 0.8 + 0.3), cos(a * 0.8 + 0.3)) * 0.34, 0.045));
	} else if (data.g > 0.55 && data.g < 0.85) {
		float a = 0.25 + sin(t * 1.4) * 0.15;
		arms = min(sd_capsule(p, sr, sr + vec2(sin(a), cos(a)) * 0.34, 0.045),
			sd_capsule(p, sl, sl + vec2(-sin(a), cos(a)) * 0.34, 0.045));
	} else if (data.g >= 0.85) {
		vec2 hand = sr + vec2(0.08, 0.3);
		arms = sd_capsule(p, sr, hand, 0.045);
		float pole = sd_capsule(p, hand - vec2(0.0, 0.05), hand + vec2(0.0, 0.42), 0.012);
		// Bandeira tremulando
		vec2 fp = p - (hand + vec2(0.0, 0.42));
		fp.y += sin(fp.x * 14.0 - TIME * 7.0 + data.r * 20.0) * 0.025 * clamp(fp.x * 6.0, 0.0, 1.0);
		float cloth = sd_round_box(fp - vec2(-0.17, -0.1), vec2(0.17, 0.1), 0.0);
		flag_uv = vec2(fp.x + 0.34, fp.y + 0.2) / vec2(0.34, 0.2);
		flag = min(cloth, 1e3);
		arms = min(arms, pole);
	}

	// Mãos nas pontas dos braços levantados, pescoço, cabelo/boné e cachecol
	int hair_style = int(fract(data.a * 5.0) * 3.99);   // 0 curto, 1 boné, 2 comprido, 3 coque
	int shirt_style = int(fract(data.b * 13.0) * 3.99); // 0 liso, 1 listras, 2 número, 3 cachecol
	float neck = sd_capsule(p, vec2(sway * 0.7, 0.62), head_c, 0.045);
	float cap = 1e3;
	float hair_shape = 1e3;
	if (hair_style == 1) {
		cap = min(sd_round_box(p - head_c - vec2(0.0, 0.07), vec2(0.12, 0.06), 0.05),
			sd_round_box(p - head_c - vec2(0.0, 0.025), vec2(0.17, 0.018), 0.012));
	} else if (hair_style == 2) {
		hair_shape = sd_round_box(p - head_c - vec2(0.0, -0.06), vec2(0.14, 0.15), 0.09);
	} else if (hair_style == 3) {
		hair_shape = length(p - head_c - vec2(0.0, 0.14)) - 0.06;
	}
	float d = min(min(body, head), min(neck, min(cap, hair_shape)));
	vec3 c = shirt;
	vec2 q = p - vec2(sway * 0.5, 0.42);
	if (body < 0.0) {
		if (shirt_style == 1 && abs(fract(q.y * 7.0) - 0.5) < 0.18) c = mix(shirt, vec3(0.97), 0.85);
		if (shirt_style == 2 && length(q - vec2(0.0, 0.06)) < 0.07) c = vec3(0.97);
		// Cachecol (cores da torcida) no pescoço
		if (shirt_style == 3 && q.y > 0.13 && q.y < 0.2) c = data.b > 0.5 ? vec3(0.85, 0.1, 0.14) : vec3(0.1, 0.55, 0.3);
	}
	if (neck < 0.0 && body >= 0.0) c = skin;
	if (head < 0.0 || hair_shape < 0.0) {
		c = skin;
		if (hair_shape < 0.0 && head >= 0.0) c = hair;
		// Cabelo na parte de cima da cabeça
		if (head < 0.0 && hair_style != 1 && p.y > head_c.y + 0.02 + (p.x - head_c.x) * 0.25) c = hair;
		// Olhos
		vec2 eo = p - head_c - vec2(0.0, -0.005);
		if (head < 0.0 && (length(eo - vec2(0.045, 0.0)) < 0.016 || length(eo + vec2(0.045, 0.0)) < 0.016)) {
			c = vec3(0.06, 0.05, 0.1);
		}
		// Bochechas rosadas (anime)
		if (head < 0.0 && length(eo - vec2(0.065, -0.045)) < 0.02) c = mix(c, vec3(1.0, 0.55, 0.6), 0.5);
	}
	if (cap < 0.0) c = shirt * 0.8 + vec3(0.05);
	if (arms < 0.0 && head >= 0.0) {
		c = mix(skin, shirt, step(0.5, fract(data.r * 7.0)));
		d = min(d, arms);
	}
	if (flag < 0.0) {
		// Faixas verticais verde/branco/vermelho ou bandeira na cor da camisa
		vec3 tri = flag_uv.x < 0.333 ? vec3(0.1, 0.55, 0.3) : (flag_uv.x < 0.666 ? vec3(0.96) : vec3(0.85, 0.1, 0.14));
		c = data.b > 0.5 ? tri : shirt;
		d = min(d, flag);
	}
	// Sombreamento cel: um lado da silhueta um pouco mais escuro
	if (p.x < -0.04 && flag >= 0.0) c *= 0.84;
	// Contorno escuro na borda da silhueta (traço de anime)
	float edge = min(min(abs(body), abs(head)), min(min(abs(arms), abs(flag)), min(abs(cap), abs(hair_shape))));
	c = mix(vec3(0.08, 0.06, 0.12), c, smoothstep(0.012, 0.022, edge) * 0.65 + 0.35 * step(0.0, -d));
	ALBEDO = c;
	ALPHA = d < 0.0 ? 1.0 : 0.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// Rugosidade 0 = sem contorno do pós-processamento (a silhueta já tem traço próprio)
	ROUGHNESS = 0.0;
}
