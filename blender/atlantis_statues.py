"""Estátuas da Atlantis Abyss (rosto das cachoeiras, Poseidon em pé e sentado, busto da deusa), em
unidades da peça (base em z = 0, frente para -Y; a direita das figuras fica em -X).

Cada estátua é esculpida como um campo de distância (SDF, em numpy): elipsoides, cones arredondados,
caixas, toros e tubos ao longo de curvas, unidos com filete (união suave) e com cavidades subtraídas
(órbitas, boca, narinas, sulcos). Mechas de barba e cabelo, dobras de pano e a musculatura do tronco
são relevo somado ao campo (cristas arredondadas com sulco em V); os cachos são botões com sulco em
espiral. O campo é avaliado só nos blocos perto da superfície (árvore de caixas) e vira malha pelo
OpenVDB do Blender; a malha é consertada onde a superfície ficou mais fina que a grade, reduzida
(Decimate, com mais triângulos no rosto e nas mãos) e limpa dos triângulos-agulha. As peças duras
(trono, degrau, plinto) ganham arestas vivas.

A cor de vértice (paint) é branca na pedra, escurecida nas reentrâncias (oclusão medida no próprio
campo: mechas, dobras, olhos, boca) e dourada na coroa, no tridente e no diadema. O Godot usa a pedra
de Atlântida (sea_stone), que toma a cor de vértice como cor: o branco e os cinzas viram mármore e o
dourado (saturado) fica como está.
"""
import math

import bpy
import numpy as np

try:
    import openvdb as vdb
except ImportError:  # (Blender sem OpenVDB: sem estátuas)
    vdb = None

F = np.float32
BIG = F(1e9)
LEAF = 6  # filhos por nó da árvore de caixas


# ---------------------------------------------------------------------------
# Campo de distância: operações
# ---------------------------------------------------------------------------
def smin(a, b, k):
    """União suave (filete de raio ~k)."""
    if k <= 0:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0) / k
    return np.minimum(a, b) - h * h * (k * 0.25)


def smax(a, b, k):
    """Interseção suave (e, com -b, a subtração)."""
    if k <= 0:
        return np.maximum(a, b)
    h = np.maximum(k - np.abs(a - b), 0) / k
    return np.maximum(a, b) + h * h * (k * 0.25)


def _pick(blo, bhi, lo, hi, pad):
    """Blocos cuja caixa encosta na caixa (lo, hi) aumentada de pad."""
    return np.nonzero(np.all(bhi >= lo - pad, axis=1) & np.all(blo <= hi + pad, axis=1))[0]


def rot(*axes_angles):
    """Matriz de rotação (colunas = eixos locais no mundo) por rotações seguidas: ('x', graus), ..."""
    m = np.eye(3)
    for ax, deg in axes_angles:
        a = math.radians(deg)
        c, s = math.cos(a), math.sin(a)
        if ax == "x":
            r = np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
        elif ax == "y":
            r = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
        else:
            r = np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
        m = r @ m
    return m


def frame(z_axis, x_hint=(1, 0, 0)):
    """Base ortonormal (colunas x, y, z) com o z dado e o x o mais perto possível de x_hint."""
    z = np.asarray(z_axis, float)
    z = z / np.linalg.norm(z)
    x = np.asarray(x_hint, float)
    x = x - z * (x @ z)
    if np.linalg.norm(x) < 1e-6:
        x = np.array([0.0, 1.0, 0.0]) - z * z[1]
    x = x / np.linalg.norm(x)
    y = np.cross(z, x)
    return np.stack([x, y, z], axis=1)


# ---------------------------------------------------------------------------
# Campo de distância: nós (cada um com a caixa lo/hi fora da qual o valor é > 0)
# ---------------------------------------------------------------------------
class Node:
    lo = None
    hi = None

    def ev(self, p, blo, bhi, band):
        """Valor do campo nos pontos p (m, S, 3) agrupados em blocos de caixa (blo, bhi)."""
        raise NotImplementedError


class Prim(Node):
    """Primitiva: f(pontos (n, 3)) -> distâncias (n,)."""

    def __init__(self, f, lo, hi):
        self.f = f
        self.lo = np.asarray(lo, F)
        self.hi = np.asarray(hi, F)

    def ev(self, p, blo, bhi, band):
        return self.f(p.reshape(-1, 3)).reshape(p.shape[:-1]).astype(F, copy=False)


def sphere(c, r):
    c = np.asarray(c, F)
    return Prim(lambda p: np.sqrt(((p - c) ** 2).sum(-1)) - r, c - r, c + r)


def ellipsoid(c, radii, R=None):
    """Elipsoide (centro, semi-eixos, rotação R com os eixos locais nas colunas)."""
    c = np.asarray(c, F)
    r = np.asarray(radii, F)
    R = np.eye(3, dtype=F) if R is None else np.asarray(R, F)
    ext = np.sqrt(((R * r[None, :]) ** 2).sum(1))

    def f(p):
        q = (p - c) @ R
        k0 = np.sqrt(((q / r) ** 2).sum(-1))
        k1 = np.sqrt(((q / (r * r)) ** 2).sum(-1))
        return k0 * (k0 - 1) / np.maximum(k1, 1e-9)
    return Prim(f, c - ext, c + ext)


def box(c, half, R=None, rnd=0.0):
    """Caixa de cantos arredondados (centro, meias medidas, rotação, raio do arredondado)."""
    c = np.asarray(c, F)
    hb = np.asarray(half, F)
    R = np.eye(3, dtype=F) if R is None else np.asarray(R, F)
    ext = np.abs(R) @ hb

    def f(p):
        q = np.abs((p - c) @ R) - (hb - rnd)
        return np.sqrt((np.maximum(q, 0) ** 2).sum(-1)) + np.minimum(q.max(-1), 0) - rnd
    return Prim(f, c - ext, c + ext)


def torus(c, R_major, r_minor, R=None):
    """Toro em volta do eixo z local."""
    c = np.asarray(c, F)
    R = np.eye(3, dtype=F) if R is None else np.asarray(R, F)
    ext = np.abs(R) @ np.array([R_major + r_minor, R_major + r_minor, r_minor], F)

    def f(p):
        q = (p - c) @ R
        return np.sqrt((np.sqrt(q[:, 0] ** 2 + q[:, 1] ** 2) - R_major) ** 2 + q[:, 2] ** 2) - r_minor
    return Prim(f, c - ext, c + ext)


def halfspace(point, normal):
    """Semiespaço do lado de trás da normal (dentro onde dot(p - point, n) < 0); caixa infinita."""
    pt = np.asarray(point, F)
    n = np.asarray(normal, F)
    n = n / np.linalg.norm(n)
    return Prim(lambda p: (p - pt) @ n, np.full(3, -BIG, F), np.full(3, BIG, F))


def lathe(c, profile, R=None):
    """Sólido de revolução em volta do eixo z local: perfil fechado [(raio, altura), ...]."""
    c = np.asarray(c, F)
    R = np.eye(3, dtype=F) if R is None else np.asarray(R, F)
    v = np.asarray(profile, F)
    w = np.roll(v, -1, axis=0) - v
    ww = np.maximum((w * w).sum(-1), 1e-12)
    rmax = float(v[:, 0].max())
    ext = np.abs(R) @ np.array([rmax, rmax, 0], F)
    zlo, zhi = float(v[:, 1].min()), float(v[:, 1].max())
    lo = c + np.minimum(R @ np.array([0, 0, zlo], F), R @ np.array([0, 0, zhi], F)) - ext
    hi = c + np.maximum(R @ np.array([0, 0, zlo], F), R @ np.array([0, 0, zhi], F)) + ext

    def f(p):
        q = (p - c) @ R
        pp = np.stack([np.sqrt(q[:, 0] ** 2 + q[:, 1] ** 2), q[:, 2]], -1)
        e = pp[:, None, :] - v[None]
        t = np.clip((e * w[None]).sum(-1) / ww[None], 0, 1)
        b = e - w[None] * t[..., None]
        d = (b * b).sum(-1).min(1)
        # paridade (dentro/fora) pelo número de arestas cruzadas
        c1 = pp[:, None, 1] >= v[None, :, 1]
        c2 = pp[:, None, 1] < np.roll(v, -1, axis=0)[None, :, 1]
        c3 = w[None, :, 0] * e[..., 1] > w[None, :, 1] * e[..., 0]
        flip = (c1 & c2 & c3) | (~c1 & ~c2 & ~c3)
        s = np.where(flip.sum(1) % 2 == 1, -1.0, 1.0)
        return s * np.sqrt(d)
    return Prim(f, lo, hi)


def loft(prof, cap_k=0.02):
    """Sólido de seções elípticas empilhadas em z: prof = [(z, meia largura, frente, trás, y do eixo)]
    (a frente vai para -y). As pontas de baixo e de cima são cortadas com filete cap_k."""
    P = np.asarray(prof, F)
    zs = P[:, 0]

    def f(p):
        z = p[:, 2]
        a = np.maximum(np.interp(z, zs, P[:, 1]), 1e-4)
        y0 = np.interp(z, zs, P[:, 4])
        dy = p[:, 1] - y0
        b = np.maximum(np.where(dy < 0, np.interp(z, zs, P[:, 2]), np.interp(z, zs, P[:, 3])), 1e-4)
        x = p[:, 0]
        k0 = np.sqrt((x / a) ** 2 + (dy / b) ** 2)
        k1 = np.sqrt((x / (a * a)) ** 2 + (dy / (b * b)) ** 2)
        d = k0 * (k0 - 1) / np.maximum(k1, 1e-9)
        return smax(d, np.maximum(zs[0] - z, z - zs[-1]), cap_k)
    amax = float(P[:, 1].max())
    lo = (-amax, float((P[:, 4] - P[:, 2]).min()), float(zs[0]))
    hi = (amax, float((P[:, 4] + P[:, 3]).max()), float(zs[-1]))
    return Prim(f, lo, hi)


def loft_at(prof, phi, z, off=0.0):
    """Ponto na superfície do loft na altura z e no ângulo phi (0 = frente, -y; positivo para +x),
    afastado `off` ao longo da normal (horizontal), e a normal."""
    P = np.asarray(prof, float)
    zs = P[:, 0]
    a = np.interp(z, zs, P[:, 1])
    y0 = np.interp(z, zs, P[:, 4])
    b = np.interp(z, zs, P[:, 2]) if math.cos(phi) >= 0 else np.interp(z, zs, P[:, 3])
    pt = np.array([a * math.sin(phi), y0 - b * math.cos(phi), z])
    n = _unit((math.sin(phi) / a, -math.cos(phi) / b, 0.0))
    return pt + n * off, n


def _segments_field(p, A, Bp, RA, RB, N=None, flat=1.0):
    """Distância à união de segmentos A->B (raio RA->RB), seção redonda ou achatada ao longo de N."""
    ba = Bp - A
    l2 = np.maximum((ba * ba).sum(-1), 1e-12)
    pa = p[:, None, :] - A[None]
    t = np.clip((pa * ba[None]).sum(-1) / l2, 0, 1)
    q = pa - t[..., None] * ba[None]
    r = RA[None] + (RB - RA)[None] * t
    q2 = (q * q).sum(-1)
    if N is None or flat == 1.0:
        d = np.sqrt(q2) - r
    else:
        qn = (q * N[None]).sum(-1)
        qo2 = np.maximum(q2 - qn * qn, 0)
        r2 = r * r
        k0 = np.sqrt(qo2 / r2 + (qn * flat) ** 2 / r2)
        k1 = np.sqrt(qo2 / (r2 * r2) + (qn * flat * flat) ** 2 / (r2 * r2))
        d = k0 * (k0 - 1) / np.maximum(k1, 1e-9)
    return d.min(1)


class Segs(Node):
    """Pedaço de tubo: alguns segmentos avaliados juntos."""

    def __init__(self, A, Bp, RA, RB, N=None, flat=1.0):
        self.A, self.B, self.RA, self.RB = (np.asarray(x, F) for x in (A, Bp, RA, RB))
        self.N = None if N is None else np.asarray(N, F)
        self.flat = flat
        rr = np.maximum(self.RA, self.RB)[:, None]
        self.lo = np.minimum(self.A - rr, self.B - rr).min(0)
        self.hi = np.maximum(self.A + rr, self.B + rr).max(0)

    def ev(self, p, blo, bhi, band):
        q = p.reshape(-1, 3)
        return _segments_field(q, self.A, self.B, self.RA, self.RB, self.N, self.flat).reshape(p.shape[:-1])


def tube(points, radii, normals=None, flat=1.0, per=4):
    """Tubo ao longo de uma poligonal com o raio de cada ponto (união dura dos segmentos).
    normals (opcional): direção de achatamento em cada ponto (a seção vira elipse 1 x 1/flat)."""
    P = np.asarray(points, F)
    r = np.asarray(radii, F)
    if r.ndim == 0:
        r = np.full(len(P), r, F)
    N = None
    if normals is not None:
        N = np.asarray(normals, F)
        d = P[1:] - P[:-1]
        d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)
        n = (N[:-1] + N[1:]) * 0.5
        n = n - d * (n * d).sum(1, keepdims=True)
        N = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    kids = []
    for s in range(0, len(P) - 1, per):
        e = min(s + per, len(P) - 1)
        kids.append(Segs(P[s:e], P[s + 1:e + 1], r[s:e], r[s + 1:e + 1], None if N is None else N[s:e], flat))
    return union(kids, 0.0)


class Group(Node):
    """Combinação em ordem: base e depois [(nó, modo, k)], modo 'u' (união), 's' (subtração) ou
    'i' (interseção), com filete k."""

    def __init__(self, base, ops=()):
        self.items = [(base, "u", 0.0)] + [o for o in ops if o[0] is not None]
        lo, hi = base.lo.copy(), base.hi.copy()
        for node, mode, k in self.items[1:]:
            if mode == "u":
                lo = np.minimum(lo, node.lo - k * 0.25)
                hi = np.maximum(hi, node.hi + k * 0.25)
            elif mode == "i":
                lo = np.maximum(lo, node.lo)
                hi = np.minimum(hi, node.hi)
        self.lo, self.hi = lo.astype(F), hi.astype(F)

    def ev(self, p, blo, bhi, band):
        out = np.full(p.shape[:2], BIG, F)
        for node, mode, k in self.items:
            sel = _pick(blo, bhi, node.lo, node.hi, k + band)
            if mode == "i" and sel.size < len(p):
                keep = np.zeros(len(p), bool)
                keep[sel] = True
                out[~keep] = BIG
            if sel.size == 0:
                continue
            full = sel.size == len(p)
            v = node.ev(p if full else p[sel], blo if full else blo[sel], bhi if full else bhi[sel], band + k)
            cur = out if full else out[sel]
            if mode == "u":
                r = smin(cur, v, k)
            elif mode == "s":
                r = smax(cur, -v, k)
            else:
                r = smax(cur, v, k)
            if full:
                out = r
            else:
                out[sel] = r
        return out


