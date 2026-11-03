-- El Quieto: un maniquí más entre los maniquíes. Se congela si alguien lo mira,
-- pero en la oscuridad mirarlo no alcanza: hace falta luz o estar muy cerca.
local Behavior = {}

function Behavior.Init(monster)
    monster.Frozen = true
    monster:SetState("Frozen")
end

local function isObserved(monster)
    local settings = monster.Settings
    local world = monster.World

    for _, snapshot in ipairs(world:Players()) do
        if not snapshot.Hidden then
            local offset = monster.Position - snapshot.Position
            local flat = Vector3.new(offset.X, 0, offset.Z)
            local distance = flat.Magnitude

            if distance <= settings.ObserveRange and distance > 0.01 then
                local look = Vector3.new(snapshot.Look.X, 0, snapshot.Look.Z)
                local facing = look.Magnitude > 0.01 and look.Unit:Dot(flat.Unit) >= settings.ObserveDot
                local illuminated = snapshot.Flashlight
                    or distance <= settings.CloseRange
                    or world:IsLit(monster.Position)

                if facing and illuminated and world:LineOfSight(snapshot.Position, monster.Position) then
                    return true
                end
            end
        end
    end

    return false
end

function Behavior.Update(monster)
    if isObserved(monster) then
        monster.Speed = 0
        monster:ClearPath()
        monster:SetState("Frozen")
        return
    end

    local target = monster:NearestPlayer(false)
    if not target then
        monster.Speed = 0
        return
    end

    monster:Engage(target)
    monster:SetState("Stalk")
    monster.Speed = monster.Settings.ChaseSpeed
    monster:GoTo(target.Position)

    if monster:TryAttack(target) then
        -- Después de atacar se desvanece lejos: nunca se lo ve llegar dos veces.
        local world = monster.World
        local cells = world.Nav:CellsBetween(world.Nav:CellAt(target.Position), 3, 5)
        if #cells > 0 then
            monster.Position = world.Nav:Center(cells[world:RandomInt(1, #cells)], monster.Height)
            monster:ClearPath()
        end
    end
end

return Behavior
