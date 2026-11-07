-- Modelos de los objetos que se juntan: fusibles de vidrio, pilas, botiquines,
-- llaves... Cada uno se arma con pocas piezas y materiales reales. Para que se
-- encuentren alcanza con una luz suave y cálida; nada de cubos de neón.
local Shared = game:GetService("ReplicatedStorage").Shared
local ItemConfig = require(Shared.Config.ItemConfig)

local PropKit = require(script.Parent.PropKit)

local ItemModels = {}

local Part = PropKit.Part
local Cylinder = PropKit.Cylinder
local Column = PropKit.Column
local M = PropKit.Material

local STEEL = Color3.fromRGB(176, 178, 176)
local BRASS = Color3.fromRGB(178, 142, 78)
local DARK = Color3.fromRGB(34, 34, 37)

local BUILDERS = {}

-- Fusible de cartucho: tubo de vidrio, casquillos de metal y un filamento ámbar.
function BUILDERS.Fuse(parent, base)
    local center = base * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, math.rad(18), 0)
    local glass = Cylinder(parent, "Glass", 1.25, 0.46, center, Color3.fromRGB(205, 220, 222), M("Glass"))
    glass.Transparency = 0.45
    for _, side in ipairs({-1, 1}) do
        local cap = Cylinder(parent, "Cap", 0.28, 0.54, center * CFrame.new(side * 0.76, 0, 0), STEEL, M("Metal"))
        cap.Reflectance = 0.15
    end
    local filament = Cylinder(parent, "Filament", 1.24, 0.05, center, Color3.fromRGB(255, 168, 76), M("Neon"))
    filament.Transparency = 0.3
end

-- Pila grande: cuerpo negro, banda de cobre y el borne.
function BUILDERS.Battery(parent, base)
    Column(parent, "Body", 1.05, 0.68, base * CFrame.new(0, 0.53, 0), DARK, M("Plastic"))
    Column(parent, "Band", 0.3, 0.7, base * CFrame.new(0, 1.2, 0), Color3.fromRGB(196, 132, 58), M("Metal"))
    Column(parent, "Terminal", 0.1, 0.24, base * CFrame.new(0, 1.4, 0), STEEL, M("Metal"))
end

-- Botiquín: valija blanca de plástico con cruz roja y manija.
function BUILDERS.Medkit(parent, base)
    Part(parent, "Case", Vector3.new(1.8, 0.75, 1.2), base * CFrame.new(0, 0.375, 0), Color3.fromRGB(222, 222, 216), M("Plastic"))
    Part(parent, "Seam", Vector3.new(1.82, 0.06, 1.22), base * CFrame.new(0, 0.55, 0), Color3.fromRGB(150, 150, 146), M("Plastic"))
    local red = Color3.fromRGB(178, 36, 36)
    Part(parent, "CrossA", Vector3.new(0.8, 0.03, 0.24), base * CFrame.new(0, 0.765, 0), red, M("SmoothPlastic"))
    Part(parent, "CrossB", Vector3.new(0.24, 0.03, 0.8), base * CFrame.new(0, 0.765, 0), red, M("SmoothPlastic"))
    Part(parent, "Handle", Vector3.new(0.7, 0.18, 0.14), base * CFrame.new(0, 0.86, 0.45), DARK, M("Rubber"))
end

-- Llave vieja de bronce con etiqueta de cartón.
function BUILDERS.Key(parent, base)
    local flat = base * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, math.rad(-25), 0)
    Column(parent, "Bow", 0.08, 0.5, flat * CFrame.new(-0.45, 0, 0), BRASS, M("Metal"))
    Part(parent, "Shaft", Vector3.new(0.85, 0.08, 0.12), flat * CFrame.new(0.2, 0, 0), BRASS, M("Metal"))
    Part(parent, "Bit", Vector3.new(0.14, 0.08, 0.3), flat * CFrame.new(0.56, 0, 0.12), BRASS, M("Metal"))
    Part(parent, "Tag", Vector3.new(0.42, 0.03, 0.26), flat * CFrame.new(-0.6, -0.02, 0.36) * CFrame.Angles(0, 0.4, 0), Color3.fromRGB(196, 170, 120), M("Cardboard"))
end

-- Tarjeta de acceso con franja de color y foto.
function BUILDERS.Keycard(parent, base)
    local flat = base * CFrame.new(0, 0.03, 0) * CFrame.Angles(0, math.rad(12), 0)
    Part(parent, "Card", Vector3.new(1, 0.04, 0.65), flat, Color3.fromRGB(232, 232, 228), M("SmoothPlastic"))
    Part(parent, "Stripe", Vector3.new(1, 0.045, 0.14), flat * CFrame.new(0, 0, -0.2), Color3.fromRGB(60, 150, 130), M("SmoothPlastic"))
    Part(parent, "Photo", Vector3.new(0.24, 0.045, 0.3), flat * CFrame.new(-0.3, 0, 0.1), Color3.fromRGB(120, 108, 98), M("SmoothPlastic"))
    Part(parent, "Clip", Vector3.new(0.12, 0.05, 0.22), flat * CFrame.new(0.52, 0, 0), STEEL, M("Metal"))
