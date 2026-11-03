-- Cuerpo común de las criaturas: movimiento, percepción y ataque.
-- No toca instancias: todo pasa por `world`, así las pruebas lo ejercitan sin Roblox.
local MonsterController = {}
MonsterController.__index = MonsterController

local REPATH_INTERVAL = 0.5
local ARRIVE_DISTANCE = 1.2
local HIDE_NOTICE_WINDOW = 1.5

function MonsterController.new(kind, settings, behavior, world, position, scale)
    local self = setmetatable({
        Kind = kind,
        Settings = settings,
        Behavior = behavior,
        World = world,
        Position = position,
        Facing = Vector3.new(0, 0, 1),
        Up = Vector3.new(0, 1, 0),
        Height = settings.BodyHeight,
        Speed = 0,
        SpeedScale = scale and scale.Speed or 1,
        DamageScale = scale and scale.Damage or 1,
        State = "Idle",
        StateTime = 0,
        Clock = 0,
        Waypoints = nil,
        WaypointIndex = 1,
        PathClock = -100,
        LastAttack = -100,
        LastSeen = {},
        Target = nil,
        HeardUntil = 0,
        Stunned = 0,
        Rage = false,
        Encountered = {},
    }, MonsterController)

    self.Position = Vector3.new(position.X, self.Height, position.Z)
    behavior.Init(self)
    return self
end

function MonsterController:SetState(state)
    if self.State ~= state then
        self.State = state
        self.StateTime = 0
        self.World:OnStateChanged(self, state)
    end
end

function MonsterController:Distance(position)
    local offset = position - self.Position
    return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

function MonsterController:ClearPath()
    self.Waypoints = nil
    self.WaypointIndex = 1
end

function MonsterController:HasPath()
    return self.Waypoints ~= nil and self.WaypointIndex <= #self.Waypoints
end

function MonsterController:GoTo(position, force)
    if not force and self.Clock - self.PathClock < REPATH_INTERVAL then
        return self:HasPath()
    end

    self.PathClock = self.Clock
    local points = self.World.Nav:Waypoints(self.Position, position, self.Height)
    if not points then
        self:ClearPath()
        return false
    end

    self.Waypoints = points
    self.WaypointIndex = 1
    return true
end

function MonsterController:MoveStep(deltaTime)
    local budget = self.Speed * self.SpeedScale * deltaTime

    while budget > 0 and self:HasPath() do
        local waypoint = self.Waypoints[self.WaypointIndex]
        local offset = waypoint - self.Position
        local distance = offset.Magnitude

        if distance <= math.max(budget, ARRIVE_DISTANCE * 0.25) then
            self.Position = waypoint
            budget -= distance
            self.WaypointIndex += 1
        else
            local direction = offset / distance
            self.Position += direction * budget
            local flat = Vector3.new(direction.X, 0, direction.Z)
            if flat.Magnitude > 0.05 then
                self.Facing = flat.Unit
            end
            budget = 0
        end
    end

    if not self:HasPath() then
        self:ClearPath()
    end
end

-- Paseo por celdas cercanas, con tendencia a acercarse al grupo.
function MonsterController:Wander()
    if self:HasPath() then
        return
    end

    local cell = self.World:PatrolCell(self)
    if cell then
        self:GoTo(self.World.Nav:Center(cell, self.Height), true)
    end
end

function MonsterController:CanSee(snapshot)
    local range = self.Settings.VisionRange or 0
    if range <= 0 or snapshot.Hidden then
        return false
    end

    -- La linterna encendida delata a más distancia; agacharse en la oscuridad la acorta.
    local effective = snapshot.Flashlight and range or range * 0.65
    local eye = Vector3.new(self.Position.X, math.max(self.Position.Y, 3), self.Position.Z)
    if (snapshot.Position - eye).Magnitude > effective then
        return false
    end

    return self.World:LineOfSight(eye, snapshot.Position)
end

function MonsterController:NearestVisible()
    local best, bestDistance = nil, math.huge
    for _, snapshot in ipairs(self.World:Players()) do
        if self:CanSee(snapshot) then
            self.LastSeen[snapshot.Player] = self.Clock
            local distance = self:Distance(snapshot.Position)
            if distance < bestDistance then
                best, bestDistance = snapshot, distance
            end
        end
    end
    return best, bestDistance
end

function MonsterController:NearestPlayer(includeHidden)
    local best, bestDistance = nil, math.huge
    for _, snapshot in ipairs(self.World:Players()) do
        if includeHidden or not snapshot.Hidden then
            local distance = self:Distance(snapshot.Position)
            if distance < bestDistance then
                best, bestDistance = snapshot, distance
            end
        end
    end
    return best, bestDistance
end

function MonsterController:FindSnapshot(player)
    for _, snapshot in ipairs(self.World:Players()) do
        if snapshot.Player == player then
            return snapshot
        end
    end
    return nil
end

-- El ruido nuevo más fuerte que llega hasta la criatura.
function MonsterController:Hear()
    local multiplier = self.Settings.HearingMultiplier or 0
    if multiplier <= 0 then
        return nil
    end

    local best, bestScore = nil, 0
    for _, noise in ipairs(self.World:Noises()) do
        if noise.Time > self.HeardUntil then
            local score = noise.Radius * multiplier - self:Distance(noise.Position)
            if score > bestScore then
                best, bestScore = noise, score
            end
        end
    end

    if best then
        self.HeardUntil = best.Time
    end
    return best
end

function MonsterController:TryAttack(snapshot)
    if self.Clock - self.LastAttack < self.Settings.AttackCooldown then
        return false
    end
    if self:Distance(snapshot.Position) > self.Settings.AttackRange then
        return false
    end

    self.LastAttack = self.Clock
    self.Stunned = 1.1
    self:ClearPath()
    self.World:Damage(self, snapshot, self.Settings.Damage * self.DamageScale)
    return true
end

function MonsterController:Engage(snapshot)
    self.Target = snapshot.Player
    if not self.Encountered[snapshot.Player] then
        self.Encountered[snapshot.Player] = true
        self.World:Encounter(self, snapshot)
    end
end

-- Persecución compartida. Devuelve false cuando se perdió el objetivo.
function MonsterController:UpdateChase()
    local snapshot = self.Target and self:FindSnapshot(self.Target)
    if not snapshot then
        self.Target = nil
        return false
    end

    if snapshot.Hidden then
        local lastSeen = self.LastSeen[snapshot.Player] or -100
        local sawHiding = self.Clock - (snapshot.HiddenFor or 0) - lastSeen <= HIDE_NOTICE_WINDOW
        if not sawHiding then
            self.Target = nil
            return false
        end

        self:GoTo(snapshot.Position)
        if self:Distance(snapshot.Position) <= self.Settings.AttackRange then
            self.World:PullOut(self, snapshot)
            self:TryAttack(snapshot)
        end
        return true
    end

    if self:CanSee(snapshot) then
        self.LastSeen[snapshot.Player] = self.Clock
    end

    self:GoTo(snapshot.Position)
    self:TryAttack(snapshot)
    return true
end

function MonsterController:Tick(deltaTime)
    self.Clock += deltaTime
    self.StateTime += deltaTime

    if self.Stunned > 0 then
        self.Stunned -= deltaTime
        return
    end

    self.Behavior.Update(self, deltaTime)
    self:MoveStep(deltaTime)
    self.World:OpenDoorsNear(self.Position)
end

function MonsterController:GetCFrame()
    return CFrame.lookAt(self.Position, self.Position + self.Facing, self.Up)
end

return MonsterController
