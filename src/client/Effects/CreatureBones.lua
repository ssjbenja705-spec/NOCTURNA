-- Esqueleto con piel (huesos) de una criatura: cuando MonsterFactory pudo usar
-- ServerStorage.NocturnaModels.<Criatura>Rig, la criatura es una sola malla con
-- piel y huesos (ver assets/models/rigged/README.md) y acá se mueven los huesos
-- escribiendo Bone.Transform (sólo en este cliente; no se replica).
--
-- Todo se calcula en el espacio de la raíz (HumanoidRootPart) y relativo a la
-- pose de descanso medida de los propios huesos, así no importa cómo orientó los
-- ejes de cada hueso el importador de Roblox. Cada hueso gira con un ángulo en
-- ejes de la criatura (X costado, Y arriba, Z atrás) que se suma al de su padre.
--
--   * Piernas: dos huesos con IK. El pie apoyado queda clavado en el mundo
--     mientras el cuerpo avanza; al despegar hace un arco hasta donde va a pisar
--     (adelante, según la velocidad real), la rodilla se dobla sola hacia su lado.
--   * Brazos: péndulos con codo que se dobla, mano y dedos que se cierran.
--     En El Trepador las patas delanteras también pisan con IK.
--   * Columna: la cadera gira con las piernas y los hombros al revés; la
--     inclinación y el balanceo se reparten entre las vértebras.
--   * Cuello y cabeza (mirada), mandíbula, placas sueltas y abdomen.
--
-- MonsterAnimator decide la pose (estados, paso, ataque, gestos) y llama a
-- Animate; CaptureAnimator llama a Capture con su propia pose. Las piezas
-- invisibles Head y Jaw (para la cámara y los efectos) siguen a sus huesos.
local CreatureMotion = require(script.Parent:WaitForChild("CreatureMotion"))

local Approach = CreatureMotion.Approach
local Spring = CreatureMotion.Spring
local Smooth = CreatureMotion.Smoothstep

local TAU = math.pi * 2
local ZERO = Vector3.zero
local UP = Vector3.yAxis
local IDENTITY = CFrame.identity
-- Si el pie apoyado queda más lejos que esto (en largos de pata), se vuelve a apoyar.
local REPLANT = 1.7

local CreatureBones = {}
local cache = setmetatable({}, {__mode = "k"})

local LEG_CHAIN = {"Thigh", "Shin", "Foot", "Toe"}
local ARM_CHAIN = {"UpperArm", "Forearm", "Hand", "Fingers1", "Fingers2"}

-- Pose de descanso de cada hueso en el espacio de la raíz -------------------------

local function rotationOf(cframe)
    return cframe - cframe.Position
end

-- Base ortonormal: x a lo largo de `along`, y hacia `toward` (perpendicular).
local function basis(along, toward)
    local x = along
    local y = toward - x * x:Dot(toward)
    if y.Magnitude < 1e-5 then
        y = math.abs(x.Y) < 0.9 and UP or Vector3.xAxis
        y = y - x * x:Dot(y)
    end
    y = y.Unit
    return CFrame.fromMatrix(ZERO, x, y, x:Cross(y))
end

-- Dónde está cada parte del cuerpo respecto de la raíz. El servidor lo deja en el
-- atributo RigOffset (las partes van soldadas a la raíz).
local function partOffset(part, root)
    local stored = part:GetAttribute("RigOffset")
    if typeof(stored) == "CFrame" then
        return stored
    end
    return root.CFrame:Inverse() * part.CFrame
end

local function collect(body, root)
    local nodes, byName = {}, {}
    local function visit(bone, parentNode, partBase)
        local node: {[string]: any} = {
            Name = bone.Name,
            Bone = bone,
            ParentNode = parentNode,
            PartBase = partBase,
            Local = bone.CFrame,
            Q = IDENTITY,
            D = IDENTITY,
            P = ZERO,
            R = IDENTITY,
            From = nil,
        }
        node.Rest = (parentNode and parentNode.Rest or partBase) * node.Local
        node.RestPos = node.Rest.Position
        node.RestRot = rotationOf(node.Rest)
        table.insert(nodes, node)
        if not byName[bone.Name] then
            byName[bone.Name] = node
        end
        for _, child in ipairs(bone:GetChildren()) do
            if child:IsA("Bone") then
                visit(child, node, nil)
            end
        end
    end
    for _, part in ipairs(body:GetDescendants()) do
        if part:IsA("BasePart") then
            local base = partOffset(part, root)
            for _, child in ipairs(part:GetChildren()) do
                if child:IsA("Bone") then
                    visit(child, nil, base)
                end
            end
        end
    end
    return nodes, byName
