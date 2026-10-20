"""
Gerador procedural do safety car do Speedoru (escala real, metros): cupê GT de motor dianteiro
modelado em cima de fotos do safety car da Fórmula 1 (AMG GT R de 2018): capô longo com saídas de ar,
cabine recuada em fastback, quadris largos, grade de lâminas verticais, splitter, asa traseira baixa,
barra de luzes alta no meio do teto e os grafismos na mesma disposição (emblema e texto nas portas,
"SAFETY CAR / DRIVE SAFELY" no capô, faixa preta nos vidros, placas claras). Onde o carro real leva
o logo da F1 vai o emblema do campeonato do jogo: o jogo só usa marcas próprias.

Uso (a partir da raiz do projeto):
    blender -b --factory-startup -P blender/build_safety_car.py                  # .glb + vistas
    blender -b --factory-startup -P blender/build_safety_car.py -- --no-render
    blender -b --factory-startup -P blender/build_safety_car.py -- --render-dir <pasta> --out <.glb>
    blender -b --factory-startup -P blender/build_safety_car.py -- --all-views   # + teto, roda, topo...

Convenções (as mesmas do carro de F1, de onde vêm as funções de malha, build_f1_car.py):
  * x = lateral (+ esquerda), s = longitudinal (+ frente), z = altura; origem no chão, no meio do
    entre-eixos. No Godot a frente fica em +Z e a esquerda em +X.
  * A carroceria é um loft de seções (perfil de carro: fundo reto, lateral, ombro, crista dos
    para-lamas e capô) e a cabine outro loft por cima. Vidros, faróis, lanternas, grafismos e
    letreiros são "adesivos": contornos 2D triangulados e projetados na carroceria por raycast,
    um pouco acima dela.
  * Saída: assets/car/safety_car/safety_car.glb com "Body" (tudo o que não gira) e
    "Wheel_FL/FR/RL/RR" (origem no cubo, eixo X). Os nomes dos materiais são slots (SC_Paint,
    SC_Stripe, SC_BarAmberL...) que o Godot troca pelos materiais toon da pintura escolhida
    (scripts/race/safety_car.gd).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import delaunay_2d_cdt, interpolate_bezier
from mathutils.kdtree import KDTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_f1_car as f1  # noqa: E402
from build_f1_car import (P, V3, W, Builder, box, catmull, ellipsoid, interp_dicts, lathe,  # noqa: E402
                          plate, radial_box, rod, skin, slab, wing,
                          apply_boolean_difference, export_glb, mesh_stats, new_collection, reset_scene)

ROOT = os.path.dirname(HERE)
OUT_PATH = os.path.join(ROOT, "assets", "car", "safety_car", "safety_car.glb")
FONT_PATH = os.path.join(ROOT, "assets", "fonts", "chakra_petch", "ChakraPetch-Bold.ttf")

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_RENDER = "--no-render" not in ARGS
RENDER_DIR = ARGS[ARGS.index("--render-dir") + 1] if "--render-dir" in ARGS else os.path.join(HERE, "renders", "safety_car")
# Vistas: as quatro principais (as que ficam no repositório) ou todas (--all-views)
ALL_VIEWS = "--all-views" in ARGS
# --out <arquivo.glb>: exporta em outro lugar (testes sem mexer no asset do jogo)
if "--out" in ARGS:
    OUT_PATH = ARGS[ARGS.index("--out") + 1]

# ---------------------------------------------------------------------------
# Dimensões (cupê GT de 4,58 m, entre-eixos de 2,63 m)
# ---------------------------------------------------------------------------
FRONT_AXLE = 1.30
REAR_AXLE = -1.33
WHEEL_R = 0.345
RIM_R = 0.248               # aro de 20"
FRONT_HALF_TRACK = 0.835
REAR_HALF_TRACK = 0.83
FRONT_TYRE_W = 0.285
REAR_TYRE_W = 0.325
ARCH_R = 0.385              # raio da caixa de roda

# Slots de material (cor linear das vistas do Blender; o Godot troca pelos materiais da pintura)
f1.PALETTE.update({
    "SC_Paint": ((0.62, 0.64, 0.68), 0.3, 0.6, 0.0),
    "SC_Accent": ((0.012, 0.012, 0.016), 0.4, 0.0, 0.0),
    "SC_Stripe": ((0.02, 0.02, 0.025), 0.5, 0.0, 0.0),
    "SC_Lettering": ((0.02, 0.02, 0.025), 0.5, 0.0, 0.0),
    "SC_Carbon": ((0.025, 0.025, 0.03), 0.4, 0.0, 0.0),
    "SC_Arch": ((0.012, 0.012, 0.014), 0.9, 0.0, 0.0),
    "SC_Under": ((0.02, 0.02, 0.022), 0.9, 0.0, 0.0),
    "SC_Grille": ((0.008, 0.008, 0.01), 0.8, 0.0, 0.0),
    "SC_Chrome": ((0.78, 0.8, 0.84), 0.15, 1.0, 0.0),
    "SC_Glass": ((0.02, 0.03, 0.05), 0.05, 0.3, 0.0),
    "SC_Trim": ((0.01, 0.01, 0.012), 0.3, 0.0, 0.0),
    "SC_Gap": ((0.03, 0.03, 0.035), 0.8, 0.0, 0.0),
    "SC_Tire": ((0.03, 0.03, 0.03), 0.85, 0.0, 0.0),
    "SC_Rim": ((0.035, 0.035, 0.04), 0.35, 0.6, 0.0),
    "SC_Caliper": ((0.9, 0.22, 0.02), 0.4, 0.0, 0.0),
    "SC_Disc": ((0.22, 0.22, 0.24), 0.5, 0.8, 0.0),
    "SC_HeadHousing": ((0.03, 0.035, 0.045), 0.1, 0.4, 0.0),
    "SC_HeadLED": ((1.0, 1.0, 1.0), 0.3, 0.0, 3.0),
    "SC_TailHousing": ((0.18, 0.0, 0.01), 0.1, 0.0, 0.0),
    "SC_TailLED": ((1.0, 0.02, 0.02), 0.3, 0.0, 3.0),
    "SC_BarBody": ((0.02, 0.02, 0.022), 0.4, 0.0, 0.0),
    "SC_BarAmberL": ((1.0, 0.42, 0.0), 0.3, 0.0, 3.0),
    "SC_BarAmberR": ((1.0, 0.42, 0.0), 0.3, 0.0, 3.0),
    "SC_BarGreen": ((0.05, 0.9, 0.2), 0.3, 0.0, 3.0),
    "SC_Plate": ((0.92, 0.92, 0.9), 0.4, 0.0, 0.0),
    "SC_TextDark": ((0.015, 0.015, 0.018), 0.5, 0.0, 0.0),
    "SC_TextLight": ((0.95, 0.95, 0.95), 0.5, 0.0, 0.0),
    "SC_Banner": ((0.006, 0.006, 0.008), 0.6, 0.0, 0.0),
})


# ---------------------------------------------------------------------------
# Lofts de perfil de carro
# ---------------------------------------------------------------------------
def half_profile(ctrl, seg):
    """Meio perfil (x >= 0, de baixo para cima) pelos pontos de controle: Catmull-Rom com o primeiro e
    o último ponto espelhados no eixo (tangente horizontal no meio do carro), `seg[k]` pontos no
    trecho k. O número de pontos não muda entre as seções, então as linhas do loft seguem as mesmas
    regiões da carroceria de ponta a ponta."""
    pts = [Vector(c) for c in ctrl]
    ext = [Vector((-pts[1].x, pts[1].y))] + pts + [Vector((-pts[-2].x, pts[-2].y))]
    out = []
    for k in range(len(pts) - 1):
        for i in range(seg[k]):
            out.append(catmull(ext[k], ext[k + 1], ext[k + 2], ext[k + 3], i / seg[k]))
    out.append(pts[-1])
    return out


def full_ring(half, s):
    """Anel fechado na posição s: o meio perfil (x >= 0) e o espelho dele (x < 0) de volta."""
    ring = [P(p.x, s, p.y) for p in half]
    ring += [P(-p.x, s, p.y) for p in reversed(half[1:-1])]
    return ring


def profile_loft(stations, keys, ctrl_fn, seg, sub):
    secs = interp_dicts(stations, keys, sub)
    return skin([full_ring(half_profile(ctrl_fn(d), seg), d["s"]) for d in secs])


# Carroceria (até o ombro / capô / tampa traseira)
BODY_KEYS = ("s", "zb", "hw", "zw", "hs", "zs", "xe", "ze", "zc")
BODY_SEG = (3, 2, 5, 6, 5, 4, 5)


def BS(s, zb, hw, zw, hs, zs, xe, ze, zc):
    """Seção da carroceria: fundo zb, largura máxima hw na altura zw, ombro (hs, zs), crista do
    para-lama (xe, ze) e o meio do capô / tampa zc."""
    return dict(s=s, zb=zb, hw=hw, zw=zw, hs=hs, zs=zs, xe=xe, ze=ze, zc=zc)


def body_ctrl(d):
    hw, zb = d["hw"], d["zb"]
    return [(0.0, zb), (0.55 * hw, zb), (hw - 0.035, zb + 0.07), (hw, d["zw"]), (d["hs"], d["zs"]),
            (d["xe"], d["ze"]), (0.45 * d["xe"], d["zc"] + 0.3 * (d["ze"] - d["zc"])), (0.0, d["zc"])]


# Medidas da foto lateral do safety car (AMG GT R, 2018): escala pelo entre-eixos (2,63 m). Nariz
# 0,83 m à frente do eixo dianteiro, traseira 1,05 m atrás do traseiro; a crista dos para-lamas sobe
# de 0,6 m no nariz a 0,9 m na base do para-brisa; cintura a 0,875 m; tampa traseira a 0,88 m.
BODY_STATIONS = [
    BS(2.080, 0.15, 0.58, 0.40, 0.54, 0.55, 0.44, 0.60, 0.60),
    BS(2.065, 0.13, 0.72, 0.40, 0.68, 0.58, 0.55, 0.635, 0.625),
    BS(2.030, 0.12, 0.83, 0.41, 0.79, 0.62, 0.64, 0.675, 0.655),
    BS(1.960, 0.12, 0.905, 0.43, 0.865, 0.665, 0.71, 0.715, 0.69),
    BS(1.820, 0.12, 0.95, 0.46, 0.91, 0.72, 0.765, 0.765, 0.735),
    BS(1.560, 0.12, 0.975, 0.49, 0.935, 0.77, 0.795, 0.81, 0.78),
    BS(1.300, 0.125, 0.985, 0.50, 0.945, 0.80, 0.805, 0.835, 0.81),
    BS(1.000, 0.125, 0.975, 0.50, 0.935, 0.82, 0.80, 0.86, 0.84),
    BS(0.700, 0.12, 0.955, 0.49, 0.915, 0.835, 0.79, 0.88, 0.87),
    BS(0.430, 0.115, 0.94, 0.48, 0.90, 0.845, 0.78, 0.89, 0.895),
    BS(0.100, 0.11, 0.93, 0.46, 0.89, 0.848, 0.77, 0.878, 0.88),
    BS(-0.500, 0.11, 0.935, 0.46, 0.895, 0.85, 0.77, 0.872, 0.872),
    BS(-0.950, 0.115, 0.965, 0.48, 0.92, 0.855, 0.78, 0.876, 0.872),
    BS(-1.330, 0.125, 1.005, 0.52, 0.955, 0.86, 0.78, 0.885, 0.878),
    BS(-1.750, 0.14, 1.0, 0.55, 0.945, 0.862, 0.75, 0.888, 0.882),
    BS(-2.050, 0.18, 0.96, 0.58, 0.89, 0.858, 0.69, 0.884, 0.88),
    BS(-2.210, 0.23, 0.88, 0.60, 0.81, 0.848, 0.62, 0.87, 0.868),
    BS(-2.295, 0.27, 0.78, 0.61, 0.71, 0.832, 0.53, 0.85, 0.85),
    BS(-2.330, 0.31, 0.66, 0.62, 0.60, 0.80, 0.44, 0.815, 0.815),
]

# Cabine (vidros e teto), por cima da carroceria
CABIN_KEYS = ("s", "zb", "gb", "gw", "zl", "gt", "zr", "zt")
CABIN_SEG = (2, 2, 6, 4, 3)


def CS(s, zb, gb, gw, zl, gt, zr, zt):
    """Seção da cabine: base zb (dentro da carroceria, meia largura gb), linha da cintura (gw, zl),
    calha do teto (gt, zr) e o topo zt."""
    return dict(s=s, zb=zb, gb=gb, gw=gw, zl=zl, gt=gt, zr=zr, zt=zt)


def cabin_ctrl(d):
    return [(0.0, d["zb"]), (d["gb"], d["zb"]), (d["gw"], d["zl"]), (d["gt"], d["zr"]),
            (0.55 * d["gt"], d["zt"] - 0.12 * (d["zt"] - d["zr"])), (0.0, d["zt"])]


# Foto: base do para-brisa em s = 0,42 (0,907 m), começo do teto em s = -0,06 (1,23 m), teto a
# 1,26 m e o fastback chegando na tampa em s = -1,93 (0,89 m).
CABIN_STATIONS = [
    CS(0.440, 0.86, 0.70, 0.69, 0.895, 0.68, 0.90, 0.905),
    CS(0.300, 0.85, 0.74, 0.73, 0.88, 0.67, 0.985, 1.00),
    CS(0.100, 0.84, 0.77, 0.76, 0.875, 0.65, 1.10, 1.125),
    CS(-0.080, 0.84, 0.785, 0.77, 0.872, 0.62, 1.19, 1.225),
    CS(-0.300, 0.84, 0.795, 0.775, 0.872, 0.60, 1.225, 1.255),
    CS(-0.650, 0.845, 0.80, 0.78, 0.872, 0.59, 1.235, 1.265),
    CS(-0.950, 0.85, 0.81, 0.78, 0.875, 0.575, 1.21, 1.25),
    CS(-1.220, 0.855, 0.81, 0.775, 0.88, 0.55, 1.135, 1.17),
    CS(-1.480, 0.86, 0.80, 0.76, 0.885, 0.51, 1.045, 1.085),
    CS(-1.730, 0.865, 0.76, 0.72, 0.885, 0.46, 0.955, 0.975),
    CS(-1.930, 0.865, 0.70, 0.66, 0.88, 0.40, 0.89, 0.895),
    CS(-2.000, 0.86, 0.66, 0.62, 0.875, 0.37, 0.878, 0.88),
]


def paint_body(c):
    return "SC_Under" if c.nz < -0.75 else "SC_Paint"


def cyl_x(x0, x1, s, z, r, n=48):
    """Cilindro fechado no eixo x (de x0 a x1), centro (s, z)."""
    rings = [[P(x, s + r * math.cos(2 * math.pi * i / n), z + r * math.sin(2 * math.pi * i / n)) for i in range(n)]
             for x in (x0, x1)]
    return skin(rings)


def prism_s(outline, s0, s1):
    """Prisma fechado: contorno (x, z) extrudado em s, de s0 a s1."""
    return skin([[P(x, s, z) for x, z in outline] for s in (s0, s1)])


# Grade (lâminas verticais) da frente: trapézio (x, z) de cantos arredondados, recortado 9,5 cm
GRILLE = [(-0.41, 0.25), (-0.43, 0.27), (-0.37, 0.515), (-0.35, 0.53), (0.35, 0.53), (0.37, 0.515),
          (0.43, 0.27), (0.41, 0.25)]
GRILLE_BACK = 1.985


def build_body(col):
    b = Builder("BodyShell")
    b.add(profile_loft(BODY_STATIONS, BODY_KEYS, body_ctrl, BODY_SEG, sub=6), paint_body)
    obj = b.build(col)
    for s, half in ((FRONT_AXLE, FRONT_HALF_TRACK), (REAR_AXLE, REAR_HALF_TRACK)):
        for side in (1, -1):
            x0, x1 = sorted((side * 0.62, side * 1.40))
            apply_boolean_difference(obj, cyl_x(x0, x1, s, WHEEL_R, ARCH_R), "SC_Arch", col)
    apply_boolean_difference(obj, prism_s(GRILLE, GRILLE_BACK, 2.6), "SC_Grille", col)
    return obj


def build_cabin(col):
    b = Builder("Cabin")
    b.add(profile_loft(CABIN_STATIONS, CABIN_KEYS, cabin_ctrl, CABIN_SEG, sub=6), "SC_Paint")
    return b.build(col)


# ---------------------------------------------------------------------------
# Adesivos: contornos 2D projetados na carroceria
# ---------------------------------------------------------------------------
def mesh_object(name, verts, faces, mats, col, smooth=True):
    """Objeto com as faces dadas (sem recalcular normais: a ordem dos vértices já é a de fora).
    mats: o material de todas as faces, ou uma lista com um por face."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    names = [mats] * len(faces) if isinstance(mats, str) else list(mats)
    order = list(dict.fromkeys(names))
    for m in order:
        me.materials.append(f1.get_material(m))
    for poly, m in zip(me.polygons, names):
        poly.material_index = order.index(m)
        poly.use_smooth = smooth
    me.update()
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    return obj


