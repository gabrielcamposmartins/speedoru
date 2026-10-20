"""
Estátuas e bichos da Atlantis Abyss (pista no fundo do mar).

Uso (a partir da raiz do projeto):
    blender -b --factory-startup -P blender/build_atlantis.py                       # gera os .glb
    blender -b --factory-startup -P blender/build_atlantis.py -- --render <pasta>     # + vistas
    blender -b --factory-startup -P blender/build_atlantis.py -- --only=whale,manta  # só esses
    blender -b --factory-startup -P blender/build_atlantis.py -- --out <pasta>        # .glb em outra pasta

As peças ficam em blender/atlantis_statues.py e blender/atlantis_creatures.py, em unidades (cada peça
tem ~1 de altura ou de comprimento), frente para -Y e z para cima; aqui a malha é escalada para metros
(MODELS: size), reduzida (Decimate) até o número de triângulos de cada peça e exportada com a cor de
vértice:
nos bichos, o nado e as máscaras de cor do sea_creature.gdshader (blender/atlantis_creatures.py); nas
estátuas, a cor da pedra (blender/atlantis_statues.py).
O Godot troca o material: as estátuas viram pedra de Atlântida (sea_stone), os bichos o toon
animado com as cores de cada um (scripts/track/sea_life.gd). A frente (-Y no Blender) vira +Z.

Saída: assets/track/atlantis_abyss/models/<nome>.glb
"""
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = ARGS[ARGS.index("--out") + 1] if "--out" in ARGS else os.path.join(ROOT, "assets", "track", "atlantis_abyss", "models")
RENDER_DIR = ARGS[ARGS.index("--render") + 1] if "--render" in ARGS else ""
ONLY = next((a.split("=", 1)[1].split(",") for a in ARGS if a.startswith("--only=")), [])

sys.path.insert(0, HERE)
import atlantis_creatures  # noqa: E402
import atlantis_statues  # noqa: E402

# nome: dict(build, size = metros por unidade, tris = triângulos, paint = cor de vértice ou nada,
#             base = apoiar a base em z = 0)
MODELS = {**atlantis_statues.MODELS, **atlantis_creatures.MODELS}


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
    spec = MODELS[name]
    scale, target = spec["size"], spec["tris"]
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    if tris > target:
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = target / tris
        bpy.ops.object.modifier_apply(modifier=mod.name)
    # Cor de vértice (antes de escalar: a pintura usa as unidades da peça)
    paint = spec.get("paint")
    if paint:
        paint(me)
    me.transform(Matrix.Scale(scale, 4))
    # Estátuas com a base em z = 0 (base=True); bichos centrados
    if spec.get("base"):
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
