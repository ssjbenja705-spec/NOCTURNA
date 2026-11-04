"""Genera los modelos 3D de las cinco criaturas de NOCTURNA.

Uso (desde la raíz del repositorio):
  blender --background --factory-startup --python assets/blender/build_creatures.py -- assets/models

Escribe:
  fbx/<Criatura>.fbx          una pieza por nombre, lista para el importador 3D de Studio
  previews/<Criatura>.png     render de la criatura armada
  previews/Lineup.png         las cinco juntas, a escala
  NOCTURNA_Creatures.blend    escena editable

Cada pieza se ajusta exactamente a la caja de la Part que reemplaza en
src/server/Monsters/MonsterFactory.lua (mismo nombre, mismo tamaño, centro en el
origen y frente hacia -Y, que en Roblox queda hacia -Z). Así el juego cambia Part
por MeshPart sin tocar uniones ni animaciones. Si se cambia un tamaño o una
posición en MonsterFactory, hay que cambiarlo también en CREATURES.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGS[0] if ARGS else "assets/models")
MAX_TRIS = 4000

# Roblox (x, y, z) -> Blender (-x, z, y): Y arriba pasa a Z arriba y el frente -Z a -Y.
TO_BLENDER = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))


def rb(x, y, z):
    return TO_BLENDER @ Vector((x, y, z))


def rb_size(size):
    return Vector((size[0], size[2], size[1]))


def roblox_cframe(pos, angles=(0, 0, 0)):
    # CFrame.new(pos) * CFrame.Angles(rx, ry, rz) expresado en ejes de Blender.
    rx, ry, rz = angles
    rot = (Matrix.Rotation(rx, 3, "X") @ Matrix.Rotation(ry, 3, "Y") @ Matrix.Rotation(rz, 3, "Z"))
    rot_b = TO_BLENDER @ rot @ TO_BLENDER.inverted()
    m = rot_b.to_4x4()
    m.translation = rb(*pos)
    return m


class Skel:
    """Esqueleto de nodos con radio; el modificador Skin le pone carne."""

    def __init__(self):
        self.nodes = []
        self.edges = []

    def add(self, pos, radius, parent=None):
        self.nodes.append((pos, radius))
        index = len(self.nodes) - 1
        if parent is not None:
            self.edges.append((parent, index))
        return index

    def chain(self, points, parent=None):
        last = parent
        for pos, radius in points:
            last = self.add(pos, radius, last)
        return last


# --- Piezas -------------------------------------------------------------------
# Coordenadas en studs de Roblox (Y arriba, frente -Z), centradas en la pieza.


def oyente_torso():
    s = Skel()
    hip = s.add((0, -2.2, 0.05), 0.32)
    mid = s.chain([((0, -1.2, 0.05), 0.38), ((0, -0.1, 0), 0.55)], hip)
    chest = s.chain([((0, 0.9, -0.05), 0.72), ((0, 1.8, 0), 0.62)], mid)
    s.add((0, 2.25, 0.05), 0.35, chest)
    for side in (-1, 1):
        s.add((side * 0.75, 0.5, -0.15), 0.14, mid)
        s.add((side * 0.78, 1.4, -0.1), 0.15, chest)
    for y in (-1.6, -0.6, 0.4):
        s.add((0, y, 0.42), 0.09, mid)
    return s


def oyente_head():
    s = Skel()
    chin = s.add((0, -0.9, -0.35), 0.3)
    jaw = s.add((0, -0.2, -0.2), 0.5, chin)
    skull = s.add((0, 0.5, 0.15), 0.58, jaw)
    s.add((0, 0.95, 0.35), 0.4, skull)
    return s


def oyente_mouth():
    s = Skel()
    s.chain([((-0.45, 0.08, 0), 0.18), ((0, -0.05, 0), 0.24), ((0.45, 0.08, 0), 0.18)])
    return s


def oyente_ear():
    s = Skel()
    # Abanico de membrana con nervaduras, como la oreja de un murciélago.
    base = s.add((0, -0.7, 0.1), 0.2)
    membrane = s.add((0, 0.0, 0.0), 0.62, base)
    s.add((0, 0.45, 0.15), 0.55, membrane)
    for y, z in ((0.95, 0.6), (0.9, -0.1), (0.5, -0.65), (-0.2, -0.75)):
        s.chain([((0, y * 0.75, z * 0.75), 0.16), ((0, y, z), 0.07)], membrane)
    return s


def oyente_arm():
    s = Skel()
    wrist = s.chain([
        ((0, 2.6, 0), 0.2), ((0, 1.5, 0), 0.13), ((0, 0.4, 0), 0.12),
        ((0, 0.1, 0), 0.17), ((0, -1.0, 0), 0.11), ((0, -1.9, 0), 0.1),
    ])
    palm = s.add((0, -2.1, -0.05), 0.16, wrist)
    for x in (-0.15, 0, 0.15):
        s.chain([((x, -2.45, -0.08), 0.05), ((x * 1.3, -2.7, -0.15), 0.025)], palm)
    return s


def oyente_leg():
    s = Skel()
    ankle = s.chain([
        ((0, 1.7, 0), 0.24), ((0, 0.6, 0.05), 0.17), ((0, 0.1, -0.12), 0.19),
        ((0, -1.0, 0.1), 0.12), ((0, -1.55, 0.12), 0.13),
    ])
    for x in (-0.15, 0.15):
        s.chain([((x, -1.7, -0.15), 0.08), ((x, -1.7, -0.3), 0.04)], ankle)
    return s


def imitador_torso():
    s = Skel()
    hip = s.add((0, -1.25, 0), 0.55)
    waist = s.add((0, -0.3, 0), 0.62, hip)
    chest = s.add((0, 0.6, 0.05), 0.75, waist)
    s.add((0, 1.25, 0.1), 0.3, chest)
    for side in (-1, 1):
        s.chain([((side * 0.6, 1.0, 0), 0.4), ((side * 0.95, 1.05, 0), 0.3)], chest)
    return s


def imitador_head():
    s = Skel()
    s.chain([((0, -0.6, -0.1), 0.3), ((0, 0, 0), 0.55), ((0, 0.55, 0.1), 0.5)])
    return s


def imitador_jaw():
    s = Skel()
    top = s.add((0, 0.65, 0), 0.2)
    upper = s.add((0, 0.2, 0), 0.38, top)
    lower = s.add((0, -0.3, 0), 0.35, upper)
    s.add((0, -0.65, 0), 0.18, lower)
    for y, node in ((0.35, upper), (0.0, upper), (-0.35, lower)):
        for side in (-1, 1):
            s.add((side * 0.42, y, -0.05), 0.04, node)
    return s


def imitador_arm():
    s = Skel()
    hand = s.chain([
        ((0, 1.5, 0), 0.3), ((0, 0.5, 0), 0.2), ((0, 0, 0), 0.22),
        ((0, -0.9, 0), 0.16), ((0, -1.15, 0), 0.2),
    ])
    for x in (-0.22, -0.07, 0.08, 0.22):
        s.chain([((x, -1.4, -0.05), 0.05), ((x * 1.2, -1.6, -0.1), 0.03)], hand)
    return s


def imitador_leg():
    s = Skel()
    s.chain([
        ((0, 1.15, 0), 0.33), ((0, 0.1, -0.05), 0.25), ((0, -0.9, 0.05), 0.19),
        ((0, -1.1, -0.15), 0.2), ((0, -1.15, -0.4), 0.12),
    ])
    return s


def quieto_torso():
    s = Skel()
    hip = s.add((0, -1.2, 0), 0.55)
    waist = s.add((0, -0.35, 0), 0.45, hip)
    chest = s.add((0, 0.55, 0), 0.62, waist)
    s.add((0, 1.25, 0), 0.2, chest)
    for side in (-1, 1):
        s.chain([((side * 0.55, 0.95, 0), 0.35), ((side * 0.95, 0.95, 0), 0.28)], chest)
    return s


def quieto_head():
    s = Skel()
    jaw = s.add((0, -0.6, -0.15), 0.3)
    low = s.add((0, -0.35, 0), 0.52, jaw)
    s.add((0, 0.3, 0), 0.6, low)
    return s


def quieto_arm():
    s = Skel()
    s.chain([((0, 1.35, 0), 0.3), ((0, 0.1, 0), 0.21), ((0, 0, 0), 0.23), ((0, -1.1, 0), 0.17), ((0, -1.4, 0), 0.22)])
    return s


def quieto_leg():
    s = Skel()
    s.chain([
        ((0, 1.35, 0), 0.37), ((0, 0.05, 0), 0.26), ((0, -0.05, 0), 0.27),
        ((0, -1.25, 0), 0.2), ((0, -1.45, -0.2), 0.22),
    ])
    return s


def trepador_body():
    s = Skel()
    back = s.chain([((0, 0, 1.6), 0.55), ((0, 0.1, 1.0), 0.9)])
    mid = s.chain([((0, 0, 0.2), 0.75)], back)
    s.chain([((0, 0, -0.6), 0.65), ((0, 0, -1.6), 0.45)], mid)
    s.add((0, 0.85, 1.1), 0.08, back)
    s.add((0, 0.7, 0.3), 0.08, mid)
    return s


def trepador_head():
    s = Skel()
    front = s.chain([((0, 0, 0.6), 0.45), ((0, 0.05, -0.1), 0.5), ((0, -0.1, -0.6), 0.3)])
    for side in (-1, 1):
        s.chain([((side * 0.35, -0.25, -0.7), 0.1), ((side * 0.25, -0.35, -0.85), 0.05)], front)
    return s


def trepador_leg():
    s = Skel()
    s.chain([
        ((-2.2, -0.15, 0), 0.07), ((-1.1, 0.1, 0), 0.12), ((0, 0.18, 0), 0.16),
        ((1.1, 0.1, 0), 0.12), ((2.2, -0.15, 0), 0.07),
    ])
    return s


def coloso_torso():
    s = Skel()
    hip = s.add((0, -2.0, 0.1), 1.4)
    belly = s.add((0, -0.6, -0.2), 1.9, hip)
    chest = s.add((0, 0.9, 0), 2.1, belly)
    s.add((0, 1.8, -0.6), 1.0, chest)
    for side in (-1, 1):
        s.chain([((side * 2.2, 1.3, 0.2), 1.3), ((side * 3.0, 1.2, 0.2), 1.0)], chest)
    return s


def coloso_head():
    s = Skel()
    crown = s.add((0, 0.2, 0.4), 0.8)
    face = s.add((0, -0.1, -0.4), 0.85, crown)
    s.add((0, -0.6, -0.6), 0.5, face)
    for side in (-1, 1):
        s.chain([((side * 0.7, 0.6, 0.1), 0.25), ((side * 1.1, 0.9, 0.4), 0.12)], crown)
    return s


def coloso_arm():
    s = Skel()
    fist = s.chain([
        ((0, 3.0, 0), 0.85), ((0, 1.6, 0), 0.65), ((0, 0.4, 0), 0.7),
        ((0, -1.2, 0), 0.85), ((0, -2.5, 0), 0.95),
    ])
    for x in (-0.4, 0, 0.4):
        s.add((x, -3.0, -0.25), 0.3, fist)
    return s


def coloso_leg():
    s = Skel()
    s.chain([
        ((0, 1.6, 0), 1.0), ((0, 0.4, 0), 0.85), ((0, -0.8, 0), 0.8),
        ((0, -1.5, -0.2), 0.9), ((0, -1.7, -0.6), 0.6),
    ])
    return s


# --- Criaturas ------------------------------------------------------------------
# Igual que MonsterFactory: (nombre, tamaño, posición, ángulos, forma).
# forma: función de esqueleto, "dome" o None (la pieza sigue siendo una Part).

SLATE, PLASTIC, FABRIC, NEON, METAL = 0.9, 0.35, 0.95, 0.0, 0.6


def rgb(r, g, b):
    return (r / 255, g / 255, b / 255)


def oyente():
    skin, dark = rgb(128, 120, 112), rgb(48, 44, 42)
    parts = [
        ("Torso", (1.6, 4.6, 1), (0, 0.6, 0), (0.25, 0, 0), oyente_torso, skin, SLATE, 0.06),
        ("Head", (1.3, 2, 1.4), (0, 3.4, -0.9), (0, 0, 0), oyente_head, skin, SLATE, 0.05),
        ("Mouth", (0.9, 0.5, 0.2), (0, 3, -1.6), (0, 0, 0), oyente_mouth, dark, PLASTIC, 0.02),
    ]
    for side in (-1, 1):
        parts += [
            ("Ear", (0.3, 2, 1.6), (side * 0.9, 3.8, -0.8), (0, 0, side * 0.3), oyente_ear, skin, SLATE, 0.03),
            ("Arm", (0.5, 5.4, 0.5), (side * 1.2, -0.4, -0.2), (0, 0, 0), oyente_arm, dark, SLATE, 0.02),
            ("Leg", (0.6, 3.4, 0.6), (side * 0.5, -2.3, 0), (0, 0, 0), oyente_leg, dark, SLATE, 0.02),
        ]
    return parts


def imitador():
    void = rgb(10, 10, 12)
    parts = [
        ("Torso", (2, 2.6, 1), (0, 0.6, 0), (0, 0, 0), imitador_torso, void, FABRIC, 0.08),
        ("Head", (1.2, 1.4, 1.2), (0, 2.7, 0), (0, 0, 0), imitador_head, void, PLASTIC, 0.04),
        ("Jaw", (0.8, 1.4, 0.2), (0, 2.2, -0.65), (0, 0, 0), imitador_jaw, rgb(190, 30, 40), NEON, 0.0),
    ]
    for side in (-1, 1):
        parts += [
            ("Arm", (0.7, 3.2, 0.7), (side * 1.4, 0.3, 0), (0, 0, 0), imitador_arm, void, FABRIC, 0.03),
            ("Leg", (0.8, 2.4, 0.8), (side * 0.5, -1.9, 0), (0, 0, 0), imitador_leg, void, FABRIC, 0.03),
        ]
    return parts


def quieto():
    body, eye = rgb(196, 190, 180), rgb(20, 20, 20)
    parts = [
        ("Torso", (2, 2.6, 1), (0, 0.6, 0), (0, 0, 0), quieto_torso, body, PLASTIC, 0.0),
        ("Head", (1.3, 1.5, 1.3), (0, 2.8, 0), (0, 0, 0), quieto_head, body, PLASTIC, 0.0),
    ]
    for side in (-1, 1):
        parts += [
            ("Arm", (0.7, 3, 0.7), (side * 1.4, 0.4, 0), (0, 0, 0), quieto_arm, body, PLASTIC, 0.0),
            ("Leg", (0.8, 3, 0.8), (side * 0.5, -2.1, 0), (0, 0, 0), quieto_leg, body, PLASTIC, 0.0),
            ("Eye", (0.3, 0.2, 0.15), (side * 0.3, 2.9, -0.68), (0, 0, 0), None, eye, NEON, 0.0),
        ]
    return parts


def trepador():
    flesh, legs, eye = rgb(70, 24, 30), rgb(40, 16, 20), rgb(230, 200, 60)
    parts = [
        ("Body", (3, 1.4, 4), (0, 0, 0), (0, 0, 0), trepador_body, flesh, SLATE, 0.1),
        ("Head", (1.4, 1, 1.6), (0, 0.1, -2.6), (0, 0, 0), trepador_head, flesh, SLATE, 0.05),
    ]
    for side in (-1, 1):
        parts.append(("Eye", (0.3, 0.2, 0.15), (side * 0.4, 0.3, -3.4), (0, 0, 0), None, eye, NEON, 0.0))
    for row in (-1, 0, 1):
        for side in (-1, 1):
            parts.append(("Leg", (4.4, 0.4, 0.4), (side * 3, -0.5, row * 1.5), (0, 0, side * 0.35), trepador_leg, legs, SLATE, 0.02))
    return parts


def coloso():
    hide, plate, eye = rgb(44, 42, 46), rgb(66, 62, 58), rgb(240, 110, 40)
    parts = [
        ("Torso", (7, 5, 4), (0, 1, 0), (0.2, 0, 0), coloso_torso, hide, SLATE, 0.15),
        ("Plate", (7.6, 2.4, 4.6), (0, 2.8, 0.2), (0.2, 0, 0), "dome", plate, METAL, 0.12),
        ("Head", (2.4, 2, 2.4), (0, 2.2, -2.8), (0, 0, 0), coloso_head, plate, METAL, 0.06),
    ]
    for side in (-1, 1):
        parts += [
            ("Eye", (0.3, 0.2, 0.15), (side * 0.6, 2.3, -4.05), (0, 0, 0), None, eye, NEON, 0.0),
            ("Arm", (1.9, 6.4, 1.9), (side * 4.4, -0.8, -0.4), (0, 0, 0), coloso_arm, hide, SLATE, 0.1),
            ("Leg", (2.2, 3.6, 2.2), (side * 1.9, -3.2, 0), (0, 0, 0), coloso_leg, hide, SLATE, 0.1),
        ]
    return parts


CREATURES = {
    "ElOyente": oyente,
    "ElImitador": imitador,
    "ElQuieto": quieto,
    "ElTrepador": trepador,
    "ElColoso": coloso,
}


# --- Construcción ---------------------------------------------------------------


def mesh_from_bmesh(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def skin_mesh(name, skel):
    raw = bpy.data.meshes.new(name + "_skel")
    raw.from_pydata([rb(*pos) for pos, _ in skel.nodes], skel.edges, [])
    obj = bpy.data.objects.new(name + "_skel", raw)
    bpy.context.scene.collection.objects.link(obj)

    obj.modifiers.new("Skin", "SKIN")
    for index, vertex in enumerate(raw.skin_vertices[0].data):
        radius = skel.nodes[index][1]
        vertex.radius = (radius, radius)
        vertex.use_root = index == 0
    subsurf = obj.modifiers.new("Smooth", "SUBSURF")
    subsurf.levels = 2

    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    mesh.name = name
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(raw)
    return mesh


def dome_mesh(name):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=40, v_segments=20, radius=1.0)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.25], context="VERTS")
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.18)
    for v in bm.verts:
        # Placas superpuestas: escalones a lo largo del lomo.
        v.co.z += 0.04 * math.floor((v.co.y + 1) * 4) * (1 if v.co.z > 0 else 0)
    return mesh_from_bmesh(name, bm)


def roughen(mesh, amount, seed):
    if amount <= 0:
        return
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.normal_update()
    offset = Vector((seed * 7.1, seed * 3.3, seed * 5.7))
    for v in bm.verts:
        p = v.co * 2.2 + offset
        bump = noise.noise(p) + 0.5 * noise.noise(p * 3.1)
        v.co += v.normal * amount * bump
    bm.to_mesh(mesh)
    bm.free()


def fit_box(mesh, size):
    # Centra la malla y la estira para que su caja sea exactamente la de la Part.
    target = rb_size(size)
    lo = Vector((min(v.co[i] for v in mesh.vertices) for i in range(3)))
    hi = Vector((max(v.co[i] for v in mesh.vertices) for i in range(3)))
    center = (lo + hi) / 2
    extent = hi - lo
    scale = Vector((target[i] / extent[i] if extent[i] > 1e-6 else 1 for i in range(3)))
    for v in mesh.vertices:
        v.co = Vector(((v.co[i] - center[i]) * scale[i] for i in range(3)))


def triangle_count(mesh):
    return sum(len(p.vertices) - 2 for p in mesh.polygons)


def limit_triangles(name, mesh):
    tris = triangle_count(mesh)
    if tris <= MAX_TRIS:
        return mesh
    obj = bpy.data.objects.new(name + "_dec", mesh)
    bpy.context.scene.collection.objects.link(obj)
    decimate = obj.modifiers.new("Decimate", "DECIMATE")
    decimate.ratio = MAX_TRIS / tris * 0.95
    depsgraph = bpy.context.evaluated_depsgraph_get()
    reduced = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(mesh)
    reduced.name = name
    return reduced


def box_mesh(name, size):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    mesh = mesh_from_bmesh(name, bm)
    fit_box(mesh, size)
    return mesh


def material(name, color, roughness):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.roughness = roughness
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    if roughness == NEON:
        bsdf.inputs["Emission Color"].default_value = (*color, 1)
        bsdf.inputs["Emission Strength"].default_value = 3.0
    return mat


def build_piece(kind, name, size, shape, color, finish, rough, seed):
    full = f"{kind}_{name}"
    if shape is None:
        mesh = box_mesh(full, size)
    else:
        mesh = dome_mesh(full) if shape == "dome" else skin_mesh(full, shape())
        fit_box(mesh, size)
        roughen(mesh, rough * min(size), seed)
        fit_box(mesh, size)
        mesh = limit_triangles(full, mesh)
    for polygon in mesh.polygons:
        polygon.use_smooth = shape is not None
    mesh.materials.append(material(f"{kind}_{name}_mat", color, finish))
    return mesh


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_cavity = True
    shading.show_shadows = True
    shading.show_specular_highlight = True
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("Dark")
    world.color = (0.035, 0.035, 0.045)
    scene.world = world
    scene.unit_settings.system = "NONE"
    return scene


def build_creature(scene, kind, parts):
    """Crea dos colecciones: la de exportación (una pieza por nombre, sin rotar) y la vista armada."""
    export = bpy.data.collections.new(f"{kind}_export")
    shown = bpy.data.collections.new(kind)
    scene.collection.children.link(export)
    scene.collection.children.link(shown)

    root = bpy.data.objects.new(f"{kind}_root", None)
    shown.objects.link(root)

    meshes = {}
    report = []
    for index, (name, size, pos, angles, shape, color, finish, rough) in enumerate(parts):
        if name not in meshes:
            meshes[name] = build_piece(kind, name, size, shape, color, finish, rough, index + len(kind))
            if shape is not None:
                piece = bpy.data.objects.new(name, meshes[name])
                piece.location = rb(*pos)
                export.objects.link(piece)
                report.append(f"{name}:{triangle_count(meshes[name])}")
        placed = bpy.data.objects.new(f"{kind}_{name}_{index}", meshes[name])
        placed.matrix_world = roblox_cframe(pos, angles)
        placed.parent = root
        shown.objects.link(placed)

    # Apoya la criatura en el suelo (z = 0) para los renders.
    bpy.context.view_layer.update()
    lowest = min(
        (obj.matrix_world @ Vector(corner)).z
        for obj in shown.objects if obj.type == "MESH"
        for corner in obj.bound_box
    )
    root.location.z -= lowest
    print(f"[NOCTURNA] {kind}: " + ", ".join(report))
    return export, shown, root


def collection_bounds(collection):
    bpy.context.view_layer.update()
    points = [
        obj.matrix_world @ Vector(corner)
        for obj in collection.all_objects if obj.type == "MESH"
        for corner in obj.bound_box
    ]
    lo = Vector((min(p[i] for p in points) for i in range(3)))
    hi = Vector((max(p[i] for p in points) for i in range(3)))
    return lo, hi


def aim_camera(scene, lo, hi, wide=False):
    camera = scene.camera
    center = (lo + hi) / 2
    radius = (hi - lo).length / 2
    distance = radius * (1.6 if wide else 2.6)
    direction = Vector((0.55, -1.0, 0.35)).normalized()
    camera.location = center + direction * distance
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 40 if wide else 50


def render(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    scene = reset_scene()
    os.makedirs(os.path.join(OUT, "fbx"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "previews"), exist_ok=True)

    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    scene.collection.objects.link(camera)
    scene.camera = camera

    ground_mesh = bpy.data.meshes.new("Ground")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=60)
    ground_mesh = mesh_from_bmesh("Ground", bm)
    ground_mesh.materials.append(material("Ground_mat", (0.08, 0.08, 0.09), 0.9))
    ground = bpy.data.objects.new("Ground", ground_mesh)
    scene.collection.objects.link(ground)

    built = {}
    for kind, factory in CREATURES.items():
        built[kind] = build_creature(scene, kind, factory())

    # FBX: sólo las piezas, sin rotación, con nombre igual al de la Part.
    for kind, (export, _, _) in built.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in export.objects:
            obj.select_set(True)
        bpy.ops.export_scene.fbx(
            filepath=os.path.join(OUT, "fbx", f"{kind}.fbx"),
            use_selection=True,
            object_types={"MESH"},
            axis_forward="-Z",
            axis_up="Y",
            apply_scale_options="FBX_SCALE_NONE",
            mesh_smooth_type="FACE",
            use_mesh_modifiers=True,
            add_leaf_bones=False,
            bake_anim=False,
        )

    # Renders individuales.
    for kind, (export, shown, _) in built.items():
        for other, (other_export, other_shown, _) in built.items():
            other_export.hide_render = True
            other_shown.hide_render = other != kind
        lo, hi = collection_bounds(shown)
        aim_camera(scene, lo, hi)
        render(scene, os.path.join(OUT, "previews", f"{kind}.png"))

    # Las cinco juntas, a escala, con una persona de referencia (5 studs).
    x = 0.0
    for kind, (export, shown, root) in built.items():
        shown.hide_render = False
        lo, hi = collection_bounds(shown)
        root.location.x += x - lo.x
        x += (hi.x - lo.x) + 3
    person = bpy.data.objects.new("Person_reference", box_mesh("Person_reference", (1.6, 5, 0.8)))
    person.data.materials.append(material("Person_mat", (0.25, 0.32, 0.45), 0.5))
    person.location = (x + 1, 0, 2.5)
    scene.collection.objects.link(person)
    lo = Vector((-2, -6, 0))
    hi = Vector((x + 3, 6, 13))
    scene.render.resolution_x = 1800
    aim_camera(scene, lo, hi, wide=True)
    render(scene, os.path.join(OUT, "previews", "Lineup.png"))

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "NOCTURNA_Creatures.blend"), compress=True)
    print("[NOCTURNA] Listo:", OUT)


# prepare_ai_models.py importa este archivo para reusar CREATURES sin ejecutarlo.
if __name__ == "__main__":
    main()