class Surface:
    """Alvo dos adesivos: BVH dos objetos já montados (coordenadas do Blender)."""

    def __init__(self, objs):
        verts, polys = [], []
        for o in objs:
            base = len(verts)
            verts += [o.matrix_world @ v.co for v in o.data.vertices]
            polys += [[base + i for i in p.vertices] for p in o.data.polygons]
        self.tree = BVHTree.FromPolygons(verts, polys)

    def hit(self, origin, direction):
        loc, normal, _i, _d = self.tree.ray_cast(origin, direction, 20.0)
        if loc is None:
            return None
        return loc, (-normal if normal.dot(direction) > 0.0 else normal)


def side_map(side):
    """(s, z) na lateral: raio de fora para dentro (side = +1 esquerda, -1 direita)."""
    d = Vector((-side, 0.0, 0.0))
    return lambda u, v: (P(side * 3.0, u, v), d)


def front_map(u, v):
    """(x, z) na frente."""
    return P(u, 4.0, v), V3(0.0, -1.0, 0.0)


def rear_map(u, v):
    """(x, z) na traseira."""
    return P(u, -4.0, v), V3(0.0, 1.0, 0.0)


def top_map(u, v):
    """(x, s) de cima."""
    return P(u, v, 4.0), Vector((0.0, 0.0, -1.0))


