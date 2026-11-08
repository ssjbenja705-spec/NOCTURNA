-- Sustos al azar en cada mapa (3 o 4). Al cargar el capítulo se eligen tipos y
-- lugares (ScarePlan); durante la partida cada uno se dispara una sola vez,
-- cuando alguien pasa cerca y mirando, con esperas al azar entre uno y otro.
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

local ScareDirector = {}
local current = nil
local lastKind = nil
local nextAllowedAt = math.huge
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
    current = {
        Entries = entries,
        Fired = {},
        Chapter = GameState.Chapter,
        StartedAt = os.clock(),
        LastFiredAt = nil,
        History = {},
    }
    nextAllowedAt = os.clock() + TIMING.FirstDelay
    return entries
end

function ScareDirector.Clear()
    current = nil
    nextAllowedAt = math.huge
end

function ScareDirector.Plan()
    return current and current.Entries or nil
end

function ScareDirector.History()
    return current and current.History or {}
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

local function facing(root, point)
    local look = root.CFrame.LookVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    local offset = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)
    if flatLook.Magnitude < 0.01 or offset.Magnitude < 0.01 then
        return false
    end
    return flatLook.Unit:Dot(offset.Unit) >= TRIGGER.FacingDot
end

-- El jugador que dispara este susto, o nil si nadie puede ahora.
local function pickPlayer(entry, anchor, relaxed)
    local kind = ScareConfig.Kinds[entry.Kind]
    local maxDistance = relaxed and TRIGGER.RelaxedDistance or TRIGGER.MaxDistance
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
            local inRange = flat >= TRIGGER.MinDistance and flat <= maxDistance
            if inRange and (not kind.Visual or facing(root, anchor)) then
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

local function lightInCell(cell)
    for _, fixture in ipairs(CollectionService:GetTagged("NocturnaLight")) do
        if fixture:GetAttribute("Cell") == cell and fixture.Parent then
            return fixture
        end
    end
    return nil
end

local function fire(entry, player, anchor)
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local now = os.clock()
    current.Fired[entry.Id] = true
    current.LastFiredAt = now
    lastKind = entry.Kind
    nextAllowedAt = now + ScarePlan.NextInterval(random, ScareConfig)

    local payload = {
        Id = entry.Id,
        Kind = entry.Kind,
        Position = anchor,
        From = root and root.Position or anchor,
        Seed = random:NextInteger(1, 1e6),
    }
    if entry.Kind == "DOOR_SLAM" then
        payload.Slammed = DoorService.SlamNear(anchor, 20)
    elseif entry.Kind == "LIGHT_REVEAL" then
        payload.Light = lightInCell(entry.Cell)
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
    else
        recipients = {player}
    end
    for _, recipient in ipairs(recipients) do
        Remotes.FireClient("ScareEvent", recipient, payload)
    end
    table.insert(current.History, {Kind = entry.Kind, At = now, Player = player, Cell = entry.Cell, Recipients = #recipients})
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
    local now = os.clock()
    if now < blockedUntil then
        return "respiro"
    end
    if now < nextAllowedAt then
        return "espera"
    end
    return nil
end

function ScareDirector.Step()
    if ScareDirector.Blocked() then
        return nil
    end
    local now = os.clock()
    local relaxed = now - (current.LastFiredAt or current.StartedAt) > TRIGGER.RelaxAfter
    for _, entry in ipairs(current.Entries) do
        if not current.Fired[entry.Id] and entry.Kind ~= lastKind then
            local anchor = anchorOf(entry)
            local player = anchor and pickPlayer(entry, anchor, relaxed)
            if player then
                fire(entry, player, anchor)
                return entry
            end
        end
    end
    return nil
end

-- Para pruebas: deja de esperar el intervalo.
function ScareDirector.SkipWait()
    nextAllowedAt = 0
    blockedUntil = 0
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
