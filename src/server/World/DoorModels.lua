-- Puertas comunes de cada capítulo, con la arquitectura y el deterioro del lugar:
--   Shutter: cortina metálica oxidada de túnel, sube enrollándose en el dintel.
--   Office:  puerta doble de clínica con vidrio armado sucio; se corre hacia los muros.
--   Airlock: esclusa del laboratorio, con franjas de peligro y luz de estado.
--   Vault:   hoja de acero del archivo, con nervaduras y volante; se corre entera.
--   Home:    puerta doble de madera de la casa; gira sobre sus bisagras.
--
-- Una pieza invisible (Blocker) hace de pared mientras está cerrada; las hojas son
-- sólo visuales: cada hoja tiene una raíz anclada que se anima y sus detalles van
-- soldados a ella. Así la colisión nunca depende de una animación a medio camino.
local PropKit = require(script.Parent.PropKit)

local DoorModels = {}

local Shade = PropKit.Shade
local M = PropKit.Material

local HAZARD = Color3.fromRGB(196, 158, 40)
local DARK = Color3.fromRGB(28, 28, 30)

-- Lo que distingue a cada estilo: materiales, colores, tiempos y forma de abrir.
DoorModels.Styles = {
    Shutter = {Motion = "Lift", Open = 1.1, Close = 0.8, Material = "CorrodedMetal", Color = Color3.fromRGB(86, 84, 80), Locked = Color3.fromRGB(122, 64, 42)},
    Office = {Motion = "Slide", Open = 0.8, Close = 0.6, Material = "Wood", Color = Color3.fromRGB(150, 156, 142), Locked = Color3.fromRGB(120, 92, 70)},
    Airlock = {Motion = "Slide", Open = 0.9, Close = 0.5, Material = "Metal", Color = Color3.fromRGB(158, 162, 160), Locked = Color3.fromRGB(140, 70, 70), Lamp = true},
    Vault = {Motion = "Single", Open = 1.6, Close = 1.1, Material = "DiamondPlate", Color = Color3.fromRGB(92, 100, 112), Locked = Color3.fromRGB(110, 74, 64), Lamp = true},
    Home = {Motion = "Swing", Open = 0.9, Close = 0.45, Material = "WoodPlanks", Color = Color3.fromRGB(112, 80, 56), Locked = Color3.fromRGB(92, 60, 44)},
}

function DoorModels.Style(theme)
    local name = theme and theme.DoorStyle
    if not DoorModels.Styles[name] then
        name = "Shutter"
    end
    return name, DoorModels.Styles[name]
end

local function weld(root, piece)
    piece.Anchored = false
    piece.Massless = true
    local joint = Instance.new("WeldConstraint")
    joint.Part0 = root
    joint.Part1 = piece
    joint.Parent = piece
    return piece
end

-- Detalle soldado a una hoja: `offset` es relativo a la raíz de la hoja.
local function detail(root, name, size, offset, color, material, options)
    local piece = PropKit.Part(root.Parent, name, size, root.CFrame * offset, color, material, options)
    return weld(root, piece)
end

local function leafRoot(parent, name, size, cframe, color, material)
    local root = PropKit.Part(parent, name, size, cframe, color, material)
    root.CastShadow = true
    return root
end

-- Hojas por estilo -----------------------------------------------------------------
-- Cada constructor recibe el marco del vano (`frame`: centro del vano a nivel del
-- piso, X a lo largo de la pared) y devuelve las hojas {Root, Closed, Open}.

local BUILDERS = {}

function BUILDERS.Shutter(holder, frame, width, height, style, color, locked)
    local material = M(style.Material)
    local closed = frame * CFrame.new(0, height / 2, 0)
    local root = leafRoot(holder, "ShutterLeaf", Vector3.new(width, height, 0.3), closed, color, material)
    -- Lamas de la cortina, a los dos lados, y la barra de abajo con la manija.
    for index = 1, 4 do
        local y = -height / 2 + index * height / 5
        detail(root, "Slat", Vector3.new(width, 0.16, 0.42), CFrame.new(0, y, 0), Shade(color, 0.78), material)
    end
    detail(root, "BottomBar", Vector3.new(width, 0.45, 0.5), CFrame.new(0, -height / 2 + 0.22, 0), Shade(color, 0.6), M("Metal"))
    detail(root, "Rust", Vector3.new(width * 0.4, height * 0.35, 0.34), CFrame.new(width * 0.18, -height * 0.25, 0), Color3.fromRGB(110, 58, 34), M("CorrodedMetal"))
    local leaves = {{Root = root, Closed = closed, Open = closed * CFrame.new(0, height - 0.8, 0)}}
    return leaves, locked and root or nil
