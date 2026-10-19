// Coluna de bolhas dos vulcões do fundo do mar (SeaVents): cada instância do MultiMesh é uma bolha
// que sobe sem parar da cratera (origem do nó) até a superfície (`height` m acima), girando em
// espiral, abrindo a coluna (`spread` m a mais lá em cima) e crescendo à medida que sobe, com um
// tremor. Sem emissor: a subida é do shader. INSTANCE_CUSTOM: x = fase, y = ângulo, z = afastamento,
// w = tamanho. Billboard. Com `puff`, fumaça: nuvens macias e escuras, maiores e abrindo mais.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float height = 30.0;
uniform float speed = 2.6;
uniform vec3 color : source_color = vec3(0.86, 0.97, 1.0);
uniform float fade_distance = 300.0;
// Raio da coluna na boca da cratera (m) e quanto ela abre até lá em cima
uniform float base_radius = 0.6;
uniform float spread = 3.6;
uniform bool puff = false;
uniform float puff_alpha = 0.55;

varying vec2 q;
varying float k;
varying float rise;

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float u = fract(TIME * speed * (0.75 + c.w * 0.5) / height + c.x);
	float ang = c.y * 6.2831 + u * 7.0 + TIME * 0.4;
	float r = (base_radius + u * spread) * c.z;
	vec3 local = vec3(cos(ang) * r, u * height, sin(ang) * r);
	local.x += sin(TIME * 5.0 + c.x * 40.0) * 0.12;
	vec3 world = (MODEL_MATRIX * vec4(local, 1.0)).xyz;
	float s = puff ? (0.7 + c.w * 1.3) * (0.6 + u * 3.2) : (0.14 + c.w * 0.46) * (0.6 + u * 1.5);
	world += (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
	float d = length(world - CAMERA_POSITION_WORLD);
	k = smoothstep(0.0, 0.06, u) * (1.0 - smoothstep(0.93, 1.0, u)) * exp(-d / fade_distance);
	q = UV * 2.0 - 1.0;
	rise = u;
}

void fragment() {
	float r = length(q);
	float a = 0.0;
	if (puff) {
		// Fumaça: borda macia, um pouco irregular, mais rala lá em cima
		float soft = 1.0 - smoothstep(0.15, 1.0, r + 0.12 * sin(atan(q.y, q.x) * 3.0 + rise * 11.0));
		ALBEDO = color;
		a = soft * puff_alpha * k * pow(1.0 - rise, 1.4);
	} else {
		float rim = smoothstep(0.66, 0.86, r) * (1.0 - smoothstep(0.9, 1.0, r));
		float hi = 1.0 - smoothstep(0.0, 0.24, length(q - vec2(-0.3, 0.34)));
		ALBEDO = color * (0.8 + 0.6 * hi);
		a = clamp(rim * 0.8 + hi * 0.85 + 0.08 * step(r, 0.9), 0.0, 1.0) * k;
	}
	if (a < 0.005) {
		discard;
	}
	ALPHA = a;
}
