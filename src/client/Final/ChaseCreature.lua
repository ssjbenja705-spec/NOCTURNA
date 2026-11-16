-- El Organismo, tal como se ve en la persecución: un cuadrúpedo colosal que corre
-- agazapado, con los codos hacia afuera, garras largas que se clavan en el piso,
-- una cresta de hueso en el lomo, la boca que brilla y una lengua larga que azota.
-- Existe sólo en el cliente y se anima por código (galope, rugido, embestida y la
-- escena en que se traga a alguien): el servidor sólo dice dónde está.
local ChaseCreature = {}
ChaseCreature.__index = ChaseCreature

local FLESH = Color3.fromRGB(74, 36, 38)
local DARK = Color3.fromRGB(46, 24, 26)
local BONE = Color3.fromRGB(156, 140, 122)
local TONGUE = Color3.fromRGB(150, 48, 60)
local MOUTH = Color3.fromRGB(200, 30, 24)
local WEAK = Color3.fromRGB(255, 120, 60)
local STRIDE = 13
local TONGUE_SEGMENTS = 7
local TURN = CFrame.Angles(0, math.pi, 0)

-- Piezas orgánicas modeladas en Blender (assets/blender/build_organismo.py), con
-- su textura (SurfaceAppearance), en ReplicatedStorage.NocturnaAssets.Organismo.
-- Si falta alguna, esa pieza se arma con una forma simple.
local function organicTemplate()
    local assets = game:GetService("ReplicatedStorage"):FindFirstChild("NocturnaAssets")
    return assets and assets:FindFirstChild("Organismo")
end
ChaseCreature.Template = organicTemplate

local function piece(model, name, size, color, material, shape)
    local template = organicTemplate()
    local mesh = template and template:FindFirstChild(name)
    local part
    if mesh and mesh:IsA("MeshPart") then
        part = mesh:Clone()
        part.Name = name
        part.Size = size
        shape = nil
    else
        part = Instance.new("Part")
        part.Name = name
        part.Size = size
        part.Color = color
        part.Material = material or Enum.Material.Slate
    end
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    if shape then
        part.Shape = shape
    end
    part.Parent = model
    return part
end

local function ease(alpha)
    alpha = math.clamp(alpha, 0, 1)
    return alpha * alpha * (3 - 2 * alpha)
end

