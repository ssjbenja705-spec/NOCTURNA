-- Máquinas con aspecto industrial: generador con tablero de fusibles que se llena a
-- medida que se insertan, terminal de audio, válvula, Núcleo, salida blindada y la
-- mesita de los documentos. La lógica vive en MechanismService: acá sólo se arma
-- lo que se ve y se reacciona a lo que ese servicio cambia (texto del prompt y
-- color del indicador).
--
-- Cada máquina devuelve (modelo, prompt, indicador). El prompt vive en la pieza
-- principal (PrimaryPart) con el mismo nombre de siempre: Body, Desk, Pipe, Base, Frame.
local PropKit = require(script.Parent.PropKit)

local MachineModels = {}

local Part = PropKit.Part
local M = PropKit.Material
local Shade = PropKit.Shade
local SOLID = PropKit.SOLID
local BALL = PropKit.BALL

local STEEL = Color3.fromRGB(150, 152, 150)
local DARK = Color3.fromRGB(32, 32, 34)
local HAZARD_YELLOW = Color3.fromRGB(206, 168, 40)
local LAMP_OFF = Color3.fromRGB(46, 40, 34)
local AMBER = Color3.fromRGB(236, 160, 60)
local RED = Color3.fromRGB(190, 40, 35)

local function at(x, y, z)
    return CFrame.new(x, y, z)
end

local function piece(parent, base, name, size, offset, color, material, options)
    return Part(parent, name, size, base * offset, color, material, options)
end

local function solid(parent, base, name, size, offset, color, material)
    return Part(parent, name, size, base * offset, color, material, SOLID)
end

local function column(parent, base, name, height, diameter, offset, color, material, isSolid)
    return PropKit.Column(parent, name, height, diameter, base * offset, color, material, isSolid)
end

-- Franja de peligro amarilla y negra, centrada en `offset`, a lo largo de X.
local function hazardStripe(parent, base, offset, length, height)
    piece(parent, base, "Hazard", Vector3.new(length, height, 0.05), offset, HAZARD_YELLOW, M("SmoothPlastic"))
    local count = math.max(2, math.floor(length / 1.2))
    for index = 1, count do
        local x = -length / 2 + (index - 0.5) * length / count
        piece(parent, base, "HazardBar", Vector3.new(0.28, height * 0.95, 0.06), offset * at(x, 0, -0.01) * CFrame.Angles(0, 0, math.rad(40)), DARK, M("SmoothPlastic"))
    end
end

local function lamp(parent, base, name, offset, color)
    return piece(parent, base, name, Vector3.new(0.34, 0.34, 0.34), offset, color, M("Neon"), BALL)
end

-- El indicador cambia de color cuando MechanismService da la máquina por terminada.
local function onIndicatorChanged(indicator, callback)
    indicator:GetPropertyChangedSignal("Color"):Connect(function()
        callback(indicator.Color)
    end)
end

local function model(parent, name)
    return PropKit.Model(parent, name)
end

-- Generador -----------------------------------------------------------------------------

-- Cuántos fusibles dice el prompt que ya entraron: "Generador (2/3)".
function MachineModels.InsertedFuses(prompt)
    return tonumber(string.match(prompt.ObjectText, "%((%d+)/%d+%)")) or 0
end

