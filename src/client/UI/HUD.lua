-- HUD permanente: vida, resistencia, batería, objetivo, señal, grupo y botones.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer
local Colors = Theme.Colors

local HUD = {}
local root = nil
local actionBar = nil

local function makeBar(parent, position, color, labelText)
    local holder = Theme.New("Frame", {
        Position = position,
        Size = UDim2.fromOffset(190, 22),
        BackgroundTransparency = 1,
    }, parent)

    Theme.Label(holder, {
        Size = UDim2.fromOffset(50, 20),
        Text = labelText,
        TextSize = 11,
        Font = Enum.Font.GothamMedium,
        TextColor3 = Colors.TextDim,
        TextYAlignment = Enum.TextYAlignment.Center,
    })

    local back = Theme.New("Frame", {
        Position = UDim2.fromOffset(52, 6),
        Size = UDim2.fromOffset(136, 8),
        BackgroundColor3 = Colors.PanelLight,
        BorderSizePixel = 0,
    }, holder)
    Theme.Corner(back, 4)

    local fill = Theme.New("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, back)
    Theme.Corner(fill, 4)
    return fill
end

local function buildVitals()
    local panel = Theme.Panel(root, {
        Name = "Vitals",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 16, 1, Theme.IsTouch and -150 or -16),
        Size = UDim2.fromOffset(206, 80),
        BackgroundTransparency = 0.4,
    })

    local health = makeBar(panel, UDim2.fromOffset(8, 5), Colors.Health, "VIDA")
    local stamina = makeBar(panel, UDim2.fromOffset(8, 29), Colors.Stamina, "AIRE")
    local battery = makeBar(panel, UDim2.fromOffset(8, 53), Colors.Battery, "LUZ")

    local function bindCharacter(character)
        local humanoid = character:WaitForChild("Humanoid", 10)
        if not humanoid then
            return
        end
        local function update()
            health.Size = UDim2.fromScale(math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1), 1)
        end
        humanoid.HealthChanged:Connect(update)
        update()
    end

    player.CharacterAdded:Connect(bindCharacter)
    if player.Character then
        task.spawn(bindCharacter, player.Character)
    end

    local function updateStamina()
        local value = player:GetAttribute("Stamina") or 100
        stamina.Size = UDim2.fromScale(math.clamp(value / GameConfig.Player.MaxStamina, 0, 1), 1)
    end

    local function updateBattery()
        local value = player:GetAttribute("FlashlightBattery") or 100
        battery.Size = UDim2.fromScale(math.clamp(value / 100, 0, 1), 1)
        battery.BackgroundColor3 = value <= GameConfig.Flashlight.LowBattery and Colors.Danger or Colors.Battery
    end

    player:GetAttributeChangedSignal("Stamina"):Connect(updateStamina)
    player:GetAttributeChangedSignal("FlashlightBattery"):Connect(updateBattery)
    updateStamina()
    updateBattery()
    return panel
end

local function formatTime(seconds)
    seconds = math.max(0, math.ceil(seconds))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function buildObjective()
    local panel = Theme.Panel(root, {
        Name = "Objective",
        Position = UDim2.fromOffset(16, 16),
        Size = UDim2.fromOffset(320, 84),
        BackgroundTransparency = 0.35,
    })

    local chapter = Theme.Label(panel, {
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -24, 0, 16),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = Colors.Accent,
        Text = "NOCTURNA",
    })
    local objective = Theme.Label(panel, {
        Position = UDim2.fromOffset(12, 26),
        Size = UDim2.new(1, -24, 0, 36),
        TextSize = 14,
        Text = "",
    })
    local progress = Theme.Label(panel, {
        Position = UDim2.fromOffset(12, 62),
        Size = UDim2.new(1, -24, 0, 16),
        TextSize = 12,
        TextColor3 = Colors.TextDim,
        Text = "",
    })

    local current = nil

    ClientState.Subscribe("Objective", function(data)
        current = data
        if not data then
            return
        end

        chapter.Text = string.upper(string.format("Capítulo %d — %s", data.Chapter or 0, data.ChapterName or ""))
        if data.Finished then
            objective.Text = "..."
            progress.Text = ""
            return
        end

        objective.Text = data.Objective or ""
        if (data.Total or 1) > 1 then
            progress.Text = string.format("%d / %d", data.Count or 0, data.Total)
        else
            progress.Text = ""
        end
    end)

    local timer = Theme.Label(root, {
        Name = "Timer",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 62),
        Size = UDim2.fromOffset(160, 40),
        Font = Enum.Font.GothamBold,
        TextSize = 30,
        TextColor3 = Colors.Danger,
        TextXAlignment = Enum.TextXAlignment.Center,
        Visible = false,
    })

    RunService.Heartbeat:Connect(function()
        local deadline = current and current.Deadline
        timer.Visible = deadline ~= nil
        if deadline then
            timer.Text = formatTime(deadline - workspace:GetServerTimeNow())
        end
    end)

    return panel
