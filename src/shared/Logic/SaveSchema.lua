-- Esquema de guardado. Normaliza datos viejos o dañados y combina sesiones sin
-- perder progreso, aunque el mismo jugador haya guardado desde otro servidor.
local SaveSchema = {}

SaveSchema.Version = 2
SaveSchema.ChapterCount = 5

SaveSchema.DefaultSettings = {
    MusicVolume = 0.7,
    EffectsVolume = 0.9,
    Brightness = 0.5,
    Subtitles = true,
    LowQuality = false,
}

local VALID_ENDINGS = {Release = true, Rescue = true, Remember = true}

local function wholeNumber(value, minimum, maximum, fallback)
    local number = tonumber(value)
    if not number or number ~= number then
        return fallback
    end
    return math.clamp(math.floor(number), minimum, maximum)
end

function SaveSchema.Default()
    return {
        Version = SaveSchema.Version,
        CurrentChapter = 1,
        UnlockedChapter = 1,
        Documents = {},
        Endings = {},
        Deaths = 0,
        CompletedMatches = 0,
        MonsterEncounters = 0,
        PlayTime = 0,
        LastPlayed = 0,
        Settings = table.clone(SaveSchema.DefaultSettings),
    }
end

function SaveSchema.NormalizeSettings(raw)
    local result = table.clone(SaveSchema.DefaultSettings)
    if type(raw) ~= "table" then
        return result
    end

    for _, key in ipairs({"MusicVolume", "EffectsVolume", "Brightness"}) do
        local value = raw[key]
        if type(value) == "number" and value == value then
            result[key] = math.clamp(value, 0, 1)
        end
    end

    if type(raw.Subtitles) == "boolean" then
        result.Subtitles = raw.Subtitles
    end
    if type(raw.LowQuality) == "boolean" then
        result.LowQuality = raw.LowQuality
    end

    return result
end

local function normalizeSet(raw, isValid)
    local result = {}
    if type(raw) ~= "table" then
        return result
    end
    for key, value in pairs(raw) do
        if value == true and type(key) == "string" and isValid(key) then
            result[key] = true
        end
    end
    return result
end

local function validDocumentId(id)
    return #id > 0 and #id <= 80
end

function SaveSchema.Normalize(raw)
    local data = SaveSchema.Default()
    if type(raw) ~= "table" then
        return data
    end

    local chapters = SaveSchema.ChapterCount
    data.UnlockedChapter = wholeNumber(raw.UnlockedChapter, 1, chapters, 1)
    data.CurrentChapter = math.min(wholeNumber(raw.CurrentChapter, 1, chapters, 1), data.UnlockedChapter)
    data.Documents = normalizeSet(raw.Documents, validDocumentId)
    data.Endings = normalizeSet(raw.Endings, function(id)
        return VALID_ENDINGS[id] == true
    end)
    data.Deaths = wholeNumber(raw.Deaths, 0, 2 ^ 31, 0)
    data.CompletedMatches = wholeNumber(raw.CompletedMatches, 0, 2 ^ 31, 0)
    data.MonsterEncounters = wholeNumber(raw.MonsterEncounters, 0, 2 ^ 31, 0)
    data.PlayTime = wholeNumber(raw.PlayTime, 0, 2 ^ 31, 0)
    data.LastPlayed = wholeNumber(raw.LastPlayed, 0, 2 ^ 40, 0)
    data.Settings = SaveSchema.NormalizeSettings(raw.Settings)

    return data
end

-- Fusión monótona para UpdateAsync: nunca retrocede capítulos ni borra colecciones.
function SaveSchema.Merge(stored, session)
    local old = SaveSchema.Normalize(stored)
    local new = SaveSchema.Normalize(session)
    local merged = table.clone(new)

    merged.UnlockedChapter = math.max(old.UnlockedChapter, new.UnlockedChapter)
    merged.CurrentChapter = math.min(new.CurrentChapter, merged.UnlockedChapter)
    merged.Documents = table.clone(old.Documents)
    for id in pairs(new.Documents) do
        merged.Documents[id] = true
    end
    merged.Endings = table.clone(old.Endings)
    for id in pairs(new.Endings) do
        merged.Endings[id] = true
    end

    for _, key in ipairs({"Deaths", "CompletedMatches", "MonsterEncounters", "PlayTime"}) do
        merged[key] = math.max(old[key], new[key])
    end

    return merged
end

function SaveSchema.CountSet(set)
    local count = 0
    for _ in pairs(set) do
        count += 1
    end
    return count
end

return SaveSchema
