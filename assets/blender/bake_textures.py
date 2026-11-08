"""Hornea las texturas PBR propias de NOCTURNA (MaterialVariant de Roblox).

Uso (desde la raíz del repositorio):
  blender -b --factory-startup -P assets/blender/bake_textures.py -- [opciones] [Nombre ...]

  --out DIR       carpeta de salida (por defecto assets/textures)
  --size N        lado de cada mapa en píxeles (por defecto 1024)
  --samples N     muestras de Cycles por píxel al hornear (antialias, por defecto 6)
  --preview       además arma assets/textures/preview.png con los PNG ya escritos
  --only-preview  sólo la hoja de muestra
  Nombre ...      sólo esos materiales (por ejemplo NocturnaTunnelBrick)

Cada material se arma con nodos procedurales de Blender (ruido, voronoi, ruido
fractal multifractal/ridged, ladrillos y baldosas hechos con matemática de UV) y
se hornea con Cycles (pasada EMIT) sobre un plano con UV 0..1:
  * una pasada para el color (albedo) y
  * otra con altura, rugosidad y metalicidad empaquetadas en R, G y B.

Todo es ENROSCABLE sin costura: el ruido no se evalúa en el plano sino sobre un
toro plano en 4D (cos u, sin u, cos v, sin v), así el borde derecho continúa en
el izquierdo y el de arriba en el de abajo; los patrones (ladrillo, baldosa,
tablas, chapa) usan cantidades enteras de piezas por mosaico y el azar por pieza
se toma del índice de la pieza con módulo. La normal se calcula de la altura con
diferencias que dan la vuelta por los bordes (np.roll), en formato OpenGL (Y+,
verde hacia arriba), que es el que usa Roblox.

Escribe en <out>/<Nombre>/:
  <Nombre>_Color.png      sRGB, RGB 8 bits
  <Nombre>_Normal.png     tangente OpenGL, RGB 8 bits
  <Nombre>_Roughness.png  lineal, gris 8 bits
  <Nombre>_Metalness.png  lineal, gris 8 bits (sólo los materiales con metal;
                          sin mapa, Roblox lo toma como no metálico)
y <out>/stats.json con el color medio de cada albedo (lo usa TextureAssets.lua
para no oscurecer las piezas teñidas).
"""

import json
import math
import os
import struct
import sys
import time
import zlib

import bpy
import numpy as np

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def option(name, default=None, flag=False):
    if name in ARGS:
        index = ARGS.index(name)
        if flag:
            ARGS.pop(index)
            return True
        value = ARGS[index + 1]
        del ARGS[index:index + 2]
        return value
    return False if flag else default


OUT = os.path.abspath(option("--out", "assets/textures"))
SIZE = int(option("--size", "1024"))
SAMPLES = int(option("--samples", "6"))
PREVIEW = option("--preview", flag=True)
ONLY_PREVIEW = option("--only-preview", flag=True)
ONLY = [name for name in ARGS if not name.startswith("--")]

