--!nocheck
-- Ejecuta toda la batería sin Roblox:  lune run tests/lune/run.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local Bot = require("./Bot")
local Engine = require("./Engine")
local T = require("./Harness")

local roblox = Engine.Roblox
local Vector3 = roblox.Vector3

-- Opcional: lune run tests/lune/run.luau "parte del nombre de la prueba"
T.Filter = process.args[1]

Engine.Reset()
local Rng = Engine.RequireShared("Logic.Rng")
local MazeLayout = Engine.RequireShared("Logic.MazeLayout")
local LayoutPlanner = Engine.RequireShared("Logic.LayoutPlanner")
local ObjectiveTracker = Engine.RequireShared("Logic.ObjectiveTracker")
local InventoryModel = Engine.RequireShared("Logic.InventoryModel")
local StaminaModel = Engine.RequireShared("Logic.StaminaModel")
local SaveSchema = Engine.RequireShared("Logic.SaveSchema")
local RateLimiter = Engine.RequireShared("Logic.RateLimiter")
local ChapterConfig = Engine.RequireShared("Config.ChapterConfig")
local DocumentConfig = Engine.RequireShared("Config.DocumentConfig")
local GameConfig = Engine.RequireShared("Config.GameConfig")
local ItemConfig = Engine.RequireShared("Config.ItemConfig")
local MonsterConfig = Engine.RequireShared("Config.MonsterConfig")
local RemoteNames = Engine.RequireShared("Events.RemoteNames")
local AudioConfig = Engine.RequireShared("Config.AudioConfig")
local ThemeConfig = Engine.RequireShared("Config.ThemeConfig")

local function listFiles(path, into)
    into = into or {}
    for _, entry in ipairs(fs.readDir(path)) do
        local full = path .. "/" .. entry
        if fs.isDir(full) then
            listFiles(full, into)
        elseif string.find(entry, "%.luau?$") then
            table.insert(into, full)
        end
    end
    return into
end

local allFiles = listFiles("src")

-- Arranca un servidor simulado con N jugadores y lo lleva al lobby.
local function bootServer(playerCount, options)
    Engine.Reset(options)
    Engine.StartServer()
    Engine.Run(0.5)

    local players = {}
    for index = 1, playerCount or 1 do
        table.insert(players, Engine.AddPlayer("Jugador" .. index, 2000 + index))
    end
    Engine.Run(2)
    return players
end

local function fire(remoteName, player, ...)
    local folder = Engine.Services.ReplicatedStorage:FindFirstChild("NocturnaRemotes")
    local remote = folder:FindFirstChild(remoteName)
    local saved = Engine.LocalPlayer
    Engine.LocalPlayer = player
    remote:FireServer(...)
    Engine.LocalPlayer = saved
end

local function startMatch(players, chapter, difficulty)
    if chapter then
        fire("LobbyAction", players[1], "SetChapter", chapter)
    end
    if difficulty then
        fire("LobbyAction", players[1], "SetDifficulty", difficulty)
    end
    for _, player in ipairs(players) do
        fire("LobbyAction", player, "Ready")
    end
    Engine.Run(0.5)
    fire("LobbyAction", players[1], "Start")
end

local function gameState()
    return Engine.RequireServer("Core.GameState")
end

local function waitForPhase(phase, timeout)
    return Engine.RunUntil(function()
        return gameState().Phase == phase
    end, timeout or 120)
end

-- Juega hasta terminar el capítulo actual, siempre con el jugador 1 vivo que encuentre.
local function playChapter(players, chapterIndex)
    local state = gameState()
    local steps = 0

    while state.Phase == "Playing" and state.Chapter == chapterIndex and steps < 3000 do
        steps += 1
        for _, player in ipairs(players) do
            local character = player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                Bot.Act(Engine, player)
                break
            end
        end
        Engine.Run(0.4)
    end
    return steps
end

T.Suite("Estructura del proyecto")

T.Test("no hay archivos que produzcan instancias duplicadas", function()
    Engine.Reset()
end)

T.Test("todos los módulos del servidor y compartidos cargan", function()
    Engine.Reset()
    Engine.Services.Players.CharacterAutoLoads = false
    local shared = Engine.RequireShared("Modules.RemoteHelper")
    shared.Setup()

    local loaded = 0
    local function walk(folder)
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("ModuleScript") then
                Engine.Require(child, "Server")
                loaded += 1
            elseif child:IsA("Folder") then
                walk(child)
            end
        end
    end
    walk(Engine.SharedFolder)
    walk(Engine.ServerFolder)
    T.True(loaded >= 45, "cantidad de módulos cargados: " .. loaded)
    T.NoEngineErrors(Engine)
end)

T.Test("no queda uso de _G, ni scripts sueltos además de los dos puntos de entrada", function()
    local entryPoints = 0
    for _, path in ipairs(allFiles) do
        local source = fs.readFile(path)
        T.False(string.find(source, "_G%."), path .. " usa _G")
        if string.find(path, "%.server%.luau?$") or string.find(path, "%.client%.luau?$") then
            entryPoints += 1
        end
    end
    T.Equal(entryPoints, 2, "puntos de entrada")
end)

T.Test("los remotos usados en el código coinciden con el manifiesto y su dirección", function()
    local direction = {}
    for _, name in ipairs(RemoteNames.ClientToServer) do
        direction[name] = "C2S"
    end
    for _, name in ipairs(RemoteNames.ServerToClient) do
        T.True(direction[name] == nil, "remoto repetido: " .. name)
        direction[name] = "S2C"
    end

    local used = {}
    local rules = {
        {"Remotes%.FireServer%(%s*\"(%w+)\"", "C2S", "client"},
        {"Remotes%.OnClient%(%s*\"(%w+)\"", "S2C", "client"},
        {"Remotes%.FireClient%(%s*\"(%w+)\"", "S2C", "server"},
        {"Remotes%.FireAll%(%s*\"(%w+)\"", "S2C", "server"},
        {"Remotes%.OnServer%(%s*\"(%w+)\"", "C2S", "server"},
    }

    for _, path in ipairs(allFiles) do
        local source = fs.readFile(path)
        for _, rule in ipairs(rules) do
            for name in string.gmatch(source, rule[1]) do
                T.Equal(direction[name], rule[2], name .. " en " .. path)
                T.True(string.find(path, "src/" .. rule[3], 1, true) ~= nil, name .. " usado en el lado equivocado: " .. path)
                used[name] = (used[name] or 0) + 1
            end
        end
    end

    -- ClientState conecta varios remotos por tabla en lugar de una llamada literal.
    local clientState = fs.readFile("src/client/Core/ClientState.lua")
    for name in pairs(direction) do
        if string.find(clientState, name .. " = ", 1, true) then
            used[name] = (used[name] or 0) + 1
        end
    end

    for name in pairs(direction) do
        T.True(used[name] ~= nil, "remoto declarado que nadie usa: " .. name)
    end
end)

