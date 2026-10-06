extends SceneTree
## Atualização automática (sem janela; precisa de internet):
##   godot --headless --path . -s res://tests/updater_test.gd
## Compara versões e, fingindo ser a 0.0.1, consulta a última release no GitHub, baixa o
## instalador e confere o SHA-256 publicado — sem instalar (dry_run). Apaga o download no fim.

var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(AutoUpdater.is_newer("0.2.0", "0.1.0"), "0.2.0 é mais nova que 0.1.0")
	_check(AutoUpdater.is_newer("0.10.0", "0.9.9"), "0.10.0 é mais nova que 0.9.9 (número, não texto)")
	_check(AutoUpdater.is_newer("v1.0", "0.9.12"), "aceita o v da tag")
	_check(not AutoUpdater.is_newer("0.1.0", "0.1.0"), "mesma versão não atualiza")
	_check(not AutoUpdater.is_newer("0.1.0", "0.2.0"), "versão mais velha não atualiza")
	var autoload := root.get_node_or_null("Updater") as AutoUpdater
	_check(autoload != null and not autoload.should_check(), "sem janela / fora do instalador: não consulta ao abrir")
	var up := AutoUpdater.new()
	up.dry_run = true
	root.add_child(up)
	up.current_version = "0.0.1"
	await up._check()
	_check(up.latest_version != "" and AutoUpdater.is_newer(up.latest_version, "0.0.1"), "achou a última release: %s" % up.latest_version)
	_check(up.state == "ready" and FileAccess.file_exists(up._installer_path),
		"baixou o instalador e o SHA-256 confere (%s, estado %s)" % [up._installer_path.get_file(), up.state])
	if FileAccess.file_exists(up._installer_path):
		var size := FileAccess.open(up._installer_path, FileAccess.READ).get_length()
		_check(size > 10_000_000, "instalador com %.1f MB" % (size / 1048576.0))
		DirAccess.remove_absolute(up._installer_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AutoUpdater.DIR))
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
