class_name Spectator
extends Node
## Modo espectador (F6 ou o botão no menu da pausa): câmeras fixas de TV em cada pista, TV
## automática, câmera livre e perseguição de qualquer carro.
##
## * Câmeras fixas: geradas pela geometria da pista (spots()): uma na largada, alta, olhando para o
##   grid, e uma por fora das curvas mais fechadas (afastadas entre si); em circuito de rua, fora
##   dos prédios, e enxergando a curva. Acompanham o carro seguido com zoom de TV.
## * Teclas: [1]–[9] câmera fixa · [0] TV automática (a câmera mais perto do carro) · [F] câmera
##   livre (WASD/setas, Q/E desce/sobe, Shift rápido, botão direito do mouse olha; no controle,
##   analógicos e LB/RB) · [C] perseguição no carro seguido (de novo: troca a câmera) · [←]/[→]
##   carro seguido · [F6] sai.
## * No solo, um piloto automático (BotDriver) dirige o carro do jogador enquanto ele assiste;
##   no online o modo só abre depois que o jogador terminou ou abandonou (o servidor não pilota por ele).

signal changed

enum View { TV_AUTO, TV_FIXED, FREE, FOLLOW }

const MAX_SPOTS := 9
## Curvas: ângulo mínimo (graus) entre as direções 25 m antes e depois para virar câmera, e o
## espaço mínimo (m) entre câmeras.
const CORNER_MIN_DEG := 35.0
const SPOT_GAP := 280.0
## Tamanho aparente do carro na TV: o FOV é escolhido para ~este tamanho (m) ocupar o quadro.
const TV_FRAME := 22.0
## Até onde uma câmera fixa acompanha um carro (m); sem carro no trecho dela, mostra a curva.
const WATCH_DIST := 240.0
## Quadro da curva vazia (m de largura).
const IDLE_FRAME := 70.0
const FREE_SPEED := 22.0

var hud: RaceModeHud
var active := false
var view: View = View.TV_AUTO
var spot := 0
## Carro seguido (índice em manager.entries).
var follow := 0
## [posição, nome] das câmeras fixas.
var spot_list: Array = []

var _cam: RaceCamera
var _autopilot: BotDriver
var _free_xf := Transform3D()
var _free_yaw := 0.0
var _free_pitch := 0.0
var _switch_t := 0.0
## Ponto para onde a TV olha e o zoom (suavizados ao trocar de carro); helicóptero da TV automática.
var _aim := Vector3.INF
var _aim_fov := 50.0
var _heli := false
var _heli_pos := Vector3.INF


func _ready() -> void:
	# O HUD roda sempre (menus na pausa); o espectador para junto com o jogo
	process_mode = Node.PROCESS_MODE_PAUSABLE


func manager() -> RaceManager:
	return hud.manager


## Pode entrar? (online: só depois de terminar/abandonar)
func can_enter() -> bool:
	var m := manager()
	if m == null or m.track == null or m.state == RaceManager.State.MENU:
		return false
	if m.net == RaceManager.Net.CLIENT and m.player_entry and not (m.player_entry.finished or m.player_entry.retired):
		return false
	return true


func toggle() -> void:
	if active:
		exit()
	else:
		enter()


func enter() -> void:
	if active:
		return
	var m := manager()
	if not can_enter():
		if m and m.player_entry:
			m.notify_entry(m.player_entry, "MODO ESPECTADOR", "No online ele abre depois que você terminar ou abandonar a corrida", false)
		return
	_cam = m.get_parent().get_node_or_null("RaceCamera") as RaceCamera
	if _cam == null:
		return
	if spot_list.is_empty():
		spot_list = spots(m.track)
	active = true
	follow = maxi(m.entries.find(m.player_entry), 0)
	_start_autopilot()
	_set_view(View.TV_AUTO)
	_set_base_hud(false)
	changed.emit()


func exit() -> void:
	if not active:
		return
	active = false
	_stop_autopilot()
	if _cam:
		_cam.cinematic = false
		var m := manager()
		if m.player_entry:
			_cam.target = m.player_entry.car
		_cam.set_mode(RaceCamera.Mode.CHASE)
		_cam.reset_after_cinematic()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_base_hud(true)
	changed.emit()


## O HUD do carro do jogador (velocidade, marcha) some enquanto se assiste.
func _set_base_hud(on: bool) -> void:
	var base := manager().get_parent().get_node_or_null("HUD") as CanvasItem
	if base:
		base.visible = on


