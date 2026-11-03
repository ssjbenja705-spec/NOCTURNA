-- Toda interacción pasa por acá y se valida en el servidor: jugador vivo, a distancia
-- real del objeto, sin esconderse y durante la partida.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local ChapterDocuments = require(Shared.Config.DocumentConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ItemConfig = require(Shared.Config.ItemConfig)
local RateLimiter = require(Shared.Logic.RateLimiter)
local Remotes = require(Shared.Modules.RemoteHelper)

local NoiseService = require(script.Parent.Parent.AI.NoiseService)
local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local ProgressionService = require(script.Parent.Parent.Data.ProgressionService)
local InventoryService = require(script.Parent.Parent.Inventory.InventoryService)
local FeatureBuilder = require(script.Parent.FeatureBuilder)
local RoomGenerator = require(script.Parent.RoomGenerator)

local DISTANCE_MARGIN = 5

local InteractionService = {}
local limiter = RateLimiter.new(4, 6)
local pickups = {}
local documents = {}
local objectsFolder = nil
local dropCounter = 0

local function promptHost(prompt)
    local parent = prompt.Parent
    if parent and parent:IsA("Attachment") then
        return parent.Parent
    end
    return parent
end

function InteractionService.CanInteract(player, prompt)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        return false
    end
    if player:GetAttribute("Hidden") == true then
        return false
    end

    local host = promptHost(prompt)
    if not host or not host:IsA("BasePart") or not host:IsDescendantOf(workspace) then
        return false
    end

    local distance = (host.Position - root.Position).Magnitude
    return distance <= prompt.MaxActivationDistance + DISTANCE_MARGIN
end

-- Conecta un prompt con su acción. La acción sólo corre tras pasar la validación.
function InteractionService.Bind(prompt, handler)
    prompt.Triggered:Connect(function(player)
        if not GameState.IsPlaying() then
            return
        end
        if not limiter:Allow(player, os.clock()) then
            return
        end
        if InteractionService.CanInteract(player, prompt) then
            handler(player)
        end
    end)
end

local function removePickup(entry)
    pickups[entry.Key] = nil
    if entry.Part then
        entry.Part:Destroy()
    end
end

local function collect(entry, player)
    if not pickups[entry.Key] then
        return
    end

    if not InventoryService.AddItem(player, entry.Item, entry.Amount) then
        Remotes.FireClient("StoryNotice", player, "No tenés más lugar en el inventario.")
        return
    end

    local position = entry.Part.Position
    removePickup(entry)
    NoiseService.Emit(position, GameConfig.Noise.Item, player)
    Remotes.FireClient("PlaySound", player, "Pickup")
    Remotes.FireAll("StoryNotice", player.DisplayName .. " encontró: " .. ItemConfig[entry.Item].DisplayName)
    EventBus.Emit("ItemPicked", player, entry.Item, entry.Key, entry.Dropped == true)
end

function InteractionService.SpawnPickup(itemId, cframe, key, amount, dropped)
    local holder, prompt = FeatureBuilder.Pickup(objectsFolder, itemId, cframe)
    local entry = {
        Key = key,
        Item = itemId,
        Amount = amount or 1,
        Part = holder,
        Dropped = dropped,
    }
    pickups[key] = entry
    InteractionService.Bind(prompt, function(player)
        collect(entry, player)
    end)
    return entry
end

local function openDocument(entry, player)
    local isNew = ProgressionService.AddDocument(player, entry.DocumentId)
    Remotes.FireClient("DocumentOpen", player, entry.DocumentId)
    EventBus.Emit("DocumentRead", player, entry.DocumentId, entry.Group, isNew)
end

function InteractionService.Clear()
    table.clear(pickups)
    table.clear(documents)
    objectsFolder = nil
end

function InteractionService.Populate(plan, map)
    InteractionService.Clear()

    objectsFolder = Instance.new("Folder")
    objectsFolder.Name = "Objects"
    objectsFolder.Parent = map

    local layout = plan.Layout

    for _, item in ipairs(plan.Items) do
        InteractionService.SpawnPickup(item.Item, RoomGenerator.SlotCFrame(layout, item.Cell, item.Slot), item.Key)
    end

    for _, entry in ipairs(plan.Documents) do
        local definition = ChapterDocuments[entry.DocumentId]
        local cframe = RoomGenerator.SlotCFrame(layout, entry.Cell, entry.Slot)
        local holder, prompt = FeatureBuilder.Document(objectsFolder, definition.Title, cframe)
        entry.Part = holder.PrimaryPart
        table.insert(documents, entry)
        InteractionService.Bind(prompt, function(player)
            openDocument(entry, player)
        end)
    end

    return objectsFolder
end

function InteractionService.ObjectsFolder()
    return objectsFolder
end

-- Los objetos de misión de quien muere o se va quedan en el suelo para el grupo.
function InteractionService.DropQuestItems(player, position)
    if not objectsFolder or not position then
        return
    end

    for index, stack in ipairs(InventoryService.TakeQuestItems(player)) do
        dropCounter += 1
        local offset = Vector3.new(math.cos(index) * 2.5, 0, math.sin(index) * 2.5)
        local ground = Vector3.new(position.X, 0, position.Z) + offset
        InteractionService.SpawnPickup(stack.Id, CFrame.new(ground), "DROP_" .. dropCounter, stack.Amount, true)
    end
end

function InteractionService.ItemPositions(itemId)
    local result = {}
    for _, entry in pairs(pickups) do
        if entry.Item == itemId then
            table.insert(result, entry.Part.Position)
        end
    end
    return result
end

function InteractionService.DocumentPositions(group, readIds)
    local result = {}
    for _, entry in ipairs(documents) do
        if entry.Group == group and not readIds[entry.DocumentId] then
            table.insert(result, entry.Part.Position)
        end
    end
    return result
end

function InteractionService.Start()
    Players.PlayerRemoving:Connect(function(player)
        limiter:Forget(player)
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root and GameState.IsPlaying() then
            InteractionService.DropQuestItems(player, root.Position)
        end
    end)
end

return InteractionService
