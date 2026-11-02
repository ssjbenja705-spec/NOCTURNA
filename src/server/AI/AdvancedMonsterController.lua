-- NOCTURNA: Advanced Monster Controller
-- Controlador compartido para los cinco monstruos.
-- Debe ser utilizado por scripts del servidor.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local Controller = {}
Controller.__index = Controller

local CONFIG = {
    ElOyente = {
        DetectionRange = 75,
        ChaseSpeed = 17,
        SearchDuration = 8,
        AttackRange = 4,
        AttackDamage = 25,
        CanHear = true,
    },
    ElImitador = {
        DetectionRange = 65,
        ChaseSpeed = 19,
        SearchDuration = 12,
        AttackRange = 4,
        AttackDamage = 30,
        CanHear = true,
    },
    ElQuieto = {
        DetectionRange = 55,
        ChaseSpeed = 15,
        SearchDuration = 10,
        AttackRange = 5,
        AttackDamage = 35,
        CanHear = false,
    },
    ElTrepador = {
        DetectionRange = 80,
        ChaseSpeed = 21,
        SearchDuration = 7,
        AttackRange = 4,
        AttackDamage = 30,
        CanHear = true,
    },
    ElColoso = {
        DetectionRange = 100,
        ChaseSpeed = 13,
        SearchDuration = 15,
        AttackRange = 7,
        AttackDamage = 45,
        CanHear = true,
    },
}

local function getCharacterData(player)
    local character = player.Character
    if not character then
        return nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or humanoid.Health <= 0 or not root then
        return nil
    end

    return character, humanoid, root
end

local function hasLineOfSight(monster, character, monsterRoot, targetRoot)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {monster}

    local direction = targetRoot.Position - monsterRoot.Position
    local result = workspace:Raycast(monsterRoot.Position, direction, params)

    return result ~= nil and result.Instance:IsDescendantOf(character)
end

function Controller.new(monster, monsterType, homePosition)
    assert(monster and monster:IsA("Model"), "Monstruo inválido")

    local humanoid = monster:FindFirstChildOfClass("Humanoid")
    local root = monster:FindFirstChild("HumanoidRootPart") or monster.PrimaryPart

    assert(humanoid, "El monstruo necesita un Humanoid")
    assert(root, "El monstruo necesita HumanoidRootPart o PrimaryPart")

    local settings = CONFIG[monsterType]
    assert(settings, "Tipo de monstruo desconocido: " .. tostring(monsterType))

    local self = setmetatable({}, Controller)

    self.Model = monster
    self.Humanoid = humanoid
    self.Root = root
    self.Type = monsterType
    self.Settings = settings
    self.HomePosition = homePosition or root.Position

    self.Target = nil
    self.State = "PATROL"
    self.LastKnownPosition = nil
    self.LastSeenTime = 0
    self.LastAttackTime = 0
    self.LastPathTime = 0
    self.Destroyed = false
    self.Heartbeat = nil
    self.Path = nil
    self.Waypoints = nil
    self.WaypointIndex = 1

    pcall(function()
        root:SetNetworkOwner(nil)
    end)

    humanoid.WalkSpeed = 8
    return self
end

function Controller:FindTarget()
    local nearestPlayer = nil
    local nearestDistance = self.Settings.DetectionRange

    for _, player in ipairs(Players:GetPlayers()) do
        local character, _, root = getCharacterData(player)

        if character then
            local distance = (root.Position - self.Root.Position).Magnitude
            if distance < nearestDistance and hasLineOfSight(
                self.Model,
                character,
                self.Root,
                root
            ) then
                nearestDistance = distance
                nearestPlayer = player
            end
        end
    end

    return nearestPlayer
end

function Controller:MoveTo(position)
    if os.clock() - self.LastPathTime < 1 then
        return
    end

    self.LastPathTime = os.clock()
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = 5,
    })

    local success = pcall(function()
        path:ComputeAsync(self.Root.Position, position)
    end)

    if success and path.Status == Enum.PathStatus.Success then
        self.Path = path
        self.Waypoints = path:GetWaypoints()
        self.WaypointIndex = 2
    else
        self.Path = nil
        self.Waypoints = nil
        self.Humanoid:MoveTo(position)
    end
