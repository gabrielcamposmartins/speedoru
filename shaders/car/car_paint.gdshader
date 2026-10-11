// Pintura da carroceria (toon, estilo anime) com ESQUEMAS de divisão das 3 cores.
//
// Cada malha da carroceria fica no espaço do carro (frente +Z, esquerda +X, chão em Y = 0), então a
// posição do vértice diz onde o ponto está no carro e o esquema decide a cor por ali: faixas,
// diagonal, metades, chevrons, ondas, camuflagem… O esquema 0 (Clássico) usa a cor do material de
// cada face no modelo (`slot`). Peças que se mexem (rodas, volante, piloto, flap do DRS) usam
// `plain` e ficam sempre com a cor do slot. As contas são as mesmas de CarLivery.scheme_weights
// (prévias do Estúdio). Acabamento (CarLivery.apply_paint_finish): rugosidade, metal, brilho,
// borda, verniz e flocos.
//
// SKIN (CarSkin): imagem pintada pelo jogador sobre o molde, por cima das cores (o alfa mostra a
// pintura normal). Planificação por projeção: cada face pega a vista para a qual mais aponta
// (lados, cima, baixo, frente, trás), em duas camadas: a VISÍVEL daquele lado e a ESCONDIDA (atrás
// de outra superfície virada para o mesmo lado, pelo mapa de profundidade skin_depth; a de baixo é
// sempre a escondida). Retângulos de CarSkin.rects_uniform (6 visíveis + 6 escondidos).
// template_view >= 0 é o modo MOLDE (CarSkinTemplate): só as faces daquela vista e daquela camada
// (template_layer), sem luz (a cor sai pela emissão). template_out: 0 cor, 1 identificação (R peça,
// G profundidade, B inclinação; valores exatos de 8 bits depois da conversão para sRGB), 2
// profundidade em 16 bits (R alto, G baixo) para o mapa.
shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform vec4 color_primary : source_color = vec4(0.85, 0.12, 0.17, 1.0);
uniform vec4 color_secondary : source_color = vec4(0.95, 0.95, 0.96, 1.0);
uniform vec4 color_accent : source_color = vec4(0.07, 0.64, 0.91, 1.0);
// Cor desta face no modelo: 0 principal, 1 secundária, 2 destaque
uniform int slot = 0;
uniform int scheme = 0;
uniform bool plain = false;
// Acabamento
uniform float rough = 0.22;
uniform float metal = 0.0;
uniform float spec = 0.6;
uniform float rim_amount = 0.35;
uniform float rim_tint_amount = 0.5;
uniform float coat = 0.0;
uniform float coat_rough = 0.1;
uniform float flakes = 0.0;
uniform sampler2D flake_tex : hint_normal, filter_linear_mipmap, repeat_enable;
// Skin
uniform bool use_skin = false;
uniform sampler2D skin_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 skin_rects[12];
uniform vec3 skin_box_min = vec3(-1.1, 0.0, -3.2);
uniform vec3 skin_box_max = vec3(1.1, 1.2, 3.2);
uniform bool use_skin_depth = false;
uniform sampler2D skin_depth : filter_nearest, repeat_disable;
uniform float skin_depth_eps = 0.02;
uniform int template_view = -1;
uniform int template_layer = 0;
uniform int template_out = 0;
uniform float part_id = 0.0;

varying vec3 car_pos;
varying vec3 car_nrm;

void vertex() {
	car_pos = VERTEX;
	car_nrm = NORMAL;
}

// 1 do lado positivo de d, 0 do negativo, com a borda suavizada em ~1 pixel
float on(float d) {
	float fw = max(fwidth(d), 1e-5);
	return smoothstep(-fw, fw, d);
}

// 1 dentro da faixa |d| < half_w
float band(float d, float half_w) {
	return on(half_w - abs(d));
}

