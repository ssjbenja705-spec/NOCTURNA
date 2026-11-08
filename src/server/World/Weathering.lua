-- Desgaste y daño de las salas: zarpazos tallados en la pared, grietas, pintura
-- descascarada (o ladrillos saltados, óxido, membranas, empapelado arrancado según
-- el capítulo), manchas de humedad, moho, sangre, pisos gastados y charcos.
--
-- No hay texturas propias: todo es geometría liviana con los materiales de Roblox.
-- Un zarpazo son cortes en cuña oscuros (el fondo del surco) con un labio claro de
-- revoque arrancado en un borde; la luz pega distinto en cada cara y se lee como
-- un tajo de verdad, no como una raya pintada.
--
-- Convención de las paredes: `face` es el marco de la cara interior de una pared
-- cerrada a nivel del piso (RoomGenerator), con X a lo largo de la pared y -Z hacia
-- la sala. La superficie del muro está en z = +WALL_SURFACE.
--
-- Todo es anclado, sin colisión ni consultas (PropKit.Part) y entra en el
-- presupuesto de piezas del capítulo.
local CollectionService = game:GetService("CollectionService")

local PropKit = require(script.Parent.PropKit)

local Weathering = {}

local Part = PropKit.Part
local M = PropKit.Material
local Shade = PropKit.Shade

local WALL_SURFACE = 0.15
-- Por encima del zócalo más alto (Wainscot llega a 3.7).
local MIN_HEIGHT = 4.2
local CEILING = 13
local WEDGE = {Class = "WedgePart"}
local DISC = {Shape = Enum.PartType.Cylinder}

Weathering.PUDDLE_TAG = "NocturnaPuddle"
Weathering.FX_TAG = "NocturnaAtmosFx"

-- Lo que cuesta cada daño, para repartir el presupuesto sin pasarse.
Weathering.Cost = {
    Claws = 7,
    Crack = 4,
    Peel = 3,
    Damp = 2,
    Mould = 1,
    Blood = 3,
    Puddle = 3,
    Wear = 1,
}

local DEFAULT_WEAR = {
    Peel = "Paint",
    Under = Color3.fromRGB(140, 136, 128),
    UnderMaterial = "Concrete",
    Stain = Color3.fromRGB(40, 36, 30),
    Claws = 0.3,
    Cracks = 0.4,
    Peels = 0.4,
    Damp = 0.4,
    Puddles = 0.2,
    Liquid = Color3.fromRGB(24, 28, 30),
}

function Weathering.Wear(theme)
    local wear = table.clone(DEFAULT_WEAR)
    for key, value in pairs(theme and theme.Wear or {}) do
        wear[key] = value
    end
    return wear
end

-- Marco sobre la pared: (x, y) en el plano del muro, `out` cuánto sobresale el
-- frente de la pieza y `thickness` su espesor (el resto queda metido en el muro).
local function onWall(face, x, y, out, thickness, angle)
    local z = WALL_SURFACE - out + thickness / 2
    return face * CFrame.new(x, y, z) * CFrame.Angles(0, 0, angle or 0)
end

local function between(rng, low, high)
    return low + rng:Float() * (high - low)
end

-- Zarpazos -----------------------------------------------------------------------

-- Un surco: dos cuñas oscuras unidas por la base (ancho en el medio, filoso en las
-- puntas) y, si alcanza, un labio de revoque claro levantado sobre un borde.
local function gouge(parent, face, origin, angle, length, width, depthColor, lipColor, material, lip)
    local direction = Vector3.new(math.cos(angle), math.sin(angle), 0)
    local normal = Vector3.new(0, 0, -1)
    local depth = 0.1
    local half = length / 2
    for _, sign in ipairs({1, -1}) do
        local center = origin + direction * (sign * half / 2)
        local z = WALL_SURFACE - 0.012 + depth / 2
        -- X sale de la pared, Y a lo largo del surco; la cara triangular mira a la sala.
        local frame = CFrame.fromMatrix(Vector3.new(center.X, center.Y, z), normal, direction * sign)
        Part(parent, "ClawGouge", Vector3.new(depth, half, width), face * frame, depthColor, material, WEDGE)
    end
    if lip then
        local across = Vector3.new(-math.sin(angle), math.cos(angle), 0)
        local center = origin + across * (width / 2 + 0.04)
        Part(parent, "ClawLip", Vector3.new(length * 0.62, 0.07, 0.08),
            onWall(face, center.X, center.Y, 0.05, 0.08, angle), lipColor, material)
    end