end

-- Radio portátil: caja, parlante, dial, perilla y antena.
function BUILDERS.Radio(parent, base)
    Part(parent, "Body", Vector3.new(1.5, 0.9, 0.55), base * CFrame.new(0, 0.45, 0), Color3.fromRGB(58, 52, 46), M("Plastic"))
    Part(parent, "Speaker", Vector3.new(0.68, 0.6, 0.05), base * CFrame.new(-0.32, 0.45, -0.28), DARK, M("DiamondPlate"))
    Part(parent, "Dial", Vector3.new(0.5, 0.24, 0.05), base * CFrame.new(0.38, 0.58, -0.28), Color3.fromRGB(205, 160, 90), M("Glass"))
    Cylinder(parent, "Knob", 0.12, 0.2, base * CFrame.new(0.38, 0.28, -0.32) * CFrame.Angles(0, math.rad(90), 0), STEEL, M("Metal"))
    Part(parent, "Antenna", Vector3.new(0.05, 1.05, 0.05), base * CFrame.new(0.6, 1.35, 0.1) * CFrame.Angles(0, 0, math.rad(-18)), STEEL, M("Metal"))
end

-- Muestra: frasco de vidrio con líquido oscuro en una gradilla.
function BUILDERS.Sample(parent, base)
    Part(parent, "Rack", Vector3.new(1.1, 0.2, 0.5), base * CFrame.new(0, 0.1, 0), STEEL, M("Metal"))
    local vial = Column(parent, "Vial", 1, 0.32, base * CFrame.new(0, 0.7, 0), Color3.fromRGB(210, 222, 226), M("Glass"))
    vial.Transparency = 0.55
    local fluid = Column(parent, "Fluid", 0.6, 0.26, base * CFrame.new(0, 0.52, 0), Color3.fromRGB(122, 22, 38), M("SmoothPlastic"))
    fluid.Transparency = 0.15
    Column(parent, "Stopper", 0.14, 0.34, base * CFrame.new(0, 1.24, 0), Color3.fromRGB(90, 30, 36), M("Rubber"))
end

-- Pedazo de foto vieja, rota y un poco curvada.
function BUILDERS.MemoryShard(parent, base)
    local flat = base * CFrame.new(0, 0.03, 0) * CFrame.Angles(math.rad(3), math.rad(30), 0)
    Part(parent, "Photo", Vector3.new(1, 0.03, 0.75), flat, Color3.fromRGB(214, 196, 162), M("SmoothPlastic"))
    Part(parent, "Image", Vector3.new(0.8, 0.035, 0.56), flat * CFrame.Angles(0, 0.04, 0), Color3.fromRGB(118, 98, 78), M("SmoothPlastic"))
end

-- Caja de cartón donde apoya el objeto: lo deja a la altura de la vista.
local function buildStand(parent, base)
    Part(parent, "Stand", Vector3.new(1.8, 1.55, 1.6), base * CFrame.new(0, 0.775, 0), Color3.fromRGB(150, 118, 80), M("Cardboard"), PropKit.SOLID)
    Part(parent, "Tape", Vector3.new(0.35, 0.02, 1.62), base * CFrame.new(0, 1.555, 0), Color3.fromRGB(196, 176, 128), M("SmoothPlastic"))
end

local STAND_HEIGHT = 1.56
local GLOW_TINT = Color3.fromRGB(255, 226, 180)

-- Devuelve la pieza raíz (invisible, aloja el prompt) para InteractionService.
function ItemModels.Build(parent, itemId, cframe)
    local definition = ItemConfig[itemId]
    local holder = Part(
        parent,
        "Pickup_" .. itemId,
        Vector3.new(1.6, 1.2, 1.6),
        cframe * CFrame.new(0, STAND_HEIGHT + 0.6, 0),
        definition.Color,
        M("SmoothPlastic"),
        {Transparency = 1}
    )

    PropKit.Visual(holder, "PickupStand", cframe, function(target)
        buildStand(target, cframe)
    end)

    local top = cframe * CFrame.new(0, STAND_HEIGHT, 0)
    local builder = BUILDERS[itemId]
    if builder then
        PropKit.Visual(holder, itemId, top, function(target)
            builder(target, top)
        end)
    end

    local glow = PropKit.Light(holder, "PointLight", definition.Color:Lerp(GLOW_TINT, 0.6), 0.45, 6.5, false)
    glow.Name = "Glow"
    return holder
end

ItemModels.Builders = BUILDERS

return ItemModels
