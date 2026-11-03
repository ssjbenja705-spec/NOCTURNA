-- Inventario por casilleros. Lógica pura y atómica: si no entra todo, no entra nada.
local InventoryModel = {}
InventoryModel.__index = InventoryModel

function InventoryModel.new(itemConfig, maxSlots)
    return setmetatable({
        Config = itemConfig,
        MaxSlots = maxSlots,
        Slots = {},
    }, InventoryModel)
end

local function validAmount(amount)
    return type(amount) == "number" and amount >= 1 and amount % 1 == 0
end

function InventoryModel:Count(itemId)
    local total = 0
    for _, slot in ipairs(self.Slots) do
        if slot.Id == itemId then
            total += slot.Amount
        end
    end
    return total
end

function InventoryModel:Has(itemId, amount)
    return self:Count(itemId) >= (amount or 1)
end

function InventoryModel:CanAdd(itemId, amount)
    amount = amount or 1
    local definition = self.Config[itemId]
    if not definition or not validAmount(amount) then
        return false
    end

    local maxStack = definition.Stackable and (definition.MaxStack or 1) or 1
    local free = (self.MaxSlots - #self.Slots) * maxStack

    for _, slot in ipairs(self.Slots) do
        if slot.Id == itemId then
            free += maxStack - slot.Amount
        end
    end

    return free >= amount
end

function InventoryModel:Add(itemId, amount)
    amount = amount or 1
    if not self:CanAdd(itemId, amount) then
        return false
    end

    local definition = self.Config[itemId]
    local maxStack = definition.Stackable and (definition.MaxStack or 1) or 1

    for _, slot in ipairs(self.Slots) do
        if amount == 0 then
            break
        end
        if slot.Id == itemId and slot.Amount < maxStack then
            local added = math.min(amount, maxStack - slot.Amount)
            slot.Amount += added
            amount -= added
        end
    end

    while amount > 0 do
        local added = math.min(amount, maxStack)
        table.insert(self.Slots, {Id = itemId, Amount = added})
        amount -= added
    end

    return true
end

function InventoryModel:Remove(itemId, amount)
    amount = amount or 1
    if not validAmount(amount) or self:Count(itemId) < amount then
        return false
    end

    for index = #self.Slots, 1, -1 do
        local slot = self.Slots[index]
        if slot.Id == itemId then
            local removed = math.min(amount, slot.Amount)
            slot.Amount -= removed
            amount -= removed
            if slot.Amount == 0 then
                table.remove(self.Slots, index)
            end
            if amount == 0 then
                break
            end
        end
    end

    return true
end

-- Copia segura para enviar al cliente.
function InventoryModel:Serialize()
    local result = table.create(#self.Slots)
    for _, slot in ipairs(self.Slots) do
        table.insert(result, {Id = slot.Id, Amount = slot.Amount})
    end
    return result
end

-- Quita y devuelve los objetos de misión para que caigan al suelo.
function InventoryModel:TakeQuestItems()
    local taken = {}
    for index = #self.Slots, 1, -1 do
        local slot = self.Slots[index]
        local definition = self.Config[slot.Id]
        if definition and definition.Quest then
            table.insert(taken, {Id = slot.Id, Amount = slot.Amount})
            table.remove(self.Slots, index)
        end
    end
    return taken
end

function InventoryModel:Clear()
    table.clear(self.Slots)
end

return InventoryModel
