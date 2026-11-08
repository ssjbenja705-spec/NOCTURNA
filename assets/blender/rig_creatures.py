"""Esqueletos (huesos) para las criaturas realistas generadas con IA.

Uso (desde la raíz del repositorio):
  blender --background --factory-startup --python assets/blender/rig_creatures.py -- assets/models [Criatura ...]

Por cada assets/models/ai/<Criatura>.glb:
  1. Une y reduce la malla (MAX_TRIS) y la lleva al espacio del juego con la misma
     escala, frente (-Z de Roblox) y altura de pies que prepare_ai_models.py, así
     las alturas de MonsterConfig siguen valiendo. La raíz de la criatura
     (HumanoidRootPart) queda en el origen: ahí va el hueso Root.
  2. Clasifica cada vértice en una región (torso, cabeza, brazo, pierna...) con
     las mismas cajas que usa el corte en piezas (AI_BOXES).
  3. Mide la anatomía de cada región sobre la malla (no hay imágenes): cortes
     horizontales con su centro y su grosor dan la cadera, la rodilla (donde la
     pierna se dobla, o la mitad), el tobillo (lo más angosto abajo), la punta del
     pie, el hombro, el codo, la muñeca y la punta de los dedos; el torso da la
     columna y la cabeza el cuello. Imprime todo para revisar.
  4. Arma el esqueleto (nombres sin puntos ni espacios), lo pesa con pesos
     automáticos de Blender y limpia: cada vértice sólo puede depender de huesos
     de su región o vecinos; si el cálculo automático falla en algún vértice usa
     la distancia al hueso más cercano. Máximo 4 huesos por vértice (Roblox).
  5. Exporta models/rigged/<Criatura>.fbx (malla con piel + esqueleto en pose de
     descanso, texturas adentro), <Criatura>.json (huesos, padres, largos), una
     vista previa con la pose doblada en models/previews/<Criatura>_rig.png y las
     medidas para el juego en src/server/Monsters/CreatureRigs.lua.
"""

import json
import math
import os
import sys
import tempfile

import bpy
import numpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import prepare_ai_models as prep  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(ARGS[0] if len(ARGS) > 0 else "assets/models")
ONLY = set(ARGS[1:])
SOURCES = os.path.join(OUT, "ai")
RIGGED = os.path.join(OUT, "rigged")
PREVIEWS = os.path.join(OUT, "previews")
CONFIG = os.path.abspath(os.path.join(OUT, "..", "..", "src", "server", "Monsters", "CreatureRigs.lua"))

MAX_TRIS = 18000
TEXTURE_SIZE = 1024
MAX_INFLUENCES = 4
MIN_WEIGHT = 0.02

TO_BLENDER = prep.TO_BLENDER
TO_ROBLOX = TO_BLENDER.inverted()

# Segmentos de columna entre la cadera y el pecho (El Trepador es más segmentado).
SPINES = {"ElTrepador": 3}
# Cuánto de la extremidad es mano (desde la punta de los dedos hasta la muñeca),
# rango donde se busca la muñeca (lo más angosto).
# Fracción del largo de la extremidad (desde abajo) donde se busca la muñeca y el
# tobillo: lo más angosto de esa franja. Se parte de proporciones humanas (la mano
# es ~1/4 del brazo, el tobillo está a ~7% de la pierna) y se ajusta a la malla.
WRIST_WINDOW = {"default": (0.2, 0.32), "ElOyente": (0.22, 0.36), "ElImitador": (0.22, 0.34),
                "ElTrepador": (0.14, 0.3), "ElColoso": (0.16, 0.3)}
ANKLE_WINDOW = {"default": (0.05, 0.11), "ElTrepador": (0.08, 0.2), "ElColoso": (0.06, 0.14)}
# Criaturas con patas dobladas en reposo: la rodilla y el codo se buscan donde la
# extremidad se aparta de la recta (no en la mitad).
BENT = {"ElTrepador"}


def log(kind, text):
    print(f"[NOCTURNA rig] {kind}: {text}")


# --- Medición de la anatomía ---------------------------------------------------------


def v3(p):
    return Vector((float(p[0]), float(p[1]), float(p[2])))


def slices(points, count=48):
    """Cortes horizontales de arriba hacia abajo: (y, centro, grosor, n)."""
    lo, hi = points[:, 1].min(), points[:, 1].max()
    step = max((hi - lo) / count, 1e-4)
    result = []
    for i in range(count):
        top = hi - i * step
        mask = (points[:, 1] <= top) & (points[:, 1] > top - step)
        if mask.sum() < 4:
            continue
        chunk = points[mask]
        center = numpy.median(chunk, axis=0)
        spread = numpy.sqrt((chunk[:, 0] - center[0]) ** 2 + (chunk[:, 2] - center[2]) ** 2)
        result.append((top - step / 2, center, float(numpy.percentile(spread, 60)), int(mask.sum())))
    return result


def band_center(points, y, half):
    mask = numpy.abs(points[:, 1] - y) <= half
    if mask.sum() < 3:
        index = numpy.argmin(numpy.abs(points[:, 1] - y))
        return v3(points[index])
    return v3(numpy.median(points[mask], axis=0))


