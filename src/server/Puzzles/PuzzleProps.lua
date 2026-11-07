-- Utilería física de las pruebas: paneles, válvulas, palancas, pistas pintadas y
-- compuertas. Geometría sólida con materiales reales, liviana para celulares.
local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local PuzzleConfig = require(Shared.Config.PuzzleConfig)

local FeatureBuilder = require(script.Parent.Parent.World.FeatureBuilder)
local RoomGenerator = require(script.Parent.Parent.World.RoomGenerator)

local MAP = GameConfig.Map

local PuzzleProps = {}

PuzzleProps.PendingColor = Color3.fromRGB(190, 48, 40)
PuzzleProps.DoneColor = Color3.fromRGB(70, 190, 110)

local STEEL = Color3.fromRGB(66, 70, 72)
local DARK_STEEL = Color3.fromRGB(38, 40, 43)
local RUST = Color3.fromRGB(104, 66, 48)
local WOOD = Color3.fromRGB(84, 60, 42)

local function part(parent, name, size, cframe, color, material, shape)
    local item = Instance.new("Part")
    item.Name = name
    item.Size = size
    item.CFrame = cframe
    item.Anchored = true
    item.Color = color
    item.Material = material or Enum.Material.Metal
    item.TopSurface = Enum.SurfaceType.Smooth
    item.BottomSurface = Enum.SurfaceType.Smooth
    item.CanTouch = false
    item.CastShadow = false
    if shape then
        item.Shape = shape
    end
    item.Parent = parent
    return item
end

local function detail(parent, name, size, cframe, color, material, shape)
    local item = part(parent, name, size, cframe, color, material, shape)
    item.CanCollide = false
    item.CanQuery = false
    return item
end

local function model(parent, name, kind)
    local holder = Instance.new("Model")
    holder.Name = name
    holder:SetAttribute("NocturnaPuzzle", kind)
    holder.Parent = parent
    return holder
end

local function lamp(holder, cframe)
    local light = detail(holder, "StatusLamp", Vector3.new(0.5, 0.5, 0.5), cframe, PuzzleProps.PendingColor, Enum.Material.Neon, Enum.PartType.Ball)
    local glow = Instance.new("PointLight")
    glow.Color = PuzzleProps.PendingColor
    glow.Brightness = 0.6
    glow.Range = 6
    glow.Shadows = false
    glow.Parent = light
    return light
end

-- Cambia el color de la luz de estado (y de su resplandor).
function PuzzleProps.SetLamp(light, color)
    if not light then
        return
    end
    light.Color = color
    local glow = light:FindFirstChildOfClass("PointLight")
    if glow then
        glow.Color = color
    end
end

local BUILDERS = {}

function BUILDERS.Wires(holder, cframe)
    part(holder, "Post", Vector3.new(0.8, 3, 0.8), cframe * CFrame.new(0, 1.5, 0.4), DARK_STEEL)
    local box = part(holder, "Box", Vector3.new(4, 3.2, 1.2), cframe * CFrame.new(0, 4.4, 0.4), STEEL, Enum.Material.DiamondPlate)
    detail(holder, "Lid", Vector3.new(0.15, 3.2, 2), cframe * CFrame.new(-2.1, 4.4, -0.6) * CFrame.Angles(0, math.rad(-20), 0), STEEL, Enum.Material.Metal)
    detail(holder, "Inside", Vector3.new(3.6, 2.8, 0.1), cframe * CFrame.new(0, 4.4, -0.22), DARK_STEEL, Enum.Material.SmoothPlastic)
    for index = 1, PuzzleConfig.Wires.Count do
        local wire = PuzzleConfig.WireColors[index]
        detail(holder, "Wire", Vector3.new(0.18, 1.6, 0.18), cframe * CFrame.new(-1.3 + (index - 1) * 0.85, 3.8, -0.3) * CFrame.Angles(0.25, 0, 0), wire.Color, Enum.Material.SmoothPlastic)
    end
    return box, lamp(holder, cframe * CFrame.new(1.6, 6.3, 0.2))
end

