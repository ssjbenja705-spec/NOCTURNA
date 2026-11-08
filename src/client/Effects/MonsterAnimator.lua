-- Animación procedural de las criaturas. Corre sólo en el cliente y por distancia
-- (LOD), así no hay tráfico de red extra ni costo en equipos modestos.
--
-- Las criaturas son mallas cortadas en piezas unidas a la raíz por Motor6D (ver
-- MonsterFactory): no hay animaciones subidas, todo el movimiento se arma acá.
--
-- El servidor mueve la raíz anclada (~15 veces por segundo) y publica atributos en
-- el modelo: State, BehaviorState, MoveSpeed, AttackPhase, LookTarget, Rage y
-- Gesture/GestureCount. Con eso se arma, cada cuadro:
--   * el cuerpo sigue a la raíz con resortes: acelera, frena y gira con inercia
--     (nunca de golpe), se inclina al acelerar y hacia adentro en las curvas;
--   * el paso: la fase avanza con la velocidad real medida y la amplitud sale del
--     largo de cada pata, así el pie apoyado no patina; la cadera baja lo justo
--     para que la pata inclinada siga en el piso y el peso pasa de un lado al otro;
--   * brazos como péndulos con peso, cabeza con resorte propio que mira el
--     objetivo o el ruido, respiración y tics;
--   * cada estado (Idle, Patrol, Investigate, Search, Chase, Attack, Capture,
--     Stunned, Recover, Settle, Frozen...) aporta una pose con un peso que sube
--     y baja suave: no hay cambios secos entre estados;
--   * el ataque con anticipación, golpe y vuelta (o tropezón si erró);
--   * la firma de cada una (ver SIGNATURES y CreatureStyles).
--
-- Captura: mientras el modelo tenga el atributo AnimOverride, acá no se toca
-- ningún motor (los anima el sistema de captura); al quitarlo se vuelve a la pose
-- propia mezclando desde donde quedó.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local MonsterConfig = require(Shared:WaitForChild("Config"):WaitForChild("MonsterConfig"))

local CreatureMotion = require(script.Parent:WaitForChild("CreatureMotion"))
local CreatureStyles = require(script.Parent:WaitForChild("CreatureStyles"))

local Approach = CreatureMotion.Approach
local Spring = CreatureMotion.Spring
local AngleSpring = CreatureMotion.AngleSpring
local Smooth = CreatureMotion.Smoothstep
local Cycle = CreatureMotion.Cycle

local UPDATE_RANGE = 110
local FULL_RATE_RANGE = 45
-- Detalles caros (niebla del aliento, luz) sólo de cerca.
local DETAIL_RANGE = 35
local LOW_RATE = 1 / 15
local BEHIND_RATE = 1 / 6
local SNAP_DISTANCE = 14
local STOMP_RANGE = 70
-- Temblor de cámara por pisada: fuerte a menos de STOMP_NEAR, nada desde STOMP_FAR.
local STOMP_NEAR = 8
local STOMP_FAR = 60
local SCRAPE_RANGE = 45
local RESUME_TIME = 0.35
local STATE_RATE = 5
local WALL_REACH = 7
local TAU = math.pi * 2

local CHANNELS = CreatureStyles.Channels
local STATES = CreatureStyles.States
local ROLES = {Torso = true, Head = true, Arm = true, Leg = true, Jaw = true, Plate = true, Eye = true, Tongue = true}

-- Rapidez con que entra cada estado (por segundo); el resto, STATE_RATE.
local STATE_RATES = {Attack = 9, Stunned = 7, Capture = 8, Settle = 6, Recover = 3}

local MonsterAnimator = {}
local rigs = {}
local feedback = nil

local function sign(value)
    return value < 0 and -1 or 1
end

-- Sonido, cámara y calidad: se cargan aparte en el primer uso (un require puede
-- esperar y el cuadro de animación nunca debe quedar trabado).
local function loadFeedback()
    local loaded = {}
    local effects = script.Parent
    local cameraFolder = effects.Parent:FindFirstChild("Camera")
    local modules = {
        Audio = effects:FindFirstChild("AudioController"),
        Camera = cameraFolder and cameraFolder:FindFirstChild("FirstPerson"),
        Quality = effects:FindFirstChild("QualityController"),
    }
    for name, module in pairs(modules) do
        if module then
            local ok, result = pcall(require, module)
            loaded[name] = ok and result or nil
        end
    end
    feedback = loaded
end

local loading = false
local NO_FEEDBACK = {}

local function getFeedback()
    if feedback == nil then
        if not loading then
            loading = true
            task.spawn(loadFeedback)
        end
        return NO_FEEDBACK
    end
    return feedback
end

local function playAt(name, position)
    local audio = getFeedback().Audio
    if audio and audio.PlayAt then
        pcall(audio.PlayAt, name, position)
    end
end

local function lowQuality()
    local quality = getFeedback().Quality
    if quality and quality.IsLow then
        local ok, low = pcall(quality.IsLow)
        return ok and low == true
    end
    return false
end

-- Pisada de El Coloso: sonido y un impacto suave de cámara según la distancia.
local function stomp(rig, distance, side, scale)
    rig.Stomps += 1
    if distance > STOMP_RANGE then
        return
    end
    playAt("ColosoStep", rig.Visual.Position)
    local power = CreatureMotion.StompPower(distance, STOMP_NEAR, STOMP_FAR) * (scale or 1) * (rig.Rage and 1.25 or 1)
    rig.LastImpulse = power
    local camera = getFeedback().Camera
    if power > 0 and camera and camera.Impulse then
        pcall(camera.Impulse, power, side)
    end
end

-- Rig ----------------------------------------------------------------------------

-- Efectos propios de El Imitador: brillo rojo de la boca y vaho del aliento. Sólo
-- en este cliente (no se replican).
local function addImitadorEffects(rig, head)
    local mouth = Instance.new("Attachment")
    mouth.Name = "NocturnaMouth"
    mouth.Position = Vector3.new(0, -head.Size.Y * 0.3, -head.Size.Z * 0.45)
    mouth.Parent = head

    local glow = Instance.new("PointLight")
    glow.Name = "NocturnaMouthGlow"
    glow.Color = Color3.fromRGB(255, 40, 40)
    glow.Range = 5
    glow.Brightness = 0
    glow.Shadows = false
    glow.Parent = mouth

    local fog = Instance.new("ParticleEmitter")
    fog.Name = "NocturnaBreath"
    pcall(function()
        fog.Texture = "rbxasset://textures/particles/smoke_main.dds"
    end)
    fog.Rate = 0
    fog.Lifetime = NumberRange.new(0.8, 1.4)
    fog.Speed = NumberRange.new(0.6, 1.2)
    fog.SpreadAngle = Vector2.new(18, 18)
    fog.EmissionDirection = Enum.NormalId.Front
    fog.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0.9)})
    fog.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1)})
    fog.Color = ColorSequence.new(Color3.fromRGB(200, 196, 196))
    fog.Acceleration = Vector3.new(0, 0.5, 0)
    fog.Drag = 2
    fog.LightEmission = 0
    fog.Parent = mouth

    rig.Glow = glow
    rig.Fog = fog
