# Speedoru

Jogo 3D de Fórmula 1 em estilo anime — **Godot 4.7** (Forward+) + **Blender 5.0**.

## Rodar

Antes de abrir o projeto, compile o código nativo (Rust, pasta `native/`; precisa do
[rustup](https://rustup.rs) — a versão do Rust vem do `native/rust-toolchain.toml` e é instalada
sozinha):

```
cd native
cargo build --release
```

Repita sempre que mudar algo em `native/` (com o editor fechado: no Windows ele segura a DLL). O
editor e os testes usam o build de release (`speedoru_native.gdextension`); o de debug do Rust é
lento demais para a física.

Abra a pasta no Godot 4.7 e aperte F5. A cena principal é `scenes/boot.tscn`, que abre a tela de
carregamento e carrega o menu principal (`scenes/menu/main_menu.tscn`, a garagem) por trás dela.
Jogar solo leva a `scenes/tracks/monza.tscn` (F6 nela também funciona, com o menu de corrida antigo
e sem a tela de carregamento). A área de testes antiga continua em `scenes/test/test_track.tscn`.

### Menu principal (garagem)

`scripts/menu/main_menu.gd` monta a garagem da equipe (piso brilhante, o carro numa plataforma baixa
com a luz saindo por baixo, bancada de ferramentas, portas numeradas, mezanino) e o carro do jogador com o que está
equipado. A câmera fica a nordeste do carro (frente-direita), orbita devagar e não sai da sala; arrastar
com o mouse gira, a roda aproxima (só com o mouse fora dos painéis: sobre a interface a roda é dela).
O carro fica à direita; à esquerda, os botões grandes
(`scripts/menu/menu_ui.gd`):

- **Jogar solo:** pista (abas **Reais**: Monza, Mônaco, Suzuka ou Las Vegas; **Fantasia**: Sky
  Aerobase, Atlantis Abyss ou Rainbow Raceway), modo, voltas, adversários, dificuldade, largada, horário
  e ambiente → Correr. A pista se escolhe num **carrossel** (`scripts/menu/track_carousel.gd`, o
  mesmo dos ajustes da sala multiplayer): o traçado de cada pista (linha central do CSV, norte para
  cima) num anel que gira ao trocar; a da frente fica grande, com nome, extensão, largada (sentido da
  corrida) e um ponto de luz dando a volta. Setas, clique nas de trás ou ←/→ com o foco; na sala, só
  o anfitrião gira (e o carrossel refeito a cada atualização continua o giro do anterior). Acima
  dele, abas das categorias (`RaceSettings.CATEGORIES`: Reais e Fantasia): o anel só tem as pistas
  da aba e, ao voltar a uma aba, volta na última pista escolhida nela (na sala, só o anfitrião vê as
  abas). Na corrida o horário/ambiente ficam como escolhidos (N/B só no treino livre) e
  o carro não muda: a garagem do Tab só existe no treino livre (e pausa o jogo enquanto aberta).
- **Multiplayer:** salas, amigos, grupo, ranking, perfil e a aba **Servidor** (endereço IPv4/IPv6, servidores salvos com nome, últimas conexões e **hospedar** um servidor no próprio PC) (veja [Multiplayer](#multiplayer-servidor-dedicado--turso)); convites e avisos aparecem em qualquer tela do menu.
- **Garagem:** Estúdio, Galeria e Loja, com o carro mudando na hora ao lado. No Estúdio e na
  Galeria o painel é compacto e fica à direita (o carro vem para o centro-esquerda); a Loja usa o
  painel largo à esquerda. O cenário é a garagem da equipe, fechada:
  - ao fundo, o painel claro com o logo SPEEDORU, quadriculado e faixas coloridas; embaixo, a bancada
    de gaveteiros com luz no rodapé, painel de ferramentas, prateleira de capacetes, notebook, o
    quadro de atributos (SPEED, DOWNFORCE, HANDLING, DURABILITY), carrinho vermelho e rack de pneus;
    pilar com faixa de luz e, no canto, porta, extintor e o banner "DRIVE / HAVE FUN";
  - à direita, as portas de enrolar "01" e "02" entre pilares com faixa de luz e, em cima, o mezanino
    de parede clara: porta de vidro do escritório (aceso lá dentro), quadro grande, estante com
    troféus, capacete, caixas e livros, sofá com mesinha e tapete, plantas, guarda-corpo de vidro e
    pendentes;
  - teto escuro com luminárias hexagonais e pendentes iluminando a parede do logo; piso de
    porcelanato brilhante; o carro numa plataforma escura baixa com a luz saindo por baixo da borda e
    espalhando no piso; "DRIVE FAST / HAVE FUN / EVERYDAY" pintado no chão; gaveteiro com capacete,
    pneus e uma planta em primeiro plano (no canto de baixo da câmera do menu).
  - Os destaques (logo, faixas, LEDs, plataforma, quadro de atributos) usam as cores da paleta da
    interface (`Retro.c("accent")`, `accent_2`, `accent_3`) e a garagem se refaz quando ela muda;
    a iluminação geral continua branca e quente.

  Pisos e paredes usam várias texturas procedurais por material (cor com manchas, sujeira ou
  rejunte/emendas multiplicados, normal map e rugosidade variando), em mapeamento triplanar. Sem
  névoa nenhuma: o ambiente da garagem desliga a névoa comum e a volumétrica e fica de fora da opção
  "Neblina volumétrica" das Configurações (meta `no_fog`), então o fundo fica nítido.
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
| Recolocar o carro | R | — |
| Reparar o carro | F (ou botão na garagem) | — |
| Música liga/desliga | M (volume e faixa em Configurações → Áudio) | — |
| Horário (dia → entardecer → noite) | N (ou garagem) | — |
| Pausa (reiniciar / menu / configurações) | Esc | — |
| Configurações (dentro e fora da corrida) | F10 | — |
| Linha ideal (desligada → frenagens e curvas → completa) | L | — |
| Limitador de velocidade (80 km/h: boxes e bandeira amarela) | P | D-pad ← |
| Voltar aos boxes (popup de confirmação; apertar de novo confirma): teletransporte para o box, a volta em andamento recomeça e há um pit stop, com conserto se houver dano | K | Back |
| Pedir passagem (pisca 4× a luz âmbar dos retrovisores) | X | Share |
| Menus: navegar / confirmar / voltar | setas · Enter · Esc | D-pad ou analógico · A · B |
| Menus: abas da garagem e das configurações | — | LB / RB |
| Pausa (na pista; a garagem abre pela pausa) | Esc | Start |
| Páginas da classificação | PgUp / PgDn | — |
| Pneu do próximo pit stop | 1 macio · 2 médio · 3 duro | — |
| Mostrar/esconder ajuda | H | — |
| Ambiente (verão → outono → sakura → fantasia) | B (ou garagem) | — |
| Garagem (peças e pintura) | Tab | Start |
| Votar sim na votação aberta (online: pausa, voltar, recomeçar) | Y | Touchpad |
| Modo espectador (veja abaixo) | F6 (ou botão na pausa) | — |

## Instalar (Windows)

Baixe o instalador da [última release](https://github.com/gabrielcamposmartins/speedoru/releases/latest)
— o link fixo `https://github.com/gabrielcamposmartins/speedoru/releases/latest/download/Speedoru-setup.exe`
sempre aponta para a versão mais nova. Ele instala só para o usuário atual, sem pedir
administrador, em `%LOCALAPPDATA%\Programs\Speedoru` (atalho no menu Iniciar e, se marcado, na
área de trabalho). Para atualizar, instale a versão nova por cima. Perfil, configurações e conta
ficam em `%APPDATA%\Godot\app_userdata\Speedoru` e continuam depois de atualizar ou desinstalar. Até a
0.4 o projeto se chamava F1 Gatcha e a pasta era `...\app_userdata\F1 Gatcha`: na primeira vez que o
Speedoru abre, o autoload `UserDataMigration` (o primeiro da lista) copia tudo de lá — perfil,
configurações, interface, a conta do multiplayer e os SVGs — se a pasta nova ainda estiver vazia
(a antiga fica como está). O ícone (uma roda de F1: pneu com a faixa amarela, raios ciano, pinça
vermelha) sai de `python tools/make_icon.py` (`assets/ui/speedoru_icon.png` e `.ico`) e vai na janela,
no `.exe` (export com `modify_resources`), no instalador e nos atalhos do menu Iniciar e da área de
trabalho.

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
pneus de 305/405 mm · 880 kg (um pouco acima do mínimo real, para os carros assentarem mais e as batidas pesarem).

Cada peça é um `.glb` separado em `assets/car/parts/<slot>/<variante>.glb`:

| Slot | Variantes |
|---|---|
| `chassis` (monocoque com cockpit) | standard |
| `nose` | standard, pointed, duckbill (bico de pato: ponta larga e chata com "narinas"), shark (tubarão: agulha longa com canards), hammer (tubarão-martelo: barra larga com "olhos"), dragon_snout (focinho de dragão: escamas, chifres, narinas e dentes), drill (broca: cone com rosca em espiral), tusks (presas curvas) |
| `front_wing` | standard (4 elementos), lowdf (3 elementos), gull (gaivota: plano principal em arco, pontas viradas para cima), biplane (biplano: segundo plano inteiro em cima, com montantes), bat (morcego: placa recortada com três pontas e varetas), ring (anel no lugar da placa lateral), delta (bordo de ataque varrido), scales (escamas no plano principal) |
| `rear_wing` (+ beam wing, `DRSFlap` animado) | standard, lowdf, highdf, twin (dupla: segundo plano no alto das placas) e as de formato livre (`build_rear_wing_creative`, largas até ±0,98 m como a asa dianteira, sem placas laterais, cada uma com um flap de DRS central): dragon (ossos saindo de um "pulso", membranas com a borda recortada, garras e corpo com escamas e espinhos), butterfly (borboleta: asa da frente e de trás em lobos, nervuras, "olhos" e antenas), phoenix (fênix: leque de penas nas três cores curvando para cima, penas de cauda), omega (arco largo que desce nas pontas por fora das rodas), blade (lâmina: delta muito varrido com aletinhas e quilha) |
| `sidepods` | downwash, slim, gills (guelras: aletas atravessadas no topo), jet (turbina: boca redonda com anel, cone e hélice), scales (escamas de dragão no topo), vents (persianas: frestas inclinadas na lateral), bulge (musculoso: mais largo e alto, com friso), periscope (periscópio: torre de captação) |
| `engine_cover` (airbox, T-cam, estrutura de impacto, luz de chuva) | standard, sharkfin, spine (espinha de dragão: barbatanas em dente de serra), twing (barbatana com asa em T), horns (chifres curvos ao lado da entrada de ar), scales (escamas na crista), twin_airbox (duas entradas de ar), exhaust (escapamentos aparentes com bocas em brasa e aletas de calor) |
| `floor` (assoalho, difusor, prancha) | standard |
| `halo` | standard, winged (com aletas laterais, carenagem no pilar e crista), crown (coroa de espinhos), airfoil (asa em cima), ribbed (costelas em volta do tubo), horned (chifres atrás) |
| `mirrors` (`MirrorGlassL/R` no mesmo lugar em todas) | standard, bullet (bala: carenagem pontuda com aleta), eye (olho: carcaça redonda com sobrancelha), fin (aleta alta), spiked (espinhos), winglet (asinha para fora) |
| `suspension_front`, `suspension_rear` | standard |
| `cockpit` (`SteeringWheel` animado, encostos) | standard |
| `driver` (piloto humanoide: macacão, luvas, botas, HANS, cintos, capacete com viseira) | standard |
| `tyre` (`_front` / `_rear`) | slick |
| `rim` (`_front` / `_rear`) | covered, spoked, turbine (14 pás curvas), star (estrela: 5 raios em cunha), mesh (colmeia: pás cruzadas), yspoke (raios em Y), disc (disco liso com furos), shuriken (4 lâminas curvas) |

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
troca por materiais toon (`scripts/car/car_livery.gd`). A borracha dos pneus (`Tire`) é preta e
lustrosa: faixa de brilho toon forte, verniz fino (clearcoat) e borda de luz.

### Adicionar uma variante de peça

1. No script do Blender, crie a função/variante e registre em `PART_BUILDERS` (ou `WHEEL_BUILDERS`).
2. Rode o script para exportar o `.glb`.
3. Registre a variante em `scripts/car/car_part_catalog.gd` (rótulo e `stats` aerodinâmicos).
   A garagem passa a mostrá-la sozinha.

## Estrutura no Godot

- **Código nativo** (`native/`, Rust com [godot-rust](https://godot-rust.github.io) 0.5): tudo o que roda
  a cada passo de física ou a cada quadro para todos os carros. Cada classe é a base de um script
  (`F1Car extends F1CarCore` etc.), que continua com o resto (montagem, materiais, regras que só
  acontecem às vezes) — as cenas usam o tipo nativo no nó e o script por cima:
  - `F1CarCore` (`car.rs`) — `F1Car`: pneus, motor, câmbio, freios, aerodinâmica, direção, DRS,
    bateria, fumaça e a marionete da rede;
  - `BotDriverCore` (`bot.rs`) — `BotDriver`: direção, velocidade, tráfego, boxes e sair do muro;
    lê os outros carros numa foto por passo de física, comum a todos os bots;
  - `RaceEntryCore` / `RaceManagerCore` (`manager.rs`) — `RaceEntry` (os campos que mudam a cada
    passo) e `RaceManager`: posição na pista, voltas, marcas de progresso, boxes, limites de pista,
    contramão, carros-fantasma, posições, regra do DRS e colisões punidas; as regras do GDScript
    (`_on_line_crossed`, `_penalize`, `_notify`, pit stop do jogador) são chamadas de lá;
  - `PathCore` / `LineCore` (`path.rs`) — cópia da `TrackPath` e da `RacingLine` depois de
    montadas: projeção na pista, posição/direção num ponto e perfis (o GDScript delega a elas);
  - `RaceNative.update_slipstream` (`race.rs`) — o vácuo de todos os carros;
  - `CarAudioCore` (`audio.rs`), `CarDamageCore` (`damage.rs`), `CarEffectsCore` e
    `TrailRibbonCore` (`fx.rs`) — som, contatos/faíscas/peças soltas, efeitos e rastros do carro;
  - `SlipstreamFxCore` (`fx.rs`), `RacingLineGuideCore` (`guide.rs`), `SceneryAnimatorCore` e
    `TrackOffshoreCore` (`scenery.rs`) — vácuo visual, linha ideal e o cenário em movimento.
  Ficaram em GDScript só os scripts que custam menos de ~2 ms por segundo (HUD, câmeras, música,
  menus). As tabelas dos pisos vêm do `track_surface.gd`. Medido com `tests/frame_probe.gd`.
- `scenes/car/f1_car.tscn` — `F1CarCore` (um `VehicleBody3D`: 880 kg, centro de massa customizado)
  com 4 `VehicleWheel3D` e caixas de colisão. O nó `Visual` (`CarAssembly`) instancia as peças
  conforme o `CarConfig`.
- `scripts/car/f1_car.gd` + `native/src/car.rs` — motor (curva de torque + limite de 760 kW), câmbio de 8 marchas, ré,
  controle de tração, freios limitados pela carga, downforce ∝ v² dividida entre os eixos, arrasto,
  DRS e animação do flap/volante. Entradas em `throttle_input`, `brake_input`, `steer_input` (prontas
  para IA quando `player_controlled = false`).
- **Modelo de pneu** (em `native/src/car.rs`, `update_tires`): o atrito embutido do VehicleBody3D é desligado
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
  posições, pit stops e chegada; quando o primeiro recebe a bandeirada, todos os outros veem o
  aviso "BANDEIRADA! fulano venceu" (`leader_flag`; online pelo evento `leader_finished`). Ao final
  vem a **tela de vitória** (`scripts/ui/podium_screen.gd`): os três primeiros carros, cópias com
  as peças, cores e skin de cada um, estacionados num pódio num estúdio próprio (mundo 3D separado),
  com a plaquinha 1º/2º/3º em ouro, prata e bronze e o nome em cima (as cópias são marionetes como
  os carros online, `set_puppet`: congeladas, o VehicleBody3D regravava as rodas na origem do mundo); depois o resultado (tempo +
  penalidades), com os créditos ganhos (online chegam quando a sala fecha: "Calculando prêmio…"),
  as missões e conquistas completas e, para quem venceu online, o botão da roleta do vencedor.
- **Bots** (`BotDriver`, filho de cada carro): seguem a linha de corrida de curvatura mínima de Monza
  (`assets/track/monza/monza_raceline.csv`, TUMFTM) com um perfil de velocidade calculado pela
  aderência lateral/downforce, frenagem e potência (`RacingLine`), escalado pela dificuldade
  (fácil 84% da aderência, médio 91%, difícil 97,5%; reação na largada e ruído de trajetória).
  Mantêm a faixa do grid na largada e **ultrapassam sem medo**: começam com 90 m de reta à frente
  e um pouco mais rápidos que o da frente (escolhem um lado e mantêm até passar), seguem perto o
  bastante para pegar o vácuo e não desistem já lado a lado na entrada da curva; para evitar a
  batida abrem espaço lado a lado, tiram o pé se sobrepõem e só voltam para a linha 10 m à frente.
  Fazem o pit stop numa volta sorteada (80 km/h nos boxes, param no box da equipe, trocam para
  duro/médio). **Presos** (encostados no muro, rodados, sem avançar querendo andar — e sem carro
  logo à frente, para não confundir com tráfego): dão ré esterçando para apontar de volta à pista
  (até 3 vezes, cada vez mais longa); se não saírem, são levados de volta à pista num vão do
  tráfego (`tests/bot_recover_test.gd`).
  Usam os mesmos carros e a mesma física do jogador (sem retrovisores, mais leves). Um bot
  que perde uma roda abandona (DNF). Na corrida o reparo instantâneo (F) fica desligado.
  Com jogadores humanos: todos deixam mais espaço (folga maior atrás de você e uma faixa mais
  larga em volta), sem frear nem desviar instantâneo — a batida continua possível. Bots fácil e
  médio **respeitam ataques**: com você chegando por trás (até 25 m, mais rápido) ou lado a lado,
  abrem para o outro lado e tiram um pouco o pé (10% / 5%); o difícil defende a posição. Sob
  bandeira amarela ninguém dá passagem (`tests/bot_yield_test.gd`). Na corrida online os humanos
  de todos os aparelhos contam como jogadores para essas regras.
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
- **Boxes:** os bots fazem fila indiana na pista dos boxes e esperam qualquer carro que esteja no
  caminho que vão fazer (na faixa rápida, entrando ou saindo de uma vaga, ou parado na vaga perto
  da sua, humanos inclusive); só passam para a faixa da vaga nos últimos 18 m (antes passavam por
  cima das vagas vizinhas) e só saem do box quando ninguém vem avançando pela faixa rápida.
  Enroscados saindo do box são postos na faixa rápida logo à frente. Numa corrida de 3 voltas os
  toques nos boxes caíram de 7 para 0 (`tests/race_test.gd` mede toques nos boxes, ultrapassagens,
  colisões punidas, ré e voltas à pista).
- **Colisões no box** (Jogar solo, menu da corrida e sala online; ligadas por padrão): desligadas,
  nenhum carro — jogador e humanos online inclusive — colide com outro enquanto um dos dois está
  nos boxes (a menos de 40 m); voltam a colidir quando os dois saem e se afastam. Os bots já se
  atravessam entre si nos boxes sempre (`RaceManagerCore.update_pit_ghosts`, `pit_collisions`;
  online o cliente faz o mesmo com o carro previsto). `tests/pit_collisions_test.gd`.
- `tests/race_test.gd` roda uma corrida inteira sem janela (o jogador também pilotado por bot) e
  confere que todos terminam e fazem o pit; `tests/capture_race.gd` gera capturas do HUD.

## Economia: loja, roletas, galeria e estúdio

Mesmo modelo de negócio do Pokeru (nada se vende por dinheiro real; o gacha é o sumidouro da moeda
e a meta de longo prazo). Catálogo e regras em `scripts/economy/shop_catalog.gd`; perfil do jogador
(autoload `Profile`, `scripts/economy/player_profile.gd`) salvo em `user://profile.cfg`.

- **Moeda:** créditos. Conta nova: 10.000. Corrida: 200 / 300 / 400 créditos por volta completada
  (bots fácil / médio / difícil; mista 300), ou seja 2.000 / 3.000 / 4.000 em 10 voltas; abandono recebe
  metade (online, sair depois que os três primeiros chegaram recebe inteiro), desclassificado e treino livre não recebem. O resultado mostra quanto entrou.
- **Ticket = um giro** numa roleta, 2.500 créditos. Sem estoque, sem pacote, sem giro de 10, sem
  desconto. Duas roletas temáticas e sem sobreposição, com **peças, decalques, as cores de luz
  (brilho do boost e neon) e auras**: **Neon** (asas leves, bico, sidepods; sakura,
  asas, cometa, coração, onda, listras, raio; boost Hiperluz, Gelo, Rosa choque, Violeta; neon
  Aurora, Ciano, Sakura; auras Raios, Pétalas de sakura, Arco-íris, Estrelinhas, Bolhas de
  sabão e Flocos de neve) e
  **Dragão** (id `inferno`, o nome antigo, que fica nos perfis e no servidor; asas traseiras, barbatana, rodas raiadas; chamas, garras, logo S, xadrez, shuriken,
  faixas duplas; boost Chama solar, Rubi, Ouro; neon Lava, Âmbar, Carmesim, Violeta; partículas
  Fogo no chão, Brasas, Chuva de moedas e Fumaça colorida), 46 e 44 itens.
  Peças: a Neon tem as de luz, céu e máquina (asas traseiras Borboleta e Ômega, sidepods Turbina e
  Periscópio, asas dianteiras Gaivota, Anel e Delta, bicos de pato, Tubarão-martelo e Broca, rodas
  Turbina, Colmeia e Disco…); a Dragão, as de fogo e bicho (asas traseiras Fênix, Dragão, Dupla e
  Lâmina, focinho de dragão, Tubarão e Presas, Morcego, escamas, chifres, Guelras, rodas Estrela,
  Shuriken e Raios em Y…).
- **Sorteio:** um degrau de raridade com fatia fixa e, dentro dele, uma peça com chance igual. Sem
  pity nem garantia. Gerador criptográfico (`Crypto`), e a loja mostra a mesma tabela que o sorteio
  usa.

| Raridade | Fatia | Itens (Neon / Dragão) | Chance de cada (Neon / Dragão) | Repetida devolve |
|---|---|---|---|---|
| Lendário | 2,5% | 6 / 6 | 0,42% | 3.600 a 4.680 |
| Épico | 6% | 8 / 10 | 0,75% / 0,6% | 2.100 a 2.730 |
| Raro | 10% | 11 / 11 | 0,91% | 1.350 a 1.755 |
| Incomum | 26% | 13 / 10 | 2% / 2,6% | 900 a 1.170 |
| Comum | 55,5% | 8 / 7 | 6,94% / 7,93% | 600 a 780 |

- **Tickets ganhos:** a roleta do vencedor (online) pode dar um ticket; na loja aparece "USAR TICKET"
  em cada roleta, um giro sem gastar créditos (`Profile.tickets`, `spin(roleta, true)`; online o
  servidor confere e gasta).
- **Exclusivos** (roleta `exclusive`, oculta: `ShopCatalog.is_hidden`, fora da loja e das chances):
  só saem como prêmio — roleta do vencedor, prêmio da semana das missões e conquistas. São a
  **asa traseira Coroa Real** e o **bico Lança** (peças novas do `build_f1_car.py`), os títulos
  **Tempestade**, **Fantasma** e **Soberano do Céu** (`ShopCatalog.EXCLUSIVE_POOL`) e a luz de
  ultrapassagem **Sirene** (só pela conquista Interceptor). `Profile.grant_item` entrega (repetido
  vira créditos) e `pick_exclusive` sorteia um que a conta ainda não tem. A Galeria mostra as abas
  "Luz de ultrapassagem" e "Títulos", com "prêmio exclusivo" no lugar da chance.
- **Faíscas de titânio aposentadas** (`ShopCatalog.RETIRED`): viraram efeito de todo carro (abaixo);
  quem tinha recebe 780 créditos uma vez (carregar o perfil não grava: a troca vai para o arquivo
  na próxima gravação, e até lá cada carga devolve o mesmo valor).
- **Som do giro** (`scripts/audio/ui_sounds.gd`, gerado por código): um "toc" macio de lingueta de plástico a cada
  cartão que passa pelo marcador (no máximo 20 por segundo no começo, mais grave ao desacelerar) e
  um arpejo de sino quando o prêmio aparece (uma nota a mais no raro e no lendário).
- **Prêmio novo** (algo que a conta ainda não tinha): chuva de confetes (`scripts/ui/confetti.gd`,
  dois canhões nos cantos, com a cor da raridade) e, logo depois do arpejo, um brilho suave no som
  (`UiSounds.discovery`: acorde de dó com sétima e nona entrando nota a nota e três pingos agudos
  baixinhos). Repetidas não têm.
- **Repetida vira créditos:** 30% do preço de tabela; o giro nunca sai vazio. Um lendário
  específico custa em média 240 giros (600 mil créditos).
- **O que se coleciona:** peças de desempenho (asas, bico, sidepods, cobertura, rodas raiadas:
  trocam aderência por velocidade, nunca melhores em tudo), decalques, as cores do **brilho do
  boost** e do **neon** (`ShopCatalog.GACHA_COLORS`: só se equipa cor ganha) e as **auras**
  (rastros de partículas, tipo `trail`, um equipado por vez, ou nenhum). Vêm com a conta, fora
  do sorteio: todas as peças padrão, os decalques Estrela e Disco de número e o boost Ciano. Conta
  nova não tem neon (desligado até ganhar um).
- **Cores livres:** pintura (3 cores), capacete, macacão e rodas são de graça e com qualquer cor
  (seletor de cor e sugestões). As 25 pinturas prontas (`ShopCatalog.PAINTS`) aplicam as 3 cores
  de uma vez; a pintura equipada é a que bate com as cores (ou nenhuma).
- **Minhas pinturas** (aba Pinturas do Estúdio): salva a combinação atual — 3 cores, esquema e
  acabamento — com um nome (mesmo nome substitui, até 24), aplica e apaga. Ficam no aparelho, fora do
  perfil (`user://paint_presets.cfg`, `PlayerProfile.custom_paints`), e valem offline e online.
- **Peças** (aba do Estúdio e da Galeria): separadas por categoria (bico, asas, sidepods, cobertura,
  halo, retrovisores, rodas), com quantas a conta tem de cada; o efeito principal fica no canto do
  cartão. A arte do cartão (e a do giro da loja) é a **silhueta branca da peça**
  (`scripts/economy/part_silhouette.gd`): a peça é desenhada uma vez numa SubViewport de fundo
  transparente, toda branca, na vista que mais diferencia as variantes (bico e sidepods de cima ou
  de lado, asas de frente/de trás, cobertura de lado, rodas só a face de fora) e fica em cache;
  todas saem em ~0,6 s, juntas, na primeira vez que a aba abre. Sem placa de vídeo (headless) o
  cartão mostra o nome do lugar. Conferência: `tests/part_silhouette_probe.gd`.
- **Esquemas de pintura** (aba do Estúdio, grátis; `CarConfig.PAINT_SCHEMES`): como as 3 cores se
  dividem pela carroceria. Clássico (as cores nas peças como o modelo foi pintado), Dois tons
  (cima/baixo com filete), Faixas de corrida, Diagonal, Flechas (chevrons), Degradê (frente → trás),
  Metades (esquerda/direita), Relâmpago (zigue-zague), Ondas, Camuflagem, Pontas (bico e asas) e
  Faixa lateral. A pintura é o shader `shaders/car/car_paint.gdshader` (toon, com os acabamentos
  como parâmetros): como todas as malhas da carroceria ficam no espaço do carro, a posição de cada
  ponto decide a cor (bordas suavizadas em ~1 pixel); rodas, volante, piloto e flap do DRS usam a
  variante `#plain` (cor do slot, para o desenho não "andar" quando giram). As prévias do Estúdio
  (carro de lado e de cima, nas cores atuais) usam as mesmas contas em `CarLivery.scheme_weights`.
  Os bots têm um esquema por equipe.
- **Acabamento** (aba do Estúdio, grátis): pintura brilhante, metálica (flocos + verniz),
  perolada (borda iridescente + verniz), acetinada, fosca ou cromada; rodas polidas, cromadas,
  acetinadas ou foscas (`CarLivery.apply_paint_finish`, shader `car_rim` com reflexo e rugosidade
  por acabamento; na pintura, `CarLivery.PAINT_FINISH_PARAMS` → parâmetros do shader `car_paint`).
- **Estúdio** (garagem e Tab na corrida): coluna de abas só com ícones (pinturas, esquema, cor 1/2/3,
  capacete, macacão, rodas, boost, neon, partículas, decalques, peças; o nome no tooltip) e uma grade de 2
  colunas em que toda opção tem o mesmo tamanho. As abas de cor livre têm o seletor (o carro muda
  enquanto se arrasta) e uma grade de sugestões; boost e neon mostram só as cores ganhas (o neon
  com Desligado; as partículas, os rastros ganhos e Nenhum). Peças e decalques só os da conta. Tudo é conferido de novo antes de ir para o
  carro (peça, decalque, boost ou neon que a conta não tem volta para o gratuito; cor livre só
  precisa ser válida).
- **Decalques** (aba do Estúdio com a estrela, grátis; `scripts/car/car_decals.gd`): adesivos SVG
  nas **laterais**, no **bico**, na **entrada de ar** e nas **placas da asa traseira** (os lugares de
  dois lados recebem o mesmo desenho: o lado direito, o que a garagem mostra, é a referência e o
  esquerdo é o **reflexo exato** dele — imagem virada, posição e giro espelhados no meio do carro —,
  então chamas, setas e asas apontam para o mesmo lado nos dois lados; "Espelhar no lado
  esquerdo" desligado faz cada lado ler o desenho normalmente, para textos, e já vem desligado no
  logo S e nos SVGs do jogador). Cada um com **cor livre** (só o seletor de
  cor), e posição e tamanho livres numa **prévia do lugar** (`StudioPanel.PositionPad`: o lugar na
  proporção real e na cor da pintura, o limite até onde o desenho pode ir e o desenho como fica;
  arrastar move, roda = tamanho, Shift+roda = giro, Ctrl+roda = largura, duplo clique centraliza)
  ou nos sliders **tamanho**, **largura**, **giro**, **horizontal** e **vertical**, e um botão que
  centraliza e volta ao tamanho padrão. Na garagem a câmera vai até o lugar escolhido. Arrastar e
  sliders mudam o carro na hora; o perfil grava (e, online, manda ao servidor) quando os valores
  param de mudar. 15 desenhos (`assets/decals/`, gerados por `python tools/generate_decals.py`: estrela,
  raio, chamas, bandeira quadriculada, sakura, coração, asas, listras, garras, disco de número,
  onda, logo S, cometa, shuriken, faixas duplas): estrela e disco de número vêm com a conta, os
  outros saem nas roletas. Os **SVGs do jogador** são livres: "Abrir pasta dos meus SVG" abre `user://decals` (desenho branco com fundo
  transparente, até 512 KB) e "Recarregar" os lista. No carro são nós `Decal` projetados só na
  carroceria (camada `CAR_LAYER`) e tingidos com a cor. Ficam em `equipped["decals"]` (validado
  também pelo servidor); online os outros veem os padrão, os SVGs próprios só aparecem para quem
  tem o arquivo.
- **Skin (pintura livre)** (aba do Estúdio com o rolo de pintura; `scripts/car/car_skin.gd`,
  `car_skin_template.gd`, shader `car_paint`): o jogador pinta o carro inteiro num editor de
  imagem. **Exportar molde…** salva (diálogo do sistema, começa em Documentos/Speedoru) um PNG
  2048×2048 com o carro **planificado**: lado esquerdo, lado direito, cima (vale também para baixo),
  frente e trás, do jeito que o carro está (cores, esquema e skin atual), sem luz, só as superfícies
  pintáveis, com contorno e legendas fora do carro, e ao lado o **`_linhas.png`** (guia, para usar
  como camada de cima e esconder antes de exportar): o contorno de cada peça e de cada parte dela,
  as bordas onde uma superfície passa por cima de outra (elementos da asa dianteira, sidepods sobre
  o assoalho, cobertura do motor sobre o monocoque), **hachura vermelha nas áreas muito inclinadas**
  para a vista (o desenho estica ali) e o nome das peças em cada região; linhas pretas com contorno
  branco, visíveis sobre qualquer cor (uma passada de identificação por quadro: peça, profundidade e
  inclinação, com as linhas achadas por um shader 2D onde esses valores mudam). **Importar skin…** lê o PNG/JPG/WebP pintado por
  cima (numa thread: uma imagem grande leva alguns segundos e o jogo não pode travar online) e já
  equipa; o que ficar **transparente** mostra a pintura normal. "Tirar a skin" volta às cores; "Suas
  skins" lista as importadas (clique usa, botão direito apaga).
  - **Planificação por projeção** no espaço do carro (todas as peças da carroceria estão nele): cada
    face pega a vista para a qual mais aponta (maior componente da normal), na caixa X ±1,1 m,
    Y 0–1,2 m, Z ±3,2 m (cabe em todas as peças). O molde vale para qualquer combinação de peças
    (um UV por peça quebraria a cada troca; e cada peça é uma malha só, a asa dianteira inteira
    inclusive). **Duas camadas por vista**, para nenhuma superfície dividir a pintura com outra:
    os quadros **visíveis** (250 px/m: o que se vê de cada lado) e os **escondidos** (120 px/m: o
    que fica atrás de outra superfície virada para o mesmo lado — o monocoque atrás do sidepod, a
    face de dentro do outro sidepod, os elementos de baixo da asa), mais o quadro de **baixo**.
    Quem é escondido sai do **mapa de profundidade** (`CarSkinTemplate.depth_texture`): em cada
    vista, a profundidade (16 bits) da superfície visível, renderizada uma vez por combinação de
    peças e guardada; o shader compara a profundidade do ponto com a do mapa (folga de 2 cm). Sem
    isso, um desenho na lateral aparecia repetido em tudo que estava atrás dela. O molde é
    renderizado com câmeras ortográficas do tamanho exato de cada quadro (`CarSkin.face_camera`)
    e o shader em modo molde (`template_view`/`template_layer`/`template_out`), com o mesmo mapa,
    então o que se pinta cai exatamente onde aparece; o `skin_test` confere a ida e volta (molde →
    importado → molde de novo dá a mesma imagem) e que pintar o visível não pinta o escondido e
    vice-versa. Peças que se mexem (rodas, volante, piloto, flap do DRS) ficam com a cor do slot.
    Skins feitas na 0.7.0 (layout antigo, sem as camadas) precisam ser pintadas de novo.
  - **Arquivos** (`user://skins/`): `<hash>.hd.webp` (2048 px, de quem importou) e `<hash>.webp` (versão
    da rede, 1024 px, até 1 MB; se não couber cai para 768/512). O hash SHA-256 dessa versão é o que
    fica em `equipped["skin"]`.
  - **Online** todos veem: ao equipar (ou entrar), se o servidor não tem a imagem ele pede ao jogo
    (`skin_need` → `skin_upload`, só da skin equipada pela conta, conferida: hash, tamanho, WebP
    quadrado). Quem precisa de uma skin que não tem (carros dos outros na corrida) pede
    (`skin_get` → `skin`) e o carro troca a pintura quando ela chega; fica guardada no aparelho. O
    servidor guarda as imagens em `user://server_skins/` (o hospedado, na pasta do host).
- **Engenharia** (primeira aba do Estúdio, a da chave inglesa, na garagem e no Tab da corrida): o
  comportamento do carro, nunca a aparência. Grupos Aerodinâmica (carga, arrasto, balanço), Freios
  (força, balanço), Pneus (aderência dianteira/traseira, ângulo de pico, queda depois do limite,
  sensibilidade à carga), Direção (esterço em baixa/alta, velocidade do volante), Motor e câmbio
  (relação final, giros de troca do automático, freio-motor), Suspensão (molas, amortecedores,
  alturas e barras estabilizadoras por eixo) e Assistências (margem). Cada parâmetro tem nome
  amigável, limites que fazem sentido, um slider largo com trilho fino e uma marca no valor
  padrão, botões redondos − / + (passo fino; com Shift, grosso), ↺ ao lado do valor só quando ele
  mudou (volta ao padrão) e um tooltip em cartão (`Retro.make_tooltip`: explicação com quebra de
  linha, valor atual, padrão, limites, passos e o efeito do botão). O padrão é o de fábrica, menos
  na direção do jogador (`CarSetup.PLAYER_DEFAULTS`): esterço em alta de 1,0° e volante 0,5 — contas
  novas já começam assim e "Restaurar" volta a isso; contas que já existiam mantêm o que tinham, e os
  bots usam o de fábrica. No controle, ↑/↓ andam pelos sliders (←/→ ajustam). Fica salvo no perfil
  (`equipped.setup`) e vale na corrida. Potência, desgaste e regras não entram
  (são iguais para todos). Catálogo em `scripts/economy/car_setup.gd`.
- **Galeria:** mesmo layout do Estúdio (abas Peças, Decalques, Boost, Neon e Aura, grade de 2 colunas); cada item
  com arte, raridade e selo ("✓", "FALTA", "GRÁTIS"). Clicar mostra **no carro** como ficaria (sem
  equipar): a câmera orbita até a peça (ou até a lateral, onde o decalque aparece) e a centraliza,
  alternando o sentido a cada clique (horário, anti-horário). O cartão de detalhes traz raridade, roleta, chance exata, quanto devolve
  se sair repetida e o botão Equipar (se for sua) ou Girar na roleta (se faltar).
- **Origem dos itens** (Estúdio e Galeria): a coleção da conta no servidor e a deste aparelho
  podem ser diferentes; o selo diz de onde vem o que é de um lado só — **CONTA** (só no servidor),
  **APARELHO** (só aqui), e apagados, sem dar para usar agora, **SÓ ONLINE** (offline, item só da
  conta) e **SÓ OFFLINE** (servidor que não aceita os itens do aparelho). Nos dois lados: sem selo.
  O Net guarda a coleção da conta a cada conexão no arquivo da conta (`[collection] by_server`,
  por endereço: o servidor da internet e o hospedado são contas diferentes); sem nunca ter
  conectado ao servidor atual, não aparece selo. `PlayerProfile.origin()`/`badge_of()`;
  captura em `tests/capture_origin.gd`.
- **Loja:** só tickets. Nenhum cosmético se compra direto; sem rotação nem ofertas. As paletas da
  interface vêm todas com o jogo (troca em Configurações → Tela).
- Não há presentes/vínculo como no Pokeru (o jogo não tem personagens para presentear).

## Interface: estilos Speedoru e Retrô

A interface tem dois estilos (`scripts/ui/retro.gd`, classe `Retro`), escolhidos em
Configurações → Tela → Estilo da interface (salvo em `user://interface.cfg`, chave `ui/style`):

- **Speedoru (padrão):** pop/anime da paleta de referência do jogo: magenta `#FF2BD6`, ciano
  `#00E8FF`, amarelo `#FFE73B`, roxo `#A259FF`, vermelho `#FF2E66` sobre tinta `#0D0D14` e
  azul-noite `#1E1342` (mais rosa `#FFB0F0`, ciano claro `#6CF3FF` e branco; o verde-menta
  `#3DFFA8` é o único tom extra, para status bom/recorde pessoal). Paleta fixa. Exo 2 itálica
  pesada nos títulos e números (`assets/fonts/exo2/`, OFL); botões em paralelogramo
  (`StyleBoxFlat.skew`) com sombra dura deslocada no lugar do brilho; painéis com faixa magenta à
  esquerda, filete ciano embaixo e retícula no canto; cantos em triângulo; etiquetas inclinadas
  com "///"; barras em paralelogramo; logo com bandeira quadriculada e "AM I RIGHT?". Fundo dos
  menus: `shaders/ui/speedoru_backdrop.gdshader` (linhas de velocidade animadas e retícula).
  `Retro.is_pop()` diz se ele está ativo; cada peça de desenho (`draw_panel`, `draw_tag`…) tem
  as duas versões.
- **Retrô (synthwave):** o visual original, descrito abaixo, com as cinco paletas.

Trocar o estilo refaz o `Theme` no lugar, reabre as configurações na mesma aba e remonta o menu
principal (`MenuUI._restyle`).

Retrô: visual synthwave + monitor CRT + HUD de ficção científica:

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
- **Paleta** (só no estilo Retrô) escolhida em Configurações → Tela (salva em `user://interface.cfg`); todas vêm com o jogo.
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
  boxes é você quem aciona e só você desliga (o pit stop não mexe nele); passar de 80 km/h na pista
  dos boxes continua dando +5 s.
- **Voltas e classificação:** depois da bandeirada as voltas param de contar (`finish_laps`; o carro
  segue andando e cruzando a linha). Ordem ao vivo e resultado final: primeiro quem completou mais
  voltas; quem levou volta e recebeu a bandeirada fica atrás de quem tem mais voltas mesmo que esse
  ainda não tenha cruzado a linha (com as mesmas voltas, quem ainda corre está na volta seguinte).
  No resultado, quem levou volta aparece com "+1 volta"; a tabela e as penalidades rolam numa área
  do tamanho da tela, com os botões sempre visíveis.
- **Bandeira amarela:** entra quando uma batida arranca peças (ou quebra uma roda). Um painel no
  topo mostra a instrução da sua situação, com a tecla certa (ou botão, se estiver no controle):
  - quem bateu: "Pressione [K] para voltar aos boxes ou vá sozinho 1:40". O botão (depois do
    popup de confirmação) leva direto ao box para o conserto; dá para ir dirigindo; se não chegar em uma volta (tempo da sua melhor volta,
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
  car entra à frente do líder com a barra de luzes âmbar piscando, anda a até 180 km/h na linha ideal (mais devagar
  nas curvas, pelo perfil de velocidade) e aparece no minimapa (SC). Quem não bateu pode aproveitar para trocar pneus; isso não muda a bandeira.
- **O safety car** (`blender/build_safety_car.py` → `assets/car/safety_car/safety_car.glb`, ~62 mil
  triângulos): cupê GT de 4,5 m modelado em cima de fotos do safety car da F1 (AMG GT R de 2018).
  - **Proporções da foto lateral:** com a escala pelo entre-eixos de 2,63 m, o nariz fica 0,78 m à
    frente do eixo dianteiro e a traseira 1,0 m atrás do traseiro. A base do para-brisa fica a
    0,91 m, o teto começa em 1,23 m e chega a 1,26 m, a cintura fica a 0,875 m e a tampa traseira a
    0,88 m. Sobreposto à foto na mesma escala, o contorno coincide do nariz à asa.
  - **Carroceria:** capô longo com duas saídas de ar com lâminas, cabine recuada em fastback e
    janela lateral em gota.
  - **Frente:** grade de lâminas verticais com a placa "SAFETY CAR", entradas de ar com lâminas,
    "cortinas" de ar e faróis com LED.
  - **Lateral e base:** saída de ar com friso cromado atrás da roda da frente, maçaneta, splitter e
    saias.
  - **Traseira:** asa baixa (10 cm acima da tampa), difusor com aletas e escape duplo no centro.
  - **Rodas:** 10 raios pretos com aba polida e pinças coloridas.
  - **Barra de luzes:** alta, sobre uma base no meio do teto (onde fica na foto). As âmbar piscam
    alternando esquerda e direita, junto com os LEDs âmbar no alto do para-brisa e do vidro
    traseiro; a verde do meio fica apagada. A placa de trás fica iluminada. À noite (e no
    entardecer) acendem os faróis, e o brilho âmbar ilumina a pista em volta.
  - **Grafismos (como os do carro real):** nas portas, emblema grande com a linha de texto embaixo e
    os blocos pretos inclinados. No capô, "SAFETY CAR / DRIVE SAFELY" com traços, emblema e linha do
    campeonato. Faixa preta com "SAFETY CAR" no para-brisa e no vidro traseiro, que tem também
    "DRIVE SAFELY" embaixo. Emblema acima da placa traseira, e placas claras "SAFETY CAR" na frente
    e atrás.
  - **Emblema:** onde o carro real leva o logo da F1 e o texto da FIA, vai o emblema do campeonato
    do jogo ("SPEEDORU" com a bandeira quadriculada) e "WORLD CHAMPIONSHIP". O jogo só usa marcas
    próprias.
  - **Movimento:** as rodas giram com a velocidade e as da frente esterçam pela curva da linha ideal.
  - **Pinturas:** duas, como a F1, que alterna dois safety cars. Prata com grafismos pretos e pinças
    laranja (a do GT R) em Monza, Suzuka e Sky Aerobase; verde com filetes e pinças limão e letreiros
    brancos em Mônaco, Las Vegas e Atlantis.
  - **Materiais:** os do `.glb` são slots (`SC_Paint`, `SC_Stripe`, `SC_BarAmberL`...) que o jogo
    troca pelos materiais toon da pintura. A carroceria usa o shader da pintura metálica dos carros,
    e o carro fica na camada dos carros (mesma luz de contorno).
  - **"Adesivos":** vidros, faróis, lanternas, grafismos e letreiros são contornos 2D triangulados e
    projetados na carroceria por raycast, alguns milímetros acima. Os letreiros saem da fonte Chakra
    Petch do jogo.
  - **Servidor:** sem janela, o modelo não é montado.
  - **Regenerar:** `blender -b --factory-startup -P blender/build_safety_car.py` (`-- --all-views`
    para mais vistas). Gera o `.glb` e as vistas em `blender/renders/safety_car/`.
- **Fim:** a amarela (com o safety car) dura **no mínimo 30 s** e só termina quando todos os
  carros batidos estão nos boxes (indo pela faixa, parados no box ou levados até ele); aí vem a
  bandeira verde e o safety car sai. **Só na última volta** (do líder) ela dura **10 s** e termina
  mesmo com carro batido ainda indo para o box (se começou antes, contam 10 s a partir da última
  volta) (`tests/last_lap_yellow_test.gd`). Os consertos seguem independentes da bandeira.
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
- **Aura** (rastro de partículas; `scripts/car/car_particles.gd`, `CarConfig.trail`; garagem → Aura):
  o carro solta **raios** (arcos estalando na carroceria, raios caindo no chão, faíscas e clarões
  azuis), **pétalas de sakura**, **estrelinhas** coloridas, **bolhas de sabão** (iridescentes, que
  estouram), **flocos de neve**, **fogo no chão** (uma faixa de fogo contínua atrás de cada roda
  traseira — fita virada para a câmera, presa ao chão —, brilho no asfalto, chamas curtas e brasas,
  com luz laranja), **brasas** com fumaça escura, **chuva de moedas**
  de ouro girando, **fumaça colorida** (nas 3 cores da pintura) ou um **arco-íris** (faixa de sete
  cores saindo da traseira, `car_rainbow_trail.gdshader`, com estrelinhas). As formas são desenhadas no shader (`shaders/car/car_particle.gdshader`, sem textura;
  as faixas de fogo em `car_fire_trail.gdshader`). Parado, só aparece na vitrine da garagem (fraco,
  de amostra; meta `showcase` do carro do menu); na pista só sai com o carro andando, cheio a partir
  de ~140 km/h. Tamanho: `CarParticles.SIZE` (0,6). As partículas nascem no mundo e herdam parte da velocidade
  do carro, com um arrasto que cresce com a velocidade: formam o rastro logo atrás do carro, visível
  na câmera de perseguição (a velocidade vai ao `RenderingServer` no `frame_pre_draw`, porque o
  `GPUParticles3D` grava a dele a cada quadro). A turbulência (bolhas, pétalas, neve, brasas) só vale
  com o carro devagar. Somem perto da câmera. A velocidade sai do quanto o carro andou, então vale
  também nos carros dos outros jogadores online (o rastro vai no equipamento). O servidor nem cria
  (tira o `Effects` inteiro).
- **Faíscas de frenagem** (todo carro, não é item): numa frenagem forte o assoalho raspa e solta
  faíscas brilhantes — só se o carro estava a 250 km/h ou mais no começo da frenagem e segura o
  freio por mais de 1 s; param ao soltar o freio ou abaixo de 120 km/h
  (`CarParticles.brake_spark_state`). Valem para o jogador, os bots e os carros dos outros (o freio
  vem no snapshot).
- **Luz de ultrapassagem** (garagem → Luz de ultrapassagem, `CarConfig.pass_light`): o pisca dos
  retrovisores ao pedir passagem (X) é âmbar; com a **Sirene** (exclusivo da conquista Interceptor)
  os dois LEDs alternam vermelho e azul, oito trocas por segundo, com o halo e a luz junto
  (`F1Car.SirenBlinker`). Online vai no equipamento, como o rastro.
- **Luz traseira de F1:** a lanterna central e os LEDs das placas da asa traseira ganham material
  próprio e piscam (~4 Hz) quando o carro freia (recuperando energia), com clarão e, à noite, luz
  vermelha no chão atrás do carro. Os LEDs do volante não são afetados.
- **Marcas de pneu:** fitas escuras no asfalto/zebra ao frear forte, travar, patinar ou derrapar;
  somem em ~45 s. Só os carros a até 150 m da câmera deixam marcas (e fumaça/pó dos pneus).
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
  luzes de três pontos. À noite (e fraco no entardecer) os postes acendem com `SpotLight3D` reais de
  luz branca apontados para a pista (em todas as pistas os postes ficam a 60% do intervalo do
  layout, `TrackProps.LIGHT_DENSITY`, e a área iluminada é 1,3× maior, `LIGHT_REACH`), as garagens
  acendem e as janelas de vidro brilham. A noite tem luz ambiente e exposição um pouco mais altas.
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

Seis faixas em `assets/audio/music/` (MP3, ~1 min cada, importadas em loop — `loop=true` no
`.import`): Pista Neon (`pista_neon.mp3`), Turbo Disco, Retro Racer, Sakura Drift, Dragon Rush e
Samba Turbo.

O menu principal tem o próprio tema (Pista Neon, em loop); ao trocar de cena a música corta para
a da pista e vice-versa. Na pista, o autoload `Music` (`scripts/audio/music_player.gd`) toca no bus "Music": em **playlist** (padrão,
cada faixa toca duas vezes e passa para a próxima com crossfade de 3 s) ou uma faixa fixa em loop
(Configurações → Áudio). Ao importar uma música nova, marque o loop na importação.

## Configurações

F10 (em qualquer momento), ou o botão **Configurações** no menu inicial, na pausa e na garagem.
Autoload `Settings` (`scripts/settings/game_settings.gd`); menu em `scripts/settings/settings_menu.gd`.
Tudo é aplicado na hora e salvo em `user://settings.cfg`
(`%APPDATA%/Godot/app_userdata/Speedoru/` no Windows).

- **Controles:** todas as ações remapeáveis, uma tecla de teclado e um botão/eixo de controle por
  ação (clique, aperte a nova; Esc cancela, Backspace apaga). Conflitos aparecem em amarelo. As
  teclas que eram fixas no código (pausa, ajuda, páginas da classificação, pneu do pit, F10) viraram
  ações também.
- **Tela:** janela / tela cheia / tela cheia exclusiva, resolução da janela, VSync (desligada,
  ligada, adaptativa, mailbox), limite de FPS, escala da interface (automática pela janela, ou
  75–150%), campo de visão da câmera, estilo da interface (Speedoru ou Retrô) e paleta (Retrô).
- **Gráficos:** predefinições Baixo/Médio/Alto/Ultra (mudar qualquer item vira "Personalizado"),
  escala de renderização 3D com upscaler (bilinear, AMD FSR 1.0, FSR 2.2), MSAA, FXAA/SMAA, TAA,
  sombras (atlas de 2048 a 16384 e filtro suave; o sol usa no máximo 8192 — com 16384 a imagem era a
  mesma e a GPU gastava 1–4 ms a mais por quadro, `tests/shadow_atlas_probe.gd`), SSAO, SSIL, glow, neblina volumétrica e nível de
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
  silhueta. A **sombra** dos pinheiros de perto é desenhada com essa versão leve (só sombra, mesma
  silhueta): o modelo de agulhas (~46 mil triângulos) desenhado de novo nas cascatas de sombra
  custava ~7 ms de GPU por quadro — em Suzuka o pior trecho foi de 61 para ~99 fps, sem mudar o
  visual (`tests/perf_probe.gd`). `pines` no nó `Track` liga/desliga.
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
- **Piso sem vincos:** cada faixa do piso (asfalto, linhas, escape, boxes) é um quadrilátero por
  amostra (2 m); numa curva fechada com subida/descida ele torce e os dois triângulos formavam um
  vinco a cada 2 m que tirava o contato do pneu de fora (Curva do Portal da Sky Aerobase: ~2 cm,
  roda esquerda dos bots sem contato em 60 de 367 passos). Onde torce mais de 0,7 mm,
  `TrackRoad._strip` divide a faixa na largura (até 12 pedaços): 0 passos sem contato.

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
  parede (`bdist`, distância de cada vértice ao prédio); o **Casino** com as torres e cúpulas de cobre; encostas da
  cidade sem rampa lisa à vista: as íngremes viram **muro de arrimo** de pedra calcária em fiadas
  com hera (`FLOOR_WALL` no shader) e as outras **jardins em terraços** (muretas de pedra nas curvas
  de nível); na entrada do túnel, um **hotel sobre o túnel** (como o Fairmont) acompanhando a pista,
  a fachada do portal subindo até o terreno de trás, **muros de ala** de pedra dos dois lados da
  rampa e o terreno em frente aos portais rebaixado (sem cunhas de morro junto à boca do túnel);
  morros dos Alpes Marítimos com
  cristas e penhascos (ruído "ridged"), **mato mediterrâneo**, rocha nas encostas íngremes e
  milhares de **árvores** (pinheiros, pinheiros-mansos, carvalhos, ciprestes) e o casario de
  Beausoleil além da área dos dados (`build_backdrop`).
- **Árvores:** as mesmas espécies de Monza (`TrackTrees`), mas de perto com **copas de folhas
  soltas** (`TrackLeaves.city_tree_mesh`, shader `tree_leafy` com vento e as cores do ambiente):
  tufos com miolo escuro e folhas em losango deitadas na superfície; **cipreste** em coluna
  contínua verde-escura afinando em chama, **pinheiro-manso** com tronco inclinado, três galhos e
  copa em guarda-chuva, carvalho e bétula de copa redonda, arbustos; de longe (além de 190 m), as
  bolhas simples sem sombra. **Palmeiras** com 12 folhas de nervura em arco caindo para fora e
  folíolos dos dois lados (versão simples além de 220 m). Nos morros só nos anéis mais perto da cidade; perto da pista (`city_props.gd`),
  ~200 árvores nos jardins e como árvores de rua a 7–55 m da borda. Nada (árvore ou objeto) fica
  sobre a pista, o pit lane, os escapes ou o piso dos boxes: `CityProps.clear_of_track` testa a
  distância à borda + escape e um raio para baixo confere que o chão é o da cidade
  (`monaco_test` confere todos os pontos).
- **Junto à pista** (`city_props.gd`, só em lugares livres — chão de calçada/praça, fora dos
  prédios, das ruas, das arquibancadas e do mar, além das barreiras): ~500 objetos de mobiliário
  urbano (bancos, floreiras com flores, frades, lixeiras e, na orla do porto, mesas de café com
  guarda-sóis de três cores). A faixa que a grade marca "sob a pista" além da borda vira calçada;
  ruas da cidade com **meio-fio de pedra**; calçadas e praças com **tampas de bueiro e grelhas**
  (shader, perto); gramados de cidade menos saturados.
- **Desempenho:** árvores, palmeiras e objetos da cidade em **blocos de 128 m**
  (`CityProps.add_chunked`), um MultiMesh por bloco e LOD — o Godot mede o alcance de visibilidade
  até o centro do MultiMesh e recorta (câmera e cascatas de sombra) pela caixa inteira, então um
  MultiMesh da cidade toda nunca trocava de LOD e ia inteiro para cada cascata (eram ~12 milhões de
  primitivas por quadro; agora ~2,7 milhões); objetos pequenos sem sombra (só guarda-sóis e
  floreiras). Na corrida (vale para as duas pistas): loops de som em silêncio **parados** (não
  pausados — um AudioStreamPlayer3D pausado continua recalculando posição e doppler a cada passo de
  física), rivais a mais de 260 m da câmera mudos (e só os 2 rivais mais perto com som: ver abaixo); marcas de pneu/rastros montados de uma vez num
  ArrayMesh (sem pontos, nada); efeitos do boost só mexidos quando ligados; tráfego dos bots a
  60 Hz, intercalado; fantasmas dos boxes só para pares com alguém nos boxes; display do volante a
  30 Hz e só nas câmeras de bordo; retrovisores fora das câmeras de bordo de vez em quando (um de
  cada vez) e, abaixo de 90 FPS, revezando; guia de traçado com a altura do asfalto em cache. No
  máximo **6 passos de física por quadro** (`max_physics_steps_per_frame`): com o processador no
  limite o jogo desacelera um pouco em vez de afundar em quadros cada vez mais longos (com 20
  carros caía a ~3 FPS). Corrida de 10 carros em Mônaco: de ~37 para ~66 FPS (RTX 5070).
  Interface da corrida: a classificação só é redesenhada quando o que ela mostra muda (posições,
  intervalos, pneus, box, página) e o minimapa desenha o traçado uma vez (só os pontos dos carros por
  quadro); avisos, bandeira e votação vazios não redesenham — a interface caiu de 2,5–3,4 ms para
  ~0,5 ms por quadro (`tests/perf_probe.gd -- … hud`). Por carro e por quadro: as partículas só
  mexem no emissor quando o valor muda e só passam a velocidade herdada aos emissores ligados; a pose
  final das mãos do piloto só é guardada nos testes (`DriverRig.capture_poses`); o composto dos pneus
  fica em cache no código nativo (era uma chamada ao GDScript por carro a cada passo). Online, o
  estado dos carros dos outros que só muda com o instantâneo (marcha, bandeiras, dano, pneus) é
  escrito só quando chega um novo, não a cada passo.
  **Processador na corrida** (`tests/cpu_probe.gd`: 14 carros correndo, imagem a 50% para a placa
  não ser o limite; ~90% do tempo era código nativo e do motor, não GDScript):
  - Passo de física do carro (`car.rs`): estado do corpo lido uma vez por passo; constantes das
    rodas, massa e marchas em cache (o dano avisa com `_core_wheels_changed`); pneus e aerodinâmica
    somados numa força e num torque em torno do centro de massa (2 chamadas em vez de 7, a mesma
    conta do `apply_force`); arrays dos pneus lidos e escritos uma vez por passo (cópias no Rust para
    efeitos e som); piso de cada roda só relido quando o corpo tocado muda; contato com outro carro
    vira sinal só uma vez por carro e por passo, e só acima do que as penalidades consideram.
  - Bots: bandeira, RaceControl e "envolvido na batida" lidos uma vez por passo para todos (sob
    amarela eram chamadas ao GDScript por bot × carro); `RaceManagerCore` lê o tempo e o estado da
    prova uma vez por passo, guarda a pista e confere os fantasmas dos boxes a 30 Hz.
  - Marcas de pneu e rastros: não refazem a fita só porque pontos já apagados saíram (refaziam a cada
    quadro por 45 s depois de cada derrapada) e montam os arrays no Rust (antes, um array por segmento).
  - Efeitos, som e dano: câmera do quadro lida uma vez para todos; cores do CarConfig relidas a 4 Hz;
    luzes, materiais e players só alterados quando o valor muda; dano sai cedo sem contatos; nuvens e
    guia de traçado mandam o MultiMesh inteiro numa chamada; vácuo escrito só quando a origem muda;
    relevo sob dirigíveis e pássaros relido a cada 8 quadros.
  - **Som só dos 2 rivais mais perto da câmera** (`audio.rs`, `AUDIBLE_RIVALS`; quem já toca leva 5 m
    de vantagem na escolha, entrada e saída em 0,25 s); os outros ficam mudos, batidas inclusive.
  - Marcas de pneu, fumaça, pó e rastro do boost só até 150 m da câmera (e não muito atrás dela);
    fumaça e pó dos pneus são `GPUParticles3D` (convertidas das CPUParticles3D pelo conversor do Godot).
  - **Modelo de longe** (`CarFarModel`): a partir de 85 m as ~40 peças do carro viram uma malha só (uma
    superfície por material, com LODs gerados), pela faixa de visibilidade do Godot (vale para sombras
    e retrovisores); montada numa thread e refeita quando as peças mudam ou o carro sofre dano. Com o
    grid a ~110 m da câmera: 3.718 → 2.461 objetos e 2.906 → 1.649 desenhos por quadro, imagem igual
    (`tests/capture_far_model.gd`).
  - godot-rust com `safeguards-release-disengaged` (`native/Cargo.toml`): sem conferir, a cada chamada
    ao motor, se o objeto ainda existe.
  Medido em Monza / Mônaco / Las Vegas: de ~70 / 76 / 74 FPS para ~94 / 97 / 89 FPS (+20–34%); passo
  de física de ~2,1 para ~1,6 ms. Nas configurações Ultra (perf_probe, junto com o atlas da sombra e a
  interface): Monza 104 → 127, Suzuka 94 → 117, Mônaco 194 → 262, Las Vegas 140 → 212, Sky Aerobase
  252 → 301 FPS. Alternativas testadas e descartadas: física Jolt (−15% de física, ganho de FPS dentro
  do ruído, muda a dirigibilidade), física e desenho em thread própria (travam: o código lê a física
  no meio do passo e atualiza buffers da GPU na thread principal).
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
- **Noite:** postes de rua (`LIGHTS` com `variant = 1`: coluna fina atrás da barreira, braço
  curvo sobre a pista e luz branca) nos pontos-chave da volta, e parte das janelas dos prédios
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

## Suzuka (o "8" com viaduto)

`scenes/tracks/suzuka.tscn` + `resources/tracks/suzuka_layout.tres`, gerados com
`tools/build_suzuka.py` a partir do [TUMFTM racetrack-database](https://github.com/TUMFTM/racetrack-database)
(linha central, larguras e linha de corrida; LGPL-3.0, derivado do OpenStreetMap/ODbL).

- **Traçado:** 5,80 km, curvas 1 e 2, os S, Dunlop, Degner 1 e 2, a passagem sob a ponte, o
  grampo, 200R, Spoon, a reta oposta sobre a ponte, 130R, chicane Casio e a última curva. A
  **elevação** (5ª coluna do CSV) é aproximada da real: a reta principal desce para a curva 2 (ponto
  mais baixo), os S e a Dunlop sobem até a Degner 1 (~34 m acima), e a reta oposta passa **10,7 m
  acima** do trecho entre a Degner 2 e o grampo (o script confere a folga).
- **Cruzamento:** `TrackPath` acha os pontos em que a pista passa por cima dela mesma
  (`crossings`: s de baixo, s de cima e ângulo) e, perto deles, `project()` também olha a altura
  — o carro embaixo da ponte fica no trecho de baixo (posição na corrida, limites de pista,
  bandeiras, bots, câmera do espectador). A linha de corrida tem a altura na 3ª coluna pelo mesmo
  motivo.
- **Relevo em volta:** circuito de campo com subidas. `TrackTerrain` soma os morros a um **relevo
  de base**: junto da pista ele é a altura dela (plana na lateral, 6 cm abaixo do asfalto) e, mais
  longe, a superfície suave de `suzuka_relief.json` (Laplace preso à altura da pista, gerado pelo
  script; `TrackLayout.relief`). O ponto da pista mais próximo de cada nó da grade sai de uma
  varredura ao longo das normais (bem mais rápido que projetar nó a nó). A textura de altura leva o
  relevo de base no canal G, e o shader do terreno acha a parte plana (faixas de corte) pela
  diferença. Sem relevo (Monza) tudo continua em 0.
- **Ponte e corte** (`track_bridge.gd`): em volta do cruzamento o chão fica no nível de cima, menos
  no corredor da pista de baixo, que passa num **corte com muros de arrimo** de concreto logo atrás
  da barreira (o topo, gramado com o shader do terreno, cobre a rampa da grade entre os níveis). A
  reta de cima atravessa numa **laje** com acostamento asfaltado, parapeito de concreto e faixas de
  anúncio nas laterais; os muros param embaixo dela. Nada de árvores no corte nem na ponte
  (`track.footprints`).
- **Roda-gigante** (`TrackFeature` `FERRIS_WHEEL`, `ferris_wheel.gd`): a do parque de diversões,
  atrás da arquibancada principal perto da curva 1 — 56 m, pernas em A, dois aros com raios e
  lâmpadas (mais fortes à noite), 24 gôndolas coloridas que ficam sempre em pé enquanto a roda gira
  (uma volta a cada ~2 min). A área dela fica plana e sem árvores.
- **Bandeiras:** os mastros das arquibancadas usam a bandeira do país do circuito
  (`TrackLayout.flag_colors`/`flag_style`; Japão = disco vermelho que tremula junto com o pano).
- **Bots:** `bot_pace = 0.92` (as lombadas e descidas tiram aderência) e margem de 1,5 m da borda.
  Volta do bot no difícil: ~1:46. Volta mínima plausível no servidor: 85 s.
- Recorde por pista em `best_lap_suzuka` nos contadores (como Mônaco).

## Las Vegas (Las Vegas Strip Circuit)

`scenes/tracks/las_vegas.tscn` + `resources/tracks/las_vegas_layout.tres`, gerados com
`python tools/build_las_vegas.py [--debug pasta]` a partir dos dados do OpenStreetMap (ODbL) salvos
em `tools/data/las_vegas/` (relação 16696508 do circuito, prédios e partes de prédio, ruas, água,
parques, árvores e a roda-gigante). Saída em `assets/track/las_vegas/` no mesmo formato da cidade de
Mônaco (`TrackCity`). Os CSVs precisam do importador "keep" (`.csv.import`), como os das outras
pistas: com o padrão (tradução) o Godot não os leva para o jogo exportado.

- **Traçado:** 6,16 km (o oficial tem 6,201 km), no sentido da corrida, começando na largada. O OSM
  tem esquinas de 90° em canto vivo: só elas são arredondadas até 17 m de raio no eixo
  (`round_corners`), o resto não muda. A Strip (Las Vegas Blvd.) tem ~1,9 km de reta; meia-largura
  6,6 m (7,4 m nas curvas fechadas). Plano: o deserto não tem desnível.
- **Boxes:** à esquerda; a faixa real sai depois da curva 1, mas a do jogo acompanha a reta e
  termina antes dela (s = −230 a +150). O Grand Prix Plaza (o prédio real dos boxes) dá lugar ao
  complexo do jogo.
- **Cidade:** ~670 prédios do OSM (as torres dos cassinos com a altura do OSM: Palazzo 196 m, Wynn e
  Encore ~190 m, Cosmopolitan 184 m…; plantas com partes viram as partes), fachadas modernas
  (`"style": "modern"`: torres de vidro e pódios lisos, sem venezianas nem telhas), ruas, ~130
  piscinas, o campo de golfe do Wynn e ~3.200 palmeiras (as mapeadas, as dos parques e uma fileira na
  calçada de toda a pista). Sem mar, cais, túnel nem navios (`TrackCity.has_sea/has_tunnel`): essas
  etapas nem rodam. O horizonte vira deserto: vale plano com a cidade baixa e serras recortadas
  (rocha avermelhada, como Red Rock) a partir de ~2 km.
- **Preenchimento** (`City.infill` no gerador): os terrenos vazios do OSM (estacionamentos abertos e
  lotes de areia, que deixavam a cidade "chapada") ganham ~780 prédios inventados no estilo da Strip,
  alinhados à rua mais próxima e com calçada, folga da pista (10 m além da área dela), das ruas, das
  piscinas, dos parques e dos marcos: resorts (pódio de cassino com torre em lâmina, em Y ou duas
  torres, de 75 a 170 m; mais altas perto da pista), hotéis médios, cassinos baixos, garagens,
  escritórios e, nos lotes estreitos, lojas e motéis. Lotes achados por erosão da máscara de lugares
  livres (2 m) e crescidos lado a lado; marcados com `"f": 1` no JSON. Fachadas próprias (vidro
  dourado, bronze, branco de hotel, vidro azul, salmão) depois das 14 do OSM.
- **Luzes da cidade** (`scripts/track/city_neon.gd`, etapa "neon", só nas cidades "modern"): cada
  prédio traz o tipo de letreiro (`"v"`), o ponto da pista mais perto (`"tp"`) e a distância (`"td"`);
  o letreiro vai na parede virada para a pista.
  - **Torres de hotel** (e parte das torres altas do OSM): nome no alto da fachada, coroa de neon na
    laje (às vezes descendo pelas quinas) e, em ~1/3, um desenho grande em pé no telhado.
  - **Cassinos:** marquise (painel escuro, moldura de neon, lâmpadas correndo e a palavra) e, embaixo,
    um telão de LED que troca de anúncio, um desenho de neon ou faixas verticais; a até 120 m da
    pista, um ponto na calçada (para o lado, sem tapar a marquise) para luminoso.
  - **Lojas e motéis:** lâmina vertical na quina, com letras empilhadas (MOTEL, BAR, PAWN…) ou só um
    desenho.
  - **Placas famosas** (nos luminosos, espalhadas pela volta; recriação ou homenagem sem o nome de
    verdade): "Welcome to Fabulous Las Vegas" — frente e verso ("Drive Carefully / Come Back Soon"),
    losango branco com os "dólares de prata" do WELCOME e a estrela de oito pontas; o desenho de Betty
    Willis nunca teve copyright —, o caubói acenando (Vegas Vic, 2 quadros), a vaqueira chutando
    (Vegas Vickie), a guitarra gigante (Hard Rock), o sapatinho girando no alto do poste (Silver
    Slipper), o pilar atômico (Stardust), o flamingo com plumas (Flamingo), a ferradura (Binion's) e a
    lâmpada do gênio (Aladdin). Os outros luminosos: painel com nome, telão de LED e estrela.
  - **Cobertura de LED** à moda da Fremont Street sobre a rua larga e reta mais perto da pista (sem
    cruzar com ela): abóbada em colunas com shows procedurais (`shaders/track/vegas_led.gdshader`:
    ondas de cor, céu com cometas, bandeira quadriculada, arco-íris).
  - **Dirigíveis:** três, a 150–200 m, dando a volta no circuito (`scripts/track/vegas_motion.gd`),
    com telão de LED curvo dos dois lados e luzes de navegação.
  - **Arte** (`scripts/track/neon_art.gd`): atlas `assets/track/las_vegas/neon_atlas.png` (4096×3328,
    94 células) com os nomes de hotel, cada um num estilo — cursiva com sublinhado e estrela,
    marquise de letras coloridas, faroeste, "Googie" com explosão atômica, tubos múltiplos, dólares
    de prata, duas linhas em duas fontes, texto em seta —, as palavras de cassino, as lâminas, 24
    desenhos de neon (naipes, dados, cerejas, 777, martíni, coroa, diamante, ferradura, fichas,
    roleta, palmeira, foguete, gato da sorte, carpa, dragão, planeta…), as placas famosas e 6 rolos de
    LED de 4 quadros. Fontes livres (OFL, licenças junto) em `assets/fonts/neon/`: Monoton, Pacifico,
    Lobster, Bungee, Rye e Righteous. Nomes inventados. O atlas é gerado fora do jogo —
    `godot --path . -s res://tools/build_neon_atlas.gd` (com janela) — e importado comprimido (S3TC),
    com mipmaps e sem `fix_alpha_border` (o alfa é pré-multiplicado): desenhar no jogo custaria ~1 s e
    deixaria centenas de MB de memória de vídeo presos. Mudou um desenho ou o tamanho de uma célula,
    gere de novo.
  - **Brilho:** neon e lâmpadas em `shaders/track/vegas_neon.gdshader` (alfa da cor de vértice = fase
    das lâmpadas em sequência); a arte em `vegas_sign.gdshader` (halo do próprio desenho, quadros
    animados por `instance uniform`; a placa Welcome, painel pintado, clareia menos). De dia acesos e
    contidos, à noite fortes, com glow (`CityNeon.set_night`).
  - **Postes** com braço sobre a rua dos dois lados das ruas largas (≥ 9 m), alternados a cada 17 m.
- **Marcos** (`scripts/track/city_landmarks.gd`, chave `landmarks` do JSON):
  - **Sphere**: tela de LED esférica (`shaders/track/vegas_sphere.gdshader`) com três shows que se
    alternam — o olho gigante (olhando para o circuito), um planeta e ondas de néon —; a grade de
    LEDs só aparece de perto; à noite brilha forte;
  - **Torre Eiffel** do Paris Las Vegas (165 m): treliça de bronze com lâmpadas douradas;
  - **High Roller** (158 m de diâmetro): a roda-gigante de Suzuka em escala real, no plano mapeado;
  - **Fontes do Bellagio**: jatos no lago (`vegas_fountain.gdshader`), coreografia de ~36 s (ondas
    correndo pela fileira, todos juntos e o estouro final) com pausa entre os shows.
- **Elementos:** arquibancadas na reta (em frente aos boxes, coberta), na curva 1, na Koval, na
  chicane da Sphere e na curva da Harmon; áreas de escape nas frenagens fortes; anúncios e postes em
  toda a volta; pórticos e placas de frenagem; bandeira dos EUA nos mastros.
- Recorde por pista em `best_lap_las_vegas` (volta mínima plausível de 80 s).
- Teste: `tests/las_vegas_test.gd` (comprimento, pista plana, pisos, grid e boxes no asfalto, cidade
  sem mar/túnel, os quatro marcos, prédios de preenchimento, letreiros e postes, nada sobre a pista);
  capturas em `tests/las_vegas_shots.gd` (horário 2 = noite; inclui as placas famosas, um
  dirigível e a cobertura de LED).
- Dados: © colaboradores do OpenStreetMap, licença ODbL (https://www.openstreetmap.org/copyright).

## Sky Aerobase (pista fantasia no céu)

Primeira pista da categoria **Fantasia** (`"category": "fantasy"` em `RaceSettings.TRACKS`):
`scenes/tracks/sky_aerobase.tscn` + `resources/tracks/sky_aerobase_layout.tres` (`sky = true`).

- **Traçado** (`python tools/build_sky_aerobase.py [--debug pasta]`): sem dados reais, montado por
  trechos (retas e arcos, cada um com a altura no fim); o fechamento é resolvido sozinho (ângulo da
  última curva e comprimento de duas retas), e o script confere rampa, curvatura vertical e que
  trechos não vizinhos fiquem a mais de 40 m. Saída em `assets/track/sky_aerobase/` (linha central
  com elevação e linha de corrida de curvatura mínima). 3,81 km: Reta dos Hangares (boxes e grid, a
  40 m), Curva da Torre, Esses do Vento, Grampo do Hangar (48 m), **Descida dos Jatos** até 9 m
  (como a de Mônaco, rampa máx. ~9%), **Curva do Portal** (70° fechada à direita no pé da descida),
  **Túnel do Reator** (quase reto), **Chicane do Abismo** (esquerda, 77 m de reta em diagonal,
  direita: ~96 m entre os ápices), Reta Oposta subindo, Curva do Céu e a Última Curva. O fechamento
  usa a Reta Oposta e a Reta da Plataforma, então tudo até a descida mantém o s. Os bots fazem
  ~69–82 s (volta mínima plausível online: 50 s).
- **Sem barreira** (`TrackFeature` BARRIER `variant = 2` → `Barrier.NONE`): por fora da Curva da
  Torre (sem barreira nem arquibancada), por fora dos esses, por fora do Grampo do Hangar (a curva
  mais fechada; a arquibancada dele foi para a reta que chega nele), por fora da Curva do Portal
  (sem barreira nem arquibancada), nos dois lados da chicane e por
  fora da Curva do Céu. Ali a pista não acaba no kerb: vem uma **área de escape** de placas metálicas (6 m na
  chicane, 8–9 m nas outras, piso RUNOFF) com uma faixa de aviso amarela e preta antes do vazio
  (`RaceTrack.open_edge` / `deck_edge`). Os bots contam com menos aderência nas curvas com borda
  aberta por fora (`RacingLine.CAUTION`). Embaixo dos pisos há uma laje de colisão de 1 m
  (`TrackRoad._deck_floor`, até a borda da plataforma): sem ela, um carro empurrado por outro
  atravessaria o asfalto (os pisos não têm espessura e não há chão).
- **Queda** (`scripts/race/fall_watch.gd`, só servidor/offline): quem passa da borda da plataforma
  (ou fica abaixo da pista) sem roda no chão cai; depois de **2 s** de queda volta pelo box da equipe
  (ou a vaga livre mais perto, se o companheiro estiver nele) e faz um **pit stop completo** (pneus,
  conserto se precisar, conta como parada; a volta em andamento recomeça, como no "voltar aos
  boxes"; na classificação a volta é anulada). Vale para bots e para o treino livre. Apertar R no ar
  não segura o carro. A câmera de corrida detecta a queda sozinha (também online): fica parada na
  borda olhando o carro cair e o HUD mostra "VOCÊ CAIU!". Na rede, o salto do teletransporte não é
  interpolado nos carros dos outros. Os boxes ficam todos antes da linha de chegada.
- **Visual** (ramo `layout.sky` do `RaceTrack.rebuild`: sem terreno nem cidade):
  - **Placas de metal com parafusos** (`metal_plate*.gdshader`): com `TrackMaterials.metal` ligado
    (o RaceTrack liga na pista no céu), todas as construções (barreiras, boxes, arquibancadas, objetos,
    plataforma, nave e base) trocam o concreto por placas de 3 × 2 m em metal escuro, com juntas,
    parafusos nos cantos e no meio dos lados maiores e relevo feito da forma das placas (chanfro nas
    bordas e cabeça abaulada dos parafusos), com iluminação realista (sem o degrau do toon) e pouco
    reflexiva; a faixa entre a pista e a barreira também é de placas. Asfalto bem mais escuro, também
    sem o toon (`track_surface_smooth.gdshader`).
  - **Barreiras**: metal com o topo arredondado, friso de LED e a faixa de anúncios em **holograma
    correndo** (`holo_ads.gdshader`, `TrackAds.holo_material`): fundo transparente, letras
    flutuando e faixas em cima e embaixo na cor da marca. Todos os anúncios da pista (pórticos, boxes,
    arquibancadas) usam o mesmo estilo, parados.
  - **LEDs** (`SkyLights`): os frisos da plataforma e das barreiras e os aros mudam de cor **a cada
    volta** de quem lidera (no treino, do jogador), entre azul, verde e roxo; à noite, luzes a cada
    18 m ao longo das barreiras, na mesma cor, iluminam onde a luz dos postes não chega.
  - `SkyDeck`: laje sob a pista e **propulsores nas beiradas**, alternando os lados a cada 46 m: a
    ponta arredondada e um pouco cônica, em metal escuro e de normais suaves (`MeshBuilder.lathe`),
    com 1,6× o raio dos outros motores, aparece acima da
    plataforma, com uma faixa acesa de
    cor fixa em cada um (vermelho, amarelo, azul e verde, de um propulsor para o outro), e o jato azul
    (`jet_plume.gdshader`) sai por baixo; MultiMesh com LOD.
  - `SkyShip`: o túnel é uma **nave** de placas de metal: casco arredondado, parede cheia (com janelas
    acesas) do lado de dentro do circuito e o lado de fora **vazado, com pilares**; espinha com luz,
    núcleos do reator em cima, proa na saída e dois propulsores com o bocal aceso na entrada; à noite,
    refletores brancos no forro a cada 10 m.
  - Postes próprios: coluna de metal, anel de luz e um pescoço curvo até uma barra de LED sobre a pista.
  - `SkyWorld`: o **mar** 1,4 km abaixo (`water.gdshader` em modo mar aberto), um **tapete de nuvens**
    com buracos (`cloud_deck.gdshader`), nuvens 3D abaixo, no nível da pista (paradas, longe do
    traçado) e altas, gaivotas, mecânicos nos boxes e menos névoa; de dia o céu é azul até o
    horizonte e abaixo dele.
  - `SkyBase`: torres de controle em plataformas flutuantes com motores, um **porta-aviões voador**
    com caças estacionados e "SKY AEROBASE" no casco, **aros gigantes girando** sobre as retas (centro
    no nível da pista, raio de 1,7× a meia-largura da plataforma; LEDs por dentro, uma faixa em cada
    face com placas e pinos em volta, pontos por fora), o letreiro "SKY AEROBASE / HIGHER · FASTER ·
    FURTHER" sobre os boxes, esquadrilhas de caças com rastro passando no alto e 12 **dirigíveis-nave** dando voltas
    sobre trechos diferentes da pista, de 55 a ~260 m acima dela, mais um rente à pista (órbita de
    60 m logo além da borda de uma reta, ~26 m acima) e um abaixo dela (20 m abaixo, do lado de uma
    borda aberta, onde nenhuma barreira o esconde; `SkyBase._orbit_beside`): mais largos que altos (casco
    achatado, convés, ponte de comando, flutuadores laterais com asas, cauda dupla), janelas acesas,
    anúncio em holograma, seis propulsores (quatro para baixo, de jato curto, dois para trás), farol vermelho
    piscando embaixo (`SkyBlink`) e, à noite, luzes nos propulsores e nas janelas iluminando o casco;
  - `SkyBeams`: **holofotes** saindo de baixo da plataforma (`searchlight.gdshader`, cone de normais
    suaves que some pelas bordas e onde atravessa alguma coisa), só ao entardecer e à noite (de dia
    ficam desligados): dez varrendo o céu, mais transparentes, e os principais, dois em cada balão
    de personagem, saindo de logo abaixo dele e subindo até passar do balão, que à noite também
    recebe a luz deles.
  Nada disso tem colisão; o servidor só gera pista, laje, barreiras e boxes.
- **Arquibancadas**: na reta dos boxes, na reta do grampo, na reta oposta e na última curva (coberta).
- Teste: `tests/sky_aerobase_test.gd` (traçado, pisos, bordas abertas com escape e nada embaixo, nada
  sobre a pista, cenário, carro parado, e quedas do jogador e de um bot na corrida e no treino);
  capturas em `tests/sky_aerobase_shots.gd`.

## Atlantis Abyss (pista fantasia no fundo do mar)

Segunda pista da categoria **Fantasia**: Atlântida submersa. `scenes/tracks/atlantis_abyss.tscn` +
`resources/tracks/atlantis_abyss_layout.tres` (grupo "Mar" do `TrackLayout`: `undersea = true`,
`water_level = 28`, `seabed_depth`, `trenches`, `canyons`; o túnel em `tunnel`).

- **Traçado** (`python tools/build_atlantis_abyss.py [--debug pasta]`, o mesmo método por trechos da
  Sky Aerobase: `solve`, `trace`, `elevation` e `check` de `tools/build_sky_aerobase.py`, que recebem
  o sentido e a meia-largura). 4,76 km, anti-horário: **Reta do Anfiteatro** (boxes, grid e
  arquibancadas, ~970 m somando o fim da volta), Curva do Templo, Avenida das Colunas, Curva do Polvo,
  **Túnel de Cristal** (366 m, quase reto), **Grampo da Âncora**, **Subida do Aqueduto** (até 34 m,
  6,9% no máximo) que **sai da água**, o trecho emerso (**Portão de Poseidon** e Ponte das
  Cachoeiras, ~640 m acima da linha d'água), o **Mergulho** (−7,6%) de volta para baixo, Curva da
  Tartaruga, Chicane dos Corais, Reta e Esses do Abismo (sobre a fossa), a **Chicane do Tridente**
  (direita-esquerda de raio 22 m com 15 m de miolo, no fim dos ~510 m de pé embaixo do abismo: os bots
  freiam de ~280 para ~110 km/h; escape de 4,5 m dos dois lados e placas de frenagem), a Ponte do
  Abismo, Curva da Baleia, Reta dos Tritões e a Última Curva. Sem cruzamentos (trechos não vizinhos a
  94 m ou mais). O desenho de `--debug` marca em amarelo o que fica fora d'água. Os bots fazem ~78 s
  (volta mínima plausível online: 55 s).
- **Barreiras em toda a volta** (ninguém cai; não há `FallWatch`): mureta de pedra arredondada com
  um **painel de vidro** em cima (`sea_glass.gdshader`: transparente, fresnel ciano, faixas de
  reflexo, montantes a cada 8 m) e **friso de LED ciano** no alto; a colisão é a mesma das outras
  pistas. Escape maior por fora das curvas lentas; laje de colisão sob os pisos (`DeckFloor`, como
  na Sky: não há chão de colisão). 14 boxes (todo o grid online).
- **Pista**: asfalto azul-ardósia, zebras ciano e brancas, faixa de lajes de pedra até a barreira e
  um friso de LED ciano dentro de cada linha branca, com o pulso correndo (`TrackRoad`). Postes são
  colunas de pedra com braço de bronze e lanterna de luz fria.
- **Pedra de Atlântida** (`TrackMaterials.marble`, ligado pelo RaceTrack nesta pista): tudo o que
  passa por `TrackMaterials.building()` (barreiras, boxes, arquibancadas, objetos, ruínas) usa
  `sea_stone.gdshader` — o `building_common` com o cinza puxado para mármore, **sem o contorno anime**
  (`no_outline` forçado), juntas de cantaria (blocos em fiadas desencontradas, cada um num tom),
  musgo em duas escalas (manchas grandes e tufos finos) nas faces de cima, fios finos de alga
  escorrendo nas paredes, colônias de coral pequenas (rosa, laranja e roxo) com borda e pólipos —
  algas e coral só debaixo d'água; no trecho emerso a pedra fica com o musgo —, as faces de baixo
  mais escuras, **sem reflexo do céu** (`SPECULAR = 0`: sem contorno a rugosidade é 0 e a pedra, o
  leito, a rocha do cânion, os corais, o bronze e os estandartes viravam um espelho da água) e a
  **cáustica** da água (`caustics.gdshaderinc`: dois Voronoi animados, só abaixo
  da linha d'água, voltada para cima, some de longe). `TrackMaterials.set_sea` troca os parâmetros
  da água em todos os materiais de uma vez.
- **Geração** (ramo `layout.undersea` do `RaceTrack.rebuild`; o servidor pula tudo menos pista,
  barreiras, boxes e objetos):
  - `SeaFloor` ("leito"): grade de alturas em blocos de 250 m — logo abaixo da laje na reta do
    anfiteatro, `seabed_depth` abaixo da pista no resto, cânion de 80 m nas `trenches` (o abismo),
    dunas e **cadeias de montanhas** (ruído em cristas, mais um anel de serras em volta da área da
    pista, e montanhas avulsas pontudas à vista da pista, picos até 3 m abaixo da superfície) e, nos
    trechos em cânion, o chão entre o tubo e a parede e a **serra atrás de cada parede** (crista e a
    descida até longe, da grade de `SeaCanyon`), que passa do mar em volta do trecho emerso;
    `seabed.gdshader` (areia bege-acinzentada — a clara, na luz azulada da água, virava verde-menta —
    com manchas, ondinhas de crista clara e vale escuro, cascalho, conchas e pedrinhas de perto, rocha
    nas encostas íngremes — o limiar no fragment, com ruído —, algas, cáustica fina, sem contorno
    anime; acima do mar, rocha seca e vegetação). Os shaders do mar que desenham pela posição no mundo
    (leito, pedra, cáustica, bronze, rocha do cânion) usam **hashes sem seno**: longe da origem o
    `fract(sin(...))` perdia a precisão na placa de vídeo e a areia saía em polígonos de faixas retas.
  - `SeaCauseway` ("aqueduto"): laje de pedra sob a pista (até `RaceTrack.deck_edge`, alargada até a
    base do tubo) com cornija e friso de LED; onde o leito está perto, parede cheia; no resto,
    **arcos de aqueduto** a cada 24 m, em andares de até 24 m (dois ou três na subida e no abismo),
    com pilastras salientes nos pilares, aduelas de pedra e tijolo alternados em volta dos arcos,
    pedra de fecho (no andar de cima, com um medalhão dourado do tridente), cornijas entre os andares,
    lanternas e estandartes do tridente nos pilares;
    algas penduradas na cornija e nos arcos, corais no pé dos pilares e musgo.
  - `SeaTube` ("tubo"): o **tubo de vidro grande em volta de toda a pista submersa** (os carros
    correm no seco): seção em superelipse da largura da laje, 13 a 22 m de altura, **nervuras de
    bronze com pátina** a cada 12 m (`sea_bronze.gdshader`: a cor de vértice é o metal, manchas de
    pátina verde-azulada, frisos gravados, brilho de borda e cáustica; perfil em I com aba por fora e
    por dentro, pilastras na base com capitel dourado e, a cada três nervuras, um **medalhão dourado
    com o tridente** pendurado no alto, virado para quem chega), espinha no topo com friso de LED,
    portais de pedra onde a pista sai da água e um anel ligando ao Túnel de Cristal. `SeaTube.clearance`/`covers`/`inside`/`blocked` são usados por
    ruínas, bichos, recifes e vulcões para ficar do lado de fora. **Por dentro é seco**: onde o tubo
    atravessa a linha d'água (subida para o Portão e mergulho) a superfície do mar é recortada
    (`SeaTube.surface_carve`, máscara vista de cima em `sea_carve.gdshaderinc`, usada pelo
    `sea_surface.gdshader` — o `water.gdshader` com `CARVE` — e pelo teto), e a neve marinha e as
    bolhas somem dentro do trecho do tubo perto da câmera (`SeaTube.corridor`, passado a cada quadro
    pela `SeaAtmosphere`), chegando bem perto do vidro por fora.
  - Estandartes do tridente pendurados numa nervura a cada três do tubo de vidro (lados
    alternados, por cima da faixa entre a barreira e o vidro).
  - `GlassTunnel` ("túnel"): o **Túnel de Cristal**, o tubo menor dentro do grande, sobre a pista,
    com nervuras de bronze a cada 8 m (o mesmo material do tubo grande; luzes amarelas e friso ciano),
    viga no topo, estandartes e portais de pedra; luz ciano dentro e refletores à noite.
  - `SeaCanyon` ("cânion"): na maior parte da pista submersa (`layout.canyons`: trechos e a folga
    de cada lado entre o tubo e o pé da parede — 5 a 8 m, mais só no polvo e no portal —, ~60% da
    volta debaixo d'água) o tubo corre num **cânion de montanhas submarinas** bem junto dele:
    paredes de rocha do leito até perto da superfície (acima do tubo), com três patamares ondulando,
    cornija no alto e ruído de rocha — uma malha própria, fina (o leito passa escondido atrás dela),
    que não invade o tubo de outro trecho. A **inclinação das paredes varia** ao longo do cânion
    (`SLOPE_RANGE`: penhascos quase retos com patamares estreitos e encostas mais deitadas em
    terraços largos). Onde a pista chega na superfície as paredes **sobem acima
    do mar e viram a cadeia de montanhas** do trecho emerso (a 24 m da pista, picos de 34 a 112 m,
    rocha mais saliente e quase sem patamares). Material `canyon_rock.gdshader`, com muita **variação
    de cor**: estratos em faixas (debaixo d'água ardósia azulada, ocre, ferrugem, roxo acinzentado e
    verde mineral; acima do mar creme, ocre, terracota, tijolo e cinza), a sequência mudando por
    região, do tom da faixa até bem escuro pela **textura de ruído** (três eixos: manchas, médias,
    grão), escorridos de ferrugem, veios claros de quartzo, rachaduras (textura de células), colônias
    de líquen e esponjas em pontinhos de cores vivas, relevo (normal map do ruído), musgo e areia nos
    patamares, incrustações de coral, cáustica e mais escuro com a profundidade; acima do mar
    vegetação, líquen alaranjado e a faixa molhada. Nas paredes crescem (via `SeaReef.place`) corais,
    leques colados na rocha, esponjas e anêmonas saindo dela, kelp e capim no pé, **pedras** no pé e
    nos patamares, algas penduradas da cornija e musgo na borda, **jardins de corais elaborados** a
    cada 17 m nos patamares (`SeaReef.garden`), prateleiras de coral de placa e chicotes-do-mar na
    face, corais moles de cabeça para baixo na cornija e **cavernas** na face (`cave_mouth.gdshader`:
    a boca escura com pedras em volta, a sobrancelha de pedra por cima com estalactites e o cascalho na
    soleira, pontinhos de bioluminescência e, às vezes, os olhos de uma
    moreia); nas montanhas, arbustos e **árvores**
    (pinheiros-mansos, ciprestes e pinheiros de `CityProps.add_trees`) na crista e na serra. **Luzes coloridas
    submarinas** (~130): cristais acesos nos patamares (e no leito dos trechos abertos), um facho
    aditivo (`sea_beam.gdshader`) e uma `OmniLight3D` de verdade, mais fortes no entardecer e à
    noite. `SeaCanyon.open_spans` dá os trechos abertos (anfiteatro, templo e abismo).
  - `CanyonRuins` (na etapa "cânion"): ruínas de Atlântida junto da pista para dar variedade —
    **pontes de pedra atravessando o cânion por cima do tubo** (6: um arco grande que acompanha a
    seção do tubo ou do túnel de cristal 2,5 m por fora, com os pés no fundo dos dois lados, aduelas
    alternando pedra escura e tijolo e o fecho com o medalhão dourado do tridente, cornija, tabuleiro com mureta abaixo da superfície, estandartes e lanternas;
    algumas com o tabuleiro desabado no meio), **fachadas de templo** esculpidas no pé das paredes
    (colunas, entablamento e frontão entrando na rocha, porta escura, estátua ou estandartes),
    colunas quebradas e tambores caídos nos patamares e, nos trechos abertos, **aquedutos de dois
    andares** ao lado do tubo; tudo com corais, algas e musgo, e nada dentro do tubo.
  - `AtlantisRuins` ("ruínas"): Templo de Poseidon por fora da Curva do Templo (escadaria, colunas,
    friso de tríglifos, frontão com a moldura saliente, o tímpano recuado, o **tridente dourado** em
    relevo e os acrotérios, e a estátua), colunatas na avenida, o **Portal de Atlântida** (arco sobre a pista, 15 m
    livres), o **Tridente do abismo** (um tridente gigante de bronze com pátina e pontas de ouro,
    `sea_bronze.gdshader`, fincado no fundo da fossa por fora da Chicane do Tridente, com as pontas a
    3 m da superfície: de quem freia para a chicane ele aparece bem à frente; o Portal com pilastras e
    capitel nos pilares, aduelas alternando pedra e tijolo, a pedra de fecho saliente com o tridente
    dourado em relevo e a cornija), a muralha em arcos de dois andares atrás das arquibancadas do anfiteatro e, ao longe,
    prédios em ruínas (com pedaços do telhado caídos dentro, blocos soltos em volta e, às vezes, a
    escadaria e meio frontão), torres (cornijas a cada andar, janelas em arco, ameias faltando e
    blocos caídos no pé), aquedutos em ruínas (`AtlantisRuins.aqueduct`: dois andares,
    contrafortes, o canal no alto com as lajes, pontas e vãos desabados; os arcos com plinto,
    imposta, aduelas de tijolo, fecho e cornija) e colunas (cada uma no chão do seu lugar) com
    lanternas (globo aceso com o anel e a tampa de bronze em cúpula), estandartes azuis com o tridente
    dourado (`banner_trident.gdshader`, desenhado no shader) e estátuas, tudo fora do tubo; corais
    no pé das colunas, musgo no alto e algas penduradas nas arcadas. As **colunas** (`column`, usadas
    pelo templo, pela avenida, pelas praças, pelas fachadas do cânion e pelas ruínas) são jônicas: base
    moldurada, fuste com êntase e doze caneluras em facetas (o toon mostra as listras), equino, as duas
    volutas enroladas e o ábaco; as quebradas têm o topo irregular. A muralha do anfiteatro tem
    estátuas (Poseidon e a deusa, alternando) em pedestais no alto.
  - `SeaVents` ("vulcões"): **10 vulcões de bolhas** logo ao lado do tubo nos trechos abertos (3 a 22 m
    da borda dele, sem encostar no tubo, na laje nem nos arcos) — montes de rocha vulcânica irregular
    (anéis com ruído, sulcos de lava escorrida), crostas minerais coloridas perto da boca (enxofre,
    ferrugem, esteiras de bactérias), almofadas de lava, a cratera acesa, rachaduras de lava, halo
    laranja (`vent_glow.gdshader`) e uma luz de verdade; **chaminés** em volta da boca (fumarolas
    negras: troncos tortos e encaroçados, largos no pé e finos no alto, com crostas de enxofre e
    ferrugem em manchas perto da boca e a esteira branca no pé) soltando fumaça escura e bolhas, as
    rachaduras de lava finas e em zigue-zague, com falhas, **vermes tubulares** no pé (tubos brancos
    com a pluma vermelha), a água
    tremendo de calor sobre a boca (`vent_shimmer.gdshader`), a coluna de bolhas até a superfície
    (`vent_bubbles.gdshader`, sem emissor; o modo `puff` faz a fumaça) e a espuma onde ela chega.
  - `SeaRelics` ("relíquias"): o que enche o leito nos trechos abertos, dos dois lados do tubo (perto
    na maioria): **naufrágios de galés** (casco de tábuas tombado e meio enterrado — 26 seções com o
    bojo arredondado de nove pontos e as fiadas de tábuas finas —, o rombo com as costelas à mostra e
    tábuas quebradas saindo tortas, aríete de bronze, popa enrolada, remos, mastro com a vela do
    tridente ou quebrado, ânforas), **praças afundadas** (lajes com a areia nas bordas, templo redondo de cúpula
    meio desabada, fonte com estátua ou estátua no pedestal, muretas de casas, escadaria, lanternas,
    o piso em mosaico com a estrela de oito pontas em azul-marinho e dourado e as faixas azul e
    terracota),
    **arcos de pedra** naturais e **pináculos** (malhas de rocha varridas, com ruído e camadas, na
    rocha estratificada do cânion) com corais no topo, campos de **ânforas** (com as faixas pintadas de
    preto) com âncora e baú de moedas (tábuas, cintas e cantos de bronze, fechadura dourada e a tampa
    abobadada aberta), **estátuas gigantes** caídas (Poseidon tombado de costas, com as costas na areia, e o
    rosto, o busto e o sentado meio enterrados, cada um na sua profundidade) e, junto do vidro, **poças de vida**
    (marisco gigante com o manto colorido, estrelas-do-mar, ouriços, anêmonas). As peças saem de um
    saco embaralhado na proporção dos pesos (quem não coube tenta no próximo lugar e, depois de três
    vezes, vai para o fundo do saco), então nenhuma falta quando o traçado muda. Cada peça ocupa o seu
    lugar do leito (`SeaFloor.claim`): os recifes não nascem dentro e os bichos grandes passam por
    cima.
  - `PoseidonGate` ("portão"): no trecho emerso, a **cadeia de montanhas** do cânion em volta da
    pista com **três cachoeiras grandes e largas** (`WIDE_FALLS`: cortinas de 76 a 96 m saltando do
    alto da montanha em arco por cima da encosta, a velocidade de cada coluna calculada para passar
    na frente da rocha; `waterfall.gdshader` modo 3, com espuma ao longo do pé e névoa subindo, modo
    4), **dois aquedutos de pedra por cima da pista** (`AQUEDUCTS`: de montanha a montanha, o arco
    grande sobre a ponte com os pilares na água, arcos menores até as montanhas, um andar de arcos
    pequenos em cima com o canal de água despejando no mar dos dois lados, estandartes,
    **trepadeiras** penduradas — nunca a menos de 14 m do asfalto —, tufos de plantas debruçados nas
    bordas, arbustos e árvores em cima), **cipós** trançados pendendo de uma montanha à outra por
    cima da pista, **árvores gigantes** saindo da face das montanhas e se debruçando sobre a pista
    (em três trechos, `CANOPY_ZONES`, as copas dos dois lados se juntam e **fecham o céu**; tudo a
    14 m ou mais do asfalto), mastros com estandartes a cada 24 m dos dois lados da ponte e
    bandeiras grandes nas cristas, **dois rostos gigantes de Poseidon** esculpidos na face com
    cachoeiras saindo da boca, Poseidon com o tridente no pico mais alto, ruínas nas cristas, o
    **arco-íris** à frente da ponte (só de dia), peixes-voadores saltando e gaivotas.
  - `SeaReef` ("recifes"): recifes em manchas sobre **pedras com musgo** (coral ramificado, de
    mesa, cérebro com sulcos, esponjas em tubo, leques em rede e anêmonas; os de cima crescem sobre
    as pedras; mais as peças elaboradas: prateleiras de coral de placa, coral-pilar, esponja-barril,
    coral mole com cachos de pólipos, chicote-do-mar, marisco gigante, estrela-do-mar, ouriço e
    vermes tubulares), florestas de kelp e capim do mar (mais nos trechos abertos, nada dentro da rocha do
    cânion), mais o que as construções e as paredes do cânion registram (`hang`/`cluster`/`moss`/
    `place`). Tudo em MultiMesh por blocos com `coral.gdshader` (cor por instância — cores cheias, não
    claras demais: as claras viravam pastel de brinquedo na luz azulada —, escura na base e clareando
    para um tom mais quente nas pontas, um pouco de luz própria para os vermelhos e laranjas não
    apagarem, balanço da corrente, pólipos que brilham à noite, desenho na superfície e a cavidade
    escura no miolo dos tubos). O coral ramificado é um chifre-de-veado (galhos que se curvam e abrem em
    volta até o terceiro nível, com galhos curtos no meio), o coral-cérebro é caroçudo, o de mesa tem
    dois andares com a borda em lóbulos, o leque (gorgônia) é curvo como uma concha aberta, a anêmona
    tem a coluna, o disco oral com a boca escura e três voltas de tentáculos curvos com as pontas em
    bolinha, a estrela-do-mar tem o disco abaulado e cinco braços roliços com as pontas erguidas, o
    capim do mar tem onze folhas em fita curvando e torcendo, o kelp tem lâminas compridas que sobem
    e caem, mais cheias no alto, as prateleiras de coral de placa têm anéis de crescimento e a borda
    subindo, o coral-pilar tem os caroços das colônias, a esponja-barril tem os gomos, a borda ondulada
    e o miolo escuro, o coral mole se divide em galhos com cachos de pólipos (uma couve-flor), os
    chicotes-do-mar têm a ponta arredondada e os pólipos, o marisco tem mais gomos na concha, o ouriço
    tem mais espinhos e de tamanhos variados, os vermes tubulares têm anéis de crescimento e a pluma
    com oito filamentos, as algas penduradas têm folhas alternadas, o musgo tem os tufos fofos na borda
    e as pedras do recife têm camadas de estrato e o topo achatado. A âncora das relíquias tem a coroa,
    os braços de seção redonda com as patas em pá e o bico, e o cepo com as pontas arredondadas.
  - `SeaWorld` ("oceano"): a superfície em `water_level` — vista de cima o mar (`water.gdshader`),
    vista de baixo o **espelho d'água** (`sea_ceiling.gdshader`): pela **janela de Snell** o que
    está acima do mar — o céu de verdade do período com as nuvens e o sol, as montanhas, as
    cachoeiras e os barcos — refratado (água → ar) e distorcido pelas ondas, procurado na imagem da
    **janela do céu** (`SkyWindow`: `SubViewport` com uma câmera na superfície olhando para cima,
    só a camada `SeaWorld.WINDOW_LAYER`, com uma cópia do ambiente de fora d'água, desenhada só com a
    câmera debaixo d'água); fora dela (reflexão total) a superfície reflete a água funda: prateada
    perto da borda da janela (`mirror_tint` do período) e escurecendo até a cor da água no horizonte,
    com as linhas de luz das ondas — sem copiar a tela (o reflexo da cena virava riscos coloridos e o
    céu dobrado punha nuvens no teto todo), então o teto é opaco; o Fresnel e a borda clara entre os
    dois;
    **barcos e navios** perto da pista (`SeaBoats`: lanchas e veleiros bem por cima dela, ao longo,
    e navios ao lado, a 110–230 m, nos trechos abertos e fundos, indo e voltando, com esteira; o fundo
    dos navios debaixo d'água é de verdade — seções em V com a pintura vermelha antiincrustante, o
    bulbo da proa, a hélice e o leme —; as rotas não passam sobre rocha, o tubo perto da superfície
    nem a ponte);
    raios de sol descendo pela água (`sea_rays.gdshader`: inclinados pela luz já refratada — no máximo
    ~48,6° da vertical —, abrindo um pouco para baixo e com filetes por dentro), neve marinha e bolhas
    em volta da câmera
    (`sea_specks.gdshader`: posições numa caixa que o shader repete em volta da câmera, sem emissor;
    fora do tubo) e a cáustica sobre os pisos (`sea_caustic_overlay.gdshader`).
  - `SeaLife` ("vida marinha"): nos **trechos abertos** (sem cânion), muitos bichos — até 24 cardumes de
    peixinhos (MultiMesh: corpo fusiforme em anéis, cauda em forquilha, dorsal e peitorais;
    `fish.gdshader` com quatro espécies desenhadas no shader — cirurgião-amarelo, cirurgião-azul,
    sardinha e palhaço), raias-manta, **baleias grandes** (34 a 39 m,
    indo e voltando junto do tubo, do lado sem arquibancadas nem boxes: um grupo com filhote ao lado
    do abismo e mais quatro nos trechos abertos), tubarões,
    tartarugas e dois grupos de golfinhos (rotas fora do tubo, acima do leito; as órbitas sobem o que
    precisarem para passar por cima das ruínas, naufrágios e vulcões, e os bandos contam a altura e a
    largura em separado: um cardume é bem mais largo que alto), o polvo gigante numa
    coluna por fora da Curva do
    Polvo e grupos de **águas-vivas brilhantes** (sino em domo com a borda em lóbulos, quatro braços
    orais franzidos e dezesseis tentáculos finos; `jellyfish.gdshader`, aditivas, mais fortes à
    noite); todos andam pelo `SceneryAnimator` (Rust) e nadam no shader (`sea_creature.gdshader`: um
    material só, cor e nado por *instance uniform*, peso da animação na cor de vértice).
- **Saindo da água** (`SeaSplash`): quando a câmera passa da água para o ar (andando, depois de um
  tempo debaixo d'água; cortes de câmera não contam), gotas na lente com a imagem refratada atrás
  delas — pequenas quase paradas e grandes escorrendo com rastro — e a película d'água descendo
  pela tela no começo (`water_lens.gdshader`, numa `CanvasLayer` embaixo do HUD, ~2,8 s), mais o som
  da água escorrendo (`water_exit.wav`: o estouro na superfície, um tum grave, a água escorrendo e
  pingos; bus Crowd).
- **Linha d'água** (`SeaAtmosphere`): a altura da câmera contra `water_level` mistura (faixa de
  ±0,8 m) o ambiente do período com o de **debaixo d'água** (`SeaWorld.UNDER`: névoa densa e azul,
  céu e reflexos de água, luz do sol mais fraca e fria, sem névoa rasteira nem espalhamento da luz na
  névoa; a perspectiva aérea zerada, então a névoa é só a cor da água — com o céu misturado o fundo
  ficava azul-claro e lavado —, e a névoa de altura escurecendo a água abaixo de `deep_start` m de
  profundidade: as fossas somem no escuro); reaplica só quando muda. Só mexe no que o `Daylight`
  define de novo, mais `fog_sky_affect`, `fog_sun_scatter`, a perspectiva aérea e a névoa de altura,
  devolvidos ao sair da pista. **Noite**: água azul-marinho, LEDs, vidro e águas-vivas brilhando, sem
  raios de sol; **entardecer**: água azul-arroxeada, luz e cáustica douradas.
- **Modelos** (`blender/build_atlantis.py`, `blender -b --factory-startup -P blender/build_atlantis.py
  [-- --render <pasta>] [--only=nomes] [--out <pasta>]`, em `assets/track/atlantis_abyss/models/`;
  frente para −Y no Blender, +Z no jogo). O `build_atlantis.py` só junta, escala, reduz até o limite
  de triângulos de cada peça, pinta a cor de vértice e exporta; as peças ficam em
  `blender/atlantis_statues.py` e `blender/atlantis_creatures.py`.
  - **Bichos** (`atlantis_creatures.py`): modelados por seções já na resolução final (o corpo é um
    tubo de anéis em superelipse com costuras onde a cor muda, as nadadeiras são perfis de asa, olhos,
    tubérculos, cracas e fendas são peças encaixadas). **Jubarte** (~9 mil triângulos: cabeça achatada
    com tubérculos, mandíbula, pregas da garganta, peitorais de 1/3 do corpo com o bordo ondulado,
    corcova, cauda com o entalhe e a borda serrilhada, cracas), **raia-manta** (asa em aerofólio,
    lobos cefálicos enrolados, fendas das guelras, as manchas brancas dos ombros), **tubarão**
    (galha-preta: cinco fendas, duas dorsais, cauda heterocerca, contra-sombreamento nítido e as
    pontas pretas), **golfinho** (bico, melão, dorsal falcada, o capote escuro), **tartaruga-verde**
    (carapaça com as placas de verdade em relevo, plastrão claro, nadadeiras da frente longas como
    asas) e o **polvo** (manto rugoso, olhos com a pupila em barra, sifão, membrana e oito braços
    com as ventosas: três descem enrolados na coluna, cinco ficam soltos com as pontas enroladas).
    A cor de vértice vai para o `sea_creature.gdshader`: R = peso do nado, G = ventre, B =
    escurecimento (olhos, guelras, sulcos, bordas das placas, oclusão) e A = a cor de destaque; a cor
    final é `mix(mix(dorso, ventre, G), destaque, A) × (1 − 0,85·B)`, com dorso, ventre e destaque de
    cada bicho por *instance uniform* (`SeaLife.LOOK`).
  - **Estátuas** (`atlantis_statues.py`): esculpidas como um campo de distância em numpy e viradas
    em malha pelo OpenVDB do Blender (mechas, dobras e musculatura em relevo sobre o volume, os cachos
    como botões com o sulco em espiral, as peças duras — trono, plinto, base do busto — com arestas
    vivas; na redução o rosto e as mãos ficam com a maior parte dos triângulos). O **rosto das
    cachoeiras** (28 m: testa franzida, olhos fundos, nariz grego, a boca aberta e funda com o lábio de
    baixo de bica — `PoseidonGate.FACE_MOUTH` = 10,8 m de altura e 8,7 m à frente, a água com a
    largura da boca —, bigode, barba longa em mechas e cachos, juba de ondas do mar e coroa de nove
    pontas), **Poseidon em pé** (15 m: contrapposto, o punho fechado no tridente farpado, himátio com
    o rolo na cintura e as dobras, sandálias e plinto), **Poseidon sentado** (11 m: trono com o encosto
    em leque de concha, golfinhos nos braços e ondas nos painéis, himátio no colo, o tridente em pé) e
    o **busto da deusa** (7,8 m: rosto sereno, cabelo repartido com o coque torcido e as mechas
    onduladas, o diadema em crescente baixo com a concha, quíton com dobras e a base moldurada). A cor de vértice é a pedra
    escurecida pela oclusão medida no campo (os sulcos e o fundo da boca escuros), mais o dourado das
    coroas, dos tridentes e do diadema; a pedra de Atlântida (`sea_stone`) clareia os cinzas para o
    mármore e mantém o dourado.
- **Som** (`SeaAudio`, sons de `python tools/generate_sea_sounds.py` em `assets/audio/ambient/`, bus
  Crowd; `water_exit.wav` é da saída da água): debaixo d'água o zumbido grave e as bolhas (entram e
  saem com a linha d'água) e cantos de
  baleia de vez em quando; no Portão, o rugido de cada cachoeira, e o borbulhar de cada vulcão (3D,
  só perto da câmera).
- Teste: `tests/atlantis_abyss_test.gd` (traçado abaixo e acima da água, a Chicane do Tridente
  (direita-esquerda, escape largo) e o tridente gigante fora do tubo, pisos, grid e 14 boxes,
  boxes antes da linha, barreira em toda a volta, nada sobre a pista, cenário gerado, pista submersa
  toda dentro do tubo ou do túnel, corais e águas-vivas fora do tubo, vulcões, barcos e baleias
  grandes perto do tubo, cânion na maior parte da pista submersa com as paredes fora do tubo e a
  inclinação variando, pontes, fachadas e aquedutos do cânion fora do tubo, montanhas no trecho
  emerso com as cachoeiras largas fora da laje e os aquedutos por cima da pista, paredes perto do
  tubo, árvores nas montanhas, luzes coloridas, bichos grandes nos trechos abertos, vulcões perto do
  tubo com chaminés, relíquias dos trechos abertos fora do tubo, corais elaborados, cavernas,
  estandartes no tubo e no aqueduto, cipós e árvores sobre a pista com a folga dos carros, bandeiras
  nas cristas, barcos perto da pista, a janela do céu, troca de névoa na linha d'água e o
  Environment de volta ao sair, gotas na tela e som saindo da água, carro parado nas curvas e
  rampas); a galeria dos modelos em `tests/atlantis_models_gallery.gd` (com janela, `--offline`: esconde
  o cenário e monta cada peça do fundo do mar sozinha, de perto, num lugar plano do leito longe da
  pista, com os materiais e a luz do jogo — uma captura por peça); capturas em
  `tests/atlantis_abyss_shots.gd` (com janela: rode com `--offline`), inclusive
  a Chicane do Tridente (chegando, por dentro e do alto), o tridente gigante, um cardume, as
  águas-vivas, o kelp, um recife do leito e as relíquias de perto.

## Rainbow Raceway (pista fantasia fofa nas nuvens)

Terceira pista da categoria **Fantasia**: uma pista cor-de-rosa flutuando sobre nuvens de algodão-doce,
entre ilhas voadoras, arco-íris e ursinhos de pelúcia. `scenes/tracks/rainbow_raceway.tscn` +
`resources/tracks/rainbow_raceway_layout.tres` (grupo "Nuvens" do `TrackLayout`: `clouds = true` e
`cloud_floor`, a altura do mar de nuvens lá embaixo; o túnel em `tunnel`).

- **Traçado** (`python tools/build_rainbow_raceway.py [--debug pasta]`, o método por trechos da Sky
  Aerobase). 4,23 km, anti-horário, de 8 a 41 m de altura: **Reta do Arco-Íris** (boxes, grid e
  arquibancadas, ~820 m somando o fim da volta), Curva do Ursinho, Subida do Algodão, Esses das Nuvens,
  Reta do Castelo, **Grampo do Castelo** (165°, raio 34 m), Ponte Levadiça, Curva da Torre, o **Túnel do
  Arco-Íris** (265 m), Esse das Bolhas, a **Reta do Mirante** e a **Espiral do Algodão-Doce** (300° de
  raio 66 m descendo 18 m em volta da Torre de Algodão-Doce), que sai **por baixo da Reta do Mirante**
  (o único cruzamento da pista: 19 m de folga, a 60°; o rumo soma 720° — `DIRECTION = 2` no gerador),
  a Passagem do Arco-Íris, a Curva do Pirulito, Reta das Cachoeiras, a **Chicane da Estrela**
  (esquerda-direita de raio 22 m), Reta dos Balões, Curva do Coração, Reta dos Ursinhos e a Última
  Curva. O gerador confere que há exatamente um cruzamento com folga e que os outros trechos não
  vizinhos ficam a 60 m ou mais. A linha de corrida (`rainbow_raceway_raceline.csv`) leva a elevação, como
  a de Suzuka: o `RacingLine` projeta cada ponto com a altura e não mistura os dois níveis no cruzamento.
  Os bots fazem ~76 s (volta mínima plausível online: 55 s).
- **Barreiras em toda a volta** (ninguém cai; não há `FallWatch`): muro acolchoado cor-de-rosa com o
  topo arredondado, um **rolo de almofada** creme por cima e **corações acesos** na face a cada ~10 m
  (`TrackBarriers._cloud_wall`; colisão igual à das outras pistas). Escape maior por fora das curvas
  lentas; laje de colisão sob os pisos (`DeckFloor`); 14 boxes (todo o grid online).
- **Pista** (`TrackRoad`, com `clouds`): **asfalto rosa envernizado** (`track_surface_gloss.gdshader`:
  o piso de sempre com brilho e reflexo do céu), **zebras de arco-íris** (as seis cores em sequência),
  faixa creme até a barreira com as **seis listras do arco-íris** no pé dela, **corações brancos
  pintados** no meio da pista (vazados a cada ~55 m nas retas, com um par de pequenos cheios nas
  faixas) e **três estrelas acesas** no piso na saída de cada curva lenta. Os postes são **bengalas de
  doce** listradas com o gancho sobre a pista e uma estrela pendurada (luz de verdade à noite).
- **Plástico pastel** (`TrackMaterials.candy`, ligado pelo RaceTrack nesta pista): tudo o que passa
  por `TrackMaterials.building()` (barreiras, boxes, arquibancadas, pórticos, castelo, enfeites) usa
  `candy.gdshader` — cinzas e brancos da cor de vértice viram lilás, rosa e creme pela claridade,
  cores fortes ficam, com brilho macio de brinquedo e pontinhos de **açúcar cintilando** de perto.
- **Geração** (ramo `layout.clouds` do `RaceTrack.rebuild`; o servidor pula tudo menos pista,
  barreiras, boxes e objetos, que é o que tem colisão):
  - `CloudDeck` ("almofadas"): laje de glacê sob a pista, de uma borda à outra da plataforma, com a
    beirada branca, as seis listras do arco-íris na lateral e o fundo lilás, apoiada em **nuvens
    fofas** (de pé nas beiradas, aparecendo um pouco acima da laje, e de cabeça para baixo no fundo,
    com umas pendentes maiores); perto do cruzamento as da pista de cima não descem sobre a de baixo.
    Pedaços de ~300 m com a nuvem detalhada até 420 m e uma simples longe.
  - `RainbowTunnel` ("túnel"): abóbada com as seis faixas acesas subindo dos dois lados até o teto
    lilás estrelado, **anéis de luz** a cada ~12 m com um pulso correndo no sentido da pista, portais
    de arco-íris sólido com estrela nas duas bocas e, por fora, a casca rosa coberta de nuvens.
  - `CloudIslands` ("ilhas"): ~60 **ilhas voadoras** (rocha de bala afinando para baixo, em degradê
    pastel e com normais suaves, topo de grama menta ou rosa, contorno de nuvens) longe da plataforma, com **árvores de pirulito e
    de algodão-doce**, arbustos, canteiros de flores, cogumelos, balas de goma, bengalas e **casinhas
    de cupcake** (porta em arco, janelas acesas, granulado, cereja e chaminé de bengala), agrupados por
    célula do mapa num MultiMesh por tipo (`CandyDecor`). **Cachoeiras** pastel caindo das beiradas
    (`candy_fall.gdshader`: filetes, arco-íris no meio da queda, somem em névoa) com riacho até a
    borda, nuvens de névoa e arco-íris pequenos. Marcos (`CloudIslands.LANDMARKS`): a ilha do
    castelo, a **Ilha do Coração** (moldura de coração gigante), a **Ilha das Cachoeiras** (alta, três
    quedas), a **Ilha dos Ursinhos**, a do Ursinho da curva 1, a **Ilha dos Doces** (cupcakes,
    rosquinhas e pirulitos gigantes) e a ilha da torre no meio da espiral (`spiral_center`).
  - `CandyCastle` ("castelo"): o **Castelo de Algodão-Doce** no campo interno, de frente para a
    largada: base em degraus, muralha de oito lados com ameias e glacê escorrendo, oito torres com
    telhado de bruxa, aba dourada e bandeira, a torre principal com varanda e **janela de coração**,
    quatro torres altas e duas agulhas, portão com ponte levadiça e janelas acesas à noite, com um
    **arco-íris sólido** por trás; e a **Torre de Algodão-Doce** (forminha listrada e uma espiral de
    sorvete subindo até ~66 m, com cereja e coração) que a pista contorna na espiral.
  - `HeartArches` ("arcos"): o **Arco do Coração** na largada (arco fofo cor-de-rosa sobre a pista e
    a pista dos boxes, arco-íris por dentro, coração aceso no topo, estrelas e a **faixa xadrez** que
    segura as luzes de largada — o `TrackProps` só põe as luzes na altura `START_BEAM`), **arcos de
    arco-íris** sólidos atravessando a pista, **portais de pirulitos gigantes** com bandeirolas pastel
    e o arco-íris sob a ponte do cruzamento.
  - `PlushFriends` ("pelúcias"): **ursinhos e coelhinhos de pelúcia** (`blender/cloud_plush.py`:
    metabolas fundidas num corpo macio, olhos, nariz, boquinha, laço e coração; `blender
    -b --factory-startup -P blender/build_clouds.py` gera os `.glb` em
    `assets/track/rainbow_raceway/models/`) em almofadas de nuvem atrás das barreiras, **acenando**
    para quem passa (`plush.gdshader`: o braço gira em volta do ombro, a cor do pelo e do laço vêm de
    cada instância), o **Ursinho gigante** da Curva do Ursinho (22 m) e o piquenique na Ilha dos
    Ursinhos.
  - `CloudProps` ("doces"): **placas** com coração e tábuas em seta com recados (Label3D na fonte
    Bungee), o letreiro **RAINBOW RACEWAY** numa nuvem depois da largada, nomes nas ilhas grandes, o
    **Mirante das Nuvens** (varanda com binóculos de moeda, bancos e vasos, virada para a torre),
    **caixas de presente** de vidro com coração dentro girando sobre a pista (`gift_box.gdshader`),
    cachos de **balões de coração** balançando nas barreiras (`balloon.gdshader`) e estrelas grandes
    acesas girando no ar.
  - `CloudWorld` ("céu"): mar de nuvens pastel lá embaixo (`cloud_deck.gdshader` mais fechado, fundo
    lilás), nuvens 3D em tons de rosa, lilás e branco em quatro camadas, **arco-íris gigantes** saindo
    do mar de nuvens, **brilhinhos** piscando no ar (`sparkle.gdshader`), **balões de ar quente** (gomos
    pastel ou coração estufado, passeando com o `SceneryAnimator`), pombinhas e as equipes nos boxes. `apply_mood` deixa o céu pastel em todos os períodos (azul e rosa de dia, pêssego e violeta
    no entardecer, índigo estrelado à noite), as nuvens lilases de luar à noite, menos perspectiva
    aérea e um pouco mais de saturação; o `_EnvKeeper` devolve o Environment do Daylight ao sair.
- **Teste**: `tests/rainbow_raceway_test.gd` (traçado e desnível, o cruzamento com folga e projeção no
  nível certo, asfalto em cima e embaixo da ponte, pisos, grid e 14 boxes, barreira em toda a volta,
  vão livre e nada acima do asfalto, o mundo gerado, arcos e enfeites a mais de 5,5 m sobre a pista,
  as caixas no alto, as nuvens da ponte acima da pista de baixo, ilhas longe da plataforma,
  cachoeiras, enfeites e casinhas, a torre no meio da espiral, pelúcias atrás das barreiras, placas e
  textos, luzes à noite, o ambiente de volta ao sair e o carro parado no grampo, na espiral, em cima e
  embaixo da ponte e na chicane); capturas em `tests/rainbow_raceway_shots.gd` (com janela, `--offline`).

## Vitrine: balões de personagem, outdoors e murais

`scripts/track/track_showcase.gd` (etapa "vitrine" da geração, nas duas pistas; o servidor pula):

- **Balões de personagem — Psyduck e Hamtaro** (`assets/track/balloons/*.glb`): balões de formato
  especial com ~40 m (modelo de ~27 m em escala 1,5), cesto de vime, maçarico e cabos. Ficam presos
  e bem à vista: em Monza, nas duas retas mais longas (`TrackShowcase.straights`), ~300 m à frente
  de quem entra nela e pouco para o lado de fora, com a base a 34 m (acima das árvores); em Mônaco,
  procurados ao longo da volta onde há céu aberto, por cima dos telhados e de preferência sobre o
  porto. Nos dois casos a visada da pista até o balão não pode passar por prédios nem por
  arquibancadas/boxes (`TrackShowcase.blocked`, filtrando pelos retângulos) e o balão não pode ficar
  alto demais no quadro. Virados para quem vem, sobem e descem e giram poucos graus; materiais toon.
- **Modelagem** (`blender/build_balloons.py`, `blender -b --factory-startup -P blender/build_balloons.py
  [-- --render <pasta>]`): metabolas (o corpo sai liso e "inflado", como um balão), uma família por
  cor, viradas malha. *Psyduck*: cabeça grande, corpo em pera, as mãos segurando a cabeça (braços em
  peça à parte, com vinco no ombro), bico creme chato em duas partes, olhinhos brancos com pupila de
  ponto, três fios de cabelo pretos e pés de pato com dedos. *Hamtaro*: cabeça de chibi com bochechas,
  testa laranja em arco por cima dos olhos com a faixa branca no meio, laterais/nuca/costas laranja e
  cara/barriga creme (a malha é cortada nas bordas antes de pintar, para as manchas saírem limpas),
  orelhas laranja e rosa, olhões pretos com dois brilhos, bochechas rosadas, nariz, boquinha em "w",
  bigodes e bracinhos para cima. Olhos, nariz e cabelos são presos na superfície por raycast.
- **Imagens de `assets/outdoors`** (todas as que estiverem na pasta; recorte central 3:2; importadas
  comprimidas, com mipmaps, até 1024 px), sempre discretas:
  - **dirigíveis**: um painel curvo (segue o casco) na traseira de alguns deles, nas duas pistas;
  - **outdoors**: até 4 placas de 6 × 4 m em dois postes, logo atrás da barreira e acima da tela,
    giradas 40° para quem vem pela reta (só em chão livre: fora de escapes, arquibancadas, boxes e
    prédios);
  - **murais**: no alto de paredes de prédios de Mônaco viradas para a pista (a 50–230 m, vistas da
    pista por cima dos outros prédios) e nas paredes laterais (sem janelas) das casas e nos
    campanários dos vilarejos ao fundo de Monza.

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
endereço muda na aba **SERVIDOR** da tela Multiplayer (fica salvo) ou com `-- --connect=host:porta`.
Para dois jogos no mesmo PC: `-- --account=segundo` (outra conta). `-- --offline` não conecta. Sem
servidor, o jogo segue offline com o perfil local do aparelho (solo, loja e estúdio locais).

**IPv6**: o servidor escuta em IPv4 e IPv6 na mesma porta (ENet com socket duplo). O endereço
aceita `host`, `host:porta`, IPv6 puro (`2001:db8::1`, porta padrão) ou com porta entre colchetes
(`[2001:db8::1]:7350`), e nomes que resolvem para IPv6 (`NetProtocol.parse_address` /
`format_address`). Na VM, a porta UDP precisa estar liberada também para IPv6.

**Aba SERVIDOR** (`multiplayer_panel.gd`, aparece também sem conexão):
- **Endereço** atual (com ping) e **Desconectar**; **servidores salvos com nome** (salvar de novo o
  mesmo endereço renomeia; editar, remover) e as **últimas conexões** (8, só as que entraram de
  fato, com "há 2 h"; salvar com nome, limpar). Ficam no arquivo da conta do aparelho
  (`account.cfg`, seção `[servers]`).
- **Hospedar** (`scripts/net/local_host.gd`, `LocalHost`, filho do `Net`): **ABRIR SERVIDOR** sobe o
  servidor dedicado num processo à parte, o mesmo executável sem janela
  (`--headless -- --server --host-dir=… --host-watch`; fora do jogo exportado, com `--path`).
  Com `--host-dir` o servidor usa um **banco em arquivo** em vez do Turso (`LocalStore`,
  `user://host/server_db.json`; mesmas operações do `AccountStore`, grava no máximo 1 vez por
  segundo, por troca atômica) — quem hospeda não precisa de banco nem de segredo. O jogo entra no
  próprio servidor sozinho (opção) sem trocar o servidor padrão; ao fechar, volta para ele.
- **Controle** por arquivos na pasta do host (`HostControl`, `scripts/server/host_control.gd`):
  `status.json` a cada segundo (no ar há quanto tempo, jogadores e onde estão, salas, contas) e
  `cmd_<n>.json` com **fechar** (grava o banco e sai) e **tirar** um jogador (ele vê o motivo e não
  reconecta sozinho). O jogo grava a hora em `alive` a cada 2 s; se parar por 30 s (jogo fechou ou
  travou), o servidor fecha sozinho. O log do processo aparece na tela (e em `server.log`).
- **Passe para os amigos**: endereços da rede local (IPv4/IPv6) e IPv6 público (forma curta), com
  Copiar; **UPnP** opcional abre a porta UDP no roteador (numa thread) e mostra o IP externo; a
  porta é fechada ao parar. O processo do servidor nunca grava o perfil nem as configurações do
  jogador (`NetProtocol.is_server_process()`).

**Conectado** (`Profile.mode = "remote"`): créditos, coleção e equipamento vêm do servidor; o giro
da loja é feito lá. **O carro do aparelho vale no servidor**: ao conectar, o jogo manda o visual
(pintura, cores, peças, acabamentos) e a engenharia do perfil local, e o servidor usa esse carro
nas corridas; a coleção local também conta para montar o carro no Estúdio enquanto conectado. **Qual carro vale**: o equipamento guarda a hora da última mudança do jogador (`equipped.edited`);
ao conectar, o servidor só troca o do banco pelo do aparelho se o do aparelho for mais novo, e o
jogo guarda no aparelho o equipamento que vale no servidor (`Profile.store_equipped_locally`). Assim
o que se configura online (decalques, skin, cores, peças, engenharia) fica salvo no banco e não é
apagado na próxima conexão pelo carro antigo do aparelho, e o carro offline é o mesmo. Uma resposta
do servidor mais velha que uma mudança ainda a caminho não desfaz a mudança na tela.
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
- **Observadores**: na sala (fora da fila), "SÓ ASSISTIR" deixa o jogador fora do grid — não precisa
  marcar pronto, não ocupa lugar (até `NetProtocol.MAX_SPECTATORS` por sala) e, na largada, abre a
  corrida sem carro, no modo espectador travado (câmeras de TV, livre e perseguição; Esc volta ao
  menu). Na lista de salas, as que estão correndo aparecem com "ASSISTIR": dá para entrar no meio da
  corrida só para ver (o servidor manda a largada na hora e os instantâneos dali em diante). Uma sala
  só de observadores não larga.
- **Atualizações da sala** (ajustes do anfitrião, alguém pronto) não tiram ninguém da tela em que
  está (garagem, loja…): a tela da sala só abre sozinha quando o jogador entra numa sala nova, e a
  própria tela da sala se refaz mantendo a rolagem e o foco.
- **Salas**: corrida rápida (fila, larga quando todos marcam pronto), Custom (nome, senha, pista,
  voltas 3/5/10/15, bots e dificuldade, **corredores no grid** 2–14 — jogadores + bots; a sala
  aceita até 10 jogadores —, classificatória (voltas, tempo limite, colisão e se infração anula a
  volta), DRS, colisões no box, horário, ambiente; o anfitrião
  larga), contra bots (do grupo). Quem está na sala Custom convida amigos online, e o convidado
  entra mesmo com senha.
- **Ranking**: Geral, Vitórias, Ganhos, Volta mais rápida; Geral = soma de round(valor ÷ líder ×
  1000) por aba; só valores > 0; empates por nome e id dividem a posição (1, 2, 2, 4); 50 linhas e
  a sua; cache de 15 s; sem temporadas.
- **Perfil** (só amigos e o dono): nome (até 16, vazio = Jogador), código, nível, título (validado
  pelas conquistas e pelos títulos-item da coleção), últimas 5 corridas, 25 conquistas, "como você
  pilota" (6 traços das últimas 10 corridas, 0,5 sem histórico). Ganhos totais só o dono vê.
- **Conquistas pagam** (uma vez, `counters.ach_paid`): 300 / 800 / 2.000 / 5.000 / 12.000 créditos
  pelo grau; Interceptor (300 posições ganhas online) dá também a **Sirene**. Contas antigas
  recebem as já feitas ao entrar (aviso "Recompensas de conquistas"). Conquistas difíceis novas,
  com **títulos especiais**: **Midnight** (100 vitórias online à noite), **Winged Death** (1.000
  batidas fortes causadas em outros jogadores: a culpa da colisão, `_penalize` "COLISÃO", junto de
  uma peça arrancada da vítima em até 2 s, `RaceManager.note_crash`) e **Nightmare** (vencer
  ultrapassando o líder humano na reta final da última volta; `RaceTrack.final_straight_s`).
- **Títulos especiais** (`scripts/ui/title_label.gd`, `TitleLabel`): fonte própria
  (`assets/fonts/neon/`) e animação — Midnight (Monoton, pulso azul), Winged Death (Rye, vermelho
  com tremor), Nightmare (Bungee, glitch roxo), Tempestade (clarão percorrendo as letras), Fantasma
  (some e volta) e Soberano do Céu (dourado com brilho deslizando). Aparecem na sala, no perfil,
  na lista de amigos e nos cartões da Galeria; os comuns ficam na cor do grau.
- **Missões diárias** (`scripts/server/missions.gd`, aba MISSÕES): três por dia, iguais para todos,
  sorteadas pela data (Brasília) entre 10 tipos (corridas, pódio, vitória, voltas, corrida limpa,
  volta mais rápida, pista do dia, corrida à noite, ganhar 4 posições, corridas online), de 300 a
  1.000 créditos cada, pagos na hora. Completar as 21 da semana (segunda a domingo) dá 3.000
  créditos e um exclusivo. Contam as corridas validadas pelo servidor (online e solo conectado); o
  estado fica em `counters.missions`, sem tabela nova, e vira o dia sem job (comparação preguiçosa).
- **Roleta do vencedor** (online, 1º lugar sem desclassificação): o servidor guarda o giro
  (`counters.race_spins`) e sorteia em `race_spin` — 5% exclusivo (2.000 créditos se já tiver
  todos), 50% 500 créditos, 30% 1.000 créditos, 15% um ticket (`ShopCatalog.WINNER_WHEEL`). A roda
  (`scripts/ui/prize_wheel.gd`) tem as fatias do tamanho das chances e para na sorteada; quem fechar
  a tela final sem girar gira depois na aba MISSÕES.
- **Nível** = 1 + ⌊√(xp ÷ 40)⌋, xp dos contadores (volta 3, corrida 10, pódio 15, vitória 25).
  Bots liberados por nível: fácil 1, médio 3, difícil 6, mista 3.

**Corrida em rede**: a cena de Monza roda no servidor dentro de um `SubViewport` com mundo 3D
próprio (cada sala tem a sua física) e só o que tem colisão (sem árvores, folhas, público…). O
`RaceManager` em modo `SERVER` monta o grid (humanos na frente em ordem sorteada, bots completando
até 10 se a sala usa bots; carros com o visual e a engenharia das contas) e aplica todas as regras
(penalidades, pit, bandeira amarela, safety car). O cliente manda os comandos a cada passo de
física (pedais, direção e contadores das ações de toque, que não se perdem); recebe instantâneos
de todos os carros 30×/s (`NetSnapshot`, 64 bytes por carro; o servidor desconta o intervalo em
vez de zerar, sem deriva) e o estado da prova 5×/s; desenha os carros um pouco no passado (a
**folga de interpolação**), interpolando (`NetRaceClient`; os carros do cliente são marionetes
cinemáticas, `F1Car.set_puppet`). A folga é **adaptativa**: para cada instantâneo o cliente mede o
quanto ele chegou atrasado em relação ao mais rápido dos últimos ~3 s e usa um intervalo entre
instantâneos + o percentil 95 desses atrasos + 10 ms (entre 40 e 250 ms; começa em 150 ms), subindo
rápido quando a rede piora e descendo devagar. Numa rede estável fica em ~55 ms (era 150 fixa);
com 60 ms de variação, ~100 ms, faltando instantâneo em menos de 1% dos passos
(`tests/interp_test.gd`, `-- --net-jitter=ms` simula variação). **Conexão**: o ENet tolera 15 a
30 s sem resposta (`NetProtocol.PEER_TIMEOUT_*`; o padrão de ~5 s derrubava quem engasgava
gerando a pista ao carregar a corrida). O relógio do servidor no cliente é o maior "tempo do
instantâneo − hora local" dos últimos 15 instantâneos: sobe na hora e desce aos poucos (~0,5 s),
então um passo atrasado no servidor (o tempo da simulação fica para trás) não deixa o cliente
adiante dos instantâneos. Sem instantâneo novo, a última posição é esticada pela velocidade (até
0,25 s) e, quando eles voltam, o carro vai até a posição interpolada em 8 passos, sem salto.

**Predição no cliente** (`NetPrediction`, só o carro do próprio jogador): o carro roda a física no
aparelho com o comando aplicado na hora — sem a ida e volta ao servidor nem o atraso de
interpolação no controle (com 120 ms de ida e volta, o carro respondia em ~370 ms; com predição,
em ~50 ms, o mesmo de jogar sem rede). O servidor aplica os comandos **um por passo, em ordem**
(fila curta contra o jitter; repete o último se faltar, descarta os mais velhos se acumular) e
manda no fim do instantâneo de cada jogador o **ack** (u32: último comando aplicado + quantas
vezes ele foi repetido desde que chegou, zerando a cada comando novo; clientes antigos ignoram).
Na 0.8.1 a repetição adiantava a numeração de vez: depois de um engasgo do jogo (carregando a
pista, na largada, ao recomeçar) o ack passava à frente do jogo e a limpeza do histórico da
predição entrava em loop infinito — o jogo congelava na largada. O histórico agora é descartado
pela ordem das sequências, sem contador (`tests/prediction_test.gd` congela o jogo 1,5 s no meio
da corrida). Na 0.8.2, ao recomeçar, o carro voltava aos saltos para onde estava: na sala nova
o servidor deixava os carros dos jogadores soltos enquanto esperava todos carregarem e repetia o
último comando da corrida anterior (quem vota costuma estar acelerando) — o carro saía andando
sozinho, a predição saltava atrás dele e a largada o devolvia ao grid. Agora os humanos ficam
travados no grid desde que a corrida nova é montada até o semáforo, e a numeração dos comandos é
contínua entre corridas (fica no `Net`; o servidor recomeça a fila se ela voltar muito para trás,
p. ex. jogo reiniciado) — `tests/restart_jump_test.gd`. O cliente guarda o estado previsto depois
de cada comando e,
quando o instantâneo chega, compara com o estado do servidor para o mesmo comando
(**reconciliação**): erro pequeno (< 5 cm, 0,3 m/s, 1°) é ignorado; médio corrige a velocidade na
hora e a posição/rotação aos poucos (25% por passo), corrigindo junto o histórico posterior;
grande (> 4 m: batida, carro levado aos boxes ou de volta à pista) salta para o estado do
servidor. Largada/parada, dano, pneus, rodas quebradas e bateria vêm sempre do servidor; o dano das
batidas também (os contatos locais não viram dano). Servidor antigo (sem ack), depois da
bandeirada ou abandono: o carro volta a seguir o servidor como os outros. Para testar com atraso:
`-- --net-lag=120` (ida e volta simulada) e `-- --no-prediction` (comparar com o modo antigo).

**Batidas fantasmas e trancos (protocolo 8)**. O carro previsto fica à frente do servidor (os
comandos dele ainda vão chegar lá) e os outros eram desenhados no passado (atraso + folga): juntos,
100–200 ms, 8–16 m a 300 km/h. O carro daqui colidia com esse "fantasma" (às vezes ficava preso nele
enquanto o servidor seguia: "travo, volto e bato") e, no servidor, quem passava "perto" batia de
verdade no carro que estava bem mais à frente. Agora:
- **Os outros no instante do meu carro** (`NetRaceClient._update_lead`): a pose interpolada é
  esticada pela velocidade e pelo giro até o instante em que o servidor aplica o comando atual do
  jogador (o instante mostrado anda um passo do servidor por passo e o esticar acompanha o relógio
  da interpolação na hora — um ajuste nele cancela o outro; só a velocidade e o giro usados para
  esticar são suavizados, sem quina no começo de uma freada). `-- --no-lead` desliga.
- **Colisão entre carros é do servidor**: aqui o carro previsto não colide com os outros em
  movimento nem com os destroços (simulados à parte em cada máquina); com um carro parado (batido,
  rodado, no grid) colide também, porque a posição dele é a de verdade.
- **Comandos com redundância**: cada pacote leva os 4 anteriores (`NetProtocol.INPUT_REDUNDANCY`);
  o que se perdeu ou chegou fora de ordem entra pelo seguinte (antes o servidor repetia o último).
- **Ritmo**: o servidor manda no instantâneo a folga dos comandos (percentil 5 da janela de 1 s) e
  o cliente roda 1 ou 2 passos de física por segundo a mais ou a menos para mantê-la entre 2 e 4
  (`physics_ticks_per_second` e `time_scale` juntos: o passo tem a duração do do servidor). Segurar
  ou pular um passo no servidor movia o carro um passo inteiro (~0,7 m a 300 km/h) — agora só fora
  dessa faixa.
- O salto da correção grande mantém a altura do carro acima do piso (adiantado em linha reta numa
  chicane, podia ficar dentro do chão).

Medido com `tests/net_frame_probe.gd` (Monza, 10 carros, bot pilotando o carro do jogador; antes →
depois): com 60 ms de ida e volta e 20 ms de variação, o outro carro perto aparecia a 9,0 m
(mediana; p95 26 m) de onde estava no servidor → 0,6 m (p95 1,8 m); colisões só no cliente 79 → 0;
batidas do jogador no servidor 20 → 0; comandos repetidos 1.270/min → 1; correções 272 → 68 (erro
máx. 8,8 → 0,07 m); saltos visuais do meu carro 271 → 0. Com 90/45 ms: 28 → 0 batidas, 300 → 0
colisões fantasmas, 2.409 → ~10 repetidos. A sonda mede também os saltos visuais dos outros carros
(passo × passo anterior: 25 antes, 4–22 depois).

**Servidor sem travar as salas**: a thread principal do servidor roda a física, os bots e a rede
de todas as salas a 120 Hz, então nada pode prendê-la por muito tempo.
- **Pistas geradas uma vez**: na subida, `RaceTrack.prewarm_server` gera a versão de servidor de
  cada pista (só colisão, sem o visual de `SERVER_SKIP`; ~10 a 15 s, em etapas) e guarda uma cópia
  dos nós e os dados calculados. Cada sala só copia os nós (`duplicate`, ~50 ms; os shapes de colisão
  são compartilhados e cada sala monta os próprios corpos no seu mundo de física) e monta luzes de
  largada novas. Os shapes criados direto no corpo (`create_shape_owner`: barreiras e muros do
  corte de Suzuka) não vão no `duplicate` e são recriados na cópia (sem isso, na 0.8.0, os muros não
  tinham colisão no servidor). Uma sala que larga antes de a pista ficar pronta espera por ela. O log mostra
  `RaceTrack: ... copiados do cache` em vez de `gerados em`.
- **Carros do servidor**: nascem sem som, efeitos, piloto animado e retrovisores, e o dano não copia
  as malhas (a zona de cada peça sai da caixa da malha; o amassado é coisa dos clientes). O grid entra
  **um carro por quadro**, cada um já no seu lugar. Antes, uma largada prendia a thread uns 5 s (pista
  ~3,5 s + carros ~1,3 s) e as outras salas congelavam e depois davam um salto.
- **Medidor** (`ServerStats`): a cada minuto o log mostra quantos passos de física passaram de 8,3 ms,
  o pior passo e quantas salas estavam correndo. Avisos e penalidades chegam só para o piloto envolvido; cada batida
(ponto, direção, força e a resistência de todas as peças) e as peças arrancadas vão para todos:
o carro amassa no lugar certo em todas as telas e o diagrama/"DANO %" do HUD mostra o dano
calculado no servidor (`CarDamage.hit_applied` → evento `hit` → `CarDamage.remote_hit`). Esc abre o menu sem parar o jogo (os pedais soltam). **Votações** (protocolo
5: `{"cmd": "vote", "kind": "pause" | "resume" | "restart", "yes": bool}`): no menu (Esc)
qualquer jogador abre uma; a faixa no HUD mostra o tipo, os votos e o tempo, e os outros aceitam
com **Y / Touchpad** sem abrir o menu. Uma votação por vez, aberta 30 s; passa com a maioria dos
humanos ainda na corrida (2 de 2, 2 de 3, 3 de 4…; sozinho, 1).
  - **Pausar:** o servidor congela a física e a cena da corrida (relógio parado para todos, painel
    "PAUSADO" no HUD). Volta por outra votação (**Voltar**, com contagem de 3 s) ou sozinha depois
    de 3 min.
  - **Recomeçar:** a corrida é descartada sem resultado nem prêmio e o servidor larga outra com a
    mesma sala (os clientes recarregam o grid).

**Modo espectador** (`scripts/camera/spectator.gd`, F6 ou o botão na pausa; online, depois de
terminar ou abandonar; solo, a qualquer momento, com o piloto automático — um bot difícil, que faz
o pit obrigatório — dirigindo o seu carro até sair): o HUD do carro some e uma faixa embaixo mostra
a câmera e as teclas.
  - **Câmeras fixas** de TV geradas pela pista: uma na largada, alta, olhando o grid, e gruas
    altas logo atrás da barreira das curvas mais fechadas (no máximo 9, afastadas entre si). Em
    Mônaco ficam fora dos prédios e só onde enxergam o ápice e os trechos antes e depois dele por
    cima dos prédios e arquibancadas. Cada uma sabe que trecho da pista enxerga: segue o carro
    escolhido ali com zoom de TV (o carro fica do mesmo tamanho), um outro carro que esteja
    passando, ou mostra a curva vazia.
  - **TV automática:** corta para a câmera que enxerga o carro, a mais perto dele; nenhuma
    enxerga → helicóptero, alto e atrás do carro.
  - **Câmera livre:** WASD/setas, Q/E desce/sobe, Shift rápido, botão direito do mouse olha
    (controle: analógicos, LB/RB desce/sobe).
  - **Perseguição** de qualquer carro (a câmera normal da corrida).
  - Teclas: 1–9 câmera fixa · 0 TV automática · F livre · C perseguição · ← → carro · F6 sai. No
    controle: D-pad ← → carro, ↑ alterna TV/perseguição/livre, Y próxima câmera fixa, B sai. Fim: quando todos os
humanos terminam/abandonam (ou 150 s depois do primeiro); quem sai vira abandono. Depois que os
três primeiros recebem a bandeirada (`podium_done` no estado da corrida), quem ainda corre vê o
aviso "PODE SAIR DA CORRIDA" (e uma nota no menu de pausa): sair a partir daí conta como chegada
com as voltas que tinha (`RaceManager.leave_after_podium`: créditos inteiros, sem a metade do
abandono; sem o pit stop obrigatório continua desclassificado) e o carro sai da pista. O servidor paga e
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
godot --headless --path . -s res://tests/signal_repair_test.gd -- --offline  # seta dos retrovisores volta a acender depois do reparo (pit stop, queda na Sky Aerobase)
godot --headless --path . -s res://tests/podium_test.gd -- --offline  # pódio: as cópias dos três primeiros com as quatro rodas no lugar
godot --headless --path . -s res://tests/pit_collisions_test.gd -- --offline  # colisões no box: ligadas colidem; desligadas jogador e bot se atravessam nos boxes
godot --headless --path . -s res://tests/leave_after_podium_test.gd -- --offline  # online: aviso quando os 3 primeiros chegam; sair depois conta como chegada (créditos inteiros)
godot --path . -s res://tests/capture_crash.gd -- <pasta>    # screenshots de uma batida
godot --path . -s res://tests/capture_moods.gd -- <pasta>    # todos os horários × ambientes
godot --path . -s res://tests/capture_boost.gd -- <pasta>    # boost, marcas de pneu, sombra, fantasia
godot --path . -s res://tests/capture_trails.gd -- <pasta> [efeito ...]   # rastros de partículas: perseguição, lado, parado e à noite
godot --headless --path . -s res://tests/race_test.gd -- 3 9 3  # corrida de 3 voltas, 9 bots, dificuldade mista (+ monaco, suzuka, las_vegas, sky_aerobase ou atlantis_abyss no fim = nessa pista)
godot --headless --path . -s res://tests/sky_aerobase_test.gd # Sky Aerobase: traçado, bordas abertas com escape e vazio embaixo, cenário, quedas (jogador, bot, treino) voltando pelo box
godot --path . -s res://tests/sky_aerobase_shots.gd -- <pasta> [horário] [prefixo]  # screenshots da Sky Aerobase (curvas, túnel, borda do abismo, motores, base aérea)
godot --headless --path . -s res://tests/atlantis_abyss_test.gd # Atlantis Abyss: traçado abaixo/acima da água, Chicane do Tridente, barreiras em toda a volta, tubo cobrindo a pista submersa, cânion, montanhas, cenário, linha d'água (névoa) e carro parado nas rampas
godot --path . -s res://tests/atlantis_models_gallery.gd -- <pasta> [só,estas] --offline  # galeria da Atlantis Abyss: cada peça do fundo do mar sozinha, de perto, num leito plano longe da pista (bichos, polvo, peixes, peixes-voadores, águas-vivas, estátuas, os 22 tipos de coral e de vida presa, naufrágio, praça, templo redondo, fonte, estátuas no pedestal, tombada e enterradas, arco de pedra, pináculos, ânforas, âncora, baú, poça de vida, vulcão e chaminé, colunas, lanterna, torre, prédio e aqueduto)
godot --path . -s res://tests/atlantis_abyss_shots.gd -- <pasta> [horário] [prefixo] [só,estes]  # screenshots da Atlantis Abyss (tubo, cânion com pontes e fachadas, túnel de cristal, aqueduto, montanhas, cachoeiras largas e aquedutos sobre a pista, abismo, as duas chicanes e o tridente gigante, espelho d'água, vulcões, recifes, kelp, relíquias, cardumes, águas-vivas, bichos e baleias de perto, barcos)
godot --headless --path . -s res://tests/rainbow_raceway_test.gd # Rainbow Raceway: traçado com a espiral por baixo da Reta do Mirante, barreiras em toda a volta, vão livre, arcos e enfeites altos, nuvens da ponte, ilhas longe da plataforma, pelúcias atrás das barreiras, noite e carro parado em cima e embaixo da ponte
godot --path . -s res://tests/rainbow_raceway_shots.gd -- <pasta> [horário] [prefixo] [só,estes] --offline  # screenshots da Rainbow Raceway (Arco do Coração, túnel, espiral e torre, ponte, castelo, ilhas, ursinhos, mirante, presentes, vistas do alto)
godot --headless --path . -s res://tests/monaco_test.gd     # Mônaco: traçado, desnível, pisos, túnel coberto, cidade, porto, carro na rampa
godot --path . -s res://tests/monaco_shots.gd -- <pasta> [horário] [ambiente] [prefixo]  # screenshots de Mônaco (+ calçadas, navios, balões, dirigíveis e o céu visto da pista)
godot --headless --path . -s res://tests/suzuka_test.gd     # Suzuka: traçado, desnível, cruzamento (folga, projeção nos dois níveis), nada acima do asfalto, terreno, carro na ponte e embaixo dela
godot --path . -s res://tests/suzuka_shots.gd -- <pasta> [horário] [ambiente] [prefixo] [tomadas...]  # screenshots de Suzuka (ponte, corte, roda-gigante, curvas)
godot --headless --path . -s res://tests/track_bot_probe.gd -- suzuka 2 2 0 - 2700-2900  # bot sozinho: onde perde velocidade, sai da linha ou bate (trecho com registro detalhado)
godot --path . -s res://tests/capture_decals.gd -- <pasta>   # decalques no carro, SVG do jogador (pasta de teste) e a aba do Estúdio
godot --path . -s res://tests/capture_race.gd -- <pasta>     # menu, grid, HUD da corrida, boxes, mecânicos
godot --path . -s res://tests/capture_loading.gd -- <pasta>  # tela de carregamento (circuito e grid)
godot --path . -s res://tests/capture_ui.gd -- <pasta>       # HUD em cada paleta + garagem
godot --headless --path . -s res://tests/settings_test.gd   # configurações: salvar, remapear, gráficos, áudio, músicas
godot --headless --path . -s res://tests/race_menu_test.gd    # Tab só no treino, horário/ambiente da corrida, música menu x pista
godot --headless --path . -s res://tests/race_control_test.gd # bandeira amarela, safety car, ida ao box, penalidades
godot --headless --path . -s res://tests/last_lap_yellow_test.gd # amarela de 10 s só na última volta
godot --path . -s res://tests/capture_yellow.gd -- <pasta>   # instrução da amarela, safety car
godot --headless --path . -s res://tests/safety_car_test.gd # modelo do safety car: todo slot tem material, rodas no lugar
godot --path . -s res://tests/capture_safety_car.gd -- <pasta> [pista] [day|sunset|night]   # safety car de vários ângulos, nas duas fases do pisca
godot --headless --path . -s res://tests/ui_nav_test.gd     # menus pelo controle: foco, D-pad, A/B, LB/RB
godot --headless --path . -s res://tests/economy_test.gd    # economia: chances, sorteio, giro, repetidas, loja, estúdio, partículas, faíscas de frenagem, tickets, exclusivos, Sirene
godot --headless --path . -s res://tests/missions_test.gd   # missões diárias e da semana, conquistas pagas, títulos especiais e roleta do vencedor (sem rede)
godot --path . -s res://tests/capture_menu.gd -- <pasta>     # menu principal: início, jogar solo, estúdio, galeria, loja, giro
godot --headless --path . -s res://tests/track_carousel_test.gd # carrossel de pistas e abas Reais/Fantasia, peças por categoria na Galeria, Roleta Dragão
godot --path . -s res://tests/capture_cards.gd -- <pasta>    # capturas: carrossel, silhuetas e partículas no Estúdio/Galeria, giro da Dragão
godot --path . -s res://tests/part_silhouette_probe.gd -- <pasta> # folha com a silhueta de todas as peças
godot --path . -s res://tests/capture_settings.gd -- <pasta> # menu de configurações + monitor de desempenho
godot --headless --path . -s res://tests/compile_check.gd   # carrega todos os scripts (erros de compilação)
godot --headless --path . -s res://tests/ccd_probe.gd       # carro não "para do nada" em zebra/raspão a 320 km/h e não atravessa muros
godot --headless --path . -s res://tests/highspeed_probe.gd # pneus em alta velocidade: carga, aderência, boost, toque de direção, batente
godot --headless --path . -s res://tests/net_test.gd        # multiplayer de ponta a ponta, com votações de pausa/voltar/recomeçar (precisa do libSQL local; SPEEDORU_TEST_DB=local usa o banco em arquivo)
godot --headless --path . -s res://tests/track_cache_test.gd -- --server # pista do servidor copiada do cache: mesmos shapes de colisão e raios batendo nas barreiras
godot --headless --path . -s res://tests/equip_persist_test.gd -- --offline # equipamento (decalques, skin) salvo no banco: online, offline, carro antigo do aparelho, servidor reiniciado
godot --headless --path . -s res://tests/prediction_test.gd -- --offline [--net-lag=120] [--no-prediction] # predição: resposta ao acelerador, erro previsto x servidor, correções e saltos
godot --headless --path . -s res://tests/server_load_test.gd # servidor com duas salas: pistas geradas uma vez, a sala correndo não congela quando outra larga, 30 instantâneos/s, relógio da interpolação
godot --headless --path . -s res://tests/host_test.gd       # endereços IPv4/IPv6, banco local, hospedar (entrar por ::1, status, tirar, fechar, batimento), skins pela rede, salvos e histórico (+ -- <Speedoru.exe> = build exportada)
godot --path . -s res://tests/skin_test.gd -- [pasta]        # skin: planificação, importar/arquivos, ida e volta pelo molde, pintar um lado só muda ele (com janela)
godot --path . -s res://tests/capture_skin.gd -- <pasta> --offline # aba Skin, molde exportado, pintura simulada importada e o carro na garagem
godot --path . -s res://tests/capture_host.gd -- <pasta> [porta] --offline # aba SERVIDOR: salvos, histórico, hospedando com um amigo, log
godot --headless --path . -s res://tests/puppet_wheel_test.gd # rodas dos carros da rede: altura do servidor, esterço e giro, sem tremer
godot --headless --path . -s res://tests/updater_test.gd    # atualizador: versões e download/SHA-256 da última release (internet)
godot --headless --path . -s res://tests/chase_camera_test.gd # câmera de perseguição: frenagem, aceleração, curva, batida
godot --headless --path . -s res://tests/bot_yield_test.gd  # bots dão passagem ao jogador (fácil/médio), o difícil defende, amarela; ultrapassam com 90 m de reta e não desistem lado a lado
godot --headless --path . -s res://tests/bot_recover_test.gd # bot preso apontado para o muro sai sozinho (ré esterçando, volta à pista) e segue a corrida
godot --headless --path . -s res://tests/interp_test.gd -- --offline [--net-lag=ms] [--net-jitter=ms] # folga de interpolação adaptativa: pequena sem variação, sobe só o necessário com variação
godot --headless --path . -s res://tests/restart_jump_test.gd -- --offline [--net-lag=ms] # recomeçar acelerando: o carro não volta aos saltos para trás até a largada
godot --path . -s res://tests/frame_probe.gd -- [monza,monaco] [segundos] [puro] [--deep=race_manager,bot_driver] # com janela: onde vai o tempo de cada quadro numa corrida com 10 carros (GDScript por função, física, render, GPU)
godot --path . -s res://tests/online_restart_test.gd -- --offline [vezes] # corrida online com skins e bots, com janela: largada e recomeços seguidos sem o jogo travar
godot --path . -s res://tests/perf_probe.gd -- [monza,suzuka] [grupos[@0.75]] [sombra_grupos[@0.75]] [sombras] [hud] [pinheiros] # FPS, CPU/GPU, desenhos e triângulos em pontos da volta; custo de cada grupo da pista (e da sombra dele), das cascatas e da interface
godot --path . -s res://tests/shadow_atlas_probe.gd -- <pasta> [pistas] [16384,8192] # atlas da sombra do sol: GPU de cada tamanho (alternando) e capturas para comparar a imagem
godot --path . -s res://tests/cpu_probe.gd -- [pistas] [s] [adversários] [--trace] [--experimentos] # CPU numa corrida de verdade (física, lógica, desenho por quadro; scripts cronometrados; custo de efeitos, som, dano e IK dos rivais)
godot --path . -s res://tests/capture_far_model.gd -- <pasta> # modelo de longe dos carros: capturas com e sem, objetos e desenhos do quadro
godot --path . -s res://tests/net_frame_probe.gd -- --offline [pista] [s] [carros] [--net-lag=ms] [--net-jitter=ms] [--no-lead] # corrida online como o jogador vê: quadros, instantâneos, trancos e saltos visuais, correções, outro carro perto (onde aparece × servidor), colisões só no cliente, batidas no servidor
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
godot --path . -s res://tests/capture_spectator.gd -- <pasta> [monaco|monza]  # modo espectador: TV automática, câmeras fixas, livre, perseguição
godot --path . -s res://tests/capture_showcase.gd -- <pasta> [monza|monaco]  # balões de personagem vistos da pista, outdoors, murais e dirigível com imagem
godot --headless --path . -s res://tests/user_data_migration_test.gd # nome Speedoru e cópia da pasta antiga (F1 Gatcha), sem copiar por cima
godot --headless --path . -s res://tests/server_host_migration_test.gd -- --offline  # endereço antigo do servidor oficial (speedoru.padoru.org) vira play.speedoru.padoru.org no arquivo da conta
godot --headless --path . -s res://tests/parts_test.gd     # cada variante de peça monta no carro, com dano, DRS e retrovisores, e está numa roleta
godot --headless --path . -s res://tests/return_pit_test.gd # voltar aos boxes com confirmação, dano replicado na rede, contadores das ações
godot --headless --path . -s res://tests/offtrack_probe.gd  # fora da pista: velocidade perdida e aderência lateral por piso
godot --path . -s res://tests/capture_online.gd -- <pasta> <porta> --offline  # telas do multiplayer + corrida online
```

Os testes de multiplayer usam um libSQL local no Docker (`docker run -d -p 18080:8080
ghcr.io/tursodatabase/libsql-server`; outra URL com `SPEEDORU_TEST_DB`) e contas de teste próprias
(`user://test_net_*.cfg`, apagadas no fim). O `capture_online` precisa de um servidor rodando na
porta indicada.

Resultado de referência (880 kg): 0–100 km/h em 2,5 s · 0–200 em 5,0 s · 0–300 em 10,6 s · máx.
~334 km/h (sem DRS) · 334→0 km/h em 3,4 s / 122 m · 2,1 G lateral a 120 km/h e 3,1 G a 220 km/h.
