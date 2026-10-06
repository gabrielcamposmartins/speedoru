class_name RaceSettings
extends RefCounted
## Configuração da corrida escolhida no menu (sobrevive ao recarregar a cena).

enum Mode { RACE, PRACTICE }
enum Grid { POLE, MIDDLE, BACK }

static var mode := Mode.RACE
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

## Tela que o menu principal abre ao voltar de uma corrida ("" = inicial, "multiplayer" = sala).
static var return_to := ""
