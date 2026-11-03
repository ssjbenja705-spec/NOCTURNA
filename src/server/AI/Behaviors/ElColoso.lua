-- El Coloso: lento e imparable. Mientras avanza derrumba pasillos, rompe puertas
-- y apaga luces; con la furia del final alcanza a quien se quede atrás.
local Behavior = {}

function Behavior.Init(monster)
    monster.EnvironmentClock = 0
    monster.StepClock = 0
    monster:SetState("Patrol")
end

local function stomp(monster, deltaTime)
    monster.StepClock += deltaTime
    if monster.StepClock >= 1.4 and monster.Speed > 0 then
        monster.StepClock = 0
        monster.World:Effect("ColosoStep", {Position = monster.Position})
    end
end

local function alterEnvironment(monster, deltaTime)
    monster.EnvironmentClock += deltaTime
    if monster.EnvironmentClock < monster.Settings.EnvironmentInterval then
        return
    end

    local nearest, distance = monster:NearestPlayer(true)
    if nearest and distance < 90 then
        monster.EnvironmentClock = 0
        monster.World:Quake(monster.Position)
        monster.World:Collapse(monster, nearest.Position)
    end
end

function Behavior.Update(monster, deltaTime)
    local settings = monster.Settings
    stomp(monster, deltaTime)
    alterEnvironment(monster, deltaTime)
    monster.World:SmashDoorsNear(monster.Position)

    local chaseSpeed = monster.Rage and settings.RageSpeed or settings.ChaseSpeed

    if monster.State == "Patrol" then
        monster.Speed = settings.PatrolSpeed
        local visible = monster:NearestVisible()
        local noise = monster:Hear()

        if visible then
            monster:Engage(visible)
            monster:SetState("Chase")
            monster.World:Effect("ColosoRoar", {Position = monster.Position})
        elseif monster.Rage then
            local nearest = monster:NearestPlayer(false)
            if nearest then
                monster:Engage(nearest)
                monster:SetState("Chase")
            end
        elseif noise then
            monster.NoisePosition = noise.Position
            monster:SetState("Investigate")
            monster:GoTo(noise.Position, true)
        else
            monster:Wander()
        end
    elseif monster.State == "Investigate" then
        monster.Speed = chaseSpeed
        local visible = monster:NearestVisible()
        if visible then
            monster:Engage(visible)
            monster:SetState("Chase")
        elseif not monster:HasPath() then
            monster:SetState("Search")
        end
    elseif monster.State == "Search" then
        monster.Speed = 0
        local visible = monster:NearestVisible()
        if visible then
            monster:Engage(visible)
            monster:SetState("Chase")
        elseif monster.StateTime >= settings.SearchTime then
            monster:SetState("Patrol")
        end
    elseif monster.State == "Chase" then
        monster.Speed = chaseSpeed
        if not monster:UpdateChase() then
            monster:SetState("Search")
        end
    end
end

return Behavior
