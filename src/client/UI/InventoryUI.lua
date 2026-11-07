-- Inventario por casilleros, con cada objeto dibujado. Tocar un objeto usable lo
-- usa; el servidor valida.
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ItemConfig = require(Shared.Config.ItemConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local HUD = require(script.Parent.HUD)
local Icons = require(script.Parent.Icons)
local Theme = require(script.Parent.Theme)

local Colors = Theme.Colors
local IsTouch = Theme.IsTouch
local COLUMNS = 4
local SLOT_SIZE = IsTouch and 86 or 80
local SLOT_GAP = 10
local HEADER = 62
local DETAIL = 74

local InventoryUI = {}
local panel = nil

function InventoryUI.SetOpen(open)
    panel.Visible = open
    Theme.SetModal("Inventory", open)
end

function InventoryUI.Toggle()
    InventoryUI.SetOpen(not panel.Visible)
end

local function buildSlot(parent, index)
    local column = (index - 1) % COLUMNS
    local row = math.floor((index - 1) / COLUMNS)
    local button = Theme.Button(parent, "", {
        Name = "Slot" .. index,
        Position = UDim2.fromOffset(18 + column * (SLOT_SIZE + SLOT_GAP), HEADER + row * (SLOT_SIZE + SLOT_GAP)),
        Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
        BackgroundColor3 = Colors.Track,
        BackgroundTransparency = 0,
    })
    -- Fondo hundido: más oscuro arriba, como un cajón.
    Theme.New("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new(Color3.fromRGB(150, 140, 136), Color3.fromRGB(255, 255, 255)),
    }, button)

    local name = Theme.Label(button, {
        Name = "ItemName",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -3),
        Size = UDim2.new(1, -6, 0, IsTouch and 32 or 28),
        TextSize = IsTouch and 14 or 12,
        TextColor3 = Colors.TextDim,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Bottom,
    })
    local count = Theme.Label(button, {
        Name = "Count",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -5, 0, 3),
        Size = UDim2.fromOffset(36, 16),
        TextSize = 13,
        TextColor3 = Colors.Accent,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextWrapped = false,
    })

    return {Button = button, Name = name, Count = count, Icon = nil, ItemId = nil}
end

local function setSlot(slot, stack)
    local itemId = stack and stack.Id or nil
    local definition = itemId and ItemConfig[itemId]
    if not definition then
        itemId = nil
    end

    if slot.ItemId ~= itemId then
        if slot.Icon then
            slot.Icon:Destroy()
            slot.Icon = nil
        end
        if itemId then
            local size = math.floor(SLOT_SIZE * 0.46)
            slot.Icon = Icons.Draw(itemId, slot.Button, {
                AnchorPoint = Vector2.new(0.5, 0),
                Position = UDim2.new(0.5, 0, 0, 6),
                Size = UDim2.fromOffset(size, size),
            })
        end
        slot.ItemId = itemId
    end

    slot.Name.Text = definition and definition.DisplayName or ""
    slot.Count.Text = stack and definition and stack.Amount > 1 and ("x" .. stack.Amount) or ""
end

function InventoryUI.Start()
    local root = Theme.Screen("NocturnaInventory", 10)
    local rows = math.ceil(GameConfig.Inventory.MaxSlots / COLUMNS)
    local width = COLUMNS * SLOT_SIZE + (COLUMNS - 1) * SLOT_GAP + 36
    local height = HEADER + rows * (SLOT_SIZE + SLOT_GAP) + DETAIL


    local window, _, close = Theme.Window(root, "InventoryPanel", "OBJETOS", width, height)
    panel = window
    close.Activated:Connect(function()
        InventoryUI.SetOpen(false)
    end)

    local detailName = Theme.Label(panel, {
        Name = "DetailName",
        Position = UDim2.new(0, 18, 1, -DETAIL + 4),
        Size = UDim2.new(1, -36, 0, 20),
        TextSize = 16,
        TextColor3 = Colors.Accent,
        TextWrapped = false,
        Text = "",
    })
    local detail = Theme.Label(panel, {
        Name = "Detail",
        Position = UDim2.new(0, 18, 1, -DETAIL + 26),
        Size = UDim2.new(1, -36, 0, 40),
        TextSize = 14,
        TextColor3 = Colors.TextDim,
        Text = IsTouch and "Tocá un objeto para usarlo." or "Hacé clic en un objeto para usarlo.  [R] batería · [H] botiquín · [I] cerrar",
    })

    local slots = {}
    for index = 1, GameConfig.Inventory.MaxSlots do
        local slot = buildSlot(panel, index)
        slots[index] = slot

        slot.Button.Activated:Connect(function()
            local definition = slot.ItemId and ItemConfig[slot.ItemId]
            if not definition then
                return
            end
            for _, other in ipairs(slots) do
                local stroke = other.Button:FindFirstChildOfClass("UIStroke")
                if stroke then
                    stroke.Color = other == slot and Colors.Accent or Colors.Stroke
                end
            end
            detailName.Text = definition.DisplayName
            detail.Text = definition.Description
            if definition.Usable then
                Remotes.FireServer("UseItem", slot.ItemId)
            end
        end)
    end

    ClientState.Subscribe("Inventory", function(items)
        for index, slot in ipairs(slots) do
            setSlot(slot, items[index])
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
