-- Envía eventos a Roblox Analytics y lleva contadores por sesión de servidor.
-- Ningún fallo de analítica puede afectar a la partida.
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")

local Analytics = {}
local sessionStarts = {}
local counters = {}

local function count(name)
    counters[name] = (counters[name] or 0) + 1
end

local function logEvent(player, name, value, fields)
    count(name)
    pcall(function()
        AnalyticsService:LogCustomEvent(player, name, value or 1, fields)
    end)
end

local function logAll(name, value, fields)
    for _, player in ipairs(Players:GetPlayers()) do
        logEvent(player, name, value, fields)
    end
end

function Analytics.ChapterStarted(chapter)
    logAll("ChapterStarted", chapter)
end

function Analytics.ChapterCompleted(chapter)
    logAll("ChapterCompleted", chapter)
end

function Analytics.ChapterFailed(chapter)
    logAll("ChapterFailed", chapter)
end

function Analytics.ObjectiveCompleted(chapter, objectiveId)
    count("ObjectiveCompleted")
    logAll("Objective_" .. objectiveId, chapter)
end

function Analytics.PlayerDied(player, chapter)
    logEvent(player, "PlayerDied", chapter)
end

function Analytics.MonsterEncountered(player, kind)
    logEvent(player, "Encounter_" .. kind)
end

function Analytics.EndingReached(endingId)
    logAll("Ending_" .. endingId)
end

function Analytics.GetCounters()
    return table.clone(counters)
end

function Analytics.Start()
    Players.PlayerAdded:Connect(function(player)
        sessionStarts[player] = os.time()
        count("PlayerJoined")
    end)

    Players.PlayerRemoving:Connect(function(player)
        local started = sessionStarts[player]
        if started then
            logEvent(player, "SessionLength", os.time() - started)
        end
        sessionStarts[player] = nil
    end)
end

return Analytics
