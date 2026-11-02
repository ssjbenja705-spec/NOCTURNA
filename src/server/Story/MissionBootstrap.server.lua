-- NOCTURNA: Mission Bootstrap
-- Recibe solicitudes internas de otros sistemas del servidor.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MissionService = require(script.Parent:WaitForChild("MissionService"))

local internalFolder = ServerScriptService:FindFirstChild("NocturnaMissionEvents")
if not internalFolder then
    internalFolder = Instance.new("Folder")
    internalFolder.Name = "NocturnaMissionEvents"
    internalFolder.Parent = ServerScriptService
end

local function getOrCreateBindable(name)
    local event = internalFolder:FindFirstChild(name)
    if not event then
        event = Instance.new("BindableEvent")
        event.Name = name
        event.Parent = internalFolder
    end
    return event
end

local startMission = getOrCreateBindable("StartMission")
local completeObjective = getOrCreateBindable("CompleteObjective")

local remoteFolder = ReplicatedStorage:FindFirstChild("NocturnaRemotes")
if not remoteFolder then
    remoteFolder = Instance.new("Folder")
    remoteFolder.Name = "NocturnaRemotes"
    remoteFolder.Parent = ReplicatedStorage
end

local missionUpdate = remoteFolder:FindFirstChild("MissionUpdate")
if not missionUpdate then
    missionUpdate = Instance.new("RemoteEvent")
    missionUpdate.Name = "MissionUpdate"
    missionUpdate.Parent = remoteFolder
end

startMission.Event:Connect(function(player, missionId, objectives)
    local success, reason = MissionService.StartMission(player, missionId, objectives)
    if not success then
        warn("[NOCTURNA] No se pudo iniciar misión:", reason)
        return
    end

    local data = MissionService.GetProgress(player, missionId)
    if data then
        missionUpdate:FireClient(player, data)
    end
end)

completeObjective.Event:Connect(function(player, missionId, objectiveId)
    local success, finished = MissionService.CompleteObjective(
        player,
        missionId,
        objectiveId
    )
    if not success then
        warn("[NOCTURNA] No se pudo completar objetivo:", finished)
        return
    end

    local data = MissionService.GetProgress(player, missionId)
    if data then
        missionUpdate:FireClient(player, data)
    end

    if finished then
        print("[NOCTURNA] Misión completada:", player.Name, missionId)
    end
end)

print("[NOCTURNA] Servicio de misiones iniciado.")
