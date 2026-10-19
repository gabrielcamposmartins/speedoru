// Água do Portão de Poseidon (trecho emerso da Atlantis Abyss):
//   mode 0: lâmina de cachoeira (UV.x = 0..1 na largura, UV.y = 0 no alto .. 1 embaixo): filetes
//           claros rolando para baixo, bordas transparentes, espuma onde a água sai e onde cai;
//   mode 1: espuma no pé da cachoeira (disco; UV = posição no disco, 0..1), mexendo;
//   mode 2: faixa de espuma (linha d'água, esteira dos barcos): UV.x ao longo, em metros; UV.y = 0..1
//           através; COLOR.a some ao longo (esteira);
//   mode 3: cortina de cachoeira grande e larga: UV.x em metros na largura, UV.y = 0 no alto .. 1
//           embaixo, COLOR.r = 0 nas bordas da largura (somem) .. 1 no meio; filetes de ~1 m, véus de
//           espuma passando e espuma no alto e no pé;
//   mode 4: névoa no pé da cachoeira grande (UV.x ao longo, 0..1; UV.y = 0 embaixo .. 1 no alto;
//           COLOR.a = força): nuvem branca subindo e mexendo.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;

uniform int mode = 0;
uniform vec3 water_color : source_color = vec3(0.72, 0.9, 1.0);
uniform vec3 foam_color : source_color = vec3(0.97, 0.99, 1.0);
uniform float speed = 1.0;

float wf_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float wf_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(wf_hash(i), wf_hash(i + vec2(1.0, 0.0)), u.x), mix(wf_hash(i + vec2(0.0, 1.0)), wf_hash(i + vec2(1.0)), u.x), u.y);
}

void fragment() {
	float t = TIME * speed;
	vec3 col;
	float a;
	if (mode == 0) {
		float x = UV.x;
		float y = UV.y;
		float edge = smoothstep(0.0, 0.14, x) * (1.0 - smoothstep(0.86, 1.0, x));
		float streak = wf_noise(vec2(x * 22.0, y * 3.0 - t * 2.4));
		float fine = wf_noise(vec2(x * 60.0, y * 9.0 - t * 4.0));
		float foam = smoothstep(0.72, 1.0, y) + (1.0 - smoothstep(0.0, 0.12, y)) * 0.6;
		col = mix(water_color, foam_color, clamp(streak * 0.55 + fine * 0.25 + foam, 0.0, 1.0));
		a = edge * clamp(0.5 + streak * 0.35 + fine * 0.2 + foam * 0.4, 0.0, 0.95);
	} else if (mode == 1) {
		vec2 q = UV * 2.0 - 1.0;
		float r = length(q);
		float ang = atan(q.y, q.x);
		float churn = wf_noise(vec2(ang * 3.0 + t * 0.6, r * 6.0 - t * 1.5));
		col = foam_color;
		a = (1.0 - smoothstep(0.45, 1.0, r)) * (0.45 + 0.55 * churn);
	} else if (mode == 2) {
		float churn = wf_noise(vec2(UV.x * 0.8 + t * 0.4, UV.y * 4.0 - t * 0.7));
		float band = sin(clamp(UV.y, 0.0, 1.0) * 3.14159);
		col = foam_color;
		a = band * smoothstep(0.35, 0.75, churn) * 0.9 * COLOR.a;
	} else if (mode == 3) {
		float x = UV.x;
		float y = UV.y;
		float streak = wf_noise(vec2(x * 0.9, y * 5.0 - t * 2.6));
		float fine = wf_noise(vec2(x * 2.7, y * 14.0 - t * 4.2));
		float veil = wf_noise(vec2(x * 0.12 + t * 0.05, y * 2.2 - t * 1.1));
		float foam = smoothstep(0.82, 1.0, y) + (1.0 - smoothstep(0.0, 0.06, y)) * 0.7;
		col = mix(water_color, foam_color, clamp(streak * 0.5 + fine * 0.3 + foam + smoothstep(0.55, 0.85, veil) * 0.4, 0.0, 1.0));
		a = COLOR.r * clamp(0.6 + streak * 0.25 + fine * 0.2 + foam * 0.4, 0.0, 0.96);
	} else {
		float n = wf_noise(vec2(UV.x * 7.0 + t * 0.25, UV.y * 3.0 - t * 0.9));
		col = foam_color;
		a = (1.0 - smoothstep(0.1, 1.0, UV.y)) * (0.3 + 0.45 * n) * sin(clamp(UV.x, 0.0, 1.0) * 3.14159) * COLOR.a;
	}
	ALBEDO = col;
	ALPHA = a;
	EMISSION = col * 0.12;
}