end

function Controller:FollowPath()
    if not self.Waypoints then
        return
    end

    local waypoint = self.Waypoints[self.WaypointIndex]
    if not waypoint then
        self.Waypoints = nil
        return
    end

    if waypoint.Action == Enum.PathWaypointAction.Jump then
        self.Humanoid.Jump = true
    end

    if (self.Root.Position - waypoint.Position).Magnitude < 4 then
        self.WaypointIndex += 1
        waypoint = self.Waypoints[self.WaypointIndex]
        if not waypoint then
            self.Waypoints = nil
            return
        end
    end

    self.Humanoid:MoveTo(waypoint.Position)
end

function Controller:Attack(player)
    local now = os.clock()
    if now - self.LastAttackTime < 1.5 then
        return
    end

    local _, targetHumanoid, targetRoot = getCharacterData(player)
    if not targetHumanoid or not targetRoot then
        return
    end

    local distance = (targetRoot.Position - self.Root.Position).Magnitude
    if distance <= self.Settings.AttackRange then
        self.LastAttackTime = now
        targetHumanoid:TakeDamage(self.Settings.AttackDamage)
    end
end

function Controller:Update()
    if self.Destroyed or self.Humanoid.Health <= 0 then
        self:Stop()
        return
    end

    local now = os.clock()

    if self.State == "PATROL" then
        local target = self:FindTarget()
        if target then
            self.Target = target
            self.State = "CHASE"
            self.Humanoid.WalkSpeed = self.Settings.ChaseSpeed
        else
            self.Humanoid.WalkSpeed = 8
            if (self.Root.Position - self.HomePosition).Magnitude > 8 then
                self:MoveTo(self.HomePosition)
                self:FollowPath()
            end
        end
    elseif self.State == "CHASE" then
        local character, _, targetRoot = getCharacterData(self.Target)
        if not character then
            self.State = "SEARCH"
            self.LastSeenTime = now
            return
        end

        local distance = (targetRoot.Position - self.Root.Position).Magnitude
        if distance > self.Settings.DetectionRange * 1.5 then
            self.LastKnownPosition = targetRoot.Position
            self.State = "SEARCH"
            self.LastSeenTime = now
            return
        end

        if hasLineOfSight(self.Model, character, self.Root, targetRoot) then
            self.LastKnownPosition = targetRoot.Position
            self.LastSeenTime = now
        end

        self:MoveTo(targetRoot.Position)
        self:FollowPath()
        self:Attack(self.Target)
    elseif self.State == "SEARCH" then
        if now - self.LastSeenTime >= self.Settings.SearchDuration then
            self.Target = nil
            self.State = "RETURN"
            return
        end

        if self.LastKnownPosition then
            self:MoveTo(self.LastKnownPosition)
            self:FollowPath()
        end

        local target = self:FindTarget()
        if target then
            self.Target = target
            self.State = "CHASE"
        end
    elseif self.State == "RETURN" then
        if (self.Root.Position - self.HomePosition).Magnitude < 6 then
            self.State = "PATROL"
            self.Humanoid.WalkSpeed = 8
            return
        end

        self:MoveTo(self.HomePosition)
        self:FollowPath()
    end
end

function Controller:Start()
    if self.Heartbeat then
        return
    end

    local elapsed = 0
    self.Heartbeat = RunService.Heartbeat:Connect(function(deltaTime)
        elapsed += deltaTime
        if elapsed < 0.2 then
            return
        end

        elapsed = 0
        local success, err = pcall(function()
            self:Update()
        end)
        if not success then
            warn("[NOCTURNA] Error de IA:", self.Type, err)
        end
    end)
end

function Controller:Stop()
    self.Destroyed = true
    if self.Heartbeat then
        self.Heartbeat:Disconnect()
        self.Heartbeat = nil
    end

    self.Humanoid:MoveTo(self.Root.Position)
end

return Controller
