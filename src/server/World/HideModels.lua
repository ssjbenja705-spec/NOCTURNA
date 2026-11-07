-- Escondites: casillero, ropero, debajo del escritorio, debajo de la cama y conducto
-- de ventilación. Todos miran hacia -Z (la sala) y dejan rendijas reales entre las
-- tablillas, para que la cámara de adentro vea la habitación.
--
-- Cada escondite devuelve su especificación, en coordenadas del rincón:
--   Inside: dónde queda fijo el personaje.
--   Camera: desde dónde mira el jugador (adentro, detrás de las rendijas).
--   Exit:   dónde sale, delante del escondite y mirando a la sala.
--   DoorZ:  plano interior de la puerta o abertura (la cámara queda detrás).
-- El prompt siempre vive en una pieza invisible llamada "Door".
local PropKit = require(script.Parent.PropKit)

local HideModels = {}

local Part = PropKit.Part
local Solid = PropKit.Solid
local M = PropKit.Material
local SOLID = PropKit.SOLID

local STEEL = Color3.fromRGB(150, 152, 150)

local DEFAULT_STYLE = {
    Locker = Color3.fromRGB(74, 86, 84),
    Wardrobe = Color3.fromRGB(92, 66, 46),
    WardrobeMaterial = "Wood",
    WardrobeLabel = "Ropero",
    Desk = Color3.fromRGB(96, 78, 58),
    DeskMaterial = "WoodPlanks",
    Bed = "Hospital",
    Vent = Color3.fromRGB(128, 134, 136),
    VentMaterial = "Metal",
}

-- Tablillas horizontales con aire entre ellas, de yFrom a yTo.
local function louvers(parent, base, width, yFrom, yTo, count, z, color, material)
    local pitch = (yTo - yFrom) / count
    for index = 1, count do
        local y = yFrom + pitch * (index - 0.5)
        Part(
            parent,
            "Slat",
            Vector3.new(width, 0.09, 0.15),
            base * CFrame.new(0, y, z) * CFrame.Angles(math.rad(-14), 0, 0),
            color,
            material,
            SOLID
        )
    end
end

local function host(parent, base, size, offset)
    local door = Part(parent, "Door", size, base * offset, Color3.new(0, 0, 0), M("SmoothPlastic"), {Transparency = 1})
    return door
end

local function box(parent, base, name, size, offset, color, material)
    return Solid(parent, name, size, base * offset, color, material)
end

local BUILDERS = {}

-- Casillero metálico de vestuario con persianas a la altura de los ojos.
function BUILDERS.Locker(parent, base, style)
    local shell = style.Locker
    local metal = M("Metal")
    local width, depth, height = 3.4, 2.8, 7.6

    PropKit.Visual(parent, "Locker", base, function(target)
        box(target, base, "Back", Vector3.new(width, height, 0.12), CFrame.new(0, height / 2, depth / 2 - 0.06), shell, metal)
        for _, side in ipairs({-1, 1}) do
            box(target, base, "Side", Vector3.new(0.12, height, depth), CFrame.new(side * (width / 2 - 0.06), height / 2, 0), shell, metal)
        end
        box(target, base, "Top", Vector3.new(width, 0.12, depth), CFrame.new(0, height - 0.06, 0), shell, metal)
        box(target, base, "Plinth", Vector3.new(width, 0.3, depth), CFrame.new(0, 0.15, 0), PropKit.Shade(shell, 0.6), M("CorrodedMetal"))

        local door = PropKit.Shade(shell, 0.92)
        local z = -depth / 2 + 0.04
        box(target, base, "DoorPanel", Vector3.new(width - 0.24, 4.25, 0.08), CFrame.new(0, 2.425, z), door, metal)
        for _, side in ipairs({-1, 1}) do
            box(target, base, "Stile", Vector3.new(0.3, 1.8, 0.08), CFrame.new(side * (width / 2 - 0.27), 5.45, z), door, metal)
        end
        louvers(target, base, width - 0.3, 4.55, 6.35, 5, z, door, metal)
        box(target, base, "DoorTop", Vector3.new(width - 0.24, 1.13, 0.08), CFrame.new(0, 6.915, z), door, metal)
        Part(target, "Handle", Vector3.new(0.1, 0.55, 0.1), base * CFrame.new(1.2, 4, z - 0.09), STEEL, metal)
        Part(target, "Plate", Vector3.new(0.42, 0.22, 0.02), base * CFrame.new(0, 7.05, z - 0.05), Color3.fromRGB(176, 146, 86), metal)
    end)

    return host(parent, base, Vector3.new(width - 0.4, 6, 0.1), CFrame.new(0, 3.4, -depth / 2 - 0.02)), {
        Label = "Casillero",
        Inside = CFrame.new(0, 3, 0.5),
        Camera = CFrame.new(0, 5.45, -0.5),
        Exit = CFrame.new(0, 3, -4),
        DoorZ = -depth / 2 + 0.08,
    }
