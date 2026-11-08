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
local Weathering = require(script.Parent.Weathering)

local MAP = GameConfig.Map
-- Piezas apartadas por sala para el desgaste y el tope por sala.
local WEATHER_RESERVE = 7
local WEATHER_MAX = 16

local RoomGenerator = {}
-- Paredes y salas del último amueblado, para la pasada de desgaste.
local furnished = nil

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
        PropKit.Surface(createPart(parent, "Wall", wallSize, Vector3.new(center.X, wallY, center.Z), color, material), theme, "Wall")
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
        PropKit.Surface(createPart(parent, "Wall", segmentSize, segmentPosition, color, material), theme, "Wall")
    end

    local headerHeight = height - openingHeight
    local headerSize = horizontal
        and Vector3.new(openingWidth, headerHeight, thickness)
        or Vector3.new(thickness, headerHeight, openingWidth)
    local header = createPart(
        parent,
        "OpeningHeader",
        headerSize,
        Vector3.new(center.X, center.Y + height - headerHeight / 2, center.Z),
        color,
        material
    )
    PropKit.Surface(header, theme, "Wall")
end

-- Las celdas "Corridor" se vuelven pasillos en cruz con cuatro bloques macizos.
local function buildCorridorBlocks(parent, center, theme, color)
    local block = (MAP.CellSize - MAP.CorridorWidth) / 2 - MAP.WallThickness / 2
    local offset = MAP.CorridorWidth / 2 + block / 2
    local material = PropKit.Material(theme.WallMaterial)

    for _, sideX in ipairs({-1, 1}) do
        for _, sideZ in ipairs({-1, 1}) do
            local blockPart = createPart(
                parent,
                "CorridorBlock",
                Vector3.new(block, MAP.WallHeight, block),
                center + Vector3.new(sideX * offset, MAP.WallHeight / 2, sideZ * offset),
                color,
                material
            )
            PropKit.Surface(blockPart, theme, "Wall")
        end
    end
end

-- Luz de cada sala ------------------------------------------------------------------
-- Ninguna sala se ilumina igual: según Mood del tema la lámpara puede estar tenue,
-- titilar (lo hace el cliente, AmbientMotion), o estar rota y dejar la sala en
-- penumbra (sólo la luz ambiente y la linterna). La sala de inicio siempre tiene luz.
local LIGHT_LEVELS = {
    Normal = {Brightness = 1, Range = 28},
    Dim = {Brightness = 0.5, Range = 20},
    Flicker = {Brightness = 0.9, Range = 26},
}
RoomGenerator.LightLevels = LIGHT_LEVELS

local DEAD_BULB = Color3.fromRGB(46, 44, 40)

local function pickLightState(mood, rng, isStart)
    if isStart then
        return "Normal"
    end
    local roll = rng:Float()
    local broken = mood.Broken or 0
    local dim = broken + (mood.Dim or 0)
    local flicker = dim + (mood.Flicker or 0)
    if roll < broken then
        return "Broken"
    elseif roll < dim then
        return "Dim"
    elseif roll < flicker then
        return "Flicker"
    end
    return "Normal"
end

-- Haz de luz falso: un Beam del foco al piso que se abre y se desvanece. No es una
-- pieza (no gasta presupuesto); el cliente lo apaga si la lámpara se apaga.
local function addShaft(fixture, floor, color)
    local top = Instance.new("Attachment")
    top.Name = "ShaftTop"
    top.Parent = fixture
    local bottom = Instance.new("Attachment")
    bottom.Name = "ShaftBottom"
    bottom.Position = Vector3.new(0, MAP.FloorThickness / 2, 0)
    bottom.Parent = floor

    local beam = Instance.new("Beam")
    beam.Name = "LightShaft"
    beam.Attachment0 = top
    beam.Attachment1 = bottom
    beam.Color = ColorSequence.new(color)
    beam.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.8),
        NumberSequenceKeypoint.new(0.55, 0.92),
        NumberSequenceKeypoint.new(1, 1),
    })
    beam.Width0 = 1.6
    beam.Width1 = 13
    beam.FaceCamera = true
    beam.LightEmission = 0.6
    beam.LightInfluence = 0
    beam.Segments = 1
    beam.Parent = fixture
    CollectionService:AddTag(beam, Weathering.FX_TAG)
    return beam
end

-- Polvo que cae despacio del techo. Sólo se ve donde hay luz (LightInfluence 1):
-- marca los bolsillos iluminados y deja negros los rincones.
local function addDust(ceiling, color)
    local dust = Instance.new("ParticleEmitter")
    dust.Name = "Dust"
    dust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    dust.Color = ColorSequence.new(color)
    dust.LightEmission = 0
    dust.LightInfluence = 1
    dust.Size = NumberSequence.new(0.08)
    dust.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.2, 0.35),
        NumberSequenceKeypoint.new(1, 1),
    })
    dust.Lifetime = NumberRange.new(9, 14)
    dust.Speed = NumberRange.new(0.3, 0.7)
    dust.SpreadAngle = Vector2.new(35, 35)
    dust.Drag = 0.4
    dust.Rate = 5
    dust.Shape = Enum.ParticleEmitterShape.Box
    dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
    dust.EmissionDirection = Enum.NormalId.Bottom
    dust.Parent = ceiling
    CollectionService:AddTag(dust, Weathering.FX_TAG)
    return dust
