"""Bichos da Atlantis Abyss (polvo, baleia, raia-manta, tubarão, golfinho, tartaruga), em unidades
da peça: frente para -Y, z para cima, centrados na origem (caixa envolvente) com 1 de comprimento em
y (a raia: 1 de envergadura em x). O polvo é a exceção: fica em volta da coluna (x = y = 0), com o
topo dela em z = 0,16 (veja octopus).

Modelagem por seções, já na resolução final (sem Decimate): o corpo é um tubo de anéis ao longo de y
(cada anel uma superelipse, com costuras onde a cor muda de repente e sulcos), as nadadeiras são
perfis de asa (NACA) entre o bordo de ataque e o de fuga, a carapaça da tartaruga é um grafo plano
de placas erguido sobre um domo, os braços do polvo são tubos por curvas, e olhos, tubérculos, cracas
e fendas são peças pequenas encaixadas. Cada peça é fechada (sem buracos, normais para fora); as
peças se cruzam, sem solda.

Cor de vértice (atributo "Color", por ponto, RGBA) para o shader (sea_creature.gdshader):
  R = peso do nado: 0 no corpo rígido, subindo suave até 1 no que mexe. Quase sempre uma função
      contínua da posição, para as peças que se cruzam mexerem juntas:
        tubarão (modo 0) e baleia e golfinho (modo 1): do meio do corpo até a cauda, mais um pouco
        nas peitorais da baleia e do golfinho; raia (modo 2): de |x| = 0,06 até as pontas das asas;
        tartaruga (modo 3): ao longo de cada nadadeira (1 na ponta das da frente, 0,65 nas de trás);
        polvo (modo 4): só nos cinco braços soltos, da metade até a ponta (os enrolados na coluna e
        o corpo ficam parados).
  G = ventre: 0 = cor do dorso, 1 = cor do ventre (a linha do contra-sombreamento de cada bicho).
  B = escurecimento, cor × (1 − 0,85·B): olhos, fendas das guelras, boca, sulcos da garganta, bordas
      das placas do casco, pontas pretas das nadadeiras, mais um pouco de oclusão nas reentrâncias.
  A = destaque (a terceira cor do bicho): manchas dos ombros da raia, casco da tartaruga, ventosas do
      polvo, capote do golfinho, nadadeiras claras e cracas da baleia, faixa clara do tubarão.
A cor final pensada: mix(mix(dorso, ventre, G), destaque, A) × (1 − 0,85·B).
"""
import bisect
import math

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

TAU = math.pi * 2.0


def smooth(e0, e1, x):
    """smoothstep: 0 até e0, 1 a partir de e1, curva suave no meio."""
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------------------
# Contas e curvas
# ---------------------------------------------------------------------------
def clamp(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))


def mix(a, b, t):
    return a + (b - a) * t


def ramp(e0, e1, x):
    """Rampa linear: 0 em e0, 1 em e1."""
    return clamp((x - e0) / (e1 - e0))


def window(x, a, b, soft):
    """1 entre a e b, caindo suave em `soft` de cada lado."""
    return smooth(a - soft, a, x) * (1.0 - smooth(b, b + soft, x))


def hash01(*k):
    """Ruído fixo de 0 a 1 a partir de números (para espalhar cracas e manchas)."""
    h = math.sin(sum(v * c for v, c in zip(k, (12.9898, 78.233, 37.719, 4.581)))) * 43758.5453
    return h - math.floor(h)


def noise3(p, freq):
    """Ruído de valor 3D suave, de 0 a 1 (manchas da pele)."""
    x, y, z = p.x * freq, p.y * freq, p.z * freq
    ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = x - ix, y - iy, z - iz
    fx, fy, fz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (fx if dx else 1 - fx) * (fy if dy else 1 - fy) * (fz if dz else 1 - fz)
                out += w * hash01(ix + dx, iy + dy, iz + dz, 5.0)
    return out


def sgnpow(v, e):
    return math.copysign(abs(v) ** e, v)


class Curve:
    """Interpolação suave e monótona (PCHIP) pelos pontos [(x, y), ...]: não ondula entre eles."""

    def __init__(self, pts):
        self.x = [float(p[0]) for p in pts]
        self.y = [float(p[1]) for p in pts]
        n = len(pts)
        h = [self.x[i + 1] - self.x[i] for i in range(n - 1)]
        d = [(self.y[i + 1] - self.y[i]) / h[i] for i in range(n - 1)]
        m = [d[0]] + [0.0] * (n - 2) + [d[-1]]
        for i in range(1, n - 1):
            if d[i - 1] * d[i] > 0.0:
                w1, w2 = 2.0 * h[i] + h[i - 1], h[i] + 2.0 * h[i - 1]
                m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
        self.h, self.m = h, m

    def __call__(self, x):
        xs = self.x
        if x <= xs[0]:
            return self.y[0]
        if x >= xs[-1]:
            return self.y[-1]
        i = bisect.bisect_right(xs, x) - 1
        h = self.h[i]
        t = (x - xs[i]) / h
        t2, t3 = t * t, t * t * t
        return ((2 * t3 - 3 * t2 + 1) * self.y[i] + (t3 - 2 * t2 + t) * h * self.m[i]
                + (-2 * t3 + 3 * t2) * self.y[i + 1] + (t3 - t2) * h * self.m[i + 1])


class Path:
    """Curva no espaço por pontos com parâmetro, [(s, (x, y, z)), ...]: cada coordenada uma Curve."""

    def __init__(self, pts):
        self.c = [Curve([(s, p[k]) for s, p in pts]) for k in range(3)]

    def __call__(self, s):
        return Vector((self.c[0](s), self.c[1](s), self.c[2](s)))


def catmull(ctrl, per=12):
    """Curva suave (Catmull-Rom centrípeta) pelos pontos de controle, bem amostrada."""
    P = [Vector(p) for p in ctrl]
    P = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        t0 = 0.0
        t1 = t0 + max((p1 - p0).length ** 0.5, 1e-6)
        t2 = t1 + max((p2 - p1).length ** 0.5, 1e-6)
        t3 = t2 + max((p3 - p2).length ** 0.5, 1e-6)
        for k in range(per):
            t = t1 + (t2 - t1) * k / per
            a1 = p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
            a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
            a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
            b1 = a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
            b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
            out.append(b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1)))
    out.append(P[-2].copy())
    return out


def resample(pts, step):
    """Reamostra a poligonal pelo comprimento: passo step(s) (s = comprimento desde o começo).
    Devolve os pontos e o comprimento de cada um."""
    cum = [0.0]
    for a, b in zip(pts, pts[1:]):
        cum.append(cum[-1] + (b - a).length)
    total = cum[-1]
    out, ss = [pts[0].copy()], [0.0]
    s, k = 0.0, 0
    while True:
        s += step(s)
        if s >= total - step(s) * 0.4:
            break
        while cum[k + 1] < s:
            k += 1
        t = (s - cum[k]) / max(cum[k + 1] - cum[k], 1e-12)
        out.append(pts[k].lerp(pts[k + 1], t))
        ss.append(s)
    out.append(pts[-1].copy())
    ss.append(total)
    return out, ss


# ---------------------------------------------------------------------------
# Peças: vértices, faces, parâmetros por vértice (para pintar) e arestas vivas
# ---------------------------------------------------------------------------
class Part:
    def __init__(self, name, paint):
        self.name = name
        self.paint = paint      # (co, prm) -> (r ou None, g, b, a); r None = peso do nado do bicho
        self.co = []
        self.prm = []
        self.faces = []
        self.sharp = []

    def vert(self, co, prm=None):
        self.co.append(Vector(co))
        self.prm.append(prm or {})
        return len(self.co) - 1

    def ring(self, pts):
        """Pontos [(co, prm), ...] viram vértices; devolve os índices."""
        return [self.vert(co, prm) for co, prm in pts]

    def connect(self, rings, closed=True):
        """Liga anéis consecutivos (listas de índices) com quads; um anel de um índice só é um polo."""
        for r0, r1 in zip(rings, rings[1:]):
            n = max(len(r0), len(r1))
            span = n if closed else n - 1
            if len(r0) == 1:
                for j in range(span):
                    self.faces.append((r0[0], r1[(j + 1) % n], r1[j]))
            elif len(r1) == 1:
                for j in range(span):
                    self.faces.append((r1[0], r0[j], r0[(j + 1) % n]))
            else:
                for j in range(span):
                    k = (j + 1) % n
                    self.faces.append((r0[j], r0[k], r1[k], r1[j]))

    def fan(self, ring, prm=None, first=True):
        """Fecha um anel com um leque até o centro (tampa escondida dentro de outra peça)."""
        c = sum((self.co[i] for i in ring), Vector()) / len(ring)
        self.connect([[self.vert(c, prm)], ring] if first else [ring, [self.vert(c, prm)]])

    def volume(self):
        v = 0.0
        for f in self.faces:
            a = self.co[f[0]]
            for k in range(1, len(f) - 1):
                v += a.dot(self.co[f[k]].cross(self.co[f[k + 1]]))
        return v / 6.0

    def orient(self):
        """Normais para fora: acerta o sentido das faces (a peça é fechada) e confere pelo volume."""
        bm = bmesh.new()
        vs = [bm.verts.new(c) for c in self.co]
        for f in self.faces:
            bm.faces.new([vs[i] for i in f])
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.verts.index_update()
        self.faces = [tuple(v.index for v in f.verts) for f in bm.faces]
        bm.free()
        if self.volume() < 0.0:
            self.faces = [tuple(reversed(f)) for f in self.faces]

    def to_object(self, colors):
        me = bpy.data.meshes.new(self.name)
        me.from_pydata([tuple(c) for c in self.co], [], self.faces)
        me.update()
        if self.sharp:
            keys = {tuple(sorted(e)) for e in self.sharp}
            attr = me.attributes.get("sharp_edge") or me.attributes.new("sharp_edge", "BOOLEAN", "EDGE")
            attr.data.foreach_set("value", [tuple(sorted(e.vertices)) in keys for e in me.edges])
        col = me.color_attributes.new(name="Color", type="BYTE_COLOR", domain="POINT")
        col.data.foreach_set("color", [c for rgba in colors for c in rgba])
        me.color_attributes.active_color = col
        for p in me.polygons:
            p.use_smooth = True
        obj = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(obj)
        return obj


class Model:
    """As peças de um bicho e o peso do nado dele (função da posição, depois de escalar)."""

    def __init__(self, name, swim):
        self.name = name
        self.swim = swim
        self.parts = []

    def part(self, name, paint):
        p = Part(self.name + name, paint)
        self.parts.append(p)
        return p

    def objects(self, length=1.0, axis=1):
        """Escala para `length` no eixo `axis` (None: não mexe), centra, pinta e cria os objetos."""
        if axis is not None:
            allco = [c for p in self.parts for c in p.co]
            lo = Vector([min(c[k] for c in allco) for k in range(3)])
            hi = Vector([max(c[k] for c in allco) for k in range(3)])
            s = length / (hi[axis] - lo[axis])
            mid = (lo + hi) * 0.5
            for p in self.parts:
                p.co = [(c - mid) * s for c in p.co]
        objs = []
        for p in self.parts:
            p.orient()
            cols = []
            for co, prm in zip(p.co, p.prm):
                r, g, b, a = p.paint(co, prm)
                if r is None:
                    r = self.swim(co)
                cols.append((clamp(r), clamp(g), clamp(b), clamp(a)))
            objs.append(p.to_object(cols))
        return objs


# ---------------------------------------------------------------------------
# Corpo por anéis
# ---------------------------------------------------------------------------
def thetas(knots):
    """Ângulos de um anel (0 = dorso, pi/2 = lado +x, pi = ventre): knots = [(ângulo, segmentos até o
    próximo), ..., (pi, 0)] na metade +x; a metade -x é o espelho."""
    half = []
    for (a, n), (b, _) in zip(knots, knots[1:]):
        half += [a + (b - a) * i / n for i in range(n)]
    half.append(knots[-1][0])
    return half + [TAU - t for t in reversed(half[1:-1])]


def profile(top, bot, mid):
    """Perfis do corpo a partir do contorno de lado: z do dorso, do ventre e da linha mais larga
    (tabelas [(d, z), ...]); devolve zc, a, b."""
    top, bot, mid = Curve(top), Curve(bot), Curve(mid)
    return mid, (lambda d: max(top(d) - mid(d), 0.0)), (lambda d: max(mid(d) - bot(d), 0.0))


class Body:
    """Corpo ao longo de y: d = distância desde a ponta do focinho (y = y0 + d); perfis em função de d
    (Curve ou função): altura do centro zc, dorso a, ventre b, meia-largura w, expoentes da
    superelipse em cima (nt) e embaixo (nb)."""

    def __init__(self, zc, a, b, w, nt=2.0, nb=2.0, y0=0.0):
        self.zc, self.a, self.b, self.w = zc, a, b, w
        self.nt, self.nb = nt, nb
        self.y0 = y0

    def point(self, d, th):
        s, c = math.sin(th), math.cos(th)
        n = self.nt(d) if c >= 0.0 else self.nb(d)
        n = n if isinstance(n, float) else float(n)
        x = self.w(d) * sgnpow(s, 2.0 / n)
        z = self.zc(d) + (self.a(d) if c >= 0.0 else self.b(d)) * sgnpow(c, 2.0 / n)
        return Vector((x, self.y0 + d, z))

    def normal(self, d, th):
        e = 1e-4
        pd = self.point(d + e, th) - self.point(max(d - e, 0.0), th)
        pt = self.point(d, th + e) - self.point(d, th - e)
        n = pt.cross(pd)
        if n.length < 1e-12:
            return Vector((math.sin(th), 0.0, math.cos(th)))
        n.normalize()
        return n

    def ring(self, d, ths, prm=None, push=None):
        """Anel em d (ou o polo, se o raio é zero); push(d, th) empurra pela normal (sulcos)."""
        if self.w(d) < 1e-6 and self.a(d) < 1e-6:
            return [(Vector((0.0, self.y0 + d, self.zc(d))), dict(prm or {}, d=d, th=0.0))]
        out = []
        for th in ths:
            p = self.point(d, th)
            if push:
                k = push(d, th)
                if k:
                    p = p + self.normal(d, th) * k
            out.append((p, dict(prm or {}, d=d, th=th)))
        return out