TAU = math.pi * 2


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(value):
    value = value.lstrip("#")
    rgb = [int(value[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(srgb_to_linear(c) for c in rgb) + (1.0,)


# Constructor de grafos ------------------------------------------------------------


class Graph:
    """Arma nodos de shader con una sintaxis corta. Cada función devuelve un
    socket de salida (o un número, que se usa como valor fijo)."""

    def __init__(self, material):
        self.nt = material.node_tree
        self.nt.nodes.clear()
        coords = self.node("ShaderNodeTexCoord")
        split = self.node("ShaderNodeSeparateXYZ")
        self.link(coords.outputs["UV"], split.inputs[0])
        self.u = split.outputs[0]
        self.v = split.outputs[1]
        self.tori = {}

    def node(self, kind, **props):
        node = self.nt.nodes.new(kind)
        for key, value in props.items():
            setattr(node, key, value)
        return node

    def link(self, output, target):
        self.nt.links.new(output, target)

    def put(self, socket, value):
        if isinstance(value, bpy.types.NodeSocket):
            self.link(value, socket)
        elif isinstance(value, (tuple, list)):
            socket.default_value = value
        else:
            socket.default_value = value

    @staticmethod
    def enabled(sockets, name, kind=None):
        for socket in sockets:
            if socket.name == name and socket.enabled and (kind is None or socket.type == kind):
                return socket
        raise KeyError(name)

    # Matemática -------------------------------------------------------------------
    def m(self, op, a, b=0.0, c=0.0, clamp=False):
        node = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        self.put(node.inputs[0], a)
        self.put(node.inputs[1], b)
        self.put(node.inputs[2], c)
        return node.outputs[0]

    def add(self, a, b):
        return self.m("ADD", a, b)

    def sub(self, a, b):
        return self.m("SUBTRACT", a, b)

    def mul(self, a, b):
        return self.m("MULTIPLY", a, b)

    def mx(self, a, b):
        return self.m("MAXIMUM", a, b)

    def mn(self, a, b):
        return self.m("MINIMUM", a, b)

    def clamp(self, a):
        return self.m("ADD", a, 0.0, clamp=True)

    def inv(self, a):
        return self.m("SUBTRACT", 1.0, a)

    def frac(self, a):
        return self.m("FRACT", a)

    def floor(self, a):
        return self.m("FLOOR", a)

    def mod(self, a, b):
        return self.m("FLOORED_MODULO", a, b)

    def absv(self, a):
        return self.m("ABSOLUTE", a)

    def sin(self, a):
        return self.m("SINE", a)

    def cos(self, a):
        return self.m("COSINE", a)

    def pw(self, a, b):
        return self.m("POWER", a, b)

    def mad(self, a, b, c):
        return self.m("MULTIPLY_ADD", a, b, c)

    def remap(self, x, a, b, c=0.0, d=1.0, smooth=False, clamp=True):
        node = self.node("ShaderNodeMapRange", data_type="FLOAT",
                         interpolation_type="SMOOTHSTEP" if smooth else "LINEAR", clamp=clamp)
        self.put(node.inputs["Value"], x)
        self.put(node.inputs["From Min"], a)
        self.put(node.inputs["From Max"], b)
        self.put(node.inputs["To Min"], c)
        self.put(node.inputs["To Max"], d)
        return node.outputs["Result"]

    def ss(self, x, a, b):
        """Smoothstep de a a b (si a > b, invertido)."""
        return self.remap(x, a, b, 0.0, 1.0, smooth=True)

    def lerp(self, t, a, b):
        node = self.node("ShaderNodeMix", data_type="FLOAT", clamp_factor=True)
        self.put(self.enabled(node.inputs, "Factor", "VALUE"), t)
        self.put(self.enabled(node.inputs, "A", "VALUE"), a)
        self.put(self.enabled(node.inputs, "B", "VALUE"), b)
        return self.enabled(node.outputs, "Result", "VALUE")

    def mixc(self, t, a, b, blend="MIX"):
        node = self.node("ShaderNodeMix", data_type="RGBA", blend_type=blend, clamp_factor=True)
        self.put(self.enabled(node.inputs, "Factor", "VALUE"), t)
        self.put(self.enabled(node.inputs, "A", "RGBA"), hexcol(a) if isinstance(a, str) else a)
        self.put(self.enabled(node.inputs, "B", "RGBA"), hexcol(b) if isinstance(b, str) else b)
        return self.enabled(node.outputs, "Result", "RGBA")

    def ramp(self, fac, stops):
        node = self.node("ShaderNodeValToRGB")
        elements = node.color_ramp.elements
        while len(elements) < len(stops):
            elements.new(0.5)
        for element, (position, color) in zip(elements, stops):
            element.position = position
            element.color = hexcol(color)
        self.put(node.inputs[0], fac)
        return node.outputs["Color"]

    def scale_color(self, color, factor):
        """Color por un factor (oscurecer/aclarar)."""
        node = self.node("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY", clamp_factor=True)
        self.put(self.enabled(node.inputs, "Factor", "VALUE"), 1.0)
        self.put(self.enabled(node.inputs, "A", "RGBA"), color)
        combine = self.node("ShaderNodeCombineXYZ")
        for index in range(3):
            self.put(combine.inputs[index], factor)
        self.put(self.enabled(node.inputs, "B", "RGBA"), combine.outputs[0])
        return self.enabled(node.outputs, "Result", "RGBA")

    # Coordenadas enroscables --------------------------------------------------------
    def torus(self, fu, fv, seed, u=None, v=None):
        """(vector, w) sobre un toro plano en 4D: fu y fv rasgos por mosaico."""
        key = (fu, fv, seed, id(u), id(v))
        if key in self.tori:
            return self.tori[key]
        u = self.u if u is None else u
        v = self.v if v is None else v
        au = self.mul(u, TAU)
        av = self.mul(v, TAU)
        ru = fu / TAU
        rv = fv / TAU
        offset = (seed * 7.31 + 3.1, seed * 1.73 + 11.4, seed * 3.17 + 5.2, seed * 5.91 + 1.7)
        combine = self.node("ShaderNodeCombineXYZ")
        self.put(combine.inputs[0], self.mad(self.cos(au), ru, offset[0]))
        self.put(combine.inputs[1], self.mad(self.sin(au), ru, offset[1]))
        self.put(combine.inputs[2], self.mad(self.cos(av), rv, offset[2]))
        w = self.mad(self.sin(av), rv, offset[3])
        result = (combine.outputs[0], w)
        self.tori[key] = result
        return result

    def noise(self, f, detail=5.0, rough=0.55, seed=0, fv=None, kind="FBM", dist=0.0, lac=2.0,
              gain=1.0, offset=0.0, u=None, v=None):
        vec, w = self.torus(f, f if fv is None else fv, seed, u, v)
        node = self.node("ShaderNodeTexNoise", noise_dimensions="4D", noise_type=kind, normalize=True)
        self.put(node.inputs["Vector"], vec)
        self.put(node.inputs["W"], w)
        node.inputs["Scale"].default_value = 1.0
        node.inputs["Detail"].default_value = detail
        node.inputs["Roughness"].default_value = rough
        node.inputs["Lacunarity"].default_value = lac
        node.inputs["Distortion"].default_value = dist
        if kind != "FBM":
            node.inputs["Offset"].default_value = offset
            node.inputs["Gain"].default_value = gain
        return node.outputs["Fac"]

    def voronoi(self, f, feature="F1", metric="EUCLIDEAN", rand=1.0, seed=0, fv=None, out="Distance",
                detail=0.0, u=None, v=None):
        vec, w = self.torus(f, f if fv is None else fv, seed, u, v)
        node = self.node("ShaderNodeTexVoronoi", voronoi_dimensions="4D", feature=feature, distance=metric)
        self.put(node.inputs["Vector"], vec)
        self.put(node.inputs["W"], w)
        node.inputs["Scale"].default_value = 1.0
        node.inputs["Randomness"].default_value = rand
        if "Detail" in node.inputs:
            node.inputs["Detail"].default_value = detail
        return node.outputs[out]

    def white(self, a, b, seed=0):
        """Azar 0..1 por pieza a partir de dos índices enteros."""
        combine = self.node("ShaderNodeCombineXYZ")
        self.put(combine.inputs[0], a)
        self.put(combine.inputs[1], b)
        self.put(combine.inputs[2], float(seed) * 1.37 + 0.5)
        node = self.node("ShaderNodeTexWhiteNoise", noise_dimensions="3D")
        self.put(node.inputs["Vector"], combine.outputs[0])
        return node.outputs["Value"]

    # Patrones -----------------------------------------------------------------------
    def grid(self, cols, rows, stagger=0.0, row_jitter=None, warp=None, warp_amount=0.0):
        """Piezas en filas: devuelve dict con col, row, fx, fy (0..1 dentro de la
        pieza), edge (distancia al borde, en fracción de la pieza más corta)."""
        v = self.v
        u = self.u
        if warp is not None:
            u = self.add(u, self.mul(self.sub(warp, 0.5), warp_amount))
            v = self.add(v, self.mul(self.sub(self.noise(9, 3, seed=91), 0.5), warp_amount))
        yy = self.mul(v, rows)
        row = self.floor(yy)
        fy = self.frac(yy)
        shift = 0.0
        if stagger:
            shift = self.mul(self.mod(row, 2.0), stagger)
        if row_jitter is not None:
            shift = self.add(shift, self.mul(self.white(row, 7.0, 3), row_jitter))
        xx = self.add(self.mul(u, cols), shift)
        col = self.mod(self.floor(xx), cols)
        row = self.mod(row, rows)
        fx = self.frac(xx)
        # Distancia al borde en unidades de mosaico, para que la junta tenga el
        # mismo ancho en las dos direcciones.
        ex = self.mul(self.mn(fx, self.inv(fx)), 1.0 / cols)
        ey = self.mul(self.mn(fy, self.inv(fy)), 1.0 / rows)
        return {"col": col, "row": row, "fx": fx, "fy": fy, "edge": self.mn(ex, ey), "ex": ex, "ey": ey}


# Piezas comunes ---------------------------------------------------------------------


def cracks(g, f, width, seed, mask_f=3.0, mask_lo=0.55, mask_hi=0.7):
    """Grietas finas (bordes de voronoi) sólo donde un ruido lo permite. 1 = grieta."""
    edge = g.voronoi(f, feature="DISTANCE_TO_EDGE", seed=seed)
    jitter = g.mul(g.noise(f * 4, 3, seed=seed + 1), width * 0.8)
    line = g.inv(g.ss(g.add(edge, jitter), width * 0.4, width * 1.4))
    mask = g.ss(g.noise(mask_f, 4, seed=seed + 2), mask_lo, mask_hi)
    return g.mul(line, mask)


def streaks(g, seed, across=14.0, along=1.2, lo=0.55, hi=0.75):
    """Chorreaduras verticales (manchas de humedad que bajan)."""
    n = g.noise(across, 4, 0.6, seed=seed, fv=along, dist=0.3)
    return g.ss(n, lo, hi)


def grime(g, f, seed, lo=0.45, hi=0.75, detail=6):
    return g.ss(g.noise(f, detail, 0.6, seed=seed), lo, hi)


def speckle(g, f, seed, amount=0.85):
    """Puntitos (poros, áridos)."""
    return g.ss(g.voronoi(f, seed=seed), 0.25, 0.0) if amount else 0.0


def result(color, height, rough, metal=0.0):
    return {"color": color, "height": height, "rough": rough, "metal": metal}


# Materiales -------------------------------------------------------------------------
# Cada uno devuelve color (albedo), altura 0..1, rugosidad y metal. Strength: cuánto
# relieve tiene la normal; Metal: si se escribe el mapa de metalicidad.

MATERIALS = {}


def material(name, strength=4.0, metal=False):
    def register(fn):
        MATERIALS[name] = {"build": fn, "strength": strength, "metal": metal}
        return fn
    return register


@material("NocturnaTunnelBrick", strength=6.0)
def tunnel_brick(g):
    warp = g.noise(18, 3, seed=1)
    b = g.grid(4, 12, stagger=0.5, warp=warp, warp_amount=0.006)
    rnd = g.white(b["col"], b["row"], 1)
    rnd2 = g.white(b["col"], b["row"], 2)
    # Ladrillo con canto astillado: el ruido come las esquinas.
    chip = g.mul(g.noise(26, 4, seed=3), 0.012)
    edge = g.sub(b["edge"], chip)
    face = g.ss(edge, 0.004, 0.016)
    mortar = g.inv(g.ss(edge, 0.002, 0.008))
    pits = g.ss(g.voronoi(40, seed=4), 0.18, 0.0)
    surface = g.noise(14, 6, 0.6, seed=5)
    brick = g.ramp(g.add(g.mul(rnd, 0.7), g.mul(surface, 0.3)),
                   [(0.0, "#4a271d"), (0.35, "#6b3627"), (0.7, "#7d4630"), (1.0, "#5a3a2e")])
    brick = g.mixc(g.mul(g.ss(rnd2, 0.85, 0.95), 0.6), brick, "#3a2a24")
    brick = g.mixc(g.mul(pits, 0.35), brick, "#2c1a14")
    mortar_col = g.mixc(g.noise(30, 4, seed=6), "#6f6a60", "#8d877b")
    color = g.mixc(mortar, brick, mortar_col)
    # Salitre: blanco que sale de las juntas y mancha la parte baja.
    salt = g.mul(g.ss(g.noise(5, 6, 0.65, seed=7), 0.55, 0.72), g.inv(g.ss(edge, 0.0, 0.05)))
    color = g.mixc(g.mul(salt, 0.75), color, "#c9c3b2")
    soot = grime(g, 3, 8, 0.4, 0.8)
    color = g.mixc(g.mul(soot, 0.75), color, "#16120f")
    wet = streaks(g, 9, 12, 1.0, 0.52, 0.72)
    color = g.scale_color(color, g.lerp(wet, 1.0, 0.6))
    height = g.add(g.mul(face, g.add(0.62, g.mul(rnd, 0.08))), g.mul(surface, 0.12))
    height = g.sub(height, g.mul(pits, 0.08))
    height = g.add(height, g.mul(mortar, g.mul(g.noise(40, 3, seed=10), 0.08)))
    rough = g.lerp(mortar, 0.82, 0.95)
    rough = g.lerp(wet, rough, 0.32)
    return result(color, g.clamp(height), g.clamp(rough))


@material("NocturnaWetConcrete", strength=3.0)
def wet_concrete(g):
    base = g.noise(4, 7, 0.62, seed=11)
    fine = g.noise(60, 3, 0.5, seed=12)
    color = g.ramp(g.add(g.mul(base, 0.75), g.mul(fine, 0.25)),
                   [(0.0, "#46453f"), (0.45, "#5e5c55"), (0.75, "#6f6c63"), (1.0, "#57544c")])
    aggregate = g.ss(g.voronoi(70, seed=13), 0.2, 0.05)
    color = g.mixc(g.mul(aggregate, 0.35), color, "#8a867b")
    crack = cracks(g, 3.5, 0.010, 14, 2.5, 0.5, 0.65)
    color = g.mixc(g.mul(crack, 0.9), color, "#1c1b18")
    oil = grime(g, 2.2, 15, 0.55, 0.8)
    color = g.mixc(g.mul(oil, 0.55), color, "#25231f")
    # Partes mojadas: más oscuras y casi espejadas.
    wet = g.ss(g.noise(2.6, 5, 0.55, seed=16), 0.52, 0.6)
    color = g.scale_color(color, g.lerp(wet, 1.0, 0.55))
    height = g.add(g.mul(base, 0.25), g.mul(fine, 0.18))
    height = g.add(height, g.mul(aggregate, 0.12))
    height = g.sub(height, g.mul(crack, 0.35))
    height = g.sub(height, g.mul(wet, 0.06))
    rough = g.lerp(fine, 0.78, 0.92)
    rough = g.lerp(wet, rough, g.add(0.06, g.mul(fine, 0.1)))
    return result(color, g.clamp(g.add(height, 0.3)), g.clamp(rough))


@material("NocturnaStainedConcrete", strength=2.5)
def stained_concrete(g):
    base = g.noise(5, 7, 0.6, seed=21)
    fine = g.noise(55, 3, 0.5, seed=22)
    color = g.ramp(g.add(g.mul(base, 0.8), g.mul(fine, 0.2)),
                   [(0.0, "#55534d"), (0.5, "#6c6962"), (1.0, "#7b776e")])
    # Encofrado: juntas de tablas horizontales cada 1/6.
    board = g.frac(g.mul(g.v, 6.0))
    seam = g.inv(g.ss(g.mn(board, g.inv(board)), 0.0, 0.02))
    color = g.mixc(g.mul(seam, 0.4), color, "#3c3a35")
    # Aureolas de goteras: anillos del contorno de un ruido.
    field = g.noise(1.6, 5, 0.55, seed=23, dist=0.2)
    ring = g.inv(g.ss(g.absv(g.sub(field, 0.5)), 0.0, 0.012))
    inside = g.ss(field, 0.5, 0.58)
    color = g.mixc(g.mul(inside, 0.45), color, "#6e5a3e")
    color = g.mixc(g.mul(ring, 0.7), color, "#4a3624")
    rust = g.mul(streaks(g, 24, 16, 1.4, 0.6, 0.78), g.ss(g.noise(3, 3, seed=25), 0.5, 0.65))
    color = g.mixc(g.mul(rust, 0.75), color, "#6a3a1e")
    soot = grime(g, 3, 26, 0.5, 0.85)
    color = g.mixc(g.mul(soot, 0.5), color, "#1e1c19")
    height = g.add(g.mul(base, 0.25), g.mul(fine, 0.2))
    height = g.sub(height, g.mul(seam, 0.15))
    height = g.add(height, g.mul(g.ss(g.voronoi(45, seed=27), 0.15, 0.0), -0.12))
    rough = g.lerp(inside, 0.9, 0.8)
    return result(color, g.clamp(g.add(height, 0.4)), g.clamp(rough))


@material("NocturnaPeelingPlaster", strength=5.0)
def peeling_plaster(g):
    fine = g.noise(45, 4, 0.55, seed=31)
    plaster = g.ramp(g.add(g.mul(g.noise(6, 5, seed=32), 0.7), g.mul(fine, 0.3)),
                     [(0.0, "#857c6c"), (0.6, "#a69c88"), (1.0, "#b8ae98")])
    paint = g.ramp(g.noise(3, 5, 0.5, seed=33), [(0.0, "#4f6a58"), (0.5, "#5f7d68"), (1.0, "#6f8b74")])
    paint = g.mixc(g.mul(fine, 0.2), paint, "#8aa08e")
    # Donde la pintura se levantó: máscara de ruido con un borde claro levantado.
    field = g.add(g.noise(3.2, 6, 0.62, seed=34, dist=0.4), g.mul(g.noise(18, 3, seed=35), 0.12))
    peeled = g.ss(field, 0.6, 0.615)
    lip = g.mul(g.ss(field, 0.56, 0.6), g.inv(peeled))
    color = g.mixc(peeled, paint, plaster)
    color = g.mixc(g.mul(lip, 0.5), color, "#c7cdbb")
    deep = g.mul(peeled, g.ss(field, 0.72, 0.78))
    color = g.mixc(g.mul(deep, 0.7), color, "#5d5246")
    stain = streaks(g, 36, 10, 1.1, 0.55, 0.75)
    color = g.mixc(g.mul(stain, 0.55), color, "#3f3a2c")
    dirt = grime(g, 4, 37, 0.5, 0.85)
    color = g.mixc(g.mul(dirt, 0.4), color, "#2a2620")
    crack = cracks(g, 4, 0.006, 38, 3, 0.5, 0.62)
    color = g.mixc(g.mul(crack, 0.85), color, "#221e19")
    height = g.add(g.lerp(peeled, 0.6, 0.42), g.mul(lip, 0.12))
    height = g.sub(height, g.mul(deep, 0.08))
    height = g.add(height, g.mul(fine, 0.06))
    height = g.sub(height, g.mul(crack, 0.25))
    rough = g.lerp(peeled, 0.5, 0.92)
    rough = g.lerp(g.mul(stain, 0.5), rough, 0.35)
    return result(color, g.clamp(height), g.clamp(rough))


@material("NocturnaDirtyTiles", strength=5.0)
def dirty_tiles(g):
    t = g.grid(8, 8)
    rnd = g.white(t["col"], t["row"], 41)
    rnd2 = g.white(t["col"], t["row"], 42)
    face = g.ss(t["edge"], 0.003, 0.012)
    grout = g.inv(g.ss(t["edge"], 0.002, 0.005))
    tile = g.ramp(g.add(g.mul(rnd, 0.6), g.mul(g.noise(8, 4, seed=43), 0.4)),
                  [(0.0, "#a7a497"), (0.5, "#bbb8aa"), (1.0, "#c9c5b4")])
    # Mugre que se junta cerca de las juntas.
    near = g.inv(g.ss(t["edge"], 0.0, 0.03))
    dirt = g.mul(near, g.noise(20, 4, seed=44))
    tile = g.mixc(dirt, tile, "#4d473b")
    stains = grime(g, 3, 45, 0.45, 0.75)
    tile = g.mixc(g.mul(stains, 0.75), tile, "#5e5240")
    # Algunas baldosas rajadas.
    cracked = g.ss(rnd2, 0.82, 0.84)
    crack_line = g.inv(g.ss(g.voronoi(10, feature="DISTANCE_TO_EDGE", seed=46), 0.0, 0.006))
    crack = g.mul(crack_line, cracked)
    tile = g.mixc(g.mul(crack, 0.9), tile, "#2b2822")
    grout_col = g.mixc(g.noise(30, 3, seed=47), "#24221e", "#3a362f")
    color = g.mixc(grout, tile, grout_col)
    color = g.mixc(g.mul(grime(g, 1.6, 48, 0.45, 0.85), 0.55), color, "#2a261f")
    height = g.add(g.mul(face, 0.6), g.mul(g.noise(25, 3, seed=49), 0.03))
    height = g.sub(height, g.mul(crack, 0.25))
    height = g.add(height, 0.25)
    rough = g.lerp(g.add(g.mul(dirt, 0.8), g.mul(stains, 0.6)), 0.18, 0.6)
    rough = g.lerp(grout, rough, 0.95)
    return result(color, g.clamp(height), g.clamp(rough))


@material("NocturnaStainedPlaster", strength=2.5)
def stained_plaster(g):
    fine = g.noise(50, 4, 0.55, seed=51)
    color = g.ramp(g.add(g.mul(g.noise(5, 5, seed=52), 0.7), g.mul(fine, 0.3)),
                   [(0.0, "#9b9484"), (0.6, "#b3ac9a"), (1.0, "#c0b8a5")])
    field = g.noise(1.8, 5, 0.55, seed=53, dist=0.2)
    inside = g.ss(field, 0.5, 0.57)
    ring = g.inv(g.ss(g.absv(g.sub(field, 0.51)), 0.0, 0.012))
    ring2 = g.inv(g.ss(g.absv(g.sub(field, 0.58)), 0.0, 0.008))
    color = g.mixc(g.mul(inside, 0.5), color, "#8d7650")
    color = g.mixc(g.mul(g.add(ring, g.mul(ring2, 0.6)), 0.7), color, "#5e4628")
    # Moho: puntos oscuros en racimos, sólo cerca de la humedad.
    mold = g.mul(g.ss(g.voronoi(35, seed=54), 0.3, 0.05), g.ss(field, 0.55, 0.7))
    mold = g.mul(mold, g.ss(g.noise(8, 3, seed=55), 0.45, 0.6))
    color = g.mixc(g.mul(mold, 0.85), color, "#262b20")
    dirt = grime(g, 3, 56, 0.45, 0.85)
    color = g.mixc(g.mul(dirt, 0.5), color, "#3b352b")
    crack = cracks(g, 3, 0.005, 57, 2.5, 0.55, 0.65)
    color = g.mixc(g.mul(crack, 0.8), color, "#2b261f")
    height = g.add(g.mul(fine, 0.15), g.mul(g.noise(9, 4, seed=58), 0.1))
    height = g.add(height, g.mul(inside, 0.04))
    height = g.sub(height, g.mul(crack, 0.2))
    height = g.add(height, g.mul(mold, 0.05))
    rough = g.lerp(inside, 0.93, 0.85)
    return result(color, g.clamp(g.add(height, 0.45)), g.clamp(rough))


@material("NocturnaFleshWall", strength=6.0)
def flesh_wall(g):
    # Azulejo de abajo, tapado por tejido que crece.
    t = g.grid(6, 6)
    tile_face = g.ss(t["edge"], 0.002, 0.01)
    tile = g.mixc(g.noise(9, 3, seed=61), "#69725f", "#7f8873")
    tile = g.mixc(g.mul(grime(g, 3, 69, 0.4, 0.8), 0.7), tile, "#2e2a20")
    tile = g.mixc(g.inv(tile_face), tile, "#2c2a24")
    cover = g.ss(g.noise(2.4, 6, 0.6, seed=62, dist=0.5), 0.42, 0.52)
    lumps = g.voronoi(9, feature="SMOOTH_F1", seed=63)
    bulge = g.inv(g.ss(lumps, 0.0, 0.7))
    flesh = g.ramp(g.add(g.mul(bulge, 0.6), g.mul(g.noise(14, 5, seed=64), 0.4)),
                   [(0.0, "#3e1418"), (0.4, "#6a2628"), (0.75, "#8f4440"), (1.0, "#a8605a")])
    veins = g.inv(g.ss(g.voronoi(6, feature="DISTANCE_TO_EDGE", seed=65), 0.0, 0.03))
    veins_small = g.inv(g.ss(g.voronoi(18, feature="DISTANCE_TO_EDGE", seed=66), 0.0, 0.02))
    vein = g.mx(veins, g.mul(veins_small, 0.6))
    flesh = g.mixc(g.mul(vein, 0.8), flesh, "#2a0c16")
    # Bordes del tejido: amarillento, como fibra seca.
    rim = g.mul(g.ss(g.noise(2.4, 6, 0.6, seed=62, dist=0.5), 0.38, 0.44), g.inv(cover))
    tile = g.mixc(g.mul(rim, 0.7), tile, "#7a6a3e")
    color = g.mixc(cover, tile, flesh)
    height = g.lerp(cover, g.add(g.mul(tile_face, 0.3), 0.2), g.add(0.55, g.mul(bulge, 0.35)))
    height = g.add(height, g.mul(g.mul(vein, cover), 0.08))
    rough = g.lerp(cover, 0.3, g.add(0.12, g.mul(vein, 0.25)))
    return result(color, g.clamp(height), g.clamp(rough))


@material("NocturnaStainedSlate", strength=3.5)
def stained_slate(g):
    t = g.grid(2, 2)
    rnd = g.white(t["col"], t["row"], 71)
    seam = g.inv(g.ss(t["edge"], 0.001, 0.004))
    layers = g.noise(3, 8, 0.6, seed=72, fv=5, dist=0.3)
    color = g.ramp(g.add(g.mul(layers, 0.7), g.mul(rnd, 0.3)),
                   [(0.0, "#26292a"), (0.5, "#363a3a"), (1.0, "#454846")])
    # Fluidos secos: manchas con borde marcado, apenas brillantes.
    field = g.noise(2.6, 5, 0.55, seed=73, dist=0.3)
    stain = g.ss(field, 0.52, 0.55)
    edge_ring = g.inv(g.ss(g.absv(g.sub(field, 0.535)), 0.0, 0.01))
    stain_col = g.mixc(g.noise(6, 3, seed=74), "#2c2416", "#3a3a22")
    color = g.mixc(g.mul(stain, 0.8), color, stain_col)
    color = g.mixc(g.mul(edge_ring, 0.8), color, "#1b160e")
    scratch = g.ss(g.noise(1.5, 2, seed=75, fv=90, kind="RIDGED_MULTIFRACTAL", offset=1.0, gain=1.0), 0.9, 0.98)
    color = g.mixc(g.mul(scratch, 0.35), color, "#6a6c68")
    color = g.mixc(seam, color, "#121313")
    height = g.add(g.mul(layers, 0.2), 0.5)
    height = g.sub(height, g.mul(seam, 0.4))
    height = g.add(height, g.mul(stain, 0.03))
    height = g.sub(height, g.mul(scratch, 0.06))
    rough = g.lerp(layers, 0.55, 0.7)
    rough = g.lerp(stain, rough, 0.3)
    return result(color, g.clamp(height), g.clamp(rough))


@material("NocturnaFleshCeiling", strength=6.0)
def flesh_ceiling(g):
    base = g.noise(3, 6, 0.6, seed=81, dist=0.6)
    membrane = g.ramp(base, [(0.0, "#3a1418"), (0.5, "#5c2428"), (0.8, "#7c3c3a"), (1.0, "#93524c")])
    # Venas: varias escalas de bordes de voronoi deformados.
    warp_u = g.add(g.u, g.mul(g.sub(g.noise(5, 3, seed=82), 0.5), 0.05))
    v1 = g.inv(g.ss(g.voronoi(4, feature="DISTANCE_TO_EDGE", seed=83, u=warp_u), 0.0, 0.04))
    v2 = g.inv(g.ss(g.voronoi(11, feature="DISTANCE_TO_EDGE", seed=84, u=warp_u), 0.0, 0.025))
    v3 = g.mul(g.inv(g.ss(g.voronoi(26, feature="DISTANCE_TO_EDGE", seed=85), 0.0, 0.02)),
               g.ss(g.noise(6, 3, seed=86), 0.45, 0.6))
    vein = g.mx(v1, g.mx(g.mul(v2, 0.75), g.mul(v3, 0.5)))
    color = g.mixc(g.mul(vein, 0.85), membrane, "#1e0812")
    thin = g.ss(g.voronoi(5, feature="SMOOTH_F1", seed=87), 0.35, 0.05)
    color = g.mixc(g.mul(thin, 0.35), color, "#b0706a")
    height = g.add(g.mul(base, 0.35), g.mul(vein, 0.3))
    height = g.add(height, g.mul(g.noise(30, 3, seed=88), 0.05))
    rough = g.lerp(vein, g.add(0.15, g.mul(base, 0.15)), 0.4)
    return result(color, g.clamp(g.add(height, 0.2)), g.clamp(rough))


@material("NocturnaScratchedSteel", strength=4.0, metal=True)
def scratched_steel(g):
    # Paneles de chapa: dos de ancho por uno de alto, con remaches en el borde.
    t = g.grid(2, 1)
    rnd = g.white(t["col"], t["row"], 91)
    seam = g.inv(g.ss(t["edge"], 0.002, 0.006))
    near = g.inv(g.ss(t["edge"], 0.0, 0.05))
    # Remaches: puntos cada 1/16 a lo largo del borde, a 0.02 de la junta.
    rx = g.frac(g.mul(g.v, 16.0))
    ry = g.frac(g.mul(g.u, 16.0))
    dx = g.sub(t["ex"], 0.018)
    dy = g.sub(t["ey"], 0.018)
    rivet_a = g.inv(g.ss(g.add(g.mul(dx, dx), g.mul(g.mul(g.sub(rx, 0.5), 0.0625), g.mul(g.sub(rx, 0.5), 0.0625))), 0.0, 0.00003))
    rivet_b = g.inv(g.ss(g.add(g.mul(dy, dy), g.mul(g.mul(g.sub(ry, 0.5), 0.0625), g.mul(g.sub(ry, 0.5), 0.0625))), 0.0, 0.00003))
    rivet = g.mx(rivet_a, rivet_b)
    paint = g.ramp(g.add(g.mul(rnd, 0.5), g.mul(g.noise(3, 3, seed=92), 0.5)),
                   [(0.0, "#3f4850"), (0.5, "#4b555e"), (1.0, "#57616a")])
    # Rayones: líneas finas en dos direcciones.
    s1 = g.ss(g.noise(2, 2, seed=93, fv=70, kind="RIDGED_MULTIFRACTAL", offset=1.0), 0.96, 0.995)
    s2 = g.ss(g.noise(55, 2, seed=94, fv=3, kind="RIDGED_MULTIFRACTAL", offset=1.0), 0.965, 0.998)
    scratch = g.mx(s1, s2)
    scratch = g.mul(scratch, g.ss(g.noise(3, 3, seed=96), 0.4, 0.6))
    chipped = g.ss(g.add(g.noise(6, 6, 0.6, seed=97), g.mul(near, 0.25)), 0.75, 0.77)
    rust = g.mul(g.ss(g.add(g.noise(5, 6, 0.65, seed=98), g.mul(near, 0.35)), 0.66, 0.8), 1.0)
    bare = g.mx(scratch, chipped)
    steel = g.mixc(g.noise(40, 3, seed=99, fv=4), "#7a7c7c", "#929493")
    paint = g.mixc(g.mul(grime(g, 2.5, 103, 0.4, 0.8), 0.6), paint, "#23272a")
    color = g.mixc(bare, paint, steel)
    rust_col = g.ramp(g.noise(20, 4, seed=100), [(0.0, "#3a1d0e"), (0.5, "#5e2f15"), (1.0, "#7a4420")])
    color = g.mixc(rust, color, rust_col)
    color = g.mixc(seam, color, "#16181a")
    color = g.mixc(g.mul(rivet, 0.5), color, "#3a3f44")
    streak = streaks(g, 101, 14, 1.0, 0.6, 0.78)
    color = g.mixc(g.mul(streak, 0.5), color, "#3a2416")
    height = g.add(0.55, g.mul(rivet, 0.25))
    height = g.sub(height, g.mul(seam, 0.4))
    height = g.sub(height, g.mul(bare, 0.06))
    height = g.add(height, g.mul(rust, g.mul(g.noise(40, 4, seed=102), 0.12)))
    rough = g.lerp(bare, g.add(0.45, g.mul(rnd, 0.1)), 0.28)
    rough = g.lerp(rust, rough, 0.88)
    metal = g.lerp(bare, 0.35, 1.0)
    metal = g.lerp(rust, metal, 0.0)
    return result(color, g.clamp(height), g.clamp(rough), g.clamp(metal))


@material("NocturnaWornPlate", strength=6.0, metal=True)
def worn_plate(g):
    # Chapa semillada: rombos alargados alternando ±45° en una grilla de 10x10.
    n = 10.0
    t = g.grid(n, n)
    flip = g.mod(g.add(t["col"], t["row"]), 2.0)
    x = g.sub(t["fx"], 0.5)
    y = g.sub(t["fy"], 0.5)
    a = g.mul(g.add(x, y), 0.7071)
    b = g.mul(g.sub(x, y), 0.7071)
    along = g.lerp(flip, a, b)
    across = g.lerp(flip, b, a)
    shape = g.add(g.mul(g.absv(along), 1.0), g.mul(g.absv(across), 3.2))
    bump = g.inv(g.ss(shape, 0.28, 0.42))
    top = g.inv(g.ss(shape, 0.0, 0.3))
    wear = g.ss(g.noise(2, 5, 0.55, seed=111), 0.4, 0.7)
    base = g.mixc(g.noise(18, 4, seed=112), "#5c5f62", "#717477")
    color = g.mixc(g.mul(g.mul(top, wear), 0.9), base, "#b4b5b3")
    dirt = g.mul(g.inv(bump), g.ss(g.noise(6, 5, seed=113), 0.35, 0.6))
    color = g.mixc(g.mul(dirt, 0.8), color, "#2a2723")
    rust = g.ss(g.noise(3.5, 6, 0.65, seed=114), 0.64, 0.74)
    rust_col = g.ramp(g.noise(25, 4, seed=115), [(0.0, "#3a1c0d"), (0.6, "#653318"), (1.0, "#80461f")])
    color = g.mixc(rust, color, rust_col)
    scratch = g.ss(g.noise(2, 2, seed=116, fv=60, kind="RIDGED_MULTIFRACTAL", offset=1.0), 0.94, 0.99)
    color = g.mixc(g.mul(scratch, 0.5), color, "#9a9b99")
    height = g.add(g.mul(bump, 0.45), 0.3)
    height = g.add(height, g.mul(rust, g.mul(g.noise(50, 3, seed=117), 0.1)))
    rough = g.lerp(g.mul(top, wear), 0.55, 0.22)
    rough = g.lerp(dirt, rough, 0.85)
    rough = g.lerp(rust, rough, 0.9)
    metal = g.lerp(dirt, 1.0, 0.4)
    metal = g.lerp(rust, metal, 0.0)
    return result(color, g.clamp(height), g.clamp(rough), g.clamp(metal))


@material("NocturnaTornWallpaper", strength=4.0)
def torn_wallpaper(g):
    # Motivo floral: rosetas en una grilla 4x4 desplazada, con rayas verticales.
    t = g.grid(4, 4, stagger=0.5)
    x = g.sub(t["fx"], 0.5)
    y = g.sub(t["fy"], 0.5)
    r = g.pw(g.add(g.mul(x, x), g.mul(y, y)), 0.5)
    angle = g.m("ARCTAN2", y, x)
    petals = g.add(0.2, g.mul(g.cos(g.mul(angle, 5.0)), 0.07))
    flower = g.inv(g.ss(g.sub(r, petals), -0.01, 0.01))
    heart = g.inv(g.ss(r, 0.05, 0.065))
    leaf_angle = g.cos(g.mul(g.sub(angle, 0.785), 2.0))
    leaf = g.mul(g.inv(g.ss(g.absv(g.sub(r, 0.33)), 0.02, 0.05)), g.ss(leaf_angle, 0.7, 0.9))
    stripe = g.ss(g.sin(g.mul(g.u, TAU * 16)), 0.85, 0.95)
    paper = g.mixc(g.noise(4, 4, seed=121), "#8a7660", "#9b8770")
    paper = g.mixc(g.mul(stripe, 0.4), paper, "#76644f")
    paper = g.mixc(g.mul(leaf, 0.7), paper, "#5d5f45")
    paper = g.mixc(g.mul(flower, 0.75), paper, "#7e4e46")
    paper = g.mixc(g.mul(heart, 0.7), paper, "#5a3a2c")
    # Desteñido: zonas pálidas.
    fade = g.ss(g.noise(2.5, 5, seed=122), 0.45, 0.75)
    paper = g.mixc(g.mul(fade, 0.45), paper, "#b3a68e")
    # Arrancado: se ve el revoque, con el borde blanco del papel roto.
    field = g.add(g.noise(2.2, 6, 0.65, seed=123, dist=0.3), g.mul(g.noise(25, 3, seed=124), 0.08))
    torn = g.ss(field, 0.63, 0.64)
    rim = g.mul(g.ss(field, 0.6, 0.63), g.inv(torn))
    plaster = g.mixc(g.noise(12, 4, seed=125), "#857c6a", "#a39883")
    color = g.mixc(torn, paper, plaster)
    color = g.mixc(g.mul(rim, 0.85), color, "#cfc4ab")
    damp = streaks(g, 126, 9, 1.0, 0.55, 0.78)
    color = g.mixc(g.mul(damp, 0.55), color, "#4b3a26")
    dirt = grime(g, 3, 127, 0.5, 0.85)
    color = g.mixc(g.mul(dirt, 0.4), color, "#2a231b")
    height = g.lerp(torn, 0.55, 0.38)
    height = g.add(height, g.mul(rim, 0.1))
    height = g.add(height, g.mul(g.noise(60, 3, seed=128), 0.03))
    height = g.add(height, g.mul(g.mul(flower, g.inv(torn)), 0.02))
    rough = g.lerp(torn, 0.82, 0.93)
    return result(color, g.clamp(height), g.clamp(rough))


@material("NocturnaScuffedOak", strength=4.5)
def scuffed_oak(g):
    # Tablas: 8 filas por mosaico, dos tablas por fila con corte al azar por fila.
    t = g.grid(2, 8, row_jitter=1.0)
    rnd = g.white(t["col"], t["row"], 131)
    gap = g.inv(g.ss(t["edge"], 0.0008, 0.003))
    # Veta: ruido muy estirado a lo largo de la tabla, desplazado por tabla.
    vv = g.add(g.v, g.mul(rnd, 0.37))
    grain = g.noise(3, 6, 0.6, seed=132, fv=60, dist=0.8, v=vv)
    rings = g.ss(g.sin(g.mul(g.add(g.mul(grain, 6.0), g.mul(g.v, 40.0)), 3.0)), 0.3, 1.0)
    wood = g.ramp(g.add(g.mul(grain, 0.55), g.mul(rnd, 0.45)),
                  [(0.0, "#4e341f"), (0.4, "#6b4a2d"), (0.75, "#81603b"), (1.0, "#5d4128")])
    wood = g.mixc(g.mul(rings, 0.3), wood, "#3f2a18")
    # Marcas de arrastre y polvo en las juntas.
    scuff = g.mul(g.ss(g.noise(3, 2, seed=133, fv=40, kind="RIDGED_MULTIFRACTAL", offset=1.0), 0.85, 0.97),
                  g.ss(g.noise(2.5, 3, seed=134), 0.45, 0.6))
    wood = g.mixc(g.mul(scuff, 0.55), wood, "#a48a68")
    worn = g.ss(g.noise(1.8, 4, seed=135), 0.55, 0.75)
    wood = g.mixc(g.mul(worn, 0.35), wood, "#93795a")
    dust = g.inv(g.ss(t["edge"], 0.0, 0.006))
    wood = g.mixc(g.mul(dust, 0.6), wood, "#7d7568")
    color = g.mixc(gap, wood, "#1a120b")
    color = g.mixc(g.mul(grime(g, 2, 136, 0.55, 0.85), 0.35), color, "#2a2017")
    height = g.add(0.6, g.mul(grain, 0.06))
    height = g.sub(height, g.mul(gap, 0.45))
    height = g.sub(height, g.mul(scuff, 0.03))
    height = g.add(height, g.mul(g.sub(rnd, 0.5), 0.04))
    rough = g.lerp(worn, 0.5, 0.7)
    rough = g.lerp(scuff, rough, 0.8)
    rough = g.lerp(gap, rough, 0.95)
    return result(color, g.clamp(height), g.clamp(rough))


# Utilería: mapas casi neutros, los tiñe el color de cada pieza ------------------------


@material("NocturnaRottenWood", strength=5.0)
def rotten_wood(g):
    t = g.grid(1, 4, row_jitter=1.0)
    rnd = g.white(t["col"], t["row"], 141)
    gap = g.inv(g.ss(t["edge"], 0.001, 0.004))
    vv = g.add(g.v, g.mul(rnd, 0.29))
    grain = g.noise(2.5, 6, 0.62, seed=142, fv=45, dist=1.0, v=vv)
    color = g.ramp(g.add(g.mul(grain, 0.7), g.mul(rnd, 0.3)),
                   [(0.0, "#b3a796"), (0.5, "#c6b9a6"), (1.0, "#d4c7b2")])
    split = g.ss(g.noise(2, 3, seed=143, fv=50, kind="RIDGED_MULTIFRACTAL", offset=1.0), 0.965, 0.995)
    color = g.mixc(g.mul(split, 0.6), color, "#3a3128")
    rot = g.ss(g.noise(2.5, 6, 0.65, seed=144, dist=0.4), 0.62, 0.72)
    color = g.mixc(g.mul(rot, 0.75), color, "#4e463c")
    mold = g.mul(rot, g.ss(g.voronoi(30, seed=145), 0.3, 0.05))
    color = g.mixc(g.mul(mold, 0.6), color, "#5a6450")
    color = g.mixc(gap, color, "#2a241e")
    height = g.add(0.55, g.mul(grain, 0.15))
    height = g.sub(height, g.mul(split, 0.3))
    height = g.sub(height, g.mul(rot, g.mul(g.noise(30, 4, seed=146), 0.25)))
    height = g.sub(height, g.mul(gap, 0.4))
    rough = g.lerp(rot, 0.72, 0.95)
    return result(color, g.clamp(height), g.clamp(rough))


@material("NocturnaRustedSheet", strength=5.0, metal=True)
def rusted_sheet(g):
    # Chapa ondulada (cortina) con pintura saltada y óxido.
    ripple = g.mul(g.add(g.sin(g.mul(g.v, TAU * 8)), 1.0), 0.5)
    paint = g.mixc(g.noise(4, 5, seed=151), "#a8aaa6", "#c3c4be")
    field = g.noise(2.8, 7, 0.65, seed=152, dist=0.3)
    rust = g.ss(field, 0.55, 0.62)
    heavy = g.ss(field, 0.68, 0.76)
    rust_col = g.ramp(g.noise(30, 5, seed=153), [(0.0, "#6d4630"), (0.5, "#9a6440"), (1.0, "#b07a52")])
    color = g.mixc(rust, paint, rust_col)
    color = g.mixc(g.mul(heavy, 0.7), color, "#4a2c1c")
    run = g.mul(streaks(g, 154, 18, 1.4, 0.6, 0.8), 0.6)
    color = g.mixc(run, color, "#8a5a3a")
    scratch = g.ss(g.noise(2, 2, seed=155, fv=60, kind="RIDGED_MULTIFRACTAL", offset=1.0), 0.95, 0.99)
    color = g.mixc(g.mul(scratch, g.inv(rust)), color, "#d8d8d4")
    height = g.add(g.mul(ripple, 0.35), 0.3)
    height = g.add(height, g.mul(rust, g.mul(g.noise(45, 4, seed=156), 0.18)))
    height = g.sub(height, g.mul(heavy, 0.08))
    rough = g.lerp(rust, 0.5, 0.92)
    metal = g.lerp(rust, g.lerp(scratch, 0.25, 1.0), 0.0)
    return result(color, g.clamp(height), g.clamp(rough), g.clamp(metal))


@material("NocturnaGrimyMetal", strength=3.0, metal=True)
def grimy_metal(g):
    brushed = g.noise(1.5, 4, 0.6, seed=161, fv=120)
    base = g.mixc(brushed, "#b9bbbb", "#d2d3d1")
    scratch = g.mx(
        g.ss(g.noise(2, 2, seed=162, fv=70, kind="RIDGED_MULTIFRACTAL", offset=1.0), 0.94, 0.99),
        g.ss(g.noise(45, 2, seed=163, fv=4, kind="RIDGED_MULTIFRACTAL", offset=1.0), 0.95, 0.995))
    color = g.mixc(g.mul(scratch, 0.35), base, "#eeeeec")
    dirt = grime(g, 3, 164, 0.45, 0.8)
    color = g.mixc(g.mul(dirt, 0.55), color, "#5c574e")
    prints = g.mul(g.ss(g.voronoi(14, feature="DISTANCE_TO_EDGE", seed=165), 0.0, 0.04), g.ss(g.noise(4, 3, seed=166), 0.6, 0.7))
    dents = g.ss(g.voronoi(5, feature="SMOOTH_F1", seed=167), 0.0, 0.5)
    rust = g.ss(g.noise(4, 6, 0.65, seed=168), 0.7, 0.78)
    color = g.mixc(rust, color, "#7a5238")
    height = g.add(g.mul(dents, 0.25), 0.45)
    height = g.sub(height, g.mul(scratch, 0.05))
    height = g.add(height, g.mul(rust, g.mul(g.noise(40, 3, seed=169), 0.1)))
    rough = g.lerp(dirt, g.add(0.35, g.mul(brushed, 0.1)), 0.8)
    rough = g.lerp(g.mul(prints, 0.6), rough, 0.15)
    rough = g.lerp(rust, rough, 0.9)
    metal = g.lerp(dirt, 0.55, 0.2)
    metal = g.lerp(scratch, metal, 1.0)
    metal = g.lerp(rust, metal, 0.0)
    return result(color, g.clamp(height), g.clamp(rough), g.clamp(metal))


@material("NocturnaWornFabric", strength=3.0)
def worn_fabric(g):
    # Tejido: trama y urdimbre con sinusoides enteras.
    wu = g.sin(g.mul(g.u, TAU * 96))
    wv = g.sin(g.mul(g.v, TAU * 96))
    checker = g.sin(g.mul(g.add(g.u, g.v), TAU * 48))
    weave = g.mul(g.add(g.mul(g.lerp(g.ss(checker, -0.2, 0.2), wu, wv), 0.5), 0.5), 1.0)
    fibers = g.noise(6, 4, 0.6, seed=171, fv=40)
    color = g.mixc(g.add(g.mul(weave, 0.5), g.mul(fibers, 0.5)), "#b4ab9e", "#d1c8ba")
    thin = g.ss(g.noise(2.5, 5, seed=172), 0.62, 0.75)
    color = g.mixc(g.mul(thin, 0.5), color, "#e2dccf")
    stain = g.ss(g.noise(2.2, 5, 0.6, seed=173, dist=0.3), 0.6, 0.66)
    ring = g.inv(g.ss(g.absv(g.sub(g.noise(2.2, 5, 0.6, seed=173, dist=0.3), 0.63)), 0.0, 0.012))
    color = g.mixc(g.mul(stain, 0.45), color, "#8e7a5c")
    color = g.mixc(g.mul(ring, 0.5), color, "#6a5a40")
    dirt = grime(g, 3, 174, 0.5, 0.85)
    color = g.mixc(g.mul(dirt, 0.45), color, "#4c463c")
    height = g.add(g.mul(weave, 0.35), g.mul(fibers, 0.15))
    height = g.sub(height, g.mul(thin, 0.1))
    rough = g.lerp(stain, 0.95, 0.8)
    return result(color, g.clamp(g.add(height, 0.3)), g.clamp(rough))


@material("NocturnaBookCloth", strength=4.0)
def book_cloth(g):
    # Cuero/tela de tapas: celdas de cuero cuarteado, roces claros.
    cells = g.voronoi(28, feature="DISTANCE_TO_EDGE", seed=181)
    crease = g.inv(g.ss(cells, 0.0, 0.05))
    grain = g.noise(80, 3, 0.5, seed=182)
    color = g.mixc(g.add(g.mul(grain, 0.6), g.mul(g.noise(5, 4, seed=183), 0.4)), "#a99c8c", "#c8bba9")
    color = g.mixc(g.mul(crease, 0.6), color, "#5c5248")
    scuff = g.ss(g.noise(3, 5, seed=184), 0.6, 0.75)
    color = g.mixc(g.mul(scuff, 0.6), color, "#ddd2c0")
    big = cracks(g, 4, 0.01, 185, 2.5, 0.5, 0.62)
    color = g.mixc(g.mul(big, 0.8), color, "#3a332b")
    dirt = grime(g, 3, 186, 0.5, 0.85)
    color = g.mixc(g.mul(dirt, 0.4), color, "#4b443a")
    height = g.add(0.55, g.mul(grain, 0.08))
    height = g.sub(height, g.mul(crease, 0.18))
    height = g.sub(height, g.mul(big, 0.3))
    rough = g.lerp(scuff, 0.55, 0.85)
    return result(color, g.clamp(height), g.clamp(rough))


@material("NocturnaDirtyGlass", strength=1.0)
def dirty_glass(g):
    smudge = g.ss(g.noise(3, 6, 0.6, seed=191, dist=0.5), 0.45, 0.75)
    drips = streaks(g, 192, 22, 1.5, 0.58, 0.8)
    dust = g.ss(g.noise(40, 3, seed=193), 0.5, 0.7)
    dirt = g.clamp(g.add(g.mul(smudge, 0.7), g.add(g.mul(drips, 0.6), g.mul(dust, 0.2))))
    color = g.mixc(dirt, "#f2f2ee", "#8f8a7e")
    scratch = g.ss(g.noise(2, 2, seed=194, fv=70, kind="RIDGED_MULTIFRACTAL", offset=1.0), 0.95, 0.995)
    height = g.add(0.5, g.mul(dirt, 0.05))
    height = g.sub(height, g.mul(scratch, 0.05))
    rough = g.lerp(dirt, 0.04, 0.7)
    rough = g.lerp(scratch, rough, 0.4)
    return result(color, g.clamp(height), g.clamp(rough))


@material("NocturnaAgedPaper", strength=2.0)
def aged_paper(g):
    fibers = g.noise(8, 5, 0.6, seed=201, fv=30, dist=0.5)
    color = g.mixc(g.add(g.mul(fibers, 0.6), g.mul(g.noise(3, 4, seed=202), 0.4)), "#c7bca4", "#ddd3bd")
    # Manchas de óxido del papel viejo (foxing) y bordes amarillos de humedad.
    fox = g.mul(g.ss(g.voronoi(20, seed=203), 0.22, 0.05), g.ss(g.noise(4, 3, seed=204), 0.5, 0.62))
    color = g.mixc(g.mul(fox, 0.75), color, "#8a6236")
    field = g.noise(2, 5, 0.55, seed=205)
    tide = g.inv(g.ss(g.absv(g.sub(field, 0.62)), 0.0, 0.015))
    color = g.mixc(g.mul(g.ss(field, 0.62, 0.66), 0.35), color, "#b39462")
    color = g.mixc(g.mul(tide, 0.55), color, "#8a6a3c")
    fold = g.inv(g.ss(g.voronoi(3, feature="DISTANCE_TO_EDGE", seed=206), 0.0, 0.006))
    color = g.mixc(g.mul(fold, 0.22), color, "#8b8270")
    dirt = grime(g, 3, 207, 0.5, 0.85)
    color = g.mixc(g.mul(dirt, 0.35), color, "#5a5040")
    height = g.add(0.5, g.mul(fibers, 0.1))
    height = g.sub(height, g.mul(fold, 0.15))
    rough = g.lerp(fibers, 0.85, 0.95)
    return result(color, g.clamp(height), g.clamp(rough))


# Horneado ---------------------------------------------------------------------------


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = False
    scene.cycles.use_adaptive_sampling = False
    scene.render.bake.margin = 0
    scene.render.bake.use_clear = True
    scene.view_settings.view_transform = "Standard"
    return scene


def bake_plane():
    bpy.ops.mesh.primitive_plane_add(size=2)
    plane = bpy.context.active_object
    # El plano por defecto ya trae UV 0..1 en las cuatro esquinas.
    return plane


def bake_pass(plane, material_data, channel):
    material = bpy.data.materials.new("Bake_" + channel)
    material.use_nodes = True
    g = Graph(material)
    built = material_data["build"](g)
    emission = g.node("ShaderNodeEmission")
    emission.inputs["Strength"].default_value = 1.0
    if channel == "color":
        g.put(emission.inputs["Color"], built["color"])
    else:
        combine = g.node("ShaderNodeCombineColor")
        g.put(combine.inputs[0], built["height"])
        g.put(combine.inputs[1], built["rough"])
        g.put(combine.inputs[2], built["metal"])
        g.link(combine.outputs[0], emission.inputs["Color"])
    out = g.node("ShaderNodeOutputMaterial")
    g.link(emission.outputs[0], out.inputs["Surface"])
    image = bpy.data.images.new("bake_" + channel, SIZE, SIZE, alpha=False, float_buffer=True)
    image.colorspace_settings.name = "Non-Color"
    target = g.node("ShaderNodeTexImage")
    target.image = image
    g.nt.nodes.active = target
    plane.data.materials.clear()
    plane.data.materials.append(material)
    bpy.ops.object.select_all(action="DESELECT")
    plane.select_set(True)
    bpy.context.view_layer.objects.active = plane
    bpy.ops.object.bake(type="EMIT")
    pixels = np.empty(SIZE * SIZE * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    pixels = pixels.reshape(SIZE, SIZE, 4)[:, :, :3].copy()
    bpy.data.images.remove(image)
    bpy.data.materials.remove(material)
    return pixels


def linear_to_srgb(x):
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def normal_from_height(height, strength):
    """Normal tangente OpenGL (Y+) de una altura enroscable. Fila 0 = v = 0 (abajo)."""
    du = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dv = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    scale = strength * SIZE / 256.0
    nx = -du * scale
    ny = -dv * scale
    nz = np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / length, ny / length, nz / length], axis=-1) * 0.5 + 0.5


def to_bytes(array):
    return (np.clip(array, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def write_png(path, array):
    """PNG 8 bits sin dependencias. array: (alto, ancho) gris o (alto, ancho, 3) RGB,
    con la fila 0 abajo (como Blender); se da vuelta para el PNG (fila 0 arriba)."""
    data = to_bytes(array)[::-1]
    gray = data.ndim == 2
    height, width = data.shape[:2]
    channels = 1 if gray else 3
    rows = data.reshape(height, width * channels).astype(np.int16)
    # Filtro "Sub" o "Up" según cuál comprima mejor (el ruido comprime mejor así).
    best = None
    for kind in (1, 2):
        if kind == 1:
            filtered = rows.copy()
            filtered[:, channels:] = rows[:, channels:] - rows[:, :-channels]
        else:
            filtered = rows.copy()
            filtered[1:] = rows[1:] - rows[:-1]
        raw = np.concatenate([np.full((height, 1), kind, dtype=np.uint8),
                              (filtered % 256).astype(np.uint8)], axis=1).tobytes()
        packed = zlib.compress(raw, 9)
        if best is None or len(packed) < len(best):
            best = packed

    def chunk(tag, payload):
        body = tag + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    color_type = 0 if gray else 2
    header = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)
    srgb = chunk(b"sRGB", b"\x00") if not gray else b""
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + srgb + chunk(b"IDAT", best) + chunk(b"IEND", b""))


def seam_error(array):
    """Salto en el borde comparado con el salto típico entre píxeles vecinos en la
    misma dirección (≈1 = sin costura; una costura real da muchas veces más)."""
    inner_u = np.mean(np.abs(np.diff(array, axis=1)))
    inner_v = np.mean(np.abs(np.diff(array, axis=0)))
    wrap_u = np.mean(np.abs(array[:, 0] - array[:, -1]))
    wrap_v = np.mean(np.abs(array[0] - array[-1]))
    return max(wrap_u / max(inner_u, 1e-6), wrap_v / max(inner_v, 1e-6))


def bake_material(name, stats):
    data = MATERIALS[name]
    started = time.time()
    scene = reset_scene()
    plane = bake_plane()
    color = bake_pass(plane, data, "color")
    packed = bake_pass(plane, data, "packed")
    height, rough, metal = packed[:, :, 0], packed[:, :, 1], packed[:, :, 2]
    # Oclusión de cavidades desde la altura: las juntas y grietas se oscurecen.
    blur = height.copy()
    for _ in range(4):
        blur = (blur + np.roll(blur, 3, 0) + np.roll(blur, -3, 0) + np.roll(blur, 3, 1) + np.roll(blur, -3, 1)) / 5
    cavity = np.clip(1.0 - np.maximum(blur - height, 0.0) * 4.0, 0.55, 1.0)
    color = color * cavity[:, :, None]
    folder = os.path.join(OUT, name)
    os.makedirs(folder, exist_ok=True)
    srgb = linear_to_srgb(color)
    write_png(os.path.join(folder, name + "_Color.png"), srgb)
    write_png(os.path.join(folder, name + "_Normal.png"), normal_from_height(height, data["strength"]))
    write_png(os.path.join(folder, name + "_Roughness.png"), rough)
    metal_path = os.path.join(folder, name + "_Metalness.png")
    if data["metal"]:
        write_png(metal_path, metal)
    elif os.path.exists(metal_path):
        os.remove(metal_path)
    mean = srgb.reshape(-1, 3).mean(axis=0)
    stats[name] = {
        "Mean": [int(round(c * 255)) for c in mean],
        "Roughness": round(float(rough.mean()), 3),
        "Metalness": round(float(metal.mean()), 3) if data["metal"] else 0.0,
        "Seam": round(float(max(seam_error(srgb), seam_error(height))), 3),
    }
    del scene
    print("[bake] %s listo en %.1f s (borde %.2f)" % (name, time.time() - started, stats[name]["Seam"]), flush=True)


# Hoja de muestra ----------------------------------------------------------------------


def load_png(path, colorspace):
    image = bpy.data.images.load(path, check_existing=False)
    image.colorspace_settings.name = colorspace
    return image


def preview(names):
    scene = reset_scene()
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 1600
    columns = 5
    rows = math.ceil(len(names) / columns)
    scene.render.resolution_y = int(1600 / columns * rows * 1.12)
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("Preview")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.012, 0.014, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    scene.world = world
    pitch = 2.2
    for index, name in enumerate(names):
        col = index % columns
        row = index // columns
        x = (col - (columns - 1) / 2) * pitch
        y = -((row - (rows - 1) / 2) * pitch * 1.12)
        folder = os.path.join(OUT, name)
        bpy.ops.mesh.primitive_plane_add(size=2, location=(x, y + 0.1, 0))
        plane = bpy.context.active_object
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        bsdf = nodes["Principled BSDF"]
        coord = nodes.new("ShaderNodeTexCoord")
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (2, 2, 1)
        links.new(coord.outputs["UV"], mapping.inputs["Vector"])

        def tex(suffix, colorspace):
            path = os.path.join(folder, name + suffix)
            if not os.path.exists(path):
                return None
            node = nodes.new("ShaderNodeTexImage")
            node.image = load_png(path, colorspace)
            links.new(mapping.outputs[0], node.inputs["Vector"])
            return node

        color = tex("_Color.png", "sRGB")
        if color:
            links.new(color.outputs["Color"], bsdf.inputs["Base Color"])
        rough = tex("_Roughness.png", "Non-Color")
        if rough:
            links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
        metal = tex("_Metalness.png", "Non-Color")
        if metal:
            links.new(metal.outputs["Color"], bsdf.inputs["Metallic"])
        normal = tex("_Normal.png", "Non-Color")
        if normal:
            normal_map = nodes.new("ShaderNodeNormalMap")
            links.new(normal.outputs["Color"], normal_map.inputs["Color"])
            links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
        plane.data.materials.append(material)
        bpy.ops.object.text_add(location=(x - 1.0, y - 1.12, 0))
        label = bpy.context.active_object
        label.data.body = name.replace("Nocturna", "")
        label.data.size = 0.22
        text_mat = bpy.data.materials.new("Label")
        text_mat.use_nodes = True
        text_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.8, 0.78, 0.74, 1)
        text_mat.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (0.8, 0.78, 0.74, 1)
        text_mat.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 0.6
        label.data.materials.append(text_mat)
    # Luz rasante (desde arriba a la izquierda) para que se lea el relieve, y un
    # relleno suave: las superficies metálicas reflejan el cielo de estudio.
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(62), 0, math.radians(-40)))
    bpy.context.active_object.data.energy = 3.2
    bpy.ops.object.light_add(type="AREA", location=(0, 0, 9))
    bpy.context.active_object.data.energy = 900
    bpy.context.active_object.data.size = 14
    bpy.ops.object.camera_add(location=(0, 0, 20))
    camera = bpy.context.active_object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = columns * pitch
    scene.camera = camera
    scene.render.filepath = os.path.join(OUT, "preview.png")
    bpy.ops.render.render(write_still=True)
    print("[bake] hoja de muestra: " + scene.render.filepath, flush=True)


def main():
    stats_path = os.path.join(OUT, "stats.json")
    stats = {}
    if os.path.exists(stats_path):
        with open(stats_path, encoding="utf-8") as handle:
            stats = json.load(handle)
    names = ONLY or list(MATERIALS)
    unknown = [name for name in names if name not in MATERIALS]
    if unknown:
        raise SystemExit("Materiales desconocidos: " + ", ".join(unknown))
    if not ONLY_PREVIEW:
        for name in names:
            bake_material(name, stats)
            with open(stats_path, "w", encoding="utf-8") as handle:
                json.dump(dict(sorted(stats.items())), handle, indent=2)
    if PREVIEW or ONLY_PREVIEW:
        preview([name for name in MATERIALS if os.path.exists(os.path.join(OUT, name, name + "_Color.png"))])


main()