end

-- Ropero (madera) o armario metálico de dos puertas con persianas.
function BUILDERS.Wardrobe(parent, base, style)
    local shell = style.Wardrobe
    local material = M(style.WardrobeMaterial)
    local width, depth, height = 4.6, 2.6, 7.8

    PropKit.Visual(parent, "Wardrobe", base, function(target)
        box(target, base, "Back", Vector3.new(width, height, 0.12), CFrame.new(0, height / 2, depth / 2 - 0.06), shell, material)
        for _, side in ipairs({-1, 1}) do
            box(target, base, "Side", Vector3.new(0.14, height, depth), CFrame.new(side * (width / 2 - 0.07), height / 2, 0), shell, material)
        end
        box(target, base, "Crown", Vector3.new(width + 0.3, 0.3, depth + 0.2), CFrame.new(0, height + 0.15, 0), PropKit.Shade(shell, 0.85), material)
        box(target, base, "Plinth", Vector3.new(width, 0.3, depth), CFrame.new(0, 0.15, 0), PropKit.Shade(shell, 0.7), material)

        local door = PropKit.Shade(shell, 1.08)
        local z = -depth / 2 + 0.05
        for _, side in ipairs({-1, 1}) do
            box(target, base, "DoorPanel", Vector3.new(width / 2 - 0.16, 4, 0.1), CFrame.new(side * width / 4, 2.3, z), door, material)
            box(target, base, "Stile", Vector3.new(0.22, 2.2, 0.1), CFrame.new(side * (width / 2 - 0.25), 5.4, z), door, material)
            Part(target, "Knob", Vector3.new(0.16, 0.16, 0.16), base * CFrame.new(side * 0.25, 4.1, z - 0.1), Color3.fromRGB(170, 140, 80), M("Metal"), {Shape = Enum.PartType.Ball})
        end
        box(target, base, "Mullion", Vector3.new(0.14, 2.2, 0.1), CFrame.new(0, 5.4, z), door, material)
        louvers(target, base, width - 0.4, 4.3, 6.5, 5, z, door, material)
        box(target, base, "DoorTop", Vector3.new(width - 0.3, 1, 0.1), CFrame.new(0, 7, z), door, material)
    end)

    return host(parent, base, Vector3.new(width - 0.5, 6, 0.1), CFrame.new(0, 3.4, -depth / 2 - 0.02)), {
        Label = style.WardrobeLabel,
        Inside = CFrame.new(0, 3, 0.45),
        Camera = CFrame.new(0, 5.4, -0.42),
        Exit = CFrame.new(0, 3, -3.9),
        DoorZ = -depth / 2 + 0.1,
    }
end

