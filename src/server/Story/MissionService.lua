-- NOCTURNA: Mission Service
-- Control centralizado de misiones y objetivos por jugador.

local Players = game:GetService("Players")

local MissionService = {}
local progress = {}

local function getPlayerData(player)
    if not progress[player] then
        progress[player] = {
            missions = {},
        }
    end

    return progress[player]
end

local function copyObjectives(objectives)
    local result = {}

    for _, objectiveId in ipairs(objectives) do
        result[objectiveId] = false
    end

    return result
end

function MissionService.StartMission(player, missionId, objectiveIds)
    if not player or not player:IsA("Player") then
        return false, "Jugador inválido"
    end

    if typeof(missionId) ~= "string" or missionId == "" then
        return false, "Identificador de misión inválido"
    end

    if typeof(objectiveIds) ~= "table" or #objectiveIds == 0 then
        return false, "La misión necesita objetivos"
    end

    local objectives = {}

    for _, id in ipairs(objectiveIds) do
        if typeof(id) ~= "string" or id == "" then
            return false, "Identificador de objetivo inválido"
        end

        if objectives[id] then
            return false, "Hay objetivos repetidos"
        end

        objectives[id] = true
    end

    local data = getPlayerData(player)
    if data.missions[missionId] then
        return false, "La misión ya fue iniciada"
    end

    data.missions[missionId] = {
        objectives = copyObjectives(objectiveIds),
        completed = false,
    }
    player:SetAttribute("ActiveMission", missionId)

    return true
end

function MissionService.CompleteObjective(player, missionId, objectiveId)
    local data = progress[player]
    if not data then
        return false, "No hay progreso cargado"
    end

    local mission = data.missions[missionId]
    if not mission then
        return false, "Misión no iniciada"
    end

    if mission.completed then
        return false, "Misión ya completada"
    end

    if mission.objectives[objectiveId] == nil then
        return false, "Objetivo desconocido"
    end

    if mission.objectives[objectiveId] then
        return false, "Objetivo ya completado"
    end

    mission.objectives[objectiveId] = true
    local allCompleted = true

    for _, completed in pairs(mission.objectives) do
        if not completed then
            allCompleted = false
            break
        end
    end

    if allCompleted then
        mission.completed = true
        player:SetAttribute("ActiveMission", "")
        player:SetAttribute("LastCompletedMission", missionId)
    end

    return true, allCompleted
end

function MissionService.GetProgress(player, missionId)
    local data = progress[player]
    if not data then return nil end

    local mission = data.missions[missionId]
    if not mission then return nil end

    local total = 0
    local completed = 0
    for _, isCompleted in pairs(mission.objectives) do
        total += 1
        if isCompleted then
            completed += 1
        end
    end

    return {
        missionId = missionId,
        completed = completed,
        total = total,
        finished = mission.completed,
        objectives = table.clone(mission.objectives),
    }
end

function MissionService.RemovePlayer(player)
    progress[player] = nil
end

Players.PlayerRemoving:Connect(MissionService.RemovePlayer)

return MissionService
