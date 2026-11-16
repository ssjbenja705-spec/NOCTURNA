"""Esqueleto para El Organismo generado con Meshy (assets/models/ai/ElOrganismo.glb).

Uso:
  blender -b --factory-startup -P assets/blender/rig_organismo.py -- assets/models/ai/ElOrganismo.glb C:/tmp/org

El modelo es un cuadrúpedo agazapado (frente hacia -Y de Blender, Z arriba), de
~1,9 unidades de largo. El script:
  1. Une la malla, la reduce a MAX_TRIS triángulos (límite de Roblox) y la escala a
     studs con las garras apoyadas en el piso (Z = 0).
  2. Arma un esqueleto de 20 huesos con las articulaciones medidas sobre las
     vistas del modelo (JOINTS): columna, cuello, cabeza, mandíbula, lengua y
     cuatro patas de tres tramos.
  3. Lo pesa con pesos automáticos (y distancia al hueso donde falle), con un
     máximo de 4 huesos por vértice.
  4. Exporta ElOrganismoRig.fbx (malla con piel + esqueleto), las texturas PBR a
     1024 px (Color, Normal, Roughness), bones.json y una vista previa con una
     pose doblada para revisar los pesos.
"""

import json
import math
import os
import sys

import bpy
import numpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
SRC = os.path.abspath(ARGS[0])
OUT = os.path.abspath(ARGS[1])
os.makedirs(OUT, exist_ok=True)

MAX_TRIS = 18000
TEXTURE = 1024
SCALE = 10.0  # unidades del modelo -> studs (queda de ~15 studs de alto)

# Articulaciones en unidades del modelo original (x derecha, y atrás, z arriba).
# Sólo el lado derecho (x > 0); el izquierdo se espeja.
SPINE = [
    ("Hips", (0, 0.60, 0.20), (0, 0.20, 0.33), None),
    ("Chest", (0, 0.20, 0.33), (0, -0.20, 0.38), "Hips"),
    ("Neck", (0, -0.20, 0.38), (0, -0.48, 0.27), "Chest"),
    ("Head", (0, -0.48, 0.27), (0, -0.90, 0.22), "Neck"),
    ("Jaw", (0, -0.62, 0.17), (0, -0.80, -0.05), "Head"),
    ("Tongue1", (0, -0.74, 0.06), (0, -0.82, -0.10), "Jaw"),
    ("Tongue2", (0, -0.82, -0.10), (0, -0.93, -0.25), "Tongue1"),
]
LIMBS = [
    ("UpperArm", (0.38, -0.16, 0.33), (0.68, 0.02, -0.05), "Chest"),
    ("Forearm", (0.68, 0.02, -0.05), (0.64, -0.35, -0.60), "UpperArm"),
    ("Hand", (0.64, -0.35, -0.60), (0.64, -0.80, -0.70), "Forearm"),
    ("Thigh", (0.29, 0.58, 0.15), (0.58, 0.26, -0.25), "Hips"),
    ("Shin", (0.58, 0.26, -0.25), (0.48, 0.88, -0.33), "Thigh"),
    ("Foot", (0.48, 0.88, -0.33), (0.68, 0.45, -0.70), "Shin"),
]


