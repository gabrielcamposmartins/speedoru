// Halo de luz sobre a cratera dos vulcões de bolhas (SeaVents): billboard aditivo (o quad 2x2 na
// escala do nó = raio do halo), queda radial suave, mais forte à noite, sumindo com a distância (a
// névoa não apaga direito o que é aditivo) e de leve onde encosta na rocha (sem a linha dura do
// corte com a encosta).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.42, 0.12);
uniform float day_energy = 0.35;
uniform float night_energy = 1.1;
uniform float fade_distance = 240.0;
uniform float soft_distance = 4.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
global uniform float night;

varying float k;
varying vec2 q;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 world = center + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * size;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
	k = exp(-length(center - CAMERA_POSITION_WORLD) / fade_distance);
	q = UV * 2.0 - 1.0;
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene = -view.z / view.w;
	float soft = clamp((scene + VERTEX.z) / soft_distance, 0.0, 1.0);
	float a = pow(max(1.0 - length(q), 0.0), 2.4);
	ALBEDO = color * a * mix(day_energy, night_energy, night) * k * soft;
}
