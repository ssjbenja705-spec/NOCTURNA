-- Sanciones persistentes. Si DataStore falla, la sanción sigue vigente en este servidor.
local DataStoreService = game:GetService("DataStoreService")

local STORE_NAME = "NOCTURNA_MODERATION_V1"

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
    end
    return store
end

local function key(userId)
    return "BAN_" .. tostring(userId)
end

function ModerationStore.Ban(userId, days, reason, moderatorId)
    local record = {
        Until = days and os.time() + math.floor(days * 86400) or 0,
        Reason = reason,
        By = moderatorId,
        At = os.time(),
    }
    cache[userId] = record

    local dataStore = getStore()
    if dataStore then
        pcall(function()
            dataStore:SetAsync(key(userId), record, {userId})
        end)
    end
    return record
end

function ModerationStore.Unban(userId)
    cache[userId] = false

    local dataStore = getStore()
    if dataStore then
        pcall(function()
            dataStore:RemoveAsync(key(userId))
        end)
    end
end

-- Devuelve la sanción vigente, o nil si no hay ninguna.
function ModerationStore.GetActiveBan(userId)
    local record = cache[userId]

    if record == nil then
        local dataStore = getStore()
        if dataStore then
            local success, result = pcall(function()
                return dataStore:GetAsync(key(userId))
            end)
            if success then
                record = result
            end
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
