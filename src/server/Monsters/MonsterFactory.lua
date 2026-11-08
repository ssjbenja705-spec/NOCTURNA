-- Construye las criaturas. La raíz va anclada y las extremidades cuelgan de
-- Motor6D que el cliente anima.
--
-- Cada pieza usa, en este orden, lo que encuentre en ServerStorage.NocturnaModels/<Criatura>:
--   1. La pieza cortada del modelo realista (Arm1, Arm2...), con su tamaño y
--      desplazamiento reales de CreatureMeshes (ver assets/models/ai/README.md).
--   2. La malla de Blender con el nombre de la pieza (Arm), estirada a su caja
--      (ver assets/models/README.md).
--   3. Una Part simple del mismo tamaño.
-- Así el juego funciona igual con o sin los modelos importados.
--
-- Antes que todo eso, si existe NocturnaModels.<Criatura>Rig (malla con piel y
-- huesos, ver assets/models/rigged/README.md), la criatura es esa malla entera y
-- el cliente la anima moviendo los huesos (atributo BoneRig).
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local CreatureMeshes = require(script.Parent.CreatureMeshes)
local CreatureRigs = require(script.Parent.CreatureRigs)

local MODELS_FOLDER = "NocturnaModels"

local MonsterFactory = {}

local function modelSet(model)
    local kind = model:GetAttribute("ModelSet") or ""
    local folder = ServerStorage:FindFirstChild(MODELS_FOLDER)
    return folder, folder and folder:FindFirstChild(kind), CreatureMeshes[kind]
end

local function findMesh(set, name)
    local found = set:FindFirstChild(name, true)
    return found and found:IsA("MeshPart") and found or nil
end

-- Con el modelo realista importado, la criatura usa su propia cara y no los ojos de neón.
local function usesCuts(model)
    local _, set, cuts = modelSet(model)
    if not (set and cuts) then
        return false
    end
    for key in pairs(cuts) do
        if findMesh(set, key) then
            return true
        end
    end
    return false
end

local warnedMissing = {}

local function meshTemplate(model, name, index)
    local folder, set, cuts = modelSet(model)
    if not set then
        -- Se avisa una vez: sin esto, una publicación sin los modelos saldría
        -- con criaturas de bloques sin que nadie lo note.
        local kind = model:GetAttribute("ModelSet") or ""
        if kind ~= "" and not warnedMissing[kind] then
            warnedMissing[kind] = true
            warn("[NOCTURNA] Falta el modelo de " .. kind .. " en ServerStorage." .. MODELS_FOLDER
                .. ": se arma con piezas simples.")
        end
        return nil
    end
    -- TurnAround corrige un importador que deje las mallas mirando hacia atrás.
    local turnAround = folder:GetAttribute("TurnAround") == true
    local fit = cuts and cuts[name .. index]
    local cut = fit and findMesh(set, name .. index)
    if cut then
        return cut, fit, turnAround, set
    end
    local template = findMesh(set, name)
    if template then
        return template, nil, turnAround, set
    end
    return nil
end

-- Una malla con textura propia conserva su aspecto; si no, toma color y material.
local function hasOwnLook(part)
    return part.TextureID ~= "" or part:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil
end

local function nextIndex(model, name)
    local count = 0
    for _, child in ipairs(model:GetChildren()) do
        if child.Name == name then
            count += 1
        end
    end
    return count + 1
end

local function newPart(model, name)
    local template, fit, turnAround, set = meshTemplate(model, name, nextIndex(model, name))
    if not template then
        return Instance.new("Part"), false, false, nil
    end

    local part = template:Clone()
    for _, child in ipairs(part:GetChildren()) do
        if not child:IsA("SurfaceAppearance") then
            child:Destroy()
        end
    end
    -- Una sola SurfaceAppearance en la carpeta de la criatura viste todas sus piezas.
    local shared = set:FindFirstChildWhichIsA("SurfaceAppearance")
    if shared and not part:FindFirstChildWhichIsA("SurfaceAppearance") then
        shared:Clone().Parent = part
    end
    part.Anchored = false
    return part, hasOwnLook(part), turnAround, fit
end

local function newRoot(parent, name, height)
    local model = Instance.new("Model")
    model.Name = name

    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.Size = Vector3.new(2, 2, 1)
    root.Transparency = 1
    root.Anchored = true
    root.CanCollide = false
    root.CanTouch = false
    root.CanQuery = false
    root.Parent = model

    model.PrimaryPart = root
    model:SetAttribute("BodyHeight", height)
    model.Parent = parent
    return model, root
