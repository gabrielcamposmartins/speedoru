"""
Estátuas e bichos da Atlantis Abyss (pista no fundo do mar).

Uso (a partir da raiz do projeto):
    blender -b --factory-startup -P blender/build_atlantis.py                       # gera os .glb
    blender -b --factory-startup -P blender/build_atlantis.py -- --render <pasta>     # + vistas
    blender -b --factory-startup -P blender/build_atlantis.py -- --only=whale,manta  # só esses

Modelagem com metabolas (formas lisas, estilo anime) em unidades (cada peça tem ~1 de altura ou de
comprimento), frente para -Y e z para cima; no fim a malha é escalada para metros (SIZE), reduzida
(Decimate) até o número de triângulos de cada peça e exportada com a cor de vértice:
  R = quanto a parte mexe no shader (sea_creature.gdshader): cauda e nadadeiras dos peixes, asas
      da raia, nadadeiras da tartaruga, tentáculos do polvo (as estátuas vão sem cor de vértice).
O Godot troca o material: as estátuas viram pedra de Atlântida (sea_stone), os bichos o toon
animado com as cores de cada um (scripts/track/sea_life.gd). A frente (-Y no Blender) vira +Z.

Saída: assets/track/atlantis_abyss/models/<nome>.glb
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DIR = os.path.join(ROOT, "assets", "track", "atlantis_abyss", "models")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER_DIR = ARGS[ARGS.index("--render") + 1] if "--render" in ARGS else ""
ONLY = next((a.split("=", 1)[1].split(",") for a in ARGS if a.startswith("--only=")), [])

# nome: (tamanho em metros da unidade, triângulos)
SIZE = {
    "poseidon_face": (16.0, 14000),
    "poseidon_standing": (9.0, 14000),
    "poseidon_seated": (7.0, 12000),
    "goddess_head": (8.0, 12000),
    "octopus": (5.0, 9000),
    "whale": (17.0, 5000),
    "manta": (7.0, 2500),
    "shark": (4.5, 2500),
    "turtle": (1.7, 2000),
    "dolphin": (2.6, 2200),
}


# ---------------------------------------------------------------------------
# Metabolas e peças
# ---------------------------------------------------------------------------
VIS = 0.574  # raio visível de uma metabola isolada = 0,574 x raio


def V(co, radius, size=(1, 1, 1), kind="ELLIPSOID", neg=False, rot=None):
    """Elemento pelo tamanho visível: centro, raio visível, proporção por eixo, tipo, negativo."""
    return dict(co=co, r=radius / VIS, size=size, kind=kind, neg=neg, rot=rot)


def blob(name, elements, res=0.012, threshold=0.6):
    mb = bpy.data.metaballs.new(name)
    mb.resolution = res
    mb.render_resolution = res
    mb.threshold = threshold
    for e in elements:
        el = mb.elements.new(type=e["kind"])
        el.co = Vector(e["co"])
        el.radius = e["r"]
        el.size_x, el.size_y, el.size_z = e["size"]
        el.stiffness = 2.0
        el.use_negative = e["neg"]
        if e["rot"] is not None:
            el.rotation = e["rot"]
    obj = bpy.data.objects.new(name, mb)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    bpy.data.objects.remove(obj)
    me.name = name
    out = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(out)
    for p in me.polygons:
        p.use_smooth = True
    return out


def chain(points, radii, size=(1, 1, 1), n=4):
    """Elementos ao longo de uma poligonal, com o raio visível interpolado (lista de raios por ponto)."""
    out = []
    for k in range(len(points) - 1):
        a, b = Vector(points[k]), Vector(points[k + 1])
        for i in range(n):
            t = i / n
            r = radii[k] + (radii[k + 1] - radii[k]) * t
            out.append(V(tuple(a.lerp(b, t)), r, size))
    out.append(V(tuple(points[-1]), radii[-1], size))
    return out


def body(length_pts, size=(1, 1, 1)):
    """Corpo ao longo de y: lista de (y, raio visível, z)."""
    out = []
    for k in range(len(length_pts) - 1):
        y0, r0, z0 = length_pts[k]
        y1, r1, z1 = length_pts[k + 1]
        steps = max(int(abs(y1 - y0) / 0.02), 1)
        for i in range(steps):
            t = i / steps
            out.append(V((0, y0 + (y1 - y0) * t, z0 + (z1 - z0) * t), r0 + (r1 - r0) * t, size))
    y, r, z = length_pts[-1]
    out.append(V((0, y, z), r, size))
    return out


def mirror(elements):
    """Os elementos e o espelho deles em x (o que já está em x = 0 não repete)."""
    out = list(elements)
    for e in elements:
        if abs(e["co"][0]) > 1e-4:
            m = dict(e)
            m["co"] = (-e["co"][0], e["co"][1], e["co"][2])
            out.append(m)
    return out


def cone(name, base, tip, radius, segs=10):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=radius, radius2=0.0, depth=1.0)
    d = Vector(tip) - Vector(base)
    rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    m = Matrix.Translation((Vector(base) + Vector(tip)) * 0.5) @ rot @ Matrix.Diagonal((1, 1, d.length, 1))
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def cylinder(name, a, b, radius, segs=12):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=radius, radius2=radius, depth=1.0)
    d = Vector(b) - Vector(a)
    rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    m = Matrix.Translation((Vector(a) + Vector(b)) * 0.5) @ rot @ Matrix.Diagonal((1, 1, d.length, 1))
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def box(name, center, size):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(center)) @ Matrix.Diagonal((*size, 1)), verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def trident(name, base, top, scale=1.0):
    """Tridente: haste, travessa curva e três pontas de lança (unidades da peça)."""
    base, top = Vector(base), Vector(top)
    objs = [cylinder(name + "Shaft", base, top, 0.012 * scale)]
    w = 0.09 * scale
    cross = top + Vector((0, 0, 0.0))
    objs.append(cylinder(name + "Bar", cross + Vector((-w, 0, 0)), cross + Vector((w, 0, 0)), 0.013 * scale))
    for x in (-w, 0.0, w):
        b = cross + Vector((x, 0, 0))
        t = b + Vector((0, 0, 0.13 * scale + (0.03 * scale if x == 0 else 0.0)))
        objs.append(cylinder(name + "Prong", b, t, 0.01 * scale, 8))
        objs.append(cone(name + "Tip", t, t + Vector((0, 0, 0.06 * scale)), 0.022 * scale, 8))
    return objs


def crown(name, center, radius, height, spikes=7, arc=1.0):
    """Coroa: aro e pontas na metade da frente (arc = fração da volta com pontas)."""
    objs = []
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=24, radius1=radius, radius2=radius * 1.04, depth=height * 0.35)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    me = bpy.data.meshes.new(name + "Band")
    bm.to_mesh(me)
    bm.free()
    band = bpy.data.objects.new(name + "Band", me)
    bpy.context.scene.collection.objects.link(band)
    objs.append(band)
    for k in range(spikes):
        a = -math.pi * 0.5 + (k - (spikes - 1) * 0.5) / max(spikes - 1, 1) * math.pi * arc
        base = Vector(center) + Vector((math.cos(a) * radius, math.sin(a) * radius, height * 0.15))
        tip = base + Vector((math.cos(a) * radius * 0.15, math.sin(a) * radius * 0.15, height))
        objs.append(cone(name + "Spike", base, tip, radius * 0.16, 6))
    return objs


# ---------------------------------------------------------------------------
# Estátuas
# ---------------------------------------------------------------------------
def bearded_head(c, s, mouth_open=0.0, crown_on=True):
    """Cabeça de Poseidon (centro c, escala s): rosto, nariz, sobrancelhas, olhos, bigode, barba
    ondulada e cabelo; mouth_open abre a boca (o rosto das cachoeiras)."""
    cx, cy, cz = c
    el = [
        V((cx, cy, cz), 0.27 * s, (0.92, 0.95, 1.12)),
        V((cx, cy - 0.2 * s, cz + 0.1 * s), 0.11 * s, (1.7, 0.6, 0.5)),         # testa/sobrancelhas
        V((cx, cy - 0.27 * s, cz - 0.02 * s), 0.06 * s, (0.6, 0.9, 1.4)),        # nariz
        V((cx, cy - 0.285 * s, cz - 0.08 * s), 0.05 * s, (1.2, 0.8, 0.6)),       # ponta do nariz
        V((cx + 0.13 * s, cy - 0.2 * s, cz - 0.07 * s), 0.08 * s),             # bochechas
        V((cx - 0.13 * s, cy - 0.2 * s, cz - 0.07 * s), 0.08 * s),
        V((cx + 0.1 * s, cy - 0.27 * s, cz + 0.04 * s), 0.04 * s, neg=True),   # órbitas
        V((cx - 0.1 * s, cy - 0.27 * s, cz + 0.04 * s), 0.04 * s, neg=True),
        V((cx + 0.1 * s, cy - 0.245 * s, cz + 0.035 * s), 0.028 * s),          # olhos
        V((cx - 0.1 * s, cy - 0.245 * s, cz + 0.035 * s), 0.028 * s),
    ]
    # Bigode: dois arcos saindo do nariz e caindo pelos cantos da boca
    for side in (1, -1):
        for k in range(6):
            t = k / 5
            el.append(V((cx + side * (0.02 + 0.16 * t) * s, cy - (0.27 - 0.05 * t) * s, cz - (0.13 + 0.09 * t * t) * s),
                        (0.035 - 0.012 * t) * s, (1.3, 0.8, 0.7)))
    # Barba ondulada: fileiras do queixo para baixo, cada vez mais estreitas
    rows = 7
    for r in range(rows):
        t = r / (rows - 1)
        z = cz - (0.2 + 0.42 * t) * s
        half = (0.24 - 0.13 * t) * s
        n = 5 - r // 2
        for k in range(n):
            u = (k / max(n - 1, 1)) * 2 - 1
            wave = math.sin(r * 1.7 + k * 1.3) * 0.02 * s
            el.append(V((cx + u * half + wave, cy - (0.16 - 0.05 * t) * s + abs(u) * 0.05 * s, z), (0.075 - 0.025 * t) * s))
    # Cabelo: mechas em volta da parte de trás e do alto
    for k in range(10):
        a = math.pi * (0.05 + 0.9 * k / 9)
        el.append(V((cx + math.cos(a) * 0.25 * s, cy + math.sin(a) * 0.2 * s + 0.04 * s, cz + 0.12 * s), 0.09 * s))
        el.append(V((cx + math.cos(a) * 0.27 * s, cy + math.sin(a) * 0.22 * s + 0.06 * s, cz - 0.08 * s), 0.08 * s))
    if mouth_open > 0:
        el.append(V((cx, cy - 0.27 * s, cz - 0.21 * s), 0.07 * s * mouth_open, (1.5, 1.4, 0.9), neg=True))
    objs = [blob("Head", el, res=0.012 * s)]
    if crown_on:
        objs += crown("Crown", (cx, cy + 0.01 * s, cz + 0.24 * s), 0.235 * s, 0.17 * s, spikes=7, arc=0.85)
    return objs


def poseidon_face():
    """O rosto gigante das cachoeiras do Portão (boca aberta, de onde sai a água)."""
    return bearded_head((0, 0, 0.62), 1.6, mouth_open=1.3)


def robe_figure(seated=False):
    """Corpo de Poseidon: manto, tronco, ombros e braços; o direito erguido com o tridente."""
    el = []
    if seated:
        el += [V((0, 0.02, 0.5), 0.12, (1.4, 1.0, 0.9)),                     # quadril
               V((0.07, -0.12, 0.47), 0.07, (1.0, 2.2, 0.8)), V((-0.07, -0.12, 0.47), 0.07, (1.0, 2.2, 0.8)),
               V((0.07, -0.24, 0.3), 0.06, (1, 1, 2.2)), V((-0.07, -0.24, 0.3), 0.06, (1, 1, 2.2)),
               V((0.07, -0.27, 0.08), 0.06, (1.1, 1.6, 0.8)), V((-0.07, -0.27, 0.08), 0.06, (1.1, 1.6, 0.8))]
        z0 = 0.5
    else:
        # Manto até os pés
        el += [V((0, 0, z), r) for z, r in [(0.02, 0.17), (0.12, 0.165), (0.24, 0.155), (0.36, 0.145), (0.48, 0.13)]]
        z0 = 0.5
    el += [V((0, 0.0, z0 + 0.12), 0.14, (1.2, 0.8, 1.2)),                     # tronco
           V((0, -0.04, z0 + 0.2), 0.12, (1.25, 0.75, 0.8)),                  # peito
           V((0.13, 0, z0 + 0.25), 0.07), V((-0.13, 0, z0 + 0.25), 0.07),      # ombros
           V((0, 0, z0 + 0.32), 0.05)]                                       # pescoço
    # Braço direito erguido (segura o tridente), esquerdo junto ao corpo
    el += chain([(0.13, 0, z0 + 0.25), (0.22, -0.02, z0 + 0.36), (0.24, -0.03, z0 + 0.5)], [0.045, 0.038, 0.035])
    el += chain([(-0.13, 0, z0 + 0.25), (-0.18, -0.03, z0 + 0.12), (-0.15, -0.09, z0 + 0.02)], [0.045, 0.038, 0.035])
    # Dobra do manto em diagonal
    for k in range(5):
        t = k / 4
        el.append(V((0.12 - 0.24 * t, -0.08, z0 + 0.22 - 0.25 * t), 0.05))
    objs = [blob("Body", el, res=0.012)]
    objs += bearded_head((0, -0.01, z0 + 0.42), 0.32)
    objs += trident("Trident", (0.245, -0.03, 0.05 if not seated else 0.0), (0.245, -0.03, z0 + 0.82))
    if seated:
        objs.append(box("Throne", (0, 0.1, 0.22), (0.5, 0.42, 0.44)))
        objs.append(box("ThroneBack", (0, 0.29, 0.62), (0.5, 0.08, 0.6)))
    return objs


def poseidon_standing():
    return robe_figure(False)


def poseidon_seated():
    return robe_figure(True)


def goddess_head():
    """Busto da deusa: rosto sereno, cabelo ondulado caindo pelos ombros, tiara."""
    c = Vector((0, 0, 0.66))
    el = [V(tuple(c), 0.25, (0.86, 0.92, 1.12)),
          V((0, -0.235, 0.64), 0.04, (0.55, 0.9, 1.3)),                     # nariz
          V((0, -0.235, 0.57), 0.03, (1.4, 0.7, 0.5)),                      # lábios
          V((0.09, -0.21, 0.69), 0.035, neg=True), V((-0.09, -0.21, 0.69), 0.035, neg=True),
          V((0.11, -0.17, 0.6), 0.07), V((-0.11, -0.17, 0.6), 0.07),           # maçãs do rosto
          V((0, -0.15, 0.48), 0.07, (1.0, 1.0, 0.9)),                        # queixo
          V((0, 0.0, 0.38), 0.08),                                           # pescoço
          V((0, 0.02, 0.18), 0.2, (1.9, 0.9, 0.7)),                          # ombros/busto
          V((0, -0.05, 0.1), 0.16, (1.5, 0.9, 0.8))]
    # Cabelo: mechas onduladas para trás e descendo pelos lados
    for k in range(18):
        a = math.pi * (k / 17)
        for d in range(7):
            z = 0.84 - d * 0.075
            r = 0.225 + d * 0.018
            wave = math.sin(k * 1.3 + d * 0.9) * 0.018
            el.append(V((math.cos(a) * r + wave, math.sin(a) * r * 0.9 + 0.06, z), 0.06 - d * 0.004, (0.85, 0.85, 1.5)))
    objs = [blob("Goddess", el, res=0.011)]
    band = crown("Tiara", (0, 0.0, 0.84), 0.235, 0.07, spikes=5, arc=0.5)
    return objs + band


# ---------------------------------------------------------------------------
# Bichos (frente para -Y)
# ---------------------------------------------------------------------------
def octopus():
    el = [V((0, 0.12, 0.62), 0.3, (0.9, 1.0, 1.25)),                        # manto
          V((0, -0.05, 0.36), 0.2, (1.1, 1.0, 0.8)),                        # cabeça
          V((0.14, -0.17, 0.42), 0.07), V((-0.14, -0.17, 0.42), 0.07)]      # olhos
    # Oito tentáculos espiralando (alguns se enroscando para cima, como na coluna)
    for k in range(8):
        a = math.pi * 2 * (k + 0.5) / 8
        pts, radii = [], []
        for i in range(14):
            t = i / 13
            ang = a + t * 2.2 * (1 if k % 2 == 0 else -1)
            rad = 0.14 + t * 0.7
            z = 0.25 - t * 0.2 + (math.sin(t * 5 + k) * 0.08 if k % 3 == 0 else 0.0) + (t * t * 0.6 if k in (1, 4) else 0.0)
            pts.append((math.cos(ang) * rad, math.sin(ang) * rad, z))
            radii.append(0.1 * (1 - t) + 0.025)
        el += chain(pts, radii, n=5)
    return [blob("Octopus", el, res=0.016)]


def whale():
    prof = [(-0.5, 0.05, 0.0), (-0.46, 0.085, 0.0), (-0.36, 0.11, 0.0), (-0.15, 0.115, 0.0), (0.1, 0.095, 0.01),
            (0.3, 0.055, 0.02), (0.42, 0.028, 0.02), (0.47, 0.02, 0.02)]
    el = body(prof, (1.0, 1.0, 0.86))
    el += mirror(chain([(0.09, -0.16, -0.05), (0.22, -0.1, -0.08), (0.36, -0.02, -0.1)], [0.035, 0.03, 0.015], (1.0, 1.6, 0.35)))
    el += mirror([V((0.07, 0.49, 0.02), 0.045, (1.8, 0.7, 0.2)), V((0.13, 0.51, 0.02), 0.03, (1.6, 0.6, 0.2))])
    el.append(V((0, 0.24, 0.07), 0.025, (0.3, 1.6, 0.8)))                  # barbatana dorsal
    return [blob("Whale", el, res=0.012)]


def manta():
    el = [V((0, 0, 0), 0.13, (1.0, 1.3, 0.35)), V((0, -0.1, 0), 0.1, (1.2, 0.8, 0.35))]
    for k in range(9):
        t = (k + 1) / 9
        x = t * 0.5
        el += mirror([V((x, 0.04 + 0.18 * t * t, 0.0), 0.11 * (1 - t) + 0.02, (1.1, 0.9, 0.22))])
    el += mirror([V((0.09, -0.22, 0.0), 0.035, (0.7, 1.4, 0.35))])            # nadadeiras cefálicas
    el += chain([(0, 0.15, 0.0), (0, 0.35, 0.0), (0, 0.55, 0.0)], [0.035, 0.018, 0.012], n=8)
    return [blob("Manta", el, res=0.008)]


def shark():
    prof = [(-0.5, 0.02, 0.0), (-0.44, 0.055, 0.0), (-0.3, 0.085, 0.0), (-0.1, 0.09, 0.0), (0.15, 0.065, 0.0),
            (0.35, 0.03, 0.0), (0.44, 0.02, 0.0)]
    el = body(prof, (0.72, 1.0, 0.85))
    el += chain([(0, -0.12, 0.05), (0, -0.06, 0.11), (0, 0.0, 0.16)], [0.035, 0.022, 0.008], (0.25, 1.0, 1.0))  # dorsal
    el += mirror(chain([(0.05, -0.16, -0.04), (0.12, -0.1, -0.08), (0.17, -0.05, -0.1)], [0.03, 0.02, 0.008], (1.0, 1.0, 0.25)))
    el += chain([(0, 0.42, 0.0), (0, 0.48, 0.07), (0, 0.53, 0.14)], [0.022, 0.016, 0.006], (0.25, 1.0, 1.0))  # cauda (alto)
    el += chain([(0, 0.42, 0.0), (0, 0.47, -0.05), (0, 0.5, -0.09)], [0.02, 0.013, 0.006], (0.25, 1.0, 1.0))  # cauda (baixo)
    return [blob("Shark", el, res=0.008)]


def dolphin():
    prof = [(-0.5, 0.012, 0.0), (-0.42, 0.025, 0.0), (-0.36, 0.06, 0.02), (-0.15, 0.09, 0.02), (0.15, 0.07, 0.01),
            (0.36, 0.03, 0.0), (0.44, 0.018, 0.0)]
    el = body(prof, (0.95, 1.0, 1.0))
    el.append(V((0, -0.02, 0.1), 0.04, (0.25, 1.2, 1.3)))
    el += mirror([V((0.07, -0.15, -0.05), 0.035, (1.6, 0.9, 0.25))])
    el += mirror([V((0.06, 0.48, 0.0), 0.035, (1.6, 0.7, 0.22))])
    return [blob("Dolphin", el, res=0.008)]


def turtle():
    el = [V((0, 0, 0.02), 0.36, (0.86, 1.0, 0.36)),                         # casco
          V((0, 0, -0.04), 0.33, (0.85, 0.95, 0.2)),                         # plastrão
          V((0, -0.46, 0.0), 0.1, (0.9, 1.1, 0.8)),                          # cabeça
          V((0, -0.36, 0.0), 0.07)]                                          # pescoço
    el += mirror(chain([(0.22, -0.2, 0.0), (0.45, -0.18, -0.02), (0.68, -0.05, -0.03)], [0.07, 0.06, 0.025], (1.0, 1.4, 0.3)))
    el += mirror(chain([(0.18, 0.28, 0.0), (0.3, 0.38, -0.01)], [0.06, 0.03], (1.0, 1.2, 0.3)))
    return [blob("Turtle", el, res=0.01)]


# Peso da animação (R) por vértice, em unidades da peça
WEIGHTS = {
    "whale": lambda v: smooth(-0.05, 0.5, v.y) + 0.6 * smooth(0.25, 0.4, abs(v.x)),
    "shark": lambda v: smooth(-0.1, 0.5, v.y),
    "dolphin": lambda v: smooth(-0.1, 0.5, v.y),
    "manta": lambda v: smooth(0.08, 0.5, abs(v.x)) + 0.5 * smooth(0.2, 0.55, v.y),
    "turtle": lambda v: smooth(0.22, 0.6, abs(v.x)),
    "octopus": lambda v: smooth(0.25, 1.0, math.hypot(v.x, v.y)),
}


def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


BUILDERS = {
    "poseidon_face": poseidon_face,
    "poseidon_standing": poseidon_standing,
    "poseidon_seated": poseidon_seated,
    "goddess_head": goddess_head,
    "octopus": octopus,
    "whale": whale,
    "manta": manta,
    "shark": shark,
    "turtle": turtle,
    "dolphin": dolphin,
}


# ---------------------------------------------------------------------------
# Montagem e exportação
# ---------------------------------------------------------------------------
def finish(name, objs):
    """Junta, reduz até os triângulos da peça, pinta o peso da animação, escala e exporta."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    me = obj.data
    scale, target = SIZE[name]
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    if tris > target:
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = target / tris
        bpy.ops.object.modifier_apply(modifier=mod.name)
    # Peso da animação (antes de escalar: as funções usam as unidades da peça)
    # (só nos bichos: nas estátuas a pedra usa a cor de vértice como cor, então elas vão sem)
    fn = WEIGHTS.get(name)
    if fn:
        attr = me.color_attributes.new(name="Color", type="BYTE_COLOR", domain="POINT")
        for i, v in enumerate(me.vertices):
            attr.data[i].color = (min(max(fn(v.co), 0.0), 1.0), 1.0, 1.0, 1.0)
        me.color_attributes.active_color = attr
    me.transform(Matrix.Scale(scale, 4))
    # Estátuas com a base em z = 0; bichos centrados
    if not fn:
        low = min(v.co.z for v in me.vertices)
        me.transform(Matrix.Translation((0, 0, -low)))
    for p in me.polygons:
        p.use_smooth = True
    mat = bpy.data.materials.new(name)
    me.materials.clear()
    me.materials.append(mat)
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    lo = Vector((min(v.co[k] for v in me.vertices) for k in range(3)))
    hi = Vector((max(v.co[k] for v in me.vertices) for k in range(3)))
    print("%s: %d triângulos, %.1f x %.1f x %.1f m" % (name, tris, *(hi - lo)))
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_cameras=False, export_lights=False,
                              export_vertex_color="ACTIVE", export_materials="PLACEHOLDER")
    print("  exportado:", os.path.relpath(path, ROOT))
    return obj


def render(obj, name):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.show_cavity = True
    lo = Vector((min(v.co[k] for v in obj.data.vertices) for k in range(3)))
    hi = Vector((max(v.co[k] for v in obj.data.vertices) for k in range(3)))
    center = (lo + hi) * 0.5
    size = max(hi - lo)
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for view, d in (("front", Vector((0.35, -1.0, 0.25))), ("side", Vector((1.0, -0.2, 0.3))), ("top", Vector((0.2, -0.3, 1.0)))):
        cam.location = center + d.normalized() * size * 1.9
        cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(RENDER_DIR, "%s_%s.png" % (name, view))
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    for name, fn in BUILDERS.items():
        if ONLY and name not in ONLY:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        obj = finish(name, fn())
        if RENDER_DIR:
            os.makedirs(RENDER_DIR, exist_ok=True)
            render(obj, name)


if __name__ == "__main__":
    main()
