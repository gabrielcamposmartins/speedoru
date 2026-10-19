// Partículas da água em volta da câmera (pista no fundo do mar): neve marinha (pontinhos claros à
// deriva) ou bolhas de ar subindo. Não há emissor: cada instância do MultiMesh tem um lugar fixo
// numa caixa de `box` m que se repete pelo espaço (mod em volta da câmera), então as partículas
// passam com a perspectiva certa em qualquer velocidade, sem custo de CPU. Somem perto da borda da
// caixa (sem "pular"), fora d'água e dentro do tubo de vidro (o ar onde os carros correm: o trecho
// dele perto da câmera vem da SeaAtmosphere, SeaTube.corridor), podendo chegar bem perto da câmera
// do lado de fora do vidro; longe da pista, só a partir de min_distance. Billboard; shape 0 = neve,
// 1 = bolha.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform int shape = 0;
uniform float box = 60.0;
uniform float size = 0.06;
uniform float rise = 0.0;
uniform vec3 color : source_color = vec3(0.85, 0.95, 1.0);
uniform float intensity = 1.0;
uniform float water_level = 28.0;
// Distância da câmera a partir da qual as partículas aparecem (sem o trecho do tubo).
uniform float min_distance = 16.0;
// Trecho do tubo de vidro perto da câmera: linha do meio da seção (xyz) com a meia-largura (w) e a
// altura do teto acima dela em cada ponto.
uniform bool tube_on = false;
uniform vec4 tube_path[5];
uniform float tube_tops[5];
uniform float tube_min_distance = 3.0;

varying vec2 q;
varying float k;
varying float seed;

// 1 dentro do trecho do tubo (borda suave de ~1,5 m), 0 fora.
float inside_tube(vec3 c) {
	float best = 1e9;
	float half_w = 0.0;
	float floor_y = 0.0;
	float top = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 a = tube_path[i].xz;
		vec2 ab = tube_path[i + 1].xz - a;
		float h = clamp(dot(c.xz - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
		float d = length(c.xz - (a + ab * h));
		if (d < best) {
			best = d;
			half_w = mix(tube_path[i].w, tube_path[i + 1].w, h);
			floor_y = mix(tube_path[i].y, tube_path[i + 1].y, h);
			top = mix(tube_tops[i], tube_tops[i + 1], h);
		}
	}
	float dy = c.y - floor_y;
	return (1.0 - smoothstep(half_w - 1.5, half_w, best)) * (1.0 - smoothstep(top - 1.5, top, dy)) * step(-3.0, dy);
}

void vertex() {
	vec3 p0 = MODEL_MATRIX[3].xyz;
	seed = fract(sin(dot(p0, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float t = TIME;
	vec3 drift = vec3(sin(t * 0.21 + seed * 6.2831) * 0.7,
		rise * t * (0.7 + 0.6 * seed) + sin(t * 0.47 + seed * 9.0) * 0.25,
		cos(t * 0.17 + seed * 4.1) * 0.7);
	if (shape == 1) {
		drift.x += sin(t * 2.3 + seed * 20.0) * 0.12;
	}
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 rel = mod(p0 + drift - cam, box) - box * 0.5;
	vec3 world = cam + rel;
	float s = size * (shape == 1 ? (0.5 + seed * 1.5) : (0.6 + seed * 0.9));
	world += (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
	float d = length(rel);
	k = 1.0 - smoothstep(box * 0.3, box * 0.48, d);
	if (tube_on) {
		k *= smoothstep(tube_min_distance, tube_min_distance + 3.0, d) * (1.0 - inside_tube(cam + rel));
	} else {
		k *= smoothstep(min_distance, min_distance + 6.0, d);
	}
	k *= step(world.y, water_level - 0.2);
	q = UV * 2.0 - 1.0;
}

void fragment() {
	float r = length(q);
	if (shape == 0) {
		float a = (1.0 - smoothstep(0.2, 1.0, r)) * k * intensity * (0.5 + 0.5 * seed);
		ALBEDO = color;
		ALPHA = a;
	} else {
		// Bolha de ar: aro prateado, miolo transparente e um reflexo
		float rim = smoothstep(0.7, 0.88, r) * (1.0 - smoothstep(0.9, 1.0, r));
		float hi = 1.0 - smoothstep(0.0, 0.22, length(q - vec2(-0.32, 0.36)));
		ALBEDO = color * (0.8 + 0.6 * hi);
		ALPHA = clamp(rim * 0.75 + hi * 0.8 + 0.06 * step(r, 0.9), 0.0, 1.0) * k * intensity;
	}
	if (ALPHA < 0.003) {
		discard;
	}
}
