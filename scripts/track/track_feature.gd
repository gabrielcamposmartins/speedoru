@tool
class_name TrackFeature
extends Resource
## Um elemento posicionado ao longo da pista (s em metros a partir da linha de largada;
## valores negativos contam para trás a partir da largada). Editável no inspetor.

enum Kind {
	GRANDSTAND,     ## Arquibancada com público animado (rows = fileiras, roof = cobertura)
	SPECTATORS,     ## Público em pé sobre um barranco de grama
	GRAVEL,         ## Caixa de brita (distance = largura)
	BARRIER,        ## Muda a barreira no trecho (distance = afastamento; variant 0 guard-rail, 1 concreto)
	BARRIER_ADS,    ## Placas de anúncio na face da barreira
	BILLBOARD,      ## Painéis de anúncio grandes sobre pernas (spacing = intervalo)
	LIGHTS,         ## Postes de iluminação (spacing = intervalo)
	AD_BRIDGE,      ## Pórtico de anúncios sobre a pista (em s_start)
	START_GANTRY,   ## Pórtico com as luzes de largada (em s_start)
	BRAKE_MARKERS,  ## Placas 200/150/100/50 antes de s_start
	BUNTING,        ## Bandeirolas ao longo das cercas e cruzando por cima da pista (spacing = intervalo das travessias)
	FERRIS_WHEEL,   ## Roda-gigante (em s_start; distance = afastamento além da barreira, rows = diâmetro em m)
}
enum Side { LEFT, RIGHT, BOTH }

@export var kind := Kind.GRANDSTAND
@export var label := ""
@export var s_start := 0.0
@export var s_end := 0.0
@export var side := Side.LEFT
## Afastamento atrás da barreira (ou largura, para GRAVEL / BARRIER).
@export var distance := 2.0
@export var rows := 12
@export var spacing := 40.0
@export var roof := false
@export var variant := 0


func sides() -> Array[int]:
	match side:
		Side.LEFT:
			return [1]
		Side.RIGHT:
			return [-1]
	return [1, -1]


## Comprimento do trecho (considera a volta: s_end < s_start atravessa a largada).
func span_length(track_length: float) -> float:
	return fposmod(s_end - s_start, track_length) if s_end != s_start else 0.0
