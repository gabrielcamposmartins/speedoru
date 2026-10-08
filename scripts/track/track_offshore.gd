class_name TrackOffshore
extends Node3D
## Movimento ao largo de um circuito de rua (dados da TrackCity): navios grandes cruzando o mar
## (cruzeiro, porta-contêineres, petroleiro e balsa, com rastro de espuma) em rotas paralelas à
## costa; balões de ar quente passando com o vento sobre o porto e a orla, perto do circuito e
## baixos o bastante para ver da pista; e dirigíveis com anúncios: a maioria em órbitas curtas à
## frente dos trechos em que o piloto olha naquela direção (reta, Beau Rivage, saída do túnel,
## Piscine, Rascasse), um pouco acima dos prédios em volta; e dois altos ao longo da costa.
##
## A costa fora da área dos dados é a reta entre as duas saídas (coast_exits), como no entorno
## (TrackCity.build_backdrop): as rotas ficam do lado do mar dela e, dentro da área, longe da
## costa de verdade (conferido na textura da costa).

enum Ship { CRUISE, CONTAINER, TANKER, FERRY }

## [tipo, comprimento (m), distância da costa (m), velocidade (m/s)]
const SHIPS := [
	[Ship.CRUISE, 240.0, 1500.0, 8.0], [Ship.CONTAINER, 220.0, 2600.0, 9.5], [Ship.TANKER, 200.0, 3600.0, 7.0],
	[Ship.FERRY, 120.0, 900.0, 11.0], [Ship.CRUISE, 200.0, 4300.0, 7.5], [Ship.CONTAINER, 180.0, 2000.0, 8.5],
]
## Meia-extensão das rotas ao longo da costa (m): depois disso o navio volta para o outro lado.
const ROUTE_HALF := 7000.0
## Paletas dos balões (duas cores por balão).
const BALLOON_COLORS := [
	[Color(0.95, 0.25, 0.3), Color(1.0, 0.85, 0.2)], [Color(0.2, 0.55, 0.95), Color(1, 1, 1)],
	[Color(0.55, 0.3, 0.85), Color(0.3, 0.9, 0.7)], [Color(1.0, 0.55, 0.15), Color(0.95, 0.2, 0.5)],
	[Color(0.12, 0.7, 0.45), Color(1.0, 0.95, 0.85)], [Color(0.95, 0.4, 0.7), Color(0.35, 0.3, 0.75)],
	[Color(0.98, 0.78, 0.15), Color(0.15, 0.35, 0.8)], [Color(0.85, 0.15, 0.2), Color(0.1, 0.12, 0.15)],
	[Color(0.3, 0.85, 0.95), Color(0.95, 0.5, 0.2)], [Color(1, 1, 1), Color(0.9, 0.2, 0.25)],
]
## Faixa que os balões percorrem ao longo da costa (a partir do centro do circuito) antes de
## recomeçar do outro lado (m).
const BALLOON_HALF := 1500.0
## Balões extras (as paletas se repetem com outra escala/altura).
const BALLOON_COUNT := 14
## Dirigíveis altos ao longo da costa: [cor da faixa, anúncio, altura (m), meio-eixo ao longo da
## costa, meio-eixo para o mar (m), afastamento do centro para o mar (m), velocidade (m/s)].
const BLIMPS := [
	[Color(0.6, 0.35, 0.9), 10, 320.0, 2100.0, 650.0, 900.0, -14.0],
	[Color(0.2, 0.6, 0.95), 7, 280.0, 1700.0, 520.0, 650.0, -11.0],
]
## Dirigíveis nos pontos de vista: pairam sobre a própria pista um pouco à frente de onde o piloto
## está — na faixa de céu que se vê por cima da rua, entre os prédios —, acima dos prédios vizinhos:
## [s da pista onde o piloto está (m), quanto à frente (m), cor da faixa, anúncio].
const VIEW_BLIMPS := [
	[-260.0, 230.0, Color(0.95, 0.25, 0.3), 3],      # reta → Sainte Dévote
	[330.0, 220.0, Color(1.0, 0.82, 0.2), 1],        # subida do Beau Rivage
	[760.0, 200.0, Color(0.95, 0.4, 0.75), 12],      # Massenet → Praça do Casino
	[1990.0, 220.0, Color(0.15, 0.8, 0.6), 5],       # saída do túnel → chicane
	[2280.0, 220.0, Color(1.0, 0.5, 0.2), 9],        # Tabac / Piscine
	[2850.0, 200.0, Color(0.3, 0.55, 0.95), 7],      # Rascasse → reta
]
## Altura mínima sobre a pista (m) e acima dos prédios a até BLIMP_SIDE m dela.
const BLIMP_OVER_ROAD := 55.0
const BLIMP_SIDE := 35.0
## Ângulo máximo de elevação (tangente) visto da pista: mais alto que isso some do quadro.
const BLIMP_MAX_SLOPE := 0.42