end

-- La radio apunta hacia la señal de Alma: el objetivo pendiente más cercano.
local function buildCompass()
    local holder = Theme.New("Frame", {
        Name = "Signal",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 14),
        Size = UDim2.fromOffset(44, 44),
        BackgroundTransparency = 1,
        Visible = false,
    }, root)

    local ring = Theme.New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(40, 40),
        BackgroundColor3 = Colors.Panel,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
    }, holder)
    Theme.Corner(ring, 20)

    local arrow = Theme.Label(holder, {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(40, 40),
        Text = "▲",
        TextSize = 20,
        TextColor3 = Colors.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    })

    RunService.RenderStepped:Connect(function()
        local game_ = ClientState.Get("Game")
        local objective = ClientState.Get("Objective")
        local waypoints = objective and objective.Waypoints
        local character = player.Character
        local head = character and character:FindFirstChild("Head")

        local active = game_.Phase == "Playing" and game_.ShowCompass and waypoints and #waypoints > 0 and head
        holder.Visible = active and true or false
        if not active then
            return
        end

        local nearest, nearestDistance = nil, math.huge
        for _, position in ipairs(waypoints) do
            local distance = (position - head.Position).Magnitude
            if distance < nearestDistance then
                nearest, nearestDistance = position, distance
            end
        end

        local camera = workspace.CurrentCamera
        local look = camera.CFrame.LookVector
        local offset = nearest - head.Position
        local angle = math.atan2(offset.X, offset.Z) - math.atan2(look.X, look.Z)
        arrow.Rotation = -math.deg(angle)
    end)

    return holder
end

local function buildParty()
    local panel = Theme.New("Frame", {
        Name = "Party",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -16, 0, 62),
        Size = UDim2.fromOffset(180, 112),
        BackgroundTransparency = 1,
    }, root)

    local lives = Theme.Label(panel, {
        Size = UDim2.new(1, 0, 0, 18),
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        TextColor3 = Colors.Accent,
        TextXAlignment = Enum.TextXAlignment.Right,
    })

    local rows = {}
    for index = 1, GameConfig.MaxPlayers do
        rows[index] = Theme.Label(panel, {
            Position = UDim2.fromOffset(0, 20 + (index - 1) * 20),
            Size = UDim2.new(1, 0, 0, 18),
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Right,
            Visible = false,
        })
    end

    ClientState.Subscribe("Party", function(members)
        for index, row in ipairs(rows) do
            local member = members[index]
            row.Visible = member ~= nil
            if member then
                local state = member.Down and "caído" or (member.Hidden and "oculto" or tostring(member.Health))
                row.Text = member.Name .. "  " .. state
                row.TextColor3 = member.Down and Colors.Danger or Colors.TextDim
            end
        end
    end)

    ClientState.Subscribe("Game", function(data)
        lives.Text = data.MaxLives > 0 and string.format("REINTENTOS  %d", data.Lives) or ""
    end)

    return panel
end

local function buildButtons()
    local bar = Theme.New("Frame", {
        Name = "Buttons",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -16, 0, 14),
        Size = UDim2.fromOffset(250, 42),
        BackgroundTransparency = 1,
    }, root)

    Theme.New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, bar)

    return bar
end

-- Agrega un botón a la barra superior. Otros controladores registran acá sus menús.
function HUD.AddAction(name, text, order, callback)
    local button = Theme.Button(actionBar, text, {
        Name = name,
        Size = UDim2.fromOffset(74, 40),
        TextSize = 11,
        BackgroundTransparency = 0.2,
        LayoutOrder = order,
    })
    button.Activated:Connect(callback)
    return button
end

function HUD.Root()
    return root
end

function HUD.Start()
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
    end)

    root = Theme.Screen("NocturnaHUD", 1)
    actionBar = buildButtons()

    local vitals = buildVitals()
    local objective = buildObjective()
    local compass = buildCompass()
    local party = buildParty()

    Theme.New("Frame", {
        Name = "Crosshair",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(3, 3),
        BackgroundColor3 = Colors.Text,
        BackgroundTransparency = 0.55,
        BorderSizePixel = 0,
    }, root)

    ClientState.Subscribe("Game", function(data)
        local inGame = data.Phase == "Playing"
        vitals.Visible = inGame
        objective.Visible = inGame
        party.Visible = data.Phase ~= "Lobby"
        compass.Visible = compass.Visible and inGame
    end)
end

return HUD
