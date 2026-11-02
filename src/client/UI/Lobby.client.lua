local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("NocturnaRemotes")

local actionRemote = remotes:WaitForChild("LobbyAction")
local updateRemote = remotes:WaitForChild("LobbyUpdate")
local startedRemote = remotes:WaitForChild("MatchStarted")

local gui = Instance.new("ScreenGui")
gui.Name = "NocturnaLobby"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(330, 300)
panel.Position = UDim2.new(0.5, -165, 0.5, -150)
panel.BackgroundColor3 = Color3.fromRGB(12, 15, 21)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = panel

local function makeLabel(parent, text, size, position, fontSize)
    local label = Instance.new("TextLabel")
    label.Size = size
    label.Position = position
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(235, 235, 240)
    label.Font = Enum.Font.GothamBold
    label.TextSize = fontSize
    label.TextWrapped = true
    label.Parent = parent
    return label
end

local title = makeLabel(
    panel,
    "NOCTURNA",
    UDim2.new(1, -20, 0, 38),
    UDim2.fromOffset(10, 10),
    23
)

local subtitle = makeLabel(
    panel,
    "SALA COOPERATIVA",
    UDim2.new(1, -20, 0, 22),
    UDim2.fromOffset(10, 45),
    12
)

local playersLabel = makeLabel(
    panel,
    "Esperando jugadores...",
    UDim2.new(1, -30, 0, 135),
    UDim2.fromOffset(15, 78),
    14
)
playersLabel.Font = Enum.Font.Gotham
playersLabel.TextXAlignment = Enum.TextXAlignment.Left
playersLabel.TextYAlignment = Enum.TextYAlignment.Top

local function makeButton(text, position)
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(140, 42)
    button.Position = position
    button.BackgroundColor3 = Color3.fromRGB(55, 65, 78)
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Text = text
    button.Font = Enum.Font.GothamBold
    button.TextSize = 13
    button.Parent = panel

    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 7)
    buttonCorner.Parent = button

    return button
end

local readyButton = makeButton("ESTOY LISTO", UDim2.fromOffset(15, 245))
local startButton = makeButton("INICIAR", UDim2.fromOffset(175, 245))

local status = makeLabel(
    panel,
    "Esperando...",
    UDim2.new(1, -20, 0, 18),
    UDim2.fromOffset(10, 218),
    11
)

readyButton.Visible = false
startButton.Visible = false

readyButton.Activated:Connect(function()
    actionRemote:FireServer("Ready")
end)

startButton.Activated:Connect(function()
    actionRemote:FireServer("Start")
end)

local function refresh(data)
    if typeof(data) ~= "table" then return end

    local lines = {}
    for _, member in ipairs(data.Players or {}) do
        local state = member.Ready and "LISTO" or "ESPERANDO"
        local leader = member.IsLeader and " [LÍDER]" or ""
        table.insert(lines, member.Name .. " - " .. state .. leader)
    end

    playersLabel.Text = #lines > 0 and table.concat(lines, "\n") or "Esperando jugadores..."
    subtitle.Text = string.format(
        "JUGADORES: %d/%d",
        data.PlayerCount or 0,
        data.MaxPlayers or 4
    )

    local isReady = false
    local isLeader = false
    for _, member in ipairs(data.Players or {}) do
        if member.UserId == player.UserId then
            isReady = member.Ready
            isLeader = member.IsLeader
            break
        end
    end

    readyButton.Text = isReady and "NO ESTOY LISTO" or "ESTOY LISTO"
    startButton.Visible = isLeader and not data.MatchActive
    readyButton.Visible = not data.MatchActive

    if data.MatchActive then
        status.Text = "PARTIDA EN CURSO"
    elseif isLeader then
        status.Text = "Sos el líder de la sala"
    else
        status.Text = "Esperando al líder"
    end
end

updateRemote.OnClientEvent:Connect(refresh)

startedRemote.OnClientEvent:Connect(function()
    status.Text = "¡LA PARTIDA HA COMENZADO!"
    readyButton.Visible = false
    startButton.Visible = false
    title.Text = "NOCTURNA - CAPÍTULO 1"
end)

task.wait(1)
actionRemote:FireServer("RequestUpdate")
