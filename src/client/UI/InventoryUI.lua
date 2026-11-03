-- Inventario por casilleros. Tocar un objeto usable lo usa; el servidor valida.
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ItemConfig = require(Shared.Config.ItemConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local HUD = require(script.Parent.HUD)
local Theme = require(script.Parent.Theme)

local Colors = Theme.Colors
local COLUMNS = 4
local SLOT_SIZE = 72
local SLOT_GAP = 8

local InventoryUI = {}
local panel = nil

function InventoryUI.SetOpen(open)
    panel.Visible = open
    Theme.SetModal("Inventory", open)
end

function InventoryUI.Toggle()
    InventoryUI.SetOpen(not panel.Visible)
end

function InventoryUI.Start()
    local root = Theme.Screen("NocturnaInventory", 10)
    local width = COLUMNS * SLOT_SIZE + (COLUMNS - 1) * SLOT_GAP + 28

    panel = Theme.Panel(root, {
        Name = "InventoryPanel",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(width, 270),
        BackgroundTransparency = 0.05,
        Visible = false,
    })

    Theme.Label(panel, {
        Position = UDim2.fromOffset(14, 10),
        Size = UDim2.new(1, -70, 0, 24),
        Text = "INVENTARIO",
        Font = Enum.Font.GothamBold,
        TextSize = 16,
    })

    local close = Theme.Button(panel, "X", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 8),
        Size = UDim2.fromOffset(40, 40),
    })
    close.Activated:Connect(function()
        InventoryUI.SetOpen(false)
    end)

    local detail = Theme.Label(panel, {
        Position = UDim2.new(0, 14, 1, -42),
        Size = UDim2.new(1, -28, 0, 36),
        TextSize = 12,
        TextColor3 = Colors.TextDim,
        Text = "Tocá un objeto para usarlo.",
    })

    local slots = {}
    for index = 1, GameConfig.Inventory.MaxSlots do
        local column = (index - 1) % COLUMNS
        local row = math.floor((index - 1) / COLUMNS)
        local button = Theme.Button(panel, "", {
            Position = UDim2.fromOffset(14 + column * (SLOT_SIZE + SLOT_GAP), 52 + row * (SLOT_SIZE + SLOT_GAP)),
            Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
            BackgroundColor3 = Colors.PanelLight,
            TextSize = 11,
            TextWrapped = true,
        })
        local swatch = Theme.New("Frame", {
            Position = UDim2.fromOffset(6, 6),
            Size = UDim2.fromOffset(10, 10),
            BorderSizePixel = 0,
            Visible = false,
        }, button)
        Theme.Corner(swatch, 5)

        local slot = {Button = button, Swatch = swatch, ItemId = nil}
        slots[index] = slot

        button.Activated:Connect(function()
            local definition = slot.ItemId and ItemConfig[slot.ItemId]
            if not definition then
                return
            end
            detail.Text = definition.DisplayName .. ": " .. definition.Description
            if definition.Usable then
                Remotes.FireServer("UseItem", slot.ItemId)
            end
        end)
    end

    ClientState.Subscribe("Inventory", function(items)
        for index, slot in ipairs(slots) do
            local stack = items[index]
            local definition = stack and ItemConfig[stack.Id]
            slot.ItemId = stack and stack.Id or nil
            slot.Swatch.Visible = definition ~= nil
            if definition then
                slot.Swatch.BackgroundColor3 = definition.Color
                slot.Button.Text = stack.Amount > 1
                    and string.format("%s\nx%d", definition.DisplayName, stack.Amount)
                    or definition.DisplayName
            else
                slot.Button.Text = ""
            end
        end
    end)

    HUD.AddAction("Inventory", "OBJETOS", 1, InventoryUI.Toggle)

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then
            return
        end
        if input.KeyCode == Enum.KeyCode.I or input.KeyCode == Enum.KeyCode.Tab then
            InventoryUI.Toggle()
        elseif input.KeyCode == Enum.KeyCode.R then
            Remotes.FireServer("UseItem", "Battery")
        elseif input.KeyCode == Enum.KeyCode.H then
            Remotes.FireServer("UseItem", "Medkit")
        end
    end)
end

return InventoryUI