-- Escritorio pesado: el jugador se mete agachado en el hueco de las rodillas.
function BUILDERS.Desk(parent, base, style)
    local color = style.Desk
    local material = M(style.DeskMaterial)
    local width, depth, height = 6, 3.2, 3

    PropKit.Visual(parent, "HideDesk", base, function(target)
        box(target, base, "Top", Vector3.new(width, 0.22, depth), CFrame.new(0, height - 0.11, 0), color, material)
        box(target, base, "Pedestal", Vector3.new(1.7, height - 0.22, depth - 0.1), CFrame.new(-(width / 2 - 0.85), (height - 0.22) / 2, 0), PropKit.Shade(color, 0.9), material)
        for _, y in ipairs({0.9, 2}) do
            Part(target, "Pull", Vector3.new(0.5, 0.08, 0.06), base * CFrame.new(-(width / 2 - 0.85), y, -depth / 2 + 0.02), STEEL, M("Metal"))
        end
        box(target, base, "Side", Vector3.new(0.18, height - 0.22, depth - 0.1), CFrame.new(width / 2 - 0.09, (height - 0.22) / 2, 0), PropKit.Shade(color, 0.9), material)
        box(target, base, "Modesty", Vector3.new(width - 1.9, 1.7, 0.12), CFrame.new(0.85, 1.95, depth / 2 - 0.15), PropKit.Shade(color, 0.8), material)

        Part(target, "Monitor", Vector3.new(1.4, 1.15, 1.2), base * CFrame.new(-1.6, height + 0.58, 0.5), Color3.fromRGB(196, 190, 172), M("Plastic"))
        Part(target, "Papers", Vector3.new(1, 0.05, 1.3), base * CFrame.new(1.2, height + 0.03, -0.2) * CFrame.Angles(0, 0.35, 0), Color3.fromRGB(222, 214, 190), M("SmoothPlastic"))
        PropKit.Column(target, "Mug", 0.42, 0.34, base * CFrame.new(2.3, height + 0.21, 0.6), Color3.fromRGB(150, 60, 50), M("Plastic"))
    end)

    return host(parent, base, Vector3.new(2.8, 2.2, 0.1), CFrame.new(0.8, 1.2, -depth / 2 + 0.05)), {
        Label = "Debajo del escritorio",
        Inside = CFrame.new(0.8, -1.15, 0.35),
        Camera = CFrame.new(0.8, 1.45, -0.55) * CFrame.Angles(math.rad(-3), 0, 0),
        Exit = CFrame.new(0.8, 3, -3.7),
        DoorZ = -depth / 2,
    }
end

-- Cama de hospital (metal) o de casa (madera): se esconde abajo, con la colcha
-- tapando la pared y los costados.
function BUILDERS.Bed(parent, base, style)
    local hospital = style.Bed == "Hospital"
    local frameColor = hospital and Color3.fromRGB(150, 156, 158) or Color3.fromRGB(96, 64, 42)
    local frameMaterial = hospital and M("Metal") or M("Wood")
    local length, depth = 7.4, 3.8

    PropKit.Visual(parent, "HideBed", base, function(target)
        box(target, base, "Frame", Vector3.new(length, 0.25, depth), CFrame.new(0, 1.42, 0), frameColor, frameMaterial)
        for _, side in ipairs({-1, 1}) do
            Part(target, "Legs", Vector3.new(0.2, 1.3, depth - 0.4), base * CFrame.new(side * (length / 2 - 0.25), 0.65, 0), frameColor, frameMaterial)
        end
        local sheet = hospital and Color3.fromRGB(196, 204, 206) or Color3.fromRGB(176, 150, 128)
        box(target, base, "Mattress", Vector3.new(length - 0.3, 0.55, depth - 0.3), CFrame.new(0, 1.82, 0), sheet, M("Fabric"))
        Part(target, "Pillow", Vector3.new(1.3, 0.3, depth - 0.9), base * CFrame.new(-(length / 2 - 0.95), 2.24, 0), PropKit.Shade(sheet, 1.08), M("Fabric"))
        local blanket = hospital and Color3.fromRGB(110, 128, 140) or Color3.fromRGB(128, 70, 62)
        Part(target, "Blanket", Vector3.new(length * 0.62, 0.1, depth + 0.1), base * CFrame.new(0.9, 2.14, 0), blanket, M("Fabric"))
        Part(target, "Drape", Vector3.new(length * 0.62, 1.5, 0.08), base * CFrame.new(0.9, 1.4, depth / 2 + 0.05), blanket, M("Fabric"), SOLID)
        box(target, base, "Headboard", Vector3.new(0.25, 2.8, depth), CFrame.new(-length / 2 + 0.12, 1.4, 0), frameColor, frameMaterial)
        box(target, base, "Footboard", Vector3.new(0.2, 2, depth), CFrame.new(length / 2 - 0.1, 1, 0), frameColor, frameMaterial)
    end)

    return host(parent, base, Vector3.new(3, 1.2, 0.1), CFrame.new(0, 0.6, -depth / 2 + 0.05)), {
        Label = "Debajo de la cama",
        Inside = CFrame.new(0.3, -1.35, 0.25),
        Camera = CFrame.new(0.3, 0.8, -0.75) * CFrame.Angles(math.rad(-2), 0, 0),
        Exit = CFrame.new(0, 3, -4.1),
        DoorZ = -depth / 2,
    }
