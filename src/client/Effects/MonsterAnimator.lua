-- Animación procedural de las criaturas. Corre sólo en el cliente y por distancia
-- (LOD), así no hay tráfico de red extra ni costo en equipos modestos.
--
-- El servidor mueve la raíz anclada (~15 veces por segundo) y publica atributos en
-- el modelo: State, BehaviorState, MoveSpeed, AttackPhase, LookTarget, Rage y
-- Gesture/GestureCount. Acá se suaviza ese movimiento y se arma la pose:
--   * paso sincronizado con la velocidad real (zancada según el largo de la pierna),
--     balanceo de cadera, contragiro de hombros y rebote;
--   * giro suave del cuerpo y cabeza que sigue al objetivo o al ruido;
--   * respiración y tics cuando está quieta;
--   * ataque con anticipación, estocada y recuperación (o tropezón si erró);
--   * la firma de cada una: El Oyente ladea la cabeza para escuchar, El Imitador se
--     mueve a sacudones, El Quieto no respira cuando lo miran y avanza a saltos,
--     El Trepador camina como araña por el techo y El Coloso pisa fuerte.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local MonsterConfig = require(Shared:WaitForChild("Config"):WaitForChild("MonsterConfig"))

local UPDATE_RANGE = 110
local FULL_RATE_RANGE = 45
local LOW_RATE = 1 / 15
local BEHIND_RATE = 1 / 6
local SNAP_DISTANCE = 14
local POSITION_RATE = 14
local ROTATION_RATE = 9
local STOMP_RANGE = 70
local SCRAPE_RANGE = 45
local TAU = math.pi * 2

-- Zancada: studs por ciclo completo, en largos de pierna. Ángulos en radianes.
local PROFILES = {
    ElOyente = {
        Stride = 2.6, LegSwing = 0.55, ArmSwing = 0.3, Sway = 0.06, Twist = 0.12, Bob = 0.14,
        Lean = 0.25, FullSpeed = 14, Breath = 2.6, BreathAmount = 0.05,
        TwitchEvery = {2, 5}, TwitchSize = 0.22, HeadRate = 6,
    },
    ElImitador = {
        Stride = 2.3, LegSwing = 0.62, ArmSwing = 0.5, Sway = 0.05, Twist = 0.18, Bob = 0.12,
        Lean = 0.3, FullSpeed = 15, Breath = 2, BreathAmount = 0.04,
        TwitchEvery = {0.8, 2.2}, TwitchSize = 0.45, HeadRate = 35, Jerky = true,
    },
    ElQuieto = {
        Stride = 2.4, LegSwing = 0.5, ArmSwing = 0.28, Sway = 0, Twist = 0.05, Bob = 0.06,
        Lean = 0.12, FullSpeed = 15, Breath = 0, BreathAmount = 0,
        TwitchEvery = {3, 7}, TwitchSize = 0.3, HeadRate = 40, StopMotion = 0.14,
    },
    ElTrepador = {
        Stride = 1.7, LegSwing = 0.6, ArmSwing = 0.7, Sway = 0.04, Twist = 0.1, Bob = 0.08,
        Lean = 0.15, FullSpeed = 14, Breath = 1.4, BreathAmount = 0.035,
        TwitchEvery = {1, 3}, TwitchSize = 0.25, HeadRate = 12, Crawler = true,
    },
    ElColoso = {
        Stride = 3, LegSwing = 0.38, ArmSwing = 0.32, Sway = 0.12, Twist = 0.08, Bob = 0.32,
        Lean = 0.12, FullSpeed = 13, Breath = 3.4, BreathAmount = 0.08,
        TwitchEvery = {4, 9}, TwitchSize = 0.12, HeadRate = 3.5, Heavy = true,
    },
}

