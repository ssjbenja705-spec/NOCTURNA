local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("NocturnaRemotes")

local names = {
    "InventoryUpdate",
    "ObjectiveUpdate",
    "InteractionEvent",
    "NoiseEvent",
    "HealthUpdate",
    "AdminMessage",
}

for _, name in ipairs(names) do
    if not folder:FindFirstChild(name) then
        local event = Instance.new("RemoteEvent")
        event.Name = name
        event.Parent = folder
    end
end

print("[NOCTURNA] Eventos adicionales preparados.")