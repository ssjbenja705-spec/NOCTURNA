-- Crea, actualiza y retira a las criaturas de cada capítulo.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local ChapterConfig = require(Shared.Config.ChapterConfig)
local MonsterConfig = require(Shared.Config.MonsterConfig)

local MonsterController = require(script.Parent.Parent.AI.MonsterController)
local Behaviors = script.Parent.Parent.AI.Behaviors
local GameState = require(script.Parent.Parent.Core.GameState)
local MonsterFactory = require(script.Parent.MonsterFactory)
local MonsterWorld = require(script.Parent.MonsterWorld)

local TICK = 1 / 15
local THREAT_INTERVAL = 0.5
local THREAT_RANGE = 45
local MIN_SPAWN_STEPS = 3
local MAX_FAILURES = 30

local MonsterService = {}
local active = {}
local world = nil
local folder = nil
local paused = false
local threatWarned = false

local BEHAVIORS = {
    ElOyente = require(Behaviors.ElOyente),
    ElImitador = require(Behaviors.ElImitador),
    ElQuieto = require(Behaviors.ElQuieto),
    ElTrepador = require(Behaviors.ElTrepador),
    ElColoso = require(Behaviors.ElColoso),
}

local function getFolder()
    if folder and folder.Parent then
        return folder
    end
    folder = Instance.new("Folder")
    folder.Name = "Monsters"
    folder.Parent = workspace
    return folder
end

-- Las criaturas aparecen lejos de todos; nunca a la vista de un jugador recién llegado.
local function spawnCell()
    local layout = GameState.Layout
    local nav = GameState.Nav
    local best, bestSteps = layout.Start, -1

    for _, cell in ipairs(layout.Cells) do
        local steps = layout.Distance[cell.Index] or 0
        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if root then
                steps = math.min(steps, nav:Steps(nav:CellAt(root.Position), cell.Index))
            end
        end

        for _, entry in ipairs(active) do
            steps = math.min(steps, nav:Steps(nav:CellAt(entry.Controller.Position), cell.Index))
        end

        if steps > bestSteps and nav:Path(cell.Index, layout.Start) then
            best, bestSteps = cell.Index, steps
        end
    end

    if bestSteps < MIN_SPAWN_STEPS then
        warn("[NOCTURNA] Criatura aparece cerca del grupo; el mapa es demasiado chico.")
    end
    return best
end

function MonsterService.Spawn(kind)
    local settings = MonsterConfig[kind]
    if not settings or not GameState.Nav then
        return nil
    end

    world = world or MonsterWorld.new()
    world:BeginTick()

    -- Si algo falla al armarla, no queda un cuerpo quieto en el mapa ni se
    -- cancelan las demás criaturas del capítulo.
    local model = nil
    local success, result = pcall(function()
        local difficulty = GameState.DifficultySettings()
        local position = GameState.Nav:Center(spawnCell(), settings.BodyHeight)
        local root
        model, root = MonsterFactory.Build(kind, getFolder(), settings.BodyHeight)
        local controller = MonsterController.new(kind, settings, BEHAVIORS[settings.Behavior], world, position, {
            Speed = difficulty.MonsterSpeed,
            Damage = difficulty.MonsterDamage,
        })

        root.CFrame = controller:GetCFrame()
        return {Controller = controller, Model = model, Root = root, LastSpeed = -1, Failures = 0}
    end)

    if not success then
        if model then
            model:Destroy()
        end
        warn("[NOCTURNA] No se pudo crear la criatura", kind, result)
        return nil
    end

    table.insert(active, result)
    return result
end

function MonsterService.SpawnChapter(chapterIndex)
    for _, kind in ipairs(ChapterConfig[chapterIndex].Monsters or {}) do
        MonsterService.Spawn(kind)
    end
end

function MonsterService.SpawnReinforcements(chapterIndex, objectiveId)
    for _, reinforcement in ipairs(ChapterConfig[chapterIndex].Reinforcements or {}) do
        if reinforcement.AfterObjective == objectiveId
            and #Players:GetPlayers() >= (reinforcement.MinPlayers or 1) then
            MonsterService.Spawn(reinforcement.Monster)
        end
    end
end

function MonsterService.SetRage(enabled)
    for _, entry in ipairs(active) do
        entry.Controller.Rage = enabled
    end
end

function MonsterService.SetPaused(value)
    paused = value
end

function MonsterService.IsPaused()
    return paused
end

function MonsterService.Clear()
    for _, entry in ipairs(active) do
        entry.Model:Destroy()
    end
    table.clear(active)
    world = nil

    for _, player in ipairs(Players:GetPlayers()) do
        player:SetAttribute("NocturnaThreat", 0)
    end
end

function MonsterService.Active()
    return active
end

-- Nivel de amenaza por jugador: alimenta el latido y la música de persecución.
local function updateThreat()
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local level = 0

        if root then
            for _, entry in ipairs(active) do
                local controller = entry.Controller
                local distance = (controller.Position - root.Position).Magnitude
                local proximity = 1 - math.clamp(distance / THREAT_RANGE, 0, 1)
                if controller.Target == player then
                    proximity = math.max(proximity, 0.75)
                end
                level = math.max(level, proximity)
            end
        end

        local rounded = math.floor(level * 10) / 10
        if player:GetAttribute("NocturnaThreat") ~= rounded then
            player:SetAttribute("NocturnaThreat", rounded)
        end
    end
end

local function tickEntry(entry, deltaTime)
    local controller = entry.Controller
    controller:Tick(deltaTime)
    entry.Root.CFrame = controller:GetCFrame()

    if entry.LastSpeed ~= controller.Speed then
        entry.LastSpeed = controller.Speed
        entry.Model:SetAttribute("MoveSpeed", controller.Speed)
    end
end

-- Cada criatura se actualiza por separado: si una falla, las demás siguen.
-- La que falla seguido se retira para no llenar la consola.
local function tick(deltaTime)
    world:BeginTick()

    local broken = nil
    for index, entry in ipairs(active) do
        local success, err = pcall(tickEntry, entry, deltaTime)
        if success then
            entry.Failures = 0
        else
            entry.Failures += 1
            if entry.Failures == 1 then
                warn("[NOCTURNA] Error de IA en " .. entry.Model.Name .. ":", err)
            end
            if entry.Failures >= MAX_FAILURES then
                broken = broken or {}
                table.insert(broken, index)
            end
        end
    end

    if broken then
        for position = #broken, 1, -1 do
            local entry = table.remove(active, broken[position])
            warn("[NOCTURNA] Se retira " .. entry.Model.Name .. " por errores repetidos.")
            entry.Model:Destroy()
        end
    end
end

function MonsterService.Start()
    local elapsed, threatElapsed = 0, 0

    RunService.Heartbeat:Connect(function(deltaTime)
        if #active == 0 or paused or not GameState.IsPlaying() then
            return
        end

        elapsed += deltaTime
        threatElapsed += deltaTime

        if elapsed >= TICK then
            local step = elapsed
            elapsed = 0
            local success, err = pcall(tick, step)
            if not success then
                warn("[NOCTURNA] Error de IA:", err)
            end
        end

        if threatElapsed >= THREAT_INTERVAL then
            threatElapsed = 0
            local success, err = pcall(updateThreat)
            if not success and not threatWarned then
                threatWarned = true
                warn("[NOCTURNA] Error calculando la amenaza:", err)
            end
        end
    end)
end

return MonsterService
