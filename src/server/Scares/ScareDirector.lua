-- Sustos de cada mapa (3 o 4, uno o dos de golpe). Al cargar el capítulo se eligen
-- tipos y lugares (ScarePlan); durante la partida cada uno pasa una sola vez y
-- todos pasan dentro de un capítulo normal:
--   * solo: cuando alguien pasa cerca (y mirando, si es visual) de su lugar;
--   * a tiempo: el reloj de juego (sin contar escenas ni la persecución final)
--     marca cuándo le toca a cada uno. El primero a los ~28 s; los demás, entre 50
--     y 70 s después del anterior. Si a esa hora nadie pasó por el lugar, el susto
--     se muda adelante de un jugador (o cambia por uno que no necesita lugar).
--
-- Nunca durante escenas, la persecución final, un golpe o una captura, ni con una
-- criatura cerca o persiguiendo: los sustos son sólo imagen y sonido en el
-- cliente, no hacen ruido para la IA ni tocan a las criaturas.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local ScareConfig = require(Shared.Config.ScareConfig)
local ScarePlan = require(Shared.Logic.ScarePlan)
local Rng = require(Shared.Logic.Rng)
local Remotes = require(Shared.Modules.RemoteHelper)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local MonsterService = require(script.Parent.Parent.Monsters.MonsterService)
local DoorService = require(script.Parent.Parent.World.DoorService)
local WorldService = require(script.Parent.Parent.World.WorldService)
local FinalChaseService = require(script.Parent.Parent.Final.FinalChaseService)

local TIMING = ScareConfig.Timing
local TRIGGER = ScareConfig.Trigger
-- Atributos que puede poner el sistema de captura mientras sostiene a alguien.
local CAPTURE_ATTRIBUTES = {"Captured", "NocturnaCaptured", "Grabbed"}
-- Motivos de bloqueo durante los que el reloj de juego sigue corriendo.
local CLOCK_RUNS = {respiro = true, espera = true}

local ScareDirector = {}
local current = nil
local lastKind = nil
local blockedUntil = 0
local elapsed = 0
local started = false
local random = Random.new()

local function block(seconds)
    blockedUntil = math.max(blockedUntil, os.clock() + seconds)
end

function ScareDirector.Prepare(plan, seed)
    local layout = plan and plan.Layout
    if not layout then
        current = nil
        return nil
    end
    local entries = ScarePlan.Generate(layout, Rng.new(seed or random:NextInteger(1, 2 ^ 30)), ScareConfig, lastKind)
    for _, entry in ipairs(entries) do
        entry.Planned = entry.Kind
    end
    current = {
        Entries = entries,
        Fired = {},
        Chapter = GameState.Chapter,
        StartedAt = os.clock(),
        LastFiredAt = nil,
        History = {},
        -- Reloj de juego del capítulo (segundos jugados, sin escenas).
        PlayTime = 0,
        -- Desde cuándo puede pasar uno solo y cuándo se fuerza el próximo.
        GapUntil = TIMING.FirstDelay,
        DueAt = TIMING.FirstDue,
    }
    return entries
end

function ScareDirector.Clear()
    current = nil
end

function ScareDirector.Plan()
    return current and current.Entries or nil
end

function ScareDirector.History()
    return current and current.History or {}
end

-- Segundos jugados del capítulo y cuándo se fuerza el próximo susto.
function ScareDirector.PlayTime()
    return current and current.PlayTime or 0
end

function ScareDirector.DueAt()
    return current and current.DueAt or math.huge
end

local function anchorOf(entry)
    local nav = GameState.Nav
    return nav and nav:Center(entry.Cell, 0) or nil
end

local function captured(player)
    for _, name in ipairs(CAPTURE_ATTRIBUTES) do
        if player:GetAttribute(name) == true then
            return true
        end
    end
    return false
end

local function monsterNear(position)
    for _, entry in ipairs(MonsterService.Active()) do
        local controller = entry.Controller
        local where = controller and controller.Position
        if typeof(where) == "Vector3" and (where - position).Magnitude <= TRIGGER.MonsterClearance then
            return true
        end
    end
    return false
end

local function isAlone(player, root)
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            local character = other.Character
            local otherRoot = character and character:FindFirstChild("HumanoidRootPart")
            if otherRoot and (otherRoot.Position - root.Position).Magnitude < TRIGGER.AloneDistance then
                return false
            end
        end
    end
    return true
end