def narrowest(cuts, low, high):
    """El corte más angosto con y entre low y high (tobillo, muñeca)."""
    best = None
    for y, center, radius, _ in cuts:
        if low <= y <= high and (best is None or radius < best[2]):
            best = (y, center, radius)
    return best


def bend_point(cuts, start, end, length, bent=False, prefer=-1):
    """Rodilla o codo: el centro que más se aparta de la recta (patas dobladas); si
    la extremidad está casi derecha, en la mitad, apenas corrida hacia donde se
    dobla (prefer: -1 adelante para rodillas, +1 atrás para codos). En criaturas
    de dos patas no se acepta una rodilla doblada al revés (sería ruido de la
    malla: una mano o una placa cerca)."""
    chord = end - start
    span = chord.length
    if span < 1e-4:
        return (start + end) / 2, 0.0
    direction = chord / span
    best, best_dev = None, 0.0
    for y, center, _, _ in cuts:
        p = v3(center)
        p.y = y
        t = (p - start).dot(direction) / span
        if (0.25 <= t <= 0.75) if bent else (0.42 <= t <= 0.6):
            offset = p - (start + direction * t * span)
            deviation = offset.length
            if not bent and offset.z * prefer < 0:
                continue
            if deviation > best_dev:
                best, best_dev = p, deviation
    if best is not None and best_dev > (0.06 if bent else 0.1) * span:
        return best, best_dev
    mid_y = start.y + (end.y - start.y) * 0.5
    nearest = min(cuts, key=lambda c: abs(c[0] - mid_y))
    p = v3(nearest[1])
    p.y = mid_y
    # La rodilla o el codo quedan sobre la recta, corridos hacia el centro medido
    # de costado y hacia donde se doblan.
    on_line = (start + end) / 2
    point = on_line.lerp(p, 0.5)
    point.z = on_line.z + prefer * 0.05 * span
    return point, best_dev


def measure_leg(kind, points, side):
    top, bottom = float(points[:, 1].max()), float(points[:, 1].min())
    length = top - bottom
    hip = band_center(points, top - 0.06 * length, 0.05 * length)
    hip.y = top - 0.05 * length
    cuts = slices(points)
    low, high = ANKLE_WINDOW.get(kind, ANKLE_WINDOW["default"])
    found = narrowest(cuts, bottom + low * length, bottom + high * length)
    guess = bottom + (low + high) / 2 * length
    ankle = v3(found[1]) if found else band_center(points, guess, 0.03 * length)
    ankle.y = found[0] if found else guess
    below = points[points[:, 1] < ankle.y]
    if len(below) < 4:
        below = points[points[:, 1] < bottom + 0.1 * length]
    toe = v3(below[numpy.argmin(below[:, 2])])
    heel = v3(below[numpy.argmax(below[:, 2])])
    ball = ankle.lerp(toe, 0.62)
    ball.y = bottom + 0.3 * (ankle.y - bottom)
    toe.y = bottom + 0.15 * (ankle.y - bottom)
    knee, deviation = bend_point(cuts, hip, ankle, length, kind in BENT, -1)
    return {"Hip": hip, "Knee": knee, "Ankle": ankle, "Ball": ball, "Toe": toe, "Heel": heel,
            "Length": length, "Bend": deviation, "Side": side}


def measure_arm(kind, points, side):
    top = float(points[:, 1].max())
    tip_index = numpy.argmin(points[:, 1])
    bottom = float(points[tip_index, 1])
    length = top - bottom
    shoulder = band_center(points, top - 0.07 * length, 0.05 * length)
    shoulder.y = top - 0.06 * length
    cuts = slices(points)
    low, high = WRIST_WINDOW.get(kind, WRIST_WINDOW["default"])
    found = narrowest(cuts, bottom + low * length, bottom + high * length)
    guess = bottom + (low + high) / 2 * length
    wrist = v3(found[1]) if found else band_center(points, guess, 0.03 * length)
    wrist.y = found[0] if found else guess
    hand = wrist.y - bottom
    knuckle = band_center(points, wrist.y - 0.4 * hand, 0.06 * hand)
    middle = band_center(points, wrist.y - 0.72 * hand, 0.06 * hand)
    lowest = points[points[:, 1] < bottom + 0.06 * hand]
    tip = v3(lowest.mean(axis=0)) if len(lowest) >= 3 else v3(points[tip_index])
    tip.y = bottom
    elbow, deviation = bend_point(cuts, shoulder, wrist, length, kind in BENT, 1)
    return {"Shoulder": shoulder, "Elbow": elbow, "Wrist": wrist, "Knuckle": knuckle, "Middle": middle,
            "Tip": tip, "Length": length, "Bend": deviation, "Side": side}


def mirror_pair(left, right, keys):
    """Promedia izquierda y derecha (espejadas) para un esqueleto simétrico."""
    for key in keys:
        a, b = left[key], right[key]
        x = (abs(a.x) + abs(b.x)) / 2
        y = (a.y + b.y) / 2
        z = (a.z + b.z) / 2
        left[key] = Vector((-x, y, z))
        right[key] = Vector((x, y, z))


