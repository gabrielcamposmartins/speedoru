extends SceneTree
## Endereço antigo do servidor oficial no arquivo da conta (sem janela):
##   godot --headless --path . -s res://tests/server_host_migration_test.gd -- --offline
## Usa user://test_host_migration.cfg (o account.cfg do jogador não é tocado).

const FILE := "user://test_host_migration.cfg"
var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	var old: String = NetProtocol.OLD_HOSTS[0]
	var new := NetProtocol.DEFAULT_HOST
	_check(old != new, "endereço padrão mudou (%s)" % new)
	var cfg := ConfigFile.new()
	cfg.set_value("account", "token", "abc")
	cfg.set_value("server", "host", old)
	cfg.set_value("server", "port", 7350)
	cfg.set_value("servers", "saved", [
		{"name": "Oficial", "host": old, "port": 7350},
		{"name": "Casa", "host": "10.0.0.9", "port": 7350},
	])
	# o novo já está no histórico: o antigo some em vez de duplicar
	cfg.set_value("servers", "history", [
		{"host": new, "port": 7350, "t": 3},
		{"host": "127.0.0.1", "port": 7350, "t": 2},
		{"host": old, "port": 7350, "t": 1},
	])
	cfg.set_value("collection", "by_server", {"%s:7350" % old: ["trail_fire"], "127.0.0.1:7350": ["boost_x"]})
	cfg.save(FILE)

	var net: Node = load("res://scripts/net/net.gd").new()
	net.account_file = FILE
	# sem persist (como nos testes e no --offline): só a memória muda
	var mem := ConfigFile.new()
	mem.load(FILE)
	net._migrate_old_hosts(mem, false)
	var disk := ConfigFile.new()
	disk.load(FILE)
	_check(mem.get_value("server", "host") == new and disk.get_value("server", "host") == old,
		"sem persist, muda só na memória")

	var loaded := ConfigFile.new()
	loaded.load(FILE)
	net._migrate_old_hosts(loaded)

	var got := ConfigFile.new()
	got.load(FILE)
	_check(got.get_value("server", "host") == new, "servidor escolhido vira o novo")
	_check(got.get_value("account", "token") == "abc", "token da conta continua")
	var saved: Array = got.get_value("servers", "saved")
	_check(saved.size() == 2 and saved[0]["host"] == new and saved[0]["name"] == "Oficial", "servidor salvo com nome migra")
	_check(saved[1]["host"] == "10.0.0.9", "outro servidor salvo fica igual")
	var hist: Array = got.get_value("servers", "history")
	_check(hist.size() == 2 and hist[0]["host"] == new and hist[1]["host"] == "127.0.0.1", "histórico sem repetir o oficial")
	var by: Dictionary = got.get_value("collection", "by_server")
	_check(by.get("%s:7350" % new) == ["trail_fire"] and not by.has("%s:7350" % old), "coleção guardada muda de chave")
	_check(by.get("127.0.0.1:7350") == ["boost_x"], "coleção de outro servidor fica")

	# arquivo sem endereço antigo: não regrava (o que só mudou na memória não vai para o disco)
	var again := ConfigFile.new()
	again.load(FILE)
	again.set_value("account", "token", "mudou_so_na_memoria")
	net._migrate_old_hosts(again)
	var after := ConfigFile.new()
	after.load(FILE)
	_check(after.get_value("account", "token") == "abc", "sem endereço antigo, o arquivo não muda")

	net.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	print("RESULTADO: ", "OK" if failures == 0 else "%d FALHA(S)" % failures)
	quit(1 if failures else 0)
