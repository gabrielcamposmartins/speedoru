class_name CityNeon
extends RefCounted
## Luzes de Las Vegas (cidade "modern" da TrackCity): letreiros, luminosos, placas famosas, telões
## de LED, uma cobertura de LED, dirigíveis e postes nas ruas. A arte (textos em várias fontes e
## cores, desenhos de neon, as placas famosas, os quadros de LED) vem do atlas do NeonArt; tubos de
## neon, painéis e lâmpadas em sequência são geometria (shader vegas_neon). Tudo acende forte à
## noite (set_night).
##
## Cada prédio traz no JSON (tools/build_las_vegas.py) o tipo de letreiro ("v"), o ponto da pista
## mais perto ("tp") e a distância até ele ("td"); o letreiro vai na parede virada para a pista:
## * torre (1): nome do hotel no alto da fachada (cada nome num estilo de letreiro), coroa de neon na
##   laje e, em parte delas, um desenho grande em pé no telhado (coroa, diamante, foguete...);
## * cassino (2): marquise (painel escuro, moldura de neon, lâmpadas correndo, a palavra) e, abaixo,
##   um telão de LED que troca de anúncio ou um desenho de neon na fachada; perto da pista, um ponto
##   para luminoso na calçada;
## * pequeno (3): lâmina vertical na quina, com letras empilhadas ou só um desenho.
## Luminosos de calçada: as placas famosas (espalhadas pela volta) e, nos outros, painel com nome,
## telão de LED e estrela. Placas famosas (recriação ou homenagem, sem nomes de verdade): "Welcome
## to Fabulous Las Vegas" (frente e verso), o caubói acenando (Vegas Vic), a vaqueira chutando
## (Vegas Vickie), a guitarra gigante (Hard Rock), o sapatinho girando no poste (Silver Slipper), o
## pilar atômico (Stardust), o flamingo com plumas (Flamingo), a ferradura (Binion's) e a lâmpada do
## gênio (Aladdin). Cobertura de LED à moda da Fremont Street sobre uma rua perto da pista
## (shader vegas_led). Três dirigíveis com telão de LED dando a volta no circuito.

const SIGN_TOWER := 1
const SIGN_CASINO := 2
const SIGN_SMALL := 3
## Distância máxima da pista (m) por tipo de letreiro: longe ninguém lê.
const RANGE_TOWER := 650.0
const RANGE_CASINO := 420.0
const RANGE_SMALL := 220.0
const RANGE_PYLON := 120.0
const POST_STEP := 34.0
const POST_MIN_STREET := 9.0
## Placas famosas, na ordem em que entram nos luminosos (espalhadas pela volta).
const FAMOUS := ["welcome", "cowboy", "guitar", "slipper", "atomic", "cowgirl", "flamingo", "luckyshoe", "genie"]

const NEON := ["ff2bd6", "21e6ff", "ffd23f", "7cff4f", "ff5a36", "b06bff", "ff3355", "49a6ff"]
const BULB := Color(1.0, 0.86, 0.55)
const PANEL := Color(0.06, 0.05, 0.1)
const STEEL := Color(0.78, 0.76, 0.74)

static var _mat: ShaderMaterial
static var _led_mat: ShaderMaterial

var track: RaceTrack
var city: TrackCity
var props: CityProps
var rng := RandomNumberGenerator.new()
## Tubos, painéis e lâmpadas (vegas_neon), estrutura (postes, sem brilho) e arte do atlas.
var neon := MeshBuilder.new()
var solid := MeshBuilder.new()
var art := MeshBuilder.new()
var root: Node3D
## Pontos para luminosos: [ponto (dados), parede da frente, s da pista].
var _spots: Array = []
var _art_points := PackedVector3Array()
var _count := {}


static func build(p_track: RaceTrack, p_city: TrackCity, parent: Node3D) -> void:
	var cn := CityNeon.new()
	cn.track = p_track
	cn.city = p_city
	cn.rng.seed = 7077
	cn.props = CityProps.new()
	cn.props.track = p_track
	cn.props.city = p_city
	cn.props._index()
	cn.root = Node3D.new()
	cn.root.name = "Neon"
	parent.add_child(cn.root)
	cn._signs()
	cn._pylons()
	cn._canopy()
	cn._blimps()
	cn._commit()
	cn._posts()
	print("CityNeon: %s" % ", ".join(cn._count.keys().map(func(k: String) -> String: return "%d %s" % [cn._count[k], k])))


func _commit() -> void:
	if not neon.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "NeonSigns"
		mi.mesh = neon.commit(null, material())
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	if not solid.is_empty():
		var si := MeshInstance3D.new()
		si.name = "NeonStructure"
		si.mesh = solid.commit(null, TrackMaterials.plain())
		root.add_child(si)
	if not art.is_empty():
		var ai := MeshInstance3D.new()
		ai.name = "SignArt"
		ai.mesh = art.commit(null, NeonArt.material())
		ai.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ai.set_meta("points", _art_points)
		root.add_child(ai)


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/track/vegas_neon.gdshader")
	return _mat