-- Poses del ataque: inclinación (+ hacia atrás), brazos (+ hacia adelante),
-- apertura de brazos, agachada y mandíbula.
local ATTACK_POSES = {
    Windup = {Lean = 0.28, Arms = -0.9, Out = 0.35, Crouch = -0.18, Jaw = 0.35},
    Strike = {Lean = -0.5, Arms = 1.7, Out = 0.1, Crouch = -0.05, Jaw = 0.9},
    Recover = {Lean = -0.18, Arms = 0.5, Out = 0.05, Crouch = 0, Jaw = 0.2},
    Stumble = {Lean = -0.45, Arms = 0.2, Out = 0.25, Crouch = -0.12, Jaw = 0.1},
    None = {Lean = 0, Arms = 0, Out = 0, Crouch = 0, Jaw = 0},
}

local MonsterAnimator = {}
local rigs = {}
local feedback = nil

local function approach(current, goal, rate, deltaTime)
    return current + (goal - current) * (1 - math.exp(-rate * deltaTime))
end

local function sign(value)
    return value < 0 and -1 or 1
end

-- Sonido y temblor de cámara: se buscan al primer uso para no atar el arranque.
local function getFeedback()
    if feedback == nil then
        feedback = {}
        local audioModule = script.Parent:FindFirstChild("AudioController")
        local cameraFolder = script.Parent.Parent:FindFirstChild("Camera")
        local cameraModule = cameraFolder and cameraFolder:FindFirstChild("FirstPerson")
        if audioModule then
            local ok, audio = pcall(require, audioModule)
            feedback.Audio = ok and audio or nil
        end
        if cameraModule then
            local ok, camera = pcall(require, cameraModule)
            feedback.Camera = ok and camera or nil
        end
    end
    return feedback
end

local function playAt(name, position)
    local audio = getFeedback().Audio
    if audio and audio.PlayAt then
        pcall(audio.PlayAt, name, position)
    end
end

local function stomp(rig, distance)
    playAt("ColosoStep", rig.Visual.Position)
    local camera = getFeedback().Camera
    local power = 1 - math.clamp(distance / STOMP_RANGE, 0, 1)
    if camera and camera.Shake and power > 0 then
        pcall(camera.Shake, (rig.Rage and 3 or 2.2) * power, 0.35)
    end
    rig.Stomps += 1
end

-- Rig ----------------------------------------------------------------------------

local ROLES = {Torso = true, Head = true, Arm = true, Leg = true, Jaw = true, Plate = true, Eye = true}

local function addRig(model)
    if rigs[model] then
        return rigs[model]
    end
    local root = model:FindFirstChild("HumanoidRootPart") or model:WaitForChild("HumanoidRootPart", 5)
    if not root or rigs[model] then
        return rigs[model]
    end

    local kind = model:GetAttribute("Kind") or model.Name
    local rig = {
        Model = model,
        Root = root,
        Kind = kind,
        Profile = PROFILES[kind] or PROFILES.ElOyente,
        Settings = MonsterConfig[kind] or {},
        Joints = {},
        Visual = root.CFrame,
        Offset = CFrame.identity,
        LastPosition = root.Position,
        LastLook = root.CFrame.LookVector,
        Speed = 0,
        Gait = 0,
        Phase = 0,
        Clock = 0,
        Elapsed = 0,
        Stomps = 0,
        Random = Random.new(),
        HeadYaw = 0,
        HeadPitch = 0,
        HeadRoll = 0,
        Attack = {Lean = 0, Arms = 0, Out = 0, Crouch = 0, Jaw = 0},
        AttackPhase = "",
        AttackTime = 0,
        Gesture = nil,
        GestureTime = 99,
        Twitch = nil,
        NextTwitch = 1,
        HoldUntil = 0,
        HeldYaw = 0,
        HeldPitch = 0,
        Cock = 0,
        CockUntil = 0,
        StutterUntil = 0,
        NextStutter = 2,
        SnapClock = 0,
        NextScrape = 0,
        TiltGoal = 0.15,
        NextTilt = 0,
    }
    rig.Seed = rig.Random:NextNumber(0, 100)

    local legs, legLength = 0, 0
    local pelvis = Vector3.zero
    for _, joint in ipairs(model:GetDescendants()) do
        if joint:IsA("Motor6D") and joint.Part0 == root and joint.Part1 then
            local part = joint.Part1
            local role = ROLES[part.Name] and part.Name or "Torso"
            local base = joint.C0
            local entry = {
                Joint = joint,
                Base = base,
                Role = role,
                Side = sign(base.Position.X),
                Size = part.Size,
            }
            if role == "Leg" then
                legs += 1
                legLength += part.Size.Y
                pelvis += base.Position
            end
            table.insert(rig.Joints, entry)
            if role == "Head" and not rig.HeadBase then
                rig.HeadBase = base
                rig.Neck = CFrame.new(0, -part.Size.Y * 0.4, 0)
            elseif part.Name == "Torso" and not rig.TorsoBase then
                rig.TorsoBase = base
            end
        end
    end
    rig.LegLength = legs > 0 and legLength / legs or 3
    rig.Pelvis = legs > 0 and pelvis / legs or Vector3.zero
    rig.Neck = rig.Neck or CFrame.identity

    rig.NextTwitch = rig.Random:NextNumber(rig.Profile.TwitchEvery[1], rig.Profile.TwitchEvery[2])
    rig.Connection = model:GetAttributeChangedSignal("GestureCount"):Connect(function()
        rig.Gesture = model:GetAttribute("Gesture")
        rig.GestureTime = 0
    end)

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

