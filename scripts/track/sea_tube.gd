class_name SeaTube
extends RefCounted
## O grande tubo de vidro da pista no fundo do mar: os carros correm no seco, dentro dele. Cobre
## toda a pista debaixo d'água (até um pouco depois de a pista sair dela no Portão de Poseidon),
## menos o túnel de cristal (GlassTunnel), que continua sendo o trecho mais estreito: nas pontas
## dele, uma parede de pedra fecha o vão entre o tubo grande e o túnel. Onde a pista sai da água o
## tubo termina num portal de pedra.
##
## A seção é quase quadrada (superelipse: paredes retas que curvam no alto), com a base nas bordas
## da laje (as mesmas da SeaCauseway: atrás das barreiras, arquibancadas e boxes) e a altura pela
## largura (TUBE_MIN..TUBE_MAX m), suavizadas ao longo da pista. Vidro transparente
## (sea_glass.gdshader), nervuras de bronze com pátina (sea_bronze.gdshader) a cada RIB_SPACING m:
## perfil com aba por fora e por dentro, pilastras na base com capitel dourado, luzes quentes embaixo,
## um friso ciano por dentro e, a cada BANNER_RIBS nervuras (entre as dos estandartes), um medalhão
## dourado com o tridente pendurado no alto; a viga do topo com uma linha de luz. Só visual; em
## pedaços para o recorte.
##
## Por dentro é seco: surface_carve() dá a máscara de onde ele atravessa a linha d'água (lá a
## superfície do mar não é desenhada) e corridor() o trecho perto da câmera, onde as partículas da
## água não aparecem.

const TUBE_MIN := 13.0
const TUBE_MAX := 22.0
## Altura = meia-largura × isto (entre TUBE_MIN e TUBE_MAX).
const HEIGHT_RATIO := 0.62
## Forma da seção (superelipse): menor = mais quadrada.
const SHAPE := 0.6
const RIB_SPACING := 12.0
## Estandarte numa nervura a cada tantas (lados alternados).
const BANNER_RIBS := 3
const ARC := 22
## O tubo continua até a pista estar isto acima da linha d'água.
const END_ABOVE := 1.5
const CHUNK := 150
## Recorte da superfície do mar dentro do tubo: folga para dentro do vidro e tamanho do pixel (m).
const CARVE_INSET := 0.35
const CARVE_TEXEL := 0.75
## Meio comprimento do trecho do tubo passado às partículas da água (corridor()).
const CORRIDOR := 48.0
const METAL := Color(0.62, 0.43, 0.2)
const GOLD := Color(1.0, 0.8, 0.32)
const STONE := Color(0.84, 0.81, 0.74)
const LAMP := Color(1.0, 0.82, 0.42)
const LED := Color(0.25, 0.95, 1.0)
const VISIBILITY := 1100.0


## Perfil do tubo por amostra (calculado uma vez por pista): bordas (lateral até a base, de cada
## lado), altura e se a amostra está coberta.
static func profile(track: RaceTrack) -> Dictionary:
	if track.has_meta("sea_tube"):
		var cached: Dictionary = track.get_meta("sea_tube")
		if cached.get("path") == track.path:
			return cached
	var p := track.path
	var n := p.size()
	var raw := [SkyDeck.edges(track, 1), SkyDeck.edges(track, -1)]
	var edges := []
	for side in 2:
		# Máximo móvel e depois média: o tubo não acompanha cada degrau da laje
		var m := RaceTrack._dilate(raw[side], 12)
		var avg := PackedFloat32Array()
		avg.resize(n)
		for i in n:
			var acc := 0.0
			for d in range(-8, 9):
				acc += m[(i + d + n) % n]
			avg[i] = acc / 17.0 - 0.6
		edges.append(avg)
	var height := PackedFloat32Array()
	height.resize(n)
	for i in n:
		height[i] = clampf((edges[0][i] + edges[1][i]) * 0.5 * HEIGHT_RATIO, TUBE_MIN, TUBE_MAX)
	var smooth := RaceTrack._dilate(height, 10)
	var on := PackedByteArray()
	on.resize(n)
	var water := track.layout.water_level
	for i in n:
		on[i] = 1 if p.points[i].y < water + END_ABOVE and not track.in_tunnel(i) else 0
	var data := {"path": p, "left": edges[0], "right": edges[1], "height": smooth, "on": on}
	track.set_meta("sea_tube", data)
	return data


