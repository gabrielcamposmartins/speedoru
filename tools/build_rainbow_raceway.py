"""Gera a Rainbow Raceway (pista fantasia fofa nas nuvens) a partir de uma lista de trechos: retas e
arcos, cada um com a altura no fim (mesmo método da Sky Aerobase). A pista flutua sobre nuvens entre
ilhas voadoras: larga sob o Arco do Coração, sobe até o Castelo de Algodão-Doce, atravessa o Túnel do
Arco-Íris, desce em espiral em volta da Torre de Algodão-Doce passando POR BAIXO dela mesma (a Ponte
do Arco-Íris), segue pelas cachoeiras e fecha com a chicane da Estrela e a Curva do Coração.

Como a espiral dá uma volta inteira a mais, o rumo soma 720° (DIRECTION = 2).

Saída (assets/track/rainbow_raceway/):
  rainbow_raceway_centerline.csv  x, y (leste/norte, m), meia-largura direita/esquerda, elevação (m)
  rainbow_raceway_raceline.csv    linha de corrida (curvatura mínima aproximada) e elevação: a altura
                                  separa os dois trechos no cruzamento (o RacingLine projeta com ela)

O circuito fecha sozinho: os comprimentos de duas retas são resolvidos para o fim cair no começo,
e o ângulo da última curva completa a volta. O script imprime o s de cada trecho (para o layout:
túnel, arquibancadas, ilhas), o cruzamento (com a folga de altura entre os dois níveis) e a menor
distância entre trechos não vizinhos fora do cruzamento.

Rodar:  python tools/build_rainbow_raceway.py [--debug pasta]   (a pasta recebe o desenho do traçado)
"""

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_monaco import raceline, resample, smooth_closed  # noqa: E402
from build_sky_aerobase import elevation, solve, trace  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "track", "rainbow_raceway")
CSV_STEP = 3.0
HALF = 7.0
# Folga mínima de altura (m) entre os dois níveis no cruzamento
CROSS_CLEARANCE = 13.0

# Trechos a partir da linha de largada (rumo inicial: leste). Cada um:
#   ("S", comprimento, z no fim, nome)            reta
#   ("C", ângulo°, raio, z no fim, nome)          arco (+ esquerda, - direita)
#   ("S?", None, z, nome) / ("C?", None, raio, z, nome)   resolvidos para fechar o circuito
# Meia-largura opcional como último item (padrão HALF).
TRACK = [
    ("S", 380.0, 20.0, "Reta do Arco-Íris"),
    ("C", 95.0, 48.0, 20.0, "Curva do Ursinho"),
    ("S", 230.0, 27.0, "Subida do Algodão"),
    ("C", -48.0, 170.0, 31.0, "Esse das Nuvens (dir.)"),
    ("C", 48.0, 170.0, 35.0, "Esse das Nuvens (esq.)"),
    ("S", 200.0, 40.0, "Reta do Castelo"),
    ("C", 165.0, 34.0, 41.0, "Grampo do Castelo", 7.6),
    ("S", 110.0, 40.0, "Ponte Levadiça"),
    ("C", -80.0, 110.0, 39.0, "Curva da Torre"),
    ("S", 80.0, 38.0, "Entrada do Túnel"),
    ("C", 14.0, 1100.0, 37.0, "Túnel do Arco-Íris", 6.8),
    ("S", 90.0, 37.0, "Saída do Túnel"),
    ("C", -24.0, 260.0, 37.0, "Esse das Bolhas (dir.)"),
    ("C", 24.0, 260.0, 37.0, "Esse das Bolhas (esq.)"),
    ("S?", None, 36.0, "Reta do Mirante"),
    ("C", 300.0, 66.0, 18.0, "Espiral do Algodão-Doce"),
    ("S", 270.0, 15.0, "Passagem do Arco-Íris"),
    ("C", 136.0, 40.0, 13.0, "Curva do Pirulito"),
    ("S", 90.0, 9.0, "Reta das Cachoeiras"),
    ("C", 52.0, 22.0, 8.0, "Chicane da Estrela (esq.)", 6.8),
    ("S", 55.0, 8.0, "Meio da Chicane", 6.8),
    ("C", -52.0, 22.0, 8.0, "Chicane da Estrela (dir.)", 6.8),
    ("S?", None, 12.0, "Reta dos Balões"),
    ("C", 50.0, 200.0, 16.0, "Curva do Coração"),
    ("S", 150.0, 19.0, "Reta dos Ursinhos"),
    ("C?", None, 50.0, 20.0, "Última Curva"),
    ("S", 440.0, 20.0, "Reta do Arco-Íris (fim)"),
]
DIRECTION = 2  # +2: anti-horário com uma volta a mais (a espiral)

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
    ok = True
    for seg in segs:
        # (o miolo de uma chicane é curto de propósito)
        if seg[0].startswith("S") and seg[1] < 40.0 and "Chicane" not in seg[3]:
            print("AVISO: reta '%s' curta demais (%.0f m)" % (seg[3], seg[1]))
            ok = False
    dense, total = resample(pts[:-1], 1.0)
    n = len(dense)
    src = np.linspace(0, len(half_raw) - 1, n).round().astype(int)
    half = smooth_closed(half_raw[src], 10.0)
    elev = elevation(ends, total, n)
    ok = check(dense, elev, total) and ok
    write_csv(dense, total, elev, half)
    line, lat = raceline(dense, half)
    write_raceline(line, elev)
    print("linha de corrida: deslocamento %.1f a %.1f m" % (lat.min(), lat.max()))
    if DEBUG:
        draw(dense, ends, elev)
    if not ok:
        print("ATENÇÃO: o traçado não passou nas conferências")


