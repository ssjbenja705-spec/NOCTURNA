"""El Organismo (criatura final) en Blender: piezas orgánicas para la persecución.

Uso:
  blender -b --factory-startup -P assets/blender/build_organismo.py -- --out C:/tmp/nto

Arma cada pieza que anima ChaseCreature.lua con las MISMAS medidas que la pieza
de Roblox (así el código que la mueve no cambia): masas que se funden como carne
(metaballs), remallado por vóxeles, detalle por desplazamiento con ruido, menos
polígonos para celulares, UV y un FBX con todas las piezas por nombre.

Ejes: se modela con Z arriba; Roblox X = Blender X, Roblox Y = Blender Z y el
frente de Roblox (-Z) = Blender +Y. El FBX sale con forward -Z / up Y, que es lo
que espera el importador de Roblox.

Piezas (tamaño Roblox X, Y, Z):
  Body 14x10x13 · Hump 11x7x9 · Head 8x5x6 · WeakPoint 3x2x3 · Jaw 7x1.6x5
  Arm 1.8x11x1.8 · Forearm 1.4x10x1.4 · Claw 2.2x0.6x2.6 · Tendril 0.9x0.9x12
  Tissue 3.5x3.5x3.5
"""

import math
import os
import random
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[ARGS.index("--out") + 1] if "--out" in ARGS else "C:/tmp/nto"
os.makedirs(OUT, exist_ok=True)

# Polígonos por pieza (Roblox admite hasta 20 000 por malla; en celular, menos es mejor).
FACES = {
    "Body": 5000, "Hump": 3500, "Head": 4000, "WeakPoint": 1800, "Jaw": 2200,
    "Arm": 1400, "Forearm": 1200, "Claw": 900, "Tendril": 700, "Tissue": 1200,
}
# Cada cuántos studs se repite la textura sobre la pieza.
TEXTURE_STUDS = 6.0

random.seed(7)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def to_blender(x, y, z):
    """Posición en ejes de Roblox (pieza) a Blender."""
    return Vector((x, -z, y))


def meta(name, elements, resolution=0.18, threshold=0.18):
    """Masa orgánica: elementos (tipo, centro Roblox, radio, tamaño, rotación Z)."""
    data = bpy.data.metaballs.new(name)
    data.resolution = resolution
    data.render_resolution = resolution
    data.threshold = threshold
    obj = bpy.data.objects.new(name + "_meta", data)
    bpy.context.collection.objects.link(obj)
    for kind, center, radius, size, stiffness in elements:
        element = data.elements.new(type=kind)
        element.co = to_blender(*center)
        element.radius = radius
        element.stiffness = stiffness
        if kind in ("ELLIPSOID", "CAPSULE", "CUBE"):
            sx, sy, sz = size
            element.size_x, element.size_y, element.size_z = sx, sz, sy
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    mesh_obj = bpy.context.view_layer.objects.active
    mesh_obj.name = name
    return mesh_obj


def select_only(obj):
    for other in bpy.context.selected_objects:
        other.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def remesh(obj, voxel):
    select_only(obj)
    modifier = obj.modifiers.new("Remesh", "REMESH")
    modifier.mode = "VOXEL"
    modifier.voxel_size = voxel
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def displace(obj, texture_type, strength, scale, seed=0, **props):
    select_only(obj)
    texture = bpy.data.textures.new(obj.name + "_" + texture_type + str(seed), texture_type)
    for key, value in props.items():
        setattr(texture, key, value)
    if hasattr(texture, "noise_scale"):
        texture.noise_scale = scale
    modifier = obj.modifiers.new("Displace", "DISPLACE")
    modifier.texture = texture
    modifier.strength = strength
    modifier.mid_level = 0.5
    modifier.texture_coords = "GLOBAL"
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def smooth(obj, factor=0.5, repeat=2):
    select_only(obj)
    modifier = obj.modifiers.new("Smooth", "SMOOTH")
    modifier.factor = factor
    modifier.iterations = repeat
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def decimate(obj, faces):
    select_only(obj)
    current = len(obj.data.polygons)
    if current > faces:
        modifier = obj.modifiers.new("Decimate", "DECIMATE")
        modifier.ratio = faces / current
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.ops.object.shade_smooth()


def fit(obj, size):
    """Escala y centra la pieza para que mida exactamente `size` (ejes Roblox)."""
    select_only(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    obj.location = (0, 0, 0)
    dims = obj.dimensions
    sx, sy, sz = size
    target = Vector((sx, sz, sy))
    obj.scale = (target.x / max(dims.x, 1e-4), target.y / max(dims.y, 1e-4), target.z / max(dims.z, 1e-4))
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def uv(obj, size):
    select_only(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    # La textura se repite cada TEXTURE_STUDS: piezas grandes, más repeticiones.
    repeat = max(size) / TEXTURE_STUDS
    for loop in obj.data.uv_layers.active.data:
        loop.uv *= repeat


def finish(obj, name, size):
    remesh(obj, max(min(size) / 28, 0.05))
    smooth(obj, 0.5, 2)
    return obj


def merge(objects, name):
    for other in bpy.context.selected_objects:
        other.select_set(False)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    return joined


def cone(name, base, tip, radius):
    """Diente o garra: cono de base a punta (posiciones Roblox)."""
    a, b = to_blender(*base), to_blender(*tip)
    direction = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=radius, radius2=0.0, depth=direction.length,
                                    location=(a + b) / 2)
    obj = bpy.context.view_layer.objects.active
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction.normalized())
    obj.name = name
    return obj


