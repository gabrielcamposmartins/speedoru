// Corais, algas, anêmonas, capim do mar, musgo, algas penduradas e pedras do recife (SeaReef): toon
// com a cor da instância (INSTANCE_CUSTOM.rgb), escura na base e clareando para um tom mais quente nas
// pontas (COLOR.b), balanço da corrente pesado por COLOR.r (0 na base, 1 nas pontas) e pela força da
// instância (INSTANCE_CUSTOM.a), um pouco de luz própria (a cor atravessando o coral: na luz azulada
// da água os vermelhos e laranjas apagavam) e pólipos brilhando de leve, mais à noite (COLOR.g). O
// alfa da cor de vértice escolhe o desenho na superfície (na posição da peça, então acompanha a
// escala): 0 = sulcos de coral-cérebro, 0,25 = pedra manchada com musgo por cima, 0,5 = pontinhos de
// pólipos, 0,85 = cavidade escura (o miolo dos tubos), 1 = liso. Sem contorno anime (rugosidade 0).
shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_disabled;

global uniform float night;

varying vec3 tint;
varying vec3 lpos;
varying float polyp;
varying float shade;
varying float pattern;

float coral_hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float coral_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(coral_hash(i), coral_hash(i + vec3(1.0, 0.0, 0.0)), u.x);
	float b = mix(coral_hash(i + vec3(0.0, 1.0, 0.0)), coral_hash(i + vec3(1.0, 1.0, 0.0)), u.x);
	float c = mix(coral_hash(i + vec3(0.0, 0.0, 1.0)), coral_hash(i + vec3(1.0, 0.0, 1.0)), u.x);
	float d = mix(coral_hash(i + vec3(0.0, 1.0, 1.0)), coral_hash(i + vec3(1.0, 1.0, 1.0)), u.x);
	return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

void vertex() {
	lpos = VERTEX;
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = dot(o.xz, vec2(0.13, 0.17));
	float w = COLOR.r * INSTANCE_CUSTOM.a;
	VERTEX.x += sin(TIME * 0.9 + ph + VERTEX.y * 0.7) * w * 0.3;
	VERTEX.z += cos(TIME * 0.7 + ph * 1.3 + VERTEX.y * 0.6) * w * 0.22;
	// (semente por instância no desenho, para as peças iguais não ficarem idênticas)
	lpos += vec3(fract(ph * 7.31) * 17.0, 0.0, fract(ph * 3.17) * 13.0);
	tint = INSTANCE_CUSTOM.rgb;
	polyp = COLOR.g;
	shade = COLOR.b;
	pattern = COLOR.a;
}

void fragment() {
	vec3 tip = tint * 1.08 + vec3(0.07, 0.05, 0.02);
	vec3 col = mix(tint * 0.48, tip, smoothstep(0.2, 1.0, shade));
	float glow = polyp;
	float own = 0.1;
	if (pattern < 0.12) {
		// Coral-cérebro: sulcos serpenteando, escuros no fundo
		float g = sin(lpos.x * 26.0 + sin(lpos.z * 17.0 + lpos.y * 11.0) * 2.6) + sin(lpos.z * 23.0 + sin(lpos.x * 13.0) * 2.2);
		float ridge = smoothstep(0.15, 0.9, abs(g));
		col *= mix(0.55, 1.08, ridge);
		glow *= ridge;
	} else if (pattern < 0.37) {
		// Pedra: manchas claras e escuras, pontinhos de líquen e musgo nas faces de cima
		float m = coral_noise(lpos * 3.0) * 0.6 + coral_noise(lpos * 9.0) * 0.4;
		col *= mix(0.72, 1.12, m);
		float lichen = step(0.82, coral_noise(lpos * 22.0));
		col = mix(col, vec3(0.78, 0.72, 0.52), lichen * 0.45);
		float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
		float moss = smoothstep(0.25, 0.7, up + (coral_noise(lpos * 4.0) - 0.5) * 0.7);
		col = mix(col, vec3(0.2, 0.36, 0.14) * mix(0.8, 1.2, coral_noise(lpos * 14.0)), moss * 0.85);
		own = 0.02;
	} else if (pattern < 0.75) {
		// Pólipos: pontinhos mais claros (e que brilham um pouco à noite)
		vec3 c = fract(lpos * 21.0) - 0.5;
		float dots = 1.0 - smoothstep(0.17, 0.3, length(c));
		col = mix(col, col * 1.4 + vec3(0.06), dots * 0.55);
		glow = max(glow, dots * 0.25);
	} else if (pattern < 0.95) {
		// Cavidade (o miolo dos tubos): quase preta, sem luz própria
		col = tint * 0.12;
		own = 0.0;
	}
	ALBEDO = col;
	EMISSION = col * (own + glow * (0.08 + 1.4 * night));
	ROUGHNESS = 0.0;
	// (sem reflexo do céu: com rugosidade 0 ele virava um espelho)
	SPECULAR = 0.0;
	RIM = 0.3;
	RIM_TINT = 0.6;
}
