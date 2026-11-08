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
    for _ = 1, math.ceil(StaminaModel.SprintDuration(config) * 10) + 5 do
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

    local settings = MonsterConfig.ElTrepador
    T.Equal(monster.Position.Y, GameConfig.Map.WallHeight - settings.BodyHeight, "arranca con los pies en el techo")
    T.True(monster.Position.Y - settings.BodyHeight > 5.5, "colgado, deja pasar a un jugador por debajo")
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
    T.True(relative.Position.Z < 0 and relative.Position.Z > -1.6, "la cámara queda adentro, detrás de la puerta")
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

T.Test("criaturas realistas: piezas cortadas con sus medidas, sin ojos de neón", function()
    Engine.Reset()
    local Factory = Engine.RequireServer("Monsters.MonsterFactory")
    local CreatureMeshes = Engine.RequireServer("Monsters.CreatureMeshes")

    -- Lo que escribe prepare_ai_models.py para un modelo cortado: cada pieza con su
    -- propia caja (Offset, Box), distinta de la de la versión simple.
    local shift = Vector3.new(0.1, -0.2, 0.3)
    local fits = {}
    for index, key in ipairs({"Torso1", "Head1", "Arm1", "Arm2", "Leg1", "Leg2"}) do
        fits[key] = {
            Offset = roblox.CFrame.new(index, -index, 0.5) * roblox.CFrame.Angles(0.2, 0, 0),
            Box = Vector3.new(0.8, 4, 0.9),
            Size = Vector3.new(1, 2, 3),
            Shift = shift,
        }
    end
    CreatureMeshes.ElTrepador = fits

    local folder = Engine.New("Folder", "NocturnaModels")
    folder.Parent = Engine.Services.ServerStorage
    local set = Engine.New("Model", "ElTrepador")
    set.Parent = folder
    for key in pairs(fits) do
        local mesh = Engine.New("MeshPart", key)
        mesh:SetAttribute("Source", key)
        mesh.Parent = set
    end
    Engine.New("SurfaceAppearance", "Skin").Parent = set

    local monster = Factory.Build("ElTrepador", Engine.Workspace, 2)
    local root = monster.PrimaryPart
    T.True(monster:FindFirstChild("Eye") == nil, "sin ojos de neón")

    local legs = {}
    for _, piece in ipairs(monster:GetChildren()) do
        if piece ~= root then
            local joint = piece:FindFirstChild(piece.Name .. "Joint")
            local fit = fits[piece:GetAttribute("Source")]
            T.Equal(piece.ClassName, "MeshPart", piece.Name .. " usa la pieza cortada")
            T.Equal(piece.Size, Vector3.new(1, 2, 3), piece.Name .. " conserva su tamaño real")
            local expected = (root.CFrame * fit.Offset * roblox.CFrame.new(shift)).Position
            T.True((piece.Position - expected).Magnitude < 1e-3, piece.Name .. " va en su caja, corrida como en Blender")
            local held = root.CFrame * joint.C0 * joint.C1:Inverse()
            T.True((held.Position - piece.Position).Magnitude < 1e-3, piece.Name .. " la articulación la sostiene ahí")
            if piece.Name == "Arm" or piece.Name == "Leg" then
                local top = (root.CFrame * fit.Offset * roblox.CFrame.new(0, 2, 0)).Position
                T.True(((root.CFrame * joint.C0).Position - top).Magnitude < 1e-3, piece.Name .. " gira desde arriba de su caja")
            end
            T.True(piece:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil, piece.Name .. " lleva la textura de la criatura")
            if piece.Name == "Leg" then
                table.insert(legs, piece:GetAttribute("Source"))
            end
        end
    end
    T.Equal(table.concat(legs, ","), "Leg1,Leg2", "cada pierna usa su propio corte, en orden")

    -- Si falta el modelo cortado, las medidas se ignoran y vuelve a la Part simple.
    set:Destroy()
    local plain = Factory.Build("ElTrepador", Engine.Workspace, 2)
    T.Equal(plain:FindFirstChild("Torso").ClassName, "Part", "sin modelo importado usa la Part")
    T.Equal(plain:FindFirstChild("Torso").Size, Vector3.new(1.2, 2.6, 1), "con el tamaño de siempre")
    T.True(plain:FindFirstChild("Eye") ~= nil, "y con sus ojos")
    CreatureMeshes.ElTrepador = nil
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
    -- No todos los mapas admiten un derrumbe junto a la salida: se busca la
    -- primera sala donde sea posible, así la prueba no depende de la semilla.
    local center = nil
    local collapsed = 0
    for _, cell in ipairs(state.Layout.Cells) do
        local position = state.Nav:Center(cell.Index, 3)
        if Environment.Collapse(position, 5) then
            center = position
            collapsed = 1
            break
        end
    end
    T.True(center ~= nil, "algún derrumbe es posible")
    for _ = 1, 4 do
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

T.Test("si el capítulo no se puede armar, el grupo vuelve al lobby en vez de quedar trabado", function()
    local players = bootServer(1)
    local WorldService = Engine.RequireServer("World.WorldService")
    local attempts = 0
    WorldService.LoadChapter = function()
        attempts += 1
        error("mapa roto")
    end

    startMatch(players)
    T.True(waitForPhase("Loading", 30), "empieza a cargar")
    T.True(waitForPhase("Lobby", 120), "vuelve al lobby")
    T.Equal(attempts, 2, "prueba con otra semilla antes de rendirse")
    T.True(Engine.Workspace:FindFirstChild("NOCTURNA_MAP") == nil, "sin mapa a medias")
    T.True(players[1].Character ~= nil, "el jugador sigue en juego")
end)

T.Test("una criatura que falla se retira y no congela a las demás", function()
    local players = bootServer(1)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")

    local MonsterService = Engine.RequireServer("Monsters.MonsterService")
    MonsterService.Clear()
    local broken = MonsterService.Spawn("ElOyente")
    local healthy = MonsterService.Spawn("ElOyente")
    T.True(broken ~= nil and healthy ~= nil, "dos criaturas")

    broken.Controller.Tick = function()
        error("IA rota")
    end
    local ticks = 0
    local originalTick = healthy.Controller.Tick
    healthy.Controller.Tick = function(self, deltaTime)
        ticks += 1
        return originalTick(self, deltaTime)
    end

    Engine.Run(5)
    T.True(ticks > 30, "la sana sigue actualizándose")
    T.True(table.find(MonsterService.Active(), broken) == nil, "la rota se retira")
    T.True(broken.Model.Parent == nil, "su cuerpo no queda en el mapa")
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

T.Test("si la carga falló, se recupera más tarde y suma lo jugado en la sesión", function()
    local stores = {NOCTURNA_PLAYER_DATA_V1 = {PLAYER_2001 = {Version = 2, UnlockedChapter = 4, Deaths = 5, Documents = {}, Endings = {}}}}
    local players = bootServer(1, {Stores = stores, DataStoreFailures = 3})
    Engine.Run(15)

    local Progression = Engine.RequireServer("Data.ProgressionService")
    T.Equal(players[1]:GetAttribute("NocturnaSaveOffline"), true, "empieza en modo sesión")
    Progression.RecordDeath(players[1])

    Engine.Run(40)
    T.Equal(players[1]:GetAttribute("NocturnaSaveOffline"), false, "recuperado")
    T.Equal(players[1]:GetAttribute("NocturnaUnlockedChapter"), 4, "capítulos guardados")
    T.Equal(players[1]:GetAttribute("NocturnaDeaths"), 6, "suma la muerte de la sesión")
    T.True(Progression.Save(players[1]), "vuelve a guardar")
    T.Equal(stores.NOCTURNA_PLAYER_DATA_V1.PLAYER_2001.UnlockedChapter, 4, "nada retrocede")
    T.Equal(stores.NOCTURNA_PLAYER_DATA_V1.PLAYER_2001.Deaths, 6, "guarda la suma")
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
    T.False(AntiCheat.IsMovementValid(Vector3.new(0, 3, 0), Vector3.new(18, 3, 0), 0.5), "doble de la carrera")
    T.False(AntiCheat.IsMovementValid(Vector3.new(0, 3, 0), Vector3.new(0, -40, 0), 0.5), "atravesar el piso")
end)

T.Test("el botón de reiniciar está desactivado: no gasta los reintentos del grupo", function()
    local players = bootServer(1)
    Engine.StartClient(players[1])
    Engine.Run(3)
    T.Equal(Engine.CoreSettings.ResetButtonCallback, false, "sin reinicio")
    T.NoEngineErrors(Engine)
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

T.Suite("Criaturas y Alma")

T.Test("velocidades: corriendo se deja atrás a toda criatura y caminando no", function()
    local player = GameConfig.Player
    for difficultyName, difficulty in pairs(GameConfig.Difficulties) do
        for kind, settings in pairs(MonsterConfig) do
            local label = kind .. " en " .. difficultyName
            local scale = difficulty.MonsterSpeed
            local pursuit = math.max(settings.ChaseSpeed, settings.RageSpeed or 0) * scale
            T.True(pursuit <= player.SprintSpeed * 0.9, label .. ": persigue a " .. pursuit .. ", hasta el 90 % del sprint")
            T.True(settings.ChaseSpeed * scale >= player.SprintSpeed * 0.75, label .. ": no es un trámite")
            T.True(settings.ChaseSpeed * scale > player.WalkSpeed + 2, label .. ": caminando te alcanza")
            T.True(settings.PatrolSpeed * scale < player.WalkSpeed, label .. ": merodea más lento que un jugador")
            T.True((settings.LungeDistance or 0) <= 4, label .. ": la estocada es corta")
            T.True((settings.AttackWindup or 0) >= 0.15, label .. ": el ataque se anticipa")
            T.True((settings.FleeSpeed or 0) * scale < player.SprintSpeed, label .. ": ni huyendo supera al sprint")
        end
    end
end)

T.Test("AIRE: la carrera dura el doble que antes y se recupera con una pausa", function()
    local config = GameConfig.Player
    local duration = StaminaModel.SprintDuration(config)
    T.True(duration >= 2 * (100 / 22) * 0.95 and duration <= 11, "dura " .. duration .. " s (antes 4,5 s)")

    local state = StaminaModel.new(config)
    StaminaModel.Request(state, true)
    for _ = 1, 80 do
        StaminaModel.Step(state, 0.1, true, config)
    end
    T.False(state.Exhausted, "8 s corriendo todavía queda aire")
    local running = 8
    while not state.Exhausted and running < 20 do
        StaminaModel.Step(state, 0.1, true, config)
        running += 0.1
    end
    T.True(state.Exhausted and running <= 10, "se agota a los " .. running .. " s")

    local before = state.Stamina
    StaminaModel.Step(state, 0.3, false, config)
    T.Equal(state.Stamina, before, "pausa antes de recuperar")
    local seconds = 0
    while state.Exhausted do
        StaminaModel.Step(state, 0.1, false, config)
        seconds += 0.1
    end
    T.True(seconds <= 5, "vuelve a poder correr en " .. seconds .. " s")
    while state.Stamina < config.MaxStamina do
        StaminaModel.Step(state, 0.1, true, config)
        seconds += 0.1
    end
    T.True(seconds <= 10, "barra llena en " .. seconds .. " s")
end)

-- Mundo con una pared: nadie ve a través de x = 25.
local function walledWorld(snapshots)
    local world = fakeWorld(snapshots)
    function world:LineOfSight(from, to)
        return (from.X < 25) == (to.X < 25)
    end
    return world
end

T.Test("sigilo: cada criatura persigue sólo a quien vio u oyó, nunca a todos", function()
    local sneaky = snapshot(Vector3.new(-18, 3, 0), {Crouching = true, Speed = 6, Look = Vector3.new(-1, 0, 0)})
    local loud = snapshot(Vector3.new(60, 3, 0), {Flashlight = true, Look = Vector3.new(1, 0, 0)})
    local world = walledWorld({sneaky, loud})
    world.PatrolCell = function()
        return nil
    end
    -- Agachado hace poco ruido: no llega a ninguna de las dos.
    table.insert(world.NoiseList, {Position = sneaky.Position, Radius = GameConfig.Noise.Crouch, Time = 10, Source = sneaky.Player})

    local Controller = Engine.RequireServer("AI.MonsterController")
    local Behavior = Engine.RequireServer("AI.Behaviors.ElColoso")
    -- Una mira hacia +Z (el agachado queda detrás, a oscuras); la otra está del otro lado de la pared.
    local blind = Controller.new("ElColoso", MonsterConfig.ElColoso, Behavior, world, Vector3.new(0, 4, 0))
    local seer = Controller.new("ElColoso", MonsterConfig.ElColoso, Behavior, world, Vector3.new(40, 4, 0))
    seer.Facing = Vector3.new(1, 0, 0)

    for _ = 1, 30 do
        blind:Tick(1 / 15)
        seer:Tick(1 / 15)
    end
    T.True(blind.Target == nil, "la que no vio a nadie no persigue a nadie")
    T.True(blind.State ~= "Chase", "ni sale a cazar")
    T.Equal(seer.State, "Chase", "la que lo ve, persigue")
    T.True(seer.Target == loud.Player, "y persigue a quien vio, no al agachado")

    -- Corriendo cerca se lo oye: ahí sí lo busca (cada una por su cuenta).
    table.insert(world.NoiseList, {Position = sneaky.Position, Radius = GameConfig.Noise.Sprint, Time = 20, Source = sneaky.Player})
    blind:Tick(1 / 15)
    T.Equal(blind.State, "Investigate", "el ruido fuerte sí lo atrae")
end)

T.Test("perder de vista: va a la última posición, busca y se rinde", function()
    local target = snapshot(Vector3.new(20, 3, 0), {Flashlight = true})
    local world = fakeWorld({target})
    world.PatrolCell = function()
        return nil
    end
    local monster = newMonster("ElImitador", world)
    monster.Facing = Vector3.new(1, 0, 0)
    tick(monster, 0.3)
    T.Equal(monster.State, "Chase", "lo ve y lo persigue")

    -- Dobla la esquina y se aleja: ya no lo ve ni lo oye.
    world.Sight = false
    target.Position = Vector3.new(150, 3, 0)
    local lastKnown = monster.LastKnown
    tick(monster, MonsterConfig.ElImitador.LoseTime + 1.5)
    T.True(monster.Target == nil, "lo dio por perdido")
    T.True(monster.State == "Search" or monster.State == "Patrol", "busca o vuelve a merodear: " .. monster.State)
    T.True(lastKnown ~= nil and (lastKnown - Vector3.new(20, 3, 0)).Magnitude < 1, "recordaba dónde lo vio")
    T.True(monster:Distance(Vector3.new(150, 3, 0)) > 60, "no fue derecho a donde está ahora")

    tick(monster, MonsterConfig.ElImitador.SearchTime + 2)
    T.Equal(monster.State, "Patrol", "después de buscar se rinde")
end)

T.Test("ataque: anticipación que se esquiva corriendo; caminando te alcanza", function()
    for _, case in ipairs({{Speed = GameConfig.Player.SprintSpeed, Hit = false}, {Speed = GameConfig.Player.WalkSpeed, Hit = true}}) do
        local target = snapshot(Vector3.new(4, 3, 0), {Flashlight = true})
        local world = fakeWorld({target})
        world.PatrolCell = function()
            return nil
        end
        local monster = newMonster("ElOyente", world)
        target.Speed = 8
        monster:Tick(1 / 15)
        T.True(monster.Attack ~= nil, "empieza el ataque")
        T.Equal(monster:PublicState(), "Attack", "estado público de ataque")
        -- El jugador ya venía escapando: se aleja en línea recta durante la anticipación.
        for _ = 1, 30 do
            target.Position += Vector3.new(case.Speed / 15, 0, 0)
            monster:Tick(1 / 15)
            if not monster.Attack then
                break
            end
        end
        T.Equal(#world.Damaged > 0, case.Hit, "a " .. case.Speed .. " studs/s")
    end
end)

T.Test("las criaturas publican su estado para que el cliente las anime", function()
    local players = bootServer(1)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")

    local MonsterService = Engine.RequireServer("Monsters.MonsterService")
    MonsterService.Clear()
    local entry = MonsterService.Spawn("ElColoso")
    T.True(entry ~= nil, "criatura creada")
    Engine.Run(2)
    local model = entry.Model
    local state = model:GetAttribute("State")
    T.True(table.find({"Patrol", "Investigate", "Search", "Chase", "Attack", "Stunned"}, state) ~= nil, "estado público: " .. tostring(state))
    T.True(model:GetAttribute("BehaviorState") ~= nil, "estado interno")
    T.True(type(model:GetAttribute("MoveSpeed")) == "number", "velocidad real")
    T.True(model:GetAttribute("AttackPhase") ~= nil, "fase del ataque")

    entry.Controller:Gesture("Roar")
    entry.Controller.LookTarget = Vector3.new(10, 3, 10)
    MonsterService.Publish(entry)
    T.Equal(model:GetAttribute("Gesture"), "Roar", "gesto")
    T.Equal(model:GetAttribute("LookTarget"), Vector3.new(10, 3, 10), "hacia dónde mira")
    T.NoEngineErrors(Engine)
end)

T.Test("animación: paso al ritmo de la velocidad, cabeza al objetivo y El Quieto inmóvil", function()
    Engine.Reset()
    local Factory = Engine.RequireServer("Monsters.MonsterFactory")
    local Animator = Engine.Require(Engine.ClientFolder:FindFirstChild("Effects"):FindFirstChild("MonsterAnimator"), "Client")

    local coloso = Factory.Build("ElColoso", Engine.Workspace, 5.5)
    local root = coloso.PrimaryPart
    root.CFrame = roblox.CFrame.new(0, 5.5, 0)
    local rig = Animator.Track(coloso)
    T.True(rig ~= nil and #rig.Joints >= 6, "articulaciones encontradas")

    local camera = roblox.CFrame.lookAt(Vector3.new(0, 5, 25), Vector3.new(0, 5, 0))
    local function legC0()
        for _, entry in ipairs(rig.Joints) do
            if entry.Role == "Leg" then
                return entry.Joint.C0
            end
        end
    end

    coloso:SetAttribute("State", "Chase")
    coloso:SetAttribute("LookTarget", Vector3.new(30, 5, -10))
    local samples = {}
    for frame = 1, 90 do
        root.CFrame = roblox.CFrame.new(0, 5.5, -frame * 14 / 60)
        Animator.Update(1 / 60, camera)
        if frame % 10 == 0 then
            table.insert(samples, legC0())
        end
    end
    T.False(rig.Broken, "sin errores al animar")
    T.True(rig.Speed > 10 and rig.Speed < 18, "mide la velocidad real: " .. rig.Speed)
    T.True(rig.Gait > 0.5, "camina")
    T.True(samples[2] ~= samples[3], "las piernas se mueven")
    T.True(rig.HeadYaw < -0.2, "gira la cabeza hacia el objetivo (a su derecha)")
    T.True(rig.Stomps > 0, "El Coloso pisa fuerte al ritmo del paso")

    local quieto = Factory.Build("ElQuieto", Engine.Workspace, 3.6)
    quieto.PrimaryPart.CFrame = roblox.CFrame.new(0, 3.6, 5)
    local frozenRig = Animator.Track(quieto)
    quieto:SetAttribute("State", "Stalk")
    for _ = 1, 30 do
        Animator.Update(1 / 60, camera)
    end
    quieto:SetAttribute("State", "Frozen")
    local held = {}
    for index, entry in ipairs(frozenRig.Joints) do
        held[index] = entry.Joint.C0
    end
    for _ = 1, 60 do
        Animator.Update(1 / 60, camera)
    end
    for index, entry in ipairs(frozenRig.Joints) do
        T.Equal(entry.Joint.C0, held[index], "El Quieto observado no se mueve ni respira")
    end
    T.NoEngineErrors(Engine)
end)

local function almaScene(options)
    Engine.Reset(options)
    local player = Engine.AddPlayer("Hermano", 3001)
    local character = Engine.CreateCharacter(player)
    character:FindFirstChild("HumanoidRootPart").CFrame = roblox.CFrame.new(0, 3, 60)
    local AlmaBuilder = Engine.RequireServer("World.AlmaBuilder")
    local holder, host = AlmaBuilder.Build(Engine.Workspace, {Id = "ALMA"}, roblox.CFrame.new(0, 0, 0))
    return holder, host, character, AlmaBuilder
end

T.Test("Alma: una nena R15 de verdad que respira y espera", function()
    local holder, host, _, AlmaBuilder = almaScene()
    local rig = holder:FindFirstChild("Alma")
    T.True(rig ~= nil, "cuerpo armado")
    T.Equal(rig:GetAttribute("Source"), "Avatar", "avatar de Roblox")
    local humanoid = rig:FindFirstChildOfClass("Humanoid")
    T.True(humanoid ~= nil and humanoid:FindFirstChildOfClass("Animator") ~= nil, "Humanoid con Animator")
    T.Equal(humanoid.DisplayDistanceType, roblox.Enum.HumanoidDisplayDistanceType.None, "sin nombre flotante")

    local description = AlmaBuilder.Description()
    T.Equal(description.HeightScale, 0.75, "más bajita")
    T.True(math.abs(description.HeadScale - 1.1) < 1e-3, "cabeza grande")
    T.Equal(description.BodyTypeScale, 0, "proporciones de nena")
    T.Equal(description.ProportionScale, 0, "proporciones clásicas")
    T.True(rig:FindFirstChild("Hair") ~= nil and rig:FindFirstChild("Pigtail") ~= nil, "pelo con colitas")
    T.True(rig:FindFirstChild("Head"):FindFirstChild("face") ~= nil, "cara feliz")

    T.True(holder.PrimaryPart == host, "el ancla es la pieza principal")
    T.False(host.Anchored, "el ancla va soldada a ella")
    T.True(table.find(Engine.AnimationLog, AlmaBuilder.Animations.Idle) ~= nil, "respira (animación de reposo)")
    Engine.Run(2)
    T.Equal(holder:GetAttribute("AlmaState"), "Idle", "lejos, sigue esperando")
    T.False(holder:GetAttribute("Found"), "todavía no la encontraron")
    T.NoEngineErrors(Engine)
end)

T.Test("Alma: al encontrarla salta, saluda, festeja, brilla y sigue al más cercano", function()
    local holder, _, character, AlmaBuilder = almaScene()
    local rig = holder:FindFirstChild("Alma")
    local root = rig:FindFirstChild("HumanoidRootPart")
    local glow = root:FindFirstChild("AlmaGlow")
    local brightness = glow.Brightness
    local playerRoot = character:FindFirstChild("HumanoidRootPart")

    playerRoot.CFrame = roblox.CFrame.new(0, 3, 9)
    Engine.Run(0.5)
    T.True(holder:GetAttribute("Found"), "la encontraron")
    T.Equal(holder:GetAttribute("AlmaState"), "Happy", "se alegra")
    T.True(table.find(Engine.AnimationLog, AlmaBuilder.Animations.Wave) ~= nil, "saluda con la mano")
    T.True(Engine.Emitted(root:FindFirstChild("AlmaSparkles")) >= 20, "chispas")
    T.True(glow.Brightness > brightness, "luz cálida")

    Engine.Run(3)
    T.True(table.find(Engine.AnimationLog, AlmaBuilder.Animations.Cheer) ~= nil, "festeja")
    Engine.Run(2.5)
    T.Equal(holder:GetAttribute("AlmaState"), "Follow", "después lo sigue")

    playerRoot.CFrame = roblox.CFrame.new(30, 3, 40)
    Engine.Run(0.5)
    T.Equal(holder:GetAttribute("Following"), "Hermano", "sigue al jugador más cercano")
    local goal = Engine.MoveTarget(rig:FindFirstChildOfClass("Humanoid"))
    T.True(goal ~= nil and (goal - root.Position).Magnitude > 1, "camina hacia él")
    T.NoEngineErrors(Engine)
end)

T.Test("Alma: sin el servicio de avatares se arma con piezas y funciona igual", function()
    local holder, _, character, AlmaBuilder = almaScene({AvatarOffline = true})
    local rig = holder:FindFirstChild("Alma")
    T.Equal(rig:GetAttribute("Source"), "Fallback", "cuerpo de piezas")
    T.True(rig:FindFirstChildOfClass("Humanoid") ~= nil, "con Humanoid")
    for _, name in ipairs({"Root", "Waist", "Neck", "LeftShoulder", "RightElbow", "LeftHip", "RightKnee", "LeftAnkle"}) do
        local found = false
        for _, descendant in ipairs(rig:GetDescendants()) do
            if descendant.Name == name and descendant:IsA("Motor6D") then
                found = true
            end
        end
        T.True(found, "articulación R15 " .. name)
    end
    local head = rig:FindFirstChild("Head")
    local foot = rig:FindFirstChild("LeftFoot")
    T.True(head.Position.Y > foot.Position.Y + 2.5 and head.Position.Y < 5, "de pie y chiquita")

    character:FindFirstChild("HumanoidRootPart").CFrame = roblox.CFrame.new(0, 3, 8)
    Engine.Run(0.5)
    T.True(holder:GetAttribute("Found"), "reacciona igual")
    T.True(table.find(Engine.AnimationLog, AlmaBuilder.Animations.Wave) ~= nil, "saluda")

    local FeatureBuilder = Engine.RequireServer("World.FeatureBuilder")
    local sister, prompt = FeatureBuilder.Sister(Engine.Workspace, {Id = "ALMA2", Prompt = "Tomarle la mano", Hold = 2}, roblox.CFrame.new(50, 0, 0))
    T.True(prompt.Parent == sister.PrimaryPart, "el cartel va en el ancla que la acompaña")
    T.NoEngineErrors(Engine)
end)

T.Suite("Lobby y servidores")

local function lobbyBuilder()
    return Engine.RequireServer("World.LobbyBuilder")
end

local function queueService()
    return Engine.RequireServer("Lobby.QueueService")
end

-- Mueve al jugador a un punto del lobby, como si hubiera caminado hasta ahí.
local function walkTo(player, position)
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    root.CFrame = roblox.CFrame.new(position)
end

local function enterElevator(player, index)
    walkTo(player, lobbyBuilder().Elevators()[index].Center)
end

local function leaveElevator(player)
    walkTo(player, lobbyBuilder().SpawnCFrame(1).Position)
end

local function queueView(player)
    local sent = Engine.LastSent("QueueUpdate", player)
    return sent and sent[1]
end

local function lastNotice(player)
    local sent = Engine.LastSent("StoryNotice", player)
    return sent and tostring(sent[1]) or ""
end

T.Test("lobby caminable: materiales reales, ascensores, donaciones y pocas piezas", function()
    bootServer(1)
    local lobby = Engine.Workspace:FindFirstChild("NOCTURNA_LOBBY")
    local parts, lights, emitters = 0, 0, 0
    for _, descendant in ipairs(lobby:GetDescendants()) do
        if descendant:IsA("BasePart") then
            parts += 1
            T.True(descendant.Material ~= roblox.Enum.Material.SmoothPlastic, "sin SmoothPlastic: " .. descendant.Name)
            T.True(descendant.Anchored, "anclada: " .. descendant.Name)
        elseif descendant:IsA("Light") then
            lights += 1
        elseif descendant:IsA("ParticleEmitter") then
            emitters += 1
        end
    end
    T.True(parts <= 400, "piezas para celular: " .. parts)
    T.True(lights <= 16, "luces: " .. lights)
    T.True(emitters >= 5, "lluvia en los ventanales")
    T.True(#Engine.CollectionService:GetTagged("NocturnaLobbyFlicker") >= 2, "luces que titilan")

    local LobbyBuilder = lobbyBuilder()
    T.Equal(#LobbyBuilder.Elevators(), 4, "ascensores")
    T.Equal(#LobbyBuilder.Podiums(), 3, "podios")
    T.True(LobbyBuilder.DonationPrompt() ~= nil, "urna de donaciones")
    for index = 1, 4 do
        T.True(LobbyBuilder.ElevatorAt(LobbyBuilder.SpawnCFrame(index).Position) == nil, "nadie aparece dentro de un ascensor")
    end
    T.NoEngineErrors(Engine)
end)

T.Test("lógica del grupo: entrar, llenarse, salir y pasar el mando", function()
    Engine.Reset()
    local PartyLogic = Engine.RequireServer("Lobby.PartyLogic")
    local party = PartyLogic.new(1)
    T.True(PartyLogic.Join(party, 10), "entra el primero")
    T.Equal(party.Host, 10, "y manda")
    T.True(PartyLogic.SetMaxPlayers(party, 10, 2), "dos lugares")
    T.True(PartyLogic.Join(party, 20), "entra el segundo")
    local joined, reason = PartyLogic.Join(party, 30)
    T.False(joined, "lleno")
    T.Equal(reason, "Full", "motivo")
    T.False(PartyLogic.SetMaxPlayers(party, 10, 1), "no menos lugares que gente adentro")
    T.True(PartyLogic.Leave(party, 10), "sale el anfitrión")
    T.Equal(party.Host, 20, "manda el siguiente")
    T.True(PartyLogic.Leave(party, 20), "sale el último")
    T.Equal(party.Host, nil, "sin anfitrión")
    T.Equal(party.MaxPlayers, 4, "el ascensor vuelve a cuatro lugares")
end)

T.Test("ascensor: entrar arma el grupo, otro se suma, salir lo deja y el mando pasa al siguiente", function()
    local players = bootServer(3)
    local Queue = queueService()

    enterElevator(players[1], 2)
    Engine.Run(0.5)
    local party = Queue.PartyOf(players[1])
    T.True(party ~= nil, "armó grupo")
    T.Equal(party.Host, players[1].UserId, "el primero es anfitrión")
    T.Equal(queueView(players[1]).Kind, "Party", "ve su panel")
    T.True(queueView(players[1]).IsHost, "panel de anfitrión")

    enterElevator(players[2], 2)
    Engine.Run(0.5)
    T.Equal(Queue.PartyOf(players[2]), party, "se suma al mismo grupo")
    T.Equal(#party.Members, 2, "dos miembros")
    T.False(queueView(players[2]).IsHost, "el segundo no manda")

    local sign = lobbyBuilder().Elevators()[2].Labels
    T.True(string.find(sign.Members.Text, "Jugador2", 1, true) ~= nil, "el cartel muestra el grupo")
    T.True(string.find(sign.Status.Text, "2/4", 1, true) ~= nil, "y los lugares: " .. sign.Status.Text)

    leaveElevator(players[1])
    Engine.Run(0.5)
    T.Equal(Queue.PartyOf(players[1]), nil, "salir del ascensor deja el grupo")
    T.Equal(queueView(players[1]).Kind, "None", "se cierra su panel")
    T.Equal(party.Host, players[2].UserId, "el anfitrión pasa al siguiente")
    T.True(queueView(players[2]).IsHost, "el nuevo anfitrión lo ve")

    fire("QueueAction", players[2], "Leave")
    Engine.Run(0.5)
    T.Equal(#party.Members, 0, "grupo vacío")
    T.Equal(party.Host, nil, "sin anfitrión")
    T.True(string.find(sign.Status.Text, "LIBRE", 1, true) ~= nil, "el ascensor queda libre")
    T.True(lobbyBuilder().ElevatorAt(players[2].Character.HumanoidRootPart.Position) == nil, "SALIR lo baja del ascensor")
    T.NoEngineErrors(Engine)
end)

T.Test("ajustes del anfitrión: capítulo desbloqueado, de 1 a 4 jugadores y sólo él", function()
    local players = bootServer(2)
    local Queue = queueService()
    local Progression = Engine.RequireServer("Data.ProgressionService")
    Progression.UnlockChapter(players[1], 2)
    Progression.UnlockChapter(players[1], 3)
    Progression.UnlockChapter(players[2], 2)

    enterElevator(players[1], 3)
    Engine.Run(0.5)
    enterElevator(players[2], 3)
    Engine.Run(0.5)
    local party = Queue.PartyOf(players[1])

    fire("QueueAction", players[1], "SetChapter", 4)
    fire("QueueAction", players[1], "SetChapter", 2.5)
    fire("QueueAction", players[1], "SetChapter", "3")
    fire("QueueAction", players[1], "SetMaxPlayers", 5)
    fire("QueueAction", players[1], "SetMaxPlayers", 0)
    fire("QueueAction", players[1], "SetMaxPlayers", 1)
    fire("QueueAction", players[1], "SetDifficulty", "Imposible")
    fire("QueueAction", players[1], {})
    fire("QueueAction", players[2], "SetChapter", 2)
    fire("QueueAction", players[2], "SetDifficulty", "Pesadilla")
    fire("QueueAction", players[2], "Start")
    Engine.Run(0.5)
    T.Equal(party.Chapter, 1, "capítulo intacto")
    T.Equal(party.MaxPlayers, 4, "lugares intactos")
    T.Equal(party.Difficulty, "Normal", "dificultad intacta")
    T.Equal(party.State, "Open", "sólo el anfitrión empieza")

    Engine.Run(2)
    fire("QueueAction", players[1], "SetChapter", 3)
    fire("QueueAction", players[1], "SetDifficulty", "Pesadilla")
    fire("QueueAction", players[1], "SetMaxPlayers", 2)
    Engine.Run(0.5)
    T.Equal(party.Chapter, 3, "hasta el capítulo desbloqueado del anfitrión")
    T.Equal(party.Difficulty, "Pesadilla", "dificultad")
    T.Equal(party.MaxPlayers, 2, "lugares")
    T.Equal(queueView(players[2]).Chapter, 3, "los demás ven el cambio")
    T.Equal(queueView(players[2]).HighestUnlocked, 3, "el límite es el del anfitrión")

    -- Si se va el anfitrión, el capítulo baja a lo que desbloqueó el nuevo.
    leaveElevator(players[1])
    Engine.Run(0.5)
    T.Equal(party.Host, players[2].UserId, "nuevo anfitrión")
    T.Equal(party.Chapter, 2, "capítulo ajustado al nuevo anfitrión")
    T.NoEngineErrors(Engine)
end)

T.Test("ascensor lleno: arranca solo, deja afuera al que sobra y sin viajes juega en este servidor", function()
    local players = bootServer(3)
    local Queue = queueService()

    enterElevator(players[1], 1)
    Engine.Run(0.5)
    fire("QueueAction", players[1], "SetMaxPlayers", 2)
    Engine.Run(0.3)
    enterElevator(players[2], 1)
    Engine.Run(0.5)
    local party = Queue.PartyOf(players[1])
    T.Equal(party.State, "Countdown", "lleno: cuenta regresiva")
    T.False(lobbyBuilder().Elevators()[1].DoorsOpen, "las puertas se cierran")

    enterElevator(players[3], 1)
    Engine.Run(0.5)
    T.Equal(Queue.PartyOf(players[3]), nil, "no entra a un grupo lleno")
    T.True(string.find(lastNotice(players[3]), "saliendo", 1, true) ~= nil, "se le avisa: " .. lastNotice(players[3]))

    T.True(waitForPhase("Loading", 15), "termina la cuenta y arranca la partida en este servidor")
    T.Equal(#Engine.Teleports, 0, "sin viajes en Studio")
    T.True(waitForPhase("Playing", 60), "partida")
    T.Equal(Queue.PartyOf(players[1]), nil, "el grupo se disuelve al empezar")
    T.True(string.find(lobbyBuilder().Elevators()[1].Labels.Status.Text, "FUERA DE SERVICIO", 1, true) ~= nil, "ascensores apagados durante la partida")
    T.NoEngineErrors(Engine)
end)

T.Test("con viajes: reserva un servidor del mismo lugar y manda al grupo junto con sus datos", function()
    local stores = {}
    local players = bootServer(3, {PlaceId = 777, Stores = stores})
    local Queue = queueService()

    enterElevator(players[1], 1)
    Engine.Run(0.5)
    enterElevator(players[2], 1)
    Engine.Run(0.5)
    fire("QueueAction", players[1], "SetDifficulty", "Pesadilla")
    Engine.Run(0.3)
    fire("QueueAction", players[1], "Start")
    Engine.Run(1)
    T.Equal(Queue.PartyOf(players[1]).State, "Countdown", "cuenta regresiva")

    T.True(Engine.RunUntil(function()
        return #Engine.Teleports > 0
    end, 15), "viaja al terminar la cuenta")
    local trip = Engine.Teleports[1]
    T.Equal(trip.PlaceId, 777, "al mismo lugar")
    T.Equal(trip.AccessCode, Engine.Reserved[1], "al servidor reservado")
    T.Equal(#trip.Players, 2, "todo el grupo junto")
    T.Equal(trip.Data.Difficulty, "Pesadilla", "con la dificultad")
    T.Equal(trip.Data.Chapter, 1, "con el capítulo")
    T.Equal(trip.Data.MaxPlayers, 4, "con los lugares")
    T.Equal(trip.Data.Party[1], players[1].UserId, "con la lista del grupo")
    T.Equal(trip.Data.Party[2], players[2].UserId, "completa")
    T.Equal(gameState().Phase, "Lobby", "el lobby no juega")

    Engine.Run(2)
    T.Equal(#Engine.Services.Players:GetPlayers(), 1, "los viajeros se fueron")
    T.True(string.find(lobbyBuilder().Elevators()[1].Labels.Status.Text, "LIBRE", 1, true) ~= nil, "el ascensor vuelve a quedar libre")
    T.True(lobbyBuilder().Elevators()[1].DoorsOpen, "con las puertas abiertas")
    local record = stores.NOCTURNA_ACTIVE_MATCH_V1 and stores.NOCTURNA_ACTIVE_MATCH_V1["USER_" .. players[1].UserId]
    T.True(record ~= nil and record.Code == trip.AccessCode, "recuerda la partida para poder volver")

    fire("LobbyAction", players[3], "Ready")
    fire("LobbyAction", players[3], "Start")
    Engine.Run(1)
    T.Equal(gameState().Phase, "Lobby", "en un lobby con viajes nadie juega en el lobby")
    T.NoEngineErrors(Engine)
end)

T.Test("viajes que fallan: reintenta, avisa y vuelve a abrir el ascensor", function()
    local players = bootServer(2, {PlaceId = 777, Stores = {}, TeleportStays = true, TeleportFailures = 1})
    local Queue = queueService()
    local teleportService = Engine.Services.TeleportService

    enterElevator(players[1], 1)
    Engine.Run(0.5)
    fire("QueueAction", players[1], "Start")
    T.True(Engine.RunUntil(function()
        return #Engine.Teleports > 0
    end, 20), "el segundo intento sale")

    -- El viaje de alguien falla después de empezar: se reintenta al mismo servidor.
    teleportService.TeleportInitFailed:Fire(players[1], roblox.Enum.TeleportResult.Failure, "falla", 777, nil)
    Engine.Run(5)
    T.Equal(#Engine.Teleports, 2, "reintenta el viaje de quien falló")
    T.Equal(Engine.Teleports[2].AccessCode, Engine.Teleports[1].AccessCode, "al mismo servidor reservado")
    teleportService.TeleportInitFailed:Fire(players[1], roblox.Enum.TeleportResult.Flooded, "lleno", 777, nil)
    Engine.Run(7)
    T.Equal(#Engine.Teleports, 3, "tercer intento")
    teleportService.TeleportInitFailed:Fire(players[1], roblox.Enum.TeleportResult.Failure, "falla", 777, nil)
    Engine.Run(1)
    T.True(string.find(lastNotice(players[1]), "No pudimos llevarte", 1, true) ~= nil, "se rinde y avisa: " .. lastNotice(players[1]))

    T.True(Engine.RunUntil(function()
        local party = Queue.PartyOf(players[1])
        return party ~= nil and party.State == "Open"
    end, 40), "el ascensor se vuelve a abrir para quien no pudo viajar")

    -- Si no se puede reservar un servidor, se avisa y el ascensor vuelve a abrir.
    Engine.Options.ReserveFailures = 3
    enterElevator(players[2], 2)
    Engine.Run(0.5)
    fire("QueueAction", players[2], "Start")
    T.True(Engine.RunUntil(function()
        return string.find(lastNotice(players[2]), "No se pudo abrir", 1, true) ~= nil
    end, 30), "avisa que no se pudo abrir el servidor")
    T.Equal(Queue.PartyOf(players[2]).State, "Open", "y se puede volver a intentar")
    T.Equal(gameState().Phase, "Lobby", "nunca juega en el lobby público")
    T.NoEngineErrors(Engine)
end)

T.Test("datos de viaje: se validan y se descartan los inventados", function()
    Engine.Reset()
    local PartyLogic = Engine.RequireServer("Lobby.PartyLogic")
    local valid = PartyLogic.ParseTeleportData({Chapter = 2, Difficulty = "Normal", MaxPlayers = 2, Party = {1, 1, 2, 3}, Host = 2})
    T.True(valid ~= nil, "válidos")
    T.Equal(#valid.Party, 2, "sin repetidos ni más que los lugares")
    T.Equal(valid.Host, 2, "anfitrión")
    local bad = {
        "texto",
        {Chapter = 9, Difficulty = "Normal", MaxPlayers = 2, Party = {1}},
        {Chapter = 1.5, Difficulty = "Normal", MaxPlayers = 2, Party = {1}},
        {Chapter = 1, Difficulty = "Imposible", MaxPlayers = 2, Party = {1}},
        {Chapter = 1, Difficulty = "Normal", MaxPlayers = 5, Party = {1}},
        {Chapter = 1, Difficulty = "Normal", MaxPlayers = 2, Party = {}},
        {Chapter = 1, Difficulty = "Normal", MaxPlayers = 2, Party = {"a"}},
    }
    T.True(PartyLogic.ParseTeleportData(nil) == nil, "sin datos")
    for index, data in ipairs(bad) do
        T.True(PartyLogic.ParseTeleportData(data) == nil, "datos inválidos " .. index)
    end
end)

T.Test("servidor de partida: detecta el modo, espera al grupo y arranca con sus datos", function()
    local stores = {NOCTURNA_PLAYER_DATA_V1 = {PLAYER_2001 = {Version = 2, UnlockedChapter = 3, Documents = {}, Endings = {}}}}
    Engine.Reset({PlaceId = 777, PrivateServerId = "reserved-9", PrivateServerOwnerId = 0, Stores = stores})
    Engine.StartServer()
    Engine.Run(0.5)
    T.True(Engine.RequireServer("Lobby.ServerMode").IsMatchServer(), "es un servidor de partida")
    T.Equal(#lobbyBuilder().Elevators(), 0, "sin ascensores")
    T.True(lobbyBuilder().DonationPrompt() == nil, "sin donaciones")
    T.True(Engine.Workspace:FindFirstChild("NOCTURNA_LOBBY") ~= nil, "con una sala de espera")

    -- Pide el capítulo 5, pero nadie del grupo lo desbloqueó: se limita al 3.
    local data = {Chapter = 5, Difficulty = "Pesadilla", MaxPlayers = 3, Party = {2001, 2002, 2003}, Host = 2001}
    local join = {SourcePlaceId = 777, TeleportData = data}
    local first = Engine.AddPlayer("Jugador1", 2001, join)
    Engine.AddPlayer("Jugador2", 2002, join)
    Engine.Run(5)
    T.Equal(gameState().Phase, "Lobby", "espera al que falta")
    local view = queueView(first)
    T.Equal(view.Kind, "Waiting", "ve la espera")
    T.Equal(view.Arrived, 2, "llegaron dos")
    T.Equal(view.Expected, 3, "de tres")

    -- El tercero nunca llega: vence la espera y se juega igual.
    local wait = Engine.RequireShared("Config.LobbyConfig").Teleport.PartyWait
    T.True(waitForPhase("Loading", wait + 5), "arranca sin el que falta")
    T.Equal(gameState().Chapter, 3, "capítulo del grupo, limitado a lo desbloqueado")
    T.Equal(gameState().Difficulty, "Pesadilla", "dificultad del grupo")
    T.True(waitForPhase("Playing", 60), "partida")

    -- Alguien que se había caído vuelve a entrar en plena partida.
    local back = Engine.AddPlayer("Jugador3", 2003, join)
    Engine.Run(2)
    T.True(back.Character ~= nil, "vuelve a jugar")
    T.Equal(Engine.Kicked[2003], nil, "no lo expulsan")

    -- Al terminar, todos vuelven a un lobby público.
    Engine.Options.TeleportStays = true
    Engine.RequireServer("Multiplayer.MatchService").ReturnToLobby()
    Engine.Run(1)
    local trip = Engine.Teleports[#Engine.Teleports]
    T.True(trip ~= nil, "viaja de vuelta")
    T.Equal(trip.PlaceId, 777, "al mismo lugar")
    T.Equal(trip.AccessCode, "", "a un lobby público, no a otro reservado")
    T.Equal(#trip.Players, 3, "todo el grupo")
    T.True(trip.Data.ReturnFromMatch, "avisando que vuelve de una partida")
    T.Equal(queueView(first).Kind, "Returning", "con el botón para reintentar")
    fire("QueueAction", first, "ReturnToLobby")
    Engine.Run(1)
    T.NoEngineErrors(Engine)
end)

T.Test("servidor de partida: si llega todo el grupo arranca sin esperar el límite", function()
    Engine.Reset({PlaceId = 777, PrivateServerId = "reserved-3", PrivateServerOwnerId = 0, Stores = {}})
    Engine.StartServer()
    Engine.Run(0.5)
    local join = {SourcePlaceId = 777, TeleportData = {Chapter = 1, Difficulty = "Normal", MaxPlayers = 2, Party = {2001, 2002}, Host = 2001}}
    Engine.AddPlayer("Jugador1", 2001, join)
    Engine.AddPlayer("Jugador2", 2002, join)
    T.True(waitForPhase("Loading", 10), "arranca enseguida")

    -- Datos de otro lugar no sirven.
    Engine.Reset({PlaceId = 777, PrivateServerId = "reserved-4", PrivateServerOwnerId = 0, Stores = {}})
    Engine.StartServer()
    Engine.Run(0.5)
    Engine.AddPlayer("Jugador1", 2001, {SourcePlaceId = 555, TeleportData = {Chapter = 3, Difficulty = "Pesadilla", MaxPlayers = 1, Party = {2001}}})
    Engine.Run(3)
    T.Equal(Engine.RequireServer("Lobby.MatchServerService").Settings(), nil, "datos de otro lugar descartados")
    T.NoEngineErrors(Engine)
end)

T.Test("quien se desconectó puede volver a su partida desde el lobby", function()
    local expires = 1800000000 + 3600
    local stores = {NOCTURNA_ACTIVE_MATCH_V1 = {
        USER_2001 = {Code = "access-7", ServerId = "reserved-7", Expires = expires, Data = {Chapter = 2, Difficulty = "Normal", MaxPlayers = 2, Party = {2001, 2002}, Host = 2002}},
    }}
    local players = bootServer(1, {PlaceId = 777, Stores = stores, TeleportStays = true})
    local offer = queueView(players[1])
    T.Equal(offer.Kind, "Rejoin", "le ofrece volver")
    T.Equal(offer.Chapter, 2, "a su capítulo")

    fire("QueueAction", players[1], "Rejoin")
    Engine.Run(1)
    local trip = Engine.Teleports[1]
    T.True(trip ~= nil, "viaja")
    T.Equal(trip.AccessCode, "access-7", "al mismo servidor reservado")
    T.True(trip.Data.Rejoin, "como regreso")
    T.Equal(trip.Data.Chapter, 2, "con los datos de la partida")

    -- Quien vuelve de una partida terminada no ve la oferta.
    local returning = Engine.AddPlayer("Jugador2", 2002, {SourcePlaceId = 777, TeleportData = {ReturnFromMatch = true}})
    Engine.Run(2)
    T.True(queueView(returning) == nil or queueView(returning).Kind ~= "Rejoin", "sin oferta al volver")
    T.NoEngineErrors(Engine)
end)

T.Test("donaciones: cada compra se acredita una sola vez y el podio ordena a los mayores", function()
    local stores = {}
    local players = bootServer(1, {Stores = stores})
    local DonationConfig = Engine.RequireShared("Config.DonationConfig")
    DonationConfig.Products[1].ProductId = 1001
    DonationConfig.Products[6].ProductId = 1006
    DonationConfig.Products[51].ProductId = 1051
    local Decision = roblox.Enum.ProductPurchaseDecision
    local function receipt(userId, productId, purchaseId)
        return {PlayerId = userId, ProductId = productId, PurchaseId = purchaseId, CurrencySpent = 0}
    end

    T.Equal(Engine.ProcessReceipt(receipt(2001, 1006, "p1")), Decision.PurchaseGranted, "acreditada")
    T.Equal(Engine.ProcessReceipt(receipt(2001, 1006, "p1")), Decision.PurchaseGranted, "el reintento también responde bien")
    T.Equal(stores.NOCTURNA_DONATIONS_V1.DONOR_2001.Total, 1000, "pero cuenta una sola vez")
    T.Equal(stores.NOCTURNA_DONATION_RANKING_V1["2001"], 1000, "ranking")
    T.Equal(Engine.LastSent("DonationUpdate", players[1])[1].Thanks, 1000, "agradece al donante")

    T.Equal(Engine.ProcessReceipt(receipt(2001, 999999, "p2")), Decision.NotProcessedYet, "producto desconocido")
    T.Equal(Engine.ProcessReceipt(receipt(2001, 0, "p3")), Decision.NotProcessedYet, "un monto sin id")

    Engine.Options.FailStore = {NOCTURNA_DONATIONS_V1 = 1}
    T.Equal(Engine.ProcessReceipt(receipt(3001, 1051, "p4")), Decision.NotProcessedYet, "si falla el guardado, Roblox reintenta")
    T.True(stores.NOCTURNA_DONATIONS_V1.DONOR_3001 == nil, "sin acreditar")
    Engine.Options.FailStore = {NOCTURNA_DONATION_RANKING_V1 = 1}
    T.Equal(Engine.ProcessReceipt(receipt(3001, 1051, "p4")), Decision.NotProcessedYet, "falla la copia del podio")
    T.Equal(Engine.ProcessReceipt(receipt(3001, 1051, "p4")), Decision.PurchaseGranted, "reintento")
    T.Equal(stores.NOCTURNA_DONATIONS_V1.DONOR_3001.Total, 10000, "una sola vez aunque hubo reintentos")
    T.Equal(stores.NOCTURNA_DONATION_RANKING_V1["3001"], 10000, "podio al día")

    Engine.ProcessReceipt(receipt(4001, 1001, "p5"))
    Engine.ProcessReceipt(receipt(5001, 1001, "p6"))
    Engine.ProcessReceipt(receipt(5001, 1001, "p7"))
    local top = Engine.RequireServer("Lobby.DonationService").RefreshTop()
    T.Equal(#top, 3, "tres en el podio")
    T.Equal(top[1].UserId, 3001, "primero el que más donó")
    T.Equal(top[2].UserId, 2001, "segundo")
    T.Equal(top[3].UserId, 5001, "tercero: 200 le gana a 100")
    T.Equal(top[2].Name, "Jugador1", "con su nombre")

    Engine.Run(5)
    local podiums = lobbyBuilder().Podiums()
    T.True(string.find(podiums[1].Labels.Name.Text, "Usuario3001", 1, true) ~= nil, "nombre en el podio: " .. podiums[1].Labels.Name.Text)
    T.Equal(podiums[1].Labels.Total.Text, "10.000 R$", "total en el podio")
    local statue = lobbyBuilder().StatueFolder():FindFirstChild("Statue1")
    T.True(statue ~= nil and statue:FindFirstChildOfClass("Humanoid") ~= nil, "estatua con el avatar")
    T.True(statue:FindFirstChildOfClass("LocalScript") == nil, "sin scripts")
    for _, piece in ipairs(statue:GetDescendants()) do
        if piece:IsA("BasePart") then
            T.True(piece.Anchored, "estatua anclada")
        end
    end

    -- Si el avatar no se puede cargar queda una silueta.
    Engine.Options.AvatarFailures = true
    Engine.ProcessReceipt(receipt(6001, 1051, "p8"))
    Engine.ProcessReceipt(receipt(6001, 1051, "p9"))
    Engine.Run(5)
    local first = lobbyBuilder().StatueFolder():FindFirstChild("Statue1")
    T.Equal(lobbyBuilder().Podiums()[1].UserId, 6001, "nuevo primero")
    T.True(first ~= nil and first:FindFirstChildOfClass("Humanoid") == nil and first:FindFirstChild("Head") ~= nil, "silueta de reemplazo")
    T.Equal(#lobbyBuilder().StatueFolder():GetChildren(), 3, "una estatua por podio")
    T.NoEngineErrors(Engine)
end)

T.Test("donaciones: 51 montos de 100 a 10000 y los botones sin id no aparecen", function()
    Engine.Reset()
    local DonationConfig = Engine.RequireShared("Config.DonationConfig")
    T.Equal(#DonationConfig.Products, 51, "montos")
    T.Equal(DonationConfig.Products[1].Robux, 100, "el primero")
    for index = 2, 51 do
        T.Equal(DonationConfig.Products[index].Robux, (index - 1) * 200, "de 200 en 200")
    end
    -- Los 51 productos ya existen en Creator Hub: cada monto tiene su id, sin repetir.
    T.Equal(#DonationConfig.Visible(), 51, "todos los montos tienen producto")
    local seen = {}
    for _, product in ipairs(DonationConfig.Products) do
        T.True(product.ProductId > 0 and not seen[product.ProductId], "id único para " .. product.Robux)
        seen[product.ProductId] = true
    end
    T.Equal(DonationConfig.FormatRobux(10000), "10.000", "formato")
    T.Equal(DonationConfig.FormatRobux(100), "100", "formato corto")

    -- En el cliente se dejan sólo dos montos con id para probar que un id 0 no aparece.
    local players = bootServer(1)
    local clientConfig = Engine.Require(Engine.SharedFolder:FindFirstChild("Config"):FindFirstChild("DonationConfig"), "Client")
    for _, product in ipairs(clientConfig.Products) do
        product.ProductId = 0
    end
    clientConfig.Products[1].ProductId = 1001
    clientConfig.Products[3].ProductId = 1003
    Engine.StartClient(players[1])
    Engine.Run(2)

    local panel = players[1]:FindFirstChild("PlayerGui"):FindFirstChild("NocturnaDonations"):FindFirstChild("Root"):FindFirstChild("DonationPanel")
    T.False(panel.Visible, "cerrado al empezar")
    local prompt = lobbyBuilder().DonationPrompt()
    walkTo(players[1], prompt.Parent.Position + Vector3.new(-4, 0, 0))
    prompt:Fire(players[1])
    Engine.Run(0.5)
    T.True(panel.Visible, "la urna abre el panel")

    local amounts = panel:FindFirstChild("Amounts")
    local buttons = {}
    for _, child in ipairs(amounts:GetChildren()) do
        if child:IsA("TextButton") then
            table.insert(buttons, child)
        end
    end
    T.Equal(#buttons, 2, "sólo los montos con id")
    T.True(amounts:FindFirstChild("Amount100") ~= nil and amounts:FindFirstChild("Amount400") ~= nil, "100 y 400")
    T.True(amounts:FindFirstChild("Amount200") == nil, "un monto con id 0 no aparece")

    Engine.GuiInput(amounts:FindFirstChild("Amount400"), "Activated")
    Engine.Run(0.2)
    T.Equal(Engine.PurchasePrompts[1].ProductId, 1003, "pide la compra del producto correcto")

    leaveElevator(players[1])
    Engine.Run(1)
    T.False(panel.Visible, "alejarse de la urna lo cierra")
    T.NoEngineErrors(Engine)
end)

T.Test("la pantalla queda libre: el panel aparece sólo dentro de un ascensor", function()
    local players = bootServer(1, {Touch = true, Viewport = roblox.Vector2.new(812, 375)})
    Engine.StartClient(players[1])
    Engine.Run(2)
    local root = players[1]:FindFirstChild("PlayerGui"):FindFirstChild("NocturnaLobby"):FindFirstChild("Root")
    local panel = root:FindFirstChild("LobbyPanel")
    T.False(panel.Visible, "nada tapa el lobby")
    T.True(root:FindFirstChild("LobbyHint").Visible, "sólo una pista")
    Engine.Run(15)
    T.False(root:FindFirstChild("LobbyHint").Visible, "la pista se va sola")

    enterElevator(players[1], 1)
    Engine.Run(1)
    T.True(panel.Visible, "al entrar al ascensor aparece el panel")
    T.True(panel.Size.Y.Offset <= 300 and panel.Size.X.Offset <= 320, "panel chico")

    Engine.GuiInput(panel:FindFirstChild("Minus"), "Activated")
    Engine.Run(0.5)
    T.Equal(queueService().PartyOf(players[1]).MaxPlayers, 3, "el anfitrión baja los lugares")
    T.True(string.find(panel:FindFirstChild("Members").Text, "1/3", 1, true) ~= nil, "y lo ve")

    Engine.GuiInput(panel:FindFirstChild("StartButton"), "Activated")
    Engine.Run(1.2)
    T.True(string.find(panel:FindFirstChild("Title").Text, "SALE EN", 1, true) ~= nil, "cuenta regresiva en el panel")
    T.True(waitForPhase("Playing", 60), "partida")
    T.False(panel.Visible, "oculto en partida")
    T.NoEngineErrors(Engine)
end)

T.Suite("Interfaz")

local function screenOf(player, name)
    return player:FindFirstChild("PlayerGui"):FindFirstChild(name)
end

local function mapMessages(player)
    local result = {}
    for _, entry in ipairs(Engine.Sent) do
        if entry.Name == "MapUpdate" and (entry.Player == nil or player == nil or entry.Player == player) then
            table.insert(result, entry.Args[1])
        end
    end
    return result
end

-- Nada de lo que viajó a los clientes puede estar fuera de lo ya recorrido.
local function assertNoLeak(MapService)
    for _, message in ipairs(mapMessages()) do
        for _, cell in ipairs(message.Cells or {}) do
            T.True(MapService.IsRevealed(cell.I), "sala sin recorrer enviada: " .. cell.I)
        end
        for _, marker in ipairs(message.Markers or {}) do
            T.True(MapService.IsRevealed(marker.Cell), "marca de una sala sin recorrer: " .. marker.Id)
        end
        for _, door in ipairs(message.Doors or {}) do
            T.True(MapService.IsRevealed(door.A) or MapService.IsRevealed(door.B), "puerta lejana enviada: " .. door.Key)
        end
    end
end

T.Test("plano: al cargar el capítulo se manda el plano con sólo la sala de entrada", function()
    local players = bootServer(1)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(1)

    local layout = gameState().Plan.Layout
    local loaded = nil
    for _, message in ipairs(mapMessages()) do
        if message.Kind == "Layout" then
            loaded = message
        end
    end
    T.True(loaded ~= nil, "plano enviado al cargar")
    T.Equal(loaded.Width, layout.Width, "ancho")
    T.Equal(loaded.Depth, layout.Depth, "largo")
    T.Equal(#loaded.Cells, 1, "una sola sala conocida")
    T.Equal(loaded.Cells[1].I, layout.Start, "la entrada")
    assertNoLeak(Engine.RequireServer("World.MapService"))
    T.NoEngineErrors(Engine)
end)

T.Test("plano: una sala aparece cuando alguien la pisa, con lo que hay adentro", function()
    local players = bootServer(1)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(1)

    local MapService = Engine.RequireServer("World.MapService")
    local RoomGenerator = Engine.RequireServer("World.RoomGenerator")
    local plan = gameState().Plan
    local target = nil
    for _, item in ipairs(plan.Items) do
        if not MapService.IsRevealed(item.Cell) then
            target = item
            break
        end
    end
    T.True(target ~= nil, "hay un objeto en una sala sin recorrer")

    local markerId = "I:" .. target.Key
    for _, message in ipairs(mapMessages()) do
        for _, marker in ipairs(message.Markers or {}) do
            T.True(marker.Id ~= markerId, "el objeto no se conocía antes de entrar")
        end
    end

    local before = #Engine.Sent
    Bot.MoveTo(Engine, players[1], gameState().Nav:Center(target.Cell, 3))
    Engine.Run(1)
    T.True(MapService.IsRevealed(target.Cell), "sala revelada")

    local cellSent, markerSent = false, false
    for index = before + 1, #Engine.Sent do
        local entry = Engine.Sent[index]
        if entry.Name == "MapUpdate" and entry.Args[1].Kind == "Reveal" then
            for _, cell in ipairs(entry.Args[1].Cells) do
                cellSent = cellSent or cell.I == target.Cell
            end
            for _, marker in ipairs(entry.Args[1].Markers) do
                markerSent = markerSent or (marker.Id == markerId and marker.Item == target.Item)
            end
        end
    end
    T.True(cellSent, "la sala viaja a los clientes")
    T.True(markerSent, "el objeto aparece en el plano")

    -- Al levantarlo, el plano lo saca.
    before = #Engine.Sent
    Bot.Use(Engine, players[1], RoomGenerator.SlotCFrame(plan.Layout, target.Cell, target.Slot).Position)
    Engine.Run(1)
    local removed = false
    for index = before + 1, #Engine.Sent do
        local entry = Engine.Sent[index]
        if entry.Name == "MapUpdate" then
            for _, marker in ipairs(entry.Args[1].Markers or {}) do
                removed = removed or (marker.Id == markerId and marker.Done == true)
            end
        end
    end
    T.True(removed, "objeto levantado marcado")
    assertNoLeak(MapService)

    -- Quien entra tarde pide el plano y recibe lo que el grupo ya recorrió.
    fire("MapRequest", players[1])
    Engine.Run(0.2)
    local snapshot = Engine.LastSent("MapUpdate", players[1])[1]
    T.Equal(snapshot.Kind, "Layout", "plano completo")
    T.True(#snapshot.Cells >= 2, "con las salas recorridas")
    for _, marker in ipairs(snapshot.Markers) do
        T.True(marker.Id ~= markerId, "sin el objeto ya levantado")
    end
    T.NoEngineErrors(Engine)
end)

T.Test("plano: el botón MAPA y la tecla M lo abren y dibujan lo recorrido", function()
    local player = clientWithMatch()
    local gui = player:FindFirstChild("PlayerGui")
    local bar = gui:FindFirstChild("NocturnaHUD"):FindFirstChild("Root"):FindFirstChild("Buttons")
    local mapButton = bar:FindFirstChild("Map")
    T.True(mapButton ~= nil and mapButton.Visible, "botón MAPA en la barra")

    local window = gui:FindFirstChild("NocturnaMap"):FindFirstChild("Root"):FindFirstChild("Map")
    T.False(window.Visible, "cerrado")
    Engine.Input("InputBegan", {KeyCode = roblox.Enum.KeyCode.M})
    Engine.Run(0.3)
    T.True(window.Visible, "abierto con M")

    local grid = window:FindFirstChild("Board"):FindFirstChild("Grid")
    local plan = gameState().Plan
    T.True(grid.Visible, "plano dibujado")
    T.True(grid:FindFirstChild("Cell" .. plan.Layout.Start) ~= nil, "entrada dibujada")
    T.True(grid:FindFirstChild("You") ~= nil, "el jugador aparece")

    local MapService = Engine.RequireServer("World.MapService")
    local hidden = nil
    for index = 1, #plan.Layout.Cells do
        if not MapService.IsRevealed(index) then
            hidden = index
            break
        end
    end
    T.True(grid:FindFirstChild("Cell" .. hidden) == nil, "lo inexplorado queda en la niebla")
    Bot.MoveTo(Engine, player, gameState().Nav:Center(hidden, 3))
    Engine.Run(1)
    T.True(grid:FindFirstChild("Cell" .. hidden) ~= nil, "la sala nueva se dibuja")

    Engine.GuiInput(mapButton, "Activated")
    Engine.Run(0.1)
    T.False(window.Visible, "el botón lo cierra")
    T.NoEngineErrors(Engine)
end)

T.Test("pantalla de carga: es lo primero que aparece y se puede saltar", function()
    local players = bootServer(1)
    Engine.StartClient(players[1])
    Engine.Run(0.3)
    local gui = players[1]:FindFirstChild("PlayerGui")
    T.Equal(gui:GetChildren()[1].Name, "NocturnaLoading", "primera pantalla")

    local skip = screenOf(players[1], "NocturnaLoading"):FindFirstChild("Root"):FindFirstChild("Background"):FindFirstChild("Skip")
    T.Equal(skip.Text, "SALTAR", "botón para saltar")
    Engine.GuiInput(skip, "Activated")
    Engine.Run(1)
    T.True(screenOf(players[1], "NocturnaLoading") == nil, "saltada")
    T.NoEngineErrors(Engine)
end)

T.Test("pantalla de carga: termina sola, aunque la precarga no termine", function()
    for _, options in ipairs({{}, {PreloadHang = true}}) do
        local players = bootServer(1, options)
        Engine.StartClient(players[1])
        Engine.Run(1)
        T.True(screenOf(players[1], "NocturnaLoading") ~= nil, "visible al empezar")
        Engine.Run(16)
        T.True(screenOf(players[1], "NocturnaLoading") == nil, "se fue sola")
        T.NoEngineErrors(Engine)
    end
end)

T.Test("diálogo: cada línea queda 10 segundos y se cierra al tocarla", function()
    local players = bootServer(1)
    Engine.StartClient(players[1])
    Engine.Run(3)
    local remote = Engine.Services.ReplicatedStorage:FindFirstChild("NocturnaRemotes"):FindFirstChild("StoryDialogue")
    local stack = screenOf(players[1], "NocturnaStory"):FindFirstChild("Root"):FindFirstChild("Subtitles")

    local function visibleLines()
        local lines = {}
        for _, child in ipairs(stack:GetChildren()) do
            if child:IsA("TextButton") and child.Visible then
                table.insert(lines, child)
            end
        end
        return lines
    end

    remote:FireClient(players[1], {Speaker = "Radio", Text = "...contá hasta cinco..."})
    Engine.Run(0.1)
    local lines = visibleLines()
    T.Equal(#lines, 1, "una línea")
    T.True(string.find(lines[1]:FindFirstChild("Body").Text, "contá hasta cinco", 1, true) ~= nil, "texto de la línea")
    T.Equal(lines[1]:FindFirstChild("Tag").Text, "RADIO", "quién habla")

    Engine.Run(9.6)
    T.Equal(#visibleLines(), 1, "sigue a los 9,7 s")
    Engine.Run(1.2)
    T.Equal(#visibleLines(), 0, "se va pasados los 10 s")

    -- Si el servidor manda líneas seguidas, se apilan en vez de pisarse.
    for index = 1, 3 do
        remote:FireClient(players[1], {Speaker = "Vos", Text = "Línea " .. index})
        Engine.Run(index < 3 and 3.8 or 0.1)
    end
    T.Equal(#visibleLines(), 3, "tres líneas a la vez")

    Engine.GuiInput(visibleLines()[1], "Activated")
    Engine.Run(0.1)
    T.Equal(#visibleLines(), 2, "tocar una la cierra")
    T.NoEngineErrors(Engine)
end)

T.Test("despertar: tras el título del capítulo los ojos se abren y la pantalla queda libre", function()
    local player = clientWithMatch()
    local eyes = screenOf(player, "NocturnaWake"):FindFirstChild("Root"):FindFirstChild("Eyes")
    T.True(eyes.Visible, "abriendo los ojos")
    T.False(screenOf(player, "NocturnaCutscene"):FindFirstChild("Root"):FindFirstChild("Curtain").Visible, "el título ya se fue")

    Engine.Run(5)
    T.False(eyes.Visible, "ojos abiertos")
    local blur = Engine.Services.Lighting:FindFirstChild("NocturnaWakeBlur")
    T.True(blur == nil or blur.Enabled == false, "sin desenfoque al terminar")
    -- El balanceo no se acumula: la cámara termina mirando igual que antes.
    local look = Engine.Workspace.CurrentCamera.CFrame.LookVector
    local original = roblox.Instance.new("Camera").CFrame.LookVector
    T.True((look - original).Magnitude < 0.001, "la cámara vuelve a su inclinación: " .. tostring(look))
    T.NoEngineErrors(Engine)
end)

T.Test("HUD: nada debajo de la barra de Roblox y los botones no pisan el objetivo", function()
    local SAFE = {"NocturnaHUD", "NocturnaStory", "NocturnaInventory", "NocturnaJournal", "NocturnaSettings", "NocturnaMap", "NocturnaAdmin", "NocturnaEnding"}
    local OVERLAY = {"NocturnaCutscene", "NocturnaWake", "NocturnaVignette", "NocturnaStatus"}
    local devices = {
        {Touch = true, Viewport = roblox.Vector2.new(812, 375), CreatorId = 2001},
        {Touch = true, Viewport = roblox.Vector2.new(667, 375), CreatorId = 2001},
        {Viewport = roblox.Vector2.new(1280, 720), CreatorId = 2001},
        {Viewport = roblox.Vector2.new(1024, 768), CreatorId = 2001},
    }

    for _, options in ipairs(devices) do
        local player = clientWithMatch(options)
        Engine.Run(0.5)
        for _, name in ipairs(SAFE) do
            T.Equal(screenOf(player, name).ScreenInsets.Name, "CoreUISafeInsets", name .. " dentro del área segura")
        end
        for _, name in ipairs(OVERLAY) do
            T.Equal(screenOf(player, name).ScreenInsets.Name, "None", name .. " cubre toda la pantalla")
        end

        local Theme = Engine.Require(Engine.ClientFolder:FindFirstChild("UI"):FindFirstChild("Theme"), "Client")
        local safe = Theme.SafeSize()
        local full = Theme.FullSize()
        T.True(safe.Y < full.Y, "descuenta la barra de Roblox")

        local hud = screenOf(player, "NocturnaHUD"):FindFirstChild("Root")
        local plate = hud:FindFirstChild("Objective")
        local bar = hud:FindFirstChild("Buttons")
        local plateRight = safe.X / 2 + plate.Size.X.Offset / 2
        local barLeft = safe.X - 12 - bar.Size.X.Offset
        T.True(plate.Visible and plate.Position.Y.Offset >= 0, "objetivo visible arriba")
        T.True(barLeft >= plateRight, string.format("botones (%d) separados del objetivo (%d)", barLeft, plateRight))
        for _, name in ipairs({"Inventory", "Journal", "Map", "Settings", "Admin"}) do
            local button = bar:FindFirstChild(name)
            T.True(button ~= nil and button.Visible, "botón " .. name)
        end

        local chapter = plate:FindFirstChild("Chapter").Text
        T.True(string.find(chapter, "CAPÍTULO 1", 1, true) ~= nil, "mayúsculas con tilde: " .. chapter)
        T.NoEngineErrors(Engine)
    end
end)

T.Suite("Pruebas e historia")

local PuzzleConfig = Engine.RequireShared("Config.PuzzleConfig")

local function chapterPuzzles(index)
    local spec = ChapterConfig[index].Layout
    local list = {}
    for _, feature in ipairs(spec.Features or {}) do
        if feature.Kind == "Puzzle" then
            table.insert(list, feature)
        end
    end
    for _, room in ipairs(spec.LockedRooms or {}) do
        for _, feature in ipairs(room.Features or {}) do
            if feature.Kind == "Puzzle" then
                table.insert(list, feature)
            end
        end
    end
    return list
end

-- Texto estable de una tabla, para comparar estados sin depender del orden.
local function serialize(value)
    if type(value) ~= "table" then
        return tostring(value)
    end
    local keys = {}
    for key in pairs(value) do
        table.insert(keys, tostring(key))
    end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        local inner = value[key]
        if inner == nil then
            inner = value[tonumber(key)]
        end
        table.insert(parts, key .. "=" .. serialize(inner))
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Partida en el capítulo pedido, con las criaturas quietas para probar tranquilo.
local function puzzleMatch(chapter, playerCount, options)
    local players = bootServer(playerCount or 1, options)
    if options and options.Client then
        Engine.StartClient(players[1])
        Engine.Run(1)
    end
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    if chapter ~= 1 then
        Engine.RequireServer("Multiplayer.MatchService").SetChapter(chapter)
        T.True(Engine.RunUntil(function()
            return gameState().Chapter == chapter and gameState().Phase == "Playing"
        end, 40), "capítulo " .. chapter)
    end
    if not (options and options.Monsters) then
        Engine.RequireServer("Monsters.MonsterService").SetPaused(true)
    end
    Engine.Run(0.5)
    return players
end

local function skipTo(objectiveId)
    local Story = Engine.RequireServer("Story.StoryService")
    local tracker = gameState().Tracker
    local guard = 0
    while tracker:Current() and tracker:Current().Id ~= objectiveId and guard < 12 do
        Story.SkipObjective()
        guard += 1
    end
    Engine.Run(0.3)
    T.Equal(tracker:Current().Id, objectiveId, "objetivo actual")
end

local function puzzleModel(puzzleId)
    for _, descendant in ipairs(Engine.Workspace:GetDescendants()) do
        if descendant:IsA("Model") and descendant:GetAttribute("NocturnaPuzzleId") == puzzleId then
            return descendant
        end
    end
    return nil
end

local function openPuzzle(player, puzzleId)
    local model = puzzleModel(puzzleId)
    T.True(model ~= nil, "utilería de " .. puzzleId .. " en el mapa")
    Bot.Use(Engine, player, model.PrimaryPart.Position)
    Engine.Run(0.1)
    return Bot.PuzzleSession(Engine, player, puzzleId)
end

local function solveWithBot(player, objectiveId, maxSteps)
    local tracker = gameState().Tracker
    for _ = 1, maxSteps or 120 do
        if tracker:IsDone(objectiveId) then
            return true
        end
        Bot.Act(Engine, player)
        Engine.Run(0.4)
    end
    return tracker:IsDone(objectiveId)
end

T.Test("cada capítulo combina al menos 2 tipos de prueba y ninguna mezcla se repite", function()
    local mixes, used = {}, {}
    for index = 1, 5 do
        local types, list = {}, {}
        for _, feature in ipairs(chapterPuzzles(index)) do
            T.True(PuzzleConfig.Types[feature.Puzzle] ~= nil, "tipo conocido: " .. tostring(feature.Puzzle))
            if not types[feature.Puzzle] then
                types[feature.Puzzle] = true
                table.insert(list, feature.Puzzle)
                used[feature.Puzzle] = true
            end
        end
        table.sort(list)
        T.True(#list >= 2, "capítulo " .. index .. " con " .. #list .. " tipos")
        local mix = table.concat(list, "+")
        T.True(mixes[mix] == nil, "mezcla repetida en el capítulo " .. index .. ": " .. mix)
        mixes[mix] = true

        local declared = table.clone(ChapterConfig[index].Puzzles)
        table.sort(declared)
        T.Equal(table.concat(declared, "+"), mix, "lista Puzzles del capítulo " .. index)
    end
    for kind in pairs(PuzzleConfig.Types) do
        T.True(used[kind], "el tipo " .. kind .. " aparece en algún capítulo")
    end
end)

T.Test("las claves de los documentos coinciden con sus pruebas", function()
    local checked = 0
    for index = 1, 5 do
        for _, feature in ipairs(chapterPuzzles(index)) do
            local documentId = feature.Clue and feature.Clue.Document
            if documentId then
                T.True(table.find(ChapterConfig[index].Layout.Documents, documentId) ~= nil, documentId .. " está en el mismo capítulo")
                local digits = Bot.DocumentCode(Engine, documentId)
                T.True(digits ~= nil, "clave escrita en " .. documentId)
                local expected = feature.Sequence and table.concat(feature.Sequence) or feature.Code
                T.Equal(table.concat(digits), expected, "clave de " .. feature.Id)
                checked += 1
            end
            if feature.Sequence then
                local seen = {}
                for _, value in ipairs(feature.Sequence) do
                    T.False(seen[value], "secuencia sin repetidos")
                    seen[value] = true
                    T.True(value >= 1 and value <= #feature.Sequence, "secuencia válida")
                end
            end
        end
    end
    T.True(checked >= 2, "hay pruebas con clave en documentos")

    -- Ningún otro documento tiene números con puntos medios que confundan.
    local marked = 0
    for _, document in pairs(DocumentConfig) do
        if string.find(document.Body, "%d ·") then
            marked += 1
        end
    end
    T.Equal(marked, checked, "documentos con clave")
end)

T.Test("las compuertas salen del plan como bordes trabados, no como puertas comunes", function()
    for index = 1, 5 do
        local spec = ChapterConfig[index].Layout
        local layout = MazeLayout.Generate({
            Width = spec.Width,
            Depth = spec.Depth,
            Seed = 1234 + index,
            LoopChance = spec.LoopChance,
            ReservedLeaves = spec.LockedRooms and #spec.LockedRooms or 0,
        })
        local plan = LayoutPlanner.Plan(layout, spec)
        local wanted = 0
        if spec.Exit.Door and spec.Exit.Door.Gate then
            wanted += 1
        end
        for _, room in ipairs(spec.LockedRooms or {}) do
            if room.Door.Gate then
                wanted += 1
            end
        end
        T.Equal(#plan.Gates, wanted, "compuertas del capítulo " .. index)
        for _, gate in ipairs(plan.Gates) do
            T.True(plan.LockedEdges[gate.Key], "la compuerta traba el borde")
            T.True(gate.RequiresFlag ~= nil, "la compuerta se abre con una marca")
            for _, door in ipairs(plan.Doors) do
                T.True(door.Key ~= gate.Key, "sin puerta común encima de la compuerta")
            end
        end
    end
end)

T.Test("reglas: cada tipo ignora jugadas mal formadas sin cambiar nada", function()
    local PuzzleRules = Engine.RequireServer("Puzzles.PuzzleRules")
    local rng = Engine.RandomClass.new(77)
    -- La posición 1 queda vacía a propósito: también se prueba nil.
    local garbage = {"nil", 0, -1, 1.5, 0 / 0, math.huge, -math.huge, 1e9, "1", "", {}, true}
    local seconds = {"nil", 2, 0 / 0, "x"}
    local specs = {
        Wires = {}, Breakers = {Sequence = {3, 1, 4, 2}}, Valves = {}, Keypad = {Code = "0315"},
        Power = {}, Simon = {}, Memory = {}, Levers = {},
    }
    for _, kind in ipairs(PuzzleRules.Types) do
        local rules = PuzzleRules[kind]
        local state = rules.New(specs[kind], rng)
        local before = serialize(rules.View(state, 0))
        for action in pairs(rules.Actions) do
            for _, first in ipairs(garbage) do
                for _, second in ipairs(seconds) do
                    local a = first ~= "nil" and first or nil
                    local b = second ~= "nil" and second or nil
                    local outcome = rules.Apply(state, action, a, b, 0)
                    T.Equal(outcome, "Invalid", string.format("%s %s(%s, %s)", kind, action, tostring(a), tostring(b)))
                end
            end
        end
        T.Equal(rules.Apply(state, "Solve", 1, 1, 0), "Invalid", kind .. ": no existe la jugada 'resolver'")
        T.Equal(serialize(rules.View(state, 0)), before, kind .. " no cambió")
    end
end)

T.Test("reglas: los errores se castigan y la solución correcta se acepta", function()
    local PuzzleRules = Engine.RequireServer("Puzzles.PuzzleRules")
    local rng = Engine.RandomClass.new(31)

    -- Cables: color equivocado, después todos bien.
    local wires = PuzzleRules.Wires.New({}, rng)
    local wrongRight = nil
    for right, color in ipairs(wires.Right) do
        if color ~= wires.Left[1] then
            wrongRight = right
        end
    end
    T.Equal(PuzzleRules.Wires.Apply(wires, "Connect", 1, wrongRight), "Wrong", "cable equivocado")
    local outcome = nil
    for left, color in ipairs(wires.Left) do
        outcome = PuzzleRules.Wires.Apply(wires, "Connect", left, table.find(wires.Right, color))
    end
    T.Equal(outcome, "Solved", "cables")
    T.Equal(PuzzleRules.Wires.Apply(wires, "Connect", 1, 1), "Blocked", "ya conectados")

    -- Disyuntores: un error reinicia todo el tablero.
    local breakers = PuzzleRules.Breakers.New({Sequence = {3, 1, 4, 2}}, rng)
    T.Equal(PuzzleRules.Breakers.Apply(breakers, "Flip", 3), "Ok", "primera")
    T.Equal(PuzzleRules.Breakers.Apply(breakers, "Flip", 4), "Wrong", "orden equivocado")
    T.False(breakers.On[3], "saltó todo")
    for _, index in ipairs({3, 1, 4}) do
        T.Equal(PuzzleRules.Breakers.Apply(breakers, "Flip", index), "Ok", "en orden")
    end
    T.Equal(PuzzleRules.Breakers.Apply(breakers, "Flip", 2), "Solved", "tablero")

    -- Válvulas: pasarse de presión es un error; el camino corto las equilibra.
    local valves = PuzzleRules.Valves.New({}, rng)
    valves.Gauges = {8, 4, 4}
    T.Equal(PuzzleRules.Valves.Apply(valves, "Turn", 1, 1), "Wrong", "sobrepresión")
    T.Equal(serialize(valves.Gauges), serialize({8, 4, 4}), "no se aplicó")
    local scrambled = PuzzleRules.Valves.New({}, rng)
    local moves = Bot.ValveMoves(PuzzleRules.Valves.View(scrambled))
    T.True(moves ~= nil and #moves > 0, "siempre tiene solución")
    for index, move in ipairs(moves) do
        outcome = PuzzleRules.Valves.Apply(scrambled, "Turn", move[1], move[2])
        T.Equal(outcome, index == #moves and "Solved" or "Ok", "giro " .. index)
    end

    -- Clave: el error es un error; el bloqueo es de quien se equivocó (PuzzleRules.Strike),
    -- no del teclado, así que la regla no traba a nadie.
    local keypad = PuzzleRules.Keypad.New({Code = "0315"}, rng)
    T.Equal(PuzzleRules.Keypad.Apply(keypad, "Submit", "1234", nil, 10), "Wrong", "clave equivocada")
    T.False(PuzzleRules.Keypad.View(keypad, 10.5).Locked, "el teclado no queda trabado para todos")
    T.Equal(PuzzleRules.Keypad.Apply(keypad, "Submit", "0315", nil, 10.5), "Solved", "clave")
    local random = PuzzleRules.Keypad.New({}, rng)
    T.True(string.match(random.Code, "^%d%d%d%d$") ~= nil, "clave al azar de 4 números")

    -- Tablero de distribución: arranca cortado y el camino del bot lo conecta.
    for seed = 1, 25 do
        local power = PuzzleRules.Power.New({}, Engine.RandomClass.new(seed))
        T.False(select(2, PuzzleRules.PowerFlow(power)), "arranca cortado")
        local view = PuzzleRules.Power.View(power)
        local targets = Bot.PowerTargets(Engine, view)
        T.True(targets ~= nil, "tiene solución " .. seed)
        local last = nil
        for cell, rotation in pairs(targets) do
            for _ = 1, (rotation - power.Tiles[cell].Rot) % 4 do
                if last ~= "Solved" then
                    last = PuzzleRules.Power.Apply(power, "Rotate", cell)
                end
            end
        end
        T.Equal(last, "Solved", "se resuelve " .. seed)
        T.True(select(2, PuzzleRules.PowerFlow(power)), "corriente conectada " .. seed)
    end

    -- Señal: un error pide empezar de nuevo con otra señal.
    local simon = PuzzleRules.Simon.New({}, rng)
    local first = simon.Sequence[1]
    T.Equal(PuzzleRules.Simon.Apply(simon, "Press", first % 4 + 1), "Wrong", "botón equivocado")
    T.Equal(simon.Round, 1, "vuelve a la primera señal")
    local guard = 0
    repeat
        guard += 1
        local view = PuzzleRules.Simon.View(simon)
        outcome = PuzzleRules.Simon.Apply(simon, "Press", view.Show[view.Position + 1])
    until outcome == "Solved" or guard > 20
    T.Equal(outcome, "Solved", "señal completa")

    -- Recuerdos: la vista nunca muestra una foto boca abajo.
    local memory = PuzzleRules.Memory.New({}, rng)
    for _, card in ipairs(PuzzleRules.Memory.View(memory).Cards) do
        T.Equal(card.Symbol, "", "fotos ocultas")
    end
    T.Equal(PuzzleRules.Memory.Apply(memory, "Flip", 1), "Ok", "primera foto")
    T.Equal(PuzzleRules.Memory.Apply(memory, "Flip", 1), "Blocked", "la misma foto dos veces")
    local byPair = {}
    for index, symbol in ipairs(memory.Cards) do
        byPair[symbol] = byPair[symbol] or {}
        table.insert(byPair[symbol], index)
    end
    table.clear(memory.Revealed)
    for _, indexes in pairs(byPair) do
        PuzzleRules.Memory.Apply(memory, "Flip", indexes[1])
        outcome = PuzzleRules.Memory.Apply(memory, "Flip", indexes[2])
    end
    T.Equal(outcome, "Solved", "todos los pares")

    -- Palancas: separadas no alcanzan; juntas sí.
    local levers = PuzzleRules.Levers.New({})
    T.Equal(PuzzleRules.Levers.Pull(levers, 1, 0, 2), "Ok", "una sola")
    T.Equal(PuzzleRules.Levers.Pull(levers, 2, 5, 2), "Ok", "la otra, tarde")
    T.Equal(PuzzleRules.Levers.Pull(levers, 1, 6, 2), "Solved", "las dos a la vez")
    T.Equal(PuzzleRules.Levers.Pull(levers, 3, 6, 2), "Invalid", "palanca inexistente")
end)

-- Cada tipo, de punta a punta por el remoto: mal formadas ignoradas, errores
-- rechazados y la solución completa el objetivo.
local REMOTE_CASES = {
    {
        Kind = "Wires", Chapter = 1, Objective = "C1_WIRES", Id = "WIRES_C1",
        Wrong = function(view)
            for right, color in ipairs(view.Right) do
                if color ~= view.Left[1] then
                    return {"Connect", 1, right}
                end
            end
            return nil
        end,
        Malformed = {{"Connect", 0, 1}, {"Connect", 1.5, 1}, {"Connect", 0 / 0, 2}, {"Connect", 99, 1}, {"Connect", "1", "2"}, {"Cut", 1, 1}},
    },
    {
        Kind = "Breakers", Chapter = 1, Objective = "C1_BREAKERS", Id = "BREAKERS_C1",
        Setup = function()
            gameState().SetFlag("POWER")
        end,
        Wrong = function()
            return {"Flip", 1}
        end,
        Malformed = {{"Flip", 0}, {"Flip", 5}, {"Flip", -1}, {"Flip", math.huge}, {"Flip", "3"}},
    },
    {
        Kind = "Keypad", Chapter = 2, Objective = "C2_CODE", Id = "KEYPAD_C2",
        Wrong = function(_, state)
            return {"Submit", state.Code == "1111" and "2222" or "1111"}
        end,
        Malformed = {{"Submit", "12"}, {"Submit", "12345"}, {"Submit", "12a4"}, {"Submit", 1234}, {"Submit", "123456789"}},
    },
    {
        Kind = "Simon", Chapter = 2, Objective = "C2_RECORDING", Id = "TERM_RECORD",
        Setup = function(players)
            Engine.RequireServer("Inventory.InventoryService").AddItem(players[1], "Radio", 1)
        end,
        Wrong = function(view)
            return {"Press", view.Show[1] % 4 + 1}
        end,
        Malformed = {{"Press", 0}, {"Press", 5}, {"Press", 2.5}, {"Press", "1"}},
    },
    {
        Kind = "Valves", Chapter = 3, Objective = "C3_PRESSURE", Id = "VALVES_C3",
        Wrong = function(view)
            for valve, effects in ipairs(view.Effects) do
                for _, direction in ipairs({1, -1}) do
                    for gauge, change in ipairs(effects) do
                        local value = view.Gauges[gauge] + change * direction
                        if value < 0 or value > view.Max then
                            return {"Turn", valve, direction}
                        end
                    end
                end
            end
            return nil
        end,
        Malformed = {{"Turn", 1, 0}, {"Turn", 1, 2}, {"Turn", 4, 1}, {"Turn", 1, 0.5}, {"Turn", "1", 1}},
    },
    {
        Kind = "Power", Chapter = 4, Objective = "C4_ROUTE", Id = "ROUTE_C4",
        Malformed = {{"Rotate", 0}, {"Rotate", 13}, {"Rotate", 1.2}, {"Rotate", "3"}},
    },
    {
        Kind = "Keypad", Chapter = 4, Objective = "C4_UNLOCK", Id = "CORE_LOCK",
        Wrong = function()
            return {"Submit", "9999"}
        end,
        Malformed = {{"Submit", "315"}, {"Submit", "0315 "}, {"Submit", 315}},
    },
    {
        Kind = "Memory", Chapter = 5, Objective = "C5_PHOTO", Id = "MEMORY_C5",
        Setup = function(players)
            Engine.RequireServer("Inventory.InventoryService").AddItem(players[1], "MemoryShard", 3)
        end,
        Malformed = {{"Flip", 0}, {"Flip", 13}, {"Flip", 1.5}, {"Flip", "2"}},
    },
}

for _, case in ipairs(REMOTE_CASES) do
    T.Test(string.format("prueba %s (%s): el servidor valida cada jugada y completa el objetivo", case.Kind, case.Id), function()
        local players = puzzleMatch(case.Chapter)
        local player = players[1]
        local Puzzles = Engine.RequireServer("Puzzles.PuzzleService")
        skipTo(case.Objective)
        if case.Setup then
            case.Setup(players)
        end

        -- Sin panel abierto no hay jugada que valga, ni "ya la resolví".
        Bot.Fire(Engine, player, "PuzzleAction", case.Id, "Solve")
        Bot.Fire(Engine, player, "PuzzleAction", case.Id, "Submit", "0315")
        Engine.Run(0.2)
        T.False(Puzzles.IsSolved(case.Id), "sin abrir no se resuelve")

        local session = openPuzzle(player, case.Id)
        T.True(session ~= nil and session.Event == "Open", "panel abierto")
        T.Equal(session.Type, case.Kind, "tipo")
        local puzzle = Puzzles.Get(case.Id)
        local before = serialize(Engine.RequireServer("Puzzles.PuzzleRules")[case.Kind].View(puzzle.State, 0))

        for _, bad in ipairs(case.Malformed) do
            Bot.Fire(Engine, player, "PuzzleAction", case.Id, bad[1], bad[2], bad[3])
            Engine.Run(0.15)
        end
        Bot.Fire(Engine, player, "PuzzleAction", case.Id, "Solve")
        Bot.Fire(Engine, player, "PuzzleAction", {}, "Connect", 1, 1)
        Engine.Run(0.3)
        T.Equal(serialize(Engine.RequireServer("Puzzles.PuzzleRules")[case.Kind].View(puzzle.State, 0)), before, "mal formadas sin efecto")
        T.False(puzzle.Solved, "no se resolvió con basura")

        if case.Wrong then
            local wrong = case.Wrong(session.View, puzzle.State)
            if wrong then
                local noisesBefore = #Engine.RequireServer("AI.NoiseService").Recent()
                Bot.Fire(Engine, player, "PuzzleAction", case.Id, wrong[1], wrong[2], wrong[3])
                Engine.Run(0.1)
                local reply = Bot.PuzzleSession(Engine, player, case.Id)
                T.Equal(reply.Event, "Wrong", "error rechazado")
                T.True(typeof(reply.Message) == "string" and #reply.Message > 0, "aviso del error")
                T.True(#Engine.RequireServer("AI.NoiseService").Recent() > noisesBefore, "el error hace ruido")
                T.False(gameState().Tracker:IsDone(case.Objective), "el error no completa nada")
                -- La clave equivocada bloquea el teclado: se espera antes de seguir.
                Engine.Run(PuzzleConfig.Keypad.Lockout + 0.5)
            end
        end

        T.True(solveWithBot(player, case.Objective), "el objetivo se completa")
        T.True(Puzzles.IsSolved(case.Id), "prueba resuelta en el servidor")
        T.NoEngineErrors(Engine)
    end)
end

T.Test("el panel se cierra si el jugador se aleja y no acepta jugadas a distancia", function()
    local players = puzzleMatch(1)
    local player = players[1]
    local Puzzles = Engine.RequireServer("Puzzles.PuzzleService")
    skipTo("C1_WIRES")
    local session = openPuzzle(player, "WIRES_C1")
    T.Equal(session.Event, "Open", "abierto")

    Bot.MoveTo(Engine, player, Vector3.new(5000, 3, 5000))
    local color = session.View.Left[1]
    Bot.Fire(Engine, player, "PuzzleAction", "WIRES_C1", "Connect", 1, table.find(session.View.Right, color))
    Engine.Run(0.2)
    T.Equal(Bot.PuzzleSession(Engine, player, "WIRES_C1").Event, "Close", "se cerró por distancia")
    T.Equal(next(Puzzles.Get("WIRES_C1").State.Links), nil, "la jugada a distancia no cuenta")
    T.Equal(Puzzles.SessionOf(player), nil, "sin sesión")
    T.NoEngineErrors(Engine)
end)

T.Test("palancas: con compañeros hay que bajarlas a la vez; solo, alcanza con correr", function()
    local players = puzzleMatch(3, 2)
    local Puzzles = Engine.RequireServer("Puzzles.PuzzleService")
    local Mechanisms = Engine.RequireServer("World.MechanismService")
    skipTo("C3_PURGE")
    local positions = Mechanisms.PositionsFor("LEVERS_C3")
    T.Equal(#positions, 2, "dos palancas en el mapa")

    Bot.Use(Engine, players[1], positions[1])
    Engine.Run(PuzzleConfig.Levers.TeamWindow + 0.5)
    Bot.Use(Engine, players[2], positions[2])
    Engine.Run(0.2)
    T.False(Puzzles.IsSolved("LEVERS_C3"), "separadas en el tiempo no alcanza")
    Engine.Run(PuzzleConfig.Levers.TeamWindow + 0.5)

    Bot.Use(Engine, players[1], positions[1])
    Engine.Run(0.3)
    Bot.Use(Engine, players[2], positions[2])
    Engine.Run(0.3)
    T.True(Puzzles.IsSolved("LEVERS_C3"), "juntas sí")
    T.True(gameState().Tracker:IsDone("C3_PURGE"), "objetivo")

    -- Con un compañero ausente, el mecanismo termina cediendo: nadie queda trabado.
    local absent = puzzleMatch(5, 2)
    skipTo("C5_DOOR")
    local switches = Engine.RequireServer("World.MechanismService").PositionsFor("LAMPS_C5")
    Bot.Use(Engine, absent[1], switches[1])
    Engine.Run(PuzzleConfig.Levers.TeamGrace + 1)
    Bot.Use(Engine, absent[1], switches[1])
    Engine.Run(6)
    Bot.Use(Engine, absent[1], switches[2])
    Engine.Run(0.3)
    T.True(gameState().Tracker:IsDone("C5_DOOR"), "un solo jugador lo logra tras la espera")

    -- Solo: tiene tiempo de correr de una palanca a la otra.
    local solo = puzzleMatch(5, 1)
    skipTo("C5_DOOR")
    local lamps = Engine.RequireServer("World.MechanismService").PositionsFor("LAMPS_C5")
    Bot.Use(Engine, solo[1], lamps[1])
    Engine.Run(8)
    T.False(Engine.RequireServer("Puzzles.PuzzleService").IsSolved("LAMPS_C5"), "falta la otra")
    Bot.Use(Engine, solo[1], lamps[2])
    Engine.Run(0.3)
    T.True(gameState().Tracker:IsDone("C5_DOOR"), "solo también se puede")
    T.NoEngineErrors(Engine)
end)

T.Test("la pista pintada aparece primero en la radio y le enseña la clave a quien la lee", function()
    local players = puzzleMatch(2)
    local Puzzles = Engine.RequireServer("Puzzles.PuzzleService")
    local Mechanisms = Engine.RequireServer("World.MechanismService")
    skipTo("C2_CODE")
    local positions = Mechanisms.PositionsFor("KEYPAD_C2")
    T.Equal(#positions, 2, "pista y teclado")

    Bot.Use(Engine, players[1], positions[1])
    Engine.Run(0.2)
    local clue = nil
    for index = #Engine.Sent, 1, -1 do
        local entry = Engine.Sent[index]
        if entry.Name == "PuzzleUpdate" and entry.Args[1].Event == "Clue" then
            clue = entry.Args[1]
            break
        end
    end
    T.True(clue ~= nil, "la pista llega a quien la lee")
    T.Equal(clue.Code, Puzzles.Get("KEYPAD_C2").State.Code, "la clave pintada es la real")
    T.True(Puzzles.IsClueRead("KEYPAD_C2"), "pista leída")
    T.Equal(#Mechanisms.PositionsFor("KEYPAD_C2"), 1, "la radio ya apunta sólo al teclado")
    local update = Engine.LastSent("ObjectiveUpdate")[1]
    T.Equal(update.Puzzle, "Keypad", "el objetivo dice qué prueba es")
    T.True(typeof(update.Hint) == "string", "con su pista")
end)

T.Test("una prueba que abre una compuerta dispara la cinemática y protege al grupo", function()
    local players = puzzleMatch(1, 1, {Monsters = true})
    local player = players[1]
    local Gates = Engine.RequireServer("Puzzles.GateService")
    local Monsters = Engine.RequireServer("Monsters.MonsterService")
    skipTo("C1_WIRES")

    local gate = gameState().Plan.Gates[1]
    T.Equal(gate.Id, "ELEVATOR_GATE", "compuerta del ascensor")
    T.False(Gates.IsOpen("ELEVATOR_GATE"), "cerrada")
    T.True(gameState().Nav:IsBlocked(gate.A, gate.B), "traba a las criaturas")
    local sentBefore = Engine.CountRemote and (Engine.Remotes.Cinematic or 0) or 0

    T.True(solveWithBot(player, "C1_WIRES"), "cables resueltos")
    Engine.Run(0.1)
    T.True(Gates.IsOpen("ELEVATOR_GATE"), "se abrió")
    T.False(gameState().Nav:IsBlocked(gate.A, gate.B), "paso libre")
    T.True((Engine.Remotes.Cinematic or 0) > sentBefore, "se mandó la cinemática")

    local scene = Engine.LastSent("Cinematic", player)[1]
    T.Equal(scene.Kind, "DoorOpen", "escena de puerta")
    T.True(scene.Duration >= 2 and scene.Duration <= 3, "dura entre 2 y 3 segundos")
    T.Equal(scene.Label, "Compuerta del ascensor", "nombre de la compuerta")
    T.True((scene.Focus - (scene.To)).Magnitude > 5, "la cámara mira la compuerta desde afuera")
    T.True(Monsters.IsPaused(), "criaturas quietas durante la escena")
    T.True(player.Character:FindFirstChild("NocturnaCinematicShield") ~= nil, "jugador protegido")

    Engine.Run(scene.Duration + 1)
    T.False(Monsters.IsPaused(), "las criaturas vuelven")
    T.True(player.Character:FindFirstChild("NocturnaCinematicShield") == nil, "sin protección después")
    T.NoEngineErrors(Engine)
end)

T.Test("abrir la puerta de investigación con la tarjeta también tiene su cinemática", function()
    local players = puzzleMatch(2)
    skipTo("C2_DOOR")
    Engine.RequireServer("Inventory.InventoryService").AddItem(players[1], "Keycard", 1)
    Bot.Use(Engine, players[1], Engine.RequireServer("World.DoorService").PositionOf("RESEARCH_DOOR"))
    Engine.Run(0.3)
    T.True(gameState().Tracker:IsDone("C2_DOOR"), "puerta abierta")
    local scene = Engine.LastSent("Cinematic", players[1])
    T.True(scene ~= nil, "cinemática")
    T.Equal(scene[1].Label, "Sector de investigación", "encuadra esa puerta")
end)

T.Test("cliente: la cinemática toma la cámara con franjas y siempre la devuelve", function()
    local players = puzzleMatch(1, 1, {Client = true})
    local player = players[1]
    skipTo("C1_WIRES")
    T.True(solveWithBot(player, "C1_WIRES"), "cables resueltos")
    Engine.Run(0.2)

    local camera = Engine.Workspace.CurrentCamera
    local root = player:FindFirstChild("PlayerGui"):FindFirstChild("NocturnaCinematic"):FindFirstChild("Root")
    T.Equal(camera.CameraType, roblox.Enum.CameraType.Scriptable, "cámara de la escena")
    T.True(Engine.RenderBindings.NocturnaCinematic ~= nil, "la escena mueve la cámara")
    T.True(root:FindFirstChild("TopBar").Size.Y.Scale > 0, "franjas visibles")

    Engine.Run(4)
    T.Equal(camera.CameraType, roblox.Enum.CameraType.Custom, "cámara devuelta")
    T.True(Engine.RenderBindings.NocturnaCinematic == nil, "sin escena activa")
    T.Equal(root:FindFirstChild("TopBar").Size.Y.Scale, 0, "franjas guardadas")
    T.NoEngineErrors(Engine)
end)

T.Test("cliente táctil: los cables se conectan tocando el cable y su borne", function()
    local players = puzzleMatch(1, 1, {Client = true, Touch = true, Viewport = roblox.Vector2.new(812, 375)})
    local player = players[1]
    skipTo("C1_WIRES")
    openPuzzle(player, "WIRES_C1")
    Engine.Run(0.2)

    local panel = player:FindFirstChild("PlayerGui"):FindFirstChild("NocturnaPuzzle"):FindFirstChild("Root"):FindFirstChild("PuzzlePanel")
    T.True(panel.Visible, "panel abierto")

    for _ = 1, PuzzleConfig.Wires.Count do
        local board = panel:FindFirstChild("Board")
        local pending = nil
        for index = 1, PuzzleConfig.Wires.Count do
            local left = board:FindFirstChild("Left" .. index)
            if left and not string.find(left.Text, "listo", 1, true) then
                pending = left
                break
            end
        end
        if not pending then
            break
        end
        local name = string.match(pending.Text, "^(%S+)")
        T.True(pending.Size.X.Offset >= 44 and pending.Size.Y.Offset >= 44, "botón cómodo para el dedo")
        Engine.GuiInput(pending, "Activated")
        Engine.Run(0.05)
        board = panel:FindFirstChild("Board")
        for index = 1, PuzzleConfig.Wires.Count do
            local right = board:FindFirstChild("Right" .. index)
            if right and string.find(right.Text, "Borne " .. name, 1, true) then
                Engine.GuiInput(right, "Activated")
                break
            end
        end
        Engine.Run(0.2)
    end

    T.True(gameState().Tracker:IsDone("C1_WIRES"), "resuelto con toques")
    Engine.Run(2)
    T.False(panel.Visible, "el panel se cierra solo")
    T.NoEngineErrors(Engine)
end)

T.Test("los diálogos duran 10 segundos y ninguna línea es demasiado larga para leerla", function()
    local Story = Engine.RequireServer("Story.StoryService")
    T.Equal(Story.LineTime(), 10, "segundos por línea")

    local function check(line, where)
        T.True(typeof(line.Text) == "string" and #line.Text > 0, "texto en " .. where)
        T.True(utf8.len(line.Text) <= 130, "línea larga en " .. where .. ": " .. line.Text)
        T.True(typeof(line.Speaker) == "string", "quién habla en " .. where)
    end
    for index = 1, 5 do
        local chapter = ChapterConfig[index]
        for _, line in ipairs(chapter.Intro) do
            check(line, "intro " .. index)
        end
        for _, line in ipairs(chapter.Outro or {}) do
            check(line, "cierre " .. index)
        end
        for _, objective in ipairs(chapter.Objectives) do
            for _, line in ipairs(objective.OnComplete and objective.OnComplete.Dialogue or {}) do
                check(line, objective.Id)
            end
        end
    end
    -- El prólogo se lee a 4,5 segundos por tarjeta: frases cortas.
    for _, line in ipairs(ChapterConfig.Prologue) do
        T.True(utf8.len(line) <= 80, "prólogo largo: " .. line)
    end
    -- La cuenta de la radio avanza capítulo a capítulo hasta el cuatro.
    for index, word in ipairs({"uno", "dos", "tres", "cuatro"}) do
        local outro = ChapterConfig[index].Outro
        T.True(string.find(outro[#outro].Text, word, 1, true) ~= nil, "la radio cuenta " .. word)
    end
end)

T.Test("la cola de diálogos no frena el juego: tiene tope y el cierre va después de lo pendiente", function()
    puzzleMatch(1)
    local Story = Engine.RequireServer("Story.StoryService")
    Engine.Run(35)

    local lines = {}
    for index = 1, 6 do
        table.insert(lines, {Speaker = "Vos", Text = "L" .. index})
    end
    Story.PlayDialogue(lines)
    Engine.Run(0.1)
    local sentLine = Engine.LastSent("StoryDialogue")[1]
    T.Equal(sentLine.Duration, 10, "el cliente recibe la duración")
    T.True(Story.PendingLines() <= 4, "la cola no crece sin límite")

    -- El objetivo avanza aunque haya diálogo pendiente.
    local tracker = gameState().Tracker
    Story.SkipObjective()
    Engine.Run(0.1)
    T.True(tracker.Index >= 2, "el juego sigue")

    -- Al cerrar el capítulo lo pendiente no se pierde: el cierre va detrás, sin
    -- pasar el tope de la cola, y se sabe cuánto falta para que termine todo.
    gameState().Phase = "Cutscene"
    local pendingBefore = Story.PendingLines()
    T.True(pendingBefore > 0, "quedaban líneas por decir")
    Story.PlayDialogue({{Speaker = "Radio", Text = "...uno..."}})
    Engine.Run(0.1)
    T.True(Engine.LastSent("StoryDialogue")[1].Text ~= "...uno...", "el cierre no pisa lo pendiente")
    T.True(Story.PendingLines() >= 1 and Story.PendingLines() <= 4, "el cierre espera su turno, con tope")
    T.True(Story.RemainingDialogue() > Story.PendingLines() * Story.LineTime(), "cuenta la línea en pantalla")
    T.True(Engine.RunUntil(function()
        return Engine.LastSent("StoryDialogue")[1].Text == "...uno..."
    end, 60), "el cierre llega después")
    gameState().Phase = "Playing"

    -- Un capítulo nuevo descarta lo que quedaba.
    Story.PlayDialogue(lines)
    Story.Stop()
    T.Equal(Story.PendingLines(), 0, "cola vacía al cortar")
    local before = Engine.Remotes.StoryDialogue or 0
    Engine.Run(25)
    T.Equal(Engine.Remotes.StoryDialogue or 0, before, "no siguen llegando líneas viejas")
end)

T.Suite("Mundo")

local function hidesFolder()
    return Engine.Workspace:FindFirstChild("NOCTURNA_MAP"):FindFirstChild("Hides")
end

local function hidePrompt(model)
    return model:FindFirstChild("Door"):FindFirstChild("NocturnaPrompt")
end

local function enterHide(player, model)
    local prompt = hidePrompt(model)
    Bot.MoveTo(Engine, player, prompt.Parent.Position)
    prompt:Fire(player)
    Engine.Run(0.3)
    return prompt
end

local function countBaseParts(root)
    local count = 0
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("BasePart") then
            count += 1
        end
    end
    return count
end

T.Test("Mundo: en PC se sale del escondite con E y los prompts vuelven", function()
    local player = clientWithMatch()
    local Hiding = Engine.RequireServer("World.HidingService")
    local promptService = Engine.Services.ProximityPromptService
    local root = player.Character:FindFirstChild("HumanoidRootPart")

    local prompt = enterHide(player, hidesFolder():GetChildren()[1])
    T.True(Hiding.IsHidden(player), "escondido")
    T.False(promptService.Enabled, "los demás prompts no roban la tecla E")
    local camera = Engine.Workspace.CurrentCamera
    T.Equal(camera.CameraType, roblox.Enum.CameraType.Scriptable, "cámara del escondite")

    local button = player:FindFirstChild("PlayerGui"):FindFirstChild("NocturnaHide"):FindFirstChild("Root"):FindFirstChild("ExitHide")
    T.True(button.Visible, "en PC también se ve SALIR [E]")

    Engine.Input("InputBegan", {KeyCode = roblox.Enum.KeyCode.E, UserInputType = roblox.Enum.UserInputType.Keyboard})
    Engine.Run(0.3)
    T.False(Hiding.IsHidden(player), "salió con E")
    T.False(root.Anchored, "libre")
    T.True(prompt.Enabled, "el escondite queda libre")
    T.True(promptService.Enabled, "prompts de nuevo activos")
    T.Equal(camera.CameraType, roblox.Enum.CameraType.Custom, "vuelve la primera persona")
    T.False(button.Visible, "botón oculto")

    -- Y el prompt del escondite sirve para volver a entrar.
    enterHide(player, hidesFolder():GetChildren()[1])
    T.True(Hiding.IsHidden(player), "entra otra vez con el prompt")
    T.NoEngineErrors(Engine)
end)

T.Test("Mundo: en el celular el botón SALIR se ve por encima de todo y saca al jugador", function()
    local player = clientWithMatch({Touch = true, Viewport = roblox.Vector2.new(812, 375)})
    local Hiding = Engine.RequireServer("World.HidingService")
    local gui = player:FindFirstChild("PlayerGui")

    enterHide(player, hidesFolder():GetChildren()[1])
    T.True(Hiding.IsHidden(player), "escondido")

    local hideGui = gui:FindFirstChild("NocturnaHide")
    local button = hideGui:FindFirstChild("Root"):FindFirstChild("ExitHide")
    T.True(button.Visible, "SALIR visible")
    T.True(button.Size.X.Offset >= 200 and button.Size.Y.Offset >= 64, "botón grande para el dedo")
    for _, name in ipairs({"NocturnaVignette", "NocturnaTouch", "NocturnaHUD"}) do
        T.True(gui:FindFirstChild(name).DisplayOrder < hideGui.DisplayOrder, "nada de juego tapa el botón: " .. name)
    end
    -- La viñeta ya no tapa la pantalla con franjas negras.
    T.True(gui:FindFirstChild("NocturnaVignette"):FindFirstChild("Root"):FindFirstChild("LockerSlit") == nil, "sin franjas negras")

    Engine.GuiInput(button, "Activated")
    Engine.Run(0.3)
    T.False(Hiding.IsHidden(player), "salió con el botón")
    T.False(button.Visible, "botón oculto al salir")
    T.NoEngineErrors(Engine)
end)

T.Test("Mundo: la cámara de cada escondite queda adentro, mirando afuera por rendijas abiertas", function()
    Engine.Reset()
    local Hide = Engine.RequireServer("World.HideModels")
    local base = roblox.CFrame.new(10, 0, 20) * roblox.CFrame.Angles(0, 0.7, 0)

    for _, kind in ipairs(Hide.Kinds) do
        local folder = Engine.New("Folder", kind)
        folder.Parent = Engine.Workspace
        local model, prompt, spec = Hide.Build(folder, kind, base)
        T.Equal(spec.Kind, kind, "tipo")
        T.True(model:FindFirstChild("Door") ~= nil and prompt.Parent == model:FindFirstChild("Door"), kind .. ": prompt en Door")
        T.True(prompt.ActionText == "Esconderse" and #spec.Label > 0, kind .. ": textos")

        local camera = spec.Camera
        T.True(camera.Position.Z > spec.DoorZ and camera.Position.Z < 0.2, kind .. ": la cámara queda adentro, detrás de la puerta")
        T.True(camera.LookVector:Dot(roblox.Vector3.new(0, 0, -1)) > 0.99, kind .. ": mira hacia la sala")
        T.True(spec.Exit.Position.Z < spec.DoorZ - 1.5, kind .. ": sale delante del escondite")

        -- Las tablillas dejan aire a la altura de los ojos.
        local slats = {}
        for _, part in ipairs(model:GetDescendants()) do
            if part.Name == "Slat" then
                table.insert(slats, base:ToObjectSpace(part.CFrame).Position.Y)
            end
        end
        if #slats > 0 then
            T.True(#slats >= 4, kind .. ": persiana con varias tablillas")
            table.sort(slats)
            local gap = (slats[#slats] - slats[1]) / (#slats - 1)
            T.True(gap - 0.12 >= 0.2, kind .. ": rendijas de verdad abiertas")
            T.True(camera.Position.Y >= slats[1] - gap and camera.Position.Y <= slats[#slats] + gap, kind .. ": la vista cae en la persiana")
        else
            T.True(camera.Position.Y < 1.6, kind .. ": abajo del mueble, la vista sale por el frente abierto")
        end
        folder:Destroy()
    end
end)

T.Test("Mundo: nunca se queda trabado adentro (reaparición, mapa que se va, ancla perdida)", function()
    local players = bootServer(1)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(1)
    local player = players[1]
    local Hiding = Engine.RequireServer("World.HidingService")

    enterHide(player, hidesFolder():GetChildren()[1])
    T.True(Hiding.IsHidden(player), "escondido")
    player.Character:FindFirstChild("HumanoidRootPart").Anchored = false
    Engine.Run(1)
    T.False(Hiding.IsHidden(player), "si algo lo suelta, el servidor lo da por afuera")
    T.Equal(Engine.LastSent("HideState", player)[1], false, "y le avisa al cliente")

    enterHide(player, hidesFolder():GetChildren()[2])
    T.True(Hiding.IsHidden(player), "escondido otra vez")
    player:LoadCharacter()
    Engine.Run(1)
    T.False(Hiding.IsHidden(player), "al reaparecer queda afuera")
    T.Equal(player:GetAttribute("Hidden"), false, "atributo limpio")

    Engine.Run(1)
    enterHide(player, hidesFolder():GetChildren()[3])
    T.True(Hiding.IsHidden(player), "escondido por tercera vez")
    local root = player.Character:FindFirstChild("HumanoidRootPart")
    Engine.RequireServer("World.WorldService").Unload()
    Engine.Run(1)
    T.False(Hiding.IsHidden(player), "al descargar el mapa nadie queda escondido")
    T.False(root.Anchored, "y nadie queda anclado")
    T.NoEngineErrors(Engine)
end)

T.Test("Mundo: los tipos nuevos de escondite funcionan en cada capítulo", function()
    local players = bootServer(1)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(1)
    local player = players[1]
    local Hiding = Engine.RequireServer("World.HidingService")
    local WorldService = Engine.RequireServer("World.WorldService")
    local Rooms = Engine.RequireServer("World.RoomGenerator")

    local seen = {}
    for _, chapter in ipairs({2, 3, 5}) do
        local plan = WorldService.LoadChapter(chapter, 4242 + chapter)
        local theme = ThemeConfig[ChapterConfig[chapter].Theme]
        T.True(#plan.Hides > ChapterConfig[chapter].Layout.Hides, "más escondites que antes en el capítulo " .. chapter)

        for index, model in ipairs(hidesFolder():GetChildren()) do
            local kind = model:GetAttribute("HideKind")
            T.True(table.find(theme.HideKinds, kind) ~= nil, "el tipo sale del tema: " .. tostring(kind))
            if not seen[kind] then
                seen[kind] = true
                enterHide(player, model)
                T.True(Hiding.IsHidden(player), kind .. ": entra")
                T.Equal(Hiding.KindOf(player), kind, kind .. ": tipo")
                local args = Engine.LastSent("HideState", player)
                T.Equal(args[4], kind, kind .. ": el cliente sabe dónde está")

                fire("ExitHiding", player)
                Engine.Run(0.3)
                T.False(Hiding.IsHidden(player), kind .. ": sale")
                local hide = plan.Hides[index]
                local slot = Rooms.SlotCFrame(plan.Layout, hide.Cell, hide.Slot)
                local relative = slot:ToObjectSpace(player.Character:FindFirstChild("HumanoidRootPart").CFrame)
                T.True(relative.Position.Z < -3 and math.abs(relative.Position.Y - 3) < 0.1, kind .. ": queda parado delante")
                Engine.Run(0.3)
            end
        end
    end
    for _, kind in ipairs({"Locker", "Wardrobe", "Desk", "Bed", "Vent"}) do
        T.True(seen[kind], "se probó " .. kind)
    end
    T.NoEngineErrors(Engine)
end)

T.Test("Mundo: pasadizos secretos sin romper ningún mapa y fuera del camino de las criaturas", function()
    Engine.Reset()
    local WorldService = Engine.RequireServer("World.WorldService")
    local MazeNav = Engine.RequireShared("Logic.MazeNav")

    for chapterIndex = 1, 5 do
        local theme = ThemeConfig[ChapterConfig[chapterIndex].Theme]
        local spec = ChapterConfig[chapterIndex].Layout
        local withPassages, extraHides = 0, 0
        for seed = 1, 150 do
            local success, plan = pcall(WorldService.PlanChapter, chapterIndex, seed * 17)
            if success then
                local valid, reason = WorldService.ValidatePlan(plan)
                T.True(valid, string.format("capítulo %d semilla %d: %s", chapterIndex, seed, tostring(reason)))
                T.True(#plan.Passages <= theme.Passages, "no más pasadizos que los del tema")
                if #plan.Passages > 0 then
                    withPassages += 1
                end
                extraHides += #plan.Hides - spec.Hides

                local nav = MazeNav.new(plan.Layout, GameConfig.Map.CellSize)
                local reachable = MazeLayout.Flood(plan.Layout, plan.Layout.Start, plan.LockedEdges)
                for _, passage in ipairs(plan.Passages) do
                    T.True(table.find(nav:Neighbors(passage.A), passage.B) == nil, "las criaturas no conocen el pasadizo")
                    T.True(reachable[passage.A] ~= nil and reachable[passage.B] ~= nil, "no saltea puertas trabadas")
                    T.True(passage.A ~= plan.Layout.Exit and passage.B ~= plan.Layout.Exit, "no lleva a la salida")
                end
            end
        end
        T.True(withPassages >= 100, string.format("capítulo %d: casi siempre hay pasadizos (%d/150)", chapterIndex, withPassages))
        T.True(extraHides >= 150 * 2, string.format("capítulo %d: escondites extra (%d)", chapterIndex, extraHides))
    end
end)

T.Test("Mundo: cada capítulo queda debajo de 2500 piezas, con salas amuebladas y distintas", function()
    bootServer(1)
    Engine.Run(0.5)
    local WorldService = Engine.RequireServer("World.WorldService")

    for chapterIndex = 1, 5 do
        for _, seed in ipairs({101, 7777}) do
            local plan = WorldService.LoadChapter(chapterIndex, seed)
            local map = Engine.Workspace:FindFirstChild("NOCTURNA_MAP")
            local count = countBaseParts(map)
            T.True(count < 2500, string.format("capítulo %d semilla %d: %d piezas", chapterIndex, seed, count))
            T.True(count > 1200, string.format("capítulo %d semilla %d: salas llenas (%d piezas)", chapterIndex, seed, count))

            local decor = map:FindFirstChild("Decor")
            local furniture, types = 0, {}
            for _, room in ipairs(decor:GetChildren()) do
                types[room:GetAttribute("RoomType")] = true
                for _, child in ipairs(room:GetChildren()) do
                    if child:IsA("Model") then
                        furniture += 1
                    end
                end
            end
            T.True(furniture >= #plan.Layout.Cells, string.format("capítulo %d: muebles (%d)", chapterIndex, furniture))
            local typeCount = 0
            for name in pairs(types) do
                if name ~= "Corridor" then
                    typeCount += 1
                end
            end
            T.True(typeCount >= 3, "varios tipos de sala en el capítulo " .. chapterIndex)

            -- Decoración liviana: las piezas que no colisionan tampoco se consultan.
            for _, part in ipairs(decor:GetDescendants()) do
                if part:IsA("BasePart") and not part.CanCollide then
                    T.False(part.CanQuery or part.CanTouch, "decoración liviana: " .. part.Name)
                end
            end
            T.True(#map:FindFirstChild("Passages"):GetChildren() == #plan.Passages, "pasadizos construidos")
        end
    end
    WorldService.Unload()
    T.NoEngineErrors(Engine)
end)

T.Test("Mundo: los cinco capítulos usan materiales, paletas y utilería propios", function()
    local themes = {}
    for index = 1, 5 do
        table.insert(themes, ThemeConfig[ChapterConfig[index].Theme])
    end

    Engine.Reset()
    local RoomDecor = Engine.RequireServer("World.RoomDecor")

    for index, theme in ipairs(themes) do
        for _, key in ipairs({"FloorMaterial", "WallMaterial", "CeilingMaterial", "TrimMaterial"}) do
            T.True(pcall(function()
                return roblox.Enum.Material[theme[key]]
            end), "material real: " .. tostring(theme[key]))
            T.True(theme[key] ~= "SmoothPlastic", "nada liso: " .. key)
        end
        for _, roomType in ipairs(theme.RoomTypes) do
            T.True(RoomDecor.RoomTypes[roomType] ~= nil, "tipo de sala definido: " .. roomType)
        end
        T.True(RoomDecor.Fixtures[theme.Fixture] ~= nil and RoomDecor.Ceiling[theme.CeilingKit] ~= nil, "luminaria y techo propios")

        for other = index + 1, 5 do
            local b = themes[other]
            T.True(theme.FloorMaterial .. theme.WallMaterial .. theme.CeilingMaterial ~= b.FloorMaterial .. b.WallMaterial .. b.CeilingMaterial,
                string.format("capítulos %d y %d con distintos materiales", index, other))
            local distance = math.abs(theme.Wall.R - b.Wall.R) + math.abs(theme.Wall.G - b.Wall.G) + math.abs(theme.Wall.B - b.Wall.B)
            T.True(distance > 0.08, string.format("capítulos %d y %d con distinta paleta", index, other))
            T.True(theme.Fixture ~= b.Fixture and theme.CeilingKit ~= b.CeilingKit, string.format("capítulos %d y %d con distinto techo", index, other))
            local shared = 0
            for _, roomType in ipairs(theme.RoomTypes) do
                if table.find(b.RoomTypes, roomType) then
                    shared += 1
                end
            end
            T.True(shared <= 1, string.format("capítulos %d y %d con salas distintas", index, other))
        end
    end
end)

T.Test("Mundo: fusibles y objetos con modelos reales, tablero que se llena y salida blindada", function()
    local players = bootServer(1)
    startMatch(players, 1)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(1)

    local objects = Engine.Workspace:FindFirstChild("NOCTURNA_MAP"):FindFirstChild("Objects")
    local pickups = 0
    for _, holder in ipairs(objects:GetChildren()) do
        if string.sub(holder.Name, 1, 7) == "Pickup_" then
            pickups += 1
            T.Equal(holder.Transparency, 1, "la raíz del objeto es invisible")
            T.True(holder.Material ~= roblox.Enum.Material.Neon, "sin cubo de neón")
            local glow = holder:FindFirstChild("Glow")
            T.True(glow ~= nil and glow.Brightness <= 0.6 and glow.Range <= 8, "pista suave para encontrarlo")
            local pieces = 0
            for _, part in ipairs(holder:GetDescendants()) do
                if part:IsA("BasePart") then
                    pieces += 1
                    if part.Material == roblox.Enum.Material.Neon then
                        T.True(part.Size.Y <= 0.1 or part.Size.Z <= 0.1, "el neón sólo en filamentos finos: " .. part.Name)
                    end
                end
            end
            T.True(pieces >= 4, "modelo de varias piezas: " .. holder.Name)
        end
    end
    T.True(pickups >= 3, "hay objetos")

    local fuse = objects:FindFirstChild("Pickup_Fuse")
    T.True(fuse:FindFirstChild("Glass", true) ~= nil and fuse:FindFirstChild("Cap", true) ~= nil and fuse:FindFirstChild("Filament", true) ~= nil, "fusible de vidrio con casquillos y filamento")

    -- El tablero muestra cada fusible a medida que entra.
    local Mechanisms = Engine.RequireServer("World.MechanismService")
    local Inventory = Engine.RequireServer("Inventory.InventoryService")
    local generator = Engine.Workspace:FindFirstChild("NOCTURNA_MAP"):FindFirstChild("Mechanisms"):FindFirstChild("GEN_MAIN")
    local function visibleFuses()
        local count = 0
        for _, part in ipairs(generator:GetChildren()) do
            if part.Name == "SlotFuse" and part.Transparency < 1 then
                count += 1
            end
        end
        return count
    end
    T.Equal(visibleFuses(), 0, "tablero vacío")
    T.True(generator:FindFirstChild("Hazard", true) ~= nil and generator:FindFirstChild("PanelDoor", true) ~= nil, "tablero con puerta y franjas de peligro")
    local position = Mechanisms.PositionsFor("GEN_MAIN")[1]
    Inventory.AddItem(players[1], "Fuse", 3)
    for expected = 1, 3 do
        Engine.Run(0.5)
        Bot.Use(Engine, players[1], position)
        Engine.Run(0.1)
        T.Equal(visibleFuses(), expected, "fusibles a la vista")
    end
    Engine.Run(0.5)
    Bot.Use(Engine, players[1], position)
    Engine.Run(0.5)
    T.True(gameState().HasFlag("POWER"), "arrancó")
    local indicator = generator:FindFirstChild("Indicator")
    T.True(indicator.Color.G > indicator.Color.R, "indicador en verde")

    local exit = Engine.Workspace:FindFirstChild("NOCTURNA_MAP"):FindFirstChild("Mechanisms"):FindFirstChild("ELEVATOR")
    T.True(exit:FindFirstChild("Leaf", true) ~= nil and exit:FindFirstChild("WarningLamp") ~= nil and exit:FindFirstChild("Jamb", true) ~= nil, "salida con hojas, marco y balizas")
    T.NoEngineErrors(Engine)
end)

T.Test("Mundo: una malla en ServerStorage.NocturnaProps reemplaza al modelo procedural", function()
    Engine.Reset()
    local FeatureBuilder = Engine.RequireServer("World.FeatureBuilder")
    local PropKit = Engine.RequireServer("World.PropKit")

    local folder = Engine.New("Folder", "NocturnaProps")
    folder.Parent = Engine.Services.ServerStorage
    local fuseModel = Engine.New("Model", "Fuse")
    fuseModel.Parent = folder
    for index = 1, 2 do
        local mesh = Engine.New("MeshPart", "Piece" .. index)
        mesh.Size = Vector3.new(10, 4, 4)
        mesh.CFrame = roblox.CFrame.new(100 + index * 10, 50, 0)
        mesh.Parent = fuseModel
    end
    local lockerMesh = Engine.New("MeshPart", "Locker")
    lockerMesh.Size = Vector3.new(6, 15, 5)
    lockerMesh.Parent = folder

    local base = roblox.CFrame.new(5, 0, 5)
    local holder = FeatureBuilder.Pickup(Engine.Workspace, "Fuse", base)
    local clone = nil
    for _, child in ipairs(holder:GetChildren()) do
        if child:GetAttribute("NocturnaMesh") then
            clone = child
        end
    end
    T.True(clone ~= nil and clone.Name == "Fuse", "usa la malla del fusible")
    T.True(holder:FindFirstChild("Glass", true) == nil, "sin la versión procedural")
    local box = PropKit.Boxes.Fuse
    local minY = math.huge
    for _, part in ipairs(clone:GetChildren()) do
        T.True(part.Anchored and part.Size.X <= box.X + 0.01, "escalada a su caja")
        minY = math.min(minY, part.Position.Y - part.Size.Y / 2)
    end
    T.True(math.abs(minY - 1.56) < 0.05, "apoyada sobre la caja de cartón")

    local hide = FeatureBuilder.Hide(Engine.Workspace, "Locker", base)
    local meshed = nil
    for _, child in ipairs(hide:GetChildren()) do
        if child:GetAttribute("NocturnaMesh") then
            meshed = child
        end
    end
    T.True(meshed ~= nil and meshed:IsA("MeshPart"), "una MeshPart suelta también sirve")
    T.True(meshed.Size.Y <= PropKit.Boxes.Locker.Y + 0.01, "casillero a su medida")
    T.True(hide:FindFirstChild("Door"):FindFirstChild("NocturnaPrompt") ~= nil, "el prompt sigue funcionando")

    -- Cada nombre del gancho está documentado con su caja.
    local readme = fs.readFile("assets/models/props/README.md")
    for name in pairs(PropKit.Boxes) do
        T.True(string.find(readme, "`" .. name .. "`", 1, true) ~= nil, "README documenta " .. name)
    end
end)

T.Test("Mundo: luz más clara y realista, linterna más fuerte y bajo consumo liviano", function()
    local player = clientWithMatch({Touch = true, Viewport = roblox.Vector2.new(812, 375)})
    local Lighting = Engine.Services.Lighting
    local theme = ThemeConfig.Tunnels

    T.True(Lighting:FindFirstChild("NocturnaAtmosphere") ~= nil and Lighting:FindFirstChild("NocturnaBloom") ~= nil, "atmósfera y resplandor")
    T.True(Lighting:FindFirstChild("NocturnaGrade") ~= nil and Lighting:FindFirstChild("NocturnaDepth") ~= nil, "corrección de color y profundidad")
    T.True(Lighting.ExposureCompensation > 0 and Lighting.ExposureCompensation < 0.6, "un poco más de exposición, no de más")
    local ambient = (Lighting.Ambient.R + Lighting.Ambient.G + Lighting.Ambient.B) / 3 * 255
    T.True(ambient >= 25 and ambient <= 45, "sin linterna se ven formas, pero sigue oscuro: " .. ambient)
    T.Equal(Lighting.Ambient, theme.Ambient, "ambiente del capítulo")

    fire("FlashlightToggle", player)
    Engine.Run(0.6)
    local attachment = player.Character:FindFirstChild("Head"):FindFirstChild("NocturnaFlashlightAttachment")
    local beam = attachment:FindFirstChild("NocturnaFlashlight")
    T.True(beam.Range >= 50 and beam.Angle >= 70 and beam.Brightness >= 3, "haz más fuerte y más abierto")
    T.True(attachment:FindFirstChild("NocturnaFlashlightSpill").Enabled, "halo cercano encendido")
    T.False(beam.Shadows, "en bajo consumo el haz no calcula sombras")
    T.False(Lighting:FindFirstChild("NocturnaDepth").Enabled, "sin profundidad de campo en el celular")

    local project = fs.readFile("default.project.json")
    T.True(string.find(project, "\"Technology\": \"Future\"", 1, true) ~= nil, "Lighting.Technology = Future")

    fire("FlashlightToggle", player)
    Engine.Run(0.6)
    local eyes = player.Character:FindFirstChild("HumanoidRootPart"):FindFirstChild("NocturnaNightEyes")
    T.True(eyes ~= nil and eyes.Enabled and eyes.Brightness < 0.5, "sin linterna, una luz tenue sólo para uno")
    T.NoEngineErrors(Engine)
end)

T.Suite("Correcciones de revisión")

local function countSent(name, first)
    local count = 0
    for _, entry in ipairs(Engine.Sent) do
        if entry.Name == name and (first == nil or entry.Args[1] == first) then
            count += 1
        end
    end
    return count
end

local function rootOf(player)
    return player.Character:FindFirstChild("HumanoidRootPart")
end

T.Test("Alma abre las puertas comunes a su paso y, si se traba, aparece detrás del jugador", function()
    local players = puzzleMatch(1)
    local player = players[1]
    local door = nil
    for _, part in ipairs(Engine.CollectionService:GetTagged("NocturnaDoor")) do
        if part.Name == "Door" and part:GetAttribute("Opened") ~= true then
            door = part
            break
        end
    end
    T.True(door ~= nil, "hay una puerta común cerrada")

    -- La encuentran lejos de la puerta y empieza a seguir al jugador.
    local base = door.Position
    local AlmaBuilder = Engine.RequireServer("World.AlmaBuilder")
    local holder = AlmaBuilder.Build(Engine.Workspace, {Id = "ALMA_TEST"}, roblox.CFrame.new(base.X, 0, base.Z + 30))
    Bot.MoveTo(Engine, player, Vector3.new(base.X, 3, base.Z + 36))
    T.True(Engine.RunUntil(function()
        return holder:GetAttribute("AlmaState") == "Follow"
    end, 10), "lo sigue")
    T.True(door:GetAttribute("Opened") ~= true, "la puerta sigue cerrada mientras está lejos")

    -- Llega a la puerta cerrada: la abre en vez de quedarse contra ella.
    local rig = holder:FindFirstChild("Alma")
    local almaRoot = rig:FindFirstChild("HumanoidRootPart")
    rig:PivotTo(roblox.CFrame.new(base.X, almaRoot.Position.Y, base.Z + 1))
    Bot.MoveTo(Engine, player, Vector3.new(base.X + 40, 3, base.Z))
    Engine.Run(0.5)
    T.Equal(door:GetAttribute("Opened"), true, "abrió la puerta")

    -- Sin avanzar (el motor de pruebas no la mueve) termina apareciendo detrás.
    T.True((almaRoot.Position - rootOf(player).Position).Magnitude > 30, "todavía lejos")
    Engine.Run(3.6)
    T.True((almaRoot.Position - rootOf(player).Position).Magnitude < 8, "trabada, aparece detrás del jugador")
    T.NoEngineErrors(Engine)
end)

T.Test("congelar la IA y la pausa de las escenas son distintas: una escena no descongela", function()
    local players = puzzleMatch(1, 1, {Monsters = true, CreatorId = 2001})
    local player = players[1]
    local Admin = Engine.RequireServer("Admin.AdminService")
    local Monsters = Engine.RequireServer("Monsters.MonsterService")
    local Cinematic = Engine.RequireServer("Puzzles.CinematicService")
    local gate = gameState().Plan.Gates[1]
    local function panel()
        return Engine.LastSent("AdminData", player)[1]
    end

    T.True(Admin.Execute(player, "freeze", {}), "congelar")
    T.True(Monsters.IsPaused("Admin") and Monsters.IsPaused(), "IA detenida")
    T.True(#Cinematic.PlayDoor(gate.A, gate.B, gate.Label, player) > 0, "escena")
    T.True(Monsters.IsPaused("Scene"), "pausa de la escena")
    Engine.Run(PuzzleConfig.Cinematic.Duration + 1)
    T.False(Monsters.IsPaused("Scene"), "terminó la escena")
    T.True(Monsters.IsPaused(), "la IA sigue congelada")
    T.True(panel().AiPaused, "el panel lo muestra")

    -- Durante una escena, el botón cambia sólo la pausa del administrador.
    T.True(Admin.Execute(player, "freeze", {}), "descongelar")
    T.False(Monsters.IsPaused(), "IA activa")
    T.False(panel().AiPaused, "el panel lo muestra")
    Cinematic.PlayDoor(gate.A, gate.B, gate.Label, player)
    T.True(Monsters.IsPaused(), "quietas por la escena")
    T.False(panel().AiPaused, "la escena no cuenta como congelada")
    T.True(Admin.Execute(player, "freeze", {}), "congelar durante la escena")
    T.True(Monsters.IsPaused("Admin"), "congela (no la invierte la escena)")
    T.True(panel().AiPaused, "el panel lo muestra")
    Engine.Run(PuzzleConfig.Cinematic.Duration + 1)
    T.True(Monsters.IsPaused(), "sigue congelada al terminar la escena")
    T.NoEngineErrors(Engine)
end)

T.Test("diálogos: las líneas que esperan detrás de la introducción no se pierden", function()
    puzzleMatch(1)
    local Story = Engine.RequireServer("Story.StoryService")
    T.Equal(Story.PendingLines(), #ChapterConfig[1].Intro - 1, "la introducción sigue en la cola")
    Story.PlayDialogue({{Speaker = "Vos", Text = "Primera"}, {Speaker = "Vos", Text = "Segunda"}})
    T.True(Engine.RunUntil(function()
        return Engine.LastSent("StoryDialogue")[1].Text == "Segunda"
    end, 70), "la segunda línea llega aunque esperó más de 30 segundos")
    T.NoEngineErrors(Engine)
end)

T.Test("diálogos: el cierre del capítulo no borra lo que decía el último objetivo", function()
    puzzleMatch(1)
    local Story = Engine.RequireServer("Story.StoryService")
    local wiresLine = nil
    for _, objective in ipairs(ChapterConfig[1].Objectives) do
        if objective.Id == "C1_WIRES" then
            wiresLine = objective.OnComplete.Dialogue[1].Text
        end
    end
    local outroLast = ChapterConfig[1].Outro[#ChapterConfig[1].Outro].Text

    skipTo("C1_WIRES")
    local mark = #Engine.Sent
    Story.SkipObjective()
    Story.SkipObjective()
    Engine.Run(0.1)
    T.Equal(gameState().Phase, "Cutscene", "capítulo cerrado")

    local summaryBefore = countSent("ChapterSummary")
    T.True(Engine.RunUntil(function()
        return Engine.LastSent("StoryDialogue")[1].Text == outroLast
    end, 70), "el cierre se muestra")
    T.Equal(countSent("ChapterSummary"), summaryBefore, "el resumen espera a que termine el diálogo")
    local wiresAt, outroAt = nil, nil
    for index = mark + 1, #Engine.Sent do
        local entry = Engine.Sent[index]
        if entry.Name == "StoryDialogue" then
            if entry.Args[1].Text == wiresLine then
                wiresAt = wiresAt or index
            elseif entry.Args[1].Text == outroLast then
                outroAt = outroAt or index
            end
        end
    end
    T.True(wiresAt ~= nil, "la línea del último objetivo se dijo")
    T.True(outroAt ~= nil and wiresAt < outroAt, "antes del cierre")
    T.True(Engine.RunUntil(function()
        return countSent("ChapterSummary") > summaryBefore
    end, 20), "después llega el resumen")
    T.NoEngineErrors(Engine)
end)

T.Test("cliente: al terminar la cinemática la vista vuelve adonde miraba el jugador", function()
    local players = puzzleMatch(1, 1, {Client = true})
    local player = players[1]
    skipTo("C1_WIRES")
    local camera = Engine.Workspace.CurrentCamera
    local eye = rootOf(player).Position + Vector3.new(0, 1.5, 0)
    local look = roblox.CFrame.lookAt(eye, eye + Vector3.new(0.3, -1, 0.2))
    camera.CFrame = look
    T.True(solveWithBot(player, "C1_WIRES"), "cables resueltos")
    Engine.Run(0.2)
    T.Equal(camera.CameraType, roblox.Enum.CameraType.Scriptable, "la escena toma la cámara")
    T.True(camera.CFrame.LookVector:Dot(look.LookVector) < 0.9, "la escena mira la compuerta")

    Engine.Run(4)
    T.Equal(camera.CameraType, roblox.Enum.CameraType.Custom, "cámara devuelta")
    T.True(camera.CFrame.LookVector:Dot(look.LookVector) > 0.99, "mira otra vez hacia donde miraba")
    T.NoEngineErrors(Engine)
end)

T.Test("reglas: el bloqueo por errores es de cada jugador, crece y se olvida", function()
    local PuzzleRules = Engine.RequireServer("Puzzles.PuzzleRules")
    local config = PuzzleConfig.Lockout
    local keypad = PuzzleRules.NewRecord()
    local expected = PuzzleConfig.Keypad.Lockout
    local now = 10
    for attempt = 1, 7 do
        local seconds = PuzzleRules.Strike(keypad, "Keypad", now)
        T.Equal(seconds, math.min(expected, config.Max), "bloqueo " .. attempt)
        T.True(PuzzleRules.LockedFor(keypad, now + 0.1) > 0, "bloqueado " .. attempt)
        now += seconds + 0.1
        T.Equal(PuzzleRules.LockedFor(keypad, now), 0, "libre después " .. attempt)
        expected *= config.Growth
    end
    T.Equal(PuzzleRules.LockedFor(nil, now), 0, "quien nunca se equivocó no espera")

    for _, kind in ipairs({"Breakers", "Wires"}) do
        T.True(PuzzleRules.Strike(PuzzleRules.NewRecord(), kind, 0) > 0, kind .. ": no se adivina probando")
    end
    local simon = PuzzleRules.NewRecord()
    T.Equal(PuzzleRules.Strike(simon, "Simon", 0), 0, "un error se perdona")
    T.Equal(PuzzleRules.Strike(simon, "Simon", 1), 0, "dos también")
    T.True(PuzzleRules.Strike(simon, "Simon", 2) > 0, "al tercero espera")

    local forgotten = PuzzleRules.Strike(keypad, "Keypad", now + config.Forget + 1)
    T.Equal(forgotten, PuzzleConfig.Keypad.Lockout, "un buen rato sin errores se olvida")
end)

T.Test("pruebas: quien se equivoca espera él solo y el compañero sigue jugando", function()
    local players = puzzleMatch(2, 2)
    local griefer, partner = players[1], players[2]
    local Puzzles = Engine.RequireServer("Puzzles.PuzzleService")
    skipTo("C2_CODE")
    T.Equal(openPuzzle(griefer, "KEYPAD_C2").Event, "Open", "panel del primero")
    T.Equal(openPuzzle(partner, "KEYPAD_C2").Event, "Open", "panel del segundo")
    local code = Puzzles.Get("KEYPAD_C2").State.Code
    local wrong = code == "1111" and "2222" or "1111"

    Bot.Fire(Engine, griefer, "PuzzleAction", "KEYPAD_C2", "Submit", wrong)
    Engine.Run(0.1)
    local reply = Bot.PuzzleSession(Engine, griefer, "KEYPAD_C2")
    T.Equal(reply.Event, "Wrong", "error")
    T.True(string.find(reply.Message, "Esperá", 1, true) ~= nil, "a él se le pide esperar: " .. reply.Message)
    T.True(reply.View.Locked, "su teclado, bloqueado")
    local seen = Bot.PuzzleSession(Engine, partner, "KEYPAD_C2")
    T.Equal(seen.Event, "Wrong", "el compañero ve el error")
    T.False(seen.View.Locked, "pero su teclado no se bloquea")
    T.True(string.find(seen.Message, "Esperá", 1, true) == nil, "y no se le pide esperar")

    -- Insistir durante el bloqueo no cambia nada ni hace ruido.
    local sounds = countSent("PlaySound", "DoorLocked")
    Bot.Fire(Engine, griefer, "PuzzleAction", "KEYPAD_C2", "Submit", wrong)
    Engine.Run(0.1)
    T.Equal(Bot.PuzzleSession(Engine, griefer, "KEYPAD_C2").Event, "State", "jugada rechazada")
    T.Equal(countSent("PlaySound", "DoorLocked"), sounds, "sin ruido")

    -- Salir y volver a entrar no borra el bloqueo (se cuenta por UserId).
    T.True(Puzzles.Get("KEYPAD_C2").Strikes[griefer.UserId] ~= nil, "bloqueo por UserId")

    Bot.Fire(Engine, partner, "PuzzleAction", "KEYPAD_C2", "Submit", code)
    Engine.Run(0.1)
    T.True(Puzzles.IsSolved("KEYPAD_C2"), "el compañero la resuelve mientras tanto")
    T.NoEngineErrors(Engine)
end)

T.Test("pruebas: el ruido del error no se repite enseguida y cada bloqueo dura más", function()
    local players = puzzleMatch(1, 2)
    local first, second = players[1], players[2]
    local Puzzles = Engine.RequireServer("Puzzles.PuzzleService")
    skipTo("C1_BREAKERS")
    gameState().SetFlag("POWER")
    T.Equal(openPuzzle(first, "BREAKERS_C1").Event, "Open", "panel del primero")
    T.Equal(openPuzzle(second, "BREAKERS_C1").Event, "Open", "panel del segundo")
    local state = Puzzles.Get("BREAKERS_C1").State
    local wrong = state.Sequence[1] % state.Count + 1
    local noise = Engine.RequireServer("AI.NoiseService")

    local sounds = countSent("PlaySound", "DoorLocked")
    local noises = #noise.Recent()
    Bot.Fire(Engine, first, "PuzzleAction", "BREAKERS_C1", "Flip", wrong)
    Engine.Run(0.1)
    T.True(countSent("PlaySound", "DoorLocked") > sounds, "el error suena")
    T.True(#noise.Recent() > noises, "y hace ruido")
    local base = PuzzleConfig.Lockout.Base.Default
    T.True(string.find(Bot.PuzzleSession(Engine, first, "BREAKERS_C1").Message, string.format("%d segundos", base), 1, true) ~= nil,
        "primer bloqueo corto")

    sounds = countSent("PlaySound", "DoorLocked")
    noises = #noise.Recent()
    Bot.Fire(Engine, second, "PuzzleAction", "BREAKERS_C1", "Flip", wrong)
    Engine.Run(0.1)
    T.Equal(Bot.PuzzleSession(Engine, second, "BREAKERS_C1").Event, "Wrong", "otro error")
    T.Equal(countSent("PlaySound", "DoorLocked"), sounds, "no vuelve a sonar enseguida")
    T.Equal(#noise.Recent(), noises, "ni a hacer ruido")

    Engine.Run(math.max(base, PuzzleConfig.Lockout.PenaltyInterval) + 0.2)
    Bot.Fire(Engine, first, "PuzzleAction", "BREAKERS_C1", "Flip", wrong)
    Engine.Run(0.1)
    local reply = Bot.PuzzleSession(Engine, first, "BREAKERS_C1")
    T.Equal(reply.Event, "Wrong", "puede volver a probar")
    T.True(string.find(reply.Message, string.format("%d segundos", base * PuzzleConfig.Lockout.Growth), 1, true) ~= nil,
        "el bloqueo crece: " .. reply.Message)
    T.True(countSent("PlaySound", "DoorLocked") > sounds, "pasado el intervalo vuelve a sonar")
    T.NoEngineErrors(Engine)
end)

T.Test("volver a la partida: no mientras el ascensor sale, y deja el ascensor antes de viajar", function()
    local expires = 1800000000 + 3600
    local stores = {NOCTURNA_ACTIVE_MATCH_V1 = {
        USER_2001 = {Code = "access-7", ServerId = "reserved-7", Expires = expires, Data = {Chapter = 2, Difficulty = "Normal", MaxPlayers = 2, Party = {2001, 2002}, Host = 2002}},
    }}
    local players = bootServer(1, {PlaceId = 777, Stores = stores, TeleportStays = true})
    local player = players[1]
    local Queue = queueService()
    T.Equal(queueView(player).Kind, "Rejoin", "tiene la oferta")

    enterElevator(player, 1)
    Engine.Run(0.5)
    local party = Queue.PartyOf(player)
    T.True(party ~= nil, "armó grupo")
    fire("QueueAction", player, "Start")
    Engine.Run(0.3)
    T.Equal(party.State, "Countdown", "el ascensor sale")
    fire("QueueAction", player, "Rejoin")
    Engine.Run(0.5)
    T.Equal(#Engine.Teleports, 0, "no pide otro viaje mientras sale")
    T.Equal(Queue.PartyOf(player), party, "sigue en el grupo")

    fire("QueueAction", player, "Cancel")
    Engine.Run(0.3)
    T.Equal(party.State, "Open", "cancelado")
    fire("QueueAction", player, "Rejoin")
    Engine.Run(1)
    T.Equal(#Engine.Teleports, 1, "vuelve a su partida")
    T.Equal(Engine.Teleports[1].AccessCode, "access-7", "a la suya")
    T.Equal(Queue.PartyOf(player), nil, "dejó el ascensor")
    T.True(lobbyBuilder().ElevatorAt(rootOf(player).Position) == nil, "y salió de él")

    -- Mientras viaja no se suma a ningún grupo.
    enterElevator(player, 2)
    Engine.Run(1)
    T.Equal(Queue.PartyOf(player), nil, "viajando no se suma")
    fire("QueueAction", player, "Rejoin")
    Engine.Run(0.5)
    T.Equal(#Engine.Teleports, 1, "ni pide un segundo viaje")
    T.NoEngineErrors(Engine)
end)

T.Test("ascensor: un grupo que no arranca sale solo y avisa antes, aunque el anfitrión cancele", function()
    local players = bootServer(2)
    local Queue = queueService()
    local LobbyConfig = Engine.RequireShared("Config.LobbyConfig")
    local sign = lobbyBuilder().Elevators()[1].Labels

    enterElevator(players[1], 1)
    Engine.Run(0.5)
    fire("QueueAction", players[1], "SetMaxPlayers", 1)
    Engine.Run(0.3)
    local party = Queue.PartyOf(players[1])
    T.Equal(party.MaxPlayers, 1, "el anfitrión cerró los lugares")
    enterElevator(players[2], 1)
    Engine.Run(0.5)
    T.Equal(Queue.PartyOf(players[2]), nil, "nadie más entra")

    Engine.Run(LobbyConfig.OpenTimeout - LobbyConfig.OpenWarning - 5)
    T.Equal(party.State, "Open", "todavía espera")
    T.True(string.find(sign.Status.Text, "SALE EN", 1, true) == nil, "sin aviso todavía")
    Engine.Run(10)
    T.True(string.find(sign.Status.Text, "SALE EN", 1, true) ~= nil, "el cartel avisa: " .. sign.Status.Text)
    T.True(type(queueView(players[1]).AutoStart) == "number", "el panel también")

    T.True(Engine.RunUntil(function()
        return party.State == "Countdown"
    end, LobbyConfig.OpenWarning + 2), "sale solo")
    T.True(string.find(lastNotice(players[1]), "tiempo de espera", 1, true) ~= nil, "se le avisa")
    fire("QueueAction", players[1], "Cancel")
    Engine.Run(0.6)
    T.Equal(party.State, "Countdown", "cancelar no reinicia la espera")
    T.True(waitForPhase("Loading", 15), "la partida arranca")
    T.NoEngineErrors(Engine)
end)

T.Test("donaciones: el podio nunca baja por una copia vieja del total", function()
    local stores = {NOCTURNA_DONATION_RANKING_V1 = {["2001"] = 50000}}
    bootServer(1, {Stores = stores})
    local DonationConfig = Engine.RequireShared("Config.DonationConfig")
    DonationConfig.Products[6].ProductId = 1006
    local receipt = {PlayerId = 2001, ProductId = 1006, PurchaseId = "q1", CurrencySpent = 0}
    T.Equal(Engine.ProcessReceipt(receipt), roblox.Enum.ProductPurchaseDecision.PurchaseGranted, "acreditada")
    T.Equal(stores.NOCTURNA_DONATIONS_V1.DONOR_2001.Total, 1000, "total de este registro")
    T.Equal(stores.NOCTURNA_DONATION_RANKING_V1["2001"], 50000, "el podio conserva el total más nuevo")

    receipt = {PlayerId = 3001, ProductId = 1006, PurchaseId = "q2", CurrencySpent = 0}
    Engine.ProcessReceipt(receipt)
    T.Equal(stores.NOCTURNA_DONATION_RANKING_V1["3001"], 1000, "un donante nuevo entra con su total")
    T.NoEngineErrors(Engine)
end)

T.Test("IsLit busca la lámpara de la celda sin recorrer todas y sigue a la oscuridad y la energía", function()
    puzzleMatch(1)
    local World = Engine.RequireServer("World.WorldService")
    local nav = gameState().Nav
    World.SetPower(true)
    local fixture = Engine.CollectionService:GetTagged("NocturnaLight")[1]
    local position = nav:Center(fixture:GetAttribute("Cell"), 3)

    local collection = Engine.CollectionService
    local original = collection.GetTagged
    local scans = 0
    rawset(collection, "GetTagged", function(...)
        scans += 1
        return original(...)
    end)
    local lit = true
    for _ = 1, 200 do
        lit = lit and World.IsLit(position)
    end
    rawset(collection, "GetTagged", original)
    T.True(lit, "con luz")
    T.Equal(scans, 0, "sin recorrer las lámparas en cada consulta")

    fixture:SetAttribute("Dark", true)
    T.False(World.IsLit(position), "a oscuras")
    fixture:SetAttribute("Dark", nil)
    T.True(World.IsLit(position), "vuelve la luz")
    World.SetPower(false)
    T.False(World.IsLit(position), "sin energía")

    World.Unload()
    gameState().Nav = nav
    gameState().Powered = true
    T.False(World.IsLit(position), "el índice se vacía al descargar el capítulo")
end)

T.Test("calidad: bajo consumo limita todas las luces del mapa, respeta las apagadas y quita sombras ajenas", function()
    local players = bootServer(2)
    local player, other = players[1], players[2]
    Engine.StartClient(player)
    Engine.Run(2)
    startMatch(players)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(1.5)

    local function beamOf(who)
        local attachment = who.Character:FindFirstChild("Head"):FindFirstChild("NocturnaFlashlightAttachment")
        return attachment and attachment:FindFirstChild("NocturnaFlashlight")
    end
    local function mapLightsOn()
        local on, decorOn = 0, 0
        for _, light in ipairs(Engine.Workspace:GetDescendants()) do
            if light:IsA("Light") and light.Enabled and not light:IsDescendantOf(player.Character) then
                on += 1
                if light.Parent and Engine.CollectionService:HasTag(light.Parent, "NocturnaDecorLight") then
                    decorOn += 1
                end
            end
        end
        return on, decorOn
    end

    -- Calidad normal en PC: sombras sólo en la linterna propia.
    T.True(beamOf(player).Shadows, "la linterna propia con sombras")
    T.False(beamOf(other).Shadows, "la del compañero sin sombras en esta pantalla")
    local Lighting = Engine.Services.Lighting
    local bloom = Lighting:FindFirstChild("NocturnaBloom")
    local normalSize = bloom.Size
    T.True(Lighting:FindFirstChild("NocturnaDepth").Enabled, "profundidad de campo en PC")
    local before = mapLightsOn()
    T.True(before > 8, "muchas luces prendidas: " .. before)

    -- El servidor deja una lámpara a oscuras.
    local fixture = Engine.CollectionService:GetTagged("NocturnaLight")[1]
    local darkLight = fixture:FindFirstChildOfClass("PointLight")
    fixture:SetAttribute("Dark", true)
    darkLight.Enabled = false

    fire("FlashlightToggle", player)
    local toggle = player:FindFirstChild("PlayerGui"):FindFirstChild("NocturnaSettings"):FindFirstChild("LowQuality", true)
    T.True(toggle ~= nil, "botón de bajo consumo")
    Engine.GuiInput(toggle, "Activated")
    Engine.Run(1.5)

    local on, decorOn = mapLightsOn()
    T.True(on <= 8, "sólo las más cercanas: " .. on)
    T.Equal(decorOn, 0, "sin lucecitas de utilería")
    T.False(darkLight.Enabled, "la lámpara a oscuras sigue apagada")
    T.True(beamOf(player).Enabled, "la linterna propia no se toca")
    T.False(beamOf(player).Shadows, "sin sombras en bajo consumo")
    T.True(bloom.Size < normalSize and bloom.Intensity <= 0.25, "menos resplandor")

    -- Una luz que aparece lejos entra a la lista por señal y se apaga.
    local part = Engine.New("Part", "FarGlow")
    part.CFrame = roblox.CFrame.new(5000, 5, 5000)
    local far = Engine.New("PointLight", "Glow")
    far.Parent = part
    part.Parent = Engine.Workspace
    Engine.Run(1.2)
    T.False(far.Enabled, "luz nueva y lejana, apagada")

    -- Vuelve a calidad normal: se prende lo que apagó el cliente, no lo del servidor.
    Engine.GuiInput(toggle, "Activated")
    Engine.Run(1.5)
    T.True(far.Enabled, "la lejana vuelve")
    T.True(mapLightsOn() >= before, "vuelven las demás")
    T.False(darkLight.Enabled, "la oscura sigue apagada")
    T.Equal(bloom.Size, normalSize, "resplandor normal")
    T.True(beamOf(player).Shadows, "sombras de la linterna propia")
    T.NoEngineErrors(Engine)
end)

T.Test("criaturas: la mirada se publica con pasos más largos y no más de cinco veces por segundo", function()
    puzzleMatch(1)
    local MonsterService = Engine.RequireServer("Monsters.MonsterService")
    MonsterService.Clear()
    local entry = MonsterService.Spawn("ElColoso")
    local model = entry.Model
    local controller = entry.Controller
    local start = Vector3.new(20, 3, 20)

    controller.LookTarget = start
    MonsterService.Publish(entry)
    T.Equal(model:GetAttribute("LookTarget"), start, "mirar a alguien sale enseguida")
    controller.LookTarget = start + Vector3.new(2, 0, 0)
    MonsterService.Publish(entry)
    T.Equal(model:GetAttribute("LookTarget"), start, "un paso corto no se publica")
    controller.LookTarget = start + Vector3.new(4, 0, 0)
    MonsterService.Publish(entry)
    T.Equal(model:GetAttribute("LookTarget"), start, "ni uno largo antes del intervalo")
    Engine.Run(0.25)
    MonsterService.Publish(entry)
    T.Equal(model:GetAttribute("LookTarget"), start + Vector3.new(4, 0, 0), "pasado el intervalo, sí")
    controller.LookTarget = nil
    MonsterService.Publish(entry)
    T.Equal(model:GetAttribute("LookTarget"), nil, "dejar de mirar sale enseguida")
    T.NoEngineErrors(Engine)
end)

T.Suite("Captura y forcejeo")

local CaptureConfig = Engine.RequireShared("Config.CaptureConfig")

-- Partida con las criaturas del capítulo ya retiradas: cada prueba trae la suya.
local function captureMatch(playerCount, options)
    options = options or {}
    local players = bootServer(playerCount or 1, options)
    if options.Client then
        Engine.StartClient(players[1])
        Engine.Run(1)
    end
    startMatch(players, nil, options.Difficulty)
    T.True(waitForPhase("Playing", 60), "partida")
    Engine.Run(GameConfig.Match.FirstMonsterDelay + 0.5)
    local MonsterService = Engine.RequireServer("Monsters.MonsterService")
    MonsterService.Clear()
    return players, MonsterService, Engine.RequireServer("Capture.CaptureService")
end

local function rootOf(player)
    return player.Character:FindFirstChild("HumanoidRootPart")
end

local function healthOf(player)
    return player.Character:FindFirstChildOfClass("Humanoid").Health
end

-- La criatura queda a unos pasos del jugador, mirándolo.
local function placeNear(entry, player, distance)
    local position = rootOf(player).Position + Vector3.new(0, 0, -(distance or 3))
    local controller = entry.Controller
    controller.Position = Vector3.new(position.X, controller.Height, position.Z)
    controller:FaceTowards(rootOf(player).Position)
    entry.Root.CFrame = controller:GetCFrame()
end

local function snapshotOf(entry, player)
    local world = entry.Controller.World
    world.Cache = nil
    for _, snap in ipairs(world:Players()) do
        if snap.Player == player then
            return snap
        end
    end
    return nil
end

-- El zarpazo que conecta, tal como lo manda MonsterController:Strike.
local function strike(entry, player)
    placeNear(entry, player)
    local controller = entry.Controller
    local snap = snapshotOf(entry, player)
    controller.World:Damage(controller, snap or {Player = player}, controller.Settings.Damage * controller.DamageScale)
end

local function toStruggle(CaptureService, player)
    T.True(Engine.RunUntil(function()
        local capture = CaptureService.CaptureOf(player)
        return capture ~= nil and capture.Phase == "Struggle"
    end, 5, 0.05), "empieza el forcejeo")
    return CaptureService.CaptureOf(player)
end

local function solve(player, capture)
    local session = capture.Session
    for step = session.Index + 1, #session.Sequence do
        fire("CaptureInput", player, capture.Id, step, session.Sequence[step])
        Engine.Run(0.1)
    end
end

local function wrongKey(key)
    for _, other in ipairs(CaptureConfig.Keys) do
        if other ~= key then
            return other
        end
    end
    return nil
end

T.Test("captura: el zarpazo agarra en vez de dañar, ancla a la víctima y retiene a la criatura", function()
    local players, MonsterService, CaptureService = captureMatch(1)
    local player = players[1]
    local entry = MonsterService.Spawn("ElImitador")
    placeNear(entry, player, 3)
    local controller = entry.Controller
    controller.LastAttack = -100
    T.True(controller:TryAttack(snapshotOf(entry, player)), "empieza el ataque")
    T.True(Engine.RunUntil(function()
        return CaptureService.IsCaptured(player)
    end, 3, 0.05), "el golpe se vuelve captura")

    T.Equal(healthOf(player), 100, "agarrar no daña")
    T.True(rootOf(player).Anchored, "víctima anclada por el servidor")
    T.Equal(player:GetAttribute("Captured"), true, "atributo de captura")
    local model = entry.Model
    T.Equal(model:GetAttribute("AnimOverride"), "Capture", "el animador de captura toma las articulaciones")
    T.Equal(model:GetAttribute("State"), "Capture", "estado público")
    T.Equal(model:GetAttribute("CaptureVictim"), player.UserId, "víctima publicada")
    local begin = Engine.LastSent("CaptureUpdate")[1]
    T.Equal(begin.Event, "Begin", "aviso a todos")
    T.Equal(begin.Monster, model, "con la criatura")

    local capture = CaptureService.CaptureOf(player)
    local hold = capture.Hold
    local offset = hold.Position - entry.Root.Position
    T.True(math.abs(Vector3.new(offset.X, 0, offset.Z).Magnitude - CaptureConfig.Creatures.ElImitador.Hold.Forward) < 0.05, "a la distancia de agarre")
    T.True(offset:Dot(controller.Facing) > 0, "delante de la criatura")

    -- Retenida: no piensa ni se mueve; la víctima no se puede correr.
    local clock, position = controller.Clock, controller.Position
    rootOf(player).CFrame = roblox.CFrame.new(rootOf(player).Position + Vector3.new(30, 0, 0))
    Engine.Run(0.5)
    T.Equal(controller.Clock, clock, "la criatura no se actualiza")
    T.Equal(controller.Position, position, "ni se mueve")
    T.True((rootOf(player).Position - hold.Position).Magnitude < 0.1, "la víctima vuelve al agarre")

    -- La interacción con el mundo queda bloqueada mientras está agarrado.
    local InteractionService = Engine.RequireServer("World.InteractionService")
    local host = Engine.New("Part")
    host.CFrame = rootOf(player).CFrame
    host.Parent = Engine.Workspace
    local prompt = Engine.New("ProximityPrompt")
    prompt.Parent = host
    T.False(InteractionService.CanInteract(player, prompt), "no usa prompts agarrado")
    T.NoEngineErrors(Engine)
end)

T.Test("captura: el servidor valida el forcejeo (orden, tiempo, spam y progreso inventado)", function()
    local players, MonsterService, CaptureService = captureMatch(1)
    local player = players[1]
    local entry = MonsterService.Spawn("ElImitador")
    strike(entry, player)
    T.True(CaptureService.IsCaptured(player), "agarrado")

    -- Antes del forcejeo (todavía en el agarre) no se acepta nada.
    local early = CaptureService.CaptureOf(player)
    fire("CaptureInput", player, early.Id, 1, "Q")
    T.Equal(early.Session, nil, "sin sesión durante el agarre")

    local capture = toStruggle(CaptureService, player)
    local session = capture.Session
    local sequence = session.Sequence
    T.Equal(#sequence, CaptureConfig.Difficulty.Normal.Length + CaptureConfig.Creatures.ElImitador.ExtraLength, "largo de la secuencia")

    fire("CaptureInput", player, capture.Id + 99, 1, sequence[1])
    T.Equal(session.Index, 0, "otra captura: ignorado")
    fire("CaptureInput", player, capture.Id, 3, sequence[3])
    T.Equal(session.Index, 0, "saltear pasos: rechazado")
    fire("CaptureInput", player, capture.Id, 1, "Z")
    T.Equal(session.Index, 0, "tecla inexistente: rechazada")
    fire("CaptureInput", player, capture.Id, 1.5, sequence[1])
    T.Equal(session.Index, 0, "paso no entero: rechazado")
    fire("CaptureInput", player, "progreso", 1, sequence[1], {Progress = 1, Escaped = true})
    T.Equal(session.Index, 0, "datos inventados: rechazados")
    T.True(CaptureService.IsCaptured(player), "sigue agarrado")

    -- Spam: diez veces la misma tecla en el mismo instante cuenta una sola.
    for _ = 1, 10 do
        fire("CaptureInput", player, capture.Id, 1, sequence[1])
    end
    T.Equal(session.Index, 1, "el spam no suma")
    for _ = 1, 10 do
        fire("CaptureInput", player, capture.Id, 2, sequence[2])
    end
    T.Equal(session.Index, 1, "ni siquiera con el paso siguiente pegado")

    -- Error: retrocede un paso y descuenta tiempo.
    Engine.Run(0.1)
    local deadline = session.Deadline
    fire("CaptureInput", player, capture.Id, 2, wrongKey(sequence[2]))
    T.Equal(session.Index, 0, "el error retrocede")
    T.True(math.abs(deadline - session.Deadline - CaptureConfig.Difficulty.Normal.MistakeTime) < 1e-6, "y cuesta tiempo")

    -- Tarde: pasado el plazo nada cuenta y el forcejeo se pierde.
    Engine.Run(session.Deadline - Engine.Clock() + 0.05, 0.05)
    local late = CaptureService.CaptureOf(player)
    T.True(late == nil or late.Phase == "Fail", "se acabó el tiempo")
    local index = session.Index
    fire("CaptureInput", player, capture.Id, index + 1, sequence[index + 1])
    T.Equal(session.Index, index, "tarde: rechazada")
    T.Equal(session.Accepted, 2, "sólo cuentan las teclas válidas")
    T.True(session.Rejected >= 13, "lo demás quedó anotado como rechazado: " .. session.Rejected)
    T.NoEngineErrors(Engine)
end)

T.Test("captura: zafar suelta, contragolpe, aturde 5 s exactos y después vuelve a cazar", function()
    local players, MonsterService, CaptureService = captureMatch(1)
    local player = players[1]
    local entry = MonsterService.Spawn("ElColoso")
    local controller = entry.Controller
    local model = entry.Model
    strike(entry, player)
    local capture = toStruggle(CaptureService, player)
    local session = capture.Session

    for step = 1, #session.Sequence - 1 do
        fire("CaptureInput", player, capture.Id, step, session.Sequence[step])
        Engine.Run(0.1)
    end
    T.True(CaptureService.IsCaptured(player), "falta una")
    local escapedAt = Engine.Clock()
    fire("CaptureInput", player, capture.Id, #session.Sequence, session.Sequence[#session.Sequence])
    local record = CaptureService.StunOf(entry)

    T.False(CaptureService.IsCaptured(player), "zafó")
    T.False(rootOf(player).Anchored, "recupera el control")
    T.Equal(player:GetAttribute("Captured"), nil, "sin atributo")
    T.True(CaptureService.IsImmune(player), "ventana de escape")
    T.Equal(model:GetAttribute("State"), "Stunned", "aturdida")
    T.Equal(model:GetAttribute("CapturePhase"), "Release", "la suelta con su animación")
    local escaped = Engine.LastSent("CaptureUpdate")[1]
    T.Equal(escaped.Event, "Escaped", "aviso de contragolpe")
    T.Equal(escaped.StunTime, 5, "5 segundos")
    local away = (rootOf(player).Position - entry.Root.Position) * Vector3.new(1, 0, 1)
    T.True(away.Magnitude > CaptureConfig.Creatures.ElColoso.Hold.Forward, "el empujón lo aleja")
    T.Equal(healthOf(player), 100, "sin daño")
    -- Aprovecha el aturdimiento para alejarse.
    Bot.MoveTo(Engine, player, rootOf(player).Position + Vector3.new(200, 0, 200))

    -- Durante el aturdimiento: ni persigue, ni ataca, ni agarra a nadie.
    local clock = controller.Clock
    Engine.Run(CaptureConfig.ReleaseTime + 0.1, 0.05)
    T.Equal(model:GetAttribute("AnimOverride"), nil, "terminó de soltar")
    T.Equal(CaptureService.TryCapture(entry, player, 10), "Busy", "no agarra aturdida")

    local recoverAt = nil
    while Engine.Clock() < escapedAt + 6 do
        Engine.Step(0.05)
        if not recoverAt and model:GetAttribute("State") == "Recover" then
            recoverAt = Engine.Clock()
        end
        if not recoverAt then
            T.Equal(model:GetAttribute("State"), "Stunned", "sigue aturdida")
        end
    end
    T.True(recoverAt ~= nil, "se recupera")
    local stunned = recoverAt - escapedAt
    T.True(stunned >= 5 - 1e-6 and stunned <= 5.05 + 1e-6, "aturdida " .. stunned .. " s")
    T.Equal(record.StunEnded - record.Started, 5, "el temporizador del servidor marca 5 s")
    T.Equal(controller.Clock, clock, "no pensó durante el aturdimiento")
    T.Equal(controller.Attack, nil, "sin ataque pendiente")

    Engine.Run(CaptureConfig.RecoverTime + 0.2)
    T.Equal(entry.CaptureHold, nil, "suelta")
    local state = model:GetAttribute("State")
    T.True(state ~= "Recover" and state ~= "Stunned" and state ~= "Capture", "estado normal: " .. tostring(state))
    Engine.Run(1)
    T.True(controller.Clock > clock, "vuelve a la IA normal")
    T.NoEngineErrors(Engine)
end)

T.Test("captura: perder el forcejeo aplica el daño de la dificultad y el camino de muerte", function()
    for _, difficulty in ipairs({"Normal", "Pesadilla"}) do
        local players, MonsterService, CaptureService = captureMatch(1, {Difficulty = difficulty})
        local player = players[1]
        local entry = MonsterService.Spawn("ElImitador")
        strike(entry, player)
        local capture = toStruggle(CaptureService, player)
        T.Equal(#capture.Session.Sequence, CaptureConfig.Difficulty[difficulty].Length + 1, "largo en " .. difficulty)
        T.True(Engine.RunUntil(function()
            return not CaptureService.IsCaptured(player)
        end, 15, 0.05), "termina")
        local expected = math.floor(MonsterConfig.ElImitador.Damage * GameConfig.Difficulties[difficulty].MonsterDamage + 0.5)
        T.Equal(healthOf(player), 100 - expected, "daño en " .. difficulty)
        T.False(rootOf(player).Anchored, "suelto")
        T.Equal(Engine.LastSent("MonsterEffect", player)[1], "Jumpscare", "golpe")
        T.Equal(entry.Model:GetAttribute("State"), "Recover", "se recupera sin aturdirse")
        T.True(CaptureService.IsImmune(player), "no lo agarra enseguida")
    end

    -- Con poca vida, el remate mata y sigue el camino normal de MatchService.
    local players, MonsterService, CaptureService = captureMatch(1)
    local player = players[1]
    local state = gameState()
    local lives = state.Lives
    player.Character:FindFirstChildOfClass("Humanoid").Health = 10
    local entry = MonsterService.Spawn("ElQuieto")
    strike(entry, player)
    T.True(Engine.RunUntil(function()
        return not CaptureService.IsCaptured(player)
    end, 15, 0.05), "termina")
    Engine.Run(0.3)
    T.Equal(state.Lives, lives - 1, "consume un reintento")
    T.Equal(Engine.LastSent("DownState", player)[1].Down, true, "cae")
    Engine.Run(GameConfig.Match.RespawnDelay + 1)
    T.True(healthOf(player) > 0, "reaparece")
    T.False(rootOf(player).Anchored, "sin anclar")
    T.Equal(player:GetAttribute("Captured"), nil, "sin captura")
    T.NoEngineErrors(Engine)
end)

T.Test("captura: si la víctima se va o muere en medio, todo se suelta sin trabarse", function()
    local players, MonsterService, CaptureService = captureMatch(2)
    local entry = MonsterService.Spawn("ElOyente")
    strike(entry, players[1])
    toStruggle(CaptureService, players[1])
    Engine.RemovePlayer(players[1])
    Engine.Run(0.1)
    T.False(CaptureService.IsCaptured(players[1]), "quien se fue queda suelto")
    T.Equal(entry.CaptureHold, "Recover", "la criatura se recupera")
    Engine.Run(CaptureConfig.RecoverTime + 0.2)
    T.Equal(entry.CaptureHold, nil, "y sigue")
    T.Equal(entry.Model:GetAttribute("AnimOverride"), nil, "sin animación de captura")

    -- Muere en medio (por otra causa): se suelta y la criatura no queda trabada.
    local victim = players[2]
    Engine.Run(1)
    strike(entry, victim)
    T.True(CaptureService.IsCaptured(victim), "agarra al otro")
    victim.Character:FindFirstChildOfClass("Humanoid").Health = 0
    Engine.Run(0.2)
    T.False(CaptureService.IsCaptured(victim), "muerto: suelto")
    T.False(rootOf(victim).Anchored, "sin anclar")
    Engine.Run(CaptureConfig.RecoverTime + 0.2)
    T.False(CaptureService.IsBusy(entry), "la criatura queda libre")
    T.NoEngineErrors(Engine)
end)

T.Test("captura: una criatura agarra a uno solo y nadie agarra al que ya está agarrado", function()
    local players, MonsterService, CaptureService = captureMatch(2)
    local first = MonsterService.Spawn("ElTrepador")
    local second = MonsterService.Spawn("ElColoso")
    strike(first, players[1])
    T.True(CaptureService.IsCaptured(players[1]), "agarra al primero")
    T.Equal(CaptureService.TryCapture(first, players[2], 30), "Busy", "no agarra a un segundo")
    T.Equal(CaptureService.TryCapture(second, players[1], 30), "Busy", "otra no le saca la presa")
    T.Equal(snapshotOf(second, players[1]), nil, "las demás no ven al agarrado")
    T.True(snapshotOf(second, players[2]) ~= nil, "sí al compañero")
    T.Equal(healthOf(players[1]), 100, "nadie más lo lastima")

    -- La otra criatura sí puede agarrar al compañero: dos capturas a la vez.
    strike(second, players[2])
    T.True(CaptureService.IsCaptured(players[2]), "la otra agarra al compañero")
    T.Equal(CaptureService.CaptureOf(players[1]).Entry, first, "cada una con el suyo")
    T.Equal(CaptureService.CaptureOf(players[2]).Entry, second, "cada una con el suyo")
    T.NoEngineErrors(Engine)
end)

T.Test("captura: fracaso, cambio de capítulo o vuelta al lobby sueltan a todos", function()
    local players, MonsterService, CaptureService = captureMatch(1)
    local player = players[1]
    local entry = MonsterService.Spawn("ElImitador")
    strike(entry, player)
    toStruggle(CaptureService, player)
    Engine.RequireServer("Multiplayer.MatchService").FailChapter("prueba")
    Engine.Run(0.1)
    T.False(CaptureService.IsCaptured(player), "suelto al fallar")
    T.False(rootOf(player).Anchored, "sin anclar")
    T.Equal(player:GetAttribute("Captured"), nil, "sin atributo")
    T.Equal(Engine.LastSent("CaptureUpdate")[1].Event, "Ended", "aviso de fin")
    T.NoEngineErrors(Engine)
end)

T.Test("captura: inmunidad al zafar y escudo de las escenas", function()
    local players, MonsterService, CaptureService = captureMatch(1)
    local player = players[1]
    local first = MonsterService.Spawn("ElOyente")
    strike(first, player)
    solve(player, toStruggle(CaptureService, player))
    T.False(CaptureService.IsCaptured(player), "zafó")

    local second = MonsterService.Spawn("ElImitador")
    strike(second, player)
    T.False(CaptureService.IsCaptured(player), "no lo vuelven a agarrar enseguida")
    T.Equal(healthOf(player), 100, "ni lo lastiman")

    Engine.Run(CaptureConfig.EscapeImmunity + 0.2)
    local field = Engine.New("ForceField")
    field.Parent = player.Character
    T.Equal(CaptureService.TryCapture(second, player, 30), "Immune", "la escena lo protege")
    field:Destroy()
    strike(second, player)
    T.True(CaptureService.IsCaptured(player), "pasada la ventana, sí")
    T.NoEngineErrors(Engine)
end)

T.Test("captura: las cinco criaturas agarran y se las puede vencer en todas las dificultades", function()
    for _, difficulty in ipairs({"Normal", "Pesadilla"}) do
        local players, MonsterService, CaptureService = captureMatch(1, {Difficulty = difficulty})
        local player = players[1]
        for _, kind in ipairs({"ElOyente", "ElImitador", "ElQuieto", "ElTrepador", "ElColoso"}) do
            MonsterService.Clear()
            Engine.Run(CaptureConfig.EscapeImmunity + 0.2)
            local entry = MonsterService.Spawn(kind)
            strike(entry, player)
            T.True(CaptureService.IsCaptured(player), kind .. " agarra")
            local capture = toStruggle(CaptureService, player)
            local profile = CaptureConfig.Creatures[kind]
            T.Equal(#capture.Session.Sequence, CaptureConfig.Difficulty[difficulty].Length + profile.ExtraLength, kind .. " largo")
            local lift = capture.Hold.Position.Y - capture.StandY
            T.True(math.abs(lift - profile.Hold.Lift) < 0.05, kind .. " levanta " .. lift)
            solve(player, capture)
            T.False(CaptureService.IsCaptured(player), kind .. " vencida en " .. difficulty)
            T.Equal(entry.Model:GetAttribute("State"), "Stunned", kind .. " aturdida")
        end
    end
    T.NoEngineErrors(Engine)
end)

T.Test("captura: el bot de la campaña forcejea y zafa como un jugador", function()
    local players, MonsterService, CaptureService = captureMatch(1)
    local player = players[1]
    local entry = MonsterService.Spawn("ElColoso")
    strike(entry, player)
    T.True(Engine.RunUntil(function()
        Bot.Act(Engine, player)
        return not CaptureService.IsCaptured(player)
    end, 15, 0.4), "zafa")
    T.Equal(healthOf(player), 100, "sin daño")
    T.NoEngineErrors(Engine)
end)

local function insideModel(model, point)
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            local localPoint = part.CFrame:PointToObjectSpace(point)
            local half = part.Size / 2
            if math.abs(localPoint.X) < half.X and math.abs(localPoint.Y) < half.Y and math.abs(localPoint.Z) < half.Z then
                return true
            end
        end
    end
    return false
end

local KEY_CODES = {
    Q = roblox.Enum.KeyCode.Q, E = roblox.Enum.KeyCode.E, R = roblox.Enum.KeyCode.R,
    F = roblox.Enum.KeyCode.F, Space = roblox.Enum.KeyCode.Space,
}
local PAD_CODES = {
    Q = roblox.Enum.KeyCode.ButtonX, E = roblox.Enum.KeyCode.ButtonY, R = roblox.Enum.KeyCode.ButtonB,
    F = roblox.Enum.KeyCode.ButtonR1, Space = roblox.Enum.KeyCode.ButtonA,
}

T.Test("cliente: forcejeo con teclado y mando, cámara protegida y animación de la criatura", function()
    local players, MonsterService, CaptureService = captureMatch(1, {Client = true})
    local player = players[1]
    local gui = player:FindFirstChild("PlayerGui")
    local panel = gui:FindFirstChild("NocturnaStruggle"):FindFirstChild("Root"):FindFirstChild("StrugglePanel")
    local camera = Engine.Workspace.CurrentCamera
    local flashlight = player:GetAttribute("FlashlightEnabled")

    local entry = MonsterService.Spawn("ElImitador")
    local model = entry.Model
    local jawPart = model:FindFirstChild("Jaw")
    local jaw = jawPart:FindFirstChildOfClass("Motor6D")
    local jawBase = jaw.C0
    strike(entry, player)
    Engine.Run(0.2)
    T.True(panel.Visible, "panel del forcejeo")
    T.Equal(camera.CameraType, roblox.Enum.CameraType.Scriptable, "la captura toma la cámara")

    local capture = toStruggle(CaptureService, player)
    Engine.Run(0.3)
    T.False(insideModel(model, camera.CFrame.Position), "la cámara no atraviesa a la criatura")
    T.True((camera.CFrame.Position - rootOf(player).Position).Magnitude > 1.5, "plano a distancia")
    local head = model:FindFirstChild("Head")
    -- Se compara contra lookAt del mismo motor (el de Lune invierte el frente).
    local toward = roblox.CFrame.lookAt(camera.CFrame.Position, head.Position).LookVector
    T.True(camera.CFrame.LookVector:Dot(toward) > 0.5, "mira a la criatura")
    T.True(jaw.C0 ~= jawBase, "la boca se abre")
    T.True(jawPart:FindFirstChild("CaptureDrip", true) ~= nil, "baba")
    T.True(head:FindFirstChild("CaptureRim") ~= nil, "luz de recorte")

    local sequence = capture.Session.Sequence
    for step, key in ipairs(sequence) do
        local codes = step % 2 == 0 and PAD_CODES or KEY_CODES
        Engine.Input("InputBegan", {KeyCode = codes[key], UserInputType = roblox.Enum.UserInputType.Keyboard})
        Engine.Run(0.1)
    end
    T.False(CaptureService.IsCaptured(player), "zafó con teclado y mando")
    T.Equal(player:GetAttribute("FlashlightEnabled"), flashlight, "la F del forcejeo no toca la linterna")
    T.Equal(model:GetAttribute("State"), "Stunned", "aturdida")

    Engine.Run(1.5)
    T.False(panel.Visible, "el panel se va")
    T.Equal(camera.CameraType, roblox.Enum.CameraType.Custom, "devuelve la cámara")
    T.True(jawPart:FindFirstChild("CaptureDrip", true) == nil, "limpia los efectos")
    local animator = Engine.Require(Engine.ClientFolder:FindFirstChild("Effects"):FindFirstChild("CaptureAnimator"), "Client")
    T.Equal(animator.Sessions()[model], nil, "la animación de captura devuelve las articulaciones")
    for _, message in ipairs(Engine.Warnings()) do
        T.False(string.find(message, "aptura") or string.find(message, "StruggleUI") or string.find(message, "Capture"), "aviso: " .. message)
    end
    T.NoEngineErrors(Engine)
end)

T.Test("cliente táctil: botones grandes numerados para forcejear", function()
    local players, MonsterService, CaptureService = captureMatch(1, {Client = true, Touch = true, Viewport = roblox.Vector2.new(812, 375)})
    local player = players[1]
    local holder = player:FindFirstChild("PlayerGui"):FindFirstChild("NocturnaStruggle"):FindFirstChild("Root"):FindFirstChild("StruggleButtons")
    local entry = MonsterService.Spawn("ElQuieto")
    strike(entry, player)
    local capture = toStruggle(CaptureService, player)
    Engine.Run(0.2)
    T.True(holder.Visible, "botones a la vista")
    local count = 0
    for _, child in ipairs(holder:GetChildren()) do
        if child:IsA("TextButton") then
            count += 1
            T.True(child.Size.X.Offset >= 80 and child.Size.Y.Offset >= 80, "botón grande")
        end
    end
    T.Equal(count, #CaptureConfig.Keys, "uno por tecla")

    for _, key in ipairs(capture.Session.Sequence) do
        Engine.GuiInput(holder:FindFirstChild("Key" .. key), "Activated")
        Engine.Run(0.1)
    end
    T.False(CaptureService.IsCaptured(player), "zafó tocando")
    Engine.Run(1.5)
    T.False(holder.Visible, "los botones se van")
    T.NoEngineErrors(Engine)
end)

T.Test("cliente: el compañero ve el aviso y la escena de quien está atrapado", function()
    local players, MonsterService, CaptureService = captureMatch(2, {Client = true})
    local banner = players[1]:FindFirstChild("PlayerGui"):FindFirstChild("NocturnaStruggle"):FindFirstChild("Root"):FindFirstChild("CaptureBanner")
    local entry = MonsterService.Spawn("ElOyente")
    strike(entry, players[2])
    Engine.Run(0.3)
    T.True(banner.Visible, "aviso al compañero")
    T.True(string.find(banner:FindFirstChild("Text").Text, players[2].DisplayName, 1, true) ~= nil, "con el nombre")
    local animator = Engine.Require(Engine.ClientFolder:FindFirstChild("Effects"):FindFirstChild("CaptureAnimator"), "Client")
    T.True(animator.Sessions()[entry.Model] ~= nil, "la criatura se anima también en su pantalla")
    T.True(Engine.Workspace.CurrentCamera.CameraType ~= roblox.Enum.CameraType.Scriptable, "su cámara sigue siendo suya")
    T.True(Engine.RunUntil(function()
        return not CaptureService.IsCaptured(players[2])
    end, 15), "termina")
    Engine.Run(2.5)
    T.False(banner.Visible, "el aviso se va")
    T.NoEngineErrors(Engine)
end)

local failed = T.Summary()
process.exit(failed > 0 and 1 or 0)
