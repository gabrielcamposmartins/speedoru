"""
Balões de personagem (formato especial, como os de festival): Psyduck e Hamtaro.

Uso (a partir da raiz do projeto):
    blender -b --factory-startup -P blender/build_balloons.py                 # gera os .glb
    blender -b --factory-startup -P blender/build_balloons.py -- --render <pasta>   # + vistas

Modelagem com metabolas (o corpo "inflado" sai liso, como um balão) em unidades de altura
(o personagem tem ~1 de altura, frente para -Y, z para cima). Cada cor é uma família de metabolas
separada (amarelo, creme do bico, branco/laranja...), virada malha e pintada por região (manchas
laranja do Hamtaro, bochechas rosadas). Olhos, pupilas, brilhos, nariz e os fios de cabelo são
peças à parte, presas na superfície com raycast. No fim tudo é escalado para o tamanho real
(SCALE m de altura) e ganha o cesto do balão (vime, maçarico e cabos) pendurado embaixo.

Saída: assets/track/balloons/<nome>.glb (um objeto, materiais pelo nome da cor; o Godot troca
por materiais toon, ver scripts/track/character_balloons.gd).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DIR = os.path.join(ROOT, "assets", "track", "balloons")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER_DIR = ARGS[ARGS.index("--render") + 1] if "--render" in ARGS else ""
ONLY = next((a.split("=", 1)[1].split(",") for a in ARGS if a.startswith("--only=")), [])

# Altura do personagem no jogo (m)
SCALE = 22.0

# nome: cor (sRGB)
COLORS = {
    "Psy_Yellow": (1.0, 0.82, 0.22),
    "Psy_Cream": (0.99, 0.91, 0.66),
    "Eye_White": (0.98, 0.98, 0.96),
    "Eye_Black": (0.04, 0.04, 0.05),
    "Ham_White": (0.99, 0.95, 0.86),
    "Ham_Orange": (0.98, 0.52, 0.12),
    "Ham_Pink": (1.0, 0.62, 0.66),
    "Ham_Blush": (1.0, 0.55, 0.55),
    "Mouth": (0.55, 0.12, 0.14),
    "Basket": (0.45, 0.28, 0.12),
    "Metal": (0.55, 0.56, 0.6),
    "Rope": (0.85, 0.82, 0.74),
}


def srgb_to_linear(c):
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


def material(name):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    col = (*srgb_to_linear(COLORS[name]), 1.0)
    mat.diffuse_color = col
    mat.use_nodes = True
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = col
        bsdf.inputs["Roughness"].default_value = 0.45
    return mat


# ---------------------------------------------------------------------------
# Metabolas
# ---------------------------------------------------------------------------
def E(co, r, size=(1, 1, 1), kind="ELLIPSOID", rot=None, neg=False, stiff=2.0):
    """Elemento de metabola: centro, raio, escala por eixo, tipo, rotação (Quaternion), negativo."""
    return dict(co=co, r=r, size=size, kind=kind, rot=rot, neg=neg, stiff=stiff)


def blob(name, elements, mat, res=0.012, threshold=0.6):
    """Família de metabolas -> objeto de malha (liso) com um material."""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = res
    mb.render_resolution = res
    mb.threshold = threshold
    for e in elements:
        el = mb.elements.new(type=e["kind"])
        el.co = Vector(e["co"])
        el.radius = e["r"]
        el.size_x, el.size_y, el.size_z = e["size"]
        el.stiffness = e["stiff"]
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
    me.materials.append(material(mat))
    for p in me.polygons:
        p.use_smooth = True
    return out


def paint(obj, fn):
    """Pinta por região: fn(centro, normal) -> nome do material (ou None = mantém)."""
    me = obj.data
    names = [m.name for m in me.materials]
    for p in me.polygons:
        m = fn(p.center, p.normal)
        if m is None:
            continue
        if m not in names:
            me.materials.append(material(m))
            names.append(m)
        p.material_index = names.index(m)


def cut(obj, planes):
    """Corta a malha por planos (centro, normal) antes de pintar: as bordas entre as cores saem
    retas em vez de serrilhadas pelos triângulos."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for plane in planes:
        co, no = plane[0], plane[1]
        region = plane[2] if len(plane) > 2 else None
        faces = [f for f in bm.faces if region is None or region(f.calc_center_median())]
        edges = {e for f in faces for e in f.edges}
        verts = {v for f in faces for v in f.verts}
        bmesh.ops.bisect_plane(bm, geom=list(verts) + list(edges) + faces, plane_co=Vector(co),
                               plane_no=Vector(no).normalized())
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.to_mesh(obj.data)
    bm.free()
    for p in obj.data.polygons:
        p.use_smooth = True


