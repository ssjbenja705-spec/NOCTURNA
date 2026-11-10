-- HUD permanente: vida, aire y luz, el objetivo con la señal de la radio, el grupo
-- y los botones de menú. Vive dentro del área segura: arriba empieza debajo de la
-- barra de Roblox, así el objetivo nunca queda tapado por sus botones.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local Icons = require(script.Parent.Icons)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer
local Colors = Theme.Colors
local IsTouch = Theme.IsTouch

local MARGIN = 12
local TOP = 6
local PLATE_HEIGHT = 66
local CELL = IsTouch and Vector2.new(72, 58) or Vector2.new(64, 54)
local CELL_GAP = 6
local KEYS = {Inventory = "I", Journal = "J", Map = "M", Settings = "P"}

local HUD = {}
local root = nil
local actionBar = nil
local actionGrid = nil
local plate = nil
local party = nil

local function countVisibleActions()
    local count = 0
    for _, child in ipairs(actionBar:GetChildren()) do
        if child:IsA("GuiButton") and child.Visible then
            count += 1
        end
    end
    return count
end

-- El objetivo va arriba al centro y los botones a la derecha. Si no entran en una
-- fila sin pisar el objetivo, pasan a dos filas.
local function arrange()
    if not plate or not actionBar or not party then
        return
    end
    local width = Theme.SafeSize().X
    local plateWidth = math.clamp(math.floor(width * 0.36), 320, 430)
    plate.Size = UDim2.fromOffset(plateWidth, PLATE_HEIGHT)

    local free = width - MARGIN - (width / 2 + plateWidth / 2) - 10
    local visible = math.max(1, countVisibleActions())
    local perRow = math.max(2, math.floor((free + CELL_GAP) / (CELL.X + CELL_GAP)))
    perRow = math.min(perRow, visible)
    local rows = math.ceil(visible / perRow)

    actionGrid.FillDirectionMaxCells = perRow
    actionBar.Size = UDim2.fromOffset(perRow * (CELL.X + CELL_GAP) - CELL_GAP, rows * (CELL.Y + CELL_GAP) - CELL_GAP)
    party.Position = UDim2.new(1, -MARGIN, 0, TOP + rows * (CELL.Y + CELL_GAP) + 4)
end

local function makeGauge(parent, y, color, labelText)
    Theme.Label(parent, {
        Name = labelText .. "Label",
        Position = UDim2.fromOffset(12, y),
        Size = UDim2.fromOffset(50, 18),
        Text = labelText,
        TextSize = 13,
        TextColor3 = Colors.TextDim,
        TextYAlignment = Enum.TextYAlignment.Center,
    })

    local track = Theme.New("Frame", {
        Name = labelText,
        Position = UDim2.fromOffset(64, y + 5),
        Size = UDim2.new(1, -78, 0, 9),
        BackgroundColor3 = Colors.Track,
        BorderSizePixel = 0,
    }, parent)
    Theme.Stroke(track, Colors.Black, 1, 0.1)

    local fill = Theme.New("Frame", {
        Name = "Fill",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, track)
    Theme.New("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 130, 126)),
    }, fill)

    -- Marcas de instrumento viejo sobre la barra.
    for index = 1, 9 do
        Theme.New("Frame", {
            Name = "Tick",
            Position = UDim2.new(index / 10, 0, 0, 0),
            Size = UDim2.new(0, 1, 1, 0),
            BackgroundColor3 = Colors.Black,
            BackgroundTransparency = 0.4,
            BorderSizePixel = 0,
            ZIndex = 2,
        }, track)
    end
    return fill
end

local function setFill(fill, fraction)
    local size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
    if fill.Size ~= size then
        fill.Size = size
    end
end

local function buildVitals()
    local panel = Theme.Panel(root, {
        Name = "Vitals",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, MARGIN, 1, IsTouch and -150 or -14),
        Size = UDim2.fromOffset(236, 88),
        BackgroundTransparency = 0.28,
    })

    local health = makeGauge(panel, 8, Colors.Health, "VIDA")
    local stamina = makeGauge(panel, 34, Colors.Stamina, "AIRE")
    local battery = makeGauge(panel, 60, Colors.Battery, "LUZ")

    local function bindCharacter(character)
        local humanoid = character:WaitForChild("Humanoid", 10)
        if not humanoid then
            return
        end
        local function update()
            setFill(health, humanoid.Health / humanoid.MaxHealth)
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
        setFill(stamina, value / GameConfig.Player.MaxStamina)
    end

    local function updateBattery()
        local value = player:GetAttribute("FlashlightBattery") or 100
        setFill(battery, value / 100)
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

