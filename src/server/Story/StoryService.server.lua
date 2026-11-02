local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Chapters = require(script.Parent:WaitForChild("ChapterConfig"))

local remotes = ReplicatedStorage:FindFirstChild("NocturnaRemotes")
if not remotes then
    remotes = Instance.new("Folder")
    remotes.Name = "NocturnaRemotes"
    remotes.Parent = ReplicatedStorage
end

local function getRemote(name)
    local remote = remotes:FindFirstChild(name)
    if not remote then
        remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = remotes
    end
    return remote
end

local updateRemote = getRemote("StoryUpdate")
local dialogueRemote = getRemote("StoryDialogue")
local noticeRemote = getRemote("StoryNotice")

local currentChapter = 1
local currentObjective = 1
local completed = {}
local finished = false

local function getCurrentData()
    if finished then
        local finalChapter = Chapters[#Chapters]
        return {
            Chapter = #Chapters,
            ChapterName = finalChapter.Name,
            Objective = "Historia completada",
            ObjectiveNumber = #finalChapter.Objectives,
            TotalObjectives = #finalChapter.Objectives,
            Finished = true
        }
    end

    local chapter = Chapters[currentChapter]
    local objective = chapter.Objectives[currentObjective]

    return {
        Chapter = currentChapter,
        ChapterName = chapter.Name,
        Description = chapter.Description,
        Monster = chapter.Monster,
        Objective = objective.Name,
        ObjectiveId = objective.Id,
        ObjectiveNumber = currentObjective,
        TotalObjectives = #chapter.Objectives,
        Finished = false
    }
end

local function broadcastUpdate()
    updateRemote:FireAllClients(getCurrentData())
end

local function playChapterDialogue()
    local chapter = Chapters[currentChapter]
    if not chapter then return end

    for _, line in ipairs(chapter.Dialogue) do
        dialogueRemote:FireAllClients(line)
        task.wait(4)
    end
end

local function setChapter(index)
    if typeof(index) ~= "number" or index % 1 ~= 0 or not Chapters[index] then
        return false
    end

    currentChapter = index
    currentObjective = 1
    completed = {}
    finished = false
    broadcastUpdate()
    task.spawn(playChapterDialogue)
    return true
end

local function completeObjective(objectiveId, player)
    if finished then return end

    local chapter = Chapters[currentChapter]
    local objective = chapter.Objectives[currentObjective]
    if not objective or objective.Id ~= objectiveId or completed[objectiveId] then
        return
    end

    completed[objectiveId] = true
    noticeRemote:FireAllClients(player.Name .. " completó: " .. objective.Name)
    currentObjective += 1

    if currentObjective > #chapter.Objectives then
        if currentChapter >= #Chapters then
            finished = true
            broadcastUpdate()
            noticeRemote:FireAllClients("La historia de NOCTURNA ha terminado.")
        else
            currentChapter += 1
            currentObjective = 1
            noticeRemote:FireAllClients(
                "Capítulo desbloqueado: " .. Chapters[currentChapter].Name
            )
            broadcastUpdate()
            task.spawn(playChapterDialogue)
            return
        end
    end

    broadcastUpdate()
end

local function setupObjective(object)
    if not object:IsA("BasePart") then return end
    if object:GetAttribute("NocturnaPromptReady") then return end

    local objectiveId = object:GetAttribute("ObjectiveId")
    if typeof(objectiveId) ~= "string" then
        warn("[NOCTURNA] Falta el atributo ObjectiveId en", object:GetFullName())
        return
    end

    object:SetAttribute("NocturnaPromptReady", true)
    local prompt = object:FindFirstChild("NocturnaObjectivePrompt")
        or object:FindFirstChildOfClass("ProximityPrompt")

    if not prompt then
        prompt = Instance.new("ProximityPrompt")
        prompt.Name = "NocturnaObjectivePrompt"
        prompt.ActionText = "Completar"
        prompt.ObjectText = object:GetAttribute("DisplayName") or "Objetivo"
        prompt.KeyboardKeyCode = Enum.KeyCode.E
        prompt.HoldDuration = 0.6
        prompt.MaxActivationDistance = 10
        prompt.RequiresLineOfSight = false
        prompt.Parent = object
    end

    prompt.Triggered:Connect(function(player)
        completeObjective(objectiveId, player)
    end)
end

for _, object in ipairs(CollectionService:GetTagged("NocturnaObjective")) do
    setupObjective(object)
end
CollectionService:GetInstanceAddedSignal("NocturnaObjective"):Connect(setupObjective)

Players.PlayerAdded:Connect(function(player)
    task.delay(2, function()
        if player.Parent then
            updateRemote:FireClient(player, getCurrentData())
        end
    end)
end)

_G.NocturnaSetChapter = setChapter

broadcastUpdate()
task.spawn(playChapterDialogue)

print("[NOCTURNA] Historia y campaña iniciadas.")
