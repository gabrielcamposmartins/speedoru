class_name RaceSettings
extends RefCounted
## Configuração da corrida escolhida no menu (sobrevive ao recarregar a cena).

enum Mode { RACE, PRACTICE }

## Pistas disponíveis (id, nome e cena).
const TRACKS := [
	{"id": "monza", "name": "Monza", "scene": "res://scenes/tracks/monza.tscn"},
	{"id": "monaco", "name": "Mônaco", "scene": "res://scenes/tracks/monaco.tscn"},
]
enum Grid { POLE, MIDDLE, BACK }

static var mode := Mode.RACE
## Pista escolhida (id de TRACKS).
static var track := "monza"
static var laps := 10
static var opponents := 9
## 0 fácil, 1 médio, 2 difícil, 3 misto
static var difficulty := 1
static var grid := Grid.MIDDLE
static var mandatory_pits := 1
## Pular o menu ao carregar a cena (botão "correr de novo").
static var skip_menu := false

## Horário (DaylightPresets.TimeOfDay) e ambiente (DaylightPresets.Biome) da corrida.
static var time_of_day := 0
static var biome := 0
## DRS: 0 = livre, 1 = só a até 1 s do carro da frente.
static var drs_rule := 0
## Classificatória antes da corrida: voltas cronometradas (0 = sem) e se os carros colidem nela.
static var quali_laps := 0
static var quali_collisions := true

## Tela que o menu principal abre ao voltar de uma corrida ("" = inicial, "multiplayer" = sala).
static var return_to := ""


static func track_index(id: String) -> int:
	for i in TRACKS.size():
		if TRACKS[i]["id"] == id:
			return i
	return 0


## Cena da pista (id desconhecido = a primeira).
static func track_scene(id: String) -> String:
	return TRACKS[track_index(id)]["scene"]


static func track_name(id: String) -> String:
	return TRACKS[track_index(id)]["name"]


static func valid_track(id: String) -> String:
	return TRACKS[track_index(id)]["id"]
