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

local function objectiveIds(chapter)
    local ids = {}
    for _, objective in ipairs(chapter.Objectives) do
        table.insert(ids, objective.Id)
    end
    return ids
end

local function sendProgress(player, chapterNumber)
    local missionId = "CHAPTER_" .. chapterNumber
    local data = MissionService.GetProgress(player, missionId)
    if data then missionUpdate:FireClient(player, data) end
end

local function startChapter(player, chapterNumber)
    if not player.Parent or not chapters[chapterNumber] then return end
    local missionId = "CHAPTER_" .. chapterNumber
    local existing = MissionService.GetProgress(player, missionId)
    if not existing then
        local success, reason = MissionService.StartMission(
            player,
            missionId,
            objectiveIds(chapters[chapterNumber])
        )
        if not success then
            warn("[NOCTURNA] No se pudo iniciar misión:", reason)
            return
        end
    end
    player:SetAttribute("ActiveMission", missionId)
    sendProgress(player, chapterNumber)
end

startMission.Event:Connect(function(player, missionId, objectives)
    if not player or not player:IsA("Player") then return end
    local success, reason = MissionService.StartMission(player, missionId, objectives)
    if not success then warn("[NOCTURNA] No se pudo iniciar misión:", reason) end
    local chapterNumber = tonumber(string.match(missionId, "^CHAPTER_(%d+)$"))
    if chapterNumber then sendProgress(player, chapterNumber) end
end)

completeObjective.Event:Connect(function(player, missionId, objectiveId)
    if not player or not player:IsA("Player") then return end
    local chapterNumber = tonumber(string.match(missionId, "^CHAPTER_(%d+)$"))
    local currentChapter = math.clamp(tonumber(player:GetAttribute("LastChapter")) or 1, 1, #chapters)
    if not chapterNumber or chapterNumber ~= currentChapter then return end
    if player:GetAttribute("ActiveMission") ~= missionId then return end

    local success, finished = MissionService.CompleteObjective(player, missionId, objectiveId)
    if not success then return end
    sendProgress(player, chapterNumber)

    if finished then
        local nextChapter = chapterNumber + 1
        if nextChapter <= #chapters then
            player:SetAttribute("LastChapter", nextChapter)
            task.delay(2, function()
                if player.Parent then
                    startChapter(player, nextChapter)
                    missionUpdate:FireClient(player, {
                        missionId = missionId,
                        completed = #chapters[chapterNumber].Objectives,
                        total = #chapters[chapterNumber].Objectives,
                        finished = true,
                        objectives = {},
                    })
                end
            end)
            print("[NOCTURNA] Capítulo completado:", player.Name, missionId)
        else
            player:SetAttribute("CampaignCompleted", true)
            print("[NOCTURNA] Campaña completada:", player.Name)
        end
    end
end)

local function startCampaign(player)
    if player:GetAttribute("DataLoaded") ~= true then
        local deadline = os.clock() + 20
        while player.Parent and player:GetAttribute("DataLoaded") ~= true and os.clock() < deadline do
            task.wait(0.25)
        end
    end
    if not player.Parent then return end
    if player:GetAttribute("DataLoaded") ~= true then
        warn("[NOCTURNA] Progreso no cargado; se inicia capítulo 1 temporalmente:", player.Name)
    end
    local current = math.clamp(tonumber(player:GetAttribute("LastChapter")) or 1, 1, #chapters)
    startChapter(player, current)
end

Players.PlayerAdded:Connect(function(player)
    task.spawn(startCampaign, player)
end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(startCampaign, player) end

print("[NOCTURNA] Campaña individual y progresión por capítulos inicializadas.")