class Union(Node):
    """União (com filete k) de muitas peças, organizada numa árvore de caixas."""

    def __init__(self, kids, k=0.0):
        self.k = k
        if len(kids) > LEAF:
            cen = np.array([(n.lo + n.hi) * 0.5 for n in kids])
            ax = int(np.argmax(cen.max(0) - cen.min(0)))
            order = np.argsort(cen[:, ax])
            half = len(kids) // 2
            kids = [Union([kids[i] for i in order[:half]], k), Union([kids[i] for i in order[half:]], k)]
        self.kids = kids
        self.lo = (np.min([n.lo for n in kids], axis=0) - k * 0.25).astype(F)
        self.hi = (np.max([n.hi for n in kids], axis=0) + k * 0.25).astype(F)

    def ev(self, p, blo, bhi, band):
        out = None
        for node in self.kids:
            sel = _pick(blo, bhi, node.lo, node.hi, self.k + band)
            if sel.size == 0:
                continue
            if out is None:
                out = np.full(p.shape[:2], BIG, F)
            if sel.size == len(p):
                out = smin(out, node.ev(p, blo, bhi, band + self.k), self.k)
            else:
                out[sel] = smin(out[sel], node.ev(p[sel], blo[sel], bhi[sel], band + self.k), self.k)
        return np.full(p.shape[:2], BIG, F) if out is None else out


def union(kids, k=0.0):
    kids = [n for n in kids if n is not None]
    if len(kids) == 1:
        return kids[0]
    return Union(kids, k)


class Xform(Node):
    """Peça modelada no seu próprio referencial: mundo = t + s * R @ local."""

    def __init__(self, child, R=None, t=(0, 0, 0), s=1.0):
        self.child = child
        self.R = np.eye(3, dtype=F) if R is None else np.asarray(R, F)
        self.t = np.asarray(t, F)
        self.s = float(s)
        c = (child.lo + child.hi) * 0.5
        e = (child.hi - child.lo) * 0.5
        wc = self.t + self.s * (self.R @ c)
        we = self.s * (np.abs(self.R) @ e)
        self.lo, self.hi = (wc - we).astype(F), (wc + we).astype(F)

    def ev(self, p, blo, bhi, band):
        lp = ((p - self.t) @ self.R) / self.s
        c = (blo + bhi) * 0.5
        e = (bhi - blo) * 0.5
        lc = ((c - self.t) @ self.R) / self.s
        le = (e @ np.abs(self.R)) / self.s
        return self.child.ev(lp.astype(F), (lc - le).astype(F), (lc + le).astype(F), band / self.s) * F(self.s)


def mirror_x(node):
    """A peça espelhada em x."""
    return Xform(node, np.diag([-1.0, 1.0, 1.0]))


class Displace(Node):
    """Relevo somado ao campo: valor + fn(p), com |fn| <= amp."""

    def __init__(self, child, fn, amp):
        self.child, self.fn, self.amp = child, fn, amp
        self.lo, self.hi = (child.lo - amp).astype(F), (child.hi + amp).astype(F)

    def ev(self, p, blo, bhi, band):
        return self.child.ev(p, blo, bhi, band + self.amp) + self.fn(p).astype(F, copy=False)


class Offset(Node):
    """O campo engordado (r > 0) ou emagrecido (r < 0)."""

    def __init__(self, child, r):
        self.child, self.r = child, r
        self.lo, self.hi = (child.lo - max(r, 0)).astype(F), (child.hi + max(r, 0)).astype(F)

    def ev(self, p, blo, bhi, band):
        return self.child.ev(p, blo, bhi, band + abs(self.r)) - F(self.r)


# ---------------------------------------------------------------------------
# Avaliação em pontos soltos e malha (OpenVDB)
# ---------------------------------------------------------------------------
def _part1by2(x):
    x = x.astype(np.uint32) & 0x3FF
    x = (x | (x << 16)) & 0x030000FF
    x = (x | (x << 8)) & 0x0300F00F
    x = (x | (x << 4)) & 0x030C30C3
    x = (x | (x << 2)) & 0x09249249
    return x


def sdf_points(root, P, band, S=64, chunk=4096):
    """Valor do campo em pontos soltos (agrupados em blocos pela curva de Morton)."""
    P = np.asarray(P, F)
    n = len(P)
    if n == 0:
        return np.zeros(0, F)
    lo = P.min(0)
    span = float((P.max(0) - lo).max()) + 1e-9
    qi = ((P - lo) / span * 1023).astype(np.uint32)
    code = _part1by2(qi[:, 0]) | (_part1by2(qi[:, 1]) << 1) | (_part1by2(qi[:, 2]) << 2)
    order = np.argsort(code, kind="stable")
    m = (n + S - 1) // S
    idx = np.concatenate([order, np.full(m * S - n, order[-1])])
    PB = P[idx].reshape(m, S, 3)
    vals = np.empty((m, S), F)
    for s in range(0, m, chunk):
        pb = PB[s:s + chunk]
        vals[s:s + chunk] = root.ev(pb, pb.min(1), pb.max(1), band)
    out = np.empty(n, F)
    out[order] = vals.reshape(-1)[:n]
    return out


def sdf_grid(root, h, B=8, chunk=2048):
    """Campo numa grade VDB de passo h (em voxels, faixa de +-3): só os blocos B^3 perto da superfície
    são avaliados e gravados; o resto fica com o fundo e o sinal certo (signedFloodFill). Devolve
    (grade, canto lo)."""
    lo = np.asarray(root.lo, F) - 4 * h
    hi = np.asarray(root.hi, F) + 4 * h
    nb = np.ceil((hi - lo) / (B * h)).astype(int)
    ijk = np.indices(nb).reshape(3, -1).T.astype(np.int32)
    half = (B - 1) * 0.5 * h * math.sqrt(3)
    centers = lo + (ijk * B + (B - 1) * 0.5) * h
    dc = sdf_points(root, centers, band=3.0 * half)
    act = np.abs(dc) < 2.5 * half
    a = ijk[act]
    off = np.indices((B, B, B)).reshape(3, -1).T.astype(np.int32)
    grid = vdb.FloatGrid(3.0)
    grid.gridClass = vdb.GridClass.LEVEL_SET
    for s in range(0, len(a), chunk):
        ab = a[s:s + chunk]
        pts = (lo + (ab[:, None, :] * B + off[None]) * h).astype(F)
        blo = (lo + ab * B * h).astype(F)
        bhi = (blo + (B - 1) * h).astype(F)
        v = np.clip(root.ev(pts, blo, bhi, 2.0 * h) / h, -3, 3).reshape(-1, B, B, B)
        for k in range(len(ab)):
            grid.copyFromArray(np.ascontiguousarray(v[k]), tuple(int(x) for x in ab[k] * B))
    grid.signedFloodFill()
    return grid, lo


def mesh_from_arrays(name, verts, tris, quads):
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(verts))
    me.vertices.foreach_set("co", np.asarray(verts, np.float32).ravel())
    tris = np.asarray(tris, np.int32).reshape(-1, 3)
    quads = np.asarray(quads, np.int32).reshape(-1, 4)
    loops = np.concatenate([tris.ravel(), quads.ravel()])
    starts = np.concatenate([np.arange(len(tris)) * 3, len(tris) * 3 + np.arange(len(quads)) * 4]).astype(np.int32)
    me.loops.add(len(loops))
    me.loops.foreach_set("vertex_index", loops)
    me.polygons.add(len(starts))
    me.polygons.foreach_set("loop_start", starts)
    me.update(calc_edges=True)
    me.validate(clean_customdata=False)
    return me


def sdf_object(name, root, h, adapt=0.0):
    """Malha da superfície do campo (OpenVDB), como objeto na cena."""
    grid, lo = sdf_grid(root, h)
    pts, tris, quads = grid.convertToPolygons(0.0, adapt)
    tris = np.asarray(tris, np.int64).reshape(-1, 3)
    quads = np.asarray(quads, np.int64).reshape(-1, 4)
    # Faces viradas para fora: o volume com sinal tem de dar positivo (o VDB inverte o sentido nas
    # grades de nível)
    P = pts.astype(np.float64)
    vol = (np.einsum("ij,ij->i", P[tris[:, 0]], np.cross(P[tris[:, 1]], P[tris[:, 2]])).sum()
           + np.einsum("ij,ij->i", P[quads[:, 0]], np.cross(P[quads[:, 1]], P[quads[:, 2]])).sum()
           + np.einsum("ij,ij->i", P[quads[:, 0]], np.cross(P[quads[:, 2]], P[quads[:, 3]])).sum())
    if vol < 0:
        tris, quads = tris[:, ::-1], quads[:, ::-1]
    me = mesh_from_arrays(name, lo + pts.astype(F) * h, tris, quads)
    if not _closed(tris, quads):
        repair(me)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _closed(tris, quads):
    """A malha é fechada e sem arestas compartilhadas por mais de duas faces?"""
    e = np.concatenate([np.stack([tris[:, i], tris[:, (i + 1) % 3]], 1) for i in range(3)]
                       + [np.stack([quads[:, i], quads[:, (i + 1) % 4]], 1) for i in range(4)])
    e.sort(axis=1)
    _, counts = np.unique(e, axis=0, return_counts=True)
    return bool((counts == 2).all())


def repair(me, rounds=4):
    """Conserta onde a superfície ficou mais fina que a grade (o VDB junta duas folhas na mesma aresta
    ou no mesmo vértice): apaga as faces em volta, solta o que sobrar e fecha os furos."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    for _ in range(rounds):
        bad = [e for e in bm.edges if not e.is_manifold] + [v for v in bm.verts if not v.is_manifold]
        if not bad:
            break
        faces = set()
        for x in bad:
            for v in (x.verts if isinstance(x, bmesh.types.BMEdge) else (x,)):
                for f in v.link_faces:
                    faces.update(f2 for u in f.verts for f2 in u.link_faces)
        bmesh.ops.delete(bm, geom=list(faces), context="FACES")
        loose = [e for e in bm.edges if not e.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="EDGES")
        loose = [v for v in bm.verts if not v.link_edges]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
        filled = bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
        bmesh.ops.triangulate(bm, faces=filled["faces"])
    bmesh.ops.dissolve_degenerate(bm, dist=1e-7, edges=bm.edges[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def clean_mesh(obj, max_aspect=14.0, flat_deg=12.0, rounds=4):
    """Tira os triângulos-agulha que a redução deixa: colapsa a aresta curta das agulhas (só onde o
    colapso mantém a malha fechada: as duas pontas têm em comum só os dois vértices opostos) e gira
    as arestas entre triângulos quase coplanares para o lado mais equilibrado."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)

    def collapsible(e):
        if not e.is_manifold or len(e.link_faces) != 2:
            return False
        a, b = e.verts
        na = {x.other_vert(a) for x in a.link_edges}
        nb = {x.other_vert(b) for x in b.link_edges}
        opp = {v for f in e.link_faces for v in f.verts if v is not a and v is not b}
        if not ((na & nb) == opp and len(opp) == 2 and all(len(v.link_edges) > 3 for v in opp)):
            return False
        # nenhuma face em volta pode virar com o vértice no ponto médio
        mid = (a.co + b.co) * 0.5
        for v in (a, b):
            for f in v.link_faces:
                if f in e.link_faces:
                    continue
                co = [mid if u is a or u is b else u.co for u in f.verts]
                n = (co[1] - co[0]).cross(co[2] - co[0])
                if n.length < 1e-14 or n.normalized().dot(f.normal) < 0.4:
                    return False
        return True

    for _ in range(rounds):
        used = set()
        edges = []
        for f in bm.faces:
            ls = [e.calc_length() for e in f.edges]
            mx, mn = max(ls), min(ls)
            if mx * mx / max(2 * f.calc_area(), 1e-14) > max_aspect and mn < 0.3 * mx:
                e = f.edges[ls.index(mn)]
                if e.verts[0] in used or e.verts[1] in used or not collapsible(e):
                    continue
                used.update(v for fe in e.link_faces for v in fe.verts)
                edges.append(e)
        if not edges:
            break
        for e in edges:
            if e.is_valid and collapsible(e):
                bmesh.ops.collapse(bm, edges=[e], uvs=False)
    # Giro de arestas quase planas, só se a outra diagonal ainda não existe
    for e in list(bm.edges):
        if not e.is_valid or not e.is_manifold or len(e.link_faces) != 2:
            continue
        if e.calc_face_angle(3.14) > math.radians(flat_deg):
            continue
        f1, f2 = e.link_faces
        if len(f1.verts) != 3 or len(f2.verts) != 3:
            continue
        c = [v for v in f1.verts if v not in e.verts][0]
        d = [v for v in f2.verts if v not in e.verts][0]
        if any(x.other_vert(c) is d for x in c.link_edges):
            continue
        a, b = e.verts
        # gira se a menor das alturas melhora (triângulos mais cheios)
        def worst(p, q, r):
            ls = [(p.co - q.co).length, (q.co - r.co).length, (r.co - p.co).length]
            area = ((q.co - p.co).cross(r.co - p.co)).length * 0.5
            return max(ls) ** 2 / max(2 * area, 1e-14)
        now = max(worst(a, b, c), worst(a, b, d))
        then = max(worst(c, d, a), worst(c, d, b))
        if then < now * 0.7:
            nrm = (f1.normal + f2.normal).normalized()
            n1 = (d.co - c.co).cross(a.co - c.co)
            n2 = (b.co - c.co).cross(d.co - c.co)
            if n1.length < 1e-14 or n2.length < 1e-14:
                continue
            if n1.normalized().dot(n2.normalized()) < 0.8 or abs(n1.normalized().dot(nrm)) < 0.8:
                continue
            bmesh.ops.rotate_edges(bm, edges=[e], use_ccw=False)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def _apply_decimate(obj, ratio, symmetric, group=None, factor=1.0):
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = min(max(ratio, 0.0001), 1.0)
    mod.use_collapse_triangulate = True
    if symmetric:
        mod.use_symmetry = True
        mod.symmetry_axis = "X"
    if group:
        mod.vertex_group = group
        mod.invert_vertex_group = True          # (o grupo marca o que segurar)
        mod.vertex_group_factor = factor
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    old = obj.data
    obj.modifiers.clear()
    obj.data = me
    bpy.data.meshes.remove(old)