end

-- Rodilla o codo: si el modelo trae la parte baja de una extremidad cortada
-- (<Pieza><n>Lower, por ejemplo Leg1Lower), se cuelga del extremo de la parte de
-- arriba con su propia articulación y el cliente la dobla (dos huesos). Los cortes
-- actuales son de una sola pieza por extremidad, así que hoy no se usa.
local function attachLower(model, upper, name, length, place)
    local _, set = modelSet(model)
    if not set then
        return nil
    end
    local index = nextIndex(model, name) - 1
    local template = findMesh(set, name .. index .. "Lower")
    if not template then
        return nil
    end
    local lower = template:Clone()
    for _, child in ipairs(lower:GetChildren()) do
        if not child:IsA("SurfaceAppearance") then
            child:Destroy()
        end
    end
    local shared = set:FindFirstChildWhichIsA("SurfaceAppearance")
    if shared and not lower:FindFirstChildWhichIsA("SurfaceAppearance") then
        shared:Clone().Parent = lower
    end
    lower.Name = name .. "Lower"
    lower.Anchored = false
    lower.Massless = true
    lower.CanCollide = false
    lower.CanTouch = false
    lower.CanQuery = false
    lower.CastShadow = false

    -- La rodilla está en el borde de abajo de la caja de la parte de arriba.
    local knee = place:Inverse() * CFrame.new(0, -length / 2, 0)
    local hang = CFrame.new(0, lower.Size.Y / 2, 0)
    lower.CFrame = upper.CFrame * knee * hang:Inverse()
    lower.Parent = model

    local joint = Instance.new("Motor6D")
    joint.Name = name .. "LowerJoint"
    joint.Part0 = upper
    joint.Part1 = lower
    joint.C0 = knee
    joint.C1 = hang
    joint.Parent = lower
    return lower
end

local function limb(model, root, name, size, offset, color, material, swing)
    local part, ownLook, turnAround, fit = newPart(model, name)
    if fit then
        -- El modelo realista trae su propia caja, medida sobre su anatomía.
        offset, size = fit.Offset, fit.Box
    end
    -- La pieza cortada conserva sus medidas: su centro se corre respecto de la caja.
    local place = (fit and CFrame.new(fit.Shift) or CFrame.identity)
        * (turnAround and CFrame.Angles(0, math.pi, 0) or CFrame.identity)
    -- Lo que se balancea gira desde el borde de arriba (hombro, cadera), no desde el centro.
    local pivot = swing and CFrame.new(0, size.Y / 2, 0) or CFrame.identity
    part.Name = name
    part.Size = fit and fit.Size or size
    part.CFrame = root.CFrame * offset * place
    if not ownLook then
        part.Color = color
        part.Material = material or Enum.Material.SmoothPlastic
    end
    part.Massless = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Parent = model

    local joint = Instance.new("Motor6D")
    joint.Name = name .. "Joint"
    joint.Part0 = root
    joint.Part1 = part
    joint.C0 = offset * pivot
    joint.C1 = place:Inverse() * pivot
    joint.Parent = part

    if swing then
        joint:SetAttribute("SwingAmount", swing.Amount)
        joint:SetAttribute("SwingPhase", swing.Phase or 0)
        joint:SetAttribute("SwingAxis", swing.Axis or "X")
        attachLower(model, part, name, (fit and fit.Box or size).Y, place)
    end

    return part
end

-- Pieza propia (no cortada) que el modelo puede traer aparte, como una mandíbula
-- articulada o una lengua: ServerStorage.NocturnaModels.<Criatura>.<Nombre>.
local function dedicatedTemplate(model, name)
    local _, set = modelSet(model)
    return set and findMesh(set, name) or nil
end

-- Agrega una pieza propia unida a la raíz con su tamaño real. `hinge` es el
-- punto de giro relativo al centro de la pieza (por ejemplo, arriba y atrás).
local function dedicatedPart(model, root, template, name, offset, hinge)
    local _, set = modelSet(model)
    local part = template:Clone()
    for _, child in ipairs(part:GetChildren()) do
        if not child:IsA("SurfaceAppearance") then
            child:Destroy()
        end
    end
    local shared = set and set:FindFirstChildWhichIsA("SurfaceAppearance")
    if shared and not part:FindFirstChildWhichIsA("SurfaceAppearance") then
        shared:Clone().Parent = part
    end
    part.Name = name
    part.Anchored = false
    part.Massless = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.CFrame = root.CFrame * offset
    part.Parent = model

    local pivot = hinge or CFrame.identity
    local joint = Instance.new("Motor6D")
    joint.Name = name .. "Joint"
    joint.Part0 = root
    joint.Part1 = part
    joint.C0 = offset * pivot
    joint.C1 = pivot
    joint.Parent = part
    return part, joint
