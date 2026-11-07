-- Íconos dibujados con formas de la interfaz, sin imágenes externas: objetos del
-- inventario, botones del HUD y marcas del plano. Todo se mide en proporción al
-- contenedor, así el mismo ícono sirve chico en el plano o grande en un casillero.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ItemConfig = require(Shared.Config.ItemConfig)
local Theme = require(script.Parent.Theme)

local Colors = Theme.Colors

local Icons = {}
local DRAW = {}

local GLASS = Color3.fromRGB(150, 190, 205)
local METAL = Color3.fromRGB(120, 116, 110)
local LEATHER = Color3.fromRGB(92, 60, 38)
local LOCKER = Color3.fromRGB(82, 98, 90)

-- Rectángulo en proporciones del ícono. options: Hollow, Stroke, Thickness,
-- Round (escala del radio), Rotation, Transparency.
local function shape(parent, x, y, width, height, color, options)
    options = options or {}
    local frame = Theme.New("Frame", {
        Name = "Shape",
        Position = UDim2.fromScale(x, y),
        Size = UDim2.fromScale(width, height),
        BackgroundColor3 = color or Colors.Text,
        BackgroundTransparency = options.Hollow and 1 or (options.Transparency or 0),
        BorderSizePixel = 0,
        Rotation = options.Rotation or 0,
    }, parent)
    if options.Round then
        Theme.New("UICorner", {CornerRadius = UDim.new(options.Round, 0)}, frame)
    end
    if options.Stroke then
        Theme.Stroke(frame, options.Stroke, options.Thickness or 1, 0)
    end
    return frame
end

-- Botones del HUD ----------------------------------------------------------------

function DRAW.Inventory(icon)
    shape(icon, 0.33, 0.06, 0.34, 0.3, nil, {Hollow = true, Stroke = Colors.Text, Round = 0.4, Thickness = 2})
    shape(icon, 0.12, 0.28, 0.76, 0.64, LEATHER, {Round = 0.12, Stroke = Colors.Text})
    shape(icon, 0.12, 0.28, 0.76, 0.26, Colors.Grime, {Round = 0.1, Stroke = Colors.Text})
    shape(icon, 0.44, 0.46, 0.12, 0.16, Colors.Accent)
end

function DRAW.Journal(icon)
    shape(icon, 0.2, 0.08, 0.62, 0.84, Colors.Blood, {Round = 0.08, Stroke = Colors.Text})
    shape(icon, 0.2, 0.08, 0.13, 0.84, Colors.Black, {Transparency = 0.3})
    shape(icon, 0.76, 0.14, 0.08, 0.72, Colors.Paper)
    shape(icon, 0.42, 0.28, 0.3, 0.08, Colors.Paper)
    shape(icon, 0.42, 0.42, 0.22, 0.06, Colors.Paper, {Transparency = 0.3})
end

function DRAW.Map(icon)
    shape(icon, 0.06, 0.18, 0.3, 0.64, Colors.Paper, {Rotation = -6})
    shape(icon, 0.35, 0.15, 0.3, 0.64, Colors.TextDim, {Rotation = 6})
    shape(icon, 0.64, 0.18, 0.3, 0.64, Colors.Paper, {Rotation = -6})
    shape(icon, 0.4, 0.44, 0.22, 0.07, Colors.Danger, {Rotation = 45})
    shape(icon, 0.4, 0.44, 0.22, 0.07, Colors.Danger, {Rotation = -45})
end

function DRAW.Settings(icon)
    for row, knob in ipairs({0.26, 0.6, 0.42}) do
        local y = 0.14 + (row - 1) * 0.28
        shape(icon, 0.08, y + 0.06, 0.84, 0.06, Colors.TextDim)
        shape(icon, knob, y, 0.18, 0.18, Colors.Accent, {Stroke = Colors.Black})
    end
end

function DRAW.Admin(icon)
    shape(icon, 0.06, 0.27, 0.88, 0.46, nil, {Hollow = true, Stroke = Colors.Text, Round = 0.5, Thickness = 2})
    shape(icon, 0.36, 0.34, 0.28, 0.32, Colors.Danger, {Round = 0.5})
    shape(icon, 0.45, 0.44, 0.1, 0.12, Colors.Black, {Round = 0.5})
