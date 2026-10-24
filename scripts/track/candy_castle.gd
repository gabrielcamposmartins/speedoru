class_name CandyCastle
extends RefCounted
## O Castelo de Algodão-Doce da Rainbow Raceway (na ilha "castle" do CloudIslands, de frente para a
## reta principal) e a Torre de Algodão-Doce no meio da espiral (ilha "tower").
##
## Castelo: base em degraus, muralha de oito lados com ameias e glacê escorrendo, oito torres nos
## cantos com telhado cônico e bandeira, a torre principal com a janela de coração e a varanda, quatro
## torres altas em volta dela e duas agulhas atrás, o portão com a ponte levadiça e o coração em cima,
## janelas em arco (acesas à noite) e um arco-íris sólido por trás de tudo.
## Torre: forminha de cupcake e uma espiral de sorvete/algodão-doce subindo e afinando, listrada de
## rosa, branco, menta e lilás, com uma cereja e um coração no topo.

const WALL := Color(1.0, 0.62, 0.8)
const WALL_DARK := Color(0.96, 0.5, 0.72)
const TRIM := Color(1.0, 0.96, 0.92)
const ROOFS := [Color(0.72, 0.5, 1.0), Color(1.0, 0.38, 0.66), Color(0.5, 0.72, 1.0)]
const GOLD := Color(1.0, 0.82, 0.32)
const WINDOW := Color(1.0, 0.86, 0.5)
const DOOR := Color(0.55, 0.32, 0.4)
const WOOD := Color(0.8, 0.56, 0.42)


