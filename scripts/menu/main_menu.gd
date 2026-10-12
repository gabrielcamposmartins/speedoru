extends Node3D
## Menu principal na garagem: botões grandes à esquerda (Jogar solo, Multiplayer, Garagem,
## Configurações, Sair) e o carro do jogador à direita, visto do nordeste por uma câmera orbital
## (gira devagar sozinha; arrastar com o mouse gira, a roda aproxima).
##
## Cenário: a garagem da equipe (_build_garage). No Estúdio o carro vem para o centro-esquerda (o
## painel fica à direita); na Galeria e na Loja ele vai para a direita.

const CAR_SCENE := preload("res://scenes/car/f1_car.tscn")

## Direção da câmera: nordeste do carro (frente-direita; o carro olha para +Z, a direita é -X).
const BASE_YAW := deg_to_rad(-45.0)
## Altura do piso onde o carro pousa.
const FLOOR_Y := 0.08
## Espaço livre da garagem para a câmera (dentro das paredes, com folga): a órbita e o zoom não
## saem da sala.
const ROOM := AABB(Vector3(-12.4, 0.4, -8.3), Vector3(21.4, 6.6, 20.7))

var car: F1Car
var camera: Camera3D
var ui: MenuUI
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
	build_scene()
	Retro.events.changed.connect(build_scene)
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
		elif mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _over_ui():
			# Rodinha em cima de um painel (que não rolou, ex.: já no fim): não mexe no zoom
			return
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


## O mouse está sobre algum elemento da interface (painel, botão, lista…)? O fundo da tela do menu
## ignora o mouse, então sobre a garagem não há nenhum.
func _over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _update_camera(delta: float) -> void:
	_shift = lerpf(_shift, car_shift, 1.0 - exp(-4.0 * delta)) if delta > 0.0 else car_shift
	var target := _focus_target
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	var distance := _room_distance(target, dir, _distance)
	camera.global_position = target + dir * distance
	camera.look_at(target, Vector3.UP)
	camera.h_offset = -distance * _shift


## Distância até onde a câmera pode ir na direção `dir` sem sair da sala (o deslocamento lateral do
## carro na tela também precisa caber).
func _room_distance(target: Vector3, dir: Vector3, wanted: float) -> float:
	var margin := absf(_shift) * wanted
	var lo := ROOM.position + Vector3(margin, 0, margin)
	var hi := ROOM.end - Vector3(margin, 0, margin)
	var t := wanted
	for k in 3:
		if dir[k] > 1e-4:
			t = minf(t, (hi[k] - target[k]) / dir[k])
		elif dir[k] < -1e-4:
			t = minf(t, (lo[k] - target[k]) / dir[k])
	return maxf(t, 2.5)
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
	"airbox": [Vector3(-0.15, 0.8, -0.8), -PI / 2.0 + 0.3, 24.0, 3.6],
	"halo": [Vector3(0, 0.8, 0.0), -0.7, 30.0, 3.4],
	"mirrors": [Vector3(-0.5, 0.75, 0.45), -0.8, 22.0, 3.0],
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
		"decal":
			var decals := cfg.decals.duplicate(true)
			var cur: Dictionary = decals.get("sidepods", {"color": "ffffff", "scale": 1.0, "rot": 0.0})
			cur["id"] = ShopCatalog.decal_of(id)
			decals["sidepods"] = cur
			cfg.decals = decals
			focus_key = "sidepods"
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


func build_scene() -> void:
	if _set:
		_set.queue_free()
	_set = Node3D.new()
	_set.name = "Set"
	add_child(_set)
	_build_garage()


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


## Garagem sem névoa nenhuma: nem a comum nem a volumétrica (que as Configurações ligam nas
## pistas; o meta "no_fog" deixa este ambiente de fora).
func _env(env: Environment) -> void:
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.set_meta("no_fog", true)
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


# ---------------------------------------------------------------------------
# Objetos de cena
# ---------------------------------------------------------------------------
## Extintor: cilindro vermelho com faixa de rótulo, válvula, alça, manômetro e a mangueira descendo.
## `facing` = direção para onde ele olha (a mangueira fica na frente).
func _extinguisher(pos: Vector3, facing := Vector3.BACK) -> void:
	var red := _mat(Color("c8102e"), 0.3, 0.35)
	var black := _mat(Color("1a1a1a"), 0.5, 0.4)
	var chrome := _mat(Color("c9ccd2"), 0.25, 0.9)
	var side := facing.cross(Vector3.UP).normalized()
	_cyl(0.09, 0.5, pos + Vector3(0, 0.25, 0), red)
	_cyl(0.092, 0.12, pos + Vector3(0, 0.3, 0), _mat(Color("f2f2f2"), 0.5))
	_cyl(0.06, 0.04, pos + Vector3(0, 0.52, 0), red, Vector3.ZERO, 0.04)
	_cyl(0.025, 0.08, pos + Vector3(0, 0.58, 0), chrome)
	_box(Vector3(0.03, 0.02, 0.14), pos + Vector3(0, 0.63, 0) + facing * 0.03, black, Vector3(0, atan2(facing.x, facing.z), 0))
	# Manômetro (mostrador virado para a frente)
	_cyl(0.022, 0.012, pos + Vector3(0, 0.6, 0) + side * 0.05 + facing * 0.02, _mat(Color("f2f2f2"), 0.3),
		Vector3(PI / 2.0, atan2(facing.x, facing.z), 0))
	# Mangueira: desce pela frente até perto da base
	_cyl(0.015, 0.42, pos + Vector3(0, 0.38, 0) + facing * 0.1, black)
	_cyl(0.025, 0.06, pos + Vector3(0, 0.15, 0) + facing * 0.1, black)


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


# ---------------------------------------------------------------------------
# Garagem da equipe
# ---------------------------------------------------------------------------
## Cores da garagem: grafite das paredes e móveis e branco do painel do logo; os destaques (logo,
## faixas, LEDs, plataforma) usam a paleta da interface (Retro.c: accent, accent_2, accent_3) e a
## garagem se refaz quando ela muda.
const GRAPHITE := Color("25262b")
const PANEL := Color("e9e6df")
## Altura da plataforma do carro (o piso da sala fica esta altura abaixo de FLOOR_Y).
const PLATFORM_H := 0.12

var _c1 := Color.MAGENTA
var _c2 := Color.CYAN
var _c3 := Color.PURPLE

## Garagem fechada (o carro no meio, numa plataforma baixa com a luz saindo por baixo):
## * atrás (−Z): painel branco com o logo, quadriculado e faixas na cor da paleta; embaixo, a bancada de
##   ferramentas iluminada (painel de ferramentas, capacetes na prateleira, notebook), o quadro de
##   atributos e o carrinho vermelho; um pilar com faixa de luz; no canto, porta, extintor e o
##   banner "DRIVE / HAVE FUN";
## * à direita (+X): duas portas de enrolar numeradas e, em cima, o mezanino com guarda-corpo de
##   vidro, parede clara, porta de vidro do escritório, quadro, estante de troféus, sofá e plantas;
## * à esquerda (−X) e na frente (+Z), mais longe (é de onde a câmera olha): rack de pneus, estantes
##   e o letreiro da equipe;
## * teto escuro com luminárias hexagonais e pendentes iluminando a parede do logo;
## * piso de porcelanato cinza brilhante (reflexos) com a frase pintada no chão.
## Tudo a partir do chão da sala em y = 0 (o conjunto fica PLATFORM_H abaixo de FLOOR_Y).
func _build_garage() -> void:
	_c1 = Retro.c("accent")
	_c2 = Retro.c("accent_2")
	_c3 = Retro.c("accent_3")
	# O carro pousa no tampo da plataforma (FLOOR_Y); o piso da sala fica PLATFORM_H abaixo
	_set.position = Vector3(0, FLOOR_Y - PLATFORM_H, 0)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0b0f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("7d6e5a")
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.2
	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	env.ssr_enabled = true
	_env(env)
	var steel := _mat(Color("c9ccd2"), 0.3, 0.9)
	var black := _mat(Color("141416"), 0.5, 0.3)
	var dark := _tmat(GRAPHITE, 0.6, 0.35, 2.4, 0.14, 0.4, Vector2(2, 1), 0.006, Color(0, 0, 0, 0.6), 61)
	var led := _mat(Color.WHITE, 0.5, 0.0, _c2, 3.0)
	# Piso de porcelanato em placas de 1,5 m, brilhante
	_box(Vector3(22.5, FLOOR_Y, 22.0), Vector3(-1.75, -FLOOR_Y * 0.5, 2.0),
		_tmat(Color("7f8288"), 0.12, 0.15, 3.0, 0.16, 0.25, Vector2(2, 2), 0.005, Color(0.12, 0.12, 0.14, 0.7), 63))
	_platform()
	_floor_text()
	# Paredes e teto
	_box(Vector3(22.9, 7.6, 0.4), Vector3(-1.75, 3.8, -9.0), dark)
	_box(Vector3(0.4, 7.6, 22.4), Vector3(9.5, 3.8, 2.0), dark)
	_box(Vector3(0.4, 7.6, 22.4), Vector3(-13.0, 3.8, 2.0), dark)
	_box(Vector3(22.9, 7.6, 0.4), Vector3(-1.75, 3.8, 13.0), dark)
	_box(Vector3(22.9, 0.2, 22.4), Vector3(-1.75, 7.7, 2.0), _mat(Color("101013"), 0.8))
	for x in [-10.0, -6.0, -2.0, 2.0, 6.0]:
		_box(Vector3(0.3, 0.4, 22.0), Vector3(x, 7.4, 2.0), black)
	_back_wall(led, steel, black)
	_right_wall(led, steel, black)
	_side_walls(steel, black)
	_foreground(steel)
	_ceiling_lights()