end

-- Tres o cuatro surcos paralelos, abiertos en abanico como una mano con garras.
function Weathering.Claws(parent, face, x, theme, _palette, rng, count)
    local wear = Weathering.Wear(theme)
    local depthColor = Shade(wear.Under, 0.28)
    local lipColor = Shade(wear.Under, 1.12)
    local material = M(wear.UnderMaterial)
    count = math.clamp(count or 4, 2, 4)

    local y = between(rng, 5.2, 8.4)
    local angle = math.rad(-90 + between(rng, -28, 28))
    local spacing = between(rng, 0.38, 0.5)
    local across = Vector3.new(-math.sin(angle), math.cos(angle), 0)
    local along = Vector3.new(math.cos(angle), math.sin(angle), 0)
    local base = Vector3.new(x, y, 0)
    for index = 1, count do
        local offset = (index - (count + 1) / 2)
        -- Los dedos de los costados son más cortos y arrancan más abajo.
        local length = between(rng, 2.6, 3.6) * (1 - math.abs(offset) * 0.14)
        local origin = base + across * (offset * spacing) + along * (math.abs(offset) * 0.25)
        local fan = angle + math.rad(offset * 3 + between(rng, -2, 2))
        -- Sólo los dedos del medio levantan revoque: el golpe más fuerte.
        local lip = math.abs(offset) < 1
        gouge(parent, face, origin, fan, length, between(rng, 0.17, 0.26), depthColor, lipColor, material, lip)
    end
    return count * 2 + (count % 2 == 0 and 2 or 1)
end

-- Grietas -------------------------------------------------------------------------

function Weathering.Crack(parent, face, x, theme, palette, rng, segments)
    local wall = theme.Wall or palette.Paint
    local color = Shade(wall, 0.24)
    local material = M(theme.WallMaterial or "Concrete")
    segments = segments or 4
    -- Baja desde el techo o sube desde el zócalo, siempre quebrada.
    local fromTop = rng:Chance(0.65)
    local point = Vector3.new(x, fromTop and CEILING - 0.2 or MIN_HEIGHT, 0)
    local heading = fromTop and -math.pi / 2 or math.pi / 2
    local used = 0
    for index = 1, segments do
        local length = between(rng, 1.1, 2.3)
        local angle = heading + math.rad(between(rng, -38, 38))
        local step = Vector3.new(math.cos(angle), math.sin(angle), 0) * length
        local middle = point + step / 2
        local width = index == 1 and 0.11 or 0.08
        if index == segments then
            -- Una rama corta al final.
            local branch = angle + math.rad(rng:Chance(0.5) and 40 or -40)
            local stepB = Vector3.new(math.cos(branch), math.sin(branch), 0) * (length * 0.6)
            local midB = point + stepB / 2
            Part(parent, "Crack", Vector3.new(length * 0.6, 0.06, 0.05), onWall(face, midB.X, midB.Y, 0.012, 0.05, branch), color, material)
            used += 1
        else
            Part(parent, "Crack", Vector3.new(length, width, 0.05), onWall(face, middle.X, middle.Y, 0.012, 0.05, angle), color, material)
            used += 1
        end
        point += step
        if point.Y < MIN_HEIGHT or point.Y > CEILING then
            break
        end
    end
    return used
end

-- Descascarado ----------------------------------------------------------------------
-- Según el capítulo: pintura (Paint), ladrillos saltados (Spall), óxido (Rust),
-- membrana rota (Membrane) o empapelado arrancado (Wallpaper).