function MachineModels.Generator(parent, feature, base)
    local holder = model(parent, feature.Id)
    local paint = Color3.fromRGB(70, 78, 60)

    local body = solid(holder, base, "Body", Vector3.new(5.2, 3.6, 3.2), at(0.4, 2.2, 0.4), paint, M("Metal"))
    holder.PrimaryPart = body

    local meshed = PropKit.Visual(holder, "Generator", base, function(target)
        solid(target, base, "Skid", Vector3.new(6.4, 0.4, 4), at(0, 0.2, 0), Color3.fromRGB(52, 54, 56), M("DiamondPlate"))
        piece(target, base, "Roof", Vector3.new(5.4, 0.25, 3.4), at(0.4, 4.12, 0.4), Shade(paint, 0.85), M("Metal"))
        for index = 1, 3 do
            piece(target, base, "Louver", Vector3.new(1.8, 0.12, 0.05), at(1.9, 1.3 + index * 0.45, -1.22), DARK, M("Metal"))
        end
        PropKit.Cylinder(target, "FuelTank", 3.4, 1.3, base * at(0.6, 4.9, 0.9), Color3.fromRGB(120, 42, 34), M("Metal"), true)
        column(target, base, "Exhaust", 2.6, 0.4, at(2.5, 5.6, 1.4), Color3.fromRGB(60, 46, 38), M("CorrodedMetal"))
        PropKit.Cylinder(target, "Muffler", 1.4, 0.8, base * at(2.1, 4.6, 1.4), Color3.fromRGB(70, 52, 42), M("CorrodedMetal"))
        hazardStripe(target, base, at(0, 0.2, -2.03), 6.2, 0.38)
        for _, x in ipairs({-0.4, -1.6}) do
            piece(target, base, "Cable", Vector3.new(0.14, 1.5, 0.14), at(x, 0.95, -1.5) * CFrame.Angles(0.15, 0, 0), DARK, M("Rubber"))
        end
    end)
    if meshed then
        body.Transparency = 1
    end

    -- Tablero de fusibles abierto: cada ranura muestra su fusible cuando entra.
    local panel = at(-1, 2.7, -1.45)
    local panelColor = Color3.fromRGB(118, 122, 120)
    PropKit.Visual(holder, "FusePanel", base * panel * at(0, -1.2, 0), function(target)
        solid(target, base, "PanelBox", Vector3.new(2.4, 2.4, 0.5), panel, panelColor, M("Metal"))
        piece(target, base, "PanelDoor", Vector3.new(2.3, 2.3, 0.06), at(-2.2, 2.7, -1.72) * CFrame.Angles(0, math.rad(115), 0) * at(1.15, 0, 0), Shade(panelColor, 0.9), M("Metal"))
        piece(target, base, "Label", Vector3.new(0.9, 0.3, 0.02), at(-1, 3.75, -1.71), HAZARD_YELLOW, M("SmoothPlastic"))
    end)

    local slots = {}
    local count = math.max(1, feature.Fuses or 1)
    for index = 1, count do
        local x = -1 + (index - (count + 1) / 2) * 0.62
        piece(holder, base, "Slot", Vector3.new(0.42, 1.5, 0.1), at(x, 2.55, -1.74), Color3.fromRGB(40, 34, 30), M("Plastic"))
        local glass = column(holder, base, "SlotFuse", 1.2, 0.3, at(x, 2.55, -1.86), Color3.fromRGB(205, 220, 222), M("Glass"))
        local filament = column(holder, base, "SlotFilament", 1.18, 0.05, at(x, 2.55, -1.86), Color3.fromRGB(255, 168, 76), M("Neon"))
        glass.Transparency = 1
        filament.Transparency = 1
        table.insert(slots, {Glass = glass, Filament = filament})
    end

    local indicator = lamp(holder, base, "Indicator", at(-0.1, 3.75, -1.74), RED)
    local ready = lamp(holder, base, "Ready", at(-0.55, 3.75, -1.74), LAMP_OFF)
    local glow = PropKit.Light(indicator, "PointLight", RED, 0.5, 6, false)

    local prompt = PropKit.AddPrompt(body, "Insertar fusible", feature.Label, 1)

    local function refresh()
        local inserted = MachineModels.InsertedFuses(prompt)
        for index, slot in ipairs(slots) do
            local filled = index <= inserted
            slot.Glass.Transparency = filled and 0.45 or 1
            slot.Filament.Transparency = filled and 0.3 or 1
        end
        ready.Color = inserted >= #slots and AMBER or LAMP_OFF
    end
    prompt:GetPropertyChangedSignal("ObjectText"):Connect(refresh)

    onIndicatorChanged(indicator, function(color)
        glow.Color = color
        glow.Brightness = 0.9
        ready.Color = AMBER
        -- El motor en marcha: los fusibles quedan encendidos.
        for _, slot in ipairs(slots) do
            slot.Glass.Transparency = 0.45
            slot.Filament.Transparency = 0
        end
    end)

    return holder, prompt, indicator
end

-- Terminal de audio / análisis --------------------------------------------------------