end

-- Objetos -----------------------------------------------------------------------

function DRAW.Battery(icon)
    shape(icon, 0.41, 0.08, 0.18, 0.1, METAL)
    shape(icon, 0.3, 0.17, 0.4, 0.75, Colors.Accent, {Round = 0.15, Stroke = Colors.Black})
    shape(icon, 0.3, 0.6, 0.4, 0.1, Colors.Black, {Transparency = 0.4})
    shape(icon, 0.46, 0.3, 0.08, 0.2, Colors.Black, {Transparency = 0.2})
    shape(icon, 0.4, 0.36, 0.2, 0.08, Colors.Black, {Transparency = 0.2})
end

function DRAW.Medkit(icon)
    shape(icon, 0.37, 0.12, 0.26, 0.16, nil, {Hollow = true, Stroke = Colors.Text, Thickness = 2})
    shape(icon, 0.1, 0.26, 0.8, 0.62, Colors.Paper, {Round = 0.1, Stroke = Colors.Black})
    shape(icon, 0.44, 0.38, 0.12, 0.38, Colors.Danger)
    shape(icon, 0.31, 0.51, 0.38, 0.12, Colors.Danger)
end

function DRAW.Fuse(icon)
    shape(icon, 0.3, 0.1, 0.4, 0.14, METAL, {Stroke = Colors.Black})
    shape(icon, 0.33, 0.24, 0.34, 0.52, GLASS, {Transparency = 0.45, Stroke = Colors.Text})
    shape(icon, 0.48, 0.24, 0.04, 0.52, Colors.Accent)
    shape(icon, 0.3, 0.76, 0.4, 0.14, METAL, {Stroke = Colors.Black})
end

function DRAW.Key(icon)
    shape(icon, 0.08, 0.3, 0.38, 0.38, nil, {Hollow = true, Stroke = Colors.Accent, Round = 0.5, Thickness = 3})
    shape(icon, 0.44, 0.45, 0.48, 0.08, Colors.Accent)
    shape(icon, 0.72, 0.53, 0.07, 0.16, Colors.Accent)
    shape(icon, 0.84, 0.53, 0.07, 0.11, Colors.Accent)
end

function DRAW.Keycard(icon)
    shape(icon, 0.1, 0.24, 0.8, 0.52, Color3.fromRGB(96, 150, 132), {Round = 0.1, Stroke = Colors.Black})
    shape(icon, 0.1, 0.32, 0.8, 0.09, Colors.Black, {Transparency = 0.2})
    shape(icon, 0.18, 0.5, 0.17, 0.14, Colors.Accent)
    shape(icon, 0.6, 0.47, 0.2, 0.22, Colors.Paper)
end

function DRAW.Radio(icon)
    shape(icon, 0.66, 0.06, 0.05, 0.34, METAL, {Rotation = 14})
    shape(icon, 0.12, 0.34, 0.76, 0.54, Color3.fromRGB(58, 56, 54), {Round = 0.1, Stroke = Colors.Text})
    for row = 0, 2 do
        shape(icon, 0.2, 0.44 + row * 0.12, 0.3, 0.05, Colors.Black, {Transparency = 0.1})
    end
    shape(icon, 0.6, 0.48, 0.18, 0.18, Colors.Accent, {Round = 0.5})
end

function DRAW.Sample(icon)
    shape(icon, 0.34, 0.06, 0.32, 0.1, METAL)
    shape(icon, 0.38, 0.15, 0.24, 0.76, GLASS, {Transparency = 0.6, Round = 0.4, Stroke = Colors.Text})
    shape(icon, 0.38, 0.48, 0.24, 0.43, Color3.fromRGB(150, 22, 40), {Round = 0.4})
    shape(icon, 0.45, 0.56, 0.06, 0.08, Colors.Text, {Transparency = 0.4, Round = 0.5})
end

function DRAW.MemoryShard(icon)
    local photo = shape(icon, 0.14, 0.18, 0.72, 0.62, Colors.Paper, {Rotation = -12, Stroke = Colors.Black})
    shape(photo, 0.1, 0.1, 0.8, 0.6, Color3.fromRGB(120, 92, 62))
    shape(photo, 0.3, 0.24, 0.16, 0.3, Color3.fromRGB(70, 50, 34), {Round = 0.5})
    shape(photo, 0.56, 0.3, 0.14, 0.26, Color3.fromRGB(70, 50, 34), {Round = 0.5})
