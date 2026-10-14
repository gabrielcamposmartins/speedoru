"""Gera a Sky Aerobase (pista fantasia no céu) a partir de uma lista de trechos: retas e arcos,
cada um com a altura no fim. Não há dados reais: o traçado segue o que as pistas costumam ter
(reta longa com os boxes, frenagem forte, esses rápidos, grampo, descida estilo Mônaco, túnel,
chicane e uma reta oposta subindo).

Saída (assets/track/sky_aerobase/):
  sky_aerobase_centerline.csv  x, y (leste/norte, m), meia-largura direita/esquerda, elevação (m)
  sky_aerobase_raceline.csv    linha de corrida (curvatura mínima aproximada)

O circuito fecha sozinho: os comprimentos de duas retas (o fim da reta principal e a reta oposta)
são resolvidos para o fim cair no começo, e o ângulo da última curva completa a volta.

Rodar:  python tools/build_sky_aerobase.py [--debug pasta]   (a pasta recebe o desenho do traçado)
"""

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_monaco import raceline, resample, smooth_closed  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "track", "sky_aerobase")
CSV_STEP = 3.0
HALF = 7.0

# Trechos a partir da linha de largada (rumo inicial: leste). Cada um:
#   ("S", comprimento, z no fim, nome)            reta
#   ("C", ângulo°, raio, z no fim, nome)          arco (+ esquerda, - direita)
#   ("S?", None, z, nome) / ("C?", None, raio, z, nome)   resolvidos para fechar o circuito
# Meia-largura opcional como último item (padrão HALF).
TRACK = [
    ("S", 420.0, 40.0, "Reta dos Hangares"),
    ("C", 90.0, 42.0, 40.0, "Curva da Torre"),
    ("S", 378.0, 42.0, "Saída da Torre"),
    ("C", -42.0, 150.0, 44.0, "Esse do Vento (dir.)"),
    ("C", 42.0, 150.0, 47.0, "Esse do Vento (esq.)"),
    ("S", 340.0, 48.0, "Reta do Grampo"),
    ("C", 150.0, 18.0, 48.0, "Grampo do Hangar", 7.6),
    ("S", 110.0, 46.0, "Topo da Descida"),
    ("C", 20.0, 80.0, 43.0, "Mirage"),
    ("S", 300.0, 24.0, "Descida dos Jatos"),
    ("C", -70.0, 22.0, 21.0, "Curva do Portal", 7.4),
    ("S", 100.0, 15.0, "Entrada do Túnel"),
    ("C", -10.0, 1350.0, 10.0, "Túnel do Reator", 6.8),
    ("S", 130.0, 9.0, "Saída do Túnel"),
    ("C", 50.0, 22.0, 9.0, "Chicane do Abismo (esq.)", 6.8),
    ("S", 77.0, 9.0, "Meio da Chicane", 6.8),
    ("C", -50.0, 22.0, 9.0, "Chicane do Abismo (dir.)", 6.8),
    ("S?", None, 22.0, "Reta Oposta"),
    ("C", 75.0, 185.0, 33.0, "Curva do Céu"),
    ("S?", None, 39.0, "Reta da Plataforma"),
    ("C?", None, 36.0, 40.0, "Última Curva"),
    ("S", 560.0, 40.0, "Reta dos Hangares (fim)"),
]
DIRECTION = 1  # +1: anti-horário (soma +360°)

DEBUG = None


def heading_after(segs, upto):
    h = 0.0
    for seg in segs[:upto]:
        if seg[0] in ("C", "C?") and seg[1] is not None:
            h += seg[1]
    return h


def solve(track):
    """Fecha o circuito: ângulo da última curva e comprimentos das duas retas livres."""
    segs = [list(s) for s in track]
    free_c = [i for i, s in enumerate(segs) if s[0] == "C?"]
    free_s = [i for i, s in enumerate(segs) if s[0] == "S?"]
    assert len(free_c) == 1 and len(free_s) == 2
    known = sum(s[1] for s in segs if s[0] == "C")
    segs[free_c[0]][1] = 360.0 * DIRECTION - known
    # Posição final com as retas livres em zero; depois resolve L1*d1 + L2*d2 = -fim
    for i in free_s:
        segs[i][1] = 0.0
    end = trace(segs)[0][-1]
    d = []
    for i in free_s:
        h = math.radians(heading_after(segs, i))
        d.append((math.cos(h), math.sin(h)))
    m = np.array([[d[0][0], d[1][0]], [d[0][1], d[1][1]]])
    sol = np.linalg.solve(m, -np.asarray(end))
    for i, length in zip(free_s, sol):
        segs[i][1] = float(length)
    return segs


