-- Convierte un plan de capítulo en geometría. Todas las piezas son anclas simples
-- para mantener el mapa liviano en celulares.
--
-- Build arma lo obligatorio (pisos, paredes, techos, pasadizos y luces). Furnish
-- agrega después, dentro de un presupuesto de piezas, lo que da vida a las salas:
-- zócalos, marcos, cosas colgando del techo, muebles según el tipo de sala y mugre.
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local MazeLayout = require(Shared.Logic.MazeLayout)
local Rng = require(Shared.Logic.Rng)

local PropKit = require(script.Parent.PropKit)
local RoomDecor = require(script.Parent.RoomDecor)

local MAP = GameConfig.Map

local RoomGenerator = {}

local function createPart(parent, name, size, position, color, material)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.Position = position
    part.Anchored = true
    part.Color = color
    part.Material = material or Enum.Material.Concrete
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.CanTouch = false
    part.Parent = parent
    return part
end

RoomGenerator.CreatePart = createPart

-- Lados de una celda: normal hacia afuera y giro para que -Z mire a la sala.
local SIDES = {
    N = {Normal = Vector3.new(0, 0, -1), Yaw = math.pi},
    S = {Normal = Vector3.new(0, 0, 1), Yaw = 0},
    W = {Normal = Vector3.new(-1, 0, 0), Yaw = -math.pi / 2},
    E = {Normal = Vector3.new(1, 0, 0), Yaw = math.pi / 2},
}
local SIDE_ORDER = {"N", "E", "S", "W"}

-- Distancia del centro de la celda a la cara interior de la pared (menos el zócalo).
local WALL_FACE = MAP.CellSize / 2 - MAP.WallThickness / 2 - 0.15

local function cellCenter(cell)
    return Vector3.new((cell.X - 1) * MAP.CellSize, 0, (cell.Z - 1) * MAP.CellSize)
end

-- Marco en la cara interior de la pared: -Z hacia la sala, X a lo largo de la pared.
local function sideFrame(center, side)
    local info = SIDES[side]
    return CFrame.new(center + info.Normal * WALL_FACE) * CFrame.Angles(0, info.Yaw, 0)
end

-- Marco en el centro de la pared a nivel del piso, con X a lo largo de la pared.
local function wallFrame(center, horizontal)
    if horizontal then
        return CFrame.new(center)
    end
    return CFrame.new(center) * CFrame.Angles(0, math.rad(90), 0)
end

-- Estado de cada lado: "Open" (abertura común), "Passage" (pasadizo) o nil (pared).
local function sideStatus(plan, layout, cell, side)
    if cell.Open[side] then
        return "Open"
    end
    local neighbor = MazeLayout.Neighbor(layout, cell, side)
    local edges = plan.PassageEdges
    if neighbor and edges and edges[MazeLayout.EdgeKey(cell.Index, neighbor.Index)] then
        return "Passage"
    end
    return nil
end

local function gapFor(status)
    if status == "Open" then
        return MAP.CorridorWidth, MAP.OpeningHeight
    elseif status == "Passage" then
        return RoomDecor.PassageWidth, RoomDecor.PassageHeight
    end
    return 0, 0
end

local function buildWall(parent, center, width, status, horizontal, theme, color)
    local height = MAP.WallHeight
    local thickness = MAP.WallThickness
    local material = PropKit.Material(theme.WallMaterial)
    local wallY = center.Y + height / 2

    if not status then
        local wallSize = horizontal
            and Vector3.new(width, height, thickness)
            or Vector3.new(thickness, height, width)
        createPart(parent, "Wall", wallSize, Vector3.new(center.X, wallY, center.Z), color, material)
        return
    end

    local openingWidth, openingHeight = gapFor(status)
    local segmentWidth = (width - openingWidth) / 2
    for _, side in ipairs({-1, 1}) do
        local offset = side * (openingWidth / 2 + segmentWidth / 2)
        local segmentSize = horizontal
            and Vector3.new(segmentWidth, height, thickness)
            or Vector3.new(thickness, height, segmentWidth)
        local segmentPosition = horizontal
            and Vector3.new(center.X + offset, wallY, center.Z)
            or Vector3.new(center.X, wallY, center.Z + offset)
        createPart(parent, "Wall", segmentSize, segmentPosition, color, material)
    end

    local headerHeight = height - openingHeight
    local headerSize = horizontal
        and Vector3.new(openingWidth, headerHeight, thickness)
        or Vector3.new(thickness, headerHeight, openingWidth)
    createPart(
        parent,
        "OpeningHeader",
        headerSize,
        Vector3.new(center.X, center.Y + height - headerHeight / 2, center.Z),
        color,
        material
    )
