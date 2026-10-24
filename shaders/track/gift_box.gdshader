// Cubo de vidro das caixas de presente (ver gift_common.gdshaderinc).
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx, depth_draw_never;

#include "res://shaders/track/gift_common.gdshaderinc"

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	// Arestas do cubo mais claras (a malha vai de -0,5 a 0,5)
	vec3 q = abs(local_pos) * 2.0;
	float edge = smoothstep(0.82, 0.96, max(min(q.x, q.y), max(min(q.y, q.z), min(q.x, q.z))));
	ALBEDO = mix(tint, vec3(1.0), 0.35 + 0.4 * edge);
	ALPHA = clamp(0.2 + fres * 0.5 + edge * 0.6, 0.0, 0.92);
	EMISSION = tint * (0.15 + 0.5 * edge) * mix(day_energy, night_energy, night) * 0.4;
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
}
