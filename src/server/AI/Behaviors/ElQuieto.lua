-- El Quieto: un maniquí más entre los maniquíes. Se congela si alguien lo mira,
-- pero en la oscuridad mirarlo no alcanza: hace falta luz o estar muy cerca.
-- Sólo acecha a quien vio (o a quien lo estuvo mirando); a los demás no los conoce.
--
-- Mirarlo de verdad: la cámara del jugador (ViewService; si no informó, su cabeza)
-- tiene que apuntarle dentro del cono ObserveDot, a menos de ObserveRange y sin
-- nada en el medio (rayo de oclusión hasta el pecho o la cabeza).
-- Cuando alguien empieza a mirarlo pasa SettleTime en "Settle": no avanza, pero el
-- cliente muestra micro-movimientos (cabeza, mano, postura). Después, "Frozen":
-- inmóvil por completo mientras lo sigan mirando.
local Behavior = {}

-- Puntos del cuerpo que, vistos, cuentan como "lo están mirando".
local CHEST = Vector3.new(0, 1.2, 0)
local HEAD = Vector3.new(0, 2.6, 0)

function Behavior.Init(monster)
    monster:SetState("Frozen")
end

local function sees(world, origin, look, point, settings)
    local offset = point - origin
    local distance = offset.Magnitude
    if distance > settings.ObserveRange or distance < 0.01 then
        return false
    end
    if look:Dot(offset / distance) < settings.ObserveDot then
        return false
    end
    return world:LineOfSight(origin, point)
end

-- ¿Este jugador lo está mirando (con luz o de muy cerca)?
function Behavior.IsObservedBy(monster, snapshot)
    if snapshot.Hidden then
        return false
    end
    local settings = monster.Settings
    local world = monster.World
    local origin, look = monster:ViewOf(snapshot)
    if typeof(look) ~= "Vector3" or look.Magnitude < 0.01 then
        return false
    end
    look = look.Unit

    local base = monster.Position
    local distance = (base - origin).Magnitude
    if distance > settings.ObserveRange + 3 then
        return false
    end
    local illuminated = snapshot.Flashlight or distance <= settings.CloseRange or world:IsLit(base)
    if not illuminated then
        return false
    end
    return sees(world, origin, look, base + CHEST, settings) or sees(world, origin, look, base + HEAD, settings)
end

-- Devuelve a quien lo está mirando, si hay alguien.
local function observer(monster)
    for _, snapshot in ipairs(monster.World:Players()) do
        if Behavior.IsObservedBy(monster, snapshot) then
            return snapshot
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
        monster.CurrentSpeed = 0
        monster.LookTarget = nil
        monster:ClearPath()
        if monster.State ~= "Settle" and monster.State ~= "Frozen" then
            monster:SetState("Settle")
        elseif monster.State == "Settle" and monster.StateTime >= (settings.SettleTime or 1) then
            monster:SetState("Frozen")
        end
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
