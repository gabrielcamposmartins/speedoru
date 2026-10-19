"""Gera a Atlantis Abyss (pista fantasia no fundo do mar, Atlântida) a partir de uma lista de trechos:
retas e arcos, cada um com a altura no fim (mesmo método da Sky Aerobase). A pista corre entre as
ruínas, passa por um túnel de cristal, sobe por um aqueduto até SAIR DA ÁGUA (Portão de Poseidon,
acima de WATER_LEVEL), mergulha de volta e cruza o abismo sobre arcos.

Saída (assets/track/atlantis_abyss/):
  atlantis_abyss_centerline.csv  x, y (leste/norte, m), meia-largura direita/esquerda, elevação (m)
  atlantis_abyss_raceline.csv    linha de corrida (curvatura mínima aproximada)

O circuito fecha sozinho: os comprimentos de duas retas são resolvidos para o fim cair no começo,
e o ângulo da última curva completa a volta. O script imprime o s de cada trecho (para o layout:
túnel, fossas, arquibancadas) e quanto da volta fica fora d'água.

Rodar:  python tools/build_atlantis_abyss.py [--debug pasta]   (a pasta recebe o desenho do traçado)
"""

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_monaco import raceline, resample, smooth_closed  # noqa: E402
from build_sky_aerobase import check, elevation, solve, trace  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "track", "atlantis_abyss")
CSV_STEP = 3.0
HALF = 7.0
# Linha d'água (m, mesma referência de z): igual a TrackLayout.water_level no .tres
WATER_LEVEL = 28.0

# Trechos a partir da linha de largada (rumo inicial: leste). Cada um:
#   ("S", comprimento, z no fim, nome)            reta
#   ("C", ângulo°, raio, z no fim, nome)          arco (+ esquerda, - direita)
#   ("S?", None, z, nome) / ("C?", None, raio, z, nome)   resolvidos para fechar o circuito
# Meia-largura opcional como último item (padrão HALF).
TRACK = [
    ("S", 450.0, 0.0, "Reta do Anfiteatro"),
    ("C", 95.0, 45.0, 0.0, "Curva do Templo"),
    ("S", 250.0, 1.0, "Avenida das Colunas"),
    ("C", -60.0, 110.0, 2.0, "Curva do Polvo"),
    ("S", 110.0, 3.0, "Entrada do Túnel"),
    ("C", 14.0, 1500.0, 8.0, "Túnel de Cristal", 6.8),
    ("S", 60.0, 10.0, "Saída do Túnel"),
    ("C", 120.0, 28.0, 10.0, "Grampo da Âncora", 7.6),
    ("S", 520.0, 34.0, "Subida do Aqueduto"),
    ("C", -40.0, 160.0, 34.0, "Portão de Poseidon"),
    ("S", 100.0, 34.0, "Ponte das Cachoeiras"),
    ("C", 35.0, 140.0, 34.0, "Curva do Arco-Íris"),
    ("S", 420.0, 10.0, "Mergulho"),
    ("C", 70.0, 24.0, 8.0, "Curva da Tartaruga", 7.4),
    ("S", 60.0, 7.0, "Jardim de Corais"),
    ("C", 50.0, 22.0, 6.0, "Chicane dos Corais (esq.)", 6.8),
    ("S", 70.0, 6.0, "Meio da Chicane", 6.8),
    ("C", -50.0, 22.0, 5.0, "Chicane dos Corais (dir.)", 6.8),
    ("S", 220.0, 3.0, "Reta do Abismo"),
    ("C", -22.0, 380.0, 2.0, "Esse do Abismo (dir.)"),
    ("C", 22.0, 380.0, 2.0, "Esse do Abismo (esq.)"),
    ("S?", None, 2.0, "Ponte do Abismo"),
    ("C", 70.0, 190.0, 1.0, "Curva da Baleia"),
    ("S?", None, 0.0, "Reta dos Tritões"),
    ("C?", None, 40.0, 0.0, "Última Curva"),
    ("S", 520.0, 0.0, "Reta do Anfiteatro (fim)"),
]
DIRECTION = 1  # +1: anti-horário (soma +360°)

DEBUG = None