def surface(obj, origin, outward):
    """Ponto e normal da superfície de `obj` saindo de `origin` (de dentro do corpo) na direção
    `outward`: o raio vem de fora para dentro e pega a primeira superfície desse lado."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    d = Vector(outward).normalized()
    start = Vector(origin) + d * 5.0
    hit = tree.ray_cast(start, -d)
    if hit[0] is None:
        return Vector(origin), d
    return hit[0], hit[1]


def bbox(obj):
    vs = [v.co for v in obj.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def ellipsoid(name, center, radii, mat, normal=None, segs=24, rings=14, tilt=0.0):
    """Elipsoide; com `normal`, o eixo z local aponta para ela (achatado contra a superfície)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    m = Matrix.Diagonal((radii[0], radii[1], radii[2], 1.0))
    if normal is not None:
        n = Vector(normal).normalized()
        up = Vector((0, 0, 1)) if abs(n.z) < 0.95 else Vector((0, 1, 0))
        x = up.cross(n).normalized()
        y = n.cross(x).normalized()
        rot = Matrix((x, y, n)).transposed().to_4x4()
        rot = rot @ Matrix.Rotation(tilt, 4, "Z")
        m = rot @ m
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(center)) @ m, verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material(mat))
    for p in me.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def tube(name, points, radius, mat, taper=0.0, res=12):
    """Tubo ao longo de uma curva (fios de cabelo, bigodes, cabos); taper afina até a ponta."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 3
    cu.resolution_u = res
    cu.use_fill_caps = True
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for i, pt in enumerate(points):
        bp = sp.bezier_points[i]
        bp.co = Vector(pt)
        bp.handle_left_type = bp.handle_right_type = "AUTO"
        bp.radius = 1.0 - taper * i / max(len(points) - 1, 1)
    obj = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    bpy.data.objects.remove(obj)
    out = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(out)
    me.materials.clear()
    me.materials.append(material(mat))
    for p in me.polygons:
        p.use_smooth = True
    return out


def q_axis(axis, deg):
    return Quaternion(Vector(axis).normalized(), math.radians(deg))


# Raio visível de uma metabola isolada = 0,574 x raio (medido); V() recebe o raio visível.
VIS = 0.574


def V(co, radius, size=(1, 1, 1), kind="ELLIPSOID", neg=False):
    """Elemento pelo tamanho visível: centro, raio visível e proporção por eixo."""
    return E(co, radius / VIS, size, kind=kind, neg=neg)


def chain(a, b, radius, n=5):
    """Bolas em fila de a até b (braços, pernas): viram um cilindro arredondado."""
    a, b = Vector(a), Vector(b)
    return [V(tuple(a.lerp(b, k / (n - 1))), radius, kind="BALL") for k in range(n)]


# ---------------------------------------------------------------------------
# Psyduck
# ---------------------------------------------------------------------------
def build_psyduck():
    objs = []
    head_c = Vector((0, 0, 0.66))
    yellow = [
        # Cabeça grande e redonda, um pouco mais larga que alta (maior que o corpo)
        V(head_c, 0.30, (1.0, 0.9, 0.9)),
        # Corpo em pera com a barriga redonda
        V((0, 0.01, 0.27), 0.25, (1.0, 0.92, 0.95)),
        V((0, -0.05, 0.24), 0.20),
        # Pernas curtas
        V((0.11, 0.0, 0.08), 0.085),
        V((-0.11, 0.0, 0.08), 0.085),
        # Rabinho
        V((0, 0.21, 0.22), 0.06),
    ]
    body = blob("Psy_Body", yellow, "Psy_Yellow")
    objs.append(body)
    # Braços (peça à parte, com vinco no ombro): a pose clássica, cotovelos para fora e as mãos
    # segurando os lados da cabeça
    arms = []
    for sx in (1, -1):
        sh = (sx * 0.19, -0.03, 0.40)
        el = (sx * 0.36, -0.09, 0.47)
        hand_out, hn = surface(body, head_c + Vector((0, -0.03, -0.02)), (sx * 1.0, -0.25, 0.0))
        hand = hand_out + hn * 0.035
        arms += chain(sh, el, 0.048, n=6) + chain(el, tuple(hand), 0.045, n=6)
        arms.append(V(tuple(hand), 0.068, (0.65, 1.0, 1.2)))
    objs.append(blob("Psy_Arms", arms, "Psy_Yellow"))
    lo, hi = bbox(body)
    print("Psyduck corpo:", tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi))
    # Pés de pato (creme), chatos, para a frente e um pouco abertos, com três dedos arredondados
    feet = []
    for sx in (1, -1):
        feet.append(V((sx * 0.12, -0.07, 0.022), 0.09, (1.0, 1.35, 0.32)))
        for k, dx in enumerate((-0.05, 0.0, 0.05)):
            feet.append(V((sx * 0.12 + dx + sx * 0.012, -0.175 - (0.012 if k == 1 else 0.0), 0.02), 0.042, (1.0, 1.2, 0.5)))
    objs.append(blob("Psy_Feet", feet, "Psy_Cream"))
    # Bico: chato e largo na parte de baixo do rosto; a parte de cima maior e arredondada na frente,
    # a de baixo menor e mais recuada (fica um vinco entre as duas)
    face, n = surface(body, Vector((0, 0, 0.60)), (0, -1, 0))
    fy = face.y
    up = blob("Psy_BillTop", [V((0, fy - 0.06, 0.605), 0.17, (1.0, 0.70, 0.30)),
                              V((0, fy - 0.13, 0.600), 0.14, (1.0, 0.55, 0.30))], "Psy_Cream")
    lowb = blob("Psy_BillLow", [V((0, fy - 0.05, 0.548), 0.13, (1.0, 0.68, 0.26))], "Psy_Cream")
    objs += [up, lowb]
    # Olhos: pequenos, brancos, afastados, acima do bico, com pupila de ponto (o olhar vazio)
    for sx in (1, -1):
        p, n = surface(body, head_c + Vector((0, 0, 0.05)), (sx * 0.42, -1.0, 0.12))
        objs.append(ellipsoid("Psy_Eye", p - n * 0.008, (0.052, 0.047, 0.022), "Eye_White", normal=n))
        objs.append(ellipsoid("Psy_Pupil", p + n * 0.013, (0.010, 0.010, 0.006), "Eye_Black", normal=n, segs=12, rings=8))
    # Três fios de cabelo pretos em cima da cabeça
    top, n = surface(body, head_c, (0, 0.05, 1))
    for dx, lean, curl in ((0.0, 0.0, 0.05), (-0.03, -0.045, -0.045), (0.03, 0.045, 0.045)):
        base = top + Vector((dx, 0.0, -0.015))
        objs.append(tube("Psy_Hair", [base, base + Vector((lean * 0.5, 0, 0.07)),
                                      base + Vector((lean + curl * 0.6, 0, 0.13)),
                                      base + Vector((lean + curl, 0.0, 0.15))], 0.011, "Eye_Black", taper=0.6))
    return objs


# ---------------------------------------------------------------------------
# Hamtaro
# ---------------------------------------------------------------------------
def build_hamtaro():
    objs = []
    head_c = Vector((0, 0, 0.62))
    els = [
        # Cabeça enorme (chibi), mais larga que alta, com bochechas fofas embaixo e o focinho
        V(head_c, 0.33, (1.0, 0.86, 0.86)),
        V((0.16, -0.12, 0.52), 0.15, kind="BALL"),
        V((-0.16, -0.12, 0.52), 0.15, kind="BALL"),
        V((0, -0.20, 0.535), 0.085, (1.25, 0.8, 0.8)),
        # Corpo em ovo, menor que a cabeça
        V((0, 0.02, 0.22), 0.235, (1.0, 0.9, 0.95)),
        # Pezinhos e rabinho
        V((0.10, -0.11, 0.03), 0.065, (1.0, 1.3, 0.45)),
        V((-0.10, -0.11, 0.03), 0.065, (1.0, 1.3, 0.45)),
        V((0, 0.21, 0.12), 0.045),
    ]
    body = blob("Ham_Body", els, "Ham_White")
    objs.append(body)
    # Bracinhos levantados para os lados, comemorando (peça à parte), com as mãozinhas rosadas
    arms = []
    for sx in (1, -1):
        a = (sx * 0.17, -0.05, 0.31)
        b = (sx * 0.31, -0.12, 0.43)
        arms += chain(a, b, 0.045, n=5)
        objs.append(ellipsoid("Ham_Paw", (sx * 0.325, -0.13, 0.45), (0.038, 0.034, 0.042), "Ham_Pink"))
    objs.append(blob("Ham_Arms", arms, "Ham_White"))
    lo, hi = bbox(body)
    print("Hamtaro corpo:", tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi))
    eye_z = 0.64

    # Manchas laranja: testa em arco por cima dos olhos (com a faixa branca no meio, do focinho até
    # a nuca), laterais da cabeça atrás das bochechas, nuca, costas e flancos; cara, focinho e
    # barriga brancos; pés rosados. As bordas são cortadas na malha antes de pintar (retas/em arco).
    arch = [0.045, 0.10, 0.16, 0.22, 0.28]

    def brow(ax):
        return eye_z + 0.085 - 1.4 * ax * ax

    def ham_paint(c, n):
        x, y, z = c.x, c.y, c.z
        ax = abs(x)
        if z < 0.06 and y < -0.04:
            return "Ham_Pink"
        if z > 0.40:  # cabeça
            if ax < 0.045 and (y < 0.02 or z > 0.80):
                return None  # faixa branca no meio
            if y > 0.02:
                return "Ham_Orange"  # nuca
            if ax <= arch[-1] and z > brow(ax):
                return "Ham_Orange"  # testa
            if ax > arch[-1] and z > 0.47:
                return "Ham_Orange"  # laterais, atrás das bochechas
            return None
        if y > 0.02 or (y > -0.10 and ax > 0.20):
            return "Ham_Orange"  # costas e flancos
        return None

    head = lambda c: c.z > 0.36
    lower = lambda c: c.z < 0.44
    planes = [((0.045, 0, 0), (1, 0, 0), lambda c: c.z > eye_z and (c.y < 0.05 or c.z > 0.76)),
              ((-0.045, 0, 0), (1, 0, 0), lambda c: c.z > eye_z and (c.y < 0.05 or c.z > 0.76)),
              ((0, 0.02, 0), (0, 1, 0), lambda c: True),
              ((0, 0, 0.40), (0, 0, 1), lambda c: c.y < 0.05 and abs(c.x) > 0.12),
              ((0, 0, 0.47), (0, 0, 1), lambda c: abs(c.x) > arch[-1] - 0.02 and c.y < 0.05),
              ((0, -0.10, 0), (0, 1, 0), lambda c: lower(c) and abs(c.x) > 0.18)]
    for sx in (1, -1):
        planes.append(((sx * arch[-1], 0, 0), (1, 0, 0), lambda c: c.z > 0.44 and c.y < 0.05))
        planes.append(((sx * 0.20, 0, 0), (1, 0, 0), lambda c: lower(c) and -0.12 < c.y < 0.05))
        # Arco da testa: um plano por trecho entre os pontos de `arch`
        for i in range(len(arch) - 1):
            x0, x1 = arch[i], arch[i + 1]
            z0, z1 = brow(x0), brow(x1)
            no = Vector((-(z1 - z0) * sx, 0, (x1 - x0))).normalized()
            planes.append(((sx * x0, 0, z0), tuple(no),
                           lambda c, sx=sx, x0=x0, x1=x1: head(c) and x0 - 0.01 <= c.x * sx <= x1 + 0.01 and c.y < 0.05))
    cut(body, planes)
    paint(body, ham_paint)
    # Orelhas redondas: laranja por fora, rosa por dentro, nos lados do alto da cabeça
    for sx in (1, -1):
        p, n = surface(body, head_c, (sx * 0.62, 0.05, 0.78))
        face_dir = Vector((sx * 0.35, -1.0, 0.15)).normalized()
        c = p + n * 0.045
        objs.append(ellipsoid("Ham_Ear", c, (0.10, 0.105, 0.035), "Ham_Orange", normal=face_dir))
        objs.append(ellipsoid("Ham_EarIn", c + face_dir * 0.022, (0.068, 0.072, 0.02), "Ham_Pink", normal=face_dir))
    # Olhos grandes, pretos e ovais, com dois brilhos
    for sx in (1, -1):
        p, n = surface(body, Vector((sx * 0.12, 0.0, eye_z)), (sx * 0.30, -1.0, 0.05))
        objs.append(ellipsoid("Ham_Eye", p - n * 0.006, (0.064, 0.082, 0.03), "Eye_Black", normal=n))
        objs.append(ellipsoid("Ham_Shine", p + n * 0.022 + Vector((sx * 0.012, 0, 0.028)), (0.021, 0.021, 0.01),
                              "Eye_White", normal=n, segs=12, rings=8))
        objs.append(ellipsoid("Ham_Shine2", p + n * 0.022 + Vector((-sx * 0.016, 0, -0.03)), (0.010, 0.010, 0.006),
                              "Eye_White", normal=n, segs=10, rings=6))
        # Bochechas rosadas
        q, m = surface(body, Vector((sx * 0.16, -0.05, 0.53)), (sx * 0.55, -1.0, -0.05))
        objs.append(ellipsoid("Ham_Blush", q - m * 0.004, (0.045, 0.032, 0.01), "Ham_Blush", normal=m))
    # Narizinho rosa no alto do focinho e a boquinha em "w"
    p, n = surface(body, Vector((0, 0, 0.565)), (0, -1.0, 0.25))
    objs.append(ellipsoid("Ham_Nose", p + n * 0.006, (0.024, 0.018, 0.014), "Ham_Pink", normal=n))
    mouth = []
    for k in range(5):
        x = -0.04 + 0.02 * k
        z = 0.512 - (0.011 if k % 2 == 1 else 0.0)
        q, m = surface(body, Vector((x, 0.0, z)), (0, -1.0, 0.0))
        mouth.append(q + m * 0.003)
    objs.append(tube("Ham_Mouth", mouth, 0.004, "Mouth"))
    # Bigodes finos saindo das bochechas
    for sx in (1, -1):
        for dz, rise in ((0.015, 0.05), (-0.012, -0.03)):
            q, m = surface(body, Vector((sx * 0.10, 0.0, 0.545 + dz)), (sx * 0.35, -1.0, 0.0))
            a0 = q + m * 0.003
            tip = a0 + Vector((sx * 0.13, -0.03, rise))
            objs.append(tube("Ham_Whisker", [a0, a0.lerp(tip, 0.5) + Vector((0, -0.01, 0.006)), tip], 0.003, "Eye_Black"))
    return objs


# ---------------------------------------------------------------------------
# Montagem: escala real + cesto do balão
# ---------------------------------------------------------------------------
def basket_parts(feet_z):
    """Cesto de vime com borda, maçarico e quatro cabos até a "boca" do balão (em metros)."""
    objs = []
    gap = 4.0
    top = feet_z - gap
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(1.3, 1.3, 1.1), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(0, 0, top - 0.55), verts=bm.verts)
    me = bpy.data.meshes.new("Basket")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material("Basket"))
    o = bpy.data.objects.new("Basket", me)
    bpy.context.scene.collection.objects.link(o)
    objs.append(o)
    rim = tube("BasketRim", [(-0.68, -0.68, top), (0.68, -0.68, top), (0.68, 0.68, top), (-0.68, 0.68, top),
                             (-0.68, -0.68, top)], 0.06, "Basket", res=2)
    objs.append(rim)
    objs.append(ellipsoid("Burner", (0, 0, top + 0.6), (0.35, 0.35, 0.25), "Metal"))
    for sx, sy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        objs.append(tube("Cable", [(sx * 0.62, sy * 0.62, top), (sx * 0.9, sy * 0.9, feet_z + 0.3)], 0.025, "Rope", res=2))
    # Boca do balão (o tecido fecha embaixo dos pés)
    objs.append(ellipsoid("Throat", (0, 0, feet_z + 0.15), (1.2, 1.2, 0.5), "Rope"))
    return objs


def finish(name, objs):
    """Escala para metros, junta tudo num objeto, põe o cesto e exporta."""
    for o in objs:
        o.data.transform(Matrix.Scale(SCALE, 4))
    feet_z = min((o.matrix_world @ Vector(v)).z for o in objs for v in o.bound_box)
    objs += basket_parts(feet_z)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    # Base do cesto em y = 0 (o Godot põe o balão pela base)
    low = min(v.co.z for v in obj.data.vertices)
    obj.data.transform(Matrix.Translation((0, 0, -low)))
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print("%s: %d triângulos, %.1f m de altura" % (name, tris, max(v.co.z for v in obj.data.vertices)))
    if not ONLY or name.lower() in ONLY:
        os.makedirs(OUT_DIR, exist_ok=True)
        path = os.path.join(OUT_DIR, name.lower() + ".glb")
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                  export_yup=True, export_cameras=False, export_lights=False)
        print("  exportado:", os.path.relpath(path, ROOT))
    return obj


def render(obj, prefix):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_object_outline = True
    sh.object_outline_color = (0.05, 0.03, 0.03)
    sh.show_cavity = False
    sh.show_specular_highlight = True
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.color = (0.55, 0.7, 0.9)
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    h = max(v.co.z for v in obj.data.vertices)
    target = Vector((0, 0, h * 0.62))
    lo = min(v.co.z for v in obj.data.vertices if v.co.z > h * 0.3)
    mid = (lo + h) * 0.5
    span = (h - lo) * 1.12
    for vname, ang, el, dist, tz, ortho in (("frente", 0, 0, 2.6, mid / h, True), ("lado", 90, 0, 2.6, mid / h, True),
                                            ("tres_quartos", 35, 12, 2.4, mid / h, False),
                                            ("costas", 180, 10, 2.4, mid / h, False),
                                            ("rosto", 20, 6, 1.1, 0.80, False), ("inteiro", 25, 8, 3.6, 0.5, False)):
        a = math.radians(ang)
        e = math.radians(el)
        tgt = Vector((0, 0, h * tz))
        d = h * dist * 0.5
        cam.location = tgt + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * d
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam_data.type = "ORTHO" if ortho else "PERSP"
        cam_data.ortho_scale = span
        cam_data.angle = math.radians(32)
        scene.render.filepath = os.path.join(RENDER_DIR, "%s_%s.png" % (prefix, vname))
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    for name, fn in (("Psyduck", build_psyduck), ("Hamtaro", build_hamtaro)):
        if ONLY and name.lower() not in ONLY:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        obj = finish(name, fn())
        if RENDER_DIR:
            os.makedirs(RENDER_DIR, exist_ok=True)
            render(obj, name.lower())


if __name__ == "__main__":
    main()