function BUILDERS.Breakers(holder, cframe)
    local cabinet = part(holder, "Cabinet", Vector3.new(3.6, 6.2, 1.4), cframe * CFrame.new(0, 3.1, 0.5), STEEL, Enum.Material.Metal)
    detail(holder, "Door", Vector3.new(0.12, 5.4, 1.8), cframe * CFrame.new(1.95, 3.2, -0.8) * CFrame.Angles(0, math.rad(25), 0), STEEL, Enum.Material.Metal)
    detail(holder, "Plate", Vector3.new(3, 4.6, 0.1), cframe * CFrame.new(0, 3.3, -0.25), DARK_STEEL, Enum.Material.SmoothPlastic)
    for index = 1, PuzzleConfig.Breakers.Count do
        detail(holder, "Switch", Vector3.new(0.45, 0.9, 0.35), cframe * CFrame.new(-1.05 + (index - 1) * 0.7, 3.4, -0.4), Color3.fromRGB(20, 20, 22), Enum.Material.SmoothPlastic)
    end
    detail(holder, "Warning", Vector3.new(1.6, 0.6, 0.05), cframe * CFrame.new(0, 5.4, -0.32), Color3.fromRGB(214, 176, 40), Enum.Material.SmoothPlastic)
    return cabinet, lamp(holder, cframe * CFrame.new(1.2, 5.4, -0.35))
end

function BUILDERS.Valves(holder, cframe)
    local manifold = part(holder, "Manifold", Vector3.new(6, 1.4, 1.4), cframe * CFrame.new(0, 2.2, 0.4), RUST, Enum.Material.CorrodedMetal)
    for index = 1, PuzzleConfig.Valves.Count do
        local x = -2 + (index - 1) * 2
        part(holder, "Pipe", Vector3.new(0.9, 6, 0.9), cframe * CFrame.new(x, 3, 0.4), RUST, Enum.Material.CorrodedMetal)
        detail(holder, "Wheel", Vector3.new(0.3, 1.6, 1.6), cframe * CFrame.new(x, 3.6, -0.3) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(160, 44, 40), Enum.Material.Metal, Enum.PartType.Cylinder)
        detail(holder, "Gauge", Vector3.new(0.2, 0.9, 0.9), cframe * CFrame.new(x, 5.2, -0.15) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(220, 220, 210), Enum.Material.Glass, Enum.PartType.Cylinder)
    end
    return manifold, lamp(holder, cframe * CFrame.new(0, 6.4, 0.4))
end

function BUILDERS.Keypad(holder, cframe)
    local panel = part(holder, "Panel", Vector3.new(2.6, 4.4, 0.8), cframe * CFrame.new(0, 3.4, 0.6), DARK_STEEL, Enum.Material.Metal)
    detail(holder, "Screen", Vector3.new(1.8, 0.6, 0.1), cframe * CFrame.new(0, 4.8, 0.16), Color3.fromRGB(40, 120, 90), Enum.Material.Neon)
    for row = 1, 4 do
        for column = 1, 3 do
            detail(holder, "Key", Vector3.new(0.42, 0.36, 0.12), cframe * CFrame.new(-0.55 + (column - 1) * 0.55, 4.1 - row * 0.5, 0.16), Color3.fromRGB(150, 150, 146), Enum.Material.SmoothPlastic)
        end
    end
    return panel, lamp(holder, cframe * CFrame.new(0.95, 5.35, 0.16))
end

function BUILDERS.Power(holder, cframe)
    local bench = part(holder, "Bench", Vector3.new(5, 2.8, 2.8), cframe * CFrame.new(0, 1.4, 0), DARK_STEEL, Enum.Material.DiamondPlate)
    detail(holder, "Board", Vector3.new(4.4, 0.2, 2.4), cframe * CFrame.new(0, 2.9, 0), Color3.fromRGB(30, 34, 30), Enum.Material.Slate)
    local config = PuzzleConfig.Power
    for column = 1, config.Columns do
        for row = 1, config.Rows do
            detail(holder, "Tile", Vector3.new(0.85, 0.12, 0.6), cframe * CFrame.new(-1.6 + (column - 1) * 1.05, 3.05, -0.75 + (row - 1) * 0.75), Color3.fromRGB(120, 112, 90), Enum.Material.Metal)
        end
    end
    detail(holder, "Coil", Vector3.new(0.8, 1.6, 1.6), cframe * CFrame.new(2.9, 0.8, 0.6) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(40, 40, 40), Enum.Material.Rubber, Enum.PartType.Cylinder)
    return bench, lamp(holder, cframe * CFrame.new(2.1, 3.3, -1))
