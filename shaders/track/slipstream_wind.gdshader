// Filetes de vento do vácuo: correm da frente do carro da frente (UV.x = 0) até o carro de trás
// (UV.x = 1). Traços que andam ao longo do filete, bordas suaves (UV.y) e força pelo vácuo.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float strength = 0.0;
uniform vec4 wind_color : source_color = vec4(0.7, 0.92, 1.0, 1.0);

void fragment() {
	float seed = COLOR.r * 17.0;
	float flow = fract(UV.x * 3.2 - TIME * 2.4 + seed);
	float dash = smoothstep(0.0, 0.25, flow) * (1.0 - smoothstep(0.55, 0.95, flow));
	float edge = 1.0 - abs(UV.y * 2.0 - 1.0);
	float ends = smoothstep(0.0, 0.12, UV.x) * (1.0 - smoothstep(0.85, 1.0, UV.x));
	ALBEDO = wind_color.rgb;
	ALPHA = strength * dash * edge * edge * ends * COLOR.a * 0.95;
}
