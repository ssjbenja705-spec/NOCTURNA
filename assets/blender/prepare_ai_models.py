"""Prepara para Roblox los modelos realistas generados con IA (Meshy, Tripo...).

Uso (desde la raíz del repositorio):
  blender --background --factory-startup --python assets/blender/prepare_ai_models.py -- assets/models [fuentes] [config]

  fuentes  carpeta con <Criatura>.glb / .gltf / .fbx / .obj  (por defecto assets/models/ai)
  config   archivo Luau que se genera  (por defecto src/server/Monsters/CreatureMeshes.lua)

Por cada criatura encontrada:
  1. Une la malla, la reduce a MAX_TRIS triángulos y las texturas a TEXTURE_SIZE px.
  2. La escala y la ubica sobre la criatura del juego (CREATURES de build_creatures.py),
     con los pies donde los tiene la versión simple.
  3. Corta cada cara hacia la pieza animada más cercana (Torso, Head, Arm, Leg...).
     Las piezas repetidas se numeran en el orden de MonsterFactory: Arm1, Arm2...
  4. Exporta fbx/<Criatura>_AI.fbx con las texturas adentro, los mapas PBR sueltos
     para una SurfaceAppearance, una vista previa y las medidas de cada pieza.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_creatures as creatures  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGS[0] if len(ARGS) > 0 else "assets/models")
SOURCES = os.path.abspath(ARGS[1] if len(ARGS) > 1 else os.path.join(OUT, "ai"))
CONFIG = os.path.abspath(ARGS[2] if len(ARGS) > 2 else os.path.join(OUT, "..", "..", "src", "server", "Monsters", "CreatureMeshes.lua"))

MAX_TRIS = 18000
TEXTURE_SIZE = 1024
EXTENSIONS = (".glb", ".gltf", ".fbx", ".obj")
# Piezas que no reciben geometría: los ojos de neón no se usan con un modelo realista.
SKIP = {"Eye"}
# Giro extra (grados, alrededor del eje vertical) si el generador dejó una criatura
# mirando a un costado. El frente correcto es -Z de Roblox.
TURN = {}

TO_BLENDER = creatures.TO_BLENDER
TO_ROBLOX = TO_BLENDER.inverted()


# --- Piezas del juego -------------------------------------------------------------


class Box:
    def __init__(self, key, name, size, pos, angles):
        self.key = key
        self.name = name
        self.half = Vector(size) / 2
        rx, ry, rz = angles
        rotation = Matrix.Rotation(rx, 4, "X") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rz, 4, "Z")
        self.matrix = Matrix.Translation(Vector(pos)) @ rotation
        self.inverse = self.matrix.inverted()

    def score(self, point):
        # Distancia firmada a la caja: negativa adentro, positiva afuera.
        local = self.inverse @ point
        q = Vector((abs(local[i]) - self.half[i] for i in range(3)))
        outside = Vector((max(c, 0) for c in q)).length
        inside = min(max(q), 0)
        return outside + inside

    def corners(self):
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    yield self.matrix @ Vector((sx * self.half.x, sy * self.half.y, sz * self.half.z))


def boxes_for(kind):
    counts = {}
    result = []
    for name, size, pos, angles, *_ in creatures.CREATURES[kind]():
        counts[name] = counts.get(name, 0) + 1
        if name not in SKIP:
            result.append(Box(f"{name}{counts[name]}", name, size, pos, angles))
    return result


def bounds(points):
    points = list(points)
    lo = Vector((min(p[i] for p in points) for i in range(3)))
    hi = Vector((max(p[i] for p in points) for i in range(3)))
    return lo, hi


# --- Malla ----------------------------------------------------------------------------


def import_source(path):
    before = set(bpy.data.objects)
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        bpy.ops.wm.obj_import(filepath=path)
    meshes = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    if not meshes:
        raise RuntimeError(f"{path} no tiene mallas")

    # Lleva todo al espacio del mundo y lo une en una sola malla.
    for obj in meshes:
        obj.modifiers.clear()
        obj.data = obj.data.copy()
        obj.data.transform(obj.matrix_world)
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    merged = bpy.context.view_layer.objects.active

    for obj in [o for o in bpy.data.objects if o not in before and o != merged]:
        bpy.data.objects.remove(obj)
    return merged


def triangles(mesh):
    return sum(len(p.vertices) - 2 for p in mesh.polygons)


def reduce(obj):
    tris = triangles(obj.data)
    if tris <= MAX_TRIS:
        return
    decimate = obj.modifiers.new("Decimate", "DECIMATE")
    decimate.ratio = MAX_TRIS / tris * 0.97
    depsgraph = bpy.context.evaluated_depsgraph_get()
    reduced = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    old = obj.data
    obj.modifiers.clear()
    obj.data = reduced
    bpy.data.meshes.remove(old)


def to_roblox_space(obj, kind, boxes):
    mesh = obj.data
    if mesh.has_custom_normals:
        # Las normales importadas no sobreviven al recorte; se recalculan suaves.
        bpy.context.view_layer.objects.active = obj
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    mesh.transform(TO_ROBLOX.to_4x4())
    if TURN.get(kind):
        mesh.transform(Matrix.Rotation(math.radians(TURN[kind]), 4, "Y"))

    # Mismo volumen que la criatura simple y apoyada en el mismo piso.
    lo, hi = bounds(v.co for v in mesh.vertices)
    target_lo, target_hi = bounds(c for box in boxes for c in box.corners())
    extent, target = hi - lo, target_hi - target_lo
    ratio = (target.x / extent.x * target.y / extent.y * target.z / extent.z) ** (1 / 3)
    mesh.transform(Matrix.Scale(ratio, 4))
    lo, hi = bounds(v.co for v in mesh.vertices)
    move = Vector((
        (target_lo.x + target_hi.x) / 2 - (lo.x + hi.x) / 2,
        target_lo.y - lo.y,
        (target_lo.z + target_hi.z) / 2 - (lo.z + hi.z) / 2,
    ))
    mesh.transform(Matrix.Translation(move))
    for polygon in mesh.polygons:
        polygon.use_smooth = True


def cut(obj, boxes):
    """Devuelve {clave: (malla en ejes de Blender, tamaño, desplazamiento)}."""
    mesh = obj.data
    owner = []
    for polygon in mesh.polygons:
        center = polygon.center
        owner.append(min(range(len(boxes)), key=lambda i: boxes[i].score(center)))

    pieces = {}
    for index, box in enumerate(boxes):
        if index not in owner:
            continue
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if owner[f.index] != index], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")

        # Ejes de la pieza: así la MeshPart queda orientada como la Part simple.
        for v in bm.verts:
            v.co = box.inverse @ v.co
        lo, hi = bounds(v.co for v in bm.verts)
        shift = (lo + hi) / 2
        size = hi - lo
        for v in bm.verts:
            v.co = TO_BLENDER @ (v.co - shift)

        piece = bpy.data.meshes.new(box.key)
        bm.to_mesh(piece)
        bm.free()
        for material in mesh.materials:
            piece.materials.append(material)
        pieces[box.key] = (piece, size, shift)
    return pieces


# --- Texturas -------------------------------------------------------------------------


def linked_image(socket):
    # Sigue los enlaces hacia atrás hasta encontrar una textura.
    pending = [socket]
    while pending:
        current = pending.pop()
        for link in current.links:
            node = link.from_node
            if node.type == "TEX_IMAGE" and node.image:
                return node.image, link.from_socket
            pending.extend(i for i in node.inputs if i.is_linked)
    return None, None


def save_channel(image, channel, path):
    width, height = image.size
    pixels = numpy.empty(width * height * 4, dtype=numpy.float32)
    image.pixels.foreach_get(pixels)
    rgba = pixels.reshape(-1, 4)
    out = numpy.ones_like(rgba)
    for i in range(3):
        out[:, i] = rgba[:, channel]
    single = bpy.data.images.new(os.path.basename(path), width, height)
    single.pixels.foreach_set(out.ravel())
    single.filepath_raw = path
    single.file_format = "PNG"
    single.save()
    bpy.data.images.remove(single)


def save_image(image, path):
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()


def prepare_textures(kind, materials):
    for image in bpy.data.images:
        width, height = image.size
        if max(width, height) > TEXTURE_SIZE:
            factor = TEXTURE_SIZE / max(width, height)
            image.scale(max(1, round(width * factor)), max(1, round(height * factor)))

    folder = os.path.join(OUT, "ai_textures", kind)
    os.makedirs(folder, exist_ok=True)
    written = []
    for material in materials:
        if not material or not material.use_nodes:
            continue
        bsdf = next((n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if not bsdf:
            continue
        maps = {
            "Color": bsdf.inputs["Base Color"],
            "Normal": bsdf.inputs["Normal"],
            "Roughness": bsdf.inputs["Roughness"],
            "Metalness": bsdf.inputs["Metallic"],
        }
        for label, socket in maps.items():
            image, source = linked_image(socket)
            if not image:
                continue
            path = os.path.join(folder, f"{kind}_{label}.png")
            if label in ("Roughness", "Metalness") and source and source.name == "Color":
                # glTF guarda rugosidad (G) y metal (B) en una sola imagen; Roblox los quiere sueltos.
                save_channel(image, 1 if label == "Roughness" else 2, path)
            else:
                save_image(image, path)
            written.append(label)
        break
    return written


# --- Salida ---------------------------------------------------------------------------


def export_fbx(kind, pieces):
    bpy.ops.object.select_all(action="DESELECT")
    objects = []
    for key, (mesh, _, _) in pieces.items():
        obj = bpy.data.objects.new(key, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.select_set(True)
        objects.append(obj)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT, "fbx", f"{kind}_AI.fbx"),
        use_selection=True,
        object_types={"MESH"},
        axis_forward="-Z",
        axis_up="Y",
        apply_scale_options="FBX_SCALE_NONE",
        mesh_smooth_type="FACE",
        path_mode="COPY",
        embed_textures=True,
        add_leaf_bones=False,
        bake_anim=False,
    )
    return objects


def render_preview(kind, objects, pieces, boxes):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "TEXTURE"
    shading.show_cavity = True
    shading.show_shadows = True
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    world = bpy.data.worlds.get("Dark") or bpy.data.worlds.new("Dark")
    world.color = (0.035, 0.035, 0.045)
    scene.world = world

    by_key = {box.key: box for box in boxes}
    for obj in objects:
        box = by_key[obj.name]
        shift = pieces[obj.name][2]
        placed = box.matrix @ Matrix.Translation(shift)
        obj.matrix_world = TO_BLENDER.to_4x4() @ placed @ TO_ROBLOX.to_4x4()
    bpy.context.view_layer.update()

    lo, hi = bounds(obj.matrix_world @ Vector(c) for obj in objects for c in obj.bound_box)
    camera = scene.camera
    if camera is None:
        camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
        scene.collection.objects.link(camera)
        scene.camera = camera
    center = (lo + hi) / 2
    distance = (hi - lo).length / 2 * 2.6
    camera.location = center + Vector((0.55, -1.0, 0.35)).normalized() * distance
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 50

    scene.render.filepath = os.path.join(OUT, "previews", f"{kind}_AI.png")
    bpy.ops.render.render(write_still=True)


def luau_vector(v):
    return "Vector3.new({:.4f}, {:.4f}, {:.4f})".format(*v)


def write_config(results):
    lines = [
        "-- Generado por assets/blender/prepare_ai_models.py: no editar a mano.",
        "-- Medidas de las piezas cortadas de los modelos realistas (assets/models/ai).",
        "-- Size: tamaño real de la MeshPart. Shift: centro de la malla respecto del",
        "-- centro de la pieza simple, en los ejes de esa pieza.",
        "return {",
    ]
    for kind in sorted(results):
        lines.append(f"    {kind} = {{")
        for key, size, shift in results[kind]:
            lines.append(f"        {key} = {{Size = {luau_vector(size)}, Shift = {luau_vector(shift)}}},")
        lines.append("    },")
    lines.append("}")
    with open(CONFIG, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def find_source(kind):
    for ext in EXTENSIONS:
        path = os.path.join(SOURCES, kind + ext)
        if os.path.exists(path):
            return path
    return None


def main():
    os.makedirs(os.path.join(OUT, "fbx"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "previews"), exist_ok=True)

    results = {}
    for kind in creatures.CREATURES:
        source = find_source(kind)
        if not source:
            print(f"[NOCTURNA] {kind}: sin modelo en {SOURCES}, se omite")
            continue

        bpy.ops.wm.read_factory_settings(use_empty=True)
        boxes = boxes_for(kind)
        obj = import_source(source)
        original = triangles(obj.data)
        reduce(obj)
        to_roblox_space(obj, kind, boxes)
        materials = list(obj.data.materials)
        pieces = cut(obj, boxes)
        textures = prepare_textures(kind, materials)
        bpy.data.objects.remove(obj)

        objects = export_fbx(kind, pieces)
        render_preview(kind, objects, pieces, boxes)
        results[kind] = [(key, size, shift) for key, (_, size, shift) in pieces.items()]

        counts = ", ".join(f"{key}:{triangles(mesh)}" for key, (mesh, _, _) in pieces.items())
        print(f"[NOCTURNA] {kind}: {original} -> {sum(triangles(m) for m, _, _ in pieces.values())} triángulos; {counts}")
        print(f"[NOCTURNA] {kind}: texturas {', '.join(textures) or 'ninguna'}")

    write_config(results)
    print(f"[NOCTURNA] Listo: {len(results)} criaturas. Medidas en {CONFIG}")


if __name__ == "__main__":
    main()
