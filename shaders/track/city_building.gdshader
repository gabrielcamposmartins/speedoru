// Prédios da cidade (TrackCity): cor de vértice + texturas do material (como building_common) e
// janelas procedurais nas paredes.
//   UV  = (posição ao longo da parede, altura acima da base) em metros;
//   UV2 = (vão útil da parede onde cabem janelas, altura total da parede).
//   COLOR.a = estilo: < 0.3 clássico (venezianas), < 0.6 moderno (varandas e vidro),
//             < 0.9 simples, >= 0.9 sem janelas (telhados).
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
		} else if (style < 0.6) {
			// Moderno: faixa de varanda clara e vidro corrido
			win = rect(f, vec2(0.04, 0.22), vec2(0.96, 0.9), faa);
			band = rect(vec2(0.5, f.y), vec2(0.0, 0.0), vec2(1.0, 0.2), faa);
			frame = rect(f, vec2(0.48, 0.22), vec2(0.52, 0.9), faa) * win;
		} else {
			win = rect(f, vec2(0.3, 0.3), vec2(0.7, 0.78), faa);
		}
		// Térreo: vitrines largas e escuras
		if (fl < 1.0 && UV2.y > 6.0) {
			win = rect(f, vec2(0.08, 0.1), vec2(0.92, 0.8), faa);
			frame = 0.0;
			shutters = 0.0;
			band = 0.0;
		}
		win *= inside;
		frame *= inside;
		shutters *= inside;
		band *= step(UV.y, UV2.y - 0.9) * step(0.4, UV.y) * step(1.0, fl);
		// Vidro: escuro com reflexo do céu na parte de cima, variando por janela
		float var_w = hash(floor(cell) + 7.7);
		vec3 glass = mix(glass_color, glass_sky, clamp(f.y * 0.8 - 0.1 + var_w * 0.35, 0.0, 1.0) * 0.55);
		glass = mix(glass, glass * 1.6, step(0.92, var_w)); // cortina clara
		c = mix(c, c * 1.12 + 0.04, clamp(frame, 0.0, 1.0) * 0.8);
		c = mix(c, balcony_color, clamp(band, 0.0, 1.0) * (style < 0.6 && style >= 0.3 ? 0.9 : 0.35));
		c = mix(c, shutter_color * (0.8 + 0.4 * var_w), clamp(shutters, 0.0, 1.0));
		c = mix(c, glass, clamp(win, 0.0, 1.0));
		rough = mix(0.75, 0.35, clamp(win, 0.0, 1.0));
		if (night > 0.0) {
			float lit = step(0.55, hash(floor(cell) + floor(UV2.x * 0.37) + 1.3));
			emission_out = window_light * clamp(win, 0.0, 1.0) * lit * night * (0.6 + 0.8 * var_w);
		}
	}
	ALBEDO = c;
	NORMAL_MAP = texture(normal_tex, tuv * normal_scale + vec2(0.57, 0.23)).rgb;
	float facing_light = dot(normalize(NORMAL), normalize((VIEW_MATRIX * vec4(sun_dir_world, 0.0)).xyz));
	NORMAL_MAP_DEPTH = normal_strength * near * smoothstep(0.15, 0.55, facing_light);
	ROUGHNESS = rough;
	EMISSION = emission_out * 2.2;
	RIM = 0.15;
	RIM_TINT = 0.6;
}