static func led_material() -> ShaderMaterial:
	if _led_mat == null:
		_led_mat = ShaderMaterial.new()
		_led_mat.shader = load("res://shaders/track/vegas_led.gdshader")
	return _led_mat


## Noite (0..1): neon, arte dos letreiros e LEDs mais fortes.
static func set_night(amount: float) -> void:
	for m in [_mat, _led_mat, NeonArt._mat]:
		if m:
			(m as ShaderMaterial).set_shader_parameter("night", amount)


static func _neon_color(i: int) -> Color:
	return Color(NEON[posmod(i, NEON.size())])


## Cor de vértice para o shader (linear) com a fase da lâmpada no alfa (1 = aceso direto).
static func _v(c: Color, phase := 1.0) -> Color:
	var l := c.srgb_to_linear()
	return Color(l.r, l.g, l.b, phase)


func _add(key: String) -> void:
	_count[key] = int(_count.get(key, 0)) + 1


func _pick(list: Array) -> String:
	return str(list[rng.randi() % list.size()])


# ---------------------------------------------------------------------------
# Arte do atlas
# ---------------------------------------------------------------------------
## Cartão com a célula `id` do atlas, centrado em `c`, de frente para right × up.
func _card(c: Vector3, right: Vector3, up: Vector3, w: float, h: float, id: String, mb: MeshBuilder = null, lit := 1.0) -> void:
	var r := NeonArt.uv(id)
	if r.size == Vector2.ZERO:
		return
	var b := mb if mb else art
	var hx := right * w * 0.5
	var hy := up * h * 0.5
	b.quad(c - hx - hy, c + hx - hy, c + hx + hy, c - hx + hy, Color(1, 1, 1, lit), right.cross(up),
		Vector2(r.position.x, r.end.y), r.end, Vector2(r.end.x, r.position.y), r.position)
	if mb == null:
		_art_points.append(c)


## Cartão dos dois lados (luminosos soltos): a frente para +z da base, o verso para -z, a `gap` m
## do meio (a espessura do que fica entre eles). `lit` = 0 para painel pintado (ver vegas_sign).
func _card2(c: Vector3, basis: Basis, w: float, h: float, id: String, back := "", mb: MeshBuilder = null, gap := 0.05,
		lit := 1.0) -> void:
	_card(c + basis.z * gap, basis.x, basis.y, w, h, id, mb, lit)
	_card(c - basis.z * gap, -basis.x, basis.y, w, h, back if back != "" else id, mb, lit)


## Cartão animado (quadros lado a lado no atlas): instância própria com os parâmetros de quadro.
func _anim(parent: Node3D, c: Vector3, basis: Basis, w: float, h: float, id: String, fps: float, two_sided := true) -> MeshInstance3D:
	var mb := MeshBuilder.new()
	if two_sided:
		_card2(c, basis, w, h, id, "", mb)
	else:
		_card(c, basis.x, basis.y, w, h, id, mb)
	return _anim_instance(parent, mb, id, fps)


