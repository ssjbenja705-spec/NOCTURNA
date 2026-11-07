-- Modelos procedurales de objetos, máquinas, escondites y utilería.
-- Los modelos detallados viven en ItemModels, MachineModels, HideModels y RoomDecor;
-- este módulo es la puerta de entrada que usan los servicios.
local Shared = game:GetService("ReplicatedStorage").Shared
local ItemConfig = require(Shared.Config.ItemConfig)
local Rng = require(Shared.Logic.Rng)

local HideModels = require(script.Parent.HideModels)
local ItemModels = require(script.Parent.ItemModels)
local MachineModels = require(script.Parent.MachineModels)
local PropKit = require(script.Parent.PropKit)
local RoomDecor = require(script.Parent.RoomDecor)

local FeatureBuilder = {}

local function part(parent, name, size, offset, color, material, shape)
    local item = Instance.new("Part")
    item.Name = name
    item.Size = size
    item.CFrame = offset
    item.Anchored = true
    item.Color = color
    item.Material = material or Enum.Material.Metal
    item.TopSurface = Enum.SurfaceType.Smooth
    item.BottomSurface = Enum.SurfaceType.Smooth
    item.CanTouch = false
    item.CastShadow = false
    if shape then
        item.Shape = shape
    end
    item.Parent = parent
    return item
end

local function model(parent, name)
    local item = Instance.new("Model")
    item.Name = name
    item.Parent = parent
    return item
end

FeatureBuilder.AddPrompt = PropKit.AddPrompt

function FeatureBuilder.Pickup(parent, itemId, cframe)
    local holder = ItemModels.Build(parent, itemId, cframe)
    return holder, PropKit.AddPrompt(holder, "Recoger", ItemConfig[itemId].DisplayName, 0.3)
end

function FeatureBuilder.Document(parent, title, cframe)
    return MachineModels.Document(parent, title, cframe)
end

FeatureBuilder.Generator = MachineModels.Generator
FeatureBuilder.Terminal = MachineModels.Terminal
FeatureBuilder.Valve = MachineModels.Valve
FeatureBuilder.Core = MachineModels.Core

function FeatureBuilder.Exit(parent, feature, cframe)
    return MachineModels.Exit(parent, feature, cframe)
end

function FeatureBuilder.Sister(parent, feature, cframe)
    local holder = model(parent, feature.Id)
    local skin = Color3.fromRGB(216, 190, 165)
    local hospital = Color3.fromRGB(200, 205, 205)

    local chair = part(
        holder,
        "Chair",
        Vector3.new(4, 2, 4),
        cframe * CFrame.new(0, 1, 0),
        Color3.fromRGB(70, 56, 48),
        Enum.Material.WoodPlanks
    )
    holder.PrimaryPart = chair
    part(holder, "Torso", Vector3.new(2, 2.4, 1), cframe * CFrame.new(0, 3.2, 0.4), hospital, Enum.Material.Fabric)
    part(holder, "Head", Vector3.new(1.3, 1.3, 1.3), cframe * CFrame.new(0, 5.1, 0.4), skin, Enum.Material.SmoothPlastic)
    part(holder, "Hair", Vector3.new(1.5, 1.5, 0.8), cframe * CFrame.new(0, 5.2, 0.8), Color3.fromRGB(50, 34, 26), Enum.Material.Fabric)
    part(holder, "ArmLeft", Vector3.new(0.7, 2.2, 0.7), cframe * CFrame.new(-1.4, 3.2, 0.2), hospital, Enum.Material.Fabric)
    part(holder, "ArmRight", Vector3.new(0.7, 2.2, 0.7), cframe * CFrame.new(1.4, 3.2, 0.2), hospital, Enum.Material.Fabric)
    part(holder, "Legs", Vector3.new(2, 1, 2.4), cframe * CFrame.new(0, 2.4, -0.8), hospital, Enum.Material.Fabric)

    for index = 1, 3 do
        local cable = part(
            holder,
            "Cable",
            Vector3.new(0.25, 7, 0.25),
            cframe * CFrame.new((index - 2) * 0.7, 9, 1) * CFrame.Angles(0.15, 0, 0),
            Color3.fromRGB(90, 30, 45),
            Enum.Material.SmoothPlastic
        )
        cable.CanCollide = false
    end

    local glow = Instance.new("PointLight")
    glow.Color = Color3.fromRGB(255, 220, 180)
    glow.Brightness = 1
    glow.Range = 16
    glow.Shadows = false
    glow.Parent = chair

    return holder, FeatureBuilder.AddPrompt(chair, feature.Prompt, "Alma", feature.Hold), chair
end

function FeatureBuilder.Locker(parent, cframe)
    local holder, prompt = HideModels.Build(parent, "Locker", cframe)
    return holder, prompt
end

-- Escondite de cualquier tipo (Locker, Wardrobe, Desk, Bed, Vent): devuelve el
-- modelo, el prompt y la especificación de cámara, interior y salida.
FeatureBuilder.Hide = HideModels.Build

-- Nombre de la malla de NocturnaProps que reemplaza a cada utilería de rincón.
local CORNER_MESHES = {
    Pipe = "CornerPipe",
    Growth = "GrowthMass",
    Tank = "SpecimenTank",
}

-- Utilería de rincón. `theme` y `rng` son opcionales.
function FeatureBuilder.Prop(parent, kind, cframe, theme, rng)
    local builder = RoomDecor.Corner[kind]
    if not builder then
        return nil
    end

    local holder = model(parent, kind)
    local palette = RoomDecor.Palette(theme or {})
    rng = rng or Rng.new(math.floor(cframe.Position.X * 31 + cframe.Position.Z))
    local meshName = CORNER_MESHES[kind] or kind
    if PropKit.Boxes[meshName] then
        PropKit.Visual(holder, meshName, cframe, function(target)
            builder(target, cframe, palette, rng)
        end)
    else
        builder(holder, cframe, palette, rng)
    end
    return holder
end

FeatureBuilder.PropKinds = RoomDecor.Corner

return FeatureBuilder
