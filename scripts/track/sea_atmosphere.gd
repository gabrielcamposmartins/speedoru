class_name SeaAtmosphere
extends Node
## Ambiente da pista no fundo do mar: debaixo d'água a névoa é densa e azul, o céu (e o que ele
## reflete) vira água, a luz do sol entra mais fraca e azulada e a névoa rasteira some; acima da linha
## d'água (o trecho emerso, Portão de Poseidon) volta o ambiente normal do período. A cada quadro a
## altura da câmera ativa contra layout.water_level dá a mistura (faixa de ±BAND m), reaplicada só
## quando muda.
##
## O "acima" é o que o Daylight aplicou (capture(), chamado pelo SeaWorld.apply_mood logo depois
## dele); o "embaixo" é o preset do período (SeaWorld.UNDER). Só mexe em propriedades que o
## Daylight._apply_mood define de novo (névoa, luz ambiente, brilho, céu, sol, névoa rasteira), mais
## fog_sky_affect e fog_sun_scatter, devolvidos ao sair (o Environment é um sub-recurso do
## daylight.tscn e pode ser o mesmo objeto na próxima pista).
##
## Também cuida da janela do céu (SeaWorld: a câmera na superfície olhando para cima que o espelho
## d'água usa): ela fica com uma cópia do ambiente de fora d'água (o céu de verdade do período), segue
## a câmera do jogo e só é desenhada com a câmera debaixo d'água. E avisa a saída da água (SeaSplash:
## gotas na tela e o som) quando a câmera passa da água para o ar.

const BAND := 0.8
## Folga (m) em volta da linha d'água para contar a saída (sem piscar com a câmera na linha).
const SURFACE_BAND := 0.4

var track: RaceTrack
## Preset do período debaixo d'água (SeaWorld.UNDER[...]).
var under := {}
## Mistura atual (0 = fora d'água, 1 = debaixo d'água).
var factor := 0.0
## Partículas da água (SeaWorld._specks): recebem a cada quadro o trecho do tubo de vidro perto da
## câmera, para não aparecerem dentro dele.
var specks: Array[ShaderMaterial] = []
## Janela do céu (SeaWorld._surface).
var window: SubViewport
var _window_on := false
## Gotas na tela e som quando a câmera sai da água (SeaWorld).
var splash: SeaSplash
var _under := false
var _under_time := 0.0
var _last_cam := Vector3.INF
var _above := {}
var _last := -1.0
var _forced := true


## Guarda o ambiente "fora d'água" (o que o Daylight acabou de aplicar) e reaplica a mistura.
func capture() -> void:
	var env := _env()
	if env == null:
		return
	# (Chamado logo depois do Daylight aplicar o período, ou depois de gerar a pista, antes de
	# qualquer mistura: o que está no Environment é o de fora d'água. fog_sky_affect e
	# fog_sun_scatter o Daylight não define de novo: ficam os da primeira vez.)
	var sky_affect: float = _above.get("fog_sky_affect", env.fog_sky_affect)
	var scatter: float = _above.get("fog_sun_scatter", env.fog_sun_scatter)
	_above = {
		"fog_density": env.fog_density, "fog_light_color": env.fog_light_color, "fog_sky_affect": sky_affect,
		"fog_sun_scatter": scatter,
		"ambient_light_color": env.ambient_light_color, "ambient_light_energy": env.ambient_light_energy,
		"glow_intensity": env.glow_intensity,
	}
	var sky := _sky()
	if sky:
		for k in ["top_color", "horizon_color", "ground_color", "cloud_coverage", "energy"]:
			_above[k] = sky.get_shader_parameter(k)
	var sun := _sun()
	if sun:
		_above["sun_color"] = sun.light_color
		_above["sun_energy"] = sun.light_energy
	var mist := _mist()
	if mist:
		_above["mist_density"] = mist.density
	_forced = true
	_window_env(env)


## A janela do céu com uma cópia do ambiente de fora d'água: o céu do período sem o tom de câmera
## (a imagem passa de novo pelo da câmera do jogo no espelho), sem brilho nem efeitos de tela.
func _window_env(env: Environment) -> void:
	if window == null or window.get_camera_3d() == null:
		return
	var wenv := env.duplicate(true) as Environment
	wenv.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	wenv.tonemap_exposure = 1.0
	wenv.glow_enabled = false
	wenv.ssao_enabled = false
	wenv.ssil_enabled = false
	wenv.ssr_enabled = false
	wenv.sdfgi_enabled = false
	wenv.volumetric_fog_enabled = false
	wenv.adjustment_enabled = false
	if wenv.sky:
		wenv.sky.radiance_size = Sky.RADIANCE_SIZE_32
	window.get_camera_3d().environment = wenv


