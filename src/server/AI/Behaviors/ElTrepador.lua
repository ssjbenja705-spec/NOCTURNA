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
    local cells = world.Nav:CellsBetween(world.Nav:CellAt(monster.Position), 2, 4)
    if #cells > 0 then
        local cell = cells[world:RandomInt(1, #cells)]
        monster:GoTo(world.Nav:Center(cell, monster.Height), true)
    end
    monster:SetState("Flee")
    world:Effect("TrepadorSkitter", {Position = monster.Position})
end

function Behavior.Update(monster)
    local settings = monster.Settings

    if monster.State == "Crawl" then
        monster.Speed = settings.PatrolSpeed
        if isRepelled(monster) then
            flee(monster)
            return
        end

        local visible = monster:NearestVisible()
        local noise = monster:Hear()
        if visible then
            monster:Engage(visible)
            monster:SetState("Stalk")
        elseif noise then
            monster:GoTo(noise.Position, true)
        else
            monster:Wander()
        end
    elseif monster.State == "Stalk" then
        monster.Speed = settings.ChaseSpeed
        if isRepelled(monster) then
            monster.Target = nil
            flee(monster)
            return
        end

        local snapshot = monster.Target and monster:FindSnapshot(monster.Target)
        if not snapshot or snapshot.Hidden then
            monster.Target = nil
            monster:SetState("Crawl")
            return
        end

        monster:GoTo(snapshot.Position)
        if monster:Distance(snapshot.Position) <= settings.DropRange * 0.5 then
            drop(monster)
            monster:ClearPath()
            monster:SetState("Pounce")
            monster.World:Effect("TrepadorDrop", {Position = monster.Position})
        elseif monster.StateTime >= 20 then
            monster.Target = nil
            monster:SetState("Crawl")
        end
    elseif monster.State == "Pounce" then
        monster.Speed = settings.ChaseSpeed
        local snapshot = monster.Target and monster:FindSnapshot(monster.Target)
        if snapshot and not snapshot.Hidden then
            monster:GoTo(snapshot.Position)
            monster:TryAttack(snapshot)
        end
        if monster.StateTime >= 2.5 or monster.Clock - monster.LastAttack < 0.2 then
            climb(monster)
            monster.Target = nil
            monster:SetState("Crawl")
        end
    elseif monster.State == "Flee" then
        monster.Speed = settings.ChaseSpeed * 1.2
        if not monster:HasPath() or monster.StateTime >= settings.RepelTime then
            monster:SetState("Crawl")
        end
    end
end

return Behavior
