class_name FallWatch
extends RefCounted
## Pista no céu (TrackLayout.sky): quem passa da borda da plataforma (onde não há barreira) cai.
## Depois de FALL_TIME segundos no ar fora da plataforma o carro volta pelo box da equipe e faz um
## pit stop completo (pneus novos, conserto se precisar, conta como parada). Na classificação a
## volta é anulada. Roda no servidor ou offline (o RaceManager chama a cada passo de física);
## o cliente recebe o teletransporte pelo snapshot.
##
## O critério é lateral (além da borda da plataforma) ou de altura (abaixo da pista), sempre sem
## roda no chão: apertar "recolocar o carro" (R) no ar não segura o carro em cima do vazio.

signal fell(entry: RaceEntry)

## Segundos de queda até voltar aos boxes.
const FALL_TIME := 2.0
## Metros abaixo da pista que já contam como queda (mesmo sem passar da borda: caiu por um vão).
const DROP := 2.5
## Folga além da borda da plataforma (m).
const EDGE_MARGIN := 0.4

var manager: RaceManager
var _edges: Array = []
## RaceEntry -> segundos no ar fora da plataforma.
var _air := {}


func _init(race_manager: RaceManager) -> void:
	manager = race_manager
	_edges = [SkyDeck.edges(manager.track, 1), SkyDeck.edges(manager.track, -1)]


## O carro está fora da plataforma (além da borda do lado em que está, ou abaixo da pista)?
static func off_deck(track: RaceTrack, edges: Array, pos: Vector3, s: float, lateral: float) -> bool:
	var p := track.path
	var i := p.index_at(s)
	var k := 0 if lateral > 0.0 else 1
	if absf(lateral) > float(edges[k][i]) + EDGE_MARGIN:
		return true
	return pos.y < p.height_at(s) - DROP


static func grounded(car: F1Car) -> bool:
	for w in car.get_wheels():
		if w.is_in_contact():
			return true
	return false


func is_falling(e: RaceEntry) -> bool:
	return _air.has(e)


func physics_update(delta: float) -> void:
	for e in manager.entries:
		var car := e.car
		if car == null or e.retired or e.finished:
			_air.erase(e)
			continue
		if grounded(car) or not off_deck(manager.track, _edges, car.global_position, e.s, e.lateral):
			_air.erase(e)
			continue
		var t: float = _air.get(e, 0.0) + delta
		_air[e] = t
		if t >= FALL_TIME or car.global_position.y < manager.track.layout.sea_level + 200.0:
			_air.erase(e)
			_respawn(e)


## Volta pelo box (ou por uma vaga livre ao lado, se outro carro estiver nele) e faz o pit stop.
## Quem já estava num pit stop (arremessado do box por uma batida) só volta para lá.
func _respawn(e: RaceEntry) -> void:
	if manager.quali:
		manager.quali.invalidate(e, "Caiu da pista")
	manager.teleport_to_box(e, _free_spot(e))
	if not e.in_pit_stop:
		if e.bot:
			e.bot.force_pit_stop(0.0)
		else:
			manager.begin_player_pit(e, 0.0)
	fell.emit(e)


## O box da equipe, ou a vaga livre mais perto dele na faixa dos boxes (o companheiro de equipe
## pode estar parado lá: aparecer em cima dele arremessaria os dois).
func _free_spot(e: RaceEntry) -> Transform3D:
	var track := manager.track
	var s0 := track.garage_s(e.garage)
	for ds: float in [0.0, -9.0, 9.0, -18.0, 18.0, -27.0, 27.0]:
		var s := s0 + ds
		var xf := track.path.frame_at(s, track.pit_lateral(track.path.index_at(s), RaceTrack.PIT_WALL_STRIP + track.layout.pit_lane_width * 0.72), 0.05)
		var free := true
		for other in manager.entries:
			if other != e and other.car and other.car.global_position.distance_to(xf.origin) < 6.0:
				free = false
				break
		if free:
			return xf
	return track.get_pit_box_transform(e.garage)
