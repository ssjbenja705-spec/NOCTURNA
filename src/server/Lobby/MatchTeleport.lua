-- Viajes entre servidores del mismo lugar: el grupo a un servidor reservado nuevo y,
-- al terminar, de vuelta a un lobby público. Cada viaje se reintenta y, si alguien
-- no puede salir, se le avisa. También recuerda la partida de cada jugador para que
-- quien se desconecta pueda volver a ella desde el lobby.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local Shared = game:GetService("ReplicatedStorage").Shared
local LobbyConfig = require(Shared.Config.LobbyConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local PartyLogic = require(script.Parent.PartyLogic)

local CONFIG = LobbyConfig.Teleport
local ACTIVE_STORE = "NOCTURNA_ACTIVE_MATCH_V1"

local MatchTeleport = {}
-- [player] = {Options, PlaceId, Attempts, Kind, Since}: viajes en curso, para reintentar.
local pending = {}
-- Un viaje que no terminó ni falló en este tiempo se da por perdido: el jugador
-- vuelve a poder usar los ascensores en vez de quedar marcado como "viajando".
local PENDING_TTL = LobbyConfig.LaunchTimeout + 15

-- Fallas que no se arreglan reintentando: se avisa enseguida con el motivo.
local FATAL_RESULTS = {
    Unauthorized = "Roblox no autorizó el viaje",
    GameNotFound = "No se encontró el servidor",
    GameFull = "El servidor de la partida está lleno",
}
local store = nil

local function getStore()
    if store then
        return store
    end
    local success, result = pcall(function()
        return DataStoreService:GetDataStore(ACTIVE_STORE)
    end)
    if success then
        store = result
    end
    return store
end

local function activeKey(userId)
    return "USER_" .. tostring(userId)
end

local function notify(player, text)
    Remotes.FireClient("StoryNotice", player, text)
end

-- Repite una llamada que puede fallar (red, cupos de Roblox) con espera creciente.
local function retry(callback)
    local lastError = nil
    for attempt = 1, CONFIG.Attempts do
        local results = table.pack(pcall(callback))
        if results[1] then
            return true, table.unpack(results, 2, results.n)
        end
        lastError = results[2]
        warn("[NOCTURNA] Falló un viaje entre servidores. Intento:", attempt, lastError)
        if attempt < CONFIG.Attempts then
            task.wait(CONFIG.RetryDelay * attempt)
        end
    end
    return false, lastError
end

local function present(players)
    local result = {}
    for _, player in ipairs(players) do
        if player.Parent == Players then
            table.insert(result, player)
        end
    end
    return result
end

local function teleport(players, options, kind)
    local placeId = game.PlaceId
    for _, player in ipairs(players) do
        pending[player] = {Options = options, PlaceId = placeId, Attempts = 1, Kind = kind, Since = os.clock()}
    end

    local success, result = retry(function()
        return TeleportService:TeleportAsync(placeId, players, options)
    end)
    if not success then
        for _, player in ipairs(players) do
            pending[player] = nil
        end
    end
    return success, result
end

-- Si el viaje de alguien falla después de empezar, se vuelve a intentar con los
-- mismos datos (el mismo servidor reservado) antes de darse por vencido.
local function giveUp(player, entry, reason)
    pending[player] = nil
    local detail = reason and (reason .. ". ") or ""
    if entry.Kind == "Lobby" then
        notify(player, detail .. "No pudimos llevarte a la recepción. Tocá VOLVER AL LOBBY para intentar de nuevo.")
    else
        notify(player, detail .. "No pudimos llevarte a la partida. Probá de nuevo desde un ascensor.")
    end
end

local function onTeleportFailed(player, result, message)
    local entry = pending[player]
    local resultName = typeof(result) == "EnumItem" and result.Name or tostring(result)
    warn("[NOCTURNA] Viaje fallido de", player.Name, resultName, tostring(message))
    if not entry then
        return
    end

    -- Ya hay un viaje en marcha para este jugador: reintentar sólo lo trabaría más.
    if resultName == "IsTeleporting" then
        return
    end

    local fatal = FATAL_RESULTS[resultName]
    if fatal or entry.Attempts >= CONFIG.Attempts then
        giveUp(player, entry, fatal)
        return
    end

    entry.Attempts += 1
    entry.Since = os.clock()
    notify(player, string.format("El viaje falló. Reintentando (%d/%d)...", entry.Attempts, CONFIG.Attempts))
    task.delay(CONFIG.RetryDelay * entry.Attempts, function()
        if player.Parent ~= Players or pending[player] ~= entry then
            return
        end
        local success, err = pcall(function()
            TeleportService:TeleportAsync(entry.PlaceId, {player}, entry.Options)
        end)
        if not success then
            onTeleportFailed(player, "Retry", err)
        end
    end)
end

local function remember(players, accessCode, serverId, data)
    local dataStore = getStore()
    if not dataStore then
        return
    end
    local record = {
        Code = accessCode,
        ServerId = serverId,
        Data = data,
        Expires = os.time() + math.floor(CONFIG.RejoinHours * 3600),
    }
    for _, player in ipairs(players) do
        local success, err = pcall(function()
            dataStore:SetAsync(activeKey(player.UserId), record)
        end)
        if not success then
            warn("[NOCTURNA] No se pudo recordar la partida de", player.Name, err)
        end
    end
end

-- Reserva un servidor nuevo del mismo lugar y manda a todo el grupo junto.
function MatchTeleport.LaunchParty(players, data)
    local travellers = present(players)
    if #travellers == 0 then
        return false, "Sin jugadores"
    end

    local placeId = game.PlaceId
    local reserved, accessCode, serverId = retry(function()
        return TeleportService:ReserveServer(placeId)
    end)
    if not reserved or type(accessCode) ~= "string" then
        return false, "No se pudo reservar un servidor"
    end

    -- Mientras se reservaba alguien pudo irse. La lista del grupo es la de quienes
    -- de verdad viajan: si no, el servidor de la partida esperaría el límite
    -- completo a alguien que nunca va a llegar.
    travellers = present(travellers)
    if #travellers == 0 then
        return false, "Sin jugadores"
    end
    data = table.clone(data)
    data.Party = {}
    for _, player in ipairs(travellers) do
        table.insert(data.Party, player.UserId)
    end
    if not table.find(data.Party, data.Host) then
        data.Host = data.Party[1]
    end
    data.MaxPlayers = math.max(tonumber(data.MaxPlayers) or #data.Party, #data.Party)

    local options = Instance.new("TeleportOptions")
    options.ReservedServerAccessCode = accessCode
    options:SetTeleportData(data)

    local success, err = teleport(travellers, options, "Match")
    if not success then
        return false, tostring(err)
    end
    task.spawn(remember, travellers, accessCode, serverId, data)
    return true
end

-- De la partida a un lobby público cualquiera del mismo lugar.
function MatchTeleport.ReturnToLobby(players)
    local travellers = present(players)
    if #travellers == 0 then
        return true
    end
    local options = Instance.new("TeleportOptions")
    options:SetTeleportData({ReturnFromMatch = true})
    return (teleport(travellers, options, "Lobby"))
end

-- La partida de la que alguien se desconectó, si sigue vigente.
function MatchTeleport.LookupActive(userId)
    local dataStore = getStore()
    if not dataStore then
        return nil
    end
    local success, record = pcall(function()
        return dataStore:GetAsync(activeKey(userId))
    end)
    if not success or type(record) ~= "table" or type(record.Code) ~= "string" then
        return nil
    end
    if type(record.Expires) ~= "number" or record.Expires < os.time() then
        return nil
    end
    local settings = PartyLogic.ParseTeleportData(record.Data)
    if not settings or not table.find(settings.Party, userId) then
        return nil
    end
    record.Settings = settings
    return record
end

function MatchTeleport.Forget(userId, serverId)
    local dataStore = getStore()
    if not dataStore then
        return
    end
    pcall(function()
        local record = dataStore:GetAsync(activeKey(userId))
        if record ~= nil and (serverId == nil or type(record) ~= "table" or record.ServerId == serverId) then
            dataStore:RemoveAsync(activeKey(userId))
        end
    end)
end

-- Vuelve a la partida con el mismo código: si el servidor ya cerró, Roblox abre uno
-- nuevo con esos datos y el capítulo empieza de nuevo.
function MatchTeleport.Rejoin(player)
    local record = MatchTeleport.LookupActive(player.UserId)
    if not record then
        notify(player, "Esa partida ya terminó.")
        return false
    end

    local settings = record.Settings
    local data = {
        Chapter = settings.Chapter,
        Difficulty = settings.Difficulty,
        MaxPlayers = settings.MaxPlayers,
        Party = settings.Party,
        Host = settings.Host,
        Rejoin = true,
    }
    local options = Instance.new("TeleportOptions")
    options.ReservedServerAccessCode = record.Code
    options:SetTeleportData(data)

    local success = teleport({player}, options, "Match")
    if not success then
        notify(player, "No pudimos llevarte a tu partida. Probá de nuevo en un rato.")
    end
    return success
end

function MatchTeleport.IsTravelling(player)
    local entry = pending[player]
    if entry and os.clock() - entry.Since > PENDING_TTL then
        pending[player] = nil
        return false
    end
    return entry ~= nil
end

-- El ascensor se volvió a abrir porque el viaje no se completó: quien sigue acá
-- deja de figurar como viajando y puede volver a intentarlo.
function MatchTeleport.Cancel(player)
    pending[player] = nil
end

function MatchTeleport.Start()
    TeleportService.TeleportInitFailed:Connect(onTeleportFailed)
    Players.PlayerRemoving:Connect(function(player)
        pending[player] = nil
    end)
end

return MatchTeleport
