// Pedra de Atlântida visível dos dois lados (coberturas finas, placas, estandartes de pedra).
shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_disabled;

#define SEA_STONE
#include "res://shaders/track/sea_stone_common.gdshaderinc"
#include "res://shaders/track/building_common.gdshaderinc"