const WHITE := Color(0.94, 0.94, 0.92)
const GLASS := Color(0.12, 0.16, 0.22)

var _ships: Array = []     # [nó, rastro, base (x, y), direção (x, y), t, velocidade, fase]
var _balloons: Array = []  # [nó, base (x, y), direção do vento, t, velocidade, altura, fase]
var _blimps: Array = []    # [nó, centro (x, y), eixo ao longo, eixo para o mar, raios, velocidade, ângulo, altura]
var _t := 0.0


static func build(track: RaceTrack, city: TrackCity, parent: Node3D) -> void:
	var node := TrackOffshore.new()
	node.name = "Offshore"
	parent.add_child(node)
	# Centro do circuito (média dos pontos da pista), em coordenadas dos dados (x leste, y norte)
	var sum := Vector3.ZERO
	var n := 0
	var s := 0.0
	while s < track.path.length:
		sum += track.path.position_at(s)
		n += 1
		s += 25.0
	var c := sum / maxi(n, 1)
	node._setup(city, Vector2(c.x, -c.z))
	node._view_blimps(track, city)


## Dirigíveis de VIEW_BLIMPS: sobre a pista à frente do ponto de vista, acima dos prédios vizinhos;
## se ficariam altos demais no quadro, vão mais para a frente. Deslizam um pouco para a frente e
## para trás ao longo da pista (continuam na faixa de céu sobre a rua).
func _view_blimps(track: RaceTrack, city: TrackCity) -> void:
	var p := track.path
	var blocks := _building_blocks(city)
	for k in VIEW_BLIMPS.size():
		var spec: Array = VIEW_BLIMPS[k]
		var s0 := fposmod(float(spec[0]), p.length)
		var eye := p.frame_at(s0, 0.0, 3.0).origin
		var ahead: float = spec[1]
		var at := Vector3.ZERO
		var h := 0.0
		for tries in 8:
			at = p.frame_at(s0 + ahead, 0.0, 0.0).origin
			h = maxf(at.y + BLIMP_OVER_ROAD, _top_near(blocks, Vector2(at.x, -at.z), BLIMP_SIDE) + 25.0)
			if (h - eye.y) / maxf(eye.distance_to(Vector3(at.x, eye.y, at.z)), 1.0) <= BLIMP_MAX_SLOPE:
				break
			ahead += 60.0
		var t := p.tangent_at(s0 + ahead)
		var fwd := Vector2(t.x, -t.z).normalized()
		var node := MeshInstance3D.new()
		node.name = "ViewBlimp%d" % k
		node.mesh = TrackScenery.blimp_mesh(spec[2], spec[3])
		# Baixos sobre a pista: a sombra (70 m) escureceria prédios inteiros e pareceria defeito
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		# Elipse achatada ao longo da pista (vai e volta ~40 m, quase sem sair do corredor)
		_blimps.append([node, Vector2(at.x, -at.z), fwd, Vector2(-fwd.y, fwd.x), Vector2(40.0, 6.0), 3.0 if k % 2 == 0 else -3.0,
			float(k) * 1.3, h])
	_update(0.0)


