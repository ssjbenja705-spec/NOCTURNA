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
        return {
            Kind = "Waiting",
            Arrived = arrivedCount(),
            Expected = expectedCount(),
            Remaining = deadline and math.max(0, math.ceil(deadline - os.clock())) or LobbyConfig.Teleport.PartyWait,
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

local function begin()
    stage = "Playing"
    local chapter = settings and settings.Chapter or 1
    local difficulty = settings and settings.Difficulty or GameConfig.DefaultDifficulty
    -- Los datos de viaje pasan por el cliente: el capítulo nunca supera lo que
    -- desbloqueó alguien del grupo que está presente.
    chapter = math.clamp(chapter, 1, highestUnlocked())
    broadcast()
    LobbyService.RequestMatch(chapter, difficulty)
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
    end

    if stage == "Returning" then
        -- Llegó cuando la partida ya había terminado.
        task.spawn(MatchTeleport.ReturnToLobby, {player})
    end
    broadcast()
end

local function returnEveryone()
    if stage ~= "Playing" then
        return
    end
    stage = "Returning"
    broadcast()

    local players = Players:GetPlayers()
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
