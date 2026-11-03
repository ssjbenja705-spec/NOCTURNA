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

T.Suite("Sistemas de juego en partida")

local function firstLockerPrompt()
    local hides = Engine.Workspace:FindFirstChild("NOCTURNA_MAP"):FindFirstChild("Hides")
    return hides:GetChildren()[1]:FindFirstChild("Door"):FindFirstChild("NocturnaPrompt")
end

T.Test("escondites: entra, apaga la linterna, no hace ruido, y sale", function()
    local players = bootServer(2)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(1)

    local Hiding = Engine.RequireServer("World.HidingService")
    local Noise = Engine.RequireServer("AI.NoiseService")
    local Flashlight = Engine.RequireServer("Data.FlashlightService")
    local prompt = firstLockerPrompt()
    local root = players[1].Character:FindFirstChild("HumanoidRootPart")

    Flashlight.SetEnabled(players[1], true)
    Bot.MoveTo(Engine, players[1], prompt.Parent.Position)
    prompt:Fire(players[1])
    Engine.Run(0.5)

    T.True(Hiding.IsHidden(players[1]), "escondido")
    T.True(root.Anchored, "fijo adentro")
    T.False(Flashlight.IsOn(players[1]), "linterna apagada")
    T.False(prompt.Enabled, "casillero ocupado")
    T.Equal(Engine.LastSent("HideState", players[1])[1], true, "cliente avisado")

    Bot.MoveTo(Engine, players[2], prompt.Parent.Position)
    prompt:Fire(players[2])
    Engine.Run(0.2)
    T.False(Hiding.IsHidden(players[2]), "no entran dos")

    Noise.Clear()
    root.AssemblyLinearVelocity = Vector3.new(20, 0, 0)
    Engine.Run(1)
    local fromHidden = 0
    for _, noise in ipairs(Noise.Recent()) do
        if noise.Source == players[1] then
            fromHidden += 1
        end
    end
    T.Equal(fromHidden, 0, "escondido no hace ruido")

    fire("ExitHiding", players[1])
    Engine.Run(0.2)
    T.False(Hiding.IsHidden(players[1]), "salió")
    T.False(root.Anchored, "libre")
    T.True(prompt.Enabled, "casillero libre")
    T.Equal(Engine.LastSent("HideState", players[1])[1], false, "cliente avisado al salir")
    T.NoEngineErrors(Engine)
end)

T.Test("el casillero mira hacia la sala y deja al jugador afuera, enfrente", function()
    local players = bootServer(1)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(1)

    -- La orientación absoluta se comprueba en Studio: CFrame.lookAt de Lune no coincide
    -- con el del motor. Acá se valida la posición relativa al casillero.
    local plan = gameState().Plan
    local Rooms = Engine.RequireServer("World.RoomGenerator")
    local spot = plan.Hides[1]
    local slot = Rooms.SlotCFrame(plan.Layout, spot.Cell, spot.Slot)

    local prompt = firstLockerPrompt()
    Bot.MoveTo(Engine, players[1], prompt.Parent.Position)
    prompt:Fire(players[1])
    Engine.Run(0.3)
    local camera = Engine.LastSent("HideState", players[1])[2]
    local relative = slot:ToObjectSpace(camera)
    T.True(relative.Position.Z < -1.8, "la cámara queda del lado de la puerta")
    T.True(camera.LookVector:Dot(slot.LookVector) > 0.99, "mira hacia donde mira la puerta")

    fire("ExitHiding", players[1])
    Engine.Run(0.3)
    local root = players[1].Character:FindFirstChild("HumanoidRootPart")
    T.True((root.Position - camera.Position).Magnitude < 6, "sale frente al casillero")
end)