## Plataforma baixa do carro: tampo escuro brilhante um pouco maior que a base, com a luz (cores da
## paleta) saindo por baixo da borda e espalhando no piso.
func _platform() -> void:
	var half := Vector2(2.65, 4.15)
	var c := Vector3(0, 0, 0.2)
	var top := _tmat(Color("24232c"), 0.18, 0.7, 1.0, 0.1, 0.6, Vector2(8, 12), 0.006, Color(0, 0, 0, 0.5), 81)
	# Base recuada (a luz sai dela) e o tampo por cima, com a borda saliente
	_box(Vector3(half.x * 2.0 - 0.3, PLATFORM_H - 0.035, half.y * 2.0 - 0.3), c + Vector3(0, (PLATFORM_H - 0.035) * 0.5, 0),
		_mat(Color("0c0c10"), 0.6, 0.3))
	_box(Vector3(half.x * 2.0, 0.035, half.y * 2.0), c + Vector3(0, PLATFORM_H - 0.0175, 0), top)
	# Filete fino na borda de cima
	var trim := _mat(_c2, 0.4, 0.0, _c2, 0.8)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.025, 0.012, half.y * 2.0), c + Vector3(sx * (half.x - 0.0125), PLATFORM_H + 0.001, 0), trim)
	for sz in [-1.0, 1.0]:
		_box(Vector3(half.x * 2.0, 0.012, 0.025), c + Vector3(0, PLATFORM_H + 0.001, sz * (half.y - 0.0125)), trim)
	# Faixa de LED escondida embaixo da borda, em volta da base
	var led := _mat(Color.WHITE, 0.5, 0.0, _c1, 5.0)
	var inner := half - Vector2(0.14, 0.14)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.03, 0.03, inner.y * 2.0), c + Vector3(sx * inner.x, 0.03, 0), led)
	for sz in [-1.0, 1.0]:
		_box(Vector3(inner.x * 2.0, 0.03, 0.03), c + Vector3(0, 0.03, sz * inner.y), led)
	# Brilho no piso em volta (some com a distância da borda)
	var spread := 0.45
	var size := half * 2.0 + Vector2(spread, spread) * 2.0
	var w := 96
	var h := int(w * size.y / size.x)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var p := Vector2((x + 0.5) / w * size.x - size.x * 0.5, (y + 0.5) / h * size.y - size.y * 0.5)
			var out := Vector2(maxf(absf(p.x) - half.x, 0.0), maxf(absf(p.y) - half.y, 0.0)).length()
			# Mistura das duas cores da paleta ao longo do comprimento
			var mix := clampf(p.y / size.y + 0.5, 0.0, 1.0)
			var col := _c1.lerp(_c2, mix)
			# Cai rápido perto da borda e chega a zero antes do fim do quadro (sem degrau visível)
			var a := exp(-out * 7.8) * (1.0 - smoothstep(spread * 0.55, spread * 0.95, out))
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.albedo_color = Color(1.4, 1.4, 1.4, 0.85)
	var q := QuadMesh.new()
	q.size = size
	_mesh(q, c + Vector3(0, 0.003, 0), m, Vector3(-PI / 2.0, 0, 0))
	# Luz de verdade no piso (aparece nos reflexos e no carro por baixo)
	for p in [Vector3(-half.x, 0.06, 0.2), Vector3(half.x, 0.06, 0.2), Vector3(0, 0.06, 0.2 - half.y), Vector3(0, 0.06, 0.2 + half.y)]:
		_omni(p, _c1.lerp(_c2, clampf((p.z - 0.2) / (half.y * 2.0) + 0.5, 0.0, 1.0)), 0.6, 0.9)


## Frase pintada no chão, na diagonal (lida de onde a câmera fica) e uma faixa amarela.
func _floor_text() -> void:
	# Na diagonal, subindo para a direita na câmera do menu; cada linha nova vem para perto dela
	var yaw := -0.3
	var along := Vector3(cos(yaw), 0, -sin(yaw))
	var down := Vector3(sin(yaw), 0, cos(yaw)) * 0.5
	var base := Vector3(-3.9, 0.004, 2.9)
	var lines := ["DRIVE FAST", "HAVE FUN", "EVERYDAY"]
	for k in lines.size():
		var l := _label(lines[k], 72, base + down * k, Vector3(-PI / 2.0, yaw, 0), Color(0.86, 0.86, 0.9, 0.75))
		l.shaded = true
	_box(Vector3(3.2, 0.01, 0.2), base + down * 2.9 + along * 0.4, _mat(_c1, 0.5), Vector3(0, yaw, 0))


