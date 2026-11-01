local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ObjectiveConfig"))
local remote = ReplicatedStorage:WaitForChild("NocturnaRemotes"):WaitForChild("ObjectiveUpdate")
local progress = {}

local function sendProgress(player)
    local chapter = workspace:GetAttribute("NocturnaChapter") or 1
    local chapterData = Config.Chapters[chapter]
    if not chapterData then return end

    local index = progress[player] or 1
    remote:FireClient(player, {
        Chapter = chapterData.Name,
        Objectives = chapterData.Objectives,
        Current = index,
        Complete = index > #chapterData.Objectives,
    })
end

local function completeObjective(player)
    local chapter = workspace:GetAttribute("NocturnaChapter") or 1
    local chapterData = Config.Chapters[chapter]
    if not chapterData or not progress[player] or progress[player] > #chapterData.Objectives then
        return false
    end

    progress[player] += 1
    sendProgress(player)
    if progress[player] > #chapterData.Objectives then
        print("[NOCTURNA] Objetivos completados por", player.Name)
    end
    return true
end

local function setupPlayer(player)
    progress[player] = 1
    task.delay(2, function()
        if player.Parent then sendProgress(player) end
    end)
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
    progress[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

workspace:GetAttributeChangedSignal("NocturnaChapter"):Connect(function()
    for player in pairs(progress) do
        progress[player] = 1
        sendProgress(player)
    end
end)

local function connectPrompt(object)
    if object:IsA("ProximityPrompt") then
        object.Triggered:Connect(function(player)
            if object:GetAttribute("CompleteObjective") == true then
                completeObjective(player)
            end
        end)
    end
end

for _, object in ipairs(workspace:GetDescendants()) do
    connectPrompt(object)
end
workspace.DescendantAdded:Connect(connectPrompt)

_G.NocturnaObjectives = {
    Complete = completeObjective,
    Refresh = sendProgress,
}

print("[NOCTURNA] Sistema de objetivos iniciado.")