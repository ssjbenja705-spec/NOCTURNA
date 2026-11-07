-- El Coloso: lento e imparable. Mientras avanza derrumba pasillos, rompe puertas
-- y apaga luces. Con la furia del final ve, oye y corre más, pero sigue sin
-- saber dónde está quien no vio ni oyó, y corriendo se lo deja atrás.
-- Los pisotones (sonido y temblor de cámara) los hace el cliente al ritmo del paso.
local Behavior = {}

function Behavior.Init(monster)
    monster.EnvironmentClock = 0
    monster:SetState("Patrol")
end

-- Temblores y derrumbes cerca del grupo: es ambiente, no persecución.
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

local function startChase(monster, snapshot)
    monster:Engage(snapshot)
    monster:SetState("Chase")
    monster.World:Effect("ColosoRoar", {Position = monster.Position})
    monster:Gesture("Roar")
end

function Behavior.Update(monster, deltaTime)
    local settings = monster.Settings
    alterEnvironment(monster, deltaTime)
    monster.World:SmashDoorsNear(monster.Position)

    local chaseSpeed = monster.Rage and settings.RageSpeed or settings.ChaseSpeed

    if monster.State == "Chase" then
        monster.Speed = chaseSpeed
        if not monster:UpdateChase() then
            monster:SetState("Search")
            monster:BeginSearch()
        end
        return
    end

    local visible = monster:NearestVisible()
    if visible then
        monster.Speed = chaseSpeed
        startChase(monster, visible)
        return
    end

    local noise = monster:Hear()
    if noise then
        monster.NoisePosition = noise.Position
        monster.LastKnown = noise.Position
        monster:SetState("Investigate")
        monster:GoTo(noise.Position, true)
    end

    if monster.State == "Patrol" then
        monster.Speed = settings.PatrolSpeed
        monster.LookTarget = nil
        monster:Wander()
    elseif monster.State == "Investigate" then
        monster.Speed = monster.Rage and chaseSpeed or settings.InvestigateSpeed
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