end

-- Baliza de emergencia en una pared cerrada: caja, lente y una luz chica de color
-- que siempre queda prendida (va con batería). Se apaga en bajo consumo.
local function addEmergencyLamp(parent, frame, theme, palette)
    local color = theme.EmergencyLight or Color3.fromRGB(170, 40, 34)
    local base = frame * CFrame.new(0, 10.6, 0)
    PropKit.Part(parent, "BeaconBox", Vector3.new(1.4, 0.7, 0.5), base * CFrame.new(0, 0, -0.25), PropKit.Shade(palette.Metal, 0.7), PropKit.Material("Metal"))
    local lens = PropKit.Part(parent, "BeaconLens", Vector3.new(1, 0.4, 0.2), base * CFrame.new(0, -0.05, -0.55), color, PropKit.Material("Neon"))
    local light = PropKit.Light(lens, "PointLight", color, 0.7, 15, false)
    light.Name = "BeaconLight"
    CollectionService:AddTag(lens, "NocturnaDecorLight")
    return lens
end

local function addLight(parent, center, cell, theme, palette, rng, parts)
    local mood = theme.Mood or {}
    local isStart = parts.IsStart
    local state = pickLightState(mood, rng, isStart)
    local fixture = RoomDecor.Fixture(parent, theme.Fixture, center + Vector3.new(0, MAP.WallHeight, 0), palette)
    fixture.CanCollide = false
    fixture.CastShadow = false
    fixture:SetAttribute("Cell", cell.Index)
    fixture:SetAttribute("LightState", state)

    if state == "Broken" then
        -- Lámpara quemada: sin luz y sin etiqueta, así la IA sabe que acá está oscuro.
        fixture.Color = DEAD_BULB
        fixture.Material = Enum.Material.Glass
        return fixture
    end

    local level = LIGHT_LEVELS[state]
    local color = PropKit.Vary(theme.Light, rng, 0.05)
    fixture:SetAttribute("BaseBrightness", level.Brightness)
    fixture:SetAttribute("BaseRange", level.Range)
    fixture:SetAttribute("BaseColor", color)
    if state == "Flicker" then
        fixture:SetAttribute("Flicker", true)
    end

    local light = Instance.new("PointLight")
    light.Color = color
    light.Brightness = level.Brightness
    light.Range = level.Range
    -- Sombras sólo en las salas con haz de luz: pocas, y las que más se lucen.
    light.Shadows = false
    light.Parent = fixture

    if not isStart and cell.Role ~= "Corridor" and rng:Chance(mood.Shafts or 0) then
        addShaft(fixture, parts.Floor, color)
        light.Shadows = true
    end
    if rng:Chance(mood.Dust or 0) then
        addDust(parts.Ceiling, mood.DustColor or color)
    end

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
    local lightRng = Rng.new((layout.Seed or 0) * 17 + 3)
    PropKit.RefreshSurfaces()

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
        local floor = createPart(
            sector,
            "Floor",
            Vector3.new(size, MAP.FloorThickness, size),
            Vector3.new(centerX, -MAP.FloorThickness / 2, centerZ),
            PropKit.Vary(theme.Floor, rng, 0.08),
            floorMaterial
        )
        PropKit.Surface(floor, theme, "Floor")
        local ceiling = createPart(
            sector,
            "Ceiling",
            Vector3.new(size, 2, size),
            Vector3.new(centerX, height + 1, centerZ),
            PropKit.Vary(theme.Ceiling, rng, 0.06),
            ceilingMaterial
        )
        PropKit.Surface(ceiling, theme, "Ceiling")

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

        addLight(sector, center, cell, theme, palette, lightRng, {
            Floor = floor,
            Ceiling = ceiling,
            IsStart = cell.Index == layout.Start,
        })
        -- Baliza de emergencia en una pared cerrada (contraste de color en la penumbra).
        if lightRng:Chance((theme.Mood or {}).Emergency or 0) then
            for _, side in ipairs(SIDE_ORDER) do
                if not sideStatus(plan, layout, cell, side) then
                    addEmergencyLamp(sector, sideFrame(center, side), theme, palette)
                    break
                end
            end
        end
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
-- `occupied` (opcional) recibe los tramos de pared que quedaron tapados.
local function fillZone(parent, frame, zone, names, smallOnly, palette, rng, limit, occupied)
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
                if occupied then
                    table.insert(occupied, {start - 0.4, start + spec.Width + 0.4})
                end
                cursor = start + spec.Width + 0.8
                placed += 1
            end
        end
    end
    return placed
end

-- Paredes cerradas de una celda, con lo que quedó tapado por muebles en cada una.
local function closedWalls(plan, layout, cell)
    local center = cellCenter(cell)
    local walls = {}
    for _, side in ipairs(SIDE_ORDER) do
        if not sideStatus(plan, layout, cell, side) then
            walls[side] = {Frame = sideFrame(center, side), Occupied = {}}
        end
    end
    return walls