## Distância da linha central até onde termina tudo o que está junto da pista naquele lado,
## contando o tubo (para quem constrói do lado de fora: colunas, portal, muralhas, falésias).
static func clearance(track: RaceTrack, i: int, side: int) -> float:
	var data := profile(track)
	var e := track.structure_extent(i, side)
	if data.on[i] == 1:
		e = maxf(e, float(data.left[i] if side > 0 else data.right[i]) + 1.5)
	return e


## A amostra i está dentro do tubo grande.
static func covers(track: RaceTrack, i: int) -> bool:
	return profile(track).on[i] == 1


## Ponto `pos` dentro do volume do tubo (ou do túnel de cristal), com folga `margin` m: o ar onde os
## carros correm (os corais e as algas ficam fora dele).
static func inside(track: RaceTrack, pos: Vector3, margin := 3.0) -> bool:
	return _volume(track, pos, margin, 1.0 + margin)


## Como inside(), mas com a forma de verdade da seção (a superelipse do tubo, a elipse do túnel de
## cristal) em vez da caixa em volta dela: para o que contorna o tubo de perto (o arco das pontes do
## cânion). `margin` aumenta a seção.
static func in_section(track: RaceTrack, pos: Vector3, margin := 0.0) -> bool:
	var pr := track.path.project(pos, false, false)
	if pr.y == INF:
		return false
	var data := profile(track)
	var i := track.path.index_at(pr.x)
	var tunnel := track.in_tunnel(i)
	if data.on[i] == 0 and not tunnel:
		return false
	var dy := pos.y - track.path.points[i].y
	if dy < -margin:
		return false
	var l: float = GlassTunnel._edge(track, i, 1) if tunnel else float(data.left[i])
	var r: float = GlassTunnel._edge(track, i, -1) if tunnel else float(data.right[i])
	var h: float = GlassTunnel.HEIGHT if tunnel else float(data.height[i])
	# (point(): |x - meio| / meia-largura = |cos|^SHAPE, y / altura = sen^SHAPE)
	var power := 2.0 if tunnel else 2.0 / SHAPE
	var x := absf(pr.y - (l - r) * 0.5) / ((l + r) * 0.5 + margin)
	var y := maxf(dy, 0.0) / (h + margin)
	return pow(x, power) + pow(y, power) < 1.0


## Como inside(), contando também a laje e o aqueduto embaixo dela: para os bichos não passarem por
## dentro do tubo nem atravessarem os pilares.
static func blocked(track: RaceTrack, pos: Vector3, margin := 3.0) -> bool:
	return _volume(track, pos, margin, 60.0)


static func _volume(track: RaceTrack, pos: Vector3, margin: float, below: float) -> bool:
	var pr := track.path.project(pos, false, false)
	if pr.y == INF:
		return false
	var data := profile(track)
	var i := track.path.index_at(pr.x)
	var tunnel := track.in_tunnel(i)
	if data.on[i] == 0 and not tunnel:
		return false
	var side := 1 if pr.y > 0.0 else -1
	var edge: float = data.left[i] if side > 0 else data.right[i]
	var top: float = data.height[i]
	if tunnel:
		edge = GlassTunnel._edge(track, i, side)
		top = GlassTunnel.HEIGHT
	var dy := pos.y - track.path.points[i].y
	return absf(pr.y) < edge + margin and dy < top + margin and dy > -below


