-- Panel de donaciones: se abre desde la urna del lobby. Cada botón es un producto de
-- desarrollador; los montos que todavía no tienen id no aparecen. Roblox muestra la
-- confirmación de compra y el servidor acredita y agradece.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DonationConfig = require(Shared.Config.DonationConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer
local Colors = Theme.Colors

-- Alejarse de la urna cierra el panel.
local CLOSE_DISTANCE = 16

local DonationUI = {}

local function rootPosition()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root and root.Position
end

local function describeTop(top)
    if type(top) ~= "table" or #top == 0 then
        return "Todavía no hay mecenas. Tu nombre puede ser el primero del podio."
    end
    local lines = {}
    for rank, entry in ipairs(top) do
        table.insert(lines, string.format("%d° %s — %s R$", rank, tostring(entry.Name), DonationConfig.FormatRobux(entry.Total)))
    end
    return table.concat(lines, "    ")
end

function DonationUI.Start()
    local root = Theme.Screen("NocturnaDonations", 9)
    local panel = Theme.Panel(root, {
        Name = "DonationPanel",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(460, 340),
        BackgroundTransparency = 0.08,
        Visible = false,
    })

    Theme.Label(panel, {
        Position = UDim2.fromOffset(18, 12),
        Size = UDim2.new(1, -36, 0, 26),
        Text = "DONACIONES",
        Font = Enum.Font.GothamBold,
        TextSize = 20,
        TextColor3 = Colors.Accent,
    })
    local subtitle = Theme.Label(panel, {
        Name = "Subtitle",
        Position = UDim2.fromOffset(18, 40),
        Size = UDim2.new(1, -36, 0, 18),
        Text = "Tu aporte mantiene encendidas las luces de la Fundación.",
        TextSize = 12,
        TextColor3 = Colors.TextDim,
    })
    local topLabel = Theme.Label(panel, {
        Name = "Top",
        Position = UDim2.fromOffset(18, 62),
        Size = UDim2.new(1, -36, 0, 30),
        TextSize = 12,
    })

    local list = Theme.New("ScrollingFrame", {
        Name = "Amounts",
        Position = UDim2.fromOffset(18, 98),
        Size = UDim2.new(1, -36, 0, 176),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 6,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
    }, panel)
    Theme.New("UIGridLayout", {
        CellSize = UDim2.fromOffset(96, 42),
        CellPadding = UDim2.fromOffset(8, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, list)

    local visible = DonationConfig.Visible()
    for index, product in ipairs(visible) do
        local button = Theme.Button(list, DonationConfig.FormatRobux(product.Robux) .. " R$", {
            Name = "Amount" .. product.Robux,
            LayoutOrder = index,
            TextSize = 13,
        })
        button.Activated:Connect(function()
            MarketplaceService:PromptProductPurchase(player, product.ProductId)
        end)
    end
    Theme.Label(panel, {
        Name = "Empty",
        Position = UDim2.fromOffset(18, 140),
        Size = UDim2.new(1, -36, 0, 40),
        Text = "Las donaciones todavía no están habilitadas.",
        TextSize = 13,
        TextColor3 = Colors.TextDim,
        TextXAlignment = Enum.TextXAlignment.Center,
        Visible = #visible == 0,
    })

    local close = Theme.Button(panel, "CERRAR", {
        Name = "CloseButton",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -12),
        Size = UDim2.fromOffset(150, 44),
    })

    local openedAt = nil

    local function setOpen(open)
        panel.Visible = open
        openedAt = open and rootPosition() or nil
        Theme.SetModal("Donations", open)
    end

    close.Activated:Connect(function()
        setOpen(false)
    end)

    Remotes.OnClient("DonationUpdate", function(data)
        if type(data) ~= "table" then
            return
        end
        if data.Top ~= nil then
            topLabel.Text = describeTop(data.Top)
        end
        if type(data.Thanks) == "number" then
            subtitle.Text = string.format("¡Gracias por tu donación de %s R$!", DonationConfig.FormatRobux(data.Thanks))
        end
        if data.Open == true and ClientState.Get("Game").Phase == "Lobby" then
            setOpen(true)
        end
    end)

    ClientState.Subscribe("Game", function(state)
        if state.Phase ~= "Lobby" and panel.Visible then
            setOpen(false)
        end
    end)

    task.spawn(function()
        while true do
            task.wait(0.5)
            if panel.Visible and openedAt then
                local position = rootPosition()
                if not position or (position - openedAt).Magnitude > CLOSE_DISTANCE then
                    setOpen(false)
                end
            end
        end
    end)
end

return DonationUI