-- Movimiento del cuerpo ----------------------------------------------------------

-- La raíz llega a saltos desde el servidor: el cuerpo la sigue con suavidad.
local function smoothRoot(rig, deltaTime, snap)
    local target = rig.Root.CFrame
    local visual = rig.Visual
    if snap or (visual.Position - target.Position).Magnitude > SNAP_DISTANCE then
        visual = target
    else
        local position = visual.Position:Lerp(target.Position, 1 - math.exp(-POSITION_RATE * deltaTime))
        local rotation = (visual - visual.Position):Lerp(target - target.Position, 1 - math.exp(-ROTATION_RATE * deltaTime))
        visual = rotation + position
    end
    rig.Visual = visual
    rig.Offset = target:Inverse() * visual
end

local function updateGait(rig, deltaTime, distance)
    local profile = rig.Profile
    local position = rig.Visual.Position
    local moved = position - rig.LastPosition
    rig.LastPosition = position
    local raw = Vector3.new(moved.X, 0, moved.Z).Magnitude / math.max(deltaTime, 1e-3)
    if raw > 60 then
        raw = 0
    end
    rig.Speed = approach(rig.Speed, raw, 8, deltaTime)

    -- Girar en el lugar también mueve los pies.
    local look = rig.Visual.LookVector
    local turn = math.acos(math.clamp(look:Dot(rig.LastLook), -1, 1)) / math.max(deltaTime, 1e-3)
    rig.LastLook = look
    local drive = rig.Speed + math.min(turn, 3) * 1.2

    -- El Imitador se traba un instante y después recupera el paso de golpe.
    if profile.Jerky and drive > 1 then
        if rig.Clock >= rig.NextStutter then
            rig.StutterUntil = rig.Clock + rig.Random:NextNumber(0.1, 0.25)
            rig.NextStutter = rig.Clock + rig.Random:NextNumber(1.5, 4)
        end
        if rig.Clock < rig.StutterUntil then
            rig.Owed = (rig.Owed or 0) + deltaTime
            return
        end
        deltaTime += rig.Owed or 0
        rig.Owed = 0
    end

    local cycle = rig.LegLength * profile.Stride
    local before = rig.Phase
    rig.Phase = (rig.Phase + TAU * drive / cycle * deltaTime) % TAU
    local goal = drive > 0.25 and math.clamp(drive / profile.FullSpeed, 0, 1.2) or 0
    rig.Gait = approach(rig.Gait, goal, 6, deltaTime)

    -- Cada pie apoya cuando llega adelante (fase π/2 y 3π/2).
    local stepBefore = math.floor((before - math.pi / 2) / math.pi)
    local stepAfter = math.floor((rig.Phase - math.pi / 2) / math.pi)
    if stepBefore ~= stepAfter and rig.Gait > 0.2 and profile.Heavy and distance <= STOMP_RANGE then
        stomp(rig, distance)
    end
