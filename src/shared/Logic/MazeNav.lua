-- Navegación de monstruos sobre el grafo del laberinto. No depende de la física:
-- funciona igual en piso, paredes o techos y nunca falla por geometría recién creada.
local MazeLayout = require(script.Parent.MazeLayout)

local MazeNav = {}
MazeNav.__index = MazeNav

function MazeNav.new(layout, cellSize)
    return setmetatable({
        Layout = layout,
        CellSize = cellSize,
        Blocked = {},
    }, MazeNav)
end

function MazeNav:CellAt(position)
    local layout = self.Layout
    local x = math.clamp(math.floor(position.X / self.CellSize + 0.5) + 1, 1, layout.Width)
    local z = math.clamp(math.floor(position.Z / self.CellSize + 0.5) + 1, 1, layout.Depth)
    return (z - 1) * layout.Width + x
end

function MazeNav:Center(index, height)
    local cell = self.Layout.Cells[index]
    return Vector3.new((cell.X - 1) * self.CellSize, height or 0, (cell.Z - 1) * self.CellSize)
end

function MazeNav:Block(a, b)
    self.Blocked[MazeLayout.EdgeKey(a, b)] = true
end

function MazeNav:Unblock(a, b)
    self.Blocked[MazeLayout.EdgeKey(a, b)] = nil
end

function MazeNav:IsBlocked(a, b)
    return self.Blocked[MazeLayout.EdgeKey(a, b)] == true
end

function MazeNav:Path(fromCell, toCell)
    return MazeLayout.PathBetween(self.Layout, fromCell, toCell, self.Blocked)
end

function MazeNav:Neighbors(index)
    return MazeLayout.Neighbors(self.Layout, index, self.Blocked)
end

-- Puntos de paso: centro de cada abertura y de cada celda, terminando en el destino.
function MazeNav:Waypoints(from, to, height)
    local fromCell = self:CellAt(from)
    local toCell = self:CellAt(to)
    local path = self:Path(fromCell, toCell)
    if not path then
        return nil
    end

    local points = {}
    for index = 2, #path do
        local previous = self:Center(path[index - 1], height)
        local nextCenter = self:Center(path[index], height)
        table.insert(points, previous:Lerp(nextCenter, 0.5))
        if index < #path then
            table.insert(points, nextCenter)
        end
    end
    table.insert(points, Vector3.new(to.X, height or to.Y, to.Z))
    return points
end

function MazeNav:Steps(fromCell, toCell)
    local path = self:Path(fromCell, toCell)
    return path and #path - 1 or math.huge
end

-- Celdas a exactamente entre minSteps y maxSteps pasos de origin.
function MazeNav:CellsBetween(origin, minSteps, maxSteps)
    local distance = MazeLayout.Flood(self.Layout, origin, self.Blocked)
    local result = {}
    for index, steps in pairs(distance) do
        if steps >= minSteps and steps <= maxSteps then
            table.insert(result, index)
        end
    end
    table.sort(result)
    return result
end

return MazeNav
