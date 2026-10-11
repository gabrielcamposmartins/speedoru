extends SceneTree
## Equipamento (decalques, skin, engenharia) salvo no banco e mantido entre conexões (sem janela; servidor
## hospedado com banco local):
## * configurado online (decalque e skin) → gravado no banco e também no aparelho;
## * offline o carro é o mesmo;
## * aparelho com um carro mais velho (jogo antigo) não apaga o do banco ao conectar;
## * mudança feita offline depois (mais nova) vale no servidor ao conectar;
## * reiniciar o servidor mantém tudo (veio do banco).
##   godot --headless --path . -s res://tests/equip_persist_test.gd -- --offline
## Arquivos de teste: user://test_equip_* (apagados no fim).

const PORT := 7366
const DIR := "user://test_equip_host"
const SKINS := "user://test_equip_skins"

var failures := 0
var host: LocalHost
var net: Node
var profile: PlayerProfile


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await create_timer(0.05).timeout
		t += 0.05
	return cond.call()


func _clean() -> void:
	for d in [DIR.path_join("skins"), DIR, SKINS]:
		var abs_dir := ProjectSettings.globalize_path(d)
		if DirAccess.dir_exists_absolute(abs_dir):
			for f in DirAccess.get_files_at(abs_dir):
				DirAccess.remove_absolute(abs_dir.path_join(f))
			DirAccess.remove_absolute(abs_dir)
	for f in ["user://test_equip_account.cfg", "user://test_equip_profile.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## Equipamento da (única) conta no banco do servidor.
func _db_equipped() -> Dictionary:
	var path := ProjectSettings.globalize_path(DIR).path_join(LocalStore.FILE)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or (data["accounts"] as Array).is_empty():
		return {}
	return data["accounts"][0]["profile"].get("equipped", {})


func _local_equipped() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(PlayerProfile.save_path)
	return cfg.get_value("equipped", "data", {})


func _setup(eq: Dictionary, key: String) -> float:
	return snappedf(float((eq.get("setup", {}) as Dictionary).get(key, -1.0)), 0.001)


func _decal(eq: Dictionary, slot: String) -> String:
	return str((eq.get("decals", {}) as Dictionary).get(slot, {}).get("id", ""))


func _connect() -> bool:
	net.connect_to_server("127.0.0.1", PORT)
	return await _wait_for(func() -> bool: return net.online, 20.0)


func _disconnect() -> void:
	net.disconnect_from_server()
	await create_timer(0.3).timeout


func _start_server() -> bool:
	host.start(PORT)
	return await _wait_for(func() -> bool: return host.is_running(), 60.0)


func _run() -> void:
	_clean()
	CarSkin.dir = SKINS
	PlayerProfile.save_path = "user://test_equip_profile.cfg"
	profile = root.get_node("Profile") as PlayerProfile
	profile.reset_profile()
	net = root.get_node("Net")
	net.account_file = "user://test_equip_account.cfg"
	host = LocalHost.new()
	host.dir = DIR
	host.auto_join = false
	root.add_child(host)
	_check(await _start_server(), "servidor no ar")
	_check(await _connect(), "conectado")
	# Configura online
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.7, 1.0))
	var skin: String = CarSkin.import_image(img)["hash"]
	profile.set_decal("sidepods", "estrela")
	profile.set_skin(skin)
	profile.set_setup_value("downforce_area", 5.0)
	profile.set_setup_value("aero_balance", 0.4)
	var saved := await _wait_for(func() -> bool:
		var eq := _db_equipped()
		return _decal(eq, "sidepods") == "estrela" and str(eq.get("skin", "")) == skin and _setup(eq, "downforce_area") == 5.0, 8.0)
	_check(saved, "decalque, skin e engenharia configurados online gravados no banco")
	_check(is_equal_approx(_setup(_db_equipped(), "aero_balance"), 0.4), "os dois ajustes de engenharia no banco")
	_check(_decal(_local_equipped(), "sidepods") == "estrela" and str(_local_equipped().get("skin", "")) == skin,
		"e também no aparelho")
	await _disconnect()
	_check(_decal(profile.equipped, "sidepods") == "estrela" and profile.equipped["skin"] == skin and _setup(profile.equipped, "downforce_area") == 5.0,
		"offline o carro é o mesmo (com a engenharia)")
	# Aparelho com um carro mais velho (como um jogo antigo deixaria): o do banco vale
	var cfg := ConfigFile.new()
	cfg.load(PlayerProfile.save_path)
	var old := PlayerProfile.default_equipped()
	old["edited"] = 1000.0
	cfg.set_value("equipped", "data", old)
	cfg.save(PlayerProfile.save_path)
	profile.load_profile()
	_check(await _connect(), "conectado de novo")
	await create_timer(0.5).timeout
	_check(_decal(profile.equipped, "sidepods") == "estrela" and profile.equipped["skin"] == skin and _setup(profile.equipped, "downforce_area") == 5.0,
		"carro mais velho do aparelho não apagou o do banco (nem a engenharia)")
	_check(_decal(_db_equipped(), "sidepods") == "estrela", "banco continua com o decalque")
	await _disconnect()
	# Mudança offline mais nova: vale no servidor
	profile.set_decal("nose", "estrela")
	_check(await _connect(), "conectado depois de mudar offline")
	var newer := await _wait_for(func() -> bool: return _decal(_db_equipped(), "nose") == "estrela", 8.0)
	_check(newer, "mudança offline mais nova chegou ao banco")
	_check(_decal(profile.equipped, "sidepods") == "estrela", "sem perder o decalque de antes")
	await _disconnect()
	# Reinicia o servidor: tudo vem do banco
	host.stop()
	await _wait_for(func() -> bool: return host.state == LocalHost.State.STOPPED, 15.0)
	profile.reset_profile()
	_check(await _start_server(), "servidor reiniciado")
	_check(await _connect(), "conectado ao servidor reiniciado")
	await create_timer(0.5).timeout
	var eq := profile.equipped
	_check(_decal(eq, "sidepods") == "estrela" and _decal(eq, "nose") == "estrela" and eq["skin"] == skin,
		"decalques e skin voltam do banco depois de reiniciar o servidor")
	_check(_setup(eq, "downforce_area") == 5.0 and is_equal_approx(_setup(eq, "aero_balance"), 0.4),
		"engenharia volta do banco depois de reiniciar o servidor")
	await _disconnect()
	host.stop()
	await _wait_for(func() -> bool: return host.state == LocalHost.State.STOPPED, 15.0)
	_clean()
	print("\nequip_persist_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)
