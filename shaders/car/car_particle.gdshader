shader_type spatial;
// Partículas do rastro equipável (CarParticles): a forma é desenhada aqui, sem textura — bolha de
// sabão, estrela, chama, raio, pétala de sakura, floco de neve, moeda, faísca, fumaça e brasa.
// Alfa pré-multiplicado: ALPHA 0 soma luz (brilho), ALPHA 1 cobre (moeda, pétala, fumaça).
// Partículas: INSTANCE_CUSTOM.x = giro (rad), INSTANCE_CUSTOM.y = idade (0..1); COLOR = cor da
// partícula (tom inicial × rampa de cor, com o alfa sumindo).
// orient: 0 = virada para a câmera (com o giro), 1 = comprida na direção do movimento (faísca;
// precisa de particle_flag_align_y), 2 = em pé (eixo Y do mundo: chama, raio que cai no chão).
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled;

uniform int shape = 1;
uniform int orient = 0;
uniform float intensity = 1.0;

varying float age;
varying flat float seed;

float hash1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.55 + noise(p * 2.1 + 3.7) * 0.3 + noise(p * 4.3 + 7.1) * 0.15;
}

mat2 rot(float a) {
	return mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
}

// Estrela de 5 pontas (distância com sinal; Inigo Quilez)
float star5(vec2 p, float r, float rf) {
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-0.809016994375, -0.587785252292);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