end

-- Las celdas "Corridor" se vuelven pasillos en cruz con cuatro bloques macizos.
local function buildCorridorBlocks(parent, center, theme, color)
    local block = (MAP.CellSize - MAP.CorridorWidth) / 2 - MAP.WallThickness / 2
    local offset = MAP.CorridorWidth / 2 + block / 2
    local material = PropKit.Material(theme.WallMaterial)

    for _, sideX in ipairs({-1, 1}) do
        for _, sideZ in ipairs({-1, 1}) do
            createPart(
                parent,
                "CorridorBlock",
                Vector3.new(block, MAP.WallHeight, block),
                center + Vector3.new(sideX * offset, MAP.WallHeight / 2, sideZ * offset),
                color,
                material
            )
        end
    end
end

local function addLight(parent, center, cellIndex, theme, palette)
    local fixture = RoomDecor.Fixture(parent, theme.Fixture, center + Vector3.new(0, MAP.WallHeight, 0), palette)
    fixture.CanCollide = false
    fixture.CastShadow = false
    fixture:SetAttribute("Cell", cellIndex)

    local light = Instance.new("PointLight")
    light.Color = theme.Light
    light.Brightness = 1
    light.Range = 28
    light.Shadows = false
    light.Parent = fixture

    CollectionService:AddTag(fixture, "NocturnaLight")
    return fixture
end

-- Posición del rincón de una celda. Los rincones nunca tapan una abertura.
function RoomGenerator.SlotCFrame(layout, cellIndex, slot)
    local cell = layout.Cells[cellIndex]
    local size = MAP.CellSize
    local inset = size / 2 - MAP.SlotInset
    local center = Vector3.new((cell.X - 1) * size, 0, (cell.Z - 1) * size)
    local sideX = string.find(slot, "E") and 1 or -1
    local sideZ = string.find(slot, "S") and 1 or -1
    local position = center + Vector3.new(sideX * inset, 0, sideZ * inset)
    return CFrame.lookAt(position, Vector3.new(center.X, 0, center.Z))
end

-- Centro y orientación de la abertura entre dos celdas vecinas.
function RoomGenerator.EdgeInfo(layout, a, b)
    local cellA, cellB = layout.Cells[a], layout.Cells[b]
    local size = MAP.CellSize
    local midpoint = Vector3.new(
        ((cellA.X + cellB.X) / 2 - 1) * size,
        0,
        ((cellA.Z + cellB.Z) / 2 - 1) * size
    )
    return midpoint, cellA.Z ~= cellB.Z
end

local function buildPassages(plan, theme, palette, map)
    local folder = Instance.new("Folder")
    folder.Name = "Passages"
    folder.Parent = map

    for _, passage in ipairs(plan.Passages or {}) do
        local holder = Instance.new("Model")
        holder.Name = "Passage_" .. passage.Key
        holder:SetAttribute("A", passage.A)
        holder:SetAttribute("B", passage.B)
        local midpoint, horizontal = RoomGenerator.EdgeInfo(plan.Layout, passage.A, passage.B)
        RoomDecor.Passage(holder, wallFrame(midpoint, horizontal), MAP.WallThickness, palette)
        holder.Parent = folder
    end
end

