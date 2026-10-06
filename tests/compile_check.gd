extends SceneTree
## Carrega todos os scripts do projeto (erros de compilação aparecem no log).
## godot --headless --path . -s res://tests/compile_check.gd


func _init() -> void:
	var bad := 0
	for path in _scripts("res://scripts"):
		var s := load(path) as Script
		if s == null or not s.can_instantiate():
			print("FALHA ", path)
			bad += 1
	print("Scripts com erro: %d" % bad)
	quit(1 if bad > 0 else 0)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out
