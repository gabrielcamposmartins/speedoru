shader_type spatial;
// Neon e lâmpadas dos letreiros de Las Vegas (CityNeon): sem luz, a cor de vértice (linear) é a do
// tubo; de dia acesa mas contida, à noite forte (passa de 1 e o glow do ambiente espalha).
// Alfa da cor de vértice: 1 = aceso direto; < 1 = lâmpada de letreiro em sequência ("chaser"), o alfa
// é a fase (lâmpadas vizinhas com fases 0, .25, .5, .75 fazem a luz correr).
render_mode unshaded, cull_disabled;

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float day_level = 0.9;
uniform float night_level = 3.4;
uniform float chase_speed = 1.6;

void fragment() {
	float lvl = mix(day_level, night_level, night);
	float on = 1.0;
	if (COLOR.a < 0.99) {
		float ph = fract(TIME * chase_speed - COLOR.a);
		on = ph < 0.5 ? 1.0 : 0.28;
	}
	ALBEDO = COLOR.rgb * lvl * on;
}