## Ponto da seção na amostra i: t = 0 na base direita, 1 na esquerda; `inset` para dentro.
static func point(track: RaceTrack, data: Dictionary, i: int, t: float, inset := 0.0) -> Vector3:
	var p := track.path
	var l: float = data.left[i] - inset
	var r: float = data.right[i] - inset
	var half := (l + r) * 0.5
	var mid := (l - r) * 0.5
	var a := PI * t
	var c := cos(a)
	var x := mid - signf(c) * pow(absf(c), SHAPE) * half
	var y := pow(maxf(sin(a), 0.0), SHAPE) * (float(data.height[i]) - inset)
	return p.points[i] + p.lefts[i] * x + Vector3.UP * y


## Máscara (vista de cima) de onde o tubo atravessa a linha d'água — a seção dele na altura da água,
## na subida para o Portão e no mergulho de volta: ali a superfície do mar não é desenhada
## (sea_carve.gdshaderinc), senão o tubo pareceria alagado. [textura, área (x0, z0, x1, z1)] ou []
## se o tubo não chega à superfície.
static func surface_carve(track: RaceTrack) -> Array:
	var data := profile(track)
	var p := track.path
	var n := p.size()
	var water := track.layout.water_level
	# Amostra -> [ponto direito, ponto esquerdo] da seção na linha d'água
	var cuts := {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in n:
		if data.on[i] == 0:
			continue
		var top: float = float(data.height[i]) - CARVE_INSET
		var dy := water - p.points[i].y
		if dy < -0.5 or dy > top:
			continue
		# Superelipse: y = sen(a)^SHAPE × altura
		var a := asin(pow(clampf(dy / top, 0.0, 1.0), 1.0 / SHAPE))
		var r := point(track, data, i, a / PI, CARVE_INSET)
		var l := point(track, data, i, 1.0 - a / PI, CARVE_INSET)
		cuts[i] = [r, l]
		for v: Vector3 in [r, l]:
			lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.z))
			hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.z))
	if cuts.is_empty():
		return []
	lo -= Vector2.ONE * 4.0
	hi += Vector2.ONE * 4.0
	var w := int(ceil((hi.x - lo.x) / CARVE_TEXEL))
	var h := int(ceil((hi.y - lo.y) / CARVE_TEXEL))
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	var step := CARVE_TEXEL * 0.7
	# Preenche o quadrilátero entre a seção de cada amostra e a da seguinte
	for i: int in cuts:
		var j := (i + 1) % n
		if not cuts.has(j):
			continue
		var a0: Vector3 = cuts[i][0]
		var a1: Vector3 = cuts[i][1]
		var b0: Vector3 = cuts[j][0]
		var b1: Vector3 = cuts[j][1]
		var along := int(ceil(maxf(a0.distance_to(b0), a1.distance_to(b1)) / step)) + 1
		var across := int(ceil(maxf(a0.distance_to(a1), b0.distance_to(b1)) / step)) + 1
		for u in along + 1:
			var e0 := a0.lerp(b0, float(u) / along)
			var e1 := a1.lerp(b1, float(u) / along)
			for v in across + 1:
				var q := e0.lerp(e1, float(v) / across)
				var px := int((q.x - lo.x) / CARVE_TEXEL)
				var py := int((q.z - lo.y) / CARVE_TEXEL)
				if px >= 0 and py >= 0 and px < w and py < h:
					img.set_pixel(px, py, Color.WHITE)
	return [ImageTexture.create_from_image(img), Vector4(lo.x, lo.y, lo.x + w * CARVE_TEXEL, lo.y + h * CARVE_TEXEL)]


