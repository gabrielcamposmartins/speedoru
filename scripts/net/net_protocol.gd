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
## Servidor oficial (VM em São Paulo, docker/server/compose.yml). Quem escolheu outro endereço na
## aba SERVIDOR continua nele: o escolhido fica salvo no aparelho.
const DEFAULT_HOST := "speedoru.padoru.org"
const MAX_CLIENTS := 64
## Servidores com nome guardados no aparelho e últimas conexões (tela de multiplayer).
const SAVED_SERVERS_MAX := 20
const SERVER_HISTORY_MAX := 8

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
## O mesmo por pista (Mônaco é bem mais curta; Suzuka tem o comprimento de Monza, mas bem mais curvas).
const MIN_LAP_BY_TRACK := {"monza": MIN_PLAUSIBLE_LAP, "monaco": 55.0, "suzuka": 85.0}


## Lê o endereço que o jogador digitou: "host", "host:porta", IPv6 puro ("2001:db8::1") ou IPv6
## com porta entre colchetes ("[2001:db8::1]:7350"). Devolve {host, port}; host "" se inválido.
static func parse_address(text: String, default_port := DEFAULT_PORT) -> Dictionary:
	var s := text.strip_edges()
	var host := s
	var port := default_port
	if s.begins_with("["):
		var close := s.find("]")
		if close < 0:
			return {"host": "", "port": default_port}
		host = s.substr(1, close - 1)
		var rest := s.substr(close + 1)
		if rest.begins_with(":"):
			port = _port(rest.substr(1))
		elif rest != "":
			port = -1
	elif s.count(":") == 1:
		# host:porta (IPv6 sem colchetes tem dois ou mais ":" e fica inteiro como host)
		host = s.get_slice(":", 0)
		port = _port(s.get_slice(":", 1))
	host = host.strip_edges()
	if host == "" or port <= 0 or host.contains(" "):
		return {"host": "", "port": default_port}
	return {"host": host, "port": port}


## Endereço para mostrar/guardar: IPv6 vai entre colchetes ("[::1]:7350").
static func format_address(host: String, port: int) -> String:
	return ("[%s]:%d" if host.contains(":") else "%s:%d") % [host, port]


## IPv6 na forma curta (sem zeros à esquerda, a maior sequência de zeros vira "::"), mais fácil de
## ditar: "2804:14c:0:0:0:0:0:11a8" -> "2804:14c::11a8". IPv4 e nomes voltam como estão.
static func compact_ipv6(ip: String) -> String:
	if not ip.contains(":") or ip.contains("::") or ip.count(":") != 7:
		return ip
	var parts := ip.to_lower().split(":")
	for i in parts.size():
		if not parts[i].is_valid_hex_number():
			return ip
		parts[i] = "%x" % parts[i].hex_to_int()
	# Maior sequência de "0" (de pelo menos dois grupos)
	var best := -1
	var best_len := 1
	var i := 0
	while i < parts.size():
		if parts[i] == "0":
			var j := i
			while j < parts.size() and parts[j] == "0":
				j += 1
			if j - i > best_len:
				best = i
				best_len = j - i
			i = j
		else:
			i += 1
	if best < 0:
		return ":".join(parts)
	return ":".join(parts.slice(0, best)) + "::" + ":".join(parts.slice(best + best_len))


static func _port(text: String) -> int:
	var t := text.strip_edges()
	if not t.is_valid_int():
		return -1
	var p := t.to_int()
	return p if p > 0 and p < 65536 else -1


## Este processo é o servidor dedicado (--server)? O servidor aberto pelo jogo roda no mesmo PC
## e na mesma pasta de dados: ele não grava o perfil nem as configurações do jogador.
static func is_server_process() -> bool:
	return "--server" in OS.get_cmdline_user_args() + OS.get_cmdline_args()


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
