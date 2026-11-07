-- Pantallas de caída, espectador, fracaso del capítulo y el informe al terminarlo.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer
local Colors = Theme.Colors

local StatusUI = {}

local function formatDuration(seconds)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Rojo que entra desde los bordes, como sangre en los ojos.
local function bloodEdges(parent)
    for _, edge in ipairs({{0, 90}, {1, -90}}) do
        local frame = Theme.New("Frame", {
            Name = "Blood",
            AnchorPoint = Vector2.new(0, edge[1]),
            Position = UDim2.fromScale(0, edge[1]),
            Size = UDim2.fromScale(1, 0.35),
            BackgroundColor3 = Colors.Blood,
            BackgroundTransparency = 0.2,
            BorderSizePixel = 0,
        }, parent)
        Theme.New("UIGradient", {
            Rotation = edge[2],
            Transparency = NumberSequence.new(0, 1),
        }, frame)
    end
end

local function buildSummary(root)
    local summary = Theme.New("Frame", {
        Name = "Summary",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(440, 270),
        BackgroundColor3 = Colors.Paper,
        BorderSizePixel = 0,
        Visible = false,
    }, root)
    Theme.Corner(summary, 2)
    Theme.New("UIGradient", {
        Rotation = 60,
        Color = ColorSequence.new(Color3.fromRGB(255, 248, 236), Color3.fromRGB(190, 166, 128)),
    }, summary)
    Theme.Wear(summary, "informe", 2)

    local title = Theme.Label(summary, {
        Name = "Title",
        Position = UDim2.fromOffset(26, 18),
        Size = UDim2.new(1, -52, 0, 52),
        TextSize = 19,
        TextColor3 = Colors.Ink,
    })
    Theme.New("Frame", {
        Name = "Line",
        Position = UDim2.fromOffset(26, 72),
        Size = UDim2.new(1, -52, 0, 1),
        BackgroundColor3 = Colors.Ink,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
    }, summary)
    local body = Theme.Label(summary, {
        Name = "Body",
        Position = UDim2.fromOffset(30, 82),
        Size = UDim2.new(1, -60, 1, -96),
        TextSize = 16,
        TextColor3 = Colors.Ink,
        LineHeight = 1.15,
    })

    -- Sello rojo torcido, como en un expediente.
    local stamp = Theme.Label(summary, {
        Name = "Stamp",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, -96, 1, -58),
        Size = UDim2.fromOffset(170, 40),
        Rotation = -12,
        Text = "SOBREVIVIERON",
        TextSize = 20,
        TextColor3 = Colors.Danger,
        TextTransparency = 0.15,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    Theme.Stroke(stamp, Colors.Danger, 2, 0.25)

    return summary, title, body
end

function StatusUI.Start()
    local root = Theme.Screen("NocturnaStatus", 20, true)

    local downPanel = Theme.New("Frame", {
        Name = "Down",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(26, 2, 2),
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Visible = false,
    }, root)
    bloodEdges(downPanel)
    Theme.Grain(downPanel, 14, function()
        return downPanel.Visible
    end)

    local downTitle = Theme.Title(downPanel, {
        Name = "Title",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.4),
        Size = UDim2.new(0.9, 0, 0, 90),
        TextSize = 66,
        TextStrokeColor3 = Colors.Black,
        TextStrokeTransparency = 0.3,
    })
    local downDetail = Theme.Label(downPanel, {
        Name = "Detail",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0.8, 0, 0, 50),
        TextSize = 19,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextStrokeTransparency = 0.5,
    })

    local retryButton = Theme.Button(downPanel, "REINTENTAR", {
        Name = "Retry",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(0.5, -8, 0.62, 0),
        Size = UDim2.fromOffset(190, 54),
        BackgroundColor3 = Colors.ButtonActive,
        TextSize = 17,
        Visible = false,
    })
    local lobbyButton = Theme.Button(downPanel, "VOLVER AL LOBBY", {
        Name = "Lobby",
        Position = UDim2.new(0.5, 8, 0.62, 0),
        Size = UDim2.fromOffset(190, 54),
        TextSize = 17,
        Visible = false,
    })

    retryButton.Activated:Connect(function()
        Remotes.FireServer("LobbyAction", "Retry")
    end)
    lobbyButton.Activated:Connect(function()
        Remotes.FireServer("LobbyAction", "ToLobby")
    end)

    local respawnAt, retryAt = nil, nil
    local shownSeconds = nil

    local function isLeader()
        local lobby = ClientState.Get("Lobby")
        return lobby ~= nil and lobby.LeaderUserId == player.UserId
    end

    local function hideDown()
        downPanel.Visible = false
        retryButton.Visible = false
        lobbyButton.Visible = false
        respawnAt, retryAt = nil, nil
        Theme.SetModal("Failed", false)
    end

    Remotes.OnClient("DownState", function(data)
        shownSeconds = nil
        if data.Failed then
            respawnAt = nil
            retryAt = os.clock() + (data.AutoRetry or GameConfig.Match.FailureAutoRetry)
            downTitle.Text = "EL RECUERDO SE APAGA"
            downTitle.TextSize = 54
            downDetail.Text = data.Reason or ""
            downPanel.BackgroundTransparency = 0.08
            downPanel.Visible = true
            retryButton.Visible = isLeader()
            lobbyButton.Visible = isLeader()
            Theme.SetModal("Failed", isLeader())
        elseif data.Down then
            downTitle.Text = "CAÍSTE"
            downTitle.TextSize = 66
            downPanel.BackgroundTransparency = 0.35
            downPanel.Visible = true
            if data.Spectating then
                respawnAt = nil
                downDetail.Text = "No quedan reintentos. Mirá a tu grupo."
                task.delay(3, function()
                    if respawnAt == nil and retryAt == nil then
                        downPanel.Visible = false
                    end
                end)
            else
                respawnAt = os.clock() + data.RespawnIn
            end
        else
            hideDown()
        end
    end)

    ClientState.Subscribe("Game", function(data)
        if data.Phase ~= "Failed" and retryAt then
            hideDown()
        elseif (data.Phase == "Loading" or data.Phase == "Lobby") and downPanel.Visible then
            -- Un capítulo nuevo o el lobby nunca empiezan con el aviso de caída puesto.
            hideDown()
        end
    end)

    -- La cuenta regresiva sólo reescribe el texto cuando cambia el segundo.
    RunService.Heartbeat:Connect(function()
        local deadline = respawnAt or retryAt
        if not deadline then
            return
        end
        local seconds = math.max(0, math.ceil(deadline - os.clock()))
        if seconds ~= shownSeconds then
            shownSeconds = seconds
            if respawnAt then
                downDetail.Text = string.format("Volvés en %d s", seconds)
            else
                downDetail.Text = string.format("Reintento automático en %d s", seconds)
            end
        end
    end)

    local summary, summaryTitle, summaryBody = buildSummary(root)

    Remotes.OnClient("ChapterSummary", function(data)
        summaryTitle.Text = Theme.Upper(string.format("Informe · Capítulo %s", data.Count or "")) .. "\n" .. tostring(data.ChapterName or "")
        Theme.Typewrite(summaryBody, string.format(
            "Tiempo: %s\nObjetivos cumplidos: %d\nCaídas del grupo: %d\nEncuentros: %d\nIntentos fallidos: %d",
            formatDuration(data.Duration or 0),
            data.Objectives or 0,
            data.Deaths or 0,
            data.Monsters or 0,
            data.Failures or 0
        ), 60)
        summary.Visible = true
        task.delay(GameConfig.Match.SummaryDuration, function()
            summary.Visible = false
        end)
    end)
end

return StatusUI
