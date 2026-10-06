// Linhas de velocidade radiais estilo mangá; `intensity` é controlada pelo HUD.
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.55);
uniform float density = 110.0;
uniform float inner_radius = 0.32;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float angle = atan(uv.y, uv.x) / TAU + 0.5;
	float cell = floor(angle * density);
	float frame = floor(TIME * 24.0);
	float on = step(0.82, hash(cell + frame * 7.13));
	float width = fract(angle * density);
	float thin = smoothstep(0.0, 0.25, width) * smoothstep(1.0, 0.6, width);
	float r = length(uv);
	float mask = smoothstep(inner_radius, inner_radius + 0.35, r);
	COLOR = vec4(line_color.rgb, line_color.a * on * thin * mask * intensity);
}