end

local function eye(model, root, offset, color)
    if usesCuts(model) then
        return nil
    end
    return limb(model, root, "Eye", Vector3.new(0.3, 0.2, 0.15), offset, color, Enum.Material.Neon)
end

local BUILDERS = {}

function BUILDERS.ElOyente(model, root)
    local skin = Color3.fromRGB(128, 120, 112)
    local dark = Color3.fromRGB(48, 44, 42)
    limb(model, root, "Torso", Vector3.new(1.6, 4.6, 1), CFrame.new(0, 0.6, 0) * CFrame.Angles(0.25, 0, 0), skin, Enum.Material.Slate)
    limb(model, root, "Head", Vector3.new(1.3, 2, 1.4), CFrame.new(0, 3.4, -0.9), skin, Enum.Material.Slate)

    for _, side in ipairs({-1, 1}) do
        limb(model, root, "Arm", Vector3.new(0.5, 5.4, 0.5), CFrame.new(side * 1.2, -0.4, -0.2), dark, Enum.Material.Slate, {Amount = 0.4, Phase = side})
        limb(model, root, "Leg", Vector3.new(0.6, 3.4, 0.6), CFrame.new(side * 0.5, -2.3, 0), dark, Enum.Material.Slate, {Amount = 0.5, Phase = -side})
    end
end

-- Boca: el modelo realista trae un parche cortado (Jaw1) que apenas se puede
-- entreabrir. Si en NocturnaModels/ElImitador hay una mandíbula propia ("Jaw") o
-- una lengua ("Tongue"), se usan solas: la mandíbula gira desde arriba y atrás
-- (JawHinge: el cliente la abre del todo) y la lengua sale de la boca al atacar.
local function imitadorMouth(model, root)
    local cuts = CreatureMeshes.ElImitador
    local mouth = cuts and cuts.Jaw1 and cuts.Jaw1.Offset or CFrame.new(0, 2.2, -0.65)
    local jaw = dedicatedTemplate(model, "Jaw")
    if jaw then
        local size = jaw.Size
        local _, joint = dedicatedPart(model, root, jaw, "Jaw", mouth, CFrame.new(0, size.Y / 2, size.Z / 2))
        joint:SetAttribute("JawHinge", true)
    else
        limb(model, root, "Jaw", Vector3.new(0.8, 1.4, 0.2), CFrame.new(0, 2.2, -0.65), Color3.fromRGB(190, 30, 40), Enum.Material.Neon, {Amount = 0.25})
    end
    local tongue = dedicatedTemplate(model, "Tongue")
    if tongue then
        -- Guardada dentro de la boca: el cliente la empuja hacia afuera.
        dedicatedPart(model, root, tongue, "Tongue", mouth * CFrame.new(0, 0, tongue.Size.Z * 0.5))
    end
end

function BUILDERS.ElImitador(model, root)
    local void = Color3.fromRGB(10, 10, 12)
    limb(model, root, "Torso", Vector3.new(2, 2.6, 1), CFrame.new(0, 0.6, 0), void, Enum.Material.Fabric)
    limb(model, root, "Head", Vector3.new(1.2, 1.4, 1.2), CFrame.new(0, 2.7, 0), void, Enum.Material.SmoothPlastic)
    imitadorMouth(model, root)

    for _, side in ipairs({-1, 1}) do
        limb(model, root, "Arm", Vector3.new(0.7, 3.2, 0.7), CFrame.new(side * 1.4, 0.3, 0), void, Enum.Material.Fabric, {Amount = 0.6, Phase = side})
        limb(model, root, "Leg", Vector3.new(0.8, 2.4, 0.8), CFrame.new(side * 0.5, -1.9, 0), void, Enum.Material.Fabric, {Amount = 0.6, Phase = -side})
    end
end

