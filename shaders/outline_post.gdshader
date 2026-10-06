// Contorno estilo anime em tela cheia (detecção de bordas por profundidade + normais).
// Uso: MeshInstance3D com QuadMesh 2x2 filho da câmera, extra_cull_margin no máximo.
shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;

uniform vec4 line_color : source_color = vec4(0.07, 0.05, 0.13, 1.0);
uniform float line_width : hint_range(0.5, 4.0) = 1.4;
// Diferença relativa de profundidade que gera linha (ajustada pelo ângulo de visão).
uniform float depth_threshold : hint_range(0.001, 0.5) = 0.04;
// 1 - dot(n0, n1) acima disso gera linha de dobra.
uniform float normal_threshold : hint_range(0.05, 2.0) = 0.45;
uniform float fade_start = 60.0;
uniform float fade_end = 220.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float linear_depth(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_tex, uv, 0.0).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

// Rugosidade decodificada (o Godot espelha o canal em objetos dinâmicos).
float roughness_at(vec2 uv) {
	float r = textureLod(normal_tex, uv, 0.0).a;
	if (r > 0.5) {
		r = 1.0 - r;
	}
	return r / (127.0 / 255.0);
}

vec3 view_normal(vec2 uv) {
	return normalize(textureLod(normal_tex, uv, 0.0).xyz * 2.0 - 1.0);
}

void fragment() {
	vec2 px = line_width / VIEWPORT_SIZE;
	float d0 = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	if (d0 > 11000.0) {
		discard; // céu
	}
	// Rugosidade 0 marca o que não leva contorno (grama, postes, pilares, mastros)
	if (roughness_at(SCREEN_UV) < 0.02) {
		discard;
	}
	vec3 n0 = view_normal(SCREEN_UV);
	// Superfícies vistas de lado (ex.: chão ao longe) precisam de um limiar maior.
	float facing = clamp(abs(n0.z), 0.05, 1.0);
	float threshold = depth_threshold / facing;

	vec2 offsets[4] = vec2[](vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y));
	float edge = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 uv = SCREEN_UV + offsets[i];
		float d = linear_depth(uv, INV_PROJECTION_MATRIX);
		// Só desenha no pixel mais próximo da borda (contorno do objeto da frente).
		float depth_edge = step(threshold, (d - d0) / d0);
		float normal_edge = 0.0;
		if (abs(d - d0) / d0 < 0.15 && roughness_at(uv) >= 0.02) {
			normal_edge = step(normal_threshold, 1.0 - dot(n0, view_normal(uv)));
		}
		edge = max(edge, max(depth_edge, normal_edge));
	}
	float fade = 1.0 - smoothstep(fade_start, fade_end, d0);
	ALBEDO = line_color.rgb;
	ALPHA = edge * fade * line_color.a;
}