# Piezas -----------------------------------------------------------------------------

def body():
    els = [("ELLIPSOID", (0, 0, 0), 5.0, (1.3, 1.0, 1.15), 2.0)]
    # Grandes masas musculares sobre el lomo y los costados.
    for side in (-1, 1):
        for index in range(4):
            els.append(("ELLIPSOID", (side * (3.6 + random.uniform(-0.4, 0.4)), 0.6 + index * 0.4, -3.5 + index * 2.4),
                        2.2 + random.uniform(-0.3, 0.4), (1.0, 0.8, 1.4), 2.0))
        # Costillas que asoman bajo la carne.
        for rib in range(5):
            els.append(("CAPSULE", (side * 5.2, -1.2 + rib * 0.15, -3 + rib * 1.6), 0.55, (0.2, 0.2, 2.6), 2.0))
    # Tumores y bultos irregulares.
    for _ in range(7):
        els.append(("BALL", (random.uniform(-4.5, 4.5), random.uniform(1.5, 3.8), random.uniform(-4.5, 4.5)),
                    random.uniform(0.9, 1.7), None, 2.0))
    obj = meta("Body", els)
    finish(obj, "Body", (14, 10, 13))
    displace(obj, "CLOUDS", 0.35, 1.4, noise_depth=3)
    displace(obj, "STUCCI", 0.12, 0.35, seed=1)
    return obj


def hump():
    # Coraza: placas solapadas que crecen sobre la carne del lomo.
    pieces = []
    for row in range(3):
        for col in range(3):
            x = (col - 1) * 3.4 + random.uniform(-0.4, 0.4)
            z = (row - 1) * 2.8 + random.uniform(-0.3, 0.3)
            y = 1.2 - abs(col - 1) * 1.1 - abs(row - 1) * 0.5
            bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1, location=to_blender(x, y, z))
            plate = bpy.context.view_layer.objects.active
            plate.scale = (2.2, 1.8, 0.55)
            plate.rotation_euler = (random.uniform(-0.25, 0.25), random.uniform(-0.25, 0.25), random.uniform(-0.6, 0.6))
            pieces.append(plate)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1, location=to_blender(0, -1.2, 0))
    base = bpy.context.view_layer.objects.active
    base.scale = (5.2, 4.2, 2.6)
    pieces.append(base)
    obj = merge(pieces, "Hump")
    finish(obj, "Hump", (11, 7, 9))
    displace(obj, "VORONOI", 0.18, 0.7, seed=2)
    displace(obj, "CLOUDS", 0.1, 0.3, seed=3, noise_depth=2)
    return obj


def head():
    els = [
        ("ELLIPSOID", (0, 0, 0), 2.6, (1.4, 0.9, 1.15), 2.0),
        # Hocico que avanza (frente de Roblox: -Z).
        ("ELLIPSOID", (0, -0.6, -1.8), 1.8, (1.1, 0.7, 1.0), 2.0),
        # Arcos sobre los ojos y pómulos.
        ("CAPSULE", (0, 0.9, -1.2), 0.6, (1.9, 0.2, 0.2), 2.0),
        ("BALL", (-2.2, -0.2, -0.6), 1.0, None, 2.0),
        ("BALL", (2.2, -0.2, -0.6), 1.0, None, 2.0),
    ]
    for side in (-1, 1):
        for index in range(3):
            els.append(("BALL", (side * (1.0 + index * 0.6), 1.4 - index * 0.2, 1.4), 0.7, None, 2.0))
    obj = meta("Head", els)
    finish(obj, "Head", (8, 5, 6))
    displace(obj, "VORONOI", 0.14, 0.6, seed=4)
    displace(obj, "CLOUDS", 0.12, 0.5, seed=5, noise_depth=3)
    return obj


def weak_point():
    # El punto débil: un saco de tejido nervioso expuesto entre las placas del
    # cráneo, surcado de venas (el juego lo hace latir con luz).
    els = [("ELLIPSOID", (0, 0, 0), 1.2, (1.25, 0.8, 1.25), 2.0)]
    for index in range(6):
        angle = index / 6 * math.tau
        els.append(("BALL", (math.cos(angle) * 0.8, 0.2, math.sin(angle) * 0.8), 0.55, None, 2.0))
    obj = meta("WeakPoint", els)
    finish(obj, "WeakPoint", (3, 2, 3))
    displace(obj, "VORONOI", 0.12, 0.25, seed=6, distance_metric="DISTANCE")
    return obj


