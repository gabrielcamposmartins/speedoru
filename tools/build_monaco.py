"""Gera a pista de Mônaco a partir dos dados do OpenStreetMap (ODbL) em tools/data/monaco/.

Entrada (baixada da Overpass API, © colaboradores do OpenStreetMap, ODbL):
  circuit_chain.json   linha central da relação 148194 "Circuit de Monaco" (vias encadeadas, metros)
  circuit_ways.json    vias do circuito (túnel, saída dos boxes)
  b_*.json             prédios (4 quadrantes)          coast.json   linha da costa
  piers.json           píeres e quebra-mares            water.json   piscinas, espelhos d'água
  green.json           parques e jardins                roads.json   ruas da cidade

Saída (assets/track/monaco/):
  monaco_centerline.csv  x, y (leste/norte, m), meia-largura direita/esquerda, elevação (m)
  monaco_city.json       terreno (grade de alturas), costa, prédios, ruas, parques, piscinas,
                         píeres, árvores, barcos e o trecho do túnel

Coordenadas: origem em (lat 43.7347, lon 7.4206), x = leste, y = norte, em metros.

Rodar:  python tools/build_monaco.py [--debug pasta]   (a pasta recebe imagens de conferência)
"""

import base64
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data", "monaco")
OUT = os.path.join(HERE, "..", "assets", "track", "monaco")
LAT0, LON0 = 43.7347, 7.4206
KX = 111320.0 * math.cos(math.radians(LAT0))
KY = 110540.0
START_NODE = (43.7350269, 7.4212652)
TUNNEL_WAYS = {4230891, 1230247123, 1470365907}

# Área do terreno (m) e resolução da grade de alturas
AREA = (-290.0, -600.0, 1130.0, 1056.0)  # xmin, ymin, xmax, ymax (dentro da área baixada)
CELL = 4.0
SEA_FLOOR = -7.0
QUAY = 1.8
TUNNEL_ROOF = 8.5
CSV_STEP = 3.0

DEBUG = None


def xy(lat, lon):
    return ((lon - LON0) * KX, (lat - LAT0) * KY)


def load(name):
    with open(os.path.join(DATA, name), encoding="utf-8") as f:
        return json.load(f)


def ways_of(name):
    """[(tags, [(x, y)...], id)] de vias e de membros de relações."""
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
    s = np.arange(n) * total / n
    idx = np.searchsorted(cum, s, side="right") - 1
    t = (s - cum[idx]) / np.maximum(lens[idx], 1e-9)
    return pts[idx] + seg[idx] * t[:, None], total


def smooth_closed(a, sigma):
    """Suavização gaussiana circular (sigma em amostras)."""
    r = int(math.ceil(sigma * 3))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    pad = np.concatenate([a[-r:], a, a[:r]])
    if a.ndim == 1:
        return np.convolve(pad, k, mode="valid")
    return np.stack([np.convolve(pad[:, c], k, mode="valid") for c in range(a.shape[1])], axis=1)


def centerline():
    chain = load("circuit_chain.json")["chain"]
    pts = [tuple(p) for p in chain][::-1]  # o OSM encadeou no sentido contrário ao da corrida
    # Nó de cruzamento fora do eixo no alto do Beau Rivage (cria um "dente" na reta)
    pts = [p for p in pts if math.hypot(p[0] - 491.6, p[1] - 356.8) > 3.5]
    # Remove "bicos" (ida e volta do mapeamento, ex.: no Beau Rivage)
    changed = True
    while changed:
        changed = False
        for i in range(len(pts)):
            a, b, c = np.array(pts[i - 2]), np.array(pts[i - 1]), np.array(pts[i])
            u, v = b - a, c - b
            if np.dot(u, v) < -0.3 * np.linalg.norm(u) * np.linalg.norm(v):
                del pts[i - 1]
                changed = True
                break
    dense, total = resample(pts, 1.0)
    dense = smooth_closed(dense, 3.5)
    dense, total = resample(dense, 1.0)
    # Começa na linha de chegada
    sx, sy = xy(*START_NODE)
    i0 = int(np.argmin(np.hypot(dense[:, 0] - sx, dense[:, 1] - sy)))
    dense = np.roll(dense, -i0, axis=0)
    return dense, total


def nearest_s(dense, x, y):
    return float(np.argmin(np.hypot(dense[:, 0] - x, dense[:, 1] - y)))  # passo de 1 m


def tunnel_range(dense):
    pts = []
    for t, g, wid in ways_of("circuit_ways.json"):
        if wid in TUNNEL_WAYS:
            for a, b in zip(g[:-1], g[1:]):
                k = max(int(math.dist(a, b)), 1)
                pts.extend((a[0] + (b[0] - a[0]) * t / k, a[1] + (b[1] - a[1]) * t / k) for t in range(k + 1))
    pts = np.array(pts)
    d = np.min(np.hypot(dense[:, None, 0] - pts[None, :, 0], dense[:, None, 1] - pts[None, :, 1]), axis=1)
    inside = np.where(d < 6.0)[0]
    # Maior trecho contínuo
    runs, start = [], inside[0]
    for a, b in zip(inside[:-1], inside[1:]):
        if b != a + 1:
            runs.append((start, a))
            start = b
    runs.append((start, inside[-1]))
    s0, s1 = max(runs, key=lambda r: r[1] - r[0])
    return float(s0), float(s1)


# Elevação aproximada do circuito real (m acima do mar) em pontos conhecidos (x, y, z)
LANDMARKS = [
    ("Linha de chegada", 53.5, 36.1, 6.5),
    ("Sainte Dévote", 75.0, 246.0, 8.5),
    ("Beau Rivage", 300.0, 298.0, 24.0),
    ("Beau Rivage alto", 470.0, 351.0, 35.0),
    ("Massenet", 581.0, 467.0, 43.0),
    ("Casino", 537.0, 555.0, 44.5),
    ("Mirabeau Haute", 649.0, 709.0, 35.0),
    ("Grand Hotel", 726.0, 612.0, 26.0),
    ("Mirabeau Bas", 702.0, 681.0, 21.0),
    ("Portier", 775.0, 704.0, 12.0),
    ("Túnel", 745.0, 490.0, 8.5),
    ("Saída do túnel", 593.0, 340.0, 6.0),
    ("Nouvelle Chicane", 372.0, 264.0, 4.0),
    ("Tabac", 130.0, 230.0, 3.2),
    ("Piscine", 140.0, -30.0, 2.6),
    ("Rascasse", 232.0, -235.0, 3.0),
    ("Antony Noghès", 145.0, -254.0, 3.8),
    ("Reta dos boxes", 52.0, -100.0, 5.0),
]