end

-- Dos hojas que se corren hacia adentro de los muros.
local function slidingPair(holder, frame, width, height, style, color, decorate)
    local material = M(style.Material)
    local leaves = {}
    for _, side in ipairs({-1, 1}) do
        local closed = frame * CFrame.new(side * width / 4, height / 2, 0)
        local root = leafRoot(holder, "DoorLeaf", Vector3.new(width / 2, height, 0.4), closed, color, material)
        decorate(root, side)
        table.insert(leaves, {Root = root, Closed = closed, Open = closed * CFrame.new(side * (width / 2 - 0.3), 0, 0)})
    end
    return leaves
end

function BUILDERS.Office(holder, frame, width, height, style, color, locked)
    local leaves = slidingPair(holder, frame, width, height, style, color, function(root, side)
        -- Vidrio armado opaco de mugre, marco de metal, zócalo de chapa y tirador.
        local glass = detail(root, "WiredGlass", Vector3.new(width / 2 - 1.6, height * 0.3, 0.46), CFrame.new(0, height * 0.18, 0), Color3.fromRGB(150, 160, 150), M("Glass"))
        glass.Transparency = 0.45
        glass.Reflectance = 0.05
        detail(root, "KickPlate", Vector3.new(width / 2 - 0.2, 1.1, 0.46), CFrame.new(0, -height / 2 + 0.6, 0), Color3.fromRGB(120, 122, 118), M("Metal"))
        detail(root, "Handle", Vector3.new(0.18, 1.4, 0.6), CFrame.new(-side * (width / 4 - 0.5), 0, 0), Color3.fromRGB(70, 72, 74), M("Metal"))
    end)
    return leaves, locked and leaves[1].Root or nil
end

function BUILDERS.Airlock(holder, frame, width, height, style, color, locked)
    local leaves = slidingPair(holder, frame, width, height, style, color, function(root, side)
        -- Franjas de peligro en el canto y una membrana que se pegó a la chapa.
        detail(root, "Hazard", Vector3.new(0.5, height, 0.46), CFrame.new(-side * (width / 4 - 0.25), 0, 0), HAZARD, M("Metal"))
        detail(root, "Porthole", Vector3.new(0.46, 1.2, 1.2), CFrame.new(0, height * 0.2, 0) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(70, 90, 80), M("Glass"), {Shape = Enum.PartType.Cylinder, Transparency = 0.35})
        detail(root, "Growth", Vector3.new(width / 2 - 1, 0.8, 0.5), CFrame.new(0, -height / 2 + 0.4, 0), Color3.fromRGB(96, 30, 40), M("Slate"))
    end)
    return leaves, locked and leaves[1].Root or nil
end

function BUILDERS.Vault(holder, frame, width, height, style, color, locked)
    local material = M(style.Material)
    local closed = frame * CFrame.new(0, height / 2, 0)
    local root = leafRoot(holder, "VaultLeaf", Vector3.new(width, height, 0.5), closed, color, material)
    for _, x in ipairs({-width / 3, 0, width / 3}) do
        detail(root, "Rib", Vector3.new(0.4, height - 0.4, 0.64), CFrame.new(x, 0, 0), Shade(color, 0.8), M("Metal"))
    end
    detail(root, "Wheel", Vector3.new(0.7, 1.8, 1.8), CFrame.new(width / 6, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), Shade(color, 0.6), M("Metal"), {Shape = Enum.PartType.Cylinder})
    detail(root, "Scrapes", Vector3.new(width * 0.6, 0.12, 0.54), CFrame.new(0, -height / 2 + 0.9, 0) * CFrame.Angles(0, 0, 0.05), Color3.fromRGB(150, 156, 164), M("Metal"))
    local leaves = {{Root = root, Closed = closed, Open = closed * CFrame.new(width - 0.4, 0, 0)}}
    return leaves, locked and root or nil
