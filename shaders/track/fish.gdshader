// Peixinhos dos cardumes (SeaLife): corpo fusiforme, cauda em forquilha e nadadeiras; a cauda abana
// (COLOR.r = peso) e cada peixe oscila um pouco em volta do lugar dele no cardume. INSTANCE_CUSTOM:
// x, y = fase; z = espécie, com o desenho dela pela posição no corpo (frente em +Z):
//   < 0,25 cirurgião-amarelo (amarelo com o espinho branco perto da cauda);
//   < 0,5  cirurgião-azul (azul com a faixa escura em cima e a cauda amarela);
//   < 0,8  sardinha (prateada, dorso azul-acinzentado e a linha lateral);
//   senão  palhaço (laranja com três faixas brancas de borda preta).
// Toon com o ventre claro (COLOR.g) e um pouco de luz própria.
shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_disabled;

varying float belly;
varying float kind;
varying vec3 lp;

void vertex() {
	lp = VERTEX;
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float t = TIME * (7.0 + INSTANCE_CUSTOM.y * 4.0) + ph;
	VERTEX.x += sin(t) * 0.09 * COLOR.r;
	// Cada peixe vai e volta um pouco no cardume
	VERTEX += vec3(sin(TIME * 0.7 + ph) * 0.5, sin(TIME * 0.9 + ph * 1.3) * 0.3, cos(TIME * 0.6 + ph) * 0.5);
	kind = INSTANCE_CUSTOM.z;
	belly = COLOR.g;
}

void fragment() {
	vec3 col;
	vec3 under = vec3(0.95, 0.96, 0.98);
	if (kind < 0.25) {
		col = vec3(1.0, 0.8, 0.1);
		// Espinho branco no pedúnculo
		col = mix(col, under, (1.0 - smoothstep(0.012, 0.025, abs(lp.z + 0.13))) * step(abs(lp.y), 0.03));
		under = vec3(1.0, 0.9, 0.5);
	} else if (kind < 0.5) {
		col = vec3(0.12, 0.38, 0.95);
		// Faixa escura (a "paleta") em cima e a cauda amarela
		float band = smoothstep(0.03, 0.045, lp.y) * (1.0 - smoothstep(0.075, 0.09, lp.y)) * smoothstep(-0.14, -0.08, lp.z);
		col = mix(col, vec3(0.03, 0.05, 0.14), band);
		col = mix(col, vec3(1.0, 0.82, 0.12), smoothstep(-0.17, -0.19, lp.z));
		under = vec3(0.4, 0.62, 1.0);
	} else if (kind < 0.8) {
		col = vec3(0.32, 0.45, 0.58);
		// Linha lateral escura e o flanco prateado
		col = mix(col, vec3(0.78, 0.84, 0.9), smoothstep(0.02, -0.01, lp.y));
		col *= 1.0 - 0.35 * (1.0 - smoothstep(0.004, 0.01, abs(lp.y - 0.012)));
	} else {
		col = vec3(1.0, 0.42, 0.08);
		// Três faixas brancas com a borda preta
		float d = min(min(abs(lp.z - 0.15), abs(lp.z - 0.0)), abs(lp.z + 0.135));
		float white = 1.0 - smoothstep(0.018, 0.024, d);
		float edge = (1.0 - smoothstep(0.026, 0.032, d)) * (1.0 - white);
		col = mix(col, vec3(0.97), white);
		col = mix(col, vec3(0.04), edge);
		under = col;
	}
	col = mix(col, under, belly * 0.6);
	ALBEDO = col;
	// (um pouco de luz própria: na luz azulada da água o laranja do palhaço e o amarelo viravam oliva)
	EMISSION = col * 0.14;
	ROUGHNESS = 0.4;
	RIM = 0.4;
	RIM_TINT = 0.5;
}