static func build(track: RaceTrack, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "CandyCastle"
	parent.add_child(root)
	var lm := CloudIslands.landmark(track, "castle")
	var center: Vector3 = lm.pos
	center.y = CloudIslands.top_y(lm.pos, lm.radius, 0.0) - 0.2
	# De frente para a largada
	var to_start := track.path.position_at(-80.0) - center
	to_start.y = 0.0
	var front := to_start.normalized()
	var mb := MeshBuilder.new()
	var glow := MeshBuilder.new()
	var cloth := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1717
	var xf := Transform3D(Basis(Vector3.UP.cross(front).normalized(), Vector3.UP, front), center)
	_castle(mb, glow, cloth, xf, rng)
	var mesh := mb.commit(null, CandyDecor.material())
	TrackFlags.commit_to(cloth, mesh)
	var castle := CloudLook.add_mesh(root, "Castle", mesh)
	castle.extra_cull_margin = 10.0
	CloudLook.add_mesh(root, "CastleWindows", glow.commit(null, CloudLook.glow(0.5, 3.2)))
	root.set_meta("castle", center)
	root.set_meta("front", front)
	_tower_of_sweets(track, root)


# ---------------------------------------------------------------------------
# Castelo (coordenadas locais: +Z = frente, +X = esquerda de quem olha da frente, y = 0 no chão)
# ---------------------------------------------------------------------------
static func _castle(mb: MeshBuilder, glow: MeshBuilder, cloth: MeshBuilder, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	# Base em degraus
	mb.lathe(xf, PackedVector2Array([Vector2(37.0, -1.0), Vector2(37.0, 1.2), Vector2(34.0, 1.3), Vector2(34.0, 2.6), Vector2(0.0, 2.7)]), TRIM, 40)
	var floor_y := 2.6
	# Muralha de oito lados com torres nos cantos
	var wall_r := 26.0
	var corners: Array[Vector3] = []
	for k in 8:
		var a := TAU * (k + 0.5) / 8.0
		corners.append(Vector3(sin(a) * wall_r, floor_y, cos(a) * wall_r))
	for k in 8:
		var a := corners[k]
		var b := corners[(k + 1) % 8]
		# O lado da frente (entre os cantos 7 e 0) tem o portão
		var gate := k == 7
		_wall(mb, glow, xf, a, b, 13.0, 2.4, gate)
	for k in 8:
		var c := corners[k]
		_tower(mb, glow, cloth, xf, c, 4.4, 21.0, 9.5, ROOFS[k % 2], rng, 2)
	# Torre principal com varanda e janela de coração
	var keep := Vector3(0, floor_y, -2.0)
	_tower(mb, glow, cloth, xf, keep, 11.0, 31.0, 17.0, ROOFS[1], rng, 3, 16.0)
	var heart_at := keep + Vector3(0, 21.0, 11.2)
	_slab_local(mb, CloudLook.heart(7.4), xf, heart_at, 0.6, TRIM)
	_slab_local(glow, CloudLook.heart(5.6), xf, heart_at + Vector3(0, 0, 0.35), 0.3, Color(1.0, 0.45, 0.7))
	# Varanda redonda
	mb.lathe(Transform3D(xf.basis, xf * (keep + Vector3.UP * 14.0)), PackedVector2Array([Vector2(11.0, 0.0), Vector2(13.6, 0.6),
		Vector2(13.6, 1.2), Vector2(11.0, 1.3)]), TRIM, 32)
	for k in 28:
		var a := TAU * k / 28.0
		var pos := keep + Vector3(sin(a) * 13.2, 15.2, cos(a) * 13.2)
		mb.cylinder(xf * Transform3D(Basis(), pos), 0.18, 0.18, 1.3, TRIM, 6, false)
	mb.lathe(Transform3D(xf.basis, xf * (keep + Vector3.UP * 16.4)), PackedVector2Array([Vector2(13.0, 0.0), Vector2(13.6, 0.0),
		Vector2(13.6, 0.35), Vector2(13.0, 0.35)]), TRIM, 32)
	# Quatro torres altas em volta da torre principal e duas agulhas atrás
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var pos := keep + Vector3(sin(a) * 14.5, 0.0, cos(a) * 14.5)
		_tower(mb, glow, cloth, xf, pos, 4.0, 38.0, 14.0, ROOFS[0] if k % 2 == 0 else ROOFS[2], rng, 3)
	for side: float in [-1.0, 1.0]:
		var pos := keep + Vector3(side * 7.5, 0.0, -9.0)
		_tower(mb, glow, cloth, xf, pos, 3.2, 48.0, 17.0, ROOFS[1], rng, 4)
	# Portão: arco escuro, a ponte levadiça baixada e o coração em cima
	var gate_c := (corners[7] + corners[0]) * 0.5
	var gate_poly := PackedVector2Array()
	for k in 11:
		var a := PI * k / 10.0
		gate_poly.append(Vector2(cos(a) * 3.2, 6.0 + sin(a) * 3.2))
	gate_poly.append(Vector2(-3.2, 0.0))
	gate_poly.append(Vector2(3.2, 0.0))
	_slab_local(mb, gate_poly, xf, gate_c + Vector3(0, 0, 1.25), 0.2, DOOR)
	var arch := PackedVector2Array()
	for k in 11:
		var a := PI * k / 10.0
		arch.append(Vector2(cos(a) * 4.0, 6.0 + sin(a) * 4.0))
	arch.append(Vector2(-4.0, 0.0))
	arch.append(Vector2(4.0, 0.0))
	_slab_local(mb, arch, xf, gate_c + Vector3(0, 0, 1.2), 0.15, TRIM)
	# Ponte levadiça: pranchas descendo até o chão na frente
	var bridge_basis := Basis(Vector3.RIGHT, -0.22)
	for k in 7:
		var x := (k - 3) * 0.9
		mb.box(xf * Transform3D(bridge_basis, gate_c + Vector3(x, 0.9, 6.6)), Vector3(0.85, 0.3, 11.0), WOOD * (0.94 + 0.06 * (k % 2)))
	for side: float in [-1.0, 1.0]:
		# Correntes (cordões finos)
		var top := xf * (gate_c + Vector3(side * 3.6, 9.5, 1.4))
		var low := xf * (gate_c + Vector3(side * 3.0, 2.0, 11.5))
		var dir := (low - top).normalized()
		var x_axis := dir.cross(xf.basis.x).normalized()
		mb.cylinder(Transform3D(Basis(x_axis, dir, x_axis.cross(dir)).orthonormalized(), top), 0.1, 0.1, top.distance_to(low), Color(0.8, 0.8, 0.86), 5, false)
	_slab_local(mb, CloudLook.heart(4.2), xf, gate_c + Vector3(0, 12.0, 1.5), 0.5, Color(1.0, 0.3, 0.62))
	# Arco-íris sólido por trás
	CandyDecor.rainbow_arch(mb, xf * Transform3D(Basis(), Vector3(0, floor_y - 3.0, -30.0)), 72.0, 4.6, 3.2, 40)
	# Nuvens nos pés do arco-íris
	for side: float in [-1.0, 1.0]:
		for k in 4:
			var pos := Vector3(side * (60.0 + k * 3.0), floor_y - 1.0 + rng.randf_range(-1.0, 2.0), -30.0 + rng.randf_range(-4.0, 4.0))
			mb.blob(xf * pos, Vector3(6.0, 4.5, 6.0) * rng.randf_range(0.8, 1.2), Color.WHITE, 12, 8, 0.25)


## Peça com volume de um polígono no plano XY local do castelo, em `at` (local), olhando para +Z.
static func _slab_local(mb: MeshBuilder, poly: PackedVector2Array, xf: Transform3D, at: Vector3, depth: float, color: Color) -> void:
	CloudLook.slab(mb, poly, Transform3D(xf.basis, xf * at), depth, color)


## Trecho de muralha de a até b (local, no chão): parede com faixa de friso, glacê escorrendo e ameias
## no alto. Com `gate`, uma abertura no meio (o arco do portão é desenhado à parte).
static func _wall(mb: MeshBuilder, glow: MeshBuilder, xf: Transform3D, a: Vector3, b: Vector3, h: float, thick: float, gate: bool) -> void:
	var along := (b - a)
	var length := along.length()
	var dir := along / length
	var out := Vector3(dir.z, 0, -dir.x)
	if out.dot((a + b) * 0.5) < 0.0:
		out = -out
	var basis := Basis(dir, Vector3.UP, out)
	var mid := (a + b) * 0.5
	var pieces: Array = [[0.0, length]]
	if gate:
		pieces = [[0.0, length * 0.5 - 4.0], [length * 0.5 + 4.0, length]]
	for piece: Array in pieces:
		var t0: float = piece[0]
		var t1: float = piece[1]
		var c := a + dir * ((t0 + t1) * 0.5)
		mb.box(xf * Transform3D(basis, c + Vector3.UP * h * 0.5), Vector3(t1 - t0, h, thick), WALL)
		mb.box(xf * Transform3D(basis, c + Vector3.UP * (h * 0.35)), Vector3(t1 - t0 + 0.05, 0.6, thick + 0.3), TRIM)
	if gate:
		# Por cima do portão
		mb.box(xf * Transform3D(basis, mid + Vector3.UP * (h - 1.5)), Vector3(8.0, 3.0, thick), WALL)
	# Topo: faixa de glacê com gotas escorrendo e as ameias
	mb.box(xf * Transform3D(basis, mid + Vector3.UP * (h + 0.3)), Vector3(length + 0.4, 0.6, thick + 0.6), TRIM)
	var drips := int(length / 1.1)
	for k in drips:
		var t := (k + 0.5) / drips
		var pos := a + dir * (t * length) + out * (thick * 0.5 + 0.1) + Vector3.UP * (h - 0.25 - 0.35 * (k % 3) * 0.5)
		mb.blob(xf * pos, Vector3(0.42, 0.75 + 0.3 * (k % 3), 0.42), TRIM, 8, 5)
	var merlons := int(length / 2.4)
	for k in merlons:
		var t := (k + 0.5) / merlons
		mb.box(xf * Transform3D(basis, a + dir * (t * length) + Vector3.UP * (h + 1.3)), Vector3(1.3, 1.6, thick), WALL_DARK)
	# Janelinhas acesas na muralha
	for k in 2:
		var t := 0.25 + 0.5 * k
		if gate and absf(t - 0.5) < 0.2:
			continue
		var pos := a + dir * (t * length) + out * (thick * 0.5 + 0.06) + Vector3.UP * (h * 0.62)
		CloudLook.slab(glow, _arch_window(0.8, 1.6), Transform3D(xf.basis * basis, xf * pos), 0.1, WINDOW)


## Contorno de janela em arco (largura `w`, altura `h` até o topo do arco), base em y = -h/2.
static func _arch_window(w: float, h: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r := w * 0.5
	for k in 9:
		var a := PI * k / 8.0
		out.append(Vector2(cos(a) * r, h * 0.5 - r + sin(a) * r))
	out.append(Vector2(-r, -h * 0.5))
	out.append(Vector2(r, -h * 0.5))
	return out


## Torre redonda (base `at` local, raio, altura do corpo, altura do telhado): corpo com frisos, coroa
## mais larga com glacê escorrendo, telhado cônico de bruxa, bola dourada e bandeira; janelas em arco
## acesas em `rows` alturas. `slim` > 0: telhado começa mais estreito (torre principal).
static func _tower(mb: MeshBuilder, glow: MeshBuilder, cloth: MeshBuilder, xf: Transform3D, at: Vector3, r: float, h: float,
		roof_h: float, roof: Color, rng: RandomNumberGenerator, rows: int, slim := 0.0) -> void:
	var base := Transform3D(xf.basis, xf * at)
	var sides := 24 if r > 6.0 else 16
	mb.lathe(base, PackedVector2Array([Vector2(r * 1.08, 0.0), Vector2(r, 0.8), Vector2(r, h - 1.6), Vector2(r * 1.16, h - 0.9),
		Vector2(r * 1.16, h), Vector2(0.0, h)]), WALL, sides)
	for y: float in [h * 0.33, h * 0.66]:
		mb.lathe(Transform3D(base.basis, base * Vector3(0, y, 0)), PackedVector2Array([Vector2(r * 1.03, 0.0), Vector2(r * 1.03, 0.5),
			Vector2(0.0, 0.5)]), TRIM, sides)
	# Glacê escorrendo sob a coroa
	var drips := maxi(int(TAU * r * 1.16 / 1.0), 10)
	for k in drips:
		var a := TAU * k / drips
		var drip := 0.6 + 0.45 * float((k * 7) % 3)
		mb.blob(base * Vector3(cos(a) * r * 1.13, h - 1.0 - drip * 0.5, sin(a) * r * 1.13), Vector3(0.38, drip, 0.38), TRIM, 7, 4)
	# Telhado de bruxa (um pouco côncavo) com a aba
	var prof := PackedVector2Array()
	var rr := r * 1.32 if slim <= 0.0 else r * 1.2
	prof.append(Vector2(rr, 0.0))
	for k in range(1, 10):
		var t := k / 9.0
		prof.append(Vector2(rr * pow(1.0 - t, 1.5) * (1.0 - 0.15 * sin(t * PI)), roof_h * t))
	mb.lathe(Transform3D(base.basis, base * Vector3(0, h - 0.1, 0)), prof, roof, sides)
	# Faixa dourada na aba e a bola na ponta
	mb.lathe(Transform3D(base.basis, base * Vector3(0, h - 0.15, 0)), PackedVector2Array([Vector2(rr + 0.05, 0.0), Vector2(rr * 0.92, 0.6),
		Vector2(0.0, 0.62)]), GOLD, sides)
	var tip := base * Vector3(0, h + roof_h, 0)
	mb.blob(tip + Vector3.UP * 0.35, Vector3.ONE * maxf(r * 0.12, 0.45), GOLD, 10, 6)
	TrackFlags.flagpole(mb, cloth, tip + Vector3.UP * 0.6, 3.6, Vector2(2.6, 1.5), [CloudLook.HOT_PINK, Color.WHITE, CloudLook.LILAC], 1)
	# Janelas
	for q in rows:
		var y := h * (0.25 + 0.6 * (q + 0.5) / rows)
		var n := 3 if r < 6.0 else 6
		var off := rng.randf() * TAU
		for k in n:
			var a := off + TAU * k / n
			var dir := Vector3(sin(a), 0.0, cos(a))
			var wb := xf.basis * Basis(Vector3.UP, a)
			var wpos := xf * (at + dir * (r + 0.05) + Vector3.UP * y)
			CloudLook.slab(mb, _arch_window(1.5, 2.6), Transform3D(wb, wpos), 0.12, TRIM)
			CloudLook.slab(glow, _arch_window(1.1, 2.1), Transform3D(wb, wpos + wb.z * 0.08), 0.06, WINDOW)


# ---------------------------------------------------------------------------
# Torre de Algodão-Doce (meio da espiral)
# ---------------------------------------------------------------------------
static func _tower_of_sweets(track: RaceTrack, root: Node3D) -> void:
	var lm := CloudIslands.landmark(track, "tower")
	var base: Vector3 = lm.pos
	base.y = CloudIslands.top_y(lm.pos, lm.radius, 0.0) - 0.2
	var mb := MeshBuilder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2828
	# Forminha listrada e a borda de glacê
	var r0 := 13.0
	var cup_h := 12.0
	var sides := 32
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var col := CloudLook.BABY_BLUE if k % 2 == 0 else Color.WHITE
		mb.quad(base + d0 * r0 * 0.8, base + d1 * r0 * 0.8, base + d1 * r0 + Vector3.UP * cup_h, base + d0 * r0 + Vector3.UP * cup_h, col, d0 + d1)
	# Espiral: um tubo grosso subindo em hélice, afinando, listrado
	var turns := 5.0
	var steps := 220
	var h0 := cup_h + 2.0
	var h1 := 66.0
	var stripes := [CloudLook.PINK, Color.WHITE, CloudLook.MINT, CloudLook.LILAC, Color.WHITE, CloudLook.BUTTER]
	var ring := 14
	var prev: Array[Vector3] = []
	for k in steps + 1:
		var t := float(k) / steps
		var ang := TAU * turns * t
		var helix_r := lerpf(r0 * 0.78, 0.6, pow(t, 0.85))
		var tube_r := lerpf(5.2, 1.0, t)
		var c := base + Vector3(cos(ang) * helix_r, lerpf(h0, h1, t), sin(ang) * helix_r)
		var tangent := Vector3(-sin(ang) * helix_r * TAU * turns, h1 - h0, cos(ang) * helix_r * TAU * turns).normalized()
		var radial := Vector3(cos(ang), 0, sin(ang))
		var n1 := radial
		var n2 := tangent.cross(n1).normalized()
		var row: Array[Vector3] = []
		for q in ring:
			var b := TAU * q / ring
			row.append(c + (n1 * cos(b) + n2 * sin(b)) * tube_r)
		if not prev.is_empty():
			var col: Color = stripes[int(t * turns * 4.0) % stripes.size()]
			for q in ring:
				var q1 := (q + 1) % ring
				var nrm := (row[q] + row[q1]) * 0.5 - c
				mb.quad(prev[q], prev[q1], row[q1], row[q], col, nrm)
		prev = row
	# Miolo (para não ver o vão da hélice) e o topo: cereja e coração
	mb.lathe(Transform3D(Basis(), base + Vector3.UP * h0), PackedVector2Array([Vector2(r0 * 0.7, 0.0), Vector2(1.0, h1 - h0),
		Vector2(0.0, h1 - h0 + 0.5)]), Color.WHITE, 24)
	var top := base + Vector3.UP * (h1 + 2.0)
	mb.blob(top, Vector3.ONE * 2.6, Color(0.95, 0.12, 0.32), 14, 10)
	mb.cylinder(Transform3D(Basis(Vector3.FORWARD, 0.4), top + Vector3.UP * 2.0), 0.25, 0.15, 3.5, Color(0.35, 0.65, 0.35), 6, false)
	var face := track.path.position_at(2300.0) - base
	face.y = 0.0
	var hb := Basis(Vector3.UP.cross(face.normalized()).normalized(), Vector3.UP, face.normalized())
	CloudLook.slab(mb, CloudLook.heart(6.0), Transform3D(hb, top + Vector3.UP * 7.5), 1.0, CloudLook.HOT_PINK)
	# Granulado na forminha
	for k in 80:
		var a := rng.randf() * TAU
		var y := rng.randf_range(h0, h0 + 12.0)
		var pos := base + Vector3(cos(a) * (r0 * 0.85), y, sin(a) * (r0 * 0.85))
		mb.box(Transform3D(Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU), pos),
			Vector3(0.25, 0.25, 1.1), CloudLook.pick(rng, CloudLook.RAINBOW))
	var mi := CloudLook.add_mesh(root, "SweetsTower", mb.commit(null, CandyDecor.material()))
	mi.set_meta("top", top)
