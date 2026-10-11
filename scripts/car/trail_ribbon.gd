class_name TrailRibbon
extends TrailRibbonCore
## Fita que segue um ponto (rastro). Dois modos:
##  * GROUND: faixa deitada no chão (marca de pneu), alinhada à normal do piso; os pontos ficam
##    até sumir por idade (`lifetime`) ou excesso (`max_points`). A malha só é refeita quando muda.
##  * BILLBOARD: fita virada para a câmera (rastro de luz), refeita todo quadro.
## Cada `stop()` encerra o traço atual; o próximo `add_point()` começa outro (sem ligar os dois).
## Fica em coordenadas de mundo (top_level). A malha é um ArrayMesh montado de uma vez com arrays
## compactos (dois vértices por ponto); sem pontos, não faz nada.
## Tudo roda no código nativo (TrailRibbonCore, native/src/fx.rs): mode, width, lifetime,
## max_points, min_spacing, color, fade_start, taper; add_point(), stop(), clear().

enum Mode { GROUND, BILLBOARD }