end

local function newEntry(joint, role, part)
    local base = joint.C0
    local entry: {[string]: any} = {
        Joint = joint,
        Part = part,
        Base = base,
        Role = role,
        Side = sign(base.Position.X),
        Size = part.Size,
        -- Las extremidades giran desde el borde de arriba: su largo es el alto.
        Length = math.max(part.Size.Y, 0.5),
        Fwd = 0,
        FwdVel = 0,
        Out = 0,
        OutVel = 0,
        LastU = 0,
        Lift = 0,
        PhaseOffset = 0,
        DutyBias = 0,
        Swing = 0,
        From = nil,
    }
    return entry
end

local function addRig(model)
    if rigs[model] then
        return rigs[model]
    end
    local root = model:FindFirstChild("HumanoidRootPart") or model:WaitForChild("HumanoidRootPart", 5)
    if not root or rigs[model] then
        return rigs[model]
    end

    local kind = model:GetAttribute("Kind") or model.Name
    local style = CreatureStyles.Get(kind)
    local rig: {[string]: any} = {
        Model = model,
        Root = root,
        Kind = kind,
        Style = style,
        Settings = MonsterConfig[kind] or {},
        Joints = {},
        Feet = {},
        Visual = root.CFrame,
        VisualPosition = root.Position,
        VisualVelocity = Vector3.zero,
        RootLast = root.Position,
        RootLastTime = 0,
        RootVelocity = Vector3.zero,
        Yaw = 0,
        YawVel = 0,
        Tilt = CFrame.identity,
        Offset = CFrame.identity,
        Started = false,
        Speed = 0,
        Accel = 0,
        Gait = 0,
        Run = 0,
        Phase = 0,
        Cycle = 1,
        Duty = 0.6,
        Clock = 0,
        Elapsed = 0,
        Stomps = 0,
        Steps = 0,
        LastImpulse = 0,
        Random = Random.new(),
        State = "Idle",
        StateTime = 0,
        Behavior = "",
        BehaviorTime = 0,
        W = {},
        Pose = {},
        AttackPose = {},
        AttackPhase = "",
        AttackTime = 0,
        HeadYaw = 0,
        HeadYawVel = 0,
        HeadPitch = 0,
        HeadPitchVel = 0,
        HeadRoll = 0,
        HeadRollVel = 0,
        SnapUntil = 0,
        Gesture = nil,
        GestureTime = 99,
        GestureResult = {Pitch = 0, Roll = 0, Yaw = 0, Jaw = 0, Out = 0, Lean = 0, Jitter = 0},
        GestureSmooth = {Pitch = 0, Roll = 0, Yaw = 0, Jaw = 0, Out = 0, Lean = 0, Jitter = 0},
        TwitchActive = false,
        TwitchRole = "Head",
        TwitchSide = 1,
        TwitchAngles = Vector3.zero,
        TwitchTime = 0,
        NextTwitch = 1,
        TiltGoal = 0.15,
        NextTilt = 0,
        SwayX = 0,
        BodyRoll = 0,
        BodyLean = 0,
        AccelLean = 0,
        BodyTwist = 0,
        ExtraYaw = 0,
        ExtraTwist = 0,
        BreathLift = 0,
        SettleTwitches = 2,
        LastBehavior = "",
        Detail = false,
        LowQuality = false,
        Impact = 0,
        ImpactVel = 0,
        Hitch = 0,
        HitchSide = 1,
        Posture = 0,
        PostureGoal = 0,
        NextPosture = 0,
        OddTilt = 0,
        OddTiltGoal = 0,
        NextOddTilt = 0,
        PlateY = 0,
        PlateVel = 0,
        Shift = 0,
        SettleSide = 1,
        Flash = 0,
        Overridden = false,
        Frozen = false,
        Resume = 1,
        LeftS = 0,
        RightS = 0,
        NextScrape = 0,
    }
    rig.Seed = rig.Random:NextNumber(0, 100)
    for _, name in ipairs(STATES) do
        rig.W[name] = 0
    end
    rig.W.Idle = 1
    for _, channel in ipairs(CHANNELS) do
        rig.Pose[channel] = 0
        rig.AttackPose[channel] = 0
    end

    -- Piezas unidas a la raíz y, si el modelo las trae, partes bajas (rodillas).
    local lowers = {}
    local legs, legLength = 0, 0
    local pelvis = Vector3.zero
    for _, joint in ipairs(model:GetDescendants()) do
        if joint:IsA("Motor6D") and joint.Part1 then
            if joint.Part0 == root then
                local part = joint.Part1
                local role = ROLES[part.Name] and part.Name or "Torso"
                local entry = newEntry(joint, role, part)
                table.insert(rig.Joints, entry)
                if role == "Leg" then
                    legs += 1
                    legLength += entry.Length
                    pelvis += entry.Base.Position
                elseif role == "Head" and not rig.HeadBase then
                    rig.HeadBase = entry.Base
                    rig.HeadPart = part
                    rig.Neck = CFrame.new(0, -part.Size.Y * 0.4, 0)
                elseif role == "Torso" and part.Name == "Torso" and not rig.TorsoBase then
                    rig.TorsoBase = entry.Base
                elseif role == "Jaw" then
                    rig.JawMax = joint:GetAttribute("JawHinge") == true and style.JawHinged or style.JawCut
                end
            elseif joint.Part0 and string.sub(joint.Name, -10) == "LowerJoint" then
                lowers[joint.Part0] = joint
            end
        end
    end
    rig.LegLength = legs > 0 and legLength / legs or 3
    rig.Pelvis = legs > 0 and pelvis / legs or Vector3.zero
    rig.Neck = rig.Neck or CFrame.identity
    rig.JawMax = rig.JawMax or style.JawCut

    -- Patas que pisan: las piernas (y los brazos, si anda en cuatro patas).
    for _, entry in ipairs(rig.Joints) do
        local lowerJoint = lowers[entry.Part]
        if lowerJoint then
            entry.Lower = {Joint = lowerJoint, Base = lowerJoint.C0, Length = lowerJoint.Part1.Size.Y}
        end
        local isFoot = entry.Role == "Leg" or (style.Quadruped and entry.Role == "Arm")
        if isFoot then
            table.insert(rig.Feet, entry)
            local left = entry.Side < 0
            if style.LegPhase then
                entry.PhaseOffset = style.LegPhase[entry.Role .. (left and "Left" or "Right")] or 0
            else
                entry.PhaseOffset = left and 0 or 0.5 + (style.PhaseLag or 0)
                entry.DutyBias = (style.Limp or 0) * (left and 1 or -0.5)
            end
            entry.IsFoot = true
        end
    end

    rig.NextTwitch = rig.Random:NextNumber(style.TwitchEvery[1], style.TwitchEvery[2])
    rig.Connection = model:GetAttributeChangedSignal("GestureCount"):Connect(function()
        rig.Gesture = model:GetAttribute("Gesture")
        rig.GestureTime = 0
    end)

    if kind == "ElImitador" and rig.HeadPart then
        local ok, err = pcall(addImitadorEffects, rig, rig.HeadPart)
        if not ok then
            warn("[NOCTURNA] Sin efectos de boca para El Imitador: " .. tostring(err))
        end
    end

    rigs[model] = rig
    return rig