-- ¿Puede este jugador recibir un susto ahora?
local function eligible(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then
        return nil
    end
    if player:GetAttribute("Hidden") == true or captured(player) then
        return nil
    end
    if (player:GetAttribute("NocturnaThreat") or 0) > TRIGGER.MaxThreat then
        return nil
    end
    if monsterNear(root.Position) then
        return nil
    end
    return root
end

local function flatLook(root)
    local look = root.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    return flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
end

local function facing(root, point)
    local offset = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)
    if offset.Magnitude < 0.01 then
        return false
    end
    return flatLook(root):Dot(offset.Unit) >= TRIGGER.FacingDot
end

-- El jugador que dispara este susto en su lugar, o nil si nadie puede ahora.
local function pickPlayer(entry, anchor)
    local kind = ScareConfig.Kinds[entry.Kind]
    if monsterNear(anchor) then
        return nil
    end
    if entry.Kind == "DARK_SILHOUETTE" and WorldService.IsLit(anchor) then
        return nil
    end

    local best, bestScore = nil, -math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        local root = eligible(player)
        if root then
            local flat = Vector3.new(anchor.X - root.Position.X, 0, anchor.Z - root.Position.Z).Magnitude
            local inRange
            if kind.Jumpscare then
                inRange = flat <= TRIGGER.JumpscareRadius
            else
                inRange = flat >= TRIGGER.MinDistance and flat <= TRIGGER.MaxDistance
                    and (not kind.Visual or facing(root, anchor))
            end
            if inRange then
                local score = -flat
                if not kind.Shared and isAlone(player, root) then
                    score += 1000
                end
                if score > bestScore then
                    best, bestScore = player, score
                end
            end
        end
    end
    return best
end

-- Un susto que no necesita lugar y que el mapa todavía no usó.
local function fallbackKind(entry)
    local used = {}
    for _, other in ipairs(current.Entries) do
        if other ~= entry then
            used[other.Kind] = true
        end
    end
    for _, kind in ipairs(ScareConfig.Fallbacks) do
        if not used[kind] and kind ~= lastKind then
            return kind
        end
    end
    for _, kind in ipairs(ScareConfig.Fallbacks) do
        if kind ~= lastKind then
            return kind
        end
    end
    return ScareConfig.Fallbacks[1]
end

-- Llegó la hora y nadie pasó por el lugar: el susto se muda adelante de un
-- jugador (el más cercano a su lugar; si es personal, mejor uno que ande solo).
-- Devuelve jugador, punto y tipo (el mismo o uno que no necesita lugar).
local function relocate(entry)
    local planned = anchorOf(entry)
    local kind = entry.Kind
    local info = ScareConfig.Kinds[kind]
    local best, bestRoot, bestScore = nil, nil, -math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        local root = eligible(player)
        if root then
            local score = planned and -(root.Position - planned).Magnitude or 0
            if not info.Shared and isAlone(player, root) then
                score += 1000
            end
            if score > bestScore then
                best, bestRoot, bestScore = player, root, score
            end
        end
    end
    if not best then
        return nil
    end

    local base = Vector3.new(bestRoot.Position.X, planned and planned.Y or 0, bestRoot.Position.Z)
    local look = flatLook(bestRoot)
    local spot = base
    if info.Visual then
        spot = base + look * TRIGGER.RelocateDistance
    elseif info.Jumpscare then
        spot = base + look * 3
    elseif kind == "DOOR_SLAM" then
        spot = base + look * 10
    end
    if info.Visual and (monsterNear(spot) or (kind == "DARK_SILHOUETTE" and WorldService.IsLit(spot))) then
        kind = fallbackKind(entry)
        spot = base
    end
    return best, spot, kind
end

local function lightNear(cell, position)
    local best, bestDistance = nil, 60
    for _, fixture in ipairs(CollectionService:GetTagged("NocturnaLight")) do
        if fixture.Parent then
            if cell and fixture:GetAttribute("Cell") == cell then
                return fixture
            end
            if fixture:IsA("BasePart") then
                local distance = (fixture.Position - position).Magnitude
                if distance < bestDistance then
                    best, bestDistance = fixture, distance
                end
            end
        end
    end
    return best
end

