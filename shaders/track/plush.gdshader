// Bichos de pelúcia da Rainbow Raceway (ursinhos e coelhinhos de blender/cloud_plush.py): toon macio
// com borda clara (pelo), a cor do pelo, a parte clara (o pelo clareado), o escuro brilhante dos olhos
// e do nariz e a cor de destaque (laço, coração) pelas máscaras da cor de vértice:
//   R = peso do aceno (gira em volta do ombro `pivot`, no plano da frente), G = parte clara,
//   B = escuro, A = destaque.
// mode 0: acena com o braço; mode 1: balança o corpo de leve (o que abraça o coração).
// MultiMesh (use_custom = true): INSTANCE_CUSTOM = (cor do pelo rgb, índice da cor de destaque + fase
// em fração). Nó solto: as cores e a fase vêm dos instance uniforms.
shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform bool use_custom = false;
instance uniform vec3 pivot = vec3(-0.215, 0.49, 0.02);
instance uniform int mode = 0;
instance uniform float amp = 0.45;
instance uniform float freq = 3.0;
instance uniform vec3 fur_color : source_color = vec3(1.0, 0.62, 0.76);
instance uniform vec3 accent_color : source_color = vec3(1.0, 0.3, 0.6);
instance uniform float phase = 0.0;
global uniform float night;

const vec3 ACCENTS[5] = vec3[5](vec3(1.0, 0.3, 0.6), vec3(0.6, 0.42, 1.0), vec3(0.32, 0.62, 1.0), vec3(1.0, 0.55, 0.25),
	vec3(0.3, 0.8, 0.55));

varying vec3 fur;
varying vec3 accent;
varying vec4 masks;
varying vec3 local_pos;

vec3 rot_z(vec3 d, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * d.x - s * d.y, s * d.x + c * d.y, d.z);
}

void vertex() {
	float ph = phase;
	fur = fur_color;
	accent = accent_color;
	if (use_custom) {
		fur = INSTANCE_CUSTOM.rgb;
		float a = INSTANCE_CUSTOM.a;
		accent = ACCENTS[int(floor(a)) % 5];
		ph = fract(a) * 6.2831;
	}
	float t = TIME * freq + ph;
	vec3 v = VERTEX;
	if (mode == 0) {
		// Aceno: o braço vai e volta (só para fora: não entra na cabeça)
		float ang = (0.5 + 0.5 * sin(t)) * amp * COLOR.r;
		v = pivot + rot_z(v - pivot, ang);
	} else {
		v = rot_z(v, sin(t * 0.45) * 0.07);
	}
	// Respiração
	v.y *= 1.0 + 0.015 * sin(t * 0.33);
	VERTEX = v;
	masks = COLOR;
	local_pos = v;
}

void fragment() {
	vec3 cream = mix(fur, vec3(1.0, 0.96, 0.92), 0.72);
	vec3 col = mix(fur, cream, masks.g);
	col = mix(col, accent, masks.a);
	col = mix(col, vec3(0.17, 0.1, 0.15), masks.b);
	// Grão fino do pelo
	float n = fract(sin(dot(floor(local_pos * 120.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	col *= 0.95 + 0.07 * n * (1.0 - masks.b);
	ALBEDO = col;
	SPECULAR = mix(0.04, 0.7, masks.b);
	ROUGHNESS = mix(0.85, 0.22, masks.b);
	RIM = 0.75;
	RIM_TINT = 0.35;
	EMISSION = col * (0.05 + 0.08 * night);
}
