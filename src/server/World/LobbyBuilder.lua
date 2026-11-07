-- Recepción de la Fundación Leteo: el lobby se camina. Sala de espera con mostrador,
-- bancos, carteles y ventanales con lluvia; al fondo la fila de ascensores donde se
-- arman los grupos y, a un costado, el rincón de los donantes. En un servidor de
-- partida sólo se arma la sala de espera. Piezas simples con materiales reales y
-- pocas luces, para que ande bien en celulares.
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local LobbyConfig = require(Shared.Config.LobbyConfig)
local ServerMode = require(script.Parent.Parent.Lobby.ServerMode)

local ORIGIN = GameConfig.Map.LobbyOrigin
local HALF_X = 40
local HALF_Z = 30
local HEIGHT = 16
local ELEVATOR_X = {-27, -9, 9, 27}
local DOOR_WIDTH = 8
local DOOR_HEIGHT = 10
local CABIN_DEPTH = 10
local WINDOW_X = {-28, -14, 14, 28}
local FLICKER_TAG = "NocturnaLobbyFlicker"
local RAIN_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local M = Enum.Material
local NORMAL = Enum.NormalId

local COLORS = {
    Floor = Color3.fromRGB(54, 56, 52),
    Wall = Color3.fromRGB(86, 92, 82),
    Ceiling = Color3.fromRGB(36, 37, 35),
    Wood = Color3.fromRGB(56, 39, 29),
    Brass = Color3.fromRGB(146, 116, 62),
    Iron = Color3.fromRGB(34, 34, 36),
    Steel = Color3.fromRGB(116, 112, 102),
    Paper = Color3.fromRGB(194, 184, 154),
    Leather = Color3.fromRGB(70, 30, 30),
    Glass = Color3.fromRGB(70, 86, 96),
    Fluorescent = Color3.fromRGB(196, 214, 200),
    Warm = Color3.fromRGB(255, 190, 120),
    Sodium = Color3.fromRGB(255, 150, 70),
    Ink = Color3.fromRGB(30, 26, 22),
    SignText = Color3.fromRGB(214, 206, 186),
    Accent = Color3.fromRGB(196, 158, 96),
    Blood = Color3.fromRGB(120, 24, 22),
}

local LobbyBuilder = {}
local center = Vector3.zero
local elevators = {}
local podiums = {}
local donationPrompt = nil
local statueFolder = nil

local function origin()
    return Vector3.new(ORIGIN.X, ORIGIN.Y, ORIGIN.Z)
end

local function at(x, y, z)
    return center + Vector3.new(x, y, z)
end

local function part(parent, name, size, placement, color, material, properties)
    local piece = Instance.new("Part")
    piece.Name = name
    piece.Size = size
    if typeof(placement) == "CFrame" then
        piece.CFrame = placement
    else
        piece.Position = placement
    end
    piece.Anchored = true
    piece.Color = color
    piece.Material = material
    piece.TopSurface = Enum.SurfaceType.Smooth
    piece.BottomSurface = Enum.SurfaceType.Smooth
    piece.CanTouch = false
    for key, value in pairs(properties or {}) do
        piece[key] = value
    end
    piece.Parent = parent
    return piece
end

-- Adorno chico: sin colisión ni sombra, casi gratis para el celular.
local function detail(parent, name, size, placement, color, material, properties)
    local piece = part(parent, name, size, placement, color, material, properties)
    piece.CanCollide = false
    piece.CastShadow = false
    return piece
end

local function lamp(parent, name, size, position, color, range, brightness, flicker)
    local fixture = detail(parent, name, size, position, color, M.Neon)
    local light = Instance.new("PointLight")
    light.Color = color
    light.Range = range
    light.Brightness = brightness
    light.Shadows = false
    light.Parent = fixture
    if flicker then
        CollectionService:AddTag(fixture, FLICKER_TAG)
    end
    return fixture, light
end

local function surface(host, face, pixelsPerStud)
    local gui = Instance.new("SurfaceGui")
    gui.Name = "Sign"
    gui.Face = face
    gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    gui.PixelsPerStud = pixelsPerStud or 40
    gui.LightInfluence = 0.7
    gui.Parent = host
    return gui
end

local function text(gui, name, value, top, height, properties)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromScale(0.05, top)
    label.Size = UDim2.fromScale(0.9, height)
    label.Font = Enum.Font.SpecialElite
    label.TextScaled = true
    label.TextWrapped = true
    label.TextColor3 = COLORS.SignText
    label.Text = value
    for key, val in pairs(properties or {}) do
        label[key] = val
    end
    label.Parent = gui
    return label