def crossings(dense, elev):
    """Cruzamentos (s1, s2, folga de altura, ângulo°) entre segmentos não vizinhos."""
    n = len(dense)
    out = []
    for i in range(n):
        a, b = dense[i], dense[(i + 1) % n]
        for j in range(i + 200, n):
            if n - (j - i) < 200:
                break
            c, d = dense[j], dense[(j + 1) % n]
            den = (b[0] - a[0]) * (d[1] - c[1]) - (b[1] - a[1]) * (d[0] - c[0])
            if abs(den) < 1e-9:
                continue
            t = ((c[0] - a[0]) * (d[1] - c[1]) - (c[1] - a[1]) * (d[0] - c[0])) / den
            u = ((c[0] - a[0]) * (b[1] - a[1]) - (c[1] - a[1]) * (b[0] - a[0])) / den
            if 0.0 <= t <= 1.0 and 0.0 <= u <= 1.0:
                ang = math.degrees(math.acos(min(1.0, abs(np.dot(b - a, d - c)) / (np.linalg.norm(b - a) * np.linalg.norm(d - c)))))
                out.append((i + t, j + u, abs(elev[i] - elev[j]), ang))
    return out


def check(dense, elev, total):
    ok = True
    grade = np.gradient(elev) * 100.0
    vc = np.gradient(np.gradient(elev))
    print("comprimento %.0f m; altura %.1f a %.1f m" % (total, elev.min(), elev.max()))
    print("rampa máx %.1f%% / mín %.1f%%; curvatura vertical máx %.4f (raio %.0f m)" % (
        grade.max(), grade.min(), np.abs(vc).max(), 1.0 / max(np.abs(vc).max(), 1e-9)))
    cr = crossings(dense, elev)
    n = len(dense)
    for s1, s2, dz, ang in cr:
        print("cruzamento: s %.0f e %.0f, folga de altura %.1f m, ângulo %.0f°" % (s1 * total / n, s2 * total / n, dz, ang))
        if dz < CROSS_CLEARANCE:
            print("AVISO: folga de altura pequena no cruzamento")
            ok = False
    if len(cr) != 1:
        print("AVISO: esperado exatamente 1 cruzamento (%d)" % len(cr))
        ok = False
    # Trechos não vizinhos (mais de 150 m de pista entre eles) a menos de 45 m, longe do cruzamento
    zone = np.zeros(n, dtype=bool)
    for s1, s2, _dz, _ang in cr:
        for s in (s1, s2):
            k = int(s)
            for d in range(-90, 91):
                zone[(k + d) % n] = True
    worst = (1e9, 0, 0)
    for i in range(0, n, 3):
        if zone[i]:
            continue
        d = np.hypot(*(dense - dense[i]).T)
        sep = np.abs(np.arange(n) - i)
        sep = np.minimum(sep, n - sep)
        d[sep < 150] = 1e9
        d[zone] = 1e9
        j = int(np.argmin(d))
        if d[j] < worst[0]:
            worst = (d[j], i, j)
    print("menor distância entre trechos não vizinhos (fora do cruzamento): %.0f m (s %.0f e %.0f)" % (
        worst[0], worst[1] * total / n, worst[2] * total / n))
    if worst[0] < 60.0:
        print("AVISO: trechos perto demais")
        ok = False
    return ok