# --- Esqueleto ------------------------------------------------------------------------


class Bone:
    def __init__(self, name, head, tail, parent, region):
        self.name = name
        self.head = Vector(head)
        self.tail = Vector(tail)
        self.parent = parent
        self.region = region


def safe_tail(head, tail, minimum=0.08):
    if (tail - head).length < minimum:
        return head + Vector((0, minimum, 0))
    return tail


def build_skeleton(kind, regions):
    torso = regions["Torso"]
    head_points = regions["Head"]
    legs = {"Left": measure_leg(kind, regions["LegLeft"], -1), "Right": measure_leg(kind, regions["LegRight"], 1)}
    arms = {"Left": measure_arm(kind, regions["ArmLeft"], -1), "Right": measure_arm(kind, regions["ArmRight"], 1)}
    mirror_pair(legs["Left"], legs["Right"], ["Hip", "Knee", "Ankle", "Ball", "Toe", "Heel"])
    mirror_pair(arms["Left"], arms["Right"], ["Shoulder", "Elbow", "Wrist", "Knuckle", "Middle", "Tip"])
    for side in ("Left", "Right"):
        leg, arm = legs[side], arms[side]
        log(kind, "{} pierna: cadera {} rodilla {} (curva {:.2f}) tobillo {} punta {}".format(
            side, fmt(leg["Hip"]), fmt(leg["Knee"]), leg["Bend"], fmt(leg["Ankle"]), fmt(leg["Toe"])))
        log(kind, "{} brazo: hombro {} codo {} (curva {:.2f}) muñeca {} dedos {}".format(
            side, fmt(arm["Shoulder"]), fmt(arm["Elbow"]), arm["Bend"], fmt(arm["Wrist"]), fmt(arm["Tip"])))

    hip_y = legs["Left"]["Hip"].y
    leg_length = legs["Left"]["Length"]
    shoulder_y = arms["Left"]["Shoulder"].y
    shoulder_z = arms["Left"]["Shoulder"].z
    pelvis_z = legs["Left"]["Hip"].z
    pelvis = Vector((0, hip_y + 0.06 * leg_length, pelvis_z))
    chest_top = Vector((0, shoulder_y, shoulder_z))

    # Columna: centro del torso en franjas entre la pelvis y los hombros.
    spines = SPINES.get(kind, 2)
    span = max(chest_top.y - pelvis.y, 0.3)
    points = []
    for i in range(spines + 2):
        f = i / (spines + 1) * 0.82
        y = pelvis.y + span * f
        center = band_center(torso, y, span * 0.07)
        points.append(Vector((0, y, center.z)))
    points[0] = pelvis

    # Cabeza y cuello.
    head_lo, head_hi = float(head_points[:, 1].min()), float(head_points[:, 1].max())
    head_height = head_hi - head_lo
    head_base = band_center(head_points, head_lo + 0.22 * head_height, 0.12 * head_height)
    head_base.x = 0
    crown = band_center(head_points, head_hi - 0.08 * head_height, 0.08 * head_height)
    crown.x = 0
    crown.y = head_hi
    neck_base = points[-1].lerp(head_base, 0.4)
    neck_base.x = 0
    if neck_base.y < points[-1].y:
        neck_base.y = points[-1].y + 0.02
    log(kind, "columna {} | cuello {} | cabeza {} -> {}".format(
        " ".join(fmt(p) for p in points), fmt(neck_base), fmt(head_base), fmt(crown)))

    bones = [Bone("Root", (0, 0, 0), (0, 0.6, 0), None, None),
             Bone("Hips", pelvis, points[1], "Root", "Torso")]
    parent = "Hips"
    for i in range(1, spines + 1):
        name = f"Spine{i}"
        bones.append(Bone(name, points[i], points[i + 1], parent, "Torso"))
        parent = name
    bones.append(Bone("Chest", points[-1], neck_base, parent, "Torso"))
    bones.append(Bone("Neck", neck_base, head_base, "Chest", "Head"))
    bones.append(Bone("Head", head_base, safe_tail(head_base, crown), "Neck", "Head"))

    for side in ("Left", "Right"):
        leg, arm = legs[side], arms[side]
        sign = -1 if side == "Left" else 1
        clavicle = Vector((sign * abs(arm["Shoulder"].x) * 0.3, arm["Shoulder"].y - 0.02 * leg_length, points[-1].z))
        bones += [
            Bone(f"{side}Clavicle", clavicle, arm["Shoulder"], "Chest", f"Arm{side}"),
            Bone(f"{side}UpperArm", arm["Shoulder"], arm["Elbow"], f"{side}Clavicle", f"Arm{side}"),
            Bone(f"{side}Forearm", arm["Elbow"], arm["Wrist"], f"{side}UpperArm", f"Arm{side}"),
            Bone(f"{side}Hand", arm["Wrist"], arm["Knuckle"], f"{side}Forearm", f"Arm{side}"),
            Bone(f"{side}Fingers1", arm["Knuckle"], arm["Middle"], f"{side}Hand", f"Arm{side}"),
            Bone(f"{side}Fingers2", arm["Middle"], safe_tail(arm["Middle"], arm["Tip"]), f"{side}Fingers1", f"Arm{side}"),
            Bone(f"{side}Thigh", leg["Hip"], leg["Knee"], "Hips", f"Leg{side}"),
            Bone(f"{side}Shin", leg["Knee"], leg["Ankle"], f"{side}Thigh", f"Leg{side}"),
            Bone(f"{side}Foot", leg["Ankle"], leg["Ball"], f"{side}Shin", f"Leg{side}"),
            Bone(f"{side}Toe", leg["Ball"], safe_tail(leg["Ball"], leg["Toe"], 0.05), f"{side}Foot", f"Leg{side}"),
        ]

    if kind == "ElImitador" and "Jaw" in regions and len(regions["Jaw"]) >= 6:
        mouth = v3(regions["Jaw"].mean(axis=0))
        hinge = Vector((0, mouth.y + 0.06, head_base.z + 0.05))
        chin = Vector((0, mouth.y - 0.14, mouth.z - 0.02))
        bones.append(Bone("Jaw", hinge, chin, "Head", "Head"))
        log(kind, f"mandíbula: bisagra {fmt(hinge)} mentón {fmt(chin)}")
    else:
        mouth = None

    if kind == "ElColoso" and "Plate" in regions and len(regions["Plate"]) >= 12:
        plate = regions["Plate"]
        width = float(numpy.abs(plate[:, 0]).max())
        for name, mask, out in (
            ("PlateLeft", plate[:, 0] < -0.35 * width, Vector((-0.5, 0.35, 0.1))),
            ("PlateRight", plate[:, 0] > 0.35 * width, Vector((0.5, 0.35, 0.1))),
            ("PlateBack", (numpy.abs(plate[:, 0]) <= 0.35 * width) & (plate[:, 2] > numpy.median(plate[:, 2])), Vector((0, 0.3, 0.5))),
        ):
            chunk = plate[mask] if mask.sum() >= 4 else plate
            head = v3(chunk.mean(axis=0))
            bones.append(Bone(name, head, head + out.normalized() * 0.6, "Chest", "Plate"))
        log(kind, "placas sueltas: PlateLeft, PlateRight, PlateBack")

    if kind == "ElTrepador":
        # El abdomen segmentado sobresale atrás y arriba del pecho.
        top_y = float(torso[:, 1].max())
        if top_y > points[-1].y + 0.4:
            tip = band_center(torso, top_y - 0.1, 0.12)
            tip.x = 0
            bones.append(Bone("Abdomen", points[-1] + (tip - points[-1]) * 0.25, tip, "Chest", "Torso"))
            log(kind, f"abdomen hasta {fmt(tip)}")

    measures = {"Legs": legs, "Arms": arms, "Mouth": mouth}
    return bones, measures


