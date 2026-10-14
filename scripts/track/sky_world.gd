class_name SkyWorld
extends RefCounted
## O mundo em volta da pista no céu (Sky Aerobase): o mar lá embaixo (layout.sea_level), um tapete
## de nuvens com buracos por onde se vê o mar, nuvens 3D em três camadas (abaixo, no nível da
## pista e altas) e bandos de gaivotas. Nada aqui tem colisão: quem cai da pista atravessa tudo.

## Altura do tapete de nuvens acima do mar (m).
const CLOUD_DECK_ABOVE_SEA := 950.0
const SEA_SIZE := 60000.0
## As nuvens no nível da pista ficam pelo menos a isso do traçado (e paradas: não cruzam a pista).
const TRACK_CLEARANCE := 140.0
## Fração da névoa normal do período (o ar no alto é limpo).
const FOG := 0.35
## De dia o céu lá em cima é azul até o horizonte e embaixo dele (sem o branco leitoso do chão):
## topo, horizonte, abaixo do horizonte e a cor da névoa.
const DAY_SKY := [Color(0.08, 0.32, 0.9), Color(0.36, 0.62, 0.98), Color(0.24, 0.5, 0.92), Color(0.5, 0.72, 1.0)]

static var _cloud_deck: ShaderMaterial


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "SkyWorld"
	parent.add_child(root)
	var bounds := track.path.bounds()
	var center := Vector3(bounds.get_center().x, 0.0, bounds.get_center().y)
	var radius := bounds.size.length() * 0.5
	_sea(track, root, center)
	_deck(track, root, center)
	var animator := SceneryAnimator.new()
	animator.name = "Animator"
	root.add_child(animator)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7123
	_clouds(track, root, animator, rng, center, radius)
	TrackLife._birds(track, null, rng, root, animator)
	TrackLife._garage_crews(track, rng, root)


static func _sea(track: RaceTrack, root: Node3D, center: Vector3) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/water.gdshader")
	mat.set_shader_parameter("normal_a", TrackHarbour._wave_normal(0.018, 7))
	mat.set_shader_parameter("normal_b", TrackHarbour._wave_normal(0.05, 13))
	mat.set_shader_parameter("far_plane", true)
	var mb := MeshBuilder.new()
	var h := SEA_SIZE * 0.5
	mb.quad(Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h), Color.WHITE, Vector3.UP)
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = mb.commit(null, mat)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.position = center + Vector3.UP * track.layout.sea_level
	root.add_child(sea)


## Tapete de nuvens (cloud_deck.gdshader) num plano do tamanho do mar.
static func _deck(track: RaceTrack, root: Node3D, center: Vector3) -> void:
	if _cloud_deck == null:
		_cloud_deck = ShaderMaterial.new()
		_cloud_deck.shader = load("res://shaders/track/cloud_deck.gdshader")
	_cloud_deck.set_shader_parameter("center", center)
	var mb := MeshBuilder.new()
	var h := SEA_SIZE * 0.5
	mb.quad(Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h), Color.WHITE, Vector3.UP)
	var deck := MeshInstance3D.new()
	deck.name = "CloudDeck"
	deck.mesh = mb.commit(null, _cloud_deck)
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deck.position = center + Vector3.UP * (track.layout.sea_level + CLOUD_DECK_ABOVE_SEA)
	root.add_child(deck)


## Nuvens 3D fofas (a malha do TrackScenery): abaixo e no alto levadas pelo vento; no nível da pista,
## paradas e longe do traçado.
static func _clouds(track: RaceTrack, root: Node3D, animator: SceneryAnimator, rng: RandomNumberGenerator,
		center: Vector3, radius: float) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/cloud.gdshader")
	var meshes: Array[ArrayMesh] = []
	for v in 3:
		meshes.append(TrackScenery._cloud_mesh(rng, 6 + v * 3))
	var low_y := track.layout.sea_level + CLOUD_DECK_ABOVE_SEA
	# [nome, quantidade, altura mín, máx, escala mín, máx, raio da área, animadas]
	var layers := [
		["Below", 50, low_y + 60.0, -140.0, 70.0, 200.0, radius + 4500.0, true],
		["Level", 26, -40.0, 80.0, 35.0, 95.0, radius + 1400.0, false],
		["High", 40, 450.0, 1300.0, 70.0, 180.0, radius + 6000.0, true],
	]
	for layer in layers:
		var area: float = layer[6]
		var transforms := [[] as Array[Transform3D], [] as Array[Transform3D], [] as Array[Transform3D]]
		var placed := 0
		var tries := 0
		while placed < layer[1] and tries < layer[1] * 20:
			tries += 1
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf_range(0.02, 1.0)) * area
			var pos := Vector3(center.x + cos(a) * r, rng.randf_range(layer[2], layer[3]), center.z + sin(a) * r)
			var s := rng.randf_range(layer[4], layer[5])
			if not layer[7] and absf(track.path.project(pos).y) < TRACK_CLEARANCE + s:
				continue
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.6, 0.95), s))
			transforms[placed % 3].append(Transform3D(basis, pos))
			placed += 1
		for v in 3:
			var list: Array[Transform3D] = transforms[v]
			if list.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[v]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Clouds%s%d" % [layer[0], v]
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
			if layer[7]:
				mmi.custom_aabb = AABB(Vector3(-30000, -3000, -30000), Vector3(60000, 6000, 60000))
				animator.add_clouds(mm, list, Vector2(center.x, center.z), area)


## Período do dia: cores do tapete de nuvens, o "chão" do céu abaixo do horizonte da cor do mar
## distante e a névoa rasteira levada para baixo (a pista fica acima dela).
static func apply_mood(track: RaceTrack, time_of_day: int) -> void:
	var t: Dictionary = DaylightPresets.TIMES[time_of_day]
	if _cloud_deck:
		_cloud_deck.set_shader_parameter("lit_color", t.cloud_lit)
		_cloud_deck.set_shader_parameter("shade_color", t.cloud_shade)
		_cloud_deck.set_shader_parameter("coverage", 0.36 if time_of_day != DaylightPresets.TimeOfDay.NIGHT else 0.3)
	if not track.is_inside_tree():
		return
	var daylight := track.get_tree().get_first_node_in_group("daylight") as Node3D
	if daylight == null:
		return
	var we := daylight.get_node_or_null("WorldEnvironment") as WorldEnvironment
	# Ar limpo lá em cima: menos névoa (senão o mar, 1,4 km abaixo, some no branco)
	if we and we.environment:
		we.environment.fog_density = t.fog_density * Daylight.FOG_SCALE * FOG
	if we and we.environment and we.environment.sky:
		var sky := we.environment.sky.sky_material as ShaderMaterial
		if sky and time_of_day == DaylightPresets.TimeOfDay.DAY:
			sky.set_shader_parameter("top_color", DAY_SKY[0])
			sky.set_shader_parameter("horizon_color", DAY_SKY[1])
			sky.set_shader_parameter("ground_color", DAY_SKY[2])
			we.environment.fog_light_color = DAY_SKY[3]
		elif sky:
			var horizon: Color = sky.get_shader_parameter("horizon_color")
			sky.set_shader_parameter("ground_color", horizon.lerp(t.cloud_shade, 0.35))
	var mist := daylight.get_node_or_null("GroundMist") as Node3D
	if mist:
		mist.position.y = track.layout.sea_level + CLOUD_DECK_ABOVE_SEA