function MachineModels.Terminal(parent, feature, base)
    local holder = model(parent, feature.Id)
    local console = Color3.fromRGB(64, 68, 74)

    local desk = solid(holder, base, "Desk", Vector3.new(5, 2.6, 2.5), at(0, 1.3, 0), console, M("Metal"))
    holder.PrimaryPart = desk

    local meshed = PropKit.Visual(holder, "Terminal", base, function(target)
        piece(target, base, "Panel", Vector3.new(5, 0.2, 1.4), at(0, 2.75, -0.35) * CFrame.Angles(math.rad(14), 0, 0), Shade(console, 0.8), M("Metal"))
        piece(target, base, "Buttons", Vector3.new(2.4, 0.08, 0.3), at(-0.8, 2.92, -0.55) * CFrame.Angles(math.rad(14), 0, 0), Color3.fromRGB(120, 60, 40), M("Plastic"))
        for _, x in ipairs({1.2, 1.8}) do
            PropKit.Column(target, "Knob", 0.12, 0.3, base * at(x, 2.92, -0.5), STEEL, M("Metal"))
        end
        solid(target, base, "Monitor", Vector3.new(2.6, 2.1, 2), at(0, 3.9, 0.4), Color3.fromRGB(176, 170, 152), M("Plastic"))
        piece(target, base, "Keyboard", Vector3.new(2.4, 0.12, 0.8), at(0, 2.68, -0.9), Color3.fromRGB(150, 146, 132), M("Plastic"))
        solid(target, base, "TapeDeck", Vector3.new(1.2, 0.8, 1.2), at(-1.9, 3, 0.4), DARK, M("Plastic"))
        piece(target, base, "Grille", Vector3.new(1, 0.6, 0.04), at(-1.9, 3, -0.22), Color3.fromRGB(70, 70, 72), M("DiamondPlate"))
        piece(target, base, "Cable", Vector3.new(0.12, 2.6, 0.12), at(0.8, 1.6, 1.3) * CFrame.Angles(0.2, 0, 0.1), DARK, M("Rubber"))
    end)
    if meshed then
        desk.Transparency = 1
    end

    local screen = piece(holder, base, "Screen", Vector3.new(2.1, 1.6, 0.06), at(0, 3.95, -0.62), Color3.fromRGB(32, 92, 76), M("Neon"))
    screen.Transparency = 0.2
    local glow = PropKit.Light(screen, "PointLight", Color3.fromRGB(90, 200, 160), 0.6, 9, false)
    onIndicatorChanged(screen, function(color)
        glow.Color = color
    end)

    return holder, PropKit.AddPrompt(desk, feature.Prompt or "Usar", feature.Label, feature.Hold), screen
end

-- Válvula de contención -----------------------------------------------------------------

