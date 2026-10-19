// Pedra de Atlântida (pista no fundo do mar): o material das construções (building_common) com a
// pedra clareada para mármore/calcário, musgo e algas nas faces de cima, manchas de coral perto da
// base e a cáustica da água (caustics.gdshaderinc).
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

#define SEA_STONE
#include "res://shaders/track/sea_stone_common.gdshaderinc"
#include "res://shaders/track/building_common.gdshaderinc"
