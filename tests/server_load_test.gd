extends SceneTree
## Servidor com duas salas (sem janela, banco local): a pista do servidor é gerada uma vez na
## subida e cada sala só copia; uma sala correndo não congela quando outra larga.
##
## * Sobe o servidor (LocalHost, --host-dir de teste) e espera as pistas ficarem prontas.
## * Cliente A larga uma corrida com bots em Monza; com ela andando, B larga outra em Suzuka.
## * Mede, no A, o maior intervalo entre instantâneos e o quanto o tempo da simulação andou nesse
##   intervalo, antes e durante a largada do B; confere no log que nenhuma pista foi gerada de novo
##   na largada.
## * Relógio da interpolação (NetRaceClient._track_offset): sobe na hora, desce aos poucos.
##   godot --headless --path . -s res://tests/server_load_test.gd
## Arquivos: user://test_load_host/ e user://test_load_*.cfg (apagados no fim).

const PORT := 7364
const DIR := "user://test_load_host"

var failures := 0
var host: LocalHost
var a: Node
var b: Node
## Chegadas de instantâneos no A: [hora local (s), tempo da simulação]
var arrivals: Array = []


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


func _client(tag: String) -> Node:
	var holder := Node.new()
	holder.name = "Client" + tag
	root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var n: Node = load("res://scripts/net/net.gd").new()
	n.name = "Net"
	n.account_file = "user://test_load_%s.cfg" % tag.to_lower()
	n.auto_profile = false
	n.auto_race = false
	holder.add_child(n)
	return n


