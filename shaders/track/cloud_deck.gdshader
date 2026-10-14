// Tapete de nuvens bem abaixo da Sky Aerobase: plano enorme com nuvens procedurais (fbm) cheias de
// buracos por onde se vê o mar. De perto e de cima mostra os furos; para o horizonte vai fechando
// (vira um mar de nuvens). Lado iluminado e sombra vêm do período do dia (SkyWorld.apply_mood).
shader_type spatial;
render_mode diffuse_toon, specular_disabled, shadows_disabled, cull_disabled;

uniform vec4 lit_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shade_color : source_color = vec4(0.68, 0.75, 0.93, 1.0);
uniform float coverage = 0.5;
uniform float scale = 1400.0;
uniform vec2 wind = vec2(4.0, 2.5);
uniform vec3 center = vec3(0.0);
global uniform float night;

varying vec3 wpos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 5; k++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = (wpos.xz + TIME * wind) / scale;
	float n = fbm(q);
	float far = smoothstep(2500.0, 14000.0, length(wpos.xz - center.xz));
	float cover = mix(coverage, 0.95, far);
	float d = smoothstep(1.0 - cover - 0.06, 1.0 - cover + 0.1, n);
	if (d < 0.35) {
		discard;
	}
	// Relevo: o miolo mais grosso fica mais claro (topo das nuvens ao sol), as bordas na sombra
	float top = smoothstep(0.0, 0.8, d) * (0.6 + 0.4 * fbm(q * 3.1 + 4.0));
	vec3 c = mix(shade_color.rgb, lit_color.rgb, top);
	ALBEDO = c * mix(1.0, 0.2, night);
	EMISSION = shade_color.rgb * 0.06 * (1.0 - night);
	ROUGHNESS = 1.0;
	RIM = 0.3;
	RIM_TINT = 1.0;
}
