// Chão da cidade (TrackCity): cor de vértice + desenho do piso pelo tipo (COLOR.a):
//   >= 0.85 praça / calçadão: lajes de pedra desencontradas com faixas decorativas;
//   >= 0.6  calçada: ladrilhos quadrados;
//   >= 0.4  rua de pedestres: paralelepípedos;
//   >= 0.27 jardim / grama: cor de grama do ambiente (globais do terreno), tufos e flores; nas
//           encostas, terraços com muretas de pedra seguindo as curvas de nível;
//   >= 0.2  mato mediterrâneo (morros): manchas de verde escuro, oliva e rocha aparecendo;
//   >= 0.06 encosta: rocha com estratos;
//   <  0.06 sob a pista: asfalto escuro.
// Os desenhos finos somem com a distância (sem serrilhado); o tom de cada peça varia um pouco.
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

#include "res://shaders/track/terrain_common.gdshaderinc"

uniform sampler2D grime_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grime_scale = 0.05;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.22;

varying vec3 world_pos;
varying vec3 world_n;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// 1 nas juntas de uma grade (f = fração dentro da peça, w = meia-largura da junta na fração).
float joints(vec2 f, vec2 w, vec2 aa) {
	vec2 e = min(f, 1.0 - f);
	vec2 j = 1.0 - smoothstep(w - aa, w + aa, e);
	return max(j.x, j.y);
}

