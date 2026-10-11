extends SceneTree
## Skin do carro (CarSkin / CarSkinTemplate / car_paint), com janela (precisa renderizar):
## * planificação: face pela normal, pixel no retângulo certo, câmeras das vistas;
## * importar: tamanho, hash, arquivos, conferência dos bytes da rede, perfil limpa hash inválido;
## * ida e volta: molde → importado como skin → molde de novo dá a mesma imagem (o shader lê a
##   skin exatamente onde o molde mostra cada face);
## * pintar o lado esquerdo de magenta só muda o lado esquerdo — e não pinta o que fica escondido
##   atrás dele (o monocoque atrás do sidepod, o lado de dentro do outro sidepod: cada superfície
##   tem o seu lugar); pintar o quadro escondido não muda o visível.
##   godot --path . -s res://tests/skin_test.gd -- [pasta para salvar os moldes]
## Arquivos de teste: user://test_skins/ (apagada no fim).

const TEST_DIR := "user://test_skins"

var failures := 0
var out_dir := ""


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args()).filter(func(a: String) -> bool: return not a.begins_with("--"))
	if args.size() > 0:
		out_dir = args[0]
		DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _clean() -> void:
	var abs_dir := ProjectSettings.globalize_path(TEST_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		for f in DirAccess.get_files_at(abs_dir):
			DirAccess.remove_absolute(abs_dir.path_join(f))
		DirAccess.remove_absolute(abs_dir)


func _run() -> void:
	CarSkin.dir = TEST_DIR
	_clean()
	_mapping()
	_files()
	await _round_trip()
	_clean()
	print("\nskin_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)


func _mapping() -> void:
	print("Planificação")
	_check(CarSkin.face_of(Vector3(1, 0.2, 0.1)) == CarSkin.Face.LEFT and CarSkin.face_of(Vector3(-1, 0, 0)) == CarSkin.Face.RIGHT,
		"normal para +X = lado esquerdo, -X = direito")
	_check(CarSkin.face_of(Vector3(0.1, 1, 0)) == CarSkin.Face.TOP and CarSkin.face_of(Vector3(0, -1, 0.2)) == CarSkin.Face.BOTTOM,
		"cima e baixo")
	_check(CarSkin.face_of(Vector3(0, 0.1, 1)) == CarSkin.Face.FRONT and CarSkin.face_of(Vector3(0, 0, -1)) == CarSkin.Face.BACK, "frente e trás")
	# Bico (frente do carro) aparece à esquerda no lado esquerdo e à direita no lado direito e em cima
	var nose := Vector3(0, 0.3, 2.8)
	var l := CarSkin.pixel_of(nose, Vector3.RIGHT)
	var r := CarSkin.pixel_of(nose, Vector3.LEFT)
	var t := CarSkin.pixel_of(nose, Vector3.UP)
	_check(l.x < CarSkin.RECTS[0].get_center().x and r.x > CarSkin.RECTS[1].get_center().x and t.x > CarSkin.RECTS[2].get_center().x,
		"frente do carro: à esquerda no lado esquerdo, à direita no lado direito e em cima")
	_check(CarSkin.pixel_of(Vector3(0.9, 0.7, 0), Vector3.UP).y < CarSkin.pixel_of(Vector3(-0.9, 0.7, 0), Vector3.UP).y,
		"em cima, o lado esquerdo do carro fica na parte de cima da vista")
	var all_inside := true
	for layer in 2:
		for p in [CarSkin.BOX_MIN, CarSkin.BOX_MAX, Vector3(0, 0.5, 0)]:
			for n in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
				var f := CarSkin.face_of(n)
				all_inside = all_inside and Rect2(CarSkin.rect_of(f, layer)).grow(0.5).has_point(CarSkin.pixel_of(p, n, layer))
	_check(all_inside, "toda a caixa do carro cai dentro dos retângulos (visíveis e escondidos)")
	var rects := _all_rects()
	var overlap := false
	for i in rects.size():
		for j in rects.size():
			if i < j and Rect2i(rects[i]).grow(2).intersects(rects[j]):
				overlap = true
		_check(Rect2i(0, 0, CarSkin.SIZE, CarSkin.SIZE).encloses(rects[i]), "quadro %d dentro do molde" % i)
	_check(not overlap, "quadros não se sobrepõem (%d)" % rects.size())
	var aspect_ok := true
	for layer in 2:
		for f in CarSkin.ALL_FACES:
			var rr := CarSkin.rect_of(f, layer)
			var cam: Array = CarSkin.face_camera(f)
			var size := CarSkin.BOX_MAX - CarSkin.BOX_MIN
			var w := size.z if f in [0, 1, 2, 3] else size.x
			aspect_ok = aspect_ok and absf(float(rr.size.x) / rr.size.y - w / float(cam[3])) < 0.02
	_check(aspect_ok, "proporção de cada quadro igual à da vista")


## Os 11 quadros: 5 visíveis, 5 escondidos e o de baixo.
func _all_rects() -> Array:
	var out := []
	for f in CarSkin.VISIBLE_FACES:
		out.append(CarSkin.rect_of(f, 0))
	for f in CarSkin.ALL_FACES:
		out.append(CarSkin.rect_of(f, 1))
	return out


func _files() -> void:
	print("Arquivos")
	var img := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 0.5))
	var res := CarSkin.import_image(img)
	_check(res.get("ok", false), "importou")
	var h: String = res.get("hash", "")
	_check(CarSkin.valid_hash(h) and CarSkin.has_local(h), "hash válido e arquivos gravados")
	var bytes := CarSkin.net_bytes(h)
	_check(CarSkin.check_net_bytes(h, bytes), "bytes da rede conferem (%d KB)" % (bytes.size() / 1024))
	var bad := bytes.duplicate()
	bad[bad.size() / 2] ^= 0xff
	_check(not CarSkin.check_net_bytes(h, bad), "bytes alterados são recusados")
	_check(not CarSkin.check_net_bytes("ab" + h.substr(2), bytes), "hash errado é recusado")
	var tex := CarSkin.texture(h)
	_check(tex != null and tex.get_width() == CarSkin.SIZE, "textura cheia (versão de quem importou)")
	_check(CarSkin.own_skins().has(h), "aparece entre as skins do aparelho")
	var p := PlayerProfile.new()
	p.mode = "server"
	p.equipped = PlayerProfile.default_equipped()
	p.equipped["skin"] = "não é hash"
	p.clamp_equipped()
	_check(p.equipped["skin"] == "", "perfil limpa hash inválido")
	p.equipped["skin"] = h
	p.clamp_equipped()
	_check(p.equipped["skin"] == h, "perfil aceita hash válido")
	p.free()
	CarSkin.delete(h)
	_check(not CarSkin.has_local(h), "apagar a skin")