end

-- Lluvia que cae del otro lado del vidrio y gotas que resbalan por él.
local function rainOutside(parent, x, width)
    local emitterPart = detail(parent, "Rain", Vector3.new(width, 0.2, 5), at(x, HEIGHT - 1, HALF_Z + 5), COLORS.Glass, M.Glass, {
        Transparency = 1,
        CanQuery = false,
    })
    local rain = Instance.new("ParticleEmitter")
    rain.Name = "Rain"
    rain.Texture = RAIN_TEXTURE
    rain.EmissionDirection = NORMAL.Bottom
    rain.Shape = Enum.ParticleEmitterShape.Box
    rain.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
    rain.Orientation = Enum.ParticleOrientation.VelocityParallel
    rain.Speed = NumberRange.new(45, 60)
    rain.Lifetime = NumberRange.new(0.3, 0.42)
    rain.Rate = 35
    rain.Size = NumberSequence.new(0.08)
    rain.Squash = NumberSequence.new(3)
    rain.Transparency = NumberSequence.new(0.5)
    rain.Color = ColorSequence.new(Color3.fromRGB(168, 186, 200))
    rain.LightInfluence = 1
    rain.Parent = emitterPart
end

local function dripsOnGlass(glass)
    local drips = Instance.new("ParticleEmitter")
    drips.Name = "Drips"
    drips.Texture = RAIN_TEXTURE
    drips.EmissionDirection = NORMAL.Bottom
    drips.Shape = Enum.ParticleEmitterShape.Box
    drips.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
    drips.Speed = NumberRange.new(0.8, 2.2)
    drips.Acceleration = Vector3.new(0, -0.6, 0)
    drips.Lifetime = NumberRange.new(2.5, 4)
    drips.Rate = 5
    drips.Size = NumberSequence.new(0.12)
    drips.Squash = NumberSequence.new(1)
    drips.Transparency = NumberSequence.new(0.35)
    drips.Color = ColorSequence.new(Color3.fromRGB(190, 205, 215))
    drips.LockedToPart = true
    drips.Parent = glass
end

-- Muro a lo ancho del eje X con aberturas: {centro, ancho} cada una.
local function wallWithOpenings(parent, z, openings, openingHeight, bottom)
    openings = table.clone(openings)
    table.sort(openings, function(a, b)
        return a[1] < b[1]
    end)
    local edges = {-HALF_X - 2}
    for _, opening in ipairs(openings) do
        table.insert(edges, opening[1] - opening[2] / 2)
        table.insert(edges, opening[1] + opening[2] / 2)
    end
    table.insert(edges, HALF_X + 2)

    for index = 1, #edges, 2 do
        local left, right = edges[index], edges[index + 1]
        part(parent, "Wall", Vector3.new(right - left, HEIGHT, 2), at((left + right) / 2, HEIGHT / 2, z), COLORS.Wall, M.Plaster)
    end
    for _, opening in ipairs(openings) do
        local headerHeight = HEIGHT - openingHeight
        part(parent, "WallHeader", Vector3.new(opening[2], headerHeight, 2), at(opening[1], HEIGHT - headerHeight / 2, z), COLORS.Wall, M.Plaster)
        if bottom and bottom > 0 then
            part(parent, "WallSill", Vector3.new(opening[2], bottom, 2), at(opening[1], bottom / 2, z), COLORS.Wood, M.WoodPlanks)
        end
    end
end