def write_csv(dense, total, elev, half):
    step = int(CSV_STEP)
    path = os.path.join(OUT, "rainbow_raceway_centerline.csv")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Rainbow Raceway - pista fantasia fofa nas nuvens: linha central (x leste, y norte, metros),"
                " larguras e elevação.\n")
        f.write("# Gerada por tools/build_rainbow_raceway.py.\n")
        f.write("# x_m,y_m,w_tr_right_m,w_tr_left_m,z_m\n")
        for i in range(0, len(dense), step):
            x, y = dense[i]
            f.write("%.2f,%.2f,%.2f,%.2f,%.2f\n" % (x, y, half[i], half[i], elev[i]))
    print("linha central: %.0f m, %d pontos" % (total, len(dense) // step))


def write_raceline(line, elev):
    path = os.path.join(OUT, "rainbow_raceway_raceline.csv")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Rainbow Raceway - linha de corrida (x leste, y norte, metros), curvatura mínima aproximada, e elevação.\n")
        f.write("# x_m,y_m,z_m\n")
        for i in range(0, len(line), int(CSV_STEP)):
            f.write("%.2f,%.2f,%.2f\n" % (line[i][0], line[i][1], elev[i]))


def draw(dense, ends, elev):
    from PIL import Image, ImageDraw
    lo = dense.min(axis=0) - 80
    hi = dense.max(axis=0) + 80
    scale = 1400.0 / max(hi - lo)
    size = ((hi - lo) * scale).astype(int)
    img = Image.new("RGB", (int(size[0]), int(size[1]) + 240), (60, 40, 80))
    d = ImageDraw.Draw(img)

    def px(p):
        return ((p[0] - lo[0]) * scale, (hi[1] - p[1]) * scale)

    zmin, zmax = elev.min(), elev.max()
    for i in range(len(dense)):
        t = (elev[i] - zmin) / max(zmax - zmin, 1e-6)
        c = (int(255), int(120 + 100 * t), int(200 - 40 * t))
        a, b = px(dense[i]), px(dense[(i + 1) % len(dense)])
        d.line([a, b], fill=c, width=6)
    d.ellipse([px(dense[0])[0] - 8, px(dense[0])[1] - 8, px(dense[0])[0] + 8, px(dense[0])[1] + 8], fill=(255, 255, 255))
    for s, z, name in ends:
        p = px(dense[int(s) % len(dense)])
        d.text((p[0] + 6, p[1] - 6), "%s (%.0f)" % (name, s), fill=(255, 250, 200))
    base = size[1] + 220
    k = 4.0
    for i in range(0, len(elev) - 1):
        x0 = i / len(elev) * size[0]
        x1 = (i + 1) / len(elev) * size[0]
        d.line([(x0, base - elev[i] * k), (x1, base - elev[i + 1] * k)], fill=(255, 200, 240), width=2)
    img.save(os.path.join(DEBUG, "rainbow_raceway.png"))


if __name__ == "__main__":
    main()
