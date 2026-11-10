-- Inventario de cada jugador. Las puertas y máquinas usan el fondo común del grupo,
-- para que nadie quede trabado porque otro lleva el fragmento que falta.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local ItemConfig = require(Shared.Config.ItemConfig)
local InventoryModel = require(Shared.Logic.InventoryModel)
local Remotes = require(Shared.Modules.RemoteHelper)
local DamageService = require(script.Parent.Parent.Data.DamageService)
local FlashlightService = require(script.Parent.Parent.Data.FlashlightService)

local InventoryService = {}
local inventories = {}

local function send(player)
    local inventory = inventories[player]
    if inventory then
        Remotes.FireClient("InventoryUpdate", player, inventory:Serialize())
    end
end

function InventoryService.AddItem(player, itemId, amount)
    local inventory = inventories[player]
    if not inventory or not inventory:Add(itemId, amount or 1) then
        return false
    end
    send(player)
    return true
end

function InventoryService.RemoveItem(player, itemId, amount)
    local inventory = inventories[player]
    if not inventory or not inventory:Remove(itemId, amount or 1) then
        return false
    end
    send(player)
    return true
end

function InventoryService.HasItem(player, itemId, amount)
    local inventory = inventories[player]
    return inventory ~= nil and inventory:Has(itemId, amount or 1)
end

function InventoryService.GetInventory(player)
    local inventory = inventories[player]
    return inventory and inventory:Serialize() or {}
end

function InventoryService.CountParty(itemId)
    local total = 0
    for _, inventory in pairs(inventories) do
        total += inventory:Count(itemId)
    end
    return total
end

-- Descuenta primero de quien interactúa y luego del resto. Todo o nada.
function InventoryService.RemoveFromParty(player, itemId, amount)
    if InventoryService.CountParty(itemId) < amount then
        return false
    end

    local remaining = amount
    local order = {player}
    for member in pairs(inventories) do
        if member ~= player then
            table.insert(order, member)
        end
    end

    for _, member in ipairs(order) do
        local inventory = inventories[member]
        local available = inventory and inventory:Count(itemId) or 0
        local taken = math.min(available, remaining)
        if taken > 0 then
            inventory:Remove(itemId, taken)
            remaining -= taken
            send(member)
        end
        if remaining == 0 then
            break
        end
    end

    return true
end

function InventoryService.TakeQuestItems(player)
    local inventory = inventories[player]
    if not inventory then
        return {}
    end
    local taken = inventory:TakeQuestItems()
    send(player)
    return taken
end

function InventoryService.ClearAll()
    for player, inventory in pairs(inventories) do
        inventory:Clear()
        send(player)
    end
end

-- Compañero vivo y herido más cercano, dentro del alcance.
local function hurtTeammate(player, range)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local own = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not own or own.Health <= 0 then
        return nil
    end
    local best, bestDistance = nil, range
    for _, other in ipairs(Players:GetPlayers()) do
        local otherCharacter = other ~= player and other.Character
        local otherRoot = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
        local humanoid = otherCharacter and otherCharacter:FindFirstChildOfClass("Humanoid")
        if otherRoot and humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
            local distance = (otherRoot.Position - root.Position).Magnitude
            if distance <= bestDistance then
                best, bestDistance = other, distance
            end
        end
    end
    return best
end

local function useItem(player, itemId)
    if typeof(itemId) ~= "string" or not InventoryService.HasItem(player, itemId) then
        return
    end

    local definition = ItemConfig[itemId]
    if not definition or not definition.Usable then
        return
    end

    local used = false
    if itemId == "Battery" then
        used = FlashlightService.Recharge(player)
    elseif itemId == "Medkit" then
        used = DamageService.Heal(player, definition.HealAmount)
        local mate = not used and definition.ShareRange and hurtTeammate(player, definition.ShareRange)
        if mate and DamageService.Heal(mate, definition.HealAmount) then
            used = true
            Remotes.FireClient("StoryNotice", mate, player.DisplayName .. " te curó con un botiquín.")
            Remotes.FireClient("StoryNotice", player, "Curaste a " .. mate.DisplayName .. ".")
        end
    end

    if used then
        InventoryService.RemoveItem(player, itemId, 1)
        Remotes.FireClient("PlaySound", player, "Pickup")
    else
        Remotes.FireClient("StoryNotice", player, "Ahora no lo necesitás.")
    end
end

local function setupPlayer(player)
    inventories[player] = InventoryModel.new(ItemConfig, GameConfig.Inventory.MaxSlots)
    send(player)
end

function InventoryService.Start()
    Remotes.OnServer("UseItem", 5, useItem)

    Players.PlayerAdded:Connect(setupPlayer)
    -- Se borra después, para que los objetos de misión alcancen a caer al suelo.
    Players.PlayerRemoving:Connect(function(player)
        task.defer(function()
            inventories[player] = nil
        end)
    end)
    for _, player in ipairs(Players:GetPlayers()) do
        setupPlayer(player)
    end
end

return InventoryService