def elevation(dense, total):
    n = len(dense)
    marks = sorted((nearest_s(dense, x, y), z, name) for name, x, y, z in LANDMARKS)
    s = np.array([m[0] for m in marks])
    z = np.array([m[1] for m in marks])
    # Interpolação cúbica monotônica (sem ultrapassar os pontos) e circular
    ss = np.concatenate([s[-2:] - total, s, s[:2] + total])
    zz = np.concatenate([z[-2:], z, z[:2]])
    d = np.diff(zz) / np.diff(ss)
    m = np.zeros_like(zz)
    for k in range(1, len(zz) - 1):
        m[k] = 0.0 if d[k - 1] * d[k] <= 0 else 2.0 / (1.0 / d[k - 1] + 1.0 / d[k])
    q = np.arange(n, dtype=float)
    k = np.searchsorted(ss, q, side="right") - 1
    h = ss[k + 1] - ss[k]
    t = (q - ss[k]) / h
    h00, h10, h01, h11 = 2 * t**3 - 3 * t**2 + 1, t**3 - 2 * t**2 + t, -2 * t**3 + 3 * t**2, t**3 - t**2
    elev = h00 * zz[k] + h10 * h * m[k] + h01 * zz[k + 1] + h11 * h * m[k + 1]
    elev = smooth_closed(elev, 22.0)
    return elev, marks


# Meias-larguras (m) por trecho: (s inicial, s final, meia-largura)
def widths(dense, total, marks, tunnel):
    n = len(dense)
    by_name = {name: s for s, z, name in marks}
    half = np.full(n, 5.0)

    def span(a, b, w):
        a, b = int(a) % n, int(b) % n
        idx = np.arange(a, b + 1) if a <= b else np.concatenate([np.arange(a, n), np.arange(0, b + 1)])
        half[idx] = np.maximum(half[idx], w)

    span(by_name["Antony Noghès"] + 20, by_name["Sainte Dévote"] - 30, 6.6)  # reta dos boxes
    span(by_name["Sainte Dévote"] - 30, by_name["Sainte Dévote"] + 25, 6.0)
    span(by_name["Grand Hotel"] - 35, by_name["Grand Hotel"] + 35, 7.2)  # o grampo precisa de espaço
    span(tunnel[0] - 20, tunnel[1] + 40, 5.8)
    span(by_name["Nouvelle Chicane"] - 30, by_name["Nouvelle Chicane"] + 30, 5.8)
    span(by_name["Tabac"] - 20, by_name["Antony Noghès"] + 20, 5.4)
    return smooth_closed(half, 10.0)


