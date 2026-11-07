-- Muebles, terminaciones y detalles de las salas: escritorios con papeles, camas de
-- hospital, estanterías con cajas, mesadas de laboratorio, cañerías en el techo,
-- zócalos, marcos de puertas, manchas y cosas rotas.
--
-- Convención de los muebles: `base` es el centro de la huella en el piso, -Z mira
-- hacia la sala y +Z hacia la pared. Width es el ancho a lo largo de la pared y
-- Depth lo que sobresale hacia la sala. Todo es anclado; sólo colisiona lo grande.
local CollectionService = game:GetService("CollectionService")

local PropKit = require(script.Parent.PropKit)

local RoomDecor = {}

local Part = PropKit.Part
local M = PropKit.Material
local Shade = PropKit.Shade
local SOLID = PropKit.SOLID
local BALL = PropKit.BALL

local PAPER = Color3.fromRGB(214, 206, 182)
local CARDBOARD = Color3.fromRGB(150, 118, 80)
local BLACK = Color3.fromRGB(26, 26, 28)

local DEFAULT_PALETTE = {
    Trim = Color3.fromRGB(60, 58, 56),
    WallLower = Color3.fromRGB(90, 90, 86),
    Grime = Color3.fromRGB(30, 28, 24),
    Wood = Color3.fromRGB(104, 80, 56),
    Metal = Color3.fromRGB(120, 122, 122),
    Paint = Color3.fromRGB(90, 96, 90),
    Accent = Color3.fromRGB(150, 110, 50),
    Fabric = Color3.fromRGB(80, 78, 74),
    Pipe = Color3.fromRGB(100, 80, 64),
}

function RoomDecor.Palette(theme)
    local palette = table.clone(DEFAULT_PALETTE)
    for key, value in pairs(theme.Palette or {}) do
        palette[key] = value
    end
    return palette
end

local function at(x, y, z)
    return CFrame.new(x, y, z)
end

local function piece(parent, base, name, size, offset, color, material, options)
    return Part(parent, name, size, base * offset, color, material, options)
end

local function solid(parent, base, name, size, offset, color, material)
    return Part(parent, name, size, base * offset, color, material, SOLID)
end

local function column(parent, base, name, height, diameter, offset, color, material, isSolid)
    return PropKit.Column(parent, name, height, diameter, base * offset, color, material, isSolid)
end

local function ball(parent, base, name, size, offset, color, material)
    return Part(parent, name, size, base * offset, color, material, BALL)
end

local function turn(rng, amount)
    return CFrame.Angles(0, (rng:Float() * 2 - 1) * amount, 0)
end

-- Las lucecitas de utilería se apagan en bajo consumo (QualityController).
local function decorLight(host, color, brightness, range)
    local light = PropKit.Light(host, "PointLight", color, brightness, range, false)
    CollectionService:AddTag(host, "NocturnaDecorLight")
    return light
end

-- Silla de oficina; a veces volcada en el piso.
local function chair(parent, base, palette, rng)
    local frame = base * turn(rng, 0.5)
    if rng:Chance(0.3) then
        frame = frame * at(0, 0.9, 0) * CFrame.Angles(math.rad(-82), 0, 0) * at(0, -0.9, 0)
    end
    piece(parent, frame, "Seat", Vector3.new(1.7, 0.3, 1.6), at(0, 1.75, 0), palette.Fabric, M("Fabric"))
    piece(parent, frame, "ChairBack", Vector3.new(1.7, 1.7, 0.2), at(0, 2.75, -0.75), palette.Fabric, M("Fabric"))
    column(parent, frame, "ChairPost", 1.4, 0.25, at(0, 0.95, 0), BLACK, M("Metal"))
    piece(parent, frame, "ChairBase", Vector3.new(1.9, 0.15, 1.9), at(0, 0.1, 0) * CFrame.Angles(0, 0.6, 0), BLACK, M("Metal"))
end

local function cardboardBox(parent, base, rng, y, x, z)
    local size = Vector3.new(1.1 + rng:Float() * 0.7, 0.8 + rng:Float() * 0.6, 1.1 + rng:Float() * 0.5)
    piece(parent, base, "Box", size, at(x, y + size.Y / 2, z) * turn(rng, 0.25), PropKit.Vary(CARDBOARD, rng, 0.12), M("Cardboard"))
end

-- Muebles grandes, contra la pared --------------------------------------------------

local FURNITURE = {}

FURNITURE.Workbench = {Width = 7, Depth = 2.6, Build = function(p, b, pal, rng)
    solid(p, b, "BenchTop", Vector3.new(7, 0.3, 2.6), at(0, 3, 0), pal.Wood, M("WoodPlanks"))
    for _, side in ipairs({-1, 1}) do
        solid(p, b, "BenchLeg", Vector3.new(0.3, 2.85, 2.3), at(side * 3.2, 1.43, 0), Shade(pal.Wood, 0.8), M("WoodPlanks"))
    end
    piece(p, b, "BenchShelf", Vector3.new(6.2, 0.2, 2.1), at(0, 0.8, 0.05), Shade(pal.Wood, 0.75), M("WoodPlanks"))
    piece(p, b, "Vise", Vector3.new(0.7, 0.5, 0.8), at(2.7, 3.4, -0.9), pal.Metal, M("Metal"))
    piece(p, b, "Toolbox", Vector3.new(1.4, 0.7, 0.7), at(-1.8, 3.5, 0.3) * turn(rng, 0.3), Color3.fromRGB(150, 40, 34), M("Metal"))
    piece(p, b, "Pegboard", Vector3.new(6.4, 3, 0.15), at(0, 5.3, 1.22), Shade(pal.Wood, 1.25), M("Wood"))
    piece(p, b, "Wrench", Vector3.new(0.18, 1.3, 0.08), at(-1.5, 5.4, 1.1) * CFrame.Angles(0, 0, 0.3), pal.Metal, M("Metal"))
    piece(p, b, "Saw", Vector3.new(1.6, 0.6, 0.05), at(1.4, 5.6, 1.12), pal.Metal, M("Metal"))
end}

FURNITURE.ElectricalPanel = {Width = 3, Depth = 1.2, Build = function(p, b, pal)
    solid(p, b, "Cabinet", Vector3.new(2.6, 3.6, 0.8), at(0, 3.6, 0.2), pal.Paint, M("Metal"))
    piece(p, b, "CabinetDoor", Vector3.new(2.5, 3.5, 0.05), at(0, 3.6, -0.22), Shade(pal.Paint, 0.9), M("Metal"))
    piece(p, b, "Hazard", Vector3.new(0.6, 0.5, 0.02), at(0, 4.6, -0.26), Color3.fromRGB(200, 165, 40), M("SmoothPlastic"))
    for _, x in ipairs({-0.7, 0.7}) do
        column(p, b, "Conduit", 7.6, 0.25, at(x, 9.2, 0.3), pal.Metal, M("Metal"))
    end
end}