def body_part(part, body, stations, knots, push=None, extra=None):
    """Tubo do corpo pelos valores de d em `stations`; knots(d) dá os nós do anel (thetas);
    extra(d) acrescenta parâmetros aos vértices do anel. Uma ponta que não termina num polo é fechada
    com um leque (fica escondida dentro de outra peça)."""
    rings = []
    for d in stations:
        rings.append(part.ring(body.ring(d, thetas(knots(d)), extra(d) if extra else None, push)))
    part.connect(rings)
    if len(rings[0]) > 1:
        part.fan(rings[0], dict(part.prm[rings[0][0]]), first=True)
    if len(rings[-1]) > 1:
        part.fan(rings[-1], dict(part.prm[rings[-1][0]]), first=False)
    return rings


# ---------------------------------------------------------------------------
# Nadadeiras (perfil NACA entre o bordo de ataque e o de fuga)
# ---------------------------------------------------------------------------
def naca(c):
    """Meia-espessura do perfil NACA 00xx (bordo de fuga fechado), normalizada para 1 no máximo."""
    return max(0.2969 * math.sqrt(c) - 0.1260 * c - 0.3516 * c * c + 0.2843 * c ** 3 - 0.1036 * c ** 4, 0.0) / 0.10003


def foil(part, ss, le, te, thick, normal, m=5, root="fan", tip="pole", prm=None, shape=naca, camber=None, cs=None,
         bow=None):
    """Nadadeira de s = ss[0] a ss[-1]: le(s) e te(s) são os bordos (Vector), thick(s) a espessura
    máxima, normal(s) o lado de cima (+). root/tip: "pole" fecha num ponto (ponta), "fan" num leque
    (raiz escondida no corpo). Anel: bordo de fuga, m pontos em cima, bordo de ataque, m embaixo
    (nas frações de corda `cs`: lista, ou função de s que devolve as listas de cima e de baixo, com
    o mesmo número de pontos em todas as estações). camber(s): fração da espessura que passa para
    cima (0 = simétrico). bow(s, c) -> Vector curva a linha da corda (a membrana do polvo). Os
    parâmetros do vértice: s, c (0 no ataque, 1 na fuga) e side (+1 em cima, -1 embaixo, 0 nos
    bordos). O bordo de fuga fica com aresta viva."""
    if cs is None:
        cs = [1.0 - math.cos(math.pi * 0.5 * i / (m + 1)) for i in range(1, m + 1)]
    rings = []
    last = len(ss) - 1
    for k, s in enumerate(ss):
        base = dict(prm or {}, s=s)
        a, b = le(s), te(s)
        if (k == 0 and root == "pole") or (k == last and tip == "pole"):
            rings.append([part.vert((a + b) * 0.5, dict(base, c=0.5, side=0))])
            continue
        up, lo = cs(s) if callable(cs) else (cs, cs)
        n = Vector(normal(s)).normalized()
        h = thick(s) * 0.5
        k = camber(s) if camber else 0.0

        def mid(c, a=a, b=b, s=s):
            return a.lerp(b, c) + (bow(s, c) if bow else Vector())
        pts = [(b, dict(base, c=1.0, side=0))]
        pts += [(mid(c) + n * (h * (1.0 + k) * shape(c)), dict(base, c=c, side=1)) for c in reversed(up)]
        pts.append((a, dict(base, c=0.0, side=0)))
        pts += [(mid(c) - n * (h * (1.0 - k) * shape(c)), dict(base, c=c, side=-1)) for c in lo]
        rings.append(part.ring(pts))
    part.connect(rings)
    if root == "fan":
        part.fan(rings[0], dict(prm or {}, s=ss[0], c=0.5, side=0), first=True)
    if tip == "fan":
        part.fan(rings[-1], dict(prm or {}, s=ss[-1], c=0.5, side=0), first=False)
    for r0, r1 in zip(rings, rings[1:]):
        if len(r0) > 1 and len(r1) > 1:
            part.sharp.append((r0[0], r1[0]))
    return rings


# ---------------------------------------------------------------------------
# Domos (olhos, tubérculos, cracas) e tubos (braços, cauda, fendas)
# ---------------------------------------------------------------------------
def frame(n):
    """Dois vetores perpendiculares a n."""
    n = Vector(n).normalized()
    t = n.cross(Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))).normalized()
    return t, n.cross(t)


def dome(part, center, normal, radius, height, nu=8, rings=(100, 62, 30), prm=None):
    """Calota (meio esferoide) sobre a superfície: base um pouco enterrada (tampa em leque escondida),
    anéis nos ângulos `rings` (graus a partir do eixo) e o polo no alto. Parâmetros: phi (0 no alto)
    e ang (ângulo em volta)."""
    n = Vector(normal).normalized()
    t1, t2 = frame(n)
    out = []
    for deg in rings:
        phi = math.radians(deg)
        r = []
        for i in range(nu):
            ang = TAU * i / nu
            p = Vector(center) + n * (height * math.cos(phi)) + (t1 * math.cos(ang) + t2 * math.sin(ang)) * (radius * math.sin(phi))
            r.append(part.vert(p, dict(prm or {}, phi=phi, ang=ang)))
        out.append(r)
    top = part.vert(Vector(center) + n * height, dict(prm or {}, phi=0.0, ang=0.0))
    part.connect(out + [[top]])
    part.fan(out[0], dict(prm or {}, phi=math.pi, ang=0.0), first=True)
    return out


def ellipsoid(part, center, axes, nu=8, nv=6, prm=None):
    """Esferoide de eixos (Vector x, y, z: o eixo z vai de polo a polo). Parâmetros: phi (0 no polo
    +z) e ang."""
    ax, ay, az = (Vector(v) for v in axes)
    rings = [[part.vert(Vector(center) - az, dict(prm or {}, phi=math.pi, ang=0.0))]]
    for k in range(1, nv):
        phi = math.pi * (1.0 - k / nv)
        r = []
        for i in range(nu):
            ang = TAU * i / nu
            p = Vector(center) + az * math.cos(phi) + (ax * math.cos(ang) + ay * math.sin(ang)) * math.sin(phi)
            r.append(part.vert(p, dict(prm or {}, phi=phi, ang=ang)))
        rings.append(r)
    rings.append([part.vert(Vector(center) + az, dict(prm or {}, phi=0.0, ang=0.0))])
    part.connect(rings)
    return rings


def tube(part, pts, radii, nseg, prm=None, start="fan", end="pole", shape=None, frames=None):
    """Tubo pela poligonal `pts` (Vector) com os raios `radii`; frames = [(normal, binormal)] por
    ponto (senão, transporte paralelo). shape(i, ang) -> (fx, fy) achata a seção (ou um número só,
    que escala o raio naquele ângulo). Parâmetros do vértice: i (ponto), u (0..1 ao longo), ang (0 =
    lado da normal) e j (índice no anel)."""
    n = len(pts)
    if frames is None:
        frames = transport(pts)
    rings = []
    for i, (p, r) in enumerate(zip(pts, radii)):
        base = dict(prm or {}, i=i, u=i / (n - 1))
        if (i == 0 and start == "pole") or (i == n - 1 and end == "pole"):
            rings.append([part.vert(p, dict(base, ang=0.0, j=-1))])
            continue
        nn, bb = frames[i]
        ring = []
        for j in range(nseg):
            ang = TAU * j / nseg
            f = shape(i, ang) if shape else (1.0, 1.0)
            fx, fy = (f, f) if isinstance(f, float) else f
            ring.append(part.vert(p + (nn * (math.cos(ang) * fx) + bb * (math.sin(ang) * fy)) * r, dict(base, ang=ang, j=j)))
        rings.append(ring)
    part.connect(rings)
    if start == "fan":
        part.fan(rings[0], dict(prm or {}, i=0, u=0.0, ang=0.0), first=True)
    if end == "fan":
        part.fan(rings[-1], dict(prm or {}, i=n - 1, u=1.0, ang=0.0), first=False)
    return rings


def frames_up(pts, up):
    """Referenciais com a normal o mais perto possível de `up` (para tubos achatados)."""
    out = []
    for i in range(len(pts)):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        n = (Vector(up) - t * t.dot(Vector(up))).normalized()
        out.append((n, t.cross(n).normalized()))
    return out


def transport(pts):
    """Referenciais por transporte paralelo ao longo da poligonal: [(normal, binormal)]."""
    tans = []
    for i in range(len(pts)):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        tans.append((b - a).normalized())
    n = frame(tans[0])[0]
    out = []
    for i, t in enumerate(tans):
        if i > 0:
            n = n - t * n.dot(t)
            if n.length < 1e-9:
                n = frame(t)[0]
            n.normalize()
        out.append((n.copy(), t.cross(n).normalized()))
    return out


