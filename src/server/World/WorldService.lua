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
local Rng = require(Shared.Logic.Rng)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local DoorService = require(script.Parent.DoorService)
local EnvironmentService = require(script.Parent.EnvironmentService)
local FeatureBuilder = require(script.Parent.FeatureBuilder)
local HidingService = require(script.Parent.HidingService)
local InteractionService = require(script.Parent.InteractionService)
local MapService = require(script.Parent.MapService)
local MechanismService = require(script.Parent.MechanismService)
local PropKit = require(script.Parent.PropKit)
local RoomGenerator = require(script.Parent.RoomGenerator)

local MAX_ATTEMPTS = 24
local POWER_FLAGS = {POWER = true, CORE_POWER = true}

-- Tope de piezas por capítulo para que corra en celulares (el objetivo es < 2500).
local PART_BUDGET = 2400

local WorldService = {}
WorldService.PartBudget = PART_BUDGET
local currentTheme = nil
-- Celda → lámpara de techo del capítulo cargado. IsLit se consulta por jugador en
-- cada paso de la IA: así no recorre todas las lámparas cada vez.
local lightByCell = {}

-- Busca el efecto por nombre (puede venir del proyecto) o lo crea.
local function effect(className, name)
    local existing = Lighting:FindFirstChild(name)
    if existing and existing.ClassName == className then
        return existing
    end
    local created = Instance.new(className)
    created.Name = name
    created.Parent = Lighting
    return created
end

-- Luz realista y un poco más clara: sin linterna se distinguen las formas, pero la
-- oscuridad sigue mandando. Technology = Future se fija en default.project.json.
local function applyAtmosphere(theme)
    local settings = theme.Lighting or ThemeConfig.Lobby.Lighting

    Lighting.Ambient = theme.Ambient
    Lighting.OutdoorAmbient = theme.Ambient
    Lighting.FogColor = theme.FogColor
    Lighting.FogStart = 6
    Lighting.FogEnd = theme.FogEnd
    Lighting.ExposureCompensation = settings.Exposure
    Lighting.EnvironmentDiffuseScale = settings.DiffuseScale
    Lighting.EnvironmentSpecularScale = settings.SpecularScale

    local atmosphere = effect("Atmosphere", "NocturnaAtmosphere")
    atmosphere.Density = settings.Atmosphere.Density
    atmosphere.Offset = settings.Atmosphere.Offset
    atmosphere.Color = settings.Atmosphere.Color
    atmosphere.Decay = settings.Atmosphere.Decay
    atmosphere.Glare = settings.Atmosphere.Glare
    atmosphere.Haze = settings.Atmosphere.Haze

    local bloom = effect("BloomEffect", "NocturnaBloom")
    bloom.Intensity = settings.Bloom.Intensity
    bloom.Size = settings.Bloom.Size
    bloom.Threshold = settings.Bloom.Threshold

    local grade = effect("ColorCorrectionEffect", "NocturnaGrade")
    grade.Brightness = settings.Grade.Brightness
    grade.Contrast = settings.Grade.Contrast
    grade.Saturation = settings.Grade.Saturation
    grade.TintColor = settings.Grade.Tint

    local depth = effect("DepthOfFieldEffect", "NocturnaDepth")
    depth.FarIntensity = settings.Depth.FarIntensity
    depth.FocusDistance = settings.Depth.FocusDistance
    depth.InFocusRadius = settings.Depth.InFocusRadius
    depth.NearIntensity = settings.Depth.NearIntensity
end

WorldService.ApplyAtmosphere = applyAtmosphere

-- Plan completo de un capítulo: el del capítulo más los escondites extra y los
-- pasadizos del tema. Se valida todo junto.
function WorldService.PlanChapter(chapterIndex, seed)
    local chapter = ChapterConfig[chapterIndex]
    local spec = chapter.Layout
    local theme = ThemeConfig[chapter.Theme] or {}
    local layout = MazeLayout.Generate({
        Width = spec.Width,
        Depth = spec.Depth,
        Seed = seed,
        LoopChance = spec.LoopChance,
        ReservedLeaves = spec.LockedRooms and #spec.LockedRooms or 0,
    })
    local plan = LayoutPlanner.Plan(layout, spec)
    LayoutPlanner.AddHides(plan, theme.ExtraHides or 0)
    LayoutPlanner.AddPassages(plan, theme.Passages or 0)
    return plan
end

function WorldService.ValidatePlan(plan)
    local valid, reason = LayoutPlanner.Validate(plan)
    if not valid then
        return false, reason
    end
    return LayoutPlanner.ValidatePassages(plan)
end

local function generatePlan(chapterIndex, seed)
    local lastError = nil

    for attempt = 0, MAX_ATTEMPTS do
        local success, result = pcall(WorldService.PlanChapter, chapterIndex, seed + attempt * 131)

        if success then
            local valid, reason = WorldService.ValidatePlan(result)
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

