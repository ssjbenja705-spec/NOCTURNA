-- Ajustes del jugador. Se aplican al instante y se guardan en su perfil.
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local HUD = require(script.Parent.HUD)
local Theme = require(script.Parent.Theme)

local Colors = Theme.Colors
local STEP = 0.1
local ROW_HEIGHT = 56
local FIRST_ROW = 62
local SEGMENTS = 10
local BUTTON = Theme.IsTouch and 48 or 44

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
    local panel, _, closeButton = Theme.Window(root, "Settings", "AJUSTES", 440, FIRST_ROW + ROW_HEIGHT * 5 + 34)

    Theme.Label(panel, {
        Name = "Hint",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 18, 1, -10),
        Size = UDim2.new(1, -36, 0, 18),
        Text = "Se guarda al cerrar.",
        TextSize = 13,
        TextColor3 = Colors.TextDim,
    })

    local refreshers = {}

    local function rowLabel(y, text)
        return Theme.Label(panel, {
            Position = UDim2.fromOffset(18, y),
            Size = UDim2.fromOffset(130, BUTTON),
            Text = text,
            TextSize = 16,
            TextYAlignment = Enum.TextYAlignment.Center,
        })
    end

    -- Volumen y brillo: una barra de diez marcas, como un dial viejo.
    local function addStepper(key, title, order)
        local y = FIRST_ROW + (order - 1) * ROW_HEIGHT
        rowLabel(y, title)

        local meter = Theme.New("Frame", {
            Name = key,
            Position = UDim2.fromOffset(148, y + BUTTON / 2 - 7),
            Size = UDim2.new(1, -(148 + 2 * BUTTON + 34), 0, 14),
            BackgroundTransparency = 1,
        }, panel)
        local segments = {}
        for index = 1, SEGMENTS do
            segments[index] = Theme.New("Frame", {
                Position = UDim2.new((index - 1) / SEGMENTS, 1, 0, 0),
                Size = UDim2.new(1 / SEGMENTS, -3, 1, 0),
                BackgroundColor3 = Colors.Track,
                BorderSizePixel = 0,
            }, meter)
        end

        local minus = Theme.Button(panel, "-", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -(BUTTON + 24), 0, y),
            Size = UDim2.fromOffset(BUTTON, BUTTON),
            TextSize = 22,
        })
        local plus = Theme.Button(panel, "+", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -16, 0, y),
            Size = UDim2.fromOffset(BUTTON, BUTTON),
            TextSize = 22,
        })

        local function change(delta)
            if current then
                current[key] = math.clamp(math.floor((current[key] + delta) * 10 + 0.5) / 10, 0, 1)
                refreshers[key]()
                notify()
            end
        end

        refreshers[key] = function()
            local filled = math.floor(current[key] * SEGMENTS + 0.5)
            for index, segment in ipairs(segments) do
                segment.BackgroundColor3 = index <= filled and Colors.Accent or Colors.Track
            end
        end
        minus.Activated:Connect(function()
            change(-STEP)
        end)
        plus.Activated:Connect(function()
            change(STEP)
        end)
    end

    local function addToggle(key, title, order)
        local y = FIRST_ROW + (order - 1) * ROW_HEIGHT
        rowLabel(y, title).Size = UDim2.new(1, -150, 0, BUTTON)
        local button = Theme.Button(panel, "", {
            Name = key,
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -16, 0, y),
            Size = UDim2.fromOffset(2 * BUTTON + 8, BUTTON),
            TextSize = 16,
        })

        refreshers[key] = function()
            button.Text = current[key] and "SÍ" or "NO"
            button.BackgroundColor3 = current[key] and Colors.ButtonActive or Colors.Button
            button.TextColor3 = current[key] and Colors.Text or Colors.TextDim
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

    HUD.AddAction("Settings", "AJUSTES", 4, toggle)

    UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.P then
            toggle()
        end
    end)
end

return SettingsUI
