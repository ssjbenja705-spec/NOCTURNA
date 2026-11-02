local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))

local EVENT_FOLDER_NAME = "NocturnaProgressionEvents"
local eventFolder = ServerScriptService:FindFirstChild(EVENT_FOLDER_NAME)

if not eventFolder then
    eventFolder = Instance.new("Folder")
    eventFolder.Name = EVENT_FOLDER_NAME
    eventFolder.Parent = ServerScriptService
end

local function getOrCreateEvent(name)
    local event = eventFolder:FindFirstChild(name)
    if not event then
        event = Instance.new("BindableEvent")
        event.Name = name
        event.Parent = eventFolder
    end
    return event
end

local chapterUnlocked = getOrCreateEvent("ChapterUnlocked")
local documentCollected = getOrCreateEvent("DocumentCollected")
local playerDied = getOrCreateEvent("PlayerDied")
local matchCompleted = getOrCreateEvent("MatchCompleted")
local monsterEncountered = getOrCreateEvent("MonsterEncountered")
local connectedCharacters = {}

local function waitForProfile(player)
    local attempts = 0
    while player.Parent == Players and attempts < 300 do
        if ProgressionService.Get(player) then
            return true
        end
        attempts += 1
        task.wait(0.1)
    end
    return false
end

local function connectCharacter(player, character)
    if connectedCharacters[character] then return end
    connectedCharacters[character] = true

    local humanoid = character:WaitForChild("Humanoid", 15)
    if not humanoid then return end

    humanoid.Died:Connect(function()
        if not waitForProfile(player) then return end
        ProgressionService.RecordDeath(player)
        playerDied:Fire(player)
    end)
end

local function setupPlayer(player)
    player.CharacterAdded:Connect(function(character)
        connectCharacter(player, character)
    end)
    if player.Character then
        connectCharacter(player, player.Character)
    end
end

chapterUnlocked.Event:Connect(function(player, chapterNumber)
    if player and player:IsA("Player") and waitForProfile(player) then
        chapterNumber = tonumber(chapterNumber)
        if not chapterNumber or chapterNumber < 1 or chapterNumber > 5 then
            return
        end

        chapterNumber = math.floor(chapterNumber)
        local profile = ProgressionService.Get(player)
        if not profile then return end

        for chapter = profile.UnlockedChapter + 1, chapterNumber do
            if not ProgressionService.UnlockChapter(player, chapter) then
                return
            end
        end

        ProgressionService.SetCurrentChapter(player, chapterNumber)
    end
end)

documentCollected.Event:Connect(function(player, documentId)
    if player and player:IsA("Player") and waitForProfile(player) then
        ProgressionService.AddDocument(player, documentId)
    end
end)

matchCompleted.Event:Connect(function(player)
    if player and player:IsA("Player") and waitForProfile(player) then
        ProgressionService.RecordMatchCompleted(player)
    end
end)

monsterEncountered.Event:Connect(function(player)
    if player and player:IsA("Player") and waitForProfile(player) then
        ProgressionService.RecordMonsterEncounter(player)
    end
end)

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
    for character in pairs(connectedCharacters) do
        if character.Parent == nil then
            connectedCharacters[character] = nil
        end
    end
end)

for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

print("[NOCTURNA] Integración de progreso iniciada correctamente.")
