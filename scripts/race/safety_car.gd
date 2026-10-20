class_name SafetyCar
extends Node3D
## Safety car: cupê GT no estilo dos safety cars da F1 (capô longo, asa traseira, "SAFETY CAR" nas
## portas, nos vidros e nas placas) com a barra de luzes no teto: as âmbar piscam alternadas
## (esquerda/direita) e a placa de trás fica iluminada. Anda na linha ideal à frente do líder durante a
## bandeira amarela. É só visual (sem colisão): passar por ele é punido pelo RaceControl.
## Posição = `progress` (metros ao longo da pista, mesma conta do RaceEntry).
##
## Modelo: assets/car/safety_car/safety_car.glb (gerado por blender/build_safety_car.py). Os
## materiais do .glb são slots (SC_Paint, SC_Stripe, SC_BarAmberL...) trocados aqui por materiais toon
## da pintura. Como na F1, que alterna dois safety cars, são duas pinturas (prata e verde),
## escolhidas pela pista. Sem janela (servidor) o modelo não é montado.

## Velocidade nas retas; nas curvas segue o perfil de velocidade da linha ideal (CORNER_FACTOR).
const SPEED := 180.0 / 3.6
const SLOW := 9.0
const CORNER_FACTOR := 0.8

const MODEL := preload("res://assets/car/safety_car/safety_car.glb")
const WHEEL_RADIUS := 0.345
const WHEELBASE := 2.63
## Pisca da barra (trocas por segundo entre a esquerda e a direita).
const FLASH_RATE := 6.0
## Pinturas: carroceria, filetes (splitter, saias, asa), blocos da lateral, letreiros e emblemas
## (portas, capô, traseira) e pinças. A prata é a do safety car de 2018: prata com grafismos pretos e
## pinças laranja; a verde, a do outro safety car: verde com filetes limão.
const LIVERIES := [
	{"paint": Color("949aa4"), "accent": Color("1d1e23"), "stripe": Color("17181c"), "lettering": Color("17181c"),
		"caliper": Color("ee5a12")},
	{"paint": Color("0d5e52"), "accent": Color("c8ef1e"), "stripe": Color("093f37"), "lettering": Color("f2f5f0"),
		"caliper": Color("c8ef1e")},
]

var progress := 0.0
var speed := SPEED
var line: RacingLine
## Perfil de velocidade da linha ideal (m/s por trecho), para frear nas curvas. Vazio = só SPEED.
var profile := PackedFloat32Array()
var track: RaceTrack
## Pintura (índice de LIVERIES); -1 = a da pista.
var livery := -1

var _model: Node3D
## Rodas: dianteiras (esterçam) e traseiras.
var _front_wheels: Array[Node3D] = []
var _rear_wheels: Array[Node3D] = []
var _spin := 0.0
var _steer := 0.0
var _amber_l: StandardMaterial3D
var _amber_r: StandardMaterial3D
var _glow_l: OmniLight3D
var _glow_r: OmniLight3D
var _heads: Array[SpotLight3D] = []
var _phase := -1
var _t := 0.0


func setup(p_track: RaceTrack, p_line: RacingLine, start_progress: float) -> void:
	track = p_track
	line = p_line
	progress = start_progress
	if DisplayServer.get_name() != "headless":
		_build()
	_place()


