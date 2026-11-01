local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local noiseEvent = ReplicatedStorage:WaitForChild("NocturnaRemotes"):WaitForChild("NoiseEvent")
local lastNoise = {}
local allowedNoiseTypes = {
    Walk = true,
    Run = true,
    Door = true,
    Object = true,
}

noiseEvent.OnServerEvent:Connect(function(player, noiseType)
    if typeof(noiseType) ~= "string" or not allowedNoiseTypes[noiseType] then return end

    local now = os.clock()
    if lastNoise[player] and now - lastNoise[player] < 0.25 then return end
    lastNoise[player] = now

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then return end

    workspace:SetAttribute("LastNoiseX", root.Position.X)
    workspace:SetAttribute("LastNoiseY", root.Position.Y)
    workspace:SetAttribute("LastNoiseZ", root.Position.Z)
    workspace:SetAttribute("LastNoiseLoudness", noiseType == "Run" and 1.8 or 1)
    workspace:SetAttribute("LastNoiseTime", now)
end)

Players.PlayerRemoving:Connect(function(player)
    lastNoise[player] = nil
end)

print("[NOCTURNA] Deteccion de sonidos preparada.")