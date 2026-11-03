-- Laberinto procedural determinista. Lógica pura, sin instancias de Roblox.
local Rng = require(script.Parent.Rng)

local MazeLayout = {}

MazeLayout.Directions = {
    N = {DX = 0, DZ = -1, Opposite = "S"},
    S = {DX = 0, DZ = 1, Opposite = "N"},
    E = {DX = 1, DZ = 0, Opposite = "W"},
    W = {DX = -1, DZ = 0, Opposite = "E"},
}
MazeLayout.DirectionOrder = {"N", "S", "E", "W"}

local MAX_ATTEMPTS = 64

function MazeLayout.EdgeKey(a, b)
    if a > b then
        a, b = b, a
    end
    return a .. "_" .. b
end

local function cellAt(layout, x, z)
    if x < 1 or z < 1 or x > layout.Width or z > layout.Depth then
        return nil
    end
    return layout.Cells[(z - 1) * layout.Width + x]
end

function MazeLayout.Neighbor(layout, cell, direction)
    local offset = MazeLayout.Directions[direction]
    return cellAt(layout, cell.X + offset.DX, cell.Z + offset.DZ)
end

-- Vecinos conectados, omitiendo las aristas bloqueadas.
function MazeLayout.Neighbors(layout, index, blocked)
    local cell = layout.Cells[index]
    local result = {}

    for _, direction in ipairs(MazeLayout.DirectionOrder) do
        if cell.Open[direction] then
            local neighbor = MazeLayout.Neighbor(layout, cell, direction)
            if neighbor and not (blocked and blocked[MazeLayout.EdgeKey(index, neighbor.Index)]) then
                table.insert(result, neighbor.Index)
            end
        end
    end

    return result
end

function MazeLayout.Degree(layout, index)
    return #MazeLayout.Neighbors(layout, index)
end

-- Recorrido en anchura: distancia y padre de cada celda alcanzable.
function MazeLayout.Flood(layout, start, blocked)
    local distance = {[start] = 0}
    local parent = {}
    local queue = {start}
    local head = 1

    while head <= #queue do
        local current = queue[head]
        head += 1
        for _, neighbor in ipairs(MazeLayout.Neighbors(layout, current, blocked)) do
            if distance[neighbor] == nil then
                distance[neighbor] = distance[current] + 1
                parent[neighbor] = current
                table.insert(queue, neighbor)
            end
        end
    end

    return distance, parent
end

function MazeLayout.PathBetween(layout, from, to, blocked)
    if from == to then
        return {from}
    end

    local distance, parent = MazeLayout.Flood(layout, from, blocked)
    if distance[to] == nil then
        return nil
    end

    local reversed = {to}
    local current = to
    while current ~= from do
        current = parent[current]
        table.insert(reversed, current)
    end

    local path = table.create(#reversed)
    for index = #reversed, 1, -1 do
        table.insert(path, reversed[index])
    end
    return path
end

function MazeLayout.IsConnected(layout, blocked)
    local distance = MazeLayout.Flood(layout, layout.Start, blocked)
    local reached = 0
    for _ in pairs(distance) do
        reached += 1
    end
    return reached == #layout.Cells
end

local function emptyLayout(width, depth)
    local layout = {Width = width, Depth = depth, Cells = table.create(width * depth)}

    for z = 1, depth do
        for x = 1, width do
            table.insert(layout.Cells, {
                Index = (z - 1) * width + x,
                X = x,
                Z = z,
                Open = {N = false, S = false, E = false, W = false},
            })
        end
    end

    return layout
end

local function open(layout, cell, direction)
    local neighbor = MazeLayout.Neighbor(layout, cell, direction)
    cell.Open[direction] = true
    neighbor.Open[MazeLayout.Directions[direction].Opposite] = true
end

local function carve(layout, startCell, rng)
    local visited = {[startCell.Index] = true}
    local stack = {startCell}

    while #stack > 0 do
        local current = stack[#stack]
        local available = {}

        for _, direction in ipairs(MazeLayout.DirectionOrder) do
            local neighbor = MazeLayout.Neighbor(layout, current, direction)
            if neighbor and not visited[neighbor.Index] then
                table.insert(available, direction)
            end
        end

        if #available == 0 then
            table.remove(stack)
        else
            local direction = rng:Pick(available)
            local neighbor = MazeLayout.Neighbor(layout, current, direction)
            open(layout, current, direction)
            visited[neighbor.Index] = true
            table.insert(stack, neighbor)
        end
    end
end

local function leavesByDistance(layout, distance, exclude)
    local leaves = {}
    for _, cell in ipairs(layout.Cells) do
        if cell.Index ~= exclude and MazeLayout.Degree(layout, cell.Index) == 1 then
            table.insert(leaves, cell.Index)
        end
    end
    table.sort(leaves, function(a, b)
        if distance[a] == distance[b] then
            return a < b
        end
        return distance[a] > distance[b]
    end)
    return leaves
end

local function addLoops(layout, chance, protected, rng)
    for _, cell in ipairs(layout.Cells) do
        for _, direction in ipairs({"E", "S"}) do
            local neighbor = MazeLayout.Neighbor(layout, cell, direction)
            if neighbor
                and not cell.Open[direction]
                and not protected[cell.Index]
                and not protected[neighbor.Index]
                and rng:Chance(chance) then
                open(layout, cell, direction)
            end
        end
    end
end

-- opciones: Width, Depth, Seed, LoopChance, ReservedLeaves.
-- Exit y las celdas reservadas siguen siendo callejones sin salida, así que una
-- sola puerta alcanza para cerrarlas. Los bucles dan rutas de escape al jugador.
function MazeLayout.Generate(options)
    assert(options.Width >= 2 and options.Depth >= 2, "El mapa necesita al menos 2x2 celdas")

    local reservedCount = options.ReservedLeaves or 0
    local seed = options.Seed or 0

    for attempt = 0, MAX_ATTEMPTS do
        local rng = Rng.new(seed + attempt * 7919)
        local layout = emptyLayout(options.Width, options.Depth)
        local start = layout.Cells[(rng:Int(1, options.Depth) - 1) * options.Width + 1]

        carve(layout, start, rng)
        layout.Start = start.Index

        local distance = MazeLayout.Flood(layout, start.Index)
        local leaves = leavesByDistance(layout, distance, start.Index)

        if #leaves >= reservedCount + 1 then
            layout.Exit = leaves[1]
            layout.Reserved = {}
            local protected = {[start.Index] = true, [layout.Exit] = true}

            for index = 2, reservedCount + 1 do
                table.insert(layout.Reserved, leaves[index])
                protected[leaves[index]] = true
            end

            addLoops(layout, options.LoopChance or 0, protected, rng)

            local finalDistance = MazeLayout.Flood(layout, start.Index)
            layout.Distance = finalDistance
            layout.MainPath = MazeLayout.PathBetween(layout, layout.Start, layout.Exit)
            layout.Seed = seed
            layout.Rng = rng
            return layout
        end
    end

    error("[NOCTURNA] No se pudo generar un laberinto con suficientes callejones")
end

return MazeLayout