end

function BUILDERS.Simon(holder, cframe)
    local console = part(holder, "Console", Vector3.new(4, 3, 2.2), cframe * CFrame.new(0, 1.5, 0.2), Color3.fromRGB(58, 60, 66), Enum.Material.Metal)
    detail(holder, "Speaker", Vector3.new(2.6, 2, 0.4), cframe * CFrame.new(0, 4, 1), Color3.fromRGB(30, 30, 32), Enum.Material.Fabric)
    for index, button in ipairs(PuzzleConfig.Simon.Buttons) do
        local x = index <= 2 and -0.7 or 0.7
        local z = index % 2 == 1 and -0.45 or 0.45
        detail(holder, "Button", Vector3.new(0.3, 0.9, 0.9), cframe * CFrame.new(x, 3.1, z) * CFrame.Angles(0, 0, math.rad(90)), button.Color, Enum.Material.Neon, Enum.PartType.Cylinder)
    end
    return console, lamp(holder, cframe * CFrame.new(1.7, 3.2, -0.8))
end

function BUILDERS.Memory(holder, cframe)
    local table_ = part(holder, "Table", Vector3.new(4, 2.6, 2.6), cframe * CFrame.new(0, 1.3, 0), WOOD, Enum.Material.WoodPlanks)
    detail(holder, "ShoeBox", Vector3.new(1.6, 0.7, 1.1), cframe * CFrame.new(-1, 2.95, 0.4), Color3.fromRGB(150, 120, 86), Enum.Material.Fabric)
    for index = 1, 6 do
        detail(holder, "Photo", Vector3.new(0.7, 0.05, 0.5), cframe * CFrame.new(0.2 + (index % 3) * 0.6, 2.63, -0.6 + math.floor((index - 1) / 3) * 0.6) * CFrame.Angles(0, index * 0.4, 0), Color3.fromRGB(226, 218, 196), Enum.Material.SmoothPlastic)
    end
    return table_, lamp(holder, cframe * CFrame.new(-1.7, 2.9, -1))
end

-- Una palanca: devuelve la base y el mango, que gira al bajarla.
function BUILDERS.Levers(holder, cframe)
    local base = part(holder, "Base", Vector3.new(2, 3.6, 1.2), cframe * CFrame.new(0, 1.8, 0.4), STEEL, Enum.Material.DiamondPlate)
    detail(holder, "Slot", Vector3.new(0.4, 2.2, 0.1), cframe * CFrame.new(0, 2.6, -0.22), Color3.fromRGB(12, 12, 12), Enum.Material.SmoothPlastic)
    detail(holder, "Stripe", Vector3.new(2.02, 0.4, 1.22), cframe * CFrame.new(0, 0.6, 0.4), Color3.fromRGB(214, 176, 40), Enum.Material.SmoothPlastic)
    local pivot = cframe * CFrame.new(0, 2.6, -0.3)
    local handle = detail(holder, "Handle", Vector3.new(0.35, 2.4, 0.35), pivot * CFrame.Angles(math.rad(-30), 0, 0) * CFrame.new(0, 1.2, 0), Color3.fromRGB(60, 60, 62), Enum.Material.Metal)
    handle:SetAttribute("Pivot", pivot)
    return base, lamp(holder, cframe * CFrame.new(0, 4, 0.4)), handle
end

-- Pone el mango arriba o abajo.
function PuzzleProps.SetLever(handle, down)
    local pivot = handle and handle:GetAttribute("Pivot")
    if typeof(pivot) ~= "CFrame" then
        return
    end
    local angle = down and math.rad(150) or math.rad(-30)
    handle.CFrame = pivot * CFrame.Angles(angle, 0, 0) * CFrame.new(0, 1.2, 0)