function Weathering.Peel(parent, face, x, theme, palette, rng)
    local wear = Weathering.Wear(theme)
    local wall = theme.Wall or palette.Paint
    local kind = wear.Peel
    local width = between(rng, 1.8, 3.6)
    local height = between(rng, 1.4, 3)
    local y = between(rng, MIN_HEIGHT + height / 2, 10.5)
    local tilt = math.rad(between(rng, -12, 12))

    -- La mancha de abajo: lo que quedó a la vista.
    local under = Part(parent, "PeelPatch", Vector3.new(width, height, 0.04),
        onWall(face, x, y, 0.014, 0.04, tilt), PropKit.Vary(wear.Under, rng, 0.08), M(wear.UnderMaterial))
    if kind == "Rust" then
        under.Reflectance = 0
        -- Chorreadura de óxido hacia abajo.
        local run = between(rng, 1.6, 3.2)
        Part(parent, "RustRun", Vector3.new(width * 0.3, run, 0.03),
            onWall(face, x + between(rng, -0.4, 0.4), y - height / 2 - run / 2 + 0.2, 0.018, 0.03), Shade(wear.Under, 0.85), M("CorrodedMetal"))
        return 2
    elseif kind == "Spall" then
        -- Ladrillos saltados: el hueco es más oscuro y un trozo quedó suelto abajo.
        under.Color = Shade(wear.Under, 0.62)
        Part(parent, "LooseBrick", Vector3.new(0.9, 0.45, 0.4),
            onWall(face, x + between(rng, -0.6, 0.6), y - height / 2 + 0.15, 0.32, 0.4, math.rad(between(rng, -8, 8))), Shade(wall, 0.85), M(theme.WallMaterial or "Brick"))
        return 2
    elseif kind == "Membrane" then
        under.Color = Shade(wear.Under, 0.8)
        under.Reflectance = 0.06
    end

    -- Una lámina de pintura (o de empapelado) que se curva hacia la sala desde el
    -- borde de arriba del hueco.
    local flakeMaterial = M(theme.WallMaterial or "Plaster")
    local flakeHeight = kind == "Wallpaper" and between(rng, 1.4, 2.4) or between(rng, 0.6, 1.1)
    local curl = math.rad(kind == "Wallpaper" and between(rng, 14, 26) or between(rng, 22, 38))
    local hinge = onWall(face, x + between(rng, -0.3, 0.3), y + height / 2, 0.03, 0.03, tilt)
    Part(parent, "PeelFlake", Vector3.new(width * between(rng, 0.45, 0.7), flakeHeight, 0.03),
        hinge * CFrame.Angles(curl, 0, 0) * CFrame.new(0, -flakeHeight / 2, 0), Shade(wall, 1.05), flakeMaterial)
    return 2
end

-- Humedad, moho y sangre ------------------------------------------------------------

-- Mancha de gotera que baja desde el techo, con su chorreadura.
function Weathering.Damp(parent, face, x, theme, palette, rng)
    local wear = Weathering.Wear(theme)
    local wall = theme.Wall or palette.Paint
    local material = M(theme.WallMaterial or "Concrete")
    local width = between(rng, 3.5, 7)
    local height = between(rng, 2.5, 4.5)
    local patch = Part(parent, "DampPatch", Vector3.new(width, height, 0.03),
        onWall(face, x, CEILING - height / 2, 0.012, 0.03), Shade(wall, 0.62), material)
    patch.Transparency = 0.22
    local streakHeight = between(rng, 2.5, 5)
    local streak = Part(parent, "DampStreak", Vector3.new(between(rng, 0.5, 1.1), streakHeight, 0.03),
        onWall(face, x + between(rng, -width / 3, width / 3), CEILING - height - streakHeight / 2 + 0.4, 0.016, 0.03), Shade(wear.Stain, 1.1), material)
    streak.Transparency = 0.38
    return 2
end

function Weathering.Mould(parent, face, x, theme, _palette, rng)
    local wear = Weathering.Wear(theme)
    local size = between(rng, 1.2, 2.6)
    local blot = Part(parent, "Mould", Vector3.new(0.03, size, size),
        onWall(face, x, between(rng, MIN_HEIGHT + 0.6, 6), 0.02, 0.03) * CFrame.Angles(0, math.pi / 2, 0),
        wear.Mould or wear.Stain, M("Fabric"), DISC)
    blot.Transparency = 0.25
    return 1
end