-- origin: posición del piso en S = 0 (FinalChaseConfig.Arena.Origin).
function ChaseCreature.new(parent, origin, scale)
    local rig = ChaseCreature.RigTemplate and ChaseCreature.RigTemplate()
    if rig then
        return ChaseCreature.Rig.new(parent, origin, scale, rig)
    end
    local model = Instance.new("Model")
    model.Name = "ElOrganismo"
    local size = scale or 1
    local self = setmetatable({
        Model = model,
        Origin = origin,
        Scale = size,
        Phase = 0,
        Roar = 0,
        Lunge = 0,
        Swallow = nil,
        Parts = {},
        Limbs = {},
        Spine = {},
        Tongue = {},
        LastStepSign = 1,
        OnStep = nil,
        Mouth = CFrame.new(origin + Vector3.new(0, 6 * size, 0)),
    }, ChaseCreature)

    local parts = self.Parts
    parts.Body = piece(model, "Body", Vector3.new(10, 7, 17) * size, FLESH)
    parts.Chest = piece(model, "Chest", Vector3.new(13, 8.5, 8) * size, FLESH)
    parts.Head = piece(model, "Head", Vector3.new(6.5, 5, 7.5) * size, FLESH)
    parts.Jaw = piece(model, "Jaw", Vector3.new(5.6, 1.5, 6) * size, DARK)
    parts.Mouth = piece(model, "Mouth", Vector3.new(4.5, 1, 1) * size, MOUTH, Enum.Material.Neon)
    -- El punto débil: un saco nervioso expuesto en la nuca, que late con luz propia
    -- (se ve desde lejos durante toda la persecución).
    parts.WeakPoint = piece(model, "WeakPoint", Vector3.new(3, 2.4, 3) * size, WEAK, Enum.Material.Neon, Enum.PartType.Ball)
    parts.WeakPoint.Material = Enum.Material.Neon
    parts.WeakPoint.Color = WEAK
    local weakGlow = Instance.new("PointLight")
    weakGlow.Color = WEAK
    weakGlow.Range = 16
    weakGlow.Brightness = 1.5
    weakGlow.Shadows = false
    weakGlow.Parent = parts.WeakPoint
    self.WeakGlow = weakGlow
    local glow = Instance.new("PointLight")
    glow.Color = MOUTH
    glow.Range = 20
    glow.Brightness = 2
    glow.Shadows = false
    glow.Parent = parts.Mouth
    self.Glow = glow

    for index = 1, 6 do
        self.Spine[index] = piece(model, "Spine", Vector3.new(1.6, 2.6 - index * 0.2, 2.2) * size, BONE)
    end

    -- Cuatro patas: adelante brazos largos con garras; atrás, patas de salto.
    local specs = {
        {Front = true, Upper = "Arm", Lower = "Forearm", Claw = "Claw", UpperSize = Vector3.new(2.8, 5.6, 2.8), LowerSize = Vector3.new(2.3, 5.4, 2.3), ClawSize = Vector3.new(4.6, 1.6, 6.2)},
        {Front = false, Upper = "Thigh", Lower = "Shin", Claw = "Foot", UpperSize = Vector3.new(3.4, 5.2, 3.4), LowerSize = Vector3.new(2.4, 5.2, 2.4), ClawSize = Vector3.new(3.8, 1.3, 4.8)},
    }
    for _, spec in ipairs(specs) do
        for _, side in ipairs({-1, 1}) do
            table.insert(self.Limbs, {
                Front = spec.Front,
                Side = side,
                Upper = piece(model, spec.Upper, spec.UpperSize * size, FLESH),
                Lower = piece(model, spec.Lower, spec.LowerSize * size, DARK),
                Claw = piece(model, spec.Claw, spec.ClawSize * size, BONE),
                UpperLength = spec.UpperSize.Y * size,
                LowerLength = spec.LowerSize.Y * size,
                -- Galope: las patas cruzadas van juntas.
                Phase = ((spec.Front and 0 or math.pi) + (side > 0 and 0.9 or 0)),
            })
        end
    end

    for index = 1, TONGUE_SEGMENTS do
        local thick = 1.35 - index * 0.13
        self.Tongue[index] = piece(model, "Tongue", Vector3.new(thick, thick * 0.7, 2.6) * size, TONGUE)
    end

    -- Si el importador dejó las mallas mirando hacia atrás (atributo MeshTurn en la
    -- plantilla), cada una se gira media vuelta sobre sí misma al ubicarla.
    self.Turned = {}
    local template = organicTemplate()
    if template and template:GetAttribute("MeshTurn") == true then
        for _, child in ipairs(model:GetChildren()) do
            if child:IsA("MeshPart") then
                table.insert(self.Turned, child)
            end
        end
    end

    model.Parent = parent
    return self
end