FURNITURE.BarrelGroup = {Width = 5.5, Depth = 3, Build = function(p, b, pal, rng)
    local colors = {Color3.fromRGB(46, 70, 110), pal.Pipe, Color3.fromRGB(150, 118, 40)}
    column(p, b, "Barrel", 3.1, 2.2, at(-1.4, 1.55, 0.2), rng:Pick(colors), M("CorrodedMetal"), true)
    column(p, b, "Barrel", 3.1, 2.2, at(1.1, 1.55, 0.3), rng:Pick(colors), M("CorrodedMetal"), true)
    column(p, b, "Canister", 1.4, 1, at(2.2, 0.7, -0.9), Color3.fromRGB(160, 40, 34), M("Metal"))
end}

FURNITURE.CrateStack = {Width = 6, Depth = 4, Build = function(p, b, pal, rng)
    solid(p, b, "Pallet", Vector3.new(5.6, 0.45, 3.6), at(0, 0.225, 0), Shade(pal.Wood, 0.85), M("WoodPlanks"))
    solid(p, b, "Crate", Vector3.new(2.6, 2.6, 2.6), at(-1.4, 1.75, 0.3) * turn(rng, 0.1), pal.Wood, M("WoodPlanks"))
    solid(p, b, "Crate", Vector3.new(2.6, 2.6, 2.6), at(1.4, 1.75, 0.2) * turn(rng, 0.15), Shade(pal.Wood, 1.1), M("WoodPlanks"))
    solid(p, b, "Crate", Vector3.new(2.2, 2.2, 2.2), at(-0.5, 4.15, 0.4) * turn(rng, 0.5), Shade(pal.Wood, 0.92), M("WoodPlanks"))
end}

FURNITURE.Shelf = {Width = 6, Depth = 2, Build = function(p, b, pal, rng)
    for _, side in ipairs({-1, 1}) do
        solid(p, b, "Upright", Vector3.new(0.2, 7.2, 2), at(side * 2.9, 3.6, 0), pal.Metal, M("Metal"))
    end
    local levels = {0.5, 2.3, 4.1, 5.9}
    for _, y in ipairs(levels) do
        piece(p, b, "Board", Vector3.new(5.8, 0.12, 1.9), at(0, y, 0), Shade(pal.Metal, 0.9), M("Metal"))
    end
    for _ = 1, 4 do
        if rng:Chance(0.85) then
            cardboardBox(p, b, rng, rng:Pick(levels) + 0.06, rng:Float() * 3.6 - 1.8, 0)
        end
    end
end}

FURNITURE.Bookcase = {Width = 6, Depth = 1.8, Build = function(p, b, pal, rng)
    solid(p, b, "Back", Vector3.new(6, 8, 0.15), at(0, 4, 0.82), Shade(pal.Wood, 0.8), M("Wood"))
    for _, side in ipairs({-1, 1}) do
        solid(p, b, "Side", Vector3.new(0.18, 8, 1.8), at(side * 2.91, 4, 0), pal.Wood, M("Wood"))
    end
    local binders = {pal.Accent, Color3.fromRGB(120, 40, 40), Color3.fromRGB(40, 60, 90), Color3.fromRGB(150, 140, 110)}
    for _, y in ipairs({0.15, 2.1, 4.1, 6.1}) do
        piece(p, b, "Board", Vector3.new(5.7, 0.14, 1.7), at(0, y, 0), pal.Wood, M("Wood"))
        if rng:Chance(0.85) then
            local width = 3 + rng:Float() * 2.4
            local x = (5.6 - width) / 2 * (rng:Float() * 2 - 1)
            piece(p, b, "Binders", Vector3.new(width, 1.5, 1.2), at(x, y + 0.82, 0.1), rng:Pick(binders), M("Cardboard"))
        end
    end
end}

FURNITURE.FilingCabinet = {Width = 2, Depth = 2.2, Build = function(p, b, pal, rng)
    solid(p, b, "Cabinet", Vector3.new(1.8, 4.4, 2), at(0, 2.2, 0.1), pal.Paint, M("Metal"))
    local open = rng:Int(0, 4)
    for index, y in ipairs({0.85, 2.25, 3.65}) do
        if index == open then
            piece(p, b, "OpenDrawer", Vector3.new(1.6, 1.15, 1.4), at(0, y, -1.45), Shade(pal.Paint, 1.1), M("Metal"))
            piece(p, b, "Files", Vector3.new(1.3, 0.3, 1.2), at(0, y + 0.55, -1.45), PAPER, M("Cardboard"))
        else
            piece(p, b, "Drawer", Vector3.new(1.66, 1.2, 0.06), at(0, y, -0.92), Shade(pal.Paint, 1.1), M("Metal"))
        end
    end
    piece(p, b, "Folders", Vector3.new(1.2, 0.25, 1.4), at(0, 4.53, 0.1) * turn(rng, 0.4), Color3.fromRGB(190, 160, 100), M("Cardboard"))
end}

FURNITURE.Desk = {Width = 5.6, Depth = 4.6, Build = function(p, b, pal, rng)
    solid(p, b, "DeskTop", Vector3.new(5.2, 0.2, 2.6), at(0, 2.8, 1), pal.Wood, M("Wood"))
    for _, side in ipairs({-1, 1}) do
        solid(p, b, "DeskLeg", Vector3.new(0.2, 2.7, 2.4), at(side * 2.45, 1.35, 1), Shade(pal.Wood, 0.85), M("Wood"))
    end
    piece(p, b, "Monitor", Vector3.new(1.6, 1.3, 1.3), at(-1.2, 3.55, 1.4), Color3.fromRGB(190, 184, 166), M("Plastic"))
    piece(p, b, "Papers", Vector3.new(1.1, 0.04, 1.4), at(1, 2.92, 0.8) * turn(rng, 0.5), PAPER, M("SmoothPlastic"))
    column(p, b, "LampBase", 0.15, 0.6, at(2.1, 2.98, 1.7), BLACK, M("Metal"))
    piece(p, b, "LampArm", Vector3.new(0.12, 1.3, 0.12), at(2.1, 3.6, 1.6) * CFrame.Angles(-0.4, 0, 0), BLACK, M("Metal"))
    chair(p, b * at(0.3, 0, -1.2), pal, rng)
end}

