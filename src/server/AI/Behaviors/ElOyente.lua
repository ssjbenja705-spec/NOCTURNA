-- El Oyente: ciego. Sólo reacciona al ruido y a lo que se mueve pegado a él.
-- Se detiene a escuchar con la cabeza ladeada y chasquea para ubicarse.
-- Gestos para el cliente: "Snap" (gira la cabeza de golpe hacia un ruido nuevo) y
-- "Found" (lo ubicó: se cuadra hacia el jugador antes de salir corriendo).
local Behavior = {}

function Behavior.Init(monster)
    monster.PulseClock = 0
    monster.ListenClock = 0
    monster:SetState("Patrol")
end

local function emitClicks(monster, deltaTime)
    -- Chasquidos de ecolocalización: más seguidos cuando caza.
    local interval = (monster.State == "Patrol" or monster.State == "Listen") and 3 or 1.6
    monster.PulseClock += deltaTime
    if monster.PulseClock >= interval then
        monster.PulseClock = 0
        monster.World:Effect("OyenteClick", {Position = monster.Position})
        monster:Gesture("Click")
    end
end

-- Vibraciones: lo que se mueve cerca. Agachado sólo se lo nota muy pegado.
local function closeTarget(monster)
    local range = monster.Settings.CloseSense
    for _, snapshot in ipairs(monster.World:Players()) do
        if not snapshot.Hidden then
            local distance = monster:Distance(snapshot.Position)
            local reach = snapshot.Crouching and range * 0.5 or range
            if distance <= 3 or (distance <= reach and snapshot.Speed > 1) then
                return snapshot
            end
        end
    end
    return nil
end

local function investigate(monster, noise)
    monster:Gesture("Snap")
    monster.NoisePosition = noise.Position
    monster.LastKnown = noise.Position
    monster:SetState("Investigate")
    monster:GoTo(noise.Position, true)
end

function Behavior.Update(monster, deltaTime)
    local settings = monster.Settings
    emitClicks(monster, deltaTime)

    local close = closeTarget(monster)
    if close then
        if monster.State ~= "Chase" then
            monster:Gesture("Found")
        end
        monster:Engage(close)
        monster:Remember(close, false)
        monster:SetState("Chase")
    end

    if monster.State == "Chase" then
        monster.Speed = settings.ChaseSpeed
        if not monster:UpdateChase() then
            monster:SetState("Search")
            monster:BeginSearch()
        end
        return
    end

    local noise = monster:Hear()
    if noise then
        investigate(monster, noise)
    end

    if monster.State == "Patrol" then
        monster.Speed = settings.PatrolSpeed
        monster.LookTarget = nil
        monster:Wander()
        monster.ListenClock += deltaTime
        if monster.ListenClock >= settings.ListenEvery then
            monster.ListenClock = 0
            monster:ClearPath()
            monster:SetState("Listen")
        end
    elseif monster.State == "Listen" then
        -- Pausa para escuchar: quieto, con la cabeza ladeada.
        monster.Speed = 0
        if monster.StateTime >= settings.ListenTime then
            monster:SetState("Patrol")
        end
    elseif monster.State == "Investigate" then
        monster.Speed = settings.InvestigateSpeed
        monster.LookTarget = monster.NoisePosition
        if not monster:HasPath() then
            monster:SetState("Search")
            monster:BeginSearch()
        end
    elseif monster.State == "Search" then
        if not monster:UpdateSearch(settings.InvestigateSpeed) then
            monster:SetState("Patrol")
        end
    end
end

return Behavior