## Parede do fundo: painel branco com o logo, bancada de ferramentas, quadro de atributos, pilar
## com luz e, no canto, porta, extintor e banner.
func _back_wall(led: Material, steel: Material, black: Material) -> void:
	var z := -8.78
	# Painel branco (logo) em cima, faixa grafite embaixo
	_box(Vector3(12.7, 5.0, 0.05), Vector3(-3.15, 5.1, z), _tmat(PANEL, 0.7, 0.0, 3.0, 0.08, 0.2, Vector2(3, 1), 0.003,
		Color(0, 0, 0, 0.25), 65))
	_box(Vector3(12.7, 2.6, 0.05), Vector3(-3.15, 1.3, z), _tmat(Color("1d1e22"), 0.6, 0.3, 2.0, 0.12, 0.4, Vector2(4, 1),
		0.006, Color(0, 0, 0, 0.6), 67))
	# Faixas amarelas na diagonal e quadriculado
	var stripe := _mat(_c1, 0.5)
	_box(Vector3(0.55, 3.4, 0.02), Vector3(-8.7, 4.7, z + 0.04), stripe, Vector3(0, 0, deg_to_rad(-32.0)))
	_box(Vector3(0.55, 3.0, 0.02), Vector3(2.55, 4.4, z + 0.04), stripe, Vector3(0, 0, deg_to_rad(-32.0)))
	_checker(Vector3(-7.4, 3.45, z + 0.03), Vector2(4.2, 1.3))
	# Logo da equipe
	var logo := _label("SPEEDORU", 210, Vector3(-3.4, 3.95, z + 0.05), Vector3.ZERO, _c1)
	logo.outline_size = 44
	logo.outline_modulate = Color("2a1f0c")
	logo.shaded = true
	var sub := _label("RACING TEAM  ·  GARAGE", 56, Vector3(-3.0, 2.95, z + 0.05), Vector3.ZERO, Color("1f1f24"))
	sub.shaded = true
	# Prateleira com capacetes e faixa de luz embaixo dela
	_box(Vector3(5.9, 0.05, 0.35), Vector3(-6.3, 2.2, z + 0.18), black)
	_box(Vector3(5.8, 0.03, 0.03), Vector3(-6.3, 2.16, z + 0.33), led)
	var helmet_colors := [_c1, Color("f2f2f2"), Color("1a1a1e"), Color("ff7a1a"), Color("f2f2f2"), _c1, Color("1a1a1e"),
		Color("c8102e")]
	for k in helmet_colors.size():
		_helmet(Vector3(-8.9 + k * 0.72, 2.4, z + 0.2), helmet_colors[k], 0.0)
	# Painel de ferramentas (furos) com chaves penduradas
	_box(Vector3(5.8, 1.05, 0.03), Vector3(-6.3, 1.55, z + 0.04), _tmat(Color("2a2b30"), 0.7, 0.2, 0.5, 0.08, 0.5,
		Vector2(16, 6), 0.06, Color(0, 0, 0, 0.8), 69))
	for k in 22:
		var x := -9.0 + k * 0.25
		var h := 0.22 + float((k * 7) % 5) * 0.05
		_box(Vector3(0.035, h, 0.02), Vector3(x, 1.95 - h * 0.5, z + 0.08), steel)
		var ring := TorusMesh.new()
		ring.inner_radius = 0.025
		ring.outer_radius = 0.05
		_mesh(ring, Vector3(x, 1.97, z + 0.08), steel, Vector3(PI / 2.0, 0, 0))
	# Bancada: gaveteiros grafite, tampo claro, luz no rodapé
	for k in 9:
		_cabinet(Vector3(-8.65 + k * 1.2, 0, -8.42))
	_box(Vector3(10.9, 0.05, 0.66), Vector3(-3.95, 0.93, -8.43), _tmat(Color("cfc4b0"), 0.45, 0.05, 1.5, 0.1, 0.3,
		Vector2.ZERO, 0.0, Color.BLACK, 71))
	_box(Vector3(10.8, 0.02, 0.02), Vector3(-3.95, 0.03, -8.1), led)
	_box(Vector3(10.8, 0.02, 0.02), Vector3(-3.95, 0.9, -8.1), led)
	# Em cima da bancada: notebook, frascos e uma caixa de ferramentas
	_box(Vector3(0.5, 0.02, 0.35), Vector3(-4.8, 0.97, -8.4), _mat(Color("2b2b30"), 0.4, 0.6))
	_box(Vector3(0.5, 0.32, 0.02), Vector3(-4.8, 1.13, -8.58), _mat(Color("101018"), 0.3, 0.0, Color("ffd36b"), 1.3),
		Vector3(deg_to_rad(-12.0), 0, 0))
	for k in 5:
		_cyl(0.035, 0.18, Vector3(-3.6 + k * 0.12, 1.05, -8.35), _mat([Color("2f6bff"), _c1, Color("e8e8e8")][k % 3], 0.4))
	_box(Vector3(0.6, 0.28, 0.3), Vector3(-7.6, 1.1, -8.4), _mat(Color("c8102e"), 0.4, 0.3))
	# Quadro de atributos (painel escuro com moldura amarela)
	_stats_board(Vector3(-1.6, 1.75, z + 0.05))
	# Carrinho vermelho, rack de pneus e pilhas
	_tool_cart(Vector3(2.15, 0, -8.35), Color("b3122e"))
	var tyre_mat := _mat(Color("121216"), 0.85)
	_box(Vector3(2.0, 0.05, 0.5), Vector3(1.9, 2.1, -8.55), black)
	for k in 4:
		_tyre(Vector3(1.2 + k * 0.48, 2.48, -8.55), tyre_mat, Vector3(0, 0, PI / 2.0))
	_tyre_stack(Vector3(3.0, 0, -7.6), 4, tyre_mat)
	_tyre_stack(Vector3(2.9, 0, -6.9), 3, tyre_mat)
	# Pilar preto com faixa de luz
	_box(Vector3(0.7, 7.6, 0.7), Vector3(3.6, 3.8, -8.5), black)
	_box(Vector3(0.06, 4.6, 0.03), Vector3(3.6, 3.3, -8.13), led)
	# Canto: parede branca com a porta de serviço, extintor, banner e um gaveteiro
	_door_corner(z, steel)
	_banner(Vector3(5.3, 4.9, z + 0.04))
	_box(Vector3(0.05, 4.6, 0.03), Vector3(4.15, 3.3, z + 0.06), led)
	_cabinet(Vector3(8.0, 0, -8.42))
	# Pendentes iluminando a parede do logo
	for x in [-8.0, -5.2, -2.4, 0.4]:
		_cyl(0.18, 0.22, Vector3(x, 7.0, -7.6), black, Vector3.ZERO, 0.08)
		_cyl(0.16, 0.02, Vector3(x, 6.88, -7.6), _mat(Color.WHITE, 0.5, 0.0, Color("fff0d0"), 4.0))
		_spot(Vector3(x, 6.85, -7.6), Vector3(x, 3.4, -8.8), 5.0, 34.0, Color("ffe7c2"), false)
	for x in [-7.5, -4.5, -1.5]:
		_omni(Vector3(x, 1.6, -7.9), Color("ffc46a"), 1.3, 3.5)


## Parede da direita (como a referência): embaixo, parede grafite com as portas de enrolar "01" e
## "02" entre pilares pretos com faixa de luz; em cima, o mezanino com a parede clara, a porta de
## vidro do escritório, o quadro grande, a estante de troféus, sofá, plantas e pendentes.
func _right_wall(led: Material, steel: Material, black: Material) -> void:
	var x := 9.27
	_shutter(-4.6, "01")
	_shutter(1.3, "02")
	# Pilares pretos com faixa de luz e base na cor da paleta
	for z in [-7.25, -1.65, 3.95]:
		_box(Vector3(0.5, 3.6, 0.5), Vector3(9.1, 1.8, z), black)
		_box(Vector3(0.03, 2.6, 0.06), Vector3(8.84, 1.9, z), led)
		_box(Vector3(0.52, 0.3, 0.52), Vector3(9.1, 0.15, z), _mat(_c1, 0.5))
	# Carrinhos de pneus e extintores perto das portas
	_tyre_cart(Vector3(8.2, 0, -1.6))
	_tyre_cart(Vector3(8.4, 0, 4.6))
	_extinguisher(Vector3(8.75, 0, -2.4))
	_extinguisher(Vector3(8.75, 0, 3.55))
	# Mezanino: laje, pontos de luz embaixo, guarda-corpo de vidro com corrimão preto
	var slab := _tmat(Color("2a2b31"), 0.55, 0.4, 2.0, 0.1, 0.4, Vector2(6, 0), 0.006, Color(0, 0, 0, 0.6), 75)
	_box(Vector3(2.9, 0.3, 22.0), Vector3(8.05, 3.75, 2.0), slab)
	_box(Vector3(0.03, 0.03, 22.0), Vector3(6.6, 3.58, 2.0), led)
	for z in [-6.0, -3.0, 0.0, 3.0, 6.0]:
		_cyl(0.1, 0.02, Vector3(7.6, 3.59, z), _mat(Color.WHITE, 0.5, 0.0, Color("fff0d0"), 4.0))
	for z in [-6.0, -1.5, 3.0]:
		_omni(Vector3(7.8, 3.2, z), Color("ffd59a"), 1.6, 5.0)
	var rail_glass := _mat(Color(0.75, 0.82, 0.9, 0.16), 0.05, 0.2)
	rail_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for k in 15:
		_box(Vector3(0.06, 1.05, 0.06), Vector3(6.7, 4.42, -9.0 + k * 1.5), black)
	_box(Vector3(0.1, 0.06, 22.0), Vector3(6.7, 4.95, 2.0), black)
	_box(Vector3(0.02, 0.9, 22.0), Vector3(6.7, 4.38, 2.0), rail_glass)
	_box(Vector3(0.03, 0.03, 22.0), Vector3(6.68, 3.93, 2.0), led)
	# Parede clara do mezanino (até o teto) com rodapé escuro
	_box(Vector3(0.05, 3.7, 22.0), Vector3(9.28, 5.75, 2.0), _mat(PANEL.darkened(0.04), 0.8))
	_box(Vector3(0.06, 0.15, 22.0), Vector3(9.26, 3.97, 2.0), black)
	_office_door(Vector3(x, 3.9, -6.7))
	_framed(Vector3(9.25, 5.55, -3.4), Vector2(2.2, 1.45), _c1, _c3, "SPEEDORU")
	_trophy_shelf(Vector3(9.0, 3.9, 4.6))
	# Sofá preto de frente para o guarda-corpo, mesa e tapete
	var leather := _tmat(Color("17181c"), 0.4, 0.05, 0.8, 0.12, 0.7, Vector2.ZERO, 0.0, Color.BLACK, 77)
	_box(Vector3(0.95, 0.38, 2.8), Vector3(8.7, 4.09, -0.6), leather)
	_box(Vector3(0.28, 0.75, 2.8), Vector3(9.05, 4.28, -0.6), leather)
	for sz in [-1.0, 1.0]:
		_box(Vector3(0.95, 0.55, 0.22), Vector3(8.7, 4.18, -0.6 + sz * 1.5), leather)
	for k in 3:
		_box(Vector3(0.7, 0.12, 0.86), Vector3(8.62, 4.33, -1.5 + k * 0.9), _tmat(Color("202127"), 0.45, 0.05, 0.8, 0.1, 0.6,
			Vector2.ZERO, 0.0, Color.BLACK, 85))
	_box(Vector3(1.2, 0.01, 2.2), Vector3(7.8, 3.905, -0.6), _mat(_c3.darkened(0.55), 0.9))
	_box(Vector3(0.6, 0.05, 1.0), Vector3(7.75, 4.3, -0.6), _mat(Color("8a6a45"), 0.5))
	for sz in [-0.4, 0.4]:
		_box(Vector3(0.04, 0.4, 0.04), Vector3(7.75, 4.1, -0.6 + sz), black)
	_plant(Vector3(7.25, 3.9, -5.3), 1.5)
	_plant(Vector3(7.25, 3.9, 1.6), 1.3)
	_plant(Vector3(7.25, 3.9, 8.0), 1.4)
	# Pendentes do mezanino
	for z in [-4.5, 1.0, 6.0]:
		_cyl(0.008, 0.9, Vector3(8.0, 7.1, z), black)
		_cyl(0.22, 0.25, Vector3(8.0, 6.55, z), black, Vector3.ZERO, 0.05)
		_cyl(0.2, 0.02, Vector3(8.0, 6.42, z), _mat(Color.WHITE, 0.5, 0.0, Color("fff0d0"), 4.0))
		_omni(Vector3(8.0, 6.2, z), Color("ffe2b8"), 1.3, 5.0)


