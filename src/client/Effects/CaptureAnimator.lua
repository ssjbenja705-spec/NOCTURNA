-- Animación de la captura en cada cliente (víctima y compañeros ven lo mismo).
-- Mientras el modelo tiene AnimOverride = "Capture", MonsterAnimator deja de
-- escribir sus articulaciones y las mueve este módulo, a partir de lo que el
-- servidor publica en el modelo (CapturePhase, CaptureVictim, CaptureProgress).
--
-- Cada criatura agarra a su manera, respetando su anatomía:
--   El Imitador: la boca roja es una pieza propia (Jaw): se abre de a poco, con
--     baba que gotea, hilos de saliva entre los labios y respiración húmeda; la
--     cabeza se acerca a la cara de la víctima como si la fuera a devorar.
--   El Oyente: su sonrisa está tallada en la cabeza (no se abre). Pega la cabeza a
--     la víctima, la ladea para escucharla y chasquea cada vez más rápido; babea.
--   El Quieto: maniquí sin boca. Le aprieta el cuello con tirones de muñeco
--     articulado: la cabeza gira a saltos, imposible.
--   El Trepador: sin boca. Se encorva desde arriba y levanta a la víctima.
--   El Coloso: sin boca. La aprieta en su puño con pulsos que crujen.
-- Gancho: si una criatura trae una pieza Jaw o Tongue (malla futura), se abre y
-- asoma sola. Una textura de saliva se puede poner en CaptureAnimator.SalivaTexture.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CaptureConfig = require(Shared.Config.CaptureConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local AudioController = require(script.Parent.AudioController)

local VISIBLE_RANGE = 120
local SALIVA_COLOR = Color3.fromRGB(214, 220, 200)

local CaptureAnimator = {
    -- Sin textura propia de saliva: se usa la partícula suave de Roblox.
    SalivaTexture = "rbxasset://textures/particles/smoke_main.dds",
}
local sessions = {}
local watched = {}
local random = Random.new()

local function ease(alpha)
    alpha = math.clamp(alpha, 0, 1)
    return alpha * alpha * (3 - 2 * alpha)
end

local function sign(value)
    return value < 0 and -1 or 1
end

-- Articulaciones con su C0 original. Si MonsterAnimator ya las midió, se usan
-- las suyas (son las de fábrica); si no, se miden acá la primera vez.
local baseCache = {}

local function jointsOf(model)
    local cached = baseCache[model]
    if cached then
        return cached
    end
    local root = model:FindFirstChild("HumanoidRootPart")
    if not root then
        return nil
    end

    local known = {}
    pcall(function()
        local animator = require(script.Parent.MonsterAnimator)
        local rig = animator.Rigs()[model]
        for _, entry in ipairs(rig and rig.Joints or {}) do
            known[entry.Joint] = entry.Base
        end
    end)

    local joints = {}
    for _, joint in ipairs(model:GetDescendants()) do
        if joint:IsA("Motor6D") and joint.Part0 == root and joint.Part1 then
            local part = joint.Part1
            local base = known[joint] or joint.C0
            table.insert(joints, {
                Joint = joint,
                Part = part,
                Base = base,
                Role = part.Name,
                Side = sign(base.Position.X),
            })
        end
    end
    baseCache[model] = joints
    return joints
end

local function findJoint(joints, role)
    for _, entry in ipairs(joints) do
        if entry.Role == role then
            return entry
        end
    end
    return nil
end

-- Efectos -----------------------------------------------------------------------

local function attachment(part, name, position)
    local item = Instance.new("Attachment")
    item.Name = name
    item.Position = position
    item.Parent = part
    return item
end

local function droolEmitter(parent, rate)
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "CaptureDrool"
    emitter.Texture = CaptureAnimator.SalivaTexture
    emitter.Color = ColorSequence.new(SALIVA_COLOR)
    emitter.LightEmission = 0.15
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.25),
        NumberSequenceKeypoint.new(1, 0.9),
    })
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.07),
        NumberSequenceKeypoint.new(1, 0.025),
    })
    emitter.Lifetime = NumberRange.new(0.5, 1)
    emitter.Speed = NumberRange.new(0.3, 1.2)
    emitter.SpreadAngle = Vector2.new(18, 18)
    emitter.Acceleration = Vector3.new(0, -26, 0)
    emitter.Drag = 1.5
    emitter.Rate = rate
    emitter.Parent = parent
    return emitter
