// Águas-vivas brilhantes (SeaLife): sino e tentáculos aditivos (brilham sem ordenar a transparência),
// o sino pulsando, os tentáculos ondulando e cada uma subindo e descendo devagar. Mais fortes à
// noite (bioluminescência). Como é aditivo, a distância apaga no lugar da névoa (fade_distance).
// COLOR.r = 0 no sino, 1 na ponta dos tentáculos; COLOR.g = borda do sino (mais clara).
// INSTANCE_CUSTOM: x = fase, y = cor (0 rosa, 0,5 ciano, 1 violeta).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float intensity = 0.6;
uniform float fade_distance = 240.0;
global uniform float night;

varying vec3 tint;
varying float rim;
varying float tail;
varying vec3 wpos;

void vertex() {
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float pulse = sin(TIME * 1.8 + ph);
	tail = COLOR.r;
	rim = COLOR.g;
	// Sino: encolhe e abre; tentáculos ondulam e se arrastam para baixo no pulso
	vec3 v = VERTEX;
	float bell = 1.0 - tail;
	v.xz *= 1.0 + pulse * 0.12 * bell;
	v.y *= 1.0 - pulse * 0.08 * bell;
	v.x += sin(TIME * 1.3 + ph + v.y * 2.2) * 0.12 * tail;
	v.z += cos(TIME * 1.1 + ph + v.y * 1.9) * 0.12 * tail;
	// Sobe e desce devagar
	v.y += sin(TIME * 0.35 + ph) * 1.2;
	VERTEX = v;
	float c = INSTANCE_CUSTOM.y;
	tint = c < 0.33 ? vec3(1.0, 0.45, 0.85) : (c < 0.66 ? vec3(0.35, 0.95, 1.0) : vec3(0.7, 0.5, 1.0));
	wpos = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
}

void fragment() {
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float far = exp(-dist / fade_distance) * smoothstep(1.0, 4.0, dist);
	float facing = abs(dot(NORMAL, VIEW));
	float body = mix(0.25 + 0.75 * pow(1.0 - facing, 2.0), 0.6, tail) + rim * 0.6;
	ALBEDO = tint * body * intensity * (1.0 + 2.0 * night) * far * (1.0 - tail * 0.5);
}