end

-- Tronco de ventilación de chapa, del piso al techo, con la rejilla de acceso abajo.
function BUILDERS.Vent(parent, base, style)
    local color = style.Vent
    local material = M(style.VentMaterial)
    local width, depth, height = 4.2, 3.4, 12.9
    local z = -depth / 2 + 0.05

    PropKit.Visual(parent, "VentDuct", base, function(target)
        box(target, base, "Back", Vector3.new(width, height, 0.1), CFrame.new(0, height / 2, depth / 2 - 0.05), color, material)
        for _, side in ipairs({-1, 1}) do
            box(target, base, "Side", Vector3.new(0.1, height, depth), CFrame.new(side * (width / 2 - 0.05), height / 2, 0), color, material)
        end
        box(target, base, "Front", Vector3.new(width, height - 3.4, 0.1), CFrame.new(0, 3.4 + (height - 3.4) / 2, z), color, material)
        for _, y in ipairs({6.5, 10}) do
            Part(target, "Seam", Vector3.new(width + 0.06, 0.18, depth + 0.06), base * CFrame.new(0, y, 0), PropKit.Shade(color, 0.82), material)
        end
        local grate = PropKit.Shade(color, 0.7)
        box(target, base, "RailTop", Vector3.new(width - 0.1, 0.25, 0.14), CFrame.new(0, 3.27, z), grate, material)
        box(target, base, "RailBottom", Vector3.new(width - 0.1, 0.3, 0.14), CFrame.new(0, 0.15, z), grate, material)
        louvers(target, base, width - 0.2, 0.3, 3.15, 6, z, grate, material)
        Part(target, "Warning", Vector3.new(0.9, 0.5, 0.02), base * CFrame.new(0, 4.2, z - 0.06), Color3.fromRGB(196, 160, 52), M("SmoothPlastic"))
    end)

    return host(parent, base, Vector3.new(width - 0.6, 2.6, 0.1), CFrame.new(0, 1.7, z - 0.1)), {
        Label = "Conducto de ventilación",
        Inside = CFrame.new(0, 1.25, 0.55),
        Camera = CFrame.new(0, 1.75, -0.5),
        Exit = CFrame.new(0, 3, -4.3),
        DoorZ = z + 0.07,
    }
end

HideModels.Kinds = {"Locker", "Wardrobe", "Desk", "Bed", "Vent"}

-- Arma un escondite en `base` (rincón mirando a la sala). Devuelve el modelo, el
-- prompt y la especificación.
function HideModels.Build(parent, kind, base, style)
    local builder = BUILDERS[kind] or BUILDERS.Locker
    local merged = table.clone(DEFAULT_STYLE)
    for key, value in pairs(style or {}) do
        merged[key] = value
    end

    local holder = PropKit.Model(parent, kind)
    local door, spec = builder(holder, base, merged)
    holder.PrimaryPart = door
    holder:SetAttribute("HideKind", kind)
    spec.Kind = kind

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "NocturnaPrompt"
    prompt.ActionText = "Esconderse"
    prompt.ObjectText = spec.Label
    prompt.HoldDuration = 0.25
    prompt.MaxActivationDistance = 8
    prompt.RequiresLineOfSight = false
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.Parent = door

    return holder, prompt, spec
end

return HideModels