local function buildShell(lobby, full)
    part(lobby, "Floor", Vector3.new(HALF_X * 2 + 4, 2, HALF_Z * 2 + 4), at(0, -1, 0), COLORS.Floor, M.Marble)
    part(lobby, "Ceiling", Vector3.new(HALF_X * 2 + 4, 2, HALF_Z * 2 + 4), at(0, HEIGHT + 1, 0), COLORS.Ceiling, M.Plaster)
    detail(lobby, "Carpet", Vector3.new(8, 0.1, 34), at(0, 0.05, 12), Color3.fromRGB(70, 22, 26), M.Carpet)

    for _, side in ipairs({-1, 1}) do
        part(lobby, "Wall", Vector3.new(2, HEIGHT, HALF_Z * 2 + 4), at(side * (HALF_X + 1), HEIGHT / 2, 0), COLORS.Wall, M.Plaster)
        detail(lobby, "Wainscot", Vector3.new(0.4, 4, HALF_Z * 2), at(side * (HALF_X - 0.2), 2, 0), COLORS.Wood, M.WoodPlanks)
    end

    for _, x in ipairs({-18, 18}) do
        for _, z in ipairs({-18, 18}) do
            part(lobby, "Column", Vector3.new(2.4, HEIGHT, 2.4), at(x, HEIGHT / 2, z), Color3.fromRGB(78, 78, 74), M.Concrete)
        end
    end

    -- Fondo: la fila de ascensores, o una pared lisa en la sala de espera de una partida.
    if full then
        local openings = {}
        for _, x in ipairs(ELEVATOR_X) do
            table.insert(openings, {x, DOOR_WIDTH})
        end
        wallWithOpenings(lobby, -HALF_Z - 1, openings, DOOR_HEIGHT, 0)
    else
        part(lobby, "Wall", Vector3.new(HALF_X * 2 + 4, HEIGHT, 2), at(0, HEIGHT / 2, -HALF_Z - 1), COLORS.Wall, M.Plaster)
    end
end

-- Frente: cuatro ventanales y la entrada cerrada con cadena. Afuera llueve.
local function buildFront(lobby)
    local openings = {{0, 10}}
    for _, x in ipairs(WINDOW_X) do
        table.insert(openings, {x, 10})
    end
    wallWithOpenings(lobby, HALF_Z + 1, openings, 12, 0)

    for _, x in ipairs(WINDOW_X) do
        part(lobby, "Sill", Vector3.new(10, 3, 2), at(x, 1.5, HALF_Z + 1), COLORS.Wood, M.WoodPlanks)
        local glass = part(lobby, "Window", Vector3.new(10, 9, 0.3), at(x, 7.5, HALF_Z + 1), COLORS.Glass, M.Glass, {
            Transparency = 0.5,
            CastShadow = false,
        })
        dripsOnGlass(glass)
        detail(lobby, "Mullion", Vector3.new(0.35, 9, 0.6), at(x, 7.5, HALF_Z + 1), COLORS.Iron, M.Metal)
        detail(lobby, "Transom", Vector3.new(10, 0.35, 0.6), at(x, 9.5, HALF_Z + 1), COLORS.Iron, M.Metal)
        rainOutside(lobby, x, 12)
    end

    for _, side in ipairs({-1, 1}) do
        part(lobby, "EntranceDoor", Vector3.new(4.9, 12, 0.3), at(side * 2.5, 6, HALF_Z + 1), COLORS.Glass, M.Glass, {
            Transparency = 0.45,
            CastShadow = false,
        })
        detail(lobby, "Chain", Vector3.new(6, 0.25, 0.25), CFrame.new(at(0, 4.5, HALF_Z + 0.6)) * CFrame.Angles(0, 0, math.rad(side * 12)), COLORS.Iron, M.CorrodedMetal)
    end
    detail(lobby, "DoorFrame", Vector3.new(0.4, 12, 0.6), at(0, 6, HALF_Z + 1), COLORS.Iron, M.Metal)
    detail(lobby, "Padlock", Vector3.new(0.8, 1, 0.4), at(0, 4.4, HALF_Z + 0.4), COLORS.Brass, M.Metal)
    rainOutside(lobby, 0, 12)

    local closed = detail(lobby, "ClosedSign", Vector3.new(3.4, 1.3, 0.1), at(0, 7.6, HALF_Z + 0.5), COLORS.Paper, M.Cardboard)
    text(surface(closed, NORMAL.Front, 60), "Text", "CERRADO", 0.1, 0.8, {TextColor3 = COLORS.Blood})

    -- La calle: asfalto mojado, el edificio de enfrente y un farol de sodio que titila.
    part(lobby, "Street", Vector3.new(HALF_X * 2 + 4, 1, 16), at(0, -0.5, HALF_Z + 10), Color3.fromRGB(26, 28, 30), M.Asphalt, {
        Reflectance = 0.12,
    })
    part(lobby, "BuildingAcross", Vector3.new(HALF_X * 2 + 4, 26, 2), at(0, 13, HALF_Z + 19), Color3.fromRGB(26, 24, 26), M.Brick)
    detail(lobby, "StreetLampPole", Vector3.new(0.5, 13, 0.5), at(-20, 6.5, HALF_Z + 7), COLORS.Iron, M.Metal)
    lamp(lobby, "StreetLamp", Vector3.new(2, 0.6, 1), at(-20, 13, HALF_Z + 7), COLORS.Sodium, 32, 1.2, true)