FURNITURE.LabTable = {Width = 7, Depth = 3, Build = function(p, b, pal, rng)
    solid(p, b, "LabBase", Vector3.new(7, 2.85, 2.8), at(0, 1.425, 0.1), pal.Paint, M("Metal"))
    solid(p, b, "LabTop", Vector3.new(7.2, 0.15, 3), at(0, 2.93, 0), Color3.fromRGB(26, 26, 28), M("Slate"))
    for _ = 1, 3 do
        local height = 0.8 + rng:Float() * 0.5
        local flask = column(p, b, "Flask", height, 0.45, at(rng:Float() * 3.8 - 2.8, 3 + height / 2, rng:Float() * 1.2 - 0.6), Color3.fromRGB(200, 220, 215), M("Glass"))
        flask.Transparency = 0.5
    end
    piece(p, b, "Microscope", Vector3.new(0.7, 1.2, 0.6), at(2.4, 3.6, 0.2), Color3.fromRGB(40, 40, 44), M("Metal"))
    piece(p, b, "WallShelf", Vector3.new(7, 0.15, 1.1), at(0, 5.4, 0.95), pal.Metal, M("Metal"))
    for _, x in ipairs({-2, 1.5}) do
        local bottle = column(p, b, "Bottle", 0.9, 0.55, at(x, 5.93, 0.95), Color3.fromRGB(150, 90, 40), M("Glass"))
        bottle.Transparency = 0.3
    end
end}

FURNITURE.HospitalBed = {Width = 3.6, Depth = 7.4, Build = function(p, b, pal, rng)
    solid(p, b, "BedFrame", Vector3.new(3.4, 0.25, 7), at(0, 1.6, 0), pal.Metal, M("Metal"))
    for _, z in ipairs({-3.2, 3.2}) do
        piece(p, b, "BedLegs", Vector3.new(3.2, 1.5, 0.2), at(0, 0.75, z), pal.Metal, M("Metal"))
    end
    solid(p, b, "Mattress", Vector3.new(3.2, 0.5, 6.8), at(0, 1.98, 0), Color3.fromRGB(190, 198, 200), M("Fabric"))
    piece(p, b, "Pillow", Vector3.new(2.4, 0.35, 1.1), at(0, 2.4, 2.8), Color3.fromRGB(214, 220, 222), M("Fabric"))
    piece(p, b, "Sheet", Vector3.new(3.3, 0.12, 4.2), at(0, 2.28, -1) * turn(rng, 0.12), pal.Fabric, M("Fabric"))
    piece(p, b, "Rail", Vector3.new(0.1, 0.6, 3.4), at(1.72, 2.6, -0.5), pal.Metal, M("Metal"))
    solid(p, b, "Headboard", Vector3.new(3.4, 2.6, 0.2), at(0, 1.9, 3.6), pal.Metal, M("Metal"))
    column(p, b, "IVPole", 6, 0.12, at(2.4, 3, 2.6), pal.Metal, M("Metal"))
    local bag = piece(p, b, "IVBag", Vector3.new(0.6, 0.9, 0.15), at(2.4, 5.9, 2.6), Color3.fromRGB(220, 214, 170), M("Glass"))
    bag.Transparency = 0.3
    if rng:Chance(0.5) then
        piece(p, b, "Stain", Vector3.new(1.6, 0.03, 1.2), at(rng:Float() - 0.5, 2.35, rng:Float() * 2 - 1), Color3.fromRGB(96, 26, 26), M("SmoothPlastic"))
    end
end}

FURNITURE.Wheelchair = {Width = 2.4, Depth = 3, Build = function(p, b, pal, rng)
    local frame = b * turn(rng, 0.6)
    local seat = Color3.fromRGB(32, 32, 34)
    piece(p, frame, "Seat", Vector3.new(1.8, 0.15, 1.6), at(0, 1.9, 0), seat, M("Fabric"))
    piece(p, frame, "SeatBack", Vector3.new(1.8, 1.7, 0.15), at(0, 2.85, 0.8), seat, M("Fabric"))
    for _, side in ipairs({-1, 1}) do
        PropKit.Cylinder(p, "Wheel", 0.15, 2.4, frame * at(side * 1.02, 1.2, 0.2), pal.Metal, M("Metal"))
    end
    piece(p, frame, "Footrest", Vector3.new(1.4, 0.1, 0.6), at(0, 0.55, -1.1), pal.Metal, M("Metal"))
end}

FURNITURE.ServerRack = {Width = 3.2, Depth = 2.4, Build = function(p, b)
    solid(p, b, "Rack", Vector3.new(2.8, 7, 2.2), at(0, 3.5, 0), Color3.fromRGB(30, 32, 36), M("Metal"))
    piece(p, b, "Mesh", Vector3.new(2.6, 6.6, 0.05), at(0, 3.5, -1.12), Color3.fromRGB(54, 58, 64), M("DiamondPlate"))
    piece(p, b, "Status", Vector3.new(0.15, 0.15, 0.04), at(-0.9, 5.6, -1.16), Color3.fromRGB(70, 200, 110), M("Neon"))
    piece(p, b, "Status", Vector3.new(0.15, 0.15, 0.04), at(-0.9, 4.4, -1.16), Color3.fromRGB(220, 150, 50), M("Neon"))
end}

FURNITURE.Sofa = {Width = 7, Depth = 3, Build = function(p, b, pal, rng)
    local fabric = pal.Fabric
    solid(p, b, "SofaBase", Vector3.new(7, 1.4, 3), at(0, 0.9, 0), fabric, M("Fabric"))
    solid(p, b, "SofaBack", Vector3.new(7, 1.9, 0.7), at(0, 2.4, 1.15), Shade(fabric, 0.92), M("Fabric"))
    for _, side in ipairs({-1, 1}) do
        solid(p, b, "SofaArm", Vector3.new(0.7, 1, 3), at(side * 3.15, 2.1, 0), Shade(fabric, 0.9), M("Fabric"))
    end
    piece(p, b, "Cushion", Vector3.new(2.8, 0.45, 2.1), at(-1.4, 1.83, -0.25) * turn(rng, 0.08), Shade(fabric, 1.1), M("Fabric"))
    -- Un almohadón tirado en el piso, como si alguien hubiera salido corriendo.
    local fallen = rng:Chance(0.5)
    local offset = fallen and at(1.6, 0.25, -2.4) * turn(rng, 0.8) or at(1.4, 1.83, -0.25)
    piece(p, b, "Cushion", Vector3.new(2.8, 0.45, 2.1), offset, Shade(fabric, 1.1), M("Fabric"))
end}