end

local function furnishRoom(plan, layout, cell, palette, rng, parent, roomType, walls)
    local center = cellCenter(cell)

    for _, side in ipairs(SIDE_ORDER) do
        local status = sideStatus(plan, layout, cell, side)
        local frame = sideFrame(center, side)
        local occupied = walls[side] and walls[side].Occupied or nil

        local zones, smallOnly = zonesFor(status)
        for _, zone in ipairs(zones) do
            if smallOnly then
                if rng:Chance(0.45) then
                    fillZone(parent, frame, zone, roomType.Small, true, palette, rng, 1)
                end
            elseif status == "Passage" then
                fillZone(parent, frame, zone, roomType.Large, false, palette, rng, 1)
            elseif rng:Chance(0.85) then
                fillZone(parent, frame, zone, roomType.Large, false, palette, rng, 2, occupied)
            end
        end
    end
end

-- Tramos libres de una pared para dañarla: lejos de los rincones (escondites,
-- máquinas y objetos van ahí) y de los muebles que se apoyan en ella.
local DAMAGE_EDGE = 11
local CORRIDOR_EDGE = MAP.CorridorWidth / 2 - 1.2

local function freeSpans(occupied, edge)
    local spans = {{-edge, edge}}
    for _, block in ipairs(occupied) do
        local nextSpans = {}
        for _, span in ipairs(spans) do
            if block[2] <= span[1] or block[1] >= span[2] then
                table.insert(nextSpans, span)
            else
                if block[1] - span[1] > 1.5 then
                    table.insert(nextSpans, {span[1], block[1]})
                end
                if span[2] - block[2] > 1.5 then
                    table.insert(nextSpans, {block[2], span[2]})
                end
            end
        end
        spans = nextSpans
    end
    return spans
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
        rooms[cell.Index] = {Cell = cell, Holder = holder, Type = typeName, Walls = closedWalls(plan, layout, cell)}
    end
    furnished = {Rooms = rooms, Map = map}
    -- Lo mínimo para el desgaste de las paredes queda apartado: los muebles y la
    -- utilería de los rincones no se lo pueden comer (ver RoomGenerator.Weather).
    PropKit.SetReserve(#layout.Cells * WEATHER_RESERVE)

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
            furnishRoom(plan, layout, room.Cell, palette, rng, room.Holder, roomType, room.Walls)
        end
    end

    -- 4. Mugre, manchas y papeles.
    for _, room in ipairs(rooms) do
        if PropKit.Fits(8) then
            local faces = {}
            for _, side in ipairs(SIDE_ORDER) do
                local wall = room.Walls[side]
                if wall then
                    table.insert(faces, wall.Frame)
                end
            end
            RoomDecor.Grime(room.Holder, cellCenter(room.Cell), theme, palette, rng, faces)
        end
    end

    return decor
end

-- Desgaste: zarpazos, grietas, descascarado, humedad, charcos y pisos gastados.
-- Va al final (después de la utilería de los rincones) y reparte lo que queda del
-- presupuesto en partes iguales, así ninguna sala queda impecable.
function RoomGenerator.Weather(plan, theme, map)
    local state = furnished
    furnished = nil
    PropKit.SetReserve(0)
    if not state or state.Map ~= map then
        return 0
    end

    local palette = RoomDecor.Palette(theme)
    local rng = Rng.new((plan.Layout.Seed or 0) * 13 + 5)
    local rooms = state.Rooms
    local total = 0
    for index, room in ipairs(rooms) do
        local corridor = room.Cell.Role == "Corridor"
        local walls = {}
        for _, side in ipairs(SIDE_ORDER) do
            local wall = room.Walls[side]
            if wall then
                local spans = freeSpans(wall.Occupied, corridor and CORRIDOR_EDGE or DAMAGE_EDGE)
                if #spans > 0 then
                    table.insert(walls, {Frame = wall.Frame, Free = spans})
                end
            end
        end
        local share = math.floor(PropKit.Remaining() / (#rooms - index + 1))
        local allowance = math.min(share, WEATHER_MAX)
        if allowance > 0 then
            local holder = room.Holder:FindFirstChild("Weathering") or Instance.new("Folder")
            holder.Name = "Weathering"
            holder.Parent = room.Holder
            total += Weathering.Room(holder, cellCenter(room.Cell), walls, theme, palette, rng, allowance, {
                Corridor = corridor,
                -- La sala de inicio queda seca: el primer vistazo no es un charco.
                NoPuddle = room.Cell.Index == plan.Layout.Start,
            })
        end
    end
    return total
end

function RoomGenerator.StartCFrame(layout, index)
    local cell = layout.Cells[layout.Start]
    local offsetX = ((index or 1) - 2.5) * 3
    return CFrame.new((cell.X - 1) * MAP.CellSize + offsetX, 3.5, (cell.Z - 1) * MAP.CellSize)
end

return RoomGenerator
