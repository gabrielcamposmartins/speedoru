class_name SkyBeams
extends Node3D
## Holofotes da Sky Aerobase: feixes de luz que sobem de baixo da plataforma (searchlight.gdshader)
## e riscam o céu, só ao entardecer e à noite (de dia ficam desligados). A maioria varre o céu
## devagar, cada um no seu ritmo, mais transparentes; os principais, dois por balão de personagem
## (TrackShowcase), sobem de logo abaixo do balão e o acompanham, e à noite ele ganha também luz de
## verdade (SpotLight3D do grupo "night_lights").

const SWEEPERS := 10
const BEAM_LENGTH := 900.0
## Profundidade das lâmpadas abaixo da pista e distância além da borda da plataforma (m).
const DEPTH := 35.0
const OUTSIDE := 14.0
## Inclinação máxima da varredura a partir da vertical (rad).
const SWEEP_TILT := 0.55
const BALLOON_LIGHT := 28.0
## Força dos feixes à noite: os que seguem os balões e os que varrem o céu.
const MAIN_STRENGTH := 0.55
const SWEEP_STRENGTH := 0.22
## Lâmpada dos holofotes dos balões: quanto abaixo do balão, afastamento entre os dois e quanto o
## feixe passa do balão (m); largura do cone em relação aos que varrem o céu.
const BALLOON_BELOW := 170.0
const BALLOON_SPREAD := 9.0
const BALLOON_PAST := 160.0
const BALLOON_WIDTH := 0.45
## Abaixo desta escuridão (Daylight.current_night) os holofotes ficam desligados.
const ON_NIGHT := 0.05

var _sweepers: Array = []  # [nó, fase, velocidade]
var _trackers: Array = []  # [feixe, luz, índice do balão, lado]
var _track: RaceTrack
var _showcase: TrackShowcase
var _t := 0.0


static func build(track: RaceTrack, parent: Node3D) -> SkyBeams:
	var node := SkyBeams.new()
	node.name = "SkyBeams"
	node._track = track
	parent.add_child(node)
	var mat := _material(MAIN_STRENGTH)
	var sweep_mat := _material(SWEEP_STRENGTH)
	var mesh := beam_mesh(BEAM_LENGTH, 1.2, 34.0)
	var p := track.path
	var edges := [SkyDeck.edges(track, 1), SkyDeck.edges(track, -1)]
	for k in SWEEPERS:
		var s := (k + 0.3) * p.length / SWEEPERS
		var i := p.index_at(s)
		var side := 1 if k % 2 == 0 else -1
		var lat := side * (float(edges[RaceTrack._si(side)][i]) + OUTSIDE)
		var beam := node._beam(mesh, sweep_mat, p.frame_at(s, lat, -DEPTH).origin)
		node._sweepers.append([beam, k * 1.7, 0.18 + 0.05 * (k % 3)])
	# Dois por balão, de logo abaixo dele; os balões aparecem depois (vitrine), então a posição é
	# acertada a cada quadro
	for b in 4:
		var beam := node._beam(mesh, mat, Vector3.ZERO)
		var light := SpotLight3D.new()
		light.light_color = Color(0.95, 0.97, 1.0)
		light.light_energy = BALLOON_LIGHT
		light.set_meta("base_energy", BALLOON_LIGHT)
		light.spot_angle = 7.0
		light.spot_attenuation = 0.4
		light.shadow_enabled = false
		light.visible = false
		light.add_to_group("night_lights")
		node.add_child(light)
		node._trackers.append([beam, light, b / 2, 1.0 if b % 2 == 0 else -1.0])
	return node


static func _material(strength: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/track/searchlight.gdshader")
	mat.set_shader_parameter("beam_length", BEAM_LENGTH)
	mat.set_shader_parameter("day_strength", 0.0)
	mat.set_shader_parameter("night_strength", strength)
	return mat


func _beam(mesh: ArrayMesh, mat: Material, origin: Vector3) -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	beam.mesh = mesh
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.custom_aabb = AABB(Vector3(-200, 0, -200), Vector3(400, BEAM_LENGTH, 400))
	add_child(beam)
	beam.global_position = origin
	return beam


## Cone aberto ao longo de +Y, com normais suaves (o shader acha a posição no feixe pela altura local).
static func beam_mesh(length: float, r0: float, r1: float, sides := 32) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var profile := PackedVector2Array()
	for k in 9:
		var t := float(k) / 8.0
		profile.append(Vector2(lerpf(r0, r1, t), length * t))
	mb.lathe(Transform3D(), profile, Color.WHITE, sides)
	return mb.commit()


## Base com o eixo Y apontando para `dir`.
static func _aim(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y)).orthonormalized()


func _process(delta: float) -> void:
	_t += delta
	# De dia tudo desligado (feixes escondidos; a luz dos balões já segue o grupo "night_lights")
	var on := Daylight.current_night > ON_NIGHT
	for sw in _sweepers:
		(sw[0] as Node3D).visible = on
	if not on:
		for tr in _trackers:
			(tr[0] as Node3D).visible = false
		return
	for sw in _sweepers:
		var node: Node3D = sw[0]
		var ph: float = sw[1]
		var w: float = sw[2]
		var dir := Vector3(sin(_t * w + ph) * SWEEP_TILT, 1.0, sin(_t * w * 0.73 + ph * 1.9) * SWEEP_TILT)
		node.global_basis = _aim(dir)
	if _showcase == null and _track:
		_showcase = _track.find_child("Showcase", true, false) as TrackShowcase
	var balloons: Array = _showcase._balloons if _showcase else []
	for tr in _trackers:
		var node: Node3D = tr[0]
		var light: SpotLight3D = tr[1]
		if balloons.is_empty():
			node.visible = false
			continue
		var target: Node3D = balloons[int(tr[2]) % balloons.size()][0]
		if not is_instance_valid(target):
			continue
		node.visible = true
		# A lâmpada fica embaixo do balão (um pouco para cada lado) e o feixe sobe até passar dele
		var top := target.global_position + Vector3.UP * 22.0
		var side: float = tr[3]
		var origin := top + Vector3(side * BALLOON_SPREAD, -BALLOON_BELOW, side * BALLOON_SPREAD * 0.5)
		var aim := top - origin
		var length := aim.length() + BALLOON_PAST
		node.global_transform = Transform3D(_aim(aim) * Basis.from_scale(Vector3(BALLOON_WIDTH, length / BEAM_LENGTH, BALLOON_WIDTH)), origin)
		light.global_transform = Transform3D(Basis.looking_at(aim), origin)
		light.spot_range = aim.length() + 60.0
