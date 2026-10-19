// A superfície do mar vista de BAIXO (pista no fundo do mar): um espelho d'água ondulado.
//  * Dentro da janela de Snell (o cone de ~48,6° em volta da vertical por onde a luz de fora entra)
//    aparece o que está acima d'água — o céu de verdade do período com as nuvens e o sol, as
//    montanhas, as cachoeiras e os barcos —, refratado e distorcido pelas ondas: a direção de fora
//    sai da refração (água → ar) e é procurada na janela do céu (SeaWorld: a imagem de uma câmera na
//    superfície olhando para cima, só com o que está acima do mar), mais os brilhos do sol nas ondas.
//  * Fora da janela a superfície tem a luminosidade do céu, distorcida pelas ondas (o céu da janela
//    "dobrado" para fora dela), com o reflexo do fundo do mar, das paredes do cânion e do tubo por
//    cima, discreto (reflexo no espaço da tela, marchando o raio refletido contra a profundidade).
//  * Perto da borda o Fresnel mistura os dois, com a borda da janela clara.
// A face aponta para baixo (cull_back): de cima quem aparece é o sea_surface.gdshader. Recortado
// dentro do tubo de vidro onde ele sai da água (sea_carve.gdshaderinc). Transparente (lê a tela):
// desenhado antes dos outros transparentes (render_priority do material) e grava a profundidade,
// então o que é transparente e está acima d'água não aparece através dele.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, blend_mix, depth_draw_always;

uniform sampler2D window_tex : source_color, filter_linear, repeat_disable;
// tan(metade do campo de visão) da câmera da janela do céu
uniform float window_tan = 2.75;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 sky_horizon : source_color = vec3(0.7, 0.88, 1.0);
uniform vec3 deep_color : source_color = vec3(0.04, 0.3, 0.42);
uniform vec3 sun_color : source_color = vec3(1.0, 0.97, 0.88);
uniform float sun_strength = 7.0;
uniform float brightness = 1.0;
// Força do reflexo do fundo (0 = só a luz do céu)
uniform float mirror = 0.35;
// Luz do céu fora da janela: quanto (0 = água funda) e o brilho dela
uniform float sky_light = 0.72;
uniform float sky_glow = 0.85;
// Quanto as ondas entortam a superfície
uniform float wave_tilt = 0.24;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
global uniform vec3 sun_dir_world;

varying vec3 wpos;

#include "res://shaders/track/sea_carve.gdshaderinc"

// Profundidade da cena (z no espaço da câmera, negativo) no ponto `uv` da tela.
float scene_z(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_tex, uv, 0.0).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.z / v.w;
}

vec2 to_screen(vec3 q, mat4 proj) {
	vec4 c = proj * vec4(q, 1.0);
	return c.xy / c.w * 0.5 + 0.5;
}

// Reflexo no espaço da tela: marcha (passos crescentes) do raio refletido `d` a partir de `o` (espaço
// da câmera) até passar para trás do que está na tela, refina e devolve a cor (rgb) e o peso (a).
vec4 trace_reflection(vec3 o, vec3 d, mat4 proj, mat4 inv_proj) {
	float t = 0.8;
	float prev = 0.0;
	for (int i = 0; i < 26; i++) {
		vec3 q = o + d * t;
		if (q.z > -0.1) {
			break;
		}
		vec2 uv = to_screen(q, proj);
		if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
			break;
		}
		float sz = scene_z(uv, inv_proj);
		if (q.z < sz) {
			// (passou por trás de algo grosso, mais perto: daqui não dá para ver o reflexo)
			if (sz - q.z > max(t - prev, 0.6) * 2.5) {
				break;
			}
			float lo = prev;
			float hi = t;
			for (int k = 0; k < 5; k++) {
				float mid = (lo + hi) * 0.5;
				vec3 m = o + d * mid;
				if (m.z < scene_z(to_screen(m, proj), inv_proj)) {
					hi = mid;
				} else {
					lo = mid;
				}
			}
			vec2 uh = to_screen(o + d * hi, proj);
			float edge = smoothstep(0.0, 0.1, min(min(uh.x, 1.0 - uh.x), min(uh.y, 1.0 - uh.y)));
			return vec4(textureLod(screen_tex, uh, 0.0).rgb, edge);
		}
		prev = t;
		t = t * 1.24 + 0.4;
	}
	return vec4(0.0);
}

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
	// Fora da janela: a luz do céu (a janela "dobrada": a direção levantada para dentro do campo da
	// câmera do céu, entortada pelas ondas)
	vec3 fold = normalize(vec3(v.x + ripple.x * 0.3, max(v.y, 0.03) * 1.6 + 0.15, v.z + ripple.y * 0.3));
	vec2 fuv = vec2(0.5 + 0.5 * fold.x / (fold.y * window_tan), 0.5 - 0.5 * fold.z / (fold.y * window_tan));
	vec3 glow = mix(sky_horizon, texture(window_tex, clamp(fuv, vec2(0.0), vec2(1.0))).rgb, 0.55) * sky_glow;
	vec3 mirror_col = mix(deep_color, glow, sky_light);
	// E por cima, discreto, o fundo refletido (ondas mais calmas: no reflexo da tela viravam riscos)
	vec3 r = reflect(v, -normalize(mix(vec3(0.0, 1.0, 0.0), n, 0.45)));
	if (dist < 280.0) {
		vec3 rv = normalize((VIEW_MATRIX * vec4(r, 0.0)).xyz);
		vec4 hit = trace_reflection(VERTEX, rv, PROJECTION_MATRIX, INV_PROJECTION_MATRIX);
		mirror_col = mix(mirror_col, hit.rgb, hit.a * mirror * (1.0 - smoothstep(140.0, 260.0, dist)));
	}
	// Linhas de luz das ondas no espelho
	float lines = smoothstep(0.35, 0.8, abs(ripple.x * 1.3 + ripple.y));
	mirror_col += sky_horizon * lines * 0.08;
	vec3 col = mix(sky, mirror_col, fresnel);
	// Borda da janela mais clara (onde o Fresnel vira)
	if (!tir) {
		col += sky_horizon * 0.7 * fresnel * (1.0 - fresnel);
	}
	ALBEDO = col * brightness;
	ALPHA = 1.0;
}
