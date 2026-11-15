"""Muebles, equipos y tejido orgánico de NOCTURNA, modelados en Blender.

Uso:
  blender -b --factory-startup -P assets/blender/build_props.py -- --out C:/tmp/ntp [Nombre ...]

Cada objeto se arma con piezas reales (biseladas, torneadas, barridas por una curva
o deformadas con ruido), no con cajas sueltas. Las piezas de un mismo material se
juntan en una sola malla ("<Objeto>__<Grupo>"): en Roblox cada grupo es una MeshPart,
así un dispensador son 7 piezas y no 40.

Se modela en ejes de Roblox (X derecha, Y arriba, el frente hacia -Z y la espalda
contra la pared hacia +Z), con las medidas de la caja de PropKit.Boxes, y se pasa a
Blender al final (Roblox Z = -Blender Y). El FBX sale con forward -Z / up Y.

Salidas en --out:
  NocturnaProps.fbx   todas las mallas, una al lado de la otra
  props.json          material, color, transparencia y extras de cada grupo
  previews/<Nombre>.png  render para revisar la forma
  NocturnaProps.blend
"""

import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector, noise

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = "C:/tmp/ntp"
ONLY = []
index = 0
while index < len(ARGS):
    if ARGS[index] == "--out":
        OUT = ARGS[index + 1]
        index += 2
    else:
        ONLY.append(ARGS[index])
        index += 1
os.makedirs(os.path.join(OUT, "previews"), exist_ok=True)

# Roblox (x, y, z) -> Blender (x, -z, y)
TO_BLENDER = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))

# Texturas propias ya subidas (TextureAssets / ASSETS.md del Organismo).
FLESH = "OrganismoFlesh"


def mat(material, color, transparency=0.0, reflectance=0.0, collide=False, **extra):
    spec = {"Material": material, "Color": list(color), "Transparency": transparency,
            "Reflectance": reflectance, "Collide": collide}
    spec.update(extra)
    return spec


def axis_matrix(axis):
    if axis == "y":
        return Matrix.Rotation(-math.pi / 2, 3, "X")
    if axis == "x":
        return Matrix.Rotation(math.pi / 2, 3, "Y")
    return Matrix.Identity(3)


def place(center, rot=(0, 0, 0), local=None):
    """Matriz 4x4 en ejes de Roblox: trasladar * rotar (* eje local)."""
    rotation = Euler(rot, "XYZ").to_matrix()
    if local is not None:
        rotation = rotation @ local
    out = rotation.to_4x4()
    out.translation = Vector(center)
    return out


class Group:
    """Una malla del objeto: acumula vértices y caras en ejes de Roblox."""

    def __init__(self, prop, name, spec, split=35, tile=4.0, solidify=0.0):
        self.prop = prop
        self.name = name
        self.spec = spec
        self.split = split
        self.tile = tile
        self.solidify = solidify
        self.verts = []
        self.faces = []

    # -- base ---------------------------------------------------------------
    def absorb(self, bm):
        bm.verts.index_update()
        base = len(self.verts)
        self.verts.extend(v.co.copy() for v in bm.verts)
        for face in bm.faces:
            self.faces.append([base + v.index for v in face.verts])
        bm.free()

    def raw(self, verts, faces):
        base = len(self.verts)
        self.verts.extend(Vector(v) for v in verts)
        for face in faces:
            self.faces.append([base + i for i in face])

    # -- primitivas ----------------------------------------------------------
    def box(self, size, center, rot=(0, 0, 0), bevel=0.0, seg=2):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if bevel > 0:
            bevel = min(bevel, min(size) * 0.45)
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=seg, profile=0.5,
                            affect="EDGES", clamp_overlap=True)
        bmesh.ops.transform(bm, matrix=place(center, rot), verts=bm.verts)
        self.absorb(bm)

    def cyl(self, radius, length, center, axis="y", rot=(0, 0, 0), segs=16, radius2=None, bevel=0.0):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=radius,
                              radius2=radius if radius2 is None else radius2, depth=length)
        if bevel > 0:
            rim = [e for e in bm.edges if len(e.link_faces) == 2 and abs(e.link_faces[0].normal.dot(e.link_faces[1].normal)) < 0.5]
            bmesh.ops.bevel(bm, geom=rim, offset=bevel, segments=2, profile=0.5, affect="EDGES", clamp_overlap=True)
        bmesh.ops.transform(bm, matrix=place(center, rot, axis_matrix(axis)), verts=bm.verts)
        self.absorb(bm)

    def lathe(self, profile, center=(0, 0, 0), rot=(0, 0, 0), segs=24):
        """Superficie de revolución alrededor del eje Y local. profile: [(radio, y)]."""
        verts, faces, rings = [], [], []
        for r, y in profile:
            if r <= 1e-4:
                rings.append([len(verts)])
                verts.append((0.0, y, 0.0))
            else:
                ring = []
                for k in range(segs):
                    a = 2 * math.pi * k / segs
                    ring.append(len(verts))
                    verts.append((r * math.cos(a), y, r * math.sin(a)))
                rings.append(ring)
        for a, b in zip(rings, rings[1:]):
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                for k in range(segs):
                    faces.append([a[0], b[(k + 1) % segs], b[k]])
            elif len(b) == 1:
                for k in range(segs):
                    faces.append([a[k], a[(k + 1) % segs], b[0]])
            else:
                for k in range(segs):
                    faces.append([a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]])
        m = place(center, rot)
        self.raw([m @ Vector(v) for v in verts], faces)

    def torus(self, big, small, center, axis="y", rot=(0, 0, 0), segs=24, ring=8, arc=2 * math.pi):
        verts, faces = [], []
        closed = arc >= 2 * math.pi - 1e-6
        count = segs if closed else segs + 1
        for i in range(count):
            a = arc * i / segs
            for j in range(ring):
                b = 2 * math.pi * j / ring
                r = big + small * math.cos(b)
                verts.append((r * math.cos(a), r * math.sin(a), small * math.sin(b)))
        for i in range(segs if closed else segs):
            i2 = (i + 1) % count
            for j in range(ring):
                j2 = (j + 1) % ring
                faces.append([i * ring + j, i2 * ring + j, i2 * ring + j2, i * ring + j2])
        m = place(center, rot, axis_matrix(axis))
        self.raw([m @ Vector(v) for v in verts], faces)

    def sphere(self, radii, center, rot=(0, 0, 0), segs=16, rings=10):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
        for v in bm.verts:
            v.co = Vector((v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2]))
        bmesh.ops.transform(bm, matrix=place(center, rot), verts=bm.verts)
        self.absorb(bm)

    def cushion(self, size, center, rot=(0, 0, 0), round_=0.35, sag=0.0, seed=0, segs=20, rings=14):
        """Almohadón: una esfera llevada a caja con bordes redondos (superelipsoide)."""
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
        e = round_
        for v in bm.verts:
            c = v.co
            p = Vector(tuple(math.copysign(abs(x) ** e, x) for x in c))
            p = Vector((p.x * size[0] / 2, p.y * size[1] / 2, p.z * size[2] / 2))
            if sag:
                w = noise.noise(Vector((p.x * 1.3 + seed, p.y * 1.3, p.z * 1.3)))
                p.z += 0  # (Blender-agnóstico: la deformación va en Y de Roblox abajo)
                p.y += w * sag
            v.co = p
        bmesh.ops.transform(bm, matrix=place(center, rot), verts=bm.verts)
        self.absorb(bm)

    def blob(self, center, radii, seed=0, amp=0.1, freq=2.0, subdiv=3, rot=(0, 0, 0), octaves=2):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
        offset = Vector((seed * 7.13, seed * 3.71, seed * 5.29))
        for v in bm.verts:
            n = v.co.normalized()
            d = 0.0
            f = freq
            a = 1.0
            for _ in range(octaves):
                d += noise.noise(n * f + offset) * a
                f *= 2.1
                a *= 0.45
            v.co = Vector((n.x * radii[0], n.y * radii[1], n.z * radii[2])) + n * (d * amp)
        bmesh.ops.transform(bm, matrix=place(center, rot), verts=bm.verts)
        self.absorb(bm)

    def tube(self, points, radius, segs=8, caps=True, smooth=0, wobble=0.0, seed=0):
        """Tubo que sigue una polilínea. radius: número o función de t (0..1)."""
        pts = [Vector(p) for p in points]
        for _ in range(smooth):
            if len(pts) < 3:
                break
            out = [pts[0]]
            for a, b in zip(pts, pts[1:]):
                out.append(a.lerp(b, 0.25))
                out.append(a.lerp(b, 0.75))
            out.append(pts[-1])
            pts = out
        if len(pts) < 2:
            return
        lengths = [0.0]
        for a, b in zip(pts, pts[1:]):
            lengths.append(lengths[-1] + (b - a).length)
        total = lengths[-1] or 1.0
        tangents = []
        for i in range(len(pts)):
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, len(pts) - 1)]
            tangents.append((b - a).normalized())
        ref = Vector((0, 1, 0)) if abs(tangents[0].y) < 0.9 else Vector((1, 0, 0))
        normal = tangents[0].cross(ref).normalized()
        verts, faces = [], []
        for i, p in enumerate(pts):
            t = tangents[i]
            normal = (normal - t * normal.dot(t)).normalized()
            binormal = t.cross(normal)
            r = radius(lengths[i] / total) if callable(radius) else radius
            if wobble:
                r *= 1 + wobble * noise.noise(p * 1.7 + Vector((seed, seed * 0.5, 0)))
            for k in range(segs):
                a = 2 * math.pi * k / segs
                verts.append(p + (normal * math.cos(a) + binormal * math.sin(a)) * r)
        for i in range(len(pts) - 1):
            for k in range(segs):
                k2 = (k + 1) % segs
                faces.append([i * segs + k, i * segs + k2, (i + 1) * segs + k2, (i + 1) * segs + k])
        if caps:
            faces.append(list(reversed(range(segs))))
            last = (len(pts) - 1) * segs
            faces.append([last + k for k in range(segs)])
        self.raw(verts, faces)

    def cloth(self, xmin, xmax, zmin, zmax, top, drop=0.4, edge=1.5, seed=0, wrinkle=0.04, nx=26, nz=30, rot_y=0.0):
        """Sábana o tela apoyada en `top` que cae por los costados (|x| > edge)."""
        verts, faces = [], []
        for i in range(nx + 1):
            u = xmin + (xmax - xmin) * i / nx
            for j in range(nz + 1):
                z = zmin + (zmax - zmin) * j / nz
                x, y = u, top
                over = abs(u) - edge
                if over > 0:
                    x = math.copysign(edge + 0.06 + over * 0.12, u)
                    y = top - over * (drop / max(abs(xmax) - edge, 0.01)) * 1.0
                w = noise.noise(Vector((u * 1.6 + seed, z * 0.9, seed * 0.3)))
                y += w * wrinkle
                x += noise.noise(Vector((z * 2.0, u, seed))) * wrinkle * 0.5
                c, s = math.cos(rot_y), math.sin(rot_y)
                verts.append((x * c + z * s, y, -x * s + z * c))
        for i in range(nx):
            for j in range(nz):
                a = i * (nz + 1) + j
                faces.append([a, a + 1, a + nz + 2, a + nz + 1])
        self.raw(verts, faces)


class Prop:
    def __init__(self, name):
        self.name = name
        self.groups = []

    def group(self, name, spec, **options):
        g = Group(self, name, spec, **options)
        self.groups.append(g)
        return g


PROPS = {}


def prop(name):
    def register(fn):
        PROPS[name] = fn
        return fn
    return register


# ---------------------------------------------------------------------------
# Hospital y oficinas
# ---------------------------------------------------------------------------

