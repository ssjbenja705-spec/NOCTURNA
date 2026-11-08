-- El Trepador: recorre el techo boca abajo, se deja caer sobre quien no mira y
-- vuelve a subir. La linterna apuntada lo hace huir.
--
-- Pasar del techo al piso no es instantáneo: "Drop" dura DropTime (cae girando
-- sobre su eje de avance y aterriza encima del jugador, ya atacando) y "Climb"
-- dura ClimbTime (sube y se da vuelta hasta quedar colgado). El cliente anima
-- esas transiciones (y, si hay una pared cerca, sube por ella).
local Behavior = {}

-- Boca abajo, con los pies apoyados en el techo.
local function ceilingHeight(monster)
    return monster.World.CeilingHeight - monster.Settings.BodyHeight
end

local function setHeight(monster, height)
    monster.Height = height
    monster.Position = Vector3.new(monster.Position.X, height, monster.Position.Z)
end

local function settleOnCeiling(monster)
    setHeight(monster, ceilingHeight(monster))
    monster.Up = Vector3.new(0, -1, 0)
    monster.Roll = 0
end

local function settleOnFloor(monster)
    setHeight(monster, monster.Settings.BodyHeight)
    monster.Up = Vector3.new(0, 1, 0)
    monster.Roll = 0
end

-- Durante la transición la orientación se expresa con Roll (π = boca abajo).
local function startTransition(monster, kind)
    local settings = monster.Settings
    local onCeiling = monster.Up.Y < 0 or math.abs(monster.Roll) > math.pi / 2
    local toCeiling = kind == "Climb"
    monster.Transition = {
        Kind = kind,
        Time = 0,
        Duration = toCeiling and (settings.ClimbTime or 0.9) or (settings.DropTime or 0.4),
        From = monster.Height,
        To = toCeiling and ceilingHeight(monster) or settings.BodyHeight,
        FromRoll = onCeiling and math.pi or 0,
        ToRoll = toCeiling and math.pi or 0,
    }
    monster.Up = Vector3.new(0, 1, 0)
    monster.Roll = monster.Transition.FromRoll
    monster.Speed = 0
    monster:ClearPath()
    monster:SetState(kind)
end

local function smooth(alpha)
    return alpha * alpha * (3 - 2 * alpha)
end

-- Avanza la transición. Devuelve true mientras siga en curso.
local function updateTransition(monster, deltaTime)
    local transition = monster.Transition
    if not transition then
        return false
    end
    transition.Time += deltaTime
    local alpha = math.clamp(transition.Time / transition.Duration, 0, 1)
    -- Cae acelerando; sube con arranque y llegada suaves.
    local heightAlpha = transition.Kind == "Drop" and alpha * alpha or smooth(alpha)
    -- Se da vuelta antes de tocar el piso (o apenas despega, al subir).
    local rollAlpha = smooth(math.clamp(transition.Kind == "Drop" and alpha / 0.75 or (alpha - 0.15) / 0.75, 0, 1))
    setHeight(monster, transition.From + (transition.To - transition.From) * heightAlpha)
    monster.Roll = transition.FromRoll + (transition.ToRoll - transition.FromRoll) * rollAlpha
    monster.Speed = 0
    if alpha < 1 then
        return true
    end

    monster.Transition = nil
    if transition.Kind == "Drop" then
        settleOnFloor(monster)
        monster:SetState("Pounce")
        -- Ataque desde arriba: aterriza ya lanzando el zarpazo si lo tiene al alcance.
        local snapshot = monster.Target and monster:FindSnapshot(monster.Target)
        if snapshot and not snapshot.Hidden then
            monster:TryAttack(snapshot)
        end
    else
        settleOnCeiling(monster)
        monster:SetState("Crawl")
    end
    return true
end

function Behavior.Init(monster)
    settleOnCeiling(monster)
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
        settleOnCeiling(monster)
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
    monster.Target = nil
    monster:ClearPath()
    if monster.Height < ceilingHeight(monster) - 0.01 then
        startTransition(monster, "Climb")
    else
        settleOnCeiling(monster)
        monster:SetState("Crawl")
    end
end

-- Retenido o aturdido a mitad de camino entre el techo y el piso: cae al piso.
function Behavior.OnInterrupt(monster)
    if monster.Transition then
        monster.Transition = nil
        settleOnFloor(monster)
        monster:SetState("Pounce")
    end
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
        monster.LookTarget = snapshot.Position
        startTransition(monster, "Drop")
        monster.World:Effect("TrepadorDrop", {Position = monster.Position})
        monster:Gesture("Drop")
    end
end

function Behavior.Update(monster, deltaTime)
    local settings = monster.Settings

    if updateTransition(monster, deltaTime or 0) then
        return
    end

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