end

-- Marcas del plano --------------------------------------------------------------

function DRAW.Document(icon)
    shape(icon, 0.22, 0.1, 0.56, 0.8, Colors.Paper, {Stroke = Colors.Black, Rotation = 4})
    for row = 0, 2 do
        shape(icon, 0.32, 0.28 + row * 0.16, 0.36, 0.06, Colors.Ink)
    end
end

function DRAW.Locker(icon)
    shape(icon, 0.26, 0.06, 0.48, 0.88, LOCKER, {Stroke = Colors.Black})
    for row = 0, 2 do
        shape(icon, 0.34, 0.16 + row * 0.1, 0.32, 0.05, Colors.Black, {Transparency = 0.2})
    end
    shape(icon, 0.6, 0.55, 0.08, 0.12, Colors.Accent)
end

function DRAW.Mechanism(icon)
    shape(icon, 0.2, 0.2, 0.6, 0.6, Colors.Grime, {Rotation = 45, Stroke = Colors.Accent})
    shape(icon, 0.35, 0.35, 0.3, 0.3, Colors.Accent, {Round = 0.5})
    shape(icon, 0.45, 0.45, 0.1, 0.1, Colors.Black, {Round = 0.5})
end

function DRAW.Exit(icon)
    shape(icon, 0.2, 0.06, 0.6, 0.88, Colors.Exit, {Stroke = Colors.Black})
    shape(icon, 0.32, 0.18, 0.36, 0.76, Colors.Black, {Transparency = 0.15})
    shape(icon, 0.56, 0.5, 0.08, 0.08, Colors.Exit)
end

function DRAW.Objective(icon)
    shape(icon, 0.06, 0.06, 0.88, 0.88, nil, {Hollow = true, Stroke = Colors.Danger, Round = 0.5, Thickness = 2})
    shape(icon, 0.3, 0.3, 0.4, 0.4, nil, {Hollow = true, Stroke = Colors.Danger, Round = 0.5, Thickness = 1})
    shape(icon, 0.42, 0.42, 0.16, 0.16, Colors.Danger, {Round = 0.5})
end

function DRAW.DoorLocked(icon)
    shape(icon, 0.05, 0.42, 0.9, 0.16, Colors.Danger)
    shape(icon, 0.36, 0.16, 0.28, 0.3, nil, {Hollow = true, Stroke = Colors.Text, Round = 0.5, Thickness = 2})
    shape(icon, 0.3, 0.36, 0.4, 0.34, Colors.Text, {Round = 0.1})
end

function DRAW.Door(icon)
    shape(icon, 0.05, 0.44, 0.35, 0.12, Colors.Accent)
    shape(icon, 0.6, 0.44, 0.35, 0.12, Colors.Accent)
end

function DRAW.You(icon)
    shape(icon, 0.25, 0.3, 0.5, 0.5, Colors.Accent, {Rotation = 45, Stroke = Colors.Black})
    shape(icon, 0.44, 0.02, 0.12, 0.42, Colors.Accent)
end

function DRAW.Teammate(icon)
    shape(icon, 0.15, 0.15, 0.7, 0.7, Colors.Text, {Round = 0.5, Stroke = Colors.Black})
end

local function generic(icon, color)
    shape(icon, 0.2, 0.2, 0.6, 0.6, color or Colors.TextDim, {Round = 0.15, Stroke = Colors.Black})
end

-- Dibuja un ícono dentro de un contenedor nuevo. properties se aplican al contenedor.
function Icons.Draw(kind, parent, properties)
    local merged = {
        Name = "Icon",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
    }
    for key, value in pairs(properties or {}) do
        merged[key] = value
    end
    local icon = Theme.New("Frame", merged, parent)

    local draw = DRAW[kind]
    if draw then
        draw(icon)
    else
        local definition = ItemConfig[kind]
        generic(icon, definition and definition.Color)
    end
    return icon
end

function Icons.Has(kind)
    return DRAW[kind] ~= nil
end

return Icons