end

local function removeRig(model)
    local rig = rigs[model]
    if rig and rig.Connection then
        rig.Connection:Disconnect()
    end
    rigs[model] = nil
end

-- Mezcla desde la pose en que quedaron los motores (captura, congelado).
local function beginResume(rig)
    for _, entry in ipairs(rig.Joints) do
        entry.From = entry.Joint.C0
        if entry.Lower then
            entry.Lower.From = entry.Lower.Joint.C0
        end
    end
    rig.Resume = 0
end

-- Cuerpo: sigue a la raíz con inercia -------------------------------------------

local function yawOf(look)
    return math.atan2(-look.X, -look.Z)
end

local function followRoot(rig, deltaTime)
    local style = rig.Style
    local target = rig.Root.CFrame
    local goal = target.Position
    local targetYaw = yawOf(target.LookVector)
    local rest = CFrame.Angles(0, targetYaw, 0):Inverse() * (target - goal)

    -- La raíz llega a saltos (~15 por segundo): se estima su velocidad con cada
    -- salto y se extrapola entre uno y otro, así el cuerpo avanza parejo.
    if (goal - rig.RootLast).Magnitude > 1e-4 then
        local span = rig.Clock - rig.RootLastTime
        if span > 1e-3 then
            local sample = (goal - rig.RootLast) / span
            if sample.Magnitude > 60 then
                sample = Vector3.zero
            end
            rig.RootVelocity = rig.RootVelocity:Lerp(sample, 0.6)
        end
        rig.RootLast = goal
        rig.RootLastTime = rig.Clock
    elseif rig.Clock - rig.RootLastTime > 0.2 then
        rig.RootVelocity = rig.RootVelocity:Lerp(Vector3.zero, 1 - math.exp(-12 * deltaTime))
    end

    if not rig.Started or (rig.VisualPosition - goal).Magnitude > SNAP_DISTANCE then
        rig.Started = true
        rig.VisualPosition = goal
        rig.VisualVelocity = Vector3.zero
        rig.RootVelocity = Vector3.zero
        rig.Yaw = targetYaw
        rig.YawVel = 0
        rig.Tilt = rest
    else
        -- Resorte crítico que además copia la velocidad de la raíz: arranca y
        -- frena con suavidad, sin rebotar ni quedarse atrás.
        local omega = TAU * style.Follow
        local steps = math.clamp(math.ceil(deltaTime * 60), 1, 16)
        local h = deltaTime / steps
        local position, velocity = rig.VisualPosition, rig.VisualVelocity
        local goalVelocity = rig.RootVelocity
        -- Objetivo extrapolado al comienzo del intervalo; avanza hasta "ahora".
        local ahead = goal + goalVelocity * (math.min(rig.Clock - rig.RootLastTime, 0.1) - deltaTime)
        for _ = 1, steps do
            velocity += ((ahead - position) * (omega * omega) + (goalVelocity - velocity) * (2 * omega)) * h
            position += velocity * h
            ahead += goalVelocity * h
        end
        rig.VisualPosition, rig.VisualVelocity = position, velocity
        rig.Yaw, rig.YawVel = AngleSpring(rig.Yaw, rig.YawVel, targetYaw, style.TurnFreq, style.TurnDamp, deltaTime)
        rig.Tilt = rig.Tilt:Lerp(rest, 1 - math.exp(-10 * deltaTime))
    end
    rig.Visual = CFrame.new(rig.VisualPosition) * CFrame.Angles(0, rig.Yaw, 0) * rig.Tilt
end

-- El Trepador sube al techo por la pared más cercana (si hay una a mano): el
-- cuerpo va hasta la pared, se para sobre ella y después pasa al techo.
local wallParams = nil

local function findWall(rig)
    if not wallParams then
        wallParams = RaycastParams.new()
        wallParams.FilterType = Enum.RaycastFilterType.Exclude
    end
    local monsters = workspace:FindFirstChild("Monsters")
    wallParams.FilterDescendantsInstances = {monsters or rig.Model}
    local origin = rig.VisualPosition
    local look = rig.Visual.LookVector
    local forward = Vector3.new(look.X, 0, look.Z)
    forward = forward.Magnitude > 0.05 and forward.Unit or Vector3.new(0, 0, -1)
    local right = Vector3.new(-forward.Z, 0, forward.X)
    local best, bestDistance = nil, math.huge
    for _, direction in ipairs({forward, right, -right, -forward}) do
        local hit = workspace:Raycast(origin, direction * WALL_REACH, wallParams)
        if hit and math.abs(hit.Normal.Y) < 0.3 then
            local distance = (hit.Position - origin).Magnitude
            if distance < bestDistance then
                best, bestDistance = hit, distance
            end
        end
    end
    if best then
        rig.WallPoint = best.Position
        rig.WallNormal = Vector3.new(best.Normal.X, 0, best.Normal.Z).Unit
    else
        rig.WallPoint = nil
        rig.WallNormal = nil
    end
end

local function climbAlongWall(rig)
    local normal = rig.WallNormal
    if not normal then
        return
    end
    local duration = rig.Settings.ClimbTime or 0.9
    local t = math.clamp(rig.BehaviorTime / duration, 0, 1)
    local floorRotation = CFrame.Angles(0, rig.Yaw, 0)
    local wallRotation = CFrame.lookAt(Vector3.zero, Vector3.yAxis, normal)
    local ceilingRotation = floorRotation * CFrame.Angles(0, 0, math.pi)
    local rotation
    if t < 0.5 then
        rotation = floorRotation:Lerp(wallRotation, Smooth(t / 0.5))
    else
        rotation = wallRotation:Lerp(ceilingRotation, Smooth((t - 0.5) / 0.5))
    end
    -- Se arrima a la pared a mitad de camino y vuelve al centro al llegar arriba.
    local toWall = rig.WallPoint - rig.VisualPosition
    toWall = Vector3.new(toWall.X, 0, toWall.Z)
    local reach = math.max(toWall:Dot(-normal) - 1, 0)
    local offset = -normal * reach * math.sin(t * math.pi)
    rig.Visual = CFrame.new(rig.VisualPosition + offset) * rotation
    -- La orientación queda coherente para cuando termina la subida.
    rig.Tilt = CFrame.Angles(0, rig.Yaw, 0):Inverse() * rotation
end

-- Paso ---------------------------------------------------------------------------

local SIGNATURES = {}

