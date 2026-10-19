// Superfície do mar da Atlantis Abyss vista de cima: o mesmo mar do water.gdshader, sem a água
// dentro do tubo de vidro onde ele atravessa a linha d'água (sea_carve.gdshaderinc), para os carros
// não parecerem correr dentro d'água na subida para o Portão de Poseidon e no mergulho de volta.
shader_type spatial;
render_mode cull_back;

#define CARVE
#include "res://shaders/track/water_common.gdshaderinc"
