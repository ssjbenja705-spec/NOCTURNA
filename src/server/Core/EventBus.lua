-- Eventos internos del servidor. Reemplaza a _G y a los BindableEvent sueltos.
local EventBus = {}
local handlers = {}

function EventBus.On(name, handler)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], handler)

    return function()
        local list = handlers[name]
        local index = list and table.find(list, handler)
        if index then
            table.remove(list, index)
        end
    end
end

function EventBus.Emit(name, ...)
    local list = handlers[name]
    if not list then
        return
    end
    for _, handler in ipairs(table.clone(list)) do
        task.spawn(handler, ...)
    end
end

return EventBus
