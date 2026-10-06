class_name PerfOverlay
extends CanvasLayer
## Monitor de desempenho na tela (Configurações → Desempenho): uma faixa fina e quase transparente
## na borda escolhida.
##
## * FPS: só os quadros por segundo (cor pela faixa: verde ≥ 55, amarelo ≥ 30, vermelho).
## * Detalhado (duas linhas): FPS, média e mínimo, tempo de quadro com um mini gráfico; CPU (tempo
##   da lógica e da física por quadro), GPU (tempo de renderização medido), RAM do jogo, VRAM e
##   draw calls.
##
## O Godot não expõe o uso total de CPU do sistema; "CPU" aqui é quanto tempo o processador
## gasta na lógica do jogo e na física (medidas separadas: podem se sobrepor entre threads).

enum Mode { OFF, FPS, DETAILED }
enum ScreenCorner { TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT, TOP_CENTER }

const HISTORY := 150

var mode := Mode.OFF
var corner := ScreenCorner.BOTTOM_LEFT

var _panel: PerfPanel


func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PerfPanel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	configure(mode, corner)


func configure(p_mode: int, p_corner: int) -> void:
	mode = p_mode as Mode
	corner = p_corner as ScreenCorner
	if _panel == null:
		return
	_panel.visible = mode != Mode.OFF
	_panel.detailed = mode == Mode.DETAILED
	_panel.custom_minimum_size = Vector2(470, 40) if _panel.detailed else Vector2(84, 24)
	_panel.size = _panel.custom_minimum_size
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, mode == Mode.DETAILED)
	var preset: Control.LayoutPreset = [Control.PRESET_TOP_LEFT, Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_LEFT,
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_TOP][clampi(corner, 0, 4)]
	_panel.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_KEEP_SIZE, 8)


class PerfPanel extends Control:
	var detailed := false
	var _frames := PackedFloat32Array()
	var _accum := 0.0
	var _count := 0
	var _worst := 0.0
	var _fps_avg := 0.0
	var _fps_low := 0.0

	func _ready() -> void:
		_frames.resize(HISTORY)

	func _process(delta: float) -> void:
		if not visible:
			return
		var ms := delta * 1000.0
		_frames.remove_at(0)
		_frames.append(ms)
		_accum += delta
		_count += 1
		_worst = maxf(_worst, ms)
		if _accum >= 0.5:
			_fps_avg = _count / _accum
			_fps_low = 1000.0 / maxf(_worst, 0.001)
			_accum = 0.0
			_count = 0
			_worst = 0.0
		queue_redraw()

	func _fps_color(fps: float) -> Color:
		if fps >= 55.0:
			return Retro.c("good")
		if fps >= 30.0:
			return Retro.c("warn")
		return Retro.c("bad")

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(Retro.c("bg"), 0.38))
		draw_rect(Rect2(0, 0, 2, size.y), Color(Retro.c("accent"), 0.7))
		var disp := Retro.display(800)
		var body := Retro.body(600)
		var muted := Retro.c("muted")
		var fps := Engine.get_frames_per_second()
		if not detailed:
			draw_string(disp, Vector2(8, 18), "%d" % fps, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, _fps_color(fps))
			draw_string(Retro.display(700), Vector2(0, 17), "FPS", HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6, 9, muted)
			return
		# Linha 1: FPS, média/mínimo, tempo de quadro e mini gráfico
		draw_string(disp, Vector2(8, 17), "%d" % fps, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, _fps_color(fps))
		draw_string(Retro.display(700), Vector2(48, 16), "FPS", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, muted)
		var frame_ms := 1000.0 / maxf(fps, 1.0)
		draw_string(body, Vector2(78, 16), "média %d · mín %d · %.1f ms" % [roundi(_fps_avg), roundi(_fps_low), frame_ms],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Retro.c("text_2"))
		var g := Rect2(size.x - 128, 4, 120, 14)
		var scale_ms := 50.0
		var gy := g.end.y - g.size.y * 16.7 / scale_ms
		draw_line(Vector2(g.position.x, gy), Vector2(g.end.x, gy), Retro.line(1), 1.0)
		var pts := PackedVector2Array()
		for k in HISTORY:
			pts.append(Vector2(g.position.x + g.size.x * k / (HISTORY - 1),
				g.end.y - g.size.y * clampf(_frames[k] / scale_ms, 0.0, 1.0)))
		draw_polyline(pts, Retro.c("accent_2"), 1.0, true)
		# Linha 2: CPU, GPU, memória, draw calls
		var logic_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		var ram := OS.get_static_memory_usage() / 1048576.0
		var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
		var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var parts := [["CPU", "%.1f + %.1f ms" % [logic_ms, physics_ms]], ["GPU", "%.1f ms" % gpu_ms],
			["RAM", "%d MB" % roundi(ram)], ["VRAM", "%d MB" % roundi(vram)], ["DRAW", "%d" % draws]]
		var x := 8.0
		var f := Retro.display(700)
		for part in parts:
			draw_string(f, Vector2(x, 34), part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Retro.c("accent_2"))
			x += f.get_string_size(part[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 4
			draw_string(body, Vector2(x, 34), part[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Retro.c("text"))
			x += body.get_string_size(part[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12
