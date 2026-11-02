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
    part.Parent = parent
    return part
end

local function cellKey(x, z)
    return tostring(x) .. "_" .. tostring(z)
end

local function buildMaze(width, depth, seed)
    local random = Random.new(seed)
    local cells = {}

    for x = 1, width do
        for z = 1, depth do
            cells[cellKey(x, z)] = {
                x = x,
                z = z,
                visited = false,
                openings = {
                    North = false,
                    South = false,
                    East = false,
                    West = false,
                },
            }
        end
    end

    local directions = {
        {dx = 0, dz = -1, from = "North", to = "South"},
        {dx = 0, dz = 1, from = "South", to = "North"},
        {dx = 1, dz = 0, from = "East", to = "West"},
        {dx = -1, dz = 0, from = "West", to = "East"},
    }

    local stack = {}
    local start = cells[cellKey(1, 1)]
    start.visited = true
    table.insert(stack, start)

    while #stack > 0 do
        local current = stack[#stack]
        local available = {}

        for _, direction in ipairs(directions) do
            local neighbor = cells[cellKey(
                current.x + direction.dx,
                current.z + direction.dz
            )]

            if neighbor and not neighbor.visited then
                table.insert(available, {cell = neighbor, direction = direction})
            end
        end

        if #available == 0 then
            table.remove(stack)
        else
            local choice = available[random:NextInteger(1, #available)]
            current.openings[choice.direction.from] = true
            choice.cell.openings[choice.direction.to] = true
            choice.cell.visited = true
            table.insert(stack, choice.cell)
        end
    end

    return cells
end

local function buildWall(parent, center, width, height, thickness, opening, horizontal, color, openingWidth)
    local wallY = center.Y + height / 2

    if not opening then
        local wallSize = horizontal
            and Vector3.new(width, height, thickness)
            or Vector3.new(thickness, height, width)
        createPart(parent, "ConcreteWall", wallSize, Vector3.new(center.X, wallY, center.Z), color)
        return
    end

    local segmentWidth = (width - openingWidth) / 2
    for _, side in ipairs({-1, 1}) do
        local offset = side * (openingWidth / 2 + segmentWidth / 2)
        local segmentSize = horizontal
            and Vector3.new(segmentWidth, height, thickness)
            or Vector3.new(thickness, height, segmentWidth)
        local segmentPosition = horizontal
            and Vector3.new(center.X + offset, wallY, center.Z)
            or Vector3.new(center.X, wallY, center.Z + offset)
        createPart(parent, "ConcreteWall", segmentSize, segmentPosition, color)
    end

    local headerSize = horizontal
        and Vector3.new(openingWidth, 4, thickness)
        or Vector3.new(thickness, 4, openingWidth)
    createPart(
        parent,
        "OpeningHeader",
        headerSize,
        Vector3.new(center.X, center.Y + height - 2, center.Z),
        color
    )
end

local function addLight(parent, position, config)
    local fixture = createPart(
        parent,
        "CeilingLight",
        Vector3.new(7, 0.5, 3),
        position,
        Color3.fromRGB(105, 125, 135),
        Enum.Material.Metal
    )

    local light = Instance.new("PointLight")
    light.Color = config.Colors.Light
    light.Brightness = 0.7
    light.Range = 28
    light.Shadows = true
    light.Parent = fixture
end

function RoomGenerator.Generate(config)
    assert(typeof(config) == "table", "Map configuration must be a table")
    assert(config.Width >= 1 and config.Width % 1 == 0, "Map width must be a positive integer")
    assert(config.Depth >= 1 and config.Depth % 1 == 0, "Map depth must be a positive integer")
    assert(config.CorridorWidth > 0 and config.CorridorWidth < config.CellSize, "Corridor width must fit inside a cell")

    local oldMap = workspace:FindFirstChild("NOCTURNA_MAP")
    if oldMap then oldMap:Destroy() end

    local map = Instance.new("Folder")
    map.Name = "NOCTURNA_MAP"
    map.Parent = workspace

    local rooms = Instance.new("Folder")
    rooms.Name = "Sectors"
    rooms.Parent = map

    local markers = Instance.new("Folder")
    markers.Name = "MonsterSpawns"
    markers.Parent = map

    local width = config.Width
    local depth = config.Depth
    local size = config.CellSize
    local wallHeight = config.WallHeight
    local thickness = config.WallThickness
    local cells = buildMaze(width, depth, config.Seed or 0)

    for x = 1, width do
        for z = 1, depth do
            local cell = cells[cellKey(x, z)]
            local centerX = (x - 1) * size
            local centerZ = (z - 1) * size
            local sector = Instance.new("Model")
            sector.Name = string.format("Sector_%02d_%02d", x, z)
            sector.Parent = rooms
            sector:SetAttribute("GridX", x)
            sector:SetAttribute("GridZ", z)

            createPart(
                sector,
                "Floor",
                Vector3.new(size, config.FloorThickness, size),
                Vector3.new(centerX, -config.FloorThickness / 2, centerZ),
                config.Colors.Floor
            )
            createPart(
                sector,
                "Ceiling",
                Vector3.new(size, 2, size),
                Vector3.new(centerX, wallHeight + 1, centerZ),
                config.Colors.Ceiling
            )

            local northCenter = Vector3.new(centerX, 0, centerZ - size / 2)
            local westCenter = Vector3.new(centerX - size / 2, 0, centerZ)

            buildWall(sector, northCenter, size, wallHeight, thickness, cell.openings.North, true, config.Colors.Wall, config.CorridorWidth)
            buildWall(sector, westCenter, size, wallHeight, thickness, cell.openings.West, false, config.Colors.Wall, config.CorridorWidth)

            if z == depth then
                buildWall(
                    sector,
                    Vector3.new(centerX, 0, centerZ + size / 2),
                    size,
                    wallHeight,
                    thickness,
                    false,
                    true,
                    config.Colors.Wall,
                    config.CorridorWidth
                )
            end
            if x == width then
                buildWall(
                    sector,
                    Vector3.new(centerX + size / 2, 0, centerZ),
                    size,
                    wallHeight,
                    thickness,
                    false,
                    false,
                    config.Colors.Wall,
                    config.CorridorWidth
                )
            end

            addLight(sector, Vector3.new(centerX, wallHeight - 1, centerZ), config)
        end
    end

    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "PlayerSpawn"
    spawn.Size = Vector3.new(8, 1, 8)
    spawn.Position = Vector3.new(0, 1, 0)
    spawn.Anchored = true
    spawn.Neutral = true
    spawn.Material = Enum.Material.Metal
    spawn.Color = Color3.fromRGB(45, 55, 60)
    spawn.Parent = map

    local monsterPositions = {
        ElOyente = Vector3.new(size * 2, 2, size * 2),
        ElImitador = Vector3.new(size * 4, 2, size),
        ElQuieto = Vector3.new(size * 3, 2, size * 4),
        ElTrepador = Vector3.new(size, 2, size * 4),
        ElColoso = Vector3.new(size * 4, 2, size * 4),
    }

    for monsterName, position in pairs(monsterPositions) do
        local marker = Instance.new("Part")
        marker.Name = monsterName
        marker.Size = Vector3.new(3, 1, 3)
        marker.Position = position
        marker.Anchored = true
        marker.CanCollide = false
        marker.CanTouch = false
        marker.Transparency = 1
        marker:SetAttribute("MonsterType", monsterName)
        marker.Parent = markers
    end

    map:SetAttribute("Generated", true)
    map:SetAttribute("SectorCount", width * depth)
    return map
end

return RoomGenerator