end

local function buildReception(lobby)
    part(lobby, "Desk", Vector3.new(16, 4, 1), at(0, 2, -6), COLORS.Wood, M.WoodPlanks)
    part(lobby, "DeskTop", Vector3.new(17, 0.4, 3.2), at(0, 4.2, -7.1), Color3.fromRGB(112, 108, 98), M.Marble)
    for _, side in ipairs({-1, 1}) do
        part(lobby, "DeskSide", Vector3.new(1, 4, 3), at(side * 7.5, 2, -7.5), COLORS.Wood, M.WoodPlanks)
    end

    local plate = detail(lobby, "DeskPlate", Vector3.new(8, 1.4, 0.1), at(0, 2.6, -5.45), COLORS.Brass, M.Metal)
    text(surface(plate, NORMAL.Back, 50), "Text", "RECEPCIÓN", 0.1, 0.8, {TextColor3 = COLORS.Ink, Font = Enum.Font.Garamond})

    detail(lobby, "Monitor", Vector3.new(2.2, 1.8, 1.6), at(-4, 5.3, -7.6), Color3.fromRGB(64, 62, 58), M.Metal)
    local screen = detail(lobby, "Screen", Vector3.new(1.8, 1.3, 0.05), at(-4, 5.35, -6.78), Color3.fromRGB(26, 60, 40), M.Glass)
    text(surface(screen, NORMAL.Back, 80), "Text", "SISTEMA LETEO\nSIN CONEXIÓN", 0.15, 0.7, {
        Font = Enum.Font.Code,
        TextColor3 = Color3.fromRGB(110, 220, 140),
    })

    detail(lobby, "Bell", Vector3.new(0.7, 0.7, 0.7), at(3, 4.6, -6.8), COLORS.Brass, M.Metal, {Shape = Enum.PartType.Ball})
    detail(lobby, "Papers", Vector3.new(1.6, 0.12, 1.1), CFrame.new(at(1, 4.46, -7.2)) * CFrame.Angles(0, math.rad(14), 0), COLORS.Paper, M.Cardboard)
    detail(lobby, "Files", Vector3.new(1.2, 0.8, 1.6), at(-1.6, 4.8, -8), Color3.fromRGB(132, 104, 66), M.Cardboard)
    detail(lobby, "LampBase", Vector3.new(0.8, 0.2, 0.8), at(5.5, 4.5, -7.6), COLORS.Iron, M.Metal)
    detail(lobby, "LampStem", Vector3.new(0.15, 1.4, 0.15), at(5.5, 5.2, -7.6), COLORS.Iron, M.Metal)
    lamp(lobby, "DeskLamp", Vector3.new(0.7, 0.4, 0.7), at(5.5, 6, -7.6), COLORS.Warm, 16, 1.1, true)

    part(lobby, "ChairSeat", Vector3.new(2.2, 0.4, 2.2), at(0, 2.2, -10), COLORS.Leather, M.Leather)
    detail(lobby, "ChairBack", Vector3.new(2.2, 2.4, 0.3), at(0, 3.6, -11.1), COLORS.Leather, M.Leather)
    detail(lobby, "ChairPost", Vector3.new(0.3, 2, 0.3), at(0, 1, -10), COLORS.Iron, M.Metal)
end