end

local function strand(from, to, offset)
    local beam = Instance.new("Beam")
    beam.Name = "CaptureStrand"
    beam.Attachment0 = from
    beam.Attachment1 = to
    beam.Color = ColorSequence.new(SALIVA_COLOR)
    beam.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.35),
        NumberSequenceKeypoint.new(0.5, 0.55),
        NumberSequenceKeypoint.new(1, 0.35),
    })
    beam.LightEmission = 0.1
    beam.Width0 = 0.045
    beam.Width1 = 0.03
    beam.CurveSize0 = -0.25 + offset
    beam.CurveSize1 = 0.25
    beam.Segments = 8
    beam.FaceCamera = true
    beam.Parent = from
    return beam
end

-- Arma lo que la criatura necesita: luz de recorte (para que la cara se lea en la
-- oscuridad), baba y saliva si tiene boca, y el polvo del golpe.
local function buildEffects(session)
    local model = session.Model
    local head = model:FindFirstChild("Head")
    local created = session.Created
    if not head then
        return
    end

    local light = Instance.new("PointLight")
    light.Name = "CaptureRim"
    light.Brightness = 0.9
    light.Range = 8
    light.Shadows = false
    light.Color = session.Profile.Mouth == "Jaw" and Color3.fromRGB(255, 120, 110) or Color3.fromRGB(176, 186, 210)
    light.Parent = head
    table.insert(created, light)

    local size = head.Size
    local jaw = model:FindFirstChild("Jaw")
    if jaw and jaw:IsA("BasePart") then
        local top = attachment(head, "CaptureLipTop", Vector3.new(0, -size.Y * 0.3, -size.Z * 0.42))
        local jawSize = jaw.Size
        local bottomLeft = attachment(jaw, "CaptureLipLeft", Vector3.new(-jawSize.X * 0.25, -jawSize.Y * 0.35, -jawSize.Z * 0.3))
        local bottomRight = attachment(jaw, "CaptureLipRight", Vector3.new(jawSize.X * 0.25, -jawSize.Y * 0.35, -jawSize.Z * 0.3))
        local drip = attachment(jaw, "CaptureDrip", Vector3.new(0, -jawSize.Y * 0.5, -jawSize.Z * 0.3))
        table.insert(created, top)
        table.insert(created, bottomLeft)
        table.insert(created, bottomRight)
        table.insert(created, drip)
        session.Strands = {strand(top, bottomLeft, -0.1), strand(top, bottomRight, 0.12)}
        session.Drool = droolEmitter(drip, 10)
    elseif session.Profile.Mouth == "Sealed" then
        -- La boca está tallada en la malla de la cabeza: gotea por la comisura.
        local drip = attachment(head, "CaptureDrip", Vector3.new(0, -size.Y * 0.38, -size.Z * 0.44))
        table.insert(created, drip)
        session.Drool = droolEmitter(drip, 5)
    end

    local impact = Instance.new("ParticleEmitter")
    impact.Name = "CaptureImpact"
    impact.Color = ColorSequence.new(Color3.fromRGB(200, 196, 186))
    impact.LightEmission = 0.4
    impact.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.35),
        NumberSequenceKeypoint.new(1, 0),
    })
    impact.Transparency = NumberSequence.new(0.2, 1)
    impact.Lifetime = NumberRange.new(0.25, 0.5)
    impact.Speed = NumberRange.new(8, 15)
    impact.SpreadAngle = Vector2.new(180, 180)
    impact.Rate = 0
    impact.Parent = head
    table.insert(created, impact)
    session.Impact = impact
