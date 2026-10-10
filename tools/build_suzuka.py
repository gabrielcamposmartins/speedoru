"""Gera a pista de Suzuka a partir do TUMFTM racetrack-database (tools/data/suzuka/).

Entrada (TUMFTM racetrack-database, LGPL-3.0, derivado do OpenStreetMap, ODbL):
  Suzuka.csv             linha central x, y (leste/norte, m) e meias-larguras direita/esquerda
  Suzuka_raceline.csv    linha de corrida de curvatura mínima x, y

Saída (assets/track/suzuka/):
  suzuka_centerline.csv  x, y, meia-largura direita/esquerda e elevação (m)
  suzuka_raceline.csv    x, y e elevação (m): a altura separa os dois trechos no cruzamento
  suzuka_relief.json     relevo de base do terreno (grade de 16 m, coordenadas do Godot): superfície
                         suave (Laplace) presa à altura da pista perto dela; o jogo soma os morros

Suzuka é um "8": a reta oposta (da Spoon à 130R) passa por cima do trecho entre a Degner 2 e o
grampo. A elevação (aproximada do circuito real, ~40 m de desnível) deixa a reta de cima 10 m acima
da de baixo no cruzamento.

Rodar:  python tools/build_suzuka.py
"""

import base64
import json
import math
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data", "suzuka")
OUT = os.path.join(HERE, "..", "assets", "track", "suzuka")

# Elevação (m) em pontos do traçado (s em m a partir do 1º ponto do CSV do TUMFTM, que fica na reta
# principal ~150 m depois da última curva)
ELEVATION = [
    (0.0, 17.0, "reta principal"),
    (300.0, 15.5, ""),
    (600.0, 13.0, "freada da 1"),
    (700.0, 10.0, "curva 1"),
    (850.0, 6.0, "curva 2"),
    (950.0, 4.0, "saída da 2 (ponto mais baixo)"),
    (1100.0, 5.0, "S"),
    (1300.0, 9.0, ""),
    (1500.0, 14.0, ""),
    (1700.0, 20.0, "Dunlop"),
    (1900.0, 27.0, ""),
    (2100.0, 34.0, ""),
    (2290.0, 38.5, "Degner 1 (ponto mais alto)"),
    (2450.0, 33.0, "Degner 2"),
    (2544.0, 26.5, "sob a ponte"),
    (2700.0, 21.5, ""),
    (2920.0, 20.0, "grampo"),
    (3150.0, 22.5, "200R"),
    (3400.0, 27.0, ""),
    (3650.0, 31.0, ""),
    (3900.0, 33.5, "Spoon"),
    (4100.0, 34.5, ""),
    (4450.0, 36.5, "reta oposta"),
    (4750.0, 38.0, ""),
    (4918.0, 38.0, "sobre a ponte"),
    (5050.0, 35.0, "130R"),
    (5250.0, 28.0, ""),
    (5420.0, 23.0, "chicane Casio"),
    (5600.0, 19.0, "última curva"),
]
# Folga mínima entre os dois níveis no cruzamento (m)
MIN_CLEARANCE = 9.5
# Relevo: célula (m), margem além da pista (m) e faixa presa à altura da pista (m do eixo)
RELIEF_CELL = 16.0
RELIEF_MARGIN = 1000.0
RELIEF_FIXED = 30.0


def load(name):
    return np.loadtxt(os.path.join(DATA, name), delimiter=",", comments="#")


def smooth_closed(a, sigma):
    """Suavização gaussiana circular (sigma em amostras)."""
    r = int(math.ceil(sigma * 3))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    pad = np.concatenate([a[-r:], a, a[:r]])
    return np.convolve(pad, k, mode="valid")


def cumulative(pts):
    seg = np.roll(pts, -1, axis=0) - pts
    lens = np.hypot(seg[:, 0], seg[:, 1])
    return np.concatenate([[0.0], np.cumsum(lens)])


def elevation(total):
    """Perfil a cada 1 m: linear entre os pontos (fechado) e suavizado (sigma 35 m)."""
    s = np.arange(int(math.ceil(total)))
    ks = np.array([e[0] for e in ELEVATION] + [ELEVATION[0][0] + total])
    kz = np.array([e[1] for e in ELEVATION] + [ELEVATION[0][1]])
    z = np.interp(s, ks, kz)
    return smooth_closed(z, 35.0)


