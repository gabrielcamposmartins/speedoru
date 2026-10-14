// Anúncios em holograma da Sky Aerobase: o fundo de cada marca some (transparente), as letras e o
// desenho ficam flutuando, acesos, e cada anúncio ganha uma faixa em cima e outra embaixo na cor da
// marca (nunca branca). Linhas de varredura subindo e uma leve cintilação.
//   scrolling = true (faixa das barreiras): UV.x = metros ao longo da faixa (do lado direito ao
//     contrário, para o texto ler certo), UV.y 0 embaixo e 1 em cima; a cada `panel_length` m vem
//     uma marca, na ordem de `rects`, e a faixa toda anda a `speed` m/s;
//   scrolling = false (pórticos, boxes, arquibancadas): UV é a do atlas; a marca sai da posição
//     (fora das marcas, ex. placas de frenagem, desenha o atlas normal).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 rects[16];
uniform vec3 bg[16];
uniform vec3 text[16];
uniform vec3 band[16];
uniform int count = 16;
uniform vec2 grid = vec2(4.0, 8.0);
uniform bool scrolling = true;
uniform float panel_length = 12.0;
uniform float speed = 7.0;
uniform float energy = 1.5;
global uniform float night;

void fragment() {
	int brand = -1;
	vec2 auv;
	float local_v;
	float u;
	float k = 0.0;
	if (scrolling) {
		float t = (UV.x + TIME * speed) / panel_length;
		k = floor(t);
		brand = int(mod(k, float(max(count, 1))));
		u = fract(t);
		local_v = UV.y;
		vec4 r = rects[brand];
		auv = vec2(r.x + u * r.z, r.y + (1.0 - UV.y) * r.w);
	} else {
		auv = UV;
		vec2 cellf = floor(UV * grid);
		int idx = int(cellf.y) * int(grid.x) + int(cellf.x);
		brand = idx < count ? idx : -1;
		vec2 f = fract(UV * grid);
		u = f.x;
		local_v = 1.0 - f.y;
		k = float(idx);
	}
	vec3 ad = texture(atlas, auv).rgb;
	if (brand < 0) {
		ALBEDO = ad;
		ALPHA = 1.0;
	} else {
		// Recorte: o que tem a cor do fundo da marca some; o resto flutua
		float key = smoothstep(0.1, 0.28, distance(ad, bg[brand]));
		// Letras brancas ou pretas viram a cor de destaque da marca (no ar, branco some e preto não aparece)
		vec3 glyph = (distance(ad, vec3(1.0)) < 0.25 || length(ad) < 0.22) ? text[brand] : ad;
		// Faixas delimitadoras em cima e embaixo, na cor da marca
		float edge = smoothstep(0.88, 0.92, local_v) + smoothstep(0.12, 0.08, local_v);
		float scan = 0.8 + 0.2 * sin(local_v * 50.0 - TIME * 8.0);
		float flicker = 0.93 + 0.07 * sin(TIME * 29.0 + k * 1.7) * sin(TIME * 13.0);
		float gap = scrolling ? smoothstep(0.0, 0.01, u) * smoothstep(1.0, 0.99, u) : 1.0;
		float inside = (1.0 - clamp(edge, 0.0, 1.0));
		vec3 c = mix(glyph * scan, band[brand], clamp(edge, 0.0, 1.0)) * flicker;
		ALBEDO = c * energy * mix(1.0, 1.4, night);
		ALPHA = clamp(max(key * inside * 0.95, edge), 0.0, 1.0) * gap;
	}
}
