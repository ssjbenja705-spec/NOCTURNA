local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local Brain = {}

local function nearestTarget(position, maxDistance)
    local selected
    local shortest = maxDistance

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if root and humanoid and humanoid.Health > 0 then
            local distance = (root.Position - position).Magnitude
            if distance < shortest then
                shortest = distance
                selected = character
            end
        end
    end
    return selected
end

function Brain.Start(monster, settings)
    settings = settings or {}
    local humanoid = monster:FindFirstChildOfClass("Humanoid")
    local root = monster:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then
        warn("[NOCTURNA] Criatura sin Humanoid o HumanoidRootPart:", monster.Name)
        return
    end

    local detectionRange = settings.DetectionRange or 65
    local patrolSpeed = settings.Speed or 12
    local chaseSpeed = settings.ChaseSpeed or 18
    local attackDistance = settings.AttackDistance or 4
    local damage = settings.Damage or 25
    local lastAttack = 0

    task.spawn(function()
        while monster.Parent and humanoid.Health > 0 do
            local target = nearestTarget(root.Position, detectionRange)
            if target then
                local targetRoot = target:FindFirstChild("HumanoidRootPart")
                local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
                if targetRoot and targetHumanoid then
                    humanoid.WalkSpeed = chaseSpeed
                    local path = PathfindingService:CreatePath({
                        AgentRadius = 2,
                        AgentHeight = 5,
                        AgentCanJump = true,
                    })
                    local success = pcall(function()
                        path:ComputeAsync(root.Position, targetRoot.Position)
                    end)
                    if success and path.Status == Enum.PathStatus.Success then
                        local waypoint = path:GetWaypoints()[2]
                        if waypoint then
                            if waypoint.Action == Enum.PathWaypointAction.Jump then
                                humanoid.Jump = true
                            end
                            humanoid:MoveTo(waypoint.Position)
                        end
                    else
                        humanoid:MoveTo(targetRoot.Position)
                    end

                    if (root.Position - targetRoot.Position).Magnitude <= attackDistance and os.clock() - lastAttack >= 1.5 then
                        targetHumanoid:TakeDamage(damage)
                        lastAttack = os.clock()
                    end
                end
            else
                humanoid.WalkSpeed = patrolSpeed
            end
            task.wait(0.5)
        end
    end)
end

return Brain