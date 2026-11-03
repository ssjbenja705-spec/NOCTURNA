-- Generadores, terminales, válvulas, Núcleo y salidas de cada capítulo.
local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local ItemConfig = require(Shared.Config.ItemConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local NoiseService = require(script.Parent.Parent.AI.NoiseService)
local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local InventoryService = require(script.Parent.Parent.Inventory.InventoryService)
local FeatureBuilder = require(script.Parent.FeatureBuilder)
local InteractionService = require(script.Parent.InteractionService)
local RoomGenerator = require(script.Parent.RoomGenerator)

local DONE_COLOR = Color3.fromRGB(70, 190, 110)

local MechanismService = {}
local mechanisms = {}
local flagCounts = {}

local function deny(player, text)
    Remotes.FireClient("StoryNotice", player, text)
end

local function finish(mechanism, player)
    local feature = mechanism.Feature
    mechanism.Done = true
    mechanism.Prompt.Enabled = false
    if mechanism.Indicator then
        mechanism.Indicator.Color = DONE_COLOR
    end

    if feature.Flag then
        GameState.SetFlag(feature.Flag)
        EventBus.Emit("FlagSet", feature.Flag)
    end

    if feature.CountFlag then
        local flag = feature.CountFlag
        flagCounts[flag.Name] = (flagCounts[flag.Name] or 0) + 1
        if flagCounts[flag.Name] >= flag.Needed then
            GameState.SetFlag(flag.Name)
            EventBus.Emit("FlagSet", flag.Name)
        end
    end

    EventBus.Emit("FeatureActivated", player, feature)
end

local function startGenerator(mechanism, player)
    local position = mechanism.Model.PrimaryPart.Position
    NoiseService.Emit(position, GameConfig.Noise.Machine, player)
    Remotes.FireAll("PlaySound", "MachineStart", position)
    Remotes.FireAll("StoryNotice", player.DisplayName .. " encendió " .. mechanism.Feature.Label)
    finish(mechanism, player)
end

local function useGenerator(mechanism, player)
    local feature = mechanism.Feature

    if mechanism.Inserted >= feature.Fuses then
        startGenerator(mechanism, player)
        return
    end

    if not InventoryService.RemoveItem(player, "Fuse", 1) then
        deny(player, "Necesitás un fusible.")
        return
    end

    mechanism.Inserted += 1
    Remotes.FireAll("PlaySound", "Metal", mechanism.Model.PrimaryPart.Position)

    if mechanism.Inserted >= feature.Fuses then
        mechanism.Prompt.ActionText = "Arrancar"
        mechanism.Prompt.HoldDuration = 3
    end
    mechanism.Prompt.ObjectText = string.format("%s (%d/%d)", feature.Label, mechanism.Inserted, feature.Fuses)
end

local function checkRequirements(mechanism, player)
    local feature = mechanism.Feature

    if feature.RequiresFlag and not GameState.HasFlag(feature.RequiresFlag) then
        deny(player, feature.DeniedText or "Todavía no funciona.")
        return false
    end

    local tracker = GameState.Tracker
    if feature.RequiresObjective and tracker and not tracker:IsDone(feature.RequiresObjective) then
        deny(player, feature.DeniedText or "Todavía no funciona.")
        return false
    end

    return true
end

local function useTerminal(mechanism, player)
    local feature = mechanism.Feature
    local itemId = feature.RequiredItem

    if itemId then
        local amount = feature.RequiredAmount or 1
        local have = InventoryService.CountParty(itemId)
        if have < amount then
            deny(player, feature.DeniedText or ("Falta: " .. ItemConfig[itemId].DisplayName))
            return
        end
        if not feature.KeepItem and not InventoryService.RemoveFromParty(player, itemId, amount) then
            return
        end
    end

    finish(mechanism, player)
end

local function useValve(mechanism, player)
    Remotes.FireAll("PlaySound", "Metal", mechanism.Model.PrimaryPart.Position)
    NoiseService.Emit(mechanism.Model.PrimaryPart.Position, GameConfig.Noise.Door, player)
    finish(mechanism, player)
end

local function useCore(mechanism, player)
    Remotes.FireAll("PlaySound", "Collapse", mechanism.Model.PrimaryPart.Position)
    NoiseService.Emit(mechanism.Model.PrimaryPart.Position, GameConfig.Noise.Machine, player)
    finish(mechanism, player)
end

-- Una salida sólo funciona cuando es el objetivo actual, para no saltear la historia.
local function useExit(mechanism, player)
    local tracker = GameState.Tracker
    local current = tracker and tracker:Current()
    if not current or current.Target ~= mechanism.Feature.Id then
        deny(player, mechanism.Feature.DeniedText or "Todavía no podés irte. Queda algo por hacer.")
        return
    end
    finish(mechanism, player)
end

local HANDLERS = {
    Generator = useGenerator,
    Terminal = useTerminal,
    Valve = useValve,
    Core = useCore,
    Exit = useExit,
    Sister = useExit,
}

local BUILDERS = {
    Generator = FeatureBuilder.Generator,
    Terminal = FeatureBuilder.Terminal,
    Valve = FeatureBuilder.Valve,
    Core = FeatureBuilder.Core,
    Exit = FeatureBuilder.Exit,
    Sister = FeatureBuilder.Sister,
}

function MechanismService.Populate(plan, map)
    table.clear(mechanisms)
    table.clear(flagCounts)

    local folder = Instance.new("Folder")
    folder.Name = "Mechanisms"
    folder.Parent = map

    for _, feature in ipairs(plan.Features) do
        local cframe = RoomGenerator.SlotCFrame(plan.Layout, feature.Cell, feature.Slot)
        local holder, prompt, indicator = BUILDERS[feature.Kind](folder, feature, cframe)
        local mechanism = {
            Feature = feature,
            Model = holder,
            Prompt = prompt,
            Indicator = indicator,
            Inserted = 0,
            Done = false,
        }
        table.insert(mechanisms, mechanism)

        InteractionService.Bind(prompt, function(player)
            if mechanism.Done or not checkRequirements(mechanism, player) then
                return
            end
            HANDLERS[feature.Kind](mechanism, player)
        end)
    end
end

function MechanismService.Clear()
    table.clear(mechanisms)
    table.clear(flagCounts)
end

-- Posiciones pendientes de un objetivo, por Id o por grupo.
function MechanismService.PositionsFor(target)
    local result = {}
    for _, mechanism in ipairs(mechanisms) do
        local feature = mechanism.Feature
        if not mechanism.Done and (feature.Id == target or feature.Group == target) then
            table.insert(result, mechanism.Model.PrimaryPart.Position)
        end
    end
    return result
end

return MechanismService
