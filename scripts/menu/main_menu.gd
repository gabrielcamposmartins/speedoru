extends Node3D
## Menu principal na garagem: botões grandes à esquerda (Jogar solo, Multiplayer, Garagem,
## Configurações, Sair) e o carro do jogador à direita, visto do nordeste por uma câmera orbital
## (gira devagar sozinha; arrastar com o mouse gira, a roda aproxima).
##
## Três cenários (escolhidos na garagem, salvos no perfil): "neon" (garagem noturna com neon),
## "sun" (pátio ao sol com prédio dos boxes, tenda e bandeiras) e "box" (box de F1: ferramentas,
## pneus com mantas, monitores, porta aberta para o pit lane). No Estúdio o carro vem para o
## centro-esquerda (o painel fica à direita); na Galeria e na Loja ele vai para a direita.

const RACE_SCENE := "res://scenes/tracks/monza.tscn"
const CAR_SCENE := preload("res://scenes/car/f1_car.tscn")
const SCENES := [["neon", "Garagem neon"], ["sun", "Ao sol"], ["box", "No box"]]

## Direção da câmera: nordeste do carro (frente-direita; o carro olha para +Z, a direita é -X).
const BASE_YAW := deg_to_rad(-45.0)
## Altura do piso onde o carro pousa (todos os cenários).
const FLOOR_Y := 0.08

var car: F1Car
var camera: Camera3D
var ui: MenuUI
var scene_kind := "neon"
## Quanto o carro fica deslocado para a direita (fração da distância); negativo = para a esquerda.
var car_shift := 0.26

var _set: Node3D
var _shift := 0.26
## Foco da câmera (Galeria): alvo, distância e altura que a câmera persegue; null = normal.
var _focus_target := Vector3(0, 0.55, 0.2)
var _focus_distance := 10.5
var _focused := false
var _clockwise := true
var _orbit_tween: Tween
var _previewing := false
var _yaw := BASE_YAW
var _pitch := deg_to_rad(16.0)
var _distance := 10.5
var _drag := false
var _idle := 0.0
var _profile: PlayerProfile


func _ready() -> void:
	_profile = get_node("/root/Profile") as PlayerProfile
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	ground.position = Vector3(0, FLOOR_Y, 0)
	add_child(ground)
	scene_kind = str(_profile.equipped.get("scene", "neon"))
	build_scene(scene_kind)
	_spawn_car()
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.current = true
	add_child(camera)
	ui = MenuUI.new()
	ui.menu = self
	add_child(ui)
	_update_camera(0.0)
	LoadingScreen.done()


func _process(delta: float) -> void:
	_idle += delta
	if not _drag and not _focused and _idle > 2.5:
		# Órbita lenta ao redor do nordeste (vai e volta)
		var target := BASE_YAW + sin(Time.get_ticks_msec() / 1000.0 * 0.12) * deg_to_rad(28.0)
		_yaw = lerp_angle(_yaw, target, 1.0 - exp(-0.6 * delta))
	_update_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = mb.pressed
			_idle = 0.0
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance - 0.4, 3.5 if _focused else 7.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance + 0.4, 15.0)
	elif event is InputEventMouseMotion and _drag:
		if _orbit_tween:
			_orbit_tween.kill()
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.006
		_pitch = clampf(_pitch + mm.relative.y * 0.004, deg_to_rad(4.0), deg_to_rad(48.0))
		_idle = 0.0


func _update_camera(delta: float) -> void:
	_shift = lerpf(_shift, car_shift, 1.0 - exp(-4.0 * delta)) if delta > 0.0 else car_shift
	var target := _focus_target
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	camera.global_position = target + dir * _distance
	camera.look_at(target, Vector3.UP)
	camera.h_offset = -_distance * _shift
	camera.v_offset = 0.2


# ---------------------------------------------------------------------------
# Prévia e foco (Galeria)
# ---------------------------------------------------------------------------
## Pontos do carro para centralizar (coordenadas locais: frente = +Z, esquerda = +X) e o ângulo
## de onde olhar: [ponto, yaw relativo ao carro, pitch (graus), distância].
const FOCUS := {
	"front_wing": [Vector3(0, 0.15, 2.55), 0.55, 18.0, 4.6],
	"nose": [Vector3(0, 0.35, 1.8), 0.7, 22.0, 4.4],
	"rear_wing": [Vector3(0, 0.85, -2.35), PI - 0.6, 18.0, 4.8],
	"sidepods": [Vector3(-0.65, 0.42, -0.2), -PI / 2.0 + 0.25, 16.0, 4.6],
	"engine_cover": [Vector3(0, 0.75, -1.0), PI - 0.9, 32.0, 4.6],
	"rim": [Vector3(-0.85, 0.33, 1.62), -PI / 2.0 + 0.45, 10.0, 3.6],
	"helmet": [Vector3(0, 0.85, 0.35), -0.5, 28.0, 3.6],
	"suit": [Vector3(0, 0.8, 0.2), -0.6, 34.0, 3.8],
	"neon": [Vector3(0, 0.05, 0.0), -0.9, 6.0, 6.0],
	"boost": [Vector3(-0.85, 0.33, -1.55), -PI / 2.0 - 0.4, 10.0, 4.0],
}


## Mostra no carro como ficaria uma peça da coleção (sem equipar) e, se ela tem um lugar no carro,
## gira a câmera até lá: cada vez num sentido (horário, anti-horário, …).
func preview_item(id: String) -> void:
	var it := ShopCatalog.item(id)
	if it.is_empty() or car == null:
		return
	var cfg: CarConfig = car.config.duplicate(true) if car.config else CarConfig.new()
	_profile.apply_to_config(cfg)
	var cols := ShopCatalog.colors_of(id)
	var focus_key := ""
	match it["type"]:
		"livery":
			cfg.primary_color = cols[0]
			cfg.secondary_color = cols[1]
			cfg.accent_color = cols[2]
		"helmet":
			cfg.helmet_color = cols[0]
			focus_key = "helmet"
		"suit":
			cfg.suit_color = cols[0]
			focus_key = "suit"
		"rim":
			cfg.rim_color = cols[0]
			focus_key = "rim"
		"boost":
			cfg.boost_color = cols[0]
			focus_key = "boost"
		"neon":
			cfg.neon_enabled = true
			cfg.neon_color = cols[0]
			focus_key = "neon"
		"part":
			cfg.set_part(it["slot"], it["variant"])
			focus_key = it["slot"]
	car.config = cfg
	_previewing = true
	if focus_key != "" and FOCUS.has(focus_key):
		focus_on(focus_key)
	else:
		clear_focus()