def decimate(obj, target, symmetric=False, importance=None, share=0.3):
    """Reduz até `target` triângulos (colapso de arestas). Com importance(pontos) -> 0..1, as faces
    importantes (rosto, mãos; peso >= 0,5) ficam com a fração `share` do orçamento e o resto com o
    que sobra, cada região reduzida à parte (no modo de edição, só as faces selecionadas)."""
    tris = tri_count(obj)
    if tris <= target:
        return obj
    if importance is None:
        _apply_decimate(obj, target / tris, symmetric)
        return obj
    if tris > target * 3:
        _apply_decimate(obj, target * 3 / tris, symmetric)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for frac, want_important in ((1 - share, False), (share, True)):
        me = obj.data
        n = len(me.vertices)
        V = np.empty(n * 3, np.float32)
        me.vertices.foreach_get("co", V)
        w = importance(V.reshape(-1, 3))
        loops = np.empty(len(me.loops), np.int32)
        me.loops.foreach_get("vertex_index", loops)
        starts = np.empty(len(me.polygons), np.int32)
        me.polygons.foreach_get("loop_start", starts)
        counts = np.empty(len(me.polygons), np.int32)
        me.polygons.foreach_get("loop_total", counts)
        fw = np.add.reduceat(w[loops], starts) / counts
        sel = (fw >= 0.5) == want_important
        region = int(((counts - 2) * sel).sum())
        if region == 0:
            continue
        me.polygons.foreach_set("select", sel)
        me.vertices.foreach_set("select", np.zeros(n, bool))
        me.edges.foreach_set("select", np.zeros(len(me.edges), bool))
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        bpy.ops.mesh.decimate(ratio=min(1.0, target * frac / region), use_symmetry=symmetric, symmetry_axis="X")
        bpy.ops.mesh.quads_convert_to_tris()
        bpy.ops.object.mode_set(mode="OBJECT")
    tris = tri_count(obj)
    if tris > target:
        _apply_decimate(obj, target / tris, symmetric)
    return obj


# ---------------------------------------------------------------------------
# Curvas (mechas, cachos, dobras)
# ---------------------------------------------------------------------------
def _unit(v):
    v = np.asarray(v, float)
    return v / max(np.linalg.norm(v), 1e-12)


def on_ellipsoid(c, radii, d, off=0.0):
    """Ponto na superfície do elipsoide (centro c, semi-eixos) na direção d a partir do centro,
    afastado `off` para fora."""
    c = np.asarray(c, float)
    r = np.asarray(radii, float)
    d = np.asarray(d, float)
    t = 1.0 / np.linalg.norm(d / r, axis=-1, keepdims=True)
    p = d * t
    n = p / (r * r)
    n = n / np.linalg.norm(n, axis=-1, keepdims=True)
    return c + p + n * off


def sph(theta, phi):
    """Direção pelos ângulos (theta a partir de +z, phi a partir de -y girando para +x)."""
    return np.array([math.sin(theta) * math.sin(phi), -math.sin(theta) * math.cos(phi), math.cos(theta)])


def _cone(a, b, ra, rb):
    """Cone arredondado de a (raio ra) a b (raio rb)."""
    return Segs([a], [b], [ra], [rb])


# ---------------------------------------------------------------------------
# Cabeça masculina (Poseidon): unidades da cabeça, queixo em z = 0, alto do crânio em z = 1
# ---------------------------------------------------------------------------
def male_face(mouth=0.0, furrow=0.5):
    """Crânio e rosto: testa (franzida com furrow), arcadas, órbitas com olhos, pálpebras e íris,
    nariz grego, maçãs, boca (aberta com mouth > 0) e queixo."""
    base = union([
        ellipsoid((0, 0.06, 0.62), (0.31, 0.43, 0.39)),           # crânio
        ellipsoid((0, -0.17, 0.7), (0.25, 0.21, 0.17)),           # testa
        ellipsoid((0, -0.1, 0.4), (0.285, 0.29, 0.32)),           # massa do rosto
        ellipsoid((0, -0.12, 0.17), (0.235, 0.27, 0.17), rot(("x", -12))),  # mandíbula
        ellipsoid((0, -0.29, 0.225), (0.14, 0.14, 0.12)),         # barril da boca
        ellipsoid((0, -0.335, 0.068), (0.085, 0.078, 0.07)),      # queixo
    ], 0.07)
    adds = []
    subs = []
    # Arcadas: uma de cada lado, da ponta de dentro (mais baixa e grossa na testa franzida, em "\ /")
    # até a têmpora, com a massa da glabela entre elas
    s_ = np.linspace(0, 1, 13)
    bx = 0.03 + 0.225 * s_
    by = -0.384 + 0.16 * (bx / 0.27) ** 2.2
    bz = 0.583 - furrow * 0.026 * (1 - s_) ** 1.5 + 0.022 * np.sin(np.clip(s_ * 1.6, 0, 1) * math.pi * 0.5) - 0.03 * s_ ** 3
    br = (0.03 + 0.012 * furrow) * (1 - 0.45 * s_ ** 2) + 0.008 * np.sin(s_ * math.pi)
    brow = tube(np.stack([bx, by, bz], 1), br)
    adds += [brow, mirror_x(brow), ellipsoid((0, -0.372, 0.565 - 0.012 * furrow), (0.045, 0.03, 0.038))]
    # Maçãs do rosto (zigomático)
    cheek = ellipsoid((0.19, -0.26, 0.435), (0.085, 0.06, 0.05), rot(("z", 30), ("y", -12)))
    adds += [cheek, mirror_x(cheek)]
    # Nariz (ponte reta continuando a testa), ponta, asas
    nose = union([
        _cone((0, -0.372, 0.55), (0, -0.458, 0.35), 0.026, 0.034),
        sphere((0, -0.462, 0.335), 0.038),
        ellipsoid((0.045, -0.418, 0.315), (0.034, 0.034, 0.03)),
        ellipsoid((-0.045, -0.418, 0.315), (0.034, 0.034, 0.03)),
    ], 0.025)
    # Órbitas: a parte da frente do rosto na altura dos olhos, logo abaixo da arcada
    sock = ellipsoid((0.14, -0.425, 0.505), (0.1, 0.075, 0.058), rot(("z", 20)))
    subs += [sock, mirror_x(sock)]
    # Rugas da testa (franzida): sulcos horizontais e os dois verticais entre as sobrancelhas
    creases = []
    if furrow:
        for zc, w in ((0.68, 0.16), (0.735, 0.13)):
            xs = np.linspace(-w, w, 9)
            creases.append(tube([(x, -0.395 + 0.5 * x * x, zc + 0.15 * x * x) for x in xs], 0.006))
        for s in (1, -1):
            creases.append(_cone((0.022 * s, -0.42, 0.575), (0.03 * s, -0.405, 0.64), 0.006, 0.003))
    # Narinas
    nos = ellipsoid((0.027, -0.46, 0.296), (0.013, 0.02, 0.011))
    nostrils = [nos, mirror_x(nos)]
    face = Group(base, [(union(adds, 0.0), "u", 0.05), (union(subs, 0.0), "s", 0.035),
                        (nose, "u", 0.03), (union(nostrils, 0.0), "s", 0.008),
                        (union(creases, 0.0) if creases else None, "s", 0.008)])
    eyes = [eye(1), eye(-1)]
    face = Group(face, [(union(eyes, 0.0), "u", 0.01)])
    face = Group(face, [(m, mode, k) for m, mode, k in mouth_parts(mouth)])
    return face


def almond(cx, cz, w, h_up, h_low, tilt=0.0):
    """Abertura amendoada do olho (prisma ao longo de y): interseção de dois cilindros (arcos de
    cima e de baixo), largura w, alturas h_up e h_low a partir do centro."""
    R1 = ((w * 0.5) ** 2 + h_up ** 2) / (2 * h_up)
    R2 = ((w * 0.5) ** 2 + h_low ** 2) / (2 * h_low)
    a1 = np.array([cx + tilt, cz + h_up - R1])
    a2 = np.array([cx, cz - h_low + R2])

    def f(p):
        d1 = np.sqrt((p[:, 0] - a1[0]) ** 2 + (p[:, 2] - a1[1]) ** 2) - R1
        d2 = np.sqrt((p[:, 0] - a2[0]) ** 2 + (p[:, 2] - a2[1]) ** 2) - R2
        return np.maximum(d1, d2)
    return Prim(f, (cx - w, -BIG, cz - h_low - 0.01), (cx + w, BIG, cz + h_up + 0.01))


def eye(side, c=(0.138, -0.355, 0.505), R=0.075, w=0.125, h_up=0.029, h_low=0.021, lid=0.009,
        gaze=(0, -1, -0.04), iris=0.026):
    """Olho clássico: calota amendoada (prisma amendoado cortado por uma esfera de raio R cuja frente
    fica em c), o anel das pálpebras em volta (mais largo em cima, saltando `lid`) e a íris marcada
    (anel cavado e pupila)."""
    cx, cy, cz = c[0] * side, c[1], c[2]
    cs = np.array([cx, cy + R, cz])
    g = _unit(gaze)
    cap = Group(almond(cx, cz, w, h_up, h_low, 0.006 * side), [(sphere(cs, R), "i", 0.004)])
    ring_lids = Group(almond(cx, cz + 0.007, w * 1.1, h_up + 0.017, h_low + 0.006, 0.006 * side),
                      [(sphere(cs, R + lid), "i", 0.004),
                       (almond(cx, cz, w, h_up, h_low, 0.006 * side), "s", 0.005)])
    iris_c = cs + g * (R - 0.001)
    ring = torus(iris_c, iris, 0.006, frame(g))
    pupil = sphere(cs + g * (R + 0.007), 0.0125)
    return Group(union([cap, ring_lids], 0.004), [(ring, "s", 0.003), (pupil, "s", 0.003)])


def mouth_parts(mouth):
    """Lábios; com mouth > 0, a boca aberta (cavidade funda) com lábios grossos em volta (o de baixo
    um pouco para a frente, como uma bica)."""
    if mouth <= 0:
        up = ellipsoid((0, -0.425, 0.238), (0.068, 0.028, 0.02))
        lowl = ellipsoid((0, -0.414, 0.198), (0.054, 0.03, 0.022))
        slit = ellipsoid((0, -0.452, 0.218), (0.064, 0.04, 0.0055))
        return [(union([up, lowl], 0.01), "u", 0.02), (slit, "s", 0.006)]
    w = 0.1 + 0.01 * mouth
    hgt = 0.055 * mouth
    zc = 0.205 - hgt * 0.35
    xs = np.linspace(-w * 1.02, w * 1.02, 15)
    u = (xs / w) ** 2
    ul = [(x, -0.448 + 0.05 * uu, zc + hgt + 0.012 - 0.01 * uu) for x, uu in zip(xs, u)]
    ll = [(x, -0.468 + 0.07 * uu, zc - hgt - 0.016 + 0.014 * uu) for x, uu in zip(xs, u)]
    lips = union([tube(ul, [0.016 + 0.014 * (1 - uu) for uu in u]), tube(ll, [0.02 + 0.02 * (1 - uu) for uu in u])], 0.0)
    return [(lips, "u", 0.02), (mouth_hole(mouth), "s", 0.012)]


# ---------------------------------------------------------------------------
# Barba, bigode, cabelo e coroa (cabeça masculina)
# ---------------------------------------------------------------------------
def snail(c, n, t, R, turns=1.7, side=1, depth=0.45, groove=0.12):
    """Cacho em caracol deitado na superfície (centro c, normal n, direção t): botão abaulado com um
    sulco em espiral do aro até o miolo."""
    n = _unit(n)
    t = _unit(np.asarray(t, float) - n * (np.asarray(t, float) @ n))
    b = np.cross(n, t) * side
    c = np.asarray(c, float)
    M = np.stack([t, np.cross(n, t), n], axis=1)
    knob = ellipsoid(c + n * R * 0.1, (R, R, R * depth), M)
    th = np.linspace(0, turns * 2 * math.pi, int(turns * 18) + 2)
    rho = R * (0.92 - 0.8 * th / th[-1])
    hgt = R * 0.1 + R * depth * np.sqrt(np.maximum(1 - (rho / R) ** 2, 0)) + R * 0.02
    pts = c + hgt[:, None] * n + rho[:, None] * (np.cos(th)[:, None] * t + np.sin(th)[:, None] * b)
    rr = R * groove * np.linspace(1.0, 0.6, len(th))
    return Group(knob, [(tube(pts, rr), "s", R * 0.04)])


def beard_profile(length=0.35, width=1.0):
    """Volume da barba (loft): das costeletas (z ~ 0,5) até a ponta (z = -length)."""
    rows = []
    for z in np.linspace(-length, 0.5, 28):
        t = (z + length) / (0.5 + length)               # 0 na ponta, 1 em cima
        a = (0.08 + 0.225 * math.sin(min(t * 1.35, 1.0) * math.pi * 0.5) ** 0.6) * width
        bf = 0.1 + 0.21 * math.sin(min(t * 1.5, 1.0) * math.pi * 0.5) ** 0.6
        bb = 0.08 + 0.2 * t
        y0 = -0.11 - 0.12 * (1 - t) ** 1.4
        rows.append((z, a, bf, bb, y0))
    return rows


def locks_relief(t, A, sharp=0.6):
    """Relevo de mechas: t em unidades de mecha (cada inteiro é um sulco); crista arredondada e
    sulco em V de profundidade A."""
    f = t - np.floor(t)
    return A * np.sin(math.pi * f) ** sharp


def beard_line(top=0.16, side=0.4, k=0.03):
    """Limite de cima da barba: baixo embaixo do lábio (top), subindo pelas bochechas até as
    costeletas (side); campo ~ z - altura(ângulo)."""
    def f(p):
        phi = np.abs(np.arctan2(p[:, 0], -(p[:, 1] + 0.08)))
        u = np.clip(phi / math.radians(95), 0, 1)
        h = top + (side - top) * (u ** 1.6) + 0.25 * np.clip((phi - math.radians(95)) / 0.6, 0, 1)
        return (p[:, 2] - h) * 0.8
    return Prim(f, (-BIG, -BIG, -BIG), (BIG, BIG, BIG))


def beard(length=0.35, width=1.0, n_locks=11, A=0.026, top=0.16, side=0.4, seed=3):
    """Barba: volume cheio com mechas largas e onduladas em relevo (cristas arredondadas e sulcos em V
    que ondulam juntas e convergem para a ponta) e uma fileira de caracóis na borda de baixo; em cima,
    acaba embaixo do lábio e sobe pelas bochechas até as costeletas."""
    rng = np.random.default_rng(seed)
    prof = beard_profile(length, width)
    P = np.asarray(prof, F)
    z0, z1 = float(P[0, 0]), float(P[-1, 0])
    dphi = math.pi / n_locks

    def relief(p):
        q = p.reshape(-1, 3)
        z = q[:, 2]
        a = np.interp(z, P[:, 0], P[:, 1])
        y0 = np.interp(z, P[:, 0], P[:, 4])
        bf = np.interp(z, P[:, 0], P[:, 2])
        phi = np.arctan2(q[:, 0] / a, -(q[:, 1] - y0) / bf)
        t = (z - z0) / (z1 - z0)
        wave = 0.16 * np.sin((z - z0) * 2 * math.pi / 0.3) * (0.4 + 0.6 * t)
        rel = locks_relief((phi + wave) / dphi + 0.5, A)
        fade = np.clip(1.6 - np.abs(phi), 0.25, 1)
        return (-(rel - A * 0.5) * fade).reshape(p.shape[:-1])
    vol = Group(Displace(loft(prof, 0.08), relief, A), [(beard_line(top, side), "i", 0.03)])
    curls_ = []
    for k in range(7):
        u = (k / 6) * 2 - 1
        phi = u * math.radians(68)
        z = -length * (0.84 - 0.42 * abs(u) ** 1.5)
        p, nn = loft_at(prof, phi, z, 0.012)
        curls_.append(snail(p, nn, (0, 0, -1), 0.05 + 0.004 * rng.uniform(-1, 1), 1.6, 1 if u > 0 else -1))
    return union([vol, union(curls_, 0.0)], 0.012)


