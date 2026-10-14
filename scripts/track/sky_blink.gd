class_name SkyBlink
extends Node
## Faróis piscando (dirigíveis da Sky Aerobase): as luzes registradas acendem por um instante a cada
## PERIOD segundos, junto com o brilho dos materiais registrados (sky_glow.gdshader, blink_level).
## À noite a luz tem a força de base; de dia fica apagada (o brilho do farol continua piscando).

const PERIOD := 1.4
## Fração do período com o farol aceso.
const ON := 0.15

var lights: Array[Light3D] = []
var materials: Array[ShaderMaterial] = []


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var on := fmod(t / PERIOD, 1.0) < ON
	var night := Daylight.current_night
	for mat in materials:
		mat.set_shader_parameter("blink_level", 1.6 if on else 0.05)
	for light in lights:
		if is_instance_valid(light):
			light.visible = on and night > 0.05
			light.light_energy = float(light.get_meta("base_energy", 4.0)) * night
