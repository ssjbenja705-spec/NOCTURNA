-- Plano compartido del grupo. El servidor conoce todo el capítulo, pero a los
-- clientes sólo les manda lo que algún compañero ya pisó: la sala, sus aberturas,
-- las puertas que la tocan y lo que hay adentro. Nada de lo inexplorado sale de acá.
--
-- Mensajes de "MapUpdate":
--   {Kind = "Layout", Chapter, Width, Depth, Cells, Doors, Markers}  plano completo conocido
--   {Kind = "Reveal", Chapter, Cells, Doors, Markers}               novedades
--   {Kind = "Clear"}                                                 sin capítulo cargado
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local ChapterConfig = require(Shared.Config.ChapterConfig)
local GameConfig = require(Shared.Config.GameConfig)
local MazeLayout = require(Shared.Logic.MazeLayout)
local Remotes = require(Shared.Modules.RemoteHelper)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)

local VISIT_INTERVAL = 0.5
local CELL_SIZE = GameConfig.Map.CellSize

local MapService = {}
local current = nil
local elapsed = 0

local function openings(cell)
    local text = ""
    for _, direction in ipairs(MazeLayout.DirectionOrder) do
        if cell.Open[direction] then
            text ..= direction
        end
    end
    return text
end

local function cellPayload(cell)
    return {I = cell.Index, X = cell.X, Z = cell.Z, Open = openings(cell), Role = cell.Role}
end

local function doorPayload(spec)
    return {Key = spec.Key, A = spec.A, B = spec.B, Locked = spec.Locked == true, Label = spec.Label}
end

local function markerPayload(marker)
    return {
        Id = marker.Id,
        Type = marker.Type,
        Cell = marker.Cell,
        Slot = marker.Slot,
        Item = marker.Item,
        Document = marker.Document,
        Label = marker.Label,
        Done = marker.Done,
    }
end

-- Un objeto levantado ya no está: no se muestra más.
local function isVisible(marker)
    return not (marker.Type == "Item" and marker.Done)
end

local function addMarker(state, marker)
    if typeof(marker.Cell) ~= "number" then
        return
    end
    state.Markers[marker.Id] = marker
    local list = state.MarkersByCell[marker.Cell]
    if not list then
        list = {}
        state.MarkersByCell[marker.Cell] = list
    end
    table.insert(list, marker)
end

local function buildMarkers(state, plan, chapter)
    local exitId = chapter and chapter.Layout and chapter.Layout.Exit and chapter.Layout.Exit.Id

    for _, item in ipairs(plan.Items or {}) do
        addMarker(state, {Id = "I:" .. tostring(item.Key), Type = "Item", Item = item.Item, Cell = item.Cell, Slot = item.Slot})
    end
    for _, document in ipairs(plan.Documents or {}) do
        addMarker(state, {
            Id = "D:" .. tostring(document.DocumentId),
            Type = "Document",
            Document = document.DocumentId,
            Cell = document.Cell,
            Slot = document.Slot,
        })
    end
    for index, hide in ipairs(plan.Hides or {}) do
        addMarker(state, {Id = "H:" .. index, Type = "Hide", Cell = hide.Cell, Slot = hide.Slot})
    end
    for _, feature in ipairs(plan.Features or {}) do
        local isExit = feature.Id ~= nil and feature.Id == exitId
        addMarker(state, {
            Id = "F:" .. tostring(feature.Id),
            Type = isExit and "Exit" or "Mechanism",
            Cell = feature.Cell,
            Slot = feature.Slot,
            Label = feature.Label or (isExit and "Salida" or nil),
        })
    end
end

local function newDelta(state)
    return {Kind = "Reveal", Chapter = state.Chapter, Cells = {}, Doors = {}, Markers = {}}
end

local function reveal(state, index, delta)
    if state.Revealed[index] then
        return
    end
    local cell = state.Layout.Cells[index]
    if not cell then
        return
    end

    state.Revealed[index] = true
    table.insert(state.Order, index)
    table.insert(delta.Cells, cellPayload(cell))

    for _, spec in ipairs(state.DoorsByCell[index] or {}) do
        if state.SentDoors[spec.Key] == nil then
            state.SentDoors[spec.Key] = spec.Locked == true
            table.insert(delta.Doors, doorPayload(spec))
        end
    end
    for _, marker in ipairs(state.MarkersByCell[index] or {}) do
        state.Dirty[marker.Id] = nil
        if isVisible(marker) then
            table.insert(delta.Markers, markerPayload(marker))
        end
    end
end

