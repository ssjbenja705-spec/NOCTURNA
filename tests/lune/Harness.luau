--!nocheck
-- Mínimo marco de pruebas para Lune.
local Harness = {}

local results = {}
local current = nil

-- Mensajes cortos: sin la ruta local ni tramos repetidos del motor simulado.
local function clean(message)
    local text = string.gsub(tostring(message), "[%w_:\\/%-%.]*NOCTURNA[\\/]", "")
    if #text > 900 then
        text = string.sub(text, 1, 900) .. " ..."
    end
    return text
end

function Harness.Suite(name)
    current = name
    print("\n== " .. name)
end

function Harness.Test(name, callback)
    if Harness.Filter and not string.find(name, Harness.Filter, 1, true) then
        return
    end

    local started = os.clock()
    local ok, message = xpcall(callback, function(err)
        return debug.traceback(tostring(err), 2)
    end)
    table.insert(results, {Suite = current, Name = name, Ok = ok, Message = message})
    local elapsed = os.clock() - started
    if ok then
        print(string.format("  OK    %s (%.2fs)", name, elapsed))
    else
        print(string.format("  FALLA %s\n%s", name, clean(message)))
    end
end

function Harness.Equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: se esperaba %s y se obtuvo %s", label or "valor", tostring(expected), tostring(actual)), 2)
    end
end

function Harness.True(value, label)
    if not value then
        error((label or "condición") .. " debía ser verdadera", 2)
    end
end

function Harness.False(value, label)
    if value then
        error((label or "condición") .. " debía ser falsa", 2)
    end
end

function Harness.NoEngineErrors(Engine)
    local failures = Engine.Failures()
    if #failures > 0 then
        error(string.format("%d errores durante la simulación:\n%s", #failures, failures[1]), 2)
    end
end

function Harness.Summary()
    local passed, failed = 0, 0
    for _, result in ipairs(results) do
        if result.Ok then
            passed += 1
        else
            failed += 1
        end
    end

    print(string.format("\nRESULTADO: %d pruebas, %d correctas, %d fallidas", passed + failed, passed, failed))
    return failed
end

return Harness