## Trecho do tubo (ou do túnel de cristal) perto de s, para as partículas da água não aparecerem
## dentro dele: 5 pontos da linha do meio da seção, de -CORRIDOR a +CORRIDOR m (xyz, meia-largura
## em w), e a altura do teto em cada um. [] onde a pista não está coberta.
static func corridor(track: RaceTrack, s: float) -> Array:
	var data := profile(track)
	var p := track.path
	var i0 := p.index_at(s)
	if data.on[i0] == 0 and not track.in_tunnel(i0):
		return []
	var pts := PackedVector4Array()
	var tops := PackedFloat32Array()
	for k in 5:
		var i := p.index_at(s + CORRIDOR * (k - 2) * 0.5)
		var l: float = data.left[i]
		var r: float = data.right[i]
		var h: float = data.height[i]
		if track.in_tunnel(i):
			l = GlassTunnel._edge(track, i, 1)
			r = GlassTunnel._edge(track, i, -1)
			h = GlassTunnel.HEIGHT
		elif data.on[i] == 0:
			# (ponta do tubo: depois dela não há o que esconder)
			l = 0.0
			r = 0.0
		var c := p.points[i] + p.lefts[i] * ((l - r) * 0.5)
		pts.append(Vector4(c.x, c.y, c.z, (l + r) * 0.5))
		tops.append(h)
	return [pts, tops]


static func build(track: RaceTrack, parent: Node3D) -> void:
	var data := profile(track)
	var p := track.path
	var n := p.size()
	var root := Node3D.new()
	root.name = "SeaTube"
	parent.add_child(root)
	# Trechos contínuos cobertos
	var runs := []
	var start := -1
	var first_off := -1
	for i in n:
		if data.on[i] == 0:
			first_off = i
			break
	if first_off < 0:
		runs.append([0, n - 1])
	else:
		for k in n + 1:
			var i := (first_off + k) % n
			var on: bool = data.on[i] == 1 and k < n
			if on and start < 0:
				start = i
			elif not on and start >= 0:
				runs.append([start, (i - 1 + n) % n])
				start = -1
	var glass_mat := TrackMaterials.sea_glass(RIB_SPACING, {"base_alpha": 0.03, "rim_alpha": 0.2, "glow": 0.22})
	var stone_mat := TrackMaterials.sea_stone("tube_end", false, {"panel_size": 1.5, "moss_amount": 0.6})
	var piece := 0
	for run: Array in runs:
		var a: int = run[0]
		var b: int = run[1]
		var count := (b - a + n) % n + 1
		var k := 0
		while k < count - 1:
			var stop := mini(k + CHUNK, count - 1)
			var glass := MeshBuilder.new()
			var metal := MeshBuilder.new()
			var lamps := MeshBuilder.new()
			var leds := MeshBuilder.new()
			var banners := MeshBuilder.new()
			for q in range(k, stop, 2):
				var i := (a + q) % n
				var j := (a + mini(q + 2, count - 1)) % n
				_slice(track, data, glass, metal, leds, i, j)
			# Nervuras a cada RIB_SPACING m (pelo índice da amostra, igual em todos os pedaços)
			var every := maxi(int(round(RIB_SPACING / p.spacing)), 1)
			for q in range(k, stop):
				var i := (a + q) % n
				if i % every == 0:
					# Estandarte do tridente numa nervura a cada BANNER_RIBS, lados alternados; medalhão na seguinte
					var r := i / every
					_rib(track, data, metal, lamps, leds, i, 0.7, 0.7, false, r % BANNER_RIBS == 1)
					if r % BANNER_RIBS == 0:
						_rib_banner(track, data, metal, banners, i, 1 if (r / BANNER_RIBS) % 2 == 0 else -1)
			var gmi := MeshInstance3D.new()
			gmi.name = "Glass%d" % piece
			gmi.mesh = glass.commit(null, glass_mat)
			gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gmi.visibility_range_end = VISIBILITY
			root.add_child(gmi)
			var fmi := MeshInstance3D.new()
			fmi.name = "Frame%d" % piece
			fmi.mesh = metal.commit(null, TrackMaterials.sea_bronze("sea_tube"))
			if not lamps.is_empty():
				lamps.commit(fmi.mesh as ArrayMesh, SkyDeck.glow(0.0, 1.8, 3.4))
			leds.commit(fmi.mesh as ArrayMesh, SkyDeck.glow(0.35, 1.6, 3.4))
			fmi.visibility_range_end = VISIBILITY
			root.add_child(fmi)
			if not banners.is_empty():
				var bmi := MeshInstance3D.new()
				bmi.name = "Banners%d" % piece
				bmi.mesh = banners.commit(null, AtlantisRuins.banner_material())
				bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				bmi.visibility_range_end = VISIBILITY
				root.add_child(bmi)
			k = stop
			piece += 1
		# Pontas: parede até o túnel de cristal ou portal de pedra onde a pista sai da água
		var ends := MeshBuilder.new()
		var end_leds := MeshBuilder.new()
		for end: int in [a, b]:
			var outside := (end - 1 + n) % n if end == a else (end + 1) % n
			if track.in_tunnel(outside):
				_tunnel_wall(track, data, ends, end_leds, end)
			_rib(track, data, ends, null, end_leds, end, 2.6, 2.2, true)
		var emi := MeshInstance3D.new()
		emi.name = "Ends%d" % piece
		emi.mesh = ends.commit(null, stone_mat)
		end_leds.commit(emi.mesh as ArrayMesh, SkyDeck.glow(0.0, 1.6, 3.4))
		emi.visibility_range_end = VISIBILITY
		root.add_child(emi)
		piece += 1


