-- Punto único de acceso a los RemoteEvents, con límite de frecuencia en el servidor.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Names = require(script.Parent.Parent.Events.RemoteNames)
local RateLimiter = require(script.Parent.Parent.Logic.RateLimiter)

local FOLDER_NAME = "NocturnaRemotes"

local RemoteHelper = {}
local directions = {}

for _, name in ipairs(Names.ClientToServer) do
    directions[name] = "ClientToServer"
end
for _, name in ipairs(Names.ServerToClient) do
    directions[name] = "ServerToClient"
end

local function assertDirection(name, expected)
    local direction = directions[name]
    assert(direction ~= nil, "[NOCTURNA] Remoto desconocido: " .. tostring(name))
    assert(direction == expected, "[NOCTURNA] Remoto usado en dirección incorrecta: " .. name)
end

local function getFolder()
    return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

-- Sólo el servidor crea los remotos; lo hace una vez, antes de iniciar los servicios.
function RemoteHelper.Setup()
    assert(RunService:IsServer(), "RemoteHelper.Setup es exclusivo del servidor")

    local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = FOLDER_NAME
        folder.Parent = ReplicatedStorage
    end

    for name in pairs(directions) do
        if not folder:FindFirstChild(name) then
            local remote = Instance.new("RemoteEvent")
            remote.Name = name
            remote.Parent = folder
        end
    end

    return folder
end

function RemoteHelper.Get(name)
    assert(directions[name] ~= nil, "[NOCTURNA] Remoto desconocido: " .. tostring(name))
    return getFolder():WaitForChild(name)
end

function RemoteHelper.FireServer(name, ...)
    assertDirection(name, "ClientToServer")
    RemoteHelper.Get(name):FireServer(...)
end

function RemoteHelper.FireClient(name, player, ...)
    assertDirection(name, "ServerToClient")
    if player and player.Parent == Players then
        RemoteHelper.Get(name):FireClient(player, ...)
    end
end

function RemoteHelper.FireAll(name, ...)
    assertDirection(name, "ServerToClient")
    RemoteHelper.Get(name):FireAllClients(...)
end

function RemoteHelper.OnClient(name, handler)
    assertDirection(name, "ServerToClient")
    return RemoteHelper.Get(name).OnClientEvent:Connect(handler)
end

-- perSecond limita cuántas veces por segundo se atiende a cada jugador.
function RemoteHelper.OnServer(name, perSecond, handler)
    assertDirection(name, "ClientToServer")
    local limiter = RateLimiter.new(perSecond, perSecond * 2)

    Players.PlayerRemoving:Connect(function(player)
        limiter:Forget(player)
    end)

    return RemoteHelper.Get(name).OnServerEvent:Connect(function(player, ...)
        if limiter:Allow(player, os.clock()) then
            handler(player, ...)
        end
    end)
end

return RemoteHelper
