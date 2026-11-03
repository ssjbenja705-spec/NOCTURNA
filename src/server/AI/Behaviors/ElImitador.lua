-- El Imitador: elige a quien está más solo, lo llama con una voz conocida y espera
-- emboscado donde sonó esa voz.
local Behavior = {}

function Behavior.Init(monster)
    monster.LureClock = 0
    monster:SetState("Patrol")
end

-- Quien tenga a sus compañeros más lejos es la presa más fácil.
local function mostIsolated(monster)
    local snapshots = monster.World:Players()
    local best, bestScore = nil, -1

    for _, snapshot in ipairs(snapshots) do
        if not snapshot.Hidden then
            local score = 1000
            for _, other in ipairs(snapshots) do
                if other ~= snapshot then
                    score = math.min(score, (other.Position - snapshot.Position).Magnitude)
                end
            end
            if score > bestScore then
                best, bestScore = snapshot, score
            end
        end
    end

    return best
end

local function nobodyWatching(monster, position)
    for _, snapshot in ipairs(monster.World:Players()) do
        if not snapshot.Hidden and monster.World:LineOfSight(snapshot.Position, position) then
            return false
        end
    end
    return true
end

local function startLure(monster)
    local world = monster.World
    local target = mostIsolated(monster)
    if not target then
        return false
    end

    local origin = world.Nav:CellAt(target.Position)
    local cells = world.Nav:CellsBetween(origin, 2, 3)
    if #cells == 0 then
        return false
    end

    local cell = cells[world:RandomInt(1, #cells)]
    local position = world.Nav:Center(cell, monster.Height)
    if not nobodyWatching(monster, position) then
        return false
    end

    monster.Position = position
    monster:ClearPath()
    monster.AmbushTarget = target.Player

    local line = monster.Settings.Lines[world:RandomInt(1, #monster.Settings.Lines)]
    world:Effect("ImitatorVoice", {
        Position = position,
        Speaker = world:VoiceFor(target.Player),
        Text = line,
    }, target.Player)

    monster:SetState("Ambush")
    return true
end

local function retreat(monster)
    local world = monster.World
    local nearest = monster:NearestPlayer(true)
    if nearest then
        local cells = world.Nav:CellsBetween(world.Nav:CellAt(nearest.Position), 3, 6)
        if #cells > 0 then
            local position = world.Nav:Center(cells[world:RandomInt(1, #cells)], monster.Height)
            if nobodyWatching(monster, position) then
                monster.Position = position
                monster:ClearPath()
            end
        end
    end
    monster.Target = nil
    monster.LureClock = 0
    monster:SetState("Patrol")
end

function Behavior.Update(monster, deltaTime)
    local settings = monster.Settings
    monster.LureClock += deltaTime

    if monster.State == "Patrol" then
        monster.Speed = settings.PatrolSpeed
        monster:Wander()

        local visible = monster:NearestVisible()
        if visible then
            monster:Engage(visible)
            monster:SetState("Chase")
            monster.World:Effect("ImitatorScream", {Position = monster.Position})
        elseif monster.LureClock >= settings.LureInterval then
            monster.LureClock = 0
            startLure(monster)
        end
    elseif monster.State == "Ambush" then
        monster.Speed = 0
        for _, snapshot in ipairs(monster.World:Players()) do
            if not snapshot.Hidden and monster:Distance(snapshot.Position) <= settings.AmbushRange then
                monster:Engage(snapshot)
                monster:SetState("Chase")
                monster.World:Effect("ImitatorScream", {Position = monster.Position})
                return
            end
        end
        if monster.StateTime >= settings.AmbushTime then
            retreat(monster)
        end
    elseif monster.State == "Chase" then
        monster.Speed = settings.ChaseSpeed
        local chasing = monster:UpdateChase()
        if not chasing or monster.StateTime >= settings.ChaseLimit then
            retreat(monster)
        end
    end
end

return Behavior