## Portão de enrolar (na parede da direita, centrado em `z`): lâminas de metal em relevo com frestas
## escuras, fileira de janelinhas, trilhos laterais, barra de baixo com borracha e puxadores, caixa
## do enrolador em cima, o número pintado e uma arandela.
func _shutter(z: float, number: String) -> void:
	var x := 9.27
	var width := 4.2
	var top := 3.22
	var pitch := 0.14
	var frame := _mat(Color("0f0f12"), 0.45, 0.4)
	var rail := _mat(Color("7d828b"), 0.3, 0.85)
	# Fundo escuro do vão (aparece nas frestas entre as lâminas)
	_box(Vector3(0.02, top, width), Vector3(x + 0.01, top * 0.5, z), _mat(Color("08080a"), 0.9))
	# Lâminas: cada uma com a face curva (três faixas em ângulo) e um friso no meio; numa malha só
	var mb := MeshBuilder.new()
	var steel := Color("5b6069")
	var count := int((top - 0.16) / pitch)
	var windows_row := int(count * 0.48)
	for i in count:
		var y := 0.16 + i * pitch + pitch * 0.5
		var h := pitch - 0.012
		var face := x - 0.045
		# Corpo da lâmina e as duas abas inclinadas (dá o perfil ondulado do portão de enrolar)
		mb.box(Transform3D(Basis(), Vector3(face, y, z)), Vector3(0.03, h * 0.62, width - 0.04), steel)
		for sy in [-1.0, 1.0]:
			var bevel := Basis(Vector3.BACK, sy * 0.5)
			mb.box(Transform3D(bevel, Vector3(face + 0.01, y + sy * h * 0.38, z)), Vector3(0.022, h * 0.3, width - 0.04),
				steel.darkened(0.18))
		mb.box(Transform3D(Basis(), Vector3(face - 0.018, y, z)), Vector3(0.008, 0.012, width - 0.06), steel.lightened(0.25))
		if i == windows_row:
			# Janelinhas recortadas nesta lâmina
			for w in 4:
				var wz := z - width * 0.375 + w * width * 0.25
				mb.box(Transform3D(Basis(), Vector3(face - 0.02, y, wz)), Vector3(0.012, h * 0.62, 0.62), Color("1b1d22"))
	var slats := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.75
	mat.roughness = 0.38
	slats.mesh = mb.commit()
	slats.material_override = mat
	_set.add_child(slats)
	var glass := _mat(Color("b9d6ee"), 0.15, 0.0, Color("cfe6ff"), 1.1)
	var wy := 0.16 + windows_row * pitch + pitch * 0.5
	for w in 4:
		_box(Vector3(0.01, pitch * 0.5, 0.52), Vector3(x - 0.077, wy, z - width * 0.375 + w * width * 0.25), glass)
	# Trilhos laterais (perfil em U) e batentes
	for sz in [-1.0, 1.0]:
		var rz: float = z + sz * (width * 0.5 + 0.03)
		_box(Vector3(0.14, top + 0.1, 0.08), Vector3(x - 0.05, (top + 0.1) * 0.5, rz), rail)
		_box(Vector3(0.03, top + 0.1, 0.1), Vector3(x - 0.12, (top + 0.1) * 0.5, rz + sz * 0.02), rail)
		_box(Vector3(0.18, top + 0.3, 0.14), Vector3(x - 0.03, (top + 0.3) * 0.5, rz + sz * 0.12), frame)
	# Barra de baixo: perfil de alumínio, borracha no chão, dois puxadores e a fechadura
	_box(Vector3(0.09, 0.12, width), Vector3(x - 0.06, 0.1, z), rail)
	_box(Vector3(0.07, 0.04, width), Vector3(x - 0.05, 0.02, z), _mat(Color("101012"), 0.9))
	for hz in [-1.2, 1.2]:
		_box(Vector3(0.05, 0.03, 0.22), Vector3(x - 0.13, 0.16, z + hz), _mat(Color("c9ccd2"), 0.25, 0.9))
		for ez in [-0.1, 0.1]:
			_box(Vector3(0.05, 0.05, 0.03), Vector3(x - 0.11, 0.14, z + hz + ez), _mat(Color("c9ccd2"), 0.25, 0.9))
	_cyl(0.03, 0.03, Vector3(x - 0.11, 0.1, z), _mat(Color("d8b45a"), 0.3, 0.9), Vector3(0, 0, PI / 2.0))
	# Caixa do enrolador com tampa chanfrada
	_box(Vector3(0.34, 0.36, width + 0.36), Vector3(x - 0.12, top + 0.2, z), frame)
	_box(Vector3(0.06, 0.08, width + 0.36), Vector3(x - 0.3, top + 0.04, z), frame, Vector3(0, 0, 0.6))
	# Número pintado nas lâminas e a arandela
	var n := _label(number, 240, Vector3(x - 0.075, 2.4, z), Vector3(0, -PI / 2.0, 0), Color("c3c4cc"))
	n.shaded = true
	_box(Vector3(0.12, 0.06, 0.6), Vector3(x - 0.3, top + 0.5, z + 1.6), _mat(Color.WHITE, 0.5, 0.0, Color("fff0d0"), 3.0))


