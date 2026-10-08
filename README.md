# F1 Gatcha

Jogo 3D de Fórmula 1 em estilo anime — **Godot 4.7** (Forward+) + **Blender 5.0**.

## Rodar

Abra a pasta no Godot 4.7 e aperte F5. A cena principal é `scenes/boot.tscn`, que abre a tela de
carregamento e carrega o menu principal (`scenes/menu/main_menu.tscn`, a garagem) por trás dela.
Jogar solo leva a `scenes/tracks/monza.tscn` (F6 nela também funciona, com o menu de corrida antigo
e sem a tela de carregamento). A área de testes antiga continua em `scenes/test/test_track.tscn`.

### Menu principal (garagem)

`scripts/menu/main_menu.gd` monta a garagem (piso brilhante, plataforma com anel de neon, paredes
com faixas de luz, bancadas, pneus, letreiro) e o carro do jogador com o que está equipado,
pousado na plataforma. A câmera fica a nordeste do carro (frente-direita) e orbita devagar; arrastar
com o mouse gira, a roda aproxima. O carro fica à direita; à esquerda, os botões grandes
(`scripts/menu/menu_ui.gd`):

- **Jogar solo:** pista (Monza ou Mônaco), modo, voltas, adversários, dificuldade, largada, horário
  e ambiente → Correr. Na corrida o horário/ambiente ficam como escolhidos (N/B só no treino livre) e
  o carro não muda: a garagem do Tab só existe no treino livre (e pausa o jogo enquanto aberta).