local function snapshot(state)
    local message = {
        Kind = "Layout",
        Chapter = state.Chapter,
        Width = state.Layout.Width,
        Depth = state.Layout.Depth,
        Cells = {},
        Doors = {},
        Markers = {},
    }
    for _, index in ipairs(state.Order) do
        table.insert(message.Cells, cellPayload(state.Layout.Cells[index]))
        for _, marker in ipairs(state.MarkersByCell[index] or {}) do
            if isVisible(marker) then
                table.insert(message.Markers, markerPayload(marker))
            end
        end
    end
    for _, spec in ipairs(state.Plan.Doors or {}) do
        if state.SentDoors[spec.Key] ~= nil then
            table.insert(message.Doors, doorPayload(spec))
        end
    end
    return message
end

-- Sala en la que está una posición, o nil si queda fuera del capítulo (el lobby).
local function cellAt(layout, position)
    local x = math.floor(position.X / CELL_SIZE + 0.5) + 1
    local z = math.floor(position.Z / CELL_SIZE + 0.5) + 1
    if x < 1 or z < 1 or x > layout.Width or z > layout.Depth then
        return nil
    end
    return (z - 1) * layout.Width + x
end

local function step()
    local state = current
    if not state or not GameState.IsPlaying() then
        return
    end

    local delta = newDelta(state)
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if root and humanoid and humanoid.Health > 0 then
            local index = cellAt(state.Layout, root.Position)
            if index then
                reveal(state, index, delta)
            end
        end
    end

    -- Puertas ya conocidas que alguien destrabó.
    for _, spec in ipairs(state.Plan.Doors or {}) do
        local sent = state.SentDoors[spec.Key]
        if sent ~= nil and sent ~= (spec.Locked == true) then
            state.SentDoors[spec.Key] = spec.Locked == true
            table.insert(delta.Doors, doorPayload(spec))
        end
    end

    -- Marcas conocidas que cambiaron: objeto levantado, máquina encendida.
    for id in pairs(state.Dirty) do
        local marker = state.Markers[id]
        if marker and state.Revealed[marker.Cell] then
            table.insert(delta.Markers, markerPayload(marker))
        end
    end
    table.clear(state.Dirty)

    if #delta.Cells > 0 or #delta.Doors > 0 or #delta.Markers > 0 then
        Remotes.FireAll("MapUpdate", delta)
    end
end

local function markDone(id)
    local state = current
    local marker = state and state.Markers[id]
    if marker and not marker.Done then
        marker.Done = true
        state.Dirty[id] = true
    end
end

-- WorldService lo llama al terminar de construir un capítulo.
function MapService.Begin(plan)
    if typeof(plan) ~= "table" or typeof(plan.Layout) ~= "table" then
        return
    end

    local state = {
        Chapter = GameState.Chapter,
        Plan = plan,
        Layout = plan.Layout,
        Revealed = {},
        Order = {},
        Markers = {},
        MarkersByCell = {},
        DoorsByCell = {},
        SentDoors = {},
        Dirty = {},
    }
    buildMarkers(state, plan, ChapterConfig[GameState.Chapter])
    for _, spec in ipairs(plan.Doors or {}) do
        for _, index in ipairs({spec.A, spec.B}) do
            state.DoorsByCell[index] = state.DoorsByCell[index] or {}
            table.insert(state.DoorsByCell[index], spec)
        end
    end

    current = state
    elapsed = 0
    -- Todos despiertan en la entrada: esa sala ya está vista.
    reveal(state, plan.Layout.Start, newDelta(state))
    Remotes.FireAll("MapUpdate", snapshot(state))
end

-- WorldService lo llama al descargar el capítulo.
function MapService.Clear()
    if current == nil then
        return
    end
    current = nil
    Remotes.FireAll("MapUpdate", {Kind = "Clear"})
end

function MapService.IsRevealed(index)
    return current ~= nil and current.Revealed[index] == true
end

function MapService.Snapshot()
    return current and snapshot(current) or {Kind = "Clear"}
end

function MapService.Start()
    EventBus.On("ItemPicked", function(_, _, key)
        markDone("I:" .. tostring(key))
    end)
    EventBus.On("FeatureActivated", function(_, feature)
        if typeof(feature) == "table" then
            markDone("F:" .. tostring(feature.Id))
        end
    end)

    -- Quien entra tarde o reconecta pide lo que el grupo ya conoce. No lleva datos
    -- del cliente: sólo se limita la frecuencia.
    Remotes.OnServer("MapRequest", 1, function(player)
        Remotes.FireClient("MapUpdate", player, MapService.Snapshot())
    end)

    RunService.Heartbeat:Connect(function(deltaTime)
        if not current then
            return
        end
        elapsed += deltaTime
        if elapsed >= VISIT_INTERVAL then
            elapsed = 0
            step()
        end
    end)
end

return MapService
