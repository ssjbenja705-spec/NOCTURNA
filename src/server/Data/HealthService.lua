-- Prepara cada personaje y avisa cuando muere. La vida no se regenera sola:
-- los botiquines son la única forma de recuperarla.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local EventBus = require(script.Parent.Parent.Core.EventBus)

local HealthService = {}

local function setupCharacter(player, character)
    local humanoid = character:WaitForChild("Humanoid", 15)
    if not humanoid then
        return
    end

    humanoid.MaxHealth = GameConfig.Player.MaxHealth
    humanoid.Health = GameConfig.Player.MaxHealth
    humanoid.WalkSpeed = GameConfig.Player.WalkSpeed
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0
    humanoid.UseJumpPower = true
    humanoid.BreakJointsOnDeath = false

    local regeneration = character:WaitForChild("Health", 3)
    if regeneration then
        regeneration:Destroy()
    end

    humanoid.Died:Connect(function()
        EventBus.Emit("PlayerDied", player, character)
    end)

    EventBus.Emit("CharacterReady", player, character)
end

local function setupPlayer(player)
    player.CharacterAdded:Connect(function(character)
        setupCharacter(player, character)
    end)
    if player.Character then
        task.spawn(setupCharacter, player, player.Character)
    end
end

function HealthService.Start()
    Players.PlayerAdded:Connect(setupPlayer)
    for _, player in ipairs(Players:GetPlayers()) do
        setupPlayer(player)
    end
end

return HealthService