-- La radio apunta hacia la señal de Alma: el objetivo pendiente más cercano.
local function buildDial(parent)
    local dial = Theme.New("Frame", {
        Name = "Dial",
        Position = UDim2.fromOffset(9, 9),
        Size = UDim2.fromOffset(48, 48),
        BackgroundColor3 = Colors.Track,
        BorderSizePixel = 0,
    }, parent)
    Theme.New("UICorner", {CornerRadius = UDim.new(0.5, 0)}, dial)
    Theme.Stroke(dial, Colors.Accent, 2, 0.45)

    for _, position in ipairs({{0.5, 0.06}, {0.94, 0.5}, {0.5, 0.94}, {0.06, 0.5}}) do
        Theme.New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(position[1], position[2]),
            Size = UDim2.fromOffset(3, 3),
            BackgroundColor3 = Colors.TextDim,
            BorderSizePixel = 0,
        }, dial)
    end

    local needle = Theme.New("Frame", {
        Name = "Needle",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
    }, dial)
    Theme.New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.18),
        Size = UDim2.new(0, 2, 0.32, 0),
        BackgroundColor3 = Colors.Accent,
        BorderSizePixel = 0,
    }, needle)
    Theme.New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.2),
        Size = UDim2.fromOffset(9, 9),
        Rotation = 45,
        BackgroundColor3 = Colors.Accent,
        BorderSizePixel = 0,
    }, needle)
    Theme.New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0, 2, 0.26, 0),
        BackgroundColor3 = Colors.Blood,
        BorderSizePixel = 0,
    }, needle)

    -- Sin señal la radio muestra una línea plana.
    local flatline = Theme.New("Frame", {
        Name = "Flatline",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0.6, 0, 0, 2),
        BackgroundColor3 = Colors.TextDim,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
    }, dial)

    return needle, flatline
end

local function buildObjective()
    plate = Theme.Panel(root, {
        Name = "Objective",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, TOP),
        Size = UDim2.fromOffset(380, PLATE_HEIGHT),
        BackgroundTransparency = 0.2,
    })
    local stroke = plate:FindFirstChildOfClass("UIStroke")
    local needle, flatline = buildDial(plate)

    local chapter = Theme.Label(plate, {
        Name = "Chapter",
        Position = UDim2.fromOffset(66, 6),
        Size = UDim2.new(1, -130, 0, 17),
        TextSize = 13,
        TextColor3 = Colors.Accent,
        TextWrapped = false,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Text = "NOCTURNA",
    })
    local objective = Theme.Label(plate, {
        Name = "Text",
        Position = UDim2.fromOffset(66, 23),
        Size = UDim2.new(1, -130, 0, 40),
        TextSize = IsTouch and 15 or 16,
        Text = "",
    })
    local tally = Theme.Label(plate, {
        Name = "Tally",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(56, 40),
        TextSize = 22,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextYAlignment = Enum.TextYAlignment.Center,
        Text = "",
    })

    local current = nil
    local lastObjective = nil

    ClientState.Subscribe("Objective", function(data)
        current = data
        if not data then
            return
        end

        chapter.Text = Theme.Upper(string.format("Capítulo %d · %s", data.Chapter or 0, data.ChapterName or ""))
        if data.Finished then
            objective.Text = "..."
            tally.Text = ""
            lastObjective = nil
            return
        end

        local text = data.Objective or ""
        if text ~= lastObjective then
            lastObjective = text
            Theme.Typewrite(objective, text, 45)
            -- El borde se enciende un momento cuando cambia el objetivo.
            if stroke then
                stroke.Color = Colors.Accent
                stroke.Transparency = 0
                Theme.Tween(stroke, 1.4, {Color = Colors.Stroke, Transparency = 0.15})
            end
        end
        tally.Text = (data.Total or 1) > 1 and string.format("%d/%d", data.Count or 0, data.Total) or ""
    end)

    local timer = Theme.Label(root, {
        Name = "Timer",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, TOP + PLATE_HEIGHT + 4),
        Size = UDim2.fromOffset(180, 34),
        Font = Theme.Fonts.Title,
        TextSize = 28,
        TextColor3 = Colors.Danger,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        Visible = false,
    })

    -- El texto sólo se reescribe cuando cambia el segundo.
    local shownSeconds = -1
    RunService.Heartbeat:Connect(function()
        local deadline = current and current.Deadline
        local visible = deadline ~= nil and plate.Visible
        if timer.Visible ~= visible then
            timer.Visible = visible
        end
        if visible then
            local seconds = math.max(0, math.ceil(deadline - workspace:GetServerTimeNow()))
            if seconds ~= shownSeconds then
                shownSeconds = seconds
                timer.Text = formatTime(seconds)
            end
        end
    end)

    RunService.RenderStepped:Connect(function()
        local game_ = ClientState.Get("Game")
        local data = ClientState.Get("Objective")
        local waypoints = data and data.Waypoints
        local character = player.Character
        local head = character and character:FindFirstChild("Head")

        local active = game_.Phase == "Playing" and game_.ShowCompass and waypoints and #waypoints > 0 and head
        active = active and true or false
        if needle.Visible ~= active then
            needle.Visible = active
            flatline.Visible = not active
        end
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
        needle.Rotation = -math.deg(angle)
    end)

    return plate
