// Saída da água (SeaSplash): a câmera acabou de passar da água para o ar. Gotas na lente com a
// imagem refratada atrás delas — muitas pequenas quase paradas e as maiores escorrendo para baixo
// com um rastro — e, no começo, a película d'água descendo pela tela (ondulação, borrão e um clarão,
// clareando de cima para baixo). `strength` cai de 1 a 0 (as gotas secam); `elapsed` em segundos.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;
uniform float elapsed = 0.0;
uniform float seed = 0.0;

float lens_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.17) * 43758.5453);
}

// Uma camada de gotas: `cells` células (quadradas na tela) na largura, `fill` = chance de a célula
// ter gota, `size` = raio (fração da célula), `slide` = células por segundo escorrendo (as que
// escorrem deixam um rastro curto e fino), `dry` = quanto ainda não secou. Devolve o desvio da imagem
// (xy, em UV da tela) e a máscara da gota (z).
vec3 drops(vec2 uv, float aspect, float cells, float fill, float size, float slide, float dry) {
	vec2 grid = vec2(cells, cells / aspect);
	vec2 g = uv * grid;
	vec2 id = floor(g);
	float a = lens_hash(id);
	if (a > fill) {
		return vec3(0.0);
	}
	float b = lens_hash(id + 3.7);
	float c = lens_hash(id + 9.1);
	vec2 f = fract(g);
	vec2 center = vec2(0.25 + 0.5 * b, 0.2 + 0.6 * c + slide * elapsed * (0.4 + 0.8 * b));
	float r = size * (0.55 + 0.45 * a / max(fill, 0.001)) * dry;
	vec2 d = f - center;
	// (um pouco mais pesada embaixo: escorrendo)
	d.y *= d.y > 0.0 ? 1.15 : 0.9;
	float m = 1.0 - smoothstep(r * 0.8, r, length(d));
	float trail = 0.0;
	if (slide > 0.0) {
		// rastro só logo acima da gota, afinando para cima
		float above = clamp((center.y - f.y) / 0.35, 0.0, 1.0);
		float width = r * mix(0.16, 0.04, above);
		trail = (1.0 - smoothstep(width * 0.5, width, abs(f.x - center.x))) * step(f.y, center.y - r * 0.6) * (1.0 - above) * dry * 0.7;
	}
	vec2 off = -d / max(r, 0.001) * m * r + vec2(0.0, -0.08) * trail;
	return vec3(off / grid, max(m, trail * 0.5));
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = res.x / res.y;
	vec2 uv = SCREEN_UV;
	float dry = clamp(strength * 1.2, 0.0, 1.0);
	vec3 small = drops(uv, aspect, 34.0, 0.3, 0.28, 0.0, dry);
	vec3 big = drops(uv + vec2(0.37, 0.11), aspect, 12.0, 0.26, 0.24, 0.45, dry);
	vec2 off = small.xy * 0.8 + big.xy * 1.2;
	float mask = max(small.z, big.z);
	// Película d'água descendo no começo (a parte de cima clareia primeiro)
	float sheet = (1.0 - smoothstep(0.0, 0.65, elapsed)) * smoothstep(-0.15, 0.1, uv.y - elapsed * 1.8);
	off += vec2(sin(uv.y * 38.0 + elapsed * 20.0), cos(uv.x * 24.0 - elapsed * 15.0)) * 0.008 * sheet;
	vec3 col = textureLod(screen_tex, uv + off, sheet * 2.2 + mask * 0.5).rgb;
	// Borda das gotas um pouco mais escura e o clarão da película
	col *= 1.0 - 0.3 * mask * (1.0 - mask);
	col += vec3(0.75, 0.9, 1.0) * sheet * 0.16;
	COLOR = vec4(col, 1.0);
}