local function footstep(rig, entry, distance)
    rig.Steps += 1
    rig.Model:SetAttribute("Footstep", rig.Steps * entry.Side) -- ColosoFootsteps escucha este pulso (signo = pie).
    local style = rig.Style
    if style.Heavy then
        -- Impacto: la cadera se hunde y las placas saltan.
        rig.ImpactVel -= 3.2 * math.min(rig.Gait, 1)
        rig.PlateVel += 1.6 * math.min(rig.Gait, 1)
        stomp(rig, distance, entry.Side, 0.55 + 0.45 * math.min(rig.Run + rig.Gait * 0.5, 1))
    elseif rig.Kind == "ElQuieto" then
        if rig.Steps % 2 == 0 and distance <= SCRAPE_RANGE and rig.Clock >= rig.NextScrape then
            rig.NextScrape = rig.Clock + 0.5
            playAt("QuietoScrape", rig.Visual.Position)
        end
    elseif rig.Kind == "ElOyente" then
        -- Cada tanto un enganche: el hombro cae y la cabeza da un tirón.
        if rig.Random:NextNumber() < 0.22 then
            rig.Hitch = 1
            rig.HitchSide = entry.Side
        end
    end
end

local function updateGait(rig, deltaTime, distance, moving)
    local style = rig.Style
    local velocity = rig.VisualVelocity
    local measured = moving and Vector3.new(velocity.X, 0, velocity.Z).Magnitude or 0
    if measured > 60 then
        measured = 0
    end
    local before = rig.Speed
    rig.Speed = Approach(rig.Speed, measured, 10, deltaTime)
    rig.Accel = Approach(rig.Accel, (rig.Speed - before) / math.max(deltaTime, 1e-3), 6, deltaTime)

    -- Girar en el lugar también mueve las patas.
    local drive = rig.Speed + (moving and math.min(math.abs(rig.YawVel), 4) * style.TurnStep or 0)
    local walking = drive > 0.35
    rig.Gait = Approach(rig.Gait, walking and 1 or 0, walking and 7 or 3.5, deltaTime)
    local runGoal = math.clamp((drive - style.WalkSpeed) / math.max(style.RunSpeed - style.WalkSpeed, 1), 0, 1)
    rig.Run = Approach(rig.Run, runGoal, 4, deltaTime)

    -- Zancada más corta al ir despacio; la fase avanza con la distancia recorrida.
    local stride = style.StrideWalk + (style.StrideRun - style.StrideWalk) * rig.Run
    local cycle = rig.LegLength * stride * (0.65 + 0.35 * math.clamp(drive / style.WalkSpeed, 0, 1))
    rig.Cycle = cycle
    rig.Duty = style.WalkDuty + (style.RunDuty - style.WalkDuty) * rig.Run
    rig.Phase = (rig.Phase + drive / cycle * deltaTime) % 1

    -- Pasos: cada pata apoya cuando su ciclo vuelve a empezar.
    for _, entry in ipairs(rig.Feet) do
        local u = (rig.Phase + entry.PhaseOffset) % 1
        if u < entry.LastU and rig.Gait > 0.3 then
            footstep(rig, entry, distance)
        end
        entry.LastU = u
    end
end

-- Ataque ---------------------------------------------------------------------------

local function updateAttack(rig, deltaTime, distance)
    local model = rig.Model
    local phase = model:GetAttribute("AttackPhase") or ""
    if phase ~= rig.AttackPhase then
        rig.AttackPhase = phase
        rig.AttackTime = 0
        if phase == "Strike" then
            rig.Flash = 1
            if rig.Style.Heavy then
                -- El aplastamiento hace temblar el piso.
                rig.ImpactVel -= 4
                rig.PlateVel += 2.5
                stomp(rig, distance, 1, 1.5)
            end
            if rig.Fog then
                pcall(rig.Fog.Emit, rig.Fog, 8)
            end
        end
    end
    rig.AttackTime += deltaTime

    local poses = rig.Style.Attack
    local pose, rate = nil, 5
    if phase == "Windup" then
        pose, rate = poses.Windup, 2.3 / math.max(rig.Settings.AttackWindup or 0.3, 0.05)
    elseif phase == "Strike" then
        pose, rate = poses.Strike, rig.Style.StrikeRate
    elseif phase == "Recover" then
        pose, rate = poses.Recover, 4
    elseif phase == "Miss" then
        pose, rate = poses.Miss, 5
    end

    local attack = rig.AttackPose
    for _, channel in ipairs(CHANNELS) do
        attack[channel] = Approach(attack[channel], pose and pose[channel] or 0, rate, deltaTime)
    end
end

-- Gestos puntuales: sumandos para cabeza, boca, brazos e inclinación. La tabla se
-- reusa entre cuadros para no generar basura en celulares.
local function bump(t, from, to)
    if t <= from or t >= to then
        return 0
    end
    return math.sin((t - from) / (to - from) * math.pi)
end

local GESTURE_KEYS = {"Pitch", "Roll", "Yaw", "Jaw", "Out", "Lean", "Jitter"}

local function rawGesture(rig, deltaTime)
    rig.GestureTime += deltaTime
    local t = rig.GestureTime
    local name = rig.Gesture
    local result = rig.GestureResult
    result.Pitch, result.Roll, result.Yaw, result.Jaw, result.Out, result.Lean, result.Jitter = 0, 0, 0, 0, 0, 0, 0
    if not name then
        return result
    end

    if name == "Click" and t < 0.4 then
        result.Pitch = 0.22 * math.exp(-t * 12) * math.cos(t * 50)
        result.Roll = 0.12 * math.exp(-t * 10)
    elseif name == "Snap" and t < 0.5 then
        -- Un ruido nuevo: la cabeza va de golpe hacia él y el cuerpo da un respingo.
        if t < deltaTime * 1.5 then
            rig.SnapUntil = rig.Clock + 0.3
        end
        result.Lean = -0.1 * bump(t, 0, 0.35)
        result.Roll = 0.15 * bump(t, 0, 0.25)
    elseif name == "Found" and t < 1 then
        -- Lo ubicó: ladea la cabeza, la adelanta y abre los brazos.
        if t < deltaTime * 1.5 then
            rig.SnapUntil = rig.Clock + 0.4
        end
        result.Roll = 0.5 * bump(t, 0, 0.4)
        result.Pitch = -0.25 * bump(t, 0.3, 1)
        result.Out = 0.6 * bump(t, 0.1, 1)
        result.Lean = 0.2 * bump(t, 0.3, 1)
    elseif name == "Voice" and t < 2.6 then
        result.Jaw = 0.35 + 0.35 * math.sin(t * 22)
        result.Roll = 0.35
    elseif name == "Scream" and t < 1.3 then
        local k = math.sin(math.clamp(t / 1.3, 0, 1) * math.pi)
        result.Pitch = 0.6 * k
        result.Jaw = 1.1 * k
        result.Out = 0.5 * k
        result.Lean = -0.2 * k
        rig.Flash = math.max(rig.Flash, k)
    elseif name == "Roar" and t < 1.7 then
        local k = math.sin(math.clamp(t / 1.7, 0, 1) * math.pi)
        result.Pitch = 0.45 * k
        result.Out = 0.7 * k
        result.Lean = -0.3 * k
        result.Jaw = k
    elseif name == "Drop" and t < 0.6 then
        result.Out = 0.9 * math.exp(-t * 5)
        result.Jitter = 1
    elseif name == "Skitter" and t < 1.2 then
        result.Jitter = 2.5
    end
    return result