function MachineModels.Valve(parent, feature, base)
    local holder = model(parent, feature.Id)
    local rust = Color3.fromRGB(110, 70, 52)

    local pipe = column(holder, base, "Pipe", 6, 1.4, at(0, 3, 0.6), rust, M("CorrodedMetal"), true)
    holder.PrimaryPart = pipe

    local meshed = PropKit.Visual(holder, "Valve", base, function(target)
        column(target, base, "PipeUpper", 7, 1.4, at(0, 9.5, 0.6), rust, M("CorrodedMetal"), true)
        for _, y in ipairs({0.15, 6, 12.85}) do
            column(target, base, "Flange", 0.3, 2, at(0, y, 0.6), Shade(rust, 0.8), M("Metal"))
        end
        solid(target, base, "ValveBody", Vector3.new(1.8, 1.6, 1.8), at(0, 3.6, 0.6), Color3.fromRGB(70, 72, 74), M("Metal"))
        PropKit.Cylinder(target, "Stem", 1.2, 0.3, base * at(0, 3.6, -0.6) * CFrame.Angles(0, math.rad(90), 0), STEEL, M("Metal"))
        PropKit.Cylinder(target, "Branch", 3, 1, base * at(0, 8.5, 1.8) * CFrame.Angles(0, math.rad(90), 0), rust, M("CorrodedMetal"))
        PropKit.Cylinder(target, "Gauge", 0.15, 0.9, base * at(0.95, 5, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(230, 226, 210), M("SmoothPlastic"))
        piece(target, base, "Needle", Vector3.new(0.04, 0.35, 0.02), at(0.95, 5.08, -0.09) * CFrame.Angles(0, 0, 0.6), RED, M("SmoothPlastic"))
        piece(target, base, "Tag", Vector3.new(0.5, 0.7, 0.02), at(-0.5, 2.9, -0.15) * CFrame.Angles(0, 0, 0.12), HAZARD_YELLOW, M("Cardboard"))
    end)
    if meshed then
        pipe.Transparency = 1
    end

    local wheelFrame = base * at(0, 3.6, -1.25) * CFrame.Angles(0, math.rad(90), 0)
    local wheel = PropKit.Cylinder(holder, "Wheel", 0.18, 2.6, wheelFrame, Color3.fromRGB(170, 50, 45), M("Metal"))
    for _, angle in ipairs({45, 135}) do
        Part(holder, "Spoke", Vector3.new(0.12, 2.4, 0.16), wheelFrame * at(-0.1, 0, 0) * CFrame.Angles(math.rad(angle), 0, 0), Shade(STEEL, 0.8), M("Metal"))
    end

    return holder, PropKit.AddPrompt(pipe, feature.Prompt or "Cerrar", "Válvula de contención", feature.Hold), wheel
end

-- Núcleo de contención -----------------------------------------------------------------

function MachineModels.Core(parent, feature, base)
    local holder = model(parent, feature.Id)

    local platform = solid(holder, base, "Base", Vector3.new(7, 1.5, 7), at(0, 0.75, 0), Color3.fromRGB(44, 46, 56), M("DiamondPlate"))
    holder.PrimaryPart = platform

    local meshed = PropKit.Visual(holder, "Core", base, function(target)
        local glass = column(target, base, "Containment", 8, 3.6, at(0, 5.5, 0), Color3.fromRGB(170, 190, 210), M("Glass"), true)
        glass.Transparency = 0.6
        column(target, base, "RingBottom", 0.6, 4.4, at(0, 1.8, 0), STEEL, M("Metal"))
        column(target, base, "Cap", 0.8, 4.4, at(0, 9.9, 0), STEEL, M("Metal"))
        for _, x in ipairs({-2.1, 2.1}) do
            for _, z in ipairs({-2.1, 2.1}) do
                piece(target, base, "Strut", Vector3.new(0.35, 8, 0.35), at(x, 5.8, z), Color3.fromRGB(70, 72, 80), M("Metal"))
            end
        end
        for _, x in ipairs({-0.8, 0.8}) do
            piece(target, base, "Cable", Vector3.new(0.3, 2.8, 0.3), at(x, 11.7, 0.4), DARK, M("Rubber"))
        end
        solid(target, base, "Console", Vector3.new(2.4, 2.8, 1.2), at(2.4, 2.9, -2.6), Color3.fromRGB(60, 62, 70), M("Metal"))
        piece(target, base, "ConsoleScreen", Vector3.new(1.8, 1, 0.05), at(2.4, 3.6, -3.22), Color3.fromRGB(60, 40, 90), M("Neon"))
    end)
    if meshed then
        platform.Transparency = 1
    end

    local core = column(holder, base, "Column", 7.6, 2, at(0, 5.5, 0), Color3.fromRGB(120, 60, 170), M("Neon"))
    core.Transparency = 0.25
    local glow = PropKit.Light(core, "PointLight", Color3.fromRGB(150, 90, 230), 1.2, 22, false)
    onIndicatorChanged(core, function(color)
        glow.Color = color
    end)

    return holder, PropKit.AddPrompt(platform, feature.Prompt, feature.Label, feature.Hold), core
end

-- Salida blindada (ascensor de servicio o compuerta) ----------------------------------------

function MachineModels.Exit(parent, feature, base)
    local holder = model(parent, feature.Id)
    local steel = Color3.fromRGB(58, 60, 64)

    local frame = solid(holder, base, "Frame", Vector3.new(7, 8, 0.6), at(0, 4, 0.6), steel, M("Metal"))
    holder.PrimaryPart = frame

    local leaves = {}
    local meshed = PropKit.Visual(holder, "ExitDoor", base, function(target)
        for _, side in ipairs({-1, 1}) do
            solid(target, base, "Jamb", Vector3.new(1, 9.2, 1.6), at(side * 4, 4.6, 0.2), Color3.fromRGB(84, 86, 90), M("Metal"))
        end
        solid(target, base, "Header", Vector3.new(9, 1.2, 1.6), at(0, 9.6, 0.2), Color3.fromRGB(84, 86, 90), M("Metal"))
        hazardStripe(target, base, at(0, 9.6, -0.63), 8.6, 0.6)
        piece(target, base, "Threshold", Vector3.new(8, 0.1, 2), at(0, 0.05, -0.8), Color3.fromRGB(90, 92, 94), M("DiamondPlate"))
        for _, side in ipairs({-1, 1}) do
            local leaf = solid(target, base, "Leaf", Vector3.new(3.45, 7.8, 0.35), at(side * 1.75, 3.9, -0.1), Color3.fromRGB(122, 126, 128), M("Metal"))
            local rib = piece(target, base, "Rib", Vector3.new(3.2, 0.25, 0.1), at(side * 1.75, 4, -0.32), Color3.fromRGB(96, 98, 100), M("Metal"))
            table.insert(leaves, {Side = side, Parts = {leaf, rib}})
        end
        piece(target, base, "CallBox", Vector3.new(0.8, 1.2, 0.3), at(4.9, 4, -0.4), DARK, M("Metal"))
    end)
    if meshed then
        frame.Transparency = 1
    end

    local warnings = {}
    for _, side in ipairs({-1, 1}) do
        table.insert(warnings, lamp(holder, base, "WarningLamp", at(side * 3.6, 9.6, -0.75), RED))
    end
    local warningLight = PropKit.Light(warnings[1], "PointLight", RED, 0.8, 12, false)

    local panel = piece(holder, base, "Panel", Vector3.new(0.4, 0.4, 0.08), at(4.9, 4.1, -0.58), Color3.fromRGB(200, 170, 60), M("Neon"))

    -- Al usarse la salida, las luces pasan a verde y las hojas se corren.
    onIndicatorChanged(panel, function(color)
        warningLight.Color = color
        for _, warning in ipairs(warnings) do
            warning.Color = color
        end
        for _, leaf in ipairs(leaves) do
            for _, item in ipairs(leaf.Parts) do
                item.CFrame = item.CFrame * at(leaf.Side * 1.6, 0, 0)
            end
        end
    end)

    local label = feature.Id == "ELEVATOR" and "Ascensor de servicio" or "Salida"
    return holder, PropKit.AddPrompt(frame, feature.Prompt, label, feature.Hold), panel
end

-- Mesita de documentos -----------------------------------------------------------------------

function MachineModels.Document(parent, title, base)
    local holder = model(parent, "Document")
    local wood = Color3.fromRGB(70, 56, 44)

    PropKit.Visual(holder, "DocumentTable", base, function(target)
        solid(target, base, "Table", Vector3.new(3, 0.18, 2), at(0, 2.31, 0), wood, M("Wood"))
        for _, side in ipairs({-1, 1}) do
            solid(target, base, "TableSide", Vector3.new(0.18, 2.22, 1.8), at(side * 1.35, 1.11, 0), Shade(wood, 0.85), M("Wood"))
        end
        piece(target, base, "Folder", Vector3.new(1.5, 0.04, 1.9), at(-0.1, 2.42, 0) * CFrame.Angles(0, 0.15, 0), Color3.fromRGB(184, 154, 98), M("Cardboard"))
        PropKit.Column(target, "LampBase", 0.12, 0.5, base * at(1.1, 2.46, 0.6), DARK, M("Metal"))
        PropKit.Column(target, "LampShade", 0.5, 0.7, base * at(1.1, 3.2, 0.6), Color3.fromRGB(60, 80, 60), M("Metal"))
    end)

    local sheet = piece(holder, base, "Sheet", Vector3.new(1.3, 0.05, 1.7), at(0, 2.47, 0) * CFrame.Angles(0, 0.3, 0), Color3.fromRGB(225, 218, 190), M("SmoothPlastic"))
    holder.PrimaryPart = sheet

    -- La lámpara de escritorio es la pista para encontrarlo.
    PropKit.Light(sheet, "PointLight", Color3.fromRGB(240, 220, 170), 0.55, 8, false)

    return holder, PropKit.AddPrompt(sheet, "Leer", title, 0.2)
end

return MachineModels
