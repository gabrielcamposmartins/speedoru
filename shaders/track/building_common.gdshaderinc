// Material das construções (barreiras, prédios, arquibancadas, postes, casas, rochas...).
// A cor vem do vértice; três texturas projetadas no espaço do objeto (eixo dominante da normal)
// dão naturalidade:
//   detail_tex: grão do material (concreto/pintura), em duas escalas;
//   grime_tex:  manchas e escorridos de sujeira (1 = limpo);
//   normal_tex: pequenas deformidades (amassados, ondulações, poros).
// Também: juntas de painéis opcionais, sujeira perto do chão e borda iluminada (toon).
// no_outline = true grava rugosidade 0, que o contorno anime (outline_post) não desenha.

uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 0.6;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.22;
uniform float grime_scale = 0.07;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.45;
uniform float normal_scale = 0.35;
uniform float normal_strength = 0.55;
// Tamanho (m) das placas/painéis; 0 = sem juntas.
uniform float panel_size = 0.0;
uniform float ground_dirt : hint_range(0.0, 1.0) = 0.3;
uniform float roughness_value = 0.75;
uniform float rim_amount = 0.2;
uniform bool no_outline = false;
// Direção para o sol (mundo). Atualizada pelo Daylight; usada para estabilizar o normal map.
global uniform vec3 sun_dir_world;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_pos;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Base tangente do plano de projeção escolhido (mesmo eixo usado no fragment)
	vec3 an = abs(NORMAL);
	if (an.y >= an.x && an.y >= an.z) {
		TANGENT = vec3(1.0, 0.0, 0.0);
	} else if (an.x >= an.z) {
		TANGENT = vec3(0.0, 0.0, 1.0);
	} else {
		TANGENT = vec3(1.0, 0.0, 0.0);
	}
	TANGENT = normalize(TANGENT - NORMAL * dot(NORMAL, TANGENT));
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

vec2 projected_uv(vec3 p, vec3 n) {
	vec3 an = abs(n);
	if (an.y >= an.x && an.y >= an.z) {
		return p.xz;
	} else if (an.x >= an.z) {
		return vec2(p.z, -p.y);
	}
	return vec2(p.x, -p.y);
}

void fragment() {
	vec2 uv = projected_uv(local_pos, local_normal);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(40.0, 140.0, dist);

	float d1 = texture(detail_tex, uv * detail_scale).r;
	float d2 = texture(detail_tex, uv * detail_scale * 0.27 + vec2(0.31, 0.17)).r;
	float detail = mix(d2, d1 * 0.6 + d2 * 0.4, near);
	vec3 c = COLOR.rgb * (1.0 + (detail - 0.5) * 2.0 * detail_strength);

	float grime = texture(grime_tex, uv * grime_scale + vec2(0.13, 0.41)).r;
	c *= mix(1.0, grime, grime_strength);
	// Sujeira/umidade subindo do chão nas paredes
	float wall = 1.0 - abs(normalize(local_normal).y);
	c *= 1.0 - ground_dirt * (1.0 - smoothstep(0.0, 1.4, world_pos.y)) * wall;

	if (panel_size > 0.0) {
		vec2 g = abs(fract(uv / panel_size) - 0.5);
		float aa = fwidth(uv.x / panel_size) * 1.5;
		float seam = smoothstep(0.5 - 0.012 - aa, 0.5 - 0.004, max(g.x, g.y));
		c *= 1.0 - 0.22 * seam * near;
	}
	ALBEDO = c;
	NORMAL_MAP = texture(normal_tex, uv * normal_scale + vec2(0.57, 0.23)).rgb;
	// Com sombreamento toon (dois degraus) o relevo faz o pixel alternar entre luz e sombra onde a
	// superfície está quase de lado/de costas para o sol: lá o normal map é atenuado (sem "cintilar").
	float facing_light = dot(normalize(NORMAL), normalize((VIEW_MATRIX * vec4(sun_dir_world, 0.0)).xyz));
	float stable = smoothstep(0.15, 0.55, facing_light);
	float down = smoothstep(-0.2, -0.6, normalize(local_normal).y);
	NORMAL_MAP_DEPTH = normal_strength * mix(0.3, 1.0, near) * stable * (1.0 - down);
	ROUGHNESS = no_outline ? 0.0 : roughness_value;
	RIM = rim_amount;
	RIM_TINT = 0.6;
}