def clean(ring, eps=1e-5):
    out = []
    for p in ring:
        p = Vector((p[0], p[1]))
        if not out or (p - out[-1]).length > eps:
            out.append(p)
    if len(out) > 1 and (out[0] - out[-1]).length <= eps:
        out.pop()
    return out


def resample(ring, step):
    out = []
    for i in range(len(ring)):
        a, b = ring[i], ring[(i + 1) % len(ring)]
        k = max(1, int(math.ceil((b - a).length / step)))
        out += [a.lerp(b, j / k) for j in range(k)]
    return out


def signed_area(ring):
    return 0.5 * sum(ring[i - 1][0] * ring[i][1] - ring[i][0] * ring[i - 1][1] for i in range(len(ring)))


class Region:
    """Dentro dos contornos pela regra par-ímpar (os furos das letras ficam de fora)."""

    def __init__(self, rings):
        self.rings = rings
        self.boxes = [(min(p.x for p in r), max(p.x for p in r), min(p.y for p in r), max(p.y for p in r))
                      for r in rings]

    def inside(self, x, y):
        c = False
        for r, (x0, x1, y0, y1) in zip(self.rings, self.boxes):
            if x < x0 or x > x1 or y < y0 or y > y1:
                continue
            j = len(r) - 1
            for i in range(len(r)):
                a, b = r[i], r[j]
                if (a.y > y) != (b.y > y) and x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x:
                    c = not c
                j = i
        return c


def fill_2d(rings, step):
    """Triangula o que está dentro dos contornos, com pontos internos a cada `step` (o adesivo
    acompanha a curvatura da carroceria). Retorna (vértices 2D, triângulos)."""
    rings = [r for r in (clean(resample(clean(r), step)) for r in rings) if len(r) >= 3]
    region = Region(rings)
    pts, edges = [], []
    for r in rings:
        base = len(pts)
        pts += r
        edges += [(base + i, base + (i + 1) % len(r)) for i in range(len(r))]
    kd = KDTree(len(pts))
    for i, p in enumerate(pts):
        kd.insert((p.x, p.y, 0.0), i)
    kd.balance()
    x0, x1 = min(p.x for p in pts), max(p.x for p in pts)
    y0, y1 = min(p.y for p in pts), max(p.y for p in pts)
    for j in range(int((y1 - y0) / step) + 1):
        for i in range(int((x1 - x0) / step) + 1):
            q = Vector((x0 + (i + (0.75 if j % 2 else 0.25)) * step, y0 + (j + 0.5) * step))
            if region.inside(q.x, q.y) and kd.find((q.x, q.y, 0.0))[2] > 0.5 * step:
                pts.append(q)
    out = delaunay_2d_cdt(pts, edges, [], 0, 1e-7)
    verts, tris = out[0], []
    for f in out[2]:
        a, b, c = (verts[i] for i in f[:3])
        if region.inside((a.x + b.x + c.x) / 3.0, (a.y + b.y + c.y) / 3.0):
            tris.append(tuple(f[:3]))
    return verts, tris


