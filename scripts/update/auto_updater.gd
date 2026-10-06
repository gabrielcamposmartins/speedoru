class_name AutoUpdater
extends CanvasLayer
## Atualização automática (autoload "Updater"), como no Pokeru: ao abrir, o jogo consulta a última
## release no GitHub; se ela é mais nova que a versão rodando, baixa o instalador, confere o
## SHA-256 publicado na release (SHA256SUMS.txt), roda o instalador em modo silencioso (sem
## janela, sem administrador — a instalação é por usuário) e fecha. O instalador termina e abre o
## jogo de novo (installer/speedoru.iss, [Run] com skipifnotsilent).
##
## * Um aviso pequeno no canto mostra o progresso; erro (sem internet, sem release…) vira um aviso
##   que some sozinho e o jogo segue normal.
## * Se o download terminar no meio de uma corrida, a instalação espera a volta ao menu.
## * Só roda na versão instalada pelo instalador (tem o desinstalador ao lado do .exe): nem no
##   editor, nem no servidor dedicado, nem com --no-update. Desliga em Configurações → Jogo.

const REPO := "gabrielcamposmartins/speedoru"
const API := "https://api.github.com/repos/%s/releases/latest" % REPO
const INSTALLER := "Speedoru-setup.exe"
const SUMS := "SHA256SUMS.txt"
const DIR := "user://update"
const MENU_SCENE := "res://scenes/menu/main_menu.tscn"

var current_version := ""
var latest_version := ""
## idle | checking | downloading | ready | installing | done | error
var state := "idle"
## Testes: para em "ready" (baixado e conferido), sem instalar nem fechar o jogo.
var dry_run := false

var _http: HTTPRequest
var _panel: PanelContainer
var _label: Label
var _bar: ProgressBar
var _installer_path := ""


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	current_version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_clean_old_downloads()
	if not should_check():
		return
	_build_ui()
	_check.call_deferred()


## Atualiza só a versão instalada, fora do editor e do servidor, com a opção ligada.
func should_check() -> bool:
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	if "--server" in args or "--no-update" in args or DisplayServer.get_name() == "headless":
		return false
	if OS.has_feature("editor") or not OS.has_feature("template"):
		return false
	if not FileAccess.file_exists(OS.get_executable_path().get_base_dir().path_join("unins000.exe")):
		return false
	var settings := get_node_or_null("/root/Settings") as GameSettings
	return settings == null or bool(settings.get_value("gameplay", "auto_update"))


## "0.10.2" > "0.9.9": compara número a número.
static func is_newer(candidate: String, current: String) -> bool:
	var a := candidate.trim_prefix("v").split(".")
	var b := current.trim_prefix("v").split(".")
	for i in maxi(a.size(), b.size()):
		var x := int(a[i]) if i < a.size() else 0
		var y := int(b[i]) if i < b.size() else 0
		if x != y:
			return x > y
	return false


func _check() -> void:
	state = "checking"
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	var headers := PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: Speedoru/" + current_version])
	if _http.request(API, headers) != OK:
		_fail("não foi possível consultar as versões")
		return
	var res: Array = await _http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_fail("sem resposta do GitHub (%d)" % res[1], false)
		return
	var data: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not data is Dictionary:
		_fail("resposta inválida do GitHub", false)
		return
	latest_version = str(data.get("tag_name", "")).trim_prefix("v")
	if latest_version == "" or not is_newer(latest_version, current_version):
		state = "idle"
		return
	var urls := {}
	for asset: Dictionary in data.get("assets", []):
		urls[str(asset.get("name", ""))] = str(asset.get("browser_download_url", ""))
	if not urls.has(INSTALLER) or not urls.has(SUMS):
		_fail("a versão %s não tem instalador" % latest_version)
		return
	await _download(urls[INSTALLER], urls[SUMS])


func _download(installer_url: String, sums_url: String) -> void:
	state = "downloading"
	_show("Baixando a versão %s…" % latest_version, 0.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	# Somas primeiro (arquivo pequeno)
	if _http.request(sums_url, PackedStringArray(["User-Agent: Speedoru"])) != OK:
		_fail("falha ao baixar as somas")
		return
	var res: Array = await _http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_fail("falha ao baixar as somas (%d)" % res[1])
		return
	var expected := ""
	for line in (res[3] as PackedByteArray).get_string_from_utf8().split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() >= 2 and parts[parts.size() - 1].trim_prefix("*") == INSTALLER:
			expected = parts[0].to_lower()
	if expected == "":
		_fail("a release não publica o SHA-256 do instalador")
		return
	_installer_path = ProjectSettings.globalize_path(DIR.path_join("Speedoru-%s-setup.exe" % latest_version))
	_http.download_file = _installer_path
	if _http.request(installer_url, PackedStringArray(["User-Agent: Speedoru"])) != OK:
		_fail("falha ao baixar o instalador")
		return
	res = await _http.request_completed
	_http.download_file = ""
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_fail("falha ao baixar o instalador (%d)" % res[1])
		return
	if FileAccess.get_sha256(_installer_path).to_lower() != expected:
		DirAccess.remove_absolute(_installer_path)
		_fail("o instalador baixado não confere (SHA-256)")
		return
	state = "ready"
	if not dry_run:
		_install_when_possible()


## Instala já, ou espera o jogador sair da corrida (volta ao menu).
func _install_when_possible() -> void:
	if not _in_race():
		_install()
		return
	_show("Versão %s pronta: instala ao voltar ao menu" % latest_version, 1.0)
	while _in_race():
		await get_tree().process_frame
	_install()


func _in_race() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path != MENU_SCENE and scene.has_node("RaceManager")


func _install() -> void:
	state = "installing"
	_show("Instalando a versão %s… o jogo vai reabrir" % latest_version, 1.0)
	await get_tree().create_timer(1.2).timeout
	# Silencioso (sem janela), por usuário; o instalador fecha este jogo se ainda estiver aberto
	# e abre a versão nova no fim
	var pid := OS.create_process(_installer_path, ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/CURRENTUSER"])
	if pid <= 0:
		_fail("não foi possível abrir o instalador")
		return
	state = "done"
	get_tree().quit()


func _process(_delta: float) -> void:
	if state == "downloading" and _http and _http.download_file != "":
		var total := _http.get_body_size()
		if total > 0:
			_show("Baixando a versão %s… %d%%" % [latest_version, roundi(100.0 * _http.get_downloaded_bytes() / total)],
				float(_http.get_downloaded_bytes()) / total)


func _fail(reason: String, visible_to_player := true) -> void:
	state = "error"
	push_warning("Atualização: " + reason)
	if not visible_to_player or _panel == null:
		return
	_show("Atualização: " + reason, -1.0)
	await get_tree().create_timer(6.0).timeout
	if state == "error" and _panel:
		_panel.visible = false


## Instaladores de atualizações anteriores (já instaladas) são apagados ao abrir.
func _clean_old_downloads() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with("-setup.exe"):
			dir.remove(f)


# ---------------------------------------------------------------------------
# Aviso no canto
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.theme = Retro.theme()
	_panel.add_theme_stylebox_override("panel", Retro.panel_style(10.0, 0.88))
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.custom_minimum_size = Vector2(380, 0)
	_panel.position = Vector2(-400, -90)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 14)
	box.add_child(_label)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	_bar.max_value = 1.0
	_bar.step = 0.001
	box.add_child(_bar)


## progress < 0: só o texto.
func _show(text: String, progress: float) -> void:
	if _panel == null:
		return
	_panel.visible = true
	_label.text = text
	_bar.visible = progress >= 0.0
	_bar.value = maxf(progress, 0.0)
