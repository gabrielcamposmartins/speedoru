// Piso da pista fofa nas nuvens (ver track_surface_common.gdshaderinc): toon com brilho de verniz.
shader_type spatial;
render_mode diffuse_toon, specular_schlick_ggx;

#define SURFACE_GLOSS
#include "res://shaders/track/track_surface_common.gdshaderinc"