end

-- Poses ---------------------------------------------------------------------------

-- Pose de la criatura en este instante. Ángulos en radianes; Lean negativo es
-- hacia adelante, Arms positivo hacia adelante, Out hacia afuera.
local function poseFor(session, now)
    local kind = session.Kind
    local phase = session.Phase
    local t = now - session.PhaseStart
    local since = now - session.Started
    local grab = phase == "Grab" and ease(t / session.Profile.GrabTime) or 1
    local danger = 0
    if session.Deadline and session.TimeLimit and session.TimeLimit > 0 then
        danger = 1 - math.clamp((session.Deadline - now) / session.TimeLimit, 0, 1)
    end
    if phase == "Fail" then
        danger = 1
    end
    local jerk = session.Jerk
    local pose = {
        Lean = -0.3 * grab, Twist = 0, Roll = 0, Crouch = 0, Lift = 0,
        HeadPitch = 0, HeadYaw = 0, HeadRoll = 0, HeadPush = 0,
        Arms = 1.2 * grab, Out = -0.3 * grab, ArmShake = jerk * 0.15,
        Legs = 0, Splay = 0, Gape = 0,
    }

    if kind == "ElImitador" then
        pose.Lean = -0.35 * grab - 0.18 * danger
        pose.HeadPitch = 0.3 * grab - 0.5 * danger
        pose.HeadPush = 0.25 * grab + 0.35 * danger
        pose.Gape = 0.25 * grab + 0.8 * grab * (0.4 + 0.6 * danger) + math.sin(since * 3) * 0.06
        -- Se mueve a sacudones, como en el resto del juego.
        local stutter = math.floor(since * 7)
        pose.HeadRoll = (stutter % 3 - 1) * 0.08
        pose.Arms = 1.4 * grab
        pose.Out = -0.28 * grab
    elseif kind == "ElOyente" then
        pose.Lean = -0.32 * grab
        pose.HeadPush = 0.35 * grab
        pose.HeadPitch = -0.2 * grab
        pose.HeadRoll = math.sin(since * 1.7) * 0.35 * grab
        pose.HeadYaw = session.ClickTwitch
        pose.Arms = 1.05 * grab
        pose.Out = -0.48 * grab + math.sin(since * 2.2) * 0.05
        pose.Gape = 0.2 + 0.6 * danger
    elseif kind == "ElQuieto" then
        -- Cuadro a cuadro: la pose salta de una posición a otra.
        local frame = math.floor(since / 0.14)
        if frame ~= session.QuietoFrame then
            session.QuietoFrame = frame
            if random:NextNumber() < 0.22 + danger * 0.3 then
                session.QuietoYaw = random:NextNumber(-1.3, 1.3)
                session.QuietoRoll = random:NextNumber(-0.6, 0.6)
                session.Snaps += 1
                if session.Snaps % 3 == 0 then
                    session.PlaySound("QuietoScrape")
                end
            end
        end
        pose.Lean = -0.2 * grab
        pose.HeadYaw = session.QuietoYaw * grab
        pose.HeadRoll = session.QuietoRoll * grab
        pose.Arms = 1.5 * grab
        pose.Out = -0.5 * grab
        pose.Twist = (frame % 5 == 0) and 0.12 or 0
    elseif kind == "ElTrepador" then
        pose.Lean = -0.6 * grab
        pose.HeadPitch = -0.55 * grab
        pose.HeadPush = 0.2 * grab
        pose.Arms = 2.3 * grab
        pose.Out = -0.3 * grab
        pose.Splay = 0.35 * grab
        pose.Lift = math.sin(since * 2) * 0.12 * grab
    elseif kind == "ElColoso" then
        local pulse = math.max(0, math.sin(since * math.pi / 0.9)) ^ 6
        if pulse > 0.8 and not session.Squeezing then
            session.Squeezing = true
            session.PlaySound("CaptureSqueeze")
        elseif pulse < 0.2 then
            session.Squeezing = false
        end
        pose.Lean = -0.22 * grab - 0.1 * pulse
        pose.HeadPitch = -0.35 * grab
        pose.Arms = 1.35 * grab
        pose.Out = -0.55 * grab - 0.15 * pulse
        pose.Crouch = -0.15 * grab
    end

    if phase == "Fail" then
        local climax = ease(t / CaptureConfig.FailTime)
        pose.Gape += 0.5 * climax
        pose.HeadPush += 0.5 * climax
        pose.Lean -= 0.2 * climax
        pose.Out -= 0.15 * climax
    elseif phase == "Release" then
        -- El contragolpe: la cabeza salta hacia atrás y los brazos se abren.
        local recoil = 1 - ease(t / CaptureConfig.ReleaseTime)
        pose.Lean = 0.45 * recoil
        pose.HeadPitch = 0.6 * recoil
        pose.HeadPush = -0.3 * recoil
        pose.Arms = -0.3 * recoil
        pose.Out = 0.8 * recoil
        pose.Gape = 0.4 * recoil
    end
    return pose