## Vidro e viga do topo entre as amostras i e j.
static func _slice(track: RaceTrack, data: Dictionary, glass: MeshBuilder, metal: MeshBuilder, leds: MeshBuilder, i: int, j: int) -> void:
	var p := track.path
	var s_i := p.s_at(i)
	var s_j := s_i + p.spacing * float((j - i + p.size()) % p.size())
	for n in ARC:
		var t0 := float(n) / ARC
		var t1 := float(n + 1) / ARC
		var a0 := point(track, data, i, t0)
		var a1 := point(track, data, i, t1)
		var b0 := point(track, data, j, t0)
		var b1 := point(track, data, j, t1)
		var center := p.points[i] + Vector3.UP * float(data.height[i]) * 0.4
		glass.quad(a0, b0, b1, a1, Color.WHITE, (center - (a0 + a1) * 0.5).normalized(),
			Vector2(s_i, t0), Vector2(s_j, t0), Vector2(s_j, t1), Vector2(s_i, t1))
	# Viga do topo (por fora) e a linha de luz dela (por dentro)
	var ti := point(track, data, i, 0.5, -0.3)
	var tj := point(track, data, j, 0.5, -0.3)
	var along := tj - ti
	if along.length() > 0.01:
		var z := along.normalized()
		var x := Vector3.UP.cross(z).normalized()
		metal.box(Transform3D(Basis(x, z.cross(x), z), (ti + tj) * 0.5), Vector3(0.8, 0.5, along.length() + 0.05), METAL * 0.85)
	var li := point(track, data, i, 0.5, 0.15)
	var lj := point(track, data, j, 0.5, 0.15)
	var w := p.lefts[i] * 0.15
	leds.quad(li - w, lj - w, lj + w, li + w, LED, Vector3.DOWN, Vector2(s_i, 0), Vector2(s_j, 0), Vector2(s_j, 1), Vector2(s_i, 1))


## Estandarte do tridente pendurado na nervura da amostra i, do lado `side`, de frente para quem
## chega: preso num braço de metal por dentro do tubo, por cima da faixa entre a barreira e o vidro
## (nunca sobre o asfalto).
static func _rib_banner(track: RaceTrack, data: Dictionary, metal: MeshBuilder, banners: MeshBuilder, i: int, side: int) -> void:
	var p := track.path
	var t := 0.17 if side < 0 else 0.83
	var at := point(track, data, i, t, 1.1)
	var lat := (at - p.points[i]).dot(p.lefts[i])
	if absf(lat) - 0.9 < p.half_width(i, side) + 1.5:
		return
	var tangent := p.tangents[i].normalized()
	metal.box(Transform3D(Basis(p.lefts[i], Vector3.UP, tangent).orthonormalized(), at + Vector3.UP * 0.1), Vector3(1.9, 0.12, 0.12), METAL)
	AtlantisRuins.add_banner(banners, at, p.lefts[i], -tangent, 1.6, minf(4.6, at.y - p.points[i].y - 3.0))