def fmt(v):
    return "({:.2f}, {:.2f}, {:.2f})".format(v.x, v.y, v.z)


# --- Regiones ---------------------------------------------------------------------------

REGION_OF_BOX = {"Torso1": "Torso", "Head1": "Head", "Jaw1": "Jaw", "Plate1": "Plate",
                 "Arm1": "ArmLeft", "Arm2": "ArmRight", "Leg1": "LegLeft", "Leg2": "LegRight"}


def classify(mesh, boxes):
    """Región de cada vértice. Las cajas solas confunden lo que se toca (la mano
    que cuelga junto a la rodilla cae en la caja de la pierna), así que cada
    región crece desde el centro de su caja recorriendo la superficie (distancia
    por las aristas): la mano llega por la muñeca, no por el aire. Lo que no
    está unido a ningún centro (placas sueltas, garras aparte) usa la caja."""
    import heapq
    keys = [box.key for box in boxes]
    count = len(mesh.vertices)
    scores = numpy.empty((count, len(boxes)))
    for index, vertex in enumerate(mesh.vertices):
        for b, box in enumerate(boxes):
            scores[index, b] = box.score(vertex.co)
    owner = scores.argmin(axis=1)
    links = neighbors_of(mesh)
    best = numpy.full(count, numpy.inf)
    label = owner.copy()
    heap = []
    for b, box in enumerate(boxes):
        inside = numpy.where((owner == b) & (scores[:, b] < 0))[0]
        if len(inside) == 0:
            inside = numpy.argsort(scores[:, b])[:20]
            deep = inside
        else:
            cut = numpy.percentile(scores[inside, b], 35)
            deep = inside[scores[inside, b] <= cut]
        for index in deep:
            best[index] = 0.0
            label[index] = b
            heap.append((0.0, int(index), b))
    heapq.heapify(heap)
    co = numpy.array([tuple(v.co) for v in mesh.vertices])
    while heap:
        distance, index, b = heapq.heappop(heap)
        if distance > best[index] or label[index] != b:
            continue
        for other in links[index]:
            step = distance + float(numpy.linalg.norm(co[other] - co[index]))
            if step < best[other]:
                best[other] = step
                label[other] = b
                heapq.heappush(heap, (step, other, b))
    # Sólo se corrige lo que una caja de extremidad le robó a otra extremidad: el
    # límite con el torso y la cabeza (hombro, cadera, cuello) queda como lo
    # marcan las cajas, que se midieron ahí a propósito.
    limbs = {b for b, key in enumerate(keys) if REGION_OF_BOX.get(key, "").startswith(("Arm", "Leg"))}
    final = owner.copy()
    for index in range(count):
        if owner[index] in limbs and label[index] in limbs and numpy.isfinite(best[index]):
            final[index] = label[index]
    changed = int((final != owner).sum())
    return [REGION_OF_BOX.get(keys[b], "Torso") for b in final], changed