FURNITURE.KitchenCounter = {Width = 8, Depth = 2.4, Build = function(p, b, pal)
    solid(p, b, "Cabinets", Vector3.new(8, 3, 2.2), at(0, 1.5, 0.1), pal.Paint, M("Wood"))
    solid(p, b, "Counter", Vector3.new(8.2, 0.2, 2.4), at(0, 3.1, 0), Color3.fromRGB(60, 58, 56), M("Granite"))
    local sink = piece(p, b, "Sink", Vector3.new(1.8, 0.06, 1.4), at(1.5, 3.22, 0), Color3.fromRGB(130, 132, 134), M("Metal"))
    sink.Reflectance = 0.2
    piece(p, b, "Faucet", Vector3.new(0.15, 0.9, 0.15), at(1.5, 3.65, 0.7), pal.Metal, M("Metal"))
    piece(p, b, "UpperCabinets", Vector3.new(8, 2.4, 1.2), at(0, 6.4, 0.6), Shade(pal.Paint, 0.95), M("Wood"))
    piece(p, b, "Dishes", Vector3.new(1.2, 0.5, 0.9), at(-2.4, 3.45, 0), Color3.fromRGB(220, 214, 200), M("Plastic"))
end}

FURNITURE.ChildBed = {Width = 3.4, Depth = 6.4, Build = function(p, b, pal)
    solid(p, b, "BedFrame", Vector3.new(3.2, 0.9, 6.2), at(0, 0.65, 0), pal.Wood, M("Wood"))
    piece(p, b, "Mattress", Vector3.new(3, 0.5, 6), at(0, 1.35, 0), Color3.fromRGB(200, 190, 176), M("Fabric"))
    piece(p, b, "Pillow", Vector3.new(2, 0.3, 0.9), at(0, 1.75, 2.4), Color3.fromRGB(230, 224, 214), M("Fabric"))
    piece(p, b, "Blanket", Vector3.new(3.1, 0.12, 3.6), at(0, 1.66, -1), Color3.fromRGB(150, 170, 200), M("Fabric"))
    solid(p, b, "Headboard", Vector3.new(3.3, 2.6, 0.2), at(0, 1.3, 3.1), pal.Wood, M("Wood"))
    ball(p, b, "Teddy", Vector3.new(0.9, 0.9, 0.9), at(0.6, 2.05, 1.9), Color3.fromRGB(130, 90, 60), M("Fabric"))
    ball(p, b, "TeddyHead", Vector3.new(0.6, 0.6, 0.6), at(0.6, 2.7, 1.95), Color3.fromRGB(130, 90, 60), M("Fabric"))
end}

FURNITURE.Dresser = {Width = 4.4, Depth = 2, Build = function(p, b, pal, rng)
    solid(p, b, "Body", Vector3.new(4.2, 3.6, 1.8), at(0, 1.8, 0.1), pal.Wood, M("Wood"))
    for _, y in ipairs({0.75, 1.85, 2.95}) do
        piece(p, b, "Drawer", Vector3.new(4, 0.95, 0.05), at(0, y, -0.82), Shade(pal.Wood, 1.15), M("Wood"))
    end
    local mirror = piece(p, b, "Mirror", Vector3.new(3, 2.2, 0.1), at(0, 4.9, 0.8), Color3.fromRGB(150, 160, 166), M("Glass"))
    mirror.Reflectance = 0.35
    piece(p, b, "Photo", Vector3.new(0.6, 0.8, 0.1), at(-1.4, 4, 0.2) * turn(rng, 0.4), Color3.fromRGB(60, 50, 40), M("Wood"))
end}

FURNITURE.TVStand = {Width = 4, Depth = 2, Build = function(p, b, pal)
    solid(p, b, "Stand", Vector3.new(3.8, 1.8, 1.8), at(0, 0.9, 0.1), pal.Wood, M("Wood"))
    solid(p, b, "TV", Vector3.new(2.6, 2.2, 2), at(0, 2.9, 0.1), Color3.fromRGB(40, 38, 36), M("Plastic"))
    local screen = piece(p, b, "Screen", Vector3.new(2, 1.6, 0.05), at(0, 2.95, -0.92), Color3.fromRGB(20, 24, 26), M("Glass"))
    screen.Reflectance = 0.2
    piece(p, b, "Antenna", Vector3.new(0.06, 1.2, 0.06), at(0.4, 4.5, 0.3) * CFrame.Angles(0, 0, 0.4), pal.Metal, M("Metal"))
end}

FURNITURE.SpecimenTank = {Width = 3.4, Depth = 3.4, Build = function(p, b, pal)
    column(p, b, "TankBase", 0.8, 3.4, at(0, 0.4, 0), pal.Metal, M("Metal"), true)
    local glass = column(p, b, "TankGlass", 6.4, 3, at(0, 4, 0), Color3.fromRGB(190, 210, 206), M("Glass"), true)
    glass.Transparency = 0.65
    local fluid = column(p, b, "TankFluid", 5.6, 2.8, at(0, 3.7, 0), Color3.fromRGB(86, 110, 70), M("SmoothPlastic"))
    fluid.Transparency = 0.55
    ball(p, b, "Specimen", Vector3.new(1.7, 1.7, 1.7), at(0, 3.6, 0), Color3.fromRGB(150, 96, 92), M("SmoothPlastic"))
    column(p, b, "TankCap", 0.6, 3.3, at(0, 7.5, 0), pal.Metal, M("Metal"), true)
    column(p, b, "TankPipe", 5.2, 0.5, at(0.8, 10.4, 0.6), pal.Pipe, M("Metal"))
    decorLight(fluid, Color3.fromRGB(120, 170, 110), 0.5, 9)
end}

FURNITURE.OperatingTable = {Width = 3, Depth = 6.6, Build = function(p, b, pal)
    column(p, b, "Pedestal", 2.2, 1.2, at(0, 1.1, 0), pal.Metal, M("Metal"), true)
    solid(p, b, "TableTop", Vector3.new(2.6, 0.25, 6.2), at(0, 2.4, 0), pal.Metal, M("Metal"))
    piece(p, b, "Cloth", Vector3.new(2.2, 0.06, 2.6), at(0, 2.55, -0.8), Color3.fromRGB(150, 150, 140), M("Fabric"))
    piece(p, b, "Blood", Vector3.new(1.2, 0.03, 1), at(0.2, 2.58, 0.6), Color3.fromRGB(96, 20, 24), M("SmoothPlastic"))
    column(p, b, "SurgicalLamp", 0.4, 2.4, at(0, 8.6, 0), Color3.fromRGB(200, 204, 204), M("Metal"))
    piece(p, b, "LampArm", Vector3.new(0.2, 4.2, 0.2), at(0, 10.9, 0), pal.Metal, M("Metal"))
    piece(p, b, "Tray", Vector3.new(1.4, 0.1, 0.9), at(1.9, 3.2, 1.8), pal.Metal, M("Metal"))
end}