end

local function applyPose(session, pose)
    local joints = session.Joints
    local pivot = session.Pivot
    local torso = CFrame.new(0, pose.Crouch + pose.Lift, 0) * CFrame.new(pivot)
        * CFrame.Angles(pose.Lean, pose.Twist, pose.Roll) * CFrame.new(-pivot)

    local headEntry = session.HeadEntry
    local headDelta = torso
    if headEntry then
        local neck = session.Neck
        local posed = torso * headEntry.Base * CFrame.new(0, 0, -pose.HeadPush) * neck
            * CFrame.Angles(pose.HeadPitch, pose.HeadYaw, pose.HeadRoll) * neck:Inverse()
        headDelta = posed * headEntry.Base:Inverse()
    end

    for _, entry in ipairs(joints) do
        local role = entry.Role
        local side = entry.Side
        local c0
        if role == "Head" then
            c0 = headDelta * entry.Base
        elseif role == "Jaw" then
            c0 = headDelta * entry.Base * CFrame.Angles(math.max(0, pose.Gape), 0, 0)
        elseif role == "Tongue" then
            c0 = headDelta * entry.Base * CFrame.new(0, 0, -math.max(0, pose.Gape) * 0.4)
        elseif role == "Eye" then
            c0 = headDelta * entry.Base
        elseif role == "Arm" then
            local shake = pose.ArmShake * math.sin(os.clock() * 40 + side)
            c0 = torso * entry.Base * CFrame.Angles(pose.Arms + shake, 0, side * pose.Out)
        elseif role == "Leg" then
            c0 = entry.Base * CFrame.Angles(pose.Legs, 0, side * pose.Splay)
        else
            c0 = torso * entry.Base
        end
        entry.Joint.C0 = c0
    end
end

-- La víctima se retuerce en el agarre (en todas las pantallas). El servidor la
-- deja anclada en CaptureHold; acá sólo se le suma el temblor.
local function shakeVictim(session, now)
    if not session.Victim then
        local victimId = session.Model:GetAttribute("CaptureVictim")
        session.Victim = type(victimId) == "number" and Players:GetPlayerByUserId(victimId) or nil
    end
    local victim = session.Victim
    local character = victim and victim.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local hold = character and character:GetAttribute("CaptureHold")
    if not root or typeof(hold) ~= "CFrame" or not root.Anchored then
        return
    end
    local power = 0.35 + session.Jerk * 1.2
    root.CFrame = hold * CFrame.Angles(
        math.sin(now * 13) * 0.04 * power,
        math.sin(now * 9.3) * 0.07 * power,
        math.sin(now * 11.1) * 0.05 * power
    )
end

