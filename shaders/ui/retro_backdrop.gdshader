shader_type canvas_item;
// Fundo synthwave dos menus (estático): céu escuro em degradê, "sol" brilhando no horizonte,
// brilho difuso no canto superior esquerdo e grade em perspectiva no chão que some antes do
// horizonte. Cores vêm da paleta do tema (Retro).

uniform vec4 bg : source_color = vec4(0.05, 0.01, 0.13, 1.0);
uniform vec4 bg_2 : source_color = vec4(0.07, 0.02, 0.18, 1.0);
uniform vec4 horizon : source_color = vec4(1.0, 0.16, 0.43, 1.0);
uniform vec4 accent : source_color = vec4(1.0, 0.16, 0.43, 1.0);
uniform vec4 accent_3 : source_color = vec4(0.83, 0.0, 0.77, 1.0);
uniform float alpha = 0.82;
// Altura do horizonte (0 = topo, 1 = base) e quanto a grade sobe
uniform float horizon_y = 0.6;

// 1 na linha (inteiro mais próximo), com ~1 px de largura na tela
float grid_line(float x) {
	float w = fwidth(x);
	float f = abs(fract(x - 0.5) - 0.5);
	return 1.0 - smoothstep(0.0, w * 1.3, f);
}

void fragment() {
	vec2 uv = UV;
	float aspect = 1.0 / max(SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y, 0.0001);
	// 3. céu: escuro no topo, levemente tingido pelo horizonte embaixo
	vec3 col = mix(bg.rgb, bg_2.rgb, smoothstep(0.0, 0.55, uv.y));
	col = mix(col, mix(bg.rgb, horizon.rgb, 0.09), smoothstep(0.55, 1.0, uv.y));
	// 2. brilho difuso no canto superior esquerdo
	vec2 c2 = (uv - vec2(0.1, -0.1)) * vec2(aspect, 1.0) / vec2(0.9, 0.55);
	col += accent_3.rgb * 0.14 * (1.0 - smoothstep(0.0, 1.0, length(c2)));
	// 1. "sol": elipse brilhante centrada no rodapé
	vec2 s = (uv - vec2(0.5, 1.0)) / vec2(0.55, 0.32);
	col += horizon.rgb * 0.26 * (1.0 - smoothstep(0.0, 1.0, length(s)));
	// Grade em perspectiva (estática)
	float a = alpha;
	if (uv.y > horizon_y) {
		float d = uv.y - horizon_y;
		float z = 0.06 / d;
		float gx = (uv.x - 0.5) * aspect * z * 75.0;
		float gz = z * 50.0;
		float lines = max(grid_line(gx), grid_line(gz));
		// some antes de chegar ao horizonte
		float fade = smoothstep(0.02, 0.5, d / (1.0 - horizon_y));
		col = mix(col, accent.rgb, lines * fade * 0.42);
	}
	COLOR = vec4(col, a);
}