end

-- Un gesto nuevo no corta de golpe al anterior: los canales se suavizan.
local function gestureOffsets(rig, deltaTime)
    local raw = rawGesture(rig, deltaTime)
    local smooth = rig.GestureSmooth
    for _, key in ipairs(GESTURE_KEYS) do
        smooth[key] = Approach(smooth[key], raw[key], 22, deltaTime)
    end
    return smooth
end

-- Tics de quieto: un sacudón rápido que vuelve solo (sin tablas nuevas).
local function startTwitch(rig, role, side, size)
    local random = rig.Random
    rig.TwitchActive = true
    rig.TwitchRole = role
    rig.TwitchSide = side
    rig.TwitchAngles = Vector3.new(random:NextNumber(-size, size), random:NextNumber(-size, size), random:NextNumber(-size, size))
    rig.TwitchTime = 0
end

local function updateTwitch(rig, deltaTime, still)
    local style = rig.Style
    if rig.TwitchActive then
        rig.TwitchTime += deltaTime
        if rig.TwitchTime > 0.8 then
            rig.TwitchActive = false
        end
    elseif still and rig.Clock >= rig.NextTwitch then
        local random = rig.Random
        local roll = random:NextNumber()
        startTwitch(rig, roll < 0.5 and "Head" or roll < 0.8 and "Arm" or "Torso", random:NextNumber() < 0.5 and -1 or 1, style.TwitchSize)
        rig.NextTwitch = rig.Clock + random:NextNumber(style.TwitchEvery[1], style.TwitchEvery[2])
    end
end

local function twitchFor(rig, role, side)
    if not rig.TwitchActive or rig.TwitchRole ~= role or (role == "Arm" and rig.TwitchSide ~= side) then
        return CFrame.identity
    end
    local t = rig.TwitchTime
    local k = math.exp(-t * 9) * math.min(1, t * 40)
    local angles = rig.TwitchAngles * k
    return CFrame.Angles(angles.X, angles.Y, angles.Z)
end

-- Estados: cada uno aporta su pose con un peso suave ----------------------------

local function blendStates(rig, deltaTime)
    local weights = rig.W
    local current = rig.State
    for _, name in ipairs(STATES) do
        weights[name] = Approach(weights[name], name == current and 1 or 0, STATE_RATES[name] or STATE_RATE, deltaTime)
    end

    local pose = rig.Pose
    local attack = rig.AttackPose
    for _, channel in ipairs(CHANNELS) do
        pose[channel] = attack[channel]
    end
    local poses = rig.Style.States
    for _, name in ipairs(STATES) do
        local weight = weights[name]
        local statePose = poses[name]
        if weight > 0.002 and statePose then
            for channel, value in pairs(statePose) do
                pose[channel] += value * weight
            end
        end
    end
    return pose
end

-- Aturdido (mareado, tambaleándose), reponiéndose (se sacude) y atrapado (forcejea).
local function stateLoops(rig, pose)
    local weights = rig.W
    local t = rig.Clock
    local style = rig.Style

    local stunned = weights.Stunned
    if stunned > 0.002 then
        pose.Crouch += style.StunCrouch * stunned * (0.85 + 0.15 * math.sin(t * 1.3))
        pose.HeadRoll += math.sin(t * 1.1) * 0.45 * stunned
        pose.HeadPitch += math.sin(t * 0.8 + 1) * 0.15 * stunned
        pose.ArmsFwd += (math.sin(t * 1.7 + 1) * 0.15 - 0.1) * stunned
        pose.Spread += 0.08 * stunned
        rig.BodyRoll += math.sin(t * 1.7) * 0.16 * stunned
        rig.ExtraYaw += math.sin(t * 0.9) * 0.3 * stunned
    end

    local recovering = weights.Recover
    if recovering > 0.002 then
        local since = rig.State == "Recover" and rig.StateTime or 2
        local fade = math.exp(-since * 2.5)
        rig.ExtraYaw += math.sin(since * 17) * 0.4 * fade * recovering
        rig.BodyRoll += math.sin(since * 13) * 0.1 * fade * recovering
        pose.Crouch += style.StunCrouch * 0.5 * (1 - Smooth(since / (rig.Settings.StunRecover or 1))) * recovering
    end

    local captured = weights.Capture
    if captured > 0.002 then
        local seed = rig.Seed
        rig.ExtraYaw += math.noise(seed, t * 5) * 0.8 * captured
        rig.BodyRoll += math.noise(seed + 3, t * 4) * 0.3 * captured
        pose.ArmsFwd += math.noise(seed + 5, t * 6) * 1.2 * captured
        pose.ArmsOut += math.abs(math.noise(seed + 9, t * 5)) * 0.8 * captured
        pose.HeadPitch += math.noise(seed + 11, t * 7) * 0.4 * captured
    end
end

-- Firmas de cada criatura ----------------------------------------------------------

function SIGNATURES.ElOyente(rig, deltaTime, pose)
    -- Ciego: ladea la cabeza para escuchar y la sostiene, cambiando de lado.
    local behavior = rig.Behavior
    local listening = behavior == "Listen" or behavior == "Search" or rig.State == "Idle" or rig.Speed < 1
    if rig.Clock >= rig.NextTilt then
        rig.TiltGoal = (listening and 0.5 or 0.12) * (rig.Random:NextNumber() < 0.5 and -1 or 1)
        rig.NextTilt = rig.Clock + rig.Random:NextNumber(1.2, 2.6)
    end
    rig.OddTilt = Approach(rig.OddTilt, rig.TiltGoal, listening and 3 or 6, deltaTime)
    pose.HeadRoll += rig.OddTilt

    -- Cabeza que cabecea con cada paso, como un pájaro.
    pose.HeadPitch -= 0.1 * math.cos(rig.Phase * TAU * 2) * rig.Gait

    -- Enganche del rengueo.
    rig.Hitch = Approach(rig.Hitch, 0, 7, deltaTime)
    if rig.Hitch > 0.01 then
        local k = rig.Hitch
        pose.HeadRoll += 0.3 * k * rig.HitchSide
        pose.Lean += 0.12 * k
        rig.BodyRoll += 0.1 * k * rig.HitchSide
    end
end

