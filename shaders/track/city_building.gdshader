// Prédios da cidade (TrackCity): cor de vértice + texturas do material (como building_common) e
// janelas procedurais nas paredes.
//   UV  = (posição ao longo da parede, altura acima da base) em metros;
//   UV2 = (vão útil da parede onde cabem janelas, altura total da parede).
//   COLOR.a = estilo: < 0.3 clássico (venezianas), < 0.6 moderno (varandas e vidro),
//             < 0.9 simples, >= 0.9 sem janelas (telhados).
// Detalhes: embasamento de pedra e cornija no topo das paredes, peitoris, toldos listrados sobre
// parte das vitrines do térreo, guarda-corpo nas varandas; telhados com telhas em fiadas (cor
// telha) ou cascalho e manta (laje plana). Sem contorno anime (rugosidade 0) e com sombra de
// contato escurecendo a base das paredes.
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float floor_h = 3.3;
uniform float bay_w = 3.2;
uniform vec3 glass_color : source_color = vec3(0.16, 0.22, 0.3);
uniform vec3 glass_sky : source_color = vec3(0.55, 0.7, 0.85);
uniform vec3 shutter_color : source_color = vec3(0.24, 0.42, 0.3);
uniform vec3 balcony_color : source_color = vec3(0.93, 0.93, 0.9);
uniform float detail_scale = 0.6;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.18;
uniform float grime_scale = 0.07;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.35;
uniform float normal_scale = 0.35;
uniform float normal_strength = 0.4;
// À noite (0..1) parte das janelas acende com luz quente
uniform float night = 0.0;
uniform vec3 window_light : source_color = vec3(1.0, 0.78, 0.45);
global uniform vec3 sun_dir_world;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 an = abs(NORMAL);
	TANGENT = an.y > 0.7 ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL));
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

