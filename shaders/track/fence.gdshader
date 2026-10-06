// Tela de proteção (alambrado) procedural: losangos de arame + barras horizontais.
// UV em metros (u = ao longo, v = altura). Ao longe vira uma película translúcida.
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled, depth_draw_opaque;

uniform vec4 wire_color : source_color = vec4(0.55, 0.58, 0.62, 1.0);
uniform float cell = 0.1;
uniform float wire_width = 0.1;
uniform float far_alpha : hint_range(0.0, 1.0) = 0.22;
uniform float height = 3.0;

void fragment() {
	vec2 p = UV / cell;
	vec2 q = vec2(p.x + p.y, p.x - p.y) * 0.7071;
	vec2 d = abs(fract(q) - 0.5);
	vec2 aa = fwidth(q);
	float line_x = smoothstep(0.5 - wire_width - aa.x, 0.5 - wire_width + aa.x, d.x);
	float line_y = smoothstep(0.5 - wire_width - aa.y, 0.5 - wire_width + aa.y, d.y);
	float wire = max(line_x, line_y);
	float blur = clamp(length(aa) * 1.5, 0.0, 1.0);
	float alpha = mix(wire, far_alpha, blur);
	// Barras horizontais (topo, meio e base) e cabo superior
	float bar = step(abs(UV.y - height + 0.04), 0.04) + step(abs(UV.y - height * 0.5), 0.025) + step(UV.y, 0.05);
	alpha = max(alpha, clamp(bar, 0.0, 1.0));
	ALBEDO = wire_color.rgb * (1.0 - 0.25 * bar);
	ALPHA = alpha;
	ROUGHNESS = 0.6;
}