function SIGNATURES.ElImitador(rig, deltaTime, pose)
    local random = rig.Random
    local clock = rig.Clock
    -- Persiguiendo cambia de postura: erguido, encorvado casi en cuatro patas...
    if rig.State == "Chase" or rig.State == "Attack" then
        if clock >= rig.NextPosture then
            rig.PostureGoal = rig.PostureGoal > 0.5 and 0 or 1
            rig.NextPosture = clock + random:NextNumber(2.5, 5)
        end
    else
        rig.PostureGoal = 0
    end
    rig.Posture = Approach(rig.Posture, rig.PostureGoal, 2.2, deltaTime)
    if rig.Posture > 0.002 then
        for channel, value in pairs(rig.Style.Hunch) do
            pose[channel] += value * rig.Posture
        end
    end

    -- El torso ondula despacio, a destiempo del paso.
    rig.ExtraTwist += math.sin(clock * 1.3) * 0.12 + math.sin(rig.Phase * TAU - 1.6) * 0.1 * rig.Gait
    rig.BodyRoll += math.sin(clock * 0.9 + 1) * 0.08

    -- La cabeza se ladea demasiado, despacio, y se queda así.
    if clock >= rig.NextOddTilt then
        rig.OddTiltGoal = random:NextNumber() < 0.4 and 0 or random:NextNumber(0.55, 1.15) * (random:NextNumber() < 0.5 and -1 or 1)
        rig.NextOddTilt = clock + random:NextNumber(1.5, 3.5)
    end
    rig.OddTilt = Approach(rig.OddTilt, rig.OddTiltGoal, 2.2, deltaTime)
    pose.HeadRoll += rig.OddTilt

    -- Respira con la boca entreabierta.
    pose.Jaw += 0.06 + 0.05 * math.sin(clock * 2.4)

    -- Brillo rojo de la boca (fogonazo al gritar o atacar) y vaho cuando está cerca.
    rig.Flash = Approach(rig.Flash, 0, 2.5, deltaTime)
    if rig.Glow then
        rig.Glow.Brightness = (0.35 + 0.25 * math.sin(clock * 2.4) + pose.Jaw * 1.2 + rig.Flash * 3) * (rig.Detail and 1 or 0)
    end
    if rig.Fog then
        local rate = 0
        if rig.Detail and not rig.LowQuality then
            rate = (rig.State == "Chase" or rig.State == "Attack") and 7 or 2.5
        end
        if rig.Fog.Rate ~= rate then
            rig.Fog.Rate = rate
        end
    end
end

function SIGNATURES.ElQuieto(rig, deltaTime, pose)
    if rig.State ~= "Settle" then
        rig.Shift = Approach(rig.Shift, 0, 3, deltaTime)
        return
    end
    -- Lo empezaron a mirar: un segundo de micro-movimientos antes de quedar inmóvil.
    local t = rig.StateTime
    local side = rig.SettleSide
    pose.HeadRoll += 0.1 * Smooth(t / 0.35) * side
    pose.HeadPitch -= 0.05 * Smooth((t - 0.2) / 0.4)
    pose.Crouch -= 0.05 * Smooth(t / 0.5)
    pose.Lean += 0.03 * Smooth(t / 0.6)
    rig.Shift = 0.06 * Smooth(t / 0.7) * side
    -- La mano (los dedos son parte de la pieza del brazo) da dos tics.
    if rig.SettleTwitches == 0 and t >= 0.45 then
        rig.SettleTwitches = 1
        startTwitch(rig, "Arm", side, 0.14)
    elseif rig.SettleTwitches == 1 and t >= 0.72 then
        rig.SettleTwitches = 2
        startTwitch(rig, "Arm", -side, 0.07)
    end
end

function SIGNATURES.ElTrepador(rig, deltaTime, pose)
    local behavior = rig.Behavior
    local t = rig.BehaviorTime
    if behavior == "Drop" then
        -- Cae abierto, garras adelante.
        local k = Smooth(t / 0.15)
        pose.ArmsOut += 0.8 * k
        pose.ArmsFwd += 0.6 * k
        pose.Spread += 0.5 * k
        pose.Lean -= 0.3 * k
    elseif behavior == "Climb" then
        -- Se encoge para saltar y estira las patas hacia arriba.
        local k = bump(t, 0, rig.Settings.ClimbTime or 0.9)
        pose.Crouch -= 0.5 * bump(t, 0, 0.3)
        pose.ArmsFwd += 1.1 * k
        pose.Spread += 0.3 * k
    end
    if rig.LastBehavior == "Drop" and behavior ~= "Drop" and rig.BehaviorTime < deltaTime * 1.5 then
        -- Aterrizaje: se aplasta contra el piso.
        rig.ImpactVel -= 5
    end
end

function SIGNATURES.ElColoso(rig, deltaTime, pose)
    -- Las placas siguen al torso con retraso y rebotan con cada pisada.
    rig.PlateY, rig.PlateVel = Spring(rig.PlateY, rig.PlateVel, rig.BreathLift * 1.4, 2.2, 0.35, deltaTime)
    -- Respiración honda: los hombros suben y se nota en la cabeza.
    pose.HeadPitch += rig.BreathLift * 0.6
end

-- Cabeza -----------------------------------------------------------------------------

local function updateHead(rig, deltaTime, pose, gesture)
    local model = rig.Model
    local style = rig.Style
    local look = model:GetAttribute("LookTarget")

    local yaw, pitch
    if typeof(look) == "Vector3" and rig.HeadBase then
        local head = rig.Visual * rig.HeadBase
        local direction = rig.Visual:VectorToObjectSpace(look - head.Position)
        local horizontal = math.sqrt(direction.X * direction.X + direction.Z * direction.Z)
        yaw = math.atan2(-direction.X, -direction.Z)
        pitch = math.atan2(direction.Y, math.max(horizontal, 0.1))
    else
        yaw = math.noise(rig.Seed, rig.Clock * 0.25) * 1.2
        pitch = math.noise(rig.Seed + 7, rig.Clock * 0.2) * 0.3
    end
    local limit = style.HeadYawLimit
    yaw = math.clamp(yaw, -limit, limit) + rig.ExtraYaw + gesture.Yaw - rig.ExtraTwist * 0.5
    pitch = math.clamp(pitch, -0.6, 0.5) + pose.HeadPitch + gesture.Pitch
    local roll = pose.HeadRoll + gesture.Roll

    -- Cabeza estabilizada (El Imitador): queda fija aunque el cuerpo se incline.
    local stabilize = style.HeadStabilize
    if stabilize > 0 then
        pitch += rig.BodyLean * stabilize
        roll += rig.BodyRoll * stabilize
        yaw -= rig.BodyTwist * stabilize
    end

    -- Tic de la cabeza (El Oyente, antes del ataque, buscando el sonido exacto).
    if rig.AttackPhase == "Windup" and rig.Kind == "ElOyente" then
        yaw += math.sin(rig.Clock * 31) * 0.08
        roll += math.sin(rig.Clock * 23) * 0.1
    end

    local snapping = rig.Clock < rig.SnapUntil
    local frequency = snapping and style.SnapFreq or style.HeadFreq
    local damping = snapping and style.SnapDamp or style.HeadDamp
    rig.HeadYaw, rig.HeadYawVel = AngleSpring(rig.HeadYaw, rig.HeadYawVel, yaw, frequency, damping, deltaTime)
    rig.HeadPitch, rig.HeadPitchVel = Spring(rig.HeadPitch, rig.HeadPitchVel, pitch, frequency, damping, deltaTime)
    rig.HeadRoll, rig.HeadRollVel = Spring(rig.HeadRoll, rig.HeadRollVel, roll, math.min(frequency, 4), math.max(damping, 0.6), deltaTime)