def trace(segs, step=1.0):
    """Pontos a cada `step` m, com altura alvo e meia-largura por ponto e o s do fim de cada trecho."""
    p = np.zeros(2)
    h = 0.0
    pts, half, ends = [], [], []
    s = 0.0
    for seg in segs:
        kind = seg[0].rstrip("?")
        if kind == "S":
            length = seg[1]
            w = seg[4] if len(seg) > 4 else HALF
            d = np.array([math.cos(math.radians(h)), math.sin(math.radians(h))])
            n = max(int(round(abs(length) / step)), 1)
            for k in range(n):
                pts.append(p + d * (length * k / n))
                half.append(w)
            p = p + d * length
            s += length
            ends.append((s, seg[2], seg[3]))
        else:
            ang, r = seg[1], seg[2]
            w = seg[5] if len(seg) > 5 else HALF
            length = abs(math.radians(ang)) * r
            n = max(int(round(length / step)), 1)
            sign = 1.0 if ang > 0 else -1.0
            hr = math.radians(h)
            center = p + sign * r * np.array([-math.sin(hr), math.cos(hr)])
            a0 = hr - sign * math.pi / 2.0
            for k in range(n):
                a = a0 + math.radians(ang) * k / n
                pts.append(center + r * np.array([math.cos(a), math.sin(a)]))
                half.append(w)
            a1 = a0 + math.radians(ang)
            p = center + r * np.array([math.cos(a1), math.sin(a1)])
            h += ang
            s += length
            ends.append((s, seg[3], seg[4]))
    return np.array(pts + [p]), np.array(half), ends


def elevation(ends, total, n):
    """Altura ao longo de s: interpolação monotônica (sem passar dos alvos) entre os fins dos trechos."""
    ks = np.array([0.0] + [e[0] for e in ends])
    kz = np.array([ends[-1][1]] + [e[1] for e in ends])
    s = np.arange(n) * total / n
    z = pchip(ks, kz, s)
    return smooth_closed(z, 18.0)


def pchip(x, y, xs):
    h = np.diff(x)
    dl = np.diff(y) / np.maximum(h, 1e-9)
    m = np.zeros_like(y)
    for i in range(1, len(y) - 1):
        if dl[i - 1] * dl[i] > 0:
            w1 = 2 * h[i] + h[i - 1]
            w2 = h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / dl[i - 1] + w2 / dl[i])
    idx = np.clip(np.searchsorted(x, xs, side="right") - 1, 0, len(h) - 1)
    t = (xs - x[idx]) / h[idx]
    h00 = 2 * t ** 3 - 3 * t ** 2 + 1
    h10 = t ** 3 - 2 * t ** 2 + t
    h01 = -2 * t ** 3 + 3 * t ** 2
    h11 = t ** 3 - t ** 2
    return h00 * y[idx] + h10 * h[idx] * m[idx] + h01 * y[idx + 1] + h11 * h[idx] * m[idx + 1]


def check(dense, elev, total):
    grade = np.gradient(elev) * 100.0
    vc = np.gradient(np.gradient(elev))
    print("comprimento %.0f m; altura %.1f a %.1f m" % (total, elev.min(), elev.max()))
    print("rampa máx %.1f%% / mín %.1f%%; curvatura vertical máx %.4f (raio %.0f m)" % (
        grade.max(), grade.min(), np.abs(vc).max(), 1.0 / max(np.abs(vc).max(), 1e-9)))
    # Trechos não vizinhos (mais de 150 m de pista entre eles) a menos de 45 m: cruzamento ou quase
    n = len(dense)
    worst = (1e9, 0, 0)
    for i in range(0, n, 4):
        d = np.hypot(*(dense - dense[i]).T)
        sep = np.abs(np.arange(n) - i)
        sep = np.minimum(sep, n - sep)
        d[sep < 150] = 1e9
        j = int(np.argmin(d))
        if d[j] < worst[0]:
            worst = (d[j], i, j)
    print("menor distância entre trechos não vizinhos: %.0f m (s %.0f e %.0f)" % worst)
    return worst[0]


