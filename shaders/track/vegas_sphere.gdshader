shader_type spatial;
render_mode unshaded, cull_back;
// Tela de LED da Sphere (Las Vegas): o casco inteiro é um painel. Três shows se alternam com uma
// troca suave: o olho gigante (olhando para look_dir), um planeta e ondas de néon. A malha de
// pontos de LED aparece de perto; à noite brilha bem mais (night 0..1).

uniform vec3 look_dir = vec3(1.0, 0.15, 0.0);
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float show_time = 16.0;

varying vec3 n_obj;

void vertex() {
	n_obj = normalize(VERTEX);
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 5; k++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

vec3 eye(vec3 n) {
	vec3 d = normalize(look_dir);
	// O olhar passeia um pouco
	float t = TIME * 0.35;
	d = normalize(d + vec3(0.0, 0.18 * sin(t * 0.7), 0.0) + cross(vec3(0.0, 1.0, 0.0), d) * 0.25 * sin(t));
	float ang = acos(clamp(dot(n, d), -1.0, 1.0));
	// Esclera com veias
	vec2 q = vec2(atan(n.z, n.x) * 6.0, n.y * 6.0);
	float veins = smoothstep(0.62, 0.7, fbm(q * 1.7)) * smoothstep(0.4, 1.6, ang);
	vec3 col = mix(vec3(0.96, 0.95, 0.92), vec3(0.85, 0.15, 0.12), veins * 0.8);
	// Íris (anéis e fibras) e pupila
	float iris = 1.0 - smoothstep(0.42, 0.45, ang);
	float fib = fbm(vec2(atan(dot(n, cross(d, vec3(0.0, 1.0, 0.0))), dot(n, vec3(0.0, 1.0, 0.0))) * 14.0, ang * 20.0));
	vec3 iris_col = mix(vec3(0.05, 0.35, 0.75), vec3(0.2, 0.75, 0.55), fib) * (0.7 + 0.5 * smoothstep(0.1, 0.42, ang));
	col = mix(col, iris_col, iris);
	float pupil = 1.0 - smoothstep(0.17, 0.19, ang);
	col = mix(col, vec3(0.02), pupil);
	// Brilho
	vec3 hl_dir = normalize(d + vec3(-0.12, 0.16, 0.08));
	col += vec3(1.0) * (1.0 - smoothstep(0.03, 0.05, acos(clamp(dot(n, hl_dir), -1.0, 1.0))));
	// Pálpebra piscando de vez em quando
	float blink = smoothstep(0.92, 1.0, fract(TIME * 0.11)) * (1.0 - smoothstep(0.97, 1.0, fract(TIME * 0.11)));
	float lid = smoothstep(1.0 - blink * 1.2, 1.0 - blink * 1.2 + 0.05, abs(dot(n, vec3(0.0, 1.0, 0.0))));
	return mix(col, vec3(0.75, 0.55, 0.45), lid);
}

vec3 planet(vec3 n) {
	float lon = atan(n.z, n.x) + TIME * 0.05;
	vec2 q = vec2(lon * 2.2, n.y * 2.6);
	float land = smoothstep(0.5, 0.56, fbm(q * 1.4 + 3.0));
	vec3 ocean = mix(vec3(0.02, 0.12, 0.38), vec3(0.08, 0.35, 0.7), fbm(q * 4.0));
	vec3 ground = mix(vec3(0.2, 0.45, 0.15), vec3(0.65, 0.55, 0.3), fbm(q * 3.0 + 9.0));
	vec3 col = mix(ocean, ground, land);
	float ice = smoothstep(0.78, 0.85, abs(n.y));
	col = mix(col, vec3(0.95), ice);
	float clouds = smoothstep(0.55, 0.75, fbm(vec2(lon * 3.0 - TIME * 0.03, n.y * 4.0) + 20.0));
	return mix(col, vec3(1.0), clouds * 0.8);
}

vec3 neon(vec3 n) {
	float a = atan(n.z, n.x);
	float bands = sin(n.y * 9.0 + a * 3.0 - TIME * 1.6) * 0.5 + 0.5;
	vec3 c1 = vec3(1.0, 0.1, 0.6);
	vec3 c2 = vec3(0.1, 0.85, 1.0);
	vec3 c3 = vec3(0.6, 0.2, 1.0);
	vec3 col = mix(mix(c1, c2, bands), c3, sin(a * 2.0 + TIME * 0.7) * 0.5 + 0.5);
	float sparks = step(0.985, hash(floor(vec2(a * 80.0, n.y * 80.0)) + floor(TIME * 6.0)));
	return col * (0.55 + 0.45 * bands) + vec3(sparks);
}

void fragment() {
	vec3 n = normalize(n_obj);
	float phase = TIME / show_time;
	int k = int(floor(phase)) % 3;
	float blend = smoothstep(0.88, 1.0, fract(phase));
	vec3 shows[3];
	shows[0] = eye(n);
	shows[1] = planet(n);
	shows[2] = neon(n);
	vec3 col = mix(shows[k], shows[(k + 1) % 3], blend);
	// Pontos de LED (grade no próprio casco): somem de longe, onde virariam moiré
	vec2 led_uv = vec2(atan(n.z, n.x) * 260.0, n.y * 320.0);
	vec2 fw = fwidth(led_uv);
	float near = 1.0 - smoothstep(0.25, 0.6, max(fw.x, fw.y));
	float dot_mask = smoothstep(0.5, 0.32, length(fract(led_uv) - 0.5));
	col *= mix(1.0, dot_mask * 1.25 + 0.15, 0.5 * near);
	// De dia a tela fica um pouco mais escura (o sol lava); à noite brilha forte
	ALBEDO = col * mix(0.82, 1.0, night);
	EMISSION = col * mix(0.0, 1.7, night);
}