local function fire(entry, player, anchor, forced)
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local now = os.clock()
    current.Fired[entry.Id] = true
    current.LastFiredAt = now
    current.GapUntil = current.PlayTime + TIMING.MinGap
    current.DueAt = current.PlayTime + ScarePlan.NextInterval(random, ScareConfig)
    lastKind = entry.Kind
    entry.Shared = ScareConfig.Kinds[entry.Kind].Shared

    local payload = {
        Id = entry.Id,
        Kind = entry.Kind,
        Position = anchor,
        From = root and root.Position or anchor,
        Seed = random:NextInteger(1, 1e6),
        Forced = forced == true,
    }
    if entry.Kind == "DOOR_SLAM" then
        payload.Slammed = DoorService.SlamNear(anchor, forced and 30 or 20)
    elseif entry.Kind == "LIGHT_REVEAL" then
        payload.Light = lightNear(not forced and entry.Cell or nil, anchor)
    end

    local recipients = {}
    if entry.Shared then
        for _, other in ipairs(Players:GetPlayers()) do
            local character = other.Character
            local otherRoot = character and character:FindFirstChild("HumanoidRootPart")
            if otherRoot and (otherRoot.Position - anchor).Magnitude <= TRIGGER.SharedRange then
                table.insert(recipients, other)
            end
        end
        if not table.find(recipients, player) then
            table.insert(recipients, player)
        end
    else
        recipients = {player}
    end
    for _, recipient in ipairs(recipients) do
        Remotes.FireClient("ScareEvent", recipient, payload)
    end
    table.insert(current.History, {
        Kind = entry.Kind,
        Planned = entry.Planned,
        At = now,
        PlayTime = current.PlayTime,
        Player = player,
        Cell = entry.Cell,
        Recipients = #recipients,
        Forced = forced == true,
    })
    EventBus.Emit("ScarePlayed", entry, player, recipients)
end

-- Motivos por los que ahora no puede haber ningún susto.
function ScareDirector.Blocked()
    if not current or not GameState.IsPlaying() or GameState.Chapter ~= current.Chapter then
        return "estado"
    end
    if FinalChaseService.IsActive() then
        return "persecución"
    end
    if MonsterService.IsPaused("Scene") then
        return "escena"
    end
    if os.clock() < blockedUntil then
        return "respiro"
    end
    if current.PlayTime < current.GapUntil then
        return "espera"
    end
    return nil
end

local function firedCount()
    local count = 0
    for _ in pairs(current.Fired) do
        count += 1
    end
    return count
end

function ScareDirector.Step()
    if ScareDirector.Blocked() then
        return nil
    end
    -- Solo: alguien pasa por el lugar de uno pendiente. Los de golpe nunca abren
    -- el mapa.
    local anyFired = firedCount() > 0
    for _, entry in ipairs(current.Entries) do
        if not current.Fired[entry.Id] and entry.Kind ~= lastKind
            and (anyFired or not ScarePlan.IsJumpscare(ScareConfig, entry.Kind)) then
            local anchor = anchorOf(entry)
            local player = anchor and pickPlayer(entry, anchor)
            if player then
                fire(entry, player, anchor, false)
                return entry
            end
        end
    end
    -- A tiempo: el próximo del plan, mudado adelante de un jugador.
    if current.PlayTime >= current.DueAt then
        for _, entry in ipairs(current.Entries) do
            if not current.Fired[entry.Id] then
                local player, spot, kind = relocate(entry)
                if player then
                    entry.Kind = kind
                    fire(entry, player, spot, true)
                    return entry
                end
                break
            end
        end
    end
    return nil
end

-- Avanza el reloj de juego (sólo mientras se juega: no en escenas, en la
-- persecución final ni fuera de la partida).
function ScareDirector.Advance(deltaTime)
    if not current then
        return
    end
    local reason = ScareDirector.Blocked()
    if reason == nil or CLOCK_RUNS[reason] then
        current.PlayTime += deltaTime
    end
end

-- Para pruebas: deja de esperar el intervalo.
function ScareDirector.SkipWait()
    blockedUntil = 0
    if current then
        current.GapUntil = 0
    end
end

function ScareDirector.Start()
    if started then
        return
    end
    started = true

    EventBus.On("WorldLoaded", function(plan)
        ScareDirector.Prepare(plan)
    end)
    EventBus.On("WorldUnloaded", ScareDirector.Clear)
    EventBus.On("CinematicPlayed", function(payload)
        local duration = typeof(payload) == "table" and tonumber(payload.Duration) or 3
        block(duration + TIMING.AfterCinematic)
    end)
    EventBus.On("PlayerHit", function()
        block(TIMING.AfterHit)
    end)
    EventBus.On("ScriptedHorror", function()
        block(TIMING.AfterScripted)
    end)

    RunService.Heartbeat:Connect(function(deltaTime)
        ScareDirector.Advance(deltaTime)
        elapsed += deltaTime
        if elapsed < TIMING.CheckInterval then
            return
        end
        elapsed = 0
        if current then
            ScareDirector.Step()
        end
    end)
end

return ScareDirector