end

-- Pose completa ----------------------------------------------------------------------

local function writeJoint(rig, entry, c0)
    local final = rig.Offset * c0
    if rig.Resume < 1 and entry.From then
        final = entry.From:Lerp(final, Smooth(rig.Resume))
    end
    entry.Joint.C0 = final
end

local function setState(rig, model)
    local state = model:GetAttribute("State") or "Idle"
    if state ~= rig.State then
        rig.State = state
        rig.StateTime = 0
        if state == "Settle" then
            rig.SettleSide = rig.Random:NextNumber() < 0.5 and -1 or 1
            rig.SettleTwitches = 0
        end
    end
    local behavior = model:GetAttribute("BehaviorState") or ""
    if behavior ~= rig.Behavior then
        rig.LastBehavior = rig.Behavior
        rig.Behavior = behavior
        rig.BehaviorTime = 0
        if behavior == "Climb" and rig.Kind == "ElTrepador" then
            findWall(rig)
        end
    end
end

local function animate(rig, deltaTime, distance)
    local model = rig.Model
    local style = rig.Style
    rig.Clock += deltaTime

    -- La captura anima el modelo: acá no se toca ningún motor.
    if model:GetAttribute("AnimOverride") ~= nil then
        rig.Overridden = true
        rig.Started = false
        return
    elseif rig.Overridden then
        rig.Overridden = false
        beginResume(rig)
    end

    setState(rig, model)
    rig.StateTime += deltaTime
    rig.BehaviorTime += deltaTime

    -- El Quieto observado no respira ni parpadea: la pose queda congelada tal cual.
    if rig.State == "Frozen" then
        rig.Frozen = true
        return
    elseif rig.Frozen then
        rig.Frozen = false
        rig.Started = false
        beginResume(rig)
    end

    rig.Detail = distance <= DETAIL_RANGE
    rig.LowQuality = rig.Detail and lowQuality()
    rig.Rage = model:GetAttribute("Rage") == true
    rig.ExtraYaw, rig.ExtraTwist, rig.BodyRoll = 0, 0, 0

    followRoot(rig, deltaTime)
    local transition = rig.Kind == "ElTrepador" and (rig.Behavior == "Drop" or rig.Behavior == "Climb")
    if transition and rig.Behavior == "Climb" then
        climbAlongWall(rig)
    end
    rig.Offset = rig.Root.CFrame:Inverse() * rig.Visual

    local busy = rig.State == "Stunned" or rig.State == "Recover" or rig.State == "Capture" or rig.State == "Settle"
    updateGait(rig, deltaTime, distance, not transition and not busy)
    updateAttack(rig, deltaTime, distance)
    local gesture = gestureOffsets(rig, deltaTime)
    updateTwitch(rig, deltaTime, rig.Gait < 0.3 and rig.AttackPhase == "" and rig.State ~= "Settle")
    local pose = blendStates(rig, deltaTime)
    stateLoops(rig, pose)

    -- Respiración: más visible quieta; agitada persiguiendo o en furia.
    local breath, amount = 0, 0
    if style.Breath > 0 then
        local excited = (rig.Rage or rig.State == "Chase" or rig.State == "Recover") and 1.6 or 1
        breath = math.sin(rig.Clock * TAU * excited / style.Breath)
        amount = style.BreathAmount * (1.5 - rig.Gait * 0.5) * excited
    end
    rig.BreathLift = breath * amount

    local signature = SIGNATURES[rig.Kind]
    if signature then
        signature(rig, deltaTime, pose)
    end
    pose.Lean += gesture.Lean
    updateHead(rig, deltaTime, pose, gesture)

    -- Patas: ángulo de cada una según su fase; la cadera baja por las apoyadas.
    local gait = rig.Gait
    local duty = rig.Duty
    local drop, planted = 0, 0
    local support = 0
    local twist = 0
    local leftS, rightS = 0, 0
    for _, entry in ipairs(rig.Feet) do
        local entryDuty = math.clamp(duty + entry.DutyBias, 0.3, 0.8)
        local u = (rig.Phase + entry.PhaseOffset) % 1
        local s, lift = Cycle(u, entryDuty)
        local amplitude = CreatureMotion.StrideAmplitude(rig.Cycle, entryDuty, entry.Length)
        local angle = s * amplitude * gait
        entry.Swing = angle
        entry.Lift = lift * gait
        if lift == 0 then
            -- Peso de la pata apoyada: entra y sale suave al pisar y al despegar,
            -- así la cadera no salta cuando cambia qué patas tocan el piso.
            local edge = math.min(u / entryDuty, 1 - u / entryDuty) / 0.18
            local weight = Smooth(edge)
            drop += CreatureMotion.HipDrop(angle, entry.Length) * weight
            planted += weight
            support += entry.Side * weight
        end
        if entry.Role == "Leg" then
            twist -= entry.Side * s * 0.5
            if entry.Side < 0 then
                leftS = s
            else
                rightS = s
            end
        end
    end
    rig.LeftS, rig.RightS = leftS, rightS
    -- Con menos de una pata entera apoyada (carrera) el cuerpo queda en el aire.
    local carried = math.max(planted, 1)
    local hipDrop = drop / carried
    local flight = (1 - math.min(planted, 1)) * style.RunBounce * rig.Run * gait
    rig.SwayX = Approach(rig.SwayX, support / carried * style.Sway * gait, 6, deltaTime)

    -- Impacto de las pisadas pesadas (resorte que vuelve solo).
    rig.Impact, rig.ImpactVel = Spring(rig.Impact, rig.ImpactVel, 0, 3, 0.55, deltaTime)

    -- Cadera.
    local hips = CFrame.new(rig.SwayX * 0.5 + rig.Shift, -hipDrop + flight + pose.Crouch + rig.Impact * math.max(style.ImpactDip, 0.15), 0)

    -- Torso: inclinación (carrera, aceleración, estado), contragiro de hombros,
    -- peso hacia la pata apoyada, inclinación en las curvas y temblor.
    local tremor = 0
    if style.Tremor then
        tremor = (style.Tremor + gesture.Jitter * 0.04) * math.noise(rig.Seed, rig.Clock * 9)
    end
    rig.AccelLean = Approach(rig.AccelLean, math.clamp(rig.Accel * style.AccelLean, -0.25, 0.3), 3, deltaTime)
    local accelLean = rig.AccelLean
    local lean = style.Lean * rig.Run * gait + accelLean + pose.Lean
    local bank = math.clamp(-rig.YawVel * rig.Speed * style.Bank, -0.25, 0.25)
    local bodyTwist = twist * style.Twist * gait + rig.ExtraTwist + tremor
    local bodyRoll = rig.SwayX * 0.5 + bank + rig.BodyRoll + tremor
    rig.BodyLean, rig.BodyTwist, rig.BodyRoll = lean, bodyTwist, bodyRoll
    local pelvis = rig.Pelvis
    local body = hips * CFrame.new(pelvis) * CFrame.Angles(-lean, bodyTwist, -bodyRoll) * CFrame.new(-pelvis)

    local torsoPose = CFrame.new(0, breath * amount, 0) * CFrame.Angles(-breath * amount * 0.6, 0, 0)
        * twitchFor(rig, "Torso", 0)
    local torsoBase = rig.TorsoBase or CFrame.identity
    local torsoDelta = body * torsoBase * torsoPose * torsoBase:Inverse()

    local headBase = rig.HeadBase or CFrame.identity
    local neck = rig.Neck
    local headPose = neck * CFrame.fromEulerAnglesYXZ(rig.HeadPitch, rig.HeadYaw, rig.HeadRoll) * neck:Inverse()
        * twitchFor(rig, "Head", 0)
    local headDelta = torsoDelta * headBase * headPose * headBase:Inverse()

    local jaw = math.clamp(pose.Jaw + gesture.Jaw, 0, 1)
    local armSwing = style.ArmSwing * gait
    local spread = style.Splay + pose.Spread

    for _, entry in ipairs(rig.Joints) do
        local role = entry.Role
        local side = entry.Side
        local c0
        if entry.IsFoot then
            local lift = entry.Lift * style.Clearance * entry.Length
            local fwd = entry.Swing + entry.Lift * 0.2
            local out = side * spread
            if role == "Arm" then
                -- Patas delanteras de El Trepador: también obedecen a la pose de brazos.
                fwd += pose.ArmsFwd * 0.5
                out += side * (pose.ArmsOut * 0.5 + gesture.Out * 0.5 + entry.Lift * 0.25)
            end
            c0 = hips * entry.Base * CFrame.new(0, lift, 0) * CFrame.Angles(fwd, 0, out)
            local lower = entry.Lower
            if lower then
                -- Rodilla real (si el modelo trae la parte baja): dos huesos.
                local reach = (entry.Length + lower.Length) * (1 - entry.Lift * 0.25 - math.max(-pose.Crouch, 0) * 0.08)
                local hip, knee = CreatureMotion.TwoBone(entry.Length, lower.Length, reach)
                c0 *= CFrame.Angles(hip * 0.5, 0, 0)
                local bend = role == "Arm" and knee or -knee
                local final = lower.Base * CFrame.Angles(bend, 0, 0)
                if rig.Resume < 1 and lower.From then
                    final = lower.From:Lerp(final, Smooth(rig.Resume))
                end
                lower.Joint.C0 = final
            end
        elseif role == "Arm" then
            -- Péndulo con peso: contrabalancea la pierna de su lado y llega con retraso.
            local legS = side < 0 and leftS or rightS
            local goalFwd = -legS * armSwing + pose.ArmsFwd
            local goalOut = pose.ArmsOut + gesture.Out
            entry.Fwd, entry.FwdVel = Spring(entry.Fwd, entry.FwdVel, goalFwd, style.ArmFreq, style.ArmDamp, deltaTime)
            entry.Out, entry.OutVel = Spring(entry.Out, entry.OutVel, goalOut, style.ArmFreq, style.ArmDamp, deltaTime)
            local hang = breath * amount * 0.4
            c0 = torsoDelta * entry.Base * CFrame.new(0, hang, 0) * CFrame.Angles(entry.Fwd, 0, side * entry.Out)
                * twitchFor(rig, "Arm", side)
        elseif role == "Head" then
            c0 = torsoDelta * entry.Base * headPose
        elseif role == "Eye" then
            c0 = headDelta * entry.Base
        elseif role == "Jaw" then
            local open = jaw * rig.JawMax
            c0 = headDelta * entry.Base * CFrame.Angles(open * 0.8, 0, 0) * CFrame.new(0, -open * 0.12, -open * 0.04)
        elseif role == "Tongue" then
            -- Lengua (si el modelo la trae): sale de la boca sólo bien abierta.
            local out = math.clamp((jaw - 0.55) / 0.45, 0, 1) * entry.Size.Z * 0.8
            c0 = headDelta * entry.Base * CFrame.new(0, -out * 0.2, -out)
        elseif role == "Plate" then
            local rattle = math.noise(rig.Seed + 2, rig.Clock * 14) * math.clamp(math.abs(rig.PlateVel) * 0.04, 0, 0.06)
            c0 = torsoDelta * entry.Base * CFrame.new(0, rig.PlateY, 0) * CFrame.Angles(rattle, 0, rattle * 0.5)
        else
            c0 = torsoDelta * entry.Base
        end
        writeJoint(rig, entry, c0)
    end

    if rig.Resume < 1 then
        rig.Resume = math.min(1, rig.Resume + deltaTime / RESUME_TIME)
    end
