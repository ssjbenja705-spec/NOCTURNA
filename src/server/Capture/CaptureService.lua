-- Captura cinemática: cuando una criatura alcanza a un jugador ya no lo toca y
-- listo, lo agarra. Todo lo decide el servidor:
--   1. Grab: la criatura queda retenida (no piensa ni se mueve), el jugador se
--      ancla en la posición de agarre propia de esa criatura y todos los clientes
--      reciben la escena (atributos en el modelo + CaptureUpdate).
--   2. Struggle: el servidor arma la secuencia y el plazo; cada tecla llega por un
--      remoto limitado y se valida acá (orden, tiempo, spam). El progreso es sólo
--      del servidor: el cliente no puede adelantarlo ni estirar el tiempo.
--   3a. Zafó: la criatura lo suelta, el jugador le pega y queda aturdida 5 s
--       exactos (State = Stunned), después Recover y vuelve a cazar.
--   3b. No zafó: remate y el daño de siempre según la dificultad (DamageService);
--       si eso lo mata, sigue el camino normal de muerte/caída de MatchService.
-- Una criatura agarra a uno solo por vez y nadie agarra a quien ya está agarrado
-- o acaba de zafar. Si la víctima se va, muere o cambia el capítulo, todo se
-- suelta limpio.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local CaptureConfig = require(Shared.Config.CaptureConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local DamageService = require(script.Parent.Parent.Data.DamageService)
local AntiCheat = require(script.Parent.Parent.Security.AntiCheat)
local HidingService = require(script.Parent.Parent.World.HidingService)
local StruggleSession = require(script.Parent.StruggleSession)

local INPUT_RATE = 20
local STANDING_HEIGHT = 3

local CaptureService = {}
local captures = {} -- [player] = captura en curso
local byEntry = {} -- [entrada de criatura] = captura en curso
local stuns = {} -- [entrada de criatura] = aturdimiento o recuperación
local immuneUntil = {} -- [player] = os.clock() hasta el que no lo pueden agarrar
local nextId = 0
local random = Random.new()

local KEYS = {}
for _, key in ipairs(CaptureConfig.Keys) do
    KEYS[key] = true
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function flat(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function ease(alpha)
    alpha = math.clamp(alpha, 0, 1)
    return alpha * alpha * (3 - 2 * alpha)
end

local function refreshRayFilter()
    local excluded = {}
    local monsters = workspace:FindFirstChild("Monsters")
    if monsters then
        table.insert(excluded, monsters)
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(excluded, player.Character)
        end
    end
    rayParams.FilterDescendantsInstances = excluded
end

-- Lo que sigue más allá del primer obstáculo no sirve: se queda un poco antes.
local function clampToWalls(origin, target, margin)
    local offset = target - origin
    if offset.Magnitude < 0.05 then
        return target
    end
    local hit = workspace:Raycast(origin, offset, rayParams)
    if not hit then
        return target
    end
    local distance = math.max(0, (hit.Position - origin).Magnitude - margin)
    return origin + offset.Unit * distance
end

-- Métodos que el controlador de la IA puede ofrecer (Hold/Release/Stun). Si no
-- están, alcanza con que MonsterService no lo actualice mientras está retenido.
local function controllerCall(controller, method, ...)
    local fn = controller and controller[method]
    if type(fn) == "function" then
        local ok, err = pcall(fn, controller, ...)
        if not ok then
            warn("[NOCTURNA] Falló " .. method .. " de la criatura:", err)
        end
    end
end

local function publishState(entry, state)
    entry.StateOverride = state
    local value = state or entry.Controller:PublicState()
    if entry.Published then
        entry.Published.State = value
    end
    if entry.Model.Parent then
        entry.Model:SetAttribute("State", value)
    end
end

local function setModelCapture(entry, values)
    local model = entry.Model
    for _, name in ipairs({"AnimOverride", "CaptureId", "CaptureVictim", "CapturePhase", "CaptureProgress", "StunnedUntil"}) do
        if values[name] ~= nil or values.Clear then
            model:SetAttribute(name, values[name])
        end
    end
end

local function holdEntry(entry, reason)
    entry.CaptureHold = reason
    controllerCall(entry.Controller, "Hold", reason)
end

-- El ataque que terminó en agarre se cierra como un golpe: el comportamiento se
-- entera (algunos huyen o se reubican después de golpear).
local function closeAttack(entry)
    local controller = entry.Controller
    if controller.Attack and type(controller.EndAttack) == "function" then
        local ok, err = pcall(controller.EndAttack, controller)
        if not ok then
            warn("[NOCTURNA] Falló el cierre del ataque:", err)
            controller.Attack = nil
        end
    end
end

local function payload(capture, event, extra)
    local session = capture and capture.Session
    local data = {
        Event = event,
        Id = capture.Id,
        Victim = capture.Player.UserId,
        Kind = capture.Kind,
        Monster = capture.Entry.Model,
        Phase = capture.Phase,
        GrabTime = capture.Profile.GrabTime,
    }
    if session then
        local now = os.clock()
        data.Sequence = session.Sequence
        data.Index = session.Index
        data.Length = #session.Sequence
        data.Progress = session:Progress()
        data.TimeLeft = session:TimeLeft(now)
        data.TimeLimit = session.Deadline - session.Started
        data.Accepted = session.Accepted
    end
    for key, value in pairs(extra or {}) do
        data[key] = value
    end
    return data
end

local function broadcast(capture, event, extra)
    Remotes.FireAll("CaptureUpdate", payload(capture, event, extra))
end

-- Dónde queda el jugador: delante de la criatura, a su altura de pie más lo que
-- lo levante esa criatura, mirándola. Nunca adentro de una pared.
local function holdCFrame(entry, standY, profile)
    local rootCFrame = entry.Root.CFrame
    local look = flat(rootCFrame.LookVector)
    if look.Magnitude < 0.05 then
        look = flat(entry.Controller.Facing)
    end
    look = look.Magnitude > 0.05 and look.Unit or Vector3.new(0, 0, -1)
    local right = look:Cross(Vector3.new(0, 1, 0))
    local hold = profile.Hold

    local base = Vector3.new(rootCFrame.X, standY, rootCFrame.Z)
    local origin = base + Vector3.new(0, hold.Lift, 0)
    local wanted = origin + look * hold.Forward + right * hold.Side
    local position = clampToWalls(origin, wanted, 1)
    if (position - origin).Magnitude < 0.8 then
        position = origin + look * 0.8
    end
    local facing = Vector3.new(base.X, position.Y, base.Z)
    return CFrame.lookAt(position, facing) * CFrame.Angles(hold.Pitch or 0, 0, 0)
end

local function victimAlive(capture)
    local player = capture.Player
    if player.Parent ~= Players or player.Character ~= capture.Character then
        return false
    end
    local humanoid = capture.Humanoid
    return humanoid.Parent ~= nil and humanoid.Health > 0 and capture.Root.Parent ~= nil
end

-- Suelta al jugador de pie, un poco hacia atrás (el empujón), mirando a la criatura.
local function releaseVictim(capture, shove)
    local player = capture.Player
    local root = capture.Root
    if player.Parent == Players then
        player:SetAttribute("Captured", nil)
        player:SetAttribute("CapturedBy", nil)
    end
    if capture.Character then
        capture.Character:SetAttribute("CaptureHold", nil)
    end
    if not root or not root.Parent then
        return
    end

    refreshRayFilter()
    local creature = capture.Entry.Root.Position
    local hold = capture.Hold.Position
    local standing = Vector3.new(hold.X, capture.StandY, hold.Z)
    local away = flat(standing - creature)
    away = away.Magnitude > 0.05 and away.Unit or -flat(capture.Hold.LookVector)
    if away.Magnitude < 0.05 then
        away = Vector3.new(0, 0, 1)
    end
    local target = standing
    if shove then
        target = clampToWalls(standing, standing + away * CaptureConfig.ShoveDistance, 1)
    end
    AntiCheat.Grace(player, 2)
    root.CFrame = CFrame.lookAt(target, Vector3.new(creature.X, target.Y, creature.Z))
    root.Anchored = false
end

local function resumeEntry(entry)
    stuns[entry] = nil
    entry.CaptureHold = nil
    local controller = entry.Controller
    controllerCall(controller, "Release", "Capture")
    if type(controller.Stunned) == "number" then
        controller.Stunned = 0
    end
    if entry.Model.Parent then
        setModelCapture(entry, {Clear = true})
    end
    publishState(entry, nil)
end

-- Recuperación corta tras soltar a alguien sin aturdirse: no agarra a otro enseguida.
local function recoverEntry(entry, now)
    entry.CaptureHold = "Recover"
    stuns[entry] = {Phase = "Recover", RecoverUntil = now + CaptureConfig.RecoverTime}
    if entry.Model.Parent then
        setModelCapture(entry, {Clear = true})
    end
    publishState(entry, "Recover")
end

local function forget(capture)
    captures[capture.Player] = nil
    if byEntry[capture.Entry] == capture then
        byEntry[capture.Entry] = nil
    end
    capture.Phase = "Done"
end

-- Corte limpio: la víctima se fue, murió, cambió el capítulo o la criatura desapareció.
local function abort(capture, reason)
    if capture.Phase == "Done" then
        return
    end
    forget(capture)
    releaseVictim(capture, false)
    local entry = capture.Entry
    if entry.Model.Parent then
        recoverEntry(entry, os.clock())
    end
    broadcast(capture, "Ended", {Reason = reason})
end

local function startStruggle(capture, now)
    local difficulty = CaptureConfig.Difficulty[GameState.Difficulty] or CaptureConfig.Difficulty.Normal
    local profile = capture.Profile
    local length = difficulty.Length + (profile.ExtraLength or 0)
    capture.Session = StruggleSession.new({
        Sequence = StruggleSession.Generate(CaptureConfig.Keys, length, random),
        Now = now,
        TimeLimit = difficulty.Time + (profile.ExtraTime or 0),
        MistakeTime = difficulty.MistakeTime,
        MinInterval = CaptureConfig.MinPressInterval,
    })
    capture.Phase = "Struggle"
    capture.PhaseStart = now
    capture.Entry.Model:SetAttribute("CapturePhase", "Struggle")
    broadcast(capture, "Struggle")
end

local function startFail(capture, now)
    capture.Phase = "Fail"
    capture.PhaseStart = now
    capture.Entry.Model:SetAttribute("CapturePhase", "Fail")
    broadcast(capture, "Failing")
end

-- Zafó: suelta, contragolpe y aturdimiento de exactamente StunTime segundos.
local function escape(capture, now)
    local entry = capture.Entry
    local player = capture.Player
    forget(capture)
    releaseVictim(capture, true)
    immuneUntil[player] = now + CaptureConfig.EscapeImmunity

    closeAttack(entry)
    controllerCall(entry.Controller, "Stun", CaptureConfig.StunTime)
    entry.CaptureHold = "Stun"
    stuns[entry] = {
        Phase = "Stunned",
        Started = now,
        Until = now + CaptureConfig.StunTime,
        ReleaseUntil = now + CaptureConfig.ReleaseTime,
        Player = player,
    }
    setModelCapture(entry, {
        CapturePhase = "Release",
        CaptureProgress = 1,
        StunnedUntil = workspace:GetServerTimeNow() + CaptureConfig.StunTime,
    })
    publishState(entry, "Stunned")

    broadcast(capture, "Escaped", {StunTime = CaptureConfig.StunTime, Progress = 1})
    EventBus.Emit("PlayerEscaped", player, capture.Kind)
end

-- No zafó: el daño de siempre (escalado por la dificultad al crear la criatura).
local function completeFail(capture, now)
    local entry = capture.Entry
    local player = capture.Player
    forget(capture)
    releaseVictim(capture, true)
    immuneUntil[player] = now + CaptureConfig.FailImmunity
    closeAttack(entry)
    recoverEntry(entry, now)

    broadcast(capture, "Failed", {Damage = capture.Damage})
    if DamageService.ApplyDamage(player, capture.Damage) then
        Remotes.FireClient("MonsterEffect", player, "Jumpscare", {Kind = capture.Kind})
        EventBus.Emit("PlayerHit", player, capture.Kind)
    end
end

local function holdVictim(capture, now)
    local alpha = ease((now - capture.Started) / CaptureConfig.PullTime)
    local goal = alpha >= 1 and capture.Hold or capture.StartCFrame:Lerp(capture.Hold, alpha)
    local root = capture.Root
    -- Se reimpone cada cuadro: nada (física, latencia ni un cliente) lo mueve.
    if alpha < 1 or (root.Position - goal.Position).Magnitude > 0.05 then
        root.CFrame = goal
    end
    if not root.Anchored then
        root.Anchored = true
    end
end

local function updateCapture(capture, now)
    if not victimAlive(capture) then
        abort(capture, "Victim")
        return
    end
    if not capture.Entry.Model.Parent or not GameState.IsPlaying() then
        abort(capture, "Creature")
        return
    end

    holdVictim(capture, now)
    if capture.Phase == "Grab" then
        if now - capture.PhaseStart >= capture.Profile.GrabTime then
            startStruggle(capture, now)
        end
    elseif capture.Phase == "Struggle" then
        if capture.Session:Check(now) == "Failed" then
            startFail(capture, now)
        end
    elseif capture.Phase == "Fail" then
        if now - capture.PhaseStart >= CaptureConfig.FailTime then
            completeFail(capture, now)
        end
    end
end

local function updateStun(entry, record, now)
    if not entry.Model.Parent then
        stuns[entry] = nil
        return
    end
    if record.Phase == "Stunned" then
        if record.ReleaseUntil and now >= record.ReleaseUntil then
            -- Terminó de soltar: la pose de aturdido la anima el cliente con State.
            record.ReleaseUntil = nil
            entry.Model:SetAttribute("AnimOverride", nil)
            entry.Model:SetAttribute("CapturePhase", nil)
        end
        if now >= record.Until then
            record.Phase = "Recover"
            record.StunEnded = record.Until
            record.RecoverUntil = record.Until + CaptureConfig.RecoverTime
            entry.Model:SetAttribute("AnimOverride", nil)
            entry.Model:SetAttribute("CapturePhase", nil)
            entry.Model:SetAttribute("StunnedUntil", nil)
            publishState(entry, "Recover")
            EventBus.Emit("MonsterRecovered", entry.Controller.Kind)
        end
    elseif record.Phase == "Recover" and now >= record.RecoverUntil then
        resumeEntry(entry)
    end
end

function CaptureService.Update()
    local now = os.clock()
    if next(captures) then
        refreshRayFilter()
    end
    for _, capture in pairs(table.clone(captures)) do
        local ok, err = pcall(updateCapture, capture, now)
        if not ok then
            warn("[NOCTURNA] Error en la captura:", err)
            pcall(abort, capture, "Error")
        end
    end
    for entry, record in pairs(table.clone(stuns)) do
        local ok, err = pcall(updateStun, entry, record, now)
        if not ok then
            warn("[NOCTURNA] Error en el aturdimiento:", err)
            stuns[entry] = nil
            pcall(resumeEntry, entry)
        end
    end
end

-- API ---------------------------------------------------------------------------

function CaptureService.IsCaptured(player)
    return captures[player] ~= nil
end

function CaptureService.CaptureOf(player)
    return captures[player]
end

function CaptureService.IsImmune(player)
    return os.clock() < (immuneUntil[player] or -math.huge)
end

-- Ocupada: agarrando a alguien, aturdida o recuperándose.
function CaptureService.IsBusy(entry)
    return byEntry[entry] ~= nil or stuns[entry] ~= nil
end

function CaptureService.StunOf(entry)
    return stuns[entry]
end

-- Llamado cuando el zarpazo de una criatura conecta. Devuelve:
--   "Captured"  empezó la captura.
--   "Busy"      la criatura o la víctima ya están en una captura (no hay daño).
--   "Immune"    acaba de zafar o la protege una escena (no hay daño).
--   "Invalid"   no se puede capturar ahora (el que llama decide qué hacer).
function CaptureService.TryCapture(entry, player, damage)
    if not entry or not entry.Model or not entry.Model.Parent or not GameState.IsPlaying() then
        return "Invalid"
    end
    if captures[player] or CaptureService.IsBusy(entry) then
        return "Busy"
    end
    if CaptureService.IsImmune(player) then
        return "Immune"
    end

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 or player.Parent ~= Players then
        return "Invalid"
    end
    if character:FindFirstChildOfClass("ForceField") then
        return "Immune"
    end

    local controller = entry.Controller
    local kind = controller.Kind
    local profile = CaptureConfig.Creatures[kind] or CaptureConfig.Creatures.ElOyente
    if HidingService.IsHidden(player) then
        HidingService.ForceOut(player)
    end

    refreshRayFilter()
    controller:FaceTowards(root.Position)
    entry.Root.CFrame = controller:GetCFrame()
    local now = os.clock()
    local standY = root.Position.Y
    if standY > entry.Root.Position.Y + 1 then
        -- Por las dudas: nunca se arma el agarre más arriba de la criatura.
        standY = entry.Root.Position.Y
    end

    nextId += 1
    local capture = {
        Id = nextId,
        Player = player,
        Character = character,
        Root = root,
        Humanoid = humanoid,
        Entry = entry,
        Kind = kind,
        Profile = profile,
        Damage = math.clamp(math.floor((tonumber(damage) or 0) + 0.5), 1, 100),
        Phase = "Grab",
        Started = now,
        PhaseStart = now,
        StartCFrame = root.CFrame,
        StandY = standY,
    }
    capture.Hold = holdCFrame(entry, standY, profile)
    captures[player] = capture
    byEntry[entry] = capture

    holdEntry(entry, "Capture")
    root.Anchored = true
    AntiCheat.Grace(player, 2)
    player:SetAttribute("Captured", true)
    player:SetAttribute("CapturedBy", kind)
    character:SetAttribute("CaptureHold", capture.Hold)
    setModelCapture(entry, {
        AnimOverride = "Capture",
        CaptureId = capture.Id,
        CaptureVictim = player.UserId,
        CapturePhase = "Grab",
        CaptureProgress = 0,
    })
    publishState(entry, "Capture")

    broadcast(capture, "Begin")
    EventBus.Emit("PlayerCaptured", player, kind)
    return "Captured"
end

-- Una tecla del forcejeo. Devuelve el resultado (para las pruebas) o nil si se
-- descartó antes de llegar a las reglas.
function CaptureService.HandleInput(player, id, step, key)
    local capture = captures[player]
    if not capture or capture.Phase ~= "Struggle" or type(id) ~= "number" or id ~= capture.Id then
        return nil
    end
    local session = capture.Session
    if type(key) ~= "string" or not KEYS[key] then
        session.Rejected += 1
        return "Invalid"
    end

    local now = os.clock()
    local result = session:Press(step, key, now)
    capture.LastResult = result
    if result == "Escaped" then
        escape(capture, now)
    elseif result == "Late" or session.State == "Failed" then
        startFail(capture, now)
    elseif result == "Correct" or result == "Wrong" then
        capture.Entry.Model:SetAttribute("CaptureProgress", session:Progress())
        broadcast(capture, "Progress", {Result = result})
    end
    return result
end

-- Fin de capítulo, fracaso o vuelta al lobby: nadie queda anclado ni retenido.
function CaptureService.ReleaseAll()
    for _, capture in pairs(table.clone(captures)) do
        pcall(abort, capture, "Clear")
    end
    for entry in pairs(table.clone(stuns)) do
        pcall(resumeEntry, entry)
    end
    table.clear(captures)
    table.clear(byEntry)
    table.clear(stuns)
end

-- La criatura se retira (por errores): su víctima queda libre.
function CaptureService.ForgetEntry(entry)
    local capture = byEntry[entry]
    if capture then
        abort(capture, "Creature")
    end
    stuns[entry] = nil
end

function CaptureService.Start()
    Remotes.OnServer("CaptureInput", INPUT_RATE, function(player, id, step, key)
        CaptureService.HandleInput(player, id, step, key)
    end)

    EventBus.On("PlayerDied", function(player)
        local capture = captures[player]
        if capture then
            abort(capture, "Died")
        end
    end)

    Players.PlayerRemoving:Connect(function(player)
        local capture = captures[player]
        if capture then
            abort(capture, "Left")
        end
        immuneUntil[player] = nil
    end)

    RunService.Heartbeat:Connect(function()
        if next(captures) or next(stuns) then
            CaptureService.Update()
        end
    end)
end

return CaptureService