def allowed_bones(region, names):
    """Huesos de los que puede depender un vértice de esa región (y vecinos)."""
    spine = [n for n in names if n.startswith("Spine")] + ["Hips", "Chest"]
    if region and region.startswith("Leg"):
        side = region[3:]
        return [f"{side}Thigh", f"{side}Shin", f"{side}Foot", f"{side}Toe", "Hips"]
    if region and region.startswith("Arm"):
        side = region[3:]
        return [f"{side}Clavicle", f"{side}UpperArm", f"{side}Forearm", f"{side}Hand",
                f"{side}Fingers1", f"{side}Fingers2", "Chest"]
    if region == "Head":
        return ["Head", "Neck", "Jaw"]
    if region == "Jaw":
        return ["Head", "Jaw"]
    if region == "Plate":
        return ["Chest", "Neck", "PlateLeft", "PlateRight", "PlateBack"] + spine
    return spine + ["Neck", "Abdomen", "LeftClavicle", "RightClavicle", "LeftUpperArm", "RightUpperArm",
                    "LeftThigh", "RightThigh"]


def segment_distance(p, a, b):
    ab = b - a
    t = 0.0 if ab.length_squared < 1e-9 else max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


def nearest_weights(point, candidates):
    """Respaldo: por distancia a los huesos permitidos (los 3 más cercanos)."""
    scored = sorted(((segment_distance(point, b.head, b.tail), b.name) for b in candidates))[:3]
    raw = [(name, 1.0 / (d + 0.03) ** 4) for d, name in scored]
    total = sum(w for _, w in raw)
    return {name: w / total for name, w in raw}


# --- Blender ----------------------------------------------------------------------------