func _anim_instance(parent: Node3D, mb: MeshBuilder, id: String, fps: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Anim_" + id.replace(":", "_")
	mi.set_meta("anim", id)
	mi.mesh = mb.commit(null, NeonArt.material())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fr := NeonArt.frames(id)
	mi.set_instance_shader_parameter("frame_step", fr[0])
	mi.set_instance_shader_parameter("frames", float(fr[1]))
	mi.set_instance_shader_parameter("fps", fps)
	parent.add_child(mi)
	if parent == root and not mb.verts.is_empty():
		_art_points.append(mb.verts[0])
	return mi


# ---------------------------------------------------------------------------
# Letreiros dos prédios
# ---------------------------------------------------------------------------
func _signs() -> void:
	for b: Dictionary in city.data["buildings"]:
		var v := int(b.get("v", 0))
		if v == 0 or not b.has("tp"):
			continue
		var td := float(b["td"])
		if td > [0.0, RANGE_TOWER, RANGE_CASINO, RANGE_SMALL][v]:
			continue
		var p: Array = b["p"]
		var poly := PackedVector2Array()
		for i in range(0, p.size(), 2):
			poly.append(Vector2(p[i], p[i + 1]))
		var tp := Vector2(b["tp"][0], b["tp"][1])
		var front := _front_edge(poly, tp)
		if front.is_empty():
			continue
		var base := float(b["b"]) + 0.6
		var top := float(b["t"])
		match v:
			SIGN_TOWER:
				_tower(poly, front, top, base)
			SIGN_CASINO:
				_casino(front, top, base, td, tp)
			SIGN_SMALL:
				_blade(front, top, base)


## Parede virada para a pista (a mais comprida entre as que olham para ela): [a, b, normal para fora].
func _front_edge(poly: PackedVector2Array, tp: Vector2) -> Array:
	var best := -1.0
	var out := []
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var length := a.distance_to(b)
		if length < 6.0:
			continue
		var e := (b - a) / length
		var nrm := Vector2(e.y, -e.x)  # anti-horário: fora à direita
		var facing := nrm.dot((tp - (a + b) * 0.5).normalized())
		if facing < 0.2:
			continue
		var score := length * facing
		if score > best:
			best = score
			out = [a, b, nrm]
	return out


## Base de frente para `z` (horizontal): x à direita de quem olha de fora, y para cima.
static func _facing(z: Vector3) -> Basis:
	return Basis(Vector3.UP.cross(z).normalized(), Vector3.UP, z)


static func _wall_basis(front: Array) -> Basis:
	var nrm: Vector2 = front[2]
	return _facing(Vector3(nrm.x, 0.0, -nrm.y))


func _tower(poly: PackedVector2Array, front: Array, top: float, base: float) -> void:
	var a: Vector2 = front[0]
	var b: Vector2 = front[1]
	var length := a.distance_to(b)
	var basis := _wall_basis(front)
	var mid := (a + b) * 0.5
	var id := "name:%d" % (rng.randi() % NeonArt.TOWER_NAMES.size())
	var asp := NeonArt.aspect(id)
	var w := minf(length * 0.88, (top - base) * 0.16 * asp)
	var h := w / maxf(asp, 0.01)
	if h >= 2.0:
		_card(TrackCity.to_world(mid.x, mid.y, top - h * 0.5 - 1.5) + basis.z * 0.5, basis.x, Vector3.UP, w, h, id)
		_add("nomes de torre")
	# Coroa de neon em volta da laje (sobre a mureta) e, em metade das torres, faixas nas quinas
	var crown := _neon_color(rng.randi())
	var n := poly.size()
	for i in n:
		var p0 := poly[i]
		var p1 := poly[(i + 1) % n]
		_tube(TrackCity.to_world(p0.x, p0.y, top + 1.05), TrackCity.to_world(p1.x, p1.y, top + 1.05), 0.32, _v(crown))
	if rng.randf() < 0.5:
		var drop := (top - base) * rng.randf_range(0.25, 0.6)
		var crown2 := _neon_color(rng.randi())
		for p0 in poly:
			var wp := TrackCity.to_world(p0.x, p0.y, top + 0.9)
			_tube(wp, wp + Vector3.DOWN * drop, 0.3, _v(crown2))
	# Desenho grande em pé no telhado, recuado da fachada, com a armação atrás
	if rng.randf() < 0.38 and length > 16.0:
		var icon := "icon:" + _pick(NeonArt.ICONS)
		var size := clampf(length * 0.42, 9.0, 26.0)
		var c := TrackCity.to_world(mid.x, mid.y, top + 1.6 + size * 0.5) - basis.z * 3.0
		_card2(c, basis, size, size, icon)
		for sx: float in [-0.3, 0.3]:
			var leg := c + basis.x * size * sx - basis.z * 0.6
			solid.box(Transform3D(basis, Vector3(leg.x, top + (size * 0.5 + 1.6) * 0.5, leg.z)), Vector3(0.4, size * 0.5 + 1.6, 0.4), STEEL)
		_add("desenhos no telhado")


func _casino(front: Array, top: float, base: float, td: float, tp: Vector2) -> void:
	var a: Vector2 = front[0]
	var b: Vector2 = front[1]
	var length := a.distance_to(b)
	var basis := _wall_basis(front)
	var mid := (a + b) * 0.5
	var height := top - base
	var frame := _neon_color(rng.randi())
	# Marquise: painel no alto da fachada, um pouco acima da mureta, com a palavra
	var w := minf(length * 0.72, 60.0)
	var h := clampf(height * 0.32, 3.2, 7.5)
	var c := TrackCity.to_world(mid.x, mid.y, top - h * 0.5 + 1.6) + basis.z * 0.5
	_panel(Transform3D(basis, c), w, h, frame, true)
	var word := "word:%d" % (rng.randi() % NeonArt.CASINO_WORDS.size())
	var asp := NeonArt.aspect(word)
	var ww := minf(w * 0.94, h * 1.05 * asp)
	_card(c + basis.z * 0.5, basis.x, Vector3.UP, ww, ww / asp, word)
	_add("marquises")
	# Embaixo: telão de LED, desenho de neon ou faixas verticais
	var low := base + 1.0
	var high := top - h + 1.0
	var room := high - low
	var r := rng.randf()
	if r < 0.45 and room > 8.0 and length > 22.0:
		var sw := minf(minf(length * 0.34, 20.0), (room - 2.0) * 2.0)
		var sh := sw * 0.5
		var along := (rng.randf_range(-1.0, 1.0)) * maxf(length * 0.5 - sw * 0.6, 0.0)
		var e := (b - a).normalized()
		var sp := mid + e * along
		var sc := TrackCity.to_world(sp.x, sp.y, high - sh * 0.5 - 1.0) + basis.z * 0.45
		neon.box(Transform3D(basis, sc - basis.z * 0.2), Vector3(sw + 0.8, sh + 0.8, 0.4), _v(PANEL))
		_anim(root, sc + basis.z * 0.05, basis, sw, sh, "reel:%d" % (rng.randi() % NeonArt.REELS), 0.4, false)
		_add("telões de LED")
	elif r < 0.8 and room > 6.0:
		var size := clampf(room * 0.7, 5.0, 14.0)
		var icon := "icon:" + _pick(NeonArt.ICONS)
		var e := (b - a).normalized()
		var sp := mid + e * rng.randf_range(-0.3, 0.3) * length
		_card(TrackCity.to_world(sp.x, sp.y, low + room * 0.5) + basis.z * 0.4, basis.x, Vector3.UP, size, size, icon)
		_add("desenhos na fachada")
	elif room > 3.0:
		var stripes := _neon_color(rng.randi())
		var k := int(length / 12.0)
		for i in range(1, k):
			var p := a.lerp(b, float(i) / k)
			var w0 := TrackCity.to_world(p.x, p.y, low) + basis.z * 0.25
			_tube(w0, w0 + Vector3.UP * room, 0.26, _v(stripes))
	# Ponto para luminoso na calçada, para um lado da fachada (sem tapar a marquise)
	if td < RANGE_PYLON:
		_spot(mid + (b - a).normalized() * length * rng.randf_range(0.25, 0.4) * (1.0 if rng.randf() < 0.5 else -1.0), front, tp)


## Lâmina vertical na quina da fachada: letras empilhadas (os dois lados) ou só um desenho.
func _blade(front: Array, top: float, base: float) -> void:
	var a: Vector2 = front[0]
	var b: Vector2 = front[1]
	var e := (b - a).normalized()
	var nrm: Vector2 = front[2]
	var corner := a + e * 1.6 if rng.randf() < 0.5 else b - e * 1.6
	var out := Vector3(nrm.x, 0.0, -nrm.y)
	var along := Vector3(e.x, 0.0, -e.y)
	var color := _neon_color(rng.randi())
	if rng.randf() < 0.62:
		var id := "blade:%d" % (rng.randi() % NeonArt.BLADE_WORDS.size())
		var hb := clampf((top - base) * 0.9 + 2.0, 6.0, 13.0)
		var bottom := maxf(base + 3.0, top + 2.0 - hb)
		var c := TrackCity.to_world(corner.x, corner.y, bottom + hb * 0.5) + out * 1.5
		var asp := NeonArt.aspect(id)
		_panel(Transform3D(_facing(along), c), (hb - 0.4) * asp + 0.6, hb, color, false, 0.4)
		_card2(c, _facing(along), (hb - 0.6) * asp, hb - 0.6, id)
		_add("lâminas")
	else:
		var size := rng.randf_range(3.2, 4.6)
		var c := TrackCity.to_world(corner.x, corner.y, maxf(base + 3.5, top - size * 0.3)) + out * (size * 0.5 + 0.6)
		_panel(Transform3D(_facing(along), c), size, size, color, false, 0.3)
		_card2(c, _facing(along), size * 0.95, size * 0.95, "icon:" + _pick(NeonArt.ICONS))
		solid.box(Transform3D(_facing(along), c - out * (size * 0.5 + 0.3)), Vector3(0.2, 0.2, 0.8), STEEL)
		_add("lâminas de desenho")


# ---------------------------------------------------------------------------
# Luminosos de calçada e placas famosas
# ---------------------------------------------------------------------------
func _spot(mid: Vector2, front: Array, tp: Vector2) -> void:
	for d: float in [6.0, 9.0, 12.0, 15.0]:
		var q: Vector2 = mid + (front[2] as Vector2) * d
		var far := true
		for s: Array in _spots:
			if (s[0] as Vector2).distance_to(q) < 70.0:
				far = false
				break
		if far and props._free(q, 3.0):
			var pr := track.path.project(Vector3(tp.x, 0.0, -tp.y), false)
			_spots.append([q, front, pr.x if pr.y != INF else 0.0])
			props._mark(q)
			return


func _pylons() -> void:
	_spots.sort_custom(func(x: Array, y: Array) -> bool: return float(x[2]) < float(y[2]))
	var famous_at := {}
	var n := _spots.size()
	for k in mini(FAMOUS.size(), n):
		famous_at[int((k + 0.5) * n / mini(FAMOUS.size(), n))] = FAMOUS[k]
	for i in n:
		var spot: Vector2 = _spots[i][0]
		var basis := _wall_basis(_spots[i][1])
		var foot := Vector3(spot.x, city.height_at(spot.x, -spot.y), -spot.y)
		if famous_at.has(i):
			_famous(famous_at[i], foot, basis)
			_add("placas famosas")
		else:
			_generic_pylon(foot, basis)
			_add("luminosos")


func _posts2(foot: Vector3, basis: Basis, half_sep: float, height: float, thick := 0.7, color := STEEL) -> void:
	for sx: float in [-1.0, 1.0]:
		solid.box(Transform3D(basis, foot + basis.x * sx * half_sep + Vector3.UP * height * 0.5), Vector3(thick, height, thick), color)


func _famous(id: String, foot: Vector3, basis: Basis) -> void:
	var node := Node3D.new()
	node.name = id.capitalize().replace(" ", "")
	# Marca da placa (vazia): posição e frente (+z), para testes e capturas
	node.transform = Transform3D(basis, foot)
	root.add_child(node)
	var art_id := "famous:" + id
	var asp := NeonArt.aspect(art_id)
	match id:
		"welcome":
			# Postes chatos ligados por uma travessa; o painel (com a estrela) entre eles
			var w := 11.0
			var h := w / asp
			_posts2(foot, basis, 3.4, h + 3.6, 0.5, Color(0.92, 0.92, 0.9))
			solid.box(Transform3D(basis, foot + Vector3.UP * (h + 3.4)), Vector3(7.4, 0.5, 0.5), Color(0.92, 0.92, 0.9))
			_card2(foot + Vector3.UP * (h * 0.5 + 2.6), basis, w, h, art_id, "famous:welcome_back", null, 0.05, 0.0)
		"cowboy", "cowgirl":
			# Em cima de um pedestal com moldura de neon, acenando (2 quadros)
			var w := 12.0
			var h := w / asp
			solid.box(Transform3D(basis, foot + Vector3.UP * 2.0), Vector3(8.0, 4.0, 3.0), Color(0.35, 0.22, 0.14))
			_tube(foot + Vector3.UP * 4.1 - basis.x * 4.0 + basis.z * 1.6, foot + Vector3.UP * 4.1 + basis.x * 4.0 + basis.z * 1.6, 0.3,
				_v(Color("ffd23f")))
			solid.box(Transform3D(basis, foot + Vector3.UP * (4.0 + h * 0.45) - basis.z * 0.4), Vector3(0.5, h * 0.9, 0.5), STEEL)
			_anim(root, foot + Vector3.UP * (4.0 + h * 0.5), basis, w, h, art_id, 1.3)
		"guitar":
			var w := 9.0
			var h := w / asp
			solid.box(Transform3D(basis, foot + Vector3.UP * h * 0.45 - basis.z * 0.5), Vector3(0.6, h * 0.9, 0.6), STEEL)
			_card2(foot + Vector3.UP * (h * 0.5 + 0.5), basis, w, h, art_id)
		"slipper":
			# Sapatinho girando no alto do poste
			var pole := 15.0
			solid.cylinder(Transform3D(basis, foot), 0.45, 0.35, pole, STEEL)
			var pivot := VegasMotion.new()
			pivot.name = "SlipperSpin"
			pivot.spin = 0.55
			pivot.position = foot + Vector3.UP * pole
			root.add_child(pivot)
			var w := 15.0
			var mb := MeshBuilder.new()
			_card2(Vector3.UP * (w / asp * 0.5), Basis(), w, w / asp, art_id, "", mb)
			var mi := MeshInstance3D.new()
			mi.mesh = mb.commit(null, NeonArt.material())
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(mi)
			_art_points.append(foot + Vector3.UP * pole)
		"atomic":
			var w := 7.0
			var h := w / asp
			neon.box(Transform3D(basis, foot + Vector3.UP * (h * 0.5 + 1.5)), Vector3(w * 0.5, h * 0.9, 0.6), _v(PANEL))
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var e0 := foot + basis.x * sx * w * 0.26 + basis.z * sz * 0.35 + Vector3.UP * 2.0
					_tube(e0, e0 + Vector3.UP * h * 0.85, 0.25, _v(Color("ffd23f")))
			_card2(foot + Vector3.UP * (h * 0.5 + 1.5), basis, w, h, art_id, "", null, 0.36)
		_:
			# Flamingo, ferradura, gênio: painel solto em dois postes
			var w := 12.0
			var h := w / asp
			_posts2(foot, basis, w * 0.3, 6.0 + h * 0.6)
			_card2(foot + Vector3.UP * (6.0 + h * 0.5), basis, w, h, art_id)


## Luminoso comum: painel com o nome (num estilo de letreiro), telão de LED embaixo e estrela.
func _generic_pylon(foot: Vector3, basis: Basis) -> void:
	var hp := rng.randf_range(14.0, 22.0)
	var w := rng.randf_range(8.5, 11.0)
	var frame := _neon_color(rng.randi())
	_posts2(foot, basis, w * 0.32, hp)
	var id := "name:%d" % (rng.randi() % NeonArt.TOWER_NAMES.size())
	var main_h := w / NeonArt.aspect(id) + 1.2
	var mc := foot + Vector3.UP * (hp + main_h * 0.5 - 1.0)
	_panel(Transform3D(basis, mc), w, main_h, frame, true)
	var cw := w * 0.94
	_card(mc + basis.z * 0.5, basis.x, Vector3.UP, cw, cw / NeonArt.aspect(id), id)
	_card(mc - basis.z * 0.5, -basis.x, Vector3.UP, cw, cw / NeonArt.aspect(id), id)
	# Telão de LED embaixo do painel
	var sw := w * 0.8
	var sh := sw * 0.5
	var sc := foot + Vector3.UP * (hp - sh * 0.5 - 2.0)
	neon.box(Transform3D(basis, sc), Vector3(sw + 0.6, sh + 0.6, 0.7), _v(PANEL))
	var mb := MeshBuilder.new()
	_card(sc + basis.z * 0.37, basis.x, Vector3.UP, sw, sh, "reel:%d" % (rng.randi() % NeonArt.REELS), mb)
	var reel := "reel:%d" % (rng.randi() % NeonArt.REELS)
	_card(sc - basis.z * 0.37, -basis.x, Vector3.UP, sw, sh, reel, mb)
	_anim_instance(root, mb, reel, 0.4)
	# Estrela de neon no alto
	var star := mc + Vector3.UP * (main_h * 0.5 + 2.6)
	var sc2 := _v(_neon_color(rng.randi()))
	for k in 4:
		var ang := k * PI * 0.25
		var d := basis.x * cos(ang) + Vector3.UP * sin(ang)
		_tube(star - d * 2.2, star + d * 2.2, 0.35, sc2)


# ---------------------------------------------------------------------------
# Cobertura de LED (Fremont Street) e dirigíveis
# ---------------------------------------------------------------------------
## Rua larga e reta perto da pista (sem cruzar com ela) coberta por uma abóbada de LED em colunas.
func _canopy() -> void:
	var best := []
	var best_d := INF
	for st: Dictionary in city.data["streets"]:
		var w := float(st["w"])
		if w < 9.0 or int(st.get("k", 0)) == 1:
			continue
		var p: Array = st["p"]
		var pts := PackedVector2Array()
		for i in range(0, p.size(), 3):
			pts.append(Vector2(p[i], p[i + 1]))
		var i := 0
		while i < pts.size() - 1:
			var dir := (pts[i + 1] - pts[i]).normalized()
			var j := i + 1
			while j < pts.size() - 1 and (pts[j + 1] - pts[j]).normalized().dot(dir) > 0.997:
				j += 1
			var run := pts[i].distance_to(pts[j])
			if run >= 130.0:
				var length := minf(run, 170.0)
				var a := pts[i] + dir * (run - length) * 0.5
				var center := a + dir * length * 0.5
				var pr := track.path.project(Vector3(center.x, 0.0, -center.y), false)
				var d := absf(pr.y) if pr.y != INF else 400.0
				if d > 45.0 and d < best_d and _canopy_clear(a, dir, length, w + 6.0):
					best_d = d
					best = [a, dir, length, w]
			i = j
	if best.is_empty():
		return
	var a: Vector2 = best[0]
	var dir: Vector2 = best[1]
	var length: float = best[2]
	var span: float = float(best[3]) + 4.0
	var nrm := Vector2(-dir.y, dir.x)
	var col_h := 17.0
	var rise := 5.0
	var ground := city.height_at(a.x, -a.y)
	var led := MeshBuilder.new()
	var across := 12
	var steps := int(length / 3.0)
	for k in steps:
		var t0 := float(k) / steps
		var t1 := float(k + 1) / steps
		for i in across:
			var v0 := float(i) / across
			var v1 := float(i + 1) / across
			var q := [[t0, v0], [t1, v0], [t1, v1], [t0, v1]]
			var verts: Array[Vector3] = []
			for c: Array in q:
				var pp: Vector2 = a + dir * length * float(c[0]) + nrm * (float(c[1]) - 0.5) * span
				verts.append(Vector3(pp.x, ground + col_h + rise * sin(PI * float(c[1])), -pp.y))
			led.quad(verts[0], verts[1], verts[2], verts[3], Color.WHITE, Vector3.DOWN,
				Vector2(t0 * length, v0), Vector2(t1 * length, v0), Vector2(t1 * length, v1), Vector2(t0 * length, v1))
	var mi := MeshInstance3D.new()
	mi.name = "LedCanopy"
	mi.mesh = led.commit(null, led_material())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# Colunas e vigas laterais
	var d3 := Vector3(dir.x, 0.0, -dir.y)
	var basis := _facing(d3)
	var s := 0.0
	while s <= length + 0.1:
		for side: float in [-0.5, 0.5]:
			var pp := a + dir * s + nrm * side * span
			solid.box(Transform3D(basis, Vector3(pp.x, ground + col_h * 0.5, -pp.y)), Vector3(1.0, col_h, 1.0), Color(0.35, 0.36, 0.4))
		s += 18.0
	for side: float in [-0.5, 0.5]:
		var mid := a + dir * length * 0.5 + nrm * side * span
		solid.box(Transform3D(basis, Vector3(mid.x, ground + col_h, -mid.y)), Vector3(1.2, 1.2, length), Color(0.3, 0.3, 0.34))
	_art_points.append(Vector3(a.x + dir.x * length * 0.5, ground + col_h, -(a.y + dir.y * length * 0.5)))
	_add("cobertura de LED")


func _canopy_clear(a: Vector2, dir: Vector2, length: float, span: float) -> bool:
	var nrm := Vector2(-dir.y, dir.x)
	var s := 0.0
	while s <= length:
		for side: float in [-0.5, 0.0, 0.5]:
			var pp := a + dir * s + nrm * side * span
			if not CityProps.clear_of_track(track, Vector3(pp.x, 0.0, -pp.y), 6.0):
				return false
		s += 6.0
	return true


## Três dirigíveis em volta do circuito, a 150–200 m de altura, com telão de LED dos dois lados.
func _blimps() -> void:
	var center := Vector3.ZERO
	var n := 0
	var s := 0.0
	while s < track.path.length:
		center += track.path.position_at(s)
		n += 1
		s += 50.0
	center /= maxi(n, 1)
	var colors := [Color("ff3fa4"), Color("3fe6ff"), Color("ffc93f")]
	for k in 3:
		var pivot := VegasMotion.new()
		pivot.name = "BlimpOrbit%d" % k
		var dirn := 1.0 if k != 1 else -1.0
		pivot.spin = (0.016 + k * 0.004) * dirn
		pivot.position = center + Vector3.UP * (150.0 + k * 25.0)
		pivot.rotation.y = k * TAU / 3.0
		root.add_child(pivot)
		var blimp := VegasMotion.new()
		blimp.name = "Blimp%d" % k
		blimp.bob = 3.0
		blimp.position = Vector3(520.0 + k * 140.0, 0.0, 0.0)
		# Nariz para onde a órbita leva (spin positivo leva +X para -Z)
		if dirn < 0.0:
			blimp.rotation.y = PI
		pivot.add_child(blimp)
		_blimp_model(blimp, colors[k], k)


func _blimp_model(blimp: Node3D, color: Color, k: int) -> void:
	var body := MeshBuilder.new()
	var hull := Color(0.93, 0.93, 0.95)
	body.blob(Vector3.ZERO, Vector3(8.0, 8.0, 30.0), hull, 18, 12, 0.25)
	for f: Array in [[Vector3(0, 6.5, 24), Vector3(0.6, 9.0, 8.0)], [Vector3(0, -6.5, 24), Vector3(0.6, 9.0, 8.0)],
			[Vector3(6.5, 0, 24), Vector3(9.0, 0.6, 8.0)], [Vector3(-6.5, 0, 24), Vector3(9.0, 0.6, 8.0)]]:
		body.box(Transform3D(Basis(), f[0]), f[1], color)
	body.box(Transform3D(Basis(), Vector3(0, -8.6, -4)), Vector3(3.2, 2.6, 10.0), Color(0.25, 0.26, 0.3))
	var mi := MeshInstance3D.new()
	mi.name = "Hull"
	mi.mesh = body.commit(null, TrackMaterials.plain())
	blimp.add_child(mi)
	# Telão curvo dos dois lados (segue o casco) e luzes de navegação
	var reel := "reel:%d" % ((k * 2 + 1) % NeonArt.REELS)
	var r := NeonArt.uv(reel)
	var mb := MeshBuilder.new()
	for side: float in [1.0, -1.0]:
		var cols := 10
		var rows := 6
		for i in cols:
			for j in rows:
				var q: Array[Vector3] = []
				var uvs: Array[Vector2] = []
				for c: Vector2 in [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]:
					var z := lerpf(13.0, -13.0, c.x / cols) * side
					var y := lerpf(-5.2, 5.2, c.y / rows)
					var rz := 8.0 * sqrt(maxf(1.0 - pow(z / 30.0, 2.0), 0.0))
					var x := sqrt(maxf(rz * rz - y * y, 0.0)) + 0.12
					q.append(Vector3(x * side, y, z))
					uvs.append(Vector2(lerpf(r.position.x, r.end.x, c.x / cols), lerpf(r.end.y, r.position.y, c.y / rows)))
				var nrm := Vector3(side, 0.0, 0.0)
				mb.quad(q[0], q[1], q[2], q[3], Color.WHITE, nrm, uvs[0], uvs[1], uvs[2], uvs[3])
	_anim_instance(blimp, mb, reel, 0.35)
	var lights := MeshBuilder.new()
	lights.box(Transform3D(Basis(), Vector3(-11.0, 0, 24)), Vector3(0.8, 0.8, 0.8), _v(Color(1, 0.15, 0.1)))
	lights.box(Transform3D(Basis(), Vector3(11.0, 0, 24)), Vector3(0.8, 0.8, 0.8), _v(Color(0.2, 1, 0.3)))
	lights.box(Transform3D(Basis(), Vector3(0, 11.0, 26)), Vector3(0.8, 0.8, 0.8), _v(Color.WHITE, 0.0))
	for z in range(-26, 27, 4):
		lights.box(Transform3D(Basis(), Vector3(0, 8.0 * sqrt(1.0 - pow(z / 30.0, 2.0)) + 0.1, z)), Vector3(0.5, 0.3, 0.5),
			_v(color, fposmod(z * 0.0625, 1.0)))
	var li := MeshInstance3D.new()
	li.name = "Lights"
	li.mesh = lights.commit(null, material())
	li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blimp.add_child(li)


# ---------------------------------------------------------------------------
# Geometria de neon
# ---------------------------------------------------------------------------
## Painel escuro com moldura de neon (os dois lados) e, opcionalmente, lâmpadas correndo em cima e
## embaixo. Base: x = largura, y = altura, z = espessura (frente em +z).
func _panel(xf: Transform3D, w: float, h: float, frame: Color, bulbs: bool, depth := 0.8) -> void:
	neon.box(xf, Vector3(w, h, depth), _v(PANEL))
	var fc := _v(frame)
	var bx := xf.basis.x
	var by := xf.basis.y
	for side: float in [1.0, -1.0]:
		var z: Vector3 = xf.basis.z * side * (depth * 0.5 + 0.08)
		var o := xf.origin + z
		var hx := bx * (w * 0.5 - 0.15)
		var hy := by * (h * 0.5 - 0.15)
		_tube(o - hx - hy, o + hx - hy, 0.22, fc)
		_tube(o - hx + hy, o + hx + hy, 0.22, fc)
		_tube(o - hx - hy, o - hx + hy, 0.22, fc)
		_tube(o + hx - hy, o + hx + hy, 0.22, fc)
		if not bulbs:
			continue
		var count := int(w / 0.9)
		for i in count:
			var t := (i + 0.5) / count - 0.5
			for row: float in [-1.0, 1.0]:
				var p: Vector3 = o + bx * t * w + by * row * (h * 0.5 + 0.35)
				neon.box(Transform3D(xf.basis, p), Vector3(0.3, 0.3, 0.2), _v(BULB, float(i % 4) * 0.25))


func _tube(a: Vector3, b: Vector3, thick: float, color: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var y := d / length
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	neon.box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(thick, length + thick, thick), color)


# ---------------------------------------------------------------------------
# Postes
# ---------------------------------------------------------------------------
func _posts() -> void:
	var xfs: Array[Transform3D] = []
	for st: Dictionary in city.data["streets"]:
		var w := float(st["w"])
		if w < POST_MIN_STREET or int(st.get("k", 0)) == 1:
			continue
		var p: Array = st["p"]
		var pts := PackedVector2Array()
		for i in range(0, p.size(), 3):
			pts.append(Vector2(p[i], p[i + 1]))
		# Meio passo entre os lados: os postes ficam alternados
		var run := POST_STEP * 0.25
		var k := 0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var length := a.distance_to(b)
			if length < 0.01:
				continue
			var e := (b - a) / length
			var t := run
			while t < length:
				var nrm := Vector2(-e.y, e.x) * (1.0 if k % 2 == 0 else -1.0)
				var d := a + e * t + nrm * (w * 0.5 + 1.1)
				k += 1
				if props._free(d, 0.15):
					props._mark(d)
					var to_street := Vector3(-nrm.x, 0.0, nrm.y)
					xfs.append(Transform3D(Basis.looking_at(to_street), Vector3(d.x, city.height_at(d.x, -d.y), -d.y)))
				t += POST_STEP * 0.5
			run = t - length
	if xfs.is_empty():
		return
	var lods := [[_post_mesh(), null, 0.0, 650.0, false]]
	CityProps.add_chunked(root, "StreetPosts", xfs, [], lods)
	_count["postes"] = xfs.size()


## Poste de rua com braço (frente para -Z, a rua): coluna cinza e luminária acesa (neon).
static func _post_mesh() -> ArrayMesh:
	var pole := MeshBuilder.new()
	var gray := Color(0.42, 0.43, 0.45)
	pole.cylinder(Transform3D.IDENTITY, 0.16, 0.1, 10.0, gray, 6)
	pole.box(Transform3D(Basis(), Vector3(0, 9.75, -1.4)), Vector3(0.14, 0.14, 2.9), gray)
	pole.box(Transform3D(Basis(), Vector3(0, 0.4, 0)), Vector3(0.5, 0.8, 0.5), gray.darkened(0.2))
	var mesh := pole.commit(null, TrackMaterials.plain())
	var head := MeshBuilder.new()
	head.box(Transform3D(Basis(), Vector3(0, 9.6, -2.75)), Vector3(0.45, 0.22, 0.95), _v(Color(1.0, 0.9, 0.72)))
	head.commit(mesh, material())
	return mesh
