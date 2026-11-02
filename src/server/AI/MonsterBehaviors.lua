local Players = game:GetService("Players")

local Behaviors = {}

local function nearestPlayer(position)
    local nearest, distance = nil, math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if root and humanoid and humanoid.Health > 0 then
            local d = (root.Position - position).Magnitude
            if d < distance then
                nearest, distance = player, d
            end
        end
    end

    return nearest, distance
end

function Behaviors.GetTarget(monster, monsterType)
    local root = monster:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local player, distance = nearestPlayer(root.Position)
    if not player then return nil end

    if monsterType == "ElQuieto" or monsterType == "Quieto" then
        local character = player.Character
        local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
        local head = character and character:FindFirstChild("Head")

        if head and playerRoot then
            local direction = (root.Position - head.Position).Unit
            local facing = head.CFrame.LookVector:Dot(direction)

            if facing > 0.75 and distance < 45 then
                return nil
            end
        end
    end

    return player
end

function Behaviors.GetSpeed(monsterType)
    local speeds = {
        ElOyente = 12,
        Oyente = 12,
        ElImitador = 14,
        Imitador = 14,
        ElQuieto = 16,
        Quieto = 16,
        ElTrepador = 17,
        Trepador = 17,
        ElColoso = 9,
        Coloso = 9,
    }

    return speeds[monsterType] or 12
end

return Behaviors