func _round_trip() -> void:
	print("Ida e volta pelo molde")
	var host := Node.new()
	root.add_child(host)
	var cfg := CarConfig.new()
	cfg.primary_color = Color("1f6feb")
	cfg.secondary_color = Color("ffd21f")
	cfg.accent_color = Color("e5303a")
	cfg.paint_scheme = 4
	var t0 := Time.get_ticks_msec()
	var layers := await CarSkinTemplate.render_layers(host, cfg)
	var tpl: Image = layers["template"]
	var lines: Image = layers["lines"]
	print("  molde e linhas em %d ms" % (Time.get_ticks_msec() - t0))
	# Linhas escuras das peças dentro dos quadros
	var inside := 0
	for r: Rect2i in _all_rects():
		for y in range(r.position.y, r.end.y, 2):
			for x in range(r.position.x, r.end.x, 2):
				var lc := lines.get_pixel(x, y)
				if lc.a > 0.5 and lc.r < 0.3:
					inside += 1
	_check(inside > 4000, "linhas das peças dentro das vistas (%d pontos)" % inside)
	if out_dir != "":
		lines.save_png(out_dir.path_join("molde_linhas.png"))
	_check(tpl.get_width() == CarSkin.SIZE, "molde 2048×2048")
	var cover := []
	for r: Rect2i in _all_rects():
		cover.append(_coverage(tpl, r))
	_check(cover.slice(0, 5).all(func(c: float) -> bool: return c > 0.08), "todas as vistas visíveis têm carro (%s)" % str(cover.map(func(c: float) -> String: return "%.0f%%" % (c * 100))))
	_check(cover.slice(5).all(func(c: float) -> bool: return c > 0.01), "os quadros escondidos e o de baixo têm superfícies")
	if out_dir != "":
		tpl.save_png(out_dir.path_join("molde.png"))
	# Importa o molde sem mexer e gera de novo: tem que dar a mesma coisa
	var res := CarSkin.import_image(tpl)
	cfg.skin = res["hash"]
	var tpl2 := await CarSkinTemplate.render(host, cfg)
	var diff := _diff(tpl, tpl2)
	_check(diff.x < 0.02 and diff.y < 0.01, "molde com a própria skin igual ao original (diferença média %.3f, %.2f%% dos pixels)" % [diff.x, diff.y * 100])
	# Lado esquerdo pintado de magenta
	var painted := tpl.duplicate() as Image
	var left: Rect2i = CarSkin.RECTS[CarSkin.Face.LEFT]
	painted.fill_rect(left, Color(1, 0, 1))
	cfg.skin = CarSkin.import_image(painted)["hash"]
	var tpl3 := await CarSkinTemplate.render(host, cfg)
	if out_dir != "":
		tpl3.save_png(out_dir.path_join("molde_magenta.png"))
	_check(_magenta(tpl3, left) > 0.95, "lado esquerdo virou magenta (%.0f%%)" % (_magenta(tpl3, left) * 100))
	_check(_magenta(tpl3, CarSkin.RECTS[CarSkin.Face.RIGHT]) < 0.01 and _magenta(tpl3, CarSkin.RECTS[CarSkin.Face.TOP]) < 0.01,
		"lado direito e cima continuam sem magenta")
	var hidden_left := CarSkin.rect_of(CarSkin.Face.LEFT, 1)
	_check(_magenta(tpl3, hidden_left) < 0.01, "o que fica escondido atrás do lado esquerdo não pegou o magenta (%.1f%%)" % (_magenta(tpl3, hidden_left) * 100))
	# Quadro escondido pintado de magenta: muda as superfícies escondidas, não o lado visível
	var painted2 := tpl.duplicate() as Image
	painted2.fill_rect(hidden_left, Color(1, 0, 1))
	cfg.skin = CarSkin.import_image(painted2)["hash"]
	var tpl4 := await CarSkinTemplate.render(host, cfg)
	_check(_magenta(tpl4, hidden_left) > 0.9, "quadro escondido pintado (%.0f%%)" % (_magenta(tpl4, hidden_left) * 100))
	_check(_magenta(tpl4, left) < 0.01, "o lado esquerdo visível continua sem magenta (%.1f%%)" % (_magenta(tpl4, left) * 100))
	host.queue_free()


