// Bichos do mar da Atlantis Abyss (baleia, raias, tubarões, golfinhos, tartarugas, polvo; modelos de
// blender/build_atlantis.py): toon com dorso e ventre de cores próprias, manchas opcionais e o nado no
// vértice, pesado pela cor de vértice R (0 no corpo, 1 na cauda, nas asas, nas nadadeiras ou nas
// pontas dos tentáculos). Um material só para todos: a cor e o nado de cada bicho vêm dos
// instance uniforms (SeaLife). Frente do modelo = +Z.
//   mode 0: onda lateral (peixe, tubarão)    1: onda vertical (baleia, golfinho)
//        2: asas batendo (raia)               3: nadadeiras remando (tartaruga)
//        4: tentáculos ondulando (polvo)
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

instance uniform vec3 top_color : source_color = vec3(0.2, 0.28, 0.4);
instance uniform vec3 belly_color : source_color = vec3(0.85, 0.88, 0.9);
instance uniform float spots = 0.0;
instance uniform float mode = 0.0;
instance uniform float amp = 0.3;
instance uniform float freq = 1.6;
instance uniform float wave = 0.5;
instance uniform float phase = 0.0;
global uniform float night;

varying vec3 local_pos;
varying float up;

void vertex() {
	float w = COLOR.r;
	float t = TIME * freq + phase;
	vec3 v = VERTEX;
	if (mode < 0.5) {
		v.x += sin(v.z * wave + t) * amp * w;
	} else if (mode < 1.5) {
		v.y += sin(v.z * wave + t) * amp * w;
	} else if (mode < 2.5) {
		v.y += sin(t - abs(v.x) * wave) * amp * w * abs(v.x) * 0.35;
	} else if (mode < 3.5) {
		v.y += sin(t + sign(v.x) * 0.6) * amp * w;
		v.z += cos(t + sign(v.x) * 0.6) * amp * 0.5 * w;
	} else {
		float a = atan(v.z, v.x);
		v.x += sin(t + a * 2.0 + v.y * 0.8) * amp * w;
		v.z += cos(t * 0.8 + a * 2.0) * amp * w;
		v.y += sin(t * 1.3 + a * 3.0) * amp * 0.5 * w;
	}
	VERTEX = v;
	local_pos = v;
	up = NORMAL.y;
}

float creature_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float creature_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(creature_hash(i), creature_hash(i + vec2(1.0, 0.0)), u.x),
		mix(creature_hash(i + vec2(0.0, 1.0)), creature_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float back = smoothstep(-0.35, 0.35, up);
	vec3 col = mix(belly_color, top_color, back);
	if (spots > 0.0) {
		float s = smoothstep(0.72, 0.78, creature_noise(local_pos.xz * 1.6 + local_pos.y * 0.7));
		col = mix(col, belly_color * 1.05, s * spots * back);
	}
	ALBEDO = col;
	ROUGHNESS = 0.6;
	RIM = 0.35;
	RIM_TINT = 0.4;
}
