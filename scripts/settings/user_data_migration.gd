class_name UserDataMigrator
extends Node
## Migração da pasta de dados (autoload "UserDataMigration", o primeiro da lista).
##
## Até a versão 0.4 o projeto se chamava "F1 Gatcha", e o Godot guardava o perfil, as
## configurações, a interface, a conta do multiplayer (account.cfg: o token do aparelho) e os SVGs
## do jogador em app_userdata/F1 Gatcha. Com o nome Speedoru a pasta passa a ser
## app_userdata/Speedoru. Na primeira vez que o Speedoru abre, se a pasta nova ainda não tem
## perfil, configurações nem conta, copia tudo da antiga (que fica como está). Roda no _init, antes
## dos outros autoloads lerem os arquivos.

const OLD_NAME := "F1 Gatcha"
## Arquivos que mostram que a pasta nova já está em uso (não copia por cima).
const MARKERS := ["profile.cfg", "settings.cfg", "account.cfg", "interface.cfg"]
## Pastas que não valem a cópia (caches e downloads temporários).
const SKIP := ["logs", "shader_cache", "vulkan", "update"]


func _init() -> void:
	migrate(OS.get_user_data_dir(), OS.get_user_data_dir().get_base_dir().path_join(OLD_NAME))


## Copia old_dir -> new_dir se a antiga existe e a nova ainda não tem dados. Devolve quantos
## arquivos copiou.
static func migrate(new_dir: String, old_dir: String) -> int:
	if new_dir.simplify_path() == old_dir.simplify_path() or not DirAccess.dir_exists_absolute(old_dir):
		return 0
	for m in MARKERS:
		if FileAccess.file_exists(new_dir.path_join(m)):
			return 0
	var n := _copy_dir(old_dir, new_dir)
	if n > 0:
		print("Speedoru: %d arquivos trazidos de %s" % [n, old_dir])
	return n


static func _copy_dir(from: String, to: String) -> int:
	DirAccess.make_dir_recursive_absolute(to)
	var dir := DirAccess.open(from)
	if dir == null:
		return 0
	var n := 0
	for f in dir.get_files():
		if DirAccess.copy_absolute(from.path_join(f), to.path_join(f)) == OK:
			n += 1
	for sub in dir.get_directories():
		if not sub in SKIP:
			n += _copy_dir(from.path_join(sub), to.path_join(sub))
	return n