func _ready() -> void:
	tree_exiting.connect(restore)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_corridor(cam.global_position)
	var water := track.layout.water_level
	_follow_window(cam.global_position, water)
	_surfacing(cam.global_position, water, delta)
	if _above.is_empty() or under.is_empty():
		return
	var f := 1.0 - smoothstep(water - BAND, water + BAND, cam.global_position.y)
	if not _forced and absf(f - _last) < 0.004:
		return
	_forced = false
	_last = f
	_apply(f)


## A câmera saindo da água: gotas na tela e o som (só depois de um tempo debaixo d'água e com a câmera
## andando: um corte de câmera de dentro para fora d'água não conta).
func _surfacing(pos: Vector3, water: float, delta: float) -> void:
	var moved := _last_cam.distance_to(pos) if _last_cam != Vector3.INF else INF
	_last_cam = pos
	if _under:
		_under_time += delta
		if pos.y > water + SURFACE_BAND:
			_under = false
			if splash and _under_time > 0.6 and moved < 8.0:
				splash.surfaced()
	elif pos.y < water - SURFACE_BAND:
		_under = true
		_under_time = 0.0
		# (debaixo d'água não há gotas na lente)
		if splash:
			splash.cancel()


## A janela do céu na superfície, sobre a câmera do jogo; desenhada só com ela debaixo d'água.
func _follow_window(pos: Vector3, water: float) -> void:
	if window == null:
		return
	var on := pos.y < water + 0.5
	if on != _window_on:
		_window_on = on
		window.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	var wc := window.get_camera_3d()
	if on and wc:
		wc.global_position = Vector3(pos.x, water + 0.3, pos.z)


## Trecho do tubo perto da câmera para as partículas (nenhum longe da pista ou onde ela não é coberta).
func _corridor(pos: Vector3) -> void:
	if specks.is_empty():
		return
	var pr := track.path.project(pos, false, false)
	var c := [] if pr.y == INF else SeaTube.corridor(track, pr.x)
	for mat in specks:
		mat.set_shader_parameter("tube_on", not c.is_empty())
		if not c.is_empty():
			mat.set_shader_parameter("tube_path", c[0])
			mat.set_shader_parameter("tube_tops", c[1])


## Volta o ambiente de fora d'água (ao sair da pista).
func restore() -> void:
	if not _above.is_empty():
		_apply(0.0)


func _apply(f: float) -> void:
	factor = f
	var env := _env()
	if env == null:
		return
	env.fog_density = lerpf(_above.fog_density, under.fog_density, f)
	env.fog_light_color = (_above.fog_light_color as Color).lerp(under.fog_color, f)
	env.fog_sky_affect = lerpf(_above.fog_sky_affect, 1.0, f)
	env.fog_sun_scatter = lerpf(_above.fog_sun_scatter, under.sun_scatter, f)
	env.ambient_light_color = (_above.ambient_light_color as Color).lerp(under.ambient_color, f)
	env.ambient_light_energy = lerpf(_above.ambient_light_energy, under.ambient_energy, f)
	env.glow_intensity = lerpf(_above.glow_intensity, under.glow, f)
	var sky := _sky()
	if sky and _above.has("top_color"):
		sky.set_shader_parameter("top_color", (_above.top_color as Color).lerp(under.sky_top, f))
		sky.set_shader_parameter("horizon_color", (_above.horizon_color as Color).lerp(under.sky_horizon, f))
		sky.set_shader_parameter("ground_color", (_above.ground_color as Color).lerp(under.sky_ground, f))
		sky.set_shader_parameter("cloud_coverage", lerpf(_above.cloud_coverage, 0.0, f))
	var sun := _sun()
	if sun and _above.has("sun_color"):
		sun.light_color = (_above.sun_color as Color).lerp(under.sun_color, f)
		sun.light_energy = lerpf(_above.sun_energy, _above.sun_energy * under.sun_energy, f)
	var mist := _mist()
	if mist and _above.has("mist_density"):
		mist.density = lerpf(_above.mist_density, 0.0, f)


func _daylight() -> Node3D:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("daylight") as Node3D


func _env() -> Environment:
	var daylight := _daylight()
	var we := daylight.get_node_or_null("WorldEnvironment") as WorldEnvironment if daylight else null
	return we.environment if we else null


func _sky() -> ShaderMaterial:
	var env := _env()
	return env.sky.sky_material as ShaderMaterial if env and env.sky else null


func _sun() -> DirectionalLight3D:
	var daylight := _daylight()
	return daylight.get_node_or_null("Sun") as DirectionalLight3D if daylight else null


func _mist() -> FogMaterial:
	var daylight := _daylight()
	var node := daylight.get_node_or_null("GroundMist") as FogVolume if daylight else null
	return node.material as FogMaterial if node else null
