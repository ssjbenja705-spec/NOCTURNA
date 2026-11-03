-- Cambios del escenario: derrumbes del Coloso, temblores y apagones por zona.
-- Un derrumbe nunca aísla una parte del mapa.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local MazeLayout = require(Shared.Logic.MazeLayout)
local Remotes = require(Shared.Modules.RemoteHelper)

local GameState = require(script.Parent.Parent.Core.GameState)
local RoomGenerator = require(script.Parent.RoomGenerator)

local MAP = GameConfig.Map
local MAX_COLLAPSES = 2
local PLAYER_CLEARANCE = 8

local EnvironmentService = {}
local collapsed = {}
local generation = 0

local function collapsedCount()
    local count = 0
    for _ in pairs(collapsed) do
        count += 1
    end
    return count
end

local function playerNear(position, range)
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root then
            local offset = root.Position - position
            if Vector3.new(offset.X, 0, offset.Z).Magnitude < range then
                return true
            end
        end
    end
    return false
end

local function wouldIsolate(layout, key)
    local blocked = {[key] = true}
    for existing in pairs(collapsed) do
        blocked[existing] = true
    end
    return not MazeLayout.IsConnected(layout, blocked)
end

local function restore(key, token)
    local entry = collapsed[key]
    if not entry or token ~= generation then
        return
    end
    collapsed[key] = nil
    entry.Rubble:Destroy()
    if GameState.Nav then
        GameState.Nav:Unblock(entry.A, entry.B)
    end
end

-- Derrumba un pasillo sin puerta cerca de `position`. Devuelve true si cayó uno.
function EnvironmentService.Collapse(position, duration)
    local layout = GameState.Layout
    local nav = GameState.Nav
    local plan = GameState.Plan
    if not layout or not nav or not plan or collapsedCount() >= MAX_COLLAPSES then
        return false
    end

    local origin = nav:CellAt(position)
    for _, cell in ipairs(nav:CellsBetween(origin, 0, 2)) do
        for _, neighbor in ipairs(nav:Neighbors(cell)) do
            local key = MazeLayout.EdgeKey(cell, neighbor)
            local midpoint, horizontal = RoomGenerator.EdgeInfo(layout, cell, neighbor)

            if not plan.DoorEdges[key]
                and not collapsed[key]
                and not wouldIsolate(layout, key)
                and not playerNear(midpoint, PLAYER_CLEARANCE) then
                local width = MAP.CorridorWidth
                local size = horizontal and Vector3.new(width, MAP.OpeningHeight, 5) or Vector3.new(5, MAP.OpeningHeight, width)
                local rubble = RoomGenerator.CreatePart(
                    workspace:FindFirstChild("NOCTURNA_MAP"),
                    "Rubble",
                    size,
                    midpoint + Vector3.new(0, MAP.OpeningHeight / 2, 0),
                    Color3.fromRGB(70, 66, 62),
                    Enum.Material.Slate
                )

                nav:Block(cell, neighbor)
                collapsed[key] = {Rubble = rubble, A = cell, B = neighbor}
                Remotes.FireAll("PlaySound", "Collapse", midpoint)

                local token = generation
                task.delay(duration, restore, key, token)
                return true
            end
        end
    end

    return false
end

local function lightsIn(cells)
    local wanted = {}
    for _, index in ipairs(cells) do
        wanted[index] = true
    end

    local result = {}
    for _, fixture in ipairs(CollectionService:GetTagged("NocturnaLight")) do
        if wanted[fixture:GetAttribute("Cell")] then
            table.insert(result, fixture)
        end
    end
    return result
end

local function setFixtureDark(fixture, dark)
    fixture:SetAttribute("Dark", dark or nil)
    local light = fixture:FindFirstChildOfClass("PointLight")
    if light then
        light.Enabled = not dark
    end
end

-- Oscurece las celdas cercanas durante un rato.
function EnvironmentService.DarkenNear(position, steps, duration)
    local nav = GameState.Nav
    if not nav then
        return
    end

    local cells = nav:CellsBetween(nav:CellAt(position), 0, steps)
    local fixtures = lightsIn(cells)
    for _, fixture in ipairs(fixtures) do
        setFixtureDark(fixture, true)
    end

    task.delay(duration, function()
        for _, fixture in ipairs(fixtures) do
            if fixture.Parent then
                setFixtureDark(fixture, false)
            end
        end
    end)

    Remotes.FireAll("HorrorEvent", "ZONE_DARK")
end

function EnvironmentService.Quake(position)
    Remotes.FireAll("MonsterEffect", "Quake", {Position = position})
    EnvironmentService.DarkenNear(position, 1, 12)
end

function EnvironmentService.Clear()
    generation += 1
    table.clear(collapsed)
end

return EnvironmentService
