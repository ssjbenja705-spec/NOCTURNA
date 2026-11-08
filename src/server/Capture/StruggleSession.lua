-- Reglas puras del forcejeo (sin instancias): el servidor arma la secuencia, fija
-- el plazo y es el único que cuenta el progreso. El cliente sólo dice "apreté
-- esta tecla para este paso"; acá se decide si vale.
--
-- Resultados de Press:
--   Correct / Escaped  tecla correcta en orden (Escaped: completó la secuencia).
--   Wrong              tecla equivocada: retrocede un paso y descuenta tiempo.
--   Late               llegó después del plazo: el forcejeo se pierde.
--   Stale              un paso ya contado (repetido o atrasado): se ignora.
--   Invalid            paso salteado o datos mal formados: se ignora y se anota.
--   Spam               demasiado pegada a la anterior: se ignora.
--   Closed             el forcejeo ya terminó.
local StruggleSession = {}
StruggleSession.__index = StruggleSession

-- Secuencia al azar sin tres teclas iguales seguidas (se lee mejor y no hay
-- tramos que se resuelvan machacando una sola tecla).
function StruggleSession.Generate(keys, length, random)
    local sequence = {}
    for index = 1, length do
        local key
        repeat
            key = keys[random:NextInteger(1, #keys)]
        until index < 3 or not (sequence[index - 1] == key and sequence[index - 2] == key)
        sequence[index] = key
    end
    return sequence
end

function StruggleSession.new(options)
    assert(type(options.Sequence) == "table" and #options.Sequence > 0, "secuencia vacía")
    return setmetatable({
        Sequence = table.clone(options.Sequence),
        Index = 0,
        Started = options.Now,
        Deadline = options.Now + options.TimeLimit,
        MistakeTime = options.MistakeTime or 0.5,
        MinInterval = options.MinInterval or 0.06,
        LastPress = -math.huge,
        State = "Active",
        Accepted = 0,
        Mistakes = 0,
        Rejected = 0,
    }, StruggleSession)
end

function StruggleSession:Check(now)
    if self.State == "Active" and now > self.Deadline then
        self.State = "Failed"
    end
    return self.State
end

function StruggleSession:Press(step, key, now)
    if self:Check(now) ~= "Active" then
        return self.State == "Failed" and "Late" or "Closed"
    end
    if type(step) ~= "number" or step ~= step or step % 1 ~= 0 or type(key) ~= "string" then
        self.Rejected += 1
        return "Invalid"
    end
    if step <= self.Index then
        return "Stale"
    end
    if step > self.Index + 1 then
        self.Rejected += 1
        return "Invalid"
    end
    if now - self.LastPress < self.MinInterval then
        self.Rejected += 1
        return "Spam"
    end

    self.LastPress = now
    self.Accepted += 1
    if key ~= self.Sequence[step] then
        self.Mistakes += 1
        self.Index = math.max(0, self.Index - 1)
        self.Deadline -= self.MistakeTime
        if now > self.Deadline then
            self.State = "Failed"
        end
        return "Wrong"
    end

    self.Index += 1
    if self.Index >= #self.Sequence then
        self.State = "Escaped"
        return "Escaped"
    end
    return "Correct"
end

function StruggleSession:Progress()
    return self.Index / #self.Sequence
end

function StruggleSession:TimeLeft(now)
    return math.max(0, self.Deadline - now)
end

return StruggleSession
