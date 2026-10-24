// Construções da Rainbow Raceway vistas dos dois lados (telhados finos, bandeiras, placas): plástico
// pastel (ver candy_common.gdshaderinc).
shader_type spatial;
render_mode diffuse_toon, specular_toon, cull_disabled;

#define CANDY_TWO_SIDED
#include "res://shaders/track/candy_common.gdshaderinc"
