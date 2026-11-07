-- Ascensores del lobby: entrar a uno vacío te hace anfitrión, los demás entran para
-- sumarse y salir del ascensor te saca del grupo. El anfitrión elige jugadores,
-- dificultad y capítulo y presiona EMPEZAR (o arranca solo al llenarse): las puertas
-- se cierran y el grupo viaja a un servidor propio. Sin viajes (Studio) la partida se
-- juega en este mismo servidor, como antes.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local LobbyConfig = require(Shared.Config.LobbyConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local AntiCheat = require(script.Parent.Parent.Security.AntiCheat)
local GameState = require(script.Parent.Parent.Core.GameState)
local LobbyService = require(script.Parent.Parent.Multiplayer.LobbyService)
local LobbyBuilder = require(script.Parent.Parent.World.LobbyBuilder)
local MatchServerService = require(script.Parent.MatchServerService)
local MatchTeleport = require(script.Parent.MatchTeleport)
local PartyLogic = require(script.Parent.PartyLogic)
local ServerMode = require(script.Parent.ServerMode)

local STATUS_COLORS = {
    Free = Color3.fromRGB(150, 196, 150),
    Open = Color3.fromRGB(214, 206, 186),
    Countdown = Color3.fromRGB(220, 120, 80),
    Closed = Color3.fromRGB(200, 60, 50),
}

local QueueService = {}
-- [index] = {Elevator, Party, EndsAt, LaunchDeadline, LastSecond}
local queues = {}
local memberOf = {}
local warned = {}
local rejoinOffers = {}
local disabled = false

local function notify(player, text)
    Remotes.FireClient("StoryNotice", player, text)
end

local function unlockedOf(player)
    local unlocked = player and player:GetAttribute("NocturnaUnlockedChapter")
    return type(unlocked) == "number" and unlocked or 1
end

local function rootPosition(player)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        return nil
    end
    return root.Position
end

local function membersOf(queue)
    local result = {}
    for _, userId in ipairs(queue.Party.Members) do
        local player = Players:GetPlayerByUserId(userId)
        if player then
            table.insert(result, player)
        end
    end
    return result
end

local function hostOf(queue)
    return queue.Party.Host and Players:GetPlayerByUserId(queue.Party.Host)
end

local function secondsLeft(queue)
    return math.max(0, math.ceil((queue.EndsAt or 0) - os.clock()))
end

-- Lo que ve cada miembro en su panel. Todo sale del servidor.
local function partyView(queue, player)
    local party = queue.Party
    local members = {}
    for _, member in ipairs(membersOf(queue)) do
        table.insert(members, {
            UserId = member.UserId,
            Name = member.DisplayName,
            IsHost = member.UserId == party.Host,
        })
    end
    local host = hostOf(queue)

    return {
        Kind = "Party",
        Elevator = queue.Elevator.Index,
        IsHost = player.UserId == party.Host,
        HostName = host and host.DisplayName or "",
        Members = members,
        MaxPlayers = party.MaxPlayers,
        Chapter = party.Chapter,
        ChapterName = GameConfig.Chapters[party.Chapter],
        HighestUnlocked = unlockedOf(host),
        Difficulty = party.Difficulty,
        State = party.State,
        Countdown = party.State == "Countdown" and secondsLeft(queue) or nil,
    }
end

local function viewFor(player)
    if ServerMode.IsMatchServer() then
        return MatchServerService.View(player)
    end
    local queue = memberOf[player]
    if queue then
        return partyView(queue, player)
    end
    if rejoinOffers[player] then
        return rejoinOffers[player]
    end
    return {Kind = "None"}
end

local function send(player)
    Remotes.FireClient("QueueUpdate", player, viewFor(player))
end

local function refreshSign(queue)
    local party = queue.Party
    local elevator = queue.Elevator
    if disabled then
        LobbyBuilder.SetSign(elevator, "FUERA DE SERVICIO", "", STATUS_COLORS.Closed)
        return
    end

    local slots = {}
    for _, member in ipairs(membersOf(queue)) do
        table.insert(slots, member.DisplayName)
    end
    for _ = #slots + 1, party.MaxPlayers do
        table.insert(slots, "libre")
    end
    local names = table.concat(slots, " · ")

    if PartyLogic.IsEmpty(party) then
        LobbyBuilder.SetSign(elevator, "LIBRE · entrá para armar grupo", "", STATUS_COLORS.Free)
    elseif party.State == "Countdown" then
        LobbyBuilder.SetSign(elevator, string.format("SALE EN %d", secondsLeft(queue)), names, STATUS_COLORS.Countdown)
    elseif party.State == "Launching" then
        LobbyBuilder.SetSign(elevator, "EN VIAJE", names, STATUS_COLORS.Closed)
    else
        local difficulty = GameConfig.Difficulties[party.Difficulty]
        LobbyBuilder.SetSign(elevator, string.format(
            "%d/%d · %s · CAP. %d",
            #party.Members, party.MaxPlayers, string.upper(difficulty.DisplayName), party.Chapter
        ), names, STATUS_COLORS.Open)
    end
end

local function update(queue)
    refreshSign(queue)
    for _, member in ipairs(membersOf(queue)) do
        send(member)
    end
end

local function moveOut(player, queue)
    local character = player.Character
    if character then
        AntiCheat.Grace(player, 2)
        character:PivotTo(queue.Elevator.Exit)
    end
end

local function reopen(queue)
    queue.EndsAt = nil
    queue.LaunchDeadline = nil
    queue.Party.State = "Open"
    LobbyBuilder.SetDoors(queue.Elevator, true)
    update(queue)
end

local function resetQueue(queue)
    for _, member in ipairs(membersOf(queue)) do
        memberOf[member] = nil
        send(member)
    end
    for player, current in pairs(memberOf) do
        if current == queue then
            memberOf[player] = nil
        end
    end
    PartyLogic.Reset(queue.Party)
    queue.EndsAt = nil
    queue.LaunchDeadline = nil
    LobbyBuilder.SetDoors(queue.Elevator, not disabled)
    refreshSign(queue)
end

local function beginCountdown(queue)
    local party = queue.Party
    if party.State ~= "Open" or PartyLogic.IsEmpty(party) then
        return
    end
    party.State = "Countdown"
    queue.EndsAt = os.clock() + LobbyConfig.Countdown
    queue.LastSecond = secondsLeft(queue)
    LobbyBuilder.SetDoors(queue.Elevator, false)

    -- Quien quedó adentro sin lugar en el grupo baja antes de que cierren las puertas.
    for _, player in ipairs(Players:GetPlayers()) do
        if memberOf[player] ~= queue and LobbyBuilder.ElevatorAt(rootPosition(player)) == queue.Elevator then
            moveOut(player, queue)
            notify(player, "Este ascensor ya sale. Probá con otro.")
        end
    end
    update(queue)
end

local function leave(player, queue, silent)
    local party = queue.Party
    local previousHost = party.Host
    memberOf[player] = nil
    if not PartyLogic.Leave(party, player.UserId) then
        return
    end

    if player.Parent == Players and not silent then
        send(player)
    end

    if PartyLogic.IsEmpty(party) then
        resetQueue(queue)
        return
    end

    if party.Host ~= previousHost then
        local host = hostOf(queue)
        PartyLogic.ClampChapter(party, unlockedOf(host))
        if host then
            notify(host, "Ahora sos el anfitrión del ascensor.")
        end
    end
    update(queue)
end

local function join(player, queue)
    local party = queue.Party
    local wasEmpty = PartyLogic.IsEmpty(party)
    local success, reason = PartyLogic.Join(party, player.UserId)
    if not success then
        if warned[player] ~= queue then
            warned[player] = queue
            notify(player, reason == "Full" and "Este ascensor está lleno." or "Este ascensor ya está saliendo.")
        end
        return
    end

    memberOf[player] = queue
    warned[player] = nil
    if wasEmpty then
        -- El anfitrión arranca desde el último capítulo que jugó.
        local current = player:GetAttribute("NocturnaCurrentChapter")
        party.Chapter = math.clamp(type(current) == "number" and current or 1, 1, unlockedOf(player))
    end

    if not wasEmpty and PartyLogic.IsFull(party) then
        beginCountdown(queue)
    else
        update(queue)
    end
end

local function startLocal(queue)
    local party = queue.Party
    local chapter, difficulty = party.Chapter, party.Difficulty
    for _, other in ipairs(queues) do
        resetQueue(other)
    end
    LobbyService.RequestMatch(chapter, difficulty)
end

local function launch(queue)
    local party = queue.Party
    local host = hostOf(queue)
    PartyLogic.ClampChapter(party, unlockedOf(host))

    if not ServerMode.CanTeleport() then
        startLocal(queue)
        return
    end

    party.State = "Launching"
    queue.LaunchDeadline = os.clock() + LobbyConfig.LaunchTimeout
    update(queue)

    local travellers = membersOf(queue)
    local data = PartyLogic.TeleportData(party)
    task.spawn(function()
        local success = MatchTeleport.LaunchParty(travellers, data)
        if not success and party.State == "Launching" then
            for _, member in ipairs(membersOf(queue)) do
                notify(member, "No se pudo abrir el servidor de la partida. Probá de nuevo.")
            end
            reopen(queue)
        end
    end)
end

local function tickQueue(queue)
    local party = queue.Party
    if party.State == "Countdown" then
        if os.clock() >= queue.EndsAt then
            launch(queue)
            return
        end
        local seconds = secondsLeft(queue)
        if seconds ~= queue.LastSecond then
            queue.LastSecond = seconds
            update(queue)
        end
    elseif party.State == "Launching" and queue.LaunchDeadline and os.clock() >= queue.LaunchDeadline then
        -- Quien sigue acá no pudo viajar: el ascensor vuelve a abrir para ellos.
        for _, member in ipairs(membersOf(queue)) do
            notify(member, "El viaje no se completó. Podés volver a intentarlo.")
        end
        reopen(queue)
    end
end

local function setDisabled(value)
    if disabled == value then
        return
    end
    disabled = value
    for _, queue in ipairs(queues) do
        resetQueue(queue)
    end
end

local function tick()
    -- Con una partida en curso en este servidor los ascensores no funcionan.
    setDisabled(GameState.Phase ~= "Lobby")
    if disabled then
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        local position = rootPosition(player)
        if position then
            local elevator = LobbyBuilder.ElevatorAt(position)
            local current = memberOf[player]
            if current and current.Elevator ~= elevator and current.Party.State ~= "Launching" then
                leave(player, current)
            end
            if elevator then
                local queue = queues[elevator.Index]
                if memberOf[player] ~= queue then
                    join(player, queue)
                end
            else
                warned[player] = nil
            end
        end
    end

    for _, queue in ipairs(queues) do
        tickQueue(queue)
    end
end

local function handleAction(player, action, argument)
    if typeof(action) ~= "string" then
        return
    end

    if action == "Sync" then
        send(player)
        return
    elseif action == "ReturnToLobby" then
        MatchServerService.RequestReturn(player)
        return
    elseif action == "Rejoin" then
        if rejoinOffers[player] and ServerMode.IsLobbyServer() then
            rejoinOffers[player] = nil
            send(player)
            task.spawn(MatchTeleport.Rejoin, player)
        end
        return
    elseif action == "DismissRejoin" then
        if rejoinOffers[player] then
            rejoinOffers[player] = nil
            send(player)
            task.spawn(MatchTeleport.Forget, player.UserId)
        end
        return
    end

    local queue = memberOf[player]
    if not queue or disabled then
        return
    end
    local party = queue.Party

    if action == "Leave" then
        if party.State ~= "Launching" then
            leave(player, queue)
            moveOut(player, queue)
        end
    elseif action == "Start" then
        if party.Host == player.UserId then
            beginCountdown(queue)
        end
    elseif action == "Cancel" then
        if party.Host == player.UserId and party.State == "Countdown" then
            reopen(queue)
        end
    elseif action == "SetMaxPlayers" then
        if PartyLogic.SetMaxPlayers(party, player.UserId, argument) then
            update(queue)
        end
    elseif action == "SetDifficulty" then
        if PartyLogic.SetDifficulty(party, player.UserId, argument) then
            update(queue)
        end
    elseif action == "SetChapter" then
        if PartyLogic.SetChapter(party, player.UserId, argument, unlockedOf(player)) then
            update(queue)
        end
    end
end

-- Quien se desconectó en medio de una partida puede volver a ella desde el lobby.
local function offerRejoin(player)
    local success, joinData = pcall(function()
        return player:GetJoinData()
    end)
    local teleportData = success and type(joinData) == "table" and joinData.TeleportData
    if type(teleportData) == "table" and teleportData.ReturnFromMatch == true then
        return
    end

    local record = MatchTeleport.LookupActive(player.UserId)
    if not record or player.Parent ~= Players then
        return
    end
    rejoinOffers[player] = {
        Kind = "Rejoin",
        Chapter = record.Settings.Chapter,
        ChapterName = GameConfig.Chapters[record.Settings.Chapter],
        Difficulty = record.Settings.Difficulty,
    }
    if not memberOf[player] then
        send(player)
    end
end

function QueueService.PartyOf(player)
    local queue = memberOf[player]
    return queue and queue.Party or nil
end

function QueueService.Queues()
    return queues
end

function QueueService.Start()
    Remotes.OnServer("QueueAction", 6, handleAction)
    if ServerMode.IsMatchServer() then
        return
    end

    LobbyBuilder.Build()
    for index, elevator in ipairs(LobbyBuilder.Elevators()) do
        queues[index] = {Elevator = elevator, Party = PartyLogic.new(index)}
        refreshSign(queues[index])
    end

    Players.PlayerAdded:Connect(function(player)
        if ServerMode.IsLobbyServer() then
            task.spawn(offerRejoin, player)
        end
    end)
    Players.PlayerRemoving:Connect(function(player)
        local queue = memberOf[player]
        if queue then
            leave(player, queue, true)
        end
        warned[player] = nil
        rejoinOffers[player] = nil
    end)

    local elapsed = 0
    RunService.Heartbeat:Connect(function(deltaTime)
        elapsed += deltaTime
        if elapsed >= LobbyConfig.ZoneCheckInterval then
            elapsed = 0
            tick()
        end
    end)
end

return QueueService