def make_armature(kind, bones):
    data = bpy.data.armatures.new(f"{kind}Armature")
    arm = bpy.data.objects.new(f"{kind}Rig", data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    forward = TO_BLENDER @ Vector((0, 0, -1))
    up = TO_BLENDER @ Vector((0, 1, 0))
    edit = {}
    for bone in bones:
        eb = data.edit_bones.new(bone.name)
        eb.head = TO_BLENDER @ bone.head
        eb.tail = TO_BLENDER @ bone.tail
        direction = (eb.tail - eb.head).normalized()
        eb.align_roll(forward if abs(direction.dot(forward)) < 0.85 else up)
        eb.use_connect = False
        if bone.parent:
            eb.parent = edit[bone.parent]
        edit[bone.name] = eb
    data.edit_bones["Root"].use_deform = False
    bpy.ops.object.mode_set(mode="OBJECT")
    data.display_type = "STICK"
    return arm


def skin(kind, mesh_obj, arm, bones, labels, measures, roblox_points):
    bpy.ops.object.select_all(action="DESELECT")
    mesh_obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    heat_ok = True
    try:
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    except RuntimeError as err:
        heat_ok = False
        log(kind, f"pesos automáticos fallaron ({err}); se usa el hueso más cercano")
        bpy.ops.object.parent_set(type="ARMATURE_NAME")

    mesh = mesh_obj.data
    by_name = {b.name: b for b in bones}
    names = [b.name for b in bones]
    group_names = {g.index: g.name for g in mesh_obj.vertex_groups}

    final = []
    allowed_of = []
    fallback = 0
    for index, vertex in enumerate(mesh.vertices):
        region = labels[index]
        allowed = [n for n in allowed_bones(region, names) if n in by_name]
        allowed_of.append(set(allowed))
        weights = {}
        for g in vertex.groups:
            name = group_names.get(g.group)
            if name in allowed and g.weight > 0:
                weights[name] = g.weight
        if sum(weights.values()) < 0.05:
            weights = nearest_weights(roblox_points[index], [by_name[n] for n in allowed])
            fallback += 1
        final.append(weights)
    # Una pasada de suavizado: las uniones entre regiones no quedan con escalón.
    final = smooth_weights(final, neighbors_of(mesh), allowed_of, rounds=2)

    # Boca de El Imitador: lo que queda bajo la comisura y adelante va con la mandíbula.
    mouth = measures.get("Mouth")
    if mouth is not None and "Jaw" in by_name:
        moved = 0
        for index, p in enumerate(roblox_points):
            if labels[index] not in ("Head", "Jaw"):
                continue
            if abs(p.x) > 0.42 or p.z > mouth.z + 0.38 or p.y > mouth.y + 0.03 or p.y < mouth.y - 0.6:
                continue
            t = min(max((mouth.y + 0.03 - p.y) / 0.1, 0.0), 1.0)
            t *= min(max((mouth.z + 0.38 - p.z) / 0.15, 0.0), 1.0)
            if t <= 0:
                continue
            final[index] = {"Jaw": t, "Head": 1 - t} if t < 1 else {"Jaw": 1.0}
            moved += 1
        log(kind, f"mandíbula: {moved} vértices")

    # Caparazón de El Coloso: las placas cuelgan sueltas sobre el pecho.
    plates = [by_name[n] for n in ("PlateLeft", "PlateRight", "PlateBack") if n in by_name]
    if plates:
        for index, p in enumerate(roblox_points):
            if labels[index] != "Plate":
                continue
            raw = {b.name: 1.0 / ((p - b.head).length + 0.2) ** 2 for b in plates}
            total = sum(raw.values())
            weights = {name: 0.6 * w / total for name, w in raw.items()}
            weights["Chest"] = 0.4
            final[index] = weights

    # Máximo 4 huesos, sin pesos chicos, normalizado.
    for group in list(mesh_obj.vertex_groups):
        mesh_obj.vertex_groups.remove(group)
    groups = {b.name: mesh_obj.vertex_groups.new(name=b.name) for b in bones if b.name != "Root"}
    used = set()
    for index, weights in enumerate(final):
        top = sorted(weights.items(), key=lambda kv: -kv[1])[:MAX_INFLUENCES]
        top = [(n, w) for n, w in top if w >= MIN_WEIGHT] or top[:1]
        total = sum(w for _, w in top)
        for name, w in top:
            groups[name].add([index], w / total, "REPLACE")
            used.add(name)
    log(kind, "pesos: {} automáticos, {} por cercanía ({}); huesos sin piel: {}".format(
        len(final) - fallback, fallback, "calor" if heat_ok else "sin calor",
        ", ".join(sorted(set(groups) - used)) or "ninguno"))
    return fallback


def scale_textures(kind, folder):
    """Texturas a 1024 px guardadas aparte para que el FBX las lleve adentro."""
    count = 0
    for image in bpy.data.images:
        if image.size[0] == 0:
            continue
        width, height = image.size
        if max(width, height) > TEXTURE_SIZE:
            factor = TEXTURE_SIZE / max(width, height)
            image.scale(max(1, round(width * factor)), max(1, round(height * factor)))
        safe = "".join(c if c.isalnum() else "_" for c in image.name)
        path = os.path.join(folder, f"{kind}_{safe}.png")
        image.filepath_raw = path
        image.file_format = "PNG"
        image.save()
        if image.packed_file:
            image.unpack(method="REMOVE")
        image.filepath = path
        image.reload()
        count += 1
    return count


def export_fbx(kind, mesh_obj, arm):
    bpy.ops.object.select_all(action="DESELECT")
    mesh_obj.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    path = os.path.join(RIGGED, f"{kind}.fbx")
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        object_types={"ARMATURE", "MESH"},
        axis_forward="-Z",
        axis_up="Y",
        global_scale=1.0,
        apply_unit_scale=False,
        apply_scale_options="FBX_SCALE_NONE",
        mesh_smooth_type="FACE",
        use_armature_deform_only=False,
        add_leaf_bones=False,
        primary_bone_axis="Y",
        secondary_bone_axis="X",
        armature_nodetype="NULL",
        bake_anim=False,
        path_mode="COPY",
        embed_textures=True,
    )
    return path


# --- Vista previa -----------------------------------------------------------------------

POSE = {
    # (hueso, eje local, grados): rodilla izquierda doblada, paso adelante, codo
    # derecho doblado, torso inclinado y cabeza girada.
    "LeftThigh": ("X", 55), "LeftShin": ("X", -95), "LeftFoot": ("X", 25),
    "RightThigh": ("X", -15), "RightShin": ("X", -20),
    "RightUpperArm": ("X", 35), "RightForearm": ("X", 85), "RightFingers1": ("X", 30),
    "LeftUpperArm": ("X", -20), "LeftForearm": ("X", 30),
    "Spine2": ("X", 12), "Chest": ("Y", 15), "Head": ("Y", 30), "Jaw": ("X", -25),
}


