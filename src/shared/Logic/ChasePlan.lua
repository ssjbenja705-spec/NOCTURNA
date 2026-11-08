-- Lógica pura de la persecución final: la secuencia de obstáculos, el paso de la
-- criatura (un elástico que mantiene el peligro sin ser injusto) y qué acción
-- pide cada obstáculo. No toca instancias: la usan el servidor, el cliente y las
-- pruebas por igual.
local ChasePlan = {}

local function lerp(a, b, alpha)
    return a + (b - a) * math.clamp(alpha, 0, 1)
end

ChasePlan.Lerp = lerp

-- Avance de 0 a 1 sobre la galería.
function ChasePlan.Progress(config, s)
    return math.clamp(s / config.Arena.FinishS, 0, 1)
end

-- ¿Puede ir este tipo después de los anteriores? Nunca tres iguales seguidos, ni
-- dos compuertas o dos derrumbes pegados.
local function allowed(history, kind)
    local last = history[#history]
    local before = history[#history - 1]
    if last == kind and before == kind then
        return false
    end
    if (kind == "Door" or kind == "Debris") and last == kind then
        return false
    end
    return true
end

ChasePlan.Allowed = allowed

-- Arma la lista de obstáculos para una semilla (un Rng de Shared.Logic.Rng).
-- Cada uno: {Id, Kind, S, Side}. Side sólo en derrumbes: -1 izquierda, 0 centro,
-- 1 derecha (la franja donde cae).
function ChasePlan.Generate(rng, config)
    local settings = config.Obstacles
    local limit = config.Arena.FinishS - settings.LastBefore
    local list = {}
    local history = {}
    local s = settings.FirstS

    local function add(kind)
        local entry = {Id = #list + 1, Kind = kind, S = math.floor(s * 10 + 0.5) / 10}
        if kind == "Debris" then
            entry.Side = rng:Pick({-1, 0, 1})
        end
        table.insert(list, entry)
        table.insert(history, kind)

        local progress = ChasePlan.Progress(config, s)
        local spacing = lerp(settings.SpacingStart, settings.SpacingEnd, progress)
        spacing *= 0.9 + rng:Float() * 0.2
        if kind == "Door" or kind == "Debris" then
            spacing += settings.RecoverySpacing
        end
        s += spacing
    end

    for _, kind in ipairs(settings.Intro) do
        if s > limit then
            break
        end
        add(kind)
    end

    while s <= limit do
        local kind = nil
        for _ = 1, 24 do
            local candidate = rng:Pick(settings.Pool)
            if allowed(history, candidate) then
                kind = candidate
                break
            end
        end
        add(kind or "Vault")
    end

    return list
end

-- Comprueba que una lista cumpla las reglas (las pruebas la usan con miles de semillas).
function ChasePlan.Validate(list, config)
    local settings = config.Obstacles
    local history = {}
    local previous = nil
    for index, entry in ipairs(list) do
        if entry.Id ~= index then
            return false, "ids fuera de orden"
        end
        if config.Actions[entry.Kind] == nil and entry.Kind ~= "Debris" then
            return false, "tipo desconocido " .. tostring(entry.Kind)
        end
        if entry.S < settings.FirstS or entry.S > config.Arena.FinishS - settings.LastBefore then
            return false, "fuera de la galería: " .. entry.S
        end
        if previous and entry.S - previous.S < settings.SpacingEnd * 0.9 - 0.15 then
            return false, string.format("obstáculos pegados en %.1f y %.1f", previous.S, entry.S)
        end
        if index > #settings.Intro and not allowed(history, entry.Kind) then
            return false, "repetición en " .. entry.S
        end
        table.insert(history, entry.Kind)
        previous = entry
    end
    return true
end

-- Ritmo base y distancia deseada según el avance del último jugador.
function ChasePlan.Pace(config, progress)
    local creature = config.Creature
    return lerp(creature.PaceStart, creature.PaceEnd, progress)
end

function ChasePlan.TargetGap(config, progress)
    local creature = config.Creature
    return lerp(creature.GapStart, creature.GapEnd, progress)
end

function ChasePlan.NewCreature(config, rearS)
    return {S = rearS - config.Creature.StartGap, Speed = 0, Recoil = 0}
end

-- Un paso de la criatura detrás del último jugador (rearS). multiplier es el de la
-- dificultad. Siempre deja a la criatura entre MinGap y MaxGap detrás del último.
function ChasePlan.StepCreature(state, rearS, deltaTime, config, multiplier)
    local creature = config.Creature
    local progress = ChasePlan.Progress(config, rearS)
    local gap = rearS - state.S

    local desired
    if state.Recoil > 0 then
        state.Recoil = math.max(0, state.Recoil - deltaTime)
        desired = 0
    else
        desired = ChasePlan.Pace(config, progress) * (multiplier or 1)
            + creature.BandGain * (gap - ChasePlan.TargetGap(config, progress))
        desired = math.clamp(desired, creature.MinSpeed, creature.MaxSpeed)
    end

    local change = desired - state.Speed
    local up = creature.Acceleration * deltaTime
    local down = creature.Deceleration * deltaTime
    state.Speed = math.max(0, state.Speed + math.clamp(change, -down, up))
    state.S += state.Speed * deltaTime

    if state.S > rearS - creature.MinGap then
        state.S = rearS - creature.MinGap
    end
    if rearS - state.S > creature.MaxGap then
        state.S = rearS - creature.MaxGap
    end
    return state
end

function ChasePlan.Caught(state, s, config)
    return s - state.S <= config.Creature.CatchDistance
end

function ChasePlan.ActionFor(config, kind)
    return config.Actions[kind]
end

-- El obstáculo (de los que todavía no resolvió este jugador) para el que vale
-- esta acción desde la posición s. resolved: {[id] = true}.
function ChasePlan.ActionTarget(list, s, action, config, resolved)
    local settings = config.Obstacles
    for _, entry in ipairs(list) do
        if not resolved[entry.Id] and config.Actions[entry.Kind] == action and entry.Kind ~= "Door" then
            if s >= entry.S - settings.ActionReach and s <= entry.S + settings.ActionLate then
                return entry
            end
        end
    end
    return nil
end

-- Próximo obstáculo delante de s que este jugador todavía tiene que resolver.
function ChasePlan.NextObstacle(list, s, resolved, doors)
    for _, entry in ipairs(list) do
        local done = resolved[entry.Id] or (entry.Kind == "Door" and doors and doors[entry.Id])
        if not done and entry.S >= s - 2 then
            return entry
        end
    end
    return nil
end

-- ¿La posición lateral (0 = centro) queda dentro de la franja del derrumbe?
function ChasePlan.InDebrisZone(side, lateral, width)
    local half = width / 2
    if side == 0 then
        return math.abs(lateral) <= width * 0.22
    elseif side < 0 then
        return lateral <= -half + width * 0.55
    end
    return lateral >= half - width * 0.55
end

-- Dónde conviene pararse para esquivar (lateral de 0 = centro).
function ChasePlan.SafeLateral(side, width)
    if side == 0 then
        return width * 0.34
    end
    return -side * width * 0.34
end

return ChasePlan
