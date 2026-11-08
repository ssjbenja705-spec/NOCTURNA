-- Persecución final del capítulo 5. Cuando el grupo abre la puerta del cuarto de
-- Alma, la casa se deshace: todos aparecen en la galería del Núcleo y El Organismo
-- irrumpe detrás. Hay que correr hasta la compuerta del fondo saltando, agachándose,
-- esquivando derrumbes y embistiendo compuertas. Del otro lado está Alma.
--
-- El servidor decide todo: dónde está la criatura (un elástico justo detrás del
-- último jugador), quién pasó bien cada obstáculo y a quién alcanza. El cliente
-- sólo dibuja, hace sonar y pide acciones ("Jump" o "Duck") por ChaseAction.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local ChapterConfig = require(Shared.Config.ChapterConfig)
local FinalChaseConfig = require(Shared.Config.FinalChaseConfig)
local ThemeConfig = require(Shared.Config.ThemeConfig)
local ChasePlan = require(Shared.Logic.ChasePlan)
local Rng = require(Shared.Logic.Rng)
local Remotes = require(Shared.Modules.RemoteHelper)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local DamageService = require(script.Parent.Parent.Data.DamageService)
local StaminaService = require(script.Parent.Parent.Data.StaminaService)
local MonsterService = require(script.Parent.Parent.Monsters.MonsterService)
local AntiCheat = require(script.Parent.Parent.Security.AntiCheat)
local StoryService = require(script.Parent.Parent.Story.StoryService)
local HidingService = require(script.Parent.Parent.World.HidingService)
local RoomGenerator = require(script.Parent.Parent.World.RoomGenerator)
local WorldService = require(script.Parent.Parent.World.WorldService)
local ChaseArena = require(script.Parent.ChaseArena)
local ChaseHit = require(script.Parent.ChaseHit)

local CONFIG = FinalChaseConfig
local ARENA = CONFIG.Arena
local CREATURE = CONFIG.Creature
local OBSTACLES = CONFIG.Obstacles
local TIMING = CONFIG.Timing
local SPAWN_AHEAD = 24
local ACTIONS = {Jump = true, Duck = true}

local FinalChaseService = {}
FinalChaseService.Config = CONFIG
local chase = nil
local started = false
local tickClock = 0
local random = Random.new()

