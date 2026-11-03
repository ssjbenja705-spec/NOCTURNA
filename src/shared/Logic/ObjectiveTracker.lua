-- Progreso secuencial de objetivos. Recuerda las señales recibidas fuera de orden,
-- de modo que juntar un fusible antes de tiempo también cuenta después.
local ObjectiveTracker = {}
ObjectiveTracker.__index = ObjectiveTracker

function ObjectiveTracker.new(objectives)
    return setmetatable({
        Objectives = objectives,
        Index = 1,
        Counts = {},
        Seen = {},
        Done = {},
    }, ObjectiveTracker)
end

local function countKey(kind, target)
    return kind .. ":" .. target
end

function ObjectiveTracker:Count(kind, target)
    return self.Counts[countKey(kind, target)] or 0
end

function ObjectiveTracker:Current()
    return self.Objectives[self.Index]
end

function ObjectiveTracker:IsFinished()
    return self.Index > #self.Objectives
end

function ObjectiveTracker:IsDone(objectiveId)
    return self.Done[objectiveId] == true
end

function ObjectiveTracker:Progress()
    local objective = self:Current()
    if not objective then
        return 0, 0
    end
    local needed = objective.Count or 1
    return math.min(self:Count(objective.Type, objective.Target), needed), needed
end

-- Avanza mientras el objetivo actual ya esté cumplido. Devuelve los completados.
function ObjectiveTracker:Advance()
    local completed = {}

    while true do
        local objective = self:Current()
        if not objective then
            break
        end
        if self:Count(objective.Type, objective.Target) < (objective.Count or 1) then
            break
        end
        self.Done[objective.Id] = true
        table.insert(completed, objective)
        self.Index += 1
    end

    return completed
end

-- unique evita contar dos veces el mismo objeto físico (por ejemplo, si se suelta).
function ObjectiveTracker:Signal(kind, target, unique)
    if type(kind) ~= "string" or type(target) ~= "string" then
        return {}
    end

    if unique ~= nil then
        local seenKey = countKey(kind, target) .. "|" .. tostring(unique)
        if self.Seen[seenKey] then
            return {}
        end
        self.Seen[seenKey] = true
    end

    local key = countKey(kind, target)
    self.Counts[key] = (self.Counts[key] or 0) + 1
    return self:Advance()
end

-- Uso administrativo: fuerza el objetivo actual sin importar su progreso.
function ObjectiveTracker:Skip()
    local objective = self:Current()
    if not objective then
        return nil
    end
    self.Done[objective.Id] = true
    self.Index += 1
    return objective
end

return ObjectiveTracker