-- Sala de espera: bancos enfrentados, una mesa con revistas viejas, una planta seca,
-- un dispenser de agua y un reloj parado a las tres.
local function buildWaitingArea(lobby)
    local benches = {{-34, 6, 1}, {-34, 16, 1}, {-22, 6, -1}, {-22, 16, -1}}
    for _, bench in ipairs(benches) do
        local x, z, facing = bench[1], bench[2], bench[3]
        part(lobby, "BenchSeat", Vector3.new(2.2, 0.5, 7), at(x, 1.8, z), COLORS.Leather, M.Leather)
        detail(lobby, "BenchBack", Vector3.new(0.4, 2.2, 7), at(x - facing * 1.2, 3.1, z), COLORS.Leather, M.Leather)
        for _, offset in ipairs({-3, 3}) do
            detail(lobby, "BenchLeg", Vector3.new(2, 1.6, 0.3), at(x, 0.8, z + offset), COLORS.Iron, M.Metal)
        end
    end

    part(lobby, "Table", Vector3.new(3, 0.3, 5), at(-28, 1.6, 11), COLORS.Wood, M.Wood)
    detail(lobby, "TableBase", Vector3.new(1, 1.4, 1), at(-28, 0.7, 11), COLORS.Iron, M.Metal)
    detail(lobby, "Magazine", Vector3.new(1, 0.08, 1.4), CFrame.new(at(-28.3, 1.8, 10)) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(150, 60, 50), M.Cardboard)
    detail(lobby, "Magazine", Vector3.new(1, 0.08, 1.4), CFrame.new(at(-27.6, 1.8, 12.2)) * CFrame.Angles(0, math.rad(-8), 0), Color3.fromRGB(60, 80, 110), M.Cardboard)

    part(lobby, "PlantPot", Vector3.new(2, 2, 2), at(-38, 1, 27), Color3.fromRGB(70, 66, 60), M.Concrete)
    for _, angle in ipairs({-18, 14}) do
        detail(lobby, "DeadStem", Vector3.new(0.2, 3.4, 0.2), CFrame.new(at(-38, 3.6, 27)) * CFrame.Angles(math.rad(angle), 0, math.rad(-angle)), Color3.fromRGB(64, 50, 36), M.Wood)
    end

    part(lobby, "WaterCooler", Vector3.new(1.8, 3.5, 1.8), at(-38, 1.75, -20), Color3.fromRGB(168, 168, 162), M.Metal)
    detail(lobby, "WaterBottle", Vector3.new(1.4, 2, 1.4), at(-38, 4.5, -20), Color3.fromRGB(120, 150, 170), M.Glass, {Transparency = 0.4})

    local clock = detail(lobby, "Clock", Vector3.new(0.2, 2.2, 2.2), at(-HALF_X + 0.1, 11, 11), COLORS.Wood, M.Wood)
    text(surface(clock, NORMAL.Right, 60), "Text", "3:00", 0.2, 0.6, {Font = Enum.Font.Antique})
end

local function poster(lobby, position, face, size, title, body, style)
    local sheet = detail(lobby, "Poster", size, position, style and style.Paper or COLORS.Paper, M.Cardboard, {
        Transparency = style and style.Transparency or 0,
    })
    local gui = surface(sheet, face, 40)
    local color = style and style.Color or COLORS.Ink
    local font = style and style.Font or Enum.Font.SpecialElite
    text(gui, "Title", title, 0.06, 0.4, {TextColor3 = color, Font = font})
    if body then
        text(gui, "Body", body, 0.52, 0.4, {TextColor3 = color, Font = Enum.Font.Garamond})
    end
    return sheet
end

local function buildPosters(lobby, full)
    local west, east = -HALF_X + 0.05, HALF_X - 0.05
    poster(lobby, at(west, 8, -12), NORMAL.Right, Vector3.new(0.1, 5, 3.6), "¿DUELO?\nHAY CURA.", "Fundación Leteo\nTerapia de olvido selectivo")
    poster(lobby, at(west, 8, 22), NORMAL.Right, Vector3.new(0.1, 5, 3.6), "SE RUEGA\nSILENCIO", "Los pacientes descansan.")
    poster(lobby, at(east, 8, -12), NORMAL.Left, Vector3.new(0.1, 5, 3.6), "PROYECTO\nNOCTURNA", "Se buscan voluntarios.\nSe paga bien.")
    poster(lobby, at(west, 5.5, 27), NORMAL.Right, Vector3.new(0.1, 3, 4), "contá hasta cinco", nil, {
        Transparency = 1,
        Color = COLORS.Blood,
        Font = Enum.Font.PermanentMarker,
    })

    local logo = detail(lobby, "Logo", Vector3.new(36, 2.6, 0.2), at(0, 14.5, -HALF_Z + 0.1), COLORS.Iron, M.Metal)
    local gui = surface(logo, NORMAL.Back, 20)
    if full then
        text(gui, "Title", "FUNDACIÓN LETEO", 0.05, 0.6, {TextColor3 = COLORS.Accent, Font = Enum.Font.Garamond})
        text(gui, "Body", "olvidar también es sanar", 0.62, 0.34, {Font = Enum.Font.Garamond})
        poster(lobby, at(0, 6, -HALF_Z + 0.05), NORMAL.Back, Vector3.new(3.6, 4.4, 0.1), "AVISO", "No use los ascensores\nsin acompañante.")
    else
        text(gui, "Title", "SALA DE ESPERA", 0.05, 0.6, {TextColor3 = COLORS.Accent, Font = Enum.Font.Garamond})
        text(gui, "Body", "el ascensor ya bajó: esperá a tu grupo", 0.62, 0.34, {Font = Enum.Font.Garamond})
    end