// Retângulo suave (anti-serrilhado) em coordenadas de célula
float rect(vec2 p, vec2 lo, vec2 hi, vec2 aa) {
	vec2 a = smoothstep(lo - aa, lo + aa, p) * (1.0 - smoothstep(hi - aa, hi + aa, p));
	return a.x * a.y;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Cores das venezianas por prédio (lineares): verde, azul-acinzentado, vinho, creme, sálvia
vec3 shutter_tone(float h) {
	if (h < 0.35) return vec3(0.05, 0.15, 0.08);
	if (h < 0.55) return vec3(0.09, 0.15, 0.24);
	if (h < 0.7) return vec3(0.24, 0.05, 0.04);
	if (h < 0.85) return vec3(0.6, 0.55, 0.42);
	return vec3(0.18, 0.25, 0.15);
}

// Cores dos toldos (lineares)
vec3 awning_color(float h) {
	if (h < 0.25) return vec3(0.6, 0.05, 0.06);
	if (h < 0.5) return vec3(0.04, 0.25, 0.12);
	if (h < 0.75) return vec3(0.03, 0.08, 0.3);
	return vec3(0.75, 0.6, 0.35);
}

void fragment() {
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec2 tuv = abs(world_normal.y) > 0.7 ? world_pos.xz : vec2(dot(world_pos.xz, vec2(-world_normal.z, world_normal.x)), -world_pos.y);
	float d1 = texture(detail_tex, tuv * detail_scale).r;
	float d2 = texture(detail_tex, tuv * detail_scale * 0.27 + vec2(0.31, 0.17)).r;
	float near = 1.0 - smoothstep(40.0, 160.0, dist);
	float detail = mix(d2, d1 * 0.6 + d2 * 0.4, near);
	vec3 c = COLOR.rgb * (1.0 + (detail - 0.5) * 2.0 * detail_strength);
	float grime = texture(grime_tex, tuv * grime_scale + vec2(0.13, 0.41)).r;
	c *= mix(1.0, grime, grime_strength);

	float style = COLOR.a;
	float wall = 1.0 - abs(world_normal.y);
	vec2 aa = fwidth(UV) * 0.75 + 0.002;
	float rough = 0.75;
	vec3 emission_out = vec3(0.0);
	if (style < 0.9 && wall > 0.5) {
		// Sombra de contato com o chão (o chão costuma estar na base da parede)
		c *= mix(0.62, 1.0, smoothstep(-0.2, 1.8, UV.y));
		// Embasamento de pedra mais escuro e cornija clara com friso no topo da parede
		float plinth = 1.0 - smoothstep(0.7 - aa.y, 0.7 + aa.y, UV.y);
		c = mix(c, c * 0.7, plinth);
		float crown = smoothstep(UV2.y - 0.6 - aa.y, UV2.y - 0.6 + aa.y, UV.y);
		c = mix(c, c * 1.12 + 0.035, crown);
		c *= 1.0 - 0.35 * rect(vec2(0.5, UV.y), vec2(0.0, UV2.y - 0.72), vec2(1.0, UV2.y - 0.62), aa);
		float fl = floor(UV.y / floor_h);
		vec2 cell = vec2(UV.x / bay_w, UV.y / floor_h);
		vec2 f = fract(cell);
		vec2 faa = aa / vec2(bay_w, floor_h);
		// Só dentro do vão útil e abaixo do topo da parede
		float inside = step(0.0, UV.x) * step(UV.x, UV2.x) * step(UV.y, UV2.y - 0.9) * step(0.4, UV.y);
		float win;
		float frame = 0.0;
		float shutters = 0.0;
		float band = 0.0;
		if (style < 0.3) {
			// Clássico: janelas altas, molduras claras e venezianas verdes (algumas fechadas)
			win = rect(f, vec2(0.33, 0.2), vec2(0.67, 0.82), faa);
			frame = rect(f, vec2(0.3, 0.17), vec2(0.7, 0.86), faa) - win;
			float closed = step(0.7, hash(floor(cell) + 3.1));
			shutters = (rect(f, vec2(0.16, 0.2), vec2(0.33, 0.82), faa) + rect(f, vec2(0.67, 0.2), vec2(0.84, 0.82), faa));
			shutters += closed * win;
			win *= 1.0 - closed;
			// Cornija entre os andares
			band = rect(vec2(0.5, f.y), vec2(0.0, 0.0), vec2(1.0, 0.05), faa) * 0.6;
			// Peitoril de pedra clara sob a janela
			frame += rect(f, vec2(0.28, 0.15), vec2(0.72, 0.2), faa) * 0.9;
		} else if (style < 0.6) {
			// Moderno: faixa de varanda clara e vidro corrido
			win = rect(f, vec2(0.04, 0.22), vec2(0.96, 0.9), faa);
			band = rect(vec2(0.5, f.y), vec2(0.0, 0.0), vec2(1.0, 0.2), faa);
			frame = rect(f, vec2(0.48, 0.22), vec2(0.52, 0.9), faa) * win;
		} else {
			win = rect(f, vec2(0.3, 0.3), vec2(0.7, 0.78), faa);
			frame = rect(f, vec2(0.27, 0.25), vec2(0.73, 0.3), faa) * 0.9;
		}
		float awning = 0.0;
		vec3 awning_col = vec3(0.0);
		// Cada prédio com a sua cor de veneziana (pelo tamanho da parede e da altura)
		float bld = hash(vec2(floor(UV2.x * 0.37), floor(UV2.y * 0.53)) + 5.0);
		vec3 shutter_col = mix(shutter_color, shutter_tone(bld), 0.85);
		float flowers = 0.0;
		float lintel = 0.0;
		if (style < 0.3) {
			// Verga clara sobre a janela e floreira (verde com flores) em parte das janelas
			lintel = rect(f, vec2(0.29, 0.84), vec2(0.71, 0.9), faa);
			flowers = rect(f, vec2(0.31, 0.2), vec2(0.69, 0.27), faa) * step(0.72, hash(floor(cell) + 13.7)) * step(1.0, fl);
		}
		// Térreo: vitrines largas e escuras
		if (fl < 1.0 && UV2.y > 6.0) {
			win = rect(f, vec2(0.08, 0.1), vec2(0.92, 0.76), faa);
			frame = 0.0;
			shutters = 0.0;
			band = 0.0;
			// Toldo listrado sobre parte das vitrines (lojas, cafés)
			float shop = hash(vec2(floor(cell.x), floor(UV2.x * 0.71)) + 21.0);
			awning = rect(f, vec2(0.03, 0.78), vec2(0.97, 0.95), faa) * step(0.4, shop);
			awning_col = mix(awning_color(fract(shop * 5.3)), vec3(0.85, 0.83, 0.78), step(0.5, fract(f.x * 7.0)) * step(0.7, fract(shop * 3.1)));
		}
		win *= inside;
		frame *= inside;
		shutters *= inside;
		lintel *= inside;
		flowers *= inside;
		band *= step(UV.y, UV2.y - 0.9) * step(0.4, UV.y) * step(1.0, fl);
		// Vidro: escuro com reflexo do céu na parte de cima, variando por janela
		float var_w = hash(floor(cell) + 7.7);
		vec3 glass = mix(glass_color, glass_sky, clamp(f.y * 0.8 - 0.1 + var_w * 0.35, 0.0, 1.0) * 0.55);
		glass = mix(glass, glass * 1.6, step(0.92, var_w)); // cortina clara
		c = mix(c, c * 1.12 + 0.04, clamp(frame, 0.0, 1.0) * 0.8);
		c = mix(c, balcony_color, clamp(band, 0.0, 1.0) * (style < 0.6 && style >= 0.3 ? 0.9 : 0.35));
		c = mix(c, shutter_col * (0.8 + 0.4 * var_w), clamp(shutters, 0.0, 1.0));
		c = mix(c, c * 1.18 + 0.04, clamp(lintel, 0.0, 1.0) * 0.8);
		c = mix(c, glass, clamp(win, 0.0, 1.0));
		// Guarda-corpo das varandas (montantes e corrimão escuros na faixa clara)
		if (style >= 0.3 && style < 0.6) {
			float rail = band * (step(0.88, fract(f.x * 12.0)) + rect(vec2(0.5, f.y), vec2(0.0, 0.17), vec2(1.0, 0.2), faa));
			c = mix(c, vec3(0.08, 0.09, 0.1), clamp(rail, 0.0, 1.0) * 0.8 * inside);
		}
		c = mix(c, awning_col, clamp(awning * inside, 0.0, 1.0));
		// Floreiras: folhagem com pontinhos de flor (vermelho, rosa, branco)
		if (flowers > 0.0) {
			float dots = step(0.6, hash(floor(UV * 9.0)));
			vec3 bloom = mix(vec3(0.7, 0.04, 0.06), vec3(0.9, 0.35, 0.55), step(0.5, hash(floor(UV * 9.0) + 2.0)));
			c = mix(c, mix(vec3(0.03, 0.12, 0.03), bloom, dots), clamp(flowers, 0.0, 1.0));
		}
		// Pedras de cunhal nas quinas (fora do vão das janelas), alternando a cada 0,55 m
		if (style < 0.6) {
			float corner = 1.0 - step(0.0, UV.x) * step(UV.x, UV2.x);
			float block = step(0.5, fract(UV.y / 1.1));
			c = mix(c, c * mix(1.16, 0.92, block) + 0.02, corner * step(UV.y, UV2.y - 0.7) * 0.85);
		}
		rough = mix(0.75, 0.35, clamp(win, 0.0, 1.0));
		if (night > 0.0) {
			float lit = step(0.55, hash(floor(cell) + floor(UV2.x * 0.37) + 1.3));
			emission_out = window_light * clamp(win, 0.0, 1.0) * lit * night * (0.6 + 0.8 * var_w);
		}
	}
	if (world_normal.y > 0.55 && style >= 0.9) {
		bool tile = COLOR.r > COLOR.g * 1.45 && COLOR.r > 0.25;
		if (tile) {
			// Telhas: fiadas horizontais (pela altura) com a borda inferior escura e tom por peça
			float row = world_pos.y * 3.2;
			float col = dot(world_pos.xz, vec2(0.71, 0.71)) * 4.0 + floor(row) * 0.5;
			c *= 0.88 + 0.16 * hash(vec2(floor(col), floor(row)));
			c *= 1.0 - 0.25 * smoothstep(0.75, 1.0, fract(row)) * near;
		} else {
			// Laje plana: cascalho e manchas de manta
			c *= 0.9 + 0.14 * vnoise(world_pos.xz * 6.0) * near;
			c *= 0.92 + 0.12 * vnoise(world_pos.xz * 0.35);
		}
	}
	ALBEDO = c;
	NORMAL_MAP = texture(normal_tex, tuv * normal_scale + vec2(0.57, 0.23)).rgb;
	float facing_light = dot(normalize(NORMAL), normalize((VIEW_MATRIX * vec4(sun_dir_world, 0.0)).xyz));
	NORMAL_MAP_DEPTH = normal_strength * near * smoothstep(0.15, 0.55, facing_light);
	// Rugosidade 0: o contorno anime (outline_post) não desenha nos prédios nem nas varandas. Sem
	// especular nas paredes (não ficam espelhadas); o vidro das janelas reflete um pouco o céu.
	ROUGHNESS = 0.0;
	SPECULAR = (0.75 - rough) * 0.75;
	EMISSION = emission_out * 2.2;
	RIM = 0.15;
	RIM_TINT = 0.6;
}