def patch_object(name, pos, nrm, tris, mat, col):
    """Triângulos com as posições 3D (None = o raio não pegou nada), virados para `nrm`."""
    used, verts, faces = {}, [], []
    for t in tris:
        if any(pos[i] is None for i in t):
            continue
        a, b, c = (pos[i] for i in t)
        if (b - a).cross(c - a).dot(nrm[t[0]] + nrm[t[1]] + nrm[t[2]]) < 0.0:
            t = (t[0], t[2], t[1])
        idx = []
        for i in t:
            if i not in used:
                used[i] = len(verts)
                verts.append(pos[i])
            idx.append(used[i])
        faces.append(idx)
    return mesh_object(name, verts, faces, mat, col) if faces else None


def project(name, rings, mapping, mat, surf, col, offset=0.004, step=0.03):
    """Adesivo: contornos 2D (coordenadas do mapeamento) projetados na superfície, `offset` acima."""
    verts2, tris = fill_2d(rings, step)
    pos, nrm = [], []
    for p in verts2:
        o, d = mapping(p.x, p.y)
        h = surf.hit(o, d)
        pos.append(h[0] + h[1] * offset if h else None)
        nrm.append(h[1] if h else None)
    return patch_object(name, pos, nrm, tris, mat, col)


def mirror_x(ring):
    return [(-p[0], p[1]) for p in ring]


def smooth_ring(points, sub=4):
    """Contorno fechado suavizado (Catmull-Rom); um ponto repetido vira um canto vivo."""
    pts = [Vector(p) for p in points]
    n = len(pts)
    out = []
    for i in range(n):
        out += [catmull(pts[i - 1], pts[i], pts[(i + 1) % n], pts[(i + 2) % n], k / sub) for k in range(sub)]
    return out


def offset_ring(ring, d):
    """Contorno deslocado `d` para fora (d < 0: para dentro)."""
    ring = [Vector(p) for p in ring]
    if signed_area(ring) < 0.0:
        d = -d
    out = []
    for i in range(len(ring)):
        p0, p1, p2 = ring[i - 1], ring[i], ring[(i + 1) % len(ring)]
        e1, e2 = (p1 - p0).normalized(), (p2 - p1).normalized()
        n1, n2 = Vector((e1.y, -e1.x)), Vector((e2.y, -e2.x))
        m = n1 + n2
        m = m.normalized() if m.length > 1e-6 else n1
        out.append(p1 + m * (d / max(m.dot(n1), 0.35)))
    return out


def stroke(points, width):
    """Faixa de largura `width` ao longo de uma linha aberta (contorno fechado)."""
    pts = [Vector(p) for p in points]
    left, right = [], []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        n = Vector((-t.y, t.x)) * (width / 2)
        left.append(p + n)
        right.append(p - n)
    return left + right[::-1]


