@tool
class_name TrackLayout
extends Resource
## Descrição de um circuito: linha central (CSV), boxes e lista de elementos (TrackFeature).
## O RaceTrack gera toda a geometria a partir daqui; zebras e caixas de brita nas curvas
## também podem ser automáticas.

@export_file("*.csv") var centerline := ""
## Linha de corrida (CSV x,y) usada pelos bots; vazio = gerada pela curvatura.
@export_file("*.csv") var raceline := ""
## Folga (m) entre o centro do carro na linha de corrida e a borda da pista (pistas estreitas: mais).
@export var line_margin := 1.3
## Agressividade dos bots nesta pista (multiplica aderência e frenagem do perfil de velocidade).
@export var bot_pace := 1.0
## Distância (m) do 1º ponto do CSV até a linha de largada.
@export var start_offset := 0.0
@export var width_scale := 1.0
@export var min_half_width := 5.0
## Nome mostrado no menu.
@export var display_name := ""
## Bandeira do país nos mastros das arquibancadas: cores e estilo (TrackFlags.flagpole: 0 listras
## verticais, 1 faixas horizontais, 2 disco no centro sobre a 1ª cor).
@export var flag_colors := PackedColorArray([Color(0.1, 0.6, 0.3), Color(0.97, 0.97, 0.97), Color(0.86, 0.12, 0.17)])
@export var flag_style := 0

@export_group("Cidade")
## Dados de um circuito de rua (gerados por tools/build_monaco.py): terreno, costa, prédios, ruas,
## árvores, píeres e barcos. Com isso o RaceTrack gera a cidade, o mar e o túnel no lugar do
## campo (terreno com montanhas, árvores, folhagem, pinheiros, cenário e grama).
@export_file("*.json") var city := ""

@export_group("Relevo")
## Relevo de base do terreno dos circuitos de campo com subidas (gerado por tools/build_suzuka.py):
## grade de alturas suave presa à altura da pista; os morros somam por cima. Vazio = plano.
@export_file("*.json") var relief := ""

@export_group("Automático")
@export var auto_kerbs := true
## Raio máximo (m) de curva que recebe zebras.
@export var kerb_max_radius := 260.0
@export var kerb_width := 1.6
@export var auto_gravel := true
@export var gravel_max_radius := 160.0
@export var gravel_width := 22.0
## Afastamento padrão da barreira a partir da borda da pista.
@export var barrier_distance := 9.0

@export_group("Boxes")
@export var has_pit := true
## -1 = boxes à direita da reta, +1 = à esquerda.
@export var pit_side := -1
@export var pit_entry_s := -500.0
@export var pit_exit_s := 420.0
@export var pit_taper := 90.0
@export var pit_lane_width := 12.0
@export var garage_count := 20
@export var garage_width := 12.0
## Centro do prédio dos boxes (s).
@export var garage_center_s := 0.0
@export var pit_building_length := 560.0
## Profundidade do paddock atrás dos boxes (piso e motorhomes); 0 = sem paddock.
@export var paddock_depth := 75.0
@export var team_colors: PackedColorArray = PackedColorArray([
	Color("d7263d"), Color("1f5fd6"), Color("ff8a1d"), Color("12b886"), Color("7a2cf0"),
	Color("f2f2f2"), Color("e8256f"), Color("16161d"), Color("ffd23f"), Color("2ab7ca"),
])

@export_group("Largada")
@export var grid_slots := 20
@export var grid_spacing := 8.0
@export var grid_lateral := 2.6

@export_group("Elementos")
@export var features: Array[TrackFeature] = []
