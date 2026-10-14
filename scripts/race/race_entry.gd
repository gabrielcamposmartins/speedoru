class_name RaceEntry
extends RaceEntryCore
## Estado de um piloto na corrida (jogador ou bot).
## Os campos que mudam a cada passo de física ficam no RaceEntryCore (native/src/manager.rs): s,
## lateral, race_time, crossings, progress, position, retired, finished, finished_and_parked,
## finish_time, finish_laps, is_player, is_human, in_pit, in_pit_stop, pit_served, pit_speeding_flagged,
## pit_timer, pit_count, garage, off_time, off_distance, off_start_progress, track_limit_warnings,
## wrong_way_time e checkpoint_times.

var car: F1Car:
	set(value):
		car = value
		_core_car(value)
var bot: BotDriver:
	set(value):
		bot = value
		_core_bot(value)
## Rede: piloto humano (no servidor, todos os humanos têm is_player; no cliente, só o próprio carro)
## e o id da conta dele ("" para bots). index = posição fixa na lista de carros da corrida.
var net_id := ""
var index := 0
## Rede (cliente): intervalo para o carro da frente, calculado pelo servidor.
var net_interval := ""
## Composto escolhido para o próximo pit stop (humanos).
var pit_compound := CarConfig.TyreCompound.HARD
## Pit stop: quando o carro parou na vaga (tempo de corrida) e quanto durou o último.
var pit_stop_start := 0.0
var last_pit_time := 0.0
var name := ""
var code := ""
var color := Color.WHITE
var grid_slot := 0
var difficulty := -1

var lap_start := 0.0
var last_lap := 0.0
var best_lap := 0.0
var lap_times := PackedFloat32Array()

var penalty_seconds := 0.0
var penalties: Array[String] = []
## Detalhe de cada penalidade: [título, segundos, explicação, volta].
var penalty_log: Array = []
var disqualified := false
var dsq_reason := ""
## Online (servidor): batidas fortes causadas em outros jogadores nesta corrida (conquista Winged
## Death) e se venceu ultrapassando o líder humano na reta final (Nightmare).
var crashes_caused := 0
var nightmare := false
## Título equipado na conta (humanos; "" = nenhum): aparece na apresentação dos carros.
var title := ""

## A volta em andamento não vale para melhor volta.
var lap_invalid := false
## Levado ao box pela ida rápida (botão, tempo esgotado ou bot): a volta em andamento recomeça —
## o próximo cruzamento da linha (saindo do box) só marca o início dela de novo, sem contá-la.
var lap_restart := false

## Número da volta em andamento (1 = primeira), para o HUD.
func current_lap() -> int:
	return crossings + (1 if lap_restart else 0)
var compounds_used: Array[int] = []


## Voltas completadas; depois da bandeirada, as que tinha ao recebê-la (finish_laps: o carro segue
## andando e cruzando a linha, mas isso não conta).
func laps_completed() -> int:
	return finish_laps if finished else maxi(crossings - 1, 0)


func total_time() -> float:
	return finish_time + penalty_seconds


## Tempo (corrida) em que passou pela marca de progresso `index`; -1 se ainda não passou.
func time_at_checkpoint(index: int) -> float:
	if index < 0 or index >= checkpoint_times.size():
		return -1.0
	return checkpoint_times[index]