@prop("WaterCooler")
def water_cooler(P):
    body = P.group("Body", mat("Plastic", (204, 202, 192), collide=True))
    dark = P.group("Dark", mat("Plastic", (46, 48, 50)))
    metal = P.group("Metal", mat("Metal", (118, 120, 118)))
    hot = P.group("TapHot", mat("Plastic", (168, 38, 34)))
    cold = P.group("TapCold", mat("Plastic", (38, 84, 160)))
    bottle = P.group("Bottle", mat("Glass", (162, 198, 216), transparency=0.55, reflectance=0.08), split=None)
    # Opaca: dos capas transparentes una dentro de otra parpadean en Roblox.
    water = P.group("Water", mat("SmoothPlastic", (58, 116, 168), reflectance=0.18), split=None)

    body.box((1.22, 2.86, 1.18), (0, 1.53, 0.02), bevel=0.07, seg=3)
    body.box((1.28, 0.1, 1.24), (0, 0.05, 0.02), bevel=0.02)
    body.box((1.28, 0.08, 1.24), (0, 2.99, 0.02), bevel=0.03)
    # Hueco de los grifos: fondo oscuro con un marco que sobresale.
    dark.box((0.86, 0.95, 0.03), (0, 1.76, -0.585))
    for y in (2.26, 1.26):
        body.box((1.0, 0.07, 0.07), (0, y, -0.595), bevel=0.02)
    for x in (-0.465, 0.465):
        body.box((0.07, 1.0, 0.07), (x, 1.76, -0.595), bevel=0.02)
    # Bandeja de goteo con rejilla.
    dark.box((0.8, 0.12, 0.36), (0, 1.27, -0.71), bevel=0.03)
    metal.box((0.76, 0.03, 0.32), (0, 1.34, -0.71), bevel=0.01)
    for i in range(7):
        metal.box((0.03, 0.03, 0.3), (-0.33 + i * 0.11, 1.37, -0.71))
    # Canillas: cuerpo, paleta y pico.
    for g, x in ((hot, -0.2), (cold, 0.2)):
        g.cyl(0.075, 0.2, (x, 2.06, -0.68), axis="z", segs=14, bevel=0.015)
        g.box((0.13, 0.2, 0.06), (x, 2.17, -0.77), rot=(0.3, 0, 0), bevel=0.025)
        g.cyl(0.04, 0.13, (x, 1.97, -0.74), axis="y", segs=10)
    # Rejillas de ventilación a los costados y placa de la marca.
    for i in range(6):
        for s in (-1, 1):
            dark.box((0.03, 0.045, 0.7), (s * 0.615, 0.5 + i * 0.1, 0.0))
    dark.box((0.5, 0.12, 0.03), (0, 0.66, -0.6), bevel=0.01)
    # Serpentina del condensador atrás.
    points = []
    for i in range(9):
        y = 0.45 + i * 0.22
        xs = (-0.42, 0.42) if i % 2 == 0 else (0.42, -0.42)
        points += [(xs[0], y, 0.66), (xs[1], y, 0.66)]
    metal.tube(points, 0.025, segs=6)
    # Asiento del bidón, bidón con estrías y el agua adentro.
    dark.lathe([(0, 3.03), (0.46, 3.03), (0.46, 3.1), (0.22, 3.15), (0, 3.15)], segs=28)
    bottle.lathe([(0, 3.0), (0.16, 3.0), (0.16, 3.2), (0.26, 3.26), (0.52, 3.36), (0.6, 3.46), (0.6, 3.62),
                  (0.625, 3.66), (0.6, 3.7), (0.6, 3.9), (0.625, 3.94), (0.6, 3.98), (0.6, 4.16),
                  (0.56, 4.28), (0.4, 4.37), (0, 4.4)], segs=32)
    water.lathe([(0, 3.02), (0.14, 3.02), (0.14, 3.2), (0.24, 3.27), (0.5, 3.37), (0.575, 3.47),
                 (0.575, 3.82), (0, 3.82)], segs=32)


@prop("HospitalBed")
def hospital_bed(P):
    frame = P.group("Frame", mat("Metal", (176, 180, 182), collide=True))
    wheels = P.group("Wheels", mat("Rubber", (30, 30, 32)))
    panels = P.group("Panels", mat("Plastic", (186, 182, 170)))
    bedding = P.group("Mattress", mat("Fabric", (176, 186, 188), collide=True), split=None)
    sheet = P.group("Sheet", mat("Fabric", (148, 156, 146)), split=None, solidify=0.03)
    iv = P.group("IVBag", mat("Glass", (222, 214, 168), transparency=0.35), split=None)

    r = 0.07
    frame.tube([(-1.55, 1.45, -3.3), (1.55, 1.45, -3.3), (1.55, 1.45, 3.3), (-1.55, 1.45, 3.3), (-1.55, 1.45, -3.3)], r)
    z = -3.0
    while z <= 3.01:
        frame.box((3.0, 0.04, 0.12), (0, 1.5, z))
        z += 0.5
    for x in (-1.45, 1.45):
        for z in (-3.1, 3.1):
            frame.cyl(0.07, 1.05, (x, 0.92, z), axis="y", segs=10)
            frame.box((0.1, 0.16, 0.3), (x, 0.34, z + 0.04), bevel=0.02)
            wheels.cyl(0.17, 0.12, (x, 0.18, z + 0.1), axis="x", segs=16, bevel=0.03)
    for z in (-3.1, 3.1):
        frame.tube([(-1.45, 0.7, z), (1.45, 0.7, z)], 0.05, segs=6)
    frame.tube([(0, 0.75, -3.1), (0, 0.75, 3.1)], 0.06, segs=6)
    # Cabecera y pie: caño curvado con panel de plástico.
    for x in (-1.6, 1.6):
        frame.cyl(0.08, 2.4, (x, 2.1, 3.45), axis="y", segs=10)
        frame.cyl(0.08, 1.6, (x, 1.7, -3.45), axis="y", segs=10)
    frame.tube([(-1.6, 3.3, 3.45), (-1.45, 3.45, 3.45), (1.45, 3.45, 3.45), (1.6, 3.3, 3.45)], 0.08, smooth=2)
    frame.tube([(-1.6, 2.5, -3.45), (-1.45, 2.58, -3.45), (1.45, 2.58, -3.45), (1.6, 2.5, -3.45)], 0.08, smooth=2)
    panels.box((3.05, 1.3, 0.1), (0, 2.55, 3.45), bevel=0.05, seg=3)
    panels.box((3.05, 0.75, 0.1), (0, 2.05, -3.45), bevel=0.05, seg=3)
    frame.box((0.55, 0.65, 0.04), (0.85, 2.1, -3.53), bevel=0.01)  # porta historia clínica
    frame.tube([(0.6, 1.25, -3.4), (0.6, 1.25, -3.62), (0.78, 1.1, -3.62)], 0.04, segs=6)  # manivela
    # Barandas: la derecha levantada, la izquierda bajada.
    for y in (2.45, 2.8):
        frame.tube([(1.72, y, -0.9), (1.72, y, 2.4)], 0.045, segs=6)
    for z in (-0.6, 0.8, 2.1):
        frame.cyl(0.035, 0.55, (1.72, 2.62, z), axis="y", segs=8)
    for z in (-0.6, 2.1):
        frame.tube([(1.72, 2.4, z), (1.66, 1.9, z), (1.55, 1.48, z)], 0.04, segs=6)
    for y in (1.62, 1.88):
        frame.tube([(-1.72, y, -0.9), (-1.72, y, 2.4)], 0.045, segs=6)
    # Colchón, almohada y sábana arrugada que cae por los costados.
    bedding.cushion((3.1, 0.5, 6.6), (0, 1.82, 0), round_=0.2, sag=0.02, seed=1)
    bedding.blob((0, 2.25, 2.75), (1.05, 0.2, 0.48), seed=3, amp=0.04, freq=2.5, subdiv=3)
    sheet.cloth(-1.95, 1.95, -3.2, 1.7, 2.2, drop=0.45, edge=1.5, seed=2, wrinkle=0.05, rot_y=0.04)
    # Soporte de suero con la bolsa y la guía.
    frame.cyl(0.04, 4.6, (1.58, 3.75, 3.3), axis="y", segs=8)
    frame.tube([(1.58, 6.0, 3.3), (1.32, 6.05, 3.3), (1.28, 5.93, 3.3)], 0.025, segs=6)
    frame.tube([(1.58, 6.0, 3.3), (1.84, 6.05, 3.3), (1.88, 5.93, 3.3)], 0.025, segs=6)
    iv.blob((1.28, 5.5, 3.3), (0.28, 0.42, 0.08), seed=5, amp=0.02, subdiv=3)
    iv.tube([(1.28, 5.05, 3.3), (1.24, 4.5, 3.2), (1.1, 3.2, 2.6), (0.6, 2.35, 2.2)], 0.015, segs=5, smooth=2)


@prop("Desk")
def desk(P):
    wood = P.group("Wood", mat("Wood", (118, 88, 62), collide=True))
    metal = P.group("Metal", mat("Metal", (58, 58, 60)))
    beige = P.group("Monitor", mat("Plastic", (186, 178, 156)))
    screen = P.group("Screen", mat("Glass", (28, 50, 40), reflectance=0.2))
    paper = P.group("Papers", mat("Cardboard", (206, 196, 168)))
    fabric = P.group("Chair", mat("Fabric", (52, 50, 54)), split=None)
    rng = random.Random(4)

    wood.box((5.3, 0.16, 2.6), (0, 2.84, 1.0), bevel=0.03)
    wood.box((1.5, 2.72, 2.45), (-1.8, 1.38, 1.05), bevel=0.02)
    for y in (0.55, 1.4, 2.25):
        wood.box((1.38, 0.78, 0.06), (-1.8, y, -0.2), bevel=0.015)
        metal.box((0.5, 0.06, 0.08), (-1.8, y + 0.22, -0.26), bevel=0.01)
    wood.box((0.12, 2.72, 2.45), (2.55, 1.38, 1.05), bevel=0.01)
    wood.box((3.9, 1.5, 0.06), (0.55, 2.0, 2.2))
    # Monitor de tubo con su joroba, base y pantalla de vidrio.
    beige.box((1.5, 1.25, 1.15), (-1.2, 3.62, 1.55), bevel=0.1, seg=3)
    beige.box((1.2, 0.95, 0.6), (-1.2, 3.6, 2.25), bevel=0.15, seg=3)
    beige.cyl(0.38, 0.06, (-1.2, 2.95, 1.6), axis="y", segs=20)
    beige.box((0.3, 0.12, 0.3), (-1.2, 3.0, 1.6))
    screen.box((1.15, 0.9, 0.05), (-1.2, 3.65, 0.955), bevel=0.06, seg=3)
    beige.box((1.6, 0.08, 0.55), (-0.2, 2.96, 0.42), bevel=0.02)
    metal.box((1.45, 0.03, 0.4), (-0.2, 3.01, 0.42))
    # Lámpara de brazo.
    metal.cyl(0.22, 0.06, (2.0, 2.95, 1.75), axis="y", segs=18)
    metal.tube([(2.0, 2.95, 1.75), (2.0, 3.8, 1.9), (1.75, 4.2, 1.35)], 0.035, segs=6)
    metal.lathe([(0.06, 0), (0.12, -0.05), (0.3, -0.35), (0.27, -0.36), (0, -0.2)], center=(1.72, 4.25, 1.3), rot=(-0.5, 0, 0), segs=18)
    # Papeles sueltos, una pila de carpetas y una taza.
    for k in range(4):
        paper.box((0.85, 0.05, 1.1), (0.7 + rng.uniform(-0.2, 0.3), 2.93 + k * 0.03, 0.8 + rng.uniform(-0.2, 0.2)),
                  rot=(0, rng.uniform(-0.6, 0.6), 0))
    paper.box((0.95, 0.16, 1.25), (1.65, 3.0, 1.55), rot=(0, 0.15, 0), bevel=0.01)
    beige.lathe([(0, 2.92), (0.16, 2.92), (0.17, 3.2), (0.15, 3.2), (0.14, 2.95), (0, 2.95)], center=(0.6, 0, 1.75), segs=16)
    # Silla de oficina: estrella de cinco patas, columna, asiento y respaldo.
    cx, cz = 0.3, -1.3
    for k in range(5):
        a = 2 * math.pi * k / 5
        metal.box((0.12, 0.08, 0.9), (cx + math.sin(a) * 0.45, 0.25, cz + math.cos(a) * 0.45), rot=(0, a, 0), bevel=0.02)
        metal.cyl(0.08, 0.07, (cx + math.sin(a) * 0.88, 0.1, cz + math.cos(a) * 0.88), axis="x", segs=10)
    metal.cyl(0.07, 1.0, (cx, 0.75, cz), axis="y", segs=10)
    metal.box((1.0, 0.06, 0.9), (cx, 1.22, cz))
    fabric.cushion((1.75, 0.32, 1.65), (cx, 1.4, cz), round_=0.3)
    fabric.cushion((1.6, 1.85, 0.3), (cx, 2.55, cz + 0.85), rot=(-0.12, 0, 0), round_=0.3)
    metal.tube([(cx, 1.3, cz + 0.6), (cx, 1.4, cz + 0.9), (cx, 1.8, cz + 0.95)], 0.06, segs=6)
    for s in (-1, 1):
        metal.tube([(cx + s * 0.85, 1.5, cz - 0.3), (cx + s * 0.85, 2.05, cz - 0.2), (cx + s * 0.85, 2.05, cz + 0.5)], 0.04, segs=6)
        fabric.cushion((0.18, 0.1, 0.7), (cx + s * 0.85, 2.1, cz + 0.15), round_=0.4)