-- Sangre arrastrada por la pared, con gotas abajo. Mojada: un poco de brillo.
function Weathering.Blood(parent, face, x, _theme, _palette, rng)
    local color = Color3.fromRGB(78, 10, 16)
    local length = between(rng, 2.2, 3.6)
    local top = between(rng, 6, 8.5)
    local smear = Part(parent, "BloodSmear", Vector3.new(between(rng, 0.7, 1.1), length, 0.03),
        onWall(face, x, top - length / 2, 0.02, 0.03, math.rad(between(rng, -10, 10))), color, M("SmoothPlastic"))
    smear.Reflectance = 0.08
    for index = 1, 2 do
        local drop = Part(parent, "BloodDrop", Vector3.new(0.03, 0.25, 0.25),
            onWall(face, x + between(rng, -0.6, 0.6), top - length - 0.3 * index, 0.022, 0.03) * CFrame.Angles(0, math.pi / 2, 0),
            Shade(color, 0.9), M("SmoothPlastic"), DISC)
        drop.Reflectance = 0.1
    end
    return 3
end

-- Pisos -----------------------------------------------------------------------------

-- Camino gastado en el centro de la sala: más oscuro y un poco más liso donde más
-- se pisó, siempre del mismo material que el piso.
function Weathering.FloorWear(parent, center, theme, rng)
    local size = between(rng, 12, 18)
    local material = M(theme.FloorMaterial or "Concrete")
    local worn = Part(parent, "WornFloor", Vector3.new(0.02, size, size),
        CFrame.new(center + Vector3.new(between(rng, -3, 3), 0.008, between(rng, -3, 3))) * CFrame.Angles(0, 0, math.pi / 2),
        Shade(theme.Floor, rng:Chance(0.5) and 0.82 or 1.12), material, DISC)
    worn.Transparency = 0.45
    return 1
end

-- Charco irregular: un halo de piso mojado, el agua y una parte más honda (más
-- oscura y con más reflejo). Refleja las lámparas cercanas con el brillo especular
-- de Future; el cliente lo hace temblar apenas (AmbientMotion).
function Weathering.Puddle(parent, position, theme, rng, drip)
    local wear = Weathering.Wear(theme)
    local liquid = wear.Liquid
    local diameter = between(rng, 4, 8)
    local floorMaterial = M(theme.FloorMaterial or "Concrete")
    local upright = CFrame.Angles(0, 0, math.pi / 2)
    local holder = Instance.new("Model")
    holder.Name = "Puddle"
    holder.Parent = parent

    local ring = Part(holder, "WetFloor", Vector3.new(0.02, diameter * 1.35, diameter * 1.35),
        CFrame.new(position + Vector3.new(0, 0.006, 0)) * upright, Shade(theme.Floor or liquid, 0.55), floorMaterial, DISC)
    ring.Reflectance = 0.06
    ring.Transparency = 0.2

    local water = Part(holder, "PuddleWater", Vector3.new(0.02, diameter, diameter),
        CFrame.new(position + Vector3.new(0, 0.018, 0)) * upright, liquid, M("Glass"), DISC)
    water.Transparency = 0.12
    water.Reflectance = 0.28
    CollectionService:AddTag(water, Weathering.PUDDLE_TAG)

    local offset = Vector3.new(between(rng, -1, 1), 0, between(rng, -1, 1)) * diameter * 0.3
    local deep = Part(holder, "PuddleDeep", Vector3.new(0.02, diameter * 0.55, diameter * 0.55),
        CFrame.new(position + offset + Vector3.new(0, 0.022, 0)) * upright, Shade(liquid, 0.7), M("Glass"), DISC)
    deep.Transparency = 0.18
    deep.Reflectance = 0.42

    if drip then
        -- Gotera: gotas que caen del techo justo sobre el charco (sin piezas extra).
        local attachment = Instance.new("Attachment")
        attachment.Name = "DripPoint"
        -- El disco está acostado: su eje X apunta hacia arriba.
        attachment.Position = Vector3.new(CEILING - 0.3, 0, 0)
        attachment.Parent = water
        local drops = Instance.new("ParticleEmitter")
        drops.Name = "Drips"
        drops.Texture = "rbxasset://textures/particles/sparkles_main.dds"
        drops.Color = ColorSequence.new(Color3.fromRGB(170, 190, 200))
        drops.LightEmission = 0.2
        drops.LightInfluence = 1
        drops.Size = NumberSequence.new(0.07)
        drops.Transparency = NumberSequence.new(0.2)
        drops.Lifetime = NumberRange.new(0.78)
        drops.Speed = NumberRange.new(0)
        drops.Acceleration = Vector3.new(0, -40, 0)
        drops.Rate = 0.6
        drops.Orientation = Enum.ParticleOrientation.VelocityParallel
        drops.Parent = attachment
        CollectionService:AddTag(drops, Weathering.FX_TAG)
        water:SetAttribute("Drips", true)
    end
    return 3