end

-- Extremidades ----------------------------------------------------------------------

local function newLimb(rig, role, side, names, clavicle)
    local chain = {}
    for _, name in ipairs(names) do
        local node = rig.ByName[name]
        if not node then
            break
        end
        table.insert(chain, node)
    end
    if #chain < 3 then
        return nil
    end
    local upper, lower, last = chain[1], chain[2], chain[3]
    local a0 = lower.RestPos - upper.RestPos
    local b0 = last.RestPos - lower.RestPos
    local chord = last.RestPos - upper.RestPos
    -- Hacia dónde se dobla: lo que la malla ya trae doblado; si viene derecha,
    -- rodillas adelante y codos atrás.
    local bend = a0 - chord.Unit * a0:Dot(chord.Unit)
    local pole
    if bend.Magnitude > 0.03 * a0.Magnitude then
        pole = bend.Unit
    else
        pole = role == "Leg" and Vector3.new(0, 0, -1) or Vector3.new(0, 0, 1)
    end
    -- Altura del tobillo (o la muñeca, en patas delanteras) sobre el piso.
    local lowest = last.RestPos.Y
    for index = 3, #chain do
        lowest = math.min(lowest, chain[index].RestPos.Y)
    end
    local tip = chain[#chain]
    local tipBone = tip.Bone
    -- Dónde apoya en el paso: debajo de donde la tiene en reposo; si la malla la
    -- trae muy atrás o muy adelante de la cadera (casi estirada, como las patas de
    -- atrás de El Trepador), se acerca a la mitad para que el paso no la estire.
    local home = last.RestPos
    local reachZ = home.Z - upper.RestPos.Z
    if math.abs(reachZ) > 0.25 * (a0.Magnitude + b0.Magnitude) then
        home = Vector3.new(home.X, home.Y, upper.RestPos.Z + reachZ * 0.5)
    end
    local limb: {[string]: any} = {
        Role = role,
        Side = side,
        Chain = chain,
        Clavicle = clavicle and rig.ByName[clavicle] or nil,
        Upper = upper,
        Lower = lower,
        End = last,
        L1 = a0.Magnitude,
        L2 = b0.Magnitude,
        Pole = pole,
        Home = home,
        Length = math.max(upper.RestPos.Y - math.min(lowest, tip.RestPos.Y), a0.Magnitude + b0.Magnitude, 0.5),
        TipName = tipBone.Name,
        -- Mismos campos que las patas de piezas (MonsterAnimator los usa igual).
        Fwd = 0, FwdVel = 0, Out = 0, OutVel = 0, Elbow = 0.25, ElbowVel = 0,
        LastU = 0, Lift = 0, PhaseOffset = 0, DutyBias = 0, Swing = 0, IsFoot = false,
        Plant = nil, LiftFrom = nil, Stance = true, Curl = 0.2,
    }
    return limb
end

local function buildLimbs(rig, quadruped)
    rig.Legs, rig.Arms, rig.Feet = {}, {}, {}
    for _, sideName in ipairs({"Left", "Right"}) do
        local side = sideName == "Left" and -1 or 1
        local legNames, armNames = {}, {}
        for index, name in ipairs(LEG_CHAIN) do
            legNames[index] = sideName .. name
        end
        for index, name in ipairs(ARM_CHAIN) do
            armNames[index] = sideName .. name
        end
        local arm = newLimb(rig, "Arm", side, armNames, sideName .. "Clavicle")
        local leg = newLimb(rig, "Leg", side, legNames, nil)
        if arm then
            table.insert(rig.Arms, arm)
            if quadruped then
                arm.IsFoot = true
                table.insert(rig.Feet, arm)
            end
        end
        if leg then
            leg.IsFoot = true
            table.insert(rig.Legs, leg)
            table.insert(rig.Feet, leg)
        end
    end
end

-- Piezas invisibles (Head, Jaw) que siguen a un hueso: las usan la cámara de la
-- captura y los efectos de la boca.
local function findProxies(rig, model)
    rig.Proxies = {}
    for _, joint in ipairs(model:GetChildren()) do
        if joint:IsA("BasePart") then
            local motor = joint:FindFirstChildWhichIsA("Motor6D")
            local boneName = motor and motor:GetAttribute("BoneProxy")
            local node = boneName and rig.ByName[boneName]
            if node then
                local offset = motor:GetAttribute("ProxyOffset")
                if typeof(offset) ~= "CFrame" then
                    offset = node.Rest:Inverse() * motor.C0
                end
                table.insert(rig.Proxies, {Joint = motor, Node = node, Offset = offset})
            end
        end
    end
end

-- El modelo es una criatura con huesos.
function CreatureBones.IsRig(model)
    return model:GetAttribute("BoneRig") == true
end

-- Esqueleto de la criatura (uno por modelo, compartido por los animadores).
function CreatureBones.Get(model, style)
    local existing = cache[model]
    if existing then
        return existing
    end
    if not CreatureBones.IsRig(model) then
        return nil
    end
    local root = model:FindFirstChild("HumanoidRootPart")
    local body = model:FindFirstChild("Body")
    if not (root and body) then
        return nil
    end
    local nodes, byName = collect(body, root)
    if not (byName.Hips and byName.LeftThigh and byName.RightThigh) then
        return nil
    end
    local rig: {[string]: any} = {
        Model = model,
        Root = root,
        Body = body,
        Nodes = nodes,
        ByName = byName,
        Resume = 1,
        Started = false,
        Quadruped = style and style.Quadruped == true or false,
        Writes = 0,
        Frame = 0,
        AbdomenVel = 0,
        Abdomen = 0,
    }
    for _, node in ipairs(nodes) do
        node.Rig = rig
    end
    buildLimbs(rig, rig.Quadruped)
    findProxies(rig, model)

    local legLength = 0
    for _, leg in ipairs(rig.Legs) do
        legLength += leg.Length
    end
    rig.LegLength = #rig.Legs > 0 and legLength / #rig.Legs or 3
    rig.Pelvis = byName.Hips.RestPos
    rig.HeadBase = byName.Head and CFrame.new(byName.Head.RestPos) or nil
    rig.HasJaw = byName.Jaw ~= nil
    cache[model] = rig
    return rig
end

-- Escritura ---------------------------------------------------------------------------

-- FK: el hueso gira `q` (ejes de la criatura) además de lo que giró su padre.
local function fk(node, q)
    node.Set = node.Rig.Frame
    local parent = node.ParentNode
    if parent then
        node.D = parent.D * q
        node.P = parent.P + parent.D * (node.RestPos - parent.RestPos)
    else
        node.D = q
        node.P = node.RestPos
    end
end

local function resetPose(rig)
    rig.Frame += 1
    for _, node in ipairs(rig.Nodes) do
        fk(node, IDENTITY)
    end
end

-- Los huesos que nadie movió en este cuadro (dedos, huesos extra del modelo)
-- acompañan a su padre. Los nodos están en orden: cada padre antes que sus hijos.
local function settleRest(rig)
    local frame = rig.Frame
    for _, node in ipairs(rig.Nodes) do
        if node.Set ~= frame then
            fk(node, IDENTITY)
        end
    end
end

local function spinesOf(rig)
    local spines = rig.Spines
    if not spines then
        spines = {}
        for index = 1, 4 do
            local node = rig.ByName["Spine" .. index]
            if node then
                table.insert(spines, node)
            end
        end
        rig.Spines = spines
    end
    return spines
end

-- Lleva la pose (espacio de la criatura) a Bone.Transform. `offset` mueve todo el
-- cuerpo respecto de la raíz (el cuerpo sigue a la raíz con inercia).
local function write(rig, offset)
    local blend = rig.Resume < 1 and Smooth(rig.Resume) or nil
    for _, node in ipairs(rig.Nodes) do
        local goal = offset * (CFrame.new(node.P) * node.D * node.RestRot)
        local parentPose = node.ParentNode and node.ParentNode.R or node.PartBase
        local base = parentPose * node.Local
        local transform = base:Inverse() * goal
        if blend and node.From then
            transform = node.From:Lerp(transform, blend)
        end
        node.Bone.Transform = transform
        node.R = base * transform
    end
    for _, proxy in ipairs(rig.Proxies) do
        proxy.Joint.C0 = proxy.Node.R * proxy.Offset
    end
    rig.Writes += 1
end

-- Mezcla desde la pose en que quedaron los huesos (captura, congelado).
function CreatureBones.BeginResume(rig)
    for _, node in ipairs(rig.Nodes) do
        node.From = node.Bone.Transform
    end
    rig.Resume = 0
    rig.Started = false
end

function CreatureBones.StepResume(rig, deltaTime, duration)
    if rig.Resume < 1 then
        rig.Resume = math.min(1, rig.Resume + deltaTime / duration)
    end
end

-- Vuelve a la pose de descanso.
function CreatureBones.Reset(rig)
    for _, node in ipairs(rig.Nodes) do
        node.Bone.Transform = IDENTITY
        node.R = (node.ParentNode and node.ParentNode.R or node.PartBase) * node.Local
    end
    for _, proxy in ipairs(rig.Proxies) do
        proxy.Joint.C0 = proxy.Node.R * proxy.Offset
    end
end

-- Posición en el mundo de un hueso según lo último escrito (para pruebas y efectos).
function CreatureBones.WorldOf(rig, name)
    local node = rig.ByName[name]
    if not node then
        return nil
    end
    return rig.Root.CFrame * node.R
end

-- IK de dos huesos --------------------------------------------------------------------

-- Ubica el tobillo (o la muñeca) en `target` (espacio de la criatura). La rodilla
-- se dobla hacia `pole`. Devuelve dónde quedó de verdad el extremo.
local function solveTwoBone(limb, target, pole)
    local upper, lower, last = limb.Upper, limb.Lower, limb.End
    local hip = upper.P
    local l1, l2 = limb.L1, limb.L2
    local toTarget = target - hip
    local distance = toTarget.Magnitude
    local direction = distance > 1e-4 and toTarget / distance or Vector3.new(0, -1, 0)
    distance = math.clamp(distance, math.abs(l1 - l2) + 1e-3, (l1 + l2) * 0.999)
    local along = (l1 * l1 - l2 * l2 + distance * distance) / (2 * distance)
    local height = math.sqrt(math.max(l1 * l1 - along * along, 0))
    local side = pole - direction * direction:Dot(pole)
    if side.Magnitude < 1e-4 then
        side = upper.ParentNode and (upper.ParentNode.D * limb.Pole) or limb.Pole
        side = side - direction * direction:Dot(side)
    end
    side = side.Magnitude > 1e-5 and side.Unit or Vector3.new(0, 0, -1)
    local knee = hip + direction * along + side * height
    local reached = hip + direction * distance

    local restPole = limb.Pole
    local a0 = (lower.RestPos - upper.RestPos).Unit
    local b0 = (last.RestPos - lower.RestPos).Unit
    local frame = upper.Rig.Frame
    upper.D = basis((knee - hip).Unit, side) * basis(a0, restPole):Inverse()
    upper.P = hip
    lower.D = basis((reached - knee).Unit, side) * basis(b0, restPole):Inverse()
    lower.P = knee
    last.P = reached
    upper.Set, lower.Set, last.Set = frame, frame, frame
    return reached
end

-- El resto de la cadena (pie y dedos, o mano y garras) cuelga del extremo.
local function chainEnd(limb, endRotation, bends)
    local chain = limb.Chain
    local last = chain[3]
    last.D = endRotation
    last.Set = last.Rig.Frame
    for index = 4, #chain do
        fk(chain[index], bends[index - 3] or IDENTITY)
    end
    return last
end

-- Paso de cada pata (MonsterAnimator) ---------------------------------------------------

-- Dónde apoya cada pata: clavada en el mundo durante el apoyo, en arco en el aire.
local function stepTarget(rig, limb, frame, spreadOffset)
    local visual = frame.Visual
    local home = limb.Home + spreadOffset
    local homeWorld = visual * home
    local u = (frame.Phase + limb.PhaseOffset) % 1
    local duty = math.clamp(frame.Duty + limb.DutyBias, 0.3, 0.8)
    local stance = u < duty
    local gait = frame.Gait

    if not rig.Started or not limb.Plant or gait < 0.03 then
        limb.Plant = homeWorld
        limb.LiftFrom = homeWorld
    end

    local world
    local lift = 0
    if stance then
        if not limb.Stance then
            -- Acaba de pisar: queda donde llegó.
            limb.Plant = limb.Landing or homeWorld
        end
        world = limb.Plant
        limb.Progress = 0
    else
        if limb.Stance then
            limb.LiftFrom = limb.Plant
        end
        local v = (u - duty) / (1 - duty)
        -- Va a pisar adelante: lo que avance el cuerpo hasta apoyar más medio apoyo.
        local velocity = visual:VectorToObjectSpace(frame.Velocity)
        velocity = Vector3.new(velocity.X, 0, velocity.Z)
        local ahead = ZERO
        if velocity.Magnitude > 0.05 then
            local share = math.min(velocity.Magnitude / math.max(frame.Drive, 0.05), 1)
            ahead = velocity.Unit * share * ((1 - u) * frame.Cycle + duty * frame.Cycle * 0.5)
        end
        local landing = visual * (home + ahead)
        limb.Landing = landing
        local s = Smooth(v)
        lift = math.sin(v * math.pi)
        world = limb.LiftFrom:Lerp(landing, s) + visual.UpVector * (lift * frame.Clearance * limb.Length)
        limb.Progress = v
    end
    limb.Stance = stance
    limb.Lift = lift

    -- Muy lejos (la raíz saltó o giró de golpe): se vuelve a apoyar.
    if (world - homeWorld).Magnitude > REPLANT * limb.Length then
        limb.Plant = homeWorld
        limb.LiftFrom = homeWorld
        world = homeWorld
    end
    -- Al frenar las patas vuelven solas debajo del cuerpo.
    if gait < 1 then
        world = homeWorld:Lerp(world, gait)
    end
    return visual:PointToObjectSpace(world), stance, u, duty
end

-- Pose completa a partir de lo que calculó MonsterAnimator (ver `frame` ahí).
function CreatureBones.Animate(rig, frame)
    local byName = rig.ByName
    local style = frame.Style
    local dt = frame.DeltaTime

    -- Raíz y cadera: la cadera baja, se mece y gira con las piernas; los hombros
    -- giran al revés (contragiro), repartido en la columna.
    local lean, twist, roll = frame.Lean, frame.Twist, frame.Roll
    local spines = spinesOf(rig)
    local count = #spines + 1
    rig.Frame += 1
    for _, node in ipairs(rig.Nodes) do
        if not node.ParentNode then
            fk(node, IDENTITY)
        end
    end
    -- Dónde pisa cada pata. La cadera baja lo justo para que todas lleguen (con la
    -- pata adelante y la de atrás estiradas la cadera queda más baja que en el
    -- medio del paso) y un poco más para no caminar con las rodillas trabadas.
    local spread = frame.Spread
    local shift = frame.Shift - Vector3.new(0, rig.LegLength * 0.025, 0)
    local extra, front, shoulders, fronts = 0, 0, ZERO, 0
    local limit = rig.LegLength * 0.5
    for _, limb in ipairs(rig.Feet) do
        local side = limb.Side
        local out = side * spread
        if limb.Role == "Arm" then
            out += side * (frame.ArmsOut * 0.5 + frame.GestureOut * 0.5)
        end
        local target, _, u, duty = stepTarget(rig, limb, frame, Vector3.new(math.sin(out) * limb.Length * 0.6, 0, 0))
        limb.Target, limb.U, limb.Duty = target, u, duty
        if not (limb.Role == "Arm" and frame.ArmsFwd > 0.15) then
            local hip = limb.Upper.RestPos + shift
            local dx, dz = target.X - hip.X, target.Z - hip.Z
            local reach = (limb.L1 + limb.L2) * 0.97
            local allowed = math.sqrt(math.max(reach * reach - dx * dx - dz * dz, 0))
            local need = (hip.Y - target.Y) - allowed
            if limb.Role == "Arm" then
                -- Patas delanteras (El Trepador): las baja el pecho, no la cadera.
                front = math.max(front, need)
                shoulders += limb.Upper.RestPos
                fronts += 1
            else
                extra = math.max(extra, need)
                -- Sin plegar de más la pata que acaba de pisar adelante.
                local short = math.abs(limb.L1 - limb.L2) * 1.15
                local room = (hip.Y - target.Y) - math.sqrt(math.max(short * short - dx * dx - dz * dz, 0))
                limit = math.min(limit, math.max(room, 0))
            end
        end
    end
    rig.HipDrop = math.min(extra, limit)
    -- El pecho se inclina adelante lo justo para que las patas delanteras lleguen.
    local bow = 0
    if fronts > 0 then
        local lever = shoulders / fronts - byName.Hips.RestPos
        local radius = math.sqrt(lever.Y * lever.Y + lever.Z * lever.Z)
        local need = front - rig.HipDrop
        if need > 0 and radius > 0.1 then
            local angle = math.atan2(lever.Y, -lever.Z)
            bow = angle - math.asin(math.clamp(math.sin(angle) - need / radius, -1, 1))
        end
    end
    rig.Bow = math.clamp(bow, 0, 0.9)

    local hips = byName.Hips
    fk(hips, CFrame.Angles(-lean * 0.3, -twist * 0.4, -roll * 0.5))
    hips.P += shift - Vector3.new(0, rig.HipDrop, 0)
    local spineQ = CFrame.Angles((-lean * 0.7 - rig.Bow) / count, twist * 1.4 / count, -roll * 0.5 / count)
    for _, node in ipairs(spines) do
        fk(node, spineQ)
    end
    local chest = byName.Chest
    if chest then
        fk(chest, spineQ * CFrame.Angles(-frame.Breath * 0.6, 0, 0) * frame.TwitchTorso)
        chest.P += UP * frame.Breath * 0.4
    end

    -- Cuello y cabeza: la mirada se reparte entre los dos.
    local neck, head = byName.Neck, byName.Head
    local share = neck and 0.65 or 1
    if neck then
        fk(neck, CFrame.fromEulerAnglesYXZ(frame.HeadPitch * 0.35, frame.HeadYaw * 0.35, frame.HeadRoll * 0.3))
    end
    if head then
        local look = CFrame.fromEulerAnglesYXZ(frame.HeadPitch * share, frame.HeadYaw * share, frame.HeadRoll * (neck and 0.7 or 1))
        fk(head, look * frame.TwitchHead)
    end
    local jaw = byName.Jaw
    if jaw then
        fk(jaw, CFrame.Angles(-frame.Jaw * 0.6, 0, 0))
    end

    -- Placas de El Coloso: siguen al pecho con retraso y vibran con las pisadas.
    for _, name in ipairs({"PlateLeft", "PlateRight", "PlateBack"}) do
        local plate = byName[name]
        if plate then
            local rattle = frame.Rattle * (name == "PlateRight" and -1 or 1)
            fk(plate, CFrame.Angles(rattle, 0, rattle * 0.5))
            plate.P += (plate.ParentNode and plate.ParentNode.D or IDENTITY) * Vector3.new(0, frame.PlateY, 0)
        end
    end
    -- Abdomen de El Trepador: péndulo que se balancea a destiempo del paso.
    local abdomen = byName.Abdomen
    if abdomen then
        local goal = math.sin(frame.Phase * TAU) * 0.12 * frame.Gait + frame.Breath * 2
        rig.Abdomen, rig.AbdomenVel = Spring(rig.Abdomen, rig.AbdomenVel, goal, 1.6, 0.4, dt)
        fk(abdomen, CFrame.Angles(rig.Abdomen, -twist * 0.6, roll * 0.4))
    end

    -- Patas que pisan (IK con el pie clavado).
    for _, limb in ipairs(rig.Feet) do
        local side = limb.Side
        if limb.Clavicle then
            fk(limb.Clavicle, IDENTITY)
        end
        fk(limb.Upper, IDENTITY)
        local target, u, duty = limb.Target, limb.U, limb.Duty

        -- Patas delanteras que se levantan (ataque, caída, trepar).
        if limb.Role == "Arm" then
            local raise = math.clamp(frame.ArmsFwd - 0.15, 0, 1.2)
            if raise > 0 then
                local chord = CFrame.Angles(frame.ArmsFwd * 0.8, 0, side * frame.ArmsOut * 0.4)
                    * (limb.Home - limb.Upper.RestPos)
                local reach = limb.Upper.P + limb.Upper.ParentNode.D * chord
                target = target:Lerp(reach, math.min(raise, 1))
            end
        end

        local pole = limb.Upper.ParentNode.D * limb.Pole
        solveTwoBone(limb, target, pole)

        -- Pie: plano en el apoyo; en el aire despega con la punta abajo y llega con
        -- la punta arriba. Los dedos se doblan al empujar.
        local v = limb.Progress or 0
        local pitch, toe = 0, 0
        if not limb.Stance then
            pitch = -0.5 * math.sin(math.min(v * 2, 1) * math.pi) * frame.Gait
                + 0.3 * math.sin(math.max(v * 2 - 1, 0) * math.pi) * frame.Gait
        else
            local late = math.clamp((u / duty - 0.7) / 0.3, 0, 1)
            pitch = -0.25 * late * frame.Gait
            toe = 0.5 * late * frame.Gait
        end
        if limb.Role == "Arm" then
            -- Garras de El Trepador: se cierran un poco en el aire.
            limb.Curl = Approach(limb.Curl, limb.Stance and 0.1 or 0.5, 8, dt)
            chainEnd(limb, CFrame.Angles(pitch, 0, 0), {CFrame.Angles(limb.Curl, 0, 0), CFrame.Angles(limb.Curl, 0, 0)})
        else
            chainEnd(limb, CFrame.Angles(pitch, 0, 0), {CFrame.Angles(toe, 0, 0)})
        end
    end

    -- Brazos que cuelgan: péndulo con peso, codo, mano y dedos.
    if not rig.Quadruped then
        for _, arm in ipairs(rig.Arms) do
            local side = arm.Side
            local legS = side < 0 and frame.LeftS or frame.RightS
            local goalFwd = -legS * frame.ArmSwing + frame.ArmsFwd
            local goalOut = frame.ArmsOut + frame.GestureOut
            arm.Fwd, arm.FwdVel = Spring(arm.Fwd, arm.FwdVel, goalFwd, style.ArmFreq, style.ArmDamp, dt)
            arm.Out, arm.OutVel = Spring(arm.Out, arm.OutVel, goalOut, style.ArmFreq, style.ArmDamp, dt)
            -- El codo se dobla más con el brazo adelante o atrás, y llega con retraso.
            local elbowGoal = 0.22 + 0.28 * math.max(arm.Fwd, 0) + 0.45 * math.max(-arm.Fwd, 0)
                - 0.25 * math.max(arm.Fwd - 1.3, 0)
            arm.Elbow, arm.ElbowVel = Spring(arm.Elbow, arm.ElbowVel, math.clamp(elbowGoal, 0.05, 1.6), style.ArmFreq * 1.3, 0.6, dt)
            arm.Curl = Approach(arm.Curl, frame.Claw, 6, dt)
            if arm.Clavicle then
                fk(arm.Clavicle, CFrame.Angles(0, 0, side * (frame.Breath * 0.8 + arm.Out * 0.15)))
            end
            fk(arm.Upper, CFrame.Angles(arm.Fwd, 0, side * arm.Out) * (side < 0 and frame.TwitchArmLeft or frame.TwitchArmRight))
            fk(arm.Lower, CFrame.Angles(arm.Elbow, 0, 0))
            local chain = arm.Chain
            fk(chain[3], CFrame.Angles(-0.15 - arm.Elbow * 0.2, 0, 0))
            for index = 4, #chain do
                fk(chain[index], CFrame.Angles(arm.Curl, 0, 0))
            end
        end
    end

    settleRest(rig)
    rig.Started = true
    write(rig, frame.Offset)
end

-- Captura (CaptureAnimator) -------------------------------------------------------------

-- Pose de la captura: mismos nombres que CaptureAnimator (Lean negativo es hacia
-- adelante, Arms positivo adelante, Out afuera, Gape boca abierta).
function CreatureBones.Capture(rig, pose, clock)
    local byName = rig.ByName
    resetPose(rig)
    local hips = byName.Hips
    hips.P += Vector3.new(0, pose.Crouch + pose.Lift - rig.LegLength * 0.04, 0)
    local spines = spinesOf(rig)
    local count = #spines + 1
    local spineQ = CFrame.Angles(pose.Lean / count, pose.Twist / count, pose.Roll / count)
    for _, node in ipairs(spines) do
        fk(node, spineQ)
    end
    if byName.Chest then
        fk(byName.Chest, spineQ)
    end
    local neck, head = byName.Neck, byName.Head
    if neck then
        fk(neck, CFrame.Angles(pose.HeadPitch * 0.4, pose.HeadYaw * 0.4, pose.HeadRoll * 0.4))
        neck.P += (neck.ParentNode and neck.ParentNode.D or IDENTITY) * Vector3.new(0, 0, -pose.HeadPush)
    end
    if head then
        fk(head, CFrame.Angles(pose.HeadPitch * 0.6, pose.HeadYaw * 0.6, pose.HeadRoll * 0.6))
    end
    if byName.Jaw then
        fk(byName.Jaw, CFrame.Angles(-math.clamp(pose.Gape, 0, 1.4) * 0.55, 0, 0))
    end
    for _, name in ipairs({"PlateLeft", "PlateRight", "PlateBack", "Abdomen"}) do
        if byName[name] then
            fk(byName[name], IDENTITY)
        end
    end

    -- Brazos (y las patas delanteras de El Trepador) agarran: codo doblado y dedos
    -- cerrados alrededor de la víctima.
    for _, arm in ipairs(rig.Arms) do
        local side = arm.Side
        local shake = pose.ArmShake * math.sin(clock * 40 + side)
        if arm.Clavicle then
            fk(arm.Clavicle, IDENTITY)
        end
        fk(arm.Upper, CFrame.Angles(pose.Arms + shake, 0, side * pose.Out))
        fk(arm.Lower, CFrame.Angles(0.35 + 0.35 * math.clamp(pose.Arms, 0, 1.5), 0, 0))
        local chain = arm.Chain
        fk(chain[3], CFrame.Angles(0.2, 0, 0))
        for index = 4, #chain do
            fk(chain[index], CFrame.Angles(0.9, 0, 0))
        end
    end
    -- Piernas: los pies quedan donde estaban (IK) aunque el cuerpo se agache.
    for _, leg in ipairs(rig.Legs) do
        fk(leg.Upper, IDENTITY)
        local splay = leg.Side * pose.Splay
        local target = leg.Home + Vector3.new(math.sin(splay) * leg.Length * 0.6, 0, -math.sin(pose.Legs) * leg.Length * 0.5)
        solveTwoBone(leg, target, leg.Upper.ParentNode.D * leg.Pole)
        chainEnd(leg, IDENTITY, {})
    end
    settleRest(rig)
    rig.Started = false
    write(rig, IDENTITY)
end

-- Para pruebas: ángulo de la rodilla (o el codo) de una extremidad, en radianes.
function CreatureBones.BendOf(rig, upperName, lowerName, endName)
    local upper, lower, last = rig.ByName[upperName], rig.ByName[lowerName], rig.ByName[endName]
    if not (upper and lower and last) then
        return nil
    end
    local a = (upper.R.Position - lower.R.Position).Unit
    local b = (last.R.Position - lower.R.Position).Unit
    return math.pi - math.acos(math.clamp(a:Dot(b), -1, 1))
end

return CreatureBones