end

local function updateAttack(rig, deltaTime)
    local model = rig.Model
    local phase = model:GetAttribute("AttackPhase") or ""
    if phase ~= rig.AttackPhase then
        rig.AttackPhase = phase
        rig.AttackTime = 0
    end
    rig.AttackTime += deltaTime

    local key, rate = "None", 5
    if phase == "Windup" then
        key, rate = "Windup", 2.3 / math.max(rig.Settings.AttackWindup or 0.3, 0.05)
    elseif phase == "Strike" then
        key, rate = "Strike", 30
    elseif phase == "Recover" then
        key, rate = model:GetAttribute("State") == "Stunned" and "Stumble" or "Recover", 4
    end

    local pose = ATTACK_POSES[key]
    local attack = rig.Attack
    for name, value in pairs(pose) do
        attack[name] = approach(attack[name], value, rate, deltaTime)
    end
end

-- Gestos puntuales: devuelven sumandos para cabeza, mandíbula, brazos e inclinación.
-- La tabla se reusa entre cuadros para no generar basura en celulares.
local function gestureOffsets(rig, deltaTime)
    rig.GestureTime += deltaTime
    local t = rig.GestureTime
    local name = rig.Gesture
    local result = rig.GestureResult
    if not result then
        result = {}
        rig.GestureResult = result
    end
    result.Pitch, result.Roll, result.Jaw, result.Out, result.Lean, result.Jitter = 0, 0, 0, 0, 0, 0
    if not name then
        return result
    end

    if name == "Click" and t < 0.4 then
        result.Pitch = 0.22 * math.exp(-t * 12) * math.cos(t * 50)
        result.Roll = 0.12 * math.exp(-t * 10)
    elseif name == "Voice" and t < 2.6 then
        result.Jaw = 0.35 + 0.35 * math.sin(t * 22)
        result.Roll = 0.35
    elseif name == "Scream" and t < 1.3 then
        local k = math.sin(math.clamp(t / 1.3, 0, 1) * math.pi)
        result.Pitch = 0.5 * k
        result.Jaw = 1.1 * k
        result.Out = 0.5 * k
        result.Lean = 0.25 * k
    elseif name == "Roar" and t < 1.7 then
        local k = math.sin(math.clamp(t / 1.7, 0, 1) * math.pi)
        result.Pitch = 0.45 * k
        result.Out = 0.7 * k
        result.Lean = 0.3 * k
    elseif name == "Drop" and t < 0.6 then
        result.Out = 0.9 * math.exp(-t * 5)
        result.Jitter = 1
    elseif name == "Skitter" and t < 1.2 then
        result.Jitter = 2.5
    end
    return result
end

local function updateTwitch(rig, deltaTime, still)
    local profile = rig.Profile
    if rig.Twitch then
        rig.Twitch.Time += deltaTime
        if rig.Twitch.Time > 0.8 then
            rig.Twitch = nil
        end
    elseif still and rig.Clock >= rig.NextTwitch then
        local random = rig.Random
        local roll = random:NextNumber()
        local size = profile.TwitchSize
        rig.Twitch = {
            Role = roll < 0.5 and "Head" or roll < 0.8 and "Arm" or "Torso",
            Side = random:NextNumber() < 0.5 and -1 or 1,
            Angles = Vector3.new(random:NextNumber(-size, size), random:NextNumber(-size, size), random:NextNumber(-size, size)),
            Time = 0,
        }
        rig.NextTwitch = rig.Clock + random:NextNumber(profile.TwitchEvery[1], profile.TwitchEvery[2])
    end
end

local function twitchFor(rig, role, side)
    local twitch = rig.Twitch
    if not twitch or twitch.Role ~= role or (role == "Arm" and twitch.Side ~= side) then
        return CFrame.identity
    end
    -- Sacudón rápido que vuelve solo.
    local k = math.exp(-twitch.Time * 9) * math.min(1, twitch.Time * 40)
    local angles = twitch.Angles * k
    return CFrame.Angles(angles.X, angles.Y, angles.Z)
