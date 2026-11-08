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

local function pickKinds(rng, count, config, avoid)
    local kinds = table.clone(config.Order)
    for _ = 1, 40 do
        rng:Shuffle(kinds)
        local chosen = {}
        for index = 1, count do
            chosen[index] = kinds[index]
        end
        local shared, personal = false, false
        for _, kind in ipairs(chosen) do
            if config.Kinds[kind].Shared then
                shared = true
            else
                personal = true
            end
        end
        if shared and personal and chosen[1] ~= avoid then
            return chosen
        end
    end
    -- Respaldo determinista: uno compartido y uno personal siempre están.
    local fallback = {"SHADOW_CROSS", "FOOTSTEPS_BEHIND", "DOOR_SLAM", "FIGURE_BEHIND"}
    if avoid == fallback[1] then
        fallback[1], fallback[3] = fallback[3], fallback[1]
    end
    return table.move(fallback, 1, count, 1, {})
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
