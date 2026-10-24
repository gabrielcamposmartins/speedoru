// Construções da Rainbow Raceway (pista fofa nas nuvens: barreiras, boxes, arquibancadas, postes,
// pórticos, castelo, casinhas): plástico de brinquedo / glacê em tons pastel.
//   * a cor do vértice cinza/branca vira pastel pela claridade (escuro → lilás, meio → rosa,
//     claro → creme); cores fortes ficam, um pouco clareadas (pastel), e as bem escuras (pneus,
//     vidros, sombras) continuam escuras;
//   * painéis de panel_size m com um leve tom diferente por painel e junta suave (opcional);
//   * brilho de açúcar (pontinhos que cintilam com o ângulo) de perto;
//   * toon com borda clara e um brilho especular macio (rugosidade baixa: no_outline grava < 0,02,
//     que o contorno anime do outline_post não desenha).

uniform vec3 dark_tint : source_color = vec3(0.66, 0.55, 0.92);
uniform vec3 mid_tint : source_color = vec3(1.0, 0.66, 0.82);
uniform vec3 light_tint : source_color = vec3(1.0, 0.95, 0.97);
// Quanto as cores fortes clareiam (0 = ficam como estão).
uniform float pastel = 0.08;
uniform float panel_size = 0.0;
uniform float sparkle = 0.6;
uniform float rim_amount = 0.35;
uniform bool no_outline = false;
global uniform float night;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_pos;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float candy_hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

vec2 candy_uv(vec3 p, vec3 n) {
	vec3 an = abs(n);
	if (an.y >= an.x && an.y >= an.z) {
		return p.xz;
	} else if (an.x >= an.z) {
		return vec2(p.z, p.y);
	}
	return vec2(p.x, p.y);
}

vec3 candy_color(vec3 v) {
	float lum = dot(v, vec3(0.3, 0.59, 0.11));
	float sat = max(v.r, max(v.g, v.b)) - min(v.r, min(v.g, v.b));
	vec3 grey = mix(dark_tint, mid_tint, smoothstep(0.2, 0.55, lum));
	grey = mix(grey, light_tint, smoothstep(0.62, 0.9, lum));
	vec3 strong = mix(v, vec3(1.0), pastel * smoothstep(0.08, 0.3, lum));
	vec3 c = mix(grey, strong, smoothstep(0.16, 0.4, sat));
	// Pretos e quase pretos (pneus, vãos, fundo dos vidros) continuam escuros, puxados para o lilás
	return mix(dark_tint * 0.22 + v * 0.5, c, smoothstep(0.05, 0.16, lum + sat));
}

void fragment() {
	vec3 c = candy_color(COLOR.rgb);
	if (panel_size > 0.0) {
		vec2 uv = candy_uv(local_pos, local_normal) / panel_size;
		c *= 0.96 + 0.08 * candy_hash(vec3(floor(uv), 3.1));
		vec2 g = abs(fract(uv) - 0.5);
		float aa = fwidth(uv.x) * 1.5;
		c *= 1.0 - 0.12 * smoothstep(0.5 - 0.012 - aa, 0.5 - 0.002, max(g.x, g.y));
	}
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(12.0, 60.0, dist);
	// Brilho de açúcar: células de ~6 cm, poucas acesas, piscando com o ângulo de visão
	vec3 view = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
	float h = candy_hash(floor(world_pos * 16.0));
	float glint = step(0.985, h) * pow(max(sin(dot(view, vec3(13.1, 7.7, 5.3)) * 6.0 + h * 40.0), 0.0), 8.0);
	ALBEDO = c;
	EMISSION = c * 0.06 + vec3(1.0, 0.95, 1.0) * glint * sparkle * near * (1.0 + night);
	SPECULAR = no_outline ? 0.2 : 0.45;
	ROUGHNESS = no_outline ? 0.015 : 0.32;
	RIM = rim_amount;
	RIM_TINT = 0.6;
#ifdef CANDY_TWO_SIDED
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
#endif
}
