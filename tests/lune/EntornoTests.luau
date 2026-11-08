--!nocheck
-- Pruebas del área de entorno: materiales y paredes dañadas, charcos, luz por
-- capítulo, puertas temáticas, entrada a los servidores y el pelo de Alma.
-- run.luau las carga con sus ayudantes en `ctx`.
return function(ctx)
    local Engine = ctx.Engine
    local T = ctx.T
    local roblox = Engine.Roblox
    local Vector3 = roblox.Vector3
    local fire = ctx.fire
    local gameState = ctx.gameState
    local waitForPhase = ctx.waitForPhase
    local bootServer = ctx.bootServer
    local startMatch = ctx.startMatch
    local ChapterConfig = ctx.ChapterConfig
    local ThemeConfig = ctx.ThemeConfig

    local function queueService()
        return Engine.RequireServer("Lobby.QueueService")
    end

    local function lobbyBuilder()
        return Engine.RequireServer("World.LobbyBuilder")
    end

    local function walkTo(player, position)
        player.Character:FindFirstChild("HumanoidRootPart").CFrame = roblox.CFrame.new(position)
    end

    local function enterElevator(player, index)
        walkTo(player, lobbyBuilder().Elevators()[index].Center)
    end

    local function notices(player)
        local result = {}
        for _, entry in ipairs(Engine.Sent) do
            if entry.Name == "StoryNotice" and (entry.Player == player or entry.Player == nil) then
                table.insert(result, tostring(entry.Args[1]))
            end
        end
        return result
    end

    local function noticed(player, text)
        for _, message in ipairs(notices(player)) do
            if string.find(message, text, 1, true) then
                return true
            end
        end
        return false
    end

    local function queueView(player)
        local sent = Engine.LastSent("QueueUpdate", player)
        return sent and sent[1]
    end

    T.Suite("Entorno: entrada a los servidores")

    T.Test("Entorno: el grupo que viaja es el que de verdad sale, no el que se anotó", function()
        local players = bootServer(2, {PlaceId = 777, Stores = {}, TeleportStays = true})
        local MatchTeleport = Engine.RequireServer("Lobby.MatchTeleport")
        local data = {Chapter = 1, Difficulty = "Normal", MaxPlayers = 3, Party = {9999, players[1].UserId, players[2].UserId}, Host = 9999}
        T.True(MatchTeleport.LaunchParty(players, data), "sale")
        local trip = Engine.Teleports[1]
        T.Equal(#trip.Data.Party, 2, "sin el que ya no estaba")
        T.Equal(trip.Data.Host, players[1].UserId, "el anfitrión pasa a alguien que viaja")
        T.True(table.find(trip.Data.Party, 9999) == nil, "nadie espera a un ausente")
        T.Equal(#data.Party, 3, "los datos originales no se tocan")
        T.NoEngineErrors(Engine)
    end)

    T.Test("Entorno: un viaje que no se completa no deja al jugador trabado como 'viajando'", function()
        local players = bootServer(1, {PlaceId = 777, Stores = {}, TeleportStays = true})
        local Queue = queueService()
        local MatchTeleport = Engine.RequireServer("Lobby.MatchTeleport")
        enterElevator(players[1], 1)
        Engine.Run(0.5)
        fire("QueueAction", players[1], "Start")
        T.True(Engine.RunUntil(function()
            return #Engine.Teleports > 0
        end, 15), "viaja")
        T.True(MatchTeleport.IsTravelling(players[1]), "viajando")
        T.True(Engine.RunUntil(function()
            local party = Queue.PartyOf(players[1])
            return party ~= nil and party.State == "Open"
        end, 40), "el ascensor vuelve a abrir")
        T.False(MatchTeleport.IsTravelling(players[1]), "ya no figura viajando")

        -- Puede salir y sumarse a otro ascensor.
        walkTo(players[1], lobbyBuilder().SpawnCFrame(1).Position)
        Engine.Run(0.5)
        enterElevator(players[1], 2)
        Engine.Run(0.5)
        local view = queueView(players[1])
        T.True(view ~= nil and view.Kind == "Party" and view.Elevator == 2, "se suma a otro ascensor")
        T.NoEngineErrors(Engine)
    end)

    T.Test("Entorno: una falla definitiva avisa enseguida y un viaje en curso no se duplica", function()
        local players = bootServer(2, {PlaceId = 777, Stores = {}, TeleportStays = true})
        local MatchTeleport = Engine.RequireServer("Lobby.MatchTeleport")
        local teleportService = Engine.Services.TeleportService
        local data = {Chapter = 1, Difficulty = "Normal", MaxPlayers = 2, Party = {players[1].UserId, players[2].UserId}, Host = players[1].UserId}
        T.True(MatchTeleport.LaunchParty(players, data), "sale")

        teleportService.TeleportInitFailed:Fire(players[1], roblox.Enum.TeleportResult.IsTeleporting, "ya viaja", 777, nil)
        Engine.Run(6)
        T.Equal(#Engine.Teleports, 1, "no repite un viaje que ya está en marcha")
        T.True(MatchTeleport.IsTravelling(players[1]), "sigue viajando")

        teleportService.TeleportInitFailed:Fire(players[2], roblox.Enum.TeleportResult.Unauthorized, "no", 777, nil)
        Engine.Run(6)
        T.Equal(#Engine.Teleports, 1, "sin reintentos inútiles")
        T.True(noticed(players[2], "no autorizó"), "explica el motivo")
        T.False(MatchTeleport.IsTravelling(players[2]), "puede volver a intentar")

        teleportService.TeleportInitFailed:Fire(players[1], roblox.Enum.TeleportResult.Flooded, "lleno", 777, nil)
        Engine.Run(1)
        T.True(noticed(players[1], "Reintentando (2/3)"), "reintenta y cuenta los intentos")
        T.NoEngineErrors(Engine)
    end)

    T.Test("Entorno: si el grupo no llega completo, la partida empieza igual y lo explica", function()
        Engine.Reset({PlaceId = 777, PrivateServerId = "reserved-5", PrivateServerOwnerId = 0, Stores = {}})
        Engine.StartServer()
        Engine.Run(0.5)
        local join = {SourcePlaceId = 777, TeleportData = {Chapter = 1, Difficulty = "Normal", MaxPlayers = 2, Party = {2001, 2002}, Host = 2001}}
        local first = Engine.AddPlayer("Jugador1", 2001, join)
        local wait = Engine.RequireShared("Config.LobbyConfig").Teleport.PartyWait
        Engine.Run(wait - 5)
        T.Equal(queueView(first).Kind, "Waiting", "espera")
        T.True(waitForPhase("Loading", 30), "arranca sin el que falta")
        T.True(noticed(first, "No llegaron todos (1 de 2)"), "y avisa por qué")
        T.NoEngineErrors(Engine)
    end)

    T.Test("Entorno: si se caen todos, quien vuelve retoma la partida en vez de rebotar", function()
        local stores = {}
        Engine.Reset({PlaceId = 777, PrivateServerId = "reserved-8", PrivateServerOwnerId = 0, Stores = stores})
        Engine.StartServer()
        Engine.Run(0.5)
        local data = {Chapter = 1, Difficulty = "Normal", MaxPlayers = 1, Party = {2001}, Host = 2001}
        local first = Engine.AddPlayer("Jugador1", 2001, {SourcePlaceId = 777, TeleportData = data})
        T.True(waitForPhase("Playing", 90), "partida")

        Engine.RemovePlayer(first)
        Engine.Run(2)
        local MatchServer = Engine.RequireServer("Lobby.MatchServerService")
        T.Equal(MatchServer.Stage(), "Waiting", "el servidor vuelve a esperar")
        T.Equal(#Engine.Teleports, 0, "no manda a nadie a la recepción")

        local rejoin = table.clone(data)
        rejoin.Rejoin = true
        local back = Engine.AddPlayer("Jugador1", 2001, {SourcePlaceId = 777, TeleportData = rejoin})
        T.True(waitForPhase("Loading", 20), "la partida vuelve a empezar")
        T.False(noticed(back, "ya terminó"), "sin rebotarlo")
        T.Equal(#Engine.Teleports, 0, "sigue en el servidor de la partida")
        T.NoEngineErrors(Engine)
    end)

    T.Test("Entorno: quien llega a una partida terminada vuelve a la recepción con aviso", function()
        Engine.Reset({PlaceId = 777, PrivateServerId = "reserved-6", PrivateServerOwnerId = 0, Stores = {}, TeleportStays = true})
        Engine.StartServer()
        Engine.Run(0.5)
        local join = {SourcePlaceId = 777, TeleportData = {Chapter = 1, Difficulty = "Normal", MaxPlayers = 2, Party = {2001, 2002}, Host = 2001}}
        Engine.AddPlayer("Jugador1", 2001, join)
        Engine.AddPlayer("Jugador2", 2002, join)
        T.True(waitForPhase("Playing", 90), "partida")
        Engine.RequireServer("Multiplayer.MatchService").ReturnToLobby()
        Engine.Run(1)
        local late = Engine.AddPlayer("Jugador3", 2003, join)
        Engine.Run(1)
        T.True(noticed(late, "ya terminó"), "avisa")
        local trip = Engine.Teleports[#Engine.Teleports]
        T.True(trip ~= nil and trip.Players[1] == late and trip.AccessCode == "", "lo manda a un lobby público")
        T.NoEngineErrors(Engine)
    end)

    return {
        Notices = notices,
        Noticed = noticed,
        WalkTo = walkTo,
        ChapterConfig = ChapterConfig,
        ThemeConfig = ThemeConfig,
        StartMatch = startMatch,
        Vector3 = Vector3,
    }
end
