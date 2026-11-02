-- NOCTURNA: Chapter Progression Hook

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ServerScriptService = game:GetService("ServerScriptService")

local eventFolder = ServerScriptService:WaitForChild(
    "NocturnaProgressionEvents"
)

local chapterEvent = eventFolder:WaitForChild("ChapterUnlocked")

local activated = {}

local function onPromptTriggered(prompt, player)
    if not player or not player:IsA("Player") then
        return
    end

    local isChapterTrigger =
        CollectionService:HasTag(prompt, "NocturnaChapterTrigger")
        or prompt:GetAttribute("IsNocturnaChapterTrigger") == true

    if not isChapterTrigger then
        return
    end

    local chapterNumber = prompt:GetAttribute("ChapterNumber")

    if typeof(chapterNumber) ~= "number"
        or chapterNumber < 1
        or chapterNumber > 5
        or chapterNumber % 1 ~= 0 then

        warn("[NOCTURNA] Activador de capítulo con ChapterNumber inválido:",
            prompt:GetFullName())
        return
    end

    local key = tostring(player.UserId) .. ":" .. prompt:GetFullName()
    if activated[key] then
        return
    end

    activated[key] = true
    chapterEvent:Fire(player, chapterNumber)
    print("[NOCTURNA] Capítulo registrado:", player.Name, chapterNumber)
end

ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

Players.PlayerRemoving:Connect(function(player)
    local prefix = tostring(player.UserId) .. ":"
    for key in pairs(activated) do
        if string.sub(key, 1, #prefix) == prefix then
            activated[key] = nil
        end
    end
end)

print("[NOCTURNA] Conexión de progreso de capítulos iniciada.")
