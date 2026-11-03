-- Construye las criaturas. La raíz va anclada y las extremidades cuelgan de
-- Motor6D que el cliente anima.
--
-- Cada pieza usa la malla de Blender importada en ServerStorage.NocturnaModels
-- (ver assets/models/README.md) si existe; si no, una Part simple del mismo tamaño.
-- Así el juego funciona igual con o sin los modelos importados.
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local MODELS_FOLDER = "NocturnaModels"

local MonsterFactory = {}

local function meshTemplate(model, name)
    local folder = ServerStorage:FindFirstChild(MODELS_FOLDER)
    local set = folder and folder:FindFirstChild(model:GetAttribute("ModelSet") or "")
    local template = set and set:FindFirstChild(name, true)
    if template and template:IsA("MeshPart") then
        -- TurnAround corrige un importador que deje las mallas mirando hacia atrás.
        return template, folder:GetAttribute("TurnAround") == true
    end
    return nil, false
end

-- Una malla con textura propia conserva su aspecto; si no, toma color y material.
local function hasOwnLook(part)
    return part.TextureID ~= "" or part:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil
end

local function newPart(model, name)
    local template, turnAround = meshTemplate(model, name)
    if not template then
        return Instance.new("Part"), false, false
    end

    local part = template:Clone()
    for _, child in ipairs(part:GetChildren()) do
        if not child:IsA("SurfaceAppearance") then
            child:Destroy()
        end
    end
    part.Anchored = false
    return part, hasOwnLook(part), turnAround
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

local function limb(model, root, name, size, offset, color, material, swing)
    local part, ownLook, turnAround = newPart(model, name)
    local turn = turnAround and CFrame.Angles(0, math.pi, 0) or CFrame.identity
    part.Name = name
    part.Size = size
    part.CFrame = root.CFrame * offset * turn
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
    joint.C0 = offset
    joint.C1 = turn:Inverse()
    joint.Parent = part

    if swing then
        joint:SetAttribute("SwingAmount", swing.Amount)
        joint:SetAttribute("SwingPhase", swing.Phase or 0)
        joint:SetAttribute("SwingAxis", swing.Axis or "X")
    end

    return part
end

local function eye(model, root, offset, color)
    return limb(model, root, "Eye", Vector3.new(0.3, 0.2, 0.15), offset, color, Enum.Material.Neon)
end

local BUILDERS = {}

function BUILDERS.ElOyente(model, root)
    local skin = Color3.fromRGB(128, 120, 112)
    local dark = Color3.fromRGB(48, 44, 42)
    limb(model, root, "Torso", Vector3.new(1.6, 4.6, 1), CFrame.new(0, 0.6, 0) * CFrame.Angles(0.25, 0, 0), skin, Enum.Material.Slate)
    limb(model, root, "Head", Vector3.new(1.3, 2, 1.4), CFrame.new(0, 3.4, -0.9), skin, Enum.Material.Slate)
    limb(model, root, "Mouth", Vector3.new(0.9, 0.5, 0.2), CFrame.new(0, 3, -1.6), dark, Enum.Material.SmoothPlastic)

    for _, side in ipairs({-1, 1}) do
        limb(model, root, "Ear", Vector3.new(0.3, 2, 1.6), CFrame.new(side * 0.9, 3.8, -0.8) * CFrame.Angles(0, 0, side * 0.3), skin, Enum.Material.Slate, {Amount = 0.1, Axis = "Z", Phase = side})
        limb(model, root, "Arm", Vector3.new(0.5, 5.4, 0.5), CFrame.new(side * 1.2, -0.4, -0.2), dark, Enum.Material.Slate, {Amount = 0.4, Phase = side})
        limb(model, root, "Leg", Vector3.new(0.6, 3.4, 0.6), CFrame.new(side * 0.5, -2.3, 0), dark, Enum.Material.Slate, {Amount = 0.5, Phase = -side})
    end
end