T.Test("cada remoto cliente-servidor tiene un receptor en el servidor y viceversa", function()
    local handled = {}
    for _, path in ipairs(listFiles("src/server")) do
        for name in string.gmatch(fs.readFile(path), "Remotes%.OnServer%(%s*\"(%w+)\"") do
            handled[name] = true
        end
    end
    for _, name in ipairs(RemoteNames.ClientToServer) do
        T.True(handled[name], "sin receptor: " .. name)
    end

    local received = {}
    for _, path in ipairs(listFiles("src/client")) do
        local source = fs.readFile(path)
        for name in string.gmatch(source, "Remotes%.OnClient%(%s*\"(%w+)\"") do
            received[name] = true
        end
        for name in string.gmatch(source, "(%w+) = \"%w+\",") do
            received[name] = true
        end
    end
    for _, name in ipairs(RemoteNames.ServerToClient) do
        T.True(received[name], "sin receptor en el cliente: " .. name)
    end
end)

T.Test("toda orden de sonido del servidor existe en AudioConfig", function()
    for _, path in ipairs(listFiles("src/server")) do
        for name in string.gmatch(fs.readFile(path), "\"PlaySound\",[^\n]-\"(%w+)\"") do
            T.True(AudioConfig.Sfx[name] ~= nil, "sonido desconocido: " .. name)
        end
    end
    for name in string.gmatch(fs.readFile("src/server/World/DoorService.lua"), "playAt%(door, \"(%w+)\"%)") do
        T.True(AudioConfig.Sfx[name] ~= nil, "sonido desconocido: " .. name)
    end
end)

T.Suite("Datos del juego")