end

-- Hacia dónde gira la cabeza: el objetivo, el ruido o una mirada curiosa.
local function updateHead(rig, deltaTime, gesture)
    local model = rig.Model
    local profile = rig.Profile
    local behavior = model:GetAttribute("BehaviorState")
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
    yaw = math.clamp(yaw, -1.2, 1.2)
    pitch = math.clamp(pitch, -0.6, 0.5)

    local roll = 0
    if rig.Kind == "ElOyente" then
        -- Ciego: ladea la cabeza para escuchar y la sostiene, cambiando de lado.
        local listening = behavior == "Listen" or behavior == "Search" or rig.Speed < 1
        if rig.Clock >= rig.NextTilt then
            rig.TiltGoal = (listening and 0.55 or 0.15) * (rig.Random:NextNumber() < 0.5 and -1 or 1)
            rig.NextTilt = rig.Clock + rig.Random:NextNumber(1.2, 2.6)
        end
        roll = rig.TiltGoal
        pitch = pitch * 0.4 + (listening and 0.12 or 0)
    end

    if profile.Jerky then
        -- El Imitador sostiene la cabeza y la cambia de golpe, a veces muy torcida.
        if rig.Clock >= rig.HoldUntil then
            rig.HeldYaw = yaw + rig.Random:NextNumber(-0.25, 0.25)
            rig.HeldPitch = pitch + rig.Random:NextNumber(-0.15, 0.15)
            rig.HoldUntil = rig.Clock + rig.Random:NextNumber(0.12, 0.6)
        end
        if rig.Clock >= rig.CockUntil then
            local cocked = rig.Random:NextNumber() < 0.35
            rig.Cock = cocked and rig.Random:NextNumber(0.6, 1.05) * (rig.Random:NextNumber() < 0.5 and -1 or 1) or 0
            rig.CockUntil = rig.Clock + rig.Random:NextNumber(0.8, 2.2)
        end
        yaw, pitch, roll = rig.HeldYaw, rig.HeldPitch, rig.Cock
    end

    local rate = profile.HeadRate
    rig.HeadYaw = approach(rig.HeadYaw, yaw, rate, deltaTime)
    rig.HeadPitch = approach(rig.HeadPitch, pitch + gesture.Pitch - rig.Attack.Lean * 0.3, rate, deltaTime)
    rig.HeadRoll = approach(rig.HeadRoll, roll + gesture.Roll, math.min(rate, 12), deltaTime)
end

