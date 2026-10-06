// Pessoas em pé/andando (MultiMesh): pedestres do paddock e corredores, e mecânicos das equipes.
// Billboard vertical (sempre de frente para a câmera), silhueta desenhada no fragment com
// pernas, braços, mãos, sapatos, cabeça com olhos e cabelo/boné, roupa com detalhes e
// sombreamento cel (lado da luz mais claro). Tudo animado na GPU.
// INSTANCE_CUSTOM: r = fase (0..1), g = comprimento do caminho / 100 m (0 = parado),
//                  g = -1 mecânico parado, -2 mecânico trabalhando (cor da equipe = COLOR),
//                  b = roupa (paleta), a = pele + cabelo/boné.
// Quad: QuadMesh 0.8 x 1.9 com a base na origem (center_offset y = 0.95).
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

uniform float width = 0.8;
uniform float height = 1.9;
global uniform vec3 sun_dir_world;

const vec3 SHIRTS[12] = vec3[](
	vec3(0.86, 0.10, 0.14), vec3(0.95, 0.95, 0.97), vec3(0.98, 0.78, 0.12), vec3(0.16, 0.42, 0.88),
	vec3(0.12, 0.62, 0.36), vec3(0.95, 0.42, 0.62), vec3(0.20, 0.20, 0.26), vec3(0.96, 0.52, 0.12),
	vec3(0.55, 0.30, 0.82), vec3(0.18, 0.78, 0.86), vec3(0.86, 0.10, 0.14), vec3(0.98, 0.92, 0.80)
);
const vec3 PANTS[4] = vec3[](vec3(0.18, 0.22, 0.38), vec3(0.15, 0.15, 0.17), vec3(0.62, 0.55, 0.42), vec3(0.3, 0.32, 0.36));
const vec3 SKINS[4] = vec3[](
	vec3(0.98, 0.84, 0.72), vec3(0.90, 0.70, 0.54), vec3(0.70, 0.48, 0.34), vec3(0.46, 0.30, 0.22)
);
const vec3 HAIRS[4] = vec3[](
	vec3(0.12, 0.10, 0.12), vec3(0.45, 0.28, 0.14), vec3(0.95, 0.80, 0.40), vec3(0.86, 0.10, 0.14)
);

varying flat vec4 data;
varying flat vec3 team;
varying float stride;
varying float mirror;
varying float light_side;