local function buildMannequinBody(model, root)
    local body = Color3.fromRGB(196, 190, 180)
    limb(model, root, "Torso", Vector3.new(2, 2.6, 1), CFrame.new(0, 0.6, 0), body, Enum.Material.SmoothPlastic)
    limb(model, root, "Head", Vector3.new(1.3, 1.5, 1.3), CFrame.new(0, 2.8, 0), body, Enum.Material.SmoothPlastic)
    for _, side in ipairs({-1, 1}) do
        limb(model, root, "Arm", Vector3.new(0.7, 3, 0.7), CFrame.new(side * 1.4, 0.4, 0), body, Enum.Material.SmoothPlastic, {Amount = 0.3, Phase = side})
        limb(model, root, "Leg", Vector3.new(0.8, 3, 0.8), CFrame.new(side * 0.5, -2.1, 0), body, Enum.Material.SmoothPlastic, {Amount = 0.4, Phase = -side})
    end
end

function BUILDERS.ElQuieto(model, root)
    buildMannequinBody(model, root)
    eye(model, root, CFrame.new(-0.3, 2.9, -0.68), Color3.fromRGB(20, 20, 20))
    eye(model, root, CFrame.new(0.3, 2.9, -0.68), Color3.fromRGB(20, 20, 20))
end

-- Alto y encorvado, con brazos que llegan al piso. En el techo cuelga boca abajo
-- con los pies arriba, así que su altura total (7) deja pasar a un jugador debajo.
function BUILDERS.ElTrepador(model, root)
    local shell = Color3.fromRGB(38, 36, 38)
    limb(model, root, "Torso", Vector3.new(1.2, 2.6, 1), CFrame.new(0, 1.5, 0.15) * CFrame.Angles(0.35, 0, 0), shell, Enum.Material.Slate)
    limb(model, root, "Head", Vector3.new(0.9, 1.1, 1.6), CFrame.new(0, 2.9, -0.8), shell, Enum.Material.Slate)
    eye(model, root, CFrame.new(-0.22, 3, -1.6), Color3.fromRGB(230, 200, 60))
    eye(model, root, CFrame.new(0.22, 3, -1.6), Color3.fromRGB(230, 200, 60))

    for _, side in ipairs({-1, 1}) do
        limb(model, root, "Arm", Vector3.new(0.9, 6.2, 0.9), CFrame.new(side * 1.7, -0.3, -0.3) * CFrame.Angles(0, 0, side * 0.2), shell, Enum.Material.Slate, {Amount = 0.35, Phase = side})
        limb(model, root, "Leg", Vector3.new(0.8, 3.8, 1.2), CFrame.new(side * 0.7, -1.6, 0.15) * CFrame.Angles(0, 0, side * 0.12), shell, Enum.Material.Slate, {Amount = 0.4, Phase = -side})
    end
end

function BUILDERS.ElColoso(model, root)
    local hide = Color3.fromRGB(44, 42, 46)
    local plate = Color3.fromRGB(66, 62, 58)
    -- Cubierto de placas, encorvado, con brazos largos que cuelgan junto a las piernas.
    limb(model, root, "Torso", Vector3.new(4.4, 4.4, 3), CFrame.new(0, 1.8, 0) * CFrame.Angles(0.15, 0, 0), hide, Enum.Material.Slate)
    limb(model, root, "Plate", Vector3.new(5.6, 2.6, 3.8), CFrame.new(0, 3.7, 0.3) * CFrame.Angles(0.2, 0, 0), plate, Enum.Material.CorrodedMetal)
    limb(model, root, "Head", Vector3.new(1.8, 1.8, 2), CFrame.new(0, 3.3, -1.5), plate, Enum.Material.CorrodedMetal)
    eye(model, root, CFrame.new(-0.45, 3.4, -2.55), Color3.fromRGB(240, 110, 40))
    eye(model, root, CFrame.new(0.45, 3.4, -2.55), Color3.fromRGB(240, 110, 40))

    for _, side in ipairs({-1, 1}) do
        limb(model, root, "Arm", Vector3.new(1.6, 8.4, 1.8), CFrame.new(side * 2.8, -0.8, -0.2), hide, Enum.Material.Slate, {Amount = 0.28, Phase = side})
        limb(model, root, "Leg", Vector3.new(1.9, 5.6, 2), CFrame.new(side * 1.15, -2.7, 0.1), hide, Enum.Material.Slate, {Amount = 0.32, Phase = -side})
    end
end

-- Esqueleto con piel ---------------------------------------------------------------
-- Si ServerStorage.NocturnaModels tiene <Criatura>Rig (un Model con una MeshPart
-- con piel y sus huesos, importado de assets/models/rigged/<Criatura>.fbx), la
-- criatura es esa malla entera, soldada a la raíz, y el cliente mueve los huesos
-- (CreatureBones). Si no está o le faltan huesos, se arma con piezas como antes.