function ChaseCreature:SetVisible(visible)
    for _, descendant in ipairs(self.Model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.LocalTransparencyModifier = visible and 0 or 1
        end
    end
    self.Glow.Enabled = visible
    if self.WeakGlow then
        self.WeakGlow.Enabled = visible
    end
end

function ChaseCreature:StartRoar(duration)
    self.Roar = math.max(self.Roar, duration or 1.4)
end

function ChaseCreature:StartLunge()
    self.Lunge = 0.5
end

-- Se traga a alguien: baja la cabeza, abre la boca de par en par, saca la lengua y
-- cierra de golpe al final.
function ChaseCreature:StartSwallow(duration)
    self.Swallow = {Time = math.max(duration or 2.8, 0.5), Elapsed = 0}
end

function ChaseCreature:IsSwallowing()
    return self.Swallow ~= nil
end

-- Dónde está la boca (centro, entre las mandíbulas) en este cuadro.
function ChaseCreature:MouthPosition()
    return self.Mouth.Position
end

-- Ubica y anima la criatura en la posición s de la galería.
function ChaseCreature:Update(s, speed, deltaTime)
    local size = self.Scale
    speed = speed or 0
    self.Phase += speed * deltaTime / STRIDE * math.pi * 2
    self.Roar = math.max(0, self.Roar - deltaTime)
    self.Lunge = math.max(0, self.Lunge - deltaTime)
    local swallow = self.Swallow
    local gulp = nil
    if swallow then
        swallow.Elapsed += deltaTime
        gulp = swallow.Elapsed / swallow.Time
        if gulp >= 1.2 then
            self.Swallow = nil
            swallow, gulp = nil, nil
        end
    end

    -- Pasos: cada medio ciclo de galope pega contra el piso.
    local stepSign = math.sin(self.Phase) >= 0 and 1 or -1
    if stepSign ~= self.LastStepSign then
        self.LastStepSign = stepSign
        if self.OnStep and speed > 1 then
            self.OnStep(self:Position(s))
        end
    end

    local now = os.clock()
    local roaring = self.Roar > 0 and not swallow
    local bob = math.abs(math.sin(self.Phase)) * 0.7 * size
    local sway = math.sin(self.Phase * 0.5) * 1.1 * size
    -- Ángulo positivo: se alza (ruge); negativo: hunde la cabeza para correr o tragar.
    local lean = -(0.08 + math.min(speed, 30) / 30 * 0.1)
    if roaring then
        lean = 0.3
    elseif swallow then
        lean = -0.26 * ease(gulp / 0.3)
    end
    local lunge = self.Lunge > 0 and math.sin(self.Lunge / 0.5 * math.pi) * 3 * size or 0
    if swallow then
        lunge = ease(gulp / 0.4) * 2.5 * size
    end

    local origin = self.Origin
    local base = CFrame.new(origin.X + sway, origin.Y + 8.2 * size + bob, origin.Z + s + lunge)
        * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(lean, 0, math.sin(self.Phase * 0.5) * 0.05)

    local parts = self.Parts
    parts.Body.CFrame = base * CFrame.new(0, 0, 1.5 * size)
    parts.Chest.CFrame = base * CFrame.new(0, 0.6 * size, -6 * size) * CFrame.Angles(-0.15, 0, 0)

    local headLift = math.sin(self.Phase) * 0.06 - 0.1
    local jawOpen = 0.2 + math.abs(math.sin(self.Phase * 1.5)) * 0.12
    local tongueOut = 0.55
    if roaring then
        headLift, jawOpen, tongueOut = 0.5, 0.8, 1
    elseif swallow then
        headLift = -0.3 * ease(gulp / 0.3)
        -- Abre de a poco hasta el 72 % y cierra de golpe.
        jawOpen = gulp < 0.72 and 0.3 + 0.95 * ease(gulp / 0.72) or math.max(0.03, 1.25 - (gulp - 0.72) / 0.08 * 1.25)
        tongueOut = gulp < 0.72 and 1 or 0.2
    end
    local head = base * CFrame.new(0, -1.2 * size, -11.5 * size) * CFrame.Angles(headLift, math.sin(self.Phase * 0.5) * 0.12, 0)
    parts.Head.CFrame = head
    parts.Jaw.CFrame = head * CFrame.new(0, -2.4 * size, -0.3 * size) * CFrame.Angles(-jawOpen, 0, 0)
    parts.Mouth.CFrame = head * CFrame.new(0, -1.7 * size, -2.4 * size)
    self.Mouth = head * CFrame.new(0, -2 * size, -3.2 * size)
    self.Glow.Brightness = (roaring or swallow) and 4 or 1.6 + math.sin(now * 7) * 0.3

    -- Punto débil en la nuca, latiendo (más rápido cuando ruge o traga).
    local beat = (math.sin(now * ((roaring or swallow) and 9 or 4)) + 1) / 2
    parts.WeakPoint.CFrame = head * CFrame.new(0, (2.3 + beat * 0.15) * size, 1.8 * size)
    parts.WeakPoint.Color = WEAK:Lerp(Color3.fromRGB(255, 220, 140), beat)
    self.WeakGlow.Brightness = 0.8 + beat * 1.6

    -- Cresta de hueso a lo largo del lomo.
    for index, plate in ipairs(self.Spine) do
        plate.CFrame = base * CFrame.new(0, (3.9 - index * 0.12) * size, (-7 + index * 2.7) * size) * CFrame.Angles(0.55, 0, 0)
    end

    -- Patas. Hombro o cadera -> codo o rodilla hacia afuera -> garra apoyada plana.
    local flat = CFrame.Angles(0, math.pi, 0)
    for _, limb in ipairs(self.Limbs) do
        local swing = math.sin(self.Phase + limb.Phase)
        local lift = math.max(0, math.cos(self.Phase + limb.Phase)) * (speed > 1 and 1.6 or 0) * size
        local root, reach, splay, bend
        if limb.Front then
            root = base * CFrame.new(limb.Side * 6.2 * size, 0.5 * size, -5.5 * size)
            reach = (roaring or swallow) and 0.75 or 0.3 + swing * 0.5
            splay = 0.8
            bend = -reach * 0.85 + 0.1
        else
            root = base * CFrame.new(limb.Side * 4.8 * size, -0.3 * size, 7.5 * size)
            reach = 0.6 + swing * 0.4
            splay = 0.45
            bend = -1.3 - swing * 0.2
        end
        local upper = root * CFrame.Angles(reach, 0, limb.Side * splay) * CFrame.new(0, -limb.UpperLength / 2, 0)
        limb.Upper.CFrame = upper
        local joint = upper * CFrame.new(0, -limb.UpperLength / 2, 0)
        local lower = joint * CFrame.Angles(bend, 0, -limb.Side * splay * 0.9) * CFrame.new(0, -limb.LowerLength / 2, 0)
        limb.Lower.CFrame = lower
        local tip = (lower * CFrame.new(0, -limb.LowerLength / 2, 0)).Position
        local ground = math.max(tip.Y, origin.Y + limb.Claw.Size.Y / 2) + lift
        limb.Claw.CFrame = CFrame.new(tip.X, ground, tip.Z + 1.2 * size) * flat
            * CFrame.Angles(lift > 0 and -0.35 or 0, limb.Side * -0.2, 0)
    end

    -- Lengua: una cadena que sale de la boca, cuelga y azota.
    local link = head * CFrame.new(0, -2 * size, -2.6 * size) * CFrame.Angles(-0.08, 0, 0)
    for index, segment in ipairs(self.Tongue) do
        local whip = (roaring or swallow) and 0.34 or 0.2
        link = link
            * CFrame.Angles(math.sin(now * 3.1 + index * 0.9) * whip - 0.045, math.sin(now * 2.3 + index * 0.7) * whip * 1.2, 0)
            * CFrame.new(0, 0, -segment.Size.Z * 0.5 * tongueOut)
        segment.CFrame = link
        link = link * CFrame.new(0, 0, -segment.Size.Z * 0.5 * tongueOut)
    end

    for _, part in ipairs(self.Turned) do
        part.CFrame *= TURN
    end
end

function ChaseCreature:Position(s)
    local origin = self.Origin
    return Vector3.new(origin.X, origin.Y + 4, origin.Z + s)
end

function ChaseCreature:Destroy()
    self.Model:Destroy()
end

-- Versión con esqueleto -------------------------------------------------------------
-- Si existe ReplicatedStorage.NocturnaAssets.OrganismoRig (el modelo de Meshy con
-- huesos, assets/blender/rig_organismo.py), la criatura es esa única malla con piel
-- y se anima girando sus huesos (Bone.Transform). Misma interfaz que la de piezas.
local RigCreature = {}
RigCreature.__index = RigCreature

local RIG_HEIGHT = 15.5
local UP = Vector3.new(0, 1, 0)

local function rigTemplate()
    local assets = game:GetService("ReplicatedStorage"):FindFirstChild("NocturnaAssets")
    local rig = assets and assets:FindFirstChild("OrganismoRig")
    if rig and rig:IsA("MeshPart") and rig:FindFirstChildWhichIsA("Bone", true) then
        return rig
    end
    return nil
end
ChaseCreature.RigTemplate = rigTemplate

function RigCreature.new(parent, origin, scale, template)
    local size = scale or 1
    local model = Instance.new("Model")
    model.Name = "ElOrganismo"
    local mesh = template:Clone()
    mesh.Name = "Rig"
    mesh.Anchored = true
    mesh.CanCollide = false
    mesh.CanTouch = false
    mesh.CanQuery = false
    mesh.CastShadow = false
    mesh.Parent = model
    model.Parent = parent
    -- Escala: la pieza y, uno por uno, la posición de cada hueso respecto de su
    -- padre. (Cambiar sólo Size, o Model:ScaleTo, deja los huesos donde estaban y la
    -- piel se estira cientos de studs.)
    local factor = RIG_HEIGHT * size / template.Size.Y
    mesh.Size = template.Size * factor
    for _, bone in ipairs(mesh:GetDescendants()) do
        if bone:IsA("Bone") then
            bone.Position *= factor
        end
    end
    mesh.CFrame = CFrame.new(origin + Vector3.new(0, mesh.Size.Y / 2, 0))

    local bones, rest = {}, {}
    for _, bone in ipairs(mesh:GetDescendants()) do
        if bone:IsA("Bone") then
            bones[bone.Name] = bone
            bone.Transform = CFrame.identity
        end
    end
    for name, bone in pairs(bones) do
        rest[name] = mesh.CFrame:ToObjectSpace(bone.WorldCFrame).Rotation
    end

    -- Hacia dónde mira la malla dentro de su propia pieza: de la cadera a la cabeza.
    -- El importador puede dejarla al derecho o al revés; así da igual.
    local front = Vector3.new(0, 0, -1)
    if bones.Head and bones.Hips then
        local toHead = mesh.CFrame:PointToObjectSpace(bones.Head.WorldPosition) - mesh.CFrame:PointToObjectSpace(bones.Hips.WorldPosition)
        front = Vector3.new(0, 0, toHead.Z >= 0 and 1 or -1)
    end

    local glowPart = Instance.new("Part")
    glowPart.Name = "WeakPoint"
    glowPart.Size = Vector3.new(0.4, 0.4, 0.4)
    glowPart.Transparency = 1
    glowPart.Anchored = true
    glowPart.CanCollide = false
    glowPart.CanTouch = false
    glowPart.CanQuery = false
    glowPart.Parent = model
    local mouthPart = glowPart:Clone()
    mouthPart.Name = "Mouth"
    mouthPart.Parent = model
    local weakGlow = Instance.new("PointLight")
    weakGlow.Color = WEAK
    weakGlow.Range = 18 * size
    weakGlow.Brightness = 1.5
    weakGlow.Shadows = false
    weakGlow.Parent = glowPart
    local glow = Instance.new("PointLight")
    glow.Color = MOUTH
    glow.Range = 16 * size
    glow.Brightness = 1.2
    glow.Shadows = false
    glow.Parent = mouthPart

    local self = setmetatable({
        Model = model,
        Mesh = mesh,
        Origin = origin,
        Scale = size,
        Bones = bones,
        Rest = rest,
        Front = front,
        -- Girar alrededor de este eje un ángulo positivo levanta el frente (y lleva
        -- una pata hacia adelante); negativo lo baja.
        Lateral = front:Cross(UP),
        -- Con el frente de la pieza en -Z (lo normal en Roblox) hay que darla vuelta
        -- para que corra hacia +Z, como la galería.
        Facing = front.Z < 0 and CFrame.Angles(0, math.pi, 0) or CFrame.identity,
        Phase = 0,
        Roar = 0,
        Lunge = 0,
        Swallow = nil,
        LastStepSign = 1,
        OnStep = nil,
        Glow = glow,
        WeakGlow = weakGlow,
        GlowPart = glowPart,
        MouthPart = mouthPart,
        Mouth = CFrame.new(origin + Vector3.new(0, 6 * size, 9 * size)),
        IsRig = true,
    }, RigCreature)
    model.Parent = parent
    return self
end

function RigCreature:SetVisible(visible)
    self.Mesh.LocalTransparencyModifier = visible and 0 or 1
    self.Glow.Enabled = visible
    self.WeakGlow.Enabled = visible
end

RigCreature.StartRoar = ChaseCreature.StartRoar
RigCreature.StartLunge = ChaseCreature.StartLunge
RigCreature.StartSwallow = ChaseCreature.StartSwallow
RigCreature.IsSwallowing = ChaseCreature.IsSwallowing
RigCreature.MouthPosition = ChaseCreature.MouthPosition
RigCreature.Position = ChaseCreature.Position

-- Gira un hueso: `pitch` levanta (+) o baja (-) su frente, `yaw` lo lleva a los
-- lados y `roll` lo inclina. Los ángulos están en el espacio de la criatura.
function RigCreature:Turn(name, pitch, yaw, roll)
    local bone = self.Bones[name]
    if not bone then
        return
    end
    local rotation = CFrame.fromAxisAngle(self.Lateral, pitch or 0)
    if yaw and yaw ~= 0 then
        rotation = CFrame.fromAxisAngle(UP, yaw) * rotation
    end
    if roll and roll ~= 0 then
        rotation = CFrame.fromAxisAngle(self.Front, roll) * rotation
    end
    local restRotation = self.Rest[name]
    bone.Transform = restRotation:Inverse() * rotation * restRotation
end

function RigCreature:Update(s, speed, deltaTime)
    local size = self.Scale
    speed = speed or 0
    self.Phase += speed * deltaTime / STRIDE * math.pi * 2
    self.Roar = math.max(0, self.Roar - deltaTime)
    self.Lunge = math.max(0, self.Lunge - deltaTime)
    local swallow = self.Swallow
    local gulp = nil
    if swallow then
        swallow.Elapsed += deltaTime
        gulp = swallow.Elapsed / swallow.Time
        if gulp >= 1.2 then
            self.Swallow = nil
            swallow, gulp = nil, nil
        end
    end

    local phase = self.Phase
    local stepSign = math.sin(phase) >= 0 and 1 or -1
    if stepSign ~= self.LastStepSign then
        self.LastStepSign = stepSign
        if self.OnStep and speed > 1 then
            self.OnStep(self:Position(s))
        end
    end

    local now = os.clock()
    local roaring = self.Roar > 0 and not swallow
    local moving = math.clamp(speed / 12, 0, 1)
    local bob = math.abs(math.sin(phase)) * 0.6 * size * moving
    local sway = math.sin(phase * 0.5) * 0.9 * size * moving
    -- En el mundo corre hacia +Z: girar alrededor de X un ángulo positivo baja el frente.
    local lean = 0.05 * moving
    if roaring then
        lean = -0.2
    elseif swallow then
        lean = 0.16 * ease(gulp / 0.3)
    end
    local lunge = self.Lunge > 0 and math.sin(self.Lunge / 0.5 * math.pi) * 3 * size or 0
    if swallow then
        lunge = ease(gulp / 0.4) * 2.5 * size
    end

    local origin = self.Origin
    local mesh = self.Mesh
    mesh.CFrame = CFrame.new(origin.X + sway, origin.Y + mesh.Size.Y / 2 + bob, origin.Z + s + lunge)
        * CFrame.Angles(lean, 0, math.sin(phase * 0.5) * 0.04 * moving) * self.Facing

    -- Columna, cuello y cabeza.
    local breath = math.sin(now * 1.7) * 0.03
    self:Turn("Hips", math.sin(phase) * 0.06 * moving, math.sin(phase * 0.5) * 0.07 * moving, 0)
    self:Turn("Chest", -math.sin(phase) * 0.08 * moving + breath, -math.sin(phase * 0.5) * 0.09 * moving, 0)
    local headLift = math.sin(phase) * 0.07 * moving + breath
    local headYaw = math.sin(now * 0.9) * 0.12
    -- En reposo la boca ya está entreabierta: negativo la abre más, positivo la cierra.
    local jaw = -0.1 - math.abs(math.sin(phase * 1.5)) * 0.12 * moving
    local whip = 0.3
    if roaring then
        headLift, headYaw, jaw, whip = 0.4, math.sin(now * 14) * 0.05, -0.6, 0.6
    elseif swallow then
        headLift = -0.25 * ease(gulp / 0.3)
        headYaw = 0
        -- Abre de a poco hasta el 72 % y cierra de golpe.
        jaw = gulp < 0.72 and -0.15 - 0.75 * ease(gulp / 0.72) or math.min(0.22, -0.9 + (gulp - 0.72) / 0.08 * 1.12)
        whip = gulp < 0.72 and 0.7 or 0.1
    end
    self:Turn("Neck", headLift * 0.5, headYaw * 0.5, 0)
    self:Turn("Head", headLift * 0.6, headYaw * 0.6, 0)
    self:Turn("Jaw", jaw, 0, 0)
    self:Turn("Tongue1", math.sin(now * 3.1) * whip * 0.6, math.sin(now * 2.3) * whip, 0)
    self:Turn("Tongue2", math.sin(now * 3.1 + 0.9) * whip, math.sin(now * 2.3 + 0.7) * whip * 1.3, 0)

    -- Patas: galope con las cruzadas juntas. Adelante se estira el brazo y se
    -- recoge la mano; atrás empuja el muslo.
    local reach = (roaring or swallow) and 0.25 or 0
    local armGain = math.max(moving, reach > 0 and 1 or 0)
    for _, limb in ipairs({{"Right", 0}, {"Left", math.pi}}) do
        local side, offset = limb[1], limb[2]
        local front = math.sin(phase + offset)
        local frontLift = math.max(0, math.cos(phase + offset))
        self:Turn(side .. "UpperArm", (front * 0.42 * moving + reach) * armGain, 0, 0)
        self:Turn(side .. "Forearm", (-front * 0.3 - frontLift * 0.25) * moving - reach * 0.6, 0, 0)
        self:Turn(side .. "Hand", (frontLift * 0.5 - front * 0.15) * moving, 0, 0)
        local back = math.sin(phase + offset + math.pi)
        local backLift = math.max(0, math.cos(phase + offset + math.pi))
        self:Turn(side .. "Thigh", back * 0.38 * moving, 0, 0)
        self:Turn(side .. "Shin", (-back * 0.3 + backLift * 0.3) * moving, 0, 0)
        self:Turn(side .. "Foot", (backLift * 0.35 - back * 0.1) * moving, 0, 0)
    end

    -- Boca y saco de la nuca (luces que siguen a los huesos ya animados).
    local bones = self.Bones
    local tongue = bones.Tongue1 or bones.Jaw or bones.Head
    if tongue then
        self.Mouth = CFrame.new(tongue.TransformedWorldCFrame.Position)
        self.MouthPart.CFrame = self.Mouth
    end
    local neck = bones.Neck or bones.Head
    if neck then
        self.GlowPart.CFrame = CFrame.new(neck.TransformedWorldCFrame.Position + UP * 1.5 * size)
    end
    self.Glow.Brightness = (roaring or swallow) and 3 or 1.2 + math.sin(now * 7) * 0.2
    local beat = (math.sin(now * ((roaring or swallow) and 9 or 4)) + 1) / 2
    self.WeakGlow.Brightness = 0.8 + beat * 1.6
end

function RigCreature:Destroy()
    self.Model:Destroy()
end

ChaseCreature.Rig = RigCreature

return ChaseCreature