## Canto do fundo (térreo): parede branca com manchas discretas, porta de serviço com placa de saída,
## extintor de parede com placa e alarme, cabideiro com o macacão da equipe, leitor de crachá,
## quadro de avisos, relógio, lixeira, tapete e uma luz quente.
func _door_corner(z: float, steel: Material) -> void:
	var face := z + 0.035
	# Parede branca (até o teto) com algumas manchas discretas, encardido leve perto do chão e rodapé
	_box(Vector3(5.35, 7.6, 0.03), Vector3(6.625, 3.8, z + 0.005), _mat(Color("efede8"), 0.8))
	var spots := [[Vector2(4.6, 3.2), 0.9], [Vector2(7.6, 3.4), 1.2], [Vector2(5.9, 0.6), 0.7], [Vector2(8.7, 1.1), 0.8],
		[Vector2(4.4, 0.4), 0.6], [Vector2(7.1, 2.9), 0.5], [Vector2(8.9, 2.6), 0.9], [Vector2(5.7, 3.3), 0.6]]
	for sp in spots:
		var c: Vector2 = sp[0]
		var r: float = sp[1]
		_mesh(_quad(Vector2(r * 1.4, r)), Vector3(c.x, c.y, face - 0.012), _stain_mat())
	_mesh(_quad(Vector2(5.3, 0.7)), Vector3(6.625, 0.42, face - 0.011), _grime_mat())
	_box(Vector3(5.35, 0.12, 0.03), Vector3(6.625, 0.06, face), _mat(Color("2a2b30"), 0.6))
	# Moldura escura atrás do banner (destaca o painel na parede branca)
	_box(Vector3(1.86, 3.06, 0.02), Vector3(5.3, 4.9, face), _mat(Color("16171b"), 0.5))
	# Porta de serviço: batente, folha de aço com visor, chapa de chute, maçaneta, mola e placa
	var door_c := Vector3(6.4, 0, face)
	var casing := _mat(Color("3a3c42"), 0.4, 0.6)
	_box(Vector3(0.1, 2.34, 0.06), door_c + Vector3(-0.6, 1.17, 0.01), casing)
	_box(Vector3(0.1, 2.34, 0.06), door_c + Vector3(0.6, 1.17, 0.01), casing)
	_box(Vector3(1.3, 0.1, 0.06), door_c + Vector3(0, 2.29, 0.01), casing)
	_box(Vector3(1.1, 2.22, 0.05), door_c + Vector3(0, 1.11, 0.0), _tmat(Color("4b4f58"), 0.42, 0.55, 1.2, 0.06, 0.3,
		Vector2.ZERO, 0.0, Color.BLACK, 89))
	_box(Vector3(0.22, 0.7, 0.01), door_c + Vector3(-0.2, 1.4, 0.03), _mat(Color("0f141b"), 0.05, 0.6))
	_box(Vector3(1.0, 0.25, 0.01), door_c + Vector3(0, 0.15, 0.03), _mat(Color("8f949c"), 0.3, 0.85))
	_box(Vector3(0.05, 0.05, 0.08), door_c + Vector3(0.4, 1.05, 0.06), steel)
	_box(Vector3(0.16, 0.035, 0.035), door_c + Vector3(0.33, 1.05, 0.1), steel)
	_box(Vector3(0.36, 0.06, 0.06), door_c + Vector3(0.25, 2.12, 0.06), _mat(Color("6f737c"), 0.4, 0.7))
	_box(Vector3(0.34, 0.1, 0.01), door_c + Vector3(0.12, 1.9, 0.03), _mat(Color("f2f2f2"), 0.5))
	var plate := _small_label("EQUIPE", 13, door_c + Vector3(0.12, 1.9, 0.04), Color("1f1f24"))
	plate.shaded = true
	# Placa de saída acesa em cima da porta
	_box(Vector3(0.62, 0.22, 0.05), door_c + Vector3(0, 2.62, 0.03), _mat(Color("0a7a36"), 0.4, 0.0, Color("12b04e"), 1.1))
	_small_label("SAÍDA", 16, door_c + Vector3(0, 2.62, 0.06), Color(1.6, 1.6, 1.6))
	_omni(door_c + Vector3(0, 2.5, 0.3), Color("4dff8a"), 0.35, 1.6)
	# Leitor de crachá e interruptor ao lado da porta
	_box(Vector3(0.09, 0.13, 0.025), door_c + Vector3(0.78, 1.15, 0.02), _mat(Color("1d1e22"), 0.4, 0.3))
	_box(Vector3(0.04, 0.012, 0.01), door_c + Vector3(0.78, 1.19, 0.035), _mat(Color.WHITE, 0.5, 0.0, _c2, 2.5))
	_box(Vector3(0.08, 0.12, 0.02), door_c + Vector3(0.78, 1.42, 0.015), _mat(Color("f4f4f2"), 0.5))
	# Extintor de parede: suporte, extintor, placa e o acionador do alarme
	var ext := Vector3(5.2, 0.55, face + 0.11)
	_box(Vector3(0.12, 0.08, 0.06), Vector3(5.2, 0.95, face + 0.03), _mat(Color("2a2b30"), 0.4, 0.6))
	_extinguisher(ext, Vector3.BACK)
	_box(Vector3(0.28, 0.36, 0.01), Vector3(5.2, 1.55, face + 0.005), _mat(Color("c8102e"), 0.5))
	_small_label("EXTINTOR", 8, Vector3(5.2, 1.43, face + 0.012), Color.WHITE)
	_cyl(0.06, 0.02, Vector3(5.2, 1.6, face + 0.012), _mat(Color.WHITE, 0.5), Vector3(PI / 2.0, 0, 0))
	_box(Vector3(0.12, 0.12, 0.05), Vector3(5.2, 1.95, face + 0.02), _mat(Color("d01a24"), 0.4))
	_box(Vector3(0.07, 0.07, 0.01), Vector3(5.2, 1.95, face + 0.05), _mat(Color("f2f2f2"), 0.3))
	# Cabideiro com o macacão da equipe e uma toalha
	_box(Vector3(0.5, 0.04, 0.04), Vector3(4.55, 2.02, face + 0.02), _mat(Color("1d1e22"), 0.4, 0.6))
	for hx in [4.42, 4.68]:
		_box(Vector3(0.02, 0.02, 0.08), Vector3(hx, 1.99, face + 0.06), steel)
	_box(Vector3(0.3, 0.75, 0.08), Vector3(4.42, 1.6, face + 0.08), _mat(_c1.darkened(0.15), 0.7))
	_box(Vector3(0.3, 0.06, 0.081), Vector3(4.42, 1.45, face + 0.08), _mat(Color.WHITE, 0.6))
	_box(Vector3(0.08, 0.5, 0.06), Vector3(4.24, 1.7, face + 0.08), _mat(_c1.darkened(0.25), 0.7), Vector3(0, 0, 0.12))
	_box(Vector3(0.18, 0.55, 0.03), Vector3(4.7, 1.72, face + 0.06), _mat(_c2.lightened(0.3), 0.85))
	# Quadro de avisos (cortiça com papéis presos) em cima do gaveteiro e um relógio
	_box(Vector3(1.0, 0.7, 0.03), Vector3(8.0, 1.7, face + 0.01), _tmat(Color("b08a5a"), 0.9, 0.0, 0.4, 0.2, 0.8, Vector2.ZERO,
		0.0, Color.BLACK, 91))
	_box(Vector3(1.06, 0.76, 0.02), Vector3(8.0, 1.7, face), _mat(Color("2a2b30"), 0.5))
	var notes := [[Vector2(-0.3, 0.12), Color("f7f3e8"), 0.08], [Vector2(-0.05, 0.15), Color("fff27a"), -0.06],
		[Vector2(0.25, 0.08), Color("f7f3e8"), 0.04], [Vector2(-0.25, -0.15), _c2.lightened(0.5), -0.1],
		[Vector2(0.08, -0.12), Color("f7f3e8"), 0.12], [Vector2(0.32, -0.16), _c1.lightened(0.5), 0.0]]
	for n in notes:
		var off: Vector2 = n[0]
		_box(Vector3(0.2, 0.26, 0.004), Vector3(8.0 + off.x, 1.7 + off.y, face + 0.03), _mat(n[1], 0.8), Vector3(0, 0, n[2]))
		_cyl(0.012, 0.01, Vector3(8.0 + off.x, 1.81 + off.y, face + 0.035), _mat(_c1, 0.4), Vector3(PI / 2.0, 0, 0))
	_cyl(0.18, 0.04, Vector3(8.0, 2.55, face + 0.02), _mat(Color("f4f4f2"), 0.5), Vector3(PI / 2.0, 0, 0))
	_cyl(0.19, 0.03, Vector3(8.0, 2.55, face + 0.012), _mat(Color("1d1e22"), 0.5), Vector3(PI / 2.0, 0, 0))
	_box(Vector3(0.012, 0.13, 0.005), Vector3(8.0, 2.6, face + 0.045), _mat(Color("1d1e22"), 0.5))
	_box(Vector3(0.1, 0.012, 0.005), Vector3(8.04, 2.55, face + 0.045), _mat(Color("1d1e22"), 0.5), Vector3(0, 0, 0.5))
	# Lixeira, tapete na porta e uma luz quente no canto (fica embaixo do mezanino)
	_cyl(0.17, 0.42, Vector3(7.2, 0.21, -8.55), _mat(Color("2a2b30"), 0.4, 0.6), Vector3.ZERO, 0.19)
	_box(Vector3(1.25, 0.012, 0.7), Vector3(6.4, 0.006, -8.3), _mat(Color("16171b"), 0.95))
	_box(Vector3(1.1, 0.013, 0.05), Vector3(6.4, 0.006, -8.05), _mat(_c1, 0.7))
	_omni(Vector3(6.4, 2.9, -7.9), Color("ffe2b8"), 1.4, 4.5)
	_omni(Vector3(4.8, 2.4, -7.9), Color("ffe2b8"), 0.8, 3.0)


