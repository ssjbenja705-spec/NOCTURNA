local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("NocturnaRemotes")
local updateEvent = remotes:WaitForChild("InventoryUpdate")
local itemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ItemConfig"))

local inventories = {}
local maxSlots = 8

local function sendInventory(player)
    updateEvent:FireClient(player, inventories[player] or {})
end

local function addItem(player, itemId, amount)
    amount = amount or 1
    if typeof(itemId) ~= "string" or typeof(amount) ~= "number" or amount < 1 or amount % 1 ~= 0 then
        return false
    end

    local definition = itemConfig[itemId]
    local inventory = inventories[player]
    if not definition or not inventory then return false end

    if definition.Stackable then
        local maxStack = definition.MaxStack or 1
        for _, slot in ipairs(inventory) do
            if slot.Id == itemId and slot.Amount < maxStack then
                local added = math.min(amount, maxStack - slot.Amount)
                slot.Amount += added
                amount -= added
                if amount <= 0 then
                    sendInventory(player)
                    return true
                end
            end
        end
    end

    while amount > 0 and #inventory < maxSlots do
        local stackSize = definition.Stackable and (definition.MaxStack or 1) or 1
        local count = math.min(amount, stackSize)
        table.insert(inventory, {Id = itemId, Amount = count})
        amount -= count
    end

    sendInventory(player)
    return amount == 0
end

local function removeItem(player, itemId, amount)
    amount = amount or 1
    local inventory = inventories[player]
    if not inventory or typeof(itemId) ~= "string" or typeof(amount) ~= "number" or amount < 1 or amount % 1 ~= 0 then
        return false
    end

    local available = 0
    for _, slot in ipairs(inventory) do
        if slot.Id == itemId then
            available += slot.Amount
        end
    end
    if available < amount then return false end

    for index = #inventory, 1, -1 do
        local slot = inventory[index]
        if slot.Id == itemId then
            local removed = math.min(amount, slot.Amount)
            slot.Amount -= removed
            amount -= removed
            if slot.Amount == 0 then
                table.remove(inventory, index)
            end
            if amount == 0 then break end
        end
    end

    sendInventory(player)
    return true
end

Players.PlayerAdded:Connect(function(player)
    inventories[player] = {}
    sendInventory(player)
end)

Players.PlayerRemoving:Connect(function(player)
    inventories[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
    inventories[player] = {}
    sendInventory(player)
end

_G.NocturnaInventory = {
    AddItem = addItem,
    RemoveItem = removeItem,
    HasItem = function(player, itemId)
        for _, slot in ipairs(inventories[player] or {}) do
            if slot.Id == itemId and slot.Amount > 0 then
                return true
            end
        end
        return false
    end,
    GetInventory = function(player)
        return inventories[player] or {}
    end,
}

print("[NOCTURNA] Inventario iniciado.")