## Volta o carro para o que está equipado e a câmera para a órbita normal.
func clear_preview() -> void:
	if _previewing and car and car.config:
		_profile.apply_to_config(car.config)
	_previewing = false
	clear_focus()


func focus_on(key: String) -> void:
	var f: Array = FOCUS[key]
	var car_yaw := car.global_rotation.y
	var target_yaw: float = car_yaw + f[1]
	# Gira até o ângulo da peça, alternando o sentido a cada clique
	var delta := fposmod(target_yaw - _yaw, TAU)
	if not _clockwise:
		delta -= TAU
	_clockwise = not _clockwise
	_focused = true
	if _orbit_tween:
		_orbit_tween.kill()
	_orbit_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_orbit_tween.tween_property(self, "_yaw", _yaw + delta, 1.3)
	_orbit_tween.tween_property(self, "_pitch", deg_to_rad(f[2]), 1.3)
	_orbit_tween.tween_property(self, "_distance", f[3], 1.3)
	_orbit_tween.tween_property(self, "_focus_target", car.global_transform * (f[0] as Vector3), 1.3)


func clear_focus() -> void:
	if not _focused:
		return
	_focused = false
	if _orbit_tween:
		_orbit_tween.kill()
	_orbit_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_orbit_tween.tween_property(self, "_pitch", deg_to_rad(16.0), 1.0)
	_orbit_tween.tween_property(self, "_distance", 10.5, 1.0)
	_orbit_tween.tween_property(self, "_focus_target", Vector3(0, 0.55, 0.2), 1.0)


## Troca o cenário (e salva a escolha no perfil).
func set_scene(kind: String) -> void:
	if kind == scene_kind:
		return
	scene_kind = kind
	_profile.equipped["scene"] = kind
	_profile.save_profile()
	build_scene(kind)


func build_scene(kind: String) -> void:
	if _set:
		_set.queue_free()
	_set = Node3D.new()
	_set.name = "Set"
	add_child(_set)
	match kind:
		"sun":
			_build_sun()
		"box":
			_build_box()
		_:
			_build_neon()


# ---------------------------------------------------------------------------
# Peças
# ---------------------------------------------------------------------------
func _mat(color: Color, rough := 0.6, metal := 0.0, emission := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


var _tex_cache := {}


## Material com várias texturas procedurais (em cache): cor com manchas grandes (ruído em
## degradê), detalhe multiplicado (rejunte/emendas de uma grade, ou sujeira fina), normal map de
## ruído e rugosidade variando. Triplanar em coordenadas do mundo: [param tile] = metros por
## repetição; [param grid] = células por repetição (0 = sem grade, usa sujeira).
func _tmat(base: Color, rough := 0.7, metal := 0.0, tile := 4.0, contrast := 0.16, bump := 0.6,
		grid := Vector2.ZERO, grid_line := 0.03, grid_color := Color(0, 0, 0, 0.55), seed_v := 1) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f|%.2f|%.2f|%s|%.3f|%s|%d" % [base.to_html(), rough, metal, tile, contrast, bump, grid, grid_line,
		grid_color.to_html(), seed_v]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.roughness = rough
	m.metallic = metal
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	# 1. Cor: manchas grandes
	var g := Gradient.new()
	g.colors = PackedColorArray([base.darkened(contrast), base, base.lightened(contrast * 0.6)])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	m.albedo_texture = _noise_tex(seed_v, 0.006, 4, g)
	# 2. Normal: relevo fino
	if bump > 0.0:
		var n := _noise_tex(seed_v + 11, 0.03, 5, null)
		n.as_normal_map = true
		n.bump_strength = bump * 6.0
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = bump
	# 3. Rugosidade irregular
	var rg := Gradient.new()
	rg.colors = PackedColorArray([Color(rough * 0.6, rough * 0.6, rough * 0.6), Color(minf(rough * 1.3, 1.0), minf(rough * 1.3, 1.0), minf(rough * 1.3, 1.0))])
	m.roughness_texture = _noise_tex(seed_v + 23, 0.012, 3, rg)
	m.roughness = 1.0
	# 4. Detalhe multiplicado: grade (rejunte/emendas) ou sujeira fina
	m.detail_enabled = true
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	if grid != Vector2.ZERO:
		m.detail_albedo = _grid_tex(grid, grid_line, grid_color)
	else:
		var dg := Gradient.new()
		dg.colors = PackedColorArray([Color(0.72, 0.7, 0.68), Color(1, 1, 1), Color(1, 1, 1)])
		dg.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		m.detail_albedo = _noise_tex(seed_v + 37, 0.05, 3, dg)
	_tex_cache[key] = m
	return m


func _noise_tex(seed_v: int, freq: float, octaves: int, ramp: Gradient) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.seed = seed_v
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = fn
	if ramp:
		t.color_ramp = ramp
	return t