def render(path, objects, xray=False):
    scene = bpy.context.scene
    shading = scene.display.shading
    shading.show_xray = xray
    shading.xray_alpha = 0.35
    for obj in objects:
        obj.hide_render = False
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def bone_sticks(arm):
    """Huesos posados como varillas naranjas (para verlos a través de la piel)."""
    import bmesh
    bm = bmesh.new()
    for pb in arm.pose.bones:
        if pb.name == "Root":
            continue
        head = arm.matrix_world @ pb.head
        tail = arm.matrix_world @ pb.tail
        axis = tail - head
        if axis.length < 1e-4:
            continue
        rot = axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
        mat = Matrix.Translation((head + tail) / 2) @ rot @ Matrix.Diagonal((0.045, 0.045, axis.length / 2, 1))
        bmesh.ops.create_cube(bm, size=2, matrix=mat)
        bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=0.08, matrix=Matrix.Translation(head))
    mesh = bpy.data.meshes.new("Sticks")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Sticks", mesh)
    obj.color = (1.0, 0.45, 0.05, 1)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def render_preview(kind, mesh_obj, arm):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "TEXTURE"
    shading.show_cavity = True
    shading.show_shadows = False
    scene.render.resolution_x = 640
    scene.render.resolution_y = 760
    scene.render.film_transparent = False
    world = bpy.data.worlds.get("Dark") or bpy.data.worlds.new("Dark")
    world.color = (0.035, 0.035, 0.045)
    scene.world = world

    lo, hi = prep.bounds(mesh_obj.matrix_world @ Vector(c) for c in mesh_obj.bound_box)
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    center = (lo + hi) / 2
    distance = (hi - lo).length / 2 * 3.0
    # Desde adelante y a la izquierda de la criatura: se ven las rodillas de perfil.
    camera.location = center + Vector((0.9, -0.75, 0.2)).normalized() * distance
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 50

    folder = tempfile.mkdtemp(prefix="nocturna_rig_")
    shots = []
    rest = os.path.join(folder, "rest.png")
    render(rest, [mesh_obj])
    shots.append(rest)

    for name, (axis, degrees) in POSE.items():
        pb = arm.pose.bones.get(name)
        if pb:
            pb.rotation_mode = "XYZ"
            angles = [0.0, 0.0, 0.0]
            angles["XYZ".index(axis)] = math.radians(degrees)
            pb.rotation_euler = angles
    bpy.context.view_layer.update()
    posed = os.path.join(folder, "posed.png")
    render(posed, [mesh_obj])
    shots.append(posed)

    sticks = bone_sticks(arm)
    shading.color_type = "OBJECT"
    mesh_obj.color = (0.75, 0.75, 0.78, 1)
    xray = os.path.join(folder, "xray.png")
    render(xray, [mesh_obj, sticks], xray=True)
    shots.append(xray)
    bpy.data.objects.remove(sticks)
    shading.show_xray = False
    shading.color_type = "TEXTURE"

    # Vuelve a la pose de descanso antes de exportar.
    for pb in arm.pose.bones:
        pb.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()

    images = [bpy.data.images.load(p) for p in shots]
    arrays = []
    for image in images:
        w, h = image.size
        pixels = numpy.empty(w * h * 4, dtype=numpy.float32)
        image.pixels.foreach_get(pixels)
        arrays.append(pixels.reshape(h, w, 4))
    joined = numpy.concatenate(arrays, axis=1)
    h, w = joined.shape[0], joined.shape[1]
    out = bpy.data.images.new(f"{kind}_rig", w, h)
    out.pixels.foreach_set(joined.ravel())
    out.filepath_raw = os.path.join(PREVIEWS, f"{kind}_rig.png")
    out.file_format = "PNG"
    out.save()
    for image in images:
        bpy.data.images.remove(image)
    return out.filepath_raw


# --- Salida -----------------------------------------------------------------------------