def main():
    global DEBUG
    if "--debug" in sys.argv:
        DEBUG = sys.argv[sys.argv.index("--debug") + 1]
        os.makedirs(DEBUG, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    segs = solve(TRACK)
    pts, half_raw, ends = trace(segs)
    print("fechamento: %.3f m" % np.hypot(*pts[-1]))
    for seg, e in zip(segs, ends):
        desc = ("%.0f m" % seg[1]) if seg[0].startswith("S") else ("%+.0f° R%.0f" % (seg[1], seg[2]))
        print("  s %6.0f  z %5.1f  %-26s %s" % (e[0], e[1], e[2], desc))
    dense, total = resample(pts[:-1], 1.0)
    n = len(dense)
    # Meia-largura: a do trecho mais próximo (já em passos de ~1 m), suavizada
    src = np.linspace(0, len(half_raw) - 1, n).round().astype(int)
    half = smooth_closed(half_raw[src], 10.0)
    elev = elevation(ends, total, n)
    check(dense, elev, total)
    write_csv(dense, total, elev, half)
    line, lat = raceline(dense, half)
    write_raceline(line)
    print("linha de corrida: deslocamento %.1f a %.1f m" % (lat.min(), lat.max()))
    if DEBUG:
        draw(dense, ends, elev)


def write_csv(dense, total, elev, half):
    step = int(CSV_STEP)
    path = os.path.join(OUT, "sky_aerobase_centerline.csv")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Sky Aerobase - pista fantasia no céu: linha central (x leste, y norte, metros), larguras e elevação.\n")
        f.write("# Gerada por tools/build_sky_aerobase.py.\n")
        f.write("# x_m,y_m,w_tr_right_m,w_tr_left_m,z_m\n")
        for i in range(0, len(dense), step):
            x, y = dense[i]
            f.write("%.2f,%.2f,%.2f,%.2f,%.2f\n" % (x, y, half[i], half[i], elev[i]))
    print("linha central: %.0f m, %d pontos" % (total, len(dense) // step))


def write_raceline(line):
    path = os.path.join(OUT, "sky_aerobase_raceline.csv")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Sky Aerobase - linha de corrida (x leste, y norte, metros), curvatura mínima aproximada.\n")
        f.write("# x_m,y_m\n")
        for i in range(0, len(line), int(CSV_STEP)):
            f.write("%.2f,%.2f\n" % tuple(line[i]))


def draw(dense, ends, elev):
    from PIL import Image, ImageDraw
    lo = dense.min(axis=0) - 80
    hi = dense.max(axis=0) + 80
    scale = 1400.0 / max(hi - lo)
    size = ((hi - lo) * scale).astype(int)
    img = Image.new("RGB", (int(size[0]), int(size[1]) + 220), (18, 24, 40))
    d = ImageDraw.Draw(img)

    def px(p):
        return ((p[0] - lo[0]) * scale, (hi[1] - p[1]) * scale)

    zmin, zmax = elev.min(), elev.max()
    for i in range(len(dense)):
        t = (elev[i] - zmin) / max(zmax - zmin, 1e-6)
        c = (int(60 + 195 * t), int(140 + 60 * (1 - t)), int(255 - 120 * t))
        a, b = px(dense[i]), px(dense[(i + 1) % len(dense)])
        d.line([a, b], fill=c, width=6)
    d.ellipse([px(dense[0])[0] - 8, px(dense[0])[1] - 8, px(dense[0])[0] + 8, px(dense[0])[1] + 8], fill=(255, 255, 255))
    for s, z, name in ends:
        p = px(dense[int(s) % len(dense)])
        d.text((p[0] + 6, p[1] - 6), "%s (%.0f)" % (name, s), fill=(255, 230, 120))
    # Perfil de altura embaixo
    base = size[1] + 200
    for i in range(0, len(elev) - 1):
        x0 = i / len(elev) * size[0]
        x1 = (i + 1) / len(elev) * size[0]
        d.line([(x0, base - elev[i] * 3.5), (x1, base - elev[i + 1] * 3.5)], fill=(120, 220, 255), width=2)
    img.save(os.path.join(DEBUG, "sky_aerobase.png"))


if __name__ == "__main__":
    main()
