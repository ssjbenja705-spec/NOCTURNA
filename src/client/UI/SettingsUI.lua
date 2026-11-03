-- Ajustes del jugador. Se aplican al instante y se guardan en su perfil.
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local HUD = require(script.Parent.HUD)
local Theme = require(script.Parent.Theme)

local Colors = Theme.Colors
local STEP = 0.1

local SettingsUI = {}
local current = nil
local listeners = {}

function SettingsUI.OnChanged(listener)
    table.insert(listeners, listener)
    if current then
        listener(current)
    end
end

local function notify()
    for _, listener in ipairs(listeners) do
        task.spawn(listener, current)
    end
end

function SettingsUI.Start()
    local root = Theme.Screen("NocturnaSettings", 12)

    local panel = Theme.Panel(root, {
        Name = "Settings",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(400, 372),
        BackgroundTransparency = 0.05,
        Visible = false,
    })

    Theme.Label(panel, {
        Position = UDim2.fromOffset(16, 12),
        Size = UDim2.new(1, -70, 0, 24),
        Text = "AJUSTES",
        Font = Enum.Font.GothamBold,
        TextSize = 16,
    })

    local refreshers = {}

    local function addStepper(key, title, order)
        local y = 54 + (order - 1) * 54
        local label = Theme.Label(panel, {
            Position = UDim2.fromOffset(16, y),
            Size = UDim2.new(1, -140, 0, 44),
            TextYAlignment = Enum.TextYAlignment.Center,
        })
        local minus = Theme.Button(panel, "-", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -66, 0, y),
            Size = UDim2.fromOffset(44, 44),
        })
        local plus = Theme.Button(panel, "+", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -16, 0, y),
            Size = UDim2.fromOffset(44, 44),
        })

        local function change(delta)
            if current then
                current[key] = math.clamp(math.floor((current[key] + delta) * 10 + 0.5) / 10, 0, 1)
                refreshers[key]()
                notify()
            end
        end

        refreshers[key] = function()
            label.Text = string.format("%s  %d%%", title, math.floor(current[key] * 100 + 0.5))
        end
        minus.Activated:Connect(function()
            change(-STEP)
        end)
        plus.Activated:Connect(function()
            change(STEP)
        end)
    end

    local function addToggle(key, title, order)
        local y = 54 + (order - 1) * 54
        local button = Theme.Button(panel, "", {
            Position = UDim2.fromOffset(16, y),
            Size = UDim2.new(1, -32, 0, 44),
        })

        refreshers[key] = function()
            button.Text = title .. ": " .. (current[key] and "SÍ" or "NO")
            button.BackgroundColor3 = current[key] and Colors.ButtonActive or Colors.Button
        end
        button.Activated:Connect(function()
            if current then
                current[key] = not current[key]
                refreshers[key]()
                notify()
            end
        end)
    end

    addStepper("MusicVolume", "Música", 1)
    addStepper("EffectsVolume", "Efectos", 2)
    addStepper("Brightness", "Brillo", 3)
    addToggle("Subtitles", "Subtítulos", 4)
    addToggle("LowQuality", "Modo bajo consumo", 5)

    local function close()
        panel.Visible = false
        Theme.SetModal("Settings", false)
        if current then
            Remotes.FireServer("SettingsUpdate", current)
        end
    end

    local closeButton = Theme.Button(panel, "X", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 6),
        Size = UDim2.fromOffset(40, 40),
    })
    closeButton.Activated:Connect(close)

    local function toggle()
        if panel.Visible then
            close()
        else
            panel.Visible = true
            Theme.SetModal("Settings", true)
        end
    end

    ClientState.Subscribe("Profile", function(profile)
        if not current then
            current = table.clone(profile.Settings)
            for _, refresh in pairs(refreshers) do
                refresh()
            end
            notify()
        end
    end)

    HUD.AddAction("Settings", "AJUSTES", 3, toggle)

    UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.P then
            toggle()
        end
    end)
end

return SettingsUI
