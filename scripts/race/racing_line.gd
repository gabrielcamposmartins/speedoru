class_name RacingLine
extends RefCounted
## Linha de corrida e perfil de velocidade usados pelos bots.
##
## * Linha: o CSV de linha de curvatura mínima (TUMFTM) projetado na TrackPath, guardado como
##   deslocamento lateral por amostra da pista (sem CSV, usa uma linha "fora-dentro-fora" gerada
##   pela curvatura). Limitada para o carro inteiro ficar dentro da pista.
## * Velocidade: limite de curva pela aderência lateral (que cresce com a downforce, v²),
##   depois passadas para trás (frenagem) e para frente (aceleração), em volta fechada.
##   `grip_scale`/`brake_scale` diminuem a agressividade (dificuldade dos bots).

const G := 9.81
## Aderência lateral do carro: a = (A0 + C·v²)·g (medido no drive_test: 2,2 g a 120 km/h,
## 3,3 g a 220 km/h).
const LAT_A0 := 1.75
const LAT_C := 0.000406
const TOP_SPEED := 94.0
## Margem de cada lado entre o centro do carro e a borda da pista (m).
const EDGE_MARGIN := 1.3

var path: TrackPath
var margin := EDGE_MARGIN
var lateral := PackedFloat32Array()
var positions := PackedVector3Array()
var curvature := PackedFloat32Array()


static func build(track: RaceTrack, csv_path: String) -> RacingLine:
	var line := RacingLine.new()
	line.path = track.path
	line.margin = track.layout.line_margin if track.layout else EDGE_MARGIN
	line._compute_lateral(csv_path)
	line._compute_geometry()
	return line


## Velocidade alvo (m/s) por amostra para uma dada agressividade.
func speed_profile(grip_scale: float, brake_scale: float, accel_scale := 1.0) -> PackedFloat32Array:
	var n := path.size()
	var v := PackedFloat32Array()
	v.resize(n)
	var ds := path.spacing
	# Rampa (fração) entre i e i+1 e curvatura vertical (1/m, + = vale): pistas com relevo
	var grade := PackedFloat32Array()
	var vert := PackedFloat32Array()
	grade.resize(n)
	vert.resize(n)
	for i in n:
		grade[i] = (path.points[(i + 1) % n].y - path.points[i].y) / ds
		var h := 4
		vert[i] = (path.points[(i + h) % n].y - 2.0 * path.points[i].y + path.points[(i - h + n) % n].y) / (h * h * ds * ds)
	for i in n:
		var k := absf(curvature[i])
		var denom := k - LAT_C * G * grip_scale
		v[i] = TOP_SPEED if denom <= 1e-5 else minf(sqrt(LAT_A0 * G * grip_scale / denom), TOP_SPEED)
		# Na lombada o carro fica leve (menos aderência); no vale, mais
		if vert[i] != 0.0 and v[i] < TOP_SPEED:
			var load := clampf(1.0 + vert[i] * v[i] * v[i] / G, 0.55, 1.2)
			v[i] *= sqrt(load)
	# Frenagem (para trás) e aceleração (para frente), duas voltas para fechar o laço. Na descida
	# a gravidade tira frenagem e dá aceleração (e o contrário na subida).
	for pass_i in 2:
		for k in range(n - 1, -1, -1):
			var i := k
			var j := (i + 1) % n
			var a_brake := (1.9 + 0.00028 * v[j] * v[j]) * G * brake_scale + G * grade[i]
			v[i] = minf(v[i], sqrt(v[j] * v[j] + 2.0 * maxf(a_brake, 1.0) * ds))
	for pass_i in 2:
		for i in n:
			var j := (i + 1) % n
			var a_acc := minf(1.25 * G, 760000.0 * accel_scale / (800.0 * maxf(v[i], 5.0))) - 0.00055 * v[i] * v[i] - G * grade[i]
			v[j] = minf(v[j], sqrt(v[i] * v[i] + 2.0 * maxf(a_acc, 0.2) * ds))
	return v


func position_at(s: float, extra_lateral := 0.0) -> Vector3:
	return path.position_at(s, lateral_at(s) + extra_lateral)


func lateral_at(s: float) -> float:
	var f := fposmod(s, path.length) / path.spacing
	var i := int(floor(f))
	var n := path.size()
	return lerpf(lateral[i % n], lateral[(i + 1) % n], f - i)


static func sample(arr: PackedFloat32Array, path: TrackPath, s: float) -> float:
	var f := fposmod(s, path.length) / path.spacing
	var i := int(floor(f))
	var n := arr.size()
	return lerpf(arr[i % n], arr[(i + 1) % n], f - i)


func _compute_lateral(csv_path: String) -> void:
	var n := path.size()
	lateral.resize(n)
	lateral.fill(INF)
	var points := _load_csv(csv_path)
	if points.size() > 10:
		# Projeta cada ponto da linha e interpola nos índices da pista
		var proj: Array[Vector2] = []
		for pt in points:
			proj.append(path.project(pt))
		proj.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var m := proj.size()
		var j := 0
		for i in n:
			var s := path.s_at(i)
			while j < m - 1 and proj[j + 1].x < s:
				j += 1
			var a := proj[j]
			var b := proj[(j + 1) % m]
			var sb := b.x if b.x >= a.x else b.x + path.length
			var t := clampf((s - a.x) / maxf(sb - a.x, 0.01), 0.0, 1.0) if s >= a.x else 0.0
			lateral[i] = lerpf(a.y, b.y, t)
	else:
		# Sem CSV: fora-dentro-fora pela curvatura suavizada
		for i in n:
			var k := 0.0
			for d in range(-25, 26):
				k += path.curvature[(i + d + n) % n]
			lateral[i] = -signf(k) * minf(absf(k) * 120.0, 1.0) * 4.0
	# Suaviza e limita à largura útil
	for pass_i in 3:
		var smoothed := lateral.duplicate()
		for i in n:
			smoothed[i] = (lateral[(i - 2 + n) % n] + lateral[(i - 1 + n) % n] + lateral[i] * 2.0
				+ lateral[(i + 1) % n] + lateral[(i + 2) % n]) / 6.0
		lateral = smoothed
	for i in n:
		lateral[i] = clampf(lateral[i], -path.width_right[i] + margin, path.width_left[i] - margin)


func _compute_geometry() -> void:
	var n := path.size()
	positions.resize(n)
	curvature.resize(n)
	for i in n:
		positions[i] = path.points[i] + path.lefts[i] * lateral[i]
	for i in n:
		# Curvatura pelo círculo que passa por 3 pontos (±4 amostras)
		var a := positions[(i - 4 + n) % n]
		var b := positions[i]
		var c := positions[(i + 4) % n]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var bc := Vector2(c.x - b.x, c.z - b.z)
		var ac := Vector2(c.x - a.x, c.z - a.z)
		var cross := ab.x * bc.y - ab.y * bc.x
		var denom := ab.length() * bc.length() * ac.length()
		curvature[i] = 2.0 * cross / denom if denom > 1e-6 else 0.0


func _load_csv(csv_path: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	if csv_path.is_empty() or not FileAccess.file_exists(csv_path):
		return out
	var file := FileAccess.open(csv_path, FileAccess.READ)
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var v := line.split_floats(",")
		if v.size() >= 2:
			out.append(Vector3(v[0], 0.0, -v[1]))
	return out
