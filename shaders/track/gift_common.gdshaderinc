// Caixas de presente flutuando sobre a pista da Rainbow Raceway e as estrelas grandes no ar: giram em
// volta do próprio eixo vertical e sobem e descem devagar, cada uma no seu ritmo (fase tirada da
// posição). gift_box.gdshader = cubo de vidro colorido (transparente, arestas claras, reflexo);
// gift_solid.gdshader = o que está dentro ou a peça cheia (coração, estrela), acesa com a cor do
// vértice × instância.

uniform float spin = 0.8;
uniform float bob = 0.25;
uniform float day_energy = 1.2;
uniform float night_energy = 2.6;
global uniform float night;

varying vec3 tint;
varying vec3 local_pos;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float h = fract(sin(dot(center, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float a = TIME * spin * (0.7 + 0.6 * h) + h * 6.2831;
	float c = cos(a);
	float s = sin(a);
	local_pos = VERTEX;
	vec3 v = VERTEX;
	v = vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z);
	v.y += sin(TIME * 1.3 + h * 6.2831) * bob / max(length(MODEL_MATRIX[1].xyz), 0.001);
	VERTEX = v;
	NORMAL = vec3(c * NORMAL.x + s * NORMAL.z, NORMAL.y, -s * NORMAL.x + c * NORMAL.z);
	tint = COLOR.rgb;
}
