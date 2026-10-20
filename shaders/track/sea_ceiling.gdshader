// A superfície do mar vista de BAIXO (pista no fundo do mar): um espelho d'água ondulado.
//  * Dentro da janela de Snell (o cone de ~48,6° em volta da vertical por onde a luz de fora entra)
//    aparece o que está acima d'água — o céu de verdade do período com as nuvens e o sol, as
//    montanhas, as cachoeiras e os barcos —, refratado e distorcido pelas ondas: a direção de fora
//    sai da refração (água → ar) e é procurada na janela do céu (SeaWorld: a imagem de uma câmera na
//    superfície olhando para cima, só com o que está acima do mar), mais os brilhos do sol nas ondas.
//  * Fora da janela (reflexão total) a superfície reflete a água funda: prateada perto da borda da
//    janela e escurecendo até a cor da água no horizonte, com as linhas de luz das ondas (sem copiar
//    a tela: o reflexo da cena virava riscos coloridos e o céu "dobrado" punha nuvens no teto todo).
//  * Perto da borda o Fresnel mistura os dois, com a borda da janela clara.
// A face aponta para baixo (cull_back): de cima quem aparece é o sea_surface.gdshader. Recortado
// dentro do tubo de vidro onde ele sai da água (sea_carve.gdshaderinc). Opaco: grava a profundidade,
// então o que é transparente e está acima d'água não aparece através dele.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform sampler2D window_tex : source_color, filter_linear, repeat_disable;
// tan(metade do campo de visão) da câmera da janela do céu
uniform float window_tan = 2.75;
uniform vec3 sky_horizon : source_color = vec3(0.7, 0.88, 1.0);
uniform vec3 deep_color : source_color = vec3(0.04, 0.3, 0.42);
// Tom prateado do reflexo fora da janela (a água refletida, não o céu: no fim da tarde o laranja do
// horizonte pintava o teto todo)
uniform vec3 mirror_tint : source_color = vec3(0.3, 0.6, 0.72);
uniform vec3 sun_color : source_color = vec3(1.0, 0.97, 0.88);
uniform float sun_strength = 7.0;
uniform float brightness = 1.0;
// Quanto as ondas entortam a superfície
uniform float wave_tilt = 0.24;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
global uniform vec3 sun_dir_world;

varying vec3 wpos;

#include "res://shaders/track/sea_carve.gdshaderinc"

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// (sem teto dentro do tubo de vidro, onde ele sai da água)
	if (sea_carved(wpos.xz)) {
		discard;
	}
	vec3 v = normalize(wpos - CAMERA_POSITION_WORLD);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float t = TIME;
	vec3 na = texture(normal_a, wpos.xz * 0.045 + vec2(t * 0.012, t * 0.007)).rgb * 2.0 - 1.0;
	vec3 nb = texture(normal_b, wpos.xz * 0.11 + vec2(-t * 0.018, t * 0.021)).rgb * 2.0 - 1.0;
	// Ondas mais calmas longe (de raspão a textura comprimida virava chiado)
	float calm = mix(1.0, 0.35, smoothstep(60.0, 260.0, dist));
	vec2 ripple = (na.xy + nb.xy) * 0.5 * calm;
	// Normal da superfície (para cima), entortada pelas ondas
	vec3 n = normalize(vec3(-ripple.x * wave_tilt, 1.0, -ripple.y * wave_tilt));
	// Refração para fora (água → ar): a direção de onde vem a luz que chega aqui
	vec3 a = refract(v, -n, 1.333);
	bool tir = dot(a, a) < 0.25;
	vec3 sky = sky_horizon;
	float fresnel = 1.0;
	if (!tir) {
		a = normalize(a);
		fresnel = 0.02 + 0.98 * pow(1.0 - clamp(dot(a, n), 0.0, 1.0), 5.0);
		// Na janela do céu (câmera olhando para cima: +X à direita, +Z para baixo na imagem)
		float ay = max(a.y, 0.03);
		vec2 uv = vec2(0.5 + 0.5 * a.x / (ay * window_tan), 0.5 - 0.5 * a.z / (ay * window_tan));
		float inside = smoothstep(0.0, 0.07, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
		sky = mix(sky_horizon, texture(window_tex, clamp(uv, vec2(0.0), vec2(1.0))).rgb, inside);
		// Brilhos do sol nas ondas
		vec3 sd = normalize(sun_dir_world);
		float sdot = max(dot(a, sd), 0.0);
		sky += sun_color * (pow(sdot, 900.0) * sun_strength * 0.4 + pow(sdot, 60.0) * 0.35) * step(0.0, sd.y);
	}
	// Fora da janela: a água funda refletida, prateada junto da janela e escurecendo de raspão
	float graze = smoothstep(0.68, 0.12, v.y);
	vec3 mirror_col = mix(mix(deep_color, mirror_tint, 0.42), deep_color * 0.85, graze);
	// Linhas de luz das ondas no espelho (mais fracas de raspão)
	float lines = smoothstep(0.35, 0.85, abs(ripple.x * 1.3 + ripple.y));
	mirror_col += mirror_tint * lines * mix(0.24, 0.05, graze);
	vec3 col = mix(sky, mirror_col, fresnel);
	// Borda da janela mais clara (onde o Fresnel vira)
	if (!tir) {
		col += sky_horizon * 0.7 * fresnel * (1.0 - fresnel);
	}
	ALBEDO = col * brightness;
}