local function updateSounds(session, now)
    local profile = session.Profile
    if session.Phase ~= "Grab" and session.Phase ~= "Struggle" and session.Phase ~= "Fail" then
        return
    end
    if now < session.NextSound then
        return
    end
    local kind = session.Kind
    if kind == "ElOyente" then
        -- Chasquidos cada vez más seguidos mientras escucha a su presa.
        session.PlaySound("OyenteClick")
        session.ClickTwitch = random:NextNumber(-0.15, 0.15)
        session.NextSound = now + 0.9 - 0.6 * session.Danger
    elseif profile.Mouth == "Jaw" then
        session.PlaySound("WetBreath")
        if random:NextNumber() < 0.4 then
            session.PlaySound("Drool")
        end
        session.NextSound = now + random:NextNumber(1, 1.5) - 0.4 * session.Danger
    elseif kind == "ElTrepador" then
        session.PlaySound("TrepadorSkitter")
        session.NextSound = now + random:NextNumber(0.8, 1.6)
    elseif kind == "ElColoso" then
        session.PlaySound("WetBreath")
        session.NextSound = now + random:NextNumber(1.6, 2.2)
    else
        session.NextSound = now + 1
    end
end

local function updateEffects(session)
    local danger = session.Danger
    if session.Drool then
        session.Drool.Rate = (session.Phase == "Release") and 0 or (6 + 18 * danger)
    end
    for _, beam in ipairs(session.Strands or {}) do
        -- Los hilos se estiran y se cortan cuando la boca se abre del todo.
        beam.Enabled = session.Phase ~= "Release" and session.Gape < 1.15
    end
end

-- Sesiones -----------------------------------------------------------------------

local function stopSession(model)
    local session = sessions[model]
    if not session then
        return
    end
    sessions[model] = nil
    for _, item in ipairs(session.Created) do
        item:Destroy()
    end
    for _, beam in ipairs(session.Strands or {}) do
        beam:Destroy()
    end
    if session.Drool then
        session.Drool:Destroy()
    end
    -- Vuelve a la pose de fábrica; MonsterAnimator retoma desde ahí.
    for _, entry in ipairs(session.Joints) do
        if entry.Joint.Parent then
            entry.Joint.C0 = entry.Base
        end
    end
end

local function startSession(model)
    if sessions[model] then
        return sessions[model]
    end
    local joints = jointsOf(model)
    if not joints then
        return nil
    end
    local kind = model:GetAttribute("Kind") or model.Name
    local profile = CaptureConfig.Creatures[kind] or CaptureConfig.Creatures.ElOyente
    local now = os.clock()

    local headEntry = findJoint(joints, "Head")
    local pivot = Vector3.zero
    local legs = 0
    for _, entry in ipairs(joints) do
        if entry.Role == "Leg" then
            pivot += entry.Base.Position
            legs += 1
        end
    end
    pivot = legs > 0 and pivot / legs or Vector3.zero

    local session
    session = {
        Model = model,
        Kind = kind,
        Profile = profile,
        Joints = joints,
        HeadEntry = headEntry,
        Neck = headEntry and CFrame.new(0, -headEntry.Part.Size.Y * 0.4, 0) or CFrame.identity,
        Pivot = pivot,
        Phase = model:GetAttribute("CapturePhase") or "Grab",
        Started = now,
        PhaseStart = now,
        Jerk = 0,
        Danger = 0,
        Gape = 0,
        ClickTwitch = 0,
        QuietoYaw = 0,
        QuietoRoll = 0,
        Snaps = 0,
        NextSound = now + 0.3,
        Created = {},
        PlaySound = function(name)
            local head = model:FindFirstChild("Head") or model.PrimaryPart
            if head then
                AudioController.PlayAt(name, head.Position)
            end
        end,
    }
    local victimId = model:GetAttribute("CaptureVictim")
    session.Victim = type(victimId) == "number" and Players:GetPlayerByUserId(victimId) or nil
    sessions[model] = session
    pcall(buildEffects, session)
    return session