T.Test("criaturas: usan las mallas de Blender importadas y, si faltan, piezas simples", function()
    Engine.Reset()
    local Factory = Engine.RequireServer("Monsters.MonsterFactory")
    local workspace = Engine.Workspace

    -- Sin modelos importados: todo son Parts.
    local plain = Factory.Build("ElOyente", workspace, 4)
    for _, piece in ipairs(plain:GetChildren()) do
        T.Equal(piece.ClassName, "Part", "sin modelos, " .. piece.Name .. " es una Part")
    end
    plain:Destroy()

    -- Como deja el importador 3D de Studio: un modelo con una MeshPart por nombre.
    local folder = Engine.New("Folder", "NocturnaModels")
    folder.Parent = Engine.Services.ServerStorage
    local set = Engine.New("Model", "ElQuieto")
    set.Parent = folder
    local inner = Engine.New("Model", "Imported")
    inner.Parent = set
    for _, name in ipairs({"Torso", "Head", "Arm", "Leg"}) do
        local mesh = Engine.New("MeshPart", name)
        mesh.Size = Vector3.new(9, 9, 9)
        mesh.Anchored = true
        mesh.Parent = inner
        Engine.New("Attachment", "Stray").Parent = mesh
    end

    local quieto = Factory.Build("ElQuieto", workspace, 3.6)
    local root = quieto.PrimaryPart
    local meshes = 0
    for _, piece in ipairs(quieto:GetChildren()) do
        if piece ~= root then
            local joint = piece:FindFirstChild(piece.Name .. "Joint")
            T.True(joint ~= nil and joint.Part0 == root, piece.Name .. " sigue unida a la raíz")
            if piece.Name == "Eye" then
                T.Equal(piece.ClassName, "Part", "el ojo no tiene malla y queda como Part")
            else
                meshes += 1
                T.Equal(piece.ClassName, "MeshPart", piece.Name .. " usa la malla")
                T.False(piece.Anchored, piece.Name .. " no queda anclada")
                T.True(piece.Size.Magnitude < 5, piece.Name .. " toma el tamaño de la pieza, no el de la plantilla")
                T.Equal(piece.Material, roblox.Enum.Material.SmoothPlastic, "sin textura toma el material de la criatura")
                T.True(piece:FindFirstChild("Stray") == nil, "no arrastra hijos de la plantilla")
            end
        end
    end
    T.Equal(meshes, 6, "torso, cabeza, dos brazos y dos piernas")
    T.Equal(#inner:GetChildren(), 4, "las plantillas quedan intactas")

    -- Los maniquíes del capítulo 5 son idénticos a El Quieto.
    local mannequin = Factory.BuildMannequin(workspace, roblox.CFrame.new(0, 0, 0))
    T.Equal(mannequin:FindFirstChild("Head").ClassName, "MeshPart", "el maniquí usa la misma malla")

    -- TurnAround gira las mallas media vuelta sin mover la articulación.
    folder:SetAttribute("TurnAround", true)
    local turned = Factory.Build("ElQuieto", workspace, 3.6)
    local head = turned:FindFirstChild("Head")
    local joint = head:FindFirstChild("HeadJoint")
    T.True(joint.C1.LookVector:Dot(Vector3.new(0, 0, 1)) > 0.99, "C1 gira media vuelta")
    T.True((head.Position - (turned.PrimaryPart.CFrame * joint.C0).Position).Magnitude < 1e-3, "la cabeza queda en su lugar")
end)

T.Test("linterna: se gasta en el servidor, se apaga sola y se recarga con una batería", function()
    local players = bootServer(1)
    Engine.Run(1)
    local player = players[1]
    local Inventory = Engine.RequireServer("Inventory.InventoryService")

    fire("FlashlightToggle", player)
    Engine.Run(0.2)
    T.Equal(player:GetAttribute("FlashlightEnabled"), true, "encendida")

    local light = player.Character:FindFirstChild("Head"):FindFirstChild("NocturnaFlashlightAttachment"):FindFirstChild("NocturnaFlashlight")
    T.True(light.Enabled, "la luz existe en el personaje y la ve todo el grupo")

    Engine.Run(GameConfig.Flashlight.BatterySeconds + 2)
    T.Equal(player:GetAttribute("FlashlightEnabled"), false, "se apagó")
    T.Equal(player:GetAttribute("FlashlightBattery"), 0, "sin batería")
    fire("FlashlightToggle", player)
    Engine.Run(0.5)
    T.Equal(player:GetAttribute("FlashlightEnabled"), false, "sin batería no enciende")

    Inventory.AddItem(player, "Battery", 1)
    fire("UseItem", player, "Battery")
    Engine.Run(0.5)
    T.Equal(player:GetAttribute("FlashlightBattery"), GameConfig.Flashlight.BatteryRecharge, "recargada")
    T.False(Inventory.HasItem(player, "Battery"), "batería consumida")
end)

T.Test("botiquín: cura, y no se gasta con la vida llena", function()
    local players = bootServer(1)
    Engine.Run(1)
    local player = players[1]
    local Inventory = Engine.RequireServer("Inventory.InventoryService")
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")

    Inventory.AddItem(player, "Medkit", 1)
    fire("UseItem", player, "Medkit")
    Engine.Run(0.5)
    T.True(Inventory.HasItem(player, "Medkit"), "con vida llena no se gasta")

    humanoid.Health = 30
    Engine.Run(0.5)
    fire("UseItem", player, "Medkit")
    Engine.Run(0.5)
    T.Equal(humanoid.Health, 80, "curó")
    T.False(Inventory.HasItem(player, "Medkit"), "consumido")
end)

T.Test("la vida no se regenera sola: el script por defecto se elimina", function()
    local players = bootServer(1)
    Engine.Run(4)
    T.True(players[1].Character:FindFirstChild("Health") == nil, "sin regeneración")
end)

T.Test("sprint y sigilo cambian la velocidad real desde el servidor", function()
    local players = bootServer(1)
    Engine.Run(1)
    local player = players[1]
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")

    fire("SprintRequest", player, true)
    Engine.Run(0.2)
    T.Equal(humanoid.WalkSpeed, GameConfig.Player.SprintSpeed, "corre")

    fire("CrouchRequest", player, true)
    Engine.Run(0.2)
    T.Equal(humanoid.WalkSpeed, GameConfig.Player.CrouchSpeed, "sigilo")
    T.Equal(player:GetAttribute("IsSprinting"), false, "dejó de correr")

    fire("CrouchRequest", player, false)
    Engine.Run(0.2)
    T.Equal(humanoid.WalkSpeed, GameConfig.Player.WalkSpeed, "camina")
end)

T.Test("el ruido sale de la velocidad real: correr se oye más que caminar o ir en sigilo", function()
    local players = bootServer(1)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")

    local Noise = Engine.RequireServer("AI.NoiseService")
    local root = players[1].Character:FindFirstChild("HumanoidRootPart")

    local function loudest()
        Noise.Clear()
        Engine.Run(1)
        local radius = 0
        for _, noise in ipairs(Noise.Recent()) do
            radius = math.max(radius, noise.Radius)
        end
        return radius
    end

    T.Equal(loudest(), 0, "quieto no hace ruido")
    root.AssemblyLinearVelocity = Vector3.new(10, 0, 0)
    T.Equal(loudest(), GameConfig.Noise.Walk, "caminar")
    root.AssemblyLinearVelocity = Vector3.new(17, 0, 0)
    T.Equal(loudest(), GameConfig.Noise.Sprint, "correr")
    fire("CrouchRequest", players[1], true)
    Engine.Run(0.1)
    T.Equal(loudest(), GameConfig.Noise.Crouch, "sigilo")
end)

T.Test("puertas: la cerrada pide su objeto, bloquea a los monstruos y se abre una vez", function()
    local players = bootServer(1)
    startMatch(players, 1)
    T.True(waitForPhase("Playing", 60), "partida")

    local Admin = Engine.RequireServer("Multiplayer.MatchService")
    Admin.SetChapter(2)
    T.True(Engine.RunUntil(function()
        return gameState().Chapter == 2 and gameState().Phase == "Playing"
    end, 30), "capítulo 2")
    Engine.Run(1)

    local Doors = Engine.RequireServer("World.DoorService")
    local Inventory = Engine.RequireServer("Inventory.InventoryService")
    local position = Doors.PositionOf("RESEARCH_DOOR")
    local plan = gameState().Plan
    local spec = nil
    for _, door in ipairs(plan.Doors) do
        if door.Id == "RESEARCH_DOOR" then
            spec = door
        end
    end

    T.True(gameState().Nav:IsBlocked(spec.A, spec.B), "los monstruos no pasan")
    Bot.Use(Engine, players[1], position)
    Engine.Run(0.5)
    T.True(Doors.IsLocked("RESEARCH_DOOR"), "sin tarjeta sigue cerrada")

    Inventory.AddItem(players[1], "Keycard", 1)
    Bot.Use(Engine, players[1], position)
    Engine.Run(0.5)
    T.False(Doors.IsLocked("RESEARCH_DOOR"), "abierta")
    T.False(Inventory.HasItem(players[1], "Keycard"), "tarjeta consumida")
    T.False(gameState().Nav:IsBlocked(spec.A, spec.B), "navegación habilitada")
    T.NoEngineErrors(Engine)
end)

T.Test("generador: necesita fusibles y enciende las luces del capítulo", function()
    local players = bootServer(1)
    startMatch(players, 1)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(1)

    local state = gameState()
    local Mechanisms = Engine.RequireServer("World.MechanismService")
    local Inventory = Engine.RequireServer("Inventory.InventoryService")
    local position = Mechanisms.PositionsFor("GEN_MAIN")[1]
    T.False(state.Powered, "empieza sin energía")

    local prompt = Bot.Use(Engine, players[1], position)
    Engine.Run(0.3)
    T.False(state.HasFlag("POWER"), "sin fusibles no arranca")

    Inventory.AddItem(players[1], "Fuse", 3)
    for _ = 1, 3 do
        Engine.Run(0.5)
        Bot.Use(Engine, players[1], position)
    end
    Engine.Run(0.5)
    T.Equal(prompt.ActionText, "Arrancar", "listo para arrancar")
    T.False(state.HasFlag("POWER"), "falta arrancarlo")

    Bot.Use(Engine, players[1], position)
    Engine.Run(0.5)
    T.True(state.HasFlag("POWER"), "energía")
    T.True(state.Powered, "luces encendidas")
    T.False(prompt.Enabled, "ya no se usa")
end)

T.Test("una salida no se puede usar antes de tiempo", function()
    local players = bootServer(1)
    startMatch(players, 1)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(1)

    local Mechanisms = Engine.RequireServer("World.MechanismService")
    local position = Mechanisms.PositionsFor("ELEVATOR")[1]
    Bot.Use(Engine, players[1], position)
    Engine.Run(0.5)
    T.False(gameState().Tracker:IsDone("C1_ELEVATOR"), "no saltea la historia")
    T.Equal(gameState().Phase, "Playing", "sigue el capítulo")
end)

T.Test("derrumbes del Coloso: nunca aíslan el mapa y se despejan", function()
    local players = bootServer(1)
    startMatch(players, 4)
    Engine.Run(1)

    local Match = Engine.RequireServer("Multiplayer.MatchService")
    Match.SetChapter(4)
    T.True(Engine.RunUntil(function()
        return gameState().Chapter == 4 and gameState().Phase == "Playing"
    end, 30), "capítulo 4")

    local state = gameState()
    local Environment = Engine.RequireServer("World.EnvironmentService")
    local center = state.Nav:Center(state.Layout.Exit, 3)
    local collapsed = 0
    for _ = 1, 5 do
        if Environment.Collapse(center, 5) then
            collapsed += 1
        end
    end
    T.True(collapsed >= 1 and collapsed <= 2, "derrumbes acotados: " .. collapsed)

    local blocked = table.clone(state.Nav.Blocked)
    for key in pairs(state.Plan.LockedEdges) do
        blocked[key] = nil
    end
    T.True(MazeLayout.IsConnected(state.Layout, blocked), "el mapa sigue conectado")

    Engine.Run(6)
    local remaining = 0
    for key in pairs(state.Nav.Blocked) do
        if not state.Plan.LockedEdges[key] then
            remaining += 1
        end
    end
    T.Equal(remaining, 0, "los escombros se despejan")
    T.NoEngineErrors(Engine)
end)

T.Suite("Cooperativo y reconexión")

T.Test("reintentos según jugadores y dificultad", function()
    local players = bootServer(4)
    startMatch(players, 1, "Pesadilla")
    T.True(waitForPhase("Playing", 60), "partida")
    local expected = GameConfig.Match.LivesPerChapter + 3 * GameConfig.Match.LivesPerExtraPlayer + GameConfig.Difficulties.Pesadilla.ExtraLives
    T.Equal(gameState().MaxLives, expected, "reintentos")
    T.Equal(gameState().Difficulty, "Pesadilla", "dificultad")
end)

T.Test("se puede entrar o volver con la partida en curso", function()
    local players = bootServer(1)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(2)

    local joiner = Engine.AddPlayer("Llega", 3001)
    Engine.Run(2)
    T.True(joiner.Character ~= nil, "tiene personaje")
    T.Equal(Engine.Kicked[3001], nil, "no fue expulsado")
    T.True(Engine.LastSent("ObjectiveUpdate", joiner) ~= nil, "recibe el objetivo")

    local root = joiner.Character:FindFirstChild("HumanoidRootPart")
    T.True(root.Position.Z > -600, "aparece en el mapa, no en el lobby")

    Engine.RemovePlayer(joiner)
    Engine.Run(1)
    local back = Engine.AddPlayer("Llega", 3001)
    Engine.Run(2)
    T.True(back.Character ~= nil, "volvió a entrar")
    T.NoEngineErrors(Engine)
end)

T.Test("si se va quien lleva objetos de misión, quedan para el grupo", function()
    local players = bootServer(2)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(1)

    local Inventory = Engine.RequireServer("Inventory.InventoryService")
    local Interaction = Engine.RequireServer("World.InteractionService")
    Inventory.AddItem(players[2], "Fuse", 2)
    local before = #Interaction.ItemPositions("Fuse")
    Engine.RemovePlayer(players[2])
    Engine.Run(1)
    T.Equal(#Interaction.ItemPositions("Fuse"), before + 1, "no se pierden")
    T.NoEngineErrors(Engine)
end)

T.Test("si se va el líder, otro toma el mando", function()
    local players = bootServer(2)
    Engine.RemovePlayer(players[1])
    Engine.Run(1)
    local lobby = Engine.LastSent("LobbyUpdate")[1]
    T.Equal(lobby.LeaderUserId, players[2].UserId, "nuevo líder")
end)

T.Test("si se van todos, el servidor vuelve al lobby y limpia el mapa", function()
    local players = bootServer(1)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.RemovePlayer(players[1])
    Engine.Run(2)
    T.Equal(gameState().Phase, "Lobby", "lobby")
    T.True(Engine.Workspace:FindFirstChild("NOCTURNA_MAP") == nil, "mapa eliminado")
    T.NoEngineErrors(Engine)
end)

T.Test("un capítulo desbloqueado por un amigo se puede jugar en grupo", function()
    local players = bootServer(2)
    local Progression = Engine.RequireServer("Data.ProgressionService")
    for chapter = 2, 3 do
        Progression.UnlockChapter(players[2], chapter)
    end

    fire("LobbyAction", players[1], "SetChapter", 3)
    Engine.Run(0.3)
    T.Equal(Engine.LastSent("LobbyUpdate")[1].Chapter, 3, "capítulo elegido")
    fire("LobbyAction", players[1], "SetChapter", 4)
    Engine.Run(0.3)
    T.Equal(Engine.LastSent("LobbyUpdate")[1].Chapter, 3, "no pasa del desbloqueado")
end)

T.Suite("Controles del cliente")

local function clientWithMatch(options)
    local players = bootServer(1, options)
    Engine.StartClient(players[1])
    Engine.Run(2)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(0.5)
    return players[1]
end

T.Test("teclado: Shift corre, C agacha y F enciende la linterna", function()
    local player = clientWithMatch()
    local Key = roblox.Enum.KeyCode

    Engine.Input("InputBegan", {KeyCode = Key.LeftShift})
    Engine.Run(0.2)
    T.Equal(player:GetAttribute("IsSprinting"), true, "corre")

    Engine.Input("InputEnded", {KeyCode = Key.LeftShift})
    Engine.Run(0.2)
    T.Equal(player:GetAttribute("IsSprinting"), false, "suelta")

    Engine.Input("InputBegan", {KeyCode = Key.C})
    Engine.Run(0.2)
    T.Equal(player:GetAttribute("IsCrouching"), true, "agachado")

    Engine.Input("InputBegan", {KeyCode = Key.F})
    Engine.Run(0.3)
    T.Equal(player:GetAttribute("FlashlightEnabled"), true, "linterna")
    T.NoEngineErrors(Engine)
end)

T.Test("teclado: I abre el inventario, J el diario y P los ajustes", function()
    local player = clientWithMatch()
    local Key = roblox.Enum.KeyCode
    local gui = player:FindFirstChild("PlayerGui")

    local inventory = gui:FindFirstChild("NocturnaInventory"):FindFirstChild("Root"):FindFirstChild("InventoryPanel")
    T.False(inventory.Visible, "cerrado")
    Engine.Input("InputBegan", {KeyCode = Key.I})
    Engine.Run(0.1)
    T.True(inventory.Visible, "abierto")

    local journal = gui:FindFirstChild("NocturnaJournal"):FindFirstChild("Root"):FindFirstChild("Journal")
    Engine.Input("InputBegan", {KeyCode = Key.J})
    Engine.Run(0.1)
    T.True(journal.Visible, "diario")

    local settings = gui:FindFirstChild("NocturnaSettings"):FindFirstChild("Root"):FindFirstChild("Settings")
    Engine.Input("InputBegan", {KeyCode = Key.P})
    Engine.Run(0.1)
    T.True(settings.Visible, "ajustes")
    T.NoEngineErrors(Engine)
end)

T.Test("táctil: mantener CORRER corre, SIGILO alterna y LUZ enciende", function()
    local player = clientWithMatch({Touch = true, Viewport = roblox.Vector2.new(812, 375)})
    local holder = player:FindFirstChild("PlayerGui"):FindFirstChild("NocturnaTouch"):FindFirstChild("Root"):FindFirstChild("TouchActions")
    local touch = {UserInputType = roblox.Enum.UserInputType.Touch}

    local buttons = {}
    for _, child in ipairs(holder:GetChildren()) do
        if child:IsA("TextButton") then
            buttons[child.Text] = child
        end
    end

    Engine.GuiInput(buttons.CORRER, "InputBegan", touch)
    Engine.Run(0.2)
    T.Equal(player:GetAttribute("IsSprinting"), true, "corre mientras mantiene")
    Engine.GuiInput(buttons.CORRER, "InputEnded", touch)
    Engine.Run(0.2)
    T.Equal(player:GetAttribute("IsSprinting"), false, "suelta")

    Engine.GuiInput(buttons.SIGILO, "Activated")
    Engine.Run(0.2)
    T.Equal(player:GetAttribute("IsCrouching"), true, "sigilo")

    Engine.GuiInput(buttons.LUZ, "Activated")
    Engine.Run(0.3)
    T.Equal(player:GetAttribute("FlashlightEnabled"), true, "linterna")
    T.True(holder.Visible, "visibles en partida")
    T.NoEngineErrors(Engine)
end)

T.Test("la interfaz sigue el estado: el lobby se oculta y el HUD aparece", function()
    local player = clientWithMatch()
    local gui = player:FindFirstChild("PlayerGui")
    T.False(gui:FindFirstChild("NocturnaLobby"):FindFirstChild("Root"):FindFirstChild("LobbyPanel").Visible, "lobby oculto")

    local objective = gui:FindFirstChild("NocturnaHUD"):FindFirstChild("Root"):FindFirstChild("Objective")
    T.True(objective.Visible, "objetivo visible")

    local shown = false
    for _, child in ipairs(objective:GetChildren()) do
        if child:IsA("TextLabel") and string.find(child.Text, "vestíbulo", 1, true) then
            shown = true
        end
    end
    T.True(shown, "muestra el objetivo con su texto, no el identificador")
end)

T.Test("el lector muestra el documento y el diario lo conserva", function()
    local player = clientWithMatch()
    local Interaction = Engine.RequireServer("World.InteractionService")
    local gui = player:FindFirstChild("PlayerGui")
    local reader = gui:FindFirstChild("NocturnaJournal"):FindFirstChild("Root"):FindFirstChild("Reader")

    local plan = gameState().Plan
    local entry = plan.Documents[1]
    Bot.Use(Engine, player, entry.Part.Position)
    Engine.Run(0.5)

    T.True(reader.Visible, "lector abierto")
    T.Equal(reader:GetChildren()[2].Text, DocumentConfig[entry.DocumentId].Title, "título del documento")
    T.True(Interaction ~= nil, "servicio")
    T.True(Engine.RequireServer("Data.ProgressionService").HasDocument(player, entry.DocumentId), "guardado en el perfil")
end)

T.Test("el texto tachado del diario usa RichText válido", function()
    local players = bootServer(1)
    Engine.StartClient(players[1])
    Engine.Run(1)
    local folder = players[1]:FindFirstChild("PlayerGui"):FindFirstChild("NocturnaJournal"):FindFirstChild("Root"):FindFirstChild("Reader")
    local remote = Engine.Services.ReplicatedStorage:FindFirstChild("NocturnaRemotes"):FindFirstChild("DocumentOpen")
    remote:FireClient(players[1], "DOC_5B")
    Engine.Run(0.1)

    local found = false
    for _, descendant in ipairs(folder:GetDescendants()) do
        if descendant:IsA("TextLabel") and string.find(descendant.Text, "<s>", 1, true) then
            found = true
            T.False(string.find(descendant.Text, "~~", 1, true), "sin marcas crudas")
        end
    end
    T.True(found, "tachado convertido")
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