function RoomGenerator.Build(plan, theme)
    local layout = plan.Layout

    local oldMap = workspace:FindFirstChild("NOCTURNA_MAP")
    if oldMap then
        oldMap:Destroy()
    end

    local map = Instance.new("Folder")
    map.Name = "NOCTURNA_MAP"

    local sectors = Instance.new("Folder")
    sectors.Name = "Sectors"
    sectors.Parent = map

    local size = MAP.CellSize
    local height = MAP.WallHeight
    local floorMaterial = PropKit.Material(theme.FloorMaterial)
    local ceilingMaterial = PropKit.Material(theme.CeilingMaterial or "Concrete")
    local palette = RoomDecor.Palette(theme)
    local rng = Rng.new((layout.Seed or 0) * 3 + 11)

    for _, cell in ipairs(layout.Cells) do
        local center = cellCenter(cell)
        local centerX, centerZ = center.X, center.Z

        local sector = Instance.new("Model")
        sector.Name = string.format("Sector_%02d_%02d", cell.X, cell.Z)
        sector:SetAttribute("GridX", cell.X)
        sector:SetAttribute("GridZ", cell.Z)
        sector:SetAttribute("Role", cell.Role)

        -- Cada celda varía apenas de tono: dos salas vecinas nunca son idénticas.
        local wallColor = PropKit.Vary(theme.Wall, rng, 0.07)
        createPart(
            sector,
            "Floor",
            Vector3.new(size, MAP.FloorThickness, size),
            Vector3.new(centerX, -MAP.FloorThickness / 2, centerZ),
            PropKit.Vary(theme.Floor, rng, 0.08),
            floorMaterial
        )
        createPart(
            sector,
            "Ceiling",
            Vector3.new(size, 2, size),
            Vector3.new(centerX, height + 1, centerZ),
            PropKit.Vary(theme.Ceiling, rng, 0.06),
            ceilingMaterial
        )

        buildWall(sector, Vector3.new(centerX, 0, centerZ - size / 2), size, sideStatus(plan, layout, cell, "N"), true, theme, wallColor)
        buildWall(sector, Vector3.new(centerX - size / 2, 0, centerZ), size, sideStatus(plan, layout, cell, "W"), false, theme, wallColor)

        if cell.Z == layout.Depth then
            buildWall(sector, Vector3.new(centerX, 0, centerZ + size / 2), size, nil, true, theme, wallColor)
        end
        if cell.X == layout.Width then
            buildWall(sector, Vector3.new(centerX + size / 2, 0, centerZ), size, nil, false, theme, wallColor)
        end

        if cell.Role == "Corridor" then
            buildCorridorBlocks(sector, center, theme, wallColor)
        end

        addLight(sector, center, cell.Index, theme, palette)
        sector.Parent = sectors
    end

    buildPassages(plan, theme, palette, map)

    map:SetAttribute("SectorCount", #layout.Cells)
    map.Parent = workspace
    map:SetAttribute("Generated", true)
    return map
end

-- Amueblado ---------------------------------------------------------------------------

-- Paredes que construye cada celda (N y W, más las del borde), con su estado.
local function ownWalls(plan, layout, cell)
    local center = cellCenter(cell)
    local half = MAP.CellSize / 2
    local walls = {
        {Center = center + Vector3.new(0, 0, -half), Horizontal = true, Status = sideStatus(plan, layout, cell, "N")},
        {Center = center + Vector3.new(-half, 0, 0), Horizontal = false, Status = sideStatus(plan, layout, cell, "W")},
    }
    if cell.Z == layout.Depth then
        table.insert(walls, {Center = center + Vector3.new(0, 0, half), Horizontal = true})
    end
    if cell.X == layout.Width then
        table.insert(walls, {Center = center + Vector3.new(half, 0, 0), Horizontal = false})
    end
    return walls
end

local function trimWalls(plan, layout, cell, theme, palette, parent)
    for _, wall in ipairs(ownWalls(plan, layout, cell)) do
        local frame = wallFrame(wall.Center, wall.Horizontal)
        local gap, gapHeight = gapFor(wall.Status)
        if not PropKit.Fits(10) then
            return
        end

        if gap == 0 then
            RoomDecor.WallTrim(parent, theme.Trim, frame, MAP.CellSize, MAP.WallThickness, theme, palette)
        else
            local segment = (MAP.CellSize - gap) / 2
            for _, side in ipairs({-1, 1}) do
                local offset = side * (gap / 2 + segment / 2)
                RoomDecor.WallTrim(parent, theme.Trim, frame * CFrame.new(offset, 0, 0), segment, MAP.WallThickness, theme, palette)
            end
            if wall.Status == "Open" then
                RoomDecor.DoorFrame(parent, frame, gap, gapHeight, MAP.WallThickness, theme, palette)
            end
        end
    end
end

-- Huecos libres a lo largo de cada lado, según lo que haya en esa pared.
local FREE_EDGE = 9
local DEEP_EDGE = 7
local DEEP = 4.6

local function zonesFor(status)
    if status == "Open" then
        return {{-FREE_EDGE, -(MAP.CorridorWidth / 2 + 1.2)}, {MAP.CorridorWidth / 2 + 1.2, FREE_EDGE}}, true
    elseif status == "Passage" then
        local edge = RoomDecor.PassageWidth / 2 + 1.3
        return {{-FREE_EDGE, -edge}, {edge, FREE_EDGE}}, false
    end
    return {{-FREE_EDGE, FREE_EDGE}}, false
end

local function placePiece(parent, name, frame, lateral, palette, rng)
    local spec = RoomDecor.Furniture[name]
    local base = frame * CFrame.new(lateral, 0, -spec.Depth / 2)
    local holder = Instance.new("Model")
    holder.Name = name
    holder.Parent = parent
    PropKit.Visual(holder, name, base, function(target)
        spec.Build(target, base, palette, rng)
    end)
end

-- Elige y ubica muebles en un hueco [from, to] de una pared. Devuelve cuántos puso.
local function fillZone(parent, frame, zone, names, smallOnly, palette, rng, limit)
    local from, to = zone[1], zone[2]
    local placed = 0
    local cursor = from

    for _ = 1, #names do
        if placed >= limit or not PropKit.Fits(16) then
            break
        end
        local name = names[rng:Int(1, #names)]
        local spec = RoomDecor.Furniture[name]
        if spec and (spec.Small or not smallOnly) then
            local deep = spec.Depth > DEEP
            local left = deep and math.max(cursor, -DEEP_EDGE) or cursor
            local right = deep and math.min(to, DEEP_EDGE) or to
            local room = right - left
            if spec.Width <= room then
                -- Un poco de juego para que no queden todos alineados al milímetro.
                local slack = math.min(room - spec.Width, placed == 0 and 2.5 or 0.6)
                local start = left + rng:Float() * slack
                placePiece(parent, name, frame, start + spec.Width / 2, palette, rng)
                cursor = start + spec.Width + 0.8
                placed += 1
            end
        end
    end
    return placed
end

local function furnishRoom(plan, layout, cell, theme, palette, rng, parent, roomType)
    local center = cellCenter(cell)
    local closedFaces = {}

    for _, side in ipairs(SIDE_ORDER) do
        local status = sideStatus(plan, layout, cell, side)
        local frame = sideFrame(center, side)
        if not status then
            table.insert(closedFaces, frame)
        end

        local zones, smallOnly = zonesFor(status)
        for _, zone in ipairs(zones) do
            if smallOnly then
                if rng:Chance(0.45) then
                    fillZone(parent, frame, zone, roomType.Small, true, palette, rng, 1)
                end
            elseif status == "Passage" then
                fillZone(parent, frame, zone, roomType.Large, false, palette, rng, 1)
            elseif rng:Chance(0.85) then
                fillZone(parent, frame, zone, roomType.Large, false, palette, rng, 2)
            end
        end
    end

    return closedFaces
end

-- Agrega terminaciones y muebles hasta `limit` piezas en total en el mapa. Va por
-- pasadas (primero lo que más se nota) para que, si el presupuesto no alcanza,
-- ninguna sala quede pelada mientras otra está llena.
function RoomGenerator.Furnish(plan, theme, map, limit)
    local layout = plan.Layout
    local palette = RoomDecor.Palette(theme)
    local rng = Rng.new((layout.Seed or 0) * 7 + 3)
    PropKit.ResetBudget(limit)

    local decor = Instance.new("Folder")
    decor.Name = "Decor"
    decor.Parent = map

    local rooms = {}
    for _, cell in ipairs(layout.Cells) do
        local holder = Instance.new("Model")
        holder.Name = string.format("Room_%02d_%02d", cell.X, cell.Z)
        local types = theme.RoomTypes or {}
        local typeName = #types > 0 and types[rng:Int(1, #types)] or nil
        if cell.Role == "Corridor" then
            typeName = nil
        end
        holder:SetAttribute("RoomType", typeName or "Corridor")
        holder.Parent = decor
        rooms[cell.Index] = {Cell = cell, Holder = holder, Type = typeName, Faces = {}}
    end

    -- 1. Zócalos y marcos de puertas.
    for _, room in ipairs(rooms) do
        trimWalls(plan, layout, room.Cell, theme, palette, room.Holder)
    end

    -- 2. Lo que cuelga del techo.
    local kit = RoomDecor.Ceiling[theme.CeilingKit or ""]
    if kit then
        for _, room in ipairs(rooms) do
            if PropKit.Fits(8) then
                kit(room.Holder, cellCenter(room.Cell), palette, rng, room.Cell.Role == "Corridor", theme)
            end
        end
    end

    -- 3. Muebles según el tipo de sala.
    for _, room in ipairs(rooms) do
        local roomType = room.Type and RoomDecor.RoomTypes[room.Type]
        if roomType then
            room.Faces = furnishRoom(plan, layout, room.Cell, theme, palette, rng, room.Holder, roomType)
        end
    end

    -- 4. Mugre, manchas y papeles.
    for _, room in ipairs(rooms) do
        if PropKit.Fits(8) then
            RoomDecor.Grime(room.Holder, cellCenter(room.Cell), theme, palette, rng, room.Faces)
        end
    end

    return decor
end

function RoomGenerator.StartCFrame(layout, index)
    local cell = layout.Cells[layout.Start]
    local offsetX = ((index or 1) - 2.5) * 3
    return CFrame.new((cell.X - 1) * MAP.CellSize + offsetX, 3.5, (cell.Z - 1) * MAP.CellSize)
end

return RoomGenerator