def write_json(kind, bones, tris, height, feet, path):
    data = {
        "Creature": kind,
        "Triangles": tris,
        "Height": height,
        "Feet": feet,
        "Space": "studs de Roblox relativos a HumanoidRootPart; frente -Z, arriba +Y",
        "Bones": [
            {
                "Name": b.name,
                "Parent": b.parent,
                "Head": [round(c, 4) for c in b.head],
                "Tail": [round(c, 4) for c in b.tail],
                "Length": round((b.tail - b.head).length, 4),
            }
            for b in bones
        ],
    }
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def write_config(results):
    lines = [
        "-- Generado por assets/blender/rig_creatures.py: no editar a mano.",
        "-- Esqueletos de las criaturas (assets/models/rigged). Height: alto total de la",
        "-- malla en studs; Feet: altura de los pies respecto de la raíz; Span: distancia",
        "-- del hueso Root al Head (MonsterFactory corrige la escala del importado con",
        "-- ella); HeadSize: largo del hueso Head; Bones: huesos que trae el FBX.",
        "return {",
    ]
    for kind in sorted(results):
        info = results[kind]
        names = ", ".join(f'"{n}"' for n in info["Bones"])
        lines.append(f"    {kind} = {{Height = {info['Height']:.4f}, Feet = {info['Feet']:.4f}, Span = {info['Span']:.4f}, "
                     f"HeadSize = {info['HeadSize']:.4f}, Triangles = {info['Triangles']},")
        lines.append(f"        Bones = {{{names}}}}},")
    lines.append("}")
    with open(CONFIG, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


def load_existing_config():
    """Conserva las criaturas que no se rehacen en esta corrida."""
    results = {}
    for kind in prep.creatures.CREATURES:
        path = os.path.join(RIGGED, f"{kind}.json")
        if os.path.exists(path):
            with open(path, encoding="utf-8") as handle:
                data = json.load(handle)
            heads = {b["Name"]: Vector(b["Head"]) for b in data["Bones"]}
            lengths = {b["Name"]: b["Length"] for b in data["Bones"]}
            results[kind] = {"Height": data["Height"], "Feet": data["Feet"], "Triangles": data["Triangles"],
                             "Span": (heads["Head"] - heads["Root"]).length, "HeadSize": lengths["Head"],
                             "Bones": [b["Name"] for b in data["Bones"]]}
    return results


def weld(obj):
    """El glTF trae los vértices partidos en cada costura de UV: se sueldan (las UV
    son por esquina y se conservan) para que la piel no se abra al doblar."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0004)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return before, len(obj.data.vertices)


def neighbors_of(mesh):
    links = [[] for _ in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        links[a].append(b)
        links[b].append(a)
    return links


def smooth_weights(final, links, allowed_of, rounds=1, keep=0.5):
    """Suaviza los pesos con los vecinos (sin pasar a huesos no permitidos)."""
    for _ in range(rounds):
        result = []
        for index, weights in enumerate(final):
            near = links[index]
            if not near:
                result.append(weights)
                continue
            mixed = {name: w * keep for name, w in weights.items()}
            share = (1 - keep) / len(near)
            for other in near:
                for name, w in final[other].items():
                    mixed[name] = mixed.get(name, 0) + w * share
            allowed = allowed_of[index]
            mixed = {name: w for name, w in mixed.items() if name in allowed and w > 0}
            total = sum(mixed.values())
            result.append({name: w / total for name, w in mixed.items()} if total > 0 else weights)
        final = result
    return final


def rig(kind, source):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    boxes = prep.boxes_for(kind)
    obj = prep.import_source(source)
    original = prep.triangles(obj.data)
    reduced_to = MAX_TRIS
    tris = original
    if original > MAX_TRIS:
        decimate = obj.modifiers.new("Decimate", "DECIMATE")
        decimate.ratio = reduced_to / original * 0.97
        depsgraph = bpy.context.evaluated_depsgraph_get()
        reduced = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
        old = obj.data
        obj.modifiers.clear()
        obj.data = reduced
        bpy.data.meshes.remove(old)
        tris = prep.triangles(obj.data)
    prep.to_roblox_space(obj, kind, boxes)
    weld(obj)
    obj.name = f"{kind}Body"
    obj.data.name = f"{kind}Body"

    labels, changed = classify(obj.data, boxes)
    log(kind, f"regiones por superficie: {changed} vértices cambiaron de caja")
    coords = numpy.array([tuple(v.co) for v in obj.data.vertices], dtype=numpy.float64)
    label_array = numpy.array(labels)
    regions = {name: coords[label_array == name] for name in set(labels)}
    counts = ", ".join(f"{k}:{len(v)}" for k, v in sorted(regions.items()))
    log(kind, f"{original} -> {tris} triángulos; vértices por región {counts}")
    for needed in ("Torso", "Head", "ArmLeft", "ArmRight", "LegLeft", "LegRight"):
        if needed not in regions or len(regions[needed]) < 12:
            raise RuntimeError(f"{kind}: región {needed} casi vacía")

    bones, measures = build_skeleton(kind, regions)
    lo, hi = prep.bounds(v.co for v in obj.data.vertices)
    height, feet = hi.y - lo.y, lo.y

    # Las medidas están en ejes de Roblox; la malla y el esqueleto pasan a ejes de
    # Blender (como prepare_ai_models.py) y el FBX los vuelve a Y arriba.
    roblox_points = [v.co.copy() for v in obj.data.vertices]
    arm = make_armature(kind, bones)
    obj.data.transform(TO_BLENDER.to_4x4())
    fallback = skin(kind, obj, arm, bones, labels, measures, roblox_points)

    texture_dir = tempfile.mkdtemp(prefix=f"nocturna_{kind}_tex_")
    textures = scale_textures(kind, texture_dir)
    preview = render_preview(kind, obj, arm)
    path = export_fbx(kind, obj, arm)
    write_json(kind, bones, tris, height, feet, os.path.join(RIGGED, f"{kind}.json"))
    log(kind, f"{len(bones)} huesos, {tris} triángulos, {textures} texturas, alto {height:.2f}, pies {feet:.2f}")
    log(kind, f"FBX {path} | vista {preview} | respaldo por cercanía en {fallback} vértices")
    by_name = {b.name: b for b in bones}
    return {"Height": height, "Feet": feet, "Triangles": tris, "Bones": [b.name for b in bones],
            "Span": (by_name["Head"].head - by_name["Root"].head).length,
            "HeadSize": (by_name["Head"].tail - by_name["Head"].head).length}


def main():
    os.makedirs(RIGGED, exist_ok=True)
    os.makedirs(PREVIEWS, exist_ok=True)
    results = load_existing_config()
    for kind in prep.creatures.CREATURES:
        if ONLY and kind not in ONLY:
            continue
        source = os.path.join(SOURCES, f"{kind}.glb")
        if not os.path.exists(source):
            log(kind, f"sin modelo en {SOURCES}, se omite")
            continue
        results[kind] = rig(kind, source)
    write_config(results)
    log("Listo", f"{len(results)} criaturas. Medidas en {CONFIG}")


if __name__ == "__main__":
    main()
