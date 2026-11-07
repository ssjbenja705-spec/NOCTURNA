-- El Quieto: un maniquí más entre los maniquíes. Se congela si alguien lo mira,
-- pero en la oscuridad mirarlo no alcanza: hace falta luz o estar muy cerca.
-- Sólo acecha a quien vio (o a quien lo estuvo mirando); a los demás no los conoce.
local Behavior = {}

function Behavior.Init(monster)
    monster:SetState("Frozen")
end

-- Devuelve a quien lo está mirando con luz (o de muy cerca), si hay alguien.
local function observer(monster)
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
                    return snapshot
                end
            end
        end
    end

    return nil
end

-- Mientras lo miran no puede terminar el zarpazo.
function Behavior.AttackAllowed(monster)
    return observer(monster) == nil
end

-- Después de atacar se desvanece lejos: nunca se lo ve llegar dos veces.
function Behavior.OnAttackEnd(monster, hit, target)
    if not hit or not target then
        return
    end
    local world = monster.World
    local cells = world.Nav:CellsBetween(world.Nav:CellAt(target.Position), 3, 5)
    if #cells > 0 then
        monster.Position = world.Nav:Center(cells[world:RandomInt(1, #cells)], monster.Height)
        monster:ClearPath()
    end
    monster.Target = nil
    monster.LastKnown = nil
    monster:SetState("Patrol")
end

function Behavior.Update(monster)
    local settings = monster.Settings
    local watcher = observer(monster)
    if watcher then
        -- Quien lo mira sabe que está ahí, y él también sabe de quien lo mira.
        monster:Remember(watcher, true)
        if not monster.Target then
            monster:Engage(watcher)
        end
        monster.Speed = 0
        monster.LookTarget = nil
        monster:ClearPath()
        monster:SetState("Frozen")
        return
    end

    if not monster.Target then
        local visible = monster:NearestVisible()
        if visible then
            monster:Engage(visible)
        end
    end

    if monster.Target then
        monster:SetState("Stalk")
        monster.Speed = settings.ChaseSpeed
        if not monster:UpdateChase() then
            monster:SetState("Search")
            monster:BeginSearch()
        end
        return
    end

    if monster.State == "Search" then
        if not monster:UpdateSearch(settings.InvestigateSpeed) then
            monster:SetState("Patrol")
        end
        return
    end

    -- Nadie a la vista: se desplaza despacio mientras nadie lo ilumina.
    monster:SetState("Patrol")
    monster.Speed = settings.PatrolSpeed
    monster.LookTarget = nil
    monster:Wander()
end

return Behavior
