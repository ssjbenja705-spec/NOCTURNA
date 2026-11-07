-- Sala de hasta cuatro jugadores: listos, líder, capítulo y dificultad.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local ProgressionService = require(script.Parent.Parent.Data.ProgressionService)

local MAX_PLAYERS = GameConfig.MaxPlayers
local MIN_PLAYERS = GameConfig.MinPlayers

local LobbyService = {}
local ready = {}
local leaderUserId = nil
local selectedChapter = 1
local selectedDifficulty = GameConfig.DefaultDifficulty
local matchNumber = 0

local function highestUnlocked()
    local highest = 1
    for _, player in ipairs(Players:GetPlayers()) do
        local unlocked = player:GetAttribute("NocturnaUnlockedChapter")
        if type(unlocked) == "number" then
            highest = math.max(highest, unlocked)
        end
    end
    return highest
end

local function getLobbyData()
    local members = {}

    for _, player in ipairs(Players:GetPlayers()) do
        table.insert(members, {
            UserId = player.UserId,
            Name = player.DisplayName,
            Ready = ready[player.UserId] == true,
            IsLeader = player.UserId == leaderUserId,
        })
    end

    return {
        Players = members,
        PlayerCount = #members,
        MaxPlayers = MAX_PLAYERS,
        LeaderUserId = leaderUserId,
        MatchActive = GameState.Phase ~= "Lobby",
        MatchNumber = matchNumber,
        Chapter = selectedChapter,
        HighestUnlocked = highestUnlocked(),
        Difficulty = selectedDifficulty,
    }
end

function LobbyService.Broadcast()
    Remotes.FireAll("LobbyUpdate", getLobbyData())
end

local function assignLeader()
    local players = Players:GetPlayers()

    if #players == 0 then
        leaderUserId = nil
        return
    end

    for _, player in ipairs(players) do
        if player.UserId == leaderUserId then
            return
        end
    end

    leaderUserId = players[1].UserId
end

local function allPlayersReady()
    local players = Players:GetPlayers()
    if #players < MIN_PLAYERS then
        return false
    end

    for _, player in ipairs(players) do
        if ready[player.UserId] ~= true then
            return false
        end
    end

    return true
end

function LobbyService.IsLeader(player)
    return player.UserId == leaderUserId
end

function LobbyService.ResetReady()
    for userId in pairs(ready) do
        ready[userId] = false
    end
    LobbyService.Broadcast()
end

local function startMatch(player)
    if GameState.Phase ~= "Lobby" or player.UserId ~= leaderUserId then
        return
    end
    if not allPlayersReady() then
        Remotes.FireClient("StoryNotice", player, "Todos los jugadores tienen que estar listos.")
        return
    end

    matchNumber += 1
    EventBus.Emit("MatchRequested", math.min(selectedChapter, highestUnlocked()), selectedDifficulty)
end

local function handleAction(player, action, argument)
    if typeof(action) ~= "string" then
        return
    end

    if action == "RequestUpdate" then
        -- Sólo a quien lo pidió: pedirlo muchas veces no satura a los demás.
        Remotes.FireClient("LobbyUpdate", player, getLobbyData())
        GameState.Broadcast(player)
        ProgressionService.Push(player)
    elseif action == "Ready" then
        if GameState.Phase == "Lobby" and ready[player.UserId] ~= nil then
            ready[player.UserId] = not ready[player.UserId]
            LobbyService.Broadcast()
        end
    elseif action == "Start" then
        startMatch(player)
    elseif action == "SetChapter" then
        if player.UserId == leaderUserId and GameState.Phase == "Lobby"
            and typeof(argument) == "number" and argument % 1 == 0
            and argument >= 1 and argument <= highestUnlocked() then
            selectedChapter = argument
            LobbyService.Broadcast()
        end
    elseif action == "SetDifficulty" then
        if player.UserId == leaderUserId and GameState.Phase == "Lobby"
            and typeof(argument) == "string" and GameConfig.Difficulties[argument] then
            selectedDifficulty = argument
            LobbyService.Broadcast()
        end
    elseif action == "Retry" or action == "ToLobby" then
        if player.UserId == leaderUserId and GameState.Phase == "Failed" then
            EventBus.Emit("FailureDecision", action)
        end
    end
end

function LobbyService.Start()
    Remotes.OnServer("LobbyAction", 8, handleAction)

    Players.PlayerAdded:Connect(function(player)
        if #Players:GetPlayers() > MAX_PLAYERS then
            player:Kick("La partida de NOCTURNA está completa.")
            return
        end

        ready[player.UserId] = false
        assignLeader()
        task.defer(LobbyService.Broadcast)
    end)

    Players.PlayerRemoving:Connect(function(player)
        ready[player.UserId] = nil
        task.defer(function()
            assignLeader()
            LobbyService.Broadcast()
        end)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        ready[player.UserId] = false
    end

    assignLeader()
    LobbyService.Broadcast()
end

return LobbyService