@prop("FilingCabinet")
def filing_cabinet(P):
    body = P.group("Body", mat("Metal", (150, 156, 148), collide=True))
    handles = P.group("Handles", mat("Metal", (70, 70, 72)))
    paper = P.group("Papers", mat("Cardboard", (200, 178, 128)))
    rng = random.Random(9)
    body.box((1.8, 4.4, 2.0), (0, 2.2, 0.1), bevel=0.03)
    for index, y in enumerate((0.8, 2.2, 3.6)):
        out = 0.45 if index == 2 else 0.0
        body.box((1.68, 1.28, 0.07), (0, y, -0.935 - out), bevel=0.02)
        handles.tube([(-0.3, y + 0.3, -0.98 - out), (-0.3, y + 0.3, -1.06 - out), (0.3, y + 0.3, -1.06 - out), (0.3, y + 0.3, -0.98 - out)], 0.025, segs=6)
        for x in (-0.2, 0.2):
            handles.box((0.04, 0.2, 0.02), (x, y + 0.5, -0.98 - out))
        handles.box((0.44, 0.04, 0.02), (0, y + 0.6, -0.98 - out))
        handles.box((0.44, 0.04, 0.02), (0, y + 0.4, -0.98 - out))
        if out:
            # Cajón abierto: costados y carpetas colgantes que asoman.
            for x in (-0.78, 0.78):
                body.box((0.04, 1.0, 0.5), (x, y, -1.15))
            for k in range(9):
                tab = rng.uniform(0.0, 0.12)
                paper.box((1.4, 0.75 + tab, 0.02), (rng.uniform(-0.04, 0.04), y + 0.05 + tab / 2, -1.33 + k * 0.05), rot=(rng.uniform(-0.1, 0.1), 0, 0))
    paper.box((1.2, 0.25, 1.4), (0.05, 4.53, 0.1), rot=(0, 0.3, 0), bevel=0.01)
    paper.box((1.1, 0.12, 1.3), (-0.05, 4.71, 0.15), rot=(0, -0.2, 0), bevel=0.01)


@prop("Bookcase")
def bookcase(P):
    wood = P.group("Wood", mat("Wood", (96, 70, 50), collide=True))
    groups = [P.group("BooksRed", mat("Leather", (104, 40, 34))),
              P.group("BooksGreen", mat("Fabric", (50, 68, 58))),
              P.group("BooksTan", mat("Leather", (128, 100, 64)))]
    rng = random.Random(12)
    for s in (-1, 1):
        wood.box((0.18, 7.94, 1.8), (s * 2.91, 3.97, 0), bevel=0.02)
    wood.box((6.04, 0.16, 1.86), (0, 7.86, -0.01), bevel=0.03)
    wood.box((5.66, 0.4, 1.7), (0, 0.2, 0.0), bevel=0.02)
    wood.box((5.66, 7.6, 0.08), (0, 3.9, 0.86))
    levels = [0.4]
    for y in (2.0, 3.9, 5.8):
        wood.box((5.66, 0.12, 1.62), (0, y, 0.02), bevel=0.01)
        levels.append(y + 0.06)
    for base in levels:
        x = -2.72
        while x < 2.6:
            if rng.random() < 0.08:
                x += rng.uniform(0.3, 0.7)
                continue
            w = rng.uniform(0.12, 0.3)
            h = rng.uniform(1.1, 1.6)
            d = rng.uniform(1.05, 1.35)
            lean = 0.0
            if rng.random() < 0.07 and x + w + h * 0.4 < 2.7:
                lean = -0.35
            g = rng.choice(groups)
            if lean:
                g.box((w, h, d), (x + w / 2 + h * 0.18, base + h / 2 - 0.05, 0.1), rot=(0, 0, lean), bevel=0.015)
                x += w + h * 0.36
            else:
                g.box((w, h, d), (x + w / 2, base + h / 2, 0.15 - d / 2 + 0.5), bevel=0.015)
                x += w + 0.005
        if rng.random() < 0.6:
            g = rng.choice(groups)
            for k in range(3):
                g.box((1.2, 0.18, 1.05), (rng.uniform(-1.5, 1.5), base + 0.09 + k * 0.185, 0.1), rot=(0, rng.uniform(-0.2, 0.2), 0), bevel=0.015)


@prop("Sofa")
def sofa(P):
    fabric = P.group("Fabric", mat("Fabric", (96, 62, 54), collide=True), split=None)
    cushions = P.group("Cushions", mat("Fabric", (112, 74, 62)), split=None)
    legs = P.group("Legs", mat("Wood", (52, 38, 28)))
    fabric.cushion((6.9, 0.85, 2.9), (0, 0.72, 0), round_=0.25)
    fabric.cushion((6.9, 2.0, 0.62), (0, 2.1, 1.15), rot=(-0.06, 0, 0), round_=0.3)
    for s in (-1, 1):
        fabric.cushion((0.78, 1.15, 2.95), (s * 3.08, 1.45, 0), round_=0.35)
        fabric.cyl(0.42, 2.95, (s * 3.08, 2.05, 0), axis="z", segs=20)
    for i, x in enumerate((-2.0, 0.0, 2.0)):
        cushions.cushion((2.02, 0.45, 2.2), (x, 1.38, -0.25), round_=0.3, sag=0.05, seed=i)
        cushions.cushion((2.0, 1.5, 0.5), (x, 2.35, 0.68), rot=(-0.18, 0, 0), round_=0.3, sag=0.04, seed=i + 5)
    for x in (-3.2, 3.2):
        for z in (-1.25, 1.25):
            legs.cyl(0.1, 0.32, (x, 0.16, z), axis="y", radius2=0.07, segs=10)


@prop("Wheelchair")
def wheelchair(P):
    frame = P.group("Frame", mat("Metal", (150, 154, 156), collide=True))
    tires = P.group("Tires", mat("Rubber", (28, 28, 30)))
    seat = P.group("Seat", mat("Fabric", (34, 34, 36)), split=None)
    for s in (-1, 1):
        x = s * 1.1
        tires.torus(0.98, 0.065, (x, 1.05, 0.35), axis="x", segs=40, ring=8)
        frame.torus(0.86, 0.025, (x + s * 0.09, 1.05, 0.35), axis="x", segs=36, ring=6)
        frame.cyl(0.09, 0.2, (x, 1.05, 0.35), axis="x", segs=12)
        for k in range(14):
            a = 2 * math.pi * k / 14
            frame.tube([(x - s * 0.08, 1.05, 0.35), (x, 1.05 + math.sin(a) * 0.9, 0.35 + math.cos(a) * 0.9)], 0.01, segs=4, caps=False)
        # Rueditas de adelante con su horquilla.
        tires.cyl(0.22, 0.09, (s * 0.8, 0.22, -1.15), axis="x", segs=16, bevel=0.03)
        frame.tube([(s * 0.8, 0.22, -1.15), (s * 0.8, 0.55, -1.05), (s * 0.8, 0.7, -1.0)], 0.03, segs=6)
        # Bastidor lateral, manijas y apoyabrazos.
        frame.tube([(s * 0.85, 0.7, -1.0), (s * 0.85, 1.5, -0.95), (s * 0.85, 1.55, 0.6), (s * 0.85, 3.2, 0.85), (s * 0.85, 3.28, 1.15)], 0.045, segs=8, smooth=1)
        tires.cyl(0.06, 0.32, (s * 0.85, 3.28, 1.2), axis="z", segs=10)
        frame.tube([(s * 0.85, 1.55, -0.6), (s * 0.85, 2.3, -0.5), (s * 0.85, 2.3, 0.55), (s * 0.85, 2.0, 0.75)], 0.035, segs=6, smooth=1)
        seat.cushion((0.2, 0.12, 0.85), (s * 0.85, 2.36, 0.05), round_=0.4)
        frame.tube([(s * 0.6, 1.4, -1.0), (s * 0.6, 0.45, -1.35)], 0.035, segs=6)
        frame.box((0.55, 0.04, 0.38), (s * 0.55, 0.42, -1.45), rot=(-0.2, 0, 0), bevel=0.01)
    frame.tube([(-0.85, 1.5, -0.2), (0.85, 1.5, 0.3)], 0.03, segs=6)
    frame.tube([(-0.85, 1.5, 0.3), (0.85, 1.5, -0.2)], 0.03, segs=6)
    seat.cushion((1.72, 0.1, 1.5), (0, 1.56, -0.15), round_=0.4, sag=0.03)
    seat.cushion((1.72, 1.3, 0.08), (0, 2.38, 0.75), rot=(-0.12, 0, 0), round_=0.4, sag=0.03, seed=3)


@prop("TrashBin")
def trash_bin(P):
    bin_ = P.group("Bin", mat("Metal", (110, 114, 110), collide=True))
    bag = P.group("Bag", mat("Plastic", (26, 26, 28)), split=None)
    trash = P.group("Trash", mat("Cardboard", (196, 186, 160)), split=None)
    bin_.lathe([(0, 0), (0.55, 0), (0.58, 0.04), (0.62, 1.48), (0.66, 1.5), (0.66, 1.55), (0.6, 1.55), (0.57, 0.1), (0, 0.1)], segs=28)
    for y in (0.4, 0.9):
        bin_.torus(0.6 + y * 0.03, 0.02, (0, y, 0), axis="y", segs=28, ring=6)
    bin_.box((0.4, 0.06, 0.2), (0, 0.06, -0.62), rot=(0.25, 0, 0), bevel=0.02)
    bag.torus(0.64, 0.05, (0, 1.5, 0), axis="y", segs=28, ring=6)
    bag.blob((0, 1.47, 0), (0.6, 0.08, 0.6), seed=2, amp=0.03, subdiv=3)
    for k, (x, y, z, s) in enumerate([(0.15, 1.62, 0.1, 0.22), (-0.2, 1.68, -0.1, 0.2), (0.05, 1.78, -0.05, 0.17), (0.35, 0.12, -0.95, 0.16)]):
        trash.blob((x, y, z), (s, s * 0.85, s), seed=k + 4, amp=s * 0.35, freq=3.0, subdiv=2)


@prop("Extinguisher")
def extinguisher(P):
    body = P.group("Body", mat("Metal", (160, 28, 26), reflectance=0.05, collide=True), split=None)
    valve = P.group("Valve", mat("Metal", (170, 172, 170)))
    hose = P.group("Hose", mat("Rubber", (24, 24, 26)), split=None)
    label = P.group("Label", mat("Plastic", (226, 222, 206)))
    sign = P.group("Sign", mat("Plastic", (172, 34, 32)))
    z0 = 0.05
    body.lathe([(0, 0.3), (0.26, 0.3), (0.28, 0.34), (0.28, 1.65), (0.24, 1.8), (0.12, 1.88), (0, 1.9)], center=(0, 0, z0), segs=28)
    valve.cyl(0.07, 0.12, (0, 1.95, z0), axis="y", segs=12)
    valve.box((0.18, 0.14, 0.2), (0, 2.05, z0), bevel=0.03)
    valve.box((0.08, 0.04, 0.42), (0, 2.16, z0 - 0.08), rot=(0.25, 0, 0), bevel=0.015)
    valve.box((0.08, 0.04, 0.36), (0, 2.08, z0 - 0.06), rot=(0.05, 0, 0), bevel=0.015)
    valve.torus(0.05, 0.012, (0.11, 2.08, z0), axis="x", segs=12, ring=4)
    valve.cyl(0.07, 0.04, (0.0, 2.04, z0 - 0.12), axis="z", segs=14)
    label.cyl(0.055, 0.01, (0.0, 2.04, z0 - 0.145), axis="z", segs=14)
    label.box((0.32, 0.5, 0.03), (0, 1.05, z0 - 0.28), bevel=0.01)
    hose.tube([(0.1, 2.0, z0), (0.25, 1.95, z0 - 0.05), (0.32, 1.6, z0 - 0.15), (0.33, 0.95, z0 - 0.2), (0.3, 0.8, z0 - 0.2)], 0.035, segs=8, smooth=2)
    valve.cyl(0.05, 0.16, (0.3, 0.74, z0 - 0.2), axis="y", radius2=0.035, segs=10)
    valve.torus(0.3, 0.03, (0, 1.4, z0), axis="y", segs=24, ring=5, rot=(0, -0.6, 0), arc=4.4)
    valve.box((0.45, 0.85, 0.04), (0, 1.3, 0.36), bevel=0.01)
    sign.box((0.8, 0.6, 0.05), (0, 2.3, 0.37), bevel=0.02)
    label.box((0.5, 0.3, 0.02), (0, 2.3, 0.335))