def circle(cx, cy, r, n=20):
    return [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def rect(x0, y0, x1, y1, r=0.0, n=4):
    """Retângulo de cantos arredondados (raio r)."""
    if r <= 0.0:
        return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    pts = []
    for cx, cy, a0 in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


_FONT = []


def text_rings(text, height, slant=0.22):
    """Contornos do texto (fonte Chakra Petch Bold do jogo) com altura `height`, centrado em (0, 0) e
    inclinado (itálico) por `slant`."""
    if not _FONT:
        _FONT.append(bpy.data.fonts.load(FONT_PATH))
    cu = bpy.data.curves.new("SC_Text", type="FONT")
    cu.body = text
    cu.font = _FONT[0]
    cu.size = 1.0
    cu.resolution_u = 3
    obj = bpy.data.objects.new("SC_Text", cu)
    bpy.context.scene.collection.objects.link(obj)
    dg = bpy.context.evaluated_depsgraph_get()
    try:
        curve = obj.to_curve(dg)
    except Exception:
        curve = obj.evaluated_get(dg).to_curve(dg)
    rings = []
    for sp in curve.splines:
        ring = []
        if sp.type == "BEZIER":
            bp = sp.bezier_points
            for i in range(len(bp)):
                a, b = bp[i], bp[(i + 1) % len(bp)]
                ring += [Vector((q.x, q.y)) for q in interpolate_bezier(a.co, a.handle_right, b.handle_left, b.co, 5)[:-1]]
        else:
            ring = [Vector((p.co.x, p.co.y)) for p in sp.points]
        ring = clean(ring)
        if len(ring) >= 3:
            rings.append(ring)
    obj.to_curve_clear()
    bpy.data.objects.remove(obj)
    bpy.data.curves.remove(cu)
    xs = [p.x for r in rings for p in r]
    ys = [p.y for r in rings for p in r]
    k = height / (max(ys) - min(ys))
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    return [[Vector(((p.x - cx) * k + slant * (p.y - cy) * k, (p.y - cy) * k)) for p in r] for r in rings]


def project_text(name, text, height, place, mapping, mat, surf, col, offset=0.006, slant=0.22):
    """Letreiro projetado: place(u, v) leva as coordenadas do texto para as do mapeamento."""
    rings = [[Vector(place(p.x, p.y)) for p in r] for r in text_rings(text, height, slant)]
    return project(name, rings, mapping, mat, surf, col, offset, step=0.02)


def flat_text(name, text, height, origin, u_dir, v_dir, normal, mat, col, slant=0.22):
    """Letreiro plano (placas): o texto no plano origin + u * u_dir + v * v_dir, virado para `normal`
    (coordenadas de carro; u_dir é a direita de quem lê)."""
    verts2, tris = fill_2d(text_rings(text, height, slant), 1.0)
    o, u, v, n = P(*origin), V3(*u_dir), V3(*v_dir), V3(*normal)
    pos = [o + u * p.x + v * p.y for p in verts2]
    return patch_object(name, pos, [n] * len(pos), tris, mat, col)


def project_shape(name, rings, place, mapping, mat, surf, col, offset=0.006, step=0.02):
    """Contornos (texto, emblema) levados por place(u, v) para as coordenadas do mapeamento e projetados."""
    return project(name, [[Vector(place(p.x, p.y)) for p in r] for r in rings], mapping, mat, surf, col, offset, step)


def emblem_rings(height, slant=0.22):
    """Emblema do campeonato do jogo ("SPEEDORU" em itálico com a bandeira quadriculada), no lugar onde
    os safety cars de verdade levam o logo da F1. Centrado em (0, 0)."""
    rings = list(text_rings("SPEEDORU", height, slant))
    x1 = max(p.x for r in rings for p in r)
    q = height / 3.0
    for row in range(3):
        for c in range(4):
            if (row + c) % 2:
                continue
            x0, y0 = x1 + 0.3 * height + c * q, -height / 2 + row * q
            sq = [(x0 + 0.002, y0 + 0.002), (x0 + q - 0.002, y0 + 0.002), (x0 + q - 0.002, y0 + q - 0.002),
                  (x0 + 0.002, y0 + q - 0.002)]
            rings.append([Vector((x + slant * y, y)) for x, y in sq])
    xs = [p.x for r in rings for p in r]
    cx = (min(xs) + max(xs)) / 2
    return [[Vector((p.x - cx, p.y)) for p in r] for r in rings]


def side_place(side, sc, zc):
    """Texto na lateral: quem olha a esquerda vê a frente à sua esquerda (lê de trás para a frente
    no lado direito)."""
    return (lambda u, v: (sc - u, zc + v)) if side > 0 else (lambda u, v: (sc + u, zc + v))


# Medidas da foto lateral (s, z): janela lateral em gota (frente reta atrás do retrovisor, ponta
# fina atrás, a 1,36 m do meio), baixa (0,885 a 1,155 m)
SIDE_WINDOW = smooth_ring([(0.05, 0.885), (0.05, 0.885), (-0.10, 1.03), (-0.22, 1.142), (-0.50, 1.155),
                           (-0.84, 1.15), (-1.05, 1.12), (-1.22, 1.075), (-1.36, 1.03), (-1.36, 1.03),
                           (-1.10, 0.925), (-0.70, 0.895), (-0.30, 0.887)], 4)
WINDSHIELD = smooth_ring([(0.0, 0.40), (0.35, 0.385), (0.62, 0.33), (0.62, 0.33), (0.56, -0.03), (0.56, -0.03),
                          (0.30, -0.042), (0.0, -0.045), (-0.30, -0.042), (-0.56, -0.03), (-0.56, -0.03),
                          (-0.62, 0.33), (-0.62, 0.33), (-0.35, 0.385)], 4)
REAR_WINDOW = smooth_ring([(0.0, -1.0), (0.30, -1.005), (0.47, -1.02), (0.47, -1.02), (0.36, -1.85),
                           (0.36, -1.85), (0.20, -1.875), (0.0, -1.88), (-0.20, -1.875), (-0.36, -1.85),
                           (-0.36, -1.85), (-0.47, -1.02), (-0.47, -1.02), (-0.30, -1.005)], 4)
HEADLIGHT = smooth_ring([(0.40, 0.535), (0.52, 0.548), (0.66, 0.578), (0.77, 0.615), (0.85, 0.66), (0.85, 0.66),
                         (0.855, 0.69), (0.80, 0.70), (0.66, 0.67), (0.52, 0.632), (0.42, 0.60),
                         (0.39, 0.565)], 3)
TAILLIGHT = smooth_ring([(0.29, 0.712), (0.55, 0.700), (0.80, 0.694), (0.865, 0.705), (0.89, 0.735),
                         (0.872, 0.772), (0.80, 0.786), (0.55, 0.790), (0.31, 0.778), (0.282, 0.745)], 3)
INTAKE = smooth_ring([(0.47, 0.19), (0.76, 0.19), (0.80, 0.235), (0.775, 0.39), (0.62, 0.425), (0.49, 0.375)], 2)
FENDER_GILL = [(0.88, 0.615), (0.56, 0.645), (0.54, 0.69), (0.86, 0.665)]
HOOD_VENT = smooth_ring([(0.22, 0.88), (0.22, 0.88), (0.44, 0.90), (0.44, 0.90), (0.47, 0.62), (0.47, 0.62),
                         (0.25, 0.58), (0.25, 0.58)], 3)
DOOR_LINE = [(0.29, 0.872), (0.30, 0.62), (0.32, 0.32), (0.28, 0.215), (0.19, 0.205), (-0.78, 0.205),
             (-0.85, 0.23), (-0.88, 0.45), (-0.92, 0.70), (-0.95, 0.87)]
# Blocos pretos inclinados na parte de baixo das portas (os grafismos do safety car), da frente para trás
STRIPES = [(0.72, 0.64), (0.56, 0.44), (0.36, 0.20), (0.12, -0.10), (-0.18, -0.48), (-0.56, -0.80)]
STRIPE_Z = (0.18, 0.34)
STRIPE_LEAN = 0.10


def build_decals(col, surf):
    out = []

    def add(obj):
        if obj is not None:
            out.append(obj)

    for side, tag in ((1, "L"), (-1, "R")):
        sm = side_map(side)
        add(project("Glass_Side" + tag, [SIDE_WINDOW], sm, "SC_Glass", surf, col, 0.005, 0.04))
        add(project("Trim_Side" + tag, [offset_ring(SIDE_WINDOW, 0.02), SIDE_WINDOW], sm, "SC_Trim", surf, col, 0.004))
        add(project("DoorLine" + tag, [stroke(DOOR_LINE, 0.008)], sm, "SC_Gap", surf, col, 0.0025, 0.02))
        add(project("DoorHandle" + tag, [stroke([(-0.56, 0.815), (-0.72, 0.818)], 0.022)], sm, "SC_Gap", surf, col,
                    0.004, 0.015))
        add(project("Gill" + tag, [FENDER_GILL], sm, "SC_Grille", surf, col, 0.004, 0.02))
        add(project("GillBar" + tag, [stroke([(0.84, 0.64), (0.58, 0.662)], 0.011)], sm, "SC_Chrome", surf, col,
                    0.006, 0.02))
        for k, (s0, s1) in enumerate(STRIPES):
            z0, z1 = STRIPE_Z
            add(project("Stripe%s%d" % (tag, k), [[(s0, z0), (s1, z0), (s1 - STRIPE_LEAN, z1), (s0 - STRIPE_LEAN, z1)]],
                        sm, "SC_Stripe", surf, col, 0.0045, 0.03))
        # Porta: emblema grande e a linha de texto embaixo (onde o carro real leva o logo da F1)
        add(project_shape("DoorEmblem" + tag, emblem_rings(0.13), side_place(side, -0.33, 0.59), sm,
                          "SC_Lettering", surf, col, 0.0055))
        add(project_shape("DoorText" + tag, text_rings("WORLD CHAMPIONSHIP", 0.036, 0.0), side_place(side, -0.33, 0.465),
                          sm, "SC_Lettering", surf, col, 0.0055, 0.015))
        sx = 1.0 if side > 0 else -1.0
        ring = (lambda r: r) if side > 0 else mirror_x
        add(project("HeadHousing" + tag, [ring(HEADLIGHT)], front_map, "SC_HeadHousing", surf, col, 0.004, 0.02))
        add(project("HeadLED" + tag, [ring(stroke([(0.43, 0.59), (0.52, 0.61), (0.66, 0.645), (0.77, 0.675),
                                                   (0.835, 0.69)], 0.011))], front_map, "SC_HeadLED", surf, col,
                    0.007, 0.015))
        for k, (cx, cy) in enumerate(((0.53, 0.575), (0.61, 0.593), (0.69, 0.615))):
            add(project("HeadDot%s%d" % (tag, k), [circle(sx * cx, cy, 0.016, 14)], front_map, "SC_HeadLED", surf, col,
                        0.007, 0.015))
        add(project("Intake" + tag, [ring(INTAKE)], front_map, "SC_Grille", surf, col, 0.004, 0.025))
        for k, z in enumerate((0.27, 0.34)):
            add(project("IntakeBlade%s%d" % (tag, k), [ring(stroke([(0.50, z), (0.775, z)], 0.016))], front_map,
                        "SC_Paint", surf, col, 0.006, 0.02))
        add(project("AirCurtain" + tag, [ring(stroke([(0.835, 0.22), (0.83, 0.40)], 0.018))], front_map, "SC_Grille",
                    surf, col, 0.004, 0.015))
        add(project("TailHousing" + tag, [ring(TAILLIGHT)], rear_map, "SC_TailHousing", surf, col, 0.004, 0.02))
        add(project("TailLED" + tag, [ring(stroke([(0.32, 0.758), (0.55, 0.768), (0.80, 0.765), (0.862, 0.748)], 0.013))],
                    rear_map, "SC_TailLED", surf, col, 0.007, 0.015))
        add(project("HoodVent" + tag, [ring(HOOD_VENT)], top_map, "SC_Grille", surf, col, 0.004, 0.03))
        for k in range(4):
            t0 = (k + 1) / 5.0
            a = Vector((0.22, 0.88)).lerp(Vector((0.25, 0.58)), t0)
            b = Vector((0.44, 0.90)).lerp(Vector((0.47, 0.62)), t0)
            add(project("HoodLouvre%s%d" % (tag, k), [ring(stroke([a + (b - a) * 0.06, b - (b - a) * 0.06], 0.014))],
                        top_map, "SC_Paint", surf, col, 0.006, 0.02))
        # Traços dos dois lados do "DRIVE SAFELY" do capô
        add(project("HoodBar" + tag, [ring(stroke([(0.215, 1.075), (0.40, 1.075)], 0.012))], top_map, "SC_Lettering",
                    surf, col, 0.0055, 0.02))
    # Capô: "SAFETY CAR / Drive Safely", emblema e a linha do campeonato (como no carro real)
    hood = lambda sc: (lambda u, v: (u, sc - v))  # noqa: E731  (lido de frente: o "alto" é o para-brisa)
    add(project_shape("HoodText", text_rings("SAFETY CAR", 0.11), hood(0.985), top_map, "SC_Lettering", surf, col, 0.0055))
    add(project_shape("HoodDrive", text_rings("DRIVE SAFELY", 0.04), hood(1.075), top_map, "SC_Lettering", surf, col,
                      0.0055, 0.015))
    add(project_shape("HoodEmblem", emblem_rings(0.10), hood(1.27), top_map, "SC_Lettering", surf, col, 0.0055))
    add(project_shape("HoodChamp", text_rings("WORLD CHAMPIONSHIP", 0.032, 0.0), hood(1.385), top_map, "SC_Lettering",
                      surf, col, 0.0055, 0.012))
    # Vidros de frente e de trás com a faixa escura e o letreiro
    add(project("Windshield", [WINDSHIELD], top_map, "SC_Glass", surf, col, 0.005, 0.04))
    add(project("WindshieldTrim", [offset_ring(WINDSHIELD, 0.02), WINDSHIELD], top_map, "SC_Trim", surf, col, 0.004))
    add(project("WindshieldBanner", [rect(-0.555, -0.035, 0.555, 0.085)], top_map, "SC_Banner", surf, col, 0.007, 0.03))
    add(project_shape("WindshieldText", text_rings("SAFETY CAR", 0.06, 0.18), hood(0.025), top_map, "SC_TextLight",
                      surf, col, 0.009))
    for sx, mat in ((1.0, "SC_BarAmberL"), (-1.0, "SC_BarAmberR")):
        for k in range(3):
            x0 = 0.28 + 0.075 * k
            r = rect(x0, -0.002, x0 + 0.06, 0.053, 0.01)
            add(project("WindshieldLED%s%d" % (mat[-1], k), [mirror_x(r) if sx < 0 else r], top_map, mat, surf, col,
                        0.009, 0.02))
    add(project("RearWindow", [REAR_WINDOW], top_map, "SC_Glass", surf, col, 0.005, 0.04))
    add(project("RearWindowTrim", [offset_ring(REAR_WINDOW, 0.02), REAR_WINDOW], top_map, "SC_Trim", surf, col, 0.004))
    add(project("RearBanner", [rect(-0.455, -1.13, 0.455, -1.03)], top_map, "SC_Banner", surf, col, 0.007, 0.03))
    rear_glass = lambda sc: (lambda u, v: (-u, sc + v))  # noqa: E731  (lido de trás: o "alto" é o teto)
    add(project_shape("RearBannerText", text_rings("SAFETY CAR", 0.05, 0.18), rear_glass(-1.08), top_map,
                      "SC_TextLight", surf, col, 0.009))
    for sx, mat in ((1.0, "SC_BarAmberL"), (-1.0, "SC_BarAmberR")):
        for k in range(3):
            x0 = 0.25 + 0.062 * k
            r = rect(x0, -1.105, x0 + 0.05, -1.055, 0.01)
            add(project("RearLED%s%d" % (mat[-1], k), [mirror_x(r) if sx < 0 else r], top_map, mat, surf, col,
                        0.009, 0.02))
    add(project_shape("RearGlassText", text_rings("DRIVE SAFELY", 0.032, 0.0), rear_glass(-1.76), top_map,
                      "SC_TextLight", surf, col, 0.008, 0.012))
    # Traseira: emblema acima da placa clara "SAFETY CAR" (iluminada por trás no jogo)
    add(project_shape("RearEmblem", emblem_rings(0.05), lambda u, v: (-u, 0.605 + v), rear_map, "SC_Lettering", surf,
                      col, 0.0055, 0.015))
    add(project("RearPlate", [rect(-0.25, 0.43, 0.25, 0.535, 0.012)], rear_map, "SC_Plate", surf, col, 0.004, 0.03))
    add(project_shape("RearPlateText", text_rings("SAFETY CAR", 0.058), lambda u, v: (-u, 0.4825 + v), rear_map,
                      "SC_TextDark", surf, col, 0.007, 0.015))
    return out


# ---------------------------------------------------------------------------
# Peças
# ---------------------------------------------------------------------------
def build_grille(col):
    """Lâminas verticais dentro do recorte da grade e a placa da frente."""
    b = Builder("GrilleSlats")
    for i in range(15):
        x = -0.34 + 0.68 * i / 14
        b.add(box(x, GRILLE_BACK + 0.045, 0.39, 0.0065, 0.035, 0.135), "SC_Chrome")
    objs = [b.build(col)]
    p = Builder("FrontPlate")
    p.add(box(0.0, 2.09, 0.31, 0.23, 0.007, 0.033), "SC_Plate")
    objs.append(p.build(col))
    t = flat_text("FrontPlateText", "SAFETY CAR", 0.04, (0.0, 2.0975, 0.31), (1, 0, 0), (0, 0, 1), (0, 1, 0),
                  "SC_TextDark", col)
    if t:
        objs.append(t)
    return objs


def edge_accent(top, edge="SC_Accent"):
    """Placa (slab) com a borda (faces laterais da frente e dos lados) na cor de destaque."""
    def fn(c):
        if abs(c.nz) < 0.5 and c.ns > -0.6:
            return edge
        return top
    return fn


def build_aero(col):
    objs = []
    # Splitter da frente com a borda colorida
    b = Builder("Splitter")
    b.add(slab([(-0.88, 1.80), (-0.86, 1.96), (-0.74, 2.06), (-0.50, 2.11), (0.50, 2.11), (0.74, 2.06),
                (0.86, 1.96), (0.88, 1.80)], 0.088, 0.112), edge_accent("SC_Carbon"))
    objs.append(b.build(col, smooth_angle=30))
    # Saias laterais com um filete colorido embaixo
    b = Builder("Skirts")
    b.add(slab([(0.86, 0.88), (0.94, 0.86), (0.945, -0.90), (0.86, -0.92)], 0.09, 0.15), "SC_Carbon", mirror=True)
    b.add(slab([(0.944, 0.84), (0.953, 0.84), (0.953, -0.88), (0.944, -0.88)], 0.093, 0.105), "SC_Accent", mirror=True)
    objs.append(b.build(col, smooth_angle=30))
    # Difusor com aletas e o escape duplo no meio (como o do GT R)
    b = Builder("Diffuser")
    b.add(slab([(-0.70, -2.00), (0.70, -2.00), (0.66, -2.28), (0.60, -2.33), (-0.60, -2.33), (-0.66, -2.28)],
               0.10, 0.315), "SC_Carbon")
    for x in (-0.55, -0.3, 0.3, 0.55):
        b.add(plate([(-2.10, 0.10), (-2.36, 0.10), (-2.36, 0.19), (-2.31, 0.25), (-2.10, 0.25)], x, 0.012), "SC_Carbon")
    for x in (-0.085, 0.085):
        b.add(lathe([(0.0, 0.042), (0.12, 0.042), (0.12, 0.049), (0.0, 0.049)], segments=24),
              "SC_Chrome", transform=Matrix.Translation(P(x, -2.255, 0.20)) @ Matrix.Rotation(math.pi / 2, 4, "Z"))
        b.add(lathe([(0.0, 0.002), (0.004, 0.002), (0.004, 0.042), (0.0, 0.042)], segments=24),
              "SC_Grille", transform=Matrix.Translation(P(x, -2.35, 0.20)) @ Matrix.Rotation(math.pi / 2, 4, "Z"))
    objs.append(b.build(col, smooth_angle=35))
    # Asa traseira baixa, 10 cm acima da tampa (como a do GT R): plano principal, flap com a borda de
    # fuga colorida, placas laterais pequenas e dois suportes
    b = Builder("RearWing")
    b.add(wing([W(0.0, -1.94, 0.985, 0.26, 6.0, 0.10, 0.05), W(0.45, -1.94, 0.985, 0.26, 6.0, 0.10, 0.05),
                W(0.80, -1.945, 0.99, 0.26, 7.0, 0.10, 0.05)], n=10, sub=2, symmetric=True), "SC_Carbon")
    b.add(wing([W(0.0, -2.165, 1.02, 0.10, 22.0, 0.10, 0.05), W(0.80, -2.165, 1.025, 0.10, 23.0, 0.10, 0.05)],
               n=8, sub=2, symmetric=True), lambda c: "SC_Accent" if c.s < -2.245 else "SC_Carbon")
    for x in (-0.815, 0.815):
        b.add(plate([(-1.90, 0.95), (-1.90, 1.03), (-1.98, 1.09), (-2.30, 1.10), (-2.32, 1.06), (-2.32, 0.95)],
                    x, 0.010), "SC_Carbon")
    for x in (-0.30, 0.30):
        b.add(plate([(-1.95, 0.85), (-1.98, 0.995), (-2.10, 1.0), (-2.10, 0.85)], x, 0.018), "SC_Carbon")
    objs.append(b.build(col, smooth_angle=35))
    # Retrovisores (carcaça de carbono, na quina da janela) e a antena na tampa traseira, do lado
    # direito, perto da asa (como na foto)
    b = Builder("Mirrors")
    b.add(ellipsoid(0.93, -0.03, 0.965, 0.095, 0.075, 0.055, n=20, rows=10), "SC_Carbon", mirror=True)
    b.add(rod((0.72, 0.03, 0.915), (0.86, -0.01, 0.955), 0.022, flat=0.6), "SC_Carbon", mirror=True)
    b.add(rod((-0.30, -1.97, 0.87), (-0.30, -2.12, 1.40), 0.004, sides=6), "SC_Carbon")
    objs.append(b.build(col))
    return objs


# Barra de luzes do teto: centro (s, z), meia largura. Alta e apoiada numa base, na frente do teto
BAR_S, BAR_Z, BAR_HALF = -0.75, 1.375, 0.56
# Células âmbar (|x|) e a verde do meio
BAR_AMBER = ((0.19, 0.29), (0.305, 0.405), (0.42, 0.52), (0.535, 1.0))
BAR_GREEN = 0.10


def bar_paint(c):
    ax = abs(c.x)
    lens = abs(c.ns) > 0.45 or ax > BAR_HALF - 0.035
    if not lens or abs(c.z - BAR_Z) > 0.036:
        return "SC_BarBody"
    if ax < BAR_GREEN:
        return "SC_BarGreen"
    for a, b in BAR_AMBER:
        if a < ax < b:
            return "SC_BarAmberL" if c.x > 0 else "SC_BarAmberR"
    return "SC_BarBody"


def build_light_bar(col):
    b = Builder("LightBar")
    marks = [0.0, 0.05, BAR_GREEN, 0.145, 0.19, 0.24, 0.29, 0.305, 0.355, 0.405, 0.42, 0.47, 0.52, 0.535,
             0.55, BAR_HALF]
    xs = sorted(set([-m for m in marks] + marks))
    rings = []
    for x in xs:
        t = (abs(x) - (BAR_HALF - 0.05)) / 0.05
        f = math.sqrt(max(1.0 - t * t, 0.05)) if t > 0.0 else 1.0
        d, h = 0.13 * f, 0.052 * f
        ring = []
        for i in range(28):
            a = 2 * math.pi * i / 28
            ring.append(P(x, BAR_S + d * f1._sgnpow(math.cos(a), 2 / 3.0), BAR_Z + h * f1._sgnpow(math.sin(a), 2 / 3.0)))
        rings.append(ring)
    b.add(skin(rings), bar_paint)
    # Base que prende a barra no teto
    b.add(box(0.0, BAR_S, 1.28, 0.36, 0.10, 0.05), "SC_BarBody")
    return b.build(col, smooth_angle=50)


# ---------------------------------------------------------------------------
# Rodas
# ---------------------------------------------------------------------------
def tyre_profile(w, rr=0.045):
    """Perfil do pneu (axial, raio) em volta do eixo: banda com ombros redondos e flancos baixos."""
    hw = w / 2
    R, rb = WHEEL_R, RIM_R + 0.004

    def side_a(t):
        return hw - 0.010 * (1 - t) + 0.012 * math.sin(math.pi * t)

    pts = []
    for i in range(6):
        t = i / 6
        pts.append((side_a(t), rb + (R - rr - rb) * t))
    ca, cr = hw - rr, R - rr
    for i in range(7):
        th = math.radians(90 * i / 6)
        pts.append((ca + rr * math.cos(th), cr + rr * math.sin(th)))
    for i in range(7):
        th = math.radians(90 + 90 * i / 6)
        pts.append((-ca + rr * math.cos(th), cr + rr * math.sin(th)))
    for i in range(5, -1, -1):
        t = i / 6
        pts.append((-side_a(t), rb + (R - rr - rb) * t))
    return pts


def wheel_parts(w):
    """Pneu e roda de 10 raios (5 pares), face externa para +x, centro na origem."""
    hw = w / 2
    parts = [(lathe(tyre_profile(w), segments=64), "SC_Tire")]
    # Tambor da roda e a aba polida na borda de fora
    parts.append((lathe([(-hw + 0.02, RIM_R - 0.03), (hw - 0.03, RIM_R - 0.03), (hw - 0.03, RIM_R - 0.012),
                         (hw - 0.006, RIM_R - 0.012), (hw - 0.004, RIM_R + 0.006), (-hw + 0.02, RIM_R + 0.006)],
                        segments=64), "SC_Rim"))
    parts.append((lathe([(hw - 0.03, RIM_R - 0.024), (hw - 0.001, RIM_R - 0.024), (hw - 0.001, RIM_R + 0.004),
                         (hw - 0.03, RIM_R + 0.004)], segments=64), "SC_Chrome"))
    face = hw - 0.05
    for i in range(5):
        th = 2 * math.pi * i / 5
        for d in (-0.15, 0.15):
            parts.append((radial_box(th + d, 0.07, RIM_R - 0.022, face - 0.014, face + 0.012, 0.034, 0.026), "SC_Rim"))
    # Cubo e porca central
    parts.append((lathe([(face - 0.03, 0.002), (face + 0.008, 0.002), (face + 0.008, 0.085),
                         (face - 0.03, 0.085)], segments=40), "SC_Rim"))
    parts.append((lathe([(face, 0.002), (face + 0.03, 0.002), (face + 0.03, 0.032), (face, 0.032)],
                        segments=6), "SC_Chrome"))
    return parts


def build_wheels(col):
    objs = []
    for name, s, half, w in (("Wheel_FL", FRONT_AXLE, FRONT_HALF_TRACK, FRONT_TYRE_W),
                             ("Wheel_FR", FRONT_AXLE, -FRONT_HALF_TRACK, FRONT_TYRE_W),
                             ("Wheel_RL", REAR_AXLE, REAR_HALF_TRACK, REAR_TYRE_W),
                             ("Wheel_RR", REAR_AXLE, -REAR_HALF_TRACK, REAR_TYRE_W)):
        hub = P(half, s, WHEEL_R)
        xf = Matrix.Translation(hub) @ (Matrix.Scale(-1, 4, (1, 0, 0)) if half < 0 else Matrix.Identity(4))
        b = Builder(name)
        for mesh, mat in wheel_parts(w):
            b.add(mesh, mat, transform=xf)
        objs.append(b.build(col, origin=hub))
    return objs


def build_brakes(col):
    """Discos e pinças (não giram: ficam na carroceria)."""
    b = Builder("Brakes")
    for s, half, w in ((FRONT_AXLE, FRONT_HALF_TRACK, FRONT_TYRE_W), (REAR_AXLE, REAR_HALF_TRACK, REAR_TYRE_W)):
        for side in (1, -1):
            xf = Matrix.Translation(P(side * half, s, WHEEL_R)) @ (Matrix.Scale(-1, 4, (1, 0, 0)) if side < 0
                                                                     else Matrix.Identity(4))
            hw = w / 2
            b.add(lathe([(hw - 0.115, 0.07), (hw - 0.085, 0.07), (hw - 0.085, 0.19), (hw - 0.115, 0.19)],
                        segments=40), "SC_Disc", transform=xf)
            # Pinça em cima e à frente do disco
            th = math.radians(115 if s > 0 else 65)
            b.add(radial_box(th, 0.13, 0.215, hw - 0.125, hw - 0.072, 0.13, 0.15), "SC_Caliper", transform=xf)
    return b.build(col)


# ---------------------------------------------------------------------------
# Montagem / vistas
# ---------------------------------------------------------------------------
def join(objs, name):
    """Junta os objetos num só (materiais por face mantidos)."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs,
                                   selected_objects=objs):
        bpy.ops.object.join()
    obj = objs[0]
    obj.name = name
    obj.data.name = name
    return obj


def main():
    reset_scene()
    col = new_collection("SafetyCar")
    body = build_body(col)
    cabin = build_cabin(col)
    surf = Surface([body, cabin])
    decals = build_decals(col, surf)
    parts = build_grille(col) + build_aero(col) + [build_light_bar(col), build_brakes(col)]
    car = join([body, cabin] + decals + parts, "Body")
    wheels = build_wheels(col)
    print("triângulos: carroceria %d, rodas %d" % (mesh_stats([car]), mesh_stats(wheels)))
    print("materiais:", ", ".join(sorted(m.name for m in car.data.materials)))
    export_glb([car] + wheels, OUT_PATH)
    if DO_RENDER:
        render_previews()


def render_previews():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_object_outline = True
    sh.object_outline_color = (0.02, 0.02, 0.05)
    sh.show_shadows = True
    sh.show_cavity = True
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.color = (0.55, 0.7, 0.9)
    ground_mesh = bpy.data.meshes.new("Ground")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=14)
    bm.to_mesh(ground_mesh)
    bm.free()
    ground = bpy.data.objects.new("Ground", ground_mesh)
    gmat = bpy.data.materials.new("GroundPreview")
    gmat.diffuse_color = (0.35, 0.37, 0.4, 1)
    ground_mesh.materials.append(gmat)
    scene.collection.objects.link(ground)
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    os.makedirs(RENDER_DIR, exist_ok=True)
    # nome: (câmera, alvo, ângulo; 0 = ortográfica) em coordenadas do Blender (frente do carro em -Y)
    views = {
        "front34": ((4.6, -6.3, 2.1), (0, -0.25, 0.62), 40),
        "side": ((9.0, 0.0, 0.95), (0, 0.0, 0.62), 40),
        "rear34": ((-4.6, 6.3, 2.4), (0, 0.3, 0.7), 40),
        "front": ((0.0, -8.5, 1.0), (0, 0.0, 0.62), 30),
        "rear": ((0.0, 8.5, 1.3), (0, 0.0, 0.7), 30),
        "top": ((0.0, 0.01, 12.0), (0, 0.0, 0.0), 45),
        "roof": ((1.6, -1.4, 2.6), (0, 0.6, 1.2), 40),
        "wheel": ((2.6, -2.9, 0.7), (FRONT_HALF_TRACK, -FRONT_AXLE, 0.4), 32),
        "side_ortho": ((9.0, 0.0, 0.65), (0, 0.0, 0.65), 0),
    }
    for name, (loc, target, lens_deg) in views.items():
        if not ALL_VIEWS and name not in ("front34", "side", "rear34", "front"):
            continue
        cam.location = Vector(loc)
        cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        if lens_deg > 0:
            cam_data.type = "PERSP"
            cam_data.angle = math.radians(lens_deg)
        else:
            # Ortográfica (para conferir proporções): 5,4 m na largura da imagem
            cam_data.type = "ORTHO"
            cam_data.ortho_scale = 5.4
        scene.render.filepath = os.path.join(RENDER_DIR, name + ".png")
        bpy.ops.render.render(write_still=True)
        print("  render:", scene.render.filepath)
    bpy.data.objects.remove(ground)
    bpy.data.objects.remove(cam)


if __name__ == "__main__":
    main()
