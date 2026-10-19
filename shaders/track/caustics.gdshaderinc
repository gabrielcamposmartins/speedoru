// Cáustica da água (pista no fundo do mar): a rede de luz que a superfície ondulada projeta no
// fundo. Dois diagramas de Voronoi animados, em escalas e velocidades diferentes; a luz fica nas
// bordas entre as células e é mais forte onde as duas redes se cruzam. Só abaixo da linha d'água,
// nas faces voltadas para cima, enfraquecendo com a profundidade e some de longe (sem cintilar).
// Os parâmetros são trocados pelo SeaWorld conforme o período do dia (TrackMaterials.set_sea).

uniform float caustic_strength = 0.0;
// Células por metro (0,2 = células de ~5 m).
uniform float caustic_scale = 0.2;
uniform vec3 caustic_color : source_color = vec3(0.62, 0.95, 1.0);
uniform float water_level = 28.0;

vec2 caustic_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Distância até a borda entre as duas células mais próximas (0 = em cima da borda).
float caustic_cells(vec2 p, float t) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = caustic_hash(i + g);
			o = 0.5 + 0.42 * sin(t + 6.2831 * o);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}

// Intensidade (~0..1,5) da cáustica no ponto `wp` do mundo.
float caustics(vec3 wp, float t, float scale) {
	vec2 p = wp.xz * scale;
	float a = caustic_cells(p, t * 0.9);
	float b = caustic_cells(p * 1.37 + vec2(3.1, 7.7), 1.3 - t * 0.7);
	float la = 1.0 - smoothstep(0.0, 0.16, a);
	float lb = 1.0 - smoothstep(0.0, 0.2, b);
	return la * 0.55 + lb * 0.4 + la * lb * 0.6;
}

// Luz (para EMISSION) da cáustica num ponto com normal de mundo `wn`, a `dist` m da câmera.
vec3 sea_caustic_light(vec3 wp, vec3 wn, float dist, float t) {
	if (caustic_strength <= 0.0) {
		return vec3(0.0);
	}
	float depth = water_level - wp.y;
	float under = smoothstep(0.0, 1.5, depth);
	float up = smoothstep(-0.1, 0.8, wn.y);
	float fade = 1.0 - smoothstep(35.0, 110.0, dist);
	float k = under * up * fade * exp(-max(depth, 0.0) * 0.018);
	if (k <= 0.001) {
		return vec3(0.0);
	}
	return caustic_color * (caustic_strength * k * caustics(wp, t, caustic_scale));
}
