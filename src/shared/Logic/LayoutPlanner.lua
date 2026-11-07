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

-- Extras del mundo ------------------------------------------------------------------
-- Escondites además de los que pide el capítulo y pasadizos secretos. Se agregan
-- después de Plan y no tocan nada de lo que ya quedó ubicado.

-- Suma hasta `count` escondites en rincones libres. Devuelve cuántos entraron.
function LayoutPlanner.AddHides(plan, count)
    local before = #plan.Hides
    placeSimple(plan, plan.Layout, plan.Hides, count, plan.Layout.Rng, {Kind = "Locker"})
    return #plan.Hides - before
end

-- Una celda sirve de boca de pasadizo si se llega sin abrir puertas trabadas y no
-- es la salida, una sala cerrada ni una zona de la historia.
local function passageCell(layout, cell, reachable)
    return reachable[cell.Index] ~= nil
        and cell.Index ~= layout.Exit
        and cell.Index ~= layout.Start
        and cell.Role ~= "Locked"
        and cell.Zone == nil
end

-- Pasadizos entre celdas vecinas separadas por una pared, que por los pasillos
-- quedan lejos (al menos `minimumSteps` pasos). No forman parte del grafo de
-- MazeLayout, así que las criaturas no los usan y la validación no cambia.
function LayoutPlanner.AddPassages(plan, count, minimumSteps)
    local layout = plan.Layout
    local rng = layout.Rng
    minimumSteps = minimumSteps or 3
    plan.Passages = plan.Passages or {}
    plan.PassageEdges = plan.PassageEdges or {}

    local reachable = MazeLayout.Flood(layout, layout.Start, plan.LockedEdges)
    local candidates = {}
    for _, cell in ipairs(layout.Cells) do
        for _, direction in ipairs({"E", "S"}) do
            local neighbor = MazeLayout.Neighbor(layout, cell, direction)
            if neighbor
                and not cell.Open[direction]
                and passageCell(layout, cell, reachable)
                and passageCell(layout, neighbor, reachable) then
                table.insert(candidates, {cell.Index, neighbor.Index})
            end
        end
    end
    rng:Shuffle(candidates)

    local used = {}
    for _, pair in ipairs(plan.Passages) do
        used[pair.A], used[pair.B] = true, true
    end

    for _, pair in ipairs(candidates) do
        if #plan.Passages >= count then
            break
        end
        local a, b = pair[1], pair[2]
        if not used[a] and not used[b] then
            local path = MazeLayout.PathBetween(layout, a, b)
            if path and #path - 1 >= minimumSteps then
                local passage = {A = a, B = b, Key = MazeLayout.EdgeKey(a, b)}
                table.insert(plan.Passages, passage)
                plan.PassageEdges[passage.Key] = passage
                used[a], used[b] = true, true
            end
        end
    end

    return #plan.Passages
end

-- Un pasadizo válido une dos vecinas con pared de por medio, las dos alcanzables
-- sin puertas trabadas, y nunca lleva a la salida ni a una sala cerrada.
function LayoutPlanner.ValidatePassages(plan)
    local layout = plan.Layout
    local reachable = MazeLayout.Flood(layout, layout.Start, plan.LockedEdges)

    for _, passage in ipairs(plan.Passages or {}) do
        local a, b = layout.Cells[passage.A], layout.Cells[passage.B]
        if not a or not b or math.abs(a.X - b.X) + math.abs(a.Z - b.Z) ~= 1 then
            return false, "Pasadizo entre celdas que no son vecinas"
        end
        for direction in pairs(MazeLayout.Directions) do
            if MazeLayout.Neighbor(layout, a, direction) == b and a.Open[direction] then
                return false, "Pasadizo sobre una abertura común"
            end
        end
        if not passageCell(layout, a, reachable) or not passageCell(layout, b, reachable) then
            return false, "Pasadizo que saltea una puerta trabada"
        end
    end

    return true
end

return LayoutPlanner