float hash3(vec3 q) {
	return fract(sin(dot(q, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

// Peso da cor 2 (x) e da cor 3 (y) por cima da cor 1, no ponto p do carro
vec2 scheme_weights(vec3 p) {
	vec2 w = vec2(0.0);
	if (scheme == 1) {  // Dois tons: cima / baixo, filete na divisão
		float d = p.y - 0.40;
		w = vec2(1.0 - on(d), band(d, 0.034));
	} else if (scheme == 2) {  // Faixas de corrida: duas faixas largas de ponta a ponta
		float d = abs(p.x) - 0.115;
		w = vec2(band(d, 0.05), band(d, 0.07) * (1.0 - band(d, 0.05)));
	} else if (scheme == 3) {  // Diagonal: frente / traseira
		float d = p.z + 1.4 * (p.y - 0.35) - 0.15;
		w = vec2(1.0 - on(d), band(d, 0.05));
	} else if (scheme == 4) {  // Flechas: chevrons apontando para a frente
		float d = p.z - 0.85 * abs(p.x);
		float t = (d / 1.1 - floor(d / 1.1 + 0.5)) * 1.1;
		w = vec2(band(t, 0.17), band(t, 0.21) * (1.0 - band(t, 0.17)));
	} else if (scheme == 5) {  // Degradê da frente para trás, base na cor 3
		w = vec2(smoothstep(1.8, -2.2, p.z), 1.0 - on(p.y - 0.13));
	} else if (scheme == 6) {  // Metades: esquerda / direita, faixa central
		w = vec2(1.0 - on(p.x), band(p.x, 0.035));
	} else if (scheme == 7) {  // Relâmpago: divisão em zigue-zague na lateral
		float tri = abs(fract(p.z * 0.8) - 0.5) * 2.0;
		float d = p.y - (0.30 + 0.16 * tri);
		w = vec2(1.0 - on(d), band(d, 0.034));
	} else if (scheme == 8) {  // Ondas: duas ondas pela lateral
		float d = p.y - (0.40 + 0.06 * sin(p.z * 4.5));
		float d2 = p.y - (0.27 + 0.05 * sin(p.z * 4.5 + 1.6));
		w = vec2(1.0 - on(d), band(d2, 0.034));
	} else if (scheme == 9) {  // Camuflagem: manchas nas três cores
		float n = 0.65 * vnoise(p * 2.2) + 0.35 * vnoise(p * 5.0 + 7.3);
		w = vec2(on(n - 0.48) * (1.0 - on(n - 0.62)), on(n - 0.62));
	} else if (scheme == 10) {  // Pontas: bico e asas na cor 2
		float d1 = p.z - 1.55;
		float d2 = -2.2 - p.z;
		w = vec2(max(on(d1), on(d2)), max(band(d1, 0.03), band(d2, 0.03)));
	} else if (scheme == 11) {  // Faixa lateral larga com filetes
		float d = p.y - 0.36;
		w = vec2(band(d, 0.075), band(abs(d) - 0.105, 0.022));
	}
	return w;
}

// Mesma conta de CarSkin.face_of
int skin_face(vec3 n) {
	vec3 a = abs(n);
	if (a.x >= a.y && a.x >= a.z) {
		return n.x >= 0.0 ? 0 : 1;
	}
	if (a.y >= a.z) {
		return n.y >= 0.0 ? 2 : 3;
	}
	return n.z >= 0.0 ? 4 : 5;
}

// Mesma conta de CarSkin.face_uv (0..1 dentro do retângulo da face)
vec2 skin_face_uv(int f, vec3 p) {
	vec3 s = skin_box_max - skin_box_min;
	vec2 uv;
	if (f == 0) {
		uv = vec2((skin_box_max.z - p.z) / s.z, (skin_box_max.y - p.y) / s.y);
	} else if (f == 1) {
		uv = vec2((p.z - skin_box_min.z) / s.z, (skin_box_max.y - p.y) / s.y);
	} else if (f == 2) {
		uv = vec2((p.z - skin_box_min.z) / s.z, (skin_box_max.x - p.x) / s.x);
	} else if (f == 3) {
		uv = vec2((p.z - skin_box_min.z) / s.z, (p.x - skin_box_min.x) / s.x);
	} else if (f == 4) {
		uv = vec2((p.x - skin_box_min.x) / s.x, (skin_box_max.y - p.y) / s.y);
	} else {
		uv = vec2((skin_box_max.x - p.x) / s.x, (skin_box_max.y - p.y) / s.y);
	}
	return clamp(uv, vec2(0.0), vec2(1.0));
}

// Coordenada no molde (0..1) da face na camada (0 visível, 1 escondida)
vec2 skin_uv(int f, vec3 p, int layer) {
	vec4 r = skin_rects[f + 6 * layer];
	return r.xy + skin_face_uv(f, p) * r.zw;
}

// Quanto o ponto está perto de quem olha a vista (0..1, 1 = colado na câmera)
float skin_closeness(int f, vec3 p) {
	vec3 t = (p - skin_box_min) / (skin_box_max - skin_box_min);
	if (f == 0) return t.x;
	if (f == 1) return 1.0 - t.x;
	if (f == 2) return t.y;
	if (f == 3) return 1.0 - t.y;
	if (f == 4) return t.z;
	return 1.0 - t.z;
}

float skin_axis(int f) {
	vec3 s = skin_box_max - skin_box_min;
	return f < 2 ? s.x : (f < 4 ? s.y : s.z);
}

// Camada do ponto: escondido se está atrás da superfície visível (mapa de profundidade) por mais
// que a folga; a parte de baixo é sempre a escondida
int skin_layer(int f, vec3 p) {
	if (f == 3) {
		return 1;
	}
	if (!use_skin_depth) {
		return 0;
	}
	vec4 d = texture(skin_depth, skin_uv(f, p, 0));
	if (d.a < 0.5) {
		return 0;
	}
	float front = (round(d.r * 255.0) * 256.0 + round(d.g * 255.0)) / 65535.0;
	return skin_closeness(f, p) < front - skin_depth_eps / skin_axis(f) ? 1 : 0;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec3 c1 = color_primary.rgb;
	vec3 c2 = color_secondary.rgb;
	vec3 c3 = color_accent.rgb;
	vec3 col;
	if (plain || scheme == 0) {
		col = slot == 1 ? c2 : (slot == 2 ? c3 : c1);
	} else {
		vec2 w = scheme_weights(car_pos);
		col = mix(mix(c1, c2, w.x), c3, w.y);
	}
	int face = skin_face(car_nrm);
	int layer = skin_layer(face, car_pos);
	if (use_skin && !plain) {
		vec4 sk = texture(skin_tex, skin_uv(face, car_pos, layer));
		col = mix(col, sk.rgb, sk.a);
	}
	if (template_view >= 0) {
		// Molde: só as faces desta vista e desta camada, cor pura (a cena do molde não tem luz)
		if (face != template_view || layer != template_layer || plain) {
			discard;
		}
		ALBEDO = vec3(0.0);
		float near = skin_closeness(face, car_pos);
		if (template_out == 2) {
			float v = round(near * 65535.0);
			EMISSION = srgb_to_linear(vec3(floor(v / 256.0) / 255.0, mod(v, 256.0) / 255.0, 0.0));
		} else if (template_out == 1) {
			vec3 n = normalize(car_nrm);
			float tilt = max(abs(n.x), max(abs(n.y), abs(n.z)));
			EMISSION = srgb_to_linear(vec3(part_id, near, tilt));
		} else {
			EMISSION = col;
		}
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	} else {
		ALBEDO = col;
		ROUGHNESS = rough;
		METALLIC = metal;
		SPECULAR = spec;
		RIM = rim_amount;
		RIM_TINT = rim_tint_amount;
		CLEARCOAT = coat;
		CLEARCOAT_ROUGHNESS = coat_rough;
		if (flakes > 0.0) {
			// Flocos metálicos: normal map projetado nos três planos do carro
			vec3 bw = pow(abs(car_nrm), vec3(4.0));
			bw /= max(bw.x + bw.y + bw.z, 1e-4);
			vec3 nx = texture(flake_tex, car_pos.zy * 24.0).xyz;
			vec3 ny = texture(flake_tex, car_pos.xz * 24.0).xyz;
			vec3 nz = texture(flake_tex, car_pos.xy * 24.0).xyz;
			NORMAL_MAP = nx * bw.x + ny * bw.y + nz * bw.z;
			NORMAL_MAP_DEPTH = flakes;
		}
	}
}
