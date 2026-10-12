"""Gera a pista de Las Vegas (Las Vegas Strip Circuit) a partir dos dados do OpenStreetMap (ODbL)
em tools/data/las_vegas/ (baixados da Overpass API, © colaboradores do OpenStreetMap):

  circuit.json    relação 16696508 "Las Vegas Strip Circuit" (vias na ordem da corrida, largada,
                  faixa dos boxes)
  buildings.json  prédios                     parts.json    partes de prédio (torres com altura)
  roads.json      ruas                        high_roller.json  a roda-gigante High Roller
  water.json      lagos, piscinas, a Fonte do Bellagio
  green.json      parques, jardins, campo de golfe
  trees.json      árvores mapeadas

Saída (assets/track/las_vegas/), no mesmo formato da cidade de Mônaco (TrackCity):
  las_vegas_centerline.csv  x, y (leste/norte, m), meias-larguras, elevação (m)
  las_vegas_raceline.csv    linha de corrida (curvatura mínima aproximada)
  las_vegas_city.json       terreno (plano), prédios (os do OSM e os inventados nos terrenos vazios,
                            com o tipo de letreiro de neon), ruas, piscinas, parques, árvores e os
                            marcos (Sphere, roda-gigante High Roller, Torre Eiffel do Paris, fonte do
                            Bellagio)

Diferenças para Mônaco: o deserto é plano (sem encosta, mar, cais, túnel nem barcos) e a corrida
é à noite na vida real (o jogo escolhe o horário).
Coordenadas: origem em (lat 36.1167, lon -115.1666), x = leste, y = norte, em metros.

Rodar:  python tools/build_las_vegas.py [--debug pasta]   (a pasta recebe imagens de conferência)
"""

import base64
import json
import math
import os
import sys
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data", "las_vegas")
OUT = os.path.join(HERE, "..", "assets", "track", "las_vegas")
LAT0, LON0 = 36.1167, -115.1666
KX = 111320.0 * math.cos(math.radians(LAT0))
KY = 110540.0
RELATION = 16696508

# Área do terreno (m): o circuito e ~450 m em volta
AREA = (-1050.0, -1430.0, 1050.0, 1440.0)  # xmin, ymin, xmax, ymax
CELL = 6.0
# Altura da pista (o deserto é plano; o chão fica um pouco abaixo dela)
ROAD_Z = 0.6
GROUND_Z = 0.0
CSV_STEP = 3.0

DEBUG = None


def xy(lat, lon):
    return ((lon - LON0) * KX, (lat - LAT0) * KY)


def load(name):
    with open(os.path.join(DATA, name), encoding="utf-8") as f:
        return json.load(f)


def ways_of(name):
    """[(tags, [(x, y)...], id)] de vias e de membros externos de relações."""
    out = []
    for e in load(name)["elements"]:
        if e["type"] == "way" and "geometry" in e:
            out.append((e.get("tags", {}), [xy(p["lat"], p["lon"]) for p in e["geometry"]], e["id"]))
        elif e["type"] == "relation":
            for m in e.get("members", []):
                if "geometry" in m and m.get("role", "outer") in ("outer", ""):
                    out.append((dict(e.get("tags", {})), [xy(p["lat"], p["lon"]) for p in m["geometry"] if p], e["id"]))
    return out


# ---------------------------------------------------------------------------
# Linha central
# ---------------------------------------------------------------------------
def resample(pts, step):
    """Polilinha fechada reamostrada com passo constante."""
    pts = np.asarray(pts, float)
    seg = np.roll(pts, -1, axis=0) - pts
    lens = np.hypot(seg[:, 0], seg[:, 1])
    cum = np.concatenate([[0.0], np.cumsum(lens)])
    total = cum[-1]
    n = int(round(total / step))
    t = np.linspace(0.0, total, n, endpoint=False)
    k = np.clip(np.searchsorted(cum, t, side="right") - 1, 0, len(pts) - 1)
    f = ((t - cum[k]) / np.maximum(lens[k], 1e-9))[:, None]
    return pts[k] + seg[k] * f, total


def smooth_closed(a, sigma):
    a = np.asarray(a, float)
    r = int(sigma * 3)
    w = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    w /= w.sum()
    if a.ndim == 1:
        return np.convolve(np.concatenate([a[-r:], a, a[:r]]), w, mode="valid")
    return np.stack([smooth_closed(a[:, k], sigma) for k in range(a.shape[1])], axis=1)


def relation():
    return load("circuit.json")["elements"][0]


def centerline():
    """Vias da relação na ordem da corrida (forward/backward), sem a faixa dos boxes e a variante."""
    rel = relation()
    pts = []
    start = None
    for m in rel["members"]:
        if m["type"] == "node" and m.get("role") == "start":
            start = xy(m["lat"], m["lon"])
        if m["type"] != "way" or m.get("role") not in ("forward", "backward"):
            continue
        g = [xy(p["lat"], p["lon"]) for p in m["geometry"]]
        if m["role"] == "backward":
            g = g[::-1]
        if pts and math.dist(pts[-1], g[0]) < 0.5:
            g = g[1:]
        pts.extend(g)
    if math.dist(pts[0], pts[-1]) < 0.5:
        pts = pts[:-1]
    # Remove "bicos" (ida e volta do mapeamento)
    changed = True
    while changed:
        changed = False
        for i in range(len(pts)):
            a, b, c = np.array(pts[i - 2]), np.array(pts[i - 1]), np.array(pts[i])
            u, v = b - a, c - b
            if np.linalg.norm(u) > 1e-6 and np.linalg.norm(v) > 1e-6 and np.dot(u, v) < -0.3 * np.linalg.norm(u) * np.linalg.norm(v):
                del pts[i - 1]
                changed = True
                break
    dense, total = resample(pts, 1.0)
    dense = smooth_closed(dense, 3.0)
    dense, total = resample(dense, 1.0)
    dense, total = round_corners(dense, R_MIN)
    i0 = int(np.argmin(np.hypot(dense[:, 0] - start[0], dense[:, 1] - start[1])))
    dense = np.roll(dense, -i0, axis=0)
    return dense, total


## Raio mínimo do eixo nas esquinas (m): o mapeamento faz cantos vivos de 90°; o eixo da rua larga
## faz a curva com este raio (a borda de dentro fica com ~R_MIN - meia-largura).
R_MIN = 17.0


def round_corners(dense, r_min):
    """Arredonda só os cantos com raio menor que r_min: suavização local (Laplace) nos pontos
    apertados e vizinhos, repetida até todos passarem do raio (o resto do traçado não muda)."""
    for it in range(600):
        kc = np.abs(curvature(dense, 3))
        tight = kc > 1.0 / r_min
        if not tight.any():
            break
        grow = tight.copy()
        for d in range(1, 9):
            grow |= np.roll(tight, d) | np.roll(tight, -d)
        avg = (np.roll(dense, 1, axis=0) + np.roll(dense, -1, axis=0)) * 0.5
        dense = np.where(grow[:, None], dense + (avg - dense) * 0.5, dense)
        if it % 10 == 9:
            dense, _ = resample(dense, 1.0)
    dense, total = resample(dense, 1.0)
    kc = np.abs(curvature(dense, 3))
    print("esquinas arredondadas: raio mínimo %.1f m" % (1.0 / max(kc.max(), 1e-6)))
    return dense, total