-- Root no es obligatorio: no pesa vértices y el importador puede descartarlo
-- (entonces se ubica por Hips, con su posición medida en Blender).
local REQUIRED_BONES = {"Hips", "Chest", "Head", "LeftThigh", "LeftShin", "LeftFoot", "RightThigh", "RightShin", "RightFoot"}
local warnedRig = {}

local function rigTemplate(kind)
    local folder = ServerStorage:FindFirstChild(MODELS_FOLDER)
    local template = folder and folder:FindFirstChild(kind .. "Rig")
    if not (template and template:IsA("Model")) then
        return nil
    end
    local bones = {}
    local skinned = false
    for _, item in ipairs(template:GetDescendants()) do
        if item:IsA("Bone") then
            bones[item.Name] = true
        elseif item:IsA("MeshPart") then
            skinned = true
        end
    end
    local missing = {}
    for _, name in ipairs(REQUIRED_BONES) do
        if not bones[name] then
            table.insert(missing, name)
        end
    end
    if not skinned or #missing > 0 then
        if not warnedRig[kind] then
            warnedRig[kind] = true
            warn("[NOCTURNA] " .. kind .. "Rig no sirve (" .. (skinned and "faltan huesos: " .. table.concat(missing, ", ") or "sin MeshPart")
                .. "): se arma con piezas.")
        end
        return nil
    end
    return template
end

-- CFrame en el mundo de un hueso en reposo (sin Transform): su pieza y la cadena
-- de huesos hasta él.
local function boneWorld(bone)
    local chain = {}
    local current = bone
    while current and current:IsA("Bone") do
        table.insert(chain, 1, current)
        current = current.Parent
    end
    local cframe = (current and current:IsA("BasePart")) and current.CFrame or CFrame.identity
    for _, item in ipairs(chain) do
        cframe = cframe * item.CFrame
    end
    return cframe
end

local function findBone(body, name)
    for _, item in ipairs(body:GetDescendants()) do
        if item:IsA("Bone") and item.Name == name then
            return item
        end
    end
    return nil
end

-- Ejes del esqueleto según sus huesos (no según cómo los ejes de cada hueso o el
-- frente que dejó el importador): arriba es +Y (el importador siempre deja Y
-- arriba) y el costado va de la cadera izquierda a la derecha; con eso el frente
-- queda definido (la criatura mira hacia -Z de esa base, como la raíz).
local function rigFrame(body, info)
    local root = findBone(body, "Root")
    local left, right = findBone(body, "LeftThigh"), findBone(body, "RightThigh")
    local side = boneWorld(right).Position - boneWorld(left).Position
    side = Vector3.new(side.X, 0, side.Z)
    if side.Magnitude < 1e-3 then
        return nil
    end
    local axes = CFrame.fromMatrix(Vector3.zero, side.Unit, Vector3.yAxis)
    local origin
    if root then
        origin = boneWorld(root).Position
    else
        local hips = info and info.Hips or Vector3.zero
        origin = boneWorld(findBone(body, "Hips")).Position - axes:VectorToWorldSpace(hips)
    end
    return CFrame.new(origin) * axes
end

-- Pieza invisible que sigue a un hueso (Head, Jaw): la cámara de la captura y los
-- efectos (luz de la boca, baba) se apoyan en ellas. El cliente mueve su Motor6D.
local function boneProxy(model, root, body, boneName, name, size)
    local bone = findBone(body, boneName)
    if not bone then
        return nil
    end
    local world = boneWorld(bone)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.Transparency = 1
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Massless = true
    part.Anchored = false
    -- Centrada sobre el hueso, con los ejes de la raíz.
    local offset = root.CFrame:ToObjectSpace(CFrame.new(world.Position)) * CFrame.new(0, size.Y * 0.35, 0)
    part.CFrame = root.CFrame * offset
    part.Parent = model
    local joint = Instance.new("Motor6D")
    joint.Name = name .. "Joint"
    joint.Part0 = root
    joint.Part1 = part
    joint.C0 = offset
    joint.C1 = CFrame.identity
    joint:SetAttribute("BoneProxy", boneName)
    -- Dónde está la pieza respecto del hueso en reposo (en ejes de la raíz).
    joint:SetAttribute("ProxyOffset", (root.CFrame:Inverse() * world):Inverse() * offset)
    joint.Parent = part
    return part
end

