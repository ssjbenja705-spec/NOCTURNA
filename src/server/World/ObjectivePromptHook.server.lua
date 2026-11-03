-- NOCTURNA: conecta prompts con misiones individuales y capítulo activo.
local ProximityPromptService = game:GetService("ProximityPromptService")
local ServerScriptService = game:GetService("ServerScriptService")

local missionFolder = ServerScriptService:WaitForChild("NocturnaMissionEvents")
local completeObjective = missionFolder:WaitForChild("CompleteObjective")

local function handlePrompt(prompt, player)
    if not player or not player:IsA("Player") then return end
    if not prompt:IsDescendantOf(workspace) then return end
    if player:GetAttribute("InNocturnaMatch") == false then return end

    local missionId = prompt:GetAttribute("MissionId")
    local objectiveId = prompt:GetAttribute("ObjectiveId")
    if typeof(missionId) ~= "string" or missionId == "" then return end
    if typeof(objectiveId) ~= "string" or objectiveId == "" then return end

    local chapterNumber = tonumber(string.match(missionId, "^CHAPTER_(%d+)$"))
    local currentChapter = tonumber(player:GetAttribute("LastChapter")) or 1
    if not chapterNumber or chapterNumber ~= currentChapter then return end
    if player:GetAttribute("ActiveMission") ~= missionId then return end

    completeObjective:Fire(player, missionId, objectiveId)
end

ProximityPromptService.PromptTriggered:Connect(handlePrompt)
print("[NOCTURNA] Prompts de objetivos validados por capítulo y jugador.")
