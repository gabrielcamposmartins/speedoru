// Mar (opaco, estilo anime): ondas no vértice (calmas dentro do porto), dois normal maps
// rolando, cor rasa/funda pela distância da costa, fresnel com o céu, brilho do sol e espuma
// junto aos cais e nas cristas.
// shore_tex (2 m/pixel sobre shore_area): R = distância até a terra (0..48 m), G = porto (calmo).
// ROUGHNESS quase 0: o contorno anime (outline_post) não desenha a água.
shader_type spatial;
render_mode cull_back;

uniform sampler2D shore_tex : filter_linear, repeat_disable;
// (x mínimo, y mínimo, x máximo, y máximo) da textura, em x leste / y norte (y = -z do Godot)
uniform vec4 shore_area = vec4(0.0, 0.0, 1.0, 1.0);
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.02, 0.2, 0.38);
uniform vec3 open_color : source_color = vec3(0.04, 0.33, 0.52);
uniform vec3 shallow_color : source_color = vec3(0.09, 0.55, 0.6);
uniform vec3 sky_tint : source_color = vec3(0.6, 0.78, 0.95);
uniform vec3 foam_color : source_color = vec3(0.95, 0.97, 1.0);
uniform float wave_height = 0.32;
uniform float harbour_wave = 0.05;
// Plano do horizonte: sem ondas no vértice nem textura da costa
uniform bool far_plane = false;

varying vec3 wpos;
varying float calm;
varying float shore_d;
varying float crest;

vec2 shore_uv(vec3 p) {
	return vec2((p.x - shore_area.x) / (shore_area.z - shore_area.x), (shore_area.w + p.z) / (shore_area.w - shore_area.y));
}

vec3 sample_shore(vec3 p) {
	vec2 uv = shore_uv(p);
	if (far_plane || uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return vec3(1.0, 0.0, 0.0);
	}
	return textureLod(shore_tex, uv, 0.0).rgb;
}

// Soma de ondas direcionais: altura e derivadas (dh/dx, dh/dz)
vec3 waves(vec2 p, float t) {
	vec3 acc = vec3(0.0);
	vec4 w[4] = vec4[](vec4(0.8, 0.6, 62.0, 0.9), vec4(-0.3, 0.95, 37.0, 1.25), vec4(0.95, -0.2, 23.0, 1.7), vec4(0.2, 0.98, 14.0, 2.3));
	float amp[4] = float[](1.0, 0.55, 0.3, 0.16);
	for (int i = 0; i < 4; i++) {
		vec2 d = normalize(w[i].xy);
		float k = 6.2831 / w[i].z;
		float ph = dot(d, p) * k - t * w[i].w;
		acc.x += sin(ph) * amp[i];
		acc.yz += d * cos(ph) * amp[i] * k;
	}
	return acc;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 sh = sample_shore(wpos);
	calm = sh.g;
	shore_d = sh.r * 48.0;
	float a = far_plane ? 0.0 : mix(wave_height, harbour_wave, calm) * smoothstep(0.0, 14.0, shore_d);
	vec3 w = waves(wpos.xz, TIME);
	VERTEX.y += w.x * a;
	NORMAL = normalize(vec3(-w.y * a, 1.0, -w.z * a));
	crest = clamp(w.x / 1.6, 0.0, 1.0) * (1.0 - calm);
}

void fragment() {
	vec3 sh = sample_shore(wpos);
	float c_calm = sh.g;
	float d = sh.r * 48.0;
	vec2 uv = wpos.xz;
	float t = TIME;
	vec3 na = texture(normal_a, uv * 0.045 + vec2(t * 0.012, t * 0.007)).rgb;
	vec3 nb = texture(normal_b, uv * 0.11 + vec2(-t * 0.018, t * 0.021)).rgb;
	vec3 nm = normalize(mix(na, nb, 0.5) * 2.0 - 1.0);
	nm.xy *= mix(1.0, 0.45, c_calm);
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	float dist = length(wpos - CAMERA_POSITION_WORLD);
	// Cor: azul profundo ao largo, turquesa junto à costa e dentro do porto
	vec3 col = mix(deep_color, open_color, smoothstep(2500.0, 200.0, dist));
	col = mix(col, shallow_color, (1.0 - smoothstep(4.0, 40.0, d)) * 0.75 + c_calm * 0.25);
	// Fresnel: de longe ou rasante a água reflete o céu
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	col = mix(col, sky_tint, clamp(fres * 0.85, 0.0, 0.85));

	// Espuma: faixa junto ao cais (pulsando) e nas cristas do mar aberto
	float n1 = texture(normal_a, uv * 0.21 + vec2(t * 0.03, 0.0)).r;
	float shore_foam = (1.0 - smoothstep(0.6, 2.6 + 0.8 * sin(t * 1.3 + uv.x * 0.15), d + n1 * 1.5)) * step(0.01, d + 0.02);
	float n2 = texture(normal_b, uv * 0.37 + vec2(0.0, t * 0.025)).g;
	float crest_foam = smoothstep(0.82, 0.97, crest + (n2 - 0.5) * 0.25) * (1.0 - smoothstep(120.0, 500.0, dist));
	float foam = clamp(shore_foam + crest_foam * 0.45, 0.0, 1.0);
	col = mix(col, foam_color, foam);

	ALBEDO = col;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ROUGHNESS = mix(0.004, 0.006, foam);
}
