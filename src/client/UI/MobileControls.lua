-- Botones táctiles grandes, separados del joystick y de la zona de cámara.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local MovementInput = require(script.Parent.Parent.Movement.MovementInput)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer
local Colors = Theme.Colors
local SIZE = 76

local MobileControls = {}

local function roundButton(parent, text, position, size)
    local button = Theme.Button(parent, text, {
        AnchorPoint = Vector2.new(1, 1),
        Position = position,
        Size = UDim2.fromOffset(size or SIZE, size or SIZE),
        BackgroundColor3 = Colors.Panel,
        BackgroundTransparency = 0.25,
        TextSize = 12,
        TextWrapped = true,
    })
    Theme.Corner(button, (size or SIZE) / 2)
    return button
end

local function holdButton(button, onChange)
    local function setActive(active)
        button.BackgroundColor3 = active and Colors.ButtonActive or Colors.Panel
        onChange(active)
    end

    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            setActive(true)
        end
    end)
    button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            setActive(false)
        end
    end)
end

-- Botón SALIR del escondite: en su propia pantalla, por encima de la viñeta y del
-- HUD, para que nada lo tape. En PC además libera el mouse y recuerda la tecla E.
local function buildExitHide()
    local root = Theme.Screen("NocturnaHide", 6)
    local exitHide = Theme.Button(root, Theme.IsTouch and "SALIR" or "SALIR  [E]", {
        Name = "ExitHide",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, Theme.IsTouch and -36 or -40),
        Size = UDim2.fromOffset(Theme.IsTouch and 230 or 200, Theme.IsTouch and 76 or 54),
        BackgroundColor3 = Colors.ButtonActive,
        BackgroundTransparency = 0.1,
        TextSize = Theme.IsTouch and 24 or 18,
        Visible = false,
    })
    Theme.New("UIStroke", {Color = Colors.Accent, Thickness = 2, Transparency = 0.2}, exitHide)

    local hint = Theme.Label(root, {
        Name = "HideHint",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, Theme.IsTouch and -120 or -100),
        Size = UDim2.fromOffset(420, 24),
        Text = "Escondido. Si no te vieron entrar, no te encuentran.",
        TextXAlignment = Enum.TextXAlignment.Center,
        TextColor3 = Colors.TextDim,
        Visible = false,
    })

    exitHide.Activated:Connect(function()
        Remotes.FireServer("ExitHiding")
    end)

    local function show(hidden)
        exitHide.Visible = hidden
        hint.Visible = hidden
        Theme.SetModal("Hide", hidden)
    end

    Remotes.OnClient("HideState", function(hidden)
        show(hidden == true)
    end)
    -- El atributo lo pone el servidor: si por algo se pierde el aviso, igual se corrige.
    player:GetAttributeChangedSignal("Hidden"):Connect(function()
        show(player:GetAttribute("Hidden") == true)
    end)
end

function MobileControls.Start()
    local root = Theme.Screen("NocturnaTouch", 2)
    buildExitHide()

    if not Theme.IsTouch then
        return
    end

    local holder = Theme.New("Frame", {
        Name = "TouchActions",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
    }, root)

    local sprint = roundButton(holder, "CORRER", UDim2.new(1, -24, 1, -28))
    local crouch = roundButton(holder, "SIGILO", UDim2.new(1, -112, 1, -28))
    local light = roundButton(holder, "LUZ", UDim2.new(1, -24, 1, -116))

    holdButton(sprint, MovementInput.SetSprinting)
    crouch.Activated:Connect(function()
        crouch.BackgroundColor3 = MovementInput.ToggleCrouch() and Colors.ButtonActive or Colors.Panel
    end)
    light.Activated:Connect(function()
        Remotes.FireServer("FlashlightToggle")
    end)

    player:GetAttributeChangedSignal("FlashlightEnabled"):Connect(function()
        light.BackgroundColor3 = player:GetAttribute("FlashlightEnabled") == true and Colors.ButtonActive or Colors.Panel
    end)

    ClientState.Subscribe("Game", function(data)
        holder.Visible = data.Phase == "Playing"
    end)
end

return MobileControls
