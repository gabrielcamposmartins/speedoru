"""Bichos de pelúcia da Rainbow Raceway (ursinho acenando, ursinho abraçando um coração, coelhinho
acenando), em unidades da peça: frente para -Y, z para cima, sentados com a base em z = 0 e ~1 de
altura.

Modelagem com metabolas (o corpo, a cabeça, as bochechas, o focinho, as orelhas, os braços, as pernas
e os pés se fundem num corpo só, macio como o de uma pelúcia), convertidas em malha; olhos, nariz,
boca, laço e coração são peças à parte encaixadas.

Cor de vértice (atributo "Color", por ponto, RGBA) para o shader (plush.gdshader):
  R = peso do aceno: 1 no braço que acena (subindo suave desde o ombro), 0 no resto;
  G = parte clara (focinho, barriga, dentro das orelhas, solas dos pés, palmas): cor do pelo clareada;
  B = escuro (olhos, nariz, boca);
  A = destaque (laço no pescoço, coração abraçado): a cor de destaque da instância.
O ombro do braço que acena fica em SHOULDER[nome] (unidades da peça), para o shader girar em volta dele.
"""
import math

import bmesh
import bpy
from mathutils import Quaternion, Vector

# Ombro do braço que acena (unidades da peça, Blender: x, y, z)
SHOULDER = {
    "bear_wave": (-0.215, -0.02, 0.5),
    "bunny_wave": (-0.19, -0.02, 0.45),
    "bear_hug": (0.0, -0.05, 0.48),
}


def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


# Com limiar baixo cada elemento aparece com ~0,88 do raio e os campos se somam até o raio inteiro:
# as partes vizinhas se fundem macias. RADIUS compensa (o raio pedido é o que aparece).
THRESHOLD = 0.1
RADIUS = 1.13


def _quat_to(direction):
    """Rotação que leva o eixo X para `direction` (as cápsulas das metabolas são ao longo de X)."""
    d = Vector(direction).normalized()
    return Vector((1, 0, 0)).rotation_difference(d)


def _capsule(mb, a, b, radius, stiffness=2.0):
    a = Vector(a)
    b = Vector(b)
    el = mb.elements.new(type="CAPSULE")
    el.co = (a + b) * 0.5
    el.radius = radius * RADIUS
    el.size_x = (b - a).length * 0.5
    el.rotation = _quat_to(b - a)
    el.stiffness = stiffness
    return el


def _ball(mb, c, radius, stiffness=2.0):
    el = mb.elements.new(type="BALL")
    el.co = c
    el.radius = radius * RADIUS
    el.stiffness = stiffness
    return el


def _ellipsoid(mb, c, radius, size, stiffness=2.0, rot=None):
    el = mb.elements.new(type="ELLIPSOID")
    el.co = c
    el.radius = radius * RADIUS
    el.size_x, el.size_y, el.size_z = size
    el.stiffness = stiffness
    if rot is not None:
        el.rotation = rot
    return el


def _meta_to_mesh(name, build, resolution=0.012):
    data = bpy.data.metaballs.new(name + "_meta")
    data.resolution = resolution
    data.render_resolution = resolution
    data.threshold = THRESHOLD
    build(data)
    obj = bpy.data.objects.new(name + "_meta", data)
    bpy.context.scene.collection.objects.link(obj)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    bpy.data.objects.remove(obj)
    out = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(out)
    return out