void fragment() {
	vec2 xz = world_pos.xz;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float fine = 1.0 - smoothstep(45.0, 160.0, dist);
	float a = COLOR.a;
	vec3 c = COLOR.rgb;
	float rough = 0.85;
	if (a >= 0.85) {
		// Lajes de 1,6 x 1,0 m em fiadas desencontradas; a cada 12 m uma faixa de pedra clara
		vec2 p = xz / vec2(1.6, 1.0);
		p.x += 0.5 * mod(floor(p.y), 2.0);
		vec2 id = floor(p);
		vec2 f = fract(p);
		float h = tc_hash(id + 17.0);
		c *= mix(1.0, 0.9 + 0.16 * h, fine);
		c *= 1.0 - joints(f, vec2(0.012, 0.02), fwidth(p)) * 0.2 * fine;
		vec2 band = abs(fract(xz / 12.0 + 0.5) - 0.5) * 12.0;
		float stripe = 1.0 - smoothstep(0.35, 0.4, min(band.x, band.y));
		c = mix(c, c * 1.12 + vec3(0.03), stripe * 0.6);
	} else if (a >= 0.6) {
		// Ladrilhos de 0,5 m com rejunte
		vec2 p = xz / 0.5;
		vec2 id = floor(p);
		float h = tc_hash(id + 3.0);
		c *= mix(1.0, 0.94 + 0.1 * h, fine);
		c *= 1.0 - joints(fract(p), vec2(0.03), fwidth(p)) * 0.18 * fine;
	} else if (a >= 0.4) {
		// Paralelepípedos (pedras de 0,22 m arredondadas, fiadas desencontradas)
		vec2 p = xz / vec2(0.24, 0.2);
		p.x += 0.5 * mod(floor(p.y), 2.0);
		vec2 id = floor(p);
		vec2 f = fract(p) - 0.5;
		float h = tc_hash(id + 9.0);
		float stone = 1.0 - smoothstep(0.32, 0.5, length(f * vec2(1.0, 1.1)));
		c *= mix(1.0, (0.78 + 0.22 * stone) * (0.9 + 0.18 * h), fine);
		rough = 0.95;
	} else if (a >= 0.27) {
		// Grama dos jardins com a cor do ambiente (verão, outono, sakura, fantasia), tufos e flores
		vec3 g = tc_grass_color(xz * 1.3);
		// Gramado de cidade: um pouco mais escuro e menos saturado que os campos de Monza
		g = mix(g, vec3(dot(g, vec3(0.3, 0.59, 0.11))), 0.3) * 0.74;
		float tuft = tc_noise(xz * 1.7);
		g *= 0.88 + 0.22 * tuft * (0.4 + 0.6 * fine);
		c = mix(c, g, 0.85);
		vec2 fp = xz * 2.2;
		float fh = tc_hash(floor(fp) + 41.0);
		float flower = step(0.93, fh) * (1.0 - smoothstep(0.18, 0.3, length(fract(fp) - 0.5))) * tc_meadow(xz * 0.6) * fine;
		c = mix(c, tc_flower_color(fract(fh * 7.3)), flower);
		// Encosta: terraços (muretas de pedra clara seguindo as curvas de nível a cada 3,5 m)
		float slope = 1.0 - world_n.y;
		if (slope > 0.06) {
			float lev = world_pos.y / 3.5;
			float wall_aa = fwidth(lev) * 1.5 + 0.01;
			float wall = 1.0 - smoothstep(0.1, 0.1 + wall_aa, fract(lev));
			vec3 stone = vec3(0.42, 0.38, 0.32) * (0.85 + 0.25 * tc_noise(xz * 2.0));
			c = mix(c, stone, wall * smoothstep(0.06, 0.15, slope) * (0.5 + 0.5 * fine));
		}
		rough = 1.0;
	} else if (a >= 0.2) {
		// Mato mediterrâneo dos morros: verde escuro e oliva em manchas, rocha clara aparecendo
		vec3 deep = grass_deep * 0.85;
		vec3 olive = mix(grass_warm, vec3(0.16, 0.16, 0.06), 0.5);
		float m = tc_fbm(xz / 55.0);
		vec3 scrub = mix(deep, olive, smoothstep(0.35, 0.7, m));
		float bare = smoothstep(0.62, 0.75, tc_fbm(xz / 30.0 + 9.0)) + smoothstep(0.25, 0.5, 1.0 - world_n.y);
		scrub = mix(scrub, vec3(0.45, 0.42, 0.36), clamp(bare, 0.0, 1.0) * 0.8);
		c = mix(c, scrub * (0.85 + 0.3 * tc_noise(xz / 9.0)), 0.9);
		rough = 1.0;
	} else if (a >= 0.06) {
		// Rocha da encosta: estratos e manchas
		float strata = tc_noise(vec2(xz.x * 0.08, world_pos.y * 0.9));
		c *= 0.86 + 0.24 * strata;
		c *= 0.9 + 0.15 * tc_noise(xz * 0.6);
		rough = 1.0;
	} else {
		// Asfalto sob a pista
		c *= 0.92 + 0.12 * tc_noise(xz * 3.0) * fine;
	}
	// Tampas de bueiro (redondas) e grelhas nas calçadas e praças, só perto
	if (a >= 0.6 && fine > 0.0) {
		vec2 cellp = xz / 9.0;
		vec2 cid = floor(cellp);
		float hm = tc_hash(cid + 71.0);
		if (hm > 0.8) {
			vec2 center = (cid + 0.25 + 0.5 * vec2(tc_hash(cid + 3.0), tc_hash(cid + 5.0))) * 9.0;
			float r = length(xz - center);
			float lid = 1.0 - smoothstep(0.34, 0.37, r);
			float ring = smoothstep(0.3, 0.32, r) * lid;
			float grid = step(0.5, fract((xz.x - center.x) * 6.0)) * step(0.5, fract((xz.y - center.y) * 6.0));
			vec3 metal = vec3(0.13, 0.13, 0.14) * (0.85 + 0.3 * grid);
			c = mix(c, metal, lid * fine);
			c = mix(c, vec3(0.08), ring * fine * 0.6);
		} else if (hm < 0.06) {
			vec2 center = (cid + 0.5) * 9.0;
			vec2 q = abs(xz - center);
			float drain = (1.0 - step(0.5, q.x)) * (1.0 - step(0.18, q.y));
			float slots = step(0.5, fract((xz.x - center.x) * 10.0));
			c = mix(c, vec3(0.07, 0.07, 0.08) * (0.7 + 0.6 * slots), drain * fine);
		}
	}
	// Sujeira e variação larga (quebra a repetição de longe)
	float grime = texture(grime_tex, xz * grime_scale + vec2(0.37, 0.11)).r;
	c *= mix(1.0, grime, grime_strength);
	c *= 0.94 + 0.12 * tc_noise(xz / 37.0);
	if (a >= 0.6) {
		// Pisos de pedra: manchas grandes mais quentes (pedra de calcário) e mais frias (granito)
		float tone = tc_fbm(xz / 70.0 + 5.0);
		c *= mix(vec3(0.95, 0.97, 1.03), vec3(1.05, 1.0, 0.92), smoothstep(0.3, 0.7, tone));
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	RIM = 0.0;
}
