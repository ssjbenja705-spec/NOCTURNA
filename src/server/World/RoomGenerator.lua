-- Convierte un plan de capítulo en geometría. Todas las piezas son anclas simples
-- para mantener el mapa liviano en celulares.
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)

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

local function buildWall(parent, center, width, opening, horizontal, theme)
    local height = MAP.WallHeight
    local thickness = MAP.WallThickness
    local openingWidth = MAP.CorridorWidth
    local color = theme.Wall
    local material = Enum.Material[theme.WallMaterial]
    local wallY = center.Y + height / 2

    if not opening then
        local wallSize = horizontal
            and Vector3.new(width, height, thickness)
            or Vector3.new(thickness, height, width)
        createPart(parent, "Wall", wallSize, Vector3.new(center.X, wallY, center.Z), color, material)
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
        createPart(parent, "Wall", segmentSize, segmentPosition, color, material)
    end

    local headerHeight = height - MAP.OpeningHeight
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
local function buildCorridorBlocks(parent, center, theme)
    local block = (MAP.CellSize - MAP.CorridorWidth) / 2 - MAP.WallThickness / 2
    local offset = MAP.CorridorWidth / 2 + block / 2
    local material = Enum.Material[theme.WallMaterial]

    for _, sideX in ipairs({-1, 1}) do
        for _, sideZ in ipairs({-1, 1}) do
            createPart(
                parent,
                "CorridorBlock",
                Vector3.new(block, MAP.WallHeight, block),
                center + Vector3.new(sideX * offset, MAP.WallHeight / 2, sideZ * offset),
                theme.Wall,
                material
            )
        end
    end
end

local function addLight(parent, position, cellIndex, theme)
    local fixture = createPart(
        parent,
        "CeilingLight",
        Vector3.new(6, 0.5, 2.5),
        position,
        Color3.fromRGB(105, 125, 135),
        Enum.Material.SmoothPlastic
    )
    fixture.CanCollide = false
    fixture.CastShadow = false
    fixture:SetAttribute("Cell", cellIndex)

    local light = Instance.new("PointLight")
    light.Color = theme.Light
    light.Brightness = 0.9
    light.Range = 26
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
    local floorMaterial = Enum.Material[theme.FloorMaterial]

    for _, cell in ipairs(layout.Cells) do
        local centerX = (cell.X - 1) * size
        local centerZ = (cell.Z - 1) * size
        local center = Vector3.new(centerX, 0, centerZ)

        local sector = Instance.new("Model")
        sector.Name = string.format("Sector_%02d_%02d", cell.X, cell.Z)
        sector:SetAttribute("GridX", cell.X)
        sector:SetAttribute("GridZ", cell.Z)
        sector:SetAttribute("Role", cell.Role)

        createPart(
            sector,
            "Floor",
            Vector3.new(size, MAP.FloorThickness, size),
            Vector3.new(centerX, -MAP.FloorThickness / 2, centerZ),
            theme.Floor,
            floorMaterial
        )
        createPart(
            sector,
            "Ceiling",
            Vector3.new(size, 2, size),
            Vector3.new(centerX, height + 1, centerZ),
            theme.Ceiling
        )

        buildWall(sector, Vector3.new(centerX, 0, centerZ - size / 2), size, cell.Open.N, true, theme)
        buildWall(sector, Vector3.new(centerX - size / 2, 0, centerZ), size, cell.Open.W, false, theme)

        if cell.Z == layout.Depth then
            buildWall(sector, Vector3.new(centerX, 0, centerZ + size / 2), size, false, true, theme)
        end
        if cell.X == layout.Width then
            buildWall(sector, Vector3.new(centerX + size / 2, 0, centerZ), size, false, false, theme)
        end

        if cell.Role == "Corridor" then
            buildCorridorBlocks(sector, center, theme)
        end

        addLight(sector, Vector3.new(centerX, height - 0.3, centerZ), cell.Index, theme)
        sector.Parent = sectors
    end

    map:SetAttribute("SectorCount", #layout.Cells)
    map.Parent = workspace
    map:SetAttribute("Generated", true)
    return map
end

function RoomGenerator.StartCFrame(layout, index)
    local cell = layout.Cells[layout.Start]
    local offsetX = ((index or 1) - 2.5) * 3
    return CFrame.new((cell.X - 1) * MAP.CellSize + offsetX, 3.5, (cell.Z - 1) * MAP.CellSize)
end

return RoomGenerator
