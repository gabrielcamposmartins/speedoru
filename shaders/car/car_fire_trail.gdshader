shader_type spatial;
// Fogo no chão atrás das rodas traseiras (rastro "Fogo no chão" do CarParticles), em duas fitas que
// queimam e apagam com a idade (alfa da cor de vértice):
//  * band = false: brilho deitado no asfalto (TrailRibbon GROUND);
//  * band = true: a faixa de chamas contínua (TrailRibbon BILLBOARD, virada para a câmera), com
//    línguas de fogo tremulando nas bordas.
// UV.x vai de uma borda à outra; o ruído corre no mundo, então o fogo fica parado enquanto tremula.
// Alfa pré-multiplicado: soma luz e cobre um pouco (de dia o laranja não vira branco).
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled;

uniform bool band = false;

varying vec3 wpos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = UV.x * 2.0 - 1.0;
	float life = COLOR.a;
	if (band) {
		float nb = noise(wpos.xz * 2.4 + vec2(0.0, -TIME * 5.0)) * 0.6 + noise(wpos.xz * 5.5 + wpos.y * 3.0 - TIME * 7.5) * 0.4;
		float body = 1.0 - smoothstep(0.05 + 0.5 * nb, 1.0, abs(u));
		float hb = body * (0.45 + 0.9 * nb) * life;
		vec3 cb = mix(vec3(0.7, 0.06, 0.0), vec3(1.0, 0.45, 0.04), smoothstep(0.1, 0.45, hb));
		cb = mix(cb, vec3(1.0, 0.9, 0.6), smoothstep(0.6, 0.95, hb));
		ALBEDO = cb * hb * 1.7;
		ALPHA = clamp(hb * 0.7, 0.0, 1.0);
	} else {
		float n = noise(wpos.xz * 1.7 + vec2(TIME * 1.3, -TIME * 2.6)) * 0.65 + noise(wpos.xz * 4.1 - TIME * 3.0) * 0.35;
		float across = 1.0 - smoothstep(0.15 + 0.35 * n, 1.0, abs(u));
		float heat = across * (0.35 + 0.9 * n) * life;
		vec3 c = mix(vec3(0.6, 0.04, 0.0), vec3(1.0, 0.42, 0.03), smoothstep(0.12, 0.5, heat));
		c = mix(c, vec3(1.0, 0.88, 0.55), smoothstep(0.65, 1.0, heat));
		ALBEDO = c * heat * 1.6;
		ALPHA = clamp(heat * 0.6, 0.0, 1.0);
	}
}
