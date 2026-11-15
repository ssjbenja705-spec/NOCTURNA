-- Victorias y récords. Todo lo decide el servidor:
--   * Victoria: cada jugador que está en la partida cuando el grupo termina un
--     capítulo suma una (una sola vez por capítulo jugado: Token).
--   * Tiempo: lo mide el servidor desde que empezó el capítulo hasta que se
--     completó (el cliente nunca manda tiempos).
--   * Récord personal: el perfil (ProgressionService) y se guarda enseguida.
--   * Récords del servidor: en memoria, los mejores de quienes jugaron acá.
--   * Récords globales: un OrderedDataStore por capítulo (centésimas de segundo,
--     de menor a mayor), con reintentos; la lista se guarda un rato en caché.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local ProgressionService = require(script.Parent.ProgressionService)

local RecordsService = {}

local STORE_PREFIX = "NOCTURNA_BEST_TIME_C"
local TOP = 10
local MAX_ATTEMPTS = 3
local CACHE_TIME = 60
-- Menos que esto no es un capítulo de verdad (protege el ranking).
local MIN_TIME = 20

local serverBest = {} -- [capítulo] = {{UserId, Name, Time}} ordenada
local globalCache = {} -- [capítulo] = {List = {...}, Fetched = os.clock()}
local names = {} -- [UserId] = nombre (no se le pregunta a Roblox cada vez)
-- Si el ranking falla, no se reintenta enseguida: protege el cupo de DataStore.
local FAIL_CACHE_TIME = 30
local recorded = {} -- [token .. ":" .. userId] = true
local storeCache = {}
local storesOff = false

local function chapterCount()
    return #GameConfig.Chapters
end

local function orderedStore(chapter)
    if storesOff then
        return nil
    end
    if storeCache[chapter] then
        return storeCache[chapter]
    end
    local ok, store = pcall(function()
        return DataStoreService:GetOrderedDataStore(STORE_PREFIX .. chapter)
    end)
    if not ok then
        storesOff = true
        return nil
    end
    storeCache[chapter] = store
    return store
end

local function withRetries(callback)
    local lastError = nil
    for attempt = 1, MAX_ATTEMPTS do
        local ok, result = pcall(callback)
        if ok then
            return true, result
        end
        lastError = result
        if attempt < MAX_ATTEMPTS then
            task.wait(attempt)
        end
    end
    return false, lastError
end

local function insertServer(chapter, entry)
    local list = serverBest[chapter] or {}
    serverBest[chapter] = list
    for index, existing in ipairs(list) do
        if existing.UserId == entry.UserId then
            if existing.Time <= entry.Time then
                return
            end
            table.remove(list, index)
            break
        end
    end
    table.insert(list, entry)
    table.sort(list, function(a, b)
        return a.Time < b.Time
    end)
    while #list > TOP do
        table.remove(list)
    end
end

local function rankIn(list, userId)
    for index, entry in ipairs(list or {}) do
        if entry.UserId == userId then
            return index
        end
    end
    return nil
end

-- Lista global de un capítulo (de la caché si es reciente).
function RecordsService.Global(chapter, fresh)
    local cached = globalCache[chapter]
    if cached and not fresh and os.clock() - cached.Fetched < CACHE_TIME then
        return cached.List
    end
    local store = orderedStore(chapter)
    if not store then
        return cached and cached.List or {}
    end
    local ok, page = withRetries(function()
        return store:GetSortedAsync(true, TOP):GetCurrentPage()
    end)
    if not ok then
        warn("[NOCTURNA] No se pudo leer el ranking del capítulo " .. chapter .. ": " .. tostring(page))
        local list = cached and cached.List or {}
        globalCache[chapter] = {List = list, Fetched = os.clock() - CACHE_TIME + FAIL_CACHE_TIME}
        return list
    end
    local list = {}
    for _, item in ipairs(page) do
        local userId = tonumber(item.key)
        local name = userId and names[userId] or "Jugador"
        local player = userId and Players:GetPlayerByUserId(userId)
        if player then
            name = player.DisplayName
            names[userId] = name
        elseif userId and not names[userId] then
            local found, result = pcall(function()
                return Players:GetNameFromUserIdAsync(userId)
            end)
            name = found and result or name
            names[userId] = name
        end
        table.insert(list, {UserId = userId, Name = name, Time = item.value / 100})
    end
    globalCache[chapter] = {List = list, Fetched = os.clock()}
    return list
end

-- Sube el tiempo al ranking global si mejora el anterior de ese jugador.
local function submitGlobal(player, chapter, time)
    local store = orderedStore(chapter)
    if not store then
        return false
    end
    local centiseconds = math.floor(time * 100 + 0.5)
    local ok, err = withRetries(function()
        store:UpdateAsync(tostring(player.UserId), function(old)
            if type(old) == "number" and old <= centiseconds then
                return nil
            end
            return centiseconds
        end)
    end)
    if not ok then
        warn("[NOCTURNA] No se pudo guardar el récord global: " .. tostring(err))
    end
    return ok
end

-- Llamado al completar un capítulo. token identifica esa partida del capítulo:
-- dos llamadas con el mismo token no suman dos victorias.
function RecordsService.RecordChapter(chapter, seconds, token)
    if typeof(chapter) ~= "number" or chapter < 1 or chapter > chapterCount() then
        return {}
    end
    if typeof(seconds) ~= "number" or seconds ~= seconds or seconds < MIN_TIME then
        return {}
    end
    local results = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local key = tostring(token) .. ":" .. player.UserId
        if not recorded[key] then
            recorded[key] = true
            local result = ProgressionService.RecordWin(player, chapter, seconds)
            if result then
                insertServer(chapter, {UserId = player.UserId, Name = player.DisplayName, Time = result.Time})
                result.Chapter = chapter
                result.ServerRank = rankIn(serverBest[chapter], player.UserId)
                results[player] = result
                task.spawn(function()
                    if result.PersonalBest then
                        submitGlobal(player, chapter, result.Time)
                    end
                    local global = RecordsService.Global(chapter, result.PersonalBest)
                    result.GlobalRank = rankIn(global, player.UserId)
                    result.GlobalBest = result.GlobalRank == 1
                    if player.Parent then
                        Remotes.FireClient("RecordResult", player, result)
                    end
                end)
            end
        end
    end
    return results
end

function RecordsService.Server(chapter)
    return serverBest[chapter] or {}
end

-- Todo lo que muestra la pantalla de récords del lobby.
local function snapshotFor(player)
    local profile = ProgressionService.ClientView(player) or {}
    local data = {
        Personal = {
            Wins = profile.Wins or 0,
            ChapterWins = profile.ChapterWins or {},
            BestTimes = profile.BestTimes or {},
            LastWin = profile.LastWin,
            PlayTime = profile.PlayTime or 0,
            Completed = profile.CompletedMatches or 0,
        },
        Server = {},
        Global = {},
        Chapters = GameConfig.Chapters,
    }
    for chapter = 1, chapterCount() do
        data.Server[chapter] = RecordsService.Server(chapter)
        data.Global[chapter] = RecordsService.Global(chapter)
    end
    return data
end
RecordsService.Snapshot = snapshotFor

function RecordsService.Start()
    local lastRequest = {}
    Remotes.OnServer("RecordsRequest", 2, function(player)
        local now = os.clock()
        if now - (lastRequest[player] or -math.huge) < 2 then
            return
        end
        lastRequest[player] = now
        Remotes.FireClient("RecordsData", player, snapshotFor(player))
    end)
    Players.PlayerRemoving:Connect(function(player)
        lastRequest[player] = nil
    end)
end

return RecordsService