end

local function onPhaseChanged(model)
    local session = sessions[model]
    if not session then
        return
    end
    local phase = model:GetAttribute("CapturePhase")
    if phase and phase ~= session.Phase then
        session.Phase = phase
        session.PhaseStart = os.clock()
        if phase == "Release" and session.Impact then
            session.Impact:Emit(26)
            session.PlaySound("CaptureHit")
        elseif phase == "Fail" and session.Kind == "ElColoso" then
            session.PlaySound("ColosoRoar")
        elseif phase == "Fail" then
            session.PlaySound("CaptureDevour")
        end
    end
end

local function refresh(model)
    if model:GetAttribute("AnimOverride") == "Capture" then
        startSession(model)
        onPhaseChanged(model)
    else
        stopSession(model)
    end
end

local function watch(model)
    if watched[model] then
        return
    end
    watched[model] = {
        model:GetAttributeChangedSignal("AnimOverride"):Connect(function()
            refresh(model)
        end),
        model:GetAttributeChangedSignal("CapturePhase"):Connect(function()
            onPhaseChanged(model)
        end),
    }
    refresh(model)
end

local function unwatch(model)
    stopSession(model)
    baseCache[model] = nil
    for _, connection in ipairs(watched[model] or {}) do
        connection:Disconnect()
    end
    watched[model] = nil
end

function CaptureAnimator.Update(deltaTime)
    local now = os.clock()
    local camera = workspace.CurrentCamera
    local origin = camera and camera.CFrame.Position
    for model, session in pairs(sessions) do
        if not model.Parent then
            unwatch(model)
        else
            session.Jerk = math.max(0, session.Jerk - deltaTime * 3)
            if session.Deadline and session.TimeLimit and session.TimeLimit > 0 then
                session.Danger = 1 - math.clamp((session.Deadline - now) / session.TimeLimit, 0, 1)
            end
            local root = model.PrimaryPart
            local near = not origin or not root or (root.Position - origin).Magnitude <= VISIBLE_RANGE
            if near then
                local ok, err = pcall(function()
                    local pose = poseFor(session, now)
                    session.Gape = pose.Gape
                    applyPose(session, pose)
                    shakeVictim(session, now)
                    updateSounds(session, now)
                    updateEffects(session)
                end)
                if not ok and not session.Warned then
                    session.Warned = true
                    warn("[NOCTURNA] Falló la animación de captura: " .. tostring(err))
                end
            end
        end
    end
end

function CaptureAnimator.Sessions()
    return sessions
end

function CaptureAnimator.Start()
    CollectionService:GetInstanceAddedSignal("NocturnaMonster"):Connect(function(model)
        task.spawn(watch, model)
    end)
    CollectionService:GetInstanceRemovedSignal("NocturnaMonster"):Connect(unwatch)
    for _, model in ipairs(CollectionService:GetTagged("NocturnaMonster")) do
        task.spawn(watch, model)
    end

    -- El ritmo del forcejeo (cada tecla de la víctima) sacude a la criatura y a la
    -- víctima en todas las pantallas; el plazo acerca el "a punto de devorar".
    Remotes.OnClient("CaptureUpdate", function(data)
        if typeof(data) ~= "table" or typeof(data.Monster) ~= "Instance" then
            return
        end
        local session = sessions[data.Monster]
        if not session then
            return
        end
        if type(data.TimeLeft) == "number" and type(data.TimeLimit) == "number" then
            session.Deadline = os.clock() + data.TimeLeft
            session.TimeLimit = data.TimeLimit
        end
        if data.Event == "Progress" then
            session.Jerk = math.min(1.5, session.Jerk + (data.Result == "Wrong" and 0.4 or 0.8))
        end
    end)

    RunService.RenderStepped:Connect(CaptureAnimator.Update)
end

return CaptureAnimator