@prop("Plant")
def plant(P):
    pot = P.group("Pot", mat("Slate", (128, 74, 54), collide=True), split=None)
    soil = P.group("Soil", mat("Ground", (52, 40, 30)), split=None)
    stems = P.group("Stems", mat("Wood", (72, 56, 38)), split=None)
    leaves = P.group("Leaves", mat("Fabric", (98, 88, 54)), split=None)
    rng = random.Random(21)
    pot.lathe([(0, 0), (0.42, 0), (0.6, 1.12), (0.68, 1.14), (0.68, 1.3), (0.6, 1.3), (0.56, 1.15), (0, 1.15)], segs=28)
    soil.blob((0, 1.16, 0), (0.56, 0.06, 0.56), seed=1, amp=0.02, subdiv=3)

    def branch(start, direction, length, radius, depth):
        points = [start]
        p = Vector(start)
        d = Vector(direction).normalized()
        for _ in range(4):
            d = (d + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.1, 0.15), rng.uniform(-0.3, 0.3)))).normalized()
            p = p + d * (length / 4)
            points.append(tuple(p))
        stems.tube(points, lambda t: radius * (1 - 0.7 * t), segs=6, smooth=1)
        if depth > 0:
            for _ in range(rng.randint(1, 2)):
                k = rng.randint(1, len(points) - 2)
                side = Vector((rng.uniform(-1, 1), rng.uniform(0.2, 0.8), rng.uniform(-1, 1)))
                branch(points[k], side, length * 0.55, radius * 0.6, depth - 1)
        tip = Vector(points[-1])
        for _ in range(rng.randint(1, 3)):
            droop = Vector((rng.uniform(-0.2, 0.2), -0.2, rng.uniform(-0.2, 0.2)))
            leaves.blob(tuple(tip + droop), (0.2, 0.03, 0.08), seed=rng.randint(0, 99), amp=0.02, subdiv=2,
                        rot=(rng.uniform(-0.6, 0.6), rng.uniform(0, 3.1), rng.uniform(-1.0, 1.0)))

    for k in range(4):
        a = k * 1.7
        branch((math.cos(a) * 0.1, 1.15, math.sin(a) * 0.1), (math.cos(a) * 0.25, 1, math.sin(a) * 0.25), rng.uniform(2.0, 2.7), 0.06, 2)
    for k in range(5):
        a = rng.uniform(0, 6.28)
        r = rng.uniform(0.1, 0.75)
        leaves.blob((math.cos(a) * r, 1.19 if r < 0.55 else 0.03, math.sin(a) * r), (0.2, 0.02, 0.08), seed=k + 40, amp=0.01,
                    subdiv=2, rot=(0, rng.uniform(0, 3), 0))


# ---------------------------------------------------------------------------
# Laboratorio tomado por el organismo
# ---------------------------------------------------------------------------

@prop("LabTable")
def lab_table(P):
    cab = P.group("Cabinet", mat("Metal", (184, 188, 186), collide=True))
    top = P.group("Top", mat("Slate", (28, 28, 30), collide=True))
    chrome = P.group("Chrome", mat("Metal", (196, 200, 200), reflectance=0.1))
    glass = P.group("Glassware", mat("Glass", (205, 222, 218), transparency=0.5), split=None)
    reagents = P.group("Reagents", mat("Glass", (150, 92, 40), transparency=0.2), split=None)
    liquids = P.group("Liquids", mat("SmoothPlastic", (96, 150, 58), reflectance=0.15), split=None)
    rng = random.Random(31)
    cab.box((7.0, 2.6, 2.7), (0, 1.55, 0.15), bevel=0.03)
    cab.box((6.86, 0.26, 2.5), (0, 0.13, 0.25))
    for i in range(4):
        x = -2.62 + i * 1.75
        cab.box((1.66, 2.3, 0.05), (x, 1.55, -1.215), bevel=0.02)
        chrome.tube([(x + 0.6, 2.25, -1.25), (x + 0.6, 2.25, -1.33), (x + 0.6, 1.75, -1.33), (x + 0.6, 1.75, -1.25)], 0.025, segs=6)
    top.box((7.2, 0.15, 3.0), (0, 2.93, 0), bevel=0.03)
    # Pileta: borde de acero, fondo oscuro, desagüe y canilla de cuello de ganso.
    for dx, dz, sx, sz in ((0, -0.5, 1.4, 0.08), (0, 0.5, 1.4, 0.08), (-0.66, 0, 0.08, 1.0), (0.66, 0, 0.08, 1.0)):
        chrome.box((sx, 0.06, sz), (2.2 + dx, 3.03, 0.05 + dz), bevel=0.02)
    chrome.box((1.26, 0.06, 0.92), (2.2, 3.02, 0.05))
    top.cyl(0.08, 0.04, (2.2, 3.05, 0.05), axis="y", segs=12)
    chrome.tube([(2.2, 3.0, 0.82), (2.2, 3.85, 0.8), (2.2, 3.98, 0.55), (2.2, 3.85, 0.3), (2.2, 3.7, 0.28)], 0.04, segs=8, smooth=2)
    for dx in (-0.3, 0.3):
        chrome.cyl(0.07, 0.12, (2.2 + dx, 3.06, 0.82), axis="y", segs=10)
        chrome.box((0.24, 0.04, 0.05), (2.2 + dx, 3.13, 0.82))
    # Microscopio.
    mx, mz = -2.4, 0.2
    chrome.box((0.6, 0.1, 0.8), (mx, 3.05, mz), bevel=0.03)
    chrome.tube([(mx, 3.1, mz + 0.3), (mx, 3.6, mz + 0.35), (mx, 3.95, mz + 0.1)], 0.07, segs=8, smooth=1)
    chrome.box((0.45, 0.04, 0.45), (mx, 3.4, mz - 0.05))
    chrome.cyl(0.07, 0.5, (mx, 3.95, mz - 0.05), axis="y", rot=(-0.45, 0, 0), segs=12)
    chrome.cyl(0.05, 0.25, (mx, 3.55, mz - 0.05), axis="y", segs=10)
    # Matraces, vasos, tubos de ensayo en gradilla y el líquido adentro.
    for k, (x, z) in enumerate(((-1.2, -0.3), (-0.5, 0.4), (0.4, -0.2))):
        h = rng.uniform(0.7, 1.0)
        glass.lathe([(0, 3.0), (0.32, 3.0), (0.34, 3.03), (0.12, 3.0 + h * 0.75), (0.09, 3.0 + h), (0.11, 3.03 + h), (0, 3.03 + h)], center=(x, 0, z), segs=20)
        liquids.lathe([(0, 3.02), (0.3, 3.02), (0.22, 3.02 + h * 0.3), (0, 3.02 + h * 0.3)], center=(x, 0, z), segs=20)
    glass.lathe([(0, 3.0), (0.22, 3.0), (0.23, 3.55), (0.25, 3.58), (0, 3.58)], center=(1.0, 0, 0.6), segs=18)
    chrome.box((0.9, 0.04, 0.3), (-0.4, 3.35, -0.75))
    chrome.box((0.9, 0.04, 0.3), (-0.4, 3.12, -0.75))
    for k in range(6):
        x = -0.75 + k * 0.14
        glass.cyl(0.05, 0.55, (x, 3.3, -0.75), axis="y", segs=10)
        liquids.cyl(0.04, rng.uniform(0.1, 0.3), (x, 3.12, -0.75), axis="y", segs=8)
    # Repisa de pared con frascos de reactivos.
    cab.box((7.0, 0.12, 1.0), (0, 5.35, 0.95), bevel=0.02)
    for x in (-3.0, 0, 3.0):
        chrome.box((0.08, 0.6, 0.08), (x, 5.05, 1.38))
        chrome.tube([(x, 4.85, 1.38), (x, 5.28, 0.6)], 0.03, segs=5)
    for k in range(7):
        x = -3.0 + k * 0.95 + rng.uniform(-0.15, 0.15)
        h = rng.uniform(0.6, 1.0)
        reagents.lathe([(0, 5.41), (0.22, 5.41), (0.23, 5.41 + h * 0.75), (0.1, 5.41 + h * 0.9), (0.1, 5.41 + h), (0, 5.41 + h)], center=(x, 0, 0.95), segs=16)
        cab.cyl(0.11, 0.1, (x, 5.46 + h, 0.95), axis="y", segs=12)


def tank(P, fluid_color, level, organism, seed):
    frame = P.group("Frame", mat("Metal", (112, 118, 122), collide=True))
    # Una sola capa transparente, teñida del color del líquido (dos capas una dentro
    # de otra parpadean, y el material Glass esconde las burbujas de adentro).
    glass = P.group("Glass", mat("SmoothPlastic", fluid_color, transparency=0.58, reflectance=0.2, collide=True,
                                 Light={"Color": fluid_color, "Brightness": 0.9, "Range": 11}, Bubbles=True), split=None)
    # La superficie del líquido: un disco opaco apenas ondulado a la altura del nivel.
    fluid = P.group("Surface", mat("SmoothPlastic", fluid_color, reflectance=0.25), split=None)
    specimen = P.group("Specimen", mat("Slate", (150, 96, 92), Surface=FLESH), split=None)
    lights = P.group("Lights", mat("Neon", (120, 255, 150)))
    rng = random.Random(seed)
    frame.cyl(1.68, 0.55, (0, 0.275, 0), axis="y", segs=8, bevel=0.04)
    frame.cyl(1.55, 0.25, (0, 0.67, 0), axis="y", segs=32, bevel=0.03)
    frame.torus(1.46, 0.09, (0, 0.86, 0), axis="y", segs=40, ring=8)
    frame.torus(1.46, 0.09, (0, 6.3, 0), axis="y", segs=40, ring=8)
    frame.cyl(1.6, 0.4, (0, 6.55, 0), axis="y", segs=32, bevel=0.04)
    frame.lathe([(1.45, 6.75), (1.2, 6.95), (0.6, 7.2), (0.3, 7.28), (0, 7.3)], segs=32)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        frame.box((0.14, 5.6, 0.14), (math.cos(a) * 1.55, 3.55, math.sin(a) * 1.55), rot=(0, -a, 0), bevel=0.02)
    for k in range(8):
        a = k * math.pi / 4 + 0.2
        frame.cyl(0.06, 0.08, (math.cos(a) * 1.35, 6.79, math.sin(a) * 1.35), axis="y", segs=8)
    frame.tube([(0, 7.25, 0), (0, 7.85, 0), (0.3, 8.2, 0.5), (0.3, 8.22, 1.7)], 0.16, segs=10, smooth=2)
    frame.tube([(-0.65, 7.0, 0.55), (-0.65, 7.9, 0.9), (-0.65, 7.95, 1.7)], 0.1, segs=8, smooth=2)
    frame.tube([(1.15, 6.8, 0.95), (1.3, 6.2, 1.2), (1.3, 1.5, 1.25), (1.2, 0.75, 1.15)], 0.08, segs=8, smooth=2)
    frame.box((0.9, 0.45, 0.12), (0, 0.4, -1.66), bevel=0.02)
    for k in range(3):
        lights.box((0.12, 0.08, 0.04), (-0.25 + k * 0.25, 0.48, -1.73), bevel=0.01)
    lights.torus(1.25, 0.035, (0, 0.92, 0), axis="y", segs=40, ring=5)
    glass.cyl(1.42, 5.5, (0, 3.6, 0), axis="y", segs=36)
    fluid.blob((0, level, 0), (1.36, 0.05, 1.36), seed=seed, amp=0.03, freq=2.0, subdiv=3)
    organism(specimen, rng, level)