local function countParts(root)
    local count = 0
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("BasePart") then
            count += 1
        end
    end
    return count
end

WorldService.CountParts = countParts

-- Utilería en los rincones que quedaron libres, mientras alcance el presupuesto.
local function decorate(plan, theme, map)
    local layout = plan.Layout
    local rng = layout.Rng
    local kinds = theme.PropSet
    if #kinds == 0 then
        return
    end

    local folder = Instance.new("Folder")
    folder.Name = "Props"
    local decorRng = Rng.new((layout.Seed or 0) * 5 + 1)

    for _, cell in ipairs(layout.Cells) do
        while #cell.Slots > 0 and rng:Chance(0.55) and PropKit.Fits(14) do
            local slot = table.remove(cell.Slots, rng:Int(1, #cell.Slots))
            FeatureBuilder.Prop(folder, rng:Pick(kinds), RoomGenerator.SlotCFrame(layout, cell.Index, slot), theme, decorRng)
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

local UNPOWERED_BULB = 0.45
-- Sin energía queda la luz de emergencia: más débil y más corta.
local UNPOWERED_LIGHT = 0.45
local UNPOWERED_RANGE = 0.65

function WorldService.SetPower(enabled)
    GameState.Powered = enabled
    local theme = currentTheme
    if not theme then
        return
    end

    for _, fixture in ipairs(CollectionService:GetTagged("NocturnaLight")) do
        -- Cada sala tiene su intensidad (normal, tenue o titilante): se respeta.
        local brightness = fixture:GetAttribute("BaseBrightness") or 1
        local range = fixture:GetAttribute("BaseRange") or 28
        local color = fixture:GetAttribute("BaseColor") or theme.Light
        local current = enabled and color or theme.EmergencyLight
        local light = fixture:FindFirstChildOfClass("PointLight")
        if light then
            light.Color = current
            light.Brightness = enabled and brightness or brightness * UNPOWERED_LIGHT
            light.Range = enabled and range or range * UNPOWERED_RANGE
        end
        local shaft = fixture:FindFirstChild("LightShaft")
        if shaft and shaft:IsA("Beam") then
            shaft.Color = ColorSequence.new(current)
        end
        -- La lámpara misma también cambia: blanca con energía, roja de emergencia sin.
        fixture.Color = enabled and color or PropKit.Shade(theme.EmergencyLight, UNPOWERED_BULB)
    end
end

-- Arma el índice de lámparas por celda (la primera de cada una, como antes).
local function indexLights()
    table.clear(lightByCell)
    for _, fixture in ipairs(CollectionService:GetTagged("NocturnaLight")) do
        local cell = fixture:GetAttribute("Cell")
        if cell ~= nil and lightByCell[cell] == nil then
            lightByCell[cell] = fixture
        end
    end
end

-- Devuelve si una posición tiene luz encendida en este momento. La lámpara se lee
-- en vivo: oscurecerla o cortar la energía se nota enseguida.
function WorldService.IsLit(position)
    local nav = GameState.Nav
    if not nav or not GameState.Powered then
        return false
    end

    local fixture = lightByCell[nav:CellAt(position)]
    if not fixture or not fixture.Parent then
        return false
    end
    return fixture:GetAttribute("Dark") ~= true
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
    indexLights()
    InteractionService.Populate(plan, map)
    DoorService.Populate(plan, map, theme)
    MechanismService.Populate(plan, map)
    HidingService.Populate(plan, map, theme)
    placeMannequins(plan, map)

    -- Lo obligatorio ya está; muebles y utilería usan lo que sobra del presupuesto.
    RoomGenerator.Furnish(plan, theme, map, PART_BUDGET - countParts(map))
    decorate(plan, theme, map)
    -- Al final, lo que sobra del presupuesto va al desgaste: zarpazos, grietas,
    -- humedad y charcos repartidos en todas las salas.
    RoomGenerator.Weather(plan, theme, map)
    map:SetAttribute("PartCount", countParts(map))
    WorldService.SetPower(theme.StartsPowered)
    MapService.Begin(plan)

    return plan
end

function WorldService.Unload()
    HidingService.Clear()
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
    table.clear(lightByCell)
    applyAtmosphere(ThemeConfig.Lobby)
end

function WorldService.Start()
    Lighting.ClockTime = 0
    Lighting.Brightness = 1
    Lighting.GlobalShadows = true
    Lighting.ShadowSoftness = 0.35
    applyAtmosphere(ThemeConfig.Lobby)

    EventBus.On("FlagSet", function(flag)
        if POWER_FLAGS[flag] then
            WorldService.SetPower(true)
        end
    end)
end

return WorldService
