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

    T.Suite("Entorno: materiales, luz, puertas y Alma")

    local function loadChapter(index, seed)
        local WorldService = Engine.RequireServer("World.WorldService")
        local plan = WorldService.LoadChapter(index, seed or 101)
        return plan, Engine.Workspace:FindFirstChild("NOCTURNA_MAP"), WorldService
    end

    local function themeOf(index)
        return ThemeConfig[ChapterConfig[index].Theme]
    end

    T.Test("Entorno: paredes dañadas y charcos en cada capítulo, livianos y dentro del presupuesto", function()
        bootServer(1)
        Engine.Run(0.5)
        for index = 1, 5 do
            local _, map, WorldService = loadChapter(index, 101 + index)
            local total = ctx.countBaseParts(map)
            T.True(total <= WorldService.PartBudget, string.format("capítulo %d dentro del presupuesto: %d", index, total))

            local damage, gouges, wedges, puddles = 0, 0, 0, 0
            for _, part in ipairs(map:FindFirstChild("Decor"):GetDescendants()) do
                if part:IsA("BasePart") and part:FindFirstAncestor("Weathering") then
                    damage += 1
                    T.False(part.CanCollide or part.CanQuery or part.CanTouch, "el desgaste no choca ni tapa la vista: " .. part.Name)
                    T.True(part.Anchored, "anclado: " .. part.Name)
                    if part.Name == "ClawGouge" then
                        gouges += 1
                        if part:IsA("WedgePart") then
                            wedges += 1
                        end
                    elseif part.Name == "PuddleWater" then
                        puddles += 1
                        T.True(part.Reflectance >= 0.2 and part.Transparency < 0.5, "agua que refleja la luz")
                        T.True(Engine.CollectionService:HasTag(part, "NocturnaPuddle"), "el cliente la encuentra para hacerla temblar")
                    end
                end
            end
            T.True(damage >= 40, string.format("capítulo %d con paredes gastadas (%d piezas)", index, damage))
            T.True(gouges > 0 and wedges == gouges, string.format("capítulo %d: zarpazos tallados en cuña (%d)", index, gouges))
            if (themeOf(index).Wear.Puddles or 0) >= 0.3 then
                T.True(puddles > 0, "capítulo " .. index .. " con charcos")
            end
        end
        T.NoEngineErrors(Engine)
    end)

    T.Test("Entorno: cada sala tiene su luz; la de inicio siempre prendida y las rotas no cuentan como luz", function()
        bootServer(1)
        Engine.Run(0.5)
        local states = {}
        for index = 1, 5 do
            local plan, map, WorldService = loadChapter(index, 300 + index)
            WorldService.SetPower(true)
            local kinds = {}
            for _, part in ipairs(map:GetDescendants()) do
                local state = part:GetAttribute("LightState")
                if state then
                    kinds[state] = true
                    states[state] = (states[state] or 0) + 1
                    local tagged = Engine.CollectionService:HasTag(part, "NocturnaLight")
                    local light = part:FindFirstChildOfClass("PointLight")
                    if state == "Broken" then
                        T.False(tagged, "lámpara rota sin etiqueta de luz")
                        T.True(light == nil, "lámpara rota sin luz")
                    else
                        T.True(tagged and light ~= nil, "lámpara con luz")
                        T.Equal(light.Brightness, part:GetAttribute("BaseBrightness"), "brillo propio de la sala")
                    end
                    if part:GetAttribute("Cell") == plan.Layout.Start then
                        T.Equal(state, "Normal", "la sala de inicio tiene luz")
                    end
                end
            end
            local count = 0
            for _ in pairs(kinds) do
                count += 1
            end
            T.True(count >= 3, "capítulo " .. index .. " sin salas iluminadas iguales")

            -- Sin energía todas bajan, pero una tenue sigue más oscura que una normal.
            WorldService.SetPower(false)
            for _, fixture in ipairs(Engine.CollectionService:GetTagged("NocturnaLight")) do
                local light = fixture:FindFirstChildOfClass("PointLight")
                T.True(light.Brightness < fixture:GetAttribute("BaseBrightness"), "luz de emergencia más débil")
                T.Equal(light.Color, themeOf(index).EmergencyLight, "color de emergencia")
            end
            WorldService.SetPower(true)
        end
        T.True((states.Dim or 0) > 0 and (states.Broken or 0) > 0 and (states.Flicker or 0) > 0, "hay salas tenues, rotas y titilantes")
        T.NoEngineErrors(Engine)
    end)

    T.Test("Entorno: la identidad de cada capítulo (luz, desgaste, puertas y texturas) es propia", function()
        local seen = {}
        for index = 1, 5 do
            local theme = themeOf(index)
            T.True(type(theme.Mood) == "table" and type(theme.Wear) == "table", "Mood y Wear en el capítulo " .. index)
            T.True(type(theme.Surfaces) == "table" and type(theme.Surfaces.Wall) == "string", "gancho de textura de pared")
            T.True(not seen[theme.DoorStyle], "puerta propia en el capítulo " .. index)
            seen[theme.DoorStyle] = true
            T.True(not seen["peel" .. theme.Wear.Peel], "desgaste propio en el capítulo " .. index)
            seen["peel" .. theme.Wear.Peel] = true
        end
        local readme = ctx.fs.readFile("assets/textures/README.md")
        for index = 1, 5 do
            for _, name in pairs(themeOf(index).Surfaces) do
                T.True(string.find(readme, name, 1, true) ~= nil, "el README lista " .. name)
            end
        end
    end)

    T.Test("Entorno: con un MaterialVariant en MaterialService las paredes lo usan solas", function()
        bootServer(1)
        Engine.Run(0.5)
        local variant = Engine.New("MaterialVariant", "NocturnaTunnelBrick")
        variant.BaseMaterial = roblox.Enum.Material.Brick
        variant.Parent = Engine.Services.MaterialService
        local _, map = loadChapter(1, 77)
        local walls, using = 0, 0
        for _, part in ipairs(map:FindFirstChild("Sectors"):GetDescendants()) do
            if part.Name == "Wall" then
                walls += 1
                if part.MaterialVariant == "NocturnaTunnelBrick" then
                    using += 1
                end
            end
        end
        T.True(walls > 0 and using == walls, string.format("paredes con la textura PBR (%d de %d)", using, walls))
        local floor = map:FindFirstChild("Floor", true)
        T.Equal(floor.MaterialVariant, "", "lo que no tiene textura sigue con el material de Roblox")
        T.NoEngineErrors(Engine)
    end)

    T.Test("Entorno: texturas propias horneadas: cada PNG existe y TextureAssets las lista todas", function()
        local TextureAssets = Engine.RequireShared("Config.TextureAssets")
        local upload = ctx.fs.readFile("assets/textures/UPLOAD.md")
        local names = {}
        for name, entry in pairs(TextureAssets.Variants) do
            table.insert(names, name)
            T.True(roblox.Enum.Material[entry.BaseMaterial] ~= nil, name .. ": BaseMaterial válido")
            T.True(entry.StudsPerTile >= 1 and entry.StudsPerTile <= 32, name .. ": StudsPerTile")
            T.True(typeof(entry.Mean) == "Color3", name .. ": color medio")
            for _, map in ipairs(TextureAssets.Maps) do
                T.Equal(entry[map.Key], 0, name .. "." .. map.Key .. " empieza en 0")
                local file = name .. map.Suffix
                local path = "assets/textures/" .. name .. "/" .. file
                if ctx.fs.isFile(path) then
                    local data = ctx.fs.readFile(path)
                    T.Equal(string.sub(data, 2, 4), "PNG", file .. " es PNG")
                    -- IHDR: ancho y alto de 1024, 8 bits.
                    T.Equal(string.unpack(">I4", data, 17), 1024, file .. " ancho")
                    T.Equal(string.unpack(">I4", data, 21), 1024, file .. " alto")
                    T.Equal(string.byte(data, 25), 8, file .. " 8 bits")
                    T.True(string.find(upload, file, 1, true) ~= nil, "UPLOAD.md lista " .. file)
                    T.True(string.find(upload, name .. "." .. map.Key, 1, true) ~= nil, "UPLOAD.md dice dónde pegar " .. file)
                else
                    T.True(map.Key == "Metalness", "falta " .. path)
                end
            end
        end
        T.True(#names >= 16, "variantes: " .. #names)
        for index = 1, 5 do
            for key, name in pairs(themeOf(index).Surfaces) do
                T.True(TextureAssets.Variants[name] ~= nil, "capítulo " .. index .. " " .. key .. " usa una textura horneada: " .. name)
            end
            for _, key in pairs(TextureAssets.PropMaterials) do
                T.True(themeOf(index).Surfaces[key] ~= nil, "capítulo " .. index .. " tiene textura de utilería " .. key)
            end
        end
        T.True(ctx.fs.isFile("assets/textures/preview.png"), "hoja de muestra")
    end)

    T.Test("Entorno: con los números de las imágenes, las texturas propias visten salas, muebles y puertas (y en 0 no cambia nada)", function()
        bootServer(1)
        Engine.Run(0.5)
        local TextureAssets = Engine.RequireShared("Config.TextureAssets")
        local Library = Engine.RequireServer("World.MaterialLibrary")
        local MaterialService = Engine.Services.MaterialService

        -- Todo en 0: no se crea nada y ninguna pieza usa variante.
        local _, plain = loadChapter(1, 77)
        T.Equal(#Library.Created(), 0, "sin imágenes no hay variantes")
        for _, part in ipairs(plain:GetDescendants()) do
            if part:IsA("BasePart") then
                T.Equal(part.MaterialVariant, "", "sin texturas: " .. part:GetFullName())
            end
        end

        -- Números falsos para todos los mapas, como si ya estuvieran subidos.
        local names = {}
        for name in pairs(TextureAssets.Variants) do
            table.insert(names, name)
        end
        table.sort(names)
        for index, name in ipairs(names) do
            local entry = TextureAssets.Variants[name]
            entry.Color = 9000 + index * 10
            entry.Normal = 9001 + index * 10
            entry.Roughness = 9002 + index * 10
            entry.Metalness = name == "NocturnaScratchedSteel" and 9003 + index * 10 or 0
        end

        for chapter = 1, 5 do
            local theme = themeOf(chapter)
            local _, map = loadChapter(chapter, 400 + chapter)
            T.Equal(#Library.Created(), #names, "capítulo " .. chapter .. ": una variante por fila")
            for index, name in ipairs(names) do
                local variant = MaterialService:FindFirstChild(name)
                local entry = TextureAssets.Variants[name]
                T.True(variant ~= nil and variant:IsA("MaterialVariant"), "variante " .. name)
                T.Equal(variant.ColorMap, "rbxassetid://" .. (9000 + index * 10), name .. " ColorMap")
                T.Equal(variant.NormalMap, "rbxassetid://" .. (9001 + index * 10), name .. " NormalMap")
                T.Equal(variant.RoughnessMap, "rbxassetid://" .. (9002 + index * 10), name .. " RoughnessMap")
                T.Equal(variant.BaseMaterial, roblox.Enum.Material[entry.BaseMaterial], name .. " BaseMaterial")
                T.Equal(variant.StudsPerTile, entry.StudsPerTile, name .. " StudsPerTile")
            end
            T.Equal(MaterialService:FindFirstChild("NocturnaScratchedSteel").MetalnessMap, "rbxassetid://" .. (9003 + table.find(names, "NocturnaScratchedSteel") * 10), "metal")

            -- Salas: paredes, pisos y techos con la variante del capítulo, en su tono.
            local counts = {Wall = {0, 0}, Floor = {0, 0}, Ceiling = {0, 0}}
            for _, part in ipairs(map:FindFirstChild("Sectors"):GetDescendants()) do
                local count = part:IsA("BasePart") and part.Parent and part.Parent.Parent and part.Parent.Parent.Name == "Sectors" and counts[part.Name]
                if count then
                    count[1] += 1
                    if part.MaterialVariant == theme.Surfaces[part.Name] then
                        count[2] += 1
                        local variant = MaterialService:FindFirstChild(part.MaterialVariant)
                        T.Equal(part.Material, variant.BaseMaterial, "material base de " .. part.Name)
                        T.True(part.Color.R > 0.8 and part.Color.G > 0.8, "la textura trae su color: " .. part.Name)
                    end
                end
            end
            for key, count in pairs(counts) do
                T.True(count[1] > 0 and count[2] == count[1], string.format("capítulo %d %s con textura (%d de %d)", chapter, key, count[2], count[1]))
            end

            -- Utilería y puertas: cada material de la lista lleva su variante.
            local byKey = {}
            local untouched = 0
            for _, part in ipairs(map:GetDescendants()) do
                if part:IsA("BasePart") and part.Transparency < 0.95 then
                    local inWeathering = part:FindFirstAncestor("Weathering") ~= nil
                    for name, key in pairs(TextureAssets.PropMaterials) do
                        local variantName = theme.Surfaces[key]
                        if part.MaterialVariant == variantName and not counts[part.Name] then
                            byKey[key] = (byKey[key] or 0) + 1
                        end
                        if part.Material.Name == name and part.MaterialVariant == "" and not inWeathering then
                            untouched += 1
                        end
                    end
                end
            end
            T.Equal(untouched, 0, "capítulo " .. chapter .. ": ninguna pieza de utilería quedó sin su textura")
            T.True((byKey.Metal or 0) > 0, "capítulo " .. chapter .. ": metal con textura")
            T.True((byKey.Wood or 0) + (byKey.Fabric or 0) > 0, "capítulo " .. chapter .. ": madera o tela con textura")

            local doors = map:FindFirstChild("Doors", true)
            T.True(doors ~= nil, "puertas del capítulo")
            local textured = 0
            for _, part in ipairs(doors:GetDescendants()) do
                if part:IsA("BasePart") and part.MaterialVariant ~= "" and string.find(part:GetFullName(), "_Leaves", 1, true) then
                    textured += 1
                end
            end
            T.True(textured > 0, "capítulo " .. chapter .. ": las puertas usan la textura de su material")
        end

        -- Volver un número a 0 borra la variante en la próxima carga.
        TextureAssets.Variants.NocturnaTunnelBrick.Color = 0
        loadChapter(1, 77)
        T.Equal(MaterialService:FindFirstChild("NocturnaTunnelBrick"), nil, "sin imagen se borra la variante")
        T.NoEngineErrors(Engine)
    end)

    T.Test("Entorno: las puertas de cada capítulo tienen su estilo, se abren, y nunca encierran a nadie al cerrar", function()
        local players = bootServer(1)
        Engine.Run(0.5)
        local Doors = Engine.RequireServer("World.DoorService")
        local root = players[1].Character and players[1].Character:FindFirstChild("HumanoidRootPart")
        T.True(root ~= nil, "jugador con personaje")
        for index = 1, 5 do
            local _, map = loadChapter(index, 500 + index)
            local style = themeOf(index).DoorStyle
            local folder = map:FindFirstChild("Doors")
            local common = nil
            for _, part in ipairs(Engine.CollectionService:GetTagged("NocturnaDoor")) do
                if part:IsDescendantOf(folder) then
                    T.Equal(part:GetAttribute("DoorStyle"), style, "puerta del estilo del capítulo " .. index)
                    T.Equal(part.Transparency, 1, "lo que choca es invisible: se ven las hojas")
                    local leaves = folder:FindFirstChild(part.Name .. "_Leaves")
                    T.True(leaves ~= nil and #leaves:GetChildren() >= 3, "con hojas y detalles")
                    if part.Name == "Door" and not common then
                        common = part
                    end
                end
            end
            T.True(common ~= nil, "hay una puerta común en el capítulo " .. index)

            -- Se abre: el paso queda libre enseguida.
            Doors.OpenNear(common.Position)
            T.Equal(common:GetAttribute("Opened"), true, "abierta")
            T.False(common.CanCollide, "abierta no choca")

            -- Se cierra de golpe con alguien parado en el vano: no se vuelve sólida.
            root.CFrame = roblox.CFrame.new(common.Position)
            T.True(Doors.SlamNear(common.Position, 5), "portazo")
            Engine.Run(2)
            T.False(common.CanCollide, "no encierra a quien está en el vano")
            -- Cuando sale, el vano vuelve a ser pared.
            root.CFrame = roblox.CFrame.new(common.Position + Vector3.new(0, 0, 0) + common.CFrame.LookVector * 8)
            Engine.Run(1)
            T.True(common.CanCollide, "cerrada vuelve a tapar el paso")
        end
        T.NoEngineErrors(Engine)
    end)

    T.Test("Entorno: una puerta trabada se ve trabada y suelta el candado al abrirse", function()
        local players = bootServer(1)
        startMatch(players, 2)
        T.True(waitForPhase("Playing", 90), "partida")
        local Admin = Engine.RequireServer("Multiplayer.MatchService")
        Admin.SetChapter(2)
        T.True(Engine.RunUntil(function()
            return gameState().Chapter == 2 and gameState().Phase == "Playing"
        end, 40), "capítulo 2")
        local map = Engine.Workspace:FindFirstChild("NOCTURNA_MAP")
        local leaves = map:FindFirstChild("Doors"):FindFirstChild("RESEARCH_DOOR_Leaves")
        T.True(leaves ~= nil, "la puerta de investigación tiene hojas")
        T.True(leaves:FindFirstChild("Padlock") ~= nil and leaves:FindFirstChild("LockBar") ~= nil, "candado y barra")
        local lamp = leaves:FindFirstChild("StatusLamp")
        T.True(lamp ~= nil and lamp.Color.R > lamp.Color.G, "luz roja de trabada")

        Engine.RequireServer("Inventory.InventoryService").AddItem(players[1], "Keycard", 1)
        local position = Engine.RequireServer("World.DoorService").PositionOf("RESEARCH_DOOR")
        ctx.Bot.Use(Engine, players[1], position)
        Engine.Run(0.5)
        T.True(leaves:FindFirstChild("Padlock") == nil, "el candado se cae")
        T.True(lamp.Color.G > lamp.Color.R, "luz verde al abrirse")
        T.NoEngineErrors(Engine)
    end)

    local function hairCheck(rig, label)
        local head = rig:FindFirstChild("Head")
        local counts = {}
        local pigtailRoots = {}
        for _, part in ipairs(rig:GetChildren()) do
            if part:IsA("BasePart") and part ~= head then
                counts[part.Name] = (counts[part.Name] or 0) + 1
            end
        end
        for _, name in ipairs({"Hair", "HairBack", "Hairclip"}) do
            T.True((counts[name] or 0) >= 1, label .. ": " .. name)
        end
        T.Equal(counts.Bang, 3, label .. ": flequillo de tres mechones")
        T.Equal(counts.Pigtail, 2, label .. ": dos colitas")
        T.Equal(counts.Scrunchie, 2, label .. ": atadas con colitas de tela")
        T.Equal(counts.Bow, 4, label .. ": dos moños")

        -- Todo cuelga de la cabeza: soldado a ella o a una colita que cuelga de ella.
        for _, part in ipairs(rig:GetChildren()) do
            if part:IsA("BasePart") and part.Name == "Pigtail" then
                local joint = part:FindFirstChild("PigtailWeld")
                T.True(joint ~= nil and joint.Part0 == head and joint.Part1 == part, label .. ": colita colgada de la cabeza")
                T.True(Engine.CollectionService:HasTag(joint, "NocturnaHairSway"), label .. ": la colita se balancea")
                pigtailRoots[part] = true
            end
        end
        local names = {Hair = true, HairBack = true, Bang = true, Hairclip = true, PigtailPuff = true, Scrunchie = true, Bow = true}
        for _, part in ipairs(rig:GetChildren()) do
            if part:IsA("BasePart") and names[part.Name] then
                local weld = part:FindFirstChildOfClass("WeldConstraint")
                T.True(weld ~= nil and (weld.Part0 == head or pigtailRoots[weld.Part0]), label .. ": " .. part.Name .. " soldado")
                T.True(part.Massless and not part.CanCollide and not part.CanQuery, label .. ": " .. part.Name .. " no pesa ni choca")
                -- Nada baja hasta los hombros ni se aleja de la cabeza.
                local offset = head.CFrame:PointToObjectSpace(part.Position)
                T.True(offset.Y > -head.Size.Y * 0.95 and offset.Magnitude < head.Size.X * 1.4, label .. ": " .. part.Name .. " cerca de la cabeza")
            end
        end
    end

    T.Test("Entorno: Alma tiene un pelo tierno pegado a la cabeza, con avatar y con piezas", function()
        for _, options in ipairs({{}, {AvatarOffline = true}}) do
            Engine.Reset(options)
            local player = Engine.AddPlayer("Hermano", 3001)
            local character = Engine.CreateCharacter(player)
            character:FindFirstChild("HumanoidRootPart").CFrame = roblox.CFrame.new(0, 3, 60)
            local AlmaBuilder = Engine.RequireServer("World.AlmaBuilder")
            local holder = AlmaBuilder.Build(Engine.Workspace, {Id = "ALMA"}, roblox.CFrame.new(0, 0, 0))
            local rig = holder:FindFirstChild("Alma")
            hairCheck(rig, rig:GetAttribute("Source"))

            -- La alegría sigue igual con el pelo puesto.
            character:FindFirstChild("HumanoidRootPart").CFrame = roblox.CFrame.new(0, 3, 8)
            Engine.Run(0.5)
            T.True(holder:GetAttribute("Found"), "lo encuentra")
            Engine.Run(3)
            T.True(table.find(Engine.AnimationLog, AlmaBuilder.Animations.Cheer) ~= nil, "festeja")
            T.NoEngineErrors(Engine)
        end
    end)

    T.Test("Entorno: en bajo consumo no hay haces, polvo ni goteras; en calidad normal vuelven cerca", function()
        local player = ctx.clientWithMatch({})
        local fx = Engine.CollectionService:GetTagged("NocturnaAtmosFx")
        T.True(#fx > 0, "hay efectos de atmósfera")
        local toggle = player:FindFirstChild("PlayerGui"):FindFirstChild("NocturnaSettings"):FindFirstChild("LowQuality", true)
        Engine.GuiInput(toggle, "Activated")
        Engine.Run(1)
        for _, effect in ipairs(fx) do
            T.False(effect.Enabled, "apagado en bajo consumo: " .. effect.Name)
        end
        Engine.GuiInput(toggle, "Activated")
        -- La cámara va al lado de un efecto para que quede cerca.
        local target = fx[1]
        local parent = target.Parent
        local position = parent:IsA("Attachment") and parent.WorldPosition or parent.Position
        Engine.Workspace.CurrentCamera.CFrame = roblox.CFrame.new(position + Vector3.new(0, -2, 3))
        Engine.Run(1)
        local lit = not target:IsA("Beam") or (target.Parent:FindFirstChildOfClass("PointLight") and target.Parent:FindFirstChildOfClass("PointLight").Enabled)
        if lit then
            T.True(target.Enabled, "vuelve cerca en calidad normal: " .. target.Name)
        end
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