## Texto pequeno de placa (sem contorno).
func _small_label(text: String, size: int, pos: Vector3, color: Color) -> Label3D:
	var l := _label(text, size, pos, Vector3.ZERO, color)
	l.outline_size = 0
	return l


func _quad(size: Vector2) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	return q


var _stain: StandardMaterial3D
var _grime: StandardMaterial3D


## Mancha suave (cinza-amarronzado, bem transparente, borda esfumada).
func _stain_mat() -> StandardMaterial3D:
	if _stain == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0.42, 0.38, 0.32, 0.22), Color(0.42, 0.38, 0.32, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_stain = StandardMaterial3D.new()
		_stain.albedo_texture = t
		_stain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_stain.roughness = 0.9
	return _stain


## Encardido perto do chão (escurece de baixo para cima, bem leve).
func _grime_mat() -> StandardMaterial3D:
	if _grime == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0.3, 0.28, 0.25, 0.22), Color(0.3, 0.28, 0.25, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill_from = Vector2(0.5, 1.0)
		t.fill_to = Vector2(0.5, 0.0)
		_grime = StandardMaterial3D.new()
		_grime.albedo_texture = t
		_grime.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_grime.roughness = 0.9
	return _grime


## Porta de vidro do escritório (no mezanino): batentes pretos, vidro entreaberto e a sala acesa
## lá dentro.
func _office_door(base: Vector3) -> void:
	var frame := _mat(Color("0f0f12"), 0.45, 0.4)
	var w := 1.3
	var h := 2.35
	# Sala iluminada atrás da porta
	_box(Vector3(0.02, h, w), base + Vector3(-0.035, h * 0.5, 0), _mat(Color("2b2722"), 0.8, 0.0, Color("ffcf8a"), 0.35))
	_box(Vector3(0.12, h + 0.12, 0.08), base + Vector3(-0.02, h * 0.5, -w * 0.5 - 0.04), frame)
	_box(Vector3(0.12, h + 0.12, 0.08), base + Vector3(-0.02, h * 0.5, w * 0.5 + 0.04), frame)
	_box(Vector3(0.12, 0.08, w + 0.16), base + Vector3(-0.02, h + 0.04, 0), frame)
	# Folha de vidro aberta uns 30° para dentro do mezanino, presa no batente de trás
	var hinge := Node3D.new()
	hinge.position = base + Vector3(-0.06, 0, -w * 0.5)
	hinge.rotation.y = deg_to_rad(-30.0)
	_set.add_child(hinge)
	var prev := _set
	_set = hinge
	var glass := _mat(Color(0.8, 0.88, 0.95, 0.22), 0.05, 0.2)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box(Vector3(0.03, h - 0.1, w - 0.1), Vector3(0, h * 0.5, w * 0.5), glass)
	_box(Vector3(0.05, h - 0.05, 0.06), Vector3(0, h * 0.5, 0.03), frame)
	_box(Vector3(0.05, h - 0.05, 0.06), Vector3(0, h * 0.5, w - 0.08), frame)
	_box(Vector3(0.05, 0.06, w - 0.05), Vector3(0, h - 0.06, w * 0.5), frame)
	_box(Vector3(0.05, 0.08, w - 0.05), Vector3(0, 0.05, w * 0.5), frame)
	_box(Vector3(0.06, 0.5, 0.03), Vector3(-0.05, 1.05, w - 0.2), _mat(Color("c9ccd2"), 0.3, 0.9))
	_set = prev
	_omni(base + Vector3(-0.6, 1.8, 0), Color("ffd59a"), 0.8, 3.0)


## Estante de metal preto com troféus, caixas, livros, um capacete e LED embaixo de cada prateleira.
func _trophy_shelf(base: Vector3) -> void:
	var black := _mat(Color("121214"), 0.45, 0.5)
	var width := 2.8
	var depth := 0.4
	for zz in [-width * 0.5, width * 0.5]:
		for xx in [-depth * 0.5, depth * 0.5]:
			_box(Vector3(0.04, 2.7, 0.04), base + Vector3(xx, 1.35, zz), black)
	var levels := [0.35, 1.0, 1.65, 2.3]
	for k in levels.size():
		var y: float = levels[k]
		_box(Vector3(depth + 0.04, 0.035, width), base + Vector3(0, y, 0), black)
		_box(Vector3(0.02, 0.02, width - 0.1), base + Vector3(-depth * 0.5 + 0.02, y - 0.03, 0), _mat(Color.WHITE, 0.5, 0.0, _c2, 2.0))
	# Troféus no alto, capacete e caixas no meio, livros e uma planta pequena embaixo
	for k in 5:
		_trophy(base + Vector3(0, 2.32, -1.1 + k * 0.55), 0.3 + (k % 2) * 0.14)
	for k in 3:
		_trophy(base + Vector3(0, 1.67, 0.3 + k * 0.42), 0.26)
	_helmet(base + Vector3(0, 1.84, -0.8), _c1, -PI / 2.0, Color.WHITE)
	var box_cols := [_c3, Color("e8e8e8"), _c2.darkened(0.3), Color("1d1d22")]
	for k in 4:
		_box(Vector3(0.3, 0.26, 0.32), base + Vector3(0, 1.15, -1.15 + k * 0.42), _mat(box_cols[k], 0.6))
	for k in 14:
		var hh := 0.22 + float((k * 5) % 4) * 0.04
		_box(Vector3(0.24, hh, 0.045), base + Vector3(0, 0.37 + hh * 0.5, -1.3 + k * 0.06),
			_mat([_c1.darkened(0.3), Color("e8e8e8"), Color("2b2d33"), _c2.darkened(0.4)][k % 4], 0.6))
	_plant(base + Vector3(0, 0.37, 0.9), 0.45)


## Paredes da esquerda e da frente (vistas ao girar a câmera).
func _side_walls(steel: Material, black: Material) -> void:
	var tyre_mat := _mat(Color("121216"), 0.85)
	# Esquerda: rack de pneus na parede, estantes e o carrinho
	for row in 3:
		_box(Vector3(0.4, 0.05, 6.0), Vector3(-12.6, 0.6 + row * 0.85, 2.0), black)
		for k in 9:
			_tyre(Vector3(-12.5, 0.97 + row * 0.85, -0.6 + k * 0.65), tyre_mat, Vector3(0, 0, PI / 2.0))
	_shelf(Vector3(-12.5, 0, -4.6), PI / 2.0, 2.4, [_c1, Color("e8e8e8"), Color("1a1a1e")])
	_shelf(Vector3(-12.5, 0, 8.0), PI / 2.0, 2.4)
	_box(Vector3(0.05, 1.4, 2.4), Vector3(-12.77, 4.2, 2.0), _mat(Color("101014"), 0.4, 0.0, _c1, 0.35))
	var s := _label("PIT CREW ONLY", 90, Vector3(-12.72, 4.2, 2.0), Vector3(0, PI / 2.0, 0), _c1)
	s.outline_size = 16
	s.outline_modulate = Color(_c1, 0.3)
	# Frente: letreiro da equipe e gaveteiros
	var sign := _label("SPEEDORU", 160, Vector3(-1.5, 5.2, 12.76), Vector3(0, PI, 0), _c1.lightened(0.15))
	sign.outline_size = 28
	sign.outline_modulate = Color(_c1, 0.35)
	_box(Vector3(9.0, 0.06, 0.06), Vector3(-1.5, 4.1, 12.75), _mat(Color.WHITE, 0.5, 0.0, _c1, 3.0))
	for k in 5:
		_cabinet(Vector3(-4.5 + k * 1.2, 0, 12.4), PI)
	_omni(Vector3(-1.5, 4.8, 11.6), _c1, 1.5, 6.0)
	_tyre_stack(Vector3(-12.0, 0, 12.2), 4, tyre_mat, _mat(_c1, 0.6))
	_extinguisher(Vector3(3.2, 0, 12.6))
	_omni(Vector3(-8.0, 5.5, 7.0), Color("fff1e0"), 1.6, 10.0)


## Primeiro plano (perto da câmera, no canto de baixo à esquerda): gaveteiro preto virado para a
## câmera com capacete e chave em cima, pneus ao lado e uma planta na frente.
func _foreground(steel: Material) -> void:
	var holder := Node3D.new()
	# Posições calculadas para a câmera do menu: o gaveteiro entra cortado pela borda esquerda e a
	# planta embaixo, sem cobrir o carro
	holder.position = Vector3(-7.7, 0, -0.1)
	holder.rotation.y = deg_to_rad(25.0)
	_set.add_child(holder)
	var prev := _set
	_set = holder
	_box(Vector3(1.5, 0.95, 0.75), Vector3(0, 0.475, 0), _mat(Color("16171b"), 0.45, 0.45))
	_box(Vector3(1.54, 0.05, 0.79), Vector3(0, 0.975, 0), _mat(Color("2b2d33"), 0.35, 0.6))
	for d in 3:
		var y := 0.22 + d * 0.27
		_box(Vector3(1.36, 0.008, 0.01), Vector3(0, y + 0.12, 0.38), _mat(Color("0b0b0e"), 0.5))
		_box(Vector3(1.2, 0.03, 0.02), Vector3(0, y, 0.39), _mat(_c1, 0.4, 0.2))
	_box(Vector3(1.5, 0.04, 0.02), Vector3(0, 0.04, 0.38), _mat(Color.WHITE, 0.5, 0.0, _c2, 2.0))
	_helmet(Vector3(-0.35, 1.17, 0.05), Color("f2f2f2"), PI * 0.15, _c1)
	_box(Vector3(0.55, 0.04, 0.05), Vector3(0.35, 1.02, 0.12), steel, Vector3(0, -0.35, 0))
	_cyl(0.04, 0.14, Vector3(0.62, 1.02, 0.0), _mat(Color("1a1a1e"), 0.5), Vector3(0, 0, PI / 2.0))
	_set = prev
	var tyre_mat := _mat(Color("121216"), 0.85)
	_tyre_stack(Vector3(-8.9, 0, 1.0), 3, tyre_mat, _mat(_c1, 0.6))
	_plant(Vector3(-7.0, 0, 2.2), 1.2)


## Luminárias hexagonais no teto (anéis de LED) e as luzes principais sobre o carro.
func _ceiling_lights() -> void:
	_hex_light(Vector3(0, 7.25, 0.2), 1.7)
	_hex_light(Vector3(-5.0, 7.25, -3.0), 1.1)
	_hex_light(Vector3(4.5, 7.25, 4.5), 1.1)
	_hex_light(Vector3(-4.5, 7.25, 5.0), 1.1)
	_spot(Vector3(0.5, 7.0, 1.0), Vector3(0, 0.3, 0.2), 7.5, 42.0, Color("fff1dc"))
	_spot(Vector3(-3.5, 6.6, 4.2), Vector3(0, 0.4, 0.2), 4.0, 38.0, Color("fff6ec"), false)
	_omni(Vector3(-5.0, 6.4, -3.0), Color("fff1e0"), 1.6, 8.0)
	_omni(Vector3(4.5, 6.4, 4.5), Color("fff1e0"), 1.4, 8.0)


# ---------------------------------------------------------------------------
# Peças da garagem
# ---------------------------------------------------------------------------
func _label(text: String, size: int, pos: Vector3, rot: Vector3, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Retro.display(900)
	l.font_size = size
	l.pixel_size = 0.006
	l.modulate = color
	l.shaded = false
	l.position = pos
	l.rotation = rot
	_set.add_child(l)
	return l


## Gaveteiro de bancada (1,2 m): corpo grafite, gavetas com puxadores.
func _cabinet(pos: Vector3, rot := 0.0) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = rot
	_set.add_child(holder)
	var prev := _set
	_set = holder
	_box(Vector3(1.16, 0.9, 0.6), Vector3(0, 0.45, 0), _tmat(Color("2b2d33"), 0.45, 0.45, 1.5, 0.08, 0.3, Vector2.ZERO, 0.0,
		Color.BLACK, 79))
	var handle := _mat(Color("c9ccd2"), 0.3, 0.9)
	for d in 4:
		var y := 0.15 + d * 0.2
		_box(Vector3(1.1, 0.008, 0.01), Vector3(0, y + 0.09, 0.305), _mat(Color("15161a"), 0.5))
		_box(Vector3(0.4, 0.025, 0.02), Vector3(0, y, 0.315), handle)
	_set = prev


func _helmet(pos: Vector3, color: Color, yaw: float, stripe := Color.TRANSPARENT) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	_set.add_child(holder)
	var shell := SphereMesh.new()
	shell.radius = 0.16
	shell.height = 0.3
	var mi := MeshInstance3D.new()
	mi.mesh = shell
	mi.material_override = _mat(color, 0.25, 0.1)
	holder.add_child(mi)
	var visor := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.22, 0.08, 0.05)
	visor.mesh = vb
	visor.material_override = _mat(Color("0d0d12"), 0.1, 0.6)
	visor.position = Vector3(0, 0.0, 0.14)
	holder.add_child(visor)
	if stripe.a > 0.0:
		var band := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.15
		tm.outer_radius = 0.165
		band.mesh = tm
		band.material_override = _mat(stripe, 0.4)
		band.rotation = Vector3(0, 0, PI / 2.0)
		holder.add_child(band)


## Planta em vaso: folhas compridas e curvas (cada uma uma fita que abre e cai na ponta).
func _plant(pos: Vector3, height: float) -> void:
	_cyl(0.2 * clampf(height, 0.5, 1.6), 0.38 * clampf(height, 0.5, 1.4), pos + Vector3(0, 0.19 * clampf(height, 0.5, 1.4), 0),
		_mat(Color("1b1c20"), 0.4, 0.3), Vector3.ZERO, 0.25 * clampf(height, 0.5, 1.6))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 97.0 + pos.z * 31.0)
	var leaves := 16
	var segs := 7
	for k in leaves:
		var a := k * TAU / leaves + rng.randf_range(-0.2, 0.2)
		var t0 := rng.randf_range(0.05, 0.55)
		var bend := rng.randf_range(0.6, 1.3)
		var length := height * rng.randf_range(0.7, 1.05)
		var width := height * rng.randf_range(0.09, 0.13)
		var d := Vector3(sin(a), 0, cos(a))
		var s := Vector3(cos(a), 0, -sin(a))
		var col := Color("2f7a2c").lerp(Color("5aa83e"), rng.randf())
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var p := Vector3.ZERO
		for i in segs + 1:
			var u := float(i) / segs
			var th := t0 + u * u * bend
			if i > 0:
				p += (d * sin(th) + Vector3.UP * cos(th)) * (length / segs)
			var w := width * pow(sin(PI * clampf(u * 0.92 + 0.08, 0.0, 1.0)), 0.8)
			var l := p - s * w * 0.5
			var r := p + s * w * 0.5
			if i > 0:
				var n := (p - (prev_l + prev_r) * 0.5).cross(s).normalized()
				for v in [prev_l, prev_r, r, prev_l, r, l]:
					st.set_color(col)
					st.set_normal(n)
					st.add_vertex(v)
			prev_l = l
			prev_r = r
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.55
	_mesh(st.commit(), pos + Vector3(0, 0.36 * clampf(height, 0.5, 1.4), 0), m)