## Topo mais alto (m) dos prédios (da lista `blocks`) com o centro a até `radius` m do ponto.
static func _top_near(blocks: Array, c: Vector2, radius: float) -> float:
	var best := 0.0
	for blk in blocks:
		if (blk[3] as Vector2).distance_to(c) < radius:
			best = maxf(best, float(blk[2]))
	return best


## Prédios para o teste de visada: [polígono, retângulo envolvente, topo, centro].
static func _building_blocks(city: TrackCity) -> Array:
	var out := []
	for b in city.data["buildings"]:
		var pts: Array = b["p"]
		var poly := PackedVector2Array()
		for i in range(0, pts.size(), 2):
			poly.append(Vector2(pts[i], pts[i + 1]))
		var rect := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			rect = rect.expand(v)
		out.append([poly, rect, float(b["t"]), rect.get_center()])
	return out


func _setup(city: TrackCity, track_center: Vector2) -> void:
	var exits: Array = city.data.get("coast_exits", [])
	if exits.size() < 2:
		return
	var p1 := Vector2(exits[0][0], exits[0][1])
	var p2 := Vector2(exits[1][0], exits[1][1])
	var along := (p2 - p1).normalized()
	var center := city.area.get_center()
	var land_sign := signf((p2 - p1).cross(Vector2(city.area.position.x, city.area.end.y) - p1))
	# Normal da costa apontando para o mar
	var to_sea := Vector2(-along.y, along.x) * -land_sign
	var foot := p1 + along * along.dot(center - p1)
	var img: Image = (load("res://assets/track/monaco/monaco_shore.png") as Texture2D).get_image()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6061
	var mat := TrackMaterials.structure()
	var wake_mesh := TrackHarbour.HarbourTraffic._wake_mesh()
	for i in SHIPS.size():
		var spec: Array = SHIPS[i]
		var dist: float = spec[2]
		# Longe da costa de verdade dentro da área dos dados
		while dist < 6000.0 and not _route_clear(img, city, foot + to_sea * dist, along):
			dist += 250.0
		var ship := MeshInstance3D.new()
		ship.name = "Ship%d" % i
		ship.mesh = ship_mesh(int(spec[0]), float(spec[1]), rng)
		ship.material_override = mat
		add_child(ship)
		var wake := MeshInstance3D.new()
		wake.mesh = wake_mesh
		wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wake)
		var length: float = spec[1]
		wake.set_meta("scale", Vector3(length / 16.0, 1.0, minf(length / 16.0, 4.0)))
		var dir := along if i % 2 == 0 else -along
		_ships.append([ship, wake, foot + to_sea * dist, dir, rng.randf_range(-ROUTE_HALF, ROUTE_HALF) * 0.6, float(spec[3]), rng.randf() * TAU])
	# Balões: o vento sopra ao longo da costa; sobre o porto e a orla, perto do circuito (um pouco
	# sobre a cidade até ~700 m mar adentro), grandes e baixos o bastante para ver da pista
	var wind := along if rng.randf() < 0.5 else -along
	var meshes := BALLOON_COLORS.map(func(pal: Array) -> ArrayMesh: return TrackScenery.balloon_mesh(pal))
	for k in BALLOON_COUNT:
		var b := MeshInstance3D.new()
		b.name = "Balloon%d" % k
		b.mesh = meshes[k % meshes.size()]
		var sc := rng.randf_range(1.6, 2.4)
		b.scale = Vector3(sc, sc, sc)
		add_child(b)
		var offset := rng.randf_range(-200.0, 700.0)
		_balloons.append([b, track_center + to_sea * offset, wind, rng.randf_range(-BALLOON_HALF, BALLOON_HALF), rng.randf_range(2.0, 4.5),
			rng.randf_range(130.0, 260.0), rng.randf() * TAU])
	# Dirigíveis: elipses ao longo da costa, deslocadas para o mar (a parte sobre a terra fica perto
	# da orla, onde os morros ainda são baixos)
	for k in BLIMPS.size():
		var spec: Array = BLIMPS[k]
		var node := MeshInstance3D.new()
		node.name = "Blimp%d" % k
		node.mesh = TrackScenery.blimp_mesh(spec[0], spec[1])
		add_child(node)
		_blimps.append([node, track_center + to_sea * float(spec[5]), along, to_sea, Vector2(spec[3], spec[4]), float(spec[6]),
			rng.randf() * TAU, float(spec[2])])
	_update(0.0)