end

-- Tubos fluorescentes: dos titilan y uno está quemado.
local function buildLights(lobby)
    local index = 0
    for _, z in ipairs({-16, 8}) do
        for _, x in ipairs({-24, 0, 24}) do
            index += 1
            local position = at(x, HEIGHT - 0.2, z)
            if index == 4 then
                detail(lobby, "DeadTube", Vector3.new(8, 0.3, 1.2), position, Color3.fromRGB(90, 96, 92), M.Glass)
            else
                lamp(lobby, "Tube", Vector3.new(8, 0.3, 1.2), position, COLORS.Fluorescent, 28, 0.8, index == 2 or index == 6)
            end
        end
    end
end

local function buildElevator(lobby, index, x)
    local cabinZ = -HALF_Z - 2 - CABIN_DEPTH / 2
    local doorZ = -HALF_Z - 1.6
    local frontZ = -HALF_Z + 0.2
    local cabinHeight = DOOR_HEIGHT + 1

    part(lobby, "ElevatorFloor", Vector3.new(10, 1, CABIN_DEPTH), at(x, -0.5, cabinZ), Color3.fromRGB(70, 70, 68), M.DiamondPlate)
    part(lobby, "ElevatorBack", Vector3.new(12, cabinHeight, 1), at(x, cabinHeight / 2, cabinZ - CABIN_DEPTH / 2 - 0.5), COLORS.Wood, M.WoodPlanks)
    for _, side in ipairs({-1, 1}) do
        part(lobby, "ElevatorSide", Vector3.new(1, cabinHeight, CABIN_DEPTH), at(x + side * 5.5, cabinHeight / 2, cabinZ), Color3.fromRGB(84, 80, 74), M.Metal)
    end
    part(lobby, "ElevatorCeiling", Vector3.new(12, 1, CABIN_DEPTH + 1), at(x, cabinHeight + 0.5, cabinZ - 0.5), COLORS.Ceiling, M.Metal)
    local _, light = lamp(lobby, "ElevatorLight", Vector3.new(3, 0.2, 3), at(x, cabinHeight - 0.1, cabinZ), Color3.fromRGB(220, 210, 170), 14, 0.9, index % 2 == 0)
    detail(lobby, "Handrail", Vector3.new(8, 0.25, 0.25), at(x, 3.4, cabinZ - CABIN_DEPTH / 2 + 0.4), COLORS.Brass, M.Metal)
    detail(lobby, "ButtonPanel", Vector3.new(0.15, 2.4, 1), at(x + 4.9, 4.5, -HALF_Z - 2.6), COLORS.Iron, M.Metal)
    detail(lobby, "Button", Vector3.new(0.1, 0.3, 0.3), at(x + 4.82, 5, -HALF_Z - 2.6), Color3.fromRGB(200, 60, 50), M.Neon)

    local doors = {}
    for _, side in ipairs({-1, 1}) do
        local closed = CFrame.new(at(x + side * DOOR_WIDTH / 4, DOOR_HEIGHT / 2, doorZ))
        local open = CFrame.new(at(x + side * (DOOR_WIDTH / 4 + DOOR_WIDTH / 2), DOOR_HEIGHT / 2, doorZ))
        local door = part(lobby, "ElevatorDoor", Vector3.new(DOOR_WIDTH / 2, DOOR_HEIGHT, 0.4), open, COLORS.Steel, M.Metal)
        table.insert(doors, {Part = door, Open = open, Closed = closed})
        detail(lobby, "DoorTrim", Vector3.new(0.6, DOOR_HEIGHT, 0.5), at(x + side * (DOOR_WIDTH / 2 + 0.3), DOOR_HEIGHT / 2, frontZ), COLORS.Brass, M.Metal)
    end
    detail(lobby, "DoorTrim", Vector3.new(DOOR_WIDTH + 1.2, 0.6, 0.5), at(x, DOOR_HEIGHT + 0.3, frontZ), COLORS.Brass, M.Metal)

    local sign = detail(lobby, "ElevatorSign", Vector3.new(DOOR_WIDTH, 2.4, 0.3), at(x, DOOR_HEIGHT + 1.9, -HALF_Z + 0.15), COLORS.Iron, M.Metal)
    sign:SetAttribute("Elevator", index)
    local gui = surface(sign, NORMAL.Back, 50)
    gui.LightInfluence = 0
    gui.Brightness = 1.2
    local labels = {
        Title = text(gui, "Title", "ASCENSOR " .. index, 0.04, 0.3, {TextColor3 = COLORS.Accent}),
        Status = text(gui, "Status", "LIBRE", 0.36, 0.28, {Font = Enum.Font.Code}),
        Members = text(gui, "Members", "", 0.66, 0.3, {Font = Enum.Font.Code, TextColor3 = Color3.fromRGB(160, 166, 176)}),
    }

    elevators[index] = {
        Index = index,
        Min = at(x - 4.6, -1, cabinZ - CABIN_DEPTH / 2 + 0.4),
        Max = at(x + 4.6, 9, cabinZ + CABIN_DEPTH / 2 - 0.4),
        Center = at(x, 3.5, cabinZ),
        Exit = CFrame.lookAt(at(x, 3.5, -HALF_Z + 5), at(x, 3.5, 0)),
        Doors = doors,
        DoorsOpen = true,
        Labels = labels,
        Light = light,
    }