## Textura de grade (branca com linhas) para o detalhe multiplicado: rejunte de piso, emendas de
## painéis de parede.
func _grid_tex(cells: Vector2, line: float, color: Color) -> ImageTexture:
	var size := 512
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var lw := maxi(int(line * size), 1)
	var c := Color.WHITE.lerp(Color(color.r, color.g, color.b), color.a)
	if cells.x > 0.0:
		for k in int(cells.x):
			var x := int(k * size / cells.x)
			img.fill_rect(Rect2i(x, 0, lw, size), c)
	if cells.y > 0.0:
		for k in int(cells.y):
			var y := int(k * size / cells.y)
			img.fill_rect(Rect2i(0, y, size, lw), c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _mesh(mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale
	_set.add_child(mi)
	return mi


func _box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _mesh(bm, pos, mat, rot)


func _cyl(radius: float, height: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, top := -1.0) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius if top < 0.0 else top
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 24
	return _mesh(cm, pos, mat, rot)


func _tyre(pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.36
	_mesh(tm, pos, mat, rot, Vector3(1, 0.75, 1))


func _env(env: Environment) -> void:
	var we := WorldEnvironment.new()
	we.environment = env
	_set.add_child(we)


func _spot(pos: Vector3, look: Vector3, energy: float, angle: float, color := Color.WHITE, shadows := true) -> void:
	var s := SpotLight3D.new()
	s.position = pos
	_set.add_child(s)
	s.look_at(look, Vector3.UP if absf((look - pos).normalized().y) < 0.95 else Vector3.FORWARD)
	s.spot_angle = angle
	s.spot_range = 18.0
	s.light_energy = energy
	s.light_color = color
	s.shadow_enabled = shadows


func _omni(pos: Vector3, color: Color, energy: float, radius := 9.0) -> void:
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = color
	o.light_energy = energy
	o.omni_range = radius
	_set.add_child(o)


func _sign(text: String, size: int, pos: Vector3, color: Color, rot_y := -PI / 2.0, glow := true) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Retro.display(900)
	l.font_size = size
	l.pixel_size = 0.006
	l.modulate = color
	if glow:
		l.outline_modulate = Color(color, 0.35)
		l.outline_size = 24
	l.shaded = not glow
	l.position = pos
	l.rotation.y = rot_y
	_set.add_child(l)


# ---------------------------------------------------------------------------
# Objetos de cena (reaproveitados nos três cenários)
# ---------------------------------------------------------------------------
func _crate(pos: Vector3, size := Vector3(0.9, 0.7, 0.9), rot := 0.0) -> void:
	var wood := _tmat(Color("8a6a45"), 0.85, 0.0, 1.2, 0.25, 0.9, Vector2(0, 5), 0.012, Color(0.2, 0.12, 0.05, 0.6), 7)
	_box(size, pos + Vector3(0, size.y * 0.5, 0), wood, Vector3(0, rot, 0))
	_box(Vector3(size.x + 0.02, 0.06, 0.08), pos + Vector3(0, size.y * 0.5, 0), _mat(Color("5e4630"), 0.8), Vector3(0, rot, 0))


func _barrel(pos: Vector3, color: Color) -> void:
	var paint := _tmat(color, 0.55, 0.5, 1.5, 0.22, 0.4, Vector2.ZERO, 0.0, Color.BLACK, 13)
	_cyl(0.3, 0.88, pos + Vector3(0, 0.44, 0), paint)
	for h in [0.2, 0.68]:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.3
		ring.outer_radius = 0.32
		_mesh(ring, pos + Vector3(0, h, 0), _mat(color.darkened(0.3), 0.5, 0.6))


func _extinguisher(pos: Vector3) -> void:
	_cyl(0.09, 0.5, pos + Vector3(0, 0.25, 0), _mat(Color("c8102e"), 0.35, 0.3))
	_cyl(0.04, 0.1, pos + Vector3(0, 0.55, 0), _mat(Color("1a1a1a"), 0.5, 0.5))


func _shelf(pos: Vector3, rot := 0.0, width := 2.0, colors: Array = []) -> void:
	var steel := _mat(Color("6f737c"), 0.4, 0.8)
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = rot
	_set.add_child(holder)
	var prev := _set
	_set = holder
	for x in [-width * 0.5, width * 0.5]:
		for z in [-0.25, 0.25]:
			_box(Vector3(0.05, 2.0, 0.05), Vector3(x, 1.0, z), steel)
	for h in [0.1, 0.75, 1.4, 1.95]:
		_box(Vector3(width + 0.05, 0.04, 0.55), Vector3(0, h, 0), steel)
	var palette := colors if not colors.is_empty() else [Color("2f6bff"), Color("ffd21f"), Color("c8102e"), Color("e8e8e8")]
	var k := 0
	for h in [0.12, 0.77, 1.42]:
		var x := -width * 0.5 + 0.25
		while x < width * 0.5 - 0.2:
			var w := 0.25 + float((k * 37) % 5) * 0.06
			var hh := 0.2 + float((k * 13) % 4) * 0.08
			_box(Vector3(w, hh, 0.4), Vector3(x + w * 0.5, h + hh * 0.5 + 0.02, 0), _mat(palette[k % palette.size()], 0.6))
			x += w + 0.08
			k += 1
	_set = prev


func _poster(pos: Vector3, rot_y: float, size: Vector2, a: Color, b: Color, text: String) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = rot_y
	_set.add_child(holder)
	var g := Gradient.new()
	g.colors = PackedColorArray([a, b])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.albedo_texture = gt
	m.roughness = 0.6
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	holder.add_child(mi)
	var l := Label3D.new()
	l.text = text
	l.font = Retro.display(900)
	l.font_size = int(size.y * 60)
	l.pixel_size = 0.006
	l.position = Vector3(0, 0, 0.01)
	l.modulate = Color.WHITE
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.4)
	holder.add_child(l)


func _tool_cart(pos: Vector3, color: Color, rot := 0.0) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = rot
	_set.add_child(holder)
	var prev := _set
	_set = holder
	var body := _tmat(color, 0.4, 0.35, 2.0, 0.12, 0.3, Vector2.ZERO, 0.0, Color.BLACK, 17)
	var steel := _mat(Color("c9ccd2"), 0.3, 0.9)
	_box(Vector3(1.1, 1.0, 0.6), Vector3(0, 0.55, 0), body)
	for d in 5:
		_box(Vector3(0.95, 0.015, 0.01), Vector3(0, 0.22 + d * 0.17, 0.305), steel)
	_box(Vector3(1.14, 0.04, 0.64), Vector3(0, 1.07, 0), _mat(Color("1d1e22"), 0.6))
	for x in [-0.45, 0.45]:
		for z in [-0.22, 0.22]:
			_cyl(0.05, 0.04, Vector3(x, 0.05, z), _mat(Color("111"), 0.6), Vector3(PI / 2.0, 0, 0))
	# Ferramentas em cima
	_box(Vector3(0.3, 0.05, 0.05), Vector3(-0.2, 1.12, 0.1), steel, Vector3(0, 0.4, 0))
	_box(Vector3(0.22, 0.04, 0.04), Vector3(0.2, 1.12, -0.05), _mat(Color("ffd21f"), 0.5), Vector3(0, -0.6, 0))
	_set = prev


func _tyre_stack(pos: Vector3, count: int, mat: Material, band: Material = null) -> void:
	for h in count:
		_tyre(pos + Vector3(0, 0.1 + h * 0.2, 0), mat)
	if band:
		var tor := TorusMesh.new()
		tor.inner_radius = 0.3
		tor.outer_radius = 0.33
		_mesh(tor, pos + Vector3(0, 0.1 + (count - 1) * 0.2 + 0.08, 0), band)


func _lamp(pos: Vector3, color: Color, energy: float) -> void:
	_box(Vector3(0.5, 0.05, 0.25), pos, _mat(Color.WHITE, 0.5, 0.0, color, 3.0))
	_omni(pos + Vector3(0, -0.3, 0), color, energy, 5.0)


# ---------------------------------------------------------------------------
# Cenário 1: garagem neon (noite)
# ---------------------------------------------------------------------------
func _build_neon() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("07060d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("3a3550")
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_hdr_threshold = 1.4
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.ssr_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color("140f24")
	env.fog_density = 0.003
	_env(env)
	var accent := Retro.c("accent")
	var accent2 := Retro.c("accent_2")
	# Piso de concreto polido escuro com placas de 1,5 m; plataforma metálica com anel de neon
	var floor_mat := _tmat(Color("1b1a22"), 0.22, 0.35, 6.0, 0.35, 0.5, Vector2(4, 4), 0.006, Color(0, 0, 0, 0.7), 3)
	_box(Vector3(40.0, 0.02, 40.0), Vector3(0, -0.01, 0), floor_mat)
	var paint := _mat(Color("e8c32a"), 0.5)
	for x in [-3.4, 3.4]:
		_box(Vector3(0.12, 0.004, 9.0), Vector3(x, 0.002, 0.2), paint)
	_box(Vector3(6.92, 0.004, 0.12), Vector3(0, 0.002, -4.3), paint)
	var plate := _tmat(Color("2a2935"), 0.3, 0.8, 1.0, 0.12, 1.2, Vector2(10, 10), 0.01, Color(0, 0, 0, 0.5), 9)
	_cyl(3.5, FLOOR_Y, Vector3(0, FLOOR_Y * 0.5, 0.2), plate, Vector3.ZERO, 3.4)
	var tm := TorusMesh.new()
	tm.inner_radius = 3.42
	tm.outer_radius = 3.52
	tm.rings = 64
	_mesh(tm, Vector3(0, FLOOR_Y, 0.2), _mat(accent, 0.4, 0.0, accent, 2.2))
	# Paredes de painéis metálicos com emendas e sujeira; faixas de neon
	var wall := _tmat(Color("2e2d3a"), 0.75, 0.3, 3.0, 0.22, 0.5, Vector2(2, 1), 0.008, Color(0, 0, 0, 0.6), 5)
	_box(Vector3(0.4, 7.0, 26.0), Vector3(9.5, 3.5, -2.0), wall)
	_box(Vector3(26.0, 7.0, 0.4), Vector3(-2.0, 3.5, -9.0), wall)
	var lower := _tmat(Color("3b3a4a"), 0.5, 0.5, 2.0, 0.18, 0.8, Vector2(4, 0), 0.01, Color(0, 0, 0, 0.6), 6)
	_box(Vector3(0.1, 1.2, 26.0), Vector3(9.25, 0.6, -2.0), lower)
	_box(Vector3(26.0, 1.2, 0.1), Vector3(-2.0, 0.6, -8.75), lower)
	for k in 5:
		var z := -7.0 + k * 3.6
		if z + 1.65 > 0.5:
			_box(Vector3(0.06, 4.2, 0.06), Vector3(9.18, 2.6, z + 1.65), _mat(accent2, 0.4, 0.0, accent2, 2.5))
	_box(Vector3(18.0, 0.08, 0.08), Vector3(-1.0, 5.2, -8.68), _mat(accent, 0.4, 0.0, accent, 2.5))
	_box(Vector3(0.08, 0.08, 18.0), Vector3(9.12, 5.2, -1.0), _mat(accent, 0.4, 0.0, accent, 2.5))
	_sign("SPEEDORU", 150, Vector3(9.05, 2.75, -4.2), accent.lightened(0.2))
	_sign("GARAGEM · EQUIPE AKANE", 64, Vector3(9.05, 2.05, -4.2), accent2)
	_sign("OPEN 24H", 70, Vector3(-9.5, 4.2, -8.7), Color("3dff6e"), 0.0)
	# Bancadas, estantes, carrinhos de ferramentas, tambores, caixotes, extintores
	for k in 3:
		_tool_cart(Vector3(-6.5 + k * 1.4, 0, -8.2), Color("b3122e"))
	_shelf(Vector3(-1.4, 0, -8.35), 0.0, 2.6)
	_shelf(Vector3(8.9, 0, 3.6), -PI / 2.0, 2.4)
	_barrel(Vector3(7.9, 0, 6.2), Color("2f6bff"))
	_barrel(Vector3(8.5, 0, 6.8), Color("e8c32a"))
	_barrel(Vector3(7.7, 0, 7.2), Color("2f6bff"))
	_crate(Vector3(-8.2, 0, -5.8))
	_crate(Vector3(-8.0, 0.7, -5.9), Vector3(0.7, 0.55, 0.7), 0.4)
	_crate(Vector3(-7.0, 0, -6.4), Vector3(0.9, 0.7, 0.9), 0.2)
	_extinguisher(Vector3(9.0, 0, -0.8))
	_extinguisher(Vector3(2.6, 0, -8.6))
	var tyre_mat := _mat(Color("101014"), 0.8)
	_tyre_stack(Vector3(7.6, 0, -6.8), 4, tyre_mat, _mat(Color("ffd21f"), 0.6))
	_tyre_stack(Vector3(7.6, 0, -5.4), 3, tyre_mat)
	_tyre_stack(Vector3(4.8, 0, -7.6), 4, tyre_mat, _mat(Color("c8102e"), 0.6))
	# Máquina de bebidas com frente iluminada e cartazes
	_box(Vector3(1.0, 2.0, 0.8), Vector3(4.6, 1.0, -8.3), _mat(Color("1a1a24"), 0.4, 0.4))
	_box(Vector3(0.8, 1.4, 0.02), Vector3(4.6, 1.15, -7.89), _mat(Color.WHITE, 0.3, 0.0, accent2, 2.2))
	_poster(Vector3(9.15, 3.4, 6.0), -PI / 2.0, Vector2(2.2, 1.3), accent, Retro.c("accent_3"), "RACE")
	_poster(Vector3(0.6, 3.6, -8.78), 0.0, Vector2(2.0, 1.2), accent2, Color("2f6bff"), "TURBO")
	# Elevador de carros (colunas amarelas) e ralos no piso
	for p in [Vector3(-4.6, 0, 3.6), Vector3(-4.6, 0, -2.8)]:
		_box(Vector3(0.35, 2.6, 0.35), p + Vector3(0, 1.3, 0), _mat(Color("e8c32a"), 0.5, 0.4))
		_box(Vector3(1.2, 0.08, 0.2), p + Vector3(0.6, 0.6, 0), _mat(Color("2b2b30"), 0.5, 0.7))
	for z in [-2.0, 2.5]:
		_box(Vector3(0.9, 0.006, 0.3), Vector3(0, 0.003, z + 5.5), _mat(Color("0c0c10"), 0.6, 0.8))
	# Luzes
	for p in [Vector3(-1.5, 6.4, 0.5), Vector3(1.5, 6.4, 0.5)]:
		_box(Vector3(2.4, 0.06, 0.6), p, _mat(Color.WHITE, 0.5, 0.0, Color("e8f0ff"), 3.0))
	_lamp(Vector3(-5.1, 2.4, -8.4), Color("ffe2b8"), 1.6)
	_spot(Vector3(-2.5, 6.2, 3.5), Vector3(0, 0.3, 0.2), 9.0, 42.0, Color("fff3e6"))
	_spot(Vector3(0, 7.0, 0.3), Vector3(0, 0, 0.2), 6.0, 35.0)
	_omni(Vector3(4.0, 1.6, -3.0), accent, 4.0)
	_omni(Vector3(-4.5, 1.4, 4.0), accent2, 3.5)
	_omni(Vector3(6.0, 2.5, 5.0), Color("8090ff"), 2.0)


# ---------------------------------------------------------------------------
# Cenário 2: ao sol (pátio do paddock)
# ---------------------------------------------------------------------------
func _build_sun() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("3d7fd6")
	sky_mat.sky_horizon_color = Color("bcd7f2")
	sky_mat.ground_horizon_color = Color("bcd7f2")
	sky_mat.ground_bottom_color = Color("5a6b4a")
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color("c9dcef")
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.2
	_env(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.light_color = Color("fff1dc")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	_set.add_child(sun)
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-140.0), 0)
	var team := Retro.c("accent")
	# Grama, asfalto do paddock (com manchas e remendos) e o pátio de concreto em placas
	_box(Vector3(240.0, 0.02, 240.0), Vector3(0, -0.03, 0), _tmat(Color("4f7a34"), 0.95, 0.0, 9.0, 0.3, 1.0, Vector2.ZERO, 0.0, Color.BLACK, 21))
	_box(Vector3(46.0, 0.02, 40.0), Vector3(2, -0.005, -2), _tmat(Color("3b3d42"), 0.85, 0.0, 5.0, 0.28, 1.2, Vector2.ZERO, 0.0, Color.BLACK, 25))
	_box(Vector3(9.0, FLOOR_Y, 11.0), Vector3(0, FLOOR_Y * 0.5, 0.2),
		_tmat(Color("b9b6ae"), 0.8, 0.0, 3.0, 0.2, 0.8, Vector2(2, 2), 0.008, Color(0.3, 0.3, 0.3, 0.7), 27))
	var white := _mat(Color("f2f2f0"), 0.6)
	for x in [-4.3, 4.3]:
		_box(Vector3(0.14, 0.004, 10.6), Vector3(x, FLOOR_Y + 0.002, 0.2), white)
	_box(Vector3(8.74, 0.004, 0.14), Vector3(0, FLOOR_Y + 0.002, -5.1), white)
	# Prédio dos boxes (reboco com sujeira, vidros, portas de garagem numeradas)
	var building := _tmat(Color("e9e7e2"), 0.75, 0.0, 4.0, 0.12, 0.5, Vector2(0, 3), 0.004, Color(0, 0, 0, 0.35), 29)
	var glass := _mat(Color("1d2a38"), 0.08, 0.6)
	_box(Vector3(3.0, 6.0, 34.0), Vector3(12.0, 3.0, -3.0), building)
	_box(Vector3(0.1, 1.4, 32.0), Vector3(10.45, 4.6, -3.0), glass)
	_box(Vector3(0.1, 0.35, 34.0), Vector3(10.45, 3.6, -3.0), _mat(team, 0.5))
	var door := _tmat(Color("2b2d33"), 0.55, 0.4, 1.0, 0.1, 0.6, Vector2(0, 10), 0.01, Color(0, 0, 0, 0.6), 31)
	for k in 6:
		var z := -15.0 + k * 5.2
		_box(Vector3(0.1, 3.0, 4.2), Vector3(10.45, 1.5, z), door)
		var num := Label3D.new()
		num.text = str(k + 1)
		num.font = Retro.display(900)
		num.font_size = 90
		num.pixel_size = 0.006
		num.position = Vector3(10.38, 3.2, z)
		num.rotation.y = -PI / 2.0
		_set.add_child(num)
	_box(Vector3(30.0, 5.0, 3.0), Vector3(-4.0, 2.5, -13.0), building)
	_box(Vector3(28.0, 1.2, 0.1), Vector3(-4.0, 3.6, -11.45), glass)
	_sign("SPEEDORU", 150, Vector3(10.38, 5.5, -4.0), team, -PI / 2.0, false)
	# Arquibancada ao longe
	var seats := [team, Color("e8e8e8"), Retro.c("accent_2")]
	for k in 6:
		_box(Vector3(22.0, 0.5, 1.0), Vector3(-6.0, 0.25 + k * 0.5, -22.0 - k * 1.0), _mat(seats[k % 3], 0.7))
	_box(Vector3(22.0, 0.2, 7.0), Vector3(-6.0, 4.4, -24.5), _mat(Color("d9dce2"), 0.5, 0.5))
	# Tenda da equipe com mesas e guarda-sóis; motorhome
	var canopy := _mat(team, 0.6)
	for p in [Vector3(5.6, 1.4, -1.6), Vector3(5.6, 1.4, 2.2), Vector3(8.4, 1.4, -1.6), Vector3(8.4, 1.4, 2.2)]:
		_cyl(0.05, 2.8, p, _mat(Color("c9ccd2"), 0.3, 0.8))
	_box(Vector3(3.4, 0.12, 4.4), Vector3(7.0, 2.85, 0.3), canopy, Vector3(0, 0, deg_to_rad(-6.0)))
	_tool_cart(Vector3(7.0, 0, -1.0), Color("b3122e"), PI / 2.0)
	_tyre_stack(Vector3(6.4, 0, 1.4), 4, _mat(Color("15161a"), 0.85), _mat(Color("ffd21f"), 0.6))
	_tyre_stack(Vector3(7.2, 0, 1.6), 4, _mat(Color("15161a"), 0.85), _mat(Color("c8102e"), 0.6))
	for p in [Vector3(-7.5, 0, 4.5), Vector3(-9.5, 0, 6.0)]:
		_cyl(0.45, 0.04, p + Vector3(0, 0.75, 0), _mat(Color.WHITE, 0.6))
		_cyl(0.03, 0.75, p + Vector3(0, 0.37, 0), _mat(Color("888"), 0.4, 0.8))
		_cyl(1.3, 0.5, p + Vector3(0, 2.3, 0), _mat(team, 0.6), Vector3.ZERO, 0.02)
		_cyl(0.025, 2.3, p + Vector3(0, 1.15, 0), _mat(Color("ddd"), 0.4, 0.8))
	_box(Vector3(2.6, 2.8, 9.0), Vector3(-11.0, 1.6, -3.0), _tmat(Color("f4f4f6"), 0.4, 0.2, 4.0, 0.08, 0.3, Vector2.ZERO, 0.0, Color.BLACK, 33))
	_box(Vector3(0.05, 0.7, 7.0), Vector3(-9.68, 2.2, -3.0), glass)
	_box(Vector3(0.05, 0.25, 9.0), Vector3(-9.68, 1.2, -3.0), _mat(team, 0.5))
	for z in [-6.0, 0.0]:
		_cyl(0.42, 0.3, Vector3(-9.95, 0.42, z), _mat(Color("151515"), 0.8), Vector3(0, 0, PI / 2.0))
	# Barreira de pneus, cones, bandeiras, cerca e árvores
	var tyre_mat := _mat(Color("15161a"), 0.85)
	for k in 9:
		for h in 3:
			_tyre(Vector3(-6.5 + k * 0.72, 0.1 + h * 0.2, -8.2), tyre_mat)
	var cone := _mat(Color("ff6a13"), 0.6)
	for p in [Vector3(-4.8, 0.25, 5.8), Vector3(-2.4, 0.25, 6.4), Vector3(4.8, 0.25, 6.0), Vector3(-6.0, 0.25, 7.5)]:
		_cyl(0.18, 0.5, p, cone, Vector3.ZERO, 0.03)
	var flag_colors := [team, Retro.c("accent_2"), Color.WHITE, Retro.c("accent_3"), Color("ffd21f"), team]
	for k in 6:
		var x := -10.0 + k * 3.0
		_cyl(0.04, 5.0, Vector3(x, 2.5, -10.5), _mat(Color("d9dce2"), 0.3, 0.8))
		_box(Vector3(1.2, 0.8, 0.02), Vector3(x + 0.62, 4.5, -10.5), _mat(flag_colors[k], 0.7))
	var fence := _mat(Color("8d949c"), 0.4, 0.8)
	var mesh_mat := _mat(Color(0.75, 0.78, 0.82, 0.35), 0.5, 0.6)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for k in 12:
		var x := -16.0 + k * 3.0
		_box(Vector3(0.06, 2.4, 0.06), Vector3(x, 1.2, -16.0), fence)
		_box(Vector3(3.0, 2.2, 0.02), Vector3(x + 1.5, 1.2, -16.0), mesh_mat)
	_crate(Vector3(4.2, 0, -7.6))
	_barrel(Vector3(5.4, 0, -7.8), Color("2f6bff"))
	var leaf := _mat(Color("2f5a2a"), 0.9)
	var leaf2 := _mat(Color("3d6e30"), 0.9)
	var trunk := _mat(Color("5b4030"), 0.9)
	var trees := [Vector3(-14, 0, -22), Vector3(-8, 0, -30), Vector3(18, 0, -20), Vector3(22, 0, 4), Vector3(-20, 0, -10),
		Vector3(20, 0, -30), Vector3(-24, 0, 2), Vector3(26, 0, -12), Vector3(4, 0, -34), Vector3(-18, 0, -34)]
	for k in trees.size():
		var p: Vector3 = trees[k]
		_cyl(0.25, 3.0, p + Vector3(0, 1.5, 0), trunk)
		var sm := SphereMesh.new()
		sm.radius = 2.4
		sm.height = 4.4
		_mesh(sm, p + Vector3(0, 4.4, 0), leaf if k % 2 == 0 else leaf2)
		_mesh(sm, p + Vector3(0.9, 5.6, 0.4), leaf2 if k % 2 == 0 else leaf, Vector3.ZERO, Vector3(0.6, 0.6, 0.6))


# ---------------------------------------------------------------------------
# Cenário 3: no box (garagem de F1 com ferramentas e pneus)
# ---------------------------------------------------------------------------
func _build_box() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9fb3c6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d7dde6")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.ssao_enabled = true
	env.ssao_intensity = 2.0
	env.ssr_enabled = true
	_env(env)
	var team := Retro.c("accent")
	var team2 := Retro.c("accent_2")
	# Piso de epóxi em placas (rejunte), manchas de borracha; faixas e a marca da equipe
	_box(Vector3(20.0, FLOOR_Y, 22.0), Vector3(0, FLOOR_Y * 0.5, -1.0),
		_tmat(Color("c7cbd1"), 0.25, 0.1, 4.8, 0.18, 0.4, Vector2(4, 4), 0.006, Color(0.35, 0.36, 0.4, 0.7), 41))
	var line := _mat(Color("ffd21f"), 0.5)
	for x in [-3.3, 3.3]:
		_box(Vector3(0.12, 0.004, 9.0), Vector3(x, FLOOR_Y + 0.002, 0.2), line)
	_box(Vector3(5.2, 0.004, 1.2), Vector3(0, FLOOR_Y + 0.002, -5.6), _mat(team, 0.5))
	var rubber := _tmat(Color("1b1c20"), 0.9, 0.0, 1.0, 0.15, 1.5, Vector2(0, 16), 0.02, Color(0, 0, 0, 0.6), 43)
	_box(Vector3(1.8, 0.01, 5.0), Vector3(6.8, FLOOR_Y + 0.005, -7.0), rubber)
	_box(Vector3(3.0, 0.01, 1.4), Vector3(-5.0, FLOOR_Y + 0.005, -8.6), rubber)
	# Paredes de painéis brancos com emendas e sujeira; faixa da equipe; porta para o pit lane
	var wall := _tmat(Color("eef0f3"), 0.6, 0.05, 2.4, 0.1, 0.4, Vector2(2, 2), 0.006, Color(0.4, 0.42, 0.45, 0.8), 45)
	var dark := _tmat(Color("2a2c33"), 0.5, 0.25, 3.4, 0.15, 0.5, Vector2(1, 0), 0.01, Color(0, 0, 0, 0.6), 47)
	_box(Vector3(20.0, 6.0, 0.3), Vector3(0, 3.0, -10.0), wall)
	for k in 5:
		_box(Vector3(3.4, 3.6, 0.08), Vector3(-7.2 + k * 3.6, 2.6, -9.82), dark)
		_box(Vector3(3.4, 0.25, 0.09), Vector3(-7.2 + k * 3.6, 4.55, -9.81), _mat(team, 0.4))
	_box(Vector3(0.3, 6.0, 5.0), Vector3(9.0, 3.0, -7.5), wall)
	_box(Vector3(0.3, 6.0, 5.0), Vector3(9.0, 3.0, 6.0), wall)
	_box(Vector3(0.3, 1.2, 9.0), Vector3(9.0, 5.4, -0.75), wall)
	_poster(Vector3(8.83, 3.2, 6.0), -PI / 2.0, Vector2(2.4, 1.4), team2, Color("2f6bff"), "ORBIT")
	_poster(Vector3(8.83, 3.2, -7.5), -PI / 2.0, Vector2(2.4, 1.4), Color("ffd21f"), Color("ff6a13"), "TURBO")
	# Lá fora (pela porta): o pit lane iluminado e o muro dos boxes
	_box(Vector3(14.0, 0.02, 30.0), Vector3(16.0, 0.0, 0.0), _tmat(Color("4a4c52"), 0.8, 0.0, 5.0, 0.25, 1.0, Vector2.ZERO, 0.0, Color.BLACK, 49))
	_box(Vector3(0.6, 1.1, 30.0), Vector3(20.0, 0.55, 0.0), _mat(Color("f0f0f0"), 0.6))
	_box(Vector3(0.1, 8.0, 30.0), Vector3(26.0, 4.0, 0.0), _mat(Color("cfe2f5"), 1.0, 0.0, Color("e6f1ff"), 1.2))
	_omni(Vector3(14.0, 4.0, -0.75), Color("eaf4ff"), 6.0, 14.0)
	_sign("SPEEDORU · BOX 1", 70, Vector3(8.83, 5.4, -0.75), team, -PI / 2.0, false)
	# Teto com luzes fluorescentes e calha de cabos
	_box(Vector3(20.0, 0.2, 22.0), Vector3(0, 6.1, -1.0), wall)
	for z in [-5.0, -1.0, 3.0]:
		for x in [-3.0, 3.0]:
			_box(Vector3(0.5, 0.06, 3.0), Vector3(x, 5.95, z), _mat(Color.WHITE, 0.5, 0.0, Color("f3f7ff"), 4.0))
	_box(Vector3(0.4, 0.12, 20.0), Vector3(-7.5, 5.6, -1.0), _mat(Color("8d949c"), 0.4, 0.8))
	_spot(Vector3(0, 5.8, 0.3), Vector3(0, 0, 0.2), 7.0, 50.0)
	_spot(Vector3(-3.0, 5.6, 4.5), Vector3(0, 0.4, 0.2), 5.0, 40.0, Color("fff6ec"))
	_omni(Vector3(-5.0, 4.0, -4.0), Color("f2f6ff"), 2.5, 12.0)
	# Carrinhos de ferramentas, quadro de ferramentas, estante de peças
	for k in 4:
		_tool_cart(Vector3(-7.0 + k * 1.3, FLOOR_Y, -9.3), team)
	var steel := _mat(Color("c9ccd2"), 0.3, 0.9)
	_box(Vector3(4.0, 1.8, 0.05), Vector3(-5.0, 2.6, -9.8), _tmat(Color("3a3d45"), 0.7, 0.2, 0.6, 0.1, 0.6, Vector2(12, 8), 0.02, Color(0, 0, 0, 0.5), 51))
	for k in 12:
		_box(Vector3(0.06, 0.35 + (k % 3) * 0.12, 0.04), Vector3(-6.6 + k * 0.28, 2.6 + (k % 2) * 0.3, -9.75), steel)
	_shelf(Vector3(-9.5, FLOOR_Y, -5.5), PI / 2.0, 2.4, [team, Color("e8e8e8"), team2])
	# Pneus: rack com mantas térmicas e pilhas soltas
	var blanket_a := _mat(Color("d2232a"), 0.7)
	var blanket_b := _mat(Color("1e4fd8"), 0.7)
	var tyre_mat := _mat(Color("131317"), 0.85)
	for k in 4:
		var p := Vector3(6.8, FLOOR_Y + 0.38, -8.6 + k * 1.0)
		_cyl(0.36, 0.38, p, blanket_a if k % 2 == 0 else blanket_b, Vector3(PI / 2.0, 0, 0))
		_cyl(0.36, 0.38, p + Vector3(0, 0.76, 0), blanket_b if k % 2 == 0 else blanket_a, Vector3(PI / 2.0, 0, 0))
	_box(Vector3(0.9, 0.06, 4.4), Vector3(6.8, FLOOR_Y + 0.02, -7.1), steel)
	_tyre_stack(Vector3(-7.4, FLOOR_Y, 4.6), 4, tyre_mat, _mat(Color("ffd21f"), 0.6))
	_tyre_stack(Vector3(-6.6, FLOOR_Y, 5.2), 4, tyre_mat, _mat(Color("c8102e"), 0.6))
	_tyre_stack(Vector3(-7.8, FLOOR_Y, 5.6), 3, tyre_mat)
	# Pistolas de roda com mangueiras, macacos, asa dianteira reserva num carrinho
	for p in [Vector3(3.6, FLOOR_Y + 0.12, 2.6), Vector3(-3.6, FLOOR_Y + 0.12, 2.6), Vector3(3.6, FLOOR_Y + 0.12, -2.0)]:
		_cyl(0.07, 0.42, p, _mat(Color("2a2a2e"), 0.5, 0.6), Vector3(0, 0, PI / 2.0))
		var hose := TorusMesh.new()
		hose.inner_radius = 0.35
		hose.outer_radius = 0.4
		_mesh(hose, p + Vector3(0.6 * signf(p.x), -0.08, 0.2), _mat(Color("111114"), 0.7))
	_box(Vector3(0.12, 0.12, 2.0), Vector3(0, FLOOR_Y + 0.08, 4.4), _mat(Color("ffd21f"), 0.5, 0.4))
	_box(Vector3(0.12, 0.12, 1.6), Vector3(0, FLOOR_Y + 0.08, -4.6), _mat(Color("ffd21f"), 0.5, 0.4))
	_box(Vector3(2.0, 0.8, 0.8), Vector3(-6.4, FLOOR_Y + 0.4, -2.6), _mat(Color("2a2c33"), 0.5, 0.4))
	_box(Vector3(1.9, 0.06, 0.5), Vector3(-6.4, FLOOR_Y + 0.9, -2.6), _mat(team, 0.4, 0.3))
	for x in [-7.3, -5.5]:
		_box(Vector3(0.05, 0.35, 0.5), Vector3(x, FLOOR_Y + 1.05, -2.6), _mat(team, 0.4, 0.3))
	# Mesa dos engenheiros com monitores e cadeiras; pórtico de telemetria; extintores, relógio
	_box(Vector3(2.4, 0.06, 0.9), Vector3(5.6, FLOOR_Y + 0.75, 4.6), _mat(Color("1d1e22"), 0.5))
	for x in [4.7, 6.5]:
		_box(Vector3(0.06, 0.75, 0.8), Vector3(x, FLOOR_Y + 0.37, 4.6), steel)
	for k in 3:
		_box(Vector3(0.62, 0.38, 0.03), Vector3(4.9 + k * 0.7, FLOOR_Y + 1.05, 4.3), _mat(Color("0d1220"), 0.3, 0.0, team2, 1.4))
	for x in [5.0, 6.1]:
		_cyl(0.24, 0.08, Vector3(x, FLOOR_Y + 0.48, 5.4), _mat(Color("222"), 0.6))
		_box(Vector3(0.45, 0.5, 0.06), Vector3(x, FLOOR_Y + 0.75, 5.62), _mat(Color("222"), 0.6))
	_box(Vector3(0.1, 2.4, 0.1), Vector3(-6.0, FLOOR_Y + 1.2, 1.0), steel)
	_box(Vector3(0.1, 2.4, 0.1), Vector3(-6.0, FLOOR_Y + 1.2, -1.0), steel)
	_box(Vector3(0.2, 0.08, 2.2), Vector3(-6.0, FLOOR_Y + 2.4, 0.0), steel)
	for z in [-0.55, 0.55]:
		_box(Vector3(0.08, 0.6, 0.95), Vector3(-5.9, FLOOR_Y + 1.95, z), _mat(Color("0d1220"), 0.3, 0.0, team2, 1.6), Vector3(0, PI / 2.0 + 0.3, 0))
	_extinguisher(Vector3(8.6, FLOOR_Y, -9.4))
	_extinguisher(Vector3(-9.6, FLOOR_Y, 6.0))
	var clock := Label3D.new()
	clock.text = "14:05"
	clock.font = Retro.display(900)
	clock.font_size = 80
	clock.pixel_size = 0.006
	clock.modulate = Color("ff3b30")
	clock.shaded = false
	clock.position = Vector3(5.5, 5.2, -9.8)
	_set.add_child(clock)


func _spawn_car() -> void:
	car = CAR_SCENE.instantiate() as F1Car
	car.player_controlled = false
	car.hold = true
	for n in ["Audio", "Onboard"]:
		var child := car.get_node_or_null(n)
		if child:
			car.remove_child(child)
			child.free()
	car.position = Vector3(0, 0.45, 0.2)
	add_child(car)
	if car.config:
		car.config = car.config.duplicate(true)
		_profile.apply_to_config(car.config)
	_profile.apply_setup(car)
	_profile.changed.connect(_on_profile_changed)


func _on_profile_changed() -> void:
	if car and car.config:
		_profile.apply_to_config(car.config)


# ---------------------------------------------------------------------------
# Ações do menu
# ---------------------------------------------------------------------------
func start_race() -> void:
	RaceSettings.skip_menu = true
	var loading := get_node_or_null("/root/Loading") as LoadingScreen
	if loading:
		loading.change_scene(RACE_SCENE)
	else:
		get_tree().change_scene_to_file(RACE_SCENE)


func open_settings() -> void:
	var settings := get_node_or_null("/root/Settings") as GameSettings
	if settings:
		settings.open_menu()
