-- Panel de moderación. Sólo aparece si el servidor marcó al jugador como administrador;
-- ocultarlo no es la protección: el servidor revalida cada acción.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)
local HUD = require(script.Parent.HUD)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer
local Colors = Theme.Colors

local AdminUI = {}

local QUICK_ACTIONS = {
    {Text = "Saltar objetivo", Action = "skip"},
    {Text = "Quitar criaturas", Action = "clearmonsters"},
    {Text = "Congelar IA", Action = "freeze"},
    {Text = "Volver al lobby", Action = "lobby"},
}

local function fireCommand(action, args)
    Remotes.FireServer("AdminAction", action, args or {})
end

function AdminUI.Start()
    local root = Theme.Screen("NocturnaAdmin", 15)

    local panel, _, close = Theme.Window(root, "AdminPanel", "MODERACIÓN", 680, 450)
    close.Activated:Connect(function()
        panel.Visible = false
        Theme.SetModal("Admin", false)
    end)

    local status = Theme.Label(panel, {
        Name = "Status",
        Position = UDim2.fromOffset(18, 56),
        Size = UDim2.new(1, -36, 0, 18),
        TextSize = 13,
        TextColor3 = Colors.Accent,
        TextWrapped = false,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    local quick = Theme.New("Frame", {
        Name = "Quick",
        Position = UDim2.fromOffset(18, 80),
        Size = UDim2.new(1, -36, 0, 44),
        BackgroundTransparency = 1,
    }, panel)
    Theme.New("UIGridLayout", {
        CellSize = UDim2.new(0.25, -6, 1, 0),
        CellPadding = UDim2.fromOffset(8, 0),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, quick)

    for index, entry in ipairs(QUICK_ACTIONS) do
        local button = Theme.Button(quick, entry.Text, {
            TextSize = 13,
            LayoutOrder = index,
            BackgroundColor3 = entry.Action == "lobby" and Colors.ButtonActive or Colors.Button,
        })
        button.Activated:Connect(function()
            fireCommand(entry.Action)
        end)
    end

    local list = Theme.New("ScrollingFrame", {
        Name = "Players",
        Position = UDim2.fromOffset(18, 134),
        Size = UDim2.new(0.5, -24, 1, -254),
        BackgroundColor3 = Colors.Track,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = Colors.Stroke,
        CanvasSize = UDim2.new(),
    }, panel)
    Theme.New("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, list)

    local logLabel = Theme.Label(panel, {
        Name = "Log",
        Position = UDim2.new(0.5, 6, 0, 134),
        Size = UDim2.new(0.5, -24, 1, -254),
        TextSize = 12,
        TextColor3 = Colors.TextDim,
        Font = Theme.Fonts.Mono,
    })

    local commandBox = Theme.New("TextBox", {
        Name = "Command",
        Position = UDim2.new(0, 18, 1, -112),
        Size = UDim2.new(1, -132, 0, 46),
        BackgroundColor3 = Colors.Track,
        BorderSizePixel = 0,
        TextColor3 = Colors.Text,
        PlaceholderText = "comando: announce hola / ban Nombre 7 motivo / give Fuse",
        PlaceholderColor3 = Colors.TextDim,
        Font = Theme.Fonts.Mono,
        TextSize = 14,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "",
    }, panel)
    Theme.Corner(commandBox)
    Theme.Stroke(commandBox, Colors.Stroke, 1, 0.1)
    Theme.New("UIPadding", {PaddingLeft = UDim.new(0, 10)}, commandBox)

    local send = Theme.Button(panel, "ENVIAR", {
        Name = "Send",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -18, 1, -112),
        Size = UDim2.fromOffset(100, 46),
        TextSize = 15,
        BackgroundColor3 = Colors.ButtonActive,
    })
    send.Activated:Connect(function()
        local parts = string.split(commandBox.Text, " ")
        local action = table.remove(parts, 1)
        if action and action ~= "" then
            fireCommand(action, parts)
            commandBox.Text = ""
        end
    end)

    Theme.Label(panel, {
        Name = "Help",
        Position = UDim2.new(0, 18, 1, -58),
        Size = UDim2.new(1, -36, 0, 48),
        TextSize = 12,
        TextColor3 = Colors.TextDim,
        Text = "heal, kill, kick, ban, unban, give, spawn <ElOyente...>, setchapter <1-5>, announce. También por chat con !comando.",
    })

    local function renderPlayers(members)
        for _, child in ipairs(list:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end

        for index, member in ipairs(members) do
            local row = Theme.New("Frame", {
                Name = "Row",
                Size = UDim2.new(1, -8, 0, 42),
                BackgroundColor3 = Colors.PanelLight,
                BackgroundTransparency = 0.2,
                BorderSizePixel = 0,
                LayoutOrder = index,
            }, list)
            Theme.Label(row, {
                Position = UDim2.fromOffset(8, 0),
                Size = UDim2.new(1, -150, 1, 0),
                Text = member.DisplayName,
                TextSize = 13,
                TextWrapped = false,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextYAlignment = Enum.TextYAlignment.Center,
            })

            for column, entry in ipairs({{"Curar", "heal"}, {"Echar", "kick"}}) do
                local button = Theme.Button(row, entry[1], {
                    AnchorPoint = Vector2.new(1, 0),
                    Position = UDim2.new(1, -4 - (2 - column) * 70, 0, 3),
                    Size = UDim2.fromOffset(66, 36),
                    TextSize = 13,
                    BackgroundColor3 = entry[2] == "kick" and Colors.ButtonActive or Colors.Button,
                })
                button.Activated:Connect(function()
                    fireCommand(entry[2], {member.Name})
                end)
            end
        end

        list.CanvasSize = UDim2.fromOffset(0, #members * 46)
    end

    Remotes.OnClient("AdminData", function(data)
        status.Text = string.format(
            "Fase: %s  ·  Capítulo: %d  ·  Reintentos: %d  ·  Criaturas: %d%s",
            data.Phase, data.Chapter, data.Lives, data.Monsters, data.AiPaused and "  ·  IA DETENIDA" or ""
        )
        renderPlayers(data.Players)

        local lines = {"Últimas acciones:"}
        for index = 1, math.min(10, #data.Log) do
            local entry = data.Log[index]
            table.insert(lines, string.format("%s: %s %s", entry.Moderator, entry.Action, entry.Detail))
        end
        logLabel.Text = table.concat(lines, "\n")
    end)

    local actionButton = nil

    local function refreshAccess()
        local isAdmin = player:GetAttribute("IsNocturnaAdmin") == true
        if isAdmin and not actionButton then
            actionButton = HUD.AddAction("Admin", "ADMIN", 5, function()
                panel.Visible = not panel.Visible
                Theme.SetModal("Admin", panel.Visible)
                if panel.Visible then
                    Remotes.FireServer("AdminAction", "Refresh")
                end
            end)
        end
    end

    player:GetAttributeChangedSignal("IsNocturnaAdmin"):Connect(refreshAccess)
    refreshAccess()
end

return AdminUI
