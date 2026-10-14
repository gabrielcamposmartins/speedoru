// Luzes da Sky Aerobase (frisos de LED da plataforma, janelas das torres, anéis, telões): cor de
// vértice brilhando (acima de 1 vira bloom), mais forte à noite. Com `chase` > 0 um pulso corre ao
// longo do friso (UV.x = metros ao longo da pista). Com `use_led_color` a cor é a dos LEDs da pista
// (led_color, trocada pelo SkyLights entre azul, verde e roxo).
shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform float day_energy = 1.4;
uniform float night_energy = 3.2;
uniform float chase = 0.0;
uniform float chase_speed = 60.0;
uniform float chase_spacing = 90.0;
uniform bool use_led_color = false;
// Farol piscando: multiplicador trocado pelo SkyBlink (aceso/apagado, junto com a luz).
uniform float blink_level = 1.0;
uniform vec3 led_color : source_color = vec3(0.3, 0.72, 1.0);
global uniform float night;

void fragment() {
	float e = mix(day_energy, night_energy, night);
	if (chase > 0.0) {
		float d = fract((UV.x - TIME * chase_speed) / chase_spacing);
		e *= 1.0 - chase + chase * 2.2 * smoothstep(0.82, 1.0, d) * (1.0 - smoothstep(0.985, 1.0, d)) + chase * 0.35;
	}
	e *= blink_level;
	ALBEDO = (use_led_color ? led_color : COLOR.rgb) * e;
	ROUGHNESS = 0.0;
}
