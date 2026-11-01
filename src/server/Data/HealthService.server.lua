local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local healthEvent = ReplicatedStorage:WaitForChild("NocturnaRemotes"):WaitForChild("HealthUpdate")

local function setupCharacter(player, character)
    local humanoid = character:WaitForChild("Humanoid")
    humanoid.MaxHealth = 100
    humanoid.Health = 100
    humanoid.HealthChanged:Connect(function(value)
        healthEvent:FireClient(player, value, humanoid.MaxHealth)
    end)
    healthEvent:FireClient(player, humanoid.Health, humanoid.MaxHealth)
end

local function setupPlayer(player)
    player.CharacterAdded:Connect(function(character)
        setupCharacter(player, character)
    end)
    if player.Character then
        setupCharacter(player, player.Character)
    end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

print("[NOCTURNA] Sistema de salud iniciado.")