# ---------------------------------------------------------------------------
# Piloto automático (solo)
# ---------------------------------------------------------------------------
func _start_autopilot() -> void:
	var m := manager()
	var e := m.player_entry
	if m.net == RaceManager.Net.CLIENT or e == null or e.bot != null or e.finished or e.retired or m.line == null:
		return
	var bot := BotDriver.new()
	bot.name = "Autopilot"
	e.car.player_controlled = false
	e.car.add_child(bot)
	bot.setup(e.car, m.track, m.line, m._profile(BotDriver.Difficulty.HARD), BotDriver.Difficulty.HARD, e, m)
	# Pit obrigatório ainda não feito: para na próxima volta (se ainda houver voltas)
	var laps_left := m.laps - e.laps_completed()
	bot.pit_lap = e.laps_completed() + 1 if RaceSettings.mode == RaceSettings.Mode.RACE and e.pit_count < RaceSettings.mandatory_pits \
		and laps_left > 1 else -1
	bot.released = true
	e.bot = bot
	_autopilot = bot


func _stop_autopilot() -> void:
	if _autopilot == null or not is_instance_valid(_autopilot):
		_autopilot = null
		return
	var e := manager().player_entry
	if e and e.bot == _autopilot:
		e.bot = null
		e.car.player_controlled = true
		e.car.throttle_input = 0.0
		e.car.brake_input = 0.0
		e.car.steer_input = 0.0
	_autopilot.queue_free()
	_autopilot = null


# ---------------------------------------------------------------------------
# Câmeras fixas
# ---------------------------------------------------------------------------
## Câmeras fixas de uma pista: largada + curvas mais fechadas. [posição, nome].
static func spots(track: RaceTrack) -> Array:
	var p := track.path
	var out := []
	# Largada: alta, à frente do grid, olhando para trás (pega o grid inteiro)
	var start := p.frame_at(70.0, 0.0, 16.0).origin
	out.append([start, "Largada", 70.0])
	var corners := []
	var s := 0.0
	while s < p.length:
		var a := p.tangent_at(s - 25.0)
		var b := p.tangent_at(s + 25.0)
		var turn := rad_to_deg(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z)))
		if absf(turn) >= CORNER_MIN_DEG:
			corners.append([absf(turn), s, signf(turn)])
		s += 10.0
	corners.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	var used: Array[float] = [70.0]
	for c in corners:
		if out.size() >= MAX_SPOTS:
			break
		var cs: float = c[1]
		var far := true
		for u in used:
			var d := absf(fposmod(cs - u + p.length * 0.5, p.length) - p.length * 0.5)
			if d < SPOT_GAP:
				far = false
		if not far:
			continue
		var pos := _corner_spot(track, cs, c[2])
		if pos == Vector3.INF:
			continue
		used.append(cs)
		out.append([pos, "Curva %d" % out.size(), cs])
	# Na ordem da volta (a largada continua a primeira)
	var rest := out.slice(1)
	rest.sort_custom(func(x: Array, y: Array) -> bool: return x[2] < y[2])
	for k in rest.size():
		rest[k][1] = "Curva %d" % (k + 1)
	out = [out[0]] + rest
	# Trecho de pista que cada câmera enxerga: [antes, depois] do ponto dela, em metros
	for sp in out:
		sp.append_array(_window(track, sp[0], sp[2]))
	return out


## Quanto da pista, para trás e para a frente do ponto s, a câmera em pos enxerga (sem prédio ou
## arquibancada no caminho e a no máximo WATCH_DIST m).
static func _window(track: RaceTrack, pos: Vector3, s: float) -> Array:
	var p := track.path
	var blocks := _blocks(track, pos, WATCH_DIST + 60.0)
	var out := []
	for dir: float in [-1.0, 1.0]:
		var reach := 0.0
		var d := 8.0
		while d <= WATCH_DIST:
			var q := p.frame_at(fposmod(s + dir * d, p.length), 0.0, 1.0).origin
			if q.distance_to(pos) > WATCH_DIST or _occluded(blocks, pos, q, 0.0):
				break
			reach = d
			d += 8.0
		out.append(reach)
	return out


## Distância (com sinal, pela pista) de s até o ponto da câmera k; negativa = antes dela.
func _offset(k: int, s: float) -> float:
	var length := manager().track.path.length
	return fposmod(s - float(spot_list[k][2]) + length * 0.5, length) - length * 0.5