def fetus(g, rng, level):
    # Algo con forma casi humana, encogido, flotando con el cordón hacia la tapa.
    g.blob((0, 3.4, 0.05), (0.55, 0.75, 0.45), seed=1, amp=0.07, freq=2.2, subdiv=4, rot=(0.35, 0, 0))
    g.blob((0, 4.35, -0.3), (0.5, 0.56, 0.5), seed=2, amp=0.06, freq=2.0, subdiv=4)
    for s in (-1, 1):
        g.tube([(s * 0.45, 3.85, -0.05), (s * 0.7, 3.4, -0.35), (s * 0.45, 3.05, -0.55), (s * 0.15, 3.3, -0.62)], lambda t: 0.16 - 0.08 * t, segs=8, smooth=2, wobble=0.2, seed=s)
        g.tube([(s * 0.3, 2.9, 0.1), (s * 0.45, 2.75, -0.45), (s * 0.35, 3.2, -0.75), (s * 0.25, 2.85, -0.85)], lambda t: 0.2 - 0.1 * t, segs=8, smooth=2, wobble=0.2, seed=s + 3)
    g.tube([(0, 3.2, -0.38), (0.2, 3.9, -0.6), (0.4, 5.2, -0.3), (0.15, 6.3, 0.1)], 0.06, segs=6, smooth=2, wobble=0.3, seed=8)
    for k in range(4):
        a = rng.uniform(0, 6.28)
        start = (math.cos(a) * 0.3, 3.0 + rng.uniform(0, 0.8), math.sin(a) * 0.3)
        end = (math.cos(a) * 1.1, start[1] + rng.uniform(-0.8, 0.8), math.sin(a) * 1.1)
        mid = ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2 + 0.3, (start[2] + end[2]) / 2)
        g.tube([start, mid, end], lambda t: 0.05 * (1 - t) + 0.01, segs=5, smooth=2, wobble=0.3, seed=k)


def tentacles(g, rng, level):
    # Masa con tentáculos y racimos de ojos, caída al fondo porque el tanque se vació.
    g.blob((0, 1.55, 0), (0.85, 0.6, 0.75), seed=11, amp=0.12, freq=2.5, subdiv=4)
    for k in range(8):
        a = k * 2 * math.pi / 8 + rng.uniform(-0.2, 0.2)
        points = [(math.cos(a) * 0.5, 1.6, math.sin(a) * 0.5)]
        p = Vector(points[0])
        d = Vector((math.cos(a), rng.uniform(0.6, 1.4), math.sin(a))).normalized()
        for _ in range(6):
            d = (d + Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.1, 0.35), rng.uniform(-0.4, 0.4)))).normalized()
            p = p + d * 0.42
            if p.xz.length > 1.2:
                p.x *= 1.2 / p.xz.length
                p.z *= 1.2 / p.xz.length
            points.append(tuple(p))
        g.tube(points, lambda t: 0.17 * (1 - t) + 0.02, segs=8, smooth=2, wobble=0.15, seed=k)
    for k in range(9):
        a = rng.uniform(0, 6.28)
        g.sphere((0.1, 0.1, 0.1), (math.cos(a) * 0.55, 1.75 + rng.uniform(-0.2, 0.3), math.sin(a) * 0.55), segs=10, rings=6)


def brain(g, rng, level):
    # Cerebro arrugado con la médula colgando y nervios sueltos.
    g.blob((0, 4.6, 0), (0.62, 0.48, 0.7), seed=21, amp=0.09, freq=6.0, subdiv=5, octaves=3)
    y = 4.15
    for k in range(10):
        g.blob((0.02 * math.sin(k), y, 0.1 + 0.05 * math.sin(k * 0.7)), (0.13, 0.09, 0.13), seed=30 + k, amp=0.02, subdiv=2)
        y -= 0.21
    g.sphere((0.12, 0.12, 0.12), (0.25, 4.4, -0.55), segs=12, rings=8)
    g.sphere((0.12, 0.12, 0.12), (-0.25, 4.4, -0.55), segs=12, rings=8)
    for k in range(10):
        a = rng.uniform(0, 6.28)
        start = (math.cos(a) * 0.3, rng.uniform(2.4, 4.3), math.sin(a) * 0.3)
        end = (math.cos(a) * rng.uniform(0.8, 1.2), start[1] - rng.uniform(0.3, 1.4), math.sin(a) * rng.uniform(0.8, 1.2))
        g.tube([start, ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2 + 0.2, (start[2] + end[2]) / 2), end], lambda t: 0.035 * (1 - t) + 0.008, segs=5, smooth=2, wobble=0.3, seed=k)


@prop("SpecimenTank")
def specimen_tank(P):
    tank(P, (96, 150, 86), 6.1, fetus, 41)


@prop("SpecimenTank_2")
def specimen_tank_2(P):
    tank(P, (170, 120, 50), 3.4, tentacles, 42)


@prop("SpecimenTank_3")
def specimen_tank_3(P):
    tank(P, (150, 46, 40), 5.7, brain, 43)


def growth(P, seed, wall_height):
    flesh = P.group("Flesh", mat("Slate", (128, 52, 60), Surface=FLESH, collide=True), split=None)
    veins = P.group("Veins", mat("Slate", (92, 22, 34), Surface=FLESH), split=None)
    sacs = P.group("Pustules", mat("Neon", (150, 60, 40), transparency=0.35), split=None)
    rng = random.Random(seed)
    for k in range(6):
        x = rng.uniform(-1.6, 1.6)
        z = rng.uniform(-0.6, 1.2)
        s = rng.uniform(0.8, 1.5)
        flesh.blob((x, s * 0.5, z), (s, s * 0.75, s * 0.85), seed=seed + k, amp=s * 0.18, freq=1.8, subdiv=3)
    # La carne trepa por la pared de atrás como una piel que se adelgaza hacia arriba.
    skin(flesh, -2.45, 2.45, 0, wall_height, 1.95, seed, bias=0.55, step=0.26, lift=0.22, low=0.9)
    for k in range(7):
        x = rng.uniform(-2.0, 2.0)
        points = [(x, 0.6, rng.uniform(0.3, 1.3))]
        p = Vector(points[0])
        while p.y < wall_height - 0.3:
            p = Vector((max(-2.3, min(2.3, p.x + rng.uniform(-0.6, 0.6))), p.y + rng.uniform(0.5, 0.9), min(1.75, p.z + 0.35)))
            points.append(tuple(p))
        thick = rng.uniform(0.12, 0.24)
        (flesh if thick > 0.2 else veins).tube(points, lambda t, a=thick: a * (1 - 0.75 * t) + 0.02, segs=7, smooth=1, wobble=0.3, seed=k)
    for k in range(14):
        x = rng.uniform(-2.2, 2.2)
        y = rng.uniform(0.2, wall_height * 0.8)
        points = [(x, y, 1.7)]
        for _ in range(4):
            x += rng.uniform(-0.6, 0.6)
            y += rng.uniform(-0.5, 0.8)
            points.append((x, max(0.1, min(wall_height - 0.1, y)), 1.72))
        veins.tube(points, lambda t: 0.06 * (1 - t) + 0.015, segs=4, smooth=1, wobble=0.3, seed=k + 30)
    for k in range(12):
        a = rng.uniform(0, 6.28)
        sacs.blob((math.cos(a) * rng.uniform(0.6, 1.8), rng.uniform(0.6, 1.6), math.sin(a) * rng.uniform(0.3, 1.0)),
                  (0.16, 0.14, 0.16), seed=k + 60, amp=0.03, subdiv=2)


@prop("GrowthMass")
def growth_mass(P):
    growth(P, 51, 6.0)


@prop("GrowthMass_2")
def growth_mass_2(P):
    growth(P, 52, 5.6)


def skin(group, x0, x1, y0, y1, wall, seed, bias=0.35, step=0.24, lift=0.28, low=None):
    """Piel pegada a una pared (plano z = wall): lámina con relieve, borde irregular
    y huecos por donde se ve la pared. `low` hace que crezca más cerca del piso."""
    nx, ny = int((x1 - x0) / step), int((y1 - y0) / step)
    offset = Vector((seed * 3.1, seed * 1.7, 0))

    def mask(x, y):
        base = noise.noise(Vector((x * 0.16, y * 0.16, 0)) + offset)
        detail = noise.noise(Vector((x * 0.6, y * 0.6, 1.3)) + offset) * 0.35
        edge = min(x - x0, x1 - x, y - y0, y1 - y)
        m = base + detail + bias - (0.6 if edge < 0.5 else 0)
        if low:
            m -= max(0.0, y - y0) / (y1 - y0) * low
        return m

    index_of, verts, faces = {}, [], []
    for i in range(nx + 1):
        for j in range(ny + 1):
            x, y = x0 + i * step, y0 + j * step
            # Un temblor en el plano para que el borde no salga en escalera.
            jx = noise.noise(Vector((x * 2.3, y * 2.3, 5.0)) + offset) * step * 0.45
            jy = noise.noise(Vector((x * 2.3, y * 2.3, 9.0)) + offset) * step * 0.45
            m = mask(x, y)
            bulge = max(0.0, m) * lift + max(0.0, noise.noise(Vector((x * 1.4, y * 1.4, 2.0)) + offset)) * 0.06
            index_of[(i, j)] = len(verts)
            verts.append((x + jx, y + jy, wall - 0.09 - bulge))
    for i in range(nx):
        for j in range(ny):
            if mask(x0 + (i + 0.5) * step, y0 + (j + 0.5) * step) > 0.05:
                faces.append([index_of[(i, j)], index_of[(i, j + 1)], index_of[(i + 1, j + 1)], index_of[(i + 1, j)]])
    # Borde suave: los vértices del contorno se promedian con sus vecinos del
    # contorno (sólo en el plano de la pared) para que no quede en escalera.
    edge_count = {}
    for f in faces:
        for a, b in zip(f, f[1:] + f[:1]):
            key = (min(a, b), max(a, b))
            edge_count[key] = edge_count.get(key, 0) + 1
    neighbors = {}
    for (a, b), count in edge_count.items():
        if count == 1:
            neighbors.setdefault(a, []).append(b)
            neighbors.setdefault(b, []).append(a)
    for _ in range(4):
        moved = {}
        for v, near in neighbors.items():
            if len(near) == 2:
                x = (verts[v][0] * 2 + verts[near[0]][0] + verts[near[1]][0]) / 4
                y = (verts[v][1] * 2 + verts[near[0]][1] + verts[near[1]][1]) / 4
                moved[v] = (x, y, verts[v][2])
        for v, p in moved.items():
            verts[v] = p
    # El borde se mete en la pared: la piel sale del muro sin ninguna zona casi
    # pegada a él (eso parpadeaba).
    for v in neighbors:
        verts[v] = (verts[v][0], verts[v][1], wall + 0.1)
    used = sorted({v for f in faces for v in f})
    remap = {old: new for new, old in enumerate(used)}
    group.raw([verts[v] for v in used], [[remap[v] for v in f] for f in faces])