end

-- Recorre las criaturas: cerca, a ritmo completo; lejos o detrás de la cámara,
-- menos veces por segundo; fuera de alcance, nada.
function MonsterAnimator.Update(deltaTime, cameraCFrame)
    local origin = cameraCFrame.Position
    local forward = cameraCFrame.LookVector
    for model, rig in pairs(rigs) do
        if rig.Root.Parent == nil or rig.Broken then
            if rig.Root.Parent == nil then
                removeRig(model)
            end
        else
            local toRig = rig.Root.Position - origin
            local distance = toRig.Magnitude
            if distance <= UPDATE_RANGE then
                rig.Elapsed += deltaTime
                local interval = distance > FULL_RATE_RANGE and LOW_RATE or 0
                if distance > 12 and toRig:Dot(forward) < 0 then
                    interval = math.max(interval, BEHIND_RATE)
                end
                if rig.Elapsed >= interval then
                    local elapsed = math.min(rig.Elapsed, 0.25)
                    rig.Elapsed = 0
                    local ok, err = pcall(animate, rig, elapsed, distance)
                    if not ok then
                        rig.Broken = true
                        warn("[NOCTURNA] Falló la animación de " .. model.Name .. ": " .. tostring(err))
                    end
                end
            end
        end
    end
end

function MonsterAnimator.Track(model)
    return addRig(model)
end

function MonsterAnimator.Rigs()
    return rigs
end

-- Para pruebas y ajustes: la fuerza del temblor por una pisada a esa distancia.
function MonsterAnimator.StompPower(distance)
    return CreatureMotion.StompPower(distance, STOMP_NEAR, STOMP_FAR)
end

function MonsterAnimator.Start()
    CollectionService:GetInstanceAddedSignal("NocturnaMonster"):Connect(function(model)
        task.spawn(addRig, model)
    end)
    CollectionService:GetInstanceRemovedSignal("NocturnaMonster"):Connect(removeRig)
    for _, model in ipairs(CollectionService:GetTagged("NocturnaMonster")) do
        task.spawn(addRig, model)
    end

    RunService.RenderStepped:Connect(function(deltaTime)
        local camera = workspace.CurrentCamera
        if camera then
            MonsterAnimator.Update(deltaTime, camera.CFrame)
        end
    end)
end

return MonsterAnimator
