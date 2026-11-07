-- Qué clase de servidor es este. El mismo lugar sirve de lobby público y, como
-- servidor reservado, de partida para un grupo:
--   Lobby: servidor público con viajes; los grupos nunca juegan acá.
--   Partida: servidor reservado por un lobby; espera al grupo y juega.
--   Local: Studio o sin viajes; el lobby y la partida comparten el servidor, como antes.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local LobbyConfig = require(Shared.Config.LobbyConfig)

local ServerMode = {}

-- Un servidor reservado no tiene dueño; uno privado (VIP) sí.
function ServerMode.IsMatchServer()
    local privateId = game.PrivateServerId
    return type(privateId) == "string" and privateId ~= "" and game.PrivateServerOwnerId == 0
end

function ServerMode.CanTeleport()
    return LobbyConfig.Teleport.Enabled == true
        and not RunService:IsStudio()
        and type(game.PlaceId) == "number"
        and game.PlaceId ~= 0
end

function ServerMode.IsLobbyServer()
    return ServerMode.CanTeleport() and not ServerMode.IsMatchServer()
end

-- El viejo inicio de "todos listos" sólo existe cuando no se puede viajar.
function ServerMode.AllowsLocalStart()
    return not ServerMode.CanTeleport()
end

function ServerMode.Capacity()
    if ServerMode.IsLobbyServer() then
        return LobbyConfig.LobbyCapacity
    end
    return GameConfig.MaxPlayers
end

function ServerMode.Name()
    if ServerMode.IsMatchServer() then
        return "Partida"
    elseif ServerMode.IsLobbyServer() then
        return "Lobby"
    end
    return "Local"
end

return ServerMode
