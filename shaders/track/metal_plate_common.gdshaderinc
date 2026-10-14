// Placas de metal escuro presas por parafusos (construções da Sky Aerobase: barreiras, boxes,
// arquibancadas, nave do túnel, plataforma e base aérea). Projeção no espaço do objeto (eixo
// dominante da normal), como building_common:
//   * a cor do vértice vira metal (cinzas e brancos; mais claro quanto mais claro o vértice) ou
//     mantém o tom (cores fortes: faixas, cadeiras, detalhes das equipes), escurecida;
//   * placas de plate_size m com juntas, um leve tom diferente por placa e parafusos nos cantos e
//     no meio dos lados maiores;
//   * relevo (normal) feito da própria forma das placas: chanfro nas bordas descendo até a junta e
//     a cabeça abaulada de cada parafuso; some de longe;
//   * iluminação realista (sem o degrau do toon), pouco reflexiva, e um pouco de sujeira do
//     grime_tex.
// no_outline = true grava rugosidade quase 0 (< 0,02), que o contorno anime (outline_post) não desenha.

uniform sampler2D grime_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 metal_color : source_color = vec3(0.3, 0.315, 0.35);
uniform vec2 plate_size = vec2(3.0, 2.0);
uniform float bevel = 0.07;
uniform float bolt_inset = 0.14;
uniform float bolt_radius = 0.045;
uniform float bump_strength = 1.0;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.22;
uniform bool no_outline = false;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_pos;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Projeção: coordenadas (u, v) e os eixos locais que elas seguem.
vec2 projected_uv(vec3 p, vec3 n, out vec3 au, out vec3 av) {
	vec3 an = abs(n);
	if (an.y >= an.x && an.y >= an.z) {
		au = vec3(1.0, 0.0, 0.0);
		av = vec3(0.0, 0.0, 1.0);
		return p.xz;
	} else if (an.x >= an.z) {
		au = vec3(0.0, 0.0, 1.0);
		av = vec3(0.0, -1.0, 0.0);
		return vec2(p.z, -p.y);
	}
	au = vec3(1.0, 0.0, 0.0);
	av = vec3(0.0, -1.0, 0.0);
	return vec2(p.x, -p.y);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Centro do parafuso mais perto de q (posição na placa, em metros): cantos e meio dos lados maiores.
vec2 nearest_bolt(vec2 q) {
	float bx = q.x < plate_size.x * 0.25 ? bolt_inset : (q.x > plate_size.x * 0.75 ? plate_size.x - bolt_inset : plate_size.x * 0.5);
	float by = q.y < plate_size.y * 0.5 ? bolt_inset : plate_size.y - bolt_inset;
	return vec2(bx, by);
}

// Altura do relevo (0 na junta, 1 no plano da placa, um pouco mais na cabeça do parafuso).
float relief(vec2 uv) {
	vec2 q = fract(uv / plate_size) * plate_size;
	float e = min(min(q.x, plate_size.x - q.x), min(q.y, plate_size.y - q.y));
	float h = smoothstep(0.0, bevel, e);
	float r = length(q - nearest_bolt(q)) / bolt_radius;
	h += 0.6 * max(1.0 - r * r, 0.0);
	return h;
}

void fragment() {
	vec3 au;
	vec3 av;
	vec2 uv = projected_uv(local_pos, local_normal, au, av);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(30.0, 110.0, dist);

	// Cor: cinza/branco → metal; cor forte fica, escurecida
	vec3 v = COLOR.rgb;
	float lum = dot(v, vec3(0.3, 0.59, 0.11));
	float sat = max(v.r, max(v.g, v.b)) - min(v.r, min(v.g, v.b));
	vec3 c = mix(metal_color * (0.6 + 0.8 * lum), v * 0.7, smoothstep(0.18, 0.45, sat));

	vec2 cell = uv / plate_size;
	vec2 q = fract(cell) * plate_size;
	c *= 0.93 + 0.14 * hash(floor(cell));
	// Junta escura e parafuso (cabeça mais clara, aro escuro)
	vec2 g = abs(fract(cell) - 0.5);
	float aa = fwidth(cell.x) * 1.5;
	float seam = smoothstep(0.5 - 0.006 - aa, 0.5 - 0.001, max(g.x, g.y));
	c *= 1.0 - 0.5 * seam * mix(0.4, 1.0, near);
	float r = length(q - nearest_bolt(q));
	float baa = fwidth(r) * 1.2 + 0.002;
	float head = 1.0 - smoothstep(bolt_radius - baa, bolt_radius + baa, r);
	float ring = (1.0 - smoothstep(bolt_radius + 0.012 - baa, bolt_radius + 0.014 + baa, r)) - head;
	c = mix(c, c * 0.55, ring * near);
	c = mix(c, c * 1.25 + metal_color * 0.15, head * near);
	c *= mix(1.0, texture(grime_tex, uv * 0.06 + vec2(0.13, 0.41)).r, grime_strength);
	ALBEDO = c;

	// Relevo das placas (derivada da altura por diferenças finitas, no espaço do objeto)
	float eps = 0.006;
	float h0 = relief(uv);
	float du = (relief(uv + vec2(eps, 0.0)) - h0) / eps;
	float dv = (relief(uv + vec2(0.0, eps)) - h0) / eps;
	float k = bump_strength * 0.012 * near;
	vec3 n = normalize(local_normal);
	vec3 bumped = normalize(n - (au * du + av * dv) * k);
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(bumped, 0.0)).xyz);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	METALLIC = 0.08;
	SPECULAR = no_outline ? 0.18 : 0.32;
	ROUGHNESS = no_outline ? 0.015 : 0.55;
}