## A rota (reta ao longo da costa) passa só por mar aberto dentro da área dos dados.
static func _route_clear(img: Image, city: TrackCity, base: Vector2, along: Vector2) -> bool:
	var a := city.area
	for k in range(-60, 61):
		var p := base + along * (k * 50.0)
		if not a.has_point(p):
			continue
		var px := int((p.x - a.position.x) / 2.0)
		var py := int((a.end.y - p.y) / 2.0)
		if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
			continue
		var pix := img.get_pixel(px, py)
		if pix.r < 0.99 or pix.g > 0.05:
			return false
	return true


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	_t += delta
	for sh in _ships:
		sh[4] = float(sh[4]) + float(sh[5]) * delta
		if sh[4] > ROUTE_HALF:
			sh[4] = -ROUTE_HALF
		var base: Vector2 = sh[2]
		var dir: Vector2 = sh[3]
		var p: Vector2 = base + dir * float(sh[4])
		var heading := atan2(dir.y, dir.x)
		var ph: float = sh[6]
		# Balanço leve no mar
		var basis := Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, sin(_t * 0.35 + ph) * 0.012)
		var pos := TrackCity.to_world(p.x, p.y, sin(_t * 0.5 + ph) * 0.25)
		(sh[0] as Node3D).transform = Transform3D(basis, pos)
		var wake: Node3D = sh[1]
		wake.transform = Transform3D(Basis(Vector3.UP, heading).scaled(wake.get_meta("scale")), TrackCity.to_world(p.x, p.y, 0.12))
	for b in _balloons:
		b[3] = float(b[3]) + float(b[4]) * delta
		if b[3] > BALLOON_HALF:
			b[3] = -BALLOON_HALF
		var base: Vector2 = b[1]
		var wind: Vector2 = b[2]
		var ph: float = b[6]
		var p: Vector2 = base + wind * float(b[3]) + Vector2(-wind.y, wind.x) * sin(_t * 0.02 + ph) * 60.0
		var node: Node3D = b[0]
		node.position = TrackCity.to_world(p.x, p.y, float(b[5]) + sin(_t * 0.25 + ph) * 6.0)
		node.rotation.y = _t * 0.03 + ph
	for bl in _blimps:
		var radii: Vector2 = bl[4]
		var speed: float = bl[5]
		# Velocidade ~constante ao longo da elipse (raio médio)
		bl[6] = float(bl[6]) + delta * speed / ((radii.x + radii.y) * 0.5)
		var ang: float = bl[6]
		var u: Vector2 = bl[2]
		var v: Vector2 = bl[3]
		var center: Vector2 = bl[1]
		var p: Vector2 = center + u * cos(ang) * radii.x + v * sin(ang) * radii.y
		var tangent: Vector2 = (-u * sin(ang) * radii.x + v * cos(ang) * radii.y) * signf(speed)
		var pos := TrackCity.to_world(p.x, p.y, float(bl[7]) + sin(_t * 0.2 + ang) * 5.0)
		var dir := TrackCity.to_world(tangent.x, tangent.y, 0.0).normalized()
		(bl[0] as Node3D).global_transform = Transform3D(Basis.looking_at(-dir), pos)


# ---------------------------------------------------------------------------
# Modelos dos navios (proa para +X, linha d'água em y = 0)
# ---------------------------------------------------------------------------
static var _cache := {}


