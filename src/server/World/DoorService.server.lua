local CollectionService = game:GetService("CollectionService")

local function configureDoor(door)
    if not door:IsA("BasePart") then return end
    if door:GetAttribute("DoorConfigured") then return end

    door:SetAttribute("DoorConfigured", true)

    local prompt = door:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        prompt = Instance.new("ProximityPrompt")
        prompt.ActionText = "Abrir"
        prompt.ObjectText = "Puerta"
        prompt.HoldDuration = 0.5
        prompt.Parent = door
    end

    local requiredItem = door:GetAttribute("RequiredItem")
    local opened = false

    prompt.Triggered:Connect(function(player)
        if opened then return end

        if requiredItem then
            local inventory = _G.NocturnaInventory
            if not inventory or not inventory.HasItem(player, requiredItem) then
                prompt.ActionText = "Acceso denegado"
                task.wait(1)
                prompt.ActionText = "Abrir"
                return
            end

            inventory.RemoveItem(player, requiredItem, 1)
        end

        opened = true
        prompt.Enabled = false
        door.CanCollide = false
        door.Transparency = 0.7
        door:SetAttribute("Opened", true)
    end)
end

for _, door in ipairs(CollectionService:GetTagged("NocturnaDoor")) do
    configureDoor(door)
end

CollectionService:GetInstanceAddedSignal("NocturnaDoor"):Connect(configureDoor)

print("[NOCTURNA] Puertas preparadas.")
