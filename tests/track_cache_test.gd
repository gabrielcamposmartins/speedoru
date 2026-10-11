extends SceneTree
## Pista do servidor copiada do cache (sem janela): a cópia de cada sala tem a mesma colisão da
## pista gerada — inclusive as barreiras e os muros do corte, cujos shapes são criados direto no
## corpo (create_shape_owner) e que o duplicate() não copia. Confere a contagem de shapes e lança
## raios do meio da pista para fora: têm que bater na barreira.
##   godot --headless --path . -s res://tests/track_cache_test.gd -- --server

var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RaceTrack.server_mode = true
	var host := Node.new()
	root.add_child(host)
	var scenes := RaceSettings.TRACKS.map(func(t: Dictionary) -> String: return t["scene"])
	await RaceTrack.prewarm_server(host, scenes)
	for t: Dictionary in RaceSettings.TRACKS:
		print(t["name"])
		var scene := (load(t["scene"]) as PackedScene).instantiate()
		var track: RaceTrack = scene.find_children("*", "RaceTrack", true, false)[0]
		track.get_parent().remove_child(track)
		track.owner = null
		scene.free()
		var world := SubViewport.new()
		world.own_world_3d = true
		world.size = Vector2i(2, 2)
		world.render_target_update_mode = SubViewport.UPDATE_DISABLED
		host.add_child(world)
		world.add_child(track)
		if not track.is_built:
			await track.built
		var cached: Dictionary = RaceTrack._server_cache[track._cache_key()]
		var gen := track.get_node("Generated")
		_check(RaceTrack.count_shapes(gen) == int(cached["shape_count"]),
			"cópia com os mesmos shapes da pista gerada (%d de %d)" % [RaceTrack.count_shapes(gen), cached["shape_count"]])
		await physics_frame
		await physics_frame
		var space := world.find_world_3d().direct_space_state
		var p := track.path
		var tried := 0
		var hits := 0
		for i in range(0, p.size(), maxi(p.size() / 60, 1)):
			for side in [1, -1]:
				var si := 0 if side > 0 else 1
				var dist: float = track.barrier[si][i]
				if track.barrier_kind[si][i] == RaceTrack.Barrier.NONE or dist > 25.0:
					continue
				var from: Vector3 = p.points[i] + Vector3.UP * 0.4
				var to: Vector3 = track.edge_point(i, side, dist + 2.0, 0.4)
				var q := PhysicsRayQueryParameters3D.create(from, to)
				tried += 1
				if not space.intersect_ray(q).is_empty():
					hits += 1
		_check(tried > 20 and hits >= tried * 0.9, "raios do meio da pista batem na barreira (%d de %d)" % [hits, tried])
		world.queue_free()
		await process_frame
	RaceTrack.clear_server_cache()
	print("\ntrack_cache_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)