static func ship_mesh(kind: int, length: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var key := "%d_%.0f" % [kind, length]
	if _cache.has(key):
		return _cache[key]
	var mb := MeshBuilder.new()
	match kind:
		Ship.CRUISE:
			var beam := length * 0.13
			var h := 13.0
			_hull(mb, length, beam, h, 8.0, WHITE, Color(0.1, 0.16, 0.32), WHITE)
			# Conveses de cabines com varandas (faixas de vidro escuro) e o deque da piscina
			var decks := 8
			for d in decks:
				var x0 := -length * (0.44 - d * 0.004)
				var x1 := length * (0.34 - d * 0.012)
				TrackHarbour._tier(mb, x0, x1, beam * (0.96 - d * 0.012), h + d * 2.9, 2.9)
			var top := h + decks * 2.9
			# Botes salva-vidas laranja nos dois bordos
			for k in 10:
				var x := -length * 0.3 + k * length * 0.055
				for side: float in [1.0, -1.0]:
					mb.box(Transform3D(Basis(), Vector3(x, h + 4.6, side * (beam * 0.5 + 0.6))), Vector3(9.0, 2.6, 3.0), Color(1.0, 0.5, 0.1))
			# Chaminé com a cor da companhia e tampa preta
			var funnel := Color(0.1, 0.35, 0.75) if rng.randf() < 0.5 else Color(0.85, 0.15, 0.2)
			mb.box(Transform3D(Basis(), Vector3(-length * 0.3, top + 5.0, 0)), Vector3(16.0, 10.0, 9.0), funnel)
			mb.box(Transform3D(Basis(), Vector3(-length * 0.3, top + 10.4, 0)), Vector3(16.4, 0.8, 9.4), Color(0.08, 0.08, 0.09))
			mb.box(Transform3D(Basis(), Vector3(length * 0.05, top + 0.6, 0)), Vector3(28.0, 1.2, beam * 0.5), Color(0.25, 0.7, 0.85))
		Ship.CONTAINER:
			var beam := length * 0.145
			var h := 11.0
			_hull(mb, length, beam, h, 9.0, Color(0.14, 0.2, 0.3), Color(0.55, 0.16, 0.12), Color(0.4, 0.4, 0.42))
			# Pilhas de contêineres (40 pés) entre a ponte e a proa
			var colors := [Color(0.75, 0.2, 0.15), Color(0.15, 0.35, 0.65), Color(0.85, 0.6, 0.15), Color(0.2, 0.55, 0.3),
				Color(0.6, 0.6, 0.62), Color(0.9, 0.45, 0.15), Color(0.45, 0.2, 0.5), Color(0.92, 0.92, 0.9)]
			var rows := int(beam / 2.6) - 1
			var bay := -length * 0.28
			while bay < length * 0.36:
				var tiers := rng.randi_range(3, 6)
				for r in rows:
					var z := (r - (rows - 1) * 0.5) * 2.55
					var stack := tiers - (1 if absi(r - rows / 2) > rows / 3 and rng.randf() < 0.5 else 0)
					for t in stack:
						var c: Color = colors[rng.randi() % colors.size()]
						mb.box(Transform3D(Basis(), Vector3(bay, h + 1.3 + t * 2.6, z)), Vector3(12.0, 2.5, 2.4), c * rng.randf_range(0.9, 1.05))
				bay += 12.6
			_bridge(mb, length, beam, h, 6, rng)
		Ship.TANKER:
			var beam := length * 0.16
			var h := 9.0
			_hull(mb, length, beam, h, 10.0, Color(0.13, 0.13, 0.15), Color(0.6, 0.12, 0.1), Color(0.55, 0.22, 0.18))
			# Tubulação e passarela ao longo do convés
			for z: float in [-2.0, 0.0, 2.0]:
				mb.posts().cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(length * 0.4, h + 1.0, z)), 0.5, 0.5, length * 0.7,
					Color(0.85, 0.8, 0.6), 6, false)
			mb.box(Transform3D(Basis(), Vector3(length * 0.05, h + 2.2, 0)), Vector3(length * 0.7, 0.3, 1.4), Color(0.75, 0.75, 0.72))
			_bridge(mb, length, beam, h, 5, rng)
		Ship.FERRY:
			var beam := length * 0.19
			var h := 9.0
			_hull(mb, length, beam, h, 5.0, WHITE, Color(0.1, 0.3, 0.6), WHITE)
			mb.box(Transform3D(Basis(), Vector3(0, h - 2.0, 0)), Vector3(length * 0.98, 1.2, beam + 0.2), Color(0.1, 0.4, 0.75))
			for d in 4:
				TrackHarbour._tier(mb, -length * (0.42 - d * 0.03), length * (0.3 - d * 0.05), beam * (0.95 - d * 0.04), h + d * 2.8, 2.8)
			mb.box(Transform3D(Basis(), Vector3(-length * 0.25, h + 4 * 2.8 + 3.5, 0)), Vector3(8.0, 7.0, 5.0), Color(0.95, 0.75, 0.1))
	var mesh := mb.commit()
	_cache[key] = mesh
	return mesh


