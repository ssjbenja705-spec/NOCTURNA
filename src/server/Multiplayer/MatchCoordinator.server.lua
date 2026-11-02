local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MAX_PLAYERS = 4
local MIN_PLAYERS = 1

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

local actionRemote = getRemote("LobbyAction")
local updateRemote = getRemote("LobbyUpdate")
local startedRemote = getRemote("MatchStarted")

local ready = {}
local leaderUserId = nil
local matchActive = false
local matchNumber = 0

local function getPlayerCount()
    return #Players:GetPlayers()
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
        MatchActive = matchActive,
        MatchNumber = matchNumber,
    }
end

local function broadcast()
    updateRemote:FireAllClients(getLobbyData())
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
    if #players < MIN_PLAYERS then return false end

    for _, player in ipairs(players) do
        if ready[player.UserId] ~= true then
            return false
        end
    end

    return true
end

local function startMatch(player)
    if matchActive or not player or player.UserId ~= leaderUserId then return end
    if not allPlayersReady() then return end

    matchActive = true
    matchNumber += 1
    local participants = {}

    for _, member in ipairs(Players:GetPlayers()) do
        member:SetAttribute("InNocturnaMatch", true)
        member:SetAttribute("NocturnaMatchNumber", matchNumber)
        table.insert(participants, {
            UserId = member.UserId,
            Name = member.DisplayName,
        })
    end

    startedRemote:FireAllClients({
        MatchNumber = matchNumber,
        Participants = participants,
        MaxPlayers = MAX_PLAYERS,
    })
    broadcast()
    print("[NOCTURNA] Partida iniciada:", matchNumber)
end

actionRemote.OnServerEvent:Connect(function(player, action)
    if typeof(action) ~= "string" then return end

    if action == "Ready" then
        if matchActive or ready[player.UserId] == nil then return end
        ready[player.UserId] = not ready[player.UserId]
        broadcast()
    elseif action == "Start" then
        startMatch(player)
    elseif action == "RequestUpdate" then
        updateRemote:FireClient(player, getLobbyData())
    end
end)

Players.PlayerAdded:Connect(function(player)
    if getPlayerCount() > MAX_PLAYERS then
        player:Kick("La partida de NOCTURNA está completa.")
        return
    end

    if matchActive then
        player:Kick("La partida ya comenzó. Intenta entrar a otra sesión.")
        return
    end

    ready[player.UserId] = false
    assignLeader()
    task.defer(broadcast)
end)

Players.PlayerRemoving:Connect(function(player)
    ready[player.UserId] = nil
    assignLeader()
    task.defer(broadcast)
end)

for _, player in ipairs(Players:GetPlayers()) do
    ready[player.UserId] = false
end

assignLeader()
broadcast()
