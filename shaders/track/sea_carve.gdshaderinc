// Recorte da superfície do mar da Atlantis Abyss onde o tubo de vidro atravessa a linha d'água
// (SeaTube.surface_carve): lá dentro do tubo não há água, então nem o mar visto de cima
// (sea_surface.gdshader) nem o teto visto de baixo (sea_ceiling.gdshader) são desenhados.
// carve_tex: vista de cima, R > 0,5 = dentro do tubo; carve_area = (x0, z0, x1, z1) que ela cobre
// (vazia = sem recorte).
uniform sampler2D carve_tex : filter_linear, repeat_disable;
uniform vec4 carve_area = vec4(0.0);

bool sea_carved(vec2 p) {
	if (carve_area.z <= carve_area.x) {
		return false;
	}
	vec2 uv = (p - carve_area.xy) / (carve_area.zw - carve_area.xy);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return false;
	}
	return textureLod(carve_tex, uv, 0.0).r > 0.5;
}
