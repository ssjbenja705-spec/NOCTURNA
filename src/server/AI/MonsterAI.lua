local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")

local MonsterAI = {}

local function getCharacterData(player)
    local character = player.Character
    if not character then return nil end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root or humanoid.Health <= 0 then
        return nil
    end

    return character, humanoid, root
end

function MonsterAI.GetNearestPlayer(position, maxDistance)
    local nearestPlayer = nil
    local nearestDistance = maxDistance

    for _, player in ipairs(Players:GetPlayers()) do
        local _, _, root = getCharacterData(player)

        if root then
            local distance = (root.Position - position).Magnitude

            if distance < nearestDistance then
                nearestDistance = distance
                nearestPlayer = player
            end
        end
    end

    return nearestPlayer, nearestDistance
end

function MonsterAI.IsBeingWatched(monster, player)
    local root = monster:FindFirstChild("HumanoidRootPart")
    local _, _, playerRoot = getCharacterData(player)

    if not root or not playerRoot then return false end

    local direction = (root.Position - playerRoot.Position).Unit
    local lookDirection = player:GetAttribute("CameraLookDirection")

    if typeof(lookDirection) ~= "Vector3" then
        return false
    end

    return lookDirection:Dot(direction) > 0.82
        and (root.Position - playerRoot.Position).Magnitude < 65
end

function MonsterAI.MoveTo(monster, destination, speed)
    local humanoid = monster:FindFirstChildOfClass("Humanoid")
    local root = monster:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root then return end

    humanoid.WalkSpeed = speed

    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 5,
    })

    local success = pcall(function()
        path:ComputeAsync(root.Position, destination)
    end)

    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()

        if #waypoints >= 2 then
            local waypoint = waypoints[2]

            if waypoint.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump = true
            end

            humanoid:MoveTo(waypoint.Position)
            return
        end
    end

    humanoid:MoveTo(destination)
end

function MonsterAI.Attack(monster, player, damage, range)
    local root = monster:FindFirstChild("HumanoidRootPart")
    local _, humanoid, playerRoot = getCharacterData(player)

    if not root or not humanoid or not playerRoot then return end

    if (root.Position - playerRoot.Position).Magnitude <= range then
        local now = os.clock()
        local lastAttack = monster:GetAttribute("LastAttack") or 0

        if now - lastAttack >= 1.5 then
            monster:SetAttribute("LastAttack", now)
            humanoid:TakeDamage(damage)
        end
    end
end

return MonsterAI
