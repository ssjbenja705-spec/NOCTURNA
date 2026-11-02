local DataStoreService = game:GetService("DataStoreService")

local Store = DataStoreService:GetDataStore("NOCTURNA_PLAYER_DATA_V1")

local Progression = {}
local profiles = {}

local DEFAULT_DATA = {
    Version = 1,
    CurrentChapter = 1,
    UnlockedChapter = 1,
    Documents = {},
    Deaths = 0,
    CompletedMatches = 0,
    MonsterEncounters = 0,
    LastPlayed = 0,
}

local function copyTable(original)
    local result = {}

    for key, value in pairs(original) do
        if type(value) == "table" then
            result[key] = copyTable(value)
        else
            result[key] = value
        end
    end

    return result
end

local function getKey(player)
    return "PLAYER_" .. tostring(player.UserId)
end

local function normalize(data)
    if type(data) ~= "table" then
        data = copyTable(DEFAULT_DATA)
    end

    for key, value in pairs(DEFAULT_DATA) do
        if data[key] == nil then
            data[key] = copyTable(value)
        end
    end

    data.CurrentChapter = math.clamp(tonumber(data.CurrentChapter) or 1, 1, 5)
    data.UnlockedChapter = math.clamp(tonumber(data.UnlockedChapter) or 1, 1, 5)
    data.Documents = type(data.Documents) == "table" and data.Documents or {}
    data.Deaths = math.max(0, tonumber(data.Deaths) or 0)
    data.CompletedMatches = math.max(0, tonumber(data.CompletedMatches) or 0)
    data.MonsterEncounters = math.max(0, tonumber(data.MonsterEncounters) or 0)

    return data
end

local function applyAttributes(player, data)
    player:SetAttribute("NocturnaDataLoaded", true)
    player:SetAttribute("NocturnaCurrentChapter", data.CurrentChapter)
    player:SetAttribute("NocturnaUnlockedChapter", data.UnlockedChapter)
    player:SetAttribute("NocturnaDeaths", data.Deaths)
    player:SetAttribute("NocturnaCompletedMatches", data.CompletedMatches)
    player:SetAttribute("NocturnaMonsterEncounters", data.MonsterEncounters)
end

function Progression.Load(player)
    local success, result

    for attempt = 1, 3 do
        success, result = pcall(function()
            return Store:GetAsync(getKey(player))
        end)

        if success then
            break
        end

        warn("[NOCTURNA] Error cargando datos. Intento:", attempt)
        task.wait(attempt * 2)
    end

    if not success then
        warn("[NOCTURNA] No se pudieron cargar los datos de", player.Name)
        return false
    end

    local data = normalize(result)
    profiles[player] = data
    applyAttributes(player, data)

    print("[NOCTURNA] Datos cargados:", player.Name)
    return true
end

function Progression.Get(player)
    local data = profiles[player]
    if not data then return nil end
    return copyTable(data)
end

function Progression.SetCurrentChapter(player, chapter)
    local data = profiles[player]
    chapter = tonumber(chapter)
    if not data or not chapter or chapter < 1 or chapter > 5 then
        return false
    end

    chapter = math.floor(chapter)
    if chapter > data.UnlockedChapter then return false end

    data.CurrentChapter = chapter
    player:SetAttribute("NocturnaCurrentChapter", chapter)
    return true
end

function Progression.UnlockChapter(player, chapter)
    local data = profiles[player]
    chapter = tonumber(chapter)
    if not data or not chapter or chapter < 1 or chapter > 5 then
        return false
    end

    chapter = math.floor(chapter)
    if chapter > data.UnlockedChapter + 1 then return false end

    data.UnlockedChapter = math.max(data.UnlockedChapter, chapter)
    player:SetAttribute("NocturnaUnlockedChapter", data.UnlockedChapter)
    return true
end

function Progression.AddDocument(player, documentId)
    local data = profiles[player]
    if not data or type(documentId) ~= "string" then return false end
    if #documentId == 0 or #documentId > 80 then return false end
    if data.Documents[documentId] then return false end

    data.Documents[documentId] = true
    return true
end

function Progression.RecordDeath(player)
    local data = profiles[player]
    if not data then return false end

    data.Deaths += 1
    player:SetAttribute("NocturnaDeaths", data.Deaths)
    return true
end

function Progression.RecordMatchCompleted(player)
    local data = profiles[player]
    if not data then return false end

    data.CompletedMatches += 1
    player:SetAttribute("NocturnaCompletedMatches", data.CompletedMatches)
    return true
end

function Progression.RecordMonsterEncounter(player)
    local data = profiles[player]
    if not data then return false end

    data.MonsterEncounters += 1
    player:SetAttribute("NocturnaMonsterEncounters", data.MonsterEncounters)
    return true
end

function Progression.Save(player)
    local data = profiles[player]
    if not data then return false end

    local snapshot = copyTable(data)
    snapshot.LastPlayed = os.time()
    local success = false

    for attempt = 1, 3 do
        success = pcall(function()
            Store:UpdateAsync(getKey(player), function()
                return snapshot
            end)
        end)

        if success then
            data.LastPlayed = snapshot.LastPlayed
            print("[NOCTURNA] Datos guardados:", player.Name)
            return true
        end

        warn("[NOCTURNA] Error guardando datos. Intento:", attempt)
        task.wait(attempt * 2)
    end

    warn("[NOCTURNA] No se pudieron guardar los datos de", player.Name)
    return false
end

function Progression.Remove(player)
    profiles[player] = nil
end

return Progression
