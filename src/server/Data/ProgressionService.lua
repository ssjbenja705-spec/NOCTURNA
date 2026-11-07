-- Guardado persistente de cada jugador. Si DataStore no está disponible (por
-- ejemplo en Studio sin API Services) el juego sigue en modo sesión.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local SaveSchema = require(Shared.Logic.SaveSchema)
local Remotes = require(Shared.Modules.RemoteHelper)

local STORE_NAME = "NOCTURNA_PLAYER_DATA_V1"
local AUTOSAVE_INTERVAL = 60
local MAX_ATTEMPTS = 3
local RECOVER_INTERVAL = 30
local RECOVER_ATTEMPTS = 10
local COUNTERS = {"Deaths", "CompletedMatches", "MonsterEncounters", "PlayTime"}

local Progression = {}
local profiles = {}
local sessionStarted = {}
local offline = {}
local saving = {}
local shuttingDown = false
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
        warn("[NOCTURNA] DataStore no disponible:", result)
    end
    return store
end

local function getKey(player)
    return "PLAYER_" .. tostring(player.UserId)
end

local function applyAttributes(player, data)
    player:SetAttribute("NocturnaDataLoaded", true)
    player:SetAttribute("NocturnaCurrentChapter", data.CurrentChapter)
    player:SetAttribute("NocturnaUnlockedChapter", data.UnlockedChapter)
    player:SetAttribute("NocturnaDeaths", data.Deaths)
    player:SetAttribute("NocturnaCompletedMatches", data.CompletedMatches)
    player:SetAttribute("NocturnaMonsterEncounters", data.MonsterEncounters)
    player:SetAttribute("NocturnaSaveOffline", offline[player] == true)
end

-- Datos que el cliente necesita para el diario, el lobby y los ajustes.
function Progression.ClientView(player)
    local data = profiles[player]
    if not data then
        return nil
    end

    return {
        UnlockedChapter = data.UnlockedChapter,
        CurrentChapter = data.CurrentChapter,
        Documents = table.clone(data.Documents),
        Endings = table.clone(data.Endings),
        Deaths = data.Deaths,
        CompletedMatches = data.CompletedMatches,
        MonsterEncounters = data.MonsterEncounters,
        PlayTime = data.PlayTime,
        Settings = table.clone(data.Settings),
        Offline = offline[player] == true,
    }
end

function Progression.Push(player)
    local view = Progression.ClientView(player)
    if view then
        Remotes.FireClient("ProfileUpdate", player, view)
    end
end

-- Si la carga falló, se sigue intentando de fondo. Cuando DataStore vuelve, lo
-- guardado se combina con lo jugado en la sesión y desde ahí se guarda normal.
local function recover(player)
    for _ = 1, RECOVER_ATTEMPTS do
        task.wait(RECOVER_INTERVAL)
        if player.Parent ~= Players or not offline[player] or shuttingDown then
            return
        end

        local dataStore = getStore()
        local success, stored = false, nil
        if dataStore then
            success, stored = pcall(function()
                return dataStore:GetAsync(getKey(player))
            end)
        end

        if success and player.Parent == Players and offline[player] and profiles[player] then
            local session = profiles[player]
            local base = SaveSchema.Normalize(stored)
            local recovered = SaveSchema.Merge(session, base)
            -- Lo de la sesión empezó en cero: se suma a lo guardado.
            for _, key in ipairs(COUNTERS) do
                recovered[key] = base[key] + session[key]
            end

            profiles[player] = recovered
            offline[player] = false
            applyAttributes(player, recovered)
            Progression.Push(player)
            print("[NOCTURNA] Datos de " .. player.Name .. " recuperados.")
            return
        end
    end

    if player.Parent == Players and offline[player] then
        warn("[NOCTURNA] El progreso de " .. player.Name .. " no se guardará en esta sesión.")
    end
end

function Progression.Load(player)
    local dataStore = getStore()
    local success, result = false, nil

    if dataStore then
        for attempt = 1, MAX_ATTEMPTS do
            success, result = pcall(function()
                return dataStore:GetAsync(getKey(player))
            end)
            -- Studio sin API Services falla siempre: no tiene sentido hacer esperar.
            if success or RunService:IsStudio() then
                break
            end
            warn("[NOCTURNA] Error cargando datos. Intento:", attempt, result)
            if attempt < MAX_ATTEMPTS then
                task.wait(attempt * 2)
            end
        end
    end

    if player.Parent ~= Players then
        return false
    end

    -- Sin carga válida se juega en modo sesión y nunca se escribe sobre lo guardado.
    offline[player] = not success
    profiles[player] = SaveSchema.Normalize(success and result or nil)
    sessionStarted[player] = os.time()
    applyAttributes(player, profiles[player])
    Progression.Push(player)

    if offline[player] and dataStore and not RunService:IsStudio() then
        task.spawn(recover, player)
    end
    return true
end

function Progression.Get(player)
    local data = profiles[player]
    if not data then
        return nil
    end
    return SaveSchema.Normalize(data)
end

