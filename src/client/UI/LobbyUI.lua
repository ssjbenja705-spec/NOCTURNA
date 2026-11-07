-- Lobby caminable: nada tapa la pantalla. Sólo aparece un panel chico al entrar a un
-- ascensor (grupo, lugares, dificultad, capítulo y EMPEZAR), una tarjeta para volver
-- a una partida, esperar al grupo o regresar al lobby, y una pista que se desvanece.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer
local Colors = Theme.Colors

local HINT_TIME = 12
local ROW_HEIGHT = 38

local LobbyUI = {}

local function difficultyOrder()
    local names = {}
    for name in pairs(GameConfig.Difficulties) do
        table.insert(names, name)
    end
    table.sort(names, function(a, b)
        if a == GameConfig.DefaultDifficulty or b == GameConfig.DefaultDifficulty then
            return a == GameConfig.DefaultDifficulty
        end
        return a < b
    end)
    return names
end

local function queueAction(action, argument)
    Remotes.FireServer("QueueAction", action, argument)
end

local function rowLabel(parent, y, text)
    return Theme.Label(parent, {
        Position = UDim2.fromOffset(14, y),
        Size = UDim2.fromOffset(92, ROW_HEIGHT),
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = Colors.TextDim,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
end

local function smallButton(parent, name, text, x, y, width)
    return Theme.Button(parent, text, {
        Name = name,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(width or 38, ROW_HEIGHT - 2),
        TextSize = 16,
    })
end

local function buildPanel(root)
    local panel = Theme.Panel(root, {
        Name = "LobbyPanel",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 64),
        Size = UDim2.fromOffset(300, 282),
        BackgroundTransparency = 0.12,
        Visible = false,
    })

    local ui = {Panel = panel}
    ui.Title = Theme.Label(panel, {
        Name = "Title",
        Position = UDim2.fromOffset(14, 10),
        Size = UDim2.new(1, -28, 0, 22),
        Font = Enum.Font.GothamBold,
        TextSize = 17,
        TextColor3 = Colors.Accent,
    })
    ui.Role = Theme.Label(panel, {
        Position = UDim2.fromOffset(14, 32),
        Size = UDim2.new(1, -28, 0, 16),
        TextSize = 12,
        TextColor3 = Colors.TextDim,
    })
    ui.Members = Theme.Label(panel, {
        Name = "Members",
        Position = UDim2.fromOffset(14, 52),
        Size = UDim2.new(1, -28, 0, 36),
        TextSize = 13,
    })

    rowLabel(panel, 94, "JUGADORES")
    ui.Minus = smallButton(panel, "Minus", "-", 150, 95)
    ui.PlayersValue = Theme.Label(panel, {
        Position = UDim2.fromOffset(190, 94),
        Size = UDim2.fromOffset(54, ROW_HEIGHT),
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    ui.Plus = smallButton(panel, "Plus", "+", 248, 95)

    rowLabel(panel, 138, "DIFICULTAD")
    ui.Difficulty = smallButton(panel, "Difficulty", "", 110, 139, 176)
    ui.Difficulty.TextSize = 13

    rowLabel(panel, 182, "CAPÍTULO")
    ui.Previous = smallButton(panel, "Previous", "<", 94, 183)
    ui.Chapter = Theme.Label(panel, {
        Position = UDim2.fromOffset(134, 182),
        Size = UDim2.fromOffset(112, ROW_HEIGHT),
        TextSize = 11,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    ui.Next = smallButton(panel, "Next", ">", 248, 183)

    ui.Start = Theme.Button(panel, "EMPEZAR", {
        Name = "StartButton",
        Position = UDim2.fromOffset(14, 228),
        Size = UDim2.fromOffset(180, 44),
        BackgroundColor3 = Colors.ButtonActive,
        TextSize = 15,
    })
    ui.Waiting = Theme.Label(panel, {
        Position = UDim2.fromOffset(14, 228),
        Size = UDim2.fromOffset(180, 44),
        TextSize = 12,
        TextColor3 = Colors.TextDim,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    ui.Leave = Theme.Button(panel, "SALIR", {
        Name = "LeaveButton",
        Position = UDim2.fromOffset(202, 228),
        Size = UDim2.fromOffset(84, 44),
        TextSize = 13,
    })
    return ui
end

local function buildCard(root)
    local card = Theme.Panel(root, {
        Name = "LobbyCard",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 64),
        Size = UDim2.fromOffset(360, 112),
        BackgroundTransparency = 0.12,
        Visible = false,
    })
    local ui = {Card = card}
    ui.Text = Theme.Label(card, {
        Position = UDim2.fromOffset(14, 10),
        Size = UDim2.new(1, -28, 0, 44),
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    ui.Primary = Theme.Button(card, "", {
        Name = "Primary",
        Position = UDim2.new(0.5, -168, 0, 60),
        Size = UDim2.fromOffset(160, 42),
        BackgroundColor3 = Colors.ButtonActive,
    })
    ui.Secondary = Theme.Button(card, "", {
        Name = "Secondary",
        Position = UDim2.new(0.5, 8, 0, 60),
        Size = UDim2.fromOffset(160, 42),
    })
    return ui
end

function LobbyUI.Start()
    local root = Theme.Screen("NocturnaLobby", 8)
    local panelUi = buildPanel(root)
    local cardUi = buildCard(root)
    local hint = Theme.Label(root, {
        Name = "LobbyHint",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -18),
        Size = UDim2.fromOffset(520, 40),
        TextSize = 13,
        TextColor3 = Colors.TextDim,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        Visible = false,
    })

    local difficulties = difficultyOrder()
    local latest = {Kind = "None"}
    local hintUntil = os.clock() + HINT_TIME
    local offline = false
    local cardActions = {}
    local waitingRemaining, waitingReceived = 0, 0

    local function phase()
        local state = ClientState.Get("Game")
        return state and state.Phase or "Lobby"
    end

    panelUi.Minus.Activated:Connect(function()
        queueAction("SetMaxPlayers", (latest.MaxPlayers or 1) - 1)
    end)
    panelUi.Plus.Activated:Connect(function()
        queueAction("SetMaxPlayers", (latest.MaxPlayers or 1) + 1)
    end)
    panelUi.Previous.Activated:Connect(function()
        queueAction("SetChapter", (latest.Chapter or 1) - 1)
    end)
    panelUi.Next.Activated:Connect(function()
        queueAction("SetChapter", (latest.Chapter or 1) + 1)
    end)
    panelUi.Difficulty.Activated:Connect(function()
        if not latest.IsHost then
            return
        end
        local index = table.find(difficulties, latest.Difficulty) or 0
        queueAction("SetDifficulty", difficulties[index % #difficulties + 1])
    end)
    panelUi.Start.Activated:Connect(function()
        queueAction(latest.State == "Countdown" and "Cancel" or "Start")
    end)
    panelUi.Leave.Activated:Connect(function()
        queueAction("Leave")
    end)
    cardUi.Primary.Activated:Connect(function()
        if cardActions.Primary then
            queueAction(cardActions.Primary)
        end
    end)
    cardUi.Secondary.Activated:Connect(function()
        if cardActions.Secondary then
            queueAction(cardActions.Secondary)
        end
    end)

    local function refreshPanel(data)
        local isHost = data.IsHost == true
        local open = data.State == "Open"
        local counting = data.State == "Countdown"
        local launching = data.State == "Launching"
        local members = data.Members or {}
        local maxPlayers = data.MaxPlayers or GameConfig.MaxPlayers

        if counting then
            panelUi.Title.Text = string.format("SALE EN %d", data.Countdown or 0)
        elseif launching then
            panelUi.Title.Text = "VIAJANDO..."
        else
            panelUi.Title.Text = "ASCENSOR " .. tostring(data.Elevator or "")
        end
        panelUi.Role.Text = isHost and "Sos el anfitrión" or ("Anfitrión: " .. tostring(data.HostName or ""))

        local names = {}
        for index, member in ipairs(members) do
            table.insert(names, index == 1 and (member.Name .. " (anfitrión)") or member.Name)
        end
        for _ = #names + 1, maxPlayers do
            table.insert(names, "libre")
        end
        panelUi.Members.Text = string.format("%d/%d  ·  %s", #members, maxPlayers, table.concat(names, " · "))

        local editable = isHost and open
        panelUi.PlayersValue.Text = tostring(maxPlayers)
        panelUi.Minus.Visible = editable and maxPlayers > math.max(1, #members)
        panelUi.Plus.Visible = editable and maxPlayers < GameConfig.MaxPlayers

        local difficulty = GameConfig.Difficulties[data.Difficulty or GameConfig.DefaultDifficulty]
        panelUi.Difficulty.Text = string.upper(difficulty and difficulty.DisplayName or "")
        panelUi.Difficulty.Active = editable
        panelUi.Difficulty.AutoButtonColor = editable

        local chapter = data.Chapter or 1
        panelUi.Chapter.Text = string.format("%d · %s", chapter, data.ChapterName or GameConfig.Chapters[chapter] or "")
        panelUi.Previous.Visible = editable and chapter > 1
        panelUi.Next.Visible = editable and chapter < (data.HighestUnlocked or 1)

        panelUi.Start.Visible = isHost and not launching
        panelUi.Start.Text = counting and "CANCELAR" or "EMPEZAR"
        panelUi.Waiting.Visible = not panelUi.Start.Visible
        if launching then
            panelUi.Waiting.Text = "Viajando a la partida..."
        elseif counting then
            panelUi.Waiting.Text = "Las puertas se cierran..."
        else
            panelUi.Waiting.Text = "Esperando que el anfitrión empiece"
        end
        panelUi.Leave.Visible = not launching
    end

    local function refreshCard(data)
        cardActions = {}
        if data.Kind == "Rejoin" then
            local difficulty = GameConfig.Difficulties[data.Difficulty or GameConfig.DefaultDifficulty]
            cardUi.Text.Text = string.format(
                "Tu partida sigue en curso.\nCapítulo %d · %s · %s",
                data.Chapter or 1, data.ChapterName or "", difficulty and difficulty.DisplayName or ""
            )
            cardActions.Primary, cardActions.Secondary = "Rejoin", "DismissRejoin"
            cardUi.Primary.Text, cardUi.Secondary.Text = "VOLVER", "DESCARTAR"
        elseif data.Kind == "Waiting" then
            local remaining = math.max(0, math.ceil(waitingRemaining - (os.clock() - waitingReceived)))
            cardUi.Text.Text = string.format(
                "Esperando al grupo... %d/%d\nEmpieza en %d s aunque falte alguien.",
                data.Arrived or 0, data.Expected or 1, remaining
            )
            cardActions.Secondary = "ReturnToLobby"
            cardUi.Secondary.Text = "SALIR"
        elseif data.Kind == "Returning" then
            cardUi.Text.Text = "La partida terminó.\nVolviendo a la recepción..."
            cardActions.Primary = "ReturnToLobby"
            cardUi.Primary.Text = "VOLVER AL LOBBY"
        end
        cardUi.Primary.Visible = cardActions.Primary ~= nil
        cardUi.Secondary.Visible = cardActions.Secondary ~= nil
    end

    local function refresh()
        local inLobby = phase() == "Lobby"
        local kind = latest.Kind
        local showPanel = inLobby and kind == "Party"
        local showCard = inLobby and (kind == "Rejoin" or kind == "Waiting" or kind == "Returning")

        if showPanel then
            refreshPanel(latest)
        end
        if showCard then
            refreshCard(latest)
        end
        panelUi.Panel.Visible = showPanel
        cardUi.Card.Visible = showCard
        Theme.SetModal("Lobby", showPanel or (showCard and next(cardActions) ~= nil))

        local hintText = "Caminá hasta los ascensores del fondo para armar tu grupo."
        if offline then
            hintText ..= "\nSin conexión al guardado: el progreso de hoy no se guardará."
        end
        hint.Text = hintText
        hint.Visible = inLobby and kind == "None" and (os.clock() < hintUntil or offline)
    end

    Remotes.OnClient("QueueUpdate", function(data)
        if type(data) ~= "table" then
            return
        end
        latest = data
        if data.Kind == "Waiting" then
            waitingRemaining, waitingReceived = tonumber(data.Remaining) or 0, os.clock()
        end
        refresh()
    end)

    local lastPhase = nil
    ClientState.Subscribe("Game", function(state)
        if state.Phase == "Lobby" and lastPhase ~= "Lobby" then
            hintUntil = os.clock() + HINT_TIME
        end
        lastPhase = state.Phase
        refresh()
    end)
    ClientState.Subscribe("Profile", function(profile)
        offline = profile.Offline == true
        refresh()
    end)

    -- La pista se apaga sola y la cuenta de la tarjeta de espera avanza.
    task.spawn(function()
        while true do
            task.wait(1)
            if hint.Visible or latest.Kind == "Waiting" then
                refresh()
            end
        end
    end)

    queueAction("Sync")
end

return LobbyUI
