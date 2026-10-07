class_name RaceEntry
extends RefCounted
## Estado de um piloto na corrida (jogador ou bot).

var car: F1Car
var bot: BotDriver
var is_player := false
## Rede: piloto humano (no servidor, todos os humanos têm is_player; no cliente, só o próprio carro)
## e o id da conta dele ("" para bots). index = posição fixa na lista de carros da corrida.
var is_human := false
var net_id := ""
var index := 0
## Rede (cliente): intervalo para o carro da frente, calculado pelo servidor.
var net_interval := ""
## Composto escolhido para o próximo pit stop e tempo que falta do pit stop em andamento (humanos).
var pit_compound := CarConfig.TyreCompound.HARD
var pit_timer := 0.0
## Pit stop: quando o carro parou na vaga (tempo de corrida) e quanto durou o último.
var pit_stop_start := 0.0
var last_pit_time := 0.0
var name := ""
var code := ""
var color := Color.WHITE
var grid_slot := 0
var garage := 0
var difficulty := -1

## Posição na pista (atualizada pelo RaceManager a cada passo de física)
var s := 0.0
var lateral := 0.0
## Vezes que cruzou a linha de chegada para frente (1 = começou a volta 1).
var crossings := 0
## Progresso total em metros: (crossings - 1) · comprimento + s.
var progress := 0.0
var position := 0
var race_time := 0.0

var lap_start := 0.0
var last_lap := 0.0
var best_lap := 0.0
var lap_times := PackedFloat32Array()
## Tempo de corrida em que passou por cada marca de progresso (para os intervalos).
var checkpoint_times := PackedFloat32Array()

var finished := false
var finished_and_parked := false
var finish_time := 0.0
var penalty_seconds := 0.0
var penalties: Array[String] = []
var track_limit_warnings := 0
var disqualified := false
## Abandonou (carro destruído).
var retired := false
var dsq_reason := ""

var pit_count := 0
var in_pit := false
var in_pit_stop := false
## Já fez a parada nesta passagem pelos boxes (só para outra depois de sair do pit lane).
var pit_served := false
## A volta em andamento não vale para melhor volta.
var lap_invalid := false
## Levado ao box pela ida rápida (botão, tempo esgotado ou bot): a volta em andamento recomeça —
## o próximo cruzamento da linha (saindo do box) só marca o início dela de novo, sem contá-la.
var lap_restart := false

## Número da volta em andamento (1 = primeira), para o HUD.
func current_lap() -> int:
	return crossings + (1 if lap_restart else 0)
var pit_speeding_flagged := false
var compounds_used: Array[int] = []

## Limites de pista: tempo fora, distância percorrida fora e s ao sair
var off_time := 0.0
var off_distance := 0.0
var off_start_progress := 0.0
## Carros logo à frente quando saiu da pista (para saber quem passou por fora).
var off_ahead: Array = []
var wrong_way_time := 0.0


func laps_completed() -> int:
	return maxi(crossings - 1, 0)


func total_time() -> float:
	return finish_time + penalty_seconds


## Tempo (corrida) em que passou pela marca de progresso `index`; -1 se ainda não passou.
func time_at_checkpoint(index: int) -> float:
	if index < 0 or index >= checkpoint_times.size():
		return -1.0
	return checkpoint_times[index]