## A câmera k enxerga o ponto s da pista?
func _covers(k: int, s: float) -> bool:
	var d := _offset(k, s)
	return d >= -float(spot_list[k][3]) and d <= float(spot_list[k][4])


func _car_s(car: F1Car) -> float:
	return manager().track.path.project(car.global_position, false).x


## Lugar da câmera numa curva (grua de TV): logo atrás da barreira, onde não há árvores, e alta,
## olhando o ápice. Tenta o lado de fora e o de dentro, afastamentos e alturas; não aceita dentro de
## arquibancada/boxes nem de prédio, e precisa enxergar o ápice e os trechos antes e depois dele por
## cima dos prédios e das arquibancadas.
static func _corner_spot(track: RaceTrack, s: float, turn_sign: float) -> Vector3:
	var p := track.path
	var i := p.index_at(s)
	var targets: Array[Vector3] = []
	for ds: float in [0.0, -35.0, 35.0]:
		targets.append(p.frame_at(fposmod(s + ds, p.length), 0.0, 1.0).origin)
	var blocks := _blocks(track, targets[0], 220.0)
	for height: float in [16.0, 22.0, 30.0]:
		for side_mul in [-1.0, 1.0]:
			var side := int(turn_sign * side_mul)
			if side == 0:
				side = 1
			for extra: float in [2.0, 6.0, 12.0]:
				var lat := side * (p.half_width(i, side) + track.outer_distance(i, side) + extra)
				var pos := p.frame_at(s, lat, height).origin
				if _occluded(blocks, pos, pos, 4.0):
					continue
				var clear := true
				for t in targets:
					if _occluded(blocks, pos, t, 0.0):
						clear = false
						break
				if clear:
					return pos
	return Vector3.INF


## Obstáculos perto de um ponto: [polígono 2D (x, -z), topo]. Prédios da cidade e arquibancadas/boxes.
static func _blocks(track: RaceTrack, center: Vector3, radius: float) -> Array:
	var out := []
	var c := Vector2(center.x, -center.z)
	if track.city != null:
		for b in track.city.data["buildings"]:
			var pts: Array = b["p"]
			var poly := PackedVector2Array()
			for k in range(0, pts.size(), 2):
				poly.append(Vector2(pts[k], pts[k + 1]))
			if poly[0].distance_to(c) < radius:
				out.append([poly, float(b["t"])])
	for fp in track.footprints:
		if fp.size() < 3:
			continue
		var poly := PackedVector2Array()
		for v in fp:
			poly.append(Vector2(v.x, -v.y))
		if poly[0].distance_to(c) < radius + 100.0:
			out.append([poly, center.y + 14.0])
	return out


## A reta de a até b passa por dentro de algum obstáculo? Com a == b, testa só o ponto a (com folga
## de `margin` m em volta). O ponto b fica na pista e não conta.
static func _occluded(blocks: Array, a: Vector3, b: Vector3, margin: float) -> bool:
	var steps := maxi(int(a.distance_to(b) / 3.0), 1)
	var last := steps - 1 if a != b else 0
	for k in range(0, last + 1):
		var q := a.lerp(b, float(k) / steps)
		var d := Vector2(q.x, -q.z)
		for blk in blocks:
			if float(blk[1]) + 1.0 < q.y:
				continue
			var poly: PackedVector2Array = blk[0]
			if Geometry2D.is_point_in_polygon(d, poly):
				return true
			if margin > 0.0:
				for e in poly.size():
					var cp := Geometry2D.get_closest_point_to_segment(d, poly[e], poly[(e + 1) % poly.size()])
					if cp.distance_to(d) < margin:
						return true
	return false


# ---------------------------------------------------------------------------
# Controle
# ---------------------------------------------------------------------------
func _set_view(v: View) -> void:
	view = v
	_switch_t = 0.0
	if _cam == null:
		return
	var m := manager()
	var car := _followed_car()
	match v:
		View.FOLLOW:
			_cam.cinematic = false
			_cam.target = car
			_cam.set_mode(RaceCamera.Mode.CHASE)
			_cam.reset_after_cinematic()
		View.FREE:
			_cam.cinematic = true
			_free_xf = _cam.global_transform
			var fwd := -_free_xf.basis.z
			_free_yaw = atan2(-fwd.x, -fwd.z)
			_free_pitch = asin(clampf(fwd.y, -1.0, 1.0))
		_:
			_cam.cinematic = true
			_heli = false
			_aim = Vector3.INF
			_heli_pos = Vector3.INF
			_switch_t = 0.0
			if v == View.TV_AUTO and car:
				_pick_auto_spot(car)
	if m.player_entry:
		_cam.cull_mask = 0xFFFFF
	changed.emit()