function Progression.SetCurrentChapter(player, chapter)
    local data = profiles[player]
    if not data or type(chapter) ~= "number" or chapter % 1 ~= 0 then
        return false
    end
    if chapter < 1 or chapter > data.UnlockedChapter then
        return false
    end

    data.CurrentChapter = chapter
    player:SetAttribute("NocturnaCurrentChapter", chapter)
    return true
end

function Progression.UnlockChapter(player, chapter)
    local data = profiles[player]
    if not data or type(chapter) ~= "number" or chapter % 1 ~= 0 then
        return false
    end
    if chapter < 1 or chapter > SaveSchema.ChapterCount then
        return false
    end

    data.UnlockedChapter = math.max(data.UnlockedChapter, chapter)
    player:SetAttribute("NocturnaUnlockedChapter", data.UnlockedChapter)
    Progression.Push(player)
    return true
end

function Progression.AddDocument(player, documentId)
    local data = profiles[player]
    if not data or type(documentId) ~= "string" then
        return false
    end
    if #documentId == 0 or #documentId > 80 or data.Documents[documentId] then
        return false
    end

    data.Documents[documentId] = true
    Progression.Push(player)
    return true
end

function Progression.HasDocument(player, documentId)
    local data = profiles[player]
    return data ~= nil and data.Documents[documentId] == true
end

function Progression.CountDocuments(player)
    local data = profiles[player]
    return data and SaveSchema.CountSet(data.Documents) or 0
end

function Progression.AddEnding(player, endingId)
    local data = profiles[player]
    if not data or type(endingId) ~= "string" then
        return false
    end
    data.Endings[endingId] = true
    Progression.Push(player)
    return true
end

local function increment(player, field, attribute)
    local data = profiles[player]
    if not data then
        return false
    end
    data[field] += 1
    player:SetAttribute(attribute, data[field])
    return true
end

function Progression.RecordDeath(player)
    return increment(player, "Deaths", "NocturnaDeaths")
end

function Progression.RecordMatchCompleted(player)
    return increment(player, "CompletedMatches", "NocturnaCompletedMatches")
end

function Progression.RecordMonsterEncounter(player)
    return increment(player, "MonsterEncounters", "NocturnaMonsterEncounters")
end

function Progression.GetSettings(player)
    local data = profiles[player]
    return data and data.Settings or SaveSchema.NormalizeSettings(nil)
end

function Progression.SetSettings(player, settings)
    local data = profiles[player]
    if not data then
        return false
    end
    data.Settings = SaveSchema.NormalizeSettings(settings)
    return true
end

local function saveNow(player)
    local data = profiles[player]
    if not data then
        return false
    end

    if offline[player] then
        return false
    end

    local dataStore = getStore()
    if not dataStore then
        return false
    end

    local now = os.time()
    data.PlayTime += math.max(0, now - (sessionStarted[player] or now))
    data.LastPlayed = now
    sessionStarted[player] = now

    local snapshot = SaveSchema.Normalize(data)
    local success, err = false, nil

    for attempt = 1, MAX_ATTEMPTS do
        success, err = pcall(function()
            dataStore:UpdateAsync(getKey(player), function(stored)
                return SaveSchema.Merge(stored, snapshot)
            end)
        end)

        if success then
            return true
        end

        warn("[NOCTURNA] Error guardando datos. Intento:", attempt, err)
        if attempt < MAX_ATTEMPTS then
            task.wait(attempt * 2)
        end
    end

    warn("[NOCTURNA] No se pudieron guardar los datos de", player.Name)
    return false
end

-- Los guardados de un mismo jugador van de a uno (al salir y al cerrar el
-- servidor pueden pedirse a la vez) y un error nunca corta a quien espera.
function Progression.Save(player)
    while saving[player] do
        task.wait(0.1)
    end

    saving[player] = true
    local success, result = pcall(saveNow, player)
    saving[player] = nil

    if not success then
        warn("[NOCTURNA] Error inesperado guardando a", player.Name, result)
        return false
    end
    return result
end

function Progression.Remove(player)
    profiles[player] = nil
    sessionStarted[player] = nil
    offline[player] = nil
end

function Progression.Start()
    Remotes.OnServer("SettingsUpdate", 1, function(player, settings)
        if type(settings) == "table" then
            Progression.SetSettings(player, settings)
        end
    end)

    Players.PlayerAdded:Connect(Progression.Load)
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(Progression.Load, player)
    end

    Players.PlayerRemoving:Connect(function(player)
        Progression.Save(player)
        Progression.Remove(player)
    end)

    task.spawn(function()
        while not shuttingDown do
            task.wait(AUTOSAVE_INTERVAL)
            for _, player in ipairs(Players:GetPlayers()) do
                task.spawn(Progression.Save, player)
            end
        end
    end)

    game:BindToClose(function()
        shuttingDown = true

        local pending = 0
        for _, player in ipairs(Players:GetPlayers()) do
            pending += 1
            task.spawn(function()
                pcall(Progression.Save, player)
                pending -= 1
            end)
        end

        local deadline = os.clock() + 25
        while pending > 0 and os.clock() < deadline do
            task.wait(0.1)
        end
    end)
end

return Progression