FURNITURE.GrowthMass = {Width = 5, Depth = 4, Build = function(p, b, pal, rng)
    local mass = ball(p, b, "Growth", Vector3.new(5, 4, 4), at(0, 1.2, 0.4) * turn(rng, 1), Color3.fromRGB(120, 40, 55), M("Slate"))
    mass.CanCollide = true
    ball(p, b, "Growth", Vector3.new(2.6, 2.6, 2.6), at(1.6, 2.9, 0.9), Color3.fromRGB(140, 50, 62), M("Slate"))
    local vein = piece(p, b, "Vein", Vector3.new(0.5, 9, 0.5), at(0.6, 6, 1.2) * CFrame.Angles(0.15, 0, 0.2), Color3.fromRGB(120, 30, 45), M("Neon"))
    vein.Transparency = 0.45
    piece(p, b, "Vein", Vector3.new(0.35, 7, 0.35), at(-1.2, 5, 1.4) * CFrame.Angles(-0.1, 0, -0.25), Color3.fromRGB(90, 24, 36), M("SmoothPlastic"))
end}

FURNITURE.Boiler = {Width = 4.4, Depth = 4, Build = function(p, b, pal)
    solid(p, b, "BoilerBase", Vector3.new(4.2, 0.4, 3.8), at(0, 0.2, 0), pal.Metal, M("Metal"))
    column(p, b, "BoilerBody", 6.5, 3.8, at(0, 3.65, 0), pal.Pipe, M("CorrodedMetal"), true)
    column(p, b, "Flue", 6.1, 0.9, at(0, 9.95, 0.5), Color3.fromRGB(50, 50, 52), M("Metal"))
    PropKit.Cylinder(p, "Gauge", 0.12, 0.8, b * at(0.8, 5.4, -1.95) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(230, 226, 210), M("SmoothPlastic"))
    piece(p, b, "FireDoor", Vector3.new(1.2, 1.1, 0.12), at(0, 1.6, -1.92), Color3.fromRGB(30, 28, 26), M("Metal"))
end}

-- Objetos chicos, al costado de las aberturas -----------------------------------------

FURNITURE.Extinguisher = {Width = 1, Depth = 0.8, Small = true, Build = function(p, b)
    column(p, b, "Extinguisher", 1.6, 0.6, at(0, 1.6, 0.05), Color3.fromRGB(170, 30, 30), M("Metal"))
    piece(p, b, "Hose", Vector3.new(0.1, 0.8, 0.1), at(0.3, 1.8, -0.2), BLACK, M("Rubber"))
    piece(p, b, "Sign", Vector3.new(0.8, 0.8, 0.05), at(0, 3.2, 0.38), Color3.fromRGB(170, 34, 34), M("SmoothPlastic"))
end}

FURNITURE.TrashBin = {Width = 1.4, Depth = 1.4, Small = true, Build = function(p, b, pal, rng)
    if rng:Chance(0.35) then
        PropKit.Cylinder(p, "Bin", 1.6, 1.2, b * at(0, 0.6, -0.2) * turn(rng, 1), pal.Metal, M("Metal"))
        ball(p, b, "Paper", Vector3.new(0.5, 0.5, 0.5), at(0.3, 0.25, -1.3), PAPER, M("SmoothPlastic"))
    else
        column(p, b, "Bin", 1.6, 1.2, at(0, 0.8, 0), pal.Metal, M("Metal"))
        ball(p, b, "Paper", Vector3.new(0.5, 0.5, 0.5), at(0.2, 1.7, 0), PAPER, M("SmoothPlastic"))
    end
end}

FURNITURE.Plant = {Width = 1.6, Depth = 1.6, Small = true, Build = function(p, b)
    column(p, b, "Pot", 1.2, 1.2, at(0, 0.6, 0), Color3.fromRGB(128, 74, 54), M("Slate"))
    ball(p, b, "Leaves", Vector3.new(1.8, 2.2, 1.8), at(0, 2.2, 0), Color3.fromRGB(64, 70, 40), M("Grass"))
end}

FURNITURE.WaterCooler = {Width = 1.4, Depth = 1.4, Small = true, Build = function(p, b)
    solid(p, b, "Cooler", Vector3.new(1.2, 3, 1.2), at(0, 1.5, 0), Color3.fromRGB(220, 220, 214), M("Plastic"))
    local bottle = column(p, b, "Bottle", 1.4, 1, at(0, 3.7, 0), Color3.fromRGB(150, 190, 210), M("Glass"))
    bottle.Transparency = 0.4
end}

RoomDecor.Furniture = FURNITURE

-- Muebles por tipo de sala. Large va contra paredes cerradas; Small, junto a las aberturas.
RoomDecor.RoomTypes = {
    Maintenance = {Large = {"Workbench", "ElectricalPanel", "Shelf"}, Small = {"Extinguisher", "TrashBin"}},
    Storage = {Large = {"Shelf", "CrateStack", "BarrelGroup"}, Small = {"TrashBin", "Extinguisher"}},
    PumpRoom = {Large = {"Boiler", "BarrelGroup", "ElectricalPanel"}, Small = {"Extinguisher"}},
    Office = {Large = {"Desk", "FilingCabinet", "Bookcase", "Desk"}, Small = {"Plant", "TrashBin", "WaterCooler"}},
    Consultation = {Large = {"HospitalBed", "FilingCabinet", "Desk"}, Small = {"Wheelchair", "TrashBin"}},
    Waiting = {Large = {"Sofa", "Bookcase", "Sofa"}, Small = {"Plant", "WaterCooler"}},
    Records = {Large = {"FilingCabinet", "Bookcase", "FilingCabinet", "Desk"}, Small = {"TrashBin", "Extinguisher"}},
    Lab = {Large = {"LabTable", "SpecimenTank", "Shelf"}, Small = {"Extinguisher", "TrashBin"}},
    Ward = {Large = {"HospitalBed", "HospitalBed", "FilingCabinet"}, Small = {"Wheelchair", "TrashBin"}},
    Specimen = {Large = {"SpecimenTank", "LabTable", "SpecimenTank"}, Small = {"Extinguisher"}},
    Nest = {Large = {"GrowthMass", "OperatingTable", "GrowthMass"}, Small = {"TrashBin"}},
    Stacks = {Large = {"Bookcase", "Shelf", "Bookcase"}, Small = {"TrashBin"}},
    ServerRoom = {Large = {"ServerRack", "ServerRack", "ElectricalPanel"}, Small = {"Extinguisher"}},
    Vault = {Large = {"FilingCabinet", "Shelf", "CrateStack", "ServerRack"}, Small = {"TrashBin", "Extinguisher"}},
    Bedroom = {Large = {"ChildBed", "Dresser", "Bookcase"}, Small = {"Plant", "TrashBin"}},
    Living = {Large = {"Sofa", "TVStand", "Bookcase"}, Small = {"Plant"}},
    Kitchen = {Large = {"KitchenCounter", "Dresser"}, Small = {"TrashBin"}},
    Nursery = {Large = {"ChildBed", "Dresser", "ChildBed"}, Small = {"Plant"}},
}

