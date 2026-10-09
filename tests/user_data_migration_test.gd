extends SceneTree
## Migração da pasta de dados (sem janela):  godot --headless --path . -s res://tests/user_data_migration_test.gd
## Usa pastas de teste dentro de user:// (as pastas de verdade do jogador não são tocadas): copia a
## pasta antiga inteira (com subpastas, sem caches) para a nova vazia, e não copia por cima de uma
## pasta nova que já tem perfil.

var failures := 0


func _check(ok: bool, msg: String) -> void:
	print(("  OK   " if ok else "  FALHA ") + msg)
	if not ok:
		failures += 1


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _rm(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in d.get_directories():
		_rm(dir.path_join(sub))
	DirAccess.remove_absolute(dir)


func _initialize() -> void:
	var base := ProjectSettings.globalize_path("user://test_migration")
	_rm(base)
	var old := base.path_join("F1 Gatcha")
	var new := base.path_join("Speedoru")
	_write(old.path_join("profile.cfg"), "perfil")
	_write(old.path_join("account.cfg"), "token")
	_write(old.path_join("decals/meu.svg"), "<svg/>")
	_write(old.path_join("logs/godot.log"), "log")
	var n := UserDataMigrator.migrate(new, old)
	_check(n == 3, "copia perfil, conta e SVGs (%d arquivos)" % n)
	_check(FileAccess.get_file_as_string(new.path_join("account.cfg")) == "token", "conta do multiplayer trazida")
	_check(FileAccess.file_exists(new.path_join("decals/meu.svg")), "subpastas trazidas")
	_check(not FileAccess.file_exists(new.path_join("logs/godot.log")), "logs ficam para trás")
	_check(FileAccess.file_exists(old.path_join("profile.cfg")), "a pasta antiga fica como está")
	_write(old.path_join("profile.cfg"), "perfil antigo mudou")
	_check(UserDataMigrator.migrate(new, old) == 0 and FileAccess.get_file_as_string(new.path_join("profile.cfg")) == "perfil",
		"não copia por cima de uma pasta nova em uso")
	_check(UserDataMigrator.migrate(new, base.path_join("nada")) == 0, "sem pasta antiga: nada a fazer")
	_check(ProjectSettings.get_setting("application/config/name") == "Speedoru", "projeto se chama Speedoru")
	_check(OS.get_user_data_dir().ends_with("Speedoru"), "pasta de dados nova: %s" % OS.get_user_data_dir())
	_rm(base)
	print("Falhas: %d" % failures)
	quit(1 if failures > 0 else 0)
