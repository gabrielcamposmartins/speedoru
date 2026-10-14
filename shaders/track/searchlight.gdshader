// Feixe de holofote da Sky Aerobase: cone aberto que sai da origem para +Y (malha de normais suaves,
// sem facetas), aditivo. Mais forte perto da lâmpada e no miolo; as bordas somem suavemente pelo
// ângulo de visão (não aparece a "casca" do cone) e, onde o feixe atravessa alguma coisa (a
// plataforma, um prédio), ele some aos poucos em vez de cortar reto. Um pouco de poeira passando;
// de dia fica desligado (SkyBeams esconde), à noite risca o céu.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 beam_color : source_color = vec4(0.85, 0.92, 1.0, 1.0);
uniform float beam_length = 900.0;
uniform float day_strength = 0.0;
uniform float night_strength = 0.55;
uniform float soft_distance = 12.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
global uniform float night;

varying vec3 wpos;
varying float along_t;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	along_t = clamp(VERTEX.y / beam_length, 0.0, 1.0);
}

void fragment() {
	float t = along_t;
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float core = pow(facing, 3.0);
	float along = pow(1.0 - t, 1.5) * smoothstep(0.0, 0.04, t);
	float dust = 0.9 + 0.1 * sin(wpos.y * 0.05 + TIME * 0.6) * sin(wpos.x * 0.03 + wpos.z * 0.02 - TIME * 0.4);
	// Esmaecimento perto do que está atrás/na frente (partícula suave)
	// (céu aberto atrás: profundidade 0, nada a esmaecer; evita a divisão por zero)
	float scene = texture(depth_tex, SCREEN_UV).r;
	float soft = 1.0;
	if (scene > 1e-6) {
		vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene, 1.0);
		float scene_dist = -sv.z / max(abs(sv.w), 1e-6);
		soft = clamp((scene_dist + VERTEX.z) / soft_distance, 0.0, 1.0);
	}
	float k = core * along * dust * soft * mix(day_strength, night_strength, night);
	ALBEDO = beam_color.rgb * clamp(k, 0.0, 4.0);
}
