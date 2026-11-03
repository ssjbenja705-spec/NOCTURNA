-- Reparte roles, puertas, objetos y mecanismos sobre un laberinto.
-- Garantiza que todo lo necesario para abrir una puerta quede antes de esa puerta.
local MazeLayout = require(script.Parent.MazeLayout)

local LayoutPlanner = {}

local CORNERS = {"NE", "NW", "SE", "SW"}

local function freeSlots(cell)
    return #cell.Slots
end

local function takeSlot(cell, rng)
    assert(#cell.Slots > 0, "[NOCTURNA] Celda sin espacio libre")
    return table.remove(cell.Slots, rng:Int(1, #cell.Slots))
end

local function assignRoles(layout, spec, rng)
    local locked = {}
    for _, index in ipairs(layout.Reserved) do
        locked[index] = true
    end

    local zoneCells = {}
    local mainPath = layout.MainPath
    for _, zone in ipairs(spec.Zones or {}) do
        local position = math.clamp(math.floor(#mainPath * zone.PathFraction + 0.5), 2, #mainPath - 1)
        zoneCells[mainPath[position]] = zone.Id
    end

    for _, cell in ipairs(layout.Cells) do
        cell.Slots = table.clone(CORNERS)
        cell.Zone = zoneCells[cell.Index]

        if cell.Index == layout.Start then
            cell.Role = "Start"
        elseif cell.Index == layout.Exit then
            cell.Role = "Exit"
        elseif locked[cell.Index] then
            cell.Role = "Locked"
        elseif cell.Zone or MazeLayout.Degree(layout, cell.Index) == 1 then
            cell.Role = "Room"
        elseif rng:Chance(spec.NarrowChance or 0) then
            cell.Role = "Corridor"
            cell.Slots = {}
        else
            cell.Role = "Room"
        end
    end
end

-- Elige la sala con lugar libre más alejada de lo ya colocado.
local function pickRoom(layout, plan, rng, minimumFree)
    local best, bestScore = nil, -math.huge

    for _, cell in ipairs(layout.Cells) do
        if cell.Role == "Room" and freeSlots(cell) >= (minimumFree or 1) then
            local nearest = 6
            for _, used in ipairs(plan.UsedCells) do
                local other = layout.Cells[used]
                local gap = math.abs(other.X - cell.X) + math.abs(other.Z - cell.Z)
                nearest = math.min(nearest, gap)
            end
            local score = nearest * 2 + math.min(layout.Distance[cell.Index], 8) * 0.25 + rng:Float()
            if score > bestScore then
                best, bestScore = cell, score
            end
        end
    end

    return best
end

local function place(plan, list, entry, cell, rng)
    entry.Cell = cell.Index
    entry.Slot = takeSlot(cell, rng)
    table.insert(list, entry)
    table.insert(plan.UsedCells, cell.Index)
    return entry
end

local function placeFeature(plan, featureSpec, cell, rng)
    local feature = table.clone(featureSpec)
    return place(plan, plan.Features, feature, cell, rng)
end

local function addDoor(plan, layout, a, b, doorSpec)
    local door = doorSpec and table.clone(doorSpec) or {}
    door.A = a
    door.B = b
    door.Key = MazeLayout.EdgeKey(a, b)
    door.Locked = door.RequiredItem ~= nil or door.RequiresFlag ~= nil
    table.insert(plan.Doors, door)
    plan.DoorEdges[door.Key] = door
    if door.Locked then
        plan.LockedEdges[door.Key] = true
    end
    return door
end

local function placeExit(plan, layout, spec, rng)
    local exitCell = layout.Cells[layout.Exit]
    local entrance = MazeLayout.Neighbors(layout, layout.Exit)[1]

    if spec.Exit.Door then
        addDoor(plan, layout, entrance, layout.Exit, spec.Exit.Door)
    end

    if spec.Exit.Zone then
        exitCell.Zone = spec.Exit.Zone
    end

    local feature = table.clone(spec.Exit)
    feature.Kind = spec.Exit.Kind or "Exit"
    feature.Door = nil
    place(plan, plan.Features, feature, exitCell, rng)
end

local function placeLockedRooms(plan, layout, spec, rng)
    for index, roomSpec in ipairs(spec.LockedRooms or {}) do
        local cellIndex = layout.Reserved[index]
        local cell = layout.Cells[cellIndex]
        local entrance = MazeLayout.Neighbors(layout, cellIndex)[1]

        addDoor(plan, layout, entrance, cellIndex, roomSpec.Door)
        cell.Zone = roomSpec.Zone
        cell.RoomId = roomSpec.Id

        for _, featureSpec in ipairs(roomSpec.Features or {}) do
            placeFeature(plan, featureSpec, cell, rng)
        end
    end
end

local function placeNormalDoors(plan, layout, spec, rng)
    local candidates = {}

    for _, cell in ipairs(layout.Cells) do
        for _, direction in ipairs({"E", "S"}) do
            if cell.Open[direction] then
                local neighbor = MazeLayout.Neighbor(layout, cell, direction)
                local key = MazeLayout.EdgeKey(cell.Index, neighbor.Index)
                if not plan.DoorEdges[key] then
                    table.insert(candidates, {cell.Index, neighbor.Index})
                end
            end
        end
    end

    rng:Shuffle(candidates)
    for index = 1, math.min(spec.Doors or 0, #candidates) do
        addDoor(plan, layout, candidates[index][1], candidates[index][2])
    end
end

local function placeItems(plan, layout, spec, rng)
    local counter = 0

    for _, itemSpec in ipairs(spec.Items or {}) do
        for _ = 1, itemSpec.Count do
            local cell = pickRoom(layout, plan, rng)
            assert(cell, "[NOCTURNA] No hay lugar para el objeto " .. itemSpec.Item)
            counter += 1
            place(plan, plan.Items, {Item = itemSpec.Item, Key = "ITEM_" .. counter}, cell, rng)
        end
    end
end

local function placeDocuments(plan, layout, spec, rng)
    for _, documentId in ipairs(spec.Documents or {}) do
        local cell = pickRoom(layout, plan, rng)
        assert(cell, "[NOCTURNA] No hay lugar para el documento " .. documentId)
        place(plan, plan.Documents, {DocumentId = documentId, Group = spec.DocumentGroup}, cell, rng)
    end
end

local function placeSimple(plan, layout, list, count, rng, entry)
    for _ = 1, count or 0 do
        local cell = pickRoom(layout, plan, rng)
        if cell then
            place(plan, list, table.clone(entry), cell, rng)
        end
    end
end

-- Devuelve el plan completo de una capítulo a partir de layout + especificación.
function LayoutPlanner.Plan(layout, spec)
    local rng = layout.Rng
    local plan = {
        Features = {},
        Items = {},
        Documents = {},
        Hides = {},
        Mannequins = {},
        Doors = {},
        DoorEdges = {},
        LockedEdges = {},
        UsedCells = {},
        Layout = layout,
    }

    assignRoles(layout, spec, rng)
    placeExit(plan, layout, spec, rng)
    placeLockedRooms(plan, layout, spec, rng)

    for _, featureSpec in ipairs(spec.Features or {}) do
        local cell = pickRoom(layout, plan, rng, 2)
        assert(cell, "[NOCTURNA] No hay lugar para la función " .. tostring(featureSpec.Id))
        placeFeature(plan, featureSpec, cell, rng)
    end

    placeItems(plan, layout, spec, rng)
    placeDocuments(plan, layout, spec, rng)
    placeSimple(plan, layout, plan.Hides, spec.Hides, rng, {Kind = "Locker"})
    placeSimple(plan, layout, plan.Mannequins, spec.Mannequins, rng, {Kind = "Mannequin"})
    placeNormalDoors(plan, layout, spec, rng)

    return plan
end

-- Comprueba que el capítulo se pueda completar. Devuelve ok, motivo.
function LayoutPlanner.Validate(plan)
    local layout = plan.Layout

    local everyEdgeOpen = MazeLayout.IsConnected(layout)
    if not everyEdgeOpen then
        return false, "El laberinto no está conectado"
    end

    local reachable = MazeLayout.Flood(layout, layout.Start, plan.LockedEdges)
    for _, item in ipairs(plan.Items) do
        if reachable[item.Cell] == nil then
            return false, "Objeto detrás de una puerta: " .. item.Item
        end
    end

    for _, document in ipairs(plan.Documents) do
        if reachable[document.Cell] == nil then
            return false, "Documento detrás de una puerta: " .. document.DocumentId
        end
    end

    for _, hide in ipairs(plan.Hides) do
        if reachable[hide.Cell] == nil then
            return false, "Escondite inalcanzable"
        end
    end

    local slots = {}
    local function checkSlots(list)
        for _, entry in ipairs(list) do
            local key = entry.Cell .. ":" .. entry.Slot
            if slots[key] then
                return false
            end
            slots[key] = true
        end
        return true
    end

    for _, list in ipairs({plan.Features, plan.Items, plan.Documents, plan.Hides, plan.Mannequins}) do
        if not checkSlots(list) then
            return false, "Dos elementos ocupan el mismo lugar"
        end
    end

    return true
end

return LayoutPlanner
