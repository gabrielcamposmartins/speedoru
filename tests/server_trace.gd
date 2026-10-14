extends SceneTree
## Servidor dedicado com cada callback dos scripts cronometrado (mesma troca na memória do
## frame_probe): quando um passo de física passa de SLOW_MS, escreve no log quanto cada script
## gastou nele (o que sobra é código nativo e o motor). A cada minuto, os scripts que mais gastaram.
## Com --trace-deep=a,b (nomes dos arquivos sem .gd) cronometra todas as funções desses scripts.
##   godot --headless -s res://tests/server_trace.gd -- --server --port=N --host-dir=DIR [--trace-deep=race_manager]
## (o net_frame_probe -- --server-trace sobe o servidor assim.)

const CALLBACKS := ["_process", "_physics_process", "_integrate_forces"]
const SLOW_MS := 8.3

## Quadro do servidor maior que isso (ms) vai para o log.
const SLOW_FRAME_MS := 60.0
var _step_t := 0
var _frame_t := 0
var _totals := {}
var _minute_t := 0


func _initialize() -> void:
	Engine.set_meta(&"prof", {})
	var paths: Array = []
	_scripts("res://scripts", paths)
	var deep := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--trace-deep="):
			deep = a.trim_prefix("--trace-deep=").split(",")
	var n := 0
	for p: String in paths:
		n += _instrument(p, p.get_file().get_basename() in deep)
	print("server_trace: %d callbacks cronometrados" % n)
	physics_frame.connect(_on_physics_frame)
	process_frame.connect(_on_process_frame)
	_minute_t = Time.get_ticks_msec()
	change_scene_to_file("res://scenes/boot.tscn")


## Quadro do servidor (fora da física) longo: o servidor ficou parado (nada sai pela rede).
func _on_process_frame() -> void:
	var now := Time.get_ticks_usec()
	if _frame_t > 0 and (now - _frame_t) / 1000.0 > SLOW_FRAME_MS:
		print("server_trace: quadro parado %.0f ms (em %.1f s de servidor; scripts no passo atual: %s)" % [
			(now - _frame_t) / 1000.0, Time.get_ticks_msec() / 1000.0, Engine.get_meta(&"prof")])
	_frame_t = now


func _on_physics_frame() -> void:
	var now := Time.get_ticks_usec()
	var d: Dictionary = Engine.get_meta(&"prof")
	var sum := 0
	for k in d:
		sum += int(d[k])
		_totals[k] = int(_totals.get(k, 0)) + int(d[k])
	if sum / 1000.0 > SLOW_MS:
		var keys := d.keys()
		keys.sort_custom(func(a, b) -> bool: return d[a] > d[b])
		var parts := []
		for k in keys.slice(0, 6):
			parts.append("%s %.1f" % [k, d[k] / 1000.0])
		print("server_trace: passo lento, scripts %.1f ms (desde o anterior %.1f ms): %s" % [sum / 1000.0,
			(now - _step_t) / 1000.0, ", ".join(parts)])
	d.clear()
	_step_t = now
	if Time.get_ticks_msec() - _minute_t > 60000:
		_minute_t = Time.get_ticks_msec()
		var keys := _totals.keys()
		keys.sort_custom(func(a, b) -> bool: return _totals[a] > _totals[b])
		var parts := []
		for k in keys.slice(0, 10):
			parts.append("%s %.0f" % [k, _totals[k] / 1000.0])
		print("server_trace: minuto (ms): ", ", ".join(parts))
		_totals.clear()


static func _scripts(dir: String, out: Array, skip := []) -> void:
	if dir in skip:
		return
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		_scripts(dir.path_join(sub), out, skip)


static func _instrument(path: String, all := false) -> int:
	var script := load(path) as GDScript
	if script == null:
		return 0
	var lines := script.source_code.split("\n")
	var out := PackedStringArray()
	var n := 0
	var rx := RegEx.create_from_string("^(\\s*)(static )?func (\\w+)\\(([^)]*)\\)(\\s*->\\s*([\\w\\[\\]\\.]+))?\\s*:\\s*$")
	for i in lines.size():
		var m := rx.search(lines[i])
		if m == null or not (all or m.get_string(3) in CALLBACKS) or _has_await(lines, i, m.get_string(1)):
			out.append(lines[i])
			continue
		var ind := m.get_string(1)
		var fn := m.get_string(3)
		var args := PackedStringArray()
		for a in m.get_string(4).split(",", false):
			args.append(a.split(":")[0].split("=")[0].strip_edges())
		var key := "%s:%s" % [path.get_file().get_basename(), fn]
		var ret := m.get_string(6)
		var head := "%s%sfunc %s(%s)%s:" % [ind, m.get_string(2), fn, m.get_string(4), (" -> " + ret) if ret != "" else ""]
		out.append(head)
		out.append("%s\tvar __t := Time.get_ticks_usec()" % ind)
		if ret == "void":
			out.append("%s\t%s__p(%s)" % [ind, fn, ", ".join(args)])
		else:
			out.append("%s\tvar __r = %s__p(%s)" % [ind, fn, ", ".join(args)])
		out.append("%s\tvar __d: Dictionary = Engine.get_meta(&\"prof\")" % ind)
		out.append("%s\t__d[\"%s\"] = int(__d.get(\"%s\", 0)) + Time.get_ticks_usec() - __t" % [ind, key, key])
		if ret != "void":
			out.append("%s\treturn __r" % ind)
		out.append("")
		out.append(head.replace("func %s(" % fn, "func %s__p(" % fn))
		n += 1
	if n == 0:
		return 0
	script.source_code = "\n".join(out)
	if script.reload(true) != OK:
		print("server_trace: não deu para cronometrar ", path)
		return 0
	return n


static func _has_await(lines: PackedStringArray, at: int, ind: String) -> bool:
	for j in range(at + 1, lines.size()):
		var l := lines[j]
		if l.strip_edges() != "" and not l.begins_with(ind + "\t") and not l.begins_with(ind + " "):
			return false
		if l.contains("await "):
			return true
	return false
