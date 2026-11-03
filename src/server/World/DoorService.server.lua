local CollectionService = game:GetService("CollectionService")

local function configureDoor(door)
    if not door:IsA("BasePart") or door:GetAttribute("DoorConfigured") then
        return
    end
    door:SetAttribute("DoorConfigured", true)

    local prompt = door:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        prompt = Instance.new("ProximityPrompt")
        prompt.ActionText = "Abrir"
        prompt.ObjectText = "Puerta"
        prompt.HoldDuration = 0.5
        prompt.MaxActivationDistance = 10
        prompt.Parent = door
    end

    local requiredItem = door:GetAttribute("RequiredItem")
    local opened = door:GetAttribute("Opened") == true
    prompt.Enabled = not opened

    prompt.Triggered:Connect(function(player)
        if opened or not door.Parent then return end

        -- Revalidar y consumir en el servidor. No abrir si el objeto no pudo
        -- descontarse del inventario (por ejemplo, dos jugadores a la vez).
        if requiredItem ~= nil then
            if typeof(requiredItem) ~= "string" then return end
            local inventory = _G.NocturnaInventory
            if not inventory or not inventory.HasItem(player, requiredItem) then
                prompt.ActionText = "Acceso denegado"
                task.delay(1, function()
                    if prompt.Parent and not opened then
                        prompt.ActionText = "Abrir"
                    end
                end)
                return
            end
            if not inventory.RemoveItem(player, requiredItem, 1) then
                return
            end
        end

        opened = true
        door:SetAttribute("Opened", true)
        prompt.Enabled = false
        door.CanCollide = false
        door.Transparency = math.max(door.Transparency, 0.7)
    end)
end

for _, door in ipairs(CollectionService:GetTagged("NocturnaDoor")) do
    configureDoor(door)
end

CollectionService:GetInstanceAddedSignal("NocturnaDoor"):Connect(configureDoor)

print("[NOCTURNA] Puertas preparadas.")