local function animate(rig, deltaTime, distance)
    local model = rig.Model
    local profile = rig.Profile
    local state = model:GetAttribute("State")
    rig.Clock += deltaTime

    -- El Quieto observado no respira ni parpadea: la pose queda congelada.
    if state == "Frozen" then
        rig.Visual = rig.Root.CFrame
        rig.Offset = CFrame.identity
        rig.LastPosition = rig.Visual.Position
        rig.SnapClock = 0
        return
    end

    -- Cuando no lo miran, avanza a saltos, como una película a la que le faltan cuadros.
    if profile.StopMotion then
        rig.SnapClock += deltaTime
        if rig.SnapClock < profile.StopMotion then
            return
        end
        deltaTime = rig.SnapClock
        rig.SnapClock = 0
        smoothRoot(rig, deltaTime, true)
        if rig.Speed > 2 and rig.Clock >= rig.NextScrape and distance <= SCRAPE_RANGE then
            rig.NextScrape = rig.Clock + 0.9
            playAt("QuietoScrape", rig.Visual.Position)
        end
    else
        smoothRoot(rig, deltaTime, false)
    end

    rig.Rage = model:GetAttribute("Rage") == true
    updateGait(rig, deltaTime, distance)
    updateAttack(rig, deltaTime)
    local gesture = gestureOffsets(rig, deltaTime)
    updateTwitch(rig, deltaTime, rig.Gait < 0.3 and rig.AttackPhase == "")
    updateHead(rig, deltaTime, gesture)

    local gait = rig.Gait
    local phase = rig.Phase
    local attack = rig.Attack

    -- Cadera: rebote, balanceo lateral hacia el pie de apoyo.
    local wave = math.cos(2 * phase)
    local bob = wave * profile.Bob * gait * 0.5
    if profile.Heavy and wave < 0 then
        bob = wave * profile.Bob * gait
    end
    local sway = math.sin(phase) * profile.Sway * gait
    local hips = CFrame.new(sway * 1.5, bob + attack.Crouch, 0)

    -- Torso: inclinación al correr, contragiro de hombros, ataque y temblor.
    local jitter = 0
    if profile.Crawler then
        jitter = (0.03 + gesture.Jitter * 0.04) * math.noise(rig.Seed, rig.Clock * 9)
    end
    local lean = -profile.Lean * gait + attack.Lean + gesture.Lean
    local twist = math.sin(phase) * profile.Twist * gait + jitter
    local pelvis = rig.Pelvis
    local body = hips * CFrame.new(pelvis) * CFrame.Angles(lean, twist, -sway + jitter) * CFrame.new(-pelvis)

    -- Respiración: más visible quieta; agitada en furia.
    local breath, amount = 0, 0
    if profile.Breath > 0 then
        local period = profile.Breath / (rig.Rage and 1.6 or 1)
        breath = math.sin(rig.Clock * TAU / period)
        amount = profile.BreathAmount * (1.5 - gait * 0.5) * (rig.Rage and 1.6 or 1)
    end
    local torsoPose = CFrame.new(0, breath * amount, 0) * CFrame.Angles(-breath * amount * 0.6, 0, 0)
        * twitchFor(rig, "Torso", 0)

    local torsoBase = rig.TorsoBase or CFrame.identity
    local torsoDelta = body * torsoBase * torsoPose * torsoBase:Inverse()

    local headBase = rig.HeadBase or CFrame.identity
    local neck = rig.Neck
    local headPose = neck * CFrame.fromEulerAnglesYXZ(rig.HeadPitch, rig.HeadYaw, rig.HeadRoll) * neck:Inverse()
        * twitchFor(rig, "Head", 0)
    local headDelta = torsoDelta * headBase * headPose * headBase:Inverse()

    local offset = rig.Offset
    local legSwing = profile.LegSwing * gait
    local armSwing = profile.ArmSwing * gait
    for _, entry in ipairs(rig.Joints) do
        local role = entry.Role
        local side = entry.Side
        local c0
        if role == "Leg" then
            local legPhase = phase + (side > 0 and math.pi or 0)
            local swing = math.sin(legPhase) * legSwing
            -- La pierna que avanza se levanta un poco (rodilla).
            local lift = math.max(0, math.cos(legPhase)) * 0.06 * gait * rig.LegLength
            local splay = profile.Crawler and side * 0.12 or 0
            c0 = hips * entry.Base * CFrame.new(0, lift, 0) * CFrame.Angles(swing, 0, splay)
        elseif role == "Arm" then
            -- Contrabalanceo: cada brazo va al revés que la pierna de su lado.
            local armPhase = phase + (side < 0 and math.pi or 0)
            if profile.Heavy then
                -- Brazos pesados que cuelgan y siguen al cuerpo con retraso.
                armPhase -= 0.7
            end
            local swing = math.sin(armPhase) * armSwing + attack.Arms
            local out = attack.Out + gesture.Out
            if profile.Crawler then
                out += 0.25 + 0.15 * math.cos(armPhase) * gait
            end
            local hang = breath * amount * 0.4
            c0 = torsoDelta * entry.Base * CFrame.new(0, hang, 0) * CFrame.Angles(swing, 0, side * out)
                * twitchFor(rig, "Arm", side)
        elseif role == "Head" then
            c0 = torsoDelta * entry.Base * headPose
        elseif role == "Eye" then
            c0 = headDelta * entry.Base
        elseif role == "Jaw" then
            c0 = headDelta * entry.Base * CFrame.Angles(attack.Jaw + gesture.Jaw, 0, 0)
        else
            c0 = torsoDelta * entry.Base
        end
        entry.Joint.C0 = offset * c0
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