def _sphere(name, center, radius, scale=(1, 1, 1), segs=20, rings=12):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2])) + Vector(center)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _heart(name, center, size, depth, facing=(0, -1, 0)):
    """Coração com volume (prisma arredondado nas bordas) de pé, virado para `facing`."""
    pts = []
    n = 48
    for k in range(n):
        t = 2 * math.pi * k / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((x / 32.0 * size, (y + 2.5) / 32.0 * size))
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = 5
    layers = []
    for r in range(rings + 1):
        a = math.pi * r / rings - math.pi * 0.5
        z = math.sin(a) * depth * 0.5
        s = 0.55 + 0.45 * math.cos(a)
        layers.append([bm.verts.new((x * s, z, y * s)) for x, y in pts])
    for r in range(rings):
        for k in range(n):
            k1 = (k + 1) % n
            bm.faces.new((layers[r][k], layers[r][k1], layers[r + 1][k1], layers[r + 1][k]))
    bm.faces.new(layers[0])
    bm.faces.new(list(reversed(layers[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    rot = Vector((0, -1, 0)).rotation_difference(Vector(facing))
    for v in bm.verts:
        v.co = rot @ v.co + Vector(center)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _arm_weight(co, shoulder, hand, reach=0.13):
    """Peso do aceno: sobe do ombro para a mão, só perto do braço (distância ao segmento < reach)."""
    a = Vector(shoulder)
    b = Vector(hand)
    ab = b - a
    t = max(0.0, min(1.0, (Vector(co) - a).dot(ab) / ab.length_squared))
    d = (Vector(co) - (a + ab * t)).length
    return smooth(0.0, 0.35, t) * (1.0 - smooth(reach * 0.8, reach * 1.15, d))


def _paint(obj, fn):
    me = obj.data
    col = me.color_attributes.new(name="Color", type="BYTE_COLOR", domain="POINT")
    rgba = []
    for v in me.vertices:
        rgba.extend(fn(v.co))
    col.data.foreach_set("color", rgba)
    me.color_attributes.active_color = col


def _solid(obj, r=0.0, g=0.0, b=0.0, a=0.0):
    _paint(obj, lambda co: (r, g, b, a))


# ---------------------------------------------------------------------------
# Ursinho
# ---------------------------------------------------------------------------
def _bear_body(mb, pose):
    # Tronco (sentado), barriga e quadril
    _ellipsoid(mb, (0, 0.0, 0.3), 0.25, (1.0, 0.9, 1.15))
    _ball(mb, (0, -0.07, 0.25), 0.19)
    _ellipsoid(mb, (0, 0.02, 0.14), 0.22, (1.15, 1.0, 0.6))
    # Cabeça grande, bochechas e focinho
    _ball(mb, (0, -0.02, 0.72), 0.25)
    for s in (-1, 1):
        _ball(mb, (0.11 * s, -0.13, 0.65), 0.11, 1.6)
    _ellipsoid(mb, (0, -0.21, 0.645), 0.1, (1.25, 0.85, 0.8))
    # Orelhas redondas
    for s in (-1, 1):
        _ellipsoid(mb, (0.195 * s, 0.0, 0.93), 0.095, (1.0, 0.62, 1.0), 2.4)
    # Pernas para a frente e os pés de sola virada para a frente
    for s in (-1, 1):
        _capsule(mb, (0.13 * s, -0.08, 0.12), (0.155 * s, -0.33, 0.1), 0.1)
        _ellipsoid(mb, (0.16 * s, -0.385, 0.12), 0.105, (0.95, 0.72, 1.1))
    # Rabinho
    _ball(mb, (0, 0.27, 0.13), 0.06, 1.6)
    # Braços
    if pose == "wave":
        _capsule(mb, (0.215, -0.02, 0.48), (0.22, -0.2, 0.3), 0.075)
        _ball(mb, (0.22, -0.22, 0.28), 0.08)
        _capsule(mb, (-0.215, -0.02, 0.5), (-0.37, -0.07, 0.76), 0.075)
        _ball(mb, (-0.385, -0.075, 0.79), 0.085)
    else:  # abraçando: os dois braços para a frente, em volta do coração
        for s in (-1, 1):
            _capsule(mb, (0.21 * s, -0.04, 0.48), (0.13 * s, -0.27, 0.42), 0.074)
            _ball(mb, (0.1 * s, -0.29, 0.42), 0.078)


def _bear_paint(pose):
    shoulder = Vector(SHOULDER["bear_wave"])

    def fn(co):
        x, y, z = co
        light = 0.0
        # Focinho
        d = (Vector((x, y, z)) - Vector((0, -0.24, 0.64))).length
        light = max(light, 1.0 - smooth(0.085, 0.115, d))
        # Barriga (oval na frente)
        if y < -0.05:
            e = math.hypot(x / 0.14, (z - 0.29) / 0.17)
            light = max(light, 1.0 - smooth(0.85, 1.05, e))
        # Dentro das orelhas (face da frente)
        for s in (-1, 1):
            d = math.hypot(x - 0.195 * s, z - 0.93)
            if y < -0.02:
                light = max(light, 1.0 - smooth(0.045, 0.065, d))
        # Solas dos pés (face da frente)
        for s in (-1, 1):
            if y < -0.43:
                d = math.hypot((x - 0.16 * s) / 0.8, (z - 0.12) / 1.0)
                light = max(light, 1.0 - smooth(0.06, 0.08, d))
        # Palma da mão que acena
        wave = 0.0
        if pose == "wave":
            wave = _arm_weight(co, shoulder, (-0.385, -0.075, 0.79))
            d = (Vector((x, y, z)) - Vector((-0.39, -0.14, 0.8))).length
            light = max(light, 1.0 - smooth(0.045, 0.06, d))
        return (wave, light, 0.0, 0.0)
    return fn


def _face(prefix, eye_y=-0.243, eye_z=0.76, eye_x=0.085, nose=(0, -0.305, 0.675), nose_r=0.034):
    parts = []
    for s in (-1, 1):
        eye = _sphere(prefix + "_eye%d" % s, (eye_x * s, eye_y, eye_z), 0.033, (1.0, 0.7, 1.15))
        _solid(eye, b=1.0)
        hl = _sphere(prefix + "_hl%d" % s, (eye_x * s + 0.012, eye_y - 0.022, eye_z + 0.014), 0.011, segs=8, rings=6)
        _solid(hl, g=1.0)
        parts += [eye, hl]
    n = _sphere(prefix + "_nose", nose, nose_r, (1.35, 0.85, 0.9))
    _solid(n, b=1.0)
    # Boquinha: dois arcos (tubos finos) em "w" debaixo do nariz
    for s in (-1, 1):
        me = bpy.data.meshes.new(prefix + "_mouth%d" % s)
        bm = bmesh.new()
        ring = []
        for k in range(9):
            t = k / 8.0
            a = math.pi * (1.0 + t)
            ring.append(Vector((nose[0] + s * (0.022 + 0.022 * math.cos(a)), nose[1] + 0.012, nose[2] - 0.045 + 0.02 * math.sin(a))))
        verts = []
        for k, c in enumerate(ring):
            row = []
            for q in range(6):
                b = 2 * math.pi * q / 6
                row.append(bm.verts.new(c + Vector((0, math.cos(b) * 0.005, math.sin(b) * 0.005))))
            verts.append(row)
        for k in range(len(verts) - 1):
            for q in range(6):
                q1 = (q + 1) % 6
                bm.faces.new((verts[k][q], verts[k][q1], verts[k + 1][q1], verts[k + 1][q]))
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new(me.name, me)
        bpy.context.scene.collection.objects.link(o)
        _solid(o, b=1.0)
        parts.append(o)
    return parts


def _bow(prefix, center, size=0.07, wave_weight=0.0):
    parts = []
    cx, cy, cz = center
    for s in (-1, 1):
        lobe = _sphere(prefix + "_bow%d" % s, (cx + s * size * 0.85, cy, cz), size, (1.0, 0.55, 0.7))
        _solid(lobe, r=wave_weight, a=1.0)
        parts.append(lobe)
    knot = _sphere(prefix + "_knot", (cx, cy - 0.01, cz), size * 0.42)
    _solid(knot, r=wave_weight, a=1.0)
    parts.append(knot)
    return parts


def bear_wave():
    body = _meta_to_mesh("bear_wave", lambda mb: _bear_body(mb, "wave"))
    _paint(body, _bear_paint("wave"))
    return [body] + _face("bw") + _bow("bw", (0, -0.17, 0.49), 0.075)


def bear_hug():
    body = _meta_to_mesh("bear_hug", lambda mb: _bear_body(mb, "hug"))
    _paint(body, _bear_paint("hug"))
    heart = _heart("bh_heart", (0, -0.3, 0.36), 0.36, 0.11)
    _solid(heart, a=1.0)
    return [body] + _face("bh") + [heart]


# ---------------------------------------------------------------------------
# Coelhinho
# ---------------------------------------------------------------------------
def _bunny_body(mb):
    _ellipsoid(mb, (0, 0.0, 0.26), 0.23, (1.0, 0.92, 1.12))
    _ball(mb, (0, -0.06, 0.22), 0.17)
    _ellipsoid(mb, (0, 0.02, 0.12), 0.2, (1.15, 1.0, 0.6))
    _ball(mb, (0, -0.02, 0.64), 0.22)
    for s in (-1, 1):
        _ball(mb, (0.09 * s, -0.12, 0.58), 0.1, 1.6)
    _ellipsoid(mb, (0, -0.185, 0.58), 0.075, (1.2, 0.8, 0.75))
    # Orelhas compridas (uma dobradinha)
    _capsule(mb, (0.08, 0.0, 0.8), (0.11, 0.02, 1.08), 0.055, 2.2)
    _capsule(mb, (-0.08, 0.0, 0.8), (-0.14, 0.02, 1.0), 0.055, 2.2)
    _capsule(mb, (-0.14, 0.02, 1.0), (-0.22, 0.04, 1.04), 0.05, 2.2)
    for s in (-1, 1):
        _capsule(mb, (0.11 * s, -0.08, 0.1), (0.13 * s, -0.3, 0.08), 0.085)
        _ellipsoid(mb, (0.13 * s, -0.36, 0.09), 0.09, (0.85, 1.3, 0.8))
    _ball(mb, (0, 0.24, 0.12), 0.08, 1.6)
    _capsule(mb, (0.19, -0.02, 0.43), (0.19, -0.17, 0.27), 0.065)
    _ball(mb, (0.19, -0.19, 0.25), 0.07)
    _capsule(mb, (-0.19, -0.02, 0.45), (-0.33, -0.06, 0.68), 0.065)
    _ball(mb, (-0.345, -0.065, 0.71), 0.072)


def _bunny_paint():
    shoulder = Vector(SHOULDER["bunny_wave"])

    def fn(co):
        x, y, z = co
        light = 0.0
        d = (Vector((x, y, z)) - Vector((0, -0.205, 0.575))).length
        light = max(light, 1.0 - smooth(0.06, 0.09, d))
        if y < -0.05:
            e = math.hypot(x / 0.12, (z - 0.25) / 0.15)
            light = max(light, 1.0 - smooth(0.85, 1.05, e))
        # Dentro das orelhas (frente)
        if y < -0.02 and z > 0.82:
            light = max(light, 0.85)
        # Rabinho de algodão
        if y > 0.25:
            light = max(light, 1.0)
        wave = _arm_weight(co, shoulder, (-0.345, -0.065, 0.71), 0.11)
        return (wave, light, 0.0, 0.0)
    return fn


def bunny_wave():
    body = _meta_to_mesh("bunny_wave", _bunny_body)
    _paint(body, _bunny_paint())
    parts = _face("bn", eye_y=-0.22, eye_z=0.665, eye_x=0.075, nose=(0, -0.258, 0.6), nose_r=0.022)
    # Dentinhos
    for s in (-1, 1):
        t = _sphere("bn_tooth%d" % s, (0.011 * s, -0.25, 0.545), 0.012, (0.9, 0.5, 1.4), segs=8, rings=6)
        _solid(t, g=1.0)
        parts.append(t)
    return [body] + parts + _bow("bn", (0.1, 0.0, 0.83), 0.05)


MODELS = {
    "bear_wave": {"build": bear_wave, "size": 1.0, "tris": 9000, "base": True},
    "bear_hug": {"build": bear_hug, "size": 1.0, "tris": 9000, "base": True},
    "bunny_wave": {"build": bunny_wave, "size": 1.0, "tris": 8000, "base": True},
}