func _coverage(img: Image, r: Rect2i) -> float:
	var n := 0
	var total := 0
	for y in range(r.position.y, r.end.y, 4):
		for x in range(r.position.x, r.end.x, 4):
			total += 1
			if img.get_pixel(x, y).a > 0.5:
				n += 1
	return float(n) / maxf(total, 1)


## Diferença média de cor nos pixels do carro e fração de pixels com diferença grande.
func _diff(a: Image, b: Image) -> Vector2:
	var sum := 0.0
	var big := 0
	var n := 0
	for r: Rect2i in _all_rects():
		for y in range(r.position.y, r.end.y, 3):
			for x in range(r.position.x, r.end.x, 3):
				var ca := a.get_pixel(x, y)
				if ca.a < 0.5:
					continue
				var cb := b.get_pixel(x, y)
				var d := (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
				sum += d
				n += 1
				if d > 0.15:
					big += 1
	return Vector2(sum / maxf(n, 1), float(big) / maxf(n, 1))


func _magenta(img: Image, r: Rect2i) -> float:
	var n := 0
	var m := 0
	for y in range(r.position.y, r.end.y, 3):
		for x in range(r.position.x, r.end.x, 3):
			var c := img.get_pixel(x, y)
			if c.a < 0.5 or Vector3(c.r - CarSkinTemplate.OUTLINE.r, c.g - CarSkinTemplate.OUTLINE.g, c.b - CarSkinTemplate.OUTLINE.b).length() < 0.03:
				continue
			n += 1
			if c.r > 0.85 and c.b > 0.85 and c.g < 0.15:
				m += 1
	return float(m) / maxf(n, 1)