end

local function buildDonationCorner(lobby)
    local plaque = detail(lobby, "DonorPlaque", Vector3.new(0.2, 2.6, 18), at(HALF_X - 0.15, 12.5, 11), Color3.fromRGB(70, 56, 34), M.Metal)
    local gui = surface(plaque, NORMAL.Left, 30)
    text(gui, "Title", "MECENAS DE LA FUNDACIÓN", 0.05, 0.55, {TextColor3 = COLORS.Accent, Font = Enum.Font.Garamond})
    text(gui, "Body", "gracias por mantener las luces encendidas", 0.6, 0.34, {Font = Enum.Font.Garamond})

    statueFolder = Instance.new("Folder")
    statueFolder.Name = "Statues"
    statueFolder.Parent = lobby

    -- El primero en el medio y más alto; segundo y tercero a los costados.
    for _, spec in ipairs({{Rank = 2, Z = 5, Height = 2}, {Rank = 1, Z = 11, Height = 3}, {Rank = 3, Z = 17, Height = 1.2}}) do
        part(lobby, "Podium", Vector3.new(5, spec.Height, 4.6), at(34, spec.Height / 2, spec.Z), Color3.fromRGB(34, 32, 36), M.Marble)
        local plate = detail(lobby, "PodiumPlate", Vector3.new(0.3, 1.4, 4.2), at(30.2, 0.9, spec.Z), COLORS.Brass, M.Metal)
        local plateGui = surface(plate, NORMAL.Left, 50)
        local top = at(34, spec.Height + 3, spec.Z)
        podiums[spec.Rank] = {
            Rank = spec.Rank,
            CFrame = CFrame.lookAt(top, top + Vector3.new(-1, 0, 0)),
            UserId = nil,
            Labels = {
                Name = text(plateGui, "Name", "Puesto libre", 0.05, 0.5, {TextColor3 = COLORS.Ink, Font = Enum.Font.Garamond}),
                Total = text(plateGui, "Total", "#" .. spec.Rank, 0.56, 0.38, {TextColor3 = COLORS.Ink}),
            },
        }
    end

    local fixture = detail(lobby, "PodiumSpot", Vector3.new(2, 0.3, 2), at(33, HEIGHT - 0.2, 11), COLORS.Iron, M.Metal)
    local spot = Instance.new("SpotLight")
    spot.Face = NORMAL.Bottom
    spot.Angle = 80
    spot.Range = 24
    spot.Brightness = 2.2
    spot.Color = Color3.fromRGB(255, 214, 160)
    spot.Shadows = false
    spot.Parent = fixture

    for _, z in ipairs({2, 20}) do
        part(lobby, "RopePost", Vector3.new(0.4, 3, 0.4), at(29, 1.5, z), COLORS.Brass, M.Metal)
    end
    detail(lobby, "Rope", Vector3.new(0.2, 0.2, 18), at(29, 2.7, 11), Color3.fromRGB(110, 20, 26), M.Fabric)

    -- La urna: se toca para abrir el panel de donaciones.
    local pedestal = part(lobby, "DonationStand", Vector3.new(2.6, 3.4, 2.6), at(25, 1.7, 11), COLORS.Wood, M.WoodPlanks)
    detail(lobby, "DonationUrn", Vector3.new(2, 1.8, 2), at(25, 4.3, 11), Color3.fromRGB(180, 200, 210), M.Glass, {Transparency = 0.5})
    detail(lobby, "DonationCoins", Vector3.new(1.4, 0.4, 1.4), at(25, 3.6, 11), Color3.fromRGB(200, 160, 60), M.Metal)
    detail(lobby, "DonationLid", Vector3.new(2.2, 0.2, 2.2), at(25, 5.3, 11), COLORS.Brass, M.Metal)
    local card = surface(pedestal, NORMAL.Left, 40)
    text(card, "Title", "DONACIONES", 0.08, 0.2, {TextColor3 = COLORS.Accent})
    text(card, "Body", "acercate para colaborar", 0.3, 0.16, {Font = Enum.Font.Garamond})

    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "DonationPrompt"
    prompt.ActionText = "Donar"
    prompt.ObjectText = "Urna de la Fundación"
    prompt.HoldDuration = 0
    prompt.MaxActivationDistance = LobbyConfig.Donations.PromptDistance
    prompt.RequiresLineOfSight = false
    prompt.Parent = pedestal
    donationPrompt = prompt