## Nervura (ou o portal de pedra, mais grosso) na amostra i: caixas ao longo da seção, luzes
## quentes perto da base e um friso ciano por dentro.
static func _rib(track: RaceTrack, data: Dictionary, mb: MeshBuilder, lamps: MeshBuilder, leds: MeshBuilder, i: int,
		thick: float, depth: float, portal: bool, medallion := false) -> void:
	var p := track.path
	var tangent := p.tangents[i].normalized()
	var prev := point(track, data, i, 0.0, -depth * 0.5)
	for n in ARC:
		var t1 := float(n + 1) / ARC
		var q := point(track, data, i, t1, -depth * 0.5)
		var y := (q - prev).normalized()
		var z := tangent.cross(y).normalized()
		var basis := Basis(tangent, y, z).orthonormalized()
		var length := prev.distance_to(q) + 0.05
		mb.box(Transform3D(basis, (prev + q) * 0.5), Vector3(thick, length, depth), STONE if portal else METAL)
		if not portal:
			# Perfil em I: aba larga por fora e uma mais fina por dentro, colada no vidro
			var t0 := float(n) / ARC
			var o0 := point(track, data, i, t0, -depth - 0.06)
			var o1 := point(track, data, i, t1, -depth - 0.06)
			mb.box(Transform3D(basis, (o0 + o1) * 0.5), Vector3(thick * 1.7, length, 0.12), METAL)
			var n0 := point(track, data, i, t0, 0.0)
			var n1 := point(track, data, i, t1, 0.0)
			mb.box(Transform3D(basis, (n0 + n1) * 0.5), Vector3(thick * 1.4, length, 0.05), METAL)
		prev = q
	if not portal:
		# Pilastras na base, com o capitel dourado
		for side: float in [0.0, 1.0]:
			var foot := point(track, data, i, side, -depth * 0.5)
			var top := point(track, data, i, absf(side - 0.08), -depth * 0.5)
			var up := (top - foot).normalized()
			var basis2 := Basis(tangent, up, tangent.cross(up).normalized()).orthonormalized()
			mb.box(Transform3D(basis2, (foot + top) * 0.5), Vector3(thick * 1.9, foot.distance_to(top), depth * 1.5), METAL)
			mb.box(Transform3D(basis2, top), Vector3(thick * 2.3, 0.32, depth * 1.9), GOLD)
			mb.box(Transform3D(basis2, foot + up * 0.2), Vector3(thick * 2.3, 0.4, depth * 1.9), METAL * 0.8)
		if medallion:
			_medallion(track, data, mb, i, tangent)
	if portal:
		for t: float in [0.0, 1.0]:
			var b := point(track, data, i, t, -depth * 0.5)
			mb.box(Transform3D(Basis(tangent, Vector3.UP, tangent.cross(Vector3.UP)).orthonormalized(), b + Vector3.UP * 0.8),
				Vector3(thick + 1.2, 1.6, depth + 1.2), STONE)
		# Friso de luz no portal, por dentro
		var a := point(track, data, i, 0.04, 0.1)
		for n in range(1, ARC):
			var b := point(track, data, i, float(n) / ARC * 0.92 + 0.04, 0.1)
			var y2 := (b - a).normalized()
			leds.box(Transform3D(Basis(tangent, y2, tangent.cross(y2)).orthonormalized(), (a + b) * 0.5), Vector3(0.3, a.distance_to(b), 0.06), LED)
			a = b
		return
	for t: float in [0.1, 0.9]:
		var c := point(track, data, i, t, 0.08)
		var y3 := (point(track, data, i, t + 0.01) - point(track, data, i, t - 0.01)).normalized()
		lamps.box(Transform3D(Basis(tangent, y3, tangent.cross(y3)).orthonormalized(), c), Vector3(thick * 0.6, 0.7, 0.06), LAMP)
	var a2 := point(track, data, i, 0.2, 0.05)
	for n in range(5, ARC - 4):
		var b2 := point(track, data, i, float(n + 1) / ARC, 0.05)
		var y4 := (b2 - a2).normalized()
		leds.box(Transform3D(Basis(tangent, y4, tangent.cross(y4)).orthonormalized(), (a2 + b2) * 0.5), Vector3(0.1, a2.distance_to(b2), 0.03), LED)
		a2 = b2