def wall_growth(P, seed):
    """Tejido que tomó la pared: venas que se ramifican, membranas y bolsas.
    Plano de la pared en z = +0.8; todo sobresale hacia la sala (-Z)."""
    membrane = P.group("Membrane", mat("Slate", (120, 44, 52), Surface=FLESH), split=None)
    veins = P.group("Veins", mat("Slate", (88, 20, 32), Surface=FLESH), split=None)
    sacs = P.group("Pustules", mat("Neon", (140, 52, 36), transparency=0.4), split=None)
    rng = random.Random(seed)
    W, H, WALL = 7.0, 10.0, 0.8

    def grow(start, direction, length, radius, depth):
        p = Vector(start)
        d = Vector(direction).normalized()
        points = [tuple(p)]
        steps = max(3, int(length / 0.7))
        for _ in range(steps):
            d = (d + Vector((rng.uniform(-0.45, 0.45), rng.uniform(-0.45, 0.45), 0))).normalized()
            p = p + d * (length / steps)
            p.x = max(-W, min(W, p.x))
            p.y = max(0.05, min(H - 0.05, p.y))
            points.append((p.x, p.y, 0))
        def r_at(t):
            return radius * (1 - 0.8 * t) + 0.03
        pts = [(x, y, WALL - 0.1 - r_at(i / (len(points) - 1)) * 0.75) for i, (x, y, _) in enumerate(points)]
        segs = 7 if radius > 0.2 else (5 if radius > 0.1 else 3)
        (membrane if radius > 0.3 else veins).tube(pts, r_at, segs=segs, smooth=1 if radius > 0.1 else 0, wobble=0.3, seed=rng.randint(0, 99))
        if depth > 0:
            for _ in range(rng.randint(2, 3)):
                k = rng.randint(1, len(pts) - 2)
                side = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0))
                grow(pts[k], side, length * rng.uniform(0.45, 0.7), radius * 0.55, depth - 1)
        return pts

    skin(membrane, -W, W, 0, H, WALL, seed, bias=0.12)

    trunks = [((-W + 1, 0.1, 0), (0.3, 1, 0)), ((W - 1.5, 0.1, 0), (-0.4, 1, 0)), ((-1, H - 0.1, 0), (0.2, -1, 0)),
              ((2.5, H - 0.1, 0), (-0.3, -1, 0)), ((-W + 0.1, 6.5, 0), (1, -0.2, 0)), ((W - 0.1, 4.0, 0), (-1, 0.3, 0))]
    for start, direction in trunks:
        grow(start, direction, rng.uniform(6, 9), rng.uniform(0.3, 0.42), 3)
    for k in range(5):
        cx, cy = rng.uniform(-W + 1.5, W - 1.5), rng.uniform(1.5, H - 2)
        for _ in range(rng.randint(3, 6)):
            r = rng.uniform(0.12, 0.26)
            sacs.blob((cx + rng.uniform(-0.5, 0.5), cy + rng.uniform(-0.5, 0.5), WALL - 0.3 - r * 0.5), (r, r * 0.9, r), seed=rng.randint(0, 999), amp=0.03, subdiv=2)


@prop("WallGrowth")
def wall_growth_1(P):
    wall_growth(P, 61)


@prop("WallGrowth_2")
def wall_growth_2(P):
    wall_growth(P, 62)


@prop("OperatingTable")
def operating_table(P):
    steel = P.group("Steel", mat("Metal", (160, 166, 168), collide=True))
    pads = P.group("Pads", mat("Leather", (34, 36, 40)), split=None)
    straps = P.group("Straps", mat("Leather", (92, 64, 42)))
    cloth = P.group("Cloth", mat("Fabric", (150, 146, 132)), split=None, solidify=0.03)
    dish = P.group("LampDish", mat("Plastic", (214, 214, 206)), split=None)
    bulbs = P.group("Bulbs", mat("Neon", (255, 236, 200)))
    tools = P.group("Tools", mat("Metal", (200, 204, 206), reflectance=0.15))
    blood = P.group("Blood", mat("Slate", (88, 16, 20)), split=None)
    steel.lathe([(0, 0), (1.1, 0), (1.1, 0.1), (0.55, 0.24), (0.4, 0.3), (0.4, 0.32), (0, 0.32)], segs=32)
    steel.cyl(0.32, 1.8, (0, 1.2, 0), axis="y", segs=20)
    steel.box((0.9, 0.3, 1.6), (0, 2.15, 0), bevel=0.05)
    steel.box((2.4, 0.16, 6.0), (0, 2.34, 0), bevel=0.04)
    for s in (-1, 1):
        steel.tube([(s * 1.28, 2.36, -2.9), (s * 1.28, 2.36, 2.9)], 0.045, segs=6)
    z = -2.95
    for length in (1.9, 2.4, 1.45):
        pads.cushion((2.3, 0.24, length - 0.06), (0, 2.54, z + length / 2), round_=0.35)
        z += length
    pads.cushion((1.0, 0.2, 0.7), (0, 2.75, 2.25), round_=0.4)
    for zz in (-1.6, 0.3, 1.5):
        straps.box((2.42, 0.05, 0.28), (0, 2.68, zz), bevel=0.01)
        tools.box((0.18, 0.06, 0.2), (1.22, 2.68, zz), bevel=0.01)
    cloth.cloth(-1.6, 1.6, -3.0, -0.6, 2.8, drop=0.5, edge=1.15, seed=3, wrinkle=0.05)
    blood.blob((0.3, 2.66, 0.5), (0.6, 0.02, 0.45), seed=5, amp=0.05, subdiv=3)
    blood.blob((-0.7, 0.01, 1.4), (0.8, 0.01, 0.55), seed=6, amp=0.08, subdiv=3)
    # Lámpara cialítica colgada del techo.
    steel.cyl(0.3, 0.12, (0, 9.94, 0.6), axis="y", segs=16)
    steel.tube([(0, 9.9, 0.6), (0, 9.0, 0.6), (0.4, 8.75, 0.45), (0.85, 8.55, 0.2)], 0.07, segs=8, smooth=1)
    steel.sphere((0.12, 0.12, 0.12), (0, 9.0, 0.6), segs=10, rings=6)
    dish.lathe([(0, 0.45), (0.3, 0.44), (0.8, 0.32), (1.2, 0.05), (1.25, 0.0), (1.18, -0.02), (0, -0.02)], center=(0.9, 8.05, 0.0), rot=(0.25, 0, 0.15), segs=32)
    for k in range(6):
        a = k * math.pi / 3
        bulbs.sphere((0.13, 0.06, 0.13), (0.9 + math.cos(a) * 0.62, 8.0 - 0.02, math.sin(a) * 0.62 + 0.0), rot=(0.25, 0, 0.15), segs=10, rings=6)
    bulbs.sphere((0.18, 0.07, 0.18), (0.9, 7.98, 0.0), rot=(0.25, 0, 0.15), segs=12, rings=6)
    # Mesa de instrumental (Mayo) en la cabecera.
    steel.cyl(0.05, 3.1, (1.0, 1.55, 3.05), axis="y", segs=8)
    steel.box((0.9, 0.06, 0.12), (1.0, 0.04, 3.05), bevel=0.02)
    steel.box((1.6, 0.05, 1.0), (0.4, 3.12, 3.0), bevel=0.02)
    for k in range(5):
        tools.box((0.06, 0.03, 0.6), (-0.1 + k * 0.2, 3.17, 2.95), rot=(0, (k - 2) * 0.12, 0), bevel=0.01)
    blood.blob((0.6, 3.16, 3.15), (0.25, 0.015, 0.2), seed=8, amp=0.03, subdiv=2)


# ---------------------------------------------------------------------------
# Lobby, puertas y depósito
# ---------------------------------------------------------------------------

@prop("LobbyBench")
def lobby_bench(P):
    """Banco de sala de espera: cuatro butacas de cuerina sobre una viga de metal."""
    seats = P.group("Seats", mat("Leather", (30, 30, 34), reflectance=0.06, collide=True), split=None)
    frame = P.group("Frame", mat("Metal", (96, 98, 100)))
    for k in range(4):
        x = -2.55 + k * 1.7
        seats.cushion((1.55, 0.34, 1.6), (x, 1.62, -0.15), round_=0.3, sag=0.03, seed=k)
        seats.cushion((1.55, 1.75, 0.3), (x, 2.75, 0.72), rot=(-0.16, 0, 0), round_=0.3, sag=0.03, seed=k + 9)
        frame.box((1.2, 0.08, 1.2), (x, 1.42, -0.1), bevel=0.02)
        frame.tube([(x, 1.4, 0.45), (x, 1.9, 0.78), (x, 2.3, 0.82)], 0.05, segs=6)
    frame.box((6.9, 0.22, 0.3), (0, 1.25, 0.1), bevel=0.04)
    for x in (-2.9, 2.9):
        frame.box((0.22, 1.2, 0.26), (x, 0.65, 0.1), bevel=0.03)
        frame.box((0.3, 0.1, 1.9), (x, 0.05, -0.05), bevel=0.03)
        frame.tube([(x * 1.17, 1.5, -0.8), (x * 1.17, 2.2, -0.75), (x * 1.17, 2.2, 0.55), (x * 1.17, 1.5, 0.6)], 0.05, segs=6, smooth=1)


def door_bolts(g, w, h, z, step=0.9, r=0.05):
    y = -h / 2 + 0.25
    while y < h / 2:
        for x in (-w / 2 + 0.2, w / 2 - 0.2):
            g.cyl(r, 0.06, (x, y, z), axis="z", segs=8)
        y += step


@prop("DoorOffice")
def door_office(P):
    """Hoja de puerta de clínica (5 x 9 x 0.4): bastidor, tableros, vidrio armado."""
    wood = P.group("Wood", mat("Wood", (150, 156, 142), collide=False))
    glass = P.group("Glass", mat("Glass", (150, 160, 150), transparency=0.45, reflectance=0.05))
    metal = P.group("Metal", mat("Metal", (110, 112, 110)))
    w, h, d = 5.0, 9.0, 0.4
    for x in (-w / 2 + 0.35, w / 2 - 0.35):
        wood.box((0.7, h, d), (x, 0, 0), bevel=0.03)
    for y, t in ((h / 2 - 0.4, 0.8), (0.6, 0.7), (-h / 2 + 0.55, 1.1)):
        wood.box((w - 1.4, t, d), (0, y, 0), bevel=0.03)
    wood.box((w - 1.4, 3.0, 0.2), (0, -1.75, 0), bevel=0.02)
    wood.box((w - 2.2, 2.2, 0.3), (0, -1.75, 0), bevel=0.06)
    glass.box((w - 1.4, 2.9, 0.08), (0, 2.4, 0))
    for k in range(5):
        metal.box((0.03, 2.9, 0.1), (-1.5 + k * 0.75, 2.4, 0))
    for k in range(4):
        metal.box((w - 1.4, 0.03, 0.1), (0, 1.2 + k * 0.8, 0))
    metal.box((w - 0.3, 1.0, d + 0.06), (0, -h / 2 + 0.6, 0), bevel=0.02)
    for z in (-0.3, 0.3):
        metal.tube([(1.7, -0.9, z * 0.7), (1.7, -0.9, z), (1.7, 0.5, z), (1.7, 0.5, z * 0.7)], 0.05, segs=6)
        metal.box((0.5, 1.9, 0.03), (1.7, -0.2, z * 0.72))
    for y in (-3.2, 0, 3.2):
        metal.cyl(0.07, 0.5, (-w / 2, y, 0), axis="y", segs=8)


@prop("DoorAirlock")
def door_airlock(P):
    steel = P.group("Steel", mat("Metal", (158, 162, 160)))
    hazard = P.group("Hazard", mat("Metal", (196, 158, 40)))
    glass = P.group("Glass", mat("Glass", (70, 90, 80), transparency=0.35))
    growth = P.group("Growth", mat("Slate", (96, 30, 40), Surface=FLESH), split=None)
    w, h, d = 5.0, 9.0, 0.4
    steel.box((w, h, d * 0.7), (0, 0, 0), bevel=0.03)
    for y in (-2.9, 0.0):
        steel.box((w - 1.3, 2.3, d), (0.25, y, 0), bevel=0.08)
    for y in (-4.2, -1.45, 1.4, 4.2):
        steel.box((w - 0.7, 0.22, d + 0.08), (0.25, y, 0), bevel=0.03)
    door_bolts(steel, w - 0.9, h, d / 2 + 0.01)
    door_bolts(steel, w - 0.9, h, -d / 2 - 0.01)
    k = -h / 2 + 0.3
    while k < h / 2 - 0.3:
        hazard.box((0.5, 0.42, d + 0.04), (-w / 2 + 0.26, k, 0), rot=(0, 0, 0.6))
        k += 0.9
    for z in (-1, 1):
        steel.torus(0.72, 0.12, (0.25, 2.9, z * d / 2), axis="z", segs=24, ring=6)
    glass.cyl(0.66, d * 0.5, (0.25, 2.9, 0), axis="z", segs=24)
    steel.box((0.5, 1.5, d + 0.3), (w / 2 - 0.5, -0.3, 0), bevel=0.05)
    for s in (-1, 1):
        growth.blob((0.2, -h / 2 + 0.45, s * 0.22), (1.9, 0.5, 0.2), seed=3 + s, amp=0.1, subdiv=3)
        growth.tube([(-1.2, -h / 2 + 0.6, s * 0.3), (-0.6, -2.4, s * 0.28), (0.3, -1.2, s * 0.27), (0.1, 0.2, s * 0.26)],
                    lambda t: 0.1 * (1 - t) + 0.02, segs=5, smooth=1, wobble=0.3, seed=s)