def jaw():
    els = []
    for index in range(15):
        t = index / 14
        angle = (t - 0.5) * math.pi * 0.9
        els.append(("BALL", (math.sin(angle) * 2.8, 0, -math.cos(angle) * 1.8), 0.75, None, 2.0))
    base = meta("JawBone", els)
    finish(base, "JawBone", (7, 1.0, 5))
    teeth = [base]
    for index in range(14):
        t = index / 13
        angle = (t - 0.5) * math.pi * 0.85
        x, z = math.sin(angle) * 3.0, -math.cos(angle) * 2.0
        length = random.uniform(0.6, 1.1) * (1.3 if index in (2, 11) else 1)
        teeth.append(cone("Tooth", (x, 0.2, z), (x * 1.02, 0.2 + length, z * 1.02), 0.18))
    obj = merge(teeth, "Jaw")
    return obj


def limb(name, size, lumps, bone):
    sx, sy, sz = size
    # Hueso: cadena de bolas que se funden a lo largo del brazo (eje Y de Roblox).
    els = []
    for index in range(22):
        t = index / 21
        els.append(("BALL", (0, -sy * 0.45 + t * sy * 0.9, 0), sx * 0.55 * (1.0 - 0.25 * t if bone else 1.0), None, 2.0))
    for index in range(lumps):
        y = sy * 0.35 - index * sy / (lumps + 1)
        els.append(("ELLIPSOID", (random.uniform(-0.15, 0.15) * sx, y, random.uniform(-0.15, 0.15) * sx),
                    sx * 0.42, (0.9, 1.6, 0.9), 2.0))
    obj = meta(name, els, resolution=0.08)
    finish(obj, name, size)
    displace(obj, "STUCCI" if bone else "CLOUDS", 0.05 if bone else 0.08, 0.25, seed=len(name))
    return obj


def claw():
    parts = []
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=1, location=(0, 0, 0))
    palm = bpy.context.view_layer.objects.active
    palm.scale = (0.9, 0.9, 0.3)
    parts.append(palm)
    for index in range(3):
        x = (index - 1) * 0.7
        parts.append(cone("Talon", (x, 0, -0.4), (x * 1.3, -0.25, -2.2), 0.28))
    obj = merge(parts, "Claw")
    return obj


def tendril():
    els = []
    for index in range(26):
        t = index / 25
        els.append(("BALL", (math.sin(t * 5) * 0.15, math.cos(t * 4) * 0.12, -6 + t * 12), 0.75 * (1.1 - t * 0.55), None, 2.0))
    obj = meta("Tendril", els, resolution=0.06)
    finish(obj, "Tendril", (0.9, 0.9, 12))
    return obj


def tissue():
    els = [("BALL", (0, 0, 0), 1.3, None, 2.0)]
    for _ in range(9):
        direction = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))).normalized()
        els.append(("BALL", tuple(direction * 1.1), random.uniform(0.35, 0.7), None, 2.0))
    obj = meta("Tissue", els, resolution=0.08)
    finish(obj, "Tissue", (3.5, 3.5, 3.5))
    displace(obj, "CLOUDS", 0.12, 0.3, seed=9, noise_depth=2)
    return obj


SIZES = {
    "Body": (14, 10, 13), "Hump": (11, 7, 9), "Head": (8, 5, 6), "WeakPoint": (3, 2, 3),
    "Jaw": (7, 1.6, 5), "Arm": (1.8, 11, 1.8), "Forearm": (1.4, 10, 1.4), "Claw": (2.2, 0.6, 2.6),
    "Tendril": (0.9, 0.9, 12), "Tissue": (3.5, 3.5, 3.5),
}


def main():
    reset()
    builders = {
        "Body": body, "Hump": hump, "Head": head, "WeakPoint": weak_point, "Jaw": jaw,
        "Arm": lambda: limb("Arm", SIZES["Arm"], 3, False),
        "Forearm": lambda: limb("Forearm", SIZES["Forearm"], 4, True),
        "Claw": claw, "Tendril": tendril, "Tissue": tissue,
    }
    report = {}
    offset = 0.0
    for name, build in builders.items():
        obj = build()
        obj.name = name
        fit(obj, SIZES[name])
        decimate(obj, FACES[name])
        uv(obj, SIZES[name])
        report[name] = len(obj.data.polygons)
        # En la escena de Blender quedan una al lado de la otra para mirarlas.
        obj["NocturnaOffset"] = offset
        offset += max(SIZES[name]) + 3

    # FBX para Roblox (todas las piezas con su origen en el centro).
    for other in bpy.context.selected_objects:
        other.select_set(False)
    for name in builders:
        bpy.data.objects[name].select_set(True)
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "Organismo.fbx"), use_selection=True,
                             axis_forward="-Z", axis_up="Y", apply_unit_scale=True, mesh_smooth_type="FACE",
                             object_types={"MESH"})
    # Escena para mirar en Blender: piezas en fila, con luz y cámara.
    for name in builders:
        obj = bpy.data.objects[name]
        obj.location.x = obj["NocturnaOffset"]
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "Organismo.blend"))
    print("ORGANISMO", report)


main()