end

function LobbyBuilder.Build()
    local existing = workspace:FindFirstChild("NOCTURNA_LOBBY")
    if existing then
        return existing
    end

    center = origin()
    table.clear(elevators)
    table.clear(podiums)
    donationPrompt = nil

    -- En el servidor de una partida no hay ascensores ni donaciones: sólo la espera.
    local full = not ServerMode.IsMatchServer()
    local lobby = Instance.new("Model")
    lobby.Name = "NOCTURNA_LOBBY"

    buildShell(lobby, full)
    buildFront(lobby)
    buildReception(lobby)
    buildWaitingArea(lobby)
    buildPosters(lobby, full)
    buildLights(lobby)
    if full then
        for index, x in ipairs(ELEVATOR_X) do
            buildElevator(lobby, index, x)
        end
        buildDonationCorner(lobby)
    end

    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "PlayerSpawn"
    spawn.Size = Vector3.new(14, 1, 8)
    spawn.Position = at(0, 0.5, 22)
    spawn.Anchored = true
    spawn.Neutral = true
    spawn.Transparency = 1
    spawn.CanCollide = false
    spawn.Duration = 0
    spawn.Parent = lobby

    lobby.Parent = workspace
    CollectionService:AddTag(lobby, "NocturnaLobby")
    return lobby
end

-- Se aparece junto a la entrada, mirando hacia el mostrador y los ascensores.
function LobbyBuilder.SpawnCFrame(index)
    local base = origin()
    local spread = ((index or 1) - 2.5) * 4
    return CFrame.lookAt(base + Vector3.new(spread, 3.5, 22), base + Vector3.new(spread, 3.5, 0))
end

function LobbyBuilder.Elevators()
    return elevators
end

function LobbyBuilder.ElevatorAt(position)
    if typeof(position) ~= "Vector3" then
        return nil
    end
    for _, elevator in ipairs(elevators) do
        local minimum, maximum = elevator.Min, elevator.Max
        if position.X >= minimum.X and position.X <= maximum.X
            and position.Y >= minimum.Y and position.Y <= maximum.Y
            and position.Z >= minimum.Z and position.Z <= maximum.Z then
            return elevator
        end
    end
    return nil
end

function LobbyBuilder.SetDoors(elevator, open)
    if elevator.DoorsOpen == open then
        return
    end
    elevator.DoorsOpen = open
    local info = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
    for _, door in ipairs(elevator.Doors) do
        TweenService:Create(door.Part, info, {CFrame = open and door.Open or door.Closed}):Play()
    end
end

function LobbyBuilder.SetSign(elevator, status, members, color)
    local labels = elevator.Labels
    labels.Status.Text = status
    labels.Status.TextColor3 = color or COLORS.SignText
    labels.Members.Text = members or ""
end

function LobbyBuilder.Podiums()
    return podiums
end

function LobbyBuilder.StatueFolder()
    return statueFolder
end

function LobbyBuilder.DonationPrompt()
    return donationPrompt
end

return LobbyBuilder
