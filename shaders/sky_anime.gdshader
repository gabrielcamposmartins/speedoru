// Céu estilo anime: degradê, sol com halo e uma camada de nuvens em duas tonalidades (lado
// iluminado branco, lado na sombra azulado), mais finas perto do horizonte.
// O sol vem da DirectionalLight3D (LIGHT0). Sem TIME: o mapa de radiância não precisa ser
// refeito todo quadro (as nuvens 3D é que se movem).
shader_type sky;
render_mode use_debanding, use_half_res_pass;

uniform vec3 top_color : source_color = vec3(0.13, 0.36, 0.86);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.8, 0.98);
uniform vec3 ground_color : source_color = vec3(0.24, 0.36, 0.25);
uniform float sky_curve : hint_range(0.05, 1.0) = 0.42;
uniform float energy = 1.05;
uniform float sun_size = 0.035;
uniform float sun_halo = 0.35;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_scale = 1.3;
uniform vec3 cloud_lit : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.68, 0.75, 0.93);
uniform vec2 cloud_offset = vec2(3.7, 1.3);
// Noite: estrelas e o disco vira lua (LIGHT0 é a lua à noite)
global uniform float night;
uniform vec3 moon_color : source_color = vec3(0.92, 0.95, 1.0);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += noise(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

float sun_disc(float s) {
	return smoothstep(cos(sun_size), cos(sun_size * 0.85), s);
}

// Céu completo (degradê, halo, nuvens). cloud = cobertura de nuvem nesse ponto.
vec3 sky_color(vec3 d, vec3 sun_dir, bool has_sun, vec3 sun_color, bool draw_disc, out float cloud) {
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), sky_curve));
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-h * 6.0, 0.0, 1.0));
	}
	float s = dot(d, sun_dir);
	cloud = 0.0;
	vec3 cloud_col = cloud_lit;
	if (h > 0.0) {
		// Nuvens projetadas num "teto" plano
		vec2 uv = d.xz / (h + 0.1) * cloud_scale + cloud_offset;
		float n = fbm(uv);
		float threshold = 1.0 - cloud_coverage;
		cloud = smoothstep(threshold, threshold + 0.05, n) * smoothstep(0.0, 0.18, h);
		// Lado virado para o sol mais claro (borda definida, estilo cel)
		float toward_sun = fbm(uv + sun_dir.xz * 0.18);
		float lit = smoothstep(0.0, 0.02, n - toward_sun + 0.02);
		cloud_col = mix(cloud_shade, cloud_lit, lit);
		// Borda clara contornando a nuvem
		cloud_col = mix(cloud_col, cloud_lit * 1.08, smoothstep(threshold + 0.05, threshold, n) * 0.6);
	}
	if (h > 0.0 && night > 0.01) {
		// Estrelas: células na esfera celeste, poucas acesas, mais fortes no alto
		vec3 sd = d * 260.0;
		vec3 cell = floor(sd);
		float hs = hash(cell.xy + cell.z * 17.31);
		vec3 center = cell + 0.5 + (vec3(hash(cell.yz), hash(cell.zx), hs) - 0.5) * 0.6;
		float star = smoothstep(0.16, 0.0, length(sd - center)) * step(0.985, hs);
		col += vec3(0.9, 0.95, 1.0) * star * night * smoothstep(0.0, 0.25, h) * (1.0 - cloud) * 3.0;
	}
	if (has_sun) {
		col += sun_color * pow(max(s, 0.0), 48.0) * sun_halo * (1.0 - night);
		if (draw_disc) {
			vec3 disc_color = mix(sun_color * 4.0, moon_color * 2.2, night);
			col += disc_color * sun_disc(s) * (1.0 - cloud);
		}
	}
	return mix(col, cloud_col, cloud * 0.96) * energy;
}


void sky() {
	vec3 sun_dir = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	if (AT_HALF_RES_PASS) {
		// Nuvens em meia resolução; a cobertura vai no alfa para esconder o sol no passe final
		float cloud;
		COLOR = sky_color(EYEDIR, sun_dir, LIGHT0_ENABLED, LIGHT0_COLOR, false, cloud);
		ALPHA = cloud;
	} else if (AT_CUBEMAP_PASS) {
		float cloud;
		COLOR = sky_color(EYEDIR, sun_dir, LIGHT0_ENABLED, LIGHT0_COLOR, true, cloud);
	} else {
		// Passe final: reaproveita a meia resolução e desenha só o disco do sol nítido
		vec3 base = HALF_RES_COLOR.rgb;
		if (LIGHT0_ENABLED) {
			vec3 disc_color = mix(LIGHT0_COLOR * 4.0, moon_color * 2.2, night);
			base += disc_color * sun_disc(dot(EYEDIR, sun_dir)) * (1.0 - HALF_RES_COLOR.a) * energy;
		}
		COLOR = base;
	}
}