func _followed_car() -> F1Car:
	var m := manager()
	if m.entries.is_empty():
		return null
	follow = posmod(follow, m.entries.size())
	return (m.entries[follow] as RaceEntry).car


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("spectator"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	var handled := true
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key >= KEY_1 and key <= KEY_9 and key - KEY_1 < spot_list.size():
			spot = key - KEY_1
			_set_view(View.TV_FIXED)
		elif key == KEY_0:
			_set_view(View.TV_AUTO)
		elif key == KEY_F:
			_set_view(View.FREE)
		elif key == KEY_C:
			if view == View.FOLLOW:
				handled = false  # a RaceCamera troca a câmera (C)
			else:
				_set_view(View.FOLLOW)
		elif (key == KEY_LEFT or key == KEY_RIGHT) and view != View.FREE:
			_change_car(1 if key == KEY_RIGHT else -1)
		else:
			handled = false
	elif event is InputEventJoypadButton and event.pressed:
		var jb := event as InputEventJoypadButton
		match jb.button_index:
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
				_change_car(1 if jb.button_index == JOY_BUTTON_DPAD_RIGHT else -1)
			JOY_BUTTON_DPAD_UP:
				# TV → perseguição → livre → TV
				var order := [View.TV_AUTO, View.FOLLOW, View.FREE]
				var cur := order.find(View.TV_AUTO if view == View.TV_FIXED else view)
				_set_view(order[(cur + 1) % order.size()])
			JOY_BUTTON_Y:
				spot = (spot + 1) % maxi(spot_list.size(), 1)
				_set_view(View.TV_FIXED)
			JOY_BUTTON_B:
				exit()
			_:
				handled = false
	elif event is InputEventMouseMotion and view == View.FREE and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mm := event as InputEventMouseMotion
		_free_yaw -= mm.relative.x * 0.004
		_free_pitch = clampf(_free_pitch - mm.relative.y * 0.004, -1.5, 1.5)
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _change_car(step: int) -> void:
	var m := manager()
	var n := m.entries.size()
	for k in n:
		follow = posmod(follow + step, n)
		if not (m.entries[follow] as RaceEntry).retired:
			break
	if view == View.FOLLOW:
		_cam.target = _followed_car()
		_cam.reset_after_cinematic()
	changed.emit()


func _process(delta: float) -> void:
	if not active or _cam == null:
		return
	var car := _followed_car()
	match view:
		View.TV_AUTO, View.TV_FIXED:
			if car == null or spot_list.is_empty():
				return
			if view == View.TV_AUTO:
				_switch_t += delta
				_pick_auto_spot(car)
			if _heli:
				_update_heli(car, delta)
			else:
				_update_tv(car, delta)
		View.FREE:
			_update_free(delta)


## TV automática: a câmera fixa que enxerga o carro, a mais perto dele pela pista (troca no máximo a
## cada 2 s, a não ser que a atual o perca); nenhuma enxerga → helicóptero.
func _pick_auto_spot(car: F1Car) -> void:
	var cs := _car_s(car)
	var best := -1
	var best_d := INF
	for k in spot_list.size():
		if _covers(k, cs) and absf(_offset(k, cs)) < best_d:
			best_d = absf(_offset(k, cs))
			best = k
	var heli := best < 0
	var lost := _heli or not _covers(spot, cs)
	if heli != _heli or (not heli and best != spot and (lost or _switch_t > 2.0)):
		_heli = heli
		if not heli:
			spot = best
		_switch_t = 0.0
		_aim = Vector3.INF
		_heli_pos = Vector3.INF
		changed.emit()


## Câmera fixa: acompanha o carro seguido no trecho dela; fora dele, outro carro que esteja passando;
## sem nenhum, a curva. Zoom de TV: o carro ocupa sempre mais ou menos o mesmo tamanho no quadro.
func _update_tv(car: F1Car, delta: float) -> void:
	var pos: Vector3 = spot_list[spot][0]
	var target: F1Car = car if _covers(spot, _car_s(car)) else null
	if target == null:
		var best_d := INF
		for e in manager().entries:
			var c := (e as RaceEntry).car
			var cs := _car_s(c)
			if c != car and _covers(spot, cs) and absf(_offset(spot, cs)) < best_d:
				best_d = absf(_offset(spot, cs))
				target = c
	var at: Vector3
	var frame := TV_FRAME
	if target:
		at = target.get_global_transform_interpolated().origin + Vector3.UP * 0.6
	else:
		var tr := manager().track
		at = tr.path.frame_at(float(spot_list[spot][2]), 0.0, 1.0).origin
		frame = IDLE_FRAME
	var fov := clampf(rad_to_deg(2.0 * atan(frame * 0.5 / maxf(pos.distance_to(at), 1.0))), 8.0, 70.0)
	if _aim == Vector3.INF:
		_aim = at
		_aim_fov = fov
	else:
		# Segue o carro de perto; ao trocar de alvo, gira a câmera em vez de cortar
		var k := 1.0 - exp(-(14.0 if _aim.distance_to(at) < 12.0 else 4.0) * delta)
		_aim = _aim.lerp(at, k)
		_aim_fov = lerpf(_aim_fov, fov, 1.0 - exp(-4.0 * delta))
	_cam.global_transform = Transform3D(Basis(), pos).looking_at(_aim, Vector3.UP)
	_cam.fov = _aim_fov


## Helicóptero da TV automática: alto, atrás e ao lado do carro, acompanhando suave.
func _update_heli(car: F1Car, delta: float) -> void:
	var xf := car.get_global_transform_interpolated()
	var fwd := -xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var want := xf.origin - fwd * 28.0 + fwd.cross(Vector3.UP) * 14.0 + Vector3.UP * 45.0
	if _heli_pos == Vector3.INF:
		_heli_pos = want
	_heli_pos = _heli_pos.lerp(want, 1.0 - exp(-2.0 * delta))
	var at := xf.origin + fwd * 12.0
	_cam.global_transform = Transform3D(Basis(), _heli_pos).looking_at(at, Vector3.UP)
	_cam.fov = lerpf(_cam.fov, 40.0, 1.0 - exp(-3.0 * delta))


func _update_free(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move.z += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER):
		move.y -= 1.0
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if stick.length() > 0.15:
		move.x += stick.x
		move.z += stick.y
	var look := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if look.length() > 0.15:
		_free_yaw -= look.x * 2.0 * delta
		_free_pitch = clampf(_free_pitch - look.y * 1.5 * delta, -1.5, 1.5)
	var basis := Basis(Vector3.UP, _free_yaw) * Basis(Vector3.RIGHT, _free_pitch)
	var speed := FREE_SPEED * (4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	_free_xf = Transform3D(basis, _free_xf.origin + basis * Vector3(move.x, 0.0, move.z) * speed * delta + Vector3.UP * move.y * speed * delta)
	_cam.global_transform = _free_xf
	_cam.fov = lerpf(_cam.fov, 70.0, 1.0 - exp(-4.0 * delta))


## Texto do HUD: o que está na tela e as teclas.
func status_text() -> Array:
	var m := manager()
	var e: RaceEntry = m.entries[posmod(follow, m.entries.size())] if not m.entries.is_empty() else null
	var who := "%s (P%d)" % [e.code, e.position] if e else ""
	var what := ""
	match view:
		View.TV_AUTO:
			what = "TV automática · %s" % ("Helicóptero" if _heli else str(spot_list[spot][1])) \
				if not spot_list.is_empty() else "TV automática"
		View.TV_FIXED:
			what = "Câmera %d · %s" % [spot + 1, str(spot_list[spot][1])]
		View.FREE:
			what = "Câmera livre"
		View.FOLLOW:
			what = "Perseguição · %s" % _cam.get_mode_name()
	var keys := "[1-%d] câmeras · [0] TV automática · [F] livre · [C] perseguição · [←/→] carro · [F6] sair" % spot_list.size()
	if view == View.FREE:
		keys = "WASD/setas move · Q/E desce/sobe · Shift rápido · botão direito olha · [0] TV · [C] perseguição · [F6] sair"
	return ["ESPECTADOR · %s" % what, ("seguindo %s · " % who if view != View.FREE else "") + keys]