void vertex() {
	data = INSTANCE_CUSTOM;
	team = COLOR.rgb;
	float len = max(data.g, 0.0) * 100.0;
	float speed = 1.0 + data.r * 0.7;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 dir = normalize(MODEL_MATRIX[2].xyz);
	float scale = length(MODEL_MATRIX[1].xyz);
	float moving = 0.0;
	stride = 0.0;
	if (len > 0.1) {
		// Vai e volta: onda triangular ao longo do segmento
		float t = TIME * speed / len + data.r * 2.0;
		float tri = abs(fract(t * 0.5) * 2.0 - 1.0);
		origin += dir * (tri - 0.5) * len;
		moving = fract(t * 0.5) < 0.5 ? 1.0 : -1.0;
		stride = TIME * speed * 1.9 + data.r * 30.0;
	}
	// Billboard vertical para a câmera
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	to_cam.y = 0.0;
	to_cam = normalize(to_cam + vec3(1e-4, 0.0, 0.0));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	// Desenho virado para o lado em que está andando (na tela)
	mirror = moving == 0.0 ? 1.0 : sign(dot(dir * moving, right) + 1e-4);
	float bob = abs(sin(stride)) * 0.04 * abs(moving);
	vec3 world = origin + right * VERTEX.x * scale + vec3(0.0, (VERTEX.y + bob) * scale, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	NORMAL = (VIEW_MATRIX * vec4(to_cam, 0.0)).xyz;
	// Lado da silhueta voltado para o sol (sombreamento cel desenhado)
	light_side = sign(dot(right, sun_dir_world) + 1e-4);
}

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

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * width * mirror, (1.0 - UV.y) * height);
	bool crew = data.g < -0.5;
	bool working = data.g < -1.5;
	float t = TIME * (1.5 + data.r) + data.r * 30.0;
	int look = int(data.a * 15.99);
	vec3 skin = SKINS[look % 4];
	vec3 hair = HAIRS[look / 4];
	vec3 shirt = crew ? team : SHIRTS[int(data.b * 11.99)];
	vec3 pants = crew ? team * 0.75 : PANTS[int(fract(data.b * 7.0) * 3.99)];
	int style = int(fract(data.b * 13.0) * 3.99);   // 0 liso, 1 listra, 2 número, 3 jaqueta aberta
	int hair_style = int(fract(data.a * 5.0) * 3.99); // 0 curto, 1 boné, 2 comprido, 3 rabo de cavalo

	float swing = sin(stride) * 0.35;
	float work = working ? sin(t * 9.0) : 0.0;
	float crouch = working ? 0.12 + 0.05 * sin(t * 3.0) : 0.0;
	vec2 hip = vec2(0.0, 0.88 - crouch);
	vec2 k1 = hip + vec2(sin(swing), -cos(swing)) * 0.42 + vec2(crouch * 0.6, 0.0);
	vec2 k2 = hip + vec2(sin(-swing), -cos(-swing)) * 0.42 + vec2(crouch * 0.6, 0.0);
	vec2 f1 = vec2(hip.x + sin(swing) * 0.8, 0.06);
	vec2 f2 = vec2(hip.x + sin(-swing) * 0.8, 0.06);
	float leg1 = min(sd_capsule(p, hip, k1, 0.075), sd_capsule(p, k1, f1, 0.065));
	float leg2 = min(sd_capsule(p, hip, k2, 0.075), sd_capsule(p, k2, f2, 0.065));
	float shoe1 = sd_round_box(p - f1 - vec2(0.05, -0.02), vec2(0.1, 0.045), 0.04);
	float shoe2 = sd_round_box(p - f2 - vec2(0.05, -0.02), vec2(0.1, 0.045), 0.04);
	vec2 chest = vec2(0.0, 1.18 - crouch);
	float torso = sd_round_box(p - chest, vec2(0.18, 0.33), 0.1);
	vec2 sh = vec2(0.0, 1.43 - crouch);
	float idle = data.g == 0.0 ? sin(TIME * 2.0 + data.r * 20.0) * 0.4 + 0.5 : 0.0;
	float a1 = -swing * 0.8 + idle * 2.0 + (working ? 1.3 + work * 0.35 : 0.0);
	float a2 = swing * 0.8 + (working ? 1.0 - work * 0.35 : 0.0);
	vec2 e1 = sh + vec2(sin(a1), -cos(a1)) * 0.3;
	vec2 e2 = sh + vec2(sin(a2), -cos(a2)) * 0.3;
	vec2 h1 = e1 + vec2(sin(a1 * 1.2), -cos(a1 * 1.2)) * 0.28;
	vec2 h2 = e2 + vec2(sin(a2 * 1.2), -cos(a2 * 1.2)) * 0.28;
	float arm1 = min(sd_capsule(p, sh, e1, 0.058), sd_capsule(p, e1, h1, 0.052));
	float arm2 = min(sd_capsule(p, sh, e2, 0.058), sd_capsule(p, e2, h2, 0.052));
	float hand1 = length(p - h1) - 0.06;
	float hand2 = length(p - h2) - 0.06;
	vec2 head_c = vec2(0.03, 1.69 - crouch);
	float head = length(p - head_c) - 0.135;
	float neck = sd_capsule(p, sh, head_c, 0.05);
	// Capacete do mecânico / boné com aba
	float cap = 1e3;
	if (crew) {
		cap = length(p - head_c - vec2(0.0, 0.02)) - 0.16;
	} else if (hair_style == 1) {
		cap = min(sd_round_box(p - head_c - vec2(0.0, 0.08), vec2(0.14, 0.07), 0.06),
			sd_round_box(p - head_c - vec2(0.15, 0.04), vec2(0.08, 0.02), 0.015));
	}
	float hair_shape = 1e3;
	if (!crew && hair_style == 2) {
		hair_shape = sd_round_box(p - head_c - vec2(-0.02, -0.05), vec2(0.15, 0.17), 0.1);
	} else if (!crew && hair_style == 3) {
		hair_shape = sd_capsule(p, head_c + vec2(-0.12, 0.05), head_c + vec2(-0.2, -0.12), 0.05);
	}

	float body = min(min(torso, neck), min(arm1, arm2));
	float legs = min(min(leg1, leg2), min(shoe1, shoe2));
	float d = min(min(body, legs), min(min(head, cap), min(min(hand1, hand2), hair_shape)));
	vec3 c = shirt;
	if (legs < 0.0 && torso >= 0.0) {
		c = pants;
		if (min(shoe1, shoe2) < 0.0) c = crew ? vec3(0.1) : vec3(0.95, 0.95, 0.95) * (look % 2 == 0 ? 1.0 : 0.15);
	}
	if (torso < 0.0 || min(arm1, arm2) < 0.0) {
		c = shirt;
		vec2 q = p - chest;
		if (crew) {
			// Macacão: faixa branca no peito e logo
			if (abs(q.y - 0.12) < 0.035) c = vec3(0.95);
			if (length(q - vec2(0.07, 0.2)) < 0.04) c = vec3(1.0, 0.85, 0.2);
		} else if (style == 1 && abs(fract(q.y * 6.0) - 0.5) < 0.18) {
			c = mix(shirt, vec3(0.97), 0.85);
		} else if (style == 2 && length(q - vec2(0.0, 0.08)) < 0.08) {
			c = vec3(0.97);
		} else if (style == 3 && abs(q.x) < 0.05 && torso < 0.0) {
			c = vec3(0.92);
		}
	}
	if (min(hand1, hand2) < 0.0) c = crew ? vec3(0.08) : skin;
	if (neck < 0.0 && torso >= 0.0) c = skin;
	if (head < 0.0 || hair_shape < 0.0) {
		c = skin;
		if (hair_shape < 0.0 && head >= 0.0) c = hair;
		if (head < 0.0 && p.y > head_c.y + 0.03 - p.x * 0.3 && hair_style != 1) c = hair;
		// Olhos (pontinhos) na metade da frente do rosto
		vec2 eye = p - head_c - vec2(0.07, 0.0);
		if (head < 0.0 && length(eye) < 0.018) c = vec3(0.06, 0.05, 0.1);
	}
	if (cap < 0.0) {
		c = crew ? team * 1.1 : shirt * 0.85;
		// Viseira escura do capacete
		if (crew && p.x > head_c.x + 0.02 && abs(p.y - head_c.y) < 0.05) c = vec3(0.08, 0.1, 0.16);
	}
	// Sombreamento cel: metade da silhueta longe do sol mais escura
	c *= (p.x * light_side * mirror) > 0.02 ? 1.0 : 0.82;
	float edge = min(min(abs(body), abs(legs)), min(abs(head), min(abs(cap), abs(min(hand1, hand2)))));
	c = mix(vec3(0.08, 0.06, 0.12), c, smoothstep(0.012, 0.024, edge) * 0.65 + 0.35);
	ALBEDO = c;
	ALPHA = d < 0.0 ? 1.0 : 0.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// Rugosidade 0 = sem o contorno do pós-processamento (a silhueta já tem traço próprio)
	ROUGHNESS = 0.0;
}