def main():
    global DEBUG
    if "--debug" in sys.argv:
        DEBUG = sys.argv[sys.argv.index("--debug") + 1]
        os.makedirs(DEBUG, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    segs = solve(TRACK, DIRECTION)
    pts, half_raw, ends = trace(segs, default_half=HALF)
    print("fechamento: %.3f m" % np.hypot(*pts[-1]))
    prev = 0.0
    for seg, e in zip(segs, ends):
        desc = ("%.0f m" % seg[1]) if seg[0].startswith("S") else ("%+.0f° R%.0f" % (seg[1], seg[2]))
        print("  s %6.0f-%6.0f  z %5.1f  %-28s %s" % (prev, e[0], e[1], e[2], desc))
        prev = e[0]
    for seg in segs:
        if seg[0].startswith("S") and seg[1] < 40.0:
            print("AVISO: reta '%s' curta demais (%.0f m)" % (seg[3], seg[1]))
    dense, total = resample(pts[:-1], 1.0)
    n = len(dense)
    # Meia-largura: a do trecho mais próximo (já em passos de ~1 m), suavizada
    src = np.linspace(0, len(half_raw) - 1, n).round().astype(int)
    half = smooth_closed(half_raw[src], 10.0)
    elev = elevation(ends, total, n)
    check(dense, elev, total)
    above = elev > WATER_LEVEL
    print("fora d'água: %.0f m (z > %.0f m); trechos:" % (above.sum() * total / n, WATER_LEVEL))
    for s0, s1 in spans(above, total):
        print("  s %.0f a %.0f" % (s0, s1))
    write_csv(dense, total, elev, half)
    line, lat = raceline(dense, half)
    write_raceline(line)
    print("linha de corrida: deslocamento %.1f a %.1f m" % (lat.min(), lat.max()))
    if DEBUG:
        draw(dense, ends, elev, total)


def spans(mask, total):
    """Trechos contínuos (s inicial, s final) onde mask é verdadeiro, numa volta fechada."""
    n = len(mask)
    out = []
    i = 0
    while i < n:
        if mask[i] and (i == 0 or not mask[i - 1]):
            j = i
            while j + 1 < n and mask[j + 1]:
                j += 1
            out.append((i * total / n, (j + 1) * total / n))
            i = j + 1
        else:
            i += 1
    return out


def write_csv(dense, total, elev, half):
    step = int(CSV_STEP)
    path = os.path.join(OUT, "atlantis_abyss_centerline.csv")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Atlantis Abyss - pista fantasia no fundo do mar: linha central (x leste, y norte, metros),"
                " larguras e elevação.\n")
        f.write("# Gerada por tools/build_atlantis_abyss.py.\n")
        f.write("# x_m,y_m,w_tr_right_m,w_tr_left_m,z_m\n")
        for i in range(0, len(dense), step):
            x, y = dense[i]
            f.write("%.2f,%.2f,%.2f,%.2f,%.2f\n" % (x, y, half[i], half[i], elev[i]))
    print("linha central: %.0f m, %d pontos" % (total, len(dense) // step))


def write_raceline(line):
    path = os.path.join(OUT, "atlantis_abyss_raceline.csv")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Atlantis Abyss - linha de corrida (x leste, y norte, metros), curvatura mínima aproximada.\n")
        f.write("# x_m,y_m\n")
        for i in range(0, len(line), int(CSV_STEP)):
            f.write("%.2f,%.2f\n" % tuple(line[i]))


def draw(dense, ends, elev, total):
    from PIL import Image, ImageDraw
    lo = dense.min(axis=0) - 80
    hi = dense.max(axis=0) + 80
    scale = 1400.0 / max(hi - lo)
    size = ((hi - lo) * scale).astype(int)
    img = Image.new("RGB", (int(size[0]), int(size[1]) + 260), (8, 22, 40))
    d = ImageDraw.Draw(img)

    def px(p):
        return ((p[0] - lo[0]) * scale, (hi[1] - p[1]) * scale)

    for i in range(len(dense)):
        c = (255, 214, 90) if elev[i] > WATER_LEVEL else (60, 200, 255)
        a, b = px(dense[i]), px(dense[(i + 1) % len(dense)])
        d.line([a, b], fill=c, width=6)
    d.ellipse([px(dense[0])[0] - 8, px(dense[0])[1] - 8, px(dense[0])[0] + 8, px(dense[0])[1] + 8], fill=(255, 255, 255))
    for s, z, name in ends:
        p = px(dense[int(s) % len(dense)])
        d.text((p[0] + 6, p[1] - 6), "%s (%.0f)" % (name, s), fill=(255, 230, 120))
    # Perfil de altura embaixo, com a linha d'água
    base = size[1] + 230
    k = 4.5
    d.line([(0, base - WATER_LEVEL * k), (size[0], base - WATER_LEVEL * k)], fill=(40, 120, 200), width=1)
    for i in range(0, len(elev) - 1):
        x0 = i / len(elev) * size[0]
        x1 = (i + 1) / len(elev) * size[0]
        c = (255, 214, 90) if elev[i] > WATER_LEVEL else (120, 220, 255)
        d.line([(x0, base - elev[i] * k), (x1, base - elev[i + 1] * k)], fill=c, width=2)
    img.save(os.path.join(DEBUG, "atlantis_abyss.png"))


if __name__ == "__main__":
    main()