# ---------------------------------------------------------------------------
# Carapaça de placas (tartaruga)
# ---------------------------------------------------------------------------
def shell(part, half, samples, nodes, faces, marg_w, center, height, under):
    """Carapaça de placas: grafo plano (x, y) erguido sobre um domo, fechado pela borda e por baixo.
      half: contorno da metade +x, da frente (no meio) à traseira (no meio); t = 0..1 pelo
            comprimento, negativo na metade -x (1 e -1 são o mesmo ponto, atrás).
      samples: valores de t das amostras dos contornos de fora e de dentro (o das marginais).
      nodes: nós internos {nome: (x, y)} da metade +x; nome + "L" é o espelho.
      faces: placas, cada uma uma volta de trechos: ("in", ta, tb) contorno de dentro com t crescendo
             (passando por trás se ta > tb), ("in-", ta, tb) com t diminuindo, ("out", ta, tb) contorno
             de fora, ("e", a, b) aresta reta entre pontos ("O:t", "I:t" ou nome de nó).
      marg_w(t): largura das marginais; center (x, y) e height: o domo; under: anéis de baixo
      [(escala, z), ...] até o centro. Parâmetros dos vértices: kind (seam, edge, ring1, ring2,
      center, rim, under) e sid (a placa). Devolve a altura do domo, dome(x, y)."""
    acc = [0.0]
    for a, b in zip(half, half[1:]):
        acc.append(acc[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    out_path = Path([(acc[i] / acc[-1], (half[i][0], half[i][1], 0.0)) for i in range(len(half))])
    cx, cy = center

    def outline(t):
        p = out_path(abs(t))
        return (p.x if t >= 0 else -p.x, p.y)

    def inner(t):
        a = abs(t)
        if a < 1e-6 or a > 1.0 - 1e-6:
            x, y = outline(t)
            return (0.0, y + (marg_w(a) if a < 0.5 else -marg_w(a)))
        p0, p1 = out_path(max(a - 1e-3, 0.0)), out_path(min(a + 1e-3, 1.0))
        tx, ty = p1.x - p0.x, p1.y - p0.y
        ln = math.hypot(tx, ty)
        x = out_path(a).x - ty / ln * marg_w(a)
        y = out_path(a).y + tx / ln * marg_w(a)
        return (x if t >= 0 else -x, y)

    # Raio do contorno em cada direção (em volta do centro do domo)
    polar = {}
    for i in range(721):
        x, y = outline(i / 360.0 - 1.0)
        polar[round(math.atan2(x, y - cy), 9)] = math.hypot(x, y - cy)
    keys = sorted(polar)
    radius = Curve([(k, polar[k]) for k in keys])

    def dome(x, y):
        r = min(math.hypot(x, y - cy) / radius(math.atan2(x, y - cy)), 1.0)
        return height * (1.0 - r ** 2.4) ** 0.6

    pts2, kinds = [], []

    def vert(p, kind):
        pts2.append(p)
        kinds.append(kind)
        return len(pts2) - 1

    def key(t):
        return 1.0 if abs(abs(t) - 1.0) < 1e-9 else round(t, 6)

    cache = {}

    def point(name):
        """Vértice do ponto "O:t", "I:t" ou do nó."""
        if name in cache:
            return cache[name]
        if name[:2] in ("O:", "I:"):
            t = float(name[2:])
            k = name[:2] + str(key(t))
            if k not in cache:
                cache[k] = vert(outline(t) if name[0] == "O" else inner(t), "edge" if name[0] == "O" else "seam")
            cache[name] = cache[k]
            return cache[name]
        base = name[:-1] if name.endswith("L") else name
        x, y = nodes[base]
        if name.endswith("L") and abs(x) < 1e-9:
            cache[name] = point(base)
            return cache[name]
        cache[name] = vert((-x if name.endswith("L") else x, y), "seam")
        return cache[name]

    signed = sorted({key(-t) for t in samples if 0.0 < t < 1.0} | {key(t) for t in samples})

    def run(prefix, ta, tb):
        """Pontos do contorno de ta a tb com t crescendo (passando por trás se ta > tb)."""
        if ta <= tb:
            mid = [t for t in signed if ta + 1e-9 < t < tb - 1e-9]
        else:
            mid = [t for t in signed if t > ta + 1e-9] + [t for t in signed if t < tb - 1e-9 and t > -1.0 + 1e-9]
        return [point("%s%r" % (prefix, t)) for t in [ta] + mid + [tb]]

    edges = {}

    def canon(name):
        return name[:2] + repr(key(float(name[2:]))) if name[:2] in ("O:", "I:") else name

    def straight(a, b):
        a, b = canon(a), canon(b)
        if (b, a) in edges:
            return list(reversed(edges[(b, a)]))
        if (a, b) not in edges:
            pa, pb = pts2[point(a)], pts2[point(b)]
            n = max(1, round(math.hypot(pb[0] - pa[0], pb[1] - pa[1]) / 0.035))
            mid = [vert((mix(pa[0], pb[0], i / n), mix(pa[1], pb[1], i / n)), "seam") for i in range(1, n)]
            edges[(a, b)] = [point(a)] + mid + [point(b)]
        return edges[(a, b)]

    loops = []
    for face in faces:
        loop = []
        for seg in face:
            if seg[0] == "in":
                idx = run("I:", seg[1], seg[2])
            elif seg[0] == "in-":
                idx = list(reversed(run("I:", seg[2], seg[1])))
            elif seg[0] == "out":
                idx = run("O:", seg[1], seg[2])
            else:
                idx = straight(seg[1], seg[2])
            if loop and loop[-1] == idx[0]:
                idx = idx[1:]
            loop += idx
        if loop[0] == loop[-1]:
            loop.pop()
        area = sum(pts2[loop[i - 1]][0] * pts2[loop[i]][1] - pts2[loop[i]][0] * pts2[loop[i - 1]][1] for i in range(len(loop)))
        loops.append(loop if area > 0 else loop[::-1])

    # Contorno e costuras (as costuras um pouco fundas)
    base = len(part.co)
    for (x, y), kind in zip(pts2, kinds):
        part.vert((x, y, dome(x, y) - (0.0035 if kind == "seam" else 0.0)), dict(kind=kind, sid=-1))
    # Cada placa: anel de dentro (onde a borda escura acaba), anel do meio e o centro estufado
    for sid, loop in enumerate(loops):
        cxp = sum(pts2[i][0] for i in loop) / len(loop)
        cyp = sum(pts2[i][1] for i in loop) / len(loop)
        size = min(math.hypot(pts2[i][0] - cxp, pts2[i][1] - cyp) for i in loop)
        bulge = 0.0045 * min(1.0, size / 0.05)
        rings = [[base + i for i in loop]]
        for f, kind, lift in ((0.84, "ring1", 0.0), (0.45, "ring2", bulge * 0.8)):
            r = []
            for i in loop:
                x, y = mix(cxp, pts2[i][0], f), mix(cyp, pts2[i][1], f)
                r.append(part.vert((x, y, dome(x, y) + lift), dict(kind=kind, sid=sid)))
            rings.append(r)
        rings.append([part.vert((cxp, cyp, dome(cxp, cyp) + bulge), dict(kind="center", sid=sid))])
        part.connect(rings)
    # Borda e a parte de baixo, a partir do contorno de fora
    ring = [base + point("O:%r" % t) for t in signed]
    rings = [ring]
    for k, (f, z) in enumerate(under):
        rings.append([part.vert((cx + part.co[i].x * f, cy + (part.co[i].y - cy) * f, z), dict(kind="rim" if k == 0 else "under", sid=-1))
                      for i in ring])
    rings.append([part.vert((cx, cy, under[-1][1] - 0.004), dict(kind="under", sid=-1))])
    part.connect(rings)
    return dome


# ---------------------------------------------------------------------------
# Acabamento: oclusão nas reentrâncias (no canal B) e o atributo ativo
# ---------------------------------------------------------------------------
def _hemisphere(count):
    """Direções num hemisfério (z para cima), distribuídas pelo cosseno (espiral de Fibonacci)."""
    out = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(count):
        r = math.sqrt((i + 0.5) / count)
        a = i * golden
        out.append((r * math.cos(a), r * math.sin(a), math.sqrt(max(1.0 - r * r, 0.0))))
    return out


def finish(reach=0.06, strength=0.4, rays=32):
    """Pintura final (malha já juntada, em unidades da peça): soma ao B a oclusão das reentrâncias
    (raios até `reach` em volta de cada vértice) sem apagar o que as peças já pintaram."""
    dirs = _hemisphere(rays)

    def paint(me):
        col = me.color_attributes.get("Color")
        if col is None:
            col = me.color_attributes.new(name="Color", type="BYTE_COLOR", domain="POINT")
            col.data.foreach_set("color", [0.0] * (4 * len(me.vertices)))
        verts = [v.co.copy() for v in me.vertices]
        bvh = BVHTree.FromPolygons(verts, [tuple(p.vertices) for p in me.polygons])
        rgba = [0.0] * (4 * len(verts))
        col.data.foreach_get("color", rgba)
        for i, v in enumerate(me.vertices):
            n = v.normal
            t1, t2 = frame(n)
            o = v.co + n * (reach * 0.02)
            hits = 0
            for dx, dy, dz in dirs:
                if bvh.ray_cast(o, t1 * dx + t2 * dy + n * dz, reach)[0] is not None:
                    hits += 1
            occ = strength * hits / rays
            b = rgba[4 * i + 2]
            rgba[4 * i + 2] = 1.0 - (1.0 - b) * (1.0 - occ)
        col.data.foreach_set("color", rgba)
        me.color_attributes.active_color = col
    return paint


# ---------------------------------------------------------------------------
# Baleia-jubarte
# ---------------------------------------------------------------------------
def whale():
    """Jubarte: cabeça achatada com tubérculos, mandíbula saltada com a linha da boca, pregas da
    garganta até o umbigo, peitorais compridas de bordo ondulado, corcova com a dorsal pequena,
    pedúnculo alto e cauda larga serrilhada com o entalhe."""
    m = Model("Whale", lambda co: max(smooth(-0.02, 0.5, co.y) ** 1.2,
                                      0.4 * smooth(0.1, 0.32, abs(co.x)) * window(co.y, -0.3, 0.05, 0.1)))
    zc, a, b = profile(
        [(0, -0.016), (0.004, -0.008), (0.012, -0.002), (0.03, 0.006), (0.06, 0.017), (0.1, 0.031), (0.15, 0.046),
         (0.19, 0.057), (0.21, 0.062), (0.24, 0.066), (0.3, 0.073), (0.4, 0.077), (0.5, 0.075), (0.57, 0.07), (0.61, 0.07),
         (0.66, 0.063), (0.72, 0.051), (0.78, 0.039), (0.84, 0.028), (0.88, 0.02), (0.91, 0.0115), (0.935, 0.0)],
        [(0, -0.016), (0.004, -0.029), (0.012, -0.041), (0.03, -0.056), (0.06, -0.073), (0.1, -0.089), (0.15, -0.103),
         (0.2, -0.113), (0.26, -0.119), (0.32, -0.119), (0.4, -0.111), (0.5, -0.097), (0.6, -0.079), (0.66, -0.066),
         (0.72, -0.051), (0.78, -0.037), (0.84, -0.025), (0.88, -0.0165), (0.91, -0.0095), (0.935, 0.0)],
        [(0, -0.016), (0.03, -0.02), (0.25, -0.022), (0.35, -0.016), (0.5, -0.01), (0.8, -0.002), (0.935, 0.0)])
    w = Curve([(0, 0), (0.004, 0.014), (0.012, 0.024), (0.03, 0.036), (0.06, 0.049), (0.1, 0.061), (0.15, 0.072),
               (0.2, 0.08), (0.26, 0.087), (0.32, 0.089), (0.4, 0.087), (0.5, 0.078), (0.6, 0.064), (0.7, 0.047),
               (0.78, 0.032), (0.84, 0.0215), (0.88, 0.0148), (0.91, 0.0097), (0.935, 0.0)])
    nt = Curve([(0, 2.7), (0.22, 2.6), (0.34, 2.1), (0.6, 2.0), (0.76, 1.6), (0.935, 1.45)])
    nb = Curve([(0, 2.0), (0.6, 2.0), (0.76, 1.65), (0.935, 1.5)])
    body = Body(zc, a, b, w, nt=nt, nb=nb)
    gape = 0.255                                              # canto da boca
    mouth = Curve([(0, 1.72), (0.03, 1.5), (0.1, 1.33), (0.18, 1.33), (0.23, 1.4), (gape, 1.57), (0.3, 1.66),
                   (0.5, 1.7), (0.935, 1.7)])
    seam = Curve([(0, math.radians(3.2)), (gape, math.radians(2.6)), (gape + 0.05, math.radians(6.0)), (1.0, math.radians(6.0))])
    belly = Curve([(0, 2.62), (0.03, 2.5), (0.06, 2.28), (0.1, 2.1), (0.2, 2.06), (0.3, 2.08), (0.45, 2.2), (0.55, 2.45),
                   (0.7, 2.75), (0.8, 2.9), (0.935, 2.95)])
    gseam = math.radians(1.2)
    pleat_n = 12                                              # segmentos do ventre (sulco sim, sulco não)

    def knots(d):
        return [(0.0, 6), (mouth(d) - seam(d), 2), (mouth(d) + seam(d), 2), (belly(d) - gseam, 1),
                (belly(d) + gseam, pleat_n), (math.pi, 0)]

    def where(d, th):
        """Na boca (0 = no sulco, -1 acima, +1 no lábio), sulco da garganta (True) e no ventre."""
        t = min(th, TAU - th)
        mo = None
        for k, off in ((-1, -seam(d)), (0, 0.0), (1, seam(d))):
            if abs(t - (mouth(d) + off)) < 1e-6:
                mo = k
        pl = False
        if t > belly(d) + gseam - 1e-6:
            k = round((t - belly(d) - gseam) / ((math.pi - belly(d) - gseam) / pleat_n))
            pl = k % 2 == 1
        return t, mo, pl

    def lip(d):
        return smooth(0.0, 0.012, d) * (1.0 - smooth(gape - 0.015, gape + 0.01, d))

    def pleat(d):
        return smooth(0.03, 0.07, d) * (1.0 - smooth(0.42, 0.5, d))

    def push(d, th):
        t, mo, pl = where(d, th)
        out = 0.0
        if mo is not None:
            out += (-0.002, -0.0045, 0.0028)[mo + 1] * lip(d)
        if pl:
            out -= 0.0017 * pleat(d)
        return out

    stations = [0.0, 0.003, 0.008, 0.015, 0.024, 0.034, 0.045, 0.057, 0.07, 0.084, 0.098, 0.113, 0.128, 0.143, 0.158,
                0.173, 0.188, 0.2, 0.212, 0.224, 0.236, 0.247, 0.257, 0.268, 0.28, 0.295, 0.312, 0.33, 0.35, 0.372, 0.4,
                0.43, 0.46, 0.49, 0.52, 0.55, 0.578, 0.6, 0.62, 0.64, 0.66, 0.68, 0.705, 0.735, 0.77, 0.805, 0.835,
                0.856, 0.874, 0.89, 0.906, 0.92, 0.935]

    def paint_body(co, p):
        d, th = p["d"], p["th"]
        t, mo, pl = where(d, th)
        g = 1.0 if t > belly(d) + 1e-6 else 0.0
        bb = 0.0
        if mo == 0:
            bb = lip(d)
        if pl:
            bb = max(bb, 0.5 * pleat(d))
        return None, g, bb, 0.0

    body_part(m.part("Body", paint_body), body, stations, knots, push)

    # Tubérculos: três fileiras no focinho, uma no lábio de baixo e o tufo do queixo
    knobs = m.part("Knobs", lambda co, p: (None, 0.0, 0.18, 0.0))
    spots = [(d, 0.0, 0.0062) for d in (0.03, 0.06, 0.09, 0.12, 0.15, 0.178)]
    spots += [(d, sg * th, r) for sg in (1, -1) for d, th, r in
              ((0.02, 0.62, 0.0055), (0.045, 0.66, 0.006), (0.075, 0.7, 0.006), (0.105, 0.72, 0.006), (0.135, 0.75, 0.0055),
               (0.165, 0.78, 0.005), (0.035, 1.92, 0.0055), (0.07, 1.82, 0.006), (0.11, 1.78, 0.0055), (0.15, 1.76, 0.005))]
    spots += [(0.01, sg * 2.6, 0.006) for sg in (1, -1)] + [(0.004, math.pi, 0.0055)]
    for d, th, r in spots:
        th = th % TAU
        c, n = body.point(d, th), body.normal(d, th)
        dome(knobs, c - n * r * 0.3, n, r * 1.1, r * 0.75, nu=6, rings=(100, 50))
    # Cracas: grupinhos claros no queixo e nos lados da mandíbula
    shells = m.part("Barnacles", lambda co, p: (None, 0.0, 0.0, 1.0))
    for d, th, r in ((0.014, 2.25, 0.0042), (0.02, 2.4, 0.0034), (0.022, 2.12, 0.003), (0.045, 1.72, 0.0046),
                     (0.052, 1.8, 0.0034), (0.04, 1.84, 0.0028), (0.085, 1.66, 0.0036), (0.09, 1.74, 0.0028)):
        for sgn in ((1, -1) if d < 0.03 else (1,)):
            tt = (sgn * th) % TAU
            c, n = body.point(d, tt), body.normal(d, tt)
            dome(shells, c - n * r * 0.25, n, r, r * 0.8, nu=6, rings=(100, 50))
    for d, th, r in ((0.06, -1.7, 0.0042), (0.068, -1.78, 0.003), (0.03, -1.95, 0.0034)):
        tt = th % TAU
        c, n = body.point(d, tt), body.normal(d, tt)
        dome(shells, c - n * r * 0.25, n, r, r * 0.8, nu=6, rings=(100, 50))

    # Olho com a pálpebra (calombo) logo acima e atrás do canto da boca
    for sgn in (1, -1):
        th = 1.45 if sgn > 0 else TAU - 1.45
        c, n = body.point(gape + 0.008, th), body.normal(gape + 0.008, th)
        dome(m.part("Lid", lambda co, p: (None, 0.0, 0.1, 0.0)), c - n * 0.004, n, 0.013, 0.0075, nu=8, rings=(100, 64, 34))
        dome(m.part("Eye", lambda co, p: (None, 0.0, 1.0, 0.0)), c + n * 0.0012, n, 0.0058, 0.0028, nu=8, rings=(100, 55))

    # Espiráculos: as duas fendas em V atrás da proteção contra respingos
    guard = m.part("Guard", lambda co, p: (None, 0.0, 0.0, 0.0))
    c, n = body.point(0.192, 0.0), body.normal(0.192, 0.0)
    ellipsoid(guard, c - n * 0.004, (Vector((0.016, 0, 0)), Vector((0, 0.014, 0)), n * 0.0085), nu=10, nv=5)
    holes = m.part("Blowholes", lambda co, p: (None, 0.0, 1.0, 0.0))
    for sgn in (1, -1):
        pts, rad = [], []
        for i in range(6):
            u = i / 5.0
            d = 0.198 + 0.02 * u
            th = sgn * (0.035 + 0.075 * u)
            q = body.point(d, th % TAU)
            pts.append(q + body.normal(d, th % TAU) * (0.0045 * (1.0 - u) ** 2))
            rad.append(0.0023 * math.sin(math.pi * (0.15 + 0.7 * u)))
        tube(holes, pts, rad, 6, start="pole", end="pole")

    def top(d):
        return body.point(d, 0.0).z

    # Corcova e a dorsal pequena a ~2/3
    tip = Vector((0, 0.668, top(0.65) + 0.024))
    le = Path([(0.0, (0, 0.6, top(0.6) - 0.01)), (0.25, (0, 0.615, top(0.615) + 0.003)), (0.6, (0, 0.645, top(0.64) + 0.014)),
               (1.0, tip)])
    te = Path([(0.0, (0, 0.7, top(0.7) - 0.01)), (0.25, (0, 0.688, top(0.688) + 0.002)), (0.6, (0, 0.672, top(0.672) + 0.011)),
               (1.0, tip)])
    foil(m.part("Dorsal", lambda co, p: (None, 0.0, 0.0, 0.0)), [0.0, 0.12, 0.26, 0.42, 0.58, 0.74, 0.88, 1.0], le, te,
         lambda s: mix(0.03, 0.005, s), lambda s: (1, 0, 0), m=4)
    # Os nós da crista do pedúnculo
    for d, r in ((0.74, 0.007), (0.77, 0.0062), (0.8, 0.0055), (0.83, 0.0048)):
        c, n = body.point(d, 0.0), body.normal(d, 0.0)
        ellipsoid(knobs, c - n * 0.002, (Vector((r * 0.7, 0, 0)), Vector((0, r * 1.6, 0)), n * r * 0.8), nu=6, nv=4)

    # Cauda: da ponta esquerda à direita (s = x), bordo de fuga serrilhado e o entalhe no meio
    span = 0.155
    le_y = Curve([(0.0, 0.884), (0.03, 0.888), (0.06, 0.897), (0.09, 0.912), (0.115, 0.932), (0.135, 0.955), (0.148, 0.978),
                  (span, 0.998)])
    te_y = Curve([(0.0, 0.952), (0.008, 0.964), (0.025, 0.97), (0.06, 0.973), (0.1, 0.979), (0.13, 0.986), (span, 0.998)])
    # Serrilha: recortes arredondados para trás, de larguras e alturas desiguais, com o entalhe vivo
    # entre eles (em |x|)
    notches = [0.014, 0.0305, 0.0465, 0.0638, 0.0795, 0.0965, 0.1125, 0.1285, 0.1425]
    heights = [0.0045, 0.006, 0.0052, 0.0066, 0.0055, 0.0062, 0.0048, 0.0038]

    def serr(x):
        for a, b, h in zip(notches, notches[1:], heights):
            if a <= x <= b:
                t = abs(2.0 * (x - a) / (b - a) - 1.0)
                return h * max(1.0 - t ** 3, 0.0) ** 0.6
        return 0.0
    shoulders = [mix(a, b, f) for a, b in zip(notches, notches[1:]) for f in (0.28, 0.72)]
    xs = sorted({0.0, 0.004, 0.149, span} | {round(x, 5) for x in notches + shoulders})
    ss = [-x for x in reversed(xs[1:])] + xs
    le = Path([(x, (x, le_y(abs(x)), 0.002)) for x in ss])
    te = Path([(x, (x, te_y(abs(x)) + serr(abs(x)), 0.0)) for x in ss])

    def fluke_paint(co, p):
        x, c, side = abs(p["s"]), p["c"], p["side"]
        g = 0.0
        if side < 0:      # embaixo: branco com a borda de trás e as pontas escuras
            g = (1.0 - smooth(0.72, 0.86, c)) * (1.0 - smooth(0.11, 0.135, x)) * smooth(0.0, 0.012, x)
        return None, g, 0.0, 0.0
    foil(m.part("Flukes", fluke_paint), ss, le, te, lambda s: mix(0.024, 0.0035, smooth(0.0, span, abs(s)) ** 0.75),
         lambda s: (0, 0, 1), m=4, root="pole", tip="pole")

    # Peitorais: ~1/3 do corpo, bordo de ataque com os tubérculos, para fora, para baixo e para trás
    bumps = [0.17 + 0.094 * k for k in range(8)]

    def lebump(u):
        best = 0.0
        for k, ub in enumerate(bumps):
            f = max(0.0, 1.0 - abs(u - ub) / 0.047)
            best = max(best, (0.5 - 0.5 * math.cos(math.pi * f)) * (0.0036 + 0.0014 * math.sin(k * 1.7)))
        return best * smooth(0.1, 0.2, u)
    us = sorted({0.0, 0.035, 0.08, 0.12, 0.985, 1.0} | {round(b + o, 4) for b in bumps for o in (-0.047, -0.0235, 0.0, 0.0235)})
    us = [u for u in us if 0.0 <= u <= 1.0]
    chord_le = Curve([(0, 0.0), (0.1, -0.006), (0.3, -0.008), (0.6, -0.006), (0.85, -0.001), (1.0, 0.012)])
    chord_te = Curve([(0, 0.062), (0.1, 0.066), (0.25, 0.058), (0.5, 0.044), (0.75, 0.03), (0.92, 0.018), (1.0, 0.012)])
    for sgn in (1, -1):
        def side(v, sgn=sgn):
            return Vector((v[0] * sgn, v[1], v[2]))
        th0 = 1.95 if sgn > 0 else TAU - 1.95
        root = body.point(0.292, th0) + side((-0.02, 0.0, 0.006))
        span_v = side((0.205, 0.105, -0.13))
        L = span_v.length
        U = span_v.normalized()
        C = (Vector((0, 1, 0)) - U * U.y).normalized()
        N = U.cross(C) * sgn
        if N.z < 0:
            N = -N

        def at(u, off, U=U, C=C, N=N, root=root, L=L):
            return root + U * (u * L) + C * off + N * (-0.02 * u * u + 0.012 * u)

        def paint(co, p):
            u, side_ = p["s"], p["side"]
            root_fade = smooth(0.06, 0.16, u)
            g = 1.0 if side_ < 0 else 0.0
            return None, g * root_fade, 0.0, (1.0 if side_ >= 0 else 0.0) * root_fade
        le = Path([(u, at(u, chord_le(u) - lebump(u))) for u in us])
        te = Path([(u, at(u, chord_te(u))) for u in us])
        foil(m.part("Flipper", paint), us, le, te, lambda u: mix(0.02, 0.004, u ** 0.9), lambda s, N=N: N, m=4)
    return m.objects()


# ---------------------------------------------------------------------------
# Raia-manta
# ---------------------------------------------------------------------------
def manta():
    """Raia-manta: o disco é um perfil de asa só, de uma ponta à outra (s = x), grosso no meio e fino
    nas asas, com a boca larga na frente; lobos cefálicos, olhos nos lados da cabeça, cinco pares de
    fendas embaixo, pélvicas, a dorsal pequena e a cauda fina."""
    m = Model("Manta", lambda co: smooth(0.06, 0.5, abs(co.x)) ** 1.1)
    yle = Curve([(0.0, -0.2), (0.04, -0.2), (0.066, -0.197), (0.082, -0.184), (0.1, -0.163), (0.13, -0.137), (0.17, -0.108),
                 (0.22, -0.078), (0.27, -0.051), (0.32, -0.027), (0.37, -0.003), (0.41, 0.018), (0.445, 0.04), (0.47, 0.061),
                 (0.488, 0.082), (0.5, 0.106)])
    yte = Curve([(0.0, 0.218), (0.025, 0.215), (0.05, 0.203), (0.075, 0.18), (0.1, 0.158), (0.13, 0.14), (0.17, 0.124),
                 (0.22, 0.112), (0.28, 0.104), (0.34, 0.1), (0.4, 0.099), (0.45, 0.1), (0.48, 0.102), (0.5, 0.106)])
    thick = Curve([(0.0, 0.084), (0.04, 0.081), (0.07, 0.071), (0.1, 0.055), (0.14, 0.04), (0.2, 0.029), (0.3, 0.019),
                   (0.4, 0.012), (0.46, 0.0075), (0.5, 0.002)])
    camber = Curve([(0.0, 0.24), (0.08, 0.2), (0.15, 0.12), (0.3, 0.08), (0.5, 0.05)])
    droop = Curve([(0.0, 0.0), (0.1, 0.0), (0.25, -0.012), (0.4, -0.03), (0.5, -0.044)])
    mouth = 0.062                                             # meia-largura da boca

    def le(s):
        x = abs(s)
        notch = 0.007 * (1.0 - smooth(mouth - 0.012, mouth, x))
        return Vector((s, yle(x) + notch, droop(x)))

    def te(s):
        return Vector((s, yte(abs(s)), droop(abs(s))))

    def surf(x, y, up):
        """Ponto da face de cima (up) ou de baixo do disco em (x, y)."""
        c = clamp((y - yle(abs(x))) / (yte(abs(x)) - yle(abs(x))))
        h = thick(abs(x)) * 0.5 * naca(c)
        k = camber(abs(x))
        return Vector((x, y, droop(abs(x)) + (h * (1 + k) if up else -h * (1 - k))))

    half = [0.0, 0.014, 0.028, 0.042, 0.055, 0.067, 0.077, 0.083, 0.095, 0.11, 0.13, 0.152, 0.176, 0.202, 0.229, 0.257,
            0.286, 0.315, 0.344, 0.372, 0.399, 0.424, 0.446, 0.465, 0.481, 0.493, 0.5]
    ss = [-x for x in reversed(half[1:])] + half

    # Manchas brancas dos ombros (o "chevron" da manta-gigante): triângulos atrás do bordo de ataque,
    # entre a borda de dentro (|x| = 0,08), a da frente (paralela ao bordo de ataque) e a diagonal de
    # trás. As bordas da frente e de trás são costuras na corda da face de cima (c1 e c2), para a
    # mancha ficar nítida e sem degraus.
    inner, tip_x, seam = 0.08, 0.292, 0.004

    def chord(x):
        return yte(x) - yle(x)

    def c1(x):
        return 0.03 / chord(min(max(x, inner), tip_x))

    def c2(x):
        xc = min(max(x, inner), tip_x)
        rear = mix(0.03, -0.022, (xc - inner) / (tip_x - inner))
        return max((rear - yle(xc)) / chord(xc), c1(x) + 0.035)

    def cs(s):
        x = abs(s)
        a, b = c1(x), c2(x)
        up = [a * 0.1, a * 0.42, a - seam, a + seam]
        up += [mix(a + seam, b - seam, i / 4.0) for i in (1, 2, 3)]
        up += [b - seam, b + seam] + [mix(b + seam, 1.0, i / 5.0) for i in (1, 2, 3, 4)]
        return up, [0.008, 0.03, 0.07, 0.13, 0.21, 0.31, 0.43, 0.56, 0.7, 0.85]

    def paint_disc(co, p):
        x, c, side = abs(p["s"]), p["c"], p["side"]
        g, bb, acc = 0.0, 0.0, 0.0
        if side < 0:
            # Ventre branco com a margem escura atrás e nas pontas
            g = (1.0 - smooth(0.8, 0.9, c) * smooth(0.12, 0.2, x)) * (1.0 - smooth(0.43, 0.47, x))
            bb = 0.25 * smooth(0.8, 0.95, c) * smooth(0.12, 0.2, x)
        elif side > 0 and inner - 1e-4 < x < tip_x + 0.01 and c1(x) < c < c2(x):
            acc = 1.0
        if x < mouth + 0.004 and c < 0.02:                   # boca
            bb = max(bb, 1.0 - smooth(mouth - 0.012, mouth + 0.002, x))
            g = 0.0
        return None, g, bb, acc
    foil(m.part("Disc", paint_disc), ss, le, te, lambda s: thick(abs(s)), lambda s: (0, 0, 1), root="pole", tip="pole",
         camber=lambda s: camber(abs(s)), cs=cs)

    for sgn in (1, -1):
        def side(v, sgn=sgn):
            return Vector((v[0] * sgn, v[1], v[2]))
        # Lobos cefálicos: enrolados como chifres para a frente, curvando para dentro na ponta (por
        # dentro mais claros)
        pts = [side(v) for v in ((0.068, -0.17, -0.003), (0.074, -0.196, 0.0), (0.074, -0.222, -0.002), (0.071, -0.246, -0.005),
                                 (0.067, -0.265, -0.007), (0.063, -0.278, -0.008), (0.061, -0.285, -0.008))]
        path = Path([(i / 6.0, p) for i, p in enumerate(pts)])
        pts = [path(i / 10.0) for i in range(11)]
        rad = [0.0125, 0.0125, 0.012, 0.0112, 0.0102, 0.009, 0.0078, 0.0066, 0.0054, 0.0042, 0.002]

        def lobe_paint(co, p, sgn=sgn):
            return None, 0.65 * smooth(0.0, 0.8, sgn * math.sin(p["ang"])), 0.0, 0.0
        tube(m.part("Lobe", lobe_paint), pts, rad, 8, start="fan", end="pole", shape=lambda i, ang: (1.0, 0.62),
             frames=frames_up(pts, side((-0.6, 0.0, 0.8))))
        # Olho no lado da cabeça, logo atrás do lobo
        c = side((0.089, -0.158, 0.006))
        n = side((1.0, -0.35, 0.25)).normalized()
        dome(m.part("Eye", lambda co, p: (None, 0.0, 1.0, 0.0)), c - n * 0.003, n, 0.0072, 0.0042, nu=8, rings=(100, 60))
        # Fendas das guelras: cinco de cada lado, embaixo, atrás da boca
        gills = m.part("Gills", lambda co, p: (None, 1.0, 1.0, 0.0))
        for k in range(5):
            y0 = -0.112 + 0.023 * k
            x0 = 0.04 + 0.004 * k
            L = 0.04 - 0.003 * k
            pts, rad = [], []
            for i in range(5):
                u = i / 4.0
                x = x0 + L * u
                y = y0 + 0.006 * u - 0.004 * math.sin(math.pi * u)
                pts.append(surf(sgn * x, y, False) + Vector((0, 0, 0.0006)))
                rad.append(0.0024 * math.sin(math.pi * (0.1 + 0.8 * u)) + 0.0004)
            tube(gills, pts, rad, 6, start="pole", end="pole", shape=lambda i, ang: (0.45, 1.0),
                 frames=frames_up(pts, (0, 0, 1)))
        # Pélvicas: abas pequenas atrás do disco, dos lados da base da cauda
        pl = Path([(0.0, side((0.016, 0.17, -0.006))), (0.5, side((0.04, 0.2, -0.007))), (1.0, side((0.052, 0.245, -0.008)))])
        pt = Path([(0.0, side((0.006, 0.2, -0.006))), (0.5, side((0.018, 0.232, -0.007))), (1.0, side((0.052, 0.245, -0.008)))])
        foil(m.part("Pelvic", lambda co, p: (None, 1.0 if p["side"] < 0 else 0.0, 0.0, 0.0)), [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
             pl, pt, lambda s: mix(0.012, 0.004, s), lambda s: (0, 0, 1), m=3, root="fan", tip="pole")

    # Dorsal pequena e a cauda fina
    le_d = Path([(0.0, (0, 0.178, 0.006)), (0.5, (0, 0.196, 0.016)), (1.0, (0, 0.214, 0.026))])
    te_d = Path([(0.0, (0, 0.226, 0.002)), (0.5, (0, 0.222, 0.012)), (1.0, (0, 0.214, 0.026))])
    foil(m.part("Dorsal", lambda co, p: (None, 0.0, 0.0, 0.0)), [0.0, 0.25, 0.5, 0.75, 1.0], le_d, te_d,
         lambda s: mix(0.008, 0.002, s), lambda s: (1, 0, 0), m=3)
    pts = [Vector((0.0, 0.19 + 0.33 * u, 0.002 - 0.012 * u * u + 0.004 * math.sin(u * 5.0))) for u in (i / 17.0 for i in range(18))]
    rad = [mix(0.011, 0.0012, (i / 17.0) ** 0.7) for i in range(18)]
    tube(m.part("Tail", lambda co, p: (None, 0.0, 0.0, 0.0)), pts, rad, 6, start="fan", end="pole")
    return m.objects(axis=0)


# ---------------------------------------------------------------------------
# Tubarão (galha-preta): focinho cônico, cinco fendas, dorsal grande, cauda heterocerca
# ---------------------------------------------------------------------------
def shark():
    """Tubarão-galha-preta: focinho cônico e achatado, olhos, boca em meia-lua embaixo, cinco fendas
    das guelras (anéis com sulco e B), primeira dorsal triangular grande e a segunda pequena,
    peitorais em asa, pélvicas e anal, cauda heterocerca com o entalhe subterminal; o
    contra-sombreamento com a linha nítida (costura no anel), a faixa clara do flanco (A) e as
    pontas pretas das nadadeiras (B)."""
    m = Model("Shark", lambda co: smooth(-0.16, 0.5, co.y) ** 1.25)
    # Perfis em d (fração do comprimento total, desde a ponta do focinho; o tubo termina dentro da cauda)
    zc = Curve([(0, 0.008), (0.05, 0.004), (0.12, 0.0), (0.7, 0.0), (0.78, 0.006), (0.84, 0.017)])
    a = Curve([(0, 0), (0.004, 0.005), (0.012, 0.0095), (0.03, 0.0175), (0.06, 0.0305), (0.1, 0.0445), (0.16, 0.0585),
               (0.22, 0.068), (0.28, 0.0755), (0.34, 0.0805), (0.4, 0.0815), (0.48, 0.0765), (0.56, 0.064), (0.64, 0.048),
               (0.7, 0.036), (0.76, 0.026), (0.8, 0.019), (0.84, 0.0)])
    b = Curve([(0, 0), (0.004, 0.0035), (0.012, 0.0065), (0.03, 0.0125), (0.06, 0.0225), (0.1, 0.0345), (0.16, 0.0475),
               (0.22, 0.0575), (0.28, 0.0645), (0.34, 0.0695), (0.4, 0.0705), (0.48, 0.0655), (0.56, 0.0545), (0.64, 0.04),
               (0.7, 0.029), (0.76, 0.0205), (0.8, 0.0145), (0.84, 0.0)])
    w = Curve([(0, 0), (0.004, 0.0075), (0.012, 0.0135), (0.03, 0.0245), (0.06, 0.037), (0.1, 0.0485), (0.16, 0.0575),
               (0.22, 0.063), (0.28, 0.066), (0.34, 0.067), (0.4, 0.0655), (0.48, 0.061), (0.56, 0.0505), (0.64, 0.038),
               (0.7, 0.028), (0.76, 0.0205), (0.8, 0.0155), (0.84, 0.0)])
    body = Body(zc, a, b, w, nt=lambda d: 2.1, nb=lambda d: 2.4)
    # Linha do contra-sombreamento (ângulo a partir do dorso): abaixo do olho, por cima da peitoral
    cs = Curve([(0, 1.58), (0.07, 1.7), (0.2, 1.78), (0.32, 1.78), (0.5, 1.76), (0.7, 1.71), (0.84, 1.68)])
    seam = math.radians(1.2)
    slits = [0.205, 0.2165, 0.2275, 0.238, 0.2475]
    slit_h = [(1.08, 1.98), (1.07, 2.0), (1.08, 1.99), (1.12, 1.96), (1.18, 1.92)]

    def knots(d):
        return [(0.0, 7), (cs(d) - seam, 1), (cs(d) + seam, 5), (math.pi, 0)]

    def slit(d, th):
        """Índice da fenda da guelra no anel em d (ou -1) e o quanto o ângulo está dentro dela."""
        for k, ds in enumerate(slits):
            if abs(d - ds) < 1e-6:
                lo, hi = slit_h[k]
                t = min(th, TAU - th)
                return k, window(t, lo, hi, 0.12)
        return -1, 0.0

    def push(d, th):
        k, f = slit(d, th)
        return -0.0016 * f if k >= 0 else 0.0

    stations = [0.0, 0.003, 0.008, 0.015, 0.025, 0.037, 0.05, 0.062, 0.075, 0.09, 0.108, 0.126, 0.145, 0.164, 0.18, 0.193]
    stations += [0.199, 0.205, 0.211, 0.2165, 0.222, 0.2275, 0.233, 0.238, 0.243, 0.2475, 0.253]
    stations += [0.265, 0.28, 0.3, 0.33, 0.37, 0.41, 0.45, 0.49, 0.53, 0.57, 0.61, 0.65, 0.69, 0.72, 0.745, 0.765, 0.785, 0.8,
                 0.82, 0.84]

    def paint_body(co, p):
        d, th = p["d"], p["th"]
        t = min(th, TAU - th)
        g = 1.0 if t > cs(d) else 0.0
        k, f = slit(d, th)
        bb = f if k >= 0 else 0.0
        # Faixa clara do flanco (acima da pélvica, afinando para a frente): presa às duas colunas de
        # vértices logo acima da costura, para a borda de baixo ficar nítida e a de cima sem degraus
        band = 0.0
        if g < 0.5:
            edge = cs(d) - seam
            step = edge / 7.0
            if t > edge - 1e-6:
                band = window(d, 0.38, 0.62, 0.04)
            elif t > edge - step - 1e-6:
                band = window(d, 0.38, 0.62, 0.04) * ramp(0.42, 0.56, d)
        return None, g, bb, band

    body_part(m.part("Body", paint_body), body, stations, knots, push)

    # Olhos (pretos), pouco acima da linha, logo atrás do focinho
    eyes = m.part("Eyes", lambda co, p: (None, 0.0, 1.0, 0.0))
    for sgn in (1, -1):
        th = 1.2 if sgn > 0 else TAU - 1.2
        c = body.point(0.064, th)
        n = body.normal(0.064, th)
        dome(eyes, c - n * 0.0012, n, 0.0072, 0.004, nu=8, rings=(100, 60))

    # Boca: meia-lua embaixo do focinho
    mouth = m.part("Mouth", lambda co, p: (None, 1.0, 1.0, 0.0))
    pts, rad = [], []
    for i in range(11):
        u = i / 10.0
        ang = mix(-1.0, 1.0, u)                      # de um canto ao outro
        d = 0.056 + 0.028 * ang * ang
        th = math.pi + ang * 0.9
        p = body.point(d, th)
        pts.append(p - body.normal(d, th) * 0.0006)
        rad.append(0.0019 * (1.0 - 0.6 * abs(ang) ** 4))
    tube(mouth, pts, rad, 6, start="pole", end="pole")

    def top(d):
        return body.point(d, 0.0).z

    def bottom(d):
        return body.point(d, math.pi).z

    def fin_paint(tip0, tip1, g_under=False, margin=False):
        def paint(co, p):
            s, side = p["s"], p["side"]
            g = 1.0 if (g_under and side < 0) else 0.0
            bb = smooth(tip0, tip1, s)
            if margin:
                bb = max(bb, 0.7 * smooth(0.82, 0.95, p["c"]) * smooth(0.0, 0.25, min(s, 1.0 - s) * 4.0))
            return None, g, bb, 0.0
        return paint

    # Primeira dorsal: triangular, bordo de fuga côncavo e a ponta solta atrás
    le = Path([(0.0, (0, 0.3, top(0.3) - 0.012)), (0.12, (0, 0.307, top(0.307) + 0.006)), (0.5, (0, 0.338, top(0.33) + 0.052)),
               (0.85, (0, 0.366, top(0.36) + 0.092)), (1.0, (0, 0.384, top(0.37) + 0.106))])
    te = Path([(0.0, (0, 0.43, top(0.43) - 0.012)), (0.12, (0, 0.425, top(0.425) + 0.004)), (0.3, (0, 0.402, top(0.4) + 0.02)),
               (0.6, (0, 0.389, top(0.39) + 0.055)), (0.85, (0, 0.384, top(0.38) + 0.088)), (1.0, (0, 0.384, top(0.37) + 0.106))])
    ss = [0.0, 0.07, 0.14, 0.24, 0.36, 0.48, 0.6, 0.71, 0.8, 0.86, 0.92, 0.96, 1.0]
    foil(m.part("Dorsal", fin_paint(0.8, 0.86)), ss, le, te, lambda s: mix(0.024, 0.004, s ** 0.8), lambda s: (1, 0, 0), m=5)

    # Segunda dorsal e anal: pequenas, com a ponta solta comprida
    le = Path([(0.0, (0, 0.598, top(0.598) - 0.006)), (0.2, (0, 0.604, top(0.604) + 0.004)), (1.0, (0, 0.628, top(0.62) + 0.031))])
    te = Path([(0.0, (0, 0.668, top(0.668) - 0.006)), (0.15, (0, 0.668, top(0.668) + 0.0025)), (0.45, (0, 0.642, top(0.64) + 0.012)),
               (1.0, (0, 0.628, top(0.62) + 0.031))])
    ss = [0.0, 0.1, 0.2, 0.35, 0.5, 0.65, 0.8, 0.9, 1.0]
    foil(m.part("Dorsal2", fin_paint(0.62, 0.75)), ss, le, te, lambda s: mix(0.012, 0.003, s), lambda s: (1, 0, 0), m=4)
    le = Path([(0.0, (0, 0.612, bottom(0.612) + 0.006)), (0.2, (0, 0.618, bottom(0.618) - 0.004)), (1.0, (0, 0.642, bottom(0.636) - 0.03))])
    te = Path([(0.0, (0, 0.68, bottom(0.68) + 0.005)), (0.15, (0, 0.68, bottom(0.68) - 0.0025)), (0.45, (0, 0.655, bottom(0.652) - 0.012)),
               (1.0, (0, 0.642, bottom(0.636) - 0.03))])
    foil(m.part("Anal", fin_paint(0.62, 0.75)), ss, le, te, lambda s: mix(0.012, 0.003, s), lambda s: (1, 0, 0), m=4)

    # Cauda heterocerca (no plano vertical): de s = 0 (ponta do lobo de baixo) a 1 (ponta do lobo de
    # cima), passando pela raiz no pedúnculo; o entalhe subterminal e o lobo terminal perto da ponta
    le = Path([(0.0, (0, 0.885, -0.118)), (0.12, (0, 0.845, -0.075)), (0.24, (0, 0.81, -0.038)), (0.33, (0, 0.786, -0.012)),
               (0.4, (0, 0.781, 0.004)), (0.47, (0, 0.792, 0.024)), (0.6, (0, 0.842, 0.07)), (0.75, (0, 0.9, 0.121)),
               (0.9, (0, 0.955, 0.17)), (1.0, (0, 0.99, 0.2))])
    te = Path([(0.0, (0, 0.885, -0.118)), (0.12, (0, 0.877, -0.08)), (0.24, (0, 0.866, -0.042)), (0.33, (0, 0.862, -0.015)),
               (0.4, (0, 0.866, 0.005)), (0.47, (0, 0.876, 0.026)), (0.6, (0, 0.9, 0.064)), (0.75, (0, 0.925, 0.104)),
               (0.82, (0, 0.94, 0.127)), (0.86, (0, 0.946, 0.14)), (0.9, (0, 0.962, 0.143)), (1.0, (0, 0.99, 0.2))])
    ss = [0.0, 0.03, 0.07, 0.12, 0.18, 0.24, 0.29, 0.33, 0.37, 0.41, 0.45, 0.5, 0.56, 0.62, 0.68, 0.74, 0.79, 0.83, 0.86,
          0.89, 0.93, 0.965, 1.0]
    thick = Curve([(0.0, 0.003), (0.2, 0.01), (0.4, 0.021), (0.6, 0.011), (1.0, 0.003)])

    def caudal_paint(co, p):
        s = p["s"]
        bb = max(1.0 - smooth(0.1, 0.17, s), smooth(0.9, 0.95, s))
        bb = max(bb, 0.75 * smooth(0.8, 0.95, p["c"]) * smooth(0.33, 0.45, s))
        return None, 0.0, bb, 0.0
    foil(m.part("Caudal", caudal_paint), ss, le, te, thick, lambda s: (1, 0, 0), m=5, root="pole", tip="pole")

    # Peitorais (em asa, falcadas) e pélvicas, espelhadas
    for sgn in (1, -1):
        def side(v, sgn=sgn):
            return Vector((v[0] * sgn, v[1], v[2]))
        r0 = body.point(0.255, 2.2 if sgn > 0 else TAU - 2.2) + side((-0.012, 0, 0.004))
        r1 = body.point(0.335, 2.25 if sgn > 0 else TAU - 2.25) + side((-0.012, 0, 0.004))
        tip = r0 + side((0.125, 0.098, -0.064))
        le = Path([(0.0, r0), (0.1, r0 + side((0.016, 0.0, -0.007))), (0.45, r0 + side((0.066, 0.021, -0.034))),
                   (0.8, r0 + side((0.105, 0.063, -0.055))), (1.0, tip)])
        te = Path([(0.0, r1), (0.1, r1 + side((0.012, 0.006, -0.006))), (0.22, r1 + side((0.027, 0.004, -0.014))),
                   (0.5, r1 + side((0.064, 0.012, -0.035))), (0.8, tip + side((-0.03, -0.004, 0.016))), (1.0, tip)])
        nrm = side((0.45, 0.0, 1.0)).normalized()
        ss = [0.0, 0.07, 0.16, 0.28, 0.42, 0.56, 0.68, 0.78, 0.85, 0.91, 0.96, 1.0]
        foil(m.part("Pectoral", fin_paint(0.8, 0.87, g_under=True)), ss, le, te, lambda s: mix(0.016, 0.003, s ** 0.8),
             lambda s, nrm=nrm: nrm, m=5)
        r0 = body.point(0.5, 2.55 if sgn > 0 else TAU - 2.55) + side((-0.006, 0, 0.005))
        r1 = body.point(0.548, 2.6 if sgn > 0 else TAU - 2.6) + side((-0.006, 0, 0.005))
        tip = r0 + side((0.04, 0.05, -0.03))
        le = Path([(0.0, r0), (0.5, r0 + side((0.022, 0.018, -0.017))), (1.0, tip)])
        te = Path([(0.0, r1), (0.2, r1 + side((0.008, 0.008, -0.006))), (0.6, tip + side((-0.012, -0.004, 0.009))), (1.0, tip)])
        nrm = side((0.6, 0.0, 1.0)).normalized()
        ss = [0.0, 0.12, 0.25, 0.4, 0.55, 0.7, 0.83, 0.93, 1.0]
        foil(m.part("Pelvic", fin_paint(0.72, 0.84, g_under=True)), ss, le, te, lambda s: mix(0.01, 0.003, s),
             lambda s, nrm=nrm: nrm, m=4)
    return m.objects()


# ---------------------------------------------------------------------------
# Golfinho-nariz-de-garrafa
# ---------------------------------------------------------------------------
def dolphin():
    """Golfinho-nariz-de-garrafa: bico curto, vinco e melão, a linha da boca com o "sorriso" (sulco e
    B), olhos e o espiráculo, dorsal falcada, peitorais pequenas, pedúnculo com quilha e a cauda com
    o entalhe; o capote mais escuro no dorso (A) e o ventre claro (G), as duas bordas em costuras."""
    m = Model("Dolphin", lambda co: max(smooth(-0.06, 0.5, co.y) ** 1.3,
                                        0.3 * smooth(0.07, 0.17, abs(co.x)) * window(co.y, -0.36, -0.12, 0.06)))
    # Contorno de lado (d desde a ponta do bico): bico curto, vinco e melão, corpo, pedúnculo alto
    zc, a, b = profile(
        [(0, -0.007), (0.004, 0.001), (0.014, 0.0075), (0.03, 0.012), (0.045, 0.015), (0.054, 0.019), (0.063, 0.029),
         (0.075, 0.046), (0.09, 0.061), (0.115, 0.077), (0.15, 0.089), (0.21, 0.097), (0.3, 0.101), (0.38, 0.099),
         (0.46, 0.092), (0.54, 0.08), (0.62, 0.065), (0.7, 0.05), (0.76, 0.04), (0.82, 0.031), (0.86, 0.023),
         (0.885, 0.014), (0.905, 0.0)],
        [(0, -0.007), (0.004, -0.015), (0.014, -0.021), (0.03, -0.0255), (0.055, -0.0305), (0.075, -0.038), (0.1, -0.049),
         (0.13, -0.062), (0.17, -0.075), (0.22, -0.084), (0.3, -0.091), (0.38, -0.09), (0.46, -0.083), (0.54, -0.07),
         (0.62, -0.056), (0.7, -0.043), (0.76, -0.034), (0.82, -0.026), (0.86, -0.019), (0.885, -0.011), (0.905, 0.0)],
        [(0, -0.007), (0.015, -0.007), (0.06, -0.007), (0.1, -0.002), (0.16, 0.004), (0.3, 0.005), (0.7, 0.003),
         (0.905, 0.0)])
    w = Curve([(0, 0), (0.004, 0.0095), (0.014, 0.0135), (0.03, 0.0158), (0.055, 0.0185), (0.075, 0.026), (0.1, 0.039),
               (0.13, 0.054), (0.17, 0.067), (0.22, 0.077), (0.3, 0.085), (0.38, 0.084), (0.46, 0.075), (0.54, 0.061),
               (0.62, 0.045), (0.7, 0.03), (0.76, 0.021), (0.82, 0.0145), (0.86, 0.011), (0.885, 0.008), (0.905, 0.0)])
    # (pedúnculo achatado dos lados, com quilha em cima e embaixo)
    keel = Curve([(0, 2.0), (0.55, 2.0), (0.7, 1.55), (0.85, 1.3), (0.905, 1.3)])
    body = Body(zc, a, b, w, nt=keel, nb=keel)
    # Costuras: borda de baixo do capote e linha do ventre (no bico, a linha da boca)
    cape = Curve([(0, 0.62), (0.08, 0.5), (0.11, 0.42), (0.2, 0.68), (0.33, 0.86), (0.44, 1.05), (0.52, 1.1),
                  (0.6, 0.95), (0.7, 0.78), (0.8, 0.66), (0.9, 0.6)])
    belly = Curve([(0, 1.66), (0.05, 1.64), (0.085, 1.52), (0.1, 1.48), (0.112, 1.6), (0.14, 1.9), (0.2, 2.06),
                   (0.3, 2.0), (0.45, 1.98), (0.6, 2.08), (0.75, 2.3), (0.9, 2.4)])
    gape = 0.1                                                # canto da boca
    # (meia-largura da costura: mais larga no bico, onde o vértice do meio é o sulco escuro da boca)
    seam = Curve([(0, math.radians(4.0)), (gape - 0.01, math.radians(3.0)), (gape + 0.02, math.radians(1.3)), (1.0, math.radians(1.3))])

    def knots(d):
        return [(0.0, 4), (cape(d) - seam(1.0), 1), (cape(d) + seam(1.0), 3), (belly(d) - seam(d), 2), (belly(d) + seam(d), 5),
                (math.pi, 0)]

    def on_line(d, th):
        return abs(min(th, TAU - th) - belly(d)) < 1e-6

    def push(d, th):
        if on_line(d, th) and d < gape + 0.004:
            return -0.0018 * smooth(0.0, 0.01, d) * (1.0 - smooth(gape - 0.006, gape + 0.004, d))
        return 0.0

    stations = [0.0, 0.002, 0.006, 0.012, 0.02, 0.029, 0.038, 0.047, 0.055, 0.063, 0.071, 0.08, 0.089, 0.098, 0.107,
                0.117, 0.128, 0.142, 0.158, 0.176, 0.196, 0.218, 0.242, 0.27, 0.3, 0.335, 0.37, 0.405, 0.44, 0.475, 0.51,
                0.545, 0.58, 0.615, 0.65, 0.685, 0.72, 0.75, 0.78, 0.81, 0.835, 0.858, 0.875, 0.89, 0.905]

    def paint_body(co, p):
        d, th = p["d"], p["th"]
        t = min(th, TAU - th)
        g = 1.0 if t > belly(d) + 1e-6 else (0.5 if on_line(d, th) else 0.0)
        cap = 1.0 if t < cape(d) else 0.0
        cap *= smooth(0.085, 0.12, d) * (1.0 - smooth(0.8, 0.88, d))
        bb = 0.0
        if on_line(d, th) and d < gape + 0.004:
            bb = smooth(0.0, 0.008, d) * (1.0 - smooth(gape - 0.002, gape + 0.004, d))
        return None, g, bb, cap

    body_part(m.part("Body", paint_body), body, stations, knots, push)

    # Olhos logo atrás e acima do canto da boca, e o espiráculo (meia-lua) no alto da cabeça
    eyes = m.part("Eyes", lambda co, p: (None, 0.0, 1.0, 0.0))
    for sgn in (1, -1):
        th = 1.36 if sgn > 0 else TAU - 1.36
        c, n = body.point(0.112, th), body.normal(0.112, th)
        dome(eyes, c - n * 0.0012, n, 0.0062, 0.0032, nu=8, rings=(100, 60))
    hole = m.part("Blowhole", lambda co, p: (None, 0.0, 1.0, 0.0))
    pts, rad = [], []
    for i in range(9):
        u = (i / 8.0) * 2.0 - 1.0
        d = 0.148 - 0.006 * (1.0 - u * u)
        pts.append(body.point(d, u * 0.42) - body.normal(d, u * 0.42) * 0.0005)
        rad.append(0.0022 * (1.0 - 0.5 * u * u))
    tube(hole, pts, rad, 6, start="pole", end="pole")

    def top(d):
        return body.point(d, 0.0).z

    def fin_paint(dark):
        def paint(co, p):
            return None, 0.0, 0.0, dark
        return paint

    # Dorsal falcada: bordo de ataque convexo, ponta para trás, bordo de fuga côncavo
    tip = Vector((0, 0.545, top(0.5) + 0.098))
    le = Path([(0.0, (0, 0.415, top(0.415) - 0.012)), (0.15, (0, 0.43, top(0.43) + 0.006)), (0.45, (0, 0.462, top(0.46) + 0.04)),
               (0.75, (0, 0.502, top(0.49) + 0.075)), (1.0, tip)])
    te = Path([(0.0, (0, 0.575, top(0.575) - 0.012)), (0.15, (0, 0.567, top(0.567) + 0.004)), (0.4, (0, 0.545, top(0.545) + 0.026)),
               (0.7, (0, 0.536, top(0.53) + 0.06)), (0.9, (0, 0.539, top(0.52) + 0.086)), (1.0, tip)])
    ss = [0.0, 0.08, 0.17, 0.28, 0.4, 0.52, 0.64, 0.75, 0.84, 0.91, 0.96, 1.0]
    foil(m.part("Dorsal", fin_paint(1.0)), ss, le, te, lambda s: mix(0.022, 0.004, s ** 0.8), lambda s: (1, 0, 0), m=4)

    # Cauda: da ponta esquerda (s = x = -0,122) à direita, com o entalhe no meio do bordo de fuga
    xs = [-0.122, -0.11, -0.09, -0.065, -0.04, -0.018, -0.006, 0.0, 0.006, 0.018, 0.04, 0.065, 0.09, 0.11, 0.122]
    le_y = Curve([(0.0, 0.868), (0.02, 0.871), (0.04, 0.88), (0.065, 0.897), (0.09, 0.92), (0.11, 0.952), (0.122, 0.99)])
    te_y = Curve([(0.0, 0.948), (0.006, 0.955), (0.018, 0.96), (0.04, 0.962), (0.065, 0.966), (0.09, 0.973), (0.11, 0.982),
                  (0.122, 0.99)])
    le = Path([(x, (x, le_y(abs(x)), 0.0)) for x in xs])
    te = Path([(x, (x, te_y(abs(x)), 0.0)) for x in xs])
    ss = [-0.122, -0.119, -0.113, -0.104, -0.092, -0.078, -0.062, -0.046, -0.03, -0.016, -0.006, 0.0, 0.006, 0.016, 0.03,
          0.046, 0.062, 0.078, 0.092, 0.104, 0.113, 0.119, 0.122]
    foil(m.part("Flukes", lambda co, p: (None, 0.35 if p["side"] < 0 else 0.0, 0.0, 0.0 if p["side"] < 0 else 0.8)), ss, le, te,
         lambda s: mix(0.02, 0.003, smooth(0.0, 0.122, abs(s)) ** 0.7), lambda s: (0, 0, 1), m=4, root="pole", tip="pole")

    # Peitorais: pequenas, pontudas, para baixo e para trás
    for sgn in (1, -1):
        def side(v, sgn=sgn):
            return Vector((v[0] * sgn, v[1], v[2]))
        th0 = 2.2 if sgn > 0 else TAU - 2.2
        r0 = body.point(0.192, th0) + side((-0.012, 0, 0.004))
        r1 = body.point(0.245, th0) + side((-0.012, 0, 0.004))
        tip = r0 + side((0.092, 0.098, -0.06))
        le = Path([(0.0, r0), (0.15, r0 + side((0.016, 0.004, -0.01))), (0.55, r0 + side((0.056, 0.036, -0.036))),
                   (0.85, r0 + side((0.083, 0.076, -0.054))), (1.0, tip)])
        te = Path([(0.0, r1), (0.15, r1 + side((0.012, 0.004, -0.008))), (0.5, r1 + side((0.048, 0.03, -0.03))),
                   (0.85, tip + side((-0.014, -0.006, 0.008))), (1.0, tip)])
        nrm = side((0.55, 0.0, 1.0)).normalized()
        ss = [0.0, 0.1, 0.22, 0.36, 0.5, 0.64, 0.77, 0.87, 0.95, 1.0]
        foil(m.part("Flipper", fin_paint(0.6)), ss, le, te, lambda s: mix(0.017, 0.004, s), lambda s, nrm=nrm: nrm, m=4)
    return m.objects()


# ---------------------------------------------------------------------------
# Tartaruga-verde
# ---------------------------------------------------------------------------
def turtle():
    """Tartaruga-verde: carapaça em domo com as placas (5 vertebrais, 4 pares de costais, a nucal, as
    marginais e as supracaudais) em relevo leve e as bordas escuras, plastrão claro, cabeça curta com
    o bico e as placas, nadadeiras da frente compridas como asas e as de trás curtas."""
    m = Model("Turtle", lambda co: 0.0)

    # Carapaça (destaque A) com as costuras escuras; por baixo, o plastrão claro
    half = [(0.0, -0.255), (0.06, -0.262), (0.13, -0.247), (0.2, -0.205), (0.258, -0.14), (0.297, -0.058), (0.316, 0.03),
            (0.312, 0.12), (0.29, 0.21), (0.252, 0.29), (0.195, 0.36), (0.125, 0.415), (0.055, 0.45), (0.0, 0.462)]
    marg = [0.035, 0.11, 0.19, 0.27, 0.35, 0.43, 0.51, 0.59, 0.67, 0.75, 0.84, 0.93]   # costuras das marginais
    samples = sorted({0.0, 1.0, 0.07, 0.885} | set(marg) | {round((a + b) * 0.5, 4) for a, b in zip([0.0] + marg, marg + [1.0])})
    nodes = dict(S1=(0.108, -0.085), S2=(0.124, -0.01), S3=(0.11, 0.06), S4=(0.122, 0.13), S5=(0.106, 0.2), S6=(0.1, 0.262),
                 S7=(0.082, 0.322), M2=(0.0, -0.09), M3=(0.0, 0.055), M4=(0.0, 0.195), M5=(0.0, 0.32))
    faces = [
        # Vertebrais
        [("in", -0.07, 0.07), ("e", "I:0.07", "S1"), ("e", "S1", "M2"), ("e", "M2", "S1L"), ("e", "S1L", "I:-0.07")],
        [("e", "S1", "S2"), ("e", "S2", "S3"), ("e", "S3", "M3"), ("e", "M3", "S3L"), ("e", "S3L", "S2L"), ("e", "S2L", "S1L"),
         ("e", "S1L", "M2"), ("e", "M2", "S1")],
        [("e", "S3", "S4"), ("e", "S4", "S5"), ("e", "S5", "M4"), ("e", "M4", "S5L"), ("e", "S5L", "S4L"), ("e", "S4L", "S3L"),
         ("e", "S3L", "M3"), ("e", "M3", "S3")],
        [("e", "S5", "S6"), ("e", "S6", "S7"), ("e", "S7", "M5"), ("e", "M5", "S7L"), ("e", "S7L", "S6L"), ("e", "S6L", "S5L"),
         ("e", "S5L", "M4"), ("e", "M4", "S5")],
        [("in", 0.885, -0.885), ("e", "I:-0.885", "S7L"), ("e", "S7L", "M5"), ("e", "M5", "S7"), ("e", "S7", "I:0.885")],
    ]
    # Costais: 4 de cada lado, entre a coluna das vertebrais e as marginais
    costals = [(0.07, 0.43, ["S2", "S1"]), (0.43, 0.59, ["S4", "S3", "S2"]), (0.59, 0.75, ["S6", "S5", "S4"]),
               (0.75, 0.885, ["S7", "S6"])]
    for sg, L in ((1, ""), (-1, "L")):
        for ta, tb, chain_ in costals:
            names = ["I:%r" % (tb * sg)] + [n + L for n in chain_] + ["I:%r" % (ta * sg)]
            face = [("in", ta, tb) if sg > 0 else ("in-", -ta, -tb)]
            face += [("e", a, b) for a, b in zip(names, names[1:])]
            faces.append(face)
    # Marginais: a nucal no meio da frente, 11 de cada lado e as duas supracaudais atrás
    cuts = sorted({-t for t in marg} | set(marg))
    for a, b in zip(cuts, cuts[1:]):
        faces.append([("out", a, b), ("e", "O:%r" % b, "I:%r" % b), ("in-", b, a), ("e", "I:%r" % a, "O:%r" % a)])
    for a, b in ((0.93, 1.0), (-1.0, -0.93)):
        faces.append([("out", a, b), ("e", "O:%r" % b, "I:%r" % b), ("in-", b, a), ("e", "I:%r" % a, "O:%r" % a)])

    def paint_shell(co, p):
        kind, sid = p["kind"], p["sid"]
        if kind in ("rim", "under"):
            return 0.0, 1.0, 0.0, 0.0
        bb = dict(seam=0.75, edge=0.3, ring1=0.12, ring2=0.0, center=0.04)[kind]
        if sid >= 0 and kind in ("ring2", "center"):
            bb += 0.12 * hash01(sid, 3.0)                       # placas um pouco diferentes
        return 0.0, 0.0, bb, 1.0
    shell(m.part("Shell", paint_shell), half, samples, nodes, faces,
                 Curve([(0.0, 0.052), (0.15, 0.046), (0.5, 0.044), (0.8, 0.05), (1.0, 0.056)]), (0.0, 0.1), 0.125,
                 [(0.965, -0.02), (0.8, -0.047), (0.45, -0.06)])

    # Cabeça e pescoço: focinho curto e redondo, o bico com a linha da boca, olhos grandes, pescoço grosso
    # e a garganta clara. As placas de cima (pré-frontais, frontal, supraoculares, parietais e
    # pós-oculares) têm as bordas claras (G) em costuras finas: trincas de vértices em que só o do meio
    # é claro, na linha do meio, nas colunas de 0,62 rad e em três anéis.
    zc, a, b = profile(
        [(0, -0.024), (0.004, -0.006), (0.014, 0.008), (0.03, 0.017), (0.06, 0.024), (0.09, 0.027), (0.115, 0.025),
         (0.14, 0.02), (0.17, 0.018), (0.24, 0.02)],
        [(0, -0.024), (0.004, -0.042), (0.014, -0.054), (0.03, -0.06), (0.06, -0.063), (0.09, -0.063), (0.12, -0.063),
         (0.145, -0.064), (0.19, -0.066), (0.24, -0.062)],
        [(0, -0.024), (0.02, -0.024), (0.08, -0.02), (0.16, -0.022), (0.24, -0.02)])
    w = Curve([(0, 0.0), (0.004, 0.017), (0.014, 0.028), (0.03, 0.036), (0.06, 0.044), (0.09, 0.048), (0.115, 0.048),
               (0.14, 0.046), (0.19, 0.048), (0.24, 0.05)])
    head = Body(zc, a, b, w, nt=lambda d: 2.3, nb=lambda d: 2.0, y0=-0.44)
    jaw = Curve([(0, 1.9), (0.02, 1.78), (0.045, 1.72), (0.07, 1.84), (0.09, 2.0), (0.24, 2.0)])
    gape = 0.072
    hseam, pseam, col = math.radians(3.0), 0.06, 0.62
    rings_ = (0.048, 0.088, 0.118)                           # anéis das bordas das placas

    def hknots(d):
        return [(0.0, 1), (pseam, 2), (col - pseam, 1), (col, 1), (col + pseam, 2), (jaw(d) - hseam, 2), (jaw(d) + hseam, 4),
                (math.pi, 0)]

    hst = [0.0, 0.004, 0.011, 0.02, 0.03, 0.04, 0.045, 0.048, 0.051, 0.06, 0.07, 0.08, 0.085, 0.088, 0.091, 0.1, 0.11, 0.115,
           0.118, 0.121, 0.135, 0.165, 0.24]

    def paint_head(co, p):
        d, th = p["d"], p["th"]
        t = min(th, TAU - th)
        on = abs(t - jaw(d)) < 1e-6
        g = 1.0 if t > jaw(d) + 1e-6 else 0.0
        # (bico: as bainhas das mandíbulas mais claras)
        g = max(g, 0.55 * (1.0 - smooth(0.03, 0.045, d)) * smooth(jaw(d) - 0.7, jaw(d) - 0.3, t))
        bb = (1.0 - smooth(gape - 0.006, gape + 0.004, d)) * smooth(0.0, 0.006, d) if on else 0.0
        mid_line = t < 1e-6 and 0.014 < d < rings_[0] + 1e-6
        column = abs(t - col) < 1e-6 and 0.02 < d < rings_[2] + 1e-6
        ring = ((abs(d - rings_[0]) < 1e-6 and t < col + 1e-6) or (abs(d - rings_[1]) < 1e-6 and t < 1.28)
                or (abs(d - rings_[2]) < 1e-6 and t < 1.0))
        if mid_line or column or ring:
            g = 0.9
        return 0.0, g, bb, 0.0
    body_part(m.part("Head", paint_head), head, hst, hknots,
              push=lambda d, th: -0.0012 * (1.0 - smooth(gape - 0.01, gape, d)) if abs(min(th, TAU - th) - jaw(d)) < 1e-6 else 0.0)
    eyes = m.part("Eyes", lambda co, p: (0.0, 0.0, 1.0, 0.0))
    for sg in (1, -1):
        th = 1.12 if sg > 0 else TAU - 1.12
        c, n = head.point(0.052, th), head.normal(0.052, th)
        dome(eyes, c - n * 0.004, n, 0.0115, 0.0068, nu=10, rings=(100, 64, 34))

    # Nadadeiras da frente: compridas e finas como asas, com a garra no bordo de ataque; as de trás
    # curtas e redondas. Por cima a pele (bordas claras), por baixo claras.
    def flipper_paint(scale):
        def paint(co, p):
            s, side = p["s"], p["side"]
            g = 1.0 if side < 0 else (0.75 if side == 0 else 0.0)
            return scale * smooth(0.16, 1.0, s) ** 0.85, g * smooth(0.05, 0.15, s), 0.0, 0.0
        return paint
    for sg in (1, -1):
        def side(v, sg=sg):
            return Vector((v[0] * sg, v[1], v[2]))
        root = side((0.15, -0.165, -0.03))
        U = side((1.0, 0.2, -0.13)).normalized()
        C = side((-0.2, 1.0, 0.0)).normalized()
        C = (C - U * U.dot(C)).normalized()
        N = U.cross(C)
        if N.z < 0:
            N = -N
        L = 0.5
        lo = Curve([(0, -0.045), (0.15, -0.066), (0.32, -0.074), (0.5, -0.064), (0.7, -0.044), (0.86, -0.02), (1.0, 0.03)])
        tr = Curve([(0, 0.052), (0.15, 0.064), (0.32, 0.066), (0.5, 0.058), (0.7, 0.049), (0.86, 0.04), (1.0, 0.03)])
        us = [0.0, 0.08, 0.17, 0.27, 0.37, 0.47, 0.57, 0.67, 0.76, 0.84, 0.91, 0.96, 1.0]

        def at(u, off, U=U, C=C, N=N, root=root, L=L):
            return root + U * (u * L) + C * off + N * (0.012 * u - 0.05 * u * u)
        foil(m.part("Flipper", flipper_paint(1.0)), us, Path([(u, at(u, lo(u))) for u in us]), Path([(u, at(u, tr(u))) for u in us]),
             lambda u: mix(0.036, 0.006, u ** 0.8), lambda s, N=N: N, m=4)
        # Garra no bordo de ataque
        cl = at(0.36, lo(0.36) - 0.004)
        dome(m.part("Claw", lambda co, p: (smooth(0.16, 1.0, 0.36) ** 0.85, 0.0, 0.8, 0.0)), cl, (C * -1.0 + U * 0.3).normalized(), 0.006, 0.012, nu=6,
             rings=(100, 50))
        # De trás: remo curto e redondo, para trás e para fora
        root = side((0.1, 0.355, -0.045))
        U = side((0.62, 0.78, -0.06)).normalized()
        C = side((-0.78, 0.62, 0.0)).normalized()
        C = (C - U * U.dot(C)).normalized()
        N = U.cross(C)
        if N.z < 0:
            N = -N
        L = 0.17
        lo = Curve([(0, -0.035), (0.4, -0.05), (0.75, -0.045), (0.92, -0.025), (1.0, 0.0)])
        tr = Curve([(0, 0.035), (0.4, 0.042), (0.75, 0.035), (0.92, 0.02), (1.0, 0.0)])
        us = [0.0, 0.15, 0.3, 0.45, 0.6, 0.73, 0.84, 0.93, 1.0]

        def at2(u, off, U=U, C=C, N=N, root=root, L=L):
            return root + U * (u * L) + C * off + N * (-0.012 * u * u)
        foil(m.part("RearFlipper", flipper_paint(0.65)), us, Path([(u, at2(u, lo(u))) for u in us]),
             Path([(u, at2(u, tr(u))) for u in us]), lambda u: mix(0.03, 0.007, u), lambda s, N=N: N, m=4)

    # Cauda curta
    pts = [Vector((0.0, 0.38 + 0.11 * u, -0.042 - 0.006 * u)) for u in (i / 5.0 for i in range(6))]
    tube(m.part("Tail", lambda co, p: (0.2 * p["u"], 0.5, 0.0, 0.0)), pts, [0.024, 0.021, 0.017, 0.012, 0.007, 0.002], 8,
         start="fan", end="pole")
    return m.objects()


# ---------------------------------------------------------------------------
# Polvo-gigante na coluna
# ---------------------------------------------------------------------------
def octopus():
    """Polvo-gigante enroscado no alto da coluna, sem escalar nem centrar: a coluna é vertical em
    x = y = 0, com raio ~0,1 no fuste, o capitel até z ~0,09 e o ábaco quadrado (meia-largura 0,17)
    com o topo em z = 0,16, como no jogo (origem 2 m abaixo do topo, 12 m por unidade). O corpo (cabeça e manto rugoso, inclinado para trás) apoiado no topo, olhos
    salientes com a pupila em barra, o sifão, oito braços com as ventosas em duas fileiras na face de
    baixo e a membrana entre as bases; três braços descem enrolando na coluna (hélices paralelas) e os
    outros cinco se espalham no ar com as pontas enroladas. Frente (-Y) para a pista."""
    m = Model("Octopus", lambda co: 0.0)
    SHAFT, PITCH = 0.1, 0.42                                  # raio do fuste e queda por volta da hélice

    def cyl(r, deg, z):
        a = math.radians(deg)
        return Vector((r * math.cos(a), r * math.sin(a), z))

    crown = [(0.035, 0.0, 0.262), (0.12, 0.0, 0.232), (0.2, 0.0, 0.2)]
    # Braços: ângulo da base, tipo, pontos (r, desvio do ângulo, z) depois da coroa, e o enrolar da
    # ponta (raio inicial, voltas, eixo: "up" = enrola de lado, "side" = enrola para cima, "down" =
    # enrola para baixo, "out" = sobe e enrola para fora) ou a hélice na coluna (voltas). Os dois da
    # frente esticam para a pista, dois dos lados se erguem emoldurando a cabeça.
    arms = [
        (-67.5, "free", [(0.29, 6, 0.17), (0.4, 14, 0.11), (0.52, 19, 0.08), (0.62, 20, 0.1), (0.68, 17, 0.15)], (0.05, 1.3, "side")),
        (-112.5, "free", [(0.29, -6, 0.16), (0.38, -14, 0.07), (0.48, -19, 0.0), (0.57, -20, -0.03), (0.63, -17, -0.01)],
         (0.05, 1.25, "side")),
        (22.5, "free", [(0.3, -3, 0.26), (0.37, -6, 0.38), (0.41, -9, 0.5), (0.41, -12, 0.61)], (0.05, 1.3, "out")),
        (67.5, "free", [(0.28, -8, 0.15), (0.38, -16, 0.11), (0.48, -22, 0.11), (0.56, -26, 0.15)], (0.05, 1.2, "up")),
        (157.5, "free", [(0.3, 3, 0.25), (0.37, 6, 0.36), (0.41, 9, 0.47), (0.41, 12, 0.57)], (0.05, 1.25, "out")),
        (-22.5, "wrap", None, 1.0),
        (112.5, "wrap", None, 0.82),
        (-157.5, "wrap", None, 0.7),
    ]
    drape = [(0.255, -2, 0.165), (0.272, -5, 0.115), (0.24, -9, 0.062), (0.18, -14, 0.022)]
    centers = {}

    def radius(s, L):
        return 0.0035 + 0.042 * max(1.0 - s / L, 0.0) ** 0.85 + 0.006 * (1.0 - smooth(0.0, 0.12, s))

    arm_data = []
    for k, (deg, kind, ctrl, extra) in enumerate(arms):
        pts = [cyl(r, deg + da, z) for r, da, z in crown]
        if kind == "free":
            pts += [cyl(r, deg + da, z) for r, da, z in ctrl]
            dense = catmull(pts, 14)
            # Ponta enrolada: espiral que encolhe, continuando a direção do fim do braço
            end, prev = dense[-1], dense[-3]
            t = (end - prev).normalized()
            r0, turns, how = extra
            if how == "up":
                axis = Vector((0, 0, 1))
            elif how == "out":
                radial = Vector((end.x, end.y, 0.0)).normalized()
                axis = Vector((0, 0, 1)).cross(radial) * -1.0
                axis = (axis - t * t.dot(axis)).normalized()
            else:
                axis = t.cross(Vector((0, 0, 1))).normalized() * (1.0 if how == "side" else -1.0)
            nrm = axis.cross(t).normalized()                 # para o centro da espiral
            c = end + nrm * r0
            b = math.log(4.0) / (turns * TAU)
            spiral = []
            for i in range(1, int(turns * 36) + 1):
                th = i / 36.0 * TAU
                rr = r0 * math.exp(-b * th)
                spiral.append(c + (-nrm * math.cos(th) + t * math.sin(th)) * rr)
            centers[k] = (how, sum((b - a).length for a, b in zip(dense, dense[1:])))
            dense += spiral
        else:
            pts += [cyl(r, deg + da, z) for r, da, z in drape]
            # Hélice descendo na coluna (todas no mesmo sentido e passo: não se cruzam)
            turns = extra
            a0 = deg - 22.0
            n = int(turns * 48)
            for i in range(n + 1):
                f = i / 48.0
                z = -0.012 - PITCH * f
                pts.append(cyl(SHAFT - 0.015 * z + 0.006 + 0.03 * (1.0 - f / turns) ** 0.85, a0 - 360.0 * f, z))
            dense = catmull(pts[:len(crown) + len(drape)] + pts[len(crown) + len(drape)::4] + [pts[-1]], 10)
        arm_data.append((deg, kind, dense))

    # Reamostra cada braço com o passo proporcional ao raio (quads quase quadrados) e monta os tubos
    nseg = 12
    rails = []
    for k, (deg, kind, dense) in enumerate(arm_data):
        cum = [0.0]
        for a, b in zip(dense, dense[1:]):
            cum.append(cum[-1] + (b - a).length)
        L = cum[-1]
        pts, ss = resample(dense, lambda s, L=L: clamp(radius(s, L) * 1.15, 0.0065, 0.03))
        rad = [radius(s, L) for s in ss]
        # Lado oral (das ventosas): para baixo na coroa e nos braços esticados, para dentro nos erguidos,
        # para o eixo da coluna nos que enrolam; na ponta enrolada o referencial só é levado adiante
        # (sem torcer), e as ventosas ficam do lado de fora da espiral
        how, reach = centers.get(k, ("wrap", L))
        orals = []
        prev = None
        for i, (p, s) in enumerate(zip(pts, ss)):
            tan = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            if prev is not None and s > reach:
                o = prev - tan * tan.dot(prev)
            else:
                target = Vector((0, 0, -1))
                inward = Vector((-p.x, -p.y, 0.0)).normalized()
                if kind == "wrap":
                    target = target.lerp(inward, smooth(0.16, 0.32, s))
                elif how == "out":
                    target = target.lerp(inward, smooth(0.12, 0.3, s))
                o = target - tan * tan.dot(target)
                if o.length < 0.25 and prev is not None:
                    o = prev - tan * tan.dot(prev)
            o.normalize()
            orals.append(o)
            prev = o
        for _ in range(4):
            sm = [orals[0]] + [(orals[i - 1] + orals[i] * 2 + orals[i + 1]) for i in range(1, len(orals) - 1)] + [orals[-1]]
            orals = sm
        frames = []
        for i, o in enumerate(orals):
            tan = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            o = (o - tan * tan.dot(o)).normalized()
            frames.append((o, tan.cross(o).normalized()))
        sfrac = [s / L for s in ss]

        def sucker(i, j, sfrac=sfrac):
            """Ventosas: duas fileiras desencontradas na face oral (j = 1 e nseg - 1), depois da membrana."""
            return sfrac[i] > 0.12 and ((j == 1 and i % 2 == 0) or (j == nseg - 1 and i % 2 == 1))

        def shape(i, ang, sucker=sucker):
            j = round(ang / TAU * nseg) % nseg
            c = math.cos(ang)
            f = (0.78 if c > 0 else 0.96, 1.0)
            if sucker(i, j):
                return (f[0] * 1.2, f[1] * 1.2)
            return f

        def paint(co, p, kind=kind, sfrac=sfrac, sucker=sucker):
            i, j, ang = p["i"], p.get("j", -1), p["ang"]
            sf = sfrac[min(i, len(sfrac) - 1)]
            r = smooth(0.26, 1.0, sf) ** 1.2 if kind == "free" else 0.0
            if j is None or j < 0:
                return r, 0.0, 0.0, 0.0
            g = 0.85 * smooth(0.15, 0.55, math.cos(ang))
            acc = 1.0 if sucker(i, j) else 0.0
            bb = 0.22 * smooth(0.45, 0.75, noise3(co, 14.0)) * (1.0 - g)
            return r, g, bb, acc
        tube(m.part("Arm", paint), pts, rad, nseg, start="fan", end="pole", shape=shape, frames=frames)
        rails.append((deg, pts, ss))

    # Membrana entre as bases dos braços vizinhos (a borda livre recua para o meio)
    rails.sort(key=lambda r: r[0])

    def rail_at(rail, s):
        _, pts, ss = rail
        k = min(bisect.bisect_right(ss, s), len(ss) - 1)
        k = max(k, 1)
        t = (s - ss[k - 1]) / max(ss[k] - ss[k - 1], 1e-9)
        return pts[k - 1].lerp(pts[k], clamp(t))
    web_len = 0.2
    for k in range(len(rails)):
        ra, rb = rails[k], rails[(k + 1) % len(rails)]

        def le(u, ra=ra):
            return rail_at(ra, u * web_len)

        def te(u, rb=rb):
            return rail_at(rb, u * web_len)

        def bow(u, c, le=le, te=te):
            mid = (le(u) + te(u)) * 0.5
            inward = Vector((-mid.x, -mid.y, 0.0))
            inward = inward.normalized() if inward.length > 1e-6 else Vector()
            return (inward * 0.07 + Vector((0, 0, -0.008))) * (math.sin(math.pi * c) * u ** 1.6)

        def nrm(u, le=le, te=te):
            n = (te(u) - le(u)).cross(le(min(u + 0.05, 1.0)) + te(min(u + 0.05, 1.0)) - le(u) - te(u))
            n = n.normalized() if n.length > 1e-9 else Vector((0, 0, 1))
            return n if n.z > 0 else -n

        def web_paint(co, p):
            return 0.0, (0.7 if p["side"] < 0 else 0.0), 0.12 * noise3(co, 14.0), 0.0
        foil(m.part("Web", web_paint), [0.0, 0.18, 0.36, 0.54, 0.72, 0.88, 1.0], le, te, lambda u: mix(0.03, 0.009, u), nrm, m=3,
             root="fan", tip="fan", bow=bow, shape=lambda c: 1.0 if 0.0 < c < 1.0 else 0.0)

    # Corpo: da coroa (embaixo) pela cabeça até a ponta do manto, inclinado para trás, com rugas
    spine = catmull([(0, 0.0, 0.215), (0, -0.006, 0.25), (0, -0.01, 0.295), (0, -0.004, 0.34), (0, 0.025, 0.38),
                     (0, 0.075, 0.44), (0, 0.13, 0.505), (0, 0.18, 0.575), (0, 0.215, 0.63), (0, 0.232, 0.66)], 8)
    spine, sp_s = resample(spine, lambda s: 0.018)
    sp_s = [s / sp_s[-1] for s in sp_s]                    # (fração do comprimento)
    prof = Curve([(0.0, 0.0), (0.023, 0.07), (0.076, 0.105), (0.17, 0.118), (0.27, 0.112), (0.36, 0.098), (0.44, 0.104),
                  (0.57, 0.14), (0.7, 0.152), (0.82, 0.14), (0.91, 0.105), (0.97, 0.06), (1.0, 0.0)])
    brad = [prof(s) for s in sp_s]
    bframes = []
    for i, p in enumerate(spine):
        tan = (spine[min(i + 1, len(spine) - 1)] - spine[max(i - 1, 0)]).normalized()
        fwd = (Vector((0, -1, 0)) - tan * tan.dot(Vector((0, -1, 0)))).normalized()
        bframes.append((fwd, tan.cross(fwd).normalized()))

    def wrinkle(i, ang):
        s = sp_s[i]
        mantle = window(s, 0.5, 0.9, 0.07)
        folds = 0.045 * math.sin(ang * 7.0 + s * 5.0) * mantle
        ridges = 0.035 * math.sin(s * 32.0) * mantle * (0.5 + 0.5 * math.cos(ang))
        return 1.0 + folds + ridges

    def body_paint(co, p):
        s = sp_s[min(p["i"], len(sp_s) - 1)]
        under = 1.0 - smooth(0.04, 0.12, s)
        groove = 0.0
        if p.get("j", -1) is not None and p.get("j", -1) >= 0:
            groove = 0.35 * max(0.0, -math.sin(p["ang"] * 7.0 + s * 5.0)) * window(s, 0.5, 0.9, 0.07)
        bb = max(groove, 0.25 * smooth(0.45, 0.75, noise3(co, 11.0)))
        return 0.0, 0.7 * under, bb, 0.0
    tube(m.part("Body", body_paint), spine, brad, 32, start="pole", end="pole", shape=wrinkle, frames=bframes)

    def body_point(s, ang):
        k = min(bisect.bisect_right(sp_s, s), len(sp_s) - 1)
        nn, bb = bframes[k]
        d = nn * math.cos(ang) + bb * math.sin(ang)
        return spine[k] + d * prof(s), d

    # Olhos salientes (calombo da pálpebra, o globo com a íris clara e a pupila em barra)
    for sg in (1, -1):
        c, n = body_point(0.26, sg * math.radians(60.0))
        look = (n + Vector((0, -0.4, 0.3))).normalized()
        dome(m.part("Lid", lambda co, p: (0.0, 0.0, 0.15, 0.0)), c - n * 0.014, n, 0.06, 0.036, nu=12, rings=(100, 66, 36))
        center = c + n * 0.02
        up = (Vector((0, 0, 1)) - look * look.z).normalized()
        side = look.cross(up)

        def eye_paint(co, p, center=center, look=look, up=up, side=side):
            d = (co - center).normalized()
            if d.dot(look) < 0.55:
                return 0.0, 0.0, 0.3, 0.0
            pupil = abs(d.dot(up)) < 0.14 and abs(d.dot(side)) < 0.42
            return 0.0, 1.0, (1.0 if pupil else 0.0), 0.0
        r = 0.04
        ellipsoid(m.part("Eye", eye_paint), center, (side * r, up * r, look * r), nu=14, nv=10)

    # Sifão: tubo curto saindo entre a cabeça e o manto, do lado direito do bicho
    c, n = body_point(0.33, math.radians(-92.0))
    d = (n + Vector((0, -0.7, -0.45))).normalized()
    pts = [c - n * 0.03 + d * (0.11 * i / 5.0) for i in range(6)]
    tube(m.part("Siphon", lambda co, p: (0.0, 0.0, 1.0 if p.get("j", -1) is None or p.get("j", -1) < 0 else 0.1, 0.0)),
         pts, [0.034, 0.034, 0.032, 0.029, 0.027, 0.028], 10, start="fan", end="fan")
    return m.objects(axis=None)


# nome: construtor, metros por unidade, triângulos, pintura final da cor de vértice (antes de escalar)
MODELS = {
    "octopus": dict(build=octopus, size=5.0, tris=14000, paint=finish(reach=0.05)),
    "whale": dict(build=whale, size=17.0, tris=9000, paint=finish(reach=0.05)),
    "manta": dict(build=manta, size=7.0, tris=4500, paint=finish(reach=0.04)),
    "shark": dict(build=shark, size=4.5, tris=4500, paint=finish(reach=0.05)),
    "turtle": dict(build=turtle, size=1.7, tris=4500, paint=finish(reach=0.05)),
    "dolphin": dict(build=dolphin, size=2.6, tris=4000, paint=finish(reach=0.05)),
}