@prop("DoorVault")
def door_vault(P):
    steel = P.group("Steel", mat("DiamondPlate", (92, 100, 112)))
    parts = P.group("Fittings", mat("Metal", (70, 76, 86)))
    w, h, d = 10.0, 9.0, 0.5
    steel.box((w, h, d * 0.7), (0, 0, 0), bevel=0.04)
    for x in (-3.3, 0, 3.3):
        parts.box((0.45, h - 0.4, d + 0.14), (x, 0, 0), bevel=0.05)
    for y in (-h / 2 + 0.3, h / 2 - 0.3):
        parts.box((w - 0.2, 0.4, d + 0.1), (0, y, 0), bevel=0.04)
    door_bolts(parts, w, h, d / 2 + 0.05, step=0.7, r=0.07)
    door_bolts(parts, w, h, -d / 2 - 0.05, step=0.7, r=0.07)
    for z in (-1, 1):
        zc = z * (d / 2 + 0.3)
        parts.torus(0.9, 0.09, (1.65, 0, zc), axis="z", segs=28, ring=6)
        for k in range(5):
            a = k * 2 * math.pi / 5
            parts.tube([(1.65, 0, zc), (1.65 + math.cos(a) * 0.9, math.sin(a) * 0.9, zc)], 0.05, segs=5, caps=False)
        parts.cyl(0.18, 0.4, (1.65, 0, z * (d / 2 + 0.15)), axis="z", segs=12)
        for y in (-2.6, 2.6):
            parts.box((1.4, 0.5, 0.2), (-2.0, y, z * (d / 2 + 0.08)), bevel=0.04)
            parts.cyl(0.14, 0.3, (-1.2, y, z * (d / 2 + 0.15)), axis="z", segs=10)


@prop("DoorHome")
def door_home(P):
    wood = P.group("Wood", mat("WoodPlanks", (112, 80, 56)))
    brass = P.group("Brass", mat("Metal", (176, 150, 90), reflectance=0.1), split=None)
    w, h, d = 4.9, 9.0, 0.35
    for x in (-w / 2 + 0.4, w / 2 - 0.4):
        wood.box((0.8, h, d), (x, 0, 0), bevel=0.03)
    wood.box((0.6, h, d), (0, 0, 0), bevel=0.03)
    for y, t in ((h / 2 - 0.45, 0.9), (0.9, 0.7), (-0.9, 0.7), (-h / 2 + 0.55, 1.1)):
        wood.box((w - 1.6, t, d), (0, y, 0), bevel=0.03)
    wood.box((w - 1.6, h - 2.0, 0.16), (0, 0, 0))
    for x in (-1.0, 1.0):
        for y, ph in ((2.65, 2.2), (0.0, 0.8), (-2.6, 2.1)):
            wood.box((1.1, ph, 0.26), (x, y, 0), bevel=0.07)
    for z in (-1, 1):
        brass.cyl(0.2, 0.05, (1.8, -0.4, z * (d / 2 + 0.02)), axis="z", segs=14)
        brass.cyl(0.06, 0.22, (1.8, -0.4, z * (d / 2 + 0.12)), axis="z", segs=8)
        brass.sphere((0.17, 0.17, 0.15), (1.8, -0.4, z * (d / 2 + 0.28)), segs=12, rings=8)
        brass.box((0.12, 0.45, 0.03), (1.8, -1.1, z * (d / 2 + 0.01)), bevel=0.01)


@prop("DoorShutter")
def door_shutter(P):
    slats = P.group("Slats", mat("CorrodedMetal", (86, 84, 80)), split=50)
    bar = P.group("Bar", mat("Metal", (52, 52, 50)))
    w, h, d = 10.0, 9.0, 0.3
    n = 22
    for k in range(n):
        y = -h / 2 + 0.5 + (k + 0.5) * (h - 0.5) / n
        slats.cyl(0.21, w, (0, y, 0), axis="x", segs=8)
    slats.box((w, h - 0.5, 0.12), (0, 0.25, 0))
    bar.box((w, 0.5, d + 0.2), (0, -h / 2 + 0.25, 0), bevel=0.04)
    for z in (-1, 1):
        bar.tube([(-0.5, -h / 2 + 0.3, z * 0.25), (-0.5, -h / 2 + 0.3, z * 0.45), (0.5, -h / 2 + 0.3, z * 0.45), (0.5, -h / 2 + 0.3, z * 0.25)], 0.05, segs=6)
    for x in (-w / 2 + 0.08, w / 2 - 0.08):
        bar.box((0.16, h, d + 0.16), (x, 0, 0))


@prop("ElevatorDoor")
def elevator_door(P):
    steel = P.group("Steel", mat("Metal", (146, 150, 152), reflectance=0.12))
    trim = P.group("Trim", mat("Metal", (70, 72, 74)))
    w, h, d = 4.0, 12.0, 0.4
    steel.box((w, h, d * 0.6), (0, 0, 0), bevel=0.02)
    for z in (-1, 1):
        steel.box((w - 0.9, h - 1.6, 0.1), (0, 0.2, z * 0.14), bevel=0.04)
        for k in range(6):
            trim.box((w - 1.3, 0.03, 0.03), (0, -4.5 + k * 1.9, z * 0.2))
        trim.box((w - 0.2, 0.9, 0.06), (0, -h / 2 + 0.55, z * 0.14), bevel=0.02)
    for x in (-w / 2 + 0.06, w / 2 - 0.06):
        trim.box((0.12, h, d), (x, 0, 0))


@prop("Crate")
def crate(P):
    wood = P.group("Wood", mat("WoodPlanks", (104, 82, 58), collide=True))
    metal = P.group("Metal", mat("CorrodedMetal", (84, 74, 66)))
    rng = random.Random(71)

    def one(center, size, yaw):
        cx, cy, cz = center
        sx, sy, sz = size
        wood.box((sx - 0.2, sy - 0.2, sz - 0.2), center, rot=(0, yaw, 0))
        c, s = math.cos(yaw), math.sin(yaw)
        def at(x, y, z):
            return (cx + x * c + z * s, cy + y, cz - x * s + z * c)
        n = 5
        for k in range(n):
            x = -sx / 2 + (k + 0.5) * sx / n
            for z in (-sz / 2, sz / 2):
                wood.box((sx / n - 0.04, sy - 0.1, 0.1), at(x, 0, z), rot=(0, yaw, 0))
            z = -sz / 2 + (k + 0.5) * sz / n
            for x2 in (-sx / 2, sx / 2):
                wood.box((0.1, sy - 0.1, sz / n - 0.04), at(x2, 0, z), rot=(0, yaw, 0))
            wood.box((sx / n - 0.04, 0.1, sz), at(x, sy / 2, 0), rot=(0, yaw, 0))
        for y in (-sy / 2 + 0.25, sy / 2 - 0.25):
            for z in (-sz / 2 - 0.06, sz / 2 + 0.06):
                wood.box((sx + 0.1, 0.3, 0.1), at(0, y, z), rot=(0, yaw, 0))
            for x2 in (-sx / 2 - 0.06, sx / 2 + 0.06):
                wood.box((0.1, 0.3, sz + 0.1), at(x2, y, 0), rot=(0, yaw, 0))
        for x2 in (-sx / 2, sx / 2):
            for z in (-sz / 2, sz / 2):
                metal.box((0.3, sy + 0.04, 0.3), at(x2 * 0.99, 0, z * 0.99), rot=(0, yaw, 0), bevel=0.03)

    one((-0.6, 1.3, 0.5), (2.6, 2.6, 2.6), 0.0)
    one((1.2, 0.9, -0.9), (1.6, 1.8, 1.6), 0.4)
    one((-0.5, 3.6, 0.5), (2.0, 2.0, 2.0), 0.25)


@prop("Barrel")
def barrel(P):
    drum = P.group("Drum", mat("CorrodedMetal", (96, 62, 44), collide=True), split=40)
    lid = P.group("Lid", mat("Metal", (60, 60, 58)))
    profile = [(0, 0), (1.2, 0), (1.26, 0.06), (1.26, 0.18), (1.2, 0.22)]
    for y in (1.45, 2.95):
        profile += [(1.2, y - 0.12), (1.27, y - 0.05), (1.27, y + 0.05), (1.2, y + 0.12)]
    profile += [(1.2, 4.2), (1.26, 4.26), (1.26, 4.4), (1.18, 4.42), (1.16, 4.3), (0, 4.3)]
    drum.lathe(profile, center=(0, 0, 0), segs=28)
    lid.cyl(0.16, 0.1, (0.6, 4.34, 0.3), axis="y", segs=12)
    lid.cyl(0.09, 0.1, (-0.7, 4.34, -0.2), axis="y", segs=10)
    lid.torus(1.22, 0.035, (0, 4.38, 0), axis="y", segs=28, ring=5)


@prop("CornerPipe")
def corner_pipe(P):
    pipe = P.group("Pipe", mat("CorrodedMetal", (104, 76, 60), collide=True), split=45)
    steel = P.group("Fittings", mat("Metal", (70, 72, 72)))
    pipe.cyl(0.55, 13, (0.2, 6.5, 0.2), axis="y", segs=16)
    pipe.tube([(-0.6, 0, 0.5), (-0.6, 4.2, 0.5), (-0.6, 4.8, 0.2), (-0.6, 4.8, -0.9)], 0.22, segs=10, smooth=2)
    pipe.tube([(-0.6, 13, 0.5), (-0.6, 9.0, 0.5), (-0.3, 8.4, 0.5), (0.2, 8.4, 0.4)], 0.18, segs=8, smooth=2)
    for y in (0.25, 3.3, 6.5, 9.7, 12.75):
        steel.cyl(0.72, 0.22, (0.2, y, 0.2), axis="y", segs=16, bevel=0.03)
        for k in range(8):
            a = k * math.pi / 4
            steel.cyl(0.05, 0.3, (0.2 + math.cos(a) * 0.63, y, 0.2 + math.sin(a) * 0.63), axis="y", segs=6)
    steel.torus(0.42, 0.05, (-0.6, 2.4, 0.5), axis="z", segs=20, ring=6)
    for k in range(4):
        a = k * math.pi / 2
        steel.tube([(-0.6, 2.4, 0.5), (-0.6 + math.cos(a) * 0.42, 2.4 + math.sin(a) * 0.42, 0.5)], 0.03, segs=5, caps=False)
    steel.cyl(0.06, 0.6, (-0.6, 2.4, 0.3), axis="z", segs=8)
    for y in (1.5, 7.2, 11.2):
        steel.box((1.9, 0.14, 0.12), (-0.1, y, 0.82), bevel=0.02)


@prop("Shelf")
def shelf(P):
    steel = P.group("Frame", mat("Metal", (104, 108, 106), collide=True))
    boxes = P.group("Boxes", mat("Cardboard", (150, 122, 86)))
    cans = P.group("Cans", mat("CorrodedMetal", (96, 70, 56)), split=45)
    rng = random.Random(81)
    for x in (-2.9, 2.9):
        for z in (-0.85, 0.85):
            steel.box((0.14, 7.2, 0.14), (x, 3.6, z), bevel=0.02)
            y = 0.5
            while y < 7:
                steel.cyl(0.03, 0.16, (x, y, z), axis="z", segs=6)
                y += 0.5
    for x in (-2.9, 2.9):
        steel.tube([(x, 0.6, -0.85), (x, 3.4, 0.85)], 0.03, segs=5)
        steel.tube([(x, 3.8, 0.85), (x, 6.6, -0.85)], 0.03, segs=5)
    levels = (0.5, 2.2, 3.9, 5.6)
    for y in levels:
        steel.box((5.9, 0.1, 1.84), (0, y, 0), bevel=0.02)
        steel.box((5.9, 0.2, 0.06), (0, y - 0.05, -0.92))
    for y in levels:
        x = -2.6
        while x < 2.3:
            if rng.random() < 0.55:
                w, h2, d2 = rng.uniform(0.8, 1.5), rng.uniform(0.6, 1.3), rng.uniform(1.0, 1.5)
                boxes.box((w, h2, d2), (x + w / 2, y + 0.05 + h2 / 2, rng.uniform(-0.1, 0.1)), rot=(0, rng.uniform(-0.15, 0.15), 0), bevel=0.02)
                boxes.box((w + 0.02, 0.03, 0.2), (x + w / 2, y + 0.05 + h2, 0), rot=(0, 0, 0))
                x += w + 0.15
            elif rng.random() < 0.6:
                r = rng.uniform(0.2, 0.32)
                h2 = rng.uniform(0.6, 1.0)
                cans.lathe([(0, 0), (r, 0), (r + 0.02, 0.03), (r + 0.02, h2 - 0.03), (r, h2), (0, h2)], center=(x + r, y + 0.05, rng.uniform(-0.4, 0.4)), segs=14)
                x += 2 * r + 0.12
            else:
                x += rng.uniform(0.4, 0.9)


