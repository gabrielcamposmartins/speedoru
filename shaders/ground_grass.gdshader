// Gramado com faixas de corte e grade sutil (ajuda a perceber a velocidade).
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

uniform vec4 grass_a : source_color = vec4(0.32, 0.57, 0.25, 1.0);
uniform vec4 grass_b : source_color = vec4(0.28, 0.51, 0.22, 1.0);
uniform vec4 grid_color : source_color = vec4(0.38, 0.62, 0.3, 1.0);
uniform float stripe_width = 12.0;
uniform float grid_size = 24.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float stripe = mod(floor(world_pos.x / stripe_width), 2.0);
	vec3 color = mix(grass_a.rgb, grass_b.rgb, stripe);
	vec2 p = world_pos.xz / grid_size;
	vec2 g = abs(fract(p - 0.5) - 0.5) / fwidth(p);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	color = mix(color, grid_color.rgb, line * 0.6);
	ALBEDO = color;
	ROUGHNESS = 1.0;
}
