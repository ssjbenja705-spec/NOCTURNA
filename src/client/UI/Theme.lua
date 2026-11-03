-- Estilo común de la interfaz y utilidades para pantallas adaptables.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Theme = {}

Theme.Colors = {
    Panel = Color3.fromRGB(9, 11, 15),
    PanelLight = Color3.fromRGB(26, 30, 38),
    Button = Color3.fromRGB(44, 50, 62),
    ButtonActive = Color3.fromRGB(120, 58, 52),
    Text = Color3.fromRGB(232, 232, 236),
    TextDim = Color3.fromRGB(160, 166, 176),
    Accent = Color3.fromRGB(196, 158, 96),
    Health = Color3.fromRGB(176, 58, 54),
    Stamina = Color3.fromRGB(160, 186, 178),
    Battery = Color3.fromRGB(208, 186, 92),
    Danger = Color3.fromRGB(200, 50, 44),
    Paper = Color3.fromRGB(222, 212, 186),
    Ink = Color3.fromRGB(34, 30, 26),
}

Theme.IsTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local DESIGN_WIDTH = 1000
local DESIGN_HEIGHT = 520

local function computeScale(viewport)
    return math.clamp(math.min(viewport.X / DESIGN_WIDTH, viewport.Y / DESIGN_HEIGHT), 0.62, 1.35)
end

-- Crea una instancia aplicando propiedades.
function Theme.New(className, properties, parent)
    local instance = Instance.new(className)
    for key, value in pairs(properties or {}) do
        instance[key] = value
    end
    instance.Parent = parent
    return instance
end

-- Cada pantalla tiene una raíz cuyo tamaño compensa el UIScale, de modo que los
-- anclajes a las esquinas se mantienen en cualquier resolución.
function Theme.Screen(name, displayOrder)
    local gui = Theme.New("ScreenGui", {
        Name = name,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = displayOrder or 0,
    }, player:WaitForChild("PlayerGui"))

    local root = Theme.New("Frame", {
        Name = "Root",
        BackgroundTransparency = 1,
    }, gui)
    local scale = Theme.New("UIScale", {}, root)

    local function update()
        local camera = workspace.CurrentCamera
        if not camera then
            return
        end
        local factor = computeScale(camera.ViewportSize)
        scale.Scale = factor
        root.Size = UDim2.fromScale(1 / factor, 1 / factor)
    end

    update()
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(update)
    if workspace.CurrentCamera then
        workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
    end

    return root, gui
end

function Theme.Corner(parent, radius)
    return Theme.New("UICorner", {CornerRadius = UDim.new(0, radius or 8)}, parent)
end

function Theme.Panel(parent, properties)
    local merged = {
        BackgroundColor3 = Theme.Colors.Panel,
        BackgroundTransparency = 0.18,
        BorderSizePixel = 0,
    }
    for key, value in pairs(properties or {}) do
        merged[key] = value
    end

    local panel = Theme.New("Frame", merged, parent)
    Theme.Corner(panel)
    return panel
end

function Theme.Label(parent, properties)
    local merged = {
        BackgroundTransparency = 1,
        TextColor3 = Theme.Colors.Text,
        Font = Enum.Font.Gotham,
        TextSize = 14,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Text = "",
    }
    for key, value in pairs(properties or {}) do
        merged[key] = value
    end
    return Theme.New("TextLabel", merged, parent)
end

function Theme.Button(parent, text, properties)
    local merged = {
        BackgroundColor3 = Theme.Colors.Button,
        TextColor3 = Theme.Colors.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        Text = text,
        AutoButtonColor = true,
        BorderSizePixel = 0,
    }
    for key, value in pairs(properties or {}) do
        merged[key] = value
    end

    local button = Theme.New("TextButton", merged, parent)
    Theme.Corner(button, 7)
    return button
end

-- Con cámara en primera persona el mouse está bloqueado: un botón Modal lo libera
-- mientras haya algún menú abierto.
local modalHolders = {}
local modalButton = nil

local function refreshModal()
    if not modalButton then
        local _, gui = Theme.Screen("NocturnaModal", -10)
        modalButton = Theme.New("TextButton", {
            Name = "Modal",
            Size = UDim2.fromOffset(0, 0),
            BackgroundTransparency = 1,
            Text = "",
            Modal = true,
            Visible = false,
        }, gui)
    end
    modalButton.Visible = next(modalHolders) ~= nil
end

function Theme.SetModal(key, enabled)
    modalHolders[key] = enabled and true or nil
    refreshModal()
end

return Theme
