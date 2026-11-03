-- Pantallas de muerte, espectador, fracaso del capítulo y resumen de capítulo.
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

function StatusUI.Start()
    local root = Theme.Screen("NocturnaStatus", 20)

    local downPanel = Theme.New("Frame", {
        Name = "Down",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(30, 2, 2),
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Visible = false,
    }, root)

    local downTitle = Theme.Label(downPanel, {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.42),
        Size = UDim2.new(0.9, 0, 0, 50),
        Font = Enum.Font.GothamBold,
        TextSize = 34,
        TextColor3 = Colors.Danger,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    local downDetail = Theme.Label(downPanel, {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.52),
        Size = UDim2.new(0.9, 0, 0, 44),
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    local retryButton = Theme.Button(downPanel, "REINTENTAR", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(0.5, -8, 0.6, 0),
        Size = UDim2.fromOffset(170, 50),
        BackgroundColor3 = Colors.ButtonActive,
        Visible = false,
    })
    local lobbyButton = Theme.Button(downPanel, "VOLVER AL LOBBY", {
        Position = UDim2.new(0.5, 8, 0.6, 0),
        Size = UDim2.fromOffset(170, 50),
        Visible = false,
    })

    retryButton.Activated:Connect(function()
        Remotes.FireServer("LobbyAction", "Retry")
    end)
    lobbyButton.Activated:Connect(function()
        Remotes.FireServer("LobbyAction", "ToLobby")
    end)

    local respawnAt, retryAt = nil, nil

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
        if data.Failed then
            respawnAt = nil
            retryAt = os.clock() + (data.AutoRetry or GameConfig.Match.FailureAutoRetry)
            downTitle.Text = "EL RECUERDO SE APAGA"
            downDetail.Text = data.Reason or ""
            downPanel.BackgroundTransparency = 0.1
            downPanel.Visible = true
            retryButton.Visible = isLeader()
            lobbyButton.Visible = isLeader()
            Theme.SetModal("Failed", isLeader())
        elseif data.Down then
            downTitle.Text = "CAÍSTE"
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
        end
    end)

    RunService.Heartbeat:Connect(function()
        if respawnAt then
            downDetail.Text = string.format("Volvés en %d s", math.max(0, math.ceil(respawnAt - os.clock())))
        elseif retryAt then
            local remaining = math.max(0, math.ceil(retryAt - os.clock()))
            downDetail.Text = string.format("Reintento automático en %d s", remaining)
        end
    end)

    local summary = Theme.Panel(root, {
        Name = "Summary",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(420, 250),
        BackgroundTransparency = 0.04,
        Visible = false,
    })
    local summaryTitle = Theme.Label(summary, {
        Position = UDim2.fromOffset(20, 16),
        Size = UDim2.new(1, -40, 0, 34),
        Font = Enum.Font.GothamBold,
        TextSize = 22,
        TextColor3 = Colors.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    local summaryBody = Theme.Label(summary, {
        Position = UDim2.fromOffset(40, 64),
        Size = UDim2.new(1, -80, 1, -80),
        TextSize = 15,
    })

    Remotes.OnClient("ChapterSummary", function(data)
        summaryTitle.Text = string.format("%s.  %s", data.Count or "", data.ChapterName or "")
        summaryBody.Text = string.format(
            "Tiempo: %s\nObjetivos: %d\nCaídas del grupo: %d\nEncuentros: %d\nIntentos fallidos: %d",
            formatDuration(data.Duration or 0),
            data.Objectives or 0,
            data.Deaths or 0,
            data.Monsters or 0,
            data.Failures or 0
        )
        summary.Visible = true
        task.delay(GameConfig.Match.SummaryDuration, function()
            summary.Visible = false
        end)
    end)
end

return StatusUI
