shader_type canvas_item;
// Fundo dos menus no estilo Speedoru: azul-noite em diagonal (tinta → roxo), brilho magenta no
// canto superior direito e ciano no inferior esquerdo, linhas de velocidade inclinadas que
// correm devagar e uma retícula (meio-tom) magenta crescendo para o canto inferior direito.
// Cores vêm da paleta do tema (Retro, estilo "speedoru").

uniform vec4 bg : source_color = vec4(0.05, 0.05, 0.08, 1.0);
uniform vec4 bg_2 : source_color = vec4(0.12, 0.07, 0.26, 1.0);
uniform vec4 horizon : source_color = vec4(1.0, 0.17, 0.84, 1.0);
uniform vec4 accent : source_color = vec4(1.0, 0.17, 0.84, 1.0);
uniform vec4 accent_2 : source_color = vec4(0.0, 0.91, 1.0, 1.0);
uniform vec4 accent_3 : source_color = vec4(0.64, 0.35, 1.0, 1.0);
uniform float alpha = 0.82;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float aspect = 1.0 / max(SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y, 0.0001);
	vec2 p = vec2(uv.x * aspect, uv.y);
	// Base: diagonal da tinta (alto à esquerda) ao roxo-noite (baixo à direita)
	vec3 col = mix(bg.rgb, bg_2.rgb, smoothstep(0.0, 1.0, (uv.x + uv.y) * 0.6));
	// Brilhos difusos nos cantos
	vec2 g1 = (uv - vec2(1.0, 0.0)) * vec2(aspect, 1.0) / vec2(1.0, 0.7);
	col += accent.rgb * 0.16 * (1.0 - smoothstep(0.0, 1.0, length(g1)));
	vec2 g2 = (uv - vec2(0.0, 1.0)) * vec2(aspect, 1.0) / vec2(0.9, 0.6);
	col += accent_2.rgb * 0.10 * (1.0 - smoothstep(0.0, 1.0, length(g2)));
	// Faixa diagonal larga e fraca em roxo
	float band = abs((uv.x * aspect * 0.35 - uv.y) + 0.15);
	col = mix(col, accent_3.rgb, 0.07 * (1.0 - smoothstep(0.08, 0.2, band)));

	// Linhas de velocidade: trilhos inclinados; em alguns corre um traço com cauda
	float ang = -0.33;
	mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
	vec2 q = rot * p;
	float rows = 46.0;
	float row = floor(q.y * rows);
	float r = hash(row);
	if (r > 0.55) {
		float fy = fract(q.y * rows);
		float w = fwidth(q.y * rows);
		float thick = 0.08 + 0.1 * hash(row + 7.0);
		float line_y = 1.0 - smoothstep(thick, thick + w * 1.5, abs(fy - 0.5));
		float speed = 0.05 + 0.12 * hash(row + 3.0);
		float len = 0.12 + 0.3 * hash(row + 11.0);
		float x = fract(q.x * 0.55 - TIME * speed + hash(row + 5.0));
		// Cabeça forte na frente, cauda que some
		float streak = smoothstep(0.0, len, x) * (1.0 - step(len, x));
		vec3 lc = hash(row + 13.0) > 0.5 ? accent.rgb : accent_2.rgb;
		col = mix(col, lc, line_y * streak * 0.32);
	}

	// Retícula magenta: pontos que crescem em direção ao canto inferior direito
	float cell = 0.018;
	vec2 hp = rot * p / cell;
	vec2 cid = floor(hp);
	vec2 f = fract(hp) - 0.5;
	vec2 c_uv = (inverse(rot) * ((cid + 0.5) * cell));
	vec2 to_corner = vec2(aspect, 1.0) - c_uv;
	float d = length(to_corner / vec2(0.75, 0.6));
	float radius = 0.42 * (1.0 - smoothstep(0.0, 1.0, d));
	float dot_px = fwidth(hp.x);
	float dots = 1.0 - smoothstep(radius - dot_px, radius + dot_px, length(f));
	col = mix(col, accent.rgb, dots * 0.28);

	COLOR = vec4(col, alpha);
}
