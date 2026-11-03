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

    local panel = Theme.Panel(root, {
        Name = "AdminPanel",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(640, 440),
        BackgroundTransparency = 0.04,
        Visible = false,
    })

    Theme.Label(panel, {
        Position = UDim2.fromOffset(16, 12),
        Size = UDim2.new(1, -70, 0, 24),
        Text = "MODERACIÓN",
        Font = Enum.Font.GothamBold,
        TextSize = 16,
    })

    local close = Theme.Button(panel, "X", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 8),
        Size = UDim2.fromOffset(40, 40),
    })
    close.Activated:Connect(function()
        panel.Visible = false
        Theme.SetModal("Admin", false)
    end)

    local status = Theme.Label(panel, {
        Position = UDim2.fromOffset(16, 40),
        Size = UDim2.new(1, -70, 0, 18),
        TextSize = 12,
        TextColor3 = Colors.TextDim,
    })

    for index, quick in ipairs(QUICK_ACTIONS) do
        local button = Theme.Button(panel, quick.Text, {
            Position = UDim2.fromOffset(16 + (index - 1) * 152, 62),
            Size = UDim2.fromOffset(146, 40),
            TextSize = 12,
        })
        button.Activated:Connect(function()
            fireCommand(quick.Action)
        end)
    end

    local list = Theme.New("ScrollingFrame", {
        Position = UDim2.fromOffset(16, 110),
        Size = UDim2.fromOffset(300, 200),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        CanvasSize = UDim2.new(),
    }, panel)
    Theme.New("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, list)

    local logLabel = Theme.Label(panel, {
        Position = UDim2.fromOffset(328, 110),
        Size = UDim2.fromOffset(296, 200),
        TextSize = 11,
        TextColor3 = Colors.TextDim,
    })

    local commandBox = Theme.New("TextBox", {
        Position = UDim2.new(0, 16, 1, -112),
        Size = UDim2.new(1, -112, 0, 44),
        BackgroundColor3 = Colors.PanelLight,
        BorderSizePixel = 0,
        TextColor3 = Colors.Text,
        PlaceholderText = "comando: announce hola / ban Nombre 7 motivo / give Fuse",
        PlaceholderColor3 = Colors.TextDim,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "",
    }, panel)
    Theme.Corner(commandBox)

    local send = Theme.Button(panel, "ENVIAR", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -16, 1, -68),
        Size = UDim2.fromOffset(84, 44),
        TextSize = 12,
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
        Position = UDim2.new(0, 16, 1, -60),
        Size = UDim2.new(1, -32, 0, 50),
        TextSize = 11,
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
                Size = UDim2.new(1, -8, 0, 40),
                BackgroundColor3 = Colors.PanelLight,
                BorderSizePixel = 0,
                LayoutOrder = index,
            }, list)
            Theme.Label(row, {
                Position = UDim2.fromOffset(8, 0),
                Size = UDim2.fromOffset(150, 40),
                Text = member.DisplayName,
                TextSize = 12,
                TextYAlignment = Enum.TextYAlignment.Center,
            })

            for column, entry in ipairs({{"Curar", "heal"}, {"Echar", "kick"}}) do
                local button = Theme.Button(row, entry[1], {
                    Position = UDim2.fromOffset(150 + (column - 1) * 70, 2),
                    Size = UDim2.fromOffset(66, 36),
                    TextSize = 11,
                })
                button.Activated:Connect(function()
                    fireCommand(entry[2], {member.Name})
                end)
            end
        end

        list.CanvasSize = UDim2.fromOffset(0, #members * 44)
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
            actionButton = HUD.AddAction("Admin", "ADMIN", 4, function()
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
