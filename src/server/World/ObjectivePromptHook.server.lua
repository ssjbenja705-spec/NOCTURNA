-- NOCTURNA: Interactive Objective Hook
-- Conecta ProximityPrompts con el sistema de misiones.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ServerScriptService = game:GetService("ServerScriptService")

local missionFolder = ServerScriptService:WaitForChild(
    "NocturnaMissionEvents"
)

local completeObjective = missionFolder:WaitForChild(
    "CompleteObjective"
)

local function handlePrompt(prompt, player)
    if not player or not player:IsA("Player") then
        return
    end

    if not prompt:IsDescendantOf(workspace) then
        return
    end

    local missionId = prompt:GetAttribute("MissionId")
    local objectiveId = prompt:GetAttribute("ObjectiveId")

    if typeof(missionId) ~= "string" or missionId == "" then
        return
    end

    if typeof(objectiveId) ~= "string" or objectiveId == "" then
        return
    end

    if player:GetAttribute("InNocturnaMatch") == false then
        return
    end

    completeObjective:Fire(player, missionId, objectiveId)

    print(
        "[NOCTURNA] Interacción de objetivo:",
        player.Name,
        missionId,
        objectiveId
    )
end

ProximityPromptService.PromptTriggered:Connect(handlePrompt)

print("[NOCTURNA] Objetivos interactivos conectados.")
