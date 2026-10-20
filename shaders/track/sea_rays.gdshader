// Raios de sol atravessando a água (pista no fundo do mar): duas folhas cruzadas por raio, aditivas,
// com o topo preso na superfície e a base inclinada na direção da luz já refratada pela superfície
// (no máximo ~48,6° da vertical, a janela de Snell: com a luz de fora o sol baixo deitava os raios em
// riscos compridos), abrindo um pouco para baixo, com filetes por dentro, suaves nas bordas, sumindo
// para baixo, de perto, de lado e com a distância (fade_distance faz o papel da névoa: aditivo com
// névoa clarearia o que está longe). Balançam e piscam devagar.
// Malha: x = -0,5..0,5 na largura, y = 0 (em cima) .. -1 (embaixo); a instância escala (largura,
// altura). INSTANCE_CUSTOM.x = semente.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 ray_color : source_color = vec3(0.7, 0.95, 1.0);
uniform float intensity = 0.0;
uniform float fade_distance = 260.0;
uniform float water_level = 28.0;
global uniform vec3 sun_dir_world;

varying float seed;
varying float depth01;
varying vec3 wpos;

void vertex() {
	seed = INSTANCE_CUSTOM.x;
	depth01 = UV.y;
	// Base inclinada na direção da luz (o topo fica na superfície). No mundo e de volta (o MODEL_MATRIX
	// do MultiMesh já inclui a instância)
	// (abrindo para baixo: a folha é ~1,6× mais larga no pé)
	vec3 v = VERTEX;
	v.xz *= 1.0 + UV.y * 0.6;
	vec3 w = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
	vec3 l = normalize(sun_dir_world);
	float down = max(water_level - w.y, 0.0);
	// Refração ar → água: seno do ângulo com a vertical dividido por 1,333
	float sa = min(length(l.xz) / 1.333, 0.74);
	vec2 lean = -normalize(l.xz + vec2(1e-5, 0.0)) * sa / sqrt(1.0 - sa * sa);
	w.xz += lean * down;
	w.x += sin(TIME * 0.21 + seed * 6.2831) * 1.6 * UV.y;
	w.z += cos(TIME * 0.17 + seed * 4.1) * 1.6 * UV.y;
	wpos = w;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
}

void fragment() {
	float across = sin(clamp(UV.x, 0.0, 1.0) * 3.14159);
	across *= across;
	// Filetes de luz por dentro do raio, mexendo devagar
	across *= 0.55 + 0.45 * sin(UV.x * 11.0 + seed * 23.0 + TIME * 0.35) * sin(UV.x * 5.0 - seed * 7.0 + TIME * 0.21);
	float fall = pow(1.0 - depth01, 1.6) * smoothstep(0.0, 0.04, depth01);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near = smoothstep(6.0, 30.0, dist);
	float far = exp(-dist / fade_distance);
	float side = smoothstep(0.05, 0.45, abs(dot(NORMAL, VIEW)));
	float flick = 0.7 + 0.3 * sin(TIME * 0.6 + seed * 11.0 + UV.x * 2.0);
	// Só abaixo da linha d'água (a câmera fora d'água vê a superfície opaca, mas por garantia)
	float under = step(wpos.y, water_level) * step(CAMERA_POSITION_WORLD.y, water_level + 0.5);
	// (Sem passar de ~0,35: somado à névoa clara não deve virar bloom)
	ALBEDO = ray_color * min(intensity * across * fall * near * far * side * flick * under, 0.35);
}