func _trophy(pos: Vector3, height: float) -> void:
	var gold := _mat(Color("d9a62e"), 0.25, 0.9)
	_box(Vector3(0.12, 0.06, 0.12), pos + Vector3(0, 0.03, 0), _mat(Color("1a1a1e"), 0.5))
	_cyl(0.02, height * 0.5, pos + Vector3(0, 0.06 + height * 0.25, 0), gold)
	_cyl(0.09, height * 0.4, pos + Vector3(0, 0.06 + height * 0.7, 0), gold, Vector3.ZERO, 0.05)


## Quadro na parede (moldura preta, imagem em degradê com um título).
func _framed(pos: Vector3, size: Vector2, a: Color, b: Color, text: String) -> void:
	_box(Vector3(0.05, size.y + 0.12, size.x + 0.12), pos, _mat(Color("101014"), 0.4))
	var g := Gradient.new()
	g.colors = PackedColorArray([a, b])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.albedo_texture = gt
	m.roughness = 0.5
	var q := QuadMesh.new()
	q.size = size
	_mesh(q, pos + Vector3(-0.03, 0, 0), m, Vector3(0, -PI / 2.0, 0))
	var font := int(minf(size.y * 70.0, size.x * 150.0 / maxf(text.length(), 1.0)))
	_label(text, font, pos + Vector3(-0.04, 0, 0), Vector3(0, -PI / 2.0, 0), Color.WHITE)