def bones_list(lift):
    def place(p):
        return Vector((p[0] * SCALE, p[1] * SCALE, p[2] * SCALE + lift))

    bones = [("Root", Vector((0, 2.0, 0.2 * SCALE + lift)), Vector((0, 2.0, 0.2 * SCALE + lift + 1.0)), None)]
    for name, head, tail, parent in SPINE:
        bones.append((name, place(head), place(tail), parent or "Root"))
    for side, sign in (("Right", 1), ("Left", -1)):
        for name, head, tail, parent in LIMBS:
            h = (head[0] * sign, head[1], head[2])
            t = (tail[0] * sign, tail[1], tail[2])
            if parent not in ("Chest", "Hips"):
                parent = side + parent
            bones.append((side + name, place(h), place(t), parent))
    return bones


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = "ElOrganismo"
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for other in list(bpy.context.scene.objects):
        if other != obj:
            bpy.data.objects.remove(other, do_unlink=True)

    # Texturas: color, normal y rugosidad (canal verde del mapa ORM de glTF).
    material = obj.data.materials[0]
    images = {}
    for node in material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image:
            for link in node.outputs["Color"].links:
                target = link.to_node.type
                socket = link.to_socket.name
                if socket == "Base Color":
                    images["Color"] = node.image
                elif target == "NORMAL_MAP":
                    images["Normal"] = node.image
                elif target in ("SEPARATE_COLOR", "SEPRGB", "SEPARATE_RGB"):
                    images["ORM"] = node.image
    print("TEXTURES", {k: v.name for k, v in images.items()})
    for key in ("Color", "Normal"):
        if key in images:
            image = images[key].copy()
            image.scale(TEXTURE, TEXTURE)
            image.filepath_raw = os.path.join(OUT, "ElOrganismo_" + key + ".png")
            image.file_format = "PNG"
            image.save()
    if "ORM" in images:
        image = images["ORM"].copy()
        image.scale(TEXTURE, TEXTURE)
        pixels = numpy.array(image.pixels[:], dtype=numpy.float32).reshape(-1, 4)
        rough = pixels[:, 1].copy()
        pixels[:, 0] = rough
        pixels[:, 1] = rough
        pixels[:, 2] = rough
        pixels[:, 3] = 1.0
        image.pixels = pixels.reshape(-1).tolist()
        image.filepath_raw = os.path.join(OUT, "ElOrganismo_Roughness.png")
        image.file_format = "PNG"
        image.save()

    # glTF trae los vértices duplicados en las costuras de la textura: sin soldarlos,
    # cada copia recibe pesos distintos y la piel se abre al doblarse.
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0002)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Menos triángulos, a studs y con las garras en el piso.
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if tris > MAX_TRIS:
        modifier = obj.modifiers.new("Decimate", "DECIMATE")
        modifier.ratio = MAX_TRIS / tris * 0.985
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0002)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.data.transform(Matrix.Scale(SCALE, 4))
    low = min(v.co.z for v in obj.data.vertices)
    lift = -low
    obj.data.transform(Matrix.Translation((0, 0, lift)))
    obj.data.update()
    final_tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    size = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    print("MESH tris", final_tris, "size", [round(s, 2) for s in size])

    # Esqueleto.
    bones = bones_list(lift)
    arm_data = bpy.data.armatures.new("OrganismoRig")
    arm = bpy.data.objects.new("OrganismoRig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for name, head, tail, parent in bones:
        bone = arm_data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        if parent:
            bone.parent = made[parent]
        made[name] = bone
    bpy.ops.object.mode_set(mode="OBJECT")

    # Piel: pesos automáticos; donde fallen, el hueso más cercano.
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    names = [b[0] for b in bones]
    segments = {b[0]: (b[1], b[2]) for b in bones}

    def distance(p, a, b):
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
        return (p - (a + ab * t)).length

    groups = {g.index: g.name for g in obj.vertex_groups}
    by_name = {g.name: g for g in obj.vertex_groups}
    for name in names:
        if name not in by_name:
            by_name[name] = obj.vertex_groups.new(name=name)
    fixed = 0
    for vertex in obj.data.vertices:
        weights = [(groups.get(g.group), g.weight) for g in vertex.groups if g.weight > 1e-4 and groups.get(g.group) in segments]
        weights = [w for w in weights if w[0] != "Root"]
        if not weights:
            fixed += 1
            ranked = sorted((distance(vertex.co, *segments[n]), n) for n in names if n != "Root")
            weights = [(ranked[0][1], 1.0)]
        weights.sort(key=lambda w: -w[1])
        weights = weights[:4]
        total = sum(w for _, w in weights)
        for group in obj.vertex_groups:
            group.remove([vertex.index])
        for name, weight in weights:
            by_name[name].add([vertex.index], weight / total, "REPLACE")
    print("SKIN sin peso automático:", fixed, "de", len(obj.data.vertices))

    # Vista previa con una pose doblada (para revisar los pesos).
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 600
    world = bpy.data.worlds.new("W")
    world.color = (0.2, 0.2, 0.22)
    scene.world = world
    cam_data = bpy.data.cameras.new("C")
    cam = bpy.data.objects.new("C", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    center = Vector((0, 0, size[2] / 2))

    def shoot(name, direction):
        cam.location = center + Vector(direction).normalized() * 42
        look = (center - cam.location).normalized()
        right = look.cross(Vector((0, 0, 1))).normalized()
        up = right.cross(look)
        cam.rotation_euler = Matrix((right, up, -look)).transposed().to_euler()
        scene.render.filepath = os.path.join(OUT, name + ".png")
        bpy.ops.render.render(write_still=True)

    shoot("rig_rest", (1, -0.9, 0.35))
    pose = {
        "Jaw": ("X", 35), "Head": ("X", -20), "Neck": ("X", -10), "Tongue1": ("X", 25), "Tongue2": ("X", 30),
        "RightUpperArm": ("X", 35), "RightForearm": ("X", -30), "LeftUpperArm": ("X", -30), "LeftForearm": ("X", 25),
        "RightThigh": ("X", -25), "RightShin": ("X", 25), "LeftThigh": ("X", 25), "LeftShin": ("X", -20),
        "Chest": ("X", 8),
    }
    for name, (axis, degrees) in pose.items():
        bone = arm.pose.bones[name]
        bone.rotation_mode = "XYZ"
        setattr(bone.rotation_euler, axis.lower(), math.radians(degrees))
    bpy.context.view_layer.update()
    shoot("rig_pose", (1, -0.9, 0.35))
    shoot("rig_pose_side", (1, 0, 0.05))
    for bone in arm.pose.bones:
        bone.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()

    # FBX sin texturas adentro (se suben aparte como imágenes).
    obj.data.materials.clear()
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT, "ElOrganismoRig.fbx"), use_selection=True, object_types={"ARMATURE", "MESH"},
        axis_forward="-Z", axis_up="Y", global_scale=1.0, apply_unit_scale=False, apply_scale_options="FBX_SCALE_NONE",
        mesh_smooth_type="FACE", use_armature_deform_only=False, add_leaf_bones=False, primary_bone_axis="Y",
        secondary_bone_axis="X", armature_nodetype="NULL", bake_anim=False,
    )
    with open(os.path.join(OUT, "bones.json"), "w", encoding="utf-8") as handle:
        json.dump({"Bones": [{"Name": n, "Parent": p} for n, _, _, p in bones], "Triangles": final_tris,
                   "Size": [round(s, 3) for s in size], "Scale": SCALE}, handle, indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "ElOrganismoRig.blend"))
    print("RIG OK bones", len(bones))


main()
