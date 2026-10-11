class_name BotDriver
extends BotDriverCore
## Piloto controlado pelo computador. Filho do F1Car (que fica com player_controlled = false);
## roda antes dele em cada passo de física e escreve throttle/brake/steer.
##
## A lógica roda no código nativo (BotDriverCore, native/src/bot.rs); aqui ficam as constantes, os
## enums e a ligação com o carro, a pista e a corrida.
##
## * Direção: "pure pursuit" num ponto à frente na linha de corrida (+ deslocamento lateral para
##   ultrapassar/desviar ou para entrar nos boxes).
## * Velocidade: perfil da linha (RacingLine.speed_profile) para a dificuldade; segue o carro da
##   frente quando não dá para passar.
## * Ultrapassagem sem medo: começa com reta suficiente (90 m) e um pouco mais rápido que o da
##   frente, segue perto (pega o vácuo) e não desiste já lado a lado na entrada da curva; evita a
##   batida abrindo espaço lado a lado, tirando o pé se sobrepõe e só voltando para a linha 10 m à
##   frente de quem passou.
## * Pit stop: na volta escolhida entra nos boxes, respeita 80 km/h, para no box da equipe, troca
##   os pneus e volta à pista. Só vai para a faixa da vaga nos últimos 18 m (não passa por cima das
##   vagas vizinhas) e, na pista dos boxes, espera qualquer carro que esteja no caminho que vai
##   fazer — inclusive parado na vaga e humanos.
## * Preso (encostado no muro, rodado, parado sem avançar): dá ré esterçando para apontar de volta
##   para a pista (até 3 vezes); se não sair, é levado de volta à pista num vão do tráfego.
## * Jogadores humanos: todos os bots deixam mais espaço (seguem com folga maior e enxergam uma faixa
##   mais larga em volta deles), sem frear nem desviar instantâneo — a batida continua possível.
##   Bots fácil e médio respeitam ataques: com um humano chegando por trás (até 25 m) ou lado a
##   lado, abrem para o outro lado e tiram um pouco o pé; o difícil defende a posição.
##   Sob bandeira amarela ninguém dá passagem (ultrapassar é proibido).
##
## Propriedades do BotDriverCore: profile, difficulty, mode, pit_lap, pit_compound, released,
## start_lateral; reaction_time(), force_pit_stop(seconds).

enum Difficulty { EASY, MEDIUM, HARD }
enum Mode { RACE, PIT_IN, PIT_STOP, PIT_OUT }

## [aderência, frenagem, aceleração, reação na largada (min, max), ruído lateral, tempo de pit]
## (reação e ruído também estão em native/src/bot.rs)
const PRESETS := {
	Difficulty.EASY: [0.84, 0.74, 0.92, Vector2(0.45, 0.8), 0.7, 3.4],
	Difficulty.MEDIUM: [0.91, 0.84, 0.97, Vector2(0.28, 0.5), 0.35, 2.9],
	Difficulty.HARD: [0.96, 0.92, 1.0, Vector2(0.17, 0.3), 0.12, 2.5],
}
const NAMES := ["Fácil", "Médio", "Difícil"]

var car: F1Car
var track: RaceTrack
var line: RacingLine
var entry: RaceEntry
var manager: RaceManager

## Contadores (testes/diagnóstico): ré para sair do muro e volta à pista.
static var reversals: int:
	get:
		return BotDriverCore.reversal_count()
static var put_backs: int:
	get:
		return BotDriverCore.put_back_count()


func setup(p_car: F1Car, p_track: RaceTrack, p_line: RacingLine, p_profile: PackedFloat32Array,
		p_difficulty: Difficulty, p_entry: RaceEntry, p_manager: RaceManager) -> void:
	car = p_car
	track = p_track
	line = p_line
	profile = p_profile
	difficulty = p_difficulty
	entry = p_entry
	manager = p_manager
	process_physics_priority = -10
	_core_setup(p_car, p_track, p_line.native, p_entry, p_manager)