## Banner vertical "DRIVE / HAVE FUN" com quadriculado embaixo.
func _banner(pos: Vector3) -> void:
	_box(Vector3(1.7, 2.9, 0.03), pos, _mat(PANEL, 0.6))
	var d := _label("DRIVE", 110, pos + Vector3(0, 0.95, 0.03), Vector3.ZERO, Color("1f1f24"))
	d.shaded = true
	var h := _label("HAVE FUN", 64, pos + Vector3(0, 0.45, 0.03), Vector3.ZERO, Color("1f1f24"))
	h.shaded = true
	_box(Vector3(1.3, 0.08, 0.02), pos + Vector3(0, 0.15, 0.025), _mat(_c1, 0.5))
	_checker(pos + Vector3(0, -1.05, 0.025), Vector2(1.7, 0.7), false)


## Quadriculado de bandeira (preto sobre o painel); com fade, some para a direita.
func _checker(pos: Vector3, size: Vector2, fade := true) -> void:
	var cols := 16 if fade else 8
	var rows := 6 if fade else 3
	var img := Image.create(cols * 8, rows * 8, false, Image.FORMAT_RGBA8)
	for y in rows * 8:
		for x in cols * 8:
			var on := (x / 8 + y / 8) % 2 == 0
			var a := 1.0 - (float(x) / (cols * 8) if fade else 0.0)
			img.set_pixel(x, y, Color(0.08, 0.08, 0.09, a * a) if on else Color(0, 0, 0, 0))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.7
	var q := QuadMesh.new()
	q.size = size
	_mesh(q, pos, m)


## Quadro de atributos (como na referência): painel escuro com moldura amarela, o nome do carro e
## barras de velocidade, downforce, dirigibilidade e durabilidade.
func _stats_board(pos: Vector3) -> void:
	var glow := _mat(_c1, 0.4, 0.0, _c1, 2.2)
	var w := 3.2
	var h := 1.4
	_box(Vector3(w, h, 0.04), pos, _mat(Color("101014"), 0.5, 0.2))
	_box(Vector3(w, 0.03, 0.02), pos + Vector3(0, h * 0.5, 0.03), glow)
	_box(Vector3(w, 0.03, 0.02), pos + Vector3(0, -h * 0.5, 0.03), glow)
	_box(Vector3(0.03, h, 0.02), pos + Vector3(-w * 0.5, 0, 0.03), glow)
	_box(Vector3(0.03, h, 0.02), pos + Vector3(w * 0.5, 0, 0.03), glow)
	_box(Vector3(0.02, h - 0.2, 0.02), pos + Vector3(-0.1, 0, 0.03), glow)
	var name_l := _label("SF-01", 50, pos + Vector3(-0.85, 0.12, 0.03), Vector3.ZERO, _c1)
	name_l.outline_size = 12
	name_l.outline_modulate = Color(_c1, 0.3)
	_label("SPEEDORU", 24, pos + Vector3(-0.85, -0.25, 0.03), Vector3.ZERO, Color("c9c9cf"))
	var stats := [["SPEED", 0.8], ["DOWNFORCE", 0.65], ["HANDLING", 0.55], ["DURABILITY", 0.7]]
	for k in stats.size():
		var y := 0.45 - k * 0.3
		_label(stats[k][0], 22, pos + Vector3(0.48, y, 0.03), Vector3.ZERO, _c1)
		var full := 0.5
		_box(Vector3(full, 0.07, 0.01), pos + Vector3(1.32, y, 0.025), _mat(Color("2a2b30"), 0.5))
		var v: float = stats[k][1]
		_box(Vector3(full * v, 0.07, 0.015), pos + Vector3(1.32 - full * (1.0 - v) * 0.5, y, 0.03), glow)


## Carrinho de pneus amarelo com dois pneus de pé.
func _tyre_cart(pos: Vector3) -> void:
	var frame := _mat(_c1, 0.5, 0.3)
	var tyre_mat := _mat(Color("121216"), 0.85)
	_box(Vector3(0.8, 0.05, 0.9), pos + Vector3(0, 0.15, 0), frame)
	for z in [-0.42, 0.42]:
		_box(Vector3(0.05, 1.1, 0.05), pos + Vector3(-0.38, 0.65, z), frame)
	for k in 2:
		_tyre(pos + Vector3(0.0, 0.55 + k * 0.62, 0), tyre_mat, Vector3(0, 0, PI / 2.0))
	for x in [-0.32, 0.32]:
		for z in [-0.38, 0.38]:
			_cyl(0.06, 0.05, pos + Vector3(x, 0.06, z), _mat(Color("111"), 0.6), Vector3(PI / 2.0, 0, 0))


## Anel hexagonal de LED no teto.
func _hex_light(center: Vector3, radius: float) -> void:
	var m := _mat(Color.WHITE, 0.5, 0.0, Color("fff3e0"), 4.5)
	var side := radius
	for k in 6:
		var a := k * TAU / 6.0 + PI / 6.0
		var mid := center + Vector3(cos(a), 0, sin(a)) * radius * 0.866
		_box(Vector3(side, 0.06, 0.12), mid, m, Vector3(0, -a - PI / 2.0, 0))


var _pin_serial := 0


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
	# Mudou a engenharia (altura, molas): solta o carro para assentar de novo e prende outra vez
	_profile.setup_changed.connect(func() -> void:
		if is_instance_valid(car) and car.freeze:
			car.freeze = false
			_pin_car())
	_pin_car.call_deferred()


## O carro assenta na plataforma (suspensão) e depois fica preso nela: nivelado e congelado, sem
## escorregar nem ir tombando para a frente com o tempo.
func _pin_car() -> void:
	_pin_serial += 1
	var serial := _pin_serial
	for k in 50:
		await get_tree().physics_frame
	if not is_instance_valid(car) or serial != _pin_serial:
		return
	var xf := car.global_transform
	var fwd := Vector3(xf.basis.z.x, 0.0, xf.basis.z.z).normalized()
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	car.freeze = true
	car.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), xf.origin)


func _on_profile_changed() -> void:
	if car and car.config:
		_profile.apply_to_config(car.config)


# ---------------------------------------------------------------------------
# Ações do menu
# ---------------------------------------------------------------------------
func start_race() -> void:
	RaceSettings.skip_menu = true
	var loading := get_node_or_null("/root/Loading") as LoadingScreen
	var scene := RaceSettings.track_scene(RaceSettings.track)
	if loading:
		loading.change_scene(scene)
	else:
		get_tree().change_scene_to_file(scene)


func open_settings() -> void:
	var settings := get_node_or_null("/root/Settings") as GameSettings
	if settings:
		settings.open_menu()
