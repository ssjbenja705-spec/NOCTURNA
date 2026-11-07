-- Sanciones persistentes. Si DataStore falla, la sanción sigue vigente en este
-- servidor y quien la puso recibe el aviso de que no quedó guardada.
local DataStoreService = game:GetService("DataStoreService")

local STORE_NAME = "NOCTURNA_MODERATION_V1"
local MAX_ATTEMPTS = 3

local ModerationStore = {}
local cache = {}
local store = nil

local function getStore()
    if store then
        return store
    end
    local success, result = pcall(function()
        return DataStoreService:GetDataStore(STORE_NAME)
    end)
    if success then
        store = result
    else
        warn("[NOCTURNA] Sanciones sin DataStore:", result)
    end
    return store
end

local function key(userId)
    return "BAN_" .. tostring(userId)
end

-- Reintenta una operación de DataStore. Devuelve si salió bien y su resultado.
local function withRetry(label, operation)
    local dataStore = getStore()
    if not dataStore then
        return false, nil
    end

    local success, result = false, nil
    for attempt = 1, MAX_ATTEMPTS do
        success, result = pcall(operation, dataStore)
        if success then
            return true, result
        end
        if attempt < MAX_ATTEMPTS then
            task.wait(attempt)
        end
    end
    warn("[NOCTURNA] Sanciones: falló " .. label .. ":", result)
    return false, nil
end

-- Devuelve la sanción y si quedó guardada para todos los servidores.
function ModerationStore.Ban(userId, days, reason, moderatorId)
    local record = {
        Until = days and os.time() + math.floor(days * 86400) or 0,
        Reason = reason,
        By = moderatorId,
        At = os.time(),
    }
    cache[userId] = record

    local saved = withRetry("guardar la sanción de " .. tostring(userId), function(dataStore)
        dataStore:SetAsync(key(userId), record, {userId})
    end)
    return record, saved
end

-- Devuelve si se borró también de lo guardado.
function ModerationStore.Unban(userId)
    cache[userId] = false

    return (withRetry("levantar la sanción de " .. tostring(userId), function(dataStore)
        dataStore:RemoveAsync(key(userId))
    end))
end

-- Devuelve la sanción vigente, o nil si no hay ninguna. Si DataStore no
-- responde se deja entrar (y se avisa) para no bloquear a todos por una caída.
function ModerationStore.GetActiveBan(userId)
    local record = cache[userId]

    if record == nil then
        local success, result = withRetry("leer la sanción de " .. tostring(userId), function(dataStore)
            return dataStore:GetAsync(key(userId))
        end)
        if success then
            record = result
        end
    end

    if type(record) ~= "table" then
        return nil
    end
    if record.Until ~= 0 and record.Until <= os.time() then
        return nil
    end
    return record
end

return ModerationStore
