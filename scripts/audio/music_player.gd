extends Node
## Música de fundo (autoload "Music") no bus "Music"; M liga/desliga.
##
## Quatro faixas originais (tools/generate_music.py e tools/generate_music_extra.py), cada uma
## fecha em loop sem emenda. O menu principal tem o próprio tema (MENU_TRACK, em loop); na pista
## toca a faixa escolhida em Configurações → Áudio ou a playlist (cada faixa duas vezes, depois a
## próxima com crossfade). Trocar de cena troca a música na hora (set_context).

const TRACKS := [
	["res://assets/audio/music/race_theme.wav", "Tema da corrida", "pop anime"],
	["res://assets/audio/music/synthwave.wav", "Neon Horizon", "synthwave"],
	["res://assets/audio/music/drum_and_bass.wav", "Slipstream", "drum & bass"],
	["res://assets/audio/music/chiptune.wav", "Pixel Grand Prix", "chiptune 8-bit"],
]
const LOOPS_PER_TRACK := 2
## Tema do menu principal (Neon Horizon).
const MENU_TRACK := 1
const CROSSFADE := 3.0
const BASE_DB := -4.0

## 0 = playlist; 1..N = faixa fixa.
var selection := 0
var enabled := true
var current := 0
## "menu" ou "race" (cada cena avisa ao entrar).
var context := "race"

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _played := 0.0
var _fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if "--server" in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		set_process(false)
		return
	for k in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Player%d" % k
		p.bus = &"Music" if AudioServer.get_bus_index(&"Music") >= 0 else &"Master"
		p.volume_db = BASE_DB
		add_child(p)
		_players.append(p)
	current = randi() % TRACKS.size()
	_start(current, false)
	get_tree().scene_changed.connect(_on_scene_changed)


## Cada cena define a música: o menu principal toca o tema do menu; as pistas, a da corrida.
func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	set_context("menu" if scene.scene_file_path.ends_with("main_menu.tscn") else "race")


func set_context(new_context: String) -> void:
	if new_context == context:
		return
	context = new_context
	if context == "menu":
		_start(MENU_TRACK, false)
	else:
		# Playlist: começa numa faixa diferente do tema do menu (a troca tem que ser perceptível)
		var pick := (MENU_TRACK + 1 + randi() % (TRACKS.size() - 1)) % TRACKS.size()
		_start(selection - 1 if selection > 0 else pick, false)


func _process(delta: float) -> void:
	if selection != 0 or not enabled or context == "menu":
		return
	var p := _players[_active]
	if not p.playing or p.stream == null:
		return
	_played += delta
	var length := p.stream.get_length()
	if length > 0.0 and _played >= length * LOOPS_PER_TRACK - CROSSFADE:
		_start((current + 1) % TRACKS.size(), true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_music"):
		var settings := get_node_or_null("/root/Settings") as GameSettings
		if settings:
			settings.set_value("audio", "music_on", not enabled)
		else:
			set_enabled(not enabled)


## Chamado pelas configurações: liga/desliga e escolhe a faixa (0 = playlist).
func configure(on: bool, track: int) -> void:
	set_enabled(on)
	track = clampi(track, 0, TRACKS.size())
	if track != selection:
		selection = track
		if selection > 0 and selection - 1 != current and context == "race":
			_start(selection - 1, true)


func set_enabled(on: bool) -> void:
	enabled = on
	for p in _players:
		p.stream_paused = not on


func is_enabled() -> bool:
	return enabled


func track_names() -> PackedStringArray:
	var out := PackedStringArray()
	for t in TRACKS:
		out.append("%s (%s)" % [t[1], t[2]])
	return out


func _start(index: int, crossfade: bool) -> void:
	current = index
	_played = 0.0
	var old := _players[_active]
	_active = 1 - _active if crossfade else _active
	var p := _players[_active]
	p.stream = load(TRACKS[index][0])
	p.stream_paused = not enabled
	if _fade:
		_fade.kill()
	if crossfade and old.playing:
		p.volume_db = -40.0
		p.play()
		_fade = create_tween().set_parallel()
		_fade.tween_property(p, "volume_db", BASE_DB, CROSSFADE)
		_fade.tween_property(old, "volume_db", -40.0, CROSSFADE)
		_fade.chain().tween_callback(old.stop)
	else:
		for other in _players:
			if other != p:
				other.stop()
		p.volume_db = BASE_DB
		p.play()