-- Utilería de rincón (rincones libres que no usó el plan). `base` mira a la sala.
local CORNER = {}

function CORNER.Crate(p, b, pal, rng)
    solid(p, b, "Crate", Vector3.new(4, 3, 4), at(0, 1.5, 0) * turn(rng, 0.2), pal.Wood, M("WoodPlanks"))
    solid(p, b, "CrateSmall", Vector3.new(2.5, 2, 2.5), at(0.4, 4, 0.2) * turn(rng, 0.6), Shade(pal.Wood, 0.85), M("WoodPlanks"))
end

function CORNER.Barrel(p, b, pal, rng)
    column(p, b, "Barrel", 3.1, 2.4, at(0, 1.55, 0.3), Color3.fromRGB(70, 50, 42), M("CorrodedMetal"), true)
    if rng:Chance(0.5) then
        PropKit.Cylinder(p, "FallenBarrel", 3.1, 2.4, b * at(0.4, 1.2, -2.4) * CFrame.Angles(0, 0.4, 0), Shade(pal.Pipe, 0.9), M("CorrodedMetal"), true)
    end
end

function CORNER.CornerPipe(p, b, pal)
    column(p, b, "Pipe", 13, 1.2, at(0, 6.5, 1), pal.Pipe, M("CorrodedMetal"), true)
    for _, y in ipairs({1.5, 7.5}) do
        column(p, b, "PipeFlange", 0.35, 1.8, at(0, y, 1), Shade(pal.Pipe, 0.8), M("Metal"))
    end
    PropKit.Cylinder(p, "PipeValve", 0.15, 1.3, b * at(0, 4.5, 0.2) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(150, 40, 34), M("Metal"))
end
CORNER.Pipe = CORNER.CornerPipe

function CORNER.Cable(p, b, pal)
    for _, x in ipairs({-0.9, 0.9}) do
        PropKit.Cylinder(p, "SpoolSide", 0.25, 3, b * at(x, 1.5, 0), pal.Wood, M("WoodPlanks"), true)
    end
    PropKit.Cylinder(p, "SpoolCable", 1.6, 2.2, b * at(0, 1.5, 0), BLACK, M("Rubber"))
end

function CORNER.Desk(p, b, pal, rng)
    FURNITURE.Desk.Build(p, b * at(0, 0, -0.6), pal, rng)
end

function CORNER.Cabinet(p, b, pal, rng)
    for _, x in ipairs({-1.05, 1.05}) do
        FURNITURE.FilingCabinet.Build(p, b * at(x, 0, 0), pal, rng)
    end
end

function CORNER.Growth(p, b, pal, rng)
    FURNITURE.GrowthMass.Build(p, b, pal, rng)
end

function CORNER.Tank(p, b, pal, rng)
    FURNITURE.SpecimenTank.Build(p, b, pal, rng)
end

function CORNER.Plant(p, b, pal, rng)
    FURNITURE.Plant.Build(p, b, pal, rng)
end

function CORNER.Table(p, b, pal, rng)
    solid(p, b, "TableTop", Vector3.new(4, 0.3, 3), at(0, 2.6, 0), pal.Wood, M("Wood"))
    for _, side in ipairs({-1, 1}) do
        solid(p, b, "TableLeg", Vector3.new(0.3, 2.45, 2.6), at(side * 1.7, 1.23, 0), Shade(pal.Wood, 0.85), M("Wood"))
    end
    piece(p, b, "Cloth", Vector3.new(2.6, 0.05, 1.8), at(0, 2.78, 0) * turn(rng, 0.3), Color3.fromRGB(200, 190, 170), M("Fabric"))
    CORNER.Chair(p, b * at(0, 0, -2.4) * CFrame.Angles(0, math.pi, 0), pal, rng)
end

function CORNER.Chair(p, b, pal, rng)
    local frame = b * turn(rng, 0.4)
    if rng:Chance(0.35) then
        frame = frame * at(0, 0.9, 0) * CFrame.Angles(math.rad(-85), 0, 0) * at(0, -0.9, 0)
    end
    solid(p, frame, "Seat", Vector3.new(2, 0.3, 2), at(0, 1.8, 0), pal.Wood, M("Wood"))
    piece(p, frame, "Legs", Vector3.new(1.8, 1.65, 1.8), at(0, 0.83, 0), Shade(pal.Wood, 0.8), M("Wood"), {Transparency = 0.55})
    piece(p, frame, "Backrest", Vector3.new(2, 2.4, 0.3), at(0, 3.15, 0.85), pal.Wood, M("Wood"))
end

RoomDecor.Corner = CORNER

-- Techo ------------------------------------------------------------------------------

local function alongAxis(center, alongX, offset, y)
    if alongX then
        return CFrame.new(center + Vector3.new(0, y, offset))
    end
    return CFrame.new(center + Vector3.new(offset, y, 0)) * CFrame.Angles(0, math.rad(90), 0)
end

local CEILING = {}

function CEILING.Pipes(parent, center, palette, rng, narrow)
    local alongX = rng:Chance(0.5)
    local first = narrow and 2.5 or rng:Int(6, 10)
    local second = narrow and -2.5 or -rng:Int(6, 10)
    PropKit.Cylinder(parent, "CeilingPipe", 38, 1.1, alongAxis(center, alongX, first, 11.9), palette.Pipe, M("CorrodedMetal"))
    PropKit.Cylinder(parent, "CeilingPipe", 38, 0.7, alongAxis(center, alongX, second, 12.2), Shade(palette.Metal, 0.8), M("Metal"))
    for _, step in ipairs({-9, 9}) do
        Part(parent, "Hanger", Vector3.new(0.15, 1.2, 0.15), alongAxis(center, alongX, first, 12.5) * at(step, 0, 0), palette.Metal, M("Metal"))
    end
