"""
Bichos de pelúcia da Rainbow Raceway (pista fofa nas nuvens).

Uso (a partir da raiz do projeto):
    blender -b --factory-startup -P blender/build_clouds.py                        # gera os .glb
    blender -b --factory-startup -P blender/build_clouds.py -- --render <pasta>      # + vistas
    blender -b --factory-startup -P blender/build_clouds.py -- --only=bear_wave      # só esse
    blender -b --factory-startup -P blender/build_clouds.py -- --out <pasta>         # .glb em outra pasta

As peças ficam em blender/cloud_plush.py, em unidades (~1 de altura, sentadas, base em z = 0), frente
para -Y e z para cima; aqui a malha é reduzida (Decimate) até o número de triângulos de cada peça,
escalada para metros (MODELS: size) e exportada com a cor de vértice (as máscaras do plush.gdshader).
O Godot troca o material (scripts/track/plush_friends.gd). A frente (-Y no Blender) vira +Z.

Saída: assets/track/rainbow_raceway/models/<nome>.glb
"""
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = ARGS[ARGS.index("--out") + 1] if "--out" in ARGS else os.path.join(ROOT, "assets", "track", "rainbow_raceway", "models")
RENDER_DIR = ARGS[ARGS.index("--render") + 1] if "--render" in ARGS else ""
ONLY = next((a.split("=", 1)[1].split(",") for a in ARGS if a.startswith("--only=")), [])

sys.path.insert(0, HERE)
import cloud_plush  # noqa: E402

MODELS = cloud_plush.MODELS


def finish(name, objs):
    """Junta, reduz até os triângulos da peça, escala e exporta."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    me = obj.data
    spec = MODELS[name]
    scale, target = spec["size"], spec["tris"]
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    if tris > target:
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = target / tris
        bpy.ops.object.modifier_apply(modifier=mod.name)
    me.transform(Matrix.Scale(scale, 4))
    low = 0.0
    if spec.get("base"):
        low = min(v.co.z for v in me.vertices)
        me.transform(Matrix.Translation((0, 0, -low)))
    # Ombro do braço que acena no espaço do Godot (x, z, -y), para o PIVOTS do plush_friends.gd
    sh = cloud_plush.SHOULDER.get(name)
    if sh:
        print("  ombro (Godot): Vector3(%.3f, %.3f, %.3f)" % (sh[0] * scale, sh[2] * scale - low, -sh[1] * scale))
    for p in me.polygons:
        p.use_smooth = True
    mat = bpy.data.materials.new(name)
    me.materials.clear()
    me.materials.append(mat)
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    lo = Vector((min(v.co[k] for v in me.vertices) for k in range(3)))
    hi = Vector((max(v.co[k] for v in me.vertices) for k in range(3)))
    print("%s: %d triângulos, %.2f x %.2f x %.2f m" % (name, tris, *(hi - lo)))
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
    scene.render.resolution_x = 700
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
    for view, d in (("front", Vector((0.3, -1.0, 0.25))), ("side", Vector((1.0, -0.25, 0.3))), ("back", Vector((-0.4, 1.0, 0.4)))):
        cam.location = center + d.normalized() * size * 2.2
        cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(RENDER_DIR, "%s_%s.png" % (name, view))
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    for name, spec in MODELS.items():
        if ONLY and name not in ONLY:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        obj = finish(name, spec["build"]())
        if RENDER_DIR:
            os.makedirs(RENDER_DIR, exist_ok=True)
            render(obj, name)


if __name__ == "__main__":
    main()