def mustache(w=0.032, open_mouth=False):
    """Bigode: dois cordões largos de cada lado saindo de baixo do nariz, passando sobre o lábio e
    caindo pelos cantos da boca até a barba; com a boca fechada, um tufo embaixo do lábio de baixo."""
    strands = []
    if open_mouth:
        base = np.array([(0.01, -0.462, 0.292), (0.05, -0.466, 0.278), (0.095, -0.455, 0.262), (0.135, -0.425, 0.232),
                         (0.155, -0.395, 0.17), (0.163, -0.37, 0.1), (0.165, -0.35, 0.035)])
        w *= 1.15
    else:
        base = np.array([(0.01, -0.458, 0.29), (0.045, -0.46, 0.273), (0.085, -0.443, 0.247), (0.118, -0.412, 0.21),
                         (0.136, -0.385, 0.16), (0.146, -0.36, 0.1), (0.15, -0.34, 0.045)])
    t = np.linspace(0, 1, len(base))
    rad = w * (0.55 + 0.55 * np.sin(np.clip(t * 1.25, 0, 1) * math.pi) ** 0.6) * (1 - 0.3 * t)
    nrm = np.array([_unit((0.6 * x, -1.0, 0.25)) for x, _, _ in base])
    for dz, dy, sc in ((0.012, 0.0, 1.0), (-0.016, 0.006, 0.8)):
        p = base.copy()
        p[:, 1] += dy
        p[:, 2] += dz * (0.4 + t)
        strand = tube(p, rad * sc, nrm, 1.6)
        strands += [strand, mirror_x(strand)]
    if not open_mouth:
        strands.append(tube([(0, -0.43, 0.168), (0, -0.425, 0.13), (0.004, -0.415, 0.09)], [0.018, 0.022, 0.012],
                            [(0, -1, 0)] * 3, 1.6))
    return union(strands, 0.004)


HAIR_C = np.array([0.0, 0.05, 0.62])
HAIR_R = np.array([0.345, 0.465, 0.425])


def on_hair(th, ph, off=0.0):
    """Ponto e normal na calota do cabelo pelos ângulos (theta do alto, phi da frente)."""
    p = on_ellipsoid(HAIR_C, HAIR_R, sph(th, ph), off)
    n = _unit((p - HAIR_C) / (HAIR_R * HAIR_R))
    return p, n


def hairline(front=0.79, temple=0.74, ear=0.42, nape=0.3):
    """Linha do cabelo (campo ~ altura(ângulo) - z): testa, têmporas, sobre as orelhas e nuca."""
    pts = np.array([[0.0, front], [0.7, temple], [1.35, ear + 0.1], [1.75, ear], [2.4, nape + 0.06], [math.pi, nape]])

    def f(p):
        phi = np.abs(np.arctan2(p[:, 0], -(p[:, 1] - 0.05)))
        h = np.interp(phi, pts[:, 0], pts[:, 1])
        return (h - p[:, 2]) * 0.8
    return Prim(f, (-BIG, -BIG, -BIG), (BIG, BIG, BIG))


def hair(n_locks=22, A=0.024, seed=5, fringe=7, line=None):
    """Cabelo: calota cheia (o crânio engordado) recortada na linha do cabelo, com mechas onduladas em
    relevo saindo do redemoinho no alto da cabeça, e uma fileira de caracóis na franja (sobre a testa,
    embaixo da coroa)."""
    rng = np.random.default_rng(seed)
    dphi = 2 * math.pi / n_locks

    def relief(p):
        q = (p.reshape(-1, 3) - HAIR_C) / HAIR_R
        th = np.arctan2(np.sqrt(q[:, 0] ** 2 + q[:, 1] ** 2), q[:, 2])
        phi = np.arctan2(q[:, 0], -q[:, 1])
        wave = 0.13 * np.sin(th * 2 * math.pi / 0.62) * np.clip(th / 0.5, 0, 1)
        rel = locks_relief((phi + wave) / dphi, A)
        fade = np.clip((th - 0.12) / 0.3, 0, 1)
        return (-(rel - A * 0.5) * fade).reshape(p.shape[:-1])
    cap = Displace(ellipsoid(HAIR_C, HAIR_R), relief, A)
    cap = Group(cap, [(line if line is not None else hairline(), "i", 0.04)])
    curls_ = []
    for k in range(fringe):
        u = (k / (fringe - 1)) * 2 - 1
        ph = u * math.radians(64)
        p, nn = on_hair(math.radians(58 + 9 * abs(u) ** 2), ph, 0.006)
        curls_.append(snail(p, nn, (math.cos(ph), math.sin(ph), -0.6), 0.058 + 0.004 * rng.uniform(-1, 1), 1.6,
                            1 if u >= 0 else -1, 0.5))
    return union([cap, union(curls_, 0.0)], 0.012)


def crown_sdf(c=(0, 0.05, 0.86), radii=(0.3, 0.39), height=0.05, thick=0.022, spikes=7, arc=150.0,
              spike_len=0.2, tilt=8.0, spike_w=0.045):
    """Coroa: aro elíptico (com filete e um friso de contas em cima) e pontas achatadas, altas e baixas
    alternadas, na frente (arc = graus cobertos), com uma conta na base de cada ponta."""
    c = np.asarray(c, float)
    a, b = radii
    R = rot(("x", -tilt))

    def ring_f(p):
        q = (p - c) @ R
        k0 = np.sqrt((q[:, 0] / a) ** 2 + (q[:, 1] / b) ** 2)
        k1 = np.sqrt((q[:, 0] / a ** 2) ** 2 + (q[:, 1] / b ** 2) ** 2)
        de = k0 * (k0 - 1) / np.maximum(k1, 1e-9)
        dx = np.abs(de) - thick * 0.5
        dz = np.abs(q[:, 2]) - height * 0.5
        rr = min(thick, height) * 0.3
        qq = np.stack([dx + rr, dz + rr], -1)
        return np.sqrt((np.maximum(qq, 0) ** 2).sum(-1)) + np.minimum(qq.max(-1), 0) - rr
    ext = np.array([a + thick, b + thick, height + 0.05])
    parts = [Prim(ring_f, c - ext, c + ext)]
    for k in range(spikes):
        ang = math.radians(-arc * 0.5 + arc * k / max(spikes - 1, 1))
        d = np.array([math.sin(ang) * a, -math.cos(ang) * b, 0.0])
        nrm = _unit((math.sin(ang) / a, -math.cos(ang) / b, 0.0))
        base = c + R @ (d + np.array([0, 0, height * 0.2]))
        L = spike_len * (1 - 0.3 * abs(ang) / math.radians(max(arc * 0.5, 1))) * (1.0 if k % 2 == 0 else 0.62)
        tip = base + R @ (np.array([0, 0, L]) + nrm * L * 0.16)
        up = _unit(tip - base)
        fl = _unit(R @ nrm - up * ((R @ nrm) @ up))
        sw = spike_w * (1.0 if k % 2 == 0 else 0.8)
        parts.append(tube([base, base * 0.55 + tip * 0.45, tip], [sw, sw * 0.62, sw * 0.12], [fl, fl, fl], 2.4, per=2))
        parts.append(sphere(base + R @ (nrm * thick * 0.55), thick * 0.75))
    return union(parts, 0.008)


def male_head(mouth=0.0, furrow=0.6, beard_len=0.35, beard_w=1.0, beard_top=0.16, crown=None, seed=1):
    """Cabeça de Poseidon (queixo em z = 0, alto do crânio em z = 1): rosto, barba, bigode, cabelo
    e coroa (crown = parâmetros de crown_sdf, ou None sem coroa)."""
    face = male_face(mouth, furrow)
    head = union([face, hair(seed=seed + 4)], 0.012)
    head = Group(head, [(beard(beard_len, beard_w, top=beard_top, seed=seed + 2), "u", 0.03),
                        (mustache(open_mouth=mouth > 0), "u", 0.01)])
    if crown is not None:
        head = Group(head, [(crown_sdf(**crown), "u", 0.01)])
    if mouth > 0:
        # a boca aberta de novo por cima da barba e do bigode
        head = Group(head, [(mouth_hole(mouth), "s", 0.012)])
    return head


def mouth_hole(mouth):
    """Abertura da boca (aberta): caixa arredondada funda."""
    w = 0.1 + 0.01 * mouth
    hgt = 0.055 * mouth
    return box((0, -0.5, 0.205 - hgt * 0.35), (w, 0.26, hgt), None, min(hgt, w) * 0.85)


def wave_mane(c=(0.0, 0.1, 0.6), radii=(0.57, 0.29, 0.59), n_locks=24, n_curls=15, A=0.04, seed=11):
    """Juba de ondas do mar em volta do rosto (máscara das cachoeiras): cúpula atrás da cabeça com
    mechas onduladas em relevo saindo do rosto para fora e, na borda, uma fileira de cristas enroladas
    (caracóis grandes virados para a frente) que recortam a silhueta."""
    rng = np.random.default_rng(seed)
    c = np.asarray(c, float)
    rx, ry, rz = radii
    dal = 2 * math.pi / n_locks

    def relief(p):
        q = p.reshape(-1, 3) - c
        al = np.arctan2(q[:, 0], q[:, 2])
        rho = np.sqrt((q[:, 0] / rx) ** 2 + (q[:, 2] / rz) ** 2)
        wave = 0.12 * np.sin(rho * 2 * math.pi / 0.33)
        rel = locks_relief((al + wave) / dal, A)
        fade = np.clip((rho - 0.35) / 0.2, 0, 1)
        return (-(rel - A * 0.5) * fade).reshape(p.shape[:-1])
    mane = Displace(ellipsoid(c, radii), relief, A)
    curls_ = []
    for k in range(n_curls):
        al = math.radians(-150 + 300 * k / (n_curls - 1))
        d = np.array([math.sin(al) * 0.9, -math.sqrt(1 - 0.81), math.cos(al) * 0.9])
        pos = c + d * np.array([rx, ry, rz])
        nrm = _unit(d / np.array([rx, ry, rz]) ** 1 * np.array([0.35, 1.0, 0.35]))
        curls_.append(snail(pos + nrm * 0.01, nrm, (math.cos(al), 0, -math.sin(al)), 0.085 + 0.005 * rng.uniform(-1, 1),
                            1.7, 1 if al > 0 else -1, 0.62, 0.13))
    return union([mane, union(curls_, 0.0)], 0.018)


FACE_CROWN = dict(c=(0, 0.04, 0.86), radii=(0.305, 0.4), height=0.075, thick=0.032, spikes=9, arc=200.0,
                  spike_len=0.3, tilt=8.0, spike_w=0.072)


def face_head():
    """O rosto das cachoeiras: cabeça de boca aberta, testa franzida, barba longa, juba de ondas e
    coroa; a parte de trás (dentro da rocha) cortada reta."""
    head = male_head(mouth=1.0, furrow=1.0, beard_len=0.46, beard_w=1.2, beard_top=0.1, crown=FACE_CROWN, seed=7)
    full = union([wave_mane(), head], 0.03)
    full = Group(full, [(halfspace((0, 0.24, 0), (0, 1, 0)), "i", 0.03), (mouth_hole(1.0), "s", 0.012)])
    return full


def poseidon_face():
    """O rosto gigante das cachoeiras do Portão (boca aberta, de onde sai a água)."""
    def imp(V):
        """O rosto (olhos, nariz, boca, bigode) fica com quase metade dos triângulos."""
        return spots(((0, -0.38, 0.38), 0.3), base=0.0)(V)
    mouth_shadow = (ellipsoid((0, -0.27, 0.186), (0.15, 0.2, 0.11)), 0.04)
    return [statue("poseidon_face", face_head(), 0.005, 23800, True, crown_sdf(**FACE_CROWN), 0.006, True, None, imp,
                   0.45, mouth_shadow)]


# ---------------------------------------------------------------------------
# Corpo (Poseidon em pé e sentado): unidades do corpo, altura da figura = 1 (da sola ao alto do
# crânio), cabeça = 1/7,5; a direita da figura fica em -x
# ---------------------------------------------------------------------------
HU = 1.0 / 7.5


def along(a, b, t, off=(0, 0, 0)):
    a, b = np.asarray(a, float), np.asarray(b, float)
    return a + (b - a) * t + np.asarray(off, float)