end

function CEILING.Grid(parent, center, palette, rng, narrow, theme)
    if narrow then
        return
    end
    for _, offset in ipairs({-10, 10}) do
        Part(parent, "TBar", Vector3.new(38, 0.12, 0.25), CFrame.new(center + Vector3.new(0, 12.94, offset)), palette.Metal, M("Metal"))
        Part(parent, "TBar", Vector3.new(0.25, 0.12, 38), CFrame.new(center + Vector3.new(offset, 12.94, 0)), palette.Metal, M("Metal"))
    end
    -- Placa caída: queda el hueco negro arriba y la placa rota en el piso.
    if rng:Chance(0.4) then
        local x = rng:Pick({-15, 15})
        local z = rng:Pick({-5, 5})
        Part(parent, "MissingTile", Vector3.new(4, 0.05, 4), CFrame.new(center + Vector3.new(x, 12.97, z)), BLACK, M("SmoothPlastic"))
        Part(parent, "FallenTile", Vector3.new(3.9, 0.15, 3.9), CFrame.new(center + Vector3.new(x * 0.7, 0.3, z + 2)) * CFrame.Angles(0.12, rng:Float() * 3, 0.05), theme.Ceiling, M("Plaster"))
    end
end

function CEILING.Veins(parent, center, palette, rng)
    for _ = 1, 2 do
        local origin = center + Vector3.new(rng:Int(-8, 8), 12.6, rng:Int(-8, 8))
        PropKit.Cylinder(parent, "CeilingVein", rng:Int(16, 28), 0.5 + rng:Float() * 0.5, CFrame.new(origin) * CFrame.Angles(0, rng:Float() * math.pi, 0), palette.Pipe, M("Slate"))
    end
    Part(parent, "Drip", Vector3.new(0.9, 1.4, 0.9), CFrame.new(center + Vector3.new(rng:Int(-10, 10), 12.4, rng:Int(-10, 10))), Color3.fromRGB(110, 36, 46), M("Slate"), BALL)
end

function CEILING.Trays(parent, center, palette, rng, narrow)
    local alongX = rng:Chance(0.5)
    local offset = narrow and 0 or rng:Int(-8, 8)
    Part(parent, "CableTray", Vector3.new(38, 0.15, 1.6), alongAxis(center, alongX, offset, 11.6), palette.Metal, M("Metal"))
    Part(parent, "Cables", Vector3.new(38, 0.35, 1.1), alongAxis(center, alongX, offset, 11.85), BLACK, M("Rubber"))
    for _, step in ipairs({-9, 9}) do
        Part(parent, "Hanger", Vector3.new(0.12, 1.2, 0.12), alongAxis(center, alongX, offset, 12.4) * at(step, 0, 0), palette.Metal, M("Metal"))
    end
end

function CEILING.Beams(parent, center, palette, rng, narrow)
    local alongX = rng:Chance(0.5)
    for _, offset in ipairs(narrow and {0} or {-9, 9}) do
        Part(parent, "Beam", Vector3.new(38, 0.9, 0.8), alongAxis(center, alongX, offset, 12.55), palette.Wood, M("WoodPlanks"))
    end
end

RoomDecor.Ceiling = CEILING

-- Luminarias -----------------------------------------------------------------------
-- Cada una devuelve la pieza que lleva la PointLight (etiquetada NocturnaLight).

local FIXTURES = {}

function FIXTURES.Cage(parent, top, palette)
    PropKit.Column(parent, "LampBase", 0.2, 1.2, CFrame.new(top + Vector3.new(0, -0.1, 0)), palette.Metal, M("Metal"))
    local cage = PropKit.Column(parent, "LampCage", 0.9, 1.15, CFrame.new(top + Vector3.new(0, -0.65, 0)), BLACK, M("Metal"))
    cage.Transparency = 0.7
    Part(parent, "Conduit", Vector3.new(0.15, 0.15, 19), CFrame.new(top + Vector3.new(0, -0.08, 9.5)), palette.Metal, M("Metal"))
    return Part(parent, "CeilingLight", Vector3.new(0.7, 0.7, 0.7), CFrame.new(top + Vector3.new(0, -0.7, 0)), Color3.new(1, 1, 1), M("Neon"), BALL)
end

function FIXTURES.Panel(parent, top, palette)
    Part(parent, "LampHousing", Vector3.new(6, 0.25, 2.2), CFrame.new(top + Vector3.new(0, -0.13, 0)), palette.Metal, M("Metal"))
    return Part(parent, "CeilingLight", Vector3.new(5.6, 0.1, 1.8), CFrame.new(top + Vector3.new(0, -0.3, 0)), Color3.new(1, 1, 1), M("Neon"))
end

function FIXTURES.Surgical(parent, top, palette)
    PropKit.Column(parent, "LampHousing", 0.4, 3.2, CFrame.new(top + Vector3.new(0, -0.4, 0)), palette.Metal, M("Metal"))
    return PropKit.Column(parent, "CeilingLight", 0.1, 2.6, CFrame.new(top + Vector3.new(0, -0.62, 0)), Color3.new(1, 1, 1), M("Neon"))
end

function FIXTURES.Pendant(parent, top)
    Part(parent, "LampCable", Vector3.new(0.08, 2.2, 0.08), CFrame.new(top + Vector3.new(0, -1.1, 0)), BLACK, M("Rubber"))
    PropKit.Column(parent, "LampShade", 0.8, 2.2, CFrame.new(top + Vector3.new(0, -2.4, 0)), Color3.fromRGB(44, 48, 54), M("Metal"))
    return Part(parent, "CeilingLight", Vector3.new(0.6, 0.6, 0.6), CFrame.new(top + Vector3.new(0, -2.85, 0)), Color3.new(1, 1, 1), M("Neon"), BALL)
end

function FIXTURES.Lamp(parent, top, palette)
    PropKit.Column(parent, "CeilingRose", 0.15, 0.8, CFrame.new(top + Vector3.new(0, -0.08, 0)), palette.Paint, M("Plastic"))
    Part(parent, "LampCable", Vector3.new(0.06, 1.6, 0.06), CFrame.new(top + Vector3.new(0, -0.9, 0)), BLACK, M("Rubber"))
    local shade = PropKit.Column(parent, "LampShade", 1, 1.8, CFrame.new(top + Vector3.new(0, -2.1, 0)), Color3.fromRGB(214, 180, 130), M("Fabric"))
    shade.Transparency = 0.15
    return Part(parent, "CeilingLight", Vector3.new(0.5, 0.5, 0.5), CFrame.new(top + Vector3.new(0, -2.3, 0)), Color3.new(1, 1, 1), M("Neon"), BALL)