local function buildBoneRig(model, root, kind, template)
    local body = template:Clone()
    body.Name = "Body"
    for _, item in ipairs(body:GetDescendants()) do
        if item:IsA("Humanoid") or item:IsA("AnimationController") or item:IsA("Script") or item:IsA("LocalScript") then
            item:Destroy()
        end
    end

    -- Escala: el importador puede traerla en otras unidades (100 veces más grande
    -- si lee centímetros). Se compara la distancia de la cadera a la cabeza con la
    -- medida en Blender (CreatureRigs).
    local info = CreatureRigs[kind]
    local hipsBone, headBone = findBone(body, "Hips"), findBone(body, "Head")
    if info and info.Span and hipsBone and headBone then
        local measured = (boneWorld(headBone).Position - boneWorld(hipsBone).Position).Magnitude
        local ratio = measured > 1e-3 and info.Span / measured or 1
        if math.abs(ratio - 1) > 0.03 then
            local ok = pcall(function()
                body:ScaleTo(body:GetScale() * ratio)
            end)
            if not ok then
                warn("[NOCTURNA] No se pudo escalar " .. kind .. "Rig (x" .. string.format("%.3f", ratio) .. ").")
            end
        end
    end

    -- Ubicación: el hueso Root va sobre la raíz, mirando hacia donde mira ella.
    local frame = rigFrame(body, info)
    if not frame then
        body:Destroy()
        return false
    end
    local folder = ServerStorage:FindFirstChild(MODELS_FOLDER)
    local turn = folder and (folder:GetAttribute("RigTurnAround") == true) and CFrame.Angles(0, math.pi, 0) or CFrame.identity
    local move = root.CFrame * turn * frame:Inverse()
    local parts = {}
    for _, item in ipairs(body:GetDescendants()) do
        if item:IsA("BasePart") then
            table.insert(parts, item)
        end
    end
    for _, part in ipairs(parts) do
        part.CFrame = move * part.CFrame
    end

    -- La SurfaceAppearance de la carpeta de la criatura (la de las piezas) viste
    -- también la malla con piel si el importador no le puso una.
    local _, set = modelSet(model)
    local shared = set and set:FindFirstChildWhichIsA("SurfaceAppearance")
    for _, part in ipairs(parts) do
        part.Anchored = false
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.Massless = true
        part.CastShadow = false
        if part:IsA("MeshPart") and shared and not part:FindFirstChildWhichIsA("SurfaceAppearance") then
            shared:Clone().Parent = part
        end
        part:SetAttribute("RigOffset", root.CFrame:Inverse() * part.CFrame)
        local weld = Instance.new("WeldConstraint")
        weld.Name = "RigWeld"
        weld.Part0 = root
        weld.Part1 = part
        weld.Parent = part
    end
    body.Parent = model

    -- Piezas invisibles para la cámara y los efectos de la cabeza y la boca.
    local headSize = math.clamp(info and info.HeadSize or 1, 0.6, 2.5)
    boneProxy(model, root, body, "Head", "Head", Vector3.new(headSize * 0.8, headSize, headSize * 0.9))
    if findBone(body, "Jaw") then
        boneProxy(model, root, body, "Jaw", "Jaw", Vector3.new(headSize * 0.45, headSize * 0.3, headSize * 0.4))
    end
    model:SetAttribute("BoneRig", true)
    return true
end

function MonsterFactory.Build(kind, parent, height)
    local builder = BUILDERS[kind]
    assert(builder, "[NOCTURNA] Criatura sin modelo: " .. tostring(kind))

    local model, root = newRoot(parent, kind, height)
    model:SetAttribute("ModelSet", kind)
    local template = rigTemplate(kind)
    if not (template and buildBoneRig(model, root, kind, template)) then
        builder(model, root)
    end
    model:SetAttribute("Kind", kind)
    model:SetAttribute("MoveSpeed", 0)
    CollectionService:AddTag(model, "NocturnaMonster")
    return model, root
end

-- Maniquí inerte, idéntico a El Quieto: el escenario esconde a la criatura.
function MonsterFactory.BuildMannequin(parent, cframe)
    local model, root = newRoot(parent, "Mannequin", 3.6)
    model:SetAttribute("ModelSet", "ElQuieto")
    root.CFrame = cframe * CFrame.new(0, 3.6, 0)
    local template = rigTemplate("ElQuieto")
    if not (template and buildBoneRig(model, root, "ElQuieto", template)) then
        buildMannequinBody(model, root)
    end
    return model
end

return MonsterFactory
