class_name RaceSettings
extends RefCounted
## Configuração da corrida escolhida no menu (sobrevive ao recarregar a cena).

enum Mode { RACE, PRACTICE }

## Pistas disponíveis (id, nome e cena).
const TRACKS := [
	{"id": "monza", "name": "Monza", "scene": "res://scenes/tracks/monza.tscn"},
	{"id": "monaco", "name": "Mônaco", "scene": "res://scenes/tracks/monaco.tscn"},
	{"id": "suzuka", "name": "Suzuka", "scene": "res://scenes/tracks/suzuka.tscn"},
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
## Classificatória antes da corrida: voltas cronometradas (índice de QUALI_LAP_NAMES: 0 = sem,
## 1-3 voltas, QUALI_FREE = livres até o tempo acabar), se os carros colidem nela, tempo limite
## (índice de QUALI_TIMES) e se infrações (sair da pista, penalidades) anulam a volta.
static var quali_laps := 0
static var quali_collisions := true
static var quali_time := 0
static var quali_strict := true

const QUALI_LAP_NAMES := ["Sem", "1 volta", "2 voltas", "3 voltas", "Livres (até o tempo acabar)"]
const QUALI_FREE := 4
## Tempo limite da classificatória (min; 0 = sem limite).
const QUALI_TIMES := [0, 3, 5, 10, 15]
const QUALI_TIME_NAMES := ["Sem limite", "3 min", "5 min", "10 min", "15 min"]
## Voltas livres sem tempo escolhido: a sessão dura isto (min).
const QUALI_FREE_MINUTES := 10

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


## Voltas cronometradas da classificatória para o índice do menu (-1 = livres).
static func quali_lap_count(index: int) -> int:
	return -1 if index >= QUALI_FREE else maxi(index, 0)


## Tempo limite (s) da classificatória para os índices do menu (0 = sem limite).
static func quali_seconds(lap_index: int, time_index: int) -> float:
	var minutes: int = QUALI_TIMES[clampi(time_index, 0, QUALI_TIMES.size() - 1)]
	if minutes == 0 and lap_index >= QUALI_FREE:
		minutes = QUALI_FREE_MINUTES
	return minutes * 60.0


static func valid_track(id: String) -> String:
	return TRACKS[track_index(id)]["id"]
