-- Cuerpo común de las criaturas: movimiento, percepción, memoria y ataque.
-- No toca instancias: todo pasa por `world`, así las pruebas lo ejercitan sin Roblox.
--
-- Percepción propia de cada criatura: sólo persigue a quien vio, oyó o tiene
-- pegado. No hay alerta compartida ni objetivos adivinados; si lo pierde, va a la
-- última posición conocida, busca un rato y se rinde.
--
-- El cuerpo tiene inercia: acelera y frena de a poco (Acceleration/Deceleration)
-- y gira con velocidad angular limitada (TurnRate). El cliente anima a partir del
-- estado público (PublicState) y de la velocidad real.
--
-- La captura (otro sistema) la controla con Hold/Release y Stun.
local MonsterController = {}
MonsterController.__index = MonsterController

local REPATH_INTERVAL = 0.5
local ARRIVE_DISTANCE = 1.2
local HIDE_NOTICE_WINDOW = 1.5
-- De muy cerca se nota aunque esté de costado o detrás (fuera del cono de visión).
local PERIPHERAL_RANGE = 8
-- Recién perdido de vista: dobla la esquina detrás de él, como haría cualquiera.
local TRACK_GRACE = 1.2
local DEFAULT_LOSE_TIME = 3
local LUNGE_TIME = 0.15
local WINDUP_SPEED = 0.35
-- Giro quieto (mirando algo): más lento que al caminar.
local TURN_RATE = 4
local DEFAULT_TURN_RATE = 6
local TELEPORT_DISTANCE = 12
-- Aceleración por defecto (studs/s²) si la criatura no define la suya.
local DEFAULT_ACCELERATION = 30
local DEFAULT_DECELERATION = 40
-- Quieta este tiempo en una ronda, se publica como Idle (el cliente respira y mira).
local IDLE_AFTER = 0.5
local DEFAULT_RECOVER = 1
local MAX_STUN = 60
local EPSILON = 1e-6
-- Altura de los ojos del jugador sobre su raíz, si no informó su cámara.
local HEAD_HEIGHT = 1.5

-- Estados internos de cada comportamiento -> estado público que anima el cliente.
-- Recorrido completo: Idle -> Patrol -> Investigate -> Chase -> Attack -> (Capture)
-- -> Stunned -> Recover -> Chase. El detalle fino va en BehaviorState.
local PUBLIC_STATE = {
    Patrol = "Patrol",
    Crawl = "Patrol",
    Idle = "Idle",
    Listen = "Idle",
    Investigate = "Investigate",
    Search = "Search",
    Chase = "Chase",
    Stalk = "Chase",
    Pounce = "Chase",
    Drop = "Chase",
    Climb = "Patrol",
    Ambush = "Ambush",
    Settle = "Settle",
    Frozen = "Frozen",
    Flee = "Flee",
}

-- Rondas que, sin moverse, se ven como Idle.
local ROAMING = {Patrol = true, Crawl = true}

-- Motivos de retención que el cliente anima con un estado propio; el resto, Idle.
local HOLD_STATES = {Capture = "Capture", Stunned = "Stunned", Recover = "Recover"}

-- Mirada de cámara informada por cada jugador (la registra ViewService).
local viewProvider = nil