def crossing(pts):
    """Pares de segmentos que se cruzam no plano: [(i, j, ponto)]."""
    n = len(pts)
    out = []
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        for j in range(i + 2, n):
            if i == 0 and j == n - 1:
                continue
            c, d = pts[j], pts[(j + 1) % n]
            r = b - a
            q = d - c
            den = r[0] * q[1] - r[1] * q[0]
            if abs(den) < 1e-9:
                continue
            t = ((c[0] - a[0]) * q[1] - (c[1] - a[1]) * q[0]) / den
            u = ((c[0] - a[0]) * r[1] - (c[1] - a[1]) * r[0]) / den
            if 0.0 <= t < 1.0 and 0.0 <= u < 1.0:
                out.append((i, t, j, u, a + r * t))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    center = load("Suzuka.csv")
    race = load("Suzuka_raceline.csv")
    pts = center[:, :2]
    cum = cumulative(pts)
    total = cum[-1]
    prof = elevation(total)

    def z_at(s):
        return float(np.interp(s % total, np.arange(len(prof)), prof))

    z = np.array([z_at(s) for s in cum[:-1]])
    for s, h, name in ELEVATION:
        if name:
            print("  %-30s s=%6.0f z=%5.1f (perfil %5.1f)" % (name, s, h, z_at(s)))
    grade = np.gradient(prof) * 100.0
    print("comprimento %.0f m, elevação %.1f a %.1f m, rampa %.1f%% a %.1f%%" % (
        total, prof.min(), prof.max(), grade.min(), grade.max()))
    for i, t, j, u, p in crossing(pts):
        si = cum[i] + t * (cum[i + 1] - cum[i])
        sj = cum[j] + u * (cum[j + 1] - cum[j])
        di = pts[(i + 1) % len(pts)] - pts[i]
        dj = pts[(j + 1) % len(pts)] - pts[j]
        ang = math.degrees(math.acos(abs(np.dot(di, dj)) / np.linalg.norm(di) / np.linalg.norm(dj)))
        gap = z_at(sj) - z_at(si)
        print("cruzamento em (%.0f, %.0f): s=%.0f (z %.1f) sob s=%.0f (z %.1f), folga %.1f m, ângulo %.0f°" % (
            p[0], p[1], si, z_at(si), sj, z_at(sj), gap, ang))
        assert abs(gap) >= MIN_CLEARANCE, "folga pequena no cruzamento"

    with open(os.path.join(OUT, "suzuka_centerline.csv"), "w", encoding="utf-8", newline="\n") as f:
        f.write("# Suzuka International Racing Course - linha central (x leste, y norte, metros), larguras e elevação.\n")
        f.write("# Fonte: TUMFTM racetrack-database (LGPL-3.0), derivado do OpenStreetMap (ODbL);\n")
        f.write("# elevação aproximada do circuito real (tools/build_suzuka.py).\n")
        f.write("# x_m,y_m,w_tr_right_m,w_tr_left_m,z_m\n")
        for k in range(len(pts)):
            f.write("%.3f,%.3f,%.3f,%.3f,%.2f\n" % (center[k, 0], center[k, 1], center[k, 2], center[k, 3], z[k]))

    # Linha de corrida: cada ponto pega a altura do ponto da linha central mais próximo, andando
    # junto com ela (no cruzamento os dois trechos ficam no mesmo lugar do plano)
    j = 0
    n = len(pts)
    with open(os.path.join(OUT, "suzuka_raceline.csv"), "w", encoding="utf-8", newline="\n") as f:
        f.write("# Suzuka International Racing Course - linha de corrida de curvatura mínima (x leste, y norte, metros) e elevação.\n")
        f.write("# Fonte: TUMFTM racetrack-database (LGPL-3.0), derivado do OpenStreetMap (ODbL).\n")
        f.write("# x_m,y_m,z_m\n")
        for k in range(len(race)):
            q = race[k]
            best = j
            best_d = np.inf
            for d in range(-3, 25):
                c = (j + d) % n
                dd = np.hypot(*(pts[c] - q))
                if dd < best_d:
                    best_d, best = dd, c
            j = best
            f.write("%.3f,%.3f,%.2f\n" % (q[0], q[1], z[best]))
    print("linha central %d pontos, linha de corrida %d pontos" % (n, len(race)))
    cross = []
    for i, t, j, u, p in crossing(pts):
        si, sj = (i, j) if z[i] < z[j] else (j, i)
        cross.append((si, sj, p))
    relief(pts, z, cross)


