-- El Oyente: ciego. Sólo reacciona al ruido y a lo que se mueve pegado a él.
local Behavior = {}

function Behavior.Init(monster)
    monster.PulseClock = 0
    monster:SetState("Patrol")
end

local function emitClicks(monster, deltaTime)
    monster.PulseClock += deltaTime
    if monster.PulseClock >= 3 then
        monster.PulseClock = 0
        monster.World:Effect("OyenteClick", {Position = monster.Position})
    end
end

local function closeTarget(monster)
    local range = monster.Settings.CloseSense
    for _, snapshot in ipairs(monster.World:Players()) do
        if not snapshot.Hidden then
            local distance = monster:Distance(snapshot.Position)
            if distance <= 3 or (distance <= range and snapshot.Speed > 1) then
                return snapshot
            end
        end
    end
    return nil
end

function Behavior.Update(monster, deltaTime)
    local settings = monster.Settings
    emitClicks(monster, deltaTime)

    local close = closeTarget(monster)
    if close then
        monster:Engage(close)
        monster.Speed = settings.ChaseSpeed
        monster:SetState("Investigate")
        monster:GoTo(close.Position)
        monster:TryAttack(close)
        return
    end

    local noise = monster:Hear()
    if noise then
        monster.NoisePosition = noise.Position
        monster:SetState("Investigate")
        monster:GoTo(noise.Position, true)
    end

    if monster.State == "Patrol" then
        monster.Speed = settings.PatrolSpeed
        monster:Wander()
    elseif monster.State == "Investigate" then
        monster.Speed = settings.ChaseSpeed
        if not monster:HasPath() then
            monster:SetState("Search")
        end
    elseif monster.State == "Search" then
        monster.Speed = 0
        if monster.StateTime >= settings.SearchTime then
            monster:SetState("Patrol")
        end
    end
end

return Behavior
