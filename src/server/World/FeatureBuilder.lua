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

local AlmaBuilder = require(script.Parent.AlmaBuilder)

local FeatureBuilder = {}

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

-- Alma la arma AlmaBuilder (área de criaturas): una nena de verdad que se alegra
-- al ver al grupo y lo sigue. El cartel va en el ancla que la acompaña.
function FeatureBuilder.Sister(parent, feature, cframe)
    local holder, host = AlmaBuilder.Build(parent, feature, cframe)
    return holder, FeatureBuilder.AddPrompt(host, feature.Prompt, "Alma", feature.Hold), nil
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