def write_csv(dense, total, elev, half):
    step = int(CSV_STEP)
    path = os.path.join(OUT, "monaco_centerline.csv")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Circuit de Monaco - linha central (x leste, y norte, metros), larguras e elevação.\n")
        f.write("# Fonte: OpenStreetMap (ODbL), relação 148194; elevação e larguras ajustadas à mão.\n")
        f.write("# x_m,y_m,w_tr_right_m,w_tr_left_m,z_m\n")
        for i in range(0, len(dense), step):
            x, y = dense[i]
            f.write("%.2f,%.2f,%.2f,%.2f,%.2f\n" % (x, y, half[i], half[i], elev[i]))
    print("linha central: %.0f m, %d pontos, elevação %.1f a %.1f m" % (total, len(dense) // step, elev.min(), elev.max()))


def raceline(dense, half, margin=2.0):
    """Linha de corrida de curvatura mínima: descida de gradiente da soma das curvaturas ao quadrado
    (suavização biharmônica, em três escalas), presa à largura útil (meia-largura - margem). No grampo
    ela abre por fora; nas curvas comuns faz fora-dentro-fora."""
    n = len(dense)
    t = np.roll(dense, -1, axis=0) - np.roll(dense, 1, axis=0)
    t /= np.hypot(t[:, 0], t[:, 1])[:, None]
    left = np.stack([-t[:, 1], t[:, 0]], axis=1)
    lim = np.maximum(half - margin, 0.3)
    # Curvas mais fechadas que o raio de giro do carro (grampo): a linha fica por fora nelas e
    # nos 20 m antes e depois (o carro não faz raio menor que ~10 m nem com o volante todo)
    ang = np.arctan2(t[:, 1], t[:, 0])
    kc = smooth_closed(np.angle(np.exp(1j * (np.roll(ang, -3) - np.roll(ang, 3)))) / 6.0, 2.0)
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
    path = os.path.join(OUT, "monaco_raceline.csv")
    with open(path, "w", encoding="utf-8", newline=chr(10)) as f:
        f.write("# Circuit de Monaco - linha de corrida (x leste, y norte, metros), curvatura mínima aproximada." + chr(10))
        f.write("# x_m,y_m" + chr(10))
        for i in range(0, len(line), int(CSV_STEP)):
            f.write("%.2f,%.2f" % tuple(line[i]) + chr(10))


def check_profile(elev, dense):
    grade = np.gradient(elev) * 100.0
    vc = np.gradient(np.gradient(elev))  # 1/m (passo 1 m)
    print("rampa máx %.1f%% / mín %.1f%%; curvatura vertical máx %.4f (raio %.0f m)" % (
        grade.max(), grade.min(), np.abs(vc).max(), 1.0 / max(np.abs(vc).max(), 1e-9)))


def main():
    global DEBUG
    if "--debug" in sys.argv:
        DEBUG = sys.argv[sys.argv.index("--debug") + 1]
        os.makedirs(DEBUG, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    dense, total = centerline()
    tunnel = tunnel_range(dense)
    elev, marks = elevation(dense, total)
    for s, z, name in marks:
        print("  %-18s s=%6.0f z=%5.1f (perfil %5.1f)" % (name, s, z, elev[int(s)]))
    print("túnel: s %.0f a %.0f (%.0f m)" % (tunnel[0], tunnel[1], tunnel[1] - tunnel[0]))
    check_profile(elev, dense)
    half = widths(dense, total, marks, tunnel)
    write_csv(dense, total, elev, half)
    line, lat = raceline(dense, half)
    write_raceline(line)
    print("linha de corrida: deslocamento %.1f a %.1f m" % (lat.min(), lat.max()))
    city = City(dense, total, elev, half, tunnel)
    city.build()
    city.write()


# ---------------------------------------------------------------------------
# Cidade
# ---------------------------------------------------------------------------
# Áreas planas no nível da pista além da barreira: (s inicial, s final, lado, profundidade a partir
# da borda). Manter igual às arquibancadas e aos boxes de resources/tracks/monaco_layout.tres
# (lado: +1 esquerda, -1 direita).
PIT = dict(entry=-250.0, exit=140.0, side=-1, lane=3.0 + 12.0, center=-50.0, building=140.0, depth=20.0)
FLAT_ZONES = [
    (-215.0, -95.0, 1, 26.0),   # Tribuna Prince Pierre (reta dos boxes)
    (175.0, 240.0, -1, 24.0),   # Sainte Dévote
    (2380.0, 2520.0, 1, 24.0),  # Piscine, lado do porto
    (2860.0, 2930.0, 1, 22.0),  # Rascasse
]
BARRIER = 1.6  # distância padrão da barreira (monaco_layout.tres)
# Barreiras mais afastadas (áreas de escape): (s inicial, s final, lado, distância; lado 0 = os dois)
BARRIER_ZONES = [
    (170.0, 250.0, 1, 6.0),      # Sainte Dévote
    (1230.0, 1280.0, -1, 3.0),   # grampo do Grand Hotel
    (2080.0, 2150.0, 0, 5.0),    # Nouvelle Chicane
    (2870.0, 2925.0, 1, 3.0),    # Rascasse
]

# Paleta das fachadas (tons de Mônaco: creme, ocre, pêssego, rosa, branco, amarelo claro)
FACADES = ["f1d9a8", "e9b98a", "e7a98a", "d9876b", "f4e3b5", "f6efe2", "e6c27a", "c9d3d6",
           "efc7b5", "dcb48f", "f2d7c2", "fbf6ec", "e8cf8f", "d99a7c"]
BOAT_TYPES = {"super": 0, "motor": 1, "sail": 2, "small": 3}
# Marcos (nós do OSM) que ganham acabamento próprio no jogo: o prédio que contém o ponto
LANDMARK_NODES = {
    "casino": (43.73916, 7.428022),      # Casino de Monte-Carlo
    "hotel_paris": (43.739006, 7.427463),  # Hôtel de Paris
    "fairmont": (43.739992, 7.429937),     # Fairmont (sobre o grampo e o túnel)
    "metropole": (43.740933, 7.427923),    # Hôtel Métropole
    "hermitage": (43.738463, 7.425958),    # Hôtel Hermitage
}


def simplify_closed(pts, tol):
    """Douglas-Peucker num polígono fechado (tira os vértices colineares das arestas reamostradas)."""
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
    # Corta no vértice mais distante do primeiro
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
    import zlib
    return base64.b64encode(zlib.compress(np.ascontiguousarray(arr).tobytes(), 9)).decode("ascii")


class City:
    def __init__(self, dense, total, elev, half, tunnel):
        self.dense, self.total, self.elev, self.half, self.tunnel = dense, total, elev, half, tunnel
        x0, y0, x1, y1 = AREA
        self.nx = int(round((x1 - x0) / CELL)) + 1
        self.ny = int(round((y1 - y0) / CELL)) + 1
        self.gx = x0 + np.arange(self.nx) * CELL
        self.gy = y0 + np.arange(self.ny) * CELL
        n = len(dense)
        t = np.roll(dense, -1, axis=0) - np.roll(dense, 1, axis=0)
        t /= np.hypot(t[:, 0], t[:, 1])[:, None]
        self.tang = t
        self.left = np.stack([-t[:, 1], t[:, 0]], axis=1)  # esquerda de quem pilota (x leste, y norte)
        self.n = n

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
        for a in range(0, px.size, 4000):
            qx, qy = px.flat[a:a + 4000], py.flat[a:a + 4000]
            dd = (qx[:, None] - d[None, :, 0]) ** 2 + (qy[:, None] - d[None, :, 1]) ** 2
            k = np.argmin(dd, axis=1)
            s.flat[a:a + 4000] = k
            dist.flat[a:a + 4000] = np.sqrt(dd[np.arange(len(k)), k])
            lat.flat[a:a + 4000] = (qx - d[k, 0]) * self.left[k, 0] + (qy - d[k, 1]) * self.left[k, 1]
        return s, lat, dist

    def side_extent(self, s, side):
        """Até onde vai a área plana (no nível da pista) a partir da linha central, num lado."""
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

    def in_tunnel(self, s, margin=0.0):
        return self.tunnel[0] - margin <= s <= self.tunnel[1] + margin

    # -- etapas ----------------------------------------------------------------
    def build(self):
        self.sea_mask()
        self.terrain()
        self.quays()
        self.buildings()
        self.streets()
        self.water_and_parks()
        self.trees()
        self.piers_and_boats()
        if DEBUG:
            self.debug_image()

    def corridor_polygon(self, extra_fn):
        """Polígono (lista de pontos) do corredor da pista com meia-largura variável por lado."""
        left, right = [], []
        for i in range(0, self.n, 2):
            p = self.dense[i]
            left.append(tuple(p + self.left[i] * extra_fn(i, 1)))
            right.append(tuple(p - self.left[i] * extra_fn(i, -1)))
        return left, right

    def sea_mask(self):
        img = self.mask()
        dr = ImageDraw.Draw(img)
        coast = [g for tags, g, wid in ways_of("coast.json")]
        self.coast_exits = []
        ends = {}
        for g in coast:
            for p in (g[0], g[-1]):
                ends[p] = ends.get(p, 0) + 1
        for g in coast:
            dr.line([self.to_px(*p) for p in g], fill=255, width=3)
            # Pontas soltas (a costa continua fora da área baixada): prolonga até sair da área
            for a, b in ((g[1], g[0]), (g[-2], g[-1])):
                near_edge = (b[0] < AREA[0] + 40 or b[0] > AREA[2] - 40 or b[1] < AREA[1] + 40 or b[1] > AREA[3] - 40)
                if ends[b] == 1 and near_edge:
                    d = np.array(b) - np.array(a)
                    d /= max(np.hypot(*d), 1e-9)
                    self.coast_exits.append([round(b[0], 1), round(b[1], 1), round(float(d[0]), 3), round(float(d[1]), 3)])
                    far = tuple(np.array(b) + d * 2000.0)
                    dr.line([self.to_px(*b), self.to_px(*far)], fill=255, width=3)
        for tags, g, wid in ways_of("piers.json"):
            if tags.get("man_made") == "breakwater":
                dr.polygon([self.to_px(*p) for p in g], fill=255)
        # A pista, os boxes e as áreas planas são sempre terra (fecha a água que caberia ali)
        left, right = self.corridor_polygon(lambda i, side: self.side_extent(i, side) + 3.0)
        for k in range(len(left)):
            a, b = left[k], left[(k + 1) % len(left)]
            c, d = right[(k + 1) % len(right)], right[k]
            dr.polygon([self.to_px(*q) for q in (a, b, c, d)], fill=255)
        seeds = [(1100.0, -300.0), (1100.0, 300.0), (1100.0, -580.0), (1100.0, 800.0)]
        for sx, sy in seeds:
            px = tuple(int(v) for v in self.to_px(sx, sy))
            if img.getpixel(px) == 0:
                ImageDraw.floodfill(img, px, 128)
        a = np.array(img)
        sea = a == 128
        # O porto: a bacia ligada ao mar aberto pela entrada entre os quebra-mares
        self.sea1 = sea  # 1 m, linhas = norte→sul
        # Vértices da grade (4 m)
        ix = ((self.gx - AREA[0])).astype(int)
        iy = ((AREA[3] - self.gy)).astype(int)
        self.sea = np.ascontiguousarray(sea[np.clip(iy, 0, sea.shape[0] - 1)][:, np.clip(ix, 0, sea.shape[1] - 1)])  # [ny, nx]
        print("mar: %.0f%% da área" % (100.0 * sea.mean()))

    def dist_to_sea(self):
        """Distância aproximada (m) de cada vértice de terra até o mar (dilatações sucessivas)."""
        land = ~self.sea
        d = np.where(land, np.inf, 0.0)
        front = ~land
        step = 0
        cur = front.copy()
        while True:
            step += 1
            grown = cur.copy()
            grown[1:] |= cur[:-1]
            grown[:-1] |= cur[1:]
            grown[:, 1:] |= cur[:, :-1]
            grown[:, :-1] |= cur[:, 1:]
            new = grown & ~cur
            if not new.any() or step > 600:
                break
            d[new] = step * CELL
            cur = grown
        d[np.isinf(d)] = 600 * CELL
        return d

    def terrain(self):
        X, Y = np.meshgrid(self.gx, self.gy)  # [ny, nx]
        land = ~self.sea
        dsea = self.dist_to_sea()
        # Encosta: sobe para o interior (Monte Carlo fica entre o mar e a Moyenne Corniche)
        hill = np.minimum(QUAY + 0.14 * np.maximum(dsea - 8.0, 0.0), 165.0)
        h = np.where(land, hill, SEA_FLOOR)
        fixed = ~land
        cls = np.zeros(X.shape, np.uint8)
        # Vértices perto da pista: altura da pista (o chão fica logo abaixo do asfalto). Onde dois
        # trechos ficam perto (o Mirabeau passa a 14 m do Mirabeau Bas, 8 m acima), vale o mais baixo:
        # o de cima fica sobre o muro de contenção (barreira com saia) e o chão não invade o de baixo.
        n = self.n
        ext_l = np.array([self.side_extent(j, 1) for j in range(n)])
        ext_r = np.array([self.side_extent(j, -1) for j in range(n)])
        tunnel_pt = np.array([self.in_tunnel(j, -4.0) for j in range(n)])
        near_tunnel = np.array([self.in_tunnel(j, 6.0) for j in range(n)])
        d = self.dense
        near = land & (np.abs(X - 400) < 2000)
        idx = np.where(near.ravel())[0]
        s, lat, dist = self.project(X.ravel()[idx], Y.ravel()[idx])
        target = np.full(idx.shape, np.nan)
        cl = np.zeros(idx.shape, np.uint8)
        close = np.where(dist < 60.0)[0]
        for a in range(0, len(close), 800):
            ks = close[a:a + 800]
            qx = X.ravel()[idx[ks]]
            qy = Y.ravel()[idx[ks]]
            dx = qx[:, None] - d[None, :, 0]
            dy = qy[:, None] - d[None, :, 1]
            D = np.hypot(dx, dy)
            L = dx * self.left[None, :, 0] + dy * self.left[None, :, 1]
            ext = np.where(L >= 0, ext_l[None, :], ext_r[None, :])
            z = self.elev[None, :]
            # A pista mais baixa vale numa faixa 6 m mais larga (a célula de 4 m não pode subir
            # para o trecho de cima por cima da borda dela)
            road_in = (D < ext) & ~tunnel_pt[None, :]
            road = (D < ext + 6.0) & ~tunnel_pt[None, :]
            tun = (D < self.half[None, :] + 11.0) & tunnel_pt[None, :]
            walk = (D < ext + 5.0) & ~near_tunnel[None, :]
            z_road = np.where(road, z, np.inf).min(axis=1)
            z_tun = np.where(tun, z, np.inf).min(axis=1)
            z_walk = np.where(walk, z, np.inf).min(axis=1)
            d_tun = np.where(tun, D - self.half[None, :], np.inf).min(axis=1)
            in_road = road_in.any(axis=1)
            for m, k in enumerate(ks):
                if in_road[m]:
                    target[k] = z_road[m] - 0.4
                    cl[k] = 1
                elif np.isfinite(z_tun[m]):
                    target[k] = z_tun[m] + TUNNEL_ROOF + 0.35
                    cl[k] = 2 if d_tun[m] < 6.5 else 3
                elif np.isfinite(z_walk[m]):
                    target[k] = z_walk[m] + 0.15  # calçada
                    cl[k] = 4
        # Perto da pista o chão tende à altura dela (as ruas e os prédios ficam no nível da rua)
        soft_w = np.full(h.shape, 0.015)
        soft_t = hill.copy()
        for k in range(len(idx)):
            i = int(s[k])
            ext = ext_l[i] if lat[k] >= 0 else ext_r[i]
            wt = 0.6 * math.exp(-(max(dist[k] - ext, 0.0) / 28.0) ** 2)
            if wt > 0.01 and not near_tunnel[i]:
                soft_t.flat[idx[k]] = (wt * self.elev[i] + 0.015 * hill.flat[idx[k]]) / (wt + 0.015)
                soft_w.flat[idx[k]] = wt + 0.015
        ok = ~np.isnan(target)
        h.flat[idx[ok]] = target[ok]
        fixed.flat[idx[ok]] = True
        cls.flat[idx] = cl
        # Relaxação (Laplace só entre vértices de terra) com termo fraco puxando para a encosta
        lf = land.astype(float)
        for it in range(2500):
            hp = np.pad(h, 1, mode="edge")
            lp = np.pad(lf, 1, mode="edge")
            num = (hp[:-2, 1:-1] * lp[:-2, 1:-1] + hp[2:, 1:-1] * lp[2:, 1:-1]
                   + hp[1:-1, :-2] * lp[1:-1, :-2] + hp[1:-1, 2:] * lp[1:-1, 2:])
            cnt = lp[:-2, 1:-1] + lp[2:, 1:-1] + lp[1:-1, :-2] + lp[1:-1, 2:]
            new = (num + soft_w * soft_t) / (cnt + soft_w)
            h = np.where(fixed, h, new)
        # Junto ao mar o chão afunda sob o cais (o cais é desenhado à parte, com a altura certa)
        self.ground = h.copy()
        coast = land & (dsea <= CELL * 0.75) & (cls == 0)
        h = np.where(coast, -0.6, h)
        self.h = h
        self.cls = cls
        self.dsea = dsea
        print("terreno: %dx%d vértices, %.1f a %.1f m" % (self.nx, self.ny, h[land].min(), h.max()))

    def height_at(self, x, y):
        """Altura do chão (antes do afundamento junto ao cais), bilinear."""
        fx = (np.asarray(x) - AREA[0]) / CELL
        fy = (np.asarray(y) - AREA[1]) / CELL
        ix = np.clip(np.floor(fx).astype(int), 0, self.nx - 2)
        iy = np.clip(np.floor(fy).astype(int), 0, self.ny - 2)
        tx, ty = np.clip(fx - ix, 0, 1), np.clip(fy - iy, 0, 1)
        g = self.ground
        return (g[iy, ix] * (1 - tx) * (1 - ty) + g[iy, ix + 1] * tx * (1 - ty)
                + g[iy + 1, ix] * (1 - tx) * ty + g[iy + 1, ix + 1] * tx * ty)

    def quays(self):
        """Muros do cais: contorno do mar (marching squares na máscara de 1 m), em segmentos."""
        sea = self.sea1
        h, w = sea.shape
        a = sea[:-1, :-1].astype(np.uint8)
        b = sea[:-1, 1:].astype(np.uint8)
        c = sea[1:, 1:].astype(np.uint8)
        d = sea[1:, :-1].astype(np.uint8)
        code = a * 8 + b * 4 + c * 2 + d
        rows, cols = np.where((code != 0) & (code != 15))
        # Pontos médios das arestas da célula (x à direita, y para baixo no raster)
        edges = {0: (0.5, 0.0), 1: (1.0, 0.5), 2: (0.5, 1.0), 3: (0.0, 0.5)}
        table = {1: [(3, 2)], 2: [(2, 1)], 3: [(3, 1)], 4: [(0, 1)], 5: [(3, 0), (2, 1)], 6: [(0, 2)],
                 7: [(3, 0)], 8: [(0, 3)], 9: [(0, 2)], 10: [(0, 1), (3, 2)], 11: [(0, 1)], 12: [(3, 1)],
                 13: [(2, 1)], 14: [(3, 2)]}
        segs = []
        for r, cidx in zip(rows, cols):
            for e0, e1 in table[int(code[r, cidx])]:
                p0 = (AREA[0] + cidx + 0.5 + edges[e0][0], AREA[3] - (r + 0.5 + edges[e0][1]))
                p1 = (AREA[0] + cidx + 0.5 + edges[e1][0], AREA[3] - (r + 0.5 + edges[e1][1]))
                segs.append((p0, p1))
        # Junta segmentos colineares em pedaços de até ~4 m (menos geometria)
        segs = np.array(segs)  # [n, 2, 2]
        mid = segs.mean(axis=1)
        # Normal para o lado de terra: amostra a máscara dos dois lados
        dv = segs[:, 1] - segs[:, 0]
        nrm = np.stack([-dv[:, 1], dv[:, 0]], axis=1)
        nrm /= np.maximum(np.hypot(nrm[:, 0], nrm[:, 1]), 1e-9)[:, None]
        probe = mid + nrm * 1.5
        px = np.clip(((probe[:, 0] - AREA[0])).astype(int), 0, w - 1)
        py = np.clip(((AREA[3] - probe[:, 1])).astype(int), 0, h - 1)
        flip = sea[py, px]  # a normal apontava para o mar: inverte
        nrm[flip] *= -1
        inland = mid + nrm * 7.0
        top = np.maximum(self.height_at(inland[:, 0], inland[:, 1]), QUAY)
        # Dentro da área do terreno, sem os que caem na borda do raster
        keep = (mid[:, 0] > AREA[0] + 4) & (mid[:, 0] < AREA[2] - 4) & (mid[:, 1] > AREA[1] + 4) & (mid[:, 1] < AREA[3] - 4)
        self.quay = [(float(s[0, 0]), float(s[0, 1]), float(s[1, 0]), float(s[1, 1]), float(nx_), float(ny_), float(t))
                     for s, nx_, ny_, t, k in zip(segs, nrm[:, 0], nrm[:, 1], top, keep) if k]
        print("cais: %d segmentos" % len(self.quay))

    def buildings(self):
        out = []
        dropped = 0
        trimmed = 0
        seen = set()
        rng = np.random.default_rng(5)
        for name in ("b_sw.json", "b_se.json", "b_nw.json", "b_ne.json"):
            for tags, g, wid in ways_of(name):
                if wid in seen and tags.get("type") != "multipolygon":
                    continue
                seen.add(wid)
                if len(g) < 4:
                    continue
                pts = np.array(g[:-1] if g[0] == g[-1] else g)
                if not ((pts[:, 0] > AREA[0] + 10).all() and (pts[:, 0] < AREA[2] - 10).all()
                        and (pts[:, 1] > AREA[1] + 10).all() and (pts[:, 1] < AREA[3] - 10).all()):
                    continue
                area = 0.5 * abs(np.dot(pts[:, 0], np.roll(pts[:, 1], 1)) - np.dot(pts[:, 1], np.roll(pts[:, 0], 1)))
                if area < 15.0:
                    continue
                # Arestas a cada 2 m: o que invadir a pista (fora do túnel) é empurrado para trás da
                # calçada; invasões grandes (boxes, arquibancadas) removem o prédio
                samples = []
                for a, b in zip(pts, np.roll(pts, -1, axis=0)):
                    k = max(int(np.hypot(*(b - a)) / 2.0), 1)
                    samples.extend(a + (b - a) * t / k for t in range(k))
                samples = np.array(samples)
                s, lat, dist = self.project(samples[:, 0], samples[:, 1])
                over_tunnel = False
                bad = False
                pushed = False
                for k in range(len(samples)):
                    i = int(s[k])
                    side = 1 if lat[k] >= 0 else -1
                    clear = self.side_extent(i, side) + 0.3
                    if self.in_tunnel(i, -2.0) and dist[k] < self.half[i] + 12.0:
                        over_tunnel = True
                    elif dist[k] < clear:
                        if clear - dist[k] > 9.0:
                            bad = True
                            break
                        samples[k] = self.dense[i] + self.left[i] * side * clear
                        pushed = True
                if bad:
                    dropped += 1
                    if DEBUG and area > 400:
                        print("    removido: %s (%s) %.0f m² em %.0f,%.0f" % (tags.get("name", "?"), tags.get("building"), area, *pts.mean(axis=0)))
                    continue
                if pushed:
                    pts = simplify_closed(samples, 0.35)
                    trimmed += 1
                # Planta que ainda cobre a pista (vértices empurrados para os dois lados da rua): fora
                lo, hi = pts.min(axis=0), pts.max(axis=0)
                d = self.dense
                near = np.where((d[:, 0] >= lo[0]) & (d[:, 0] <= hi[0]) & (d[:, 1] >= lo[1]) & (d[:, 1] <= hi[1]))[0]
                if any(point_in_poly(tuple(d[i]), pts) and not self.in_tunnel(i, -1.0) for i in near):
                    dropped += 1
                    if DEBUG:
                        print("    removido (cobre a pista): %s" % tags.get("name", "?"))
                    continue
                gh = self.height_at(pts[:, 0], pts[:, 1])
                base = float(gh.min()) - 0.6
                if over_tunnel:
                    i = int(np.median(s))
                    base = max(base, float(self.elev[i]) + TUNNEL_ROOF + 0.4)
                # Altura: etiquetas do OSM ou estimativa pelo tamanho
                height = None
                try:
                    if "height" in tags:
                        height = float(str(tags["height"]).split()[0].replace(",", "."))
                    elif "building:levels" in tags:
                        height = float(tags["building:levels"]) * 3.3 + 1.0
                except ValueError:
                    height = None
                kind = tags.get("building", "yes")
                if height is None:
                    if kind in ("house", "detached", "garage", "shed", "roof", "kiosk", "hut"):
                        height = rng.uniform(4.0, 9.0)
                    elif area < 120:
                        height = rng.uniform(8.0, 16.0)
                    else:
                        height = rng.uniform(14.0, 34.0) + min(area / 400.0, 12.0)
                height = float(np.clip(height, 3.0, 190.0))
                top = float(gh.max()) + height
                if kind == "roof":
                    base = top - 0.6
                # Orientação anti-horária (vista de cima, x leste / y norte)
                signed = np.dot(pts[:, 0], np.roll(pts[:, 1], -1)) - np.dot(pts[:, 1], np.roll(pts[:, 0], -1))
                if signed < 0:
                    pts = pts[::-1]
                roof = 1 if (height < 13.0 and rng.random() < 0.55) else 0  # 1 = telha
                lm = ""
                for key, (la, lo) in LANDMARK_NODES.items():
                    if point_in_poly(xy(la, lo), pts):
                        lm = key
                if lm == "casino":
                    top = float(gh.max()) + 21.0
                elif lm in ("hotel_paris", "hermitage", "metropole"):
                    top = max(top, float(gh.max()) + 26.0)
                out.append({
                    "p": [round(float(v), 2) for v in pts.ravel()],
                    "b": round(base, 2), "t": round(top, 2),
                    "c": int(rng.integers(len(FACADES))), "r": roof,
                    "n": tags.get("name", ""), "lm": lm,
                })
        self.blds = out
        print("prédios: %d (%d recortados e %d removidos por invadir a pista)" % (len(out), trimmed, dropped))

    def streets(self):
        widths = {"primary": 11.0, "secondary": 9.0, "tertiary": 8.0, "residential": 6.5, "unclassified": 6.5,
                  "living_street": 5.0, "pedestrian": 5.0, "service": 4.5}
        out = []
        for tags, g, wid in ways_of("roads.json"):
            hw = tags.get("highway")
            if hw not in widths or tags.get("tunnel") in ("yes", "building_passage") or tags.get("layer", "0").startswith("-"):
                continue
            pts = np.array(g)
            # Densifica a cada ~4 m
            dense = [pts[0]]
            for a, b in zip(pts[:-1], pts[1:]):
                k = max(int(np.hypot(*(b - a)) / 4.0), 1)
                dense.extend(a + (b - a) * t / k for t in range(1, k + 1))
            dense = np.array(dense)
            inside = ((dense[:, 0] > AREA[0] + 8) & (dense[:, 0] < AREA[2] - 8)
                      & (dense[:, 1] > AREA[1] + 8) & (dense[:, 1] < AREA[3] - 8))
            s, lat, dist = self.project(dense[:, 0], dense[:, 1])
            clear = np.array([dist[k] > self.side_extent(int(s[k]), 1 if lat[k] >= 0 else -1) + widths[hw] * 0.5 + 1.0
                              and not (self.in_tunnel(int(s[k]), 10.0) and dist[k] < 25.0) for k in range(len(dense))])
            ok = inside & clear
            px = np.clip(((dense[:, 0] - AREA[0])).astype(int), 0, self.sea1.shape[1] - 1)
            py = np.clip(((AREA[3] - dense[:, 1])).astype(int), 0, self.sea1.shape[0] - 1)
            ok &= ~self.sea1[py, px]
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
            if tags.get("leisure") == "marina" or tags.get("water") == "basin":
                continue  # é o próprio mar
            px = np.clip(((pts[:, 0] - AREA[0])).astype(int), 0, self.sea1.shape[1] - 1)
            py = np.clip(((AREA[3] - pts[:, 1])).astype(int), 0, self.sea1.shape[0] - 1)
            if self.sea1[py, px].mean() > 0.5:
                continue
            s, lat, dist = self.project(pts[:, 0], pts[:, 1])
            if any(dist[k] < self.side_extent(int(s[k]), 1 if lat[k] >= 0 else -1) + 1.0 for k in range(len(pts))):
                continue
            z = float(self.height_at(pts[:, 0], pts[:, 1]).max()) + 0.1
            signed = np.dot(pts[:, 0], np.roll(pts[:, 1], -1)) - np.dot(pts[:, 1], np.roll(pts[:, 0], -1))
            if signed < 0:
                pts = pts[::-1]
            pools.append({"p": [round(float(v), 2) for v in pts.ravel()], "z": round(z, 2)})
        self.pools = pools
        # Parques: cobertura por vértice (0 calçada, 1 grama)
        img = self.mask(CELL)
        dr = ImageDraw.Draw(img)
        self.park_polys = []
        for tags, g, wid in ways_of("green.json"):
            if len(g) >= 4:
                dr.polygon([self.to_px(x, y, CELL) for x, y in g], fill=1)
                self.park_polys.append(np.array(g))
        cover = np.array(img)[::-1][: self.ny, : self.nx]  # linhas sul→norte, igual à grade
        cover = np.where(self.sea, 0, cover)
        cover = np.where(self.cls == 0, cover, 0)
        self.cover = cover.astype(np.uint8)
        print("piscinas: %d; parques: %d" % (len(pools), len(self.park_polys)))

    def building_mask(self):
        img = self.mask()
        dr = ImageDraw.Draw(img)
        for b in self.blds:
            p = np.array(b["p"]).reshape(-1, 2)
            dr.polygon([self.to_px(x, y) for x, y in p], fill=255)
        for st in self.street:
            p = np.array(st["p"]).reshape(-1, 3)
            dr.line([self.to_px(x, y) for x, y, z in p], fill=255, width=int(st["w"]))
        return np.array(img) > 0

    def trees(self):
        rng = np.random.default_rng(9)
        blocked = self.building_mask() | self.sea1
        hgt, wid = blocked.shape
        trees = []

        def free(x, y, r=2):
            px, py = int(x - AREA[0]), int(AREA[3] - y)
            if px < r or py < r or px >= wid - r or py >= hgt - r:
                return False
            return not blocked[py - r:py + r + 1, px - r:px + r + 1].any()

        def add(x, y, kind):
            s, lat, dist = self.project(np.array([x]), np.array([y]))
            i = int(s[0])
            if dist[0] < self.side_extent(i, 1 if lat[0] >= 0 else -1) + 2.0 or (self.in_tunnel(i, 8.0) and dist[0] < 20):
                return
            if not free(x, y):
                return
            z = float(self.height_at(np.array([x]), np.array([y]))[0])
            trees.extend([round(x, 2), round(y, 2), round(z, 2), kind])
            px, py = int(x - AREA[0]), int(AREA[3] - y)
            blocked[py - 3:py + 4, px - 3:px + 4] = True

        # Parques: árvores e palmeiras
        for poly in self.park_polys:
            xmin, ymin = poly.min(axis=0)
            xmax, ymax = poly.max(axis=0)
            area = (xmax - xmin) * (ymax - ymin)
            img = Image.new("L", (int(xmax - xmin) + 2, int(ymax - ymin) + 2), 0)
            ImageDraw.Draw(img).polygon([(x - xmin, ymax - y) for x, y in poly], fill=1)
            m = np.array(img)
            for _ in range(int(area / 55.0)):
                x, y = rng.uniform(xmin, xmax), rng.uniform(ymin, ymax)
                if m[int(ymax - y), int(x - xmin)]:
                    add(float(x), float(y), 1 if rng.random() < 0.3 else 0)
        # Palmeiras ao longo do porto (atrás do cais)
        for k in range(0, len(self.quay), 9):
            x0, y0, x1, y1, nx_, ny_, top = self.quay[k]
            if top > 6.0:
                continue
            add((x0 + x1) * 0.5 + nx_ * 6.0, (y0 + y1) * 0.5 + ny_ * 6.0, 1)
        self.tree = trees
        print("árvores: %d" % (len(trees) // 4))

    def piers_and_boats(self):
        rng = np.random.default_rng(21)
        sea = self.sea1
        occ = np.zeros_like(sea)
        hgt, wid = sea.shape
        piers = []
        # Pontões flutuantes: polígonos (áreas finas) ou linhas com 2,6 m de largura
        img = Image.new("L", (wid, hgt), 0)
        dr = ImageDraw.Draw(img)
        moor = []  # bordas onde os barcos atracam: (a, b, normal para fora)
        for tags, g, wid_ in ways_of("piers.json"):
            if tags.get("man_made") != "pier":
                continue
            pts = np.array(g)
            px = np.clip(((pts[:, 0] - AREA[0])).astype(int), 0, wid - 1)
            py = np.clip(((AREA[3] - pts[:, 1])).astype(int), 0, hgt - 1)
            if sea[py, px].mean() < 0.5:
                continue  # píer em terra / fora da área
            closed = len(g) > 3 and g[0] == g[-1]
            if closed:
                poly = pts[:-1]
                signed = np.dot(poly[:, 0], np.roll(poly[:, 1], -1)) - np.dot(poly[:, 1], np.roll(poly[:, 0], -1))
                if signed < 0:
                    poly = poly[::-1]
                piers.append({"poly": [round(float(v), 2) for v in poly.ravel()]})
                dr.polygon([self.to_px(x, y) for x, y in poly], fill=255)
                for a, b in zip(poly, np.roll(poly, -1, axis=0)):
                    t = (b - a) / max(np.hypot(*(b - a)), 1e-9)
                    moor.append((a, b, np.array([t[1], -t[0]])))  # anti-horário: normal externa à direita
            else:
                piers.append({"line": [round(float(v), 2) for v in pts.ravel()], "w": 2.6})
                dr.line([self.to_px(x, y) for x, y in pts], fill=255, width=4)
                for a, b in zip(pts[:-1], pts[1:]):
                    t = (b - a) / max(np.hypot(*(b - a)), 1e-9)
                    nrm = np.array([-t[1], t[0]])
                    moor.append((a + nrm * 1.3, b + nrm * 1.3, nrm))
                    moor.append((b - nrm * 1.3, a - nrm * 1.3, -nrm))
        occ |= np.array(img) > 0

        def footprint(x, y, hd, length, beam):
            c, s = math.cos(hd), math.sin(hd)
            pts = []
            for u in np.linspace(-0.5, 0.5, max(int(length / 2), 2)):
                for v in np.linspace(-0.5, 0.5, max(int(beam / 2), 2)):
                    pts.append((x + c * u * length - s * v * beam, y + s * u * length + c * v * beam))
            return pts

        def fits(pts, margin=1.0):
            for x, y in pts:
                px, py = int(x - AREA[0]), int(AREA[3] - y)
                if px < 2 or py < 2 or px >= wid - 2 or py >= hgt - 2:
                    return False
                if not sea[py, px] or occ[py, px]:
                    return False
            return True

        def mark(x, y, hd, length, beam):
            img = Image.new("L", (wid, hgt), 0)
            c, s = math.cos(hd), math.sin(hd)
            corners = [(x + c * u * (length + 2) - s * v * (beam + 2), y + s * u * (length + 2) + c * v * (beam + 2))
                       for u, v in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5))]
            ImageDraw.Draw(img).polygon([self.to_px(*p) for p in corners], fill=1)
            occ[:] |= np.array(img) > 0

        boats = []

        def place(x, y, hd, length, kind):
            beam = length * (0.2 if kind != "sail" else 0.3) + 1.2
            pts = footprint(x, y, hd, length, beam)
            if not fits(pts):
                return False
            mark(x, y, hd, length, beam)
            boats.extend([round(x, 2), round(y, 2), round(hd, 3), round(length, 1), BOAT_TYPES[kind], int(rng.integers(6))])
            return True

        # Ao longo dos píeres (pontões): barcos perpendiculares, popa para o píer
        for a, b, nrm in moor:
            seg = b - a
            L = float(np.hypot(*seg))
            if L < 6:
                continue
            t = seg / L
            u = 2.0
            while u < L - 2.0:
                kind = "sail" if rng.random() < 0.35 else ("motor" if rng.random() < 0.75 else "small")
                length = {"sail": rng.uniform(9, 16), "motor": rng.uniform(11, 26), "small": rng.uniform(6, 9)}[kind]
                beam = length * (0.3 if kind == "sail" else 0.2) + 1.2
                c = a + t * (u + beam * 0.5) + nrm * (0.6 + length * 0.5)
                hd = math.atan2(nrm[1], nrm[0])  # proa para longe do píer
                if place(float(c[0]), float(c[1]), hd, length, kind):
                    u += beam + 0.9
                else:
                    u += 2.0
        # Iates grandes atracados de popa no cais (dentro do porto)
        harbour = (-20.0, -260.0, 560.0, 330.0)
        for k in range(0, len(self.quay), 2):
            x0, y0, x1, y1, nx_, ny_, top = self.quay[k]
            mx, my = (x0 + x1) * 0.5, (y0 + y1) * 0.5
            if not (harbour[0] < mx < harbour[2] and harbour[1] < my < harbour[3]):
                continue
            if rng.random() < 0.5:
                continue
            length = float(rng.uniform(28, 75) if rng.random() < 0.6 else rng.uniform(18, 30))
            kind = "super" if length > 30 else "motor"
            hd = math.atan2(-ny_, -nx_)  # proa para a água
            place(mx - nx_ * (length * 0.5 + 1.2), my - ny_ * (length * 0.5 + 1.2), hd, length, kind)
        # Superiates fundeados fora do porto e alguns veleiros
        tries = 0
        count = 0
        while count < 22 and tries < 4000:
            tries += 1
            x, y = rng.uniform(300, 1120), rng.uniform(-590, 1040)
            px, py = int(x - AREA[0]), int(AREA[3] - y)
            if not sea[py, px] or self.dsea_at(x, y) < 0:
                continue
            if harbour[0] < x < harbour[2] + 150 and harbour[1] < y < harbour[3]:
                continue
            kind = "super" if rng.random() < 0.65 else "sail"
            length = float(rng.uniform(45, 110) if kind == "super" else rng.uniform(14, 28))
            if place(x, y, float(rng.uniform(-math.pi, math.pi)), length, kind):
                count += 1
        self.piers = piers
        self.boats = boats
        print("píeres: %d; barcos: %d" % (len(piers), len(boats) // 6))

    def dsea_at(self, x, y):
        """Distância (m) até a costa a partir de um ponto do mar (negativo = perto demais)."""
        sea = self.sea1
        px, py = int(x - AREA[0]), int(AREA[3] - y)
        r = 60
        win = sea[max(py - r, 0):py + r, max(px - r, 0):px + r]
        return 1.0 if win.all() else -1.0

    def shore_texture(self):
        """Textura do mar (2 m/pixel): R = distância até a terra (0..48 m), G = porto (água calma)."""
        sea = self.sea1[::2, ::2]
        land = ~sea
        dist = np.where(land, 0.0, 255.0)
        cur = land.copy()
        for step in range(1, 25):
            grown = cur.copy()
            grown[1:] |= cur[:-1]
            grown[:-1] |= cur[1:]
            grown[:, 1:] |= cur[:, :-1]
            grown[:, :-1] |= cur[:, 1:]
            new = grown & ~cur
            dist[new] = step * 2.0 * 255.0 / 48.0
            cur = grown
        img = Image.new("L", (sea.shape[1], sea.shape[0]), 0)
        hx0, hy0 = self.to_px(-30.0, 360.0, 2.0)
        hx1, hy1 = self.to_px(640.0, -280.0, 2.0)
        ImageDraw.Draw(img).rectangle([hx0, hy0, hx1, hy1], fill=255)
        calm = np.array(img, dtype=float)
        # Borda suave do porto (média móvel)
        for _ in range(12):
            calm = (np.roll(calm, 1, 0) + np.roll(calm, -1, 0) + np.roll(calm, 1, 1) + np.roll(calm, -1, 1) + calm) / 5.0
        rgb = np.stack([np.clip(dist, 0, 255), calm, np.zeros_like(calm)], axis=2).astype(np.uint8)
        Image.fromarray(rgb, "RGB").save(os.path.join(OUT, "monaco_shore.png"))

    def write(self):
        self.shore_texture()
        data = {
            "source": "OpenStreetMap (ODbL) - Circuit de Monaco; gerado por tools/build_monaco.py",
            "area": list(AREA), "cell": CELL, "nx": self.nx, "ny": self.ny,
            "height_cm": b64(np.round(self.h * 100.0).astype("<i2")),
            "cls": b64(self.cls.astype(np.uint8)),
            "cover": b64(self.cover.astype(np.uint8)),
            "tunnel": [self.tunnel[0], self.tunnel[1]], "tunnel_roof": TUNNEL_ROOF,
            "coast_exits": self.coast_exits,
            "facades": FACADES,
            "quays": [round(v, 2) for q in self.quay for v in q],
            "buildings": self.blds,
            "streets": self.street,
            "pools": self.pools,
            "piers": self.piers,
            "trees": self.tree,
            "boats": self.boats,
        }
        path = os.path.join(OUT, "monaco_city.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, separators=(",", ":"), ensure_ascii=False)
        print("cidade: %s (%.0f KB)" % (path, os.path.getsize(path) / 1024))

    def debug_image(self):
        res = 1.0
        img = Image.new("RGB", self.sea1.shape[::-1], (240, 238, 232))
        a = np.array(img)
        hn = self.ground
        # Relevo em tons (grade de 4 m ampliada)
        rel = np.clip((hn - 0) / 80.0, 0, 1)
        rel = np.kron(rel[::-1], np.ones((4, 4)))[: a.shape[0], : a.shape[1]]
        a[..., 0] = (200 + 40 * rel).astype(np.uint8)
        a[..., 1] = (200 + 20 * rel).astype(np.uint8)
        a[..., 2] = (190 - 60 * rel).astype(np.uint8)
        a[self.sea1] = (90, 150, 210)
        img = Image.fromarray(a)
        dr = ImageDraw.Draw(img)
        for b in self.blds:
            p = np.array(b["p"]).reshape(-1, 2)
            dr.polygon([self.to_px(x, y) for x, y in p], fill=(190, 160, 140), outline=(120, 100, 90))
        for st in self.street:
            p = np.array(st["p"]).reshape(-1, 3)
            dr.line([self.to_px(x, y) for x, y, z in p], fill=(150, 150, 150), width=int(st["w"]))
        for q in self.quay[::3]:
            dr.line([self.to_px(q[0], q[1]), self.to_px(q[2], q[3])], fill=(40, 40, 40), width=2)
        for pr in self.piers:
            if "poly" in pr:
                p = np.array(pr["poly"]).reshape(-1, 2)
                dr.polygon([self.to_px(x, y) for x, y in p], fill=(120, 80, 40))
            else:
                p = np.array(pr["line"]).reshape(-1, 2)
                dr.line([self.to_px(x, y) for x, y in p], fill=(120, 80, 40), width=3)
        bt = np.array(self.boats).reshape(-1, 6)
        for x, y, hd, L, kind, col in bt:
            c, s = math.cos(hd), math.sin(hd)
            beam = L * 0.22 + 1.2
            pts = [(x + c * u * L - s * v * beam, y + s * u * L + c * v * beam) for u, v in ((-0.5, -0.5), (0.5, -0.4), (0.55, 0), (0.5, 0.4), (-0.5, 0.5))]
            dr.polygon([self.to_px(*p) for p in pts], fill=(255, 255, 255), outline=(0, 0, 0))
        tr = np.array(self.tree).reshape(-1, 4)
        for x, y, z, k in tr:
            px, py = self.to_px(x, y)
            dr.ellipse([px - 2, py - 2, px + 2, py + 2], fill=(40, 140, 50))
        for i in range(0, self.n, 2):
            q = self.dense[i]
            col = (60, 60, 60) if not self.in_tunnel(i) else (200, 30, 30)
            px, py = self.to_px(*q)
            r = self.half[i]
            dr.ellipse([px - r, py - r, px + r, py + r], fill=col)
        img.save(os.path.join(DEBUG, "monaco_city.png"))
        img.crop(tuple(int(v) for v in (*self.to_px(-40, 360), *self.to_px(620, -300)))).save(os.path.join(DEBUG, "monaco_harbour.png"))
        img.crop(tuple(int(v) for v in (*self.to_px(450, 760), *self.to_px(900, 300)))).save(os.path.join(DEBUG, "monaco_casino.png"))


if __name__ == "__main__":
    main()