## Casco: popa reta (x = -L/2), proa afinando; costado `side` acima da faixa da linha d'água e
## `bottom` abaixo dela; convés em `deck`.
static func _hull(mb: MeshBuilder, length: float, beam: float, height: float, draft: float, side: Color, bottom: Color, deck: Color) -> void:
	var stations := 14
	var pts := []
	for k in stations + 1:
		var u := float(k) / stations
		var w := beam * 0.5 * (0.92 + 0.08 * u / 0.65 if u < 0.65 else sqrt(maxf(1.0 - pow((u - 0.65) / 0.35, 2.0), 0.0)))
		var top := height * (1.0 + 0.12 * pow(maxf(u - 0.6, 0.0) / 0.4, 2.0))
		pts.append([-length * 0.5 + u * length, w, top])
	for k in stations:
		var a: Array = pts[k]
		var b: Array = pts[k + 1]
		for s: float in [1.0, -1.0]:
			var out := Vector3(0, 0, s)
			mb.quad(Vector3(a[0], 2.0, a[1] * s), Vector3(b[0], 2.0, b[1] * s), Vector3(b[0], b[2], b[1] * s),
				Vector3(a[0], a[2], a[1] * s), side, out)
			mb.quad(Vector3(a[0], -draft, a[1] * s * 0.8), Vector3(b[0], -draft, b[1] * s * 0.8), Vector3(b[0], 2.0, b[1] * s),
				Vector3(a[0], 2.0, a[1] * s), bottom, out)
		mb.quad(Vector3(a[0], a[2], -a[1]), Vector3(b[0], b[2], -b[1]), Vector3(b[0], b[2], b[1]), Vector3(a[0], a[2], a[1]), deck, Vector3.UP)
	var st: Array = pts[0]
	mb.quad(Vector3(st[0], -draft, st[1] * 0.8), Vector3(st[0], -draft, -st[1] * 0.8), Vector3(st[0], st[2], -st[1]),
		Vector3(st[0], st[2], st[1]), side, Vector3.LEFT)


## Ponte de comando na popa (navios de carga): blocos brancos com faixa de vidro e chaminé.
static func _bridge(mb: MeshBuilder, length: float, beam: float, h: float, tiers: int, rng: RandomNumberGenerator) -> void:
	var x0 := -length * 0.47
	var x1 := -length * 0.36
	for t in tiers:
		# O último andar (passadiço) vai de bordo a bordo
		TrackHarbour._tier(mb, x0, x1, beam * (1.0 if t == tiers - 1 else 0.85), h + t * 2.9, 2.9)
	var top := h + tiers * 2.9
	var funnel: Color = [Color(0.85, 0.15, 0.15), Color(0.15, 0.3, 0.6), Color(0.9, 0.7, 0.1)][rng.randi() % 3]
	mb.box(Transform3D(Basis(), Vector3(x0 - 2.0, top + 4.0, 0)), Vector3(6.0, 8.0, 5.0), funnel)
	mb.box(Transform3D(Basis(), Vector3(x0 - 2.0, top + 8.3, 0)), Vector3(6.2, 0.6, 5.2), Color(0.08, 0.08, 0.09))