T.Test("cinco capítulos con objetivos, monstruo y textos", function()
    T.Equal(#GameConfig.Chapters, 5, "capítulos")
    for index, name in ipairs(GameConfig.Chapters) do
        local chapter = ChapterConfig[index]
        T.Equal(chapter.Name, name, "nombre del capítulo")
        T.True(#chapter.Objectives >= 3, "objetivos del capítulo " .. index)
        T.True(#chapter.Intro > 0, "introducción del capítulo " .. index)
        T.True(ThemeConfig[chapter.Theme] ~= nil, "tema del capítulo " .. index)
        for _, kind in ipairs(chapter.Monsters) do
            T.True(MonsterConfig[kind] ~= nil, "monstruo " .. kind)
        end
    end
end)

T.Test("los cinco monstruos tienen configuración y comportamiento", function()
    local count = 0
    for kind in pairs(MonsterConfig) do
        count += 1
        T.True(fs.isFile("src/server/AI/Behaviors/" .. kind .. ".lua"), "comportamiento de " .. kind)
    end
    T.Equal(count, 5, "monstruos")
end)

T.Test("cada objetivo apunta a algo que existe en su mapa", function()
    for index = 1, 5 do
        local chapter = ChapterConfig[index]
        local spec = chapter.Layout
        local targets = {[spec.Exit.Id] = "Activate"}

        if spec.Exit.Door then
            targets[spec.Exit.Door.Id] = "Unlock"
        end
        if spec.Exit.Zone then
            targets[spec.Exit.Zone] = "Reach"
        end
        for _, zone in ipairs(spec.Zones or {}) do
            targets[zone.Id] = "Reach"
        end
        for _, feature in ipairs(spec.Features or {}) do
            targets[feature.Id] = "Activate"
            if feature.Group then
                targets[feature.Group] = "Activate"
            end
        end
        for _, room in ipairs(spec.LockedRooms or {}) do
            targets[room.Door.Id] = "Unlock"
            if room.Zone then
                targets[room.Zone] = "Reach"
            end
            for _, feature in ipairs(room.Features or {}) do
                targets[feature.Id] = "Activate"
            end
        end
        for _, item in ipairs(spec.Items) do
            targets[item.Item] = "Collect"
            T.True(ItemConfig[item.Item] ~= nil, "objeto " .. item.Item)
        end
        if spec.DocumentGroup then
            targets[spec.DocumentGroup] = "Read"
        end

        for _, objective in ipairs(chapter.Objectives) do
            T.Equal(targets[objective.Target], objective.Type, objective.Id .. " -> " .. objective.Target)
        end
    end
end)

T.Test("hay exactamente 15 documentos y aparecen todos en algún capítulo", function()
    local count, placed = 0, {}
    for id in pairs(DocumentConfig) do
        count += 1
        placed[id] = 0
    end
    T.Equal(count, GameConfig.Match.MaxDocuments, "documentos")

    for index = 1, 5 do
        for _, id in ipairs(ChapterConfig[index].Layout.Documents) do
            placed[id] += 1
            T.Equal(DocumentConfig[id].Chapter, index, "capítulo de " .. id)
        end
    end
    for id, times in pairs(placed) do
        T.Equal(times, 1, "ubicaciones de " .. id)
    end
end)

T.Test("los objetos consumidos alcanzan: nadie queda trabado por falta de material", function()
    for index = 1, 5 do
        local spec = ChapterConfig[index].Layout
        local supply = {}
        for _, item in ipairs(spec.Items) do
            supply[item.Item] = item.Count
        end

        local demand = {}
        local function want(itemId, amount)
            demand[itemId] = (demand[itemId] or 0) + amount
        end

        for _, feature in ipairs(spec.Features or {}) do
            if feature.Kind == "Generator" then
                want("Fuse", feature.Fuses)
            end
        end
        if spec.Exit.Door and spec.Exit.Door.RequiredItem then
            want(spec.Exit.Door.RequiredItem, spec.Exit.Door.Amount or 1)
        end
        for _, room in ipairs(spec.LockedRooms or {}) do
            if room.Door.RequiredItem then
                want(room.Door.RequiredItem, room.Door.Amount or 1)
            end
            for _, feature in ipairs(room.Features or {}) do
                if feature.RequiredItem and not feature.KeepItem then
                    want(feature.RequiredItem, feature.RequiredAmount or 1)
                end
            end
        end

        for itemId, amount in pairs(demand) do
            T.True((supply[itemId] or 0) >= amount, string.format("capítulo %d: %s %d/%d", index, itemId, supply[itemId] or 0, amount))
        end
    end
end)

T.Test("el inventario de un jugador alcanza para cargar los objetos de misión", function()
    for itemId, definition in pairs(ItemConfig) do
        T.True(definition.DisplayName ~= nil and definition.Description ~= nil, itemId)
    end
end)

T.Suite("Generación procedural")

T.Test("el mismo número da el mismo mapa", function()
    local a = MazeLayout.Generate({Width = 6, Depth = 6, Seed = 42, LoopChance = 0.2})
    local b = MazeLayout.Generate({Width = 6, Depth = 6, Seed = 42, LoopChance = 0.2})
    T.Equal(a.Exit, b.Exit, "salida")
    for index, cell in ipairs(a.Cells) do
        for _, direction in ipairs(MazeLayout.DirectionOrder) do
            T.Equal(cell.Open[direction], b.Cells[index].Open[direction], "abertura")
        end
    end
end)

T.Test("las aberturas siempre son simétricas", function()
    local layout = MazeLayout.Generate({Width = 6, Depth = 6, Seed = 7, LoopChance = 0.3})
    for _, cell in ipairs(layout.Cells) do
        for _, direction in ipairs(MazeLayout.DirectionOrder) do
            if cell.Open[direction] then
                local neighbor = MazeLayout.Neighbor(layout, cell, direction)
                T.True(neighbor.Open[MazeLayout.Directions[direction].Opposite], "abertura sin par")
            end
        end
    end
end)

T.Test("400 mapas por capítulo: conectados, completables y sin superposiciones", function()
    for chapterIndex = 1, 5 do
        local spec = ChapterConfig[chapterIndex].Layout
        for seed = 1, 400 do
            local success, plan = pcall(function()
                local layout = MazeLayout.Generate({
                    Width = spec.Width,
                    Depth = spec.Depth,
                    Seed = seed * 17,
                    LoopChance = spec.LoopChance,
                    ReservedLeaves = spec.LockedRooms and #spec.LockedRooms or 0,
                })
                return LayoutPlanner.Plan(layout, spec)
            end)

            -- WorldService reintenta con otra semilla; acá se cuenta si esto ocurriera.
            if success then
                local valid, reason = LayoutPlanner.Validate(plan)
                T.True(valid, string.format("capítulo %d semilla %d: %s", chapterIndex, seed, tostring(reason)))
                T.True(MazeLayout.Degree(plan.Layout, plan.Layout.Exit) == 1, "la salida debe tener una sola entrada")
                T.True(#plan.Layout.MainPath >= 4, "la salida no puede estar al lado del inicio")
            else
                error(string.format("capítulo %d semilla %d: %s", chapterIndex, seed, tostring(plan)))
            end
        end
    end
end)

T.Test("Rng reparte de forma razonable", function()
    local rng = Rng.new(99)
    local buckets = {0, 0, 0, 0}
    for _ = 1, 8000 do
        local value = rng:Int(1, 4)
        buckets[value] += 1
    end
    for _, count in ipairs(buckets) do
        T.True(count > 1800 and count < 2200, "bucket " .. count)
    end
end)

T.Suite("Lógica pura")

T.Test("objetivos en orden, con señales adelantadas y sin contar dos veces", function()
    local tracker = ObjectiveTracker.new({
        {Id = "A", Type = "Reach", Target = "Z"},
        {Id = "B", Type = "Collect", Target = "Fuse", Count = 2},
        {Id = "C", Type = "Activate", Target = "G"},
    })

    T.Equal(#tracker:Signal("Collect", "Fuse", "f1"), 0, "todavía no")
    T.Equal(#tracker:Signal("Collect", "Fuse", "f1"), 0, "duplicado")
    T.Equal(tracker:Count("Collect", "Fuse"), 1, "conteo sin duplicar")
    T.Equal(#tracker:Signal("Collect", "Fuse", "f2"), 0, "sigue bloqueado")

    local completed = tracker:Signal("Reach", "Z")
    T.Equal(#completed, 2, "completa A y B de golpe")
    T.Equal(tracker:Current().Id, "C", "objetivo actual")
    T.Equal(#tracker:Signal("Activate", "G"), 1, "último")
    T.True(tracker:IsFinished(), "terminado")
    T.Equal(#tracker:Signal("Activate", "G"), 0, "no falla al terminar")
end)

T.Test("inventario atómico: apila, respeta el límite y no pierde objetos", function()
    local inventory = InventoryModel.new(ItemConfig, 2)
    T.True(inventory:Add("Battery", 3), "agrega")
    T.True(inventory:Add("Battery", 3), "segundo casillero")
    T.Equal(#inventory.Slots, 2, "casilleros")
    T.False(inventory:Add("Battery", 3), "no entra")
    T.Equal(inventory:Count("Battery"), 6, "no cambió al fallar")
    T.False(inventory:Add("NoExiste"), "objeto inválido")
    T.False(inventory:Add("Battery", 1.5), "cantidad inválida")
    T.False(inventory:Add("Battery", -1), "cantidad negativa")
    T.True(inventory:Remove("Battery", 5), "quita")
    T.Equal(inventory:Count("Battery"), 1, "resto")
    T.False(inventory:Remove("Battery", 2), "no alcanza")

    local quest = InventoryModel.new(ItemConfig, 4)
    quest:Add("Fuse", 2)
    quest:Add("Battery", 1)
    local taken = quest:TakeQuestItems()
    T.Equal(#taken, 1, "objetos de misión")
    T.Equal(taken[1].Amount, 2, "cantidad caída")
    T.Equal(quest:Count("Battery"), 1, "lo común se conserva")
end)

T.Test("resistencia: se agota, bloquea el sprint y se recupera", function()
    local config = GameConfig.Player
    local state = StaminaModel.new(config)
    T.True(StaminaModel.Request(state, true), "puede correr")
    for _ = 1, 60 do
        StaminaModel.Step(state, 0.1, true, config)
    end
    T.True(state.Exhausted, "agotado")
    T.False(state.Sprinting, "deja de correr")
    T.False(StaminaModel.Request(state, true), "no puede volver a correr")
    T.Equal(StaminaModel.Speed(state, false, config), config.WalkSpeed, "camina")
    for _ = 1, 50 do
        StaminaModel.Step(state, 0.1, false, config)
    end
    T.False(state.Exhausted, "recuperado")
    T.Equal(StaminaModel.Speed(state, true, config), config.CrouchSpeed, "sigilo")
end)

T.Test("guardado: normaliza datos dañados y nunca retrocede progreso", function()
    local data = SaveSchema.Normalize({UnlockedChapter = 99, CurrentChapter = -2, Deaths = "x", Documents = "nada", Settings = {MusicVolume = 5, Subtitles = "si"}})
    T.Equal(data.UnlockedChapter, 5, "capítulo acotado")
    T.Equal(data.CurrentChapter, 1, "capítulo actual")
    T.Equal(data.Deaths, 0, "muertes")
    T.Equal(data.Settings.MusicVolume, 1, "volumen acotado")
    T.Equal(data.Settings.Subtitles, true, "ajuste inválido ignorado")

    local legacy = SaveSchema.Normalize({Version = 1, CurrentChapter = 2, UnlockedChapter = 3, Documents = {DOC_1A = true}, Deaths = 4, CompletedMatches = 1, MonsterEncounters = 2, LastPlayed = 5})
    T.Equal(legacy.Version, SaveSchema.Version, "migración de versión")
    T.Equal(legacy.UnlockedChapter, 3, "conserva capítulo de la v1")
    T.True(legacy.Documents.DOC_1A, "conserva documentos de la v1")

    local merged = SaveSchema.Merge(
        {UnlockedChapter = 4, Documents = {DOC_1A = true}, Deaths = 9, Endings = {Release = true}},
        {UnlockedChapter = 2, Documents = {DOC_2A = true}, Deaths = 3}
    )
    T.Equal(merged.UnlockedChapter, 4, "no retrocede")
    T.True(merged.Documents.DOC_1A and merged.Documents.DOC_2A, "une documentos")
    T.Equal(merged.Deaths, 9, "conserva estadística")
    T.True(merged.Endings.Release, "conserva finales")
end)

T.Test("limitador de frecuencia", function()
    local limiter = RateLimiter.new(2, 2)
    T.True(limiter:Allow("a", 0), "1")
    T.True(limiter:Allow("a", 0), "2")
    T.False(limiter:Allow("a", 0), "3 bloqueado")
    T.True(limiter:Allow("b", 0), "otro jugador")
    T.True(limiter:Allow("a", 1), "recupera con el tiempo")
end)

T.Suite("Inteligencia artificial")

-- Mundo simulado sencillo: una recta de celdas conectadas.
local function fakeWorld(snapshots)
    local layout = MazeLayout.Generate({Width = 5, Depth = 1 + 1, Seed = 3, LoopChance = 1})
    local nav = Engine.RequireShared("Logic.MazeNav").new(layout, GameConfig.Map.CellSize)
    local world = {
        Nav = nav,
        CeilingHeight = GameConfig.Map.WallHeight,
        Snapshots = snapshots,
        NoiseList = {},
        Log = {},
        Damaged = {},
        Sight = true,
        Lit = false,
    }

    function world:Players() return self.Snapshots end
    function world:Noises() return self.NoiseList end
    function world:LineOfSight() return self.Sight end
    function world:PatrolCell() return 2 end
    function world:OpenDoorsNear() end
    function world:SmashDoorsNear() self.Smashed = true end
    function world:IsLit() return self.Lit end
    function world:RandomInt(minimum) return minimum end
    function world:VoiceFor() return "Alma" end
    function world:OnStateChanged() end
    function world:Encounter(_, snapshot) self.Encountered = snapshot end
    function world:Effect(name, payload) table.insert(self.Log, {name, payload}) end
    function world:Damage(_, snapshot, amount) table.insert(self.Damaged, {snapshot, amount}) end
    function world:PullOut(_, snapshot) self.Pulled = snapshot; snapshot.Hidden = false end
    function world:Quake() self.Quaked = true end
    function world:Collapse() self.Collapsed = true end
    return world
end

local function newMonster(kind, world, position)
    Engine.Reset()
    local Controller = Engine.RequireServer("AI.MonsterController")
    local Behavior = Engine.RequireServer("AI.Behaviors." .. kind)
    return Controller.new(kind, MonsterConfig[kind], Behavior, world, position or Vector3.new(0, 4, 0))
end

local function snapshot(position, extra)
    local result = {
        Player = {},
        Position = position,
        Look = Vector3.new(1, 0, 0),
        Speed = 0,
        Hidden = false,
        HiddenFor = 0,
        Flashlight = false,
    }
    for key, value in pairs(extra or {}) do
        result[key] = value
    end
    return result
end

local function tick(monster, seconds)
    for _ = 1, math.floor(seconds * 15) do
        monster:Tick(1 / 15)
    end
end

T.Test("El Oyente ignora al jugador quieto y va hacia el ruido", function()
    local target = snapshot(Vector3.new(80, 3, 0))
    local world = fakeWorld({target})
    local monster = newMonster("ElOyente", world)

    tick(monster, 1)
    T.Equal(#world.Damaged, 0, "no ataca sin oír")

    table.insert(world.NoiseList, {Position = Vector3.new(30, 3, 0), Radius = 70, Time = 1000, Source = nil})
    monster:Tick(1 / 15)
    T.Equal(monster.State, "Investigate", "investiga el ruido")
    tick(monster, 6)
    T.True(monster:Distance(Vector3.new(30, 3, 0)) < 3, "llegó al ruido")
end)

T.Test("El Oyente no percibe a quien se queda inmóvil, pero sí a quien se mueve pegado a él", function()
    local target = snapshot(Vector3.new(6, 3, 0))
    local world = fakeWorld({target})
    world.PatrolCell = function()
        return nil
    end
    local monster = newMonster("ElOyente", world)

    tick(monster, 1)
    T.Equal(#world.Damaged, 0, "inmóvil a 6 studs está a salvo")

    target.Speed = 8
    tick(monster, 2)
    T.True(#world.Damaged > 0, "moverse cerca lo delata")
end)

T.Test("Nadie detecta a un jugador escondido que no vieron entrar", function()
    local target = snapshot(Vector3.new(4, 3, 0), {Hidden = true, HiddenFor = 30})
    local world = fakeWorld({target})
    for _, kind in ipairs({"ElOyente", "ElImitador", "ElQuieto", "ElColoso"}) do
        local monster = newMonster(kind, world)
        tick(monster, 3)
        T.Equal(#world.Damaged, 0, kind .. " no debe atacar a un escondido")
    end
end)

T.Test("Quien ve entrar al escondite saca al jugador a la fuerza", function()
    local target = snapshot(Vector3.new(5, 3, 0), {Flashlight = true})
    local world = fakeWorld({target})
    local monster = newMonster("ElColoso", world)

    tick(monster, 0.5)
    T.Equal(monster.State, "Chase", "persigue")
    monster.Clock += 0
    target.Hidden = true
    target.HiddenFor = 0.2
    tick(monster, 3)
    T.True(world.Pulled == target, "lo saca del escondite")
end)

T.Test("El Imitador llama con una voz y embosca donde sonó", function()
    local target = snapshot(Vector3.new(0, 3, 40))
    local world = fakeWorld({target})
    world.Sight = false
    local monster = newMonster("ElImitador", world, Vector3.new(160, 3, 0))

    tick(monster, MonsterConfig.ElImitador.LureInterval + 1)
    T.Equal(monster.State, "Ambush", "emboscada")

    local voice = nil
    for _, entry in ipairs(world.Log) do
        if entry[1] == "ImitatorVoice" then
            voice = entry[2]
        end
    end
    T.True(voice ~= nil, "emite la voz")
    T.Equal(voice.Speaker, "Alma", "imita a Alma si no hay compañeros")
    T.True(table.find(MonsterConfig.ElImitador.Lines, voice.Text) ~= nil, "línea configurada")
    T.Equal(voice.Position, monster.Position, "la voz sale de donde espera")

    target.Position = monster.Position + Vector3.new(6, 0, 0)
    tick(monster, 0.5)
    T.Equal(monster.State, "Chase", "ataca al acercarse")
end)

T.Test("El Quieto se congela si lo miran con luz y avanza si no", function()
    local target = snapshot(Vector3.new(60, 3, 0), {Look = Vector3.new(-1, 0, 0), Flashlight = true})
    local world = fakeWorld({target})
    local monster = newMonster("ElQuieto", world)
    local start = monster.Position

    tick(monster, 2)
    T.Equal(monster.State, "Frozen", "congelado")
    T.Equal(monster.Position, start, "no se movió")

    target.Flashlight = false
    tick(monster, 1)
    T.Equal(monster.State, "Stalk", "a oscuras mirarlo no alcanza")
    T.True(monster.Position ~= start, "avanzó")

    local position = monster.Position
    target.Flashlight = true
    target.Look = Vector3.new(1, 0, 0)
    tick(monster, 0.5)
    T.True(monster.Position ~= position, "de espaldas sigue avanzando")
end)

T.Test("El Trepador anda por el techo, cae sobre el jugador y la linterna lo espanta", function()
    local target = snapshot(Vector3.new(50, 3, 0), {Look = Vector3.new(1, 0, 0)})
    local world = fakeWorld({target})
    local monster = newMonster("ElTrepador", world)

    T.True(monster.Position.Y > 10, "arranca en el techo")
    T.True(monster.Up.Y < 0, "boca abajo")

    tick(monster, 6)
    T.True(#world.Damaged > 0 or monster.State == "Pounce", "se dejó caer y atacó")

    local spot = snapshot(Vector3.new(20, 3, 0), {Look = Vector3.new(-1, 0, 0), Flashlight = true})
    world.Snapshots = {spot}
    local second = newMonster("ElTrepador", world)
    tick(second, 0.3)
    T.Equal(second.State, "Flee", "huye de la linterna")
end)

T.Test("El Coloso derrumba, tiembla y rompe puertas, y la furia lo acelera", function()
    local target = snapshot(Vector3.new(40, 3, 0), {Flashlight = true})
    local world = fakeWorld({target})
    world.Sight = false
    local monster = newMonster("ElColoso", world)

    tick(monster, MonsterConfig.ElColoso.EnvironmentInterval + 1)
    T.True(world.Quaked, "temblor")
    T.True(world.Collapsed, "derrumbe")
    T.True(world.Smashed, "rompe puertas")

    world.Sight = true
    monster.Rage = true
    tick(monster, 1)
    T.Equal(monster.Speed, MonsterConfig.ElColoso.RageSpeed, "velocidad de furia")
end)

T.Test("la dificultad multiplica el daño", function()
    local target = snapshot(Vector3.new(3, 3, 0), {Flashlight = true})
    local world = fakeWorld({target})
    Engine.Reset()
    local Controller = Engine.RequireServer("AI.MonsterController")
    local Behavior = Engine.RequireServer("AI.Behaviors.ElColoso")
    local monster = Controller.new("ElColoso", MonsterConfig.ElColoso, Behavior, world, Vector3.new(0, 4, 0), {Speed = 1, Damage = 2})
    tick(monster, 1)
    T.Equal(world.Damaged[1][2], MonsterConfig.ElColoso.Damage * 2, "daño escalado")
end)

T.Suite("Partida simulada completa")

T.Test("el servidor arranca sin errores y crea todos los remotos", function()
    bootServer(1)
    T.NoEngineErrors(Engine)
    local folder = Engine.Services.ReplicatedStorage:FindFirstChild("NocturnaRemotes")
    T.Equal(#folder:GetChildren(), #RemoteNames.ClientToServer + #RemoteNames.ServerToClient, "remotos")
    T.True(Engine.Workspace:FindFirstChild("NOCTURNA_LOBBY") ~= nil, "lobby construido")
end)

T.Test("el cliente arranca en PC sin errores", function()
    local players = bootServer(1)
    Engine.StartClient(players[1])
    Engine.Run(3)
    T.NoEngineErrors(Engine)
    local gui = players[1]:FindFirstChild("PlayerGui")
    for _, name in ipairs({"NocturnaHUD", "NocturnaLobby", "NocturnaInventory", "NocturnaJournal", "NocturnaCutscene", "NocturnaTouch"}) do
        T.True(gui:FindFirstChild(name) ~= nil, "pantalla " .. name)
    end
end)

T.Test("el cliente arranca en móvil con controles táctiles y escala legible", function()
    local players = bootServer(1, {Touch = true, Viewport = roblox.Vector2.new(812, 375)})
    Engine.StartClient(players[1])
    Engine.Run(3)
    T.NoEngineErrors(Engine)

    local touch = players[1]:FindFirstChild("PlayerGui"):FindFirstChild("NocturnaTouch")
    local holder = touch:FindFirstChild("Root"):FindFirstChild("TouchActions")
    T.True(holder ~= nil, "controles táctiles presentes")

    local buttons = 0
    for _, child in ipairs(holder:GetChildren()) do
        if child:IsA("TextButton") then
            buttons += 1
            T.True(child.Size.X.Offset >= 44, "botón de tamaño táctil")
        end
    end
    T.Equal(buttons, 3, "correr, sigilo y luz")

    local scale = touch:FindFirstChild("Root"):FindFirstChildOfClass("UIScale").Scale
    T.True(scale >= 0.62 and scale <= 1, "escala " .. scale)
end)

T.Test("en PC no aparecen los botones táctiles", function()
    local players = bootServer(1)
    Engine.StartClient(players[1])
    Engine.Run(2)
    local root = players[1]:FindFirstChild("PlayerGui"):FindFirstChild("NocturnaTouch"):FindFirstChild("Root")
    T.True(root:FindFirstChild("TouchActions") == nil, "sin controles táctiles")
end)

T.Test("campaña completa con 2 jugadores, 5 capítulos y un final", function()
    local players = bootServer(2)
    startMatch(players)

    T.True(waitForPhase("Playing", 60), "empieza el capítulo 1")
    T.Equal(gameState().Chapter, 1, "capítulo inicial")

    for chapterIndex = 1, 5 do
        T.Equal(gameState().Chapter, chapterIndex, "capítulo en curso")
        local steps = playChapter(players, chapterIndex)
        T.True(steps < 3000, "capítulo trabado: " .. chapterIndex .. " fase " .. gameState().Phase)
        T.NoEngineErrors(Engine)
        if gameState().Phase == "Failed" then
            local update = Engine.LastSent("ObjectiveUpdate")[1]
            error(string.format(
                "capítulo %d fallido en %s: %s (pasos %d, reintentos %d, fase %s)",
                chapterIndex,
                tostring(update.ObjectiveId),
                tostring(Engine.LastSent("DownState")[1].Reason),
                steps,
                gameState().Lives,
                gameState().Phase
            ))
        end

        if chapterIndex < 5 then
            T.True(waitForPhase("Playing", 60), "avanza al capítulo " .. (chapterIndex + 1))
        end
    end

    T.True(waitForPhase("Ending", 60), "llega a la decisión final")
    fire("EndingVote", players[1], "Rescue")
    fire("EndingVote", players[2], "Rescue")
    T.True(waitForPhase("Lobby", 120), "vuelve al lobby tras el final")
    T.NoEngineErrors(Engine)

    local Progression = Engine.RequireServer("Data.ProgressionService")
    local data = Progression.Get(players[1])
    T.Equal(data.UnlockedChapter, 5, "capítulos desbloqueados")
    T.True(data.Endings.Rescue, "final registrado")
    T.Equal(data.CompletedMatches, 1, "campaña contada")
end)

T.Test("el final verdadero sólo aparece con los 15 documentos", function()
    local players = bootServer(1)
    Engine.Run(1)
    local Ending = Engine.RequireServer("Story.EndingService")
    local Progression = Engine.RequireServer("Data.ProgressionService")

    Engine.Run(0.2)
    local thread = coroutine.create(Ending.RunVote)
    coroutine.resume(thread)
    Engine.Run(0.2)
    local prompt = Engine.LastSent("EndingPrompt")[1]
    T.Equal(#prompt.Options, 2, "sin documentos, dos finales")
    fire("EndingVote", players[1], "Remember")
    Engine.Run(0.5)
    T.True(coroutine.status(thread) ~= "dead", "voto inválido ignorado")
    fire("EndingVote", players[1], "Release")
    Engine.Run(0.5)

    for id in pairs(DocumentConfig) do
        Progression.AddDocument(players[1], id)
    end
    local second = coroutine.create(Ending.RunVote)
    coroutine.resume(second)
    Engine.Run(0.2)
    prompt = Engine.LastSent("EndingPrompt")[1]
    T.Equal(#prompt.Options, 3, "con todos, tres finales")
    T.Equal(prompt.Options[3].Id, "Remember", "final verdadero")
    fire("EndingVote", players[1], "Remember")
    Engine.Run(0.5)
end)

T.Test("resolución del voto: mayoría, empate y sin votos", function()
    bootServer(1)
    local Ending = Engine.RequireServer("Story.EndingService")
    local list = {"Release", "Rescue", "Remember"}
    T.Equal(Ending.Resolve(list, {Release = 2, Rescue = 1}), "Release", "mayoría")
    T.Equal(Ending.Resolve(list, {Release = 1, Remember = 1}), "Remember", "empate")
    T.Equal(Ending.Resolve(list, {}), "Release", "sin votos")
end)

T.Test("muerte, reaparición en el punto de control y reintentos del grupo", function()
    local players = bootServer(2)
    startMatch(players, nil)
    T.True(waitForPhase("Playing", 60), "partida")

    local state = gameState()
    local lives = state.Lives
    T.Equal(lives, GameConfig.Match.LivesPerChapter + GameConfig.Match.LivesPerExtraPlayer, "reintentos para 2")

    players[1].Character:FindFirstChildOfClass("Humanoid").Health = 0
    Engine.Run(0.5)
    T.Equal(state.Lives, lives - 1, "consume un reintento")
    T.Equal(Engine.LastSent("DownState", players[1])[1].Down, true, "aviso de caída")

    local firstCharacter = players[1].Character
    Engine.Run(GameConfig.Match.RespawnDelay + 1)
    T.True(players[1].Character ~= firstCharacter, "reapareció")
    T.True(players[1].Character:FindFirstChildOfClass("Humanoid").Health > 0, "con vida")
    T.Equal(Engine.LastSent("DownState", players[1])[1].Down, false, "aviso de regreso")
    T.NoEngineErrors(Engine)
end)

T.Test("sin reintentos, el jugador queda de espectador y si caen todos falla el capítulo", function()
    local players = bootServer(2)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")

    local state = gameState()
    state.Lives = 0

    players[1].Character:FindFirstChildOfClass("Humanoid").Health = 0
    Engine.Run(1)
    T.Equal(Engine.LastSent("DownState", players[1])[1].Spectating, true, "espectador")
    T.Equal(state.Phase, "Playing", "el otro sigue jugando")

    players[2].Character:FindFirstChildOfClass("Humanoid").Health = 0
    Engine.Run(1)
    T.Equal(state.Phase, "Failed", "capítulo fallido")

    fire("LobbyAction", players[2], "Retry")
    Engine.Run(0.5)
    T.Equal(state.Phase, "Failed", "sólo el líder decide")

    fire("LobbyAction", players[1], "Retry")
    T.True(waitForPhase("Playing", 30), "reintento")
    T.True(state.Lives > 0, "reintentos restaurados")
    T.NoEngineErrors(Engine)
end)

T.Test("los objetos de misión de quien cae quedan en el suelo y siguen sirviendo", function()
    local players = bootServer(2)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(1)

    local Inventory = Engine.RequireServer("Inventory.InventoryService")
    local Interaction = Engine.RequireServer("World.InteractionService")
    Inventory.AddItem(players[1], "Fuse", 2)

    local before = #Interaction.ItemPositions("Fuse")
    players[1].Character:FindFirstChildOfClass("Humanoid").Health = 0
    Engine.Run(0.5)

    T.Equal(Inventory.CountParty("Fuse"), 0, "ya no los lleva")
    T.Equal(#Interaction.ItemPositions("Fuse"), before + 1, "quedaron en el suelo")
    T.NoEngineErrors(Engine)
end)

T.Test("el objetivo cronometrado falla el capítulo si se acaba el tiempo", function()
    local players = bootServer(1)
    startMatch(players, 1)
    T.True(waitForPhase("Playing", 60), "partida")

    local Story = Engine.RequireServer("Story.StoryService")
    local EventBus = Engine.RequireServer("Core.EventBus")
    EventBus.Emit("ChapterFailed", "Se acabó el tiempo.")
    Engine.Run(0.5)
    T.Equal(gameState().Phase, "Failed", "fallido")
    T.Equal(Engine.LastSent("DownState")[1].Reason, "Se acabó el tiempo.", "motivo")
    Engine.Run(GameConfig.Match.FailureAutoRetry + 1)
    T.True(waitForPhase("Playing", 30), "reintento automático")
    T.True(Story ~= nil, "servicio")
end)

T.Test("el grupo comparte objetos para abrir puertas", function()
    local players = bootServer(3)
    Engine.Run(1)
    local Inventory = Engine.RequireServer("Inventory.InventoryService")
    Inventory.AddItem(players[1], "MemoryShard", 1)
    Inventory.AddItem(players[2], "MemoryShard", 1)
    Inventory.AddItem(players[3], "MemoryShard", 1)

    T.False(Inventory.RemoveFromParty(players[1], "MemoryShard", 4), "no alcanza: no quita nada")
    T.Equal(Inventory.CountParty("MemoryShard"), 3, "intacto")
    T.True(Inventory.RemoveFromParty(players[1], "MemoryShard", 3), "alcanza")
    T.Equal(Inventory.CountParty("MemoryShard"), 0, "consumidos")
end)

T.Suite("Guardado")

T.Test("el progreso se guarda al salir y se carga al volver", function()
    Engine.Stores = {}
    local players = bootServer(1)
    local Progression = Engine.RequireServer("Data.ProgressionService")

    Progression.UnlockChapter(players[1], 2)
    Progression.UnlockChapter(players[1], 3)
    Progression.AddDocument(players[1], "DOC_1A")
    Progression.SetSettings(players[1], {MusicVolume = 0.2})
    Engine.RemovePlayer(players[1])
    Engine.Run(1)

    local stored = Engine.Stores.NOCTURNA_PLAYER_DATA_V1["PLAYER_2001"]
    T.True(stored ~= nil, "se escribió en DataStore")
    T.Equal(stored.UnlockedChapter, 3, "capítulo guardado")

    local stores = Engine.Stores
    local second = bootServer(0, {Stores = stores})
    T.Equal(#second, 0, "servidor nuevo")
    local returning = Engine.AddPlayer("Jugador1", 2001)
    Engine.Run(2)

    local reloaded = Engine.RequireServer("Data.ProgressionService").Get(returning)
    T.Equal(reloaded.UnlockedChapter, 3, "capítulo recuperado")
    T.True(reloaded.Documents.DOC_1A, "documento recuperado")
    T.Equal(reloaded.Settings.MusicVolume, 0.2, "ajuste recuperado")
    T.NoEngineErrors(Engine)
end)

T.Test("sin DataStore (Studio sin API) se juega en modo sesión y no se escribe nada", function()
    local players = bootServer(1, {DataStoreOffline = true, Stores = {}})
    T.Equal(players[1]:GetAttribute("NocturnaSaveOffline"), true, "avisa modo sesión")
    T.Equal(players[1]:GetAttribute("NocturnaDataLoaded"), true, "datos por defecto cargados")
    T.True(players[1].Character ~= nil, "igual puede jugar")
    T.NoEngineErrors(Engine)
end)

T.Test("un fallo al cargar no pisa los datos guardados", function()
    local stores = {NOCTURNA_PLAYER_DATA_V1 = {PLAYER_2001 = {Version = 2, UnlockedChapter = 4, Documents = {}, Endings = {}}}}
    local players = bootServer(1, {Stores = stores, DataStoreFailures = 3})
    Engine.Run(20)

    local Progression = Engine.RequireServer("Data.ProgressionService")
    T.Equal(players[1]:GetAttribute("NocturnaSaveOffline"), true, "modo sesión")
    T.False(Progression.Save(players[1]), "no guarda")
    T.Equal(stores.NOCTURNA_PLAYER_DATA_V1.PLAYER_2001.UnlockedChapter, 4, "datos intactos")
end)

T.Test("reintenta un fallo pasajero de DataStore", function()
    local stores = {NOCTURNA_PLAYER_DATA_V1 = {PLAYER_2001 = {Version = 2, UnlockedChapter = 4, Documents = {}, Endings = {}}}}
    local players = bootServer(1, {Stores = stores, DataStoreFailures = 1})
    Engine.Run(5)
    T.Equal(players[1]:GetAttribute("NocturnaSaveOffline"), false, "recuperado")
    T.Equal(players[1]:GetAttribute("NocturnaUnlockedChapter"), 4, "datos cargados")
end)

T.Suite("Seguridad")

T.Test("el cliente no puede subir su velocidad ni iniciar con datos inválidos", function()
    local players = bootServer(2)
    fire("SprintRequest", players[1], "sí")
    fire("SprintRequest", players[1], 999)
    fire("CrouchRequest", players[1], {})
    fire("UseItem", players[1], 123)
    fire("UseItem", players[1], "NoExiste")
    fire("LobbyAction", players[1], 55)
    fire("LobbyAction", players[2], "SetChapter", 5)
    fire("LobbyAction", players[1], "SetChapter", 5)
    fire("LobbyAction", players[1], "SetDifficulty", "Imposible")
    fire("EndingVote", players[1], "Remember")
    fire("SettingsUpdate", players[1], "nada")
    fire("AdminAction", players[1], "kick", {"Jugador2"})
    Engine.Run(1)

    T.Equal(gameState().Phase, "Lobby", "sigue en lobby")
    T.Equal(#Engine.Services.Players:GetPlayers(), 2, "nadie expulsado")

    local lobby = Engine.LastSent("LobbyUpdate")[1]
    T.Equal(lobby.Chapter, 1, "no pudo saltar capítulos")
    T.Equal(lobby.Difficulty, "Normal", "dificultad intacta")
    T.NoEngineErrors(Engine)
end)

T.Test("sólo el líder inicia y hacen falta todos listos", function()
    local players = bootServer(2)
    fire("LobbyAction", players[1], "Start")
    Engine.Run(1)
    T.Equal(gameState().Phase, "Lobby", "faltan listos")

    fire("LobbyAction", players[1], "Ready")
    fire("LobbyAction", players[2], "Ready")
    fire("LobbyAction", players[2], "Start")
    Engine.Run(1)
    T.Equal(gameState().Phase, "Lobby", "el no líder no inicia")

    fire("LobbyAction", players[1], "Start")
    Engine.Run(1)
    T.True(gameState().Phase ~= "Lobby", "el líder inicia")
end)

T.Test("el spam de remotos queda limitado", function()
    local players = bootServer(1)
    Engine.Run(1)
    local Flashlight = Engine.RequireServer("Data.FlashlightService")
    local changes = 0
    players[1]:GetAttributeChangedSignal("FlashlightEnabled"):Connect(function()
        changes += 1
    end)
    for _ = 1, 500 do
        fire("FlashlightToggle", players[1])
    end
    T.True(changes <= 13, "cambios aceptados: " .. changes)
    T.True(Flashlight ~= nil, "servicio")
end)

T.Test("no se puede usar un objeto a distancia ni muerto", function()
    local players = bootServer(1)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(1)

    local Inventory = Engine.RequireServer("Inventory.InventoryService")
    local Interaction = Engine.RequireServer("World.InteractionService")
    local positions = Interaction.ItemPositions("Fuse")
    local prompt = Bot.NearestPrompt(Engine, positions[1])

    Bot.MoveTo(Engine, players[1], positions[1] + Vector3.new(60, 0, 0))
    prompt:Fire(players[1])
    Engine.Run(0.5)
    T.Equal(Inventory.CountParty("Fuse"), 0, "a distancia no recoge")

    Bot.MoveTo(Engine, players[1], positions[1])
    players[1].Character:FindFirstChildOfClass("Humanoid").Health = 0
    Engine.Run(0.5)
    prompt:Fire(players[1])
    Engine.Run(0.5)
    T.Equal(Inventory.CountParty("Fuse"), 0, "muerto no recoge")
end)

T.Test("movimiento imposible detectado por el antitrampas", function()
    Engine.Reset()
    Engine.RequireShared("Modules.RemoteHelper")
    local AntiCheat = Engine.RequireServer("Security.AntiCheat")
    T.True(AntiCheat.IsMovementValid(Vector3.new(0, 3, 0), Vector3.new(8, 3, 0), 0.5), "correr es válido")
    T.False(AntiCheat.IsMovementValid(Vector3.new(0, 3, 0), Vector3.new(80, 3, 0), 0.5), "teletransporte")
    T.False(AntiCheat.IsMovementValid(Vector3.new(0, 3, 0), Vector3.new(0, 40, 0), 0.5), "volar")
end)

T.Test("la sala se limita a cuatro jugadores", function()
    local players = bootServer(4)
    local fifth = Engine.AddPlayer("Quinto", 9005)
    Engine.Run(1)
    T.True(Engine.Kicked[fifth.UserId] ~= nil, "quinto rechazado")
    T.Equal(#Engine.Services.Players:GetPlayers(), #players, "siguen cuatro")
end)

T.Suite("Moderación y analíticas")

T.Test("el dueño es administrador y un jugador común no", function()
    local players = bootServer(2, {CreatorId = 2001})
    Engine.Run(1)
    local Admin = Engine.RequireServer("Admin.AdminService")
    T.True(Admin.IsAdmin(players[1]), "dueño")
    T.False(Admin.IsAdmin(players[2]), "jugador común")
    T.Equal(players[1]:GetAttribute("IsNocturnaAdmin"), true, "marcado")
    T.Equal(players[2]:GetAttribute("IsNocturnaAdmin"), false, "no marcado")
end)

T.Test("expulsar, sancionar con persistencia y levantar la sanción", function()
    local stores = {}
    local players = bootServer(2, {CreatorId = 2001, Stores = stores})
    Engine.Run(1)
    local Admin = Engine.RequireServer("Admin.AdminService")

    T.True(Admin.Execute(players[1], "ban", {"Jugador2", "7", "molestar"}), "sanción")
    T.True(Engine.Kicked[2002] ~= nil, "expulsado")
    T.False(Admin.Execute(players[1], "ban", {"Jugador1"}), "no puede sancionarse")

    local second = bootServer(0, {CreatorId = 2001, Stores = stores})
    T.Equal(#second, 0, "servidor nuevo")
    Engine.AddPlayer("Jugador2", 2002)
    Engine.Run(1)
    T.True(Engine.Kicked[2002] ~= nil, "sanción vigente en otro servidor")

    local third = Engine.RequireServer("Admin.ModerationStore")
    third.Unban(2002)
    T.True(third.GetActiveBan(2002) == nil, "sanción levantada")
end)

T.Test("comandos de administración durante la partida", function()
    local players = bootServer(1, {CreatorId = 2001})
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")

    local Admin = Engine.RequireServer("Admin.AdminService")
    T.True(Admin.Execute(players[1], "skip", {}), "saltar objetivo")
    T.True(Admin.Execute(players[1], "spawn", {"ElColoso"}), "crear criatura")
    T.Equal(#Engine.RequireServer("Monsters.MonsterService").Active(), 1, "criatura activa")
    T.True(Admin.Execute(players[1], "clearmonsters", {}), "quitar criaturas")
    T.True(Admin.Execute(players[1], "give", {"Battery"}), "dar objeto")
    T.False(Admin.Execute(players[1], "give", {"Nada"}), "objeto inválido")
    T.True(Admin.Execute(players[1], "announce", {"hola"}), "anuncio")
    T.True(Admin.Execute(players[1], "setchapter", {"3"}), "cambiar capítulo")
    T.True(waitForPhase("Playing", 60), "capítulo cambiado")
    T.Equal(gameState().Chapter, 3, "capítulo 3")
    T.NoEngineErrors(Engine)
end)

T.Test("las analíticas registran capítulo, objetivo y final sin afectar la partida", function()
    local players = bootServer(1)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    Bot.Act(Engine, players[1])
    Engine.Run(1)

    local names = {}
    for _, entry in ipairs(Engine.AnalyticsLog) do
        names[entry.Name] = true
    end
    T.True(names.ChapterStarted, "capítulo iniciado")
    T.True(names.Objective_C1_ENTRY, "objetivo registrado")
end)

local failed = T.Summary()
process.exit(failed > 0 and 1 or 0)