end

-- Construye la utilería de una prueba. Devuelve modelo, prompt, luz de estado y,
-- para las palancas, el mango.
function PuzzleProps.Build(folder, feature, cframe)
    local kind = feature.Puzzle
    local holder = model(folder, feature.Id, kind)
    local primary, light, extra = BUILDERS[kind](holder, cframe)
    holder.PrimaryPart = primary

    local definition = PuzzleConfig.Types[kind]
    local hold = feature.Hold or (kind == "Levers" and PuzzleConfig.Levers.Hold or 0.4)
    local prompt = FeatureBuilder.AddPrompt(primary, feature.Prompt or "Usar", feature.Label or definition.Title, hold)
    return holder, prompt, light, extra
end

-- Pista pintada en la pared, con un prompt para examinarla de cerca.
function PuzzleProps.Clue(folder, feature, cframe, text)
    local holder = Instance.new("Model")
    holder.Name = feature.Id
    holder:SetAttribute("NocturnaClueFor", feature.For)
    holder.Parent = folder

    local board = part(holder, "Wall", Vector3.new(5, 4, 0.4), cframe * CFrame.new(0, 4.5, 0.6), Color3.fromRGB(150, 146, 136), Enum.Material.Concrete)
    holder.PrimaryPart = board

    local gui = Instance.new("SurfaceGui")
    gui.Name = "Paint"
    gui.Face = Enum.NormalId.Front
    gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    gui.PixelsPerStud = 40
    gui.LightInfluence = 1
    gui.Parent = board

    local label = Instance.new("TextLabel")
    label.Name = "Text"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.PermanentMarker
    label.TextScaled = true
    label.TextColor3 = Color3.fromRGB(140, 24, 22)
    label.Text = text
    label.Parent = gui

    return holder, FeatureBuilder.AddPrompt(board, "Examinar", feature.Label or "Algo escrito en la pared", 0.3)
end

-- Compuerta de una prueba sobre la abertura entre dos celdas. Devuelve la hoja y su luz.
function PuzzleProps.Gate(folder, layout, spec)
    local midpoint, horizontal = RoomGenerator.EdgeInfo(layout, spec.A, spec.B)
    local width = MAP.CorridorWidth + 0.4
    local height = MAP.OpeningHeight
    local size = horizontal and Vector3.new(width, height, 1.2) or Vector3.new(1.2, height, width)
    local closed = midpoint + Vector3.new(0, height / 2, 0)

    local holder = Instance.new("Model")
    holder.Name = spec.Id or "Gate"
    holder:SetAttribute("NocturnaGate", true)
    holder.Parent = folder

    local shutter = part(holder, "Shutter", size, CFrame.new(closed), Color3.fromRGB(58, 60, 58), Enum.Material.DiamondPlate)
    holder.PrimaryPart = shutter

    -- Franjas de peligro soldadas a la hoja: suben con ella.
    local along = horizontal and Vector3.new(1, 0, 0) or Vector3.new(0, 0, 1)
    for index = -1, 1 do
        local stripe = Instance.new("Part")
        stripe.Name = "Stripe"
        stripe.Size = horizontal and Vector3.new(width - 0.6, 0.5, 1.3) or Vector3.new(1.3, 0.5, width - 0.6)
        stripe.CFrame = CFrame.new(closed + Vector3.new(0, index * 2.6, 0))
        stripe.Color = index == 0 and Color3.fromRGB(20, 20, 20) or Color3.fromRGB(214, 176, 40)
        stripe.Material = Enum.Material.SmoothPlastic
        stripe.Anchored = true
        stripe.CanCollide = false
        stripe.CanQuery = false
        stripe.CanTouch = false
        stripe.CastShadow = false
        stripe.Parent = shutter
    end

    local light = lamp(holder, CFrame.new(midpoint + Vector3.new(0, height + 0.8, 0) + along * (width / 2 - 1)))
    return holder, shutter, light
end

return PuzzleProps
