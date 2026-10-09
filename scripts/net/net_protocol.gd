class_name NetProtocol
extends RefCounted
## Constantes e regras compartilhadas entre o servidor dedicado e o cliente.
##
## Transporte: ENet (Godot high-level multiplayer). Mensagens de lobby/conta são um RPC genérico
## `msg(type, data)` confiável nos dois sentidos; a corrida usa RPCs próprios: o cliente manda os
## comandos (`inp`, não confiável e em ordem) e o servidor manda instantâneos de todos os carros
## (`snap`, não confiável) e o estado da prova (`race`, confiável, ~5 por segundo).
##
## Regras de amigos/grupo/ranking/perfil/nível seguem o documento "Pokeru — Regras de amigos,
## ranking e perfil", adaptadas para corridas.

const VERSION := 5
## O servidor aceita o carro (skins, peças e engenharia) que o jogador traz do aparelho, sem
## conferir se a conta tem os itens.
## PENDENTE (produção): desligar e validar no servidor que a conta tem as skins e peças.
const TRUST_CLIENT_CAR := true
const DEFAULT_PORT := 7350
const DEFAULT_HOST := "127.0.0.1"
const MAX_CLIENTS := 64

# --- Amigos ----------------------------------------------------------------------
## Sem 0/O, 1/I/L (para ditar o código em voz alta).
const CODE_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const MAX_FRIENDS := 100
const MAX_REQUESTS := 50
const MAX_PARTY := 4

# --- Salas -----------------------------------------------------------------------
const MAX_ROOM_PLAYERS := 10
const ROOM_LAPS := [3, 5, 10, 15]
## Corredores no grid de uma sala custom (jogadores + bots). O máximo cabe nos boxes de todas as pistas.
const ROOM_CARS := [2, 4, 6, 8, 10, 12, 14]
const MAX_GRID := 14

# --- Perfil ------------------------------------------------------------------------
const NAME_MAX := 16
const HISTORY_SIZE := 5
const TRAITS_WINDOW := 10

# --- Ranking ---------------------------------------------------------------------
const RANKING_ROWS := 50
const RANKING_CACHE_S := 15.0
const RANKING_TAB_POINTS := 1000

# --- Corrida em rede ---------------------------------------------------------------
const SNAPSHOT_HZ := 30.0
const RACE_STATE_HZ := 5.0
## Atraso de interpolação no cliente (s): mostra o passado recente, sempre entre dois instantâneos.
const INTERP_DELAY := 0.1

# Bits dos botões no comando contínuo (inp)
const BTN_DRS := 1
const BTN_BOOST := 2
const BTN_REVERSE := 4

## Volta mais rápida plausível em Monza (s): resultados de corrida solo abaixo disso são recusados.
const MIN_PLAUSIBLE_LAP := 78.0
## O mesmo por pista (Mônaco é bem mais curta).
const MIN_LAP_BY_TRACK := {"monza": MIN_PLAUSIBLE_LAP, "monaco": 55.0}


static func min_lap(track: String) -> float:
	return MIN_LAP_BY_TRACK.get(track, MIN_PLAUSIBLE_LAP)


## Normaliza o que o jogador digitou ("abc 234", "ABC-234", "abc234") para "ABC234"; "" se inválido.
static func normalize_code(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		if ch == " " or ch == "-":
			continue
		if not CODE_ALPHABET.contains(ch):
			return ""
		out += ch
	return out if out.length() == 6 else ""


static func format_code(code: String) -> String:
	return code.substr(0, 3) + "-" + code.substr(3, 3) if code.length() == 6 else code


static func random_code(rng: RandomNumberGenerator) -> String:
	var out := ""
	for i in 6:
		out += CODE_ALPHABET[rng.randi_range(0, CODE_ALPHABET.length() - 1)]
	return out


## Nome: até 16 caracteres, sem caracteres de controle; vazio vira "Jogador".
static func clean_name(text: String) -> String:
	var out := ""
	for ch in text.strip_edges():
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	out = out.strip_edges().substr(0, NAME_MAX)
	return out if out != "" else "Jogador"