func _build() -> void:
	_model = MODEL.instantiate() as Node3D
	_model.name = "Model"
	add_child(_model)
	var mats := _materials(LIVERIES[_livery_index()])
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		# Na camada dos carros (luz de contorno do Daylight, como os carros)
		mi.layers = CarAssembly.CAR_LAYER
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var key := src.resource_name if src else ""
			if mats.has(key):
				mi.set_surface_override_material(i, mats[key])
	for wheel_name in ["Wheel_FL", "Wheel_FR"]:
		var w := _model.find_child(wheel_name, true, false) as Node3D
		if w:
			_front_wheels.append(w)
	for wheel_name in ["Wheel_RL", "Wheel_RR"]:
		var w := _model.find_child(wheel_name, true, false) as Node3D
		if w:
			_rear_wheels.append(w)
	# Brilho âmbar da barra na pista em volta (um de cada lado, piscando com ele)
	_glow_l = _glow(Vector3(0.45, 1.55, -0.66))
	_glow_r = _glow(Vector3(-0.45, 1.55, -0.66))
	# Faróis (só acendem de verdade à noite / no entardecer: apply_mood)
	for x in [0.62, -0.62]:
		var spot := SpotLight3D.new()
		spot.light_color = Color("fff3dc")
		spot.spot_range = 32.0
		spot.spot_angle = 28.0
		spot.spot_attenuation = 0.8
		spot.position = Vector3(x, 0.6, 2.2)
		spot.rotation = Vector3(deg_to_rad(-7.0), PI, 0.0)
		spot.visible = false
		spot.light_cull_mask = 0xFFFFF & ~CarAssembly.OWN_LAYERS
		add_child(spot)
		_heads.append(spot)
	add_to_group("mood_aware")
	var daylight := get_tree().get_first_node_in_group("daylight") as Daylight if is_inside_tree() else null
	if daylight:
		apply_mood(daylight.time_of_day, daylight.biome)
	_flash(0)


func _livery_index() -> int:
	if livery >= 0:
		return livery % LIVERIES.size()
	return RaceSettings.track_index(RaceSettings.track) % LIVERIES.size()


func _glow(pos: Vector3) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = Color("ff9a1a")
	l.omni_range = 9.0
	l.omni_attenuation = 1.4
	# Ilumina a pista e o que está em volta, não o próprio teto (estourava no bloom)
	l.light_cull_mask = 0xFFFFF & ~CarAssembly.OWN_LAYERS
	l.position = pos
	add_child(l)
	return l


## Materiais toon de cada slot do modelo para a pintura dada.
func _materials(p: Dictionary) -> Dictionary:
	var paint := CarLivery._paint(0, true)
	paint.set_shader_parameter("color_primary", p["paint"])
	CarLivery.apply_paint_finish(paint, 1)
	var rim := CarLivery._rim(Color("1c1d22"))
	CarLivery.apply_rim_finish(rim, 0)
	_amber_l = _light(Color("ff9a14"), 6.0)
	_amber_r = _light(Color("ff9a14"), 6.0)
	var glass := CarLivery._toon(Color("1b2532"), 0.05, 0.5, 0.45)
	glass.clearcoat_enabled = true
	glass.clearcoat = 0.8
	glass.clearcoat_roughness = 0.05
	return {
		"SC_Paint": paint,
		"SC_Accent": CarLivery._toon(p["accent"], 0.35),
		"SC_Stripe": CarLivery._toon(p["stripe"], 0.45, 0.0, 0.2),
		"SC_Lettering": CarLivery._toon(p["lettering"], 0.4, 0.0, 0.2),
		"SC_Caliper": CarLivery._toon(p["caliper"], 0.35),
		"SC_Carbon": CarLivery._toon(Color("24262d"), 0.3, 0.0, 0.25),
		"SC_Arch": CarLivery._toon(Color("101114"), 0.9, 0.0, 0.0),
		"SC_Under": CarLivery._toon(Color("15161a"), 0.9, 0.0, 0.0),
		"SC_Grille": CarLivery._toon(Color("0c0d10"), 0.7, 0.0, 0.1),
		"SC_Chrome": CarLivery._toon(Color("dfe3ea"), 0.1, 0.9, 0.5),
		"SC_Glass": glass,
		"SC_Trim": CarLivery._toon(Color("101115"), 0.25, 0.0, 0.2),
		"SC_Gap": CarLivery._toon(Color("23262c"), 0.8, 0.0, 0.0),
		"SC_Tire": CarLivery._tire(),
		"SC_Rim": rim,
		"SC_Disc": CarLivery._toon(Color("707379"), 0.4, 0.7),
		"SC_HeadHousing": CarLivery._toon(Color("1a1f29"), 0.08, 0.4, 0.4),
		"SC_HeadLED": CarLivery._emissive(Color("f4f8ff"), 3.5),
		"SC_TailHousing": CarLivery._toon(Color("5c0a12"), 0.1, 0.0, 0.4),
		"SC_TailLED": CarLivery._emissive(Color("ff2430"), 3.0),
		"SC_BarBody": CarLivery._toon(Color("18191d"), 0.35, 0.0, 0.25),
		"SC_BarAmberL": _amber_l,
		"SC_BarAmberR": _amber_r,
		"SC_BarGreen": _light(Color("2fd25a"), 0.25),
		"SC_Plate": CarLivery._emissive(Color("f4f1e8"), 0.9),
		"SC_TextDark": CarLivery._toon(Color("141518"), 0.5, 0.0, 0.0),
		"SC_TextLight": CarLivery._toon(Color("f2f4f7"), 0.4, 0.0, 0.2),
		"SC_Banner": CarLivery._toon(Color("0b0c0f"), 0.6, 0.0, 0.1),
	}