func _clean() -> void:
	for d in [DIR.path_join("skins"), DIR]:
		var abs_dir := ProjectSettings.globalize_path(d)
		if DirAccess.dir_exists_absolute(abs_dir):
			for f in DirAccess.get_files_at(abs_dir):
				DirAccess.remove_absolute(abs_dir.path_join(f))
			DirAccess.remove_absolute(abs_dir)
	for f in ["user://test_load_a.cfg", "user://test_load_b.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _log_has(text: String, from := 0) -> int:
	var n := 0
	for k in range(from, host.log_lines.size()):
		if host.log_lines[k].contains(text):
			n += 1
	return n


func _run() -> void:
	_clean()
	_offset_clock()
	host = LocalHost.new()
	host.dir = DIR
	host.auto_join = false
	root.add_child(host)
	host.start(PORT)
	var t0 := Time.get_ticks_msec()
	var ready := await _wait_for(func() -> bool: return _log_has("pistas do servidor prontas") > 0, 120.0)
	_check(ready, "pistas do servidor geradas na subida (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_check(_log_has("gerados em") == RaceSettings.TRACKS.size(), "cada pista gerada uma vez (%d)" % _log_has("gerados em"))
	if not ready:
		print("\n".join(host.log_lines))
		await _finish()
		return
	a = _client("A")
	b = _client("B")
	a.connect_to_server("127.0.0.1", PORT)
	b.connect_to_server("127.0.0.1", PORT)
	if not await _wait_for(func() -> bool: return a.online and b.online, 20.0):
		_check(false, "clientes conectados")
		await _finish()
		return
	a.race_snapshot.connect(func(data: PackedByteArray) -> void:
		arrivals.append([Time.get_ticks_usec() / 1000000.0, float(NetSnapshot.decode(data)["t"])]))
	var log_mark := host.log_lines.size()
	await _race(a, "monza")
	var racing := await _wait_for(func() -> bool: return arrivals.size() > 60, 30.0)
	_check(racing, "sala do A correndo (instantâneos chegando)")
	await create_timer(3.0).timeout
	var before := _worst_gap(0)
	# Com o A correndo, o B larga outra sala em outra pista
	var mark := arrivals.size()
	await _race(b, "suzuka")
	await create_timer(6.0).timeout
	var during := _worst_gap(mark)
	print("  maior intervalo entre instantâneos: antes %.0f ms (simulação andou %.0f ms), com o B largando %.0f ms (simulação %.0f ms)" % [
		before.x * 1000.0, before.y * 1000.0, during.x * 1000.0, during.y * 1000.0])
	print("  intervalos acima de 100 ms com o B largando: %s" % str(_gaps_over(mark, 0.1)))
	_check(during.x < 0.25, "a sala do A não congelou quando a do B largou (maior intervalo %.0f ms)" % (during.x * 1000.0))
	_check(_log_has("gerados em", log_mark) == 0, "nenhuma pista gerada de novo ao largar as corridas")
	_check(_log_has("copiados do cache", log_mark) >= 2, "as duas salas copiaram a pista do cache")
	var rate := _rate(mark)
	_check(absf(rate - NetProtocol.SNAPSHOT_HZ) < 2.0, "instantâneos a %.1f por segundo" % rate)
	await _finish()


## Larga uma sala com bots na pista e confirma que carregou.
func _race(n: Node, track: String) -> void:
	await n.request("room_create", {"kind": "custom", "name": "Carga " + track})
	await n.request("room_settings", {"track": track, "laps": 3, "bots": true, "cars": 10, "difficulty": 2})
	var started := []
	var cb := func(type: String, _d: Dictionary) -> void:
		if type == "race_start":
			started.append(true)
	n.message.connect(cb)
	await n.request("room_start")
	await _wait_for(func() -> bool: return not started.is_empty(), 60.0)
	n.message.disconnect(cb)
	n.send_to_server("race_cmd", {"cmd": "loaded"})


## Maior intervalo (s) entre instantâneos a partir de `from`, e o tempo de simulação nele.
func _worst_gap(from: int) -> Vector2:
	var worst := Vector2.ZERO
	for k in range(maxi(from, 1), arrivals.size()):
		var gap: float = arrivals[k][0] - arrivals[k - 1][0]
		if gap > worst.x:
			worst = Vector2(gap, arrivals[k][1] - arrivals[k - 1][1])
	return worst


## Intervalos (ms, entrega / simulação) acima de `limit` s a partir de `from`.
func _gaps_over(from: int, limit: float) -> Array:
	var out := []
	for k in range(maxi(from, 1), arrivals.size()):
		var gap: float = arrivals[k][0] - arrivals[k - 1][0]
		if gap > limit:
			out.append("%d/%d" % [gap * 1000.0, (arrivals[k][1] - arrivals[k - 1][1]) * 1000.0])
	return out


func _rate(from: int) -> float:
	if arrivals.size() - from < 2:
		return 0.0
	return (arrivals.size() - 1 - from) / (arrivals[-1][1] - arrivals[from][1])


## Relógio da interpolação: sobe na hora, desce aos poucos (~0,5 s) e não pula.
func _offset_clock() -> void:
	print("Relógio da interpolação")
	var c := NetRaceClient.new()
	for k in 20:
		c._track_offset(10.0)
	_check(is_equal_approx(c._offset, 10.0), "estável")
	c._track_offset(10.05)
	_check(is_equal_approx(c._offset, 10.05), "sobe na hora")
	# O servidor atrasou 0,2 s (o tempo da simulação ficou para trás) e segue assim
	var steps := []
	for k in 40:
		c._track_offset(9.85)
		steps.append(c._offset)
	var biggest := 0.0
	for k in range(1, steps.size()):
		biggest = maxf(biggest, absf(steps[k] - steps[k - 1]))
	_check(absf(steps[-1] - 9.85) < 0.005, "desce até o novo relógio (%.3f)" % steps[-1])
	_check(biggest < 0.05, "desce sem pular (maior passo %.3f s)" % biggest)
	var reached := steps.find(steps.filter(func(v: float) -> bool: return v < 9.86)[0])
	_check(reached <= 30, "converge em cerca de 0,5 s a 1 s (%d instantâneos)" % reached)
	c.free()


func _finish() -> void:
	if host and host.is_active():
		host.stop()
		await _wait_for(func() -> bool: return host.state == LocalHost.State.STOPPED, 15.0)
	if failures > 0 and host:
		print("--- log do servidor\n" + "\n".join(host.log_lines.slice(maxi(host.log_lines.size() - 40, 0))))
	_clean()
	print("\nserver_load_test: %d falhas" % failures)
	quit(1 if failures > 0 else 0)
