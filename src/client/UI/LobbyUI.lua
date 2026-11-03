-- Preparación de la partida: jugadores, capítulo, dificultad y estado de listos.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer
local Colors = Theme.Colors

local LobbyUI = {}

function LobbyUI.Start()
    local root = Theme.Screen("NocturnaLobby", 8)

    local panel = Theme.Panel(root, {
        Name = "LobbyPanel",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(440, 440),
        BackgroundTransparency = 0.08,
    })

    Theme.Label(panel, {
        Position = UDim2.fromOffset(20, 14),
        Size = UDim2.new(1, -40, 0, 32),
        Text = "NOCTURNA",
        Font = Enum.Font.GothamBold,
        TextSize = 26,
        TextColor3 = Colors.Accent,
    })
    Theme.Label(panel, {
        Position = UDim2.fromOffset(20, 46),
        Size = UDim2.new(1, -40, 0, 16),
        Text = "EL ÚLTIMO RECUERDO",
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = Colors.TextDim,
    })

    local countLabel = Theme.Label(panel, {
        Position = UDim2.fromOffset(20, 72),
        Size = UDim2.new(1, -40, 0, 18),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
    })
    local membersLabel = Theme.Label(panel, {
        Position = UDim2.fromOffset(20, 92),
        Size = UDim2.new(1, -40, 0, 92),
        TextSize = 14,
    })

    local previous = Theme.Button(panel, "<", {Position = UDim2.fromOffset(20, 192), Size = UDim2.fromOffset(44, 44)})
    local chapterLabel = Theme.Label(panel, {
        Position = UDim2.fromOffset(72, 192),
        Size = UDim2.new(1, -144, 0, 44),
        TextSize = 13,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    local nextButton = Theme.Button(panel, ">", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -20, 0, 192),
        Size = UDim2.fromOffset(44, 44),
    })

    local difficultyButton = Theme.Button(panel, "", {
        Position = UDim2.fromOffset(20, 244),
        Size = UDim2.new(1, -40, 0, 44),
        TextSize = 13,
    })

    local readyButton = Theme.Button(panel, "ESTOY LISTO", {
        Position = UDim2.fromOffset(20, 298),
        Size = UDim2.new(0.5, -26, 0, 52),
    })
    local startButton = Theme.Button(panel, "INICIAR", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -20, 0, 298),
        Size = UDim2.new(0.5, -26, 0, 52),
        BackgroundColor3 = Colors.ButtonActive,
    })

    local status = Theme.Label(panel, {
        Position = UDim2.fromOffset(20, 358),
        Size = UDim2.new(1, -40, 0, 18),
        TextSize = 12,
        TextColor3 = Colors.TextDim,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    local stats = Theme.Label(panel, {
        Position = UDim2.fromOffset(20, 382),
        Size = UDim2.new(1, -40, 0, 44),
        TextSize = 11,
        TextColor3 = Colors.TextDim,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    local latest = nil

    readyButton.Activated:Connect(function()
        Remotes.FireServer("LobbyAction", "Ready")
    end)
    startButton.Activated:Connect(function()
        Remotes.FireServer("LobbyAction", "Start")
    end)

    local function changeChapter(delta)
        if latest then
            Remotes.FireServer("LobbyAction", "SetChapter", (latest.Chapter or 1) + delta)
        end
    end
    previous.Activated:Connect(function()
        changeChapter(-1)
    end)
    nextButton.Activated:Connect(function()
        changeChapter(1)
    end)

    difficultyButton.Activated:Connect(function()
        if latest then
            local nextDifficulty = latest.Difficulty == "Normal" and "Pesadilla" or "Normal"
            Remotes.FireServer("LobbyAction", "SetDifficulty", nextDifficulty)
        end
    end)

    local function refresh(data)
        latest = data
        local lines = {}
        local isReady, isLeader = false, false

        for _, member in ipairs(data.Players or {}) do
            local state = member.Ready and "LISTO" or "ESPERANDO"
            local leader = member.IsLeader and "  [LÍDER]" or ""
            table.insert(lines, member.Name .. " — " .. state .. leader)
            if member.UserId == player.UserId then
                isReady = member.Ready
                isLeader = member.IsLeader
            end
        end

        membersLabel.Text = #lines > 0 and table.concat(lines, "\n") or "Esperando jugadores..."
        countLabel.Text = string.format("JUGADORES %d / %d", data.PlayerCount or 0, data.MaxPlayers or GameConfig.MaxPlayers)

        local chapter = data.Chapter or 1
        chapterLabel.Text = string.format("Capítulo %d\n%s", chapter, GameConfig.Chapters[chapter] or "")
        previous.Visible = isLeader and chapter > 1
        nextButton.Visible = isLeader and chapter < (data.HighestUnlocked or 1)

        local difficulty = GameConfig.Difficulties[data.Difficulty or GameConfig.DefaultDifficulty]
        difficultyButton.Text = "DIFICULTAD: " .. string.upper(difficulty.DisplayName)
        difficultyButton.Active = isLeader
        difficultyButton.AutoButtonColor = isLeader

        readyButton.Text = isReady and "NO ESTOY LISTO" or "ESTOY LISTO"
        startButton.Visible = isLeader
        status.Text = isLeader and "Sos el líder de la sala" or "Esperando al líder"
    end

    local function updateVisibility()
        local visible = ClientState.Get("Game").Phase == "Lobby"
        panel.Visible = visible
        Theme.SetModal("Lobby", visible)
    end

    ClientState.Subscribe("Lobby", refresh)
    ClientState.Subscribe("Game", updateVisibility)
    ClientState.Subscribe("Profile", function(profile)
        local documents, endings = 0, 0
        for _ in pairs(profile.Documents) do
            documents += 1
        end
        for _ in pairs(profile.Endings) do
            endings += 1
        end
        local text = string.format(
            "Documentos %d/%d  ·  Finales %d/3  ·  Muertes %d",
            documents, GameConfig.Match.MaxDocuments, endings, profile.Deaths
        )
        if profile.Offline then
            text ..= "\nSin conexión al guardado: el progreso de hoy no se guardará."
        end
        stats.Text = text
    end)
end

return LobbyUI