# ---------------------------------------------------------------------------
# El Organismo (persecución final): un cuadrúpedo colosal. Cada grupo es una pieza
# que anima ChaseCreature.lua, con sus ejes: largo de las patas en Y, frente -Z.
# ---------------------------------------------------------------------------

PLATE = "OrganismoPlate"


@prop("Organismo")
def organismo(P):
    def flesh(name, color=(150, 96, 92)):
        return P.group(name, mat("Slate", color, Surface=FLESH), split=None)

    def bone(name):
        return P.group(name, mat("Slate", (170, 156, 138), Surface=PLATE), split=None)

    # Torso largo con costillas marcadas (10 x 7 x 17).
    g = flesh("Body")
    for k in range(6):
        z = -7 + k * 2.8
        r = 4.6 - abs(k - 2) * 0.45
        g.blob((0, 0.2 - k * 0.12, z), (r, r * 0.68, 2.3), seed=k + 1, amp=0.3, freq=1.8, subdiv=3)
    for k in range(7):
        z = -6.5 + k * 2.0
        for s in (-1, 1):
            g.tube([(s * 0.8, 3.0, z), (s * 3.6, 2.2, z + 0.2), (s * 4.7, -0.3, z + 0.4), (s * 3.4, -2.8, z + 0.5)],
                   lambda t: 0.34 * (1 - 0.5 * t), segs=6, smooth=2)
    # Pecho y hombros (13 x 8.5 x 8).
    g = flesh("Chest")
    g.blob((0, 0, 0), (5.4, 3.9, 3.8), seed=11, amp=0.35, freq=1.6, subdiv=4)
    for s in (-1, 1):
        g.blob((s * 4.6, 1.2, -0.4), (2.6, 2.7, 2.9), seed=12 + s, amp=0.3, subdiv=3)
        g.blob((s * 2.2, -2.2, -1.6), (2.4, 1.8, 2.2), seed=15 + s, amp=0.2, subdiv=3)
    # Cabeza sin ojos, larga, con arcos de hueso y dientes arriba (6.5 x 5 x 7.5).
    g = flesh("Head")
    g.blob((0, 0.3, 0.6), (3.0, 2.3, 3.4), seed=21, amp=0.22, freq=2.2, subdiv=4)
    g.blob((0, -0.3, -2.2), (2.5, 1.6, 2.0), seed=22, amp=0.15, subdiv=3)
    for s in (-1, 1):
        g.tube([(s * 0.5, 1.9, -2.8), (s * 1.9, 2.0, -0.6), (s * 2.7, 1.3, 1.8), (s * 2.2, 0.2, 3.4)], lambda t: 0.42 * (1 - 0.4 * t), segs=6, smooth=2)
    for k in range(11):
        a = -1.3 + k * 0.26
        g.cyl(0.02, 1.15, (math.sin(a) * 2.2, -1.75, -3.1 - math.cos(a) * 0.75), axis="y", radius2=0.19, segs=6)
    # Mandíbula en U con dientes hacia arriba (5.6 x 1.5 x 6).
    g = flesh("Jaw", (120, 70, 70))
    pts = [(-2.5, 0, 2.8), (-2.6, -0.1, 0), (-2.0, -0.2, -2.3), (0, -0.25, -3.0), (2.0, -0.2, -2.3), (2.6, -0.1, 0), (2.5, 0, 2.8)]
    g.tube(pts, 0.55, segs=8, smooth=2)
    g.blob((0, -0.35, 0.4), (2.3, 0.3, 2.6), seed=31, amp=0.08, subdiv=3)
    for k in range(13):
        a = -1.45 + k * 0.24
        g.cyl(0.17, 1.0, (math.sin(a) * 2.35, 0.55, -0.3 - math.cos(a) * 2.5), axis="y", radius2=0.02, segs=6)
    # Saco nervioso (punto débil).
    g = P.group("WeakPoint", mat("Neon", (255, 120, 60)), split=None)
    g.blob((0, 0, 0), (1.5, 1.2, 1.5), seed=41, amp=0.28, freq=3.0, subdiv=4, octaves=3)
    # Placa de la cresta.
    g = bone("Spine")
    g.lathe([(0, -1.2), (0.75, -1.1), (0.6, -0.2), (0.32, 0.7), (0, 1.3)], rot=(0.0, 0, 0), segs=8)
    # Brazo y muslo: músculo que se afina (largo en Y).
    for name, top, low in (("Arm", 1.4, 1.0), ("Thigh", 1.7, 1.1)):
        g = flesh(name)
        g.blob((0, 1.3, 0), (top, 1.9, top), seed=51, amp=0.2, subdiv=3)
        g.blob((0.1, -0.5, 0.1), (top * 0.85, 1.9, top * 0.8), seed=52, amp=0.18, subdiv=3)
        g.blob((0, -2.1, 0), (low, 0.9, low), seed=53, amp=0.12, subdiv=3)
    for name in ("Forearm", "Shin"):
        g = flesh(name, (110, 62, 62))
        g.blob((0, 1.2, 0), (1.1, 1.7, 1.1), seed=61, amp=0.15, subdiv=3)
        g.blob((0, -1.2, 0), (0.8, 1.7, 0.8), seed=62, amp=0.1, subdiv=3)
        for k in range(4):
            a = k * 1.57 + 0.4
            g.tube([(math.cos(a) * 0.8, 2.3, math.sin(a) * 0.8), (math.cos(a) * 0.95, 0.4, math.sin(a) * 0.95), (math.cos(a) * 0.6, -2.5, math.sin(a) * 0.6)], 0.14, segs=5, smooth=2)
    # Mano y pie: palma y garras largas hacia adelante (-Z).
    for name, count, reach in (("Claw", 4, 4.0), ("Foot", 3, 2.9)):
        g = bone(name)
        g.blob((0, 0, 1.4), (1.9, 0.6, 1.5), seed=71, amp=0.15, subdiv=3)
        for k in range(count):
            x = (k - (count - 1) / 2) * (3.6 / count)
            g.tube([(x * 0.7, 0.1, 0.6), (x, 0.45, -0.6), (x * 1.15, 0.2, -reach * 0.7), (x * 1.2, -0.55, -reach)],
                   lambda t: 0.42 * (1 - t) + 0.03, segs=7, smooth=2)
    # Tramo de lengua (a lo largo de Z).
    g = flesh("Tongue", (190, 80, 96))
    g.blob((0, 0, 0), (0.62, 0.42, 1.45), seed=81, amp=0.06, freq=3.0, subdiv=3)


# ---------------------------------------------------------------------------
# Armado, UV, exportación y vistas previas
# ---------------------------------------------------------------------------

def uv_box(mesh, roblox_verts, tile):
    layer = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        ids = [mesh.loops[i].vertex_index for i in poly.loop_indices]
        pts = [roblox_verts[i] for i in ids]
        n = Vector((0, 0, 0))
        for a, b in zip(pts, pts[1:] + pts[:1]):
            n.x += (a.y - b.y) * (a.z + b.z)
            n.y += (a.z - b.z) * (a.x + b.x)
            n.z += (a.x - b.x) * (a.y + b.y)
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop_index, p in zip(poly.loop_indices, pts):
            if ax == 0:
                uv = (p.z, p.y)
            elif ax == 1:
                uv = (p.x, p.z)
            else:
                uv = (p.x, p.y)
            layer.data[loop_index].uv = (uv[0] / tile, uv[1] / tile)


def make_object(group, offset_x):
    name = group.prop.name + "__" + group.name
    roblox = [v + Vector((offset_x, 0, 0)) for v in group.verts]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([TO_BLENDER @ v for v in roblox], [], group.faces)
    mesh.validate(clean_customdata=False)
    uv_box(mesh, roblox, group.tile)
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if group.solidify:
        mod = obj.modifiers.new("Solidify", "SOLIDIFY")
        mod.thickness = group.solidify
        mod.offset = -1
    if group.split is not None:
        mod = obj.modifiers.new("EdgeSplit", "EDGE_SPLIT")
        mod.split_angle = math.radians(group.split)
        mod.use_edge_sharp = False
    # Material solo para mirarlo en Blender (Roblox usa props.json).
    color = group.spec["Color"]
    material = bpy.data.materials.new(name + "_mat")
    material.diffuse_color = (color[0] / 255, color[1] / 255, color[2] / 255, 1 - group.spec["Transparency"] * 0.6)
    mesh.materials.append(material)
    # Origen en el centro de la malla: el importador respeta la posición del nodo.
    bpy.context.view_layer.update()
    corners = [Vector(c) for c in obj.bound_box]
    center = sum(corners, Vector()) / 8
    mesh.transform(Matrix.Translation(-center))
    obj.location = center
    return obj


def evaluated_triangles(obj):
    deps = bpy.context.evaluated_depsgraph_get()
    mesh = obj.evaluated_get(deps).to_mesh()
    mesh.calc_loop_triangles()
    count = len(mesh.loop_triangles)
    obj.evaluated_get(deps).to_mesh_clear()
    return count


def render_preview(name, objects):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.display.shading.show_shadows = True
    scene.display.shading.show_xray = False
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.film_transparent = False
    world = bpy.data.worlds.get("Preview") or bpy.data.worlds.new("Preview")
    world.color = (0.12, 0.12, 0.13)
    scene.world = world
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            obj.hide_render = obj not in objects
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for obj in objects:
        for c in obj.bound_box:
            w = obj.matrix_world @ Vector(c)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    center = (lo + hi) / 2
    radius = (hi - lo).length / 2
    cam_data = bpy.data.cameras.get("PreviewCam") or bpy.data.cameras.new("PreviewCam")
    cam = bpy.data.objects.get("PreviewCam") or bpy.data.objects.new("PreviewCam", cam_data)
    if cam.name not in scene.collection.objects:
        scene.collection.objects.link(cam)
    cam_data.lens = 50
    # Frente de Roblox = Blender +Y: la cámara mira desde adelante, arriba y a un costado.
    direction = Vector((0.55, 1.0, 0.45)).normalized()
    cam.location = center + direction * radius * 2.9
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = os.path.join(OUT, "previews", name + ".png")
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    manifest = {}
    report = {}
    offset = 0.0
    built = {}
    for name, build in PROPS.items():
        if ONLY and name not in ONLY:
            continue
        P = Prop(name)
        build(P)
        objects = []
        width = max((max(v.x for v in g.verts) - min(v.x for v in g.verts)) for g in P.groups if g.verts)
        manifest[name] = {}
        report[name] = {}
        for g in P.groups:
            if not g.verts:
                continue
            obj = make_object(g, offset)
            objects.append(obj)
            manifest[name][g.name] = g.spec
            report[name][g.name] = evaluated_triangles(obj)
        built[name] = objects
        offset += width + 4
    for name, objects in built.items():
        render_preview(name, objects)
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    for objects in built.values():
        for obj in objects:
            obj.select_set(True)
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "NocturnaProps.fbx"), use_selection=True,
                             axis_forward="-Z", axis_up="Y", apply_unit_scale=True, use_mesh_modifiers=True,
                             mesh_smooth_type="FACE", object_types={"MESH"})
    with open(os.path.join(OUT, "props.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=1, ensure_ascii=False)
    with open(os.path.join(OUT, "triangles.json"), "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "NocturnaProps.blend"))
    total = 0
    for name, groups in report.items():
        subtotal = sum(groups.values())
        total += subtotal
        print("PROP", name, subtotal, groups)
    print("TOTAL", total)


main()
