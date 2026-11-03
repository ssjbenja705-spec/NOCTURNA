-- Ruido autoritativo. El servidor lo calcula con la velocidad real del personaje;
-- el cliente ya no puede enviar ni silenciar sus propios ruidos.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local GameState = require(script.Parent.Parent.Core.GameState)

local CONFIG = GameConfig.Noise
local SAMPLE_INTERVAL = 0.4

local NoiseService = {}
local noises = {}

local function prune(now)
    for index = #noises, 1, -1 do
        if now - noises[index].Time > CONFIG.Lifetime then
            table.remove(noises, index)
        end
    end
end

function NoiseService.Emit(position, radius, source)
    table.insert(noises, {
        Position = position,
        Radius = radius,
        Time = os.clock(),
        Source = source,
    })
end

function NoiseService.Recent()
    prune(os.clock())
    return noises
end

function NoiseService.Clear()
    table.clear(noises)
end

local function samplePlayer(player)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        return
    end
    if player:GetAttribute("Hidden") == true then
        return
    end

    local speed = (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
    if speed < 2 then
        return
    end

    local radius = CONFIG.Walk
    if player:GetAttribute("IsCrouching") == true then
        radius = CONFIG.Crouch
    elseif speed > GameConfig.Player.WalkSpeed + 2 then
        radius = CONFIG.Sprint
    end

    NoiseService.Emit(root.Position, radius, player)
end

function NoiseService.Start()
    local elapsed = 0
    RunService.Heartbeat:Connect(function(deltaTime)
        elapsed += deltaTime
        if elapsed < SAMPLE_INTERVAL then
            return
        end
        elapsed = 0

        if GameState.IsPlaying() then
            for _, player in ipairs(Players:GetPlayers()) do
                samplePlayer(player)
            end
        end
    end)
end

return NoiseService