## Lente de luz: emissiva, sem sombreamento (a energia muda no pisca).
static func _light(color: Color, energy: float) -> StandardMaterial3D:
	var m := CarLivery._emissive(color, energy)
	m.set_meta("color", color)
	return m


## Fase do pisca: 0 = esquerda acesa, 1 = direita acesa.
func _flash(phase: int) -> void:
	if phase == _phase or _amber_l == null:
		return
	_phase = phase
	_set_lens(_amber_l, phase == 0)
	_set_lens(_amber_r, phase == 1)
	_glow_l.light_energy = 2.2 if phase == 0 else 0.3
	_glow_r.light_energy = 2.2 if phase == 1 else 0.3


static func _set_lens(m: StandardMaterial3D, on: bool) -> void:
	var c: Color = m.get_meta("color")
	m.albedo_color = c if on else c.darkened(0.7)
	m.emission = c
	m.emission_energy_multiplier = 6.0 if on else 0.15


## Período do dia (grupo "mood_aware"): faróis acesos à noite e no entardecer.
func apply_mood(time_of_day: int, _biome: int) -> void:
	var night := DaylightPresets.night_amount(time_of_day)
	for spot in _heads:
		spot.visible = night > 0.05
		spot.light_energy = 4.0 * night


func _process(delta: float) -> void:
	if _model == null:
		return
	_t += delta
	_flash(int(_t * FLASH_RATE) % 2)
	_spin = fmod(_spin + speed * delta / WHEEL_RADIUS, TAU)
	for w in _front_wheels:
		w.rotation = Vector3(_spin, _steer, 0.0)
	for w in _rear_wheels:
		w.rotation = Vector3(_spin, 0.0, 0.0)


## Anda `delta` segundos a até 180 km/h (mais devagar nas curvas); espera o líder se ele ficar
## longe demais.
func advance(delta: float, leader_progress: float) -> void:
	var gap := progress - leader_progress
	var target := SPEED if gap < 110.0 else SLOW
	if not profile.is_empty():
		# Olha um pouco à frente para já chegar na curva devagar
		var ahead := fposmod(progress + 15.0 + speed * 1.2, track.path.length)
		target = minf(target, RacingLine.sample(profile, track.path, ahead) * CORNER_FACTOR)
	speed = move_toward(speed, target, (9.0 if target < speed else 5.0) * delta)
	progress += speed * delta
	_place()


func _place() -> void:
	var s := fposmod(progress, track.path.length)
	var p0 := line.position_at(s)
	var p1 := line.position_at(s + 2.0)
	var fwd := p1 - p0
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	var q := PhysicsRayQueryParameters3D.create(p0 + Vector3.UP * 4.0, p0 + Vector3.DOWN * 4.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q) if is_inside_tree() else {}
	var ground: Vector3 = hit["position"] if hit.has("position") else p0
	global_transform = Transform3D(Basis(Vector3.UP.cross(fwd).normalized(), Vector3.UP, fwd), ground)
	if _model:
		# Esterço das rodas da frente pela curvatura da linha logo adiante
		var p2 := line.position_at(s + 6.0)
		var fwd2 := p2 - p1
		fwd2.y = 0.0
		if fwd2.length_squared() > 1e-6:
			var turn := fwd.signed_angle_to(fwd2.normalized(), Vector3.UP)
			# Curvatura = virada entre os dois trechos (meios a 3 m um do outro); Ackermann: atan(L * k)
			_steer = lerpf(_steer, clampf(atan(WHEELBASE * turn / 3.0), -0.45, 0.45), 0.3)