def muscle(a, b, t, radii, off=(0, 0, 0), roll=0.0):
    """Ventre de músculo: elipsoide deitado ao longo do osso a -> b (no ponto t, deslocado off), com os
    semi-eixos (largura, profundidade, comprimento)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    M = frame(b - a, (1, 0, 0))
    if roll:
        M = M @ rot(("z", roll))
    return ellipsoid(along(a, b, t, off), radii, M)


def limb(a, b, ra, rb):
    return _cone(a, b, ra, rb)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


TORSO_PROF = [  # z, meia largura, frente, trás, y do eixo
    (0.44, 0.1, 0.07, 0.078, 0.012), (0.49, 0.102, 0.068, 0.074, 0.012), (0.53, 0.094, 0.064, 0.066, 0.012),
    (0.565, 0.088, 0.062, 0.062, 0.012), (0.6, 0.09, 0.064, 0.06, 0.014), (0.645, 0.098, 0.068, 0.064, 0.016),
    (0.69, 0.105, 0.072, 0.068, 0.016), (0.735, 0.112, 0.074, 0.072, 0.016), (0.775, 0.12, 0.068, 0.072, 0.018),
    (0.805, 0.122, 0.054, 0.066, 0.022), (0.825, 0.1, 0.044, 0.056, 0.024), (0.845, 0.062, 0.036, 0.046, 0.022),
    (0.87, 0.045, 0.034, 0.04, 0.016)]


def torso_relief(p):
    """Musculatura em relevo no loft do tronco (negativo = para fora): placas peitorais com a borda de
    baixo marcada, sulco do esterno, gomos do abdômen com a linha alba, serrátil, escápulas e o sulco
    da coluna."""
    q = p.reshape(-1, 3)
    x, y, z = q[:, 0], q[:, 1], q[:, 2]
    front = smoothstep(0.0, -0.035, y)
    back = smoothstep(0.03, 0.06, y)
    d = np.zeros(len(q), F)
    for s in (1, -1):
        a = math.radians(-22 * s)
        u = (x - 0.054 * s) * math.cos(a) - (z - 0.748) * math.sin(a)
        v = (x - 0.054 * s) * math.sin(a) + (z - 0.748) * math.cos(a)
        r = np.sqrt((u / 0.064) ** 2 + (v / np.where(v < 0, 0.036, 0.05)) ** 2)
        d -= 0.014 * smoothstep(1.0, 0.62, r) * front
        # serrátil: dentes na lateral das costelas
        for k in range(3):
            zz = 0.64 + 0.028 * k
            rr = np.sqrt(((x - 0.088 * s) / 0.016) ** 2 + ((z - zz) / 0.011) ** 2)
            d -= 0.004 * smoothstep(1.0, 0.3, rr) * smoothstep(-0.02, -0.045, y + 0.0)
        # escápulas
        rs = np.sqrt(((x - 0.06 * s) / 0.05) ** 2 + ((z - 0.74) / 0.065) ** 2)
        d -= 0.009 * smoothstep(1.0, 0.4, rs) * back
    # sulco do esterno
    d += 0.005 * np.exp(-(x / 0.009) ** 2) * smoothstep(0.69, 0.72, z) * smoothstep(0.8, 0.77, z) * front
    # gomos do abdômen
    ax = np.abs(x)
    gx = np.where(ax < 0.048, np.sin(np.clip(ax / 0.048, 0, 1) * math.pi) ** 0.5, 0.0)
    rows = (0.508, 0.57, 0.616, 0.662, 0.7)
    gz = np.zeros(len(q), F)
    for z0, z1 in zip(rows[:-1], rows[1:]):
        inside = (z > z0) & (z < z1)
        gz = np.where(inside, np.sin((z - z0) / (z1 - z0) * math.pi) ** 0.6, gz)
    d -= 0.0075 * gx * gz * front
    # coluna
    d += 0.006 * np.exp(-(x / 0.012) ** 2) * smoothstep(0.5, 0.56, z) * smoothstep(0.83, 0.78, z) * back
    return d.reshape(p.shape[:-1])


def torso():
    """Tronco nu de herói: loft com o peito largo e a cintura fina, musculatura em relevo (peitorais,
    abdômen, serrátil, escápulas, coluna), clavículas, trapézio e pescoço."""
    core = Displace(loft(TORSO_PROF, 0.03), torso_relief, 0.016)
    parts = [core, _cone((0, 0.014, 0.8), (0, 0.006, 0.905), 0.042, 0.039)]
    for s in (1, -1):
        parts.append(tube([(0.012 * s, -0.045, 0.808), (0.06 * s, -0.04, 0.817), (0.105 * s, -0.01, 0.822)], 0.0085))
        parts.append(ellipsoid((0.068 * s, 0.03, 0.834), (0.06, 0.032, 0.026), rot(("y", 24 * s))))
    return union(parts, 0.025)


def arm(sh, el, wr, side):
    """Braço: deltoide, braço (bíceps e tríceps) e antebraço (massa do braquiorradial perto do
    cotovelo)."""
    sh, el, wr = (np.asarray(x, float) for x in (sh, el, wr))
    parts = [
        limb(sh, el, 0.034, 0.025),
        limb(el, wr, 0.027, 0.018),
        muscle(sh, el, 0.1, (0.044, 0.042, 0.056), (0.008 * side, 0.0, 0.0)),       # deltoide
        muscle(sh, el, 0.5, (0.026, 0.029, 0.056), (0, -0.01, 0)),                  # bíceps
        muscle(sh, el, 0.42, (0.026, 0.026, 0.06), (0, 0.01, 0)),                   # tríceps
        muscle(el, wr, 0.22, (0.026, 0.024, 0.048), (0.004 * side, -0.004, 0)),     # braquiorradial
    ]
    return union(parts, 0.022)


def leg(hip, knee, ankle):
    """Perna: coxa (quadríceps), joelho, panturrilha e tornozelo."""
    hip, knee, ankle = (np.asarray(x, float) for x in (hip, knee, ankle))
    parts = [
        limb(hip, knee, 0.068, 0.043),
        limb(knee, ankle, 0.044, 0.024),
        muscle(hip, knee, 0.45, (0.058, 0.055, 0.12), (0, -0.012, 0)),               # quadríceps
        muscle(knee, ankle, 0.25, (0.04, 0.042, 0.075), (0, 0.016, 0)),              # panturrilha
        sphere(along(hip, knee, 1.0, (0, -0.012, 0.004)), 0.036),                   # joelho
    ]
    return union(parts, 0.025)


def foot(ankle, heel, toe, side, sandal=True):
    """Pé (calcanhar, peito do pé e dedos juntos com o dedão separado) com sandália: sola e tiras."""
    ankle, heel, toe = (np.asarray(x, float) for x in (ankle, heel, toe))
    fwd = _unit((toe - heel) * np.array([1, 1, 0]))
    lat = np.cross(fwd, (0, 0, 1))          # (de lado; side * lat aponta para dentro, onde fica o dedão)
    ball = heel + (toe - heel) * 0.72
    parts = [
        _cone(heel + (0, 0, 0.012), ankle, 0.024, 0.026),
        _cone(heel + (0, 0, 0.012), ball + (0, 0, 0.008), 0.022, 0.02),
        ellipsoid(ball + (0, 0, 0.006), (0.034, 0.026, 0.012), frame((0, 0, 1), lat)),
    ]
    toes = []
    for k in range(5):                                       # k = 0: o dedão
        p0 = ball + lat * side * (0.026 - 0.016 * k) + (0, 0, 0.004)
        L = 0.03 - 0.004 * k if k else 0.034
        toes.append(_cone(p0, p0 + fwd * L - (0, 0, 0.003), 0.0085 if k else 0.011, 0.006 if k else 0.0085))
    body = union([union(parts, 0.02), union(toes, 0.003)], 0.006)
    if not sandal:
        return body
    sole_c = heel + (toe - heel) * 0.5
    sole = box(sole_c + (0, 0, -0.012 + 0.006), (0.034, 0.5 * np.linalg.norm(toe - heel) + 0.012, 0.006),
               frame((0, 0, 1), lat), 0.005)
    straps = [tube([ball + lat * 0.035 + (0, 0, -0.002), ball + (0, 0, 0.022) - fwd * 0.01,
                    ball - lat * 0.035 + (0, 0, -0.002)], 0.004),
              tube([heel + lat * 0.03, ankle + (0, 0, -0.01) - fwd * 0.012, heel - lat * 0.03], 0.004)]
    ring = torus(ankle + (0, 0, 0.004), 0.027, 0.0045)
    return union([body, sole, union(straps + [ring], 0.0)], 0.004)


def fist(wrist, shaft_c, shaft_dir, side):
    """Mão fechada em volta de uma haste (centro shaft_c, direção shaft_dir): palma e dedos dobrados
    em volta, polegar por cima."""
    wrist = np.asarray(wrist, float)
    sc = np.asarray(shaft_c, float)
    sd = _unit(shaft_dir)
    to_w = wrist - sc
    to_w = _unit(to_w - sd * (to_w @ sd))
    side_v = np.cross(sd, to_w)
    parts = [ellipsoid(sc + to_w * 0.03, (0.026, 0.02, 0.034), frame(sd, to_w))]       # palma
    fingers = []
    for k in range(4):
        z = (k - 1.5) * 0.0165
        c = sc + sd * z
        pts = [c + 0.022 * (math.cos(a) * to_w + math.sin(a) * side_v * side) for a in np.linspace(0.2, 4.3, 7)]
        fingers.append(tube(pts, 0.0095 - 0.0007 * abs(k - 1.5)))
    th = [sc + sd * 0.03 + 0.024 * (math.cos(a) * to_w - math.sin(a) * side_v * side) for a in np.linspace(0.3, 2.3, 5)]
    fingers.append(tube(th, 0.01))
    return union([union(parts, 0.0), union(fingers, 0.004)], 0.01)


def open_hand(wrist, fwd, palm_n, side):
    """Mão aberta: palma, dedos juntos (com os vãos marcados) e o polegar separado."""
    wrist = np.asarray(wrist, float)
    fwd = _unit(fwd)
    pn = _unit(np.asarray(palm_n, float) - fwd * (np.asarray(palm_n, float) @ fwd))
    lat = np.cross(pn, fwd) * side
    M = np.stack([lat, fwd, pn], 1)
    parts = [box(wrist + fwd * 0.03, (0.024, 0.03, 0.01), M, 0.008)]
    fingers = []
    for k in range(4):
        x = (k - 1.5) * 0.0118
        L = (0.045, 0.05, 0.047, 0.038)[k]
        p0 = wrist + fwd * 0.058 + lat * x
        pts = [p0, p0 + fwd * L * 0.5 - pn * 0.004, p0 + fwd * L - pn * 0.012]
        fingers.append(tube(pts, [0.0068, 0.0062, 0.0052]))
    t0 = wrist + fwd * 0.02 + lat * 0.022
    fingers.append(tube([t0, t0 + fwd * 0.022 + lat * 0.012 - pn * 0.008, t0 + fwd * 0.04 + lat * 0.012 - pn * 0.014],
                        [0.009, 0.0075, 0.006]))
    return union([union(parts, 0.0), union(fingers, 0.002)], 0.008)


def folds(center, n, amp, wave=0.0, wave_len=0.2, z_amp=None, sharp=0.7):
    """Relevo de dobras verticais em volta de um eixo vertical (centro x, y): n dobras na volta,
    amplitude amp (ou z_amp(z)), ondulando com a altura."""
    cx, cy = center

    def fn(p):
        q = p.reshape(-1, 3)
        phi = np.arctan2(q[:, 0] - cx, -(q[:, 1] - cy))
        z = q[:, 2]
        t = (phi + wave * np.sin(z * 2 * math.pi / wave_len)) / (2 * math.pi / n)
        A = amp if z_amp is None else z_amp(z)
        return (-(locks_relief(t, 1.0, sharp) - 0.5) * A).reshape(p.shape[:-1])
    return fn


def hem_cut(z0, amp, n, cx=0.0, cy=0.0):
    """Barra ondulada: campo ~ altura da barra - z (corta o que fica abaixo)."""
    def f(p):
        phi = np.arctan2(p[:, 0] - cx, -(p[:, 1] - cy))
        return (z0 + amp * np.sin(phi * n) - p[:, 2]) * 0.9
    return Prim(f, (-BIG, -BIG, -BIG), (BIG, BIG, BIG))


def trident_sdf(base, top, r=0.009, w=0.07, prong=0.13):
    """Tridente: haste com anéis, colar, travessa curva para cima e três pontas de lança farpadas
    (achatadas)."""
    base, top = np.asarray(base, float), np.asarray(top, float)
    up = _unit(top - base)
    side = _unit(np.cross(up, (0, 1, 0)))
    if np.linalg.norm(np.cross(up, (0, 1, 0))) < 1e-6:
        side = np.array([1.0, 0, 0])
    fwd = np.cross(side, up)
    parts = [_cone(base, top, r, r * 1.05),
             _cone(top - up * 0.012, top + up * 0.012, r * 1.9, r * 1.9),      # colar
             sphere(base, r * 1.3)]
    for t in (0.33, 0.66):
        c = base + (top - base) * t
        parts.append(_cone(c - up * 0.006, c + up * 0.006, r * 1.6, r * 1.6))
    # travessa em arco
    bar = [top + side * w * u + up * (0.035 * u * u) for u in np.linspace(-1, 1, 11)]
    parts.append(tube(bar, [r * (1.1 - 0.25 * abs(u)) for u in np.linspace(-1, 1, 11)]))
    for u in (-1, 0, 1):
        b = top + side * w * u + up * (0.035 * u * u)
        L = prong * (1.18 if u == 0 else 1.0)
        tip_base = b + up * L
        parts.append(_cone(b, tip_base, r * 0.85, r * 0.8))
        # ponta de lança achatada (folha) e as farpas para baixo
        parts.append(tube([tip_base - up * 0.01, tip_base + up * 0.028, tip_base + up * 0.065],
                          [r * 1.2, r * 2.3, r * 0.15], [fwd] * 3, 2.6, per=2))
        for sgn in (-1, 1):
            parts.append(_cone(tip_base + up * 0.012 + side * sgn * r * 1.6,
                               tip_base - up * 0.012 + side * sgn * r * 3.2, r * 0.75, r * 0.15))
    return union(parts, 0.004)


STATUE_CROWN = dict(c=(0, 0.04, 0.86), radii=(0.3, 0.39), height=0.06, thick=0.03, spikes=9, arc=230.0,
                    spike_len=0.22, tilt=8.0, spike_w=0.055)


def statue_head(mouth=0.0, seed=1):
    """Cabeça das estátuas (unidades da cabeça): barba de comprimento médio, coroa de pontas."""
    return male_head(mouth=mouth, furrow=0.5, beard_len=0.34, beard_w=1.05, beard_top=0.16, crown=STATUE_CROWN,
                     seed=seed)


# Pose do Poseidon em pé (contrapposto, peso na perna direita, em -x)
ST = dict(
    sh_r=(-0.123, 0.004, 0.797), el_r=(-0.245, 0.0, 0.93), wr_r=(-0.214, -0.018, 1.062),
    sh_l=(0.123, 0.004, 0.797), el_l=(0.158, 0.03, 0.632), wr_l=(0.178, -0.1, 0.583),
    hip_r=(-0.08, 0.0, 0.502), kn_r=(-0.07, -0.014, 0.276), an_r=(-0.062, 0.012, 0.05),
    hip_l=(0.08, 0.0, 0.49), kn_l=(0.098, -0.058, 0.272), an_l=(0.106, -0.018, 0.052),
    heel_r=(-0.06, 0.03, 0.0), toe_r=(-0.074, -0.105, 0.0),
    heel_l=(0.104, 0.008, 0.004), toe_l=(0.138, -0.122, 0.0),
    shaft=(-0.226, -0.036),
)


def himation_standing(P):
    """Himátio do Poseidon em pé: enrolado no quadril (rolo torcido na cintura), caindo até as canelas
    em dobras fundas e quase retas, com arcos pendendo do quadril direito para o joelho esquerdo (que
    marca o pano), e a ponta jogada sobre o ombro esquerdo, passando pelas costas, enrolada no antebraço
    e caindo em cascata."""
    kn_l = np.asarray(P["kn_l"])
    skirt = union([
        ellipsoid((0, 0.014, 0.49), (0.114, 0.084, 0.088)),
        _cone(P["hip_r"], along(P["kn_r"], P["an_r"], 0.55), 0.072, 0.05),
        _cone(P["hip_l"], kn_l + (0, -0.008, 0), 0.072, 0.052),
        _cone(kn_l + (0, -0.008, 0), along(P["kn_l"], P["an_l"], 0.6), 0.052, 0.05),
        ellipsoid((0.014, 0.01, 0.31), (0.055, 0.04, 0.17)),
        ellipsoid((0.016, 0.0, 0.2), (0.075, 0.05, 0.1)),               # o pano inteiro entre as pernas
    ], 0.045)

    vert = folds((0.012, 0.0), 15, 1.0, 0.05, 0.5, None, 0.55)

    def vert_folds(p):
        """Dobras verticais (mais fundas embaixo), sumindo no pano da frente de cima, onde ficam os arcos."""
        q = p.reshape(-1, 3)
        z = q[:, 2]
        A = 0.01 + 0.016 * np.clip((0.48 - z) / 0.33, 0, 1)
        arcs_on = smoothstep(-0.02, -0.06, q[:, 1]) * smoothstep(0.27, 0.33, z) * smoothstep(0.13, 0.08, np.abs(q[:, 0] - 0.01))
        return vert(p) * (A * (1 - 0.85 * arcs_on)).reshape(p.shape[:-1])
    skirt = Displace(skirt, vert_folds, 0.026)
    def catenary(p):
        """Dobras em arco no pano da frente, pendendo do quadril direito para o joelho esquerdo."""
        q = p.reshape(-1, 3)
        al = math.radians(-16)
        xr = (q[:, 0] - 0.01) * math.cos(al) + (q[:, 2] - 0.42) * math.sin(al)
        zr = -(q[:, 0] - 0.01) * math.sin(al) + (q[:, 2] - 0.42) * math.cos(al)
        t = (zr - 3.2 * xr * xr) / 0.042
        on = smoothstep(-0.02, -0.06, q[:, 1]) * smoothstep(0.24, 0.3, q[:, 2]) * smoothstep(0.52, 0.47, q[:, 2])
        on = on * smoothstep(0.13, 0.08, np.abs(q[:, 0] - 0.01))
        return (-(locks_relief(t, 1.0, 0.6) - 0.5) * 0.016 * on).reshape(p.shape[:-1])
    skirt = Group(Displace(skirt, catenary, 0.009), [(hem_cut(0.125, 0.012, 6, 0.02, 0.0), "i", 0.012)])
    # rolo torcido na cintura (mais alto do lado da perna de apoio)
    ring = []
    for a in np.linspace(0, 2 * math.pi, 41):
        ring.append((math.sin(a) * 0.118, 0.016 - math.cos(a) * 0.088, 0.532 - 0.02 * math.sin(a) + 0.006 * math.cos(a)))
    roll = tube(ring, 0.024)
    twists = []
    for a in np.linspace(0, 2 * math.pi, 20, endpoint=False):
        c = np.array([math.sin(a) * 0.118, 0.016 - math.cos(a) * 0.088, 0.532 - 0.02 * math.sin(a)])
        out = _unit((math.sin(a), -math.cos(a), 0.0))
        tang = _unit((math.cos(a), math.sin(a), 0.0))
        g = c + out * 0.022
        twists.append(_cone(g - tang * 0.016 - np.array([0, 0, 0.016]), g + tang * 0.016 + np.array([0, 0, 0.016]),
                            0.0045, 0.0045))
    roll = Group(roll, [(union(twists, 0.0), "s", 0.004)])
    # faixa sobre o ombro esquerdo: das costas (quadril direito) pelo ombro até o antebraço
    path = np.array([(-0.08, 0.082, 0.53), (-0.02, 0.094, 0.62), (0.05, 0.09, 0.72), (0.1, 0.062, 0.806),
                     (0.126, 0.012, 0.838), (0.142, -0.03, 0.808), (0.15, -0.038, 0.765)])
    nrm = []
    for p in path:
        n = p - np.array([0.0, 0.01, p[2]])
        if p[2] > 0.76:
            n = p - np.array([0.06, 0.0, 0.76])
        nrm.append(_unit(n))
    tang = np.gradient(path, axis=0)
    strips = []
    for off, w, lift_ in ((0.0, 0.03, 0.006), (0.028, 0.026, 0.0), (-0.028, 0.026, 0.002)):
        lat = np.array([_unit(np.cross(_unit(t), n)) for t, n in zip(tang, nrm)])
        pts = path + lat * off * np.linspace(0.6, 1.0, len(path))[:, None] + np.array(nrm) * lift_
        strips.append(tube(pts, w * np.linspace(1.0, 0.85, len(path)), nrm, 2.8))
    band = union(strips, 0.006)
    # cascata que pende do antebraço esquerdo: pano enrolado no antebraço e caindo largo, com dobras em
    # zigue-zague e a ponta em bico
    el, wr = np.asarray(P["el_l"]), np.asarray(P["wr_l"])
    wrap = _cone(along(el, wr, 0.15), along(el, wr, 0.75), 0.04, 0.034)
    top = np.array([0.18, -0.066, 0.582])
    hang = []
    for k, (dx, dy, L, w) in enumerate(((0.0, 0.0, 0.25, 0.03), (0.026, 0.012, 0.2, 0.026), (-0.024, 0.01, 0.22, 0.026),
                                       (0.012, 0.02, 0.15, 0.024))):
        pts = [top + np.array([dx * (0.3 + 0.7 * i / 9) + 0.007 * math.sin(i * 1.4 + k * 2), dy, -L * i / 9])
               for i in range(10)]
        rad = [w * (1.0 + 0.25 * i / 9) * (1.0 if i < 8 else 0.55) for i in range(10)]
        hang.append(tube(pts, rad, [(0.15 * (k % 2 * 2 - 1), -1, 0.0)] * 10, 2.5))
    cascade = union([wrap, union(hang, 0.005)], 0.02)
    return union([skirt, roll, band, cascade], 0.012)


def plinth(c, half, h=0.04):
    """Plinto baixo com moldura: laje de baixo, cavado (garganta) e laje de cima."""
    c = np.asarray(c, float)
    hx, hy = half
    parts = [box(c + (0, 0, h * 0.2), (hx, hy, h * 0.2), None, 0.006),
             box(c + (0, 0, h * 0.75), (hx - 0.012, hy - 0.012, h * 0.25), None, 0.006),
             box(c + (0, 0, h * 0.48), (hx - 0.02, hy - 0.02, h * 0.1), None, 0.004)]
    return union(parts, 0.004)


def poseidon_standing_sdf():
    """Poseidon em pé no plinto, em contrapposto: torso nu, himátio, braço direito erguido segurando
    o tridente (a ponta de baixo no chão, perto do pé direito), o esquerdo com o antebraço à frente."""
    P = ST
    lift = 0.04                                          # (o plinto embaixo)
    body = union([
        torso(),
        arm(P["sh_r"], P["el_r"], P["wr_r"], -1),
        arm(P["sh_l"], P["el_l"], P["wr_l"], 1),
        leg(P["hip_r"], P["kn_r"], P["an_r"]),
        leg(P["hip_l"], P["kn_l"], P["an_l"]),
    ], 0.03)
    shaft_c = np.array([P["shaft"][0], P["shaft"][1], 1.09])
    hands = [fist(P["wr_r"], shaft_c, (0, 0, 1), -1),
             open_hand(P["wr_l"], (0.12, -0.85, -0.3), (0.15, 0.2, -1.0), 1)]
    feet = [foot(P["an_r"], P["heel_r"], P["toe_r"], -1), foot(P["an_l"], P["heel_l"], P["toe_l"], 1)]
    head = Xform(statue_head(seed=2), None, (0, 0.012, 1.0 - HU), HU)
    fig = union([body, union(hands, 0.0)], 0.012)
    fig = union([fig, union(feet, 0.0)], 0.012)
    fig = union([fig, head], 0.02)
    fig = union([fig, himation_standing(P)], 0.012)
    fig = Xform(fig, None, (0, 0, lift), 1.0)
    base = plinth((-0.04, -0.02, 0.0), (0.21, 0.16), lift)
    return union([fig, base], 0.006)


def poseidon_standing():
    lift = 0.04
    root = poseidon_standing_sdf()
    P = ST
    tri = trident_sdf((P["shaft"][0], P["shaft"][1], lift + 0.0), (P["shaft"][0], P["shaft"][1], lift + 1.28),
                      0.012, 0.085, 0.15)
    imp = spots(((0, -0.02, lift + 0.93), 0.1), ((P["shaft"][0], P["shaft"][1], lift + 1.09), 0.045),
                (np.asarray(P["wr_l"]) + (0, -0.05, lift - 0.01), 0.05), ((-0.07, -0.06, lift + 0.03), 0.06),
                ((0.12, -0.08, lift + 0.03), 0.06), base=0.0)
    body = statue("poseidon_standing", root, 0.0016, 22000, False, None, 0.003, False,
                  plinth((-0.04, -0.02, 0.0), (0.21, 0.16), lift), imp)
    trid = statue("poseidon_standing_trident", tri, 0.0012, 1900, False, tri, 0.003, False)
    _FIELDS["poseidon_standing"] = (union([root, tri], 0.0), tri, 0.003)
    return [body, trid]


def dolphin(head, tail, up, size, side=1, relief=False):
    """Golfinho esculpido (braço do trono): corpo em arco do focinho (head) à cauda (tail), com bico,
    nadadeira de dorso, peitoral e a cauda em leque (em relevo numa parede: a cauda abre no plano da
    parede, para aparecer de lado)."""
    head, tail = np.asarray(head, float), np.asarray(tail, float)
    up = _unit(up)
    ax = _unit(tail - head)
    L = np.linalg.norm(tail - head)
    pts, rad = [], []
    for t in np.linspace(0, 1, 16):
        arch = math.sin(t * math.pi) * L * 0.22
        pts.append(head + ax * L * t + up * arch)
        rad.append(size * (0.35 + 0.65 * math.sin(min(t * 1.6, 1.0) * math.pi * 0.5)) * (1 - 0.75 * t ** 1.5))
    body = tube(pts, rad)
    beak = _cone(head + ax * size * 0.3, head - ax * size * 0.9 - up * size * 0.1, size * 0.45, size * 0.22)
    lat = np.cross(ax, up) * side
    p_dorsal = np.asarray(pts[6]) + up * size * 0.7
    fin = tube([pts[5], p_dorsal + ax * size * 0.4], [size * 0.25, size * 0.06], [lat, lat], 2.5, per=1)
    pec = tube([pts[3], np.asarray(pts[4]) - up * size * 0.9 + lat * size * 0.5], [size * 0.22, size * 0.06],
               [up, up], 2.5, per=1)
    tl = np.asarray(pts[-1])
    spread, flat_n = (up, lat) if relief else (lat, up)
    flukes = [tube([tl, tl + ax * size * 0.5 + spread * size * 0.9 * s + up * size * 0.3], [size * 0.18, size * 0.08],
                   [flat_n, flat_n], 2.6, per=1) for s in (1, -1)]
    eye_ = sphere(head + ax * size * 0.55 + up * size * 0.2 + lat * size * 0.33, size * 0.09)
    return Group(union([body, beak, fin, pec] + flukes, 0.008), [(eye_, "s", 0.002)])


def shell_fan(c, R, n_ribs=13, depth=0.03, thick=0.035, up=(0, 0, 1), fwd=(0, -1, 0)):
    """Leque de concha (vieira): meio disco virado para a frente, com costelas em relevo saindo da
    charneira (c) e a borda recortada em ondas."""
    c = np.asarray(c, float)
    upv, fw = _unit(up), _unit(fwd)
    lat = np.cross(fw, upv)
    M = np.stack([lat, upv, -fw], 1)        # local: x = lado, y = cima, z = para trás

    def f(p):
        q = (p - c) @ M
        x, y, z = q[:, 0], q[:, 1], q[:, 2]
        r = np.sqrt(x * x + np.maximum(y, 0) ** 2)
        ang = np.arctan2(x, np.maximum(y, 1e-6))
        # borda recortada: o raio oscila entre as costelas
        t = ang / (math.pi / n_ribs) + 0.5
        fr = t - np.floor(t)
        edge = R * (1 + 0.04 * np.sin(fr * math.pi))
        # domo da concha (mais alto no meio) e as costelas
        dome = depth * np.sqrt(np.clip(1 - (r / R) ** 2, 0, 1))
        rib = 0.4 * depth * np.sin(fr * math.pi) ** 0.7 * np.clip(r / (0.25 * R), 0, 1)
        front = -(dome + rib)
        dz = np.maximum(z - thick * 0.5, front - z)            # entre o fundo e a frente abaulada
        dr = np.where(y >= 0, r - edge, np.sqrt(x * x + y * y) - R * 0.25)
        dy = -y - R * 0.08
        return np.maximum(np.maximum(dz, dr), dy) * 0.8
    ext = np.abs(M) @ np.array([R * 1.1, R * 1.1, thick + depth * 2])
    return Prim(f, c - ext, c + ext)


# Pose do Poseidon sentado (unidades do corpo; o degrau em z < 0, o assento em z = 0,29)
SEAT = dict(
    dz=-0.17, dy=0.06,                                    # o tronco desce e recua no assento
    sh_r=(-0.123, 0.064, 0.627), el_r=(-0.205, 0.03, 0.49), wr_r=(-0.25, -0.07, 0.565),
    sh_l=(0.123, 0.064, 0.627), el_l=(0.205, 0.05, 0.48), wr_l=(0.214, -0.085, 0.476),
    hip_r=(-0.08, 0.06, 0.33), kn_r=(-0.09, -0.175, 0.33), an_r=(-0.092, -0.19, 0.062),
    hip_l=(0.08, 0.06, 0.33), kn_l=(0.092, -0.16, 0.33), an_l=(0.096, -0.135, 0.062),
    heel_r=(-0.092, -0.17, 0.0), toe_r=(-0.1, -0.3, 0.0),
    heel_l=(0.096, -0.115, 0.0), toe_l=(0.11, -0.245, 0.0),
    shaft=(-0.272, -0.085),
)


def leg_seated(hip, knee, ankle):
    """Perna dobrada (coxa deitada, canela em pé): o quadríceps em cima da coxa, a panturrilha atrás."""
    hip, knee, ankle = (np.asarray(x, float) for x in (hip, knee, ankle))
    parts = [
        limb(hip, knee, 0.068, 0.043),
        limb(knee, ankle, 0.044, 0.024),
        muscle(hip, knee, 0.45, (0.058, 0.055, 0.12), (0, 0, 0.01)),
        muscle(knee, ankle, 0.25, (0.04, 0.042, 0.075), (0, 0.016, 0)),
        sphere(knee + (0, -0.006, 0.006), 0.036),
    ]
    return union(parts, 0.025)


def throne(seat_z=0.29):
    """Trono: bloco do assento com almofada e painéis rebaixados, braços com golfinhos e ondas
    esculpidos, encosto alto terminando num leque de concha, sobre o degrau."""
    parts = [
        box((0, 0.04, seat_z * 0.5), (0.2, 0.15, seat_z * 0.5), None, 0.012),               # assento
        box((0, 0.03, seat_z + 0.012), (0.19, 0.14, 0.014), None, 0.012),                   # almofada
        box((0, 0.185, 0.56), (0.19, 0.03, 0.29), None, 0.012),                             # encosto
        shell_fan((0, 0.16, 0.66), 0.25, 13, 0.035, 0.045),                                  # concha
    ]
    cuts = []
    for s in (1, -1):
        parts.append(box((0.222 * s, 0.03, 0.455), (0.03, 0.15, 0.016), None, 0.012))       # braço
        parts.append(box((0.222 * s, 0.075, 0.37), (0.022, 0.1, 0.085), None, 0.01))        # apoio
        parts.append(dolphin((0.252 * s, -0.15, 0.335), (0.252 * s, 0.11, 0.395), (0, 0, 1), 0.036, s, True))
        cuts.append(box((0.2 * s, 0.04, 0.15), (0.02, 0.11, 0.09), None, 0.01))             # painel
        cuts.append(box((0.0, -0.11, 0.15), (0.15, 0.02, 0.09), None, 0.01))
    # ondas (caracóis) no painel do lado e na frente do assento
    waves = []
    for s in (1, -1):
        for k in range(3):
            c = (0.2 * s + 0.004 * s, -0.04 + 0.075 * k, 0.15)
            waves.append(snail(np.array(c), (s, 0, 0), (0, -1, 0), 0.032, 1.5, -s, 0.5))
    for k in range(4):
        c = (-0.105 + 0.07 * k, -0.11 + 0.004, 0.15)
        waves.append(snail(np.array(c), (0, -1, 0), (1, 0, 0), 0.03, 1.5, 1, 0.5))
    body = Group(union(parts, 0.006), [(union(cuts, 0.0), "s", 0.006)])
    base = union([box((0, -0.05, -0.05), (0.31, 0.33, 0.03), None, 0.01),                  # degrau
                  box((0, -0.04, -0.012), (0.27, 0.3, 0.014), None, 0.008),
                  box((0, -0.235, 0.012), (0.17, 0.08, 0.014), None, 0.008)], 0.004)        # banquinho
    return union([body, union(waves, 0.0), base], 0.006)


def himation_seated(P):
    """Himátio do Poseidon sentado: o rolo na cintura, o pano cobrindo o colo e as pernas, pendendo
    entre os joelhos em dobras fundas até perto dos tornozelos, e a ponta sobre o ombro esquerdo."""
    hip_r, kn_r, an_r = (np.asarray(P[k]) for k in ("hip_r", "kn_r", "an_r"))
    hip_l, kn_l, an_l = (np.asarray(P[k]) for k in ("hip_l", "kn_l", "an_l"))
    lap = union([
        ellipsoid((0, 0.05, 0.345), (0.12, 0.1, 0.07)),
        _cone(hip_r, kn_r, 0.078, 0.056), _cone(hip_l, kn_l, 0.078, 0.056),
        _cone(kn_r, along(kn_r, an_r, 0.8), 0.058, 0.05), _cone(kn_l, along(kn_l, an_l, 0.8), 0.058, 0.05),
        ellipsoid((0.0, -0.1, 0.33), (0.07, 0.09, 0.05)),                                   # pano entre as coxas
        box((0.0, -0.17, 0.2), (0.065, 0.016, 0.12), None, 0.014),                         # cortina entre as canelas
    ], 0.04)

    def zamp(z):
        return 0.008 + 0.014 * np.clip((0.3 - z) / 0.22, 0, 1)
    lap = Displace(lap, folds((0.0, -0.05), 26, 1.0, 0.04, 0.5, zamp, 0.55), 0.022)
    def sag(p):
        """Dobras em U do pano que pende entre os joelhos."""
        q = p.reshape(-1, 3)
        t = (q[:, 2] - 0.345 - 6.0 * q[:, 0] ** 2) / 0.05
        on = smoothstep(-0.13, -0.17, q[:, 1]) * smoothstep(0.08, 0.045, np.abs(q[:, 0])) * smoothstep(0.2, 0.25, q[:, 2])
        return (-(locks_relief(t, 1.0, 0.6) - 0.5) * 0.02 * on).reshape(p.shape[:-1])
    lap = Group(Displace(lap, sag, 0.009), [(hem_cut(0.075, 0.01, 6, 0.0, -0.17), "i", 0.01)])
    ring = []
    for a in np.linspace(0, 2 * math.pi, 41):
        ring.append((math.sin(a) * 0.114, 0.074 - math.cos(a) * 0.086, 0.37 - 0.004 * math.sin(a)))
    roll = tube(ring, 0.022)
    path = np.array([(-0.08, 0.14, 0.36), (-0.02, 0.152, 0.45), (0.05, 0.15, 0.55), (0.1, 0.122, 0.636),
                     (0.126, 0.072, 0.668), (0.142, 0.03, 0.638), (0.15, 0.022, 0.595)])
    nrm = []
    for p in path:
        n = p - np.array([0.0, 0.07, p[2]])
        if p[2] > 0.59:
            n = p - np.array([0.06, 0.06, 0.59])
        nrm.append(_unit(n))
    tang = np.gradient(path, axis=0)
    strips = []
    for off, w, lift_ in ((0.0, 0.03, 0.006), (0.028, 0.026, 0.0), (-0.028, 0.026, 0.002)):
        lat = np.array([_unit(np.cross(_unit(t), n)) for t, n in zip(tang, nrm)])
        pts = path + lat * off * np.linspace(0.6, 1.0, len(path))[:, None] + np.array(nrm) * lift_
        strips.append(tube(pts, w * np.linspace(1.0, 0.85, len(path)), nrm, 2.8))
    return union([lap, roll, union(strips, 0.006)], 0.012)


def poseidon_seated_sdf():
    """Poseidon sentado no trono (como o Zeus de Olímpia): torso nu, himátio cobrindo as pernas, os
    pés no banquinho, a mão direita segurando o tridente em pé ao lado e a esquerda no braço do
    trono."""
    P = SEAT
    up = Xform(torso(), None, (0, P["dy"], P["dz"]), 1.0)
    body = union([
        up,
        arm(P["sh_r"], P["el_r"], P["wr_r"], -1),
        arm(P["sh_l"], P["el_l"], P["wr_l"], 1),
        leg_seated(P["hip_r"], P["kn_r"], P["an_r"]),
        leg_seated(P["hip_l"], P["kn_l"], P["an_l"]),
    ], 0.03)
    shaft_c = np.array([P["shaft"][0], P["shaft"][1], 0.6])
    hands = [fist(P["wr_r"], shaft_c, (0, 0, 1), -1),
             open_hand(P["wr_l"], (0.05, -1.0, -0.15), (0.0, 0.0, -1.0), 1)]
    feet = [foot(P["an_r"], P["heel_r"], P["toe_r"], -1), foot(P["an_l"], P["heel_l"], P["toe_l"], 1)]
    head = Xform(statue_head(seed=4), None, (0, 0.012 + P["dy"], 1.0 - HU + P["dz"]), HU)
    fig = union([body, union(hands, 0.0), union(feet, 0.0)], 0.012)
    fig = union([fig, head], 0.02)
    fig = union([fig, himation_seated(P)], 0.012)
    return union([fig, throne()], 0.008)


def poseidon_seated():
    P = SEAT
    root = poseidon_seated_sdf()
    hard = throne()
    tri = trident_sdf((P["shaft"][0], P["shaft"][1], -0.02), (P["shaft"][0], P["shaft"][1], 1.0), 0.012, 0.08, 0.14)
    imp = spots(((0, 0.04, 0.76), 0.1), ((P["shaft"][0], P["shaft"][1], 0.6), 0.045),
                (np.asarray(P["wr_l"]) + (0, -0.04, 0), 0.05), ((-0.09, -0.24, 0.03), 0.06),
                ((0.1, -0.19, 0.03), 0.06), base=0.0)
    body = statue("poseidon_seated", root, 0.0016, 22000, False, None, 0.003, False, hard, imp)
    trid = statue("poseidon_seated_trident", tri, 0.0012, 1800, False, tri, 0.003, False)
    _FIELDS["poseidon_seated"] = (union([root, tri], 0.0), tri, 0.003)
    return [body, trid]


# ---------------------------------------------------------------------------
# Busto da deusa (Anfitrite): unidades da cabeça (queixo em z = 0, alto do crânio em z = 1)
# ---------------------------------------------------------------------------
def female_face():
    """Rosto sereno de traços clássicos: oval, testa lisa, sobrancelhas em arco suave, nariz reto,
    olhos amendoados de pálpebra pesada olhando um pouco para baixo, lábios cheios com o arco do
    cupido, queixo arredondado."""
    base = union([
        ellipsoid((0, 0.06, 0.62), (0.3, 0.42, 0.39)),
        ellipsoid((0, -0.15, 0.7), (0.235, 0.21, 0.17)),
        ellipsoid((0, -0.1, 0.42), (0.285, 0.3, 0.32)),
        ellipsoid((0, -0.12, 0.2), (0.24, 0.26, 0.18), rot(("x", -12))),
        ellipsoid((0, -0.16, 0.3), (0.25, 0.24, 0.15)),
        ellipsoid((0, -0.27, 0.22), (0.13, 0.135, 0.115)),
        ellipsoid((0, -0.305, 0.08), (0.088, 0.075, 0.074)),
    ], 0.09)
    adds = []
    for s in (1, -1):
        adds.append(ellipsoid((0.165 * s, -0.27, 0.36), (0.105, 0.075, 0.1)))
    s_ = np.linspace(0, 1, 13)
    bx = 0.035 + 0.215 * s_
    bz = 0.572 + 0.026 * np.sin(s_ * math.pi * 0.85) - 0.02 * s_ ** 2
    brow = tube(np.stack([bx, -0.37 + 0.15 * (bx / 0.27) ** 2.2, bz], 1),
                0.017 * (1 - 0.4 * s_ ** 2))
    adds += [brow, mirror_x(brow)]
    nose = union([
        _cone((0, -0.37, 0.55), (0, -0.452, 0.35), 0.025, 0.031),
        sphere((0, -0.455, 0.338), 0.033),
        ellipsoid((0.037, -0.413, 0.32), (0.029, 0.03, 0.026)),
        ellipsoid((-0.037, -0.413, 0.32), (0.029, 0.03, 0.026)),
    ], 0.022)
    sock = ellipsoid((0.135, -0.42, 0.5), (0.1, 0.06, 0.05), rot(("z", 20)))
    nos = ellipsoid((0.022, -0.448, 0.302), (0.011, 0.016, 0.009))
    face = Group(base, [(union(adds, 0.0), "u", 0.05), (union([sock, mirror_x(sock)], 0.0), "s", 0.04),
                        (nose, "u", 0.025), (union([nos, mirror_x(nos)], 0.0), "s", 0.006)])
    eyes = [eye(s, c=(0.135, -0.352, 0.5), R=0.075, w=0.128, h_up=0.027, h_low=0.02, lid=0.009,
                gaze=(0, -1, -0.16), iris=0.024) for s in (1, -1)]
    face = Group(face, [(union(eyes, 0.0), "u", 0.01)])
    # Lábios: o de cima com o arco do cupido, o de baixo mais cheio, a fenda e os cantos
    xs = np.linspace(-0.082, 0.082, 15)
    up = [(x, -0.412 - 0.02 * (1 - (x / 0.082) ** 2), 0.226 + 0.012 * (1 - (x / 0.082) ** 2)
           - 0.006 * math.exp(-(x / 0.012) ** 2) + 0.004 * math.exp(-((abs(x) - 0.022) / 0.012) ** 2)) for x in xs]
    lips = union([tube(up, [0.009 + 0.013 * (1 - (x / 0.082) ** 2) for x in xs]),
                  ellipsoid((0, -0.424, 0.19), (0.058, 0.03, 0.026))], 0.01)
    slit = tube([(x, -0.44 - 0.012 * (1 - (x / 0.08) ** 2), 0.212 + 0.004 * (1 - (x / 0.08) ** 2))
                 for x in np.linspace(-0.08, 0.08, 9)], 0.004)
    corners = [sphere((0.084 * s, -0.405, 0.214), 0.009) for s in (1, -1)]
    return Group(face, [(lips, "u", 0.02), (slit, "s", 0.004), (union(corners, 0.0), "s", 0.006)])


GODDESS_HAIR_C = np.array([0.0, 0.05, 0.62])
GODDESS_HAIR_R = np.array([0.335, 0.465, 0.425])


def goddess_hairline():
    """Linha do cabelo da deusa: testa alta no meio, descendo em ondas pelas têmporas sobre as
    orelhas até a nuca."""
    pts = np.array([[0.0, 0.8], [0.45, 0.74], [0.95, 0.6], [1.4, 0.42], [1.9, 0.36], [2.5, 0.3], [math.pi, 0.28]])

    def f(p):
        phi = np.abs(np.arctan2(p[:, 0], -(p[:, 1] - 0.05)))
        return (np.interp(phi, pts[:, 0], pts[:, 1]) - p[:, 2]) * 0.8
    return Prim(f, (-BIG, -BIG, -BIG), (BIG, BIG, BIG))


def goddess_hair():
    """Cabelo repartido no meio: dois rolos largos saindo da risca e emoldurando a testa até as
    têmporas, o resto em ondas largas descendo pelos lados (cobrindo as orelhas) e voltando para o
    coque torcido na nuca, e uma mecha grossa e ondulada de cada lado descendo pelo pescoço até o
    ombro."""
    c = GODDESS_HAIR_C

    def relief(p):
        q = p.reshape(-1, 3)
        psi = np.arctan2(np.abs(q[:, 0]), q[:, 2] - 0.5)
        t = (q[:, 1] + 0.04 * np.sin(psi * 5.0)) / 0.11
        rel = locks_relief(t, 0.022, 0.7)
        part = 0.022 * np.exp(-(q[:, 0] / 0.02) ** 2) * smoothstep(0.75, 0.9, q[:, 2]) * smoothstep(0.3, 0.0, q[:, 1])
        return (-(rel - 0.011) + part).reshape(p.shape[:-1])
    cap = union([ellipsoid(c, GODDESS_HAIR_R),
                 ellipsoid((0.27, 0.03, 0.5), (0.1, 0.24, 0.17)), ellipsoid((-0.27, 0.03, 0.5), (0.1, 0.24, 0.17))], 0.06)
    cap = Displace(cap, relief, 0.02)
    cap = Group(cap, [(goddess_hairline(), "i", 0.04)])
    # Rolos da frente: da risca, sobre a testa, até as têmporas
    rolls = []
    for s_ in (1, -1):
        pts = []
        for t in np.linspace(0, 1, 13):
            ang = t * 1.45
            pts.append((s_ * (0.02 + 0.3 * math.sin(ang)), -0.36 * math.cos(ang) + 0.1 * t - 0.02, 0.79 - 0.2 * t ** 1.6))
        roll = tube(pts, np.linspace(0.045, 0.06, 13))
        grooves = []
        for k in range(9):
            t = (k + 0.5) / 9
            ang = t * 1.45
            cc = np.array([s_ * (0.02 + 0.3 * math.sin(ang)), -0.36 * math.cos(ang) + 0.1 * t - 0.02, 0.79 - 0.2 * t ** 1.6])
            dirv = _unit((s_ * math.cos(ang) * 0.3, math.sin(ang) * 0.36 + 0.1, -0.32 * t ** 0.6))
            up = np.array([0, 0, 1.0])
            grooves.append(_cone(cc + up * 0.06 + dirv * 0.03, cc - up * 0.06 - dirv * 0.03, 0.006, 0.006))
        rolls.append(Group(roll, [(union(grooves, 0.0), "s", 0.006)]))
    # Coque torcido na nuca
    bun_c = np.array([0.0, 0.43, 0.5])

    def twist(p):
        q = p.reshape(-1, 3) - bun_c
        ang = np.arctan2(q[:, 0], q[:, 2])
        t = (ang * 3 / (2 * math.pi) + q[:, 1] * 9.0)
        return (-(locks_relief(t, 0.018, 0.6) - 0.009)).reshape(p.shape[:-1])
    bun = Displace(ellipsoid(bun_c, (0.15, 0.11, 0.12)), twist, 0.02)
    # Mecha grossa e ondulada de cada lado: de trás da orelha, encostada no pescoço, até o ombro,
    # com o sulco torcido em espiral
    falls = []
    for s_ in (1, -1):
        pts, rad = [], []
        for i in range(17):
            t = i / 16
            pts.append((s_ * (0.25 - 0.02 * math.sin(t * math.pi) + 0.1 * t ** 2.5),
                        0.12 - 0.05 * t + 0.035 * math.sin(t * 3 * math.pi), 0.42 - 0.66 * t))
            rad.append(0.056 - 0.02 * t)
        pts = np.array(pts)
        lock_ = tube(pts, rad)
        groove = []
        for i in range(40):
            t = i / 39
            j = t * 16
            k0 = min(int(j), 15)
            f = j - k0
            cc = pts[k0] * (1 - f) + pts[k0 + 1] * f
            r = (rad[k0] * (1 - f) + rad[k0 + 1] * f)
            ang = t * 5 * 2 * math.pi
            groove.append(cc + r * np.array([math.cos(ang) * s_, math.sin(ang) * 0.9, 0.0]) * 0.95)
        falls.append(Group(lock_, [(tube(groove, 0.009), "s", 0.006)]))
    return union([cap, union(rolls, 0.0), bun, union(falls, 0.0)], 0.02)


def diadem():
    """Diadema (stephane) em crescente sobre a testa: alto no meio e baixando para os lados, com um
    friso na borda de cima, uma concha de vieira grande na frente e ondas em caracol dos lados."""
    c = np.array([0.0, 0.05, 0.74])
    a, b = 0.355, 0.445
    R = rot(("x", -7))

    def height(ang):
        # (crescente baixo e fino: alto demais, de frente o ouro cobria o alto da cabeça como uma touca)
        return 0.03 + 0.065 * np.clip(1 - ang / 1.75, 0, 1) ** 1.5

    def band_f(p):
        q = (p - c) @ R
        k0 = np.sqrt((q[:, 0] / a) ** 2 + (q[:, 1] / b) ** 2)
        k1 = np.sqrt((q[:, 0] / a ** 2) ** 2 + (q[:, 1] / b ** 2) ** 2)
        de = k0 * (k0 - 1) / np.maximum(k1, 1e-9)
        ang = np.abs(np.arctan2(q[:, 0], -q[:, 1]))
        dz = np.maximum(-q[:, 2], q[:, 2] - height(ang))
        dr = np.abs(de - 0.012) - 0.011
        return np.maximum(np.maximum(dr, dz), (ang - 2.0) * 0.2)
    ext = np.array([a + 0.03, b + 0.03, 0.24])
    parts = [Prim(band_f, c - ext, c + ext)]
    rim = []
    for ang in np.linspace(-1.95, 1.95, 31):
        d = np.array([math.sin(ang) * (a + 0.016), -math.cos(ang) * (b + 0.016), float(height(abs(ang)))])
        rim.append(c + R @ d)
    parts.append(tube(rim, 0.012))
    front = c + R @ np.array([0, -b - 0.025, 0.05])
    parts.append(shell_fan(front, 0.085, 11, 0.026, 0.022, R @ np.array([0, 0, 1.0]), R @ np.array([0, -1.0, 0])))
    for s_ in (1, -1):
        for k in range(3):
            ang = (0.55 + 0.38 * k) * s_
            hk = float(height(abs(ang)))
            pos = c + R @ np.array([math.sin(ang) * (a + 0.028), -math.cos(ang) * (b + 0.028), hk * 0.45])
            nrm = R @ _unit((math.sin(ang) / a, -math.cos(ang) / b, 0.0))
            parts.append(snail(pos, nrm, R @ np.array([0, 0, 1.0]), max(0.045 - 0.007 * k, 0.026), 1.5, s_, 0.55))
    return union(parts, 0.006)


def goddess_bust():
    """Ombros e o começo do peito vestidos com o quíton (decote arredondado com a barra enrolada,
    alfinetes nos ombros, poucas dobras pendendo em arcos na frente e caindo pelos ombros), cortados em
    arco embaixo e encaixados na base moldurada."""
    body = union([
        ellipsoid((0, 0.08, -0.46), (0.6, 0.3, 0.28)),                            # ombros e peito
        ellipsoid((0, -0.02, -0.55), (0.42, 0.26, 0.25)),                         # peito
        ellipsoid((0.52, 0.06, -0.42), (0.16, 0.2, 0.17)),
        ellipsoid((-0.52, 0.06, -0.42), (0.16, 0.2, 0.17)),
    ], 0.1)

    def chiton(p):
        q = p.reshape(-1, 3)
        x, y, z = q[:, 0], q[:, 1], q[:, 2]
        t = (z + 0.31 - 1.1 * x * x) / 0.1
        arcs = (locks_relief(t, 1.0, 0.6) - 0.5) * smoothstep(-0.08, -0.16, y) * smoothstep(0.36, 0.22, np.abs(x)) \
            * smoothstep(-0.27, -0.36, z) * smoothstep(-0.72, -0.62, z)
        t2 = (y + 0.02 * np.sin(z * 18)) / 0.07
        side = (locks_relief(t2, 1.0, 0.55) - 0.5) * smoothstep(0.36, 0.46, np.abs(x)) * smoothstep(-0.3, -0.4, z)
        return (-(arcs * 0.026 + side * 0.016)).reshape(p.shape[:-1])
    dress = Displace(Offset(body, 0.012), chiton, 0.022)
    neckline = []
    for t in np.linspace(-1, 1, 21):
        ang = t * 1.35
        neckline.append((math.sin(ang) * 0.3, 0.06 - math.cos(ang) * 0.27 * (1 - 0.15 * t * t),
                         -0.2 - 0.12 * math.cos(ang * 0.8) ** 2))
    collar = tube(neckline, 0.022)
    open_ = ellipsoid((0, -0.06, -0.19), (0.29, 0.34, 0.22))
    dress = Group(dress, [(open_, "s", 0.02)])
    pins = [sphere((0.4 * s_, -0.02, -0.27), 0.036) for s_ in (1, -1)]
    torso_ = union([body, dress, collar, union(pins, 0.0)], 0.01)
    cut = Prim(lambda p: (-0.8 + 0.2 * np.clip(np.abs(p[:, 0]) / 0.62, 0, 1) ** 2 - p[:, 2]) * 0.9,
               (-BIG, -BIG, -BIG), (BIG, BIG, BIG))
    return Group(torso_, [(cut, "i", 0.02)])


def goddess_socle():
    """Base moldurada do busto (toro, escócia e o fuste curto)."""
    return lathe((0, 0.05, -1.12), [(0.0, 0.0), (0.42, 0.0), (0.42, 0.06), (0.38, 0.08), (0.36, 0.1), (0.3, 0.13),
                                    (0.26, 0.15), (0.24, 0.26), (0.27, 0.29), (0.3, 0.31), (0.3, 0.34), (0.0, 0.34)])


def goddess_sdf():
    """A deusa inteira: cabeça (rosto, cabelo, diadema) presa no pescoço curto e grosso, o busto
    vestido e a base, numa peça só."""
    head = union([female_face(), goddess_hair()], 0.015)
    head = Group(head, [(diadem(), "u", 0.006)])
    neck = union([_cone((0, 0.09, 0.3), (0, 0.06, -0.24), 0.17, 0.2),
                  ellipsoid((0, -0.04, 0.02), (0.14, 0.13, 0.12))], 0.06)
    return union([union([head, neck], 0.07), goddess_bust(), goddess_socle()], 0.03)


def goddess_head():
    """Busto colossal da deusa nas ruínas."""
    root = goddess_sdf()
    imp = spots(((0, -0.3, 0.42), 0.3), base=0.0)
    return [statue("goddess_head", root, 0.006, 19800, True, diadem(), 0.008, True, goddess_socle(), imp, 0.45)]


# ---------------------------------------------------------------------------
# Montagem: malha reduzida e pintura (cor de vértice)
# ---------------------------------------------------------------------------
_FIELDS = {}   # nome -> (campo, campo do dourado ou None, escala da oclusão)
GOLD = (0.85, 0.62, 0.2)


def sdf_normals(root, V, eps):
    """Normais pelo gradiente do campo (diferenças centrais)."""
    offs = np.eye(3) * eps
    P = np.concatenate([V + o for o in offs] + [V - o for o in offs])
    d = sdf_points(root, P, band=eps * 4).reshape(6, -1)
    g = np.stack([d[0] - d[3], d[1] - d[4], d[2] - d[5]], 1)
    return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)


def sdf_ao(root, V, n, scale, steps=5, tilt=40.0, ring=6):
    """Oclusão medida no campo: em passos que dobram a partir de `scale` (sulcos finos até
    reentrâncias largas), o quanto o campo fica abaixo da distância andada, ao longo da normal e de
    `ring` direções inclinadas `tilt` graus em volta dela (o fundo de uma cavidade, de frente para a
    abertura, fica escuro pelos lados); 0 = livre, 1 = fechado."""
    n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    helper = np.where(np.abs(n[:, 2:3]) < 0.9, np.array([[0, 0, 1.0]]), np.array([[1.0, 0, 0]]))
    t1 = np.cross(n, helper)
    t1 /= np.maximum(np.linalg.norm(t1, axis=1, keepdims=True), 1e-9)
    t2 = np.cross(n, t1)
    ct, st = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))
    dirs = [(n, 0.5)]
    for k in range(ring):
        a = 2 * math.pi * k / ring
        dirs.append((n * ct + (t1 * math.cos(a) + t2 * math.sin(a)) * st, 0.5 / ring))
    occ = np.zeros(len(V))
    for d_, wd in dirs:
        o = np.zeros(len(V))
        wsum = 0.0
        for i in range(steps):
            delta = scale * (2 ** i)
            d = sdf_points(root, (V + d_ * delta).astype(F), band=delta * 1.5)
            w = 1.0 / (1.3 ** i)
            o += w * np.clip((delta - d) / delta, 0, 1)
            wsum += w
        occ += wd * o / wsum
    return occ


def stone_paint(name):
    """Pintura da estátua: branco na pedra, escurecido pela oclusão nas reentrâncias (mechas, dobras,
    olhos, boca) e dourado nas peças de ouro (coroa, tridente, tiara)."""
    def paint(me):
        n = len(me.vertices)
        V = np.empty(n * 3, np.float32)
        me.vertices.foreach_get("co", V)
        V = V.reshape(-1, 3).astype(F)
        cols = np.ones((n, 4), np.float32)
        spec = _FIELDS.get(name)
        if spec is not None:
            root, gold, scale = spec[:3]
            nrm = sdf_normals(root, V, scale * 0.5).astype(F)
            occ = sdf_ao(root, V, nrm, scale)
            ao = 1 - occ
            # o que é quase livre fica branco; sulcos até ~0,4; as cavidades fundas quase pretas
            shade = np.interp(occ, (0.0, 0.12, 0.5, 0.85), (1.0, 1.0, 0.4, 0.08))
            if len(spec) > 3 and spec[3] is not None:
                # sombra de uma cavidade larga demais para a oclusão (a boca aberta): mais escura quanto
                # mais para dentro do volume `dark`
                deep, ramp = spec[3]
                m = np.clip(-sdf_points(deep, V, band=ramp * 2) / ramp, 0, 1)
                shade = shade * (1 - 0.9 * m)
            cols[:, :3] = shade[:, None]
            if gold is not None:
                dg = sdf_points(gold, V, band=scale * 4)
                gm = np.clip((scale * 0.9 - dg) / (scale * 0.5), 0, 1)[:, None]
                gc = np.array(GOLD, np.float32)[None] * (0.72 + 0.28 * ao[:, None])
                cols[:, :3] = cols[:, :3] * (1 - gm) + gc * gm
        attr = me.color_attributes.new(name="Color", type="BYTE_COLOR", domain="POINT")
        attr.data.foreach_set("color", cols.ravel())
        me.color_attributes.active_color = attr
    return paint


LOWRES = False  # (prévia rápida: grade mais grossa)


def mark_hard(obj, hard, tol, angle=32.0):
    """Arestas vivas (normais divididas no .glb) onde a malha passa pelas peças duras `hard` (trono,
    degrau, plinto) e a dobra entre as faces passa de `angle` graus: as faces planas ficam lisas no
    toon, sem o degradê que a normal suave puxaria da quina."""
    me = obj.data
    n = len(me.vertices)
    V = np.empty(n * 3, np.float32)
    me.vertices.foreach_get("co", V)
    on = np.abs(sdf_points(hard, V.reshape(-1, 3).astype(F), band=tol * 4)) < tol
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    sharp = np.zeros(len(bm.edges), bool)
    lim = math.radians(angle)
    for e in bm.edges:
        if on[e.verts[0].index] and on[e.verts[1].index] and e.is_manifold and e.calc_face_angle(0.0) > lim:
            sharp[e.index] = True
    bm.free()
    attr = me.attributes.get("sharp_edge") or me.attributes.new("sharp_edge", "BOOLEAN", "EDGE")
    attr.data.foreach_set("value", sharp)
    return int(sharp.sum())


def spots(*balls, base=0.0):
    """Importância para a redução: 1 dentro das esferas (centro, raio) caindo até `base` no dobro do
    raio."""
    def f(V):
        w = np.full(len(V), base, F)
        for c, r in balls:
            d = np.linalg.norm(V - np.asarray(c, F), axis=1)
            w = np.maximum(w, base + (1 - base) * np.clip(2 - d / r, 0, 1))
        return w
    return f


def statue(name, root, h, tris, symmetric=False, gold=None, ao=0.01, register=True, hard=None, importance=None,
           share=0.4, dark=None):
    """Malha do campo `root` (grade de passo h), reduzida até `tris` triângulos (com mais detalhe onde
    `importance` vale 1); guarda o campo para a pintura (register); `hard` = campo das peças duras
    (arestas vivas)."""
    if LOWRES:
        h *= 1.7
    obj = sdf_object(name, root, h)
    decimate(obj, tris, symmetric, importance, share)
    clean_mesh(obj)
    repair(obj.data)            # (a redução às vezes cola as duas faces de uma fresta fina)
    if hard is not None:
        mark_hard(obj, hard, h * 1.5)
    if register:
        _FIELDS[name] = (root, gold, ao, dark)
    return obj


# nome: construtor, metros por unidade, triângulos, base apoiada em z = 0, pintura (cor de vértice)
MODELS = {
    "poseidon_face": dict(build=poseidon_face, size=16.5, tris=24000, base=True, paint=stone_paint("poseidon_face")),
    "poseidon_standing": dict(build=poseidon_standing, size=9.6, tris=24000, base=True,
                              paint=stone_paint("poseidon_standing")),
    "poseidon_seated": dict(build=poseidon_seated, size=8.4, tris=24000, base=True, paint=stone_paint("poseidon_seated")),
    "goddess_head": dict(build=goddess_head, size=3.57, tris=20000, base=True, paint=stone_paint("goddess_head")),
}