local function flat(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

function MonsterController.new(kind, settings, behavior, world, position, scale)
    local self = setmetatable({
        Kind = kind,
        Settings = settings,
        Behavior = behavior,
        World = world,
        Position = position,
        Facing = Vector3.new(0, 0, 1),
        Up = Vector3.new(0, 1, 0),
        -- Giro sobre el eje de avance (El Trepador al pasar del techo al piso).
        Roll = 0,
        Height = settings.BodyHeight,
        Speed = 0,
        -- Velocidad que lleva: se acerca a Speed con aceleración, sin arranques secos.
        CurrentSpeed = 0,
        ActualSpeed = 0,
        StillTime = 0,
        SpeedScale = scale and scale.Speed or 1,
        DamageScale = scale and scale.Damage or 1,
        SenseScale = scale and scale.Senses or 1,
        State = "Idle",
        StateTime = 0,
        Clock = 0,
        Waypoints = nil,
        WaypointIndex = 1,
        PathClock = -100,
        LastAttack = -100,
        LastSeen = {},
        LastSensed = {},
        HeardMark = {},
        LastKnown = nil,
        LookTarget = nil,
        Target = nil,
        HeardUntil = 0,
        -- Aturdida (StunLeft) y después reponiéndose (RecoverLeft); ver Stun.
        StunLeft = 0,
        RecoverLeft = 0,
        -- Retenciones activas por motivo (captura, escena...); ver Hold.
        Holds = {},
        Attack = nil,
        Rage = false,
        Encountered = {},
        GestureName = nil,
        GestureCount = 0,
    }, MonsterController)

    self.Position = Vector3.new(position.X, self.Height, position.Z)
    behavior.Init(self)
    return self
end

-- provider(player) -> {Origin = Vector3, Look = Vector3} o nil.
function MonsterController.SetViewProvider(provider)
    viewProvider = provider
end

function MonsterController:SetState(state)
    if self.State ~= state then
        self.State = state
        self.StateTime = 0
        self.World:OnStateChanged(self, state)
    end
end

-- Lo que ve el cliente: Idle, Patrol, Investigate, Search, Chase, Attack, Capture,
-- Stunned, Recover... (el zarpazo errado es Attack con fase Miss).
function MonsterController:PublicState()
    local held = next(self.Holds)
    if held then
        return self.Holds.Capture and "Capture" or HOLD_STATES[held] or "Idle"
    end
    if self.StunLeft > 0 then
        return "Stunned"
    end
    if self.RecoverLeft > 0 then
        return "Recover"
    end
    if self.Attack then
        return "Attack"
    end
    if ROAMING[self.State] and self.StillTime >= IDLE_AFTER then
        return "Idle"
    end
    return PUBLIC_STATE[self.State] or self.State
end

-- Un gesto puntual (chasquido, grito, caída...) que el cliente representa.
function MonsterController:Gesture(name)
    self.GestureName = name
    self.GestureCount += 1
end

-- Retención y aturdimiento (los usa la captura) ---------------------------------

function MonsterController:IsHeld()
    return next(self.Holds) ~= nil
end

function MonsterController:IsStunned()
    return self.StunLeft > 0 or self.RecoverLeft > 0
end

-- Ruidos que sonaron mientras no podía reaccionar: no los persigue después.
function MonsterController:ForgetNoises()
    for _, noise in ipairs(self.World:Noises()) do
        self.HeardUntil = math.max(self.HeardUntil, noise.Time)
        if noise.Source ~= nil then
            self.HeardMark[noise.Source] = math.max(self.HeardMark[noise.Source] or -math.huge, noise.Time)
        end
    end
end

-- Corta el ataque y el camino, y frena en seco.
function MonsterController:Interrupt()
    self.Attack = nil
    self:ClearPath()
    self.CurrentSpeed = 0
    self.ActualSpeed = 0
    if self.Behavior.OnInterrupt then
        self.Behavior.OnInterrupt(self)
    end
end

-- La deja quieta (sin moverse ni atacar) hasta Release con el mismo motivo. Su
-- reloj de percepción se detiene: al soltarla recuerda lo mismo que antes y no
-- reacciona a ruidos viejos.
function MonsterController:Hold(reason)
    reason = type(reason) == "string" and reason or "Hold"
    self.Holds[reason] = true
    self:Interrupt()
end

function MonsterController:Release(reason)
    reason = type(reason) == "string" and reason or "Hold"
    if not self.Holds[reason] then
        return
    end
    self.Holds[reason] = nil
    if not next(self.Holds) then
        self:ForgetNoises()
        -- Vuelve a calcular el camino enseguida.
        self.PathClock = -math.huge
    end
end

-- Aturdida durante `seconds` exactos; después se repone (Recover, StunRecover
-- segundos) y vuelve a su IA donde la dejó.
function MonsterController:Stun(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds ~= seconds or seconds <= 0 then
        return
    end
    self:Interrupt()
    self.StunLeft = math.min(seconds, MAX_STUN)
    self.RecoverLeft = 0
    self.LookTarget = nil
end

function MonsterController:UpdateStun(deltaTime)
    if self.StunLeft > 0 then
        self.StunLeft -= deltaTime
        if self.StunLeft <= EPSILON then
            local overshoot = math.max(-self.StunLeft, 0)
            self.StunLeft = 0
            self.RecoverLeft = math.max((self.Settings.StunRecover or DEFAULT_RECOVER) - overshoot, EPSILON * 2)
        end
    elseif self.RecoverLeft > 0 then
        self.RecoverLeft -= deltaTime
        if self.RecoverLeft <= EPSILON then
            self.RecoverLeft = 0
            self:ForgetNoises()
            self.PathClock = -math.huge
        end
    end
end

function MonsterController:Distance(position)
    local offset = position - self.Position
    return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

function MonsterController:ClearPath()
    self.Waypoints = nil
    self.WaypointIndex = 1
end

function MonsterController:HasPath()
    return self.Waypoints ~= nil and self.WaypointIndex <= #self.Waypoints
end

function MonsterController:GoTo(position, force)
    if not force and self.Clock - self.PathClock < REPATH_INTERVAL then
        return self:HasPath()
    end

    self.PathClock = self.Clock
    local points = self.World.Nav:Waypoints(self.Position, position, self.Height)
    if not points then
        self:ClearPath()
        return false
    end

    self.Waypoints = points
    self.WaypointIndex = 1
    return true
end

-- Gira el frente hacia `heading` con velocidad angular limitada: nada de giros
-- instantáneos. Devuelve cuánto quedó alineado (1 = de frente, -1 = de espaldas).
function MonsterController:SteerTowards(heading, deltaTime, rate)
    local wanted = flat(heading)
    if wanted.Magnitude < 0.05 then
        return 1
    end
    wanted = wanted.Unit
    local facing = self.Facing
    local dot = math.clamp(facing:Dot(wanted), -1, 1)
    local angle = math.acos(dot)
    if angle < 1e-3 then
        return dot
    end

    local step = math.min(angle, (rate or self.Settings.TurnRate or DEFAULT_TURN_RATE) * deltaTime)
    -- Sentido del giro según la componente vertical del producto cruz.
    local turn = facing:Cross(wanted).Y < 0 and -step or step
    local cosTurn, sinTurn = math.cos(turn), math.sin(turn)
    local turned = Vector3.new(
        facing.X * cosTurn + facing.Z * sinTurn,
        0,
        -facing.X * sinTurn + facing.Z * cosTurn
    )
    if turned.Magnitude > 0.05 then
        self.Facing = turned.Unit
    end
    return math.clamp(self.Facing:Dot(wanted), -1, 1)
end

-- Acelera y frena de a poco hacia la velocidad pedida.
function MonsterController:Throttle(goal, deltaTime)
    local settings = self.Settings
    local current = self.CurrentSpeed
    if goal > current then
        current = math.min(goal, current + (settings.Acceleration or DEFAULT_ACCELERATION) * deltaTime)
    else
        current = math.max(goal, current - (settings.Deceleration or DEFAULT_DECELERATION) * deltaTime)
    end
    self.CurrentSpeed = current
    return current
end

function MonsterController:MoveStep(deltaTime, speedFactor)
    if not self:HasPath() then
        self:Throttle(0, deltaTime)
        return
    end

    -- Con el frente desalineado avanza más despacio mientras termina de girar.
    local alignment = self:SteerTowards(self.Waypoints[self.WaypointIndex] - self.Position, deltaTime)
    local goal = self.Speed * self.SpeedScale * (speedFactor or 1) * (0.6 + 0.4 * math.max(alignment, 0))
    local budget = self:Throttle(goal, deltaTime) * deltaTime

    while budget > 0 and self:HasPath() do
        local waypoint = self.Waypoints[self.WaypointIndex]
        local offset = waypoint - self.Position
        local distance = offset.Magnitude

        if distance <= math.max(budget, ARRIVE_DISTANCE * 0.25) then
            self.Position = waypoint
            budget -= distance
            self.WaypointIndex += 1
        else
            self.Position += offset / distance * budget
            budget = 0
        end
    end

    if not self:HasPath() then
        self:ClearPath()
    end
end

-- Gira el cuerpo hacia un punto de a poco (quieto, mirando lo que le interesa).
function MonsterController:TurnTowards(position, deltaTime)
    local wanted = flat(position - self.Position)
    if wanted.Magnitude < 0.5 then
        return
    end
    self:SteerTowards(wanted, deltaTime, math.min(self.Settings.TurnRate or TURN_RATE, TURN_RATE))
end

function MonsterController:FaceTowards(position)
    local wanted = flat(position - self.Position)
    if wanted.Magnitude > 0.05 then
        self.Facing = wanted.Unit
    end
end

-- Paseo por celdas cercanas, con tendencia a acercarse al grupo.
function MonsterController:Wander()
    if self:HasPath() then
        return
    end

    local cell = self.World:PatrolCell(self)
    if cell then
        self:GoTo(self.World.Nav:Center(cell, self.Height), true)
    end
end

-- Percepción ------------------------------------------------------------------

-- Cuánto se lo ve: la linterna delata, la luz ayuda y agacharse en la oscuridad esconde.
function MonsterController:Visibility(snapshot)
    if snapshot.Flashlight then
        return 1
    end
    local factor = snapshot.Lit and 0.9 or 0.65
    if snapshot.Crouching then
        factor *= snapshot.Lit and 0.75 or 0.6
    end
    return factor
end

function MonsterController:SenseMultiplier()
    local rage = self.Rage and self.Settings.RageSenses or 1
    return self.SenseScale * rage
end

function MonsterController:Eye()
    return Vector3.new(self.Position.X, math.max(self.Position.Y, 3), self.Position.Z)
end

-- Desde dónde y hacia dónde mira un jugador: su cámara si la informó hace poco;
-- si no, la cabeza y el frente del cuerpo.
function MonsterController:ViewOf(snapshot)
    local view = snapshot.View or (viewProvider and viewProvider(snapshot.Player))
    if view and view.Origin and view.Look then
        return view.Origin, view.Look
    end
    return snapshot.Position + Vector3.new(0, HEAD_HEIGHT, 0), snapshot.Look
end

function MonsterController:CanSee(snapshot)
    local range = (self.Settings.VisionRange or 0) * self:SenseMultiplier()
    if range <= 0 or snapshot.Hidden then
        return false
    end

    local eye = self:Eye()
    local offset = snapshot.Position - eye
    if offset.Magnitude > range * self:Visibility(snapshot) then
        return false
    end

    -- Cono de visión: lo que tiene detrás no lo ve, salvo que esté muy cerca.
    local angle = self.Settings.VisionAngle or 360
    local heading = flat(offset)
    if angle < 360 and heading.Magnitude > PERIPHERAL_RANGE then
        if self.Facing:Dot(heading.Unit) < math.cos(math.rad(angle / 2)) then
            return false
        end
    end

    return self.World:LineOfSight(eye, snapshot.Position)
end

-- Lo que tiene pegado lo nota aunque esté a oscuras, de espaldas o agachado,
-- salvo que haya una pared en el medio.
function MonsterController:Senses(snapshot)
    if snapshot.Hidden then
        return false
    end
    return self:Distance(snapshot.Position) <= (self.Settings.CloseSense or 4)
        and self.World:LineOfSight(self:Eye(), snapshot.Position)
end

function MonsterController:Remember(snapshot, seen, position)
    local player = snapshot.Player
    if seen then
        self.LastSeen[player] = self.Clock
    end
    self.LastSensed[player] = self.Clock
    self.LastKnown = position or snapshot.Position
end

function MonsterController:SinceSensed(player)
    return self.Clock - (self.LastSensed[player] or -100)
end

-- ¿Oyó algo nuevo de este jugador en particular? No consume los ruidos.
function MonsterController:HeardFrom(player)
    local multiplier = (self.Settings.HearingMultiplier or 0) * self:SenseMultiplier()
    if multiplier <= 0 then
        return nil
    end

    local mark = self.HeardMark[player] or -math.huge
    local best = nil
    for _, noise in ipairs(self.World:Noises()) do
        if noise.Source == player and noise.Time > mark
            and noise.Radius * multiplier >= self:Distance(noise.Position) then
            best = noise
            mark = noise.Time
        end
    end
    if best then
        self.HeardMark[player] = mark
    end
    return best
end

-- Actualiza la memoria si lo percibe ahora. Devuelve si lo percibió.
function MonsterController:Perceive(snapshot)
    if snapshot.Hidden then
        return false
    end
    if self:CanSee(snapshot) then
        self:Remember(snapshot, true)
        return true
    end
    if self:Senses(snapshot) then
        self:Remember(snapshot, false)
        return true
    end
    local noise = self:HeardFrom(snapshot.Player)
    if noise then
        self:Remember(snapshot, false, noise.Position)
        return true
    end
    return false
end

function MonsterController:NearestVisible()
    local best, bestDistance = nil, math.huge
    for _, snapshot in ipairs(self.World:Players()) do
        local seen = self:CanSee(snapshot)
        if seen or self:Senses(snapshot) then
            self:Remember(snapshot, seen)
            local distance = self:Distance(snapshot.Position)
            if distance < bestDistance then
                best, bestDistance = snapshot, distance
            end
        end
    end
    if best then
        self.LastKnown = best.Position
    end
    return best, bestDistance
end

-- Omnisciente a propósito: sólo para efectos de ambiente (temblores), nunca para perseguir.
function MonsterController:NearestPlayer(includeHidden)
    local best, bestDistance = nil, math.huge
    for _, snapshot in ipairs(self.World:Players()) do
        if includeHidden or not snapshot.Hidden then
            local distance = self:Distance(snapshot.Position)
            if distance < bestDistance then
                best, bestDistance = snapshot, distance
            end
        end
    end
    return best, bestDistance
end

function MonsterController:FindSnapshot(player)
    for _, snapshot in ipairs(self.World:Players()) do
        if snapshot.Player == player then
            return snapshot
        end
    end
    return nil
end

-- El ruido nuevo más fuerte que llega hasta la criatura.
function MonsterController:Hear()
    local multiplier = (self.Settings.HearingMultiplier or 0) * self:SenseMultiplier()
    if multiplier <= 0 then
        return nil
    end

    local best, bestScore = nil, 0
    for _, noise in ipairs(self.World:Noises()) do
        if noise.Time > self.HeardUntil then
            local score = noise.Radius * multiplier - self:Distance(noise.Position)
            if score > bestScore then
                best, bestScore = noise, score
            end
        end
    end

    if best then
        self.HeardUntil = best.Time
        self.LookTarget = best.Position
    end
    return best
end

-- Ataque: anticipación, estocada corta y recuperación --------------------------

function MonsterController:TryAttack(snapshot)
    if self.Attack or self.Clock - self.LastAttack < self.Settings.AttackCooldown then
        return false
    end
    if self:Distance(snapshot.Position) > self.Settings.AttackRange then
        return false
    end

    self.LastAttack = self.Clock
    self.Attack = {Player = snapshot.Player, Phase = "Windup", Time = 0, Hit = false}
    self.LookTarget = snapshot.Position
    self:FaceTowards(snapshot.Position)
    return true
end

function MonsterController:Strike(snapshot)
    local attack = self.Attack
    local settings = self.Settings
    attack.Phase = "Strike"
    attack.Time = 0
    self:ClearPath()

    local lunge = settings.LungeDistance or 0
    if snapshot and not snapshot.Hidden then
        local distance = self:Distance(snapshot.Position)
        local clear = distance <= settings.AttackRange
            or self.World:LineOfSight(self:Eye(), snapshot.Position)
        attack.Hit = clear and distance <= settings.AttackRange + lunge

        local heading = flat(snapshot.Position - self.Position)
        local reach = math.clamp(distance - 1.5, 0, lunge)
        if clear and heading.Magnitude > 0.05 and reach > 0 then
            self.Facing = heading.Unit
            local goal = self.Position + heading.Unit * reach
            attack.From = self.Position
            attack.To = Vector3.new(goal.X, self.Height, goal.Z)
        end
    end

    -- Errar el zarpazo cuesta más: deja una ventana para escapar.
    attack.RecoverTime = (settings.AttackRecover or 1) * (attack.Hit and 1 or 1.4)
    if attack.Hit then
        self.World:Damage(self, snapshot, settings.Damage * self.DamageScale)
    end
end

function MonsterController:EndAttack()
    local attack = self.Attack
    self.Attack = nil
    if attack and self.Behavior.OnAttackEnd then
        self.Behavior.OnAttackEnd(self, attack.Hit, self:FindSnapshot(attack.Player))
    end
end

function MonsterController:UpdateAttack(deltaTime)
    local attack = self.Attack
    -- El comportamiento puede cortar el ataque (a El Quieto lo frena una mirada).
    if self.Behavior.AttackAllowed and not self.Behavior.AttackAllowed(self) then
        self.Attack = nil
        return
    end

    attack.Time += deltaTime
    local snapshot = self:FindSnapshot(attack.Player)
    if snapshot and not snapshot.Hidden then
        -- Mientras ataca no le saca los ojos de encima.
        self:Perceive(snapshot)
    end

    if attack.Phase == "Windup" then
        if not snapshot or snapshot.Hidden then
            -- Se metió en un escondite (o se fue): cancela y vuelve a perseguir.
            self.Attack = nil
            return
        end
        self.LookTarget = snapshot.Position
        self:GoTo(snapshot.Position)
        self:MoveStep(deltaTime, WINDUP_SPEED)
        self:FaceTowards(snapshot.Position)
        if attack.Time >= (self.Settings.AttackWindup or 0.3) then
            self:Strike(snapshot)
        end
    elseif attack.Phase == "Strike" then
        if attack.To then
            local alpha = math.clamp(attack.Time / LUNGE_TIME, 0, 1)
            self.Position = attack.From:Lerp(attack.To, alpha)
        end
        if attack.Time >= LUNGE_TIME then
            -- Si erró, el cliente lo muestra trastabillando (Miss).
            attack.Phase = attack.Hit and "Recover" or "Miss"
            attack.Time = 0
        end
    elseif attack.Time >= attack.RecoverTime then
        self:EndAttack()
    end
end

function MonsterController:Engage(snapshot)
    self.Target = snapshot.Player
    if not self.Encountered[snapshot.Player] then
        self.Encountered[snapshot.Player] = true
        self.World:Encounter(self, snapshot)
    end
end

-- Persecución con memoria propia. Devuelve false cuando lo perdió: el
-- comportamiento pasa a buscar en la última posición conocida.
function MonsterController:UpdateChase()
    local snapshot = self.Target and self:FindSnapshot(self.Target)
    if not snapshot then
        self.Target = nil
        return false
    end

    if snapshot.Hidden then
        local lastSeen = self.LastSeen[snapshot.Player] or -100
        local sawHiding = self.Clock - (snapshot.HiddenFor or 0) - lastSeen <= HIDE_NOTICE_WINDOW
        if not sawHiding then
            -- No lo vio entrar: busca donde lo perdió, no en el escondite.
            self.Target = nil
            return false
        end

        self.LookTarget = snapshot.Position
        self:GoTo(snapshot.Position)
        if self:Distance(snapshot.Position) <= self.Settings.AttackRange then
            self.World:PullOut(self, snapshot)
            self:TryAttack(snapshot)
        end
        return true
    end

    self:Perceive(snapshot)
    local since = self:SinceSensed(snapshot.Player)
    if since <= TRACK_GRACE then
        self.LookTarget = snapshot.Position
        self:GoTo(snapshot.Position)
        self:TryAttack(snapshot)
        return true
    end

    -- Sigue el último rastro (donde lo vio u oyó) hasta llegar o rendirse.
    if self.LastKnown and since <= (self.Settings.LoseTime or DEFAULT_LOSE_TIME)
        and self:Distance(self.LastKnown) > 2 then
        self.LookTarget = self.LastKnown
        self:GoTo(self.LastKnown)
        return true
    end

    self.Target = nil
    return false
end

-- Búsqueda: va a la última posición conocida, mira alrededor y se rinde.
function MonsterController:BeginSearch()
    self:ClearPath()
    self.SearchArrived = nil
    if self.LastKnown then
        self:GoTo(self.LastKnown, true)
    end
end

-- Devuelve false cuando terminó de buscar.
function MonsterController:UpdateSearch(speed)
    if self:HasPath() then
        self.Speed = speed
        self.LookTarget = self.LastKnown
        return true
    end

    self.Speed = 0
    self.SearchArrived = self.SearchArrived or self.Clock
    local elapsed = self.Clock - self.SearchArrived
    -- Mira a un lado y al otro, como quien escucha.
    local sweep = CFrame.Angles(0, math.sin(elapsed * 1.3) * 1.3, 0):VectorToWorldSpace(self.Facing)
    self.LookTarget = self.Position + sweep * 10
    if elapsed >= self.Settings.SearchTime then
        self.LastKnown = nil
        self.LookTarget = nil
        return false
    end
    return true
end

function MonsterController:Tick(deltaTime)
    -- Retenida (captura, escena): no se mueve, no ataca y su reloj no corre.
    if next(self.Holds) then
        self.ActualSpeed = 0
        self.CurrentSpeed = 0
        return
    end
    -- Aturdida o reponiéndose: tampoco piensa ni se mueve.
    if self.StunLeft > 0 or self.RecoverLeft > 0 then
        self.ActualSpeed = 0
        self.CurrentSpeed = 0
        self:UpdateStun(deltaTime)
        return
    end

    self.Clock += deltaTime
    self.StateTime += deltaTime
    local before = self.Position

    if self.Attack then
        self:UpdateAttack(deltaTime)
    else
        self.Behavior.Update(self, deltaTime)
        self:MoveStep(deltaTime)
        if not self:HasPath() and self.LookTarget then
            self:TurnTowards(self.LookTarget, deltaTime)
        end
        self.World:OpenDoorsNear(self.Position)
    end

    -- Velocidad real (la que anima el cliente): un salto de teletransporte no cuenta.
    local moved = flat(self.Position - before).Magnitude
    self.ActualSpeed = (moved > TELEPORT_DISTANCE or deltaTime <= 0) and 0 or moved / deltaTime
    if self.ActualSpeed < 0.3 then
        self.StillTime += deltaTime
    else
        self.StillTime = 0
    end
end

function MonsterController:GetCFrame()
    local cframe = CFrame.lookAt(self.Position, self.Position + self.Facing, self.Up)
    if self.Roll ~= 0 then
        cframe *= CFrame.Angles(0, 0, self.Roll)
    end
    return cframe
end

return MonsterController