def frames(dense):
    t = np.roll(dense, -1, axis=0) - np.roll(dense, 1, axis=0)
    t /= np.hypot(t[:, 0], t[:, 1])[:, None]
    left = np.stack([-t[:, 1], t[:, 0]], axis=1)
    return t, left


def project_pt(dense, left, x, y):
    d = np.hypot(dense[:, 0] - x, dense[:, 1] - y)
    k = int(np.argmin(d))
    lat = (x - dense[k, 0]) * left[k, 0] + (y - dense[k, 1]) * left[k, 1]
    return k, lat, float(d[k])


def curvature(dense, half_window=6):
    t, _ = frames(dense)
    ang = np.arctan2(t[:, 1], t[:, 0])
    return smooth_closed(np.angle(np.exp(1j * (np.roll(ang, -half_window) - np.roll(ang, half_window)))) / (2.0 * half_window), 2.0)


def pit_info(dense, total):
    """Entrada, saída e lado da faixa dos boxes (via pit_lane da relação), em s relativo à largada."""
    _, left = frames(dense)
    pl = [m for m in relation()["members"] if m.get("role") == "pit_lane"][0]
    g = np.array([xy(p["lat"], p["lon"]) for p in pl["geometry"]])
    s_in, _, _ = project_pt(dense, left, *g[0])
    s_out, _, _ = project_pt(dense, left, *g[-1])
    lats = [project_pt(dense, left, *p)[1] for p in g[len(g) // 4: 3 * len(g) // 4]]
    side = 1 if np.median(lats) > 0 else -1
    rel = lambda s: (s + total * 0.5) % total - total * 0.5
    return rel(s_in), rel(s_out), side, float(np.median(np.abs(lats)))


def widths(dense, total):
    """Meia-largura: a Strip e as avenidas são largas; nas curvas fechadas um pouco mais."""
    n = len(dense)
    kc = np.abs(curvature(dense))
    half = np.full(n, 6.6)
    tight = kc > 1.0 / 35.0
    half[tight] = 7.4
    return smooth_closed(half, 14.0)


def write_csv(dense, total, half):
    step = int(CSV_STEP)
    path = os.path.join(OUT, "las_vegas_centerline.csv")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Las Vegas Strip Circuit - linha central (x leste, y norte, metros), larguras e elevação.\n")
        f.write("# Fonte: OpenStreetMap (ODbL), relação 16696508; larguras ajustadas à mão (o deserto é plano).\n")
        f.write("# x_m,y_m,w_tr_right_m,w_tr_left_m,z_m\n")
        for i in range(0, len(dense), step):
            x, y = dense[i]
            f.write("%.2f,%.2f,%.2f,%.2f,%.2f\n" % (x, y, half[i], half[i], ROAD_Z))
    print("linha central: %.0f m, %d pontos" % (total, len(dense) // step))


def raceline(dense, half, margin=2.0):
    """Linha de corrida de curvatura mínima (descida de gradiente biharmônica, presa à largura útil)."""
    n = len(dense)
    t, left = frames(dense)
    lim = np.maximum(half - margin, 0.3)
    kc = curvature(dense, 3)
    r_min = 11.5
    room = np.where(np.abs(kc) > 1e-4, 1.0 / np.maximum(np.abs(kc), 1e-4) - r_min, 99.0)
    hi = np.where(kc > 0, np.minimum(lim, room), lim)
    lo = np.where(kc < 0, -np.minimum(lim, room), -lim)
    win = 20
    hi = np.min(np.stack([np.roll(hi, d) for d in range(-win, win + 1)]), axis=0)
    lo = np.max(np.stack([np.roll(lo, d) for d in range(-win, win + 1)]), axis=0)
    lo = np.minimum(lo, hi)
    lat = np.clip(np.zeros(n), lo, hi)
    for k, iters in ((16, 3000), (8, 3000), (4, 3000)):
        for _ in range(iters):
            p = dense + left * lat[:, None]
            lap = np.roll(p, k, axis=0) - 2.0 * p + np.roll(p, -k, axis=0)
            bih = np.roll(lap, k, axis=0) - 2.0 * lap + np.roll(lap, -k, axis=0)
            step = -np.einsum("ij,ij->i", bih, left) * 0.05
            lat = np.clip(lat + step, lo, hi)
    return dense + left * lat[:, None], lat


def write_raceline(line):
    path = os.path.join(OUT, "las_vegas_raceline.csv")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Las Vegas Strip Circuit - linha de corrida (x leste, y norte, metros), curvatura mínima aproximada.\n")
        f.write("# x_m,y_m\n")
        for i in range(0, len(line), int(CSV_STEP)):
            f.write("%.2f,%.2f\n" % tuple(line[i]))


def corners(dense, total):
    """Curvas (para conferir e posicionar arquibancadas): trechos com raio < 80 m."""
    kc = curvature(dense)
    out = []
    inside = False
    for i in range(len(dense)):
        tight = abs(kc[i]) > 1.0 / 80.0
        if tight and not inside:
            a = i
            inside = True
        elif not tight and inside:
            inside = False
            seg = kc[a:i]
            j = a + int(np.argmax(np.abs(seg)))
            out.append((a, i, j, 1.0 / max(abs(kc[j]), 1e-6), "esq" if kc[j] > 0 else "dir"))
    return out


def main_track():
    os.makedirs(OUT, exist_ok=True)
    dense, total = centerline()
    print("volta: %.0f m (oficial 6201 m)" % total)
    pin, pout, pside, plat = pit_info(dense, total)
    print("boxes: entrada s=%.0f, saída s=%.0f, lado %s, a %.0f m do eixo" % (pin, pout, "esquerda" if pside > 0 else "direita", plat))
    for a, b, j, r, d in corners(dense, total):
        print("  curva s=%5d..%5d  ápice %5d  raio %5.0f m  %s" % (a, b, j, r, d))
    half = widths(dense, total)
    write_csv(dense, total, half)
    line, lat = raceline(dense, half)
    write_raceline(line)
    print("linha de corrida: deslocamento %.1f a %.1f m" % (lat.min(), lat.max()))
    return dense, total, half, (pin, pout, pside)


# ---------------------------------------------------------------------------
# Cidade
# ---------------------------------------------------------------------------
# Boxes no jogo (resources/tracks/las_vegas_layout.tres): a faixa real sai depois da curva 1; no jogo
# ela acompanha a reta e termina antes dela. Lado: +1 esquerda, -1 direita.
PIT = dict(entry=-230.0, exit=150.0, side=1, lane=3.0 + 12.0, center=-40.0, building=140.0, depth=20.0)
# Áreas planas além da barreira (arquibancadas): (s inicial, s final, lado, profundidade). Manter igual
# às arquibancadas do layout.
FLAT_ZONES = [
    (-190.0, -50.0, -1, 26.0),   # Arquibancada principal (em frente aos boxes)
    (170.0, 270.0, -1, 24.0),    # Curva 1
    (900.0, 1040.0, -1, 22.0),   # Reta da Koval
    (2440.0, 2500.0, 1, 22.0),   # Chicane da Sphere
    (5000.0, 5080.0, -1, 24.0),  # Curva da Harmon
]
BARRIER = 1.6  # distância padrão da barreira (las_vegas_layout.tres)
# Barreiras mais afastadas (áreas de escape): (s inicial, s final, lado, distância; lado 0 = os dois)
BARRIER_ZONES = [
    (190.0, 280.0, -1, 6.0),     # Curva 1
    (430.0, 510.0, 1, 4.0),      # Curva 5
    (2460.0, 2525.0, 0, 4.0),    # Chicane da Sphere
    (3110.0, 3160.0, -1, 5.0),   # Entrada da Strip
    (5035.0, 5075.0, -1, 5.0),   # Curva da Harmon
]

# Fachadas de Las Vegas: areia, dourado, branco, terracota, vidro azulado e cinza (as 14 primeiras
# são as dos prédios do OSM; as seguintes, só dos prédios de preenchimento)
FACADES = ["f3e7d0", "e8d4b0", "d9c29a", "c8a46e", "f5f1e8", "b8c6d1", "9fb3c8", "d6b98c",
           "e9dcc6", "c97b5a", "8fa3b8", "f0e2c0", "cdbfa8", "a9b8c6",
           # Torres de vidro dourado e bronze, branco de hotel, vidro azul, rosa-salmão, concreto
           "d9b45a", "b8874f", "faf6ee", "6f8fb5", "e7a98f", "bdb6aa"]
N_OSM_FACADES = 14
FACADE_TOWER = [14, 15, 16, 17, 4, 2, 0, 18]
FACADE_LOW = [0, 1, 3, 4, 7, 8, 9, 11, 16, 18, 19]
FACADE_GARAGE = [19, 12, 5]
# Prédios que o jogo desenha de outro jeito (marcos) ou que dão lugar aos boxes do jogo
LANDMARK_BUILDINGS = {976405284: "sphere", 27831699: "eiffel"}
SKIP_BUILDINGS = {1198427833}  # Grand Prix Plaza (o jogo monta o próprio complexo dos boxes)
HIGH_ROLLER = 402543930
FOUNTAIN_NAMES = ("Fountains of Bellagio",)


# Letreiro de neon de cada prédio ("v" no JSON; CityNeon no jogo): nenhum, nome no alto da torre,
# marquise do cassino (pódio), lâmina vertical (lojas, motéis)
SIGN_NONE, SIGN_TOWER, SIGN_CASINO, SIGN_SMALL = 0, 1, 2, 3
# Preenchimento dos terrenos vazios (m): resolução da máscara, folga além da área da pista (calçada,
# palmeiras e objetos), calçada de cada lado das ruas, folga entre prédios, menor e maior lado
FILL_RES = 2.0
FILL_TRACK_GAP = 10.0
FILL_STREET_GAP = 4.0
FILL_GAP = 6.0
FILL_MIN = 9.0
FILL_MAX = 150.0


def chess_dist(free, limit):
    """Distância (em pixels, xadrez) até o pixel ocupado mais próximo: k = quadrado de lado 2k-1
    livre em volta (erosões sucessivas)."""
    img = Image.fromarray(free.astype(np.uint8) * 255)
    dist = np.zeros(free.shape, np.int16)
    for k in range(1, limit + 1):
        arr = np.array(img) > 0
        if not arr.any():
            break
        dist[arr] = k
        img = img.filter(ImageFilter.MinFilter(3))
    return dist


def simplify_closed(pts, tol):
    """Douglas-Peucker num polígono fechado."""
    pts = np.asarray(pts)

    def dp(seg):
        if len(seg) < 3:
            return list(seg)
        a, b = seg[0], seg[-1]
        ab = b - a
        L = np.hypot(*ab)
        if L < 1e-9:
            d = np.hypot(*(seg - a).T)
        else:
            d = np.abs(ab[0] * (seg[:, 1] - a[1]) - ab[1] * (seg[:, 0] - a[0])) / L
        k = int(np.argmax(d))
        if d[k] <= tol:
            return [a, b]
        left = dp(seg[: k + 1])
        return left[:-1] + dp(seg[k:])
    far = int(np.argmax(np.hypot(*(pts - pts[0]).T)))
    ring = np.vstack([pts, pts[:1]])
    out = dp(ring[: far + 1])[:-1] + dp(ring[far:])[:-1]
    return np.array(out)


def point_in_poly(p, poly):
    x, y = p
    inside = False
    n = len(poly)
    for i in range(n):
        (xa, ya), (xb, yb) = poly[i], poly[(i + 1) % n]
        if (ya > y) != (yb > y) and x < xa + (y - ya) * (xb - xa) / (yb - ya):
            inside = not inside
    return inside


def b64(arr):
    return base64.b64encode(zlib.compress(np.ascontiguousarray(arr).tobytes(), 9)).decode("ascii")


def parse_height(tags, key="height"):
    try:
        if key in tags:
            return float(str(tags[key]).split()[0].replace(",", "."))
    except ValueError:
        pass
    return None


class City:
    def __init__(self, dense, total, half):
        self.dense, self.total, self.half = dense, total, half
        self.elev = np.full(len(dense), ROAD_Z)
        x0, y0, x1, y1 = AREA
        self.nx = int(round((x1 - x0) / CELL)) + 1
        self.ny = int(round((y1 - y0) / CELL)) + 1
        self.gx = x0 + np.arange(self.nx) * CELL
        self.gy = y0 + np.arange(self.ny) * CELL
        t, left = frames(dense)
        self.tang, self.left = t, left
        self.n = len(dense)
        self.landmarks = []
        self.ext = {1: np.array([self.side_extent(j, 1) for j in range(self.n)]),
                    -1: np.array([self.side_extent(j, -1) for j in range(self.n)])}

    # -- utilidades ------------------------------------------------------------
    def s_rel(self, s):
        return (s + self.total * 0.5) % self.total - self.total * 0.5

    def in_span(self, s, a, b):
        return (s - a) % self.total <= (b - a) % self.total

    def to_px(self, x, y, res=1.0):
        return ((x - AREA[0]) / res, (AREA[3] - y) / res)

    def mask(self, res=1.0):
        w = int((AREA[2] - AREA[0]) / res) + 1
        h = int((AREA[3] - AREA[1]) / res) + 1
        return Image.new("L", (w, h), 0)

    def project(self, px, py):
        """Ponto mais próximo da linha central para vários pontos: (s, lateral com sinal, distância)."""
        px, py = np.asarray(px, float), np.asarray(py, float)
        s = np.zeros(px.shape)
        lat = np.zeros(px.shape)
        dist = np.zeros(px.shape)
        d = self.dense
        for a in range(0, px.size, 2000):
            qx, qy = px.flat[a:a + 2000], py.flat[a:a + 2000]
            dd = (qx[:, None] - d[None, :, 0]) ** 2 + (qy[:, None] - d[None, :, 1]) ** 2
            k = np.argmin(dd, axis=1)
            s.flat[a:a + 2000] = k
            dist.flat[a:a + 2000] = np.sqrt(dd[np.arange(len(k)), k])
            lat.flat[a:a + 2000] = (qx - d[k, 0]) * self.left[k, 0] + (qy - d[k, 1]) * self.left[k, 1]
        return s, lat, dist

    def side_extent(self, s, side):
        """Até onde vai a área livre (pista, barreira, boxes, arquibancadas) a partir do eixo, num lado."""
        i = int(s) % self.n
        barrier = BARRIER
        for a, b, sd, d in BARRIER_ZONES:
            if sd in (0, side) and self.in_span(s, a, b):
                barrier = max(barrier, d)
        e = self.half[i] + barrier + 1.5
        sr = self.s_rel(s)
        if side == PIT["side"] and PIT["entry"] - 10 <= sr <= PIT["exit"] + 10:
            e = max(e, self.half[i] + PIT["lane"] + 2.0)
            if abs(sr - PIT["center"]) < PIT["building"] * 0.5 + 12:
                e = max(e, self.half[i] + PIT["lane"] + PIT["depth"] + 2.0)
        for a, b, sd, depth in FLAT_ZONES:
            if sd == side and self.in_span(s, a % self.total - 8, b % self.total + 8):
                e = max(e, self.half[i] + depth + 2.0)
        return e

    def clear_of_track(self, x, y, margin):
        """Pontos (arrays) fora da área livre da pista com folga `margin`."""
        s, lat, dist = self.project(x, y)
        idx = s.astype(int)
        ext = np.where(lat >= 0, self.ext[1][idx], self.ext[-1][idx])
        return dist > ext + margin

    # -- etapas ----------------------------------------------------------------
    def build(self):
        self.terrain()
        self.buildings()
        self.streets()
        self.water_and_parks()
        self.wheel()
        self.neon_flags()
        self.infill()
        self.trees()
        if DEBUG:
            self.debug_image()

    def terrain(self):
        """Deserto plano: o chão no nível da cidade, um pouco abaixo da pista junto dela e calçadas."""
        X, Y = np.meshgrid(self.gx, self.gy)  # [ny, nx]
        h = np.full(X.shape, GROUND_Z)
        cls = np.zeros(X.shape, np.uint8)
        s, lat, dist = self.project(X.ravel(), Y.ravel())
        idx = s.astype(int)
        ext = np.where(lat >= 0, self.ext[1][idx], self.ext[-1][idx])
        road = dist < ext
        walk = (dist < ext + 5.0) & ~road
        hv = h.ravel()
        cv = cls.ravel()
        hv[road] = ROAD_Z - 0.4
        cv[road] = 1
        hv[walk] = ROAD_Z + 0.15
        cv[walk] = 4
        self.h = hv.reshape(X.shape)
        self.cls = cv.reshape(X.shape)
        self.ground = self.h
        print("terreno: %dx%d vértices (plano)" % (self.nx, self.ny))

    def height_at(self, x, y):
        fx = (np.asarray(x) - AREA[0]) / CELL
        fy = (np.asarray(y) - AREA[1]) / CELL
        ix = np.clip(np.floor(fx).astype(int), 0, self.nx - 2)
        iy = np.clip(np.floor(fy).astype(int), 0, self.ny - 2)
        tx, ty = np.clip(fx - ix, 0, 1), np.clip(fy - iy, 0, 1)
        g = self.ground
        return (g[iy, ix] * (1 - tx) * (1 - ty) + g[iy, ix + 1] * tx * (1 - ty)
                + g[iy + 1, ix] * (1 - tx) * ty + g[iy + 1, ix + 1] * tx * ty)

    def _footprints(self):
        """Prédios e partes: [(tags, pts, id, é_parte)]; plantas com partes dão lugar às partes."""
        parts = []
        for tags, g, wid in ways_of("parts.json"):
            if len(g) < 4:
                continue
            minh = parse_height(tags, "min_height") or 0.0
            if minh > 2.0:
                continue  # passarelas e pedaços suspensos
            parts.append((tags, np.array(g[:-1] if g[0] == g[-1] else g), wid, True))
        out = []
        seen = set()
        for tags, g, wid in ways_of("buildings.json"):
            if wid in seen and tags.get("type") != "multipolygon":
                continue
            seen.add(wid)
            if len(g) < 4 or wid in SKIP_BUILDINGS:
                continue
            pts = np.array(g[:-1] if g[0] == g[-1] else g)
            if wid not in LANDMARK_BUILDINGS and any(point_in_poly(tuple(p[1].mean(axis=0)), pts) for p in parts):
                continue  # as partes desenham o prédio
            out.append((tags, pts, wid, False))
        return out + parts

    def buildings(self):
        out = []
        dropped = trimmed = 0
        rng = np.random.default_rng(5)
        for tags, pts, wid, is_part in self._footprints():
            if not ((pts[:, 0] > AREA[0] + 10).all() and (pts[:, 0] < AREA[2] - 10).all()
                    and (pts[:, 1] > AREA[1] + 10).all() and (pts[:, 1] < AREA[3] - 10).all()):
                continue
            area = 0.5 * abs(np.dot(pts[:, 0], np.roll(pts[:, 1], 1)) - np.dot(pts[:, 1], np.roll(pts[:, 0], 1)))
            if area < 15.0:
                continue
            lm = LANDMARK_BUILDINGS.get(wid, "")
            # Arestas a cada 2 m: o que invadir a área da pista é empurrado para trás dela; invasões
            # grandes (boxes, arquibancadas) removem o prédio
            samples = []
            for a, b in zip(pts, np.roll(pts, -1, axis=0)):
                k = max(int(np.hypot(*(b - a)) / 2.0), 1)
                samples.extend(a + (b - a) * t / k for t in range(k))
            samples = np.array(samples)
            s, lat, dist = self.project(samples[:, 0], samples[:, 1])
            bad = pushed = False
            for k in range(len(samples)):
                i = int(s[k])
                side = 1 if lat[k] >= 0 else -1
                clear = self.ext[side][i] + 0.3
                if dist[k] < clear:
                    if clear - dist[k] > 9.0:
                        bad = True
                        break
                    samples[k] = self.dense[i] + self.left[i] * side * clear
                    pushed = True
            if bad and not lm:
                dropped += 1
                if DEBUG and area > 400:
                    print("    removido: %s (%s) %.0f m²" % (tags.get("name", "?"), tags.get("building"), area))
                continue
            if pushed and not lm:
                pts = simplify_closed(samples, 0.35)
                trimmed += 1
            lo, hi = pts.min(axis=0), pts.max(axis=0)
            d = self.dense
            near = np.where((d[:, 0] >= lo[0]) & (d[:, 0] <= hi[0]) & (d[:, 1] >= lo[1]) & (d[:, 1] <= hi[1]))[0]
            if any(point_in_poly(tuple(d[i]), pts) for i in near):
                dropped += 1
                continue
            gh = self.height_at(pts[:, 0], pts[:, 1])
            base = float(gh.min()) - 0.6
            height = parse_height(tags)
            if height is None and "building:levels" in tags:
                try:
                    height = float(tags["building:levels"]) * 3.3 + 1.0
                except ValueError:
                    height = None
            kind = tags.get("building", tags.get("building:part", "yes"))
            if height is None:
                if kind in ("house", "detached", "garage", "shed", "roof", "kiosk", "hut", "carport"):
                    height = rng.uniform(4.0, 8.0)
                elif area < 150:
                    height = rng.uniform(6.0, 12.0)
                else:
                    # Pódios de cassino e centros de convenção: largos e baixos
                    height = rng.uniform(12.0, 26.0) + min(area / 2500.0, 10.0)
            height = float(np.clip(height, 3.0, 205.0))
            top = float(gh.max()) + height
            if kind in ("roof", "carport"):
                base = top - 0.6
            signed = np.dot(pts[:, 0], np.roll(pts[:, 1], -1)) - np.dot(pts[:, 1], np.roll(pts[:, 0], -1))
            if signed < 0:
                pts = pts[::-1]
            out.append({
                "p": [round(float(v), 2) for v in pts.ravel()],
                "b": round(base, 2), "t": round(top, 2),
                "c": int(rng.integers(N_OSM_FACADES)), "r": 0,
                "n": tags.get("name", ""), "lm": lm,
                "_kind": kind, "_area": float(area),
            })
            if lm:
                c = pts.mean(axis=0)
                r = float(np.hypot(*(pts - c).T).max())
                self.landmarks.append({"kind": lm, "x": round(float(c[0]), 2), "y": round(float(c[1]), 2),
                                       "r": round(r, 2), "h": round(height, 1), "z": round(float(gh.min()), 2)})
        self.blds = out
        print("prédios: %d (%d recortados e %d removidos por invadir a pista)" % (len(out), trimmed, dropped))

    def streets(self):
        widths = {"trunk": 20.0, "primary": 16.0, "secondary": 13.0, "tertiary": 10.0, "residential": 7.0,
                  "unclassified": 7.0, "living_street": 5.0, "pedestrian": 5.0, "service": 5.0}
        out = []
        for tags, g, wid in ways_of("roads.json"):
            hw = tags.get("highway")
            if hw not in widths or tags.get("tunnel") in ("yes", "building_passage") or tags.get("bridge") == "yes":
                continue
            if tags.get("layer", "0").startswith("-") or tags.get("service") in ("drive-through", "parking_aisle"):
                continue
            if tags.get("area") == "yes":
                continue
            pts = np.array(g)
            dense = [pts[0]]
            for a, b in zip(pts[:-1], pts[1:]):
                k = max(int(np.hypot(*(b - a)) / 4.0), 1)
                dense.extend(a + (b - a) * t / k for t in range(1, k + 1))
            dense = np.array(dense)
            inside = ((dense[:, 0] > AREA[0] + 8) & (dense[:, 0] < AREA[2] - 8)
                      & (dense[:, 1] > AREA[1] + 8) & (dense[:, 1] < AREA[3] - 8))
            ok = inside & self.clear_of_track(dense[:, 0], dense[:, 1], widths[hw] * 0.5 + 1.0)
            z = self.height_at(dense[:, 0], dense[:, 1]) + 0.12
            run = []
            for k in range(len(dense) + 1):
                if k < len(dense) and ok[k]:
                    run.append(k)
                    continue
                if len(run) >= 2:
                    seg = []
                    for j in run:
                        seg.extend([round(float(dense[j, 0]), 2), round(float(dense[j, 1]), 2), round(float(z[j]), 2)])
                    out.append({"w": widths[hw], "k": 1 if hw == "pedestrian" else 0, "p": seg})
                run = []
        self.street = out
        print("ruas: %d trechos" % len(out))

    def water_and_parks(self):
        pools = []
        for tags, g, wid in ways_of("water.json"):
            if len(g) < 4:
                continue
            pts = np.array(g[:-1] if g[0] == g[-1] else g)
            if not ((pts[:, 0] > AREA[0]).all() and (pts[:, 0] < AREA[2]).all() and (pts[:, 1] > AREA[1]).all() and (pts[:, 1] < AREA[3]).all()):
                continue
            if not self.clear_of_track(pts[:, 0], pts[:, 1], 1.0).all():
                continue
            z = float(self.height_at(pts[:, 0], pts[:, 1]).max()) + 0.1
            signed = np.dot(pts[:, 0], np.roll(pts[:, 1], -1)) - np.dot(pts[:, 1], np.roll(pts[:, 0], -1))
            if signed < 0:
                pts = pts[::-1]
            pools.append({"p": [round(float(v), 2) for v in pts.ravel()], "z": round(z, 2)})
            if tags.get("name", "") in FOUNTAIN_NAMES:
                area = 0.5 * abs(np.dot(pts[:, 0], np.roll(pts[:, 1], 1)) - np.dot(pts[:, 1], np.roll(pts[:, 0], 1)))
                if area > 2000.0:
                    self.landmarks.append({"kind": "fountain", "p": [round(float(v), 2) for v in pts.ravel()], "z": round(z, 2)})
        self.pools = pools
        img = self.mask(CELL)
        dr = ImageDraw.Draw(img)
        self.park_polys = []
        for tags, g, wid in ways_of("green.json"):
            if len(g) >= 4:
                dr.polygon([self.to_px(x, y, CELL) for x, y in g], fill=1)
                self.park_polys.append(np.array(g))
        cover = np.array(img)[::-1][: self.ny, : self.nx]
        cover = np.where(self.cls == 0, cover, 0)
        self.cover = cover.astype(np.uint8)
        print("piscinas: %d; parques: %d; fontes: %d" % (len(pools), len(self.park_polys),
              sum(1 for l in self.landmarks if l["kind"] == "fountain")))

    def wheel(self):
        """Roda-gigante High Roller: centro, direção do plano da roda e diâmetro (158 m)."""
        for tags, g, wid in ways_of("high_roller.json"):
            if wid != HIGH_ROLLER:
                continue
            pts = np.array(g)
            c = pts.mean(axis=0)
            u, sv, vt = np.linalg.svd(pts - c)
            axis = vt[0]  # direção mais comprida = plano da roda
            self.landmarks.append({"kind": "wheel", "x": round(float(c[0]), 2), "y": round(float(c[1]), 2),
                                   "dx": round(float(axis[0]), 4), "dy": round(float(axis[1]), 4), "d": 158.0,
                                   "z": round(float(self.height_at(np.array([c[0]]), np.array([c[1]]))[0]), 2)})
            print("High Roller em %.0f, %.0f" % (c[0], c[1]))

    # -- letreiros e preenchimento ---------------------------------------------
    def neon_flags(self):
        """Letreiro de neon de cada prédio do OSM ("v", desenhado por CityNeon no jogo): torres de
        hotel e cassino (e parte das outras torres altas) ganham o nome no alto; pódios largos de cassino e de lojas, a marquise; parte
        das lojas baixas, um letreiro de lâmina."""
        rng = np.random.default_rng(21)
        count = [0, 0, 0, 0]
        for b in self.blds:
            name = b["n"].lower()
            kind = b.pop("_kind")
            area = b.pop("_area")
            h = b["t"] - b["b"]
            hotel = kind == "hotel" or any(w in name for w in ("hotel", "casino", "resort", "tower", "palace"))
            v = SIGN_NONE
            if b["lm"] or "parking" in name or kind in ("parking", "roof", "carport", "garage", "construction", "bridge"):
                v = SIGN_NONE
            elif (hotel and h > 40.0) or (h > 55.0 and rng.random() < 0.6):
                v = SIGN_TOWER
            elif (hotel or kind in ("retail", "commercial")) and area > 1500.0 and h < 40.0:
                v = SIGN_CASINO
            elif kind in ("retail", "commercial", "yes") and area < 1500.0 and h < 16.0 and rng.random() < 0.35:
                v = SIGN_SMALL
            b["v"] = v
            count[v] += 1
        print("letreiros do OSM: %d torres, %d marquises, %d lâminas" % tuple(count[1:]))

    def infill(self):
        """Os terrenos vazios (estacionamentos abertos e lotes de areia, que deixavam a cidade
        "chapada") ganham prédios inventados no estilo da Strip, alinhados à rua mais próxima: resorts
        (pódio de cassino com torre em lâmina, em Y ou duas torres), hotéis médios, cassinos baixos,
        garagens, escritórios e, nos lotes estreitos, lojas e motéis. Ficam fora da pista (com
        calçada), das ruas, das piscinas, dos parques e dos marcos, com folga entre os prédios."""
        res = FILL_RES
        rng = np.random.default_rng(33)
        to = lambda x, y: self.to_px(x, y, res)
        img = self.mask(res)
        dr = ImageDraw.Draw(img)
        bimg = self.mask(res)
        bdr = ImageDraw.Draw(bimg)
        for b in self.blds:
            p = np.array(b["p"]).reshape(-1, 2)
            bdr.polygon([to(x, y) for x, y in p], fill=255)
        for st in self.street:
            p = np.array(st["p"]).reshape(-1, 3)
            r = st["w"] * 0.5 + FILL_STREET_GAP
            dr.line([to(x, y) for x, y, z in p], fill=255, width=int(round(2.0 * r / res)))
            for x, y, z in p[:: 2]:
                px, py = to(x, y)
                dr.ellipse([px - r / res, py - r / res, px + r / res, py + r / res], fill=255)
        for pl in self.pools:
            p = np.array(pl["p"]).reshape(-1, 2)
            dr.polygon([to(x, y) for x, y in p], fill=255)
        for poly in self.park_polys:
            dr.polygon([to(x, y) for x, y in poly], fill=255)
        for lm in self.landmarks:
            if lm["kind"] == "fountain":
                p = np.array(lm["p"]).reshape(-1, 2)
                dr.polygon([to(x, y) for x, y in p], fill=255)
            elif lm["kind"] == "wheel":
                c = np.array([lm["x"], lm["y"]])
                u = np.array([lm["dx"], lm["dy"]])
                v = np.array([-u[1], u[0]])
                q = [c + u * a * 90.0 + v * b * 30.0 for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
                dr.polygon([to(*p) for p in q], fill=255)
            else:
                px, py = to(lm["x"], lm["y"])
                r = (lm["r"] + 12.0) / res
                dr.ellipse([px - r, py - r, px + r, py + r], fill=255)
        # A pista e tudo o que é dela (barreira, boxes, arquibancadas) mais a calçada
        for side in (1, -1):
            off = self.dense + self.left * side * (self.ext[side] + FILL_TRACK_GAP)[:, None]
            for i in range(0, self.n, 2):
                j = (i + 3) % self.n
                dr.polygon([to(*self.dense[i]), to(*self.dense[j]), to(*off[j]), to(*off[i])], fill=255)
        gap = int(round(FILL_GAP / res))
        bmask = np.array(bimg.filter(ImageFilter.MaxFilter(2 * gap + 1))) > 0
        free = ~((np.array(img) > 0) | bmask)
        edge = int(40.0 / res)
        free[:edge, :] = free[-edge:, :] = False
        free[:, :edge] = free[:, -edge:] = False
        hgt, wid = free.shape
        # Direção das ruas (o lote se alinha à rua mais próxima)
        seg_mid, seg_ang = [], []
        for st in self.street:
            p = np.array(st["p"]).reshape(-1, 3)[:, :2]
            d = p[1:] - p[:-1]
            seg_mid.append((p[1:] + p[:-1]) * 0.5)
            seg_ang.append(np.arctan2(d[:, 1], d[:, 0]))
        seg_mid = np.concatenate(seg_mid)
        seg_ang = np.concatenate(seg_ang)

        def to_px_arr(X, Y):
            return np.round((X - AREA[0]) / res).astype(int), np.round((AREA[3] - Y) / res).astype(int)

        def samples(c, u, v, e, step):
            us = np.arange(-e[0], e[1] + 1e-6, step)
            vs = np.arange(-e[2], e[3] + 1e-6, step)
            U, V = np.meshgrid(us, vs)
            return c[0] + U * u[0] + V * v[0], c[1] + U * u[1] + V * v[1]

        def fits(c, u, v, e):
            px, py = to_px_arr(*samples(c, u, v, e, res))
            if px.min() < 0 or py.min() < 0 or px.max() >= wid or py.max() >= hgt:
                return False
            return bool(free[py, px].all())

        def occupy(c, u, v, e, pad):
            px, py = to_px_arr(*samples(c, u, v, [x + pad for x in e], res * 0.5))
            ok = (px >= 0) & (py >= 0) & (px < wid) & (py < hgt)
            free[py[ok], px[ok]] = False

        added = {"resort": 0, "hotel": 0, "casino": 0, "garage": 0, "office": 0, "shop": 0}
        k_min = int(FILL_MIN * 0.5 / res) + 1
        for it in range(8):
            dist = chess_dist(free, 60)
            ys, xs = np.nonzero((dist >= k_min) & (np.arange(hgt)[:, None] % 3 == 0) & (np.arange(wid)[None, :] % 3 == 0))
            if len(ys) == 0:
                break
            order = np.argsort(-dist[ys, xs], kind="stable")
            placed = 0
            for idx in order:
                y, x = int(ys[idx]), int(xs[idx])
                if not free[y, x]:
                    continue
                k = int(dist[y, x]) - 1
                if not free[y - k:y + k + 1, x - k:x + k + 1].all():
                    continue
                c = np.array([AREA[0] + x * res, AREA[3] - y * res])
                d2 = (seg_mid[:, 0] - c[0]) ** 2 + (seg_mid[:, 1] - c[1]) ** 2
                j = int(np.argmin(d2))
                ang = float(seg_ang[j]) if d2[j] < 150.0 ** 2 else 0.0
                ang = ang % (math.pi * 0.5)
                u = np.array([math.cos(ang), math.sin(ang)])
                v = np.array([-u[1], u[0]])
                h0 = max(k * res * 0.7, 2.0)
                e = None
                for _ in range(4):
                    if fits(c, u, v, [h0] * 4):
                        e = [h0] * 4
                        break
                    h0 *= 0.75
                if e is None:
                    free[y, x] = False
                    continue
                grow = [True] * 4
                while any(grow):
                    for sd in range(4):
                        if not grow[sd]:
                            continue
                        span = e[0] + e[1] if sd < 2 else e[2] + e[3]
                        other = e[2] + e[3] if sd < 2 else e[0] + e[1]
                        if span + 2.0 > FILL_MAX or span + 2.0 > max(other, FILL_MIN) * 3.0:
                            grow[sd] = False
                            continue
                        t = list(e)
                        t[sd] += 2.0
                        if fits(c, u, v, t):
                            e = t
                        else:
                            grow[sd] = False
                A, B = e[0] + e[1], e[2] + e[3]
                if min(A, B) < FILL_MIN:
                    occupy(c, u, v, e, 0.0)
                    continue
                c = c + u * (e[1] - e[0]) * 0.5 + v * (e[3] - e[2]) * 0.5
                if B > A:
                    u, v, A, B = v, -u, B, A
                kind = self._fill_lot(c, u, v, A, B, rng)
                added[kind] += 1
                placed += 1
                occupy(c, u, v, [A * 0.5, A * 0.5, B * 0.5, B * 0.5], FILL_GAP)
            if placed == 0:
                break
        print("preenchimento: " + ", ".join("%d %s" % (n, k) for k, n in added.items()))
        # Para onde o letreiro olha: o ponto da pista mais perto do prédio ("tp") e a distância ("td")
        signed = [b for b in self.blds if b.get("v")]
        cs = np.array([np.array(b["p"]).reshape(-1, 2).mean(axis=0) for b in signed])
        s, lat, dist = self.project(cs[:, 0], cs[:, 1])
        for b, k, d in zip(signed, s.astype(int), dist):
            b["tp"] = [round(float(self.dense[k, 0]), 1), round(float(self.dense[k, 1]), 1)]
            b["td"] = round(float(d), 1)

    def _fill_lot(self, c, u, v, A, B, rng):
        """Prédio(s) inventado(s) no lote retangular (centro c, eixos u ao longo do lado A, o maior)."""
        _, _, dist = self.project(np.array([c[0]]), np.array([c[1]]))
        near = float(dist[0]) < 280.0

        def rect(cc, a, b):
            return [cc + u * sa * a * 0.5 + v * sb * b * 0.5 for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1))]

        def add(pts, base, top, facades, sign):
            pts = np.array(pts)
            signed = np.dot(pts[:, 0], np.roll(pts[:, 1], -1)) - np.dot(pts[:, 1], np.roll(pts[:, 0], -1))
            if signed < 0:
                pts = pts[::-1]
            self.blds.append({"p": [round(float(q), 2) for q in pts.ravel()], "b": round(base, 2), "t": round(top, 2),
                              "c": int(facades[int(rng.integers(len(facades)))]), "r": 0, "n": "", "lm": "", "v": sign, "f": 1})

        base = GROUND_Z - 0.6
        if B >= 48.0 and A * B >= 3800.0:
            # Resort: pódio de cassino e torre(s) de hotel em cima
            pod = rng.uniform(12.0, 20.0)
            add(rect(c, A, B), base, pod, FACADE_LOW, SIGN_CASINO)
            tall = rng.uniform(75.0, 135.0) + (35.0 if near else 0.0)
            shape = rng.choice(["slab", "y", "twin"], p=[0.45, 0.3, 0.25])
            if shape == "twin" and A < 100.0:
                shape = "slab"
            if shape == "y" and B < 58.0:
                shape = "slab"
            if shape == "y":
                arm = min(B * rng.uniform(0.32, 0.4), 55.0)
                w = rng.uniform(8.0, 10.0)
                a0 = math.atan2(u[1], u[0]) + rng.choice([0.0, math.pi * 0.5, math.pi, math.pi * 1.5])
                pts = []
                for k in range(3):
                    a = a0 + k * 2.0 * math.pi / 3.0
                    d = np.array([math.cos(a), math.sin(a)])
                    nrm = np.array([-d[1], d[0]])
                    bis = np.array([math.cos(a + math.pi / 3.0), math.sin(a + math.pi / 3.0)])
                    pts += [c + d * arm - nrm * w, c + d * arm + nrm * w, c + bis * (w / math.sin(math.pi / 3.0))]
                add(pts, pod, pod + tall, FACADE_TOWER, SIGN_TOWER)
            elif shape == "twin":
                L = A * rng.uniform(0.28, 0.36)
                D = min(rng.uniform(17.0, 22.0), B * 0.5)
                for sa, kh in ((-1, 1.0), (1, rng.uniform(0.75, 0.95))):
                    cc = c + u * sa * A * 0.25 + v * rng.uniform(-1.0, 1.0) * (B - D) * 0.2
                    add(rect(cc, L, D), pod, pod + tall * kh, FACADE_TOWER, SIGN_TOWER)
            else:
                L = float(np.clip(A * rng.uniform(0.5, 0.82), 40.0, 115.0))
                D = min(rng.uniform(17.0, 24.0), B * 0.55)
                cc = c + v * rng.uniform(-1.0, 1.0) * (B - D) * 0.25
                add(rect(cc, L, D), pod, pod + tall, FACADE_TOWER, SIGN_TOWER)
            return "resort"
        if B >= 22.0:
            r = rng.random()
            if r < 0.34:
                top = rng.uniform(28.0, 70.0) + (15.0 if near else 0.0)
                add(rect(c, A - 2.0, B - 2.0), base, top, FACADE_TOWER, SIGN_TOWER if top > 40.0 else SIGN_CASINO)
                return "hotel"
            if r < 0.64:
                add(rect(c, A, B), base, rng.uniform(11.0, 19.0), FACADE_LOW, SIGN_CASINO)
                return "casino"
            if r < 0.84:
                add(rect(c, A, B), base, rng.uniform(13.0, 21.0), FACADE_GARAGE, SIGN_NONE)
                return "garage"
            add(rect(c, A - 2.0, B - 2.0), base, rng.uniform(18.0, 48.0), FACADE_LOW, SIGN_NONE)
            return "office"
        add(rect(c, A, B), base, rng.uniform(5.0, 11.0), FACADE_LOW, SIGN_SMALL if rng.random() < 0.7 else SIGN_NONE)
        return "shop"

    def building_mask(self):
        img = self.mask()
        dr = ImageDraw.Draw(img)
        for b in self.blds:
            p = np.array(b["p"]).reshape(-1, 2)
            dr.polygon([self.to_px(x, y) for x, y in p], fill=255)
        for st in self.street:
            p = np.array(st["p"]).reshape(-1, 3)
            dr.line([self.to_px(x, y) for x, y, z in p], fill=255, width=int(st["w"]))
        for pl in self.pools:
            p = np.array(pl["p"]).reshape(-1, 2)
            dr.polygon([self.to_px(x, y) for x, y in p], fill=255)
        for lm in self.landmarks:
            if lm["kind"] == "wheel":
                r = 40
                px, py = self.to_px(lm["x"], lm["y"])
                dr.rectangle([px - r, py - r, px + r, py + r], fill=255)
        return np.array(img) > 0

    def trees(self):
        rng = np.random.default_rng(9)
        blocked = self.building_mask()
        hgt, wid = blocked.shape
        trees = []

        def free(x, y, r=2):
            px, py = int(x - AREA[0]), int(AREA[3] - y)
            if px < r or py < r or px >= wid - r or py >= hgt - r:
                return False
            return not blocked[py - r:py + r + 1, px - r:px + r + 1].any()

        def add(x, y, kind):
            if not self.clear_of_track(np.array([x]), np.array([y]), 2.0)[0] or not free(x, y):
                return
            z = float(self.height_at(np.array([x]), np.array([y]))[0])
            trees.extend([round(x, 2), round(y, 2), round(z, 2), kind])
            px, py = int(x - AREA[0]), int(AREA[3] - y)
            blocked[py - 3:py + 4, px - 3:px + 4] = True

        # Árvores mapeadas (quase todas palmeiras na Strip)
        for e in load("trees.json")["elements"]:
            x, y = xy(e["lat"], e["lon"])
            if AREA[0] < x < AREA[2] and AREA[1] < y < AREA[3]:
                add(x, y, 1)
        # Parques e o campo de golfe
        for poly in self.park_polys:
            xmin, ymin = poly.min(axis=0)
            xmax, ymax = poly.max(axis=0)
            area = (xmax - xmin) * (ymax - ymin)
            if area < 50:
                continue
            img = Image.new("L", (int(xmax - xmin) + 2, int(ymax - ymin) + 2), 0)
            ImageDraw.Draw(img).polygon([(x - xmin, ymax - y) for x, y in poly], fill=1)
            m = np.array(img)
            for _ in range(int(min(area, 200000.0) / 140.0)):
                x, y = rng.uniform(xmin, xmax), rng.uniform(ymin, ymax)
                if m[int(ymax - y), int(x - xmin)]:
                    add(float(x), float(y), 1 if rng.random() < 0.6 else 0)
        # Palmeiras na calçada ao longo de toda a pista (atrás da barreira), a cada ~26 m
        for i in range(0, self.n, 26):
            for side in (1, -1):
                d = self.ext[side][i] + 3.5
                p = self.dense[i] + self.left[i] * side * d
                add(float(p[0]), float(p[1]), 1)
        self.tree = trees
        print("árvores: %d" % (len(trees) // 4))

    def write(self):
        data = {
            "source": "OpenStreetMap (ODbL) - Las Vegas Strip Circuit; gerado por tools/build_las_vegas.py",
            "area": list(AREA), "cell": CELL, "nx": self.nx, "ny": self.ny,
            "height_cm": b64(np.round(self.h * 100.0).astype("<i2")),
            "cls": b64(self.cls.astype(np.uint8)),
            "cover": b64(self.cover.astype(np.uint8)),
            "tunnel": [0.0, 0.0], "tunnel_roof": 0.0,
            "sea": False,
            "style": "modern",
            "coast_exits": [],
            "facades": FACADES,
            "quays": [],
            "buildings": self.blds,
            "streets": self.street,
            "pools": self.pools,
            "piers": [],
            "trees": self.tree,
            "boats": [],
            "landmarks": self.landmarks,
        }
        path = os.path.join(OUT, "las_vegas_city.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, separators=(",", ":"), ensure_ascii=False)
        print("cidade: %s (%.0f KB)" % (path, os.path.getsize(path) / 1024))

    def debug_image(self):
        w = int(AREA[2] - AREA[0]) + 1
        h = int(AREA[3] - AREA[1]) + 1
        img = Image.new("RGB", (w, h), (226, 214, 190))
        dr = ImageDraw.Draw(img)
        for poly in self.park_polys:
            dr.polygon([self.to_px(x, y) for x, y in poly], fill=(150, 190, 120))
        for pl in self.pools:
            p = np.array(pl["p"]).reshape(-1, 2)
            dr.polygon([self.to_px(x, y) for x, y in p], fill=(90, 160, 220))
        for st in self.street:
            p = np.array(st["p"]).reshape(-1, 3)
            dr.line([self.to_px(x, y) for x, y, z in p], fill=(150, 150, 150), width=int(st["w"]))
        for b in self.blds:
            p = np.array(b["p"]).reshape(-1, 2)
            hgt = b["t"] - b["b"]
            c = int(np.clip(200 - hgt, 60, 200))
            col = (220, 60, 160) if b["lm"] else ((c - 40, c - 20, c) if b.get("f") else (c, c - 20, c - 40))
            if b.get("v"):
                col = (col[0], min(col[1] + 60, 255), col[2])
            dr.polygon([self.to_px(x, y) for x, y in p], fill=col, outline=(80, 70, 60))
        tr = np.array(self.tree).reshape(-1, 4)
        for x, y, z, k in tr:
            px, py = self.to_px(x, y)
            dr.ellipse([px - 2, py - 2, px + 2, py + 2], fill=(40, 140, 50))
        for i in range(0, self.n, 2):
            px, py = self.to_px(*self.dense[i])
            r = self.half[i]
            dr.ellipse([px - r, py - r, px + r, py + r], fill=(50, 50, 55))
        for i in range(0, self.n, 100):
            px, py = self.to_px(*self.dense[i])
            dr.text((px + 12, py), str(i), fill=(255, 0, 0))
        for lm in self.landmarks:
            if "x" in lm:
                px, py = self.to_px(lm["x"], lm["y"])
                dr.text((px, py), lm["kind"].upper(), fill=(255, 255, 0))
        img.save(os.path.join(DEBUG, "las_vegas_city.png"))
        img.resize((w // 3, h // 3)).save(os.path.join(DEBUG, "las_vegas_city_small.png"))


if __name__ == "__main__":
    if "--debug" in sys.argv:
        DEBUG = sys.argv[sys.argv.index("--debug") + 1]
        os.makedirs(DEBUG, exist_ok=True)
    dense, total, half, pit = main_track()
    city = City(dense, total, half)
    city.build()
    city.write()
