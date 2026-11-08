-- Servidor de partida: un servidor reservado al que viajó un grupo desde el lobby.
-- No hay ascensores ni donaciones: espera al grupo (con un límite de tiempo), arranca
-- el capítulo elegido y, cuando la partida termina, devuelve a todos a un lobby público.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local LobbyConfig = require(Shared.Config.LobbyConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local LobbyService = require(script.Parent.Parent.Multiplayer.LobbyService)
local MatchTeleport = require(script.Parent.MatchTeleport)
local PartyLogic = require(script.Parent.PartyLogic)
local ServerMode = require(script.Parent.ServerMode)

local CHECK_INTERVAL = 0.5
-- Tras el límite se espera un poco más a que carguen los datos de quien ya llegó.
local DATA_GRACE = 15
-- Quien vuelve a una partida cuyo servidor ya cerró no espera al resto del grupo.
local REJOIN_WAIT = 5

local MatchServerService = {}
-- Waiting: esperando al grupo. Playing: en partida. Returning: volviendo al lobby.
local stage = "Waiting"
local settings = nil
local deadline = nil
local announcedExpiry = false
-- La partida se quedó sin nadie y espera a que alguien vuelva.
local resumed = false

local function readSettings(player)
    local success, joinData = pcall(function()
        return player:GetJoinData()
    end)
    if not success or type(joinData) ~= "table" then
        return nil
    end
    -- Sólo valen los datos de un viaje hecho desde este mismo juego.
    if joinData.SourcePlaceId ~= game.PlaceId then
        return nil
    end
    return PartyLogic.ParseTeleportData(joinData.TeleportData)
end

local function expectedCount()
    return settings and #settings.Party or 1
end

local function arrivedCount()
    if not settings then
        return #Players:GetPlayers()
    end
    local count = 0
    for _, userId in ipairs(settings.Party) do
        if Players:GetPlayerByUserId(userId) then
            count += 1
        end
    end
    return count
end

local function highestUnlocked()
    local highest = 1
    for _, player in ipairs(Players:GetPlayers()) do
        local unlocked = player:GetAttribute("NocturnaUnlockedChapter")
        if type(unlocked) == "number" then
            highest = math.max(highest, unlocked)
        end
    end
    return highest
end

local function everyoneLoaded()
    for _, player in ipairs(Players:GetPlayers()) do
        if player:GetAttribute("NocturnaDataLoaded") ~= true then
            return false
        end
    end
    return true
end

function MatchServerService.View(_player)
    if stage == "Waiting" then
        local remaining = deadline and math.max(0, math.ceil(deadline - os.clock())) or LobbyConfig.Teleport.PartyWait
        return {
            Kind = "Waiting",
            Arrived = arrivedCount(),
            Expected = expectedCount(),
            Remaining = remaining,
            -- Venció la espera: sólo falta que carguen los datos de quien llegó.
            Preparing = deadline ~= nil and remaining <= 0,
        }
    elseif stage == "Returning" then
        return {Kind = "Returning"}
    end
    return {Kind = "None"}
end

local function broadcast()
    for _, player in ipairs(Players:GetPlayers()) do
        Remotes.FireClient("QueueUpdate", player, MatchServerService.View(player))
    end
end

local function notifyAll(text)
    for _, player in ipairs(Players:GetPlayers()) do
        Remotes.FireClient("StoryNotice", player, text)
    end
end

local function begin()
    stage = "Playing"
    local chapter = settings and settings.Chapter or 1
    local difficulty = settings and settings.Difficulty or GameConfig.DefaultDifficulty
    -- Los datos de viaje pasan por el cliente: el capítulo nunca supera lo que
    -- desbloqueó alguien del grupo que está presente.
    chapter = math.clamp(chapter, 1, highestUnlocked())

    -- Nadie queda adivinando por qué empezó sin alguien.
    if not settings then
        notifyAll("No llegaron los datos del grupo: la partida empieza en el capítulo " .. chapter .. ".")
    elseif not settings.Rejoin and not resumed and arrivedCount() < expectedCount() then
        notifyAll(string.format(
            "No llegaron todos (%d de %d). La partida empieza igual: los que falten pueden volver desde el lobby.",
            arrivedCount(), expectedCount()
        ))
    end

    broadcast()
    if not LobbyService.RequestMatch(chapter, difficulty) then
        -- Ya había una partida en marcha en este servidor (no debería pasar):
        -- nadie queda esperando para siempre.
        warn("[NOCTURNA] El servidor de partida no pudo arrancar el capítulo: ya había una partida.")
    end
end

local function waitForParty()
    while stage == "Waiting" do
        task.wait(CHECK_INTERVAL)
        if #Players:GetPlayers() > 0 then
            deadline = deadline or (os.clock() + LobbyConfig.Teleport.PartyWait)
            local loaded = everyoneLoaded()
            local complete = settings ~= nil and arrivedCount() >= expectedCount()
            local expired = os.clock() >= deadline
            if loaded and (complete or expired) or os.clock() >= deadline + DATA_GRACE then
                begin()
            elseif expired and not announcedExpiry then
                announcedExpiry = true
                broadcast()
            end
        end
    end
end

local function onPlayerAdded(player)
    local parsed = readSettings(player)
    if parsed and not settings then
        settings = parsed
        if parsed.Rejoin then
            deadline = os.clock() + REJOIN_WAIT
        end
    elseif resumed and stage == "Waiting" and not deadline then
        -- Vuelve alguien a una partida que se había quedado sin nadie.
        deadline = os.clock() + REJOIN_WAIT
    end

    if stage == "Returning" then
        -- Llegó cuando la partida ya había terminado: vuelve a la recepción con aviso.
        Remotes.FireClient("StoryNotice", player, "Esa partida ya terminó. Volviendo a la recepción...")
        task.spawn(MatchTeleport.ReturnToLobby, {player})
    end
    broadcast()
end

local function returnEveryone()
    if stage ~= "Playing" then
        return
    end

    local players = Players:GetPlayers()
    if #players == 0 then
        -- Se cayeron todos (cierre del juego, corte de internet): la partida no
        -- terminó. Se guarda su registro y el servidor vuelve a esperar: quien
        -- vuelva desde el lobby retoma el capítulo en vez de rebotar a la recepción.
        stage = "Waiting"
        deadline = nil
        announcedExpiry = false
        resumed = true
        task.spawn(waitForParty)
        return
    end

    stage = "Returning"
    broadcast()

    local forget = {}
    for _, player in ipairs(players) do
        forget[player.UserId] = true
    end
    for _, userId in ipairs(settings and settings.Party or {}) do
        forget[userId] = true
    end
    for userId in pairs(forget) do
        task.spawn(MatchTeleport.Forget, userId, game.PrivateServerId)
    end

    MatchTeleport.ReturnToLobby(players)
end

-- Botón VOLVER AL LOBBY: reintento manual, o salir mientras se espera al grupo.
function MatchServerService.RequestReturn(player)
    if not ServerMode.IsMatchServer() or GameState.Phase ~= "Lobby" or MatchTeleport.IsTravelling(player) then
        return false
    end
    task.spawn(MatchTeleport.ReturnToLobby, {player})
    return true
end

function MatchServerService.Stage()
    return stage
end

function MatchServerService.Settings()
    return settings
end

function MatchServerService.Start()
    if not ServerMode.IsMatchServer() then
        return
    end

    EventBus.On("ReturnedToLobby", returnEveryone)
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(function()
        task.defer(broadcast)
    end)
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(onPlayerAdded, player)
    end
    task.spawn(waitForParty)
end

return MatchServerService
