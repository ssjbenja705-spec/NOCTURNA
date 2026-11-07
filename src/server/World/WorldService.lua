-- Carga cada capítulo: genera el plan, lo valida, construye el mapa y controla la luz.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage").Shared
local ChapterConfig = require(Shared.Config.ChapterConfig)
local GameConfig = require(Shared.Config.GameConfig)
local ThemeConfig = require(Shared.Config.ThemeConfig)
local LayoutPlanner = require(Shared.Logic.LayoutPlanner)
local MazeLayout = require(Shared.Logic.MazeLayout)
local MazeNav = require(Shared.Logic.MazeNav)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local DoorService = require(script.Parent.DoorService)
local EnvironmentService = require(script.Parent.EnvironmentService)
local FeatureBuilder = require(script.Parent.FeatureBuilder)
local HidingService = require(script.Parent.HidingService)
local InteractionService = require(script.Parent.InteractionService)
local MapService = require(script.Parent.MapService)
local MechanismService = require(script.Parent.MechanismService)
local RoomGenerator = require(script.Parent.RoomGenerator)

local MAX_ATTEMPTS = 24
local POWER_FLAGS = {POWER = true, CORE_POWER = true}

local WorldService = {}
local currentTheme = nil

local function applyAtmosphere(theme)
    Lighting.Ambient = theme.Ambient
    Lighting.OutdoorAmbient = theme.Ambient
    Lighting.FogColor = theme.FogColor
    Lighting.FogStart = 6
    Lighting.FogEnd = theme.FogEnd
end

local function generatePlan(chapterIndex, seed)
    local spec = ChapterConfig[chapterIndex].Layout
    local lastError = nil

    for attempt = 0, MAX_ATTEMPTS do
        local success, result = pcall(function()
            local layout = MazeLayout.Generate({
                Width = spec.Width,
                Depth = spec.Depth,
                Seed = seed + attempt * 131,
                LoopChance = spec.LoopChance,
                ReservedLeaves = spec.LockedRooms and #spec.LockedRooms or 0,
            })
            return LayoutPlanner.Plan(layout, spec)
        end)

        if success then
            local valid, reason = LayoutPlanner.Validate(result)
            if valid then
                return result
            end
            lastError = reason
        else
            lastError = result
        end
    end

    error("[NOCTURNA] No se pudo generar el capítulo " .. chapterIndex .. ": " .. tostring(lastError))
end

local function decorate(plan, theme, map)
    local layout = plan.Layout
    local rng = layout.Rng
    local kinds = theme.PropSet
    if #kinds == 0 then
        return
    end

    local folder = Instance.new("Folder")
    folder.Name = "Props"

    for _, cell in ipairs(layout.Cells) do
        while #cell.Slots > 0 and rng:Chance(0.55) do
            local slot = table.remove(cell.Slots, rng:Int(1, #cell.Slots))
            FeatureBuilder.Prop(folder, rng:Pick(kinds), RoomGenerator.SlotCFrame(layout, cell.Index, slot))
        end
    end

    folder.Parent = map
end

local function placeMannequins(plan, map)
    if #plan.Mannequins == 0 then
        return
    end

    local MonsterFactory = require(script.Parent.Parent.Monsters.MonsterFactory)
    local folder = Instance.new("Folder")
    folder.Name = "Mannequins"
    folder.Parent = map

    for _, entry in ipairs(plan.Mannequins) do
        local cframe = RoomGenerator.SlotCFrame(plan.Layout, entry.Cell, entry.Slot)
        MonsterFactory.BuildMannequin(folder, cframe)
    end
end

function WorldService.SetPower(enabled)
    GameState.Powered = enabled
    local theme = currentTheme
    if not theme then
        return
    end

    for _, fixture in ipairs(CollectionService:GetTagged("NocturnaLight")) do
        local light = fixture:FindFirstChildOfClass("PointLight")
        if light then
            light.Color = enabled and theme.Light or theme.EmergencyLight
            light.Brightness = enabled and 0.9 or 0.35
            light.Range = enabled and 26 or 16
        end
    end
end

-- Devuelve si una posición tiene luz encendida en este momento.
function WorldService.IsLit(position)
    local nav = GameState.Nav
    if not nav or not GameState.Powered then
        return false
    end

    local cell = nav:CellAt(position)
    for _, fixture in ipairs(CollectionService:GetTagged("NocturnaLight")) do
        if fixture:GetAttribute("Cell") == cell then
            return fixture:GetAttribute("Dark") ~= true
        end
    end
    return false
end

function WorldService.LoadChapter(chapterIndex, seed)
    local chapter = ChapterConfig[chapterIndex]
    local theme = ThemeConfig[chapter.Theme]
    local plan = generatePlan(chapterIndex, seed)

    currentTheme = theme
    GameState.Plan = plan
    GameState.Layout = plan.Layout
    GameState.Nav = MazeNav.new(plan.Layout, GameConfig.Map.CellSize)

    EnvironmentService.Clear()
    applyAtmosphere(theme)

    local map = RoomGenerator.Build(plan, theme)
    InteractionService.Populate(plan, map)
    DoorService.Populate(plan, map)
    MechanismService.Populate(plan, map)
    HidingService.Populate(plan, map)
    placeMannequins(plan, map)
    decorate(plan, theme, map)
    WorldService.SetPower(theme.StartsPowered)
    MapService.Begin(plan)

    return plan
end

function WorldService.Unload()
    local map = workspace:FindFirstChild("NOCTURNA_MAP")
    if map then
        map:Destroy()
    end

    InteractionService.Clear()
    DoorService.Clear()
    MechanismService.Clear()
    EnvironmentService.Clear()
    MapService.Clear()
    GameState.ResetChapter()
    currentTheme = nil
    applyAtmosphere(ThemeConfig.Lobby)
end

function WorldService.Start()
    Lighting.ClockTime = 0
    Lighting.Brightness = 0.6
    Lighting.GlobalShadows = true
    Lighting.EnvironmentDiffuseScale = 0
    Lighting.EnvironmentSpecularScale = 0
    applyAtmosphere(ThemeConfig.Lobby)

    EventBus.On("FlagSet", function(flag)
        if POWER_FLAGS[flag] then
            WorldService.SetPower(true)
        end
    end)
end

return WorldService