## Medalhão dourado com o tridente pendurado no alto da nervura i, virado para quem chega: disco de
## ouro com a borda de bronze, o tridente em relevo e a haste presa na viga do topo.
static func _medallion(track: RaceTrack, data: Dictionary, mb: MeshBuilder, i: int, tangent: Vector3) -> void:
	var p := track.path
	var top := point(track, data, i, 0.5, 0.0)
	var c := point(track, data, i, 0.5, 1.6)
	var down := (c - top).normalized()
	var side := p.lefts[i]
	# (eixo do disco ao longo da pista: a face aponta para quem vem)
	var disc := Basis(side, tangent, side.cross(tangent).normalized()).orthonormalized()
	mb.cylinder(Transform3D(disc, c - tangent * 0.06), 1.0, 1.0, 0.12, METAL, 18)
	mb.cylinder(Transform3D(disc, c - tangent * 0.1), 0.85, 0.85, 0.14, GOLD, 18)
	mb.cylinder(Transform3D(Basis(side, -down, side.cross(-down).normalized()).orthonormalized(), c - down * 0.95), 0.06, 0.06,
		top.distance_to(c) - 0.95, METAL, 6, false)
	# Tridente em relevo na face da frente (cabo, travessa e três pontas)
	var face := c - tangent * 0.13
	var up := -down
	var flat := Basis(side, up, -tangent).orthonormalized()
	mb.box(Transform3D(flat, face - up * 0.12), Vector3(0.1, 1.1, 0.06), METAL)
	mb.box(Transform3D(flat, face + up * 0.18), Vector3(0.62, 0.09, 0.06), METAL)
	for x: float in [-0.27, 0.0, 0.27]:
		mb.box(Transform3D(flat, face + up * (0.38 if x == 0.0 else 0.33) + side * x), Vector3(0.08, 0.36 if x == 0.0 else 0.28, 0.06), METAL)
		mb.box(Transform3D(flat.rotated(-tangent, PI * 0.25), face + up * (0.58 if x == 0.0 else 0.5) + side * x),
			Vector3(0.13, 0.13, 0.06), METAL)


## Parede de pedra entre a boca do tubo grande e a do túnel de cristal (na amostra i), com um friso
## de luz em volta da boca do túnel.
static func _tunnel_wall(track: RaceTrack, data: Dictionary, mb: MeshBuilder, leds: MeshBuilder, i: int) -> void:
	var p := track.path
	var normal := p.tangents[i].normalized()
	var steps := ARC
	for n in steps:
		var t0 := float(n) / steps
		var t1 := float(n + 1) / steps
		var o0 := point(track, data, i, t0)
		var o1 := point(track, data, i, t1)
		var i0 := GlassTunnel._arc(track, i, t0, -0.6)
		var i1 := GlassTunnel._arc(track, i, t1, -0.6)
		mb.quad(o0, o1, i1, i0, STONE, normal)
		mb.quad(o0, o1, i1, i0, STONE * 0.9, -normal)
		var l0 := GlassTunnel._arc(track, i, t0, -0.9)
		var l1 := GlassTunnel._arc(track, i, t1, -0.9)
		leds.quad(i0, i1, l1, l0, LED, normal)
		leds.quad(i0, i1, l1, l0, LED, -normal)