end

RoomDecor.Fixtures = FIXTURES

-- `top` es el punto del techo sobre el centro de la celda.
function RoomDecor.Fixture(parent, style, top, palette)
    local builder = FIXTURES[style] or FIXTURES.Panel
    return builder(parent, top, palette)
end

-- Terminaciones de pared ---------------------------------------------------------------
-- Una sola pieza más gruesa que la pared cubre las dos caras a la vez.

-- `cframe` es el centro de la pared a nivel del piso; `length` corre a lo largo de su X.
function RoomDecor.WallTrim(parent, style, cframe, length, thickness, theme, palette)
    local trimMaterial = M(theme.TrimMaterial or "Wood")
    if style == "Band" then
        Part(parent, "GrimeBand", Vector3.new(length, 2.4, thickness + 0.1), cframe * at(0, 1.2, 0), Shade(theme.Wall, 0.55), M(theme.WallMaterial))
        return 1
    elseif style == "Kick" then
        Part(parent, "Kickplate", Vector3.new(length, 1.4, thickness + 0.16), cframe * at(0, 0.7, 0), palette.Trim, trimMaterial)
        Part(parent, "KickRail", Vector3.new(length, 0.2, thickness + 0.22), cframe * at(0, 1.45, 0), Shade(palette.Trim, 1.2), M("Metal"))
        return 2
    end
    Part(parent, "Wainscot", Vector3.new(length, 3.6, thickness + 0.12), cframe * at(0, 1.8, 0), palette.WallLower, trimMaterial)
    Part(parent, "ChairRail", Vector3.new(length, 0.25, thickness + 0.3), cframe * at(0, 3.7, 0), palette.Trim, trimMaterial)
    Part(parent, "Baseboard", Vector3.new(length, 0.6, thickness + 0.26), cframe * at(0, 0.3, 0), Shade(palette.Trim, 0.8), trimMaterial)
    return 3
end

-- Marco de una abertura de `width` x `height` en una pared centrada en `cframe`.
function RoomDecor.DoorFrame(parent, cframe, width, height, thickness, theme, palette)
    local material = M(theme.TrimMaterial or "Wood")
    for _, side in ipairs({-1, 1}) do
        Part(parent, "Jamb", Vector3.new(0.5, height, thickness + 0.5), cframe * at(side * (width / 2 + 0.25), height / 2, 0), palette.Trim, material)
    end
    Part(parent, "Lintel", Vector3.new(width + 1, 0.5, thickness + 0.5), cframe * at(0, height + 0.25, 0), palette.Trim, material)
end

-- Suciedad: manchas, charcos, papeles, sangre y chorreaduras -------------------------------

function RoomDecor.Grime(parent, center, theme, palette, rng, wallFaces)
    local function spot()
        return center + Vector3.new(rng:Int(-15, 15), 0, rng:Int(-15, 15))
    end

    for _ = 1, 2 do
        local stain = PropKit.Column(parent, "Stain", 0.04, 3 + rng:Float() * 4, CFrame.new(spot() + Vector3.new(0, 0.02, 0)), palette.Grime, M("SmoothPlastic"))
        stain.Transparency = 0.35 + rng:Float() * 0.25
    end
    if theme.Puddles then
        local puddle = PropKit.Column(parent, "Puddle", 0.04, 4 + rng:Float() * 5, CFrame.new(spot() + Vector3.new(0, 0.03, 0)), Color3.fromRGB(20, 24, 26), M("Glass"))
        puddle.Reflectance = 0.3
        puddle.Transparency = 0.15
    end
    if theme.Papers then
        for _ = 1, 2 do
            Part(parent, "Paper", Vector3.new(0.9, 0.02, 1.2), CFrame.new(spot() + Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, rng:Float() * 3, 0), PAPER, M("SmoothPlastic"))
        end
    end
    if theme.Blood then
        local smear = Part(parent, "Blood", Vector3.new(2.6, 0.03, 0.9), CFrame.new(spot() + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, rng:Float() * 3, 0), Color3.fromRGB(90, 16, 22), M("SmoothPlastic"))
        smear.Transparency = 0.2
    end
    -- Chorreadura de humedad que baja del techo por una pared cerrada.
    if #wallFaces > 0 then
        local face = rng:Pick(wallFaces)
        local streak = Part(parent, "Streak", Vector3.new(2.2, 5, 0.05), face * at(rng:Int(-6, 6), 10.3, -0.04), palette.Grime, M("SmoothPlastic"))
        streak.Transparency = 0.45
    end
end

-- Pasadizo secreto ------------------------------------------------------------------------
-- Boca de servicio baja en la pared, con una manga de chapa a cada lado, la rejilla
-- arrancada en el piso y tablas mal clavadas. Mide lo justo para pasar caminando.

RoomDecor.PassageWidth = 4.6
RoomDecor.PassageHeight = 6.4

function RoomDecor.Passage(parent, cframe, thickness, palette)
    local width, height = RoomDecor.PassageWidth, RoomDecor.PassageHeight
    local sleeve = thickness + 3.2
    local metal = Shade(palette.Metal, 0.75)
    Part(parent, "PassageTop", Vector3.new(width + 0.6, 0.3, sleeve), cframe * at(0, height + 0.15, 0), metal, M("CorrodedMetal"), SOLID)
    for _, side in ipairs({-1, 1}) do
        Part(parent, "PassageSide", Vector3.new(0.3, height, sleeve), cframe * at(side * (width / 2 + 0.15), height / 2, 0), metal, M("CorrodedMetal"), SOLID)
    end
    Part(parent, "LooseGrate", Vector3.new(width - 0.4, 0.12, 3), cframe * at(1.2, 0.08, -(sleeve / 2 + 1.6)) * CFrame.Angles(0, 0.5, 0.06), palette.Metal, M("DiamondPlate"))
    Part(parent, "Plank", Vector3.new(width + 1.4, 0.5, 0.15), cframe * at(0, height - 0.6, -(sleeve / 2 + 0.1)) * CFrame.Angles(0, 0, 0.18), palette.Wood, M("WoodPlanks"))
    Part(parent, "Plank", Vector3.new(width + 1, 0.45, 0.15), cframe * at(0.3, height - 1.5, sleeve / 2 + 0.1) * CFrame.Angles(0, 0, -0.22), Shade(palette.Wood, 0.85), M("WoodPlanks"))
end

return RoomDecor