end

local function buildParty()
    party = Theme.New("Frame", {
        Name = "Party",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -MARGIN, 0, TOP + CELL.Y + 10),
        Size = UDim2.fromOffset(220, 130),
        BackgroundTransparency = 1,
    }, root)

    local lives = Theme.Label(party, {
        Name = "Lives",
        Size = UDim2.new(1, 0, 0, 20),
        TextSize = 14,
        TextColor3 = Colors.Accent,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextStrokeTransparency = 0.6,
    })

    local rows = {}
    for index = 1, GameConfig.MaxPlayers do
        rows[index] = Theme.Label(party, {
            Name = "Member" .. index,
            Position = UDim2.fromOffset(0, 22 + (index - 1) * 22),
            Size = UDim2.new(1, 0, 0, 20),
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextStrokeTransparency = 0.6,
            Visible = false,
        })
    end

    ClientState.Subscribe("Party", function(members)
        for index, row in ipairs(rows) do
            local member = members[index]
            row.Visible = member ~= nil
            if member then
                local state = member.Down and "caído"
                    or (member.Captured and "¡atrapado!")
                    or (member.Hidden and "escondido" or ("vida " .. tostring(member.Health)))
                row.Text = member.Name .. "  ·  " .. state
                row.TextColor3 = (member.Down or member.Captured) and Colors.Danger
                    or (member.Hidden and Colors.Radio or Colors.TextDim)
            end
        end
    end)

    ClientState.Subscribe("Game", function(data)
        lives.Text = data.MaxLives > 0 and string.format("REINTENTOS  %d", data.Lives) or ""
    end)

    return party
end

local function buildButtons()
    local bar = Theme.New("Frame", {
        Name = "Buttons",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -MARGIN, 0, TOP),
        Size = UDim2.fromOffset(CELL.X, CELL.Y),
        BackgroundTransparency = 1,
    }, root)

    actionGrid = Theme.New("UIGridLayout", {
        CellSize = UDim2.fromOffset(CELL.X, CELL.Y),
        CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP),
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, bar)

    return bar
end

-- Agrega un botón a la barra superior: ícono dibujado y nombre. Otros controladores
-- registran acá sus menús. En PC muestra también la tecla.
function HUD.AddAction(name, text, order, callback)
    local button = Theme.Button(actionBar, "", {
        Name = name,
        BackgroundTransparency = 0.18,
        LayoutOrder = order,
    })
    local iconSize = IsTouch and 26 or 24
    Icons.Draw(name, button, {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 6),
        Size = UDim2.fromOffset(iconSize, iconSize),
    })
    Theme.Label(button, {
        Name = "Caption",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -3),
        Size = UDim2.new(1, -4, 0, 18),
        Text = text,
        TextSize = IsTouch and 14 or 12,
        TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    local key = KEYS[name]
    if key and not IsTouch then
        Theme.Label(button, {
            Name = "Key",
            Position = UDim2.fromOffset(4, 2),
            Size = UDim2.fromOffset(14, 14),
            Text = key,
            TextSize = 12,
            TextColor3 = Colors.TextDim,
        })
    end

    button.Activated:Connect(callback)
    button:GetPropertyChangedSignal("Visible"):Connect(arrange)
    arrange()
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
    buildParty()

    local crosshair = Theme.New("Frame", {
        Name = "Crosshair",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(4, 4),
        BackgroundColor3 = Colors.Text,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
    }, root)
    Theme.New("UICorner", {CornerRadius = UDim.new(0.5, 0)}, crosshair)

    Theme.OnLayout(arrange)

    ClientState.Subscribe("Game", function(data)
        local inGame = data.Phase == "Playing"
        vitals.Visible = inGame
        objective.Visible = inGame
        crosshair.Visible = inGame
        party.Visible = data.Phase ~= "Lobby"
    end)
end

return HUD