end

function BUILDERS.Home(holder, frame, width, height, style, color, locked)
    local material = M(style.Material)
    local leaves = {}
    for _, side in ipairs({-1, 1}) do
        -- La raíz es la bisagra: girarla lleva la hoja entera alrededor del marco.
        local hinge = frame * CFrame.new(side * width / 2, height / 2, 0)
        local root = PropKit.Part(holder, "Hinge", Vector3.new(0.2, height, 0.2), hinge, Shade(color, 0.6), M("Metal"))
        local leaf = detail(root, "DoorLeaf", Vector3.new(width / 2 - 0.1, height, 0.35), CFrame.new(-side * width / 4, 0, 0), color, material)
        leaf.CastShadow = true
        -- Tableros rehundidos, pintura gastada en el borde y el picaporte.
        for _, y in ipairs({height * 0.22, -height * 0.2}) do
            detail(root, "Panel", Vector3.new(width / 2 - 1.4, height * 0.3, 0.42), CFrame.new(-side * width / 4, y, 0), Shade(color, 0.86), material)
        end
        detail(root, "Knob", Vector3.new(0.3, 0.3, 0.6), CFrame.new(-side * (width / 2 - 0.5), -0.4, 0), Color3.fromRGB(176, 150, 90), M("Metal"), {Shape = Enum.PartType.Ball})
        table.insert(leaves, {Root = root, Closed = hinge, Open = hinge * CFrame.Angles(0, -side * math.rad(92), 0)})
    end
    return leaves, locked and leaves[1].Root or nil
end

-- Arma la puerta en el vano. Devuelve {Blocker, Leaves, Lamp, LockParts, Style}.
function DoorModels.Build(parent, spec, frame, width, height, thickness, theme)
    local styleName, style = DoorModels.Style(theme)
    local locked = spec.Locked == true
    local color = locked and style.Locked or style.Color

    local holder = Instance.new("Model")
    holder.Name = (spec.Id or "Door") .. "_Leaves"
    holder.Parent = parent

    local leaves, lockHost = BUILDERS[styleName](holder, frame, width, height, style, color, locked)

    -- Candado y barra cruzada en las trabadas: se caen al abrirlas.
    local lockParts = {}
    if lockHost then
        table.insert(lockParts, detail(lockHost, "LockBar", Vector3.new(width * 0.9, 0.35, 0.7), CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.rad(8)), Color3.fromRGB(70, 66, 60), M("CorrodedMetal")))
        table.insert(lockParts, detail(lockHost, "Padlock", Vector3.new(0.7, 0.9, 0.9), CFrame.new(0, -1.3, 0), Color3.fromRGB(150, 120, 60), M("Metal")))
    end

    -- Luz de estado sobre el vano (fija en el marco): roja trabada, ámbar cerrada,
    -- verde abierta. Las trabadas siempre la tienen, para que se lean de lejos.
    local lamp = nil
    if style.Lamp or locked then
        lamp = PropKit.Part(holder, "StatusLamp", Vector3.new(0.9, 0.4, thickness + 0.6), frame * CFrame.new(0, height + 0.5, 0),
            locked and Color3.fromRGB(200, 40, 34) or Color3.fromRGB(210, 150, 40), M("Neon"))
        PropKit.Part(holder, "LampHousing", Vector3.new(1.2, 0.2, thickness + 0.7), frame * CFrame.new(0, height + 0.25, 0), DARK, M("Metal"))
    end

    return {
        Leaves = leaves,
        Lamp = lamp,
        LockParts = lockParts,
        Style = styleName,
        OpenTime = style.Open,
        CloseTime = style.Close,
        Heavy = style.Motion == "Lift" or style.Motion == "Single",
        Holder = holder,
    }
end

DoorModels.LampColors = {
    Locked = Color3.fromRGB(200, 40, 34),
    Closed = Color3.fromRGB(210, 150, 40),
    Open = Color3.fromRGB(70, 200, 110),
}

return DoorModels
