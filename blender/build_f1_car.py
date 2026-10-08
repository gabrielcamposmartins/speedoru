"""
Gerador procedural do carro de Fórmula 1 do F1 Gatcha (escala real, metros).

Uso (a partir da raiz do projeto):
    blender -b -P blender/build_f1_car.py              # gera .glb + .blend + renders
    blender -b -P blender/build_f1_car.py -- --no-render
    blender -b -P blender/build_f1_car.py -- --only=driver      # exporta só essas peças
    blender -b -P blender/build_f1_car.py -- --driver-preview <pasta>   # prévia do piloto

Convenções:
  * Coordenadas "de carro" usadas no script: x = lateral (+ esquerda), s = longitudinal
    (+ para frente), z = altura. Origem = chão, no meio do entre-eixos.
  * No Blender a frente do carro aponta para -Y (vista "Front"). O exportador glTF
    converte para Y-up, então no Godot a frente fica em +Z e a esquerda em +X,
    que é exatamente a convenção do VehicleBody3D.
  * Cada peça/variante é exportada em assets/car/parts/<slot>/<variante>.glb, todas com a
    mesma origem do carro (montagem = instanciar na identidade). Pneus e rodas são
    exportados com a origem no cubo da roda (eixo de rotação = X).
  * Os nomes dos materiais são "slots" que o Godot troca por materiais toon da pintura
    (Livery_Primary, Livery_Secondary, Livery_Accent, Carbon, Rim, Helmet...).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PARTS_DIR = os.path.join(ROOT, "assets", "car", "parts")
BLEND_PATH = os.path.join(HERE, "f1_car.blend")
RENDER_DIR = os.path.join(HERE, "renders")

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DO_RENDER = "--no-render" not in ARGS
# --only=driver,halo: exporta só essas peças (o .blend e os renders continuam completos)
ONLY = next((a.split("=", 1)[1].split(",") for a in ARGS if a.startswith("--only=")), [])

# ---------------------------------------------------------------------------
# Dimensões principais (regulamento 2022-2025, aproximadas)
# ---------------------------------------------------------------------------
FRONT_AXLE_S = 1.8          # entre-eixos de 3,6 m
REAR_AXLE_S = -1.8
WHEEL_RADIUS = 0.36         # pneu de 720 mm
BEAD_RADIUS = 0.235         # aro de 18"
FRONT_TYRE_WIDTH = 0.305
REAR_TYRE_WIDTH = 0.405
FRONT_HALF_TRACK = 0.83     # largura total ~1,98 m
REAR_HALF_TRACK = 0.79

# nome: (cor linear, rugosidade, metálico, emissão)
PALETTE = {
    "Livery_Primary": ((0.80, 0.02, 0.06), 0.35, 0.0, 0.0),
    "Livery_Secondary": ((0.90, 0.90, 0.93), 0.35, 0.0, 0.0),
    "Livery_Accent": ((0.0, 0.50, 0.90), 0.35, 0.0, 0.0),
    "Carbon": ((0.022, 0.022, 0.026), 0.30, 0.0, 0.0),
    "Interior": ((0.035, 0.035, 0.04), 0.80, 0.0, 0.0),
    "Tire": ((0.030, 0.030, 0.030), 0.85, 0.0, 0.0),
    "Tire_Stripe": ((0.95, 0.75, 0.0), 0.50, 0.0, 0.0),
    "Rim": ((0.05, 0.05, 0.06), 0.35, 0.6, 0.0),
    "Metal": ((0.55, 0.56, 0.60), 0.25, 1.0, 0.0),
    "Helmet": ((1.0, 0.78, 0.04), 0.25, 0.0, 0.0),
    "Visor": ((0.02, 0.03, 0.08), 0.05, 0.5, 0.0),
    "Suit": ((0.80, 0.02, 0.06), 0.70, 0.0, 0.0),
    "Light_Red": ((1.0, 0.02, 0.02), 0.30, 0.0, 4.0),
    "Mirror": ((0.60, 0.70, 0.80), 0.05, 1.0, 0.0),
    "Screen": ((0.10, 0.90, 0.80), 0.30, 0.0, 2.0),
}


def P(x, s, z):
    """Coordenada de carro -> coordenada do Blender (frente em -Y)."""
    return Vector((x, -s, z))


# ---------------------------------------------------------------------------
# Materiais
# ---------------------------------------------------------------------------
def get_material(name):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    color, rough, metal, emit = PALETTE[name]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.roughness = rough
    mat.metallic = metal
    if bpy.app.version < (5, 0, 0) and not mat.use_nodes:
        mat.use_nodes = True
    if mat.node_tree:
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (*color, 1.0)
            bsdf.inputs["Roughness"].default_value = rough
            bsdf.inputs["Metallic"].default_value = metal
            if emit > 0.0:
                bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
                bsdf.inputs["Emission Strength"].default_value = emit
    return mat


# ---------------------------------------------------------------------------
# Construção de malhas
# ---------------------------------------------------------------------------
class FaceCtx:
    """Contexto passado às funções de pintura: centro e normal em coordenadas de carro."""
    __slots__ = ("x", "s", "z", "nx", "ns", "nz", "tag", "u", "v", "el")

    def __init__(self, c, n, tag):
        self.x, self.s, self.z = c.x, -c.y, c.z
        self.nx, self.ns, self.nz = n.x, -n.y, n.z
        if isinstance(tag, tuple):
            self.tag, self.u, self.v = tag
        else:
            self.tag, self.u, self.v = tag, 0.0, 0.0
        # "elevação" no anel do loft: +1 = topo, -1 = fundo (segue as linhas da carroceria)
        self.el = math.sin(2.0 * math.pi * self.u)


class Builder:
    """Acumula geometria (em coordenadas do Blender) e gera um único objeto."""

    def __init__(self, name):
        self.name = name
        self.verts = []
        self.weights = []  # por vértice: {osso: peso} ou None (malhas com esqueleto)
        self.faces = []  # (indices, material ou função, tag)

    def add(self, mesh, mat, mirror=False, transform=None, weights=None):
        """weights: função(posição no Blender) -> {nome_do_osso: peso} para malhas com esqueleto."""
        verts, faces = mesh[0], mesh[1]
        tags = mesh[2] if len(mesh) > 2 else None
        if transform is not None:
            verts = [transform @ v for v in verts]
        for mirrored in ((False, True) if mirror else (False,)):
            base = len(self.verts)
            for v in verts:
                pos = Vector((-v.x, v.y, v.z)) if mirrored else Vector(v)
                self.verts.append(pos)
                self.weights.append(weights(pos) if weights else None)
            for i, f in enumerate(faces):
                idx = [base + k for k in f]
                if mirrored:
                    idx.reverse()
                self.faces.append((idx, mat, tags[i] if tags else "side"))
        return self

    def build(self, collection, origin=None, rot=None, smooth_angle=40.0):
        me = bpy.data.meshes.new(self.name)
        bm = bmesh.new()
        off = Vector(origin) if origin is not None else Vector((0, 0, 0))
        rot_m = rot.to_matrix() if rot is not None else Matrix.Identity(3)
        inv = rot_m.inverted()
        bverts = [bm.verts.new(inv @ (v - off)) for v in self.verts]
        records = []
        for idx, mat, tag in self.faces:
            clean = []
            for i in idx:
                if not clean or clean[-1] != i:
                    clean.append(i)
            if len(clean) < 3:
                continue
            try:
                face = bm.faces.new([bverts[i] for i in clean])
            except ValueError:
                continue
            records.append((face, mat, tag))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        mats = []
        for face, mat, tag in records:
            if callable(mat):
                center = rot_m @ face.calc_center_median() + off
                normal = rot_m @ face.normal
                mat = mat(FaceCtx(center, normal, tag))
            if mat not in mats:
                mats.append(mat)
            face.material_index = mats.index(mat)
        bm.to_mesh(me)
        bm.free()
        for m in mats:
            me.materials.append(get_material(m))
        for poly in me.polygons:
            poly.use_smooth = True
        try:
            me.set_sharp_from_angle(angle=math.radians(smooth_angle))
        except Exception:
            pass
        obj = bpy.data.objects.new(self.name, me)
        collection.objects.link(obj)
        if any(w for w in self.weights):
            groups = {}
            for vi, w in enumerate(self.weights):
                for bone, value in (w or {}).items():
                    if value <= 0.0:
                        continue
                    if bone not in groups:
                        groups[bone] = obj.vertex_groups.new(name=bone)
                    groups[bone].add([vi], value, "REPLACE")
        obj.location = off
        if rot is not None:
            obj.rotation_euler = rot
        return obj


def catmull(p0, p1, p2, p3, t):
    t2 = t * t
    t3 = t2 * t
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                  + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


def interp_dicts(items, keys, sub):
    """Interpola (Catmull-Rom) uma lista de seções-chave para suavizar o loft."""
    if sub <= 1 or len(items) < 2:
        return [dict(d) for d in items]
    out = []
    n = len(items)
    for i in range(n - 1):
        p0, p1 = items[max(i - 1, 0)], items[i]
        p2, p3 = items[i + 1], items[min(i + 2, n - 1)]
        for k in range(sub):
            t = k / sub
            out.append({key: catmull(p0[key], p1[key], p2[key], p3[key], t) for key in keys})
    out.append(dict(items[-1]))
    return out


def skin(rings, cap0=True, cap1=True, closed=True, wrap=False):
    """Liga anéis de vértices com quads. Retorna (verts, faces, tags)."""
    n = len(rings[0])
    count = len(rings)
    verts = [v for r in rings for v in r]
    faces, tags = [], []
    for k in range(count if wrap else count - 1):
        k2 = (k + 1) % count
        for i in range(n if closed else n - 1):
            i2 = (i + 1) % n
            faces.append([k * n + i, k * n + i2, k2 * n + i2, k2 * n + i])
            tags.append(("side", (i + 0.5) / n, (k + 0.5) / max(count - 1, 1)))
    if closed and cap0:
        faces.append(list(range(n))[::-1])
        tags.append("cap0")
    if closed and cap1:
        base = (count - 1) * n
        faces.append(list(range(base, base + n)))
        tags.append("cap1")
    return verts, faces, tags


# --- Loft de superelipses (carenagens) --------------------------------------
SEC_KEYS = ("s", "cx", "hw", "zb", "zt", "nt", "nb")


def S(s, hw, zb, zt, cx=0.0, nt=2.5, nb=3.0):
    """Seção transversal: posição s, meia-largura, base, topo, centro x e expoentes."""
    return dict(s=s, cx=cx, hw=hw, zb=zb, zt=zt, nt=nt, nb=nb)


def _sgnpow(v, e):
    return math.copysign(abs(v) ** e, v)


def ring(sec, n):
    zm = (sec["zb"] + sec["zt"]) * 0.5
    pts = []
    for i in range(n):
        a = 2.0 * math.pi * i / n
        c, sn = math.cos(a), math.sin(a)
        e = sec["nt"] if sn >= 0 else sec["nb"]
        x = sec["cx"] + sec["hw"] * _sgnpow(c, 2.0 / e)
        half = (sec["zt"] - zm) if sn >= 0 else (zm - sec["zb"])
        z = zm + half * _sgnpow(sn, 2.0 / e)
        pts.append(P(x, sec["s"], z))
    return pts


def loft(secs, n=40, sub=4, cap0=True, cap1=True):
    secs = interp_dicts(secs, SEC_KEYS, sub)
    for d in secs:
        d["hw"] = max(d["hw"], 0.003)
        d["zt"] = max(d["zt"], d["zb"] + 0.003)
        d["nt"] = max(d["nt"], 1.2)
        d["nb"] = max(d["nb"], 1.2)
    return skin([ring(d, n) for d in secs], cap0, cap1)


def ellipsoid(cx, cs, cz, rx, rs, rz, n=32, rows=14):
    secs = []
    for i in range(rows + 1):
        t = -1.0 + 2.0 * i / rows
        t = math.copysign(abs(t) ** 0.85, t)
        k = math.sqrt(max(1.0 - t * t, 0.0004))
        secs.append(S(cs + rs * t, rx * k, cz - rz * k, cz + rz * k, cx=cx, nt=2.0, nb=2.0))
    secs.reverse()  # da frente para trás
    return loft(secs, n=n, sub=1)


# --- Asas com perfil aerodinâmico -------------------------------------------
WING_KEYS = ("x", "s", "z", "c", "a", "t", "m")


def W(x, s, z, c, a, t=0.10, m=0.05):
    """Estação de asa: posição x, bordo de ataque (s, z), corda, ângulo (graus)."""
    return dict(x=x, s=s, z=z, c=c, a=a, t=t, m=m)


def airfoil(n=10, t=0.12, m=0.05, p=0.4):
    """Perfil NACA 4 dígitos fechado (u ao longo da corda, v espessura)."""
    xs = [0.5 * (1.0 - math.cos(math.pi * i / n)) for i in range(n + 1)]

    def yt(x):
        return 5 * t * (0.2969 * math.sqrt(x) - 0.1260 * x - 0.3516 * x ** 2
                        + 0.2843 * x ** 3 - 0.1036 * x ** 4)

    def yc(x):
        if m == 0:
            return 0.0
        if x < p:
            return m / p ** 2 * (2 * p * x - x * x)
        return m / (1 - p) ** 2 * ((1 - 2 * p) + 2 * p * x - x * x)

    upper = [(x, yc(x) + yt(x)) for x in reversed(xs)]
    lower = [(x, yc(x) - yt(x)) for x in xs[1:-1]]
    return upper + lower


def wing(stations, n=10, sub=3, symmetric=False):
    """Asa invertida (gera downforce) varrida pelas estações ao longo da envergadura."""
    st = stations
    if symmetric:
        st = [dict(d, x=-d["x"]) for d in reversed(stations) if d["x"] > 1e-6] + stations
    st = interp_dicts(st, WING_KEYS, sub)
    rings = []
    for d in st:
        a = math.radians(d["a"])
        ca, sa = math.cos(a), math.sin(a)
        pts = []
        for u, v in airfoil(n, d["t"], d["m"]):
            u *= d["c"]
            v *= -d["c"]  # perfil invertido
            back = u * ca - v * sa
            up = u * sa + v * ca
            pts.append(P(d["x"], d["s"] - back, d["z"] + up))
        rings.append(pts)
    return skin(rings)


def wing_te(st):
    a = math.radians(st["a"])
    return st["s"] - st["c"] * math.cos(a), st["z"] + st["c"] * math.sin(a)


# --- Primitivas ---------------------------------------------------------------
def plate(profile, x0, th):
    """Placa fina: perfil lateral (s, z) extrudado em x."""
    n = len(profile)
    verts = [P(x0 - th / 2, s, z) for s, z in profile] + [P(x0 + th / 2, s, z) for s, z in profile]
    faces = [list(range(n)), list(range(n, 2 * n))[::-1]]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, n + j, n + i])
    return verts, faces


def slab(profile, z0, z1):
    """Placa horizontal: contorno em planta (x, s) extrudado em z."""
    n = len(profile)
    verts = [P(x, s, z0) for x, s in profile] + [P(x, s, z1) for x, s in profile]
    faces = [list(range(n)), list(range(n, 2 * n))[::-1]]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, n + j, n + i])
    return verts, faces


def box(x, s, z, hx, hs, hz):
    verts = [P(x + dx * hx, s + ds * hs, z + dz * hz)
             for dz in (-1, 1) for ds in (-1, 1) for dx in (-1, 1)]
    faces = [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
    return verts, faces


def rod(p1, p2, r, sides=8, flat=1.0):
    """Barra entre dois pontos; flat < 1 achata verticalmente (perfil aerodinâmico)."""
    a, b = P(*p1), P(*p2)
    d = (b - a).normalized()
    ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    u = d.cross(ref).normalized()
    w = u.cross(d).normalized()
    rings = []
    for c in (a, b):
        rings.append([c + u * (r * math.cos(2 * math.pi * i / sides))
                      + w * (r * flat * math.sin(2 * math.pi * i / sides)) for i in range(sides)])
    return skin(rings)


def tube(points, r, sides=12, sub=6, flat=1.0):
    """Tubo ao longo de uma spline Catmull-Rom (ex.: halo)."""
    pts = [P(*p) for p in points]
    path = []
    for i in range(len(pts) - 1):
        p0, p1 = pts[max(i - 1, 0)], pts[i]
        p2, p3 = pts[i + 1], pts[min(i + 2, len(pts) - 1)]
        for k in range(sub):
            path.append(catmull(p0, p1, p2, p3, k / sub))
    path.append(pts[-1])
    tangents = [(path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
                for i in range(len(path))]
    ref = Vector((0, 0, 1)) if abs(tangents[0].z) < 0.9 else Vector((1, 0, 0))
    normal = tangents[0].cross(ref).normalized()
    rings = []
    for c, t in zip(path, tangents):
        normal = (normal - t * normal.dot(t)).normalized()
        binormal = t.cross(normal)
        rings.append([c + normal * (r * math.cos(2 * math.pi * i / sides))
                      + binormal * (r * flat * math.sin(2 * math.pi * i / sides))
                      for i in range(sides)])
    return skin(rings)


def lathe(profile, segments=48, a0=0.0, a1=2 * math.pi):
    """Revolve um perfil fechado (a = axial em X, r = raio) em torno do eixo X."""
    full = abs((a1 - a0) - 2 * math.pi) < 1e-6
    rings = []
    for k in range(segments if full else segments + 1):
        t = a0 + (a1 - a0) * k / segments
        rings.append([Vector((a, r * math.cos(t), r * math.sin(t))) for a, r in profile])
    return skin(rings, cap0=not full, cap1=not full, wrap=full)


def radial_box(theta, r0, r1, a0, a1, w0, w1):
    """Caixa radial (raio de roda) no plano YZ, entre os raios r0 e r1."""
    d = Vector((0, math.cos(theta), math.sin(theta)))
    p = Vector((0, -math.sin(theta), math.cos(theta)))
    verts = []
    for a in (a0, a1):
        for r, w in ((r0, w0), (r1, w1)):
            for sgn in (-1, 1):
                verts.append(Vector((a, 0, 0)) + d * r + p * (sgn * w / 2))
    faces = [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
    return verts, faces


# ---------------------------------------------------------------------------
# Pintura (atribuição de materiais por região)
# ---------------------------------------------------------------------------
def paint_body(c):
    if c.tag != "side":
        return "Livery_Primary"
    if c.el < -0.70:
        return "Carbon"
    if c.el > 0.42:
        return "Livery_Primary"
    if c.el > 0.22:
        return "Livery_Accent"
    return "Livery_Secondary"


def paint_nose(c):
    if c.tag != "side":
        return "Livery_Accent"
    if c.el < -0.70:
        return "Carbon"
    if c.v < 0.12:
        return "Livery_Accent"
    if c.el > 0.15:
        return "Livery_Primary"
    return "Livery_Secondary"


def paint_sidepod(c):
    if c.tag == "cap0":
        return "Interior"
    if c.tag != "side":
        return "Livery_Secondary"
    if c.el < -0.60:
        return "Carbon"
    if c.el > 0.50:
        return "Livery_Primary"
    if c.el > 0.28 and c.v > 0.08:
        return "Livery_Accent"
    return "Livery_Secondary"


def paint_wing(top, bottom="Carbon"):
    def fn(c):
        return top if c.nz > -0.2 else bottom
    return fn


# ---------------------------------------------------------------------------
# Peças
# ---------------------------------------------------------------------------
def apply_boolean_difference(obj, cutter_mesh, cutter_mat, collection):
    """Recorta o cockpit; as faces novas herdam o material do cortador."""
    cb = Builder(obj.name + "_cutter")
    cb.add(cutter_mesh, cutter_mat)
    cutter = cb.build(collection)
    mod = obj.modifiers.new("cockpit", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter
    try:
        mod.material_mode = "TRANSFER"
        mod.use_hole_tolerant = True
    except Exception:
        pass
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    new_mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    obj.modifiers.clear()
    old = obj.data
    obj.data = new_mesh
    bpy.data.meshes.remove(old)
    new_mesh.name = obj.name
    cutter_data = cutter.data
    bpy.data.objects.remove(cutter)
    bpy.data.meshes.remove(cutter_data)
    for poly in new_mesh.polygons:
        poly.use_smooth = True
    try:
        new_mesh.set_sharp_from_angle(angle=math.radians(40))
    except Exception:
        pass


def build_chassis(col):
    b = Builder("Chassis")
    secs = [
        S(1.65, 0.20, 0.23, 0.56, nt=2.6, nb=3.0),
        S(1.20, 0.25, 0.17, 0.62, nt=2.6, nb=4.0),
        S(0.80, 0.31, 0.12, 0.66, nt=2.8, nb=5.0),
        S(0.45, 0.36, 0.08, 0.67, nt=3.0, nb=6.0),
        S(0.00, 0.40, 0.07, 0.665, nt=3.0, nb=6.0),
        S(-0.30, 0.40, 0.07, 0.67, nt=3.0, nb=6.0),
        S(-0.58, 0.38, 0.07, 0.70, nt=3.0, nb=6.0),
    ]
    b.add(loft(secs, n=48, sub=4), paint_body)
    obj = b.build(col)
    cutter = loft([
        S(0.47, 0.10, 0.32, 1.20, nt=4, nb=4),
        S(0.38, 0.20, 0.30, 1.20, nt=4, nb=4),
        S(0.10, 0.255, 0.30, 1.20, nt=4, nb=4),
        S(-0.28, 0.25, 0.30, 1.20, nt=4, nb=4),
        S(-0.40, 0.20, 0.30, 1.20, nt=4, nb=4),
        S(-0.44, 0.10, 0.30, 1.20, nt=4, nb=4),
    ], n=32, sub=3)
    apply_boolean_difference(obj, cutter, "Interior", col)
    return [obj]


def build_nose(col, variant):
    b = Builder("Nose_" + variant)
    if variant == "pointed":
        secs = [S(2.92, 0.025, 0.125, 0.17, nt=2.0, nb=2.0),
                S(2.80, 0.065, 0.115, 0.23, nt=2.2, nb=2.5),
                S(2.50, 0.11, 0.12, 0.32, nt=2.4, nb=3.0),
                S(2.15, 0.15, 0.15, 0.42, nt=2.5, nb=3.0),
                S(1.90, 0.18, 0.19, 0.50, nt=2.6, nb=3.0),
                S(1.58, 0.205, 0.23, 0.565, nt=2.6, nb=3.0)]
    else:
        secs = [S(2.81, 0.04, 0.12, 0.19, nt=2.0, nb=2.2),
                S(2.72, 0.095, 0.11, 0.25, nt=2.3, nb=3.0),
                S(2.45, 0.135, 0.12, 0.33, nt=2.5, nb=3.5),
                S(2.15, 0.16, 0.15, 0.42, nt=2.6, nb=3.5),
                S(1.90, 0.185, 0.19, 0.50, nt=2.6, nb=3.0),
                S(1.58, 0.205, 0.23, 0.565, nt=2.6, nb=3.0)]
    b.add(loft(secs, n=40, sub=4), paint_nose)
    # Pilares que ligam o bico ao plano principal da asa
    b.add(plate([(2.66, 0.08), (2.40, 0.08), (2.40, 0.16), (2.66, 0.13)], 0.075, 0.012), "Carbon", mirror=True)
    return [b.build(col)]


def front_wing_elements(variant):
    """Retorna lista de (estações, simétrica?, material) dos elementos da asa dianteira."""
    main = [W(0.00, 2.86, 0.085, 0.44, 2, t=0.07, m=0.04),
            W(0.30, 2.86, 0.085, 0.44, 3, t=0.07, m=0.04),
            W(0.60, 2.81, 0.075, 0.40, 5, t=0.07, m=0.05),
            W(0.90, 2.72, 0.070, 0.34, 7, t=0.07, m=0.05),
            W(0.97, 2.69, 0.070, 0.32, 7, t=0.07, m=0.05)]
    if variant == "lowdf":
        main = [dict(st, a=st["a"] - 2) for st in main]
        flaps = [
            [W(0.16, 2.48, 0.110, 0.13, 10), W(0.5, 2.47, 0.118, 0.14, 13), W(0.97, 2.44, 0.135, 0.15, 15)],
            [W(0.20, 2.37, 0.140, 0.11, 18), W(0.5, 2.35, 0.150, 0.12, 22), W(0.97, 2.32, 0.175, 0.13, 25)],
        ]
    else:
        flaps = [
            [W(0.16, 2.48, 0.115, 0.13, 14), W(0.5, 2.47, 0.125, 0.15, 18), W(0.97, 2.47, 0.150, 0.17, 22)],
            [W(0.20, 2.37, 0.155, 0.12, 26), W(0.5, 2.35, 0.175, 0.13, 30), W(0.97, 2.36, 0.210, 0.15, 34)],
            [W(0.24, 2.27, 0.220, 0.10, 38), W(0.5, 2.26, 0.240, 0.11, 42), W(0.97, 2.27, 0.290, 0.12, 46)],
        ]
    flap_mats = ["Livery_Secondary", "Livery_Primary", "Livery_Accent"]
    elements = [(main, True, "Livery_Primary")]
    for i, st in enumerate(flaps):
        elements.append((st, False, flap_mats[i]))
    return elements


def build_front_wing(col, variant):
    b = Builder("FrontWing_" + variant)
    for stations, symmetric, mat in front_wing_elements(variant):
        b.add(wing(stations, n=10, sub=3, symmetric=symmetric), paint_wing(mat), mirror=not symmetric)
    if variant == "lowdf":
        endplate = [(2.71, 0.05), (2.72, 0.12), (2.50, 0.18), (2.30, 0.24), (2.20, 0.25),
                    (2.20, 0.18), (2.35, 0.12), (2.45, 0.05)]
    else:
        endplate = [(2.71, 0.05), (2.73, 0.12), (2.55, 0.20), (2.36, 0.30), (2.20, 0.34),
                    (2.19, 0.27), (2.30, 0.18), (2.45, 0.05)]
    b.add(plate(endplate, 0.975, 0.012), "Livery_Primary", mirror=True)
    # Pequeno "footplate" na base da placa lateral
    b.add(slab([(0.93, 2.70), (0.98, 2.70), (0.98, 2.40), (0.93, 2.45)], 0.045, 0.055), "Carbon", mirror=True)
    return [b.build(col)]


def build_engine_cover(col, variant):
    b = Builder("EngineCover_" + variant)
    # Entrada de ar (airbox) sobre a cabeça do piloto; a tampa frontal vira a boca escura.
    airbox = [S(-0.30, 0.12, 0.70, 0.95, nt=2.0, nb=2.0),
              S(-0.34, 0.135, 0.66, 0.97, nt=2.2, nb=2.2),
              S(-0.60, 0.15, 0.55, 0.965, nt=2.4, nb=2.4),
              S(-1.00, 0.13, 0.50, 0.83, nt=2.4, nb=2.4),
              S(-1.40, 0.08, 0.45, 0.66, nt=2.4, nb=2.4)]
    b.add(loft(airbox, n=36, sub=4), lambda c: "Interior" if c.tag == "cap0" else paint_body(c))
    cover = [S(-0.50, 0.37, 0.10, 0.72, nt=2.6, nb=6.0),
             S(-0.80, 0.33, 0.10, 0.74, nt=2.6, nb=6.0),
             S(-1.15, 0.26, 0.10, 0.68, nt=2.6, nb=6.0),
             S(-1.50, 0.19, 0.12, 0.58, nt=2.6, nb=5.0),
             S(-1.85, 0.14, 0.15, 0.47, nt=2.6, nb=4.0),
             S(-2.10, 0.10, 0.18, 0.42, nt=2.6, nb=3.0),
             S(-2.25, 0.06, 0.24, 0.36, nt=2.4, nb=2.4)]
    b.add(loft(cover, n=44, sub=4), paint_body)
    # Estrutura de impacto traseira + luz de chuva
    crash = [S(-2.15, 0.07, 0.20, 0.34, nt=2.5, nb=2.5),
             S(-2.35, 0.06, 0.21, 0.31, nt=2.5, nb=2.5),
             S(-2.52, 0.05, 0.22, 0.29, nt=2.5, nb=2.5)]
    b.add(loft(crash, n=20, sub=2), "Carbon")
    b.add(box(0.0, -2.525, 0.255, 0.04, 0.008, 0.022), "Light_Red")
    # T-cam (câmera de TV sobre o airbox)
    b.add(box(0.0, -0.66, 0.985, 0.055, 0.07, 0.02), "Livery_Accent")
    b.add(rod((0.0, -0.66, 0.96), (0.0, -0.66, 0.975), 0.012, sides=8), "Carbon")
    if variant == "sharkfin":
        fin = [(-0.75, 0.94), (-1.95, 0.80), (-2.02, 0.44), (-1.50, 0.54), (-1.0, 0.78)]
        b.add(plate(fin, 0.0, 0.010), lambda c: "Livery_Accent" if c.z > 0.70 else "Livery_Primary")
    return [b.build(col)]


def sidepod_sections(variant):
    if variant == "slim":
        return [S(0.32, 0.10, 0.50, 0.70, cx=0.50, nt=3.0, nb=3.0),
                S(0.22, 0.12, 0.30, 0.70, cx=0.49, nt=3.0, nb=3.0),
                S(0.05, 0.12, 0.13, 0.69, cx=0.47, nt=3.0, nb=4.0),
                S(-0.20, 0.10, 0.10, 0.62, cx=0.43, nt=2.8, nb=5.0),
                S(-0.60, 0.08, 0.10, 0.52, cx=0.38, nt=2.6, nb=5.0),
                S(-1.00, 0.07, 0.10, 0.42, cx=0.30, nt=2.5, nb=5.0),
                S(-1.40, 0.05, 0.10, 0.30, cx=0.22, nt=2.5, nb=4.0)]
    return [S(0.34, 0.15, 0.52, 0.665, cx=0.55, nt=3.0, nb=3.0),
            S(0.24, 0.19, 0.36, 0.68, cx=0.56, nt=3.0, nb=3.0),
            S(0.08, 0.215, 0.14, 0.68, cx=0.55, nt=3.0, nb=4.0),
            S(-0.10, 0.23, 0.10, 0.66, cx=0.52, nt=2.8, nb=5.0),
            S(-0.50, 0.22, 0.08, 0.56, cx=0.47, nt=2.4, nb=5.0),
            S(-0.90, 0.17, 0.08, 0.44, cx=0.38, nt=2.4, nb=5.0),
            S(-1.30, 0.11, 0.08, 0.33, cx=0.28, nt=2.4, nb=4.0),
            S(-1.60, 0.06, 0.08, 0.25, cx=0.20, nt=2.4, nb=3.0)]


def build_sidepods(col, variant):
    b = Builder("Sidepods_" + variant)
    b.add(loft(sidepod_sections(variant), n=40, sub=4), paint_sidepod, mirror=True)
    return [b.build(col)]


def build_floor(col):
    b = Builder("Floor")
    right = [(0.12, 1.38), (0.30, 1.30), (0.50, 1.00), (0.70, 0.70), (0.80, 0.45), (0.82, -0.40),
             (0.80, -0.95), (0.72, -1.25), (0.60, -1.42), (0.56, -1.53)]
    outline = right + [(-x, s) for x, s in reversed(right)]
    b.add(slab(outline, 0.040, 0.056), "Carbon")
    # Prancha (plank) de madeira/carbono sob o assoalho
    b.add(box(0.0, -0.05, 0.034, 0.15, 1.25, 0.007), "Carbon")
    # Borda do assoalho ("edge wing")
    b.add(tube([(0.68, 0.72, 0.058), (0.80, 0.45, 0.075), (0.83, -0.40, 0.09), (0.81, -0.95, 0.08)],
               0.016, sides=8, sub=4, flat=0.6), "Livery_Accent", mirror=True)
    # Difusor: teto em rampa + defletores verticais
    secs = []
    for i in range(7):
        t = i / 6
        z = 0.056 + 0.27 * (t ** 1.6)
        secs.append(S(-1.53 - 0.62 * t, 0.56, z - 0.006, z + 0.006, nt=12, nb=12))
    b.add(loft(secs, n=24, sub=1), "Carbon")
    roof = [(-1.53 - 0.62 * i / 8, 0.056 + 0.27 * ((i / 8) ** 1.6) - 0.004) for i in range(9)]
    for x in (0.0, 0.28, 0.55):
        strake = [(-1.60, 0.05), (-2.15, 0.05)] + [pt for pt in reversed(roof) if pt[0] < -1.62]
        b.add(plate(strake, x, 0.008), "Carbon", mirror=x > 0)
    return [b.build(col)]


def build_halo(col):
    b = Builder("Halo")
    loop = [(0.36, -0.40, 0.60), (0.39, -0.30, 0.75), (0.37, -0.08, 0.83), (0.25, 0.15, 0.86),
            (0.0, 0.26, 0.875), (-0.25, 0.15, 0.86), (-0.37, -0.08, 0.83), (-0.39, -0.30, 0.75),
            (-0.36, -0.40, 0.60)]
    b.add(tube(loop, 0.024, sides=14, sub=6), "Livery_Primary")
    b.add(tube([(0.0, 0.26, 0.875), (0.0, 0.36, 0.80), (0.0, 0.48, 0.64)], 0.022, sides=10, sub=4, flat=0.6),
          "Livery_Primary")
    return [b.build(col)]


# Posição dos retrovisores: à frente do piloto e dentro do campo de visão da câmera de 1ª pessoa.
MIRROR_X = 0.50
MIRROR_GLASS_S = 0.424
MIRROR_Z = 0.7475


def build_mirrors(col):
    """Carcaças + "vidros" separados (MirrorGlassL/R, origem no centro). No Godot o vidro recebe a
    imagem de uma câmera traseira (retrovisor funcional)."""
    b = Builder("Mirrors")
    housing = [S(0.485, 0.012, 0.735, 0.755, cx=MIRROR_X, nt=3, nb=3),
               S(0.470, 0.075, 0.72, 0.775, cx=MIRROR_X, nt=4, nb=4),
               S(0.425, 0.085, 0.715, 0.78, cx=MIRROR_X, nt=4, nb=4)]
    b.add(loft(housing, n=24, sub=2),
          lambda c: "Carbon" if c.tag == "cap1" else "Livery_Primary", mirror=True)
    b.add(rod((0.44, 0.45, 0.725), (0.33, 0.44, 0.63), 0.011, sides=8, flat=0.5), "Carbon", mirror=True)
    objs = [b.build(col)]
    for side, suffix in ((1, "L"), (-1, "R")):
        gb = Builder("MirrorGlass" + suffix)
        gb.add(box(side * MIRROR_X, MIRROR_GLASS_S, MIRROR_Z, 0.078, 0.0015, 0.029), "Mirror")
        objs.append(gb.build(col, origin=P(side * MIRROR_X, MIRROR_GLASS_S, MIRROR_Z)))
    return objs


def build_suspension_front(col):
    b = Builder("SuspensionFront")
    s = FRONT_AXLE_S
    rods = [((0.17, 1.98, 0.45), (0.70, s, 0.50)), ((0.19, 1.55, 0.50), (0.70, s, 0.50)),
            ((0.16, 2.10, 0.25), (0.73, s, 0.20)), ((0.17, 1.45, 0.24), (0.73, s, 0.20)),
            ((0.70, 1.83, 0.22), (0.20, 1.78, 0.52)), ((0.18, 1.70, 0.36), (0.70, 1.68, 0.33))]
    for p1, p2 in rods:
        b.add(rod(p1, p2, 0.018, sides=8, flat=0.45), "Carbon", mirror=True)
    return [b.build(col)]


def build_suspension_rear(col):
    b = Builder("SuspensionRear")
    s = REAR_AXLE_S
    rods = [((0.14, -1.55, 0.52), (0.66, s, 0.55)), ((0.14, -2.05, 0.50), (0.66, s, 0.55)),
            ((0.13, -1.45, 0.18), (0.68, s, 0.16)), ((0.12, -2.10, 0.20), (0.68, s, 0.16)),
            ((0.66, -1.78, 0.50), (0.15, -1.75, 0.20)), ((0.12, -2.00, 0.30), (0.66, -2.00, 0.30))]
    for p1, p2 in rods:
        b.add(rod(p1, p2, 0.018, sides=8, flat=0.45), "Carbon", mirror=True)
    b.add(rod((0.08, s, 0.36), (0.64, s, 0.36), 0.025, sides=10), "Metal", mirror=True)
    return [b.build(col)]


def rear_wing_params(variant):
    if variant == "lowdf":
        return dict(main_c=0.26, main_a=6, main_z=0.76, flap_c=0.16, flap_a=20, spoon=0.0)
    if variant == "highdf":
        return dict(main_c=0.33, main_a=14, main_z=0.74, flap_c=0.28, flap_a=42, spoon=0.04)
    return dict(main_c=0.30, main_a=10, main_z=0.75, flap_c=0.22, flap_a=32, spoon=0.02)


def build_rear_wing(col, variant):
    p = rear_wing_params(variant)
    b = Builder("RearWing_" + variant)
    span = [0.0, 0.25, 0.42, 0.49]
    main = [W(x, -2.36, p["main_z"] + p["spoon"] * (1 - (x / 0.49) ** 2), p["main_c"], p["main_a"],
              t=0.12, m=0.06) for x in span]
    b.add(wing(main, n=12, sub=3, symmetric=True), paint_wing("Livery_Primary"))
    # Placas laterais (endplates) com luz de chuva LED
    endplate = [(-2.27, 0.58), (-2.29, 0.90), (-2.36, 0.985), (-2.80, 0.99), (-2.84, 0.80),
                (-2.78, 0.62), (-2.56, 0.55)]
    b.add(plate(endplate, 0.50, 0.012), "Livery_Primary", mirror=True)
    b.add(plate([(-2.19, 0.27), (-2.27, 0.60), (-2.40, 0.58), (-2.52, 0.27)], 0.495, 0.010), "Carbon", mirror=True)
    b.add(box(0.50, -2.85, 0.80, 0.004, 0.006, 0.12), "Light_Red", mirror=True)
    # Beam wing
    beam1 = [W(x, -2.20, 0.30, 0.18, 8, t=0.10, m=0.05) for x in (0.0, 0.49)]
    beam2 = [W(x, -2.36, 0.37, 0.16, 22, t=0.10, m=0.05) for x in (0.0, 0.49)]
    b.add(wing(beam1, n=8, sub=1, symmetric=True), "Carbon")
    b.add(wing(beam2, n=8, sub=1, symmetric=True), "Carbon")
    # Pilar central ("swan neck") apoiado na estrutura de impacto
    main_lo = p["main_z"] + p["spoon"] - 0.02
    b.add(plate([(-2.22, 0.27), (-2.42, 0.27), (-2.52, main_lo), (-2.40, main_lo)], 0.0, 0.022), "Carbon")
    wing_obj = b.build(col)

    # Flap do DRS: objeto separado com pivô no bordo de fuga, para animar no Godot
    flap_le_s = -2.36 - p["main_c"] * math.cos(math.radians(p["main_a"])) + 0.07
    flap_le_z = p["main_z"] + p["main_c"] * math.sin(math.radians(p["main_a"])) + 0.035
    flap = [W(x, flap_le_s, flap_le_z + p["spoon"] * (1 - (x / 0.49) ** 2), p["flap_c"], p["flap_a"],
              t=0.11, m=0.06) for x in span]
    pivot_s, pivot_z = wing_te(flap[0])
    fb = Builder("DRSFlap_" + variant)
    fb.add(wing(flap, n=10, sub=3, symmetric=True), paint_wing("Livery_Accent"))
    flap_obj = fb.build(col, origin=P(0.0, pivot_s, pivot_z))
    return [wing_obj, flap_obj]


STEERING_PIVOT = (0.0, 0.36, 0.585)
STEERING_TILT = math.radians(20)
# Centro da palma nas manoplas, no espaço do volante (x, s, z de carro, antes da inclinação)
GRIP_LOCAL = (0.128, -0.012, -0.01)


def steering_matrix():
    return Matrix.Translation(P(*STEERING_PIVOT)) @ Euler((STEERING_TILT, 0, 0)).to_matrix().to_4x4()


def grip_point(side):
    """Centro da manopla (coordenadas do Blender); side = +1 esquerda, -1 direita."""
    return steering_matrix() @ P(side * GRIP_LOCAL[0], GRIP_LOCAL[1], GRIP_LOCAL[2])


def build_cockpit(col):
    """Volante como objeto separado (pivô no centro) para girar com a direção."""
    tilt = STEERING_TILT
    pivot = P(*STEERING_PIVOT)
    m = steering_matrix()
    b = Builder("SteeringWheel")
    b.add(box(0, 0, 0, 0.115, 0.018, 0.058), "Carbon", transform=m)
    for sx in (-1, 1):
        b.add(rod((sx * 0.125, 0.0, -0.075), (sx * 0.125, 0.0, 0.055), 0.022, sides=10), "Interior",
              transform=m)
    b.add(box(0, -0.020, 0.012, 0.045, 0.003, 0.028), "Screen", transform=m)
    b.add(box(0, -0.020, 0.050, 0.065, 0.003, 0.005), "Light_Red", transform=m)
    for bx, bz in ((-0.08, -0.02), (0.08, -0.02), (-0.08, 0.025), (0.08, 0.025)):
        b.add(box(bx, -0.020, bz, 0.010, 0.004, 0.010), "Livery_Accent", transform=m)
    wheel_obj = b.build(col, origin=pivot, rot=Euler((tilt, 0, 0)))
    # Encostos de cabeça (proteções laterais do cockpit)
    hb = Builder("Headrest")
    hb.add(loft([S(-0.02, 0.05, 0.50, 0.70, cx=0.20, nt=3, nb=3),
                 S(-0.34, 0.06, 0.50, 0.72, cx=0.19, nt=3, nb=3)], n=20, sub=1), "Interior", mirror=True)
    return [wheel_obj, hb.build(col)]


# Distância do pulso ao centro da palma, ao longo do osso da mão (o DriverRig usa o mesmo valor).
HAND_PALM_OFFSET = 0.05


def car_xyz(v):
    """Coordenada do Blender -> (x, s, z) de carro."""
    return (v.x, -v.y, v.z)


# --- Piloto humanoide low poly ---------------------------------------------------
class Sweep:
    """Tubo de seção superelíptica ao longo de um caminho Catmull-Rom (coordenadas de carro).

    secs: uma por ponto do caminho, (rx, ry, expoente[, deslocamento em ry]); rx segue `side`
    (projetado no plano da seção) e ry a normal = tangente × side.
    round0/round1: fecha a ponta com uma calota arredondada (juntas sem "tampa" chapada); o
    comprimento da calota é round * raio. Os índices de anel de point() ignoram as calotas.
    """

    CAP_ANGLES = (80.0, 62.0, 40.0)

    def __init__(self, path, secs, side=(1.0, 0.0, 0.0), sub=2, n=12, round0=0.0, round1=0.0):
        pts = [Vector(p) for p in path]
        self.n = n
        self.centers, params = [], []
        for i in range(len(pts) - 1):
            p0, p1 = pts[max(i - 1, 0)], pts[i]
            p2, p3 = pts[i + 1], pts[min(i + 2, len(pts) - 1)]
            for k in range(sub):
                self.centers.append(catmull(p0, p1, p2, p3, k / sub))
                params.append(i + k / sub)
        self.centers.append(pts[-1])
        params.append(len(pts) - 1.0)
        self.secs = []
        for prm in params:
            i = min(int(prm), len(secs) - 2)
            f = prm - i
            a = tuple(secs[i]) + (0.0,) * (4 - len(secs[i]))
            b = tuple(secs[i + 1]) + (0.0,) * (4 - len(secs[i + 1]))
            self.secs.append(tuple(a[j] + (b[j] - a[j]) * f for j in range(4)))
        self.base0 = self.base1 = 0
        if round0 > 0.0:
            self._cap(0, round0)
        if round1 > 0.0:
            self._cap(-1, round1)
        self.last = len(self.centers) - 1 - self.base0 - self.base1
        side = Vector(side)
        self.frames = []
        m = len(self.centers)
        for i in range(m):
            t = (self.centers[min(i + 1, m - 1)] - self.centers[max(i - 1, 0)]).normalized()
            sd = (side - t * side.dot(t)).normalized()
            self.frames.append((t, sd, t.cross(sd)))

    def _cap(self, end, length):
        c, (rx, ry, e, oy) = self.centers[end], self.secs[end]
        nb = self.centers[1] if end == 0 else self.centers[-2]
        out = (c - nb).normalized()
        rings = []
        for deg in self.CAP_ANGLES:
            ang = math.radians(deg)
            k = math.cos(ang)
            rings.append((c + out * (length * max(rx, ry) * math.sin(ang)), (rx * k, ry * k, e, oy)))
        if end == 0:
            self.centers[:0] = [r[0] for r in rings]
            self.secs[:0] = [r[1] for r in rings]
            self.base0 = len(rings)
        else:
            self.centers.extend(r[0] for r in reversed(rings))
            self.secs.extend(r[1] for r in reversed(rings))
            self.base1 = len(rings)

    def radius(self, fi):
        i = max(0, min(int(fi), self.last)) + self.base0
        return max(self.secs[i][:2])

    def _ring_point(self, i, a, grow):
        rx, ry, e, oy = self.secs[i]
        _, sd, nm = self.frames[i]
        return (self.centers[i] + sd * ((rx + grow) * _sgnpow(math.cos(a), 2.0 / e))
                + nm * (oy + (ry + grow) * _sgnpow(math.sin(a), 2.0 / e)))

    def point(self, fi, a, grow=0.0):
        """Ponto da superfície (coords de carro) no anel fracionário fi e ângulo a (0 = +side,
        pi/2 = +normal), afastado `grow` metros."""
        fi += self.base0
        i = max(0, min(int(fi), len(self.centers) - 2))
        f = max(0.0, min(1.0, fi - i))
        return self._ring_point(i, a, grow).lerp(self._ring_point(i + 1, a, grow), f)

    def mesh(self, cap0=True, cap1=True):
        rings = [[P(*self._ring_point(i, 2 * math.pi * k / self.n, 0.0)) for k in range(self.n)]
                 for i in range(len(self.centers))]
        return skin(rings, cap0, cap1)


def surface_strap(sweep, samples, width, th=0.006, gap=0.002):
    """Faixa (cinto) colada na superfície de um Sweep: samples = [(anel fracionário, ângulo)]."""
    rings = []
    for fi, a in samples:
        r = sweep.radius(fi)
        da = width * 0.5 / max(r, 0.02)
        rings.append([P(*sweep.point(fi, a - da, gap)), P(*sweep.point(fi, a + da, gap)),
                      P(*sweep.point(fi, a + da, gap + th)), P(*sweep.point(fi, a - da, gap + th))])
    return skin(rings)


def chain_weights(chain, power=6.0):
    """Pesos de pele pela distância aos ossos: chain = [(osso, cabeça, cauda)] em coords de carro.
    Cada vértice fica com os dois ossos mais próximos (mistura suave nas juntas)."""
    segs = [(name, Vector(h), Vector(t)) for name, h, t in chain]

    def fn(pos):
        p = Vector((pos.x, -pos.y, pos.z))
        raw = []
        for name, h, t in segs:
            d = t - h
            k = max(0.0, min(1.0, (p - h).dot(d) / d.length_squared))
            raw.append((1.0 / ((h + d * k - p).length ** power + 1e-9), name))
        raw.sort(reverse=True)
        top = raw[:2]
        total = sum(w for w, _ in top)
        return {name: w / total for w, name in top}
    return fn


# Proporções do piloto (≈1,75 m) sentado no cockpit: quadril no fundo do monocoque, tronco
# reclinado, joelhos logo abaixo do volante e pés nos pedais (dentro do bico).
DRIVER_UPPER_ARM = 0.285
DRIVER_LOWER_ARM = 0.26
DRIVER_SHOULDER = (0.175, -0.15, 0.495)
DRIVER_HIP = (0.085, -0.06, 0.17)
DRIVER_KNEE = (0.10, 0.40, 0.36)
DRIVER_ANKLE = (0.095, 0.82, 0.28)
DRIVER_FOOT_DIR = (0.0, 0.42, 0.91)
HELMET_CENTER = (0.0, -0.115, 0.715)
# Linhas de latitude do capacete (graus); a viseira vai de -8° a 22°, ±60° da frente.
HELMET_ROWS = (-78, -60, -42, -24, -8, 6, 22, 38, 54, 70, 84)
HELMET_LON = 18
VISOR_ROWS = (4, 6)
VISOR_HALF = math.radians(60)


def helmet_point(phi, th, grow=0.0):
    """Casca do capacete (coords de carro). phi = 0 na frente (+s), th = latitude.
    Abaixo do equador a frente desce e avança (queixeira) e a nuca desce até o HANS."""
    cx, cs, cz = HELMET_CENTER
    rx, rs = 0.123 + grow, 0.148 + grow
    rz = (0.135 if th > 0 else 0.13) + grow
    cf = math.cos(phi)
    # Metade de baixo mais "cheia" (casca desce quase reta até a borda, cobrindo o pescoço)
    ch = math.cos(th) ** (0.6 if th < 0 else 1.0)
    x = rx * math.sin(phi) * ch
    s = rs * cf * ch
    z = rz * math.sin(th)
    if th < 0:
        k = -math.sin(th)
        z -= 0.045 * k * max(cf, 0.0) ** 1.5
        s += 0.035 * k * max(cf, 0.0) ** 2
        z -= 0.03 * k * max(-cf, 0.0)
    return Vector((cx + x, cs + s, cz + z))


def _helmet_phi(i):
    return -math.pi + 2.0 * math.pi * i / HELMET_LON


def build_helmet(name):
    rows = [math.radians(t) for t in HELMET_ROWS]
    rings = [[P(*helmet_point(_helmet_phi(i), th)) for i in range(HELMET_LON)] for th in rows]
    shell = skin(rings)

    def paint(c):
        if c.tag == "cap0":
            return "Interior"
        if c.tag == "cap1":
            return "Livery_Accent"
        i = int(round(c.u * HELMET_LON - 0.5))
        k = int(round(c.v * (len(rows) - 1) - 0.5))
        phi = abs(_helmet_phi(i + 0.5))
        if VISOR_ROWS[0] <= k < VISOR_ROWS[1] and phi < VISOR_HALF:
            return "Visor"
        if k >= 9:
            return "Livery_Accent"  # coroa
        if k == 3 and phi < math.radians(140):
            return "Livery_Accent"  # faixa abaixo da viseira
        return "Helmet"

    hb = Builder(name)
    hb.add(shell, paint)
    # Viseira em relevo (casca fina sobre a abertura)
    vrows = [math.radians(HELMET_ROWS[k]) for k in range(VISOR_ROWS[0], VISOR_ROWS[1] + 1)]
    steps = 6
    vr = []
    for th in vrows:
        outer = [helmet_point(-VISOR_HALF + 2 * VISOR_HALF * j / steps, th, 0.006) for j in range(steps + 1)]
        inner = [helmet_point(-VISOR_HALF + 2 * VISOR_HALF * j / steps, th, -0.002) for j in range(steps, -1, -1)]
        vr.append([P(*p) for p in outer + inner])
    hb.add(skin(vr), lambda c: "Carbon" if c.tag in ("cap0", "cap1") else "Visor")
    # Aerofólio traseiro e tomada de ar no topo
    sp = helmet_point(math.pi, math.radians(40), 0.008)
    hb.add(box(sp.x, sp.y - 0.01, sp.z + 0.008, 0.058, 0.02, 0.004), "Carbon")
    for sx in (-1, 1):
        fin = helmet_point(math.pi - sx * 0.36, math.radians(36), -0.004)
        hb.add(box(fin.x, fin.y - 0.006, fin.z + 0.004, 0.003, 0.02, 0.012), "Carbon")
    return hb


def add_boot(b, ankle, knee, fd, weights):
    """Bota de corrida no pedal: cano subindo pela canela, corpo do pé com salto e biqueira de
    carbono, tira de velcro e sola. O pé aponta para cima (fd) e a sola olha para os pedais."""
    shin = (ankle - knee).normalized()
    # Cano (aberto em cima, por onde passa a perna) e a borda acolchoada
    b.add(Sweep([ankle - shin * 0.12, ankle - shin * 0.06, ankle],
                [(0.047, 0.045, 2.2), (0.05, 0.048, 2.2), (0.053, 0.051, 2.2)], n=12,
                round1=0.5).mesh(cap0=False), "Livery_Accent", weights=weights)
    b.add(Sweep([ankle - shin * 0.128, ankle - shin * 0.108], [(0.052, 0.05, 2.2), (0.053, 0.051, 2.2)],
                n=12, sub=1).mesh(), "Livery_Secondary", weights=weights)
    # Corpo do pé ao longo de fd: (t ao longo do pé, meia-largura, meia-altura, centro em direção à sola)
    st = [(-0.07, 0.036, 0.04, 0.03), (-0.045, 0.043, 0.054, 0.018), (0.0, 0.047, 0.062, 0.012),
          (0.06, 0.05, 0.052, 0.02), (0.12, 0.052, 0.046, 0.026), (0.165, 0.048, 0.041, 0.03),
          (0.2, 0.04, 0.033, 0.036)]

    def foot_paint(c):
        t = (Vector((c.x, c.s, c.z)) - ankle).dot(fd)
        return "Livery_Secondary" if t > 0.16 or t < -0.065 else "Livery_Accent"

    b.add(Sweep([ankle + fd * t for t, *_ in st], [(hw, hn, 2.5, cn) for _, hw, hn, cn in st], n=12,
                round0=0.6, round1=0.8).mesh(), foot_paint, weights=weights)
    # Tira de velcro no peito do pé
    b.add(Sweep([ankle + fd * 0.03, ankle + fd * 0.056],
                [(0.052, 0.06, 2.5, 0.017), (0.053, 0.056, 2.5, 0.02)], n=12, sub=1).mesh(),
          "Livery_Secondary", weights=weights)
    # Sola fina de borracha (mais grossa no salto), colada na face do pé que pisa no pedal
    sole = [(t, hw * 0.92, 0.009 if t < -0.03 else 0.005, cn + hn - 0.001) for t, hw, hn, cn in st]
    b.add(Sweep([ankle + fd * t for t, *_ in sole], [(hw, hn, 3.0, c) for _, hw, hn, c in sole], n=12,
                round0=0.3, round1=0.5).mesh(), "Carbon", weights=weights)


def build_driver(col):
    """Piloto humanoide (macacão, luvas, botas, HANS, cintos e capacete) sentado no cockpit, com o
    esqueleto do SkeletonProfileHumanoid do Godot (nomes de ossos padrão).

    * DriverBody: malha com pesos de pele (juntas com calotas arredondadas e pesos divididos).
    * DriverHelmet: preso ao osso Head; a câmera de 1ª pessoa o esconde.
    * DriverRig: armature. Na pose de repouso as mãos já seguram as manoplas; no Godot um
      TwoBoneIK3D mantém as mãos no volante enquanto ele gira (o modelo pode ser trocado
      por qualquer personagem com os mesmos nomes de ossos).
    """
    spine = [("Hips", (0, -0.10, 0.20), (0, -0.12, 0.30)),
             ("Spine", (0, -0.12, 0.30), (0, -0.15, 0.40)),
             ("Chest", (0, -0.15, 0.40), (0, -0.19, 0.52)),
             ("Neck", (0, -0.19, 0.52), (0, -0.155, 0.615)),
             ("Head", (0, -0.155, 0.615), (0, -0.11, 0.80))]
    bones = {}
    parent = None
    for name, h, t in spine:
        bones[name] = (h, t, parent)
        parent = name
    bone_pos = {name: (h, t) for name, h, t in spine}
    arms, legs = {}, {}
    fd = Vector(DRIVER_FOOT_DIR).normalized()
    for side, prefix in ((1, "Left"), (-1, "Right")):
        sh = (side * DRIVER_SHOULDER[0], DRIVER_SHOULDER[1], DRIVER_SHOULDER[2])
        hint = P(side * 0.2, 0.0, -1.0)
        shoulder = P(*sh)
        grip = grip_point(side)
        reach = (grip - shoulder).normalized()
        hand_dir = (reach + Vector((0.0, 0.0, 0.25))).normalized()
        wrist = grip - hand_dir * HAND_PALM_OFFSET
        to_wrist = wrist - shoulder
        dist = min(to_wrist.length, DRIVER_UPPER_ARM + DRIVER_LOWER_ARM - 0.01)
        axis = to_wrist.normalized()
        a = (DRIVER_UPPER_ARM ** 2 - DRIVER_LOWER_ARM ** 2 + dist ** 2) / (2 * dist)
        h = math.sqrt(max(DRIVER_UPPER_ARM ** 2 - a * a, 0.0))
        pole = (hint - axis * hint.dot(axis)).normalized()
        elbow = shoulder + axis * a + pole * h
        knuckles = wrist + hand_dir * 0.09
        arms[prefix] = (shoulder, elbow, wrist, knuckles, pole, hand_dir)
        bones[prefix + "Shoulder"] = ((side * 0.04, -0.17, 0.50), sh, "Chest")
        bones[prefix + "UpperArm"] = (sh, car_xyz(elbow), prefix + "Shoulder")
        bones[prefix + "LowerArm"] = (car_xyz(elbow), car_xyz(wrist), prefix + "UpperArm")
        bones[prefix + "Hand"] = (car_xyz(wrist), car_xyz(knuckles), prefix + "LowerArm")

        hip = Vector((side * DRIVER_HIP[0], DRIVER_HIP[1], DRIVER_HIP[2]))
        knee = Vector((side * DRIVER_KNEE[0], DRIVER_KNEE[1], DRIVER_KNEE[2]))
        ankle = Vector((side * DRIVER_ANKLE[0], DRIVER_ANKLE[1], DRIVER_ANKLE[2]))
        toe = ankle + fd * 0.15
        legs[prefix] = (hip, knee, ankle, toe)
        bones[prefix + "UpperLeg"] = (tuple(hip), tuple(knee), "Hips")
        bones[prefix + "LowerLeg"] = (tuple(knee), tuple(ankle), prefix + "UpperLeg")
        bones[prefix + "Foot"] = (tuple(ankle), tuple(toe), prefix + "LowerLeg")

    # --- Armature
    arm_data = bpy.data.armatures.new("DriverRig")
    rig = bpy.data.objects.new("DriverRig", arm_data)
    col.objects.link(rig)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (head, tail, parent) in bones.items():
        eb = arm_data.edit_bones.new(name)
        eb.head = P(*head)
        eb.tail = P(*tail)
        if parent:
            eb.parent = arm_data.edit_bones[parent]
            eb.use_connect = (eb.parent.tail - eb.head).length < 1e-4
    for prefix in ("Left", "Right"):
        for part in ("UpperArm", "LowerArm", "Hand"):
            arm_data.edit_bones[prefix + part].align_roll(arms[prefix][4])
        for part in ("UpperLeg", "LowerLeg", "Foot"):
            arm_data.edit_bones[prefix + part].align_roll(Vector((0.0, 0.0, 1.0)))
    bpy.ops.object.mode_set(mode="OBJECT")

    def chain(*names):
        return chain_weights([(n, bones[n][0], bones[n][1]) for n in names])

    b = Builder("DriverBody")
    # --- Tronco (macacão com painéis laterais); base arredondada
    torso = Sweep([(0, -0.075, 0.115), (0, -0.10, 0.21), (0, -0.13, 0.33), (0, -0.16, 0.43),
                   (0, -0.185, 0.505), (0, -0.195, 0.548)],
                  [(0.13, 0.085, 2.6), (0.17, 0.11, 2.8), (0.152, 0.10, 2.6, 0.005),
                   (0.18, 0.115, 2.8, 0.01), (0.195, 0.105, 3.0), (0.115, 0.075, 2.4)], n=16, round0=0.6)
    b.add(torso.mesh(), lambda c: "Livery_Secondary" if abs(c.nx) > 0.85 and c.z > 0.22 else "Suit",
          weights=chain("Hips", "Spine", "Chest"))
    top = torso.last
    # Gola, pescoço (balaclava) e HANS
    b.add(Sweep([(0, -0.197, 0.538), (0, -0.182, 0.595)], [(0.074, 0.068, 2.2), (0.064, 0.058, 2.2)],
                n=16, sub=1).mesh(), "Livery_Accent", weights=chain("Chest", "Neck"))
    b.add(Sweep([(0, -0.19, 0.55), (0, -0.165, 0.61), (0, -0.145, 0.655)],
                [(0.05, 0.05, 2.0), (0.046, 0.046, 2.0), (0.044, 0.044, 2.0)], n=12).mesh(),
          "Interior", weights=chain("Neck", "Head"))
    # (ângulos contínuos: o lado direito é o espelho -pi - a do esquerdo)
    hans_angles = [(top - 2.2, 1.12), (top - 1.2, 1.06), (top - 0.35, 0.9), (top - 0.2, 0.0),
                   (top - 0.2, -math.pi / 2), (top - 0.2, -math.pi), (top - 0.35, -math.pi - 0.9),
                   (top - 1.2, -math.pi - 1.06), (top - 2.2, -math.pi - 1.12)]
    hans_path = [tuple(torso.point(fi, a, 0.012)) for fi, a in hans_angles]
    b.add(Sweep(hans_path, [(0.010, 0.03, 2.4)] * len(hans_path), side=(0, 0, 1), sub=3, n=10,
                round0=0.4, round1=0.4).mesh(), "Carbon", weights=chain("Chest", "Neck"))
    pad = torso.point(top - 0.5, -math.pi / 2, 0.02)
    b.add(box(pad.x, pad.y - 0.004, pad.z + 0.03, 0.055, 0.016, 0.035), "Carbon", weights=chain("Chest", "Neck"))
    # Cintos de 6 pontos (ombros e abdominal) com fivela central
    belt_w = 0.05
    a_top, a_low = math.pi / 2 - 0.55, math.pi / 2 - 0.12
    for sx in (1, -1):
        def m(a, sx=sx):
            return a if sx > 0 else math.pi - a
        # Das costas, por cima do ombro, até a fivela na barriga
        samples = [(top - 1.6, m(-a_top)), (top - 0.6, m(-a_top)), (top, m(-0.6)), (top, m(0.6)),
                   (top - 0.6, m(a_top))]
        for k in range(1, 8):
            samples.append((top - 0.6 - k * (top - 4.9) / 7, m(a_top + (a_low - a_top) * k / 7)))
        b.add(surface_strap(torso, samples, belt_w), "Interior", weights=chain("Hips", "Spine", "Chest"))
        # (nasce na lateral do quadril, escondida pela coxa, e vem até a fivela)
        lap = [(2.3 + 1.65 * k / 8, m(0.05 + 1.42 * k / 8)) for k in range(9)]
        b.add(surface_strap(torso, lap, belt_w), "Interior", weights=chain("Hips", "Spine"))
    buckle = torso.point(4.1, math.pi / 2, 0.012)
    b.add(box(buckle.x, buckle.y, buckle.z, 0.04, 0.012, 0.04), "Metal", weights=chain("Hips", "Spine"))

    for side, prefix in ((1, "Left"), (-1, "Right")):
        shoulder, elbow, wrist, knuckles, pole, hand_dir = arms[prefix]
        g = steering_matrix().to_3x3() @ Vector((0.0, 0.0, 1.0))
        g_car = Vector(car_xyz(g)).normalized()
        hd = Vector(car_xyz(hand_dir))
        sh, el, wr = Vector(car_xyz(shoulder)), Vector(car_xyz(elbow)), Vector(car_xyz(wrist))
        # Braço (manga com faixa na lateral externa). A calota do início vira o deltoide, que
        # entra no tronco e acompanha o ombro (pesos divididos com o osso Shoulder).
        arm = Sweep([sh, sh.lerp(el, 0.5), el, el.lerp(wr, 0.5), wr - hd * 0.03],
                    [(0.058, 0.054, 2.2), (0.048, 0.046, 2.2), (0.042, 0.041, 2.2), (0.039, 0.036, 2.2),
                     (0.033, 0.031, 2.2)], side=tuple(car_xyz(pole)), sub=3, n=12, round0=1.0)
        b.add(arm.mesh(), lambda c, side=side: "Livery_Secondary" if c.nx * side > 0.8 else "Suit",
              weights=chain(prefix + "Shoulder", prefix + "UpperArm", prefix + "LowerArm"))
        # Luva: punho largo sobre a manga + mão fechada na manopla + polegar
        b.add(Sweep([wr - hd * 0.06, wr - hd * 0.02, wr + hd * 0.012],
                    [(0.042, 0.039, 2.4), (0.046, 0.042, 2.4), (0.04, 0.036, 2.4)],
                    side=tuple(g_car), n=12, sub=2).mesh(), "Livery_Accent", weights=chain(prefix + "Hand"))
        b.add(Sweep([wr, wr + hd * 0.035, wr + hd * 0.075, wr + hd * 0.1],
                    [(0.032, 0.025, 2.4), (0.042, 0.03, 2.6), (0.043, 0.032, 2.6), (0.035, 0.027, 2.4)],
                    side=tuple(g_car), n=12, round1=0.6).mesh(),
              "Livery_Accent", weights=chain(prefix + "Hand"))
        b.add(Sweep([wr + hd * 0.025 + g_car * 0.034, wr + hd * 0.08 + g_car * 0.05],
                    [(0.015, 0.014, 2.0), (0.013, 0.012, 2.0)], side=tuple(hd), n=8, sub=2, round1=0.8).mesh(),
              "Livery_Accent", weights=chain(prefix + "Hand"))
        # Perna: a calota do início forma o glúteo, encaixado na base do tronco
        hip, knee, ankle, toe = legs[prefix]
        leg = Sweep([hip, hip.lerp(knee, 0.5), knee, knee.lerp(ankle, 0.5), ankle],
                    [(0.09, 0.087, 2.3), (0.076, 0.071, 2.3), (0.061, 0.058, 2.2), (0.05, 0.046, 2.2),
                     (0.041, 0.039, 2.2)], sub=3, n=12, round0=1.0)
        b.add(leg.mesh(), lambda c, side=side: "Livery_Secondary" if c.nx * side > 0.8 else "Suit",
              weights=chain("Hips", prefix + "UpperLeg", prefix + "LowerLeg"))
        add_boot(b, ankle, knee, fd, chain(prefix + "LowerLeg", prefix + "Foot"))
    body = b.build(col, smooth_angle=60.0)
    body.parent = rig
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = rig

    # --- Capacete preso ao osso Head
    helmet = build_helmet("DriverHelmet").build(col, smooth_angle=50.0)
    head = arm_data.bones["Head"]
    helmet.parent = rig
    helmet.parent_type = "BONE"
    helmet.parent_bone = "Head"
    helmet.matrix_parent_inverse = (rig.matrix_world @ head.matrix_local
                                    @ Matrix.Translation((0, head.length, 0))).inverted()
    return [rig, body, helmet]


# --- Rodas ---------------------------------------------------------------------
def tyre_profile(w, rr=0.05):
    hw = w / 2
    R, rb = WHEEL_RADIUS, BEAD_RADIUS

    def side_a(t):
        return hw - 0.012 * (1 - t) + 0.010 * math.sin(math.pi * t)

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


def build_tyre(col, axle):
    w = FRONT_TYRE_WIDTH if axle == "front" else REAR_TYRE_WIDTH
    hw = w / 2
    b = Builder("Tyre_slick_" + axle)
    b.add(lathe(tyre_profile(w), segments=56), "Tire")
    # Faixa colorida do composto (com falhas, para a rotação ficar visível)
    stripe = [(hw + 0.002, 0.283), (hw + 0.0065, 0.283), (hw + 0.0065, 0.299), (hw + 0.002, 0.299)]
    for a0 in (math.radians(12), math.radians(192)):
        b.add(lathe(stripe, segments=24, a0=a0, a1=a0 + math.radians(150)), "Tire_Stripe")
    return [b.build(col)]


def rim_common(b, hw):
    barrel = [(-hw + 0.02, 0.214), (hw - 0.035, 0.214), (hw - 0.035, 0.200), (hw - 0.012, 0.200),
              (hw - 0.008, 0.236), (-hw + 0.02, 0.236)]
    b.add(lathe(barrel, segments=48), "Rim")
    drum = [(-hw + 0.02, 0.17), (hw - 0.05, 0.17), (hw - 0.05, 0.19), (-hw + 0.02, 0.19)]
    b.add(lathe(drum, segments=32), "Carbon")
    inner = [(-hw + 0.025, 0.002), (-hw + 0.025, 0.21), (-hw + 0.035, 0.21), (-hw + 0.035, 0.002)]
    b.add(lathe(inner, segments=32), "Carbon")


def build_rim(col, variant, axle):
    w = FRONT_TYRE_WIDTH if axle == "front" else REAR_TYRE_WIDTH
    hw = w / 2
    b = Builder("Rim_%s_%s" % (variant, axle))
    rim_common(b, hw)
    if variant == "spoked":
        for i in range(10):
            th = 2 * math.pi * i / 10
            b.add(radial_box(th, 0.055, 0.208, hw - 0.06, hw - 0.04, 0.030, 0.018),
                  "Livery_Accent" if i % 2 == 0 else "Rim")
        b.add(lathe([(hw - 0.07, 0.03), (hw - 0.02, 0.03), (hw - 0.02, 0.062), (hw - 0.07, 0.062)],
                    segments=24), "Rim")
        b.add(lathe([(hw - 0.13, 0.07), (hw - 0.10, 0.07), (hw - 0.10, 0.17), (hw - 0.13, 0.17)],
                    segments=32), "Carbon")
    else:
        b.add(lathe([(hw - 0.040, 0.002), (hw - 0.030, 0.002), (hw - 0.030, 0.205), (hw - 0.040, 0.205)],
                    segments=48), "Rim")
        ring_prof = [(hw - 0.031, 0.13), (hw - 0.026, 0.13), (hw - 0.026, 0.165), (hw - 0.031, 0.165)]
        for k in range(3):
            a0 = 2 * math.pi * k / 3
            b.add(lathe(ring_prof, segments=12, a0=a0, a1=a0 + math.radians(80)), "Livery_Accent")
        for k in range(3):
            th = 2 * math.pi * k / 3 + math.radians(100)
            b.add(radial_box(th, 0.075, 0.115, hw - 0.031, hw - 0.027, 0.025, 0.035), "Carbon")
    # Porca central
    b.add(lathe([(hw - 0.035, 0.002), (hw + 0.008, 0.002), (hw + 0.008, 0.042), (hw - 0.035, 0.042)],
                segments=6), "Metal")
    return [b.build(col)]


# ---------------------------------------------------------------------------
# Montagem / exportação
# ---------------------------------------------------------------------------
PART_BUILDERS = {
    # slot: {variante: função}
    "chassis": {"standard": build_chassis},
    "nose": {"standard": lambda c: build_nose(c, "standard"), "pointed": lambda c: build_nose(c, "pointed")},
    "front_wing": {"standard": lambda c: build_front_wing(c, "standard"),
                   "lowdf": lambda c: build_front_wing(c, "lowdf")},
    "rear_wing": {"standard": lambda c: build_rear_wing(c, "standard"),
                  "lowdf": lambda c: build_rear_wing(c, "lowdf"),
                  "highdf": lambda c: build_rear_wing(c, "highdf")},
    "sidepods": {"downwash": lambda c: build_sidepods(c, "downwash"), "slim": lambda c: build_sidepods(c, "slim")},
    "engine_cover": {"standard": lambda c: build_engine_cover(c, "standard"),
                     "sharkfin": lambda c: build_engine_cover(c, "sharkfin")},
    "floor": {"standard": build_floor},
    "halo": {"standard": build_halo},
    "mirrors": {"standard": build_mirrors},
    "suspension_front": {"standard": build_suspension_front},
    "suspension_rear": {"standard": build_suspension_rear},
    "cockpit": {"standard": build_cockpit},
    "driver": {"standard": build_driver},
}
WHEEL_BUILDERS = {
    "tyre": {"slick": lambda c, axle: build_tyre(c, axle)},
    "rim": {"covered": lambda c, axle: build_rim(c, "covered", axle),
            "spoked": lambda c, axle: build_rim(c, "spoked", axle)},
}
DEFAULT_VARIANTS = {"nose": "standard", "front_wing": "standard", "rear_wing": "standard",
                    "sidepods": "downwash", "engine_cover": "standard", "tyre": "slick", "rim": "covered"}


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_collection(name, parent=None):
    col = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(col)
    return col


def export_glb(objs, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_cameras=False, export_lights=False)
    print("  exportado:", os.path.relpath(path, ROOT))


def mesh_stats(objs):
    tris = 0
    for o in objs:
        if o.type != "MESH":
            continue
        for p in o.data.polygons:
            tris += len(p.vertices) - 2
    return tris


def main():
    reset_scene()
    root = new_collection("F1Car")
    built = {}  # (slot, variante, eixo) -> objetos
    total_tris = {}

    for slot, variants in PART_BUILDERS.items():
        slot_col = new_collection(slot, root)
        for variant, fn in variants.items():
            col = new_collection("%s.%s" % (slot, variant), slot_col)
            objs = fn(col)
            built[(slot, variant, None)] = objs
            if not ONLY or slot in ONLY:
                export_glb(objs, os.path.join(PARTS_DIR, slot, variant + ".glb"))
            total_tris["%s/%s" % (slot, variant)] = mesh_stats(objs)

    for slot, variants in WHEEL_BUILDERS.items():
        slot_col = new_collection(slot, root)
        for variant, fn in variants.items():
            for axle in ("front", "rear"):
                col = new_collection("%s.%s.%s" % (slot, variant, axle), slot_col)
                objs = fn(col, axle)
                built[(slot, variant, axle)] = objs
                if not ONLY or slot in ONLY:
                    export_glb(objs, os.path.join(PARTS_DIR, slot, "%s_%s.glb" % (variant, axle)))
                total_tris["%s/%s_%s" % (slot, variant, axle)] = mesh_stats(objs)

    # Visibilidade: só as variantes padrão ficam visíveis no .blend
    def hide_layer(layer_col):
        for child in layer_col.children:
            parts = child.name.split(".")
            if len(parts) >= 2:
                slot, variant = parts[0], parts[1]
                default = DEFAULT_VARIANTS.get(slot)
                child.hide_viewport = default is not None and variant != default
                child.collection.hide_render = child.hide_viewport
            hide_layer(child)

    hide_layer(bpy.context.view_layer.layer_collection)

    # Rodas montadas nas 4 posições (instâncias da mesma malha)
    wheels_col = new_collection("WheelAssembly", root)
    for axle, s, half_track in (("front", FRONT_AXLE_S, FRONT_HALF_TRACK), ("rear", REAR_AXLE_S, REAR_HALF_TRACK)):
        sources = built[("tyre", "slick", axle)] + built[("rim", "covered", axle)]
        for side in (1, -1):
            for src in sources:
                inst = bpy.data.objects.new("%s_%s" % (src.name, "L" if side > 0 else "R"), src.data)
                inst.location = P(side * half_track, s, WHEEL_RADIUS)
                if side < 0:
                    inst.rotation_euler = (0, 0, math.pi)
                wheels_col.objects.link(inst)
    for slot in ("tyre", "rim"):
        bpy.context.view_layer.layer_collection.children["F1Car"].children[slot].hide_viewport = True
        bpy.data.collections[slot].hide_render = True

    print("\nTriângulos por peça:")
    for k, v in total_tris.items():
        print("  %-28s %6d" % (k, v))

    if DO_RENDER:
        render_previews()

    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("salvo:", BLEND_PATH)


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

    # Chão para referência
    ground_mesh = bpy.data.meshes.new("Ground")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=12)
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

    views = {
        "front34": ((4.6, -6.2, 2.3), (0, -0.2, 0.35), 40),
        "side": ((8.5, 0.0, 0.9), (0, 0.0, 0.45), 40),
        "rear34": ((-4.4, 6.0, 2.6), (0, 0.4, 0.4), 40),
        "top": ((0.0, 0.01, 12.5), (0, 0.0, 0.0), 45),
        "front": ((0.0, -8.0, 0.9), (0, 0.0, 0.45), 30),
        "cockpit": ((1.6, -1.2, 2.0), (0, 0.1, 0.6), 35),
        "wheel": ((2.2, -2.6, 0.6), (FRONT_HALF_TRACK, -FRONT_AXLE_S, 0.36), 30),
    }
    for name, (loc, target, lens_deg) in views.items():
        cam.location = Vector(loc)
        direction = Vector(target) - Vector(loc)
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        cam_data.angle = math.radians(lens_deg)
        scene.render.filepath = os.path.join(RENDER_DIR, name + ".png")
        bpy.ops.render.render(write_still=True)
        print("  render:", scene.render.filepath)

    bpy.data.objects.remove(ground)
    bpy.data.objects.remove(cam)


XRAY_PARTS = ("Chassis", "Nose", "SteeringWheel", "Headrest", "Halo")


def driver_preview(out_dir):
    """Prévia do piloto (não altera os assets): monta o carro padrão com o piloto, exporta o piloto
    em <out_dir>/driver_preview.glb e renderiza vistas (sozinho, no carro e em raio-x). O .glb pode
    ser visto no jogo, sem trocar a peça, com tests/capture_driver.gd."""
    reset_scene()
    root = new_collection("F1Car")
    car_col = new_collection("car", root)
    for slot, variants in PART_BUILDERS.items():
        if slot != "driver":
            variants[DEFAULT_VARIANTS.get(slot, "standard")](car_col)
    for axle, s, half_track in (("front", FRONT_AXLE_S, FRONT_HALF_TRACK), ("rear", REAR_AXLE_S, REAR_HALF_TRACK)):
        for side in (1, -1):
            for obj in build_tyre(car_col, axle) + build_rim(car_col, "covered", axle):
                obj.location = P(side * half_track, s, WHEEL_RADIUS)
                if side < 0:
                    obj.rotation_euler = (0, 0, math.pi)
    new_col = new_collection("driver", root)
    new_objs = build_driver(new_col)
    os.makedirs(out_dir, exist_ok=True)
    export_glb(new_objs, os.path.join(out_dir, "driver_preview.glb"))
    print("triângulos do piloto:", mesh_stats(new_objs))

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
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=12)
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

    cols = {"car": car_col, "new": new_col}
    views = [
        # nome, câmera, alvo, ângulo, coleções visíveis, raio-x
        ("piloto_frente34", (1.7, -1.9, 1.2), (0, -0.3, 0.42), 38, ("new",), False),
        ("piloto_lado", (3.2, -0.38, 0.5), (0, -0.38, 0.45), 32, ("new",), False),
        ("piloto_tras34", (-1.4, 1.5, 1.3), (0, -0.2, 0.42), 38, ("new",), False),
        ("piloto_capacete", (0.62, -0.75, 0.9), (0, 0.1, 0.66), 30, ("new",), False),
        ("piloto_bota", (0.55, -1.5, 0.7), (0.0, -0.9, 0.36), 26, ("new",), False),
        ("piloto_bota_lado", (0.75, -0.95, 0.42), (0.1, -0.92, 0.36), 32, ("new",), False),
        ("piloto_juntas", (0.85, -0.45, 0.8), (0.1, 0.05, 0.42), 34, ("new",), False),
        ("carro_cockpit34", (1.6, -1.2, 2.0), (0, 0.1, 0.6), 35, ("car", "new"), False),
        ("carro_lado_raiox", (3.2, -0.45, 0.5), (0, -0.45, 0.45), 32, ("car", "new"), True),
        ("carro_frente", (0.0, -3.6, 1.25), (0, 0.0, 0.62), 22, ("car", "new"), False),
        ("carro_tras34", (-1.5, 2.1, 1.55), (0, 0.0, 0.6), 35, ("car", "new"), False),
        ("carro_topo", (0.0, 0.1, 3.2), (0, 0.1, 0.4), 30, ("car", "new"), False),
    ]
    for name, loc, target, lens_deg, visible, xray in views:
        for key, c in cols.items():
            c.hide_render = key not in visible
        for obj in car_col.objects:
            # No raio-x só a estrutura do cockpit (monocoque, bico, volante, halo)
            obj.hide_render = xray and not obj.name.startswith(XRAY_PARTS)
        sh.show_xray = xray
        sh.xray_alpha = 0.3
        cam.location = Vector(loc)
        cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        cam_data.angle = math.radians(lens_deg)
        scene.render.filepath = os.path.join(out_dir, name + ".png")
        bpy.ops.render.render(write_still=True)
        print("  render:", scene.render.filepath)


if __name__ == "__main__":
    if "--driver-preview" in ARGS:
        driver_preview(ARGS[ARGS.index("--driver-preview") + 1])
    else:
        main()