- **Multiplayer:** salas, amigos, grupo, ranking e perfil (veja [Multiplayer](#multiplayer-servidor-dedicado--turso)); convites e avisos aparecem em qualquer tela do menu.
- **Garagem:** Estúdio, Galeria e Loja, com o carro mudando na hora ao lado. No Estúdio e na
  Galeria o painel é compacto e fica à direita (o carro vem para o centro-esquerda); a Loja usa o
  painel largo à esquerda. **Cenário** da garagem (salvo no perfil):
  - *Garagem neon* (noite): piso de concreto polido em placas, paredes de painéis metálicos,
    plataforma com anel de luz, elevador de carros, estantes, carrinhos de ferramentas, tambores,
    caixotes, máquina de bebidas, cartazes e letreiros de neon.
  - *Ao sol*: pátio de concreto em placas, asfalto com manchas, prédio dos boxes com portas
    numeradas, arquibancada ao longe, tenda da equipe, motorhome, guarda-sóis, cerca, barreira de
    pneus, bandeiras e árvores.
  - *No box*: piso de epóxi com rejunte, tapetes de borracha, paredes de painéis com emendas e
    cartazes, carrinhos e quadro de ferramentas, rack de pneus com mantas térmicas, pistolas de roda,
    macacos, asa reserva, mesa dos engenheiros com monitores, relógio e a porta aberta para o pit
    lane.

  Pisos e paredes usam várias texturas procedurais por material (cor com manchas, sujeira ou
  rejunte/emendas multiplicados, normal map e rugosidade variando), em mapeamento triplanar.
- **Configurações** e **Sair**.

"Menu principal" na pausa ou no resultado da corrida volta para cá.

### Tela de carregamento

Autoload `Loading` (`scripts/ui/loading_screen.gd`): arte `assets/ui/speedoru.png` em tela cheia
(enquadrada pelo topo, com zoom lento), barra inclinada em degradê azul → roxo → rosa com
porcentagem, nome da etapa e uma dica. Aparece sempre que algo carrega:

* **Abrir/reiniciar o circuito** (`Loading.change_scene(path)`): 0–25 % é o arquivo da cena
  (carregado numa thread), 25–95 % é a geração da pista em etapas (asfalto, barreiras, boxes,
  arquibancadas, terreno, árvores, folhagem, pinheiros, cenário, grama), com a árvore pausada até o
  chão existir. O `RaceTrack` só gera em etapas quando a tela está aberta; no editor e nos testes
  continua gerando tudo de uma vez.
* **Montar a corrida** (ao apertar INICIAR): linha ideal e um passo por carro colocado no grid.
* O splash do Godot usa `assets/ui/speedoru_splash.png` (o mesmo recorte 16:9), então a troca do
  splash para a tela de carregamento não dá pulo.

Para mostrar em outro carregamento: `LoadingScreen.start("Texto")`,
`LoadingScreen.report_progress(0.5, "Etapa")` e `LoadingScreen.done()`.

| Ação | Teclado | Controle |
|---|---|---|
| Acelerar | W / ↑ | RT |
| Frear | Espaço | LT |
| Esterçar | A / D | analógico esquerdo |
| Ré no automático (com o carro parado; acelerar volta para a 1ª) | S / ↓ | B |
| DRS (acima de 80 km/h) | Shift | A |
| Boost da bateria (segurar) | Alt esquerdo | D-pad → |
| Marchas (manual: R ↔ N ↔ 1 ↔ 2 …; a ré só engata parado e anda com o acelerador; S não faz nada) | Q / E | LB / RB |
| Câmbio automático/manual | G | X |
| Controle de tração liga/desliga | T | — |
| Balanço de freio (dianteira +/−) | ] / [ | D-pad ↑ / ↓ |
| Trocar câmera | C | Y |
| Olhar para trás (segurar) | V | R3 |
| Câmera em órbita (liga/desliga) | O (arrastar mouse = girar, roda = zoom) | L3 + analógico direito |
| Recolocar o carro | R | Back |
| Reparar o carro | F (ou botão na garagem) | — |
| Música liga/desliga | M (volume e faixa em Configurações → Áudio) | — |
| Horário (dia → entardecer → noite) | N (ou garagem) | — |
| Pausa (reiniciar / menu / configurações) | Esc | — |
| Configurações (dentro e fora da corrida) | F10 | — |
| Linha ideal (desligada → frenagens e curvas → completa) | L | — |
| Limitador de velocidade (80 km/h: boxes e bandeira amarela) | P | D-pad ← |
| Ir aos boxes depois de uma batida forte | K | Back |
| Pedir passagem (pisca 4× a luz âmbar dos retrovisores) | X | Share |
| Menus: navegar / confirmar / voltar | setas · Enter · Esc | D-pad ou analógico · A · B |
| Menus: abas da garagem e das configurações | — | LB / RB |
| Pausa (na pista; a garagem abre pela pausa) | Esc | Start |
| Páginas da classificação | PgUp / PgDn | — |
| Pneu do próximo pit stop | 1 macio · 2 médio · 3 duro | — |
| Mostrar/esconder ajuda | H | — |
| Ambiente (verão → outono → sakura → fantasia) | B (ou garagem) | — |
| Garagem (peças e pintura) | Tab | Start |

## Instalar (Windows)

Baixe o instalador da [última release](https://github.com/gabrielcamposmartins/speedoru/releases/latest)
— o link fixo `https://github.com/gabrielcamposmartins/speedoru/releases/latest/download/Speedoru-setup.exe`
sempre aponta para a versão mais nova. Ele instala só para o usuário atual, sem pedir
administrador, em `%LOCALAPPDATA%\Programs\Speedoru` (atalho no menu Iniciar e, se marcado, na
área de trabalho). Para atualizar, instale a versão nova por cima. Perfil, configurações e conta
ficam em `%APPDATA%\Godotpp_userdata\F1 Gatcha` e continuam depois de atualizar ou desinstalar.

O instalador não é assinado com certificado de código, então o SmartScreen avisa na primeira vez:
*Mais informações* → *Executar assim mesmo*. Cada release publica o `SHA256SUMS.txt`
(`Get-FileHash .\Speedoru-setup.exe -Algorithm SHA256` no PowerShell para conferir).

**Atualização automática:** ao abrir, o jogo instalado consulta a última release no GitHub; se
houver versão mais nova, baixa o `Speedoru-setup.exe`, confere o SHA-256 com o `SHA256SUMS.txt`
da release, roda o instalador em silêncio (`/VERYSILENT`, sem janela nem administrador) e fecha;
o instalador termina e abre o jogo de novo. Um aviso no canto mostra o progresso; sem internet ou
sem release, o jogo abre normalmente. Se o download terminar no meio de uma corrida, a instalação
espera a volta ao menu. Desliga em **Configurações → Jogo → Atualizar o jogo sozinho ao abrir**
(`scripts/update/auto_updater.gd`; não roda no editor, no servidor dedicado nem com `--no-update`).
Quem está na 0.1.0 precisa instalar a 0.2.0 na mão uma vez (a 0.1.0 não tinha o atualizador).

A pasta do jogo tem também o `Speedoru.console.exe` (o mesmo jogo, com console), que roda o
servidor dedicado: `Speedoru.console.exe --headless -- --server --db-url=... --db-token=...`
(veja [Multiplayer](#multiplayer-servidor-dedicado--turso)).

## Publicar uma versão

A publicação é automática: **criar uma tag `vX.Y.Z` na main** dispara a action
(`.github/workflows/release.yml`), que baixa o Godot 4.7 e os templates de exportação de Windows
(em cache entre execuções), importa o projeto, roda os testes rápidos (`compile_check`, economia,
configurações, câmbio, menus pelo controle), exporta o jogo (preset "Windows Desktop" de
`export_presets.cfg`: um `Speedoru.exe` com o pacote embutido + `Speedoru.console.exe`), monta o
instalador com o Inno Setup (`installer/speedoru.iss`) e cria a release com
`Speedoru-X.Y.Z-setup.exe`, a cópia `Speedoru-setup.exe` (o link fixo) e o `SHA256SUMS.txt`.

```bash
# troque config/version no project.godot (Projeto → Configurações → Aplicação → Versão)
git commit -am "Versão 0.2.0" && git push origin main
git tag v0.2.0 && git push origin v0.2.0
```

A action confere se a tag aponta para um commit da **main** e se a versão do `project.godot` bate
com a tag. Ela também roda à mão em *Actions → Release → Run workflow* (escolhendo a tag), útil
para repetir uma publicação que falhou.

**Exportar na mão** (com os templates do Godot 4.7 instalados no editor):

```bash
mkdir -p build/windows
godot --headless --path . --export-release "Windows Desktop" build/windows/Speedoru.exe
iscc /DAppVersion=0.2.0 installer\speedoru.iss     # gera build/installer/Speedoru-0.2.0-setup.exe
```

## O carro (escala real)

Gerado proceduralmente por `blender/build_f1_car.py` (regulamento 2022–2025, aproximado):
5,6 m de comprimento · 1,98 m de largura · entre-eixos de 3,6 m · rodas de 720 mm (aro de 18") ·
pneus de 305/405 mm · 800 kg.

Cada peça é um `.glb` separado em `assets/car/parts/<slot>/<variante>.glb`:

| Slot | Variantes |
|---|---|
| `chassis` (monocoque com cockpit) | standard |
| `nose` | standard, pointed |
| `front_wing` | standard (4 elementos), lowdf (3 elementos) |
| `rear_wing` (+ beam wing, `DRSFlap` animado) | standard, lowdf, highdf |
| `sidepods` | downwash, slim |
| `engine_cover` (airbox, T-cam, estrutura de impacto, luz de chuva) | standard, sharkfin |
| `floor` (assoalho, difusor, prancha) | standard |
| `halo`, `mirrors`, `suspension_front`, `suspension_rear` | standard |
| `cockpit` (`SteeringWheel` animado, encostos) | standard |
| `driver` (piloto humanoide: macacão, luvas, botas, HANS, cintos, capacete com viseira) | standard |
| `tyre` (`_front` / `_rear`) | slick |
| `rim` (`_front` / `_rear`) | covered, spoked |

Para regenerar tudo (glb + `blender/f1_car.blend` + imagens em `blender/renders/`):

```
"C:\Program Files\Blender Foundation\Blender 5.0\blender.exe" -b -P blender/build_f1_car.py
```

`-- --only=driver` (ou outra lista de slots separados por vírgula) exporta só essas peças.

**Piloto** (`build_driver`): humanoide de ~1,75 m sentado no cockpit (~6,8 mil triângulos, shade
smooth): tronco reclinado com o quadril no fundo do monocoque, joelhos logo abaixo do volante, pés
nos pedais dentro do bico (botas com sola, salto e biqueira, tira de velcro e cano), luvas com
punho largo sobre a manga, HANS de carbono, cinto de 6 pontos com fivela e capacete com queixeira,
viseira em relevo e aerofólio. As juntas usam calotas arredondadas (deltoide entrando no tronco,
glúteo na base do tronco) com pesos de pele divididos entre os ossos. Cores: macacão `Suit`,
faixas `Livery_Secondary`, luvas/botas/gola `Livery_Accent`, capacete `Helmet`. Prévia sem trocar a
peça: `blender ... -- --driver-preview <pasta>` (renders sozinho, no carro e em raio-x + `.glb`) e
`godot --path . -s res://tests/capture_driver.gd -- <pasta>/driver_preview.glb <pasta>` (o `.glb` no
carro do jogo, com o IK, de fora e da câmera do piloto).

Convenções: todas as peças compartilham a origem do carro (chão, meio do entre-eixos), com a frente
em +Z e a esquerda em +X no Godot. Os **nomes dos materiais são slots de pintura** (`Livery_Primary`,
`Livery_Secondary`, `Livery_Accent`, `Carbon`, `Rim`, `Helmet`, `Suit`, `Tire_Stripe`...) que o Godot
troca por materiais toon (`scripts/car/car_livery.gd`).

### Adicionar uma variante de peça

1. No script do Blender, crie a função/variante e registre em `PART_BUILDERS` (ou `WHEEL_BUILDERS`).
2. Rode o script para exportar o `.glb`.
3. Registre a variante em `scripts/car/car_part_catalog.gd` (rótulo e `stats` aerodinâmicos).
   A garagem passa a mostrá-la sozinha.

## Estrutura no Godot

- `scenes/car/f1_car.tscn` — `VehicleBody3D` (800 kg, centro de massa customizado) com 4 `VehicleWheel3D`
  e caixas de colisão. O nó `Visual` (`CarAssembly`) instancia as peças conforme o `CarConfig`.
- `scripts/car/f1_car.gd` — motor (curva de torque + limite de 760 kW), câmbio de 8 marchas, ré,
  controle de tração, freios limitados pela carga, downforce ∝ v² dividida entre os eixos, arrasto,
  DRS e animação do flap/volante. Entradas em `throttle_input`, `brake_input`, `steer_input` (prontas
  para IA quando `player_controlled = false`).
- **Modelo de pneu** (em `f1_car.gd`, `_update_tires`): o atrito embutido do VehicleBody3D é desligado
  e cada pneu calcula a própria força:
  - carga vertical por roda (a compressão das molas divide peso + downforce entre as rodas →
    transferência de peso em curva, frenagem e aceleração);
  - força lateral pela curva de Pacejka em função do ângulo de deriva, com pico em ~6° e queda
    depois dele; μ diminui com a carga;
  - elipse de atrito: frear/acelerar consome aderência lateral; acima do limite a roda **trava**
    ou **patina** e quase não segura de lado.
  Resultado: **subesterço** ao esterçar demais ou frear em curva com a frente travada, e
  **sobreesterço** ao acelerar forte na saída de curva (principalmente sem controle de tração).
  Assistências (controle de tração e de freio) ficam na garagem; elas reservam aderência lateral.
  O HUD mostra o uso de aderência de cada pneu; os pneus soltam
  fumaça quando deslizam. Parâmetros no grupo "Pneus" do inspetor (`front_grip`, `rear_grip`,
  `peak_slip_angle_deg`, `tire_shape`, `load_sensitivity`...).
- **Câmeras** (`scripts/camera/race_camera.gd`): perseguição, perseguição longe, T-Cam, piloto
  (1ª pessoa) e capô (só rodas da frente, bico e retrovisores); órbita separada.
  - *Perseguição*: com vida — afasta ao acelerar/no boost e aproxima na frenagem, desliza para
    fora e inclina um pouco nas curvas olhando para dentro delas, acompanha a derrapagem, treme de
    leve em alta velocidade e nas zebras, bem mais fora da pista (brita sacode mais que a grama,
    `shake_offtrack`) e forte nas batidas; o FOV abre no boost. As
    forças G são medidas no passo de física (sem picos quando o FPS difere da física). Toques
    pequenos no volante quase não mexem a câmera (desvios abaixo de ~8° são seguidos devagar e o
    olhar/deslize têm zona morta); curvas de verdade, na velocidade normal.
  - *Apresentação antes da largada* (`IntroDirector`): com os carros no grid, a câmera passa por
    cada um do pole para trás (close pela frente, legenda "P3 · nome · dificuldade") e termina
    numa órbita no seu carro que entrega para a perseguição; depois vem o semáforo. O HUD some
    durante a apresentação; Enter / A pula; desliga em Configurações → Jogo. No online o servidor
    espera a duração dela antes das luzes (todos largam juntos).
  - *Piloto*: olhos do piloto com a cabeça escondida (camada de render `CarAssembly.HEAD_LAYER`),
    inércia da cabeça com as forças G e olhar acompanhando o esterço; vê braços, volante girando
    com display e os retrovisores.
  - *Olhar para trás*: nas externas a câmera dá a volta até a frente do carro; na 1ª pessoa o
    piloto foca o retrovisor (esquerdo, ou direito se esterçando à direita); nas de bordo usa a
    lente traseira.
  - *Órbita*: gira em volta do carro (gira sozinha quando parada); um raycast impede atravessar
    objetos, outro mantém a câmera acima do chão, e um envelope elíptico impede entrar no carro.
- `scripts/car/car_onboard.gd` — retrovisores funcionais (câmeras traseiras em SubViewports,
  imagem espelhada sobre os vidros `MirrorGlassL/R`) e display do volante
  (`scripts/ui/steering_display.gd`: luzes de troca, marcha, velocidade, giro, balanço de freio,
  TC, DRS, composto).
- `scripts/car/driver_rig.gd` — IK dos braços do piloto (`TwoBoneIK3D` + `CopyTransformModifier3D`,
  criados em tempo de execução dentro do `Skeleton3D` da peça `driver`): as mãos ficam presas às
  manoplas, os punhos giram com o volante e os cotovelos seguem um polo calculado da pose de repouso.
  **Trocar o personagem:** exporte um `.glb` para `assets/car/parts/driver/` com um esqueleto que use
  os nomes do perfil humanoide do Godot (`LeftUpperArm`, `LeftLowerArm`, `LeftHand` e os `Right…`;
  ou ajuste os nomes no inspetor do nó `DriverRig`). Malhas chamadas `DriverHelmet*` são escondidas
  na câmera de 1ª pessoa. Não é preciso que as mãos já estejam no volante: com `snap_to_grips` o IK
  leva a palma até as manoplas.
- `scripts/car/car_config.gd` — recurso com peças, cores e composto de pneu (`resources/cars/default_car.tres`).
- `shaders/outline_post.gdshader` — contorno anime em tela cheia (profundidade + normais).
- `scripts/track/test_circuit.gd` — circuito de teste procedural (editável pelos pontos de controle).

## Modo de jogo (corrida)

Ao abrir a cena aparece o menu (`RaceModeHud`): **Corrida** (3–20 voltas, padrão 10, com 1 pit stop
obrigatório) ou **Treino livre**; número de adversários (3–13), dificuldade dos bots (fácil, médio,
difícil ou mista) e posição de largada. Tudo em `scripts/race/`:

- **`RaceManager`** (nó na cena de Monza): grid, luzes de largada, contagem de voltas pela linha de
  chegada, tempos de volta, volta mais rápida, intervalos (marcas de progresso a cada 25 m),
  posições, pit stops e chegada; ao final mostra o resultado (tempo + penalidades) e permite
  correr de novo.
- **Bots** (`BotDriver`, filho de cada carro): seguem a linha de corrida de curvatura mínima de Monza
  (`assets/track/monza/monza_raceline.csv`, TUMFTM) com um perfil de velocidade calculado pela
  aderência lateral/downforce, frenagem e potência (`RacingLine`), escalado pela dificuldade
  (fácil 84% da aderência, médio 91%, difícil 97,5%; reação na largada e ruído de trajetória).
  Mantêm a faixa do grid na largada, ultrapassam só em retas (escolhem um lado e mantêm até
  passar), seguem com folga nas curvas, fazem o pit stop numa volta sorteada (80 km/h nos boxes,
  param no box da equipe, trocam para duro/médio) e se recuperam sozinhos se ficarem presos.
  Usam os mesmos carros e a mesma física do jogador (sem retrovisores, mais leves). Um bot
  que perde uma roda abandona (DNF). Na corrida o reparo instantâneo (F) fica desligado.
  Com jogadores humanos: todos deixam mais espaço (folga maior atrás de você e uma faixa mais
  larga em volta), sem frear nem desviar instantâneo — a batida continua possível. Bots fácil e
  médio **respeitam ataques**: com você chegando por trás (até 25 m, mais rápido) ou lado a lado,
  abrem para o outro lado e tiram um pouco o pé (10% / 5%); o difícil defende a posição. Sob
  bandeira amarela ninguém dá passagem (`tests/bot_yield_test.gd`).
- **Pneus:** desgaste por roda conforme a potência dissipada no contato (escorregar, travar,
  patinar, curva no limite) e o composto (macio gasta ~55% mais rápido, duro ~32% mais devagar);
  pneu gasto perde até 32% de aderência. O HUD mostra quanto resta de cada pneu.
- **Boxes:** a entrada fica logo depois da Parabolica; o retângulo da sua vaga ganha uma borda
  luminosa discreta (linha no chão e um véu baixo pulsando, `shaders/track/pit_box_glow.gdshader`); pare na
  vaga para o pit stop (sorteado entre 2 e 4 s a cada parada, + 5 s se precisar trocar peças
  danificadas; ao sair aparece "PIT STOP 2,8 s"); 1/2/3 escolhem o composto; mecânicos da equipe
  aparecem em volta do carro. Os bots também param de 2 a 4 s.
- **Penalidades** (iguais para todos; as do jogador aparecem num banner grande na lateral):
  limites de pista (todas as rodas fora do asfalto/zebra: 3 avisos, depois +5 s por infração),
  cortar a pista e ganhar vantagem (+5 s), colisão causada — quem bate por trás e mais rápido —
  (+5 s, ou +10 s se forte), largada queimada (+10 s), mais de 80 km/h nos boxes (+5 s), pit stop
  obrigatório não cumprido (desclassificação). Contramão gera aviso.
- **HUD da corrida:** classificação no canto superior esquerdo em páginas de 5 (PgUp/PgDn; se você
  não está na página, a 5ª linha mostra você), com intervalo para o da frente, composto, BOX,
  penalidades e um relógio roxo em quem tem a volta mais rápida; minimapa no canto superior
  direito; no centro, a posição, o **tempo da volta em destaque** (ao fechar uma volta, o tempo
  dela fica grande por 5 s: roxo se é a mais rápida da corrida, verde se é o seu recorde, amarelo
  nos outros casos, com a diferença para o seu melhor), última e melhor volta, a linha **VOLTA MAIS
  RÁPIDA · piloto · tempo** (pisca em roxo quando alguém bate o recorde) e o status do pit.
- **DRS** (escolhido ao criar a corrida — Jogar solo ou ajustes da sala): **livre** ou **só a até
  1 s do carro da frente** (tempo nas marcas de progresso, as mesmas dos intervalos; o líder e quem
  está nos boxes não têm). Com a regra, o "DRS" do painel fica destacado quando está disponível e
  apagado quando não está, e aparece **"DRS LIBERADO"** no centro da tela quando passa a valer.
- **Devolver a posição:** ganhar uma posição de forma irregular — ultrapassar sob bandeira amarela
  ou passar alguém por fora da pista — mostra **"DEVOLVA A POSIÇÃO PARA XXX"** com contagem de 12 s;
  deixando o carro passar, fica sem penalidade ("POSIÇÃO DEVOLVIDA"); senão, +5 s. Vale para o
  jogador (os bots são punidos na hora) (`tests/give_back_test.gd`). No online o servidor decide (`tests/drs_rule_test.gd`).
- **Vácuo** (`scripts/race/slipstream.gd`): atrás de outro carro, a mais de ~80 km/h, há uma faixa
  no rastro dele onde o **arrasto aerodinâmico some** — total colado (3–14 m) e no centro, sumindo
  até 42 m e para os lados (a faixa abre um pouco com a distância). Vale para todos (bots e
  online; o servidor calcula). Pista visual: filetes de vento saem do bico do carro da frente,
  contornam a carroceria dele e correm até o seu carro (`scripts/race/slipstream_fx.gd`, mais
  fortes e numerosos quanto maior o vácuo), as linhas de velocidade ficam azuladas e o painel
  mostra "VÁCUO" aceso no lugar do câmbio (`tests/slipstream_test.gd`:
  em roda livre a 250 km/h o carro perde 28 km/h em 1 s sozinho e 11 km/h no vácuo).
- **Classificatória** (`scripts/race/qualifying.gd`; escolhida no Jogar solo, no menu da corrida e
  na sala online): sem, 1, 2 ou 3 voltas cronometradas ou **voltas livres** até o tempo acabar, com
  ou sem colisão entre os carros, **tempo limite** (sem limite, 3, 5, 10 ou 15 min; voltas livres
  sem tempo escolhido = 10 min) e a opção **"infração anula a volta"**. Os carros saem espalhados
  pela pista, fazem a volta de saída e as cronometradas; vale a melhor volta válida. Com a opção
  ligada, sair da pista (as quatro rodas além da borda e da zebra) ou levar qualquer penalidade
  **anula a volta** (sem somar segundos); desligada, as infrações não têm efeito na classificatória.
  Ir rápido ao box recomeça como volta de saída. O HUD mostra o **tempo restante**; quando acaba,
  ninguém começa volta nova, mas quem já está numa volta cronometrada válida pode terminá-la (ela
  vale). No fim o grid é a ordem das melhores voltas (sem tempo larga atrás), os carros são
  consertados e a corrida larga do zero (`tests/qualifying_test.gd`, `tests/qualifying_time_test.gd`).
- **Pausa na largada:** pausar com o semáforo acendendo congela a sequência; ao voltar ela continua
  (`tests/start_pause_test.gd`).
- **Boxes:** os bots fazem fila indiana na pista dos boxes (seguem quem está entrando, parado ou
  saindo do box, sem ultrapassar) e só saem do box quando ninguém vem pela faixa rápida.
- `tests/race_test.gd` roda uma corrida inteira sem janela (o jogador também pilotado por bot) e
  confere que todos terminam e fazem o pit; `tests/capture_race.gd` gera capturas do HUD.

## Economia: loja, roletas, galeria e estúdio

Mesmo modelo de negócio do Pokeru (nada se vende por dinheiro real; o gacha é o sumidouro da moeda
e a meta de longo prazo). Catálogo e regras em `scripts/economy/shop_catalog.gd`; perfil do jogador
(autoload `Profile`, `scripts/economy/player_profile.gd`) salvo em `user://profile.cfg`.

- **Moeda:** créditos. Conta nova: 10.000. Corrida: 20 / 30 / 40 créditos por volta completada
  (bots fácil / médio / difícil; mista 30), ou seja 200 / 300 / 400 em 10 voltas; abandono recebe
  metade, desclassificado e treino livre não recebem. O resultado mostra quanto entrou.
- **Ticket = um giro** numa roleta, 2.500 créditos. Sem estoque, sem pacote, sem giro de 10, sem
  desconto. Duas roletas temáticas e sem sobreposição: **Neon** (luz, céu, gelo, neon, sakura) e
  **Inferno** (fogo, sombra, noite, metal, bordô), 36 peças cada.
- **Sorteio:** um degrau de raridade com fatia fixa e, dentro dele, uma peça com chance igual. Sem
  pity nem garantia. Gerador criptográfico (`Crypto`), e a loja mostra a mesma tabela que o sorteio
  usa.

| Raridade | Fatia | Peças por roleta | Chance de cada | Repetida devolve |
|---|---|---|---|---|
| Lendário | 2,5% | 4 | 0,63% | 3.600 a 4.500 |
| Épico | 6% | 8 | 0,75% | 2.100 a 2.625 |
| Raro | 10% | 6 | 1,67% | 1.350 a 1.695 |
| Incomum | 26% | 10 | 2,6% | 900 a 1.125 |
| Comum | 55,5% | 8 | 6,94% | 600 a 750 |

- **Repetida vira créditos:** 30% do preço de tabela; o giro nunca sai vazio. Um lendário
  específico custa em média 160 giros (400 mil créditos).
- **O que se coleciona:** pinturas (3 cores), capacetes, macacões, cor das rodas, brilho do boost,
  neon e peças de desempenho (asas, bico, sidepods, cobertura, rodas raiadas: trocam aderência por
  velocidade, nunca melhores em tudo). Vêm com a conta, fora do sorteio: a pintura Akane Racing,
  capacete, macacão, rodas e boost iniciais e todas as peças padrão.
- **Acabamento** (aba do Estúdio, grátis): pintura brilhante, metálica (flocos + verniz),
  perolada (borda iridescente + verniz), acetinada, fosca ou cromada; rodas polidas, cromadas,
  acetinadas ou foscas (`CarLivery.apply_paint_finish`, shader `car_rim` com reflexo e rugosidade
  por acabamento).
- **Estúdio** (garagem e Tab na corrida): equipa e combina só o que a conta tem. Coluna de abas
  só com ícones (pinturas, cor 1/2/3, capacete, macacão, rodas, boost, neon, peças; o nome no
  tooltip) e uma grade de 2 colunas em que toda opção tem o mesmo tamanho. As cores da pintura
  saem das pinturas possuídas; capacete, macacão, rodas, boost e neon, das peças daquele tipo; o
  neon só liga com uma peça de neon. Tudo é conferido de novo antes de ir para o carro (o que a
  conta não tem volta para o gratuito).
- **Decalques** (aba do Estúdio com a estrela, grátis; `scripts/car/car_decals.gd`): adesivos SVG
  nas **laterais**, no **bico**, na **entrada de ar** e nas **placas da asa traseira** (os lugares de
  dois lados recebem o mesmo desenho, legível dos dois). Cada um com **cor livre** (as três da
  pintura, uma paleta e o seletor de cor), **tamanho** e **giro**. 13 desenhos padrão
  (`assets/decals/`, gerados por `python tools/generate_decals.py`: estrela, raio, chamas, bandeira
  quadriculada, sakura, coração, asas, listras, garras, disco de número, onda, logo S, cometa) e os
  **SVGs do jogador**: "Abrir pasta dos meus SVG" abre `user://decals` (desenho branco com fundo
  transparente, até 512 KB) e "Recarregar" os lista. No carro são nós `Decal` projetados só na
  carroceria (camada `CAR_LAYER`) e tingidos com a cor. Ficam em `equipped["decals"]` (validado
  também pelo servidor); online os outros veem os padrão, os SVGs próprios só aparecem para quem
  tem o arquivo.
- **Engenharia** (primeira aba do Estúdio, a da chave inglesa, na garagem e no Tab da corrida): o
  comportamento do carro, nunca a aparência. Grupos Aerodinâmica (carga, arrasto, balanço), Freios
  (força, balanço), Pneus (aderência dianteira/traseira, ângulo de pico, queda depois do limite,
  sensibilidade à carga), Direção (esterço em baixa/alta, velocidade do volante), Motor e câmbio
  (relação final, giros de troca do automático, freio-motor), Suspensão (molas, amortecedores,
  alturas e barras estabilizadoras por eixo) e Assistências (margem). Cada parâmetro tem nome
  amigável, limites que fazem sentido, um slider largo com trilho fino e uma marca no valor de
  fábrica, botões redondos − / + (passo fino; com Shift, grosso), ↺ ao lado do valor só quando ele
  mudou (volta ao de fábrica) e um tooltip em cartão (`Retro.make_tooltip`: explicação com quebra de
  linha, valor atual, de fábrica, limites, passos e o efeito do botão). Fica salvo no perfil
  (`equipped.setup`, só o que mudou) e vale na corrida. Potência, desgaste e regras não entram
  (são iguais para todos). Catálogo em `scripts/economy/car_setup.gd`.
- **Galeria:** mesmo layout do Estúdio (abas de ícones por tipo, grade de 2 colunas); cada peça
  com arte, raridade e selo ("✓", "FALTA", "GRÁTIS"). Clicar mostra **no carro** como ficaria (sem
  equipar): se a peça tem lugar no carro (asas, bico, sidepods, cobertura, rodas, capacete,
  macacão, boost, neon), a câmera orbita até ela e a centraliza, alternando o sentido a cada clique
  (horário, anti-horário). O cartão de detalhes traz raridade, roleta, chance exata, quanto devolve
  se sair repetida e o botão Equipar (se for sua) ou Girar na roleta (se faltar).
- **Loja:** só tickets. Nenhum cosmético se compra direto; sem rotação nem ofertas. As paletas da
  interface vêm todas com o jogo (troca em Configurações → Tela).
- Não há presentes/vínculo como no Pokeru (o jogo não tem personagens para presentear).

## Interface retrofuturista

Visual synthwave + monitor CRT + HUD de ficção científica (`scripts/ui/retro.gd`, classe `Retro`):

- **Tokens:** tudo sai de uma paleta (`Retro.c("accent")`, `"surface"`, `"text"`…); bordas são o
  acento com transparência (`Retro.line(1..3)`), o brilho é acento e nunca massa. Cinco paletas:
  Synthwave (padrão), Tron, Vaporwave, Fósforo verde e Âmbar (as duas últimas monocromáticas:
  cores de equipe e de composto viram o acento, como num monitor de uma cor só). O roxo da volta
  mais rápida é o mesmo em todas.
- **Fontes:** Orbitron (títulos, números, rótulos curtos em caixa alta) e Chakra Petch (texto),
  em `assets/fonts/` (licença OFL).
- **Peças:** painel com degradê, filete de luz no topo, trama de varredura e brilho só na borda
  (`draw_panel`); cantoneiras em "L" (`draw_corners`/`add_corners`); etiqueta chanfrada em
  degradê com texto escuro (`draw_tag`/`tag_label`); barras segmentadas com brilho
  (`draw_segments`); texto com halo (`draw_glow_text`); botão principal em degradê neon
  (`theme_type_variation = "PrimaryButton"`). `Retro.theme()` é o `Theme` dos Controls (botões,
  seletores, popups, sliders, painéis) e é atualizado no lugar ao trocar a paleta.
- **Menus** (início, pausa, resultado) sobre o céu synthwave com sol no horizonte e grade em
  perspectiva (`shaders/ui/retro_backdrop.gdshader`, estático).
- **Paleta** escolhida em Configurações → Tela (salva em `user://interface.cfg`); todas vêm com o jogo.
- **HUD da corrida minimalista**, com fundos quase transparentes e as peças espalhadas pelas bordas:
  classificação (sup. esquerdo), posição e tempos (topo, centro), minimapa e nome do carro (sup.
  direito), velocidade/marcha/giro/bateria e DRS·câmbio·TC·ABS só em texto (`CarCluster`, inf.
  direito), status do carro num desenho compacto (`CarCluster.Status`, inf. esquerdo: o carro de
  cima com o dano por peça; cada pneu é uma mini barra — preenchimento = quanto resta, contorno =
  aderência em uso — com o %; composto e dano numa linha) e o monitor de desempenho numa faixa
  fina na borda. Texto pequeno tem contorno escuro para ler sobre céu e grama.

## Bandeira amarela, safety car e limitador

`scripts/race/race_control.gd` (direção de prova) e `scripts/race/safety_car.gd`.

- **Limitador** (P / D-pad ←): corta a tração acima de 80 km/h (indicador LIM no painel). Nos
  boxes é você quem aciona; passar de 80 km/h na pista dos boxes continua dando +5 s.
- **Bandeira amarela:** entra quando uma batida arranca peças (ou quebra uma roda). Um painel no
  topo mostra a instrução da sua situação, com a tecla certa (ou botão, se estiver no controle):
  - quem bateu: "Pressione [K] para ir aos boxes ou vá sozinho 1:40". O botão leva direto ao box
    para o conserto; dá para ir dirigindo; se não chegar em uma volta (tempo da sua melhor volta,
    ou 110 s), é levado ao box. Levado ao box (botão, tempo esgotado ou bot), a volta em que você
    estava recomeça: ao sair do box e cruzar a linha ela começa de novo, sem contar como completada
    (você perde a distância que tinha andado nela). Indo dirigindo até o box, a volta segue normal.
    Bots batidos vão ao box sozinhos em ~3,5 s;
  - os outros: "Não ultrapasse · não passe o safety car · safety car sai em 18 s" (ou "aguardando
    1 carro batido ir aos boxes").
- **Regras sob amarela** (fica a cargo dos jogadores; quem não segue é punido): não ultrapassar
  — o jogador vê **"DEVOLVA A POSIÇÃO PARA XXX!"** piscando no centro da tela com 12 s para deixar o
  carro passar; se não devolver, **+10 s** (bots: +10 s na hora). Quem é ultrapassado (bot ou outro
  jogador passando você) também vê o aviso **"ULTRAPASSAGEM SOB SAFETY CAR"** com quem passou e o
  que acontece com ele, e "POSIÇÃO DEVOLVIDA" quando ele devolve. A ordem de cada par é lembrada
  durante a amarela (por par, independente da classificação), então vale também a
  ultrapassagem lenta, lado a lado; pode passar quem está nos boxes ou envolvido na batida, e os envolvidos
  podem passar todos para chegar ao box) e não passar o **safety car** (+10 s). O limitador **não
  é obrigatório** sob amarela (só um jeito fácil de andar devagar atrás do safety car). O safety
  car entra à frente do líder com a giroflex âmbar, anda a até 180 km/h na linha ideal (mais devagar
  nas curvas, pelo perfil de velocidade) e aparece no minimapa (SC). Quem não bateu pode aproveitar para trocar pneus; isso não muda a bandeira.
- **Fim:** a amarela (com o safety car) dura **no mínimo 30 s** e só termina quando todos os
  carros batidos estão nos boxes (indo pela faixa, parados no box ou levados até ele); aí vem a
  bandeira verde e o safety car sai. Os consertos seguem independentes da bandeira.
- **Resultado:** a tela final mostra o detalhe das penalidades de cada jogador (título, segundos,
  motivo e volta).
- **Pedir passagem:** X (no controle, o botão Share) pisca 4 vezes a luz âmbar nos retrovisores (LED, halo e uma luz
  pequena), como a seta dos carros de rua; aparece para todos, inclusive online (vai no
  instantâneo do carro).
- Bots respeitam tudo: sob amarela seguem o carro da frente mesmo em outra linha (não ultrapassam,
  a não ser quem está nos boxes ou envolvido) e ficam atrás do safety car.
- O **semáforo** tem som: um bipe a cada coluna acesa e um tom agudo quando as luzes apagam.

## Linha ideal

`scripts/race/racing_line_guide.gd`: setas em "V" sobre a trajetória ideal (a mesma dos bots) à
frente do carro do jogador, encostadas no asfalto e levemente inclinadas para a câmera. A cor
compara a sua velocidade de agora com a velocidade ideal de cada trecho (perfil do bot difícil):
**verde** = abaixo do ideal (dá para acelerar), **amarelo** = no limite, **vermelho** = acima
(freie). Modos em Configurações → Jogo ou com L na pista: desligada, só nas frenagens e curvas, ou
completa.

## Menus pelo controle

Todos os menus funcionam com o controle: D-pad/analógico navegam (o primeiro toque foca o primeiro
item, e as telas novas já abrem focadas), A confirma, B volta/fecha, LB/RB trocam as abas da
garagem (Estúdio, Galeria, Loja) e das configurações, Start pausa na pista (a pausa tem o botão
Garagem). O item focado ganha um contorno no acento secundário, e as listas rolam até ele.

## Bateria, boost, marcas de pneu e sombra

- **Bateria** (`F1Car.battery`, barra no HUD): frear recarrega (mais em alta velocidade) até 100%;
  segurar Alt esquerdo gasta a bateria num **boost** do motor elétrico (`boost_force`, ~4,5 s de
  bateria cheia, +~45 km/h na reta). Parâmetros no grupo "Bateria e boost" do `F1Car`.
- **Efeitos** (`scripts/car/car_effects.gd`): durante o boost as rodas brilham na cor
  `CarConfig.boost_color` (escolhida na garagem), acendem luzes, deixam um rastro de luz
  (`TrailRibbon`) e partículas de pó mágico; som próprio no `CarAudio`.
- **Rodas no boost:** aro, pneu e faixa do pneu bem brilhantes na cor do boost, além da luz no chão.
- **Neon embaixo do carro** (garagem → Pintura: "Neon embaixo do carro" + cor): brilho no chão
  (`Decal` emissivo), luzes sob o assoalho e tubos de neon nas laterais; fraco de dia e forte à noite.
- **Luz traseira de F1:** a lanterna central e os LEDs das placas da asa traseira ganham material
  próprio e piscam (~4 Hz) quando o carro freia (recuperando energia), com clarão e, à noite, luz
  vermelha no chão atrás do carro. Os LEDs do volante não são afetados.
- **Marcas de pneu:** fitas escuras no asfalto/zebra ao frear forte, travar, patinar ou derrapar;
  somem em ~45 s.
- **Sombra de contato:** um `Decal` sob o carro, sempre visível (também à noite e com o sol baixo).
  O carro fica só na camada `CarAssembly.CAR_LAYER` para o decal não pintar a carroceria.

## Dano e destruição

`scripts/car/car_damage.gd` (nó `Damage` em `f1_car.tscn`). Peças com resistência própria: asa
dianteira esquerda/direita, bico, asa traseira, sidepods, retrovisores, cobertura do motor, assoalho,
suspensão de cada canto e o motor. As malhas são copiadas (e as de dois lados cortadas ao meio) ao
montar o carro, para poderem ser deformadas.

- **Batida:** os contatos do corpo chegam por `F1Car._integrate_forces` (contact monitor). O impulso é
  o reportado pela física ou estimado por massa × Δv na direção da normal (o Jolt às vezes reporta 0
  no passo da batida). Acima de `impulse_threshold` tira resistência das peças perto do ponto
  (alcance ~1 m; batidas fortes propagam 30% do choque até ~2 m) × fragilidade da peça.
- **Visual:** a malha é amassada em volta do ponto; peças com < 60% ficam soltas (caídas e
  balançando com o vento); com 0% se soltam e viram `RigidBody3D` na pista (casco convexo, colidem
  com o carro). O bico leva a asa junto; a suspensão quebrada solta a roda e o canto do carro
  arrasta no chão. Faíscas (`GPUParticles3D`), lascas de fibra de carbono, fumaça do motor ferido,
  sons de raspagem e de peça quebrando.
- **Física:** sem asa dianteira o carro sai de frente (downforce dianteira cai até 40%), sem asa
  traseira sai de traseira (e tem menos arrasto); peças danificadas aumentam o arrasto; motor
  ferido perde potência; braço de suspensão torto faz a roda apontar para um lado (o carro puxa) e
  tira aderência.
- **HUD:** o carro visto de cima com cada peça colorida pela resistência (painel CARRO do
  `CarCluster`).
- Barreiras: colisão em blocos sólidos (paredes finas deixavam o carro atravessar), atrito baixo;
  o carro usa detecção contínua de colisão (CCD).

## Iluminação

`scenes/env/daylight.tscn` (`Daylight`) é instanciada nas duas cenas. Iluminação de **três pontos**:

- **Principal** (`Sun`): o sol, com sombras em 4 cascatas até 320 m (mapa 8192, filtro suave).
  Mude a hora do dia com `sun_elevation` / `sun_azimuth` (a cor esquenta perto do horizonte).
- **Preenchimento** (`Fill`): luz fria e fraca vinda do lado da câmera oposto ao sol; clareia o que
  está na sombra.
- **Contorno** (`Rim`): luz quente vinda de trás do carro, contra a câmera, desenhando a silhueta.
  Só ilumina a camada `CarAssembly.CAR_LAYER` (as malhas do carro), para não clarear o cenário.

Fill e Rim acompanham a câmera ativa durante o jogo, não projetam sombra nem aparecem no céu
(energia e ângulos no inspetor do `Daylight`). O ambiente tem céu anime, luz ambiente mista,
tonemapping ACES, SSAO leve, bloom suave e **neblina**: exponencial com perspectiva aérea para a
distância e uma névoa baixa volumétrica (`FogVolume` "GroundMist" com queda por altura) que se
acumula perto do chão e nos vales (as duas a 72% da densidade dos presets, `Daylight.FOG_SCALE`).
MSAA 4x no projeto. Na garagem o carro assenta na plataforma e fica preso nela (nivelado e
congelado; solta para assentar de novo quando a engenharia muda).

**Contorno anime:** `shaders/outline_post.gdshader` não desenha linha em superfícies com rugosidade 0
— grama 3D, bandeirolas, barreiras e muretas, arquibancadas e público, prédio dos boxes (com vidro e anúncios), postes do alambrado, postes de luz,
colunas, mastros, pernas de painéis e torres de pórticos (`TrackMaterials.plain()` / `pit()`; nos
geradores, `MeshBuilder.posts()`).

**Texturas das construções:** `shaders/track/building*.gdshader` misturam a cor de vértice com três
texturas projetadas no espaço do objeto (`assets/track/textures/`, geradas por
`python tools/generate_textures.py` — pode trocar por imagens próprias com o mesmo nome):
`material_detail.png` (grão do concreto/pintura, em duas escalas), `grime.png` (manchas e escorridos)
e `deform_normal.png` (normal map de amassados e ondulações). Também juntas de painéis, sujeira perto
do chão e atenuação do relevo onde o toon cintilaria (usa o global `sun_dir_world`, atualizado pelo
`Daylight`). Vidro anime (`glass.gdshader`: reflexo, faixas diagonais, fresnel) nos boxes, nas janelas
dos vilarejos e nos camarotes no alto das arquibancadas cobertas.

## Horários e ambientes

`Daylight` tem `time_of_day` (dia, entardecer, noite) e `biome` (verão, outono, sakura, fantasia);
os presets ficam em `scripts/world/daylight_presets.gd`. Trocar é instantâneo, sem reconstruir a pista:

- **Horário:** sol (ou lua), céu (degradê, nuvens, estrelas e lua à noite), luz ambiente, neblina e
  luzes de três pontos. À noite (e fraco no entardecer) os postes acendem com `SpotLight3D` reais
  apontados para a pista, as garagens acendem e as janelas de vidro brilham.
- **Ambiente:** as cores da grama, das copas e das folhas vêm de uniforms globais de shader
  (`grass_*`, `leaf_*`, `leaf_mix`, `conifer_mix`, `petals`), usados pelo terreno, grama 3D, árvores
  e folhas. Outono: grama e árvores laranja/vermelho/amarelo, pinheiros verdes, algumas folhas na
  pista. Sakura: árvores rosa/branco/verde, pétalas caindo, algumas na pista e muitas no chão.
  Fantasia: grama rosa, árvores roxas e céu verde-água.
- Nós que reagem ao ambiente entram no grupo `mood_aware` e recebem `apply_mood(horário, ambiente)`.

## Sons do carro

Todos os sons são sintetizados por `tools/generate_car_sounds.py` (Python + numpy) em
`assets/audio/car/` — não há gravações. Para mudar o timbre, edite o script e rode
`python tools/generate_car_sounds.py`.

- **Motor:** V6 de 4 tempos por síntese aditiva: harmônicos da frequência de disparo (3 por volta),
  ordens do virabrequim e meias-ordens (cilindros desiguais), envelope de ressonâncias do escapamento
  (mais brilhante com carga), flutuações lentas e ruído de combustão pulsando; sem distorção dura
  nem aliasing. Loops de 2 s em 7 giros (4000–13000 rpm), com e sem carga. O nó `Audio`
  (`CarAudio`, em `f1_car.tscn`) mistura os dois loops vizinhos do giro atual (equal power), ajusta
  o pitch pelo rpm e troca carga/sem carga pelo acelerador; corte de ignição no limitador.
- **Camadas:** turbo, assobio das engrenagens (forte ao aliviar), vento, pneu cantando (no limite
  de aderência), pneu arrastando (travado/patinando), brita, grama e zebra (as batidas seguem a
  velocidade).
- **Sons curtos:** trocas de marcha (subida com estalo, redução com "blip"), **ronco do escapamento**
  ao tirar o pé em giro alto (um "brap-brap" grave por alívio: 3 a 6 pulsos de 55–85 Hz com sopro
  filtrado, ressonância do cano e sem os agudos que davam som de pipoca), DRS e batidas
  (detectadas por desaceleração brusca).
- **Mixagem:** `default_bus_layout.tres` — bus `Car` (o seu carro) com compressor e um passa-baixa
  ligado só na câmera do piloto (som abafado pelo capacete); limitador no `Master`. Os sons são 3D
  com efeito Doppler. Volumes na garagem (Tab → Som) e no inspetor do nó `Audio`.
- **Plateia** (`scripts/track/crowd_audio.gd`, sons de `tools/generate_crowd_sounds.py` em
  `assets/audio/crowd/`): murmúrio baixo em loop em alto-falantes ao longo de cada arquibancada
  (só tocam perto da câmera), palmas e torcida de vez em quando, quando o seu carro passa rápido
  perto, na largada e na sua chegada. Bus `Crowd`. Volume medido contra o motor na reta dos boxes:
  ~4 dB abaixo dos carros, com presença na faixa da voz (1–4 kHz) para não sumir sob o motor. Tudo
  sintetizado: o murmúrio são ~260 vozes falando (cada sílaba uma vogal com formantes F1/F2/F3 reais,
  excitada por ruído e pulsos glotais com entonação), a torcida um "uuuh/aaah" subindo de tom com
  gritos e assobios, palmas aleatórias, **buzinas de ar** (a corneta de arquibancada; espontâneas,
  na passagem do carro, largada e chegada) e eco de estádio.
- **Marcha lenta:** cada carro tem a marcha lenta um pouco diferente (giro com leve oscilação e
  combustão irregular nos loops de giro baixo) e os rivais parados ficam mais baixos — antes os 10
  carros no grid no mesmo giro somavam um zumbido de tom puro de 200 Hz
  (`tests/audio_hum_probe.gd` grava a saída silenciando um bus de cada vez).
- **Carros em volta** (bots e outros jogadores, `CarAudio.make_rival`): bus próprio `Rivals` (o
  compressor do seu motor não os abafa; o volume "Carro" vale para os dois), som que chega de mais
  longe, estéreo mais marcado (dá para saber de que lado vem) e até +7 dB quando o carro está perto
  da câmera — ao lado ou colado atrás.

## Música

Quatro faixas originais, compostas por código (sementes fixas), em `assets/audio/music/`, todas
em loop sem emenda e com o mesmo volume médio (−16,5 dBFS):

| Faixa | Estilo | Gerador |
|---|---|---|
| Tema da corrida (`race_theme.wav`) | pop anime, 152 BPM, Dó maior | `python tools/generate_music.py` |
| Neon Horizon (`synthwave.wav`) | synthwave/outrun, 104 BPM, Lá menor: baixo arpejado, caixa com reverb "gated", pads largos, lead com portamento | `python tools/generate_music_extra.py` |
| Slipstream (`drum_and_bass.wav`) | drum & bass, 174 BPM, Ré menor: breakbeat, baixo "reese", pads atmosféricos | idem |
| Pixel Grand Prix (`chiptune.wav`) | chiptune 8-bit, 144 BPM, Mi maior: onda de pulso, baixo triangular, bateria de ruído, arpejos rápidos | idem |

O menu principal tem o próprio tema (Neon Horizon, em loop); ao trocar de cena a música corta para
a da pista e vice-versa. Na pista, o autoload `Music` (`scripts/audio/music_player.gd`) toca no bus "Music": em **playlist** (padrão,
cada faixa toca duas vezes e passa para a próxima com crossfade de 3 s) ou uma faixa fixa em loop
(Configurações → Áudio). Ao importar um WAV novo, use loop "Forward" (`edit/loop_mode=2`).

## Configurações

F10 (em qualquer momento), ou o botão **Configurações** no menu inicial, na pausa e na garagem.
Autoload `Settings` (`scripts/settings/game_settings.gd`); menu em `scripts/settings/settings_menu.gd`.
Tudo é aplicado na hora e salvo em `user://settings.cfg`
(`%APPDATA%/Godot/app_userdata/F1 Gatcha/` no Windows).

- **Controles:** todas as ações remapeáveis, uma tecla de teclado e um botão/eixo de controle por
  ação (clique, aperte a nova; Esc cancela, Backspace apaga). Conflitos aparecem em amarelo. As
  teclas que eram fixas no código (pausa, ajuda, páginas da classificação, pneu do pit, F10) viraram
  ações também.
- **Tela:** janela / tela cheia / tela cheia exclusiva, resolução da janela, VSync (desligada,
  ligada, adaptativa, mailbox), limite de FPS, escala da interface (automática pela janela, ou
  75–150%), campo de visão da câmera e paleta da interface.
- **Gráficos:** predefinições Baixo/Médio/Alto/Ultra (mudar qualquer item vira "Personalizado"),
  escala de renderização 3D com upscaler (bilinear, AMD FSR 1.0, FSR 2.2), MSAA, FXAA/SMAA, TAA,
  sombras (atlas de 2048 a 16384 e filtro suave), SSAO, SSIL, glow, neblina volumétrica e nível de
  detalhe dos modelos (LOD).
- **Desempenho:** monitor na tela (desligado, só FPS, ou detalhado: FPS médio e mínimo, gráfico do
  tempo de quadro, CPU = tempo da lógica e da física por quadro, GPU medida, RAM do jogo, VRAM,
  draw calls, objetos, processador e placa de vídeo) e o canto onde aparece. O Godot não expõe o
  uso total de CPU do sistema, por isso o monitor mostra o tempo que o jogo gasta no processador.
  Conectado ao servidor, mostra também a **latência** (ida e volta até o servidor, em ms, do ENet).
  "Em corridas online" (padrão: FPS e latência) liga o monitor sozinho nas corridas no servidor.
- **Áudio:** volume geral, do carro, da música e do som ambiente (torcida e palmas, bus `Crowd`); música liga/desliga; faixa ou playlist; silenciar
  com a janela em segundo plano.

## Circuitos (Monza)

`scenes/tracks/monza.tscn` tem um nó `Track` (`RaceTrack`) que gera o circuito inteiro em tempo de
execução (~1 s) e também no editor (botão **Reconstruir pista** no inspetor). Nada gerado é salvo na
cena: fica no filho `Generated`.

- **Traçado real:** `assets/track/monza/monza_centerline.csv` — linha central e larguras do
  [TUMFTM racetrack-database](https://github.com/TUMFTM/racetrack-database) (LGPL-3.0, derivado do
  OpenStreetMap/ODbL). 5,79 km, sentido horário. `TrackPath` reamostra a cada 2 m; `s` = metros a
  partir da linha de largada (negativo = antes dela). Outro circuito do mesmo banco de dados é só
  trocar o CSV.
- **Layout editável:** `resources/tracks/monza_layout.tres` (`TrackLayout`) — boxes, grid e a lista
  de `TrackFeature` (tipo, trecho `s_start`..`s_end`, lado, afastamento, fileiras, cobertura...):
  arquibancadas, público em pé, brita, muros, anúncios na barreira, painéis, postes, pórticos de
  anúncio, pórtico de largada e placas de frenagem. Zebras e brita nas curvas são automáticas
  (raio da curva).
- **O que é gerado:** asfalto com faixas, zebras vermelhas/brancas elevadas, caixas de brita,
  guard-rail/muro com alambrado e blocos de proteção nas áreas de escape, boxes (20 garagens com cor
  e número das equipes, cabines no muro, marquise, paddock e motorhomes), linha de chegada, grid de
  20 posições, luzes de largada (`StartLights.run_sequence()`), anúncios de marcas fictícias,
  postes de iluminação e setas nas curvas fechadas.
- **Terreno e horizonte** (`track_terrain.gd`, ideia das pistas de Mario Kart): a área ocupada
  (pista, barreiras, arquibancadas, boxes, paddock) é plana; fora dela o terreno sobe em colinas
  arredondadas, terraços e mesas com paredões de rocha em camadas, formando uma "tigela" verde em
  volta do circuito. Mais longe, um anel de montanhas com neve fecha o horizonte. A altura é uma
  função de ruídos + distância até a área ocupada (campo de distância), amostrada a cada 8 m:
  vira textura (os blocos `PlaneMesh` são deslocados no shader `terrain.gdshader`),
  `HeightMapShape3D` (colisão) e `height_at()` para posicionar árvores e objetos. Mude o relevo
  com `terrain_seed` no nó `Track`.
- **Grama:** o chão tem manchas de cor, zonas grandes de verde mais escuro alternando com as claras
  (as árvores nessas zonas também escurecem), faixas de corte perto da pista, florzinhas, normal map
  procedural (irregularidades do chão; mais forte nos penhascos) e rocha/neve conforme a inclinação
  e a altura. Em volta da câmera (`grass_radius`, ~62 m) há grama
  3D (`GrassField`: tufos de lâminas com flores, balançando com o vento); uma máscara renderizada de
  cima impede que ela nasça no asfalto, zebras, brita e boxes. O contorno anime ignora a grama
  distante (`ROUGHNESS = 0` marca a grama para `outline_post.gdshader`).
- **Árvores** (`track_trees.gd`): carvalho, cipreste italiano, pinheiro, pinheiro-manso, bétula e
  arbusto, cada um com malha detalhada (perto) e simples (longe), em bosques e clareiras,
  sobre o relevo (~24 mil). O shader dá tufos de folhas claros/escuros, tons por árvore e vento.
- **Pinheiros de preenchimento** (`track_pines.gd`): o modelo `Tree_Pine_Light` (agulhas, de
  `edit-assets-workspace/tree/tree_pine`, copiado para `assets/track/trees/`) em quatro fileiras
  logo atrás das cercas e arquibancadas, fechando o horizonte. Cor do ambiente
  (`shaders/track/pine_fill.gdshader`); além de 400 m vira uma versão estilizada leve com a mesma
  silhueta. `pines` no nó `Track` liga/desliga.
- **Árvores folhosas** (`track_leaves.gd`): logo atrás das barreiras, com copas de centenas de
  folhas individuais (dupla face, tremulando), soltando folhas que caem girando com o vento
  (`GPUParticles3D`, `shaders/track/leaf.gdshader`; pétalas no sakura). Folhas no chão e na pista em
  quantidade definida pelo ambiente.
- **Cenário** (`track_scenery.gd`): rochas nas encostas, vilarejos italianos com campanário nas
  colinas, turbinas eólicas girando na serra, balões, três dirigíveis de anúncios (um pairando
  sobre a reta, como o da TV; seis no total, alguns baixos sobre a Parabolica e Lesmo) e ~56 nuvens 3D fofas levadas pelo vento (`SceneryAnimator`).
- **Vida** (`track_life.gd`): ~1200 pedestres andando nos corredores atrás das barreiras e
  arquibancadas e no paddock (cada caminho é conferido ponto a ponto para nunca cruzar a pista,
  os boxes ou as barreiras), mecânicos de macacão e capacete nas cores das equipes em todas as
  garagens, e grupinhos parados conversando (`shaders/track/walker.gdshader`:
  billboard com pernas e braços animados, tudo na GPU); 10 bandos de pássaros (alguns em V, alguns
  de gaivotas) dando voltas sobre o parque, baixos e altos (`bird.gdshader`). Os dirigíveis agora são
  13: órbitas altas, quatro órbitas baixas (50–70 m) sobre trechos da pista e três passando em linha
  reta por cima do circuito; todos (e os pássaros) sobem para não entrar nas colinas.
- **Bandeirolas** (`track_flags.gd` + `shaders/track/flag.gdshader`): cordões de bandeirinhas no
  topo das arquibancadas, entre os postes da reta e da Parabolica e sob a marquise dos boxes;
  mastros com a bandeira da Itália e das equipes. O elemento de layout `BUNTING` estende cordões
  sobre o alambrado e, a cada `spacing`, mastros dos dois lados com bandeirolas cruzando por cima
  da pista. Tudo tremula no shader (UV.x = distância da corda).
- **Céu:** `shaders/sky_anime.gdshader` (em `daylight.tscn`) — degradê, sol com halo e nuvens em duas
  tonalidades (lado iluminado/sombra), calculadas em meia resolução.
- **Brita:** normal map de pedrinhas (ruído celular) além da cor; os normal maps são `NoiseTexture2D`
  gerados em `TrackMaterials.normal_texture()` (sem arquivos de imagem).
- **Público:** quads de um MultiMesh por arquibancada (~48 mil pessoas). A silhueta, as cores e a
  animação (sentado, acenando, pulando, com bandeira) são todas feitas no shader
  `shaders/track/crowd.gdshader`, sem custo de CPU. Some além de `crowd_visibility`.
- **Pisos:** cada superfície é um `StaticBody3D` com metadado `surface` (`TrackSurface`). O modelo
  de pneu lê o corpo sob cada roda: zebra (−10% de aderência, vibra), grama e brita. Fora da pista
  o carro **escorrega bastante de lado** (grama ~40% e brita ~33% da aderência lateral do asfalto,
  `TrackSurface.GRIP × SIDE_GRIP`) mas **não atola**: a resistência extra é moderada (a 200 km/h, em
  2 s acelerando, a grama ainda ganha ~44 km/h e a brita ~14 km/h; `tests/offtrack_probe.gd`). A
  brita levanta poeira e vibra. Corpos sem metadado contam como asfalto.
- **Anúncios:** `assets/track/ads/ad_atlas.png`, gerado por `tools/bake_ad_atlas.gd` a partir de
  `TrackAds.BRANDS` (edite os nomes/cores e rode `godot --path . -s res://tools/bake_ad_atlas.gd`).
- Código: `scripts/track/` (`race_track.gd` orquestra; `track_road.gd`, `track_barriers.gd`,
  `pit_complex.gd`, `grandstands.gd`, `track_props.gd`, `track_terrain.gd`, `track_trees.gd`,
  `track_scenery.gd`, `grass_field.gd` geram cada parte).

## Mônaco (circuito de rua)

`scenes/tracks/monaco.tscn` + `resources/tracks/monaco_layout.tres`. A pista é escolhida no menu
solo e nas salas do multiplayer (`RaceSettings.TRACKS`; a sala manda `track` para o servidor, que
monta a cena certa, e para os clientes no `race_start`).

- **Traçado e relevo reais:** linha central da relação 148194 "Circuit de Monaco" do
  OpenStreetMap (3,30 km, no sentido da corrida, começando na linha de chegada), suavizada. A 5ª
  coluna do CSV é a **elevação**: `TrackPath` interpola a altura e o referencial da pista (`frame_at`)
  acompanha a rampa. Perfil ajustado nos pontos conhecidos: reta dos boxes ~6 m, Sainte Dévote ~9 m,
  subida do Beau Rivage (até ~8%), Massenet/Casino ~44 m, descida pelo Mirabeau e pelo grampo do
  Grand Hotel (raio ~9 m), Portier ~12 m, túnel caindo até ~6 m, Nouvelle Chicane, Tabac, Piscine
  ~2,6 m junto ao mar, Rascasse e Antony Noghès.
- **Gerador offline:** `python tools/build_monaco.py [--debug pasta]` lê os dados do OSM salvos em
  `tools/data/monaco/` (prédios, costa, píeres, piscinas, parques, ruas) e grava em
  `assets/track/monaco/`: o CSV da pista, `monaco_city.json` (grade de alturas de 4 m resolvida por
  relaxação — encosta subindo para o interior, chão no nível da pista perto dela e por cima do
  túnel —, muros do cais pelo contorno do mar, 1.333 prédios com altura pelas etiquetas do OSM ou
  pelo tamanho, recortados onde invadiriam a pista, ruas, árvores, pontões e ~230 barcos) e
  `monaco_shore.png` (distância até a terra e máscara do porto, para o shader do mar). As áreas
  planas da pista (boxes, arquibancadas, escapes) ficam em `FLAT_ZONES`/`BARRIER_ZONES` no script e
  precisam bater com o `.tres`.
- **Cidade** (`track_city.gd`): terreno em blocos com cor e **tipo de piso** por uso
  (`shaders/track/city_ground.gdshader`: praças de lajes de pedra desencontradas com faixas
  decorativas e manchas de calcário/granito, calçadas de ladrilho, jardins com a grama do ambiente
  e flores, rocha nas encostas, asfalto sob a pista), colisão só perto da pista; cais de pedra; ruas
  de asfalto com **faixa central tracejada** e ruas de pedestres em **paralelepípedo**; piscinas;
  prédios com fachadas coloridas e janelas procedurais (`shaders/track/city_building.gdshader`:
  venezianas verdes, varandas modernas com guarda-corpo, vitrines no térreo com **toldos
  listrados**, embasamento de pedra, cornija no topo, peitoris, vergas, **pedras de cunhal** nas
  quinas, **floreiras** em parte das janelas, venezianas de uma cor por prédio — verde,
  azul-acinzentado, vinho, creme, sálvia —; telhas em fiadas e lajes de cascalho), **varandas em
  3D** nos prédios a até 110 m da pista (sacadas de pedra com gradil nos clássicos, varandas
  corridas com guarda-corpo de vidro nos modernos), mansardas de zinco, telhados de telha (também
  em boa parte dos prédios baixos), **mureta, caixas-d'água, antenas e terraços com jardineiras**
  nas lajes, casas de máquinas; prédios **sem contorno anime** (rugosidade 0 no shader) e com
  **sombra de contato**: a base das paredes escurece, as paredes descem 4 m abaixo da base (nunca
  flutuam em encosta) e o chão em volta ganha uma faixa de calçada de ladrilho e escurece junto à
  parede (`bdist`, distância de cada vértice ao prédio); o **Casino** com as torres e cúpulas de cobre; encostas com
  **jardins em terraços** (muretas de pedra nas curvas de nível); morros dos Alpes Marítimos com
  cristas e penhascos (ruído "ridged"), **mato mediterrâneo**, rocha nas encostas íngremes e
  milhares de **árvores** (pinheiros, pinheiros-mansos, carvalhos, ciprestes) e o casario de
  Beausoleil além da área dos dados (`build_backdrop`).
- **Árvores:** as mesmas espécies de Monza (`TrackTrees`, shader das árvores com vento e as cores
  do ambiente): pinheiro-manso, carvalho, cipreste, arbusto e bétula, com malha simples de longe;
  e as palmeiras. Nos morros só nos anéis mais perto da cidade; perto da pista (`city_props.gd`),
  ~200 árvores nos jardins e como árvores de rua a 7–55 m da borda.
- **Junto à pista** (`city_props.gd`, só em lugares livres — chão de calçada/praça, fora dos
  prédios, das ruas, das arquibancadas e do mar, além das barreiras): ~500 objetos de mobiliário
  urbano (bancos, floreiras com flores, frades, lixeiras e, na orla do porto, mesas de café com
  guarda-sóis de três cores). A faixa que a grade marca "sob a pista" além da borda vira calçada;
  ruas da cidade com **meio-fio de pedra**; calçadas e praças com **tampas de bueiro e grelhas**
  (shader, perto); gramados de cidade menos saturados.
- **Navios e balões** (`track_offshore.gd`): navio de cruzeiro, porta-contêineres (pilhas
  coloridas), petroleiro e balsa cruzando ao largo em rotas paralelas à costa (longe da costa de
  verdade dentro da área dos dados), com rastro de espuma; 14 balões de ar quente grandes (o modelo
  de Monza, `TrackScenery.balloon_mesh`) passando com o vento sobre o porto e a orla, perto do
  circuito, a 130–260 m (visíveis da pista); e dirigíveis com anúncios (`TrackScenery.blimp_mesh`):
  seis nos **pontos de vista** do piloto (reta, Beau Rivage, Massenet/Casino, saída do túnel,
  Tabac/Piscine, Rascasse), pairando sobre a própria pista ~200 m à frente — na faixa de céu que
  aparece por cima da rua entre os prédios —, acima dos prédios vizinhos e indo e voltando ao
  longo da pista (sem sombra); e dois altos em órbitas ao longo da costa.
- **Túnel** (`track_tunnel.gd`): 371 m sob o Fairmont, paredes de azulejo, teto com duas fileiras
  de luminárias, luzes de sódio, portais nas bocas e sondas de reflexo com ambiente escuro (dentro
  fica na penumbra). Sem alambrado lá dentro.
- **Mar e porto** (`track_harbour.gd`, `shaders/track/water.gdshader`): ondas no vértice (calmas no
  porto), dois normal maps rolando, turquesa junto ao cais e azul profundo ao largo, fresnel com o
  céu, brilho do sol e espuma nos cais e nas cristas; um anel liso até o horizonte. Pontões
  flutuantes, iates enormes de popa no cais, lanchas e veleiros nos pontões, superiates fundeados
  (MultiMesh com balanço e cor do casco no shader `boat.gdshader`) e lanchas navegando ao largo com
  rastro de espuma.
- **Noite:** ~50 postes de rua (`LIGHTS` com `variant = 1`: coluna fina atrás da barreira, braço
  curvo sobre a pista e luz quente) nos pontos-chave da volta, e parte das janelas dos prédios
  acende (`city_building.gdshader`, `TrackCity.set_night`).
- **Ambiente:** as copas das árvores e a grama dos jardins seguem o tema (outono laranja, sakura
  rosa, fantasia roxa) pelos globais do shader; as palmeiras puxam um pouco para ele
  (`TrackCity.apply_biome`).
- **Área de escape:** a faixa asfaltada entre a pista e a barreira é o piso `RUNOFF` — anda como
  asfalto, mas conta como fora da pista para os limites (cortar a chicane por ela é infração).
- Nenhum prédio cobre a pista fora do túnel (o gerador descarta plantas que, mesmo recortadas,
  ainda atravessam a rua; o teste confere).
- **Boxes apertados** entre a reta e a Piscine (20 garagens de 7 m, sem paddock); barreiras a
  1,6 m da pista, com escapes em Sainte Dévote, grampo, chicane e Rascasse.
- Recordes: a volta mais rápida da conta (ranking) continua sendo a de Monza; Mônaco guarda o
  recorde em `best_lap_monaco` nos contadores. Volta mínima plausível por pista
  (`NetProtocol.MIN_LAP_BY_TRACK`).
- Dados: © colaboradores do OpenStreetMap, licença ODbL (https://www.openstreetmap.org/copyright).

## Multiplayer (servidor dedicado + Turso)

Servidor **autoritativo**: um processo Godot sem janela (`--server`) é dono de tudo que vale —
contas, créditos, roletas, coleção, equipamento (skins) e engenharia, resultados, ranking — e roda
as corridas em rede. O jogo só manda comandos e mostra o que o servidor diz. Transporte: ENet
(RPCs de alto nível do Godot) no autoload `Net` (`scripts/net/net.gd`), o mesmo nó nos dois lados.

**Rodar o servidor**

```
godot --headless --path . -- --server --db-url=libsql://<banco>.turso.io --db-token=<token> --port=7350
```

O banco também vem das variáveis `TURSO_DATABASE_URL` / `TURSO_AUTH_TOKEN` ou de um `server.cfg`
(veja `server.cfg.example`; não versionar o token). Funciona com o Turso na nuvem e com o libSQL
local da VM (`http://db:8080`, sem token). O servidor cria **tabelas próprias** com prefixo `sp_`
(`sp_accounts`, `sp_friends`, `sp_friend_requests`, `sp_matches`, `sp_meta`), sem tocar nas que já
existem no banco. O token do aparelho nunca é guardado, só o SHA-256 dele.

**Rodar o jogo conectado**: o jogo conecta sozinho ao abrir (`127.0.0.1:7350` por padrão); o
endereço muda na tela Multiplayer (fica salvo) ou com `-- --connect=host:porta`. Para dois jogos no
mesmo PC: `-- --account=segundo` (outra conta). `-- --offline` não conecta. Sem servidor, o jogo
segue offline com o perfil local do aparelho (solo, loja e estúdio locais).

**Conectado** (`Profile.mode = "remote"`): créditos, coleção e equipamento vêm do servidor; o giro
da loja é feito lá. **O carro do aparelho vale no servidor**: ao conectar, o jogo manda o visual
(pintura, cores, peças, acabamentos) e a engenharia do perfil local, e o servidor usa esse carro
nas corridas; a coleção local também conta para montar o carro no Estúdio enquanto conectado.
**PENDENTE (produção):** hoje o servidor aceita o carro sem conferir se a conta tem as skins e
peças (`NetProtocol.TRUST_CLIENT_CAR = true`, só a estrutura é validada); para o servidor de
produção, desligar e validar a posse no servidor; a corrida solo manda o resultado e o servidor confere (voltas, tempo plausível, dificuldade
liberada pelo nível) e paga.

**Regras** (do documento do Pokeru, adaptadas para corridas):
- **Código de amigo** de 6 letras sem 0/O/1/I/L, mostrado como `ABC-234` (maiúsculas, espaços e
  hífen não importam). Até 100 amigos e 50 pedidos pendentes; pedido cruzado vira amizade na hora;
  repetido ou para si mesmo é recusado; recusar/cancelar limpa os dois lados; desfazer é mútuo e
  silencioso; dá para pedir amizade a quem está na mesma sala.
- **Presença**: online / em corrida (nada guardado); aviso quando um amigo entra.
- **Grupo** até 4: só o líder convida amigos online e escolhe a partida (contra bots, fila ou
  Custom); se o líder sai ou sobra um, o grupo se desfaz.
- **Salas**: corrida rápida (fila, larga quando todos marcam pronto), Custom (nome, senha, pista,
  voltas 3/5/10/15, bots e dificuldade, **corredores no grid** 2–14 — jogadores + bots; a sala
  aceita até 10 jogadores —, classificatória (voltas, tempo limite, colisão e se infração anula a
  volta), DRS, horário, ambiente; o anfitrião
  larga), contra bots (do grupo). Quem está na sala Custom convida amigos online, e o convidado
  entra mesmo com senha.
- **Ranking**: Geral, Vitórias, Ganhos, Volta mais rápida; Geral = soma de round(valor ÷ líder ×
  1000) por aba; só valores > 0; empates por nome e id dividem a posição (1, 2, 2, 4); 50 linhas e
  a sua; cache de 15 s; sem temporadas.
- **Perfil** (só amigos e o dono): nome (até 16, vazio = Jogador), código, nível, título (validado
  pelas conquistas), últimas 5 corridas, 21 conquistas, "como você pilota" (6 traços das últimas
  10 corridas, 0,5 sem histórico). Ganhos totais só o dono vê.
- **Nível** = 1 + ⌊√(xp ÷ 40)⌋, xp dos contadores (volta 3, corrida 10, pódio 15, vitória 25).
  Bots liberados por nível: fácil 1, médio 3, difícil 6, mista 3.

**Corrida em rede**: a cena de Monza roda no servidor dentro de um `SubViewport` com mundo 3D
próprio (cada sala tem a sua física) e só o que tem colisão (sem árvores, folhas, público…). O
`RaceManager` em modo `SERVER` monta o grid (humanos na frente em ordem sorteada, bots completando
até 10 se a sala usa bots; carros com o visual e a engenharia das contas) e aplica todas as regras
(penalidades, pit, bandeira amarela, safety car). O cliente manda os comandos a cada passo de
física (pedais, direção e contadores das ações de toque, que não se perdem); recebe instantâneos
de todos os carros 30×/s (`NetSnapshot`, 64 bytes por carro) e o estado da prova 5×/s; desenha os
carros 0,1 s no passado, interpolando (`NetRaceClient`; os carros do cliente são marionetes
cinemáticas, `F1Car.set_puppet`). Avisos e penalidades chegam só para o piloto envolvido; peças
arrancadas para todos. Sem pausa online (Esc abre o menu, os pedais soltam). **Votação para
recomeçar**: no menu (Esc) qualquer jogador vota; a votação fica aberta 30 s (faixa no HUD com os
votos) e, com a maioria dos humanos ainda na corrida (2 de 2, 2 de 3, 3 de 4…; sozinho, 1), a
corrida é descartada sem resultado nem prêmio e o servidor larga outra com a mesma sala (os
clientes recarregam o grid). Fim: quando todos os
humanos terminam/abandonam (ou 150 s depois do primeiro); quem sai vira abandono. O servidor paga e
registra o resultado de cada um e a sala volta ao lobby.

Arquivos: `scripts/net/` (`net.gd`, `net_protocol.gd`, `progression.gd`, `ranking.gd`,
`net_snapshot.gd`, `net_race_client.gd`), `scripts/server/` (`game_server.gd`, `race_session.gd`,
`account_store.gd`, `turso_db.gd`), `scripts/menu/multiplayer_panel.gd`.

## Testes

```
godot --headless --path . -s res://tests/drive_test.gd      # física: cargas, 0-100, frenagem, curva, sub/sobreesterço
godot --headless --path . -s res://tests/gearbox_test.gd    # câmbio: neutro e ré no acelerador (manual), ré na tecla S (automático)
godot --path . -s res://tests/capture.gd -- <pasta>          # screenshots automáticos
godot --path . -s res://tests/capture_slide.gd -- <pasta>    # screenshots de derrapagem
godot --path . -s res://tests/capture_cameras.gd -- <pasta>  # screenshots das câmeras
godot --headless --path . -s res://tests/ik_test.gd         # IK: erro mão→manopla com o volante girando
godot --path . -s res://tests/capture_ik.gd -- <pasta>       # screenshots dos braços no volante
godot --headless --path . -s res://tests/track_test.gd      # Monza: comprimento, pisos, terreno, largada, zebra, brita, barreira
godot --path . -s res://tests/capture_track.gd -- <pasta>    # screenshots do circuito + medição de FPS
godot --headless --path . -s res://tests/audio_test.gd      # mixer de som: camadas do motor, pneus, pisos, batida
godot --path . -s res://tests/record_audio.gd -- <pasta>     # grava o som de uma largada (WAV + rpm em CSV)
godot --headless --path . -s res://tests/damage_test.gd     # dano: dirigir sem dano, raspada, batidas, destroços, reparo
godot --path . -s res://tests/capture_crash.gd -- <pasta>    # screenshots de uma batida
godot --path . -s res://tests/capture_moods.gd -- <pasta>    # todos os horários × ambientes
godot --path . -s res://tests/capture_boost.gd -- <pasta>    # boost, marcas de pneu, sombra, fantasia
godot --headless --path . -s res://tests/race_test.gd -- 3 9 3  # corrida de 3 voltas, 9 bots, dificuldade mista (+ monaco no fim = em Mônaco)
godot --headless --path . -s res://tests/monaco_test.gd     # Mônaco: traçado, desnível, pisos, túnel coberto, cidade, porto, carro na rampa
godot --path . -s res://tests/monaco_shots.gd -- <pasta> [horário] [ambiente] [prefixo]  # screenshots de Mônaco (+ calçadas, navios, balões, dirigíveis e o céu visto da pista)
godot --path . -s res://tests/capture_decals.gd -- <pasta>   # decalques no carro, SVG do jogador (pasta de teste) e a aba do Estúdio
godot --path . -s res://tests/capture_race.gd -- <pasta>     # menu, grid, HUD da corrida, boxes, mecânicos
godot --path . -s res://tests/capture_loading.gd -- <pasta>  # tela de carregamento (circuito e grid)
godot --path . -s res://tests/capture_ui.gd -- <pasta>       # HUD em cada paleta + garagem
godot --headless --path . -s res://tests/settings_test.gd   # configurações: salvar, remapear, gráficos, áudio, músicas
godot --headless --path . -s res://tests/race_menu_test.gd    # Tab só no treino, horário/ambiente da corrida, música menu x pista
godot --headless --path . -s res://tests/race_control_test.gd # bandeira amarela, safety car, ida ao box, penalidades
godot --path . -s res://tests/capture_yellow.gd -- <pasta>   # instrução da amarela, safety car
godot --headless --path . -s res://tests/ui_nav_test.gd     # menus pelo controle: foco, D-pad, A/B, LB/RB
godot --headless --path . -s res://tests/economy_test.gd    # economia: chances, sorteio, giro, repetidas, loja, estúdio, prêmios
godot --path . -s res://tests/capture_menu.gd -- <pasta>     # menu principal: início, jogar solo, estúdio, galeria, loja, giro
godot --path . -s res://tests/capture_settings.gd -- <pasta> # menu de configurações + monitor de desempenho
godot --headless --path . -s res://tests/compile_check.gd   # carrega todos os scripts (erros de compilação)
godot --headless --path . -s res://tests/ccd_probe.gd       # carro não "para do nada" em zebra/raspão a 320 km/h e não atravessa muros
godot --headless --path . -s res://tests/highspeed_probe.gd # pneus em alta velocidade: carga, aderência, boost, toque de direção, batente
godot --headless --path . -s res://tests/net_test.gd        # multiplayer de ponta a ponta, com votação para recomeçar (precisa do libSQL local)
godot --headless --path . -s res://tests/puppet_wheel_test.gd # rodas dos carros da rede: altura do servidor, esterço e giro, sem tremer
godot --headless --path . -s res://tests/updater_test.gd    # atualizador: versões e download/SHA-256 da última release (internet)
godot --headless --path . -s res://tests/chase_camera_test.gd # câmera de perseguição: frenagem, aceleração, curva, batida
godot --headless --path . -s res://tests/bot_yield_test.gd  # bots dão passagem ao jogador (fácil/médio), o difícil defende, amarela
godot --headless --path . -s res://tests/start_pause_test.gd # pausa na largada congela o semáforo
godot --headless --path . -s res://tests/drs_rule_test.gd   # DRS livre ou só a até 1 s do carro da frente
godot --headless --path . -s res://tests/slipstream_test.gd # vácuo: força no rastro e perda de velocidade com e sem
godot --headless --path . -s res://tests/qualifying_test.gd # classificatória: volta anulada, grid pelos tempos, colisão
godot --headless --path . -s res://tests/qualifying_time_test.gd # classificatória: voltas livres, tempo limite, infração sem efeito
godot --path . -s res://tests/capture_driver.gd -- <piloto.glb> <pasta>  # prévia de um modelo de piloto no carro (sem trocar o asset)
godot --path . -s res://tests/capture_quali_vote.gd -- <pasta>  # menu com as opções da classificatória, relógio dela e faixa da votação
godot --headless --path . -s res://tests/give_back_test.gd  # devolver a posição: resolvido deixando passar, +5 s se não
godot --headless --path . -s res://tests/yellow_pass_test.gd # sob amarela: jogador passa (aviso, +10 s sem devolver) e é passado (aviso)
godot --path . -s res://tests/capture_slipstream.gd -- <pasta>  # vento do vácuo e pisca dos retrovisores
godot --headless --path . -s res://tests/track_bot_probe.gd -- monaco 2 2 [adversários]  # bot sozinho: onde bate/perde tempo
godot --path . -s res://tests/audio_hum_probe.gd -- <pasta>  # grava o som silenciando um bus de cada vez (zumbidos)
godot --headless --path . -s res://tests/offtrack_probe.gd  # fora da pista: velocidade perdida e aderência lateral por piso
godot --path . -s res://tests/capture_online.gd -- <pasta> <porta> --offline  # telas do multiplayer + corrida online
```

Os testes de multiplayer usam um libSQL local no Docker (`docker run -d -p 18080:8080
ghcr.io/tursodatabase/libsql-server`; outra URL com `SPEEDORU_TEST_DB`) e contas de teste próprias
(`user://test_net_*.cfg`, apagadas no fim). O `capture_online` precisa de um servidor rodando na
porta indicada.

Resultado de referência: 0–100 km/h em 2,5 s · 0–200 em 4,9 s · 0–300 em 9,9 s · máx. ~335 km/h
(sem DRS) · 335→0 km/h em 3,3 s / 116 m · 2,2 G lateral a 120 km/h e 3,3 G a 220 km/h.