def relief(pts, z, cross):
    """Relevo de base: perto da pista (RELIEF_FIXED) a altura do ponto mais próximo (no cruzamento,
    o nível de cima, menos o corredor do trecho de baixo); no resto, Laplace (superfície mais suave
    que passa por essas alturas), com borda livre."""
    n = len(pts)
    # Coordenadas do Godot: x = leste, z = -norte
    gp = np.stack([pts[:, 0], -pts[:, 1]], axis=1)
    lo = gp.min(axis=0) - RELIEF_MARGIN
    hi = gp.max(axis=0) + RELIEF_MARGIN
    lo = np.floor(lo / RELIEF_CELL) * RELIEF_CELL
    w = int(math.ceil((hi[0] - lo[0]) / RELIEF_CELL)) + 1
    h = int(math.ceil((hi[1] - lo[1]) / RELIEF_CELL)) + 1
    xs = lo[0] + np.arange(w) * RELIEF_CELL
    zs = lo[1] + np.arange(h) * RELIEF_CELL
    gx, gz = np.meshgrid(xs, zs)
    cells = np.stack([gx.ravel(), gz.ravel()], axis=1)
    # Ponto mais próximo (em blocos para não estourar a memória)
    near_d = np.full(len(cells), np.inf)
    near_i = np.zeros(len(cells), int)
    for k0 in range(0, len(cells), 4000):
        c = cells[k0:k0 + 4000]
        d = np.hypot(c[:, None, 0] - gp[None, :, 0], c[:, None, 1] - gp[None, :, 1])
        near_i[k0:k0 + 4000] = d.argmin(axis=1)
        near_d[k0:k0 + 4000] = d.min(axis=1)
    val = z[near_i].copy()
    fixed = near_d < RELIEF_FIXED
    # Cruzamento: em volta dele vale o nível de cima, menos no corredor do trecho de baixo
    for ilo, ihi, cp in cross:
        cg = np.array([cp[0], -cp[1]])
        r = np.hypot(cells[:, 0] - cg[0], cells[:, 1] - cg[1])
        zone = r < 90.0
        win_lo = [(ilo + d) % n for d in range(-30, 31)]
        win_hi = [(ihi + d) % n for d in range(-30, 31)]
        for k in np.nonzero(zone)[0]:
            c = cells[k]
            dl = np.hypot(gp[win_lo, 0] - c[0], gp[win_lo, 1] - c[1])
            dh = np.hypot(gp[win_hi, 0] - c[0], gp[win_hi, 1] - c[1])
            if dl.min() < 25.0:
                val[k] = z[win_lo[int(dl.argmin())]]
            else:
                t = 1.0 - np.clip((r[k] - 45.0) / 45.0, 0.0, 1.0)
                val[k] = val[k] + (z[win_hi[int(dh.argmin())]] - val[k]) * t
    grid = val.reshape(h, w)
    fix = fixed.reshape(h, w)
    # Chute inicial: média ponderada pela distância (converge bem mais rápido)
    out = grid.copy()
    free = ~fix
    for it in range(6000):
        p = np.pad(out, 1, mode="edge")
        avg = 0.25 * (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:])
        out = np.where(free, out + 1.9 * (avg - out) * 0.5, grid)
    print("relevo: %dx%d células de %.0f m, %.1f a %.1f m" % (w, h, RELIEF_CELL, out.min(), out.max()))
    data = {
        "origin": [float(lo[0]), float(lo[1])],
        "cell": RELIEF_CELL,
        "size": [w, h],
        "h": base64.b64encode(out.astype(np.float32).tobytes()).decode("ascii"),
    }
    with open(os.path.join(OUT, "suzuka_relief.json"), "w", encoding="utf-8", newline=chr(10)) as f:
        json.dump(data, f)


if __name__ == "__main__":
    main()
