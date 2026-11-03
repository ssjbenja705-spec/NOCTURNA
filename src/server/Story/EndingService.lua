-- Decisión final del grupo. El final verdadero sólo aparece si alguien reunió
-- todos los documentos a lo largo de la campaña.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local ChapterConfig = require(Shared.Config.ChapterConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local ProgressionService = require(script.Parent.Parent.Data.ProgressionService)

local CARD_TIME = 4.5

local EndingService = {}
local votes = {}
local options = {}
local voting = false

local function availableEndings()
    local list = {"Release", "Rescue"}
    for _, player in ipairs(Players:GetPlayers()) do
        if ProgressionService.CountDocuments(player) >= GameConfig.Match.MaxDocuments then
            table.insert(list, "Remember")
            break
        end
    end
    return list
end

local function tally()
    local counts = {}
    for _, endingId in pairs(votes) do
        counts[endingId] = (counts[endingId] or 0) + 1
    end
    return counts
end

-- Gana la mayoría; en caso de empate gana el final mejor habilitado, y sin votos
-- el primero de la lista.
function EndingService.Resolve(available, voteCounts)
    local best, bestVotes = available[1], 0
    for _, endingId in ipairs(available) do
        local count = voteCounts[endingId] or 0
        if count > 0 and count >= bestVotes then
            best, bestVotes = endingId, count
        end
    end
    return best
end

local function allVoted()
    for _, player in ipairs(Players:GetPlayers()) do
        if votes[player] == nil then
            return false
        end
    end
    return #Players:GetPlayers() > 0
end

function EndingService.RunVote()
    table.clear(votes)
    options = availableEndings()
    voting = true

    local payload = {}
    for _, endingId in ipairs(options) do
        local ending = ChapterConfig.Endings[endingId]
        table.insert(payload, {
            Id = endingId,
            Option = ending.Option,
            Description = ending.Description,
        })
    end

    local duration = GameConfig.Match.EndingVoteDuration
    Remotes.FireAll("EndingPrompt", {Options = payload, Duration = duration})

    local deadline = os.clock() + duration
    while os.clock() < deadline and not allVoted() do
        task.wait(0.25)
    end

    voting = false
    return EndingService.Resolve(options, tally())
end

function EndingService.Play(endingId)
    local ending = ChapterConfig.Endings[endingId]
    local duration = #ending.Lines * CARD_TIME + 8

    Remotes.FireAll("Cutscene", {
        Kind = "Ending",
        EndingId = endingId,
        Title = ending.Title,
        Lines = ending.Lines,
        LineTime = CARD_TIME,
        Duration = duration,
    })
    task.wait(duration)

    for _, player in ipairs(Players:GetPlayers()) do
        ProgressionService.AddEnding(player, endingId)
    end
end

function EndingService.Start()
    Remotes.OnServer("EndingVote", 4, function(player, endingId)
        if voting and typeof(endingId) == "string" and table.find(options, endingId) then
            votes[player] = endingId
            Remotes.FireAll("EndingVotes", tally())
        end
    end)

    Players.PlayerRemoving:Connect(function(player)
        votes[player] = nil
    end)
end

return EndingService
