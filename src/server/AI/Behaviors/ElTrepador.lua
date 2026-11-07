-- El Trepador: recorre el techo boca abajo, se deja caer sobre quien no mira y
-- vuelve a subir. La linterna apuntada lo hace huir.
local Behavior = {}

-- Boca abajo, con los pies apoyados en el techo.
local function ceilingHeight(monster)
    return monster.World.CeilingHeight - monster.Settings.BodyHeight
end

local function climb(monster)
    monster.Height = ceilingHeight(monster)
    monster.Position = Vector3.new(monster.Position.X, monster.Height, monster.Position.Z)
    monster.Up = Vector3.new(0, -1, 0)
end

local function drop(monster)
    monster.Height = monster.Settings.BodyHeight
    monster.Position = Vector3.new(monster.Position.X, monster.Height, monster.Position.Z)
    monster.Up = Vector3.new(0, 1, 0)
end

function Behavior.Init(monster)
    climb(monster)
    monster:SetState("Crawl")
end

-- ¿Alguien le apunta con la linterna?
local function isRepelled(monster)
    local settings = monster.Settings
    for _, snapshot in ipairs(monster.World:Players()) do
        if snapshot.Flashlight and not snapshot.Hidden then
            local offset = monster.Position - snapshot.Position
            local flat = Vector3.new(offset.X, 0, offset.Z)
            local distance = flat.Magnitude
            local look = Vector3.new(snapshot.Look.X, 0, snapshot.Look.Z)
            if distance <= settings.RepelRange and distance > 0.01 and look.Magnitude > 0.01
                and look.Unit:Dot(flat.Unit) >= settings.RepelDot
                and monster.World:LineOfSight(snapshot.Position, monster.Position) then
                return true
            end
        end
    end
    return false
end

local function flee(monster)
    local world = monster.World
    if monster.Height < ceilingHeight(monster) then
        climb(monster)
    end
    local cells = world.Nav:CellsBetween(world.Nav:CellAt(monster.Position), 2, 4)
    if #cells > 0 then
        local cell = cells[world:RandomInt(1, #cells)]
        monster:GoTo(world.Nav:Center(cell, monster.Height), true)
    end
    monster.Target = nil
    monster.LookTarget = nil
    monster:SetState("Flee")
    world:Effect("TrepadorSkitter", {Position = monster.Position})
    monster:Gesture("Skitter")
end

local function backToCeiling(monster)
    climb(monster)
    monster.Target = nil
    monster:ClearPath()
    monster:SetState("Crawl")
end

-- Después del zarpazo vuelve a subir: nunca se queda peleando en el piso.
function Behavior.OnAttackEnd(monster)
    backToCeiling(monster)
end

-- Acecho desde el techo: sigue a quien percibe; si lo pierde, busca y se rinde.
local function stalk(monster)
    local settings = monster.Settings
    local snapshot = monster.Target and monster:FindSnapshot(monster.Target)
    if not snapshot or snapshot.Hidden then
        monster.Target = nil
        monster:SetState("Search")
        monster:BeginSearch()
        return
    end

    monster:Perceive(snapshot)
    local since = monster:SinceSensed(snapshot.Player)
    if since > settings.LoseTime or monster.StateTime >= settings.StalkLimit then
        monster.Target = nil
        monster:SetState("Search")
        monster:BeginSearch()
        return
    end

    local goal = since <= 1.2 and snapshot.Position or monster.LastKnown or snapshot.Position
    monster.LookTarget = goal
    monster:GoTo(goal)
    if since <= 1.2 and monster:Distance(snapshot.Position) <= settings.DropRange * 0.5 then
        drop(monster)
        monster:ClearPath()
        monster:SetState("Pounce")
        monster.World:Effect("TrepadorDrop", {Position = monster.Position})
        monster:Gesture("Drop")
    end
end

function Behavior.Update(monster)
    local settings = monster.Settings

    if monster.State ~= "Flee" and monster.State ~= "Pounce" and isRepelled(monster) then
        flee(monster)
        return
    end

    if monster.State == "Crawl" or monster.State == "Investigate" then
        local visible = monster:NearestVisible()
        if visible then
            monster:Engage(visible)
            monster:SetState("Stalk")
            return
        end

        local noise = monster:Hear()
        if noise then
            monster.NoisePosition = noise.Position
            monster.LastKnown = noise.Position
            monster:SetState("Investigate")
            monster:GoTo(noise.Position, true)
        end

        if monster.State == "Crawl" then
            monster.Speed = settings.PatrolSpeed
            monster.LookTarget = nil
            monster:Wander()
        else
            monster.Speed = settings.InvestigateSpeed
            monster.LookTarget = monster.NoisePosition
            if not monster:HasPath() then
                monster:SetState("Search")
                monster:BeginSearch()
            end
        end
    elseif monster.State == "Stalk" then
        monster.Speed = settings.ChaseSpeed
        stalk(monster)
    elseif monster.State == "Search" then
        local visible = monster:NearestVisible()
        if visible then
            monster:Engage(visible)
            monster:SetState("Stalk")
        elseif not monster:UpdateSearch(settings.InvestigateSpeed) then
            monster:SetState("Crawl")
        end
    elseif monster.State == "Pounce" then
        monster.Speed = settings.ChaseSpeed
        local chasing = monster:UpdateChase()
        if not chasing or monster.StateTime >= settings.PounceTime then
            backToCeiling(monster)
        end
    elseif monster.State == "Flee" then
        monster.Speed = settings.FleeSpeed
        if not monster:HasPath() or monster.StateTime >= settings.RepelTime then
            monster:SetState("Crawl")
        end
    end
end

return Behavior