function BUILDERS.ElImitador(model, root)
    local void = Color3.fromRGB(10, 10, 12)
    limb(model, root, "Torso", Vector3.new(2, 2.6, 1), CFrame.new(0, 0.6, 0), void, Enum.Material.Fabric)
    limb(model, root, "Head", Vector3.new(1.2, 1.4, 1.2), CFrame.new(0, 2.7, 0), void, Enum.Material.SmoothPlastic)
    limb(model, root, "Jaw", Vector3.new(0.8, 1.4, 0.2), CFrame.new(0, 2.2, -0.65), Color3.fromRGB(190, 30, 40), Enum.Material.Neon, {Amount = 0.25})

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
        limb(model, root, "Arm", Vector3.new(0.7, 3, 0.7), CFrame.new(side * 1.4, 0.4, 0), body, Enum.Material.SmoothPlastic)
        limb(model, root, "Leg", Vector3.new(0.8, 3, 0.8), CFrame.new(side * 0.5, -2.1, 0), body, Enum.Material.SmoothPlastic)
    end
end

function BUILDERS.ElQuieto(model, root)
    buildMannequinBody(model, root)
    eye(model, root, CFrame.new(-0.3, 2.9, -0.68), Color3.fromRGB(20, 20, 20))
    eye(model, root, CFrame.new(0.3, 2.9, -0.68), Color3.fromRGB(20, 20, 20))
end

function BUILDERS.ElTrepador(model, root)
    local flesh = Color3.fromRGB(70, 24, 30)
    limb(model, root, "Body", Vector3.new(3, 1.4, 4), CFrame.new(0, 0, 0), flesh, Enum.Material.Slate)
    limb(model, root, "Head", Vector3.new(1.4, 1, 1.6), CFrame.new(0, 0.1, -2.6), flesh, Enum.Material.Slate)
    eye(model, root, CFrame.new(-0.4, 0.3, -3.4), Color3.fromRGB(230, 200, 60))
    eye(model, root, CFrame.new(0.4, 0.3, -3.4), Color3.fromRGB(230, 200, 60))

    for row = -1, 1 do
        for _, side in ipairs({-1, 1}) do
            limb(
                model,
                root,
                "Leg",
                Vector3.new(4.4, 0.4, 0.4),
                CFrame.new(side * 3, -0.5, row * 1.5) * CFrame.Angles(0, 0, side * 0.35),
                Color3.fromRGB(40, 16, 20),
                Enum.Material.Slate,
                {Amount = 0.45, Axis = "Y", Phase = row + side}
            )
        end
    end
end

function BUILDERS.ElColoso(model, root)
    local hide = Color3.fromRGB(44, 42, 46)
    local plate = Color3.fromRGB(66, 62, 58)
    limb(model, root, "Torso", Vector3.new(7, 5, 4), CFrame.new(0, 1, 0) * CFrame.Angles(0.2, 0, 0), hide, Enum.Material.Slate)
    limb(model, root, "Plate", Vector3.new(7.6, 2.4, 4.6), CFrame.new(0, 2.8, 0.2) * CFrame.Angles(0.2, 0, 0), plate, Enum.Material.CorrodedMetal)
    limb(model, root, "Head", Vector3.new(2.4, 2, 2.4), CFrame.new(0, 2.2, -2.8), plate, Enum.Material.CorrodedMetal)
    eye(model, root, CFrame.new(-0.6, 2.3, -4.05), Color3.fromRGB(240, 110, 40))
    eye(model, root, CFrame.new(0.6, 2.3, -4.05), Color3.fromRGB(240, 110, 40))

    for _, side in ipairs({-1, 1}) do
        limb(model, root, "Arm", Vector3.new(1.9, 6.4, 1.9), CFrame.new(side * 4.4, -0.8, -0.4), hide, Enum.Material.Slate, {Amount = 0.28, Phase = side})
        limb(model, root, "Leg", Vector3.new(2.2, 3.6, 2.2), CFrame.new(side * 1.9, -3.2, 0), hide, Enum.Material.Slate, {Amount = 0.32, Phase = -side})
    end
end

function MonsterFactory.Build(kind, parent, height)
    local builder = BUILDERS[kind]
    assert(builder, "[NOCTURNA] Criatura sin modelo: " .. tostring(kind))

    local model, root = newRoot(parent, kind, height)
    model:SetAttribute("ModelSet", kind)
    builder(model, root)
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
    buildMannequinBody(model, root)
    return model
end

return MonsterFactory
