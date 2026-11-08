-- Plan de sustos de un mapa: cuáles, dónde y en qué orden se prefieren. Lógica
-- pura (sin instancias) para el servidor y las pruebas.
local ScarePlan = {}

local function manhattan(a, b)
    return math.abs(a.X - b.X) + math.abs(a.Z - b.Z)
end

ScarePlan.Manhattan = manhattan

-- Celdas donde puede ir un susto: ni la entrada ni sus vecinas (recién se llega),
-- ni la salida (ahí pasan las escenas importantes, como el cuarto de Alma).
function ScarePlan.Candidates(layout)
    local start = layout.Cells[layout.Start]
    local result = {}
    for _, cell in ipairs(layout.Cells) do
        if cell.Index ~= layout.Exit and manhattan(cell, start) >= 2 then
            table.insert(result, cell.Index)
        end
    end
    return result
end

local function isJumpscare(config, kind)
    local info = config.Kinds[kind]
    return info ~= nil and info.Jumpscare == true
end

ScarePlan.IsJumpscare = isJumpscare

-- Cuántos sustos de golpe lleva un mapa de `count` sustos (nunca todos).
function ScarePlan.JumpscareCount(config, count)
    local available = 0
    for _, kind in ipairs(config.Order) do
        if isJumpscare(config, kind) then
            available += 1
        end
    end
    local wanted = config.Jumpscares and config.Jumpscares[count] or 0
    return math.max(0, math.min(wanted, available, count - 1))
end

-- Lugar de cada susto de golpe en el orden del mapa: el último y, si hay dos, el
-- segundo (así se alternan con los otros y nunca abren el mapa).
local function jumpscareSlots(count, jumps)
    local slots = {}
    for index = 1, jumps do
        slots[count - (index - 1) * 2] = true
    end
    return slots
end

local function pickKinds(rng, count, config, avoid)
    local jumps = ScarePlan.JumpscareCount(config, count)
    local regular, scary = {}, {}
    for _, kind in ipairs(config.Order) do
        table.insert(isJumpscare(config, kind) and scary or regular, kind)
    end
    local need = count - jumps

    local chosen = nil
    for _ = 1, 40 do
        rng:Shuffle(regular)
        local pick = table.move(regular, 1, need, 1, {})
        local shared, personal = false, jumps > 0
        for _, kind in ipairs(pick) do
            if config.Kinds[kind].Shared then
                shared = true
            else
                personal = true
            end
        end
        if shared and personal and pick[1] ~= avoid then
            chosen = pick
            break
        end
    end
    if not chosen then
        -- Respaldo determinista: uno compartido y uno personal siempre están.
        local fallback = {"SHADOW_CROSS", "FOOTSTEPS_BEHIND", "DOOR_SLAM", "FIGURE_BEHIND"}
        if avoid == fallback[1] then
            fallback[1], fallback[3] = fallback[3], fallback[1]
        end
        chosen = table.move(fallback, 1, need, 1, {})
    end

    rng:Shuffle(scary)
    local slots = jumpscareSlots(count, jumps)
    local result = {}
    local nextRegular, nextJump = 1, 1
    for position = 1, count do
        if slots[position] then
            result[position] = scary[nextJump]
            nextJump += 1
        else
            result[position] = chosen[nextRegular]
            nextRegular += 1
        end
    end
    return result
end

local function pickCells(layout, rng, count, spacing)
    local candidates = rng:Shuffle(ScarePlan.Candidates(layout))
    for minimum = spacing, 1, -1 do
        local chosen = {}
        for _, index in ipairs(candidates) do
            local cell = layout.Cells[index]
            local fits = true
            for _, other in ipairs(chosen) do
                if manhattan(cell, layout.Cells[other]) < minimum then
                    fits = false
                    break
                end
            end
            if fits then
                table.insert(chosen, index)
                if #chosen == count then
                    return chosen
                end
            end
        end
    end
    return {}
end

-- Devuelve {Id, Kind, Cell, Shared} para 3 o 4 sustos. avoid: el último tipo que
-- sonó en el mapa anterior, para no abrir con el mismo.
function ScarePlan.Generate(layout, rng, config, avoid)
    local count = rng:Int(config.MinCount, config.MaxCount)
    local cells = pickCells(layout, rng, count, config.MinCellSpacing)
    count = math.min(count, #cells)
    local kinds = pickKinds(rng, count, config, avoid)

    local plan = {}
    for index = 1, count do
        table.insert(plan, {
            Id = index,
            Kind = kinds[index],
            Cell = cells[index],
            Shared = config.Kinds[kinds[index]].Shared,
        })
    end
    return plan
end

function ScarePlan.Validate(plan, layout, config)
    if #plan < config.MinCount or #plan > config.MaxCount then
        return false, "cantidad " .. #plan
    end
    local kinds = {}
    local candidates = {}
    for _, index in ipairs(ScarePlan.Candidates(layout)) do
        candidates[index] = true
    end
    if isJumpscare(config, plan[1].Kind) then
        return false, "abre con un susto de golpe"
    end
    local jumps = 0
    for _, entry in ipairs(plan) do
        if isJumpscare(config, entry.Kind) then
            jumps += 1
        end
    end
    if jumps ~= ScarePlan.JumpscareCount(config, #plan) then
        return false, "sustos de golpe " .. jumps
    end
    for position, entry in ipairs(plan) do
        if config.Kinds[entry.Kind] == nil then
            return false, "tipo desconocido " .. tostring(entry.Kind)
        end
        if kinds[entry.Kind] then
            return false, "tipo repetido " .. entry.Kind
        end
        kinds[entry.Kind] = true
        if not candidates[entry.Cell] then
            return false, "celda no válida " .. tostring(entry.Cell)
        end
        for other = position + 1, #plan do
            if manhattan(layout.Cells[entry.Cell], layout.Cells[plan[other].Cell]) < config.MinCellSpacing then
                return false, "sustos amontonados"
            end
        end
    end
    return true
end

-- Próxima espera entre sustos (random: un Random de Roblox o un Rng propio).
function ScarePlan.NextInterval(random, config)
    local timing = config.Timing
    if random.NextNumber then
        return random:NextNumber(timing.MinInterval, timing.MaxInterval)
    end
    return timing.MinInterval + random:Float() * (timing.MaxInterval - timing.MinInterval)
end

return ScarePlan
