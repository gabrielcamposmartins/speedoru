shader_type spatial;
// Rastro "Arco-íris" do CarParticles: fita virada para a câmera (TrailRibbon BILLBOARD) com as sete
// faixas de cor de uma borda à outra (UV.x), um brilho correndo e o fim sumindo com a idade (alfa
// da cor de vértice). Alfa pré-multiplicado, como o fogo.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled;

const vec3 BANDS[7] = vec3[7](vec3(1.0, 0.23, 0.23), vec3(1.0, 0.6, 0.12), vec3(1.0, 0.88, 0.23),
	vec3(0.24, 0.86, 0.42), vec3(0.18, 0.6, 1.0), vec3(0.42, 0.36, 1.0), vec3(0.75, 0.3, 1.0));

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = clamp(UV.x, 0.0, 0.9999);
	float f = u * 7.0;
	int k = int(floor(f));
	// Faixas com a divisa levemente suave
	float edge = fract(f);
	vec3 col = BANDS[k];
	if (edge > 0.85 && k < 6) {
		col = mix(col, BANDS[k + 1], (edge - 0.85) / 0.15);
	}
	float life = COLOR.a;
	float shine = 0.85 + 0.15 * sin(dot(wpos, vec3(0.9, 0.3, 0.7)) * 2.0 - TIME * 9.0);
	float side = 1.0 - smoothstep(0.92, 1.0, abs(u * 2.0 - 1.0));
	float a = clamp(life * 1.3, 0.0, 1.0) * side;
	ALBEDO = col * shine * a * 1.25;
	ALPHA = a * 0.85;
}