local function aliveRoot(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then
        return nil
    end
    return root, character
end

local function teleport(player, cframe)
    local character = player.Character
    if not character then
        return
    end
    AntiCheat.Grace(player, 3)
    character:PivotTo(cframe)
end

local function chaseObjectiveId(chapter, spec)
    for _, objective in ipairs(chapter.Objectives) do
        if objective.Target == spec.Id then
            return objective.Id
        end
    end
    return nil
end

local function obstaclePayload(list)
    local result = {}
    for _, entry in ipairs(list) do
        table.insert(result, {Id = entry.Id, Kind = entry.Kind, S = entry.S, Side = entry.Side})
    end
    return result
end

local function current(c)
    return chase == c and c ~= nil
end

-- Atmósfera de la galería: niebla rojiza, más cerrada que la del capítulo.
local function applyChaseAtmosphere()
    Lighting.FogColor = ARENA.FogColor
    Lighting.FogStart = ARENA.FogStart
    Lighting.FogEnd = ARENA.FogEnd
    Lighting.Ambient = ARENA.Ambient
    Lighting.OutdoorAmbient = ARENA.Ambient
end

local function restoreAtmosphere(c)
    local chapter = ChapterConfig[c.Chapter]
    local theme = chapter and ThemeConfig[chapter.Theme]
    if theme then
        WorldService.ApplyAtmosphere(theme)
    end
end

-- Lugar de llegada: justo pasando la puerta del cuarto de Alma, mirando adentro.
local function arrivalCFrame(index)
    local plan = GameState.Plan
    local layout = plan and plan.Layout
    if not layout then
        return CFrame.new(0, 3.5, 0)
    end
    local exitIndex = layout.Exit
    local exitCell = layout.Cells[exitIndex]
    local size = 40
    local nav = GameState.Nav
    if nav then
        size = nav.CellSize
    end
    local center = Vector3.new((exitCell.X - 1) * size, 3.5, (exitCell.Z - 1) * size)

    local entrance = nil
    for _, gate in ipairs(plan.Gates or {}) do
        if gate.A == exitIndex then
            entrance = gate.B
        elseif gate.B == exitIndex then
            entrance = gate.A
        end
    end
    local position = center
    if entrance and layout.Cells[entrance] then
        local midpoint = RoomGenerator.EdgeInfo(layout, entrance, exitIndex)
        local inward = Vector3.new(center.X - midpoint.X, 0, center.Z - midpoint.Z)
        if inward.Magnitude > 0.01 then
            inward = inward.Unit
            local side = Vector3.new(-inward.Z, 0, inward.X)
            position = Vector3.new(midpoint.X, 3.5, midpoint.Z) + inward * 7 + side * (((index or 1) - 2.5) * 2.2)
        end
    end
    return CFrame.lookAt(position, Vector3.new(center.X, 3.5, center.Z))
end

FinalChaseService.ArrivalCFrame = arrivalCFrame

local function startSlot(c, index)
    local lateral = (((index - 1) % 4) - 1.5) * 4
    return c.Arena:Frame(ARENA.StartS, lateral, 3.5)
end

-- Estado de un jugador dentro de la galería. Lo que quedó atrás cuenta como pasado.
local function register(c, player, character, s)
    local entry = {
        Character = character,
        LastS = s,
        Passed = {},
        Tokens = {},
        Pending = {},
        CatchReadyAt = 0,
        Safe = false,
    }
    for _, obstacle in ipairs(c.Obstacles) do
        if obstacle.S <= s then
            entry.Passed[obstacle.Id] = true
        end
    end
    c.Players[player] = entry
    return entry
end

local function startPayload(c)
    return {
        Event = "Start",
        Phase = c.Phase,
        Obstacles = obstaclePayload(c.Obstacles),
        Creature = {S = c.Creature.S, Speed = c.Creature.Speed},
        Doors = c.DoorsOpen,
        Time = workspace:GetServerTimeNow(),
    }
end

local function newChase(chapterIndex, spec)
    local seed = random:NextInteger(1, 2 ^ 30)
    local obstacles = ChasePlan.Generate(Rng.new(seed), CONFIG)
    local byId = {}
    for _, entry in ipairs(obstacles) do
        byId[entry.Id] = entry
    end
    return {
        Chapter = chapterIndex,
        Spec = spec,
        ObjectiveId = chaseObjectiveId(ChapterConfig[chapterIndex], spec),
        Seed = seed,
        Obstacles = obstacles,
        ById = byId,
        Phase = "Waiting",
        Creature = ChasePlan.NewCreature(CONFIG, ARENA.StartS),
        Players = {},
        DoorsOpen = {},
        Debris = {},
        Arena = nil,
        Token = 0,
    }
end

local function cleanup(c)
    if c.Arena then
        c.Arena:Destroy()
        c.Arena = nil
    end
    if chase == c then
        chase = nil
        Remotes.FireAll("ChaseState", {Event = "Stop"})
    end
end

-- Cambio de capítulo, vuelta al lobby o mapa nuevo: la persecución se borra entera.
function FinalChaseService.Clear()
    local c = chase
    if not c then
        return
    end
    c.Token += 1
    if c.Phase == "Run" or c.Phase == "Intro" or c.Phase == "Retry" then
        restoreAtmosphere(c)
    end
    cleanup(c)
end

function FinalChaseService.IsActive()
    return chase ~= nil and chase.Phase ~= "Done"
end

function FinalChaseService.Phase()
    return chase and chase.Phase or nil
end

function FinalChaseService.State()
    return chase
end

-- Mueve al grupo a la largada y arranca la criatura detrás.
local function placeGroup(c)
    for index, player in ipairs(Players:GetPlayers()) do
        if player:GetAttribute("Hidden") == true then
            HidingService.ForceOut(player)
        end
        local root, character = aliveRoot(player)
        if root then
            teleport(player, startSlot(c, index))
            register(c, player, character, ARENA.StartS)
        end
    end
    GameState.Checkpoint = c.Arena:Frame(ARENA.StartS, 0, 3.5)
end

local function runSequence(c, withTransition)
    c.Token += 1
    local token = c.Token
    local function alive()
        return current(c) and c.Token == token
    end

    if withTransition then
        Remotes.FireAll("ChaseState", {Event = "Intro", Lines = c.Spec.Transition, Fade = TIMING.FadeOut})
        task.wait(TIMING.FadeOut)
        if not alive() then
            return
        end
    end

    MonsterService.Clear()
    applyChaseAtmosphere()
    c.Phase = "Intro"
    c.Creature = ChasePlan.NewCreature(CONFIG, ARENA.StartS)
    c.Arena:Stream(ARENA.BackS, ARENA.StartS + ARENA.BuildAhead)
    placeGroup(c)
    Remotes.FireAll("ChaseState", startPayload(c))

    task.wait(withTransition and TIMING.Arrive or 1)
    if not alive() then
        return
    end
    -- La pared del fondo revienta y aparece El Organismo.
    Remotes.FireAll("ChaseState", {Event = "Reveal", S = c.Creature.S})
    task.wait(TIMING.Reveal)
    if not alive() then
        return
    end
    Remotes.FireAll("ChaseState", {Event = "Countdown", Duration = TIMING.Countdown})
    task.wait(TIMING.Countdown)
    if not alive() then
        return
    end

    c.Phase = "Run"
    Remotes.FireAll("ChaseState", {Event = "Run"})
    if withTransition then
        StoryService.PlayDialogue(c.Spec.Start)
    end
end

function FinalChaseService.Begin(chapterIndex)
    local chapter = ChapterConfig[chapterIndex]
    local spec = chapter and chapter.FinalChase
    if not spec or chase ~= nil or not GameState.IsPlaying() then
        return false
    end
    local c = newChase(chapterIndex, spec)
    chase = c
    c.Arena = ChaseArena.new(CONFIG, c.Obstacles, c.Seed)

    task.spawn(function()
        -- Primero termina la cinemática de la puerta que se abrió.
        task.wait(TIMING.GateCinematic)
        if current(c) and GameState.IsPlaying() then
            runSequence(c, true)
        elseif current(c) then
            cleanup(c)
        end
    end)
    return true
end

-- Si el grupo entero cae durante la persecución, se reintenta sólo la persecución:
-- MatchService repone los reintentos y hace reaparecer a todos en la largada.
function FinalChaseService.CanRetry()
    return chase ~= nil and (chase.Phase == "Intro" or chase.Phase == "Run" or chase.Phase == "Retry")
end

function FinalChaseService.PrepareRetry()
    local c = chase
    if not FinalChaseService.CanRetry() then
        return false
    end
    c.Token += 1
    c.Phase = "Retry"
    if c.Arena then
        c.Arena:Destroy()
    end
    c.Arena = ChaseArena.new(CONFIG, c.Obstacles, c.Seed)
    c.Arena:Stream(ARENA.BackS, ARENA.StartS + ARENA.BuildAhead)
    c.Players = {}
    c.DoorsOpen = {}
    c.Debris = {}
    c.Creature = ChasePlan.NewCreature(CONFIG, ARENA.StartS)
    GameState.Checkpoint = c.Arena:Frame(ARENA.StartS, 0, 3.5)
    return true
end

function FinalChaseService.Restart()
    local c = chase
    if not c or c.Phase ~= "Retry" then
        return false
    end
    task.spawn(function()
        -- Da tiempo a que todos reaparezcan.
        task.wait(1)
        if current(c) and c.Phase == "Retry" then
            runSequence(c, false)
        end
    end)
    return true
end

-- Obstáculos ----------------------------------------------------------------------

local function difficultyDamage(amount)
    return math.floor(amount * GameState.DifficultySettings().MonsterDamage + 0.5)
end

local function stumble(c, player, obstacle, damage)
    StaminaService.Stagger(player, OBSTACLES.StumbleTime, OBSTACLES.StumbleSlow)
    DamageService.ApplyDamage(player, math.clamp(difficultyDamage(damage or OBSTACLES.StumbleDamage), 1, 100))
    Remotes.FireAll("ChaseState", {Event = "Act", UserId = player.UserId, Kind = "Stumble", Obstacle = obstacle and obstacle.Id})
    EventBus.Emit("ChaseStumble", player, obstacle)
end

local function pass(c, player, obstacle)
    AntiCheat.Grace(player, 1.2)
    EventBus.Emit("ChaseObstaclePassed", player, obstacle)
end

local function burstDoor(c, player, door)
    if c.DoorsOpen[door.Id] then
        return false
    end
    c.DoorsOpen[door.Id] = true
    if c.Arena then
        c.Arena:BurstDoor(door.Id)
    end
    Remotes.FireAll("ChaseState", {Event = "Door", Id = door.Id, UserId = player and player.UserId})
    EventBus.Emit("ChaseDoorBurst", player, door)
    return true
end

-- Cruces de cada jugador: quien pasa un salto o una viga sin la acción tropieza.
local function processCrossings(c, player, entry, s, now)
    for _, obstacle in ipairs(c.Obstacles) do
        local kind = obstacle.Kind
        if (kind == "Vault" or kind == "Slide") and not entry.Passed[obstacle.Id]
            and entry.LastS < obstacle.S and s >= obstacle.S then
            entry.Passed[obstacle.Id] = true
            local expires = entry.Tokens[obstacle.Id]
            if expires and now <= expires then
                pass(c, player, obstacle)
            else
                entry.Pending[obstacle.Id] = now + OBSTACLES.LateGrace
            end
        end
    end
    for id, deadline in pairs(entry.Pending) do
        if now > deadline then
            entry.Pending[id] = nil
            stumble(c, player, c.ById[id])
        end
    end
end

-- Una compuerta entera frena físicamente. Si algo la atraviesa igual (lag o
-- trampa), el servidor devuelve al jugador delante de ella.
local function enforceDoors(c, player, root, s, lateral)
    for _, obstacle in ipairs(c.Obstacles) do
        if obstacle.Kind == "Door" and not c.DoorsOpen[obstacle.Id] then
            local entry = c.Players[player]
            if entry and entry.LastS <= obstacle.S and s > obstacle.S + 0.5 then
                AntiCheat.Grace(player, 1)
                root.CFrame = c.Arena:Frame(obstacle.S - 2.5, math.clamp(lateral, -ARENA.Width / 2 + 2, ARENA.Width / 2 - 2), root.Position.Y)
                return obstacle.S - 2.5
            end
        end
    end
    return s
end

function FinalChaseService.Action(player, action)
    local c = chase
    if not c or c.Phase ~= "Run" or not ACTIONS[action] then
        return false
    end
    local root = aliveRoot(player)
    local entry = c.Players[player]
    if not root or not entry or entry.Safe or not c.Arena then
        return false
    end
    local s = c.Arena:Coordinates(root.Position)

    if action == "Jump" then
        for _, obstacle in ipairs(c.Obstacles) do
            if obstacle.Kind == "Door" and not c.DoorsOpen[obstacle.Id]
                and s >= obstacle.S - OBSTACLES.DoorReach and s <= obstacle.S + 1 then
                return burstDoor(c, player, obstacle)
            end
        end
    end

    -- Un pedido que llega justo después de cruzar (latencia) todavía vale.
    for id in pairs(entry.Pending) do
        local obstacle = c.ById[id]
        if CONFIG.Actions[obstacle.Kind] == action and s <= obstacle.S + OBSTACLES.ActionLate + 3 then
            entry.Pending[id] = nil
            pass(c, player, obstacle)
            Remotes.FireAll("ChaseState", {Event = "Act", UserId = player.UserId, Kind = obstacle.Kind, Obstacle = id})
            return true
        end
    end

    local resolved = {}
    for id in pairs(entry.Passed) do
        resolved[id] = true
    end
    local target = ChasePlan.ActionTarget(c.Obstacles, s, action, CONFIG, resolved)
    if not target then
        return false
    end
    entry.Tokens[target.Id] = os.clock() + OBSTACLES.TokenTime
    Remotes.FireAll("ChaseState", {Event = "Act", UserId = player.UserId, Kind = target.Kind, Obstacle = target.Id})
    return true
end

-- Derrumbes: se disparan con el primero que llega y caen sobre una franja.
local function updateDebris(c, frontS, runners, now)
    for _, obstacle in ipairs(c.Obstacles) do
        if obstacle.Kind == "Debris" then
            local state = c.Debris[obstacle.Id]
            if not state and frontS >= obstacle.S - OBSTACLES.DebrisLead then
                state = {ImpactAt = now + OBSTACLES.DebrisWarn}
                c.Debris[obstacle.Id] = state
                Remotes.FireAll("ChaseState", {Event = "Debris", Id = obstacle.Id, Side = obstacle.Side, Warn = OBSTACLES.DebrisWarn})
            elseif state and not state.Landed and now >= state.ImpactAt then
                state.Landed = true
                if c.Arena then
                    c.Arena:LandDebris(obstacle.Id)
                end
                Remotes.FireAll("ChaseState", {Event = "DebrisLanded", Id = obstacle.Id})
                for _, runner in ipairs(runners) do
                    if math.abs(runner.S - obstacle.S) <= OBSTACLES.DebrisHalfDepth
                        and ChasePlan.InDebrisZone(obstacle.Side or 0, runner.Lateral, ARENA.Width) then
                        stumble(c, runner.Player, obstacle, OBSTACLES.DebrisDamage)
                    end
                end
            end
        end
    end
end

local function catchPlayer(c, player, root)
    local entry = c.Players[player]
    entry.CatchReadyAt = os.clock() + CREATURE.CatchCooldown
    c.Creature.Recoil = CREATURE.RecoilTime
    Remotes.FireAll("ChaseState", {Event = "Catch", UserId = player.UserId, S = c.Creature.S})
    ChaseHit.Apply(player, difficultyDamage(CREATURE.Damage), root.Position, CREATURE.Kind)
end

-- Dónde reaparece quien cae: con el grupo, siempre por delante de la criatura.
local function updateCheckpoint(c, frontRunnerS, anySafe)
    local s
    if frontRunnerS then
        s = math.max(c.Creature.S + SPAWN_AHEAD, math.min(frontRunnerS - 6, ARENA.FinishS - 6))
        -- Cerca del final no queda lugar delante de la criatura: del otro lado.
        if s > ARENA.FinishS - 3 then
            s = ARENA.FinishS + 8
        end
    elseif anySafe then
        s = ARENA.FinishS + 8
    else
        s = math.max(ARENA.StartS, c.Creature.S + SPAWN_AHEAD)
    end
    for _, obstacle in ipairs(c.Obstacles) do
        if math.abs(obstacle.S - s) < 4 then
            s = obstacle.S + 5
        end
    end
    GameState.Checkpoint = c.Arena:Frame(s, 0, 3.5)
end

local function finish(c)
    c.Phase = "Finish"
    c.Token += 1
    local token = c.Token
    if c.Arena then
        c.Arena:CloseShutter()
    end
    Remotes.FireAll("ChaseState", {Event = "Finish", Fade = TIMING.FinishFade})

    task.delay(TIMING.FinishFade, function()
        if not current(c) or c.Token ~= token then
            return
        end
        for index, player in ipairs(Players:GetPlayers()) do
            if aliveRoot(player) then
                teleport(player, arrivalCFrame(index))
            end
        end
        GameState.Checkpoint = arrivalCFrame(1)
        restoreAtmosphere(c)
        c.Phase = "Done"
        Remotes.FireAll("ChaseState", {Event = "Arrive", Text = c.Spec.Arrive})
        EventBus.Emit("FeatureActivated", nil, {Id = c.Spec.Id})
        task.delay(TIMING.CleanupAfter, function()
            if current(c) then
                cleanup(c)
            end
        end)
    end)
end

local function step(c, deltaTime)
    local now = os.clock()
    local arena = c.Arena
    local runners = {}
    local rearS, frontS = math.huge, -math.huge
    local anySafe = false

    for _, player in ipairs(Players:GetPlayers()) do
        local root, character = aliveRoot(player)
        if root and arena:Contains(root.Position) then
            local s, lateral = arena:Coordinates(root.Position)
            local entry = c.Players[player]
            if not entry or entry.Character ~= character then
                entry = register(c, player, character, s)
            end
            s = enforceDoors(c, player, root, s, lateral)
            processCrossings(c, player, entry, s, now)
            entry.LastS = s

            if s >= ARENA.FinishS and not entry.Safe then
                entry.Safe = true
                Remotes.FireAll("ChaseState", {Event = "Safe", UserId = player.UserId})
            end
            if entry.Safe then
                anySafe = true
            else
                table.insert(runners, {Player = player, Root = root, S = s, Lateral = lateral})
                rearS = math.min(rearS, s)
                frontS = math.max(frontS, s)
            end
        end
    end

    if #runners == 0 then
        if anySafe then
            finish(c)
        end
        return
    end

    ChasePlan.StepCreature(c.Creature, rearS, deltaTime, CONFIG, GameState.DifficultySettings().MonsterSpeed)
    for _, runner in ipairs(runners) do
        local entry = c.Players[runner.Player]
        if now >= entry.CatchReadyAt and ChasePlan.Caught(c.Creature, runner.S, CONFIG) then
            catchPlayer(c, runner.Player, runner.Root)
        end
    end

    updateDebris(c, frontS, runners, now)
    arena:Stream(c.Creature.S - ARENA.KeepBehind, frontS + ARENA.BuildAhead)
    updateCheckpoint(c, frontS, anySafe)

    tickClock += deltaTime
    if tickClock >= 1 / TIMING.TickRate then
        tickClock = 0
        Remotes.FireAll("ChaseState", {
            Event = "Tick",
            S = c.Creature.S,
            Speed = c.Creature.Speed,
            Recoil = c.Creature.Recoil > 0,
            Rear = rearS,
            Time = workspace:GetServerTimeNow(),
        })
    end
end

local function onHeartbeat(deltaTime)
    local c = chase
    if not c then
        return
    end
    if GameState.Phase == "Lobby" or GameState.Chapter ~= c.Chapter then
        FinalChaseService.Clear()
        return
    end
    if c.Phase ~= "Run" or not GameState.IsPlaying() or not c.Arena then
        return
    end
    -- Si un administrador saltea el objetivo, la persecución termina ya.
    local tracker = GameState.Tracker
    if tracker and c.ObjectiveId and tracker:IsDone(c.ObjectiveId) then
        c.Phase = "Done"
        restoreAtmosphere(c)
        for index, player in ipairs(Players:GetPlayers()) do
            if aliveRoot(player) then
                teleport(player, arrivalCFrame(index))
            end
        end
        cleanup(c)
        return
    end
    step(c, math.min(deltaTime, 0.25))
end

function FinalChaseService.Start()
    if started then
        return
    end
    started = true

    EventBus.On("ObjectiveCompleted", function(objective, chapterIndex)
        local chapter = ChapterConfig[chapterIndex]
        local spec = chapter and chapter.FinalChase
        if spec and objective and objective.Id == spec.StartAfter and chapterIndex == GameState.Chapter then
            FinalChaseService.Begin(chapterIndex)
        end
    end)

    EventBus.On("WorldLoaded", FinalChaseService.Clear)
    EventBus.On("WorldUnloaded", FinalChaseService.Clear)

    Remotes.OnServer("ChaseAction", 6, function(player, action)
        if typeof(action) == "string" then
            FinalChaseService.Action(player, action)
        end
    end)

    -- Quien entra o vuelve en medio de la persecución recibe el estado.
    Players.PlayerAdded:Connect(function(player)
        task.delay(2, function()
            local c = chase
            if c and player.Parent == Players and (c.Phase == "Intro" or c.Phase == "Run") then
                Remotes.FireClient("ChaseState", player, startPayload(c))
            end
        end)
    end)

    RunService.Heartbeat:Connect(onHeartbeat)
end

return FinalChaseService
