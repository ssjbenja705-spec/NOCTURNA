local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MissionService = require(script.Parent:WaitForChild("MissionService"))
local chapters = require(script.Parent:WaitForChild("ChapterConfig"))

local internalFolder = ServerScriptService:FindFirstChild("NocturnaMissionEvents") or Instance.new("Folder")
internalFolder.Name = "NocturnaMissionEvents"
internalFolder.Parent = ServerScriptService

local function bindable(name)
    local event = internalFolder:FindFirstChild(name) or Instance.new("BindableEvent")
    event.Name = name
    event.Parent = internalFolder
    return event
end

local startMission = bindable("StartMission")
local completeObjective = bindable("CompleteObjective")

local remotes = ReplicatedStorage:FindFirstChild("NocturnaRemotes") or Instance.new("Folder")
remotes.Name = "NocturnaRemotes"
remotes.Parent = ReplicatedStorage
local missionUpdate = remotes:FindFirstChild("MissionUpdate") or Instance.new("RemoteEvent")
missionUpdate.Name = "MissionUpdate"
missionUpdate.Parent = remotes

local function startCampaign(player)
    for chapterNumber, chapter in ipairs(chapters) do
        local ids = {}
        for _, objective in ipairs(chapter.Objectives) do
            table.insert(ids, objective.Id)
        end
        MissionService.StartMission(player, "CHAPTER_" .. chapterNumber, ids)
    end
    local current = math.clamp(tonumber(player:GetAttribute("LastChapter")) or 1, 1, #chapters)
    local progress = MissionService.GetProgress(player, "CHAPTER_" .. current)
    if progress then missionUpdate:FireClient(player, progress) end
end

startMission.Event:Connect(function(player, missionId, objectives)
    if not player or not player:IsA("Player") then return end
    local success, reason = MissionService.StartMission(player, missionId, objectives)
    if not success then warn("[NOCTURNA] No se pudo iniciar misión:", reason) end
    local data = MissionService.GetProgress(player, missionId)
    if data then missionUpdate:FireClient(player, data) end
end)

completeObjective.Event:Connect(function(player, missionId, objectiveId)
    if not player or not player:IsA("Player") then return end
    local success, finished = MissionService.CompleteObjective(player, missionId, objectiveId)
    if not success then return end
    local data = MissionService.GetProgress(player, missionId)
    if data then missionUpdate:FireClient(player, data) end
    if finished then
        local chapterNumber = tonumber(string.match(missionId, "^CHAPTER_(%d+)$"))
        if chapterNumber and chapterNumber < #chapters then
            player:SetAttribute("LastChapter", math.max(player:GetAttribute("LastChapter") or 1, chapterNumber + 1))
        end
        print("[NOCTURNA] Capítulo completado:", player.Name, missionId)
    end
end)

Players.PlayerAdded:Connect(function(player)
    task.defer(startCampaign, player)
end)
for _, player in ipairs(Players:GetPlayers()) do task.defer(startCampaign, player) end

print("[NOCTURNA] Misiones de campaña inicializadas.")