end

-- Una sala completa ------------------------------------------------------------------

local WALL_KINDS = {
    {Name = "Claws", Chance = "Claws", Builder = Weathering.Claws},
    {Name = "Crack", Chance = "Cracks", Builder = Weathering.Crack},
    {Name = "Peel", Chance = "Peels", Builder = Weathering.Peel},
    {Name = "Damp", Chance = "Damp", Builder = Weathering.Damp},
}

-- Elige un punto libre de una pared (lejos de muebles y rincones). Devuelve nil si
-- ya no queda lugar.
local function takeSpot(wall, rng, width)
    local candidates = {}
    for index, zone in ipairs(wall.Free) do
        if zone[2] - zone[1] >= width then
            table.insert(candidates, index)
        end
    end
    if #candidates == 0 then
        return nil
    end
    local index = candidates[rng:Int(1, #candidates)]
    local zone = wall.Free[index]
    local x = zone[1] + width / 2 + rng:Float() * (zone[2] - zone[1] - width)
    -- El lugar usado se saca de la lista para que dos daños no se pisen.
    table.remove(wall.Free, index)
    if x - width / 2 - zone[1] > 1 then
        table.insert(wall.Free, {zone[1], x - width / 2})
    end
    if zone[2] - (x + width / 2) > 1 then
        table.insert(wall.Free, {x + width / 2, zone[2]})
    end
    return x
end

-- Daña una sala con hasta `allowance` piezas. `walls` son las paredes cerradas con
-- sus huecos libres: {{Frame = CFrame, Free = {{desde, hasta}, ...}}}.
function Weathering.Room(parent, center, walls, theme, palette, rng, allowance, options)
    options = options or {}
    local wear = Weathering.Wear(theme)
    local cost = Weathering.Cost
    local used = 0
    local function afford(amount)
        return used + amount <= allowance and PropKit.Fits(amount)
    end

    -- Charco primero: es lo que más se nota con la linterna.
    if not options.NoPuddle and rng:Chance(wear.Puddles or 0) and afford(cost.Puddle) then
        local spot = center + Vector3.new(between(rng, -9, 9), 0, between(rng, -9, 9))
        used += Weathering.Puddle(parent, spot, theme, rng, rng:Chance(0.45))
    end

    if #walls > 0 then
        local order = table.clone(WALL_KINDS)
        rng:Shuffle(order)
        for _, kind in ipairs(order) do
            local chance = wear[kind.Chance] or 0
            if rng:Chance(chance) and afford(cost[kind.Name]) then
                local wall = walls[rng:Int(1, #walls)]
                local width = kind.Name == "Damp" and 6 or kind.Name == "Claws" and 2.6 or 3
                local x = takeSpot(wall, rng, width)
                if x then
                    local count = nil
                    if kind.Name == "Claws" then
                        count = afford(10) and 4 or 3
                    end
                    used += kind.Builder(parent, wall.Frame, x, theme, palette, rng, count)
                end
            end
        end

        if wear.Mould and rng:Chance(0.4) and afford(cost.Mould) then
            local wall = walls[rng:Int(1, #walls)]
            local x = takeSpot(wall, rng, 2)
            if x then
                used += Weathering.Mould(parent, wall.Frame, x, theme, palette, rng)
            end
        end
        if theme.Blood and rng:Chance(0.45) and afford(cost.Blood) then
            local wall = walls[rng:Int(1, #walls)]
            local x = takeSpot(wall, rng, 1.6)
            if x then
                used += Weathering.Blood(parent, wall.Frame, x, theme, palette, rng)
            end
        end
    end

    if not options.Corridor and rng:Chance(0.55) and afford(cost.Wear) then
        used += Weathering.FloorWear(parent, center, theme, rng)
    end
    return used
end

return Weathering
