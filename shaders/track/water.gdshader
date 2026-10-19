// Mar (opaco, estilo anime): ondas no vértice (calmas dentro do porto), dois normal maps
// rolando, cor rasa/funda pela distância da costa, fresnel com o céu, brilho do sol e espuma
// junto aos cais e nas cristas.
// shore_tex (2 m/pixel sobre shore_area): R = distância até a terra (0..48 m), G = porto (calmo).
// ROUGHNESS quase 0: o contorno anime (outline_post) não desenha a água.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/track/water_common.gdshaderinc"