void vertex() {
	age = INSTANCE_CUSTOM.y;
	seed = hash1(float(INSTANCE_ID) * 1.618 + 0.37);
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - origin);
	if (orient == 0) {
		mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
		float a = INSTANCE_CUSTOM.x;
		w = w * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * w * mat4(vec4(scale.x, 0.0, 0.0, 0.0), vec4(0.0, scale.y, 0.0, 0.0), vec4(0.0, 0.0, scale.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	} else {
		vec3 up = orient == 1 ? MODEL_MATRIX[1].xyz / max(scale.y, 1e-5) : vec3(0.0, 1.0, 0.0);
		vec3 right = cross(up, to_cam);
		right = length(right) > 1e-4 ? normalize(right) : normalize(INV_VIEW_MATRIX[0].xyz);
		vec3 fwd = cross(right, up);
		mat4 w = mat4(vec4(right * scale.x, 0.0), vec4(up * scale.y, 0.0), vec4(fwd * scale.z, 0.0), MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * w;
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	vec3 tint = COLOR.rgb;
	float fade = COLOR.a;
	vec3 col = vec3(0.0);
	float cover = 0.0;
	float t = TIME;
	if (shape == 0) {
		// Bolha de sabão: aro iridescente, miolo quase transparente e reflexos; estoura no fim
		float pop = smoothstep(0.86, 1.0, age);
		vec2 q = p * mix(1.0, 0.82, pop);
		float r = length(q);
		float ang = atan(q.y, q.x);
		float rim = smoothstep(0.78, 0.92, r) * (1.0 - smoothstep(0.92, 1.0, r));
		float body = (1.0 - smoothstep(0.9, 1.0, r)) * 0.1;
		vec3 iri = 0.5 + 0.5 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + ang * 0.16 + r * 1.3 + t * 0.35 + seed * 3.0));
		vec3 film = mix(vec3(1.0), iri, 0.7) * tint;
		float hi = smoothstep(0.2, 0.02, length(q - vec2(-0.36, 0.42)));
		float hi2 = smoothstep(0.1, 0.0, length(q - vec2(0.38, -0.4))) * 0.5;
		// Estourando: o aro vira gotinhas e some
		float dash = mix(1.0, step(0.55, fract(ang * 1.9 + seed * 5.0)), pop);
		float keep = 1.0 - smoothstep(0.55, 1.0, pop);
		rim *= dash;
		col = (film * (rim * 1.1 + body) + vec3(hi + hi2) * (1.0 - pop)) * keep;
		cover = (rim * 0.35 + body * 0.4 + hi * 0.5) * keep;
	} else if (shape == 1) {
		// Estrela de 5 pontas (ou brilho de 4 pontas) piscando
		float tw = 0.65 + 0.35 * sin(t * 9.0 + seed * 40.0);
		if (seed > 0.62) {
			float sx = exp(-abs(p.x) * 16.0) * (1.0 - abs(p.y));
			float sy = exp(-abs(p.y) * 16.0) * (1.0 - abs(p.x));
			float core = exp(-dot(p, p) * 14.0);
			float a = clamp((sx + sy) * 1.2 + core, 0.0, 1.5) * tw;
			col = mix(tint, vec3(1.0), core) * a * 1.6;
			cover = clamp(core * 0.6, 0.0, 1.0);
		} else {
			float d = star5(p, 0.66, 0.46) - 0.07;
			float fill = smoothstep(0.03, -0.03, d);
			float glow = exp(-max(d, 0.0) * 6.0) * 0.55;
			float inner = smoothstep(0.0, -0.32, d);
			col = (mix(tint, vec3(1.0), inner * 0.55) * fill * 1.3 + tint * glow) * tw;
			cover = fill * 0.75;
		}
	} else if (shape == 2) {
		// Chama: gota que afina para cima, distorcida por ruído subindo; núcleo claro
		float y = p.y * 0.5 + 0.5;
		float n = fbm(vec2(p.x * 1.6 + seed * 9.0, y * 2.2 - t * 3.2 - seed * 5.0));
		float sway = (n - 0.5) * 0.9 * y;
		float wid = 0.7 * pow(max(1.0 - y, 0.0), 0.75) * smoothstep(-0.12, 0.22, y);
		float d = abs(p.x - sway) / max(wid, 1e-3);
		float body = 1.0 - smoothstep(0.45, 1.0, d + (n - 0.5) * 0.6 * y);
		float heat = body * (1.0 - y * 0.75) * (1.0 - age * 0.5);
		vec3 c = mix(vec3(0.85, 0.08, 0.01), vec3(1.0, 0.45, 0.04), smoothstep(0.1, 0.45, heat));
		c = mix(c, vec3(1.0, 0.92, 0.6), smoothstep(0.55, 0.9, heat));
		col = c * tint * body * 1.6;
		cover = body * 0.6;
	} else if (shape == 3) {
		// Raio: caminho em zigue-zague (sorteado de novo ~20 vezes por segundo) com um galho
		float s2 = seed * 91.0 + floor(t * 20.0 + seed * 7.0);
		float yy = (p.y * 0.5 + 0.5) * 7.0;
		float k = floor(yy);
		float f = fract(yy);
		float x0 = (hash2(vec2(k, s2)) - 0.5) * (k < 0.5 ? 0.15 : 0.75);
		float x1 = (hash2(vec2(k + 1.0, s2)) - 0.5) * (k > 5.5 ? 0.15 : 0.75);
		float d = abs(p.x - mix(x0, x1, f));
		// Galho: sai do meio e vai para o lado
		float side = hash2(vec2(s2, 3.0)) > 0.5 ? 1.0 : -1.0;
		float by = clamp((0.15 - p.y) / 0.8, 0.0, 1.0);
		float bx = mix(x0, x1, f) + side * by * 0.55 + (noise(vec2(p.y * 9.0, s2)) - 0.5) * 0.12;
		float branch = (p.y < 0.15 && p.y > -0.65) ? abs(p.x - bx) : 9.0;
		float ends = smoothstep(1.0, 0.82, abs(p.y));
		float core = (smoothstep(0.07, 0.0, d) + smoothstep(0.045, 0.0, branch) * 0.7) * ends;
		float glow = (exp(-d * 10.0) + exp(-branch * 14.0) * 0.5) * ends;
		float on = step(0.3, hash2(vec2(floor(t * 26.0), seed * 13.0)));
		col = (vec3(1.0) * core * 1.5 + tint * glow * 1.4) * on;
		cover = clamp(core * 0.8 + glow * 0.35, 0.0, 1.0) * on;
	} else if (shape == 4) {
		// Pétala de sakura girando (o achatamento em x imita a pétala virando)
		float flip = 0.3 + 0.7 * abs(sin(t * 3.2 + seed * 20.0));
		vec2 q = vec2(p.x / flip, p.y);
		float oval = length(vec2(q.x * 1.3, q.y * 0.95 + 0.05));
		float notch = 1.0 - smoothstep(0.24, 0.3, length(vec2(q.x, q.y - 1.0)));
		float inside = (1.0 - smoothstep(0.84, 0.92, oval)) * (1.0 - notch);
		vec3 c = mix(tint * 0.78, mix(tint, vec3(1.0), 0.45), smoothstep(-0.9, 0.7, p.y));
		c *= 0.8 + 0.3 * flip;
		col = c * inside;
		cover = inside;
	} else if (shape == 5) {
		// Floco de neve: seis braços com galhos
		float r = length(p);
		float a = atan(p.y, p.x);
		float a3 = abs(mod(a + 0.5236, 1.0472) - 0.5236);
		vec2 q = r * vec2(cos(a3), sin(a3));
		float d = q.x < 0.86 ? abs(q.y) : length(q - vec2(0.86, 0.0));
		for (int i = 0; i < 2; i++) {
			float bx = i == 0 ? 0.5 : 0.28;
			float bl = i == 0 ? 0.26 : 0.16;
			vec2 o = q - vec2(bx, 0.0);
			vec2 dir = vec2(0.5, 0.866);
			float h = clamp(dot(o, dir), 0.0, bl);
			d = min(d, length(o - dir * h));
		}
		d = min(d, abs(r - 0.14));
		float line = smoothstep(0.06, 0.02, d);
		float glow = exp(-d * 9.0) * 0.4 * (1.0 - smoothstep(0.85, 1.0, r));
		float tw = 0.8 + 0.2 * sin(t * 5.0 + seed * 30.0);
		col = mix(tint, vec3(1.0), line * 0.6) * (line + glow) * tw;
		cover = line * 0.55;
	} else if (shape == 6) {
		// Moeda de ouro girando, com uma estrela em relevo e um brilho
		float spin = cos(t * 9.0 + seed * 30.0);
		float w = max(abs(spin), 0.1);
		vec2 q = vec2(p.x / w, p.y);
		float r = length(q);
		float disc = 1.0 - smoothstep(0.86, 0.93, r);
		float edge = smoothstep(0.7, 0.76, r);
		float st = smoothstep(0.02, -0.02, star5(q, 0.42, 0.45));
		vec3 gold = tint;
		float shade = 0.75 + 0.3 * q.y * sign(spin) + 0.15 * spin;
		vec3 c = gold * shade;
		c = mix(c, gold * 0.62, edge);
		c = mix(c, gold * 1.25, st * (1.0 - edge));
		// Faixa de brilho que passa enquanto gira; lado de trás mais escuro
		c += vec3(1.0, 0.95, 0.75) * smoothstep(0.18, 0.0, abs(q.x + q.y * 0.5 - spin * 0.9)) * 0.5;
		c *= spin > 0.0 ? 1.0 : 0.8;
		col = c * disc;
		cover = disc;
	} else if (shape == 7) {
		// Faísca: risco claro com cauda (comprida na direção do movimento)
		float across = exp(-p.x * p.x * 26.0);
		float along = smoothstep(-1.0, 0.75, p.y) * (1.0 - smoothstep(0.75, 1.0, p.y));
		float hot = across * along;
		vec3 c = mix(tint, vec3(1.0, 0.97, 0.85), smoothstep(0.55, 1.0, hot) * (1.0 - age));
		col = c * hot * 2.2;
		cover = hot * 0.5;
	} else if (shape == 8) {
		// Fumaça: nuvem macia com ruído (cobre, na cor da partícula)
		float r = length(p);
		float n = fbm(p * 1.8 + vec2(seed * 7.0, seed * 3.0) + vec2(0.0, -t * 0.25));
		float dens = (1.0 - smoothstep(0.25, 1.0, r + (n - 0.5) * 0.55)) * (1.0 - smoothstep(0.75, 1.0, r));
		vec3 c = tint * (0.75 + 0.45 * n);
		float a = dens * 0.6;
		col = c * a;
		cover = a;
	} else {
		// Brasa: ponto quente que tremeluz
		float r = length(p);
		float core = exp(-r * r * 22.0);
		float glow = exp(-r * 4.5) * 0.45 * (1.0 - smoothstep(0.7, 1.0, r));
		float fl = 0.7 + 0.3 * sin(t * 17.0 + seed * 50.0);
		col = (mix(tint, vec3(1.0, 0.9, 0.6), core) * core * 1.6 + tint * glow) * fl;
		cover = clamp(core * 0.8 + glow * 0.5, 0.0, 1.0);
	}
	// Some perto da câmera (as partículas que passam pela câmera de perseguição não tapam a vista)
	fade *= smoothstep(0.5, 2.2, length(VERTEX));
	ALBEDO = col * fade * intensity;
	ALPHA = clamp(cover * fade, 0.0, 1.0);
}
