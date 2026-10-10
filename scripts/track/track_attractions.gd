class_name TrackAttractions
extends RefCounted
## Atrações em volta da pista (TrackFeature FERRIS_WHEEL): a roda-gigante do parque de diversões
## de Suzuka. Vem depois do terreno (apoia no chão) e antes das árvores (a área fica livre).


## Distância lateral (m, a partir do eixo) do centro da atração `f` na amostra i.
static func lateral(track: RaceTrack, f: TrackFeature, i: int, side: int) -> float:
	return track.path.half_width(i, side) + track.outer_distance(i, side) + f.distance


## Meia-largura (m) da área ocupada pela atração, ao longo da pista e para fora.
static func half_extent(f: TrackFeature) -> float:
	return f.rows * 0.42


static func build(track: RaceTrack, terrain: TrackTerrain, parent: Node3D) -> void:
	var p := track.path
	for f in track.layout.features:
		if f == null or f.kind != TrackFeature.Kind.FERRIS_WHEEL:
			continue
		var side: int = f.sides()[0]
		var i := p.index_at(f.s_start)
		var center := p.points[i] + p.lefts[i] * side * lateral(track, f, i, side)
		var wheel := FerrisWheel.create(float(f.rows))
		# Roda de frente para a pista (eixo na direção lateral); a base no ponto mais baixo do chão
		var axis := p.lefts[i]
		var basis := Basis(axis, Vector3.UP, axis.cross(Vector3.UP).normalized())
		var ground := INF
		var e := half_extent(f)
		for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2.ZERO]:
			var q: Vector3 = center + basis.x * d.x * 6.0 + basis.z * d.y * e * 0.8
			ground = minf(ground, terrain.height_at(q.x, q.z) if terrain else p.points[i].y)
		center.y = ground - 0.2
		wheel.transform = Transform3D(basis, center)
		parent.add_child(wheel)
		# Sem árvores em volta
		var poly := PackedVector2Array()
		for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var q: Vector3 = center + basis.x * d.x * 14.0 + basis.z * d.y * (e + 4.0)
			poly.append(Vector2(q.x, q.z))
		track.footprints.append(poly)
